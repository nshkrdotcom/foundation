# Sleep Test Fixes Strategy - July 1, 2025

## Executive Summary

Following the successful fix of an intermittent test failure in `agent_registry_test.exs`, this document outlines a systematic approach to fixing the remaining **106 sleep instances** across the Foundation test suite.

## Context and References

### Required Reading
1. **`test/SLEEPFIXES.md`** - Comprehensive 85+ sleep migration completed June 30, 2025
   - Documents patterns for replacing Process.sleep with deterministic helpers
   - Shows successful migration of task_agent_test.exs as gold standard
   - Provides phase-by-phase migration strategy

2. **`test/THE_TELEMETRY_MANUAL.md`** - Foundation telemetry system documentation
   - Event-driven testing without timing hacks
   - Telemetry event structure and categories
   - Test helper macros for event assertions

3. **`test/support/async_test_helpers.ex`** - Async testing utilities
   - `wait_for/3` function for polling conditions
   - Acceptable replacement for Process.sleep in complex scenarios

## Problem Analysis

### Current State
- **106 instances** of sleep patterns remain after June 30 migration
- These represent either:
  1. New tests added after the migration
  2. Tests missed in the original sweep
  3. Legitimate timing requirements (rare)

### Sleep Anti-Pattern Categories

1. **Process Lifecycle Synchronization** (Most Common)
   ```elixir
   # BAD: Arbitrary wait for process death/restart
   Process.exit(pid, :kill)
   Process.sleep(100)
   assert new_pid = Process.whereis(Name)
   ```

2. **Async Operation Completion**
   ```elixir
   # BAD: Fixed delay for background work
   Task.async(fn -> do_work() end)
   Process.sleep(500)
   assert work_completed?()
   ```

3. **State Change Verification**
   ```elixir
   # BAD: Hope state changed after delay
   CircuitBreaker.trip(service)
   Process.sleep(50)
   assert CircuitBreaker.open?(service)
   ```

## Fix Strategy

### Pattern 1: Telemetry-Based Synchronization (PREFERRED)

**When to use**: When the system emits telemetry events for state changes

