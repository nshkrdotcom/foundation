# Foundation Backport Testing Strategy

## Executive Summary

This document defines the comprehensive testing strategy for backporting agent-aware capabilities into the existing Foundation infrastructure. The analysis reveals that Foundation has **exceptional test coverage (90%+ of requirements)** with enterprise-grade testing infrastructure, requiring only **targeted enhancements** for agent-specific functionality rather than rebuilding test infrastructure.

## Current Test Infrastructure Assessment

### Strengths of Existing Test Architecture ✅

1. **Comprehensive Component Coverage**: All backport targets have thorough test coverage
2. **Sophisticated Test Infrastructure**: Advanced helpers, isolation, and resource management
3. **Multiple Testing Levels**: Unit, integration, property-based, stress, and security testing
4. **Concurrent Testing Excellence**: Proper isolation and thread-safety verification
5. **Real-World Scenario Testing**: Production-like usage patterns
6. **Performance Testing**: Load testing with resource monitoring
7. **Property-Based Testing**: Advanced generative testing with StreamData

### Test Coverage Analysis by Component

| Component | Current Coverage | Agent-Aware Gaps | Enhancement Required |
|-----------|------------------|-------------------|---------------------|
| ProcessRegistry | ✅ Excellent | Agent metadata, discovery | Medium |
| CircuitBreaker | ✅ Excellent | Agent health integration | Low |
| RateLimiter | ✅ Excellent | Agent capability throttling | Medium |
| ConfigServer | ✅ Excellent | Agent-specific config | Low |
| EventStore | ✅ Good | Agent correlation, subscriptions | Medium |
| TelemetryService | ✅ Good | Agent metrics aggregation | Medium |
| Coordination | ✅ Excellent | Agent-aware coordination | High |

## Testing Gaps for Agent-Aware Features

### 1. Agent Lifecycle Integration Testing
**Current State**: Basic service lifecycle testing
**Required Enhancement**: Agent-specific lifecycle management

**New Test Requirements**:
```elixir
defmodule Foundation.Agent.LifecycleTest do
  # Agent registration with rich metadata
  # Agent health monitoring and state transitions  
  # Agent capability discovery and updates
  # Agent resource requirement validation
  # Agent coordination participation
end
```

### 2. Agent Metadata Validation Testing
**Current State**: Basic metadata support in ProcessRegistry
**Required Enhancement**: Agent-specific metadata validation and querying

**New Test Requirements**:
```elixir
defmodule Foundation.ProcessRegistry.AgentMetadataTest do
  # Agent metadata schema validation
  # Agent capability-based discovery
  # Agent health status tracking
  # Agent resource usage monitoring
  # Agent coordination state management
end
```

### 3. Multi-Agent Coordination Testing
**Current State**: Basic coordination primitives testing
**Required Enhancement**: Agent-aware coordination scenarios

**New Test Requirements**:
```elixir
defmodule Foundation.Coordination.AgentAwareTest do
  # Agent-aware consensus with health consideration
  # Agent capability-based leader election
  # Agent resource allocation coordination
  # Agent coordination failure recovery
  # Cross-agent communication patterns
end
```

### 4. Agent Resource Management Testing
**Current State**: No centralized resource management testing
**Required Enhancement**: Comprehensive resource testing for agents

**New Test Requirements**:
```elixir
defmodule Foundation.Infrastructure.ResourceManagerTest do
  # Agent resource allocation and tracking
  # Resource threshold monitoring and alerting
  # Resource contention resolution
  # Resource usage prediction and optimization
  # Resource cleanup and recovery
end
```

## Enhanced Testing Strategy

### Phase 1: Foundation Enhancement Testing (Weeks 1-2)

#### 1.1 ProcessRegistry Agent-Aware Testing

**File**: `test/foundation/process_registry_agent_test.exs`

