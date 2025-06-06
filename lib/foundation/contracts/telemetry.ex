defmodule Foundation.Contracts.Telemetry do
  @moduledoc """
  Behaviour contract for telemetry implementations.

  Defines the interface for metrics collection, event emission,
  and monitoring across different telemetry backends.
  """

  alias Foundation.Types.Error

  @type event_name :: [atom(), ...]
  @type measurements :: map()
  @type metadata :: map()
  @type metric_value :: number()

  @doc """
  Execute telemetry event with measurements.
  """
  @callback execute(event_name(), measurements(), metadata()) :: :ok

  @doc """
  Measure execution time and emit results.
  """
  @callback measure(event_name(), metadata(), (-> result)) :: result when result: var

  @doc """
  Emit a counter metric.
  """
  @callback emit_counter(event_name(), metadata()) :: :ok

  @doc """
  Emit a gauge metric.
  """
  @callback emit_gauge(event_name(), metric_value(), metadata()) :: :ok

  @doc """
  Emit a histogram metric for distribution analysis.

  Histograms track the distribution of values over time and are useful for
  measuring latencies, response sizes, and other continuous metrics.

  ## Parameters
  - `event_name` - List of atoms representing the telemetry event path
  - `value` - Numeric value to record in the histogram
  - `metadata` - Optional map containing additional context (defaults to empty map)

  ## Examples
      emit_histogram([:api, :request_duration], 150, %{endpoint: "/users"})
      emit_histogram([:database, :query_time], 45.5)
  """
  @callback emit_histogram(event_name(), metric_value(), metadata()) :: :ok
  @callback emit_histogram(event_name(), metric_value()) :: :ok

  @doc """
  Get collected metrics.
  """
  @callback get_metrics() :: {:ok, map()} | {:error, Error.t()}

  @doc """
  Attach event handlers for specific events.
  """
  @callback attach_handlers([event_name()]) :: :ok | {:error, Error.t()}

  @doc """
  Detach event handlers.
  """
  @callback detach_handlers([event_name()]) :: :ok

  @doc """
  Check if telemetry is available.
  """
  @callback available?() :: boolean()

  @doc """
  Initialize the telemetry service.
  """
  @callback initialize() :: :ok | {:error, Error.t()}

  @doc """
  Get telemetry service status.
  """
  @callback status() :: {:ok, map()} | {:error, Error.t()}
end
