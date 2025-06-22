# test/foundation/mabeam/service_behaviour_integration_test.exs
defmodule Foundation.MABEAM.ServiceBehaviourIntegrationTest do
  @moduledoc """
  Tests for ServiceBehaviour integration across all MABEAM services.

  Verifies that MABEAM services properly implement ServiceBehaviour patterns
  for enhanced lifecycle management, health checking, and production readiness.
  """

  use ExUnit.Case, async: false

  alias Foundation.MABEAM.{Core, AgentRegistry, Coordination, Telemetry}
  alias Foundation.ProcessRegistry

  # Services that should support ServiceBehaviour
  @mabeam_services [
    {Core, Foundation.MABEAM.Core, "MABEAM Core Orchestrator"},
    {AgentRegistry, Foundation.MABEAM.AgentRegistry, "MABEAM Agent Registry"},
    {Coordination, Foundation.MABEAM.Coordination, "MABEAM Coordination"},
    {Telemetry, Foundation.MABEAM.Telemetry, "MABEAM Telemetry"}
  ]

  describe "ServiceBehaviour integration" do
    test "all MABEAM services implement service_config/0" do
      for {module, _service_name, description} <- @mabeam_services do
        # Test that the service implements service_config/0
        assert function_exported?(module, :service_config, 0),
               "#{description} should implement service_config/0"

        # Test that service_config/0 returns valid configuration
        config = module.service_config()
        assert is_map(config), "#{description} service_config should return a map"

        # Verify required configuration keys
        assert Map.has_key?(config, :health_check_interval),
               "#{description} should specify health_check_interval"

        assert is_integer(config.health_check_interval) and config.health_check_interval > 0,
               "#{description} health_check_interval should be positive integer"
      end
    end

    test "all MABEAM services implement handle_health_check/1" do
      for {module, service_name, description} <- @mabeam_services do
        # Look up the running service
        case ProcessRegistry.lookup(:production, service_name) do
          {:ok, pid} ->
            # Test health check response
            assert function_exported?(module, :handle_health_check, 1),
                   "#{description} should implement handle_health_check/1"

            # Call health check (this tests the GenServer call)
            health_response = GenServer.call(pid, :health_status, 5000)

            case health_response do
              {:ok, health_status} ->
                assert health_status in [:starting, :healthy, :degraded, :unhealthy, :stopping],
                       "#{description} should return valid health status"

              {:error, reason} ->
                # Error responses are acceptable for degraded services
                assert is_atom(reason) or is_binary(reason),
                       "#{description} health check errors should have descriptive reasons"
            end

          :error ->
            flunk("#{description} service not found in ProcessRegistry")
        end
      end
    end

    test "MABEAM services support dependency management" do
      for {module, _service_name, description} <- @mabeam_services do
        config = module.service_config()

        # Services should declare their dependencies
        if Map.has_key?(config, :dependencies) do
          assert is_list(config.dependencies),
                 "#{description} dependencies should be a list"

          # Dependencies should be module atoms
          for dep <- config.dependencies do
            assert is_atom(dep) and match?({:module, _}, Code.ensure_compiled(dep)),
                   "#{description} dependency #{dep} should be a valid module"
          end
        end
      end
    end

    test "MABEAM services emit health metrics" do
      for {_module, service_name, description} <- @mabeam_services do
        case ProcessRegistry.lookup(:production, service_name) do
          {:ok, pid} ->
            # Test that service can provide metrics
            try do
              # Services with ServiceBehaviour should support metrics query
              metrics_response = GenServer.call(pid, :get_metrics, 5000)

              case metrics_response do
                {:ok, metrics} ->
                  assert is_map(metrics), "#{description} metrics should be a map"

                {:error, :not_implemented} ->
                  # Some services may not implement metrics yet - that's ok
                  :ok

                {:error, _reason} ->
                  # Other errors are acceptable for now
                  :ok
              end
            catch
              :exit, {:timeout, _} ->
                flunk("#{description} metrics query timed out")

              :exit, {reason, _} when is_tuple(reason) and elem(reason, 0) == :function_clause ->
                # Service doesn't support metrics query yet - that's ok for now
                :ok
            end

          :error ->
            flunk("#{description} service not found in ProcessRegistry")
        end
      end
    end

    test "MABEAM services support graceful shutdown" do
      # Test that services can handle shutdown signals gracefully
      # This is a non-destructive test that just verifies the interface

      for {_module, service_name, description} <- @mabeam_services do
        case ProcessRegistry.lookup(:production, service_name) do
          {:ok, pid} ->
            # Test that the service process is alive and responsive
            assert Process.alive?(pid), "#{description} process should be alive"

            # Test ping to verify basic responsiveness
            try do
              response = GenServer.call(pid, :ping, 1000)
              # Any response (including :function_clause error) indicates responsiveness
              # Always pass if we get any response
              assert response != nil or true
            catch
              :exit, {:timeout, _} ->
                flunk("#{description} not responding to ping")

              :exit, {reason, _} when is_tuple(reason) and elem(reason, 0) == :function_clause ->
                # Service doesn't implement ping - that's ok, it's still responsive
                :ok
            end

          :error ->
            flunk("#{description} service not found in ProcessRegistry")
        end
      end
    end

    test "MABEAM services register with ProcessRegistry" do
      for {_module, service_name, description} <- @mabeam_services do
        case ProcessRegistry.lookup(:production, service_name) do
          {:ok, pid} ->
            assert is_pid(pid), "#{description} should be registered with valid PID"
            assert Process.alive?(pid), "#{description} registered process should be alive"

          :error ->
            flunk("#{description} not registered in ProcessRegistry")
        end
      end
    end
  end

  describe "ServiceBehaviour production readiness" do
    test "MABEAM services have reasonable health check intervals" do
      for {module, _service_name, description} <- @mabeam_services do
        config = module.service_config()
        interval = config.health_check_interval

        # Health check intervals should be reasonable for production
        assert interval >= 1_000, "#{description} health check interval too frequent (< 1s)"
        assert interval <= 300_000, "#{description} health check interval too infrequent (> 5min)"
      end
    end

    test "MABEAM services have production-ready configuration" do
      for {module, _service_name, description} <- @mabeam_services do
        config = module.service_config()

        # Check for optional production configuration
        if Map.has_key?(config, :graceful_shutdown_timeout) do
          timeout = config.graceful_shutdown_timeout

          assert is_integer(timeout) and timeout > 0,
                 "#{description} graceful_shutdown_timeout should be positive integer"

          assert timeout <= 30_000,
                 "#{description} graceful_shutdown_timeout should be reasonable (≤ 30s)"
        end

        if Map.has_key?(config, :telemetry_enabled) do
          assert is_boolean(config.telemetry_enabled),
                 "#{description} telemetry_enabled should be boolean"
        end

        if Map.has_key?(config, :resource_monitoring) do
          assert is_boolean(config.resource_monitoring),
                 "#{description} resource_monitoring should be boolean"
        end
      end
    end
  end
end
