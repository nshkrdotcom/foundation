# Foundation Development Roadmap

## Overview

This document provides a detailed, actionable development roadmap for implementing the Foundation Layer prototype. It breaks down the implementation into specific tasks, defines success criteria, and provides implementation guidelines that bridge the architectural vision with concrete code.

## Development Principles

### 1. Test-Driven Development
- **Red-Green-Refactor**: Write failing tests first, make them pass, then optimize
- **Comprehensive Coverage**: Target 95%+ line coverage with focus on edge cases
- **Integration Focus**: Test component interactions extensively
- **Property-Based Testing**: Use StreamData for behavioral guarantees

### 2. Supervision-First Architecture
- **No Orphan Processes**: Every process must have a supervisor
- **Graceful Degradation**: System continues operating when components fail
- **Resource Cleanup**: Proper cleanup on process termination
- **Health Monitoring**: Continuous health checks and alerts

### 3. Protocol-Based Design
- **Interface Contracts**: Define clear behavioral contracts
- **Loose Coupling**: Components interact through protocols, not implementations
- **Swappable Implementations**: Support different backends for different environments
- **Version Compatibility**: Maintain backward compatibility in protocol changes

## Phase 1: Foundation Infrastructure (Weeks 1-2)

### Week 1: Core Types and Basic Infrastructure

#### Task 1.1: Core Type Definitions
**Files to Create:**
- `lib/elixir_ml/foundation/types.ex`
- `lib/elixir_ml/foundation/types/agent.ex`
- `lib/elixir_ml/foundation/types/variable.ex`
- `lib/elixir_ml/foundation/types/action.ex`
- `lib/elixir_ml/foundation/types/event.ex`

**Implementation Strategy:**
```elixir
# Start with basic structs, add validation later
defmodule ElixirML.Foundation.Types.Agent do
  @enforce_keys [:id, :name, :behavior]
  defstruct [
    # Core fields from technical spec
    # Add validation functions
    # Add helper functions for common operations
  ]
  
  def new(name, behavior, opts \\ []) do
    # Constructor with validation
  end
  
  def validate(%__MODULE__{} = agent) do
    # Comprehensive validation
  end
end
```

**Tests to Write:**
- Struct creation and validation
- Field constraints and defaults
- Helper function behavior
- Error cases and edge conditions

**Success Criteria:**
- [ ] All type structs defined with proper enforcement
- [ ] Validation functions working correctly
- [ ] 100% test coverage on type definitions
- [ ] No compilation warnings

#### Task 1.2: Basic Agent Framework
**Files to Create:**
- `lib/elixir_ml/foundation/agent.ex`
- `lib/elixir_ml/foundation/agent_behaviour.ex`
- `lib/elixir_ml/foundation/agent_server.ex`

**Implementation Strategy:**
```elixir
defmodule ElixirML.Foundation.Agent do
  @moduledoc """
  Core agent implementation with GenServer backend.
  """
  
  use GenServer
  alias ElixirML.Foundation.Types.Agent, as: AgentType
  
  # Client API
  def start_link(agent_config) do
    GenServer.start_link(__MODULE__, agent_config)
  end
  
  def execute_action(pid, action_name, params) do
    GenServer.call(pid, {:execute_action, action_name, params})
  end
  
  # Server callbacks
  def init(config) do
    # Initialize agent state
    # Call behavior init
    # Set up monitoring
  end
  
  def handle_call({:execute_action, action_name, params}, from, state) do
    # Validate action exists
    # Check capabilities
    # Execute action
    # Update state
  end
end
```

**Tests to Write:**
- Agent lifecycle (start, stop, crash recovery)
- Action execution with various scenarios
- State management and persistence
- Capability checking and enforcement

**Success Criteria:**
- [ ] Basic agent can start and execute simple actions
- [ ] Proper GenServer implementation with supervision
- [ ] Error handling and recovery working
- [ ] 95%+ test coverage

#### Task 1.3: Application and Supervision Tree
**Files to Create:**
- `lib/elixir_ml/foundation/application.ex`
- `lib/elixir_ml/foundation/supervisor.ex`
- `lib/elixir_ml/foundation/registry.ex`

