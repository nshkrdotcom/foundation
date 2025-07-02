defmodule Foundation.OTPCleanupStressTest do
  @moduledoc """
  Concurrency and stress tests for OTP cleanup migration.
  
  Tests the system under high load and concurrent access to identify
  race conditions, deadlocks, and resource leaks.
  """
  
  use ExUnit.Case, async: false
  
  import Foundation.AsyncTestHelpers
  alias Foundation.{FeatureFlags, ErrorContext, Registry}
  alias Foundation.Telemetry.{Span, SampledEvents}
  
  @moduletag :stress
  @moduletag :concurrency
  @moduletag timeout: 600_000  # 10 minutes for stress tests
  
  describe "Concurrent Registry Access" do
    setup do
      FeatureFlags.reset_all()
      
      on_exit(fn ->
        FeatureFlags.reset_all()
        # Cleanup any remaining registrations
        cleanup_test_registrations()
      end)
      
      :ok
    end
    
    test "massive concurrent registration and lookup" do
      FeatureFlags.enable(:use_ets_agent_registry)
      
      case Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
        {:module, _} ->
          {:ok, _} = Foundation.Protocols.RegistryETS.start_link()
          
          num_processes = 100
          operations_per_process = 1000
          
          # Track all agent IDs for cleanup
          test_pid = self()
          
          # Spawn many concurrent processes
          tasks = for i <- 1..num_processes do
            Task.async(fn ->
              results = for j <- 1..operations_per_process do
                agent_id = :"stress_#{i}_#{j}"
                
                try do
                  # Register agent
                  case Registry.register(nil, agent_id, self()) do
                    :ok ->
                      # Immediate lookup
                      case Registry.lookup(nil, agent_id) do
                        {:ok, {pid, _}} when pid == self() ->
                          # Random operation
                          case rem(j, 3) do
                            0 ->
                              # Re-lookup
                              Registry.lookup(nil, agent_id)
                            1 ->
                              # List agents (expensive operation)
                              Registry.list_agents()
                            2 ->
                              # Unregister
                              Registry.unregister(nil, agent_id)
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
          process_results = for _i <- 1..num_processes do
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
              {kind, _} -> kind
              {:register_error, _} -> :register_error
              {:lookup_error, _} -> :lookup_error
              other -> other
            end)
          
          if map_size(errors) > 0 do
            IO.puts("Error summary under concurrent access:")
            Enum.each(errors, fn {type, error_list} ->
              IO.puts("  #{type}: #{length(error_list)} occurrences")
            end)
          end
          
        {:error, :nofile} ->
          :ok
      end
    end
    
    test "registry race condition detection" do
      FeatureFlags.enable(:use_ets_agent_registry)
      
      case Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
        {:module, _} ->
          {:ok, _} = Foundation.Protocols.RegistryETS.start_link()
          
          # Test for race conditions in registration/deregistration
          num_rounds = 50
          agents_per_round = 20
          
          for round <- 1..num_rounds do
            # Create agents
            agent_pids = for i <- 1..agents_per_round do
              spawn_link(fn ->
                receive do
                  :stop -> :ok
                after
                  30_000 -> :timeout
                end
              end)
            end
            
            # Register all agents concurrently
            registration_tasks = for {i, pid} <- Enum.with_index(agent_pids) do
              Task.async(fn ->
                agent_id = :"race_test_#{round}_#{i}"
                Registry.register(nil, agent_id, pid)
                {agent_id, pid}
              end)
            end
            
            registered_agents = Task.await_many(registration_tasks, 5000)
            
            # Verify all registrations succeeded
            for {agent_id, expected_pid} <- registered_agents do
              case Registry.lookup(nil, agent_id) do
                {:ok, {^expected_pid, _}} -> :ok
                {:ok, {other_pid, _}} ->
                  flunk("Race condition: agent #{agent_id} registered to wrong pid. Expected #{inspect(expected_pid)}, got #{inspect(other_pid)}")
                {:error, reason} ->
                  flunk("Registration failed for #{agent_id}: #{inspect(reason)}")
              end
            end
            
            # Kill all agents concurrently to test cleanup
            for pid <- agent_pids do
              send(pid, :stop)
            end
            
            # Wait for cleanup
            wait_until(fn ->
              # Check that all agents are cleaned up
              Enum.all?(registered_agents, fn {agent_id, _} ->
                case Registry.lookup(nil, agent_id) do
                  {:error, :not_found} -> true
                  _ -> false
                end
              end)
            end, 5000)
          end
          
        {:error, :nofile} ->
          :ok
      end
    end
    
    test "registry memory leak under stress" do
      FeatureFlags.enable(:use_ets_agent_registry)
      
      case Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
        {:module, _} ->
          {:ok, _} = Foundation.Protocols.RegistryETS.start_link()
          
          initial_memory = :erlang.memory(:total)
          
          # Perform many registration/deregistration cycles
          for cycle <- 1..100 do
            # Create burst of agents
            agents = for i <- 1..50 do
              agent_id = :"memory_leak_test_#{cycle}_#{i}"
              agent_pid = spawn_link(fn ->
                receive do
                  :stop -> :ok
                after
                  1000 -> :timeout
                end
              end)
              
              Registry.register(nil, agent_id, agent_pid)
              {agent_id, agent_pid}
            end
            
            # Let them exist briefly
            Process.sleep(10)
            
            # Kill all agents
            for {_agent_id, agent_pid} <- agents do
              send(agent_pid, :stop)
            end
            
            # Wait for cleanup
            Process.sleep(20)
            
            # Force garbage collection every 10 cycles
            if rem(cycle, 10) == 0 do
              :erlang.garbage_collect()
            end
          end
          
          # Final garbage collection
          :erlang.garbage_collect()
          Process.sleep(100)
          
          final_memory = :erlang.memory(:total)
          memory_growth = final_memory - initial_memory
          
          # Memory growth should be minimal
          assert memory_growth < 50_000_000,  # 50MB
                 "Memory leak detected in registry: #{memory_growth} bytes growth"
          
        {:error, :nofile} ->
          :ok
      end
    end
    
    defp cleanup_test_registrations do
      # Clean up any test registrations
      try do
        if Code.ensure_loaded?(Foundation.Registry) == {:module, Foundation.Registry} do
          agents = Registry.list_agents() rescue []
          
          for {agent_id, _pid} <- agents do
            if Atom.to_string(agent_id) |> String.contains?("stress") or
               Atom.to_string(agent_id) |> String.contains?("race_test") or
               Atom.to_string(agent_id) |> String.contains?("memory_leak") do
              Registry.unregister(nil, agent_id) rescue _ -> :ok
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
      tasks = for i <- 1..num_processes do
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
      assert final_context == %{}, "Context not properly cleared: #{inspect(final_context)}"
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
      
      assert memory_growth < 100_000_000,  # 100MB
             "Excessive memory usage in error context: #{memory_growth} bytes"
    end
  end
  
  describe "Telemetry Stress Tests" do
    test "massive span creation and nesting" do
      num_root_spans = 100
      max_nesting_depth = 20
      
      # Create many root spans with deep nesting
      root_spans = for i <- 1..num_root_spans do
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
      
      tasks = for i <- 1..num_processes do
        Task.async(fn ->
          for j <- 1..spans_per_process do
            span_name = "concurrent_span_#{i}_#{j}"
            
            Span.with_span(span_name, %{process: i, span: j}, fn ->
              # Simulate concurrent work
              :timer.sleep(Enum.random(1..5))
              
              # Nested span sometimes
              if rem(j, 10) == 0 do
                Span.with_span("nested_#{j}", %{nested: true}, fn ->
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
          Span.with_span("exception_test_#{i}", %{operation: i}, fn ->
            # Randomly throw exceptions
            case rem(i, 5) do
              0 -> raise "test error #{i}"
              1 -> throw {:test_throw, i}
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
      
      case Code.ensure_loaded?(Foundation.Telemetry.SampledEvents) do
        {:module, _} ->
          {:ok, _} = Foundation.Telemetry.SampledEvents.start_link()
          
          num_emitters = 20
          events_per_emitter = 1000
          
          # Concurrent event emission
          tasks = for i <- 1..num_emitters do
            Task.async(fn ->
              for j <- 1..events_per_emitter do
                # Regular events
                SampledEvents.emit_event(
                  [:stress, :test, :regular],
                  %{count: 1, value: j},
                  %{emitter: i, event: j, dedup_key: "key_#{rem(j, 100)}"}
                )
                
                # Batched events
                SampledEvents.emit_batched(
                  [:stress, :test, :batched],
                  j,
                  %{batch_key: "batch_#{rem(i, 5)}"}
                )
                
                # Small delay to avoid overwhelming
                if rem(j, 100) == 0 do
                  Process.sleep(1)
                end
              end
            end)
          end
          
          Task.await_many(tasks, 60_000)
          
          # Wait for batch processing
          Process.sleep(2000)
          
        {:error, :nofile} ->
          :ok
      end
    end
  end
  
  describe "Combined System Stress Tests" do
    test "full system under extreme load" do
      FeatureFlags.enable_otp_cleanup_stage(4)
      
      # Start all available services
      services = []
      
      services = case Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
        {:module, _} ->
          {:ok, registry_pid} = Foundation.Protocols.RegistryETS.start_link()
          [registry_pid | services]
        {:error, :nofile} ->
          services
      end
      
      services = case Code.ensure_loaded?(Foundation.Telemetry.SampledEvents) do
        {:module, _} ->
          {:ok, sampled_events_pid} = Foundation.Telemetry.SampledEvents.start_link()
          [sampled_events_pid | services]
        {:error, :nofile} ->
          services
      end
      
      # Extreme load parameters
      num_workers = 100
      operations_per_worker = 500
      operation_types = 6
      
      initial_memory = :erlang.memory(:total)
      initial_processes = :erlang.system_info(:process_count)
      
      # Launch extreme load
      tasks = for worker_id <- 1..num_workers do
        Task.async(fn ->
          for op <- 1..operations_per_worker do
            operation_type = rem(op, operation_types)
            
            try do
              case operation_type do
                0 ->
                  # Registry operations
                  agent_id = :"extreme_#{worker_id}_#{op}"
                  Registry.register(nil, agent_id, self())
                  Registry.lookup(nil, agent_id)
                  if rem(op, 10) == 0, do: Registry.unregister(nil, agent_id)
                  
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
                  Span.with_span("extreme_test", %{worker: worker_id, op: op}, fn ->
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
                  SampledEvents.emit_event(
                    [:extreme, :test],
                    %{count: 1},
                    %{worker: worker_id, dedup_key: "key_#{rem(op, 50)}"}
                  )
                  
                5 ->
                  # Complex workflow
                  agent_id = :"workflow_#{worker_id}_#{op}"
                  
                  ErrorContext.set_context(%{workflow: true, worker: worker_id})
                  
                  Span.with_span("workflow", %{worker: worker_id}, fn ->
                    Registry.register(nil, agent_id, self())
                    
                    Span.with_span("lookup", %{}, fn ->
                      Registry.lookup(nil, agent_id)
                    end)
                    
                    SampledEvents.emit_event(
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
      Task.await_many(tasks, 600_000)  # 10 minutes
      
      # System stability check
      Process.sleep(1000)
      :erlang.garbage_collect()
      
      final_memory = :erlang.memory(:total)
      final_processes = :erlang.system_info(:process_count)
      
      memory_growth = final_memory - initial_memory
      process_growth = final_processes - initial_processes
      
      # Verify system didn't degrade
      assert memory_growth < 500_000_000,  # 500MB
             "Extreme memory growth under stress: #{memory_growth} bytes"
      
      assert process_growth < 200,
             "Process leak under extreme load: #{process_growth} extra processes"
      
      # Test that system is still functional
      Registry.register(nil, :post_stress_test, self())
      assert {:ok, {pid, _}} = Registry.lookup(nil, :post_stress_test)
      assert pid == self()
      
      ErrorContext.set_context(%{post_stress: true})
      assert ErrorContext.get_context().post_stress == true
      
      test_span = Span.start_span("post_stress", %{})
      assert :ok = Span.end_span(test_span)
    end
    
    test "system recovery after resource exhaustion" do
      FeatureFlags.enable_otp_cleanup_stage(4)
      
      # Try to exhaust some resources temporarily
      large_agents = []
      
      try do
        # Create many agents with large state
        large_agents = for i <- 1..1000 do
          agent_pid = spawn_link(fn ->
            # Hold large amount of data
            large_data = for _j <- 1..1000, do: :crypto.strong_rand_bytes(1000)
            
            receive do
              :stop -> :ok
            after
              60_000 -> :timeout
            end
          end)
          
          agent_id = :"resource_exhaustion_#{i}"
          Registry.register(nil, agent_id, agent_pid)
          
          # Large error context
          ErrorContext.set_context(%{
            resource_test: true,
            agent: i,
            large_data: for(_j <- 1..100, do: "large_string_#{i}")
          })
          
          {agent_id, agent_pid}
        end
        
        # System should still be functional despite resource pressure
        Registry.register(nil, :resource_test_agent, self())
        assert {:ok, {pid, _}} = Registry.lookup(nil, :resource_test_agent)
        assert pid == self()
        
      after
        # Clean up resources
        for {agent_id, agent_pid} <- large_agents do
          send(agent_pid, :stop)
          Registry.unregister(nil, agent_id) rescue _ -> :ok
        end
        
        # Force cleanup
        :erlang.garbage_collect()
        Process.sleep(1000)
      end
      
      # Verify system recovered
      Registry.register(nil, :recovery_test_agent, self())
      assert {:ok, {pid, _}} = Registry.lookup(nil, :recovery_test_agent)
      assert pid == self()
      
      ErrorContext.set_context(%{recovery_test: true})
      assert ErrorContext.get_context().recovery_test == true
    end
  end
end