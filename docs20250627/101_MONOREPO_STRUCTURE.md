# Foundation OS Monorepo Structure
**Version 1.0 - Detailed Implementation Layout**  
**Date: June 27, 2025**

## Executive Summary

This document provides the comprehensive monorepo structure for the Foundation OS, detailing how to integrate Foundation, Jido, MABEAM, and DSPEx into a unified, world-class multi-agent platform. The structure prioritizes clear boundaries, optimal dependencies, and maximum testability while maintaining the flexibility for incremental development.

## Core Design Principles

### 1. Dependency-Based Architecture
- **Single OTP Application**: All components exist within one cohesive application
- **Hex Dependencies**: Jido libraries used as standard hex dependencies, not copied
- **Integration Layers**: Clean integration modules bridge systems without modification
- **Boundary Enforcement**: Use of Elixir's `Boundary` library to enforce architectural constraints

### 2. Integration Strategy
- **Extension Points**: Use Jido's designed extension mechanisms (skills, sensors, signals)
- **Foundation Enhancement**: Foundation gains agent-aware capabilities through optional modules
- **Backwards Compatibility**: All existing APIs remain functional
- **Canonical Error System**: Single `Foundation.Types.Error` across all components

### 3. Test-Driven Structure
- **Comprehensive Coverage**: Full test suite across all integration points
- **Isolated Testing**: Each tier can be tested independently
- **Integration Testing**: End-to-end testing of complete workflows
- **Performance Testing**: Benchmarks for agent coordination and optimization

## Detailed Directory Structure

