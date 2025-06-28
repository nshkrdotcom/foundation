defmodule Foundation.ProcessRegistryTest do
  # Changed to false to avoid interference
  use ExUnit.Case, async: false
  @moduletag :foundation

  alias Foundation.ProcessRegistry

  describe "child_spec/1" do
    test "returns valid Registry child spec" do
      spec = ProcessRegistry.child_spec([])

      assert %{
               id: Foundation.ProcessRegistry,
               start: {Registry, :start_link, _},
               type: :supervisor,
               restart: :permanent,
               shutdown: :infinity
             } = spec
    end

    test "uses unique keys configuration" do
      spec = ProcessRegistry.child_spec([])
      {_module, _function, [config]} = spec.start

      assert Keyword.get(config, :keys) == :unique
      assert Keyword.get(config, :name) == ProcessRegistry
    end

    test "configures correct number of partitions" do
      spec = ProcessRegistry.child_spec([])
      {_module, _function, [config]} = spec.start

      expected_partitions = System.schedulers_online()
      assert Keyword.get(config, :partitions) == expected_partitions
    end
  end

  describe "register/3" do
    setup do
      test_ref = make_ref()
      namespace = {:test, test_ref}
      service = :test_service

      on_exit(fn ->
        ProcessRegistry.cleanup_test_namespace(test_ref)
      end)

      %{namespace: namespace, service: service, test_ref: test_ref}
    end

    test "successfully registers a process", %{namespace: namespace, service: service} do
      {:ok, pid} = Agent.start_link(fn -> %{} end)

      assert :ok = ProcessRegistry.register(namespace, service, pid)

      # Verify registration
      assert {:ok, ^pid} = ProcessRegistry.lookup(namespace, service)

      Agent.stop(pid)
    end

    test "returns error when service already registered", %{namespace: namespace, service: service} do
      {:ok, pid1} = Agent.start_link(fn -> %{} end)
      {:ok, pid2} = Agent.start_link(fn -> %{} end)

      assert :ok = ProcessRegistry.register(namespace, service, pid1)

      assert {:error, {:already_registered, ^pid1}} =
               ProcessRegistry.register(namespace, service, pid2)

      Agent.stop(pid1)
      Agent.stop(pid2)
    end

    test "requires valid PID parameter", %{namespace: namespace, service: service} do
      # With metadata support, invalid PIDs now return error instead of raising
      assert {:error, :invalid_pid} = ProcessRegistry.register(namespace, service, "not_a_pid")
    end

    test "supports production namespace" do
      {:ok, pid} = Agent.start_link(fn -> %{} end)
      service = :"test_production_#{:rand.uniform(10_000)}"

      assert :ok = ProcessRegistry.register(:production, service, pid)
      assert {:ok, ^pid} = ProcessRegistry.lookup(:production, service)

      ProcessRegistry.unregister(:production, service)
      Agent.stop(pid)
    end
  end

  describe "lookup/2" do
    setup do
      test_ref = make_ref()
      namespace = {:test, test_ref}

      on_exit(fn ->
        ProcessRegistry.cleanup_test_namespace(test_ref)
      end)

      %{namespace: namespace, test_ref: test_ref}
    end

    test "returns registered process PID", %{namespace: namespace} do
      service = :lookup_test_service
      {:ok, pid} = Agent.start_link(fn -> %{} end)

      ProcessRegistry.register(namespace, service, pid)

      assert {:ok, ^pid} = ProcessRegistry.lookup(namespace, service)

      Agent.stop(pid)
    end

    test "returns error for unregistered service", %{namespace: namespace} do
      assert :error = ProcessRegistry.lookup(namespace, :nonexistent_service)
    end

    test "returns error after process terminates", %{namespace: namespace} do
      service = :terminating_service
      {:ok, pid} = Agent.start_link(fn -> %{} end)

      ProcessRegistry.register(namespace, service, pid)
      Agent.stop(pid)

      # Registry should automatically clean up dead processes
      Process.sleep(10)
      assert :error = ProcessRegistry.lookup(namespace, service)
    end

    test "handles namespace isolation", %{namespace: test_namespace} do
      service = :isolation_test

      # Register in test namespace
      {:ok, test_pid} = Agent.start_link(fn -> %{} end)
      ProcessRegistry.register(test_namespace, service, test_pid)

      # Register same service in production namespace
      {:ok, prod_pid} = Agent.start_link(fn -> %{} end)
      production_service = :"isolation_test_#{:rand.uniform(10_000)}"
      ProcessRegistry.register(:production, production_service, prod_pid)

      # Verify isolation
      assert {:ok, ^test_pid} = ProcessRegistry.lookup(test_namespace, service)
      assert {:ok, ^prod_pid} = ProcessRegistry.lookup(:production, production_service)
      assert :error = ProcessRegistry.lookup(test_namespace, production_service)
      assert :error = ProcessRegistry.lookup(:production, service)

      ProcessRegistry.unregister(:production, production_service)
      Agent.stop(test_pid)
      Agent.stop(prod_pid)
    end
  end

  describe "unregister/2" do
    setup do
      test_ref = make_ref()
      namespace = {:test, test_ref}

      on_exit(fn ->
        ProcessRegistry.cleanup_test_namespace(test_ref)
      end)

      %{namespace: namespace, test_ref: test_ref}
    end

    test "unregisters existing service", %{namespace: namespace} do
      service = :unregister_test
      {:ok, pid} = Agent.start_link(fn -> %{} end)

      ProcessRegistry.register(namespace, service, pid)
      assert {:ok, ^pid} = ProcessRegistry.lookup(namespace, service)

      assert :ok = ProcessRegistry.unregister(namespace, service)
      assert :error = ProcessRegistry.lookup(namespace, service)

      Agent.stop(pid)
    end

    test "succeeds even if service not registered", %{namespace: namespace} do
      assert :ok = ProcessRegistry.unregister(namespace, :nonexistent_service)
    end

    test "returns :ok regardless of registration state", %{namespace: namespace} do
      service = :multiple_unregister_test

      # Unregister when not registered
      assert :ok = ProcessRegistry.unregister(namespace, service)

      # Register and unregister
      {:ok, pid} = Agent.start_link(fn -> %{} end)
      ProcessRegistry.register(namespace, service, pid)
      assert :ok = ProcessRegistry.unregister(namespace, service)

      # Unregister again
      assert :ok = ProcessRegistry.unregister(namespace, service)

      Agent.stop(pid)
    end
  end

  describe "list_services/1" do
    setup do
      test_ref = make_ref()
      namespace = {:test, test_ref}

      on_exit(fn ->
        ProcessRegistry.cleanup_test_namespace(test_ref)
      end)

      %{namespace: namespace, test_ref: test_ref}
    end

    test "returns empty list for namespace with no services", %{namespace: namespace} do
      assert [] = ProcessRegistry.list_services(namespace)
    end

    test "returns all registered services in namespace", %{namespace: namespace} do
      services = [:service_a, :service_b, :service_c]

      pids =
        for service <- services do
          {:ok, pid} = Agent.start_link(fn -> %{} end)
          ProcessRegistry.register(namespace, service, pid)
          pid
        end

      result = ProcessRegistry.list_services(namespace)

      # Should contain all services (order may vary)
      assert length(result) == 3
      assert Enum.all?(services, &(&1 in result))

      Enum.each(pids, &Agent.stop/1)
    end

    test "handles namespace isolation for list_services", %{namespace: test_namespace} do
      # Register services in test namespace
      test_service = :test_list_service
      {:ok, test_pid} = Agent.start_link(fn -> %{} end)
      ProcessRegistry.register(test_namespace, test_service, test_pid)

      # Register service in production namespace
      prod_service = :"prod_list_service_#{:rand.uniform(10_000)}"
      {:ok, prod_pid} = Agent.start_link(fn -> %{} end)
      ProcessRegistry.register(:production, prod_service, prod_pid)

      # Verify isolation
      test_services = ProcessRegistry.list_services(test_namespace)
      prod_services = ProcessRegistry.list_services(:production)

      assert test_service in test_services
      refute prod_service in test_services
      assert prod_service in prod_services
      refute test_service in prod_services

      ProcessRegistry.unregister(:production, prod_service)
      Agent.stop(test_pid)
      Agent.stop(prod_pid)
    end
  end

  describe "get_all_services/1" do
    setup do
      test_ref = make_ref()
      namespace = {:test, test_ref}

      on_exit(fn ->
        ProcessRegistry.cleanup_test_namespace(test_ref)
      end)

      %{namespace: namespace, test_ref: test_ref}
    end

    test "returns empty map for namespace with no services", %{namespace: namespace} do
      assert %{} = ProcessRegistry.get_all_services(namespace)
    end

    test "returns map of service names to PIDs", %{namespace: namespace} do
      services_and_pids = [
        {:service_x, Agent.start_link(fn -> %{} end)},
        {:service_y, Agent.start_link(fn -> %{} end)},
        {:service_z, Agent.start_link(fn -> %{} end)}
      ]

      # Register services
      for {service, {:ok, pid}} <- services_and_pids do
        ProcessRegistry.register(namespace, service, pid)
      end

      result = ProcessRegistry.get_all_services(namespace)

      # Verify map structure
      assert is_map(result)
      assert map_size(result) == 3

      for {service, {:ok, expected_pid}} <- services_and_pids do
        assert Map.get(result, service) == expected_pid
      end

      # Cleanup
      for {_service, {:ok, pid}} <- services_and_pids do
        Agent.stop(pid)
      end
    end
  end

  describe "registered?/2" do
    setup do
      test_ref = make_ref()
      namespace = {:test, test_ref}

      on_exit(fn ->
        ProcessRegistry.cleanup_test_namespace(test_ref)
      end)

      %{namespace: namespace, test_ref: test_ref}
    end

    test "returns true for registered service", %{namespace: namespace} do
      service = :registered_check_service
      {:ok, pid} = Agent.start_link(fn -> %{} end)

      ProcessRegistry.register(namespace, service, pid)

      assert ProcessRegistry.registered?(namespace, service) == true

      Agent.stop(pid)
    end

    test "returns false for unregistered service", %{namespace: namespace} do
      assert ProcessRegistry.registered?(namespace, :unregistered_service) == false
    end

    test "returns false after service unregisters", %{namespace: namespace} do
      service = :temp_registered_service
      {:ok, pid} = Agent.start_link(fn -> %{} end)

      ProcessRegistry.register(namespace, service, pid)
      assert ProcessRegistry.registered?(namespace, service) == true

      ProcessRegistry.unregister(namespace, service)
      assert ProcessRegistry.registered?(namespace, service) == false

      Agent.stop(pid)
    end
  end

  describe "count_services/1" do
    setup do
      test_ref = make_ref()
      namespace = {:test, test_ref}

      on_exit(fn ->
        ProcessRegistry.cleanup_test_namespace(test_ref)
      end)

      %{namespace: namespace, test_ref: test_ref}
    end

    test "returns 0 for empty namespace", %{namespace: namespace} do
      assert ProcessRegistry.count_services(namespace) == 0
    end

    test "returns correct count for registered services", %{namespace: namespace} do
      # Register multiple services
      services =
        for i <- 1..5 do
          service = :"count_test_service_#{i}"
          {:ok, pid} = Agent.start_link(fn -> %{} end)
          ProcessRegistry.register(namespace, service, pid)
          {service, pid}
        end

      assert ProcessRegistry.count_services(namespace) == 5

      # Cleanup
      for {_service, pid} <- services do
        Agent.stop(pid)
      end
    end

    test "count decreases when services are unregistered", %{namespace: namespace} do
      service = :count_decrease_service
      {:ok, pid} = Agent.start_link(fn -> %{} end)

      assert ProcessRegistry.count_services(namespace) == 0

      ProcessRegistry.register(namespace, service, pid)
      assert ProcessRegistry.count_services(namespace) == 1

      ProcessRegistry.unregister(namespace, service)
      assert ProcessRegistry.count_services(namespace) == 0

      Agent.stop(pid)
    end
  end

  describe "via_tuple/2" do
    test "returns correct via tuple structure" do
      namespace = :production
      service = :config_server

      result = ProcessRegistry.via_tuple(namespace, service)

      assert {:via, Registry, {ProcessRegistry, {^namespace, ^service}}} = result
    end

    test "supports test namespaces" do
      test_ref = make_ref()
      namespace = {:test, test_ref}
      service = :test_service

      result = ProcessRegistry.via_tuple(namespace, service)

      assert {:via, Registry, {ProcessRegistry, {^namespace, ^service}}} = result
    end
  end

  describe "cleanup_test_namespace/1" do
    test "terminates all processes in test namespace" do
      test_ref = make_ref()
      namespace = {:test, test_ref}

      # Register multiple services (use start instead of start_link to avoid linking)
      pids =
        for i <- 1..3 do
          service = :"cleanup_service_#{i}"
          {:ok, pid} = Agent.start(fn -> %{} end)
          ProcessRegistry.register(namespace, service, pid)
          pid
        end

      # Verify services are registered
      assert ProcessRegistry.count_services(namespace) == 3

      # Cleanup namespace
      assert :ok = ProcessRegistry.cleanup_test_namespace(test_ref)

      # Wait for cleanup to complete
      Process.sleep(150)

      # Verify all processes are terminated
      for pid <- pids do
        refute Process.alive?(pid)
      end

      # Verify services are unregistered
      assert ProcessRegistry.count_services(namespace) == 0
    end

    test "succeeds with empty namespace" do
      test_ref = make_ref()

      assert :ok = ProcessRegistry.cleanup_test_namespace(test_ref)
    end

    test "handles processes that exit gracefully" do
      test_ref = make_ref()
      namespace = {:test, test_ref}

      {:ok, pid} = Agent.start(fn -> %{} end)
      ProcessRegistry.register(namespace, :graceful_service, pid)

      # Stop the process normally
      Agent.stop(pid)

      # Cleanup should still succeed
      assert :ok = ProcessRegistry.cleanup_test_namespace(test_ref)
    end
  end

  describe "stats/0" do
    setup do
      test_ref = make_ref()
      namespace = {:test, test_ref}

      on_exit(fn ->
        ProcessRegistry.cleanup_test_namespace(test_ref)
      end)

      %{namespace: namespace, test_ref: test_ref}
    end

    test "returns comprehensive statistics" do
      stats = ProcessRegistry.stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :total_services)
      assert Map.has_key?(stats, :production_services)
      assert Map.has_key?(stats, :test_namespaces)
      assert Map.has_key?(stats, :partitions)
      assert Map.has_key?(stats, :partition_count)
      assert Map.has_key?(stats, :memory_usage_bytes)
      assert Map.has_key?(stats, :ets_table_info)

      # Verify types
      assert is_integer(stats.total_services)
      assert is_integer(stats.production_services)
      assert is_integer(stats.test_namespaces)
      assert is_integer(stats.partitions)
      assert is_integer(stats.partition_count)
      assert is_integer(stats.memory_usage_bytes)
      assert is_map(stats.ets_table_info)
    end

    test "correctly counts production and test services", %{namespace: test_namespace} do
      # Register services in test namespace
      {:ok, test_pid} = Agent.start_link(fn -> %{} end)
      ProcessRegistry.register(test_namespace, :stats_test_service, test_pid)

      # Register service in production namespace
      prod_service = :"stats_prod_service_#{:rand.uniform(10_000)}"
      {:ok, prod_pid} = Agent.start_link(fn -> %{} end)
      ProcessRegistry.register(:production, prod_service, prod_pid)

      stats = ProcessRegistry.stats()

      # Should have at least 1 test namespace and 1 production service
      assert stats.test_namespaces >= 1
      assert stats.production_services >= 1

      ProcessRegistry.unregister(:production, prod_service)
      Agent.stop(test_pid)
      Agent.stop(prod_pid)
    end

    test "partition count matches CPU cores" do
      stats = ProcessRegistry.stats()

      expected_partitions = System.schedulers_online()
      assert stats.partitions == expected_partitions
      assert stats.partition_count == expected_partitions
    end
  end
end
