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
  alias Foundation.Telemetry

  # All handle_call/3 clauses are grouped together below

  alias Foundation.ETSHelpers.MatchSpecCompiler
  alias MABEAM.AgentRegistry.{Validator, IndexManager, QueryEngine}

  defstruct main_table: nil,
            capability_index: nil,
            health_index: nil,
            node_index: nil,
            resource_index: nil,
            monitors: nil,
            registry_id: nil

  # Delegated to Validator module

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

    # Create tables using IndexManager
    tables = IndexManager.create_index_tables(registry_id)

    state =
      struct!(
        __MODULE__,
        Map.merge(tables, %{
          monitors: %{},
          registry_id: registry_id
        })
      )

    # Register tables with ResourceManager
    IndexManager.register_tables_with_resource_manager(tables)

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
    start_time = System.monotonic_time()

    case :ets.lookup(state.main_table, agent_id) do
      [{^agent_id, _pid, metadata, _timestamp}] ->
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
        IndexManager.clear_agent_from_indexes(state, agent_id)

        # Clean up monitor
        new_monitors =
          if monitor_ref do
            Process.demonitor(monitor_ref, [:flush])
            Map.delete(state.monitors, monitor_ref)
          else
            state.monitors
          end

        Telemetry.emit(
          [:foundation, :mabeam, :registry, :unregister],
          %{duration: System.monotonic_time() - start_time},
          %{
            agent_id: agent_id,
            registry_id: state.registry_id,
            capabilities: List.wrap(Map.get(metadata, :capability, [])),
            health_status: Map.get(metadata, :health_status)
          }
        )

        Logger.debug("Unregistered agent #{inspect(agent_id)}")
        {:reply, :ok, %{state | monitors: new_monitors}}

      [] ->
        Telemetry.emit(
          [:foundation, :mabeam, :registry, :unregister_failed],
          %{duration: System.monotonic_time() - start_time},
          %{
            agent_id: agent_id,
            registry_id: state.registry_id,
            reason: :not_found
          }
        )

        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:update_metadata, agent_id, new_metadata}, _from, state) do
    start_time = System.monotonic_time()

    with :ok <- Validator.validate_agent_metadata(new_metadata),
         [{^agent_id, pid, old_metadata, _timestamp}] <- :ets.lookup(state.main_table, agent_id) do
      # Atomic metadata update - all operations in single GenServer call
      # This provides atomicity through GenServer serialization

      # Update main table
      :ets.insert(state.main_table, {agent_id, pid, new_metadata, :os.timestamp()})

      # Clear old indexes and rebuild atomically within same call
      IndexManager.clear_agent_from_indexes(state, agent_id)
      IndexManager.update_all_indexes(state, agent_id, new_metadata)

      Telemetry.emit(
        [:foundation, :mabeam, :registry, :update],
        %{duration: System.monotonic_time() - start_time},
        %{
          agent_id: agent_id,
          registry_id: state.registry_id,
          old_capabilities: List.wrap(Map.get(old_metadata, :capability, [])),
          new_capabilities: List.wrap(Map.get(new_metadata, :capability, [])),
          old_health: Map.get(old_metadata, :health_status),
          new_health: Map.get(new_metadata, :health_status)
        }
      )

      Logger.debug("Updated metadata for agent #{inspect(agent_id)}")
      {:reply, :ok, state}
    else
      [] ->
        Telemetry.emit(
          [:foundation, :mabeam, :registry, :update_failed],
          %{duration: System.monotonic_time() - start_time},
          %{
            agent_id: agent_id,
            registry_id: state.registry_id,
            reason: :not_found
          }
        )

        {:reply, {:error, :not_found}, state}

      error ->
        Telemetry.emit(
          [:foundation, :mabeam, :registry, :update_failed],
          %{duration: System.monotonic_time() - start_time},
          %{
            agent_id: agent_id,
            registry_id: state.registry_id,
            reason: error
          }
        )

        {:reply, error, state}
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
    start_time = System.monotonic_time()

    result =
      case MatchSpecCompiler.validate_criteria(criteria) do
        :ok ->
          # Try to compile to match spec for atomic query
          case MatchSpecCompiler.compile(criteria) do
            {:ok, match_spec} ->
              # Use atomic ETS select for O(1) performance
              try do
                results = :ets.select(state.main_table, match_spec)
                query_result = {:ok, results}

                Telemetry.emit(
                  [:foundation, :mabeam, :registry, :query],
                  %{
                    duration: System.monotonic_time() - start_time,
                    result_count: length(results)
                  },
                  %{
                    registry_id: state.registry_id,
                    criteria_count: length(criteria),
                    query_type: :match_spec
                  }
                )

                query_result
              rescue
                e ->
                  # Fall back to application-level filtering when match spec fails
                  Logger.debug(
                    "Match spec execution failed: #{Exception.message(e)}. Using application-level filtering."
                  )

                  do_application_level_query(criteria, state, start_time)
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
    # Use streaming to avoid loading entire table
    # This is the GenServer path - Reader module provides direct access
    match_spec = [{:_, [], [:"$_"]}]
    batch_size = 100

    results =
      stream_ets_select(state.main_table, match_spec, batch_size)
      |> Stream.map(fn {id, pid, metadata, _timestamp} -> {id, pid, metadata} end)
      |> Enum.to_list()
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

    # IMPORTANT: This function provides atomicity ONLY through GenServer serialization.
    # ETS operations are NOT rolled back on failure - the caller must handle cleanup.
    # The "atomic" guarantee is that all operations run without interleaving with other
    # GenServer calls, NOT that changes are rolled back on failure.
    result = execute_transaction_operations(operations, state, [], tx_id)

    case result do
      {:ok, rollback_data, new_state} ->
        {:reply, {:ok, rollback_data}, new_state}

      {:error, reason, rollback_data, _partial_state} ->
        # Transaction failed - GenServer state unchanged, but ETS changes persist!
        # Caller must use rollback_data to manually undo changes if needed.
        Logger.warning(
          "Transaction #{tx_id} failed: #{inspect(reason)}. ETS changes NOT rolled back."
        )

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
    start_time = System.monotonic_time()

    # Get agent metadata before deletion for telemetry
    metadata =
      case :ets.lookup(state.main_table, agent_id) do
        [{^agent_id, _pid, meta, _timestamp}] -> meta
        [] -> %{}
      end

    Logger.info("Agent #{inspect(agent_id)} process died (#{inspect(reason)}), cleaning up")

    # Atomic cleanup - all operations in single GenServer message handler
    # This provides atomicity through GenServer serialization
    :ets.delete(state.main_table, agent_id)
    IndexManager.clear_agent_from_indexes(state, agent_id)

    # Remove from monitors
    new_monitors = Map.delete(state.monitors, monitor_ref)

    Telemetry.emit(
      [:foundation, :mabeam, :registry, :agent_down],
      %{
        duration: System.monotonic_time() - start_time,
        timestamp: System.system_time()
      },
      %{
        agent_id: agent_id,
        registry_id: state.registry_id,
        reason: reason,
        capabilities: List.wrap(Map.get(metadata, :capability, [])),
        health_status: Map.get(metadata, :health_status)
      }
    )

    # Notify ResourceManager about cleanup if available
    notify_resource_manager_cleanup(agent_id, reason)

    {:noreply, %{state | monitors: new_monitors}}
  end

  defp notify_resource_manager_cleanup(agent_id, reason) do
    if Process.whereis(Foundation.ResourceManager) do
      Foundation.TaskHelper.spawn_supervised_safe(fn ->
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
    start_time = System.monotonic_time()
    result = perform_registration(agent_id, pid, metadata, state)

    # Release resource token if registration failed
    case result do
      {:reply, :ok, _new_state} = success_result ->
        Telemetry.emit(
          [:foundation, :mabeam, :registry, :register],
          %{duration: System.monotonic_time() - start_time},
          %{
            agent_id: agent_id,
            registry_id: state.registry_id,
            capabilities: List.wrap(Map.get(metadata, :capability, [])),
            health_status: Map.get(metadata, :health_status),
            node: Map.get(metadata, :node)
          }
        )

        success_result

      error_result ->
        if resource_token, do: Foundation.ResourceManager.release_resource(resource_token)

        {:reply, {:error, reason}, _} = error_result

        Telemetry.emit(
          [:foundation, :mabeam, :registry, :register_failed],
          %{duration: System.monotonic_time() - start_time},
          %{
            agent_id: agent_id,
            registry_id: state.registry_id,
            reason: reason
          }
        )

        error_result
    end
  end

  defp perform_registration(agent_id, pid, metadata, state) do
    with :ok <- Validator.validate_agent_metadata(metadata),
         :ok <- Validator.validate_process_alive(pid),
         :ok <- Validator.validate_agent_not_exists(state.main_table, agent_id) do
      atomic_register(agent_id, pid, metadata, state)
    else
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # Validation functions moved to Validator module

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
    IndexManager.update_all_indexes(state, agent_id, metadata)

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
    start_time = System.monotonic_time()
    result = execute_batch_register(agents, state, [], resource_token)

    # Emit telemetry based on result
    case result do
      {:ok, registered_ids, _new_state} ->
        Telemetry.emit(
          [:foundation, :mabeam, :registry, :batch_operation],
          %{
            duration: System.monotonic_time() - start_time,
            success_count: length(registered_ids),
            total_count: length(agents)
          },
          %{
            registry_id: state.registry_id,
            operation: :batch_register,
            status: :success
          }
        )

      {:error, reason, partial_ids, _} ->
        Telemetry.emit(
          [:foundation, :mabeam, :registry, :batch_operation],
          %{
            duration: System.monotonic_time() - start_time,
            success_count: length(partial_ids),
            total_count: length(agents),
            failed_count: length(agents) - length(partial_ids)
          },
          %{
            registry_id: state.registry_id,
            operation: :batch_register,
            status: :partial_failure,
            error: reason
          }
        )
    end

    handle_batch_register_result(result, state, resource_token)
  end

  defp handle_batch_register_result({:ok, registered_ids, new_state}, _state, _resource_token) do
    {:reply, {:ok, registered_ids}, new_state}
  end

  defp handle_batch_register_result({:error, reason, partial_ids, _}, state, resource_token) do
    if resource_token, do: Foundation.ResourceManager.release_resource(resource_token)
    {:reply, {:error, reason, partial_ids}, state}
  end

  defp do_application_level_query(criteria, state, start_time \\ nil) do
    QueryEngine.do_application_level_query(criteria, state, start_time)
  end

  defp batch_lookup_agents(agent_ids, state) do
    QueryEngine.batch_lookup_agents(agent_ids, state)
  end

  defp apply_filter(results, filter_fn) do
    QueryEngine.apply_filter(results, filter_fn)
  end

  # Validation functions moved to Validator module

  # Index management functions moved to IndexManager module

  # Query matching functions moved to QueryEngine module

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
    with :ok <- Validator.validate_agent_metadata(metadata),
         true <- Process.alive?(pid),
         false <- :ets.member(state.main_table, agent_id) do
      # Create all the updates
      monitor_ref = Process.monitor(pid)
      entry = {agent_id, pid, metadata, :os.timestamp()}

      # Apply updates to ETS tables
      :ets.insert(state.main_table, entry)
      IndexManager.update_all_indexes(state, agent_id, metadata)

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
    with :ok <- Validator.validate_agent_metadata(new_metadata),
         [{^agent_id, pid, old_metadata, _timestamp}] <- :ets.lookup(state.main_table, agent_id) do
      # Update main table
      :ets.insert(state.main_table, {agent_id, pid, new_metadata, :os.timestamp()})

      # Update indexes
      IndexManager.clear_agent_from_indexes(state, agent_id)
      IndexManager.update_all_indexes(state, agent_id, new_metadata)

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
        IndexManager.clear_agent_from_indexes(state, agent_id)

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

  # Streaming helper for efficient ETS access

  defp stream_ets_select(table, match_spec, batch_size) do
    Stream.resource(
      # Start function - initiate the select
      fn -> :ets.select(table, match_spec, batch_size) end,

      # Next function - get next batch
      fn
        :"$end_of_table" -> {:halt, nil}
        {results, continuation} -> {results, continuation}
      end,

      # Cleanup function - nothing to clean up
      fn _acc -> :ok end
    )
  end
end
