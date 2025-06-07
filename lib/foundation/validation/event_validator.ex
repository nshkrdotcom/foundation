defmodule Foundation.Validation.EventValidator do
  @moduledoc """
  Pure validation functions for event structures.

  Contains only validation logic - no side effects, no business logic.
  All functions are pure and easily testable.

  This module validates Event structs to ensure they contain valid data
  before storage or processing.

  ## Examples

      iex> event = Foundation.Types.Event.new([
      ...>   event_id: 123,
      ...>   event_type: :function_entry,
      ...>   timestamp: System.monotonic_time()
      ...> ])
      iex> Foundation.Validation.EventValidator.validate(event)
      :ok
  """

  alias Foundation.Types.{Event, Error}

  @typedoc "Maximum allowed size for event data in bytes"
  @type max_data_size :: 1_000_000

  @doc """
  Validate an event structure.

  Performs comprehensive validation including required fields, types, and data size.

  ## Parameters
  - `event`: The Event struct to validate

  ## Examples

      iex> valid_event = Event.new([event_id: 1, event_type: :test, timestamp: 123])
      iex> EventValidator.validate(valid_event)
      :ok

      iex> invalid_event = Event.new([event_id: nil, event_type: :test])
      iex> EventValidator.validate(invalid_event)
      {:error, %Error{error_type: :validation_failed}}
  """
  @spec validate(Event.t()) :: :ok | {:error, Error.t()}
  def validate(%Event{} = event) do
    with :ok <- validate_required_fields(event),
         :ok <- validate_field_types(event),
         :ok <- validate_data_size(event) do
      :ok
    end
  end

  @doc """
  Validate that an event has all required fields.

  Checks that critical fields like event_id, event_type, and timestamp are present.
  """
  @spec validate_required_fields(Event.t()) :: :ok | {:error, Error.t()}
  def validate_required_fields(%Event{} = event) do
    cond do
      is_nil(event.event_id) ->
        create_error(:validation_failed, "Event ID cannot be nil")

      is_nil(event.event_type) ->
        create_error(:validation_failed, "Event type cannot be nil")

      is_nil(event.timestamp) ->
        create_error(:validation_failed, "Timestamp cannot be nil")

      true ->
        :ok
    end
  end

  @doc """
  Validate event field types.

  Ensures all fields have the correct data types when present.
  """
  @spec validate_field_types(Event.t()) :: :ok | {:error, Error.t()}
  def validate_field_types(%Event{} = event) do
    cond do
      event.event_id && (not is_integer(event.event_id) or event.event_id <= 0) ->
        create_error(:type_mismatch, "Event ID must be a positive integer")

      event.event_type && not is_atom(event.event_type) ->
        create_error(:type_mismatch, "Event type must be an atom")

      event.timestamp && not is_integer(event.timestamp) ->
        create_error(:type_mismatch, "Timestamp must be an integer")

      event.wall_time && not is_struct(event.wall_time, DateTime) ->
        create_error(:type_mismatch, "Wall time must be a DateTime")

      event.node && not is_atom(event.node) ->
        create_error(:type_mismatch, "Node must be an atom")

      event.pid && not is_pid(event.pid) ->
        create_error(:type_mismatch, "PID must be a process identifier")

      event.correlation_id && not is_binary(event.correlation_id) ->
        create_error(:type_mismatch, "Correlation ID must be a string")

      event.parent_id && (not is_integer(event.parent_id) or event.parent_id <= 0) ->
        create_error(:type_mismatch, "Parent ID must be a positive integer")

      true ->
        :ok
    end
  end

  @doc """
  Validate event data size to prevent memory issues.

  Checks that the event data doesn't exceed the maximum allowed size.
  """
  @spec validate_data_size(Event.t()) :: :ok | {:error, Error.t()}
  def validate_data_size(%Event{data: data}) do
    # Check if data is too large (prevent memory issues)
    size = estimate_size(data)
    max_size = 1_000_000

    if size > max_size do
      create_error(
        :data_too_large,
        "Event data too large",
        %{size: size, max_size: max_size}
      )
    else
      :ok
    end
  end

  @doc """
  Validate event type is allowed.

  Checks that the event type is one of the predefined valid types.

  ## Parameters
  - `event_type`: Atom representing the event type

  ## Examples

      iex> EventValidator.validate_event_type(:function_entry)
      :ok

      iex> EventValidator.validate_event_type(:invalid_type)
      {:error, %Error{error_type: :invalid_event_type}}
  """
  @spec validate_event_type(atom()) :: :ok | {:error, Error.t()}
  def validate_event_type(event_type) when is_atom(event_type) do
    # Define allowed event types
    allowed_types = [
      :function_entry,
      :function_exit,
      :state_change,
      :message_send,
      :message_receive,
      :spawn,
      :exit,
      :link,
      :unlink,
      :monitor,
      :demonitor,
      :system_event,
      :custom_event,
      :config_updated,
      :config_reset,
      :test,
      :test1,
      :test2,
      :test3,
      :test_event,
      :default,
      :type_a,
      :type_b
    ]

    if event_type in allowed_types do
      :ok
    else
      create_error(
        :invalid_event_type,
        "Invalid event type",
        %{event_type: event_type, allowed_types: allowed_types}
      )
    end
  end

  def validate_event_type(_) do
    create_error(:type_mismatch, "Event type must be an atom")
  end

  ## Private Functions

  @spec estimate_size(term()) :: non_neg_integer()
  defp estimate_size(data) do
    try do
      :erlang.external_size(data)
    rescue
      _ -> 0
    end
  end

  @spec create_error(atom(), String.t(), map()) :: {:error, Error.t()}
  defp create_error(error_type, message, context \\ %{}) do
    error =
      Error.new(
        code: error_code_for_type(error_type),
        error_type: error_type,
        message: message,
        severity: severity_for_type(error_type),
        context: context,
        category: :data,
        subcategory: :validation
      )

    {:error, error}
  end

  @spec error_code_for_type(
          :validation_failed
          | :type_mismatch
          | :data_too_large
          | :invalid_event_type
        ) :: 2001 | 2002 | 2003 | 2004
  defp error_code_for_type(:validation_failed), do: 2001
  defp error_code_for_type(:type_mismatch), do: 2002
  defp error_code_for_type(:data_too_large), do: 2003
  defp error_code_for_type(:invalid_event_type), do: 2004

  @spec severity_for_type(
          :validation_failed
          | :type_mismatch
          | :data_too_large
          | :invalid_event_type
        ) :: Error.error_severity()
  defp severity_for_type(:data_too_large), do: :high
  defp severity_for_type(:validation_failed), do: :high
  defp severity_for_type(_), do: :medium
end