**Implementation Strategy:**
```elixir
defmodule ElixirML.Foundation.Application do
  use Application
  
  def start(_type, _args) do
    children = [
      # Registry for process discovery
      {Registry, keys: :unique, name: ElixirML.Foundation.Registry},
      
      # Main supervisor
      ElixirML.Foundation.Supervisor,
      
      # Core services
      ElixirML.Foundation.EventBus,
      ElixirML.Foundation.ResourceManager
    ]
    
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

**Tests to Write:**
- Application startup and shutdown
- Supervisor restart strategies
- Process registration and discovery
- Service availability

**Success Criteria:**
- [ ] Application starts cleanly
- [ ] All core services available
- [ ] Proper supervisor hierarchies
- [ ] Clean shutdown handling

### Week 2: Communication and Event System

#### Task 2.1: Event Bus Implementation
**Files to Create:**
- `lib/elixir_ml/foundation/event_bus.ex`
- `lib/elixir_ml/foundation/event_store.ex`
- `lib/elixir_ml/foundation/cloud_events.ex`

**Implementation Strategy:**
```elixir
defmodule ElixirML.Foundation.EventBus do
  use GenServer
  
  # Topic-based publish/subscribe
  def subscribe(topic_pattern) do
    GenServer.call(__MODULE__, {:subscribe, topic_pattern, self()})
  end
  
  def publish(event) do
    GenServer.cast(__MODULE__, {:publish, event})
  end
  
  # CloudEvents compatibility
  def publish_cloud_event(source, type, data, opts \\ []) do
    event = ElixirML.Foundation.CloudEvents.new(source, type, data, opts)
    publish(event)
  end
end
```

**Tests to Write:**
- Topic subscription and unsubscription
- Event publishing and delivery
- CloudEvents format compliance
- Dead letter queue handling
- Performance under load

**Success Criteria:**
- [ ] Reliable event delivery
- [ ] CloudEvents v1.0.2 compliance
- [ ] Topic-based routing working
- [ ] Performance targets met (10k events/sec)

#### Task 2.2: Signal System for Sensors
**Files to Create:**
- `lib/elixir_ml/foundation/signal_router.ex`
- `lib/elixir_ml/foundation/signal_processor.ex`

**Implementation Strategy:**
```elixir
defmodule ElixirML.Foundation.SignalRouter do
  @moduledoc """
  Routes sensor signals to interested agents.
  """
  
  def route_signal(signal) do
    # Determine interested agents
    # Convert signal to events
    # Emit to event bus
  end
  
  def register_signal_handler(agent_id, signal_pattern, handler) do
    # Register agent interest in signal types
  end
end
```

**Success Criteria:**
- [ ] Signals properly routed to interested agents
- [ ] Signal-to-event conversion working
- [ ] Pattern matching for signal routing
- [ ] Integration with event bus

## Phase 2: Resource Management (Weeks 3-4)

### Week 3: Quota and Rate Limiting

#### Task 3.1: Resource Type System
**Files to Create:**
- `lib/elixir_ml/foundation/resources/types.ex`
- `lib/elixir_ml/foundation/resources/quota_manager.ex`
- `lib/elixir_ml/foundation/resources/rate_limiter.ex`

**Implementation Strategy:**
```elixir
defmodule ElixirML.Foundation.Resources.QuotaManager do
  use GenServer
  
  # Token bucket algorithm for rate limiting
  def check_quota(resource, agent_id, amount) do
    GenServer.call(__MODULE__, {:check_quota, resource, agent_id, amount})
  end
  
  def consume_quota(resource, agent_id, amount) do
    GenServer.call(__MODULE__, {:consume, resource, agent_id, amount})
  end
  
  # Handle token replenishment
  def handle_info(:replenish_tokens, state) do
    # Replenish tokens for renewable resources
    # Schedule next replenishment
  end
