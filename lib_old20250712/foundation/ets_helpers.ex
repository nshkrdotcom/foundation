defmodule Foundation.ETSHelpers do
  @moduledoc """
  Reusable ETS utilities for high-performance Foundation Protocol Platform backends.

  This module provides common ETS functionality that can be used by any
  protocol implementation, promoting code reuse and consistency across
  the Foundation ecosystem.

  ## Key Features

  - **MatchSpecCompiler**: Compile high-level query criteria into efficient ETS match specs
  - **Query Validation**: Validate query criteria format and operations
  - **Performance Optimizations**: Generate O(1) atomic queries from multi-criteria filters

  ## Usage Examples

      # Compile a multi-criteria query
      criteria = [
        {[:capability], :inference, :eq},
        {[:health_status], :healthy, :eq}
      ]

      {:ok, match_spec} = Foundation.ETSHelpers.compile_match_spec(criteria)
      results = :ets.select(table, match_spec)

      # Validate criteria before compilation
      :ok = Foundation.ETSHelpers.validate_criteria(criteria)

  ## Supported Operations

  - `:eq` - Equality check (with special handling for list membership)
  - `:neq` - Inequality check
  - `:gt`, `:gte`, `:lt`, `:lte` - Numeric comparisons
  - `:in` - Member of list (with smart list handling)
  - `:not_in` - Not member of list

  ## ETS Table Structure Assumptions

  This module assumes ETS table records have the structure:
  `{key, pid, metadata, timestamp}`

  Where:
  - `key` - The record identifier
  - `pid` - Associated process PID
  - `metadata` - Map containing searchable fields
  - `timestamp` - Record creation/update time
  """

  alias Foundation.ETSHelpers.MatchSpecCompiler

  @doc """
  Compiles query criteria into an ETS match specification for atomic queries.

  ## Parameters
  - `criteria` - List of criterion tuples `{path, value, operation}`

  ## Returns
  - `{:ok, match_spec}` - Compiled match specification ready for `:ets.select/2`
  - `{:error, reason}` - Compilation failed

  ## Examples
      criteria = [
        {[:resources, :memory_available], 0.5, :gte},
        {[:health_status], :healthy, :eq}
      ]

      {:ok, match_spec} = Foundation.ETSHelpers.compile_match_spec(criteria)
      results = :ets.select(my_table, match_spec)
  """
  @spec compile_match_spec(criteria :: [{[atom()], any(), atom()}]) ::
          {:ok, [{{any(), any(), any(), any()}, [any()], [any(), ...]}, ...]}
          | {:error, :invalid_criteria_format | {:compilation_failed, binary()}}
  def compile_match_spec(criteria) do
    MatchSpecCompiler.compile(criteria)
  end

  @doc """
  Validates that criteria are properly formatted before compilation.

  ## Parameters
  - `criteria` - List of criterion tuples to validate

  ## Returns
  - `:ok` - All criteria are valid
  - `{:error, reason}` - Invalid criteria detected

  ## Examples
      criteria = [
        {[:capability], :inference, :eq},
        {[:invalid_path], "value", :unsupported_op}  # This will fail
      ]

      {:error, {:invalid_criterion, _}} = Foundation.ETSHelpers.validate_criteria(criteria)
  """
  @spec validate_criteria(criteria :: [term()]) ::
          :ok | {:error, :criteria_must_be_list | {:invalid_criterion, term()}}
  def validate_criteria(criteria) do
    MatchSpecCompiler.validate_criteria(criteria)
  end

  @doc """
  Returns the list of supported query operations.

  ## Returns
  List of atoms representing supported operations for query criteria.
  """
  @spec supported_operations() :: [:eq | :neq | :gt | :lt | :gte | :lte | :in | :not_in, ...]
  def supported_operations do
    [:eq, :neq, :gt, :lt, :gte, :lte, :in, :not_in]
  end

  @doc """
  Checks if an operation is supported by the match spec compiler.

  ## Parameters
  - `operation` - The operation atom to check

  ## Examples
      true = Foundation.ETSHelpers.operation_supported?(:eq)
      false = Foundation.ETSHelpers.operation_supported?(:regex)
  """
  @spec operation_supported?(operation :: atom()) :: boolean()
  def operation_supported?(operation) do
    operation in supported_operations()
  end
end
