# Sleep Test Fixes Phase 2 - Comprehensive Plan

## Overview

Following successful Phase 1 fixes (19 instances), we need to systematically fix the remaining ~65 sleep instances across the Foundation test suite.

## Current Status

### Phase 1 Achievements:
- Fixed 19 sleep instances
- Established proven patterns
- All affected tests now passing
- Uncovered and resolved fundamental architectural issues

### Remaining Work:
- ~65 sleep instances across multiple test files
- Various patterns requiring different solutions
- Some legitimate uses (TTL testing) to preserve

## Categorized Fix Plan

### Category 1: Process Lifecycle Management (HIGH PRIORITY)
**Pattern**: Tests waiting for process death/restart
**Solution**: Use process monitoring and `wait_for`

**Files to fix**:
1. `supervision_crash_recovery_test.exs` - Multiple process restart waits
2. `resource_leak_detection_test.exs` - Process cleanup verification
3. `foundation_agent_test.exs` - Agent lifecycle testing

**Example fix**:
```elixir
# BEFORE
Process.exit(pid, :kill)
Process.sleep(50)

# AFTER
ref = Process.monitor(pid)
Process.exit(pid, :kill)
assert_receive {:DOWN, ^ref, :process, ^pid, _}, 5000
```

### Category 2: State Change Verification (HIGH PRIORITY)
**Pattern**: Waiting for GenServer state updates
**Solution**: Use `wait_for` with state polling

**Files to fix**:
1. `circuit_breaker_test.exs` - State transition verification (already partially fixed)
2. `rate_limiter_test.exs` - Rate limit window updates
3. `cache_test.exs` - Cache operation verification

**Example fix**:
```elixir
# BEFORE
GenServer.cast(server, :update)
Process.sleep(100)
state = GenServer.call(server, :get_state)

# AFTER
GenServer.cast(server, :update)
wait_for(fn ->
  case GenServer.call(server, :get_state) do
    %{updated: true} -> true
    _ -> nil
  end
end)
```

### Category 3: Telemetry Event Synchronization (MEDIUM PRIORITY)
**Pattern**: Waiting for telemetry events
**Solution**: Use telemetry event handlers with assert_receive

**Files to fix**:
1. `cache_telemetry_test.exs` - Cache events (1 legitimate TTL sleep to keep)
2. `telemetry_test.exs` - General telemetry testing
3. `span_test.exs` - Span timing verification

**Example fix**:
```elixir
# BEFORE
perform_operation()
Process.sleep(50)
assert telemetry_received?()

# AFTER
ref = make_ref()
:telemetry.attach(
  "test-#{inspect(ref)}",
  [:foundation, :operation, :complete],
  fn _, _, metadata, config ->
    send(config.test_pid, {:event_received, metadata})
  end,
  %{test_pid: self()}
)
perform_operation()
assert_receive {:event_received, _}, 5000
:telemetry.detach("test-#{inspect(ref)}")
```

### Category 4: Background Work Simulation (LOW PRIORITY)
**Pattern**: Simulating work with sleep
**Solution**: Remove sleep or use actual computation

**Files to fix**:
1. `batch_operations_test.exs` - Work simulation
2. `performance_benchmark_test.exs` - Load testing
3. `load_test_test.exs` - Performance testing

**Example fix**:
```elixir
# BEFORE
fn item ->
  Process.sleep(10)  # Simulate work
  item * 2
end

# AFTER
fn item ->
  # Do actual computation or just return
  item * 2
end
```

### Category 5: Test Process Management (LOW PRIORITY)
**Pattern**: Spawning processes with sleep(:infinity)
**Solution**: Usually fine, but can use receive blocks

**Files to fix**:
1. `serial_operations_test.exs` - Test process spawning
2. `atomic_transaction_test.exs` - Transaction testing

**Note**: `spawn(fn -> :timer.sleep(:infinity) end)` is generally acceptable for keeping test processes alive.

### Category 6: Legitimate Time-Based Testing (PRESERVE)
**Pattern**: Testing actual time-based features
**Solution**: Keep minimal sleep with clear documentation

**Files to preserve**:
1. `cache_telemetry_test.exs` - TTL expiry testing (15ms)
2. `sampler_test.exs` - Time-based sampling

## Implementation Strategy

### Phase 2A: Critical Infrastructure (Days 1-2)
1. Fix all process lifecycle sleeps in supervision tests
2. Fix state change verification in core services
3. Run full test suite after each file

### Phase 2B: Service Layer (Days 3-4)
1. Fix telemetry synchronization
2. Fix rate limiting and cache tests
3. Verify no performance regression

### Phase 2C: Cleanup (Day 5)
1. Remove work simulation sleeps
2. Document legitimate time-based tests
3. Add CI checks to prevent regression

## Success Metrics

1. **Zero sleep instances** (except documented legitimate uses)
2. **All tests passing** reliably
3. **Test execution time** reduced by >50%
4. **No intermittent failures** in CI
5. **Clear documentation** for any remaining time-based tests

## Tools and Patterns

### Available Helpers:
- `Foundation.AsyncTestHelpers.wait_for/3`
- `assert_telemetry_event` macro
- Process monitoring patterns
- Task.await for synchronous completion

### Key Principles:
1. **Deterministic over time-based** - Always prefer explicit synchronization
2. **Event-driven testing** - Use telemetry and messages
3. **State verification** - Poll for expected state changes
4. **Document exceptions** - Any remaining sleep must have clear justification

## Risk Mitigation

1. **Test each fix** - Run affected test file after changes
2. **Preserve semantics** - Ensure test still validates intended behavior
3. **Watch for cascading failures** - Some tests may depend on timing
4. **Keep audit trail** - Document all changes in worklog

## Next Steps

1. Start with `supervision_crash_recovery_test.exs` (highest sleep count)
2. Apply patterns systematically
3. Run tests frequently
4. Update worklog with progress
5. Create PR after each major category

This plan provides a clear path to eliminating the remaining sleep instances while maintaining test reliability and improving overall test suite performance.