defmodule Foundation.Telemetry do
  @moduledoc """
  Lightweight telemetry helpers with optional TelemetryReporter integration.

  This module is intentionally thin: it emits `:telemetry` events and provides
  convenience wrappers for timing code. If the optional `telemetry_reporter`
  dependency is available, it can also start a reporter and attach handlers
  that forward events.
  """

  @type event_name :: [atom()]
  @type measurements :: map()
  @type metadata :: map()
  @type reporter :: GenServer.server()

  @doc """
  Emit a telemetry event.
  """
  @spec execute(event_name(), measurements(), metadata()) :: :ok
  def execute(event_name, measurements \\ %{}, metadata \\ %{}) when is_list(event_name) do
    :telemetry.execute(event_name, measurements, metadata)
    :ok
  end

  @doc """
  Measure execution time and emit `:stop` or `:exception` events.

  Options:
    * `:time_unit` - unit for duration (default: `:microsecond`)
  """
  @spec measure(event_name(), metadata(), (-> result), keyword()) :: result when result: term
  def measure(event_name, metadata, fun, opts \\ [])
      when is_list(event_name) and is_map(metadata) and is_function(fun, 0) do
    time_unit = Keyword.get(opts, :time_unit, :microsecond)
    start_time = System.monotonic_time(time_unit)

    try do
      result = fun.()
      duration = System.monotonic_time(time_unit) - start_time
      execute(event_name ++ [:stop], %{duration: duration, time_unit: time_unit}, metadata)
      result
    rescue
      error ->
        duration = System.monotonic_time(time_unit) - start_time

        execute(
          event_name ++ [:exception],
          %{duration: duration, time_unit: time_unit},
          Map.put(metadata, :error, error)
        )

        reraise error, __STACKTRACE__
    end
  end

  @doc """
  Start a TelemetryReporter instance if the dependency is available.
  """
  @spec start_reporter(keyword()) :: GenServer.on_start() | {:error, :missing_dependency}
  def start_reporter(opts) when is_list(opts) do
    with {:ok, reporter} <- telemetry_reporter() do
      reporter.start_link(opts)
    end
  end

  @doc """
  Log a telemetry event via TelemetryReporter if available.
  """
  @spec log(reporter(), String.t() | [atom()], map(), atom()) ::
          :ok | {:error, :overloaded} | {:error, :not_running} | {:error, :missing_dependency}
  def log(reporter, name, data \\ %{}, severity \\ :info) do
    with {:ok, reporter_mod} <- telemetry_reporter() do
      reporter_mod.log(reporter, name, data, severity)
    end
  end

  @doc """
  Attach TelemetryReporter handlers for forwarding `:telemetry` events.

  Returns the handler id.
  """
  @spec attach_reporter(keyword()) :: {:ok, term()} | {:error, :missing_dependency}
  def attach_reporter(opts) when is_list(opts) do
    with {:ok, adapter} <- telemetry_adapter() do
      {:ok, adapter.attach_many(opts)}
    end
  end

  @doc """
  Detach a TelemetryReporter handler.
  """
  @spec detach_reporter(term()) :: :ok | {:error, :not_found} | {:error, :missing_dependency}
  def detach_reporter(handler_id) do
    with {:ok, adapter} <- telemetry_adapter() do
      adapter.detach(handler_id)
    end
  end

  defp telemetry_reporter do
    if Code.ensure_loaded?(TelemetryReporter) do
      {:ok, TelemetryReporter}
    else
      {:error, :missing_dependency}
    end
  end

  defp telemetry_adapter do
    if Code.ensure_loaded?(TelemetryReporter.TelemetryAdapter) do
      {:ok, TelemetryReporter.TelemetryAdapter}
    else
      {:error, :missing_dependency}
    end
  end
end
