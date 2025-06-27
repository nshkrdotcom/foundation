# COUPLING_MITIGATION_ARCHITECTURE.md

## Executive Summary

After deep code analysis, Foundation and MABEAM exhibit **severe architectural coupling** through 6 primary mechanisms: direct service calls, shared ETS state, unified configuration, telemetry event namespacing, process supervision interdependencies, and runtime service discovery patterns. This document provides a comprehensive architecture for decoupling these systems while maintaining functionality and preparing for context-window-friendly development.

**Core Finding**: The coupling is far more extensive than initially apparent, requiring a **systematic architectural transformation** rather than simple refactoring.

## 1. Current Coupling Analysis Summary

### 1.1 Critical Coupling Vectors Identified

| Coupling Type | Severity | Impact | Current Pattern | Files Affected |
|---------------|----------|--------|-----------------|----------------|
| **Service Calls** | 🔴 CRITICAL | Runtime dependency | Direct `Foundation.ProcessRegistry` calls | 15+ MABEAM modules |
| **Shared ETS State** | 🔴 CRITICAL | Data consistency | `:process_registry_backup` table | ProcessRegistry, MABEAM services |
| **Configuration** | 🟡 HIGH | Deployment coupling | MABEAM config under `:foundation` app | config.exs, migration.ex |
| **Telemetry Events** | 🟡 HIGH | Monitoring coupling | `[:foundation, :mabeam, ...]` events | All MABEAM telemetry |
| **Process Supervision** | 🟠 MEDIUM | Lifecycle coupling | Historical supervision in Foundation | application.ex |
| **Error Propagation** | 🟠 MEDIUM | Failure coupling | Graceful degradation patterns | Agent services |

### 1.2 Specific Code Coupling Examples

#### Direct Service Call Coupling
```elixir
# lib/mabeam/agent_registry.ex:143
case Foundation.ProcessRegistry.register(:production, {:mabeam, :agent_registry}, self(), %{
  service: :agent_registry,
  type: :mabeam_service
}) do
  :ok -> Logger.info("AgentRegistry registered successfully")
  {:error, reason} -> Logger.error("Failed to register: #{inspect(reason)}")
end
```

#### Telemetry Event Coupling  
```elixir
# lib/mabeam/telemetry.ex:632-641
@agent_events [
  [:foundation, :mabeam, :agent, :registered],    # Foundation namespace!
  [:foundation, :mabeam, :agent, :started],
  [:foundation, :mabeam, :coordination, :started]
]
```

#### Configuration Coupling
```elixir
# config/config.exs:75-92
config :foundation,
  mabeam: [                                      # MABEAM config under Foundation!
    use_unified_registry: true,
    legacy_registry: [...],
    migration: [...]
  ]
```

#### Shared ETS State Coupling
```elixir
# lib/foundation/process_registry.ex:182
:ets.insert(:process_registry_backup, {registry_key, pid, metadata})
# This ETS table is accessed by MABEAM services for process discovery
```

## 2. Coupling Mitigation Architecture

### 2.1 Overview: Four-Layer Decoupling Strategy

```
┌─────────────────────────────────────────────────────────────────┐
│                    MABEAM APPLICATION                           │
├─────────────────────────────────────────────────────────────────┤
│                    INTEGRATION LAYER                           │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │ Service Adapter │  │ Event Translator│  │ Config Bridge   │ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│                   COUPLING CONTROL LAYER                       │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐ │
│  │ Coupling Budget │  │ Contract Monitor│  │ Circuit Breakers│ │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘ │
├─────────────────────────────────────────────────────────────────┤
│                    FOUNDATION LAYER                            │
└─────────────────────────────────────────────────────────────────┘
```

### 2.2 Integration Layer Components

#### 2.2.1 Service Adapter Pattern

