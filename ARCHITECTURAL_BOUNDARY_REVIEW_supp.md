# ARCHITECTURAL_BOUNDARY_REVIEW_supp.md

## Executive Summary

This supplementary document provides detailed integration contracts, interfaces, and implementation specifications for Foundation ↔ MABEAM architectural boundaries. It defines concrete APIs, message protocols, error handling patterns, and testing contracts needed for clean architectural separation.

**Scope**: Detailed implementation specifications complementing ARCHITECTURAL_BOUNDARY_REVIEW.md
**Target**: Production-ready integration contracts with comprehensive error handling and monitoring

## 1. Foundation ↔ MABEAM Integration Architecture

### 1.1 Integration Layer Design

```elixir
# Foundation.Integration.MABEAM - Bridge module for MABEAM integration
defmodule Foundation.Integration.MABEAM do
  @moduledoc """
  Integration boundary between Foundation infrastructure and MABEAM services.
  
  This module provides the official API for MABEAM services to interact with
  Foundation infrastructure while maintaining architectural boundaries.
  """
  
  use Foundation.ServiceBehaviour
  alias Foundation.{ProcessRegistry, Events, Config}
  
  # Public API - Process Management
  @callback register_agent(agent_spec :: Agent.spec()) :: 
    {:ok, pid()} | {:error, reason :: term()}
    
  @callback unregister_agent(agent_id :: Agent.id()) :: 
    :ok | {:error, reason :: term()}
    
  @callback list_agents(filter :: Agent.filter()) :: 
    {:ok, [Agent.t()]} | {:error, reason :: term()}
  
  # Public API - Event Integration  
  @callback publish_agent_event(event :: Agent.event()) :: 
    :ok | {:error, reason :: term()}
    
  @callback subscribe_to_foundation_events(subscriber :: pid(), topics :: [atom()]) :: 
    :ok | {:error, reason :: term()}
  
  # Public API - Configuration Integration
  @callback get_foundation_config(key :: Config.key()) :: 
    {:ok, Config.value()} | {:error, :not_found}
    
  @callback update_mabeam_config(updates :: Config.updates()) :: 
    :ok | {:error, reason :: term()}
end
```

### 1.2 Process Registry Integration Contract

```elixir
# Foundation.ProcessRegistry.MABEAMAdapter
defmodule Foundation.ProcessRegistry.MABEAMAdapter do
  @moduledoc """
  Adapter for MABEAM-specific process registration patterns.
  
  Provides MABEAM-optimized interface to Foundation.ProcessRegistry
  while maintaining architectural boundaries.
  """
  
  alias Foundation.ProcessRegistry
  alias MABEAM.Types.{Agent, Coordination}
  
  # Agent Registration Interface
  @spec register_agent(Agent.spec()) :: 
    {:ok, Agent.registration()} | {:error, term()}
  def register_agent(%Agent.Spec{} = spec) do
    registration_opts = [
      type: :agent,
      supervision: spec.supervision_strategy,
      restart: spec.restart_strategy,
      metadata: %{
        agent_type: spec.type,
        capabilities: spec.capabilities,
        resource_limits: spec.resource_limits
      }
    ]
    
    with {:ok, pid} <- ProcessRegistry.register(spec.id, spec.module, spec.args, registration_opts),
         :ok <- setup_agent_monitoring(pid, spec),
         :ok <- publish_agent_registered_event(spec, pid) do
      {:ok, %Agent.Registration{
        id: spec.id,
        pid: pid,
        status: :active,
        registered_at: DateTime.utc_now()
      }}
    else
      {:error, reason} -> 
        Logger.error("Agent registration failed", agent: spec.id, reason: reason)
        {:error, reason}
    end
  end
  
  # Coordination Process Registration
  @spec register_coordination_process(Coordination.spec()) :: 
    {:ok, Coordination.registration()} | {:error, term()}
  def register_coordination_process(%Coordination.Spec{} = spec) do
    # Implementation with coordination-specific registration logic
  end
  
  # Monitoring and Health Checks
  defp setup_agent_monitoring(pid, spec) do
    monitor_ref = Process.monitor(pid)
    
    :ok = Foundation.Telemetry.agent_registered(spec.id, pid)
    :ok = schedule_health_check(pid, spec.health_check_interval)
    
    # Store monitoring metadata
    ProcessRegistry.put_metadata(pid, :monitor_ref, monitor_ref)
    ProcessRegistry.put_metadata(pid, :health_check_enabled, true)
  end
end
```

