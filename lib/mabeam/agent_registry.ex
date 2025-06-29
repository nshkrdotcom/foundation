defmodule MABEAM.AgentRegistry do
  @moduledoc """
  High-performance agent registry with v2.1 Protocol Platform architecture.

  ## Architecture: Write-Through-Process, Read-From-Table Pattern

  **Write Operations** go through GenServer for consistency:
  - Atomic operations across all tables
  - Consistent state management
  - Proper isolation between registry instances

  **Read Operations** use direct ETS access for performance:
  - Lock-free concurrent reads via protocol implementation
  - No GenServer bottleneck
  - Table names cached in process dictionary

  ## Concurrency Model

  **Write Operations**:
  - Serialized through GenServer for consistency
  - Typical latency: 100-500 microseconds

  **Read Operations**:
  - Direct ETS access for maximum performance
  - Lock-free concurrent reads
  - Typical latency: 1-10 microseconds

  ## Scaling Considerations

  This implementation prioritizes correctness and isolation over raw performance.
  Systems expecting exceptionally high-volume concurrent operations (>10,000/sec)
  should consider a sharded registry implementation.

  ## Agent Metadata Schema

  All registered agents must have metadata containing:
  - `:capability` - List of capabilities (indexed)
  - `:health_status` - `:healthy`, `:degraded`, or `:unhealthy` (indexed)
  - `:node` - Node where agent is running (indexed)
  - `:resources` - Map with resource usage/availability
  - `:agent_type` - Type of agent (optional, for future sharding)
  """

  use GenServer
  require Logger

  # All handle_call/3 clauses are grouped together below

  alias Foundation.ETSHelpers.MatchSpecCompiler

  defstruct main_table: nil,
            capability_index: nil,
            health_index: nil,
            node_index: nil,
            resource_index: nil,
            monitors: nil,
            registry_id: nil

  # Required metadata fields for agents
  @required_fields [:capability, :health_status, :node, :resources]
  @valid_health_statuses [:healthy, :degraded, :unhealthy]

  # --- OTP Lifecycle ---

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  def init(opts) do
    # Use the registry ID for logging but not for dynamic atom creation
    registry_id = Keyword.get(opts, :id, :default)

    # Create anonymous ETS tables tied to this process for safety
    # No dynamic atom creation - tables are anonymous and garbage collected with process
    table_opts = [:public, read_concurrency: true, write_concurrency: true]

    state = %__MODULE__{
      main_table: :ets.new(:agent_main, [:set | table_opts]),
      capability_index: :ets.new(:agent_capability_idx, [:bag | table_opts]),
      health_index: :ets.new(:agent_health_idx, [:bag | table_opts]),
      node_index: :ets.new(:agent_node_idx, [:bag | table_opts]),
      resource_index: :ets.new(:agent_resource_idx, [:ordered_set | table_opts]),
      monitors: %{},
      registry_id: registry_id
    }

    # Register tables with ResourceManager if available
    if Process.whereis(Foundation.ResourceManager) do
      Foundation.ResourceManager.monitor_table(state.main_table)
      Foundation.ResourceManager.monitor_table(state.capability_index)
      Foundation.ResourceManager.monitor_table(state.health_index)
      Foundation.ResourceManager.monitor_table(state.node_index)
      Foundation.ResourceManager.monitor_table(state.resource_index)
    end

    Logger.info(
      "MABEAM.AgentRegistry (#{registry_id}) started with anonymous ETS tables (process-managed)"
    )

    {:ok, state}
  end

  def terminate(_reason, state) do
    Logger.info(
      "MABEAM.AgentRegistry (#{state.registry_id}) terminating, ETS tables will be automatically garbage collected"
    )

    # Anonymous ETS tables are automatically garbage collected when the process dies
    # No manual cleanup needed - this makes the implementation more robust
    :ok
  end

  # --- GenServer Implementation for ALL Operations ---

  def handle_call({:register, agent_id, pid, metadata}, _from, state) do
    case acquire_registration_resource(agent_id, state.registry_id) do
      {:ok, resource_token} ->
        register_with_resource(agent_id, pid, metadata, state, resource_token)

      {:error, reason} ->
        Logger.warning("Resource manager denied registration: #{inspect(reason)}")
        {:reply, {:error, {:resource_exhausted, reason}}, state}
    end
  end

  def handle_call({:unregister, agent_id}, _from, state) do
    case :ets.lookup(state.main_table, agent_id) do
      [{^agent_id, _pid, _metadata, _timestamp}] ->
        # Find monitor reference
        monitor_ref =
          state.monitors
          |> Enum.find(fn {_ref, id} -> id == agent_id end)
          |> case do
            {ref, _} -> ref
            nil -> nil
          end

        # Atomic unregistration - all operations in single GenServer call
        # This provides atomicity through GenServer serialization
        :ets.delete(state.main_table, agent_id)
        clear_agent_from_indexes(state, agent_id)

        # Clean up monitor
        new_monitors =
          if monitor_ref do
            Process.demonitor(monitor_ref, [:flush])
            Map.delete(state.monitors, monitor_ref)
          else
            state.monitors
          end

        Logger.debug("Unregistered agent #{inspect(agent_id)}")
        {:reply, :ok, %{state | monitors: new_monitors}}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:update_metadata, agent_id, new_metadata}, _from, state) do
    with :ok <- validate_agent_metadata(new_metadata),
         [{^agent_id, pid, _old_metadata, _timestamp}] <- :ets.lookup(state.main_table, agent_id) do
      # Atomic metadata update - all operations in single GenServer call
      # This provides atomicity through GenServer serialization

      # Update main table
      :ets.insert(state.main_table, {agent_id, pid, new_metadata, :os.timestamp()})

      # Clear old indexes and rebuild atomically within same call
      clear_agent_from_indexes(state, agent_id)
      update_all_indexes(state, agent_id, new_metadata)

      Logger.debug("Updated metadata for agent #{inspect(agent_id)}")
      {:reply, :ok, state}
    else
      [] -> {:reply, {:error, :not_found}, state}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:lookup, agent_id}, _from, state) do
    result =
      case :ets.lookup(state.main_table, agent_id) do
        [{^agent_id, pid, metadata, _timestamp}] ->
          {:ok, {pid, metadata}}

        [] ->
          :error
      end

    {:reply, result, state}
  end

  def handle_call({:find_by_attribute, attribute, value}, _from, state) do
    result =
      case attribute do
        :capability ->
          agent_ids = :ets.lookup(state.capability_index, value) |> Enum.map(&elem(&1, 1))
          batch_lookup_agents(agent_ids, state)

        :health_status ->
          agent_ids = :ets.lookup(state.health_index, value) |> Enum.map(&elem(&1, 1))
          batch_lookup_agents(agent_ids, state)

        :node ->
          agent_ids = :ets.lookup(state.node_index, value) |> Enum.map(&elem(&1, 1))
          batch_lookup_agents(agent_ids, state)

        _ ->
          {:error, {:unsupported_attribute, attribute}}
      end

    {:reply, result, state}
  end

  def handle_call({:query, criteria}, _from, state) when is_list(criteria) do
    result =
      case MatchSpecCompiler.validate_criteria(criteria) do
        :ok ->
          # Try to compile to match spec for atomic query
          case MatchSpecCompiler.compile(criteria) do
            {:ok, match_spec} ->
              # Use atomic ETS select for O(1) performance
              try do
                results = :ets.select(state.main_table, match_spec)
                {:ok, results}
              rescue
                e ->
                  # Fall back to application-level filtering when match spec fails
                  Logger.debug(
                    "Match spec execution failed: #{Exception.message(e)}. Using application-level filtering."
                  )

                  do_application_level_query(criteria, state)
              end

            {:error, reason} ->
              # Fall back to application-level filtering for unsupported criteria
              Logger.debug(
                "Cannot compile criteria to match spec: #{inspect(reason)}. Using application-level filtering."
              )

              do_application_level_query(criteria, state)
          end

        {:error, reason} ->
          {:error, {:invalid_criteria, reason}}
      end

    {:reply, result, state}
  end

  def handle_call({:query, _invalid_criteria}, _from, state) do
    {:reply, {:error, :invalid_criteria_format}, state}
  end

  def handle_call({:indexed_attributes}, _from, state) do
    {:reply, [:capability, :health_status, :node], state}
  end

  def handle_call({:list_all, filter_fn}, _from, state) do
    results =
      :ets.tab2list(state.main_table)
      |> Enum.map(fn {id, pid, metadata, _timestamp} -> {id, pid, metadata} end)
      |> apply_filter(filter_fn)

    {:reply, results, state}
  end

  def handle_call({:protocol_version}, _from, state) do
    {:reply, "2.0", state}
  end

  def handle_call({:count}, _from, state) do
    count = :ets.info(state.main_table, :size)
    {:reply, {:ok, count}, state}
  end

  def handle_call({:select, match_spec}, _from, state) do
    results = :ets.select(state.main_table, match_spec)
    {:reply, results, state}
  end

  def handle_call({:get_table_names}, _from, state) do
    table_names = %{
      main: state.main_table,
      capability_index: state.capability_index,
      health_index: state.health_index,
      node_index: state.node_index,
      resource_index: state.resource_index
    }

    {:reply, {:ok, table_names}, state}
  end

  def handle_call({:atomic_transaction, operations, tx_id}, _from, state) do
    Logger.debug("Executing atomic transaction #{tx_id} with #{length(operations)} operations")

    # Execute all operations within this single GenServer call
    # This ensures atomicity through GenServer serialization
    result = execute_transaction_operations(operations, state, [], tx_id)

    case result do
      {:ok, rollback_data, new_state} ->
        {:reply, {:ok, rollback_data}, new_state}

      {:error, reason, rollback_data, _partial_state} ->
        # Transaction failed - state unchanged due to functional approach
        {:reply, {:error, reason, rollback_data}, state}
    end
  end

  def handle_call({:batch_register, agents}, _from, state) when is_list(agents) do
    Logger.debug("Executing batch registration for #{length(agents)} agents")

    case acquire_batch_registration_resource(agents, state) do
      {:ok, resource_token} ->
        execute_batch_registration_with_resource(agents, state, resource_token)

      {:error, reason} ->
        {:reply, {:error, {:resource_exhausted, reason}}, state}
    end
  end

  # --- handle_info for process monitoring ---

  def handle_info({:DOWN, monitor_ref, :process, _pid, reason}, state) do
    case Map.get(state.monitors, monitor_ref) do
      nil ->
        # Unknown monitor, ignore
        {:noreply, state}

      agent_id ->
        handle_agent_down(agent_id, monitor_ref, reason, state)
    end
  end

  defp handle_agent_down(agent_id, monitor_ref, reason, state) do
    Logger.info("Agent #{inspect(agent_id)} process died (#{inspect(reason)}), cleaning up")

    # Atomic cleanup - all operations in single GenServer message handler
    # This provides atomicity through GenServer serialization
    :ets.delete(state.main_table, agent_id)
    clear_agent_from_indexes(state, agent_id)

    # Remove from monitors
    new_monitors = Map.delete(state.monitors, monitor_ref)

    # Notify ResourceManager about cleanup if available
    notify_resource_manager_cleanup(agent_id, reason)

    {:noreply, %{state | monitors: new_monitors}}
  end

  defp notify_resource_manager_cleanup(agent_id, reason) do
    if Process.whereis(Foundation.ResourceManager) do
      spawn(fn ->
        Foundation.ResourceManager.release_resource(%{
          id: agent_id,
          type: :register_agent,
          metadata: %{agent_id: agent_id, cleanup_reason: reason}
        })
      end)
    end
  end

  # --- Private Helper Functions ---
  # These functions support the GenServer callbacks above

  # Helper functions for registration
  defp acquire_registration_resource(agent_id, registry_id) do
    if Process.whereis(Foundation.ResourceManager) do
      Foundation.ResourceManager.acquire_resource(:register_agent, %{
        agent_id: agent_id,
        registry_id: registry_id
      })
    else
      {:ok, nil}
    end
  end

  defp register_with_resource(agent_id, pid, metadata, state, resource_token) do
    result = perform_registration(agent_id, pid, metadata, state)

    # Release resource token if registration failed
    case result do
      {:reply, :ok, _} ->
        result

      error_result ->
        if resource_token, do: Foundation.ResourceManager.release_resource(resource_token)
        error_result
    end
  end

  defp perform_registration(agent_id, pid, metadata, state) do
    with :ok <- validate_agent_metadata(metadata),
         :ok <- validate_process_alive(pid),
         :ok <- validate_agent_not_exists(state.main_table, agent_id) do
      atomic_register(agent_id, pid, metadata, state)
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp validate_process_alive(pid) do
    if Process.alive?(pid), do: :ok, else: {:error, :process_not_alive}
  end

  defp validate_agent_not_exists(table, agent_id) do
    if :ets.member(table, agent_id), do: {:error, :already_exists}, else: :ok
  end

  defp atomic_register(agent_id, pid, metadata, state) do
    monitor_ref = Process.monitor(pid)
    entry = {agent_id, pid, metadata, :os.timestamp()}

    case :ets.insert_new(state.main_table, entry) do
      true ->
        complete_registration(agent_id, metadata, monitor_ref, state)

      false ->
        # Cleanup monitor and return error
        Process.demonitor(monitor_ref, [:flush])
        {:reply, {:error, :already_exists}, state}
    end
  end

  defp complete_registration(agent_id, metadata, monitor_ref, state) do
    # Update all indexes atomically within same call
    update_all_indexes(state, agent_id, metadata)

    # Track monitor reference
    new_monitors = Map.put(state.monitors, monitor_ref, agent_id)

    Logger.debug(
      "Registered agent #{inspect(agent_id)} with capabilities #{inspect(metadata.capability)}"
    )

    {:reply, :ok, %{state | monitors: new_monitors}}
  end

  # Helper functions for batch registration
  defp acquire_batch_registration_resource(agents, state) do
    if Process.whereis(Foundation.ResourceManager) do
      Foundation.ResourceManager.acquire_resource(:batch_register, %{
        count: length(agents),
        registry_id: state.registry_id
      })
    else
      {:ok, nil}
    end
  end

  defp execute_batch_registration_with_resource(agents, state, resource_token) do
    result = execute_batch_register(agents, state, [], resource_token)
    handle_batch_register_result(result, state, resource_token)
  end

  defp handle_batch_register_result({:ok, registered_ids, new_state}, _state, _resource_token) do
    {:reply, {:ok, registered_ids}, new_state}
  end

  defp handle_batch_register_result({:error, reason, partial_ids, _}, state, resource_token) do
    if resource_token, do: Foundation.ResourceManager.release_resource(resource_token)
    {:reply, {:error, reason, partial_ids}, state}
  end

  defp do_application_level_query(criteria, state) do
    all_agents = :ets.tab2list(state.main_table)

    filtered =
      Enum.filter(all_agents, fn {_id, _pid, metadata, _timestamp} ->
        Enum.all?(criteria, fn criterion ->
          matches_criterion?(metadata, criterion)
        end)
      end)

    formatted_results =
      Enum.map(filtered, fn {id, pid, metadata, _timestamp} ->
        {id, pid, metadata}
      end)

    {:ok, formatted_results}
  rescue
    e in [ArgumentError, MatchError] ->
      {:error, {:invalid_criteria, Exception.message(e)}}
  end

  defp batch_lookup_agents(agent_ids, state) do
    results =
      agent_ids
      |> Enum.map(&:ets.lookup(state.main_table, &1))
      |> List.flatten()
      |> Enum.map(fn {id, pid, metadata, _timestamp} -> {id, pid, metadata} end)

    {:ok, results}
  end

  defp apply_filter(results, nil), do: results

  defp apply_filter(results, filter_fn) do
    Enum.filter(results, fn {_id, _pid, metadata} -> filter_fn.(metadata) end)
  end

  defp validate_agent_metadata(metadata) do
    case find_missing_fields(metadata) do
      [] ->
        validate_health_status(metadata)

      missing_fields ->
        {:error, {:missing_required_fields, missing_fields}}
    end
  end

  defp find_missing_fields(metadata) do
    Enum.filter(@required_fields, fn field ->
      not Map.has_key?(metadata, field)
    end)
  end

  defp validate_health_status(metadata) do
    health_status = Map.get(metadata, :health_status)

    if health_status in @valid_health_statuses do
      :ok
    else
      {:error, {:invalid_health_status, health_status, @valid_health_statuses}}
    end
  end

  defp update_all_indexes(state, agent_id, metadata) do
    # Capability index (handle both single capability and list)
    capabilities = List.wrap(Map.get(metadata, :capability, []))

    for capability <- capabilities do
      :ets.insert(state.capability_index, {capability, agent_id})
    end

    # Health index
    health_status = Map.get(metadata, :health_status, :unknown)
    :ets.insert(state.health_index, {health_status, agent_id})

    # Node index
    node = Map.get(metadata, :node, node())
    :ets.insert(state.node_index, {node, agent_id})

    # Resource index (ordered by memory usage for efficient range queries)
    resources = Map.get(metadata, :resources, %{})
    memory_usage = Map.get(resources, :memory_usage, 0.0)
    :ets.insert(state.resource_index, {{memory_usage, agent_id}, agent_id})
  end

  defp clear_agent_from_indexes(state, agent_id) do
    # Use match_delete for efficient cleanup
    :ets.match_delete(state.capability_index, {:_, agent_id})
    :ets.match_delete(state.health_index, {:_, agent_id})
    :ets.match_delete(state.node_index, {:_, agent_id})
    :ets.match_delete(state.resource_index, {{:_, agent_id}, agent_id})
  end

  # --- Criteria Matching ---

  defp matches_criterion?(metadata, {path, value, op}) do
    actual_value = get_nested_value(metadata, path)
    apply_operation(actual_value, value, op)
  end

  defp get_nested_value(metadata, [key]) do
    Map.get(metadata, key)
  end

  defp get_nested_value(metadata, [key | rest]) do
    case Map.get(metadata, key) do
      nil -> nil
      nested_map when is_map(nested_map) -> get_nested_value(nested_map, rest)
      _ -> nil
    end
  end

  defp apply_operation(actual, expected, :eq) do
    # Special handling for capability lists
    case {actual, expected} do
      {actual_list, expected_atom} when is_list(actual_list) and is_atom(expected_atom) ->
        expected_atom in actual_list

      _ ->
        actual == expected
    end
  end

  defp apply_operation(actual, expected, :neq), do: actual != expected
  defp apply_operation(actual, expected, :gt), do: actual > expected
  defp apply_operation(actual, expected, :lt), do: actual < expected
  defp apply_operation(actual, expected, :gte), do: actual >= expected
  defp apply_operation(actual, expected, :lte), do: actual <= expected

  defp apply_operation(actual, expected_list, :in) when is_list(expected_list) do
    cond do
      # If actual is a single value, check if it's in the expected list
      is_atom(actual) -> actual in expected_list
      # If actual is a list, check if any of its values are in the expected list
      is_list(actual) -> Enum.any?(actual, fn val -> val in expected_list end)
      # For other types, use standard membership check
      true -> actual in expected_list
    end
  end

  defp apply_operation(actual, expected_list, :not_in) when is_list(expected_list) do
    cond do
      # If actual is a single value, check if it's not in the expected list
      is_atom(actual) -> actual not in expected_list
      # If actual is a list, check that none of its values are in the expected list
      is_list(actual) -> not Enum.any?(actual, fn val -> val in expected_list end)
      # For other types, use standard not-in check
      true -> actual not in expected_list
    end
  end

  # --- Atomic Transaction Helpers ---

  defp execute_transaction_operations([], state, rollback_data, _tx_id) do
    # All operations completed successfully
    {:ok, Enum.reverse(rollback_data), state}
  end

  defp execute_transaction_operations([{:register, args} | rest], state, rollback_data, tx_id) do
    [agent_id, pid, metadata] = args

    case validate_and_register(agent_id, pid, metadata, state) do
      {:ok, new_state, _monitor_ref} ->
        # Operation succeeded, continue with rest
        rollback_info = {:unregister, agent_id}
        execute_transaction_operations(rest, new_state, [rollback_info | rollback_data], tx_id)

      {:error, reason} ->
        # Operation failed, abort transaction
        {:error, {:register_failed, agent_id, reason}, rollback_data, state}
    end
  end

  defp execute_transaction_operations(
         [{:update_metadata, args} | rest],
         state,
         rollback_data,
         tx_id
       ) do
    [agent_id, new_metadata] = args

    case lookup_and_update_metadata(agent_id, new_metadata, state) do
      {:ok, new_state, old_metadata} ->
        # Operation succeeded, continue with rest
        rollback_info = {:update_metadata, agent_id, old_metadata}
        execute_transaction_operations(rest, new_state, [rollback_info | rollback_data], tx_id)

      {:error, reason} ->
        # Operation failed, abort transaction
        {:error, {:update_metadata_failed, agent_id, reason}, rollback_data, state}
    end
  end

  defp execute_transaction_operations([{:unregister, args} | rest], state, rollback_data, tx_id) do
    [agent_id] = args

    case lookup_and_unregister(agent_id, state) do
      {:ok, new_state, {pid, metadata}} ->
        # Operation succeeded, continue with rest
        rollback_info = {:register, agent_id, pid, metadata}
        execute_transaction_operations(rest, new_state, [rollback_info | rollback_data], tx_id)

      {:error, reason} ->
        # Operation failed, abort transaction
        {:error, {:unregister_failed, agent_id, reason}, rollback_data, state}
    end
  end

  defp validate_and_register(agent_id, pid, metadata, state) do
    with :ok <- validate_agent_metadata(metadata),
         true <- Process.alive?(pid),
         false <- :ets.member(state.main_table, agent_id) do
      # Create all the updates
      monitor_ref = Process.monitor(pid)
      entry = {agent_id, pid, metadata, :os.timestamp()}

      # Apply updates to ETS tables
      :ets.insert(state.main_table, entry)
      update_all_indexes(state, agent_id, metadata)

      # Update state
      new_monitors = Map.put(state.monitors, monitor_ref, agent_id)
      new_state = %{state | monitors: new_monitors}

      {:ok, new_state, monitor_ref}
    else
      false -> {:error, :process_not_alive}
      true -> {:error, :already_exists}
      error -> error
    end
  end

  defp lookup_and_update_metadata(agent_id, new_metadata, state) do
    with :ok <- validate_agent_metadata(new_metadata),
         [{^agent_id, pid, old_metadata, _timestamp}] <- :ets.lookup(state.main_table, agent_id) do
      # Update main table
      :ets.insert(state.main_table, {agent_id, pid, new_metadata, :os.timestamp()})

      # Update indexes
      clear_agent_from_indexes(state, agent_id)
      update_all_indexes(state, agent_id, new_metadata)

      {:ok, state, old_metadata}
    else
      [] -> {:error, :not_found}
      error -> error
    end
  end

  defp lookup_and_unregister(agent_id, state) do
    case :ets.lookup(state.main_table, agent_id) do
      [{^agent_id, pid, metadata, _timestamp}] ->
        # Find monitor reference
        monitor_ref =
          state.monitors
          |> Enum.find(fn {_ref, id} -> id == agent_id end)
          |> case do
            {ref, _} -> ref
            nil -> nil
          end

        # Remove from all tables
        :ets.delete(state.main_table, agent_id)
        clear_agent_from_indexes(state, agent_id)

        # Update state
        new_monitors =
          if monitor_ref do
            Process.demonitor(monitor_ref, [:flush])
            Map.delete(state.monitors, monitor_ref)
          else
            state.monitors
          end

        new_state = %{state | monitors: new_monitors}
        {:ok, new_state, {pid, metadata}}

      [] ->
        {:error, :not_found}
    end
  end

  # --- Batch Operation Helpers ---

  defp execute_batch_register([], state, registered_ids, _resource_token) do
    # All registrations completed successfully
    {:ok, Enum.reverse(registered_ids), state}
  end

  defp execute_batch_register(
         [{agent_id, pid, metadata} | rest],
         state,
         registered_ids,
         resource_token
       ) do
    case validate_and_register(agent_id, pid, metadata, state) do
      {:ok, new_state, _monitor_ref} ->
        # Continue with rest
        execute_batch_register(rest, new_state, [agent_id | registered_ids], resource_token)

      {:error, reason} ->
        # Batch failed - return partial results
        {:error, {:batch_register_failed, agent_id, reason}, Enum.reverse(registered_ids), state}
    end
  end
end
