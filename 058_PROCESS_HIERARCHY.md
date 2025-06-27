# Process Hierarchy & Supervision Architecture

## Overview

This document defines the complete process supervision architecture for the Foundation + MABEAM system, addressing the critical patterns for process lifecycle management, fault tolerance, and clean shutdown procedures.

## Foundation Layer Process Hierarchy

### Application Supervision Tree

```
Foundation.Application (Supervisor, strategy: :one_for_one)
├── Foundation.ProcessRegistry (GenServer)
│   ├── ETS Table: :foundation_processes
│   ├── Namespace: :production | :test  
│   └── Responsibilities: Process discovery, service registration
│
├── Foundation.ServiceRegistry (GenServer) 
│   ├── Depends on: ProcessRegistry
│   ├── Responsibilities: High-level service coordination, dependency management
│   └── Fallback: ConfigServer for service unavailability
│
├── Foundation.TelemetryService (GenServer)
│   ├── Responsibilities: Metrics collection, event emission
│   └── Integration: :telemetry events, monitoring dashboards
│
├── Foundation.ConfigServer (GenServer)
│   ├── Responsibilities: Configuration management, change notifications
│   ├── Storage: ETS table with persistent backing
│   └── Change notifications: PubSub pattern
│
├── Foundation.EventStore (GenServer)  
│   ├── Responsibilities: Event persistence, querying, replay
│   ├── Storage: Persistent term storage
│   └── Pattern: Event sourcing with append-only log
│
├── Foundation.ConnectionManager (GenServer)
│   ├── Responsibilities: Network topology, node management
│   └── Distribution: Multi-node cluster coordination
│
├── Foundation.RateLimiter (GenServer)
│   ├── Responsibilities: Traffic control, resource protection
│   └── Algorithm: Token bucket with ETS backing
│
├── Foundation.TaskSupervisor (DynamicSupervisor)
│   ├── Strategy: :one_for_one
│   ├── Responsibilities: Ad-hoc task execution
│   └── Max children: :infinity
│
├── Foundation.HealthMonitor (GenServer)
│   ├── Responsibilities: System health tracking, alerting
│   ├── Monitors: All Foundation services + MABEAM components
│   └── Integration: Telemetry pipeline
│
└── Foundation.ServiceMonitor (GenServer)
    ├── Responsibilities: Service availability monitoring
    ├── Health checks: Periodic service pings
    └── Recovery: Automatic restart coordination
```

### Process Registry Architecture

#### **Namespace Isolation Pattern**
```elixir
# Process registration with namespace isolation
# Production: {:production, service_name}
# Test: {:test, service_name}

ProcessRegistry.register({namespace, :config_server}, self())
ProcessRegistry.lookup({namespace, :config_server})
```

#### **Service Discovery Flow**
```
Client Request → ProcessRegistry.lookup(service) → 
  ├─ Found: Return PID
  ├─ Not Found: Check ServiceRegistry for startup
  └─ Unavailable: Fallback to ConfigServer/ETS cache
```

## MABEAM Layer Process Hierarchy

### Agent Supervision Architecture

```
MABEAM.Application (Supervisor, strategy: :one_for_one)
├── MABEAM.Core (GenServer)
│   ├── Responsibilities: Universal Variable Orchestration
│   ├── State: Variable spaces, optimization contexts
│   └── Coordination: Parameter optimization across agents
│
├── MABEAM.AgentRegistry (GenServer) 
│   ├── Responsibilities: Agent metadata, lifecycle tracking
│   ├── State: Agent configurations, status, metrics
│   ├── ETS Table: Agent registry with fast lookups
│   └── Process monitoring: Automatic status updates on crashes
│
├── MABEAM.AgentSupervisor (DynamicSupervisor)
│   ├── Strategy: :one_for_one  
│   ├── Max children: :infinity
│   ├── Responsibilities: Agent process lifecycle
│   ├── Child spec: {agent_module, init_args, id: agent_id}
│   └── Termination: By PID using DynamicSupervisor.terminate_child/2
│
├── MABEAM.CoordinationSupervisor (Supervisor, strategy: :one_for_one)
│   ├── MABEAM.Coordination (GenServer)
│   │   ├── Responsibilities: Multi-agent consensus protocols
│   │   ├── Algorithms: Raft-like consensus, leader election
│   │   └── State: Coordination contexts, voting records
│   │
│   ├── MABEAM.Economics (GenServer)
│   │   ├── Responsibilities: Resource allocation, cost optimization
│   │   ├── State: Resource usage, cost models
│   │   └── Integration: LoadBalancer for workload distribution
│   │
│   └── MABEAM.LoadBalancer (GenServer)
│       ├── Responsibilities: Workload distribution across agents
│       ├── Algorithms: Round-robin, weighted distribution
│       └── Metrics: Agent performance, resource utilization
│
└── MABEAM.PerformanceMonitor (GenServer)
    ├── Responsibilities: Agent performance tracking
    ├── Metrics: Throughput, latency, resource usage
    ├── Integration: Foundation telemetry pipeline
    └── Alerting: Performance degradation detection
```