## 2. Event Integration Contracts

### 2.1 Event Bridge Architecture

```elixir
# Foundation.Events.MABEAMBridge
defmodule Foundation.Events.MABEAMBridge do
  @moduledoc """
  Event integration bridge between Foundation and MABEAM systems.
  
  Provides event translation, filtering, and routing while maintaining
  architectural boundaries and preventing event coupling.
  """
  
  use GenServer
  alias Foundation.Events
  alias MABEAM.Events, as: MABEAMEvents
  
  # Event Translation Specifications
  @foundation_to_mabeam_mappings %{
    "foundation.process.started" => "mabeam.agent.infrastructure_ready",
    "foundation.process.crashed" => "mabeam.agent.infrastructure_failed", 
    "foundation.config.updated" => "mabeam.coordination.config_changed",
    "foundation.telemetry.alert" => "mabeam.system.alert_received"
  }
  
  @mabeam_to_foundation_mappings %{
    "mabeam.agent.created" => "foundation.process.agent_created",
    "mabeam.coordination.started" => "foundation.process.coordination_started",
    "mabeam.economics.transaction" => "foundation.telemetry.transaction_recorded"
  }
  
  # Event Contract Specifications
  @type foundation_event :: %{
    type: String.t(),
    source: atom(),
    data: map(),
    timestamp: DateTime.t(),
    correlation_id: String.t()
  }
  
  @type mabeam_event :: %{
    event_type: atom(),
    agent_id: String.t() | nil,
    payload: map(),
    metadata: map(),
    occurred_at: DateTime.t()
  }
  
  # Public API
  @spec start_link(opts :: keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @spec translate_foundation_event(foundation_event()) :: 
    {:ok, mabeam_event()} | {:ignore} | {:error, term()}
  def translate_foundation_event(foundation_event) do
    case Map.get(@foundation_to_mabeam_mappings, foundation_event.type) do
      nil -> {:ignore}
      mabeam_type -> 
        {:ok, %{
          event_type: String.to_atom(mabeam_type),
          agent_id: extract_agent_id(foundation_event),
          payload: transform_payload(foundation_event.data, :foundation_to_mabeam),
          metadata: %{
            source_system: :foundation,
            correlation_id: foundation_event.correlation_id,
            translated_at: DateTime.utc_now()
          },
          occurred_at: foundation_event.timestamp
        }}
    end
  end
  
  # Error Handling and Recovery
  defp handle_translation_error(error, event) do
    Logger.error("Event translation failed", 
      error: error, 
      event_type: event.type,
      correlation_id: event.correlation_id
    )
    
    # Publish dead letter event for debugging
    Events.publish("foundation.events.translation_failed", %{
      original_event: event,
      error: error,
      failed_at: DateTime.utc_now()
    })
    
    {:error, error}
  end
end
```

### 2.2 Event Schema Validation

```elixir
# Foundation.Events.SchemaValidator
defmodule Foundation.Events.SchemaValidator do
  @moduledoc """
  Schema validation for cross-boundary events to ensure API contracts.
  """
  
  # Foundation Event Schemas
  @foundation_event_schema %{
    type: :string,
    source: :atom,
    data: :map,
    timestamp: :datetime,
    correlation_id: :string
  }
  
  # MABEAM Event Schemas  
  @mabeam_event_schema %{
    event_type: :atom,
    agent_id: {:union, [:string, :nil]},
    payload: :map,
    metadata: :map,
    occurred_at: :datetime
  }
  
  @spec validate_foundation_event(map()) :: 
    {:ok, foundation_event()} | {:error, validation_errors()}
  def validate_foundation_event(event) do
    # Implementation with comprehensive schema validation
  end
  
  @spec validate_mabeam_event(map()) :: 
    {:ok, mabeam_event()} | {:error, validation_errors()}
  def validate_mabeam_event(event) do
    # Implementation with comprehensive schema validation
  end
end
```