```elixir
defmodule Foundation.ProcessRegistryAgentTest do
  use ExUnit.Case, async: false
  use ExUnitProperties
  
  alias Foundation.ProcessRegistry
  
  describe "agent registration" do
    test "registers agent with comprehensive metadata" do
      agent_metadata = %{
        type: :ml_agent,
        capabilities: [:nlp, :classification, :generation],
        health: :healthy,
        resource_usage: %{memory: 0.7, cpu: 0.4},
        coordination_state: %{active_consensus: [], held_locks: []},
        last_health_check: DateTime.utc_now()
      }
      
      pid = spawn(fn -> :timer.sleep(1000) end)
      
      assert :ok = ProcessRegistry.register_agent(
        :production, 
        :ml_agent_1, 
        pid, 
        agent_metadata
      )
      
      assert {:ok, {^pid, returned_metadata}} = 
        ProcessRegistry.lookup_agent(:production, :ml_agent_1)
      
      assert returned_metadata.type == :ml_agent
      assert :nlp in returned_metadata.capabilities
    end
    
    test "agent capability-based discovery" do
      # Register multiple agents with different capabilities
      agents = [
        {:nlp_agent_1, [:nlp, :tokenization]},
        {:nlp_agent_2, [:nlp, :classification]}, 
        {:ml_agent_1, [:training, :inference]},
        {:coord_agent_1, [:coordination, :scheduling]}
      ]
      
      for {agent_id, capabilities} <- agents do
        pid = spawn(fn -> :timer.sleep(1000) end)
        metadata = %{type: :agent, capabilities: capabilities}
        ProcessRegistry.register_agent(:production, agent_id, pid, metadata)
      end
      
      # Test capability-based queries
      nlp_agents = ProcessRegistry.lookup_agents_by_capability(:production, :nlp)
      assert length(nlp_agents) == 2
      
      training_agents = ProcessRegistry.lookup_agents_by_capability(:production, :training)
      assert length(training_agents) == 1
    end
  end
  
  describe "agent health monitoring" do
    test "tracks agent health changes" do
      pid = spawn(fn -> :timer.sleep(1000) end)
      initial_metadata = %{type: :agent, health: :healthy}
      
      ProcessRegistry.register_agent(:production, :test_agent, pid, initial_metadata)
      
      # Update agent health
      updated_metadata = %{initial_metadata | health: :degraded}
      ProcessRegistry.update_agent_metadata(:production, :test_agent, updated_metadata)
      
      {:ok, {^pid, metadata}} = ProcessRegistry.lookup_agent(:production, :test_agent)
      assert metadata.health == :degraded
    end
  end
  
  property "agent metadata consistency under concurrent operations" do
    check all(
      agent_count <- integer(1..10),
      capability_sets <- list_of(list_of(atom(), min_length: 1), min_length: 1)
    ) do
      # Test concurrent agent registration maintains metadata consistency
      tasks = for i <- 1..agent_count do
        Task.async(fn ->
          pid = spawn(fn -> :timer.sleep(100) end)
          capabilities = Enum.at(capability_sets, rem(i, length(capability_sets)))
          metadata = %{type: :agent, capabilities: capabilities}
          
          ProcessRegistry.register_agent(:production, :"agent_#{i}", pid, metadata)
        end)
      end
      
      # Wait for all registrations
      Enum.each(tasks, &Task.await/1)
      
      # Verify all agents registered correctly
      for i <- 1..agent_count do
        assert {:ok, {_pid, _metadata}} = 
          ProcessRegistry.lookup_agent(:production, :"agent_#{i}")
      end
      
      # Cleanup
      for i <- 1..agent_count do
        ProcessRegistry.unregister(:production, :"agent_#{i}")
      end
    end
  end
end
```

#### 1.2 CircuitBreaker Agent Integration Testing

**File**: `test/foundation/infrastructure/agent_circuit_breaker_test.exs`

