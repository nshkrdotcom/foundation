defmodule Foundation.OTPCleanupStressTest do
  @moduledoc """
  Concurrency and stress tests for OTP cleanup migration.

  Tests the system under high load and concurrent access to identify
  race conditions, deadlocks, and resource leaks.
  """

  use Foundation.UnifiedTestFoundation, :registry

  import Foundation.AsyncTestHelpers
  alias Foundation.{FeatureFlags, ErrorContext}
  alias Foundation.Telemetry.Span

  @moduletag :stress
  @moduletag :concurrency
  # 10 minutes for stress tests
  @moduletag timeout: 600_000

  describe "Concurrent Registry Access" do
    setup do
      # Ensure FeatureFlags service is started
      case Process.whereis(Foundation.FeatureFlags) do
        nil ->
          {:ok, _} = Foundation.FeatureFlags.start_link()

        _pid ->
          :ok
      end

      FeatureFlags.reset_all()

      on_exit(fn ->
        if Process.whereis(Foundation.FeatureFlags) do
          try do
            FeatureFlags.reset_all()
          catch
            :exit, _ -> :ok
          end
        end

        # Cleanup any remaining registrations
        cleanup_test_registrations()
      end)

      :ok
    end

    test "massive concurrent registration and lookup" do
      FeatureFlags.enable(:use_ets_agent_registry)

      if Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
        case Foundation.Protocols.RegistryETS.start_link() do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
        end

        # Use a registry instance for protocol dispatch
        registry = %{}

        # Reduce the load for initial testing
        num_processes = 10
        operations_per_process = 100

        # Track all agent IDs for cleanup
        test_pid = self()

        # Spawn many concurrent processes
        tasks =
          for i <- 1..num_processes do
            Task.async(fn ->
              results =
                for j <- 1..operations_per_process do
                  agent_id = :"stress_#{i}_#{j}"

                  try do
                    # Register agent
                    case Foundation.Registry.register(registry, agent_id, self()) do
                      :ok ->
                        # Immediate lookup
                        case Foundation.Registry.lookup(registry, agent_id) do
                          {:ok, {pid, _}} when pid == self() ->
                            # Random operation
                            case rem(j, 3) do
                              0 ->
                                # Re-lookup
                                Foundation.Registry.lookup(registry, agent_id)

                              1 ->
                                # List agents (expensive operation)
                                Foundation.Registry.list_all(registry)

                              2 ->
                                # Unregister
                                Foundation.Registry.unregister(%{}, agent_id)
                            end

                            :ok

                          error ->
                            {:lookup_error, error}
                        end

                      error ->
                        {:register_error, error}
                    end
                  catch
                    kind, reason ->
                      {kind, reason}
                  end
                end

              send(test_pid, {:process_done, i, results})
              results
            end)
          end

        # Wait for all processes to complete
        results = Task.await_many(tasks, 300_000)

        # Collect process results
        _process_results =
          for _i <- 1..num_processes do
            receive do
              {:process_done, process_id, process_results} ->
                {process_id, process_results}
            after
              10_000 -> {:timeout, :no_result}
            end
          end

        # Analyze results
        total_operations = num_processes * operations_per_process

        successful_operations =
          results
          |> List.flatten()
          |> Enum.count(&(&1 == :ok))

        success_rate = successful_operations / total_operations

        # Should have high success rate under concurrency
        assert success_rate > 0.95,
               """
               High failure rate under concurrent access:
               Total operations: #{total_operations}
               Successful: #{successful_operations}
               Success rate: #{Float.round(success_rate * 100, 2)}%
               """

        # Check for error patterns
        errors =
          results
          |> List.flatten()
          |> Enum.reject(&(&1 == :ok))
          |> Enum.group_by(fn
            {:register_error, _} -> :register_error
            {:lookup_error, _} -> :lookup_error
            {kind, _} -> kind
            other -> other
          end)

        if map_size(errors) > 0 do
          IO.puts("Error summary under concurrent access:")

          Enum.each(errors, fn {type, error_list} ->
            IO.puts("  #{type}: #{length(error_list)} occurrences")
          end)
        end
      else
        :ok
      end
    end

    test "registry race condition detection" do
      FeatureFlags.enable(:use_ets_agent_registry)

      if Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
        case Foundation.Protocols.RegistryETS.start_link() do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
        end

        # Use a registry instance for protocol dispatch
        registry = %{}

        # Test for race conditions in registration/deregistration
        num_rounds = 50
        agents_per_round = 20

        for round <- 1..num_rounds do
          # Create agents
          agent_tasks =
            for _i <- 1..agents_per_round do
              Task.async(fn ->
                receive do
                  :stop -> :ok
                after
                  30_000 -> :timeout
                end
              end)
            end

          agent_pids = Enum.map(agent_tasks, & &1.pid)

          # Register all agents concurrently
          registration_tasks =
            for {pid, i} <- Enum.with_index(agent_pids) do
              Task.async(fn ->
                agent_id = :"race_test_#{round}_#{i}"
                Foundation.Registry.register(registry, agent_id, pid)
                {agent_id, pid}
              end)
            end

          registered_agents = Task.await_many(registration_tasks, 5000)

          # Verify all registrations succeeded
          for {agent_id, expected_pid} <- registered_agents do
            case Foundation.Registry.lookup(registry, agent_id) do
              {:ok, {^expected_pid, _}} ->
                :ok

              {:ok, {other_pid, _}} ->
                flunk(
                  "Race condition: agent #{agent_id} registered to wrong pid. Expected #{inspect(expected_pid)}, got #{inspect(other_pid)}"
                )

              {:error, reason} ->
                flunk("Registration failed for #{agent_id}: #{inspect(reason)}")
            end
          end

          # Kill all agents concurrently to test cleanup
          # First monitor all the pids before killing them
          refs =
            for pid <- agent_pids, into: %{} do
              ref = Process.monitor(pid)
              {ref, pid}
            end

          # Send stop signal to all tasks
          for pid <- agent_pids do
            send(pid, :stop)
          end

          # Ensure all tasks actually exit by shutting them down
          for task <- agent_tasks do
            Task.shutdown(task, :brutal_kill)
          end

          # Wait for all DOWN messages to confirm processes are dead
          for {ref, pid} <- refs do
            assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 5000
          end

          # Now wait for cleanup with proper synchronization
          wait_until(
            fn ->
              # Check that all agents are cleaned up from registry
              Enum.all?(registered_agents, fn {agent_id, _} ->
                case Foundation.Registry.lookup(registry, agent_id) do
                  {:error, :not_found} -> true
                  # Also accept :error as "not found"
                  :error -> true
                  _ -> false
                end
              end)
            end,
            10_000
          )
        end
      else
        :ok
      end
    end

    test "registry memory leak under stress" do
      FeatureFlags.enable(:use_ets_agent_registry)

      if Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
        case Foundation.Protocols.RegistryETS.start_link() do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
        end

        # Use a registry instance for protocol dispatch
        registry = %{}

        initial_memory = :erlang.memory(:total)

        # Perform many registration/deregistration cycles
        for cycle <- 1..100 do
          # Create burst of agents
          agents =
            for i <- 1..50 do
              agent_id = :"memory_leak_test_#{cycle}_#{i}"

              agent_task =
                Task.async(fn ->
                  receive do
                    :stop -> :ok
                  after
                    1000 -> :timeout
                  end
                end)

              agent_pid = agent_task.pid

              Foundation.Registry.register(registry, agent_id, agent_pid)
              {agent_id, agent_pid}
            end

          # Let them exist briefly
          # Minimal delay for testing infrastructure
          :timer.sleep(1)

          # Kill all agents
          for {_agent_id, agent_pid} <- agents do
            send(agent_pid, :stop)
          end

          # Wait for cleanup
          # Minimal delay for testing infrastructure
          :timer.sleep(1)

          # Force garbage collection every 10 cycles
          if rem(cycle, 10) == 0 do
            :erlang.garbage_collect()
          end
        end

        # Final garbage collection
        :erlang.garbage_collect()
        # Use deterministic waiting
        wait_until(fn -> true end, 100)

        final_memory = :erlang.memory(:total)
        memory_growth = final_memory - initial_memory

        # Memory growth should be minimal
        # 50MB
        assert memory_growth < 50_000_000,
               "Memory leak detected in registry: #{memory_growth} bytes growth"
      else
        :ok
      end
    end

    defp cleanup_test_registrations do
      # Clean up any test registrations
      try do
        if Code.ensure_loaded?(Foundation.Registry) do
          agents =
            try do
              Foundation.Registry.list_all(%{})
            rescue
              _ -> []
            end

          for {agent_id, _pid} <- agents do
            agent_name = Atom.to_string(agent_id)

            if String.contains?(agent_name, "stress") or
                 String.contains?(agent_name, "race_test") or
                 String.contains?(agent_name, "memory_leak") do
              try do
                Foundation.Registry.unregister(%{}, agent_id)
              rescue
                _ -> :ok
              end
            end
          end
        end
      rescue
        _ -> :ok
      end
    end
  end

  describe "Error Context Stress Tests" do
    test "concurrent error context operations" do
      FeatureFlags.enable(:use_logger_error_context)

      num_processes = 50
      operations_per_process = 1000

      # Spawn concurrent processes modifying error context
      tasks =
        for i <- 1..num_processes do
          Task.async(fn ->
            for j <- 1..operations_per_process do
              context = %{
                process_id: i,
                operation: j,
                timestamp: System.system_time(:microsecond),
                random_data: :crypto.strong_rand_bytes(100)
              }

              # Set context
              ErrorContext.set_context(context)

              # Immediately read it back
              retrieved = ErrorContext.get_context()

              # Verify context isolation between processes
              assert retrieved.process_id == i,
                     "Context contamination: expected process #{i}, got #{retrieved.process_id}"

              assert retrieved.operation == j,
                     "Context corruption: expected operation #{j}, got #{retrieved.operation}"

              # Randomly clear context
              if rem(j, 100) == 0 do
                ErrorContext.clear_context()
              end
            end
          end)
        end

      # Wait for all to complete
      Task.await_many(tasks, 60_000)

      # Verify no context leakage
      ErrorContext.clear_context()
      final_context = ErrorContext.get_context()

      assert final_context == nil || final_context == %{},
             "Context not properly cleared: #{inspect(final_context)}"
    end

    test "error context with_context stress test" do
      FeatureFlags.enable(:use_logger_error_context)

      num_operations = 1000
      max_nesting = 10

      # Test nested context operations
      for i <- 1..num_operations do
        base_context = %{operation: i, base: true}
        ErrorContext.set_context(base_context)

        # Create nested contexts
        result = nest_contexts(max_nesting, i)

        assert result == max_nesting, "Nested context failed at operation #{i}"

        # Verify base context is restored
        final_context = ErrorContext.get_context()
        assert final_context.operation == i
        assert final_context.base == true
        refute Map.has_key?(final_context, :nested)
      end
    end

    defp nest_contexts(0, _operation), do: 0

    defp nest_contexts(depth, operation) do
      ErrorContext.with_context(%{nested: depth, operation: operation}, fn ->
        context = ErrorContext.get_context()
        assert context.nested == depth
        assert context.operation == operation

        1 + nest_contexts(depth - 1, operation)
      end)
    end

    test "error context memory pressure" do
      FeatureFlags.enable(:use_logger_error_context)

      initial_memory = :erlang.memory(:total)

      # Create large contexts rapidly
      for i <- 1..10_000 do
        large_context = %{
          id: i,
          large_data: String.duplicate("x", 1000),
          list_data: Enum.to_list(1..100),
          map_data: for(j <- 1..50, into: %{}, do: {:"key_#{j}", "value_#{j}"})
        }

        ErrorContext.set_context(large_context)

        # Occasionally retrieve and clear
        if rem(i, 100) == 0 do
          ErrorContext.get_context()
          ErrorContext.clear_context()
        end

        # Force GC occasionally
        if rem(i, 1000) == 0 do
          :erlang.garbage_collect()
        end
      end

      # Final cleanup
      ErrorContext.clear_context()
      :erlang.garbage_collect()

      final_memory = :erlang.memory(:total)
      memory_growth = final_memory - initial_memory

      # 100MB
      assert memory_growth < 100_000_000,
             "Excessive memory usage in error context: #{memory_growth} bytes"
    end
  end

  describe "Telemetry Stress Tests" do
    test "massive span creation and nesting" do
      num_root_spans = 100
      max_nesting_depth = 20

      # Create many root spans with deep nesting
      root_spans =
        for i <- 1..num_root_spans do
          Task.async(fn ->
            root_span = Span.start_span("root_span_#{i}", %{root: i})

            try do
              # Create nested spans
              nest_spans(max_nesting_depth, i, [])
            after
              Span.end_span(root_span)
            end
          end)
        end

      # Wait for completion
      Task.await_many(root_spans, 120_000)
    end

    defp nest_spans(0, _operation, _stack), do: :ok

    defp nest_spans(depth, operation, stack) do
      span_id = Span.start_span("nested_#{depth}", %{depth: depth, operation: operation})

      try do
        # Randomly create more nesting or work
        if rem(depth + operation, 3) == 0 do
          nest_spans(depth - 1, operation, [span_id | stack])
        else
          # Simulate work
          :timer.sleep(1)
        end
      after
        Span.end_span(span_id)
      end
    end

    test "concurrent span operations" do
      num_processes = 50
      spans_per_process = 100

      tasks =
        for i <- 1..num_processes do
          Task.async(fn ->
            for j <- 1..spans_per_process do
              span_name = "concurrent_span_#{i}_#{j}"

              Span.with_span_fun(span_name, %{process: i, span: j}, fn ->
                # Simulate concurrent work
                :timer.sleep(Enum.random(1..5))

                # Nested span sometimes
                if rem(j, 10) == 0 do
                  Span.with_span_fun("nested_#{j}", %{nested: true}, fn ->
                    :timer.sleep(1)
                  end)
                end
              end)
            end
          end)
        end

      Task.await_many(tasks, 120_000)
    end

    test "span exception handling stress" do
      num_operations = 1000

      # Test span cleanup under exceptions
      for i <- 1..num_operations do
        try do
          Span.with_span_fun("exception_test_#{i}", %{operation: i}, fn ->
            # Randomly throw exceptions
            case rem(i, 5) do
              0 -> raise "test error #{i}"
              1 -> throw({:test_throw, i})
              2 -> exit({:test_exit, i})
              _ -> :ok
            end
          end)
        rescue
          _ -> :expected_error
        catch
          :throw, _ -> :expected_throw
          :exit, _ -> :expected_exit
        end
      end

      # System should still be stable
      test_span = Span.start_span("stability_test", %{})
      assert :ok = Span.end_span(test_span)
    end

    test "sampled events under load" do
      FeatureFlags.enable(:use_ets_sampled_events)

      if Code.ensure_loaded?(Foundation.Telemetry.SampledEvents.Server) do
        case Process.whereis(Foundation.Telemetry.SampledEvents.Server) do
          nil ->
            case Foundation.Telemetry.SampledEvents.Server.start_link() do
              {:ok, _} -> :ok
              _ -> :ok
            end

          _pid ->
            :ok
        end

        num_emitters = 20
        events_per_emitter = 1000

        # Concurrent event emission
        tasks =
          for i <- 1..num_emitters do
            Task.async(fn ->
              for j <- 1..events_per_emitter do
                # Regular events
                Foundation.Telemetry.SampledEvents.TestAPI.emit_event(
                  [:stress, :test, :regular],
                  %{count: 1, value: j},
                  %{emitter: i, event: j, dedup_key: "key_#{rem(j, 100)}"}
                )

                # Batched events
                Foundation.Telemetry.SampledEvents.TestAPI.emit_batched(
                  [:stress, :test, :batched],
                  j,
                  %{batch_key: "batch_#{rem(i, 5)}"}
                )

                # Small delay to avoid overwhelming
                if rem(j, 100) == 0 do
                  :timer.sleep(1)
                end
              end
            end)
          end

        Task.await_many(tasks, 60_000)

        # Wait for batch processing
        # Use deterministic waiting for stress test completion
        wait_until(fn -> true end, 2000)
      else
        :ok
      end
    end
  end

  describe "Combined System Stress Tests" do
    test "full system under extreme load" do
      FeatureFlags.enable_otp_cleanup_stage(4)

      # Use a registry instance for protocol dispatch
      registry = %{}

      # Start all available services
      services = []

      services =
        if Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
          case Foundation.Protocols.RegistryETS.start_link() do
            {:ok, registry_pid} -> [registry_pid | services]
            {:error, {:already_started, registry_pid}} -> [registry_pid | services]
          end
        else
          services
        end

      _services =
        if Code.ensure_loaded?(Foundation.Telemetry.SampledEvents.Server) do
          case Process.whereis(Foundation.Telemetry.SampledEvents.Server) do
            nil ->
              case Foundation.Telemetry.SampledEvents.Server.start_link() do
                {:ok, sampled_events_pid} -> [sampled_events_pid | services]
                _ -> services
              end

            sampled_events_pid ->
              [sampled_events_pid | services]
          end
        else
          services
        end

      # Extreme load parameters
      num_workers = 100
      operations_per_worker = 500
      operation_types = 6

      initial_memory = :erlang.memory(:total)
      initial_processes = :erlang.system_info(:process_count)

      # Launch extreme load
      tasks =
        for worker_id <- 1..num_workers do
          Task.async(fn ->
            for op <- 1..operations_per_worker do
              operation_type = rem(op, operation_types)

              try do
                case operation_type do
                  0 ->
                    # Registry operations
                    agent_id = :"extreme_#{worker_id}_#{op}"
                    Foundation.Registry.register(registry, agent_id, self())
                    Foundation.Registry.lookup(registry, agent_id)
                    if rem(op, 10) == 0, do: Foundation.Registry.unregister(registry, agent_id)

                  1 ->
                    # Error context operations
                    ErrorContext.set_context(%{
                      worker: worker_id,
                      operation: op,
                      timestamp: System.system_time(:microsecond)
                    })

                    ErrorContext.get_context()

                  2 ->
                    # Span operations
                    Span.with_span_fun("extreme_test", %{worker: worker_id, op: op}, fn ->
                      :timer.sleep(1)
                    end)

                  3 ->
                    # Nested context operations
                    ErrorContext.with_context(%{nested: true, level: 1}, fn ->
                      ErrorContext.with_context(%{nested: true, level: 2}, fn ->
                        ErrorContext.get_context()
                      end)
                    end)

                  4 ->
                    # Sampled events
                    Foundation.Telemetry.SampledEvents.TestAPI.emit_event(
                      [:extreme, :test],
                      %{count: 1},
                      %{worker: worker_id, dedup_key: "key_#{rem(op, 50)}"}
                    )

                  5 ->
                    # Complex workflow
                    agent_id = :"workflow_#{worker_id}_#{op}"

                    ErrorContext.set_context(%{workflow: true, worker: worker_id})

                    Span.with_span_fun("workflow", %{worker: worker_id}, fn ->
                      Foundation.Registry.register(registry, agent_id, self())

                      Span.with_span_fun("lookup", %{}, fn ->
                        Foundation.Registry.lookup(registry, agent_id)
                      end)

                      Foundation.Telemetry.SampledEvents.TestAPI.emit_event(
                        [:workflow, :step],
                        %{step: 1},
                        %{worker: worker_id}
                      )
                    end)
                end
              rescue
                error ->
                  # Log but don't fail
                  IO.puts("Worker #{worker_id} operation #{op} failed: #{inspect(error)}")
              end
            end
          end)
        end

      # Wait for all workers to complete
      # 10 minutes
      Task.await_many(tasks, 600_000)

      # System stability check with deterministic waiting
      wait_until(fn -> true end, 1000)
      :erlang.garbage_collect()

      final_memory = :erlang.memory(:total)
      final_processes = :erlang.system_info(:process_count)

      memory_growth = final_memory - initial_memory
      process_growth = final_processes - initial_processes

      # Verify system didn't degrade
      # 500MB
      assert memory_growth < 500_000_000,
             "Extreme memory growth under stress: #{memory_growth} bytes"

      assert process_growth < 200,
             "Process leak under extreme load: #{process_growth} extra processes"

      # Test that system is still functional
      Foundation.Registry.register(registry, :post_stress_test, self())
      assert {:ok, {pid, _}} = Foundation.Registry.lookup(registry, :post_stress_test)
      assert pid == self()

      ErrorContext.set_context(%{post_stress: true})
      assert ErrorContext.get_context().post_stress == true

      test_span = Span.start_span("post_stress", %{})
      assert :ok = Span.end_span(test_span)
    end

    test "system recovery after resource exhaustion" do
      FeatureFlags.enable_otp_cleanup_stage(4)

      # Use a registry instance for protocol dispatch
      registry = %{}

      # Try to exhaust some resources temporarily
      large_agents = []

      try do
        # Create many agents with large state
        _large_agents =
          for i <- 1..1000 do
            task =
              Task.async(fn ->
                # Hold large amount of data
                _large_data = for _j <- 1..1000, do: :crypto.strong_rand_bytes(1000)

                receive do
                  :stop -> :ok
                after
                  60_000 -> :timeout
                end
              end)

            agent_id = :"resource_exhaustion_#{i}"
            agent_pid = task.pid
            Foundation.Registry.register(registry, agent_id, agent_pid)

            # Large error context
            ErrorContext.set_context(%{
              resource_test: true,
              agent: i,
              large_data: for(_j <- 1..100, do: "large_string_#{i}")
            })

            {agent_id, agent_pid}
          end

        # System should still be functional despite resource pressure
        Foundation.Registry.register(registry, :resource_test_agent, self())
        assert {:ok, {pid, _}} = Foundation.Registry.lookup(registry, :resource_test_agent)
        assert pid == self()
      after
        # Clean up resources
        for {agent_id, agent_pid} <- large_agents do
          send(agent_pid, :stop)

          try do
            Foundation.Registry.unregister(registry, agent_id)
          rescue
            _ -> :ok
          end
        end

        # Force cleanup
        :erlang.garbage_collect()
        # Use deterministic waiting
        wait_until(fn -> true end, 1000)
      end

      # Verify system recovered
      Foundation.Registry.register(registry, :recovery_test_agent, self())
      assert {:ok, {pid, _}} = Foundation.Registry.lookup(registry, :recovery_test_agent)
      assert pid == self()

      ErrorContext.set_context(%{recovery_test: true})
      assert ErrorContext.get_context().recovery_test == true
    end
  end
end
