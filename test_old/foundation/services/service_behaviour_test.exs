# test/foundation/services/service_behaviour_test.exs
defmodule Foundation.Services.ServiceBehaviourTest do
  use ExUnit.Case, async: false

  # ServiceBehaviour is used via macro, ProcessRegistry via Foundation services

  # Simple test service implementation
  defmodule TestService do
    use Foundation.Services.ServiceBehaviour

    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @impl Foundation.Services.ServiceBehaviour
    def service_config do
      %{
        # Fast for testing
        health_check_interval: 100,
        graceful_shutdown_timeout: 1000,
        dependencies: [],
        telemetry_enabled: true,
        resource_monitoring: true
      }
    end

    @impl Foundation.Services.ServiceBehaviour
    def handle_health_check(state) do
      case Map.get(state, :custom_health_status, :healthy) do
        :healthy -> {:ok, :healthy, state}
        :degraded -> {:ok, :degraded, state}
        :unhealthy -> {:error, :simulated_failure, state}
      end
    end

    # ServiceBehaviour init callback
    def init_service(opts) do
      {:ok,
       %{
         test_data: Keyword.get(opts, :test_data, "default"),
         custom_health_status: Keyword.get(opts, :health_status, :healthy)
       }}
    end

    # Custom handle_call implementations (ServiceBehaviour provides GenServer functionality)
    def handle_call(:get_state, _from, state) do
      {:reply, state, state}
    end

    def handle_call({:set_health, health_status}, _from, state) do
      new_state = Map.put(state, :custom_health_status, health_status)
      {:reply, :ok, new_state}
    end

    def handle_call(:ping, _from, state) do
      {:reply, :pong, state}
    end
  end

  setup do
    # Clean up any existing test services
    cleanup_test_services()

    # Foundation services should already be started by the application
    # No need to start them again

    :ok
  end

  describe "service registration and lifecycle" do
    test "service registers and starts successfully" do
      {:ok, pid} = start_supervised({TestService, [namespace: :test]})

      assert Process.alive?(pid)

      # Should be able to ping the service
      assert :pong = GenServer.call(pid, :ping)
    end

    test "service initializes with custom state" do
      {:ok, pid} = start_supervised({TestService, [test_data: "custom_data", namespace: :test]})

      state = GenServer.call(pid, :get_state)
      assert state.test_data == "custom_data"
      assert state.custom_health_status == :healthy
      # ServiceBehaviour manages this
      assert state.health_status == :starting
    end

    test "service handles graceful shutdown" do
      {:ok, pid} = start_supervised({TestService, [namespace: :test]})

      # Service should be alive initially
      assert Process.alive?(pid)

      # Stop the service gracefully
      GenServer.stop(pid, :normal)

      # Give it a moment to shut down
      Process.sleep(100)

      # Process should be terminated
      refute Process.alive?(pid)
    end
  end

  describe "health checking" do
    test "service performs health checks" do
      {:ok, pid} = start_supervised({TestService, [namespace: :test]})

      # Wait for at least one health check cycle
      Process.sleep(150)

      # Service should still be alive and responsive
      assert Process.alive?(pid)
      assert :pong = GenServer.call(pid, :ping)
    end

    test "service handles different health states" do
      {:ok, pid} = start_supervised({TestService, [health_status: :degraded, namespace: :test]})

      # Wait for health check
      Process.sleep(150)

      # Service should still be alive even if degraded
      assert Process.alive?(pid)

      # Change to unhealthy
      GenServer.call(pid, {:set_health, :unhealthy})

      # Wait for health check
      Process.sleep(150)

      # Service should handle unhealthy state gracefully
      assert Process.alive?(pid)
    end
  end

  describe "service configuration" do
    test "service provides configuration" do
      {:ok, pid} = start_supervised({TestService, [namespace: :test]})

      # Service should be running with expected configuration
      assert Process.alive?(pid)

      # Configuration should be accessible through the service_config callback
      config = TestService.service_config()
      assert config.health_check_interval == 100
      assert config.graceful_shutdown_timeout == 1000
      assert config.dependencies == []
      assert config.telemetry_enabled == true
      assert config.resource_monitoring == true
    end
  end

  describe "error handling" do
    test "service handles errors gracefully" do
      {:ok, pid} = start_supervised({TestService, [namespace: :test]})

      # Service should handle health check errors
      GenServer.call(pid, {:set_health, :unhealthy})

      # Wait for health check cycle
      Process.sleep(150)

      # Service should still be alive despite health check errors
      assert Process.alive?(pid)
    end

    test "service recovers from temporary issues" do
      {:ok, pid} = start_supervised({TestService, [health_status: :unhealthy, namespace: :test]})

      # Wait for unhealthy state
      Process.sleep(150)

      # Restore health
      GenServer.call(pid, {:set_health, :healthy})

      # Wait for recovery
      Process.sleep(150)

      # Service should be responsive again
      assert :pong = GenServer.call(pid, :ping)
    end
  end

  describe "telemetry integration" do
    test "service integrates with telemetry system" do
      # Test that service can start with telemetry enabled
      {:ok, pid} = start_supervised({TestService, [namespace: :test]})

      # Service should be running with telemetry
      assert Process.alive?(pid)

      # Configuration should show telemetry is enabled
      config = TestService.service_config()
      assert config.telemetry_enabled == true
    end
  end

  describe "service behavior compliance" do
    test "service implements required callbacks" do
      # Verify that TestService implements ServiceBehaviour callbacks
      assert function_exported?(TestService, :service_config, 0)
      assert function_exported?(TestService, :handle_health_check, 1)
      assert function_exported?(TestService, :init_service, 1)
    end

    test "service behavior provides expected interface" do
      {:ok, pid} = start_supervised({TestService, [namespace: :test]})

      # Service should respond to standard calls
      assert :pong = GenServer.call(pid, :ping)

      # Service should have accessible state
      state = GenServer.call(pid, :get_state)
      assert is_map(state)
      assert Map.has_key?(state, :test_data)
      # ServiceBehaviour managed
      assert Map.has_key?(state, :health_status)
      # Our custom field
      assert Map.has_key?(state, :custom_health_status)
      assert Map.has_key?(state, :service_name)
      assert Map.has_key?(state, :config)
    end
  end

  # Helper functions

  defp cleanup_test_services do
    services = [TestService]

    Enum.each(services, fn service ->
      case Process.whereis(service) do
        nil ->
          :ok

        pid ->
          Process.exit(pid, :kill)
          Process.sleep(10)
      end
    end)
  end
end
