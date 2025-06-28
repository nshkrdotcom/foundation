defmodule MABEAM.CoordinationHierarchicalTest do
  @moduledoc """
  Tests for hierarchical coordination algorithms in the coordination module.

  This test suite validates:
  - Multi-level agent hierarchy construction and management
  - Delegated consensus protocols with cluster representatives
  - Load balancing across hierarchical levels
  - Fault tolerance and leader election in hierarchical structures
  - Performance optimization for large agent teams (1000+ agents)
  """

  use ExUnit.Case, async: false
  alias MABEAM.{Coordination, ProcessRegistry, Types}

  setup do
    # Start all required services
    case start_supervised({ProcessRegistry, [test_mode: true]}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    case start_supervised({Coordination, [test_mode: true]}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    # Create test agents for hierarchical coordination
    agent_configs = create_hierarchical_agent_configs(20)

    # Register agents
    Enum.each(agent_configs, &ProcessRegistry.register_agent/1)

    # Start agents
    started_agents =
      for config <- agent_configs do
        {:ok, pid} = ProcessRegistry.start_agent(config.id)
        {config.id, pid}
      end

    %{agents: started_agents, agent_configs: agent_configs}
  end

  describe "Hierarchical coordination initialization" do
    test "creates hierarchical coordination with cluster structure", %{agents: agents} do
      # Use first 12 agents for 3-level hierarchy (4 clusters of 3 agents each)
      hierarchical_agents = agents |> Enum.take(12) |> Enum.map(&elem(&1, 0))
      proposal = "Large-scale decision requiring hierarchical coordination"

      # Start hierarchical coordination
      result =
        Coordination.start_hierarchical_consensus(proposal, hierarchical_agents,
          cluster_size: 3,
          max_levels: 3,
          delegation_strategy: :expertise_based
        )

      assert {:ok, session_id} = result
      assert is_binary(session_id)

      # Verify session was created with hierarchical structure
      {:ok, session_status} = Coordination.get_session_status(session_id)
      assert session_status.type == :hierarchical_consensus
      assert session_status.participants == hierarchical_agents
      assert session_status.metadata.task_specification.proposal == proposal
      assert session_status.metadata.task_specification.cluster_size == 3
      assert session_status.metadata.task_specification.max_levels == 3
      assert session_status.metadata.task_specification.delegation_strategy == :expertise_based
      assert session_status.status in [:initializing, :active]

      # Verify hierarchical state structure
      hierarchical_state = session_status.state
      assert Map.has_key?(hierarchical_state, :hierarchy_levels)
      assert Map.has_key?(hierarchical_state, :cluster_representatives)
      assert Map.has_key?(hierarchical_state, :delegation_tree)
      assert Map.has_key?(hierarchical_state, :current_level)
      # Start at leaf level
      assert hierarchical_state.current_level == 0
    end

    test "automatically calculates optimal hierarchy structure", %{agents: agents} do
      # Use 16 agents for auto-optimization
      hierarchical_agents = agents |> Enum.take(16) |> Enum.map(&elem(&1, 0))
      proposal = "Auto-optimized hierarchical decision"

      result =
        Coordination.start_hierarchical_consensus(proposal, hierarchical_agents,
          auto_optimize: true,
          target_efficiency: 0.85
        )

      assert {:ok, session_id} = result

      {:ok, session_status} = Coordination.get_session_status(session_id)
      hierarchical_state = session_status.state

      # Verify auto-optimization created reasonable structure
      assert hierarchical_state.total_levels >= 2
      # Reasonable for 16 agents
      assert hierarchical_state.total_levels <= 4
      assert is_map(hierarchical_state.hierarchy_levels)
      assert map_size(hierarchical_state.hierarchy_levels) == hierarchical_state.total_levels
    end

    test "handles insufficient agents for hierarchical coordination" do
      # Use only 2 agents (insufficient for meaningful hierarchy)
      insufficient_agents = [:agent_1, :agent_2]
      proposal = "This should fail due to insufficient agents"

      result =
        Coordination.start_hierarchical_consensus(proposal, insufficient_agents, cluster_size: 3)

      assert {:error, {:insufficient_agents_for_hierarchy, min_required, actual_count}} = result
      # Need at least 2 levels with 3 agents each
      assert min_required >= 6
      assert actual_count == 2
    end
  end

  describe "Multi-level hierarchy construction" do
    test "constructs proper 3-level hierarchy with designated representatives", %{agents: agents} do
      hierarchical_agents = agents |> Enum.take(15) |> Enum.map(&elem(&1, 0))

      {:ok, session_id} =
        Coordination.start_hierarchical_consensus(
          "3-level hierarchy test",
          hierarchical_agents,
          cluster_size: 3,
          max_levels: 3
        )

      {:ok, session_status} = Coordination.get_session_status(session_id)
      hierarchical_state = session_status.state

      # Level 0: 15 agents in 5 clusters (3 each)
      level_0 = hierarchical_state.hierarchy_levels[0]
      assert length(level_0.clusters) == 5
      assert Enum.all?(level_0.clusters, fn cluster -> length(cluster.members) == 3 end)

      # Level 1: 5 representatives in 2 clusters (3 and 2)
      level_1 = hierarchical_state.hierarchy_levels[1]
      assert length(level_1.clusters) <= 2

      # Level 2: Final decision level
      level_2 = hierarchical_state.hierarchy_levels[2]
      assert length(level_2.clusters) == 1
      final_cluster = hd(level_2.clusters)
      assert length(final_cluster.members) <= 3

      # Verify representatives are properly designated
      all_representatives =
        hierarchical_state.cluster_representatives |> Map.values() |> List.flatten()

      # 5 from level 0 + 2 from level 1
      assert length(all_representatives) == 7
    end

    test "supports different clustering strategies", %{agents: agents} do
      hierarchical_agents = agents |> Enum.take(12) |> Enum.map(&elem(&1, 0))

      strategies = [:random, :expertise_based, :load_balanced, :geographic]

      for strategy <- strategies do
        {:ok, session_id} =
          Coordination.start_hierarchical_consensus(
            "Test #{strategy} clustering",
            hierarchical_agents,
            cluster_size: 4,
            clustering_strategy: strategy
          )

        {:ok, session_status} = Coordination.get_session_status(session_id)
        assert session_status.metadata.task_specification.clustering_strategy == strategy
      end
    end

    test "maintains cluster balance within tolerance", %{agents: agents} do
      # 13 doesn't divide evenly
      hierarchical_agents = agents |> Enum.take(13) |> Enum.map(&elem(&1, 0))

      {:ok, session_id} =
        Coordination.start_hierarchical_consensus(
          "Balance test",
          hierarchical_agents,
          cluster_size: 4,
          # Allow 25% variance in cluster sizes
          balance_tolerance: 0.25
        )

      {:ok, session_status} = Coordination.get_session_status(session_id)
      hierarchical_state = session_status.state

      level_0 = hierarchical_state.hierarchy_levels[0]
      cluster_sizes = Enum.map(level_0.clusters, fn cluster -> length(cluster.members) end)

      # Verify cluster sizes are within tolerance
      min_size = Enum.min(cluster_sizes)
      max_size = Enum.max(cluster_sizes)
      variance = (max_size - min_size) / max_size
      assert variance <= 0.25
    end
  end

  describe "Delegated consensus protocols" do
    test "executes bottom-up consensus with delegation", %{agents: agents} do
      hierarchical_agents = agents |> Enum.take(9) |> Enum.map(&elem(&1, 0))

      {:ok, session_id} =
        Coordination.start_hierarchical_consensus(
          "Bottom-up consensus test",
          hierarchical_agents,
          cluster_size: 3,
          consensus_strategy: :bottom_up
        )

      # Simulate consensus process
      {:ok, delegation_result} =
        Coordination.execute_hierarchical_consensus(session_id, %{
          decision_data: %{option: "A", rationale: "Best choice for efficiency"},
          timeout: 30_000
        })

      assert delegation_result.consensus_reached == true
      assert Map.has_key?(delegation_result, :final_decision)
      assert Map.has_key?(delegation_result, :delegation_path)
      assert Map.has_key?(delegation_result, :participation_metrics)

      # Verify delegation path shows bottom-up flow
      # At least 2 levels
      assert length(delegation_result.delegation_path) >= 2
    end

    test "handles representative failures during consensus", %{agents: agents} do
      hierarchical_agents = agents |> Enum.take(12) |> Enum.map(&elem(&1, 0))

      {:ok, session_id} =
        Coordination.start_hierarchical_consensus(
          "Fault tolerance test",
          hierarchical_agents,
          cluster_size: 4,
          fault_tolerance: :automatic_replacement
        )

      # Simulate representative failure
      {:ok, session_status} = Coordination.get_session_status(session_id)
      hierarchical_state = session_status.state

      # Pick a representative to simulate failure
      representative_id =
        hierarchical_state.cluster_representatives |> Map.values() |> List.flatten() |> hd()

      result = Coordination.handle_representative_failure(session_id, representative_id)
      assert {:ok, replacement_info} = result

      # Verify replacement was selected
      assert Map.has_key?(replacement_info, :replacement_representative)
      assert Map.has_key?(replacement_info, :cluster_id)
      assert replacement_info.replacement_representative != representative_id
    end

    test "supports different delegation strategies", %{agents: agents} do
      hierarchical_agents = agents |> Enum.take(12) |> Enum.map(&elem(&1, 0))

      strategies = [:round_robin, :expertise_based, :load_based, :performance_history]

      for strategy <- strategies do
        {:ok, session_id} =
          Coordination.start_hierarchical_consensus(
            "Delegation strategy: #{strategy}",
            hierarchical_agents,
            cluster_size: 3,
            delegation_strategy: strategy
          )

        {:ok, session_status} = Coordination.get_session_status(session_id)
        assert session_status.metadata.task_specification.delegation_strategy == strategy

        # Verify strategy-specific state is initialized
        hierarchical_state = session_status.state
        assert Map.has_key?(hierarchical_state, :delegation_state)
      end
    end
  end

  describe "Load balancing and performance optimization" do
    test "distributes computational load across hierarchy levels", %{agents: agents} do
      # Use more agents to test load balancing
      hierarchical_agents = agents |> Enum.take(16) |> Enum.map(&elem(&1, 0))

      {:ok, session_id} =
        Coordination.start_hierarchical_consensus(
          "Load balancing test",
          hierarchical_agents,
          cluster_size: 4,
          load_balancing: :adaptive,
          enable_metrics: true
        )

      # Execute consensus and measure load distribution
      {:ok, result} =
        Coordination.execute_hierarchical_consensus(session_id, %{
          decision_data: %{complex_computation: true},
          measure_performance: true
        })

      # Verify load metrics are collected
      assert Map.has_key?(result, :performance_metrics)
      performance = result.performance_metrics

      assert Map.has_key?(performance, :level_load_distribution)
      assert Map.has_key?(performance, :representative_workload)
      assert Map.has_key?(performance, :total_coordination_time)

      # Verify load is reasonably distributed
      load_variance = performance.level_load_distribution[:variance]
      # Load should be relatively balanced
      assert load_variance < 0.5
    end

    test "adapts hierarchy structure based on performance feedback", %{agents: agents} do
      hierarchical_agents = agents |> Enum.take(20) |> Enum.map(&elem(&1, 0))

      {:ok, session_id} =
        Coordination.start_hierarchical_consensus(
          "Adaptive restructuring test",
          hierarchical_agents,
          cluster_size: 5,
          adaptive_restructuring: true,
          performance_threshold: 0.7
        )

      # Simulate poor performance to trigger restructuring
      {:ok, initial_structure} = Coordination.get_hierarchy_structure(session_id)

      result =
        Coordination.adapt_hierarchy_structure(session_id, %{
          # Below threshold
          performance_score: 0.6,
          bottleneck_level: 1,
          suggested_optimization: :reduce_cluster_size
        })

      assert {:ok, adaptation_result} = result
      assert adaptation_result.restructuring_applied == true

      {:ok, updated_structure} = Coordination.get_hierarchy_structure(session_id)

      # Verify structure was optimized
      assert updated_structure != initial_structure
      assert Map.has_key?(adaptation_result, :performance_improvement_estimate)
    end

    test "handles large-scale coordination efficiently", %{} do
      # Test with a large number of virtual agents (for performance testing)
      large_agent_list = for i <- 1..100, do: :"large_agent_#{i}"

      {:ok, session_id} =
        Coordination.start_hierarchical_consensus(
          "Large-scale test",
          large_agent_list,
          cluster_size: 8,
          max_levels: 4,
          optimization_mode: :large_scale
        )

      start_time = System.monotonic_time(:millisecond)

      {:ok, result} =
        Coordination.execute_hierarchical_consensus(session_id, %{
          decision_data: %{simple_vote: "yes"},
          timeout: 60_000
        })

      end_time = System.monotonic_time(:millisecond)
      coordination_time = end_time - start_time

      # Large-scale coordination should complete in reasonable time
      # Less than 30 seconds
      assert coordination_time < 30_000
      assert result.consensus_reached == true
      assert Map.has_key?(result, :efficiency_metrics)

      # Verify scalability metrics
      efficiency = result.efficiency_metrics
      # Should handle at least 3 agents per second
      assert efficiency.agents_per_second > 3.0
    end
  end

  describe "Hierarchical session management" do
    test "integrates with existing session management infrastructure", %{agents: agents} do
      hierarchical_agents = agents |> Enum.take(12) |> Enum.map(&elem(&1, 0))

      {:ok, session_id} =
        Coordination.start_hierarchical_consensus(
          "Integration test",
          hierarchical_agents,
          cluster_size: 4
        )

      # Verify session appears in active sessions
      {:ok, active_sessions} = Coordination.list_active_sessions()
      session_ids = Enum.map(active_sessions, & &1.id)
      assert session_id in session_ids

      # Verify session type is correctly reported
      hierarchical_sessions = Enum.filter(active_sessions, &(&1.type == :hierarchical_consensus))
      assert length(hierarchical_sessions) >= 1

      # Test session cancellation
      assert :ok = Coordination.cancel_session(session_id)

      # Verify session is properly cleaned up
      case Coordination.get_session_status(session_id) do
        {:ok, status} -> assert status.status in [:cancelled, :terminated]
        {:error, :not_found} -> :ok
      end
    end

    test "provides hierarchical analytics and metrics", %{agents: agents} do
      hierarchical_agents = agents |> Enum.take(9) |> Enum.map(&elem(&1, 0))

      {:ok, session_id} =
        Coordination.start_hierarchical_consensus(
          "Analytics test",
          hierarchical_agents,
          cluster_size: 3,
          enable_analytics: true
        )

      # Get hierarchical-specific analytics
      {:ok, analytics} = Coordination.get_hierarchical_analytics(session_id)

      assert Map.has_key?(analytics, :hierarchy_depth)
      assert Map.has_key?(analytics, :cluster_distribution)
      assert Map.has_key?(analytics, :representative_efficiency)
      assert Map.has_key?(analytics, :delegation_latency)
      assert Map.has_key?(analytics, :fault_tolerance_score)

      # Verify analytics make sense for our setup
      assert analytics.hierarchy_depth >= 2
      assert analytics.cluster_distribution.total_clusters >= 3
      assert analytics.fault_tolerance_score > 0.0
    end
  end

  describe "Edge cases and error handling" do
    test "handles empty agent list gracefully" do
      result =
        Coordination.start_hierarchical_consensus(
          "Empty agent test",
          [],
          cluster_size: 3
        )

      assert {:error, :empty_agent_list} = result
    end

    test "validates hierarchical configuration parameters" do
      agents_list = [:a1, :a2, :a3, :a4, :a5, :a6]

      invalid_configs = [
        # Invalid cluster size
        %{cluster_size: 0},
        # Invalid max levels  
        %{cluster_size: 10, max_levels: 0},
        # Invalid tolerance
        %{cluster_size: 3, balance_tolerance: -0.1},
        # Invalid strategy
        %{cluster_size: 3, delegation_strategy: :invalid_strategy}
      ]

      for invalid_config <- invalid_configs do
        result =
          Coordination.start_hierarchical_consensus(
            "Invalid config test",
            agents_list,
            invalid_config
          )

        assert {:error, {:invalid_hierarchical_config, _reason}} = result
      end
    end

    test "handles hierarchical deadlocks and circular delegation" do
      hierarchical_agents = [:agent_1, :agent_2, :agent_3, :agent_4, :agent_5, :agent_6]

      {:ok, session_id} =
        Coordination.start_hierarchical_consensus(
          "Deadlock prevention test",
          hierarchical_agents,
          cluster_size: 3,
          deadlock_prevention: true,
          delegation_timeout: 5_000
        )

      # Simulate a scenario that could cause deadlock
      result =
        Coordination.handle_delegation_deadlock(session_id, %{
          deadlock_type: :circular_delegation,
          affected_representatives: [:agent_1, :agent_4],
          timeout_occurred: true
        })

      assert {:ok, resolution} = result
      assert Map.has_key?(resolution, :resolution_strategy)
      assert Map.has_key?(resolution, :new_delegation_path)
      assert resolution.deadlock_resolved == true
    end
  end

  # Helper functions

  defp create_hierarchical_agent_configs(count) do
    for i <- 1..count do
      # Assign different expertise levels for testing
      expertise_level =
        case rem(i, 4) do
          0 -> :expert
          1 -> :intermediate
          2 -> :novice
          3 -> :specialist
        end

      capabilities =
        case expertise_level do
          :expert -> [:consensus, :coordination, :leadership, :analysis]
          :intermediate -> [:consensus, :coordination]
          :novice -> [:consensus]
          :specialist -> [:consensus, :specialized_task]
        end

      Types.new_agent_config(
        :"hierarchical_agent_#{i}",
        HierarchicalTestAgent,
        [],
        capabilities: capabilities,
        expertise_level: expertise_level,
        load_capacity: :rand.uniform(100)
      )
    end
  end
end

# Test agent module for hierarchical coordination tests
defmodule HierarchicalTestAgent do
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(args) do
    {:ok,
     %{
       id: Keyword.get(args, :id, :test_agent),
       state: :ready,
       expertise_level: Keyword.get(args, :expertise_level, :intermediate),
       load_capacity: Keyword.get(args, :load_capacity, 50)
     }}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:delegate_decision, decision_data}, _from, state) do
    # Simulate decision delegation processing
    # Random processing time
    processing_time = :rand.uniform(100)
    :timer.sleep(processing_time)

    response = %{
      decision: decision_data,
      confidence: 0.8 + :rand.uniform() * 0.2,
      processing_time: processing_time
    }

    {:reply, {:ok, response}, state}
  end

  def handle_cast({:update_state, new_state}, _state) do
    {:noreply, new_state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
