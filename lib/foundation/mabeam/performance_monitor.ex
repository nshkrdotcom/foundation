defmodule Foundation.MABEAM.PerformanceMonitor do
  @moduledoc """
  Real-time agent performance monitoring and metrics collection for MABEAM.

  Provides comprehensive performance monitoring capabilities including:
  - Agent performance metrics tracking (CPU, memory, throughput, errors)
  - Resource utilization monitoring and trending
  - Performance alerts and threshold management
  - Metrics aggregation and statistical analysis
  - Export functionality for monitoring dashboards

  ## Features

  - **Real-time Metrics Collection**: Track performance metrics as they occur
  - **Historical Analysis**: Store and analyze performance trends over time
  - **Alert System**: Configurable thresholds with automatic alert generation
  - **Statistical Aggregation**: Calculate performance statistics across agents
  - **Export Capabilities**: Export metrics in JSON, CSV, or programmatic formats
  - **Monitoring Lifecycle**: Start/stop monitoring for individual agents

  ## Usage

      # Start monitoring an agent
      :ok = PerformanceMonitor.start_monitoring(:worker1)

      # Record performance metrics
      metrics = %{
        cpu_usage: 0.65,
        memory_usage: 512 * 1024 * 1024,  # 512MB
        throughput: 15.5,                 # tasks per second
        error_rate: 0.02                  # 2% error rate
      }
      :ok = PerformanceMonitor.record_metrics(:worker1, metrics)

      # Get current metrics
      {:ok, current_metrics} = PerformanceMonitor.get_agent_metrics(:worker1)

      # Set alert thresholds
      thresholds = %{
        high_cpu_threshold: 0.8,
        high_memory_threshold: 1024 * 1024 * 1024,  # 1GB
        low_throughput_threshold: 5.0
      }
      :ok = PerformanceMonitor.set_alert_thresholds(thresholds)

      # Check for active alerts
      alerts = PerformanceMonitor.get_active_alerts()

      # Export metrics for external monitoring
      {:ok, json_data} = PerformanceMonitor.export_metrics(:json)
  """

  use GenServer
  require Logger

  alias Foundation.ProcessRegistry

  @type agent_id :: atom()
  @type metrics :: %{
          cpu_usage: float(),
          memory_usage: non_neg_integer(),
          task_completion_time: float(),
          throughput: float(),
          error_rate: float(),
          timestamp: DateTime.t()
        }
  @type alert :: %{
          agent_id: agent_id(),
          type: atom(),
          severity: :info | :warning | :critical,
          message: String.t(),
          triggered_at: DateTime.t()
        }
  @type alert_thresholds :: %{
          high_cpu_threshold: float(),
          high_memory_threshold: non_neg_integer(),
          high_error_rate_threshold: float(),
          low_throughput_threshold: float()
        }

  # Registry key for performance monitor state
  @monitor_key {:agent, :mabeam_performance_monitor}

  ## Public API

  @doc """
  Start the PerformanceMonitor GenServer.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Record performance metrics for an agent.

  ## Parameters
  - `agent_id` - The agent to record metrics for
  - `metrics` - Performance metrics map

  ## Returns
  - `:ok` - Metrics recorded successfully
  """
  @spec record_metrics(agent_id(), map()) :: :ok
  def record_metrics(agent_id, metrics) do
    GenServer.cast(__MODULE__, {:record_metrics, agent_id, metrics})
  end

  @doc """
  Get current performance metrics for an agent.

  ## Parameters
  - `agent_id` - The agent to get metrics for

  ## Returns
  - `{:ok, metrics}` - Current metrics for the agent
  - `{:error, :not_found}` - Agent has no recorded metrics
  """
  @spec get_agent_metrics(agent_id()) :: {:ok, metrics()} | {:error, :not_found}
  def get_agent_metrics(agent_id) do
    GenServer.call(__MODULE__, {:get_agent_metrics, agent_id})
  end

  @doc """
  Get metrics history for an agent.

  ## Parameters
  - `agent_id` - The agent to get history for
  - `opts` - Options including :limit for number of records

  ## Returns
  - `{:ok, [metrics]}` - List of historical metrics (newest first)
  - `{:error, :not_found}` - Agent has no recorded metrics
  """
  @spec get_metrics_history(agent_id(), keyword()) :: {:ok, [metrics()]} | {:error, :not_found}
  def get_metrics_history(agent_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    GenServer.call(__MODULE__, {:get_metrics_history, agent_id, limit})
  end

  @doc """
  Get aggregated performance statistics across all monitored agents.

  ## Returns
  - Performance statistics map with averages, totals, and extremes
  """
  @spec get_performance_statistics() :: %{
          total_agents: non_neg_integer(),
          average_cpu_usage: float(),
          average_throughput: float(),
          average_error_rate: float(),
          max_cpu_usage: float(),
          min_cpu_usage: float(),
          calculated_at: DateTime.t()
        }
  def get_performance_statistics() do
    GenServer.call(__MODULE__, :get_performance_statistics)
  end

  @doc """
  Set alert thresholds for performance monitoring.

  ## Parameters
  - `thresholds` - Map of threshold values

  ## Returns
  - `:ok` - Thresholds set successfully
  """
  @spec set_alert_thresholds(alert_thresholds()) :: :ok
  def set_alert_thresholds(thresholds) do
    GenServer.call(__MODULE__, {:set_alert_thresholds, thresholds})
  end

  @doc """
  Get currently active performance alerts.

  ## Returns
  - List of active alert maps
  """
  @spec get_active_alerts() :: [alert()]
  def get_active_alerts() do
    GenServer.call(__MODULE__, :get_active_alerts)
  end

  @doc """
  Start monitoring an agent.

  ## Parameters
  - `agent_id` - The agent to start monitoring

  ## Returns
  - `:ok` - Monitoring started successfully
  """
  @spec start_monitoring(agent_id()) :: :ok
  def start_monitoring(agent_id) do
    GenServer.call(__MODULE__, {:start_monitoring, agent_id})
  end

  @doc """
  Stop monitoring an agent.

  ## Parameters
  - `agent_id` - The agent to stop monitoring

  ## Returns
  - `:ok` - Monitoring stopped successfully
  """
  @spec stop_monitoring(agent_id()) :: :ok
  def stop_monitoring(agent_id) do
    GenServer.call(__MODULE__, {:stop_monitoring, agent_id})
  end

  @doc """
  Check if an agent is being monitored.

  ## Parameters
  - `agent_id` - The agent to check

  ## Returns
  - `{:ok, boolean}` - Whether the agent is being monitored
  """
  @spec is_monitoring?(agent_id()) :: {:ok, boolean()}
  def is_monitoring?(agent_id) do
    GenServer.call(__MODULE__, {:is_monitoring, agent_id})
  end

  @doc """
  Get monitoring status for all agents.

  ## Returns
  - Monitoring status summary
  """
  @spec get_monitoring_status() :: %{
          total_agents: non_neg_integer(),
          monitored_agents: non_neg_integer(),
          unmonitored_agents: non_neg_integer(),
          agent_status: %{monitored: [agent_id()], unmonitored: [agent_id()]}
        }
  def get_monitoring_status() do
    GenServer.call(__MODULE__, :get_monitoring_status)
  end

  @doc """
  Export performance metrics in the specified format.

  ## Parameters
  - `format` - Export format (:json, :csv, :map)

  ## Returns
  - `{:ok, data}` - Exported data in the requested format
  - `{:error, reason}` - Export failed
  """
  @spec export_metrics(:json | :csv | :map) :: {:ok, term()} | {:error, term()}
  def export_metrics(format) do
    GenServer.call(__MODULE__, {:export_metrics, format})
  end

  @doc """
  Clear all metrics data (for testing).
  """
  @spec clear_metrics() :: :ok
  def clear_metrics() do
    GenServer.call(__MODULE__, :clear_metrics)
  end

  ## GenServer Callbacks

  @impl true
  def init(opts) do
    # Initialize performance monitor state
    initial_state = %{
      # agent_id => current_metrics
      agent_metrics: %{},
      # agent_id => [historical_metrics]
      metrics_history: %{},
      # agent_id => boolean
      monitoring_status: %{},
      # [alert]
      active_alerts: [],
      alert_thresholds: default_alert_thresholds(),
      max_history_size: Keyword.get(opts, :max_history_size, 1000)
    }

    # Register with ProcessRegistry for service discovery
    ProcessRegistry.register(:production, @monitor_key, self(), %{
      type: :mabeam_performance_monitor,
      started_at: DateTime.utc_now()
    })

    Logger.info("MABEAM Performance Monitor started")

    {:ok, initial_state}
  end

  @impl true
  def handle_cast({:record_metrics, agent_id, metrics}, state) do
    # Only record metrics for agents that have been explicitly registered for monitoring
    # OR if the agent has been started in the monitoring system
    should_record =
      Map.has_key?(state.monitoring_status, agent_id) or
        Map.has_key?(state.agent_metrics, agent_id)

    if should_record do
      # Add timestamp if not present
      timestamped_metrics = Map.put_new(metrics, :timestamp, DateTime.utc_now())

      # Update current metrics
      updated_agent_metrics = Map.put(state.agent_metrics, agent_id, timestamped_metrics)

      # Update metrics history
      current_history = Map.get(state.metrics_history, agent_id, [])

      new_history =
        [timestamped_metrics | current_history]
        # Limit history size
        |> Enum.take(state.max_history_size)

      updated_history = Map.put(state.metrics_history, agent_id, new_history)

      # Check for alerts
      new_alerts = check_and_update_alerts(agent_id, timestamped_metrics, state)

      new_state = %{
        state
        | agent_metrics: updated_agent_metrics,
          metrics_history: updated_history,
          active_alerts: new_alerts
      }

      {:noreply, new_state}
    else
      # Don't record metrics for agents that aren't being monitored
      {:noreply, state}
    end
  end

  @impl true
  def handle_call({:get_agent_metrics, agent_id}, _from, state) do
    case Map.get(state.agent_metrics, agent_id) do
      nil -> {:reply, {:error, :not_found}, state}
      metrics -> {:reply, {:ok, metrics}, state}
    end
  end

  @impl true
  def handle_call({:get_metrics_history, agent_id, limit}, _from, state) do
    case Map.get(state.metrics_history, agent_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      history ->
        limited_history = Enum.take(history, limit)
        {:reply, {:ok, limited_history}, state}
    end
  end

  @impl true
  def handle_call(:get_performance_statistics, _from, state) do
    stats = calculate_performance_statistics(state.agent_metrics)
    {:reply, stats, state}
  end

  @impl true
  def handle_call({:set_alert_thresholds, thresholds}, _from, state) do
    new_state = %{state | alert_thresholds: thresholds}
    Logger.info("Performance alert thresholds updated: #{inspect(thresholds)}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_active_alerts, _from, state) do
    {:reply, state.active_alerts, state}
  end

  @impl true
  def handle_call({:start_monitoring, agent_id}, _from, state) do
    updated_status = Map.put(state.monitoring_status, agent_id, true)
    new_state = %{state | monitoring_status: updated_status}
    Logger.debug("Started monitoring agent #{agent_id}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:stop_monitoring, agent_id}, _from, state) do
    updated_status = Map.put(state.monitoring_status, agent_id, false)
    new_state = %{state | monitoring_status: updated_status}
    Logger.debug("Stopped monitoring agent #{agent_id}")
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:is_monitoring, agent_id}, _from, state) do
    is_monitoring = Map.get(state.monitoring_status, agent_id, false)
    {:reply, {:ok, is_monitoring}, state}
  end

  @impl true
  def handle_call(:get_monitoring_status, _from, state) do
    # Get all agents that have ever been tracked for monitoring
    # This includes agents with explicit monitoring status AND agents that have metrics
    all_tracked_agents =
      (Map.keys(state.monitoring_status) ++ Map.keys(state.agent_metrics))
      |> Enum.uniq()

    {monitored, unmonitored} =
      Enum.split_with(all_tracked_agents, fn agent_id ->
        Map.get(state.monitoring_status, agent_id, false)
      end)

    status = %{
      total_agents: length(all_tracked_agents),
      monitored_agents: length(monitored),
      unmonitored_agents: length(unmonitored),
      agent_status: %{
        monitored: monitored,
        unmonitored: unmonitored
      }
    }

    {:reply, status, state}
  end

  @impl true
  def handle_call({:export_metrics, format}, _from, state) do
    case export_metrics_internal(format, state) do
      {:ok, data} -> {:reply, {:ok, data}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:clear_metrics, _from, state) do
    cleared_state = %{
      state
      | agent_metrics: %{},
        metrics_history: %{},
        monitoring_status: %{},
        active_alerts: []
    }

    {:reply, :ok, cleared_state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  ## Private Functions

  defp default_alert_thresholds do
    %{
      high_cpu_threshold: 0.9,
      # 2GB
      high_memory_threshold: 2 * 1024 * 1024 * 1024,
      # 10%
      high_error_rate_threshold: 0.1,
      low_throughput_threshold: 1.0
    }
  end

  defp check_and_update_alerts(agent_id, metrics, state) do
    thresholds = state.alert_thresholds

    # Generate new alerts based on current metrics
    new_alerts = []

    new_alerts =
      if metrics[:cpu_usage] && metrics[:cpu_usage] > thresholds[:high_cpu_threshold] do
        alert = %{
          agent_id: agent_id,
          type: :high_cpu_usage,
          severity: :warning,
          message:
            "Agent #{agent_id} CPU usage is #{Float.round(metrics[:cpu_usage] * 100, 1)}% (threshold: #{Float.round(thresholds[:high_cpu_threshold] * 100, 1)}%)",
          triggered_at: DateTime.utc_now()
        }

        [alert | new_alerts]
      else
        new_alerts
      end

    new_alerts =
      if metrics[:memory_usage] && metrics[:memory_usage] > thresholds[:high_memory_threshold] do
        memory_mb = metrics[:memory_usage] / (1024 * 1024)
        threshold_mb = thresholds[:high_memory_threshold] / (1024 * 1024)

        alert = %{
          agent_id: agent_id,
          type: :high_memory_usage,
          severity: :warning,
          message:
            "Agent #{agent_id} memory usage is #{Float.round(memory_mb, 1)}MB (threshold: #{Float.round(threshold_mb, 1)}MB)",
          triggered_at: DateTime.utc_now()
        }

        [alert | new_alerts]
      else
        new_alerts
      end

    new_alerts =
      if metrics[:error_rate] && metrics[:error_rate] > thresholds[:high_error_rate_threshold] do
        alert = %{
          agent_id: agent_id,
          type: :high_error_rate,
          severity: :warning,
          message:
            "Agent #{agent_id} error rate is #{Float.round(metrics[:error_rate] * 100, 1)}% (threshold: #{Float.round(thresholds[:high_error_rate_threshold] * 100, 1)}%)",
          triggered_at: DateTime.utc_now()
        }

        [alert | new_alerts]
      else
        new_alerts
      end

    new_alerts =
      if metrics[:throughput] && metrics[:throughput] < thresholds[:low_throughput_threshold] do
        alert = %{
          agent_id: agent_id,
          type: :low_throughput,
          severity: :warning,
          message:
            "Agent #{agent_id} throughput is #{metrics[:throughput]} tasks/sec (threshold: #{thresholds[:low_throughput_threshold]} tasks/sec)",
          triggered_at: DateTime.utc_now()
        }

        [alert | new_alerts]
      else
        new_alerts
      end

    # Remove resolved alerts (where current metrics are back to normal)
    existing_alerts = state.active_alerts

    resolved_alerts =
      Enum.filter(existing_alerts, fn alert ->
        if alert.agent_id == agent_id do
          case alert.type do
            :high_cpu_usage ->
              metrics[:cpu_usage] && metrics[:cpu_usage] <= thresholds[:high_cpu_threshold]

            :high_memory_usage ->
              metrics[:memory_usage] && metrics[:memory_usage] <= thresholds[:high_memory_threshold]

            :high_error_rate ->
              metrics[:error_rate] && metrics[:error_rate] <= thresholds[:high_error_rate_threshold]

            :low_throughput ->
              metrics[:throughput] && metrics[:throughput] >= thresholds[:low_throughput_threshold]

            _ ->
              false
          end
        else
          false
        end
      end)

    # Keep alerts that are not resolved and add new alerts
    unresolved_alerts = existing_alerts -- resolved_alerts
    all_alerts = unresolved_alerts ++ new_alerts

    # Log resolved alerts
    Enum.each(resolved_alerts, fn alert ->
      Logger.info("Performance alert resolved: #{alert.type} for agent #{alert.agent_id}")
    end)

    # Log new alerts
    Enum.each(new_alerts, fn alert ->
      Logger.warning("Performance alert triggered: #{alert.message}")
    end)

    all_alerts
  end

  defp calculate_performance_statistics(agent_metrics) do
    if map_size(agent_metrics) == 0 do
      %{
        total_agents: 0,
        average_cpu_usage: 0.0,
        average_throughput: 0.0,
        average_error_rate: 0.0,
        max_cpu_usage: 0.0,
        min_cpu_usage: 0.0,
        calculated_at: DateTime.utc_now()
      }
    else
      metrics_list = Map.values(agent_metrics)

      cpu_values = Enum.map(metrics_list, &(&1[:cpu_usage] || 0.0))
      throughput_values = Enum.map(metrics_list, &(&1[:throughput] || 0.0))
      error_rate_values = Enum.map(metrics_list, &(&1[:error_rate] || 0.0))

      %{
        total_agents: length(metrics_list),
        average_cpu_usage: calculate_average(cpu_values),
        average_throughput: calculate_average(throughput_values),
        average_error_rate: calculate_average(error_rate_values),
        max_cpu_usage: Enum.max(cpu_values),
        min_cpu_usage: Enum.min(cpu_values),
        calculated_at: DateTime.utc_now()
      }
    end
  end

  defp calculate_average([]), do: 0.0

  defp calculate_average(values) do
    result = Enum.sum(values) / length(values)
    # Round to avoid floating point precision issues in tests
    Float.round(result, 10)
  end

  defp export_metrics_internal(format, state) do
    export_data = %{
      agents: state.agent_metrics,
      statistics: calculate_performance_statistics(state.agent_metrics),
      alerts: state.active_alerts,
      exported_at: DateTime.utc_now()
    }

    case format do
      :map ->
        {:ok, export_data}

      :json ->
        case Jason.encode(export_data) do
          {:ok, json} -> {:ok, json}
          {:error, reason} -> {:error, {:json_encode_failed, reason}}
        end

      :csv ->
        {:ok, export_to_csv(state.agent_metrics)}

      _ ->
        {:error, {:unsupported_format, format}}
    end
  end

  defp export_to_csv(agent_metrics) do
    headers = "agent_id,cpu_usage,memory_usage,throughput,error_rate,timestamp\n"

    rows =
      Enum.map(agent_metrics, fn {agent_id, metrics} ->
        "#{agent_id},#{metrics[:cpu_usage] || ""},#{metrics[:memory_usage] || ""},#{metrics[:throughput] || ""},#{metrics[:error_rate] || ""},#{metrics[:timestamp] || ""}"
      end)

    headers <> Enum.join(rows, "\n")
  end
end
