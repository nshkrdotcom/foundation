# Foundation Fresh Start Implementation Plan

## Overview
Complete rewrite of Foundation/MABEAM architecture following PLAN_0001.md specifications. Start from scratch with clean separation, reference old code for domain knowledge only.

## Implementation Strategy

### Phase 1: Clean Foundation Infrastructure (Week 1)
**Goal**: Pure BEAM infrastructure with agent-aware capabilities

#### 1.1 Foundation.Application (Day 1)
- Fresh supervisor tree, zero MABEAM knowledge
- Clean startup phases: infrastructure → foundation_services → coordination → application
- Enhanced service management with agent metadata support

#### 1.2 Enhanced ProcessRegistry (Day 2)
- Distribution-ready process identification: `{namespace, node, id}`
- Agent metadata support: capabilities, health, resources
- Agent-specific lookup functions
- Future Horde integration points

#### 1.3 Coordination Primitives (Day 3)
- Consensus mechanisms (Raft-ready)
- Barrier synchronization
- Distributed locks
- Leader election
- All designed for multi-node from day 1

#### 1.4 Infrastructure Services (Day 4-5)
- Agent-aware circuit breakers
- Agent-specific rate limiting
- Resource management
- Enhanced telemetry with agent metrics

### Phase 2: Jido Integration Layer (Week 2)
**Goal**: Bridge between Foundation infrastructure and Jido agent runtime

#### 2.1 Core Integration (Day 1-2)
- Agent bridge: Jido agent → Foundation services
- Signal bridge: JidoSignal ↔ Foundation events
- Error bridge: Unified error conversion
- Telemetry bridge: Cross-layer observability

#### 2.2 Service Adapters (Day 3-5)
- ProcessRegistry adapter for Jido agents
- Infrastructure adapter (circuit breakers, rate limiting)
- Coordination adapter (consensus, barriers)
- Health monitoring integration

### Phase 3: MABEAM Reconstruction (Week 3-4)
**Goal**: Multi-agent coordination rebuilt on Jido framework

#### 3.1 Orchestration Layer (Day 1-3)
- Coordinator agent (Jido-based)
- Resource allocator agent
- Performance optimizer agent
- All coordination as Jido actions

#### 3.2 Economic Mechanisms (Day 4-7)
- Auctioneer agent
- Marketplace agent
- Pricing engine
- Auction/market actions

#### 3.3 Integration Testing (Day 8-10)
- Foundation ↔ Jido integration tests
- MABEAM coordination scenarios
- Performance validation
- Distribution readiness verification

## Migration Strategy

### Reference Code Approach
```bash
# Preserve old code as reference
mv lib/foundation lib/foundation_old
mv lib/mabeam lib/mabeam_old

# Fresh implementations
mkdir lib/foundation
mkdir lib/jido_foundation  
mkdir lib/mabeam
```

### Key Reference Points
- **Process Registry**: Registration/lookup patterns
- **Circuit Breaker**: Core logic patterns
- **Telemetry**: Event structures
- **MABEAM Types**: Data structures (without Foundation coupling)
- **Agent Logic**: Domain knowledge and coordination patterns

## Target Directory Structure
```
lib/
├── foundation/                    # Pure BEAM infrastructure
│   ├── application.ex            # Clean supervisor
│   ├── process_registry.ex       # Agent-aware registry
│   ├── infrastructure/           # Agent-aware services
│   ├── coordination/             # Distribution-ready primitives
│   ├── telemetry.ex             # Enhanced metrics
│   └── types/                   # Unified types
├── jido_foundation/              # Integration layer
│   ├── application.ex           # Integration supervisor
│   ├── agent_bridge.ex          # Jido → Foundation
│   ├── signal_bridge.ex         # Signal ↔ Event
│   ├── error_bridge.ex          # Error conversion
│   └── adapters/                # Service adapters
└── mabeam/                      # Multi-agent coordination
    ├── application.ex           # MABEAM supervisor
    ├── orchestration/           # Coordination agents
    ├── economic/                # Economic mechanisms
    ├── actions/                 # Jido actions
    └── agents/                  # MABEAM agents
```

## Success Criteria

### Technical Metrics
- **Clean Architecture**: Zero dependency violations
- **Distribution Ready**: All APIs support clustering
- **Performance**: 1000+ agents on single node
- **Test Coverage**: >95% across all layers

### Integration Quality
- **Unified Errors**: Single error system across layers
- **Seamless Bridging**: Transparent Jido ↔ Foundation integration
- **Agent-Centric**: All infrastructure services agent-aware
- **Production Ready**: Full observability and fault tolerance

## Benefits

1. **🚀 Speed**: No refactoring constraints
2. **🧹 Clean**: Zero technical debt from day 1
3. **📚 Learning**: Reference old code for domain knowledge
4. **🎯 Focus**: Single responsibility per module
5. **✅ Testing**: Independent layer testing
6. **🔄 Future-Proof**: Distribution-ready architecture

## Next Steps

1. Start with Foundation.Application - clean supervisor implementation
2. Implement enhanced ProcessRegistry with agent metadata
3. Add coordination primitives designed for distribution
4. Reference old code for patterns, implement with new architecture
5. Maintain WORKLOG.md with progress tracking

This approach delivers architectural benefits without cleanup overhead, resulting in cleaner code faster.