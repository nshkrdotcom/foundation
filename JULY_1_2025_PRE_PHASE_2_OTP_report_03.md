# OTP Refactor Plan - Document 03: Testing Architecture & Communication Patterns
Generated: July 1, 2025

## Executive Summary

This document addresses the testing anti-patterns and communication issues that make the system brittle and hard to test. We'll replace telemetry-based test synchronization with proper OTP patterns and fix unreliable messaging throughout the system.

**Time Estimate**: 1 week
**Risk**: Medium - primarily affects tests and communication paths
**Impact**: Dramatic improvement in test reliability and system debuggability

## Context & Required Reading

1. **CRITICAL**: Read `JULY_1_2025_PRE_PHASE_2_OTP_report_gem_02c_replaceTelemetryWithOTP.md`
2. Review `JULY_1_2025_PRE_PHASE_2_OTP_report_gem_02d_replaceTelemetryWithOTP.md`
3. Understand current anti-patterns in `test/` directory

## The Core Problems

From the gem documents:
1. **Telemetry used for control flow** - "Testing the fire alarm, not the fire"
2. **Process.sleep everywhere** - Hides real synchronization issues
3. **Unreliable send/2** - No delivery guarantees for critical messages
4. **Untestable APIs** - Only async operations with no sync alternatives

## Stage 3.1: Build Proper Test Foundation (Day 1)

### Step 1: Create Foundation.Test.Helpers

**File**: `test/support/foundation_test_helpers.ex`

```elixir
defmodule Foundation.Test.Helpers do
  @moduledoc """
  Synchronous helpers for testing asynchronous OTP systems.
  Eliminates Process.sleep and telemetry-based synchronization.
  """
  
  @doc """
  Primary helper: Performs an async operation and waits for completion.
  """
  def sync_operation(server, message, checker_fun, timeout \\ 1000) do
    :ok = GenServer.cast(server, message)
    wait_for(checker_fun, timeout)
  end
  
  @doc """
  Polls a condition function until it returns true or timeout.
  This is our ONLY sanctioned waiting mechanism.
  """
  def wait_for(condition_fun, timeout \\ 1000) when is_function(condition_fun, 0) do
    start_time = System.monotonic_time(:millisecond)
    wait_interval = 10  # ms
    
    Stream.repeatedly(fn ->
      cond do
        condition_fun.() ->
          :ok
          
        System.monotonic_time(:millisecond) - start_time > timeout ->
          :timeout
          
        true ->
          :timer.sleep(wait_interval)
          :continue
      end
    end)
    |> Enum.find(&(&1 != :continue))
    |> case do
      :ok -> :ok
      :timeout -> {:error, :timeout}
    end
  end
  
  @doc """
  Waits for a process to reach a specific state.
  """
  def wait_for_state(pid, state_check, timeout \\ 1000) do
    wait_for(fn ->
      if Process.alive?(pid) do
        :sys.get_state(pid) |> state_check.()
      else
        false
      end
    end, timeout)
  end
  
  @doc """
  Waits for a GenServer call to return a specific value.
  """
  def wait_for_condition(server, call_msg, condition, timeout \\ 1000) do
    wait_for(fn ->
      try do
        result = GenServer.call(server, call_msg, 100)
        condition.(result)
      catch
        :exit, {:timeout, _} -> false
        :exit, {:noproc, _} -> false
      end
    end, timeout)
  end
  
  @doc """
  Ensures a process has processed all messages in its mailbox.
  """
  def drain_mailbox(pid) do
    :sys.suspend(pid)
    :sys.resume(pid)
    :ok
  end
end
```

### Step 2: Create Test-Only Supervisor

**File**: `test/support/foundation_test_supervisor.ex`

```elixir
defmodule Foundation.Test.Supervisor do
  @moduledoc """
  Supervisor for test-specific infrastructure.
  Allows aggressive restart strategies without affecting production.
  """
  
  use Supervisor
  
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    children = [
      # Test-specific task supervisor with lenient settings
      {Task.Supervisor, name: Foundation.Test.TaskSupervisor},
      
      # Test event collector (replaces telemetry handlers)
      Foundation.Test.EventCollector,
      
      # Test-specific registry
      {Registry, keys: :unique, name: Foundation.Test.Registry}
    ]
    
    Supervisor.init(children, 
      strategy: :one_for_one,
      # Lenient for tests
      max_restarts: 1000,
      max_seconds: 1
    )
  end
end
```

