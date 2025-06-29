# JIDO Implementation Context - Critical Findings

## FUNDAMENTAL DESIGN FLAWS DISCOVERED

### 1. **Result Format Inconsistency (CRITICAL)**
- **Problem**: Actions return `{:ok, map}` but agents expect bare maps in some places
- **Root Cause**: Incomplete migration from old API, mixing mental models
- **Impact**: Cascading failures through on_after_run callbacks
- **Fix Applied**: Updated TaskAgent patterns, but FoundationAgent still has workarounds

### 2. **Telemetry Integration Broken**
- **Problem**: Bridge emits `[:jido, :agent, event]` but tests expect `[:jido_foundation, :bridge, :agent_event]`
- **Root Cause**: No unified telemetry contract between Jido and Foundation layers
- **Fix Applied**: Changed FoundationAgent to emit expected events directly
- **Deeper Issue**: Bridge.emit_agent_event is bypassed, coupling concerns

### 3. **Action Contract Confusion**
- **Problem**: Tests still calling run/3 when actions implement run/2
- **Root Cause**: Incomplete API migration, tests not updated with implementation
- **Fix Applied**: Updated test calls
- **Remaining**: No type specs to catch these at compile time

### 4. **State Management Assumptions**
- **Problem**: Actions receive context.state directly, not context.agent.state
- **Root Cause**: Layering violation - actions shouldn't know about agent internals
- **Fix Applied**: Updated action implementations
- **Deeper Issue**: No clear boundary between action context and agent state

### 5. **Sensor Target Validation**
- **Problem**: Tests use `{:test, self()}` but sensor expects `{:bus, Foundation.EventBus}`
- **Root Cause**: No documented contract for sensor targets
- **Not Fixed**: Lower priority, but shows missing architectural documentation

## SYSTEMIC ISSUES

1. **Missing Abstractions**: No unified result handling layer
2. **Implicit Contracts**: Too many assumptions without types/specs
3. **Test-Implementation Drift**: Tests reflect old mental models
4. **Layering Violations**: Components know too much about each other

## WHAT'S NOT DONE

1. **Sensor target contract** - needs clear specification
2. **Unified telemetry strategy** - Foundation vs Jido events
3. **Result handling abstraction** - standardize success/error patterns
4. **Type specifications** - catch interface mismatches at compile time
5. **Integration tests** - verify full stack works together

## CRITICAL INSIGHT

The core issue is **mixing multiple mental models** without explicit contracts:
- Old Jido API (run/3, bare maps)
- New Jido API (run/2, tuple results)
- Foundation expectations (specific telemetry events)
- Test assumptions (outdated interfaces)

The fixes applied are tactical bandaids. The system needs:
1. Clear architectural boundaries
2. Explicit contracts (behaviours + typespecs)
3. Unified error/result handling
4. Complete API migration (no legacy patterns)

**STATUS**: 259 tests, 11 failures remaining (from 55 originally)

## IMPLEMENTATION DETAILS & FIXES

### Files Modified & Why
1. **ProcessTask** (`lib/jido_system/actions/process_task.ex`)
   - Changed from run/3 to run/2 per Jido.Action behaviour
   - Returns `{:ok, %{status: :completed, ...}}` format
   - Uses context.state directly, not context.agent

2. **TaskAgent** (`lib/jido_system/agents/task_agent.ex`)
   - Fixed on_after_run patterns: `{:ok, %{status: :completed}}` not bare `%{status: :completed}`
   - handle_pause_processing returns proper result format
   - Added uptime: 0 to status (missing started_at initialization)

3. **FoundationAgent** (`lib/jido_system/agents/foundation_agent.ex`)
   - Added bare map handling in on_after_run (lines 143-161) - WORKAROUND
   - Changed Bridge.emit_agent_event to direct :telemetry.execute calls
   - Emits `[:jido_foundation, :bridge, :agent_event]` to match test expectations

4. **Action Context Fix** (`get_task_status.ex`, `pause_processing.ex`, etc)
   - All use `state = Map.get(context, :state, %{})` 
   - NOT `agent = context.agent; state = agent.state`

### Test Patterns Discovered
- Tests expect telemetry at `[:jido_foundation, :bridge, :agent_event]`
- Tests pass context with :state key directly to actions
- TaskAgent tests expect specific result shapes from actions

### Architecture Mismatch
**JIDO_BUILDOUT.md** describes:
- on_init → reality: mount
- on_before_action → reality: on_before_run
- on_after_action → reality: on_after_run
- Actions in chain with compensations

