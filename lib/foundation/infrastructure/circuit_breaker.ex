defmodule Foundation.Infrastructure.CircuitBreaker do
  @moduledoc """
  Circuit breaker implementation using the :fuse library.

  Provides circuit breaker functionality with telemetry integration
  and Foundation-specific error handling.

  ## Usage

      # Configure a circuit breaker for a service
      :ok = CircuitBreaker.configure(:my_service,
        failure_threshold: 5,
        timeout: 60_000
      )

      # Execute protected operation
      case CircuitBreaker.call(:my_service, fn -> risky_operation() end) do
        {:ok, result} -> result
        {:error, :circuit_open} -> handle_circuit_open()
        {:error, reason} -> handle_error(reason)
      end

      # Check circuit status
      {:ok, status} = CircuitBreaker.get_status(:my_service)
  """

  use GenServer
  require Logger

  @behaviour Foundation.Infrastructure

  @type service_id :: atom() | String.t()
  @type circuit_status :: :closed | :open | :half_open

  # GenServer state
  defmodule State do
    defstruct circuits: %{},
              default_config: %{}
  end

  # Circuit configuration
  defmodule CircuitConfig do
    defstruct failure_threshold: 5,
              success_threshold: 3,
              timeout: 60_000,
              reset_timeout: 60_000
  end

  # Client API

  @doc """
  Starts the circuit breaker service.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Configures a circuit breaker for a service.

  ## Options

    * `:failure_threshold` - Number of failures before opening (default: 5)
    * `:timeout` - Time in ms before attempting to close (default: 60_000)
    * `:success_threshold` - Successes needed to close from half-open (default: 3)
    * `:reset_timeout` - Time in ms for automatic reset (default: 60_000)
  """
  @spec configure(service_id(), keyword()) :: :ok | {:error, term()}
  def configure(service_id, config \\ []) do
    GenServer.call(__MODULE__, {:configure, service_id, config})
  end

  @doc """
  Executes a function with circuit breaker protection.

  ## Returns

    * `{:ok, result}` - If function executes successfully
    * `{:error, :circuit_open}` - If circuit is open
    * `{:error, :service_not_found}` - If service not configured
    * `{:error, reason}` - If function fails
  """
  @spec call(service_id(), (-> any()), keyword()) :: {:ok, any()} | {:error, term()}
  def call(service_id, function, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)
    GenServer.call(__MODULE__, {:execute, service_id, function}, timeout)
  rescue
    error ->
      Logger.error("Circuit breaker call failed: #{inspect(error)}")
      {:error, :circuit_breaker_error}
  end

  @doc """
  Gets the current status of a circuit breaker.
  """
  @spec get_status(service_id()) :: {:ok, circuit_status()} | {:error, term()}
  def get_status(service_id) do
    GenServer.call(__MODULE__, {:get_status, service_id})
  end

  @doc """
  Manually resets a circuit breaker.
  """
  @spec reset(service_id()) :: :ok | {:error, term()}
  def reset(service_id) do
    GenServer.call(__MODULE__, {:reset, service_id})
  end

  # Server callbacks

  @impl true
  def init(opts) do
    # Initialize :fuse application if not started
    case ensure_fuse_started() do
      :ok ->
        default_config = %CircuitConfig{
          failure_threshold: Keyword.get(opts, :default_failure_threshold, 5),
          success_threshold: Keyword.get(opts, :default_success_threshold, 3),
          timeout: Keyword.get(opts, :default_timeout, 60_000),
          reset_timeout: Keyword.get(opts, :default_reset_timeout, 60_000)
        }

        state = %State{
          circuits: %{},
          default_config: default_config
        }

        {:ok, state}

      {:error, reason} ->
        Logger.error(
          "Failed to start :fuse application: #{inspect(reason)}. Circuit breaker service cannot start."
        )

        {:stop, {:fuse_not_available, reason}}
    end
  end

  @impl true
  def handle_call({:configure, service_id, config}, _from, state) do
    circuit_config = build_circuit_config(config, state.default_config)

    # Configure the fuse
    fuse_opts = build_fuse_options(circuit_config)

    case :fuse.install(service_id, fuse_opts) do
      :ok ->
        new_circuits = Map.put(state.circuits, service_id, circuit_config)
        emit_telemetry(:circuit_configured, %{service_id: service_id})
        {:reply, :ok, %{state | circuits: new_circuits}}

      {:error, :already_installed} ->
        # Update configuration
        new_circuits = Map.put(state.circuits, service_id, circuit_config)
        {:reply, :ok, %{state | circuits: new_circuits}}

      error ->
        {:reply, {:error, error}, state}
    end
  end

  @impl true
  def handle_call({:execute, service_id, function}, _from, state) do
    if Map.has_key?(state.circuits, service_id) do
      result = execute_with_circuit_breaker(service_id, function)
      {:reply, result, state}
    else
      {:reply, {:error, :service_not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_status, service_id}, _from, state) do
    if Map.has_key?(state.circuits, service_id) do
      status = get_fuse_status(service_id)
      {:reply, {:ok, status}, state}
    else
      {:reply, {:error, :service_not_found}, state}
    end
  end

  @impl true
  def handle_call({:reset, service_id}, _from, state) do
    if Map.has_key?(state.circuits, service_id) do
      case :fuse.reset(service_id) do
        :ok ->
          emit_telemetry(:circuit_reset, %{service_id: service_id})
          {:reply, :ok, state}

        error ->
          {:reply, {:error, error}, state}
      end
    else
      {:reply, {:error, :service_not_found}, state}
    end
  end

  # Private functions

  defp ensure_fuse_started do
    case Application.ensure_all_started(:fuse) do
      {:ok, _} ->
        :ok

      {:error, reason} = error ->
        Logger.warning("Failed to start :fuse application: #{inspect(reason)}")
        error
    end
  end

  defp build_circuit_config(config, default_config) when is_list(config) do
    %CircuitConfig{
      failure_threshold: Keyword.get(config, :failure_threshold, default_config.failure_threshold),
      success_threshold: Keyword.get(config, :success_threshold, default_config.success_threshold),
      timeout: Keyword.get(config, :timeout, default_config.timeout),
      reset_timeout: Keyword.get(config, :reset_timeout, default_config.reset_timeout)
    }
  end

  defp build_circuit_config(config, default_config) when is_map(config) do
    %CircuitConfig{
      failure_threshold: Map.get(config, :failure_threshold, default_config.failure_threshold),
      success_threshold: Map.get(config, :success_threshold, default_config.success_threshold),
      timeout: Map.get(config, :timeout, default_config.timeout),
      reset_timeout: Map.get(config, :reset_timeout, default_config.reset_timeout)
    }
  end

  defp build_fuse_options(circuit_config) do
    # Based on lib_old pattern: {{:standard, tolerance, refresh}, {:reset, refresh}}
    # IMPORTANT: fuse tolerance means "number of failures to tolerate before opening"
    # So if we want circuit to open after N failures, tolerance should be N-1
    tolerance = max(0, circuit_config.failure_threshold - 1)

    fuse_opts =
      {{:standard, tolerance, circuit_config.reset_timeout}, {:reset, circuit_config.reset_timeout}}

    Logger.debug(
      "Building fuse options: #{inspect(fuse_opts)} (failure_threshold=#{circuit_config.failure_threshold})"
    )

    fuse_opts
  end

  defp execute_with_circuit_breaker(service_id, function) do
    start_time = System.monotonic_time(:millisecond)

    case :fuse.ask(service_id, :sync) do
      :ok ->
        # Circuit is closed, execute the function
        Logger.debug("Circuit #{inspect(service_id)} is closed, executing function")

        try do
          result = function.()
          duration = System.monotonic_time(:millisecond) - start_time

          emit_telemetry(:call_success, %{
            service_id: service_id,
            duration: duration
          })

          {:ok, result}
        rescue
          exception ->
            # Melt the fuse on failure
            Logger.debug(
              "Function failed, melting fuse #{inspect(service_id)}: #{inspect(exception)}"
            )

            :fuse.melt(service_id)
            duration = System.monotonic_time(:millisecond) - start_time

            emit_telemetry(:call_failure, %{
              service_id: service_id,
              duration: duration,
              error: exception
            })

            {:error, Exception.message(exception)}
        catch
          kind, reason ->
            # Melt the fuse on failure
            Logger.debug(
              "Function crashed, melting fuse #{inspect(service_id)}: #{kind} #{inspect(reason)}"
            )

            :fuse.melt(service_id)
            duration = System.monotonic_time(:millisecond) - start_time

            emit_telemetry(:call_failure, %{
              service_id: service_id,
              duration: duration,
              error: {kind, reason}
            })

            {:error, {kind, reason}}
        end

      :blown ->
        # Circuit is open
        Logger.debug("Circuit #{inspect(service_id)} is blown/open")

        emit_telemetry(:call_rejected, %{
          service_id: service_id,
          reason: :circuit_open
        })

        {:error, :circuit_open}

      {:error, :not_found} ->
        Logger.debug("Fuse #{inspect(service_id)} not found")
        {:error, :service_not_found}
    end
  end

  defp get_fuse_status(service_id) do
    case :fuse.ask(service_id, :sync) do
      :ok -> :closed
      :blown -> :open
      _ -> :unknown
    end
  end

  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:foundation, :circuit_breaker, event],
      %{count: 1},
      metadata
    )
  rescue
    _ -> :ok
  end

  # Foundation.Infrastructure protocol implementation

  @impl Foundation.Infrastructure
  def protocol_version(_impl), do: {:ok, "1.0"}

  @impl Foundation.Infrastructure
  def register_circuit_breaker(_impl, service_id, config) do
    # Convert config to keyword list if it's a map
    config_kwlist = if is_map(config), do: Map.to_list(config), else: config
    configure(service_id, config_kwlist)
  end

  @impl Foundation.Infrastructure
  def execute_protected(_impl, service_id, function, _context) do
    call(service_id, function)
  end

  @impl Foundation.Infrastructure
  def get_circuit_status(_impl, service_id) do
    get_status(service_id)
  end

  # These functions are not applicable to circuit breaker

  @impl Foundation.Infrastructure
  def setup_rate_limiter(_impl, _limiter_id, _config) do
    {:error, :not_implemented}
  end

  @impl Foundation.Infrastructure
  def check_rate_limit(_impl, _limiter_id, _identifier) do
    {:error, :limiter_not_found}
  end

  @impl Foundation.Infrastructure
  def get_rate_limit_status(_impl, _limiter_id, _identifier) do
    {:error, :not_implemented}
  end

  @impl Foundation.Infrastructure
  def monitor_resource(_impl, _resource_id, _config) do
    {:error, :not_implemented}
  end

  @impl Foundation.Infrastructure
  def get_resource_usage(_impl, _resource_id) do
    {:error, :not_implemented}
  end
end
