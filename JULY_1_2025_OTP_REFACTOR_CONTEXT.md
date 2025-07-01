# OTP Refactor Context & Starting Guide
Generated: July 1, 2025

## Quick Start for New Context

If you're starting fresh, this document provides all the context needed to execute the OTP refactor plan.

## Background

The Foundation/Jido codebase currently exhibits what we call "The Illusion of OTP" - it uses Elixir syntax and OTP modules (GenServer, Supervisor) but actively fights against core OTP principles. This results in:

- **Data loss** when processes crash (no state persistence)
- **Memory leaks** from unmonitored processes  
- **Race conditions** in critical services
- **Brittle tests** using Process.sleep and telemetry for synchronization
- **Poor fault tolerance** despite having supervisors

## Document Reading Order

### 1. Problem Analysis Documents (Read First)
These explain WHY the refactor is critical:

- `JULY_1_2025_PRE_PHASE_2_OTP_report_gem_02b.md` - "The Illusion of OTP" - Core architectural critique
- `JULY_1_2025_PRE_PHASE_2_OTP_report_gem_02c_replaceTelemetryWithOTP.md` - Testing anti-patterns analysis
- `JULY_1_2025_PRE_PHASE_2_OTP_report_gem_01.md` - Current state assessment
- `JULY_1_2025_PRE_PHASE_2_OTP_report.md` - Comprehensive audit results

### 2. Solution Documents (Execute in Order)
These explain HOW to fix the problems:

1. **`JULY_1_2025_PRE_PHASE_2_OTP_report_01.md`** - Critical fixes (2-3 days)
2. **`JULY_1_2025_PRE_PHASE_2_OTP_report_02.md`** - State persistence & architecture (1-2 weeks)
3. **`JULY_1_2025_PRE_PHASE_2_OTP_report_03.md`** - Testing & communication (1 week)
4. **`JULY_1_2025_PRE_PHASE_2_OTP_report_04.md`** - Error handling unification (5-7 days)
5. **`JULY_1_2025_PRE_PHASE_2_OTP_report_05.md`** - Integration & deployment (2 weeks)

## Key Code Locations

### Critical Files to Understand Before Starting

#### Anti-Pattern Examples (Study These)
- `lib/foundation/task_helper.ex` - Contains dangerous spawn fallback
- `lib/jido_foundation/signal_router.ex` - Missing Process.demonitor (line 153, 239)
- `lib/foundation/services/rate_limiter.ex` - Race condition (lines 533-541)
- `lib/foundation/service_integration/signal_coordinator.ex` - Telemetry for control flow
- `lib/jido_system/agents/task_agent.ex` - No state persistence
- `lib/jido_system/agents/coordinator_agent.ex` - God agent anti-pattern

#### Good Patterns (Already Implemented)
- `lib/jido_system/agents/persistent_foundation_agent.ex` - State persistence (needs fixes)
- `lib/jido_system/supervisors/workflow_supervisor.ex` - Proper supervision pattern
- `lib/jido_foundation/scheduler_manager.ex` - Centralized timer management (good fix)

#### Test Anti-Patterns
- Search for `Process.sleep` in `test/` directory - ~65 instances to fix
- Search for `assert_receive.*telemetry` - Telemetry used for synchronization

## Core Concepts to Understand

### 1. Process + State = Inseparable Unit
```elixir
# WRONG - Current pattern
defmodule BadAgent do
  use GenServer
  def init(_), do: {:ok, %{tasks: []}}  # State lost on crash!
end

# RIGHT - Target pattern  
defmodule GoodAgent do
  use PersistentFoundationAgent
  # State automatically persisted and restored
end
```

### 2. Let It Crash Philosophy
```elixir
# WRONG - Current pattern
try do
  complex_operation()
rescue
  e -> {:error, e}  # Hides bugs!
end

# RIGHT - Target pattern
# Only catch EXPECTED errors
try do
  network_call()
rescue
  error in [Mint.HTTPError] -> {:error, error}
  # Let everything else crash!
end
```

### 3. Supervised vs Unsupervised
```elixir
# WRONG - Current pattern
spawn(fn -> do_work() end)  # Orphaned process!

# RIGHT - Target pattern
Task.Supervisor.async_nolink(TaskSupervisor, fn -> do_work() end)
```

### 4. Testing Without Sleep
```elixir
# WRONG - Current pattern
Thing.async_operation()
Process.sleep(100)
assert Thing.done?

# RIGHT - Target pattern
Thing.async_operation()
assert :ok = wait_for(fn -> Thing.done? end)
```

## Quick Audit Commands

Run these to understand current state:

```bash
# Find dangerous patterns
grep -r "spawn(" lib/ --include="*.ex" | wc -l
grep -r "Process\.put\|Process\.get" lib/ --include="*.ex" | wc -l
grep -r "send(" lib/ --include="*.ex" | grep -v "GenServer\|Task" | wc -l

# Find missing demonitors
grep -r "Process\.monitor" lib/ --include="*.ex" -l | xargs grep -L "Process\.demonitor"

# Find test anti-patterns  
grep -r "Process\.sleep" test/ --include="*.exs" | wc -l
grep -r "assert_receive.*telemetry" test/ --include="*.exs" | wc -l

# Check current test status
mix test
```

## Success Criteria

You'll know the refactor is complete when:

1. **Zero unsupervised processes** - Everything under supervision
2. **State survives crashes** - Agents restart with their data intact
3. **No Process.sleep in tests** - All tests use deterministic patterns
4. **Single error type** - All errors are Foundation.Error structs
5. **Safe deployment** - Feature flags enable gradual rollout

## Execution Checklist

- [ ] Read all gem analysis documents to understand problems
- [ ] Set up development environment with full test suite passing
- [ ] Create git branch: `otp-refactor-phase-1`
- [ ] Execute Document 01 (Critical Fixes) - 2-3 days
- [ ] Verify all tests still pass
- [ ] Create branch: `otp-refactor-phase-2`  
- [ ] Execute Document 02 (State & Architecture) - 1-2 weeks
- [ ] Continue through all 5 documents
- [ ] Run production readiness checklist
- [ ] Deploy with feature flags per Document 05

## Common Pitfalls to Avoid

1. **Don't skip the reading** - The gem documents explain critical "why" context
2. **Don't fix symptoms** - Address root causes (e.g., don't just remove sleep, fix the async API)
3. **Don't catch all errors** - Let unexpected errors crash (OTP will restart)
4. **Don't rush deployment** - Use the gradual rollout plan with monitoring

## Questions This Refactor Answers

- Why do our agents lose data when they crash?
- Why are our tests flaky and slow?
- Why do we have memory leaks in production?
- Why doesn't our "fault-tolerant" system actually tolerate faults?
- Why is the codebase hard to reason about?

The answer to all: We're fighting OTP instead of embracing it.

## Ready to Start?

1. Ensure you have all documents listed above
2. Set up a dev environment with `mix test` passing
3. Start with Document 01, Stage 1.1
4. Follow each stage systematically
5. Test thoroughly at each step

The journey from "Elixir with OTP veneer" to "proper OTP application" begins with Document 01!

---

**Note**: This is a significant architectural change but is essential for production reliability. The gradual approach with feature flags ensures safety. Total time: ~5-6 weeks of focused development.