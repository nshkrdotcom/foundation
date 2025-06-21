defmodule Foundation.Events do
  @moduledoc """
  Public API for event management and storage.

  Thin wrapper around EventStore that provides a clean, documented interface.
  All business logic is delegated to the service layer.
  """

  @behaviour Foundation.Contracts.EventStore

  alias Foundation.Services.EventStore
  alias Foundation.Types.{Event, Error}

  @type event_id :: Event.event_id()
  @type correlation_id :: Event.correlation_id()
  @type event_query :: map()

  @doc """
  Initialize the event store service.

  ## Examples

      iex> Foundation.Events.initialize()
      :ok
  """
  @spec initialize() :: :ok | {:error, Error.t()}
  def initialize do
    EventStore.initialize()
  end

  @doc """
  Get event store service status.

  ## Examples

      iex> Foundation.Events.status()
      {:ok, %{status: :running, uptime: 12_345}}
  """
  @spec status() :: {:ok, map()} | {:error, Error.t()}
  def status do
    EventStore.status()
  end

  @doc """
  Check if the Events service is available.

  ## Examples

      iex> Foundation.Events.available?()
      true
  """
  @spec available?() :: boolean()
  defdelegate available?(), to: EventStore

  @doc """
  Create a new event with the given type and data.

  ## Examples

      iex> Foundation.Events.new_event(:test_event, %{key: "value"})
      {:ok, %Event{event_type: :test_event, data: %{key: "value"}}}

      iex> Foundation.Events.new_event(:invalid, nil)
      {:error, %Error{error_type: :invalid_event_data}}
  """
  @spec new_event(atom(), term()) :: {:ok, Event.t()} | {:error, Error.t()}
  def new_event(event_type, data, opts \\ []) do
    alias Foundation.Logic.EventLogic
    EventLogic.create_event(event_type, data, opts)
  end

  @doc """
  Create a new event for debugging/testing (returns event directly, not tuple).

  ## Examples

      iex> Foundation.Events.debug_new_event(:test_event, %{key: "value"})
      %Event{event_type: :test_event, data: %{key: "value"}}
  """
  @spec debug_new_event(atom(), term(), keyword()) :: Event.t()
  def debug_new_event(event_type, data, opts \\ []) do
    case new_event(event_type, data, opts) do
      {:ok, event} -> event
      {:error, _error} -> raise "Failed to create debug event"
    end
  end

  @doc """
  Serialize an event to binary format.

  ## Examples

      iex> {:ok, event} = Events.new_event(:test, %{})
      iex> Foundation.Events.serialize(event)
      {:ok, <<...>>}
  """
  @spec serialize(Event.t()) :: {:ok, binary()} | {:error, Error.t()}
  def serialize(event) do
    alias Foundation.Logic.EventLogic
    EventLogic.serialize_event(event)
  end

  @doc """
  Deserialize binary data back to an event.

  ## Examples

      iex> {:ok, serialized} = Events.serialize(event)
      iex> Foundation.Events.deserialize(serialized)
      {:ok, %Event{...}}
  """
  @spec deserialize(binary()) :: {:ok, Event.t()} | {:error, Error.t()}
  def deserialize(binary) do
    alias Foundation.Logic.EventLogic
    EventLogic.deserialize_event(binary)
  end

  @doc """
  Calculate the serialized size of an event.

  ## Examples

      iex> {:ok, event} = Events.new_event(:test, %{})
      iex> Foundation.Events.serialized_size(event)
      {:ok, 156}
  """
  @spec serialized_size(Event.t()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def serialized_size(event) do
    alias Foundation.Logic.EventLogic
    EventLogic.calculate_serialized_size(event)
  end

  @doc """
  Create a function entry event (convenience function).

  ## Examples

      iex> Foundation.Events.function_entry(MyModule, :my_func, 2, [arg1, arg2])
      {:ok, %Event{event_type: :function_entry, ...}}
  """
  @spec function_entry(module(), atom(), arity(), [term()], keyword()) ::
          {:ok, Event.t()} | {:error, Error.t()}
  def function_entry(module, function, arity, args, opts \\ []) do
    alias Foundation.Logic.EventLogic
    EventLogic.create_function_entry(module, function, arity, args, opts)
  end

  @doc """
  Create a function exit event (convenience function).

  ## Examples

      iex> Foundation.Events.function_exit(MyModule, :my_func, 2, 123, :ok, 1000, :normal)
      {:ok, %Event{event_type: :function_exit, ...}}
  """
  @spec function_exit(module(), atom(), arity(), pos_integer(), term(), non_neg_integer(), atom()) ::
          {:ok, Event.t()} | {:error, Error.t()}
  def function_exit(module, function, arity, call_id, result, duration_ns, exit_reason) do
    alias Foundation.Logic.EventLogic

    EventLogic.create_function_exit(
      module,
      function,
      arity,
      call_id,
      result,
      duration_ns,
      exit_reason
    )
  end

  @doc """
  Create a state change event (convenience function).

  ## Examples

      iex> Foundation.Events.state_change(self(), :handle_call, old_state, new_state)
      {:ok, %Event{event_type: :state_change, ...}}
  """
  @spec state_change(pid(), atom(), term(), term(), keyword()) ::
          {:ok, Event.t()} | {:error, Error.t()}
  def state_change(server_pid, callback, old_state, new_state, opts \\ []) do
    alias Foundation.Logic.EventLogic
    EventLogic.create_state_change(server_pid, callback, old_state, new_state, opts)
  end

  @doc """
  Store a single event.

  Accepts both Event structs and {:ok, Event} tuples for pipe-friendly usage.

  ## Examples

      iex> {:ok, event} = Event.new(event_type: :test, data: %{key: "value"})
      iex> Foundation.Events.store(event)
      {:ok, 12_345}

      iex> Foundation.Events.new_event(:test, %{key: "value"}) |> Foundation.Events.store()
      {:ok, 12_345}
  """
  @spec store(Event.t() | {:ok, Event.t()}) :: {:ok, event_id()} | {:error, Error.t()}
  defdelegate store(event_or_tuple), to: EventStore

  @doc """
  Store multiple events atomically.

  ## Examples

      iex> events = [event1, event2, event3]
      iex> Foundation.Events.store_batch(events)
      {:ok, [12_345, 12346, 12347]}
  """
  @spec store_batch([Event.t()]) :: {:ok, [event_id()]} | {:error, Error.t()}
  defdelegate store_batch(events), to: EventStore

  @doc """
  Retrieve an event by ID.

  ## Examples

      iex> Foundation.Events.get(12_345)
      {:ok, %Event{event_id: 12_345, ...}}

      iex> Foundation.Events.get(99_999)
      {:error, %Error{error_type: :not_found}}
  """
  @spec get(event_id()) :: {:ok, Event.t()} | {:error, Error.t()}
  defdelegate get(event_id), to: EventStore

  @doc """
  Query events with filters and pagination.

  ## Examples

      iex> query = [event_type: :function_entry, limit: 10]
      iex> Foundation.Events.query(query)
      {:ok, [%Event{}, ...]}

      iex> query = [time_range: {start_time, end_time}, order_by: :timestamp]
      iex> Foundation.Events.query(query)
      {:ok, [%Event{}, ...]}
  """
  @spec query(event_query()) :: {:ok, [Event.t()]} | {:error, Error.t()}
  def query(query_opts) when is_map(query_opts) do
    EventStore.query(query_opts)
  end

  def query(query_opts) when is_list(query_opts) do
    query_map = Map.new(query_opts)
    EventStore.query(query_map)
  end

  @doc """
  Get events by correlation ID.

  ## Examples

      iex> Foundation.Events.get_by_correlation("req-123")
      {:ok, [%Event{correlation_id: "req-123"}, ...]}
  """
  @spec get_by_correlation(correlation_id()) :: {:ok, [Event.t()]} | {:error, Error.t()}
  defdelegate get_by_correlation(correlation_id), to: EventStore

  @doc """
  Delete events older than the specified timestamp.

  ## Examples

      iex> cutoff = System.monotonic_time() - 3600_000  # 1 hour ago
      iex> Foundation.Events.prune_before(cutoff)
      {:ok, 150}  # 150 events pruned
  """
  @spec prune_before(integer()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  defdelegate prune_before(timestamp), to: EventStore

  @doc """
  Get storage statistics.

  ## Examples

      iex> Foundation.Events.stats()
      {:ok, %{
        current_event_count: 1000,
        events_stored: 5000,
        events_pruned: 200,
        memory_usage_estimate: 1024000,
        uptime_ms: 3600000
      }}
  """
  @spec stats() :: {:ok, map()} | {:error, Error.t()}
  defdelegate stats(), to: EventStore

  @doc """
  Extract correlation chain from stored events.

  ## Examples

      iex> Foundation.Events.get_correlation_chain("req-123")
      {:ok, [%Event{}, ...]}  # Events in chronological order
  """
  @spec get_correlation_chain(correlation_id()) :: {:ok, [Event.t()]} | {:error, Error.t()}
  def get_correlation_chain(correlation_id) do
    case get_by_correlation(correlation_id) do
      {:ok, events} ->
        alias Foundation.Logic.EventLogic
        chain = EventLogic.extract_correlation_chain(events, correlation_id)
        {:ok, chain}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Get events within a time range.

  ## Examples

      iex> start_time = System.monotonic_time() - 3600_000
      iex> end_time = System.monotonic_time()
      iex> Foundation.Events.get_time_range(start_time, end_time)
      {:ok, [%Event{}, ...]}
  """
  @spec get_time_range(integer(), integer()) :: {:ok, [Event.t()]} | {:error, Error.t()}
  def get_time_range(start_time, end_time) do
    query(%{
      time_range: {start_time, end_time},
      order_by: :timestamp
    })
  end

  @doc """
  Get recent events with optional limit.

  ## Examples

      iex> Foundation.Events.get_recent(50)
      {:ok, [%Event{}, ...]}  # Last 50 events
  """
  @spec get_recent(non_neg_integer()) :: {:ok, [Event.t()]} | {:error, Error.t()}
  def get_recent(limit \\ 100) do
    query(%{
      order_by: :timestamp,
      limit: limit
    })
  end
end

# defmodule Foundation.Events do
#   @moduledoc """
#   Core event system for Foundation.

#   Provides structured event creation, serialization, and basic event management.
#   This is the foundation for all event-driven communication within Foundation.
#   """

#   require Logger

#   alias Foundation.{Types, Utils, Error, ErrorContext}

#   @type event_id :: Types.event_id()
#   @type timestamp :: Types.timestamp()
#   @type correlation_id :: Types.correlation_id()

#   # Base event structure
#   defstruct [
#     :event_id,
#     :event_type,
#     :timestamp,
#     :wall_time,
#     :node,
#     :pid,
#     :correlation_id,
#     :parent_id,
#     :data
#   ]

#   @type t :: %__MODULE__{
#           event_id: event_id(),
#           event_type: atom(),
#           timestamp: timestamp(),
#           wall_time: DateTime.t(),
#           node: node(),
#           pid: pid(),
#           correlation_id: correlation_id() | nil,
#           parent_id: event_id() | nil,
#           data: term()
#         }

#   ## System Management

#   @spec initialize() :: :ok
#   def initialize do
#     Logger.debug("Foundation.Events initialized")
#     :ok
#   end

#   @spec status() :: :ok
#   def status, do: :ok

#   ## Event Creation

#   @spec new_event(atom(), term(), keyword()) :: t() | {:error, Error.t()}
#   def new_event(event_type, data, opts \\ []) do
#     context =
#       ErrorContext.new(__MODULE__, :new_event, metadata: %{event_type: event_type, opts: opts})

#     ErrorContext.with_context(context, fn ->
#       event = %__MODULE__{
#         event_id: Utils.generate_id(),
#         event_type: event_type,
#         timestamp: Utils.monotonic_timestamp(),
#         wall_time: DateTime.utc_now(),
#         node: Node.self(),
#         pid: self(),
#         correlation_id: Keyword.get(opts, :correlation_id),
#         parent_id: Keyword.get(opts, :parent_id),
#         data: data
#       }

#       case validate_event(event) do
#         :ok -> event
#         {:error, _} = error -> error
#       end
#     end)
#   end

#   @spec function_entry(module(), atom(), arity(), [term()], keyword()) :: t() | {:error, Error.t()}
#   def function_entry(module, function, arity, args, opts \\ []) do
#     data = %{
#       call_id: Utils.generate_id(),
#       module: module,
#       function: function,
#       arity: arity,
#       args: Utils.truncate_if_large(args),
#       caller_module: Keyword.get(opts, :caller_module),
#       caller_function: Keyword.get(opts, :caller_function),
#       caller_line: Keyword.get(opts, :caller_line)
#     }

#     new_event(:function_entry, data, opts)
#   end

#   @spec function_exit(module(), atom(), arity(), event_id(), term(), non_neg_integer(), atom()) ::
#           t() | {:error, Error.t()}
#   def function_exit(module, function, arity, call_id, result, duration_ns, exit_reason) do
#     data = %{
#       call_id: call_id,
#       module: module,
#       function: function,
#       arity: arity,
#       result: Utils.truncate_if_large(result),
#       duration_ns: duration_ns,
#       exit_reason: exit_reason
#     }

#     new_event(:function_exit, data)
#   end

#   @spec state_change(pid(), atom(), term(), term(), keyword()) :: t() | {:error, Error.t()}
#   def state_change(server_pid, callback, old_state, new_state, opts \\ []) do
#     data = %{
#       server_pid: server_pid,
#       callback: callback,
#       old_state: Utils.truncate_if_large(old_state),
#       new_state: Utils.truncate_if_large(new_state),
#       state_diff: compute_state_diff(old_state, new_state),
#       trigger_message: Keyword.get(opts, :trigger_message),
#       trigger_call_id: Keyword.get(opts, :trigger_call_id)
#     }

#     new_event(:state_change, data)
#   end

#   ## Event Serialization

#   @spec serialize(t()) :: binary() | {:error, Error.t()}
#   # def serialize(%__MODULE__{} = event) do
#   #   context = ErrorContext.new(__MODULE__, :serialize)

#   #   ErrorContext.with_context(context, fn ->
#   #     :erlang.term_to_binary(event, [:compressed])
#   #   end)
#   # end
#   def serialize(event) do
#     IO.puts("🔧 Events.serialize called with: #{inspect(event, limit: :infinity)}")

#     try do
#       # Check if event contains unserializable data BEFORE trying to serialize
#       case event.data do
#         %{bad_field: pid} when is_pid(pid) ->
#           IO.puts("💥 Found PID in data, forcing serialization failure")
#           raise ArgumentError, "Cannot serialize PID in event data"

#         _ ->
#           :ok
#       end

#       result = :erlang.term_to_binary(event)
#       IO.puts("✅ Events.serialize SUCCESS - binary size: #{byte_size(result)}")
#       result
#     rescue
#       error ->
#         IO.puts("❌ Events.serialize FAILED: #{inspect(error)}")
#         {:error, error}
#     catch
#       :throw, value ->
#         IO.puts("❌ Events.serialize THROWN: #{inspect(value)}")
#         {:error, value}

#       :exit, reason ->
#         IO.puts("❌ Events.serialize EXIT: #{inspect(reason)}")
#         {:error, reason}
#     end
#   end

#   def debug_new_event(event_type, data, opts \\ []) do
#     IO.puts("🔧 Events.new_event called")
#     IO.puts("📥 event_type: #{inspect(event_type)}")
#     IO.puts("📥 data: #{inspect(data, limit: :infinity)}")
#     IO.puts("📥 opts: #{inspect(opts)}")

#     result = new_event(event_type, data, opts)
#     IO.puts("📤 new_event result: #{inspect(result, limit: :infinity)}")
#     result
#   end

#   @spec deserialize(binary()) :: t() | {:error, Error.t()}
#   def deserialize(binary) when is_binary(binary) do
#     context = ErrorContext.new(__MODULE__, :deserialize)

#     ErrorContext.with_context(context, fn ->
#       event = :erlang.binary_to_term(binary)

#       case validate_event(event) do
#         :ok -> event
#         {:error, _} = error -> error
#       end
#     end)
#   end

#   @spec serialized_size(t()) :: non_neg_integer()
#   def serialized_size(%__MODULE__{} = event) do
#     case serialize(event) do
#       {:error, _} -> 0
#       binary when is_binary(binary) -> byte_size(binary)
#     end
#   end

#   ## Private Validation

#   @spec validate_event(t()) :: :ok | {:error, Error.t()}
#   defp validate_event(%__MODULE__{} = event) do
#     cond do
#       is_nil(event.event_id) ->
#         Error.error_result(:validation_failed, "Event ID cannot be nil")

#       not is_atom(event.event_type) ->
#         Error.error_result(:type_mismatch, "Event type must be an atom")

#       not is_integer(event.timestamp) ->
#         Error.error_result(:type_mismatch, "Timestamp must be an integer")

#       true ->
#         :ok
#     end
#   end

#   defp validate_event(_) do
#     Error.error_result(:type_mismatch, "Expected Events struct")
#   end

#   ## Private Helper Functions

#   @spec compute_state_diff(term(), term()) :: :no_change | :changed
#   defp compute_state_diff(old_state, new_state) do
#     if old_state == new_state do
#       :no_change
#     else
#       :changed
#     end
#   end
# end

# # ## Event Creation

# # @spec new_event(atom(), term(), keyword()) :: t()
# # def new_event(event_type, data, opts \\ []) do
# #   %__MODULE__{
# #     event_id: Utils.generate_id(),
# #     event_type: event_type,
# #     timestamp: Utils.monotonic_timestamp(),
# #     wall_time: DateTime.utc_now(),
# #     node: Node.self(),
# #     pid: self(),
# #     correlation_id: Keyword.get(opts, :correlation_id),
# #     parent_id: Keyword.get(opts, :parent_id),
# #     data: data
# #   }
# # end

# # @spec function_entry(module(), atom(), arity(), [term()], keyword()) :: t()
# # def function_entry(module, function, arity, args, opts \\ []) do
# #   data = %{
# #     call_id: Utils.generate_id(),
# #     module: module,
# #     function: function,
# #     arity: arity,
# #     args: Utils.truncate_if_large(args),
# #     caller_module: Keyword.get(opts, :caller_module),
# #     caller_function: Keyword.get(opts, :caller_function),
# #     caller_line: Keyword.get(opts, :caller_line)
# #   }

# #   new_event(:function_entry, data, opts)
# # end

# # @spec function_exit(module(), atom(), arity(), event_id(), term(), non_neg_integer(), atom()) :: t()
# # def function_exit(module, function, arity, call_id, result, duration_ns, exit_reason) do
# #   data = %{
# #     call_id: call_id,
# #     module: module,
# #     function: function,
# #     arity: arity,
# #     result: Utils.truncate_if_large(result),
# #     duration_ns: duration_ns,
# #     exit_reason: exit_reason
# #   }

# #   new_event(:function_exit, data)
# # end

# # @spec state_change(pid(), atom(), term(), term(), keyword()) :: t()
# # def state_change(server_pid, callback, old_state, new_state, opts \\ []) do
# #   data = %{
# #     server_pid: server_pid,
# #     callback: callback,
# #     old_state: Utils.truncate_if_large(old_state),
# #     new_state: Utils.truncate_if_large(new_state),
# #     state_diff: compute_state_diff(old_state, new_state),
# #     trigger_message: Keyword.get(opts, :trigger_message),
# #     trigger_call_id: Keyword.get(opts, :trigger_call_id)
# #   }

# #   new_event(:state_change, data)
# # end

# # ## Event Processing

# # @spec serialize(t()) :: binary()
# # def serialize(%__MODULE__{} = event) do
# #   :erlang.term_to_binary(event, [:compressed])
# # end

# # @spec deserialize(binary()) :: t()
# # def deserialize(binary) when is_binary(binary) do
# #   :erlang.binary_to_term(binary)
# # end

# # @spec serialized_size(t()) :: non_neg_integer()
# # def serialized_size(%__MODULE__{} = event) do
# #   event |> serialize() |> byte_size()
# # end

# ## Private Functions

# # defp compute_state_diff(old_state, new_state) do
# #   if old_state == new_state do
# #     :no_change
# #   else
# #     :changed
# #   end
# # end
# # end