end
```

**Tests to Write:**
- Token bucket behavior
- Quota enforcement
- Resource replenishment
- Multi-agent quota isolation
- Edge cases (zero quotas, overflow)

**Success Criteria:**
- [ ] Accurate quota tracking
- [ ] Rate limiting enforcement
- [ ] Token replenishment working
- [ ] Sub-millisecond quota checks

#### Task 3.2: Circuit Breaker Implementation
**Files to Create:**
- `lib/elixir_ml/foundation/resources/circuit_breaker.ex`
- `lib/elixir_ml/foundation/resources/health_monitor.ex`

**Implementation Strategy:**
```elixir
defmodule ElixirML.Foundation.Resources.CircuitBreaker do
  use GenServer
  
  # States: closed, open, half_open
  def execute(name, fun, timeout \\ 5000) do
    case get_state(name) do
      :closed -> execute_and_monitor(name, fun, timeout)
      :open -> {:error, :circuit_open}
      :half_open -> execute_probe(name, fun, timeout)
    end
  end
  
  defp execute_and_monitor(name, fun, timeout) do
    # Execute with monitoring
    # Update failure counts
    # Transition state if needed
  end
end
```

**Success Criteria:**
- [ ] Circuit breaker state transitions
- [ ] Failure threshold detection
- [ ] Automatic recovery testing
- [ ] Integration with resource management

### Week 4: Cost Tracking and Resource Pools

#### Task 4.1: Cost Tracking System
**Files to Create:**
- `lib/elixir_ml/foundation/resources/cost_tracker.ex`
- `lib/elixir_ml/foundation/resources/budget_manager.ex`

**Success Criteria:**
- [ ] Accurate cost calculation
- [ ] Budget enforcement
- [ ] Cost reporting and analytics
- [ ] Integration with quota system

#### Task 4.2: Resource Pool Management
**Files to Create:**
- `lib/elixir_ml/foundation/resources/pool_manager.ex`
- `lib/elixir_ml/foundation/resources/priority_scheduler.ex`

**Success Criteria:**
- [ ] Efficient resource pooling
- [ ] Priority-based allocation
- [ ] Pool health monitoring
- [ ] Dynamic pool resizing

## Phase 3: Skills and Sensors (Weeks 5-6)

### Week 5: Skills System Implementation

#### Task 5.1: Skill Framework
**Files to Create:**
- `lib/elixir_ml/foundation/skills/skill.ex`
- `lib/elixir_ml/foundation/skills/registry.ex`
- `lib/elixir_ml/foundation/skills/loader.ex`

**Implementation Strategy:**
```elixir
defmodule ElixirML.Foundation.Skills.Registry do
  use GenServer
  
  def register_skill(skill_module, config) do
    # Validate skill implementation
    # Check dependencies
    # Register in registry
  end
  
  def load_skill(agent_id, skill_id, config \\ %{}) do
    # Get skill from registry
    # Initialize skill state
    # Attach to agent
    # Wire up routes and actions
  end
end
```

**Tests to Write:**
- Skill registration and validation
- Dynamic skill loading/unloading
- Dependency resolution
- Route compilation and routing
- Error handling for skill failures

**Success Criteria:**
- [ ] Dynamic skill loading working
- [ ] Skill dependency resolution
- [ ] Route-based request handling
- [ ] Skill state isolation

#### Task 5.2: Example Skills Implementation
**Files to Create:**
- `lib/elixir_ml/foundation/skills/chat_skill.ex`
- `lib/elixir_ml/foundation/skills/database_skill.ex`
- `lib/elixir_ml/foundation/skills/web_skill.ex`

**Success Criteria:**
- [ ] Working chat skill with conversation management
- [ ] Database skill with query capabilities
- [ ] Web skill with HTTP client functionality
- [ ] Integration tests for all skills

### Week 6: Sensors Framework

#### Task 6.1: Sensor Base System
**Files to Create:**
- `lib/elixir_ml/foundation/sensors/sensor.ex`
- `lib/elixir_ml/foundation/sensors/manager.ex`
- `lib/elixir_ml/foundation/sensors/supervisor.ex`

**Implementation Strategy:**
```elixir
defmodule ElixirML.Foundation.Sensors.Manager do
  use GenServer
  
  def register_sensor(sensor_module, config) do
    # Validate sensor implementation
    # Initialize sensor
    # Start under supervision
    # Begin detection loop
  end
  
  def handle_info(:detection_cycle, state) do
    # Run detection on all sensors
    # Process generated signals
    # Schedule next cycle
  end
