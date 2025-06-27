# Agent Lifecycle Management

## Overview

This document defines the complete agent lifecycle management system for MABEAM, addressing the critical patterns for agent spawning, supervision, coordination, and termination. This directly addresses the supervision architecture issues identified in the debug session.

## Agent Architecture Model

### **Agent-as-Process Paradigm**

Every ML agent in MABEAM runs as a dedicated OTP process with:
- **Individual supervision** via DynamicSupervisor
- **Fault isolation** - agent failures don't cascade
- **Resource management** - memory/CPU limits per agent
- **State encapsulation** - agent state maintained separately from coordination

```
Agent Process = OTP GenServer + ML Capabilities + Coordination Interface
```

## Complete Agent Lifecycle

### **Phase 1: Agent Definition & Registration**

#### **Agent Specification**
```elixir
agent_spec = %{
  id: :coder_agent_1,
  module: MABEAM.Agents.CoderAgent,
  init_args: %{
    language: :elixir,
    expertise_level: :senior,
    specializations: [:functional_programming, :otp]
  },
  resources: %{
    max_memory: 100_000_000,  # 100MB
    cpu_priority: :normal,
    max_runtime: :infinity
  },
  coordination: %{
    participates_in_consensus: true,
    leadership_eligible: false,
    communication_pattern: :async
  }
}
```

#### **Agent Registration Flow**
```
1. MABEAM.AgentRegistry.register_agent(agent_spec)
2. ├─ Validate agent specification
3. ├─ Store agent metadata in ETS table
4. ├─ Generate unique agent ID if not provided
5. ├─ Set initial status: :registered
6. └─ Return {:ok, agent_id} or {:error, reason}
```

### **Phase 2: Agent Spawning & Initialization**

#### **Correct Agent Startup Pattern**
```elixir
defmodule MABEAM.AgentRegistry do
  def start_agent(agent_id) do
    with {:ok, spec} <- get_agent_spec(agent_id),
         :ok <- validate_resources_available(spec),
         {:ok, pid} <- spawn_agent_process(spec),
         :ok <- initialize_agent_state(agent_id, pid, spec),
         :ok <- setup_process_monitoring(pid, agent_id),
         :ok <- notify_coordination_system(agent_id, :started) do
      {:ok, pid}
    else
      error -> 
        cleanup_failed_start(agent_id)
        error
    end
  end

  defp spawn_agent_process(spec) do
    child_spec = %{
      id: spec.id,
      start: {spec.module, :start_link, [spec.init_args, [name: spec.id]]},
      restart: :temporary,  # Don't auto-restart failed agents
      shutdown: 5000,       # 5 second graceful shutdown
      type: :worker
    }
    
    MABEAM.AgentSupervisor.start_child(child_spec)
  end
end
```

#### **Agent Process Initialization**
```elixir
defmodule MABEAM.Agents.CoderAgent do
  use GenServer
  
  def start_link(init_args, opts \\ []) do
    GenServer.start_link(__MODULE__, init_args, opts)
  end

  def init(init_args) do
    # Set process resource limits
    Process.flag(:max_heap_size, init_args[:max_memory] || 50_000_000)
    Process.flag(:priority, init_args[:cpu_priority] || :normal)
    
    # Initialize agent state
    state = %{
      agent_id: init_args[:agent_id],
      capabilities: init_args[:capabilities] || [],
      current_task: nil,
      performance_metrics: %{},
      coordination_context: %{},
      variables: %{}  # ML variables this agent optimizes
    }
    
    # Register with coordination system
    :ok = MABEAM.Coordination.agent_ready(self(), state.agent_id)
    
    {:ok, state}
  end
end
```

### **Phase 3: Agent Operation & Coordination**

#### **Variable-Driven Coordination**
```elixir
# Agent receives variable updates from MABEAM.Core
def handle_cast({:variable_update, variable_name, new_value}, state) do
  # Update agent's understanding of optimization parameters
  new_variables = Map.put(state.variables, variable_name, new_value)
  
  # Potentially trigger agent behavior change
  new_state = %{state | variables: new_variables}
  |> maybe_update_strategy(variable_name, new_value)
  |> update_performance_expectations()
  
  # Notify coordination system of parameter change
  MABEAM.Coordination.variable_updated(self(), variable_name, new_value)
  
  {:noreply, new_state}
end
```

