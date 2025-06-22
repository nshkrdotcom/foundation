# MABEAM Phase 2: Agent Registry and Lifecycle (Foundation.MABEAM.AgentRegistry)

## Phase Overview

**Goal**: Implement robust agent lifecycle management with OTP supervision
**Duration**: 3-4 development cycles
**Prerequisites**: Phase 1 complete (Foundation.MABEAM.Core operational)

## Phase 2 Architecture

```
Foundation.MABEAM.AgentRegistry
├── Agent Lifecycle Management
├── OTP Supervision Integration
├── Agent State Tracking
├── Health Monitoring
└── Resource Management
```

## Step-by-Step Implementation

### Step 2.1: Agent Registry Core
**Duration**: 1 development cycle
**Checkpoint**: Basic agent registration and lookup, no warnings

#### Objectives
- Implement Foundation.MABEAM.AgentRegistry GenServer
- Agent registration and deregistration
- Agent lookup and enumeration
- Integration with Foundation.ProcessRegistry

#### TDD Approach

**Red Phase**: Create failing tests
```elixir
# test/foundation/mabeam/agent_registry_test.exs
defmodule Foundation.MABEAM.AgentRegistryTest do
  use ExUnit.Case, async: false
  
  alias Foundation.MABEAM.{AgentRegistry, Types}
  
  setup do
    start_supervised!(AgentRegistry)
    :ok
  end
  
  describe "agent registration" do
    test "registers agent with valid config" do
      agent_config = create_valid_agent_config()
      assert :ok = AgentRegistry.register_agent(:test_agent, agent_config)
      
      assert {:ok, ^agent_config} = AgentRegistry.get_agent_config(:test_agent)
    end
    
    test "rejects duplicate agent registration" do
      agent_config = create_valid_agent_config()
      :ok = AgentRegistry.register_agent(:test_agent, agent_config)
      
      assert {:error, :already_registered} = 
        AgentRegistry.register_agent(:test_agent, agent_config)
    end
    
    test "lists all registered agents" do
      configs = [
        {:agent1, create_valid_agent_config()},
        {:agent2, create_valid_agent_config()},
        {:agent3, create_valid_agent_config()}
      ]
      
      Enum.each(configs, fn {id, config} ->
        :ok = AgentRegistry.register_agent(id, config)
      end)
      
      {:ok, agents} = AgentRegistry.list_agents()
      assert length(agents) == 3
      assert Enum.all?([:agent1, :agent2, :agent3], &(&1 in Enum.map(agents, fn {id, _} -> id end)))
    end
  end
  
  describe "agent deregistration" do
    test "deregisters existing agent" do
      agent_config = create_valid_agent_config()
      :ok = AgentRegistry.register_agent(:test_agent, agent_config)
      
      assert :ok = AgentRegistry.deregister_agent(:test_agent)
      assert {:error, :not_found} = AgentRegistry.get_agent_config(:test_agent)
    end
    
    test "handles deregistration of non-existent agent" do
      assert {:error, :not_found} = AgentRegistry.deregister_agent(:non_existent)
    end
  end
end
```

**Green Phase**: Implement agent registry
```elixir
# lib/foundation/mabeam/agent_registry.ex
defmodule Foundation.MABEAM.AgentRegistry do
  @moduledoc """
  Registry for managing agent lifecycle, supervision, and metadata.
  
  Provides fault-tolerant agent management with integration to OTP supervision
  trees and Foundation's process registry.
  """
  
  use GenServer
  use Foundation.Services.ServiceBehaviour
  
  alias Foundation.{ProcessRegistry, Events, Telemetry}
  alias Foundation.MABEAM.Types
  
  @type registry_state :: %{
    agents: %{atom() => agent_entry()},
    supervisors: %{atom() => pid()},
    health_monitors: %{atom() => reference()},
    metrics: registry_metrics()
  }
  
  @type agent_entry :: %{
    id: atom(),
    config: Types.agent_config(),
    pid: pid() | nil,
    status: agent_status(),
    started_at: DateTime.t(),
    last_health_check: DateTime.t(),
    restart_count: non_neg_integer()
  }
  
  @type agent_status :: :registered | :starting | :active | :stopping | :failed | :migrating
  
  ## Public API
  
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @spec register_agent(atom(), Types.agent_config()) :: :ok | {:error, term()}
  def register_agent(agent_id, config) do
    GenServer.call(__MODULE__, {:register_agent, agent_id, config})
  end
  
  @spec deregister_agent(atom()) :: :ok | {:error, term()}
  def deregister_agent(agent_id) do
    GenServer.call(__MODULE__, {:deregister_agent, agent_id})
  end
  
  @spec get_agent_config(atom()) :: {:ok, Types.agent_config()} | {:error, term()}
  def get_agent_config(agent_id) do
    GenServer.call(__MODULE__, {:get_agent_config, agent_id})
  end
  
  @spec list_agents() :: {:ok, [{atom(), agent_entry()}]} | {:error, term()}
  def list_agents() do
    GenServer.call(__MODULE__, :list_agents)
  end
  
  ## GenServer Implementation
  
  @impl true
  def init(opts) do
    case Foundation.Services.ServiceRegistry.register_service(__MODULE__, opts) do
      :ok ->
        state = initialize_registry_state(opts)
        setup_telemetry()
        {:ok, state}
      
      {:error, reason} ->
        {:stop, reason}
    end
  end
  
  @impl true
  def handle_call({:register_agent, agent_id, config}, _from, state) do
    case Map.get(state.agents, agent_id) do
      nil ->
        case Types.validate_agent_config(config) do
          {:ok, validated_config} ->
            entry = create_agent_entry(agent_id, validated_config)
            new_state = %{state | agents: Map.put(state.agents, agent_id, entry)}
            
            emit_agent_registered_event(agent_id, validated_config)
            {:reply, :ok, new_state}
          
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
      
      _existing ->
        {:reply, {:error, :already_registered}, state}
    end
  end
  
  @impl true
  def handle_call({:deregister_agent, agent_id}, _from, state) do
    case Map.get(state.agents, agent_id) do
      nil ->
        {:reply, {:error, :not_found}, state}
      
      entry ->
        # Stop agent if running
        new_state = case entry.pid do
          nil -> state
          pid -> stop_agent_process(pid, agent_id, state)
        end
        
        final_state = %{new_state | agents: Map.delete(new_state.agents, agent_id)}
        emit_agent_deregistered_event(agent_id)
        {:reply, :ok, final_state}
    end
  end
  
  # ... additional GenServer callbacks
end
```

