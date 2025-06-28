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

  alias Foundation.Infrastructure.{CircuitBreaker, ConnectionManager, RateLimiter}
  alias Foundation.Services.TelemetryService
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
  def initialize_all_infra_components do
    initialize_all_infra_components(%{})
  end

  @doc """
  Get the status of all infrastructure components.

  ## Examples

      iex> Infrastructure.get_infrastructure_status()
      {:ok, %{fuse: :running, hammer: :running}}
  """
  @spec get_infrastructure_status() :: {:ok, map()} | {:error, term()}
  def get_infrastructure_status do
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

  Stores configuration in main ConfigServer for unified configuration management.

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
        # Store in main ConfigServer instead of private Agent
        config_path = [:infrastructure, :protection, protection_key]

        case Foundation.Config.update(config_path, config) do
          :ok ->
            Logger.info("Configured protection for #{protection_key}")
            :ok

          {:error, reason} ->
            Logger.warning(
              "Failed to store protection config for #{protection_key}: #{inspect(reason)}"
            )

            {:error, reason}
        end

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
    config_path = [:infrastructure, :protection, protection_key]

    case Foundation.Config.get(config_path) do
      {:ok, config} -> {:ok, config}
      {:error, %Foundation.Types.Error{error_type: :config_path_not_found}} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
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
    config_path = [:infrastructure, :protection]

    case Foundation.Config.get(config_path) do
      {:ok, protection_configs} when is_map(protection_configs) ->
        Map.keys(protection_configs)

      {:error, _} ->
        []
    end
  end

  @doc """
  Initialize a circuit breaker with the given configuration.

  Creates and configures a circuit breaker that can be used with execute_protected.
  The circuit breaker will use the :fuse library for the actual circuit breaking logic.

  ## Parameters
  - `name` - Atom identifier for the circuit breaker
  - `config` - Configuration map with required keys

  ## Configuration Keys
  - `:failure_threshold` - Number of failures before opening circuit (required)
  - `:recovery_time` - Time in milliseconds before attempting recovery (required)

  ## Examples

      # Initialize with custom configuration
      :ok = Infrastructure.initialize_circuit_breaker(:api_breaker, %{
        failure_threshold: 5,
        recovery_time: 30_000
      })

      # Use in execute_protected
      Infrastructure.execute_protected(:api, [circuit_breaker: :api_breaker], fn ->
        # Your operation here
      end)

  ## Returns
  - `:ok` - Circuit breaker initialized successfully
  - `{:error, reason}` - Initialization failed
  """
  @spec initialize_circuit_breaker(atom(), map()) :: :ok | {:error, Error.t()}
  def initialize_circuit_breaker(name, config) when is_atom(name) and is_map(config) do
    with :ok <- validate_circuit_breaker_name(name),
         :ok <- validate_circuit_breaker_init_config(config),
         :ok <- ensure_circuit_breaker_not_exists(name) do
      # Convert Foundation config to Fuse format
      fuse_config = [
        strategy: :standard,
        tolerance: config.failure_threshold,
        refresh: config.recovery_time
      ]

      case CircuitBreaker.start_fuse_instance(name, fuse_config) do
        :ok ->
          Logger.info("Initialized circuit breaker #{inspect(name)} with config #{inspect(config)}")
          :ok

        {:error, reason} ->
          {:error,
           Error.new(
             error_type: :circuit_breaker_init_failed,
             message: "Failed to initialize circuit breaker #{inspect(name)}: #{inspect(reason)}",
             context: %{name: name, config: config, fuse_reason: reason}
           )}
      end
    end
  end

  def initialize_circuit_breaker(name, config) do
    {:error,
     Error.new(
       error_type: :invalid_arguments,
       message: "Circuit breaker name must be an atom and config must be a map",
       context: %{name: name, config: config}
     )}
  end

  @doc """
  Initialize a circuit breaker with default configuration.

  Uses sensible defaults for failure threshold and recovery time.

  ## Parameters
  - `name` - Atom identifier for the circuit breaker

  ## Default Configuration
  - `:failure_threshold` - 5 failures
  - `:recovery_time` - 30,000 milliseconds (30 seconds)

  ## Examples

      :ok = Infrastructure.initialize_circuit_breaker(:default_breaker)

  ## Returns
  - `:ok` - Circuit breaker initialized successfully
  - `{:error, reason}` - Initialization failed
  """
  @spec initialize_circuit_breaker(atom()) :: :ok | {:error, Error.t()}
  def initialize_circuit_breaker(name) when is_atom(name) do
    default_config = %{
      failure_threshold: 5,
      recovery_time: 30_000
    }

    initialize_circuit_breaker(name, default_config)
  end

  def initialize_circuit_breaker(name) do
    {:error,
     Error.new(
       error_type: :invalid_name,
       message: "Circuit breaker name must be an atom",
       context: %{name: name}
     )}
  end

  ## Private Functions

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
        execute_with_named_circuit_breaker(circuit_breaker_name, options, fun)
    end
  end

  defp execute_with_named_circuit_breaker(circuit_breaker_name, options, fun) do
    case CircuitBreaker.execute(circuit_breaker_name, fn ->
           execute_with_connection_pool(options, fun)
         end) do
      {:ok, {:ok, result}} -> {:ok, result}
      {:ok, {:error, reason}} -> {:error, reason}
      other -> other
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
         :ok <- validate_rate_limiter_config(config.rate_limiter) do
      validate_connection_pool_config(config.connection_pool)
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

  # Helper functions for circuit breaker initialization

  @spec validate_circuit_breaker_name(term()) :: :ok | {:error, Error.t()}
  defp validate_circuit_breaker_name(name) when is_atom(name) and not is_nil(name) do
    case Atom.to_string(name) do
      "" ->
        {:error,
         Error.new(
           error_type: :invalid_name,
           message: "Circuit breaker name cannot be an empty atom",
           context: %{name: name}
         )}

      _valid_name ->
        :ok
    end
  end

  defp validate_circuit_breaker_name(name) do
    {:error,
     Error.new(
       error_type: :invalid_name,
       message: "Circuit breaker name must be a non-nil atom",
       context: %{name: name, type: get_type(name)}
     )}
  end

  @spec validate_circuit_breaker_init_config(term()) :: :ok | {:error, Error.t()}
  defp validate_circuit_breaker_init_config(config) when is_map(config) do
    with :ok <- validate_failure_threshold(config) do
      validate_recovery_time(config)
    end
  end

  defp validate_circuit_breaker_init_config(config) do
    {:error,
     Error.new(
       error_type: :invalid_configuration,
       message: "Circuit breaker configuration must be a map",
       context: %{config: config, type: get_type(config)}
     )}
  end

  @spec validate_failure_threshold(map()) :: :ok | {:error, Error.t()}
  defp validate_failure_threshold(%{failure_threshold: threshold})
       when is_integer(threshold) and threshold > 0 do
    :ok
  end

  defp validate_failure_threshold(%{failure_threshold: threshold}) do
    {:error,
     Error.new(
       error_type: :invalid_configuration,
       message: "failure_threshold must be a positive integer",
       context: %{failure_threshold: threshold, type: get_type(threshold)}
     )}
  end

  defp validate_failure_threshold(_config) do
    {:error,
     Error.new(
       error_type: :invalid_configuration,
       message: "failure_threshold is required",
       context: %{missing_key: :failure_threshold}
     )}
  end

  @spec validate_recovery_time(map()) :: :ok | {:error, Error.t()}
  defp validate_recovery_time(%{recovery_time: time})
       when is_integer(time) and time > 0 do
    :ok
  end

  defp validate_recovery_time(%{recovery_time: time}) do
    {:error,
     Error.new(
       error_type: :invalid_configuration,
       message: "recovery_time must be a positive integer (milliseconds)",
       context: %{recovery_time: time, type: get_type(time)}
     )}
  end

  defp validate_recovery_time(_config) do
    {:error,
     Error.new(
       error_type: :invalid_configuration,
       message: "recovery_time is required",
       context: %{missing_key: :recovery_time}
     )}
  end

  @spec ensure_circuit_breaker_not_exists(atom()) :: :ok | {:error, Error.t()}
  defp ensure_circuit_breaker_not_exists(name) do
    case CircuitBreaker.get_status(name) do
      :ok ->
        {:error,
         Error.new(
           error_type: :already_exists,
           message: "Circuit breaker #{inspect(name)} already exists",
           context: %{name: name}
         )}

      {:error, _} ->
        # Circuit breaker doesn't exist, which is what we want
        :ok

      :blown ->
        {:error,
         Error.new(
           error_type: :already_exists,
           message: "Circuit breaker #{inspect(name)} already exists (currently blown)",
           context: %{name: name, status: :blown}
         )}
    end
  end

  @spec get_type(term()) :: atom()
  defp get_type(value) do
    cond do
      is_atom(value) -> :atom
      is_binary(value) -> :string
      is_integer(value) -> :integer
      is_float(value) -> :float
      is_list(value) -> :list
      is_map(value) -> :map
      is_tuple(value) -> :tuple
      is_pid(value) -> :pid
      is_function(value) -> :function
      true -> :unknown
    end
  end
end
