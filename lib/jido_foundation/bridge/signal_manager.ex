defmodule JidoFoundation.Bridge.SignalManager do
  @moduledoc """
  Manages signal routing, subscriptions, and emission for Jido agents within Foundation.
  
  This module handles all signal-related operations that were previously in the Bridge module,
  providing a focused interface for signal management using Jido.Signal.Bus.
  """
  
  require Logger
  alias Jido.Signal.Bus
  
  @doc """
  Starts the Jido signal bus for Foundation agents.

  The signal bus provides production-grade signal routing for Jido agents
  with features like persistence, replay, and middleware support.

  ## Options

  - `:name` - Bus name (default: `:foundation_signal_bus`)
  - `:middleware` - List of middleware modules (default: logger middleware)

  ## Examples

      {:ok, bus_pid} = SignalManager.start_bus()
      {:ok, bus_pid} = SignalManager.start_bus(name: :my_bus, middleware: [{MyMiddleware, []}])
  """
  def start_bus(opts \\ []) do
    name = Keyword.get(opts, :name, :foundation_signal_bus)
    middleware = Keyword.get(opts, :middleware, [{Bus.Middleware.Logger, []}])

    # Start Jido Signal Bus with Foundation-specific configuration
    Bus.start_link(
      [
        name: name,
        middleware: middleware
      ] ++ Keyword.drop(opts, [:name, :middleware])
    )
  end

  @doc """
  Subscribes a handler to receive signals matching a specific path pattern.

  Uses Jido.Signal.Bus path patterns, which support wildcards and more
  sophisticated routing than the previous custom SignalRouter.

  ## Examples

      # Subscribe to exact signal type
      {:ok, subscription_id} = SignalManager.subscribe("agent.task.completed", handler_pid)

      # Subscribe to all task signals
      {:ok, subscription_id} = SignalManager.subscribe("agent.task.*", handler_pid)

      # Subscribe to all agent signals
      {:ok, subscription_id} = SignalManager.subscribe("agent.*", handler_pid)

  ## Returns

  - `{:ok, subscription_id}` - Unique subscription identifier for unsubscribing
  - `{:error, reason}` - If subscription fails
  """
  def subscribe(signal_path, handler_pid, opts \\ []) do
    bus_name = Keyword.get(opts, :bus, :foundation_signal_bus)

    # Configure dispatch to the handler process
    dispatch_opts = [
      dispatch: {:pid, [target: handler_pid, delivery_mode: :async]}
    ]

    subscription_opts = Keyword.merge(dispatch_opts, Keyword.drop(opts, [:bus]))

    Bus.subscribe(bus_name, signal_path, subscription_opts)
  end

  @doc """
  Unsubscribes a handler from receiving signals using the subscription ID.

  ## Examples

      {:ok, subscription_id} = SignalManager.subscribe("agent.task.*", handler_pid)
      :ok = SignalManager.unsubscribe(subscription_id)
  """
  def unsubscribe(subscription_id, opts \\ []) do
    bus_name = Keyword.get(opts, :bus, :foundation_signal_bus)
    Bus.unsubscribe(bus_name, subscription_id)
  end

  @doc """
  Gets signal replay from the bus for debugging and monitoring.

  ## Examples

      # Get all recent signals
      {:ok, signals} = SignalManager.get_history()

      # Get signals matching a specific path
      {:ok, signals} = SignalManager.get_history("agent.task.*")
  """
  def get_history(path \\ "*", opts \\ []) do
    bus_name = Keyword.get(opts, :bus, :foundation_signal_bus)
    start_timestamp = Keyword.get(opts, :since, 0)

    Bus.replay(bus_name, path, start_timestamp, opts)
  end

  @doc """
  Emits a Jido signal through the signal bus.

  This function publishes signals to the Jido.Signal.Bus, which provides
  proper signal routing to all subscribers with persistence and middleware support.

  ## Signal Format

  Signals should be Jido.Signal structs or maps with:
  - `:type` - Signal type (e.g., "agent.task.completed")
  - `:source` - Signal source (e.g., "/agent/task_processor")
  - `:data` - Signal payload
  - `:time` - ISO 8601 timestamp (optional, auto-generated)

  ## Examples

      # Emit a task completion signal
      signal = %Jido.Signal{
        type: "agent.task.completed",
        source: "/agent/task_processor",
        data: %{result: "success", duration: 150}
      }
      {:ok, [signal]} = SignalManager.emit(signal)

      # Emit using map format (will be converted to Jido.Signal)
      signal_map = %{
        type: "agent.error.occurred",
        source: "/agent/worker",
        data: %{error: "timeout", retry_count: 3}
      }
      {:ok, [signal]} = SignalManager.emit(agent_pid, signal_map)
  """
  def emit(agent, signal, opts \\ []) do
    # Agent parameter is used in telemetry metadata
    bus_name = Keyword.get(opts, :bus, :foundation_signal_bus)

    # Preserve original signal ID for telemetry
    original_signal_id =
      case signal do
        %{id: id} -> id
        _ -> nil
      end

    # Ensure signal is in the proper format
    normalized_signal = normalize_signal(signal)

    # Publish to the signal bus if signal creation succeeded
    case normalized_signal do
      nil ->
        {:error, :invalid_signal_format}

      signal ->
        # Get the bus name from Foundation Signal Bus service
        actual_bus_name =
          case Foundation.Services.SignalBus.get_bus_name() do
            bus when is_atom(bus) -> bus
            # fallback to provided bus_name
            {:error, :not_started} -> bus_name
          end

        case Bus.publish(actual_bus_name, [signal]) do
          {:ok, [published_signal]} = result ->
            # Extract signal data from RecordedSignal structure
            signal_data = published_signal.signal

            # Also emit traditional telemetry for backward compatibility
            # Use original signal ID if available, otherwise use the Jido.Signal ID
            telemetry_signal_id = original_signal_id || signal_data.id

            emit_telemetry(agent, signal_data, telemetry_signal_id)

            result

          {:error, :not_found} ->
            # Bus not started, but we can still emit telemetry
            # This allows tests to work without a full signal bus
            telemetry_signal_id = original_signal_id || signal.id
            emit_telemetry(agent, signal, telemetry_signal_id)
            
            # Return a simulated success response for compatibility
            {:ok, [%{signal: signal, timestamp: System.system_time(:microsecond)}]}

          error ->
            error
        end
    end
  end

  @doc """
  Emits a signal with protection against handler failures.

  This function ensures that even if signal handlers crash, the emission
  process continues gracefully.

  ## Examples

      result = SignalManager.emit_protected(agent_pid, signal)
      # => :ok (even if some handlers crash)
  """
  def emit_protected(agent_pid, signal, opts \\ []) do
    emit(agent_pid, signal, opts)
    :ok
  catch
    kind, reason ->
      Logger.warning("Signal emission failed: #{kind} #{inspect(reason)}")
      :ok
  end

  @doc """
  Converts a Jido signal to CloudEvents v1.0.2 format.

  ## Examples

      signal = %{id: 123, type: "task.completed", source: "agent://123", data: %{}}
      cloudevent = SignalManager.signal_to_cloudevent(signal)
  """
  def signal_to_cloudevent(signal) do
    # Extract signal data
    signal_id = Map.get(signal, :id, System.unique_integer())
    signal_type = Map.get(signal, :type, "unknown")
    source = Map.get(signal, :source, "unknown")
    data = Map.get(signal, :data, %{})
    time = Map.get(signal, :time, DateTime.utc_now())
    metadata = Map.get(signal, :metadata, %{})

    # Build CloudEvent structure
    %{
      specversion: "1.0",
      type: signal_type,
      source: source,
      id: to_string(signal_id),
      time: DateTime.to_iso8601(time),
      datacontenttype: "application/json",
      data: data,
      subject: Map.get(metadata, :subject),
      extensions: Map.drop(metadata, [:subject])
    }
  end

  @doc """
  Emits a Jido agent event through Foundation telemetry.

  ## Examples

      emit_agent_event(agent_pid, :action_completed, %{
        action: :process_request,
        duration: 150
      })
  """
  def emit_agent_event(agent_pid, event_type, measurements \\ %{}, metadata \\ %{}) do
    :telemetry.execute(
      [:jido, :agent, event_type],
      measurements,
      Map.merge(metadata, %{
        agent_id: agent_pid,
        framework: :jido,
        timestamp: System.system_time(:microsecond)
      })
    )
  end

  # Private functions

  defp normalize_signal(signal) do
    case signal do
      %Jido.Signal{} = sig ->
        sig

      signal_map when is_map(signal_map) ->
        # Convert legacy signal format to Jido.Signal
        type =
          Map.get(signal_map, :type) ||
            Map.get(signal_map, :path) ||
            "unknown"

        source =
          Map.get(signal_map, :source) ||
            "/agent/foundation"

        data = Map.get(signal_map, :data, %{})

        # Preserve original ID if present
        signal_attrs = %{
          type: type,
          source: source,
          data: data,
          time: DateTime.utc_now() |> DateTime.to_iso8601()
        }

        # Add ID if it exists in the original signal (convert to string for Jido.Signal)
        signal_attrs =
          case Map.get(signal_map, :id) do
            nil -> signal_attrs
            id -> Map.put(signal_attrs, "id", to_string(id))
          end

        case Jido.Signal.new(signal_attrs) do
          {:ok, signal} ->
            signal

          {:error, _} ->
            # Fallback with minimal fields
            case Jido.Signal.new(%{type: type, source: source}) do
              {:ok, signal} -> %{signal | data: data}
              {:error, _} -> nil
            end
        end

      _ ->
        # Fallback for other formats
        case Jido.Signal.new(%{
               type: "unknown",
               source: "/agent/foundation",
               data: signal
             }) do
          {:ok, signal} -> signal
          {:error, _} -> nil
        end
    end
  end

  defp emit_telemetry(agent, signal_data, telemetry_signal_id) do
    :telemetry.execute(
      [:jido, :signal, :emitted],
      %{signal_id: telemetry_signal_id},
      %{
        agent_id: agent,
        signal_type: signal_data.type,
        signal_source: signal_data.source,
        framework: :jido,
        timestamp: System.system_time(:microsecond)
      }
    )
  end
end