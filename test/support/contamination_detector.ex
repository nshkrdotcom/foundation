defmodule Foundation.ContaminationDetector do
  @moduledoc """
  Advanced contamination detection system for Foundation tests.

  This module provides comprehensive monitoring of test execution to detect
  and report contamination issues that could affect test reliability.

  ## Features

  - Process leak detection
  - Telemetry handler cleanup verification
  - ETS table growth monitoring
  - Memory usage tracking
  - Registry state verification
  - Custom contamination checks

  ## Usage

      # Automatic contamination detection (via UnifiedTestFoundation)
      use Foundation.UnifiedTestFoundation, :contamination_detection
      
      # Manual contamination detection
      setup do
        contamination_monitor = ContaminationDetector.start_monitoring()
        on_exit(fn -> ContaminationDetector.stop_monitoring(contamination_monitor) end)
      end
  """

  @doc """
  Starts contamination monitoring for a test.
  """
  def start_monitoring(opts \\ []) do
    test_id = Keyword.get(opts, :test_id, :erlang.unique_integer([:positive]))

    initial_state = capture_detailed_state(test_id)

    monitor = %{
      test_id: test_id,
      start_time: System.system_time(:microsecond),
      initial_state: initial_state,
      custom_checks: Keyword.get(opts, :custom_checks, []),
      strict_mode: Keyword.get(opts, :strict_mode, false)
    }

    # Store monitor in process dictionary for easy access
    Process.put({:contamination_monitor, test_id}, monitor)

    monitor
  end

  @doc """
  Stops contamination monitoring and reports any detected issues.
  """
  def stop_monitoring(monitor) do
    test_id = monitor.test_id
    final_state = capture_detailed_state(test_id)

    contamination_report = analyze_contamination(monitor, final_state)

    # Clean up monitor from process dictionary
    Process.delete({:contamination_monitor, test_id})

    # Report contamination if found
    if contamination_report.has_contamination do
      report_contamination(contamination_report)
    end

    contamination_report
  end

  @doc """
  Captures comprehensive system state for contamination analysis.
  """
  def capture_detailed_state(test_id) do
    %{
      test_id: test_id,
      timestamp: System.system_time(:microsecond),

      # Process monitoring
      processes: %{
        registered: Process.registered(),
        test_processes: find_test_processes(test_id),
        total_count: length(Process.list())
      },

      # Telemetry monitoring
      telemetry: %{
        handlers: :telemetry.list_handlers([]),
        test_handlers: find_test_telemetry_handlers(test_id)
      },

      # ETS monitoring
      ets: %{
        tables: :ets.all(),
        table_count: length(:ets.all()),
        test_tables: find_test_ets_tables(test_id)
      },

      # Memory monitoring
      memory: :erlang.memory(),

      # Registry monitoring
      registry: capture_registry_state(test_id),

      # Application environment (if needed)
      app_env: capture_relevant_app_env()
    }
  end

  @doc """
  Analyzes contamination between initial and final states.
  """
  def analyze_contamination(monitor, final_state) do
    initial_state = monitor.initial_state
    test_id = monitor.test_id

    issues = []

    # Analyze process contamination
    process_issues =
      analyze_process_contamination(initial_state.processes, final_state.processes, test_id)

    issues = issues ++ process_issues

    # Analyze telemetry contamination
    telemetry_issues =
      analyze_telemetry_contamination(initial_state.telemetry, final_state.telemetry, test_id)

    issues = issues ++ telemetry_issues

    # Analyze ETS contamination
    ets_issues = analyze_ets_contamination(initial_state.ets, final_state.ets, test_id)
    issues = issues ++ ets_issues

    # Analyze memory growth
    memory_issues =
      analyze_memory_contamination(initial_state.memory, final_state.memory, monitor.strict_mode)

    issues = issues ++ memory_issues

    # Run custom checks if provided
    custom_issues = run_custom_checks(monitor.custom_checks, initial_state, final_state)
    issues = issues ++ custom_issues

    %{
      test_id: test_id,
      has_contamination: issues != [],
      issues: issues,
      initial_state: initial_state,
      final_state: final_state,
      duration_microseconds: final_state.timestamp - initial_state.timestamp,
      analysis_timestamp: System.system_time(:microsecond)
    }
  end

  @doc """
  Reports contamination issues in a user-friendly format.
  """
  def report_contamination(contamination_report) do
    test_id = contamination_report.test_id
    duration_ms = div(contamination_report.duration_microseconds, 1000)

    IO.puts("\n🚨 CONTAMINATION DETECTED in test_#{test_id} (#{duration_ms}ms)")
    IO.puts("═" <> String.duplicate("═", 60))

    Enum.each(contamination_report.issues, fn issue ->
      IO.puts("⚠️  #{issue.type}: #{issue.description}")

      if issue[:details] do
        Enum.each(issue.details, fn detail ->
          IO.puts("   └─ #{detail}")
        end)
      end

      if issue[:suggestion] do
        IO.puts("   💡 #{issue.suggestion}")
      end

      IO.puts("")
    end)

    IO.puts("═" <> String.duplicate("═", 60))

    IO.puts(
      "ℹ️  Use `use Foundation.UnifiedTestFoundation, :contamination_detection` for automatic cleanup"
    )

    IO.puts("")
  end

  # Private analysis functions

  defp analyze_process_contamination(initial_processes, final_processes, test_id) do
    leftover_registered = final_processes.registered -- initial_processes.registered
    leftover_test_processes = final_processes.test_processes -- initial_processes.test_processes

    issues = []

    # Check for leftover registered processes
    issues =
      if leftover_registered != [] do
        non_test_processes =
          Enum.reject(leftover_registered, fn name ->
            String.contains?(to_string(name), "test_#{test_id}")
          end)

        if non_test_processes != [] do
          [
            %{
              type: "Process Leak",
              description: "Leftover registered processes detected",
              details: Enum.map(non_test_processes, &"#{inspect(&1)}"),
              suggestion: "Ensure all processes are properly cleaned up in on_exit/1"
            }
            | issues
          ]
        else
          issues
        end
      else
        issues
      end

    # Check for leftover test processes
    issues =
      if leftover_test_processes != [] do
        [
          %{
            type: "Test Process Leak",
            description: "Test-specific processes not cleaned up",
            details: Enum.map(leftover_test_processes, &"#{inspect(&1)}"),
            suggestion: "Check test-scoped process cleanup in teardown"
          }
          | issues
        ]
      else
        issues
      end

    # Check for significant process count growth
    process_growth = final_processes.total_count - initial_processes.total_count

    issues =
      if process_growth > 10 do
        [
          %{
            type: "Process Count Growth",
            description: "Significant increase in total process count (+#{process_growth})",
            suggestion: "Review process creation and cleanup patterns"
          }
          | issues
        ]
      else
        issues
      end

    issues
  end

  defp analyze_telemetry_contamination(initial_telemetry, final_telemetry, test_id) do
    leftover_handlers = final_telemetry.handlers -- initial_telemetry.handlers
    leftover_test_handlers = final_telemetry.test_handlers -- initial_telemetry.test_handlers

    issues = []

    # Check for leftover telemetry handlers
    issues =
      if leftover_handlers != [] do
        non_test_handlers =
          Enum.reject(leftover_handlers, fn handler ->
            String.contains?(handler.id, "test_#{test_id}")
          end)

        if non_test_handlers != [] do
          handler_ids = Enum.map(non_test_handlers, & &1.id)

          [
            %{
              type: "Telemetry Handler Leak",
              description: "Leftover telemetry handlers detected",
              details: handler_ids,
              suggestion: "Use :telemetry.detach/1 in test cleanup or use test-scoped handler IDs"
            }
            | issues
          ]
        else
          issues
        end
      else
        issues
      end

    # Check for leftover test handlers
    issues =
      if leftover_test_handlers != [] do
        handler_ids = Enum.map(leftover_test_handlers, & &1.id)

        [
          %{
            type: "Test Telemetry Handler Leak",
            description: "Test-specific telemetry handlers not cleaned up",
            details: handler_ids,
            suggestion: "Ensure test telemetry handlers are detached in on_exit/1"
          }
          | issues
        ]
      else
        issues
      end

    issues
  end

  defp analyze_ets_contamination(initial_ets, final_ets, _test_id) do
    table_growth = final_ets.table_count - initial_ets.table_count
    leftover_test_tables = final_ets.test_tables -- initial_ets.test_tables

    issues = []

    # Check for significant ETS table growth
    issues =
      if table_growth > 5 do
        [
          %{
            type: "ETS Table Growth",
            description: "Significant increase in ETS table count (+#{table_growth})",
            suggestion: "Review ETS table creation and cleanup patterns"
          }
          | issues
        ]
      else
        issues
      end

    # Check for leftover test tables
    issues =
      if leftover_test_tables != [] do
        [
          %{
            type: "Test ETS Table Leak",
            description: "Test-specific ETS tables not cleaned up",
            details: Enum.map(leftover_test_tables, &"Table #{inspect(&1)}"),
            suggestion: "Ensure test ETS tables are deleted in cleanup"
          }
          | issues
        ]
      else
        issues
      end

    issues
  end

  defp analyze_memory_contamination(initial_memory, final_memory, strict_mode) do
    # Calculate memory growth
    total_growth = final_memory[:total] - initial_memory[:total]
    process_growth = final_memory[:processes] - initial_memory[:processes]

    # Define thresholds based on strictness
    {total_threshold, process_threshold} =
      if strict_mode do
        # 5MB total, 2MB process in strict mode
        {5 * 1024 * 1024, 2 * 1024 * 1024}
      else
        # 20MB total, 10MB process in normal mode
        {20 * 1024 * 1024, 10 * 1024 * 1024}
      end

    issues = []

    # Check total memory growth
    issues =
      if total_growth > total_threshold do
        growth_mb = div(total_growth, 1024 * 1024)

        [
          %{
            type: "Memory Growth",
            description: "Significant total memory growth (+#{growth_mb}MB)",
            suggestion: "Review memory allocation patterns and ensure proper cleanup"
          }
          | issues
        ]
      else
        issues
      end

    # Check process memory growth
    issues =
      if process_growth > process_threshold do
        growth_mb = div(process_growth, 1024 * 1024)

        [
          %{
            type: "Process Memory Growth",
            description: "Significant process memory growth (+#{growth_mb}MB)",
            suggestion: "Review process memory usage and cleanup patterns"
          }
          | issues
        ]
      else
        issues
      end

    issues
  end

  defp run_custom_checks(custom_checks, initial_state, final_state) do
    Enum.flat_map(custom_checks, fn check_fun ->
      try do
        case check_fun.(initial_state, final_state) do
          {:ok, nil} ->
            []

          {:ok, issues} when is_list(issues) ->
            issues

          {:error, reason} ->
            [
              %{
                type: "Custom Check Error",
                description: "Custom contamination check failed: #{inspect(reason)}"
              }
            ]

          other ->
            [
              %{
                type: "Custom Check Warning",
                description: "Custom check returned unexpected value: #{inspect(other)}"
              }
            ]
        end
      catch
        kind, reason ->
          [
            %{
              type: "Custom Check Crash",
              description: "Custom contamination check crashed: #{kind} #{inspect(reason)}"
            }
          ]
      end
    end)
  end

  # Helper functions for state capture

  defp find_test_processes(test_id) do
    Process.registered()
    |> Enum.filter(fn name ->
      String.contains?(to_string(name), "test_#{test_id}")
    end)
  end

  defp find_test_telemetry_handlers(test_id) do
    :telemetry.list_handlers([])
    |> Enum.filter(fn handler ->
      String.contains?(handler.id, "test_#{test_id}")
    end)
  end

  defp find_test_ets_tables(test_id) do
    # This is approximate - ETS doesn't provide easy filtering by name pattern
    :ets.all()
    |> Enum.filter(fn table ->
      try do
        info = :ets.info(table)
        name = info[:name]
        String.contains?(to_string(name), "test_#{test_id}")
      catch
        _, _ -> false
      end
    end)
  end

  defp capture_registry_state(_test_id) do
    # Capture relevant registry state if needed
    # This could be expanded based on specific registry needs
    %{
      # Could capture Foundation registry states
      foundation_registries: [],
      # Could capture MABEAM registry states
      mabeam_registries: []
    }
  end

  defp capture_relevant_app_env do
    # Capture only relevant application environment variables
    # that might affect test isolation
    %{
      # Add relevant app env keys here if needed
    }
  end
end
