defmodule Foundation.Telemetry.SampledEvents.TestAPI do
  @moduledoc """
  Test-compatible API for SampledEvents to avoid macro conflicts.
  
  This module provides simple function-based APIs that tests can use
  without conflicting with the macro-based DSL in the main module.
  """

  @doc """
  Emits a telemetry event (function version for tests).
  """
  def emit_event(event_name, measurements, metadata) do
    Foundation.Telemetry.Sampler.execute(event_name, measurements, metadata)
  end

  @doc """
  Emits a batched event (function version for tests).
  """
  def emit_batched(event_name, measurement, metadata) do
    Foundation.Telemetry.SampledEvents.ensure_server_started()
    Foundation.Telemetry.Sampler.execute([:batched | event_name], %{count: measurement}, metadata)
  end
end