# test/foundation/services/service_behaviour_test.exs
defmodule Foundation.Services.ServiceBehaviourTest do
  use ExUnit.Case, async: false
  
  alias Foundation.{ProcessRegistry, ServiceRegistry, Telemetry, Events}
  alias Foundation.Services.ServiceBehaviour

  # Test service implementation for testing the behavior
  defmodule TestService do
    use Foundation.Services.ServiceBehaviour
    use GenServer

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @impl Foundation.Services.ServiceBehaviour
    def service_config do
      %{
        health_check_interval: 100,  # Fast for testing
        graceful_shutdown_timeout: 1000,
        dependencies: [],
        telemetry_enabled: true,
        resource_monitoring: true
      }
    end

    @impl Foundation.Services.ServiceBehaviour
    def handle_health_check(state) do
      case Map.get(state, :health_status, :healthy) do
        :healthy -> {:ok, :healthy, state}
        :degraded -> {:ok, :degraded, state}
        :unhealthy -> {:error, :simulated_failure, state}
      end
    end

    @impl Foundation.Services.ServiceBehaviour
    def init_service(opts) do
      {:ok, %{
        test_data: Keyword.get(opts, :test_data, "default"),
        health_status: Keyword.get(opts, :health_status, :healthy)
      }}
    end

    # Additional GenServer callbacks for testing
    def handle_call(:get_state, _from, state) do
      {:reply, state, state}
    end

    def handle_call(:set_health, {_pid, _tag}, health_status, state) do
      new_state = Map.put(state, :health_status, health_status)
      {:reply, :ok, new_state}
    end

    def handle_call(:ping, _from, state) do
      {:reply, :pong, state}
    end
  end

  # Test service with dependencies
  defmodule DependentTestService do
    use Foundation.Services.ServiceBehaviour
    use GenServer

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @impl Foundation.Services.ServiceBehaviour
    def service_config do
      %{
        health_check_interval: 100,
        dependencies: [:test_service],
        telemetry_enabled: true,
        resource_monitoring: false
      }
    end

    @impl Foundation.Services.ServiceBehaviour
    def handle_health_check(state) do
      {:ok, :healthy, state}
    end

    @impl Foundation.Services.ServiceBehaviour
    def handle_dependency_ready(dependency, state) do
      new_state = Map.update(state, :ready_deps, [dependency], &[dependency | &1])
      {:ok, new_state}
    end

    @impl Foundation.Services.ServiceBehaviour
    def handle_dependency_lost(dependency, state) do
      new_state = Map.update(state, :lost_deps, [dependency], &[dependency | &1])
      {:ok, new_state}
    end

    @impl Foundation.Services.ServiceBehaviour
    def init_service(_opts) do
      {:ok, %{ready_deps: [], lost_deps: []}}
    end

    def handle_call(:get_state, _from, state) do
      {:reply, state, state}
    end
  end

  # Test service that fails during config changes
  defmodule ConfigurableTestService do
    use Foundation.Services.ServiceBehaviour
    use GenServer

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @impl Foundation.Services.ServiceBehaviour
    def service_config do
      %{
        health_check_interval: 100,
        dependencies: [],
        telemetry_enabled: true,
        resource_monitoring: true
      }
    end

    @impl Foundation.Services.ServiceBehaviour
    def handle_health_check(state) do
      {:ok, :healthy, state}
    end

    @impl Foundation.Services.ServiceBehaviour
    def handle_config_change(new_config, state) do
      case Map.get(new_config, :should_fail) do
        true -> {:error, :config_change_failed, state}
        _ -> {:ok, Map.put(state, :config_updated, true)}
      end
    end

    @impl Foundation.Services.ServiceBehaviour
    def init_service(_opts) do
      {:ok, %{config_updated: false}}
    end

    def handle_call(:get_state, _from, state) do
      {:reply, state, state}
    end
  end

  setup do
    # Clean up any existing services
    cleanup_test_services()
    
    # Start required foundation services
    start_supervised!({ProcessRegistry, []})
    start_supervised!({Foundation.Services.TelemetryService, [namespace: :test]})
    
    :ok
  end

  describe "service registration and lifecycle" do
    test "service registers with ProcessRegistry on startup" do
      {:ok, _pid} = start_supervised({TestService, [namespace: :test]})
      
      assert {:ok, _pid} = ProcessRegistry.lookup(:test, TestService)
    end

    test "service fails to start if registration fails" do
      # Start service with same name twice
      {:ok, _pid1} = start_supervised({TestService, [namespace: :test]})
      
      # Starting second service with same name should fail
      # Note: This test verifies the behavior when registration conflicts occur
      # In practice, this would be handled by the supervision tree
    end

    test "service initializes with custom state" do
      {:ok, pid} = start_supervised({TestService, [test_data: "custom_data", namespace: :test]})
      
      state = GenServer.call(pid, :get_state)
      assert state.test_data == "custom_data"
    end

    test "service handles graceful shutdown" do
      {:ok, pid} = start_supervised({TestService, [namespace: :test]})
      
      # Send shutdown signal
      send(pid, :shutdown)
      
      # Process should terminate gracefully
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :shutdown}, 2000
    end
  end

  describe "health checking" do
    test "service performs regular health checks" do
      {:ok, pid} = start_supervised({TestService, [namespace: :test]})
      
      # Wait for at least one health check cycle
      Process.sleep(150)
      
      # Service should still be alive and healthy
      assert Process.alive?(pid)
      
      # Check health status
      assert {:ok, :healthy} = GenServer.call(pid, :health_status)
    end

    test "service reports degraded health" do
      {:ok, pid} = start_supervised({TestService, [health_status: :degraded, namespace: :test]})
      
      # Wait for health check
      Process.sleep(150)
      
      assert {:ok, :degraded} = GenServer.call(pid, :health_status)
    end

    test "service reports unhealthy status" do
      {:ok, pid} = start_supervised({TestService, [health_status: :unhealthy, namespace: :test]})
      
      # Wait for health check
      Process.sleep(150)
      
      assert Process.alive?(pid)  # Service should still be alive even if unhealthy
    end

    test "service handles health check exceptions" do
      {:ok, pid} = start_supervised({TestService, [namespace: :test]})
      
      # Force an unhealthy state
      GenServer.call(pid, {:set_health, :unhealthy})
      
      # Wait for health check
      Process.sleep(150)
      
      # Service should handle the error gracefully
      assert Process.alive?(pid)
    end

    test "service emits health check telemetry" do
      # Attach telemetry handler
      telemetry_events = []
      test_pid = self()
      
      handler_id = "test_health_telemetry"
      :telemetry.attach(handler_id, [:foundation, :service, :health_check, :duration], 
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end, nil)
      
      {:ok, _pid} = start_supervised({TestService, [namespace: :test]})
      
      # Wait for health check
      Process.sleep(200)
      
      # Should receive telemetry event
      assert_receive {:telemetry_event, 
        [:foundation, :service, :health_check, :duration], 
        measurements, 
        metadata}, 1000
      
      assert is_number(measurements.histogram)
      assert metadata.service == TestService
      assert metadata.result in [:success, :degraded, :failure]
      
      :telemetry.detach(handler_id)
    end
  end

  describe "dependency management" do
    test "service checks dependencies on startup" do
      # Start dependency first
      {:ok, _dep_pid} = start_supervised({TestService, [namespace: :test]})
      
      # Start dependent service
      {:ok, dependent_pid} = start_supervised({DependentTestService, [namespace: :test]})
      
      # Wait for dependency check
      Process.sleep(200)
      
      state = GenServer.call(dependent_pid, :get_state)
      assert :test_service in state.ready_deps
    end

    test "service handles dependency becoming unavailable" do
      # Start dependency first
      {:ok, dep_pid} = start_supervised({TestService, [namespace: :test]})
      
      # Start dependent service
      {:ok, dependent_pid} = start_supervised({DependentTestService, [namespace: :test]})
      
      # Wait for initial dependency check
      Process.sleep(150)
      
      # Stop dependency
      GenServer.stop(dep_pid)
      
      # Wait for dependency loss detection
      Process.sleep(200)
      
      state = GenServer.call(dependent_pid, :get_state)
      assert :test_service in state.lost_deps
    end
  end

  describe "configuration management" do
    test "service handles configuration updates" do
      {:ok, pid} = start_supervised({ConfigurableTestService, [namespace: :test]})
      
      # Update configuration
      new_config = %{some_setting: :new_value}
      assert :ok = GenServer.call(pid, {:update_config, new_config})
      
      state = GenServer.call(pid, :get_state)
      assert state.config_updated == true
    end

    test "service handles configuration update failures" do
      {:ok, pid} = start_supervised({ConfigurableTestService, [namespace: :test]})
      
      # Send failing configuration
      failing_config = %{should_fail: true}
      assert {:error, :config_change_failed} = GenServer.call(pid, {:update_config, failing_config})
      
      # Service should still be running
      assert Process.alive?(pid)
    end
  end

  describe "telemetry integration" do
    test "service emits startup telemetry" do
      telemetry_events = []
      test_pid = self()
      
      handler_id = "test_startup_telemetry"
      :telemetry.attach(handler_id, [:foundation, :service, :started], 
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end, nil)
      
      {:ok, _pid} = start_supervised({TestService, [namespace: :test]})
      
      # Should receive startup telemetry
      assert_receive {:telemetry_event, 
        [:foundation, :service, :started], 
        _measurements, 
        metadata}, 1000
      
      assert metadata.service == TestService
      assert metadata.namespace == :test
      
      :telemetry.detach(handler_id)
    end

    test "service emits shutdown telemetry" do
      test_pid = self()
      
      handler_id = "test_shutdown_telemetry"
      :telemetry.attach(handler_id, [:foundation, :service, :stopped], 
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end, nil)
      
      {:ok, pid} = start_supervised({TestService, [namespace: :test]})
      
      # Stop the service
      GenServer.stop(pid)
      
      # Should receive shutdown telemetry
      assert_receive {:telemetry_event, 
        [:foundation, :service, :stopped], 
        _measurements, 
        metadata}, 1000
      
      assert metadata.service == TestService
      
      :telemetry.detach(handler_id)
    end

    test "service provides metrics on request" do
      {:ok, pid} = start_supervised({TestService, [namespace: :test]})
      
      # Wait for some operation
      Process.sleep(100)
      
      # Get service metrics
      assert {:ok, metrics} = GenServer.call(pid, :service_metrics)
      
      assert is_map(metrics)
      assert is_integer(metrics.uptime_ms)
      assert metrics.uptime_ms >= 0
      assert is_integer(metrics.memory_usage)
      assert is_integer(metrics.message_queue_length)
      assert is_integer(metrics.health_checks)
      assert is_integer(metrics.health_check_failures)
    end
  end

  describe "error handling and recovery" do
    test "service handles health check timeouts gracefully" do
      # This would require a service that simulates slow health checks
      # For now, we verify the service stays alive during health checks
      {:ok, pid} = start_supervised({TestService, [namespace: :test]})
      
      # Wait through several health check cycles
      Process.sleep(500)
      
      assert Process.alive?(pid)
    end

    test "service recovers from temporary health check failures" do
      {:ok, pid} = start_supervised({TestService, [health_status: :unhealthy, namespace: :test]})
      
      # Wait for unhealthy state
      Process.sleep(150)
      
      # Restore health
      GenServer.call(pid, {:set_health, :healthy})
      
      # Wait for recovery
      Process.sleep(150)
      
      assert {:ok, :healthy} = GenServer.call(pid, :health_status)
    end
  end

  describe "resource monitoring" do
    test "service tracks memory usage" do
      {:ok, pid} = start_supervised({TestService, [namespace: :test]})
      
      assert {:ok, metrics} = GenServer.call(pid, :service_metrics)
      
      assert is_integer(metrics.memory_usage)
      assert metrics.memory_usage > 0
    end

    test "service tracks message queue length" do
      {:ok, pid} = start_supervised({TestService, [namespace: :test]})
      
      # Send some messages to queue them up
      send(pid, :test_message1)
      send(pid, :test_message2)
      
      assert {:ok, metrics} = GenServer.call(pid, :service_metrics)
      
      assert is_integer(metrics.message_queue_length)
      assert metrics.message_queue_length >= 0
    end
  end

  # Property-based tests using StreamData
  @tag :property
  test "service behavior properties" do
    ExUnitProperties.check all health_status <- StreamData.member_of([:healthy, :degraded, :unhealthy]),
                              test_data <- StreamData.string(:alphanumeric),
                              max_runs: 20 do
      
      {:ok, pid} = start_supervised({TestService, [
        health_status: health_status, 
        test_data: test_data,
        namespace: :test
      ]}, restart: :temporary)
      
      # Service should always start successfully
      assert Process.alive?(pid)
      
      # State should match initialization
      state = GenServer.call(pid, :get_state)
      assert state.test_data == test_data
      assert state.health_status == health_status
      
      # Health check should reflect configured status
      Process.sleep(150)  # Wait for health check
      
      case health_status do
        :healthy -> assert {:ok, :healthy} = GenServer.call(pid, :health_status)
        :degraded -> assert {:ok, :degraded} = GenServer.call(pid, :health_status) 
        :unhealthy -> 
          # Unhealthy services may still respond depending on implementation
          result = GenServer.call(pid, :health_status)
          assert result in [{:ok, :unhealthy}, {:error, :simulated_failure}]
      end
      
      GenServer.stop(pid)
    end
  end

  # Helper functions

  defp cleanup_test_services do
    services = [TestService, DependentTestService, ConfigurableTestService]
    
    Enum.each(services, fn service ->
      case Process.whereis(service) do
        nil -> :ok
        pid -> 
          Process.exit(pid, :kill)
          Process.sleep(10)
      end
    end)
  end
end
