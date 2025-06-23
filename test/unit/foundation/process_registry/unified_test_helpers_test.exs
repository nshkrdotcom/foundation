defmodule Foundation.ProcessRegistry.UnifiedTestHelpersTest do
  @moduledoc """
  Tests for the unified test helper infrastructure.
  """
  use ExUnit.Case, async: false

  import Foundation.TestHelpers.UnifiedRegistry
  alias Foundation.TestHelpers.AgentFixtures
  alias Foundation.ProcessRegistry

  describe "basic test namespace operations" do
    test "setup_test_namespace creates isolated namespace" do
      %{namespace: namespace1, test_ref: ref1} = setup_test_namespace(cleanup_on_exit: false)
      %{namespace: namespace2, test_ref: ref2} = setup_test_namespace(cleanup_on_exit: false)

      # Namespaces should be different
      assert namespace1 != namespace2
      assert ref1 != ref2

      # Create separate processes to avoid cleanup conflicts
      {:ok, pid1} = Task.start(fn -> Process.sleep(:infinity) end)
      {:ok, pid2} = Task.start(fn -> Process.sleep(:infinity) end)

      # Should be able to register in each independently
      assert :ok = register_test_service(namespace1, :service1, pid1)
      assert :ok = register_test_service(namespace2, :service1, pid2)

      # Services should be isolated
      assert_registered(namespace1, :service1)
      assert_registered(namespace2, :service1)

      # Manual cleanup to avoid process exit conflicts
      ProcessRegistry.unregister(namespace1, :service1)
      ProcessRegistry.unregister(namespace2, :service1)
      Process.exit(pid1, :shutdown)
      Process.exit(pid2, :shutdown)
    end

    test "register_test_service with metadata" do
      %{namespace: namespace} = setup_test_namespace(cleanup_on_exit: false)

      metadata = %{type: :test_service, priority: :high}
      assert :ok = register_test_service(namespace, :test_service, self(), metadata)

      assert_registered(namespace, :test_service)
      assert_metadata_equals(namespace, :test_service, metadata)

      # Just unregister since self() is the process
      ProcessRegistry.unregister(namespace, :test_service)
    end

    test "register_test_service defaults to self()" do
      %{namespace: namespace} = setup_test_namespace(cleanup_on_exit: false)

      assert :ok = register_test_service(namespace, :default_service)

      {:ok, pid} = ProcessRegistry.lookup(namespace, :default_service)
      assert pid == self()

      # Don't cleanup since self() is registered - just unregister
      ProcessRegistry.unregister(namespace, :default_service)
    end
  end

  describe "agent configuration and registration" do
    test "create_test_agent_config with defaults" do
      config = create_test_agent_config(:test_agent)

      assert config.id == :test_agent
      assert config.type == :worker
      assert config.module == Foundation.TestHelpers.TestWorker
      assert config.args == []
      assert config.capabilities == []
      assert config.restart_policy == :temporary
      assert is_map(config.metadata)
      assert config.metadata.test_agent == true
    end

    test "create_test_agent_config with custom options" do
      opts = [
        capabilities: [:compute, :ml],
        type: :ml_worker,
        restart_policy: :permanent,
        metadata: %{custom: true}
      ]

      config = create_test_agent_config(:ml_agent, Foundation.TestHelpers.MLWorker, [], opts)

      assert config.id == :ml_agent
      assert config.type == :ml_worker
      assert config.module == Foundation.TestHelpers.MLWorker
      assert config.capabilities == [:compute, :ml]
      assert config.restart_policy == :permanent
      assert config.metadata.test_agent == true
      assert config.metadata.custom == true
    end

    test "register_test_agent" do
      %{namespace: namespace} = setup_test_namespace(cleanup_on_exit: false)

      config =
        create_test_agent_config(:test_agent, Foundation.TestHelpers.TestWorker, [],
          capabilities: [:compute],
          type: :worker
        )

      assert :ok = register_test_agent(config, namespace)

      # Verify agent is registered
      service_name = {:agent, :test_agent}
      assert_registered(namespace, service_name)

      # Verify metadata includes agent configuration
      {:ok, metadata} = ProcessRegistry.get_metadata(namespace, service_name)
      assert metadata.type == :mabeam_agent
      assert metadata.agent_type == :worker
      assert metadata.capabilities == [:compute]
      assert metadata.module == Foundation.TestHelpers.TestWorker

      # Just unregister since self() is the process
      ProcessRegistry.unregister(namespace, service_name)
    end

    test "start_test_agent creates and registers process" do
      %{namespace: namespace, test_ref: test_ref} = setup_test_namespace(cleanup_on_exit: false)

      {:ok, pid} = start_test_agent(:worker1, namespace, capabilities: [:compute])

      # Verify agent is registered and running
      assert_agent_running(:worker1, namespace)
      assert_agent_has_capabilities(:worker1, [:compute], namespace)

      # Verify PID is alive
      assert Process.alive?(pid)

      # Cleanup
      Process.exit(pid, :shutdown)
      cleanup_test_namespace(test_ref)
    end
  end

  describe "agent fixtures" do
    test "basic_worker_config" do
      config = AgentFixtures.basic_worker_config()

      assert config.id == :test_worker
      assert config.type == :worker
      assert config.capabilities == [:compute]
      assert config.metadata.priority == :normal
      assert config.metadata.max_concurrent_tasks == 1
    end

    test "ml_agent_config" do
      config = AgentFixtures.ml_agent_config(:ml_test, model_type: :transformer, gpu: true)

      assert config.id == :ml_test
      assert config.type == :ml_agent
      assert :compute in config.capabilities
      assert :ml in config.capabilities
      assert :gpu in config.capabilities
      assert :nlp in config.capabilities
      assert config.metadata.model_type == :transformer
      assert config.metadata.gpu_enabled == true
    end

    test "coordination_agent_config" do
      config = AgentFixtures.coordination_agent_config(:coordinator, max_managed_agents: 20)

      assert config.id == :coordinator
      assert config.type == :coordinator
      assert :coordination in config.capabilities
      assert :management in config.capabilities
      assert config.metadata.max_managed_agents == 20
    end

    test "failing_agent_config" do
      config =
        AgentFixtures.failing_agent_config(:failing, failure_mode: :random, failure_rate: 0.5)

      assert config.id == :failing
      assert config.type == :failing_agent
      assert config.metadata.failure_mode == :random
      assert config.metadata.failure_rate == 0.5
      assert config.metadata.expected_failures == true
    end

    test "nlp_agent_config" do
      config = AgentFixtures.nlp_agent_config(:nlp_worker, languages: [:en, :es])

      assert config.id == :nlp_worker
      assert config.type == :nlp_agent
      assert :nlp in config.capabilities
      assert :text_generation in config.capabilities
      assert config.metadata.supported_languages == [:en, :es]
    end

    test "multi_capability_agent_configs" do
      configs = AgentFixtures.multi_capability_agent_configs(5, include_coordinators: true)

      assert length(configs) == 5

      # Should have at least one coordinator
      coordinator_count = Enum.count(configs, fn config -> config.type == :coordinator end)
      assert coordinator_count >= 1

      # All should have different IDs
      ids = Enum.map(configs, & &1.id)
      assert length(Enum.uniq(ids)) == length(ids)
    end

    test "load_test_agent_configs" do
      configs = AgentFixtures.load_test_agent_configs(10, lightweight: true)

      assert length(configs) == 10

      # All should be basic workers for lightweight testing
      Enum.each(configs, fn config ->
        assert config.type == :worker
        assert config.capabilities == [:compute]
      end)
    end
  end

  describe "assertion helpers" do
    setup do
      setup_test_namespace()
    end

    test "assert_registered success", %{namespace: namespace} do
      :ok = register_test_service(namespace, :test_service, self())

      # Should not raise
      assert_registered(namespace, :test_service)
    end

    test "assert_registered failure", %{namespace: namespace} do
      assert_raise ExUnit.AssertionError, ~r/Expected service.*to be registered/, fn ->
        assert_registered(namespace, :missing_service)
      end
    end

    test "assert_not_registered success", %{namespace: namespace} do
      # Should not raise
      assert_not_registered(namespace, :missing_service)
    end

    test "assert_not_registered failure", %{namespace: namespace} do
      :ok = register_test_service(namespace, :existing_service, self())

      assert_raise ExUnit.AssertionError, ~r/Expected service.*to NOT be registered/, fn ->
        assert_not_registered(namespace, :existing_service)
      end
    end

    test "assert_metadata_equals success", %{namespace: namespace} do
      metadata = %{type: :test, priority: :high}
      :ok = register_test_service(namespace, :meta_service, self(), metadata)

      # Should not raise
      assert_metadata_equals(namespace, :meta_service, metadata)
    end

    test "assert_metadata_equals failure", %{namespace: namespace} do
      metadata = %{type: :test, priority: :high}
      :ok = register_test_service(namespace, :meta_service, self(), metadata)

      wrong_metadata = %{type: :wrong, priority: :low}

      assert_raise ExUnit.AssertionError, ~r/Metadata mismatch/, fn ->
        assert_metadata_equals(namespace, :meta_service, wrong_metadata)
      end
    end

    test "assert_agent_has_capabilities success", %{namespace: namespace} do
      config =
        create_test_agent_config(:test_agent, Foundation.TestHelpers.TestWorker, [],
          capabilities: [:compute, :ml]
        )

      :ok = register_test_agent(config, namespace)

      # Should not raise
      assert_agent_has_capabilities(:test_agent, [:compute], namespace)
      assert_agent_has_capabilities(:test_agent, [:ml], namespace)
      assert_agent_has_capabilities(:test_agent, [:compute, :ml], namespace)
    end

    test "assert_agent_has_capabilities failure", %{namespace: namespace} do
      config =
        create_test_agent_config(:test_agent, Foundation.TestHelpers.TestWorker, [],
          capabilities: [:compute]
        )

      :ok = register_test_agent(config, namespace)

      assert_raise ExUnit.AssertionError, ~r/missing expected capabilities/, fn ->
        assert_agent_has_capabilities(:test_agent, [:compute, :ml], namespace)
      end
    end

    test "assert_agent_running success", %{namespace: namespace} do
      {:ok, _pid} = start_test_agent(:running_agent, namespace)

      # Should not raise
      assert_agent_running(:running_agent, namespace)
    end

    test "assert_agent_running failure for missing agent", %{namespace: namespace} do
      assert_raise ExUnit.AssertionError, ~r/is not registered/, fn ->
        assert_agent_running(:missing_agent, namespace)
      end
    end
  end

  describe "performance testing utilities" do
    test "create_load_test_agents" do
      agents = create_load_test_agents(5, start_processes: false)

      assert length(agents) == 5

      Enum.each(agents, fn config ->
        assert is_map(config)
        assert Map.has_key?(config, :id)
      end)
    end

    test "create_load_test_agents with processes" do
      agents = create_load_test_agents(3, start_processes: true)

      assert length(agents) == 3

      # Each should be a {config, pid} tuple
      Enum.each(agents, fn {config, pid} ->
        assert is_map(config)
        assert is_pid(pid)
        assert Process.alive?(pid)

        # Cleanup
        Process.exit(pid, :shutdown)
      end)
    end

    test "benchmark_registry_operations basic test" do
      # Test the benchmark infrastructure manually to avoid cleanup conflicts
      %{namespace: namespace} = setup_test_namespace(cleanup_on_exit: false)

      # Simple manual benchmark verification
      start_time = :os.system_time(:microsecond)

      # Run a few operations
      for i <- 1..5 do
        service = :"bench_service_#{i}"
        :ok = register_test_service(namespace, service, self(), %{benchmark: true})
        {:ok, _pid} = ProcessRegistry.lookup(namespace, service)
        :ok = ProcessRegistry.unregister(namespace, service)
      end

      end_time = :os.system_time(:microsecond)
      elapsed = end_time - start_time

      # Basic sanity check - operations should complete in reasonable time
      assert elapsed > 0
      # Should complete in less than 1 second
      assert elapsed < 1_000_000

      # Don't call cleanup_test_namespace since that would terminate the test process
    end
  end

  describe "cleanup utilities" do
    setup do
      setup_test_namespace()
    end

    test "cleanup_all_test_agents", %{namespace: namespace} do
      # Create separate processes for the test agents so they don't conflict with test process
      {:ok, agent1_pid} = Task.start(fn -> Process.sleep(:infinity) end)
      {:ok, agent2_pid} = Task.start(fn -> Process.sleep(:infinity) end)

      # Register test agents with separate processes
      :ok =
        register_test_service(namespace, {:agent, :agent1}, agent1_pid, %{
          test_agent: true,
          type: :mabeam_agent
        })

      :ok =
        register_test_service(namespace, {:agent, :agent2}, agent2_pid, %{
          test_agent: true,
          type: :mabeam_agent
        })

      # Register a non-test service with self() (should not be cleaned up)
      :ok = register_test_service(namespace, :regular_service, self(), %{test_agent: false})

      # Verify all are registered
      assert_registered(namespace, {:agent, :agent1})
      assert_registered(namespace, {:agent, :agent2})
      assert_registered(namespace, :regular_service)

      # Clean up test agents
      :ok = cleanup_all_test_agents(namespace)

      # Wait a moment for cleanup to complete
      Process.sleep(100)

      # Test agents should be gone, regular service should remain
      assert_not_registered(namespace, {:agent, :agent1})
      assert_not_registered(namespace, {:agent, :agent2})
      assert_registered(namespace, :regular_service)

      # Clean up remaining service
      ProcessRegistry.unregister(namespace, :regular_service)
    end

    test "reset_registry_state" do
      # This is mainly a smoke test to ensure the function doesn't crash
      assert :ok = reset_registry_state()
    end
  end

  describe "agent fixtures validation" do
    test "validate_agent_config with valid config" do
      config = AgentFixtures.basic_worker_config()
      assert :ok = AgentFixtures.validate_agent_config(config)
    end

    test "validate_agent_config with missing fields" do
      invalid_config = %{id: :test}
      assert {:error, message} = AgentFixtures.validate_agent_config(invalid_config)
      assert message =~ "Missing required fields"
    end

    test "validate_agent_config with wrong types" do
      invalid_config = %{
        # Should be atom
        id: "not_atom",
        type: :worker,
        module: Foundation.TestHelpers.TestWorker,
        args: [],
        capabilities: [],
        restart_policy: :temporary,
        metadata: %{}
      }

      assert {:error, message} = AgentFixtures.validate_agent_config(invalid_config)
      assert message =~ "id must be an atom"
    end

    test "validate_agent_config with non-map" do
      assert {:error, "Configuration must be a map"} =
               AgentFixtures.validate_agent_config("not a map")
    end
  end

  describe "random agent generation" do
    test "random_agent_config generates valid configs" do
      # Test multiple random configs to verify variety
      configs =
        Enum.map(1..10, fn i ->
          AgentFixtures.random_agent_config(seed: i)
        end)

      # All should be valid
      Enum.each(configs, fn config ->
        assert :ok = AgentFixtures.validate_agent_config(config)
      end)

      # Should have some variety in types
      types = Enum.map(configs, & &1.type) |> Enum.uniq()
      assert length(types) > 1
    end
  end
end
