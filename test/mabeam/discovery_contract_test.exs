defmodule MABEAM.DiscoveryContractTest do
  @moduledoc """
  Property-based contract tests for MABEAM.Discovery service boundaries.

  This test module validates that Discovery service implementations consistently
  follow the proper contract format, preventing the API evolution mismatches
  identified in P23aTranscend.md.

  These tests run property-based validation to ensure Discovery functions
  always return `{:ok, agents}` or `{:error, reason}` tuples, never raw lists.
  """

  use ExUnit.Case
  use ExUnitProperties

  import Foundation.Support.ServiceContractTesting

  alias MABEAM.Discovery

  describe "MABEAM.Discovery contract validation" do
    test "validates Discovery service contract manually" do
      # This will catch if Discovery functions return raw lists instead of {:ok, list}
      assert validate_discovery_contract(Discovery) == :ok
    end

    property "Discovery.find_capable_and_healthy always returns proper format" do
      check all(
              capability <-
                one_of([
                  atom(:alphanumeric),
                  constant(:inference),
                  constant(:training),
                  constant(:coordination),
                  constant(:non_existent)
                ]),
              max_runs: 30
            ) do
        # Use evolved arity 2 signature (capability, impl)
        result = Discovery.find_capable_and_healthy(capability, nil)

        case validate_discovery_result(result) do
          :ok ->
            :ok

          {:error, reason} ->
            flunk(
              "Discovery.find_capable_and_healthy violated contract for #{capability}: #{inspect(reason)}"
            )
        end
      end
    end

    property "Discovery.find_agents_with_resources always returns proper format" do
      check all(
              memory <- float(min: 0.0, max: 1.0),
              cpu <- float(min: 0.0, max: 1.0),
              max_runs: 20
            ) do
        # Use evolved arity 3 signature (memory, cpu, impl)
        result = Discovery.find_agents_with_resources(memory, cpu, nil)

        case validate_discovery_result(result) do
          :ok ->
            :ok

          {:error, reason} ->
            flunk(
              "Discovery.find_agents_with_resources violated contract for memory=#{memory}, cpu=#{cpu}: #{inspect(reason)}"
            )
        end
      end
    end

    property "Discovery.find_least_loaded_agents always returns proper format" do
      check all(
              capability <-
                one_of([
                  constant(:inference),
                  constant(:training),
                  constant(:coordination)
                ]),
              count <- integer(1..10),
              max_runs: 20
            ) do
        # Use evolved arity 3 signature (capability, count, impl)
        result = Discovery.find_least_loaded_agents(capability, count, nil)

        case validate_discovery_result(result) do
          :ok ->
            :ok

          {:error, reason} ->
            flunk(
              "Discovery.find_least_loaded_agents violated contract for #{capability}, count=#{count}: #{inspect(reason)}"
            )
        end
      end
    end
  end

  describe "Mock contract validation (regression prevention)" do
    @doc """
    This test validates the MockDiscovery used in coordination tests.
    It prevents the regression we just fixed where mocks returned raw lists.
    """
    test "MockDiscovery from coordination tests follows proper contract" do
      # Use the MockDiscovery from coordination_test.exs
      defmodule TestMockDiscovery do
        def find_capable_and_healthy(capability, impl \\ nil)

        def find_capable_and_healthy(:inference, _impl) do
          {:ok,
           [
             {"agent1", self(), %{capability: :inference, health_status: :healthy}},
             {"agent2", self(), %{capability: :training, health_status: :healthy}}
           ]}
        end

        def find_capable_and_healthy(:non_existent, _impl) do
          {:ok, []}
        end

        def find_capable_and_healthy(capability, _impl) do
          {:ok,
           [
             {"test_agent", self(), %{capability: capability, health_status: :healthy}}
           ]}
        end

        def find_agents_with_resources(min_memory, min_cpu, impl \\ nil)

        def find_agents_with_resources(_min_memory, _min_cpu, _impl) do
          {:ok,
           [
             {"resource_agent", self(), %{resources: %{memory_available: 0.8, cpu_available: 0.7}}}
           ]}
        end

        def find_least_loaded_agents(capability, count \\ 5, impl \\ nil)

        def find_least_loaded_agents(capability, count, _impl) do
          agents =
            for i <- 1..count do
              {"agent_#{i}", self(), %{capability: capability, health_status: :healthy}}
            end

          {:ok, agents}
        end
      end

      # This should pass - if it fails, we have a contract violation
      assert validate_discovery_contract(TestMockDiscovery) == :ok
    end

    test "detects contract violations in bad mocks" do
      # Create a mock that violates the contract (like the old broken mocks)
      defmodule BadMockDiscovery do
        def find_capable_and_healthy(capability, impl \\ nil)

        def find_capable_and_healthy(_capability, _impl) do
          # This is wrong - should return {:ok, [...]} not raw list
          [{"agent1", self(), %{}}]
        end

        def find_agents_with_resources(min_memory, min_cpu, impl \\ nil)

        def find_agents_with_resources(_min_memory, _min_cpu, _impl) do
          # This is wrong - should return {:ok, [...]} not raw list  
          []
        end

        def find_least_loaded_agents(capability, count \\ 5, impl \\ nil)

        def find_least_loaded_agents(_capability, _count, _impl) do
          # This is wrong - should return {:ok, [...]} not raw list
          [{"agent1", self(), %{}}]
        end
      end

      # This should detect violations
      {:error, violations} = validate_discovery_contract(BadMockDiscovery)

      # Should have 3 violations (one for each function)
      assert length(violations) == 3

      # All should be contract violations about missing {:ok, ...} wrapper
      Enum.each(violations, fn violation ->
        assert {:contract_violation, MABEAM.DiscoveryContractTest.BadMockDiscovery, _function,
                {:missing_ok_tuple, _msg}} = violation
      end)
    end
  end

  describe "Discovery result format validation" do
    test "accepts valid {:ok, agents} format" do
      valid_result =
        {:ok,
         [
           {"agent1", self(), %{capability: :inference, health_status: :healthy}},
           {"agent2", self(), %{capability: :training, health_status: :healthy}}
         ]}

      assert validate_discovery_result(valid_result) == :ok
    end

    test "accepts valid {:error, reason} format" do
      assert validate_discovery_result({:error, :not_found}) == :ok
      assert validate_discovery_result({:error, :service_unavailable}) == :ok
    end

    test "rejects raw lists (the old broken format)" do
      invalid_result = [
        {"agent1", self(), %{capability: :inference}}
      ]

      {:error, {:missing_ok_tuple, _msg}} = validate_discovery_result(invalid_result)
    end

    test "rejects nil returns" do
      {:error, {:invalid_return, _msg}} = validate_discovery_result(nil)
    end

    test "validates agent tuple format" do
      # Valid agent tuple
      assert validate_agent_tuple({"agent1", self(), %{capability: :inference}}) == []

      # Invalid agent tuple (wrong number of elements)
      violations = validate_agent_tuple({"agent1", self()})
      assert length(violations) == 1
      assert {:invalid_tuple_format, _msg} = hd(violations)

      # Invalid metadata (not a map)
      violations = validate_agent_tuple({"agent1", self(), "not_a_map"})
      assert length(violations) == 1
      assert {:invalid_metadata, _msg} = hd(violations)
    end
  end

  describe "Migration utilities" do
    test "upgrade_discovery_mock_result fixes common violations" do
      # Raw list should be wrapped in {:ok, ...}
      assert upgrade_discovery_mock_result([{"agent1", self(), %{}}]) ==
               {:ok, [{"agent1", self(), %{}}]}

      # nil should become {:error, :not_found}
      assert upgrade_discovery_mock_result(nil) == {:error, :not_found}

      # Already correct format should pass through
      correct = {:ok, [{"agent1", self(), %{}}]}
      assert upgrade_discovery_mock_result(correct) == correct

      error = {:error, :service_down}
      assert upgrade_discovery_mock_result(error) == error
    end
  end
end
