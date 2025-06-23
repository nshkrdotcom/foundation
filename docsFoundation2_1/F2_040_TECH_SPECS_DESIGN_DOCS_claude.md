# Foundation 2.0: Technical Specifications & Design Documents

## Document Set Overview

This document set provides the technical foundation for implementing Foundation 2.0 based on our synthesis of "Smart Facades on a Pragmatic Core" with intentionally leaky abstractions.

---

# 1. API Contract Specification

## Layer 1: Pragmatic Core APIs

### Configuration System
```elixir
# Mortal Mode (Zero Config)
config :foundation, cluster: true

# Apprentice Mode (Simple Config)
config :foundation, cluster: :kubernetes
config :foundation, cluster: :consul
config :foundation, cluster: :dns
config :foundation, cluster: [strategy: :gossip, secret: "my-secret"]

# Wizard Mode (Full libcluster passthrough)
config :libcluster, topologies: [...]  # Foundation detects and defers
```

### Core Supervision Contract
```elixir
# Foundation.Supervisor must provide these child processes when clustering enabled:
- {Cluster.Supervisor, resolved_topology}
- {Phoenix.PubSub, name: Foundation.PubSub, adapter: Phoenix.PubSub.PG2}
- {Horde.Registry, name: Foundation.ProcessRegistry, keys: :unique, members: :auto}
- {Horde.DynamicSupervisor, name: Foundation.DistributedSupervisor, members: :auto}
```

## Layer 2: Smart Facade APIs

### Process Management Facade
```elixir
# Primary API Contract
@spec start_singleton(module(), args :: list(), opts :: keyword()) ::
  {:ok, pid()} | {:error, term()}

@spec start_replicated(module(), args :: list(), opts :: keyword()) ::
  list({:ok, pid()} | {:error, term()})

@spec lookup_singleton(term()) :: {:ok, pid()} | :not_found

# Required Options
opts :: [
  name: term(),           # Registry key (optional)
  restart: :permanent | :temporary | :transient,
  timeout: pos_integer() | :infinity
]
```

### Service Discovery Facade
```elixir
# Primary API Contract
@spec register_service(name :: term(), pid(), capabilities :: list(), metadata :: map()) ::
  :ok | {:error, term()}

@spec discover_services(criteria :: keyword()) :: list(service_info())

@type service_info() :: %{
  name: term(),
  pid: pid(),
  node: atom(),
  capabilities: list(),
  metadata: map(),
  registered_at: integer()
}

# Discovery Criteria
criteria :: [
  name: term(),
  capabilities: list(),
  node: atom(),
  health_check: (service_info() -> boolean())
]
```

### Channel Communication Facade
```elixir
# Primary API Contract  
@spec broadcast(channel :: atom(), message :: term(), opts :: keyword()) :: :ok
@spec subscribe(channel :: atom(), handler :: pid()) :: :ok
@spec route_message(message :: term(), opts :: keyword()) :: :ok

# Standard Channels
@type channel() :: :control | :events | :telemetry | :data

# Routing Options
opts :: [
  channel: channel(),
  priority: :low | :normal | :high,
  compression: boolean(),
  timeout: pos_integer()
]
```

## Layer 3: Direct Tool Access

Foundation MUST provide these registered processes for direct access:
- `Foundation.PubSub` (Phoenix.PubSub process)
- `Foundation.ProcessRegistry` (Horde.Registry process)
- `Foundation.DistributedSupervisor` (Horde.DynamicSupervisor process)
- `Foundation.ClusterSupervisor` (Cluster.Supervisor process)

---

# 2. Architecture Decision Records (ADRs)

## ADR-001: Leaky Abstractions by Design

**Status**: Accepted  
**Date**: 2024-12-XX  
**Deciders**: Claude & Gemini Synthesis

### Context
We need to decide whether Foundation's facades should hide or expose the underlying tool implementations.

### Decision
We will implement **intentionally leaky abstractions** that celebrate rather than hide the underlying tools.

### Rationale
- **Debuggability**: Developers can understand what's happening under the hood
- **No Lock-in**: Easy to drop to tool level when needed
- **Learning Path**: Smooth progression from simple to advanced usage
- **Community Leverage**: Builds on existing knowledge rather than replacing it

### Implementation
- All facades are thin, stateless wrappers
- Facade source code clearly shows underlying tool calls
- Direct tool access is always available and documented
- Error messages reference both facade and underlying tool