```elixir
defmodule MABEAM.Foundation.ServiceAdapter do
  @moduledoc """
  Central adapter that encapsulates ALL Foundation service interactions.
  
  This is the ONLY module that should directly call Foundation services.
  All other MABEAM modules must go through this adapter.
  """

  use GenServer
  require Logger

  # Adapter behaviour for service interactions
  @behaviour MABEAM.Foundation.ServiceBehaviour

  # ============================================================================
  # Public API - All Foundation interactions go through here
  # ============================================================================

  @doc """
  Register a process in the Foundation service registry.
  
  This encapsulates the Foundation.ProcessRegistry.register call and provides
  MABEAM-specific error handling and retry logic.
  """
  @spec register_process(service_spec()) :: :ok | {:error, term()}
  def register_process(service_spec) do
    GenServer.call(__MODULE__, {:register_process, service_spec})
  end

  @doc """
  Lookup a process in the Foundation service registry.
  
  Provides caching and fallback mechanisms for service discovery.
  """
  @spec lookup_process(service_key()) :: {:ok, pid()} | {:error, :not_found}
  def lookup_process(service_key) do
    GenServer.call(__MODULE__, {:lookup_process, service_key})
  end

  @doc """
  Emit telemetry through Foundation infrastructure.
  
  Translates MABEAM events to Foundation telemetry format.
  """
  @spec emit_telemetry(event_name(), measurements(), metadata()) :: :ok
  def emit_telemetry(event_name, measurements, metadata) do
    GenServer.cast(__MODULE__, {:emit_telemetry, event_name, measurements, metadata})
  end

  # ============================================================================
  # GenServer Implementation
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    # Initialize adapter state with caching and circuit breaker
    state = %{
      service_cache: %{},
      circuit_breaker: init_circuit_breaker(),
      foundation_available: check_foundation_availability(),
      coupling_budget: init_coupling_budget(opts),
      call_count: 0,
      start_time: DateTime.utc_now()
    }

    # Schedule periodic health checks
    schedule_foundation_health_check()

    {:ok, state}
  end

  # ============================================================================
  # Foundation Service Interactions (Private)
  # ============================================================================

  def handle_call({:register_process, service_spec}, _from, state) do
    # Record coupling interaction
    new_state = record_coupling_interaction(state, :register_process)

    case check_coupling_budget(new_state, :register_process) do
      :ok ->
        result = perform_foundation_register(service_spec, new_state)
        {:reply, result, new_state}

      {:error, :budget_exceeded} ->
        Logger.warning("Coupling budget exceeded for register_process")
        {:reply, {:error, :coupling_budget_exceeded}, new_state}
    end
  end

  def handle_call({:lookup_process, service_key}, _from, state) do
    # Check cache first to reduce Foundation calls
    case get_cached_service(service_key, state) do
      {:ok, pid} ->
        {:reply, {:ok, pid}, state}

      :cache_miss ->
        new_state = record_coupling_interaction(state, :lookup_process)
        result = perform_foundation_lookup(service_key, new_state)
        updated_state = update_service_cache(service_key, result, new_state)
        {:reply, result, updated_state}
    end
  end

  def handle_cast({:emit_telemetry, event_name, measurements, metadata}, state) do
    # Translate MABEAM events to Foundation format
    translated_event = translate_telemetry_event(event_name, measurements, metadata)

    case state.foundation_available do
      true ->
        perform_foundation_telemetry(translated_event)
      false ->
        # Buffer events when Foundation unavailable
        buffer_telemetry_event(translated_event)
    end

    {:noreply, state}
  end

  # ============================================================================
  # Foundation Interaction Implementation
  # ============================================================================

  defp perform_foundation_register(service_spec, state) do
    case state.circuit_breaker.state do
      :open ->
        {:error, :foundation_circuit_breaker_open}

      _ ->
        try do
          # Translate MABEAM service spec to Foundation format
          foundation_spec = translate_service_spec(service_spec)

          case Foundation.ProcessRegistry.register(
                 foundation_spec.namespace,
                 foundation_spec.service_name,
                 foundation_spec.pid,
                 foundation_spec.metadata
               ) do
            :ok ->
              record_foundation_success()
              :ok

            {:error, reason} ->
              record_foundation_error(reason)
              {:error, {:foundation_register_failed, reason}}
          end
        rescue
          error ->
            record_foundation_exception(error)
            {:error, {:foundation_register_exception, error}}
        end
    end
  end

  defp perform_foundation_lookup(service_key, state) do
    case state.circuit_breaker.state do
      :open ->
        {:error, :foundation_circuit_breaker_open}

      _ ->
        try do
          foundation_key = translate_service_key(service_key)

          case Foundation.ProcessRegistry.lookup(foundation_key.namespace, foundation_key.service) do
            {:ok, pid} ->
              record_foundation_success()
              {:ok, pid}

            :error ->
              {:error, :not_found}
          end
        rescue
          error ->
            record_foundation_exception(error)
            {:error, {:foundation_lookup_exception, error}}
        end
    end
  end

  # ============================================================================
  # Translation Layer
  # ============================================================================

  defp translate_service_spec(%{id: id, pid: pid, type: type, metadata: metadata}) do
    %{
      namespace: :production,
      service_name: {:mabeam, id},
      pid: pid,
      metadata: Map.merge(metadata, %{
        mabeam_type: type,
        adapter_version: "1.0.0",
        registered_via: :mabeam_adapter
      })
    }
  end

  defp translate_service_key(service_key) when is_atom(service_key) do
    %{namespace: :production, service: {:mabeam, service_key}}
  end

  defp translate_service_key({:mabeam, service_key}) do
    %{namespace: :production, service: {:mabeam, service_key}}
  end

  defp translate_telemetry_event(event_name, measurements, metadata) do
    # Transform MABEAM event namespace to proper format
    foundation_event_name = [:mabeam, :adapter] ++ event_name

    enhanced_metadata = Map.merge(metadata, %{
      source_application: :mabeam,
      adapter_version: "1.0.0",
      translated_at: DateTime.utc_now()
    })

    {foundation_event_name, measurements, enhanced_metadata}
  end

  # ============================================================================
  # Coupling Budget Management
  # ============================================================================

  defp init_coupling_budget(opts) do
    %{
      max_calls_per_minute: Keyword.get(opts, :max_calls_per_minute, 1000),
      max_register_calls_per_minute: Keyword.get(opts, :max_register_calls_per_minute, 100),
      max_lookup_calls_per_minute: Keyword.get(opts, :max_lookup_calls_per_minute, 500),
      current_window_start: DateTime.utc_now(),
      current_calls: %{
        register_process: 0,
        lookup_process: 0,
        emit_telemetry: 0
      }
    }
  end

  defp check_coupling_budget(state, operation) do
    budget = state.coupling_budget
    current_time = DateTime.utc_now()

    # Reset budget if new minute
    budget = reset_budget_if_needed(budget, current_time)

    current_calls = Map.get(budget.current_calls, operation, 0)
    max_calls = get_operation_limit(budget, operation)

    if current_calls >= max_calls do
      {:error, :budget_exceeded}
    else
      :ok
    end
  end

  defp record_coupling_interaction(state, operation) do
    budget = state.coupling_budget
    current_calls = Map.update(budget.current_calls, operation, 1, &(&1 + 1))
    updated_budget = %{budget | current_calls: current_calls}

    # Emit coupling metrics
    :telemetry.execute(
      [:mabeam, :adapter, :coupling],
      %{operation_count: 1},
      %{operation: operation, total_calls: state.call_count + 1}
    )

    %{state | coupling_budget: updated_budget, call_count: state.call_count + 1}
  end

  # ============================================================================
  # Circuit Breaker Implementation
  # ============================================================================

  defp init_circuit_breaker do
    %{
      state: :closed,
      failure_count: 0,
      failure_threshold: 5,
      recovery_timeout: 30_000,
      last_failure_time: nil
    }
  end

  defp record_foundation_success do
    # Reset circuit breaker on success
    GenServer.cast(__MODULE__, :reset_circuit_breaker)
  end

  defp record_foundation_error(reason) do
    Logger.warning("Foundation service error", reason: reason)
    GenServer.cast(__MODULE__, :record_foundation_failure)
  end

  defp record_foundation_exception(error) do
    Logger.error("Foundation service exception", error: error)
    GenServer.cast(__MODULE__, :record_foundation_failure)
  end

  def handle_cast(:reset_circuit_breaker, state) do
    circuit_breaker = %{state.circuit_breaker | state: :closed, failure_count: 0}
    {:noreply, %{state | circuit_breaker: circuit_breaker}}
  end

  def handle_cast(:record_foundation_failure, state) do
    circuit_breaker = state.circuit_breaker
    new_failure_count = circuit_breaker.failure_count + 1

    new_circuit_breaker =
      if new_failure_count >= circuit_breaker.failure_threshold do
        Logger.error("Foundation circuit breaker opened due to failures")
        %{circuit_breaker | state: :open, last_failure_time: DateTime.utc_now()}
      else
        %{circuit_breaker | failure_count: new_failure_count}
      end

    {:noreply, %{state | circuit_breaker: new_circuit_breaker}}
  end

  # ============================================================================
  # Service Discovery Caching
  # ============================================================================

  defp get_cached_service(service_key, state) do
    case Map.get(state.service_cache, service_key) do
      nil ->
        :cache_miss

      {pid, cached_at} ->
        # Check if cache entry is still valid
        if cache_entry_valid?(cached_at) and Process.alive?(pid) do
          {:ok, pid}
        else
          :cache_miss
        end
    end
  end

  defp update_service_cache(service_key, {:ok, pid}, state) do
    updated_cache = Map.put(state.service_cache, service_key, {pid, DateTime.utc_now()})
    %{state | service_cache: updated_cache}
  end

  defp update_service_cache(_service_key, {:error, _reason}, state) do
    # Don't cache errors
    state
  end

  defp cache_entry_valid?(cached_at) do
    cache_ttl_seconds = 300  # 5 minutes
    DateTime.diff(DateTime.utc_now(), cached_at) < cache_ttl_seconds
  end

  # ============================================================================
  # Foundation Health Monitoring
  # ============================================================================

  defp check_foundation_availability do
    try do
      case Process.whereis(Foundation.ProcessRegistry) do
        nil -> false
        pid when is_pid(pid) -> Process.alive?(pid)
      end
    rescue
      _ -> false
    end
  end

  defp schedule_foundation_health_check do
    Process.send_after(self(), :health_check, 30_000)
  end

  def handle_info(:health_check, state) do
    foundation_available = check_foundation_availability()

    if foundation_available != state.foundation_available do
      Logger.info("Foundation availability changed", available: foundation_available)

      # Emit availability change event
      :telemetry.execute(
        [:mabeam, :adapter, :foundation_availability],
        %{available: if(foundation_available, do: 1, else: 0)},
        %{previous_state: state.foundation_available}
      )
    end

    schedule_foundation_health_check()
    {:noreply, %{state | foundation_available: foundation_available}}
  end
end
```

