defmodule Foundation.Coordination.AgentAwareServiceTest do
  use ExUnit.Case, async: false

  alias Foundation.Coordination.Service, as: CoordinationService
  alias Foundation.ProcessRegistry
  alias Foundation.Types.AgentInfo

  setup do
    namespace = {:test, make_ref()}

    # Start CoordinationService with test configuration
    {:ok, _pid} = CoordinationService.start_link([
      consensus_timeout: 5000,
      leader_election_timeout: 3000,
      barrier_timeout: 10000,
      health_check_interval: 100,
      namespace: namespace
    ])

    # Register multiple test agents with different capabilities
    agents = [
      {:ml_agent_1, [:inference, :training], :healthy},
      {:ml_agent_2, [:inference], :healthy},
      {:coord_agent_1, [:coordination], :healthy},
      {:degraded_agent, [:inference], :degraded},
      {:specialist_agent, [:specialized_ml], :healthy}
    ]

    for {agent_id, capabilities, health} <- agents do
      pid = spawn(fn -> Process.sleep(5000) end)
      metadata = %AgentInfo{
        id: agent_id,
        type: :agent,
        capabilities: capabilities,
        health: health,
        resource_usage: %{memory: 0.5, cpu: 0.3},
        coordination_state: %{
          active_consensus: [],
          active_barriers: [],
          held_locks: [],
          leadership_roles: []
        }
      }

      ProcessRegistry.register_agent(namespace, agent_id, pid, metadata)
    end

    on_exit(fn ->
      try do
        for {agent_id, _, _} <- agents do
          ProcessRegistry.unregister(namespace, agent_id)
        end
      rescue
        _ -> :ok
      end
    end)

    {:ok, namespace: namespace}
  end

  describe "agent-aware consensus" do
    test "consensus considers agent health in participation", %{namespace: namespace} do
      participants = [:ml_agent_1, :ml_agent_2, :degraded_agent]

      proposal = %{
        action: :model_selection,
        models: ["gpt-4", "claude-3"],
        criteria: :accuracy,
        voting_strategy: :health_weighted
      }

      {:ok, result} = CoordinationService.consensus(
        :model_selection_round_1,
        participants,
        proposal,
        %{
          strategy: :majority,
          timeout: 5_000,
          health_consideration: true,
          namespace: namespace
        }
      )

      # Verify consensus completed successfully
      assert result.status == :accepted
      assert result.consensus_id == :model_selection_round_1
      assert length(result.participant_votes) <= 3

      # Degraded agent should have reduced voting weight or be excluded
      degraded_vote = Enum.find(result.participant_votes, &(&1.agent_id == :degraded_agent))
      if degraded_vote do
        assert degraded_vote.weight < 1.0  # Reduced weight due to health
      end
    end

    test "consensus filters participants by required capabilities", %{namespace: namespace} do
      # Only inference agents should participate in inference-related decisions
      all_agents = [:ml_agent_1, :ml_agent_2, :coord_agent_1, :degraded_agent]

      proposal = %{
        action: :inference_optimization,
        required_capabilities: [:inference],
        optimization_params: %{batch_size: 32, max_tokens: 1000}
      }

      {:ok, result} = CoordinationService.consensus(
        :inference_optimization_round_1,
        all_agents,
        proposal,
        %{
          strategy: :capability_filtered_majority,
          namespace: namespace
        }
      )

      assert result.status == :accepted

      # Only agents with inference capability should have participated
      participating_agents = Enum.map(result.participant_votes, & &1.agent_id)
      assert :ml_agent_1 in participating_agents
      assert :ml_agent_2 in participating_agents
      assert :degraded_agent in participating_agents  # Has inference capability
      refute :coord_agent_1 in participating_agents  # Lacks inference capability
    end

    test "consensus adapts to agent availability during process", %{namespace: namespace} do
      participants = [:ml_agent_1, :ml_agent_2]

      proposal = %{
        action: :dynamic_consensus_test,
        adaptive: true
      }

      # Start consensus
      consensus_task = Task.async(fn ->
        CoordinationService.consensus(
          :dynamic_consensus,
          participants,
          proposal,
          %{
            strategy: :adaptive_majority,
            timeout: 10_000,
            namespace: namespace
          }
        )
      end)

      # Simulate agent becoming unavailable during consensus
      Process.sleep(500)  # Let consensus start

      # Update agent health to critical (simulating failure)
      critical_metadata = %AgentInfo{
        id: :ml_agent_2,
        type: :agent,
        capabilities: [:inference],
        health: :critical,
        resource_usage: %{memory: 0.99, cpu: 0.95}
      }
      ProcessRegistry.update_agent_metadata(namespace, :ml_agent_2, critical_metadata)

      # Consensus should adapt and complete with available agents
      {:ok, result} = Task.await(consensus_task, 15_000)

      assert result.status in [:accepted, :adapted]
      assert result.adaptation_reason != nil
      assert "agent_unavailable" in result.adaptation_reason or
             "health_degraded" in result.adaptation_reason
    end
  end

  describe "capability-based leader election" do
    test "elects leader based on agent capabilities and performance", %{namespace: namespace} do
      candidates = [:ml_agent_1, :ml_agent_2, :coord_agent_1, :specialist_agent]

      {:ok, election_result} = CoordinationService.elect_leader(
        candidates,
        %{
          election_type: :capability_based,
          required_capabilities: [:coordination],
          performance_weight: 0.3,
          experience_weight: 0.4,
          health_weight: 0.3,
          namespace: namespace
        }
      )

      # Coordination agent should be preferred for leadership due to capability match
      assert election_result.leader == :coord_agent_1
      assert election_result.election_reason =~ "capability_match"
      assert length(election_result.candidate_scores) == 4

      # Verify scoring included capability matching
      coord_score = Enum.find(election_result.candidate_scores, &(&1.agent_id == :coord_agent_1))
      assert coord_score.capability_score > 0.8  # High score for coordination capability
    end

    test "considers agent load and availability in leader election", %{namespace: namespace} do
      # Update agents with different resource usage
      high_load_metadata = %AgentInfo{
        id: :ml_agent_1,
        type: :agent,
        capabilities: [:inference, :training],
        health: :healthy,
        resource_usage: %{memory: 0.9, cpu: 0.85},  # High load
        coordination_state: %{
          active_consensus: [:consensus1, :consensus2],  # Already coordinating
          active_barriers: [],
          held_locks: ["resource_lock"],
          leadership_roles: [:model_trainer]
        }
      }

      low_load_metadata = %AgentInfo{
        id: :ml_agent_2,
        type: :agent,
        capabilities: [:inference],
        health: :healthy,
        resource_usage: %{memory: 0.3, cpu: 0.2},  # Low load
        coordination_state: %{
          active_consensus: [],
          active_barriers: [],
          held_locks: [],
          leadership_roles: []
        }
      }

      ProcessRegistry.update_agent_metadata(namespace, :ml_agent_1, high_load_metadata)
      ProcessRegistry.update_agent_metadata(namespace, :ml_agent_2, low_load_metadata)

      candidates = [:ml_agent_1, :ml_agent_2]

      {:ok, result} = CoordinationService.elect_leader(
        candidates,
        %{
          election_type: :load_balanced,
          namespace: namespace
        }
      )

      # Lower load agent should be preferred
      assert result.leader == :ml_agent_2
      assert result.election_reason =~ "load_balanced"

      # Verify load consideration in scoring
      ml_agent_2_score = Enum.find(result.candidate_scores, &(&1.agent_id == :ml_agent_2))
      ml_agent_1_score = Enum.find(result.candidate_scores, &(&1.agent_id == :ml_agent_1))

      assert ml_agent_2_score.availability_score > ml_agent_1_score.availability_score
    end

    test "handles leader failure and re-election", %{namespace: namespace} do
      candidates = [:coord_agent_1, :ml_agent_1]

      # Initial election
      {:ok, initial_result} = CoordinationService.elect_leader(
        candidates,
        %{namespace: namespace}
      )

      initial_leader = initial_result.leader

      # Simulate leader failure
      failed_metadata = %AgentInfo{
        id: initial_leader,
        type: :agent,
        capabilities: [:coordination],
        health: :critical,  # Failed
        resource_usage: %{memory: 0.99, cpu: 0.99}
      }
      ProcessRegistry.update_agent_metadata(namespace, initial_leader, failed_metadata)

      # Trigger re-election
      {:ok, reelection_result} = CoordinationService.elect_leader(
        candidates,
        %{
          election_type: :failure_recovery,
          failed_leader: initial_leader,
          namespace: namespace
        }
      )

      # New leader should be elected
      assert reelection_result.leader != initial_leader
      assert reelection_result.election_reason =~ "failure_recovery"
      assert reelection_result.previous_leader == initial_leader
    end
  end

  describe "barrier synchronization with agent context" do
    test "creates barrier with agent capability requirements", %{namespace: namespace} do
      participants = [:ml_agent_1, :ml_agent_2]

      # Create barrier for training completion that requires training capability
      barrier_config = %{
        required_capabilities: [:training],
        timeout: 10_000,
        health_threshold: :healthy
      }

      :ok = CoordinationService.create_barrier(
        :training_phase_complete,
        participants,
        barrier_config,
        %{namespace: namespace}
      )

      # Simulate agents reaching barrier with different capabilities
      barrier_tasks = for agent_id <- participants do
        Task.async(fn ->
          CoordinationService.wait_for_barrier(
            :training_phase_complete,
            agent_id,
            %{namespace: namespace}
          )
        end)
      end

      # All agents should complete (both have training capabilities or are filtered)
      results = Task.await_many(barrier_tasks, 15_000)

      # At least one agent with training capability should succeed
      successful_results = Enum.filter(results, &(&1 == :ok))
      assert length(successful_results) > 0
    end

    test "barrier waits for minimum healthy agent threshold", %{namespace: namespace} do
      participants = [:ml_agent_1, :ml_agent_2, :degraded_agent]

      # Create barrier requiring at least 2 healthy agents
      barrier_config = %{
        min_healthy_agents: 2,
        timeout: 5_000
      }

      CoordinationService.create_barrier(
        :health_threshold_barrier,
        participants,
        barrier_config,
        %{namespace: namespace}
      )

      # Start barrier wait tasks
      barrier_tasks = for agent_id <- participants do
        Task.async(fn ->
          CoordinationService.wait_for_barrier(
            :health_threshold_barrier,
            agent_id,
            %{namespace: namespace}
          )
        end)
      end

      # Should complete since we have 2 healthy agents (ml_agent_1, ml_agent_2)
      results = Task.await_many(barrier_tasks, 10_000)
      successful_results = Enum.filter(results, &(&1 == :ok))
      assert length(successful_results) >= 2
    end

    test "barrier handles agent health changes during wait", %{namespace: namespace} do
      participants = [:ml_agent_1, :ml_agent_2]

      CoordinationService.create_barrier(
        :dynamic_health_barrier,
        participants,
        %{health_monitoring: true, timeout: 10_000},
        %{namespace: namespace}
      )

      # Start barrier wait
      barrier_task = Task.async(fn ->
        CoordinationService.wait_for_barrier(
          :dynamic_health_barrier,
          :ml_agent_1,
          %{namespace: namespace}
        )
      end)

      # Simulate ml_agent_2 becoming unhealthy during wait
      Process.sleep(500)

      unhealthy_metadata = %AgentInfo{
        id: :ml_agent_2,
        type: :agent,
        capabilities: [:inference],
        health: :unhealthy,
        resource_usage: %{memory: 0.95, cpu: 0.9}
      }
      ProcessRegistry.update_agent_metadata(namespace, :ml_agent_2, unhealthy_metadata)

      # ml_agent_1 should still complete the barrier (adapted to health change)
      result = Task.await(barrier_task, 12_000)
      assert result == :ok or match?({:ok, _}, result)
    end
  end

  describe "resource-aware coordination" do
    test "coordination considers agent resource constraints", %{namespace: namespace} do
      high_memory_agent = :degraded_agent

      # Update agent to show high resource usage
      high_resource_metadata = %AgentInfo{
        id: high_memory_agent,
        type: :agent,
        capabilities: [:inference],
        health: :degraded,
        resource_usage: %{memory: 0.95, cpu: 0.8}  # Very high usage
      }
      ProcessRegistry.update_agent_metadata(namespace, high_memory_agent, high_resource_metadata)

      participants = [:ml_agent_1, :ml_agent_2, high_memory_agent]

      proposal = %{
        action: :resource_intensive_task,
        resource_requirements: %{
          memory_per_agent: 0.3,  # Would push high_memory_agent over limit
          cpu_per_agent: 0.2
        }
      }

      {:ok, result} = CoordinationService.consensus(
        :resource_aware_consensus,
        participants,
        proposal,
        %{
          strategy: :resource_aware_majority,
          resource_validation: true,
          namespace: namespace
        }
      )

      assert result.status in [:accepted, :modified]

      # High resource agent should either be excluded or have modified participation
      if result.status == :modified do
        assert result.modifications =~ "resource_constraints"
      end

      # Resource allocation should be tracked
      assert Map.has_key?(result, :resource_allocations)
    end

    test "coordinates resource allocation across agents", %{namespace: namespace} do
      agents = [:ml_agent_1, :ml_agent_2, :specialist_agent]

      resource_request = %{
        total_memory: 2.0,  # 2GB total
        total_cpu: 3.0,     # 3 cores total
        allocation_strategy: :fair_share
      }

      {:ok, allocation_result} = CoordinationService.coordinate_resource_allocation(
        :shared_training_resources,
        agents,
        resource_request,
        %{namespace: namespace}
      )

      assert allocation_result.status == :allocated
      assert length(allocation_result.agent_allocations) == 3

      # Verify fair distribution
      total_allocated_memory = allocation_result.agent_allocations
                              |> Enum.map(& &1.memory_allocation)
                              |> Enum.sum()

      assert_in_delta total_allocated_memory, 2.0, 0.1  # Within 10% of requested

      # Each agent should have reasonable allocation
      for allocation <- allocation_result.agent_allocations do
        assert allocation.memory_allocation > 0
        assert allocation.cpu_allocation > 0
        assert allocation.agent_id in agents
      end
    end

    test "handles resource contention and negotiation", %{namespace: namespace} do
      # Set up agents with competing resource needs
      agents = [:ml_agent_1, :ml_agent_2]

      competing_requests = [
        %{
          agent_id: :ml_agent_1,
          priority: :high,
          memory_needed: 1.5,  # 1.5GB
          justification: "critical_training_job"
        },
        %{
          agent_id: :ml_agent_2,
          priority: :medium,
          memory_needed: 1.2,  # 1.2GB
          justification: "inference_scaling"
        }
      ]

      # Total available: 2GB, Total requested: 2.7GB (contention)
      available_resources = %{
        memory: 2.0,
        cpu: 2.0
      }

      {:ok, negotiation_result} = CoordinationService.negotiate_resource_allocation(
        :resource_contention_scenario,
        competing_requests,
        available_resources,
        %{
          negotiation_strategy: :priority_weighted,
          timeout: 5000,
          namespace: namespace
        }
      )

      assert negotiation_result.status == :negotiated
      assert length(negotiation_result.final_allocations) == 2

      # Higher priority agent should get larger share
      ml_agent_1_allocation = Enum.find(negotiation_result.final_allocations,
                                      &(&1.agent_id == :ml_agent_1))
      ml_agent_2_allocation = Enum.find(negotiation_result.final_allocations,
                                      &(&1.agent_id == :ml_agent_2))

      assert ml_agent_1_allocation.memory_allocation > ml_agent_2_allocation.memory_allocation

      # Total should not exceed available
      total_memory = ml_agent_1_allocation.memory_allocation + ml_agent_2_allocation.memory_allocation
      assert total_memory <= 2.0
    end
  end

  describe "coordination performance and monitoring" do
    test "tracks coordination performance metrics", %{namespace: namespace} do
      participants = [:ml_agent_1, :ml_agent_2, :coord_agent_1]

      # Perform multiple coordination operations
      for i <- 1..5 do
        proposal = %{action: :performance_test, round: i}

        {:ok, _result} = CoordinationService.consensus(
          :"performance_consensus_#{i}",
          participants,
          proposal,
          %{namespace: namespace}
        )
      end

      # Get coordination performance metrics
      {:ok, metrics} = CoordinationService.get_coordination_metrics(%{
        namespace: namespace
      })

      assert metrics.total_consensus_operations == 5
      assert is_number(metrics.avg_consensus_duration_ms)
      assert is_number(metrics.success_rate)
      assert Map.has_key?(metrics.agent_participation, :ml_agent_1)
      assert Map.has_key?(metrics.agent_participation, :ml_agent_2)
      assert Map.has_key?(metrics.agent_participation, :coord_agent_1)
    end

    test "provides real-time coordination status", %{namespace: namespace} do
      # Start long-running coordination
      participants = [:ml_agent_1, :ml_agent_2]

      consensus_task = Task.async(fn ->
        CoordinationService.consensus(
          :long_running_consensus,
          participants,
          %{action: :complex_decision, duration: 2000},
          %{timeout: 10_000, namespace: namespace}
        )
      end)

      # Check status during operation
      Process.sleep(200)

      {:ok, status} = CoordinationService.get_coordination_status(
        :long_running_consensus,
        %{namespace: namespace}
      )

      assert status.status in [:in_progress, :voting, :calculating]
      assert status.consensus_id == :long_running_consensus
      assert length(status.participants) == 2
      assert is_number(status.elapsed_time_ms)

      # Wait for completion
      {:ok, final_result} = Task.await(consensus_task, 15_000)
      assert final_result.status == :accepted
    end
  end

  describe "coordination failure handling and recovery" do
    test "handles coordination timeout gracefully", %{namespace: namespace} do
      participants = [:ml_agent_1]  # Single agent that won't respond

      proposal = %{action: :timeout_test}

      # Use very short timeout to trigger timeout condition
      result = CoordinationService.consensus(
        :timeout_consensus,
        participants,
        proposal,
        %{
          strategy: :unanimous,  # Requires response from all
          timeout: 100,  # Very short timeout
          namespace: namespace
        }
      )

      assert {:error, reason} = result
      assert reason =~ "timeout" or reason =~ "insufficient_responses"
    end

    test "recovers from agent failures during coordination", %{namespace: namespace} do
      participants = [:ml_agent_1, :ml_agent_2]

      # Start coordination
      consensus_task = Task.async(fn ->
        CoordinationService.consensus(
          :failure_recovery_test,
          participants,
          %{action: :resilience_test},
          %{
            strategy: :fault_tolerant_majority,
            timeout: 8000,
            failure_recovery: true,
            namespace: namespace
          }
        )
      end)

      # Simulate agent failure during coordination
      Process.sleep(500)

      # Make ml_agent_2 unavailable
      critical_metadata = %AgentInfo{
        id: :ml_agent_2,
        type: :agent,
        capabilities: [:inference],
        health: :critical,
        resource_usage: %{memory: 0.99, cpu: 0.99}
      }
      ProcessRegistry.update_agent_metadata(namespace, :ml_agent_2, critical_metadata)

      # Should complete with remaining agents
      {:ok, result} = Task.await(consensus_task, 12_000)

      assert result.status in [:accepted, :accepted_with_failures]
      assert result.failed_agents != nil
      assert :ml_agent_2 in result.failed_agents
    end

    test "maintains coordination state consistency during failures" do
      participants = [:ml_agent_1, :ml_agent_2, :coord_agent_1]

      # Simulate rapid coordination requests with some failures
      tasks = for i <- 1..10 do
        Task.async(fn ->
          # Randomly introduce failures
          if rem(i, 3) == 0 do
            # Fail every 3rd operation
            {:error, "simulated_failure_#{i}"}
          else
            CoordinationService.consensus(
              :"consistency_test_#{i}",
              participants,
              %{action: :consistency_test, round: i},
              %{strategy: :majority, timeout: 2000}
            )
          end
        end)
      end

      results = Task.await_many(tasks, 5000)

      # Some should succeed, some should fail
      successes = Enum.count(results, &match?({:ok, _}, &1))
      failures = Enum.count(results, &match?({:error, _}, &1))

      assert successes > 0
      assert failures > 0
      assert successes + failures == 10

      # System should remain consistent
      {:ok, system_status} = CoordinationService.get_system_status()
      assert system_status.status == :healthy
      assert system_status.active_operations >= 0
    end
  end

  describe "multi-agent workflow coordination" do
    test "coordinates complex multi-stage workflows", %{namespace: namespace} do
      workflow_participants = %{
        preparation: [:ml_agent_1],
        execution: [:ml_agent_1, :ml_agent_2],
        validation: [:ml_agent_2, :specialist_agent],
        coordination: [:coord_agent_1]
      }

      workflow_definition = %{
        stages: [
          %{
            name: :preparation,
            participants: workflow_participants.preparation,
            requirements: %{capabilities: [:training]},
            timeout: 3000
          },
          %{
            name: :execution,
            participants: workflow_participants.execution,
            requirements: %{capabilities: [:inference]},
            timeout: 5000,
            depends_on: [:preparation]
          },
          %{
            name: :validation,
            participants: workflow_participants.validation,
            requirements: %{capabilities: [:specialized_ml, :inference]},
            timeout: 3000,
            depends_on: [:execution]
          }
        ]
      }

      {:ok, workflow_result} = CoordinationService.execute_workflow(
        :complex_ml_workflow,
        workflow_definition,
        %{namespace: namespace}
      )

      assert workflow_result.status == :completed
      assert length(workflow_result.stage_results) == 3

      # Verify stages completed in order
      stage_names = Enum.map(workflow_result.stage_results, & &1.stage_name)
      assert stage_names == [:preparation, :execution, :validation]

      # All stages should have succeeded
      for stage_result <- workflow_result.stage_results do
        assert stage_result.status == :completed
      end
    end

    test "handles workflow failures and provides rollback", %{namespace: namespace} do
      # Workflow that will fail at validation stage
      failing_workflow = %{
        stages: [
          %{
            name: :setup,
            participants: [:ml_agent_1],
            timeout: 2000
          },
          %{
            name: :processing,
            participants: [:ml_agent_2],
            timeout: 2000,
            depends_on: [:setup]
          },
          %{
            name: :failing_validation,
            participants: [:degraded_agent],  # Degraded agent likely to fail
            timeout: 1000,  # Short timeout
            depends_on: [:processing],
            failure_simulation: true
          }
        ],
        rollback_on_failure: true
      }

      result = CoordinationService.execute_workflow(
        :failing_workflow,
        failing_workflow,
        %{namespace: namespace}
      )

      # Should complete with failure
      assert {:ok, workflow_result} = result
      assert workflow_result.status == :failed
      assert workflow_result.failed_stage != nil

      # Should have attempted rollback
      assert workflow_result.rollback_attempted == true
      assert length(workflow_result.rollback_actions) > 0
    end
  end
end