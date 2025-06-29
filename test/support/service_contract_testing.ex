defmodule Foundation.Support.ServiceContractTesting do
  @moduledoc """
  Service Contract Testing Framework for Foundation.

  This module provides property-based testing utilities to validate service boundaries
  and prevent API evolution mismatches like the Discovery mock format issues.

  ## Purpose

  As identified in P23aTranscend.md, protocol boundary evolution is a transcendent
  architectural challenge. When service APIs evolve (e.g., Discovery functions changing
  from `[agents]` to `{:ok, agents}`), test infrastructure often doesn't adapt automatically.

  This framework addresses that by:
  1. Defining explicit service contracts with property-based validation
  2. Ensuring test mocks conform to production service APIs
  3. Detecting contract violations during development
  4. Providing contract migration utilities

  ## Usage

      defmodule MyServiceTest do
        use ExUnit.Case
        import Foundation.Support.ServiceContractTesting

        test "service respects Discovery contract" do
          validate_discovery_contract(MyMockModule)
        end
      end
  """

  @doc """
  Validates that a Discovery implementation respects the standard Discovery contract.

  ## Discovery Service Contract

  All Discovery service functions must return `{:ok, results}` or `{:error, reason}` tuples:

  - `find_capable_and_healthy/2` → `{:ok, [agent_tuples]} | {:error, reason}`
  - `find_agents_with_resources/3` → `{:ok, [agent_tuples]} | {:error, reason}`
  - `find_least_loaded_agents/3` → `{:ok, [agent_tuples]} | {:error, reason}`

  Where `agent_tuples` are `{id, pid, metadata}` tuples.

  ## Examples

      # Validate real Discovery module
      validate_discovery_contract(MABEAM.Discovery)

      # Validate test mock
      validate_discovery_contract(MyTest.MockDiscovery)

  This will catch issues like returning raw lists instead of `{:ok, list}` tuples.
  """
  @spec validate_discovery_contract(module()) :: :ok | {:error, [term()]}
  def validate_discovery_contract(discovery_module) do
    violations = []

    # Test find_capable_and_healthy contract (arity 1 and 2)
    violations = violations ++ validate_function_contract(
      discovery_module,
      :find_capable_and_healthy,
      [:test_capability],
      &validate_discovery_result/1
    )

    # Test find_agents_with_resources contract (arity 2 and 3)
    violations = violations ++ validate_function_contract(
      discovery_module,
      :find_agents_with_resources,
      [0.5, 0.5],
      &validate_discovery_result/1
    )

    # Test find_least_loaded_agents contract (arity 1, 2, and 3)
    violations = violations ++ validate_function_contract(
      discovery_module,
      :find_least_loaded_agents,
      [:test_capability],
      &validate_discovery_result/1
    )

    case violations do
      [] -> :ok
      violations -> {:error, violations}
    end
  end

  @doc """
  Validates a function against a contract specification.

  ## Parameters

  - `module` - The module to test
  - `function` - The function name (atom)
  - `args` - Arguments to pass to the function
  - `validator` - Function that validates the result

  Returns a list of contract violations (empty list means no violations).
  """
  @spec validate_function_contract(module(), atom(), [term()], function()) :: [term()]
  def validate_function_contract(module, function, args, validator) do
    try do
      if function_exported?(module, function, length(args)) do
        result = apply(module, function, args)
        case validator.(result) do
          :ok -> []
          {:error, reason} -> [{:contract_violation, module, function, reason}]
        end
      else
        [{:function_not_exported, module, function, length(args)}]
      end
    catch
      kind, error ->
        [{:function_error, module, function, {kind, error}}]
    end
  end

  @doc """
  Validates that a Discovery function result follows the standard contract.

  Discovery functions must return:
  - `{:ok, agents}` where agents is a list of `{id, pid, metadata}` tuples
  - `{:error, reason}` for error cases

  Common violations:
  - Returning raw lists instead of `{:ok, list}` 
  - Returning `nil` instead of `{:error, reason}`
  - Malformed agent tuples
  """
  @spec validate_discovery_result(term()) :: :ok | {:error, term()}
  def validate_discovery_result(result) do
    case result do
      {:ok, agents} when is_list(agents) ->
        # Validate each agent tuple format
        agent_violations = Enum.flat_map(agents, &validate_agent_tuple/1)
        case agent_violations do
          [] -> :ok
          violations -> {:error, {:invalid_agent_tuples, violations}}
        end

      {:error, _reason} ->
        :ok

      # Common violations
      agents when is_list(agents) ->
        {:error, {:missing_ok_tuple, "Function returned raw list instead of {:ok, list}"}}

      nil ->
        {:error, {:invalid_return, "Function returned nil instead of {:ok, []} or {:error, reason}"}}

      other ->
        {:error, {:invalid_return, "Unknown return format: #{inspect(other)}"}}
    end
  end

  @doc """
  Validates that an agent tuple follows the expected `{id, pid, metadata}` format.
  """
  @spec validate_agent_tuple(term()) :: [term()]
  def validate_agent_tuple(agent_tuple) do
    case agent_tuple do
      {id, pid, metadata} when is_binary(id) or is_atom(id) ->
        violations = []
        
        # Validate pid
        violations = if is_pid(pid) or is_atom(pid) do
          violations
        else
          [{:invalid_pid, "Agent pid must be a pid or atom, got: #{inspect(pid)}"} | violations]
        end

        # Validate metadata
        violations = if is_map(metadata) do
          violations
        else
          [{:invalid_metadata, "Agent metadata must be a map, got: #{inspect(metadata)}"} | violations]
        end

        violations

      other ->
        [{:invalid_tuple_format, "Agent tuple must be {id, pid, metadata}, got: #{inspect(other)}"}]
    end
  end

  @doc """
  Creates a property-based test for Discovery contract validation.

  Uses StreamData to generate test inputs and validate that the service
  consistently returns properly formatted responses.

  ## Example

      property "Discovery service always returns proper format" do
        check all capability <- atom(:alphanumeric),
                  max_runs: 50 do
          result = MABEAM.Discovery.find_capable_and_healthy(capability, nil)
          assert validate_discovery_result(result) == :ok
        end
      end
  """
  defmacro property_discovery_contract(discovery_module) do
    quote do
      import StreamData
      import ExUnitProperties

      property "#{unquote(discovery_module)} respects Discovery contract" do
        check all capability <- atom(:alphanumeric),
                  memory <- float(min: 0.0, max: 1.0),
                  cpu <- float(min: 0.0, max: 1.0),
                  count <- positive_integer(),
                  max_runs: 20 do

          # Test find_capable_and_healthy
          result1 = unquote(discovery_module).find_capable_and_healthy(capability, nil)
          assert Foundation.Support.ServiceContractTesting.validate_discovery_result(result1) == :ok

          # Test find_agents_with_resources  
          result2 = unquote(discovery_module).find_agents_with_resources(memory, cpu, nil)
          assert Foundation.Support.ServiceContractTesting.validate_discovery_result(result2) == :ok

          # Test find_least_loaded_agents
          result3 = unquote(discovery_module).find_least_loaded_agents(capability, count, nil)
          assert Foundation.Support.ServiceContractTesting.validate_discovery_result(result3) == :ok
        end
      end
    end
  end

  @doc """
  Migration utility to upgrade Discovery mock functions to the new contract.

  This can be used to automatically fix mock violations during development.
  """
  @spec upgrade_discovery_mock_result(term()) :: {:ok, [term()]} | {:error, term()}
  def upgrade_discovery_mock_result(result) do
    case result do
      # Already in correct format
      {:ok, _agents} = correct -> correct
      {:error, _reason} = error -> error

      # Upgrade raw list to {:ok, list} format
      agents when is_list(agents) -> {:ok, agents}

      # Upgrade nil to proper error
      nil -> {:error, :not_found}

      # Unknown format
      other -> {:error, {:unknown_format, other}}
    end
  end
end