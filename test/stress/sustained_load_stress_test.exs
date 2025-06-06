defmodule Foundation.Stress.SustainedLoadTest do
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
  test "system remains stable and responsive under sustained concurrent load" do
    # 30 seconds
    load_duration = 30_000
    num_workers = 50
    # Check every 2 seconds
    check_interval = 2_000

    Logger.info("Starting sustained load test with #{num_workers} workers for #{load_duration}ms")

    # Get initial memory and queue stats
    initial_stats = get_service_stats()
    Logger.info("Initial service stats: #{inspect(initial_stats)}")

    # Start the load generation
    start_time = System.monotonic_time(:millisecond)
    workers = start_load_workers(num_workers, start_time + load_duration)

    # Monitor system during load
    monitor_task =
      Task.async(fn ->
        monitor_system_health(start_time, load_duration, check_interval)
      end)

    # Wait for workers to complete
    Enum.each(workers, fn worker ->
      Task.await(worker, load_duration + 5_000)
    end)

    # Wait for monitoring to complete
    stats_history = Task.await(monitor_task, 10_000)

    Logger.info("Load test completed. Collected #{length(stats_history)} stat snapshots")

    # Get final stats and verify system health
    final_stats = get_service_stats()
    Logger.info("Final service stats: #{inspect(final_stats)}")

    # Verify system is still healthy
    assert Foundation.available?()
    assert {:ok, %{status: :healthy}} = Foundation.health()

    # Verify basic functionality still works
    verify_basic_functionality()

    # Assert memory usage didn't grow excessively
    verify_memory_stability(initial_stats, final_stats, stats_history)

    Logger.info("Sustained load stress test completed successfully")
  end

  defp start_load_workers(num_workers, end_time) do
    Enum.map(1..num_workers, fn worker_id ->
      Task.async(fn ->
        run_load_worker(worker_id, end_time)
      end)
    end)
  end

  defp run_load_worker(worker_id, end_time) do
    operations = [:config_read, :event_store, :telemetry_emit, :service_lookup]

    loop_until_time(end_time, fn ->
      operation = Enum.random(operations)

      try do
        case operation do
          :config_read ->
            Foundation.Config.get([:dev, :debug_mode])

          :event_store ->
            {:ok, event} =
              Foundation.Events.new_event(:stress_test, %{
                worker: worker_id,
                timestamp: System.os_time(:microsecond),
                operation: :event_store
              })

            Foundation.Events.store(event)

          :telemetry_emit ->
            Foundation.Telemetry.emit_counter([:stress_test, :operations], %{
              worker: worker_id,
              operation: operation
            })

          :service_lookup ->
            Foundation.ServiceRegistry.lookup(:production, :config_server)
        end
      rescue
        error ->
          Logger.warning("Worker #{worker_id} encountered error in #{operation}: #{inspect(error)}")
          # Continue running even if individual operations fail
      end

      # Small delay to prevent overwhelming the system
      :timer.sleep(:rand.uniform(10))
    end)
  end

  defp loop_until_time(end_time, operation) do
    if System.monotonic_time(:millisecond) < end_time do
      operation.()
      loop_until_time(end_time, operation)
    end
  end

  defp monitor_system_health(start_time, duration, check_interval) do
    monitor_until_time(start_time + duration, check_interval, [])
  end

  defp monitor_until_time(end_time, check_interval, acc) do
    current_time = System.monotonic_time(:millisecond)

    if current_time < end_time do
      stats = get_service_stats()
      new_acc = [%{timestamp: current_time, stats: stats} | acc]

      :timer.sleep(check_interval)
      monitor_until_time(end_time, check_interval, new_acc)
    else
      Enum.reverse(acc)
    end
  end

  defp get_service_stats do
    services = [:config_server, :event_store, :telemetry_service]

    Enum.reduce(services, %{}, fn service, acc ->
      case Foundation.ServiceRegistry.lookup(:production, service) do
        {:ok, pid} when is_pid(pid) ->
          info = Process.info(pid, [:memory, :message_queue_len, :reductions])
          Map.put(acc, service, info)

        _ ->
          Map.put(acc, service, :not_found)
      end
    end)
  end

  defp verify_basic_functionality do
    # Test config operations
    assert {:ok, _} = Foundation.Config.get([:dev, :debug_mode])

    # Test event operations
    {:ok, event} = Foundation.Events.new_event(:verification, %{test: :post_stress})
    assert {:ok, _id} = Foundation.Events.store(event)

    # Test telemetry operations
    assert :ok = Foundation.Telemetry.emit_counter([:verification, :post_stress], %{})
    assert {:ok, _metrics} = Foundation.Telemetry.get_metrics()

    # Test service registry
    assert {:ok, _pid} = Foundation.ServiceRegistry.lookup(:production, :config_server)
  end

  defp verify_memory_stability(initial_stats, final_stats, stats_history) do
    # Check that memory usage didn't grow excessively
    Enum.each([:config_server, :event_store, :telemetry_service], fn service ->
      initial_memory = get_in(initial_stats, [service, :memory]) || 0
      final_memory = get_in(final_stats, [service, :memory]) || 0

      # Allow significant memory growth for stress test (event store accumulates many events)
      # Use a reasonable upper bound of 50MB for any service
      max_allowed_memory = max(initial_memory * 20, 50_000_000)

      if final_memory > max_allowed_memory do
        Logger.error(
          "Service #{service} memory grew from #{initial_memory} to #{final_memory} bytes"
        )

        flunk(
          "Memory usage for #{service} grew excessively: #{final_memory} > #{max_allowed_memory}"
        )
      end

      # Check message queue lengths stayed reasonable
      _initial_queue = get_in(initial_stats, [service, :message_queue_len]) || 0
      final_queue = get_in(final_stats, [service, :message_queue_len]) || 0

      # Message queues should not accumulate indefinitely
      if final_queue > 1000 do
        Logger.error("Service #{service} has large message queue: #{final_queue}")
        flunk("Message queue for #{service} grew too large: #{final_queue}")
      end
    end)

    # Log some statistics about the test run
    if length(stats_history) > 0 do
      Logger.info("Memory stability check passed. Monitored #{length(stats_history)} snapshots")
    end
  end
end
