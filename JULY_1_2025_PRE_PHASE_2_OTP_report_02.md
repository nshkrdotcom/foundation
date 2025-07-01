# OTP Refactor Plan - Document 02: Core Architecture - State & God Agents
Generated: July 1, 2025

## Executive Summary

This second document addresses the **most fundamental architectural flaw**: volatile agent state and monolithic "God" agents. These issues are at the heart of why the system appears to use OTP but gains none of its fault-tolerance benefits.

**Time Estimate**: 1-2 weeks
**Risk**: High - touches core agent functionality
**Impact**: Transforms system from "brittle" to "fault-tolerant"

## Context & Required Reading

1. Review `JULY_1_2025_PRE_PHASE_2_OTP_report_01.md` - Ensure Stage 1 fixes are complete
2. Study `JULY_1_2025_PRE_PHASE_2_OTP_report_gem_01.md` - Flaw #9 on ephemeral state
3. Review existing persistence infrastructure in:
   - `lib/jido_system/agents/persistent_foundation_agent.ex`
   - `lib/jido_system/agents/state_persistence.ex`

## The Core Problem

From gem_02b.md:
> "The system fails to treat a process and its state as a single, inseparable, recoverable unit, which is the entire point of a GenServer."

Currently:
- Agents lose ALL state on crash
- Supervisors restart agents but with empty state
- In-flight tasks, workflows, and queues are lost forever
- The system has persistence infrastructure but **doesn't use it**

## Stage 2.1: Apply State Persistence to Critical Agents (Week 1)

### Priority Order

1. **TaskAgent** - Holds task queues, most critical for data loss
2. **CoordinatorAgent** - Manages workflows, second most critical
3. **MonitorAgent** - Monitoring state should persist
4. All other agents

### Step 1: Refactor TaskAgent (Days 1-2)

**File**: `lib/jido_system/agents/task_agent.ex`

**Current Problem**:
```elixir
defmodule JidoSystem.Agents.TaskAgent do
  use Jido.Agent,
    name: "task_agent",
    schema: [
      task_queue: [type: {:queue, :queue.new()}, default: :queue.new()],
      processing_tasks: [type: :map, default: %{}],
      completed_count: [type: :integer, default: 0],
      error_count: [type: :integer, default: 0],
      status: [type: :atom, default: :active]
    ]
  # NO PERSISTENCE! All state lost on crash
end
```

**Fixed Implementation**:
```elixir
defmodule JidoSystem.Agents.TaskAgent do
  use JidoSystem.Agents.PersistentFoundationAgent,
    name: "task_agent",
    persistent_fields: [:task_queue, :processing_tasks, :completed_count, :error_count, :status],
    schema: [
      task_queue: [type: {:queue, :queue.new()}, default: :queue.new()],
      processing_tasks: [type: :map, default: %{}],
      completed_count: [type: :integer, default: 0],
      error_count: [type: :integer, default: 0],
      status: [type: :atom, default: :active],
      # Add persistence metadata
      last_persisted_at: [type: :datetime, default: nil],
      persistence_version: [type: :integer, default: 1]
    ]

  # Override mount to handle queue deserialization
  def mount(server_state, opts) do
    {:ok, server_state} = super(server_state, opts)
    
    # Convert persisted list back to queue if needed
    updated_agent = update_in(server_state.agent.state.task_queue, fn
      queue when is_list(queue) -> :queue.from_list(queue)
      queue -> queue
    end)
    
    {:ok, %{server_state | agent: updated_agent}}
  end

  # Override on_before_save to serialize queue
  def on_before_save(agent) do
    # Convert queue to list for persistence
    serializable_state = update_in(agent.state.task_queue, fn queue ->
      :queue.to_list(queue)
    end)
    
    %{agent | state: serializable_state}
  end

  # Ensure state is saved after critical operations
  def on_after_run(agent, _action, _result) do
    # Save state but not on every operation (performance)
    if should_persist?(agent) do
      save_state(agent)
    end
    
    agent
  end

  defp should_persist?(agent) do
    # Persist if queue size changed significantly or time elapsed
    now = DateTime.utc_now()
    last = agent.state.last_persisted_at
    
    queue_size_changed?(agent) or 
    time_elapsed?(last, now, :timer.seconds(30)) or
    agent.state.error_count > 0
  end
end
```

