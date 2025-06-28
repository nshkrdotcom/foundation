defmodule Foundation.ETSHelpers.MatchSpecCompiler do
  @moduledoc """
  ETS match specification compiler for efficient multi-criteria queries.

  This is a generalized version of the match spec compiler originally
  developed for MABEAM.AgentRegistry. It can be used by any Foundation
  protocol implementation that needs to compile high-level query criteria
  into efficient ETS match specifications.

  ## Supported Operations

  - `:eq` - Equality check (with special handling for list membership)
  - `:neq` - Inequality check
  - `:gt`, `:gte`, `:lt`, `:lte` - Numeric comparisons
  - `:in` - Member of list (with smart list/atom handling)
  - `:not_in` - Not member of list

  ## Query Format

  Criteria are specified as tuples: `{path, value, operation}`

  - `path` - List of keys to navigate nested maps (e.g., `[:resources, :memory_usage]`)
  - `value` - The value to compare against
  - `operation` - One of the supported operations above

  ## ETS Table Structure

  This compiler assumes ETS table records have the structure:
  `{key, pid, metadata, timestamp}`

  Where queries are performed against the `metadata` field (position 3).

  ## Examples

      # Find healthy agents with inference capability
      criteria = [
        {[:capability], :inference, :eq},
        {[:health_status], :healthy, :eq}
      ]

      # Find agents with sufficient resources
      criteria = [
        {[:resources, :memory_available], 0.5, :gte},
        {[:resources, :cpu_available], 0.3, :gte}
      ]

      # Compile and use
      {:ok, match_spec} = Foundation.ETSHelpers.MatchSpecCompiler.compile(criteria)
      results = :ets.select(table, match_spec)
  """

  @doc """
  Compiles query criteria into an ETS match specification.

  Returns a match spec that can be used with `:ets.select/2` for atomic queries.

  ## Parameters
  - `criteria` - List of criterion tuples `{path, value, operation}`

  ## Returns
  - `{:ok, match_spec}` - Compiled match specification
  - `{:error, reason}` - Compilation failed

  ## Match Spec Structure

  The generated match spec operates on ETS records with structure:
  `{key, pid, metadata, timestamp}` and returns `{key, pid, metadata}`.
  """
  @spec compile(criteria :: list({path :: list(atom()), value :: any(), op :: atom()})) ::
          {:ok, match_spec :: list()} | {:error, reason :: term()}
  def compile(criteria) when is_list(criteria) do
    # ETS table structure: {key, pid, metadata, timestamp}
    # $1 = key, $2 = pid, $3 = metadata, $4 = timestamp
    match_head = {:"$1", :"$2", :"$3", :"$4"}

    # Build guards from criteria (metadata is $3)
    guards = build_guards(criteria, :"$3")

    # Return pattern - we want {key, pid, metadata}
    return_pattern = {:"$1", :"$2", :"$3"}

    match_spec = [{match_head, guards, [return_pattern]}]

    {:ok, match_spec}
  rescue
    e ->
      {:error, {:compilation_failed, Exception.message(e)}}
  end

  def compile(_invalid_criteria) do
    {:error, :invalid_criteria_format}
  end

  @doc """
  Validates that criteria are properly formatted before compilation.

  ## Parameters
  - `criteria` - List of criterion tuples to validate

  ## Returns
  - `:ok` - All criteria are valid
  - `{:error, reason}` - Invalid criteria detected
  """
  @spec validate_criteria(criteria :: list()) :: :ok | {:error, reason :: term()}
  def validate_criteria(criteria) when is_list(criteria) do
    case Enum.find(criteria, &invalid_criterion?/1) do
      nil -> :ok
      invalid -> {:error, {:invalid_criterion, invalid}}
    end
  end

  def validate_criteria(_) do
    {:error, :criteria_must_be_list}
  end

  # --- Private Implementation ---

  # Build guard expressions from criteria
  defp build_guards(criteria, metadata_var) do
    guards =
      Enum.map(criteria, fn {path, value, op} ->
        build_guard_for_criterion(path, value, op, metadata_var)
      end)

    # If we have multiple guards, combine them with andalso
    case guards do
      [] -> []
      [single] -> [single]
      multiple -> [{:andalso, combine_guards(multiple)}]
    end
  end

  # Recursively combine guards with andalso
  defp combine_guards([guard1, guard2]) do
    {guard1, guard2}
  end

  defp combine_guards([guard | rest]) do
    {guard, combine_guards(rest)}
  end

  # Build a single guard expression for a criterion
  defp build_guard_for_criterion(path, value, op, metadata_var) do
    # Build the path accessor for nested map navigation
    accessor = build_path_accessor(path, metadata_var)

    # Delegate to specific operation builder
    build_operation_guard(op, accessor, value)
  end

  # Operation-specific guard builders
  defp build_operation_guard(:eq, accessor, value), do: build_equality_guard(accessor, value)
  defp build_operation_guard(:neq, accessor, value), do: {:"/=", accessor, value}
  defp build_operation_guard(:gt, accessor, value), do: {:>, accessor, value}
  defp build_operation_guard(:gte, accessor, value), do: {:>=, accessor, value}
  defp build_operation_guard(:lt, accessor, value), do: {:<, accessor, value}
  defp build_operation_guard(:lte, accessor, value), do: {:"=<", accessor, value}

  defp build_operation_guard(:in, accessor, value) when is_list(value) do
    build_in_guard(accessor, value)
  end

  defp build_operation_guard(:not_in, accessor, value) when is_list(value) do
    build_not_in_guard(accessor, value)
  end

  defp build_operation_guard(_, _, _) do
    # Unsupported operation - this will cause match to fail
    {:const, false}
  end

  # Special handling for equality with capability lists
  # This handles the common case where a field might be a single atom or a list of atoms
  defp build_equality_guard(accessor, value) when is_atom(value) do
    # Check if the value equals the accessor directly OR if it's a member of a list
    {:orelse, {:"=:=", accessor, value},
     {:andalso, {:is_list, accessor}, {:member, value, accessor}}}
  end

  defp build_equality_guard(accessor, value) do
    {:"=:=", accessor, value}
  end

  # Build :in guard as OR of equality checks
  # Handle the case where the field might be a single atom or a list
  defp build_in_guard(accessor, [single_value]) do
    # Check if accessor equals the value OR if it's a list containing the value
    {:orelse, {:"=:=", accessor, single_value},
     {:andalso, {:is_list, accessor}, {:member, single_value, accessor}}}
  end

  defp build_in_guard(accessor, values) do
    guards =
      Enum.map(values, fn value ->
        # For each value, check if accessor equals it OR contains it in a list
        {:orelse, {:"=:=", accessor, value},
         {:andalso, {:is_list, accessor}, {:member, value, accessor}}}
      end)

    # Combine all guards with orelse
    case guards do
      [single] -> single
      multiple -> {:orelse, combine_or_guards(multiple)}
    end
  end

  # Build :not_in guard as AND of inequality checks
  defp build_not_in_guard(accessor, values) do
    guards =
      Enum.map(values, fn value ->
        {:"/=", accessor, value}
      end)

    # Combine with andalso
    case guards do
      [single] -> single
      multiple -> {:andalso, combine_guards(multiple)}
    end
  end

  # Recursively combine guards with orelse
  defp combine_or_guards([guard1, guard2]) do
    {guard1, guard2}
  end

  defp combine_or_guards([guard | rest]) do
    {guard, combine_or_guards(rest)}
  end

  # Build nested map accessor for ETS match spec
  # For path [:a, :b], builds equivalent of: maps:get(:b, maps:get(:a, metadata, #{}), nil)
  defp build_path_accessor([key], base_var) do
    {:maps, :get, [key, base_var, :undefined]}
  end

  defp build_path_accessor([key | rest], base_var) do
    inner_map = {:maps, :get, [key, base_var, {:map}]}
    build_path_accessor(rest, inner_map)
  end

  # Validation helpers
  defp invalid_criterion?({path, _value, op}) when is_list(path) do
    not valid_operation?(op)
  end

  defp invalid_criterion?(_), do: true

  defp valid_operation?(op) do
    op in [:eq, :neq, :gt, :lt, :gte, :lte, :in, :not_in]
  end
end
