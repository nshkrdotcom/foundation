defmodule Foundation.Services.EventStore do
  @moduledoc """
  Event storage service implementation using GenServer.

  Provides persistent event storage with querying capabilities.
  """

  use GenServer
  require Logger

  alias Foundation.{Services.TelemetryService}
  alias Foundation.Types.{Event, Error}
  alias Foundation.Validation.EventValidator
  alias Foundation.Contracts.EventStore, as: EventStoreContract

  @behaviour EventStoreContract

  @type server_state :: %{
          events: %{non_neg_integer() => Event.t()},
          next_id: non_neg_integer(),
          metrics: map()
        }

  ## Public API (EventStore Behaviour Implementation)

  @impl EventStoreContract
  @spec store(Event.t() | {:ok, Event.t()}) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def store(event_or_tuple) do
    # Handle both direct Event.t() and {:ok, Event.t()} for pipe-friendly API
    case event_or_tuple do
      {:ok, %Event{} = event} ->
        case Foundation.ServiceRegistry.lookup(:production, :event_store) do
          {:ok, pid} -> GenServer.call(pid, {:store_event, event})
          {:error, _} -> create_service_error("Event store not available")
        end

      %Event{} = event ->
        case Foundation.ServiceRegistry.lookup(:production, :event_store) do
          {:ok, pid} -> GenServer.call(pid, {:store_event, event})
          {:error, _} -> create_service_error("Event store not available")
        end

      {:error, _} = error ->
        error

      _ ->
        {:error,
         Error.new(
           code: 2005,
           error_type: :invalid_argument,
           message: "Expected Event struct or {:ok, Event} tuple",
           severity: :high,
           context: %{received: event_or_tuple},
           category: :data,
           subcategory: :validation
         )}
    end
  end

  @impl EventStoreContract
  @spec store_batch([Event.t()]) :: {:ok, [non_neg_integer()]} | {:error, Error.t()}
  def store_batch(events) when is_list(events) do
    case Foundation.ServiceRegistry.lookup(:production, :event_store) do
      {:ok, pid} -> GenServer.call(pid, {:store_batch, events})
      {:error, _} -> create_service_error("Event store not available")
    end
  end

  @impl EventStoreContract
  @spec get(non_neg_integer()) :: {:ok, Event.t()} | {:error, Error.t()}
  def get(event_id) when is_integer(event_id) and event_id > 0 do
    case Foundation.ServiceRegistry.lookup(:production, :event_store) do
      {:ok, pid} -> GenServer.call(pid, {:get_event, event_id})
      {:error, _} -> create_service_error("Event store not available")
    end
  end

  @impl EventStoreContract
  @spec query(map()) :: {:ok, [Event.t()]} | {:error, Error.t()}
  def query(query_map) when is_map(query_map) do
    case Foundation.ServiceRegistry.lookup(:production, :event_store) do
      {:ok, pid} -> GenServer.call(pid, {:query_events, query_map})
      {:error, _} -> create_service_error("Event store not available")
    end
  end

  @impl EventStoreContract
  @spec get_by_correlation(String.t()) :: {:ok, [Event.t()]} | {:error, Error.t()}
  def get_by_correlation(correlation_id) when is_binary(correlation_id) do
    case Foundation.ServiceRegistry.lookup(:production, :event_store) do
      {:ok, pid} -> GenServer.call(pid, {:get_by_correlation, correlation_id})
      {:error, _} -> create_service_error("Event store not available")
    end
  end

  @impl EventStoreContract
  @spec prune_before(integer()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def prune_before(timestamp) when is_integer(timestamp) do
    case Foundation.ServiceRegistry.lookup(:production, :event_store) do
      {:ok, pid} -> GenServer.call(pid, {:prune_before, timestamp})
      {:error, _} -> create_service_error("Event store not available")
    end
  end

  @impl EventStoreContract
  @spec stats() :: {:ok, map()} | {:error, Error.t()}
  def stats do
    case Foundation.ServiceRegistry.lookup(:production, :event_store) do
      {:ok, pid} -> GenServer.call(pid, :get_stats)
      {:error, _} -> create_service_error("Event store not available")
    end
  end

  @impl EventStoreContract
  @spec available?() :: boolean()
  def available? do
    case Foundation.ServiceRegistry.lookup(:production, :event_store) do
      {:ok, _pid} -> true
      {:error, _} -> false
    end
  end

  @impl EventStoreContract
  @spec initialize() :: :ok | {:error, Error.t()}
  def initialize do
    initialize([])
  end

  # Note: initialize/1 is not in the contract but we need it for internal use
  @spec initialize(keyword()) :: :ok | {:error, Error.t()}
  def initialize(opts) do
    case Foundation.ServiceRegistry.lookup(:production, :event_store) do
      {:ok, _pid} ->
        :ok

      {:error, _} ->
        case start_link(opts) do
          {:ok, _pid} ->
            :ok

          {:error, {:already_started, _pid}} ->
            :ok

          {:error, reason} ->
            create_service_error("Failed to initialize event store: #{inspect(reason)}")
        end
    end
  end

  @impl EventStoreContract
  @spec status() :: {:ok, map()} | {:error, Error.t()}
  def status do
    case Foundation.ServiceRegistry.lookup(:production, :event_store) do
      {:ok, pid} -> GenServer.call(pid, :get_status)
      {:error, _} -> create_service_error("Event store not available")
    end
  end

  @doc """
  Reset all stored events and metrics for testing purposes.

  This function should only be used in test environments.
  """
  @spec reset_state() :: :ok | {:error, Error.t()}
  def reset_state do
    if Application.get_env(:foundation, :test_mode, false) do
      case Foundation.ServiceRegistry.lookup(:production, :event_store) do
        {:ok, pid} -> GenServer.call(pid, :reset_state)
        {:error, _} -> create_service_error("Event store not available")
      end
    else
      {:error,
       Error.new(
         code: 3002,
         error_type: :operation_forbidden,
         message: "State reset only allowed in test mode",
         severity: :high,
         category: :security,
         subcategory: :authorization
       )}
    end
  end

  ## GenServer API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    namespace = Keyword.get(opts, :namespace, :production)
    name = Foundation.ServiceRegistry.via_tuple(namespace, :event_store)
    GenServer.start_link(__MODULE__, Keyword.put(opts, :namespace, namespace), name: name)
  end

  @spec stop() :: :ok
  def stop do
    case Foundation.ServiceRegistry.lookup(:production, :event_store) do
      {:ok, pid} -> GenServer.stop(pid)
      {:error, _} -> :ok
    end
  end

  ## GenServer Callbacks

  @impl GenServer
  @spec init(keyword()) :: {:ok, server_state()}
  def init(_opts) do
    state = %{
      events: %{},
      next_id: 1,
      metrics: %{
        events_stored: 0,
        events_pruned: 0,
        start_time: System.monotonic_time(:millisecond)
      }
    }

    case Application.get_env(:foundation, :test_mode, false) do
      false -> Logger.info("Event store initialized successfully")
      _ -> :ok
    end

    {:ok, state}
  end

  @impl GenServer
  @spec handle_call(term(), GenServer.from(), server_state()) ::
          {:reply, term(), server_state()}
  def handle_call({:store_event, event}, _from, state) do
    case EventValidator.validate(event) do
      :ok ->
        # Use event's ID if provided, otherwise assign next available ID
        event_id =
          if event.event_id && event.event_id > 0 do
            event.event_id
          else
            state.next_id
          end

        updated_event = %{event | event_id: event_id}
        new_events = Map.put(state.events, event_id, updated_event)

        new_next_id = max(state.next_id, event_id) + 1
        new_metrics = Map.update!(state.metrics, :events_stored, &(&1 + 1))

        new_state = %{
          state
          | events: new_events,
            next_id: new_next_id,
            metrics: new_metrics
        }

        # Emit telemetry for events stored
        TelemetryService.emit_counter([:foundation, :event_store, :events_stored], 1, %{
          event_type: updated_event.event_type,
          event_id: event_id
        })

        {:reply, {:ok, event_id}, new_state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call({:store_batch, events}, _from, state) do
    # Validate all events first
    case validate_batch(events) do
      :ok ->
        {new_state, event_ids} = store_events_batch(events, state)
        {:reply, {:ok, event_ids}, new_state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  @impl GenServer
  def handle_call({:get_event, event_id}, _from, %{events: events} = state) do
    case Map.get(events, event_id) do
      nil ->
        error =
          Error.new(
            code: 3001,
            error_type: :not_found,
            message: "Event not found",
            severity: :low,
            context: %{event_id: event_id},
            category: :data,
            subcategory: :retrieval
          )

        {:reply, {:error, error}, state}

      event ->
        {:reply, {:ok, event}, state}
    end
  end

  @impl GenServer
  def handle_call({:query_events, query_map}, _from, %{events: events} = state) do
    filtered_events = apply_query_filters(events, query_map)
    {:reply, {:ok, filtered_events}, state}
  end

  @impl GenServer
  def handle_call({:get_by_correlation, correlation_id}, _from, %{events: events} = state) do
    correlated_events =
      events
      |> Map.values()
      |> Enum.filter(fn event -> event.correlation_id == correlation_id end)
      |> Enum.sort_by(& &1.timestamp)

    {:reply, {:ok, correlated_events}, state}
  end

  @impl GenServer
  def handle_call({:prune_before, cutoff_timestamp}, _from, %{events: events} = state) do
    {remaining_events, pruned_count} =
      Enum.reduce(events, {%{}, 0}, fn {id, event}, {acc_events, count} ->
        if event.timestamp < cutoff_timestamp do
          {acc_events, count + 1}
        else
          {Map.put(acc_events, id, event), count}
        end
      end)

    new_metrics = Map.update!(state.metrics, :events_pruned, &(&1 + pruned_count))
    new_state = %{state | events: remaining_events, metrics: new_metrics}

    {:reply, {:ok, pruned_count}, new_state}
  end

  @impl GenServer
  def handle_call(:get_stats, _from, %{events: events, metrics: metrics} = state) do
    current_time = System.monotonic_time(:millisecond)

    stats =
      Map.merge(metrics, %{
        current_event_count: map_size(events),
        uptime_ms: current_time - metrics.start_time,
        memory_usage_estimate: estimate_memory_usage(events)
      })

    {:reply, {:ok, stats}, state}
  end

  @impl GenServer
  def handle_call(:get_status, _from, %{events: events} = state) do
    status = %{
      status: :running,
      event_count: map_size(events),
      next_id: state.next_id
    }

    {:reply, {:ok, status}, state}
  end

  @impl GenServer
  def handle_call(:reset_state, _from, _state) do
    # Reset to initial state (for testing)
    new_state = %{
      events: %{},
      next_id: 1,
      metrics: %{
        events_stored: 0,
        events_pruned: 0,
        start_time: System.monotonic_time(:millisecond)
      }
    }

    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call(:health_status, _from, state) do
    # Health check for application monitoring
    health =
      if map_size(state.events) >= 0 do
        :healthy
      else
        :degraded
      end

    {:reply, {:ok, health}, state}
  end

  @impl GenServer
  def handle_call(:ping, _from, state) do
    # Simple ping for response time measurement
    {:reply, :pong, state}
  end

  # Catch-all for unsupported operations (security protection)
  @impl GenServer
  def handle_call(unsupported_operation, _from, state) do
    Logger.warning("Attempted unsupported EventStore operation: #{inspect(unsupported_operation)}")

    operation_name =
      case unsupported_operation do
        {op, _} -> op
        {op, _, _} -> op
        op when is_atom(op) -> op
        _ -> :unknown
      end

    error =
      Error.new(
        code: 4001,
        error_type: :operation_not_supported,
        message:
          "EventStore operation not supported for security reasons: #{inspect(operation_name)}",
        severity: :medium,
        context: %{operation: operation_name},
        category: :security,
        subcategory: :access_control
      )

    {:reply, {:error, error}, state}
  end

  @impl GenServer
  def handle_info(msg, state) do
    Logger.warning("Unexpected message in EventStore: #{inspect(msg)}")
    {:noreply, state}
  end

  ## Private Functions

  @spec validate_batch([Event.t()]) :: :ok | {:error, Error.t()}
  defp validate_batch(events) do
    Enum.reduce_while(events, :ok, fn event, :ok ->
      case EventValidator.validate(event) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  @spec store_events_batch([Event.t()], server_state()) :: {server_state(), [non_neg_integer()]}
  defp store_events_batch(events, state) do
    {new_state, event_ids} =
      Enum.reduce(events, {state, []}, fn event, {acc_state, acc_ids} ->
        event_id =
          if event.event_id && event.event_id > 0 do
            event.event_id
          else
            acc_state.next_id
          end

        updated_event = %{event | event_id: event_id}
        new_events = Map.put(acc_state.events, event_id, updated_event)
        new_next_id = max(acc_state.next_id, event_id) + 1

        updated_state = %{
          acc_state
          | events: new_events,
            next_id: new_next_id
        }

        {updated_state, [event_id | acc_ids]}
      end)

    # Update metrics
    events_count = length(events)
    new_metrics = Map.update!(new_state.metrics, :events_stored, &(&1 + events_count))
    final_state = %{new_state | metrics: new_metrics}

    # Emit telemetry for batch events stored
    TelemetryService.emit_counter([:foundation, :event_store, :events_stored], events_count, %{
      batch_size: events_count
    })

    {final_state, Enum.reverse(event_ids)}
  end

  @spec apply_query_filters(map(), map()) :: [Event.t()]
  defp apply_query_filters(events, query_map) do
    events
    |> Map.values()
    |> filter_by_event_type(query_map[:event_type])
    |> filter_by_time_range(query_map[:time_range])
    |> apply_pagination(query_map)
  end

  @spec filter_by_event_type([Event.t()], atom() | nil) :: [Event.t()]
  defp filter_by_event_type(events, nil), do: events

  defp filter_by_event_type(events, event_type) do
    Enum.filter(events, fn event -> event.event_type == event_type end)
  end

  @spec filter_by_time_range([Event.t()], {integer(), integer()} | nil) :: [Event.t()]
  defp filter_by_time_range(events, nil), do: events

  defp filter_by_time_range(events, {start_time, end_time}) do
    Enum.filter(events, fn event ->
      event.timestamp >= start_time && event.timestamp <= end_time
    end)
  end

  @spec apply_pagination([Event.t()], map()) :: [Event.t()]
  defp apply_pagination(events, query_map) do
    events
    |> maybe_sort(query_map[:order_by])
    |> maybe_offset(query_map[:offset])
    |> maybe_limit(query_map[:limit])
  end

  @spec maybe_sort([Event.t()], atom() | nil) :: [Event.t()]
  defp maybe_sort(events, nil), do: events
  defp maybe_sort(events, :event_id), do: Enum.sort_by(events, & &1.event_id)
  defp maybe_sort(events, :timestamp), do: Enum.sort_by(events, & &1.timestamp)
  defp maybe_sort(events, _), do: events

  @spec maybe_offset([Event.t()], non_neg_integer() | nil) :: [Event.t()]
  defp maybe_offset(events, nil), do: events
  defp maybe_offset(events, offset) when offset >= 0, do: Enum.drop(events, offset)
  defp maybe_offset(events, _), do: events

  @spec maybe_limit([Event.t()], pos_integer() | nil) :: [Event.t()]
  defp maybe_limit(events, nil), do: events
  defp maybe_limit(events, limit) when limit > 0, do: Enum.take(events, limit)
  defp maybe_limit(events, _), do: events

  @spec estimate_memory_usage(map()) :: non_neg_integer()
  defp estimate_memory_usage(events) do
    # Simple estimation - in a real implementation this might be more sophisticated
    # Rough estimate of 1KB per event
    map_size(events) * 1000
  end

  @spec create_service_error(String.t()) :: {:error, Error.t()}
  defp create_service_error(message) do
    error =
      Error.new(
        code: 3000,
        error_type: :service_unavailable,
        message: message,
        severity: :high,
        category: :system,
        subcategory: :availability
      )

    {:error, error}
  end
end