#### 2.2.2 Event Translation Layer

```elixir
defmodule MABEAM.Foundation.EventTranslator do
  @moduledoc """
  Translates between MABEAM and Foundation event formats.
  
  This module eliminates event namespace coupling by providing clean translation
  between application-specific events and Foundation telemetry events.
  """

  # ============================================================================
  # Event Translation Mapping
  # ============================================================================

  @mabeam_to_foundation_events %{
    # Agent lifecycle events
    [:agent, :registered] => [:foundation, :process, :registered],
    [:agent, :started] => [:foundation, :process, :started],
    [:agent, :stopped] => [:foundation, :process, :stopped],
    [:agent, :failed] => [:foundation, :process, :failed],

    # Coordination events
    [:coordination, :started] => [:foundation, :coordination, :session_started],
    [:coordination, :completed] => [:foundation, :coordination, :session_completed],

    # Economics events
    [:economics, :auction_created] => [:foundation, :business_event, :auction_created],
    [:economics, :bid_placed] => [:foundation, :business_event, :bid_placed]
  }

  @foundation_to_mabeam_events %{
    # Infrastructure events that affect MABEAM
    [:foundation, :process_registry, :unavailable] => [:mabeam, :infrastructure, :registry_unavailable],
    [:foundation, :telemetry, :service_degraded] => [:mabeam, :infrastructure, :telemetry_degraded]
  }

  # ============================================================================
  # Translation Functions
  # ============================================================================

  @spec translate_mabeam_event(event_name(), measurements(), metadata()) ::
          {translated_event_name(), measurements(), metadata()}
  def translate_mabeam_event(event_name, measurements, metadata) do
    foundation_event_name = Map.get(@mabeam_to_foundation_events, event_name, event_name)

    enhanced_metadata = Map.merge(metadata, %{
      source_application: :mabeam,
      original_event: event_name,
      translated_at: DateTime.utc_now(),
      translation_version: "1.0.0"
    })

    {foundation_event_name, measurements, enhanced_metadata}
  end

  @spec translate_foundation_event(event_name(), measurements(), metadata()) ::
          {translated_event_name(), measurements(), metadata()} | :ignore
  def translate_foundation_event(event_name, measurements, metadata) do
    case Map.get(@foundation_to_mabeam_events, event_name) do
      nil ->
        :ignore

      mabeam_event_name ->
        enhanced_metadata = Map.merge(metadata, %{
          source_application: :foundation,
          original_event: event_name,
          translated_at: DateTime.utc_now()
        })

        {mabeam_event_name, measurements, enhanced_metadata}
    end
  end

  # ============================================================================
  # Event Subscription Management
  # ============================================================================

  @spec subscribe_to_foundation_events(pid()) :: :ok
  def subscribe_to_foundation_events(subscriber_pid) do
    foundation_events = Map.keys(@foundation_to_mabeam_events)

    Enum.each(foundation_events, fn event_pattern ->
      :telemetry.attach(
        {:mabeam_translator, event_pattern, subscriber_pid},
        event_pattern,
        &handle_foundation_event/4,
        %{subscriber: subscriber_pid}
      )
    end)

    :ok
  end

  defp handle_foundation_event(event_name, measurements, metadata, %{subscriber: subscriber_pid}) do
    case translate_foundation_event(event_name, measurements, metadata) do
      :ignore ->
        :ok

      {translated_event, translated_measurements, translated_metadata} ->
        send(subscriber_pid, {:translated_event, translated_event, translated_measurements, translated_metadata})
    end
  end
end
```

#### 2.2.3 Configuration Bridge