## 3. Configuration Integration Contracts

### 3.1 Configuration Boundary Interface

```elixir
# Foundation.Config.MABEAMInterface
defmodule Foundation.Config.MABEAMInterface do
  @moduledoc """
  Configuration integration interface for MABEAM services.
  
  Provides controlled access to Foundation configuration while maintaining
  architectural boundaries and preventing configuration coupling.
  """
  
  alias Foundation.Config
  
  # MABEAM Configuration Namespace
  @mabeam_config_namespace "mabeam"
  @allowed_foundation_configs [
    "foundation.telemetry.enabled",
    "foundation.process_registry.backend",
    "foundation.events.max_buffer_size",
    "foundation.infrastructure.rate_limits"
  ]
  
  # Configuration Access Interface
  @spec get_mabeam_config(key :: String.t()) :: 
    {:ok, term()} | {:error, :not_found} | {:error, :unauthorized}
  def get_mabeam_config(key) do
    namespaced_key = "#{@mabeam_config_namespace}.#{key}"
    Config.get(namespaced_key)
  end
  
  @spec get_foundation_config(key :: String.t()) :: 
    {:ok, term()} | {:error, :not_found} | {:error, :unauthorized}
  def get_foundation_config(key) do
    if key in @allowed_foundation_configs do
      Config.get(key)
    else
      {:error, :unauthorized}
    end
  end
  
  # Configuration Update Interface
  @spec update_mabeam_config(updates :: map()) :: 
    {:ok, Config.update_result()} | {:error, term()}
  def update_mabeam_config(updates) when is_map(updates) do
    namespaced_updates = 
      updates
      |> Enum.map(fn {key, value} -> {"#{@mabeam_config_namespace}.#{key}", value} end)
      |> Map.new()
    
    with :ok <- validate_config_updates(namespaced_updates),
         {:ok, result} <- Config.update(namespaced_updates),
         :ok <- notify_config_change(updates) do
      {:ok, result}
    end
  end
  
  # Configuration Change Notifications
  defp notify_config_change(updates) do
    Foundation.Events.publish("mabeam.config.updated", %{
      updates: updates,
      updated_at: DateTime.utc_now(),
      updated_by: :mabeam_interface
    })
  end
end
```

## 4. Error Handling and Recovery Contracts

### 4.1 Cross-Boundary Error Handling

```elixir
# Foundation.ErrorHandling.MABEAMIntegration
defmodule Foundation.ErrorHandling.MABEAMIntegration do
  @moduledoc """
  Standardized error handling patterns for Foundation ↔ MABEAM integration.
  
  Provides error translation, recovery strategies, and monitoring
  for cross-boundary operations.
  """
  
  # Error Type Definitions
  @type integration_error :: 
    {:foundation_error, Foundation.Error.t()} |
    {:mabeam_error, MABEAM.Error.t()} |
    {:translation_error, term()} |
    {:timeout_error, timeout_details()} |
    {:network_error, network_details()}
  
  # Error Recovery Strategies
  @error_recovery_strategies %{
    {:foundation_error, :process_not_found} => :retry_with_backoff,
    {:foundation_error, :registry_unavailable} => :fallback_to_local,
    {:mabeam_error, :agent_not_responding} => :restart_agent,
    {:translation_error, _} => :log_and_continue,
    {:timeout_error, _} => :retry_with_exponential_backoff,
    {:network_error, _} => :circuit_breaker_pattern
  }
  
  # Error Handling Interface
  @spec handle_integration_error(integration_error(), context :: map()) :: 
    {:ok, recovery_action()} | {:error, :unrecoverable}
  def handle_integration_error(error, context) do
    error_key = normalize_error_key(error)
    strategy = Map.get(@error_recovery_strategies, error_key, :log_and_fail)
    
    Logger.error("Integration error occurred", 
      error: error, 
      context: context, 
      recovery_strategy: strategy
    )
    
    case execute_recovery_strategy(strategy, error, context) do
      {:ok, action} -> 
        record_error_recovery_success(error, strategy, context)
        {:ok, action}
      {:error, reason} ->
        record_error_recovery_failure(error, strategy, reason, context)
        {:error, :unrecoverable}
    end
  end
  
  # Circuit Breaker for Integration Points
  defp execute_recovery_strategy(:circuit_breaker_pattern, error, context) do
    circuit_key = "integration:#{context.integration_point}"
    
    case Foundation.Infrastructure.CircuitBreaker.state(circuit_key) do
      :open -> {:error, :circuit_breaker_open}
      :half_open -> attempt_recovery_operation(error, context)
      :closed -> attempt_recovery_operation(error, context)
    end
  end
end
```