```
foundation/
├── lib/
│   ├── foundation_os.ex                    # Main application module
│   ├── foundation_os/
│   │   └── application.ex                  # OTP application supervisor
│   │
│   ├── foundation/                         # Tier 1: BEAM Kernel
│   │   ├── application.ex                  # Foundation services supervisor
│   │   ├── boundary.ex                     # Boundary definitions
│   │   │
│   │   ├── process_registry/               # Universal process management
│   │   │   ├── registry.ex
│   │   │   ├── backend.ex
│   │   │   └── backends/
│   │   │       ├── ets.ex
│   │   │       └── horde.ex                # FUTURE: distributed registry
│   │   │
│   │   ├── infrastructure/                 # Core BEAM services
│   │   │   ├── circuit_breaker.ex
│   │   │   ├── rate_limiter.ex
│   │   │   ├── connection_manager.ex
│   │   │   └── supervisor.ex
│   │   │
│   │   ├── services/                       # Foundation services
│   │   │   ├── config_server.ex
│   │   │   ├── telemetry_service.ex
│   │   │   ├── event_store.ex
│   │   │   └── supervisor.ex
│   │   │
│   │   ├── telemetry/                      # Observability platform
│   │   │   ├── metrics.ex
│   │   │   ├── events.ex
│   │   │   ├── reporter.ex
│   │   │   └── collectors/
│   │   │       ├── agent_collector.ex
│   │   │       └── coordination_collector.ex
│   │   │
│   │   ├── types/                          # Foundation data types
│   │   │   ├── config.ex
│   │   │   ├── event.ex
│   │   │   ├── error.ex                    # Canonical error system
│   │   │   └── agent_info.ex
│   │   │
│   │   └── contracts/                      # Service contracts
│   │       ├── configurable.ex
│   │       ├── observable.ex
│   │       └── manageable.ex
│   │
│   ├── foundation_jido/                   # Tier 2: Integration Layer
│   │   ├── application.ex                 # Integration supervisor
│   │   ├── boundary.ex                    # Integration boundary definitions
│   │   │
│   │   ├── agent/                         # Agent integration
│   │   │   ├── registry_adapter.ex        # Bridge Jido agents to Foundation.ProcessRegistry
│   │   │   ├── telemetry_integration.ex   # Agent telemetry -> Foundation.Telemetry
│   │   │   ├── error_bridge.ex            # Standardize on Foundation.Types.Error
│   │   │   └── lifecycle_manager.ex       # Enhanced agent lifecycle with Foundation services
│   │   │
│   │   ├── signal/                        # Signal integration
│   │   │   ├── foundation_dispatch.ex     # JidoSignal adapter using Foundation services
│   │   │   ├── event_bridge.ex            # JidoSignal.Signal -> Foundation.Event conversion
│   │   │   ├── infrastructure_adapters.ex # Circuit breaker integration for HTTP adapters
│   │   │   └── telemetry_middleware.ex    # Signal telemetry -> Foundation.Telemetry
│   │   │
│   │   ├── action/                        # Action integration
│   │   │   ├── foundation_actions.ex      # Actions that use Foundation services
│   │   │   ├── error_standardization.ex   # JidoAction errors -> Foundation.Types.Error
│   │   │   ├── telemetry_integration.ex   # Action telemetry -> Foundation.Telemetry
│   │   │   └── infrastructure_actions.ex  # Actions for Foundation service management
│   │   │
│   │   └── coordination/                  # Multi-agent coordination (replaces foundation.mabeam)
│   │       ├── auction.ex                 # Economic auction protocols
│   │       ├── market.ex                  # Marketplace mechanisms
│   │       ├── consensus.ex               # Consensus algorithms
│   │       ├── negotiation.ex             # Agent negotiation protocols
│   │       └── orchestrator.ex            # Multi-agent orchestration
│   │
│   └── dspex/                           # Tier 3: ML Intelligence
│       ├── application.ex               # DSPEx supervisor
│       ├── boundary.ex                  # DSPEx boundary definitions
│       │
│       ├── program.ex                   # Core DSPEx program
│       ├── predict.ex                   # Prediction interface
│       ├── signature.ex                 # Program signatures
│       │
│       ├── teleprompter/                # Optimization algorithms
│       │   ├── simba.ex
│       │   ├── beacon.ex
│       │   ├── bootstrap_fewshot.ex
│       │   ├── multi_agent.ex           # Multi-agent teleprompters
│       │   └── variable_aware.ex        # Variable-aware optimization
│       │
│       ├── variable/                    # DSPEx variable system
│       │   ├── ml_types.ex
│       │   ├── space.ex
│       │   ├── jido_integration.ex      # Bridge to Jido coordination
│       │   └── optimization.ex
│       │
│       ├── schema/                      # ML data validation
│       │   ├── behaviour.ex
│       │   ├── compiler.ex
│       │   ├── definition.ex
│       │   ├── dsl.ex
│       │   ├── runtime.ex
│       │   ├── types.ex
│       │   └── validation_error.ex
│       │
│       ├── jido/                        # DSPEx-Jido integration
│       │   ├── program_agent.ex         # DSPEx program as Jido agent
│       │   ├── teleprompter_actions.ex  # Optimization as Jido actions
│       │   ├── ml_signals.ex            # ML-specific signals
│       │   └── coordination_bridge.ex   # DSPEx coordination with agents
│       │
│       ├── client.ex                    # LLM client
│       ├── adapter.ex                   # Response adapters
│       └── util.ex                      # DSPEx utilities
│
├── config/                              # Configuration
│   ├── config.exs                       # Base configuration
│   ├── dev.exs                          # Development config
│   ├── test.exs                         # Test configuration
│   └── prod.exs                         # Production config
│
├── test/                                # Comprehensive test suite
│   ├── foundation/                      # Foundation tests
│   │   ├── process_registry_test.exs
│   │   ├── infrastructure_test.exs
│   │   ├── services_test.exs
│   │   ├── types_test.exs
│   │   └── integration_test.exs
│   │
│   ├── foundation_jido/                 # Integration layer tests
│   │   ├── agent/
│   │   │   ├── registry_adapter_test.exs
│   │   │   ├── telemetry_integration_test.exs
│   │   │   ├── error_bridge_test.exs
│   │   │   └── lifecycle_manager_test.exs
│   │   ├── signal/
│   │   │   ├── foundation_dispatch_test.exs
│   │   │   ├── event_bridge_test.exs
│   │   │   └── infrastructure_adapters_test.exs
│   │   ├── action/
│   │   │   ├── foundation_actions_test.exs
│   │   │   └── error_standardization_test.exs
│   │   ├── coordination/
│   │   │   ├── auction_test.exs
│   │   │   ├── market_test.exs
│   │   │   └── orchestrator_test.exs
│   │   └── integration_test.exs
│   │
│   ├── dspex/                          # DSPEx tests
│   │   ├── program_test.exs
│   │   ├── teleprompter_test.exs
│   │   ├── variable_test.exs
│   │   ├── schema_test.exs
│   │   └── jido_integration_test.exs
│   │
│   ├── integration/                    # End-to-end integration tests
│   │   ├── multi_agent_workflow_test.exs
│   │   ├── jido_foundation_test.exs
│   │   ├── dspex_coordination_test.exs
│   │   ├── performance_test.exs
│   │   └── fault_tolerance_test.exs
│   │
│   └── support/                        # Test support
│       ├── test_case.ex
│       ├── foundation_helpers.ex
│       ├── jido_helpers.ex
│       └── dspex_helpers.ex
│
├── docs/                               # Documentation
│   ├── architecture/                   # Architecture documentation
│   ├── guides/                         # User guides
│   ├── api/                           # API documentation
│   └── examples/                       # Example applications
│
├── mix.exs                             # Mix project configuration
├── mix.lock                            # Dependency lock file
├── README.md                           # Project README
└── .boundary.exs                       # Boundary configuration
```