**Reality**:
- Simpler callback names
- No compensation framework visible
- Direct telemetry instead of Bridge abstraction

### Key Functions & Flows
1. **Action Execution**: Jido.Exec.run/4 → action.run/2 → validate_output
2. **Agent Processing**: Server.cast → on_before_run → Exec → on_after_run
3. **Result Handling**: Actions return {:ok/:error, map} → Agent callbacks process

### Remaining 11 Failures
- 3 sensor tests: "invalid dispatch configuration" error
- 5 TaskAgent tests: result format/state management issues  
- 3 FoundationAgent tests: telemetry not received

### Critical Code Locations
- Jido.Action behaviour: `/deps/jido/lib/jido/action.ex:39`
- Agent callbacks: `/deps/jido/lib/jido/agent.ex`
- Bridge implementation: `/lib/jido_foundation/bridge.ex`
- Test expectations: `/test/jido_system/agents/*_test.exs`

### Next Developer Must Know
1. **Don't trust the docs** - implementation differs significantly
2. **Check deps/jido** for actual behaviour contracts
3. **Telemetry is fragmented** - some through Bridge, some direct
4. **State management is inconsistent** - agents vs actions have different views
5. **Test assertions reveal the true expected API**

## CRITICAL PATTERNS & GOTCHAS

### Action Result Patterns Found
```elixir
# ProcessTask returns:
{:ok, %{status: :completed, task_id: id, result: data, duration: ms}}
{:error, %{status: :failed, task_id: id, error: reason}}

# QueueTask returns:
{:ok, %{queued: true, updated_queue: queue, task_id: id}}

# PauseProcessing returns:
{:ok, %{status: :paused, previous_status: old, reason: str, paused_at: dt}}

# GetTaskStatus returns:
{:ok, %{status: atom, uptime: 0, queue_size: n, ...}}
```

### Context Structure for Actions
```elixir
# What actions receive:
context = %{
  state: agent.state,  # Agent's internal state map
  agent_id: "id",      # Optional
  action_metadata: %{} # From Jido.Exec
}
```

### Agent Lifecycle Reality
1. mount/2 - NOT on_init - returns {:ok, server_state}
2. on_before_run/1 - returns {:ok, agent}
3. on_after_run/3 - returns {:ok, agent} - MUST handle various result formats
4. on_error/2 - returns {:ok, agent, directives}
5. shutdown/2 - cleanup

### Telemetry Events Map
```elixir
# What Bridge SHOULD emit (but doesn't):
[:jido_foundation, :bridge, :agent_event]

# What Bridge ACTUALLY emits:
[:jido, :agent, event_type]

# What tests expect:
[:jido_foundation, :bridge, :agent_event]

# ProcessTask emits directly:
[:jido_system, :task, :started/:completed/:failed]
```

### Test Failure Categories
1. **run/3 calls** - Fixed by removing third argument
2. **Result patterns** - Fixed by matching {:ok, map} not bare map
3. **Telemetry missing** - Fixed by direct :telemetry.execute
4. **State access** - Fixed by using context.state not context.agent.state
5. **Sensor targets** - NOT FIXED - needs {:bus, _} format

### Hidden Dependencies
- Foundation.CircuitBreaker - used by ProcessTask
- Foundation.Telemetry - aliased but unused in many files
- MABEAM.AgentRegistry - auto-started in tests
- Jido.Signal - sensors must return Signal structs
- :queue module - Erlang queue for task_queue

### Working Examples
```elixir
# Correct action:
def run(params, context) do
  state = Map.get(context, :state, %{})
  {:ok, %{field: value}}  # ALWAYS tuple
end

# Correct on_after_run:
def on_after_run(agent, result, directives) do
  case result do
    {:ok, %{specific: pattern}} -> handle_specific
    {:ok, _} -> handle_generic
    {:error, _} -> handle_error
  end
end
```

### DANGER ZONES
1. Process.sleep removed but retry backoff broken
2. Agent started_at never initialized → uptime always 0
3. Bridge functions bypassed → no Foundation integration
4. No resource management despite ProcessTask having it
5. Sensor target validation undefined contract

### FILE LOCATIONS THAT MATTER
```
/deps/jido/lib/jido/action.ex:@callback run(params :: map(), context :: map())
/lib/jido_system/agents/foundation_agent.ex:125-161 (on_after_run workaround)
/lib/jido_foundation/bridge.ex:112 (emit_agent_event)
/test/jido_system/agents/*_test.exs (true expectations)
```

INCOMPLETE: Agent initialization flow, supervisor structure, sensor contracts