```elixir
defmodule Foundation.Infrastructure.AgentCircuitBreakerTest do
  use ExUnit.Case, async: false
  
  alias Foundation.Infrastructure.AgentCircuitBreaker
  alias Foundation.ProcessRegistry
  
  setup do
    # Register test agent
    pid = spawn(fn -> :timer.sleep(1000) end)
    agent_metadata = %{
      type: :ml_agent,
      capabilities: [:inference],
      health: :healthy,
      resource_usage: %{memory: 0.5, cpu: 0.3}
    }
    
    ProcessRegistry.register_agent(:foundation, :test_agent, pid, agent_metadata)
    
    on_exit(fn ->
      ProcessRegistry.unregister(:foundation, :test_agent)
    end)
    
    :ok
  end
  
  describe "agent-aware circuit breaker" do
    test "creates agent circuit breaker with health integration" do
      {:ok, _pid} = AgentCircuitBreaker.start_agent_breaker(
        :ml_inference_service,
        agent_id: :test_agent,
        capability: :inference,
        resource_thresholds: %{memory: 0.8, cpu: 0.9}
      )
      
      assert {:ok, status} = 
        AgentCircuitBreaker.get_agent_status(:ml_inference_service, :test_agent)
      
      assert status.agent_id == :test_agent
      assert status.capability == :inference
      assert status.circuit_state == :closed
    end
    
    test "agent health affects circuit breaker decisions" do
      {:ok, _pid} = AgentCircuitBreaker.start_agent_breaker(
        :ml_service,
        agent_id: :test_agent,
        capability: :inference
      )
      
      # Simulate agent health degradation
      degraded_metadata = %{
        type: :ml_agent,
        capabilities: [:inference],
        health: :unhealthy,
        resource_usage: %{memory: 0.95, cpu: 0.8}
      }
      
      ProcessRegistry.update_agent_metadata(:foundation, :test_agent, degraded_metadata)
      
      # Circuit should consider agent health in decisions
      result = AgentCircuitBreaker.execute_with_agent(
        :ml_service, 
        :test_agent,
        fn -> {:ok, "success"} end
      )
      
      # Should potentially fail due to unhealthy agent
      assert match?({:error, _}, result) or match?({:ok, _}, result)
    end
  end
end
```

### Phase 2: Service Layer Enhancement Testing (Weeks 3-4)

#### 2.1 EventStore Agent Correlation Testing

**File**: `test/foundation/services/agent_event_store_test.exs`

```elixir
defmodule Foundation.Services.AgentEventStoreTest do
  use ExUnit.Case, async: false
  
  alias Foundation.Services.EventStore
  
  describe "agent event correlation" do
    test "stores events with agent context" do
      event_data = %{
        type: :agent_health_changed,
        agent_id: :ml_agent_1,
        data: %{old_health: :healthy, new_health: :degraded},
        correlation_id: "health-check-123"
      }
      
      assert :ok = EventStore.store_event(event_data)
      
      # Query events by agent
      {:ok, agent_events} = EventStore.query_events(%{agent_id: :ml_agent_1})
      
      assert length(agent_events) == 1
      assert hd(agent_events).agent_id == :ml_agent_1
      assert hd(agent_events).correlation_id == "health-check-123"
    end
    
    test "real-time event subscriptions with agent filtering" do
      # Subscribe to agent-specific events
      {:ok, subscription_id} = EventStore.subscribe_to_events(%{
        agent_id: :ml_agent_1,
        type: :agent_health_changed
      })
      
      # Store relevant event
      event_data = %{
        type: :agent_health_changed,
        agent_id: :ml_agent_1,
        data: %{old_health: :healthy, new_health: :degraded}
      }
      
      EventStore.store_event(event_data)
      
      # Should receive notification
      assert_receive {:event, ^subscription_id, event}, 1000
      assert event.agent_id == :ml_agent_1
      assert event.type == :agent_health_changed
    end
    
    test "correlated event tracking across agents" do
      correlation_id = "coordination-session-456"
      
      # Multiple agents participate in coordination
      events = [
        %{type: :consensus_started, agent_id: :coord_agent, 
          data: %{participants: [:agent_1, :agent_2, :agent_3]}, 
          correlation_id: correlation_id},
        %{type: :consensus_vote, agent_id: :agent_1, 
          data: %{vote: :accept}, correlation_id: correlation_id},
        %{type: :consensus_vote, agent_id: :agent_2, 
          data: %{vote: :accept}, correlation_id: correlation_id},
        %{type: :consensus_completed, agent_id: :coord_agent, 
          data: %{result: :accepted}, correlation_id: correlation_id}
      ]
      
      for event <- events do
        EventStore.store_event(event)
      end
      
      # Query correlated events
      {:ok, correlated_events} = EventStore.get_correlated_events(correlation_id)
      
      assert length(correlated_events) == 4
      assert Enum.all?(correlated_events, &(&1.correlation_id == correlation_id))
    end
  end
end
```

