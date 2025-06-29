# JidoSystem Testing Strategy - From Mocks to Production

## Executive Summary

The current testing approach relies heavily on mocks, creating a dangerous gap between test and production behavior. This document outlines a comprehensive testing strategy that ensures production readiness while maintaining fast, reliable tests.

## Current Testing Problems

### 1. **Mock-Reality Divergence**

**Current State**:
```elixir
# Test passes with mock
defmodule CacheTest do
  test "caches values" do
    Foundation.Cache.put(:key, :value)  # Uses Process dictionary
    assert Foundation.Cache.get(:key) == :value
  end
end

# Production fails
Foundation.Cache.put(:key, :value)  # No real implementation!
```

**Root Cause**: Tests written against mock behavior, not contracts.

### 2. **Missing Failure Scenarios**

Tests assume happy path:
- No network failures
- No resource exhaustion  
- No concurrent conflicts
- No distributed system issues

### 3. **Incomplete Integration Testing**

Current integration tests:
- Single node only
- Synchronous execution
- No cross-system boundaries
- Mock external dependencies

## Proposed Testing Architecture

### Testing Pyramid

```
         ┌─────────────┐
         │    E2E      │  5%
         │   Tests     │
       ┌─┴─────────────┴─┐
       │  Integration    │  20%
       │     Tests       │
     ┌─┴─────────────────┴─┐
     │   Contract Tests    │  25%
     │  (Mock Validation)  │
   ┌─┴─────────────────────┴─┐
   │     Unit Tests         │  50%
   │  (Pure Functions)      │
   └─────────────────────────┘
```

### 1. Contract Tests (New Layer)

**Purpose**: Ensure mocks match production behavior.

```elixir
defmodule Foundation.CacheContractTest do
  use Foundation.ContractTest, 
    module: Foundation.Cache,
    implementations: [
      Foundation.Infrastructure.Cache,
      Foundation.MockCache
    ]
  
  # Define contract all implementations must satisfy
  describe "cache contract" do
    property "get returns what was put" do
      check all key <- term(),
                value <- term() do
        
        # Test against ALL implementations
        for impl <- implementations() do
          impl.clear()
          assert impl.put(key, value) == :ok
          assert impl.get(key) == value
        end
      end
    end
    
    property "TTL expires values" do
      check all key <- term(),
                value <- term(),
                ttl <- positive_integer() do
        
        for impl <- implementations() do
          impl.put(key, value, ttl: ttl)
          Process.sleep(ttl + 10)
          assert impl.get(key) == nil
        end
      end
    end
    
    property "concurrent operations are safe" do
      # Test concurrent access patterns
    end
  end
end
```

### 2. Behavior Verification Tests

```elixir
defmodule CircuitBreakerBehaviorTest do
  use ExUnit.Case
  
  # Test the behavior, not the implementation
  describe "circuit breaker behavior" do
    test "opens after threshold failures" do
      # Create test harness
      {:ok, breaker} = start_breaker(threshold: 3)
      
      # Inject failures
      for _ <- 1..3 do
        execute_and_fail(breaker)
      end
      
      # Verify circuit is open
      assert {:error, :circuit_open} = execute(breaker, fn -> :ok end)
    end
    
    test "recovers after timeout" do
      {:ok, breaker} = start_breaker(threshold: 1, recovery: 100)
      
      # Open circuit
      execute_and_fail(breaker)
      assert circuit_state(breaker) == :open
      
      # Wait for recovery
      Process.sleep(150)
      
      # Should allow one test call
      assert {:ok, :success} = execute(breaker, fn -> :success end)
      assert circuit_state(breaker) == :closed
    end
  end
  
  # Helper to start any breaker implementation
  defp start_breaker(opts) do
    impl = Application.get_env(:test, :circuit_breaker_impl, RealCircuitBreaker)
    impl.start_link(opts)
  end
end
```

### 3. Property-Based Testing

```elixir
defmodule AgentPropertyTest do
  use ExUnit.Case
  use ExUnitProperties
  
  property "agents handle any valid instruction sequence" do
    check all instructions <- list_of(valid_instruction()) do
      {:ok, agent} = start_test_agent()
      
      # Send all instructions
      results = Enum.map(instructions, &send_instruction(agent, &1))
      
      # Verify invariants hold
      assert agent_invariants_hold?(agent)
      assert all_results_valid?(results)
    end
  end
  
  property "agents recover from any error" do
    check all good_instructions <- list_of(valid_instruction()),
              bad_instruction <- error_instruction(),
              more_good <- list_of(valid_instruction()) do
      
      {:ok, agent} = start_test_agent()
      
      # Send good instructions
      Enum.each(good_instructions, &send_instruction(agent, &1))
      
      # Send bad instruction (should not crash agent)
      send_instruction(agent, bad_instruction)
      
      # Agent should still process good instructions
      results = Enum.map(more_good, &send_instruction(agent, &1))
      assert all_results_valid?(results)
    end
  end
end
```

### 4. Chaos Testing

