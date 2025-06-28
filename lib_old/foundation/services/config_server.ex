defmodule Foundation.Services.ConfigServer do
  @moduledoc """
  Resilient configuration service that handles both normal operation
  and graceful degradation in a single, cohesive interface.

  This module serves as a resilient proxy to the internal GenServer implementation,
  providing built-in fallback mechanisms when the primary service is unavailable.
  All graceful degradation logic is integrated directly into this service layer.

  ## Key Features

  - **Service-Owned Resilience**: All configuration behavior (success and failure paths)
    is owned by this module
  - **Transparent Fallback**: Graceful degradation is built into every public function
  - **Cache Management**: Automatic caching of successful reads for fallback scenarios
  - **Pending Updates**: Failed updates are cached and retried when service recovers
  - **Uniform Error Handling**: Consistent error responses across all operations

  ## Examples

      # All operations automatically include graceful degradation
      {:ok, config} = Foundation.Services.ConfigServer.get()
      {:ok, value} = Foundation.Services.ConfigServer.get([:ai, :provider])
      :ok = Foundation.Services.ConfigServer.update([:ai, :temperature], 0.7)

  The calling code doesn't need to know about fallback mechanisms - they're
  transparent and built into the service contract.
  """

  require Logger

  @behaviour Foundation.Contracts.Configurable

  alias Foundation.ServiceRegistry
  alias Foundation.Logic.ConfigLogic
  alias Foundation.Services.ConfigServer.GenServer, as: ConfigGenServer
  alias Foundation.Types.{Config, Error}
  alias Foundation.Validation.ConfigValidator

  @fallback_table :config_fallback_cache
  # 5 minutes
  @cache_ttl 300

  ## Public API with Built-in Resilience

  @doc """
  Initialize the configuration service.

  Sets up both the internal GenServer and the fallback system.
  """
  @spec initialize() :: :ok | {:error, Error.t()}
  def initialize do
    initialize([])
  end

  @doc """
  Initialize the configuration service with options.
  """
  @spec initialize(keyword()) :: :ok | {:error, Error.t()}
  def initialize(opts) when is_list(opts) do
    # Initialize fallback system first
    initialize_fallback_cache()

    # Check if service is already running in production namespace
    case ServiceRegistry.lookup(:production, :config_server) do
      {:ok, _pid} ->
        # Already running
        :ok

      {:error, _} ->
        # Service not running, try to start it
        case start_link(Keyword.put(opts, :namespace, :production)) do
          {:ok, _pid} ->
            :ok

          {:error, {:already_started, _pid}} ->
            :ok

          {:error, reason} ->
            create_service_unavailable_error("Failed to start ConfigServer: #{inspect(reason)}")
        end
    end
  end

  @doc """
  Get the complete configuration with automatic fallback.
  """
  @impl Foundation.Contracts.Configurable
  @spec get() :: {:ok, Config.t()} | {:error, Error.t()}
  def get do
    try_with_fallback(
      fn ->
        case ServiceRegistry.lookup(:production, :config_server) do
          {:ok, pid} -> GenServer.call(pid, :get_config)
          {:error, _} -> {:error, :service_not_found}
        end
      end,
      fn ->
        {:error, create_service_unavailable_error("get/0")}
      end
    )
  end

  @doc """
  Get a configuration value by path with automatic fallback to cache.
  """
  @impl Foundation.Contracts.Configurable
  @spec get([atom()]) :: {:ok, term()} | {:error, Error.t()}
  def get(path) when is_list(path) do
    try_with_fallback(
      fn ->
        case ServiceRegistry.lookup(:production, :config_server) do
          {:ok, pid} ->
            case GenServer.call(pid, {:get_config_path, path}) do
              {:ok, value} = result ->
                cache_successful_read(path, value)
                result

              error ->
                error
            end

          {:error, _} ->
            {:error, :service_not_found}
        end
      end,
      fn ->
        get_from_cache(path)
      end
    )
  end

  @doc """
  Update a configuration value with pending update caching.
  """
  @impl Foundation.Contracts.Configurable
  @spec update([atom()], term()) :: :ok | {:error, Error.t()}
  def update(path, value) when is_list(path) do
    try_with_fallback(
      fn ->
        case ServiceRegistry.lookup(:production, :config_server) do
          {:ok, pid} ->
            case GenServer.call(pid, {:update_config, path, value}) do
              :ok ->
                clear_pending_update(path)
                :ok

              error ->
                error
            end

          {:error, _} ->
            {:error, :service_not_found}
        end
      end,
      fn ->
        cache_pending_update(path, value)
      end
    )
  end

  @doc """
  Validate a configuration structure.
  """
  @impl Foundation.Contracts.Configurable
  @spec validate(Config.t()) :: :ok | {:error, Error.t()}
  def validate(config) do
    # Validation is stateless, no fallback needed
    ConfigValidator.validate(config)
  end

  @doc """
  Get the list of paths that can be updated at runtime.
  """
  @impl Foundation.Contracts.Configurable
  @spec updatable_paths() :: [[atom(), ...], ...]
  def updatable_paths do
    # This is stateless, no fallback needed
    ConfigLogic.updatable_paths()
  end

  @doc """
  Reset configuration to defaults with resilience.
  """
  @impl Foundation.Contracts.Configurable
  @spec reset() :: :ok | {:error, Error.t()}
  def reset do
    try_with_fallback(
      fn ->
        case ServiceRegistry.lookup(:production, :config_server) do
          {:ok, pid} -> GenServer.call(pid, :reset_config)
          {:error, _} -> {:error, :service_not_found}
        end
      end,
      fn ->
        {:error, create_service_unavailable_error("reset/0")}
      end
    )
  end

  @doc """
  Check if the configuration service is available.
  """
  @impl Foundation.Contracts.Configurable
  @spec available?() :: boolean()
  def available? do
    case ServiceRegistry.lookup(:production, :config_server) do
      {:ok, _pid} -> true
      {:error, _} -> false
    end
  end

  @doc """
  Get configuration service status with resilience.
  """
  @spec status() :: {:ok, map()} | {:error, Error.t()}
  def status do
    try_with_fallback(
      fn ->
        case ServiceRegistry.lookup(:production, :config_server) do
          {:ok, pid} -> GenServer.call(pid, :get_status)
          {:error, _} -> {:error, :service_not_found}
        end
      end,
      fn ->
        {:ok,
         %{
           status: :degraded,
           fallback_mode: true,
           cache_stats: get_cache_stats()
         }}
      end
    )
  end

  @doc """
  Subscribe to configuration change notifications with resilience.
  """
  @spec subscribe(pid()) :: :ok | {:error, Error.t()}
  def subscribe(pid \\ self()) do
    try_with_fallback(
      fn ->
        case ServiceRegistry.lookup(:production, :config_server) do
          {:ok, server_pid} -> GenServer.call(server_pid, {:subscribe, pid})
          {:error, _} -> {:error, :service_not_found}
        end
      end,
      fn ->
        Logger.warning("Configuration service unavailable, subscription failed")
        {:error, create_service_unavailable_error("subscribe/1")}
      end
    )
  end

  @doc """
  Unsubscribe from configuration change notifications with resilience.
  """
  @spec unsubscribe(pid()) :: :ok | {:error, Error.t()}
  def unsubscribe(pid \\ self()) do
    try_with_fallback(
      fn ->
        case ServiceRegistry.lookup(:production, :config_server) do
          {:ok, server_pid} -> GenServer.call(server_pid, {:unsubscribe, pid})
          {:error, _} -> {:error, :service_not_found}
        end
      end,
      fn ->
        # Unsubscribe failing is not critical - return success
        :ok
      end
    )
  end

  @doc """
  Reset all internal state for testing purposes with resilience.
  """
  @spec reset_state() :: :ok | {:error, Error.t()}
  def reset_state do
    if Application.get_env(:foundation, :test_mode, false) do
      try_with_fallback(
        fn ->
          case ServiceRegistry.lookup(:production, :config_server) do
            {:ok, pid} -> GenServer.call(pid, :reset_state)
            {:error, _} -> {:error, :service_not_found}
          end
        end,
        fn ->
          # In test mode, also reset the cache
          cleanup_fallback_cache()
          initialize_fallback_cache()
          :ok
        end
      )
    else
      {:error,
       Error.new(
         code: 5002,
         error_type: :operation_forbidden,
         message: "State reset only allowed in test mode",
         severity: :high,
         category: :security,
         subcategory: :authorization
       )}
    end
  end

  ## Graceful Degradation Management

  @doc """
  Retry all pending configuration updates.
  """
  @spec retry_pending_updates() :: :ok
  def retry_pending_updates do
    # Get all pending updates
    pending_updates =
      :ets.select(@fallback_table, [
        {{{:pending_update, :"$1"}, :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}
      ])

    Logger.debug("Retrying #{length(pending_updates)} pending updates")

    # Try to apply each pending update
    results =
      Enum.map(pending_updates, fn {path, value} ->
        case update(path, value) do
          :ok ->
            Logger.debug("Successfully applied pending update: #{inspect(path)}")
            {:ok, path}

          {:error, reason} ->
            Logger.debug("Pending update still failed: #{inspect(path)} - #{inspect(reason)}")
            {:error, {path, reason}}
        end
      end)

    successful = Enum.count(results, &match?({:ok, _}, &1))
    Logger.info("Retry completed: #{successful}/#{length(pending_updates)} updates successful")

    :ok
  end

  @doc """
  Clean up expired cache entries based on TTL.
  """
  @spec cleanup_expired_cache() :: :ok
  def cleanup_expired_cache do
    current_time = System.system_time(:second)

    # Get all entries and remove expired ones
    :ets.foldl(
      fn
        {key, _value, timestamp}, _acc when is_integer(timestamp) ->
          if current_time - timestamp > @cache_ttl do
            :ets.delete(@fallback_table, key)
          end

          :ok

        _entry, _acc ->
          :ok
      end,
      :ok,
      @fallback_table
    )

    Logger.debug("Expired cache entries cleaned up")
    :ok
  catch
    :error, :badarg ->
      Logger.debug("Cache table not found during cleanup")
      :ok
  end

  @doc """
  Get current cache statistics.
  """
  @spec get_cache_stats() ::
          %{
            total_entries: non_neg_integer(),
            memory_words: non_neg_integer(),
            config_cache_entries: non_neg_integer(),
            pending_update_entries: non_neg_integer()
          }
          | %{error: :table_not_found}
  def get_cache_stats do
    try do
      size = :ets.info(@fallback_table, :size)
      memory = :ets.info(@fallback_table, :memory)

      # Count different types of entries
      config_entries =
        :ets.select_count(@fallback_table, [
          {{{:config_cache, :"$1"}, :"$2", :"$3"}, [], [true]}
        ])

      pending_entries =
        :ets.select_count(@fallback_table, [
          {{{:pending_update, :"$1"}, :"$2", :"$3"}, [], [true]}
        ])

      %{
        total_entries: size,
        memory_words: memory,
        config_cache_entries: config_entries,
        pending_update_entries: pending_entries
      }
    catch
      :error, :badarg ->
        %{error: :table_not_found}
    end
  end

  ## GenServer Lifecycle Management

  @doc """
  Returns a specification to start this module under a supervisor.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 10_000
    }
  end

  @doc """
  Start the configuration server.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    # Ensure fallback system is initialized
    initialize_fallback_cache()

    # Start the actual GenServer
    _namespace = Keyword.get(opts, :namespace, :production)
    ConfigGenServer.start_link(opts)
  end

  @doc """
  Stop the configuration server.
  """
  @spec stop() :: :ok
  def stop do
    case ServiceRegistry.lookup(:production, :config_server) do
      {:ok, pid} -> GenServer.stop(pid)
      {:error, _} -> :ok
    end
  end

  ## Private Resilience Implementation

  @spec try_with_fallback((-> any()), (-> :ok | {:error, map()} | {:ok, any()})) :: any()
  defp try_with_fallback(primary_fn, fallback_fn) do
    case primary_fn.() do
      {:error, :service_not_found} ->
        Logger.warning("ConfigServer unavailable, using fallback")
        fallback_fn.()

      result ->
        result
    end
  rescue
    error in ArgumentError ->
      # Handle registry not available (common in tests)
      Logger.warning(
        "ConfigServer registry unavailable: #{Exception.message(error)}, using fallback"
      )

      fallback_fn.()

    error ->
      Logger.warning("ConfigServer error: #{Exception.message(error)}, using fallback")
      fallback_fn.()
  catch
    :exit, reason ->
      Logger.warning("ConfigServer process issue: #{inspect(reason)}, using fallback")
      fallback_fn.()
  end

  @spec initialize_fallback_cache() :: :ok
  defp initialize_fallback_cache do
    case :ets.whereis(@fallback_table) do
      :undefined ->
        :ets.new(@fallback_table, [:named_table, :public, :set, {:read_concurrency, true}])
        Logger.debug("Fallback cache initialized")
        :ok

      _table ->
        Logger.debug("Fallback cache already initialized")
        :ok
    end
  end

  @spec cleanup_fallback_cache() :: :ok
  defp cleanup_fallback_cache do
    case :ets.info(@fallback_table) do
      :undefined ->
        :ok

      _ ->
        :ets.delete(@fallback_table)
        :ok
    end
  rescue
    ArgumentError ->
      # Table doesn't exist or already deleted
      :ok
  end

  @spec get_from_cache([atom()]) :: {:ok, term()} | {:error, Error.t()}
  defp get_from_cache(path) do
    cache_key = {:config_cache, path}
    current_time = System.system_time(:second)

    case :ets.lookup(@fallback_table, cache_key) do
      [{^cache_key, value, timestamp}] ->
        if current_time - timestamp <= @cache_ttl do
          Logger.debug("Using cached config value for path: #{inspect(path)}")
          {:ok, value}
        else
          # Cache expired
          :ets.delete(@fallback_table, cache_key)
          Logger.warning("Cache expired for path: #{inspect(path)}")

          {:error,
           Error.new(
             error_type: :config_unavailable,
             message: "Configuration cache expired",
             context: %{path: path},
             category: :config,
             subcategory: :access,
             severity: :medium
           )}
        end

      [] ->
        Logger.warning("No cached value available for path: #{inspect(path)}")

        {:error,
         Error.new(
           error_type: :config_unavailable,
           message: "Configuration not available",
           context: %{path: path},
           category: :config,
           subcategory: :access,
           severity: :medium
         )}
    end
  catch
    :error, :badarg ->
      initialize_fallback_cache()
      get_from_cache(path)
  end

  @spec cache_successful_read([atom()], term()) :: :ok
  defp cache_successful_read(path, value) do
    cache_key = {:config_cache, path}
    timestamp = System.system_time(:second)
    :ets.insert(@fallback_table, {cache_key, value, timestamp})
    :ok
  catch
    :error, :badarg ->
      initialize_fallback_cache()
      cache_successful_read(path, value)
  end

  @spec cache_pending_update([atom()], term()) :: {:error, Error.t()}
  defp cache_pending_update(path, value) do
    timestamp = System.system_time(:second)
    pending_key = {:pending_update, path}

    try do
      :ets.insert(@fallback_table, {pending_key, value, timestamp})
    catch
      :error, :badarg ->
        initialize_fallback_cache()
        :ets.insert(@fallback_table, {pending_key, value, timestamp})
    end

    Logger.warning("Config update failed, cached as pending: #{inspect(path)} -> #{inspect(value)}")

    {:error, create_service_unavailable_error("update/2")}
  end

  @spec clear_pending_update([atom()]) :: :ok
  defp clear_pending_update(path) do
    pending_key = {:pending_update, path}
    :ets.delete(@fallback_table, pending_key)
    :ok
  catch
    :error, :badarg ->
      :ok
  end

  @spec create_service_unavailable_error(String.t()) :: Error.t()
  defp create_service_unavailable_error(operation) do
    Error.new(
      code: 5000,
      error_type: :service_unavailable,
      message: "Configuration service unavailable for #{operation}",
      severity: :high,
      category: :system,
      subcategory: :initialization
    )
  end
end
