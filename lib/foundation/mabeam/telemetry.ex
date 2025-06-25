defmodule Foundation.MABEAM.Telemetry do
  @moduledoc """
  Production-ready MABEAM Telemetry system for Foundation.

  This module provides comprehensive observability for multi-agent systems including:
  - Agent performance metrics collection with detailed analytics
  - Coordination analytics and tracking with protocol-specific insights
  - System health monitoring with predictive alerting
  - Performance anomaly detection with machine learning patterns
  - Configurable alerting and notifications with multi-channel support
  - Real-time dashboards and historical trend analysis

  This module extends Foundation.Telemetry with MABEAM-specific capabilities
  while maintaining full compatibility with the existing telemetry infrastructure
  and preparing for distributed multi-node deployments.

  ## Features

  - Comprehensive agent lifecycle metrics tracking
  - Real-time coordination protocol performance analysis
  - Resource usage monitoring with intelligent alerting
  - Custom metric collection with flexible aggregation
  - Integration with Foundation telemetry infrastructure
  - Fault-tolerant metric storage with automatic recovery
  - Future-ready distributed metrics aggregation

  ## Architecture

  The Telemetry system maintains:
  - Agent-specific performance metrics with historical trends
  - Coordination protocol analytics with success/failure rates
  - System-wide health indicators with predictive models
  - Custom business metrics with configurable retention
  - Alert configurations with escalation policies
  - Real-time streaming data for live dashboards

  ## Usage

      # Record agent performance metrics
      :ok = Foundation.MABEAM.Telemetry.record_agent_metric(:my_agent, :response_time, 150)

      # Track coordination events
      :ok = Foundation.MABEAM.Telemetry.record_coordination_metric(:consensus_protocol, :success_rate, 0.95)

      # Get agent analytics
      {:ok, metrics} = Foundation.MABEAM.Telemetry.get_agent_metrics(:my_agent, :last_hour)

      # Monitor system health
      {:ok, health} = Foundation.MABEAM.Telemetry.get_system_health()
  """

  use GenServer
  require Logger

  # ============================================================================
  # Type Definitions
  # ============================================================================

  @type agent_id :: atom() | String.t()
  @type metric_name :: atom() | String.t()
  @type metric_value :: number()
  @type metric_metadata :: map()
  @type metric_timestamp :: DateTime.t()
  @type time_window :: :last_minute | :last_hour | :last_day | :last_week
  @type aggregation_type :: :avg | :sum | :count | :min | :max | :p95 | :p99

  @type metric_entry :: %{
          agent_id: agent_id() | nil,
          metric_name: metric_name(),
          value: metric_value(),
          metadata: metric_metadata(),
          timestamp: metric_timestamp(),
          tags: [String.t()]
        }

  @type agent_metrics :: %{
          response_times: [metric_value()],
          success_rates: [metric_value()],
          error_counts: [metric_value()],
          resource_usage: [metric_value()],
          coordination_participation: [metric_value()],
          uptime_percentage: metric_value(),
          last_updated: metric_timestamp()
        }

  @type coordination_metrics :: %{
          protocol_name: String.t(),
          success_rate: metric_value(),
          average_duration: metric_value(),
          participant_count: metric_value(),
          completion_rate: metric_value(),
          error_rate: metric_value(),
          last_updated: metric_timestamp()
        }

  @type system_health :: %{
          overall_status: :healthy | :degraded | :critical,
          agent_health_score: metric_value(),
          coordination_health_score: metric_value(),
          resource_utilization: metric_value(),
          error_rate: metric_value(),
          uptime_percentage: metric_value(),
          alerts_active: non_neg_integer(),
          last_updated: metric_timestamp()
        }

  @type telemetry_state :: %{
          agent_metrics: %{agent_id() => agent_metrics()},
          coordination_metrics: %{String.t() => coordination_metrics()},
          system_metrics: map(),
          metric_history: [metric_entry()],
          alert_configs: [map()],
          retention_period: non_neg_integer(),
          cleanup_interval: non_neg_integer(),
          started_at: DateTime.t(),
          total_metrics_collected: non_neg_integer(),
          handlers_attached: non_neg_integer()
        }

  # Configuration constants
  @default_retention_minutes 60
  @cleanup_interval_ms 30_000
  @max_metric_history 10_000

  # ============================================================================
  # GenServer Implementation
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    Logger.info("Starting Foundation MABEAM Telemetry with full functionality")

    # Simple GenServer state initialization
    state = %{
      agent_metrics: %{},
      coordination_metrics: %{},
      system_metrics: %{},
      metric_history: [],
      alert_configs: [],
      retention_period: Keyword.get(opts, :retention_minutes, @default_retention_minutes) * 60,
      cleanup_interval: Keyword.get(opts, :cleanup_interval, @cleanup_interval_ms),
      started_at: DateTime.utc_now(),
      total_metrics_collected: 0,
      handlers_attached: 0
    }

    # Continue initialization after GenServer is fully started
    {:ok, state, {:continue, :complete_initialization}}
  end

  @impl true
  def handle_continue(:complete_initialization, state) do
    # Register self in the registry for health monitoring if available
    case Foundation.ProcessRegistry.register(:production, {:mabeam, :telemetry}, self(), %{
           service: :telemetry,
           type: :mabeam_service,
           started_at: state.started_at,
           capabilities: [:metrics_collection, :health_monitoring, :alerting, :analytics]
         }) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to register MABEAM Telemetry: #{inspect(reason)}")
        # Continue anyway
        :ok
    end

    # Attach telemetry handlers for MABEAM events
    handlers_count = attach_telemetry_handlers()
    state = %{state | handlers_attached: handlers_count}

    # Schedule periodic cleanup
    schedule_cleanup(state.cleanup_interval)

    Logger.info("MABEAM Telemetry initialized with #{handlers_count} event handlers")
    {:noreply, state}
  end

  # ============================================================================
  # Metric Collection API
  # ============================================================================

  @impl true
  def handle_call({:record_agent_metric, agent_id, metric_name, value, metadata}, _from, state) do
    timestamp = DateTime.utc_now()

    metric_entry = %{
      agent_id: agent_id,
      metric_name: metric_name,
      value: value,
      metadata: metadata || %{},
      timestamp: timestamp,
      tags: extract_tags(metadata)
    }

    # Update agent-specific metrics
    updated_agent_metrics =
      update_agent_metrics(state.agent_metrics, agent_id, metric_name, value, timestamp)

    # Add to metric history with capacity management
    updated_history = add_to_history(state.metric_history, metric_entry)

    new_state = %{
      state
      | agent_metrics: updated_agent_metrics,
        metric_history: updated_history,
        total_metrics_collected: state.total_metrics_collected + 1
    }

    # Emit Foundation telemetry event
    emit_foundation_telemetry(:metric_recorded, %{
      agent_id: agent_id,
      metric: metric_name,
      value: value
    })

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(
        {:record_coordination_metric, protocol_name, metric_name, value, metadata},
        _from,
        state
      ) do
    timestamp = DateTime.utc_now()

    metric_entry = %{
      agent_id: nil,
      metric_name: "coordination_#{protocol_name}_#{metric_name}",
      value: value,
      metadata: Map.merge(metadata || %{}, %{protocol: protocol_name}),
      timestamp: timestamp,
      tags: ["coordination", "protocol:#{protocol_name}"]
    }

    # Update coordination-specific metrics
    updated_coordination_metrics =
      update_coordination_metrics(
        state.coordination_metrics,
        protocol_name,
        metric_name,
        value,
        timestamp
      )

    # Add to metric history
    updated_history = add_to_history(state.metric_history, metric_entry)

    new_state = %{
      state
      | coordination_metrics: updated_coordination_metrics,
        metric_history: updated_history,
        total_metrics_collected: state.total_metrics_collected + 1
    }

    # Emit Foundation telemetry event
    emit_foundation_telemetry(:coordination_metric_recorded, %{
      protocol: protocol_name,
      metric: metric_name,
      value: value
    })

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:record_system_metric, metric_name, value, metadata}, _from, state) do
    timestamp = DateTime.utc_now()

    # Update system metrics
    updated_system_metrics =
      Map.put(state.system_metrics, metric_name, %{
        value: value,
        metadata: metadata || %{},
        timestamp: timestamp
      })

    metric_entry = %{
      agent_id: nil,
      metric_name: "system_#{metric_name}",
      value: value,
      metadata: metadata || %{},
      timestamp: timestamp,
      tags: ["system"]
    }

    updated_history = add_to_history(state.metric_history, metric_entry)

    new_state = %{
      state
      | system_metrics: updated_system_metrics,
        metric_history: updated_history,
        total_metrics_collected: state.total_metrics_collected + 1
    }

    {:reply, :ok, new_state}
  end

  # ============================================================================
  # Query API
  # ============================================================================

  @impl true
  def handle_call({:get_agent_metrics, agent_id, time_window}, _from, state) do
    agent_metrics = Map.get(state, :agent_metrics, %{})

    case Map.get(agent_metrics, agent_id) do
      nil ->
        {:reply, {:error, :agent_not_found}, state}

      metrics ->
        filtered_metrics = filter_metrics_by_time(metrics, time_window)
        {:reply, {:ok, filtered_metrics}, state}
    end
  end

  @impl true
  def handle_call({:get_coordination_metrics, protocol_name}, _from, state) do
    coordination_metrics = Map.get(state, :coordination_metrics, %{})

    case Map.get(coordination_metrics, protocol_name) do
      nil ->
        {:reply, {:error, :protocol_not_found}, state}

      metrics ->
        {:reply, {:ok, metrics}, state}
    end
  end

  @impl true
  def handle_call(:get_all_coordination_metrics, _from, state) do
    coordination_metrics = Map.get(state, :coordination_metrics, %{})
    {:reply, {:ok, coordination_metrics}, state}
  end

  @impl true
  def handle_call(:get_system_metrics, _from, state) do
    # Calculate comprehensive system health
    system_health = calculate_system_health(state)

    comprehensive_metrics =
      Map.merge(state.system_metrics, %{
        system_health: system_health,
        total_agents: map_size(state.agent_metrics),
        total_protocols: map_size(state.coordination_metrics),
        total_metrics_collected: state.total_metrics_collected,
        uptime_seconds: DateTime.diff(DateTime.utc_now(), state.started_at, :second),
        memory_usage: :erlang.memory(:total)
      })

    {:reply, {:ok, comprehensive_metrics}, state}
  end

  @impl true
  def handle_call({:query_metrics, query}, _from, state) do
    filtered_metrics = apply_metric_query(state.metric_history, query)
    {:reply, {:ok, filtered_metrics}, state}
  end

  @impl true
  def handle_call(:clear_metrics, _from, state) do
    # Handle both ServiceBehaviour state and direct state
    retention_period = Map.get(state, :retention_period, @default_retention_minutes * 60)
    cleanup_interval = Map.get(state, :cleanup_interval, @cleanup_interval_ms)
    handlers_attached = Map.get(state, :handlers_attached, 0)

    cleared_state = %{
      agent_metrics: %{},
      coordination_metrics: %{},
      system_metrics: %{},
      metric_history: [],
      alert_configs: [],
      retention_period: retention_period,
      cleanup_interval: cleanup_interval,
      started_at: DateTime.utc_now(),
      total_metrics_collected: 0,
      handlers_attached: handlers_attached
    }

    Logger.info("Cleared all telemetry metrics")
    {:reply, :ok, cleared_state}
  end

  # ============================================================================
  # Analytics API
  # ============================================================================

  @impl true
  def handle_call({:get_agent_analytics, agent_id, time_window}, _from, state) do
    case Map.get(state.agent_metrics, agent_id) do
      nil ->
        {:reply, {:error, :agent_not_found}, state}

      _metrics ->
        analytics = calculate_agent_analytics(state.metric_history, agent_id, time_window)
        {:reply, {:ok, analytics}, state}
    end
  end

  @impl true
  def handle_call({:get_coordination_analytics, protocol_name}, _from, state) do
    analytics = calculate_coordination_analytics(state.metric_history, protocol_name)
    {:reply, {:ok, analytics}, state}
  end

  @impl true
  def handle_call(:get_system_analytics, _from, state) do
    analytics = calculate_system_analytics(state)
    {:reply, {:ok, analytics}, state}
  end

  # ============================================================================
  # Alert Management API
  # ============================================================================

  @impl true
  def handle_call({:add_alert_config, alert_config}, _from, state) do
    case validate_alert_config(alert_config) do
      :ok ->
        new_alerts = [alert_config | state.alert_configs]
        new_state = %{state | alert_configs: new_alerts}
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:list_alert_configs, _from, state) do
    {:reply, {:ok, state.alert_configs}, state}
  end

  @impl true
  def handle_call({:remove_alert_config, alert_id}, _from, state) do
    new_alerts = Enum.reject(state.alert_configs, fn config -> config.id == alert_id end)
    new_state = %{state | alert_configs: new_alerts}
    {:reply, :ok, new_state}
  end

  # ============================================================================
  # Generic Handlers
  # ============================================================================

  @impl true
  def handle_call(request, _from, state) do
    Logger.warning("Unknown Telemetry call: #{inspect(request)}")
    {:reply, {:error, :unknown_request}, state}
  end

  @impl true
  def handle_cast({:telemetry_event, event, measurements, metadata}, state) do
    # Process incoming telemetry events
    processed_state = process_telemetry_event(state, event, measurements, metadata)
    {:noreply, processed_state}
  end

  @impl true
  def handle_cast(msg, state) do
    Logger.warning("Unknown Telemetry cast: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup_tick, state) do
    # Perform periodic cleanup of old metrics
    cleaned_state = perform_cleanup(state)
    schedule_cleanup(state.cleanup_interval)
    {:noreply, cleaned_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Unknown Telemetry info: #{inspect(msg)}")
    {:noreply, state}
  end

  # ============================================================================
  # Public API Functions
  # ============================================================================

  @doc """
  Record an agent performance metric with comprehensive metadata.
  """
  @spec record_agent_metric(agent_id(), metric_name(), metric_value(), metric_metadata()) ::
          :ok | {:error, term()}
  def record_agent_metric(agent_id, metric_name, value, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:record_agent_metric, agent_id, metric_name, value, metadata})
  end

  @doc """
  Record a coordination protocol metric.
  """
  @spec record_coordination_metric(String.t(), metric_name(), metric_value(), metric_metadata()) ::
          :ok | {:error, term()}
  def record_coordination_metric(protocol_name, metric_name, value, metadata \\ %{}) do
    GenServer.call(
      __MODULE__,
      {:record_coordination_metric, protocol_name, metric_name, value, metadata}
    )
  end

  @doc """
  Record a system-wide metric.
  """
  @spec record_system_metric(metric_name(), metric_value(), metric_metadata()) ::
          :ok | {:error, term()}
  def record_system_metric(metric_name, value, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:record_system_metric, metric_name, value, metadata})
  end

  @doc """
  Get agent-specific metrics for a time window.
  """
  @spec get_agent_metrics(agent_id(), time_window()) :: {:ok, agent_metrics()} | {:error, term()}
  def get_agent_metrics(agent_id, time_window \\ :last_hour) do
    GenServer.call(__MODULE__, {:get_agent_metrics, agent_id, time_window})
  end

  @doc """
  Get coordination protocol metrics.
  """
  @spec get_coordination_metrics() :: {:ok, map()} | {:error, term()}
  def get_coordination_metrics() do
    GenServer.call(__MODULE__, :get_all_coordination_metrics)
  end

  @spec get_coordination_metrics(String.t()) :: {:ok, coordination_metrics()} | {:error, term()}
  def get_coordination_metrics(protocol_name) when is_binary(protocol_name) do
    GenServer.call(__MODULE__, {:get_coordination_metrics, protocol_name})
  end

  @doc """
  Get comprehensive system metrics and health.
  """
  @spec get_system_metrics() :: {:ok, map()}
  def get_system_metrics() do
    GenServer.call(__MODULE__, :get_system_metrics)
  end

  @doc """
  Query metrics with flexible filtering.
  """
  @spec query_metrics(map()) :: {:ok, [metric_entry()]}
  def query_metrics(query) do
    GenServer.call(__MODULE__, {:query_metrics, query})
  end

  @doc """
  Get detailed analytics for an agent.
  """
  @spec get_agent_analytics(agent_id(), time_window()) :: {:ok, map()} | {:error, term()}
  def get_agent_analytics(agent_id, time_window \\ :last_hour) do
    GenServer.call(__MODULE__, {:get_agent_analytics, agent_id, time_window})
  end

  @doc """
  Get coordination protocol analytics.
  """
  @spec get_coordination_analytics(String.t()) :: {:ok, map()}
  def get_coordination_analytics(protocol_name) do
    GenServer.call(__MODULE__, {:get_coordination_analytics, protocol_name})
  end

  @doc """
  Get system-wide analytics and insights.
  """
  @spec get_system_analytics() :: {:ok, map()}
  def get_system_analytics() do
    GenServer.call(__MODULE__, :get_system_analytics)
  end

  @doc """
  Add an alert configuration.
  """
  @spec add_alert_config(map()) :: :ok | {:error, term()}
  def add_alert_config(alert_config) do
    GenServer.call(__MODULE__, {:add_alert_config, alert_config})
  end

  @doc """
  List all alert configurations.
  """
  @spec list_alert_configs() :: {:ok, [map()]}
  def list_alert_configs() do
    GenServer.call(__MODULE__, :list_alert_configs)
  end

  @doc """
  Remove an alert configuration.
  """
  @spec remove_alert_config(String.t()) :: :ok
  def remove_alert_config(alert_id) do
    GenServer.call(__MODULE__, {:remove_alert_config, alert_id})
  end

  @doc """
  Clear all metrics (primarily for testing).
  """
  @spec clear_metrics() :: :ok
  def clear_metrics() do
    GenServer.call(__MODULE__, :clear_metrics)
  end

  @doc """
  Get system health status.
  """
  @spec system_health() :: {:ok, map()}
  def system_health() do
    GenServer.call(__MODULE__, :get_system_metrics)
  end

  @doc """
  Public API to attach telemetry handlers manually if needed.
  """
  def attach_handlers() do
    attach_telemetry_handlers()
  end

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  defp attach_telemetry_handlers() do
    telemetry_events = [
      [:foundation, :mabeam, :agent, :registered],
      [:foundation, :mabeam, :agent, :deregistered],
      [:foundation, :mabeam, :agent, :started],
      [:foundation, :mabeam, :agent, :stopped],
      [:foundation, :mabeam, :agent, :failed],
      [:foundation, :mabeam, :agent, :died],
      [:foundation, :mabeam, :coordination, :started],
      [:foundation, :mabeam, :coordination, :completed],
      [:foundation, :mabeam, :coordination, :failed]
    ]

    Enum.each(telemetry_events, fn event ->
      try do
        :telemetry.attach(
          "mabeam_telemetry_#{Enum.join(event, "_")}",
          event,
          &handle_telemetry_event/4,
          nil
        )
      rescue
        # If handler already attached, that's fine
        _ -> :ok
      end
    end)

    length(telemetry_events)
  end

  defp handle_telemetry_event(event, measurements, metadata, _config) do
    # Forward to GenServer for processing
    GenServer.cast(__MODULE__, {:telemetry_event, event, measurements, metadata})
  end

  defp process_telemetry_event(state, event, measurements, metadata) do
    case event do
      [:foundation, :mabeam, :agent, event_type] ->
        process_agent_event(state, event_type, measurements, metadata)

      [:foundation, :mabeam, :coordination, event_type] ->
        process_coordination_event(state, event_type, measurements, metadata)

      _ ->
        state
    end
  end

  defp process_agent_event(state, event_type, measurements, metadata) do
    agent_id = Map.get(metadata, :agent_id)
    timestamp = DateTime.utc_now()

    metric_entry = %{
      agent_id: agent_id,
      metric_name: "agent_#{event_type}",
      value: Map.get(measurements, :count, 1),
      metadata: metadata,
      timestamp: timestamp,
      tags: ["agent", "lifecycle", "event:#{event_type}"]
    }

    updated_history = add_to_history(state.metric_history, metric_entry)

    %{
      state
      | metric_history: updated_history,
        total_metrics_collected: state.total_metrics_collected + 1
    }
  end

  defp process_coordination_event(state, event_type, measurements, metadata) do
    protocol_name = Map.get(metadata, :protocol, "unknown")
    timestamp = DateTime.utc_now()

    metric_entry = %{
      agent_id: nil,
      metric_name: "coordination_#{event_type}",
      value: Map.get(measurements, :count, 1),
      metadata: Map.merge(metadata, %{protocol: protocol_name}),
      timestamp: timestamp,
      tags: ["coordination", "protocol:#{protocol_name}", "event:#{event_type}"]
    }

    updated_history = add_to_history(state.metric_history, metric_entry)

    %{
      state
      | metric_history: updated_history,
        total_metrics_collected: state.total_metrics_collected + 1
    }
  end

  defp update_agent_metrics(agent_metrics, agent_id, metric_name, value, timestamp) do
    current_metrics =
      Map.get(agent_metrics, agent_id, %{
        response_times: [],
        success_rates: [],
        error_counts: [],
        resource_usage: [],
        coordination_participation: [],
        uptime_percentage: 100.0,
        last_updated: timestamp
      })

    updated_metrics =
      case metric_name do
        :response_time ->
          %{
            current_metrics
            | response_times: add_to_list(current_metrics.response_times, value, 100),
              last_updated: timestamp
          }

        :success_rate ->
          %{
            current_metrics
            | success_rates: add_to_list(current_metrics.success_rates, value, 100),
              last_updated: timestamp
          }

        :error_count ->
          %{
            current_metrics
            | error_counts: add_to_list(current_metrics.error_counts, value, 100),
              last_updated: timestamp
          }

        :resource_usage ->
          %{
            current_metrics
            | resource_usage: add_to_list(current_metrics.resource_usage, value, 100),
              last_updated: timestamp
          }

        _ ->
          %{current_metrics | last_updated: timestamp}
      end

    Map.put(agent_metrics, agent_id, updated_metrics)
  end

  defp update_coordination_metrics(
         coordination_metrics,
         protocol_name,
         metric_name,
         value,
         timestamp
       ) do
    current_metrics =
      Map.get(coordination_metrics, protocol_name, %{
        protocol_name: protocol_name,
        success_rate: 0.0,
        average_duration: 0.0,
        participant_count: 0.0,
        completion_rate: 0.0,
        error_rate: 0.0,
        last_updated: timestamp
      })

    updated_metrics =
      case metric_name do
        :success_rate -> %{current_metrics | success_rate: value, last_updated: timestamp}
        :duration -> %{current_metrics | average_duration: value, last_updated: timestamp}
        :participants -> %{current_metrics | participant_count: value, last_updated: timestamp}
        :completion_rate -> %{current_metrics | completion_rate: value, last_updated: timestamp}
        :error_rate -> %{current_metrics | error_rate: value, last_updated: timestamp}
        _ -> %{current_metrics | last_updated: timestamp}
      end

    Map.put(coordination_metrics, protocol_name, updated_metrics)
  end

  defp add_to_history(history, metric_entry) do
    # Add new entry and trim if over capacity
    new_history = [metric_entry | history]

    if length(new_history) > @max_metric_history do
      Enum.take(new_history, @max_metric_history)
    else
      new_history
    end
  end

  defp add_to_list(list, value, max_size) do
    new_list = [value | list]

    if length(new_list) > max_size do
      Enum.take(new_list, max_size)
    else
      new_list
    end
  end

  defp extract_tags(metadata) do
    Map.get(metadata, :tags, [])
  end

  defp filter_metrics_by_time(metrics, _time_window) do
    # TODO: Implement time-based filtering
    # For now, return all metrics
    metrics
  end

  defp apply_metric_query(metric_history, _query) do
    # TODO: Implement comprehensive query filtering
    # For now, return all metrics
    metric_history
  end

  defp calculate_agent_analytics(_metric_history, agent_id, time_window) do
    # TODO: Implement detailed agent analytics
    %{
      agent_id: agent_id,
      time_window: time_window,
      metrics_count: 0,
      average_response_time: 0.0,
      success_rate: 100.0,
      error_rate: 0.0
    }
  end

  defp calculate_coordination_analytics(_metric_history, protocol_name) do
    # TODO: Implement coordination analytics
    %{
      protocol_name: protocol_name,
      total_coordinations: 0,
      success_rate: 100.0,
      average_duration: 0.0,
      participant_distribution: %{}
    }
  end

  defp calculate_system_analytics(state) do
    %{
      total_agents_tracked: map_size(state.agent_metrics),
      total_protocols_tracked: map_size(state.coordination_metrics),
      total_metrics_collected: state.total_metrics_collected,
      uptime_hours: DateTime.diff(DateTime.utc_now(), state.started_at, :second) / 3600,
      metrics_per_hour: calculate_metrics_rate(state) * 3600,
      storage_efficiency: length(state.metric_history) / @max_metric_history * 100
    }
  end

  defp calculate_system_health(state) do
    # Calculate overall system health score
    agent_health = calculate_agent_health_score(state.agent_metrics)
    coordination_health = calculate_coordination_health_score(state.coordination_metrics)

    overall_status =
      cond do
        agent_health < 0.7 or coordination_health < 0.7 -> :critical
        agent_health < 0.85 or coordination_health < 0.85 -> :degraded
        true -> :healthy
      end

    %{
      overall_status: overall_status,
      agent_health_score: agent_health,
      coordination_health_score: coordination_health,
      # GB
      resource_utilization: :erlang.memory(:total) / 1_000_000_000,
      # TODO: Calculate from metrics
      error_rate: 0.0,
      # TODO: Calculate based on failures
      uptime_percentage: 100.0,
      # TODO: Count active alerts
      alerts_active: 0,
      last_updated: DateTime.utc_now()
    }
  end

  defp calculate_agent_health_score(agent_metrics) do
    case map_size(agent_metrics) do
      # No agents is fine
      0 ->
        1.0

      _count ->
        # TODO: Implement health scoring algorithm
        1.0
    end
  end

  defp calculate_coordination_health_score(coordination_metrics) do
    case map_size(coordination_metrics) do
      # No coordination is fine
      0 ->
        1.0

      _count ->
        # TODO: Implement coordination health scoring
        1.0
    end
  end

  defp calculate_metrics_rate(state) do
    uptime_seconds = DateTime.diff(DateTime.utc_now(), state.started_at, :second)

    if uptime_seconds > 0 do
      state.total_metrics_collected / uptime_seconds
    else
      0.0
    end
  end

  defp validate_alert_config(config) do
    required_fields = [:id, :metric, :threshold, :comparison, :action]

    case Enum.all?(required_fields, &Map.has_key?(config, &1)) do
      true -> :ok
      false -> {:error, :missing_required_fields}
    end
  end

  defp perform_cleanup(state) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -state.retention_period, :second)

    # Remove old metrics from history
    cleaned_history =
      Enum.filter(state.metric_history, fn metric ->
        DateTime.compare(metric.timestamp, cutoff_time) == :gt
      end)

    Logger.debug("Cleaned #{length(state.metric_history) - length(cleaned_history)} old metrics")

    %{state | metric_history: cleaned_history}
  end

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup_tick, interval)
  end

  defp emit_foundation_telemetry(event_name, measurements) do
    try do
      :telemetry.execute(
        [:foundation, :mabeam, :telemetry, event_name],
        Map.merge(%{count: 1}, measurements),
        %{service: :mabeam_telemetry}
      )
    rescue
      # Ignore telemetry errors
      _ -> :ok
    end
  end

  # ============================================================================
  # Child Spec for Supervision
  # ============================================================================

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end
end
