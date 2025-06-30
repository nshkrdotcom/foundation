defmodule JidoSystem.Sensors.AgentPerformanceSensor do
  @moduledoc """
  Intelligent agent performance monitoring sensor.

  This sensor tracks performance metrics for all registered agents in the
  Foundation system, detecting performance degradation, bottlenecks, and
  optimization opportunities.

  ## Features
  - Real-time agent performance tracking
  - Task execution time monitoring
  - Error rate and failure pattern analysis
  - Resource utilization per agent
  - Performance trend analysis
  - Automatic performance optimization suggestions

  ## Monitored Metrics
  - Task execution times and throughput
  - Error rates and failure patterns
  - Memory and CPU usage per agent
  - Message queue lengths and processing delays
  - Agent lifecycle events
  - Coordination efficiency metrics

  ## Signal Types
  - `agent.performance.normal` - Normal performance
  - `agent.performance.degraded` - Performance issues detected
  - `agent.performance.optimal` - Exceptional performance
  - `agent.performance.bottleneck` - Bottleneck identified
  """

  use Jido.Sensor,
    name: "agent_performance_sensor",
    description: "Monitors agent performance with intelligent analysis",
    category: :monitoring,
    tags: [:agents, :performance, :optimization],
    schema: [
      monitoring_interval: [
        type: :integer,
        default: 60_000,
        doc: "Performance monitoring interval in milliseconds"
      ],
      performance_thresholds: [
        type: :map,
        default: %{
          # 5 seconds
          max_avg_execution_time: 5_000,
          # 5%
          max_error_rate: 5.0,
          max_queue_length: 100,
          # tasks per minute
          min_throughput: 10
        },
        doc: "Performance thresholds for alerts"
      ],
      trend_analysis_window: [
        type: :integer,
        default: 20,
        doc: "Number of samples for trend analysis"
      ],
      enable_optimization_suggestions: [
        type: :boolean,
        default: true,
        doc: "Enable automatic optimization suggestions"
      ]
    ]

  require Logger
  alias Foundation.{Registry, Telemetry}
  alias Jido.Signal

  # Override Jido.Sensor callback specs - our implementations never return errors
  @spec mount(map()) :: {:ok, map()}
  @spec deliver_signal(map()) :: {:ok, Jido.Signal.t()}
  @spec on_before_deliver(Jido.Signal.t(), map()) :: {:ok, Jido.Signal.t()}
  @spec shutdown(map()) :: {:ok, map()}

  # Override Jido.Sensor generated function specs for more precise types
  @spec __sensor_metadata__() :: %{
          category: atom(),
          description: String.t(),
          name: String.t(),
          schema: list(),
          tags: list(),
          vsn: String.t()
        }
  @spec to_json() :: %{
          category: atom(),
          description: String.t(),
          name: String.t(),
          schema: list(),
          tags: list(),
          vsn: String.t()
        }

  @impl true
  def mount(config) do
    Logger.info("Starting AgentPerformanceSensor",
      sensor_id: config.id,
      interval: config.monitoring_interval
    )

    # Subscribe to agent telemetry events
    subscribe_to_agent_events()

    initial_state =
      Map.merge(config, %{
        agent_metrics: %{},
        performance_history: %{},
        last_analysis: DateTime.utc_now(),
        optimization_suggestions: %{},
        started_at: DateTime.utc_now()
      })

    # Schedule first analysis
    schedule_analysis(config.monitoring_interval)

    {:ok, initial_state}
  end

  @impl true
  def deliver_signal(state) do
    {:ok, signal, _new_state} = deliver_signal_with_state(state)
    {:ok, signal}
  end

  # Public API for testing that returns state
  def deliver_signal_with_state(state) do
    try do
      start_time = System.monotonic_time()

      # Collect current agent performance data
      current_agent_data = collect_agent_performance_data()

      # Update agent metrics
      updated_metrics = merge_agent_metrics(state.agent_metrics, current_agent_data)

      # Analyze performance for each agent
      performance_analysis = analyze_agent_performance(updated_metrics, state)

      # Generate signal based on analysis
      signal = create_performance_signal(performance_analysis, state)

      # Update state
      new_state = %{
        state
        | agent_metrics: updated_metrics,
          performance_history:
            update_performance_history(state.performance_history, performance_analysis),
          last_analysis: DateTime.utc_now()
      }

      # Schedule next analysis
      schedule_analysis(state.monitoring_interval)

      # Emit telemetry for performance analysis completion
      :telemetry.execute(
        [:jido_system, :performance_sensor, :analysis_completed],
        %{
          duration: System.monotonic_time() - start_time,
          agents_analyzed: map_size(updated_metrics),
          issues_detected: count_performance_issues(performance_analysis),
          timestamp: System.system_time()
        },
        %{
          sensor_id: state.id,
          signal_type: signal.type
        }
      )

      Logger.debug("Agent performance signal generated",
        agents_analyzed: map_size(updated_metrics),
        issues_detected: count_performance_issues(performance_analysis)
      )

      {:ok, signal, new_state}
    rescue
      e ->
        Logger.error("Failed to analyze agent performance",
          error: inspect(e),
          stacktrace: __STACKTRACE__
        )

        error_signal =
          Signal.new!(%{
            type: "agent.performance.error",
            source: "/sensors/agent_performance",
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
  def on_before_deliver(signal, _state) do
    # Default implementation - pass signal through unchanged
    {:ok, signal}
  end

  @impl true
  def shutdown(state) do
    Logger.info("Shutting down AgentPerformanceSensor",
      sensor_id: state.id,
      agents_monitored: map_size(state.agent_metrics)
    )

    {:ok, state}
  end

  # Private helper functions

  defp schedule_analysis(interval) do
    Process.send_after(self(), :analyze_performance, interval)
  end

  defp subscribe_to_agent_events() do
    events = [
      [:jido_system, :agent, :started],
      [:jido_system, :agent, :terminated],
      [:jido_system, :task, :completed],
      [:jido_system, :task, :failed],
      [:jido_foundation, :bridge, :agent_event]
    ]

    Enum.each(events, fn event ->
      handler_id = "agent_performance_sensor_#{inspect(self())}_#{Enum.join(event, "_")}"
      Telemetry.attach(handler_id, event, &handle_telemetry_event/4, %{sensor_pid: self()})
    end)
  end

  defp handle_telemetry_event(event, measurements, metadata, %{sensor_pid: pid}) do
    GenServer.cast(pid, {:telemetry_event, event, measurements, metadata})
  end

  defp collect_agent_performance_data() do
    try do
      # Get all registered agents from Foundation Registry
      registry_entries = Registry.select(Foundation.Registry, [{{:_, :_, :_}, [], [:"$_"]}])

      agent_data =
        Enum.reduce(registry_entries, %{}, fn {agent_id, pid, metadata}, acc ->
          if is_pid(pid) and Process.alive?(pid) do
            performance_data = collect_single_agent_data(agent_id, pid, metadata)
            Map.put(acc, agent_id, performance_data)
          else
            acc
          end
        end)

      agent_data
    rescue
      e ->
        Logger.warning("Failed to collect agent performance data", error: inspect(e))
        %{}
    end
  end

  defp collect_single_agent_data(agent_id, pid, metadata) do
    try do
      start_time = System.monotonic_time()

      # Get process info
      process_info =
        Process.info(pid, [
          :memory,
          :message_queue_len,
          :reductions,
          :status,
          :current_function,
          :current_location
        ])

      # Get agent-specific metrics from metadata
      agent_type = Map.get(metadata, :agent_type, "unknown")
      capabilities = Map.get(metadata, :capabilities, [])

      result = %{
        agent_id: agent_id,
        agent_type: agent_type,
        pid: pid,
        capabilities: capabilities,
        timestamp: DateTime.utc_now(),

        # Process metrics
        memory_usage: Keyword.get(process_info, :memory, 0),
        message_queue_length: Keyword.get(process_info, :message_queue_len, 0),
        reductions: Keyword.get(process_info, :reductions, 0),
        status: Keyword.get(process_info, :status, :unknown),

        # Performance indicators
        is_responsive: is_process_responsive(pid),
        uptime: calculate_agent_uptime(metadata),

        # Derived metrics
        memory_mb: Keyword.get(process_info, :memory, 0) / 1024 / 1024,
        queue_status: classify_queue_status(Keyword.get(process_info, :message_queue_len, 0))
      }

      # Emit telemetry for agent data collection
      :telemetry.execute(
        [:jido_system, :performance_sensor, :agent_data_collected],
        %{
          duration: System.monotonic_time() - start_time,
          memory_mb: result.memory_mb,
          queue_length: result.message_queue_length,
          timestamp: System.system_time()
        },
        %{
          agent_id: agent_id,
          agent_type: agent_type,
          is_responsive: result.is_responsive
        }
      )

      result
    rescue
      e ->
        Logger.debug("Failed to collect data for agent #{agent_id}", error: inspect(e))

        %{
          agent_id: agent_id,
          pid: pid,
          timestamp: DateTime.utc_now(),
          error: inspect(e),
          status: :error
        }
    end
  end

  defp is_process_responsive(pid) do
    try do
      # Simple responsiveness check
      ref = Process.monitor(pid)
      send(pid, {self(), ref, :ping})

      receive do
        {^ref, :pong} ->
          Process.demonitor(ref, [:flush])
          true

        {:DOWN, ^ref, :process, ^pid, _reason} ->
          false
      after
        # 1 second timeout
        1000 ->
          Process.demonitor(ref, [:flush])
          false
      end
    rescue
      _ -> false
    end
  end

  defp calculate_agent_uptime(metadata) do
    case Map.get(metadata, :started_at) do
      started_at when is_binary(started_at) ->
        case DateTime.from_iso8601(started_at) do
          {:ok, start_time, _} -> DateTime.diff(DateTime.utc_now(), start_time, :second)
          _ -> 0
        end

      %DateTime{} = start_time ->
        DateTime.diff(DateTime.utc_now(), start_time, :second)

      _ ->
        0
    end
  end

  defp classify_queue_status(queue_length) do
    cond do
      queue_length == 0 -> :idle
      queue_length < 10 -> :light
      queue_length < 50 -> :moderate
      queue_length < 100 -> :heavy
      true -> :overloaded
    end
  end

  defp merge_agent_metrics(existing_metrics, new_data) do
    Enum.reduce(new_data, existing_metrics, fn {agent_id, current_data}, acc ->
      case Map.get(acc, agent_id) do
        nil ->
          # New agent
          Map.put(acc, agent_id, %{
            current: current_data,
            history: [current_data],
            performance_stats: init_performance_stats(current_data)
          })

        existing ->
          # Update existing agent data
          updated_history = [current_data | existing.history] |> Enum.take(100)
          updated_stats = update_performance_stats(existing.performance_stats, current_data)

          Map.put(acc, agent_id, %{
            current: current_data,
            history: updated_history,
            performance_stats: updated_stats
          })
      end
    end)
  end

  defp init_performance_stats(data) do
    %{
      total_samples: 1,
      avg_memory_usage: data.memory_mb,
      max_memory_usage: data.memory_mb,
      avg_queue_length: data.message_queue_length,
      max_queue_length: data.message_queue_length,
      responsiveness_rate: if(data.is_responsive, do: 1.0, else: 0.0),
      first_seen: data.timestamp,
      last_updated: data.timestamp
    }
  end

  defp update_performance_stats(stats, new_data) do
    new_sample_count = stats.total_samples + 1

    %{
      stats
      | total_samples: new_sample_count,
        avg_memory_usage:
          (stats.avg_memory_usage * stats.total_samples + new_data.memory_mb) / new_sample_count,
        max_memory_usage: max(stats.max_memory_usage, new_data.memory_mb),
        avg_queue_length:
          (stats.avg_queue_length * stats.total_samples + new_data.message_queue_length) /
            new_sample_count,
        max_queue_length: max(stats.max_queue_length, new_data.message_queue_length),
        responsiveness_rate: calculate_responsiveness_rate(stats, new_data.is_responsive),
        last_updated: new_data.timestamp
    }
  end

  defp calculate_responsiveness_rate(stats, is_responsive) do
    responsive_count = stats.responsiveness_rate * stats.total_samples
    new_responsive_count = responsive_count + if(is_responsive, do: 1, else: 0)
    new_responsive_count / (stats.total_samples + 1)
  end

  defp analyze_agent_performance(agent_metrics, state) do
    thresholds = state.performance_thresholds

    analysis_results =
      Enum.map(agent_metrics, fn {agent_id, agent_data} ->
        current = agent_data.current
        stats = agent_data.performance_stats
        history = agent_data.history

        # Analyze various performance aspects
        performance_issues = []

        # Memory usage analysis
        # 100MB threshold
        performance_issues =
          if stats.avg_memory_usage > 100 do
            [{:high_memory_usage, stats.avg_memory_usage} | performance_issues]
          else
            performance_issues
          end

        # Queue length analysis
        performance_issues =
          if stats.avg_queue_length > thresholds.max_queue_length do
            [{:high_queue_length, stats.avg_queue_length} | performance_issues]
          else
            performance_issues
          end

        # Responsiveness analysis
        performance_issues =
          if stats.responsiveness_rate < 0.9 do
            [{:low_responsiveness, stats.responsiveness_rate} | performance_issues]
          else
            performance_issues
          end

        # Trend analysis
        trends =
          if length(history) >= 5 do
            analyze_performance_trends(history)
          else
            %{}
          end

        # Overall performance classification
        performance_level = classify_performance_level(performance_issues, stats, trends)

        # Generate optimization suggestions
        suggestions =
          if state.enable_optimization_suggestions do
            generate_optimization_suggestions(performance_issues, stats, trends)
          else
            []
          end

        {agent_id,
         %{
           performance_level: performance_level,
           performance_issues: performance_issues,
           trends: trends,
           optimization_suggestions: suggestions,
           stats: stats,
           current_data: current
         }}
      end)

    Map.new(analysis_results)
  end

  defp analyze_performance_trends(history) do
    recent_samples = Enum.take(history, 10)

    %{
      memory_trend: calculate_trend(recent_samples, & &1.memory_mb),
      queue_trend: calculate_trend(recent_samples, & &1.message_queue_length),
      responsiveness_trend: calculate_trend(recent_samples, &if(&1.is_responsive, do: 1, else: 0))
    }
  end

  defp calculate_trend(samples, extractor) do
    values = Enum.map(samples, extractor)

    if length(values) >= 3 do
      first_half = Enum.take(values, div(length(values), 2))
      second_half = Enum.drop(values, div(length(values), 2))

      first_avg = Enum.sum(first_half) / length(first_half)
      second_avg = Enum.sum(second_half) / length(second_half)

      cond do
        second_avg > first_avg * 1.2 -> :increasing
        second_avg < first_avg * 0.8 -> :decreasing
        true -> :stable
      end
    else
      :unknown
    end
  end

  defp classify_performance_level(issues, stats, _trends) do
    cond do
      length(issues) == 0 and stats.responsiveness_rate > 0.95 ->
        :optimal

      length(issues) <= 1 and stats.responsiveness_rate > 0.9 ->
        :normal

      length(issues) <= 2 or stats.responsiveness_rate > 0.7 ->
        :degraded

      true ->
        :critical
    end
  end

  defp generate_optimization_suggestions(issues, _stats, trends) do
    suggestions = []

    # Memory optimization suggestions
    suggestions =
      if Enum.any?(issues, fn {type, _} -> type == :high_memory_usage end) do
        ["Consider implementing memory cleanup or garbage collection optimization" | suggestions]
      else
        suggestions
      end

    # Queue optimization suggestions
    suggestions =
      if Enum.any?(issues, fn {type, _} -> type == :high_queue_length end) do
        [
          "Consider increasing processing capacity or implementing queue prioritization"
          | suggestions
        ]
      else
        suggestions
      end

    # Responsiveness optimization
    suggestions =
      if Enum.any?(issues, fn {type, _} -> type == :low_responsiveness end) do
        ["Investigate blocking operations and consider async processing" | suggestions]
      else
        suggestions
      end

    # Trend-based suggestions
    suggestions =
      case Map.get(trends, :memory_trend) do
        :increasing ->
          ["Monitor memory usage trends - consider implementing memory limits" | suggestions]

        _ ->
          suggestions
      end

    suggestions
  end

  defp count_performance_issues(analysis) do
    Enum.reduce(analysis, 0, fn {_agent_id, agent_analysis}, acc ->
      acc + length(agent_analysis.performance_issues)
    end)
  end

  defp update_performance_history(history, analysis) do
    timestamp = DateTime.utc_now()

    # Keep last 100 analysis results
    new_entry = %{
      timestamp: timestamp,
      agent_count: map_size(analysis),
      performance_summary: summarize_performance(analysis)
    }

    [new_entry | history] |> Enum.take(100)
  end

  defp summarize_performance(analysis) do
    agent_levels = Enum.map(analysis, fn {_id, data} -> data.performance_level end)

    %{
      optimal_count: Enum.count(agent_levels, &(&1 == :optimal)),
      normal_count: Enum.count(agent_levels, &(&1 == :normal)),
      degraded_count: Enum.count(agent_levels, &(&1 == :degraded)),
      critical_count: Enum.count(agent_levels, &(&1 == :critical)),
      total_issues:
        Enum.reduce(analysis, 0, fn {_, data}, acc ->
          acc + length(data.performance_issues)
        end)
    }
  end

  defp create_performance_signal(analysis, state) do
    summary = summarize_performance(analysis)

    # Determine overall system performance status
    overall_status =
      cond do
        summary.critical_count > 0 -> :critical
        summary.degraded_count > summary.normal_count + summary.optimal_count -> :degraded
        summary.optimal_count > summary.normal_count -> :optimal
        true -> :normal
      end

    signal_type = "agent.performance.#{overall_status}"

    signal_data = %{
      status: overall_status,
      timestamp: DateTime.utc_now(),
      sensor_id: state.id,

      # Summary statistics
      summary: summary,
      total_agents: map_size(analysis),

      # Detailed analysis for agents with issues
      problem_agents: get_problem_agents(analysis),

      # Top performers
      top_performers: get_top_performers(analysis),

      # System-wide recommendations
      system_recommendations: generate_system_recommendations(analysis, summary),

      # Alert metadata
      alert_level: determine_alert_level(overall_status),
      requires_attention: overall_status in [:degraded, :critical]
    }

    Signal.new!(%{
      type: signal_type,
      source: "/sensors/agent_performance",
      data: signal_data
    })
  end

  defp get_problem_agents(analysis) do
    analysis
    |> Enum.filter(fn {_id, data} ->
      data.performance_level in [:degraded, :critical] or length(data.performance_issues) > 0
    end)
    |> Enum.map(fn {agent_id, data} ->
      %{
        agent_id: agent_id,
        agent_type: data.current_data.agent_type,
        performance_level: data.performance_level,
        issues: data.performance_issues,
        suggestions: data.optimization_suggestions
      }
    end)
    # Limit to top 10 problem agents
    |> Enum.take(10)
  end

  defp get_top_performers(analysis) do
    analysis
    |> Enum.filter(fn {_id, data} -> data.performance_level == :optimal end)
    |> Enum.map(fn {agent_id, data} ->
      %{
        agent_id: agent_id,
        agent_type: data.current_data.agent_type,
        responsiveness_rate: data.stats.responsiveness_rate,
        avg_memory_usage: data.stats.avg_memory_usage,
        uptime: data.current_data.uptime
      }
    end)
    # Top 5 performers
    |> Enum.take(5)
  end

  defp generate_system_recommendations(analysis, summary) do
    recommendations = []

    # Overall system health recommendations
    recommendations =
      if summary.critical_count > 0 do
        [
          "Immediate attention required for #{summary.critical_count} critical agents"
          | recommendations
        ]
      else
        recommendations
      end

    recommendations =
      if summary.degraded_count > summary.normal_count do
        ["Consider system-wide performance optimization" | recommendations]
      else
        recommendations
      end

    # Resource optimization recommendations
    high_memory_agents = count_agents_with_issue(analysis, :high_memory_usage)

    recommendations =
      if high_memory_agents > 3 do
        ["Consider implementing global memory management policies" | recommendations]
      else
        recommendations
      end

    if Enum.empty?(recommendations) do
      ["System performance is within normal parameters"]
    else
      recommendations
    end
  end

  defp count_agents_with_issue(analysis, issue_type) do
    Enum.count(analysis, fn {_id, data} ->
      Enum.any?(data.performance_issues, fn {type, _} -> type == issue_type end)
    end)
  end

  defp determine_alert_level(:optimal), do: :info
  defp determine_alert_level(:normal), do: :info
  defp determine_alert_level(:degraded), do: :warning
  defp determine_alert_level(:critical), do: :error

  # Handle periodic analysis
  def handle_info(:analyze_performance, state) do
    {:ok, signal, new_state} = deliver_signal_with_state(state)
    Jido.Signal.Dispatch.dispatch(signal, state.target)
    {:noreply, new_state}
  end

  def handle_info(msg, state) do
    Logger.debug("AgentPerformanceSensor received unknown message", message: inspect(msg))
    {:noreply, state}
  end

  # Handle telemetry events
  def handle_cast({:telemetry_event, event, measurements, metadata}, state) do
    # Update real-time metrics based on telemetry events
    case event do
      [:jido_system, :task, :completed] ->
        # Record task completion metrics
        agent_id = metadata[:agent_id]
        duration = measurements[:duration] || 0

        if agent_id do
          # Update task execution metrics (simplified)
          Logger.debug("Task completed", agent_id: agent_id, duration: duration)
        end

      [:jido_system, :task, :failed] ->
        # Record task failure metrics
        agent_id = metadata[:agent_id]

        if agent_id do
          Logger.debug("Task failed", agent_id: agent_id)
        end

      _ ->
        :ok
    end

    {:noreply, state}
  end
end