### Step 3: Create Telemetry Test Helpers (Correct Usage)

**File**: `test/support/telemetry_test_helpers.ex`

```elixir
defmodule Foundation.Test.TelemetryHelpers do
  @moduledoc """
  CORRECT telemetry testing - verification only, never synchronization.
  """
  
  import ExUnit.Assertions
  
  @doc """
  Captures telemetry events during block execution.
  Events are available AFTER the block completes.
  """
  defmacro assert_telemetry(event_pattern, assertions \\ quote(do: _), do: block) do
    quote do
      test_pid = self()
      handler_ref = make_ref()
      
      # Attach handler
      :telemetry.attach(
        {__MODULE__, handler_ref},
        unquote(event_pattern),
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, handler_ref, measurements, metadata})
        end,
        nil
      )
      
      # Execute block synchronously
      result = unquote(block)
      
      # Detach immediately
      :telemetry.detach({__MODULE__, handler_ref})
      
      # Now check what events were emitted
      events = collect_telemetry_events(handler_ref)
      
      # Allow custom assertions
      unquote(assertions) = events
      
      result
    end
  end
  
  defp collect_telemetry_events(handler_ref) do
    receive do
      {:telemetry_event, ^handler_ref, measurements, metadata} ->
        [{measurements, metadata} | collect_telemetry_events(handler_ref)]
    after
      0 -> []
    end
  end
  
  @doc """
  Asserts specific telemetry event was emitted.
  """
  def assert_telemetry_emitted(events, event_match) do
    assert Enum.any?(events, fn {measurements, metadata} ->
      match?({^event_match, _}, {metadata, measurements}) or
      match?(^event_match, metadata)
    end), "Expected telemetry event matching #{inspect(event_match)} but got #{inspect(events)}"
  end
end
```

## Stage 3.2: Make APIs Testable (Days 2-3)

### Pattern: Add Synchronous Test APIs

For every async operation, add a sync version for testing.

### Example 1: Circuit Breaker

**File**: `lib/foundation/services/circuit_breaker.ex`

```elixir
defmodule Foundation.Services.CircuitBreaker do
  # Existing async API
  def handle_cast({:record_failure, service_id}, state) do
    new_state = record_failure_impl(service_id, state)
    maybe_emit_telemetry(new_state)
    {:noreply, new_state}
  end
  
  # NEW: Synchronous test API
  @doc "Synchronous version for testing. Do not use in production."
  def handle_call({:record_failure_sync, service_id}, _from, state) do
    new_state = record_failure_impl(service_id, state)
    maybe_emit_telemetry(new_state)
    {:reply, :ok, new_state}
  end
  
  @doc "Test helper to trip circuit breaker synchronously"
  def trip_circuit_sync(circuit_breaker, failure_count \\ 5) do
    for _ <- 1..failure_count do
      GenServer.call(circuit_breaker, {:record_failure_sync, :test_service})
    end
    :ok
  end
  
  # Extract business logic for reuse
  defp record_failure_impl(service_id, state) do
    # Original implementation
    # ...
  end
end
```

### Example 2: Rate Limiter

**File**: `lib/foundation/services/rate_limiter.ex`

```elixir
defmodule Foundation.Services.RateLimiter do
  # Add sync reset for testing
  def handle_call({:reset_limiter_sync, limiter_id}, _from, state) do
    # Clear all buckets for limiter
    clear_limiter_buckets(limiter_id)
    {:reply, :ok, state}
  end
  
  # Test helper
  def reset_for_testing(limiter_id) do
    GenServer.call(__MODULE__, {:reset_limiter_sync, limiter_id})
  end
end
```

### Example 3: Agent Operations

**File**: `lib/jido_system/agents/task_agent.ex`

```elixir
defmodule JidoSystem.Agents.TaskAgent do
  # Add sync task completion for testing
  def handle_call({:complete_task_sync, task_id}, _from, state) do
    case complete_task_impl(task_id, state) do
      {:ok, new_state} ->
        # Ensure state is persisted
        save_state(%{state | state: new_state})
        {:reply, :ok, new_state}
      error ->
        {:reply, error, state}
    end
  end
  
  # Test helper module
  defmodule TestHelpers do
    def complete_all_tasks_sync(agent) do
      tasks = GenServer.call(agent, :get_all_tasks)
      Enum.each(tasks, fn task ->
        GenServer.call(agent, {:complete_task_sync, task.id})
      end)
    end
  end
end
```

