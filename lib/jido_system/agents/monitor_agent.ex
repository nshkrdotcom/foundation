defmodule JidoSystem.Agents.MonitorAgent do
  @moduledoc """
  System monitoring agent with intelligent alerting and Foundation integration.

  MonitorAgent continuously tracks system health, performance metrics, and agent
  status across the Foundation infrastructure. It provides intelligent alerting,
  trend analysis, and proactive issue detection.

  ## Features
  - Real-time system resource monitoring (CPU, memory, disk)
  - Agent health and performance tracking
  - Intelligent threshold-based alerting
  - Trend analysis and anomaly detection
  - Integration with Foundation.Telemetry
  - Automatic escalation workflows
  - Historical metrics storage and analysis

  ## Monitoring Capabilities
  - System resource utilization
  - Agent registration/deregistration events
  - Task processing performance
  - Error rates and patterns
  - Foundation service health
  - MABEAM coordination metrics
  - Network connectivity and latency

  ## State Management
  The agent maintains:
  - `:monitoring_status` - Current monitoring state (:active, :paused, :error)
  - `:metrics_history` - Rolling window of collected metrics
  - `:alert_thresholds` - Configurable alert trigger values
  - `:active_alerts` - Currently active alert conditions
  - `:system_health` - Overall system health assessment
  - `:monitored_agents` - List of agents being monitored

  ## Usage

      # Start the monitor agent
      {:ok, pid} = JidoSystem.Agents.MonitorAgent.start_link(id: "system_monitor")

      # Get system health report
      {:ok, health} = JidoSystem.Agents.MonitorAgent.cmd(pid, :get_system_health)

      # Configure alert thresholds
      thresholds = %{
        cpu_usage: 80,
        memory_usage: 85,
        error_rate: 5.0,
        response_time: 1000
      }
      JidoSystem.Agents.MonitorAgent.cmd(pid, :set_alert_thresholds, thresholds)

      # Get active alerts
      {:ok, alerts} = JidoSystem.Agents.MonitorAgent.cmd(pid, :get_active_alerts)
  """

  use JidoSystem.Agents.FoundationAgent,
    name: "monitor_agent",
    description: "System monitoring with intelligent alerting and Foundation integration",
    actions: [
      JidoSystem.Actions.CollectMetrics,
      JidoSystem.Actions.AnalyzeHealth,
      JidoSystem.Actions.GenerateAlert,
      JidoSystem.Actions.GetSystemHealth,
      JidoSystem.Actions.SetAlertThresholds,
      JidoSystem.Actions.GetActiveAlerts,
      JidoSystem.Actions.AcknowledgeAlert,
      JidoSystem.Actions.StartMonitoring,
      JidoSystem.Actions.StopMonitoring
    ],
    schema: [
      monitoring_status: [type: :atom, default: :active],
      metrics_history: [type: :list, default: []],
      alert_thresholds: [
        type: :map,
        default: %{
          cpu_usage: 80,
          memory_usage: 85,
          disk_usage: 90,
          error_rate: 5.0,
          response_time: 1000,
          agent_failures: 3
        }
      ],
      active_alerts: [type: :map, default: %{}],
      system_health: [
        type: :map,
        default: %{
          overall_status: :unknown,
          score: 0,
          last_assessment: nil
        }
      ],
      monitored_agents: [type: :list, default: []],
      # 30 seconds
      collection_interval: [type: :integer, default: 30_000],
      # 24 hours worth of data points
      history_retention: [type: :integer, default: 1440]
    ]

  require Logger
  alias Foundation.{Registry, Telemetry}
  alias JidoSystem.Actions.{CollectMetrics, AnalyzeHealth}

  @impl true
  def mount(server_state, opts) do
    case super(server_state, opts) do
      {:ok, initialized_server_state} ->
        agent = initialized_server_state.agent
        Logger.info("MonitorAgent #{agent.id} mounted and starting monitoring")

        # Register with supervised scheduler instead of self-scheduling
        register_with_scheduler()

        # Subscribe to Foundation telemetry events
        subscribe_to_telemetry_events()

        {:ok, initialized_server_state}
    end
  end

  @impl true
  def on_before_run(agent) do
    case super(agent) do
      {:ok, updated_agent} ->
        # Ensure monitoring is active
        if agent.state.monitoring_status != :active do
          emit_event(agent, :monitoring_inactive, %{}, %{
            reason: "Monitoring is not active"
          })

          {:error, {:monitoring_inactive, "Monitoring is currently inactive"}}
        else
          {:ok, updated_agent}
        end
    end
  end

  # Action Handlers

  def handle_collect_metrics(agent, _params) do
    try do
      start_time = System.monotonic_time(:microsecond)

      # Collect system metrics
      system_metrics = collect_system_metrics()

      # Collect agent metrics
      agent_metrics = collect_agent_metrics(agent.state.monitored_agents)

      # Collect Foundation service metrics
      foundation_metrics = collect_foundation_metrics()

      metrics = %{
        timestamp: DateTime.utc_now(),
        system: system_metrics,
        agents: agent_metrics,
        foundation: foundation_metrics,
        collection_time: System.monotonic_time(:microsecond) - start_time
      }

      # Update metrics history with retention limit
      new_history =
        [metrics | agent.state.metrics_history]
        |> Enum.take(agent.state.history_retention)

      new_state = %{agent.state | metrics_history: new_history}

      emit_event(
        agent,
        :metrics_collected,
        %{
          metrics_count:
            map_size(system_metrics) + map_size(agent_metrics) + map_size(foundation_metrics),
          collection_time: metrics.collection_time
        },
        %{}
      )

      {:ok, metrics, %{agent | state: new_state}}
    rescue
      e ->
        emit_event(agent, :metrics_collection_error, %{}, %{error: inspect(e)})
        {:error, {:collection_error, e}}
    end
  end

  def handle_analyze_health(agent, _params) do
    if Enum.empty?(agent.state.metrics_history) do
      {:error, :no_metrics_available}
    else
      latest_metrics = hd(agent.state.metrics_history)

      # Analyze system health
      health_score = calculate_health_score(latest_metrics, agent.state.alert_thresholds)

      status =
        cond do
          health_score >= 90 -> :excellent
          health_score >= 75 -> :good
          health_score >= 50 -> :fair
          health_score >= 25 -> :poor
          true -> :critical
        end

      health_report = %{
        overall_status: status,
        score: health_score,
        last_assessment: DateTime.utc_now(),
        metrics_analyzed: latest_metrics,
        recommendations: generate_recommendations(latest_metrics, agent.state.alert_thresholds)
      }

      new_state = %{agent.state | system_health: health_report}

      emit_event(
        agent,
        :health_analyzed,
        %{
          health_score: health_score,
          status: status
        },
        %{}
      )

      {:ok, health_report, %{agent | state: new_state}}
    end
  end

  def handle_check_thresholds(agent, _params) do
    if Enum.empty?(agent.state.metrics_history) do
      {:error, :no_metrics_available}
    else
      latest_metrics = hd(agent.state.metrics_history)

      # Check each threshold
      violated_thresholds = check_all_thresholds(latest_metrics, agent.state.alert_thresholds)

      # Generate or update alerts
      {new_alerts, alert_actions} =
        process_threshold_violations(
          violated_thresholds,
          agent.state.active_alerts,
          latest_metrics
        )

      new_state = %{agent.state | active_alerts: new_alerts}

      # Emit events for new alerts
      Enum.each(alert_actions, fn {action, alert} ->
        emit_event(
          agent,
          :alert_triggered,
          %{
            alert_type: alert.type,
            severity: alert.severity,
            action: action
          },
          %{alert_id: alert.id}
        )
      end)

      result = %{
        violations_detected: length(violated_thresholds),
        active_alerts: map_size(new_alerts),
        alert_actions: alert_actions
      }

      {:ok, result, %{agent | state: new_state}}
    end
  end

  def handle_get_system_health(agent, _params) do
    health_report =
      Map.merge(agent.state.system_health, %{
        metrics_available: length(agent.state.metrics_history),
        monitoring_status: agent.state.monitoring_status,
        active_alerts_count: map_size(agent.state.active_alerts)
      })

    {:ok, health_report, agent}
  end

  def handle_set_alert_thresholds(agent, thresholds) when is_map(thresholds) do
    # Validate thresholds
    case validate_thresholds(thresholds) do
      :ok ->
        new_thresholds = Map.merge(agent.state.alert_thresholds, thresholds)
        new_state = %{agent.state | alert_thresholds: new_thresholds}

        emit_event(
          agent,
          :thresholds_updated,
          %{
            thresholds_count: map_size(thresholds)
          },
          %{}
        )

        {:ok, :updated, %{agent | state: new_state}}

      {:error, reason} ->
        {:error, {:invalid_thresholds, reason}}
    end
  end

  def handle_get_active_alerts(agent, _params) do
    alerts_summary =
      agent.state.active_alerts
      |> Enum.map(fn {_id, alert} ->
        Map.take(alert, [:id, :type, :severity, :created_at, :message])
      end)

    {:ok, alerts_summary, agent}
  end

  def handle_acknowledge_alert(agent, %{alert_id: alert_id}) do
    case Map.get(agent.state.active_alerts, alert_id) do
      nil ->
        {:error, :alert_not_found}

      alert ->
        updated_alert = %{alert | acknowledged: true, acknowledged_at: DateTime.utc_now()}
        new_alerts = Map.put(agent.state.active_alerts, alert_id, updated_alert)
        new_state = %{agent.state | active_alerts: new_alerts}

        emit_event(agent, :alert_acknowledged, %{}, %{alert_id: alert_id})

        {:ok, :acknowledged, %{agent | state: new_state}}
    end
  end

  def handle_start_monitoring(agent, _params) do
    new_state = %{agent.state | monitoring_status: :active}
    register_with_scheduler()

    emit_event(agent, :monitoring_started, %{}, %{})

    {:ok, :started, %{agent | state: new_state}}
  end

  def handle_stop_monitoring(agent, _params) do
    new_state = %{agent.state | monitoring_status: :paused}

    # Unregister from scheduler when stopping
    unregister_from_scheduler()

    emit_event(agent, :monitoring_stopped, %{}, %{})

    {:ok, :stopped, %{agent | state: new_state}}
  end

  # Private helper functions

  defp register_with_scheduler do
    # Register periodic operations with the supervised scheduler
    JidoFoundation.SchedulerManager.register_periodic(
      self(),
      :metrics_collection,
      # 30 seconds
      30_000,
      :collect_metrics
    )

    JidoFoundation.SchedulerManager.register_periodic(
      self(),
      :health_analysis,
      # 1 minute
      60_000,
      :analyze_health
    )
  end

  defp unregister_from_scheduler do
    # Unregister all periodic operations when stopping
    JidoFoundation.SchedulerManager.unregister_agent(self())
  end

  defp subscribe_to_telemetry_events do
    events = [
      [:jido_system, :agent, :started],
      [:jido_system, :agent, :terminated],
      [:jido_system, :agent, :error],
      [:foundation, :registry, :registered],
      [:foundation, :registry, :deregistered]
    ]

    Enum.each(events, fn event ->
      Telemetry.attach(
        "monitor_agent_#{inspect(self())}_#{Enum.join(event, "_")}",
        event,
        &handle_telemetry_event/4,
        %{monitor_pid: self()}
      )
    end)
  end

  defp handle_telemetry_event(event, measurements, metadata, %{monitor_pid: pid}) do
    GenServer.cast(pid, {:telemetry_event, event, measurements, metadata})
  end

  defp collect_system_metrics do
    %{
      memory: :erlang.memory(),
      system_info: %{
        process_count: :erlang.system_info(:process_count),
        port_count: :erlang.system_info(:port_count),
        ets_count: :erlang.system_info(:ets_count)
      },
      scheduler_utilization: get_scheduler_utilization(),
      load_average: get_load_average()
    }
  end

  defp collect_agent_metrics(monitored_agents) do
    agent_stats =
      Enum.map(monitored_agents, fn agent_id ->
        case Registry.lookup(Foundation.Registry, agent_id) do
          [{pid, metadata}] when is_pid(pid) ->
            process_info = Process.info(pid, [:memory, :message_queue_len, :status])

            {agent_id,
             %{
               pid: pid,
               status: :alive,
               metadata: metadata,
               process_info: process_info
             }}

          [] ->
            {agent_id, %{status: :not_found}}

          _ ->
            {agent_id, %{status: :error}}
        end
      end)

    %{
      total_agents: length(monitored_agents),
      alive_agents: Enum.count(agent_stats, fn {_, stats} -> stats.status == :alive end),
      agent_details: Map.new(agent_stats)
    }
  end

  defp collect_foundation_metrics do
    %{
      registry_count: Registry.count(Foundation.Registry),
      telemetry_handlers: length(:telemetry.list_handlers([])),
      supervisor_children: count_supervisor_children()
    }
  end

  defp get_load_average do
    # Use supervised system command execution instead of direct System.cmd
    case JidoFoundation.SystemCommandManager.get_load_average() do
      {:ok, load_avg} when is_float(load_avg) ->
        load_avg

      {:error, _reason} ->
        0.0
    end
  rescue
    _ -> 0.0
  end

  defp get_scheduler_utilization do
    try do
      schedulers = :erlang.system_info(:logical_processors)

      if schedulers > 0 do
        # Use system stats to estimate utilization
        stats = :erlang.statistics(:scheduler_wall_time)

        if is_list(stats) and length(stats) > 0 do
          # Calculate average utilization across schedulers
          Enum.map(stats, fn {_, active, total} ->
            if total > 0, do: active / total, else: 0.0
          end)
          |> Enum.sum()
          |> Kernel./(length(stats))
        else
          0.0
        end
      else
        0.0
      end
    rescue
      _ -> 0.0
    end
  end

  defp count_supervisor_children do
    try do
      case Process.whereis(Foundation.Supervisor) do
        pid when is_pid(pid) ->
          pid
          |> Supervisor.which_children()
          |> length()

        _ ->
          0
      end
    rescue
      _ -> 0
    end
  end

  defp calculate_health_score(metrics, thresholds) do
    scores = [
      score_memory_usage(metrics.system.memory, thresholds.memory_usage),
      score_cpu_usage(metrics.scheduler_utilization, thresholds.cpu_usage),
      score_agent_health(metrics.agents),
      score_foundation_health(metrics.foundation)
    ]

    scores
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> 0
      valid_scores -> Enum.sum(valid_scores) / length(valid_scores)
    end
    |> round()
  end

  defp score_memory_usage(memory_info, threshold) when is_map(memory_info) do
    total = memory_info[:total] || 0

    if total > 0 do
      # Convert to GB percentage
      usage_percent = total / (1024 * 1024 * 1024) * 100
      max(0, 100 - max(0, usage_percent - threshold))
    else
      100
    end
  end

  defp score_cpu_usage(utilization, threshold) when is_list(utilization) do
    avg_utilization =
      utilization
      |> Enum.map(fn {_, usage} -> usage end)
      |> Enum.sum()
      |> Kernel./(length(utilization))
      |> Kernel.*(100)

    max(0, 100 - max(0, avg_utilization - threshold))
  end

  defp score_cpu_usage(_, _), do: 100

  defp score_agent_health(%{total_agents: total, alive_agents: alive}) when total > 0 do
    alive / total * 100
  end

  defp score_agent_health(_), do: 100

  defp score_foundation_health(%{registry_count: count}) when count >= 0 do
    # Basic scoring
    min(100, count * 10)
  end

  defp score_foundation_health(_), do: 100

  defp check_all_thresholds(metrics, thresholds) do
    [
      check_memory_threshold(metrics.system.memory, thresholds.memory_usage, :memory_usage),
      check_cpu_threshold(metrics.scheduler_utilization, thresholds.cpu_usage, :cpu_usage),
      check_agent_threshold(metrics.agents, thresholds.agent_failures, :agent_failures)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp check_memory_threshold(memory_info, threshold, type) when is_map(memory_info) do
    total = memory_info[:total] || 0

    if total > 0 do
      usage_percent = total / (1024 * 1024 * 1024) * 100

      if usage_percent > threshold do
        %{type: type, current: usage_percent, threshold: threshold, severity: :warning}
      end
    end
  end

  defp check_cpu_threshold(utilization, threshold, type) when is_list(utilization) do
    avg_utilization =
      utilization
      |> Enum.map(fn {_, usage} -> usage end)
      |> Enum.sum()
      |> Kernel./(length(utilization))
      |> Kernel.*(100)

    if avg_utilization > threshold do
      %{type: type, current: avg_utilization, threshold: threshold, severity: :warning}
    end
  end

  defp check_cpu_threshold(_, _, _), do: nil

  defp check_agent_threshold(%{total_agents: total, alive_agents: alive}, threshold, type) do
    failed_agents = total - alive

    if failed_agents >= threshold do
      %{type: type, current: failed_agents, threshold: threshold, severity: :critical}
    end
  end

  defp check_agent_threshold(_, _, _), do: nil

  defp process_threshold_violations(violations, current_alerts, metrics) do
    timestamp = DateTime.utc_now()

    {new_alerts, actions} =
      Enum.reduce(violations, {current_alerts, []}, fn violation, {alerts, actions} ->
        alert_id = "#{violation.type}_#{System.unique_integer()}"

        alert = %{
          id: alert_id,
          type: violation.type,
          severity: violation.severity,
          message:
            "#{violation.type} exceeded threshold: #{violation.current} > #{violation.threshold}",
          current_value: violation.current,
          threshold: violation.threshold,
          created_at: timestamp,
          acknowledged: false,
          metrics_snapshot: metrics
        }

        {Map.put(alerts, alert_id, alert), [{:created, alert} | actions]}
      end)

    {new_alerts, Enum.reverse(actions)}
  end

  defp generate_recommendations(metrics, thresholds) do
    recommendations = []

    # Add memory recommendations
    recommendations =
      if check_memory_threshold(metrics.system.memory, thresholds.memory_usage, :memory_usage) do
        ["Consider reducing memory usage or increasing available memory" | recommendations]
      else
        recommendations
      end

    # Add CPU recommendations
    recommendations =
      if check_cpu_threshold(metrics.scheduler_utilization, thresholds.cpu_usage, :cpu_usage) do
        [
          "Consider optimizing CPU-intensive processes or adding more processing capacity"
          | recommendations
        ]
      else
        recommendations
      end

    # Add agent recommendations
    recommendations =
      if check_agent_threshold(metrics.agents, thresholds.agent_failures, :agent_failures) do
        ["Investigate failed agents and restart if necessary" | recommendations]
      else
        recommendations
      end

    recommendations
  end

  defp validate_thresholds(thresholds) when is_map(thresholds) do
    required_numeric = [:cpu_usage, :memory_usage, :disk_usage, :response_time]

    Enum.reduce_while(thresholds, :ok, fn {key, value}, _acc ->
      cond do
        key in required_numeric and (not is_number(value) or value < 0 or value > 100) ->
          {:halt, {:error, "#{key} must be a number between 0 and 100"}}

        key == :error_rate and (not is_number(value) or value < 0) ->
          {:halt, {:error, "error_rate must be a non-negative number"}}

        key == :agent_failures and (not is_integer(value) or value < 0) ->
          {:halt, {:error, "agent_failures must be a non-negative integer"}}

        true ->
          {:cont, :ok}
      end
    end)
  end

  # Handle periodic messages
  @impl true
  def handle_info(:collect_metrics, state) do
    if state.agent.state.monitoring_status == :active do
      instruction =
        Jido.Instruction.new!(%{
          action: CollectMetrics,
          params: %{}
        })

      Jido.Agent.Server.cast(self(), instruction)
      # Note: No longer self-scheduling - SchedulerManager handles this
    end

    {:noreply, state}
  end

  def handle_info(:analyze_health, state) do
    if state.agent.state.monitoring_status == :active do
      instruction =
        Jido.Instruction.new!(%{
          action: AnalyzeHealth,
          params: %{}
        })

      Jido.Agent.Server.cast(self(), instruction)
      # Note: No longer self-scheduling - SchedulerManager handles this
    end

    {:noreply, state}
  end

  def handle_info({:telemetry_event, event, _measurements, metadata}, state) do
    Logger.debug("MonitorAgent received telemetry event: #{inspect(event)}")

    # Process telemetry events and update monitoring state as needed
    case event do
      [:jido_system, :agent, :started] ->
        agent_id = metadata[:agent_id]

        if agent_id and agent_id not in state.agent.state.monitored_agents do
          new_monitored = [agent_id | state.agent.state.monitored_agents]
          new_agent_state = %{state.agent.state | monitored_agents: new_monitored}
          new_agent = %{state.agent | state: new_agent_state}

          emit_event(
            state.agent,
            :agent_registered_for_monitoring,
            %{
              agent_count: length(new_monitored)
            },
            %{agent_id: agent_id}
          )

          {:noreply, %{state | agent: new_agent}}
        else
          {:noreply, state}
        end

      [:jido_system, :agent, :terminated] ->
        agent_id = metadata[:agent_id]

        if agent_id do
          new_monitored = List.delete(state.agent.state.monitored_agents, agent_id)
          new_agent_state = %{state.agent.state | monitored_agents: new_monitored}
          new_agent = %{state.agent | state: new_agent_state}

          emit_event(
            state.agent,
            :agent_deregistered_from_monitoring,
            %{
              agent_count: length(new_monitored)
            },
            %{agent_id: agent_id}
          )

          {:noreply, %{state | agent: new_agent}}
        else
          {:noreply, state}
        end

      _ ->
        {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    Logger.debug("MonitorAgent received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.info("MonitorAgent terminating: #{inspect(reason)}")

    # Ensure we unregister from scheduler on termination
    try do
      unregister_from_scheduler()
    catch
      _, _ -> :ok
    end

    :ok
  end
end