## Boundary Configuration

Using the `Boundary` library to enforce architectural constraints:

```elixir
# .boundary.exs
[
  %{
    name: :foundation,
    definition: Foundation,
    deps: [],
    exports: [
      Foundation.ProcessRegistry,
      Foundation.Infrastructure,
      Foundation.Services,
      Foundation.Telemetry,
      Foundation.Types.Error
    ]
  },
  %{
    name: :foundation_jido,
    definition: FoundationJido,
    deps: [:foundation],
    exports: [
      FoundationJido.Agent,
      FoundationJido.Signal,
      FoundationJido.Action,
      FoundationJido.Coordination
    ],
    check: [
      # Ensure we only use Foundation services, not internal Jido details
      {FoundationJido, :invalid_external_dep_call}
    ]
  },
  %{
    name: :dspex,
    definition: DSPEx,
    deps: [:foundation, :foundation_jido],
    exports: [
      DSPEx.Program,
      DSPEx.Predict,
      DSPEx.Teleprompter,
      DSPEx.Schema,
      DSPEx.Variable
    ],
    check: [
      # Ensure DSPEx only uses integration layer, not direct Jido calls
      {DSPEx, :invalid_direct_jido_call}
    ]
  }
]
```

## Dependency Management

### External Dependencies

```elixir
# mix.exs dependencies
defp deps do
  [
    # Core Elixir dependencies
    {:nimble_options, "~> 1.0"},
    {:jason, "~> 1.4"},
    {:telemetry, "~> 1.2"},
    
    # Jido ecosystem (primary agent framework dependencies)
    {:jido, "~> 0.1.0"},              # Core agent framework
    {:jido_action, "~> 0.1.0"},       # Action execution system
    {:jido_signal, "~> 0.1.0"},       # Signal/messaging system
    
    # OTP and supervision
    {:horde, "~> 0.8.7"},              # Distributed process registry (FUTURE)
    {:libcluster, "~> 3.3"},           # Cluster management (FUTURE)
    
    # HTTP and networking
    {:req, "~> 0.4.0"},                # HTTP client
    {:bandit, "~> 1.0"},               # HTTP server (if needed)
    
    # Serialization and validation
    {:msgpax, "~> 2.3"},               # MessagePack serialization
    {:norm, "~> 0.13"},                # Data validation
    
    # Testing and development
    {:ex_doc, "~> 0.31", only: :dev, runtime: false},
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
    {:boundary, "~> 0.10.0", runtime: false},
    {:stream_data, "~> 0.6", only: :test},
    
    # Benchmarking and profiling
    {:benchee, "~> 1.1", only: :dev},
    {:observer_cli, "~> 1.7", only: :dev}
  ]
end
```

### Internal Module Dependencies

```
Foundation (Tier 1)
├── No internal dependencies
└── Provides: ProcessRegistry, Infrastructure, Services, Telemetry, Types.Error

Jido* Libraries (External Hex Dependencies)
├── jido: Core agent framework
├── jido_action: Action execution system
└── jido_signal: Signal/messaging system

FoundationJido (Tier 2 - Integration Layer)
├── Depends on: Foundation, jido, jido_action, jido_signal
└── Provides: Agent integration, Signal integration, Coordination protocols

DSPEx (Tier 3 - ML Intelligence)
├── Depends on: Foundation, FoundationJido, jido, jido_action, jido_signal
└── Provides: Program, Predict, Teleprompter, Schema, Variable
```