## ADR-002: Three-Layer Configuration Model

**Status**: Accepted  
**Date**: 2024-12-XX

### Context
We need a configuration system that serves beginners and experts equally well.

### Decision
Implement Mortal/Apprentice/Wizard three-tier configuration system.

### Rationale
- **Progressive Disclosure**: Start simple, add complexity as needed
- **Migration Friendly**: Wizard mode preserves existing libcluster configs
- **Environment Appropriate**: Different complexity levels for different deployment scenarios

### Implementation
```elixir
# Mortal: Foundation controls everything
config :foundation, cluster: true

# Apprentice: Foundation translates high-level config  
config :foundation, cluster: :kubernetes

# Wizard: Foundation defers to existing libcluster config
config :libcluster, topologies: [...]
```

## ADR-003: Phoenix.PubSub for Application-Layer Channels

**Status**: Accepted  
**Date**: 2024-12-XX

### Context
Distributed Erlang has head-of-line blocking issues. We need application-layer channel separation.

### Decision
Use Phoenix.PubSub with standardized topic namespaces to create logical channels over Distributed Erlang.

### Rationale
- **Proven Solution**: Phoenix.PubSub is battle-tested for distributed messaging
- **Logical Separation**: Different message types use different topics
- **No Transport Changes**: Works over standard Distributed Erlang
- **Ecosystem Integration**: Leverages existing Phoenix.PubSub knowledge

### Implementation
```elixir
# Standard channels map to PubSub topics
:control -> "foundation:control"
:events -> "foundation:events"  
:telemetry -> "foundation:telemetry"
:data -> "foundation:data"
```

## ADR-004: Horde for Distributed Process Management

**Status**: Accepted  
**Date**: 2024-12-XX

### Context
We need distributed process registry and supervision capabilities.

### Decision
Use Horde as the single source of truth for distributed processes, with facades providing common patterns.

### Rationale
- **CRDT Foundation**: Horde's delta-CRDT approach handles network partitions well
- **OTP Compatibility**: Familiar APIs that match standard OTP patterns
- **Active Maintenance**: Well-maintained with good community support
- **Proven Patterns**: Existing successful deployments validate the approach

### Implementation
- Foundation.ProcessRegistry = Horde.Registry instance
- Foundation.DistributedSupervisor = Horde.DynamicSupervisor instance
- Facades provide common patterns (singleton, replicated, partitioned)

---

# 3. Testing Strategy & Requirements

## Testing Pyramid

### Unit Tests (60% of coverage)
```elixir
# Test each facade function in isolation
test "ProcessManager.start_singleton creates child and registers" do
  assert {:ok, pid} = Foundation.ProcessManager.start_singleton(TestWorker, [], name: :test)
  assert {:ok, ^pid} = Foundation.ProcessManager.lookup_singleton(:test)
  assert [{^pid, _}] = Horde.Registry.lookup(Foundation.ProcessRegistry, :test)
end

# Test configuration translation
test "ClusterConfig translates :kubernetes to libcluster topology" do
  topology = Foundation.ClusterConfig.translate_kubernetes_config(app_name: "test-app")
  assert topology[:strategy] == Cluster.Strategy.Kubernetes
  assert topology[:config][:kubernetes_selector] == "app=test-app"
end
```

### Integration Tests (30% of coverage)
```elixir
# Multi-node cluster formation
test "cluster forms correctly with mdns_lite strategy" do
  nodes = start_cluster([:"test1@127.0.0.1", :"test2@127.0.0.1"])
  
  # Verify cluster formation
  Enum.each(nodes, fn node ->
    cluster_nodes = :rpc.call(node, Node, :list, [])
    assert length(cluster_nodes) == 1  # Other node connected
  end)
end

# Service discovery across nodes
test "services registered on one node are discoverable from another" do
  {node1, node2} = start_two_node_cluster()
  
  # Register service on node1
  :ok = :rpc.call(node1, Foundation.ServiceMesh, :register_service, 
    [:test_service, spawn_service(), [:capability_a]])
  
  # Discover from node2
  services = :rpc.call(node2, Foundation.ServiceMesh, :discover_services, 
    [name: :test_service])
  assert length(services) == 1
end
```