end
```

**Success Criteria:**
- [ ] Sensor registration and lifecycle
- [ ] Signal generation and routing
- [ ] Configurable detection intervals
- [ ] Error handling and recovery

#### Task 6.2: Built-in Sensors
**Files to Create:**
- `lib/elixir_ml/foundation/sensors/cron_sensor.ex`
- `lib/elixir_ml/foundation/sensors/heartbeat_sensor.ex`
- `lib/elixir_ml/foundation/sensors/file_watcher_sensor.ex`

**Success Criteria:**
- [ ] Cron sensor with cron expression parsing
- [ ] Heartbeat sensor with timeout detection
- [ ] File watcher with file system events
- [ ] All sensors generating proper signals

## Phase 4: Directives and Enhanced Actions (Weeks 7-8)

### Week 7: Directives System

#### Task 7.1: Directive Processing
**Files to Create:**
- `lib/elixir_ml/foundation/directives/processor.ex`
- `lib/elixir_ml/foundation/directives/validator.ex`
- `lib/elixir_ml/foundation/directives/audit.ex`

**Success Criteria:**
- [ ] Safe directive validation and execution
- [ ] Rollback capabilities for failed directives
- [ ] Complete audit trail generation
- [ ] Directive chain execution

#### Task 7.2: Directive Types Implementation
**Files to Create:**
- `lib/elixir_ml/foundation/directives/agent.ex`
- `lib/elixir_ml/foundation/directives/server.ex`
- `lib/elixir_ml/foundation/directives/chain.ex`

**Success Criteria:**
- [ ] Agent state modification directives
- [ ] Server control directives
- [ ] Transactional directive chains
- [ ] Error handling and recovery

### Week 8: Enhanced Actions

#### Task 8.1: Action Framework Enhancement
**Files to Create:**
- `lib/elixir_ml/foundation/actions/enhanced.ex`
- `lib/elixir_ml/foundation/actions/runner.ex`
- `lib/elixir_ml/foundation/actions/middleware.ex`

**Success Criteria:**
- [ ] Schema-based parameter validation
- [ ] Workflow instruction execution
- [ ] Middleware pipeline processing
- [ ] Retry and timeout handling

#### Task 8.2: Actions as Tools
**Files to Create:**
- `lib/elixir_ml/foundation/actions/tools.ex`
- `lib/elixir_ml/foundation/actions/catalog.ex`
- `lib/elixir_ml/foundation/actions/workflows.ex`

**Success Criteria:**
- [ ] JSON Schema generation for tools
- [ ] Tool catalog management
- [ ] LLM function calling integration
- [ ] Complex workflow execution

## Phase 5: Native DSPy Signatures (Weeks 9-10)

### Week 9: Signature Syntax Implementation

#### Task 9.1: Macro System
**Files to Create:**
- `lib/elixir_ml/foundation/signature.ex`
- `lib/elixir_ml/foundation/signature/dsl.ex`
- `lib/elixir_ml/foundation/signature/compiler.ex`

**Implementation Strategy:**
```elixir
defmodule ElixirML.Foundation.Signature.DSL do
  defmacro signature(name, do: block) do
    # Parse signature definition
    # Extract input/output specifications
    # Generate compile-time metadata
  end
  
  defmacro input(spec) do
    # Parse input specification
    # Extract type and constraints
    # Add to signature metadata
  end
  
  defmacro output(spec) do
    # Parse output specification
    # Generate validation code
  end
