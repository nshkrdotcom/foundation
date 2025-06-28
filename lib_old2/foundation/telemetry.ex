defmodule Foundation.Telemetry do
  @moduledoc """
  Enhanced telemetry system for Foundation infrastructure with agent-aware metrics.

  Provides comprehensive observability across all Foundation components,
  with special support for multi-agent coordination metrics, distributed
  system monitoring, and performance tracking.

  ## Features

  - **Agent-Aware Metrics**: Track metrics per agent, capability, and health state
  - **Infrastructure Metrics**: Monitor circuit breakers, rate limiters, coordination
  - **Distribution Metrics**: Cross-node coordination and process registry stats
  - **Performance Tracking**: Latency, throughput, and resource utilization
  - **Health Monitoring**: System and agent health indicators
  - **Custom Events**: Extensible event system for application-specific metrics

  ## Usage

      # Emit basic counter
      Telemetry.emit_counter([:foundation, :process_registry, :registration], %{
        namespace: :production
      })

      # Emit gauge with agent context
      Telemetry.emit_gauge([:foundation, :agent, :memory_usage], 0.85, %{
        agent_id: :ml_agent_1,
        capability: :inference
      })

      # Emit histogram for latency tracking
      Telemetry.emit_histogram([:foundation, :coordination, :consensus_latency], 150, %{
        participants: 5,
        algorithm: :raft
      })

      # Emit custom agent event
      Telemetry.emit_agent_event(:coordination_completed, %{
        agent_id: :coordinator_1,
        participants: [:agent_1, :agent_2, :agent_3],
        duration: 250
      })
  """

  require Logger

  @type event_name :: [atom()]
  @type metric_value :: number()
  @type metadata :: map()
  @type agent_id :: atom() | String.t()
  @type capability :: atom()

  # Standard telemetry events that Foundation emits
  @foundation_events [
    # Process Registry Events
    [:foundation, :process_registry, :registration],
    [:foundation, :process_registry, :lookup],
    [:foundation, :process_registry, :unregistration],
    [:foundation, :process_registry, :health_check],

    # Circuit Breaker Events
    [:foundation, :infrastructure, :agent_circuit_breaker, :circuit_started],
    [:foundation, :infrastructure, :agent_circuit_breaker, :operation_executed],
    [:foundation, :infrastructure, :agent_circuit_breaker, :circuit_reset],

    # Rate Limiter Events
    [:foundation, :infrastructure, :agent_rate_limiter, :request_allowed],
    [:foundation, :infrastructure, :agent_rate_limiter, :request_denied],
    [:foundation, :infrastructure, :agent_rate_limiter, :bucket_reset],

    # Coordination Events
    [:foundation, :coordination, :consensus_started],
    [:foundation, :coordination, :consensus_completed],
    [:foundation, :coordination, :barrier_created],
    [:foundation, :coordination, :barrier_satisfied],
    [:foundation, :coordination, :lock_acquired],
    [:foundation, :coordination, :lock_released],
    [:foundation, :coordination, :leader_elected],

    # Agent Events
    [:foundation, :agent, :health_changed],
    [:foundation, :agent, :capability_updated],
    [:foundation, :agent, :resource_threshold_exceeded],

    # System Events
    [:foundation, :system, :startup_completed],
    [:foundation, :system, :shutdown_initiated],
    [:foundation, :system, :health_check_completed]
  ]

  @doc """
  Initialize the Foundation telemetry system.

  Sets up telemetry handlers and prepares the system for metric collection.
  Should be called during application startup.
  """
  @spec initialize() :: :ok
  def initialize do
    # Attach default telemetry handlers
    attach_foundation_handlers()

    # Start periodic health metrics
    start_health_metrics_collector()

    # Emit initialization event
    emit_counter([:foundation, :telemetry, :initialized], %{
      timestamp: DateTime.utc_now(),
      events_configured: length(@foundation_events)
    })

    :ok
  end

  @doc """
  Emit a counter metric.

  Counters track the number of times an event occurs.
  """
  @spec emit_counter(event_name(), metadata()) :: :ok
  def emit_counter(event_name, metadata \\ %{}) do
    enriched_metadata = enrich_metadata(metadata)

    :telemetry.execute(event_name, %{count: 1}, enriched_metadata)

    # Log high-severity events
    if should_log_event?(event_name, enriched_metadata) do
      Logger.info("Telemetry: #{format_event_name(event_name)}",
        metadata: enriched_metadata)
    end

    :ok
  rescue
    error ->
      Logger.warning("Telemetry emit_counter failed: #{inspect(error)}")
      :ok
  end

  @doc """
  Emit a gauge metric.

  Gauges represent a value at a point in time (e.g., memory usage, connection count).
  """
  @spec emit_gauge(event_name(), metric_value(), metadata()) :: :ok
  def emit_gauge(event_name, value, metadata \\ %{}) do
    enriched_metadata = enrich_metadata(metadata)

    :telemetry.execute(event_name, %{value: value}, enriched_metadata)

    # Log critical thresholds
    if should_alert_on_gauge?(event_name, value, enriched_metadata) do
      Logger.warning("Telemetry gauge alert: #{format_event_name(event_name)} = #{value}",
        metadata: enriched_metadata)
    end

    :ok
  rescue
    error ->
      Logger.warning("Telemetry emit_gauge failed: #{inspect(error)}")
      :ok
  end

  @doc """
  Emit a histogram metric.

  Histograms track the distribution of values over time (e.g., latency, request size).
  """
  @spec emit_histogram(event_name(), metric_value(), metadata()) :: :ok
  def emit_histogram(event_name, value, metadata \\ %{}) do
    enriched_metadata = enrich_metadata(metadata)

    :telemetry.execute(event_name, %{duration: value}, enriched_metadata)

    :ok
  rescue
    error ->
      Logger.warning("Telemetry emit_histogram failed: #{inspect(error)}")
      :ok
  end

  @doc """
  Emit an agent-specific event with automatic context enrichment.

  Adds standard agent context and routing information.
  """
  @spec emit_agent_event(atom(), metadata()) :: :ok
  def emit_agent_event(event_type, metadata \\ %{}) do
    event_name = [:foundation, :agent, event_type]

    # Enrich with agent context if agent_id is provided
    enriched_metadata = case Map.get(metadata, :agent_id) do
      nil -> metadata
      agent_id ->
        metadata
        |> Map.put(:agent_context, get_agent_context(agent_id))
        |> Map.put(:node, Node.self())
    end

    emit_counter(event_name, enriched_metadata)
  end

  @doc """
  Emit a coordination event with participant information.

  Special handling for multi-agent coordination metrics.
  """
  @spec emit_coordination_event(atom(), metadata()) :: :ok
  def emit_coordination_event(event_type, metadata \\ %{}) do
    event_name = [:foundation, :coordination, event_type]

    # Add coordination-specific context
    enriched_metadata = metadata
    |> Map.put(:coordination_timestamp, DateTime.utc_now())
    |> Map.put(:node, Node.self())
    |> add_participant_context()

    emit_counter(event_name, enriched_metadata)
  end

  @doc """
  Get the list of all telemetry events that Foundation emits.

  Useful for telemetry handler setup and monitoring configuration.
  """
  @spec foundation_events() :: [event_name()]
  def foundation_events, do: @foundation_events

  @doc """
  Check if telemetry is properly initialized and functioning.
  """
  @spec health_check() :: :ok | {:error, term()}
  def health_check do
    try do
      # Emit a test event
      test_metadata = %{health_check: true, timestamp: DateTime.utc_now()}
      emit_counter([:foundation, :telemetry, :health_check], test_metadata)
      :ok
    rescue
      error -> {:error, error}
    end
  end

  # Private Implementation

  defp attach_foundation_handlers do
    # Attach a basic logging handler for all Foundation events
    :telemetry.attach_many(
      "foundation-telemetry-logger",
      @foundation_events,
      &handle_foundation_event/4,
      []
    )
  rescue
    error ->
      Logger.error("Failed to attach telemetry handlers: #{inspect(error)}")
  end

  defp handle_foundation_event(event_name, measurements, metadata, _config) do
    # This is a basic handler - in production you might send to
    # Prometheus, DataDog, New Relic, etc.

    case event_name do
      # Log critical events
      [:foundation, :agent, :health_changed] ->
        if Map.get(metadata, :new_health) == :unhealthy do
          Logger.warning("Agent health degraded", metadata: metadata)
        end

      [:foundation, :infrastructure, :agent_circuit_breaker, :operation_executed] ->
        if Map.get(metadata, :result) == :failure do
          Logger.warning("Circuit breaker operation failed", metadata: metadata)
        end

      _ ->
        # For most events, just ensure they're captured
        :ok
    end
  rescue
    error ->
      Logger.debug("Telemetry handler error: #{inspect(error)}")
  end

  defp start_health_metrics_collector do
    # Start a process that periodically collects system health metrics
    spawn(fn -> health_metrics_loop() end)
  end

  defp health_metrics_loop do
    try do
      # Collect basic system metrics
      memory_usage = :erlang.memory(:total) / (1024 * 1024)  # MB
      process_count = :erlang.system_info(:process_count)

      emit_gauge([:foundation, :system, :memory_usage_mb], memory_usage)
      emit_gauge([:foundation, :system, :process_count], process_count)

      # Collect Foundation-specific metrics
      registry_metrics = get_process_registry_metrics()
      emit_gauge([:foundation, :process_registry, :registered_processes],
        Map.get(registry_metrics, :total_registered, 0))

    rescue
      error ->
        Logger.debug("Health metrics collection error: #{inspect(error)}")
    end

    # Sleep for 30 seconds then repeat
    Process.sleep(30_000)
    health_metrics_loop()
  end

  defp enrich_metadata(metadata) do
    metadata
    |> Map.put_new(:timestamp, DateTime.utc_now())
    |> Map.put_new(:node, Node.self())
    |> Map.put_new(:process, self())
  end

  defp should_log_event?(event_name, metadata) do
    # Log critical events or events in test mode
    critical_events = [
      [:foundation, :system, :startup_completed],
      [:foundation, :system, :shutdown_initiated],
      [:foundation, :agent, :health_changed]
    ]

    event_name in critical_events or Map.get(metadata, :test_mode, false)
  end

  defp should_alert_on_gauge?(event_name, value, _metadata) do
    case event_name do
      [:foundation, :system, :memory_usage_mb] -> value > 1000  # > 1GB
      [:foundation, :agent, :memory_usage] -> value > 0.9      # > 90%
      [:foundation, :agent, :cpu_usage] -> value > 0.95        # > 95%
      _ -> false
    end
  end

  defp get_agent_context(agent_id) do
    # Try to get agent context from ProcessRegistry
    case Foundation.ProcessRegistry.lookup(:foundation, agent_id) do
      {:ok, _pid, metadata} ->
        Map.take(metadata, [:capability, :health, :resources])

      :error ->
        %{status: :not_found}
    end
  rescue
    _ -> %{status: :error}
  end

  defp add_participant_context(metadata) do
    case Map.get(metadata, :participants) do
      participants when is_list(participants) ->
        Map.put(metadata, :participant_count, length(participants))

      _ -> metadata
    end
  end

  defp get_process_registry_metrics do
    # Get basic metrics from ProcessRegistry if available
    try do
      case Foundation.ProcessRegistry.list_all(:foundation) do
        {:ok, processes} ->
          %{
            total_registered: length(processes),
            agents: Enum.count(processes, fn {_id, _pid, meta} ->
              Map.get(meta, :type) == :agent
            end)
          }

        _ -> %{}
      end
    rescue
      _ -> %{}
    end
  end

  defp format_event_name(event_name) do
    event_name
    |> Enum.map(&to_string/1)
    |> Enum.join(".")
  end
end