```elixir
defmodule ChaosSuite do
  use ExUnit.Case
  
  @tag :chaos
  test "system survives random node failures" do
    # Start cluster
    nodes = start_test_cluster(5)
    
    # Start workload
    workload = start_continuous_workload()
    
    # Inject chaos
    chaos_loop(10, fn ->
      node = Enum.random(nodes)
      kill_node(node)
      Process.sleep(5000)
      restart_node(node)
    end)
    
    # Verify system health
    assert workload_completed?(workload)
    assert data_consistent?(nodes)
    assert no_messages_lost?()
  end
  
  @tag :chaos
  test "graceful degradation under resource pressure" do
    # Limit resources
    constrain_memory("500MB")
    constrain_cpu("50%")
    
    # Apply increasing load
    results = for load <- [100, 500, 1000, 5000] do
      apply_load(load)
    end
    
    # Should degrade gracefully, not crash
    assert Enum.all?(results, &match?({:ok, _} | {:degraded, _}, &1))
  end
end
```

### 5. Load and Performance Tests

```elixir
defmodule LoadTest do
  use ExUnit.Case
  
  @tag :load
  test "handles target throughput" do
    target_rps = 10_000
    duration = 60 # seconds
    
    # Start system
    {:ok, system} = start_production_like_system()
    
    # Generate load
    results = LoadGenerator.run(
      target_rps: target_rps,
      duration: duration,
      scenario: :mixed_workload
    )
    
    # Verify SLAs
    assert results.success_rate > 0.99
    assert results.p99_latency < 100 # ms
    assert results.error_rate < 0.01
  end
  
  @tag :load  
  test "auto-scales under variable load" do
    # Start with minimal resources
    {:ok, system} = start_system(agents: 2)
    
    # Apply variable load pattern
    load_pattern = [
      {100, 30},   # 100 RPS for 30s
      {1000, 30},  # Spike to 1000 RPS
      {100, 30},   # Back to 100 RPS
      {5000, 60}   # Major spike
    ]
    
    results = LoadGenerator.run_pattern(load_pattern)
    
    # System should scale to meet demand
    assert Enum.all?(results, fn r -> r.success_rate > 0.95 end)
    
    # Verify scaling happened
    assert get_agent_count(system) > 2
  end
end
```

### 6. Integration Test Harness

```elixir
defmodule IntegrationHarness do
  @moduledoc """
  Realistic test environment for integration testing.
  """
  
  def start_test_environment(opts \\ []) do
    # Start external dependencies
    {:ok, _postgres} = start_postgres()
    {:ok, _redis} = start_redis()
    {:ok, _kafka} = start_kafka()
    
    # Start Foundation services
    {:ok, _foundation} = Foundation.start_link(
      registry_impl: MABEAM.AgentRegistry,
      infrastructure_impl: Foundation.Infrastructure.Real
    )
    
    # Start JidoSystem
    {:ok, _system} = JidoSystem.start(
      environment: :test,
      clustering: Keyword.get(opts, :clustering, false)
    )
    
    # Wait for system ready
    wait_for_ready()
    
    :ok
  end
  
  def with_test_cluster(node_count, fun) do
    # Start distributed test cluster
    {:ok, nodes} = LocalCluster.start_nodes(:jido_test, node_count)
    
    # Start system on each node
    for node <- nodes do
      rpc(node, IntegrationHarness, :start_test_environment, [[clustering: true]])
    end
    
    # Run test
    try do
      fun.(nodes)
    after
      # Cleanup
      LocalCluster.stop()
    end
  end
end
```

### 7. Test Categorization and Execution

```elixir
# mix.exs
def project do
  [
    # ... 
    test_coverage: [tool: ExCoveralls],
    preferred_cli_env: [
      "test.unit": :test,
      "test.integration": :test,
      "test.contract": :test,
      "test.chaos": :test,
      "test.load": :test,
      "test.e2e": :test
    ]
  ]
end

defp aliases do
  [
    "test.unit": ["test --only unit"],
    "test.integration": ["test --only integration"],
    "test.contract": ["test --only contract"],
    "test.chaos": ["test --only chaos --max-cases 1"],
    "test.load": ["test --only load --timeout 300000"],
    "test.e2e": ["test --only e2e"],
    "test.all": ["test.unit", "test.contract", "test.integration"],
    "test.ci": ["test.all", "dialyzer", "credo --strict"]
  ]
end
```

## Test Data Management

### 1. Fixtures and Factories

```elixir
defmodule TestFactory do
  use ExMachina
  
  def agent_factory do
    %{
      name: sequence(:name, &"agent_#{&1}"),
      capabilities: build_list(3, :capability),
      resources: build(:resource_spec),
      metadata: %{}
    }
  end
  
  def instruction_factory do
    %Jido.Instruction{
      id: UUID.uuid4(),
      action: sequence(:action, [ProcessAction, ValidateAction, TransformAction]),
      params: build(:instruction_params),
      context: build(:context)
    }
  end
  
  # Scenario builders
  def order_processing_scenario do
    %{
      agents: [
        build(:agent, name: "validator", capabilities: [:validation]),
        build(:agent, name: "processor", capabilities: [:processing]),
        build(:agent, name: "notifier", capabilities: [:notification])
      ],
      workflow: build(:workflow, :order_processing),
      test_data: build_list(100, :order)
    }
  end
end
```

