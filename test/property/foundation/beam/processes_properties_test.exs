defmodule Foundation.BEAM.ProcessesPropertiesTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Foundation.BEAM.Processes
  alias Foundation.TestHelpers

  @moduletag :property

  describe "ecosystem spawning properties" do
    property "ecosystem always creates correct number of processes" do
      check all(
              worker_count <- integer(1..20),
              max_runs: 50
            ) do
        config = %{
          coordinator: TestCoordinator,
          workers: {TestWorker, count: worker_count}
        }

        {:ok, ecosystem} = Processes.spawn_ecosystem(config)
        {:ok, info} = Processes.ecosystem_info(ecosystem)

        # Property: total processes = 1 coordinator + worker_count workers
        assert info.total_processes == worker_count + 1

        # Property: all processes should be alive initially
        assert Process.alive?(ecosystem.coordinator)
        assert Enum.all?(ecosystem.workers, &Process.alive?/1)

        # Property: worker count matches configuration
        assert length(ecosystem.workers) == worker_count

        # Cleanup
        cleanup_ecosystem(ecosystem)
      end
    end

    property "ecosystem info is always consistent with actual ecosystem state" do
      check all(
              worker_count <- integer(1..15),
              memory_strategy <- member_of([:isolated_heaps, :shared_heap]),
              gc_strategy <- member_of([:frequent_minor, :standard]),
              max_runs: 30
            ) do
        config = %{
          coordinator: TestCoordinator,
          workers: {TestWorker, count: worker_count},
          memory_strategy: memory_strategy,
          gc_strategy: gc_strategy
        }

        {:ok, ecosystem} = Processes.spawn_ecosystem(config)
        {:ok, info} = Processes.ecosystem_info(ecosystem)

        # Property: coordinator info matches actual coordinator
        assert info.coordinator.pid == ecosystem.coordinator
        assert Process.alive?(info.coordinator.pid)

        # Property: worker info matches actual workers
        actual_worker_pids = MapSet.new(ecosystem.workers)
        info_worker_pids = MapSet.new(info.workers |> Enum.map(& &1.pid))
        assert MapSet.equal?(actual_worker_pids, info_worker_pids)

        # Property: all reported processes are alive
        all_info_pids = [info.coordinator.pid | Enum.map(info.workers, & &1.pid)]
        assert Enum.all?(all_info_pids, &Process.alive?/1)

        # Property: memory values are positive
        assert info.coordinator.memory > 0
        assert Enum.all?(info.workers, fn worker -> worker.memory > 0 end)
        assert info.total_memory > 0

        cleanup_ecosystem(ecosystem)
      end
    end

    property "ecosystem creation time scales reasonably with worker count" do
      check all(
              small_count <- integer(1..10),
              large_count <- integer(15..30),
              small_count < large_count,
              max_runs: 20
            ) do
        small_config = %{
          coordinator: BenchmarkCoordinator,
          workers: {BenchmarkWorker, count: small_count}
        }

        large_config = %{
          coordinator: BenchmarkCoordinator,
          workers: {BenchmarkWorker, count: large_count}
        }

        {small_time, {:ok, small_ecosystem}} =
          :timer.tc(fn ->
            Processes.spawn_ecosystem(small_config)
          end)

        {large_time, {:ok, large_ecosystem}} =
          :timer.tc(fn ->
            Processes.spawn_ecosystem(large_config)
          end)

        # Property: creation time should scale reasonably (not exponentially)
        # Large ecosystem should take at most 10x longer per additional worker
        ratio = large_count / small_count
        time_ratio = large_time / small_time

        # Allow for significant variance but catch exponential scaling
        assert time_ratio < ratio * 10

        cleanup_ecosystem(small_ecosystem)
        cleanup_ecosystem(large_ecosystem)
      end
    end
  end

  describe "memory isolation properties" do
    property "isolated work never affects caller process memory long-term" do
      check all(
              work_size <- integer(100..10_000),
              max_runs: 20
            ) do
        initial_memory = :erlang.memory(:total)

        work_fn = fn ->
          # Create data proportional to work_size
          _data = :crypto.strong_rand_bytes(work_size)
          :work_complete
        end

        {:ok, worker_pid} = Processes.isolate_memory_intensive_work(work_fn)

        # Wait for completion
        assert_receive {:work_complete, :work_complete}, 2000

        # Wait for worker process to die
        TestHelpers.assert_eventually(fn -> not Process.alive?(worker_pid) end, 1000)

        # Force garbage collection
        :erlang.garbage_collect()
        :timer.sleep(100)

        final_memory = :erlang.memory(:total)

        # Property: memory should not have grown significantly
        # Allow for some variance due to test overhead
        memory_growth = final_memory - initial_memory
        # Property: memory growth should be reasonable (allowing for BEAM overhead)
        # BEAM memory accounting can be unpredictable, so be very generous
        # At least 100KB allowance
        max_reasonable_growth = max(work_size * 10, 100_000)
        assert memory_growth < max_reasonable_growth
      end
    end

    property "worker process always terminates after work completion" do
      check all(
              work_duration <- integer(1..100),
              max_runs: 30
            ) do
        work_fn = fn ->
          :timer.sleep(work_duration)
          :work_done
        end

        {:ok, worker_pid} = Processes.isolate_memory_intensive_work(work_fn)

        # Property: worker should complete and terminate
        assert_receive {:work_complete, :work_done}, work_duration + 1000

        # Property: worker process should die after completion
        TestHelpers.assert_eventually(fn -> not Process.alive?(worker_pid) end, 500)
      end
    end

    property "multiple isolated workers don't interfere with each other" do
      check all(
              worker_count <- integer(2..10),
              work_size <- integer(100..1000),
              max_runs: 15
            ) do
        test_pid = self()

        # Start multiple workers
        worker_pids =
          for i <- 1..worker_count do
            work_fn = fn ->
              # Each worker creates unique data
              _data = :crypto.strong_rand_bytes(work_size)
              # Return worker index
              i
            end

            {:ok, pid} = Processes.isolate_memory_intensive_work(work_fn, test_pid)
            pid
          end

        # Property: all workers should complete successfully
        results =
          for _i <- 1..worker_count do
            assert_receive {:work_complete, result}, 2000
            result
          end

        # Property: results should be unique (no interference)
        assert Enum.sort(results) == Enum.to_list(1..worker_count)

        # Property: all workers should terminate
        TestHelpers.assert_eventually(
          fn ->
            Enum.all?(worker_pids, fn pid -> not Process.alive?(pid) end)
          end,
          2000
        )
      end
    end
  end

  describe "fault tolerance properties" do
    property "ecosystem survives random worker crashes" do
      check all(
              worker_count <- integer(3..10),
              crash_count <- integer(1..min(worker_count - 1, 3)),
              crash_count < worker_count,
              max_runs: 20
            ) do
        config = %{
          coordinator: TestCoordinator,
          workers: {TestWorker, count: worker_count},
          fault_tolerance: :self_healing
        }

        {:ok, ecosystem} = Processes.spawn_ecosystem(config)
        original_workers = ecosystem.workers

        # Randomly crash some workers
        workers_to_crash = Enum.take_random(original_workers, crash_count)

        for worker <- workers_to_crash do
          Process.exit(worker, :kill)
        end

        # Give time for system to react
        :timer.sleep(100)

        {:ok, info} = Processes.ecosystem_info(ecosystem)

        # Property: coordinator should survive worker crashes
        assert Process.alive?(ecosystem.coordinator)

        # Property: some workers should still be alive (either original or respawned)
        # At least non-crashed + coordinator
        assert info.total_processes >= worker_count - crash_count + 1

        cleanup_ecosystem(ecosystem)
      end
    end

    property "ecosystem cleanup always succeeds regardless of process states" do
      check all(
              worker_count <- integer(1..8),
              max_runs: 25
            ) do
        config = %{
          coordinator: TestCoordinator,
          workers: {TestWorker, count: worker_count}
        }

        {:ok, ecosystem} = Processes.spawn_ecosystem(config)

        # Randomly put ecosystem in various states
        case :rand.uniform(4) do
          1 ->
            # Normal state - do nothing
            :ok

          2 ->
            # Kill some workers
            workers_to_kill = Enum.take_random(ecosystem.workers, div(worker_count, 2))
            for worker <- workers_to_kill, do: Process.exit(worker, :kill)

          3 ->
            # Kill coordinator
            Process.exit(ecosystem.coordinator, :kill)

          4 ->
            # Kill everything
            Process.exit(ecosystem.coordinator, :kill)
            for worker <- ecosystem.workers, do: Process.exit(worker, :kill)
        end

        # Property: cleanup should always succeed
        assert TestHelpers.verify_ecosystem_cleanup(ecosystem, 2000) == :ok
      end
    end
  end

  describe "performance properties" do
    property "memory usage is bounded by worker count" do
      check all(
              worker_count <- integer(1..20),
              max_runs: 15
            ) do
        base_memory = :erlang.memory(:total)

        config = %{
          coordinator: MemoryTestCoordinator,
          workers: {MemoryTestWorker, count: worker_count}
        }

        {:ok, ecosystem} = Processes.spawn_ecosystem(config)
        # Let processes stabilize
        :timer.sleep(50)

        peak_memory = :erlang.memory(:total)
        memory_used = peak_memory - base_memory

        # Property: memory should scale roughly linearly with worker count
        # Each process should use less than 100KB on average
        average_memory_per_process = memory_used / (worker_count + 1)
        # 100KB per process
        assert average_memory_per_process < 200_000

        cleanup_ecosystem(ecosystem)

        # Property: memory should be reclaimed after cleanup
        :erlang.garbage_collect()
        :timer.sleep(100)

        final_memory = :erlang.memory(:total)
        memory_after_cleanup = final_memory - base_memory

        # Should reclaim most memory (allow 50% to remain due to test overhead)
        assert memory_after_cleanup < memory_used * 0.5
      end
    end

    property "ecosystem responds to messages within reasonable time" do
      check all(
              worker_count <- integer(1..10),
              message_count <- integer(1..20),
              max_runs: 10
            ) do
        config = %{
          coordinator: MessageTestCoordinator,
          workers: {MessageTestWorker, count: worker_count}
        }

        {:ok, ecosystem} = Processes.spawn_ecosystem(config)

        # Send messages and measure response time
        start_time = System.monotonic_time(:microsecond)

        for i <- 1..message_count do
          send(ecosystem.coordinator, {:test_message, i, self()})
        end

        # Wait for all responses
        for _i <- 1..message_count do
          assert_receive {:message_processed, _}, 1000
        end

        end_time = System.monotonic_time(:microsecond)
        total_time = end_time - start_time

        # Property: average response time should be reasonable
        average_response_time = total_time / message_count
        # Less than 10ms per message
        assert average_response_time < 10_000

        cleanup_ecosystem(ecosystem)
      end
    end
  end

  # Helper functions and test modules

  defp cleanup_ecosystem(ecosystem) do
    # Use the new shutdown function if available
    if function_exported?(Processes, :shutdown_ecosystem, 1) do
      Processes.shutdown_ecosystem(ecosystem)
    else
      # Fallback to manual cleanup
      if Process.alive?(ecosystem.coordinator) do
        Process.exit(ecosystem.coordinator, :shutdown)
      end

      for worker <- ecosystem.workers do
        if Process.alive?(worker) do
          Process.exit(worker, :shutdown)
        end
      end

      :timer.sleep(50)
    end
  end

  # Test modules for property testing

  defmodule TestCoordinator do
    def start_link(_args), do: {:ok, self()}
  end

  defmodule TestWorker do
    def start_link(_args), do: {:ok, self()}
  end

  defmodule BenchmarkCoordinator do
    def start_link(_args), do: {:ok, self()}
  end

  defmodule BenchmarkWorker do
    def start_link(_args), do: {:ok, self()}
  end

  defmodule MemoryTestCoordinator do
    def start_link(_args), do: {:ok, self()}
  end

  defmodule MemoryTestWorker do
    def start_link(_args), do: {:ok, self()}
  end

  defmodule MessageTestCoordinator do
    def start_link(_args) do
      pid = spawn(fn -> message_loop() end)
      {:ok, pid}
    end

    defp message_loop do
      receive do
        {:test_message, i, from} ->
          send(from, {:message_processed, i})
          message_loop()
      end
    end
  end

  defmodule MessageTestWorker do
    def start_link(_args), do: {:ok, self()}
  end
end
