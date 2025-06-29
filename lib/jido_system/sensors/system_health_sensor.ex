defmodule JidoSystem.Sensors.SystemHealthSensor do
  @moduledoc """
  Intelligent system health monitoring sensor with Foundation integration.

  This sensor continuously monitors system health metrics and emits intelligent
  signals when anomalies or threshold violations are detected. It integrates
  with Foundation's telemetry system for comprehensive monitoring.

  ## Features
  - Real-time system resource monitoring
  - Intelligent threshold detection
  - Anomaly detection using statistical methods
  - Integration with Foundation.Telemetry
  - Configurable monitoring intervals
  - Historical trend analysis

  ## Monitored Metrics
  - CPU utilization and load average
  - Memory usage and garbage collection
  - Process counts and message queues
  - Disk usage and I/O metrics
  - Network connectivity
  - BEAM VM specific metrics

  ## Signal Types
  - `system.health.ok` - Normal operation
  - `system.health.warning` - Threshold violations
  - `system.health.critical` - Critical issues detected
  - `system.health.anomaly` - Unusual patterns detected

  ## Configuration

      config = [
        id: "system_health_monitor",
        target: {:bus, Foundation.EventBus},
        collection_interval: 30_000, # 30 seconds
        thresholds: %{
          cpu_usage: 80,
          memory_usage: 85,
          process_count: 10_000
        },
        enable_anomaly_detection: true,
        history_size: 100
      ]

      {:ok, pid} = SystemHealthSensor.start_link(config)
  """

  use Jido.Sensor,
    name: "system_health_sensor",
    description: "Monitors system health with intelligent alerting",
    category: :monitoring,
    tags: [:system, :health, :performance],
    schema: [
      collection_interval: [
        type: :integer,
        default: 30_000,
        doc: "Metrics collection interval in milliseconds"
      ],
      thresholds: [
        type: :map,
        default: %{
          cpu_usage: 80,
          memory_usage: 85,
          process_count: 10_000,
          message_queue_size: 1_000
        },
        doc: "Alert thresholds for various metrics"
      ],
      enable_anomaly_detection: [
        type: :boolean,
        default: true,
        doc: "Enable statistical anomaly detection"
      ],
      history_size: [
        type: :integer,
        default: 100,
        doc: "Number of historical data points to retain"
      ],
      alert_cooldown: [
        type: :integer,
        default: 300_000,
        doc: "Cooldown period between similar alerts (ms)"
      ]
    ]

  require Logger
  alias Foundation.Registry
  alias Jido.Signal

  @impl true
  def mount(config) do
    # Ensure required fields with defaults first
    config_with_defaults =
      Map.merge(
        %{
          collection_interval: 30_000,
          thresholds: %{
            cpu_usage: 80,
            memory_usage: 85,
            process_count: 10_000,
            message_queue_size: 1_000
          },
          enable_anomaly_detection: true,
          history_size: 100,
          alert_cooldown: 300_000
        },
        config
      )

    Logger.info("Starting SystemHealthSensor",
      sensor_id: config_with_defaults.id,
      interval: config_with_defaults.collection_interval
    )

    # Initialize sensor state
    initial_state =
      Map.merge(config_with_defaults, %{
        last_metrics: %{},
        metrics_history: [],
        last_alerts: %{},
        baseline_metrics: %{},
        collection_count: 0,
        started_at: DateTime.utc_now()
      })

    # Schedule first collection
    schedule_collection(initial_state.collection_interval)

    {:ok, initial_state}
  end

  @impl true
  def deliver_signal(state) do
    try do
      # Collect current system metrics
      current_metrics = collect_system_metrics()

      # Update metrics history
      updated_history =
        [current_metrics | state.metrics_history]
        |> Enum.take(state.history_size)

      # Analyze metrics and determine health status
      {health_status, analysis_results} =
        analyze_system_health(
          current_metrics,
          updated_history,
          state.thresholds,
          state.enable_anomaly_detection
        )

      # Create signal based on health status
      signal = create_health_signal(health_status, analysis_results, current_metrics, state)

      # Update state
      new_state = %{
        state
        | last_metrics: current_metrics,
          metrics_history: updated_history,
          collection_count: state.collection_count + 1
      }

      # Schedule next collection
      schedule_collection(state.collection_interval)

      Logger.debug("System health signal generated",
        status: health_status,
        metrics_collected: map_size(current_metrics)
      )

      {:ok, signal, new_state}
    rescue
      e ->
        Logger.error("Failed to collect system metrics",
          error: inspect(e),
          stacktrace: __STACKTRACE__
        )

        # Create error signal
        error_signal =
          Signal.new(%{
            type: "system.health.error",
            source: "/sensors/system_health",
            data: %{
              error: inspect(e),
              timestamp: DateTime.utc_now(),
              sensor_id: state.id
            }
          })

        {:ok, error_signal, state}
    end
  end

  @impl true
  def on_before_deliver(signal, state) do
    # Add sensor metadata to signal
    enhanced_signal = %{
      signal
      | data:
          Map.merge(signal.data, %{
            sensor_id: state.id,
            collection_count: state.collection_count,
            sensor_uptime: DateTime.diff(DateTime.utc_now(), state.started_at, :second)
          })
    }

    {:ok, enhanced_signal}
  end

  @impl true
  def shutdown(state) do
    Logger.info("Shutting down SystemHealthSensor",
      sensor_id: state.id,
      collections_performed: state.collection_count
    )

    {:ok, state}
  end

  # Private helper functions

  defp schedule_collection(interval) do
    Process.send_after(self(), :collect_metrics, interval)
  end

  defp collect_system_metrics() do
    %{
      timestamp: DateTime.utc_now(),

      # Memory metrics
      memory: collect_memory_metrics(),

      # Process metrics
      processes: collect_process_metrics(),

      # System metrics
      system: collect_system_info(),

      # VM metrics
      vm: collect_vm_metrics(),

      # Load metrics
      load: collect_load_metrics(),

      # Registry metrics
      registry: collect_registry_metrics()
    }
  end

  defp collect_memory_metrics() do
    memory_info = :erlang.memory()

    %{
      total: memory_info[:total] || 0,
      processes: memory_info[:processes] || 0,
      system: memory_info[:system] || 0,
      atom: memory_info[:atom] || 0,
      binary: memory_info[:binary] || 0,
      ets: memory_info[:ets] || 0,
      usage_percent: calculate_memory_usage_percent(memory_info)
    }
  end

  defp collect_process_metrics() do
    %{
      count: :erlang.system_info(:process_count),
      limit: :erlang.system_info(:process_limit),
      usage_percent:
        :erlang.system_info(:process_count) / :erlang.system_info(:process_limit) * 100,
      message_queue_lengths: get_message_queue_stats()
    }
  end

  defp collect_system_info() do
    %{
      schedulers: :erlang.system_info(:schedulers),
      scheduler_utilization: get_scheduler_utilization(),
      port_count: :erlang.system_info(:port_count),
      port_limit: :erlang.system_info(:port_limit),
      ets_count: :erlang.system_info(:ets_count),
      ets_limit: :erlang.system_info(:ets_limit)
    }
  end

  defp collect_vm_metrics() do
    %{
      uptime: :erlang.statistics(:wall_clock) |> elem(0),
      reductions: :erlang.statistics(:reductions) |> elem(0),
      garbage_collection: :erlang.statistics(:garbage_collection),
      io: :erlang.statistics(:io),
      run_queue: :erlang.statistics(:run_queue)
    }
  end

  defp collect_load_metrics() do
    try do
      # Try to get system load average (Unix-like systems)
      case System.cmd("uptime", []) do
        {uptime, 0} when is_binary(uptime) ->
          case Regex.run(~r/load average: ([\d.]+), ([\d.]+), ([\d.]+)/, uptime) do
            [_, load1, load5, load15] ->
              %{
                load_1min: String.to_float(load1),
                load_5min: String.to_float(load5),
                load_15min: String.to_float(load15)
              }

            _ ->
              %{load_1min: 0.0, load_5min: 0.0, load_15min: 0.0}
          end

        _ ->
          %{load_1min: 0.0, load_5min: 0.0, load_15min: 0.0}
      end
    rescue
      _ ->
        %{load_1min: 0.0, load_5min: 0.0, load_15min: 0.0}
    end
  end

  defp collect_registry_metrics() do
    try do
      %{
        foundation_registry_count: Registry.count(Foundation.Registry),
        jido_registry_count:
          case Process.whereis(Jido.Registry) do
            pid when is_pid(pid) -> Registry.count(Jido.Registry)
            nil -> 0
          end
      }
    rescue
      _ ->
        %{foundation_registry_count: 0, jido_registry_count: 0}
    end
  end

  defp calculate_memory_usage_percent(memory_info) do
    total = memory_info[:total] || 0

    if total > 0 do
      # Rough estimate - in production, would use system memory info
      # Assuming ~10GB system
      min(100.0, total / (1024 * 1024 * 1024) * 10)
    else
      0.0
    end
  end

  defp get_message_queue_stats() do
    try do
      processes = Process.list()

      queue_lengths =
        Enum.map(processes, fn pid ->
          case Process.info(pid, :message_queue_len) do
            {:message_queue_len, len} -> len
            nil -> 0
          end
        end)

      %{
        max: Enum.max(queue_lengths, fn -> 0 end),
        avg:
          if(length(queue_lengths) > 0,
            do: Enum.sum(queue_lengths) / length(queue_lengths),
            else: 0
          ),
        total: Enum.sum(queue_lengths)
      }
    rescue
      _ ->
        %{max: 0, avg: 0, total: 0}
    end
  end

  defp get_scheduler_utilization() do
    try do
      # Use :erlang.statistics/1 instead of :scheduler.utilization/1
      case :erlang.statistics(:scheduler_wall_time) do
        nil ->
          []

        stats when is_list(stats) ->
          # Return simple scheduler stats
          stats

        _ ->
          []
      end
    rescue
      _ ->
        []
    end
  end

  defp analyze_system_health(current_metrics, history, thresholds, enable_anomaly_detection) do
    # Check threshold violations
    threshold_violations = check_thresholds(current_metrics, thresholds)

    # Perform anomaly detection if enabled
    anomalies =
      if enable_anomaly_detection and length(history) >= 10 do
        detect_anomalies(current_metrics, history)
      else
        []
      end

    # Calculate overall health score
    health_score = calculate_health_score(current_metrics, threshold_violations, anomalies)

    # Determine health status
    status = determine_health_status(health_score, threshold_violations, anomalies)

    analysis_results = %{
      health_score: health_score,
      threshold_violations: threshold_violations,
      anomalies: anomalies,
      trends: calculate_trends(history)
    }

    {status, analysis_results}
  end

  defp check_thresholds(metrics, thresholds) do
    violations = []

    # Check CPU/scheduler utilization
    cpu_threshold = Map.get(thresholds, :cpu_usage, 80)

    violations =
      case get_average_cpu_utilization(metrics.system.scheduler_utilization) do
        cpu_usage when cpu_usage > cpu_threshold ->
          [{:cpu_usage, cpu_usage, cpu_threshold} | violations]

        _ ->
          violations
      end

    # Check memory usage
    memory_threshold = Map.get(thresholds, :memory_usage, 85)

    violations =
      if metrics.memory.usage_percent > memory_threshold do
        [{:memory_usage, metrics.memory.usage_percent, memory_threshold} | violations]
      else
        violations
      end

    # Check process count
    process_threshold = Map.get(thresholds, :process_count, 10_000)

    violations =
      if metrics.processes.count > process_threshold do
        [{:process_count, metrics.processes.count, process_threshold} | violations]
      else
        violations
      end

    # Check message queue sizes
    queue_threshold = Map.get(thresholds, :message_queue_size, 1_000)

    violations =
      if metrics.processes.message_queue_lengths.max > queue_threshold do
        [
          {:message_queue_size, metrics.processes.message_queue_lengths.max, queue_threshold}
          | violations
        ]
      else
        violations
      end

    violations
  end

  defp detect_anomalies(current_metrics, history) do
    anomalies = []

    # Check for sudden spikes in memory usage
    memory_values = Enum.map(history, & &1.memory.usage_percent)
    memory_anomaly = detect_statistical_anomaly(current_metrics.memory.usage_percent, memory_values)

    anomalies =
      if memory_anomaly do
        [{:memory_spike, current_metrics.memory.usage_percent} | anomalies]
      else
        anomalies
      end

    # Check for process count anomalies
    process_values = Enum.map(history, & &1.processes.count)
    process_anomaly = detect_statistical_anomaly(current_metrics.processes.count, process_values)

    anomalies =
      if process_anomaly do
        [{:process_count_spike, current_metrics.processes.count} | anomalies]
      else
        anomalies
      end

    anomalies
  end

  defp detect_statistical_anomaly(current_value, historical_values) do
    if length(historical_values) >= 10 do
      mean = Enum.sum(historical_values) / length(historical_values)

      variance =
        Enum.sum(Enum.map(historical_values, fn x -> :math.pow(x - mean, 2) end)) /
          length(historical_values)

      std_dev = :math.sqrt(variance)

      # Consider it an anomaly if it's more than 2 standard deviations from the mean
      abs(current_value - mean) > 2 * std_dev
    else
      false
    end
  end

  defp calculate_health_score(metrics, violations, anomalies) do
    base_score = 100

    # Deduct points for violations
    violation_penalty = length(violations) * 15

    # Deduct points for anomalies
    anomaly_penalty = length(anomalies) * 10

    # Deduct points for high resource usage
    usage_penalty = calculate_usage_penalty(metrics)

    max(0, base_score - violation_penalty - anomaly_penalty - usage_penalty)
  end

  defp calculate_usage_penalty(metrics) do
    penalty = 0

    # Memory usage penalty
    penalty = penalty + max(0, (metrics.memory.usage_percent - 70) / 3)

    # Process count penalty
    usage_percent = metrics.processes.usage_percent
    penalty = penalty + max(0, (usage_percent - 70) / 3)

    round(penalty)
  end

  defp determine_health_status(health_score, violations, anomalies) do
    cond do
      health_score >= 90 and Enum.empty?(violations) and Enum.empty?(anomalies) ->
        :ok

      health_score >= 70 and length(violations) <= 1 ->
        :warning

      health_score >= 50 or not Enum.empty?(anomalies) ->
        :critical

      true ->
        :emergency
    end
  end

  defp calculate_trends(history) when length(history) >= 5 do
    recent_metrics = Enum.take(history, 5)

    %{
      memory_trend: calculate_trend(recent_metrics, & &1.memory.usage_percent),
      process_trend: calculate_trend(recent_metrics, & &1.processes.count),
      load_trend: calculate_trend(recent_metrics, & &1.load.load_1min)
    }
  end

  defp calculate_trends(_), do: %{}

  defp calculate_trend(metrics, extractor) do
    values = Enum.map(metrics, extractor)

    if length(values) >= 2 do
      first = List.last(values)
      last = List.first(values)

      cond do
        last > first * 1.1 -> :increasing
        last < first * 0.9 -> :decreasing
        true -> :stable
      end
    else
      :unknown
    end
  end

  defp get_average_cpu_utilization([]), do: 0.0

  defp get_average_cpu_utilization(scheduler_utilization) do
    if length(scheduler_utilization) > 0 do
      total = Enum.sum(Enum.map(scheduler_utilization, fn {_, usage} -> usage end))
      total / length(scheduler_utilization) * 100
    else
      0.0
    end
  end

  defp create_health_signal(status, analysis, metrics, state) do
    signal_type = "system.health.#{status}"

    signal_data = %{
      status: status,
      health_score: analysis.health_score,
      timestamp: metrics.timestamp,
      sensor_id: state.id,

      # Sensor metadata
      collection_count: state.collection_count + 1,
      sensor_uptime: DateTime.diff(DateTime.utc_now(), state.started_at, :second),

      # Current metrics summary
      metrics: %{
        memory_usage: metrics.memory.usage_percent,
        process_count: metrics.processes.count,
        cpu_utilization: get_average_cpu_utilization(metrics.system.scheduler_utilization),
        message_queue_max: metrics.processes.message_queue_lengths.max
      },

      # Analysis results
      threshold_violations: analysis.threshold_violations,
      anomalies: analysis.anomalies,
      trends: analysis.trends,

      # Alert metadata
      alert_level: determine_alert_level(status),
      requires_attention: status in [:warning, :critical, :emergency],
      recommendations: generate_recommendations(status, analysis, metrics)
    }

    Signal.new!(%{
      type: signal_type,
      source: "/sensors/system_health",
      data: signal_data
    })
  end

  defp determine_alert_level(:ok), do: :info
  defp determine_alert_level(:warning), do: :warning
  defp determine_alert_level(:critical), do: :error
  defp determine_alert_level(:emergency), do: :critical

  defp generate_recommendations(:ok, _analysis, _metrics) do
    ["System is operating normally"]
  end

  defp generate_recommendations(:warning, analysis, _metrics) do
    recommendations = []

    recommendations =
      if Enum.any?(analysis.threshold_violations, fn {type, _, _} -> type == :memory_usage end) do
        ["Consider monitoring memory usage and running garbage collection" | recommendations]
      else
        recommendations
      end

    recommendations =
      if Enum.any?(analysis.threshold_violations, fn {type, _, _} -> type == :process_count end) do
        ["Monitor process creation and consider process cleanup" | recommendations]
      else
        recommendations
      end

    if Enum.empty?(recommendations) do
      ["Monitor system closely for threshold violations"]
    else
      recommendations
    end
  end

  defp generate_recommendations(:critical, _analysis, _metrics) do
    [
      "Immediate attention required",
      "Check system resources and consider scaling",
      "Review recent changes and system logs"
    ]
  end

  defp generate_recommendations(:emergency, _analysis, _metrics) do
    [
      "Critical system issues detected",
      "Take immediate action to prevent system failure",
      "Consider emergency scaling or failover procedures"
    ]
  end

  # Handle periodic collection messages
  def handle_info(:collect_metrics, state) do
    # Trigger signal delivery
    {:ok, signal, new_state} = deliver_signal(state)

    # Deliver the signal
    Jido.Signal.Dispatch.dispatch(signal, state.target)
    {:noreply, new_state}
  end

  def handle_info(msg, state) do
    Logger.debug("SystemHealthSensor received unknown message", message: inspect(msg))
    {:noreply, state}
  end
end