end
```

**Success Criteria:**
- [ ] Python-like syntax parsing
- [ ] Type specification extraction
- [ ] Compile-time validation generation
- [ ] Runtime type checking

#### Task 9.2: Type System Implementation
**Files to Create:**
- `lib/elixir_ml/foundation/signature/types.ex`
- `lib/elixir_ml/foundation/signature/validators.ex`
- `lib/elixir_ml/foundation/signature/converters.ex`

**Success Criteria:**
- [ ] ML-specific type support
- [ ] Container type handling (List, Dict, Optional)
- [ ] Type conversion and validation
- [ ] Compile-time optimization

### Week 10: Integration and Optimization

#### Task 10.1: Signature Compilation
**Files to Create:**
- `lib/elixir_ml/foundation/signature/optimizer.ex`
- `lib/elixir_ml/foundation/signature/schema_generator.ex`

**Success Criteria:**
- [ ] Optimized validation function generation
- [ ] Schema caching for performance
- [ ] Field accessor optimization
- [ ] Integration with existing systems

#### Task 10.2: DSPy Integration Examples
**Files to Create:**
- `examples/signature_examples.ex`
- `examples/dspy_integration.ex`

**Success Criteria:**
- [ ] Working signature examples
- [ ] DSPy compatibility demonstration
- [ ] Performance benchmarks
- [ ] Documentation and tutorials

## Phase 6: Integration Testing and Documentation (Week 11)

### Week 11: End-to-End Integration

#### Task 11.1: Integration Test Suite
**Files to Create:**
- `test/integration/multi_agent_test.exs`
- `test/integration/skills_integration_test.exs`
- `test/integration/resource_management_test.exs`

**Test Scenarios:**
- Multi-agent coordination workflows
- Skill loading and interaction across agents
- Resource exhaustion and recovery
- Signal propagation and action execution
- State persistence and recovery

**Success Criteria:**
- [ ] All integration tests passing
- [ ] Performance targets met
- [ ] Resource cleanup verified
- [ ] Error recovery demonstrated

#### Task 11.2: Performance Testing
**Files to Create:**
- `test/performance/load_test.exs`
- `test/performance/stress_test.exs`
- `test/performance/benchmark.exs`

**Performance Targets:**
- 1000+ active agents
- 10,000+ events/second
- <100ms message latency
- <50MB memory per agent

**Success Criteria:**
- [ ] Performance targets achieved
- [ ] Stress test scenarios passed
- [ ] Memory usage within limits
- [ ] Latency requirements met

#### Task 11.3: Documentation and Examples
**Files to Create:**
- `docs/getting_started.md`
- `docs/architecture_guide.md`
- `docs/api_reference.md`
- `examples/complete_workflow.ex`

**Success Criteria:**
- [ ] Complete API documentation
- [ ] Architecture guides written
- [ ] Working examples provided
- [ ] Tutorial walkthroughs created

## Success Metrics and Quality Gates

### Code Quality Requirements
- **Test Coverage**: Minimum 95% line coverage
- **Documentation**: All public APIs documented
- **Performance**: All targets met under load
- **Security**: Capability checks and input validation

### Delivery Requirements
- **No Breaking Changes**: Backward compatibility maintained
- **Clean Builds**: No compilation warnings or errors
- **Passing Tests**: All tests must pass before commit
- **Code Review**: All changes reviewed and approved

### Production Readiness
- **Supervision**: All processes properly supervised
- **Monitoring**: Health checks and metrics available
- **Error Handling**: Graceful error recovery
- **Resource Management**: Proper cleanup and limits

## Risk Mitigation Strategies

### Technical Risks
1. **Integration Complexity**: Incremental integration with comprehensive testing
2. **Performance Issues**: Early performance testing and optimization
3. **Memory Leaks**: Comprehensive resource cleanup testing
4. **Race Conditions**: Careful concurrency design and testing

### Schedule Risks
1. **Scope Creep**: Strict adherence to phase boundaries
2. **Dependency Delays**: Parallel development where possible
3. **Testing Bottlenecks**: Test-driven development approach
4. **Documentation Lag**: Documentation written with implementation

This roadmap provides the detailed guidance needed to implement the complete Foundation Layer prototype according to the unified vision.