### End-to-End Tests (10% of coverage)
```elixir
# Complete application scenarios
test "elixir_scope distributed debugging workflow" do
  cluster = start_three_node_cluster()
  
  # Start ElixirScope on cluster
  start_elixir_scope_on_cluster(cluster)
  
  # Execute distributed operation with tracing
  trace_id = ElixirScope.start_distributed_trace()
  result = execute_distributed_workflow(cluster, trace_id)
  
  # Verify trace data collected from all nodes
  trace_data = ElixirScope.get_trace_data(trace_id)
  assert trace_data.nodes == cluster
  assert trace_data.complete == true
end
```

## Performance Benchmarks

### Cluster Formation Speed
```elixir
@tag :benchmark
test "cluster formation completes within SLA" do
  start_time = System.monotonic_time(:millisecond)
  
  nodes = start_cluster_async(5)
  wait_for_full_cluster_formation(nodes)
  
  formation_time = System.monotonic_time(:millisecond) - start_time
  assert formation_time < 30_000  # 30 seconds SLA
end
```

### Message Throughput
```elixir
@tag :benchmark  
test "channel messaging meets throughput requirements" do
  cluster = start_cluster(3)
  
  # Measure messages per second across channels
  throughput = measure_channel_throughput(cluster, duration: 10_000)
  
  assert throughput[:control] > 1_000    # 1k/sec control messages
  assert throughput[:events] > 5_000     # 5k/sec event messages  
  assert throughput[:data] > 10_000      # 10k/sec data messages
end
```

## Chaos Testing Requirements

### Network Partitions
```elixir
test "cluster heals after network partition" do
  cluster = start_cluster(5)
  
  # Create partition: [node1, node2] vs [node3, node4, node5]
  create_network_partition(cluster, split: 2)
  
  # Verify each partition continues operating
  verify_partition_operations(cluster)
  
  # Heal partition
  heal_network_partition(cluster)
  
  # Verify cluster convergence
  assert_eventually(fn -> cluster_fully_converged?(cluster) end, 30_000)
end
```

### Node Failures
```elixir
test "services migrate when nodes fail" do
  cluster = start_cluster(3)
  
  # Start singleton service
  {:ok, service_pid} = Foundation.ProcessManager.start_singleton(TestService, [])
  original_node = node(service_pid)
  
  # Kill the node hosting the service
  kill_node(original_node)
  
  # Verify service restarts on another node
  assert_eventually(fn ->
    case Foundation.ProcessManager.lookup_singleton(TestService) do
      {:ok, new_pid} -> node(new_pid) != original_node
      _ -> false
    end
  end, 10_000)
end
```

---

# 4. Performance Characteristics & SLAs

## Cluster Formation SLAs

| Cluster Size | Formation Time | 99th Percentile |
|-------------|----------------|-----------------|
| 2-5 nodes   | < 10 seconds   | < 15 seconds    |
| 6-20 nodes  | < 30 seconds   | < 45 seconds    |
| 21-100 nodes| < 2 minutes    | < 3 minutes     |

## Message Latency SLAs

| Message Type | Average Latency | 99th Percentile |
|-------------|----------------|-----------------|
| Control     | < 5ms          | < 20ms          |
| Events      | < 10ms         | < 50ms          |
| Telemetry   | < 50ms         | < 200ms         |
| Data        | < 100ms        | < 500ms         |

## Resource Utilization Targets

### Memory Overhead
- Foundation core: < 50MB per node
- Per-service overhead: < 1MB per registered service
- Channel overhead: < 10MB per active channel

### CPU Utilization
- Idle cluster: < 1% CPU for Foundation processes
- Active messaging: < 5% CPU overhead vs direct Distributed Erlang
- Cluster formation: < 30% CPU spike, duration < 60 seconds

### Network Bandwidth
- Control messages: < 1KB/message average
- Heartbeat overhead: < 100 bytes/second per node pair
- Service discovery: < 10KB per discovery operation

---

# 5. Security & Operational Requirements

## Security Model

### Cluster Authentication
```elixir
# Foundation must support secure cluster formation
config :foundation,
  cluster: :kubernetes,
  security: [
    erlang_cookie: {:system, "ERLANG_COOKIE"},
    tls_enabled: true,
    certificate_file: "/etc/ssl/certs/cluster.pem"
  ]
```

### Service Authorization
```elixir
# Services can declare required capabilities
Foundation.ServiceMesh.register_service(
  :payment_service,
  self(),
  [:payment_processing],
  %{security_level: :high, audit_required: true}
)

# Discovery can filter by security requirements
Foundation.ServiceMesh.discover_services(
  capabilities: [:payment_processing],
  security_level: :high
)
```

