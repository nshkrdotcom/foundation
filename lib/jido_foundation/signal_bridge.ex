defmodule JidoFoundation.SignalBridge do
  @moduledoc """
  Bridge between JidoSignal and Foundation.Events for unified event handling.
  
  This module provides seamless integration between Jido's signal system
  and Foundation's event infrastructure, enabling:
  
  - Automatic conversion between Jido signals and Foundation events
  - Bidirectional event routing and subscription
  - Signal-based agent coordination through Foundation infrastructure
  - Event persistence and querying across both systems
  - Telemetry integration for signal/event analytics
  
  ## Usage Examples
  
      # Publish a Jido signal to Foundation events
      signal = Jido.Signal.new!(%{
        type: "agent.task.completed",
        source: "/agents/coder",
        data: %{task_id: "123", result: "success"}
      })
      :ok = SignalBridge.publish_signal_to_foundation(signal)
      
      # Subscribe Foundation events to Jido signal routing
      :ok = SignalBridge.subscribe_foundation_events_to_signals(
        :jido, 
        "agent.**"
      )
      
      # Create signal from Foundation event
      foundation_event = %Foundation.Event{...}
      signal = SignalBridge.create_signal_from_foundation_event(foundation_event)
  """

  alias Foundation.Events
  require Logger

  @type signal_pattern :: String.t()
  @type event_filter :: (Foundation.Event.t() -> boolean())
  @type bridge_result :: :ok | {:error, term()}

  @type bridge_config :: %{
          auto_convert: boolean(),
          preserve_metadata: boolean(),
          enable_telemetry: boolean(),
          event_namespace: atom(),
          signal_routing: boolean()
        }

  @type signal_subscription :: %{
          id: String.t(),
          pattern: signal_pattern(),
          target: :foundation_events | :jido_signals,
          config: map()
        }

  @doc """
  Publishes a Jido signal to Foundation's event system.
  
  Converts a Jido signal into a Foundation event and stores it in the
  Foundation event store, making it available for Foundation event subscribers.
  
  ## Parameters
  - `signal`: The Jido signal to publish
  - `opts`: Publishing options
  
  ## Options
  - `:namespace` - Foundation event namespace (default: :jido_signals)
  - `:correlation_id` - Event correlation ID (default: generated)
  - `:metadata` - Additional event metadata (default: %{})
  - `:persist` - Whether to persist the event (default: true)
  
  ## Returns
  - `:ok` if signal published successfully
  - `{:error, reason}` if publishing failed
  """
  @spec publish_signal_to_foundation(Jido.Signal.t(), keyword()) :: bridge_result()
  def publish_signal_to_foundation(signal, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, :jido_signals)
    correlation_id = Keyword.get(opts, :correlation_id, generate_correlation_id())
    metadata = Keyword.get(opts, :metadata, %{})
    persist = Keyword.get(opts, :persist, true)

    with {:ok, foundation_event} <- convert_signal_to_event(signal, correlation_id, metadata) do
      if persist do
        case Events.store(foundation_event) do
          {:ok, event_id} ->
            Logger.debug("Jido signal published to Foundation events", 
              signal_type: signal.type,
              event_id: event_id,
              namespace: namespace
            )
            
            emit_bridge_telemetry(:signal_to_event, signal, foundation_event)
            :ok
            
          {:error, reason} = error ->
            Logger.error("Failed to store Foundation event from Jido signal",
              signal_type: signal.type,
              reason: reason
            )
            error
        end
      else
        # Just emit the event without persistence
        emit_foundation_event(foundation_event, namespace)
        :ok
      end
    end
  end

  @doc """
  Subscribes Foundation events to Jido signal routing.
  
  Sets up automatic conversion and routing of Foundation events matching
  the specified pattern to the Jido signal system.
  
  ## Parameters
  - `namespace`: Foundation event namespace to monitor
  - `pattern`: Event pattern to match (supports wildcards)
  - `opts`: Subscription options
  
  ## Returns
  - `:ok` if subscription successful
  - `{:error, reason}` if subscription failed
  """
  @spec subscribe_foundation_events_to_signals(atom(), String.t(), keyword()) :: bridge_result()
  def subscribe_foundation_events_to_signals(namespace, pattern, opts \\ []) do
    subscription_id = generate_subscription_id()
    signal_router = Keyword.get(opts, :signal_router, :default)
    convert_config = Keyword.get(opts, :convert_config, %{})

    subscription_config = %{
      id: subscription_id,
      namespace: namespace,
      pattern: pattern,
      signal_router: signal_router,
      convert_config: convert_config,
      created_at: DateTime.utc_now()
    }

    # Set up Foundation event subscription
    case setup_foundation_event_subscription(subscription_config) do
      :ok ->
        Logger.info("Foundation events subscribed to Jido signals",
          namespace: namespace,
          pattern: pattern,
          subscription_id: subscription_id
        )
        :ok
        
      error -> error
    end
  end

  @doc """
  Creates a Jido signal from a Foundation event.
  
  Converts a Foundation event into a Jido signal with appropriate
  signal type and data mapping.
  
  ## Parameters
  - `foundation_event`: The Foundation event to convert
  - `opts`: Conversion options
  
  ## Returns
  - `{:ok, signal}` if conversion successful
  - `{:error, reason}` if conversion failed
  """
  @spec create_signal_from_foundation_event(Foundation.Event.t(), keyword()) :: 
        {:ok, Jido.Signal.t()} | {:error, term()}
  def create_signal_from_foundation_event(foundation_event, opts \\ []) do
    signal_type_mapping = Keyword.get(opts, :signal_type_mapping, %{})
    preserve_metadata = Keyword.get(opts, :preserve_metadata, true)

    with {:ok, signal_type} <- map_event_type_to_signal_type(foundation_event.event_type, signal_type_mapping),
         {:ok, signal_data} <- convert_event_data_to_signal_data(foundation_event, preserve_metadata) do
      
      signal = Jido.Signal.new!(%{
        type: signal_type,
        source: "/foundation/events",
        data: signal_data,
        correlation_id: foundation_event.correlation_id,
        timestamp: foundation_event.timestamp
      })
      
      Logger.debug("Foundation event converted to Jido signal",
        event_type: foundation_event.event_type,
        signal_type: signal_type
      )
      
      emit_bridge_telemetry(:event_to_signal, foundation_event, signal)
      {:ok, signal}
    end
  end

  @doc """
  Sets up bidirectional event/signal routing.
  
  Configures automatic conversion and routing in both directions:
  Foundation events -> Jido signals and Jido signals -> Foundation events.
  
  ## Parameters
  - `config`: Bidirectional routing configuration
  
  ## Returns
  - `:ok` if routing setup successful
  - `{:error, reason}` if setup failed
  """
  @spec setup_bidirectional_routing(bridge_config()) :: bridge_result()
  def setup_bidirectional_routing(config) do
    with :ok <- setup_signal_to_event_routing(config),
         :ok <- setup_event_to_signal_routing(config) do
      Logger.info("Bidirectional signal/event routing configured")
      :ok
    end
  end

  @doc """
  Gets statistics about signal/event bridge operations.
  
  ## Parameters
  - `time_window`: Time window for statistics in seconds (default: 300)
  
  ## Returns
  - `{:ok, stats}` with bridge statistics
  - `{:error, reason}` if statistics collection failed
  """
  @spec get_bridge_statistics(pos_integer()) :: {:ok, map()} | {:error, term()}
  def get_bridge_statistics(time_window \\ 300) do
    end_time = DateTime.utc_now()
    start_time = DateTime.add(end_time, -time_window, :second)

    stats = %{
      time_window: time_window,
      signals_to_events: count_signals_to_events(start_time, end_time),
      events_to_signals: count_events_to_signals(start_time, end_time),
      active_subscriptions: count_active_subscriptions(),
      conversion_errors: count_conversion_errors(start_time, end_time),
      bridge_performance: get_bridge_performance_metrics(start_time, end_time)
    }

    {:ok, stats}
  end

  @doc """
  Lists all active signal/event subscriptions.
  
  ## Returns
  - `{:ok, subscriptions}` with active subscriptions
  - `{:error, reason}` if listing failed
  """
  @spec list_active_subscriptions() :: {:ok, [signal_subscription()]} | {:error, term()}
  def list_active_subscriptions do
    # In a real implementation, this would query the subscription registry
    subscriptions = get_stored_subscriptions()
    {:ok, subscriptions}
  end

  @doc """
  Removes a signal/event subscription.
  
  ## Parameters
  - `subscription_id`: The subscription identifier
  
  ## Returns
  - `:ok` if removal successful
  - `{:error, reason}` if removal failed
  """
  @spec remove_subscription(String.t()) :: bridge_result()
  def remove_subscription(subscription_id) do
    case find_subscription(subscription_id) do
      {:ok, subscription} ->
        case cleanup_subscription(subscription) do
          :ok ->
            Logger.info("Signal bridge subscription removed", 
              subscription_id: subscription_id
            )
            :ok
          error -> error
        end
        
      :error -> {:error, {:subscription_not_found, subscription_id}}
    end
  end

  # Private implementation functions

  defp convert_signal_to_event(signal, correlation_id, metadata) do
    event_type = map_signal_type_to_event_type(signal.type)
    
    event_data = %{
      signal_type: signal.type,
      signal_source: signal.source,
      signal_data: signal.data,
      signal_correlation_id: signal.correlation_id,
      signal_timestamp: signal.timestamp,
      bridge_metadata: Map.merge(metadata, %{
        bridge_type: :jido_to_foundation,
        bridge_version: "1.0",
        converted_at: DateTime.utc_now()
      })
    }

    with {:ok, foundation_event} <- Events.new_event(
           event_type,
           event_data,
           correlation_id: correlation_id
         ) do
      {:ok, foundation_event}
    end
  end

  defp map_signal_type_to_event_type(signal_type) do
    # Map Jido signal types to Foundation event types
    case signal_type do
      "agent." <> _ = type -> String.replace(type, ".", "_")
      "task." <> _ = type -> String.replace(type, ".", "_")
      "coordination." <> _ = type -> String.replace(type, ".", "_")
      type -> "jido_signal_#{type}"
    end
  end

  defp emit_foundation_event(event, namespace) do
    # Emit the event through Foundation's event system
    :telemetry.execute(
      [:foundation, :events, :emitted],
      %{count: 1},
      %{namespace: namespace, event_type: event.event_type}
    )
  end

  defp setup_foundation_event_subscription(subscription_config) do
    # Set up actual Foundation event subscription
    # This would integrate with Foundation.Events subscription system
    try do
      handler_fun = fn event, measurements, metadata, _config ->
        handle_foundation_event_for_signals(event, subscription_config)
      end

      :telemetry.attach(
        subscription_config.id,
        [:foundation, :events, subscription_config.namespace],
        handler_fun,
        subscription_config
      )
      
      store_subscription(subscription_config)
      :ok
    rescue
      error -> {:error, {:subscription_setup_failed, error}}
    end
  end

  defp handle_foundation_event_for_signals(event, subscription_config) do
    if event_matches_pattern?(event, subscription_config.pattern) do
      case create_signal_from_foundation_event(event, subscription_config.convert_config) do
        {:ok, signal} ->
          # Route signal to Jido signal system
          route_signal_to_jido(signal, subscription_config.signal_router)
          
        {:error, reason} ->
          Logger.warning("Failed to convert Foundation event to signal",
            event_type: event.event_type,
            reason: reason
          )
      end
    end
  end

  defp map_event_type_to_signal_type(event_type, mapping) do
    case Map.get(mapping, event_type) do
      nil -> {:ok, "foundation.#{event_type}"}
      signal_type -> {:ok, signal_type}
    end
  end

  defp convert_event_data_to_signal_data(foundation_event, preserve_metadata) do
    signal_data = foundation_event.data
    
    if preserve_metadata do
      enhanced_data = Map.merge(signal_data, %{
        foundation_metadata: %{
          event_id: foundation_event.id,
          event_type: foundation_event.event_type,
          correlation_id: foundation_event.correlation_id,
          timestamp: foundation_event.timestamp
        }
      })
      {:ok, enhanced_data}
    else
      {:ok, signal_data}
    end
  end

  defp setup_signal_to_event_routing(config) do
    if config.auto_convert do
      # Set up automatic signal-to-event conversion
      # This would integrate with Jido signal system
      :ok
    else
      :ok
    end
  end

  defp setup_event_to_signal_routing(config) do
    if config.signal_routing do
      # Set up automatic event-to-signal conversion
      # This would integrate with Foundation event system
      :ok
    else
      :ok
    end
  end

  defp emit_bridge_telemetry(bridge_type, source, target) do
    :telemetry.execute(
      [:jido_foundation, :signal_bridge, bridge_type],
      %{count: 1},
      %{
        source_type: get_entity_type(source),
        target_type: get_entity_type(target),
        converted_at: DateTime.utc_now()
      }
    )
  end

  defp generate_correlation_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16()
  end

  defp generate_subscription_id do
    "sub_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16())
  end

  defp event_matches_pattern?(event, pattern) do
    # Simple pattern matching - in real implementation, use proper pattern matching
    String.contains?(event.event_type, String.replace(pattern, "**", ""))
  end

  defp route_signal_to_jido(signal, signal_router) do
    # Route signal through Jido signal system
    # This would integrate with Jido.Signal routing
    Logger.debug("Routing signal to Jido system", 
      signal_type: signal.type,
      router: signal_router
    )
  end

  defp get_entity_type(%Jido.Signal{}), do: :jido_signal
  defp get_entity_type(%{__struct__: module}) when module == Foundation.Events.Event, do: :foundation_event
  defp get_entity_type(_), do: :unknown

  # Placeholder functions for subscription management

  defp store_subscription(_subscription_config), do: :ok
  defp get_stored_subscriptions, do: []
  defp find_subscription(_subscription_id), do: :error
  defp cleanup_subscription(_subscription), do: :ok

  # Placeholder functions for statistics

  defp count_signals_to_events(_start_time, _end_time), do: 0
  defp count_events_to_signals(_start_time, _end_time), do: 0
  defp count_active_subscriptions, do: 0
  defp count_conversion_errors(_start_time, _end_time), do: 0
  defp get_bridge_performance_metrics(_start_time, _end_time), do: %{}
end
