# Foundation 2.0: Getting Started & Quick Implementation Guide

## Quick Start - Day 1 Implementation

### 1. Project Setup

```bash
# Clone or create Foundation 2.0 project
git checkout -b feature/foundation-2-0-revolution
cd lib/foundation

# Create the new distributed architecture
mkdir -p services/{config,events,telemetry,registry}
mkdir -p beam/{processes,messages,schedulers,memory}
mkdir -p distributed/{topology,channels,discovery,consensus}
```

### 2. Dependencies Setup

Add to `mix.exs`:

```elixir
defp deps do
  [
    # Existing Foundation dependencies
    {:jason, "~> 1.4"},
    
    # New Foundation 2.0 dependencies
    {:partisan, "~> 5.0", optional: true},
    {:libring, "~> 1.6"},
    {:phoenix_pubsub, "~> 2.1"},
    {:telemetry, "~> 1.2"},
    {:telemetry_metrics, "~> 0.6"}
  ]
end
```

### 3. Configuration

Add to `config/config.exs`:

```elixir
# Foundation 2.0 Configuration
config :foundation,
  # Core services (backward compatible)
  config_enabled: true,
  events_enabled: true,
  telemetry_enabled: true,
  service_registry_enabled: true,
  
  # New distributed features (opt-in)
  distributed_config: false,
  distributed_events: false,
  cluster_telemetry: false,
  service_mesh: false,
  
  # BEAM optimizations (automatic)
  beam_primitives: true,
  process_ecosystems: true,
  message_optimization: true,
  scheduler_awareness: true

# Partisan Configuration (when enabled)
config :partisan,
  overlay: [
    {Foundation.Distributed.Overlay, :full_mesh, %{channels: [:coordination, :data]}}
  ],
  channels: [:coordination, :data, :gossip, :events]
```

### 4. Application Supervision Tree

Update `lib/foundation/application.ex`:

```elixir
defmodule Foundation.Application do
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Core services (Foundation 1.x compatible)
      Foundation.Services.ConfigServer,
      Foundation.Services.EventStore,
      Foundation.Services.TelemetryService,
      Foundation.ServiceRegistry,
      
      # BEAM primitives (automatic)
      {Foundation.BEAM.ProcessManager, []},
      
      # Distributed services (when enabled)
      {Foundation.Distributed.Supervisor, distributed_enabled?()}
    ]

    opts = [strategy: :one_for_one, name: Foundation.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp distributed_enabled?() do
    Application.get_env(:foundation, :distributed_config, false) or
    Application.get_env(:foundation, :distributed_events, false) or
    Application.get_env(:foundation, :cluster_telemetry, false) or
    Application.get_env(:foundation, :service_mesh, false)
  end
end
```

### 5. Backward Compatibility Test

Create `test/foundation_2_0_compatibility_test.exs`:

```elixir
defmodule Foundation2CompatibilityTest do
  use ExUnit.Case, async: true
  
  # Test that all Foundation 1.x APIs work unchanged
  
  test "Foundation.Config API compatibility" do
    # Original API must work exactly as before
    assert Foundation.Config.available?() == true
    
    # Set and get configuration
    assert :ok = Foundation.Config.update([:test, :key], "value")
    assert {:ok, "value"} = Foundation.Config.get([:test, :key])
    
    # Reset functionality
    assert :ok = Foundation.Config.reset()
    assert :not_found = Foundation.Config.get([:test, :key])
  end
  
  test "Foundation.Events API compatibility" do
    # Original event creation
    {:ok, event} = Foundation.Events.new_event(:test_event, %{data: "test"})
    assert event.event_type == :test_event
    
    # Event storage
    {:ok, event_id} = Foundation.Events.store(event)
    assert is_binary(event_id)
    
    # Event querying  
    {:ok, events} = Foundation.Events.query(%{event_type: :test_event})
    assert length(events) >= 1
    
    # Stats
    {:ok, stats} = Foundation.Events.stats()
    assert is_map(stats)
  end
  
  test "Foundation.Telemetry API compatibility" do
    # Original telemetry APIs
    assert Foundation.Telemetry.available?() == true
    
    # Emit metrics
    Foundation.Telemetry.emit_counter(:test_counter, %{tag: "test"})
    Foundation.Telemetry.emit_gauge(:test_gauge, 42, %{tag: "test"})
    
    # Get metrics
    {:ok, metrics} = Foundation.Telemetry.get_metrics()
    assert is_map(metrics)
  end
  
  test "Foundation.ServiceRegistry API compatibility" do
    # Original service registry APIs
    test_pid = spawn(fn -> :timer.sleep(1000) end)
    
    # Register service
    assert :ok = Foundation.ServiceRegistry.register(:test_ns, :test_service, test_pid)
    
    # Lookup service
    assert {:ok, ^test_pid} = Foundation.ServiceRegistry.lookup(:test_ns, :test_service)
    
    # List services
    services = Foundation.ServiceRegistry.list_services(:test_ns)
    assert Enum.any?(services, fn {name, _} -> name == :test_service end)
    
    # Unregister
    assert :ok = Foundation.ServiceRegistry.unregister(:test_ns, :test_service)
    assert :not_found = Foundation.ServiceRegistry.lookup(:test_ns, :test_service)
  end
end
```

