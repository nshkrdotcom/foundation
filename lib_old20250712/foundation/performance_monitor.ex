defmodule Foundation.PerformanceMonitor do
  @moduledoc """
  Performance monitoring and metrics collection for Foundation platform.

  ## Features

  - Operation timing and throughput metrics
  - Registry performance monitoring
  - Coordination latency tracking
  - Memory and resource usage tracking
  - Telemetry integration for external monitoring

  ## Usage

      # Start monitoring
      {:ok, monitor} = Foundation.PerformanceMonitor.start_link()

      # Time operations
      Foundation.PerformanceMonitor.time_operation(:registry_lookup, fn ->
        Foundation.lookup("agent_1")
      end)

      # Get metrics
      metrics = Foundation.PerformanceMonitor.get_metrics()
  """

  use GenServer
  require Logger

  defstruct operations: %{},
            start_time: nil,
            last_cleanup: nil,
            cached_summary: nil,
            cache_timestamp: nil,
            cleanup_timer: nil

  # --- API ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Times an operation and records metrics.

  ## Parameters
  - `operation_name`: Atom identifying the operation type
  - `fun`: Function to execute and time

  ## Examples
      result = Foundation.PerformanceMonitor.time_operation(:registry_lookup, fn ->
        Foundation.lookup("agent_1")
      end)
  """
  @spec time_operation(atom(), (-> any())) :: any()
  def time_operation(operation_name, fun) do
    start_time = System.monotonic_time(:microsecond)

    try do
      result = fun.()
      duration = System.monotonic_time(:microsecond) - start_time
      record_operation(operation_name, duration, :success)
      result
    rescue
      error ->
        duration = System.monotonic_time(:microsecond) - start_time
        record_operation(operation_name, duration, :error)
        reraise error, __STACKTRACE__
    end
  end

  @doc """
  Records an operation result with duration.

  ## Parameters
  - `operation_name`: Atom identifying the operation
  - `duration_us`: Duration in microseconds
  - `result`: `:success` or `:error`
  """
  @spec record_operation(atom(), integer(), :success | :error) :: :ok
  def record_operation(operation_name, duration_us, result) do
    monitor = Process.whereis(__MODULE__)

    if monitor do
      GenServer.cast(monitor, {:record_operation, operation_name, duration_us, result})
    end

    :ok
  end

  @doc """
  Gets current performance metrics.

  ## Returns
  Map containing operation statistics:
  - `:total_operations` - Total number of operations
  - `:operations_by_type` - Statistics per operation type
  - `:uptime_seconds` - Monitor uptime
  - `:memory_usage` - Current memory usage
  """
  @spec get_metrics() :: map()
  def get_metrics do
    monitor = Process.whereis(__MODULE__)

    if monitor do
      GenServer.call(monitor, :get_metrics)
    else
      %{error: :monitor_not_running}
    end
  end

  @doc """
  Gets performance statistics for a specific operation type.

  ## Parameters
  - `operation_name`: The operation to get stats for

  ## Returns
  Map with operation-specific statistics or `:not_found`
  """
  @spec get_operation_stats(atom()) :: map() | :not_found
  def get_operation_stats(operation_name) do
    monitor = Process.whereis(__MODULE__)

    if monitor do
      GenServer.call(monitor, {:get_operation_stats, operation_name})
    else
      :not_found
    end
  end

  @doc """
  Resets all performance metrics.
  """
  @spec reset_metrics() :: :ok
  def reset_metrics do
    monitor = Process.whereis(__MODULE__)

    if monitor do
      GenServer.call(monitor, :reset_metrics)
    end

    :ok
  end

  @doc """
  Runs a simple benchmark of Foundation operations.

  ## Parameters
  - `operation_count`: Number of operations to run (default: 1000)
  - `registry_impl`: Registry implementation to benchmark

  ## Returns
  Benchmark results with operation timings and throughput
  """
  @spec benchmark(pos_integer(), term()) :: map()
  def benchmark(operation_count \\ 1000, registry_impl) do
    Logger.info("Starting Foundation benchmark with #{operation_count} operations")

    # Reset metrics before benchmark
    reset_metrics()

    # Run benchmark operations
    start_time = System.monotonic_time(:microsecond)

    # Pre-calculate node name to avoid repeated calls
    node_name = node()

    for i <- 1..operation_count do
      # Use atom instead of string interpolation in hot path
      key = {:bench_agent, i}

      metadata = %{
        capability: :benchmark,
        health_status: :healthy,
        node: node_name,
        resources: %{memory_usage: 0.1, cpu_usage: 0.1}
      }

      # Register agent
      Foundation.Registry.register(registry_impl, key, self(), metadata)

      # Lookup agent
      Foundation.Registry.lookup(registry_impl, key)

      # Find by attribute
      Foundation.Registry.find_by_attribute(registry_impl, :capability, :benchmark)

      # Unregister agent
      Foundation.Registry.unregister(registry_impl, key)
    end

    end_time = System.monotonic_time(:microsecond)
    total_duration = end_time - start_time

    # Get final metrics
    metrics = get_metrics()

    benchmark_results = %{
      operation_count: operation_count,
      total_duration_us: total_duration,
      total_duration_ms: total_duration / 1000,
      throughput_ops_per_second: operation_count * 1_000_000 / total_duration,
      avg_operation_duration_us: total_duration / operation_count,
      detailed_metrics: metrics
    }

    Logger.info(
      "Benchmark completed: #{Float.round(benchmark_results.throughput_ops_per_second, 2)} ops/sec"
    )

    benchmark_results
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      operations: %{},
      start_time: System.monotonic_time(:second),
      last_cleanup: System.monotonic_time(:second)
    }

    # Schedule periodic cleanup
    cleanup_timer = Process.send_after(self(), :cleanup, 60_000)

    Logger.info("Foundation.PerformanceMonitor started")
    {:ok, %{state | cleanup_timer: cleanup_timer}}
  end

  @impl true
  def handle_call(:get_metrics, _from, state) do
    # Use cached summary if available and fresh (within 1 second)
    current_time = System.monotonic_time(:millisecond)

    {metrics, new_state} =
      if state.cached_summary && state.cache_timestamp &&
           current_time - state.cache_timestamp < 1000 do
        # Return cached metrics
        {state.cached_summary, state}
      else
        # Build new metrics and cache them
        metrics = build_metrics_summary(state)
        updated_state = %{state | cached_summary: metrics, cache_timestamp: current_time}
        {metrics, updated_state}
      end

    {:reply, metrics, new_state}
  end

  @impl true
  def handle_call({:get_operation_stats, operation_name}, _from, state) do
    stats = Map.get(state.operations, operation_name, :not_found)
    {:reply, stats, state}
  end

  @impl true
  def handle_call(:reset_metrics, _from, state) do
    new_state = %{state | operations: %{}, start_time: System.monotonic_time(:second)}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast({:record_operation, operation_name, duration_us, result}, state) do
    updated_operations =
      update_operation_stats(state.operations, operation_name, duration_us, result)

    # Invalidate cache when new operations are recorded
    new_state = %{state | operations: updated_operations, cached_summary: nil, cache_timestamp: nil}
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Cancel old timer if it exists
    if state.cleanup_timer do
      Process.cancel_timer(state.cleanup_timer)
    end

    # Periodic cleanup of old metrics
    current_time = System.monotonic_time(:second)

    # Cleanup operations older than 1 hour
    cleaned_operations = cleanup_old_operations(state.operations, current_time)

    # Schedule next cleanup and store timer reference
    new_timer = Process.send_after(self(), :cleanup, 60_000)

    new_state = %{
      state
      | operations: cleaned_operations,
        last_cleanup: current_time,
        cleanup_timer: new_timer
    }

    {:noreply, new_state}
  end

  @impl true
  def terminate(_reason, state) do
    # Cancel cleanup timer if it exists
    if state.cleanup_timer do
      Process.cancel_timer(state.cleanup_timer)
    end

    :ok
  end

  # --- Private Functions ---

  defp update_operation_stats(operations, operation_name, duration_us, result) do
    current_stats =
      Map.get(operations, operation_name, %{
        count: 0,
        success_count: 0,
        error_count: 0,
        total_duration_us: 0,
        min_duration_us: nil,
        max_duration_us: 0,
        recent_operations: []
      })

    success_count =
      if result == :success, do: current_stats.success_count + 1, else: current_stats.success_count

    error_count =
      if result == :error, do: current_stats.error_count + 1, else: current_stats.error_count

    updated_stats = %{
      count: current_stats.count + 1,
      success_count: success_count,
      error_count: error_count,
      total_duration_us: current_stats.total_duration_us + duration_us,
      min_duration_us: min(current_stats.min_duration_us || duration_us, duration_us),
      max_duration_us: max(current_stats.max_duration_us, duration_us),
      recent_operations: add_recent_operation(current_stats.recent_operations, duration_us, result)
    }

    Map.put(operations, operation_name, updated_stats)
  end

  defp add_recent_operation(recent_ops, duration_us, result) do
    operation = %{
      timestamp: System.monotonic_time(:second),
      duration_us: duration_us,
      result: result
    }

    # Keep only last 100 operations
    # Avoid creating unnecessary intermediate lists
    if length(recent_ops) >= 100 do
      [operation | Enum.take(recent_ops, 99)]
    else
      [operation | recent_ops]
    end
  end

  defp build_metrics_summary(state) do
    current_time = System.monotonic_time(:second)
    uptime_seconds = current_time - state.start_time

    total_operations =
      state.operations
      |> Enum.reduce(0, fn {_op, stats}, acc -> acc + stats.count end)

    # Pre-calculate to avoid repeated computation
    operations_summary =
      Map.new(state.operations, fn {op_name, stats} ->
        # Only compute if we have data
        summary =
          if stats.count > 0 do
            # Use integer division where possible to avoid float operations
            avg_duration_us = div(stats.total_duration_us, stats.count)
            success_rate_percent = div(stats.success_count * 100, stats.count)

            %{
              count: stats.count,
              success_count: stats.success_count,
              error_count: stats.error_count,
              avg_duration_us: avg_duration_us,
              min_duration_us: stats.min_duration_us,
              max_duration_us: stats.max_duration_us,
              success_rate_percent: success_rate_percent
            }
          else
            %{
              count: 0,
              success_count: 0,
              error_count: 0,
              avg_duration_us: 0,
              min_duration_us: 0,
              max_duration_us: 0,
              success_rate_percent: 0
            }
          end

        {op_name, summary}
      end)

    %{
      total_operations: total_operations,
      uptime_seconds: uptime_seconds,
      operations_by_type: operations_summary,
      memory_usage: Process.info(self(), :memory),
      monitor_status: :running,
      last_cleanup: state.last_cleanup
    }
  end

  defp cleanup_old_operations(operations, _current_time) do
    # For now, just keep all operations
    # In production, this could remove operations older than a threshold
    operations
  end
end
