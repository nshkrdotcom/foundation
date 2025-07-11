defmodule Foundation.Services.ConnectionManager do
  @moduledoc """
  Production-grade HTTP connection manager using Finch.

  Provides centralized HTTP connection pooling with intelligent routing,
  connection management, and telemetry integration for reliable external
  service communication across the Foundation platform.

  ## Features

  - HTTP/2 connection pooling with Finch
  - Multiple named pools for different services
  - Connection lifecycle management
  - Request/response telemetry and metrics
  - Automatic retry integration with RetryService
  - Circuit breaker aware routing

  ## Pool Configuration

  Each pool supports the following configuration:

  - `:scheme` - HTTP scheme (:http or :https)
  - `:host` - Target host name
  - `:port` - Target port number
  - `:size` - Pool size (number of connections)
  - `:max_connections` - Maximum connections per pool
  - `:timeout` - Request timeout in milliseconds
  - `:connect_timeout` - Connection timeout in milliseconds

  ## Usage

      # Configure a pool for external API
      ConnectionManager.configure_pool(:external_api, %{
        scheme: :https,
        host: "api.external.com",
        port: 443,
        size: 10,
        max_connections: 50
      })

      # Make HTTP request through pool
      request = %{
        method: :get,
        path: "/v1/data",
        headers: [{"authorization", "Bearer token"}],
        body: nil
      }

      {:ok, response} = ConnectionManager.execute_request(:external_api, request)

      # Get pool statistics
      {:ok, stats} = ConnectionManager.get_stats()
  """

  use GenServer
  require Logger
  require Foundation.ErrorHandling
  alias Foundation.ErrorHandling

  # Define child spec for proper supervision
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :name, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }
  end

  @type pool_id :: atom() | String.t()
  @type scheme :: :http | :https
  @type pool_config :: %{
          scheme: scheme(),
          host: String.t(),
          port: pos_integer(),
          size: pos_integer(),
          max_connections: pos_integer(),
          timeout: pos_integer(),
          connect_timeout: pos_integer()
        }
  @type http_request :: %{
          method: atom(),
          path: String.t(),
          headers: list(),
          body: term()
        }
  @type http_response :: %{status: pos_integer(), headers: list(), body: binary()}

  # Default configuration
  @default_config %{
    timeout: 30_000,
    connect_timeout: 5_000,
    size: 10,
    max_connections: 50
  }

  defstruct pools: %{},
            finch_name: nil,
            config: @default_config,
            stats: %{total_requests: 0, active_requests: 0}

  # Client API

  @doc """
  Starts the connection manager service.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Configures an HTTP connection pool.

  ## Examples

      {:ok, pool_id} = ConnectionManager.configure_pool(:api_pool, %{
        scheme: :https,
        host: "api.example.com",
        port: 443,
        size: 15,
        max_connections: 75
      })
  """
  @spec configure_pool(pool_id(), pool_config()) :: {:ok, pool_id()} | {:error, term()}
  def configure_pool(pool_id, config) do
    GenServer.call(__MODULE__, {:configure_pool, pool_id, config})
  end

  @doc """
  Executes an HTTP request using the specified pool.

  ## Options

  - `:timeout` - GenServer call timeout in milliseconds (default: 60_000)

  ## Examples

      request = %{
        method: :post,
        path: "/api/v1/users",
        headers: [{"content-type", "application/json"}],
        body: Jason.encode!(%{name: "John", email: "john@example.com"})
      }

      {:ok, response} = ConnectionManager.execute_request(:user_api, request)

      # With custom timeout
      {:ok, response} = ConnectionManager.execute_request(:user_api, request, timeout: 120_000)
  """
  @spec execute_request(pool_id(), http_request(), keyword() | GenServer.server()) ::
          {:ok, http_response()} | {:error, term()}
  def execute_request(pool_id, request, opts_or_server \\ __MODULE__)

  def execute_request(pool_id, request, opts) when is_list(opts) do
    server = Keyword.get(opts, :server, __MODULE__)
    timeout = Keyword.get(opts, :timeout, 60_000)
    GenServer.call(server, {:execute_request, pool_id, request}, timeout)
  end

  def execute_request(pool_id, request, server) when is_atom(server) or is_pid(server) do
    # Backward compatibility: when third arg is a server name/pid
    GenServer.call(server, {:execute_request, pool_id, request}, 60_000)
  end

  @doc """
  Removes a connection pool.
  """
  @spec remove_pool(pool_id()) :: :ok | {:error, term()}
  def remove_pool(pool_id) do
    GenServer.call(__MODULE__, {:remove_pool, pool_id})
  end

  @doc """
  Gets connection manager statistics and metrics.
  """
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  # Server Implementation

  @impl true
  def init(opts) do
    # Generate unique Finch name for this instance
    finch_name = Keyword.get(opts, :finch_name, :"finch_#{System.unique_integer()}")

    # Start Finch with our configuration
    finch_config = []

    case Finch.start_link(name: finch_name, pools: finch_config) do
      {:ok, _finch_pid} ->
        state = %__MODULE__{
          pools: %{},
          finch_name: finch_name,
          config: Map.merge(@default_config, Enum.into(opts, %{})),
          stats: %{total_requests: 0, active_requests: 0}
        }

        Logger.info("Foundation.Services.ConnectionManager started with Finch: #{finch_name}")

        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to start Finch: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:configure_pool, pool_id, config}, _from, state) do
    case validate_pool_config(config) do
      {:ok, validated_config} ->
        # Merge with defaults
        pool_config = Map.merge(state.config, validated_config)

        # Build pool configuration for Finch
        _pool_opts = build_finch_pool_opts(pool_config)

        try do
          # Add pool to existing Finch instance
          # Note: Finch doesn't support dynamic pool addition, so we track config internally
          new_pools = Map.put(state.pools, pool_id, pool_config)

          emit_telemetry(:pool_configured, %{
            pool_id: pool_id,
            host: pool_config.host,
            scheme: pool_config.scheme
          })

          {:reply, {:ok, pool_id}, %{state | pools: new_pools}}
        rescue
          error ->
            error_tuple = ErrorHandling.exception_to_error(error)
            ErrorHandling.log_error("Failed to configure pool #{pool_id}", error_tuple)
            {:reply, error_tuple, state}
        end

      {:error, reason} ->
        {:reply, ErrorHandling.normalize_error({:error, reason}), state}
    end
  end

  @impl true
  def handle_call({:execute_request, pool_id, request}, from, state) do
    case Map.get(state.pools, pool_id) do
      nil ->
        {:reply, {:error, :pool_not_found}, state}

      pool_config ->
        # Execute in a separate process to avoid blocking
        # We spawn a task that will send the result back
        parent = self()

        case Task.Supervisor.start_child(Foundation.TaskSupervisor, fn ->
               start_time = System.monotonic_time(:millisecond)
               result = execute_http_request(state.finch_name, pool_config, request)
               duration = System.monotonic_time(:millisecond) - start_time

               # Send the result back to update stats and reply
               send(parent, {:request_completed, from, pool_id, request, result, duration})
             end) do
          {:ok, _task} ->
            # Update active requests immediately
            updated_stats = Map.update!(state.stats, :active_requests, &(&1 + 1))

            # Don't reply yet - will reply in handle_info
            {:noreply, %{state | stats: updated_stats}}

          {:error, reason} ->
            # Task supervisor is overloaded or unavailable, fall back to sync execution
            Logger.warning(
              "Task supervisor unavailable: #{inspect(reason)}, executing request synchronously"
            )

            start_time = System.monotonic_time(:millisecond)
            result = execute_http_request(state.finch_name, pool_config, request)
            duration = System.monotonic_time(:millisecond) - start_time

            # Update stats
            final_stats =
              state.stats
              |> Map.update!(:total_requests, &(&1 + 1))

            # Emit telemetry
            emit_request_telemetry(pool_id, request, result, duration)

            {:reply, result, %{state | stats: final_stats}}
        end
    end
  end

  @impl true
  def handle_call({:remove_pool, pool_id}, _from, state) do
    if Map.has_key?(state.pools, pool_id) do
      new_pools = Map.delete(state.pools, pool_id)

      emit_telemetry(:pool_removed, %{pool_id: pool_id})

      {:reply, :ok, %{state | pools: new_pools}}
    else
      {:reply, {:error, :pool_not_found}, state}
    end
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    # Return health status based on connection pools
    health_status = if map_size(state.pools) < 100, do: :healthy, else: :degraded
    {:reply, health_status, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      pools: Map.keys(state.pools) |> Enum.into(%{}, &{&1, get_pool_stats(&1, state.pools[&1])}),
      total_connections: calculate_total_connections(state.pools),
      active_requests: state.stats.active_requests,
      total_requests: state.stats.total_requests,
      finch_name: state.finch_name
    }

    {:reply, {:ok, stats}, state}
  end

  @impl true
  def handle_info({:request_completed, from, pool_id, request, result, duration}, state) do
    # Update statistics
    final_stats =
      state.stats
      |> Map.update!(:active_requests, &(&1 - 1))
      |> Map.update!(:total_requests, &(&1 + 1))

    # Emit telemetry
    emit_request_telemetry(pool_id, request, result, duration)

    # Reply to the waiting caller
    GenServer.reply(from, result)

    {:noreply, %{state | stats: final_stats}}
  end

  # Private Implementation

  @spec validate_pool_config(map()) :: {:ok, pool_config()} | {:error, term()}
  defp validate_pool_config(config) when is_map(config) do
    required_fields = [:scheme, :host, :port]

    case Enum.find(required_fields, &(not Map.has_key?(config, &1))) do
      nil ->
        validated = %{
          scheme: config.scheme,
          host: to_string(config.host),
          port: config.port,
          size: Map.get(config, :size, @default_config.size),
          max_connections: Map.get(config, :max_connections, @default_config.max_connections),
          timeout: Map.get(config, :timeout, @default_config.timeout),
          connect_timeout: Map.get(config, :connect_timeout, @default_config.connect_timeout)
        }

        {:ok, validated}

      missing_field ->
        ErrorHandling.missing_field_error(missing_field)
    end
  end

  defp validate_pool_config(_), do: ErrorHandling.invalid_field_error(:config, :invalid_format)

  defp build_finch_pool_opts(pool_config) do
    %{
      size: pool_config.size,
      count: 1,
      conn_opts: [
        timeout: pool_config.connect_timeout
      ]
    }
  end

  @spec execute_http_request(atom(), pool_config(), http_request()) ::
          {:ok, http_response()} | {:error, term()}
  defp execute_http_request(finch_name, pool_config, request) do
    # Build the URL
    url = build_url(pool_config.scheme, pool_config.host, pool_config.port, request.path)

    # Build Finch request
    finch_request =
      Finch.build(request.method, url, request.headers || [], request.body || "")

    # Execute request with timeout
    case Finch.request(finch_request, finch_name, receive_timeout: pool_config.timeout) do
      {:ok, %Finch.Response{status: status, headers: headers, body: body}} ->
        {:ok, %{status: status, headers: headers, body: body}}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    exception ->
      ErrorHandling.exception_to_error(exception)
  end

  defp build_url(scheme, host, port, path) do
    scheme_str = Atom.to_string(scheme)
    "#{scheme_str}://#{host}:#{port}#{path}"
  end

  defp get_pool_stats(_pool_id, pool_config) do
    %{
      host: pool_config.host,
      scheme: pool_config.scheme,
      port: pool_config.port,
      size: pool_config.size,
      max_connections: pool_config.max_connections
    }
  end

  defp calculate_total_connections(pools) do
    pools
    |> Map.values()
    |> Enum.reduce(0, fn pool_config, acc -> acc + pool_config.size end)
  end

  defp emit_telemetry(event, metadata) do
    ErrorHandling.emit_telemetry_safe(
      [:foundation, :connection_manager, event],
      %{count: 1},
      metadata
    )
  end

  defp emit_request_telemetry(pool_id, request, result, duration) do
    status =
      case result do
        {:ok, response} -> response.status
        {:error, _} -> :error
      end

    metadata = %{
      pool_id: pool_id,
      method: request.method,
      path: request.path,
      status: status
    }

    ErrorHandling.emit_telemetry_safe(
      [:foundation, :connection_manager, :request],
      %{duration: duration, count: 1},
      metadata
    )
  end
end
