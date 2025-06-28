defmodule MABEAM.AgentRegistry do
  @moduledoc """
  High-performance agent registry with pure GenServer implementation.

  ## Architecture: Pure GenServer Pattern

  All operations (both read and write) go through the GenServer process to ensure:
  - Atomic operations across all tables
  - Consistent state management
  - Proper isolation between registry instances
  - No global state dependencies

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

  alias MABEAM.AgentRegistry.MatchSpecCompiler

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
    # Generate unique registry ID for table names
    registry_id = Keyword.get(opts, :id, :default)

    # Create unique table names for this instance
    main_table_name = :"agent_main_#{registry_id}"
    capability_idx_name = :"agent_capability_idx_#{registry_id}"
    health_idx_name = :"agent_health_idx_#{registry_id}"
    node_idx_name = :"agent_node_idx_#{registry_id}"
    resource_idx_name = :"agent_resource_idx_#{registry_id}"

    # Clean up any existing tables from previous runs
    [main_table_name, capability_idx_name, health_idx_name, node_idx_name, resource_idx_name]
    |> Enum.each(&safe_ets_delete/1)

    # Tables are public for direct read access, with concurrent read/write optimization
    table_opts = [:public, read_concurrency: true, write_concurrency: true]

    state = %__MODULE__{
      main_table: :ets.new(main_table_name, [:set | table_opts]),
      capability_index: :ets.new(capability_idx_name, [:bag | table_opts]),
      health_index: :ets.new(health_idx_name, [:bag | table_opts]),
      node_index: :ets.new(node_idx_name, [:bag | table_opts]),
      resource_index: :ets.new(resource_idx_name, [:ordered_set | table_opts]),
      monitors: %{},
      registry_id: registry_id
    }

    Logger.info("MABEAM.AgentRegistry (#{registry_id}) started with public ETS tables")

    {:ok, state}
  end

  def terminate(_reason, state) do
    Logger.info("MABEAM.AgentRegistry (#{state.registry_id}) terminating, cleaning up ETS tables")

    # Clean up ETS tables
    safe_ets_delete(state.main_table)
    safe_ets_delete(state.capability_index)
    safe_ets_delete(state.health_index)
    safe_ets_delete(state.node_index)
    safe_ets_delete(state.resource_index)
    :ok
  end

  defp safe_ets_delete(table) do
    :ets.delete(table)
  rescue
    # Table already deleted or doesn't exist
    ArgumentError -> :ok
  end

  # --- GenServer Implementation for ALL Operations ---

  # Write Operations

  def handle_call({:register, agent_id, pid, metadata}, _from, state) do
    with :ok <- validate_agent_metadata(metadata),
         true <- Process.alive?(pid),
         false <- :ets.member(state.main_table, agent_id) do
      # Atomic registration within single GenServer call
      monitor_ref = Process.monitor(pid)

      # Insert into main table
      entry = {agent_id, pid, metadata, :os.timestamp()}
      :ets.insert(state.main_table, entry)

      # Update all indexes
      update_all_indexes(state, agent_id, metadata)

      # Track monitor reference
      new_monitors = Map.put(state.monitors, monitor_ref, agent_id)

      Logger.debug(
        "Registered agent #{inspect(agent_id)} with capabilities #{inspect(metadata.capability)}"
      )

      {:reply, :ok, %{state | monitors: new_monitors}}
    else
      false ->
        # Process is dead
        {:reply, {:error, :process_not_alive}, state}

      true ->
        # Agent already exists
        {:reply, {:error, :already_exists}, state}

      error ->
        {:reply, error, state}
    end
  end

  def handle_call({:update_metadata, agent_id, new_metadata}, _from, state) do
    with :ok <- validate_agent_metadata(new_metadata),
         [{^agent_id, pid, _old_metadata, _timestamp}] <- :ets.lookup(state.main_table, agent_id) do
      # Update main table
      :ets.insert(state.main_table, {agent_id, pid, new_metadata, :os.timestamp()})

      # Clear old indexes and rebuild
      clear_agent_from_indexes(state, agent_id)
      update_all_indexes(state, agent_id, new_metadata)

      Logger.debug("Updated metadata for agent #{inspect(agent_id)}")

      {:reply, :ok, state}
    else
      [] -> {:reply, {:error, :not_found}, state}
      error -> {:reply, error, state}
    end
  end

  def handle_call({:unregister, agent_id}, _from, state) do
    case :ets.lookup(state.main_table, agent_id) do
      [{^agent_id, _pid, _metadata, _timestamp}] ->
        :ets.delete(state.main_table, agent_id)
        clear_agent_from_indexes(state, agent_id)

        # Find and remove monitor for this agent
        monitor_ref =
          state.monitors
          |> Enum.find(fn {_ref, id} -> id == agent_id end)
          |> case do
            {ref, _} -> ref
            nil -> nil
          end

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

  # Read Operations

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

  def handle_info({:DOWN, monitor_ref, :process, _pid, reason}, state) do
    case Map.get(state.monitors, monitor_ref) do
      nil ->
        # Unknown monitor, ignore
        {:noreply, state}

      agent_id ->
        Logger.info("Agent #{inspect(agent_id)} process died (#{inspect(reason)}), cleaning up")

        # Clean up agent registration
        :ets.delete(state.main_table, agent_id)
        clear_agent_from_indexes(state, agent_id)

        # Remove from monitors
        new_monitors = Map.delete(state.monitors, monitor_ref)

        {:noreply, %{state | monitors: new_monitors}}
    end
  end

  # --- Private Helpers ---

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
end
