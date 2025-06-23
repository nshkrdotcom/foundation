# test/foundation/mabeam/performance_test.exs
defmodule Foundation.MABEAM.PerformanceTest do
  @moduledoc """
  Performance benchmarks for MABEAM services.

  Tests ServiceBehaviour integration, memory usage, and responsiveness
  of MABEAM services under various load conditions.
  """

  use ExUnit.Case, async: false

  alias Foundation.MABEAM.{Core, AgentRegistry, Coordination, Telemetry}
  alias Foundation.ProcessRegistry

  describe "MABEAM service performance" do
    @tag :performance
    test "services start within acceptable time limits" do
      # Test that MABEAM services start quickly
      start_time = System.monotonic_time(:millisecond)

      # Verify all services are running
      services = [
        {Foundation.MABEAM.Core, "MABEAM Core"},
        {Foundation.MABEAM.AgentRegistry, "MABEAM Agent Registry"},
        {Foundation.MABEAM.Coordination, "MABEAM Coordination"},
        {Foundation.MABEAM.Telemetry, "MABEAM Telemetry"}
      ]

      for {service_name, description} <- services do
        case ProcessRegistry.lookup(:production, service_name) do
          {:ok, pid} ->
            assert Process.alive?(pid), "#{description} should be running"

          :error ->
            flunk("#{description} not found in ProcessRegistry")
        end
      end

      end_time = System.monotonic_time(:millisecond)
      startup_time = end_time - start_time

      # Services should start and be discoverable within 100ms
      assert startup_time < 100, "Service discovery took too long: #{startup_time}ms"
    end

    test "services respond to health checks efficiently" do
      services = [
        {Core, Foundation.MABEAM.Core, "MABEAM Core"},
        {AgentRegistry, Foundation.MABEAM.AgentRegistry, "MABEAM Agent Registry"},
        {Coordination, Foundation.MABEAM.Coordination, "MABEAM Coordination"},
        {Telemetry, Foundation.MABEAM.Telemetry, "MABEAM Telemetry"}
      ]

      for {module, service_name, description} <- services do
        # Test that service_config is fast
        config_start = System.monotonic_time(:microsecond)
        config = module.service_config()
        config_end = System.monotonic_time(:microsecond)
        config_time = config_end - config_start

        assert is_map(config), "#{description} should return valid config"
        assert config_time < 1000, "#{description} service_config too slow: #{config_time}μs"

        # Test health check if service supports it
        case ProcessRegistry.lookup(:production, service_name) do
          {:ok, pid} ->
            # Test basic responsiveness
            health_start = System.monotonic_time(:microsecond)

            try do
              response = GenServer.call(pid, :health_status, 1000)
              health_end = System.monotonic_time(:microsecond)
              health_time = health_end - health_start

              # Health check should complete within 10ms
              assert health_time < 10_000, "#{description} health check too slow: #{health_time}μs"

              case response do
                {:ok, status} ->
                  assert status in [:starting, :healthy, :degraded, :unhealthy],
                         "#{description} should return valid health status"

                {:error, _reason} ->
                  # Error responses are acceptable for degraded services
                  :ok
              end
            catch
              :exit, {:timeout, _} ->
                flunk("#{description} health check timed out")

              :exit, {reason, _} when is_tuple(reason) and elem(reason, 0) == :function_clause ->
                # Service doesn't implement health_status - that's ok
                :ok
            end

          :error ->
            flunk("#{description} not found in ProcessRegistry")
        end
      end
    end

    test "services handle concurrent requests efficiently" do
      # Test Core service with multiple variable registrations
      case ProcessRegistry.lookup(:production, Foundation.MABEAM.Core) do
        {:ok, core_pid} ->
          # Concurrent health checks
          tasks =
            for _i <- 1..10 do
              Task.async(fn ->
                start_time = System.monotonic_time(:microsecond)

                try do
                  GenServer.call(core_pid, :health_status, 1000)
                  end_time = System.monotonic_time(:microsecond)
                  end_time - start_time
                catch
                  :exit, {reason, _}
                  when is_tuple(reason) and elem(reason, 0) == :function_clause ->
                    # Service doesn't implement health_status - use ping time
                    end_time = System.monotonic_time(:microsecond)
                    end_time - start_time
                end
              end)
            end

          response_times = Task.await_many(tasks, 5000)

          # All requests should complete
          assert length(response_times) == 10, "All concurrent requests should complete"

          # Average response time should be reasonable
          avg_time = Enum.sum(response_times) / length(response_times)
          assert avg_time < 5_000, "Average response time too high: #{avg_time}μs"

        :error ->
          flunk("MABEAM Core not found for concurrency test")
      end
    end

    test "services maintain reasonable memory usage" do
      services = [
        {Foundation.MABEAM.Core, "MABEAM Core"},
        {Foundation.MABEAM.AgentRegistry, "MABEAM Agent Registry"},
        {Foundation.MABEAM.Coordination, "MABEAM Coordination"},
        {Foundation.MABEAM.Telemetry, "MABEAM Telemetry"}
      ]

      total_memory =
        Enum.reduce(services, 0, fn {service_name, description}, acc ->
          case ProcessRegistry.lookup(:production, service_name) do
            {:ok, pid} ->
              case Process.info(pid, :memory) do
                {:memory, memory} ->
                  # Each service should use less than 10MB
                  memory_mb = memory / (1024 * 1024)
                  assert memory_mb < 10, "#{description} using too much memory: #{memory_mb}MB"
                  acc + memory

                nil ->
                  flunk("#{description} process not found for memory check")
              end

            :error ->
              flunk("#{description} not found in ProcessRegistry")
          end
        end)

      # Total MABEAM memory usage should be reasonable
      total_mb = total_memory / (1024 * 1024)
      assert total_mb < 40, "Total MABEAM memory usage too high: #{total_mb}MB"
    end

    test "ServiceBehaviour integration provides performance benefits" do
      # Test that ServiceBehaviour features work
      services_with_behaviour = [
        {AgentRegistry, Foundation.MABEAM.AgentRegistry, "MABEAM Agent Registry"},
        {Coordination, Foundation.MABEAM.Coordination, "MABEAM Coordination"},
        {Telemetry, Foundation.MABEAM.Telemetry, "MABEAM Telemetry"}
      ]

      for {module, service_name, description} <- services_with_behaviour do
        # Test service_config is defined and fast
        assert function_exported?(module, :service_config, 0),
               "#{description} should implement service_config/0"

        config = module.service_config()
        assert is_map(config), "#{description} should return valid config map"

        assert Map.has_key?(config, :health_check_interval),
               "#{description} should specify health_check_interval"

        assert Map.has_key?(config, :telemetry_enabled),
               "#{description} should specify telemetry_enabled"

        # Test handle_health_check is defined
        assert function_exported?(module, :handle_health_check, 1),
               "#{description} should implement handle_health_check/1"

        # Verify service is registered
        case ProcessRegistry.lookup(:production, service_name) do
          {:ok, _pid} -> :ok
          :error -> flunk("#{description} should be registered in ProcessRegistry")
        end
      end
    end

    test "services support production-ready configuration" do
      services = [
        {Core, "MABEAM Core"},
        {AgentRegistry, "MABEAM Agent Registry"},
        {Coordination, "MABEAM Coordination"},
        {Telemetry, "MABEAM Telemetry"}
      ]

      for {module, description} <- services do
        config = module.service_config()

        # Health check intervals should be production-ready
        if Map.has_key?(config, :health_check_interval) do
          interval = config.health_check_interval

          assert interval >= 5_000 and interval <= 300_000,
                 "#{description} health check interval should be 5s-5min, got #{interval}ms"
        end

        # Graceful shutdown timeouts should be reasonable
        if Map.has_key?(config, :graceful_shutdown_timeout) do
          timeout = config.graceful_shutdown_timeout

          assert timeout >= 1_000 and timeout <= 30_000,
                 "#{description} shutdown timeout should be 1s-30s, got #{timeout}ms"
        end

        # Telemetry should be enabled by default
        if Map.has_key?(config, :telemetry_enabled) do
          assert config.telemetry_enabled == true,
                 "#{description} should have telemetry enabled for production"
        end
      end
    end
  end
end
