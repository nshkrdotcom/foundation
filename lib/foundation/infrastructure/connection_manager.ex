defmodule Foundation.Infrastructure.ConnectionManager do
  @moduledoc """
  Connection pooling manager wrapping Poolboy for resource management.

  Provides a unified interface for managing connection pools across different
  resource types (database connections, HTTP clients, etc.) with proper
  lifecycle management and telemetry integration.

  ## Usage

      # Start a pool for database connections
      {:ok, pool_pid} = ConnectionManager.start_pool(:database, [
        size: 10,
        max_overflow: 5,
        worker_module: MyApp.DatabaseWorker,
        worker_args: [host: "localhost", port: 5432]
      ])

      # Execute work with a pooled connection
      result = ConnectionManager.with_connection(:database, fn worker ->
        GenServer.call(worker, {:query, "SELECT * FROM users"})
      end)

      # Get pool status
      status = ConnectionManager.get_pool_status(:database)

  ## Pool Configuration

  - `:size` - Initial pool size (default: 5)
  - `:max_overflow` - Maximum additional workers (default: 10)
  - `:worker_module` - Module implementing the worker behavior
  - `:worker_args` - Arguments passed to worker start_link/1
  - `:strategy` - Pool strategy (default: :lifo)

  ## Telemetry Events

  - `[:foundation, :foundation, :connection_pool, :checkout]` - Connection checked out
  - `[:foundation, :foundation, :connection_pool, :checkin]` - Connection returned
  - `[:foundation, :foundation, :connection_pool, :timeout]` - Checkout timeout
  - `[:foundation, :foundation, :connection_pool, :overflow]` - Pool overflow occurred
  """

  use GenServer
  require Logger

  alias Foundation.Services.TelemetryService

  @type pool_name :: atom()
  @type pool_config :: [
          size: non_neg_integer(),
          max_overflow: non_neg_integer(),
          worker_module: module(),
          worker_args: term(),
          strategy: :lifo | :fifo
        ]
  @type pool_status :: %{
          size: non_neg_integer(),
          overflow: non_neg_integer(),
          workers: non_neg_integer(),
          waiting: non_neg_integer(),
          monitors: non_neg_integer()
        }

  # Default pool configuration
  @default_config [
    size: 5,
    max_overflow: 10,
    strategy: :lifo
  ]

  @default_checkout_timeout 5_000

  ## Public API

  @doc """
  Starts the ConnectionManager GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts a new connection pool with the given configuration.

  ## Parameters
  - `pool_name` - Unique identifier for the pool
  - `config` - Pool configuration options

  ## Returns
  - `{:ok, pid}` - Pool started successfully
  - `{:error, reason}` - Pool failed to start
  """
  @spec start_pool(pool_name(), pool_config()) :: {:ok, pid()} | {:error, term()}
  def start_pool(pool_name, config) do
    GenServer.call(__MODULE__, {:start_pool, pool_name, config})
  end

  @doc """
  Stops an existing connection pool.

  ## Parameters
  - `pool_name` - Pool identifier to stop

  ## Returns
  - `:ok` - Pool stopped successfully
  - `{:error, :not_found}` - Pool doesn't exist
  """
  @spec stop_pool(pool_name()) :: :ok | {:error, :not_found}
  def stop_pool(pool_name) do
    GenServer.call(__MODULE__, {:stop_pool, pool_name})
  end

  @doc """
  Executes a function with a connection from the specified pool.

  Automatically handles checkout/checkin and provides proper error handling
  with telemetry integration.

  ## Parameters
  - `pool_name` - Pool to get connection from
  - `fun` - Function to execute with the worker
  - `timeout` - Checkout timeout (default: 5000ms)

  ## Returns
  - `{:ok, result}` - Function executed successfully
  - `{:error, reason}` - Execution failed or pool unavailable
  """
  @spec with_connection(pool_name(), (pid() -> term()), timeout()) ::
          {:ok, term()} | {:error, term()}
  def with_connection(pool_name, fun, timeout \\ @default_checkout_timeout) do
    # Add buffer to GenServer timeout to account for processing overhead
    # But ensure it's reasonable - minimum 500ms buffer, maximum 2000ms buffer
    buffer = min(max(trunc(timeout * 0.2), 500), 2000)
    genserver_timeout = timeout + buffer
    GenServer.call(__MODULE__, {:with_connection, pool_name, fun, timeout}, genserver_timeout)
  end

  @doc """
  Gets the current status of a connection pool.

  ## Parameters
  - `pool_name` - Pool to get status for

  ## Returns
  - `{:ok, status}` - Pool status information
  - `{:error, :not_found}` - Pool doesn't exist
  """
  @spec get_pool_status(pool_name()) :: {:ok, pool_status()} | {:error, :not_found}
  def get_pool_status(pool_name) do
    GenServer.call(__MODULE__, {:get_pool_status, pool_name})
  end

  @doc """
  Lists all active connection pools.

  ## Returns
  - `[pool_name]` - List of active pool names
  """
  @spec list_pools() :: [pool_name()]
  def list_pools do
    GenServer.call(__MODULE__, :list_pools)
  end

  ## GenServer Implementation

  @impl GenServer
  def init(_opts) do
    state = %{
      pools: %{},
      configs: %{}
    }

    Logger.info("ConnectionManager started")
    {:ok, state}
  end

  @impl GenServer
  def handle_call({:start_pool, pool_name, config}, _from, state) do
    case Map.has_key?(state.pools, pool_name) do
      true ->
        {:reply, {:error, :already_exists}, state}

      false ->
        case do_start_pool(pool_name, config) do
          {:ok, pool_pid} ->
            new_state = %{
              state
              | pools: Map.put(state.pools, pool_name, pool_pid),
                configs: Map.put(state.configs, pool_name, config)
            }

            Logger.info("Started connection pool: #{pool_name}")
            emit_telemetry(:pool_started, %{}, %{pool_name: pool_name, config: config})

            {:reply, {:ok, pool_pid}, new_state}

          {:error, reason} ->
            Logger.error("Failed to start pool #{pool_name}: #{inspect(reason)}")
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl GenServer
  def handle_call({:stop_pool, pool_name}, _from, state) do
    case Map.get(state.pools, pool_name) do
      nil ->
        {:reply, {:error, :not_found}, state}

      pool_pid ->
        :poolboy.stop(pool_pid)

        new_state = %{
          state
          | pools: Map.delete(state.pools, pool_name),
            configs: Map.delete(state.configs, pool_name)
        }

        Logger.info("Stopped connection pool: #{pool_name}")
        emit_telemetry(:pool_stopped, %{}, %{pool_name: pool_name})

        {:reply, :ok, new_state}
    end
  end

  @impl GenServer
  def handle_call({:with_connection, pool_name, fun, timeout}, _from, state) do
    case Map.get(state.pools, pool_name) do
      nil ->
        {:reply, {:error, :pool_not_found}, state}

      pool_pid ->
        result = do_with_connection(pool_name, pool_pid, fun, timeout)
        {:reply, result, state}
    end
  end

  @impl GenServer
  def handle_call({:get_pool_status, pool_name}, _from, state) do
    case Map.get(state.pools, pool_name) do
      nil ->
        {:reply, {:error, :not_found}, state}

      pool_pid ->
        status = :poolboy.status(pool_pid)

        # poolboy.status returns a tuple: {state, size, workers, waiting}
        formatted_status =
          case status do
            {_state, size, workers, waiting} ->
              %{
                size: size,
                overflow: 0,
                workers: workers,
                waiting: waiting,
                monitors: 0
              }
          end

        {:reply, {:ok, formatted_status}, state}
    end
  end

  @impl GenServer
  def handle_call(:list_pools, _from, state) do
    pool_names = Map.keys(state.pools)
    {:reply, pool_names, state}
  end

  ## Private Functions

  @spec do_start_pool(pool_name(), pool_config()) :: {:ok, pid()} | {:error, term()}
  defp do_start_pool(pool_name, config) do
    # Validate configuration values
    case validate_pool_config(config) do
      :ok ->
        # Validate worker module exists before attempting to start pool
        worker_module = Keyword.get(config, :worker_module)

        case validate_worker_module(worker_module) do
          :ok ->
            {poolboy_config, worker_args} = build_poolboy_config(pool_name, config)

            case :poolboy.start_link(poolboy_config, worker_args) do
              {:ok, pid} -> {:ok, pid}
              {:error, reason} -> {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    error -> {:error, error}
  end

  @spec validate_pool_config(pool_config()) :: :ok | {:error, term()}
  defp validate_pool_config(config) do
    merged_config = Keyword.merge(@default_config, config)

    size = Keyword.get(merged_config, :size)
    max_overflow = Keyword.get(merged_config, :max_overflow)

    cond do
      not is_integer(size) or size < 0 ->
        {:error, {:invalid_config, :size, "Size must be a non-negative integer"}}

      not is_integer(max_overflow) or max_overflow < 0 ->
        {:error, {:invalid_config, :max_overflow, "Max overflow must be a non-negative integer"}}

      true ->
        :ok
    end
  end

  @spec validate_worker_module(module()) :: :ok | {:error, term()}
  defp validate_worker_module(worker_module) do
    case Code.ensure_compiled(worker_module) do
      {:module, _} -> :ok
      _ -> {:error, {:invalid_worker_module, worker_module}}
    end
  end

  @spec build_poolboy_config(pool_name(), pool_config()) :: {keyword(), keyword()}
  defp build_poolboy_config(pool_name, config) do
    merged_config = Keyword.merge(@default_config, config)

    poolboy_config = [
      name: {:local, pool_name},
      worker_module: Keyword.fetch!(merged_config, :worker_module),
      size: Keyword.get(merged_config, :size),
      max_overflow: Keyword.get(merged_config, :max_overflow),
      strategy: Keyword.get(merged_config, :strategy)
    ]

    worker_args = Keyword.get(merged_config, :worker_args, [])

    {poolboy_config, worker_args}
  end

  @spec do_with_connection(pool_name(), pid(), (pid() -> term()), timeout()) ::
          {:ok, term()} | {:error, term()}
  defp do_with_connection(pool_name, pool_pid, fun, timeout) do
    start_time = System.monotonic_time()

    try do
      worker = :poolboy.checkout(pool_pid, true, timeout)

      emit_telemetry(
        :checkout,
        %{
          checkout_time: System.monotonic_time() - start_time
        },
        %{pool_name: pool_name}
      )

      try do
        result = fun.(worker)
        {:ok, result}
      rescue
        error ->
          Logger.error("Function execution error in pool #{pool_name}: #{inspect(error)}")
          {:error, error}
      catch
        :exit, reason ->
          # If the worker process exits while we're calling it, treat it as a function result
          # This allows the GenServer.call to return its response before the process exits
          Logger.warning(
            "Worker process exited during call in pool #{pool_name}: #{inspect(reason)}"
          )

          {:error, reason}
      after
        :poolboy.checkin(pool_pid, worker)
        emit_telemetry(:checkin, %{}, %{pool_name: pool_name})
      end
    catch
      :exit, {:timeout, {GenServer, :call, _}} ->
        emit_telemetry(:timeout, %{timeout: timeout}, %{pool_name: pool_name})
        {:error, :checkout_timeout}

      :exit, {:timeout, _} ->
        emit_telemetry(:timeout, %{timeout: timeout}, %{pool_name: pool_name})
        {:error, :checkout_timeout}

      :exit, {:noproc, _} ->
        emit_telemetry(:timeout, %{timeout: timeout}, %{pool_name: pool_name})
        {:error, :checkout_timeout}

      :exit, reason ->
        Logger.error("Connection pool error for #{pool_name}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @spec emit_telemetry(atom(), map(), map()) :: :ok
  defp emit_telemetry(event, measurements, metadata) do
    TelemetryService.execute(
      [:foundation, :foundation, :connection_pool, event],
      measurements,
      metadata
    )
  end
end
