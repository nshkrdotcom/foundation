# Foundation OS API Contracts
**Version 1.0 - Interface Definitions Between System Layers**  
**Date: June 27, 2025**

## Executive Summary

This document defines the precise API contracts between Foundation, FoundationJido, and DSPEx layers. These contracts ensure clean separation of concerns, enable independent development, and provide stability guarantees for the dependency-based architecture.

**Contract Versioning**: Semantic versioning with backward compatibility guarantees  
**Interface Stability**: APIs marked as `@stable` maintain backward compatibility  
**Breaking Changes**: Require major version increment and migration path

## Foundation Layer API Contracts

### Foundation.ProcessRegistry

**Core Registration Interface**:

```elixir
@contract "foundation.process_registry.v1"
defmodule Foundation.ProcessRegistry do
  @moduledoc """
  Universal process registration and discovery service.
  Provides foundation for agent management without agent-specific logic.
  """
  
  @typedoc "Registry namespace for logical separation"
  @type namespace :: atom()
  
  @typedoc "Process metadata for registration"
  @type metadata :: %{
    type: atom(),
    capabilities: [atom()],
    name: String.t() | atom(),
    restart_policy: :permanent | :temporary | :transient,
    tags: [atom()],
    custom_data: map()
  }
  
  @typedoc "Registry entry"
  @type entry :: %{
    pid: pid(),
    metadata: metadata(),
    registered_at: DateTime.t(),
    namespace: namespace()
  }
  
  @doc """
  Register a process with metadata.
  """
  @spec register(pid(), metadata(), namespace()) :: 
    {:ok, entry()} | {:error, Foundation.Types.Error.t()}
  def register(pid, metadata, namespace \\ :default)
  
  @doc """
  Lookup processes by various criteria.
  """
  @spec lookup(pid() | atom() | String.t(), namespace()) ::
    {:ok, entry()} | {:error, Foundation.Types.Error.t()}
  def lookup(identifier, namespace \\ :default)
  
  @doc """
  Find processes by capability.
  """
  @spec find_by_capability(atom(), namespace()) :: 
    {:ok, [entry()]} | {:error, Foundation.Types.Error.t()}
  def find_by_capability(capability, namespace \\ :default)
  
  @doc """
  Unregister a process.
  """
  @spec unregister(pid(), namespace()) :: 
    :ok | {:error, Foundation.Types.Error.t()}
  def unregister(pid, namespace \\ :default)
  
  @doc """
  List all registered processes in namespace.
  """
  @spec list_all(namespace()) :: 
    {:ok, [entry()]} | {:error, Foundation.Types.Error.t()}
  def list_all(namespace \\ :default)
end
```

### Foundation.Types.Error

**Canonical Error System**:

```elixir
@contract "foundation.types.error.v1"
defmodule Foundation.Types.Error do
  @moduledoc """
  Canonical error structure used across all system layers.
  Provides consistent error handling and debugging capabilities.
  """
  
  @typedoc "Error category for classification"
  @type category :: 
    :validation | :authentication | :authorization | :network | 
    :timeout | :not_found | :conflict | :internal | :external |
    :agent_management | :coordination | :optimization | :ml_processing
  
  @typedoc "Error severity level"
  @type severity :: :info | :warning | :error | :critical
  
  @typedoc "Error context for debugging"
  @type context :: %{
    module: module(),
    function: atom(),
    line: non_neg_integer(),
    request_id: String.t(),
    user_id: String.t(),
    trace_id: String.t(),
    additional: map()
  }
  
  @typedoc "Canonical error structure"
  @type t :: %__MODULE__{
    category: category(),
    code: atom(),
    message: String.t(),
    details: map(),
    severity: severity(),
    context: context(),
    caused_by: t() | nil,
    timestamp: DateTime.t()
  }
  
  defstruct [
    :category, :code, :message, :details, :severity, 
    :context, :caused_by, :timestamp
  ]
  
  @doc """
  Create a new error with automatic context capture.
  """
  @spec new(category(), atom(), String.t(), map()) :: t()
  def new(category, code, message, details \\ %{})
  
  @doc """
  Wrap an existing error with additional context.
  """
  @spec wrap(t(), category(), atom(), String.t()) :: t()
  def wrap(caused_by, category, code, message)
  
  @doc """
  Convert error to standardized map for serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(error)
  
  @doc """
  Extract error chain for debugging.
  """
  @spec error_chain(t()) :: [t()]
  def error_chain(error)
end
```

