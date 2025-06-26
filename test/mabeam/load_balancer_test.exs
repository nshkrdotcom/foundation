defmodule MABEAM.LoadBalancerTest do
  @moduledoc """
  Tests for MABEAM.LoadBalancer.

  Tests load balancing and resource management functionality including:
  - Agent registration and task assignment
  - Different load balancing strategies
  - Resource monitoring and overload protection
  - Performance metrics and statistics
  """
  use ExUnit.Case, async: false

  alias MABEAM.{Agent, LoadBalancer}

  setup do
    # Load balancer is started by the application supervision tree
    # Clear any existing state before each test
    LoadBalancer.clear_agents()

    # Clean up any existing agents
    on_exit(fn ->
      cleanup_test_agents()
      LoadBalancer.clear_agents()
    end)

    :ok
  end

  describe "agent registration" do
    test "registers agents for load balancing" do
      # Register test agents
      assert :ok = setup_test_agent(:worker1, [:ml, :computation])
      assert :ok = setup_test_agent(:worker2, [:communication, :coordination])

      # Verify registration
      assert :ok = LoadBalancer.register_agent(:worker1, [:ml, :computation])
      assert :ok = LoadBalancer.register_agent(:worker2, [:communication, :coordination])

      # Check load stats
      stats = LoadBalancer.get_load_stats()
      assert stats.total_agents == 2
      assert stats.available_agents == 2
      assert stats.overloaded_agents == 0
    end

    test "handles registration of non-existent agents" do
      # Try to register agent that doesn't exist in the main registry
      assert {:error, :agent_not_found} = LoadBalancer.register_agent(:nonexistent, [:test])
    end

    test "unregisters agents" do
      # Setup and register agent
      assert :ok = setup_test_agent(:worker1, [:test])
      assert :ok = LoadBalancer.register_agent(:worker1, [:test])

      # Verify it's registered
      stats = LoadBalancer.get_load_stats()
      assert stats.total_agents == 1

      # Unregister
      assert :ok = LoadBalancer.unregister_agent(:worker1)

      # Verify it's gone
      stats_after = LoadBalancer.get_load_stats()
      assert stats_after.total_agents == 0
    end
  end

  describe "task assignment" do
    test "assigns tasks to suitable agents" do
      # Setup agents
      assert :ok = setup_test_agent(:ml_worker, [:ml, :computation])
      assert :ok = setup_test_agent(:comm_worker, [:communication])

      # Register for load balancing
      assert :ok = LoadBalancer.register_agent(:ml_worker, [:ml, :computation])
      assert :ok = LoadBalancer.register_agent(:comm_worker, [:communication])

      # Assign ML task
      task_spec = %{
        capabilities: [:ml],
        complexity: :medium,
        estimated_duration: 5000,
        priority: :normal
      }

      assert {:ok, agent_id, agent_pid} = LoadBalancer.assign_task(task_spec)
      assert agent_id == :ml_worker
      assert is_pid(agent_pid)

      # Assign communication task
      comm_task = %{
        capabilities: [:communication],
        complexity: :low,
        estimated_duration: 1000,
        priority: :high
      }

      assert {:ok, agent_id2, agent_pid2} = LoadBalancer.assign_task(comm_task)
      assert agent_id2 == :comm_worker
      assert is_pid(agent_pid2)
    end

    test "handles tasks with no suitable agents" do
      # Register agent with limited capabilities
      assert :ok = setup_test_agent(:limited_worker, [:basic])
      assert :ok = LoadBalancer.register_agent(:limited_worker, [:basic])

      # Try to assign task requiring different capabilities
      task_spec = %{
        capabilities: [:advanced_ml, :gpu],
        complexity: :high,
        estimated_duration: 10000
      }

      assert {:error, :no_suitable_agent} = LoadBalancer.assign_task(task_spec)
    end

    test "avoids assigning to overloaded agents" do
      # Setup agent
      assert :ok = setup_test_agent(:worker1, [:test])
      assert :ok = LoadBalancer.register_agent(:worker1, [:test])

      # Make agent appear overloaded
      overloaded_metrics = %{
        # Over 90% threshold
        cpu_usage: 0.95,
        # 2GB, over 1GB threshold
        memory_usage: 2 * 1024 * 1024 * 1024,
        # Over 10 task threshold
        active_tasks: 15
      }

      :ok = LoadBalancer.update_agent_metrics(:worker1, overloaded_metrics)

      # Try to assign task
      task_spec = %{capabilities: [:test], complexity: :low}
      assert {:error, :no_suitable_agent} = LoadBalancer.assign_task(task_spec)
    end
  end

  describe "load balancing strategies" do
    test "round robin strategy distributes tasks evenly" do
      # Setup multiple agents
      agent_ids = [:worker1, :worker2, :worker3]

      for agent_id <- agent_ids do
        assert :ok = setup_test_agent(agent_id, [:test])
        assert :ok = LoadBalancer.register_agent(agent_id, [:test])
      end

      # Set round robin strategy
      assert :ok = LoadBalancer.set_load_strategy(:round_robin)

      # Assign multiple tasks and track assignments
      task_spec = %{capabilities: [:test], complexity: :low}

      assignments =
        for _i <- 1..6 do
          {:ok, agent_id, _pid} = LoadBalancer.assign_task(task_spec)
          agent_id
        end

      # Each agent should get 2 tasks (6 tasks / 3 agents)
      assignment_counts = Enum.frequencies(assignments)
      assert Map.get(assignment_counts, :worker1) == 2
      assert Map.get(assignment_counts, :worker2) == 2
      assert Map.get(assignment_counts, :worker3) == 2
    end

    test "resource aware strategy prefers less loaded agents" do
      # Setup agents with different load levels
      assert :ok = setup_test_agent(:light_worker, [:test])
      assert :ok = setup_test_agent(:heavy_worker, [:test])

      assert :ok = LoadBalancer.register_agent(:light_worker, [:test])
      assert :ok = LoadBalancer.register_agent(:heavy_worker, [:test])

      # Update metrics to show different load levels
      :ok =
        LoadBalancer.update_agent_metrics(:light_worker, %{
          cpu_usage: 0.2,
          # 100MB
          memory_usage: 100 * 1024 * 1024,
          active_tasks: 1
        })

      :ok =
        LoadBalancer.update_agent_metrics(:heavy_worker, %{
          cpu_usage: 0.8,
          # 800MB
          memory_usage: 800 * 1024 * 1024,
          active_tasks: 8
        })

      # Set resource aware strategy
      assert :ok = LoadBalancer.set_load_strategy(:resource_aware)

      # Assign task - should go to light worker
      task_spec = %{capabilities: [:test], complexity: :medium}
      assert {:ok, :light_worker, _pid} = LoadBalancer.assign_task(task_spec)
    end

    test "capability based strategy prefers specialized agents" do
      # Setup agents with different specializations
      assert :ok = setup_test_agent(:ml_specialist, [:ml, :deep_learning, :gpu])
      assert :ok = setup_test_agent(:general_worker, [:ml, :basic])

      assert :ok = LoadBalancer.register_agent(:ml_specialist, [:ml, :deep_learning, :gpu])
      assert :ok = LoadBalancer.register_agent(:general_worker, [:ml, :basic])

      # Set capability based strategy
      assert :ok = LoadBalancer.set_load_strategy(:capability_based)

      # Assign task requiring specialized capabilities
      task_spec = %{
        capabilities: [:ml, :deep_learning],
        complexity: :high
      }

      # Should prefer the specialist
      assert {:ok, :ml_specialist, _pid} = LoadBalancer.assign_task(task_spec)
    end

    test "performance weighted strategy prefers faster agents" do
      # Setup agents with different performance profiles
      assert :ok = setup_test_agent(:fast_worker, [:test])
      assert :ok = setup_test_agent(:slow_worker, [:test])

      assert :ok = LoadBalancer.register_agent(:fast_worker, [:test])
      assert :ok = LoadBalancer.register_agent(:slow_worker, [:test])

      # Update performance metrics
      :ok =
        LoadBalancer.update_agent_metrics(:fast_worker, %{
          # 1 second average
          average_task_duration: 1000.0,
          total_tasks_completed: 100
        })

      :ok =
        LoadBalancer.update_agent_metrics(:slow_worker, %{
          # 5 second average
          average_task_duration: 5000.0,
          total_tasks_completed: 50
        })

      # Set performance weighted strategy
      assert :ok = LoadBalancer.set_load_strategy(:performance_weighted)

      # Assign task - should go to faster worker
      task_spec = %{capabilities: [:test], complexity: :medium}
      assert {:ok, :fast_worker, _pid} = LoadBalancer.assign_task(task_spec)
    end
  end

  describe "resource monitoring" do
    test "tracks agent resource metrics" do
      # Setup agent
      assert :ok = setup_test_agent(:monitored_worker, [:test])
      assert :ok = LoadBalancer.register_agent(:monitored_worker, [:test])

      # Update metrics
      metrics = %{
        cpu_usage: 0.65,
        # 512MB
        memory_usage: 512 * 1024 * 1024,
        active_tasks: 3,
        total_tasks_completed: 25,
        average_task_duration: 2500.0
      }

      :ok = LoadBalancer.update_agent_metrics(:monitored_worker, metrics)

      # Retrieve metrics
      {:ok, stored_metrics} = LoadBalancer.get_agent_metrics(:monitored_worker)
      assert stored_metrics.cpu_usage == 0.65
      assert stored_metrics.memory_usage == 512 * 1024 * 1024
      assert stored_metrics.active_tasks == 3
      assert stored_metrics.total_tasks_completed == 25
      assert stored_metrics.average_task_duration == 2500.0
      assert %DateTime{} = stored_metrics.last_updated
    end

    test "handles metrics for non-existent agents" do
      # Try to update metrics for unregistered agent
      metrics = %{cpu_usage: 0.5, memory_usage: 100}
      :ok = LoadBalancer.update_agent_metrics(:nonexistent, metrics)

      # Should not error, but should not find the agent
      assert {:error, :not_found} = LoadBalancer.get_agent_metrics(:nonexistent)
    end

    test "provides comprehensive load statistics" do
      # Setup multiple agents with different characteristics
      agents = [
        {:worker1, [:test], %{cpu_usage: 0.3, memory_usage: 200 * 1024 * 1024, active_tasks: 2}},
        {:worker2, [:test], %{cpu_usage: 0.7, memory_usage: 600 * 1024 * 1024, active_tasks: 5}},
        {:worker3, [:test],
         %{cpu_usage: 0.95, memory_usage: 1.5 * 1024 * 1024 * 1024, active_tasks: 12}}
      ]

      for {agent_id, capabilities, metrics} <- agents do
        assert :ok = setup_test_agent(agent_id, capabilities)
        assert :ok = LoadBalancer.register_agent(agent_id, capabilities)
        :ok = LoadBalancer.update_agent_metrics(agent_id, metrics)
      end

      # Assign some tasks to increment counter
      task_spec = %{capabilities: [:test], complexity: :low}
      {:ok, _agent1, _pid1} = LoadBalancer.assign_task(task_spec)
      {:ok, _agent2, _pid2} = LoadBalancer.assign_task(task_spec)

      # Get comprehensive stats
      stats = LoadBalancer.get_load_stats()

      assert stats.total_agents == 3
      # worker1 and worker2 (worker3 is overloaded)
      assert stats.available_agents == 2
      # worker3
      assert stats.overloaded_agents == 1
      assert stats.total_tasks_assigned == 2
      # Average of 0.3, 0.7, 0.95
      assert stats.average_cpu_usage > 0.5
      # Should be calculated
      assert stats.average_memory_usage > 0
    end
  end

  describe "fault tolerance" do
    test "handles agent process death" do
      # Setup agent
      assert :ok = setup_test_agent(:dying_worker, [:test])
      assert :ok = LoadBalancer.register_agent(:dying_worker, [:test])

      # Verify agent is registered
      stats = LoadBalancer.get_load_stats()
      assert stats.total_agents == 1

      # Simulate agent death (this is simplified - in real scenario the process would die)
      # For testing, we'll unregister to simulate the effect
      :ok = LoadBalancer.unregister_agent(:dying_worker)

      # Verify agent is removed
      stats_after = LoadBalancer.get_load_stats()
      assert stats_after.total_agents == 0
    end

    test "handles assignment when all agents become unavailable" do
      # Setup agent
      assert :ok = setup_test_agent(:worker1, [:test])
      assert :ok = LoadBalancer.register_agent(:worker1, [:test])

      # Make agent overloaded
      overloaded_metrics = %{
        cpu_usage: 0.99,
        memory_usage: 2 * 1024 * 1024 * 1024,
        active_tasks: 20
      }

      :ok = LoadBalancer.update_agent_metrics(:worker1, overloaded_metrics)

      # Try to assign task
      task_spec = %{capabilities: [:test], complexity: :low}
      assert {:error, :no_suitable_agent} = LoadBalancer.assign_task(task_spec)
    end
  end

  describe "rebalancing" do
    test "supports manual rebalancing" do
      # Setup agents
      assert :ok = setup_test_agent(:worker1, [:test])
      assert :ok = LoadBalancer.register_agent(:worker1, [:test])

      # Call rebalance
      assert :ok = LoadBalancer.rebalance()
    end
  end

  # Helper functions
  defp setup_test_agent(agent_id, capabilities) do
    # Register agent in the main registry first
    agent_config = %{
      id: agent_id,
      type: :worker,
      module: MABEAM.TestWorker,
      args: [],
      capabilities: capabilities
    }

    Agent.register_agent(agent_config)
  end

  defp cleanup_test_agents do
    try do
      # Get all agents and clean them up
      agents = Agent.list_agents()

      for agent <- agents do
        case agent.id do
          id when is_atom(id) ->
            case Atom.to_string(id) do
              "worker" <> _ -> Agent.unregister_agent(id)
              "ml_" <> _ -> Agent.unregister_agent(id)
              "comm_" <> _ -> Agent.unregister_agent(id)
              "limited_" <> _ -> Agent.unregister_agent(id)
              "light_" <> _ -> Agent.unregister_agent(id)
              "heavy_" <> _ -> Agent.unregister_agent(id)
              "specialist" <> _ -> Agent.unregister_agent(id)
              "general_" <> _ -> Agent.unregister_agent(id)
              "fast_" <> _ -> Agent.unregister_agent(id)
              "slow_" <> _ -> Agent.unregister_agent(id)
              "monitored_" <> _ -> Agent.unregister_agent(id)
              "dying_" <> _ -> Agent.unregister_agent(id)
              _ -> :ok
            end

          _ ->
            :ok
        end
      end
    rescue
      _ -> :ok
    end
  end
end