```elixir
defmodule MABEAM.Foundation.ConfigBridge do
  @moduledoc """
  Configuration bridge that manages the transition from unified to separated configuration.
  
  This module provides a clean migration path from the current unified configuration
  to separate application configurations while maintaining backward compatibility.
  """

  use GenServer
  require Logger

  # ============================================================================
  # Configuration Bridge State
  # ============================================================================

  defstruct [
    :migration_mode,
    :foundation_config,
    :mabeam_config,
    :compatibility_warnings_enabled,
    :migration_progress
  ]

  # ============================================================================
  # Public API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Get MABEAM configuration with automatic migration from legacy locations.
  """
  @spec get_mabeam_config(config_key()) :: {:ok, term()} | {:error, :not_found}
  def get_mabeam_config(config_key) do
    GenServer.call(__MODULE__, {:get_mabeam_config, config_key})
  end

  @doc """
  Set MABEAM configuration with automatic migration to new locations.
  """
  @spec set_mabeam_config(config_key(), term()) :: :ok | {:error, term()}
  def set_mabeam_config(config_key, value) do
    GenServer.call(__MODULE__, {:set_mabeam_config, config_key, value})
  end

  @doc """
  Check if the configuration migration is complete.
  """
  @spec migration_complete?() :: boolean()
  def migration_complete? do
    GenServer.call(__MODULE__, :migration_complete)
  end

  @doc """
  Force migration of all MABEAM configuration from Foundation to MABEAM app.
  """
  @spec migrate_configuration() :: {:ok, migration_result()} | {:error, term()}
  def migrate_configuration do
    GenServer.call(__MODULE__, :migrate_configuration)
  end

  # ============================================================================
  # GenServer Implementation
  # ============================================================================

  def init(opts) do
    migration_mode = Keyword.get(opts, :migration_mode, :gradual)
    compatibility_warnings = Keyword.get(opts, :compatibility_warnings, true)

    state = %__MODULE__{
      migration_mode: migration_mode,
      foundation_config: load_foundation_config(),
      mabeam_config: load_mabeam_config(),
      compatibility_warnings_enabled: compatibility_warnings,
      migration_progress: assess_migration_progress()
    }

    {:ok, state}
  end

  def handle_call({:get_mabeam_config, config_key}, _from, state) do
    result = resolve_mabeam_config(config_key, state)
    {:reply, result, state}
  end

  def handle_call({:set_mabeam_config, config_key, value}, _from, state) do
    case apply_mabeam_config_change(config_key, value, state) do
      {:ok, new_state} ->
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:migration_complete, _from, state) do
    complete = is_migration_complete(state)
    {:reply, complete, state}
  end

  def handle_call(:migrate_configuration, _from, state) do
    case perform_configuration_migration(state) do
      {:ok, migration_result, new_state} ->
        {:reply, {:ok, migration_result}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  # ============================================================================
  # Configuration Resolution
  # ============================================================================

  defp resolve_mabeam_config(config_key, state) do
    # Priority order: MABEAM app config -> Foundation app config (legacy) -> default
    case get_from_mabeam_app(config_key) do
      {:ok, value} ->
        {:ok, value}

      :not_found ->
        case get_from_foundation_app_legacy(config_key, state) do
          {:ok, value} ->
            maybe_emit_compatibility_warning(config_key, state)
            {:ok, value}

          :not_found ->
            {:error, :not_found}
        end
    end
  end

  defp get_from_mabeam_app(config_key) do
    case Application.get_env(:mabeam, :config, []) do
      [] -> :not_found
      config when is_list(config) -> 
        case Keyword.get(config, config_key) do
          nil -> :not_found
          value -> {:ok, value}
        end
    end
  end

  defp get_from_foundation_app_legacy(config_key, _state) do
    case Application.get_env(:foundation, :mabeam, []) do
      [] -> :not_found
      config when is_list(config) ->
        case Keyword.get(config, config_key) do
          nil -> :not_found
          value -> {:ok, value}
        end
    end
  end

  defp maybe_emit_compatibility_warning(config_key, state) do
    if state.compatibility_warnings_enabled do
      Logger.warning(
        "MABEAM configuration accessed from legacy Foundation location",
        config_key: config_key,
        recommendation: "Migrate to :mabeam application configuration"
      )

      # Emit telemetry for monitoring migration progress
      :telemetry.execute(
        [:mabeam, :config_bridge, :legacy_access],
        %{count: 1},
        %{config_key: config_key}
      )
    end
  end

  # ============================================================================
  # Configuration Migration
  # ============================================================================

  defp perform_configuration_migration(state) do
    try do
      # Get all MABEAM config from Foundation app
      foundation_mabeam_config = Application.get_env(:foundation, :mabeam, [])

      if Enum.empty?(foundation_mabeam_config) do
        {:ok, %{migrated_keys: [], already_migrated: true}, state}
      else
        # Migrate each configuration key
        migration_results = Enum.map(foundation_mabeam_config, fn {key, value} ->
          migrate_config_key(key, value)
        end)

        # Check for migration failures
        failures = Enum.filter(migration_results, &match?({:error, _}, &1))

        if Enum.empty?(failures) do
          # Clear Foundation MABEAM config after successful migration
          Application.delete_env(:foundation, :mabeam)

          migrated_keys = Enum.map(migration_results, fn {:ok, key} -> key end)
          
          new_state = %{state | migration_progress: assess_migration_progress()}

          Logger.info("MABEAM configuration migration completed", migrated_keys: migrated_keys)

          {:ok, %{migrated_keys: migrated_keys, failures: []}, new_state}
        else
          failure_keys = Enum.map(failures, fn {:error, {key, reason}} -> {key, reason} end)
          Logger.error("MABEAM configuration migration failed", failures: failure_keys)

          {:error, {:migration_failed, failure_keys}}
        end
      end
    rescue
      error ->
        Logger.error("Configuration migration exception", error: error)
        {:error, {:migration_exception, error}}
    end
  end

  defp migrate_config_key(key, value) do
    try do
      # Get current MABEAM config
      current_mabeam_config = Application.get_env(:mabeam, :config, [])

      # Add the migrated key
      updated_config = Keyword.put(current_mabeam_config, key, value)

      # Update MABEAM application config
      Application.put_env(:mabeam, :config, updated_config)

      {:ok, key}
    rescue
      error ->
        {:error, {key, error}}
    end
  end

  defp assess_migration_progress do
    foundation_mabeam_config = Application.get_env(:foundation, :mabeam, [])
    mabeam_config = Application.get_env(:mabeam, :config, [])

    %{
      has_legacy_config: not Enum.empty?(foundation_mabeam_config),
      has_new_config: not Enum.empty?(mabeam_config),
      legacy_keys: Keyword.keys(foundation_mabeam_config),
      new_keys: Keyword.keys(mabeam_config)
    }
  end

  defp is_migration_complete(state) do
    not state.migration_progress.has_legacy_config and state.migration_progress.has_new_config
  end
end
```

### 2.3 Coupling Control Layer

#### 2.3.1 Coupling Budget System

