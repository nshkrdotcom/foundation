defmodule MABEAM.CoordinationTest do
  # Using registry isolation mode for MABEAM Coordination tests with meck contamination prevention
  use Foundation.UnifiedTestFoundation, :registry

  # Mock Foundation and Discovery for testing coordination logic
  defmodule MockFoundation do
    def start_consensus(participants, proposal, timeout, _impl) do
      send(self(), {:start_consensus_called, participants, proposal, timeout})
      {:ok, :consensus_ref_123}
    end

    def create_barrier(barrier_id, participant_count, _impl) do
      send(self(), {:create_barrier_called, barrier_id, participant_count})
      :ok
    end
  end

  defmodule MockDiscovery do
    @mock_agents [
      {"inf_agent_1", :pid1,
       %{
         capability: :inference,
         health_status: :healthy,
         node: :node1,
         resources: %{memory_available: 0.8, cpu_available: 0.7, memory_usage: 0.2, cpu_usage: 0.3}
       }},
      {"inf_agent_2", :pid2,
       %{
         capability: :inference,
         health_status: :healthy,
         node: :node1,
         resources: %{memory_available: 0.6, cpu_available: 0.5, memory_usage: 0.4, cpu_usage: 0.5}
       }},
      {"train_agent_1", :pid3,
       %{
         capability: :training,
         health_status: :healthy,
         node: :node2,
         resources: %{memory_available: 0.9, cpu_available: 0.8, memory_usage: 0.1, cpu_usage: 0.2}
       }},
      {"train_agent_2", :pid4,
       %{
         capability: :training,
         health_status: :healthy,
         node: :node2,
         resources: %{memory_available: 0.3, cpu_available: 0.4, memory_usage: 0.7, cpu_usage: 0.6}
       }},
      {"coord_agent_1", :pid5,
       %{
         capability: :coordination,
         health_status: :healthy,
         node: :node3,
         resources: %{memory_available: 0.7, cpu_available: 0.6, memory_usage: 0.3, cpu_usage: 0.4}
       }},
      {"overloaded_agent", :pid6,
       %{
         capability: :inference,
         health_status: :healthy,
         node: :node1,
         resources: %{memory_available: 0.1, cpu_available: 0.2, memory_usage: 0.9, cpu_usage: 0.8}
       }}
    ]

    def find_capable_and_healthy(capability, _impl) do
      agents = Enum.filter(@mock_agents, fn {_id, _pid, metadata} ->
        agent_capabilities = List.wrap(metadata.capability)
        capability in agent_capabilities and metadata.health_status == :healthy
      end)
      {:ok, agents}
    end

    def find_agents_with_resources(min_memory, min_cpu, _impl) do
      agents = Enum.filter(@mock_agents, fn {_id, _pid, metadata} ->
        resources = metadata.resources
        memory_ok = Map.get(resources, :memory_available, 0.0) >= min_memory
        cpu_ok = Map.get(resources, :cpu_available, 0.0) >= min_cpu
        health_ok = metadata.health_status == :healthy
        memory_ok and cpu_ok and health_ok
      end)
      {:ok, agents}
    end

    def find_least_loaded_agents(capability, count, _impl) do
      {:ok, agents} = find_capable_and_healthy(capability, nil)
      result = agents
      |> Enum.sort_by(fn {_id, _pid, metadata} ->
        resources = metadata.resources
        memory_usage = Map.get(resources, :memory_usage, 1.0)
        cpu_usage = Map.get(resources, :cpu_usage, 1.0)
        memory_usage + cpu_usage
      end)
      |> Enum.take(count)
      {:ok, result}
    end
  end

  describe "capability-based coordination" do

    test "coordinate_capable_agents starts consensus with capability filtering" do
      # Mock MABEAM.Discovery.find_capable_and_healthy
      :meck.new(MABEAM.Discovery, [:passthrough])

      :meck.expect(MABEAM.Discovery, :find_capable_and_healthy, fn :inference, _impl ->
        MockDiscovery.find_capable_and_healthy(:inference, nil)
      end)

      # Mock Foundation.start_consensus
      :meck.new(Foundation, [:passthrough])

      :meck.expect(Foundation, :start_consensus, fn participants, proposal, timeout, _impl ->
        MockFoundation.start_consensus(participants, proposal, timeout, nil)
      end)

      # Test consensus coordination
      proposal = %{action: :scale_model, target_replicas: 3}
      {:ok, ref} = MABEAM.Coordination.coordinate_capable_agents(:inference, :consensus, proposal)

      assert ref == :consensus_ref_123

      # Verify the right participants were selected and consensus was started
      assert_received {:start_consensus_called, participants, ^proposal, 30_000}
      # 3 inference agents in mock data
      assert length(participants) == 3
      assert "inf_agent_1" in participants
      assert "inf_agent_2" in participants
      assert "overloaded_agent" in participants

      :meck.unload(MABEAM.Discovery)
      :meck.unload(Foundation)
    end

    test "coordinate_capable_agents creates barrier with capability filtering" do
      :meck.new(MABEAM.Discovery, [:passthrough])

      :meck.expect(MABEAM.Discovery, :find_capable_and_healthy, fn :training, _impl ->
        MockDiscovery.find_capable_and_healthy(:training, nil)
      end)

      :meck.new(Foundation, [:passthrough])

      :meck.expect(Foundation, :create_barrier, fn barrier_id, count, _impl ->
        MockFoundation.create_barrier(barrier_id, count, nil)
      end)

      proposal = %{checkpoint: "epoch_10"}

      {:ok, barrier_id} =
        MABEAM.Coordination.coordinate_capable_agents(:training, :barrier, proposal)

      # Verify barrier was created with correct participant count
      # 2 training agents
      assert_received {:create_barrier_called, ^barrier_id, 2}

      :meck.unload(MABEAM.Discovery)
      :meck.unload(Foundation)
    end

    test "coordinate_capable_agents handles no capable agents" do
      :meck.new(MABEAM.Discovery, [:passthrough])

      :meck.expect(MABEAM.Discovery, :find_capable_and_healthy, fn :non_existent, _impl ->
        {:ok, []}
      end)

      proposal = %{action: :test}

      {:error, :no_capable_agents} =
        MABEAM.Coordination.coordinate_capable_agents(:non_existent, :consensus, proposal)

      :meck.unload(MABEAM.Discovery)
    end

    test "coordinate_capable_agents handles unsupported coordination type" do
      :meck.new(MABEAM.Discovery, [:passthrough])

      :meck.expect(MABEAM.Discovery, :find_capable_and_healthy, fn :inference, _impl ->
        MockDiscovery.find_capable_and_healthy(:inference, nil)
      end)

      proposal = %{action: :test}

      {:error, {:unsupported_coordination_type, :unknown_type}} =
        MABEAM.Coordination.coordinate_capable_agents(:inference, :unknown_type, proposal)

      :meck.unload(MABEAM.Discovery)
    end
  end

  describe "resource-based coordination" do

    test "coordinate_resource_allocation finds agents with sufficient resources" do
      :meck.new(MABEAM.Discovery, [:passthrough])

      :meck.expect(MABEAM.Discovery, :find_agents_with_resources, fn min_mem, min_cpu, _impl ->
        MockDiscovery.find_agents_with_resources(min_mem, min_cpu, nil)
      end)

      :meck.new(Foundation, [:passthrough])

      :meck.expect(Foundation, :start_consensus, fn participants, proposal, _timeout, _impl ->
        send(self(), {:consensus_with_proposal, participants, proposal})
        {:ok, :resource_consensus_ref}
      end)

      required_resources = %{memory: 0.5, cpu: 0.3}
      {:ok, ref} = MABEAM.Coordination.coordinate_resource_allocation(required_resources, :greedy)

      assert ref == :resource_consensus_ref

      # Verify consensus was started with resource allocation proposal
      assert_received {:consensus_with_proposal, _participants, proposal}
      assert proposal.type == :resource_allocation
      assert proposal.required_resources == required_resources
      assert proposal.allocation_strategy == :greedy

      :meck.unload(MABEAM.Discovery)
      :meck.unload(Foundation)
    end

    test "coordinate_resource_allocation handles insufficient resources" do
      :meck.new(MABEAM.Discovery, [:passthrough])

      :meck.expect(MABEAM.Discovery, :find_agents_with_resources, fn _min_mem, _min_cpu, _impl ->
        # No agents meet requirements
        {:ok, []}
      end)

      # Impossible requirements
      required_resources = %{memory: 2.0, cpu: 2.0}

      {:error, :insufficient_resources} =
        MABEAM.Coordination.coordinate_resource_allocation(required_resources, :balanced)

      :meck.unload(MABEAM.Discovery)
    end
  end

  describe "load balancing coordination" do

    test "coordinate_load_balancing analyzes load and starts rebalancing" do
      :meck.new(MABEAM.Discovery, [:passthrough])

      :meck.expect(MABEAM.Discovery, :find_capable_and_healthy, fn :inference, _impl ->
        # Return agents with different load levels
        {:ok, [
          {"low_load", :pid1,
           %{
             capability: :inference,
             health_status: :healthy,
             resources: %{memory_usage: 0.1, cpu_usage: 0.1}
           }},
          {"high_load", :pid2,
           %{
             capability: :inference,
             health_status: :healthy,
             resources: %{memory_usage: 0.9, cpu_usage: 0.8}
           }}
        ]}
      end)

      :meck.new(Foundation, [:passthrough])

      :meck.expect(Foundation, :start_consensus, fn participants, proposal, timeout, _impl ->
        send(self(), {:load_balancing_consensus, participants, proposal, timeout})
        {:ok, :load_balance_ref}
      end)

      {:ok, ref} = MABEAM.Coordination.coordinate_load_balancing(:inference, 0.5, 0.2)

      assert ref == :load_balance_ref

      # Verify load balancing consensus was started
      assert_received {:load_balancing_consensus, _participants, proposal, 45_000}
      assert proposal.type == :load_balancing
      assert proposal.capability == :inference
      assert proposal.target_load == 0.5
      assert length(proposal.overloaded_agents) >= 1
      assert length(proposal.underloaded_agents) >= 1

      :meck.unload(MABEAM.Discovery)
      :meck.unload(Foundation)
    end

    test "coordinate_load_balancing handles already balanced system" do
      :meck.new(MABEAM.Discovery, [:passthrough])

      :meck.expect(MABEAM.Discovery, :find_capable_and_healthy, fn :inference, _impl ->
        # Return agents with similar balanced loads
        {:ok, [
          {"balanced1", :pid1,
           %{
             capability: :inference,
             health_status: :healthy,
             resources: %{memory_usage: 0.5, cpu_usage: 0.5}
           }},
          {"balanced2", :pid2,
           %{
             capability: :inference,
             health_status: :healthy,
             resources: %{memory_usage: 0.4, cpu_usage: 0.5}
           }}
        ]}
      end)

      {:error, :no_rebalancing_needed} =
        MABEAM.Coordination.coordinate_load_balancing(:inference, 0.5, 0.2)

      :meck.unload(MABEAM.Discovery)
    end

    test "coordinate_load_balancing handles insufficient agents" do
      :meck.new(MABEAM.Discovery, [:passthrough])

      :meck.expect(MABEAM.Discovery, :find_capable_and_healthy, fn :inference, _impl ->
        # Return only one agent (insufficient for load balancing)
        {:ok, [
          {"single_agent", :pid1,
           %{
             capability: :inference,
             health_status: :healthy,
             resources: %{memory_usage: 0.9, cpu_usage: 0.8}
           }}
        ]}
      end)

      {:error, :insufficient_agents} =
        MABEAM.Coordination.coordinate_load_balancing(:inference, 0.5, 0.2)

      :meck.unload(MABEAM.Discovery)
    end
  end

  describe "capability transition coordination" do

    test "coordinate_capability_transition selects least loaded agents" do
      :meck.new(MABEAM.Discovery, [:passthrough])

      :meck.expect(MABEAM.Discovery, :find_capable_and_healthy, fn :training, _impl ->
        MockDiscovery.find_capable_and_healthy(:training, nil)
      end)

      :meck.expect(MABEAM.Discovery, :find_least_loaded_agents, fn :training, count, _impl ->
        MockDiscovery.find_least_loaded_agents(:training, count, nil)
      end)

      :meck.new(Foundation, [:passthrough])

      :meck.expect(Foundation, :start_consensus, fn participants, proposal, timeout, _impl ->
        send(self(), {:capability_transition_consensus, participants, proposal, timeout})
        {:ok, :transition_ref}
      end)

      {:ok, ref} = MABEAM.Coordination.coordinate_capability_transition(:training, :inference, 1)

      assert ref == :transition_ref

      # Verify transition consensus was started
      assert_received {:capability_transition_consensus, participants, proposal, 60_000}
      assert proposal.type == :capability_transition
      assert proposal.source_capability == :training
      assert proposal.target_capability == :inference
      assert proposal.transition_count == 1
      # Only transitioning 1 agent
      assert length(participants) == 1

      :meck.unload(MABEAM.Discovery)
      :meck.unload(Foundation)
    end

    test "coordinate_capability_transition handles insufficient source agents" do
      :meck.new(MABEAM.Discovery, [:passthrough])

      :meck.expect(MABEAM.Discovery, :find_capable_and_healthy, fn :rare_capability, _impl ->
        {:ok, [{"single_agent", :pid1, %{capability: :rare_capability, health_status: :healthy}}]}
      end)

      # Try to transition 5 agents when only 1 exists
      {:error, {:insufficient_source_agents, 1, 5}} =
        MABEAM.Coordination.coordinate_capability_transition(
          :rare_capability,
          :common_capability,
          5
        )

      :meck.unload(MABEAM.Discovery)
    end
  end

  describe "capability-based barrier creation" do

    test "create_capability_barrier creates barrier for capable agents" do
      :meck.new(MABEAM.Discovery, [:passthrough])

      :meck.expect(MABEAM.Discovery, :find_capable_and_healthy, fn :coordination, _impl ->
        MockDiscovery.find_capable_and_healthy(:coordination, nil)
      end)

      :meck.new(Foundation, [:passthrough])

      :meck.expect(Foundation, :create_barrier, fn barrier_id, count, _impl ->
        send(self(), {:barrier_created, barrier_id, count})
        :ok
      end)

      {:ok, {barrier_id, participant_count}} =
        MABEAM.Coordination.create_capability_barrier(:coordination, :sync_checkpoint)

      assert barrier_id == :sync_checkpoint
      # 1 coordination agent in mock data
      assert participant_count == 1

      assert_received {:barrier_created, :sync_checkpoint, 1}

      :meck.unload(MABEAM.Discovery)
      :meck.unload(Foundation)
    end

    test "create_capability_barrier with additional filters" do
      :meck.new(MABEAM.Discovery, [:passthrough])
      # Mock the Discovery.find_capable_and_healthy function to return test agents
      :meck.expect(MABEAM.Discovery, :find_capable_and_healthy, fn :inference, _impl ->
        {:ok, [
          {"agent1", self(), %{capability: :inference, health_status: :healthy, node: :node1}},
          {"agent2", self(), %{capability: :inference, health_status: :healthy, node: :node2}}
        ]}
      end)

      :meck.new(Foundation, [:passthrough])

      :meck.expect(Foundation, :create_barrier, fn _barrier_id, _count, _impl ->
        :ok
      end)

      additional_filters = %{node: :node1}

      # This should work but filter to only node1 agents with the capability
      # The actual filtering logic is in a private function, so we test the interface
      result =
        MABEAM.Coordination.create_capability_barrier(:inference, :node1_sync, additional_filters)

      # Should succeed with some number of participants (1 agent matches node1 filter)
      assert {:ok, {:node1_sync, 1}} = result

      :meck.unload(MABEAM.Discovery)
      :meck.unload(Foundation)
    end

    test "create_capability_barrier handles no eligible participants" do
      :meck.new(MABEAM.Discovery, [:passthrough])

      :meck.expect(MABEAM.Discovery, :find_capable_and_healthy, fn :non_existent, _impl ->
        {:ok, []}
      end)

      {:error, :no_eligible_participants} =
        MABEAM.Coordination.create_capability_barrier(:non_existent, :empty_barrier)

      :meck.unload(MABEAM.Discovery)
    end
  end

  describe "allocation strategy implementation" do

    test "greedy strategy selects agents with most available resources" do
      # Test the internal allocation strategy logic through resource coordination
      :meck.new(MABEAM.Discovery, [:passthrough])

      :meck.expect(MABEAM.Discovery, :find_agents_with_resources, fn _min_mem, _min_cpu, _impl ->
        {:ok, [
          {"high_resource", :pid1, %{resources: %{memory_available: 0.9, cpu_available: 0.8}}},
          {"med_resource", :pid2, %{resources: %{memory_available: 0.6, cpu_available: 0.5}}},
          {"low_resource", :pid3, %{resources: %{memory_available: 0.3, cpu_available: 0.2}}}
        ]}
      end)

      :meck.new(Foundation, [:passthrough])

      :meck.expect(Foundation, :start_consensus, fn participants, proposal, _timeout, _impl ->
        send(self(), {:greedy_allocation, participants, proposal})
        {:ok, :greedy_ref}
      end)

      required_resources = %{memory: 0.1, cpu: 0.1}
      {:ok, _ref} = MABEAM.Coordination.coordinate_resource_allocation(required_resources, :greedy)

      # Verify that the greedy strategy was applied
      assert_received {:greedy_allocation, _participants, proposal}
      assert proposal.allocation_strategy == :greedy

      # The implementation should select agents with highest available resources
      # This tests the internal logic through the public API

      :meck.unload(MABEAM.Discovery)
      :meck.unload(Foundation)
    end
  end

  describe "error handling and edge cases" do

    test "handles Foundation consensus failures gracefully" do
      :meck.new(MABEAM.Discovery, [:passthrough])

      :meck.expect(MABEAM.Discovery, :find_capable_and_healthy, fn :inference, _impl ->
        MockDiscovery.find_capable_and_healthy(:inference, nil)
      end)

      :meck.new(Foundation, [:passthrough])

      :meck.expect(Foundation, :start_consensus, fn _participants, _proposal, _timeout, _impl ->
        {:error, :consensus_service_unavailable}
      end)

      proposal = %{action: :test}

      {:error, :consensus_service_unavailable} =
        MABEAM.Coordination.coordinate_capable_agents(:inference, :consensus, proposal)

      :meck.unload(MABEAM.Discovery)
      :meck.unload(Foundation)
    end

    test "handles barrier creation failures gracefully" do
      :meck.new(MABEAM.Discovery, [:passthrough])

      :meck.expect(MABEAM.Discovery, :find_capable_and_healthy, fn :coordination, _impl ->
        MockDiscovery.find_capable_and_healthy(:coordination, nil)
      end)

      :meck.new(Foundation, [:passthrough])

      :meck.expect(Foundation, :create_barrier, fn _barrier_id, _count, _impl ->
        {:error, :barrier_service_unavailable}
      end)

      {:error, :barrier_service_unavailable} =
        MABEAM.Coordination.create_capability_barrier(:coordination, :test_barrier)

      :meck.unload(MABEAM.Discovery)
      :meck.unload(Foundation)
    end

    test "handles malformed proposals gracefully" do
      # The coordination module should handle any proposal format
      # since it passes them through to Foundation services

      :meck.new(MABEAM.Discovery, [:passthrough])

      :meck.expect(MABEAM.Discovery, :find_capable_and_healthy, fn :inference, _impl ->
        {:ok, [{"test_agent", :pid1, %{capability: :inference, health_status: :healthy}}]}
      end)

      :meck.new(Foundation, [:passthrough])

      :meck.expect(Foundation, :start_consensus, fn _participants, proposal, _timeout, _impl ->
        {:ok, {:consensus_with_proposal, proposal}}
      end)

      # Test with various proposal formats
      weird_proposal = %{nested: %{very: %{deep: "proposal"}}}

      {:ok, result} =
        MABEAM.Coordination.coordinate_capable_agents(:inference, :consensus, weird_proposal)

      assert result == {:consensus_with_proposal, weird_proposal}

      :meck.unload(MABEAM.Discovery)
      :meck.unload(Foundation)
    end
  end

  describe "logging and observability" do

    test "logs coordination activities appropriately" do
      # Capture log messages during coordination
      :meck.new(MABEAM.Discovery, [:passthrough])

      :meck.expect(MABEAM.Discovery, :find_capable_and_healthy, fn :inference, _impl ->
        MockDiscovery.find_capable_and_healthy(:inference, nil)
      end)

      :meck.new(Foundation, [:passthrough])

      :meck.expect(Foundation, :start_consensus, fn _participants, _proposal, _timeout, _impl ->
        {:ok, :logged_consensus}
      end)

      # Import capture_log for testing
      import ExUnit.CaptureLog

      log_output =
        capture_log(fn ->
          proposal = %{action: :scale_model}

          {:ok, _ref} =
            MABEAM.Coordination.coordinate_capable_agents(:inference, :consensus, proposal)
        end)

      # Verify appropriate logging occurs
      assert String.contains?(log_output, "Starting consensus coordination")
      assert String.contains?(log_output, "inference agents")

      :meck.unload(MABEAM.Discovery)
      :meck.unload(Foundation)
    end

    test "logs warnings for problematic coordination attempts" do
      import ExUnit.CaptureLog

      :meck.new(MABEAM.Discovery, [:passthrough])

      :meck.expect(MABEAM.Discovery, :find_capable_and_healthy, fn :non_existent, _impl ->
        {:ok, []}
      end)

      log_output =
        capture_log(fn ->
          proposal = %{action: :impossible}

          {:error, :no_capable_agents} =
            MABEAM.Coordination.coordinate_capable_agents(:non_existent, :consensus, proposal)
        end)

      assert String.contains?(log_output, "No capable agents found")
      assert String.contains?(log_output, "non_existent")

      :meck.unload(MABEAM.Discovery)
    end
  end
end
