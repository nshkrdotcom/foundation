defmodule Foundation.EventSystem do
  @moduledoc """
  Unified event system adapter for Foundation.

  This module provides a single, consistent interface for event emission
  across Foundation, consolidating multiple event systems (telemetry, signals,
  direct messaging) into one coherent API.

  ## Design Philosophy

  Different event systems serve different purposes:
  - **Telemetry**: Metrics, performance monitoring, observability
  - **Signals**: Agent communication, behavioral events, coordination
  - **Direct Messages**: Low-latency, point-to-point communication

  This module doesn't replace these systems but provides a unified
  interface that routes events to the appropriate system based on
  event type and configuration.

  ## Usage

      # Emit a metric event (routed to telemetry)
      Foundation.EventSystem.emit(:metric, [:connection, :acquired], %{
        duration: 100,
        pool_id: :main
      })

      # Emit a signal (routed to signal bus)  
      Foundation.EventSystem.emit(:signal, [:agent, :task, :completed], %{
        agent_id: "agent_1",
        task_id: "task_123",
        result: :success
      })

      # Emit a notification (configurable routing)
      Foundation.EventSystem.emit(:notification, [:error, :occurred], %{
        service: ConnectionManager,
        error: :timeout
      })

  ## Configuration

      config :foundation, :event_routing,
        metric: :telemetry,
        signal: :signal_bus,
        notification: :telemetry,
        coordination: :signal_bus
  """

  require Logger
  alias Foundation.Telemetry
  alias Foundation.ErrorHandling

  @type event_type :: :metric | :signal | :notification | :coordination | :custom
  @type event_name :: [atom()]
  @type event_data :: map()
  @type routing_target :: :telemetry | :signal_bus | :logger | :noop

  @doc """
  Emits an event through the unified event system.

  The event is routed to the appropriate backend based on its type
  and the configured routing rules.

  ## Parameters
  - `type` - The event type (determines routing)
  - `name` - Event name as a list of atoms
  - `data` - Event data/measurements as a map

  ## Examples

      # Metric event
      Foundation.EventSystem.emit(:metric, [:request, :completed], %{
        duration: 150,
        status: 200
      })

      # Signal event  
      Foundation.EventSystem.emit(:signal, [:agent, :state, :changed], %{
        agent_id: "agent_1",
        from_state: :idle,
        to_state: :busy
      })

  ## Returns
  - `:ok` - Event emitted successfully
  - `{:error, reason}` - Failed to emit event
  """
  @spec emit(event_type(), event_name(), event_data()) :: :ok | {:error, term()}
  def emit(type, name, data \\ %{}) do
    # Add common metadata
    enriched_data = enrich_event_data(data)

    # Route to appropriate backend
    case get_routing_target(type) do
      :telemetry ->
        emit_telemetry(name, enriched_data)

      :signal_bus ->
        emit_signal(type, name, enriched_data)

      :logger ->
        emit_log(type, name, enriched_data)

      :noop ->
        :ok

      {:custom, handler} ->
        emit_custom(handler, type, name, enriched_data)
    end
  end

  @doc """
  Subscribes to events of a specific type and pattern.

  This provides a unified subscription interface that works across
  different event backends.

  ## Parameters
  - `type` - Event type to subscribe to
  - `pattern` - Event name pattern (supports wildcards for signals)
  - `handler` - Handler function or process

  ## Examples

      # Subscribe to all metric events
      Foundation.EventSystem.subscribe(:metric, [:foundation, :_, :_], fn event, data ->
        IO.inspect({event, data})
      end)

      # Subscribe to specific signals
      Foundation.EventSystem.subscribe(:signal, [:agent, :task, :*], self())
  """
  @spec subscribe(event_type(), term(), term()) :: {:ok, term()} | {:error, term()}
  def subscribe(type, pattern, handler) do
    case get_routing_target(type) do
      :telemetry ->
        subscribe_telemetry(pattern, handler)

      :signal_bus ->
        subscribe_signal(pattern, handler)

      _ ->
        {:error, {:unsupported_subscription, type}}
    end
  end

  @doc """
  Gets the current event routing configuration.
  """
  @spec get_routing_config() :: %{
          optional(atom()) => atom(),
          metric: atom(),
          signal: atom(),
          notification: atom(),
          coordination: atom()
        }
  def get_routing_config do
    default_routing = %{
      metric: :telemetry,
      signal: :signal_bus,
      notification: :telemetry,
      coordination: :signal_bus
    }

    configured = Application.get_env(:foundation, :event_routing, %{})
    Map.merge(default_routing, configured)
  end

  @doc """
  Updates event routing configuration at runtime.

  Note: This only affects new subscriptions and emissions.
  Existing subscriptions remain unchanged.
  """
  @spec update_routing_config(map()) :: :ok
  def update_routing_config(new_config) do
    current = get_routing_config()
    updated = Map.merge(current, new_config)
    Application.put_env(:foundation, :event_routing, updated)
    :ok
  end

  # Private functions

  defp get_routing_target(type) do
    routing = get_routing_config()
    Map.get(routing, type, :telemetry)
  end

  defp enrich_event_data(data) do
    Map.merge(data, %{
      timestamp: System.system_time(),
      node: node(),
      foundation_version: "2.1"
    })
  end

  defp emit_telemetry(name, data) do
    ErrorHandling.emit_telemetry_safe(
      [:foundation | name],
      data,
      %{source: :event_system}
    )
  end

  defp emit_signal(type, name, data) do
    # Convert to signal format
    signal_type = name |> Enum.join(".") |> String.to_atom()

    signal = %{
      id: generate_signal_id(),
      type: signal_type,
      data: data,
      metadata: %{
        event_type: type,
        source: :event_system
      }
    }

    # Emit through signal bus if available
    case Process.whereis(:foundation_signal_bus) do
      nil ->
        Logger.debug("Signal bus not available, event not routed: #{inspect(signal_type)}")
        :ok

      _pid ->
        JidoFoundation.Bridge.emit_signal(self(), signal)
    end
  end

  defp emit_log(type, name, data) do
    Logger.info("Foundation Event: #{inspect(type)} #{inspect(name)}",
      event_data: data
    )

    :ok
  end

  defp emit_custom(handler, type, name, data) when is_function(handler, 3) do
    try do
      handler.(type, name, data)
      :ok
    rescue
      e ->
        Logger.error("Custom event handler failed: #{Exception.message(e)}")
        {:error, {:handler_failed, e}}
    end
  end

  defp subscribe_telemetry(pattern, handler) when is_function(handler) do
    handler_id = "event_system_#{:erlang.unique_integer([:positive])}"

    Telemetry.attach(
      handler_id,
      [:foundation | pattern],
      fn event, measurements, metadata, _config ->
        handler.(event, Map.merge(measurements, metadata))
      end,
      nil
    )

    {:ok, handler_id}
  end

  defp subscribe_signal(pattern, handler) do
    # Convert pattern to signal path
    signal_path = pattern |> Enum.join(".")

    case Process.whereis(:foundation_signal_bus) do
      nil ->
        {:error, :signal_bus_not_available}

      _pid ->
        JidoFoundation.Bridge.subscribe_to_signals(signal_path, handler)
    end
  end

  defp generate_signal_id do
    "evt_#{:erlang.unique_integer([:positive])}_#{System.system_time(:microsecond)}"
  end
end