## Stage 3.3: Fix Communication Patterns (Days 4-5)

### Problem: Raw send/2 Usage

From our audit, these files use raw `send/2`:
1. `signal_router.ex` - For signal delivery
2. `coordination_manager.ex` - Falls back to send
3. Various test files

### Fix 1: Signal Router with Acknowledgments

**File**: `lib/jido_foundation/signal_router.ex`

```elixir
defmodule JidoFoundation.SignalRouter do
  # Current BROKEN - no delivery guarantee
  defp route_signal_to_handlers(signal_type, measurements, metadata, subscriptions) do
    matching_handlers
    |> Enum.map(fn handler_pid ->
      send(handler_pid, {:routed_signal, signal_type, measurements, metadata})
      :ok  # Assumes success!
    end)
  end
  
  # FIXED - with delivery confirmation
  defp route_signal_to_handlers(signal_type, measurements, metadata, subscriptions) do
    matching_handlers
    |> Enum.map(fn handler_pid ->
      deliver_signal(handler_pid, signal_type, measurements, metadata)
    end)
  end
  
  defp deliver_signal(handler_pid, signal_type, measurements, metadata) do
    # Monitor for immediate failure detection
    ref = Process.monitor(handler_pid)
    
    # Send with unique ref for correlation
    msg_ref = make_ref()
    send(handler_pid, {:routed_signal, msg_ref, signal_type, measurements, metadata})
    
    # Check if process died immediately
    receive do
      {:DOWN, ^ref, :process, ^handler_pid, reason} ->
        {:error, {:handler_died, reason}}
    after
      0 ->
        Process.demonitor(ref, [:flush])
        {:ok, msg_ref}
    end
  end
  
  # Add acknowledged delivery for critical signals
  def route_signal_sync(signal_type, signal, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)
    require_ack = Keyword.get(opts, :require_ack, false)
    
    GenServer.call(__MODULE__, 
      {:route_signal_sync, signal_type, signal, require_ack}, 
      timeout
    )
  end
  
  def handle_call({:route_signal_sync, signal_type, signal, require_ack}, from, state) do
    if require_ack do
      # Use Task to route and collect acknowledgments
      task = Task.async(fn ->
        handlers = get_matching_handlers(signal_type, state.subscriptions)
        
        tasks = Enum.map(handlers, fn handler_pid ->
          Task.async(fn ->
            call_with_timeout(handler_pid, {:handle_signal, signal}, 1000)
          end)
        end)
        
        results = Task.await_many(tasks, 5000)
        {successful, _failed} = Enum.split_with(results, &match?({:ok, _}, &1))
        
        length(successful)
      end)
      
      # Don't block the GenServer
      spawn(fn ->
        result = Task.await(task)
        GenServer.reply(from, {:ok, result})
      end)
      
      {:noreply, state}
    else
      # Fast path - no ack required
      count = route_signal_to_handlers(signal_type, %{}, signal, state.subscriptions)
      {:reply, {:ok, count}, state}
    end
  end
end
```

### Fix 2: CoordinationManager Reliable Delivery

**File**: `lib/jido_foundation/coordination_manager.ex`

```elixir
defmodule JidoFoundation.CoordinationManager do
  # Current BROKEN - falls back to unreliable send
  defp attempt_message_delivery(pid, message, state) do
    try do
      GenServer.call(pid, {:coordination_message, message}, 1000)
      {:ok, :delivered}
    catch
      :exit, _ ->
        # WRONG: Falls back to fire-and-forget
        send(pid, message)
        {:ok, :sent_async}
    end
  end
  
  # FIXED - reliable delivery only
  defp attempt_message_delivery(pid, message, state) do
    ref = Process.monitor(pid)
    
    try do
      # Always use call for critical coordination
      result = GenServer.call(pid, {:coordination_message, message}, 1000)
      Process.demonitor(ref, [:flush])
      {:ok, result}
    catch
      :exit, {:timeout, _} ->
        Process.demonitor(ref, [:flush])
        # Don't fall back to send - buffer instead
        {:error, :timeout}
        
      :exit, {:noproc, _} ->
        Process.demonitor(ref, [:flush])
        {:error, :process_dead}
    end
  end
  
  # Agents must implement handle_call
  def handle_call({:coordination_message, message}, _from, state) do
    # Process coordination message
    result = process_coordination_message(message, state)
    {:reply, {:ok, result}, state}
  end
end
```

