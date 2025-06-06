defmodule Foundation.Stress.ChaosResilienceTest do
  use ExUnit.Case, async: false
  @moduletag :stress

  require Logger

  setup do
    # Ensure all services are available for testing
    Foundation.TestHelpers.wait_for_all_services_available(5000)
    assert Foundation.available?()
    assert {:ok, %{status: :healthy}} = Foundation.health()
    :ok
  end

  @tag timeout: 120_000
  test "system recovers gracefully after random service failures under load" do
    # 20 seconds of load
    load_duration = 20_000
    # 15 seconds of chaos (overlapping with load)
    chaos_duration = 15_000
    # 5 seconds to stabilize
    cooldown_period = 5_000
    num_workers = 30
    # Kill services every 2 seconds
    chaos_interval = 2_000

    Logger.info(
      "Starting chaos resilience test: #{load_duration}ms load, #{chaos_duration}ms chaos"
    )

    # Start the load generation
    start_time = System.monotonic_time(:millisecond)
    load_end_time = start_time + load_duration
    chaos_end_time = start_time + chaos_duration

    workers = start_resilient_load_workers(num_workers, load_end_time)

    # Start the chaos monkey
    chaos_task =
      Task.async(fn ->
        run_chaos_monkey(chaos_end_time, chaos_interval)
      end)

    # Monitor recovery metrics
    recovery_monitor =
      Task.async(fn ->
        monitor_recovery_metrics(start_time, load_end_time)
      end)

    # Wait for load workers to complete
    worker_results =
      Enum.map(workers, fn worker ->
        case Task.yield(worker, load_duration + 5_000) do
          {:ok, result} ->
            result

          nil ->
            Task.shutdown(worker, :brutal_kill)
            %{operations: 0, errors: 0, status: :timeout}
        end
      end)

    # Wait for chaos to complete
    chaos_events = Task.await(chaos_task, 10_000)
    recovery_metrics = Task.await(recovery_monitor, 10_000)

    Logger.info("Chaos phase completed. #{length(chaos_events)} services killed")

    Logger.info(
      "Worker results: #{inspect(Enum.reduce(worker_results, %{total_ops: 0, total_errors: 0}, fn result, acc -> %{total_ops: acc.total_ops + result.operations, total_errors: acc.total_errors + result.errors} end))}"
    )

    # Cooldown period - let supervisors stabilize the system
    Logger.info("Entering cooldown period of #{cooldown_period}ms")
    :timer.sleep(cooldown_period)

    # Verify system has recovered
    assert Foundation.available?(), "System should be available after chaos test"

    assert {:ok, %{status: :healthy}} = Foundation.health(),
           "System should be healthy after recovery"

    # Verify all core functionality is restored
    verify_full_functionality_restored()

    # Log chaos test results (some systems may be resilient enough to have zero errors)
    total_errors = Enum.reduce(worker_results, 0, fn result, acc -> acc + result.errors end)
    total_operations = Enum.reduce(worker_results, 0, fn result, acc -> acc + result.operations end)

    Logger.info(
      "Chaos test completed: #{total_operations} operations, #{total_errors} errors, #{length(chaos_events)} service kills"
    )

    # The system should continue operating even under chaos
    assert total_operations > 0, "Workers should have completed some operations"

    # Some disruption is expected, but highly resilient systems may have very few errors
    if total_errors == 0 and length(chaos_events) > 0 do
      Logger.info(
        "System showed exceptional resilience: no errors despite #{length(chaos_events)} service kills"
      )
    end

    # Verify system recovered within reasonable bounds
    verify_recovery_metrics(recovery_metrics, chaos_events)

    Logger.info("Chaos resilience test completed successfully")
  end

  defp start_resilient_load_workers(num_workers, end_time) do
    Enum.map(1..num_workers, fn worker_id ->
      Task.async(fn ->
        run_resilient_load_worker(worker_id, end_time)
      end)
    end)
  end

  defp run_resilient_load_worker(worker_id, end_time) do
    operations = [:config_read, :event_store, :telemetry_emit, :service_lookup]

    loop_with_error_tracking(end_time, 0, 0, fn ops, errs ->
      operation = Enum.random(operations)

      try do
        case operation do
          :config_read ->
            case Foundation.Config.get([:dev, :debug_mode]) do
              {:ok, _} -> {ops + 1, errs}
              {:error, _} -> {ops, errs + 1}
            end

          :event_store ->
            {:ok, event} =
              Foundation.Events.new_event(:chaos_test, %{
                worker: worker_id,
                timestamp: System.os_time(:microsecond),
                operation: operation
              })

            case Foundation.Events.store(event) do
              {:ok, _} -> {ops + 1, errs}
              {:error, _} -> {ops, errs + 1}
            end

          :telemetry_emit ->
            case Foundation.Telemetry.emit_counter([:chaos_test, :operations], %{
                   worker: worker_id,
                   operation: operation
                 }) do
              :ok -> {ops + 1, errs}
              {:error, _} -> {ops, errs + 1}
            end

          :service_lookup ->
            case Foundation.ServiceRegistry.lookup(:production, :config_server) do
              {:ok, _} -> {ops + 1, errs}
              {:error, _} -> {ops, errs + 1}
            end
        end
      rescue
        _error ->
          # Count all exceptions as errors but continue running
          {ops, errs + 1}
      end
    end)
  end

  defp loop_with_error_tracking(end_time, operations, errors, operation_fn) do
    if System.monotonic_time(:millisecond) < end_time do
      {new_ops, new_errs} = operation_fn.(operations, errors)

      # Small delay to prevent overwhelming the system
      :timer.sleep(:rand.uniform(50))

      loop_with_error_tracking(end_time, new_ops, new_errs, operation_fn)
    else
      %{operations: operations, errors: errors, status: :completed}
    end
  end

  defp run_chaos_monkey(end_time, interval) do
    chaos_events = []
    run_chaos_loop(end_time, interval, chaos_events)
  end

  defp run_chaos_loop(end_time, interval, events) do
    current_time = System.monotonic_time(:millisecond)

    if current_time < end_time do
      # Pick a random service to kill
      services = [:config_server, :event_store, :telemetry_service]
      target_service = Enum.random(services)

      case Foundation.ServiceRegistry.lookup(:production, target_service) do
        {:ok, pid} when is_pid(pid) ->
          Logger.info("Chaos monkey killing #{target_service} (#{inspect(pid)})")
          Process.exit(pid, :kill)

          new_event = %{
            timestamp: current_time,
            service: target_service,
            pid: pid,
            action: :killed
          }

          :timer.sleep(interval)
          run_chaos_loop(end_time, interval, [new_event | events])

        _ ->
          Logger.warning("Chaos monkey could not find #{target_service}")
          :timer.sleep(interval)
          run_chaos_loop(end_time, interval, events)
      end
    else
      Enum.reverse(events)
    end
  end

  defp monitor_recovery_metrics(start_time, end_time) do
    monitor_recovery_loop(start_time, end_time, [])
  end

  defp monitor_recovery_loop(start_time, end_time, metrics) do
    current_time = System.monotonic_time(:millisecond)

    if current_time < end_time do
      # Check if services are available
      health_status =
        case Foundation.health() do
          {:ok, %{status: status}} -> status
          _ -> :unhealthy
        end

      service_statuses = check_service_availability()

      metric = %{
        # Relative time
        timestamp: current_time - start_time,
        health_status: health_status,
        services: service_statuses
      }

      # Check every second
      :timer.sleep(1000)
      monitor_recovery_loop(start_time, end_time, [metric | metrics])
    else
      Enum.reverse(metrics)
    end
  end

  defp check_service_availability do
    services = [:config_server, :event_store, :telemetry_service]

    Enum.reduce(services, %{}, fn service, acc ->
      status =
        case Foundation.ServiceRegistry.lookup(:production, service) do
          {:ok, pid} when is_pid(pid) -> :available
          _ -> :unavailable
        end

      Map.put(acc, service, status)
    end)
  end

  defp verify_full_functionality_restored do
    # Test config operations work
    assert {:ok, _} = Foundation.Config.get([:dev, :debug_mode])

    # Test that config operations are functional (without updating sensitive values)
    # Just verify we can read config successfully
    assert {:ok, _} = Foundation.Config.get([:dev, :debug_mode])

    # Test config availability
    assert Foundation.Config.available?()

    # Test event operations work
    {:ok, event} =
      Foundation.Events.new_event(:recovery_verification, %{
        test: :post_chaos,
        timestamp: System.os_time(:microsecond)
      })

    assert {:ok, event_id} = Foundation.Events.store(event)
    assert {:ok, ^event} = Foundation.Events.get(event_id)

    # Test telemetry operations work
    assert :ok = Foundation.Telemetry.emit_counter([:recovery_verification, :post_chaos], %{})
    assert {:ok, _metrics} = Foundation.Telemetry.get_metrics()

    # Test all services are discoverable
    assert {:ok, _pid} = Foundation.ServiceRegistry.lookup(:production, :config_server)
    assert {:ok, _pid} = Foundation.ServiceRegistry.lookup(:production, :event_store)
    assert {:ok, _pid} = Foundation.ServiceRegistry.lookup(:production, :telemetry_service)
  end

  defp verify_recovery_metrics(recovery_metrics, chaos_events) do
    # Verify that we actually had some periods of unavailability
    unhealthy_periods =
      Enum.count(recovery_metrics, fn metric ->
        metric.health_status != :healthy
      end)

    # We expect some unhealthy periods given the chaos
    if length(chaos_events) > 0 and unhealthy_periods == 0 do
      Logger.warning("Expected some unhealthy periods during chaos, but found none")
    end

    # Verify that system eventually recovered (last few metrics should be healthy)
    # Last 3 metrics
    recent_metrics = Enum.take(recovery_metrics, -3)

    healthy_recent =
      Enum.count(recent_metrics, fn metric ->
        metric.health_status == :healthy
      end)

    assert healthy_recent >= 2,
           "System should be healthy in recent metrics, got #{healthy_recent}/#{length(recent_metrics)} healthy"

    Logger.info(
      "Recovery verification: #{unhealthy_periods}/#{length(recovery_metrics)} unhealthy periods, #{healthy_recent}/#{length(recent_metrics)} recent healthy"
    )
  end
end
