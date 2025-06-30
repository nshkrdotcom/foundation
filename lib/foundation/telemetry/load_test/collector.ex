defmodule Foundation.Telemetry.LoadTest.Collector do
  @moduledoc """
  Collects and aggregates telemetry metrics from load test executions.

  This module attaches to telemetry events emitted by workers and maintains
  statistics about scenario execution, including success rates, latencies,
  and error distributions.
  """

  use GenServer
  require Logger

  defmodule State do
    @moduledoc false
    defstruct [
      :context,
      :recording,
      :start_time,
      :scenario_stats,
      :errors,
      :telemetry_handlers
    ]
  end

  defmodule ScenarioStats do
    @moduledoc false
    defstruct [
      :name,
      :total_count,
      :success_count,
      :error_count,
      :latencies,
      :min_latency,
      :max_latency,
      :sum_latency,
      :p50_latency,
      :p95_latency,
      :p99_latency
    ]

    def new(name) do
      %__MODULE__{
        name: name,
        total_count: 0,
        success_count: 0,
        error_count: 0,
        latencies: [],
        min_latency: nil,
        max_latency: nil,
        sum_latency: 0,
        p50_latency: nil,
        p95_latency: nil,
        p99_latency: nil
      }
    end

    def record_execution(stats, duration, status) do
      %{
        stats
        | total_count: stats.total_count + 1,
          success_count: if(status == :ok, do: stats.success_count + 1, else: stats.success_count),
          error_count: if(status == :error, do: stats.error_count + 1, else: stats.error_count),
          # Keep last 10k samples
          latencies: [duration | stats.latencies] |> Enum.take(10_000),
          min_latency: min(stats.min_latency || duration, duration),
          max_latency: max(stats.max_latency || duration, duration),
          sum_latency: stats.sum_latency + duration
      }
    end

    def calculate_percentiles(stats) do
      if stats.latencies == [] do
        stats
      else
        sorted = Enum.sort(stats.latencies)
        count = length(sorted)

        %{
          stats
          | p50_latency: percentile(sorted, count, 0.50),
            p95_latency: percentile(sorted, count, 0.95),
            p99_latency: percentile(sorted, count, 0.99)
        }
      end
    end

    defp percentile(sorted_list, count, p) do
      index = round(p * (count - 1))
      Enum.at(sorted_list, index)
    end
  end

  def start_link(context) do
    GenServer.start_link(__MODULE__, context)
  end

  def get_stats(collector) do
    GenServer.call(collector, :get_stats)
  end

  def stop_collection(collector) do
    GenServer.call(collector, :stop_collection, 10_000)
  end

  def generate_report(collector, context) do
    GenServer.call(collector, {:generate_report, context}, 10_000)
  end

  # GenServer callbacks

  @impl true
  def init(context) do
    Logger.debug("Collector init called with test_id: #{context.test_id}")

    # Initialize stats for each scenario
    scenario_stats =
      context.scenarios
      |> Enum.map(fn scenario -> {scenario.name, ScenarioStats.new(scenario.name)} end)
      |> Map.new()

    state = %State{
      context: context,
      recording: false,
      start_time: nil,
      scenario_stats: scenario_stats,
      errors: [],
      telemetry_handlers: []
    }

    # Attach telemetry handlers
    handlers = attach_telemetry_handlers(context.opts[:telemetry_prefix])
    Logger.debug("Collector initialized with #{length(handlers)} telemetry handlers")

    {:ok, %{state | telemetry_handlers: handlers}}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      recording: state.recording,
      scenarios:
        Map.new(state.scenario_stats, fn {name, stats} ->
          {name,
           %{
             total: stats.total_count,
             success: stats.success_count,
             error: stats.error_count,
             avg_latency_us:
               if(stats.total_count > 0, do: div(stats.sum_latency, stats.total_count), else: 0)
           }}
        end),
      total_requests: Enum.sum(Enum.map(state.scenario_stats, fn {_, s} -> s.total_count end)),
      error_count: length(state.errors)
    }

    {:reply, stats, state}
  end

  def handle_call(:stop_collection, _from, state) do
    # Stop recording first
    new_state = %{state | recording: false}

    # Detach telemetry handlers in a separate process to avoid blocking
    handlers = state.telemetry_handlers

    spawn(fn ->
      Enum.each(handlers, fn handler ->
        try do
          :telemetry.detach(handler)
        catch
          :error, :badarg -> :ok
        end
      end)
    end)

    {:reply, :ok, %{new_state | telemetry_handlers: []}}
  end

  def handle_call({:generate_report, context}, _from, state) do
    end_time = DateTime.utc_now()

    duration_ms =
      if state.start_time do
        DateTime.diff(end_time, state.start_time, :millisecond)
      else
        0
      end

    # Calculate final percentiles
    scenario_stats =
      Map.new(state.scenario_stats, fn {name, stats} ->
        {name, ScenarioStats.calculate_percentiles(stats)}
      end)

    # Build report
    report = %{
      start_time: state.start_time || context.start_time,
      end_time: end_time,
      duration_ms: duration_ms,
      total_requests: Enum.sum(Enum.map(scenario_stats, fn {_, s} -> s.total_count end)),
      successful_requests: Enum.sum(Enum.map(scenario_stats, fn {_, s} -> s.success_count end)),
      failed_requests: Enum.sum(Enum.map(scenario_stats, fn {_, s} -> s.error_count end)),
      scenarios: format_scenario_stats(scenario_stats),
      metrics: calculate_overall_metrics(scenario_stats, duration_ms),
      # Limit errors in report
      errors: Enum.take(state.errors, 100)
    }

    # Log summary
    log_report_summary(report)

    {:reply, {:ok, report}, state}
  end

  defp flush_pending_events(state, count \\ 0) do
    # Limit how many events we process to avoid infinite loops
    if count > 1000 do
      Logger.warning("Collector flushed 1000 pending events, stopping flush")
      state
    else
      receive do
        {:telemetry_event, measurements, metadata} ->
          new_state =
            if state.recording and metadata[:test_id] == state.context.test_id do
              record_telemetry_event(measurements, metadata, state)
            else
              state
            end

          flush_pending_events(new_state, count + 1)
      after
        0 ->
          if count > 0 do
            Logger.debug("Collector flushed #{count} pending events")
          end

          state
      end
    end
  end

  @impl true
  def handle_info({:start_recording, reply_to}, state) do
    Logger.info("Load test collector started recording metrics")
    new_state = %{state | recording: true, start_time: DateTime.utc_now()}
    if reply_to, do: send(reply_to, :recording_started)
    {:noreply, new_state}
  end

  # Legacy support for tests that don't provide reply_to
  def handle_info(:start_recording, state) do
    handle_info({:start_recording, nil}, state)
  end

  @impl true
  def handle_info(:flush_pending_events, state) do
    final_state = flush_pending_events(state)
    {:noreply, final_state}
  end

  def handle_info({:telemetry_event, measurements, metadata}, state) do
    # Skip processing if not recording to avoid blocking GenServer calls
    if state.recording and metadata[:test_id] == state.context.test_id do
      new_state = record_telemetry_event(measurements, metadata, state)
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end

  # High priority message to stop recording immediately
  def handle_info(:stop_recording_immediately, state) do
    {:noreply, %{state | recording: false}}
  end

  @impl true
  def terminate(_reason, state) do
    # Detach telemetry handlers (if not already detached)
    Enum.each(state.telemetry_handlers, fn handler ->
      try do
        :telemetry.detach(handler)
      catch
        # Already detached
        :error, :badarg -> :ok
      end
    end)

    :ok
  end

  # Private functions

  defp attach_telemetry_handlers(prefix) do
    # Use a unique handler ID based on process pid and timestamp to avoid conflicts
    handler_id = "load-test-collector-#{System.unique_integer([:positive])}"

    handlers = [
      {
        "#{handler_id}-scenario-stop",
        prefix ++ [:scenario, :stop],
        &handle_telemetry_event/4
      }
    ]

    Enum.map(handlers, fn {name, event, handler} ->
      # First detach if it exists (from previous test runs)
      try do
        :telemetry.detach(name)
      catch
        :error, :badarg -> :ok
      end

      :telemetry.attach(name, event, handler, self())
      name
    end)
  end

  defp handle_telemetry_event(_event, measurements, metadata, collector_pid) do
    # Check message queue size to avoid overwhelming the collector
    case Process.info(collector_pid, :message_queue_len) do
      {:message_queue_len, queue_len} when queue_len > 1_000 ->
        # Sample 1% of events when queue is large to still get some data
        if :rand.uniform(100) == 1 do
          send(collector_pid, {:telemetry_event, measurements, metadata})
        end

        :ok

      _ ->
        # Send asynchronously to avoid blocking the caller
        send(collector_pid, {:telemetry_event, measurements, metadata})
        :ok
    end
  end

  defp record_telemetry_event(measurements, metadata, state) do
    scenario_name = metadata[:scenario_name]

    if Map.has_key?(state.scenario_stats, scenario_name) do
      # Update scenario stats
      stats = Map.get(state.scenario_stats, scenario_name)

      # Debug logging for error tracking
      if scenario_name == :error_generator and
           state.scenario_stats[:error_generator].total_count < 5 do
        Logger.debug(
          "Recording event for error_generator: status=#{inspect(metadata.status)}, error=#{inspect(metadata[:error])}"
        )
      end

      updated_stats = ScenarioStats.record_execution(stats, measurements.duration, metadata.status)

      new_scenario_stats = Map.put(state.scenario_stats, scenario_name, updated_stats)

      # Record error if present
      new_errors =
        if metadata[:error] do
          error = %{
            timestamp: DateTime.utc_now(),
            scenario: scenario_name,
            worker_id: metadata[:worker_id],
            error: metadata[:error]
          }

          [error | state.errors]
        else
          state.errors
        end

      %{state | scenario_stats: new_scenario_stats, errors: new_errors}
    else
      state
    end
  end

  defp format_scenario_stats(scenario_stats) do
    Map.new(scenario_stats, fn {name, stats} ->
      throughput =
        if stats.sum_latency > 0 do
          stats.total_count * 1_000_000 / stats.sum_latency
        else
          0.0
        end

      {name,
       %{
         total_requests: stats.total_count,
         successful_requests: stats.success_count,
         failed_requests: stats.error_count,
         success_rate:
           if(stats.total_count > 0, do: stats.success_count / stats.total_count * 100, else: 0.0),
         throughput_rps: Float.round(throughput, 2),
         latency: %{
           min_us: stats.min_latency,
           max_us: stats.max_latency,
           avg_us:
             if(stats.total_count > 0, do: div(stats.sum_latency, stats.total_count), else: 0),
           p50_us: stats.p50_latency,
           p95_us: stats.p95_latency,
           p99_us: stats.p99_latency
         }
       }}
    end)
  end

  defp calculate_overall_metrics(scenario_stats, duration_ms) do
    total_requests = Enum.sum(Enum.map(scenario_stats, fn {_, s} -> s.total_count end))
    successful_requests = Enum.sum(Enum.map(scenario_stats, fn {_, s} -> s.success_count end))

    %{
      throughput_rps:
        if(duration_ms > 0, do: Float.round(total_requests * 1000 / duration_ms, 2), else: 0.0),
      success_rate:
        if(total_requests > 0,
          do: Float.round(successful_requests / total_requests * 100, 2),
          else: 0.0
        ),
      duration_seconds: Float.round(duration_ms / 1000, 2)
    }
  end

  defp log_report_summary(report) do
    Logger.info("""

    Load Test Report Summary
    ========================
    Duration: #{report.metrics.duration_seconds}s
    Total Requests: #{report.total_requests}
    Successful: #{report.successful_requests}
    Failed: #{report.failed_requests}
    Success Rate: #{report.metrics.success_rate}%
    Overall Throughput: #{report.metrics.throughput_rps} req/s

    Scenario Results:
    #{format_scenario_summary(report.scenarios)}
    """)
  end

  defp format_scenario_summary(scenarios) do
    scenarios
    |> Enum.map_join("\n", fn {name, stats} ->
      """
      - #{name}:
        Requests: #{stats.total_requests}
        Success Rate: #{Float.round(stats.success_rate, 2)}%
        Throughput: #{stats.throughput_rps} req/s
        Avg Latency: #{stats.latency.avg_us}μs
        P95 Latency: #{stats.latency.p95_us}μs
      """
    end)
  end
end
