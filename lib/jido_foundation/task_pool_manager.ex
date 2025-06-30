defmodule JidoFoundation.TaskPoolManager do
  @moduledoc """
  Supervised task pool management for Foundation and JidoSystem.

  This module provides proper OTP supervision for concurrent task execution,
  replacing unsupervised `Task.async_stream` usage with supervised task pools.

  ## Features

  - Dedicated task supervisors for different operation types
  - Resource limits and backpressure control
  - Monitoring and metrics for task execution
  - Proper cleanup on failure
  - Isolation from critical agent processes

  ## Architecture

  Instead of using `Task.async_stream` which spawns unsupervised processes,
  this module provides supervised task pools that:
  1. Use proper Task.Supervisor for all task execution
  2. Implement resource limits and backpressure
  3. Provide monitoring and metrics
  4. Handle failures gracefully
  5. Integrate with OTP supervision trees

  ## Usage

      # Execute tasks with supervised pool
      JidoFoundation.TaskPoolManager.execute_batch(
        :distributed_computation,
        data_list,
        &process_item/1,
        max_concurrency: 5,
        timeout: 30_000
      )

      # Get pool statistics
      JidoFoundation.TaskPoolManager.get_pool_stats(:distributed_computation)
  """

  use GenServer
  require Logger

  defstruct [
    # %{pool_name => %{supervisor_pid, active_tasks, max_concurrency, stats}}
    :pools,
    # Global configuration
    :default_config,
    :stats
  ]

  @type pool_name :: atom()
  @type task_result :: {:ok, term()} | {:error, term()} | {:timeout, term()}

  # Default pool configurations
  @default_pools %{
    :general => %{max_concurrency: 10, timeout: 30_000},
    :distributed_computation => %{max_concurrency: System.schedulers_online(), timeout: 60_000},
    :agent_operations => %{max_concurrency: 20, timeout: 30_000},
    :coordination => %{max_concurrency: 15, timeout: 15_000},
    :monitoring => %{max_concurrency: 5, timeout: 10_000}
  }

  # Client API

  @doc """
  Starts the task pool manager GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Executes a batch of tasks using a supervised task pool.

  This replaces `Task.async_stream` with proper supervision.

  ## Parameters

  - `pool_name` - Name of the task pool to use
  - `enumerable` - Data to process
  - `fun` - Function to apply to each item
  - `opts` - Execution options

  ## Options

  - `:max_concurrency` - Maximum concurrent tasks (default: pool config)
  - `:timeout` - Task timeout in milliseconds (default: pool config)
  - `:on_timeout` - Action on timeout (default: `:kill_task`)
  - `:ordered` - Whether to maintain order (default: `true`)

  ## Returns

  Stream of results similar to `Task.async_stream` but supervised.
  """
  @spec execute_batch(pool_name(), Enumerable.t(), (term() -> term()), keyword()) :: Enumerable.t()
  def execute_batch(pool_name, enumerable, fun, opts \\ [])
      when is_atom(pool_name) and is_function(fun, 1) do
    GenServer.call(__MODULE__, {:execute_batch, pool_name, enumerable, fun, opts}, :infinity)
  end

  @doc """
  Executes a single supervised task.

  ## Parameters

  - `pool_name` - Name of the task pool to use
  - `fun` - Function to execute
  - `opts` - Execution options

  ## Returns

  Task reference for monitoring.
  """
  @spec execute_task(pool_name(), (-> term()), keyword()) :: Task.t()
  def execute_task(pool_name, fun, opts \\ []) when is_atom(pool_name) and is_function(fun, 0) do
    GenServer.call(__MODULE__, {:execute_task, pool_name, fun, opts})
  end

  @doc """
  Gets statistics for a specific task pool.
  """
  @spec get_pool_stats(pool_name()) :: {:ok, map()} | {:error, :pool_not_found}
  def get_pool_stats(pool_name) when is_atom(pool_name) do
    GenServer.call(__MODULE__, {:get_pool_stats, pool_name})
  end

  @doc """
  Gets statistics for all task pools.
  """
  @spec get_all_stats() :: map()
  def get_all_stats do
    GenServer.call(__MODULE__, :get_all_stats)
  end

  @doc """
  Creates a new task pool with specific configuration.
  """
  @spec create_pool(pool_name(), map()) :: :ok | {:error, :pool_exists}
  def create_pool(pool_name, config) when is_atom(pool_name) do
    GenServer.call(__MODULE__, {:create_pool, pool_name, config})
  end

  @doc """
  Updates configuration for an existing task pool.
  """
  @spec update_pool_config(pool_name(), map()) :: :ok | {:error, :pool_not_found}
  def update_pool_config(pool_name, config) when is_atom(pool_name) do
    GenServer.call(__MODULE__, {:update_pool_config, pool_name, config})
  end

  @doc """
  Forces shutdown of all tasks in a pool (emergency stop).
  """
  @spec shutdown_pool(pool_name()) :: :ok | {:error, :pool_not_found}
  def shutdown_pool(pool_name) when is_atom(pool_name) do
    GenServer.call(__MODULE__, {:shutdown_pool, pool_name})
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    default_config = Keyword.get(opts, :default_config, %{})
    pools_config = Keyword.get(opts, :pools, @default_pools)

    # Initialize pools
    pools =
      Enum.reduce(pools_config, %{}, fn {pool_name, config}, acc ->
        case start_pool_supervisor(pool_name, config) do
          {:ok, supervisor_pid} ->
            pool_info = %{
              supervisor_pid: supervisor_pid,
              config: config,
              active_tasks: 0,
              stats: %{
                tasks_started: 0,
                tasks_completed: 0,
                tasks_failed: 0,
                tasks_timeout: 0,
                total_execution_time: 0
              }
            }

            Map.put(acc, pool_name, pool_info)

          {:error, reason} ->
            Logger.error("Failed to start task pool #{pool_name}: #{inspect(reason)}")
            acc
        end
      end)

    state = %__MODULE__{
      pools: pools,
      default_config: default_config,
      stats: %{
        total_pools: map_size(pools),
        total_active_tasks: 0,
        total_tasks_executed: 0
      }
    }

    Logger.info("TaskPoolManager started with #{map_size(pools)} pools")
    {:ok, state}
  end

  @impl true
  def handle_call({:execute_batch, pool_name, enumerable, fun, opts}, _from, state) do
    case Map.get(state.pools, pool_name) do
      nil ->
        {:reply, {:error, :pool_not_found}, state}

      pool_info ->
        max_concurrency = Keyword.get(opts, :max_concurrency, pool_info.config.max_concurrency)
        timeout = Keyword.get(opts, :timeout, pool_info.config.timeout)
        on_timeout = Keyword.get(opts, :on_timeout, :kill_task)
        ordered = Keyword.get(opts, :ordered, true)

        # Create supervised async stream
        stream =
          Task.Supervisor.async_stream(
            pool_info.supervisor_pid,
            enumerable,
            fun,
            max_concurrency: max_concurrency,
            timeout: timeout,
            on_timeout: on_timeout,
            ordered: ordered
          )

        # Update stats
        task_count = Enum.count(enumerable)
        new_pool_info = update_pool_stats(pool_info, :batch_started, %{task_count: task_count})
        new_pools = Map.put(state.pools, pool_name, new_pool_info)
        new_state = %{state | pools: new_pools}

        {:reply, {:ok, stream}, new_state}
    end
  end

  def handle_call({:execute_task, pool_name, fun, _opts}, _from, state) do
    case Map.get(state.pools, pool_name) do
      nil ->
        {:reply, {:error, :pool_not_found}, state}

      pool_info ->
        # Use Task.Supervisor for single task
        task = Task.Supervisor.async(pool_info.supervisor_pid, fun)

        # Update stats
        new_pool_info = update_pool_stats(pool_info, :task_started, %{})
        new_pools = Map.put(state.pools, pool_name, new_pool_info)
        new_state = %{state | pools: new_pools}

        {:reply, {:ok, task}, new_state}
    end
  end

  def handle_call({:get_pool_stats, pool_name}, _from, state) do
    case Map.get(state.pools, pool_name) do
      nil ->
        {:reply, {:error, :pool_not_found}, state}

      pool_info ->
        stats =
          Map.merge(pool_info.stats, %{
            active_tasks: pool_info.active_tasks,
            max_concurrency: pool_info.config.max_concurrency,
            timeout: pool_info.config.timeout
          })

        {:reply, {:ok, stats}, state}
    end
  end

  def handle_call(:get_all_stats, _from, state) do
    all_stats =
      Enum.reduce(state.pools, %{}, fn {pool_name, pool_info}, acc ->
        pool_stats =
          Map.merge(pool_info.stats, %{
            active_tasks: pool_info.active_tasks,
            max_concurrency: pool_info.config.max_concurrency
          })

        Map.put(acc, pool_name, pool_stats)
      end)

    global_stats = Map.merge(state.stats, %{pools: all_stats})
    {:reply, global_stats, state}
  end

  def handle_call({:create_pool, pool_name, config}, _from, state) do
    if Map.has_key?(state.pools, pool_name) do
      {:reply, {:error, :pool_exists}, state}
    else
      case start_pool_supervisor(pool_name, config) do
        {:ok, supervisor_pid} ->
          pool_info = %{
            supervisor_pid: supervisor_pid,
            config: config,
            active_tasks: 0,
            stats: %{
              tasks_started: 0,
              tasks_completed: 0,
              tasks_failed: 0,
              tasks_timeout: 0,
              total_execution_time: 0
            }
          }

          new_pools = Map.put(state.pools, pool_name, pool_info)
          new_stats = Map.update!(state.stats, :total_pools, &(&1 + 1))
          new_state = %{state | pools: new_pools, stats: new_stats}

          Logger.info("Created new task pool: #{pool_name}")
          {:reply, :ok, new_state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end
    end
  end

  def handle_call({:update_pool_config, pool_name, config}, _from, state) do
    case Map.get(state.pools, pool_name) do
      nil ->
        {:reply, {:error, :pool_not_found}, state}

      pool_info ->
        new_config = Map.merge(pool_info.config, config)
        new_pool_info = %{pool_info | config: new_config}
        new_pools = Map.put(state.pools, pool_name, new_pool_info)
        new_state = %{state | pools: new_pools}

        Logger.info("Updated config for task pool: #{pool_name}")
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:shutdown_pool, pool_name}, _from, state) do
    case Map.get(state.pools, pool_name) do
      nil ->
        {:reply, {:error, :pool_not_found}, state}

      pool_info ->
        # Terminate all tasks in the pool
        children = Task.Supervisor.children(pool_info.supervisor_pid)

        Enum.each(children, fn child_pid ->
          Process.exit(child_pid, :shutdown)
        end)

        Logger.warning(
          "Emergency shutdown of task pool: #{pool_name} (#{length(children)} tasks killed)"
        )

        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    # Handle task completion/failure for statistics
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("TaskPoolManager terminating: #{inspect(reason)}")

    # Terminate all pool supervisors
    Enum.each(state.pools, fn {pool_name, pool_info} ->
      try do
        DynamicSupervisor.stop(pool_info.supervisor_pid, :shutdown)
      catch
        _, _ ->
          Logger.warning("Failed to stop task pool supervisor: #{pool_name}")
      end
    end)

    :ok
  end

  # Private helper functions

  defp start_pool_supervisor(pool_name, _config) do
    supervisor_name = :"TaskPool_#{pool_name}_Supervisor"

    DynamicSupervisor.start_link(
      strategy: :one_for_one,
      name: supervisor_name
    )
    |> case do
      {:ok, supervisor_pid} ->
        # Start the actual Task.Supervisor under the DynamicSupervisor
        task_supervisor_name = :"TaskSupervisor_#{pool_name}"

        child_spec = {Task.Supervisor, name: task_supervisor_name}

        case DynamicSupervisor.start_child(supervisor_pid, child_spec) do
          {:ok, task_supervisor_pid} ->
            {:ok, task_supervisor_pid}

          error ->
            DynamicSupervisor.stop(supervisor_pid)
            error
        end

      error ->
        error
    end
  end

  defp update_pool_stats(pool_info, event, metadata) do
    case event do
      :task_started ->
        new_stats = Map.update!(pool_info.stats, :tasks_started, &(&1 + 1))
        new_active = pool_info.active_tasks + 1
        %{pool_info | stats: new_stats, active_tasks: new_active}

      :batch_started ->
        task_count = metadata[:task_count] || 0
        new_stats = Map.update!(pool_info.stats, :tasks_started, &(&1 + task_count))
        new_active = pool_info.active_tasks + task_count
        %{pool_info | stats: new_stats, active_tasks: new_active}
    end
  end
end