## Application Supervision Tree

```elixir
# lib/foundation_os/application.ex
defmodule FoundationOS.Application do
  use Application
  
  def start(_type, _args) do
    children = [
      # Tier 1: Foundation BEAM kernel services
      Foundation.Application,
      
      # Tier 2: Integration layer (bridges Foundation with Jido)
      FoundationJido.Application,
      
      # Tier 3: Domain applications
      DSPEx.Application
    ]
    
    opts = [strategy: :one_for_one, name: FoundationOS.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

## Migration Strategy

### Phase 1: Dependency Integration
1. **Add Jido Dependencies**: Include `jido`, `jido_action`, `jido_signal` as hex dependencies
2. **Create Integration Layer**: Build `FoundationJido` integration modules
3. **Error System Standardization**: Refactor all error handling to use `Foundation.Types.Error`
4. **Boundary Setup**: Configure architectural boundaries for clean separation

### Phase 2: Coordination Layer Development  
1. **Move MABEAM Logic**: Migrate `foundation.mabeam` coordination protocols to `FoundationJido.Coordination`
2. **Agent Integration**: Build agent registry adapter using Foundation.ProcessRegistry
3. **Signal Integration**: Create Foundation-aware signal dispatchers
4. **Test Coverage**: Comprehensive testing of integration points

### Phase 3: DSPEx Enhancement
1. **Program-Agent Bridge**: Convert DSPEx programs to Jido agents
2. **ML Action Library**: Build DSPEx-specific Jido actions
3. **Coordination Integration**: Enable multi-agent teleprompters
4. **Schema Integration**: ML-native validation throughout the platform

## Testing Strategy

### Unit Testing
- **Component Isolation**: Each tier tested independently
- **Mock Integration**: Use mocks for dependencies between tiers
- **Property Testing**: Use StreamData for edge cases
- **Performance Testing**: Benchmarks for critical paths

### Integration Testing
- **Multi-Tier Workflows**: Test complete agent workflows
- **Fault Tolerance**: Simulate failures and recovery
- **Scalability**: Test with multiple agents and coordination
- **Real-World Scenarios**: End-to-end ML optimization workflows

### Continuous Integration
- **Boundary Checking**: Enforce architectural constraints
- **Performance Regression**: Detect performance degradation
- **Documentation**: Ensure docs stay current with code
- **Security Scanning**: Validate against security vulnerabilities

## Benefits of This Structure

### Development Benefits
- **Clear Boundaries**: Well-defined interfaces between Foundation, Integration Layer, and Domain Logic
- **Dependency Isolation**: Jido libraries remain independent while gaining Foundation services
- **Test Isolation**: Each layer can be tested independently with proper mocking
- **Modular Enhancement**: Easy to extend individual components without breaking dependencies
- **Extension Points**: Clean integration through adapters rather than code copying

### Runtime Benefits
- **Unified Supervision**: Single OTP application with coherent fault tolerance
- **Optimal Performance**: Direct function calls for Foundation services, clean interfaces for Jido
- **Simplified Deployment**: One application to build and deploy
- **Consistent Configuration**: Unified configuration management
- **Fault Tolerance**: OTP supervision benefits across all components

### Maintenance Benefits
- **Dependency Management**: Standard hex dependencies for Jido libraries
- **Version Control**: Independent versioning for Jido ecosystem
- **Code Reuse**: Jido libraries can be used in other projects
- **Architectural Purity**: Foundation remains domain-agnostic
- **Upgrade Path**: Can upgrade Jido libraries independently

### Strategic Benefits
- **Open Source Alignment**: Uses Jido libraries as intended by their creators
- **Community Benefits**: Improvements to Foundation benefit entire Elixir ecosystem
- **Technology Evolution**: Can adopt new Jido features without architectural changes
- **Integration Flexibility**: Clean integration patterns for other agent frameworks

This dependency-based architecture creates a world-class multi-agent platform that leverages the best of both Foundation's infrastructure and Jido's agent capabilities, while maintaining clean separation of concerns and enabling long-term evolution.