## Agent Lifecycle Management

### **Critical Supervision Pattern Fix**

The current issue stems from mixing DynamicSupervisor behavior with GenServer callbacks. Here's the correct architecture:

#### **AgentSupervisor (Pure DynamicSupervisor)**
```elixir
defmodule MABEAM.AgentSupervisor do
  use DynamicSupervisor

  # ONLY DynamicSupervisor callbacks - NO GenServer callbacks
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  # Direct function calls for agent management
  def start_agent(agent_module, init_args, agent_id) do
    child_spec = {agent_module, [init_args, [name: agent_id]]}
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  def stop_agent(agent_pid) when is_pid(agent_pid) do
    # CORRECT: Use PID directly with DynamicSupervisor
    DynamicSupervisor.terminate_child(__MODULE__, agent_pid)
  end
end
```

#### **AgentRegistry (Pure GenServer)**
```elixir
defmodule MABEAM.AgentRegistry do
  use GenServer

  # Agent lifecycle coordination
  def register_agent(agent_id, config) do
    GenServer.call(__MODULE__, {:register, agent_id, config})
  end

  def start_agent(agent_id) do
    with {:ok, config} <- get_agent_config(agent_id),
         {:ok, pid} <- MABEAM.AgentSupervisor.start_agent(
           config.module, config.init_args, agent_id
         ),
         :ok <- GenServer.call(__MODULE__, {:agent_started, agent_id, pid}) do
      Process.monitor(pid)  # Monitor for crash detection
      {:ok, pid}
    end
  end

  def stop_agent(agent_id) do
    with {:ok, pid} <- get_agent_pid(agent_id),
         :ok <- MABEAM.AgentSupervisor.stop_agent(pid),
         :ok <- GenServer.call(__MODULE__, {:agent_stopped, agent_id}) do
      :ok
    end
  end

  # GenServer callbacks handle state management
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Update agent status on crash
    agent_id = find_agent_by_pid(state, pid)
    new_state = update_agent_status(state, agent_id, :crashed)
    {:noreply, new_state}
  end
end
```

### **Process Termination Sequence**

#### **Correct OTP Shutdown Pattern**
```
1. AgentRegistry.stop_agent(agent_id)
2. ├─ Lookup agent PID from registry state
3. ├─ MABEAM.AgentSupervisor.stop_agent(pid)
4. │  └─ DynamicSupervisor.terminate_child(__MODULE__, pid)
5. │     └─ OTP sends :shutdown signal to agent process
6. │        └─ Agent process terminates gracefully
7. ├─ Monitor receives {:DOWN, ...} message  
8. ├─ AgentRegistry updates agent status to :stopped
9. └─ Return :ok to caller
```

#### **Critical Fix: No Process.sleep Required**
Following SLEEP.md principles, the OTP supervision system guarantees:
- `DynamicSupervisor.terminate_child/2` returns after process termination
- Process monitors fire `{:DOWN, ...}` messages synchronously
- No artificial delays needed - trust OTP guarantees

## Fault Tolerance Patterns

### **Supervision Strategies**

#### **Foundation Services: :one_for_one**
- Individual service failures don't affect other services
- Failed services restart automatically with exponential backoff
- Dependency-aware startup order through ServiceRegistry

#### **Agent Processes: :one_for_one**  
- Agent failures are isolated to individual processes
- Failed agents can be restarted by coordination system
- Agent state is maintained separately in AgentRegistry

### **Error Recovery Patterns**

#### **Service Unavailability Handling**
```elixir
def get_service_pid(service_name) do
  case ProcessRegistry.lookup({namespace(), service_name}) do
    {:ok, pid} when is_pid(pid) -> 
      {:ok, pid}
    {:error, :not_found} -> 
      # Graceful fallback to ConfigServer
      ConfigServer.get_fallback_config(service_name)
    {:error, :process_dead} ->
      # Wait for supervisor restart
      Process.sleep(100)
      get_service_pid(service_name)  # Retry once
  end
end
```

