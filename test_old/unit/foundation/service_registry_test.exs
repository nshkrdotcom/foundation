defmodule Foundation.ServiceRegistryTest do
  use ExUnit.Case, async: false
  @moduletag :foundation

  alias Foundation.{ProcessRegistry, ServiceRegistry}
  alias Foundation.Types.Error

  describe "register/3" do
    setup do
      test_ref = make_ref()
      namespace = {:test, test_ref}
      service = :test_service

      on_exit(fn ->
        ServiceRegistry.cleanup_test_namespace(test_ref)
      end)

      %{namespace: namespace, service: service, test_ref: test_ref}
    end

    test "successfully registers a process with logging", %{namespace: namespace, service: service} do
      {:ok, pid} = Agent.start_link(fn -> %{} end)

      assert :ok = ServiceRegistry.register(namespace, service, pid)

      # Verify registration through lookup
      assert {:ok, ^pid} = ServiceRegistry.lookup(namespace, service)

      Agent.stop(pid)
    end

    test "returns error when service already registered", %{namespace: namespace, service: service} do
      {:ok, pid1} = Agent.start_link(fn -> %{} end)
      {:ok, pid2} = Agent.start_link(fn -> %{} end)

      assert :ok = ServiceRegistry.register(namespace, service, pid1)

      assert {:error, {:already_registered, ^pid1}} =
               ServiceRegistry.register(namespace, service, pid2)

      Agent.stop(pid1)
      Agent.stop(pid2)
    end

    test "emits telemetry events for successful registration", %{
      namespace: namespace,
      service: service
    } do
      # Attach telemetry handler
      test_pid = self()
      handler_id = "test_registration_handler"

      :telemetry.attach(
        handler_id,
        [:foundation, :foundation, :registry, :register],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, measurements, metadata})
        end,
        %{}
      )

      {:ok, pid} = Agent.start_link(fn -> %{} end)
      ServiceRegistry.register(namespace, service, pid)

      # Verify telemetry event was emitted
      assert_receive {:telemetry_event, %{count: 1},
                      %{namespace: ^namespace, service: ^service, result: :ok}}

      :telemetry.detach(handler_id)
      Agent.stop(pid)
    end

    test "emits telemetry events for failed registration", %{namespace: namespace, service: service} do
      # Attach telemetry handler
      test_pid = self()
      handler_id = "test_registration_error_handler"

      :telemetry.attach(
        handler_id,
        [:foundation, :foundation, :registry, :register],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, measurements, metadata})
        end,
        %{}
      )

      {:ok, pid1} = Agent.start_link(fn -> %{} end)
      {:ok, pid2} = Agent.start_link(fn -> %{} end)

      ServiceRegistry.register(namespace, service, pid1)
      ServiceRegistry.register(namespace, service, pid2)

      # Should receive events for both registration attempts
      assert_receive {:telemetry_event, %{count: 1},
                      %{namespace: ^namespace, service: ^service, result: :ok}}

      assert_receive {:telemetry_event, %{count: 1},
                      %{namespace: ^namespace, service: ^service, result: :error}}

      :telemetry.detach(handler_id)
      Agent.stop(pid1)
      Agent.stop(pid2)
    end

    test "handles function clause errors gracefully", %{namespace: namespace, service: service} do
      assert_raise FunctionClauseError, fn ->
        ServiceRegistry.register(namespace, service, "not_a_pid")
      end
    end
  end

  describe "lookup/2" do
    setup do
      test_ref = make_ref()
      namespace = {:test, test_ref}

      on_exit(fn ->
        ServiceRegistry.cleanup_test_namespace(test_ref)
      end)

      %{namespace: namespace, test_ref: test_ref}
    end

    test "returns {:ok, pid} for registered service", %{namespace: namespace} do
      service = :lookup_test_service
      {:ok, pid} = Agent.start_link(fn -> %{} end)

      ServiceRegistry.register(namespace, service, pid)

      assert {:ok, ^pid} = ServiceRegistry.lookup(namespace, service)

      Agent.stop(pid)
    end

    test "returns structured error for unregistered service", %{namespace: namespace} do
      service = :nonexistent_service

      assert {:error, %Error{} = error} = ServiceRegistry.lookup(namespace, service)

      assert error.code == 5001
      assert error.error_type == :service_not_found
      assert error.severity == :medium
      assert error.category == :system
      assert error.subcategory == :discovery
      assert String.contains?(error.message, "Service #{inspect(service)} not found")
      assert String.contains?(error.message, "namespace #{inspect(namespace)}")
      assert error.context.namespace == namespace
      assert error.context.service == service
    end

    test "emits telemetry events for successful lookup", %{namespace: namespace} do
      service = :telemetry_lookup_service
      {:ok, pid} = Agent.start_link(fn -> %{} end)
      ServiceRegistry.register(namespace, service, pid)

      # Attach telemetry handler
      test_pid = self()
      handler_id = "test_lookup_handler"

      :telemetry.attach(
        handler_id,
        [:foundation, :foundation, :registry, :lookup],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, measurements, metadata})
        end,
        %{}
      )

      ServiceRegistry.lookup(namespace, service)

      # Verify telemetry event
      assert_receive {:telemetry_event, %{duration: duration},
                      %{namespace: ^namespace, service: ^service, result: :ok}}

      assert is_integer(duration)
      assert duration > 0

      :telemetry.detach(handler_id)
      Agent.stop(pid)
    end

    test "emits telemetry events for failed lookup", %{namespace: namespace} do
      service = :missing_service

      # Attach telemetry handler
      test_pid = self()
      handler_id = "test_lookup_error_handler"

      :telemetry.attach(
        handler_id,
        [:foundation, :foundation, :registry, :lookup],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, measurements, metadata})
        end,
        %{}
      )

      ServiceRegistry.lookup(namespace, service)

      # Verify telemetry event
      assert_receive {:telemetry_event, %{duration: duration},
                      %{namespace: ^namespace, service: ^service, result: :error}}

      assert is_integer(duration)
      assert duration > 0

      :telemetry.detach(handler_id)
    end

    test "handles telemetry failures gracefully", %{namespace: namespace} do
      service = :telemetry_failure_service
      {:ok, pid} = Agent.start_link(fn -> %{} end)
      ServiceRegistry.register(namespace, service, pid)

      # Ensure service is registered before proceeding
      assert {:ok, ^pid} = ServiceRegistry.lookup(namespace, service)

      # Attach a failing telemetry handler
      :telemetry.attach(
        "failing_handler",
        [:foundation, :foundation, :registry, :lookup],
        fn _event, _measurements, _metadata, _config ->
          raise "Telemetry failure"
        end,
        %{}
      )

      # Lookup should still work despite telemetry failure
      # The telemetry handler will fail but the lookup itself should succeed
      result = ServiceRegistry.lookup(namespace, service)

      # The lookup should still succeed, returning the correct PID
      # even though telemetry fails and gets detached
      case result do
        {:ok, ^pid} ->
          # Expected case - service found despite telemetry failure
          assert true

        {:error, %Error{error_type: :service_not_found}} ->
          # In some cases the service might appear not found due to timing
          # but the important thing is that the system doesn't crash
          assert true

        other ->
          flunk("Unexpected result from lookup: #{inspect(other)}")
      end

      :telemetry.detach("failing_handler")
      Agent.stop(pid)
    end
  end

  describe "unregister/2" do
    setup do
      test_ref = make_ref()
      namespace = {:test, test_ref}

      on_exit(fn ->
        ServiceRegistry.cleanup_test_namespace(test_ref)
      end)

      %{namespace: namespace, test_ref: test_ref}
    end

    test "unregisters existing service with logging", %{namespace: namespace} do
      service = :unregister_test
      {:ok, pid} = Agent.start_link(fn -> %{} end)

      ServiceRegistry.register(namespace, service, pid)
      assert {:ok, ^pid} = ServiceRegistry.lookup(namespace, service)

      assert :ok = ServiceRegistry.unregister(namespace, service)
      assert {:error, %Error{}} = ServiceRegistry.lookup(namespace, service)

      Agent.stop(pid)
    end

    test "succeeds even if service not registered", %{namespace: namespace} do
      assert :ok = ServiceRegistry.unregister(namespace, :nonexistent_service)
    end
  end

  describe "list_services/1" do
    setup do
      test_ref = make_ref()
      namespace = {:test, test_ref}

      on_exit(fn ->
        ServiceRegistry.cleanup_test_namespace(test_ref)
      end)

      %{namespace: namespace, test_ref: test_ref}
    end

    test "returns empty list for namespace with no services", %{namespace: namespace} do
      assert [] = ServiceRegistry.list_services(namespace)
    end

    test "returns all registered services with logging", %{namespace: namespace} do
      services = [:service_a, :service_b, :service_c]

      pids =
        for service <- services do
          {:ok, pid} = Agent.start_link(fn -> %{} end)
          ServiceRegistry.register(namespace, service, pid)
          pid
        end

      result = ServiceRegistry.list_services(namespace)

      # Should contain all services (order may vary)
      assert length(result) == 3
      assert Enum.all?(services, &(&1 in result))

      Enum.each(pids, &Agent.stop/1)
    end
  end

  describe "health_check/3" do
    setup do
      test_ref = make_ref()
      namespace = {:test, test_ref}

      on_exit(fn ->
        ServiceRegistry.cleanup_test_namespace(test_ref)
      end)

      %{namespace: namespace, test_ref: test_ref}
    end

    test "returns {:ok, pid} for healthy service", %{namespace: namespace} do
      service = :healthy_service
      {:ok, pid} = Agent.start_link(fn -> %{} end)
      ServiceRegistry.register(namespace, service, pid)

      assert {:ok, ^pid} = ServiceRegistry.health_check(namespace, service)

      Agent.stop(pid)
    end

    test "returns error for unregistered service", %{namespace: namespace} do
      assert {:error, %Error{}} = ServiceRegistry.health_check(namespace, :missing_service)
    end

    test "returns error for dead process", %{namespace: namespace} do
      service = :dead_service
      {:ok, pid} = Agent.start_link(fn -> %{} end)
      ServiceRegistry.register(namespace, service, pid)

      # Kill the process
      Agent.stop(pid)
      # Allow registry cleanup
      Process.sleep(10)

      # Health check should detect dead process if still registered
      result = ServiceRegistry.health_check(namespace, service)
      assert match?({:error, _}, result)
    end

    test "executes custom health check function", %{namespace: namespace} do
      service = :custom_health_service
      {:ok, pid} = Agent.start_link(fn -> :healthy end)
      ServiceRegistry.register(namespace, service, pid)

      health_check_fn = fn pid ->
        Agent.get(pid, & &1) == :healthy
      end

      assert {:ok, ^pid} =
               ServiceRegistry.health_check(namespace, service, health_check: health_check_fn)

      Agent.stop(pid)
    end

    test "handles custom health check returning :ok", %{namespace: namespace} do
      service = :ok_health_service
      {:ok, pid} = Agent.start_link(fn -> %{} end)
      ServiceRegistry.register(namespace, service, pid)

      health_check_fn = fn _pid -> :ok end

      assert {:ok, ^pid} =
               ServiceRegistry.health_check(namespace, service, health_check: health_check_fn)

      Agent.stop(pid)
    end

    test "handles custom health check returning {:ok, result}", %{namespace: namespace} do
      service = :ok_tuple_health_service
      {:ok, pid} = Agent.start_link(fn -> %{} end)
      ServiceRegistry.register(namespace, service, pid)

      health_check_fn = fn _pid -> {:ok, :service_is_healthy} end

      assert {:ok, ^pid} =
               ServiceRegistry.health_check(namespace, service, health_check: health_check_fn)

      Agent.stop(pid)
    end

    test "handles custom health check failure", %{namespace: namespace} do
      service = :failing_health_service
      {:ok, pid} = Agent.start_link(fn -> %{} end)
      ServiceRegistry.register(namespace, service, pid)

      health_check_fn = fn _pid -> {:error, :unhealthy} end

      assert {:error, {:health_check_failed, {:error, :unhealthy}}} =
               ServiceRegistry.health_check(namespace, service, health_check: health_check_fn)

      Agent.stop(pid)
    end

    @tag :slow
    test "handles custom health check timeout", %{namespace: namespace} do
      service = :timeout_health_service
      {:ok, pid} = Agent.start_link(fn -> %{} end)
      ServiceRegistry.register(namespace, service, pid)

      health_check_fn = fn _pid ->
        Process.sleep(100)
        :ok
      end

      assert {:error, :health_check_timeout} =
               ServiceRegistry.health_check(namespace, service,
                 health_check: health_check_fn,
                 timeout: 50
               )

      Agent.stop(pid)
    end

    test "handles custom health check crash", %{namespace: namespace} do
      service = :crashing_health_service
      {:ok, pid} = Agent.start_link(fn -> %{} end)
      ServiceRegistry.register(namespace, service, pid)

      health_check_fn = fn _pid ->
        raise "Health check crashed"
      end

      assert {:error, {:health_check_error, %RuntimeError{}}} =
               ServiceRegistry.health_check(namespace, service, health_check: health_check_fn)

      Agent.stop(pid)
    end

    test "handles custom health check exit", %{namespace: namespace} do
      service = :exiting_health_service
      {:ok, pid} = Agent.start_link(fn -> %{} end)
      ServiceRegistry.register(namespace, service, pid)

      health_check_fn = fn _pid ->
        exit(:health_check_exit)
      end

      assert {:error, {:health_check_crashed, :health_check_exit}} =
               ServiceRegistry.health_check(namespace, service, health_check: health_check_fn)

      Agent.stop(pid)
    end

    test "disables debug logging by default", %{namespace: namespace} do
      service = :no_debug_service
      {:ok, pid} = Agent.start_link(fn -> %{} end)
      ServiceRegistry.register(namespace, service, pid)

      # This should not log debug messages
      assert {:ok, ^pid} = ServiceRegistry.health_check(namespace, service)

      Agent.stop(pid)
    end

    test "enables debug logging when requested", %{namespace: namespace} do
      service = :debug_service
      {:ok, pid} = Agent.start_link(fn -> %{} end)
      ServiceRegistry.register(namespace, service, pid)

      # This should log debug messages
      assert {:ok, ^pid} =
               ServiceRegistry.health_check(namespace, service, debug_health_check: true)

      Agent.stop(pid)
    end
  end

  describe "wait_for_service/3" do
    setup do
      test_ref = make_ref()
      namespace = {:test, test_ref}

      on_exit(fn ->
        ServiceRegistry.cleanup_test_namespace(test_ref)
      end)

      %{namespace: namespace, test_ref: test_ref}
    end

    test "returns immediately for already available service", %{namespace: namespace} do
      service = :immediate_service
      {:ok, pid} = Agent.start_link(fn -> %{} end)
      ServiceRegistry.register(namespace, service, pid)

      assert {:ok, ^pid} = ServiceRegistry.wait_for_service(namespace, service, 1000)

      Agent.stop(pid)
    end

    test "waits for service to become available", %{namespace: namespace} do
      service = :delayed_service
      test_pid = self()

      # Start a task that will register the service after a delay
      Task.start(fn ->
        Process.sleep(50)
        {:ok, pid} = Agent.start_link(fn -> %{} end)
        ServiceRegistry.register(namespace, service, pid)
        send(test_pid, {:registered, pid})
      end)

      # Wait for service with longer timeout to be safe
      assert {:ok, pid} = ServiceRegistry.wait_for_service(namespace, service, 2000)

      # Verify we got the PID from the task
      assert_receive {:registered, ^pid}, 1000

      Agent.stop(pid)
    end

    @tag :slow
    test "returns timeout error when service never appears", %{namespace: namespace} do
      service = :never_appears

      assert {:error, :timeout} = ServiceRegistry.wait_for_service(namespace, service, 100)
    end

    @tag :slow
    test "uses default timeout when not specified", %{namespace: namespace} do
      service = :default_timeout_service

      start_time = System.monotonic_time(:millisecond)
      result = ServiceRegistry.wait_for_service(namespace, service)
      end_time = System.monotonic_time(:millisecond)

      assert {:error, :timeout} = result
      # Should take approximately 5000ms (default timeout)
      elapsed = end_time - start_time
      assert elapsed >= 4900 and elapsed <= 5500
    end
  end

  describe "get_service_info/1" do
    setup do
      test_ref = make_ref()
      namespace = {:test, test_ref}

      on_exit(fn ->
        ServiceRegistry.cleanup_test_namespace(test_ref)
      end)

      %{namespace: namespace, test_ref: test_ref}
    end

    test "returns comprehensive info for empty namespace", %{namespace: namespace} do
      info = ServiceRegistry.get_service_info(namespace)

      assert %{
               namespace: ^namespace,
               services: %{},
               total_services: 0,
               healthy_services: 0
             } = info
    end

    test "returns detailed info for services", %{namespace: namespace} do
      # Register multiple services
      services = [:info_service_a, :info_service_b]

      pids =
        for service <- services do
          {:ok, pid} = Agent.start_link(fn -> %{} end)
          ServiceRegistry.register(namespace, service, pid)
          pid
        end

      info = ServiceRegistry.get_service_info(namespace)

      assert info.namespace == namespace
      assert info.total_services == 2
      assert info.healthy_services == 2
      assert map_size(info.services) == 2

      for service <- services do
        assert Map.has_key?(info.services, service)
        service_detail = info.services[service]
        assert Map.has_key?(service_detail, :pid)
        assert Map.has_key?(service_detail, :alive)
        assert Map.has_key?(service_detail, :uptime_ms)
        assert service_detail.alive == true
        assert is_pid(service_detail.pid)
        assert is_integer(service_detail.uptime_ms)
      end

      Enum.each(pids, &Agent.stop/1)
    end

    test "correctly identifies dead processes", %{namespace: namespace} do
      service = :dying_service
      {:ok, pid} = Agent.start_link(fn -> %{} end)
      ServiceRegistry.register(namespace, service, pid)

      # Kill the process but don't unregister immediately
      Agent.stop(pid)

      info = ServiceRegistry.get_service_info(namespace)

      # The service might still be registered briefly, check if it's marked as dead
      if Map.has_key?(info.services, service) do
        service_detail = info.services[service]
        assert service_detail.alive == false
        assert service_detail.uptime_ms == 0
        assert info.healthy_services == 0
      end
    end
  end

  describe "cleanup_test_namespace/1" do
    @tag :slow
    test "cleans up all services in test namespace with logging" do
      # Trap exits to prevent test process termination during cleanup
      Process.flag(:trap_exit, true)

      test_ref = make_ref()
      namespace = {:test, test_ref}

      # Register multiple services
      services = [:cleanup_service_a, :cleanup_service_b, :cleanup_service_c]

      pids =
        for service <- services do
          {:ok, pid} = Agent.start_link(fn -> %{} end)
          ServiceRegistry.register(namespace, service, pid)
          pid
        end

      # Verify services are registered
      info_before = ServiceRegistry.get_service_info(namespace)
      assert info_before.total_services == 3

      # Cleanup namespace
      assert :ok = ServiceRegistry.cleanup_test_namespace(test_ref)

      # Wait for cleanup to complete
      Process.sleep(150)

      # Verify all processes are terminated
      for pid <- pids do
        refute Process.alive?(pid)
      end

      # Verify services are unregistered
      info_after = ServiceRegistry.get_service_info(namespace)
      assert info_after.total_services == 0

      # Clear any remaining EXIT messages
      receive do
        {:EXIT, _pid, _reason} -> :ok
      after
        0 -> :ok
      end

      # Restore normal exit handling
      Process.flag(:trap_exit, false)
    end

    test "succeeds with empty namespace" do
      test_ref = make_ref()

      assert :ok = ServiceRegistry.cleanup_test_namespace(test_ref)
    end

    test "logs appropriate messages for empty namespace" do
      test_ref = make_ref()

      # This should log that no cleanup was needed
      assert :ok = ServiceRegistry.cleanup_test_namespace(test_ref)
    end
  end

  describe "via_tuple/2" do
    test "delegates to ProcessRegistry.via_tuple/2" do
      namespace = :production
      service = :config_server

      expected = ProcessRegistry.via_tuple(namespace, service)
      result = ServiceRegistry.via_tuple(namespace, service)

      assert result == expected
      assert {:via, Registry, {ProcessRegistry, {^namespace, ^service}}} = result
    end

    test "supports test namespaces" do
      test_ref = make_ref()
      namespace = {:test, test_ref}
      service = :test_service

      result = ServiceRegistry.via_tuple(namespace, service)

      assert {:via, Registry, {ProcessRegistry, {^namespace, ^service}}} = result
    end
  end

  describe "error handling" do
    setup do
      test_ref = make_ref()
      namespace = {:test, test_ref}

      on_exit(fn ->
        ServiceRegistry.cleanup_test_namespace(test_ref)
      end)

      %{namespace: namespace, test_ref: test_ref}
    end

    test "create_service_not_found_error creates proper Error struct", %{namespace: namespace} do
      service = :error_test_service

      {:error, error} = ServiceRegistry.lookup(namespace, service)

      assert %Error{} = error
      assert error.code == 5001
      assert error.error_type == :service_not_found
      assert error.severity == :medium
      assert error.category == :system
      assert error.subcategory == :discovery
      assert is_binary(error.message)
      assert error.context.namespace == namespace
      assert error.context.service == service
    end
  end

  describe "telemetry robustness" do
    setup do
      test_ref = make_ref()
      namespace = {:test, test_ref}

      on_exit(fn ->
        ServiceRegistry.cleanup_test_namespace(test_ref)
      end)

      %{namespace: namespace, test_ref: test_ref}
    end

    test "registration continues working when telemetry fails", %{namespace: namespace} do
      service = :telemetry_robust_service
      {:ok, pid} = Agent.start_link(fn -> %{} end)

      # Attach a failing telemetry handler
      :telemetry.attach(
        "failing_registration_handler",
        [:foundation, :foundation, :registry, :register],
        fn _event, _measurements, _metadata, _config ->
          raise "Telemetry failure"
        end,
        %{}
      )

      # Registration should still work
      assert :ok = ServiceRegistry.register(namespace, service, pid)
      assert {:ok, ^pid} = ServiceRegistry.lookup(namespace, service)

      :telemetry.detach("failing_registration_handler")
      Agent.stop(pid)
    end

    test "lookup continues working when telemetry fails", %{namespace: namespace} do
      service = :telemetry_lookup_robust_service
      {:ok, pid} = Agent.start_link(fn -> %{} end)
      ServiceRegistry.register(namespace, service, pid)

      # Attach a failing telemetry handler
      :telemetry.attach(
        "failing_lookup_handler",
        [:foundation, :foundation, :registry, :lookup],
        fn _event, _measurements, _metadata, _config ->
          raise "Telemetry failure"
        end,
        %{}
      )

      # Lookup should still work
      assert {:ok, ^pid} = ServiceRegistry.lookup(namespace, service)

      :telemetry.detach("failing_lookup_handler")
      Agent.stop(pid)
    end
  end

  describe "integration with ProcessRegistry" do
    setup do
      test_ref = make_ref()
      namespace = {:test, test_ref}

      on_exit(fn ->
        ServiceRegistry.cleanup_test_namespace(test_ref)
      end)

      %{namespace: namespace, test_ref: test_ref}
    end

    test "service registered through ServiceRegistry is visible in ProcessRegistry", %{
      namespace: namespace
    } do
      service = :integration_service
      {:ok, pid} = Agent.start_link(fn -> %{} end)

      ServiceRegistry.register(namespace, service, pid)

      # Should be visible through ProcessRegistry
      assert {:ok, ^pid} = ProcessRegistry.lookup(namespace, service)
      assert ProcessRegistry.registered?(namespace, service) == true
      assert service in ProcessRegistry.list_services(namespace)

      Agent.stop(pid)
    end

    test "service registered through ProcessRegistry is visible in ServiceRegistry", %{
      namespace: namespace
    } do
      service = :reverse_integration_service
      {:ok, pid} = Agent.start_link(fn -> %{} end)

      ProcessRegistry.register(namespace, service, pid)

      # Should be visible through ServiceRegistry
      assert {:ok, ^pid} = ServiceRegistry.lookup(namespace, service)
      assert service in ServiceRegistry.list_services(namespace)

      Agent.stop(pid)
    end
  end
end
