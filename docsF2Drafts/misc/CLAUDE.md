# Claude Code Helper for Foundation 2.0 Project

## Project Vision
Foundation 2.0 is evolving into the next-generation distributed BEAM framework - a comprehensive platform that combines enhanced core services, Partisan-powered distribution, deep BEAM primitives, and intelligent features. The goal is to create the definitive framework for building scalable, fault-tolerant distributed applications on the BEAM.

## Foundation 2.0 Architecture

### **Layer 1: Enhanced Core Services (Distributed + Intelligent)**
```
Foundation.Config 2.0      # Distributed configuration with consensus
Foundation.Events 2.0      # Cluster-wide event streaming with correlation  
Foundation.Telemetry 2.0   # Intelligent metrics with predictive analytics
Foundation.Error 2.0       # Distributed error correlation and learning
Foundation.ServiceRegistry 2.0  # Cross-cluster service mesh
Foundation.ProcessRegistry 2.0  # Distributed process coordination
```

### **Layer 2: BEAM Primitives (Partisan-Optimized)**
```
Foundation.BEAM.Distribution    # Partisan topology management (replaces libcluster)
Foundation.BEAM.Channels       # Multi-channel communication patterns
Foundation.BEAM.Processes      # Process ecosystems with distributed coordination
Foundation.BEAM.Messages       # Intelligent message passing optimization
Foundation.BEAM.Schedulers     # Cluster-aware scheduler coordination
Foundation.BEAM.Memory         # Distributed memory management
```

### **Layer 3: Distributed Coordination (Partisan-Native)**
```
Foundation.Distributed.Topology    # Dynamic topology management
Foundation.Distributed.Consensus   # Raft over Partisan channels
Foundation.Distributed.Context     # Request tracing across topologies
Foundation.Distributed.State       # CRDTs with Partisan broadcast
Foundation.Distributed.Discovery   # Multi-strategy node discovery
Foundation.Distributed.Routing     # Intelligent message routing
```

## Key Commands
- **Run tests**: `mix test`
- **Run specific test categories**: 
  - `mix test --only contract`
  - `mix test --only smoke` 
  - `mix test --only integration`
  - `mix test --only stress`
  - `mix test --only benchmark`
- **Check deps**: `mix deps.get`
- **Compile**: `mix compile`

## Test Structure
- `test/contract/` - Contract/behavior compliance tests
- `test/smoke/` - Basic system health tests
- `test/integration/` - Service interaction tests  
- `test/stress/` - Load and chaos testing
- `test/benchmark/` - Performance baselines
- `test/property/` - Property-based tests
- `test/unit/` - Unit tests

## Foundation 2.0 Implementation Plan

### **Phase 1: Enhanced Core Services (Weeks 1-2)**
**Objective**: Transform Foundation's solid 1.x services into distributed, intelligent systems while maintaining 100% backward compatibility.

**Week 1: Core Service Enhancement**
- [ ] **Foundation.Config 2.0** - Distributed configuration with consensus
  - Cluster-wide configuration synchronization
  - Conflict resolution mechanisms
  - Adaptive configuration learning
  - All Foundation 1.x APIs preserved
- [ ] **Foundation.Events 2.0** - Cluster-wide event streaming  
  - Distributed event emission across cluster
  - Intelligent event correlation
  - Predictive event routing
  - Pattern detection and anomaly detection
- [ ] **Foundation.Telemetry 2.0** - Intelligent metrics
  - Cluster metrics aggregation
  - Predictive monitoring
  - Anomaly detection
  - Optimization recommendations

**Week 2: Registry & Error Enhancement**
- [ ] **Foundation.ServiceRegistry 2.0** - Service mesh capabilities
  - Cross-cluster service discovery
  - Intelligent routing and load balancing
  - Health monitoring and failover
- [ ] **Foundation.ProcessRegistry 2.0** - Distributed coordination
  - Cluster-wide process registration
  - Distributed process lookup
  - Cross-node supervision
- [ ] **Foundation.Error 2.0** - Distributed error correlation
  - Error pattern learning
  - Cascade prediction
  - Proactive error detection

### **Phase 2: Partisan Integration (Weeks 3-5)**
**Objective**: Replace libcluster + Distributed Erlang with Partisan-powered distribution that scales to 1000+ nodes.

**Week 3: Partisan Foundation**
- [ ] **Foundation.BEAM.Distribution** - Partisan integration core
  - Replace Distributed Erlang with Partisan
  - Multiple overlay strategies (full-mesh, HyParView, client-server)
  - Dynamic topology switching
- [ ] **Foundation.BEAM.Channels** - Multi-channel communication
  - Separate channels for different traffic types
  - Eliminate head-of-line blocking
  - Intelligent channel allocation

