defmodule Foundation.BEAM.EcosystemSupervisorTest do
  use ExUnit.Case, async: false

  alias Foundation.BEAM.EcosystemSupervisor
  alias Foundation.TestHelpers

  describe "EcosystemSupervisor - OTP-based ecosystem management" do
    test "starts with proper supervision tree" do
      config = %{
        id: :test_ecosystem_1,
        coordinator: Foundation.BEAM.EcosystemSupervisorTest.TestCoordinator,
        workers: {Foundation.BEAM.EcosystemSupervisorTest.TestWorker, count: 3}
      }

      # Start the ecosystem supervisor
      {:ok, supervisor_pid} = EcosystemSupervisor.start_link(config)

      # Verify it's a proper supervisor
      assert Process.alive?(supervisor_pid)

      # Wait for initial workers to start using proper monitoring
      TestHelpers.assert_eventually(
        fn ->
          children = Supervisor.which_children(supervisor_pid)
          # At least coordinator + worker supervisor
          length(children) >= 2
        end,
        1000
      )

      # Verify it supervises the correct processes
      children = Supervisor.which_children(supervisor_pid)
      # At least coordinator + worker supervisor
      assert length(children) >= 2

      # Cleanup
      Supervisor.stop(supervisor_pid)
    end

    test "restarts crashed coordinator automatically" do
      config = %{
        id: :test_ecosystem_2,
        coordinator: Foundation.BEAM.EcosystemSupervisorTest.TestCoordinator,
        workers: {Foundation.BEAM.EcosystemSupervisorTest.TestWorker, count: 2}
      }

      {:ok, supervisor_pid} = EcosystemSupervisor.start_link(config)

      # Get initial coordinator
      {:ok, original_coordinator} = EcosystemSupervisor.get_coordinator(supervisor_pid)
      assert Process.alive?(original_coordinator)

      # Kill the coordinator
      Process.exit(original_coordinator, :kill)

      # Wait for supervisor to restart it
      TestHelpers.assert_eventually(
        fn ->
          case EcosystemSupervisor.get_coordinator(supervisor_pid) do
            {:ok, new_coordinator} ->
              Process.alive?(new_coordinator) and new_coordinator != original_coordinator

            _ ->
              false
          end
        end,
        1000
      )

      Supervisor.stop(supervisor_pid)
    end

    test "adds workers dynamically" do
      config = %{
        id: :test_ecosystem_3,
        coordinator: Foundation.BEAM.EcosystemSupervisorTest.TestCoordinator,
        workers: {Foundation.BEAM.EcosystemSupervisorTest.TestWorker, count: 2}
      }

      {:ok, supervisor_pid} = EcosystemSupervisor.start_link(config)

      # Add a new worker
      {:ok, worker_pid} =
        EcosystemSupervisor.add_worker(
          supervisor_pid,
          Foundation.BEAM.EcosystemSupervisorTest.TestWorker,
          []
        )

      assert Process.alive?(worker_pid)

      # Verify it's supervised
      children = EcosystemSupervisor.list_workers(supervisor_pid)
      assert worker_pid in children

      Supervisor.stop(supervisor_pid)
    end

    test "removes workers cleanly" do
      config = %{
        id: :test_ecosystem_4,
        coordinator: Foundation.BEAM.EcosystemSupervisorTest.TestCoordinator,
        workers: {Foundation.BEAM.EcosystemSupervisorTest.TestWorker, count: 2}
      }

      {:ok, supervisor_pid} = EcosystemSupervisor.start_link(config)

      # Add a dynamic worker (since static workers can't be removed)
      {:ok, worker_to_remove} =
        EcosystemSupervisor.add_worker(
          supervisor_pid,
          Foundation.BEAM.EcosystemSupervisorTest.TestWorker,
          []
        )

      assert Process.alive?(worker_to_remove)

      # Verify it's in the worker list
      workers = EcosystemSupervisor.list_workers(supervisor_pid)
      assert worker_to_remove in workers

      # Remove the dynamic worker
      :ok = EcosystemSupervisor.remove_worker(supervisor_pid, worker_to_remove)

      # Verify it's gone
      TestHelpers.assert_eventually(
        fn ->
          not Process.alive?(worker_to_remove)
        end,
        500
      )

      updated_workers = EcosystemSupervisor.list_workers(supervisor_pid)
      assert worker_to_remove not in updated_workers

      Supervisor.stop(supervisor_pid)
    end

    test "provides ecosystem info without manual tracking" do
      config = %{
        id: :test_ecosystem_5,
        coordinator: Foundation.BEAM.EcosystemSupervisorTest.TestCoordinator,
        workers: {Foundation.BEAM.EcosystemSupervisorTest.TestWorker, count: 4}
      }

      {:ok, supervisor_pid} = EcosystemSupervisor.start_link(config)

      # Wait for initial workers to start using proper monitoring
      TestHelpers.assert_eventually(
        fn ->
          {:ok, info} = EcosystemSupervisor.get_ecosystem_info(supervisor_pid)
          # coordinator + 4 workers
          info.total_processes == 5
        end,
        2000
      )

      {:ok, info} = EcosystemSupervisor.get_ecosystem_info(supervisor_pid)

      # Should have coordinator + 4 workers
      assert info.total_processes == 5
      assert is_pid(info.coordinator.pid)
      assert length(info.workers) == 4
      assert is_number(info.total_memory)

      # All processes should be alive
      assert Process.alive?(info.coordinator.pid)
      assert Enum.all?(info.workers, fn worker -> Process.alive?(worker.pid) end)

      Supervisor.stop(supervisor_pid)
    end

    test "handles graceful shutdown" do
      config = %{
        id: :test_ecosystem_6,
        coordinator: Foundation.BEAM.EcosystemSupervisorTest.TestCoordinator,
        workers: {Foundation.BEAM.EcosystemSupervisorTest.TestWorker, count: 3}
      }

      {:ok, supervisor_pid} = EcosystemSupervisor.start_link(config)

      # Get all processes
      {:ok, info} = EcosystemSupervisor.get_ecosystem_info(supervisor_pid)
      all_pids = [info.coordinator.pid | Enum.map(info.workers, & &1.pid)]

      # Shutdown gracefully
      :ok = EcosystemSupervisor.shutdown(supervisor_pid)

      # All processes should be dead
      TestHelpers.assert_eventually(
        fn ->
          Enum.all?(all_pids, fn pid -> not Process.alive?(pid) end)
        end,
        1000
      )

      # Supervisor itself should be dead
      assert not Process.alive?(supervisor_pid)
    end

    test "integrates with ProcessRegistry" do
      config = %{
        id: :test_ecosystem_7,
        coordinator: Foundation.BEAM.EcosystemSupervisorTest.TestCoordinator,
        workers: {Foundation.BEAM.EcosystemSupervisorTest.TestWorker, count: 2}
      }

      {:ok, supervisor_pid} = EcosystemSupervisor.start_link(config)

      # Should be registered in ProcessRegistry
      assert {:ok, ^supervisor_pid} =
               Foundation.ProcessRegistry.lookup(
                 :production,
                 {:ecosystem_supervisor, :test_ecosystem_7}
               )

      Supervisor.stop(supervisor_pid)

      # Should be unregistered after shutdown
      assert :error =
               Foundation.ProcessRegistry.lookup(
                 :production,
                 {:ecosystem_supervisor, :test_ecosystem_7}
               )
    end
  end

  describe "compatibility with existing interface" do
    test "spawn_ecosystem delegates to EcosystemSupervisor" do
      config = %{
        coordinator: Foundation.BEAM.EcosystemSupervisorTest.TestCoordinator,
        workers: {Foundation.BEAM.EcosystemSupervisorTest.TestWorker, count: 3}
      }

      # This should still work but use the new supervisor underneath
      {:ok, ecosystem} = Foundation.BEAM.Processes.spawn_ecosystem(config)

      # Should have supervisor field pointing to the supervisor
      assert is_pid(ecosystem.supervisor)
      assert Process.alive?(ecosystem.supervisor)

      # Should still have coordinator and workers for compatibility
      assert is_pid(ecosystem.coordinator)
      assert length(ecosystem.workers) == 3

      # Cleanup using new shutdown
      :ok = Foundation.BEAM.Processes.shutdown_ecosystem(ecosystem)
    end
  end

  # Test modules
  defmodule TestCoordinator do
    use GenServer

    def start_link(args) do
      GenServer.start_link(__MODULE__, args)
    end

    def init(_args) do
      {:ok, %{}}
    end

    def handle_info(_msg, state) do
      {:noreply, state}
    end
  end

  defmodule TestWorker do
    use GenServer

    def start_link(args) do
      GenServer.start_link(__MODULE__, args)
    end

    def init(_args) do
      {:ok, %{}}
    end

    def handle_info(_msg, state) do
      {:noreply, state}
    end
  end
end