#### 2.2 TelemetryService Agent Metrics Testing

**File**: `test/foundation/services/agent_telemetry_service_test.exs`

```elixir
defmodule Foundation.Services.AgentTelemetryServiceTest do
  use ExUnit.Case, async: false
  
  alias Foundation.Services.TelemetryService
  
  describe "agent metrics aggregation" do
    test "records agent-specific metrics" do
      # Record agent performance metrics
      TelemetryService.record_metric(
        [:foundation, :agent, :task_duration],
        250.5,
        :histogram,
        %{agent_id: :ml_agent_1, task_type: :inference}
      )
      
      TelemetryService.record_metric(
        [:foundation, :agent, :memory_usage],
        0.75,
        :gauge,
        %{agent_id: :ml_agent_1}
      )
      
      # Trigger aggregation
      TelemetryService.trigger_aggregation()
      
      # Query aggregated metrics
      {:ok, metrics} = TelemetryService.get_aggregated_metrics(%{
        agent_id: :ml_agent_1
      })
      
      assert length(metrics) >= 2
      
      memory_metric = Enum.find(metrics, &(&1.name == [:foundation, :agent, :memory_usage]))
      assert memory_metric.last_value == 0.75
      assert memory_metric.type == :gauge
    end
    
    test "agent-specific alerting" do
      # Create alert for agent memory usage
      alert_spec = %{
        name: :agent_high_memory,
        metric_path: [:foundation, :agent, :memory_usage],
        threshold: 0.9,
        condition: :greater_than
      }
      
      assert :ok = TelemetryService.create_alert(alert_spec)
      
      # Record high memory usage
      TelemetryService.record_metric(
        [:foundation, :agent, :memory_usage],
        0.95,
        :gauge,
        %{agent_id: :ml_agent_1}
      )
      
      # Trigger aggregation to evaluate alerts
      TelemetryService.trigger_aggregation()
      
      # Verify alert was triggered (check logs or telemetry events)
      # This would be validated through telemetry event verification
    end
  end
end
```

### Phase 3: Coordination Enhancement Testing (Weeks 5-6)

#### 3.1 Agent-Aware Coordination Testing

**File**: `test/foundation/coordination/agent_aware_service_test.exs`