```elixir
defmodule MABEAM.Foundation.CouplingBudget do
  @moduledoc """
  Monitors and enforces coupling budgets between MABEAM and Foundation.
  
  This system prevents coupling from growing uncontrolled by:
  1. Tracking all cross-application interactions
  2. Enforcing configurable limits on coupling frequency
  3. Alerting when coupling budgets are exceeded
  4. Providing coupling metrics for architectural decisions
  """

  use GenServer
  require Logger

  # ============================================================================
  # Coupling Budget Configuration
  # ============================================================================

  @default_budget_config %{
    # Per-minute limits
    max_service_calls_per_minute: 1000,
    max_register_calls_per_minute: 100,
    max_lookup_calls_per_minute: 500,
    max_telemetry_events_per_minute: 2000,

    # Per-operation limits
    max_sequential_foundation_calls: 5,
    max_foundation_call_depth: 3,

    # Circuit breaker limits
    max_failures_before_circuit_break: 10,
    circuit_breaker_recovery_time: 30_000,

    # Alerting thresholds
    coupling_warning_threshold: 0.8,
    coupling_critical_threshold: 0.95
  }

  # ============================================================================
  # Budget State Management
  # ============================================================================

  defstruct [
    :config,
    :current_window,
    :usage_counts,
    :violation_history,
    :circuit_breakers,
    :alert_state
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    config = Keyword.get(opts, :budget_config, @default_budget_config)

    state = %__MODULE__{
      config: config,
      current_window: init_time_window(),
      usage_counts: init_usage_counts(),
      violation_history: [],
      circuit_breakers: %{},
      alert_state: %{}
    }

    # Schedule periodic budget reset and reporting
    schedule_budget_window_reset()
    schedule_coupling_report()

    {:ok, state}
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Record a coupling interaction and check budget compliance.
  """
  @spec record_interaction(interaction_type(), interaction_details()) :: 
    :ok | {:error, :budget_exceeded} | {:error, :circuit_breaker_open}
  def record_interaction(interaction_type, interaction_details) do
    GenServer.call(__MODULE__, {:record_interaction, interaction_type, interaction_details})
  end

  @doc """
  Get current coupling usage statistics.
  """
  @spec get_usage_statistics() :: coupling_statistics()
  def get_usage_statistics do
    GenServer.call(__MODULE__, :get_usage_statistics)
  end

  @doc """
  Check if a specific operation type is within budget.
  """
  @spec check_operation_budget(operation_type()) :: :ok | {:error, :budget_exceeded}
  def check_operation_budget(operation_type) do
    GenServer.call(__MODULE__, {:check_operation_budget, operation_type})
  end

  # ============================================================================
  # Budget Enforcement
  # ============================================================================

  def handle_call({:record_interaction, interaction_type, details}, _from, state) do
    # Reset window if needed
    state = maybe_reset_time_window(state)

    # Check circuit breaker
    case check_circuit_breaker(interaction_type, state) do
      :open ->
        {:reply, {:error, :circuit_breaker_open}, state}

      :closed ->
        # Record the interaction
        new_state = record_interaction_internal(interaction_type, details, state)

        # Check budget compliance
        case check_budget_compliance(interaction_type, new_state) do
          :ok ->
            {:reply, :ok, new_state}

          {:violation, severity} ->
            violation_state = handle_budget_violation(interaction_type, severity, new_state)
            {:reply, {:error, :budget_exceeded}, violation_state}
        end
    end
  end

  def handle_call(:get_usage_statistics, _from, state) do
    stats = compile_usage_statistics(state)
    {:reply, stats, state}
  end

  def handle_call({:check_operation_budget, operation_type}, _from, state) do
    result = check_operation_budget_internal(operation_type, state)
    {:reply, result, state}
  end

  # ============================================================================
  # Budget Compliance Checking
  # ============================================================================

  defp check_budget_compliance(interaction_type, state) do
    current_usage = get_current_usage(interaction_type, state)
    budget_limit = get_budget_limit(interaction_type, state.config)

    usage_ratio = current_usage / budget_limit

    cond do
      usage_ratio >= state.config.coupling_critical_threshold ->
        {:violation, :critical}

      usage_ratio >= state.config.coupling_warning_threshold ->
        {:violation, :warning}

      true ->
        :ok
    end
  end

  defp get_current_usage(interaction_type, state) do
    Map.get(state.usage_counts, interaction_type, 0)
  end

  defp get_budget_limit(:service_call, config), do: config.max_service_calls_per_minute
  defp get_budget_limit(:register_call, config), do: config.max_register_calls_per_minute
  defp get_budget_limit(:lookup_call, config), do: config.max_lookup_calls_per_minute
  defp get_budget_limit(:telemetry_event, config), do: config.max_telemetry_events_per_minute
  defp get_budget_limit(_, config), do: config.max_service_calls_per_minute

  # ============================================================================
  # Violation Handling
  # ============================================================================

  defp handle_budget_violation(interaction_type, severity, state) do
    violation = %{
      interaction_type: interaction_type,
      severity: severity,
      timestamp: DateTime.utc_now(),
      current_usage: get_current_usage(interaction_type, state),
      budget_limit: get_budget_limit(interaction_type, state.config)
    }

    # Log violation
    log_budget_violation(violation)

    # Record violation in history
    violation_history = [violation | state.violation_history] |> Enum.take(100)

    # Update circuit breaker if critical
    circuit_breakers =
      if severity == :critical do
        update_circuit_breaker(interaction_type, :failure, state.circuit_breakers)
      else
        state.circuit_breakers
      end

    # Emit telemetry
    emit_violation_telemetry(violation)

    %{state | violation_history: violation_history, circuit_breakers: circuit_breakers}
  end

  defp log_budget_violation(violation) do
    Logger.warning(
      "Coupling budget violation detected",
      interaction_type: violation.interaction_type,
      severity: violation.severity,
      usage: violation.current_usage,
      limit: violation.budget_limit,
      usage_ratio: violation.current_usage / violation.budget_limit
    )
  end

  defp emit_violation_telemetry(violation) do
    :telemetry.execute(
      [:mabeam, :coupling_budget, :violation],
      %{
        usage: violation.current_usage,
        limit: violation.budget_limit,
        usage_ratio: violation.current_usage / violation.budget_limit
      },
      %{
        interaction_type: violation.interaction_type,
        severity: violation.severity
      }
    )
  end

  # ============================================================================
  # Circuit Breaker Management
  # ============================================================================

  defp check_circuit_breaker(interaction_type, state) do
    case Map.get(state.circuit_breakers, interaction_type) do
      nil -> :closed
      %{state: :open, opened_at: opened_at} ->
        if circuit_breaker_should_close?(opened_at, state.config) do
          :closed
        else
          :open
        end
      %{state: :closed} -> :closed
    end
  end

  defp circuit_breaker_should_close?(opened_at, config) do
    elapsed = DateTime.diff(DateTime.utc_now(), opened_at, :millisecond)
    elapsed >= config.circuit_breaker_recovery_time
  end

  # ============================================================================
  # Usage Statistics Compilation
  # ============================================================================

  defp compile_usage_statistics(state) do
    %{
      current_window: state.current_window,
      usage_counts: state.usage_counts,
      budget_limits: extract_budget_limits(state.config),
      usage_ratios: calculate_usage_ratios(state),
      violations_this_window: count_violations_this_window(state),
      circuit_breaker_states: state.circuit_breakers,
      top_coupling_sources: identify_top_coupling_sources(state)
    }
  end

  defp calculate_usage_ratios(state) do
    Enum.map(state.usage_counts, fn {interaction_type, usage} ->
      limit = get_budget_limit(interaction_type, state.config)
      {interaction_type, usage / limit}
    end)
    |> Map.new()
  end

  # ============================================================================
  # Periodic Tasks
  # ============================================================================

  def handle_info(:reset_budget_window, state) do
    new_state = reset_budget_window(state)
    schedule_budget_window_reset()
    {:noreply, new_state}
  end

  def handle_info(:generate_coupling_report, state) do
    generate_and_emit_coupling_report(state)
    schedule_coupling_report()
    {:noreply, state}
  end

  defp reset_budget_window(state) do
    Logger.debug("Resetting coupling budget window")

    %{state |
      current_window: init_time_window(),
      usage_counts: init_usage_counts()
    }
  end

  defp generate_and_emit_coupling_report(state) do
    report = %{
      window_end: DateTime.utc_now(),
      total_interactions: Enum.sum(Map.values(state.usage_counts)),
      usage_by_type: state.usage_counts,
      violations_count: length(state.violation_history),
      circuit_breaker_trips: count_circuit_breaker_trips(state),
      average_coupling_ratio: calculate_average_coupling_ratio(state)
    }

    Logger.info("Coupling budget report", report: report)

    :telemetry.execute(
      [:mabeam, :coupling_budget, :report],
      %{
        total_interactions: report.total_interactions,
        violations_count: report.violations_count,
        average_coupling_ratio: report.average_coupling_ratio
      },
      report
    )
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp init_time_window do
    %{start: DateTime.utc_now(), duration_minutes: 1}
  end

  defp init_usage_counts do
    %{
      service_call: 0,
      register_call: 0,
      lookup_call: 0,
      telemetry_event: 0
    }
  end

  defp schedule_budget_window_reset do
    Process.send_after(self(), :reset_budget_window, 60_000)  # 1 minute
  end

  defp schedule_coupling_report do
    Process.send_after(self(), :generate_coupling_report, 300_000)  # 5 minutes
  end
end
```