### Foundation.Telemetry

**Observability Interface**:

```elixir
@contract "foundation.telemetry.v1"
defmodule Foundation.Telemetry do
  @moduledoc """
  Unified telemetry system for metrics, events, and tracing.
  Provides foundation for observability across all layers.
  """
  
  @typedoc "Metric name as list of atoms"
  @type metric_name :: [atom()]
  
  @typedoc "Metric measurements"
  @type measurements :: %{atom() => number()}
  
  @typedoc "Event metadata"
  @type metadata :: %{atom() => term()}
  
  @doc """
  Execute telemetry event with measurements and metadata.
  """
  @spec execute(metric_name(), measurements(), metadata()) :: :ok
  def execute(name, measurements \\ %{}, metadata \\ %{})
  
  @doc """
  Start a span for distributed tracing.
  """
  @spec start_span(String.t(), metadata()) :: :ok
  def start_span(name, metadata \\ %{})
  
  @doc """
  End a span and record duration.
  """
  @spec end_span() :: :ok
  def end_span()
  
  @doc """
  Attach handler for telemetry events.
  """
  @spec attach(atom(), metric_name(), function()) :: :ok | {:error, term()}
  def attach(handler_id, event_name, handler_function)
end
```

### Foundation.Infrastructure

**Core Infrastructure Services**:

```elixir
@contract "foundation.infrastructure.v1"
defmodule Foundation.Infrastructure.CircuitBreaker do
  @typedoc "Circuit breaker name"
  @type name :: atom()
  
  @typedoc "Circuit breaker configuration"
  @type config :: %{
    failure_threshold: pos_integer(),
    recovery_timeout: pos_integer(),
    call_timeout: pos_integer()
  }
  
  @doc """
  Execute function with circuit breaker protection.
  """
  @spec execute(name(), (() -> term())) :: 
    {:ok, term()} | {:error, Foundation.Types.Error.t()}
  def execute(name, function)
  
  @doc """
  Get circuit breaker status.
  """
  @spec status(name()) :: :closed | :open | :half_open
  def status(name)
end
```

---

## FoundationJido Integration Layer Contracts

### FoundationJido.Agent

**Agent Integration Interface**:

```elixir
@contract "foundation_jido.agent.v1"
defmodule FoundationJido.Agent.RegistryAdapter do
  @moduledoc """
  Bridges Jido agents with Foundation.ProcessRegistry.
  Provides agent-aware registration while using Foundation services.
  """
  
  @typedoc "Jido agent configuration"
  @type agent_config :: %{
    name: String.t() | atom(),
    module: module(),
    capabilities: [atom()],
    restart_policy: :permanent | :temporary | :transient,
    initial_state: map(),
    options: keyword()
  }
  
  @typedoc "Agent registration result"
  @type registration_result :: %{
    pid: pid(),
    agent_id: String.t(),
    registry_entry: Foundation.ProcessRegistry.entry()
  }
  
  @doc """
  Register a Jido agent with Foundation registry.
  """
  @spec register_agent(agent_config()) :: 
    {:ok, registration_result()} | {:error, Foundation.Types.Error.t()}
  def register_agent(config)
  
  @doc """
  Start a registered agent.
  """
  @spec start_agent(String.t()) :: 
    {:ok, pid()} | {:error, Foundation.Types.Error.t()}
  def start_agent(agent_id)
  
  @doc """
  Stop an agent gracefully.
  """
  @spec stop_agent(String.t(), timeout()) :: 
    :ok | {:error, Foundation.Types.Error.t()}
  def stop_agent(agent_id, timeout \\ 5000)
  
  @doc """
  Find agents by capability using Foundation registry.
  """
  @spec find_agents_by_capability(atom()) :: 
    {:ok, [registration_result()]} | {:error, Foundation.Types.Error.t()}
  def find_agents_by_capability(capability)
end
```