**Refactor Phase**: Optimize lookup performance, add validation

#### Deliverables
- [ ] `Foundation.MABEAM.AgentRegistry` GenServer with core functionality
- [ ] Agent registration/deregistration with validation
- [ ] Integration with Foundation services
- [ ] Comprehensive test suite
- [ ] Performance benchmarks for registry operations

---

### Step 2.2: Agent Lifecycle Management
**Duration**: 1-2 development cycles
**Checkpoint**: Agents can be started, stopped, and monitored

#### Objectives
- Implement agent starting and stopping
- Health monitoring and status tracking
- Restart policies and fault tolerance
- Resource tracking and limits

#### TDD Approach

**Red Phase**: Test agent lifecycle
```elixir
describe "agent lifecycle" do
  test "starts registered agent" do
    agent_config = create_valid_agent_config()
    :ok = AgentRegistry.register_agent(:test_agent, agent_config)
    
    assert {:ok, pid} = AgentRegistry.start_agent(:test_agent)
    assert is_pid(pid)
    assert Process.alive?(pid)
    
    {:ok, status} = AgentRegistry.get_agent_status(:test_agent)
    assert status.status == :active
    assert status.pid == pid
  end
  
  test "stops running agent" do
    agent_config = create_valid_agent_config()
    :ok = AgentRegistry.register_agent(:test_agent, agent_config)
    {:ok, pid} = AgentRegistry.start_agent(:test_agent)
    
    assert :ok = AgentRegistry.stop_agent(:test_agent)
    refute Process.alive?(pid)
    
    {:ok, status} = AgentRegistry.get_agent_status(:test_agent)
    assert status.status == :registered
    assert status.pid == nil
  end
  
  test "handles agent crashes with restart policy" do
    agent_config = create_crashy_agent_config()
    :ok = AgentRegistry.register_agent(:crashy_agent, agent_config)
    {:ok, pid1} = AgentRegistry.start_agent(:crashy_agent)
    
    # Crash the agent
    Process.exit(pid1, :kill)
    
    # Should restart automatically
    eventually(fn ->
      {:ok, status} = AgentRegistry.get_agent_status(:crashy_agent)
      assert status.status == :active
      assert status.pid != pid1
      assert status.restart_count == 1
    end)
  end
end
```

**Green Phase**: Implement lifecycle management

**Refactor Phase**: Optimize restart policies and monitoring

#### Deliverables
- [ ] Agent starting and stopping functionality
- [ ] Health monitoring with configurable intervals
- [ ] Restart policies (permanent, temporary, transient)
- [ ] Resource usage tracking
- [ ] Comprehensive lifecycle tests

---

### Step 2.3: OTP Supervision Integration
**Duration**: 1 development cycle
**Checkpoint**: Agents run under proper OTP supervision

#### Objectives
- DynamicSupervisor for agent processes
- Proper supervision tree integration
- Graceful shutdown handling
- Supervisor strategy configuration

#### TDD Approach

