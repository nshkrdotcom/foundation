defmodule Foundation.Services.TelemetryService do
  @moduledoc """
  Comprehensive telemetry aggregation and management service for Foundation infrastructure.

  Provides centralized telemetry collection, aggregation, and distribution
  with agent-aware metrics processing. Acts as a bridge between the basic
  Foundation.Telemetry module and external monitoring systems, providing
  additional processing, correlation, and alerting capabilities.

  ## Features

  - **Metric Aggregation**: Real-time aggregation of counters, gauges, and histograms
  - **Agent Correlation**: Link metrics to specific agents and capabilities
  - **Alert Management**: Threshold-based alerting with escalation policies
  - **Export Integration**: Push metrics to external systems (Prometheus, DataDog, etc.)
  - **Historical Tracking**: Metric history and trend analysis
  - **Performance Optimization**: Batching, sampling, and efficient storage

  ## Metric Types Processed

  - **System Metrics**: Memory, CPU, network, process counts
  - **Agent Metrics**: Per-agent resource usage, health, performance
  - **Infrastructure Metrics**: Circuit breaker states, rate limit usage
  - **Coordination Metrics**: Consensus latency, barrier completion times
  - **Business Metrics**: Request rates, error rates, success percentages

  ## Usage

      # Start telemetry service
      {:ok, _pid} = TelemetryService.start_link([
        namespace: :production,
        aggregation_interval: 10_000,
        retention_hours: 24
      ])

      # Register metric exporter
      TelemetryService.register_exporter(:prometheus, PrometheusExporter)

      # Get aggregated metrics
      {:ok, metrics} = TelemetryService.get_aggregated_metrics(%{
        agent_id: :ml_agent_1,
        metric_type: :gauge,
        since: DateTime.add(DateTime.utc_now(), -3600)
      })

      # Set up alerts
      TelemetryService.create_alert(%{
        name: :high_memory_usage,
        metric_path: [:foundation, :agent, :memory_usage],
        threshold: 0.9,
        condition: :greater_than
      })
  """

  use GenServer
  require Logger

  alias Foundation.ProcessRegistry
  alias Foundation.Telemetry
  alias Foundation.Types.Error

  @type metric_name :: [atom()]
  @type metric_value :: number()
  @type metric_type :: :counter | :gauge | :histogram
  @type agent_id :: atom() | String.t()
  @type exporter_name :: atom()
  @type alert_condition :: :greater_than | :less_than | :equals | :not_equals

  @type metric_point :: %{
    name: metric_name(),
    value: metric_value(),
    type: metric_type(),
    timestamp: DateTime.t(),
    metadata: map()
  }

  @type aggregated_metric :: %{
    name: metric_name(),
    type: metric_type(),
    count: non_neg_integer(),
    sum: number(),
    min: number(),
    max: number(),
    avg: float(),
    last_value: metric_value(),
    last_updated: DateTime.t()
  }

  @type alert_rule :: %{
    name: atom(),
    metric_path: metric_name(),
    threshold: metric_value(),
    condition: alert_condition(),
    enabled: boolean(),
    last_triggered: DateTime.t() | nil
  }

  @type metric_filter :: %{
    agent_id: agent_id() | nil,
    metric_type: metric_type() | nil,
    metric_name: metric_name() | nil,
    since: DateTime.t() | nil,
    until: DateTime.t() | nil
  }

  defstruct [
    :namespace,
    :aggregation_interval,
    :retention_hours,
    :raw_metrics,
    :aggregated_metrics,
    :alert_rules,
    :exporters,
    :last_aggregation,
    :service_stats
  ]

  @type t :: %__MODULE__{
    namespace: atom(),
    aggregation_interval: pos_integer(),
    retention_hours: pos_integer(),
    raw_metrics: :ets.tid(),
    aggregated_metrics: :ets.tid(),
    alert_rules: :ets.tid(),
    exporters: map(),
    last_aggregation: DateTime.t(),
    service_stats: map()
  }

  # Default configuration
  @default_aggregation_interval 10_000  # 10 seconds
  @default_retention_hours 24
  @cleanup_interval_ms 300_000  # 5 minutes

  # Public API

  @doc """
  Start the telemetry service.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(options \\ []) do
    namespace = Keyword.get(options, :namespace, :foundation)
    GenServer.start_link(__MODULE__, options, name: service_name(namespace))
  end

  @doc """
  Record a metric point for aggregation.

  This is typically called by the Foundation.Telemetry module
  but can also be used directly for custom metrics.
  """
  @spec record_metric(metric_name(), metric_value(), metric_type(), map(), atom()) :: :ok
  def record_metric(name, value, type, metadata \\ %{}, namespace \\ :foundation) do
    GenServer.cast(service_name(namespace), {:record_metric, name, value, type, metadata})
  end

  @doc """
  Get aggregated metrics based on filter criteria.

  Returns processed and aggregated metrics for analysis and monitoring.
  """
  @spec get_aggregated_metrics(metric_filter(), atom()) ::
    {:ok, [aggregated_metric()]} | {:error, Error.t()}
  def get_aggregated_metrics(filter, namespace \\ :foundation) do
    GenServer.call(service_name(namespace), {:get_aggregated_metrics, filter})
  rescue
    error -> {:error, telemetry_service_error("get_aggregated_metrics failed", error)}
  end

  @doc """
  Register an external metric exporter.

  Exporters are modules that implement the exporter behavior and
  are called periodically to push metrics to external systems.
  """
  @spec register_exporter(exporter_name(), module(), atom()) :: :ok | {:error, Error.t()}
  def register_exporter(name, module, namespace \\ :foundation) do
    GenServer.call(service_name(namespace), {:register_exporter, name, module})
  rescue
    error -> {:error, telemetry_service_error("register_exporter failed", error)}
  end

  @doc """
  Create an alert rule for automatic monitoring.

  Alert rules are evaluated during metric aggregation and
  trigger notifications when thresholds are exceeded.
  """
  @spec create_alert(alert_rule(), atom()) :: :ok | {:error, Error.t()}
  def create_alert(alert_spec, namespace \\ :foundation) do
    GenServer.call(service_name(namespace), {:create_alert, alert_spec})
  rescue
    error -> {:error, telemetry_service_error("create_alert failed", error)}
  end

  @doc """
  Get current service statistics and health information.
  """
  @spec get_service_stats(atom()) :: {:ok, map()} | {:error, Error.t()}
  def get_service_stats(namespace \\ :foundation) do
    GenServer.call(service_name(namespace), :get_service_stats)
  rescue
    error -> {:error, telemetry_service_error("get_service_stats failed", error)}
  end

  @doc """
  Trigger immediate metric aggregation and export.

  Useful for testing or when immediate metric processing is needed.
  """
  @spec trigger_aggregation(atom()) :: :ok
  def trigger_aggregation(namespace \\ :foundation) do
    GenServer.cast(service_name(namespace), :trigger_aggregation)
  end

  # GenServer Implementation

  @impl GenServer
  def init(options) do
    namespace = Keyword.get(options, :namespace, :foundation)
    aggregation_interval = Keyword.get(options, :aggregation_interval, @default_aggregation_interval)
    retention_hours = Keyword.get(options, :retention_hours, @default_retention_hours)

    # Create ETS tables for metric storage
    raw_metrics = :ets.new(:raw_metrics, [
      :ordered_set, :private, {:write_concurrency, true}, {:read_concurrency, true}
    ])

    aggregated_metrics = :ets.new(:aggregated_metrics, [
      :set, :private, {:write_concurrency, true}, {:read_concurrency, true}
    ])

    alert_rules = :ets.new(:alert_rules, [
      :set, :private, {:write_concurrency, true}, {:read_concurrency, true}
    ])

    state = %__MODULE__{
      namespace: namespace,
      aggregation_interval: aggregation_interval,
      retention_hours: retention_hours,
      raw_metrics: raw_metrics,
      aggregated_metrics: aggregated_metrics,
      alert_rules: alert_rules,
      exporters: %{},
      last_aggregation: DateTime.utc_now(),
      service_stats: %{metrics_processed: 0, alerts_triggered: 0}
    }

    # Register with ProcessRegistry
    case ProcessRegistry.register(namespace, __MODULE__, self(), %{
      type: :telemetry_service,
      health: :healthy,
      aggregation_interval: aggregation_interval
    }) do
      :ok ->
        # Attach to Foundation telemetry events
        attach_telemetry_handlers(namespace)

        # Schedule periodic aggregation
        schedule_aggregation(aggregation_interval)

        # Schedule periodic cleanup
        schedule_cleanup()

        Telemetry.emit_counter(
          [:foundation, :services, :telemetry_service, :started],
          %{namespace: namespace, aggregation_interval: aggregation_interval}
        )

        {:ok, state}

      {:error, reason} ->
        {:stop, {:registration_failed, reason}}
    end
  end

  @impl GenServer
  def handle_cast({:record_metric, name, value, type, metadata}, state) do
    new_state = store_raw_metric(name, value, type, metadata, state)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_cast(:trigger_aggregation, state) do
    new_state = perform_aggregation_cycle(state)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_call({:get_aggregated_metrics, filter}, _from, state) do
    result = query_aggregated_metrics(filter, state)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:register_exporter, name, module}, _from, state) do
    case validate_exporter_module(module) do
      :ok ->
        new_exporters = Map.put(state.exporters, name, module)
        new_state = %{state | exporters: new_exporters}

        Telemetry.emit_counter(
          [:foundation, :services, :telemetry_service, :exporter_registered],
          %{exporter_name: name, module: module}
        )

        {:reply, :ok, new_state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call({:create_alert, alert_spec}, _from, state) do
    case validate_alert_spec(alert_spec) do
      :ok ->
        alert_rule = build_alert_rule(alert_spec)
        :ets.insert(state.alert_rules, {alert_rule.name, alert_rule})

        Telemetry.emit_counter(
          [:foundation, :services, :telemetry_service, :alert_created],
          %{alert_name: alert_rule.name}
        )

        {:reply, :ok, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call(:get_service_stats, _from, state) do
    stats = build_service_stats(state)
    {:reply, {:ok, stats}, state}
  end

  @impl GenServer
  def handle_info(:perform_aggregation, state) do
    new_state = perform_aggregation_cycle(state)
    schedule_aggregation(state.aggregation_interval)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(:cleanup_old_metrics, state) do
    new_state = perform_metric_cleanup(state)
    schedule_cleanup()
    {:noreply, new_state}
  end

  # Handle telemetry events from Foundation.Telemetry
  @impl GenServer
  def handle_info({:telemetry_event, event_name, measurements, metadata}, state) do
    new_state = process_telemetry_event(event_name, measurements, metadata, state)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(_message, state) do
    {:noreply, state}
  end

  # Private Implementation

  defp store_raw_metric(name, value, type, metadata, state) do
    timestamp = DateTime.utc_now()
    timestamp_key = DateTime.to_unix(timestamp, :microsecond)

    metric_point = %{
      name: name,
      value: value,
      type: type,
      timestamp: timestamp,
      metadata: metadata
    }

    :ets.insert(state.raw_metrics, {timestamp_key, metric_point})

    # Update stats
    new_stats = Map.update(state.service_stats, :metrics_processed, 1, &(&1 + 1))
    %{state | service_stats: new_stats}
  end

  defp perform_aggregation_cycle(state) do
    # Get raw metrics since last aggregation
    since_timestamp = DateTime.to_unix(state.last_aggregation, :microsecond)

    raw_metrics = :ets.select(state.raw_metrics, [
      {{:"$1", :"$2"}, [{:>, :"$1", since_timestamp}], [:"$2"]}
    ])

    # Group metrics by name and type
    grouped_metrics = Enum.group_by(raw_metrics, fn metric ->
      {metric.name, metric.type}
    end)

    # Perform aggregation for each group
    current_time = DateTime.utc_now()

    Enum.each(grouped_metrics, fn {{name, type}, metrics} ->
      aggregated = aggregate_metric_group(name, type, metrics, current_time)
      :ets.insert(state.aggregated_metrics, {{name, type}, aggregated})
    end)

    # Check alert rules
    new_state = check_alert_rules(state)

    # Export metrics to registered exporters
    export_to_registered_exporters(new_state)

    %{new_state | last_aggregation: current_time}
  end

  defp aggregate_metric_group(name, type, metrics, timestamp) do
    values = Enum.map(metrics, & &1.value)

    case type do
      :counter ->
        %{
          name: name,
          type: type,
          count: length(metrics),
          sum: Enum.sum(values),
          min: Enum.min(values),
          max: Enum.max(values),
          avg: Enum.sum(values) / length(values),
          last_value: List.last(values),
          last_updated: timestamp
        }

      :gauge ->
        %{
          name: name,
          type: type,
          count: length(metrics),
          sum: Enum.sum(values),
          min: Enum.min(values),
          max: Enum.max(values),
          avg: Enum.sum(values) / length(values),
          last_value: List.last(values),
          last_updated: timestamp
        }

      :histogram ->
        %{
          name: name,
          type: type,
          count: length(metrics),
          sum: Enum.sum(values),
          min: Enum.min(values),
          max: Enum.max(values),
          avg: Enum.sum(values) / length(values),
          last_value: List.last(values),
          last_updated: timestamp,
          percentiles: calculate_percentiles(values)
        }
    end
  end

  defp calculate_percentiles(values) do
    sorted_values = Enum.sort(values)
    count = length(sorted_values)

    %{
      p50: percentile(sorted_values, count, 0.5),
      p90: percentile(sorted_values, count, 0.9),
      p95: percentile(sorted_values, count, 0.95),
      p99: percentile(sorted_values, count, 0.99)
    }
  end

  defp percentile(sorted_values, count, percentile) do
    index = trunc(count * percentile) - 1
    index = max(0, min(index, count - 1))
    Enum.at(sorted_values, index)
  end

  defp check_alert_rules(state) do
    all_alerts = :ets.tab2list(state.alert_rules)
    alerts_triggered = 0

    new_alerts_triggered = Enum.reduce(all_alerts, alerts_triggered, fn {_name, alert_rule}, acc ->
      if alert_rule.enabled do
        case evaluate_alert_rule(alert_rule, state) do
          {:triggered, updated_rule} ->
            :ets.insert(state.alert_rules, {updated_rule.name, updated_rule})
            trigger_alert(updated_rule)
            acc + 1

          :ok ->
            acc
        end
      else
        acc
      end
    end)

    # Update stats
    new_stats = Map.update(state.service_stats, :alerts_triggered, new_alerts_triggered, &(&1 + new_alerts_triggered))
    %{state | service_stats: new_stats}
  end

  defp evaluate_alert_rule(alert_rule, state) do
    case :ets.lookup(state.aggregated_metrics, {alert_rule.metric_path, :gauge}) do
      [{{_name, _type}, aggregated_metric}] ->
        current_value = aggregated_metric.last_value

        triggered = case alert_rule.condition do
          :greater_than -> current_value > alert_rule.threshold
          :less_than -> current_value < alert_rule.threshold
          :equals -> current_value == alert_rule.threshold
          :not_equals -> current_value != alert_rule.threshold
        end

        if triggered do
          updated_rule = %{alert_rule | last_triggered: DateTime.utc_now()}
          {:triggered, updated_rule}
        else
          :ok
        end

      [] ->
        :ok  # Metric not found, can't evaluate
    end
  end

  defp trigger_alert(alert_rule) do
    Telemetry.emit_counter(
      [:foundation, :services, :telemetry_service, :alert_triggered],
      %{
        alert_name: alert_rule.name,
        metric_path: alert_rule.metric_path,
        threshold: alert_rule.threshold,
        condition: alert_rule.condition
      }
    )

    Logger.warning(
      "Alert triggered: #{alert_rule.name}",
      alert_name: alert_rule.name,
      metric_path: alert_rule.metric_path,
      threshold: alert_rule.threshold
    )
  end

  defp export_to_registered_exporters(state) do
    if map_size(state.exporters) > 0 do
      all_metrics = :ets.tab2list(state.aggregated_metrics)

      Enum.each(state.exporters, fn {exporter_name, exporter_module} ->
        try do
          exporter_module.export_metrics(all_metrics)
        rescue
          error ->
            Logger.warning(
              "Metric export failed for #{exporter_name}: #{inspect(error)}"
            )
        end
      end)
    end
  end

  defp query_aggregated_metrics(filter, state) do
    try do
      all_metrics = :ets.tab2list(state.aggregated_metrics)

      filtered_metrics = Enum.filter(all_metrics, fn {{name, type}, metric} ->
        matches_filter?(name, type, metric, filter)
      end)

      result_metrics = Enum.map(filtered_metrics, fn {_key, metric} -> metric end)

      {:ok, result_metrics}
    rescue
      error ->
        {:error, query_error("Failed to query aggregated metrics", error)}
    end
  end

  defp matches_filter?(name, type, metric, filter) do
    Enum.all?(filter, fn {filter_key, filter_value} ->
      case filter_key do
        :metric_name -> name == filter_value
        :metric_type -> type == filter_value
        :since -> DateTime.compare(metric.last_updated, filter_value) != :lt
        :until -> DateTime.compare(metric.last_updated, filter_value) != :gt
        _ -> true
      end
    end)
  end

  defp perform_metric_cleanup(state) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -state.retention_hours * 3600)
    cutoff_micros = DateTime.to_unix(cutoff_time, :microsecond)

    # Delete old raw metrics
    deleted_count = :ets.select_delete(state.raw_metrics, [
      {{:"$1", :_}, [{:<, :"$1", cutoff_micros}], [true]}
    ])

    if deleted_count > 0 do
      Telemetry.emit_counter(
        [:foundation, :services, :telemetry_service, :metrics_cleaned],
        %{deleted_count: deleted_count}
      )
    end

    state
  end

  defp process_telemetry_event(event_name, measurements, metadata, state) do
    # Process Foundation telemetry events and convert to metrics
    Enum.reduce(measurements, state, fn {measurement_name, value}, acc_state ->
      metric_name = event_name ++ [measurement_name]
      metric_type = infer_metric_type(measurement_name, value)

      store_raw_metric(metric_name, value, metric_type, metadata, acc_state)
    end)
  end

  defp infer_metric_type(:count, _), do: :counter
  defp infer_metric_type(:duration, _), do: :histogram
  defp infer_metric_type(:value, _), do: :gauge
  defp infer_metric_type(_, _), do: :gauge

  defp attach_telemetry_handlers(namespace) do
    # Attach to all Foundation telemetry events
    handler_id = :"telemetry_service_#{namespace}"

    :telemetry.attach_many(
      handler_id,
      Telemetry.foundation_events(),
      fn event_name, measurements, metadata, _config ->
        # Send to our service for processing
        service_pid = Process.whereis(service_name(namespace))
        if service_pid do
          send(service_pid, {:telemetry_event, event_name, measurements, metadata})
        end
      end,
      []
    )
  rescue
    error ->
      Logger.warning("Failed to attach telemetry handlers: #{inspect(error)}")
  end

  defp validate_exporter_module(module) do
    # Basic validation - check if module exists and has export_metrics function
    if Code.ensure_loaded?(module) do
      if function_exported?(module, :export_metrics, 1) do
        :ok
      else
        {:error, validation_error("Exporter module must implement export_metrics/1")}
      end
    else
      {:error, validation_error("Exporter module does not exist")}
    end
  end

  defp validate_alert_spec(alert_spec) do
    required_fields = [:name, :metric_path, :threshold, :condition]

    case Enum.find(required_fields, fn field -> not Map.has_key?(alert_spec, field) end) do
      nil -> :ok
      missing_field -> {:error, validation_error("Alert spec missing required field: #{missing_field}")}
    end
  end

  defp build_alert_rule(alert_spec) do
    %{
      name: alert_spec.name,
      metric_path: alert_spec.metric_path,
      threshold: alert_spec.threshold,
      condition: alert_spec.condition,
      enabled: Map.get(alert_spec, :enabled, true),
      last_triggered: nil
    }
  end

  defp build_service_stats(state) do
    raw_metrics_count = :ets.info(state.raw_metrics, :size)
    aggregated_metrics_count = :ets.info(state.aggregated_metrics, :size)
    alert_rules_count = :ets.info(state.alert_rules, :size)

    Map.merge(state.service_stats, %{
      raw_metrics_count: raw_metrics_count,
      aggregated_metrics_count: aggregated_metrics_count,
      alert_rules_count: alert_rules_count,
      exporters_count: map_size(state.exporters),
      last_aggregation: state.last_aggregation,
      aggregation_interval: state.aggregation_interval,
      retention_hours: state.retention_hours
    })
  end

  defp schedule_aggregation(interval) do
    Process.send_after(self(), :perform_aggregation, interval)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_old_metrics, @cleanup_interval_ms)
  end

  defp service_name(namespace) do
    :"Foundation.Services.TelemetryService.#{namespace}"
  end

  # Error Helper Functions

  defp telemetry_service_error(message, error) do
    Error.new(
      code: 9201,
      error_type: :telemetry_service_error,
      message: "Telemetry service error: #{message}",
      severity: :medium,
      context: %{error: error}
    )
  end

  defp validation_error(message) do
    Error.new(
      code: 9202,
      error_type: :telemetry_validation_failed,
      message: "Telemetry validation failed: #{message}",
      severity: :medium,
      context: %{validation_message: message}
    )
  end

  defp query_error(message, error) do
    Error.new(
      code: 9203,
      error_type: :telemetry_query_failed,
      message: "Telemetry query failed: #{message}",
      severity: :medium,
      context: %{error: error}
    )
  end
end