### FoundationJido.Signal

**Signal Integration Interface**:

```elixir
@contract "foundation_jido.signal.v1"
defmodule FoundationJido.Signal.FoundationDispatch do
  @moduledoc """
  JidoSignal dispatch adapter using Foundation infrastructure.
  Provides enhanced reliability and observability for signal dispatching.
  """
  
  @typedoc "Enhanced dispatch configuration"
  @type dispatch_config :: %{
    type: :http | :pid | :webhook | :pubsub,
    target: String.t() | pid() | atom(),
    options: map(),
    circuit_breaker: atom() | nil,
    retry_policy: retry_policy() | nil
  }
  
  @typedoc "Retry policy configuration"
  @type retry_policy :: %{
    max_attempts: pos_integer(),
    base_delay: pos_integer(),
    max_delay: pos_integer(),
    backoff_type: :linear | :exponential
  }
  
  @typedoc "Dispatch result"
  @type dispatch_result :: %{
    success: boolean(),
    response: term(),
    duration_ms: non_neg_integer(),
    attempts: pos_integer()
  }
  
  @doc """
  Dispatch signal using Foundation infrastructure.
  """
  @spec dispatch(JidoSignal.Signal.t(), dispatch_config()) :: 
    {:ok, dispatch_result()} | {:error, Foundation.Types.Error.t()}
  def dispatch(signal, config)
  
  @doc """
  Get dispatch adapter status.
  """
  @spec adapter_status(atom()) :: 
    %{healthy: boolean(), last_success: DateTime.t(), error_rate: float()}
  def adapter_status(adapter_name)
end
```

### FoundationJido.Coordination

**Multi-Agent Coordination Interface**:

```elixir
@contract "foundation_jido.coordination.v1"
defmodule FoundationJido.Coordination.Orchestrator do
  @moduledoc """
  Multi-agent coordination and orchestration.
  Migrated from Foundation.MABEAM with Jido integration.
  """
  
  @typedoc "Agent specification for coordination"
  @type agent_spec :: %{
    agent_id: String.t(),
    capabilities: [atom()],
    resource_requirements: map(),
    coordination_preferences: map()
  }
  
  @typedoc "Coordination specification"
  @type coordination_spec :: %{
    coordination_type: :auction | :consensus | :negotiation | :market,
    objective: :minimize_cost | :maximize_performance | :balance_load,
    constraints: map(),
    timeout: pos_integer()
  }
  
  @typedoc "Coordination result"
  @type coordination_result :: %{
    success: boolean(),
    assignments: %{String.t() => map()},
    metrics: map(),
    duration_ms: non_neg_integer()
  }
  
  @doc """
  Coordinate multiple agents for task execution.
  """
  @spec coordinate([agent_spec()], coordination_spec()) :: 
    {:ok, coordination_result()} | {:error, Foundation.Types.Error.t()}
  def coordinate(agent_specs, coordination_spec)
  
  @doc """
  Run auction-based coordination.
  """
  @spec run_auction(map(), [agent_spec()]) :: 
    {:ok, coordination_result()} | {:error, Foundation.Types.Error.t()}
  def run_auction(auction_spec, participants)
end
```

---

## DSPEx Layer Contracts

### DSPEx.Jido Integration

**Program-Agent Bridge Interface**:

```elixir
@contract "dspex.jido.v1"
defmodule DSPEx.Jido.ProgramAgent do
  @moduledoc """
  Wraps DSPEx.Program as a Jido agent.
  Enables ML programs to participate in multi-agent coordination.
  """
  
  @typedoc "Program agent configuration"
  @type program_config :: %{
    program: DSPEx.Program.t(),
    optimization_enabled: boolean(),
    coordination_capabilities: [atom()],
    variable_space: DSPEx.Variable.Space.t() | nil
  }
  
  @typedoc "Program execution request"
  @type execution_request :: %{
    inputs: map(),
    options: keyword(),
    trace_id: String.t() | nil
  }
  
  @typedoc "Program execution result"
  @type execution_result :: %{
    outputs: map(),
    metadata: map(),
    performance_metrics: map(),
    variable_updates: map()
  }
  
  @doc """
  Start a DSPEx program as a Jido agent.
  """
  @spec start_program_agent(program_config()) :: 
    {:ok, pid()} | {:error, Foundation.Types.Error.t()}
  def start_program_agent(config)
  
  @doc """
  Execute program through agent interface.
  """
  @spec execute_program(pid(), execution_request()) :: 
    {:ok, execution_result()} | {:error, Foundation.Types.Error.t()}
  def execute_program(agent_pid, request)
  
  @doc """
  Optimize program using multi-agent coordination.
  """
  @spec optimize_program(pid(), map(), keyword()) :: 
    {:ok, DSPEx.Program.t()} | {:error, Foundation.Types.Error.t()}
  def optimize_program(agent_pid, training_data, options \\ [])
end
```

### DSPEx.Variable Integration

**Variable System Bridge**:

```elixir
@contract "dspex.variable.v1"
defmodule DSPEx.Variable.CoordinationBridge do
  @moduledoc """
  Bridge DSPEx variable system with multi-agent coordination.
  Enables variable-aware coordination across agent teams.
  """
  
  @typedoc "Variable coordination configuration"
  @type variable_coordination :: %{
    shared_variables: [DSPEx.Variable.t()],
    coordination_strategy: :independent | :shared | :competitive,
    optimization_target: atom(),
    constraints: map()
  }
  
  @typedoc "Coordination optimization result"
  @type optimization_result :: %{
    optimal_configuration: map(),
    performance_metrics: map(),
    convergence_data: map(),
    agent_contributions: map()
  }
  
  @doc """
  Coordinate variable optimization across multiple agents.
  """
  @spec coordinate_optimization([pid()], variable_coordination()) :: 
    {:ok, optimization_result()} | {:error, Foundation.Types.Error.t()}
  def coordinate_optimization(agent_pids, coordination_config)
  
  @doc """
  Extract variable space from program for coordination.
  """
  @spec extract_coordination_variables(DSPEx.Program.t()) :: 
    {:ok, [DSPEx.Variable.t()]} | {:error, Foundation.Types.Error.t()}
  def extract_coordination_variables(program)
end
```

---

## Version Compatibility Matrix

### API Versioning Strategy

| Layer | Current Version | Backward Compatible With | Breaking Changes |
|-------|----------------|-------------------------|------------------|
| Foundation.ProcessRegistry | v1.0 | v1.x | v2.0+ |
| Foundation.Types.Error | v1.0 | v1.x | v2.0+ |
| Foundation.Telemetry | v1.0 | v1.x | v2.0+ |
| FoundationJido.Agent | v1.0 | v1.x | v2.0+ |
| FoundationJido.Signal | v1.0 | v1.x | v2.0+ |
| FoundationJido.Coordination | v1.0 | v1.x | v2.0+ |
| DSPEx.Jido | v1.0 | v1.x | v2.0+ |

### Stability Guarantees

**@stable APIs**: Guaranteed backward compatibility within major version
- Function signatures will not change
- Return types will remain compatible
- Error codes will not be removed

**@experimental APIs**: May change in minor versions
- Marked with `@experimental` in documentation
- Subject to breaking changes based on feedback
- Will be stabilized or removed within 3 minor versions

**@deprecated APIs**: Will be removed in next major version
- Marked with `@deprecated` and migration path
- Will emit warnings when used
- Maintained for full major version cycle

### Breaking Change Policy

1. **Notice Period**: 6 months minimum before removal
2. **Migration Path**: Always provided for deprecated APIs
3. **Documentation**: Clear upgrade guides for breaking changes
4. **Testing**: Comprehensive tests for backward compatibility

---

## Error Code Registry

### Foundation Layer Error Codes

