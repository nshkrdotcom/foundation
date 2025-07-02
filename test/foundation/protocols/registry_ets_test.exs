defmodule Foundation.Protocols.RegistryETSTest do
  use ExUnit.Case, async: false
  alias Foundation.Protocols.RegistryETS

  setup do
    # Stop any existing GenServer
    case Process.whereis(RegistryETS) do
      nil ->
        :ok

      pid ->
        GenServer.stop(pid, :normal)
        # Wait for it to stop
        Process.sleep(10)
    end

    # Start fresh GenServer
    {:ok, _pid} = RegistryETS.start_link()

    # Give it time to initialize tables
    Process.sleep(20)

    :ok
  end

  describe "register_agent/3" do
    test "registers a new agent successfully" do
      pid = self()
      assert :ok = RegistryETS.register_agent(:test_agent, pid)
      assert {:ok, ^pid} = RegistryETS.get_agent(:test_agent)
    end

    test "registers agent with metadata" do
      pid = self()
      metadata = %{capability: :inference, status: :active}
      assert :ok = RegistryETS.register_agent(:test_agent, pid, metadata)

      assert {:ok, {^pid, ^metadata}} = RegistryETS.get_agent_with_metadata(:test_agent)
    end

    test "replaces existing registration" do
      old_pid = spawn(fn -> Process.sleep(100) end)
      new_pid = self()

      assert :ok = RegistryETS.register_agent(:test_agent, old_pid)
      assert :ok = RegistryETS.register_agent(:test_agent, new_pid)

      assert {:ok, ^new_pid} = RegistryETS.get_agent(:test_agent)
    end

    test "monitors registered processes" do
      # Spawn a process that we control
      test_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      assert :ok = RegistryETS.register_agent(:monitored_agent, test_pid)
      assert {:ok, ^test_pid} = RegistryETS.get_agent(:monitored_agent)

      # Kill the process
      Process.exit(test_pid, :kill)

      # Give the monitor time to clean up
      Process.sleep(50)

      # Agent should be automatically cleaned up
      assert {:error, :not_found} = RegistryETS.get_agent(:monitored_agent)
    end
  end

  describe "get_agent/1" do
    test "returns {:ok, pid} for registered agent" do
      pid = self()
      RegistryETS.register_agent(:test_agent, pid)

      assert {:ok, ^pid} = RegistryETS.get_agent(:test_agent)
    end

    test "returns {:error, :not_found} for unknown agent" do
      assert {:error, :not_found} = RegistryETS.get_agent(:unknown_agent)
    end

    test "cleans up and returns error for dead process" do
      # Create a process that dies immediately
      pid = spawn(fn -> :ok end)
      # Ensure process is dead
      Process.sleep(10)

      # Manually insert into ETS to simulate a dead process that wasn't cleaned up
      :ets.insert(:foundation_agent_registry_ets, {:dead_agent, pid, %{}, make_ref()})

      assert {:error, :not_found} = RegistryETS.get_agent(:dead_agent)

      # Verify it was cleaned up
      assert [] = :ets.lookup(:foundation_agent_registry_ets, :dead_agent)
    end
  end

  describe "list_agents/0" do
    test "returns empty list when no agents registered" do
      assert [] = RegistryETS.list_agents()
    end

    test "returns all alive agents" do
      pid1 = self()
      pid2 = spawn(fn -> Process.sleep(100) end)

      RegistryETS.register_agent(:agent1, pid1)
      RegistryETS.register_agent(:agent2, pid2)

      agents = RegistryETS.list_agents()
      assert length(agents) == 2
      assert Enum.any?(agents, fn {id, pid} -> id == :agent1 && pid == pid1 end)
      assert Enum.any?(agents, fn {id, pid} -> id == :agent2 && pid == pid2 end)

      # Clean up
      Process.exit(pid2, :kill)
    end

    test "filters out dead processes" do
      alive_pid = self()
      dead_pid = spawn(fn -> :ok end)
      # Ensure dead_pid is dead
      Process.sleep(10)

      RegistryETS.register_agent(:alive_agent, alive_pid)

      # Manually insert dead process
      :ets.insert(:foundation_agent_registry_ets, {:dead_agent, dead_pid, %{}, make_ref()})

      agents = RegistryETS.list_agents()
      assert length(agents) == 1
      assert Enum.any?(agents, fn {id, pid} -> id == :alive_agent && pid == alive_pid end)
      refute Enum.any?(agents, fn {id, pid} -> id == :dead_agent && pid == dead_pid end)
    end
  end

  describe "unregister_agent/1" do
    test "unregisters existing agent" do
      pid = self()
      RegistryETS.register_agent(:test_agent, pid)

      assert :ok = RegistryETS.unregister_agent(:test_agent)
      assert {:error, :not_found} = RegistryETS.get_agent(:test_agent)
    end

    test "returns :ok for non-existent agent" do
      assert :ok = RegistryETS.unregister_agent(:non_existent)
    end

    test "properly demonitors unregistered process" do
      pid = spawn(fn -> Process.sleep(100) end)
      RegistryETS.register_agent(:test_agent, pid)

      # Get monitor count before
      {:monitors, monitors_before} = Process.info(Process.whereis(RegistryETS), :monitors)
      initial_count = length(monitors_before)

      # Unregister
      assert :ok = RegistryETS.unregister_agent(:test_agent)

      # Get monitor count after
      {:monitors, monitors_after} = Process.info(Process.whereis(RegistryETS), :monitors)
      final_count = length(monitors_after)

      # Should have one less monitor
      assert final_count == initial_count - 1

      # Clean up
      Process.exit(pid, :kill)
    end
  end

  describe "update_metadata/2" do
    test "updates metadata for existing agent" do
      pid = self()
      initial_metadata = %{status: :active}
      RegistryETS.register_agent(:test_agent, pid, initial_metadata)

      new_metadata = %{status: :idle, updated: true}
      assert :ok = RegistryETS.update_metadata(:test_agent, new_metadata)

      assert {:ok, {^pid, ^new_metadata}} = RegistryETS.get_agent_with_metadata(:test_agent)
    end

    test "returns error for non-existent agent" do
      assert {:error, :not_found} = RegistryETS.update_metadata(:unknown, %{})
    end
  end

  describe "process monitoring" do
    test "multiple agents cleaned up when processes die" do
      # Create multiple processes
      pids =
        for _i <- 1..5 do
          spawn(fn ->
            receive do
              :stop -> :ok
            end
          end)
        end

      # Register them all
      for {pid, i} <- Enum.with_index(pids) do
        RegistryETS.register_agent(:"agent_#{i}", pid)
      end

      # Verify all registered
      assert length(RegistryETS.list_agents()) == 5

      # Kill all processes
      for pid <- pids do
        Process.exit(pid, :kill)
      end

      # Wait for cleanup
      Process.sleep(100)

      # All should be cleaned up
      assert [] = RegistryETS.list_agents()
    end

    test "no monitor leaks after many registrations" do
      genserver_pid = Process.whereis(RegistryETS)

      # Get initial monitor count
      {:monitors, initial_monitors} = Process.info(genserver_pid, :monitors)
      initial_count = length(initial_monitors)

      # Register and unregister many times
      for i <- 1..50 do
        pid = spawn(fn -> Process.sleep(10) end)
        RegistryETS.register_agent(:"temp_agent_#{i}", pid)
        RegistryETS.unregister_agent(:"temp_agent_#{i}")
        Process.exit(pid, :kill)
      end

      # Allow cleanup
      Process.sleep(100)

      # Check final monitor count
      {:monitors, final_monitors} = Process.info(genserver_pid, :monitors)
      final_count = length(final_monitors)

      # Should be back to initial count (no leaks)
      assert final_count == initial_count
    end
  end

  describe "concurrent operations" do
    test "handles concurrent registrations" do
      # Spawn multiple processes that register agents concurrently
      parent = self()

      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            # Use a stable process for registration
            RegistryETS.register_agent(:"concurrent_#{i}", parent)
          end)
        end

      # Wait for all to complete
      Enum.each(tasks, &Task.await/1)

      # Verify all registered
      agents = RegistryETS.list_agents()
      assert length(agents) == 10
    end

    test "handles concurrent reads and writes" do
      parent = self()

      # Register initial agents
      for i <- 1..5 do
        RegistryETS.register_agent(:"agent_#{i}", parent)
      end

      # Concurrent operations
      tasks = [
        # Readers
        Task.async(fn ->
          for _ <- 1..100 do
            RegistryETS.list_agents()
            RegistryETS.get_agent(:agent_1)
          end
        end),
        # Writers
        Task.async(fn ->
          for i <- 6..15 do
            RegistryETS.register_agent(:"new_agent_#{i}", parent)
          end
        end),
        # Updaters
        Task.async(fn ->
          for i <- 1..5 do
            RegistryETS.update_metadata(:"agent_#{i}", %{updated: true})
          end
        end)
      ]

      # Wait for completion
      Enum.each(tasks, &Task.await/1)

      # Verify state is consistent
      agents = RegistryETS.list_agents()
      assert length(agents) >= 10
    end
  end
end
