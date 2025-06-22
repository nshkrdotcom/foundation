# MABEAM Testing Guide

## Overview

This guide provides comprehensive testing strategies and best practices for the MABEAM (Multi-Agent BEAM) system. It covers unit testing, integration testing, performance testing, and coordination protocol testing.

## Table of Contents

1. [Testing Philosophy](#testing-philosophy)
2. [Test Organization](#test-organization)
3. [Unit Testing](#unit-testing)
4. [Integration Testing](#integration-testing)
5. [Performance Testing](#performance-testing)
6. [Coordination Protocol Testing](#coordination-protocol-testing)
7. [Test Utilities](#test-utilities)
8. [Best Practices](#best-practices)

---

## Testing Philosophy

### MABEAM Testing Principles

1. **Isolation**: Each test should be independent and not affect others
2. **Determinism**: Tests should produce consistent results
3. **Completeness**: Cover all public APIs and critical paths
4. **Performance**: Include performance regression testing
5. **Real-world Scenarios**: Test realistic coordination scenarios

### Test Categories

- **Unit Tests**: Individual module functionality
- **Integration Tests**: Service interaction testing
- **Performance Tests**: Load and stress testing
- **Protocol Tests**: Coordination algorithm validation
- **End-to-End Tests**: Complete workflow testing

---

## Test Organization

### Test Directory Structure

```
test/
├── foundation/
│   └── mabeam/
│       ├── types_test.exs              # Type definitions
│       ├── core_test.exs               # Core orchestrator
│       ├── agent_registry_test.exs     # Agent lifecycle
│       ├── coordination_test.exs       # Basic coordination
│       ├── telemetry_test.exs          # Telemetry system
│       ├── coordination/
│       │   ├── auction_test.exs        # Auction mechanisms
│       │   └── market_test.exs         # Market mechanisms
│       ├── integration_test.exs        # Service integration
│       ├── performance_test.exs        # Performance benchmarks
│       └── service_behaviour_integration_test.exs
```

### Test Naming Convention

```elixir
# Pattern: describe "function_name" do
describe "register_agent/2" do
  test "successfully registers valid agent" do
    # Test implementation
  end
  
  test "returns error for invalid configuration" do
    # Test implementation
  end
end
```

---

## Unit Testing

### Testing MABEAM.Types

```elixir
defmodule Foundation.MABEAM.TypesTest do
  use ExUnit.Case, async: true
  alias Foundation.MABEAM.Types

  describe "new_agent/3" do
    test "creates agent with default capabilities" do
      agent = Types.new_agent(:worker_1, :worker)
      
      assert agent.id == :worker_1
      assert agent.type == :worker
      assert agent.status == :initializing
      assert :variable_access in agent.capabilities
    end

    test "creates agent with custom capabilities" do
      agent = Types.new_agent(:coord_1, :coordinator,
        capabilities: [:consensus, :negotiation]
      )
      
      assert agent.capabilities == [:consensus, :negotiation]
    end
  end

  describe "new_variable/4" do
    test "creates variable with default settings" do
      var = Types.new_variable(:counter, 0, :agent_1)
      
      assert var.name == :counter
      assert var.value == 0
      assert var.access_mode == :public
      assert var.version == 1
    end
  end
end
```

### Testing MABEAM.Core

```elixir
defmodule Foundation.MABEAM.CoreTest do
  use Foundation.TestCase
  alias Foundation.MABEAM.Core

  setup do
    {:ok, _pid} = start_supervised(Core)
    :ok
  end

  describe "register_orchestration_variable/1" do
    test "registers valid variable" do
      variable = %{
        name: :test_var,
        type: :configuration,
        access_mode: :public,
        initial_value: %{setting: "test"}
      }

      assert :ok = Core.register_orchestration_variable(variable)
    end

    test "rejects invalid variable" do
      variable = %{name: nil}  # Invalid variable
      
      assert {:error, _reason} = Core.register_orchestration_variable(variable)
    end
  end
end
```

---

## Integration Testing

### Service Integration Testing

```elixir
defmodule Foundation.MABEAM.IntegrationTest do
  use Foundation.TestCase
  
  alias Foundation.MABEAM.{Core, AgentRegistry, Coordination, Telemetry}

  setup do
    # Start all MABEAM services
    {:ok, _} = start_supervised(Core)
    {:ok, _} = start_supervised(AgentRegistry)
    {:ok, _} = start_supervised(Coordination)
    {:ok, _} = start_supervised(Telemetry)
    
    :ok
  end

  describe "end-to-end coordination" do
    test "complete agent coordination workflow" do
      # 1. Register agents
      config = %{
        module: MockAgent,
        args: [],
        type: :worker,
        capabilities: [:coordination]
      }
      
      assert :ok = AgentRegistry.register_agent(:agent1, config)
      assert :ok = AgentRegistry.register_agent(:agent2, config)

      # 2. Start agents
      assert {:ok, _pid1} = AgentRegistry.start_agent(:agent1)
      assert {:ok, _pid2} = AgentRegistry.start_agent(:agent2)

      # 3. Register coordination protocol
      protocol = %{
        name: :test_consensus,
        type: :consensus,
        algorithm: &simple_consensus/1,
        timeout: 5000
      }
      
      assert :ok = Coordination.register_protocol(:test_consensus, protocol)

      # 4. Execute coordination
      assert {:ok, results} = Coordination.coordinate(
        :test_consensus,
        [:agent1, :agent2],
        %{question: "proceed?", options: [:yes, :no]}
      )

      # 5. Verify results
      assert length(results) == 2
      assert Enum.all?(results, &(&1.status == :success))

      # 6. Check telemetry
      Process.sleep(100)  # Allow telemetry to be recorded
      assert {:ok, metrics} = Telemetry.get_coordination_metrics(:test_consensus, :last_minute)
      assert metrics.total_coordinations > 0
    end
  end

  defp simple_consensus(_context) do
    {:ok, %{decision: :yes, confidence: 1.0}}
  end
end
```

---

## Performance Testing

### Performance Test Framework

```elixir
defmodule Foundation.MABEAM.PerformanceTest do
  use ExUnit.Case
  
  @moduletag :performance
  @moduletag timeout: 60_000

  alias Foundation.MABEAM.{Core, AgentRegistry, Coordination}

  setup_all do
    # Start services for performance testing
    {:ok, _} = start_supervised(Core)
    {:ok, _} = start_supervised(AgentRegistry)
    {:ok, _} = start_supervised(Coordination)
    
    :ok
  end

  describe "agent registration performance" do
    test "registers 1000 agents within time limit" do
      start_time = System.monotonic_time(:millisecond)
      
      # Register 1000 agents
      for i <- 1..1000 do
        config = %{
          module: MockAgent,
          args: [id: i],
          type: :worker
        }
        
        agent_id = String.to_atom("agent_#{i}")
        assert :ok = AgentRegistry.register_agent(agent_id, config)
      end
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      # Should complete within 5 seconds
      assert duration < 5000, "Registration took #{duration}ms, expected < 5000ms"
      
      # Verify all agents are registered
      {:ok, agents} = AgentRegistry.list_agents()
      assert length(agents) == 1000
    end
  end

  describe "coordination performance" do
    test "coordinates 100 agents efficiently" do
      # Setup 100 agents
      agents = setup_test_agents(100)
      
      # Register simple consensus protocol
      protocol = %{
        name: :perf_consensus,
        type: :consensus,
        algorithm: &simple_consensus/1,
        timeout: 10_000
      }
      
      assert :ok = Coordination.register_protocol(:perf_consensus, protocol)
      
      # Measure coordination time
      start_time = System.monotonic_time(:millisecond)
      
      assert {:ok, results} = Coordination.coordinate(
        :perf_consensus,
        agents,
        %{question: "performance_test"}
      )
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      # Should complete within 2 seconds for 100 agents
      assert duration < 2000, "Coordination took #{duration}ms, expected < 2000ms"
      assert length(results) == 100
    end
  end

  defp setup_test_agents(count) do
    for i <- 1..count do
      agent_id = String.to_atom("perf_agent_#{i}")
      config = %{module: MockAgent, args: [id: i], type: :worker}
      
      :ok = AgentRegistry.register_agent(agent_id, config)
      {:ok, _pid} = AgentRegistry.start_agent(agent_id)
      
      agent_id
    end
  end

  defp simple_consensus(_context) do
    {:ok, %{decision: :agree, confidence: 1.0}}
  end
end
```

---

## Coordination Protocol Testing

### Auction Protocol Testing

```elixir
defmodule Foundation.MABEAM.Coordination.AuctionTest do
  use ExUnit.Case, async: true
  
  alias Foundation.MABEAM.Coordination.Auction

  describe "sealed-bid auction" do
    test "first-price auction selects highest bidder" do
      bids = [
        %{agent_id: :agent1, bid_amount: 100},
        %{agent_id: :agent2, bid_amount: 150},
        %{agent_id: :agent3, bid_amount: 120}
      ]

      {:ok, result} = Auction.run_auction(
        :test_resource,
        bids,
        auction_type: :sealed_bid,
        payment_rule: :first_price
      )

      assert result.winner == :agent2
      assert result.winning_bid == 150
      assert result.payment == 150
      assert result.efficiency > 0.9
    end

    test "second-price auction uses second-highest bid for payment" do
      bids = [
        %{agent_id: :agent1, bid_amount: 100},
        %{agent_id: :agent2, bid_amount: 150},
        %{agent_id: :agent3, bid_amount: 120}
      ]

      {:ok, result} = Auction.run_auction(
        :test_resource,
        bids,
        auction_type: :sealed_bid,
        payment_rule: :second_price
      )

      assert result.winner == :agent2
      assert result.winning_bid == 150
      assert result.payment == 120  # Second-highest bid
    end
  end

  describe "english auction" do
    test "ascending auction with multiple rounds" do
      agents = [:agent1, :agent2, :agent3]

      {:ok, result} = Auction.run_auction(
        :test_resource,
        agents,
        auction_type: :english,
        starting_price: 50,
        increment: 10,
        max_rounds: 10
      )

      assert result.winner in agents
      assert result.final_price >= 50
      assert is_list(result.rounds)
      assert length(result.rounds) > 0
    end
  end
end
```

### Market Protocol Testing

```elixir
defmodule Foundation.MABEAM.Coordination.MarketTest do
  use ExUnit.Case, async: true
  
  alias Foundation.MABEAM.Coordination.Market

  describe "market equilibrium" do
    test "finds equilibrium with simple supply and demand" do
      supply = [
        %{agent_id: :supplier1, quantity: 100, min_price: 50},
        %{agent_id: :supplier2, quantity: 150, min_price: 60}
      ]

      demand = [
        %{agent_id: :buyer1, quantity: 80, max_price: 70},
        %{agent_id: :buyer2, quantity: 120, max_price: 65}
      ]

      {:ok, equilibrium} = Market.find_equilibrium(supply, demand)

      assert equilibrium.price >= 50
      assert equilibrium.price <= 70
      assert equilibrium.quantity > 0
      assert equilibrium.efficiency > 0.8
      assert is_list(equilibrium.allocations)
    end

    test "handles no equilibrium case" do
      supply = [%{agent_id: :supplier1, quantity: 100, min_price: 80}]
      demand = [%{agent_id: :buyer1, quantity: 100, max_price: 50}]

      assert {:error, :no_equilibrium} = Market.find_equilibrium(supply, demand)
    end
  end

  describe "market simulation" do
    test "multi-period simulation with learning" do
      config = %{
        periods: 3,
        learning_enabled: true,
        learning_rate: 0.1,
        demand_variation: 0.1,
        supply_variation: 0.05
      }

      {:ok, result} = Market.simulate_market(:test_market, config)

      assert length(result.period_results) == 3
      assert result.overall_efficiency > 0.0
      assert result.price_stability >= 0.0
      assert is_map(result.learning_effects)
      assert is_list(result.agent_adaptations)
    end
  end
end
```

---

## Test Utilities

### Mock Agents

```elixir
defmodule MockAgent do
  @moduledoc "Mock agent for testing purposes"
  use GenServer

  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  def init(config) do
    {:ok, config}
  end

  def handle_call({:coordinate, _context}, _from, state) do
    # Simulate coordination response
    response = %{
      agent_id: Map.get(state, :id, :mock_agent),
      decision: :agree,
      confidence: 0.9,
      timestamp: DateTime.utc_now()
    }
    
    {:reply, {:ok, response}, state}
  end

  def handle_call({:bid, auction_context}, _from, state) do
    # Simulate bidding behavior
    base_bid = Map.get(auction_context, :starting_price, 50)
    bid_amount = base_bid + :rand.uniform(50)
    
    bid = %{
      agent_id: Map.get(state, :id, :mock_agent),
      bid_amount: bid_amount,
      metadata: %{strategy: :random}
    }
    
    {:reply, {:ok, bid}, state}
  end

  def handle_call(_msg, _from, state) do
    {:reply, :ok, state}
  end

  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
```

### Test Helpers

```elixir
defmodule Foundation.MABEAM.TestHelpers do
  @moduledoc "Helper functions for MABEAM testing"

  def setup_test_agents(count, opts \\ []) do
    type = Keyword.get(opts, :type, :worker)
    module = Keyword.get(opts, :module, MockAgent)
    
    for i <- 1..count do
      agent_id = String.to_atom("test_agent_#{i}")
      config = %{
        module: module,
        args: [id: i],
        type: type,
        capabilities: [:coordination, :variable_access]
      }
      
      :ok = Foundation.MABEAM.AgentRegistry.register_agent(agent_id, config)
      {:ok, _pid} = Foundation.MABEAM.AgentRegistry.start_agent(agent_id)
      
      agent_id
    end
  end

  def create_test_bids(agent_ids, opts \\ []) do
    base_amount = Keyword.get(opts, :base_amount, 50)
    variation = Keyword.get(opts, :variation, 20)
    
    Enum.map(agent_ids, fn agent_id ->
      bid_amount = base_amount + :rand.uniform(variation)
      %{
        agent_id: agent_id,
        bid_amount: bid_amount,
        metadata: %{test: true}
      }
    end)
  end

  def wait_for_coordination(timeout \\ 5000) do
    Process.sleep(100)
    :ok
  end

  def assert_coordination_success(results) do
    assert is_list(results)
    assert length(results) > 0
    assert Enum.all?(results, fn result ->
      Map.has_key?(result, :agent_id) and Map.has_key?(result, :decision)
    end)
  end

  def assert_auction_result(result) do
    assert Map.has_key?(result, :winner)
    assert Map.has_key?(result, :winning_bid)
    assert Map.has_key?(result, :payment)
    assert is_number(result.efficiency)
    assert result.efficiency >= 0.0 and result.efficiency <= 1.0
  end

  def assert_market_equilibrium(equilibrium) do
    assert Map.has_key?(equilibrium, :price)
    assert Map.has_key?(equilibrium, :quantity)
    assert Map.has_key?(equilibrium, :efficiency)
    assert is_list(equilibrium.allocations)
    assert is_number(equilibrium.price)
    assert equilibrium.price > 0
  end
end
```

---

## Best Practices

### Test Organization

1. **Group Related Tests**: Use `describe` blocks to group related functionality
2. **Clear Test Names**: Use descriptive test names that explain the scenario
3. **Setup and Teardown**: Use proper setup and cleanup for test isolation
4. **Async When Possible**: Use `async: true` for independent tests

### Test Data Management

1. **Factories**: Create data factories for complex test objects
2. **Fixtures**: Use fixtures for consistent test data
3. **Randomization**: Use controlled randomization for robustness
4. **Edge Cases**: Test boundary conditions and error cases

### Performance Testing

1. **Baseline Measurements**: Establish performance baselines
2. **Regression Detection**: Monitor for performance regressions
3. **Resource Monitoring**: Track memory and CPU usage during tests
4. **Realistic Load**: Use realistic data volumes and concurrency

### Coordination Testing

1. **Protocol Validation**: Test all coordination protocols thoroughly
2. **Failure Scenarios**: Test timeout and failure conditions
3. **Concurrent Coordination**: Test multiple simultaneous coordinations
4. **State Consistency**: Verify system state after coordination

### Continuous Integration

```bash
# Run all tests
mix test

# Run only unit tests
mix test --exclude integration --exclude performance

# Run performance tests
mix test --only performance

# Run with coverage
mix test --cover

# Run specific test file
mix test test/foundation/mabeam/coordination_test.exs
```

### Test Configuration

```elixir
# In config/test.exs
config :foundation, Foundation.MABEAM.Core,
  max_variables: 100,
  coordination_timeout: 1000

config :foundation, Foundation.MABEAM.AgentRegistry,
  max_agents: 100,
  health_check_interval: 1000

config :foundation, Foundation.MABEAM.Coordination,
  default_timeout: 1000,
  max_concurrent_coordinations: 10

config :foundation, Foundation.MABEAM.Telemetry,
  retention_minutes: 1,
  cleanup_interval_ms: 5000
```

---

## Conclusion

This testing guide provides a comprehensive framework for testing MABEAM systems. By following these practices:

- **Comprehensive Coverage**: All components and protocols are thoroughly tested
- **Performance Assurance**: Performance regressions are caught early
- **Reliability**: Tests are deterministic and isolated
- **Maintainability**: Test code is well-organized and documented
- **Confidence**: Comprehensive testing builds confidence in system reliability

Regular testing ensures MABEAM systems remain robust, performant, and reliable as they evolve and scale. 