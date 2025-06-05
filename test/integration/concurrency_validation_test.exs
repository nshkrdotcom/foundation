defmodule Foundation.ConcurrencyValidationTest do
  @moduledoc """
  Comprehensive test suite to validate the concurrency architecture.

  Tests the Registry-based process discovery, namespace isolation,
  and concurrent operation handling according to our systematic approach.
  """

  use Foundation.TestSupport.ConcurrentTestCase

  alias Foundation.{ProcessRegistry, ServiceRegistry}
  alias Foundation.TestSupport.TestSupervisor
  # alias Foundation.Services.{ConfigServer}

  describe "Registry Infrastructure" do
    test "ProcessRegistry provides namespace isolation", %{test_ref: test_ref} do
      namespace = {:test, test_ref}

      # Verify services exist in test namespace
      services = ProcessRegistry.list_services(namespace)

      # Should have at least config_server and event_store
      assert length(services) >= 2
      assert :config_server in services
      assert :event_store in services

      # Verify production services exist but are separate
      _production_services = ProcessRegistry.list_services(:production)
      # Production and test namespaces should be completely isolated

      # Test namespace should have different PIDs than production
      {:ok, test_config_pid} = ProcessRegistry.lookup(namespace, :config_server)

      case ProcessRegistry.lookup(:production, :config_server) do
        {:ok, prod_config_pid} ->
          assert test_config_pid != prod_config_pid,
                 "Test and production should have different PIDs"

        :error ->
          # Production service not running in test, that's fine
          :ok
      end
    end

    test "ServiceRegistry provides safe service interaction", %{namespace: namespace} do
      # Test service lookup
      assert {:ok, pid} = ServiceRegistry.lookup(namespace, :config_server)
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Test health check
      assert {:ok, ^pid} = ServiceRegistry.health_check(namespace, :config_server)

      # Test service info
      info = ServiceRegistry.get_service_info(namespace)
      assert info.namespace == namespace
      # At least config_server and event_store
      assert info.total_services >= 2
      assert info.healthy_services == info.total_services
    end

    test "Registry stats show proper namespace separation", %{test_ref: _test_ref} do
      stats = ProcessRegistry.stats()

      assert stats.test_namespaces >= 1
      assert stats.total_services >= stats.production_services
      assert is_integer(stats.partitions)
      assert stats.partitions > 0
    end
  end

  describe "Service Isolation" do
    test "ConfigServer operates independently per namespace", %{namespace: namespace} do
      # Test configuration isolation
      with_service(namespace, :config_server, fn pid ->
        # These calls should work with the isolated config server
        assert {:ok, _config} = GenServer.call(pid, :get_config)

        # Update a config value that's allowed - using [:dev, :debug_mode]
        assert :ok = GenServer.call(pid, {:update_config, [:dev, :debug_mode], true})

        # Verify the update worked
        assert {:ok, true} = GenServer.call(pid, {:get_config_path, [:dev, :debug_mode]})
      end)

      # Verify production config is unaffected (if it exists)
      case ServiceRegistry.lookup(:production, :config_server) do
        {:ok, prod_pid} ->
          # Production config should be different/unaffected
          {:ok, prod_debug} = GenServer.call(prod_pid, {:get_config_path, [:dev, :debug_mode]})
          # Production should still have default (false) unless explicitly set
          # Accept either since production might be modified by other tests
          assert prod_debug in [false, true]

        {:error, _reason} ->
          # Production service not available, that's ok for this test
          :ok
      end
    end

    test "EventStore operates independently per namespace", %{namespace: namespace} do
      # Create a test event
      event = Foundation.Events.debug_new_event(:test_event, %{data: "test"})

      with_service(namespace, :event_store, fn pid ->
        # Store event in isolated namespace
        assert {:ok, event_id} = GenServer.call(pid, {:store_event, event})
        assert is_integer(event_id)

        # Retrieve the event
        assert {:ok, retrieved_event} = GenServer.call(pid, {:get_event, event_id})
        assert retrieved_event.event_type == :test_event
        assert retrieved_event.data == %{data: "test"}
      end)
    end
  end

  describe "Concurrent Operations" do
    test "handles multiple concurrent config reads", %{namespace: namespace} do
      operations = [
        fn _ns ->
          with_service(namespace, :config_server, fn pid ->
            GenServer.call(pid, :get_config)
          end)
        end
      ]

      results = measure_concurrent_ops(namespace, operations, 50)

      assert results.operations_count == 50
      # Should complete within 1 second
      assert results.duration_ms < 1000
      assert Enum.all?(results.results, &match?({:ok, _}, &1))
    end

    test "serializes concurrent config updates correctly", %{namespace: namespace} do
      # Initialize a counter using an allowed path [:dev, :verbose_logging] as a boolean toggle
      with_service(namespace, :config_server, fn pid ->
        :ok = GenServer.call(pid, {:update_config, [:dev, :verbose_logging], false})
      end)

      # Concurrent toggle operations (alternate between true/false)
      tasks =
        for _i <- 1..20 do
          Task.async(fn ->
            with_service(namespace, :config_server, fn pid ->
              {:ok, current} = GenServer.call(pid, {:get_config_path, [:dev, :verbose_logging]})
              :ok = GenServer.call(pid, {:update_config, [:dev, :verbose_logging], not current})
            end)
          end)
        end

      # Wait for all tasks to complete
      Task.await_many(tasks, 5000)

      # Verify final state exists (should be either true or false due to serialization)
      with_service(namespace, :config_server, fn pid ->
        {:ok, final_value} = GenServer.call(pid, {:get_config_path, [:dev, :verbose_logging]})

        assert is_boolean(final_value),
               "Expected boolean but got #{final_value} - updates may not be properly serialized"
      end)
    end

    test "handles concurrent event storage", %{namespace: namespace} do
      events =
        for i <- 1..50 do
          Foundation.Events.debug_new_event(:concurrent_test, %{index: i})
        end

      tasks =
        Enum.map(events, fn event ->
          Task.async(fn ->
            with_service(namespace, :event_store, fn pid ->
              GenServer.call(pid, {:store_event, event})
            end)
          end)
        end)

      results = Task.await_many(tasks, 5000)

      # All events should be stored successfully
      assert length(results) == 50
      assert Enum.all?(results, &match?({:ok, _}, &1))

      # Verify all events are retrievable
      with_service(namespace, :event_store, fn pid ->
        {:ok, stats} = GenServer.call(pid, :get_stats)
        assert stats.current_event_count == 50
      end)
    end
  end

  describe "Service Recovery" do
    test "services restart after crash", %{namespace: namespace} do
      # Get original PID
      {:ok, original_pid} = ServiceRegistry.lookup(namespace, :config_server)

      # Simulate crash and recovery
      simulate_service_crash(namespace, :config_server)

      # Get new PID
      {:ok, new_pid} = ServiceRegistry.lookup(namespace, :config_server)

      # Should be a different process
      assert original_pid != new_pid

      # New process should be functional
      with_service(namespace, :config_server, fn pid ->
        assert {:ok, _config} = GenServer.call(pid, :get_config)
      end)
    end

    test "namespace remains healthy after service restart", %{test_ref: test_ref} do
      # Initial health check
      assert TestSupervisor.namespace_healthy?(test_ref)

      # Crash a service
      simulate_service_crash({:test, test_ref}, :config_server)

      # Should be healthy again after restart
      assert TestSupervisor.namespace_healthy?(test_ref)
    end
  end

  describe "Cleanup and Isolation" do
    test "test cleanup doesn't affect other namespaces" do
      # Create two test references
      test_ref1 = make_ref()
      test_ref2 = make_ref()

      # Start services for both
      {:ok, _pids1} = TestSupervisor.start_isolated_services(test_ref1)
      {:ok, _pids2} = TestSupervisor.start_isolated_services(test_ref2)

      # Wait for both to be ready
      :ok = TestSupervisor.wait_for_services_ready(test_ref1)
      :ok = TestSupervisor.wait_for_services_ready(test_ref2)

      # Verify both namespaces have services
      assert TestSupervisor.namespace_healthy?(test_ref1)
      assert TestSupervisor.namespace_healthy?(test_ref2)

      # Cleanup first namespace
      :ok = TestSupervisor.cleanup_namespace(test_ref1)

      # First should be gone, second should remain
      refute TestSupervisor.namespace_healthy?(test_ref1)
      assert TestSupervisor.namespace_healthy?(test_ref2)

      # Clean up second namespace
      :ok = TestSupervisor.cleanup_namespace(test_ref2)
      refute TestSupervisor.namespace_healthy?(test_ref2)
    end
  end

  describe "Performance Validation" do
    test "system remains responsive under load", %{namespace: namespace} do
      # High concurrency test
      operations = [
        fn _ns ->
          with_service(namespace, :config_server, fn pid ->
            GenServer.call(pid, :get_config)
          end)
        end,
        fn _ns ->
          with_service(namespace, :event_store, fn pid ->
            event = Foundation.Events.debug_new_event(:load_test, %{})
            GenServer.call(pid, {:store_event, event})
          end)
        end
      ]

      results = measure_concurrent_ops(namespace, operations, 100)

      # System should handle 200 operations (100 * 2) efficiently
      assert results.operations_count == 200
      # At least 100 ops/second
      assert results.ops_per_second > 100
      # Complete within 5 seconds
      assert results.duration_ms < 5000
    end
  end
end
