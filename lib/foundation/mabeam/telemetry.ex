defmodule Foundation.MABEAM.Telemetry do
  @moduledoc """
  MABEAM-specific telemetry and monitoring functionality.

  Provides comprehensive observability for multi-agent systems including:
  - Agent performance metrics collection
  - Coordination analytics and tracking
  - System health monitoring
  - Performance anomaly detection
  - Configurable alerting and notifications

  This module extends Foundation.Telemetry with MABEAM-specific capabilities
  while maintaining compatibility with the existing telemetry infrastructure.
  """

  use GenServer
  require Logger

  alias Foundation.Telemetry

  @type agent_id :: String.t()
  @type metric_type :: atom()
  @type metric_value :: number()
  @type protocol_id :: String.t()
  @type auction_id :: String.t()
  @type market_id :: String.t()
  @type time_window :: :last_minute | :last_hour | :last_day
  @type alert_config :: %{
          metric: metric_type(),
          threshold: number(),
          comparison: :greater_than | :less_than | :equal_to,
          action: :notify | :log | :email
        }

  @default_retention_minutes 60
  @cleanup_interval_ms 30_000
  # Standard deviations
  @anomaly_detection_threshold 2.0

  ## Public API

  @doc "Start the MABEAM telemetry service"
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Clear all metrics (mainly for testing)"
  @spec clear_metrics() :: :ok
  def clear_metrics do
    GenServer.call(__MODULE__, :clear_metrics)
  end

  ## Agent Performance Metrics

  @doc "Record an agent performance metric"
  @spec record_agent_metric(agent_id(), metric_type(), metric_value()) :: :ok | {:error, term()}
  def record_agent_metric(agent_id, metric_type, value) when is_number(value) do
    GenServer.cast(
      __MODULE__,
      {:record_agent_metric, agent_id, metric_type, value, System.system_time(:millisecond)}
    )

    # Also emit telemetry event
    Telemetry.execute(
      [:foundation, :mabeam, :agent, :metric],
      %{value: value},
      %{agent_id: agent_id, metric_type: metric_type}
    )

    :ok
  end

  def record_agent_metric(_agent_id, _metric_type, _value) do
    {:error, "Metric value must be a number"}
  end

  @doc "Get current metrics for an agent"
  @spec get_agent_metrics(agent_id()) :: {:ok, map()} | {:error, term()}
  def get_agent_metrics(agent_id) do
    GenServer.call(__MODULE__, {:get_agent_metrics, agent_id})
  end

  @doc "Get aggregated statistics for an agent metric"
  @spec get_agent_statistics(agent_id(), metric_type(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def get_agent_statistics(agent_id, metric_type, opts \\ []) do
    window = Keyword.get(opts, :window, :last_minute)
    GenServer.call(__MODULE__, {:get_agent_statistics, agent_id, metric_type, window})
  end

  @doc "Record agent operation outcome"
  @spec record_agent_outcome(agent_id(), :success | :failure, map()) :: :ok
  def record_agent_outcome(agent_id, outcome, metadata \\ %{}) do
    GenServer.cast(
      __MODULE__,
      {:record_agent_outcome, agent_id, outcome, metadata, System.system_time(:millisecond)}
    )

    :ok
  end

  @doc "Get agent success rate"
  @spec get_agent_success_rate(agent_id()) :: {:ok, map()} | {:error, term()}
  def get_agent_success_rate(agent_id) do
    GenServer.call(__MODULE__, {:get_agent_success_rate, agent_id})
  end

  @doc "Record variable optimization metrics"
  @spec record_variable_optimization(agent_id(), String.t(), map()) :: :ok
  def record_variable_optimization(agent_id, variable_id, metrics) do
    GenServer.cast(
      __MODULE__,
      {:record_variable_optimization, agent_id, variable_id, metrics,
       System.system_time(:millisecond)}
    )

    :ok
  end

  @doc "Get variable optimization metrics"
  @spec get_variable_optimization_metrics(agent_id(), String.t()) :: {:ok, map()} | {:error, term()}
  def get_variable_optimization_metrics(agent_id, variable_id) do
    GenServer.call(__MODULE__, {:get_variable_optimization_metrics, agent_id, variable_id})
  end

  ## Coordination Analytics

  @doc "Record coordination event"
  @spec record_coordination_event(protocol_id(), atom(), map()) :: :ok
  def record_coordination_event(protocol_id, event_type, metadata \\ %{}) do
    GenServer.cast(
      __MODULE__,
      {:record_coordination_event, protocol_id, event_type, metadata,
       System.system_time(:millisecond)}
    )

    :ok
  end

  @doc "Get coordination metrics"
  @spec get_coordination_metrics(protocol_id()) :: {:ok, map()} | {:error, term()}
  def get_coordination_metrics(protocol_id) do
    GenServer.call(__MODULE__, {:get_coordination_metrics, protocol_id})
  end

  @doc "Record auction event"
  @spec record_auction_event(auction_id(), atom(), map()) :: :ok
  def record_auction_event(auction_id, event_type, metadata \\ %{}) do
    GenServer.cast(
      __MODULE__,
      {:record_auction_event, auction_id, event_type, metadata, System.system_time(:millisecond)}
    )

    :ok
  end

  @doc "Get auction metrics"
  @spec get_auction_metrics(auction_id()) :: {:ok, map()} | {:error, term()}
  def get_auction_metrics(auction_id) do
    GenServer.call(__MODULE__, {:get_auction_metrics, auction_id})
  end

  @doc "Record market event"
  @spec record_market_event(market_id(), atom(), map()) :: :ok
  def record_market_event(market_id, event_type, metadata \\ %{}) do
    GenServer.cast(
      __MODULE__,
      {:record_market_event, market_id, event_type, metadata, System.system_time(:millisecond)}
    )

    :ok
  end

  @doc "Get market metrics"
  @spec get_market_metrics(market_id()) :: {:ok, map()} | {:error, term()}
  def get_market_metrics(market_id) do
    GenServer.call(__MODULE__, {:get_market_metrics, market_id})
  end

  ## System Health Monitoring

  @doc "Get overall system health"
  @spec get_system_health() :: {:ok, map()} | {:error, term()}
  def get_system_health do
    GenServer.call(__MODULE__, :get_system_health)
  end

  @doc "Record resource usage"
  @spec record_resource_usage(atom(), number()) :: :ok
  def record_resource_usage(resource_type, value) do
    GenServer.cast(
      __MODULE__,
      {:record_resource_usage, resource_type, value, System.system_time(:millisecond)}
    )

    :ok
  end

  @doc "Get resource utilization"
  @spec get_resource_utilization() :: {:ok, map()} | {:error, term()}
  def get_resource_utilization do
    GenServer.call(__MODULE__, :get_resource_utilization)
  end

  @doc "Detect performance anomalies"
  @spec detect_anomalies(agent_id(), metric_type()) :: {:ok, list()} | {:error, term()}
  def detect_anomalies(agent_id, metric_type) do
    GenServer.call(__MODULE__, {:detect_anomalies, agent_id, metric_type})
  end

  ## Alerting and Notifications

  @doc "Configure alert threshold"
  @spec configure_alert(atom(), alert_config()) :: :ok
  def configure_alert(alert_id, config) do
    GenServer.cast(__MODULE__, {:configure_alert, alert_id, config})
    :ok
  end

  @doc "Get alert configuration"
  @spec get_alert_configuration(atom()) :: {:ok, alert_config()} | {:error, term()}
  def get_alert_configuration(alert_id) do
    GenServer.call(__MODULE__, {:get_alert_configuration, alert_id})
  end

  @doc "Set alert handler function"
  @spec set_alert_handler((map() -> any())) :: :ok
  def set_alert_handler(handler_fun) when is_function(handler_fun, 1) do
    GenServer.cast(__MODULE__, {:set_alert_handler, handler_fun})
    :ok
  end

  ## Dashboard Integration

  @doc "Get structured dashboard data"
  @spec get_dashboard_data() :: {:ok, map()} | {:error, term()}
  def get_dashboard_data do
    GenServer.call(__MODULE__, :get_dashboard_data)
  end

  @doc "Export metrics in various formats"
  @spec export_metrics(:json | :prometheus) :: {:ok, String.t()} | {:error, term()}
  def export_metrics(format) do
    GenServer.call(__MODULE__, {:export_metrics, format})
  end

  ## GenServer Implementation

  @impl GenServer
  def init(_opts) do
    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)

    {:ok,
     %{
       agent_metrics: %{},
       agent_outcomes: %{},
       variable_metrics: %{},
       coordination_events: %{},
       auction_events: %{},
       market_events: %{},
       resource_usage: %{},
       alert_configs: %{},
       alert_handler: nil,
       start_time: System.system_time(:millisecond)
     }}
  end

  @impl GenServer
  def handle_call(:clear_metrics, _from, state) do
    new_state = %{
      state
      | agent_metrics: %{},
        agent_outcomes: %{},
        variable_metrics: %{},
        coordination_events: %{},
        auction_events: %{},
        market_events: %{},
        resource_usage: %{}
    }

    {:reply, :ok, new_state}
  end

  def handle_call({:get_agent_metrics, agent_id}, _from, state) do
    case Map.get(state.agent_metrics, agent_id) do
      nil ->
        {:reply, {:ok, %{}}, state}

      metrics ->
        formatted_metrics = format_agent_metrics(metrics)
        {:reply, {:ok, formatted_metrics}, state}
    end
  end

  def handle_call({:get_agent_statistics, agent_id, metric_type, window}, _from, state) do
    case Map.get(state.agent_metrics, agent_id) do
      nil ->
        {:reply, {:error, "Agent not found"}, state}

      agent_metrics ->
        case Map.get(agent_metrics, metric_type) do
          nil ->
            {:reply, {:error, "Metric type not found"}, state}

          metric_data ->
            stats = calculate_statistics(metric_data, window)
            {:reply, {:ok, stats}, state}
        end
    end
  end

  def handle_call({:get_agent_success_rate, agent_id}, _from, state) do
    case Map.get(state.agent_outcomes, agent_id) do
      nil ->
        {:reply,
         {:ok,
          %{success_rate: 0.0, total_operations: 0, successful_operations: 0, failed_operations: 0}},
         state}

      outcomes ->
        success_rate = calculate_success_rate(outcomes)
        {:reply, {:ok, success_rate}, state}
    end
  end

  def handle_call({:get_variable_optimization_metrics, agent_id, variable_id}, _from, state) do
    key = {agent_id, variable_id}

    case Map.get(state.variable_metrics, key) do
      nil ->
        {:reply, {:error, "Variable metrics not found"}, state}

      metrics ->
        {:reply, {:ok, metrics}, state}
    end
  end

  def handle_call({:get_coordination_metrics, protocol_id}, _from, state) do
    case Map.get(state.coordination_events, protocol_id) do
      nil ->
        {:reply, {:ok, %{total_coordinations: 0, successful_coordinations: 0, average_duration: 0}},
         state}

      events ->
        metrics = calculate_coordination_metrics(events)
        {:reply, {:ok, metrics}, state}
    end
  end

  def handle_call({:get_auction_metrics, auction_id}, _from, state) do
    case Map.get(state.auction_events, auction_id) do
      nil ->
        {:reply, {:ok, %{total_bids: 0, revenue: 0, efficiency: 0}}, state}

      events ->
        metrics = calculate_auction_metrics(events)
        {:reply, {:ok, metrics}, state}
    end
  end

  def handle_call({:get_market_metrics, market_id}, _from, state) do
    case Map.get(state.market_events, market_id) do
      nil ->
        {:reply, {:ok, %{total_trades: 0, average_price: 0, price_efficiency: 0}}, state}

      events ->
        metrics = calculate_market_metrics(events)
        {:reply, {:ok, metrics}, state}
    end
  end

  def handle_call(:get_system_health, _from, state) do
    uptime = System.system_time(:millisecond) - state.start_time

    health = %{
      agent_registry: %{
        status: :healthy,
        uptime: uptime,
        resource_usage: get_component_resource_usage(:agent_registry, state)
      },
      coordination: %{
        status: :healthy,
        uptime: uptime,
        resource_usage: get_component_resource_usage(:coordination, state)
      },
      core_orchestrator: %{
        status: :healthy,
        uptime: uptime,
        resource_usage: get_component_resource_usage(:core_orchestrator, state)
      }
    }

    {:reply, {:ok, health}, state}
  end

  def handle_call(:get_resource_utilization, _from, state) do
    latest_usage = get_latest_resource_usage(state.resource_usage)
    {:reply, {:ok, latest_usage}, state}
  end

  def handle_call({:detect_anomalies, agent_id, metric_type}, _from, state) do
    case Map.get(state.agent_metrics, agent_id) do
      nil ->
        {:reply, {:ok, []}, state}

      agent_metrics ->
        case Map.get(agent_metrics, metric_type) do
          nil ->
            {:reply, {:ok, []}, state}

          metric_data ->
            anomalies = detect_metric_anomalies(metric_data)
            {:reply, {:ok, anomalies}, state}
        end
    end
  end

  def handle_call({:get_alert_configuration, alert_id}, _from, state) do
    case Map.get(state.alert_configs, alert_id) do
      nil ->
        {:reply, {:error, "Alert configuration not found"}, state}

      config ->
        {:reply, {:ok, config}, state}
    end
  end

  def handle_call(:get_dashboard_data, _from, state) do
    dashboard_data = %{
      agent_metrics: summarize_agent_metrics(state.agent_metrics),
      coordination_metrics: summarize_coordination_metrics(state.coordination_events),
      system_health: get_system_health_summary(state),
      recent_events: get_recent_events(state)
    }

    {:reply, {:ok, dashboard_data}, state}
  end

  def handle_call({:export_metrics, format}, _from, state) do
    case format do
      :json ->
        data = %{
          agent_metrics: serialize_for_json(state.agent_metrics),
          coordination_events: serialize_coordination_events_for_json(state.coordination_events),
          resource_usage: serialize_for_json(state.resource_usage),
          timestamp: System.system_time(:millisecond)
        }

        json_data = Jason.encode!(data)
        {:reply, {:ok, json_data}, state}

      :prometheus ->
        prometheus_data = format_prometheus_metrics(state)
        {:reply, {:ok, prometheus_data}, state}

      _ ->
        {:reply, {:error, "Unsupported format"}, state}
    end
  end

  @impl GenServer
  def handle_cast({:record_agent_metric, agent_id, metric_type, value, timestamp}, state) do
    new_metrics = add_agent_metric(state.agent_metrics, agent_id, metric_type, value, timestamp)
    new_state = %{state | agent_metrics: new_metrics}

    # Check for alerts
    check_and_trigger_alerts(agent_id, metric_type, value, state.alert_configs, state.alert_handler)

    {:noreply, new_state}
  end

  def handle_cast({:record_agent_outcome, agent_id, outcome, metadata, timestamp}, state) do
    new_outcomes = add_agent_outcome(state.agent_outcomes, agent_id, outcome, metadata, timestamp)
    new_state = %{state | agent_outcomes: new_outcomes}
    {:noreply, new_state}
  end

  def handle_cast({:record_variable_optimization, agent_id, variable_id, metrics, timestamp}, state) do
    key = {agent_id, variable_id}

    enhanced_metrics =
      Map.merge(metrics, %{
        improvement: metrics.optimized_value - metrics.initial_value,
        timestamp: timestamp
      })

    new_variable_metrics = Map.put(state.variable_metrics, key, enhanced_metrics)
    new_state = %{state | variable_metrics: new_variable_metrics}
    {:noreply, new_state}
  end

  def handle_cast({:record_coordination_event, protocol_id, event_type, metadata, timestamp}, state) do
    new_events =
      add_coordination_event(
        state.coordination_events,
        protocol_id,
        event_type,
        metadata,
        timestamp
      )

    new_state = %{state | coordination_events: new_events}
    {:noreply, new_state}
  end

  def handle_cast({:record_auction_event, auction_id, event_type, metadata, timestamp}, state) do
    new_events =
      add_auction_event(state.auction_events, auction_id, event_type, metadata, timestamp)

    new_state = %{state | auction_events: new_events}
    {:noreply, new_state}
  end

  def handle_cast({:record_market_event, market_id, event_type, metadata, timestamp}, state) do
    new_events = add_market_event(state.market_events, market_id, event_type, metadata, timestamp)
    new_state = %{state | market_events: new_events}
    {:noreply, new_state}
  end

  def handle_cast({:record_resource_usage, resource_type, value, timestamp}, state) do
    new_usage = add_resource_usage(state.resource_usage, resource_type, value, timestamp)
    new_state = %{state | resource_usage: new_usage}
    {:noreply, new_state}
  end

  def handle_cast({:configure_alert, alert_id, config}, state) do
    new_configs = Map.put(state.alert_configs, alert_id, config)
    new_state = %{state | alert_configs: new_configs}
    {:noreply, new_state}
  end

  def handle_cast({:set_alert_handler, handler_fun}, state) do
    new_state = %{state | alert_handler: handler_fun}
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:cleanup, state) do
    # Schedule next cleanup
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)

    # Clean up old metrics
    cutoff_time = System.system_time(:millisecond) - @default_retention_minutes * 60 * 1000
    new_state = cleanup_old_metrics(state, cutoff_time)

    {:noreply, new_state}
  end

  ## Private Helper Functions

  defp format_agent_metrics(metrics) do
    Enum.into(metrics, %{}, fn {metric_type, data} ->
      {metric_type, %{latest: get_latest_value(data)}}
    end)
  end

  defp get_latest_value(data) when is_list(data) do
    case Enum.max_by(data, fn {_value, timestamp} -> timestamp end, fn -> nil end) do
      nil -> 0
      {value, _timestamp} -> value
    end
  end

  defp calculate_statistics(metric_data, window) do
    cutoff_time = get_window_cutoff_time(window)
    recent_data = Enum.filter(metric_data, fn {_value, timestamp} -> timestamp >= cutoff_time end)
    values = Enum.map(recent_data, fn {value, _timestamp} -> value end)

    if Enum.empty?(values) do
      %{count: 0, average: 0, min: 0, max: 0, median: 0}
    else
      sorted_values = Enum.sort(values)
      count = length(values)
      average = Enum.sum(values) / count
      min = List.first(sorted_values)
      max = List.last(sorted_values)
      median = calculate_median(sorted_values)

      %{
        count: count,
        average: average,
        min: min,
        max: max,
        median: median
      }
    end
  end

  defp calculate_median([]), do: 0

  defp calculate_median(sorted_list) do
    len = length(sorted_list)

    if rem(len, 2) == 0 do
      # Even number of elements
      mid1 = Enum.at(sorted_list, div(len, 2) - 1)
      mid2 = Enum.at(sorted_list, div(len, 2))
      (mid1 + mid2) / 2
    else
      # Odd number of elements
      Enum.at(sorted_list, div(len, 2))
    end
  end

  defp calculate_success_rate(outcomes) do
    total = length(outcomes)

    successful =
      Enum.count(outcomes, fn {outcome, _metadata, _timestamp} -> outcome == :success end)

    failed = total - successful

    success_rate = if total > 0, do: Float.round(successful / total, 3), else: 0.0

    %{
      success_rate: success_rate,
      total_operations: total,
      successful_operations: successful,
      failed_operations: failed
    }
  end

  defp calculate_coordination_metrics(events) do
    completed_events =
      Enum.filter(events, fn {event_type, _metadata, _timestamp} ->
        event_type == :complete
      end)

    total_coordinations = length(completed_events)

    successful =
      Enum.count(completed_events, fn {_event_type, metadata, _timestamp} ->
        Map.get(metadata, :success, false)
      end)

    durations =
      Enum.map(completed_events, fn {_event_type, metadata, _timestamp} ->
        Map.get(metadata, :duration, 0)
      end)

    average_duration =
      if Enum.empty?(durations), do: 0, else: Enum.sum(durations) / length(durations)

    %{
      total_coordinations: total_coordinations,
      successful_coordinations: successful,
      average_duration: average_duration
    }
  end

  defp calculate_auction_metrics(events) do
    complete_events =
      Enum.filter(events, fn {event_type, _metadata, _timestamp} ->
        event_type == :complete
      end)

    bid_events =
      Enum.filter(events, fn {event_type, _metadata, _timestamp} ->
        event_type == :bid_received
      end)

    total_bids = length(bid_events)

    {revenue, efficiency} =
      case List.first(complete_events) do
        nil ->
          {0, 0}

        {_event_type, metadata, _timestamp} ->
          {Map.get(metadata, :revenue, 0), Map.get(metadata, :efficiency, 0)}
      end

    %{
      total_bids: total_bids,
      revenue: revenue,
      efficiency: efficiency
    }
  end

  defp calculate_market_metrics(events) do
    trade_events =
      Enum.filter(events, fn {event_type, _metadata, _timestamp} ->
        event_type == :trade_executed
      end)

    total_trades = length(trade_events)

    if total_trades == 0 do
      %{total_trades: 0, average_price: 0, price_efficiency: 0}
    else
      prices =
        Enum.map(trade_events, fn {_event_type, metadata, _timestamp} ->
          Map.get(metadata, :price, 0)
        end)

      average_price = Enum.sum(prices) / length(prices)

      # Calculate price efficiency based on equilibrium price
      equilibrium_prices =
        Enum.map(trade_events, fn {_event_type, metadata, _timestamp} ->
          Map.get(metadata, :equilibrium_price, 0)
        end)

      price_efficiency =
        if Enum.sum(equilibrium_prices) > 0 do
          1.0 -
            abs(average_price - Enum.sum(equilibrium_prices) / length(equilibrium_prices)) /
              average_price
        else
          1.0
        end

      %{
        total_trades: total_trades,
        average_price: average_price,
        price_efficiency: max(0.0, price_efficiency)
      }
    end
  end

  defp get_component_resource_usage(_component, _state) do
    # Placeholder for component-specific resource usage
    %{memory: 0, cpu: 0.0, network: 0}
  end

  defp get_latest_resource_usage(resource_usage) do
    Enum.into(resource_usage, %{}, fn {resource_type, data} ->
      latest_value = get_latest_value(data)
      {resource_type, latest_value}
    end)
  end

  defp detect_metric_anomalies(metric_data) do
    values = Enum.map(metric_data, fn {value, _timestamp} -> value end)

    if length(values) < 3 do
      []
    else
      mean = Enum.sum(values) / length(values)
      variance = Enum.sum(Enum.map(values, fn x -> :math.pow(x - mean, 2) end)) / length(values)
      std_dev = :math.sqrt(variance)

      threshold = @anomaly_detection_threshold * std_dev

      Enum.filter(metric_data, fn {value, _timestamp} ->
        abs(value - mean) > threshold
      end)
      |> Enum.map(fn {value, timestamp} ->
        %{value: value, timestamp: timestamp, deviation: abs(value - mean) / std_dev}
      end)
    end
  end

  defp check_and_trigger_alerts(agent_id, metric_type, value, alert_configs, alert_handler) do
    if alert_handler do
      Enum.each(alert_configs, fn {alert_id, config} ->
        if config.metric == metric_type and threshold_exceeded?(value, config) do
          alert = %{
            alert_id: alert_id,
            agent_id: agent_id,
            metric: metric_type,
            value: value,
            threshold: config.threshold,
            comparison: config.comparison,
            timestamp: System.system_time(:millisecond)
          }

          try do
            alert_handler.(alert)
          rescue
            error ->
              Logger.warning("Error in alert handler: #{inspect(error)}")
          end
        end
      end)
    end
  end

  defp threshold_exceeded?(value, config) do
    case config.comparison do
      :greater_than -> value > config.threshold
      :less_than -> value < config.threshold
      :equal_to -> value == config.threshold
    end
  end

  defp summarize_agent_metrics(agent_metrics) do
    Enum.into(agent_metrics, %{}, fn {agent_id, metrics} ->
      summary =
        Enum.into(metrics, %{}, fn {metric_type, data} ->
          {metric_type, get_latest_value(data)}
        end)

      {agent_id, summary}
    end)
  end

  defp summarize_coordination_metrics(coordination_events) do
    Enum.into(coordination_events, %{}, fn {protocol_id, events} ->
      {protocol_id, calculate_coordination_metrics(events)}
    end)
  end

  defp get_system_health_summary(state) do
    uptime = System.system_time(:millisecond) - state.start_time

    %{
      uptime: uptime,
      components_healthy: 3,
      total_components: 3
    }
  end

  defp get_recent_events(state) do
    # Last minute
    cutoff_time = System.system_time(:millisecond) - 60_000

    recent_coordination =
      get_recent_events_from_collection(state.coordination_events, cutoff_time, :coordination)

    recent_auction = get_recent_events_from_collection(state.auction_events, cutoff_time, :auction)
    recent_market = get_recent_events_from_collection(state.market_events, cutoff_time, :market)

    (recent_coordination ++ recent_auction ++ recent_market)
    |> Enum.sort_by(fn event -> event.timestamp end, :desc)
    |> Enum.take(10)
  end

  defp get_recent_events_from_collection(collection, cutoff_time, event_category) do
    Enum.flat_map(collection, fn {id, events} ->
      Enum.filter(events, fn {_event_type, _metadata, timestamp} ->
        timestamp >= cutoff_time
      end)
      |> Enum.map(fn {event_type, metadata, timestamp} ->
        %{
          category: event_category,
          id: id,
          event_type: event_type,
          metadata: metadata,
          timestamp: timestamp
        }
      end)
    end)
  end

  defp format_prometheus_metrics(state) do
    lines = []

    # Add agent metrics
    lines = lines ++ format_agent_metrics_prometheus(state.agent_metrics)

    # Add system metrics
    lines = lines ++ format_system_metrics_prometheus(state)

    Enum.join(lines, "\n")
  end

  defp format_agent_metrics_prometheus(agent_metrics) do
    Enum.flat_map(agent_metrics, fn {agent_id, metrics} ->
      Enum.flat_map(metrics, fn {metric_type, data} ->
        latest_value = get_latest_value(data)

        [
          "# HELP mabeam_agent_#{metric_type} Agent #{metric_type} metric",
          "# TYPE mabeam_agent_#{metric_type} gauge",
          "mabeam_agent_#{metric_type}{agent_id=\"#{agent_id}\"} #{latest_value}"
        ]
      end)
    end)
  end

  defp format_system_metrics_prometheus(state) do
    uptime = System.system_time(:millisecond) - state.start_time

    [
      "# HELP mabeam_system_uptime_ms System uptime in milliseconds",
      "# TYPE mabeam_system_uptime_ms counter",
      "mabeam_system_uptime_ms #{uptime}"
    ]
  end

  defp get_window_cutoff_time(window) do
    current_time = System.system_time(:millisecond)

    case window do
      :last_minute -> current_time - 60_000
      :last_hour -> current_time - 3_600_000
      :last_day -> current_time - 86_400_000
    end
  end

  defp add_agent_metric(agent_metrics, agent_id, metric_type, value, timestamp) do
    agent_data = Map.get(agent_metrics, agent_id, %{})
    metric_data = Map.get(agent_data, metric_type, [])
    new_metric_data = [{value, timestamp} | metric_data]
    new_agent_data = Map.put(agent_data, metric_type, new_metric_data)
    Map.put(agent_metrics, agent_id, new_agent_data)
  end

  defp add_agent_outcome(agent_outcomes, agent_id, outcome, metadata, timestamp) do
    outcomes = Map.get(agent_outcomes, agent_id, [])
    new_outcomes = [{outcome, metadata, timestamp} | outcomes]
    Map.put(agent_outcomes, agent_id, new_outcomes)
  end

  defp add_coordination_event(coordination_events, protocol_id, event_type, metadata, timestamp) do
    events = Map.get(coordination_events, protocol_id, [])
    new_events = [{event_type, metadata, timestamp} | events]
    Map.put(coordination_events, protocol_id, new_events)
  end

  defp add_auction_event(auction_events, auction_id, event_type, metadata, timestamp) do
    events = Map.get(auction_events, auction_id, [])
    new_events = [{event_type, metadata, timestamp} | events]
    Map.put(auction_events, auction_id, new_events)
  end

  defp add_market_event(market_events, market_id, event_type, metadata, timestamp) do
    events = Map.get(market_events, market_id, [])
    new_events = [{event_type, metadata, timestamp} | events]
    Map.put(market_events, market_id, new_events)
  end

  defp add_resource_usage(resource_usage, resource_type, value, timestamp) do
    usage_data = Map.get(resource_usage, resource_type, [])
    new_usage_data = [{value, timestamp} | usage_data]
    Map.put(resource_usage, resource_type, new_usage_data)
  end

  defp cleanup_old_metrics(state, cutoff_time) do
    %{
      state
      | agent_metrics: cleanup_agent_metrics(state.agent_metrics, cutoff_time),
        agent_outcomes: cleanup_agent_outcomes(state.agent_outcomes, cutoff_time),
        coordination_events: cleanup_coordination_events(state.coordination_events, cutoff_time),
        auction_events: cleanup_auction_events(state.auction_events, cutoff_time),
        market_events: cleanup_market_events(state.market_events, cutoff_time),
        resource_usage: cleanup_resource_usage(state.resource_usage, cutoff_time)
    }
  end

  defp cleanup_agent_metrics(agent_metrics, cutoff_time) do
    Enum.into(agent_metrics, %{}, fn {agent_id, metrics} ->
      cleaned_metrics =
        Enum.into(metrics, %{}, fn {metric_type, data} ->
          cleaned_data = Enum.filter(data, fn {_value, timestamp} -> timestamp >= cutoff_time end)
          {metric_type, cleaned_data}
        end)

      {agent_id, cleaned_metrics}
    end)
  end

  defp cleanup_agent_outcomes(agent_outcomes, cutoff_time) do
    Enum.into(agent_outcomes, %{}, fn {agent_id, outcomes} ->
      cleaned_outcomes =
        Enum.filter(outcomes, fn {_outcome, _metadata, timestamp} ->
          timestamp >= cutoff_time
        end)

      {agent_id, cleaned_outcomes}
    end)
  end

  defp cleanup_coordination_events(coordination_events, cutoff_time) do
    Enum.into(coordination_events, %{}, fn {protocol_id, events} ->
      cleaned_events =
        Enum.filter(events, fn {_event_type, _metadata, timestamp} ->
          timestamp >= cutoff_time
        end)

      {protocol_id, cleaned_events}
    end)
  end

  defp cleanup_auction_events(auction_events, cutoff_time) do
    Enum.into(auction_events, %{}, fn {auction_id, events} ->
      cleaned_events =
        Enum.filter(events, fn {_event_type, _metadata, timestamp} ->
          timestamp >= cutoff_time
        end)

      {auction_id, cleaned_events}
    end)
  end

  defp cleanup_market_events(market_events, cutoff_time) do
    Enum.into(market_events, %{}, fn {market_id, events} ->
      cleaned_events =
        Enum.filter(events, fn {_event_type, _metadata, timestamp} ->
          timestamp >= cutoff_time
        end)

      {market_id, cleaned_events}
    end)
  end

  defp cleanup_resource_usage(resource_usage, cutoff_time) do
    Enum.into(resource_usage, %{}, fn {resource_type, data} ->
      cleaned_data = Enum.filter(data, fn {_value, timestamp} -> timestamp >= cutoff_time end)
      {resource_type, cleaned_data}
    end)
  end

  # JSON serialization helpers
  defp serialize_for_json(metrics_map) do
    Enum.into(metrics_map, %{}, fn {key, value} ->
      {key, serialize_metric_data(value)}
    end)
  end

  defp serialize_metric_data(data) when is_map(data) do
    Enum.into(data, %{}, fn {metric_type, metric_values} ->
      {metric_type, serialize_metric_values(metric_values)}
    end)
  end

  defp serialize_metric_data(data) when is_list(data) do
    serialize_metric_values(data)
  end

  defp serialize_metric_values(values) when is_list(values) do
    Enum.map(values, fn
      {value, timestamp} -> %{value: value, timestamp: timestamp}
      other -> other
    end)
  end

  defp serialize_coordination_events_for_json(events_map) do
    Enum.into(events_map, %{}, fn {protocol_id, events} ->
      serialized_events =
        Enum.map(events, fn {event_type, metadata, timestamp} ->
          %{event_type: event_type, metadata: metadata, timestamp: timestamp}
        end)

      {protocol_id, serialized_events}
    end)
  end
end