**Red Phase**: Test supervision integration
```elixir
describe "supervision integration" do
  test "agents run under supervision" do
    agent_config = create_valid_agent_config()
    :ok = AgentRegistry.register_agent(:supervised_agent, agent_config)
    {:ok, pid} = AgentRegistry.start_agent(:supervised_agent)
    
    # Verify agent is under supervision
    {:ok, supervisor_pid} = AgentRegistry.get_agent_supervisor(:supervised_agent)
    assert is_pid(supervisor_pid)
    
    children = DynamicSupervisor.which_children(supervisor_pid)
    assert Enum.any?(children, fn {_, child_pid, _, _} -> child_pid == pid end)
  end
  
  test "supervisor handles agent failures according to strategy" do
    agent_config = create_agent_config_with_strategy(:one_for_one)
    :ok = AgentRegistry.register_agent(:strategy_agent, agent_config)
    {:ok, _pid} = AgentRegistry.start_agent(:strategy_agent)
    
    # Test strategy behavior
    # ... specific strategy tests
  end
end
```

**Green Phase**: Implement supervision integration

**Refactor Phase**: Optimize supervision strategies

#### Deliverables
- [ ] DynamicSupervisor for agent processes
- [ ] Configurable supervision strategies
- [ ] Graceful shutdown procedures
- [ ] Supervisor health monitoring

---

### Step 2.4: Advanced Agent Management
**Duration**: 1 development cycle
**Checkpoint**: Resource management and advanced features

#### Objectives
- Resource allocation and monitoring
- Agent migration support (preparation for clustering)
- Performance metrics and optimization
- Configuration hot-reloading

#### TDD Approach

**Red Phase**: Test advanced features
```elixir
describe "resource management" do
  test "tracks agent resource usage" do
    agent_config = create_resource_intensive_agent_config()
    :ok = AgentRegistry.register_agent(:resource_agent, agent_config)
    {:ok, _pid} = AgentRegistry.start_agent(:resource_agent)
    
    {:ok, metrics} = AgentRegistry.get_agent_metrics(:resource_agent)
    assert metrics.memory_usage > 0
    assert metrics.cpu_usage >= 0.0
  end
  
  test "enforces resource limits" do
    agent_config = create_agent_config_with_limits(%{memory: 100_000, cpu: 0.1})
    :ok = AgentRegistry.register_agent(:limited_agent, agent_config)
    
    # Test that agent is terminated if it exceeds limits
    # ...
  end
end

describe "configuration management" do
  test "hot-reloads agent configuration" do
    agent_config = create_valid_agent_config()
    :ok = AgentRegistry.register_agent(:configurable_agent, agent_config)
    {:ok, _pid} = AgentRegistry.start_agent(:configurable_agent)
    
    new_config = Map.put(agent_config, :some_setting, :new_value)
    assert :ok = AgentRegistry.update_agent_config(:configurable_agent, new_config)
    
    {:ok, current_config} = AgentRegistry.get_agent_config(:configurable_agent)
    assert current_config.some_setting == :new_value
  end
end
```

**Green Phase**: Implement advanced features

**Refactor Phase**: Optimize performance and resource usage

#### Deliverables
- [ ] Resource monitoring and enforcement
- [ ] Configuration hot-reloading
- [ ] Performance metrics collection
- [ ] Agent migration preparation

---

## Phase 2 Completion Criteria

### Functional Requirements
- [ ] Agent registration and lifecycle management operational
- [ ] OTP supervision integration complete
- [ ] Health monitoring and restart policies working
- [ ] Resource management implemented
- [ ] Configuration management functional

### Quality Requirements
- [ ] Zero dialyzer warnings
- [ ] Zero credo --strict violations
- [ ] >95% test coverage
- [ ] No compiler warnings
- [ ] Performance benchmarks for all operations
- [ ] Memory usage under acceptable limits

### Documentation Requirements
- [ ] Complete API documentation
- [ ] Agent configuration guide
- [ ] Supervision strategy guide
- [ ] Troubleshooting and monitoring guide

## Phase 2 Deliverables Summary

1. **Foundation.MABEAM.AgentRegistry** - Complete agent lifecycle management
2. **Agent Supervision** - OTP integration with configurable strategies
3. **Health Monitoring** - Comprehensive agent health tracking
4. **Resource Management** - Usage tracking and limit enforcement
5. **Configuration Management** - Hot-reloading and validation
6. **Test Suite** - Comprehensive test coverage for all functionality
7. **Documentation** - Complete API and usage guides

## Integration with Phase 1

The AgentRegistry integrates with Foundation.MABEAM.Core:
- Core orchestrator uses AgentRegistry to start/stop agents
- Variables can query agent status through the registry
- Coordination results are executed via the registry
- Performance metrics flow from registry to core

## Next Phase

Upon successful completion of Phase 2 with all quality gates passing:
- Proceed to **Phase 3: Basic Coordination**
- Begin with `MABEAM_PHASE_03_COORDINATION.md` 