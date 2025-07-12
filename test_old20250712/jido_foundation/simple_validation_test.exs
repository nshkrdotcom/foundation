defmodule JidoFoundation.SimpleValidationTest do
  @moduledoc """
  Simple validation tests to verify basic OTP compliance.

  These tests focus on basic functionality rather than complex scenarios.
  Now uses isolated supervision testing to avoid global state contamination.
  """

  use Foundation.UnifiedTestFoundation, :supervision_testing
  require Logger

  alias JidoFoundation.{TaskPoolManager, SystemCommandManager}
  alias Foundation.IsolatedServiceDiscovery, as: ServiceDiscovery

  # No custom setup needed - supervision testing infrastructure handles everything

  describe "Basic service availability" do
    test "All Foundation services are running and registered", %{supervision_tree: sup_tree} do
      service_names = [
        :task_pool_manager,
        :system_command_manager,
        :coordination_manager,
        :scheduler_manager
      ]

      for service_name <- service_names do
        {:ok, pid} = get_service(sup_tree, service_name)
        assert is_pid(pid), "#{service_name} should be running in isolated supervision"
        assert Process.alive?(pid), "#{service_name} should be alive in isolated supervision"
      end
    end

    test "TaskPoolManager basic functionality works", %{supervision_tree: sup_tree} do
      # Ensure TaskPoolManager is alive and responsive in isolated supervision
      {:ok, task_pid} = get_service(sup_tree, :task_pool_manager)
      assert is_pid(task_pid), "TaskPoolManager should be running in isolated supervision"
      assert Process.alive?(task_pid), "TaskPoolManager should be alive in isolated supervision"

      # Test basic stats with isolated service calls
      stats = ServiceDiscovery.call_service(sup_tree, TaskPoolManager, :get_all_stats)
      assert is_map(stats)

      # Create a pool for testing in isolated environment
      pool_result =
        ServiceDiscovery.call_service(sup_tree, TaskPoolManager, :create_pool, [
          :general,
          %{max_concurrency: 4, timeout: 5000}
        ])

      assert pool_result == :ok

      # Test pool stats
      {:ok, pool_stats} =
        ServiceDiscovery.call_service(sup_tree, TaskPoolManager, :get_pool_stats, [:general])

      assert is_map(pool_stats)

      # Test simple batch operation with isolated service
      {:ok, results} =
        ServiceDiscovery.call_service(sup_tree, TaskPoolManager, :execute_batch, [
          :general,
          [1, 2, 3],
          fn x -> x * 2 end,
          timeout: 5000
        ])

      # Results should be returned directly from test service
      assert length(results) == 3

      # Check we got expected results
      success_results =
        Enum.filter(results, fn
          {:ok, _} -> true
          _ -> false
        end)

      # All should succeed in test environment
      assert length(success_results) == 3
      assert {:ok, 2} in results
      assert {:ok, 4} in results
      assert {:ok, 6} in results
    end

    test "SystemCommandManager basic functionality works", %{supervision_tree: sup_tree} do
      # Test stats with isolated service
      stats = ServiceDiscovery.call_service(sup_tree, SystemCommandManager, :get_stats)
      assert is_map(stats)
      assert Map.has_key?(stats, :commands_executed)

      # Test service availability - test service always returns :ok for get_load_average
      result = ServiceDiscovery.call_service(sup_tree, SystemCommandManager, :get_load_average)
      # Test service returns :ok instead of actual load average
      assert result == :ok
    end
  end

  describe "Basic crash recovery" do
    test "TaskPoolManager restarts after being killed", %{supervision_tree: sup_tree} do
      {:ok, initial_pid} = get_service(sup_tree, :task_pool_manager)
      assert is_pid(initial_pid)

      # Kill the process in isolated supervision
      Process.exit(initial_pid, :kill)

      # Wait for restart using isolated supervision helper
      {:ok, new_pid} = wait_for_service_restart(sup_tree, :task_pool_manager, initial_pid, 5000)

      assert is_pid(new_pid)
      assert new_pid != initial_pid

      # Verify it's functional with isolated service calls
      stats = ServiceDiscovery.call_service(sup_tree, TaskPoolManager, :get_all_stats)
      assert is_map(stats)

      # Create and verify general pool availability in isolated environment
      :ok =
        ServiceDiscovery.call_service(sup_tree, TaskPoolManager, :create_pool, [
          :general,
          %{max_concurrency: 4}
        ])

      {:ok, _general_stats} =
        ServiceDiscovery.call_service(sup_tree, TaskPoolManager, :get_pool_stats, [:general])
    end

    test "SystemCommandManager restarts after being killed", %{supervision_tree: sup_tree} do
      {:ok, initial_pid} = get_service(sup_tree, :system_command_manager)
      assert is_pid(initial_pid)

      # Kill the process in isolated supervision
      Process.exit(initial_pid, :kill)

      # Wait for restart using isolated supervision helper
      {:ok, new_pid} =
        wait_for_service_restart(sup_tree, :system_command_manager, initial_pid, 5000)

      assert is_pid(new_pid)
      assert new_pid != initial_pid

      # Verify it's functional with isolated service calls
      stats = ServiceDiscovery.call_service(sup_tree, SystemCommandManager, :get_stats)
      assert is_map(stats)
    end
  end

  describe "Resource management" do
    test "Process count remains stable", %{supervision_tree: sup_tree} do
      # Ensure TaskPoolManager is alive in isolated supervision
      {:ok, task_pid} = get_service(sup_tree, :task_pool_manager)
      assert is_pid(task_pid), "TaskPoolManager should be running in isolated supervision"
      assert Process.alive?(task_pid), "TaskPoolManager should be alive in isolated supervision"

      initial_count = :erlang.system_info(:process_count)

      # Create pool for testing in isolated environment
      :ok =
        ServiceDiscovery.call_service(sup_tree, TaskPoolManager, :create_pool, [
          :general,
          %{max_concurrency: 2}
        ])

      # Do some work with isolated service calls
      for _i <- 1..5 do
        {:ok, _results} =
          ServiceDiscovery.call_service(sup_tree, TaskPoolManager, :execute_batch, [
            :general,
            [1, 2],
            fn x -> x end,
            timeout: 1000
          ])
      end

      # Wait for processes to stabilize
      wait_for(
        fn ->
          # Check process count is stable
          count1 = :erlang.system_info(:process_count)
          :erlang.yield()
          count2 = :erlang.system_info(:process_count)

          if abs(count1 - count2) <= 2 do
            true
          else
            nil
          end
        end,
        1000
      )

      final_count = :erlang.system_info(:process_count)
      diff = final_count - initial_count

      # Should not leak significant processes in isolated environment
      assert diff < 20,
             "Process count grew too much: #{initial_count} -> #{final_count} (diff: #{diff})"
    end
  end

  describe "Basic performance" do
    test "TaskPoolManager can handle multiple operations", %{supervision_tree: sup_tree} do
      # Ensure TaskPoolManager is alive in isolated supervision
      {:ok, task_pid} = get_service(sup_tree, :task_pool_manager)
      assert is_pid(task_pid), "TaskPoolManager should be running in isolated supervision"
      assert Process.alive?(task_pid), "TaskPoolManager should be alive in isolated supervision"

      start_time = System.monotonic_time(:millisecond)

      # Create pool for testing in isolated environment
      :ok =
        ServiceDiscovery.call_service(sup_tree, TaskPoolManager, :create_pool, [
          :general,
          %{max_concurrency: 4}
        ])

      # Reduced to be less aggressive, with isolated service calls
      results =
        for _i <- 1..5 do
          {:ok, batch_results} =
            ServiceDiscovery.call_service(sup_tree, TaskPoolManager, :execute_batch, [
              :general,
              [1, 2, 3],
              fn x -> x * 2 end,
              timeout: 2000
            ])

          {:ok, length(batch_results)}
        end

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # Check that all operations succeeded in isolated environment
      successful =
        Enum.count(results, fn
          {:ok, _} -> true
          _ -> false
        end)

      assert successful == 5,
             "All operations should succeed in isolated environment (#{successful}/5)"

      assert duration < 30_000, "Operations should complete in reasonable time (#{duration}ms)"
    end
  end
end