**Critical Test**:
```elixir
test "TaskAgent recovers state after crash" do
  # Start agent
  {:ok, agent} = TaskAgent.start_link(id: "test_agent")
  
  # Add tasks
  for i <- 1..10 do
    TaskAgent.add_task(agent, %{id: i, work: "task_#{i}"})
  end
  
  # Get current state
  state_before = TaskAgent.get_state(agent)
  assert length(:queue.to_list(state_before.task_queue)) == 10
  
  # Simulate crash
  Process.exit(agent, :kill)
  
  # Wait for supervisor restart
  Process.sleep(100)
  
  # Agent should have same ID
  {:ok, new_agent} = TaskAgent.get_by_id("test_agent")
  state_after = TaskAgent.get_state(new_agent)
  
  # State should be recovered!
  assert length(:queue.to_list(state_after.task_queue)) == 10
  assert state_after.completed_count == state_before.completed_count
end
```

### Step 2: Fix PersistentFoundationAgent Bug (Day 3)

**File**: `lib/jido_system/agents/persistent_foundation_agent.ex`

**Bug from gem_01.md**: Redundant and confusing state restoration logic

**Current BROKEN**:
```elixir
def mount(server_state, opts) do
  # ... complex reduce logic that duplicates StatePersistence ...
end
```

**FIXED**:
```elixir
defmodule JidoSystem.Agents.PersistentFoundationAgent do
  def mount(server_state, opts) do
    {:ok, server_state} = super(server_state, opts)
    
    if @persistent_fields != [] do
      agent_id = server_state.agent.id
      Logger.info("Restoring persistent state for agent #{agent_id}")
      
      # StatePersistence already handles defaults!
      persisted_state = load_persisted_state(agent_id)
      
      # Simple merge, no complex logic
      updated_agent = update_in(
        server_state.agent.state, 
        &Map.merge(&1, persisted_state)
      )
      
      # Call hook for custom deserialization
      final_agent = if function_exported?(__MODULE__, :on_after_load, 1) do
        on_after_load(updated_agent)
      else
        updated_agent
      end
      
      {:ok, %{server_state | agent: final_agent}}
    else
      {:ok, server_state}
    end
  end
  
  # New callback for custom deserialization
  @callback on_after_load(agent :: Jido.Agent.t()) :: Jido.Agent.t()
  @callback on_before_save(agent :: Jido.Agent.t()) :: Jido.Agent.t()
  @optional_callbacks [on_after_load: 1, on_before_save: 1]
end
```

### Step 3: Decompose CoordinatorAgent (Days 4-7)

This is the most complex refactor. The monolithic CoordinatorAgent must be split.

**Current Architecture**:
```
CoordinatorAgent (God Agent)
├── Workflow Management
├── Task Distribution  
├── State Machine (chained handle_info)
├── Resource Allocation
└── Progress Tracking
```

**New Architecture**:
```
SimplifiedCoordinatorAgent (API Gateway)
├── WorkflowSupervisor (DynamicSupervisor)
│   ├── WorkflowProcess #1 (GenServer + State)
│   ├── WorkflowProcess #2 (GenServer + State)
│   └── WorkflowProcess #N (GenServer + State)
└── WorkflowRegistry (Registry)
```

**Implementation Plan**:

#### Day 4: Create WorkflowProcess

**File**: `lib/jido_system/processes/workflow_process.ex`