### 4.2 Fault Tolerance Patterns

```elixir
# Foundation.FaultTolerance.MABEAMPatterns
defmodule Foundation.FaultTolerance.MABEAMPatterns do
  @moduledoc """
  Fault tolerance patterns specific to Foundation ↔ MABEAM integration.
  """
  
  # Supervision Strategy Definitions
  @mabeam_integration_supervision_spec [
    # Integration Bridge Process
    {Foundation.Events.MABEAMBridge, []},
    
    # Configuration Interface Process  
    {Foundation.Config.MABEAMInterface, []},
    
    # Process Registry Adapter
    {Foundation.ProcessRegistry.MABEAMAdapter, []},
    
    # Error Handling Monitor
    {Foundation.ErrorHandling.MABEAMIntegration, []}
  ]
  
  @supervisor_opts [
    strategy: :one_for_one,
    max_restarts: 3,
    max_seconds: 5
  ]
  
  # Graceful Degradation Patterns
  @spec handle_foundation_unavailable(operation :: atom(), args :: list()) :: 
    {:ok, term()} | {:degraded, term()} | {:error, term()}
  def handle_foundation_unavailable(operation, args) do
    case operation do
      :register_process -> 
        # Fallback to local registration
        {:degraded, register_locally(args)}
      :publish_event ->
        # Buffer events for later processing
        {:degraded, buffer_event(args)}
      :get_config ->
        # Use cached configuration
        {:degraded, get_cached_config(args)}
      _ ->
        {:error, {:foundation_unavailable, operation}}
    end
  end
end
```

## 5. Performance and Monitoring Contracts

### 5.1 Performance Monitoring Interface

```elixir
# Foundation.Telemetry.MABEAMMetrics
defmodule Foundation.Telemetry.MABEAMMetrics do
  @moduledoc """
  Performance monitoring and metrics collection for MABEAM integration.
  """
  
  # Metric Definitions
  @integration_metrics [
    # Process Registration Metrics
    {:counter, "foundation.mabeam.processes.registered.total"},
    {:counter, "foundation.mabeam.processes.unregistered.total"},
    {:histogram, "foundation.mabeam.process.registration.duration"},
    
    # Event Processing Metrics
    {:counter, "foundation.mabeam.events.translated.total"},
    {:counter, "foundation.mabeam.events.failed.total"},
    {:histogram, "foundation.mabeam.event.translation.duration"},
    
    # Configuration Access Metrics
    {:counter, "foundation.mabeam.config.reads.total"},
    {:counter, "foundation.mabeam.config.writes.total"},
    {:histogram, "foundation.mabeam.config.access.duration"},
    
    # Error Handling Metrics
    {:counter, "foundation.mabeam.errors.handled.total"},
    {:counter, "foundation.mabeam.errors.unrecoverable.total"},
    {:histogram, "foundation.mabeam.error.recovery.duration"}
  ]
  
  # Performance SLA Definitions
  @performance_slas %{
    process_registration: %{max_duration: 100, unit: :millisecond},
    event_translation: %{max_duration: 10, unit: :millisecond},
    config_access: %{max_duration: 50, unit: :millisecond},
    error_recovery: %{max_duration: 1000, unit: :millisecond}
  }
  
  # Monitoring Interface
  @spec record_operation(operation :: atom(), duration :: integer(), metadata :: map()) :: :ok
  def record_operation(operation, duration, metadata \\ %{}) do
    # Record operation metrics
    :telemetry.execute(
      [:foundation, :mabeam, operation],
      %{duration: duration},
      metadata
    )
    
    # Check SLA compliance
    check_sla_compliance(operation, duration, metadata)
  end
  
  # SLA Monitoring
  defp check_sla_compliance(operation, duration, metadata) do
    case Map.get(@performance_slas, operation) do
      nil -> :ok
      %{max_duration: max_duration, unit: unit} ->
        if duration > convert_to_native_time(max_duration, unit) do
          record_sla_violation(operation, duration, max_duration, metadata)
        end
    end
  end
end
```

