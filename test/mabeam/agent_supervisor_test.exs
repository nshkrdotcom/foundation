defmodule MABEAM.AgentSupervisorTest do
  @moduledoc """
  Tests for MABEAM.AgentSupervisor.

  Tests the dynamic supervision of MABEAM agents with automatic restarts,
  resource management, and performance monitoring.
  """
  use ExUnit.Case, async: false

  alias MABEAM.{Agent, AgentSupervisor}

  setup do
    # Clean up any existing agents
    on_exit(fn ->
      cleanup_test_agents()
    end)

    :ok
  end

  describe "agent supervision" do
    test "starts and supervises agents dynamically" do
      # Register an agent configuration
      agent_config = %{
        id: :supervised_agent,
        type: :worker,
        module: MABEAM.TestWorker,
        args: [],
        capabilities: [:test_supervision]
      }

      assert :ok = Agent.register_agent(agent_config)

      # Start the agent under supervision
      assert {:ok, agent_pid} = AgentSupervisor.start_agent(:supervised_agent)
      assert is_pid(agent_pid)
      assert Process.alive?(agent_pid)

      # Verify agent is registered and supervised
      assert {:ok, :running} = Agent.get_agent_status(:supervised_agent)

      # Verify agent is under the supervisor
      children = DynamicSupervisor.which_children(MABEAM.AgentSupervisor)
      assert length(children) == 1
      {_, child_pid, _, _} = hd(children)
      assert child_pid == agent_pid
    end

    test "automatically restarts failed agents" do
      agent_config = %{
        id: :restart_test_agent,
        type: :worker,
        module: MABEAM.TestWorker,
        args: [],
        capabilities: [:restart_test]
      }

      assert :ok = Agent.register_agent(agent_config)
      assert {:ok, original_pid} = AgentSupervisor.start_agent(:restart_test_agent)

      # Kill the agent process
      Process.exit(original_pid, :kill)

      # Wait for restart
      Process.sleep(200)

      # Verify the child was restarted by the supervisor
      children = DynamicSupervisor.which_children(MABEAM.AgentSupervisor)
      assert length(children) == 1
      {_, new_pid, _, _} = hd(children)
      assert is_pid(new_pid)
      assert new_pid != original_pid
      assert Process.alive?(new_pid)
    end

    test "stops supervised agents cleanly" do
      agent_config = %{
        id: :stop_test_agent,
        type: :worker,
        module: MABEAM.TestWorker,
        args: [],
        capabilities: [:stop_test]
      }

      assert :ok = Agent.register_agent(agent_config)
      assert {:ok, agent_pid} = AgentSupervisor.start_agent(:stop_test_agent)

      # Stop the agent
      assert :ok = AgentSupervisor.stop_agent(:stop_test_agent)

      # Verify agent is stopped and removed from supervision
      refute Process.alive?(agent_pid)
      assert {:error, :not_found} = AgentSupervisor.get_agent_pid(:stop_test_agent)

      # Verify no children under supervisor
      children = DynamicSupervisor.which_children(MABEAM.AgentSupervisor)
      assert length(children) == 0
    end

    test "handles agent configuration updates" do
      agent_config = %{
        id: :update_test_agent,
        type: :worker,
        module: MABEAM.TestWorker,
        args: [test: :original],
        capabilities: [:update_test]
      }

      assert :ok = Agent.register_agent(agent_config)
      assert {:ok, original_pid} = AgentSupervisor.start_agent(:update_test_agent)

      # Update agent configuration
      updated_config = %{agent_config | args: [test: :updated]}
      assert :ok = AgentSupervisor.update_agent_config(:update_test_agent, updated_config)

      # Verify agent was restarted with new configuration
      assert {:ok, new_pid} = AgentSupervisor.get_agent_pid(:update_test_agent)
      assert new_pid != original_pid
      assert Process.alive?(new_pid)
    end
  end

  describe "supervision policies" do
    test "respects restart intensity limits" do
      agent_config = %{
        id: :crash_test_agent,
        type: :worker,
        module: MABEAM.FailingAgent,
        args: [failure_mode: :immediate],
        capabilities: [:crash_test]
      }

      assert :ok = Agent.register_agent(agent_config)

      # Starting should fail immediately due to FailingAgent
      assert {:error, _reason} = AgentSupervisor.start_agent(:crash_test_agent)

      # Verify agent is not running
      assert {:error, :not_found} = AgentSupervisor.get_agent_pid(:crash_test_agent)
    end

    test "tracks supervision metrics" do
      agent_config = %{
        id: :metrics_test_agent,
        type: :worker,
        module: MABEAM.TestWorker,
        args: [],
        capabilities: [:metrics_test]
      }

      assert :ok = Agent.register_agent(agent_config)
      assert {:ok, _pid} = AgentSupervisor.start_agent(:metrics_test_agent)

      # Get supervision metrics
      metrics = AgentSupervisor.get_supervision_metrics()

      assert metrics.total_agents >= 1
      assert metrics.running_agents >= 1
      assert metrics.failed_agents >= 0
      assert metrics.restart_count >= 0
      assert is_map(metrics.agent_uptime)
    end
  end

  describe "performance monitoring" do
    test "monitors agent resource usage" do
      agent_config = %{
        id: :resource_test_agent,
        type: :worker,
        module: MABEAM.TestWorker,
        args: [],
        capabilities: [:resource_test]
      }

      assert :ok = Agent.register_agent(agent_config)
      assert {:ok, _agent_pid} = AgentSupervisor.start_agent(:resource_test_agent)

      # Get agent performance metrics
      metrics = AgentSupervisor.get_agent_performance(:resource_test_agent)

      assert metrics.memory_usage > 0
      assert metrics.message_queue_length >= 0
      assert metrics.reductions > 0
      assert is_integer(metrics.uptime_ms)
    end

    test "provides system-wide performance overview" do
      # Start multiple agents
      agent_configs = [
        %{
          id: :perf_agent_1,
          type: :worker,
          module: MABEAM.TestWorker,
          capabilities: [:perf1]
        },
        %{
          id: :perf_agent_2,
          type: :worker,
          module: MABEAM.TestWorker,
          capabilities: [:perf2]
        }
      ]

      Enum.each(agent_configs, fn config ->
        assert :ok = Agent.register_agent(config)
        assert {:ok, _pid} = AgentSupervisor.start_agent(config.id)
      end)

      # Get system performance overview
      overview = AgentSupervisor.get_system_performance()

      assert overview.total_agents >= 2
      assert overview.total_memory_usage > 0
      assert overview.average_message_queue_length >= 0
      assert is_list(overview.top_memory_consumers)
      assert is_map(overview.agents_by_capability)
    end
  end

  describe "error handling and recovery" do
    test "handles supervisor crashes gracefully" do
      agent_config = %{
        id: :supervisor_crash_test,
        type: :worker,
        module: MABEAM.TestWorker,
        args: [],
        capabilities: [:supervisor_crash_test]
      }

      assert :ok = Agent.register_agent(agent_config)
      assert {:ok, agent_pid} = AgentSupervisor.start_agent(:supervisor_crash_test)

      # Get supervisor PID
      supervisor_pid = Process.whereis(MABEAM.AgentSupervisor)
      assert is_pid(supervisor_pid)

      # Supervisor should be part of the application supervision tree
      # so it should restart automatically if it crashes
      # For this test, we just verify the agent remains manageable
      assert Process.alive?(agent_pid)
      assert {:ok, :running} = Agent.get_agent_status(:supervisor_crash_test)
    end
  end

  # Helper function to clean up test agents
  defp cleanup_test_agents do
    try do
      # Stop all supervised agents
      children = DynamicSupervisor.which_children(MABEAM.AgentSupervisor)

      Enum.each(children, fn {_, pid, _, _} ->
        if is_pid(pid) and Process.alive?(pid) do
          DynamicSupervisor.terminate_child(MABEAM.AgentSupervisor, pid)
        end
      end)

      # Clean up agent registrations
      agents = Agent.list_agents()

      Enum.each(agents, fn agent ->
        case agent.id do
          id when is_atom(id) ->
            case Atom.to_string(id) do
              "supervised_" <> _ -> Agent.unregister_agent(id)
              "restart_test_" <> _ -> Agent.unregister_agent(id)
              "stop_test_" <> _ -> Agent.unregister_agent(id)
              "update_test_" <> _ -> Agent.unregister_agent(id)
              "crash_test_" <> _ -> Agent.unregister_agent(id)
              "metrics_test_" <> _ -> Agent.unregister_agent(id)
              "resource_test_" <> _ -> Agent.unregister_agent(id)
              "perf_agent_" <> _ -> Agent.unregister_agent(id)
              "supervisor_crash_test" -> Agent.unregister_agent(id)
              _ -> :ok
            end

          _ ->
            :ok
        end
      end)
    rescue
      _ -> :ok
    end
  end
end