```elixir
defmodule JidoSystem.Processes.WorkflowProcess do
  use GenServer
  require Logger
  
  defstruct [
    :id,
    :workflow_def,
    :current_step,
    :state,
    :task_results,
    :status,
    :started_at,
    :metadata
  ]
  
  # Client API
  def start_link(opts) do
    workflow_id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(workflow_id))
  end
  
  def execute_next_step(workflow_id) do
    GenServer.call(via_tuple(workflow_id), :execute_next_step)
  end
  
  # Server callbacks
  def init(opts) do
    workflow_id = Keyword.fetch!(opts, :id)
    workflow_def = Keyword.fetch!(opts, :workflow_def)
    
    # Try to load existing state
    state = case load_workflow_state(workflow_id) do
      {:ok, saved_state} ->
        Logger.info("Resumed workflow #{workflow_id} at step #{saved_state.current_step}")
        saved_state
        
      {:error, :not_found} ->
        Logger.info("Starting new workflow #{workflow_id}")
        %__MODULE__{
          id: workflow_id,
          workflow_def: workflow_def,
          current_step: 0,
          state: %{},
          task_results: %{},
          status: :running,
          started_at: DateTime.utc_now(),
          metadata: Keyword.get(opts, :metadata, %{})
        }
    end
    
    # Save initial state
    save_workflow_state(state)
    
    # Schedule first step
    send(self(), :execute_step)
    
    {:ok, state}
  end
  
  def handle_info(:execute_step, state) do
    case execute_current_step(state) do
      {:ok, result, new_state} ->
        # Save after each step
        save_workflow_state(new_state)
        
        if workflow_complete?(new_state) do
          complete_workflow(new_state)
          {:stop, :normal, new_state}
        else
          # Schedule next step
          send(self(), :execute_step)
          {:noreply, new_state}
        end
        
      {:error, reason, new_state} ->
        save_workflow_state(new_state)
        handle_step_error(reason, new_state)
    end
  end
  
  # Persistence helpers
  defp save_workflow_state(state) do
    JidoSystem.WorkflowPersistence.save(state.id, state)
  end
  
  defp load_workflow_state(workflow_id) do
    JidoSystem.WorkflowPersistence.load(workflow_id)
  end
  
  defp via_tuple(workflow_id) do
    {:via, Registry, {JidoSystem.WorkflowRegistry, workflow_id}}
  end
end
```

#### Day 5: Create WorkflowSupervisor

**File**: `lib/jido_system/supervisors/workflow_supervisor.ex`

```elixir
defmodule JidoSystem.Supervisors.WorkflowSupervisor do
  use DynamicSupervisor
  
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  def start_workflow(workflow_id, workflow_def, metadata \\ %{}) do
    spec = %{
      id: {:workflow, workflow_id},
      start: {JidoSystem.Processes.WorkflowProcess, :start_link, [
        [
          id: workflow_id,
          workflow_def: workflow_def,
          metadata: metadata
        ]
      ]},
      restart: :transient,  # Don't restart completed workflows
      type: :worker
    }
    
    DynamicSupervisor.start_child(__MODULE__, spec)
  end
  
  def stop_workflow(workflow_id) do
    case Registry.lookup(JidoSystem.WorkflowRegistry, workflow_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> {:error, :not_found}
    end
  end
  
  def init(_init_arg) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 3,
      max_seconds: 5
    )
  end
end
```

#### Day 6-7: Refactor CoordinatorAgent to Use WorkflowSupervisor

**File**: `lib/jido_system/agents/coordinator_agent_v2.ex`