### 2. Test Containers

```elixir
defmodule TestContainers do
  @moduledoc """
  Manage external dependencies for testing.
  """
  
  def postgres_container do
    %{
      image: "postgres:14",
      environment: %{
        "POSTGRES_PASSWORD" => "test",
        "POSTGRES_DB" => "jido_test"
      },
      ports: [{5432, :random}],
      wait_strategy: :port
    }
  end
  
  def redis_container do
    %{
      image: "redis:7-alpine",
      ports: [{6379, :random}],
      wait_strategy: :log_message,
      wait_for: "Ready to accept connections"
    }
  end
  
  def start_containers do
    containers = %{
      postgres: postgres_container(),
      redis: redis_container()
    }
    
    TestContainers.start_containers(containers)
  end
end
```

## Continuous Integration Pipeline

### GitHub Actions Workflow

```yaml
name: JidoSystem CI

on: [push, pull_request]

jobs:
  unit-tests:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        elixir: [1.14, 1.15]
        otp: [25, 26]
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: ${{ matrix.elixir }}
          otp-version: ${{ matrix.otp }}
      - run: mix deps.get
      - run: mix test.unit

  contract-tests:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
      - run: mix deps.get
      - run: mix test.contract

  integration-tests:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:14
        env:
          POSTGRES_PASSWORD: test
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
      redis:
        image: redis:7
        options: >-
          --health-cmd "redis-cli ping"
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
      - run: mix deps.get
      - run: mix test.integration

  dialyzer:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
      - uses: actions/cache@v3
        with:
          path: priv/plts
          key: plts-${{ runner.os }}-${{ matrix.otp }}-${{ matrix.elixir }}-${{ hashFiles('**/mix.lock') }}
      - run: mix deps.get
      - run: mix dialyzer --halt-exit-status

  chaos-tests:
    runs-on: ubuntu-latest
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
      - run: mix deps.get
      - run: mix test.chaos
      
  load-tests:
    runs-on: ubuntu-latest
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
      - run: mix deps.get
      - run: mix test.load
```

## Test Environment Configuration

### 1. Development Environment

```elixir
# config/test.exs
config :jido_system,
  environment: :test,
  use_mocks: true,
  async_testing: true

config :foundation,
  registry_impl: Foundation.MockRegistry,
  infrastructure_impl: Foundation.MockInfrastructure
```

### 2. Integration Environment

```elixir
# config/integration_test.exs
config :jido_system,
  environment: :integration_test,
  use_mocks: false,
  async_testing: false

config :foundation,
  registry_impl: MABEAM.AgentRegistry,
  infrastructure_impl: Foundation.Infrastructure.Real

config :logger, level: :warning
```

### 3. Performance Environment

```elixir
# config/perf_test.exs
config :jido_system,
  environment: :perf_test,
  use_mocks: false,
  metrics_enabled: true,
  profiling_enabled: true
```

## Monitoring Test Health

### Test Metrics Dashboard

```elixir
defmodule TestMetrics do
  def collect do
    %{
      coverage: get_test_coverage(),
      flakiness: calculate_flakiness(),
      duration: get_test_duration_trends(),
      failures: get_failure_patterns(),
      performance: get_performance_regression()
    }
  end
  
  def report do
    metrics = collect()
    
    # Alert on concerning trends
    if metrics.flakiness > 0.05 do
      alert("Test flakiness above 5%: #{metrics.flakiness}")
    end
    
    if metrics.duration.trend == :increasing do
      alert("Test duration increasing: #{metrics.duration.change}%")
    end
  end
end
```

## Migration Strategy

### Phase 1: Add Contract Tests (Week 1)
- Create contract test framework
- Write contracts for all mocked modules
- Verify mocks match contracts

### Phase 2: Enhance Integration Tests (Week 2)
- Add test containers
- Create integration test harness
- Test distributed scenarios

### Phase 3: Add Chaos Tests (Week 3)
- Implement chaos injection
- Add failure scenario tests
- Test recovery mechanisms

### Phase 4: Performance Testing (Week 4)
- Create load test suite
- Establish performance baselines
- Add regression detection

## Success Criteria

1. **Coverage**: >90% code coverage with meaningful tests
2. **Flakiness**: <1% flaky tests
3. **Speed**: Unit tests <1 min, Integration <5 min
4. **Reliability**: No false positives in CI
5. **Realism**: Tests reflect production scenarios

## Conclusion

This testing strategy bridges the gap between mock-based testing and production reality. By introducing contract tests, property-based testing, chaos testing, and realistic integration environments, we ensure that passing tests actually mean the system will work in production.

The key is to test behaviors and contracts, not implementations, while progressively adding more realistic test scenarios that match production conditions.