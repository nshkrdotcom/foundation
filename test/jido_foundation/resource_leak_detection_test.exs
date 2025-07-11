defmodule JidoFoundation.ResourceLeakDetectionTest do
  @moduledoc """
  Comprehensive resource leak detection tests for Phase 4.1.

  Tests verify that no processes, timers, ETS tables, or other resources
  are leaked during normal operation and crash recovery scenarios.
  """

  use ExUnit.Case, async: false
  use Foundation.TelemetryTestHelpers
  require Logger

  alias JidoFoundation.{TaskPoolManager, SystemCommandManager}
  import Foundation.AsyncTestHelpers

  @moduletag :resource_testing
  @moduletag :slow
  @moduletag timeout: 60_000

  defmodule ResourceMonitor do
    @moduledoc """
    Helper module to monitor system resources during tests.
    """

    def snapshot do
      %{
        process_count: :erlang.system_info(:process_count),
        port_count: :erlang.system_info(:port_count),
        ets_count: :erlang.system_info(:ets_count),
        memory: :erlang.memory(),
        schedulers_wall_time: safe_scheduler_wall_time(),
        timestamp: System.monotonic_time(:millisecond)
      }
    end

    defp safe_scheduler_wall_time do
      try do
        :erlang.statistics(:scheduler_wall_time)
      catch
        :error, :badarg -> []
      end
    end

    def compare_snapshots(before, after_snapshot, tolerance \\ %{}) do
      default_tolerance = %{
        process_count: 20,
        port_count: 5,
        ets_count: 10,
        memory_growth_percent: 50
      }

      tolerance = Map.merge(default_tolerance, tolerance)

      results = %{
        process_leak: check_process_leak(before, after_snapshot, tolerance.process_count),
        port_leak: check_port_leak(before, after_snapshot, tolerance.port_count),
        ets_leak: check_ets_leak(before, after_snapshot, tolerance.ets_count),
        memory_leak: check_memory_leak(before, after_snapshot, tolerance.memory_growth_percent)
      }

      has_leaks = Enum.any?(results, fn {_key, result} -> result.leaked end)

      %{
        has_leaks: has_leaks,
        details: results,
        duration_ms: after_snapshot.timestamp - before.timestamp
      }
    end

    defp check_process_leak(before, after_snapshot, tolerance) do
      diff = after_snapshot.process_count - before.process_count
      leaked = diff > tolerance

      %{
        leaked: leaked,
        before: before.process_count,
        after: after_snapshot.process_count,
        diff: diff,
        tolerance: tolerance
      }
    end

    defp check_port_leak(before, after_snapshot, tolerance) do
      diff = after_snapshot.port_count - before.port_count
      leaked = diff > tolerance

      %{
        leaked: leaked,
        before: before.port_count,
        after: after_snapshot.port_count,
        diff: diff,
        tolerance: tolerance
      }
    end

    defp check_ets_leak(before, after_snapshot, tolerance) do
      diff = after_snapshot.ets_count - before.ets_count
      leaked = diff > tolerance

      %{
        leaked: leaked,
        before: before.ets_count,
        after: after_snapshot.ets_count,
        diff: diff,
        tolerance: tolerance
      }
    end

    defp check_memory_leak(before, after_snapshot, max_growth_percent) do
      before_total = before.memory[:total] || 0
      after_total = after_snapshot.memory[:total] || 0

      growth_percent =
        if before_total > 0 do
          (after_total - before_total) / before_total * 100
        else
          0
        end

      leaked = growth_percent > max_growth_percent

      %{
        leaked: leaked,
        before_mb: round(before_total / (1024 * 1024)),
        after_mb: round(after_total / (1024 * 1024)),
        growth_percent: Float.round(growth_percent, 2),
        max_growth_percent: max_growth_percent
      }
    end
  end

  setup do
    # Take initial resource snapshot
    initial_snapshot = ResourceMonitor.snapshot()

    # Clean up any existing test data and wait for GC to complete
    wait_for_gc_completion()

    on_exit(fn ->
      # Final cleanup and leak check
      wait_for_gc_completion(timeout: 500)
      wait_for_resource_cleanup(timeout: 500)

      final_snapshot = ResourceMonitor.snapshot()
      leak_results = ResourceMonitor.compare_snapshots(initial_snapshot, final_snapshot)

      if leak_results.has_leaks do
        Logger.warning("Resource leaks detected in test: #{inspect(leak_results.details)}")
      end
    end)

    %{initial_snapshot: initial_snapshot}
  end

  describe "TaskPoolManager resource leak testing" do
    test "No process leaks during normal task pool operations", %{initial_snapshot: initial} do
      # Run multiple batches of tasks
      for batch <- 1..10 do
        {:ok, stream} =
          TaskPoolManager.execute_batch(
            :general,
            1..20,
            fn x ->
              # Quick computation instead of sleep
              x * batch
            end,
            max_concurrency: 5,
            timeout: 5000
          )

        # Consume the stream
        results = Enum.to_list(stream)
        assert length(results) == 20
      end

      # Force garbage collection
      :erlang.garbage_collect()
      wait_for_gc_completion(timeout: 200)

      # Check for leaks
      final_snapshot = ResourceMonitor.snapshot()
      leak_results = ResourceMonitor.compare_snapshots(initial, final_snapshot)

      refute leak_results.has_leaks, "Resource leaks detected: #{inspect(leak_results.details)}"
    end

    test "No resource leaks during task pool crashes and restarts", %{initial_snapshot: initial} do
      for _cycle <- 1..5 do
        # Start some tasks (may fail if pool not ready)
        _task_refs =
          for i <- 1..5 do
            case TaskPoolManager.execute_task(:general, fn ->
                   # Quick computation instead of sleep
                   i * 100
                 end) do
              {:ok, task} -> task
              # Pool not available
              {:error, _} -> nil
            end
          end

        # Kill TaskPoolManager while tasks are running
        task_pool_pid = Process.whereis(JidoFoundation.TaskPoolManager)
        Process.exit(task_pool_pid, :kill)

        # Wait for restart using deterministic polling
        wait_for(fn -> Process.whereis(JidoFoundation.TaskPoolManager) end, 3000)

        # Wait for service restart instead of trying to await dead tasks
        new_pid =
          wait_for(
            fn ->
              case Process.whereis(JidoFoundation.TaskPoolManager) do
                # Still old PID
                ^task_pool_pid -> nil
                # Process dead
                nil -> nil
                # New PID
                pid when is_pid(pid) -> pid
              end
            end,
            3000
          )

        assert is_pid(new_pid)
        assert new_pid != task_pool_pid
      end

      # Cleanup and check
      :erlang.garbage_collect()
      # Wait for cleanup to complete
      wait_for(
        fn ->
          # Verify system is stable by checking service responsiveness
          case TaskPoolManager.get_all_stats() do
            stats when is_map(stats) -> true
            _ -> nil
          end
        end,
        2000
      )

      final_snapshot = ResourceMonitor.snapshot()

      leak_results =
        ResourceMonitor.compare_snapshots(
          initial,
          final_snapshot,
          # Allow higher tolerance for restart cycles
          %{process_count: 50}
        )

      refute leak_results.has_leaks, "Resource leaks detected: #{inspect(leak_results.details)}"
    end

    test "Task pool creation and deletion doesn't leak resources", %{initial_snapshot: initial} do
      # Create and delete many pools
      for i <- 1..20 do
        pool_name = :"test_pool_#{i}"

        # Create pool
        assert :ok =
                 TaskPoolManager.create_pool(pool_name, %{
                   max_concurrency: 3,
                   timeout: 1000
                 })

        # Use the pool
        {:ok, stream} =
          TaskPoolManager.execute_batch(
            pool_name,
            1..5,
            fn x -> x * 2 end,
            timeout: 500
          )

        results = Enum.to_list(stream)
        assert length(results) == 5

        # Note: We don't have a delete_pool function, but the supervisor
        # should clean up properly when processes terminate
      end

      :erlang.garbage_collect()
      # Wait for cleanup instead of sleep
      wait_for(
        fn ->
          case TaskPoolManager.get_all_stats() do
            stats when is_map(stats) -> true
            _ -> nil
          end
        end,
        1000
      )

      final_snapshot = ResourceMonitor.snapshot()

      leak_results =
        ResourceMonitor.compare_snapshots(initial, final_snapshot, %{
          # Higher tolerance for pool creation test
          process_count: 50
        })

      refute leak_results.has_leaks, "Resource leaks detected: #{inspect(leak_results.details)}"
    end
  end

  describe "SystemCommandManager resource leak testing" do
    test "No resource leaks during command execution", %{initial_snapshot: initial} do
      # Execute many commands
      for _i <- 1..50 do
        case SystemCommandManager.get_load_average() do
          {:ok, _load} -> :ok
          # Command may not be available
          {:error, _} -> :ok
        end

        # Test memory info as well
        case SystemCommandManager.get_memory_info() do
          {:ok, _memory} -> :ok
          # Acceptable if command not available
          {:error, _} -> :ok
        end

        # No artificial delay needed
      end

      :erlang.garbage_collect()
      # Wait for any async cleanup to complete
      wait_for(
        fn ->
          # Check that command manager is still responsive
          case SystemCommandManager.get_stats() do
            stats when is_map(stats) -> true
            _ -> nil
          end
        end,
        1000
      )

      final_snapshot = ResourceMonitor.snapshot()
      leak_results = ResourceMonitor.compare_snapshots(initial, final_snapshot)

      refute leak_results.has_leaks, "Resource leaks detected: #{inspect(leak_results.details)}"
    end

    test "No resource leaks during command caching cycles", %{initial_snapshot: initial} do
      # Test cache behavior with TTL
      for cycle <- 1..10 do
        # Execute commands that should be cached
        for _i <- 1..5 do
          case SystemCommandManager.get_load_average() do
            {:ok, _load} -> :ok
            # Command may not be available
            {:error, _} -> :ok
          end
        end

        # Clear cache periodically
        if rem(cycle, 3) == 0 do
          SystemCommandManager.clear_cache()
        end

        wait_for_gc_completion(timeout: 100)
      end

      :erlang.garbage_collect()
      wait_for_gc_completion(timeout: 200)

      final_snapshot = ResourceMonitor.snapshot()
      leak_results = ResourceMonitor.compare_snapshots(initial, final_snapshot)

      refute leak_results.has_leaks, "Resource leaks detected: #{inspect(leak_results.details)}"
    end

    test "No resource leaks during SystemCommandManager crashes", %{initial_snapshot: initial} do
      # Reduced cycles
      for _cycle <- 1..3 do
        # Kill SystemCommandManager
        case Process.whereis(JidoFoundation.SystemCommandManager) do
          # Already dead
          nil ->
            :ok

          cmd_manager_pid when is_pid(cmd_manager_pid) ->
            Process.exit(cmd_manager_pid, :kill)

            # Wait for restart
            wait_for_gc_completion(timeout: 500)

            # Verify restart
            new_pid = Process.whereis(JidoFoundation.SystemCommandManager)
            assert is_pid(new_pid)
            assert new_pid != cmd_manager_pid
        end
      end

      :erlang.garbage_collect()
      wait_for_gc_completion(timeout: 700)

      final_snapshot = ResourceMonitor.snapshot()

      leak_results =
        ResourceMonitor.compare_snapshots(
          initial,
          final_snapshot,
          # More lenient tolerance for crash testing
          %{process_count: 50}
        )

      refute leak_results.has_leaks, "Resource leaks detected: #{inspect(leak_results.details)}"
    end
  end

  describe "Memory leak detection" do
    test "No memory leaks during sustained operations", %{initial_snapshot: initial} do
      # Run sustained operations for a longer period
      start_time = System.monotonic_time(:millisecond)
      # 10 seconds
      end_time = start_time + 10_000

      # Run sustained operations until end time
      task_count =
        Enum.reduce_while(Stream.cycle([1]), 0, fn _, acc ->
          if System.monotonic_time(:millisecond) >= end_time do
            {:halt, acc}
          else
            # Mix of operations
            spawn(fn ->
              case TaskPoolManager.execute_batch(
                     :general,
                     1..5,
                     fn x -> x * 2 end,
                     timeout: 1000
                   ) do
                {:ok, stream} -> Enum.to_list(stream)
                _ -> :ok
              end
            end)

            spawn(fn ->
              SystemCommandManager.get_load_average()
            end)

            new_task_count = acc + 1

            # Periodic garbage collection
            if rem(new_task_count, 100) == 0 do
              :erlang.garbage_collect()
            end

            # Yield to allow other processes to run
            :erlang.yield()
            {:cont, new_task_count}
          end
        end)

      # Final cleanup
      :erlang.garbage_collect()
      wait_for_gc_completion(timeout: 1200)

      final_snapshot = ResourceMonitor.snapshot()

      leak_results =
        ResourceMonitor.compare_snapshots(
          initial,
          final_snapshot,
          # Allow for some growth during sustained ops
          %{memory_growth_percent: 100}
        )

      refute leak_results.details.memory_leak.leaked,
             "Memory leak detected: #{inspect(leak_results.details.memory_leak)}"

      Logger.info(
        "Sustained operations completed: #{task_count} cycles, " <>
          "Memory: #{leak_results.details.memory_leak.before_mb}MB -> " <>
          "#{leak_results.details.memory_leak.after_mb}MB " <>
          "(#{leak_results.details.memory_leak.growth_percent}% growth)"
      )
    end
  end

  describe "Timer leak detection" do
    test "No timer leaks from periodic operations" do
      # This test verifies that services don't leak timers
      initial_timer_count = count_active_timers()

      # Start and stop operations that use timers
      for _i <- 1..10 do
        # SystemCommandManager uses timeouts for commands
        {:ok, _load} = SystemCommandManager.get_load_average()
        wait_for_gc_completion(timeout: 100)
      end

      # Wait for timers to expire
      wait_for_gc_completion(timeout: 700)

      final_timer_count = count_active_timers()

      # Should not have significantly more timers
      assert final_timer_count - initial_timer_count < 10,
             "Timer leak detected: #{initial_timer_count} -> #{final_timer_count}"
    end

    defp count_active_timers do
      # Count timers across all processes (approximation)
      processes = Process.list()

      timer_count =
        Enum.reduce(processes, 0, fn pid, acc ->
          try do
            case Process.info(pid, :message_queue_len) do
              {:message_queue_len, _} ->
                # Process is alive, safe to check timers
                case Process.info(pid, :timer) do
                  {:timer, timer_info} when is_list(timer_info) ->
                    acc + length(timer_info)

                  {:timer, _} ->
                    acc + 1

                  nil ->
                    acc
                end

              nil ->
                # Process is dead
                acc
            end
          catch
            # Process died while we were checking
            _, _ -> acc
          end
        end)

      timer_count
    end
  end

  describe "ETS table leak detection" do
    test "No ETS table leaks during normal operations", %{initial_snapshot: initial} do
      # Operations that might create ETS tables
      for _i <- 1..20 do
        # Get stats which might use ETS internally
        TaskPoolManager.get_all_stats()
        SystemCommandManager.get_stats()
        # Yield to allow system operations to complete
        :erlang.yield()
      end

      final_snapshot = ResourceMonitor.snapshot()
      leak_results = ResourceMonitor.compare_snapshots(initial, final_snapshot)

      refute leak_results.details.ets_leak.leaked,
             "ETS table leak detected: #{inspect(leak_results.details.ets_leak)}"
    end
  end
end
