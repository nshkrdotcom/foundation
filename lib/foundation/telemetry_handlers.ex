defmodule Foundation.TelemetryHandlers do
  @moduledoc """
  Named telemetry handlers for better performance in Foundation tests and runtime.

  This module provides named functions for telemetry handlers to replace
  anonymous functions which can cause performance warnings.
  """

  @doc """
  Handle Jido agent events for testing.

  This handler sends telemetry events to the test process for verification.
  """
  def handle_jido_events(event, measurements, metadata, config) do
    test_pid = config[:test_pid] || self()
    send(test_pid, {:telemetry, event, measurements, metadata})
  end

  @doc """
  Handle error events during testing.

  Logs error telemetry events and forwards to test process.
  """
  def handle_error_events(event, measurements, metadata, config) do
    require Logger

    Logger.debug("Error telemetry event: #{inspect(event)}",
      measurements: measurements,
      metadata: metadata
    )

    test_pid = config[:test_pid] || self()
    send(test_pid, {:error_telemetry, event, measurements, metadata})
  end

  @doc """
  Handle circuit breaker events for testing.
  """
  def handle_circuit_breaker_events(event, measurements, metadata, config) do
    test_pid = config[:test_pid] || self()
    send(test_pid, {:telemetry_event, event, measurements, metadata})
  end

  @doc """
  Handle Foundation operation events.
  """
  def handle_foundation_events(event, measurements, metadata, config) do
    test_pid = config[:test_pid] || self()
    send(test_pid, {:foundation_telemetry, event, measurements, metadata})
  end

  @doc """
  Generic handler that forwards all events to the test process.
  """
  def handle_test_events(event, measurements, metadata, config) do
    test_pid = config[:test_pid] || self()
    send(test_pid, {:telemetry, event, measurements, metadata})
  end
end
