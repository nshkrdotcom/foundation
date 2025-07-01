defmodule MABEAM.AgentRegistry.Reader do
  @moduledoc """
  Direct ETS read access for agent registry queries.

  Provides lock-free concurrent reads by bypassing GenServer bottleneck.
  All functions in this module perform read-only operations directly
  on ETS tables for maximum performance.
  """

  alias MABEAM.AgentRegistry.QueryEngine

  @doc """
  Gets table names from a running registry process.

  This is the only operation that goes through the GenServer,
  and should be called once during initialization to cache table names.
  """
  @spec get_table_names(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def get_table_names(registry \\ MABEAM.AgentRegistry) do
    GenServer.call(registry, {:get_table_names})
  end

  @doc """
  Looks up an agent by ID using direct ETS access.

  Returns {:ok, {pid, metadata}} if found, :error otherwise.
  Bypasses GenServer for lock-free read performance.
  """
  @spec lookup(map(), any()) :: {:ok, {pid(), map()}} | :error
  def lookup(tables, agent_id) do
    case :ets.lookup(tables.main_table, agent_id) do
      [{^agent_id, pid, metadata, _timestamp}] ->
        {:ok, {pid, metadata}}

      [] ->
        :error
    end
  end

  @doc """
  Finds agents by attribute using direct ETS access.

  Supported attributes: :capability, :health_status, :node
  Returns {:ok, list()} with matching agents.
  """
  @spec find_by_attribute(map(), atom(), any()) :: {:ok, list()} | {:error, term()}
  def find_by_attribute(tables, attribute, value) do
    case attribute do
      :capability ->
        agent_ids = :ets.lookup(tables.capability_index, value) |> Enum.map(&elem(&1, 1))
        QueryEngine.batch_lookup_agents(agent_ids, tables)

      :health_status ->
        agent_ids = :ets.lookup(tables.health_index, value) |> Enum.map(&elem(&1, 1))
        QueryEngine.batch_lookup_agents(agent_ids, tables)

      :node ->
        agent_ids = :ets.lookup(tables.node_index, value) |> Enum.map(&elem(&1, 1))
        QueryEngine.batch_lookup_agents(agent_ids, tables)

      _ ->
        {:error, {:unsupported_attribute, attribute}}
    end
  end

  @doc """
  Lists all agents with optional filtering using direct ETS access.

  The filter function receives agent metadata and should return true to include.
  Uses streaming to avoid loading entire table into memory.
  """
  @spec list_all(map(), nil | (map() -> boolean())) :: list()
  def list_all(tables, filter_fn \\ nil) do
    # Use streaming with ETS select and continuation
    # to avoid loading entire table into memory
    match_spec = [{:_, [], [:"$_"]}]
    batch_size = 100

    results =
      stream_ets_select(tables.main_table, match_spec, batch_size)
      |> Stream.map(fn {id, pid, metadata, _timestamp} -> {id, pid, metadata} end)
      |> Enum.to_list()

    QueryEngine.apply_filter(results, filter_fn)
  end

  @doc """
  Queries agents with complex criteria using direct ETS access.

  First attempts to compile criteria to ETS match specifications for performance.
  Falls back to application-level filtering when match specs cannot express the query.
  """
  @spec query(map(), list()) :: {:ok, list()} | {:error, term()}
  def query(tables, criteria) when is_list(criteria) do
    start_time = System.monotonic_time()

    case Foundation.ETSHelpers.MatchSpecCompiler.validate_criteria(criteria) do
      :ok ->
        # Try to compile to match spec for atomic query
        case Foundation.ETSHelpers.MatchSpecCompiler.compile(criteria) do
          {:ok, match_spec} ->
            # Use atomic ETS select for O(1) performance
            try do
              results = :ets.select(tables.main_table, match_spec)

              Foundation.Telemetry.emit(
                [:foundation, :mabeam, :registry, :query],
                %{
                  duration: System.monotonic_time() - start_time,
                  result_count: length(results)
                },
                %{
                  registry_id: tables.registry_id,
                  criteria_count: length(criteria),
                  query_type: :match_spec
                }
              )

              {:ok, results}
            rescue
              _e ->
                # Fall back to application-level filtering when match spec fails
                QueryEngine.do_application_level_query(criteria, tables, start_time)
            end

          {:error, _reason} ->
            # Fall back to application-level filtering for unsupported criteria
            QueryEngine.do_application_level_query(criteria, tables, start_time)
        end

      {:error, reason} ->
        {:error, {:invalid_criteria, reason}}
    end
  end

  @doc """
  Counts the total number of registered agents using direct ETS access.
  """
  @spec count(map()) :: {:ok, non_neg_integer()}
  def count(tables) do
    {:ok, :ets.info(tables.main_table, :size)}
  end

  # Private helper for streaming ETS results

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
