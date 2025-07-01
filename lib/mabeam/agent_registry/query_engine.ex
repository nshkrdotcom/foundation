defmodule MABEAM.AgentRegistry.QueryEngine do
  @moduledoc """
  Query processing engine for agent registry lookups.

  Extracted from MABEAM.AgentRegistry to handle complex query operations.
  Supports criteria-based queries, filtering, and efficient batch lookups.
  """

  require Logger

  @doc """
  Performs application-level query when match specs cannot be used.

  Falls back to loading all agents and filtering in-memory when
  ETS match specifications cannot express the query criteria.
  """
  @spec do_application_level_query(list(), map(), integer() | nil) ::
          {:ok, list()} | {:error, term()}
  def do_application_level_query(criteria, tables, start_time \\ nil) do
    query_start = start_time || System.monotonic_time()
    all_agents = :ets.tab2list(tables.main_table)

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

    Foundation.Telemetry.emit(
      [:foundation, :mabeam, :registry, :query],
      %{
        duration: System.monotonic_time() - query_start,
        result_count: length(formatted_results),
        total_scanned: length(all_agents)
      },
      %{
        registry_id: tables.registry_id,
        criteria_count: length(criteria),
        query_type: :application_level
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
end
