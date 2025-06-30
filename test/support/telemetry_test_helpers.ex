defmodule Foundation.TelemetryTestHelpers do
  @moduledoc """
  Comprehensive telemetry test helpers for event-driven testing.

  This module provides utilities for testing telemetry events without using
  Process.sleep, enabling deterministic and fast test execution.

  ## Key Features

  - Event capture and verification
  - Timeout-based event waiting
  - Pattern matching on events
  - Performance metric analysis
  - Bulk event operations
  - Integration test helpers

  ## Example Usage

      use Foundation.TelemetryTestHelpers
      
      test "service emits lifecycle events" do
        with_telemetry_capture do
          {:ok, _pid} = MyService.start_link()
          
          assert_telemetry_event [:foundation, :service, :started],
            %{startup_time: _},
            %{service: MyService}
        end
      end
  """

  import ExUnit.Assertions

  @default_timeout 5_000
  @poll_interval 10

  defmacro __using__(_opts) do
    quote do
      import Foundation.TelemetryTestHelpers
    end
  end

  # Event Capture and Verification

  @doc """
  Captures telemetry events during test execution.

  ## Options
    - `:events` - List of event patterns to capture (default: all)
    - `:timeout` - Maximum time to wait for events
    
  ## Example

      {events, result} = with_telemetry_capture events: [[:foundation, :_, :_]] do
        MyService.perform_operation()
      end
      
      assert length(events) == 3
  """
  defmacro with_telemetry_capture(opts \\ [], do: block) do
    quote do
      Foundation.TelemetryTestHelpers.capture_telemetry_events(
        unquote(opts),
        fn -> unquote(block) end
      )
    end
  end

  def capture_telemetry_events(opts, fun) do
    test_pid = self()
    ref = make_ref()
    event_patterns = Keyword.get(opts, :events, :all)

    # For capturing all events, we need to attach to known Foundation event prefixes
    events_to_attach =
      case event_patterns do
        :all ->
          [
            [:foundation],
            [:test],
            [:foundation, :service],
            [:foundation, :async],
            [:foundation, :resource],
            [:foundation, :circuit_breaker],
            [:foundation, :metrics],
            [:foundation, :mabeam],
            [:foundation, :mabeam, :registry],
            [:foundation, :mabeam, :coordination]
          ]

        patterns when is_list(patterns) ->
          # Convert patterns to concrete event prefixes
          Enum.map(patterns, fn pattern ->
            Enum.take_while(pattern, &(&1 != :_))
          end)
          |> Enum.uniq()
      end

    captured = :ets.new(:captured_events, [:public, :bag])

    config = %{
      test_pid: test_pid,
      ref: ref,
      patterns: if(event_patterns == :all, do: nil, else: event_patterns),
      captured: captured
    }

    handler = fn event, measurements, metadata, ^config ->
      if match_event_pattern?(event, event_patterns) do
        :ets.insert(config.captured, {event, measurements, metadata, System.monotonic_time()})
      end
    end

    handler_id = {__MODULE__, ref}

    # Attach to each event prefix
    Enum.each(events_to_attach, fn event_prefix ->
      try do
        :telemetry.attach_many(
          {handler_id, event_prefix},
          expand_event_patterns(event_prefix),
          handler,
          config
        )
      rescue
        # Ignore attachment errors for non-existent events
        _ -> :ok
      end
    end)

    try do
      result = fun.()
      # Small delay to ensure all events are captured
      Process.sleep(50)
      events = :ets.tab2list(captured) |> Enum.sort_by(&elem(&1, 3))
      {events, result}
    after
      # Detach all handlers
      Enum.each(events_to_attach, fn event_prefix ->
        try do
          :telemetry.detach({handler_id, event_prefix})
        rescue
          _ -> :ok
        end
      end)

      :ets.delete(captured)
    end
  end

  # Helper to expand event patterns for known Foundation events
  defp expand_event_patterns([:foundation]) do
    [
      [:foundation, :service, :started],
      [:foundation, :service, :stopped],
      [:foundation, :service, :error],
      [:foundation, :async, :started],
      [:foundation, :async, :completed],
      [:foundation, :async, :failed],
      [:foundation, :resource, :acquired],
      [:foundation, :resource, :released],
      [:foundation, :resource, :exhausted],
      [:foundation, :circuit_breaker, :state_change],
      [:foundation, :cache, :hit],
      [:foundation, :cache, :miss],
      [:foundation, :cache, :put],
      [:foundation, :cache, :delete],
      [:foundation, :cache, :cleared],
      [:foundation, :cache, :evicted],
      [:foundation, :cache, :cleanup],
      [:foundation, :cache, :started],
      [:foundation, :cache, :error],
      [:foundation, :signal_bus, :health_check],
      [:foundation, :resource_manager, :acquired],
      [:foundation, :resource_manager, :released],
      [:foundation, :resource_manager, :denied],
      [:foundation, :resource_manager, :cleanup]
    ]
  end

  defp expand_event_patterns([:test]) do
    [
      [:test, :event],
      [:test, :span, :start],
      [:test, :span, :stop],
      [:test, :span, :exception],
      [:test, :delayed],
      [:test, :first],
      [:test, :second],
      [:test, :third],
      [:test, :perf],
      [:test, :should_not_happen],
      [:test, :never_emitted]
    ]
  end

  defp expand_event_patterns([:foundation, :metrics]) do
    [[:foundation, :metrics, :response_time]]
  end

  defp expand_event_patterns([:foundation, :mabeam, :registry]) do
    [
      [:foundation, :mabeam, :registry, :register],
      [:foundation, :mabeam, :registry, :register_failed],
      [:foundation, :mabeam, :registry, :unregister],
      [:foundation, :mabeam, :registry, :unregister_failed],
      [:foundation, :mabeam, :registry, :update],
      [:foundation, :mabeam, :registry, :update_failed],
      [:foundation, :mabeam, :registry, :query],
      [:foundation, :mabeam, :registry, :batch_operation],
      [:foundation, :mabeam, :registry, :agent_down]
    ]
  end

  defp expand_event_patterns([:foundation, :mabeam, :coordination]) do
    [
      [:foundation, :mabeam, :coordination, :started],
      [:foundation, :mabeam, :coordination, :failed],
      [:foundation, :mabeam, :coordination, :resource_allocation],
      [:foundation, :mabeam, :coordination, :resource_allocation_failed],
      [:foundation, :mabeam, :coordination, :load_balancing],
      [:foundation, :mabeam, :coordination, :consensus_started],
      [:foundation, :mabeam, :coordination, :consensus_completed],
      [:foundation, :mabeam, :coordination, :consensus_failed],
      [:foundation, :mabeam, :coordination, :barrier_created],
      [:foundation, :mabeam, :coordination, :barrier_completed],
      [:foundation, :mabeam, :coordination, :capability_transition]
    ]
  end

  defp expand_event_patterns(prefix) do
    # For other prefixes, just use the prefix itself
    [prefix]
  end

  @doc """
  Asserts that a specific telemetry event is emitted.

  ## Example

      assert_telemetry_event [:foundation, :circuit_breaker, :opened],
        %{error_count: count} when count > 5,
        %{service: :payment_gateway},
        timeout: 1000 do
          
        CircuitBreaker.trip(:payment_gateway)
      end
  """
  defmacro assert_telemetry_event(event_pattern, measurements \\ %{}, metadata \\ %{}, opts \\ [],
             do: block
           ) do
    quote do
      Foundation.TelemetryTestHelpers.do_assert_telemetry_event(
        unquote(event_pattern),
        unquote(measurements),
        unquote(metadata),
        unquote(opts),
        fn -> unquote(block) end
      )
    end
  end

  def do_assert_telemetry_event(event_pattern, expected_measurements, expected_metadata, opts, fun) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    test_pid = self()
    ref = make_ref()

    handler = fn event, measurements, metadata, _config ->
      if match_event?(event, event_pattern) do
        send(test_pid, {:telemetry_event, ref, event, measurements, metadata})
      end
    end

    handler_id = {__MODULE__, :assert, ref}
    :telemetry.attach(handler_id, event_pattern, handler, nil)

    try do
      result = fun.()

      receive do
        {:telemetry_event, ^ref, event, measurements, metadata} ->
          assert match_measurements?(measurements, expected_measurements),
                 "Measurements mismatch. Expected: #{inspect(expected_measurements)}, Got: #{inspect(measurements)}"

          assert match_metadata?(metadata, expected_metadata),
                 "Metadata mismatch. Expected: #{inspect(expected_metadata)}, Got: #{inspect(metadata)}"

          {event, measurements, metadata, result}
      after
        timeout ->
          flunk(
            "Expected telemetry event #{inspect(event_pattern)} was not emitted within #{timeout}ms"
          )
      end
    after
      :telemetry.detach(handler_id)
    end
  end

  @doc """
  Waits for a telemetry event without assertions.

  ## Example

      {:ok, {event, measurements, metadata}} = wait_for_telemetry_event(
        [:foundation, :async, :completed],
        timeout: 2000
      )
  """
  def wait_for_telemetry_event(event_pattern, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    test_pid = self()
    ref = make_ref()

    handler = fn event, measurements, metadata, _config ->
      if match_event?(event, event_pattern) do
        send(test_pid, {:telemetry_event, ref, event, measurements, metadata})
      end
    end

    handler_id = {__MODULE__, :wait, ref}
    :telemetry.attach(handler_id, event_pattern, handler, nil)

    try do
      receive do
        {:telemetry_event, ^ref, event, measurements, metadata} ->
          {:ok, {event, measurements, metadata}}
      after
        timeout ->
          {:error, :timeout}
      end
    after
      :telemetry.detach(handler_id)
    end
  end

  @doc """
  Refutes that a telemetry event is emitted within a timeout period.

  ## Example

      refute_telemetry_event [:foundation, :error, :critical], timeout: 100 do
        SafeOperation.execute()
      end
  """
  defmacro refute_telemetry_event(event_pattern, opts \\ [], do: block) do
    quote do
      Foundation.TelemetryTestHelpers.do_refute_telemetry_event(
        unquote(event_pattern),
        unquote(opts),
        fn -> unquote(block) end
      )
    end
  end

  def do_refute_telemetry_event(event_pattern, opts, fun) do
    timeout = Keyword.get(opts, :timeout, 100)
    test_pid = self()
    ref = make_ref()

    handler = fn event, _measurements, _metadata, _config ->
      if match_event?(event, event_pattern) do
        send(test_pid, {:unexpected_event, ref, event})
      end
    end

    handler_id = {__MODULE__, :refute, ref}
    :telemetry.attach(handler_id, event_pattern, handler, nil)

    try do
      result = fun.()

      receive do
        {:unexpected_event, ^ref, event} ->
          flunk("Unexpected telemetry event emitted: #{inspect(event)}")
      after
        timeout -> result
      end
    after
      :telemetry.detach(handler_id)
    end
  end

  @doc """
  Waits for multiple telemetry events in order.

  ## Example

      events = wait_for_telemetry_events [
        [:foundation, :task, :started],
        [:foundation, :task, :checkpoint],
        [:foundation, :task, :completed]
      ], timeout: 3000
      
      assert length(events) == 3
  """
  def wait_for_telemetry_events(event_patterns, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    deadline = System.monotonic_time(:millisecond) + timeout

    Enum.reduce_while(event_patterns, [], fn pattern, acc ->
      remaining = deadline - System.monotonic_time(:millisecond)

      if remaining > 0 do
        case wait_for_telemetry_event(pattern, timeout: remaining) do
          {:ok, event_data} ->
            {:cont, [event_data | acc]}

          {:error, :timeout} ->
            {:halt, {:error, {:timeout, pattern, Enum.reverse(acc)}}}
        end
      else
        {:halt, {:error, {:timeout, pattern, Enum.reverse(acc)}}}
      end
    end)
    |> case do
      {:error, _} = error -> error
      events -> {:ok, Enum.reverse(events)}
    end
  end

  @doc """
  Polls for a condition using telemetry events.

  ## Example

      assert poll_with_telemetry fn ->
        {:ok, metrics} = get_latest_telemetry_metrics([:foundation, :pool, :stats])
        metrics.active_connections > 5
      end, timeout: 2000
  """
  def poll_with_telemetry(condition_fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    interval = Keyword.get(opts, :interval, @poll_interval)
    deadline = System.monotonic_time(:millisecond) + timeout

    poll_loop(condition_fun, deadline, interval)
  end

  defp poll_loop(condition_fun, deadline, interval) do
    case condition_fun.() do
      true ->
        true

      false ->
        if System.monotonic_time(:millisecond) < deadline do
          Process.sleep(interval)
          poll_loop(condition_fun, deadline, interval)
        else
          false
        end

      result ->
        result
    end
  end

  @doc """
  Gets the latest metrics from telemetry events.

  ## Example

      {:ok, metrics} = get_latest_telemetry_metrics([:foundation, :cache, :stats])
      assert metrics.hit_rate > 0.8
  """
  def get_latest_telemetry_metrics(event_pattern, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 100)
    test_pid = self()
    ref = make_ref()
    latest = :ets.new(:latest_metrics, [:set, :public])

    handler = fn event, measurements, metadata, _config ->
      if match_event?(event, event_pattern) do
        :ets.insert(latest, {:latest, measurements, metadata})
        send(test_pid, {:metrics_updated, ref})
      end
    end

    handler_id = {__MODULE__, :metrics, ref}
    :telemetry.attach(handler_id, event_pattern, handler, nil)

    try do
      receive do
        {:metrics_updated, ^ref} ->
          case :ets.lookup(latest, :latest) do
            [{:latest, measurements, metadata}] ->
              {:ok, Map.merge(measurements, metadata)}

            [] ->
              {:error, :no_metrics}
          end
      after
        timeout -> {:error, :timeout}
      end
    after
      :telemetry.detach(handler_id)
      :ets.delete(latest)
    end
  end

  @doc """
  Asserts telemetry events are emitted in a specific order.

  ## Example

      assert_telemetry_order [
        [:foundation, :request, :start],
        [:foundation, :auth, :verified],
        [:foundation, :request, :complete]
      ] do
        handle_authenticated_request()
      end
  """
  defmacro assert_telemetry_order(event_patterns, opts \\ [], do: block) do
    quote do
      Foundation.TelemetryTestHelpers.do_assert_telemetry_order(
        unquote(event_patterns),
        unquote(opts),
        fn -> unquote(block) end
      )
    end
  end

  def do_assert_telemetry_order(event_patterns, opts, fun) do
    _timeout = Keyword.get(opts, :timeout, @default_timeout)

    {events, result} = capture_telemetry_events([events: :all], fun)

    # Extract just the event names from captured events
    emitted_events = Enum.map(events, fn {event, _, _, _} -> event end)

    # Check if the patterns appear in order
    assert_events_in_order(event_patterns, emitted_events)

    {events, result}
  end

  defp assert_events_in_order([], _emitted), do: :ok

  defp assert_events_in_order([pattern | rest], emitted) do
    case find_and_drop_until(pattern, emitted) do
      {:ok, remaining} ->
        assert_events_in_order(rest, remaining)

      :not_found ->
        flunk("Expected event pattern #{inspect(pattern)} not found in order")
    end
  end

  defp find_and_drop_until(pattern, events) do
    case Enum.drop_while(events, fn event -> not match_event?(event, pattern) end) do
      [] -> :not_found
      [_ | rest] -> {:ok, rest}
    end
  end

  # Performance Testing Helpers

  @doc """
  Measures performance metrics of an operation via telemetry.

  ## Example

      metrics = measure_telemetry_performance [:foundation, :db, :query] do
        Database.complex_query()
      end
      
      assert metrics.duration < 100_000 # microseconds
      assert metrics.count == 1
  """
  defmacro measure_telemetry_performance(event_pattern, do: block) do
    quote do
      Foundation.TelemetryTestHelpers.do_measure_telemetry_performance(
        unquote(event_pattern),
        fn -> unquote(block) end
      )
    end
  end

  def do_measure_telemetry_performance(event_pattern, fun) do
    {events, _result} = capture_telemetry_events([events: [event_pattern]], fun)

    measurements =
      events
      |> Enum.map(fn {_, measurements, _, _} -> measurements end)
      |> Enum.reduce(%{count: 0, total_duration: 0, events: []}, fn m, acc ->
        %{
          count: acc.count + 1,
          total_duration: acc.total_duration + Map.get(m, :duration, 0),
          events: [m | acc.events]
        }
      end)

    %{
      count: measurements.count,
      total_duration: measurements.total_duration,
      average_duration:
        if(measurements.count > 0, do: measurements.total_duration / measurements.count, else: 0),
      events: Enum.reverse(measurements.events)
    }
  end

  # Utility Functions

  defp match_event_pattern?(_event, :all), do: true

  defp match_event_pattern?(event, patterns) when is_list(patterns) do
    Enum.any?(patterns, &match_event?(event, &1))
  end

  defp match_event?(event, pattern) when is_list(event) and is_list(pattern) do
    length(event) == length(pattern) &&
      Enum.zip(event, pattern)
      |> Enum.all?(fn {e, p} -> p == :_ or e == p end)
  end

  defp match_event?(event, pattern), do: event == pattern

  defp match_measurements?(measurements, expected) when is_map(expected) do
    Enum.all?(expected, fn
      {key, expected_value} when is_function(expected_value, 1) ->
        expected_value.(Map.get(measurements, key))

      {key, expected_value} ->
        Map.get(measurements, key) == expected_value
    end)
  end

  defp match_measurements?(measurements, expected) when is_function(expected, 1) do
    expected.(measurements)
  end

  defp match_measurements?(_measurements, _expected), do: true

  defp match_metadata?(metadata, expected) when is_map(expected) do
    Enum.all?(expected, fn
      {key, expected_value} when is_function(expected_value, 1) ->
        expected_value.(Map.get(metadata, key))

      {key, expected_value} ->
        Map.get(metadata, key) == expected_value
    end)
  end

  defp match_metadata?(metadata, expected) when is_function(expected, 1) do
    expected.(metadata)
  end

  defp match_metadata?(_metadata, _expected), do: true

  # Additional helpers for resource and timing scenarios

  @doc """
  Waits for a condition to become true, checking periodically.

  ## Example

      assert wait_for_condition(fn ->
        Process.info(pid, :memory)[:memory] < 1000
      end, timeout: 1000, interval: 50)
  """
  def wait_for_condition(condition_fn, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    interval = Keyword.get(opts, :interval, @poll_interval)
    deadline = System.monotonic_time(:millisecond) + timeout

    do_wait_for_condition(condition_fn, deadline, interval)
  end

  defp do_wait_for_condition(condition_fn, deadline, interval) do
    if condition_fn.() do
      true
    else
      now = System.monotonic_time(:millisecond)

      if now < deadline do
        Process.sleep(interval)
        do_wait_for_condition(condition_fn, deadline, interval)
      else
        false
      end
    end
  end

  @doc """
  Asserts that a condition eventually becomes true.

  ## Example

      assert_eventually fn ->
        length(Agent.get(agent, & &1)) == 10
      end, timeout: 2000, message: "Agent should have 10 items"
  """
  defmacro assert_eventually(condition, opts \\ []) do
    quote do
      timeout = Keyword.get(unquote(opts), :timeout, 5000)
      message = Keyword.get(unquote(opts), :message, "Condition did not become true within timeout")

      unless Foundation.TelemetryTestHelpers.wait_for_condition(
               unquote(condition),
               timeout: timeout
             ) do
        flunk(message)
      end
    end
  end

  @doc """
  Waits for garbage collection to complete by monitoring memory changes.

  ## Example

      wait_for_gc_completion()
  """
  def wait_for_gc_completion(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 1000)
    initial_memory = :erlang.memory(:total)

    # Force GC
    :erlang.garbage_collect()

    # Wait for memory to stabilize
    wait_for_condition(
      fn ->
        current_memory = :erlang.memory(:total)
        # Less than 1% change
        abs(current_memory - initial_memory) < initial_memory * 0.01
      end,
      timeout: timeout,
      interval: 50
    )
  end

  @doc """
  Waits for resource manager cleanup cycle.

  ## Example

      wait_for_resource_cleanup()
  """
  def wait_for_resource_cleanup(opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 2000)

    # Force a cleanup if possible
    if Process.whereis(Foundation.ResourceManager) do
      try do
        Foundation.ResourceManager.force_cleanup()
      catch
        _, _ -> :ok
      end
    end

    # Wait for cleanup telemetry event
    wait_for_telemetry_event(
      [:foundation, :resource_manager, :cleanup],
      timeout: timeout
    )
  end
end
