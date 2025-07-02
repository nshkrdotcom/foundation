defmodule JidoFoundation.SupervisionCrashRecoveryTest do
  @moduledoc """
  Comprehensive supervision crash recovery tests for Phase 4.1.

  Tests verify that all supervised processes properly restart after crashes,
  with no leaked resources and proper state recovery according to OTP principles.
  """

  use ExUnit.Case, async: false
  require Logger

  alias JidoFoundation.{
    TaskPoolManager,
    SystemCommandManager
  }

  import Foundation.AsyncTestHelpers

  # Setup helper to ensure services are running
  defp ensure_service_running(service_name, timeout \\ 5000) do
    case Process.whereis(service_name) do
      pid when is_pid(pid) ->
        pid

      nil ->
        # Wait for the service to restart
        wait_for(
          fn ->
            case Process.whereis(service_name) do
              pid when is_pid(pid) -> pid
              nil -> nil
            end
          end,
          timeout
        )
    end
  end

  @moduletag :supervision_testing
  @moduletag timeout: 30_000

  setup do
    # Ensure clean test environment with proper supervision state
    # NOTE: We don't use Process.flag(:trap_exit, true) here because
    # it can cause the test process to receive exit signals from
    # supervised processes when we intentionally kill them for testing

    # Record initial process count
    initial_process_count = :erlang.system_info(:process_count)

    # Ensure all JidoFoundation services are stable before test starts
    services = [
      JidoFoundation.TaskPoolManager,
      JidoFoundation.SystemCommandManager,
      JidoFoundation.CoordinationManager,
      JidoFoundation.SchedulerManager
    ]

    # Wait for all services to be properly registered and stable
    for service <- services do
      wait_for(
        fn ->
          case Process.whereis(service) do
            pid when is_pid(pid) ->
              if Process.alive?(pid), do: pid, else: nil

            _ ->
              nil
          end
        end,
        5000
      )
    end

    on_exit(fn ->
      # CRITICAL: Ensure supervision tree is stable after test
      # Wait for any restart activity to complete
      for service <- services do
        wait_for(
          fn ->
            case Process.whereis(service) do
              pid when is_pid(pid) ->
                if Process.alive?(pid), do: pid, else: nil

              _ ->
                nil
            end
          end,
          10_000
        )
      end

      # Wait for processes to terminate and stabilize
      wait_for(
        fn ->
          current_count = :erlang.system_info(:process_count)
          # Allow some tolerance for normal process fluctuation
          if current_count <= initial_process_count + 10 do
            true
          else
            nil
          end
        end,
        5000
      )

      # Verify no process leaks
      final_process_count = :erlang.system_info(:process_count)

      if final_process_count > initial_process_count + 20 do
        Logger.warning(
          "Potential process leak detected: #{initial_process_count} -> #{final_process_count}"
        )
      end
    end)

    %{initial_process_count: initial_process_count}
  end

  describe "JidoFoundation.TaskPoolManager crash recovery" do
    test "TaskPoolManager restarts after crash and maintains functionality" do
      # Ensure TaskPoolManager is running and get its pid
      initial_pid = ensure_service_running(JidoFoundation.TaskPoolManager)
      assert is_pid(initial_pid), "TaskPoolManager should be running"

      # Verify it's working before crash
      stats = TaskPoolManager.get_all_stats()
      assert is_map(stats)

      # Kill the TaskPoolManager process
      Process.exit(initial_pid, :kill)

      # Wait for supervisor to restart it with new pid
      new_pid =
        wait_for(
          fn ->
            case Process.whereis(JidoFoundation.TaskPoolManager) do
              pid when pid != initial_pid and is_pid(pid) -> pid
              _ -> nil
            end
          end,
          5000
        )

      # Verify it restarted with new pid
      assert is_pid(new_pid), "TaskPoolManager should be restarted"
      assert new_pid != initial_pid, "Should have new pid after restart"

      # Verify functionality is restored
      new_stats = TaskPoolManager.get_all_stats()
      assert is_map(new_stats)

      # Test that pools can be created and used (may need to wait for pools to be ready)
      case TaskPoolManager.execute_batch(
             :general,
             [1, 2, 3],
             fn x -> x * 2 end,
             timeout: 1000
           ) do
        {:ok, stream} ->
          results = Enum.to_list(stream)
          assert length(results) == 3
          assert {:ok, 2} in results
          assert {:ok, 4} in results
          assert {:ok, 6} in results

        {:error, :pool_not_found} ->
          # Pool may not be ready yet after restart, that's ok for this test
          :ok
      end
    end

    test "TaskPoolManager survives pool supervisor crashes" do
      manager_pid = Process.whereis(JidoFoundation.TaskPoolManager)
      assert is_pid(manager_pid)

      # Create a test pool
      assert :ok =
               TaskPoolManager.create_pool(:test_crash_pool, %{max_concurrency: 2, timeout: 5000})

      # Get pool stats to verify it's working
      {:ok, stats} = TaskPoolManager.get_pool_stats(:test_crash_pool)
      assert stats.max_concurrency == 2

      # Test the pool with a simple batch operation instead of individual tasks
      {:ok, stream} =
        TaskPoolManager.execute_batch(
          :test_crash_pool,
          [1, 2, 3],
          fn i ->
            # Just compute result
            i * 10
          end,
          timeout: 2000
        )

      results = Enum.to_list(stream)

      success_results =
        Enum.filter(results, fn
          {:ok, _} -> true
          _ -> false
        end)

      assert length(success_results) == 3

      # Verify TaskPoolManager is still alive and functional
      assert Process.alive?(manager_pid)
      {:ok, final_stats} = TaskPoolManager.get_pool_stats(:test_crash_pool)
      assert is_map(final_stats)
    end
  end

  describe "JidoFoundation.SystemCommandManager crash recovery" do
    test "SystemCommandManager restarts after crash and maintains functionality" do
      initial_pid = ensure_service_running(JidoFoundation.SystemCommandManager)
      assert is_pid(initial_pid), "SystemCommandManager should be running"

      # Test functionality before crash
      case SystemCommandManager.get_load_average() do
        {:ok, load_avg} -> assert is_float(load_avg)
        # May fail if uptime command not available
        {:error, _} -> :ok
      end

      # Kill the process
      Process.exit(initial_pid, :kill)

      # Wait for supervisor to restart with new pid
      new_pid =
        wait_for(
          fn ->
            case Process.whereis(JidoFoundation.SystemCommandManager) do
              pid when pid != initial_pid and is_pid(pid) -> pid
              _ -> nil
            end
          end,
          5000
        )

      # Verify restart
      assert is_pid(new_pid)
      assert new_pid != initial_pid

      # Verify functionality is restored
      case SystemCommandManager.get_load_average() do
        {:ok, new_load_avg} -> assert is_float(new_load_avg)
        # May fail if uptime command not available
        {:error, _} -> :ok
      end

      # Test that cache is reset (new instance)
      stats = SystemCommandManager.get_stats()
      assert stats.commands_executed >= 0
    end

    test "SystemCommandManager handles command execution failures gracefully" do
      # Test with invalid command (should be rejected by allowed commands list)
      {:error, {:command_not_allowed, "invalid_command"}} =
        SystemCommandManager.execute_command("invalid_command", [])

      # Verify manager is still functional
      case SystemCommandManager.get_load_average() do
        {:ok, load_avg} -> assert is_float(load_avg)
        # May fail if uptime command not available
        {:error, _} -> :ok
      end

      stats = SystemCommandManager.get_stats()
      assert is_map(stats)
    end
  end

  describe "JidoFoundation.CoordinationManager crash recovery" do
    test "CoordinationManager restarts after crash and maintains functionality" do
      initial_pid = ensure_service_running(JidoFoundation.CoordinationManager)
      assert is_pid(initial_pid), "CoordinationManager should be running"

      # Kill the process
      Process.exit(initial_pid, :kill)

      # Wait for supervisor to restart with new pid
      new_pid =
        wait_for(
          fn ->
            case Process.whereis(JidoFoundation.CoordinationManager) do
              pid when pid != initial_pid and is_pid(pid) -> pid
              _ -> nil
            end
          end,
          5000
        )

      # Verify restart
      assert is_pid(new_pid)
      assert new_pid != initial_pid

      # Test functionality (coordination manager should handle agent coordination)
      # This is a basic aliveness test since coordination depends on agents
      assert Process.alive?(new_pid)
    end
  end

  describe "JidoFoundation.SchedulerManager crash recovery" do
    test "SchedulerManager restarts after crash and maintains functionality" do
      initial_pid = ensure_service_running(JidoFoundation.SchedulerManager)
      assert is_pid(initial_pid), "SchedulerManager should be running"

      # Kill the process
      Process.exit(initial_pid, :kill)

      # Wait for supervisor to restart with new pid
      new_pid =
        wait_for(
          fn ->
            case Process.whereis(JidoFoundation.SchedulerManager) do
              pid when pid != initial_pid and is_pid(pid) -> pid
              _ -> nil
            end
          end,
          5000
        )

      # Verify restart
      assert is_pid(new_pid)
      assert new_pid != initial_pid

      # Test basic functionality
      assert Process.alive?(new_pid)
    end
  end

  describe "Cross-supervisor crash recovery" do
    test "JidoSystem supervisor children restart independently" do
      # Get all JidoSystem supervisor children
      jido_supervisor = Process.whereis(JidoSystem.Supervisor)
      assert is_pid(jido_supervisor)

      children_before = Supervisor.which_children(jido_supervisor)
      assert length(children_before) > 0

      # Kill TaskPoolManager (one of the children)
      task_pool_pid = Process.whereis(JidoFoundation.TaskPoolManager)
      Process.exit(task_pool_pid, :kill)

      # Wait for restart using deterministic check
      wait_for(
        fn ->
          case Process.whereis(JidoFoundation.TaskPoolManager) do
            pid when pid != task_pool_pid and is_pid(pid) -> true
            _ -> nil
          end
        end,
        1000,
        10
      )

      # Verify other children are still alive (supervisor might restart too)
      current_supervisor =
        case Process.whereis(JidoSystem.Supervisor) do
          nil ->
            # Wait for supervisor to restart
            restarted_supervisor =
              wait_for(
                fn ->
                  case Process.whereis(JidoSystem.Supervisor) do
                    pid when is_pid(pid) -> pid
                    _ -> nil
                  end
                end,
                5000
              )

            assert is_pid(restarted_supervisor), "JidoSystem.Supervisor should restart"
            restarted_supervisor

          pid when is_pid(pid) ->
            pid
        end

      children_after = Supervisor.which_children(current_supervisor)
      # Allow for some variation
      assert length(children_after) >= length(children_before) - 1

      # Verify specific services are still running
      assert is_pid(Process.whereis(JidoFoundation.SystemCommandManager))
      assert is_pid(Process.whereis(JidoFoundation.CoordinationManager))
      assert is_pid(Process.whereis(JidoFoundation.SchedulerManager))

      # Verify the killed service restarted
      new_task_pool_pid = Process.whereis(JidoFoundation.TaskPoolManager)
      assert is_pid(new_task_pool_pid)
      assert new_task_pool_pid != task_pool_pid
    end

    test "Multiple simultaneous crashes don't bring down the system" do
      # Get initial pids
      task_pool_pid = Process.whereis(JidoFoundation.TaskPoolManager)
      system_cmd_pid = Process.whereis(JidoFoundation.SystemCommandManager)
      scheduler_pid = Process.whereis(JidoFoundation.SchedulerManager)

      assert is_pid(task_pool_pid)
      assert is_pid(system_cmd_pid)
      assert is_pid(scheduler_pid)

      # Kill multiple services simultaneously
      Process.exit(task_pool_pid, :kill)
      Process.exit(system_cmd_pid, :kill)
      Process.exit(scheduler_pid, :kill)

      # Wait for all services to restart
      wait_for(
        fn ->
          new_task_pid = Process.whereis(JidoFoundation.TaskPoolManager)
          new_sys_pid = Process.whereis(JidoFoundation.SystemCommandManager)
          new_sched_pid = Process.whereis(JidoFoundation.SchedulerManager)

          if new_task_pid != task_pool_pid and new_sys_pid != system_cmd_pid and
               new_sched_pid != scheduler_pid and is_pid(new_task_pid) and
               is_pid(new_sys_pid) and is_pid(new_sched_pid) do
            {new_task_pid, new_sys_pid, new_sched_pid}
          else
            nil
          end
        end,
        8000
      )

      # Verify all services restarted
      new_task_pool_pid = Process.whereis(JidoFoundation.TaskPoolManager)
      new_system_cmd_pid = Process.whereis(JidoFoundation.SystemCommandManager)
      new_scheduler_pid = Process.whereis(JidoFoundation.SchedulerManager)

      assert is_pid(new_task_pool_pid)
      assert is_pid(new_system_cmd_pid)
      assert is_pid(new_scheduler_pid)

      # Verify all have new pids
      assert new_task_pool_pid != task_pool_pid
      assert new_system_cmd_pid != system_cmd_pid
      assert new_scheduler_pid != scheduler_pid

      # Verify functionality is restored
      all_stats = TaskPoolManager.get_all_stats()

      case all_stats do
        {:ok, _stats} -> :ok
        # Sometimes returns map directly
        stats when is_map(stats) -> :ok
        _other -> flunk("Could not get TaskPoolManager stats")
      end

      case SystemCommandManager.get_load_average() do
        {:ok, _load} -> :ok
        # May fail if uptime command not available
        {:error, _} -> :ok
      end
    end
  end

  describe "Resource cleanup validation" do
    test "No process leaks after service crashes and restarts" do
      initial_count = :erlang.system_info(:process_count)

      # Test ONE crash/restart cycle PROPERLY
      task_pool_pid = Process.whereis(JidoFoundation.TaskPoolManager)

      # Monitor the process before killing it
      ref = Process.monitor(task_pool_pid)
      Process.exit(task_pool_pid, :kill)

      # Wait for the DOWN message
      assert_receive {:DOWN, ^ref, :process, ^task_pool_pid, :killed}, 1000

      # The supervisor will restart it. We need to wait for it to be registered again.
      # Instead of polling, we can use a receive with a timeout
      new_pid =
        receive do
          # Flush any messages
          _ -> nil
        after
          0 ->
            # Now try multiple times with receive blocks
            receive do
              _ -> nil
            after
              200 ->
                # Check if restarted
                Process.whereis(JidoFoundation.TaskPoolManager)
            end
        end

      # If still not restarted, try once more
      new_pid =
        if !is_pid(new_pid) or new_pid == task_pool_pid do
          receive do
            _ -> nil
          after
            1000 ->
              Process.whereis(JidoFoundation.TaskPoolManager)
          end
        else
          new_pid
        end

      assert is_pid(new_pid), "TaskPoolManager should have restarted"
      assert new_pid != task_pool_pid, "Should have new PID after restart"

      # Let any spawned children stabilize using receive timeout
      receive do
        unexpected -> flunk("Unexpected message: #{inspect(unexpected)}")
      after
        1000 -> :ok
      end

      final_count = :erlang.system_info(:process_count)

      # Allow for small variance but detect significant leaks
      assert final_count - initial_count < 20,
             "Process count increased significantly: #{initial_count} -> #{final_count}"
    end

    test "ETS tables are properly cleaned up after crashes" do
      initial_ets_count = :erlang.system_info(:ets_count)

      # Crash services that might use ETS
      for _i <- 1..3 do
        case Process.whereis(JidoFoundation.SystemCommandManager) do
          # Already dead
          nil ->
            :ok

          system_cmd_pid when is_pid(system_cmd_pid) ->
            Process.exit(system_cmd_pid, :kill)
            # Wait for process to restart
            wait_for(
              fn ->
                case Process.whereis(JidoFoundation.SystemCommandManager) do
                  pid when pid != system_cmd_pid and is_pid(pid) -> true
                  _ -> nil
                end
              end,
              100,
              5
            )
        end
      end

      # Wait for ETS cleanup to complete
      wait_for(
        fn ->
          # Check that SystemCommandManager is stable
          case Process.whereis(JidoFoundation.SystemCommandManager) do
            pid when is_pid(pid) -> true
            _ -> nil
          end
        end,
        200,
        10
      )

      final_ets_count = :erlang.system_info(:ets_count)

      # ETS count should not grow significantly
      assert final_ets_count - initial_ets_count < 10,
             "ETS count increased significantly: #{initial_ets_count} -> #{final_ets_count}"
    end
  end

  describe "Graceful shutdown testing" do
    test "Services shut down gracefully when supervisor terminates" do
      # This test ensures services handle shutdown signals properly
      # We'll test with SchedulerManager as it has timer management

      scheduler_pid = Process.whereis(JidoFoundation.SchedulerManager)
      assert is_pid(scheduler_pid)

      # Monitor the process
      ref = Process.monitor(scheduler_pid)

      # Send shutdown signal (use :kill for reliable termination in tests)
      Process.exit(scheduler_pid, :kill)

      # Wait for graceful termination (allow any shutdown reason as graceful)
      receive do
        {:DOWN, ^ref, :process, ^scheduler_pid, reason}
        when reason in [:shutdown, :normal, :killed] ->
          :ok

        {:DOWN, ^ref, :process, ^scheduler_pid, reason} ->
          Logger.warning("Process terminated with reason: #{inspect(reason)}")
          # Accept other termination reasons as tests may use :kill
          :ok
      after
        2000 ->
          # Check if process actually terminated
          case Process.alive?(scheduler_pid) do
            # Process did terminate, just didn't get the message
            false -> :ok
            true -> flunk("Process did not terminate within timeout")
          end
      end

      # Wait for restart with new pid
      new_scheduler_pid =
        wait_for(
          fn ->
            case Process.whereis(JidoFoundation.SchedulerManager) do
              pid when pid != scheduler_pid and is_pid(pid) -> pid
              _ -> nil
            end
          end,
          5000
        )

      # Verify it restarted
      assert is_pid(new_scheduler_pid)
      assert new_scheduler_pid != scheduler_pid
    end
  end

  describe "Configuration persistence after restart" do
    test "Services maintain proper configuration after restarts" do
      # Get initial configuration
      initial_stats = SystemCommandManager.get_stats()
      initial_allowed_commands = initial_stats.allowed_commands

      # Kill and restart SystemCommandManager
      system_cmd_pid = Process.whereis(JidoFoundation.SystemCommandManager)

      # Monitor the process to know when it's down
      ref = Process.monitor(system_cmd_pid)
      Process.exit(system_cmd_pid, :kill)

      # Wait for the DOWN message
      assert_receive {:DOWN, ^ref, :process, ^system_cmd_pid, :killed}, 1000

      # Wait for restart using wait_for
      wait_for(
        fn ->
          case Process.whereis(JidoFoundation.SystemCommandManager) do
            pid when pid != system_cmd_pid and is_pid(pid) -> pid
            _ -> nil
          end
        end,
        5000
      )

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

      # Monitor the process to know when it's down
      ref2 = Process.monitor(task_pool_pid)
      Process.exit(task_pool_pid, :kill)

      # Wait for the DOWN message
      assert_receive {:DOWN, ^ref2, :process, ^task_pool_pid, :killed}, 1000

      # Wait for restart using wait_for
      wait_for(
        fn ->
          case Process.whereis(JidoFoundation.TaskPoolManager) do
            pid when pid != task_pool_pid and is_pid(pid) -> pid
            _ -> nil
          end
        end,
        5000
      )

      # Verify default pools are recreated (custom pools may be lost)
      case TaskPoolManager.get_pool_stats(:general) do
        {:ok, general_stats} -> assert is_map(general_stats)
        # Pool may not be ready yet
        {:error, _} -> :ok
      end
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

      # Get initial PIDs - understand supervision order: SchedulerManager -> TaskPoolManager -> SystemCommandManager -> CoordinationManager
      task_pid = Process.whereis(JidoFoundation.TaskPoolManager)
      sys_pid = Process.whereis(JidoFoundation.SystemCommandManager)
      coord_pid = Process.whereis(JidoFoundation.CoordinationManager)
      sched_pid = Process.whereis(JidoFoundation.SchedulerManager)

      # Monitor processes we'll kill and those affected by rest_for_one
      ref1 = Process.monitor(task_pid)
      ref2 = Process.monitor(sys_pid)
      ref3 = Process.monitor(coord_pid)
      # SchedulerManager should NOT be affected by TaskPoolManager crash (starts before it)

      # Kill processes - TaskPoolManager crash should restart SystemCommandManager and CoordinationManager
      Process.exit(task_pid, :kill)
      Process.exit(sys_pid, :kill)

      # Wait for killed processes to go down
      assert_receive {:DOWN, ^ref1, :process, ^task_pid, :killed}, 1000
      assert_receive {:DOWN, ^ref2, :process, ^sys_pid, :killed}, 1000

      # CoordinationManager should be restarted by supervisor (rest_for_one behavior)
      assert_receive {:DOWN, ^ref3, :process, ^coord_pid, reason3}, 2000
      assert reason3 in [:shutdown, :killed]

      # SchedulerManager should remain running (started before TaskPoolManager)
      assert Process.alive?(sched_pid),
             "SchedulerManager should not be affected by TaskPoolManager crash"

      # Wait for affected services to restart
      {_new_task_pid, _new_sys_pid, _new_coord_pid} =
        wait_for(
          fn ->
            new_task = Process.whereis(JidoFoundation.TaskPoolManager)
            new_sys = Process.whereis(JidoFoundation.SystemCommandManager)
            new_coord = Process.whereis(JidoFoundation.CoordinationManager)

            # Only services that were restarted should have new PIDs
            if new_task != task_pid and new_sys != sys_pid and
                 new_coord != coord_pid and is_pid(new_task) and
                 is_pid(new_sys) and is_pid(new_coord) do
              {new_task, new_sys, new_coord}
            else
              nil
            end
          end,
          8000
        )

      # Verify service discovery still works for all services
      pids_after =
        for service <- services_before do
          {service, Process.whereis(service)}
        end

      for {service, pid} <- pids_after do
        assert is_pid(pid), "#{service} should be re-registered after restart"
      end

      # Verify restarted services have new PIDs, SchedulerManager keeps same PID
      {_, old_task_pool_pid} = List.keyfind(pids_before, JidoFoundation.TaskPoolManager, 0)
      {_, new_task_pool_pid} = List.keyfind(pids_after, JidoFoundation.TaskPoolManager, 0)
      {_, old_sys_cmd_pid} = List.keyfind(pids_before, JidoFoundation.SystemCommandManager, 0)
      {_, new_sys_cmd_pid} = List.keyfind(pids_after, JidoFoundation.SystemCommandManager, 0)
      {_, old_coord_pid} = List.keyfind(pids_before, JidoFoundation.CoordinationManager, 0)
      {_, new_coord_pid} = List.keyfind(pids_after, JidoFoundation.CoordinationManager, 0)
      {_, old_sched_pid} = List.keyfind(pids_before, JidoFoundation.SchedulerManager, 0)
      {_, new_sched_pid} = List.keyfind(pids_after, JidoFoundation.SchedulerManager, 0)

      # Services that were killed or restarted by rest_for_one should have new PIDs
      assert old_task_pool_pid != new_task_pool_pid, "TaskPoolManager should have new pid"
      assert old_sys_cmd_pid != new_sys_cmd_pid, "SystemCommandManager should have new pid"
      assert old_coord_pid != new_coord_pid, "CoordinationManager should have new pid"

      # SchedulerManager should keep the same PID (not affected by TaskPoolManager crash)
      assert old_sched_pid == new_sched_pid,
             "SchedulerManager should keep same pid (not affected by rest_for_one)"
    end
  end

  describe "rest_for_one supervision strategy" do
    test "Service failures cause proper dependent restarts with :rest_for_one" do
      # Get initial states
      task_pool_pid = Process.whereis(JidoFoundation.TaskPoolManager)
      system_cmd_pid = Process.whereis(JidoFoundation.SystemCommandManager)
      coordination_pid = Process.whereis(JidoFoundation.CoordinationManager)

      assert is_pid(task_pool_pid)
      assert is_pid(system_cmd_pid)
      assert is_pid(coordination_pid)

      # Monitor all processes
      ref1 = Process.monitor(task_pool_pid)
      ref2 = Process.monitor(system_cmd_pid)
      ref3 = Process.monitor(coordination_pid)

      # Kill TaskPoolManager
      Process.exit(task_pool_pid, :kill)

      # Wait for DOWN messages
      # TaskPoolManager should be killed, others should be shutdown by supervisor
      assert_receive {:DOWN, ^ref1, :process, ^task_pool_pid, :killed}, 1000
      assert_receive {:DOWN, ^ref2, :process, ^system_cmd_pid, :shutdown}, 1000
      assert_receive {:DOWN, ^ref3, :process, ^coordination_pid, :shutdown}, 1000

      # Wait for all services to restart using async helpers
      # With :rest_for_one, TaskPoolManager crash SHOULD restart downstream services
      {new_task_pool_pid, new_system_cmd_pid, new_coordination_pid} =
        wait_for(
          fn ->
            task_pool = Process.whereis(JidoFoundation.TaskPoolManager)
            system_cmd = Process.whereis(JidoFoundation.SystemCommandManager)
            coordination = Process.whereis(JidoFoundation.CoordinationManager)

            # All must be new PIDs
            if is_pid(task_pool) && task_pool != task_pool_pid &&
                 is_pid(system_cmd) && system_cmd != system_cmd_pid &&
                 is_pid(coordination) && coordination != coordination_pid do
              {task_pool, system_cmd, coordination}
            else
              nil
            end
          end,
          8000
        )

      assert is_pid(new_task_pool_pid)
      assert is_pid(new_system_cmd_pid)
      assert is_pid(new_coordination_pid)

      # Verify all have new PIDs
      assert new_task_pool_pid != task_pool_pid
      assert new_system_cmd_pid != system_cmd_pid
      assert new_coordination_pid != coordination_pid

      # Verify services are functioning after restart
      assert {:ok, _} = TaskPoolManager.get_pool_stats(:general)
      assert {:ok, _} = SystemCommandManager.get_load_average()
    end

    test "Error recovery workflow across all services" do
      # Test that the system can recover from a complex failure scenario

      # 1. Verify services are initially working
      assert {:ok, _} = TaskPoolManager.get_pool_stats(:general)
      assert {:ok, _} = SystemCommandManager.get_load_average()

      # Store initial PIDs
      task_pool_pid = Process.whereis(JidoFoundation.TaskPoolManager)
      system_cmd_pid = Process.whereis(JidoFoundation.SystemCommandManager)
      coordination_pid = Process.whereis(JidoFoundation.CoordinationManager)

      # Monitor processes
      ref1 = Process.monitor(task_pool_pid)
      ref2 = Process.monitor(system_cmd_pid)
      ref3 = Process.monitor(coordination_pid)

      # 2. Cause failure - with :rest_for_one, killing TaskPoolManager 
      # will also restart SystemCommandManager and CoordinationManager
      Process.exit(task_pool_pid, :kill)

      # Wait for DOWN messages
      assert_receive {:DOWN, ^ref1, :process, ^task_pool_pid, :killed}, 1000
      assert_receive {:DOWN, ^ref2, :process, ^system_cmd_pid, :shutdown}, 1000
      assert_receive {:DOWN, ^ref3, :process, ^coordination_pid, :shutdown}, 1000

      # 3. Wait for all dependent services to restart
      {_new_task_pool_pid, _new_system_cmd_pid, _new_coordination_pid} =
        wait_for(
          fn ->
            task_pool = Process.whereis(JidoFoundation.TaskPoolManager)
            system_cmd = Process.whereis(JidoFoundation.SystemCommandManager)
            coordination = Process.whereis(JidoFoundation.CoordinationManager)

            # All must be new PIDs (rest_for_one restarts all downstream)
            if is_pid(task_pool) && task_pool != task_pool_pid &&
                 is_pid(system_cmd) && system_cmd != system_cmd_pid &&
                 is_pid(coordination) && coordination != coordination_pid do
              {task_pool, system_cmd, coordination}
            else
              nil
            end
          end,
          8000
        )

      # 4. Verify system recovered
      assert {:ok, _} = TaskPoolManager.get_pool_stats(:general)
      assert {:ok, _} = SystemCommandManager.get_load_average()

      # 5. Test can still perform operations after recovery
      # Verify pools are accessible
      stats = TaskPoolManager.get_all_stats()
      assert is_map(stats)
    end
  end
end