```elixir
# Foundation.ProcessRegistry errors
:registry_not_found        # Registry namespace doesn't exist
:process_not_found         # Process not in registry
:process_already_registered # Process already registered
:invalid_metadata          # Metadata validation failed
:registry_unavailable      # Registry service unavailable

# Foundation.Infrastructure errors  
:circuit_breaker_open      # Circuit breaker is open
:call_timeout              # Function call timed out
:resource_exhausted        # Resource limits exceeded
:service_unavailable       # Infrastructure service down
```

### FoundationJido Layer Error Codes

```elixir
# Agent integration errors
:agent_start_failed        # Failed to start Jido agent
:agent_registration_failed # Failed to register with Foundation
:agent_not_found          # Agent not found in registry
:capability_mismatch      # Agent capabilities don't match requirements

# Signal integration errors
:dispatch_failed          # Signal dispatch failed
:adapter_unavailable      # Dispatch adapter not available
:signal_invalid           # Signal format validation failed
:target_unreachable       # Signal target unreachable

# Coordination errors
:coordination_timeout     # Coordination process timed out
:insufficient_agents      # Not enough agents for coordination
:coordination_failed      # Coordination algorithm failed
:resource_conflict        # Resource allocation conflict
```

### DSPEx Layer Error Codes

```elixir
# Program-agent integration errors
:program_invalid          # DSPEx program validation failed
:execution_failed         # Program execution failed
:optimization_failed      # Program optimization failed
:variable_conflict        # Variable space conflict

# Variable coordination errors
:variable_space_invalid   # Variable space validation failed
:coordination_convergence_failed # Optimization didn't converge
:agent_communication_failed     # Inter-agent communication failed
```

---

## Contract Testing Strategy

### Contract Validation Tests

```elixir
# test/contracts/foundation_contract_test.exs
defmodule FoundationContractTest do
  use ExUnit.Case
  
  describe "Foundation.ProcessRegistry contract" do
    test "register/3 returns correct type" do
      metadata = %{type: :agent, capabilities: [:ml], name: "test"}
      assert {:ok, %{pid: pid, metadata: ^metadata}} = 
        Foundation.ProcessRegistry.register(self(), metadata)
      assert is_pid(pid)
    end
    
    test "lookup/2 handles not found correctly" do
      assert {:error, %Foundation.Types.Error{category: :not_found}} = 
        Foundation.ProcessRegistry.lookup(:nonexistent)
    end
  end
end
```

### Integration Contract Tests

```elixir
# test/contracts/integration_contract_test.exs
defmodule IntegrationContractTest do
  use ExUnit.Case
  
  describe "FoundationJido.Agent contract" do
    test "register_agent/1 integrates with Foundation registry" do
      config = %{name: "test_agent", capabilities: [:test]}
      
      assert {:ok, result} = FoundationJido.Agent.RegistryAdapter.register_agent(config)
      assert %{pid: pid, agent_id: id, registry_entry: entry} = result
      
      # Verify Foundation registry integration
      assert {:ok, ^entry} = Foundation.ProcessRegistry.lookup(pid)
    end
  end
end
```

### Contract Evolution Testing

```elixir
# test/contracts/evolution_test.exs
defmodule ContractEvolutionTest do
  use ExUnit.Case
  
  describe "backward compatibility" do
    test "v1.0 clients work with v1.1 server" do
      # Test using v1.0 API format
      legacy_request = %{type: :agent, name: "legacy"}
      
      # Should work with current implementation
      assert {:ok, _} = Foundation.ProcessRegistry.register(self(), legacy_request)
    end
  end
end
```

## Conclusion

These API contracts provide a solid foundation for the dependency-based architecture, ensuring:

1. **Clear Boundaries**: Well-defined interfaces between layers
2. **Stability**: Backward compatibility guarantees for stable APIs
3. **Evolution**: Safe evolution path for API improvements
4. **Testing**: Comprehensive contract validation
5. **Documentation**: Complete interface specifications

The contracts enable independent development of each layer while maintaining system coherence and reliability. They form the backbone of the Foundation OS architecture, supporting long-term maintainability and evolution.