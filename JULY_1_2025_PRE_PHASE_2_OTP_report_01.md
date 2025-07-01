# OTP Refactor Plan - Document 01: CRITICAL - Stop the Bleeding
Generated: July 1, 2025

## Executive Summary

This is the first of five documents outlining a comprehensive plan to transform the Foundation/Jido codebase from "Elixir with OTP veneer" to "proper OTP architecture". This document focuses on **immediate critical fixes** that prevent data loss, resource leaks, and system instability.

**Time Estimate**: 2-3 days
**Risk**: These changes touch core functionality but are essential to prevent production disasters
**Impact**: Eliminates the most severe anti-patterns that actively harm system reliability

## Context & Required Reading

Before starting, review these documents to understand the severity:
1. `JULY_1_2025_PRE_PHASE_2_OTP_report_gem_02b.md` - The "Illusion of OTP" critique
2. `JULY_1_2025_PRE_PHASE_2_OTP_report_gem_01.md` - Status of previous fixes
3. Current code files listed in each stage below

## Stage 1.1: Ban Dangerous Primitives (Day 1 Morning)

### The Problem
The codebase uses raw `spawn/1`, `Process.put/2`, and `send/2` for critical operations, bypassing OTP supervision and guarantees.

### Action Items

1. **Add Credo Rules** to `.credo.exs`:
```elixir
%{
  configs: [
    %{
      checks: [
        # Ban unsupervised spawning
        {Credo.Check.Warning.UnsafeExec, [banned_functions: [
          {Process, :spawn, 1},
          {Process, :spawn, 2},
          {Kernel, :spawn, 1},
          {Kernel, :spawn, 2}
        ]]},
        # Ban process dictionary for state
        {Credo.Check.Warning.ProcessDict, []},
        # Custom check for raw send usage
        {Foundation.CredoChecks.NoRawSend, []}
      ]
    }
  ]
}
```

2. **Create Custom Credo Check** at `lib/foundation/credo_checks/no_raw_send.ex`:
```elixir
defmodule Foundation.CredoChecks.NoRawSend do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Raw send/2 provides no delivery guarantees. Use GenServer.call/cast or
      monitored sends for critical communication.
      """
    ]

  def run(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end
  
  defp traverse({:send, meta, _args} = ast, issues, issue_meta) do
    issue = format_issue(issue_meta, 
      message: "Use GenServer.call/cast instead of raw send/2",
      line_no: meta[:line]
    )
    {ast, [issue | issues]}
  end
  defp traverse(ast, issues, _), do: {ast, issues}
end
```

3. **Fix CI Pipeline** - Add to `.github/workflows/ci.yml`:
```yaml
- name: Check OTP compliance
  run: |
    mix credo --strict
    # Fail if any dangerous patterns found
    ! grep -r "Process\.spawn\|spawn(" lib/ --include="*.ex"
    ! grep -r "Process\.put\|Process\.get" lib/ --include="*.ex"
```

### Discussion
These primitives are the root of many issues. By banning them at the tooling level, we prevent future regressions while fixing existing violations.

## Stage 1.2: Fix Critical Resource Leaks (Day 1 Afternoon)

### The Problem
Multiple modules monitor processes but never call `Process.demonitor`, causing memory leaks and potential message floods.

### Files to Fix