#### **Task Execution Pattern**
```elixir
def handle_call({:execute_task, task_spec}, _from, state) do
  # Validate agent can handle this task type
  case validate_task_compatibility(task_spec, state.capabilities) do
    :ok ->
      # Execute task with current variable settings
      result = execute_with_variables(task_spec, state.variables)
      
      # Update performance metrics
      new_state = update_metrics(state, task_spec, result)
      
      # Report results to coordination system
      MABEAM.Coordination.task_completed(self(), task_spec, result)
      
      {:reply, {:ok, result}, new_state}
      
    {:error, reason} ->
      {:reply, {:error, {:incompatible_task, reason}}, state}
  end
end
```

### **Phase 4: Agent Monitoring & Health Management**

#### **Process Monitoring Setup**
```elixir
defmodule MABEAM.AgentRegistry do
  def setup_process_monitoring(agent_pid, agent_id) do
    # Monitor agent process for crashes
    ref = Process.monitor(agent_pid)
    
    # Store monitoring reference
    :ets.insert(:agent_monitors, {agent_id, agent_pid, ref})
    
    # Setup health check timer
    schedule_health_check(agent_id)
    
    :ok
  end

  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    case :ets.match(:agent_monitors, {:_, pid, ref}) do
      [[agent_id]] ->
        # Agent process crashed or terminated
        handle_agent_termination(agent_id, pid, reason)
        cleanup_agent_monitoring(agent_id, ref)
        
      [] ->
        # Unknown process - ignore
        :ok
    end
    
    {:noreply, state}
  end

  defp handle_agent_termination(agent_id, pid, reason) do
    new_status = case reason do
      :normal -> :completed
      :shutdown -> :stopped  
      {:shutdown, _} -> :stopped
      _ -> :crashed
    end
    
    # Update agent status
    update_agent_status(agent_id, new_status, %{
      terminated_at: DateTime.utc_now(),
      termination_reason: reason
    })
    
    # Notify coordination system
    MABEAM.Coordination.agent_terminated(agent_id, reason)
    
    # Handle crash recovery if needed
    maybe_schedule_restart(agent_id, reason)
  end
end
```

#### **Health Check Implementation**
```elixir
def perform_health_check(agent_id) do
  case get_agent_pid(agent_id) do
    {:ok, pid} ->
      try do
        # Check if agent is responsive
        response = GenServer.call(pid, :health_check, 5000)
        update_agent_health(agent_id, :healthy, response)
      catch
        :exit, {:timeout, _} ->
          update_agent_health(agent_id, :unresponsive, %{reason: :timeout})
          maybe_terminate_unresponsive_agent(agent_id)
          
        :exit, {:noproc, _} ->
          update_agent_health(agent_id, :dead, %{reason: :noproc})
      end
      
    {:error, :not_found} ->
      update_agent_health(agent_id, :not_running, %{})
  end
  
  # Schedule next health check
  schedule_health_check(agent_id)
end
```

### **Phase 5: Agent Termination & Cleanup**

#### **Graceful Shutdown Pattern**
```elixir
def stop_agent(agent_id) do
  with {:ok, pid} <- get_agent_pid(agent_id),
       :ok <- notify_coordination_of_shutdown(agent_id),
       :ok <- wait_for_task_completion(agent_id),
       :ok <- save_agent_state(agent_id),
       :ok <- terminate_agent_process(pid),
       :ok <- cleanup_agent_resources(agent_id) do
    update_agent_status(agent_id, :stopped)
    {:ok, :stopped}
  else
    {:error, :not_found} -> 
      {:error, :agent_not_running}
    {:error, reason} -> 
      force_terminate_agent(agent_id)
      {:error, reason}
  end
end

defp terminate_agent_process(pid) do
  case DynamicSupervisor.terminate_child(MABEAM.AgentSupervisor, pid) do
    :ok -> 
      # Process terminated successfully
      :ok
      
    {:error, :not_found} ->
      # Process already terminated
      :ok
      
    {:error, reason} ->
      # Force termination if graceful shutdown fails
      Process.exit(pid, :kill)
      :ok
  end
end
```

