#!/usr/bin/env elixir

defmodule OTPCleanupTestRunner do
  @moduledoc """
  Comprehensive test runner for OTP cleanup integration tests.
  
  This script runs all OTP cleanup tests in the correct order and provides
  detailed reporting on test results, performance, and coverage.
  """
  
  @test_suites [
    %{
      name: "Process Dictionary Elimination",
      file: "test/foundation/otp_cleanup_integration_test.exs",
      tags: [:integration, :otp_cleanup],
      timeout: 60_000,
      description: "Verifies that Process dictionary usage is eliminated"
    },
    %{
      name: "End-to-End Functionality",
      file: "test/foundation/otp_cleanup_e2e_test.exs",
      tags: [:e2e, :otp_cleanup],
      timeout: 120_000,
      description: "Tests complete workflows after Process dictionary cleanup"
    },
    %{
      name: "Performance Regression",
      file: "test/foundation/otp_cleanup_performance_test.exs",
      tags: [:performance, :benchmark],
      timeout: 300_000,
      description: "Benchmarks performance of new vs old implementations"
    },
    %{
      name: "Concurrency and Stress",
      file: "test/foundation/otp_cleanup_stress_test.exs",
      tags: [:stress, :concurrency],
      timeout: 600_000,
      description: "Tests system under high load and concurrent access"
    },
    %{
      name: "Feature Flag Integration",
      file: "test/foundation/otp_cleanup_feature_flag_test.exs",
      tags: [:feature_flags, :integration],
      timeout: 120_000,
      description: "Tests switching between old and new implementations"
    },
    %{
      name: "Failure Recovery",
      file: "test/foundation/otp_cleanup_failure_recovery_test.exs",
      tags: [:failure_recovery, :resilience],
      timeout: 180_000,
      description: "Tests behavior during failures and recovery scenarios"
    },
    %{
      name: "Monitoring and Observability",
      file: "test/foundation/otp_cleanup_observability_test.exs",
      tags: [:observability, :telemetry],
      timeout: 120_000,
      description: "Verifies telemetry events and error reporting work correctly"
    }
  ]
  
  def main(args) do
    IO.puts("🧪 OTP Cleanup Integration Test Suite")
    IO.puts("=====================================\n")
    
    options = parse_args(args)
    
    # Run tests based on options
    results = if options.suite do
      run_single_suite(options.suite, options)
    else
      run_all_suites(options)
    end
    
    # Generate report
    generate_report(results, options)
    
    # Exit with appropriate code
    failed_suites = Enum.count(results, fn {_, result} -> result.status != :passed end)
    System.halt(if failed_suites == 0, do: 0, else: 1)
  end
  
  defp parse_args(args) do
    {options, _, _} = OptionParser.parse(args,
      switches: [
        suite: :string,
        verbose: :boolean,
        parallel: :boolean,
        skip_slow: :boolean,
        performance_only: :boolean,
        help: :boolean
      ],
      aliases: [
        s: :suite,
        v: :verbose,
        p: :parallel,
        h: :help
      ]
    )
    
    if options[:help] do
      print_help()
      System.halt(0)
    end
    
    %{
      suite: options[:suite],
      verbose: options[:verbose] || false,
      parallel: options[:parallel] || false,
      skip_slow: options[:skip_slow] || false,
      performance_only: options[:performance_only] || false
    }
  end
  
  defp print_help do
    IO.puts("""
    OTP Cleanup Test Runner
    
    Usage: elixir test/run_otp_cleanup_tests.exs [options]
    
    Options:
      -s, --suite SUITE     Run specific test suite
      -v, --verbose         Verbose output
      -p, --parallel        Run tests in parallel (experimental)
      --skip-slow           Skip slow tests (stress, performance)
      --performance-only    Run only performance tests
      -h, --help            Show this help
    
    Available test suites:
    #{Enum.map_join(@test_suites, "\n", fn suite -> "  - #{suite.name}" end)}
    
    Examples:
      elixir test/run_otp_cleanup_tests.exs
      elixir test/run_otp_cleanup_tests.exs --suite "Process Dictionary Elimination"
      elixir test/run_otp_cleanup_tests.exs --performance-only
      elixir test/run_otp_cleanup_tests.exs --skip-slow --verbose
    """)
  end
  
  defp run_all_suites(options) do
    suites_to_run = filter_suites(@test_suites, options)
    
    IO.puts("Running #{length(suites_to_run)} test suite(s):\n")
    
    if options.parallel do
      run_suites_parallel(suites_to_run, options)
    else
      run_suites_sequential(suites_to_run, options)
    end
  end
  
  defp run_single_suite(suite_name, options) do
    suite = Enum.find(@test_suites, fn s -> s.name == suite_name end)
    
    if suite do
      IO.puts("Running single test suite: #{suite.name}\n")
      [{suite.name, run_suite(suite, options)}]
    else
      IO.puts("❌ Unknown test suite: #{suite_name}")
      IO.puts("Available suites:")
      Enum.each(@test_suites, fn s -> IO.puts("  - #{s.name}") end)
      System.halt(1)
    end
  end
  
  defp filter_suites(suites, options) do
    suites
    |> filter_by_performance(options)
    |> filter_by_slow(options)
  end
  
  defp filter_by_performance(suites, %{performance_only: true}) do
    Enum.filter(suites, fn suite ->
      :performance in suite.tags or :benchmark in suite.tags
    end)
  end
  defp filter_by_performance(suites, _), do: suites
  
  defp filter_by_slow(suites, %{skip_slow: true}) do
    Enum.reject(suites, fn suite ->
      :stress in suite.tags or :performance in suite.tags
    end)
  end
  defp filter_by_slow(suites, _), do: suites
  
  defp run_suites_sequential(suites, options) do
    Enum.map(suites, fn suite ->
      {suite.name, run_suite(suite, options)}
    end)
  end
  
  defp run_suites_parallel(suites, options) do
    IO.puts("⚠️  Parallel execution is experimental and may cause test interference\n")
    
    tasks = Enum.map(suites, fn suite ->
      Task.async(fn ->
        {suite.name, run_suite(suite, options)}
      end)
    end)
    
    Task.await_many(tasks, 1_200_000)  # 20 minutes total timeout
  end
  
  defp run_suite(suite, options) do
    IO.puts("🏃 Running: #{suite.name}")
    IO.puts("   File: #{suite.file}")
    IO.puts("   Description: #{suite.description}")
    
    start_time = System.monotonic_time(:millisecond)
    
    # Build test command
    cmd_args = build_test_command(suite, options)
    
    if options.verbose do
      IO.puts("   Command: mix test #{Enum.join(cmd_args, " ")}")
    end
    
    # Run the test
    {output, exit_code} = System.cmd("mix", ["test" | cmd_args], 
      stderr_to_stdout: true,
      cd: File.cwd!()
    )
    
    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time
    
    # Parse test results
    result = parse_test_output(output, exit_code, duration)
    
    # Print immediate result
    status_emoji = case result.status do
      :passed -> "✅"
      :failed -> "❌"
      :error -> "💥"
    end
    
    IO.puts("   Result: #{status_emoji} #{result.status} (#{format_duration(duration)})")
    
    if result.status != :passed and options.verbose do
      IO.puts("   Output:")
      IO.puts(indent_output(output, "     "))
    end
    
    IO.puts("")
    
    result
  end
  
  defp build_test_command(suite, options) do
    args = [suite.file]
    
    # Add tags
    tag_args = Enum.flat_map(suite.tags, fn tag -> ["--include", to_string(tag)] end)
    args = args ++ tag_args
    
    # Add timeout
    args = args ++ ["--timeout", to_string(suite.timeout)]
    
    # Add verbosity
    if options.verbose do
      args = args ++ ["--trace"]
    end
    
    args
  end
  
  defp parse_test_output(output, exit_code, duration) do
    # Extract test statistics from ExUnit output
    test_count = extract_test_count(output)
    failure_count = extract_failure_count(output)
    
    status = case exit_code do
      0 -> :passed
      _ -> if String.contains?(output, "** (") do
        :error
      else
        :failed
      end
    end
    
    %{
      status: status,
      exit_code: exit_code,
      duration: duration,
      test_count: test_count,
      failure_count: failure_count,
      output: output
    }
  end
  
  defp extract_test_count(output) do
    case Regex.run(~r/(\d+) tests/, output) do
      [_, count] -> String.to_integer(count)
      _ -> 0
    end
  end
  
  defp extract_failure_count(output) do
    case Regex.run(~r/(\d+) failures/, output) do
      [_, count] -> String.to_integer(count)
      _ -> 0
    end
  end
  
  defp generate_report(results, options) do
    IO.puts("📊 Test Results Summary")
    IO.puts("======================\n")
    
    total_suites = length(results)
    passed_suites = Enum.count(results, fn {_, result} -> result.status == :passed end)
    failed_suites = total_suites - passed_suites
    
    total_tests = Enum.sum(Enum.map(results, fn {_, result} -> result.test_count end))
    total_failures = Enum.sum(Enum.map(results, fn {_, result} -> result.failure_count end))
    total_duration = Enum.sum(Enum.map(results, fn {_, result} -> result.duration end))
    
    # Suite summary
    IO.puts("📋 Suite Summary:")
    IO.puts("   Total Suites: #{total_suites}")
    IO.puts("   Passed: #{passed_suites}")
    IO.puts("   Failed: #{failed_suites}")
    IO.puts("   Success Rate: #{Float.round(passed_suites / total_suites * 100, 1)}%")
    IO.puts("")
    
    # Test summary
    IO.puts("🧪 Test Summary:")
    IO.puts("   Total Tests: #{total_tests}")
    IO.puts("   Passed: #{total_tests - total_failures}")
    IO.puts("   Failed: #{total_failures}")
    IO.puts("   Success Rate: #{if total_tests > 0, do: Float.round((total_tests - total_failures) / total_tests * 100, 1), else: 0}%")
    IO.puts("")
    
    # Performance summary
    IO.puts("⏱️  Performance Summary:")
    IO.puts("   Total Duration: #{format_duration(total_duration)}")
    IO.puts("   Average per Suite: #{format_duration(div(total_duration, max(total_suites, 1)))}")
    IO.puts("")
    
    # Detailed results
    IO.puts("📈 Detailed Results:")
    for {suite_name, result} <- results do
      status_emoji = case result.status do
        :passed -> "✅"
        :failed -> "❌"
        :error -> "💥"
      end
      
      IO.puts("   #{status_emoji} #{suite_name}")
      IO.puts("      Tests: #{result.test_count}, Failures: #{result.failure_count}")
      IO.puts("      Duration: #{format_duration(result.duration)}")
      
      if result.status != :passed and not options.verbose do
        IO.puts("      (Run with --verbose to see detailed output)")
      end
    end
    
    IO.puts("")
    
    # Recommendations
    generate_recommendations(results)
  end
  
  defp generate_recommendations(results) do
    failed_results = Enum.filter(results, fn {_, result} -> result.status != :passed end)
    
    if length(failed_results) > 0 do
      IO.puts("🔧 Recommendations:")
      
      for {suite_name, result} <- failed_results do
        case result.status do
          :failed ->
            IO.puts("   - Fix failing tests in #{suite_name}")
            if result.failure_count > 0 do
              IO.puts("     #{result.failure_count} test(s) failed - check implementation correctness")
            end
            
          :error ->
            IO.puts("   - Resolve errors in #{suite_name}")
            IO.puts("     Suite had compilation or runtime errors - check syntax and dependencies")
        end
      end
      
      IO.puts("")
      IO.puts("   To debug specific failures:")
      IO.puts("   mix test <test_file> --trace --max-failures 1")
      IO.puts("")
    else
      IO.puts("🎉 All tests passed! OTP cleanup implementation is working correctly.")
      IO.puts("")
      IO.puts("   Next steps:")
      IO.puts("   - Deploy with feature flags enabled")
      IO.puts("   - Monitor performance in production")
      IO.puts("   - Gradually increase rollout percentage")
      IO.puts("")
    end
  end
  
  defp format_duration(milliseconds) do
    cond do
      milliseconds < 1000 ->
        "#{milliseconds}ms"
      milliseconds < 60_000 ->
        "#{Float.round(milliseconds / 1000, 1)}s"
      true ->
        minutes = div(milliseconds, 60_000)
        seconds = rem(milliseconds, 60_000) / 1000
        "#{minutes}m #{Float.round(seconds, 1)}s"
    end
  end
  
  defp indent_output(output, prefix) do
    output
    |> String.split("\n")
    |> Enum.map_join("\n", fn line -> prefix <> line end)
  end
end

# Run the test runner
OTPCleanupTestRunner.main(System.argv())