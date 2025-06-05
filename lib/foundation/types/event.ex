defmodule Foundation.Types.Event do
  @moduledoc """
  Event data structure for Foundation.

  Events represent actions, state changes, and system events that occur
  during Foundation operation. This is a pure data structure with no behavior.

  While all fields are optional for maximum flexibility, production events 
  typically should have at least an event_type and timestamp.

  See `@type t` for the complete type specification.

  ## Examples

      iex> event = Foundation.Types.Event.new([
      ...>   event_type: :config_updated,
      ...>   event_id: 123,
      ...>   timestamp: System.monotonic_time()
      ...> ])
      iex> event.event_type
      :config_updated

      iex> empty_event = Foundation.Types.Event.new()
      iex> is_nil(empty_event.event_type)
      true
  """

  @typedoc "Unique identifier for an event"
  @type event_id :: pos_integer()

  @typedoc "Correlation identifier for tracking related events"
  @type correlation_id :: String.t()

  @enforce_keys [:event_type, :event_id, :timestamp]
  defstruct [
    :event_type,
    :event_id,
    :timestamp,
    :wall_time,
    :node,
    :pid,
    :correlation_id,
    :parent_id,
    :data
  ]

  @type t :: %__MODULE__{
          event_type: atom() | nil,
          event_id: event_id() | nil,
          timestamp: integer() | nil,
          wall_time: DateTime.t() | nil,
          node: node() | nil,
          pid: pid() | nil,
          correlation_id: correlation_id() | nil,
          parent_id: event_id() | nil,
          data: term() | nil
        }

  @doc """
  Create a new event structure with required fields.

  Creates an event with minimal required fields for enforcement.
  Additional fields can be provided via keyword list.

  ## Examples

      iex> event = Foundation.Types.Event.new()
      iex> event.event_type
      :default

      iex> event = Foundation.Types.Event.new(event_type: :custom)
      iex> event.event_type
      :custom
  """
  @spec new() :: t()
  def new() do
    new([])
  end

  @spec new(keyword()) :: t()
  def new(fields) when is_list(fields) do
    defaults = [
      event_type: :default,
      event_id: System.unique_integer([:positive]),
      timestamp: System.monotonic_time()
    ]

    final_fields = Keyword.merge(defaults, fields)
    struct(__MODULE__, final_fields)
  end

  @doc """
  Create a new event structure with a specific event type.

  Accepts an atom for the event_type and creates an event with 
  default values for required fields.

  ## Parameters
  - `event_type`: An atom representing the event type

  ## Examples

      iex> event = Foundation.Types.Event.new(:process_started)
      iex> event.event_type
      :process_started
  """
  @spec new(atom()) :: t()
  def new(event_type) when is_atom(event_type) do
    new(event_type: event_type)
  end

  @doc """
  Create an empty event structure without enforcement (for testing).

  This function bypasses the @enforce_keys constraint to allow creation
  of events with nil values for testing purposes.

  ## Examples

      iex> event = Foundation.Types.Event.empty()
      iex> is_nil(event.event_type)
      true
  """
  @spec empty() :: %__MODULE__{
          event_type: nil,
          event_id: nil,
          timestamp: nil,
          wall_time: nil,
          node: nil,
          pid: nil,
          correlation_id: nil,
          parent_id: nil,
          data: nil
        }
  def empty() do
    %__MODULE__{
      event_type: nil,
      event_id: nil,
      timestamp: nil,
      wall_time: nil,
      node: nil,
      pid: nil,
      correlation_id: nil,
      parent_id: nil,
      data: nil
    }
  end
end