## Stage 3.4: Migrate Tests Away from Anti-Patterns (Days 6-7)

### Migration Strategy

1. Find all Process.sleep occurrences
2. Identify what they're waiting for
3. Replace with proper patterns

### Example Test Migrations

#### Before: Circuit Breaker Test
```elixir
test "circuit opens after failures" do
  {:ok, breaker} = CircuitBreaker.start_link(config)
  
  # Anti-pattern: Telemetry for synchronization
  test_pid = self()
  :telemetry.attach(
    "test-handler",
    [:circuit_breaker, :state_change],
    fn _, _, %{state: new_state}, _ ->
      send(test_pid, {:state_changed, new_state})
    end,
    nil
  )
  
  # Trigger failures
  for _ <- 1..5, do: CircuitBreaker.record_failure(breaker, :test)
  
  # Anti-pattern: Wait for telemetry
  assert_receive {:state_changed, :open}, 1000
end
```

#### After: Circuit Breaker Test
```elixir
test "circuit opens after failures" do
  {:ok, breaker} = CircuitBreaker.start_link(config)
  
  # Correct: Use telemetry only for verification
  assert_telemetry [:circuit_breaker, :state_change] do
    # Synchronous operation
    CircuitBreaker.trip_circuit_sync(breaker, 5)
  end
  
  # State is guaranteed to be updated
  assert CircuitBreaker.get_state(breaker) == :open
end
```

#### Before: Agent Restart Test
```elixir
test "agent restarts with state" do
  {:ok, agent} = TaskAgent.start_link(id: "test")
  
  TaskAgent.add_task(agent, %{id: 1})
  old_pid = Process.whereis(agent)
  
  Process.exit(agent, :kill)
  Process.sleep(100)  # Anti-pattern!
  
  new_pid = Process.whereis(agent)
  assert new_pid != old_pid
end
```

#### After: Agent Restart Test
```elixir
test "agent restarts with state" do
  {:ok, agent} = TaskAgent.start_link(id: "test")
  
  TaskAgent.add_task(agent, %{id: 1})
  old_pid = Process.whereis(agent)
  
  # Monitor for restart
  ref = Process.monitor(old_pid)
  Process.exit(old_pid, :kill)
  
  # Wait for death confirmation
  assert_receive {:DOWN, ^ref, :process, ^old_pid, :killed}
  
  # Wait for restart
  assert :ok = Foundation.Test.Helpers.wait_for(fn ->
    case Process.whereis(TaskAgent) do
      nil -> false
      new_pid -> new_pid != old_pid
    end
  end)
  
  # Verify state was restored
  new_agent = Process.whereis(TaskAgent)
  state = TaskAgent.get_state(new_agent)
  assert length(state.tasks) == 1
end
```

### Create Test Migration Script

**File**: `scripts/migrate_tests.exs`

```elixir
defmodule TestMigrator do
  @sleep_pattern ~r/Process\.sleep\(\s*(\d+)\s*\)/
  @receive_pattern ~r/assert_receive\s+.+,\s+(\d+)/
  
  def find_test_anti_patterns do
    Path.wildcard("test/**/*_test.exs")
    |> Enum.flat_map(&find_issues_in_file/1)
    |> Enum.group_by(& &1.type)
  end
  
  defp find_issues_in_file(path) do
    content = File.read!(path)
    lines = String.split(content, "\n")
    
    issues = []
    
    Enum.with_index(lines, 1)
    |> Enum.reduce(issues, fn {line, line_no}, acc ->
      cond do
        Regex.match?(@sleep_pattern, line) ->
          [{:sleep, path, line_no, line} | acc]
          
        Regex.match?(@receive_pattern, line) ->
          [{:receive_timeout, path, line_no, line} | acc]
          
        String.contains?(line, "assert_telemetry_event") ->
          [{:telemetry_sync, path, line_no, line} | acc]
          
        true ->
          acc
      end
    end)
  end
  
  def generate_report do
    issues = find_test_anti_patterns()
    
    IO.puts "Test Anti-Pattern Report"
    IO.puts "======================="
    IO.puts ""
    
    Enum.each(issues, fn {type, instances} ->
      IO.puts "#{type}: #{length(instances)} instances"
      
      Enum.each(instances, fn {_, path, line_no, content} ->
        IO.puts "  #{path}:#{line_no}"
        IO.puts "    #{String.trim(content)}"
      end)
      
      IO.puts ""
    end)
  end
end

TestMigrator.generate_report()
```

