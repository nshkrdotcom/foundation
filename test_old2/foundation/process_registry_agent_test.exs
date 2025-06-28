defmodule Foundation.ProcessRegistryAgentTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Foundation.ProcessRegistry
  alias Foundation.Types.AgentInfo

  setup do
    # Ensure clean state for each test
    namespace = {:test, make_ref()}
    
    on_exit(fn ->
      # Cleanup any registered agents in test namespace
      try do
        agents = ProcessRegistry.list_agents(namespace)
        for {agent_id, _pid, _metadata} <- agents do
          ProcessRegistry.unregister(namespace, agent_id)
        end
      rescue
        _ -> :ok
      end
    end)
    
    {:ok, namespace: namespace}
  end

  describe "agent registration with comprehensive metadata" do
    test "registers agent with complete agent metadata", %{namespace: namespace} do
      agent_metadata = %AgentInfo{
        id: :ml_agent_1,
        type: :ml_agent,
        capabilities: [:nlp, :classification, :generation],
        health: :healthy,
        state: :ready,
        resource_usage: %{memory: 0.7, cpu: 0.4, network: 5, storage: 0.2},
        coordination_state: %{
          active_consensus: [],
          active_barriers: [],
          held_locks: [],
          leadership_roles: []
        },
        last_health_check: DateTime.utc_now(),
        configuration: %{model_type: "transformer", batch_size: 32},
        metadata: %{version: "1.0.0", created_by: "test"}
      }

      pid = spawn(fn -> Process.sleep(1000) end)

      assert :ok = ProcessRegistry.register_agent(
        namespace,
        :ml_agent_1,
        pid,
        agent_metadata
      )

      assert {:ok, {^pid, returned_metadata}} = 
        ProcessRegistry.lookup_agent(namespace, :ml_agent_1)

      assert %AgentInfo{} = returned_metadata
      assert returned_metadata.id == :ml_agent_1
      assert returned_metadata.type == :ml_agent
      assert :nlp in returned_metadata.capabilities
      assert returned_metadata.health == :healthy
      assert returned_metadata.resource_usage.memory == 0.7
    end

    test "validates agent metadata schema", %{namespace: namespace} do
      pid = spawn(fn -> Process.sleep(1000) end)

      # Test with invalid metadata
      invalid_metadata = %{
        type: :invalid_type,
        capabilities: "not_a_list",
        health: :invalid_health
      }

      assert {:error, _reason} = ProcessRegistry.register_agent(
        namespace,
        :invalid_agent,
        pid,
        invalid_metadata
      )
    end

    test "updates agent metadata", %{namespace: namespace} do
      pid = spawn(fn -> Process.sleep(1000) end)
      
      initial_metadata = %AgentInfo{
        id: :test_agent,
        type: :agent,
        health: :healthy,
        capabilities: [:general]
      }

      ProcessRegistry.register_agent(namespace, :test_agent, pid, initial_metadata)

      # Update agent health and capabilities
      updated_metadata = %AgentInfo{
        initial_metadata | 
        health: :degraded,
        capabilities: [:general, :specialized],
        resource_usage: %{memory: 0.95, cpu: 0.8}
      }

      assert :ok = ProcessRegistry.update_agent_metadata(
        namespace, 
        :test_agent, 
        updated_metadata
      )

      {:ok, {^pid, metadata}} = ProcessRegistry.lookup_agent(namespace, :test_agent)
      assert metadata.health == :degraded
      assert :specialized in metadata.capabilities
      assert metadata.resource_usage.memory == 0.95
    end
  end

  describe "agent capability-based discovery" do
    test "discovers agents by single capability", %{namespace: namespace} do
      # Register multiple agents with different capabilities
      agents = [
        {:nlp_agent_1, [:nlp, :tokenization], :healthy},
        {:nlp_agent_2, [:nlp, :classification], :healthy}, 
        {:ml_agent_1, [:training, :inference], :healthy},
        {:coord_agent_1, [:coordination, :scheduling], :healthy}
      ]

      for {agent_id, capabilities, health} <- agents do
        pid = spawn(fn -> Process.sleep(1000) end)
        metadata = %AgentInfo{
          id: agent_id,
          type: :agent, 
          capabilities: capabilities,
          health: health
        }
        ProcessRegistry.register_agent(namespace, agent_id, pid, metadata)
      end

      # Test capability-based queries
      nlp_agents = ProcessRegistry.lookup_agents_by_capability(namespace, :nlp)
      assert length(nlp_agents) == 2
      
      agent_ids = Enum.map(nlp_agents, fn {agent_id, _pid, _metadata} -> agent_id end)
      assert :nlp_agent_1 in agent_ids
      assert :nlp_agent_2 in agent_ids

      training_agents = ProcessRegistry.lookup_agents_by_capability(namespace, :training)
      assert length(training_agents) == 1
      assert {:ml_agent_1, _pid, _metadata} = hd(training_agents)
    end

    test "discovers agents by multiple capabilities", %{namespace: namespace} do
      agents = [
        {:multi_agent_1, [:nlp, :classification, :training], :healthy},
        {:multi_agent_2, [:nlp, :generation], :healthy},
        {:single_agent, [:classification], :healthy}
      ]

      for {agent_id, capabilities, health} <- agents do
        pid = spawn(fn -> Process.sleep(1000) end)
        metadata = %AgentInfo{
          id: agent_id,
          type: :agent,
          capabilities: capabilities,
          health: health
        }
        ProcessRegistry.register_agent(namespace, agent_id, pid, metadata)
      end

      # Find agents with both :nlp AND :classification
      matching_agents = ProcessRegistry.lookup_agents_by_capabilities(
        namespace, 
        [:nlp, :classification]
      )
      
      assert length(matching_agents) == 1
      assert {:multi_agent_1, _pid, _metadata} = hd(matching_agents)
    end

    test "filters agents by health status", %{namespace: namespace} do
      agents = [
        {:healthy_agent_1, [:nlp], :healthy},
        {:healthy_agent_2, [:nlp], :healthy},
        {:degraded_agent, [:nlp], :degraded},
        {:unhealthy_agent, [:nlp], :unhealthy}
      ]

      for {agent_id, capabilities, health} <- agents do
        pid = spawn(fn -> Process.sleep(1000) end)
        metadata = %AgentInfo{
          id: agent_id,
          type: :agent,
          capabilities: capabilities,
          health: health
        }
        ProcessRegistry.register_agent(namespace, agent_id, pid, metadata)
      end

      # Get only healthy agents with NLP capability
      healthy_nlp_agents = ProcessRegistry.lookup_healthy_agents_by_capability(
        namespace, 
        :nlp
      )
      
      assert length(healthy_nlp_agents) == 2
      agent_ids = Enum.map(healthy_nlp_agents, fn {id, _pid, _meta} -> id end)
      assert :healthy_agent_1 in agent_ids
      assert :healthy_agent_2 in agent_ids
      refute :degraded_agent in agent_ids
      refute :unhealthy_agent in agent_ids
    end
  end

  describe "agent health monitoring" do
    test "tracks agent health changes over time", %{namespace: namespace} do
      pid = spawn(fn -> Process.sleep(1000) end)
      
      initial_metadata = %AgentInfo{
        id: :health_test_agent,
        type: :agent,
        health: :healthy,
        last_health_check: DateTime.utc_now()
      }

      ProcessRegistry.register_agent(namespace, :health_test_agent, pid, initial_metadata)

      # Simulate health degradation
      degraded_time = DateTime.utc_now()
      degraded_metadata = %AgentInfo{
        initial_metadata | 
        health: :degraded,
        last_health_check: degraded_time
      }
      
      ProcessRegistry.update_agent_metadata(namespace, :health_test_agent, degraded_metadata)

      {:ok, {^pid, metadata}} = ProcessRegistry.lookup_agent(namespace, :health_test_agent)
      assert metadata.health == :degraded
      assert DateTime.compare(metadata.last_health_check, degraded_time) == :eq

      # Get health history
      health_history = ProcessRegistry.get_agent_health_history(namespace, :health_test_agent)
      assert length(health_history) >= 2
    end

    test "provides system-wide health overview", %{namespace: namespace} do
      # Register agents with different health states
      health_states = [:healthy, :healthy, :degraded, :unhealthy]
      
      for {i, health} <- Enum.with_index(health_states) do
        pid = spawn(fn -> Process.sleep(1000) end)
        metadata = %AgentInfo{
          id: :"agent_#{i}",
          type: :agent,
          health: health,
          capabilities: [:test]
        }
        ProcessRegistry.register_agent(namespace, :"agent_#{i}", pid, metadata)
      end

      health_overview = ProcessRegistry.get_system_health_overview(namespace)
      
      assert health_overview.total_agents == 4
      assert health_overview.healthy_count == 2
      assert health_overview.degraded_count == 1
      assert health_overview.unhealthy_count == 1
      assert health_overview.health_percentage == 0.5  # 2/4 healthy
    end
  end

  describe "agent resource monitoring" do
    test "tracks agent resource usage", %{namespace: namespace} do
      pid = spawn(fn -> Process.sleep(1000) end)
      
      resource_usage = %{
        memory: 0.75,
        cpu: 0.85,
        network: 100,
        storage: 0.4,
        custom: %{gpu_memory: 0.9}
      }

      metadata = %AgentInfo{
        id: :resource_agent,
        type: :ml_agent,
        resource_usage: resource_usage,
        capabilities: [:inference]
      }

      ProcessRegistry.register_agent(namespace, :resource_agent, pid, metadata)

      # Query agents by resource constraints
      high_memory_agents = ProcessRegistry.lookup_agents_by_resource_usage(
        namespace,
        :memory,
        0.7  # threshold
      )
      
      assert length(high_memory_agents) == 1
      assert {:resource_agent, ^pid, _metadata} = hd(high_memory_agents)
    end

    test "provides resource usage aggregation", %{namespace: namespace} do
      agents_data = [
        {:agent_1, %{memory: 0.5, cpu: 0.3}},
        {:agent_2, %{memory: 0.7, cpu: 0.6}},
        {:agent_3, %{memory: 0.9, cpu: 0.8}}
      ]

      for {agent_id, resource_usage} <- agents_data do
        pid = spawn(fn -> Process.sleep(1000) end)
        metadata = %AgentInfo{
          id: agent_id,
          type: :agent,
          resource_usage: resource_usage,
          capabilities: [:test]
        }
        ProcessRegistry.register_agent(namespace, agent_id, pid, metadata)
      end

      resource_stats = ProcessRegistry.get_resource_usage_stats(namespace)
      
      assert resource_stats.average_memory_usage == 0.7  # (0.5 + 0.7 + 0.9) / 3
      assert resource_stats.max_memory_usage == 0.9
      assert resource_stats.agents_count == 3
    end
  end

  describe "agent coordination state" do
    test "tracks coordination participation", %{namespace: namespace} do
      pid = spawn(fn -> Process.sleep(1000) end)
      
      coordination_state = %{
        active_consensus: [:model_selection_round_1],
        active_barriers: [:training_phase_complete],
        held_locks: ["resource_allocation_lock"],
        leadership_roles: [:coordinator]
      }

      metadata = %AgentInfo{
        id: :coord_participant,
        type: :coordination_agent,
        coordination_state: coordination_state,
        capabilities: [:coordination]
      }

      ProcessRegistry.register_agent(namespace, :coord_participant, pid, metadata)

      # Query agents by coordination activity
      active_coordinators = ProcessRegistry.lookup_agents_in_coordination(namespace)
      assert length(active_coordinators) == 1

      consensus_participants = ProcessRegistry.lookup_agents_in_consensus(
        namespace, 
        :model_selection_round_1
      )
      assert length(consensus_participants) == 1
    end
  end

  property "agent metadata consistency under concurrent operations" do
    check all(
      agent_count <- integer(1..10),
      capability_sets <- list_of(list_of(atom(), min_length: 1), min_length: 1)
    ) do
      namespace = {:test, make_ref()}
      
      # Test concurrent agent registration maintains metadata consistency
      tasks = for i <- 1..agent_count do
        Task.async(fn ->
          pid = spawn(fn -> Process.sleep(100) end)
          capabilities = Enum.at(capability_sets, rem(i, length(capability_sets)))
          
          metadata = %AgentInfo{
            id: :"agent_#{i}",
            type: :agent,
            capabilities: capabilities,
            health: :healthy
          }

          ProcessRegistry.register_agent(namespace, :"agent_#{i}", pid, metadata)
        end)
      end

      # Wait for all registrations
      Enum.each(tasks, &Task.await/1)

      # Verify all agents registered correctly
      for i <- 1..agent_count do
        assert {:ok, {_pid, _metadata}} = 
          ProcessRegistry.lookup_agent(namespace, :"agent_#{i}")
      end

      # Test capability-based queries work correctly
      for capability <- Enum.uniq(List.flatten(capability_sets)) do
        agents_with_capability = ProcessRegistry.lookup_agents_by_capability(
          namespace, 
          capability
        )

        expected_count = Enum.count(1..agent_count, fn i ->
          capabilities = Enum.at(capability_sets, rem(i, length(capability_sets)))
          capability in capabilities
        end)

        assert length(agents_with_capability) == expected_count
      end

      # Cleanup
      for i <- 1..agent_count do
        ProcessRegistry.unregister(namespace, :"agent_#{i}")
      end
    end
  end

  describe "backward compatibility" do
    test "existing ProcessRegistry API still works", %{namespace: namespace} do
      pid = spawn(fn -> Process.sleep(1000) end)
      
      # Test basic registration (legacy API)
      assert :ok = ProcessRegistry.register(namespace, :legacy_service, pid)
      assert {:ok, ^pid} = ProcessRegistry.lookup(namespace, :legacy_service)
      
      # Test with metadata (legacy API)
      basic_metadata = %{type: :service, version: "1.0"}
      assert :ok = ProcessRegistry.register(namespace, :legacy_with_meta, pid, basic_metadata)
      
      assert {:ok, {^pid, ^basic_metadata}} = ProcessRegistry.lookup(
        namespace, 
        :legacy_with_meta
      )
    end

    test "agent-aware APIs don't interfere with legacy registrations", %{namespace: namespace} do
      # Register legacy service
      legacy_pid = spawn(fn -> Process.sleep(1000) end)
      ProcessRegistry.register(namespace, :legacy_service, legacy_pid)

      # Register agent-aware service
      agent_pid = spawn(fn -> Process.sleep(1000) end)
      agent_metadata = %AgentInfo{
        id: :modern_agent,
        type: :agent,
        capabilities: [:test]
      }
      ProcessRegistry.register_agent(namespace, :modern_agent, agent_pid, agent_metadata)

      # Both should be accessible through their respective APIs
      assert {:ok, ^legacy_pid} = ProcessRegistry.lookup(namespace, :legacy_service)
      assert {:ok, {^agent_pid, %AgentInfo{}}} = ProcessRegistry.lookup_agent(
        namespace, 
        :modern_agent
      )

      # Legacy list should only show legacy registrations
      legacy_services = ProcessRegistry.list_services(namespace)
      assert {:legacy_service, ^legacy_pid} in legacy_services
      refute {:modern_agent, ^agent_pid} in legacy_services

      # Agent list should only show agent registrations
      agents = ProcessRegistry.list_agents(namespace)
      assert {:modern_agent, ^agent_pid, %AgentInfo{}} in agents
    end
  end
end