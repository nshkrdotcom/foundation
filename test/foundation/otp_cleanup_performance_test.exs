defmodule Foundation.OTPCleanupPerformanceTest do
  @moduledoc """
  Performance regression tests for OTP cleanup migration.
  
  Benchmarks the performance of new implementations compared to legacy ones
  to ensure no significant performance degradation.
  """
  
  use Foundation.UnifiedTestFoundation, :registry
  
  import Foundation.AsyncTestHelpers
  alias Foundation.{FeatureFlags, ErrorContext, Registry}
  alias Foundation.Telemetry.{Span, SampledEvents}
  
  @moduletag :performance
  @moduletag :benchmark
  @moduletag timeout: 300_000  # 5 minutes for performance tests
  
  # Performance thresholds (in microseconds)
  @registry_operation_threshold 1000    # 1ms per operation
  @error_context_threshold 100          # 0.1ms per operation  
  @span_operation_threshold 500         # 0.5ms per operation
  @batch_operation_threshold 50         # 0.05ms per operation
  
  describe "Registry Performance Tests" do
    setup do
      FeatureFlags.reset_all()
      
      on_exit(fn ->
        FeatureFlags.reset_all()
      end)
      
      :ok
    end
    
    test "ETS registry performance vs legacy" do
      # Benchmark legacy implementation
      FeatureFlags.disable(:use_ets_agent_registry)
      
      legacy_time = benchmark_registry_operations(1000, "legacy")
      
      # Benchmark new ETS implementation
      FeatureFlags.enable(:use_ets_agent_registry)
      
      # Start ETS registry if available
      case Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
        {:module, _} ->
          {:ok, _} = Foundation.Protocols.RegistryETS.start_link()
          
          ets_time = benchmark_registry_operations(1000, "ets")
          
          # New implementation should not be more than 2x slower
          slowdown_ratio = ets_time / legacy_time
          
          assert slowdown_ratio < 2.0,
                 """
                 ETS registry significantly slower than legacy:
                 Legacy: #{legacy_time}μs
                 ETS: #{ets_time}μs
                 Slowdown: #{Float.round(slowdown_ratio, 2)}x
                 """
          
          # Absolute performance check
          operations_per_second = 1_000_000 / (ets_time / 1000)
          assert operations_per_second > 10_000,
                 "ETS registry too slow: #{Float.round(operations_per_second)} ops/sec"
          
        {:error, :nofile} ->
          # ETS implementation not available, skip comparison
          :ok
      end
    end
    
    test "registry operation scaling" do
      FeatureFlags.enable(:use_ets_agent_registry)
      
      case Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
        {:module, _} ->
          {:ok, _} = Foundation.Protocols.RegistryETS.start_link()
          
          # Test different load levels
          load_levels = [100, 500, 1000, 2000]
          
          times = for load <- load_levels do
            time = benchmark_registry_operations(load, "scaling_#{load}")
            {load, time}
          end
          
          # Check that time scales roughly linearly (not exponentially)
          [{small_load, small_time}, {_, _}, {_, _}, {large_load, large_time}] = times
          
          scaling_ratio = (large_time / small_time) / (large_load / small_load)
          
          # Should scale roughly linearly (within 3x factor)
          assert scaling_ratio < 3.0,
                 """
                 Registry scaling poorly:
                 #{small_load} ops: #{small_time}μs
                 #{large_load} ops: #{large_time}μs
                 Scaling ratio: #{Float.round(scaling_ratio, 2)}
                 """
          
        {:error, :nofile} ->
          :ok
      end
    end
    
    test "concurrent registry access performance" do
      FeatureFlags.enable(:use_ets_agent_registry)
      
      case Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
        {:module, _} ->
          {:ok, _} = Foundation.Protocols.RegistryETS.start_link()
          
          # Test concurrent access
          num_processes = 10
          operations_per_process = 100
          
          {total_time, _} = :timer.tc(fn ->
            tasks = for i <- 1..num_processes do
              Task.async(fn ->
                for j <- 1..operations_per_process do
                  agent_id = :"concurrent_#{i}_#{j}"
                  
                  # Register
                  Registry.register(nil, agent_id, self())
                  
                  # Lookup
                  Registry.lookup(nil, agent_id)
                  
                  # Small delay to avoid overwhelming
                  if rem(j, 10) == 0, do: :timer.sleep(1)
                end
              end)
            end
            
            Task.await_many(tasks, 60_000)
          end)
          
          total_operations = num_processes * operations_per_process * 2  # register + lookup
          avg_time_per_op = total_time / total_operations
          
          assert avg_time_per_op < @registry_operation_threshold,
                 """
                 Concurrent registry operations too slow:
                 Average time per operation: #{Float.round(avg_time_per_op, 2)}μs
                 Threshold: #{@registry_operation_threshold}μs
                 """
          
        {:error, :nofile} ->
          :ok
      end
    end
    
    defp benchmark_registry_operations(count, label) do
      {time, _} = :timer.tc(fn ->
        for i <- 1..count do
          agent_id = :"benchmark_#{label}_#{i}"
          
          # Register agent
          Registry.register(nil, agent_id, self())
          
          # Lookup agent
          Registry.lookup(nil, agent_id)
        end
      end)
      
      avg_time = time / (count * 2)  # 2 operations per iteration
      avg_time
    end
  end
  
  describe "Error Context Performance Tests" do
    test "Logger metadata vs Process dictionary performance" do
      # Benchmark legacy Process dictionary implementation
      FeatureFlags.disable(:use_logger_error_context)
      
      legacy_time = benchmark_error_context_operations(1000, "legacy")
      
      # Benchmark new Logger metadata implementation  
      FeatureFlags.enable(:use_logger_error_context)
      
      logger_time = benchmark_error_context_operations(1000, "logger")
      
      # Logger metadata should be reasonably fast
      slowdown_ratio = logger_time / legacy_time
      
      # Allow some slowdown since Logger metadata is more feature-rich
      assert slowdown_ratio < 5.0,
             """
             Logger metadata significantly slower than Process dictionary:
             Legacy: #{legacy_time}μs
             Logger: #{logger_time}μs  
             Slowdown: #{Float.round(slowdown_ratio, 2)}x
             """
      
      # Absolute performance check
      operations_per_second = 1_000_000 / (logger_time / 1000)
      assert operations_per_second > 50_000,
             "Error context operations too slow: #{Float.round(operations_per_second)} ops/sec"
    end
    
    test "error context memory usage" do
      FeatureFlags.enable(:use_logger_error_context)
      
      initial_memory = :erlang.memory(:total)
      
      # Create many error contexts
      for i <- 1..10_000 do
        ErrorContext.set_context(%{
          request_id: "req_#{i}",
          user_id: i,
          timestamp: System.system_time(:millisecond),
          operation: "performance_test",
          metadata: %{
            ip: "192.168.1.#{rem(i, 255)}",
            user_agent: "TestAgent/1.0"
          }
        })
        
        # Occasionally clear to test cleanup
        if rem(i, 1000) == 0 do
          ErrorContext.clear_context()
        end
      end
      
      # Force garbage collection
      :erlang.garbage_collect()
      
      final_memory = :erlang.memory(:total)
      memory_growth = final_memory - initial_memory
      
      # Memory growth should be reasonable
      assert memory_growth < 50_000_000,  # 50MB
             "Excessive memory usage in error context: #{memory_growth} bytes"
    end
    
    test "concurrent error context access" do
      FeatureFlags.enable(:use_logger_error_context)
      
      num_processes = 20
      operations_per_process = 500
      
      {total_time, _} = :timer.tc(fn ->
        tasks = for i <- 1..num_processes do
          Task.async(fn ->
            for j <- 1..operations_per_process do
              context = %{
                process: i,
                operation: j,
                timestamp: System.system_time(:millisecond)
              }
              
              ErrorContext.set_context(context)
              retrieved = ErrorContext.get_context()
              
              assert retrieved.process == i
              assert retrieved.operation == j
            end
          end)
        end
        
        Task.await_many(tasks, 60_000)
      end)
      
      total_operations = num_processes * operations_per_process * 2  # set + get
      avg_time_per_op = total_time / total_operations
      
      assert avg_time_per_op < @error_context_threshold,
             """
             Concurrent error context operations too slow:
             Average time per operation: #{Float.round(avg_time_per_op, 2)}μs
             Threshold: #{@error_context_threshold}μs
             """
    end
    
    defp benchmark_error_context_operations(count, label) do
      {time, _} = :timer.tc(fn ->
        for i <- 1..count do
          context = %{
            test: label,
            iteration: i,
            timestamp: System.system_time(:millisecond)
          }
          
          ErrorContext.set_context(context)
          ErrorContext.get_context()
        end
      end)
      
      avg_time = time / (count * 2)  # 2 operations per iteration
      avg_time
    end
  end
  
  describe "Telemetry Performance Tests" do
    test "span creation and management performance" do
      # Test span creation speed
      {span_creation_time, span_ids} = :timer.tc(fn ->
        for i <- 1..1000 do
          Span.start_span("performance_test_#{i}", %{iteration: i})
        end
      end)
      
      avg_span_creation = span_creation_time / 1000
      
      assert avg_span_creation < @span_operation_threshold,
             """
             Span creation too slow:
             Average time: #{Float.round(avg_span_creation, 2)}μs
             Threshold: #{@span_operation_threshold}μs
             """
      
      # Test span ending speed
      {span_ending_time, _} = :timer.tc(fn ->
        Enum.each(span_ids, &Span.end_span/1)
      end)
      
      avg_span_ending = span_ending_time / 1000
      
      assert avg_span_ending < @span_operation_threshold,
             """
             Span ending too slow:
             Average time: #{Float.round(avg_span_ending, 2)}μs
             Threshold: #{@span_operation_threshold}μs
             """
    end
    
    test "nested span performance" do
      max_depth = 20
      
      {nested_time, _} = :timer.tc(fn ->
        # Create deeply nested spans
        span_ids = for depth <- 1..max_depth do
          Span.start_span("nested_#{depth}", %{depth: depth})
        end
        
        # End them in reverse order
        Enum.reverse(span_ids) |> Enum.each(&Span.end_span/1)
      end)
      
      avg_nested_operation = nested_time / (max_depth * 2)
      
      assert avg_nested_operation < @span_operation_threshold,
             """
             Nested span operations too slow:
             Average time: #{Float.round(avg_nested_operation, 2)}μs
             Threshold: #{@span_operation_threshold}μs
             """
    end
    
    test "with_span performance" do
      num_operations = 1000
      
      {with_span_time, _} = :timer.tc(fn ->
        for i <- 1..num_operations do
          Span.with_span("performance_operation_#{i}", %{iteration: i}, fn ->
            # Simulate small amount of work
            :erlang.phash2(i)
          end)
        end
      end)
      
      avg_with_span = with_span_time / num_operations
      
      assert avg_with_span < @span_operation_threshold * 2,  # Allow 2x for convenience wrapper
             """
             with_span operations too slow:
             Average time: #{Float.round(avg_with_span, 2)}μs
             Threshold: #{@span_operation_threshold * 2}μs
             """
    end
    
    test "sampled events performance" do
      FeatureFlags.enable(:use_ets_sampled_events)
      
      # Start sampled events service if available
      case Code.ensure_loaded?(Foundation.Telemetry.SampledEvents) do
        {:module, _} ->
          {:ok, _} = Foundation.Telemetry.SampledEvents.start_link()
          
          # Test regular event emission
          {emit_time, _} = :timer.tc(fn ->
            for i <- 1..1000 do
              SampledEvents.emit_event(
                [:performance, :test],
                %{count: 1},
                %{iteration: i, dedup_key: "key_#{rem(i, 100)}"}
              )
            end
          end)
          
          avg_emit_time = emit_time / 1000
          
          assert avg_emit_time < @batch_operation_threshold,
                 """
                 Sampled event emission too slow:
                 Average time: #{Float.round(avg_emit_time, 2)}μs
                 Threshold: #{@batch_operation_threshold}μs
                 """
          
          # Test batched events
          {batch_time, _} = :timer.tc(fn ->
            for i <- 1..1000 do
              SampledEvents.emit_batched(
                [:performance, :batch],
                i,
                %{batch_key: "batch_#{rem(i, 10)}"}
              )
            end
          end)
          
          avg_batch_time = batch_time / 1000
          
          assert avg_batch_time < @batch_operation_threshold,
                 """
                 Batched event emission too slow:
                 Average time: #{Float.round(avg_batch_time, 2)}μs
                 Threshold: #{@batch_operation_threshold}μs
                 """
          
        {:error, :nofile} ->
          :ok
      end
    end
  end
  
  describe "Combined Workload Performance Tests" do
    test "realistic application workload" do
      FeatureFlags.enable_otp_cleanup_stage(4)
      
      # Simulate realistic application load
      num_requests = 1000
      
      {total_time, _} = :timer.tc(fn ->
        tasks = for i <- 1..num_requests do
          Task.async(fn ->
            # Simulate incoming request
            request_id = "req_#{i}"
            
            # Set error context
            ErrorContext.set_context(%{
              request_id: request_id,
              user_id: rem(i, 100),
              timestamp: System.system_time(:millisecond)
            })
            
            # Start request span
            Span.with_span("handle_request", %{request_id: request_id}, fn ->
              # Register agent for request
              agent_id = :"request_agent_#{i}"
              Registry.register(nil, agent_id, self())
              
              # Perform some operations
              for j <- 1..5 do
                Span.with_span("operation_#{j}", %{step: j}, fn ->
                  # Lookup agent
                  {:ok, {_pid, _}} = Registry.lookup(nil, agent_id)
                  
                  # Emit telemetry
                  :telemetry.execute(
                    [:app, :operation, :completed],
                    %{duration: j * 10},
                    %{request_id: request_id, step: j}
                  )
                  
                  # Small delay to simulate work
                  :timer.sleep(1)
                end)
              end
              
              # Cleanup
              try do
                Registry.unregister(nil, agent_id)
              rescue
                _ -> :ok
              end
            end)
          end)
        end
        
        Task.await_many(tasks, 120_000)
      end)
      
      avg_request_time = total_time / num_requests
      requests_per_second = 1_000_000 / avg_request_time
      
      # Should handle at least 100 requests per second
      assert requests_per_second > 100,
             """
             Application workload performance too slow:
             Average request time: #{Float.round(avg_request_time, 2)}μs
             Requests per second: #{Float.round(requests_per_second, 2)}
             """
      
      # Total time should be reasonable
      assert total_time < 30_000_000,  # 30 seconds
             "Total workload time too slow: #{total_time / 1_000_000} seconds"
    end
    
    test "memory efficiency under load" do
      FeatureFlags.enable_otp_cleanup_stage(4)
      
      initial_memory = :erlang.memory(:total)
      initial_processes = :erlang.system_info(:process_count)
      
      # Run multiple rounds of workload
      for round <- 1..5 do
        # Create burst of activity
        tasks = for i <- 1..200 do
          Task.async(fn ->
            agent_id = :"memory_test_#{round}_#{i}"
            
            ErrorContext.set_context(%{
              round: round,
              agent: i,
              timestamp: System.system_time(:millisecond)
            })
            
            span_id = Span.start_span("memory_test", %{round: round, agent: i})
            
            Registry.register(nil, agent_id, self())
            Registry.lookup(nil, agent_id)
            
            # Simulate some work
            :timer.sleep(5)
            
            Span.end_span(span_id)
            ErrorContext.clear_context()
          end)
        end
        
        Task.await_many(tasks, 30_000)
        
        # Force garbage collection between rounds
        :erlang.garbage_collect()
        # Brief pause to allow cleanup
        :timer.sleep(10)
      end
      
      final_memory = :erlang.memory(:total)
      final_processes = :erlang.system_info(:process_count)
      
      memory_growth = final_memory - initial_memory
      process_growth = final_processes - initial_processes
      
      # Memory should not grow excessively
      assert memory_growth < 100_000_000,  # 100MB
             "Excessive memory growth under load: #{memory_growth} bytes"
      
      # Process count should return to baseline
      assert process_growth < 50,
             "Process leak under load: #{process_growth} extra processes"
    end
  end
  
  describe "Performance Comparison Matrix" do
    test "performance matrix for all implementations" do
      # Test matrix of different flag combinations
      test_cases = [
        %{name: "all_legacy", flags: []},
        %{name: "ets_only", flags: [:use_ets_agent_registry]},
        %{name: "logger_only", flags: [:use_logger_error_context]},
        %{name: "telemetry_only", flags: [:use_genserver_telemetry]},
        %{name: "all_new", flags: [:use_ets_agent_registry, :use_logger_error_context, :use_genserver_telemetry]}
      ]
      
      results = for test_case <- test_cases do
        # Reset flags
        FeatureFlags.reset_all()
        
        # Enable specified flags
        Enum.each(test_case.flags, &FeatureFlags.enable/1)
        
        # Run benchmark
        {time, _} = :timer.tc(fn ->
          benchmark_mixed_workload(100)
        end)
        
        %{
          name: test_case.name,
          flags: test_case.flags,
          time: time,
          ops_per_sec: 100 * 1_000_000 / time
        }
      end
      
      # Find baseline (all legacy)
      baseline = Enum.find(results, &(&1.name == "all_legacy"))
      
      # Check that new implementations are not dramatically slower
      for result <- results do
        unless result.name == "all_legacy" do
          slowdown = result.time / baseline.time
          
          assert slowdown < 3.0,
                 """
                 Implementation #{result.name} significantly slower than baseline:
                 Baseline (all_legacy): #{Float.round(baseline.ops_per_sec, 2)} ops/sec
                 #{result.name}: #{Float.round(result.ops_per_sec, 2)} ops/sec
                 Slowdown: #{Float.round(slowdown, 2)}x
                 """
        end
      end
      
      # Log results for analysis
      IO.puts("\n=== Performance Comparison Matrix ===")
      for result <- results do
        IO.puts("#{result.name}: #{Float.round(result.ops_per_sec, 2)} ops/sec")
      end
    end
    
    defp benchmark_mixed_workload(iterations) do
      for i <- 1..iterations do
        # Mixed operations
        ErrorContext.set_context(%{test: i})
        
        Registry.register(nil, :"mixed_#{i}", self())
        Registry.lookup(nil, :"mixed_#{i}")
        
        span_id = Span.start_span("mixed_operation", %{iteration: i})
        Span.end_span(span_id)
        
        ErrorContext.get_context()
      end
    end
  end
end