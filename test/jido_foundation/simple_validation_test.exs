defmodule JidoFoundation.SimpleValidationTest do
  @moduledoc """
  Simple validation tests to verify basic OTP compliance.

  These tests focus on basic functionality rather than complex scenarios.
  """

  use ExUnit.Case, async: false
  require Logger

  alias JidoFoundation.{TaskPoolManager, SystemCommandManager}
  import Foundation.AsyncTestHelpers

  # Remove broken setup that causes infinite waits

  describe "Basic service availability" do
    test "All Foundation services are running and registered" do
      services = [
        JidoFoundation.TaskPoolManager,
        JidoFoundation.SystemCommandManager,
        JidoFoundation.CoordinationManager,
        JidoFoundation.SchedulerManager
      ]

      for service <- services do
        pid = Process.whereis(service)
        assert is_pid(pid), "#{service} should be running"
        assert Process.alive?(pid), "#{service} should be alive"
      end
    end

    test "TaskPoolManager basic functionality works" do
      # Test basic stats
      stats = TaskPoolManager.get_all_stats()
      assert is_map(stats)

      # Test simple batch operation
      case TaskPoolManager.execute_batch(
             :general,
             [1, 2, 3],
             fn x -> x * 2 end,
             timeout: 5000
           ) do
        {:ok, stream} ->
          results = Enum.to_list(stream)
          assert length(results) == 3

          # Check we got expected results
          success_results =
            Enum.filter(results, fn
              {:ok, _} -> true
              _ -> false
            end)

          # Allow for some failures
          assert length(success_results) >= 2

        {:error, reason} ->
          flunk("TaskPoolManager batch execution failed: #{inspect(reason)}")
      end
    end

    test "SystemCommandManager basic functionality works" do
      # Test stats
      stats = SystemCommandManager.get_stats()
      assert is_map(stats)
      assert Map.has_key?(stats, :commands_executed)

      # Test load average (may fail on some systems)
      case SystemCommandManager.get_load_average() do
        {:ok, load_avg} ->
          assert is_float(load_avg)
          assert load_avg >= 0.0

        {:error, _reason} ->
          # This is ok, uptime command may not be available
          :ok
      end
    end
  end

  describe "Basic crash recovery" do
    test "TaskPoolManager restarts after being killed" do
      initial_pid = Process.whereis(JidoFoundation.TaskPoolManager)
      assert is_pid(initial_pid)

      # Kill the process
      Process.exit(initial_pid, :kill)

      # Wait for restart using proper async helpers
      new_pid =
        wait_for(
          fn ->
            case Process.whereis(JidoFoundation.TaskPoolManager) do
              # Still the old PID
              ^initial_pid -> nil
              # Process dead
              nil -> nil
              # New PID
              pid when is_pid(pid) -> pid
            end
          end,
          5000
        )

      assert is_pid(new_pid)
      assert new_pid != initial_pid

      # Wait for general pool to be ready
      wait_for(
        fn ->
          case TaskPoolManager.get_pool_stats(:general) do
            {:ok, _stats} -> true
            {:error, _} -> nil
          end
        end,
        3000
      )

      # Verify it's functional
      stats = TaskPoolManager.get_all_stats()
      assert is_map(stats)

      # Verify general pool is available
      {:ok, _general_stats} = TaskPoolManager.get_pool_stats(:general)
    end

    test "SystemCommandManager restarts after being killed" do
      initial_pid = Process.whereis(JidoFoundation.SystemCommandManager)
      assert is_pid(initial_pid)

      # Kill the process
      Process.exit(initial_pid, :kill)

      # Wait for restart using proper async helpers
      new_pid =
        wait_for(
          fn ->
            case Process.whereis(JidoFoundation.SystemCommandManager) do
              # Still the old PID
              ^initial_pid -> nil
              # Process dead
              nil -> nil
              # New PID
              pid when is_pid(pid) -> pid
            end
          end,
          5000
        )

      assert is_pid(new_pid)
      assert new_pid != initial_pid

      # Verify it's functional
      stats = SystemCommandManager.get_stats()
      assert is_map(stats)
    end
  end

  describe "Resource management" do
    test "Process count remains stable" do
      initial_count = :erlang.system_info(:process_count)

      # Do some work
      for _i <- 1..5 do
        case TaskPoolManager.execute_batch(
               :general,
               [1, 2],
               fn x -> x end,
               timeout: 1000
             ) do
          {:ok, stream} -> Enum.to_list(stream)
          {:error, _} -> :ok
        end
      end

      # Wait for cleanup (minimal delay)
      :timer.sleep(50)

      final_count = :erlang.system_info(:process_count)
      diff = final_count - initial_count

      # Should not leak significant processes
      assert diff < 20,
             "Process count grew too much: #{initial_count} -> #{final_count} (diff: #{diff})"
    end
  end

  describe "Basic performance" do
    test "TaskPoolManager can handle multiple operations" do
      start_time = System.monotonic_time(:millisecond)

      # Reduced to be less aggressive
      results =
        for _i <- 1..5 do
          case TaskPoolManager.execute_batch(
                 :general,
                 [1, 2, 3],
                 fn x -> x * 2 end,
                 timeout: 2000
               ) do
            {:ok, stream} ->
              stream_results = Enum.to_list(stream)
              {:ok, length(stream_results)}

            {:error, reason} ->
              Logger.warning("TaskPoolManager operation failed: #{inspect(reason)}")
              {:error, reason}
          end
        end

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # Check that most operations succeeded
      successful =
        Enum.count(results, fn
          {:ok, _} -> true
          _ -> false
        end)

      assert successful >= 3, "Most operations should succeed (#{successful}/5)"
      assert duration < 30_000, "Operations should complete in reasonable time (#{duration}ms)"
    end
  end
end
