defmodule MABEAM.TelemetryHelpers do
  @moduledoc """
  Comprehensive telemetry test utilities for MABEAM system testing.

  Provides helper functions for:
  - Telemetry event capture and verification
  - Metric collection and analysis
  - Performance monitoring utilities
  - Event pattern matching and assertions
  - Telemetry handler management for tests
  - Integration testing with Foundation telemetry
  """

  # ============================================================================
  # Event Capture Helpers
  # ============================================================================

  @doc """
  Sets up telemetry event capture for a list of events.
  Returns a handler ID that can be used for cleanup.
  """
  @spec capture_telemetry_events([list()], pid()) :: binary()
  def capture_telemetry_events(event_patterns, test_pid \\ self()) do
    handler_id = generate_handler_id()

    :telemetry.attach_many(
      handler_id,
      event_patterns,
      fn event, measurements, metadata, _config ->
        send(
          test_pid,
          {:telemetry_event,
           %{
             event: event,
             measurements: measurements,
             metadata: metadata,
             timestamp: System.monotonic_time(:microsecond)
           }}
        )
      end,
      %{}
    )

    handler_id
  end

  @doc """
  Captures all MABEAM telemetry events for comprehensive testing.
  Returns handler_id after confirming handler is attached.
  """
  @spec capture_all_mabeam_events(pid()) :: binary()
  def capture_all_mabeam_events(test_pid \\ self()) do
    mabeam_events = [
      # Core orchestrator events
      [:foundation, :mabeam, :core, :service_started],
      [:foundation, :mabeam, :core, :variable_registered],
      [:foundation, :mabeam, :core, :variable_updated],
      [:foundation, :mabeam, :core, :coordination_start],
      [:foundation, :mabeam, :core, :coordination_complete],

      # Process registry events
      [:foundation, :mabeam, :process_registry, :agent_registered],
      [:foundation, :mabeam, :process_registry, :agent_started],
      [:foundation, :mabeam, :process_registry, :agent_stopped],
      [:foundation, :mabeam, :process_registry, :agent_crashed],

      # Communication events
      [:foundation, :mabeam, :comms, :request_sent],
      [:foundation, :mabeam, :comms, :response_received],
      [:foundation, :mabeam, :comms, :notification_sent],
      [:foundation, :mabeam, :comms, :timeout_occurred],

      # Coordination events
      [:foundation, :mabeam, :coordination, :coordination_start],
      [:foundation, :mabeam, :coordination, :coordination_complete],
      [:foundation, :mabeam, :coordination, :consensus_reached],
      [:foundation, :mabeam, :coordination, :session_created],
      [:foundation, :mabeam, :coordination, :session_completed],
      [:foundation, :mabeam, :coordination, :protocol_registered],
      [:foundation, :mabeam, :coordination, :test_integration],
      [:foundation, :mabeam, :coordination, :performance_test]
    ]

    handler_id = capture_telemetry_events(mabeam_events, test_pid)

    # Verify handler is attached by checking telemetry handlers
    :telemetry.list_handlers([])
    |> Enum.find(fn handler -> handler.id == handler_id end)
    |> case do
      nil -> raise "Telemetry handler failed to attach: #{handler_id}"
      _handler -> handler_id
    end
  end

  @doc """
  Waits for a specific telemetry event and returns it.
  """
  @spec wait_for_telemetry_event(list(), non_neg_integer()) ::
          {:ok, map()} | {:error, :timeout}
  def wait_for_telemetry_event(expected_event, timeout \\ 5000) do
    receive do
      {:telemetry_event, %{event: ^expected_event} = event_data} ->
        {:ok, event_data}

      {:telemetry_event, _other_event} ->
        # Keep waiting for the specific event
        wait_for_telemetry_event(expected_event, timeout)
    after
      timeout ->
        {:error, :timeout}
    end
  end

  @doc """
  Waits for multiple telemetry events in any order.
  """
  @spec wait_for_telemetry_events([list()], non_neg_integer()) ::
          {:ok, [map()]} | {:error, :timeout}
  def wait_for_telemetry_events(expected_events, timeout \\ 10_000) do
    deadline = System.monotonic_time(:millisecond) + timeout
    wait_for_events_loop(expected_events, [], deadline)
  end

  @doc """
  Collects all telemetry events for a given duration.
  """
  @spec collect_telemetry_events(non_neg_integer()) :: [map()]
  def collect_telemetry_events(duration_ms) do
    collect_events_loop([], System.monotonic_time(:millisecond) + duration_ms)
  end

  # ============================================================================
  # Event Verification Helpers
  # ============================================================================

  @doc """
  Asserts that a telemetry event was received with expected properties.
  """
  @spec assert_telemetry_event_received(list(), keyword()) :: :ok
  def assert_telemetry_event_received(expected_event, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)
    expected_measurements = Keyword.get(opts, :measurements, %{})
    expected_metadata = Keyword.get(opts, :metadata, %{})

    case wait_for_telemetry_event(expected_event, timeout) do
      {:ok, event_data} ->
        verify_event_measurements(event_data.measurements, expected_measurements)
        verify_event_metadata(event_data.metadata, expected_metadata)
        :ok

      {:error, :timeout} ->
        raise "Expected telemetry event #{inspect(expected_event)} not received within #{timeout}ms"
    end
  end

  @doc """
  Asserts that telemetry events match expected patterns.
  """
  @spec assert_telemetry_pattern([map()], keyword()) :: :ok
  def assert_telemetry_pattern(events, opts \\ []) do
    min_count = Keyword.get(opts, :min_count, 1)
    max_count = Keyword.get(opts, :max_count, :unlimited)
    event_pattern = Keyword.get(opts, :pattern)

    matching_events =
      if event_pattern do
        Enum.filter(events, fn event -> matches_pattern?(event, event_pattern) end)
      else
        events
      end

    event_count = length(matching_events)

    cond do
      event_count < min_count ->
        raise "Expected at least #{min_count} matching events, got #{event_count}"

      max_count != :unlimited and event_count > max_count ->
        raise "Expected at most #{max_count} matching events, got #{event_count}"

      true ->
        :ok
    end
  end

  @doc """
  Verifies telemetry event ordering and timing.
  """
  @spec assert_event_ordering([map()], [list()]) :: :ok
  def assert_event_ordering(events, expected_order) do
    # Extract events matching the expected order
    ordered_events =
      Enum.filter(events, fn event ->
        Enum.member?(expected_order, event.event)
      end)

    # Sort by timestamp
    sorted_events = Enum.sort_by(ordered_events, & &1.timestamp)

    # Check if the order matches
    actual_order = Enum.map(sorted_events, & &1.event)

    if actual_order != expected_order do
      raise "Expected event order #{inspect(expected_order)}, got #{inspect(actual_order)}"
    end

    :ok
  end

  # ============================================================================
  # Metric Analysis Helpers
  # ============================================================================

  @doc """
  Analyzes performance metrics from telemetry events.
  """
  @spec analyze_performance_metrics([map()]) :: map()
  def analyze_performance_metrics(events) do
    duration_events =
      Enum.filter(events, fn event ->
        Map.has_key?(event.measurements, :duration) or
          Map.has_key?(event.measurements, :duration_ms)
      end)

    durations =
      Enum.map(duration_events, fn event ->
        Map.get(event.measurements, :duration, Map.get(event.measurements, :duration_ms, 0))
      end)

    counter_events =
      Enum.filter(events, fn event ->
        Map.has_key?(event.measurements, :count) or Map.has_key?(event.measurements, :counter)
      end)

    total_count =
      Enum.reduce(counter_events, 0, fn event, acc ->
        count = Map.get(event.measurements, :count, Map.get(event.measurements, :counter, 0))
        acc + count
      end)

    %{
      total_events: length(events),
      duration_events: length(duration_events),
      average_duration:
        if(length(durations) > 0, do: Enum.sum(durations) / length(durations), else: 0),
      min_duration: if(length(durations) > 0, do: Enum.min(durations), else: 0),
      max_duration: if(length(durations) > 0, do: Enum.max(durations), else: 0),
      total_count: total_count,
      event_types: count_event_types(events)
    }
  end

  @doc """
  Calculates success rates from telemetry events.
  """
  @spec calculate_success_rates([map()]) :: map()
  def calculate_success_rates(events) do
    success_events =
      Enum.filter(events, fn event ->
        success_event?(event)
      end)

    error_events =
      Enum.filter(events, fn event ->
        error_event?(event)
      end)

    total_outcome_events = length(success_events) + length(error_events)

    success_rate =
      if total_outcome_events > 0 do
        length(success_events) / total_outcome_events
      else
        0.0
      end

    %{
      total_events: length(events),
      success_events: length(success_events),
      error_events: length(error_events),
      success_rate: success_rate,
      error_rate: 1.0 - success_rate
    }
  end

  @doc """
  Extracts coordination-specific metrics from events.
  """
  @spec extract_coordination_metrics([map()]) :: map()
  def extract_coordination_metrics(events) do
    coordination_events =
      Enum.filter(events, fn event ->
        case event.event do
          [:foundation, :mabeam, :coordination, _] -> true
          _ -> false
        end
      end)

    session_events =
      Enum.filter(events, fn event ->
        case event.event do
          [:foundation, :mabeam, :coordination, event_type]
          when event_type in [:session_created, :session_completed] ->
            true

          [:foundation, :mabeam, :session, event_type] when event_type in [:created, :completed] ->
            true

          _ ->
            false
        end
      end)

    consensus_events =
      Enum.filter(events, fn event ->
        case event.event do
          [:foundation, :mabeam, :coordination, :consensus_reached] -> true
          [:foundation, :mabeam, :consensus, :reached] -> true
          _ -> false
        end
      end)

    %{
      coordination_events: length(coordination_events),
      session_events: length(session_events),
      consensus_events: length(consensus_events),
      avg_coordination_time: calculate_avg_coordination_time(coordination_events),
      coordination_success_rate: calculate_coordination_success_rate(coordination_events)
    }
  end

  # ============================================================================
  # Performance Testing Helpers
  # ============================================================================

  @doc """
  Measures telemetry overhead during operations.
  """
  @spec measure_telemetry_overhead(function()) ::
          %{
            execution_time_ms: float(),
            telemetry_events: non_neg_integer(),
            overhead_ratio: float()
          }
  def measure_telemetry_overhead(operation_fn) do
    # Capture events during operation
    handler_id = capture_all_mabeam_events()

    start_time = System.monotonic_time(:microsecond)
    result = operation_fn.()
    end_time = System.monotonic_time(:microsecond)

    execution_time_ms = (end_time - start_time) / 1000

    # Collect events
    # Allow events to be processed
    Process.sleep(50)
    events = collect_telemetry_events(100)

    cleanup_telemetry_handler(handler_id)

    # Calculate overhead (rough estimate)
    event_count = length(events)

    overhead_ratio =
      if execution_time_ms > 0 do
        # Assume 0.01ms per event
        event_count * 0.01 / execution_time_ms
      else
        0.0
      end

    %{
      execution_time_ms: execution_time_ms,
      telemetry_events: event_count,
      overhead_ratio: overhead_ratio,
      result: result
    }
  end

  @doc """
  Benchmarks telemetry event throughput.
  """
  @spec benchmark_telemetry_throughput(non_neg_integer()) ::
          %{events_per_second: float(), total_events: non_neg_integer()}
  def benchmark_telemetry_throughput(duration_seconds) do
    handler_id = capture_all_mabeam_events()

    start_time = System.monotonic_time(:second)

    # Generate telemetry events
    generate_test_events(duration_seconds)

    end_time = System.monotonic_time(:second)
    actual_duration = end_time - start_time

    # Collect remaining events
    events = collect_telemetry_events(1000)
    event_count = length(events)

    cleanup_telemetry_handler(handler_id)

    events_per_second =
      if actual_duration > 0 do
        event_count / actual_duration
      else
        0.0
      end

    %{
      events_per_second: events_per_second,
      total_events: event_count,
      duration_seconds: actual_duration
    }
  end

  # ============================================================================
  # Integration Testing Helpers
  # ============================================================================

  @doc """
  Verifies MABEAM telemetry integration with Foundation telemetry.
  """
  @spec verify_foundation_integration([map()]) :: :ok | {:error, term()}
  def verify_foundation_integration(events) do
    # Check that events follow Foundation telemetry patterns
    foundation_events =
      Enum.filter(events, fn event ->
        List.first(event.event) == :foundation
      end)

    if Enum.empty?(foundation_events) do
      {:error, :no_foundation_events}
    else
      # Verify event structure
      structure_valid = Enum.all?(foundation_events, &valid_foundation_event_structure?/1)

      if structure_valid do
        :ok
      else
        {:error, :invalid_event_structure}
      end
    end
  end

  @doc """
  Tests telemetry event aggregation and rollup.
  """
  @spec test_event_aggregation([map()], keyword()) :: map()
  def test_event_aggregation(events, opts \\ []) do
    time_window_ms = Keyword.get(opts, :time_window_ms, 1000)

    # Group events by time windows
    grouped_events = group_events_by_time_window(events, time_window_ms)

    # Calculate aggregations for each window
    aggregations =
      Enum.map(grouped_events, fn {window_start, window_events} ->
        %{
          window_start: window_start,
          event_count: length(window_events),
          unique_event_types: count_unique_event_types(window_events),
          performance_metrics: analyze_performance_metrics(window_events)
        }
      end)

    %{
      total_windows: length(aggregations),
      aggregations: aggregations,
      overall_metrics: analyze_performance_metrics(events)
    }
  end

  # ============================================================================
  # Cleanup Helpers
  # ============================================================================

  @doc """
  Cleans up a telemetry handler.
  """
  @spec cleanup_telemetry_handler(binary()) :: :ok
  def cleanup_telemetry_handler(handler_id) do
    :telemetry.detach(handler_id)
  end

  @doc """
  Cleans up multiple telemetry handlers.
  """
  @spec cleanup_telemetry_handlers([binary()]) :: :ok
  def cleanup_telemetry_handlers(handler_ids) do
    Enum.each(handler_ids, &cleanup_telemetry_handler/1)
  end

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  defp generate_handler_id do
    "test_handler_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end

  defp wait_for_events_loop([], collected_events, _deadline),
    do: {:ok, Enum.reverse(collected_events)}

  defp wait_for_events_loop(remaining_events, collected_events, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      {:error, :timeout}
    else
      wait_for_events_loop_continue(remaining_events, collected_events, deadline)
    end
  end

  defp wait_for_events_loop_continue(remaining_events, collected_events, deadline) do
    timeout = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {:telemetry_event, event_data} ->
        if Enum.member?(remaining_events, event_data.event) do
          new_remaining = List.delete(remaining_events, event_data.event)
          wait_for_events_loop(new_remaining, [event_data | collected_events], deadline)
        else
          wait_for_events_loop(remaining_events, collected_events, deadline)
        end
    after
      timeout ->
        {:error, :timeout}
    end
  end

  defp collect_events_loop(events, deadline) do
    if System.monotonic_time(:millisecond) > deadline do
      Enum.reverse(events)
    else
      collect_events_loop_continue(events, deadline)
    end
  end

  defp collect_events_loop_continue(events, deadline) do
    timeout = max(0, deadline - System.monotonic_time(:millisecond))

    receive do
      {:telemetry_event, event_data} ->
        collect_events_loop([event_data | events], deadline)
    after
      timeout ->
        Enum.reverse(events)
    end
  end

  defp verify_event_measurements(actual, expected) do
    Enum.each(expected, fn {key, expected_value} ->
      verify_single_measurement(actual, key, expected_value)
    end)
  end

  defp verify_event_metadata(actual, expected) do
    Enum.each(expected, fn {key, expected_value} ->
      verify_single_metadata(actual, key, expected_value)
    end)
  end

  defp matches_pattern?(event, pattern) do
    Enum.all?(pattern, fn {key, expected_value} ->
      check_pattern_match(event, key, expected_value)
    end)
  end

  defp count_event_types(events) do
    events
    |> Enum.group_by(& &1.event)
    |> Enum.map(fn {event_type, event_list} -> {event_type, length(event_list)} end)
    |> Enum.into(%{})
  end

  defp count_unique_event_types(events) do
    events
    |> Enum.map(& &1.event)
    |> Enum.uniq()
    |> length()
  end

  defp success_event?(event) do
    success_indicators = [
      "complete",
      "completed",
      "success",
      "successful",
      "reached",
      "registered",
      "started"
    ]

    event_name = event.event |> List.last() |> to_string()

    Enum.any?(success_indicators, fn indicator ->
      String.contains?(event_name, indicator)
    end) or Map.get(event.metadata, :result) == :success
  end

  defp error_event?(event) do
    error_indicators = [
      "error",
      "failed",
      "failure",
      "timeout",
      "crashed",
      "exception"
    ]

    event_name = event.event |> List.last() |> to_string()

    Enum.any?(error_indicators, fn indicator ->
      String.contains?(event_name, indicator)
    end) or Map.get(event.metadata, :result) == :error
  end

  defp calculate_avg_coordination_time(coordination_events) do
    durations =
      coordination_events
      |> Enum.filter(fn event -> Map.has_key?(event.measurements, :duration) end)
      |> Enum.map(fn event -> event.measurements.duration end)

    if length(durations) > 0 do
      Enum.sum(durations) / length(durations)
    else
      0.0
    end
  end

  defp calculate_coordination_success_rate(coordination_events) do
    success_events = Enum.filter(coordination_events, &success_event?/1)

    if length(coordination_events) > 0 do
      length(success_events) / length(coordination_events)
    else
      0.0
    end
  end

  defp valid_foundation_event_structure?(event) do
    # Check that event follows Foundation patterns
    is_list(event.event) and
      length(event.event) >= 2 and
      List.first(event.event) == :foundation and
      is_map(event.measurements) and
      is_map(event.metadata) and
      is_integer(event.timestamp)
  end

  defp group_events_by_time_window(events, window_size_ms) do
    events
    |> Enum.group_by(fn event ->
      # Round timestamp down to window boundary
      window_start = div(event.timestamp, window_size_ms * 1000) * window_size_ms * 1000
      window_start
    end)
    |> Enum.sort_by(fn {window_start, _events} -> window_start end)
  end

  defp generate_test_events(duration_seconds) do
    # Generate test telemetry events for benchmarking
    end_time = System.monotonic_time(:second) + duration_seconds

    spawn(fn ->
      generate_events_loop(end_time)
    end)
  end

  defp generate_events_loop(end_time) do
    if System.monotonic_time(:second) >= end_time do
      :ok
    else
      generate_events_loop_continue(end_time)
    end
  end

  defp generate_events_loop_continue(end_time) do
    # Emit test events
    :telemetry.execute([:foundation, :mabeam, :test, :event], %{counter: 1}, %{test: true})
    Process.sleep(10)
    generate_events_loop(end_time)
  end

  defp verify_single_measurement(actual, key, expected_value) do
    actual_value = Map.get(actual, key)

    case expected_value do
      :any ->
        if is_nil(actual_value) do
          raise "Expected measurement #{key} to be present"
        end

      value when is_function(value, 1) ->
        if not value.(actual_value) do
          raise "Measurement #{key} with value #{actual_value} failed validation"
        end

      ^actual_value ->
        :ok

      _ ->
        raise "Expected measurement #{key} to be #{expected_value}, got #{actual_value}"
    end
  end

  defp check_pattern_match(event, key, expected_value) do
    actual_value = get_in(event, [key])

    case expected_value do
      :any -> not is_nil(actual_value)
      value when is_function(value, 1) -> value.(actual_value)
      ^actual_value -> true
      _ -> false
    end
  end

  defp verify_single_metadata(actual, key, expected_value) do
    actual_value = Map.get(actual, key)

    case expected_value do
      :any ->
        if is_nil(actual_value) do
          raise "Expected metadata #{key} to be present"
        end

      value when is_function(value, 1) ->
        if not value.(actual_value) do
          raise "Metadata #{key} with value #{actual_value} failed validation"
        end

      ^actual_value ->
        :ok

      _ ->
        raise "Expected metadata #{key} to be #{expected_value}, got #{actual_value}"
    end
  end
end