#### **Resource Cleanup Sequence**
```elixir
defp cleanup_agent_resources(agent_id) do
  # 1. Remove from agent registry
  :ets.delete(:agent_registry, agent_id)
  
  # 2. Clean up monitoring references
  case :ets.lookup(:agent_monitors, agent_id) do
    [{^agent_id, _pid, ref}] ->
      Process.demonitor(ref, [:flush])
      :ets.delete(:agent_monitors, agent_id)
    [] -> :ok
  end
  
  # 3. Cancel scheduled tasks
  cancel_health_checks(agent_id)
  cancel_scheduled_tasks(agent_id)
  
  # 4. Clean up coordination state
  MABEAM.Coordination.remove_agent(agent_id)
  
  # 5. Update telemetry
  MABEAM.Telemetry.agent_terminated(agent_id)
  
  :ok
end
```

## Agent State Management

### **State Persistence Pattern**
```elixir
# Agent state is maintained separately from process state
defmodule MABEAM.AgentState do
  def save_agent_state(agent_id, state) do
    # Persist critical agent state for potential restart
    persistent_state = %{
      agent_id: agent_id,
      variables: state.variables,
      performance_metrics: state.performance_metrics,
      learned_optimizations: state.learned_optimizations,
      saved_at: DateTime.utc_now()
    }
    
    :ets.insert(:agent_state, {agent_id, persistent_state})
    
    # Also save to EventStore for audit trail
    event = %{
      type: :agent_state_saved,
      agent_id: agent_id,
      state: persistent_state
    }
    Foundation.EventStore.append(event)
  end

  def restore_agent_state(agent_id) do
    case :ets.lookup(:agent_state, agent_id) do
      [{^agent_id, state}] -> {:ok, state}
      [] -> {:error, :no_saved_state}
    end
  end
end
```

## Coordination Integration

### **Agent-Coordination Interface**
```elixir
defmodule MABEAM.Coordination do
  # Agent lifecycle notifications
  def agent_ready(agent_pid, agent_id) do
    GenServer.cast(__MODULE__, {:agent_ready, agent_pid, agent_id})
  end

  def agent_terminated(agent_id, reason) do
    GenServer.cast(__MODULE__, {:agent_terminated, agent_id, reason})
  end

  # Variable synchronization
  def variable_updated(agent_pid, variable_name, value) do
    GenServer.cast(__MODULE__, {:variable_update_ack, agent_pid, variable_name, value})
  end

  # Task coordination
  def task_completed(agent_pid, task_spec, result) do
    GenServer.call(__MODULE__, {:task_completed, agent_pid, task_spec, result})
  end

  # Consensus participation
  def vote_cast(agent_pid, proposal_id, vote) do
    GenServer.cast(__MODULE__, {:vote, agent_pid, proposal_id, vote})
  end
end
```

### **Multi-Agent Consensus Flow**
```
1. Coordination System initiates consensus on parameter change
2. ├─ Broadcast proposal to all eligible agents
3. ├─ Each agent evaluates proposal against current state
4. ├─ Agents cast votes back to coordination system
5. ├─ Coordination system tallies votes
6. ├─ If consensus reached: broadcast parameter update to all agents
7. └─ If consensus failed: initiate fallback strategy
```

## Error Handling & Recovery

### **Agent Crash Recovery Strategies**

#### **Immediate Restart (Hot Restart)**
```elixir
defp maybe_schedule_restart(agent_id, reason) do
  case get_restart_policy(agent_id) do
    :immediate when reason != :shutdown ->
      # Restart immediately for non-graceful shutdowns
      spawn(fn -> 
        Process.sleep(1000)  # Brief delay to prevent restart loops
        restart_agent(agent_id)
      end)
      
    :delayed ->
      # Restart after delay with exponential backoff
      delay = calculate_restart_delay(agent_id)
      Process.send_after(self(), {:restart_agent, agent_id}, delay)
      
    :manual ->
      # Require manual intervention
      MABEAM.Alerts.agent_crashed(agent_id, reason)
      
    :never ->
      # Don't restart
      :ok
  end
end
```

#### **State Recovery on Restart**
```elixir
def restart_agent(agent_id) do
  case restore_agent_state(agent_id) do
    {:ok, saved_state} ->
      # Restart with previous state
      start_agent(agent_id, %{restore_state: saved_state})
      
    {:error, :no_saved_state} ->
      # Fresh start
      start_agent(agent_id)
  end
end
```

