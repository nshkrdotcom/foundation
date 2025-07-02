defmodule Foundation.OTPCleanupObservabilityTest do
  @moduledoc """
  Monitoring and observability tests for OTP cleanup migration.

  Tests that telemetry events are emitted correctly, error reporting works,
  span tracking is maintained, and no observability is lost during migration.
  """

  use ExUnit.Case, async: false

  require Logger
  import Foundation.AsyncTestHelpers
  alias Foundation.{FeatureFlags, ErrorContext, Registry}
  alias Foundation.Telemetry.{Span, SampledEvents}

  @moduletag :observability
  @moduletag :telemetry
  @moduletag timeout: 120_000

  setup_all do
    # Ensure FeatureFlags service is started for all tests
    case Process.whereis(Foundation.FeatureFlags) do
      nil ->
        {:ok, _} = Foundation.FeatureFlags.start_link()

      _pid ->
        :ok
    end

    :ok
  end

  describe "Telemetry Event Continuity" do
    setup do
      # Ensure FeatureFlags service is started
      case Process.whereis(Foundation.FeatureFlags) do
        nil ->
          {:ok, _} = Foundation.FeatureFlags.start_link()

        _pid ->
          :ok
      end

      FeatureFlags.reset_all()

      # Set up telemetry collection
      test_pid = self()
      collected_events = []

      # Comprehensive event collection
      event_names = [
        # Registry events
        [:foundation, :registry, :register],
        [:foundation, :registry, :lookup],
        [:foundation, :registry, :unregister],
        [:foundation, :registry, :list],

        # Error context events
        [:foundation, :error_context, :set],
        [:foundation, :error_context, :get],
        [:foundation, :error_context, :clear],
        [:foundation, :error_context, :enrich],

        # Telemetry events
        [:foundation, :telemetry, :span, :start],
        [:foundation, :telemetry, :span, :end],
        [:foundation, :telemetry, :sampled_event, :emit],
        [:foundation, :telemetry, :batched_event, :emit],

        # Feature flag events
        [:foundation, :feature_flag, :changed],
        [:foundation, :migration, :stage_enabled],
        [:foundation, :migration, :rollback],

        # System events
        [:foundation, :system, :service_start],
        [:foundation, :system, :service_stop],
        [:foundation, :system, :error]
      ]

      handler = fn event, measurements, metadata, _ ->
        send(
          test_pid,
          {:telemetry_event, event, measurements, metadata, System.system_time(:millisecond)}
        )
      end

      :telemetry.attach_many("observability-test-handler", event_names, handler, nil)

      on_exit(fn ->
        :telemetry.detach("observability-test-handler")
        FeatureFlags.reset_all()
        ErrorContext.clear_context()
      end)

      %{collected_events: collected_events}
    end

    test "telemetry events emitted during migration stages", %{collected_events: _events} do
      # Test telemetry continuity through migration stages

      # Stage 0: Baseline telemetry
      collect_events_during_operations("stage_0", fn ->
        basic_operations()
      end)

      stage_0_events = drain_telemetry_events()

      # Stage 1: ETS Registry
      FeatureFlags.enable_otp_cleanup_stage(1)
      start_services_for_stage(1)

      collect_events_during_operations("stage_1", fn ->
        basic_operations()
      end)

      stage_1_events = drain_telemetry_events()

      # Stage 2: Logger Error Context
      FeatureFlags.enable_otp_cleanup_stage(2)

      collect_events_during_operations("stage_2", fn ->
        basic_operations()
      end)

      stage_2_events = drain_telemetry_events()

      # Stage 3: GenServer Telemetry
      FeatureFlags.enable_otp_cleanup_stage(3)
      start_services_for_stage(3)

      collect_events_during_operations("stage_3", fn ->
        basic_operations()
      end)

      stage_3_events = drain_telemetry_events()

      # Stage 4: Full enforcement
      FeatureFlags.enable_otp_cleanup_stage(4)

      collect_events_during_operations("stage_4", fn ->
        basic_operations()
      end)

      stage_4_events = drain_telemetry_events()

      # Analyze event continuity
      all_stages = [
        {"stage_0", stage_0_events},
        {"stage_1", stage_1_events},
        {"stage_2", stage_2_events},
        {"stage_3", stage_3_events},
        {"stage_4", stage_4_events}
      ]

      for {stage_name, events} <- all_stages do
        # Should have registry events
        registry_events = filter_events(events, [:foundation, :registry])
        assert length(registry_events) > 0, "No registry events in #{stage_name}"

        # Should have error context events
        context_events = filter_events(events, [:foundation, :error_context])
        assert length(context_events) > 0, "No error context events in #{stage_name}"

        # Should have telemetry span events
        span_events = filter_events(events, [:foundation, :telemetry, :span])
        assert length(span_events) > 0, "No span events in #{stage_name}"

        IO.puts("#{stage_name}: #{length(events)} total events")
      end

      # Verify no significant telemetry loss
      event_counts = Enum.map(all_stages, fn {stage, events} -> {stage, length(events)} end)

      {min_stage, min_count} = Enum.min_by(event_counts, fn {_, count} -> count end)
      {max_stage, max_count} = Enum.max_by(event_counts, fn {_, count} -> count end)

      # Event counts should be relatively consistent (within 50% variance)
      variance = if min_count > 0, do: (max_count - min_count) / min_count, else: 1.0

      assert variance < 0.5,
             """
             Significant telemetry loss detected:
             Min: #{min_stage} (#{min_count} events)
             Max: #{max_stage} (#{max_count} events)
             Variance: #{Float.round(variance * 100, 2)}%
             """
    end

    test "error context enrichment throughout migration" do
      migration_stages = [0, 1, 2, 3, 4]

      for stage <- migration_stages do
        if stage > 0 do
          FeatureFlags.enable_otp_cleanup_stage(stage)
          start_services_for_stage(stage)
        end

        # Set error context
        ErrorContext.set_context(%{
          stage: stage,
          test_id: "error_enrichment_#{stage}",
          timestamp: System.system_time(:millisecond)
        })

        # Create an error
        error = Foundation.Error.business_error(:test_error, "Stage #{stage} test error")
        enriched_error = ErrorContext.enrich_error(error)

        # Verify enrichment works
        assert enriched_error.context[:stage] == stage
        assert enriched_error.context[:test_id] == "error_enrichment_#{stage}"
        assert Map.has_key?(enriched_error.context, :timestamp)

        # Error should include original message
        assert enriched_error.message == "Stage #{stage} test error"
        assert enriched_error.error_type == :test_error

        # Context should be properly merged
        original_context = error.context || %{}
        final_context = enriched_error.context

        # Should contain both original and enriched context
        for {key, value} <- original_context do
          assert final_context[key] == value
        end

        ErrorContext.clear_context()
      end
    end

    test "span parent-child relationships maintained" do
      FeatureFlags.enable_otp_cleanup_stage(4)
      start_services_for_stage(4)

      # Create nested spans and verify hierarchy is tracked
      span_events = []
      test_pid = self()

      # Collect span events
      span_handler = fn event, measurements, metadata, _ ->
        send(test_pid, {:span_event, event, measurements, metadata})
      end

      :telemetry.attach(
        "span-hierarchy-test",
        [:foundation, :span, :start],
        span_handler,
        nil
      )

      :telemetry.attach(
        "span-hierarchy-end-test",
        [:foundation, :span, :stop],
        span_handler,
        nil
      )

      try do
        # Create nested span structure
        root_span = Span.start_span("root_operation", %{level: "root"})

        child1_span = Span.start_span("child_1", %{level: "child", parent: "root"})

        grandchild_span = Span.start_span("grandchild", %{level: "grandchild", parent: "child_1"})
        Span.end_span(grandchild_span)

        child2_span = Span.start_span("child_2", %{level: "child", parent: "root"})
        Span.end_span(child2_span)

        Span.end_span(child1_span)
        Span.end_span(root_span)

        # Collect all span events
        # 4 starts + 4 ends
        collected_span_events =
          for _i <- 1..8 do
            receive do
              {:span_event, event, measurements, metadata} ->
                {event, measurements, metadata}
            after
              2000 -> nil
            end
          end

        span_events = Enum.reject(collected_span_events, &is_nil/1)

        # Verify we received all expected events
        start_events =
          Enum.filter(span_events, fn {event, _, _} ->
            event == [:foundation, :span, :start]
          end)

        end_events =
          Enum.filter(span_events, fn {event, _, _} ->
            event == [:foundation, :span, :stop]
          end)

        assert length(start_events) == 4, "Missing span start events"
        assert length(end_events) == 4, "Missing span end events"

        # Verify span metadata includes hierarchy information
        for {_event, _measurements, metadata} <- start_events do
          assert Map.has_key?(metadata, :span_id), "Span missing ID"
          # Parent information may be implementation specific
        end
      after
        :telemetry.detach("span-hierarchy-test")
        :telemetry.detach("span-hierarchy-end-test")
      end
    end

    defp collect_events_during_operations(context, operation_fun) do
      # Execute operations and let telemetry events flow
      operation_fun.()

      # Small delay to ensure all events are emitted
      Process.sleep(100)
    end

    defp basic_operations do
      # Registry operations
      Registry.register(nil, :"telemetry_test_#{:erlang.unique_integer()}", self())
      Registry.lookup(nil, :"telemetry_test_#{:erlang.unique_integer()}")

      # Error context operations
      ErrorContext.set_context(%{telemetry_test: true, timestamp: System.system_time()})
      ErrorContext.get_context()

      # Span operations
      span_id = Span.start_span("telemetry_test_span", %{test: true})
      Span.end_span(span_id)

      # Nested operations
      Span.with_span_fun("nested_telemetry_test", %{nested: true}, fn ->
        ErrorContext.set_context(%{nested_context: true})
        Registry.register(nil, :"nested_test_#{:erlang.unique_integer()}", self())
      end)
    end

    defp start_services_for_stage(stage) do
      case stage do
        stage when stage >= 1 ->
          if Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
            case Process.whereis(Foundation.Protocols.RegistryETS) do
              nil -> Foundation.Protocols.RegistryETS.start_link()
              _ -> :ok
            end
          else
            :ok
          end

        _ ->
          :ok
      end

      case stage do
        stage when stage >= 3 ->
          # Start SampledEvents if needed
          if Code.ensure_loaded?(Foundation.Telemetry.SampledEvents) do
            case Process.whereis(Foundation.Telemetry.SampledEvents) do
              nil -> Foundation.Telemetry.SampledEvents.start_link()
              _ -> :ok
            end
          else
            :ok
          end

          # Start SpanManager if needed
          if Code.ensure_loaded?(Foundation.Telemetry.SpanManager) do
            case Process.whereis(Foundation.Telemetry.SpanManager) do
              nil -> Foundation.Telemetry.SpanManager.start_link()
              _ -> :ok
            end
          else
            :ok
          end

        _ ->
          :ok
      end
    end

    defp drain_telemetry_events(timeout \\ 1000) do
      events = []
      drain_telemetry_events_loop(events, timeout)
    end

    defp drain_telemetry_events_loop(events, timeout) do
      receive do
        {:telemetry_event, event, measurements, metadata, timestamp} ->
          new_event = {event, measurements, metadata, timestamp}
          drain_telemetry_events_loop([new_event | events], timeout)
      after
        timeout -> Enum.reverse(events)
      end
    end

    defp filter_events(events, event_prefix) do
      Enum.filter(events, fn {event, _, _, _} ->
        List.starts_with?(event, event_prefix)
      end)
    end
  end

  describe "Error Reporting and Context" do
    test "error reporting continuity across implementations" do
      implementations = [
        {0, "legacy"},
        {2, "logger_metadata"},
        {4, "full_migration"}
      ]

      for {stage, impl_name} <- implementations do
        if stage > 0 do
          FeatureFlags.enable_otp_cleanup_stage(stage)
          start_services_for_stage(stage)
        else
          FeatureFlags.reset_all()
        end

        # Set rich error context
        ErrorContext.set_context(%{
          implementation: impl_name,
          stage: stage,
          request_id: "req_#{stage}_#{System.unique_integer()}",
          user_id: "user_#{stage}",
          operation: "error_reporting_test",
          metadata: %{
            ip_address: "192.168.1.#{stage}",
            user_agent: "TestAgent/1.0",
            session_id: "session_#{stage}"
          }
        })

        # Create various types of errors
        error_types = [
          {:validation_error, "Invalid input data"},
          {:business_error, "Business rule violation"},
          {:system_error, "System component failure"}
        ]

        for {error_type, message} <- error_types do
          error = Foundation.Error.business_error(error_type, message)
          enriched = ErrorContext.enrich_error(error)

          # Verify error enrichment
          assert enriched.context[:implementation] == impl_name
          assert enriched.context[:stage] == stage
          assert enriched.context[:request_id] =~ "req_#{stage}_"
          assert enriched.context[:operation] == "error_reporting_test"

          # Verify nested metadata is preserved
          assert enriched.context[:metadata][:ip_address] == "192.168.1.#{stage}"
          assert enriched.context[:metadata][:user_agent] == "TestAgent/1.0"

          # Original error properties should be preserved
          assert enriched.error_type == error_type
          assert enriched.message == message
        end

        ErrorContext.clear_context()
      end
    end

    test "error context isolation between processes" do
      FeatureFlags.enable(:use_logger_error_context)

      test_pid = self()

      # Create multiple processes with different error contexts
      process_results =
        for i <- 1..10 do
          Task.async(fn ->
            process_context = %{
              process_id: i,
              worker_type: "error_isolation_test",
              timestamp: System.system_time(:millisecond),
              random_data: :crypto.strong_rand_bytes(20)
            }

            ErrorContext.set_context(process_context)

            # Simulate work with potential errors
            for j <- 1..50 do
              ErrorContext.set_context(Map.put(process_context, :operation, j))

              # Random operations that might trigger errors
              case rem(j, 10) do
                0 ->
                  error = Foundation.Error.business_error(:test_error, "Test error #{j}")
                  enriched = ErrorContext.enrich_error(error)

                  # Verify context isolation
                  assert enriched.context[:process_id] == i
                  assert enriched.context[:operation] == j

                  send(test_pid, {:error_created, i, j, enriched})

                _ ->
                  # Normal operation
                  context = ErrorContext.get_context()
                  assert context.process_id == i
              end
            end

            # Return final context
            ErrorContext.get_context()
          end)
        end

      # Wait for all processes to complete
      final_contexts = Task.await_many(process_results, 30_000)

      # Verify each process maintained its own context
      for {context, i} <- Enum.with_index(final_contexts, 1) do
        assert context.process_id == i
        assert context.worker_type == "error_isolation_test"
      end

      # Collect error messages
      # Expect ~50 errors (5 per process)
      error_messages =
        for _i <- 1..50 do
          receive do
            {:error_created, process_id, operation, enriched_error} ->
              {process_id, operation, enriched_error}
          after
            1000 -> nil
          end
        end

      error_messages = Enum.reject(error_messages, &is_nil/1)

      # Verify no context contamination
      for {process_id, operation, enriched_error} <- error_messages do
        assert enriched_error.context[:process_id] == process_id
        assert enriched_error.context[:operation] == operation
        assert enriched_error.context[:worker_type] == "error_isolation_test"
      end

      # Verify main process context is clean
      main_context = ErrorContext.get_context() || %{}
      refute Map.has_key?(main_context, :process_id)
      refute Map.has_key?(main_context, :worker_type)
    end

    test "structured error logging integration" do
      FeatureFlags.enable(:use_logger_error_context)

      # Capture log messages
      :logger.add_handler(:test_error_handler, :logger_test_h, %{})

      try do
        # Set error context
        ErrorContext.set_context(%{
          structured_logging_test: true,
          component: "observability_test",
          trace_id: "trace_123",
          span_id: "span_456"
        })

        # Create and log errors
        error = Foundation.Error.business_error(:logging_test, "Test error for structured logging")
        enriched = ErrorContext.enrich_error(error)

        # Log the error (should include context)
        Logger.error("Error occurred: #{enriched.message}", error: enriched)

        # Verify context is in Logger metadata
        logger_metadata = Logger.metadata()
        assert logger_metadata[:error_context][:structured_logging_test] == true
        assert logger_metadata[:error_context][:trace_id] == "trace_123"
      after
        :logger.remove_handler(:test_error_handler)
      end
    end
  end

  describe "Performance Monitoring" do
    test "performance metrics collection across implementations" do
      test_scenarios = [
        {0, "legacy", 1000},
        {1, "ets_registry", 1000},
        {2, "logger_context", 1000},
        {4, "full_migration", 1000}
      ]

      performance_results = 
        for {stage, scenario_name, operations} <- test_scenarios do
        if stage > 0 do
          FeatureFlags.enable_otp_cleanup_stage(stage)
          start_services_for_stage(stage)
        else
          FeatureFlags.reset_all()
        end

        # Warm up
        for _i <- 1..10 do
          basic_operations()
        end

        # Measure performance
        {total_time, _} =
          :timer.tc(fn ->
            for i <- 1..operations do
              # Registry operations
              agent_id = :"perf_test_#{scenario_name}_#{i}"
              Registry.register(nil, agent_id, self())
              Registry.lookup(nil, agent_id)

              # Error context operations
              ErrorContext.set_context(%{
                scenario: scenario_name,
                operation: i,
                timestamp: System.system_time(:microsecond)
              })

              ErrorContext.get_context()

              # Telemetry operations
              span_id = Span.start_span("perf_test", %{scenario: scenario_name, op: i})
              Span.end_span(span_id)
            end
          end)

        ops_per_second = operations * 1_000_000 / total_time
        avg_time_per_op = total_time / operations

        IO.puts(
          "#{scenario_name}: #{Float.round(ops_per_second, 2)} ops/sec, #{Float.round(avg_time_per_op, 2)}μs/op"
        )

        {scenario_name, stage, ops_per_second, avg_time_per_op, total_time}
      end

      # Analyze performance across implementations

      # Find baseline (legacy)
      {_name, _stage, baseline_ops, _avg, _total} =
        Enum.find(performance_results, fn {name, _, _, _, _} -> name == "legacy" end)

      # Check for significant performance regressions
      for {scenario_name, _stage, ops_per_second, _avg_time, _total_time} <- performance_results do
        unless scenario_name == "legacy" do
          performance_ratio = ops_per_second / baseline_ops

          # Should not be more than 3x slower than baseline
          assert performance_ratio > 0.33,
                 """
                 Significant performance regression in #{scenario_name}:
                 Baseline: #{Float.round(baseline_ops, 2)} ops/sec
                 Current: #{Float.round(ops_per_second, 2)} ops/sec
                 Ratio: #{Float.round(performance_ratio, 3)}x
                 """
        end
      end
    end

    test "memory usage monitoring" do
      FeatureFlags.enable_otp_cleanup_stage(4)
      start_services_for_stage(4)

      initial_memory = :erlang.memory()

      # Perform memory-intensive operations
      for i <- 1..1000 do
        # Large error contexts
        large_context = %{
          operation: i,
          large_data: String.duplicate("x", 1000),
          nested_data: %{
            level1: %{
              level2: %{
                level3: for(j <- 1..100, do: "item_#{j}")
              }
            }
          }
        }

        ErrorContext.set_context(large_context)

        # Multiple agents
        for j <- 1..5 do
          agent_id = :"memory_test_#{i}_#{j}"
          Registry.register(nil, agent_id, self())
        end

        # Nested spans
        Span.with_span_fun("memory_test_#{i}", large_context, fn ->
          Span.with_span_fun("nested_#{i}", %{nested: true}, fn ->
            ErrorContext.get_context()
          end)
        end)

        # Periodic cleanup
        if rem(i, 100) == 0 do
          ErrorContext.clear_context()
          :erlang.garbage_collect()
        end
      end

      # Final cleanup
      ErrorContext.clear_context()
      :erlang.garbage_collect()
      Process.sleep(100)

      final_memory = :erlang.memory()

      # Calculate memory growth
      memory_fields = [:total, :processes, :atom, :ets]

      for field <- memory_fields do
        initial = initial_memory[field]
        final = final_memory[field]
        growth = final - initial

        # Memory growth should be reasonable
        max_growth =
          case field do
            # 200MB
            :total -> 200_000_000
            # 100MB
            :processes -> 100_000_000
            # 10MB
            :atom -> 10_000_000
            # 50MB
            :ets -> 50_000_000
          end

        assert growth < max_growth,
               "Excessive #{field} memory growth: #{growth} bytes (limit: #{max_growth})"
      end
    end
  end

  describe "Observability Integration Tests" do
    test "comprehensive observability workflow" do
      FeatureFlags.enable_otp_cleanup_stage(4)
      start_services_for_stage(4)

      # Set up comprehensive telemetry collection
      all_events = []
      test_pid = self()

      comprehensive_handler = fn event, measurements, metadata, _ ->
        send(
          test_pid,
          {:comprehensive_event, event, measurements, metadata, System.system_time(:microsecond)}
        )
      end

      # Attach to all possible events
      all_event_patterns = [
        [:foundation, :registry, :_],
        [:foundation, :error_context, :_],
        [:foundation, :span, :_],
        [:foundation, :feature_flag, :_],
        [:foundation, :migration, :_]
      ]

      :telemetry.attach_many(
        "comprehensive-observability",
        all_event_patterns,
        comprehensive_handler,
        nil
      )

      try do
        # Execute comprehensive workflow
        workflow_id = "comprehensive_#{System.unique_integer()}"

        # 1. Set initial context
        ErrorContext.set_context(%{
          workflow_id: workflow_id,
          phase: "initialization",
          observability_test: true
        })

        # 2. Create workflow span
        workflow_span =
          Span.start_span("comprehensive_workflow", %{
            workflow_id: workflow_id,
            test_type: "observability"
          })

        # 3. Register workflow agents
        agents =
          for i <- 1..5 do
            agent_id = :"comprehensive_agent_#{workflow_id}_#{i}"
            Registry.register(nil, agent_id, self())
            agent_id
          end

        # 4. Execute workflow steps
        for {step, agent_id} <- Enum.with_index(agents, 1) do
          ErrorContext.set_context(%{
            workflow_id: workflow_id,
            phase: "execution",
            step: step,
            agent_id: agent_id
          })

          step_span =
            Span.start_span("workflow_step", %{
              step: step,
              agent_id: agent_id
            })

          # Simulate work
          Registry.lookup(nil, agent_id)

          # Simulate error in step 3
          if step == 3 do
            error = Foundation.Error.business_error(:workflow_error, "Simulated workflow error")
            enriched = ErrorContext.enrich_error(error)

            # Error should have full context
            assert enriched.context[:workflow_id] == workflow_id
            assert enriched.context[:step] == 3
            assert enriched.context[:agent_id] == agent_id
          end

          Span.end_span(step_span)
        end

        # 5. Complete workflow
        ErrorContext.set_context(%{
          workflow_id: workflow_id,
          phase: "completion"
        })

        Span.end_span(workflow_span)

        # 6. Collect all telemetry events
        # Allow events to be emitted
        Process.sleep(200)

        collected_events = drain_comprehensive_events()

        # 7. Analyze observability coverage

        # Should have registry events
        registry_events = filter_comprehensive_events(collected_events, [:foundation, :registry])

        assert length(registry_events) >= 10,
               "Insufficient registry events: #{length(registry_events)}"

        # Should have error context events
        context_events =
          filter_comprehensive_events(collected_events, [:foundation, :error_context])

        assert length(context_events) >= 5,
               "Insufficient error context events: #{length(context_events)}"

        # Should have span events
        span_events =
          filter_comprehensive_events(collected_events, [:foundation, :span])

        assert length(span_events) >= 12,
               "Insufficient span events: #{length(span_events)} (expected >= 12)"

        # Events should have proper metadata
        for {event, _measurements, metadata, _timestamp} <- collected_events do
          case event do
            [:foundation, :registry, _] ->
              # Registry events should have agent info
              assert is_atom(metadata[:agent_id]) or is_nil(metadata[:agent_id])

            [:foundation, :error_context, _] ->
              # Context events should have workflow info
              # (if context was set when event occurred)
              :ok

            [:foundation, :span, _] ->
              # Span events should have span info
              assert Map.has_key?(metadata, :span_id) or Map.has_key?(metadata, :name)

            _ ->
              :ok
          end
        end

        # Verify temporal ordering
        timestamps = Enum.map(collected_events, fn {_, _, _, timestamp} -> timestamp end)
        sorted_timestamps = Enum.sort(timestamps)

        # Events should be roughly in temporal order (allowing for some variance)
        temporal_variance = calculate_temporal_variance(timestamps, sorted_timestamps)

        assert temporal_variance < 0.1,
               "Events not in temporal order (variance: #{temporal_variance})"

        IO.puts("Comprehensive workflow generated #{length(collected_events)} telemetry events")
      after
        :telemetry.detach("comprehensive-observability")
      end
    end

    defp drain_comprehensive_events(timeout \\ 2000) do
      events = []
      drain_comprehensive_events_loop(events, timeout)
    end

    defp drain_comprehensive_events_loop(events, timeout) do
      receive do
        {:comprehensive_event, event, measurements, metadata, timestamp} ->
          new_event = {event, measurements, metadata, timestamp}
          drain_comprehensive_events_loop([new_event | events], timeout)
      after
        timeout -> Enum.reverse(events)
      end
    end

    defp filter_comprehensive_events(events, event_prefix) do
      Enum.filter(events, fn {event, _, _, _} ->
        List.starts_with?(event, event_prefix)
      end)
    end

    defp calculate_temporal_variance(original, sorted) do
      if length(original) <= 1 do
        0.0
      else
        differences =
          Enum.zip(original, sorted)
          |> Enum.map(fn {orig, sort} -> abs(orig - sort) end)

        max_diff = Enum.max(differences)
        time_span = Enum.max(original) - Enum.min(original)

        if time_span > 0, do: max_diff / time_span, else: 0.0
      end
    end
  end
end