## Progressive Enhancement Strategy

### Week 1: Start with Enhanced Config

1. **Implement Foundation.Config 2.0** (from artifacts above)
2. **Add distributed features as opt-in**:

```elixir
# Enable distributed config gradually
config :foundation, distributed_config: true

# Test distributed consensus
Foundation.Config.set_cluster_wide([:app, :feature_flag], true)
{:ok, true} = Foundation.Config.get_with_consensus([:app, :feature_flag])

# Enable adaptive learning
Foundation.Config.enable_adaptive_config([:auto_optimize, :predict_needs])
```

3. **Validate zero breaking changes**:

```bash
# Run all existing Foundation tests
mix test --only foundation_1_x

# Run compatibility test suite  
mix test test/foundation_2_0_compatibility_test.exs

# Performance regression test
mix test --only performance
```

### Week 2: Add Enhanced Events & Telemetry

1. **Implement Foundation.Events 2.0**:

```elixir
# Enable distributed events
config :foundation, distributed_events: true

# Test cluster-wide events
{:ok, correlation_id} = Foundation.Events.emit_distributed(
  :user_action, 
  %{user_id: 123, action: :login},
  correlation: :global
)

# Subscribe to cluster events
{:ok, sub_id} = Foundation.Events.subscribe_cluster_wide(
  [event_type: :user_action],
  handler: &MyApp.EventHandler.handle/1
)
```

2. **Implement Foundation.Telemetry 2.0**:

```elixir
# Enable cluster telemetry
config :foundation, cluster_telemetry: true

# Get cluster-wide metrics
{:ok, metrics} = Foundation.Telemetry.get_cluster_metrics(
  aggregation: :sum,
  time_window: :last_hour
)

# Enable predictive monitoring
Foundation.Telemetry.enable_predictive_monitoring(
  [:memory_pressure, :cpu_saturation],
  sensitivity: :medium
)
```

### Week 3: BEAM Primitives Integration

1. **Process Ecosystems**:

```elixir
# Create a process ecosystem
{:ok, ecosystem} = Foundation.BEAM.Processes.spawn_ecosystem(%{
  coordinator: MyApp.DataCoordinator,
  workers: {MyApp.DataWorker, count: :cpu_count},
  memory_strategy: :isolated_heaps
})

# Monitor ecosystem health
Foundation.BEAM.Processes.get_ecosystem_health(ecosystem.id)
```

2. **Optimized Message Passing**:

```elixir
# Send large data with optimization
large_data = generate_large_dataset()

Foundation.BEAM.Messages.send_optimized(
  worker_pid, 
  large_data,
  strategy: :ets_reference,
  ttl: 30_000
)

# Use flow control for high-volume messaging
Foundation.BEAM.Messages.send_with_backpressure(
  worker_pid,
  batch_data,
  max_queue_size: 1000,
  backpressure_strategy: :queue
)
```

## Migration Paths

### From Foundation 1.x

**Zero-Risk Migration:**

```elixir
# 1. Update dependency
{:foundation, "~> 2.0"}

# 2. No code changes required - everything works as before

# 3. Gradually enable new features
config :foundation,
  distributed_config: true,    # Week 1
  distributed_events: true,    # Week 2  
  cluster_telemetry: true,     # Week 3
  service_mesh: true          # Week 4
```

### From libcluster

**Gradual Replacement:**

```elixir
# 1. Keep libcluster during transition
deps: [
  {:libcluster, "~> 3.3"},
  {:foundation, "~> 2.0"}
]

# 2. Add Foundation service discovery
Foundation.ServiceRegistry.register_mesh_service(
  :my_service,
  self(),
  [:database_read, :high_availability]
)

# 3. Replace libcluster topology with Foundation
config :foundation, distributed_config: true
# Remove libcluster configuration

# 4. Switch to Partisan for advanced topologies
config :foundation, 
  topology: :hyparview,  # For 10-1000 nodes
  channels: [:coordination, :data, :gossip, :events]
```

### From Plain OTP

**Enhanced Foundation Adoption:**

```elixir
# 1. Start with Foundation basics
Foundation.ServiceRegistry.register(:my_app, :worker_pool, worker_supervisor)

# 2. Add telemetry
Foundation.Telemetry.emit_counter(:requests_processed, %{service: :api})

# 3. Use BEAM primitives for performance
{:ok, ecosystem} = Foundation.BEAM.Processes.spawn_ecosystem(%{
  coordinator: MyApp.WorkerCoordinator,
  workers: {MyApp.Worker, count: 10},
  memory_strategy: :isolated_heaps
})

# 4. Scale to cluster
config :foundation, service_mesh: true
```

