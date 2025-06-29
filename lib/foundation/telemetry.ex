defmodule Foundation.Telemetry do
  @moduledoc """
  Telemetry integration for the Foundation framework.

  This module provides a convenient interface to :telemetry with Foundation-specific
  conventions and enhancements.
  """

  @doc """
  Emits a telemetry event with the given measurements and metadata.

  ## Parameters
    - `event` - List of atoms representing the event name
    - `measurements` - Map of measurement values (typically numbers)
    - `metadata` - Map of additional metadata

  ## Examples
      Foundation.Telemetry.emit([:foundation, :request, :complete], %{duration: 100}, %{path: "/api/users"})
  """
  def emit(event, measurements \\ %{}, metadata \\ %{}) do
    :telemetry.execute(event, measurements, metadata)
  end

  @doc """
  Attaches a telemetry handler to a specific event.

  ## Parameters
    - `handler_id` - Unique identifier for the handler
    - `event` - Event name to attach to
    - `function` - Function to call when event is emitted
    - `config` - Optional configuration passed to handler
  """
  def attach(handler_id, event, function, config \\ nil) do
    :telemetry.attach(handler_id, event, function, config)
  end

  @doc """
  Attaches a telemetry handler to multiple events.

  ## Parameters
    - `handler_id` - Unique identifier for the handler
    - `events` - List of event names to attach to
    - `function` - Function to call when any event is emitted
    - `config` - Optional configuration passed to handler
  """
  def attach_many(handler_id, events, function, config \\ nil) do
    :telemetry.attach_many(handler_id, events, function, config)
  end

  @doc """
  Detaches a telemetry handler.

  ## Parameters
    - `handler_id` - Handler ID to detach
  """
  def detach(handler_id) do
    :telemetry.detach(handler_id)
  end

  @doc """
  Lists all attached handlers.
  """
  def list_handlers do
    :telemetry.list_handlers([])
  end

  @doc """
  Executes a function and measures its duration, emitting a telemetry event.

  ## Parameters
    - `event` - Event name for the measurement
    - `metadata` - Additional metadata for the event
    - `fun` - Function to execute and measure

  ## Examples
      Foundation.Telemetry.span([:db, :query], %{query: "SELECT * FROM users"}, fn ->
        # Execute database query
        {:ok, results}
      end)
  """
  def span(event, metadata, fun) do
    start_time = System.monotonic_time()

    try do
      result = fun.()
      duration = System.monotonic_time() - start_time

      emit(event ++ [:stop], %{duration: duration}, Map.put(metadata, :result, :ok))
      result
    rescue
      error ->
        duration = System.monotonic_time() - start_time
        emit(event ++ [:exception], %{duration: duration}, Map.put(metadata, :error, error))
        reraise error, __STACKTRACE__
    end
  end
end
