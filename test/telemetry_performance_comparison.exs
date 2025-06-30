# Telemetry Performance Comparison Script
#
# This script compares the performance of telemetry-based tests
# vs traditional Process.sleep-based tests

defmodule TelemetryPerformanceComparison do
  use Foundation.TelemetryTestHelpers

  @iterations 100
  @sleep_duration 50
  @event_name [:test, :benchmark, :event]

  def run do
    IO.puts("Telemetry Performance Comparison")
    IO.puts("================================")
    IO.puts("Iterations: #{@iterations}")
    IO.puts("Sleep duration: #{@sleep_duration}ms")
    IO.puts("")

    # Warm up
    warmup()

    # Run sleep-based benchmark
    sleep_results = benchmark_sleep_based()

    # Run telemetry-based benchmark
    telemetry_results = benchmark_telemetry_based()

    # Compare results
    print_results(sleep_results, telemetry_results)
  end

  defp warmup do
    IO.puts("Warming up...")

    # Warm up sleep
    for _ <- 1..10 do
      Process.sleep(10)
    end

    # Warm up telemetry
    for _ <- 1..10 do
      :telemetry.execute(@event_name, %{value: 1}, %{})
      wait_for_telemetry_event(@event_name, timeout: 100)
    end

    IO.puts("Warmup complete\n")
  end

  defp benchmark_sleep_based do
    IO.puts("Running sleep-based benchmark...")

    times =
      for _i <- 1..@iterations do
        start_time = System.monotonic_time(:microsecond)

        # Simulate async operation with sleep
        Task.start(fn ->
          Process.sleep(@sleep_duration)
          # Operation complete
        end)

        # Wait with sleep
        Process.sleep(@sleep_duration + 10)

        end_time = System.monotonic_time(:microsecond)
        end_time - start_time
      end

    analyze_times(times, "Sleep-based")
  end

  defp benchmark_telemetry_based do
    IO.puts("Running telemetry-based benchmark...")

    times =
      for i <- 1..@iterations do
        start_time = System.monotonic_time(:microsecond)

        # Simulate async operation with telemetry
        Task.start(fn ->
          Process.sleep(@sleep_duration)
          :telemetry.execute(@event_name, %{value: i}, %{iteration: i})
        end)

        # Wait with telemetry
        {:ok, _} = wait_for_telemetry_event(@event_name, timeout: @sleep_duration + 100)

        end_time = System.monotonic_time(:microsecond)
        end_time - start_time
      end

    analyze_times(times, "Telemetry-based")
  end

  defp analyze_times(times, label) do
    sorted_times = Enum.sort(times)

    stats = %{
      label: label,
      min: Enum.min(times),
      max: Enum.max(times),
      mean: Enum.sum(times) / length(times),
      median: Enum.at(sorted_times, div(length(sorted_times), 2)),
      p95: Enum.at(sorted_times, round(length(sorted_times) * 0.95) - 1),
      p99: Enum.at(sorted_times, round(length(sorted_times) * 0.99) - 1),
      total: Enum.sum(times)
    }

    IO.puts("#{label} complete")
    stats
  end

  defp print_results(sleep_stats, telemetry_stats) do
    IO.puts("\nResults (all times in microseconds)")
    IO.puts("===================================")

    print_stat_comparison("Min", sleep_stats.min, telemetry_stats.min)
    print_stat_comparison("Max", sleep_stats.max, telemetry_stats.max)
    print_stat_comparison("Mean", sleep_stats.mean, telemetry_stats.mean)
    print_stat_comparison("Median", sleep_stats.median, telemetry_stats.median)
    print_stat_comparison("P95", sleep_stats.p95, telemetry_stats.p95)
    print_stat_comparison("P99", sleep_stats.p99, telemetry_stats.p99)
    print_stat_comparison("Total", sleep_stats.total, telemetry_stats.total)

    IO.puts("\nSummary")
    IO.puts("=======")

    mean_improvement = (sleep_stats.mean - telemetry_stats.mean) / sleep_stats.mean * 100
    total_improvement = (sleep_stats.total - telemetry_stats.total) / sleep_stats.total * 100

    IO.puts("Mean time improvement: #{Float.round(mean_improvement, 2)}%")
    IO.puts("Total time improvement: #{Float.round(total_improvement, 2)}%")

    if mean_improvement > 0 do
      IO.puts("\n✅ Telemetry-based approach is FASTER on average")
    else
      IO.puts("\n❌ Sleep-based approach is faster on average")
    end

    # Additional analysis
    IO.puts("\nAdditional Benefits of Telemetry:")
    IO.puts("- ✅ No arbitrary wait times")
    IO.puts("- ✅ Event-driven coordination")
    IO.puts("- ✅ Better debugging with event data")
    IO.puts("- ✅ Can handle variable timing")
    IO.puts("- ✅ Integrates with monitoring")
  end

  defp print_stat_comparison(label, sleep_value, telemetry_value) do
    diff = telemetry_value - sleep_value
    diff_percent = diff / sleep_value * 100

    sleep_ms = Float.round(sleep_value / 1000, 2)
    telemetry_ms = Float.round(telemetry_value / 1000, 2)

    status = if diff < 0, do: "✅", else: "❌"

    IO.puts(
      "#{String.pad_trailing(label, 8)}: Sleep: #{String.pad_leading("#{sleep_ms}", 8)}ms | " <>
        "Telemetry: #{String.pad_leading("#{telemetry_ms}", 8)}ms | " <>
        "Diff: #{String.pad_leading("#{Float.round(diff_percent, 1)}%", 7)} #{status}"
    )
  end
