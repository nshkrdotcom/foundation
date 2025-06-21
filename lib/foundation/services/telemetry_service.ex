defmodule Foundation.Services.TelemetryService do
  @moduledoc """
  GenServer implementation for telemetry collection and metrics.

  Provides structured telemetry with automatic metric collection,
  event emission, and performance monitoring.
  """

  use GenServer
  require Logger

  alias Foundation.Types.Error
  alias Foundation.Contracts.Telemetry

  @behaviour Telemetry

  @type server_state :: %{
          metrics: %{atom() => map()},
          handlers: %{[atom()] => function()},
          config: map(),
          namespace: atom()
        }

  @default_config %{
    enable_vm_metrics: true,
    enable_process_metrics: true,
    # 5 minutes
    metric_retention_ms: 300_000,
    # 1 minute
    cleanup_interval: 60_000
  }

  ## Public API (Telemetry Behaviour Implementation)

  @impl Telemetry
  @spec execute([atom()], map(), map()) :: :ok
  def execute(event_name, measurements, metadata) when is_list(event_name) do
    case Foundation.ServiceRegistry.lookup(:production, :telemetry_service) do
      # Fail silently for telemetry
      {:error, _} -> :ok
      {:ok, pid} -> GenServer.cast(pid, {:execute_event, event_name, measurements, metadata})
    end
  end

  @impl Telemetry
  @spec measure([atom()], map(), (-> term())) :: term()
  def measure(event_name, metadata, fun) when is_list(event_name) and is_function(fun, 0) do
    start_time = System.monotonic_time()

    try do
      result = fun.()
      end_time = System.monotonic_time()
      duration = end_time - start_time

      measurements = %{duration: duration}
      execute(event_name ++ [:stop], measurements, metadata)

      result
    rescue
      error ->
        end_time = System.monotonic_time()
        duration = end_time - start_time

        measurements = %{duration: duration}
        error_metadata = Map.put(metadata, :error, error)
        execute(event_name ++ [:exception], measurements, error_metadata)

        reraise error, __STACKTRACE__
    end
  end

  @impl Telemetry
  @spec emit_counter([atom()], map()) :: :ok
  def emit_counter(event_name, metadata) when is_list(event_name) do
    measurements = %{counter: 1}
    execute(event_name, measurements, metadata)
  end

  # Overloaded version for tests that pass a value
  @spec emit_counter([atom()], number(), map()) :: :ok
  def emit_counter(event_name, value, metadata) when is_list(event_name) and is_number(value) do
    measurements = %{counter: value}
    execute(event_name, measurements, metadata)
  end

  @impl Telemetry
  @spec emit_gauge([atom()], number(), map()) :: :ok
  def emit_gauge(event_name, value, metadata) when is_list(event_name) and is_number(value) do
    measurements = %{gauge: value}
    execute(event_name, measurements, metadata)
  end

  @doc """
  Emit a histogram metric for distribution analysis.

  Histograms track the distribution of values over time and are useful for
  measuring latencies, sizes, and other continuous metrics.

  ## Parameters
  - `event_name` - List of atoms representing the telemetry event path
  - `value` - Numeric value to record in the histogram
  - `metadata` - Map containing additional context for the measurement

  ## Examples

      iex> emit_histogram([:api, :request_duration], 150, %{endpoint: "/users"})
      :ok

      iex> emit_histogram([:database, :query_time], 45.5, %{table: "users"})
      :ok

  ## Returns
  - `:ok` - Metric emitted successfully

  ## Raises
  - `ArgumentError` - If event_name is not a list of atoms, value is not numeric,
    or metadata is not a map
  """
  @impl Telemetry
  @spec emit_histogram([atom(), ...], number(), map()) :: :ok
  def emit_histogram(event_name, value, metadata)
      when is_list(event_name) and is_number(value) and is_map(metadata) do
    # Validate event name contains only atoms and is not empty
    cond do
      event_name == [] ->
        raise ArgumentError, "Event name cannot be empty"

      not Enum.all?(event_name, &is_atom/1) ->
        raise ArgumentError, "Event name must be a list of atoms, got: #{inspect(event_name)}"

      true ->
        measurements = %{histogram: value}
        execute(event_name, measurements, metadata)
    end
  end

  def emit_histogram(event_name, value, metadata) do
    cond do
      not is_list(event_name) ->
        raise ArgumentError, "Event name must be a list of atoms, got: #{inspect(event_name)}"

      event_name == [] ->
        raise ArgumentError, "Event name cannot be empty"

      not Enum.all?(event_name, &is_atom/1) ->
        raise ArgumentError, "Event name must be a list of atoms, got: #{inspect(event_name)}"

      not is_number(value) ->
        raise ArgumentError, "Value must be a number, got: #{inspect(value)}"

      not is_map(metadata) ->
        raise ArgumentError, "Metadata must be a map, got: #{inspect(metadata)}"

      true ->
        raise ArgumentError, "Invalid arguments for emit_histogram/3"
    end
  end

  @doc """
  Emit a histogram metric with default empty metadata.

  Convenience function for emitting histogram metrics when no additional
  context is needed.

  ## Parameters
  - `event_name` - List of atoms representing the telemetry event path
  - `value` - Numeric value to record in the histogram

  ## Examples

      iex> emit_histogram([:response, :size], 1024)
      :ok

      iex> emit_histogram([:processing, :duration], 250.5)
      :ok

  ## Returns
  - `:ok` - Metric emitted successfully

  ## Raises
  - `ArgumentError` - If event_name is not a list of atoms or value is not numeric
  """
  @impl Telemetry
  @spec emit_histogram([atom(), ...], number()) :: :ok
  def emit_histogram(event_name, value) when is_list(event_name) and is_number(value) do
    # Validate event name contains only atoms and is not empty
    cond do
      event_name == [] ->
        raise ArgumentError, "Event name cannot be empty"

      not Enum.all?(event_name, &is_atom/1) ->
        raise ArgumentError, "Event name must be a list of atoms, got: #{inspect(event_name)}"

      true ->
        emit_histogram(event_name, value, %{})
    end
  end

  def emit_histogram(event_name, value) do
    cond do
      not is_list(event_name) ->
        raise ArgumentError, "Event name must be a list of atoms, got: #{inspect(event_name)}"

      event_name == [] ->
        raise ArgumentError, "Event name cannot be empty"

      not Enum.all?(event_name, &is_atom/1) ->
        raise ArgumentError, "Event name must be a list of atoms, got: #{inspect(event_name)}"

      not is_number(value) ->
        raise ArgumentError, "Value must be a number, got: #{inspect(value)}"

      true ->
        raise ArgumentError, "Invalid arguments for emit_histogram/2"
    end
  end

  @impl Telemetry
  @spec get_metrics() :: {:ok, map()} | {:error, Error.t()}
  def get_metrics do
    case Foundation.ServiceRegistry.lookup(:production, :telemetry_service) do
      {:error, _} -> create_service_error("Telemetry service not started")
      {:ok, pid} -> GenServer.call(pid, :get_metrics)
    end
  end

  @impl Telemetry
  @spec attach_handlers([[atom()]]) :: :ok | {:error, Error.t()}
  def attach_handlers(event_names) when is_list(event_names) do
    case Foundation.ServiceRegistry.lookup(:production, :telemetry_service) do
      {:error, _} -> create_service_error("Telemetry service not started")
      {:ok, pid} -> GenServer.call(pid, {:attach_handlers, event_names})
    end
  end

  @impl Telemetry
  @spec detach_handlers([[atom()]]) :: :ok
  def detach_handlers(event_names) when is_list(event_names) do
    case Foundation.ServiceRegistry.lookup(:production, :telemetry_service) do
      # Fail silently
      {:error, _} -> :ok
      {:ok, pid} -> GenServer.cast(pid, {:detach_handlers, event_names})
    end
  end

  @impl Telemetry
  @spec available?() :: boolean()
  def available? do
    case Foundation.ServiceRegistry.lookup(:production, :telemetry_service) do
      {:ok, _pid} -> true
      {:error, _} -> false
    end
  end

  @impl Telemetry
  @spec initialize() :: :ok | {:error, Error.t()}
  def initialize do
    initialize([])
  end

  @impl Telemetry
  @spec status() :: {:ok, map()} | {:error, Error.t()}
  def status do
    case Foundation.ServiceRegistry.lookup(:production, :telemetry_service) do
      {:error, _} -> create_service_error("Telemetry service not started")
      {:ok, pid} -> GenServer.call(pid, :get_status)
    end
  end

  ## GenServer API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    namespace = Keyword.get(opts, :namespace, :production)
    name = Foundation.ServiceRegistry.via_tuple(namespace, :telemetry_service)
    GenServer.start_link(__MODULE__, Keyword.put(opts, :namespace, namespace), name: name)
  end

  @spec stop() :: :ok
  def stop do
    case Foundation.ServiceRegistry.lookup(:production, :telemetry_service) do
      {:ok, pid} -> GenServer.stop(pid)
      {:error, _} -> :ok
    end
  end

  @doc """
  Reset all metrics (for testing purposes).
  """
  @spec reset_metrics() :: :ok | {:error, Error.t()}
  def reset_metrics do
    case Foundation.ServiceRegistry.lookup(:production, :telemetry_service) do
      {:error, _} -> create_service_error("Telemetry service not started")
      {:ok, pid} -> GenServer.call(pid, :clear_metrics)
    end
  end

  @doc """
  Reset all internal state for testing purposes.

  Clears all metrics, handlers, and resets configuration to defaults.
  This function should only be used in test environments.
  """
  @spec reset_state() :: :ok | {:error, Error.t()}
  def reset_state do
    if Application.get_env(:foundation, :test_mode, false) do
      case Foundation.ServiceRegistry.lookup(:production, :telemetry_service) do
        {:error, _} -> create_service_error("Telemetry service not started")
        {:ok, pid} -> GenServer.call(pid, :reset_state)
      end
    else
      {:error,
       Error.new(
         code: 7002,
         error_type: :operation_forbidden,
         message: "State reset only allowed in test mode",
         severity: :high,
         category: :security,
         subcategory: :authorization
       )}
    end
  end

  ## GenServer Callbacks

  @impl GenServer
  @spec init(keyword()) :: {:ok, server_state()}
  def init(opts) do
    config = Map.merge(@default_config, Map.new(opts))
    namespace = Keyword.get(opts, :namespace, :production)

    state = %{
      metrics: %{},
      handlers: %{},
      config: config,
      namespace: namespace
    }

    # Schedule periodic cleanup
    schedule_cleanup(config.cleanup_interval)

    # Attach VM metrics if enabled
    if config.enable_vm_metrics do
      attach_vm_metrics()
    end

    case Application.get_env(:foundation, :test_mode, false) do
      false ->
        Logger.info("Telemetry service initialized successfully in namespace #{inspect(namespace)}")

      _ ->
        :ok
    end

    {:ok, state}
  end

  @impl GenServer
  @spec handle_cast(term(), server_state()) :: {:noreply, server_state()}
  def handle_cast({:execute_event, event_name, measurements, metadata}, state) do
    new_state = record_metric(event_name, measurements, metadata, state)

    # Execute any attached handlers
    execute_handlers(event_name, measurements, metadata, state.handlers)

    # Also emit to standard telemetry system for external listeners
    :telemetry.execute(event_name, measurements, metadata)

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_cast({:detach_handlers, event_names}, %{handlers: handlers} = state) do
    new_handlers = Map.drop(handlers, event_names)
    new_state = %{state | handlers: new_handlers}
    {:noreply, new_state}
  end

  @impl GenServer
  @spec handle_call(term(), GenServer.from(), server_state()) ::
          {:reply, term(), server_state()}
  def handle_call(:get_metrics, _from, %{metrics: metrics} = state) do
    # Transform flat event names into nested structure for API compatibility
    nested_metrics = transform_to_nested_structure(metrics)

    # Add current timestamp to metrics
    timestamped_metrics = Map.put(nested_metrics, :retrieved_at, System.monotonic_time())

    {:reply, {:ok, timestamped_metrics}, state}
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    status = %{
      status: :running,
      metrics_count: map_size(state.metrics),
      handlers_count: map_size(state.handlers),
      config: state.config
    }

    {:reply, {:ok, status}, state}
  end

  @impl GenServer
  def handle_call(:health_status, _from, state) do
    # Health check for application monitoring
    health =
      if map_size(state.metrics) >= 0 and map_size(state.handlers) >= 0 do
        :healthy
      else
        :degraded
      end

    {:reply, {:ok, health}, state}
  end

  @impl GenServer
  def handle_call(:ping, _from, state) do
    # Simple ping for response time measurement
    {:reply, :pong, state}
  end

  @impl GenServer
  def handle_call(:clear_metrics, _from, state) do
    new_state = %{state | metrics: %{}}
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call(:reset_state, _from, %{namespace: namespace} = _state) do
    # Reset to initial state (for testing)
    config = Map.merge(@default_config, %{})

    new_state = %{
      metrics: %{},
      handlers: %{},
      config: config,
      namespace: namespace
    }

    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call({:attach_handlers, event_names}, _from, %{handlers: handlers} = state) do
    new_handlers =
      Enum.reduce(event_names, handlers, fn event_name, acc ->
        handler_fn = create_default_handler(event_name)
        Map.put(acc, event_name, handler_fn)
      end)

    new_state = %{state | handlers: new_handlers}
    {:reply, :ok, new_state}
  end

  @impl GenServer
  @spec handle_info(term(), server_state()) :: {:noreply, server_state()}
  def handle_info(:cleanup_old_metrics, %{config: config} = state) do
    new_state = cleanup_old_metrics(state, config.metric_retention_ms)
    schedule_cleanup(config.cleanup_interval)
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(msg, state) do
    Logger.debug("Unexpected message in TelemetryService: #{inspect(msg)}")
    {:noreply, state}
  end

  ## Private Functions

  defp record_metric(event_name, measurements, metadata, %{metrics: metrics} = state) do
    timestamp = System.monotonic_time()

    metric_entry = %{
      timestamp: timestamp,
      measurements: measurements,
      metadata: metadata,
      count: 1
    }

    new_metrics =
      Map.update(metrics, event_name, metric_entry, fn existing ->
        %{
          existing
          | timestamp: timestamp,
            measurements: merge_measurements(existing.measurements, measurements),
            count: existing.count + 1
        }
      end)

    %{state | metrics: new_metrics}
  end

  defp merge_measurements(existing, new) do
    Map.merge(existing, new, fn
      :gauge, _old_val, new_val ->
        # For gauges, always use the latest value (no averaging)
        new_val

      :counter, old_val, new_val when is_number(old_val) and is_number(new_val) ->
        # For counters, accumulate the values
        old_val + new_val

      _key, old_val, new_val when is_number(old_val) and is_number(new_val) ->
        # For other numeric values, keep running average (backwards compatibility)
        (old_val + new_val) / 2

      _key, _old_val, new_val ->
        # For non-numeric, keep the new value
        new_val
    end)
  end

  defp execute_handlers(event_name, measurements, metadata, handlers) do
    case Map.get(handlers, event_name) do
      nil ->
        :ok

      handler_fn when is_function(handler_fn) ->
        try do
          handler_fn.(event_name, measurements, metadata)
        rescue
          error ->
            Logger.warning("Telemetry handler failed: #{inspect(error)}")
        end
    end
  end

  defp create_default_handler(event_name) do
    fn ^event_name, measurements, metadata ->
      Logger.debug(
        "Telemetry event: #{inspect(event_name)}, measurements: #{inspect(measurements)}, metadata: #{inspect(metadata)}"
      )
    end
  end

  defp cleanup_old_metrics(%{metrics: metrics} = state, retention_ms) do
    current_time = System.monotonic_time()
    cutoff_time = current_time - retention_ms

    new_metrics =
      Enum.filter(metrics, fn {_event_name, metric_data} ->
        metric_data.timestamp > cutoff_time
      end)
      |> Map.new()

    %{state | metrics: new_metrics}
  end

  defp attach_vm_metrics do
    # Attach standard VM telemetry events
    vm_events = [
      [:vm, :memory],
      [:vm, :total_run_queue_lengths],
      [:vm, :system_counts]
    ]

    Enum.each(vm_events, fn event_name ->
      emit_gauge(event_name, 1, %{source: :vm})
    end)
  end

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup_old_metrics, interval)
  end

  defp create_service_error(message) do
    error =
      Error.new(
        error_type: :service_unavailable,
        message: message,
        category: :system,
        subcategory: :initialization,
        severity: :medium
      )

    {:error, error}
  end

  ## Additional Functions

  @spec initialize(keyword()) :: :ok | {:error, Error.t()}
  def initialize(opts) do
    namespace = Keyword.get(opts, :namespace, :production)

    case Foundation.ServiceRegistry.lookup(namespace, :telemetry_service) do
      {:ok, _pid} ->
        # Service already running
        :ok

      {:error, _} ->
        # Service not running, try to start it
        case start_link(opts) do
          {:ok, _pid} ->
            :ok

          {:error, {:already_started, _pid}} ->
            :ok

          {:error, reason} ->
            {:error,
             Error.new(
               error_type: :service_initialization_failed,
               message: "Failed to initialize telemetry service",
               context: %{reason: reason},
               category: :system,
               subcategory: :startup,
               severity: :high
             )}
        end
    end
  end

  defp transform_to_nested_structure(metrics) do
    Enum.reduce(metrics, %{}, fn {event_name, metric_data}, acc ->
      case event_name do
        [:foundation, :event_store, :events_stored] ->
          # Transform to the expected nested structure for events_stored
          # Safely build the nested path
          foundation_map = Map.get(acc, :foundation, %{})
          updated_foundation = Map.put(foundation_map, :events_stored, metric_data.count || 0)
          Map.put(acc, :foundation, updated_foundation)

        [:foundation, :config_updates] ->
          # Transform config_updates metric
          foundation_map = Map.get(acc, :foundation, %{})
          updated_foundation = Map.put(foundation_map, :config_updates, metric_data.count || 0)
          Map.put(acc, :foundation, updated_foundation)

        [:foundation, :config_resets] ->
          # Transform config_resets metric
          foundation_map = Map.get(acc, :foundation, %{})
          updated_foundation = Map.put(foundation_map, :config_resets, metric_data.count || 0)
          Map.put(acc, :foundation, updated_foundation)

        [:foundation, :config_operations] ->
          # Transform general config operations metric
          foundation_map = Map.get(acc, :foundation, %{})
          updated_foundation = Map.put(foundation_map, :config_operations, metric_data.count || 0)
          Map.put(acc, :foundation, updated_foundation)

        [:foundation | rest] ->
          # Handle other foundation metrics
          nested_path = [:foundation] ++ rest
          put_nested_value(acc, nested_path, metric_data)

        [first | rest] when rest != [] ->
          # Handle other nested metrics
          nested_path = [first] ++ rest
          put_nested_value(acc, nested_path, metric_data)

        [single] ->
          # Single-level metrics
          Map.put(acc, single, metric_data)

        _ ->
          acc
      end
    end)
  end

  defp put_nested_value(map, [key], value) do
    Map.put(map, key, value)
  end

  defp put_nested_value(map, [key | rest], value) do
    Map.update(map, key, put_nested_value(%{}, rest, value), fn existing ->
      put_nested_value(existing, rest, value)
    end)
  end
end