#### 2.3.2 Contract Monitor

```elixir
defmodule MABEAM.Foundation.ContractMonitor do
  @moduledoc """
  Monitors contract compliance between MABEAM and Foundation applications.
  
  This module ensures that all interactions follow defined contracts and
  detects contract violations that could indicate hidden coupling or
  architectural drift.
  """

  use GenServer
  require Logger

  # ============================================================================
  # Contract Definitions
  # ============================================================================

  @foundation_service_contracts %{
    Foundation.ProcessRegistry => %{
      register: %{
        params: [:namespace, :service_name, :pid, :metadata],
        return_types: [:ok, {:error, :term}],
        side_effects: [:process_monitored, :registry_updated],
        max_duration_ms: 100
      },
      lookup: %{
        params: [:namespace, :service_name],
        return_types: [{:ok, :pid}, :error],
        side_effects: [],
        max_duration_ms: 50
      },
      unregister: %{
        params: [:namespace, :service_name],
        return_types: [:ok, {:error, :not_found}],
        side_effects: [:process_unmonitored, :registry_updated],
        max_duration_ms: 100
      }
    }
  }

  @mabeam_service_contracts %{
    # Contracts for MABEAM services when called by Foundation
    MABEAM.AgentRegistry => %{
      health_check: %{
        params: [],
        return_types: [:ok, {:error, :term}],
        side_effects: [],
        max_duration_ms: 1000
      }
    }
  }

  # ============================================================================
  # Contract Monitoring State
  # ============================================================================

  defstruct [
    :contract_definitions,
    :violation_history,
    :monitoring_enabled,
    :performance_baselines,
    :contract_stats
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    monitoring_enabled = Keyword.get(opts, :monitoring_enabled, true)

    state = %__MODULE__{
      contract_definitions: Map.merge(@foundation_service_contracts, @mabeam_service_contracts),
      violation_history: [],
      monitoring_enabled: monitoring_enabled,
      performance_baselines: %{},
      contract_stats: init_contract_stats()
    }

    if monitoring_enabled do
      setup_contract_monitoring()
    end

    {:ok, state}
  end

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Validate a service call against its contract.
  """
  @spec validate_service_call(module(), atom(), list(), term()) :: 
    :ok | {:violation, contract_violation()}
  def validate_service_call(module, function, args, result) do
    GenServer.call(__MODULE__, {:validate_service_call, module, function, args, result})
  end

  @doc """
  Record the performance of a service call for baseline tracking.
  """
  @spec record_call_performance(module(), atom(), duration_ms :: non_neg_integer()) :: :ok
  def record_call_performance(module, function, duration_ms) do
    GenServer.cast(__MODULE__, {:record_call_performance, module, function, duration_ms})
  end

  @doc """
  Get contract compliance statistics.
  """
  @spec get_compliance_statistics() :: contract_statistics()
  def get_compliance_statistics do
    GenServer.call(__MODULE__, :get_compliance_statistics)
  end

  # ============================================================================
  # Contract Validation
  # ============================================================================

  def handle_call({:validate_service_call, module, function, args, result}, _from, state) do
    if state.monitoring_enabled do
      validation_result = perform_contract_validation(module, function, args, result, state)
      new_state = record_validation_result(module, function, validation_result, state)
      {:reply, validation_result, new_state}
    else
      {:reply, :ok, state}
    end
  end

  def handle_call(:get_compliance_statistics, _from, state) do
    stats = compile_compliance_statistics(state)
    {:reply, stats, state}
  end

  def handle_cast({:record_call_performance, module, function, duration_ms}, state) do
    new_state = update_performance_baseline(module, function, duration_ms, state)
    {:noreply, new_state}
  end

  # ============================================================================
  # Contract Validation Logic
  # ============================================================================

  defp perform_contract_validation(module, function, args, result, state) do
    case get_contract_definition(module, function, state) do
      nil ->
        # No contract defined - this could be a violation itself
        {:violation, %{
          type: :no_contract_defined,
          module: module,
          function: function,
          severity: :warning
        }}

      contract ->
        violations = []

        # Validate parameters
        violations = validate_parameters(args, contract.params, violations)

        # Validate return type
        violations = validate_return_type(result, contract.return_types, violations)

        # Check performance contract
        violations = validate_performance_contract(module, function, contract, state, violations)

        case violations do
          [] -> :ok
          violations -> {:violation, %{
            type: :contract_violations,
            module: module,
            function: function,
            violations: violations,
            severity: determine_violation_severity(violations)
          }}
        end
    end
  end

  defp validate_parameters(args, expected_param_types, violations) do
    if length(args) != length(expected_param_types) do
      violation = %{
        type: :parameter_count_mismatch,
        expected: length(expected_param_types),
        actual: length(args)
      }
      [violation | violations]
    else
      # Validate each parameter type
      args
      |> Enum.zip(expected_param_types)
      |> Enum.reduce(violations, fn {arg, expected_type}, acc ->
        if validate_parameter_type(arg, expected_type) do
          acc
        else
          violation = %{
            type: :parameter_type_mismatch,
            expected_type: expected_type,
            actual_value: arg
          }
          [violation | acc]
        end
      end)
    end
  end

  defp validate_return_type(result, expected_return_types, violations) do
    if Enum.any?(expected_return_types, &matches_return_type?(result, &1)) do
      violations
    else
      violation = %{
        type: :return_type_mismatch,
        expected_types: expected_return_types,
        actual_result: result
      }
      [violation | violations]
    end
  end

  defp validate_performance_contract(module, function, contract, state, violations) do
    case Map.get(contract, :max_duration_ms) do
      nil ->
        violations

      max_duration_ms ->
        case get_recent_performance(module, function, state) do
          nil ->
            violations  # No performance data yet

          recent_duration_ms when recent_duration_ms > max_duration_ms ->
            violation = %{
              type: :performance_contract_violation,
              max_duration_ms: max_duration_ms,
              actual_duration_ms: recent_duration_ms
            }
            [violation | violations]

          _ ->
            violations
        end
    end
  end

  # ============================================================================
  # Contract Definition Helpers
  # ============================================================================

  defp get_contract_definition(module, function, state) do
    case Map.get(state.contract_definitions, module) do
      nil -> nil
      module_contracts -> Map.get(module_contracts, function)
    end
  end

  defp validate_parameter_type(value, :namespace) when is_atom(value), do: true
  defp validate_parameter_type(value, :service_name) when is_atom(value) or is_tuple(value), do: true
  defp validate_parameter_type(value, :pid) when is_pid(value), do: true
  defp validate_parameter_type(value, :metadata) when is_map(value), do: true
  defp validate_parameter_type(_, :term), do: true  # Any term is valid
  defp validate_parameter_type(_, _), do: false

  defp matches_return_type?(:ok, :ok), do: true
  defp matches_return_type?({:ok, _}, {:ok, :pid}) when is_pid(elem(tuple, 1)), do: true
  defp matches_return_type?({:ok, _}, {:ok, :term}), do: true
  defp matches_return_type?({:error, _}, {:error, :term}), do: true
  defp matches_return_type?(:error, :error), do: true
  defp matches_return_type?(_, :term), do: true  # Any term matches :term
  defp matches_return_type?(_, _), do: false

  # ============================================================================
  # Performance Baseline Management
  # ============================================================================

  defp update_performance_baseline(module, function, duration_ms, state) do
    key = {module, function}
    
    case Map.get(state.performance_baselines, key) do
      nil ->
        baseline = %{
          samples: [duration_ms],
          average: duration_ms,
          min: duration_ms,
          max: duration_ms,
          updated_at: DateTime.utc_now()
        }
        
        %{state | performance_baselines: Map.put(state.performance_baselines, key, baseline)}

      existing_baseline ->
        updated_samples = [duration_ms | existing_baseline.samples] |> Enum.take(100)
        
        updated_baseline = %{existing_baseline |
          samples: updated_samples,
          average: Enum.sum(updated_samples) / length(updated_samples),
          min: min(existing_baseline.min, duration_ms),
          max: max(existing_baseline.max, duration_ms),
          updated_at: DateTime.utc_now()
        }
        
        %{state | performance_baselines: Map.put(state.performance_baselines, key, updated_baseline)}
    end
  end

  defp get_recent_performance(module, function, state) do
    case Map.get(state.performance_baselines, {module, function}) do
      nil -> nil
      baseline -> baseline.average
    end
  end

  # ============================================================================
  # Contract Monitoring Setup
  # ============================================================================

  defp setup_contract_monitoring do
    # Set up telemetry handlers for contract monitoring
    :telemetry.attach_many(
      :mabeam_contract_monitor,
      [
        [:mabeam, :adapter, :foundation_call],
        [:foundation, :process_registry, :call_completed]
      ],
      &handle_service_call_telemetry/4,
      %{}
    )
  end

  defp handle_service_call_telemetry([:mabeam, :adapter, :foundation_call], measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {
      :validate_and_record_call,
      metadata.module,
      metadata.function,
      metadata.args,
      metadata.result,
      measurements.duration
    })
  end

  def handle_cast({:validate_and_record_call, module, function, args, result, duration}, state) do
    # Validate the call
    validation_result = perform_contract_validation(module, function, args, result, state)
    
    # Record performance
    new_state = update_performance_baseline(module, function, duration, state)
    
    # Record validation result
    final_state = record_validation_result(module, function, validation_result, new_state)
    
    {:noreply, final_state}
  end

  # ============================================================================
  # Violation Recording and Reporting
  # ============================================================================

  defp record_validation_result(module, function, validation_result, state) do
    case validation_result do
      :ok ->
        # Update success stats
        update_contract_stats(module, function, :success, state)

      {:violation, violation_details} ->
        # Record violation
        violation = Map.merge(violation_details, %{
          timestamp: DateTime.utc_now(),
          module: module,
          function: function
        })

        # Log violation
        log_contract_violation(violation)

        # Update violation history
        violation_history = [violation | state.violation_history] |> Enum.take(1000)

        # Update violation stats
        new_state = update_contract_stats(module, function, :violation, state)

        # Emit telemetry
        emit_contract_violation_telemetry(violation)

        %{new_state | violation_history: violation_history}
    end
  end

  defp log_contract_violation(violation) do
    Logger.warning(
      "Contract violation detected",
      module: violation.module,
      function: violation.function,
      violation_type: violation.type,
      severity: violation.severity
    )
  end

  defp emit_contract_violation_telemetry(violation) do
    :telemetry.execute(
      [:mabeam, :contract_monitor, :violation],
      %{violation_count: 1},
      violation
    )
  end

  # ============================================================================
  # Statistics and Reporting
  # ============================================================================

  defp compile_compliance_statistics(state) do
    total_calls = sum_contract_stats(state.contract_stats, :total)
    total_violations = sum_contract_stats(state.contract_stats, :violations)

    %{
      total_monitored_calls: total_calls,
      total_violations: total_violations,
      compliance_rate: if(total_calls > 0, do: (total_calls - total_violations) / total_calls, else: 1.0),
      violations_by_module: group_violations_by_module(state.violation_history),
      performance_baselines: state.performance_baselines,
      recent_violations: Enum.take(state.violation_history, 10)
    }
  end

  defp init_contract_stats, do: %{}

  defp update_contract_stats(module, function, result_type, state) do
    key = {module, function}
    
    current_stats = Map.get(state.contract_stats, key, %{total: 0, violations: 0, successes: 0})
    
    updated_stats = case result_type do
      :success ->
        %{current_stats | total: current_stats.total + 1, successes: current_stats.successes + 1}
      :violation ->
        %{current_stats | total: current_stats.total + 1, violations: current_stats.violations + 1}
    end
    
    %{state | contract_stats: Map.put(state.contract_stats, key, updated_stats)}
  end
end
```

