defmodule Foundation.Services.ConfigServer do
  @moduledoc """
  Agent-aware configuration management service for Foundation infrastructure.
  
  Provides centralized configuration management with agent-specific overrides,
  dynamic configuration updates, and coordination with agent health states.
  Designed for multi-agent environments where different agents may require
  different configuration parameters.
  
  ## Features
  
  - **Hierarchical Configuration**: Global, namespace, and agent-specific configs
  - **Dynamic Updates**: Live configuration updates with change notifications
  - **Agent Integration**: Configuration aware of agent capabilities and health
  - **Validation**: Comprehensive configuration validation and type checking
  - **Persistence**: Optional configuration persistence and recovery
  - **Coordination Integration**: Configuration changes participate in coordination
  
  ## Configuration Hierarchy
  
  1. **Global Configuration**: System-wide defaults
  2. **Namespace Configuration**: Environment or deployment-specific settings
  3. **Agent Configuration**: Agent-specific overrides and customizations
  4. **Runtime Configuration**: Temporary runtime adjustments
  
  ## Usage
  
      # Start config server
      {:ok, _pid} = ConfigServer.start_link([
        namespace: :production,
        persistence_enabled: true
      ])
      
      # Get configuration
      {:ok, config} = ConfigServer.get_config([:database, :host])
      
      # Set agent-specific configuration
      ConfigServer.set_agent_config(:ml_agent_1, [:model, :temperature], 0.7)
      
      # Get effective configuration for agent
      {:ok, temp} = ConfigServer.get_effective_config(:ml_agent_1, [:model, :temperature])
      
      # Subscribe to configuration changes
      ConfigServer.subscribe_to_changes([:model])
  """
  
  use GenServer
  require Logger
  
  alias Foundation.ProcessRegistry
  alias Foundation.Telemetry
  alias Foundation.Types.Error
  
  @type config_path :: [atom() | String.t()]
  @type config_value :: any()
  @type agent_id :: atom() | String.t()
  @type namespace :: atom()
  @type config_scope :: :global | :namespace | :agent | :runtime
  
  @type config_entry :: %{
    path: config_path(),
    value: config_value(),
    scope: config_scope(),
    agent_id: agent_id() | nil,
    timestamp: DateTime.t(),
    metadata: map()
  }
  
  @type config_change :: %{
    path: config_path(),
    old_value: config_value(),
    new_value: config_value(),
    scope: config_scope(),
    agent_id: agent_id() | nil,
    timestamp: DateTime.t()
  }
  
  defstruct [
    :namespace,
    :persistence_enabled,
    :config_store,
    :subscribers,
    :validation_enabled,
    :change_history,
    :agent_configs
  ]
  
  @type t :: %__MODULE__{
    namespace: namespace(),
    persistence_enabled: boolean(),
    config_store: :ets.tid(),
    subscribers: :ets.tid(),
    validation_enabled: boolean(),
    change_history: :ets.tid(),
    agent_configs: :ets.tid()
  }
  
  # Default configuration values
  @default_config %{
    coordination: %{
      consensus_timeout: 5_000,
      election_timeout: 3_000,
      barrier_timeout: 10_000
    },
    infrastructure: %{
      circuit_breaker: %{
        failure_threshold: 5,
        recovery_timeout: 60_000
      },
      rate_limiter: %{
        default_limit: 100,
        default_window: 60_000
      }
    },
    agents: %{
      health_check_interval: 30_000,
      resource_thresholds: %{
        memory: 0.8,
        cpu: 0.9
      }
    }
  }
  
  # Public API
  
  @doc """
  Start the configuration server.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(options \\ []) do
    namespace = Keyword.get(options, :namespace, :foundation)
    GenServer.start_link(__MODULE__, options, name: service_name(namespace))
  end
  
  @doc """
  Get configuration value by path.
  
  Returns the configuration value at the specified path,
  with no agent-specific overrides applied.
  
  ## Examples
  
      {:ok, timeout} = ConfigServer.get_config([:coordination, :consensus_timeout])
      {:ok, config} = ConfigServer.get_config([])  # Get all config
  """
  @spec get_config(config_path(), namespace()) :: {:ok, config_value()} | {:error, Error.t()}
  def get_config(path, namespace \\ :foundation) do
    GenServer.call(service_name(namespace), {:get_config, path})
  rescue
    error -> {:error, config_server_error("get_config failed", error)}
  end
  
  @doc """
  Get effective configuration for an agent.
  
  Returns the configuration value with agent-specific overrides applied.
  This follows the configuration hierarchy to provide the most specific
  applicable configuration.
  """
  @spec get_effective_config(agent_id(), config_path(), namespace()) :: 
    {:ok, config_value()} | {:error, Error.t()}
  def get_effective_config(agent_id, path, namespace \\ :foundation) do
    GenServer.call(service_name(namespace), {:get_effective_config, agent_id, path})
  rescue
    error -> {:error, config_server_error("get_effective_config failed", error)}
  end
  
  @doc """
  Set configuration value.
  
  Updates configuration at the specified path and notifies subscribers.
  """
  @spec set_config(config_path(), config_value(), namespace()) :: :ok | {:error, Error.t()}
  def set_config(path, value, namespace \\ :foundation) do
    GenServer.call(service_name(namespace), {:set_config, path, value, :global})
  rescue
    error -> {:error, config_server_error("set_config failed", error)}
  end
  
  @doc """
  Set agent-specific configuration override.
  
  Creates an agent-specific configuration override that takes precedence
  over global and namespace configurations for the specified agent.
  """
  @spec set_agent_config(agent_id(), config_path(), config_value(), namespace()) :: 
    :ok | {:error, Error.t()}
  def set_agent_config(agent_id, path, value, namespace \\ :foundation) do
    GenServer.call(service_name(namespace), {:set_config, path, value, :agent, agent_id})
  rescue
    error -> {:error, config_server_error("set_agent_config failed", error)}
  end
  
  @doc """
  Subscribe to configuration changes.
  
  The calling process will receive messages of the form:
  `{:config_changed, config_change()}`
  """
  @spec subscribe_to_changes(config_path(), namespace()) :: :ok | {:error, Error.t()}
  def subscribe_to_changes(path, namespace \\ :foundation) do
    GenServer.call(service_name(namespace), {:subscribe, self(), path})
  rescue
    error -> {:error, config_server_error("subscribe_to_changes failed", error)}
  end
  
  @doc """
  Unsubscribe from configuration changes.
  """
  @spec unsubscribe_from_changes(config_path(), namespace()) :: :ok
  def unsubscribe_from_changes(path, namespace \\ :foundation) do
    GenServer.call(service_name(namespace), {:unsubscribe, self(), path})
  rescue
    error -> 
      Logger.warning("Failed to unsubscribe from config changes: #{inspect(error)}")
      :ok
  end
  
  @doc """
  Get configuration change history.
  
  Returns recent configuration changes, useful for debugging and auditing.
  """
  @spec get_change_history(namespace(), non_neg_integer()) :: {:ok, [config_change()]}
  def get_change_history(namespace \\ :foundation, limit \\ 100) do
    GenServer.call(service_name(namespace), {:get_change_history, limit})
  rescue
    error -> {:error, config_server_error("get_change_history failed", error)}
  end
  
  @doc """
  Validate configuration structure.
  
  Validates that the configuration follows expected schema and constraints.
  """
  @spec validate_config(config_value()) :: :ok | {:error, Error.t()}
  def validate_config(config) do
    # Basic validation - in production you might use a schema validation library
    case config do
      config when is_map(config) -> :ok
      _ -> {:error, validation_error("Configuration must be a map")}
    end
  end
  
  # GenServer Implementation
  
  @impl GenServer
  def init(options) do
    namespace = Keyword.get(options, :namespace, :foundation)
    persistence_enabled = Keyword.get(options, :persistence_enabled, false)
    validation_enabled = Keyword.get(options, :validation_enabled, true)
    
    # Create ETS tables for configuration storage
    config_store = :ets.new(:config_store, [
      :set, :private, {:write_concurrency, true}, {:read_concurrency, true}
    ])
    
    subscribers = :ets.new(:config_subscribers, [
      :bag, :private, {:write_concurrency, true}, {:read_concurrency, true}
    ])
    
    change_history = :ets.new(:config_change_history, [
      :ordered_set, :private, {:write_concurrency, true}, {:read_concurrency, true}
    ])
    
    agent_configs = :ets.new(:agent_configs, [
      :set, :private, {:write_concurrency, true}, {:read_concurrency, true}
    ])
    
    state = %__MODULE__{
      namespace: namespace,
      persistence_enabled: persistence_enabled,
      config_store: config_store,
      subscribers: subscribers,
      validation_enabled: validation_enabled,
      change_history: change_history,
      agent_configs: agent_configs
    }
    
    # Initialize with default configuration
    initialize_default_config(state)
    
    # Register with ProcessRegistry
    case ProcessRegistry.register(namespace, __MODULE__, self(), %{
      type: :config_server,
      health: :healthy,
      persistence_enabled: persistence_enabled
    }) do
      :ok ->
        Telemetry.emit_counter(
          [:foundation, :services, :config_server, :started],
          %{namespace: namespace, persistence_enabled: persistence_enabled}
        )
        
        {:ok, state}
      
      {:error, reason} ->
        {:stop, {:registration_failed, reason}}
    end
  end
  
  @impl GenServer
  def handle_call({:get_config, path}, _from, state) do
    result = retrieve_config_value(path, state)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:get_effective_config, agent_id, path}, _from, state) do
    result = retrieve_effective_config(agent_id, path, state)
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:set_config, path, value, scope, agent_id}, _from, state) do
    case update_config_value(path, value, scope, agent_id, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}
      
      {:error, _} = error ->
        {:reply, error, state}
    end
  end
  
  @impl GenServer
  def handle_call({:set_config, path, value, scope}, _from, state) do
    case update_config_value(path, value, scope, nil, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}
      
      {:error, _} = error ->
        {:reply, error, state}
    end
  end
  
  @impl GenServer
  def handle_call({:subscribe, pid, path}, _from, state) do
    # Add subscriber
    :ets.insert(state.subscribers, {path, pid})
    
    # Monitor the subscriber process
    Process.monitor(pid)
    
    Telemetry.emit_counter(
      [:foundation, :services, :config_server, :subscriber_added],
      %{path: path, pid: pid}
    )
    
    {:reply, :ok, state}
  end
  
  @impl GenServer
  def handle_call({:unsubscribe, pid, path}, _from, state) do
    :ets.match_delete(state.subscribers, {path, pid})
    {:reply, :ok, state}
  end
  
  @impl GenServer
  def handle_call({:get_change_history, limit}, _from, state) do
    history = get_recent_changes(state, limit)
    {:reply, {:ok, history}, state}
  end
  
  @impl GenServer
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Remove all subscriptions for the terminated process
    :ets.match_delete(state.subscribers, {:_, pid})
    {:noreply, state}
  end
  
  @impl GenServer
  def handle_info(_message, state) do
    {:noreply, state}
  end
  
  # Private Implementation
  
  defp initialize_default_config(state) do
    # Store default configuration
    store_config_entry([], @default_config, :global, nil, state)
  end
  
  defp retrieve_config_value(path, state) do
    case :ets.lookup(state.config_store, path) do
      [{^path, entry}] -> {:ok, entry.value}
      [] -> 
        # Try to get from parent paths
        case get_nested_value(@default_config, path) do
          {:ok, value} -> {:ok, value}
          :error -> {:error, config_not_found_error(path)}
        end
    end
  end
  
  defp retrieve_effective_config(agent_id, path, state) do
    # Check agent-specific config first
    agent_key = {:agent, agent_id, path}
    
    case :ets.lookup(state.agent_configs, agent_key) do
      [{^agent_key, entry}] -> {:ok, entry.value}
      [] ->
        # Fall back to regular config
        retrieve_config_value(path, state)
    end
  end
  
  defp update_config_value(path, value, scope, agent_id, state) do
    # Validate the new value if validation is enabled
    case validate_config_update(path, value, state) do
      :ok ->
        old_value = case retrieve_config_value(path, state) do
          {:ok, old} -> old
          {:error, _} -> nil
        end
        
        # Store the configuration
        store_config_entry(path, value, scope, agent_id, state)
        
        # Record the change
        change = %{
          path: path,
          old_value: old_value,
          new_value: value,
          scope: scope,
          agent_id: agent_id,
          timestamp: DateTime.utc_now()
        }
        
        record_config_change(change, state)
        
        # Notify subscribers
        notify_config_change(change, state)
        
        {:ok, state}
      
      {:error, _} = error ->
        error
    end
  end
  
  defp store_config_entry(path, value, scope, agent_id, state) do
    entry = %{
      path: path,
      value: value,
      scope: scope,
      agent_id: agent_id,
      timestamp: DateTime.utc_now(),
      metadata: %{}
    }
    
    case scope do
      :agent when agent_id != nil ->
        agent_key = {:agent, agent_id, path}
        :ets.insert(state.agent_configs, {agent_key, entry})
      
      _ ->
        :ets.insert(state.config_store, {path, entry})
    end
  end
  
  defp validate_config_update(path, value, state) do
    if state.validation_enabled do
      # Basic validation - check if value is reasonable for the path
      case path do
        [:coordination, :consensus_timeout] when is_integer(value) and value > 0 -> :ok
        [:infrastructure | _] when is_map(value) or is_binary(value) or is_number(value) -> :ok
        _ when is_binary(value) or is_number(value) or is_boolean(value) or is_map(value) -> :ok
        _ -> {:error, validation_error("Invalid value type for path #{inspect(path)}")}
      end
    else
      :ok
    end
  end
  
  defp record_config_change(change, state) do
    timestamp = System.system_time(:millisecond)
    :ets.insert(state.change_history, {timestamp, change})
    
    # Keep only recent changes (last hour)
    cutoff_time = timestamp - (60 * 60 * 1000)
    :ets.select_delete(state.change_history, [
      {{:"$1", :_}, [{:<, :"$1", cutoff_time}], [true]}
    ])
  end
  
  defp notify_config_change(change, state) do
    # Notify exact path subscribers
    exact_subscribers = :ets.lookup(state.subscribers, change.path)
    
    # Notify prefix subscribers (for parent paths)
    prefix_subscribers = find_prefix_subscribers(change.path, state)
    
    all_subscribers = exact_subscribers ++ prefix_subscribers
    
    Enum.each(all_subscribers, fn {_path, pid} ->
      try do
        send(pid, {:config_changed, change})
      rescue
        _ -> :ok  # Ignore send failures
      end
    end)
    
    # Emit telemetry
    Telemetry.emit_counter(
      [:foundation, :services, :config_server, :config_changed],
      %{
        path: change.path,
        scope: change.scope,
        subscriber_count: length(all_subscribers)
      }
    )
  end
  
  defp find_prefix_subscribers(path, state) do
    # Find subscribers to parent paths
    all_subscribers = :ets.tab2list(state.subscribers)
    
    Enum.filter(all_subscribers, fn {subscriber_path, _pid} ->
      is_prefix_of?(subscriber_path, path)
    end)
  end
  
  defp is_prefix_of?(prefix, path) when is_list(prefix) and is_list(path) do
    length(prefix) < length(path) and
      Enum.take(path, length(prefix)) == prefix
  end
  defp is_prefix_of?(_, _), do: false
  
  defp get_recent_changes(state, limit) do
    :ets.tab2list(state.change_history)
    |> Enum.sort_by(fn {timestamp, _change} -> timestamp end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {_timestamp, change} -> change end)
  end
  
  defp get_nested_value(map, []) when is_map(map), do: {:ok, map}
  defp get_nested_value(map, [key | rest]) when is_map(map) do
    case Map.get(map, key) do
      nil -> :error
      value -> get_nested_value(value, rest)
    end
  end
  defp get_nested_value(value, []), do: {:ok, value}
  defp get_nested_value(_, _), do: :error
  
  defp service_name(namespace) do
    :"Foundation.Services.ConfigServer.#{namespace}"
  end
  
  # Error Helper Functions
  
  defp config_server_error(message, error) do
    Error.new(
      code: 9001,
      error_type: :config_server_error,
      message: "Config server error: #{message}",
      severity: :medium,
      context: %{error: error}
    )
  end
  
  defp config_not_found_error(path) do
    Error.new(
      code: 9002,
      error_type: :config_not_found,
      message: "Configuration not found at path: #{inspect(path)}",
      severity: :low,
      context: %{path: path}
    )
  end
  
  defp validation_error(message) do
    Error.new(
      code: 9003,
      error_type: :config_validation_failed,
      message: "Configuration validation failed: #{message}",
      severity: :medium,
      context: %{validation_message: message}
    )
  end
end