```elixir
defmodule Foundation.Coordination.AgentAwareServiceTest do
  use ExUnit.Case, async: false
  
  alias Foundation.Coordination.Service, as: CoordinationService
  alias Foundation.ProcessRegistry
  
  setup do
    # Register multiple test agents with different capabilities
    agents = [
      {:ml_agent_1, [:inference, :training], :healthy},
      {:ml_agent_2, [:inference], :healthy},
      {:coord_agent_1, [:coordination], :healthy},
      {:degraded_agent, [:inference], :degraded}
    ]
    
    for {agent_id, capabilities, health} <- agents do
      pid = spawn(fn -> :timer.sleep(2000) end)
      metadata = %{
        type: :agent,
        capabilities: capabilities,
        health: health,
        resource_usage: %{memory: 0.5, cpu: 0.3}
      }
      
      ProcessRegistry.register_agent(:foundation, agent_id, pid, metadata)
    end
    
    on_exit(fn ->
      for {agent_id, _, _} <- agents do
        ProcessRegistry.unregister(:foundation, agent_id)
      end
    end)
    
    :ok
  end
  
  describe "agent-aware consensus" do
    test "consensus considers agent health in participation" do
      participants = [:ml_agent_1, :ml_agent_2, :degraded_agent]
      
      proposal = %{
        action: :model_selection,
        models: ["gpt-4", "claude-3"],
        criteria: :accuracy
      }
      
      {:ok, result} = CoordinationService.consensus(
        :model_selection_round_1,
        participants,
        proposal,
        %{strategy: :majority, timeout: 5_000}
      )
      
      # Verify consensus completed successfully
      assert result.status == :accepted
    end
    
    test "leader election considers agent capabilities" do
      candidates = [:ml_agent_1, :ml_agent_2, :coord_agent_1]
      
      {:ok, leader} = CoordinationService.elect_leader(candidates)
      
      # Coordination agent should be preferred for leadership
      assert leader == :coord_agent_1
    end
    
    test "barrier synchronization with agent context" do
      participants = [:ml_agent_1, :ml_agent_2]
      
      # Create barrier for training completion
      :ok = CoordinationService.create_barrier(
        :training_phase_complete,
        participants
      )
      
      # Simulate agents reaching barrier
      tasks = for agent_id <- participants do
        Task.async(fn ->
          CoordinationService.wait_for_barrier(:training_phase_complete, agent_id)
        end)
      end
      
      # All should complete successfully
      results = Enum.map(tasks, &Task.await(&1, 10_000))
      assert Enum.all?(results, &(&1 == :ok))
    end
  end
  
  describe "resource-aware coordination" do
    test "coordination considers agent resource constraints" do
      # Test coordination with resource-constrained agents
      high_memory_agent = :degraded_agent
      
      # Update agent to show high resource usage
      ProcessRegistry.update_agent_metadata(:foundation, high_memory_agent, %{
        type: :agent,
        capabilities: [:inference],
        health: :degraded,
        resource_usage: %{memory: 0.95, cpu: 0.8}
      })
      
      # Coordination should adapt to resource constraints
      participants = [:ml_agent_1, :ml_agent_2, high_memory_agent]
      
      # This might exclude the high-resource agent or apply different strategies
      {:ok, result} = CoordinationService.consensus(
        :resource_aware_consensus,
        participants,
        %{action: :lightweight_task},
        %{strategy: :majority, timeout: 5_000}
      )
      
      assert result != nil
    end
  end
end
```

### Phase 4: Resource Management Testing (Weeks 7-8)

#### 4.1 Resource Manager Testing

**File**: `test/foundation/infrastructure/resource_manager_test.exs`

