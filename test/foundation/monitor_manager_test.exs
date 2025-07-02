defmodule Foundation.MonitorManagerTest do
  use ExUnit.Case, async: false
  
  alias Foundation.MonitorManager
  
  # Test helper modules
  defmodule TestServer do
    use GenServer
    
    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts)
    end
    
    def init(opts) do
      state = %{
        behavior: Keyword.get(opts, :behavior, :normal),
        messages: []
      }
      {:ok, state}
    end
    
    def handle_call(:ping, _from, state) do
      {:reply, :pong, state}
    end
    
    def handle_call(:get_messages, _from, state) do
      {:reply, state.messages, state}
    end
    
    def handle_cast({:add_message, msg}, state) do
      new_messages = [msg | state.messages]
      {:noreply, %{state | messages: new_messages}}
    end
    
    def handle_info(msg, state) do
      new_messages = [msg | state.messages]
      {:noreply, %{state | messages: new_messages}}
    end
  end
  
  setup do
    # Configure test mode for MonitorManager notifications
    Application.put_env(:foundation, :test_mode, true)
    Application.put_env(:foundation, :test_pid, self())
    
    # Start MonitorManager for testing
    {:ok, manager_pid} = MonitorManager.start_link(name: :test_monitor_manager)
    
    on_exit(fn ->
      # Clean up test mode configuration
      Application.delete_env(:foundation, :test_mode)
      Application.delete_env(:foundation, :test_pid)
      
      # Stop the manager if still running
      if Process.alive?(manager_pid) do
        GenServer.stop(manager_pid)
      end
    end)
    
    %{manager_pid: manager_pid}
  end
  
  describe "MonitorManager.monitor/2" do
    test "successfully monitors a live process" do
      {:ok, target_pid} = TestServer.start_link()
      
      assert {:ok, ref} = MonitorManager.monitor(target_pid, :test_monitor)
      assert is_reference(ref)
      
      # Verify monitor is tracked
      monitors = MonitorManager.list_monitors()
      assert Enum.any?(monitors, fn m -> m.ref == ref and m.tag == :test_monitor end)
      
      # Verify test notification
      assert_receive {:monitor_manager, :monitor_created, %{ref: ^ref, tag: :test_monitor}}, 1000
      
      # Clean up
      :ok = MonitorManager.demonitor(ref)
      GenServer.stop(target_pid)
    end
    
    test "fails to monitor dead process" do
      # Create and immediately kill a process
      {:ok, target_pid} = TestServer.start_link()
      GenServer.stop(target_pid)
      
      # Wait for process to be completely dead
      wait_for_process_death(target_pid)
      
      assert {:error, :noproc} = MonitorManager.monitor(target_pid, :dead_process)
    end
    
    test "handles MonitorManager unavailable gracefully" do
      # Stop the manager
      GenServer.stop(:test_monitor_manager)
      
      {:ok, target_pid} = TestServer.start_link()
      
      assert {:error, :monitor_manager_unavailable} = MonitorManager.monitor(target_pid, :unavailable)
      
      GenServer.stop(target_pid)
    end
    
    test "supports different tag types" do
      {:ok, target_pid} = TestServer.start_link()
      
      # Test atom tag
      assert {:ok, ref1} = MonitorManager.monitor(target_pid, :atom_tag)
      
      # Test string tag  
      assert {:ok, ref2} = MonitorManager.monitor(target_pid, "string_tag")
      
      monitors = MonitorManager.list_monitors()
      assert Enum.any?(monitors, fn m -> m.tag == :atom_tag end)
      assert Enum.any?(monitors, fn m -> m.tag == "string_tag" end)
      
      # Clean up
      MonitorManager.demonitor(ref1)
      MonitorManager.demonitor(ref2)
      GenServer.stop(target_pid)
    end
  end
  
  describe "MonitorManager.demonitor/1" do
    test "successfully removes tracked monitor" do
      {:ok, target_pid} = TestServer.start_link()
      {:ok, ref} = MonitorManager.monitor(target_pid, :test_demonitor)
      
      # Verify monitor exists
      monitors = MonitorManager.list_monitors()
      assert Enum.any?(monitors, fn m -> m.ref == ref end)
      
      # Demonitor
      assert :ok = MonitorManager.demonitor(ref)
      
      # Verify test notification
      assert_receive {:monitor_manager, :monitor_cleaned, %{ref: ^ref, tag: :test_demonitor}}, 1000
      
      # Verify monitor is gone
      monitors = MonitorManager.list_monitors()
      assert not Enum.any?(monitors, fn m -> m.ref == ref end)
      
      GenServer.stop(target_pid)
    end
    
    test "handles unknown monitor reference" do
      fake_ref = make_ref()
      assert {:error, :not_found} = MonitorManager.demonitor(fake_ref)
    end
    
    test "handles MonitorManager unavailable" do
      {:ok, target_pid} = TestServer.start_link()
      {:ok, ref} = MonitorManager.monitor(target_pid, :test)
      
      # Stop manager
      GenServer.stop(:test_monitor_manager)
      
      assert {:error, :monitor_manager_unavailable} = MonitorManager.demonitor(ref)
      
      GenServer.stop(target_pid)
    end
  end
  
  describe "automatic cleanup on process death" do
    test "cleans up monitor when monitored process dies" do
      {:ok, target_pid} = TestServer.start_link()
      {:ok, ref} = MonitorManager.monitor(target_pid, :auto_cleanup_target)
      
      # Verify monitor exists
      monitors = MonitorManager.list_monitors()
      assert Enum.any?(monitors, fn m -> m.ref == ref end)
      
      # Kill the monitored process
      GenServer.stop(target_pid)
      
      # Wait for automatic cleanup notification
      assert_receive {:monitor_manager, :automatic_cleanup, %{ref: ^ref, tag: :auto_cleanup_target}}, 2000
      
      # Verify monitor is cleaned up
      wait_for_cleanup(ref)
    end
    
    test "cleans up monitors when caller process dies" do
      {:ok, target_pid} = TestServer.start_link()
      
      # Create monitor from a separate process
      {caller_pid, ref} = spawn_monitor_creator(target_pid)
      
      # Wait for monitor to be created
      wait_for_monitor_creation(ref)
      
      # Kill the caller process
      Process.exit(caller_pid, :kill)
      
      # Wait for caller cleanup notification
      assert_receive {:monitor_manager, :caller_cleanup, %{caller: ^caller_pid, count: 1}}, 2000
      
      # Verify monitor is cleaned up
      wait_for_cleanup(ref)
      
      GenServer.stop(target_pid)
    end
    
    test "cleans up multiple monitors from same caller" do
      targets = for _i <- 1..3, do: elem(TestServer.start_link(), 1)
      
      # Create multiple monitors from separate process
      {caller_pid, refs} = spawn_multiple_monitor_creator(targets)
      
      # Wait for all monitors to be created
      Enum.each(refs, &wait_for_monitor_creation/1)
      
      # Kill the caller
      Process.exit(caller_pid, :kill)
      
      # Wait for caller cleanup
      assert_receive {:monitor_manager, :caller_cleanup, %{caller: ^caller_pid, count: 3}}, 2000
      
      # Verify all monitors are cleaned up
      Enum.each(refs, &wait_for_cleanup/1)
      
      Enum.each(targets, &GenServer.stop/1)
    end
  end
  
  describe "MonitorManager.list_monitors/0" do
    test "returns empty list when no monitors" do
      assert [] = MonitorManager.list_monitors()
    end
    
    test "returns monitor details with metadata" do
      {:ok, target_pid} = TestServer.start_link()
      {:ok, ref} = MonitorManager.monitor(target_pid, :list_test)
      
      monitors = MonitorManager.list_monitors()
      
      assert [monitor] = monitors
      assert monitor.ref == ref
      assert monitor.pid == target_pid
      assert monitor.tag == :list_test
      assert monitor.caller == self()
      assert is_integer(monitor.age_ms)
      assert monitor.alive == true
      assert is_list(monitor.stack_trace)
      
      MonitorManager.demonitor(ref)
      GenServer.stop(target_pid)
    end
    
    test "shows correct alive status" do
      {:ok, target_pid} = TestServer.start_link()
      {:ok, _ref} = MonitorManager.monitor(target_pid, :alive_test)
      
      # Initially alive
      monitors = MonitorManager.list_monitors()
      [monitor] = monitors
      assert monitor.alive == true
      
      # Kill process but don't wait for cleanup
      GenServer.stop(target_pid)
      Process.sleep(50)  # Small delay to ensure process is dead
      
      # Check again - should show as dead if checked before automatic cleanup
      monitors = MonitorManager.list_monitors()
      if length(monitors) > 0 do
        [monitor] = monitors
        assert monitor.alive == false
      end
    end
  end
  
  describe "MonitorManager.get_stats/0" do
    test "tracks creation and cleanup statistics" do
      initial_stats = MonitorManager.get_stats()
      
      {:ok, target_pid} = TestServer.start_link()
      {:ok, ref} = MonitorManager.monitor(target_pid, :stats_test)
      
      # Check stats after creation
      stats_after_create = MonitorManager.get_stats()
      assert stats_after_create.created > initial_stats.created
      assert stats_after_create.active == 1
      
      # Clean up and check stats
      MonitorManager.demonitor(ref)
      
      stats_after_cleanup = MonitorManager.get_stats()
      assert stats_after_cleanup.cleaned > initial_stats.cleaned
      assert stats_after_cleanup.active == 0
      
      GenServer.stop(target_pid)
    end
    
    test "handles MonitorManager unavailable" do
      GenServer.stop(:test_monitor_manager)
      
      stats = MonitorManager.get_stats()
      assert stats == %{created: 0, cleaned: 0, leaked: 0, active: 0}
    end
  end
  
  describe "MonitorManager.find_leaks/1" do
    test "detects no leaks initially" do
      leaks = MonitorManager.find_leaks(0)
      assert [] = leaks
    end
    
    test "detects potential leaks based on age" do
      {:ok, target_pid} = TestServer.start_link()
      {:ok, ref} = MonitorManager.monitor(target_pid, :leak_test)
      
      # Immediately check for leaks (age 0) - should find the monitor
      leaks = MonitorManager.find_leaks(0)
      assert [leak] = leaks
      assert leak.ref == ref
      assert leak.tag == :leak_test
      assert is_integer(leak.age_ms)
      
      # Check with high age threshold - should find nothing
      leaks = MonitorManager.find_leaks(:timer.hours(1))
      assert [] = leaks
      
      MonitorManager.demonitor(ref)
      GenServer.stop(target_pid)
    end
    
    test "ignores dead processes in leak detection" do
      {:ok, target_pid} = TestServer.start_link()
      {:ok, ref} = MonitorManager.monitor(target_pid, :dead_leak_test)
      
      # Kill the target process
      GenServer.stop(target_pid)
      
      # Wait for cleanup
      wait_for_cleanup(ref)
      
      # Should not detect as leak since monitor was cleaned up
      leaks = MonitorManager.find_leaks(0)
      assert not Enum.any?(leaks, fn l -> l.ref == ref end)
    end
    
    test "handles MonitorManager unavailable" do
      GenServer.stop(:test_monitor_manager)
      
      leaks = MonitorManager.find_leaks()
      assert [] = leaks
    end
  end
  
  describe "automatic leak detection" do
    test "periodic leak detection logs warnings" do
      {:ok, target_pid} = TestServer.start_link()
      {:ok, ref} = MonitorManager.monitor(target_pid, :periodic_leak_test)
      
      # Trigger leak detection manually (simulate periodic check)
      send(:test_monitor_manager, :check_for_leaks)
      
      # Should receive leak detection notification since age threshold is small
      assert_receive {:monitor_manager, :leaks_detected, %{count: count}}, 2000
      assert count >= 1
      
      MonitorManager.demonitor(ref)
      GenServer.stop(target_pid)
    end
  end
  
  describe "error handling and edge cases" do
    test "handles unexpected messages gracefully" do
      # Send unexpected message to MonitorManager
      send(:test_monitor_manager, {:unexpected, :message})
      
      # MonitorManager should continue working
      {:ok, target_pid} = TestServer.start_link()
      {:ok, ref} = MonitorManager.monitor(target_pid, :after_unexpected)
      
      assert is_reference(ref)
      
      MonitorManager.demonitor(ref)
      GenServer.stop(target_pid)
    end
    
    test "handles monitor creation during shutdown" do
      {:ok, target_pid} = TestServer.start_link()
      
      # Start shutdown process
      GenServer.stop(:test_monitor_manager)
      
      # Try to create monitor - should fail gracefully
      assert {:error, :monitor_manager_unavailable} = MonitorManager.monitor(target_pid, :during_shutdown)
      
      GenServer.stop(target_pid)
    end
    
    test "stack trace capture works" do
      {:ok, target_pid} = TestServer.start_link()
      {:ok, ref} = MonitorManager.monitor(target_pid, :stack_trace_test)
      
      monitors = MonitorManager.list_monitors()
      [monitor] = monitors
      
      assert is_list(monitor.stack_trace)
      assert length(monitor.stack_trace) > 0
      
      # Should contain this test module in stack trace
      assert Enum.any?(monitor.stack_trace, fn frame ->
        String.contains?(frame, "MonitorManagerTest") or String.contains?(frame, "Foundation.MonitorManager")
      end)
      
      MonitorManager.demonitor(ref)
      GenServer.stop(target_pid)
    end
  end
  
  describe "concurrency and stress testing" do
    test "handles concurrent monitor operations" do
      target_pids = for _i <- 1..10, do: elem(TestServer.start_link(), 1)
      
      # Create monitors concurrently
      tasks = Enum.map(target_pids, fn pid ->
        Task.async(fn ->
          MonitorManager.monitor(pid, :concurrent_test)
        end)
      end)
      
      refs = Enum.map(tasks, fn task ->
        {:ok, ref} = Task.await(task)
        ref
      end)
      
      # Wait for all monitor creation notifications
      for _ <- 1..10 do
        assert_receive {:monitor_manager, :monitor_created, _}, 2000
      end
      
      # Verify all monitors were created
      monitors = MonitorManager.list_monitors()
      assert length(monitors) == 10
      
      # Clean up concurrently
      cleanup_tasks = Enum.map(refs, fn ref ->
        Task.async(fn ->
          MonitorManager.demonitor(ref)
        end)
      end)
      
      Enum.each(cleanup_tasks, &Task.await/1)
      
      # Verify all cleaned up
      wait_for_all_cleanup()
      
      Enum.each(target_pids, &GenServer.stop/1)
    end
    
    test "handles rapid monitor create/destroy cycles" do
      {:ok, target_pid} = TestServer.start_link()
      
      # Rapid create/destroy cycle
      for _i <- 1..50 do
        {:ok, ref} = MonitorManager.monitor(target_pid, :rapid_cycle)
        :ok = MonitorManager.demonitor(ref)
      end
      
      # Should have no active monitors
      monitors = MonitorManager.list_monitors()
      assert [] = monitors
      
      GenServer.stop(target_pid)
    end
  end
  
  # Test helper functions following OTP async patterns
  
  defp wait_for_process_death(pid) do
    ref = Process.monitor(pid)
    receive do
      {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
    after
      5000 -> flunk("Process did not die within timeout")
    end
  end
  
  defp wait_for_cleanup(ref) do
    # Poll until monitor is no longer in the list
    wait_for_condition(fn ->
      monitors = MonitorManager.list_monitors()
      not Enum.any?(monitors, fn m -> m.ref == ref end)
    end, "Monitor was not cleaned up")
  end
  
  defp wait_for_all_cleanup do
    wait_for_condition(fn ->
      monitors = MonitorManager.list_monitors()
      length(monitors) == 0
    end, "Not all monitors were cleaned up")
  end
  
  defp wait_for_monitor_creation(ref) do
    wait_for_condition(fn ->
      monitors = MonitorManager.list_monitors()
      Enum.any?(monitors, fn m -> m.ref == ref end)
    end, "Monitor was not created")
  end
  
  defp wait_for_condition(condition_fun, error_msg) do
    wait_for_condition(condition_fun, error_msg, 0)
  end
  
  defp wait_for_condition(condition_fun, error_msg, attempt) when attempt < 50 do
    if condition_fun.() do
      :ok
    else
      Process.sleep(10)
      wait_for_condition(condition_fun, error_msg, attempt + 1)
    end
  end
  
  defp wait_for_condition(_condition_fun, error_msg, _attempt) do
    flunk(error_msg)
  end
  
  defp spawn_monitor_creator(target_pid) do
    test_pid = self()
    
    caller_pid = spawn(fn ->
      {:ok, ref} = MonitorManager.monitor(target_pid, :caller_test)
      send(test_pid, {:monitor_created, ref})
      Process.sleep(:infinity)
    end)
    
    ref = receive do
      {:monitor_created, ref} -> ref
    after
      5000 -> flunk("Monitor was not created within timeout")
    end
    
    {caller_pid, ref}
  end
  
  defp spawn_multiple_monitor_creator(target_pids) do
    test_pid = self()
    
    caller_pid = spawn(fn ->
      refs = Enum.map(target_pids, fn pid ->
        {:ok, ref} = MonitorManager.monitor(pid, :multiple_caller_test)
        ref
      end)
      send(test_pid, {:monitors_created, refs})
      Process.sleep(:infinity)
    end)
    
    receive do
      {:monitors_created, refs} -> {caller_pid, refs}
    after
      5000 -> flunk("Multiple monitors were not created within timeout")
    end
  end
  
end