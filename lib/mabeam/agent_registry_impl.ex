defimpl Foundation.Registry, for: MABEAM.AgentRegistry do
  @moduledoc """
  Foundation.Registry protocol implementation for MABEAM.AgentRegistry.

  This implementation provides the bridge between the generic Foundation protocols
  and the agent-optimized MABEAM registry.

  ## Performance Optimization

  - Write operations go through the GenServer for consistency
  - Read operations use direct ETS access for maximum concurrency
  - Table names are cached in the process dictionary to avoid repeated lookups
  """

  require Logger

  # --- Write Operations (Go through GenServer) ---

  def register(registry_pid, agent_id, pid, metadata) do
    GenServer.call(registry_pid, {:register, agent_id, pid, metadata})
  end

  def update_metadata(registry_pid, agent_id, new_metadata) do
    GenServer.call(registry_pid, {:update_metadata, agent_id, new_metadata})
  end

  def unregister(registry_pid, agent_id) do
    GenServer.call(registry_pid, {:unregister, agent_id})
  end

  # --- Read Operations (Direct ETS access) ---

  def lookup(registry_pid, agent_id) do
    tables = get_cached_table_names(registry_pid)

    case :ets.lookup(tables.main, agent_id) do
      [{^agent_id, pid, metadata, _timestamp}] -> {:ok, {pid, metadata}}
      [] -> :error
    end
  end

  def find_by_attribute(registry_pid, attribute, value) do
    tables = get_cached_table_names(registry_pid)

    result =
      case attribute do
        :capability ->
          agent_ids = :ets.lookup(tables.capability_index, value) |> Enum.map(&elem(&1, 1))
          batch_lookup_agents(agent_ids, tables.main)

        :health_status ->
          agent_ids = :ets.lookup(tables.health_index, value) |> Enum.map(&elem(&1, 1))
          batch_lookup_agents(agent_ids, tables.main)

        :node ->
          agent_ids = :ets.lookup(tables.node_index, value) |> Enum.map(&elem(&1, 1))
          batch_lookup_agents(agent_ids, tables.main)

        _ ->
          {:error, {:unsupported_attribute, attribute}}
      end

    result
  end

  def query(registry_pid, criteria) do
    # Complex queries still go through GenServer for now
    # This ensures match spec compilation is handled safely
    GenServer.call(registry_pid, {:query, criteria})
  end

  def indexed_attributes(_registry_pid) do
    # This is a static list, no need to go through GenServer
    [:capability, :health_status, :node]
  end

  def list_all(registry_pid, filter_fn) do
    tables = get_cached_table_names(registry_pid)

    results =
      :ets.tab2list(tables.main)
      |> Enum.map(fn {id, pid, metadata, _timestamp} -> {id, pid, metadata} end)
      |> apply_filter(filter_fn)

    results
  end

  # --- Private Helpers ---

  defp get_cached_table_names(registry_pid) do
    cache_key = {__MODULE__, :table_names, registry_pid}

    case Process.get(cache_key) do
      nil ->
        # First access, fetch and cache the table names
        {:ok, tables} = GenServer.call(registry_pid, {:get_table_names})
        Process.put(cache_key, tables)
        tables

      tables ->
        # Use cached table names
        tables
    end
  end

  defp batch_lookup_agents(agent_ids, main_table) do
    results =
      agent_ids
      |> Enum.map(&:ets.lookup(main_table, &1))
      |> List.flatten()
      |> Enum.map(fn {id, pid, metadata, _timestamp} -> {id, pid, metadata} end)

    {:ok, results}
  end

  defp apply_filter(results, nil), do: results

  defp apply_filter(results, filter_fn) do
    Enum.filter(results, fn {_id, _pid, metadata} -> filter_fn.(metadata) end)
  end

  def count(registry_pid) do
    tables = get_cached_table_names(registry_pid)
    count = :ets.info(tables.main, :size)
    {:ok, count}
  end

  def select(registry_pid, match_spec) do
    tables = get_cached_table_names(registry_pid)
    :ets.select(tables.main, match_spec)
  end

  def protocol_version(registry_pid) do
    GenServer.call(registry_pid, {:protocol_version})
  end
end