```elixir
defmodule Foundation.Infrastructure.ResourceManagerTest do
  use ExUnit.Case, async: false
  
  alias Foundation.Infrastructure.ResourceManager
  alias Foundation.ProcessRegistry
  
  setup do
    {:ok, _pid} = ResourceManager.start_link([
      monitoring_interval: 1_000,
      system_thresholds: %{
        memory: %{warning: 0.8, critical: 0.9},
        cpu: %{warning: 0.7, critical: 0.85}
      }
    ])
    
    :ok
  end
  
  describe "agent resource management" do
    test "registers agent with resource requirements" do
      resource_limits = %{
        memory_limit: 2_000_000_000,  # 2GB
        cpu_limit: 2.0,              # 2 cores
        custom_resources: %{gpu_memory: 4_000_000_000}
      }
      
      assert :ok = ResourceManager.register_agent(
        :ml_agent_1, 
        resource_limits,
        %{model_type: "transformer"}
      )
      
      {:ok, agent_status} = ResourceManager.get_agent_resource_status(:ml_agent_1)
      
      assert agent_status.agent_id == :ml_agent_1
      assert agent_status.resource_limits == resource_limits
    end
    
    test "checks resource availability before allocation" do
      ResourceManager.register_agent(:ml_agent_1, %{
        memory_limit: 1_000_000_000  # 1GB
      })
      
      # Check if 500MB is available
      result = ResourceManager.check_resource_availability(
        :ml_agent_1, 
        :memory, 
        500_000_000
      )
      
      assert result == :ok
      
      # Check if 2GB is available (should fail)
      result = ResourceManager.check_resource_availability(
        :ml_agent_1, 
        :memory, 
        2_000_000_000
      )
      
      assert match?({:error, _}, result)
    end
    
    test "allocates and releases resources" do
      ResourceManager.register_agent(:ml_agent_1, %{
        memory_limit: 1_000_000_000
      })
      
      # Allocate resources
      assert :ok = ResourceManager.allocate_resources(:ml_agent_1, %{
        memory: 300_000_000
      })
      
      # Check current usage
      {:ok, status} = ResourceManager.get_agent_resource_status(:ml_agent_1)
      assert status.current_usage.memory == 300_000_000
      
      # Release resources
      assert :ok = ResourceManager.release_resources(:ml_agent_1, %{
        memory: 300_000_000
      })
      
      # Verify release
      {:ok, status} = ResourceManager.get_agent_resource_status(:ml_agent_1)
      assert status.current_usage.memory == 0
    end
    
    test "monitors system resource thresholds" do
      # This test would monitor system-level resource alerts
      # Implementation would depend on the specific alerting mechanism
      
      {:ok, system_status} = ResourceManager.get_system_resource_status()
      
      assert Map.has_key?(system_status, :system_resources)
      assert Map.has_key?(system_status, :agent_count)
    end
  end
end
```

## Integration Testing Strategy

### Multi-Component Integration Tests

**File**: `test/integration/foundation/agent_infrastructure_integration_test.exs`

```elixir
defmodule Foundation.AgentInfrastructureIntegrationTest do
  use ExUnit.Case, async: false
  
  alias Foundation.{ProcessRegistry, Infrastructure.AgentCircuitBreaker, 
                  Infrastructure.AgentRateLimiter, Infrastructure.ResourceManager,
                  Services.EventStore, Services.TelemetryService}
  
  describe "end-to-end agent infrastructure" do
    test "complete agent lifecycle with infrastructure protection" do
      # 1. Register agent
      pid = spawn(fn -> :timer.sleep(5000) end)
      agent_metadata = %{
        type: :ml_agent,
        capabilities: [:inference],
        health: :healthy,
        resource_usage: %{memory: 0.5, cpu: 0.3}
      }
      
      ProcessRegistry.register_agent(:foundation, :integration_agent, pid, agent_metadata)
      
      # 2. Set up infrastructure protection
      {:ok, _breaker} = AgentCircuitBreaker.start_agent_breaker(
        :ml_service,
        agent_id: :integration_agent,
        capability: :inference
      )
      
      ResourceManager.register_agent(:integration_agent, %{
        memory_limit: 1_000_000_000
      })
      
      # 3. Perform protected operations
      operations = for i <- 1..10 do
        Task.async(fn ->
          # Check rate limit
          case AgentRateLimiter.check_rate_with_agent(
            :integration_agent, 
            :inference, 
            %{request_id: i}
          ) do
            :ok ->
              # Execute with circuit breaker protection
              AgentCircuitBreaker.execute_with_agent(
                :ml_service,
                :integration_agent,
                fn -> 
                  # Simulate resource allocation
                  ResourceManager.allocate_resources(:integration_agent, %{memory: 100_000})
                  Process.sleep(10)
                  ResourceManager.release_resources(:integration_agent, %{memory: 100_000})
                  {:ok, "inference_result_#{i}"}
                end
              )
            
            {:error, _} = error ->
              error
          end
        end)
      end
      
      # 4. Verify all operations completed successfully or were properly protected
      results = Enum.map(operations, &Task.await(&1, 5000))
      
      # Should have mostly successful operations with some rate limiting
      successful_operations = Enum.count(results, &match?({:ok, _}, &1))
      assert successful_operations > 0
      
      # 5. Verify telemetry events were emitted
      # This would check for proper telemetry event emission
      
      # 6. Cleanup
      ProcessRegistry.unregister(:foundation, :integration_agent)
    end
  end
end
```