#### **Agent Crash Recovery**
```elixir
def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
  agent_id = find_agent_by_pid(state, pid)
  
  case reason do
    :shutdown -> 
      # Expected termination
      update_agent_status(state, agent_id, :stopped)
    
    :normal ->
      # Successful completion
      update_agent_status(state, agent_id, :completed)
      
    _error ->
      # Unexpected crash - mark for potential restart
      update_agent_status(state, agent_id, :crashed)
      maybe_restart_agent(agent_id, reason)
  end
  
  {:noreply, new_state}
end
```

## Process Communication Patterns

### **Service-to-Service Communication**
```
GenServer.call(ServiceRegistry.get_pid(:config_server), request)
  ↓
ProcessRegistry.lookup({:production, :config_server})
  ↓
GenServer.call(config_server_pid, request)
```

### **Agent Coordination Communication**
```
MABEAM.Core → Variable Update → Coordination.broadcast_update(agents)
  ↓
For each agent: GenServer.cast(agent_pid, {:variable_update, variable, value})
  ↓
Agent processes update their internal state asynchronously
```

### **Event-Driven Communication**
```
Event Source → EventStore.append(event) → Event Processing →
Telemetry.emit(metrics) → Monitoring Dashboard → Alerts
```

## Performance & Scalability

### **Process Scaling Characteristics**
- **Foundation Services**: Fixed set (10-15 processes) regardless of load
- **Agent Processes**: Scales linearly with workload (1 process per agent)
- **BEAM Efficiency**: Supports millions of lightweight processes

### **Memory Management**
```elixir
# Agent processes have bounded memory via :max_heap_size
{:ok, pid} = Agent.start_link(fn -> %{} end, [
  max_heap_size: %{size: 1_000_000, kill: true, error_logger: true}
])
```

### **CPU Resource Management**
- Process priorities via `Process.flag(:priority, :high)` for critical services
- CPU quota management through external tools (systemd, Docker limits)
- Rate limiting prevents CPU exhaustion from runaway processes

## Testing & Development

### **Namespace Isolation for Testing**
```elixir
# Test configuration uses separate namespace
config :foundation, namespace: :test

# Production configuration  
config :foundation, namespace: :production
```

### **Supervision Tree Testing**
```elixir
# Test supervisor startup/shutdown
{:ok, pid} = Foundation.Application.start(:normal, [])
:ok = Foundation.Application.stop(pid)

# Verify all processes terminated
assert ProcessRegistry.count({:test, :all}) == 0
```

### **Agent Lifecycle Testing**
```elixir
# Test complete agent lifecycle
{:ok, agent_pid} = MABEAM.AgentRegistry.start_agent(:test_agent)
assert Process.alive?(agent_pid)

:ok = MABEAM.AgentRegistry.stop_agent(:test_agent) 
refute Process.alive?(agent_pid)  # Should be false after stop
```

## Troubleshooting Guide

### **Common Supervision Issues**

#### **Issue: Processes Not Terminating**
```elixir
# WRONG: Using wrong termination method
DynamicSupervisor.terminate_child(supervisor, agent_id)  # agent_id is not PID

# CORRECT: Use PID directly  
DynamicSupervisor.terminate_child(supervisor, agent_pid)  # agent_pid is PID
```

#### **Issue: GenServer Callbacks in DynamicSupervisor**
```elixir
# WRONG: Mixing behaviors
defmodule AgentSupervisor do
  use DynamicSupervisor
  
  @impl true  # This causes warnings!
  def handle_cast(...), do: ...
end

# CORRECT: Pure DynamicSupervisor
defmodule AgentSupervisor do
  use DynamicSupervisor
  
  # Only DynamicSupervisor callbacks
  def init(opts), do: DynamicSupervisor.init(opts)
end
```

#### **Issue: Children Not Cleaned Up**
```elixir
# WRONG: Not waiting for termination
MABEAM.AgentSupervisor.stop_agent(pid)
# Immediately check children count - may still be terminating

# CORRECT: Trust OTP guarantees
:ok = MABEAM.AgentSupervisor.stop_agent(pid)
# stop_agent/1 returns :ok only after successful termination
```

## Summary

This process hierarchy provides:

1. **Clear Separation**: DynamicSupervisor for process lifecycle, GenServer for state management
2. **Proper OTP Patterns**: Following supervision best practices without mixing behaviors  
3. **Fault Tolerance**: Isolated failures with automatic recovery
4. **Testing Support**: Namespace isolation and deterministic cleanup
5. **Performance**: Efficient process scaling and resource management

The key insight is maintaining **clear boundaries** between different OTP behaviors and trusting the built-in guarantees rather than adding artificial synchronization.