1. **`lib/jido_foundation/signal_router.ex`** (CRITICAL FLAW #13)
   - Line 153: `Process.monitor(handler_pid)` without corresponding demonitor
   - Line 239: DOWN handler must add `Process.demonitor(ref, [:flush])`

2. **`lib/jido_foundation/coordination_manager.ex`** (gem_01b CRITICAL FLAW #13)
   - Multiple monitor calls without demonitor
   - Fix all DOWN handlers to properly clean up

3. **`lib/mabeam/agent_registry.ex`** (Already partially fixed but verify)
   - Ensure ALL monitor refs are cleaned up

### Implementation Pattern
```elixir
# WRONG - Current pattern
def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
  # Only cleans internal state, leaks monitor
  new_state = Map.delete(state.monitored_processes, pid)
  {:noreply, new_state}
end

# CORRECT - Must demonitor
def handle_info({:DOWN, ref, :process, pid, reason}, state) do
  # CRITICAL: Always demonitor with flush
  Process.demonitor(ref, [:flush])
  new_state = Map.delete(state.monitored_processes, pid)
  {:noreply, new_state}
end
```

### Testing
Create `test/foundation/monitor_leak_test.exs`:
```elixir
defmodule Foundation.MonitorLeakTest do
  use ExUnit.Case
  
  test "no monitor leaks in signal router" do
    {:ok, router} = JidoFoundation.SignalRouter.start_link()
    
    # Create and monitor 1000 processes
    pids = for _ <- 1..1000 do
      pid = spawn(fn -> :ok end)
      JidoFoundation.SignalRouter.subscribe("test.*", pid)
      pid
    end
    
    # Get initial monitor count
    initial_monitors = :erlang.system_info(:monitor_count)
    
    # Let all processes die
    Process.sleep(100)
    
    # Force cleanup
    send(router, :force_cleanup)
    Process.sleep(100)
    
    # Monitors should be cleaned up
    final_monitors = :erlang.system_info(:monitor_count)
    assert final_monitors <= initial_monitors
  end
end
```

## Stage 1.3: Fix Race Conditions in Critical Services (Day 2 Morning)

### The Problem
Rate limiter and other services have race conditions in their atomic operations.

### Critical Fix: Rate Limiter Race Condition

**File**: `lib/foundation/services/rate_limiter.ex:533-541`

**Current BROKEN Code**:
```elixir
# RACE CONDITION: Check and update are not atomic!
new_count = :ets.update_counter(:rate_limit_buckets, bucket_key, {2, 1}, {bucket_key, 0})

if new_count > limiter_config.limit do
  # Another process could increment here!
  :ets.update_counter(:rate_limit_buckets, bucket_key, {2, -1})
  {:deny, new_count - 1}
else
  {:allow, new_count}
end
```

**Fixed Code using Compare-and-Swap**:
```elixir
defp check_and_increment_rate_limit(limiter_key, limiter_config, current_time) do
  window_start = current_time - rem(current_time, limiter_config.scale_ms)
  bucket_key = {limiter_key, window_start}
  
  ensure_rate_limit_table()
  
  # Use match spec for atomic check-and-increment
  match_spec = [
    {
      {bucket_key, :"$1"},
      [{:"<", :"$1", limiter_config.limit}],
      [{:"+", :"$1", 1}]
    }
  ]
  
  case :ets.select_replace(:rate_limit_buckets, match_spec) do
    1 ->
      # Successfully incremented within limit
      count = :ets.lookup_element(:rate_limit_buckets, bucket_key, 2)
      {:allow, count}
    0 ->
      # Over limit or doesn't exist
      case :ets.lookup(:rate_limit_buckets, bucket_key) do
        [] ->
          # First request in window
          :ets.insert(:rate_limit_buckets, {bucket_key, 1})
          {:allow, 1}
        [{_, count}] when count >= limiter_config.limit ->
          # Over limit
          {:deny, count}
        [{_, count}] ->
          # Race condition - retry once
          check_and_increment_rate_limit(limiter_key, limiter_config, current_time)
      end
  end
end
```

### Testing Race Conditions
```elixir
test "rate limiter has no race conditions under concurrent load" do
  {:ok, _limiter} = RateLimiter.start_link()
  
  RateLimiter.configure_limiter(:test_limiter, %{
    scale_ms: 1000,
    limit: 100,
    cleanup_interval: 60_000
  })
  
  # Spawn 200 concurrent requests (2x the limit)
  parent = self()
  
  tasks = for i <- 1..200 do
    Task.async(fn ->
      result = RateLimiter.check_rate_limit(:test_limiter, "user_1")
      send(parent, {:result, i, result})
      result
    end)
  end
  
  # Collect results
  results = for task <- tasks, do: Task.await(task)
  
  # Exactly 100 should be allowed, 100 denied
  allowed = Enum.count(results, &match?({:ok, :allowed}, &1))
  denied = Enum.count(results, &match?({:ok, :denied}, &1))
  
  assert allowed == 100
  assert denied == 100
end
```

## Stage 1.4: Fix Telemetry Control Flow Anti-Pattern (Day 2 Afternoon)

### The Problem
`Foundation.ServiceIntegration.SignalCoordinator` uses telemetry for control flow - a fundamental misuse of observability tools.

### File to Fix
`lib/foundation/service_integration/signal_coordinator.ex`

### Current ANTI-PATTERN:
```elixir
def emit_signal_sync(agent, signal, opts \\ []) do
  coordination_ref = make_ref()
  caller_pid = self()
  handler_id = "sync_coordination_#{inspect(coordination_ref)}"
  
  # WRONG: Using telemetry as a callback mechanism!
  :telemetry.attach(
    handler_id,
    [:jido, :signal, :routed],
    fn _event, measurements, metadata, _config ->
      if metadata[:signal_id] == signal_id do
        send(caller_pid, {coordination_ref, :routing_complete, ...})
      end
    end,
    nil
  )
  
  # Race condition: Event might fire before handler attached!
  emit_signal_safely(...)
  
  receive do
    {^coordination_ref, :routing_complete, result} -> {:ok, result}
  after
    timeout -> {:error, :timeout}
  end
end
```

### Correct Implementation:
```elixir
defmodule Foundation.ServiceIntegration.SignalCoordinator do
  # DELETE the entire emit_signal_sync function
  
  # If synchronous emission is needed, implement it properly:
  def emit_signal_sync(agent, signal, opts \\ []) do
    # Use GenServer.call to the router for guaranteed delivery
    timeout = Keyword.get(opts, :timeout, 5000)
    
    case JidoFoundation.SignalRouter.route_signal_sync(
      signal[:type], 
      signal, 
      timeout
    ) do
      {:ok, routed_count} -> 
        {:ok, %{routed_to: routed_count}}
      error -> 
        error
    end
  end
end

# Add to SignalRouter:
def route_signal_sync(signal_type, signal, timeout \\ 5000) do
  GenServer.call(__MODULE__, {:route_signal_sync, signal_type, signal}, timeout)
end

def handle_call({:route_signal_sync, signal_type, signal}, _from, state) do
  # Synchronously route and count deliveries
  handlers = get_matching_handlers(signal_type, state.subscriptions)
  
  delivered = Enum.count(handlers, fn handler_pid ->
    # Use monitored send for delivery confirmation
    ref = Process.monitor(handler_pid)
    send(handler_pid, {:routed_signal, signal_type, %{}, signal})
    
    receive do
      {:DOWN, ^ref, :process, ^handler_pid, _} -> false
    after
      0 -> 
        Process.demonitor(ref, [:flush])
        true
    end
  end)
  
  {:reply, {:ok, delivered}, state}
end
```

## Stage 1.5: Fix Dangerous Error Handling (Day 3 Morning)

### The Problem
Overly broad try/catch blocks that swallow errors and prevent "let it crash" philosophy.

### Files to Fix

1. **`lib/foundation/error_handler.ex`** - The worst offender
2. **`lib/jido_system/actions/process_task.ex`** - Catches all exceptions

### Pattern to ELIMINATE:
```elixir
# WRONG - Swallows all errors including bugs
try do
  complex_logic()
rescue
  exception -> {:error, exception}  # NO! This hides bugs
catch
  kind, reason -> {:error, {kind, reason}}  # NO! Prevents supervision
end
```

### Correct Pattern:
```elixir
# RIGHT - Only catch expected, recoverable errors
try do
  complex_logic()
rescue
  # Be specific about what you can handle
  error in [Mint.HTTPError, DBConnection.ConnectionError] ->
    {:error, {:network_error, error}}
  # Let everything else crash!
end
```

### Fix for error_handler.ex:
```elixir
defmodule Foundation.ErrorHandler do
  # DELETE the safe_execute function entirely
  
  # Replace with specific error handlers
  def handle_network_error(fun) do
    try do
      fun.()
    rescue
      error in [Mint.HTTPError, Finch.Error] ->
        {:error, %Foundation.Error{
          code: :network_error,
          message: Exception.message(error),
          category: :infrastructure
        }}
    end
  end
  
  def handle_database_error(fun) do
    try do
      fun.()
    rescue
      error in DBConnection.ConnectionError ->
        {:error, %Foundation.Error{
          code: :database_error,
          message: Exception.message(error),
          category: :infrastructure
        }}
    end
  end
  
  # For truly unknown operations, just let them run
  # If they crash, the supervisor will handle it!
end
```

## Stage 1.6: Emergency Supervision Strategy Fix (Day 3 Afternoon)

### The Problem
Wrong supervision strategy allows system to run in degraded state without state persistence.

### File to Fix
`lib/jido_system/application.ex`

### Current BROKEN:
```elixir
opts = [
  strategy: :one_for_one,  # WRONG! Allows partial failure
  name: JidoSystem.Supervisor
]
```

### FIXED:
```elixir
def start(_type, _args) do
  children = [
    # State persistence supervisor - MUST start before agents
    JidoSystem.Agents.StateSupervisor,
    
    # Registry for state persistence - depends on StateSupervisor
    {Registry, keys: :unique, name: JidoSystem.StateRegistry},
    
    # Dynamic supervisor for agents - depends on state infrastructure
    {DynamicSupervisor, name: JidoSystem.AgentSupervisor, strategy: :one_for_one},
    
    # ... other children in dependency order
  ]
  
  opts = [
    strategy: :rest_for_one,  # CORRECT! Dependencies respected
    name: JidoSystem.Supervisor,
    max_restarts: 3,
    max_seconds: 5
  ]
  
  Supervisor.start_link(children, opts)
end
```

### Also Remove Test Divergence:
```elixir
# DELETE this entire conditional!
if Mix.env() == :test do
  [strategy: :one_for_one, max_restarts: 100, max_seconds: 10]
else
  [strategy: :rest_for_one, max_restarts: 3, max_seconds: 5]
end
```

## Verification & Testing

### Stage 1 Completion Checklist

1. **Run Full Test Suite**:
```bash
# All tests must pass
mix test

# No credo warnings
mix credo --strict

# No dialyzer warnings
mix dialyzer

# Check for banned patterns
./scripts/check_otp_compliance.sh
```

2. **Monitor Leak Test**:
```bash
# Run the monitor leak test under load
mix test test/foundation/monitor_leak_test.exs --repeat 100
```

3. **Race Condition Test**:
```bash
# Run concurrent tests
mix test test/foundation/race_condition_test.exs --async
```

4. **Supervision Test**:
```bash
# Kill StateSupervisor and verify cascade
iex -S mix
> Process.whereis(JidoSystem.Agents.StateSupervisor) |> Process.exit(:kill)
# Should see ALL agents restart
```

## Summary

These Stage 1 fixes address the most critical "bleeding" issues:
- ✅ Banned dangerous primitives that bypass OTP
- ✅ Fixed resource leaks from missing demonitors  
- ✅ Eliminated race conditions in critical services
- ✅ Removed telemetry control flow anti-pattern
- ✅ Fixed error handling that prevented supervision
- ✅ Corrected supervision strategy for proper dependencies

**Next Document**: `JULY_1_2025_PRE_PHASE_2_OTP_report_02.md` will address core architectural fixes including volatile state and god agents.

## Time Investment
- Day 1: 8 hours (Primitives + Resource Leaks)
- Day 2: 8 hours (Race Conditions + Telemetry)  
- Day 3: 8 hours (Error Handling + Supervision)
- Total: 24 hours of focused work

## Risk Mitigation
1. Each fix includes tests to prevent regression
2. Changes are isolated and can be deployed incrementally
3. CI pipeline will catch any reintroduction of anti-patterns
4. All fixes maintain backward compatibility at API level