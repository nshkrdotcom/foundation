defmodule MABEAM.AgentRegistry.QueryEngine do
  @moduledoc """
  Query processing engine for agent registry lookups.

  Extracted from MABEAM.AgentRegistry to handle complex query operations.
  Supports criteria-based queries, filtering, and efficient batch lookups.
  """

  require Logger

  @doc """
  Performs application-level query when match specs cannot be used.

  Uses ETS match_object with streaming to avoid loading entire table into memory.
  Falls back to filtering in-application when ETS match specifications 
  cannot express the query criteria.
  """
  @spec do_application_level_query(list(), map(), integer() | nil) ::
          {:ok, list()} | {:error, term()}
  def do_application_level_query(criteria, tables, start_time \\ nil) do
    query_start = start_time || System.monotonic_time()

    # Build a basic match spec to reduce data transferred from ETS
    # Use streaming with continuation to avoid loading entire table
    match_spec = build_partial_match_spec(criteria)

    # Stream results from ETS to avoid loading entire table
    filtered_results = stream_and_filter_ets(tables.main_table, match_spec, criteria)

    # Format results
    formatted_results =
      Enum.map(filtered_results, fn {id, pid, metadata, _timestamp} ->
        {id, pid, metadata}
      end)

    Foundation.Telemetry.emit(
      [:foundation, :mabeam, :registry, :query],
      %{
        duration: System.monotonic_time() - query_start,
        result_count: length(formatted_results),
        # Can't know without full scan
        total_scanned: :unknown
      },
      %{
        registry_id: tables.registry_id,
        criteria_count: length(criteria),
        query_type: :streaming_application_level
      }
    )

    {:ok, formatted_results}
  rescue
    e in [ArgumentError, MatchError] ->
      {:error, {:invalid_criteria, Exception.message(e)}}
  end

  @doc """
  Performs batch lookup of agents by their IDs.
  """
  @spec batch_lookup_agents(list(), map()) :: {:ok, list()}
  def batch_lookup_agents(agent_ids, tables) do
    results =
      agent_ids
      |> Enum.map(&:ets.lookup(tables.main_table, &1))
      |> List.flatten()
      |> Enum.map(fn {id, pid, metadata, _timestamp} -> {id, pid, metadata} end)

    {:ok, results}
  end

  @doc """
  Applies an optional filter function to query results.
  """
  @spec apply_filter(list(), nil | fun()) :: list()
  def apply_filter(results, nil), do: results

  def apply_filter(results, filter_fn) do
    Enum.filter(results, fn {_id, _pid, metadata} -> filter_fn.(metadata) end)
  end

  @doc """
  Checks if metadata matches a single criterion.
  """
  @spec matches_criterion?(
          map(),
          {list(), term(), :eq | :neq | :gt | :lt | :gte | :lte | :in | :not_in}
        ) :: boolean()
  def matches_criterion?(metadata, {path, value, op}) do
    actual_value = get_nested_value(metadata, path)
    apply_operation(actual_value, value, op)
  end

  # Private helper functions

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

  # Streaming ETS functions to avoid loading entire table

  @doc false
  defp build_partial_match_spec(_criteria) do
    # Build a basic match spec that can filter some criteria at ETS level
    # This reduces the amount of data transferred from ETS
    # Even if we can't express all criteria, any filtering helps
    # {id, pid, metadata, timestamp}
    pattern = {:_, :_, :_, :_}

    # For now, use a permissive pattern and filter in-app
    # Future optimization: Convert simple equality checks to ETS guards
    [{pattern, [], [:"$_"]}]
  end

  @doc false
  defp stream_and_filter_ets(table, match_spec, criteria) do
    # Use ETS select with continuation to stream results
    # This avoids loading the entire table into memory at once
    stream_ets_select(table, match_spec)
    |> Stream.filter(fn {_id, _pid, metadata, _timestamp} ->
      Enum.all?(criteria, fn criterion ->
        matches_criterion?(metadata, criterion)
      end)
    end)
    |> Enum.to_list()
  end

  @doc false
  defp stream_ets_select(table, match_spec) do
    # Stream results from ETS using continuation
    # Default to 100 items per batch to balance memory vs performance
    batch_size = 100

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