## 3. Implementation Strategy

### 3.1 Phase 1: Foundation Independence (Week 1)

#### Step 1: Create Adapter Infrastructure
```bash
# Create adapter modules
lib/mabeam/foundation/
├── service_adapter.ex           # Central Foundation service adapter
├── event_translator.ex          # Event namespace translation
├── config_bridge.ex            # Configuration migration bridge
└── service_behaviour.ex        # Contract definitions
```

#### Step 2: Replace Direct Foundation Calls
```elixir
# BEFORE (Direct coupling in MABEAM.AgentRegistry)
Foundation.ProcessRegistry.register(:production, {:mabeam, :agent_registry}, self(), metadata)

# AFTER (Through adapter)
MABEAM.Foundation.ServiceAdapter.register_process(%{
  id: :agent_registry,
  pid: self(),
  type: :mabeam_service,
  metadata: metadata
})
```

#### Step 3: Implement Coupling Budget System
```bash
# Add coupling control
lib/mabeam/foundation/
├── coupling_budget.ex          # Budget enforcement
├── contract_monitor.ex         # Contract compliance
└── circuit_breaker.ex         # Failure protection
```

### 3.2 Phase 2: Event System Decoupling (Week 2)

#### Step 1: Event Namespace Migration
```elixir
# BEFORE (Coupled namespacing)
[:foundation, :mabeam, :agent, :registered]

# AFTER (Translated through adapter)
[:mabeam, :agent, :registered] -> [:foundation, :process, :registered]
```