```elixir
defmodule JidoSystem.Agents.CoordinatorAgentV2 do
  use JidoSystem.Agents.PersistentFoundationAgent,
    name: "coordinator_agent_v2",
    persistent_fields: [:active_workflows, :completed_count, :failed_count],
    schema: [
      active_workflows: [type: :map, default: %{}],  # id -> metadata
      completed_count: [type: :integer, default: 0],
      failed_count: [type: :integer, default: 0]
    ]
  
  # Simplified - just manages workflows, doesn't execute them
  defmodule Actions.StartWorkflow do
    use Jido.Action,
      name: "start_workflow",
      schema: [
        workflow_def: [type: :map, required: true],
        metadata: [type: :map, default: %{}]
      ]
    
    def run(params, context) do
      agent = context.agent
      workflow_id = generate_workflow_id()
      
      case WorkflowSupervisor.start_workflow(
        workflow_id,
        params.workflow_def,
        params.metadata
      ) do
        {:ok, pid} ->
          # Just track it, don't manage execution
          new_workflows = Map.put(
            agent.state.active_workflows,
            workflow_id,
            %{
              pid: pid,
              started_at: DateTime.utc_now(),
              metadata: params.metadata
            }
          )
          
          new_state = %{agent.state | active_workflows: new_workflows}
          {:ok, %{workflow_id: workflow_id}, %{agent | state: new_state}}
          
        {:error, reason} ->
          {:error, reason}
      end
    end
  end
  
  # Monitor workflow completion
  def on_after_mount(agent) do
    # Subscribe to workflow completion events
    Registry.register(JidoSystem.WorkflowEvents, :workflow_completed, [])
    Registry.register(JidoSystem.WorkflowEvents, :workflow_failed, [])
    agent
  end
  
  def handle_info({:workflow_completed, workflow_id}, agent) do
    new_state = agent.state
    |> update_in([:active_workflows], &Map.delete(&1, workflow_id))
    |> update_in([:completed_count], &(&1 + 1))
    
    {:noreply, %{agent | state: new_state}}
  end
end
```

## Stage 2.2: Create Migration Path (Week 2)

### The Challenge

We now have:
- Old `CoordinatorAgent` (broken but in use)
- New `CoordinatorAgentV2` + `WorkflowSupervisor` (correct but not integrated)

### Migration Strategy

#### Step 1: Feature Flag (Day 8)

```elixir
# config/config.exs
config :jido_system, :use_v2_coordinator, false

# In code that creates coordinators:
def create_coordinator(opts) do
  if Application.get_env(:jido_system, :use_v2_coordinator, false) do
    CoordinatorAgentV2.start_link(opts)
  else
    CoordinatorAgent.start_link(opts)
  end
end
```

#### Step 2: Dual Write (Day 9)

Make V1 coordinator delegate to V2 for new workflows:

```elixir
defmodule JidoSystem.Agents.CoordinatorAgent do
  # Existing code...
  
  def handle_action(StartWorkflow, params, context) do
    if Application.get_env(:jido_system, :use_v2_coordinator, false) do
      # Delegate to V2
      CoordinatorAgentV2.Actions.StartWorkflow.run(params, context)
    else
      # Original implementation
      original_start_workflow(params, context)
    end
  end
end
```

#### Step 3: Migration Script (Day 10)

```elixir
defmodule JidoSystem.Migrations.CoordinatorV2Migration do
  def migrate_active_workflows do
    # Get all V1 coordinators
    v1_agents = get_all_coordinator_agents()
    
    Enum.each(v1_agents, fn agent ->
      # Extract workflow state
      workflows = extract_workflows_from_v1(agent)
      
      # Create V2 coordinator with same ID
      {:ok, v2_agent} = CoordinatorAgentV2.start_link(
        id: "#{agent.id}_v2",
        state: %{
          active_workflows: migrate_workflow_format(workflows),
          completed_count: agent.state.completed_count,
          failed_count: agent.state.error_count
        }
      )
      
      # Start WorkflowProcesses for active workflows
      Enum.each(workflows, fn {id, workflow} ->
        WorkflowSupervisor.start_workflow(
          id,
          workflow.definition,
          %{migrated: true, original_step: workflow.current_step}
        )
      end)
    end)
  end
end
```

#### Step 4: Gradual Rollout (Days 11-14)

1. Enable feature flag in staging
2. Run migration script
3. Monitor for issues
4. Enable in production for new workflows
5. Migrate existing workflows in batches
6. Disable V1 coordinator
7. Delete old code

## Stage 2.3: Apply Pattern to Other Agents