## 6. Testing Contracts and Interfaces

### 6.1 Integration Testing Framework

```elixir
# Foundation.Testing.MABEAMIntegration
defmodule Foundation.Testing.MABEAMIntegration do
  @moduledoc """
  Testing utilities and contracts for Foundation ↔ MABEAM integration testing.
  """
  
  # Test Fixture Definitions
  @test_agent_spec %MABEAM.Agent.Spec{
    id: "test_agent_001",
    module: TestAgent,
    args: [],
    type: :test,
    capabilities: [:testing],
    supervision_strategy: :one_for_one,
    restart_strategy: :temporary,
    resource_limits: %{memory: "100MB", cpu: "10%"}
  }
  
  # Integration Test Helpers
  @spec setup_integration_test() :: {:ok, test_context()}
  def setup_integration_test() do
    # Setup Foundation services
    {:ok, _} = Foundation.ProcessRegistry.start_link([])
    {:ok, _} = Foundation.Events.start_link([])
    {:ok, _} = Foundation.Config.start_link([])
    
    # Setup MABEAM integration layer
    {:ok, _} = Foundation.Integration.MABEAM.start_link([])
    
    # Setup test monitoring
    test_context = %{
      registry_pid: Process.whereis(Foundation.ProcessRegistry),
      events_pid: Process.whereis(Foundation.Events),
      integration_pid: Process.whereis(Foundation.Integration.MABEAM),
      test_started_at: DateTime.utc_now()
    }
    
    {:ok, test_context}
  end
  
  # Test Contract Validation
  @spec validate_integration_contract(operation :: atom(), result :: term()) :: 
    :ok | {:error, contract_violation()}
  def validate_integration_contract(:register_agent, {:ok, %Agent.Registration{} = reg}) do
    # Validate registration contract compliance
    validate_registration_fields(reg)
  end
  
  def validate_integration_contract(:register_agent, {:error, reason}) do
    # Validate error contract compliance
    validate_error_format(reason)
  end
  
  # Performance Test Utilities
  @spec measure_integration_performance(operation :: atom(), args :: list()) :: 
    {:ok, performance_result()} | {:error, term()}
  def measure_integration_performance(operation, args) do
    start_time = System.monotonic_time(:microsecond)
    
    result = apply(Foundation.Integration.MABEAM, operation, args)
    
    end_time = System.monotonic_time(:microsecond)
    duration = end_time - start_time
    
    performance_result = %{
      operation: operation,
      duration_microseconds: duration,
      result: result,
      memory_before: get_memory_usage(),
      memory_after: get_memory_usage()
    }
    
    {:ok, performance_result}
  end
end
```

### 6.2 Contract Testing Specifications  

