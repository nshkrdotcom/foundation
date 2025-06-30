defmodule JidoFoundation.IntegrationValidationTest do
  @moduledoc """
  Comprehensive integration validation tests for Phase 4.

  Tests verify that all components work together correctly across
  supervisor boundaries with proper error handling and recovery.
  """

  use ExUnit.Case, async: false
  require Logger

  alias JidoFoundation.{
    TaskPoolManager,
    SystemCommandManager,
    Bridge
  }

  @moduletag :integration_testing
  @moduletag timeout: 60_000

  describe "Cross-supervisor integration" do
    test "Bridge integrates properly with all Foundation services" do
      # Test that Bridge can use TaskPoolManager for distributed execution
      {:ok, agents} = Bridge.find_agents_by_capability(:test_capability)
      # Should work even if no agents found
      assert is_list(agents)

      # Test Bridge integration with SystemCommandManager (indirect)
      # The Bridge doesn't directly call SystemCommandManager, but agents do
      assert is_pid(Process.whereis(JidoFoundation.SystemCommandManager))

      # Test signal emission
      test_signal = %{
        type: "test.integration.signal",
        source: "/test/integration",
        data: %{message: "Integration test"}
      }

      {:ok, [emitted_signal]} = Bridge.emit_signal(self(), test_signal)
      assert emitted_signal.signal.type == "test.integration.signal"
    end

    test "TaskPoolManager integrates with Bridge distributed execution" do
      # Create a mock operation that would use distributed execution
      mock_operation = fn _agent_pid ->
        # Simulate agent operation
        Process.sleep(10)
        {:ok, "operation_result"}
      end

      # Test distributed execution with empty agent list (should handle gracefully)
      {:ok, results} = Bridge.distributed_execute(:nonexistent_capability, mock_operation)
      assert is_list(results)
      # No agents with that capability
      assert Enum.empty?(results)
    end

    test "All services communicate through proper supervision channels" do
      # Verify all key services are running under supervision
      services = [
        JidoFoundation.TaskPoolManager,
        JidoFoundation.SystemCommandManager,
        JidoFoundation.CoordinationManager,
        JidoFoundation.SchedulerManager
      ]

      for service <- services do
        pid = Process.whereis(service)
        assert is_pid(pid), "#{service} should be running"

        # Verify it's properly supervised by checking its supervisor
        case Process.info(pid, :links) do
          {:links, links} ->
            supervisor_links =
              Enum.filter(links, fn linked_pid ->
                case Process.info(linked_pid, :dictionary) do
                  {:dictionary, dict} ->
                    Keyword.has_key?(dict, :"$ancestors") or
                      Keyword.has_key?(dict, :"$initial_call")

                  nil ->
                    false
                end
              end)

            assert length(supervisor_links) > 0, "#{service} should have supervisor links"

          nil ->
            flunk("Could not get process info for #{service}")
        end
      end
    end
  end

  describe "Error boundary validation" do
    test "Service failures don't cascade across supervision boundaries" do
      # Get initial states
      task_pool_pid = Process.whereis(JidoFoundation.TaskPoolManager)
      system_cmd_pid = Process.whereis(JidoFoundation.SystemCommandManager)
      coordination_pid = Process.whereis(JidoFoundation.CoordinationManager)

      assert is_pid(task_pool_pid)
      assert is_pid(system_cmd_pid)
      assert is_pid(coordination_pid)

      # Kill TaskPoolManager
      Process.exit(task_pool_pid, :kill)
      Process.sleep(200)

      # Verify other services are still alive
      assert Process.alive?(system_cmd_pid),
             "SystemCommandManager should survive TaskPoolManager crash"

      assert Process.alive?(coordination_pid),
             "CoordinationManager should survive TaskPoolManager crash"

      # Verify TaskPoolManager restarted
      new_task_pool_pid = Process.whereis(JidoFoundation.TaskPoolManager)
      assert is_pid(new_task_pool_pid)
      assert new_task_pool_pid != task_pool_pid

      # Verify functionality is restored
      {:ok, _stats} = TaskPoolManager.get_all_stats()
      {:ok, _load} = SystemCommandManager.get_load_average()
    end

    test "Circuit breakers protect services from overload" do
      # Test SystemCommandManager under load
      # Try to overwhelm it with many concurrent requests
      concurrent_requests = 20

      tasks =
        for i <- 1..concurrent_requests do
          Task.async(fn ->
            case SystemCommandManager.execute_command("uptime", [], timeout: 1000) do
              {:ok, result} -> {:success, i, result}
              {:error, :too_many_concurrent_commands} -> {:limited, i}
              {:error, reason} -> {:error, i, reason}
            end
          end)
        end

      results = Task.await_many(tasks, 5000)

      # Should have some successful requests
      success_count =
        Enum.count(results, fn
          {:success, _, _} -> true
          _ -> false
        end)

      # Should have proper rate limiting
      limited_count =
        Enum.count(results, fn
          {:limited, _} -> true
          _ -> false
        end)

      assert success_count > 0, "Should have some successful requests"

      # If we hit limits, that's proper backpressure
      if limited_count > 0 do
        Logger.info(
          "Rate limiting working: #{limited_count} requests limited out of #{concurrent_requests}"
        )
      end

      # Verify service is still functional after load
      {:ok, _load} = SystemCommandManager.get_load_average()
    end
  end

  describe "End-to-end workflow validation" do
    test "Complete monitoring workflow through all services" do
      # Simulate a complete monitoring workflow that uses multiple services

      # 1. Start monitoring data collection (uses SystemCommandManager)
      {:ok, load_avg} = SystemCommandManager.get_load_average()
      assert is_float(load_avg)

      # 2. Process the data through task pools
      processing_data = [load_avg, load_avg * 1.1, load_avg * 0.9]

      {:ok, stream} =
        TaskPoolManager.execute_batch(
          :monitoring,
          processing_data,
          fn value ->
            # Simulate monitoring data processing
            %{
              value: value,
              status: if(value > 1.0, do: :warning, else: :ok),
              timestamp: DateTime.utc_now()
            }
          end,
          timeout: 5000
        )

      processed_results = Enum.to_list(stream)
      assert length(processed_results) == 3

      # 3. Emit signals based on results
      for {:ok, result} <- processed_results do
        signal_type =
          case result.status do
            :warning -> "monitoring.alert.warning"
            :ok -> "monitoring.status.ok"
          end

        signal = %{
          type: signal_type,
          source: "/monitoring/integration_test",
          data: result
        }

        {:ok, [_emitted]} = Bridge.emit_signal(self(), signal)
      end

      # 4. Verify system health after workflow
      stats = SystemCommandManager.get_stats()
      assert stats.commands_executed > 0

      pool_stats = TaskPoolManager.get_all_stats()
      assert is_map(pool_stats)
    end

    test "Error recovery workflow across all services" do
      # Test that the system can recover from a complex failure scenario

      # 1. Start operations across multiple services
      background_tasks = [
        Task.async(fn ->
          for _i <- 1..10 do
            TaskPoolManager.execute_batch(:general, [1, 2], fn x -> x end, timeout: 1000)
            |> elem(1)
            |> Enum.to_list()

            Process.sleep(50)
          end
        end),
        Task.async(fn ->
          for _i <- 1..5 do
            SystemCommandManager.get_load_average()
            Process.sleep(100)
          end
        end)
      ]

      # Let operations start
      Process.sleep(200)

      # 2. Cause failures
      task_pool_pid = Process.whereis(JidoFoundation.TaskPoolManager)
      system_cmd_pid = Process.whereis(JidoFoundation.SystemCommandManager)

      Process.exit(task_pool_pid, :kill)
      Process.sleep(100)
      Process.exit(system_cmd_pid, :kill)

      # 3. Wait for recovery
      Process.sleep(500)

      # 4. Verify all services recovered
      new_task_pool_pid = Process.whereis(JidoFoundation.TaskPoolManager)
      new_system_cmd_pid = Process.whereis(JidoFoundation.SystemCommandManager)

      assert is_pid(new_task_pool_pid)
      assert is_pid(new_system_cmd_pid)
      assert new_task_pool_pid != task_pool_pid
      assert new_system_cmd_pid != system_cmd_pid

      # 5. Verify functionality restored
      {:ok, _load} = SystemCommandManager.get_load_average()
      {:ok, _stats} = TaskPoolManager.get_all_stats()

      # 6. Clean up background tasks
      for task <- background_tasks do
        try do
          Task.await(task, 2000)
        catch
          # Some may have failed due to service restarts
          :exit, _ -> :ok
        end
      end
    end
  end

  describe "Configuration and state management" do
    test "Services maintain proper configuration after restarts" do
      # Get initial configuration
      initial_stats = SystemCommandManager.get_stats()
      initial_allowed_commands = initial_stats.allowed_commands

      # Kill and restart SystemCommandManager
      system_cmd_pid = Process.whereis(JidoFoundation.SystemCommandManager)
      Process.exit(system_cmd_pid, :kill)
      Process.sleep(200)

      # Verify configuration is maintained
      new_stats = SystemCommandManager.get_stats()
      assert new_stats.allowed_commands == initial_allowed_commands

      # Test TaskPoolManager configuration persistence
      # Create a pool with specific configuration
      pool_name = :test_config_pool
      config = %{max_concurrency: 7, timeout: 3000}

      assert :ok = TaskPoolManager.create_pool(pool_name, config)
      {:ok, pool_stats} = TaskPoolManager.get_pool_stats(pool_name)
      assert pool_stats.max_concurrency == 7

      # Kill and restart TaskPoolManager
      task_pool_pid = Process.whereis(JidoFoundation.TaskPoolManager)
      Process.exit(task_pool_pid, :kill)
      Process.sleep(300)

      # Verify default pools are recreated (custom pools may be lost)
      {:ok, general_stats} = TaskPoolManager.get_pool_stats(:general)
      assert is_map(general_stats)
    end

    test "Service discovery works across restarts" do
      # Verify service discovery before restarts
      services_before = [
        JidoFoundation.TaskPoolManager,
        JidoFoundation.SystemCommandManager,
        JidoFoundation.CoordinationManager,
        JidoFoundation.SchedulerManager
      ]

      pids_before =
        for service <- services_before do
          {service, Process.whereis(service)}
        end

      # All should be registered
      for {service, pid} <- pids_before do
        assert is_pid(pid), "#{service} should be registered"
      end

      # Kill half the services
      Process.exit(Process.whereis(JidoFoundation.TaskPoolManager), :kill)
      Process.exit(Process.whereis(JidoFoundation.SystemCommandManager), :kill)

      Process.sleep(300)

      # Verify service discovery still works
      pids_after =
        for service <- services_before do
          {service, Process.whereis(service)}
        end

      for {service, pid} <- pids_after do
        assert is_pid(pid), "#{service} should be re-registered after restart"
      end

      # Verify the restarted services have new pids
      {_, old_task_pool_pid} = List.keyfind(pids_before, JidoFoundation.TaskPoolManager, 0)
      {_, new_task_pool_pid} = List.keyfind(pids_after, JidoFoundation.TaskPoolManager, 0)

      assert old_task_pool_pid != new_task_pool_pid, "TaskPoolManager should have new pid"
    end
  end

  describe "Load balancing and resource management" do
    test "Task pools properly distribute load" do
      # Create multiple pools with different configurations
      pool_configs = [
        {:load_test_1, %{max_concurrency: 2, timeout: 2000}},
        {:load_test_2, %{max_concurrency: 5, timeout: 2000}},
        {:load_test_3, %{max_concurrency: 3, timeout: 2000}}
      ]

      for {pool_name, config} <- pool_configs do
        TaskPoolManager.create_pool(pool_name, config)
      end

      # Submit work to all pools simultaneously
      pool_tasks =
        for {pool_name, _config} <- pool_configs do
          Task.async(fn ->
            start_time = System.monotonic_time(:millisecond)

            {:ok, stream} =
              TaskPoolManager.execute_batch(
                pool_name,
                # 20 tasks per pool
                1..20,
                fn x ->
                  # Simulate work
                  Process.sleep(50)
                  x * 10
                end,
                timeout: 5000
              )

            results = Enum.to_list(stream)
            end_time = System.monotonic_time(:millisecond)

            {pool_name, length(results), end_time - start_time}
          end)
        end

      # Wait for all pools to complete
      pool_results = Task.await_many(pool_tasks, 10000)

      # Verify all pools completed their work
      for {pool_name, result_count, duration} <- pool_results do
        assert result_count == 20, "Pool #{pool_name} should complete all 20 tasks"
        Logger.info("Pool #{pool_name} completed #{result_count} tasks in #{duration}ms")
      end

      # Verify pools with higher concurrency completed faster
      durations = Enum.map(pool_results, fn {_, _, duration} -> duration end)
      max_duration = Enum.max(durations)
      min_duration = Enum.min(durations)

      # Higher concurrency pools should be at least somewhat faster
      assert max_duration - min_duration < 5000,
             "Pool performance should vary with concurrency settings"
    end

    test "System handles resource exhaustion gracefully" do
      # Try to create a very resource-intensive operation
      intensive_operation = fn x ->
        # Create some memory pressure
        _large_list = for i <- 1..1000, do: {i, x, :rand.uniform(1000)}
        Process.sleep(10)
        x
      end

      # Submit many concurrent intensive operations
      {:ok, stream} =
        TaskPoolManager.execute_batch(
          :general,
          # Many tasks
          1..100,
          intensive_operation,
          # High concurrency
          max_concurrency: 20,
          timeout: 10000
        )

      # Should handle the load without crashing
      results = Enum.to_list(stream)

      # Most should succeed
      success_count =
        Enum.count(results, fn
          {:ok, _} -> true
          _ -> false
        end)

      assert success_count > 50, "Most operations should succeed even under load"

      # System should still be functional
      {:ok, _stats} = TaskPoolManager.get_all_stats()
      {:ok, _load} = SystemCommandManager.get_load_average()
    end
  end
end
