defmodule Foundation.Logic.EventLogic do
  @moduledoc """
  Pure business logic functions for event operations.

  Contains event creation, transformation, and analysis logic.
  No side effects - all functions are pure and easily testable.
  """

  alias Foundation.Types.{Event, Error}
  alias Foundation.Validation.EventValidator
  alias Foundation.Utils

  @type event_opts :: keyword()
  @type serialization_opts :: keyword()

  @doc """
  Create a new event with the given parameters.
  """
  @spec create_event(atom(), term(), event_opts()) :: {:ok, Event.t()} | {:error, Error.t()}
  def create_event(event_type, data, opts \\ []) do
    event =
      Event.new(
        event_id: Keyword.get(opts, :event_id, Utils.generate_id()),
        event_type: event_type,
        timestamp: Keyword.get(opts, :timestamp, Utils.monotonic_timestamp()),
        wall_time: Keyword.get(opts, :wall_time, DateTime.utc_now()),
        node: Keyword.get(opts, :node, Node.self()),
        pid: Keyword.get(opts, :pid, self()),
        correlation_id: Keyword.get(opts, :correlation_id, Utils.generate_correlation_id()),
        parent_id: Keyword.get(opts, :parent_id),
        data: data
      )

    case EventValidator.validate(event) do
      :ok -> {:ok, event}
      {:error, _} = error -> error
    end
  end

  @doc """
  Create a function entry event.
  """
  @spec create_function_entry(module(), atom(), arity(), [term()], event_opts()) ::
          {:ok, Event.t()} | {:error, Error.t()}
  def create_function_entry(module, function, arity, args, opts \\ []) do
    data = %{
      call_id: Utils.generate_id(),
      module: module,
      function: function,
      arity: arity,
      args: Utils.truncate_if_large(args),
      caller_module: Keyword.get(opts, :caller_module),
      caller_function: Keyword.get(opts, :caller_function),
      caller_line: Keyword.get(opts, :caller_line)
    }

    create_event(:function_entry, data, opts)
  end

  @doc """
  Create a function exit event.
  """
  @spec create_function_exit(
          module(),
          atom(),
          arity(),
          pos_integer(),
          term(),
          non_neg_integer(),
          atom()
        ) :: {:ok, Event.t()} | {:error, Error.t()}
  def create_function_exit(module, function, arity, call_id, result, duration_ns, exit_reason) do
    data = %{
      call_id: call_id,
      module: module,
      function: function,
      arity: arity,
      result: Utils.truncate_if_large(result),
      duration_ns: duration_ns,
      exit_reason: exit_reason
    }

    create_event(:function_exit, data)
  end

  @doc """
  Create a state change event.
  """
  @spec create_state_change(pid(), atom(), term(), term(), event_opts()) ::
          {:ok, Event.t()} | {:error, Error.t()}
  def create_state_change(server_pid, callback, old_state, new_state, opts \\ []) do
    data = %{
      server_pid: server_pid,
      callback: callback,
      old_state: Utils.truncate_if_large(old_state),
      new_state: Utils.truncate_if_large(new_state),
      state_diff: compute_state_diff(old_state, new_state),
      trigger_message: Keyword.get(opts, :trigger_message),
      trigger_call_id: Keyword.get(opts, :trigger_call_id)
    }

    create_event(:state_change, data, opts)
  end

  @doc """
  Serialize an event to binary format.
  """
  @spec serialize_event(Event.t(), serialization_opts()) :: {:ok, binary()} | {:error, Error.t()}
  def serialize_event(%Event{} = event, opts \\ []) do
    compression = Keyword.get(opts, :compression, true)

    try do
      binary =
        if compression do
          :erlang.term_to_binary(event, [:compressed])
        else
          :erlang.term_to_binary(event)
        end

      {:ok, binary}
    rescue
      error ->
        create_error(
          :serialization_failed,
          "Failed to serialize event",
          %{original_error: error, event_id: event.event_id}
        )
    end
  end

  @doc """
  Deserialize an event from binary format.
  """
  @spec deserialize_event(binary()) :: {:ok, Event.t()} | {:error, Error.t()}
  def deserialize_event(binary) when is_binary(binary) do
    try do
      event = :erlang.binary_to_term(binary)

      case EventValidator.validate(event) do
        :ok -> {:ok, event}
        {:error, _} = error -> error
      end
    rescue
      error ->
        create_error(
          :deserialization_failed,
          "Failed to deserialize event",
          %{original_error: error, binary_size: byte_size(binary)}
        )
    end
  end

  @doc """
  Calculate the serialized size of an event.
  """
  @spec calculate_serialized_size(Event.t()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
  def calculate_serialized_size(%Event{} = event) do
    case serialize_event(event) do
      {:ok, binary} -> {:ok, byte_size(binary)}
      {:error, _} = error -> error
    end
  end

  @doc """
  Extract correlation chain from a list of events.
  """
  @spec extract_correlation_chain([Event.t()], String.t()) :: [Event.t()]
  def extract_correlation_chain(events, correlation_id)
      when is_list(events) and is_binary(correlation_id) do
    events
    |> Enum.filter(fn event -> event.correlation_id == correlation_id end)
    |> Enum.sort_by(& &1.timestamp)
  end

  @doc """
  Group events by correlation ID.
  """
  @spec group_by_correlation([Event.t()]) :: %{String.t() => [Event.t()]}
  def group_by_correlation(events) when is_list(events) do
    events
    |> Enum.filter(fn event -> not is_nil(event.correlation_id) end)
    |> Enum.group_by(& &1.correlation_id)
    |> Map.new(fn {correlation_id, group_events} ->
      {correlation_id, Enum.sort_by(group_events, & &1.timestamp)}
    end)
  end

  @doc """
  Filter events by time range.
  """
  @spec filter_by_time_range([Event.t()], integer(), integer()) :: [Event.t()]
  def filter_by_time_range(events, start_time, end_time)
      when is_list(events) and is_integer(start_time) and is_integer(end_time) do
    Enum.filter(events, fn event ->
      event.timestamp >= start_time and event.timestamp <= end_time
    end)
  end

  @doc """
  Transform event data using a transformation function.
  """
  @spec transform_event_data(Event.t(), (term() -> term())) :: Event.t()
  def transform_event_data(%Event{} = event, transform_fn) when is_function(transform_fn, 1) do
    %{event | data: transform_fn.(event.data)}
  end

  ## Private Functions

  defp compute_state_diff(old_state, new_state) do
    if old_state == new_state do
      :no_change
    else
      :changed
    end
  end

  defp create_error(error_type, message, context) do
    error =
      Error.new(
        error_type: error_type,
        message: message,
        context: context,
        category: :data,
        subcategory: :runtime,
        severity: :medium
      )

    {:error, error}
  end
end