## Operational Requirements

### Health Monitoring
```elixir
# Foundation must expose health endpoints
Foundation.HealthMonitor.cluster_health()
# => %{
#   status: :healthy | :degraded | :critical,
#   nodes: [{node, status, metrics}],
#   services: [{service, status, instances}],
#   last_check: timestamp
# }
```

### Metrics Collection
```elixir
# Standard telemetry events Foundation must emit
[:foundation, :cluster, :node_joined] => %{node: atom()}
[:foundation, :cluster, :node_left] => %{node: atom(), reason: term()}
[:foundation, :service, :registered] => %{name: term(), node: atom()}
[:foundation, :service, :deregistered] => %{name: term(), node: atom()}
[:foundation, :message, :sent] => %{channel: atom(), size: integer()}
[:foundation, :message, :received] => %{channel: atom(), latency: integer()}
```

### Logging Standards
```elixir
# Foundation must provide structured logging
Logger.info("Foundation cluster formed", 
  cluster_id: cluster_id,
  node_count: 3,
  formation_time_ms: 15_432,
  strategy: :kubernetes
)

Logger.warning("Service health check failed",
  service: :user_service,
  node: :"app@10.0.1.5",
  consecutive_failures: 3,
  action: :marking_unhealthy
)
```

## Deployment Requirements

### Container Support
```dockerfile
# Foundation must work in containerized environments
FROM elixir:1.15-alpine

# Required for clustering
RUN apk add --no-cache netcat-openbsd

# Foundation clustering just works
COPY . /app
WORKDIR /app
RUN mix deps.get && mix compile

# Single environment variable enables clustering
ENV FOUNDATION_CLUSTER=kubernetes

CMD ["mix", "run", "--no-halt"]
```

### Kubernetes Integration
```yaml
# Foundation must integrate with Kubernetes service discovery
apiVersion: apps/v1
kind: Deployment
metadata:
  name: foundation-app
spec:
  selector:
    matchLabels:
      app: foundation-app
  template:
    metadata:
      labels:
        app: foundation-app
    spec:
      containers:
      - name: app
        image: foundation-app:latest
        env:
        - name: FOUNDATION_CLUSTER
          value: "kubernetes"
        - name: FOUNDATION_APP_NAME
          value: "foundation-app"
```

---

# 6. Migration & Compatibility Guide

## From Existing libcluster

### Zero-Change Migration
```elixir
# Existing libcluster config continues to work
config :libcluster,
  topologies: [
    k8s: [
      strategy: Cluster.Strategy.Kubernetes,
      config: [...]
    ]
  ]

# Just add Foundation dependency - no config changes needed
{:foundation, "~> 2.0"}
```

### Gradual Enhancement Migration
```elixir
# Phase 1: Add Foundation, keep libcluster config
{:foundation, "~> 2.0"}

# Phase 2: Start using Foundation services
Foundation.ServiceMesh.register_service(:my_service, self())

# Phase 3: Switch to Foundation clustering
config :foundation, cluster: :kubernetes
# Remove old libcluster config
```

## From Plain OTP/GenServer

### Service Registry Migration
```elixir
# Before: Manual process registry
GenServer.start_link(MyService, [], name: {:global, :my_service})

# After: Foundation service mesh
Foundation.ProcessManager.start_singleton(MyService, [], name: :my_service)
```

### PubSub Migration  
```elixir
# Before: Manual message broadcasting
Enum.each(Node.list(), fn node ->
  send({:my_service, node}, message)
end)

# After: Foundation channels
Foundation.Channels.broadcast(:events, message)
```

## API Compatibility Matrix

| Foundation 1.x API | Foundation 2.0 Support | Notes |
|--------------------|------------------------|-------|
| `Foundation.Config.*` | ✅ Full compatibility | All existing APIs unchanged |
| `Foundation.Events.*` | ✅ Full compatibility | Enhanced with distributed features |
| `Foundation.Telemetry.*` | ✅ Full compatibility | Cluster aggregation added |
| `Foundation.ServiceRegistry.*` | ✅ Full compatibility | Enhanced with Horde backend |

---

This technical specification provides the foundation for implementing Foundation 2.0 with confidence, ensuring we build exactly what we've envisioned in our synthesis discussions.