## Stage 3.5: CI/CD Integration

### Add Test Quality Gates

**File**: `.github/workflows/test_quality.yml`

```yaml
name: Test Quality Check

on: [push, pull_request]

jobs:
  test-quality:
    runs-on: ubuntu-latest
    
    steps:
    - uses: actions/checkout@v2
    
    - name: Check for Process.sleep in tests
      run: |
        if grep -r "Process\.sleep" test/ --include="*_test.exs"; then
          echo "❌ Found Process.sleep in tests!"
          echo "Use Foundation.Test.Helpers.wait_for instead"
          exit 1
        fi
        
    - name: Check for telemetry synchronization
      run: |
        if grep -r "assert_receive.*telemetry" test/; then
          echo "❌ Found telemetry used for synchronization!"
          echo "Use assert_telemetry macro instead"
          exit 1
        fi
        
    - name: Check for raw send in lib
      run: |
        # Allow send in specific modules that need it
        if grep -r "send(" lib/ --include="*.ex" | grep -v "GenServer\|Task\|Agent"; then
          echo "⚠️  Found raw send usage - verify it's intentional"
        fi
```

### Create Test Best Practices Guide

**File**: `test/TEST_GUIDELINES.md`

```markdown
# Foundation Test Guidelines

## ✅ DO

1. **Use Foundation.Test.Helpers.wait_for** for async operations
   ```elixir
   assert :ok = wait_for(fn -> 
     SomeModule.get_state().ready? 
   end)
   ```

2. **Add synchronous test APIs** to GenServers
   ```elixir
   def handle_call(:force_timeout_sync, _from, state) do
     {:reply, :ok, %{state | status: :timeout}}
   end
   ```

3. **Use assert_telemetry** for verification only
   ```elixir
   assert_telemetry [:my_app, :event] do
     MyApp.do_something_sync()
   end
   ```

## ❌ DON'T

1. **Never use Process.sleep** - hides race conditions
2. **Never use telemetry for synchronization** - it's for observation
3. **Never use assert_receive with timeouts** - flaky and slow
4. **Never use raw send for testing** - no delivery guarantees

## Test Patterns

### Waiting for State Changes
```elixir
# ❌ BAD
Process.sleep(100)
assert Thing.get_state() == :ready

# ✅ GOOD  
assert :ok = wait_for(fn -> Thing.get_state() == :ready end)
```

### Testing Async Operations
```elixir
# ❌ BAD
Thing.async_operation()
Process.sleep(1000)
assert Thing.operation_complete?()

# ✅ GOOD
Thing.async_operation()
assert :ok = wait_for(&Thing.operation_complete?/0)
```

### Testing Process Crashes
```elixir
# ❌ BAD
Process.exit(pid, :kill)
Process.sleep(100)

# ✅ GOOD
ref = Process.monitor(pid)
Process.exit(pid, :kill)
assert_receive {:DOWN, ^ref, :process, ^pid, :killed}
```
```

## Success Metrics

1. **Zero Process.sleep** in test suite
2. **All tests pass with async: true**
3. **Test suite runs 50% faster**
4. **Zero flaky tests in CI**
5. **100% of async operations have sync test APIs**

## Summary

Stage 3 establishes proper testing patterns by:
1. Creating robust test helpers that eliminate sleep
2. Adding synchronous APIs for all async operations
3. Fixing communication to use reliable patterns
4. Migrating all tests to proper patterns
5. Enforcing standards through CI/CD

This creates a test suite that is:
- **Fast** - No artificial delays
- **Reliable** - No race conditions
- **Clear** - Tests show actual behavior, not side effects
- **Maintainable** - Patterns are enforced and documented

**Next Document**: `JULY_1_2025_PRE_PHASE_2_OTP_report_04.md` will cover error handling unification and system-wide patterns.