### **Coordination System Recovery**
```elixir
# Handle coordination system failures
def handle_coordination_unavailable(agent_id) do
  # Agent can continue with last known variable values
  # but can't participate in consensus until coordination restored
  
  case get_agent_pid(agent_id) do
    {:ok, pid} ->
      GenServer.cast(pid, {:coordination_unavailable, :fallback_mode})
    {:error, _} ->
      :ok
  end
end
```

## Performance Optimization

### **Agent Pool Management**
```elixir
# Pre-spawn agent pool for faster task assignment
defmodule MABEAM.AgentPool do
  def ensure_pool_size(agent_type, target_size) do
    current_size = count_agents_by_type(agent_type)
    
    cond do
      current_size < target_size ->
        spawn_additional_agents(agent_type, target_size - current_size)
        
      current_size > target_size ->
        terminate_excess_agents(agent_type, current_size - target_size)
        
      true ->
        :ok
    end
  end
end
```

### **Resource-Based Scaling**
```elixir
def handle_info(:check_scaling, state) do
  # Scale agent pool based on resource utilization
  metrics = MABEAM.PerformanceMonitor.get_system_metrics()
  
  scaling_action = determine_scaling_action(metrics)
  
  case scaling_action do
    {:scale_up, agent_type, count} ->
      MABEAM.AgentPool.spawn_agents(agent_type, count)
      
    {:scale_down, agent_type, count} ->
      MABEAM.AgentPool.terminate_agents(agent_type, count)
      
    :no_action ->
      :ok
  end
  
  # Schedule next check
  Process.send_after(self(), :check_scaling, 30_000)
  
  {:noreply, state}
end
```

## Testing Strategy

### **Agent Lifecycle Testing**
```elixir
defmodule MABEAM.AgentLifecycleTest do
  use ExUnit.Case
  
  test "complete agent lifecycle" do
    # 1. Register agent
    agent_spec = %{id: :test_agent, module: TestAgent, init_args: %{}}
    {:ok, agent_id} = MABEAM.AgentRegistry.register_agent(agent_spec)
    
    # 2. Start agent
    {:ok, agent_pid} = MABEAM.AgentRegistry.start_agent(agent_id)
    assert Process.alive?(agent_pid)
    
    # 3. Execute task
    {:ok, result} = GenServer.call(agent_pid, {:execute_task, %{type: :test}})
    assert result.status == :completed
    
    # 4. Stop agent gracefully
    :ok = MABEAM.AgentRegistry.stop_agent(agent_id)
    
    # 5. Verify cleanup
    refute Process.alive?(agent_pid)
    {:error, :not_found} = MABEAM.AgentRegistry.get_agent_pid(agent_id)
  end
  
  test "agent crash recovery" do
    {:ok, agent_id} = create_test_agent()
    {:ok, agent_pid} = MABEAM.AgentRegistry.start_agent(agent_id)
    
    # Simulate crash
    Process.exit(agent_pid, :kill)
    
    # Verify status updated
    :timer.sleep(100)  # Allow monitoring to process
    {:ok, status} = MABEAM.AgentRegistry.get_agent_status(agent_id)
    assert status.current_status == :crashed
  end
end
```

## Summary

This agent lifecycle management system provides:

1. **Complete Lifecycle Control**: Registration → Spawning → Operation → Termination
2. **Fault Tolerance**: Crash detection, recovery strategies, graceful degradation
3. **Resource Management**: Memory limits, CPU prioritization, scaling policies
4. **Coordination Integration**: Variable synchronization, consensus participation
5. **State Persistence**: Save/restore agent state across restarts
6. **Performance Optimization**: Agent pools, resource-based scaling
7. **Comprehensive Testing**: Deterministic lifecycle testing patterns

The key architectural insight is maintaining **clear separation** between:
- **Process lifecycle** (DynamicSupervisor)
- **Agent metadata** (AgentRegistry GenServer)  
- **Coordination state** (MABEAM.Coordination)
- **Persistent state** (ETS + EventStore)

This separation enables robust, testable, and scalable agent management while maintaining the fault tolerance guarantees of OTP.