## Testing Strategy

### Unit Testing

```elixir
# test/foundation/config_test.exs
defmodule Foundation.ConfigTest do
  use ExUnit.Case, async: true
  
  setup do
    Foundation.Config.reset()
    :ok
  end
  
  test "local configuration works as before" do
    assert :ok = Foundation.Config.update([:test], "value")
    assert {:ok, "value"} = Foundation.Config.get([:test])
  end
  
  test "distributed configuration with consensus" do
    # Mock cluster for testing
    Application.put_env(:foundation, :distributed_config, true)
    
    assert :ok = Foundation.Config.set_cluster_wide([:global], "cluster_value")
    assert {:ok, "cluster_value"} = Foundation.Config.get_with_consensus([:global])
  end
end
```

### Integration Testing

```elixir
# test/integration/distributed_test.exs
defmodule Foundation.Integration.DistributedTest do
  use ExUnit.Case
  
  @moduletag :integration
  
  test "multi-node cluster formation" do
    nodes = start_test_cluster(3)
    
    # Test service discovery across nodes
    Enum.each(nodes, fn node ->
      :rpc.call(node, Foundation.ServiceRegistry, :register_mesh_service, 
        [:test_service, self(), [:capability_a]])
    end)
    
    # Verify service discovery works
    {:ok, services} = Foundation.ServiceRegistry.discover_services(
      capability: :capability_a
    )
    
    assert length(services) == 3
  end
end
```

### Performance Testing

```elixir
# test/performance/benchmark_test.exs
defmodule Foundation.Performance.BenchmarkTest do
  use ExUnit.Case
  
  @moduletag :benchmark
  @moduletag timeout: 60_000
  
  test "message throughput benchmark" do
    large_data = :crypto.strong_rand_bytes(10_240)  # 10KB
    worker = spawn(fn -> message_receiver_loop() end)
    
    # Benchmark standard send
    {time_standard, _} = :timer.tc(fn ->
      Enum.each(1..1000, fn _ ->
        send(worker, large_data)
      end)
    end)
    
    # Benchmark optimized send
    {time_optimized, _} = :timer.tc(fn ->
      Enum.each(1..1000, fn _ ->
        Foundation.BEAM.Messages.send_optimized(
          worker, 
          large_data, 
          strategy: :binary_sharing
        )
      end)
    end)
    
    improvement = time_standard / time_optimized
    assert improvement > 1.5, "Expected >50% improvement, got #{improvement}x"
  end
end
```

## Monitoring & Observability

### Metrics Dashboard

```elixir
# lib/foundation/dashboard.ex
defmodule Foundation.Dashboard do
  def get_cluster_health() do
    %{
      topology: Foundation.Distributed.Topology.current_topology(),
      node_count: length(Node.list()) + 1,
      service_count: get_total_service_count(),
      message_throughput: get_message_throughput(),
      memory_usage: Foundation.BEAM.Memory.analyze_memory_usage(),
      performance_score: calculate_performance_score()
    }
  end
  
  def get_performance_trends() do
    Foundation.Telemetry.get_cluster_metrics(
      aggregation: :average,
      time_window: :last_24_hours
    )
  end
end
```

### Health Checks

```elixir
# lib/foundation/health_check.ex
defmodule Foundation.HealthCheck do
  def cluster_health() do
    checks = [
      topology_health(),
      service_mesh_health(), 
      consensus_health(),
      performance_health()
    ]
    
    case Enum.all?(checks, &(&1.status == :healthy)) do
      true -> :healthy
      false -> {:degraded, failing_checks(checks)}
    end
  end
  
  defp topology_health() do
    case Foundation.Distributed.Topology.analyze_performance() do
      %{cluster_health: :healthy} -> %{component: :topology, status: :healthy}
      _ -> %{component: :topology, status: :degraded}
    end
  end
end
```

## Next Steps

### Day 1 Actions:
1. ✅ Set up project structure 
2. ✅ Implement Foundation.Config 2.0
3. ✅ Create compatibility test suite
4. ✅ Validate zero breaking changes

### Week 1 Goals:
- Foundation.Config 2.0 with distributed consensus
- Foundation.Events 2.0 with intelligent correlation  
- 100% backward compatibility maintained
- Performance benchmarks established

### Month 1 Target:
- All enhanced core services implemented
- BEAM primitives optimization active
- Partisan integration foundation ready
- Production-ready migration path validated

**Ready to revolutionize BEAM distribution.** 🚀

*Start implementation: `git checkout -b feature/foundation-2-0-config && touch lib/foundation/services/config_server.ex`*