#### Step 2: Configuration Separation
```elixir
# Move configuration from :foundation to :mabeam app
# Provide migration bridge for backward compatibility
MABEAM.Foundation.ConfigBridge.migrate_configuration()
```

### 3.3 Phase 3: Validation and Monitoring (Week 3)

#### Step 1: Contract Testing
```bash
# Add comprehensive contract tests
test/mabeam/foundation/
├── adapter_test.exs            # Adapter functionality
├── contract_compliance_test.exs # Contract validation
├── coupling_budget_test.exs    # Budget enforcement
└── integration_test.exs        # End-to-end integration
```

#### Step 2: Monitoring Dashboard
```elixir
# Real-time coupling monitoring
defmodule MABEAM.Foundation.CouplingDashboard do
  # Live dashboard showing:
  # - Coupling budget usage
  # - Contract violations
  # - Circuit breaker states
  # - Performance metrics
end
```

## 4. Success Metrics and Monitoring

### 4.1 Coupling Reduction Metrics
- **Direct Foundation calls**: Target 0 (all through adapter)
- **Shared ETS tables**: Target 0 (isolated state)
- **Configuration coupling**: Target 0 (separate app configs)
- **Event namespace coupling**: Target 0 (translated events)

### 4.2 Performance Impact Metrics
- **Adapter overhead**: Target <5ms additional latency
- **Coupling budget compliance**: Target >95%
- **Contract compliance**: Target 100%
- **Circuit breaker trips**: Target <1 per day

### 4.3 Architectural Quality Metrics
- **Context window efficiency**: Each app fits in 8K lines
- **Test isolation**: MABEAM tests run without Foundation
- **Deployment independence**: Foundation deploys standalone
- **Development team independence**: Teams work in parallel

## 5. Risk Mitigation

### 5.1 Rollback Plan
```elixir
# Emergency rollback to direct coupling if adapter fails
defmodule MABEAM.Foundation.EmergencyFallback do
  def enable_direct_coupling_mode do
    # Bypass adapter and use direct Foundation calls
    Application.put_env(:mabeam, :emergency_direct_coupling, true)
  end
end
```

### 5.2 Gradual Migration
```elixir
# Feature flag for gradual migration
config :mabeam,
  foundation_integration: %{
    use_adapter: true,              # Start with adapter
    fallback_to_direct: true,       # Fallback on adapter failure
    monitor_performance: true,      # Monitor adapter overhead
    migration_complete: false       # Mark when migration done
  }
```

## Conclusion

This architecture provides a comprehensive solution for decoupling Foundation and MABEAM while maintaining functionality and preventing coupling regression. The four-layer approach (Integration, Control, Foundation, MABEAM) ensures that coupling is explicit, monitored, and controlled.

**Key Benefits**:
1. **Context Window Friendly**: Each application becomes manageable in size
2. **Coupling Control**: Automated monitoring and enforcement prevents coupling growth
3. **Architectural Quality**: Clean boundaries with contract enforcement
4. **Team Independence**: Teams can develop in parallel with clear contracts
5. **Deployment Flexibility**: Applications can be deployed independently

**Implementation Timeline**: 3 weeks with systematic validation at each phase to ensure the decoupling doesn't break functionality while achieving the architectural goals.