**Example**: Agent registry cleanup (from today's fix)
```elixir
# GOOD: Wait for specific telemetry event
ref = make_ref()
:telemetry.attach(
  "test-#{inspect(ref)}",
  [:foundation, :mabeam, :registry, :agent_down],
  fn _event, _measurements, metadata, config ->
    if metadata.agent_id == agent_id do
      send(config.test_pid, {:agent_cleaned_up, metadata})
    end
  end,
  %{test_pid: self()}
)

Process.exit(agent_pid, :kill)
assert_receive {:agent_cleaned_up, _metadata}, 5000
:telemetry.detach("test-#{inspect(ref)}")
```

### Pattern 2: State Polling with wait_for

**When to use**: When no telemetry events available but state is queryable

**Example**: Service restart detection
```elixir
# GOOD: Poll for state change
import Foundation.AsyncTestHelpers

old_pid = Process.whereis(ServiceName)
Process.exit(old_pid, :kill)

new_pid = wait_for(fn ->
  case Process.whereis(ServiceName) do
    nil -> nil
    pid when pid != old_pid -> pid
    _ -> nil
  end
end, 5000)

assert is_pid(new_pid)
assert new_pid != old_pid
```

### Pattern 3: Synchronous Task Completion

**When to use**: For Task-based async operations

**Example**: Background work completion
```elixir
# GOOD: Use Task.await for synchronous completion
task = Task.async(fn -> expensive_computation() end)
result = Task.await(task, 10_000)
assert {:ok, _} = result
```

### Pattern 4: Message-Based Synchronization

**When to use**: When you control both sides of communication

**Example**: Process coordination
```elixir
# GOOD: Use messages for synchronization
test_pid = self()
worker = spawn(fn ->
  do_setup()
  send(test_pid, :ready)
  receive do
    :continue -> do_work()
  end
end)

assert_receive :ready, 1000
send(worker, :continue)
```

## Implementation Plan

### Phase 1: Critical Infrastructure Tests (HIGH PRIORITY)
Files with timing-sensitive operations that affect system stability:
- `circuit_breaker_test.exs` - State transitions need telemetry events
- `resource_manager_test.exs` - Resource lifecycle events
- `cache_telemetry_test.exs` - Cache operation events

### Phase 2: Integration Tests (MEDIUM PRIORITY)
Files testing cross-component interactions:
- `integration_validation_test.exs` - Service coordination
- `supervision_crash_recovery_test.exs` - OTP supervision
- `signal_routing_test.exs` - Message delivery

### Phase 3: Agent/Sensor Tests (LOW PRIORITY)
Files with agent lifecycle testing:
- `foundation_agent_test.exs` - Agent state changes
- `system_health_sensor_test.exs` - Periodic measurements
- `task_agent_test.exs` - Already partially migrated

## Key Principles

1. **No Arbitrary Delays**: Every wait must be for a specific, observable condition
2. **Use System Events**: Prefer telemetry/message-based synchronization
3. **Bounded Waits**: All async operations must have reasonable timeouts
4. **Clear Intent**: The wait condition should document what we're waiting for
5. **Test Isolation**: Each test should clean up its telemetry handlers

## Common Pitfalls to Avoid

1. **Don't Replace Sleep with Sleep**: Using `:timer.sleep` is just as bad
2. **Don't Poll Too Frequently**: Use reasonable intervals (10-50ms)
3. **Don't Ignore Timeouts**: Failed waits should fail the test
4. **Don't Leak Handlers**: Always detach telemetry handlers in test cleanup

## Success Metrics

- **Zero sleep instances** in test files (except async_test_helpers.ex internals)
- **Reduced test execution time** by eliminating unnecessary delays
- **Zero intermittent failures** from timing issues
- **Clear test intent** through explicit wait conditions

## Example Migration

### Before (Intermittent Failure)
```elixir
test "automatically removes agent when process dies" do
  short_lived = spawn(fn -> :timer.sleep(10) end)
  :ok = Foundation.register("agent", short_lived, metadata, registry)
  :timer.sleep(50)  # Hope cleanup happened
  assert :error = Foundation.lookup("agent", registry)
end
```

### After (Deterministic)
```elixir
test "automatically removes agent when process dies" do
  test_pid = self()
  short_lived = spawn(fn ->
    send(test_pid, :ready)
    receive do: (:exit -> :ok)
  end)
  
  assert_receive :ready
  :ok = Foundation.register("agent", short_lived, metadata, registry)
  
  # Set up telemetry handler for cleanup event
  ref = make_ref()
  :telemetry.attach(
    "test-#{inspect(ref)}",
    [:foundation, :mabeam, :registry, :agent_down],
    fn _, _, metadata, config ->
      if metadata.agent_id == "agent" do
        send(config.test_pid, :agent_cleaned_up)
      end
    end,
    %{test_pid: test_pid}
  )
  
  Process.exit(short_lived, :kill)
  assert_receive :agent_cleaned_up, 5000
  assert :error = Foundation.lookup("agent", registry)
  
  :telemetry.detach("test-#{inspect(ref)}")
end
```

## Next Steps

1. **Audit**: Run detailed analysis of all 106 sleep instances
2. **Categorize**: Group by pattern type and priority
3. **Migrate**: Fix files in priority order using appropriate patterns
4. **Validate**: Ensure all tests pass reliably under load
5. **Prevent**: Add CI checks to prevent new sleep usage

## Concrete Examples from Current Codebase

### Example 1: Circuit Breaker State Transition (circuit_breaker_test.exs)
```elixir
# CURRENT (line 120)
# Wait for recovery timeout (150ms as configured)
:timer.sleep(150)
:ok = CircuitBreaker.reset(service_id)

# SHOULD BE:
# Wait for circuit breaker timeout event
ref = make_ref()
:telemetry.attach(
  "test-cb-#{inspect(ref)}",
  [:foundation, :circuit_breaker, :recovery_timeout],
  fn _, _, %{service_id: id}, config ->
    if id == service_id do
      send(config.test_pid, :recovery_timeout_reached)
    end
  end,
  %{test_pid: self()}
)

assert_receive :recovery_timeout_reached, 1000
:ok = CircuitBreaker.reset(service_id)
:telemetry.detach("test-cb-#{inspect(ref)}")
```

### Example 2: Process Leak Detection (supervision_crash_recovery_test.exs)
```elixir
# CURRENT (line ~25)
on_exit(fn ->
  # Wait for cleanup (minimal delay)
  :timer.sleep(20)
  # Verify no process leaks
  final_process_count = :erlang.system_info(:process_count)
end)

# SHOULD BE:
on_exit(fn ->
  # Wait for all supervised processes to terminate
  import Foundation.AsyncTestHelpers
  
  wait_for(fn ->
    current_count = :erlang.system_info(:process_count)
    if current_count <= initial_process_count + tolerance do
      true
    else
      nil
    end
  end, 1000)
end)
```

### Example 3: Batch Processing Completion
```elixir
# CURRENT (various files)
TaskPoolManager.execute_batch(:pool, items, fn i ->
  :timer.sleep(10)  # Simulate work
  i * 10
end)

# SHOULD BE:
# For tests, use synchronous execution or Task.await
task = Task.async(fn ->
  TaskPoolManager.execute_batch(:pool, items, fn i ->
    # Actual work without sleep
    i * 10
  end)
end)
results = Task.await(task, 5000)
assert length(results) == length(items)
```

## File-Specific Recommendations

### High-Priority Files (System Critical)

1. **circuit_breaker_test.exs**
   - Add telemetry events for state transitions
   - Replace recovery timeout sleep with event

2. **resource_manager_test.exs**
   - Use resource acquisition/release events
   - Poll resource availability state

3. **cache_telemetry_test.exs**
   - Already uses telemetry, just needs sleep removal
   - Use existing cache hit/miss events

### Medium-Priority Files (Integration Tests)

1. **supervision_crash_recovery_test.exs**
   - Multiple process lifecycle sleeps
   - Use process monitoring and wait_for
   
2. **integration_validation_test.exs**
   - Service restart verification sleeps
   - Use Process.whereis polling pattern

3. **signal_routing_test.exs**
   - Message delivery confirmation
   - Use receive with timeout

## Conclusion

The successful migration of `agent_registry_test.exs` demonstrates that all sleep-based synchronization can be replaced with deterministic patterns. By following the strategies outlined in this document and leveraging Foundation's telemetry system, we can eliminate the remaining 106 instances and achieve a fully deterministic test suite.