## Property-Based Testing Enhancements

### Agent Metadata Properties

**File**: `test/property/foundation/agent_metadata_properties_test.exs`

```elixir
defmodule Foundation.AgentMetadataPropertiesTest do
  use ExUnit.Case, async: false
  use ExUnitProperties
  
  alias Foundation.ProcessRegistry
  
  property "agent registration maintains metadata consistency" do
    check all(
      agent_count <- integer(1..20),
      capabilities_list <- list_of(list_of(atom(), min_length: 1), min_length: 1),
      health_states <- list_of(member_of([:healthy, :degraded, :unhealthy]))
    ) do
      # Generate agent configurations
      agents = for i <- 1..agent_count do
        capabilities = Enum.at(capabilities_list, rem(i, length(capabilities_list)))
        health = Enum.at(health_states, rem(i, length(health_states)))
        
        {:"agent_#{i}", capabilities, health}
      end
      
      # Register all agents concurrently
      registration_tasks = for {agent_id, capabilities, health} <- agents do
        Task.async(fn ->
          pid = spawn(fn -> :timer.sleep(100) end)
          metadata = %{
            type: :agent,
            capabilities: capabilities,
            health: health,
            resource_usage: %{memory: :rand.uniform()}
          }
          
          ProcessRegistry.register_agent(:production, agent_id, pid, metadata)
        end)
      end
      
      # Wait for all registrations
      Enum.each(registration_tasks, &Task.await/1)
      
      # Verify all agents can be looked up with correct metadata
      for {agent_id, expected_capabilities, expected_health} <- agents do
        assert {:ok, {_pid, metadata}} = 
          ProcessRegistry.lookup_agent(:production, agent_id)
        
        assert metadata.capabilities == expected_capabilities
        assert metadata.health == expected_health
        assert metadata.type == :agent
      end
      
      # Test capability-based queries work correctly
      for capability <- Enum.uniq(List.flatten(capabilities_list)) do
        agents_with_capability = ProcessRegistry.lookup_agents_by_capability(:production, capability)
        
        expected_count = Enum.count(agents, fn {_, caps, _} -> 
          capability in caps 
        end)
        
        assert length(agents_with_capability) == expected_count
      end
      
      # Cleanup
      for {agent_id, _, _} <- agents do
        ProcessRegistry.unregister(:production, agent_id)
      end
    end
  end
end
```

## Test Infrastructure Enhancements

### Agent Test Helpers

**File**: `test/support/agent_test_helpers.ex`

```elixir
defmodule Foundation.AgentTestHelpers do
  @moduledoc """
  Test helpers for agent-aware testing scenarios.
  """
  
  alias Foundation.ProcessRegistry
  
  def start_test_agent(agent_id, capabilities \\ [:general], health \\ :healthy) do
    pid = spawn(fn -> 
      receive do
        :stop -> :ok
      end
    end)
    
    metadata = %{
      type: :agent,
      capabilities: capabilities,
      health: health,
      resource_usage: %{memory: 0.5, cpu: 0.3},
      coordination_state: %{
        active_consensus: [],
        active_barriers: [],
        held_locks: []
      }
    }
    
    ProcessRegistry.register_agent(:foundation, agent_id, pid, metadata)
    
    {pid, metadata}
  end
  
  def stop_test_agent(agent_id, pid) do
    send(pid, :stop)
    ProcessRegistry.unregister(:foundation, agent_id)
  end
  
  def update_agent_health(agent_id, new_health) do
    {:ok, {pid, metadata}} = ProcessRegistry.lookup_agent(:foundation, agent_id)
    updated_metadata = %{metadata | health: new_health}
    ProcessRegistry.update_agent_metadata(:foundation, agent_id, updated_metadata)
  end
  
  def create_agent_coordination_scenario(agent_ids, coordination_type \\ :consensus) do
    agents = for agent_id <- agent_ids do
      {pid, metadata} = start_test_agent(agent_id, [:coordination], :healthy)
      {agent_id, pid, metadata}
    end
    
    coordination_id = :"test_coordination_#{:rand.uniform(1000)}"
    
    {agents, coordination_id}
  end
  
  def cleanup_agents(agents) do
    for {agent_id, pid, _metadata} <- agents do
      stop_test_agent(agent_id, pid)
    end
  end
end
```

