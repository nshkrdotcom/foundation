defmodule Foundation.Infrastructure do
  @moduledoc """
  Unified infrastructure facade orchestrating multiple protection patterns.

  This module provides a single entry point for coordinating circuit breakers,
  rate limiting, and connection pooling to create resilient service operations.
  It implements the Facade pattern to simplify interaction with complex
  infrastructure components.

  ## Usage

      # Execute a protected operation with all safeguards
      result = Infrastructure.execute_protected(:external_api, [
        circuit_breaker: :api_breaker,
        rate_limiter: {:api_calls, "user:123"},
        connection_pool: :http_pool
      ], fn ->
        # Your operation here
        HTTPClient.get("/api/data")
      end)

      # Configure protection rules
      Infrastructure.configure_protection(:external_api, %{
        circuit_breaker: %{
          failure_threshold: 5,
          recovery_time: 30_000
        },
        rate_limiter: %{
          scale: 60_000,    # 1 minute
          limit: 100        # 100 requests per minute
        },
        connection_pool: %{
          size: 10,
          max_overflow: 5
        }
      })

  ## Protection Layers

  1. **Rate Limiting** - First line of defense, prevents overwhelming downstream
  2. **Circuit Breaker** - Fails fast when downstream is unhealthy
  3. **Connection Pool** - Manages resource allocation efficiently

  ## Telemetry Events

  - `[:foundation, :foundation, :infrastructure, :execute_start]`
  - `[:foundation, :foundation, :infrastructure, :execute_stop]`
  - `[:foundation, :foundation, :infrastructure, :execute_exception]`
  - `[:foundation, :foundation, :infrastructure, :protection_triggered]`
  """

  require Logger

  alias Foundation.Infrastructure.{CircuitBreaker, RateLimiter, ConnectionManager}
  alias Foundation.Services.{TelemetryService}
  alias Foundation.Types.Error

  @type protection_key :: atom()
  @type protection_options :: [
          circuit_breaker: atom(),
          rate_limiter: {atom(), binary()},
          connection_pool: atom(),
          timeout: timeout()
        ]
  @type protection_config :: %{
          circuit_breaker: map(),
          rate_limiter: map(),
          connection_pool: map()
        }
  @type execution_result :: {:ok, term()} | {:error, term()}

  @default_timeout 5_000
  @agent_name __MODULE__.ConfigAgent

  ## Public API

  @doc """
  Initialize all infrastructure components.

  Sets up supervision and configuration for Fuse, Hammer, and Poolboy.
  This function should be called during application startup.

  ## Examples

      iex> Infrastructure.initialize_all_infra_components()
      {:ok, []}
  """
  @spec initialize_all_infra_components() :: {:ok, []} | {:error, term()}
  def initialize_all_infra_components() do
    initialize_all_infra_components(%{})
  end

  @doc """
  Get the status of all infrastructure components.

  ## Examples

      iex> Infrastructure.get_infrastructure_status()
      {:ok, %{fuse: :running, hammer: :running}}
  """
  @spec get_infrastructure_status() :: {:ok, map()} | {:error, term()}
  def get_infrastructure_status() do
    try do
      fuse_status =
        case Process.whereis(:fuse_sup) do
          nil -> :not_started
          pid when is_pid(pid) -> :running
        end

      hammer_status =
        case Application.get_env(:hammer, :backend) do
          nil -> :not_configured
          _ -> :configured
        end

      status = %{
        fuse: fuse_status,
        hammer: hammer_status,
        timestamp: System.system_time(:millisecond)
      }

      {:ok, status}
    rescue
      exception ->
        {:error, {:infrastructure_status_error, exception}}
    end
  end

  @doc """
  Executes a function with comprehensive protection patterns applied.

  Applies protection layers in order: rate limiting → circuit breaker → connection pooling.
  Each layer can abort the execution early if protection rules are triggered.

  ## Parameters
  - `protection_key` - Identifier for protection configuration
  - `options` - Protection layer options
  - `fun` - Function to execute with protection

  ## Returns
  - `{:ok, result}` - Function executed successfully
  - `{:error, reason}` - Execution blocked or failed
  """
  @spec execute_protected(protection_key(), protection_options(), (-> term())) ::
          execution_result()
  def execute_protected(protection_key, options, fun) do
    start_time = System.monotonic_time()

    emit_telemetry(:execute_start, %{protection_key: protection_key}, %{
      options: sanitize_options(options)
    })

    try do
      with {:ok, _} <- check_rate_limit(options),
           {:ok, result} <- execute_with_circuit_breaker(options, fun) do
        duration = System.monotonic_time() - start_time

        emit_telemetry(:execute_stop, %{protection_key: protection_key}, %{
          duration: duration,
          success: true
        })

        {:ok, result}
      else
        {:error, reason} = error ->
          duration = System.monotonic_time() - start_time

          emit_telemetry(:execute_stop, %{protection_key: protection_key}, %{
            duration: duration,
            success: false,
            reason: reason
          })

          error
      end
    rescue
      error ->
        duration = System.monotonic_time() - start_time

        emit_telemetry(:execute_exception, %{protection_key: protection_key}, %{
          duration: duration,
          error: inspect(error)
        })

        {:error, {:exception, error}}
    end
  end

  @doc """
  Configures protection rules for a specific key.

  Stores configuration in internal state for runtime access and validation.

  ## Parameters
  - `protection_key` - Identifier for protection configuration
  - `config` - Protection layer configurations

  ## Returns
  - `:ok` - Configuration stored successfully
  - `{:error, reason}` - Configuration invalid or storage failed
  """
  @spec configure_protection(protection_key(), protection_config()) :: :ok | {:error, term()}
  def configure_protection(protection_key, config) do
    case validate_protection_config(config) do
      :ok ->
        # Ensure Agent is started
        ensure_config_agent_started()

        # Store in Agent instead of ConfigServer
        Agent.update(@agent_name, fn state ->
          Map.put(state, protection_key, config)
        end)

        Logger.info("Configured protection for #{protection_key}")
        :ok

      {:error, reason} ->
        Logger.warning("Invalid protection config for #{protection_key}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Gets the current protection configuration for a key.

  ## Parameters
  - `protection_key` - Identifier for protection configuration

  ## Returns
  - `{:ok, config}` - Current configuration
  - `{:error, :not_found}` - No configuration exists
  """
  @spec get_protection_config(protection_key()) :: {:ok, any()} | {:error, any()}
  def get_protection_config(protection_key) do
    case ensure_config_agent_started() do
      :ok ->
        case Agent.get(@agent_name, fn state -> Map.get(state, protection_key) end) do
          nil -> {:error, :not_found}
          config -> {:ok, config}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets comprehensive status of all protection layers for a key.

  ## Parameters
  - `protection_key` - Identifier for protection status

  ## Returns
  - `{:ok, status}` - Status of all protection layers
  - `{:error, reason}` - Status retrieval failed
  """
  @spec get_protection_status(protection_key()) :: {:ok, map()} | {:error, term()}
  def get_protection_status(protection_key) do
    with {:ok, config} <- get_protection_config(protection_key) do
      status = %{
        circuit_breaker: get_circuit_breaker_status(config),
        rate_limiter: get_rate_limiter_status(config),
        connection_pool: get_connection_pool_status(config)
      }

      {:ok, status}
    end
  end

  @doc """
  Lists all configured protection keys.

  ## Returns
  - `[protection_key]` - List of configured protection keys
  """
  @spec list_protection_keys() :: [protection_key()]
  def list_protection_keys do
    case ensure_config_agent_started() do
      :ok ->
        Agent.get(@agent_name, fn state -> Map.keys(state) end)

      {:error, _} ->
        []
    end
  end

  ## Private Functions

  @spec ensure_config_agent_started() :: :ok | {:error, term()}
  defp ensure_config_agent_started do
    case Process.whereis(@agent_name) do
      nil ->
        case Agent.start_link(fn -> %{} end, name: @agent_name) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> {:error, reason}
        end

      _pid ->
        :ok
    end
  end

  @spec check_rate_limit(protection_options()) :: {:ok, :allowed} | {:error, term()}
  defp check_rate_limit(options) do
    case Keyword.get(options, :rate_limiter) do
      nil ->
        {:ok, :allowed}

      {rule_name, identifier} ->
        case RateLimiter.check_rate(identifier, rule_name, 100, 60_000) do
          :ok ->
            {:ok, :allowed}

          {:error, %Error{error_type: :rate_limit_exceeded} = error} ->
            emit_protection_triggered(:rate_limit, %{
              rule_name: rule_name,
              identifier: identifier
            })

            {:error, error}

          {:error, reason} ->
            {:error, {:rate_limit_error, reason}}
        end
    end
  end

  @spec execute_with_circuit_breaker(protection_options(), (-> term())) ::
          {:ok, term()} | {:error, term()}
  defp execute_with_circuit_breaker(options, fun) do
    case Keyword.get(options, :circuit_breaker) do
      nil ->
        execute_with_connection_pool(options, fun)

      circuit_breaker_name ->
        case CircuitBreaker.execute(circuit_breaker_name, fn ->
               execute_with_connection_pool(options, fun)
             end) do
          {:ok, {:ok, result}} -> {:ok, result}
          {:ok, {:error, reason}} -> {:error, reason}
          other -> other
        end
    end
  end

  @spec execute_with_connection_pool(protection_options(), (-> term())) ::
          {:ok, term()} | {:error, term()}
  defp execute_with_connection_pool(options, fun) do
    case Keyword.get(options, :connection_pool) do
      nil ->
        try do
          result = fun.()
          {:ok, result}
        rescue
          error -> {:error, {:execution_error, error}}
        end

      pool_name ->
        timeout = Keyword.get(options, :timeout, @default_timeout)

        ConnectionManager.with_connection(
          pool_name,
          fn _worker ->
            fun.()
          end,
          timeout
        )
    end
  end

  @spec validate_protection_config(protection_config()) :: :ok | {:error, term()}
  defp validate_protection_config(config) when is_map(config) do
    required_keys = [:circuit_breaker, :rate_limiter, :connection_pool]

    case Enum.all?(required_keys, &Map.has_key?(config, &1)) do
      true -> validate_individual_configs(config)
      false -> {:error, :missing_required_keys}
    end
  end

  defp validate_protection_config(_), do: {:error, :invalid_config_format}

  @spec validate_individual_configs(protection_config()) :: :ok | {:error, term()}
  defp validate_individual_configs(config) do
    with :ok <- validate_circuit_breaker_config(config.circuit_breaker),
         :ok <- validate_rate_limiter_config(config.rate_limiter),
         :ok <- validate_connection_pool_config(config.connection_pool) do
      :ok
    end
  end

  @spec validate_circuit_breaker_config(map()) :: :ok | {:error, term()}
  defp validate_circuit_breaker_config(config) when is_map(config) do
    required_keys = [:failure_threshold, :recovery_time]

    case Enum.all?(required_keys, &Map.has_key?(config, &1)) do
      true -> :ok
      false -> {:error, :invalid_circuit_breaker_config}
    end
  end

  defp validate_circuit_breaker_config(_), do: {:error, :invalid_circuit_breaker_config}

  @spec validate_rate_limiter_config(map()) :: :ok | {:error, term()}
  defp validate_rate_limiter_config(config) when is_map(config) do
    required_keys = [:scale, :limit]

    case Enum.all?(required_keys, &Map.has_key?(config, &1)) do
      true -> :ok
      false -> {:error, :invalid_rate_limiter_config}
    end
  end

  defp validate_rate_limiter_config(_), do: {:error, :invalid_rate_limiter_config}

  @spec validate_connection_pool_config(map()) :: :ok | {:error, term()}
  defp validate_connection_pool_config(config) when is_map(config) do
    required_keys = [:size, :max_overflow]

    case Enum.all?(required_keys, &Map.has_key?(config, &1)) do
      true -> :ok
      false -> {:error, :invalid_connection_pool_config}
    end
  end

  defp validate_connection_pool_config(_), do: {:error, :invalid_connection_pool_config}

  @spec get_circuit_breaker_status(protection_config()) :: map()
  defp get_circuit_breaker_status(_config) do
    # This would integrate with actual circuit breaker status
    # For now, return placeholder status
    %{status: :unknown, message: "Circuit breaker status not implemented"}
  end

  @spec get_rate_limiter_status(protection_config()) :: map()
  defp get_rate_limiter_status(_config) do
    # This would integrate with actual rate limiter status
    # For now, return placeholder status
    %{status: :unknown, message: "Rate limiter status not implemented"}
  end

  @spec get_connection_pool_status(protection_config()) :: map()
  defp get_connection_pool_status(_config) do
    # This would integrate with actual connection pool status
    # For now, return placeholder status
    %{status: :unknown, message: "Connection pool status not implemented"}
  end

  @spec sanitize_options(protection_options()) :: map()
  defp sanitize_options(options) when is_list(options) do
    # Remove sensitive data from options for telemetry
    options
    |> Keyword.take([:circuit_breaker, :connection_pool, :timeout])
    |> Enum.into(%{})
  end

  defp sanitize_options(options), do: %{options: inspect(options)}

  @spec emit_protection_triggered(atom(), map()) :: :ok
  defp emit_protection_triggered(protection_type, metadata) do
    emit_telemetry(:protection_triggered, %{protection_type: protection_type}, metadata)
  end

  @spec emit_telemetry(atom(), map(), map()) :: :ok
  defp emit_telemetry(event, measurements, metadata) do
    TelemetryService.execute(
      [:foundation, :foundation, :infrastructure, event],
      measurements,
      metadata
    )
  end

  @spec initialize_all_infra_components(map()) :: {:ok, []} | {:error, term()}
  defp initialize_all_infra_components(config) do
    try do
      # Initialize Hammer configuration if not already done
      case Application.get_env(:hammer, :backend) do
        nil ->
          Application.put_env(:hammer, :backend, {Hammer.Backend.ETS,
           [
             # 2 hours
             expiry_ms: 60_000 * 60 * 2,
             # 10 minutes
             cleanup_interval_ms: 60_000 * 10
           ]})

        _ ->
          :ok
      end

      # Ensure Fuse application is started
      case Application.ensure_all_started(:fuse) do
        {:ok, _apps} ->
          :ok

        {:error, reason} ->
          raise "Failed to start Fuse application: #{inspect(reason)}"
      end

      emit_telemetry(
        :infrastructure_initialized,
        %{
          config: config,
          components: [:fuse, :hammer]
        },
        %{}
      )

      {:ok, []}
    rescue
      exception ->
        {:error, {:infrastructure_init_failed, exception}}
    end
  end
end