```elixir
# Foundation.Testing.MABEAMContracts
defmodule Foundation.Testing.MABEAMContracts do
  @moduledoc """
  Contract testing specifications for Foundation ↔ MABEAM integration.
  """
  
  use ExUnit.Case
  
  # Contract Test Definitions
  describe "Foundation.Integration.MABEAM contract compliance" do
    test "register_agent/1 returns proper success contract" do
      spec = build_valid_agent_spec()
      
      assert {:ok, %Agent.Registration{} = registration} = 
        Foundation.Integration.MABEAM.register_agent(spec)
      
      # Validate contract fields
      assert registration.id == spec.id
      assert is_pid(registration.pid)
      assert registration.status == :active
      assert %DateTime{} = registration.registered_at
    end
    
    test "register_agent/1 returns proper error contract" do
      invalid_spec = build_invalid_agent_spec()
      
      assert {:error, reason} = 
        Foundation.Integration.MABEAM.register_agent(invalid_spec)
      
      # Validate error contract
      assert is_atom(reason) or is_tuple(reason)
    end
    
    test "event translation maintains contract integrity" do
      foundation_event = build_foundation_event()
      
      assert {:ok, mabeam_event} = 
        Foundation.Events.MABEAMBridge.translate_foundation_event(foundation_event)
      
      # Validate translation contract
      assert is_atom(mabeam_event.event_type)
      assert is_map(mabeam_event.payload)
      assert %DateTime{} = mabeam_event.occurred_at
    end
  end
  
  # Performance Contract Tests
  describe "performance contract compliance" do
    test "process registration completes within SLA" do
      spec = build_valid_agent_spec()
      
      {duration, {:ok, _}} = :timer.tc(fn ->
        Foundation.Integration.MABEAM.register_agent(spec)
      end)
      
      # Validate performance contract (100ms SLA)
      assert duration < 100_000, "Registration exceeded 100ms SLA: #{duration}μs"
    end
  end
end
```

## 7. Migration and Rollback Contracts

### 7.1 Migration Strategy Contract

```elixir
# Foundation.Migration.MABEAMIntegration
defmodule Foundation.Migration.MABEAMIntegration do
  @moduledoc """
  Migration contracts and strategies for Foundation ↔ MABEAM integration changes.
  """
  
  # Migration Version Control
  @current_integration_version "2.1.0"
  @supported_versions ["2.0.0", "2.0.1", "2.1.0"]
  
  # Migration Interface
  @spec migrate_integration(from_version :: String.t(), to_version :: String.t()) :: 
    {:ok, migration_result()} | {:error, migration_error()}
  def migrate_integration(from_version, to_version) do
    with :ok <- validate_migration_path(from_version, to_version),
         {:ok, migration_plan} <- create_migration_plan(from_version, to_version),
         {:ok, result} <- execute_migration(migration_plan) do
      {:ok, result}
    end
  end
  
  # Rollback Contract
  @spec rollback_integration(to_version :: String.t()) :: 
    {:ok, rollback_result()} | {:error, rollback_error()}
  def rollback_integration(to_version) do
    current_version = get_current_integration_version()
    
    with :ok <- validate_rollback_path(current_version, to_version),
         {:ok, rollback_plan} <- create_rollback_plan(current_version, to_version),
         {:ok, result} <- execute_rollback(rollback_plan) do
      {:ok, result}
    end
  end
end
```

## Conclusion

This supplementary document provides comprehensive implementation specifications for Foundation ↔ MABEAM architectural boundaries, including:

1. **Detailed API Contracts** - Concrete interfaces with type specifications and error handling
2. **Event Integration Architecture** - Event translation, validation, and routing systems
3. **Configuration Management** - Controlled configuration access with proper boundaries
4. **Error Handling Patterns** - Standardized error recovery and fault tolerance strategies
5. **Performance Monitoring** - SLA definitions and comprehensive metrics collection
6. **Testing Frameworks** - Contract testing and integration test utilities
7. **Migration Strategies** - Version control and rollback procedures

These specifications ensure clean architectural boundaries while providing robust, production-ready integration between Foundation infrastructure and MABEAM services.

**Implementation Priority**: HIGH - Required for ProcessRegistry refactoring and OTP supervision completion
**Dependencies**: Foundation.ProcessRegistry, Foundation.Events, Foundation.Config
**Testing Requirements**: Comprehensive contract testing and performance validation