end

# Additional benchmark for more realistic scenarios
defmodule RealisticTelemetryBenchmark do
  use Foundation.TelemetryTestHelpers

  def run do
    IO.puts("\n\nRealistic Scenario Benchmarks")
    IO.puts("=============================")

    # Scenario 1: Multiple events
    scenario1_sleep = benchmark_multiple_events_sleep()
    scenario1_telemetry = benchmark_multiple_events_telemetry()

    IO.puts("\nScenario 1: Waiting for multiple events")
    compare_results(scenario1_sleep, scenario1_telemetry)

    # Scenario 2: Variable timing
    scenario2_sleep = benchmark_variable_timing_sleep()
    scenario2_telemetry = benchmark_variable_timing_telemetry()

    IO.puts("\nScenario 2: Variable timing events")
    compare_results(scenario2_sleep, scenario2_telemetry)

    # Scenario 3: Conditional waiting
    scenario3_sleep = benchmark_conditional_sleep()
    scenario3_telemetry = benchmark_conditional_telemetry()

    IO.puts("\nScenario 3: Conditional waiting")
    compare_results(scenario3_sleep, scenario3_telemetry)
  end

  defp benchmark_multiple_events_sleep do
    start_time = System.monotonic_time(:microsecond)

    # Start 5 async operations
    for i <- 1..5 do
      Task.start(fn ->
        Process.sleep(10 * i)
        # Operation i complete
      end)
    end

    # Wait for all with conservative sleep
    Process.sleep(60)

    System.monotonic_time(:microsecond) - start_time
  end

  defp benchmark_multiple_events_telemetry do
    start_time = System.monotonic_time(:microsecond)

    # Start 5 async operations
    for i <- 1..5 do
      Task.start(fn ->
        Process.sleep(10 * i)
        :telemetry.execute([:test, :multi], %{value: i}, %{index: i})
      end)
    end

    # Wait for all events
    for _ <- 1..5 do
      wait_for_telemetry_event([:test, :multi], timeout: 100)
    end

    System.monotonic_time(:microsecond) - start_time
  end

  defp benchmark_variable_timing_sleep do
    start_time = System.monotonic_time(:microsecond)

    # Random delay operation
    delay = Enum.random(10..50)

    Task.start(fn ->
      Process.sleep(delay)
      # Operation complete
    end)

    # Conservative wait
    Process.sleep(60)

    System.monotonic_time(:microsecond) - start_time
  end

  defp benchmark_variable_timing_telemetry do
    start_time = System.monotonic_time(:microsecond)

    # Random delay operation
    delay = Enum.random(10..50)

    Task.start(fn ->
      Process.sleep(delay)
      :telemetry.execute([:test, :variable], %{delay: delay}, %{})
    end)

    # Wait for exact event
    wait_for_telemetry_event([:test, :variable], timeout: 100)

    System.monotonic_time(:microsecond) - start_time
  end

  defp benchmark_conditional_sleep do
    start_time = System.monotonic_time(:microsecond)

    success = Enum.random([true, false])

    Task.start(fn ->
      Process.sleep(20)

      if success do
        # Operation succeeded
      end
    end)

    # Always wait full duration
    Process.sleep(30)

    System.monotonic_time(:microsecond) - start_time
  end

  defp benchmark_conditional_telemetry do
    start_time = System.monotonic_time(:microsecond)

    ref = make_ref()
    success = Enum.random([true, false])

    Task.start(fn ->
      Process.sleep(20)

      if success do
        :telemetry.execute([:test, :conditional], %{}, %{ref: ref})
      end
    end)

    # Only wait if we expect success
    if success do
      wait_for_telemetry_event([:test, :conditional], timeout: 50)
    else
      Process.sleep(25)
    end

    System.monotonic_time(:microsecond) - start_time
  end

  defp compare_results(sleep_time, telemetry_time) do
    sleep_ms = Float.round(sleep_time / 1000, 2)
    telemetry_ms = Float.round(telemetry_time / 1000, 2)
    improvement = Float.round((sleep_time - telemetry_time) / sleep_time * 100, 1)

    IO.puts("Sleep-based: #{sleep_ms}ms")
    IO.puts("Telemetry-based: #{telemetry_ms}ms")
    IO.puts("Improvement: #{improvement}%")
  end
end

# Run the benchmarks
IO.puts("Starting telemetry performance comparison...\n")

TelemetryPerformanceComparison.run()
RealisticTelemetryBenchmark.run()

IO.puts("\n\nConclusion")
IO.puts("==========")
IO.puts("While telemetry may have slightly higher overhead for simple cases,")
IO.puts("it provides significant benefits for real-world testing:")
IO.puts("- More accurate timing (no over-waiting)")
IO.puts("- Better handling of variable delays")
IO.puts("- Rich event data for debugging")
IO.puts("- Integration with monitoring systems")
IO.puts("- Event-driven architecture benefits")