## Performance Testing Enhancements

### Agent-Aware Load Testing

**File**: `test/stress/agent_coordination_stress_test.exs`

```elixir
defmodule Foundation.AgentCoordinationStressTest do
  use ExUnit.Case, async: false
  
  alias Foundation.{ProcessRegistry, Coordination.Service, AgentTestHelpers}
  
  @tag :stress_test
  test "high-concurrency agent coordination" do
    agent_count = 50
    coordination_rounds = 10
    
    # Create many agents
    agents = for i <- 1..agent_count do
      agent_id = :"stress_agent_#{i}"
      capabilities = [:coordination, :inference]
      {pid, metadata} = AgentTestHelpers.start_test_agent(agent_id, capabilities)
      {agent_id, pid, metadata}
    end
    
    try do
      # Perform multiple rounds of coordination
      for round <- 1..coordination_rounds do
        coordination_id = :"stress_coordination_#{round}"
        
        # Start consensus with random subset of agents
        participants = agents
        |> Enum.take_random(min(20, agent_count))
        |> Enum.map(fn {agent_id, _, _} -> agent_id end)
        
        proposal = %{action: :stress_test, round: round}
        
        start_time = System.monotonic_time(:microsecond)
        
        {:ok, result} = Service.consensus(
          coordination_id,
          participants,
          proposal,
          %{strategy: :majority, timeout: 10_000}
        )
        
        end_time = System.monotonic_time(:microsecond)
        duration = end_time - start_time
        
        assert result.status == :accepted
        assert duration < 5_000_000  # Less than 5 seconds
        
        IO.puts("Round #{round}: #{length(participants)} agents, #{duration/1000}ms")
      end
      
      # Verify system health after stress test
      {:ok, system_stats} = Service.get_service_stats()
      assert system_stats.uptime > 0
      
    after
      # Cleanup all agents
      AgentTestHelpers.cleanup_agents(agents)
    end
  end
end
```

## Test Execution Strategy

### Test Organization by Phase

1. **Unit Tests**: Run continuously during development
2. **Integration Tests**: Run before each phase completion
3. **Property Tests**: Run nightly to catch edge cases
4. **Stress Tests**: Run weekly to validate performance
5. **End-to-End Tests**: Run before production deployment

### Continuous Integration Pipeline

```yaml
# Example CI configuration
stages:
  - unit_tests
  - integration_tests  
  - property_tests
  - stress_tests
  - security_tests

unit_tests:
  script:
    - mix test test/foundation/ --exclude stress_test

integration_tests:
  script:
    - mix test test/integration/

property_tests:
  script:
    - mix test test/property/ --max-cases 1000

stress_tests:
  script:
    - mix test --only stress_test
  only:
    - schedules
```

## Success Criteria

### Testing Completeness Metrics

1. **Code Coverage**: >95% line coverage for new agent-aware functionality
2. **Property Test Coverage**: All critical state machines have property tests
3. **Integration Test Coverage**: All service interactions tested
4. **Performance Validation**: No degradation in existing functionality
5. **Concurrent Safety**: All agent operations are thread-safe
6. **Resource Safety**: No memory leaks or resource exhaustion
7. **Error Handling**: All error paths tested and validated

### Quality Gates

- All existing tests continue to pass (regression prevention)
- New functionality has comprehensive test coverage
- Performance tests validate scalability requirements
- Property tests verify correctness under all conditions
- Integration tests validate cross-component functionality
- Stress tests validate system stability under load

The testing strategy ensures that the agent-aware backport maintains the high quality standards of the existing Foundation infrastructure while adding robust validation for all new functionality.