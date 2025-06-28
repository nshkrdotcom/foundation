defmodule Foundation.Services.EventStore do
  @moduledoc """
  Agent-aware event storage and querying service for Foundation infrastructure.

  Provides comprehensive event logging, storage, and querying capabilities
  with agent context integration. Designed for multi-agent environments
  where event correlation, agent tracing, and coordination event tracking
  are essential for system observability and debugging.

  ## Features

  - **Agent Context Events**: Events automatically enriched with agent context
  - **Event Correlation**: Link related events across agent boundaries
  - **Structured Storage**: Efficient storage with indexing for fast queries
  - **Real-time Subscriptions**: Live event streaming with filtering
  - **Coordination Integration**: Special handling for coordination events
  - **Performance Optimization**: Batching, compression, and retention policies

  ## Event Types Supported

  - **Agent Lifecycle**: Agent start, stop, health changes
  - **Coordination Events**: Consensus, barriers, locks, elections
  - **Infrastructure Events**: Circuit breaker trips, rate limits, resource alerts
  - **Configuration Changes**: Config updates with agent impact tracking
  - **Custom Events**: Application-specific events with agent context

  ## Usage

      # Start event store
      {:ok, _pid} = EventStore.start_link([
        namespace: :production,
        retention_days: 7,
        batch_size: 100
      ])

      # Store events
      event = %{
        type: :agent_health_changed,
        agent_id: :ml_agent_1,
        data: %{old_health: :healthy, new_health: :degraded},
        correlation_id: "abc-123"
      }
      EventStore.store_event(event)

      # Query events
      {:ok, events} = EventStore.query_events(%{
        agent_id: :ml_agent_1,
        type: :agent_health_changed,
        since: DateTime.add(DateTime.utc_now(), -3600)  # Last hour
      })

      # Subscribe to events
      EventStore.subscribe_to_events(%{type: :coordination_completed})
  """

  use GenServer
  require Logger

  alias Foundation.ProcessRegistry
  alias Foundation.Telemetry
  alias Foundation.Types.Error

  @type event_id :: String.t()
  @type agent_id :: atom() | String.t()
  @type event_type :: atom()
  @type correlation_id :: String.t()

  @type event :: %{
    id: event_id(),
    type: event_type(),
    agent_id: agent_id() | nil,
    data: map(),
    metadata: map(),
    correlation_id: correlation_id() | nil,
    timestamp: DateTime.t()
  }

  @type query_filter :: %{
    agent_id: agent_id() | nil,
    type: event_type() | nil,
    correlation_id: correlation_id() | nil,
    since: DateTime.t() | nil,
    until: DateTime.t() | nil,
    limit: pos_integer() | nil
  }

  @type subscription :: %{
    pid: pid(),
    filter: query_filter(),
    subscription_id: String.t()
  }

  defstruct [
    :namespace,
    :retention_days,
    :batch_size,
    :event_store,
    :event_indexes,
    :subscriptions,
    :batch_buffer,
    :last_cleanup,
    :storage_stats
  ]

  @type t :: %__MODULE__{
    namespace: atom(),
    retention_days: pos_integer(),
    batch_size: pos_integer(),
    event_store: :ets.tid(),
    event_indexes: :ets.tid(),
    subscriptions: :ets.tid(),
    batch_buffer: [event()],
    last_cleanup: DateTime.t(),
    storage_stats: map()
  }

  # Default configuration
  @default_retention_days 7
  @default_batch_size 100
  @cleanup_interval_ms 60_000  # 1 minute

  # Public API

  @doc """
  Start the event store service.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(options \\ []) do
    namespace = Keyword.get(options, :namespace, :foundation)
    GenServer.start_link(__MODULE__, options, name: service_name(namespace))
  end

  @doc """
  Store a single event.

  The event will be enriched with automatic metadata including
  timestamp, event ID, and agent context if available.

  ## Examples

      event = %{
        type: :agent_started,
        agent_id: :ml_agent_1,
        data: %{capability: :inference}
      }

      EventStore.store_event(event)
  """
  @spec store_event(map(), atom()) :: :ok | {:error, Error.t()}
  def store_event(event_data, namespace \\ :foundation) do
    GenServer.call(service_name(namespace), {:store_event, event_data})
  rescue
    error -> {:error, event_store_error("store_event failed", error)}
  end

  @doc """
  Store multiple events in a batch.

  More efficient than storing events individually for bulk operations.
  """
  @spec store_events([map()], atom()) :: :ok | {:error, Error.t()}
  def store_events(event_list, namespace \\ :foundation) when is_list(event_list) do
    GenServer.call(service_name(namespace), {:store_events, event_list})
  rescue
    error -> {:error, event_store_error("store_events failed", error)}
  end

  @doc """
  Query events based on filter criteria.

  Returns events matching the specified filter, ordered by timestamp.

  ## Filter Options

  - `:agent_id` - Filter by specific agent
  - `:type` - Filter by event type
  - `:correlation_id` - Filter by correlation ID
  - `:since` - Events after this timestamp
  - `:until` - Events before this timestamp
  - `:limit` - Maximum number of events to return

  ## Examples

      # Get all events for an agent
      {:ok, events} = EventStore.query_events(%{agent_id: :ml_agent_1})

      # Get coordination events from last hour
      one_hour_ago = DateTime.add(DateTime.utc_now(), -3600)
      {:ok, events} = EventStore.query_events(%{
        type: :coordination_completed,
        since: one_hour_ago
      })
  """
  @spec query_events(query_filter(), atom()) :: {:ok, [event()]} | {:error, Error.t()}
  def query_events(filter, namespace \\ :foundation) do
    GenServer.call(service_name(namespace), {:query_events, filter}, 10_000)
  rescue
    error -> {:error, event_store_error("query_events failed", error)}
  end

  @doc """
  Subscribe to real-time events matching filter criteria.

  The calling process will receive messages of the form:
  `{:event, subscription_id, event}`
  """
  @spec subscribe_to_events(query_filter(), atom()) :: {:ok, String.t()} | {:error, Error.t()}
  def subscribe_to_events(filter, namespace \\ :foundation) do
    GenServer.call(service_name(namespace), {:subscribe, self(), filter})
  rescue
    error -> {:error, event_store_error("subscribe_to_events failed", error)}
  end

  @doc """
  Unsubscribe from event notifications.
  """
  @spec unsubscribe_from_events(String.t(), atom()) :: :ok
  def unsubscribe_from_events(subscription_id, namespace \\ :foundation) do
    GenServer.call(service_name(namespace), {:unsubscribe, subscription_id})
  rescue
    error ->
      Logger.warning("Failed to unsubscribe from events: #{inspect(error)}")
      :ok
  end

  @doc """
  Get event store statistics.

  Returns information about storage usage, event counts, and performance metrics.
  """
  @spec get_stats(atom()) :: {:ok, map()} | {:error, Error.t()}
  def get_stats(namespace \\ :foundation) do
    GenServer.call(service_name(namespace), :get_stats)
  rescue
    error -> {:error, event_store_error("get_stats failed", error)}
  end

  @doc """
  Get events correlated with a specific correlation ID.

  Useful for tracing related events across multiple agents and components.
  """
  @spec get_correlated_events(correlation_id(), atom()) :: {:ok, [event()]} | {:error, Error.t()}
  def get_correlated_events(correlation_id, namespace \\ :foundation) do
    filter = %{correlation_id: correlation_id}
    query_events(filter, namespace)
  end

  # GenServer Implementation

  @impl GenServer
  def init(options) do
    namespace = Keyword.get(options, :namespace, :foundation)
    retention_days = Keyword.get(options, :retention_days, @default_retention_days)
    batch_size = Keyword.get(options, :batch_size, @default_batch_size)

    # Create ETS tables for event storage
    event_store = :ets.new(:event_store, [
      :ordered_set, :private, {:write_concurrency, true}, {:read_concurrency, true}
    ])

    # Create indexes for efficient querying
    event_indexes = :ets.new(:event_indexes, [
      :bag, :private, {:write_concurrency, true}, {:read_concurrency, true}
    ])

    subscriptions = :ets.new(:event_subscriptions, [
      :set, :private, {:write_concurrency, true}, {:read_concurrency, true}
    ])

    state = %__MODULE__{
      namespace: namespace,
      retention_days: retention_days,
      batch_size: batch_size,
      event_store: event_store,
      event_indexes: event_indexes,
      subscriptions: subscriptions,
      batch_buffer: [],
      last_cleanup: DateTime.utc_now(),
      storage_stats: %{events_stored: 0, queries_executed: 0}
    }

    # Register with ProcessRegistry
    case ProcessRegistry.register(namespace, __MODULE__, self(), %{
      type: :event_store,
      health: :healthy,
      retention_days: retention_days
    }) do
      :ok ->
        # Schedule periodic cleanup
        schedule_cleanup()

        Telemetry.emit_counter(
          [:foundation, :services, :event_store, :started],
          %{namespace: namespace, retention_days: retention_days}
        )

        {:ok, state}

      {:error, reason} ->
        {:stop, {:registration_failed, reason}}
    end
  end

  @impl GenServer
  def handle_call({:store_event, event_data}, _from, state) do
    case store_single_event(event_data, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call({:store_events, event_list}, _from, state) do
    case store_multiple_events(event_list, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call({:query_events, filter}, _from, state) do
    result = execute_event_query(filter, state)

    # Update stats
    new_stats = Map.update(state.storage_stats, :queries_executed, 1, &(&1 + 1))
    new_state = %{state | storage_stats: new_stats}

    {:reply, result, new_state}
  end

  @impl GenServer
  def handle_call({:subscribe, pid, filter}, _from, state) do
    subscription_id = generate_subscription_id()

    subscription = %{
      pid: pid,
      filter: filter,
      subscription_id: subscription_id
    }

    :ets.insert(state.subscriptions, {subscription_id, subscription})

    # Monitor the subscriber process
    Process.monitor(pid)

    Telemetry.emit_counter(
      [:foundation, :services, :event_store, :subscription_added],
      %{subscription_id: subscription_id}
    )

    {:reply, {:ok, subscription_id}, state}
  end

  @impl GenServer
  def handle_call({:unsubscribe, subscription_id}, _from, state) do
    :ets.delete(state.subscriptions, subscription_id)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:get_stats, _from, state) do
    stats = build_storage_stats(state)
    {:reply, {:ok, stats}, state}
  end

  @impl GenServer
  def handle_info(:cleanup_old_events, state) do
    new_state = perform_cleanup(state)
    schedule_cleanup()
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove subscriptions for terminated process
    all_subscriptions = :ets.tab2list(state.subscriptions)

    Enum.each(all_subscriptions, fn {subscription_id, subscription} ->
      if subscription.pid == pid do
        :ets.delete(state.subscriptions, subscription_id)
      end
    end)

    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_message, state) do
    {:noreply, state}
  end

  # Private Implementation

  defp store_single_event(event_data, state) do
    case validate_event(event_data) do
      :ok ->
        enriched_event = enrich_event(event_data)
        store_enriched_event(enriched_event, state)
        notify_subscribers(enriched_event, state)

        # Update stats
        new_stats = Map.update(state.storage_stats, :events_stored, 1, &(&1 + 1))
        new_state = %{state | storage_stats: new_stats}

        {:ok, new_state}

      {:error, _} = error ->
        error
    end
  end

  defp store_multiple_events(event_list, state) do
    # Validate all events first
    validation_results = Enum.map(event_list, &validate_event/1)

    case Enum.find(validation_results, fn result -> match?({:error, _}, result) end) do
      nil ->
        # All events valid, enrich and store them
        enriched_events = Enum.map(event_list, &enrich_event/1)

        Enum.each(enriched_events, fn event ->
          store_enriched_event(event, state)
          notify_subscribers(event, state)
        end)

        # Update stats
        events_count = length(event_list)
        new_stats = Map.update(state.storage_stats, :events_stored, events_count, &(&1 + events_count))
        new_state = %{state | storage_stats: new_stats}

        {:ok, new_state}

      {:error, _} = error ->
        error
    end
  end

  defp validate_event(event_data) do
    case event_data do
      %{type: type} when is_atom(type) -> :ok
      _ -> {:error, validation_error("Event must have a :type field that is an atom")}
    end
  end

  defp enrich_event(event_data) do
    base_event = %{
      id: generate_event_id(),
      timestamp: DateTime.utc_now(),
      metadata: %{node: Node.self()}
    }

    # Merge with provided event data
    enriched = Map.merge(base_event, event_data)

    # Add agent context if agent_id is provided
    case Map.get(enriched, :agent_id) do
      nil -> enriched
      agent_id -> add_agent_context(enriched, agent_id)
    end
  end

  defp add_agent_context(event, agent_id) do
    case get_agent_context(agent_id) do
      {:ok, agent_context} ->
        updated_metadata = Map.merge(event.metadata, %{agent_context: agent_context})
        %{event | metadata: updated_metadata}

      :error ->
        event
    end
  end

  defp get_agent_context(agent_id) do
    case ProcessRegistry.lookup(:foundation, agent_id) do
      {:ok, _pid, metadata} ->
        context = Map.take(metadata, [:capability, :health, :resources])
        {:ok, context}

      :error ->
        :error
    end
  end

  defp store_enriched_event(event, state) do
    # Store in main event store with timestamp as key for ordering
    timestamp_key = DateTime.to_unix(event.timestamp, :microsecond)
    :ets.insert(state.event_store, {timestamp_key, event})

    # Create indexes for efficient querying
    create_event_indexes(event, timestamp_key, state)
  end

  defp create_event_indexes(event, timestamp_key, state) do
    # Index by agent_id
    if event.agent_id do
      :ets.insert(state.event_indexes, {{:agent_id, event.agent_id}, timestamp_key})
    end

    # Index by event type
    :ets.insert(state.event_indexes, {{:type, event.type}, timestamp_key})

    # Index by correlation_id
    if event.correlation_id do
      :ets.insert(state.event_indexes, {{:correlation_id, event.correlation_id}, timestamp_key})
    end
  end

  defp execute_event_query(filter, state) do
    try do
      # Use indexes to find relevant events efficiently
      timestamp_keys = find_events_by_indexes(filter, state)

      # Retrieve events and apply additional filtering
      events = retrieve_and_filter_events(timestamp_keys, filter, state)

      # Apply limit if specified
      limited_events = case Map.get(filter, :limit) do
        nil -> events
        limit -> Enum.take(events, limit)
      end

      {:ok, limited_events}
    rescue
      error ->
        {:error, query_error("Query execution failed", error)}
    end
  end

  defp find_events_by_indexes(filter, state) do
    # Start with the most selective index
    base_keys = cond do
      Map.has_key?(filter, :correlation_id) ->
        :ets.lookup(state.event_indexes, {:correlation_id, filter.correlation_id})
        |> Enum.map(fn {_index_key, timestamp_key} -> timestamp_key end)

      Map.has_key?(filter, :agent_id) ->
        :ets.lookup(state.event_indexes, {:agent_id, filter.agent_id})
        |> Enum.map(fn {_index_key, timestamp_key} -> timestamp_key end)

      Map.has_key?(filter, :type) ->
        :ets.lookup(state.event_indexes, {:type, filter.type})
        |> Enum.map(fn {_index_key, timestamp_key} -> timestamp_key end)

      true ->
        # No specific index, scan all events
        :ets.tab2list(state.event_store)
        |> Enum.map(fn {timestamp_key, _event} -> timestamp_key end)
    end

    # Apply time range filtering on timestamp keys
    apply_time_range_filter(base_keys, filter)
  end

  defp apply_time_range_filter(timestamp_keys, filter) do
    since_micros = case Map.get(filter, :since) do
      nil -> 0
      since_dt -> DateTime.to_unix(since_dt, :microsecond)
    end

    until_micros = case Map.get(filter, :until) do
      nil -> DateTime.to_unix(DateTime.utc_now(), :microsecond)
      until_dt -> DateTime.to_unix(until_dt, :microsecond)
    end

    Enum.filter(timestamp_keys, fn timestamp_key ->
      timestamp_key >= since_micros and timestamp_key <= until_micros
    end)
  end

  defp retrieve_and_filter_events(timestamp_keys, filter, state) do
    timestamp_keys
    |> Enum.sort(:desc)  # Most recent first
    |> Enum.map(fn timestamp_key ->
      case :ets.lookup(state.event_store, timestamp_key) do
        [{^timestamp_key, event}] -> event
        [] -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&event_matches_filter?(&1, filter))
  end

  defp event_matches_filter?(event, filter) do
    Enum.all?(filter, fn {key, value} ->
      case key do
        :agent_id -> event.agent_id == value
        :type -> event.type == value
        :correlation_id -> event.correlation_id == value
        :since -> DateTime.compare(event.timestamp, value) != :lt
        :until -> DateTime.compare(event.timestamp, value) != :gt
        :limit -> true  # Handled separately
        _ -> true
      end
    end)
  end

  defp notify_subscribers(event, state) do
    all_subscriptions = :ets.tab2list(state.subscriptions)

    Enum.each(all_subscriptions, fn {subscription_id, subscription} ->
      if event_matches_filter?(event, subscription.filter) do
        try do
          send(subscription.pid, {:event, subscription_id, event})
        rescue
          _ -> :ok  # Ignore send failures
        end
      end
    end)
  end

  defp perform_cleanup(state) do
    cutoff_time = DateTime.add(DateTime.utc_now(), -state.retention_days * 24 * 3600)
    cutoff_micros = DateTime.to_unix(cutoff_time, :microsecond)

    # Find old events
    old_events = :ets.select(state.event_store, [
      {{:"$1", :"$2"}, [{:<, :"$1", cutoff_micros}], [:"$1"]}
    ])

    # Delete old events and their indexes
    deleted_count = length(old_events)

    if deleted_count > 0 do
      Enum.each(old_events, fn timestamp_key ->
        case :ets.lookup(state.event_store, timestamp_key) do
          [{^timestamp_key, event}] ->
            :ets.delete(state.event_store, timestamp_key)
            delete_event_indexes(event, timestamp_key, state)

          [] -> :ok
        end
      end)

      Telemetry.emit_counter(
        [:foundation, :services, :event_store, :events_cleaned],
        %{deleted_count: deleted_count}
      )
    end

    %{state | last_cleanup: DateTime.utc_now()}
  end

  defp delete_event_indexes(event, timestamp_key, state) do
    # Remove all indexes for this event
    if event.agent_id do
      :ets.delete_object(state.event_indexes, {{:agent_id, event.agent_id}, timestamp_key})
    end

    :ets.delete_object(state.event_indexes, {{:type, event.type}, timestamp_key})

    if event.correlation_id do
      :ets.delete_object(state.event_indexes, {{:correlation_id, event.correlation_id}, timestamp_key})
    end
  end

  defp build_storage_stats(state) do
    event_count = :ets.info(state.event_store, :size)
    index_count = :ets.info(state.event_indexes, :size)
    subscription_count = :ets.info(state.subscriptions, :size)

    Map.merge(state.storage_stats, %{
      event_count: event_count,
      index_count: index_count,
      subscription_count: subscription_count,
      last_cleanup: state.last_cleanup,
      retention_days: state.retention_days
    })
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup_old_events, @cleanup_interval_ms)
  end

  defp generate_event_id do
    :crypto.strong_rand_bytes(16)
    |> Base.url_encode64(padding: false)
  end

  defp generate_subscription_id do
    :crypto.strong_rand_bytes(8)
    |> Base.url_encode64(padding: false)
  end

  defp service_name(namespace) do
    :"Foundation.Services.EventStore.#{namespace}"
  end

  # Error Helper Functions

  defp event_store_error(message, error) do
    Error.new(
      code: 9101,
      error_type: :event_store_error,
      message: "Event store error: #{message}",
      severity: :medium,
      context: %{error: error}
    )
  end

  defp validation_error(message) do
    Error.new(
      code: 9102,
      error_type: :event_validation_failed,
      message: "Event validation failed: #{message}",
      severity: :medium,
      context: %{validation_message: message}
    )
  end

  defp query_error(message, error) do
    Error.new(
      code: 9103,
      error_type: :event_query_failed,
      message: "Event query failed: #{message}",
      severity: :medium,
      context: %{error: error}
    )
  end
end