**Week 4: Enhanced Discovery & Topology**
- [ ] **Foundation.Distributed.Discovery** - Multi-strategy node discovery
  - Kubernetes, Consul, DNS, static configurations
  - Failover between discovery mechanisms
  - Backward compatibility with libcluster
- [ ] **Foundation.Distributed.Topology** - Dynamic topology management
  - Automatic topology optimization based on cluster size
  - Performance-aware topology switching
  - Partition tolerance strategies

**Week 5: Context & Routing**
- [ ] **Foundation.Distributed.Context** - Global context propagation
  - Request tracing across network boundaries
  - Context flowing through async operations
  - Distributed debugging support
- [ ] **Foundation.Distributed.Routing** - Intelligent message routing
  - Best-path routing across topologies
  - Load-aware message distribution
  - Latency optimization

### **Phase 3: BEAM Primitives & Ecosystems (Weeks 6-8)**
**Objective**: Deep BEAM integration with process ecosystems and distributed patterns.

**Week 6: Process Ecosystems**
- [ ] **Foundation.BEAM.Processes** - Process ecosystems
  - Spawn coordinated process groups
  - Cross-node supervision trees
  - Process society patterns
- [ ] **Foundation.Ecosystems.Supervision** - Distributed supervision
  - Fault isolation across nodes
  - Restart strategies for distributed processes

**Week 7: Communication & Coordination**
- [ ] **Foundation.BEAM.Messages** - Intelligent messaging
  - Binary optimization for large data
  - Flow control and backpressure
  - Message pattern optimization
- [ ] **Foundation.Distributed.Coordination** - Distributed coordination primitives
  - Distributed locks and barriers
  - Leader election with topology awareness
  - Consensus algorithms

**Week 8: Advanced BEAM Features**
- [ ] **Foundation.BEAM.Schedulers** - Scheduler coordination
  - Cluster-aware workload distribution
  - Scheduler-aware operations
  - Reduction counting optimization
- [ ] **Foundation.BEAM.Memory** - Distributed memory management
  - Shared binary caches
  - Process heap optimization
  - Garbage collection coordination

### **Phase 4: Intelligent Infrastructure (Weeks 9-10)**
**Objective**: Self-managing, adaptive distributed systems with AI-powered optimization.

**Week 9: Adaptive Systems**
- [ ] **Foundation.Intelligence.AdaptiveTopology** - Self-optimizing networks
  - Learn from message patterns and latency
  - Automatic topology reconfiguration
  - Performance optimization
- [ ] **Foundation.Intelligence.PredictiveScaling** - Predictive node management
  - Workload prediction and scaling
  - Resource utilization optimization

**Week 10: Self-Healing & Evolution**
- [ ] **Foundation.Intelligence.FailurePrediction** - Proactive failure detection
  - Pattern recognition for failure prediction
  - Preventive measures and mitigation
- [ ] **Foundation.Intelligence.Healing** - Self-healing distributed systems
  - Automatic recovery from failures
  - System evolution based on load patterns

## Competitive Advantages

### **vs. Traditional BEAM Approaches**
- **libcluster + Distributed Erlang**: ~200 node limit, single TCP, head-of-line blocking
- **Foundation 2.0**: 1000+ nodes, multiple channels, intelligent routing

### **Key Differentiators**
1. **100% Backward Compatibility** - All Foundation 1.x APIs work unchanged
2. **Partisan-Powered Distribution** - Superior to Distributed Erlang scaling
3. **Intelligent Features** - AI-powered optimization and prediction
4. **Process Ecosystems** - Deep BEAM integration with coordinated process groups
5. **Self-Managing Infrastructure** - Adaptive, healing distributed systems

## Migration Path
```elixir
# Existing Foundation 1.x code - NO CHANGES REQUIRED
Foundation.Config.get([:ai, :provider])
Foundation.Events.new_event(:test, data)
Foundation.Telemetry.emit_counter([:requests], %{})

# New Foundation 2.0 features - OPTIONAL ENHANCEMENTS
Foundation.Config.set_cluster_wide([:feature], true)
Foundation.Events.emit_distributed(:event, data)
Foundation.Telemetry.enable_predictive_monitoring([:cpu])
Foundation.BEAM.Distribution.switch_topology(:full_mesh, :hyparview)
```

## Current Status
- Foundation 1.x stable with 25 passing tests
- Enhanced documentation architecture complete
- Ready to begin Phase 1: Enhanced Core Services implementation

## Success Metrics
- **Performance**: 3-5x faster cluster formation, 2-10x higher message throughput
- **Scalability**: Support for 1000+ nodes vs ~200 with traditional approaches
- **Reliability**: 99.9% uptime during network partitions
- **Compatibility**: 100% backward compatibility with existing Foundation APIs