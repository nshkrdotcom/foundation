defmodule Foundation.Contracts.EventStore do
  @moduledoc """
  Behaviour contract for event storage implementations.

  Defines the interface for event persistence, retrieval, and management.
  Supports different storage backends (memory, disk, distributed).
  """

  alias Foundation.Types.{Error, Event}

  @type event_id :: Event.event_id()
  @type correlation_id :: Event.correlation_id()
  @type event_filter :: keyword()
  @type event_query :: map()

  @doc """
  Store a single event.

  Accepts both Event structs and {:ok, Event} tuples for pipe-friendly usage.
  """
  @callback store(Event.t() | {:ok, Event.t()}) :: {:ok, event_id()} | {:error, Error.t()}

  @doc """
  Store multiple events atomically.
  """
  @callback store_batch([Event.t()]) :: {:ok, [event_id()]} | {:error, Error.t()}

  @doc """
  Retrieve an event by ID.
  """
  @callback get(event_id()) :: {:ok, Event.t()} | {:error, Error.t()}

  @doc """
  Query events with filters and pagination.
  """
  @callback query(event_query()) :: {:ok, [Event.t()]} | {:error, Error.t()}

  @doc """
  Get events by correlation ID.
  """
  @callback get_by_correlation(correlation_id()) :: {:ok, [Event.t()]} | {:error, Error.t()}

  @doc """
  Delete events older than the specified timestamp.
  """
  @callback prune_before(integer()) :: {:ok, non_neg_integer()} | {:error, Error.t()}

  @doc """
  Get storage statistics.
  """
  @callback stats() :: {:ok, map()} | {:error, Error.t()}

  @doc """
  Check if event store is available.
  """
  @callback available?() :: boolean()

  @doc """
  Initialize the event store service.
  """
  @callback initialize() :: :ok | {:error, Error.t()}

  @doc """
  Get event store service status.
  """
  @callback status() :: {:ok, map()} | {:error, Error.t()}
end
