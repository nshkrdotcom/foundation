defmodule FoundationTest do
  use ExUnit.Case, async: true
  doctest Foundation

  # Mock implementation for testing explicit pass-through
  defmodule MockRegistry do
    defstruct []
  end

  defmodule MockCoordination do
    defstruct []
  end

  defmodule MockInfrastructure do
    defstruct []
  end

  # Protocol implementations for mocks
  defimpl Foundation.Registry, for: MockRegistry do
    def register(_impl, key, pid, metadata) do
      send(self(), {:register_called, key, pid, metadata})
      :ok
    end

    def lookup(_impl, key) do
      send(self(), {:lookup_called, key})
      {:ok, {self(), %{capability: :test}}}
    end

    def find_by_attribute(_impl, attr, value) do
      send(self(), {:find_by_attribute_called, attr, value})
      {:ok, [{:test_key, self(), %{capability: :test}}]}
    end

    def query(_impl, criteria) do
      send(self(), {:query_called, criteria})
      {:ok, [{:test_key, self(), %{capability: :test}}]}
    end

    def count(_impl) do
      send(self(), {:count_called})
      {:ok, 1}
    end

    def select(_impl, criteria) do
      send(self(), {:select_called, criteria})
      {:ok, [{:test_key, self(), %{capability: :test}}]}
    end

    def indexed_attributes(_impl) do
      send(self(), {:indexed_attributes_called})
      [:capability, :health_status]
    end

    def list_all(_impl, filter) do
      send(self(), {:list_all_called, filter})
      [{:test_key, self(), %{capability: :test}}]
    end

    def protocol_version(_impl) do
      send(self(), {:protocol_version_called})
      {:ok, "1.1"}
    end

    def update_metadata(_impl, key, metadata) do
      send(self(), {:update_metadata_called, key, metadata})
      :ok
    end

    def unregister(_impl, key) do
      send(self(), {:unregister_called, key})
      :ok
    end
  end

  defimpl Foundation.Coordination, for: MockCoordination do
    def start_consensus(_impl, participants, proposal, timeout) do
      send(self(), {:start_consensus_called, participants, proposal, timeout})
      {:ok, :consensus_ref}
    end

    def vote(_impl, ref, participant, vote) do
      send(self(), {:vote_called, ref, participant, vote})
      :ok
    end

    def get_consensus_result(_impl, ref) do
      send(self(), {:get_consensus_result_called, ref})
      {:ok, :consensus_result}
    end

    def create_barrier(_impl, barrier_id, count) do
      send(self(), {:create_barrier_called, barrier_id, count})
      :ok
    end

    def arrive_at_barrier(_impl, barrier_id, participant) do
      send(self(), {:arrive_at_barrier_called, barrier_id, participant})
      :ok
    end

    def wait_for_barrier(_impl, barrier_id, timeout) do
      send(self(), {:wait_for_barrier_called, barrier_id, timeout})
      :ok
    end

    def acquire_lock(_impl, lock_id, holder, timeout) do
      send(self(), {:acquire_lock_called, lock_id, holder, timeout})
      {:ok, :lock_ref}
    end

    def release_lock(_impl, lock_ref) do
      send(self(), {:release_lock_called, lock_ref})
      :ok
    end

    def get_lock_status(_impl, lock_id) do
      send(self(), {:get_lock_status_called, lock_id})
      {:ok, :available}
    end

    def protocol_version(_impl) do
      send(self(), {:coordination_protocol_version_called})
      {:ok, "1.0"}
    end
  end

  defimpl Foundation.Infrastructure, for: MockInfrastructure do
    def register_circuit_breaker(_impl, service_id, config) do
      send(self(), {:register_circuit_breaker_called, service_id, config})
      :ok
    end

    def execute_protected(_impl, service_id, function, context) do
      send(self(), {:execute_protected_called, service_id, context})
      function.()
    end

    def get_circuit_status(_impl, service_id) do
      send(self(), {:get_circuit_status_called, service_id})
      {:ok, :closed}
    end

    def setup_rate_limiter(_impl, limiter_id, config) do
      send(self(), {:setup_rate_limiter_called, limiter_id, config})
      :ok
    end

    def check_rate_limit(_impl, limiter_id, identifier) do
      send(self(), {:check_rate_limit_called, limiter_id, identifier})
      :ok
    end

    def get_rate_limit_status(_impl, limiter_id, identifier) do
      send(self(), {:get_rate_limit_status_called, limiter_id, identifier})
      {:ok, %{}}
    end

    def monitor_resource(_impl, resource_id, config) do
      send(self(), {:monitor_resource_called, resource_id, config})
      :ok
    end

    def get_resource_usage(_impl, resource_id) do
      send(self(), {:get_resource_usage_called, resource_id})
      {:ok, %{}}
    end

    def protocol_version(_impl) do
      send(self(), {:infrastructure_protocol_version_called})
      {:ok, "1.0"}
    end
  end

  describe "Foundation Registry API with explicit pass-through" do
    test "register/4 uses explicit implementation when provided" do
      mock_registry = %MockRegistry{}
      assert :ok = Foundation.register("key", self(), %{capability: :test}, mock_registry)
      assert_received {:register_called, "key", _, %{capability: :test}}
    end

    test "lookup/2 uses explicit implementation when provided" do
      mock_registry = %MockRegistry{}
      assert {:ok, {_, %{capability: :test}}} = Foundation.lookup("key", mock_registry)
      assert_received {:lookup_called, "key"}
    end

    test "find_by_attribute/3 uses explicit implementation when provided" do
      mock_registry = %MockRegistry{}
      assert {:ok, results} = Foundation.find_by_attribute(:capability, :test, mock_registry)
      assert length(results) == 1
      assert_received {:find_by_attribute_called, :capability, :test}
    end

    test "query/2 uses explicit implementation when provided" do
      mock_registry = %MockRegistry{}
      criteria = [{[:capability], :test, :eq}]
      assert {:ok, results} = Foundation.query(criteria, mock_registry)
      assert length(results) == 1
      assert_received {:query_called, ^criteria}
    end

    test "indexed_attributes/1 uses explicit implementation when provided" do
      mock_registry = %MockRegistry{}
      assert attrs = Foundation.indexed_attributes(mock_registry)
      assert :capability in attrs
      assert_received {:indexed_attributes_called}
    end

    test "list_all/2 uses explicit implementation when provided" do
      mock_registry = %MockRegistry{}
      filter_fn = fn _ -> true end
      assert results = Foundation.list_all(filter_fn, mock_registry)
      assert length(results) == 1
      assert_received {:list_all_called, ^filter_fn}
    end

    test "update_metadata/3 uses explicit implementation when provided" do
      mock_registry = %MockRegistry{}
      new_metadata = %{capability: :updated}
      assert :ok = Foundation.update_metadata("key", new_metadata, mock_registry)
      assert_received {:update_metadata_called, "key", ^new_metadata}
    end

    test "unregister/2 uses explicit implementation when provided" do
      mock_registry = %MockRegistry{}
      assert :ok = Foundation.unregister("key", mock_registry)
      assert_received {:unregister_called, "key"}
    end
  end

  describe "Foundation Coordination API with explicit pass-through" do
    test "start_consensus/4 uses explicit implementation when provided" do
      mock_coordination = %MockCoordination{}
      participants = [:agent1, :agent2]
      proposal = %{action: :scale_up}

      assert {:ok, :consensus_ref} =
               Foundation.start_consensus(participants, proposal, 30_000, mock_coordination)

      assert_received {:start_consensus_called, ^participants, ^proposal, 30_000}
    end

    test "vote/4 uses explicit implementation when provided" do
      mock_coordination = %MockCoordination{}
      assert :ok = Foundation.vote(:ref, :agent1, :yes, mock_coordination)
      assert_received {:vote_called, :ref, :agent1, :yes}
    end

    test "get_consensus_result/2 uses explicit implementation when provided" do
      mock_coordination = %MockCoordination{}
      assert {:ok, :consensus_result} = Foundation.get_consensus_result(:ref, mock_coordination)
      assert_received {:get_consensus_result_called, :ref}
    end

    test "create_barrier/3 uses explicit implementation when provided" do
      mock_coordination = %MockCoordination{}
      assert :ok = Foundation.create_barrier(:barrier1, 3, mock_coordination)
      assert_received {:create_barrier_called, :barrier1, 3}
    end

    test "arrive_at_barrier/3 uses explicit implementation when provided" do
      mock_coordination = %MockCoordination{}
      assert :ok = Foundation.arrive_at_barrier(:barrier1, :agent1, mock_coordination)
      assert_received {:arrive_at_barrier_called, :barrier1, :agent1}
    end

    test "wait_for_barrier/3 uses explicit implementation when provided" do
      mock_coordination = %MockCoordination{}
      assert :ok = Foundation.wait_for_barrier(:barrier1, 60_000, mock_coordination)
      assert_received {:wait_for_barrier_called, :barrier1, 60_000}
    end

    test "acquire_lock/4 uses explicit implementation when provided" do
      mock_coordination = %MockCoordination{}
      assert {:ok, :lock_ref} = Foundation.acquire_lock(:lock1, :agent1, 30_000, mock_coordination)
      assert_received {:acquire_lock_called, :lock1, :agent1, 30_000}
    end

    test "release_lock/2 uses explicit implementation when provided" do
      mock_coordination = %MockCoordination{}
      assert :ok = Foundation.release_lock(:lock_ref, mock_coordination)
      assert_received {:release_lock_called, :lock_ref}
    end
  end

  describe "Foundation Infrastructure API with explicit pass-through" do
    test "execute_protected/4 uses explicit implementation when provided" do
      mock_infrastructure = %MockInfrastructure{}
      test_function = fn -> {:ok, :result} end
      context = %{agent_id: :agent1}

      assert {:ok, :result} =
               Foundation.execute_protected(:service1, test_function, context, mock_infrastructure)

      assert_received {:execute_protected_called, :service1, ^context}
    end

    test "setup_rate_limiter/3 uses explicit implementation when provided" do
      mock_infrastructure = %MockInfrastructure{}
      config = %{rate: 100, per: 60_000, strategy: :token_bucket}

      assert :ok = Foundation.setup_rate_limiter(:api_calls, config, mock_infrastructure)
      assert_received {:setup_rate_limiter_called, :api_calls, ^config}
    end

    test "check_rate_limit/3 uses explicit implementation when provided" do
      mock_infrastructure = %MockInfrastructure{}
      assert :ok = Foundation.check_rate_limit(:api_calls, :agent1, mock_infrastructure)
      assert_received {:check_rate_limit_called, :api_calls, :agent1}
    end
  end

  describe "error handling for missing configuration" do
    test "raises helpful error when registry implementation not configured" do
      # Store current config
      current_config = Application.get_env(:foundation, :registry_impl)

      try do
        # Clear the config temporarily
        Application.delete_env(:foundation, :registry_impl)

        # Since Foundation.register uses ErrorHandler, it will return an error instead of raising
        result = Foundation.register("key", self(), %{})

        # Check that we get an error with the expected message
        assert {:error, %Foundation.ErrorHandler.Error{reason: exception}} = result
        assert is_exception(exception)
        assert exception.message =~ "Foundation.Registry implementation not configured"
      after
        # Restore the config
        if current_config do
          Application.put_env(:foundation, :registry_impl, current_config)
        end
      end
    end
  end

  describe "API documentation and examples" do
    test "registry operations work with explicit implementation pattern" do
      # This test demonstrates the usage patterns shown in module docs
      mock_registry = %MockRegistry{}

      # Register an agent
      metadata = %{capability: :inference, health_status: :healthy}
      :ok = Foundation.register("agent_1", self(), metadata, mock_registry)

      # Look it up
      {:ok, {_pid, returned_metadata}} = Foundation.lookup("agent_1", mock_registry)
      # Mock returns test data
      assert returned_metadata.capability == :test

      # Query with criteria (atomic multi-criteria search)
      criteria = [
        {[:capability], :inference, :eq},
        {[:health_status], :healthy, :eq}
      ]

      {:ok, matching_agents} = Foundation.query(criteria, mock_registry)
      assert length(matching_agents) == 1

      # Verify all calls were made with explicit implementation
      assert_received {:register_called, "agent_1", _, ^metadata}
      assert_received {:lookup_called, "agent_1"}
      assert_received {:query_called, ^criteria}
    end

    test "coordination operations demonstrate barrier pattern" do
      mock_coordination = %MockCoordination{}

      # Create a barrier for 3 agents
      :ok = Foundation.create_barrier(:checkpoint_1, 3, mock_coordination)

      # Agents arrive at barrier
      :ok = Foundation.arrive_at_barrier(:checkpoint_1, :agent1, mock_coordination)
      :ok = Foundation.arrive_at_barrier(:checkpoint_1, :agent2, mock_coordination)

      # Wait for all to arrive (would block in real implementation)
      :ok = Foundation.wait_for_barrier(:checkpoint_1, 60_000, mock_coordination)

      # Verify coordination calls
      assert_received {:create_barrier_called, :checkpoint_1, 3}
      assert_received {:arrive_at_barrier_called, :checkpoint_1, :agent1}
      assert_received {:arrive_at_barrier_called, :checkpoint_1, :agent2}
      assert_received {:wait_for_barrier_called, :checkpoint_1, 60_000}
    end

    test "infrastructure operations demonstrate circuit breaker pattern" do
      mock_infrastructure = %MockInfrastructure{}

      # Execute a protected operation
      risky_operation = fn ->
        # Simulate external API call that might fail
        {:ok, %{data: "external_data"}}
      end

      context = %{service: :external_api, retry_count: 0}

      {:ok, %{data: "external_data"}} =
        Foundation.execute_protected(
          :external_service,
          risky_operation,
          context,
          mock_infrastructure
        )

      # Verify infrastructure integration
      assert_received {:execute_protected_called, :external_service, ^context}
    end
  end

  describe "protocol version and compatibility" do
    test "implementations can provide version information" do
      # Test that the explicit pass-through maintains protocol compatibility
      mock_registry = %MockRegistry{}
      attrs = Foundation.indexed_attributes(mock_registry)

      # Verify that standard attributes are supported
      assert :capability in attrs
      assert :health_status in attrs

      assert_received {:indexed_attributes_called}
    end
  end
end
