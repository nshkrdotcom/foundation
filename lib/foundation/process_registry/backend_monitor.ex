defmodule Foundation.ProcessRegistry.BackendMonitor do
  @moduledoc """
  Backend health monitoring and failover management for Foundation.ProcessRegistry.

  This module provides monitoring, health checking, and automatic failover
  capabilities for ProcessRegistry backends. It supports multiple backend
  types and can switch between them based on health and performance metrics.

  ## Features

  - Continuous health monitoring of active backends
  - Performance metrics collection and analysis
  - Automatic failover between backend implementations
  - Backend-specific health checks and diagnostics
  - Graceful degradation during backend failures

  ## Future Distribution Features

  When distributed backends are implemented, this module will provide:
  - Cross-cluster health monitoring
  - Distributed failover coordination
  - Network partition detection and handling
  - Automatic cluster rebalancing

  ## Usage

      # Start monitoring the current backend
      {:ok, _pid} = BackendMonitor.start_link([])

      # Check backend health
      {:ok, health} = BackendMonitor.health_check()

      # Get performance metrics
      {:ok, metrics} = BackendMonitor.get_performance_metrics()

      # Force backend switching (if multiple backends available)
      :ok = BackendMonitor.switch_backend(:horde)
  """

  use GenServer
  require Logger

  alias Foundation.ProcessRegistry.Backend

  @default_check_interval 30_000  # 30 seconds
  @default_performance_window 300_000  # 5 minutes
  @default_failure_threshold 3

  defstruct [
    :active_backend,
    :available_backends,
    :check_interval,
    :performance_window,
    :failure_threshold,
    :failure_count,
    :last_check,
    :performance_history,
    :health_status
  ]

  @type backend_type :: :ets | :registry | :horde
  @type health_status :: :healthy | :degraded | :unhealthy
  @type performance_metric :: %{
    timestamp: integer(),
    operation: atom(),
    duration_ms: number(),
    success: boolean()
  }

  # Public API

  @doc """
  Start the backend monitor.

  ## Options
  - `:check_interval` - Health check interval in milliseconds (default: 30_000)
  - `:performance_window` - Performance metrics retention window (default: 300_000)
  - `:failure_threshold` - Number of failures before switching backends (default: 3)
  - `:backends` - List of available backend modules (default: auto-detect)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get the current health status of the active backend.

  ## Returns
  - `{:ok, health_info}` - Health check successful
  - `{:error, reason}` - Health check failed

  ## Examples

      {:ok, health} = BackendMonitor.health_check()
      # => {:ok, %{
      #   status: :healthy,
      #   backend: Foundation.ProcessRegistry.Backend.ETS,
      #   response_time_ms: 1.2,
      #   last_check: ~U[2023-06-23 10:30:45Z]
      # }}
  """
  @spec health_check() :: {:ok, map()} | {:error, term()}
  def health_check do
    GenServer.call(__MODULE__, :health_check, 5000)
  end

  @doc """
  Get performance metrics for the active backend.

  ## Returns
  - `{:ok, metrics}` - Performance metrics retrieved
  - `{:error, reason}` - Failed to get metrics

  ## Examples

      {:ok, metrics} = BackendMonitor.get_performance_metrics()
      # => {:ok, %{
      #   avg_response_time_ms: 1.5,
      #   success_rate: 0.99,
      #   operations_per_second: 1250,
      #   error_count: 2
      # }}
  """
  @spec get_performance_metrics() :: {:ok, map()} | {:error, term()}
  def get_performance_metrics do
    GenServer.call(__MODULE__, :get_performance_metrics)
  end

  @doc """
  Get the currently active backend module.

  ## Returns
  - Backend module atom

  ## Examples

      backend = BackendMonitor.get_active_backend()
      # => Foundation.ProcessRegistry.Backend.ETS
  """
  @spec get_active_backend() :: module()
  def get_active_backend do
    GenServer.call(__MODULE__, :get_active_backend)
  end

  @doc """
  Switch to a different backend (if available).

  ## Parameters
  - `backend_type` - The backend type to switch to

  ## Returns
  - `:ok` - Backend switched successfully
  - `{:error, reason}` - Failed to switch backend

  ## Examples

      :ok = BackendMonitor.switch_backend(:horde)
      {:error, :backend_not_available} = BackendMonitor.switch_backend(:invalid)
  """
  @spec switch_backend(backend_type()) :: :ok | {:error, term()}
  def switch_backend(backend_type) do
    GenServer.call(__MODULE__, {:switch_backend, backend_type})
  end

  @doc """
  Record a performance metric for monitoring.

  This is typically called internally by the ProcessRegistry
  to track operation performance.

  ## Parameters
  - `operation` - The operation type (:register, :lookup, etc.)
  - `duration_ms` - How long the operation took
  - `success` - Whether the operation succeeded
  """
  @spec record_metric(atom(), number(), boolean()) :: :ok
  def record_metric(operation, duration_ms, success) do
    GenServer.cast(__MODULE__, {:record_metric, operation, duration_ms, success})
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    check_interval = Keyword.get(opts, :check_interval, @default_check_interval)
    performance_window = Keyword.get(opts, :performance_window, @default_performance_window)
    failure_threshold = Keyword.get(opts, :failure_threshold, @default_failure_threshold)
    
    available_backends = detect_available_backends()
    active_backend = List.first(available_backends)

    if active_backend do
      Logger.info("BackendMonitor started with backend: #{inspect(active_backend)}")
      
      state = %__MODULE__{
        active_backend: active_backend,
        available_backends: available_backends,
        check_interval: check_interval,
        performance_window: performance_window,
        failure_threshold: failure_threshold,
        failure_count: 0,
        last_check: nil,
        performance_history: [],
        health_status: :healthy
      }

      # Schedule the first health check
      schedule_health_check(check_interval)
      
      {:ok, state}
    else
      {:stop, :no_backends_available}
    end
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    {health_result, new_state} = perform_health_check(state)
    {:reply, health_result, new_state}
  end

  @impl true
  def handle_call(:get_performance_metrics, _from, state) do
    metrics = calculate_performance_metrics(state)
    {:reply, {:ok, metrics}, state}
  end

  @impl true
  def handle_call(:get_active_backend, _from, state) do
    {:reply, state.active_backend, state}
  end

  @impl true
  def handle_call({:switch_backend, backend_type}, _from, state) do
    case find_backend_module(backend_type, state.available_backends) do
      {:ok, backend_module} ->
        new_state = %{state | active_backend: backend_module, failure_count: 0}
        Logger.info("Switched to backend: #{inspect(backend_module)}")
        {:reply, :ok, new_state}

      :error ->
        {:reply, {:error, :backend_not_available}, state}
    end
  end

  @impl true
  def handle_cast({:record_metric, operation, duration_ms, success}, state) do
    metric = %{
      timestamp: System.monotonic_time(:millisecond),
      operation: operation,
      duration_ms: duration_ms,
      success: success
    }

    # Add metric and prune old ones
    new_history = prune_old_metrics([metric | state.performance_history], state.performance_window)
    new_state = %{state | performance_history: new_history}

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:health_check, state) do
    {_health_result, new_state} = perform_health_check(state)
    
    # Schedule the next health check
    schedule_health_check(state.check_interval)
    
    {:noreply, new_state}
  end

  # Private Functions

  defp detect_available_backends do
    # Detect which backend modules are available
    potential_backends = [
      {Foundation.ProcessRegistry.Backend.ETS, :ets},
      {Foundation.ProcessRegistry.Backend.Registry, :registry},
      {Foundation.ProcessRegistry.Backend.Horde, :horde}
    ]

    Enum.filter(potential_backends, fn {module, _type} ->
      Code.ensure_loaded?(module)
    end)
    |> Enum.map(fn {module, _type} -> module end)
  end

  defp find_backend_module(backend_type, available_backends) do
    backend_map = %{
      ets: Foundation.ProcessRegistry.Backend.ETS,
      registry: Foundation.ProcessRegistry.Backend.Registry,
      horde: Foundation.ProcessRegistry.Backend.Horde
    }

    case Map.get(backend_map, backend_type) do
      nil -> :error
      module ->
        if module in available_backends do
          {:ok, module}
        else
          :error
        end
    end
  end

  defp perform_health_check(state) do
    start_time = System.monotonic_time(:millisecond)
    
    try do
      case state.active_backend.health_check() do
        {:ok, backend_health} ->
          end_time = System.monotonic_time(:millisecond)
          response_time = end_time - start_time

          health_info = %{
            status: :healthy,
            backend: state.active_backend,
            response_time_ms: response_time,
            last_check: DateTime.utc_now(),
            backend_details: backend_health
          }

          new_state = %{state | 
            failure_count: 0,
            last_check: DateTime.utc_now(),
            health_status: :healthy
          }

          {{:ok, health_info}, new_state}

        {:error, reason} ->
          handle_backend_failure(state, reason)
      end
    rescue
      error ->
        handle_backend_failure(state, {:exception, error})
    end
  end

  defp handle_backend_failure(state, reason) do
    new_failure_count = state.failure_count + 1
    
    Logger.warning("Backend health check failed: #{inspect(reason)} (failure #{new_failure_count}/#{state.failure_threshold})")

    if new_failure_count >= state.failure_threshold do
      # Try to switch to another backend
      case attempt_backend_failover(state) do
        {:ok, new_backend, new_state} ->
          Logger.warning("Failed over to backend: #{inspect(new_backend)}")
          health_info = %{
            status: :degraded,
            backend: new_backend,
            last_check: DateTime.utc_now(),
            failover_reason: reason
          }
          {{:ok, health_info}, new_state}

        :error ->
          Logger.error("All backends failed, system degraded")
          error_info = %{
            status: :unhealthy,
            backend: state.active_backend,
            last_check: DateTime.utc_now(),
            failure_reason: reason
          }
          new_state = %{state | 
            failure_count: new_failure_count,
            health_status: :unhealthy
          }
          {{:error, error_info}, new_state}
      end
    else
      # Still within failure threshold
      error_info = %{
        status: :degraded,
        backend: state.active_backend,
        last_check: DateTime.utc_now(),
        failure_count: new_failure_count,
        failure_reason: reason
      }
      new_state = %{state | 
        failure_count: new_failure_count,
        health_status: :degraded
      }
      {{:error, error_info}, new_state}
    end
  end

  defp attempt_backend_failover(state) do
    # Try other available backends
    other_backends = List.delete(state.available_backends, state.active_backend)
    
    case find_healthy_backend(other_backends) do
      {:ok, new_backend} ->
        new_state = %{state | 
          active_backend: new_backend,
          failure_count: 0,
          health_status: :healthy
        }
        {:ok, new_backend, new_state}

      :error ->
        :error
    end
  end

  defp find_healthy_backend([]), do: :error
  defp find_healthy_backend([backend | rest]) do
    try do
      case backend.health_check() do
        {:ok, _} -> {:ok, backend}
        {:error, _} -> find_healthy_backend(rest)
      end
    rescue
      _ -> find_healthy_backend(rest)
    end
  end

  defp calculate_performance_metrics(state) do
    if length(state.performance_history) == 0 do
      %{
        avg_response_time_ms: 0.0,
        success_rate: 1.0,
        operations_per_second: 0.0,
        error_count: 0,
        total_operations: 0
      }
    else
      total_ops = length(state.performance_history)
      successful_ops = Enum.count(state.performance_history, & &1.success)
      
      avg_response_time = 
        state.performance_history
        |> Enum.map(& &1.duration_ms)
        |> Enum.sum()
        |> Kernel./(total_ops)

      # Calculate operations per second over the time window
      now = System.monotonic_time(:millisecond)
      window_start = now - state.performance_window
      recent_ops = Enum.count(state.performance_history, & &1.timestamp >= window_start)
      ops_per_second = recent_ops / (state.performance_window / 1000)

      %{
        avg_response_time_ms: Float.round(avg_response_time, 2),
        success_rate: Float.round(successful_ops / total_ops, 3),
        operations_per_second: Float.round(ops_per_second, 1),
        error_count: total_ops - successful_ops,
        total_operations: total_ops
      }
    end
  end

  defp prune_old_metrics(metrics, window_ms) do
    cutoff = System.monotonic_time(:millisecond) - window_ms
    Enum.filter(metrics, & &1.timestamp >= cutoff)
  end

  defp schedule_health_check(interval) do
    Process.send_after(self(), :health_check, interval)
  end

  # Child spec for supervision
  
  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end
end