### MonitorAgent (Day 12)

```elixir
defmodule JidoSystem.Agents.MonitorAgent do
  use JidoSystem.Agents.PersistentFoundationAgent,
    name: "monitor_agent",
    persistent_fields: [:monitored_agents, :health_history, :alert_state],
    schema: [
      monitored_agents: [type: :map, default: %{}],
      health_history: [type: :list, default: []],  # Ring buffer
      alert_state: [type: :map, default: %{}],
      max_history: [type: :integer, default: 1000]
    ]
  
  # Implement ring buffer for health history
  def on_before_save(agent) do
    # Trim history to max size
    trimmed_history = Enum.take(agent.state.health_history, agent.state.max_history)
    %{agent | state: %{agent.state | health_history: trimmed_history}}
  end
end
```

### Pattern for All Agents (Days 13-14)

Create a checklist:

```markdown
## Agent Persistence Checklist

- [ ] Extends PersistentFoundationAgent
- [ ] Defines persistent_fields
- [ ] Implements on_before_save for serialization (if needed)
- [ ] Implements on_after_load for deserialization (if needed)
- [ ] Tests verify state recovery after crash
- [ ] Performance: not saving on every operation
- [ ] Old agent data migrated
```

## Testing Strategy

### Integration Test Suite

Create `test/jido_system/persistence_integration_test.exs`:

```elixir
defmodule JidoSystem.PersistenceIntegrationTest do
  use ExUnit.Case
  
  describe "full system persistence" do
    test "complete workflow survives cascading failures" do
      # Start a complex workflow
      {:ok, coordinator} = CoordinatorAgentV2.start_link(id: "test_coord")
      {:ok, %{workflow_id: wf_id}} = CoordinatorAgentV2.start_workflow(
        coordinator,
        %{
          steps: [
            {:task, %{type: :compute, work: "step1"}},
            {:task, %{type: :compute, work: "step2"}},
            {:task, %{type: :compute, work: "step3"}}
          ]
        }
      )
      
      # Let it process first step
      Process.sleep(100)
      
      # Kill everything
      Process.exit(coordinator, :kill)
      workflow_pid = get_workflow_pid(wf_id)
      Process.exit(workflow_pid, :kill)
      
      # Restart coordinator
      {:ok, new_coord} = CoordinatorAgentV2.start_link(id: "test_coord")
      
      # Workflow should auto-resume
      assert_eventually(fn ->
        state = CoordinatorAgentV2.get_state(new_coord)
        state.completed_count == 1
      end)
    end
  end
end
```

### Chaos Testing

```elixir
defmodule JidoSystem.ChaosTest do
  use ExUnit.Case
  
  @tag :chaos
  test "system maintains consistency under random failures" do
    # Start full system
    start_supervised!(JidoSystem.Application)
    
    # Create load
    tasks = for i <- 1..100 do
      Task.async(fn ->
        add_random_work()
      end)
    end
    
    # Randomly kill processes
    for _ <- 1..20 do
      Process.sleep(Enum.random(100..500))
      kill_random_process()
    end
    
    # Wait for system to stabilize
    Process.sleep(5000)
    
    # Verify no work was lost
    assert verify_all_work_completed(tasks)
  end
end
```

## Success Metrics

1. **Zero Data Loss**: No tasks/workflows lost on crash
2. **Fast Recovery**: < 100ms to restore agent state
3. **Minimal Overhead**: < 5% performance impact from persistence
4. **Complete Coverage**: 100% of stateful agents use persistence

## Summary

Stage 2 transforms the system's most critical flaw: volatile state. By:
1. Applying existing PersistentFoundationAgent to ALL stateful agents
2. Decomposing the God CoordinatorAgent into supervised WorkflowProcesses
3. Creating a safe migration path from V1 to V2
4. Establishing patterns for all future agent development

**Next Document**: `JULY_1_2025_PRE_PHASE_2_OTP_report_03.md` will cover testing architecture and removing telemetry anti-patterns.