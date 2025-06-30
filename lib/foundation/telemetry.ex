defmodule Foundation.Telemetry do
  @moduledoc """
  Telemetry integration for the Foundation framework.

  This module provides a comprehensive telemetry infrastructure with:

  - Event emission with structured naming conventions
  - Metric collection and aggregation
  - Service lifecycle instrumentation
  - Performance measurement utilities
  - Error tracking and reporting

  ## Event Naming Convention

  Events follow the pattern: `[:foundation, :component, :action]`

  Examples:
  - `[:foundation, :service, :started]`
  - `[:foundation, :circuit_breaker, :opened]`
  - `[:foundation, :pool, :connection_acquired]`

  ## Common Measurements

  - `:duration` - Operation duration in native time units
  - `:count` - Number of items processed
  - `:queue_length` - Current queue size
  - `:error_count` - Number of errors

  ## Metadata Standards

  - `:service` - Service module name
  - `:node` - Node where event occurred
  - `:timestamp` - UTC timestamp
  - `:trace_id` - Distributed trace identifier
  """

  require Logger

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

    span_metadata =
      Map.merge(metadata, %{
        start_time: System.system_time(),
        node: node()
      })

    emit(event ++ [:start], %{system_time: System.system_time()}, span_metadata)

    try do
      result = fun.()
      duration = System.monotonic_time() - start_time

      emit(event ++ [:stop], %{duration: duration}, Map.put(span_metadata, :result, :ok))
      result
    rescue
      error ->
        duration = System.monotonic_time() - start_time

        emit(
          event ++ [:exception],
          %{duration: duration},
          Map.merge(span_metadata, %{
            error: error,
            stacktrace: __STACKTRACE__
          })
        )

        reraise error, __STACKTRACE__
    end
  end

  # Service Lifecycle Events

  @doc """
  Emits a service started event.

  ## Example
      Foundation.Telemetry.service_started(MyService, %{config: config})
  """
  def service_started(service, metadata \\ %{}) do
    emit(
      [:foundation, :service, :started],
      %{timestamp: System.system_time()},
      Map.merge(metadata, %{service: service, node: node()})
    )
  end

  @doc """
  Emits a service stopped event.

  ## Example
      Foundation.Telemetry.service_stopped(MyService, %{reason: :normal})
  """
  def service_stopped(service, metadata \\ %{}) do
    emit(
      [:foundation, :service, :stopped],
      %{timestamp: System.system_time()},
      Map.merge(metadata, %{service: service, node: node()})
    )
  end

  @doc """
  Emits a service error event.

  ## Example
      Foundation.Telemetry.service_error(MyService, error, %{operation: :handle_call})
  """
  def service_error(service, error, metadata \\ %{}) do
    emit(
      [:foundation, :service, :error],
      %{timestamp: System.system_time()},
      Map.merge(metadata, %{
        service: service,
        error: error,
        node: node()
      })
    )
  end

  # Async Operation Events

  @doc """
  Emits an async operation started event.

  ## Example
      Foundation.Telemetry.async_started(:data_processing, %{batch_size: 1000})
  """
  def async_started(operation, metadata \\ %{}) do
    emit(
      [:foundation, :async, :started],
      %{timestamp: System.system_time()},
      Map.merge(metadata, %{operation: operation, node: node()})
    )
  end

  @doc """
  Emits an async operation completed event.

  ## Example
      Foundation.Telemetry.async_completed(:data_processing, 145_000, %{records_processed: 1000})
  """
  def async_completed(operation, duration, metadata \\ %{}) do
    emit(
      [:foundation, :async, :completed],
      %{duration: duration, timestamp: System.system_time()},
      Map.merge(metadata, %{operation: operation, node: node()})
    )
  end

  @doc """
  Emits an async operation failed event.

  ## Example
      Foundation.Telemetry.async_failed(:data_processing, error, %{batch_id: 123})
  """
  def async_failed(operation, error, metadata \\ %{}) do
    emit(
      [:foundation, :async, :failed],
      %{timestamp: System.system_time()},
      Map.merge(metadata, %{
        operation: operation,
        error: error,
        node: node()
      })
    )
  end

  # Resource Management Events

  @doc """
  Emits a resource acquired event.

  ## Example
      Foundation.Telemetry.resource_acquired(:database_connection, %{pool: :primary})
  """
  def resource_acquired(resource_type, metadata \\ %{}) do
    emit(
      [:foundation, :resource, :acquired],
      %{timestamp: System.system_time()},
      Map.merge(metadata, %{resource_type: resource_type, node: node()})
    )
  end

  @doc """
  Emits a resource released event.

  ## Example
      Foundation.Telemetry.resource_released(:database_connection, 5_000_000, %{pool: :primary})
  """
  def resource_released(resource_type, hold_duration, metadata \\ %{}) do
    emit(
      [:foundation, :resource, :released],
      %{hold_duration: hold_duration, timestamp: System.system_time()},
      Map.merge(metadata, %{resource_type: resource_type, node: node()})
    )
  end

  @doc """
  Emits a resource exhausted event.

  ## Example
      Foundation.Telemetry.resource_exhausted(:database_connection, %{pool: :primary, waiting: 10})
  """
  def resource_exhausted(resource_type, metadata \\ %{}) do
    emit(
      [:foundation, :resource, :exhausted],
      %{timestamp: System.system_time()},
      Map.merge(metadata, %{resource_type: resource_type, node: node()})
    )
  end

  # Circuit Breaker Events

  @doc """
  Emits a circuit breaker state change event.

  ## Example
      Foundation.Telemetry.circuit_breaker_state_change(:payment_api, :closed, :open, %{error_count: 5})
  """
  def circuit_breaker_state_change(service, from_state, to_state, metadata \\ %{}) do
    emit(
      [:foundation, :circuit_breaker, :state_change],
      %{timestamp: System.system_time()},
      Map.merge(metadata, %{
        service: service,
        from_state: from_state,
        to_state: to_state,
        node: node()
      })
    )
  end

  # Performance Metrics

  @doc """
  Records a performance metric.

  ## Example
      Foundation.Telemetry.record_metric(:response_time, 45.2, %{endpoint: "/api/users"})
  """
  def record_metric(metric_name, value, metadata \\ %{}) do
    emit(
      [:foundation, :metrics, metric_name],
      %{value: value, timestamp: System.system_time()},
      Map.merge(metadata, %{node: node()})
    )
  end

  # Utility Functions

  @doc """
  Creates a trace context for distributed tracing.

  ## Example
      trace_id = Foundation.Telemetry.generate_trace_id()
      metadata = Foundation.Telemetry.with_trace(trace_id, %{operation: :user_signup})
  """
  def generate_trace_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  def with_trace(trace_id, metadata) do
    Map.put(metadata, :trace_id, trace_id)
  end

  @doc """
  Attaches a default error logger for all Foundation error events.
  """
  def attach_default_error_logger do
    attach(
      :foundation_error_logger,
      [:foundation, :_, :error],
      &log_error_event/4
    )
  end

  defp log_error_event(_event_name, measurements, metadata, _config) do
    Logger.error(
      "Foundation error: #{inspect(metadata.error)}",
      service: metadata[:service],
      measurements: measurements,
      metadata: metadata
    )
  end
end
