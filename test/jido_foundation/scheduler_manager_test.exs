defmodule JidoFoundation.SchedulerManagerTest do
  use ExUnit.Case, async: false

  alias JidoFoundation.SchedulerManager
  import Foundation.AsyncTestHelpers

  @moduletag :foundation_integration

  setup do
    # Ensure SchedulerManager is started (it should be via Application)
    case Process.whereis(SchedulerManager) do
      nil ->
        {:ok, _pid} = SchedulerManager.start_link()

      _pid ->
        :ok
    end

    on_exit(fn ->
      # Clean up any test agent schedules
      if Process.whereis(SchedulerManager) do
        try do
          # Get current stats to see if there are any schedules to clean up
          stats = SchedulerManager.get_stats()

          if stats.active_agents > 0 do
            # Force cleanup - the supervisor will handle this automatically
            :ok
          end
        catch
          _, _ -> :ok
        end
      end
    end)

    :ok
  end

  describe "scheduler manager" do
    test "can register and unregister periodic operations" do
      # Create a test process to schedule for
      test_agent_pid =
        spawn(fn ->
          receive do
            :test_message -> send(self(), :received_test_message)
            :stop -> :ok
          after
            5000 -> :timeout
          end
        end)

      # Register a periodic operation
      assert :ok =
               SchedulerManager.register_periodic(
                 test_agent_pid,
                 :test_schedule,
                 # 1 second
                 1000,
                 :test_message
               )

      # Check that the schedule was registered
      assert {:ok, schedules} = SchedulerManager.list_agent_schedules(test_agent_pid)
      assert length(schedules) == 1

      schedule = hd(schedules)
      assert schedule.schedule_id == :test_schedule
      assert schedule.interval == 1000
      assert schedule.message == :test_message

      # Get stats
      stats = SchedulerManager.get_stats()
      assert stats.total_schedules >= 1
      assert stats.active_agents >= 1

      # Unregister the specific schedule
      assert :ok = SchedulerManager.unregister_periodic(test_agent_pid, :test_schedule)

      # Check that the schedule was removed
      assert {:error, :not_found} = SchedulerManager.list_agent_schedules(test_agent_pid)

      # Clean up test process
      send(test_agent_pid, :stop)
    end

    test "automatically cleans up when agent dies" do
      # Create a test process
      test_agent_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          after
            5000 -> :timeout
          end
        end)

      # Register a periodic operation
      assert :ok =
               SchedulerManager.register_periodic(
                 test_agent_pid,
                 :test_schedule,
                 1000,
                 :test_message
               )

      # Verify it's registered
      assert {:ok, _schedules} = SchedulerManager.list_agent_schedules(test_agent_pid)

      # Kill the test process
      Process.exit(test_agent_pid, :kill)

      # Wait for scheduler to detect process death and clean up
      wait_for(
        fn ->
          case SchedulerManager.list_agent_schedules(test_agent_pid) do
            {:error, :not_found} -> true
            _ -> nil
          end
        end,
        2000
      )

      # Check that the schedule was automatically cleaned up
      assert {:error, :not_found} = SchedulerManager.list_agent_schedules(test_agent_pid)
    end

    test "can force immediate execution" do
      # Create a test process that records messages
      parent = self()

      test_agent_pid =
        spawn(fn ->
          receive do
            :force_test_message ->
              send(parent, :got_forced_message)

              receive do
                :stop -> :ok
              after
                5000 -> :timeout
              end

            :stop ->
              :ok
          after
            5000 -> :timeout
          end
        end)

      # Register a periodic operation with long interval
      assert :ok =
               SchedulerManager.register_periodic(
                 test_agent_pid,
                 :force_test_schedule,
                 # 1 minute - would normally take a long time
                 60_000,
                 :force_test_message
               )

      # Force immediate execution
      assert :ok = SchedulerManager.force_execution(test_agent_pid, :force_test_schedule)

      # Should receive the message quickly
      assert_receive :got_forced_message, 1000

      # Clean up
      send(test_agent_pid, :stop)
    end

    test "can update schedule intervals" do
      test_agent_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          after
            5000 -> :timeout
          end
        end)

      # Register with initial interval
      assert :ok =
               SchedulerManager.register_periodic(
                 test_agent_pid,
                 :update_test_schedule,
                 # 5 seconds
                 5000,
                 :test_message
               )

      # Update the interval
      assert :ok = SchedulerManager.update_interval(test_agent_pid, :update_test_schedule, 2000)

      # Check the updated schedule
      assert {:ok, schedules} = SchedulerManager.list_agent_schedules(test_agent_pid)
      schedule = hd(schedules)
      assert schedule.interval == 2000

      # Clean up
      send(test_agent_pid, :stop)
    end

    test "handles agent registration correctly" do
      test_agent_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          after
            5000 -> :timeout
          end
        end)

      initial_stats = SchedulerManager.get_stats()

      # Register first schedule
      assert :ok =
               SchedulerManager.register_periodic(
                 test_agent_pid,
                 :schedule1,
                 1000,
                 :message1
               )

      # Register second schedule for same agent
      assert :ok =
               SchedulerManager.register_periodic(
                 test_agent_pid,
                 :schedule2,
                 2000,
                 :message2
               )

      # Check stats - should have one more agent and two more schedules
      new_stats = SchedulerManager.get_stats()
      assert new_stats.active_agents >= initial_stats.active_agents + 1
      assert new_stats.total_schedules >= initial_stats.total_schedules + 2

      # List schedules
      assert {:ok, schedules} = SchedulerManager.list_agent_schedules(test_agent_pid)
      assert length(schedules) == 2

      # Unregister entire agent
      assert :ok = SchedulerManager.unregister_agent(test_agent_pid)

      # Should be cleaned up
      assert {:error, :not_found} = SchedulerManager.list_agent_schedules(test_agent_pid)

      # Clean up
      send(test_agent_pid, :stop)
    end
  end

  describe "error handling" do
    test "returns error for non-existent schedules" do
      test_agent_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          after
            1000 -> :timeout
          end
        end)

      # Try to unregister non-existent schedule
      assert {:error, :not_found} =
               SchedulerManager.unregister_periodic(test_agent_pid, :nonexistent)

      # Try to force execution of non-existent schedule
      assert {:error, :not_found} = SchedulerManager.force_execution(test_agent_pid, :nonexistent)

      # Try to update interval of non-existent schedule
      assert {:error, :not_found} =
               SchedulerManager.update_interval(test_agent_pid, :nonexistent, 1000)

      # Try to list schedules for agent with no schedules
      assert {:error, :not_found} = SchedulerManager.list_agent_schedules(test_agent_pid)

      send(test_agent_pid, :stop)
    end

    test "returns error for dead agent registration" do
      # Create and kill a process
      test_agent_pid = spawn(fn -> :ok end)
      # Ensure it's dead
      wait_for(
        fn ->
          if Process.alive?(test_agent_pid), do: nil, else: true
        end,
        1000
      )

      # Try to register schedule for dead agent
      assert {:error, :agent_not_alive} =
               SchedulerManager.register_periodic(
                 test_agent_pid,
                 :dead_schedule,
                 1000,
                 :message
               )
    end
  end
end
