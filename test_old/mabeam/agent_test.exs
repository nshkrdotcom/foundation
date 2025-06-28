defmodule MABEAM.AgentTest do
  @moduledoc """
  Tests for MABEAM.Agent module.

  Tests the agent-specific facade that wraps Foundation.ProcessRegistry
  with MABEAM agent semantics.
  """
  use ExUnit.Case, async: false

  alias MABEAM.Agent
  alias Foundation.ProcessRegistry
  # alias MABEAM.{UnifiedRegistry, AgentFixtures}

  setup do
    # Setup test namespace for agent testing
    test_ref = make_ref()
    namespace = {:test, test_ref}

    # Use production namespace for agent tests since Agent module uses :production
    # We'll clean up agents manually

    on_exit(fn ->
      # Clean up any registered test agents gently
      try do
        cleanup_test_agents()
      rescue
        _ -> :ok
      end
    end)

    %{test_ref: test_ref, namespace: namespace}
  end

  describe "agent registration" do
    test "register_agent/1 registers an agent with valid configuration" do
      config = %{
        id: :test_worker,
        type: :worker,
        module: MABEAM.TestWorker,
        args: [],
        capabilities: [:computation]
      }

      assert :ok = Agent.register_agent(config)

      # Verify agent is registered in the unified registry
      assert {:ok, metadata} = ProcessRegistry.get_metadata(:production, {:agent, :test_worker})
      assert metadata.type == :mabeam_agent
      assert metadata.agent_type == :worker
      assert metadata.module == MABEAM.TestWorker
      assert metadata.capabilities == [:computation]
      assert metadata.status == :registered
    end

    test "register_agent/1 includes default values for optional fields" do
      config = %{
        id: :minimal_agent,
        type: :worker,
        module: MABEAM.TestWorker
      }

      assert :ok = Agent.register_agent(config)

      assert {:ok, metadata} = ProcessRegistry.get_metadata(:production, {:agent, :minimal_agent})
      assert metadata.args == []
      assert metadata.capabilities == []
      assert metadata.restart_policy == :permanent
    end

    test "register_agent/1 validates required fields" do
      # Missing id
      config = %{type: :worker, module: MABEAM.TestWorker}
      assert {:error, {:missing_required_fields, [:id]}} = Agent.register_agent(config)

      # Missing type
      config = %{id: :test, module: MABEAM.TestWorker}
      assert {:error, {:missing_required_fields, [:type]}} = Agent.register_agent(config)

      # Missing module
      config = %{id: :test, type: :worker}
      assert {:error, {:missing_required_fields, [:module]}} = Agent.register_agent(config)
    end

    test "register_agent/1 validates agent ID format" do
      config = %{
        # Invalid - must be atom or string
        id: 123,
        type: :worker,
        module: MABEAM.TestWorker
      }

      assert {:error, :invalid_agent_id} = Agent.register_agent(config)
    end

    test "register_agent/1 validates module exists" do
      config = %{
        id: :test_agent,
        type: :worker,
        module: NonExistentModule
      }

      assert {:error, {:module_not_found, _reason}} = Agent.register_agent(config)
    end

    test "register_agent/1 allows string agent IDs" do
      config = %{
        id: "string_agent",
        type: :worker,
        module: MABEAM.TestWorker
      }

      assert :ok = Agent.register_agent(config)
      assert {:ok, _metadata} = ProcessRegistry.get_metadata(:production, {:agent, "string_agent"})
    end
  end

  describe "agent lifecycle management" do
    setup do
      # Register a test agent for lifecycle tests
      config = %{
        id: :lifecycle_agent,
        type: :worker,
        module: MABEAM.TestWorker,
        args: [name: :test_worker_instance],
        capabilities: [:test]
      }

      assert :ok = Agent.register_agent(config)
      %{agent_config: config}
    end

    test "start_agent/1 starts a registered agent", %{agent_config: config} do
      assert {:ok, pid} = Agent.start_agent(config.id)
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Verify agent status is updated
      assert {:ok, :running} = Agent.get_agent_status(config.id)

      # Verify PID is registered
      assert {:ok, registered_pid} = ProcessRegistry.lookup(:production, {:agent, config.id})
      assert registered_pid == pid
    end

    test "start_agent/1 returns error for unregistered agent" do
      assert {:error, :not_found} = Agent.start_agent(:nonexistent_agent)
    end

    test "start_agent/1 returns error if agent already running", %{agent_config: config} do
      # Start the agent first
      assert {:ok, _pid} = Agent.start_agent(config.id)

      # Try to start again
      assert {:error, :already_running} = Agent.start_agent(config.id)
    end

    test "stop_agent/1 stops a running agent", %{agent_config: config} do
      # Start the agent first
      assert {:ok, pid} = Agent.start_agent(config.id)
      assert Process.alive?(pid)

      # Stop the agent
      assert :ok = Agent.stop_agent(config.id)

      # Verify agent is stopped
      refute Process.alive?(pid)
      assert {:ok, :stopped} = Agent.get_agent_status(config.id)
    end

    test "stop_agent/1 returns error for unregistered agent" do
      assert {:error, :not_found} = Agent.stop_agent(:nonexistent_agent)
    end

    test "stop_agent/1 returns error for non-running agent", %{agent_config: config} do
      # Agent is registered but not started
      assert {:error, :not_running} = Agent.stop_agent(config.id)
    end

    test "restart_agent/1 restarts an agent", %{agent_config: config} do
      # Start the agent first
      assert {:ok, original_pid} = Agent.start_agent(config.id)

      # Restart the agent
      assert {:ok, new_pid} = Agent.restart_agent(config.id)

      # Should be a different PID
      assert new_pid != original_pid
      assert Process.alive?(new_pid)
      refute Process.alive?(original_pid)

      # Status should be running
      assert {:ok, :running} = Agent.get_agent_status(config.id)
    end

    test "restart_agent/1 works even if agent is not running", %{agent_config: config} do
      # Agent is registered but not started
      assert {:ok, :registered} = Agent.get_agent_status(config.id)

      # Restart should start it
      assert {:ok, pid} = Agent.restart_agent(config.id)
      assert Process.alive?(pid)
      assert {:ok, :running} = Agent.get_agent_status(config.id)
    end
  end

  describe "agent discovery" do
    setup do
      # Register multiple test agents with different capabilities
      agents = [
        %{
          id: :worker1,
          type: :computation_worker,
          module: MABEAM.TestWorker,
          capabilities: [:computation, :parallel_processing]
        },
        %{
          id: :worker2,
          type: :nlp_worker,
          module: MABEAM.MLTestWorker,
          capabilities: [:nlp, :text_processing]
        },
        %{
          id: :coordinator,
          type: :coordinator,
          module: MABEAM.TestWorker,
          capabilities: [:coordination, :task_distribution]
        },
        %{
          id: :hybrid_worker,
          type: :hybrid,
          module: MABEAM.TestWorker,
          capabilities: [:computation, :nlp]
        }
      ]

      Enum.each(agents, &Agent.register_agent/1)
      %{agents: agents}
    end

    test "find_agents_by_capability/1 finds agents with specific capability" do
      agents = Agent.find_agents_by_capability([:computation])

      agent_ids = Enum.map(agents, & &1.id)
      assert :worker1 in agent_ids
      assert :hybrid_worker in agent_ids
      refute :worker2 in agent_ids
      refute :coordinator in agent_ids
    end

    test "find_agents_by_capability/1 finds agents with multiple capabilities (intersection)" do
      agents = Agent.find_agents_by_capability([:computation, :nlp])

      agent_ids = Enum.map(agents, & &1.id)
      assert :hybrid_worker in agent_ids
      refute :worker1 in agent_ids
      refute :worker2 in agent_ids
      refute :coordinator in agent_ids
    end

    test "find_agents_by_capability/1 returns empty list for non-existent capability" do
      agents = Agent.find_agents_by_capability([:non_existent])
      assert agents == []
    end

    test "find_agents_by_type/1 finds agents by type" do
      workers = Agent.find_agents_by_type(:computation_worker)
      assert length(workers) == 1
      assert hd(workers).id == :worker1

      nlp_workers = Agent.find_agents_by_type(:nlp_worker)
      assert length(nlp_workers) == 1
      assert hd(nlp_workers).id == :worker2
    end

    test "find_agents_by_type/1 returns empty list for non-existent type" do
      agents = Agent.find_agents_by_type(:non_existent_type)
      assert agents == []
    end

    test "list_agents/0 returns all registered agents" do
      agents = Agent.list_agents()
      agent_ids = Enum.map(agents, & &1.id)

      assert :worker1 in agent_ids
      assert :worker2 in agent_ids
      assert :coordinator in agent_ids
      assert :hybrid_worker in agent_ids
      assert length(agents) >= 4
    end
  end

  describe "agent information and status" do
    setup do
      config = %{
        id: :info_test_agent,
        type: :test_worker,
        module: MABEAM.TestWorker,
        args: [test: true],
        capabilities: [:testing, :info_retrieval],
        restart_policy: :temporary
      }

      assert :ok = Agent.register_agent(config)
      %{agent_config: config}
    end

    test "get_agent_status/1 returns correct status for registered agent", %{agent_config: config} do
      assert {:ok, :registered} = Agent.get_agent_status(config.id)
    end

    test "get_agent_status/1 returns correct status for running agent", %{agent_config: config} do
      {:ok, _pid} = Agent.start_agent(config.id)
      assert {:ok, :running} = Agent.get_agent_status(config.id)
    end

    test "get_agent_status/1 returns correct status for stopped agent", %{agent_config: config} do
      {:ok, _pid} = Agent.start_agent(config.id)
      :ok = Agent.stop_agent(config.id)
      assert {:ok, :stopped} = Agent.get_agent_status(config.id)
    end

    test "get_agent_status/1 returns error for unregistered agent" do
      assert {:error, :not_found} = Agent.get_agent_status(:nonexistent)
    end

    test "get_agent_info/1 returns complete agent information", %{agent_config: config} do
      assert {:ok, info} = Agent.get_agent_info(config.id)

      assert info.id == config.id
      assert info.type == config.type
      assert info.module == config.module
      assert info.args == config.args
      assert info.capabilities == config.capabilities
      assert info.restart_policy == config.restart_policy
      assert info.status == :registered
      assert info.pid == nil
      assert is_struct(info.registered_at, DateTime)
    end

    test "get_agent_info/1 includes PID when agent is running", %{agent_config: config} do
      {:ok, pid} = Agent.start_agent(config.id)
      assert {:ok, info} = Agent.get_agent_info(config.id)

      assert info.status == :running
      assert info.pid == pid
    end

    test "get_agent_info/1 returns error for unregistered agent" do
      assert {:error, :not_found} = Agent.get_agent_info(:nonexistent)
    end
  end

  describe "agent unregistration" do
    setup do
      config = %{
        id: :removable_agent,
        type: :temporary,
        module: MABEAM.TestWorker
      }

      assert :ok = Agent.register_agent(config)
      %{agent_config: config}
    end

    test "unregister_agent/1 removes a registered agent", %{agent_config: config} do
      # Verify agent is registered
      assert {:ok, :registered} = Agent.get_agent_status(config.id)

      # Unregister the agent
      assert :ok = Agent.unregister_agent(config.id)

      # Verify agent is removed
      assert {:error, :not_found} = Agent.get_agent_status(config.id)
      assert :error = ProcessRegistry.lookup(:production, {:agent, config.id})
    end

    test "unregister_agent/1 stops running agent before removing", %{agent_config: config} do
      # Start the agent
      {:ok, pid} = Agent.start_agent(config.id)
      assert Process.alive?(pid)

      # Unregister should stop and remove
      assert :ok = Agent.unregister_agent(config.id)

      # Verify agent is stopped and removed
      refute Process.alive?(pid)
      assert {:error, :not_found} = Agent.get_agent_status(config.id)
    end

    test "unregister_agent/1 succeeds even for non-existent agent" do
      assert :ok = Agent.unregister_agent(:nonexistent_agent)
    end
  end

  describe "integration with ProcessRegistry" do
    test "agents coexist with regular services in production namespace" do
      # Register a regular service
      service_pid = spawn(fn -> Process.sleep(1000) end)
      ProcessRegistry.register(:production, :test_service, service_pid)

      # Register an agent
      config = %{
        id: :integration_agent,
        type: :integration_test,
        module: MABEAM.TestWorker
      }

      Agent.register_agent(config)

      # Both should be findable
      assert {:ok, ^service_pid} = ProcessRegistry.lookup(:production, :test_service)
      assert {:ok, :registered} = Agent.get_agent_status(:integration_agent)

      # Agent should not interfere with service discovery
      services = ProcessRegistry.list_services(:production)
      assert :test_service in services
      assert {:agent, :integration_agent} in services

      # Cleanup
      Process.exit(service_pid, :kill)
      Agent.unregister_agent(:integration_agent)
    end

    test "agent metadata is properly stored and retrieved" do
      config = %{
        id: :metadata_test,
        type: :metadata_worker,
        module: MABEAM.TestWorker,
        capabilities: [:metadata, :storage],
        custom_field: "custom_value"
      }

      Agent.register_agent(config)

      # Check metadata through ProcessRegistry
      assert {:ok, metadata} = ProcessRegistry.get_metadata(:production, {:agent, :metadata_test})
      assert metadata.type == :mabeam_agent
      assert metadata.agent_type == :metadata_worker
      assert metadata.capabilities == [:metadata, :storage]
      assert metadata.config.custom_field == "custom_value"

      Agent.unregister_agent(:metadata_test)
    end
  end

  # Helper functions

  defp cleanup_test_agents do
    # Find all agents registered during tests and clean them up
    try do
      agents = Agent.list_agents()

      Enum.each(agents, fn agent ->
        try do
          case agent.id do
            id when is_atom(id) ->
              case Atom.to_string(id) do
                "test" <> _ -> safely_unregister_agent(id)
                "lifecycle" <> _ -> safely_unregister_agent(id)
                "worker" <> _ -> safely_unregister_agent(id)
                "coordinator" -> safely_unregister_agent(id)
                "hybrid" <> _ -> safely_unregister_agent(id)
                "info" <> _ -> safely_unregister_agent(id)
                "removable" <> _ -> safely_unregister_agent(id)
                "integration" <> _ -> safely_unregister_agent(id)
                "metadata" <> _ -> safely_unregister_agent(id)
                "minimal" <> _ -> safely_unregister_agent(id)
                "migration_test_" <> _ -> safely_unregister_agent(id)
                _ -> :ok
              end

            id when is_binary(id) ->
              if String.starts_with?(id, "string") do
                safely_unregister_agent(id)
              end

            _ ->
              :ok
          end
        rescue
          _ -> :ok
        end
      end)
    rescue
      _ -> :ok
    end
  end

  defp safely_unregister_agent(agent_id) do
    try do
      # Remove from both ProcessRegistry and AgentRegistry
      agent_key = {:agent, agent_id}
      ProcessRegistry.unregister(:production, agent_key)
      MABEAM.AgentRegistry.deregister_agent(agent_id)
    rescue
      _ -> :ok
    end
  end
end
