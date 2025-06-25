defmodule Foundation.MABEAM.AgentRegistryTest do
  @moduledoc """
  Comprehensive test suite for Foundation.MABEAM.AgentRegistry.

  Tests all agent lifecycle management, registration, supervision, and integration
  with Foundation services following TDD best practices.
  """

  use ExUnit.Case, async: false

  alias Foundation.MABEAM.AgentRegistry
  alias Foundation.ProcessRegistry

  # ============================================================================
  # Test Setup and Helpers
  # ============================================================================

  setup do
    # The AgentRegistry is already started via application supervision tree
    # Just ensure clean state for each test
    :ok
  end

  defp create_valid_agent_config(id) do
    %{
      id: id,
      type: :worker,
      module: TestAgent,
      config: %{
        name: "Test Agent #{id}",
        capabilities: [:coordination, :computation],
        resources: %{
          # 100 MB
          memory_limit: 100_000_000,
          # 50% CPU
          cpu_limit: 0.5
        },
        test_mode: true
      },
      supervision: %{
        strategy: :one_for_one,
        max_restarts: 3,
        max_seconds: 60
      }
    }
  end

  defp create_agent_config(overrides, id) do
    create_valid_agent_config(id)
    |> Map.merge(overrides)
  end

  defp create_crashy_agent_config(id) do
    create_agent_config(
      %{
        id: id,
        module: CrashyTestAgent,
        supervision: %{
          strategy: :one_for_one,
          max_restarts: 2,
          max_seconds: 30
        }
      },
      id
    )
  end

  defp cleanup_agent(agent_id) do
    # Ensure agent is cleaned up after test
    case AgentRegistry.get_agent_status(agent_id) do
      {:ok, _} ->
        AgentRegistry.stop_agent(agent_id)
        AgentRegistry.deregister_agent(agent_id)

      {:error, :not_found} ->
        :ok
    end
  end

  defp eventually(fun, retries \\ 10, delay \\ 100)
  defp eventually(fun, 0, _delay), do: fun.()

  defp eventually(fun, retries, delay) do
    fun.()
  rescue
    _ ->
      Process.sleep(delay)
      eventually(fun, retries - 1, delay)
  end

  # ============================================================================
  # Agent Registration Tests
  # ============================================================================

  describe "agent registration" do
    test "registers agent with valid config" do
      agent_config = create_valid_agent_config(:reg_test_agent)

      try do
        # Should register successfully
        assert :ok = AgentRegistry.register_agent(:reg_test_agent, agent_config)

        # Should be able to retrieve config
        assert {:ok, returned_config} = AgentRegistry.get_agent_config(:reg_test_agent)
        assert returned_config.id == :reg_test_agent
        assert returned_config.module == TestAgent

        # Should appear in agent list
        {:ok, agents} = AgentRegistry.list_agents()
        agent_ids = Enum.map(agents, fn {id, _info} -> id end)
        assert :reg_test_agent in agent_ids
      after
        cleanup_agent(:reg_test_agent)
      end
    end

    test "rejects duplicate agent registration" do
      agent_config = create_valid_agent_config(:dup_test_agent)

      try do
        # First registration should succeed
        assert :ok = AgentRegistry.register_agent(:dup_test_agent, agent_config)

        # Second registration should fail
        assert {:error, :already_registered} =
                 AgentRegistry.register_agent(:dup_test_agent, agent_config)
      after
        cleanup_agent(:dup_test_agent)
      end
    end

    test "validates agent configuration on registration" do
      # Missing required fields
      invalid_config = %{invalid: "config"}

      assert {:error, {:validation_failed, _reason}} =
               AgentRegistry.register_agent(:invalid_agent, invalid_config)

      # Missing supervision config
      incomplete_config = %{
        id: :incomplete_agent,
        type: :worker,
        module: TestAgent,
        config: %{name: "Incomplete"}
        # Missing supervision
      }

      assert {:error, {:validation_failed, _reason}} =
               AgentRegistry.register_agent(:incomplete_agent, incomplete_config)
    end

    test "provides accurate agent count" do
      {:ok, initial_count} = AgentRegistry.agent_count()

      agent_configs = [
        {:count_agent1, create_valid_agent_config(:count_agent1)},
        {:count_agent2, create_valid_agent_config(:count_agent2)},
        {:count_agent3, create_valid_agent_config(:count_agent3)}
      ]

      try do
        # Register agents
        Enum.each(agent_configs, fn {id, config} ->
          assert :ok = AgentRegistry.register_agent(id, config)
        end)

        {:ok, final_count} = AgentRegistry.agent_count()
        assert final_count == initial_count + 3
      after
        Enum.each(agent_configs, fn {id, _config} ->
          cleanup_agent(id)
        end)
      end
    end
  end

  # ============================================================================
  # Agent Deregistration Tests
  # ============================================================================

  describe "agent deregistration" do
    test "deregisters existing agent" do
      agent_config = create_valid_agent_config(:dereg_test_agent)

      # Register agent
      assert :ok = AgentRegistry.register_agent(:dereg_test_agent, agent_config)
      assert {:ok, _config} = AgentRegistry.get_agent_config(:dereg_test_agent)

      # Deregister agent
      assert :ok = AgentRegistry.deregister_agent(:dereg_test_agent)
      assert {:error, :not_found} = AgentRegistry.get_agent_config(:dereg_test_agent)
    end

    test "handles deregistration of non-existent agent" do
      assert {:error, :not_found} = AgentRegistry.deregister_agent(:non_existent)
    end

    test "stops running agent when deregistering" do
      agent_config = create_valid_agent_config(:stop_dereg_agent)

      try do
        # Register and start agent
        assert :ok = AgentRegistry.register_agent(:stop_dereg_agent, agent_config)
        assert {:ok, pid} = AgentRegistry.start_agent(:stop_dereg_agent)
        assert Process.alive?(pid)

        # Deregister should stop the agent
        assert :ok = AgentRegistry.deregister_agent(:stop_dereg_agent)

        # Process should be terminated
        eventually(fn -> refute Process.alive?(pid) end)
      after
        cleanup_agent(:stop_dereg_agent)
      end
    end
  end

  # ============================================================================
  # Agent Lifecycle Tests
  # ============================================================================

  describe "agent lifecycle" do
    test "starts registered agent successfully" do
      agent_config = create_valid_agent_config(:lifecycle_agent)

      try do
        # Register agent
        assert :ok = AgentRegistry.register_agent(:lifecycle_agent, agent_config)

        # Start agent
        assert {:ok, pid} = AgentRegistry.start_agent(:lifecycle_agent)
        assert is_pid(pid)
        assert Process.alive?(pid)

        # Check status
        {:ok, status} = AgentRegistry.get_agent_status(:lifecycle_agent)
        assert status.status == :running
        assert status.pid == pid
        assert status.started_at != nil
      after
        cleanup_agent(:lifecycle_agent)
      end
    end

    test "rejects starting non-registered agent" do
      assert {:error, :not_found} = AgentRegistry.start_agent(:non_registered)
    end

    test "rejects starting already running agent" do
      agent_config = create_valid_agent_config(:already_running_agent)

      try do
        assert :ok = AgentRegistry.register_agent(:already_running_agent, agent_config)
        assert {:ok, _pid} = AgentRegistry.start_agent(:already_running_agent)

        # Second start should fail
        assert {:error, :already_running} = AgentRegistry.start_agent(:already_running_agent)
      after
        cleanup_agent(:already_running_agent)
      end
    end

    test "stops running agent gracefully" do
      agent_config = create_valid_agent_config(:stop_agent)

      try do
        assert :ok = AgentRegistry.register_agent(:stop_agent, agent_config)
        assert {:ok, pid} = AgentRegistry.start_agent(:stop_agent)
        assert Process.alive?(pid)

        # Stop agent
        assert :ok = AgentRegistry.stop_agent(:stop_agent)

        # Process should be terminated
        eventually(fn -> refute Process.alive?(pid) end)

        # Status should be updated
        {:ok, status} = AgentRegistry.get_agent_status(:stop_agent)
        assert status.status == :registered
        assert status.pid == nil
      after
        cleanup_agent(:stop_agent)
      end
    end

    test "handles stopping non-running agent" do
      agent_config = create_valid_agent_config(:not_running_agent)

      try do
        assert :ok = AgentRegistry.register_agent(:not_running_agent, agent_config)

        # Try to stop agent that's not running
        assert {:error, :not_running} = AgentRegistry.stop_agent(:not_running_agent)
      after
        cleanup_agent(:not_running_agent)
      end
    end

    test "tracks agent status transitions correctly" do
      agent_config = create_valid_agent_config(:status_agent)

      try do
        # Initial registration
        assert :ok = AgentRegistry.register_agent(:status_agent, agent_config)
        {:ok, status} = AgentRegistry.get_agent_status(:status_agent)
        assert status.status == :registered
        assert status.pid == nil

        # Start agent
        assert {:ok, pid} = AgentRegistry.start_agent(:status_agent)
        {:ok, status} = AgentRegistry.get_agent_status(:status_agent)
        assert status.status == :running
        assert status.pid == pid

        # Stop agent
        assert :ok = AgentRegistry.stop_agent(:status_agent)
        {:ok, status} = AgentRegistry.get_agent_status(:status_agent)
        assert status.status == :registered
        assert status.pid == nil
      after
        cleanup_agent(:status_agent)
      end
    end
  end

  # ============================================================================
  # Process Monitoring and Failure Handling Tests
  # ============================================================================

  describe "process monitoring and failure handling" do
    test "detects agent process crashes" do
      agent_config = create_valid_agent_config(:crash_detect_agent)

      try do
        assert :ok = AgentRegistry.register_agent(:crash_detect_agent, agent_config)
        assert {:ok, pid} = AgentRegistry.start_agent(:crash_detect_agent)

        # Kill the process
        Process.exit(pid, :kill)

        # Registry should detect the crash and update status
        eventually(
          fn ->
            {:ok, status} = AgentRegistry.get_agent_status(:crash_detect_agent)
            assert status.status == :failed
            assert status.restart_count >= 1
          end,
          20,
          200
        )
      after
        cleanup_agent(:crash_detect_agent)
      end
    end

    test "handles crashy agent appropriately" do
      crashy_config = create_crashy_agent_config(:crashy_agent)

      try do
        assert :ok = AgentRegistry.register_agent(:crashy_agent, crashy_config)

        # Try to start crashy agent (will fail immediately)
        assert {:error, _reason} = AgentRegistry.start_agent(:crashy_agent)

        # Should be marked as failed
        {:ok, status} = AgentRegistry.get_agent_status(:crashy_agent)
        assert status.status == :failed
        assert status.restart_count >= 1
      after
        cleanup_agent(:crashy_agent)
      end
    end
  end

  # ============================================================================
  # Resource Management Tests
  # ============================================================================

  describe "resource management" do
    test "tracks agent resource usage" do
      agent_config = create_valid_agent_config(:resource_agent)

      try do
        assert :ok = AgentRegistry.register_agent(:resource_agent, agent_config)
        assert {:ok, _pid} = AgentRegistry.start_agent(:resource_agent)

        # Allow some time for resource tracking
        Process.sleep(100)

        # Get agent metrics
        {:ok, metrics} = AgentRegistry.get_agent_metrics(:resource_agent)
        assert is_number(metrics.memory_usage)
        assert metrics.memory_usage >= 0
        assert is_number(metrics.heap_size)
        assert metrics.heap_size >= 0
      after
        cleanup_agent(:resource_agent)
      end
    end

    test "provides resource usage summary" do
      agent_configs = [
        {:summary_agent1, create_valid_agent_config(:summary_agent1)},
        {:summary_agent2, create_valid_agent_config(:summary_agent2)}
      ]

      try do
        # Get initial summary
        {:ok, initial_summary} = AgentRegistry.get_resource_summary()
        initial_active = initial_summary.active_agents

        # Register and start agents
        Enum.each(agent_configs, fn {id, config} ->
          assert :ok = AgentRegistry.register_agent(id, config)
          assert {:ok, _pid} = AgentRegistry.start_agent(id)
        end)

        # Allow resource tracking
        Process.sleep(100)

        {:ok, summary} = AgentRegistry.get_resource_summary()
        assert summary.active_agents >= initial_active + 2
        assert is_number(summary.total_memory_usage)
        assert summary.total_memory_usage >= 0
      after
        Enum.each(agent_configs, fn {id, _config} ->
          cleanup_agent(id)
        end)
      end
    end
  end

  # ============================================================================
  # Configuration Management Tests
  # ============================================================================

  describe "configuration management" do
    test "updates agent configuration successfully" do
      agent_config = create_valid_agent_config(:config_agent)

      try do
        assert :ok = AgentRegistry.register_agent(:config_agent, agent_config)

        # Update configuration
        new_config = %{
          agent_config
          | config: Map.put(agent_config.config, :updated_field, "new_value")
        }

        assert :ok = AgentRegistry.update_agent_config(:config_agent, new_config)

        # Verify update
        {:ok, updated_config} = AgentRegistry.get_agent_config(:config_agent)
        assert updated_config.config.updated_field == "new_value"
      after
        cleanup_agent(:config_agent)
      end
    end

    test "validates configuration updates" do
      agent_config = create_valid_agent_config(:validate_config_agent)

      try do
        assert :ok = AgentRegistry.register_agent(:validate_config_agent, agent_config)

        # Try invalid configuration update
        invalid_config = %{invalid: "update"}

        assert {:error, {:validation_failed, _reason}} =
                 AgentRegistry.update_agent_config(:validate_config_agent, invalid_config)
      after
        cleanup_agent(:validate_config_agent)
      end
    end
  end

  # ============================================================================
  # Health Monitoring Tests
  # ============================================================================

  describe "health monitoring" do
    test "performs health checks on agents" do
      agent_config = create_valid_agent_config(:health_agent)

      try do
        assert :ok = AgentRegistry.register_agent(:health_agent, agent_config)
        assert {:ok, _pid} = AgentRegistry.start_agent(:health_agent)

        # Perform health check
        assert :ok = AgentRegistry.health_check(:health_agent)

        # Check that health check time was recorded
        {:ok, status} = AgentRegistry.get_agent_status(:health_agent)
        assert status.last_health_check != nil
        assert DateTime.diff(DateTime.utc_now(), status.last_health_check, :second) < 5
      after
        cleanup_agent(:health_agent)
      end
    end

    test "provides system-wide health status" do
      {:ok, system_health} = AgentRegistry.system_health()

      # Should have basic health information
      assert is_number(system_health.total_agents)
      assert is_number(system_health.healthy_agents)
      assert is_number(system_health.unhealthy_agents)
      assert is_number(system_health.health_percentage)
      assert system_health.health_percentage >= 0
      assert system_health.health_percentage <= 100
    end

    test "detects unhealthy agents" do
      agent_config = create_valid_agent_config(:unhealthy_agent)

      try do
        assert :ok = AgentRegistry.register_agent(:unhealthy_agent, agent_config)
        assert {:ok, pid} = AgentRegistry.start_agent(:unhealthy_agent)

        # Kill the agent to make it unhealthy
        Process.exit(pid, :kill)

        # Health check should detect the failure
        eventually(fn ->
          assert {:error, :process_dead} = AgentRegistry.health_check(:unhealthy_agent)
        end)
      after
        cleanup_agent(:unhealthy_agent)
      end
    end
  end

  # ============================================================================
  # Supervision Integration Tests
  # ============================================================================

  describe "supervision integration" do
    test "agents run under supervision" do
      agent_config = create_valid_agent_config(:supervised_agent)

      try do
        assert :ok = AgentRegistry.register_agent(:supervised_agent, agent_config)
        assert {:ok, _pid} = AgentRegistry.start_agent(:supervised_agent)

        # Get supervisor information
        {:ok, supervisor_pid} = AgentRegistry.get_agent_supervisor(:supervised_agent)
        assert is_pid(supervisor_pid)

        # Get supervisor health
        {:ok, health} = AgentRegistry.get_supervisor_health(:supervised_agent)
        assert health.status == :healthy
        assert is_pid(health.supervisor_pid)
        assert is_number(health.children_count)
      after
        cleanup_agent(:supervised_agent)
      end
    end
  end

  # ============================================================================
  # Foundation Integration Tests
  # ============================================================================

  describe "foundation integration" do
    test "integrates with ProcessRegistry" do
      agent_config = create_valid_agent_config(:registry_agent)

      try do
        assert :ok = AgentRegistry.register_agent(:registry_agent, agent_config)
        assert {:ok, pid} = AgentRegistry.start_agent(:registry_agent)

        # Agent should be registered in ProcessRegistry
        {:ok, registered_pid} = ProcessRegistry.lookup(:production, {:agent, :registry_agent})
        assert registered_pid == pid
      after
        cleanup_agent(:registry_agent)
      end
    end
  end

  # ============================================================================
  # Error Handling and Edge Cases
  # ============================================================================

  describe "error handling and edge cases" do
    test "handles unknown requests gracefully" do
      agent_config = create_valid_agent_config(:error_test_agent)

      try do
        assert :ok = AgentRegistry.register_agent(:error_test_agent, agent_config)

        # The system should not crash with unknown requests
        # (This tests the catch-all handle_call clause)
        assert AgentRegistry |> GenServer.call(:unknown_request) == {:error, :unknown_request}
      after
        cleanup_agent(:error_test_agent)
      end
    end

    test "maintains system stability after errors" do
      crashy_config = create_crashy_agent_config(:stability_test)

      try do
        assert :ok = AgentRegistry.register_agent(:stability_test, crashy_config)
        assert {:error, _} = AgentRegistry.start_agent(:stability_test)

        # System should still be operational
        {:ok, _health} = AgentRegistry.system_health()
        {:ok, _count} = AgentRegistry.agent_count()

        # Should be able to register new agents
        normal_config = create_valid_agent_config(:stability_normal)
        assert :ok = AgentRegistry.register_agent(:stability_normal, normal_config)

        cleanup_agent(:stability_normal)
      after
        cleanup_agent(:stability_test)
      end
    end
  end
end
