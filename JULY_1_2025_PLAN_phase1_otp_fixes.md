# Phase 1: Critical OTP Fixes Implementation Guide

## Overview

This document provides a comprehensive, self-contained guide for fixing all critical OTP violations in the Foundation/Jido system. These fixes MUST be completed before any other work proceeds, as they address fundamental stability issues that affect the entire system.

## Prerequisites

### Required Reading
Before starting, read these documents in order:
1. `FLAWS_report4.md` - Understand the original architectural analysis
2. `CLAUDE.md` - Review architectural principles (supervision-first, protocol-based, test-driven)
3. This document completely

### Development Environment Setup
```bash
# Ensure you have the Foundation project
cd /path/to/foundation

# Run initial test suite to establish baseline
mix test | grep "tests.*failures"
# Expected: ~499 tests, 0-1 intermittent failures

# Ensure all dependencies are available
mix deps.get
mix compile --warnings-as-errors
```

## Critical OTP Violations Inventory

### 🔴 CRITICAL - Day 1 Fixes

#### Fix #1: Process Monitor Memory Leak
**Severity**: CRITICAL - Causes gradual memory exhaustion
**Time Estimate**: 30 minutes
**File**: `lib/mabeam/agent_registry.ex`

**Current Code** (line ~144):
```elixir
def handle_info({:DOWN, monitor_ref, :process, _pid, _reason}, state) do
  case Map.get(state.monitors, monitor_ref) do
    nil -> 
      # BUG: No Process.demonitor called for unknown refs
      {:noreply, state}
    agent_id ->
      # cleanup logic
  end
end
```

**Fixed Code**:
```elixir
def handle_info({:DOWN, monitor_ref, :process, _pid, _reason}, state) do
  # ALWAYS demonitor to prevent leak
  Process.demonitor(monitor_ref, [:flush])
  
  case Map.get(state.monitors, monitor_ref) do
    nil -> 
      Logger.debug("Received :DOWN for unknown monitor ref: #{inspect(monitor_ref)}")
      {:noreply, state}
    agent_id ->
      # existing cleanup logic
      new_monitors = Map.delete(state.monitors, monitor_ref)
      new_agents = Map.delete(state.agents, agent_id)
      {:noreply, %{state | monitors: new_monitors, agents: new_agents}}
  end
end
```

**Test to Add** in `test/mabeam/agent_registry_test.exs`:
```elixir
test "cleans up unknown monitor refs without leaking" do
  {:ok, registry} = AgentRegistry.start_link(name: :test_registry_leak)
  
  # Simulate a DOWN message for unknown monitor
  fake_ref = make_ref()
  send(registry, {:DOWN, fake_ref, :process, self(), :normal})
  
  # Verify process doesn't accumulate monitors
  Process.sleep(10)
  {:dictionary, dict} = Process.info(registry, :dictionary)
  monitors = Keyword.get(dict, :"$monitors", [])
  assert length(monitors) == 0
end
```

---

#### Fix #2: Test/Production Supervisor Strategy Divergence
**Severity**: CRITICAL - Hides production failures in tests
**Time Estimate**: 2-3 hours (may break tests)
**File**: `lib/jido_system/application.ex`

**Current Code** (line ~25):
```elixir
def start(_type, _args) do
  {max_restarts, max_seconds} =
    case Application.get_env(:foundation, :environment, :prod) do
      :test -> {100, 10}  # Too lenient!
      _ -> {3, 5}
    end
```

**Fixed Code**:
```elixir
def start(_type, _args) do
  # ALWAYS use production supervision strategy
  {max_restarts, max_seconds} = {3, 5}
  
  # If tests need different behavior, they should use their own supervisors
  opts = [strategy: :one_for_one, max_restarts: max_restarts, max_seconds: max_seconds]
```

**Test Helper** to add in `test/support/test_supervisor.ex`:
```elixir
defmodule Foundation.TestSupervisor do
  @moduledoc """
  Special supervisor for tests that need more lenient restart policies.
  Only use when testing crash/restart behavior specifically.
  """
  use Supervisor
  
  def start_link(children) do
    # More lenient for specific test scenarios only
    Supervisor.start_link(__MODULE__, children, name: __MODULE__)
  end
  
  @impl true
  def init(children) do
    # Test-specific lenient strategy
    Supervisor.init(children, strategy: :one_for_one, max_restarts: 100, max_seconds: 10)
  end
end
```

**Update Tests**: Search for tests that rely on lenient supervision and update them to use TestSupervisor.

---

### 🔴 CRITICAL - Day 2 Fixes

#### Fix #3: Unsupervised Task.async_stream Operations
**Severity**: CRITICAL - Creates orphaned processes
**Time Estimate**: 2 hours
**Files**: 
- `lib/foundation/batch_operations.ex`
- `lib/ml_foundation/distributed_optimization.ex`

**File 1**: `lib/foundation/batch_operations.ex`

**Current Code** (line ~15):
```elixir
def parallel_map(items, fun, opts \\ []) do
  timeout = Keyword.get(opts, :timeout, 5000)
  max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online())
  
  # Try supervised first, fall back to unsupervised
  case Process.whereis(Foundation.TaskSupervisor) do
    nil ->
      # PROBLEM: Unsupervised fallback!
      Task.async_stream(items, fun, 
        timeout: timeout,
        max_concurrency: max_concurrency,
        on_timeout: :kill_task
      )
    pid when is_pid(pid) ->
      Task.Supervisor.async_stream_nolink(Foundation.TaskSupervisor, items, fun,
        timeout: timeout,
        max_concurrency: max_concurrency,
        on_timeout: :kill_task
      )
  end
  |> Enum.to_list()
end
```

**Fixed Code**:
```elixir
def parallel_map(items, fun, opts \\ []) do
  timeout = Keyword.get(opts, :timeout, 5000)
  max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online())
  
  # ALWAYS require supervisor - fail fast if not available
  case Process.whereis(Foundation.TaskSupervisor) do
    nil ->
      raise "Foundation.TaskSupervisor not running. Ensure Foundation.Application is started."
    pid when is_pid(pid) ->
      Task.Supervisor.async_stream_nolink(Foundation.TaskSupervisor, items, fun,
        timeout: timeout,
        max_concurrency: max_concurrency,
        on_timeout: :kill_task
      )
      |> Enum.to_list()
  end
end
```

**File 2**: `lib/ml_foundation/distributed_optimization.ex`

**Current Code** (line ~78):
```elixir
defp run_random_search(space, evaluator, iterations, parallelism) do
  # Generate all candidates
  candidates = for _ <- 1..iterations, do: SearchSpace.sample(space)
  
  # Evaluate in parallel with fallback
  results = case Process.whereis(Foundation.TaskSupervisor) do
    nil ->
      # PROBLEM: Unsupervised fallback
      Task.async_stream(candidates, evaluator, max_concurrency: parallelism)
    supervisor ->
      Task.Supervisor.async_stream_nolink(supervisor, candidates, evaluator, 
        max_concurrency: parallelism)
  end
  |> Enum.map(fn {:ok, result} -> result end)
```

**Fixed Code**:
```elixir
defp run_random_search(space, evaluator, iterations, parallelism) do
  # Ensure supervisor is available
  supervisor = Process.whereis(Foundation.TaskSupervisor) || 
    raise "Foundation.TaskSupervisor required for distributed optimization"
    
  # Generate all candidates
  candidates = for _ <- 1..iterations, do: SearchSpace.sample(space)
  
  # ALWAYS use supervised execution
  Task.Supervisor.async_stream_nolink(supervisor, candidates, evaluator, 
    max_concurrency: parallelism,
    timeout: :infinity  # Let evaluator handle its own timeouts
  )
  |> Enum.map(fn 
    {:ok, result} -> result
    {:exit, reason} -> 
      Logger.error("Optimization task failed: #{inspect(reason)}")
      nil
  end)
  |> Enum.reject(&is_nil/1)
end
```

**Test Updates**:
```elixir
# In test/foundation/batch_operations_test.exs
test "raises when TaskSupervisor not available" do
  # Stop the supervisor temporarily
  Supervisor.terminate_child(Foundation.Supervisor, Foundation.TaskSupervisor)
  
  assert_raise RuntimeError, ~r/TaskSupervisor not running/, fn ->
    BatchOperations.parallel_map([1, 2, 3], & &1 * 2)
  end
  
  # Restart for other tests
  Supervisor.restart_child(Foundation.Supervisor, Foundation.TaskSupervisor)
end
```

---

### 🔴 CRITICAL - Day 3 Fixes

#### Fix #4: Blocking Circuit Breaker
**Severity**: CRITICAL - System-wide bottleneck
**Time Estimate**: 3 hours
**File**: `lib/foundation/infrastructure/circuit_breaker.ex`

**Current Code** (line ~125):
```elixir
def handle_call({:execute, service_id, function}, _from, state) do
  case get_circuit_state(service_id, state) do
    :open ->
      {:reply, {:error, :circuit_open}, state}
    
    :half_open ->
      # PROBLEM: Blocks GenServer while executing function!
      try do
        result = function.()
        new_state = record_success(service_id, state)
        {:reply, {:ok, result}, new_state}
      rescue
        e ->
          new_state = record_failure(service_id, state)
          {:reply, {:error, e}, new_state}
      end
    
    :closed ->
      # PROBLEM: Also blocks here!
      try do
        result = function.()
        {:reply, {:ok, result}, state}
      rescue
        e ->
          new_state = record_failure(service_id, state)
          {:reply, {:error, e}, new_state}
      end
  end
end
```

**Fixed Code**:
```elixir
def handle_call({:execute, service_id, function}, from, state) do
  case get_circuit_state(service_id, state) do
    :open ->
      {:reply, {:error, :circuit_open}, state}
    
    circuit_state when circuit_state in [:half_open, :closed] ->
      # Execute in supervised task to avoid blocking
      Task.Supervisor.start_child(Foundation.TaskSupervisor, fn ->
        try do
          result = function.()
          
          # Update circuit state based on success
          GenServer.cast(self(), {:record_result, service_id, :success})
          
          # Reply to original caller
          GenServer.reply(from, {:ok, result})
        rescue
          e ->
            # Update circuit state based on failure
            GenServer.cast(self(), {:record_result, service_id, :failure})
            
            # Reply with error
            GenServer.reply(from, {:error, e})
        end
      end)
      
      # Don't block the GenServer
      {:noreply, state}
  end
end

# Add handler for recording results
def handle_cast({:record_result, service_id, :success}, state) do
  new_state = record_success(service_id, state)
  {:noreply, new_state}
end

def handle_cast({:record_result, service_id, :failure}, state) do
  new_state = record_failure(service_id, state)
  {:noreply, new_state}
end
```

**Performance Test** to add:
```elixir
test "circuit breaker remains responsive under load" do
  {:ok, cb} = CircuitBreaker.start_link([])
  
  # Function that takes 100ms
  slow_function = fn -> 
    Process.sleep(100)
    :ok
  end
  
  # Start 10 concurrent executions
  tasks = for _ <- 1..10 do
    Task.async(fn ->
      CircuitBreaker.execute(cb, :test_service, slow_function)
    end)
  end
  
  # Circuit breaker should respond to info request immediately
  assert {:ok, _info} = CircuitBreaker.get_info(cb, timeout: 50)
  
  # Wait for all tasks
  Enum.each(tasks, &Task.await(&1, 200))
end
```

---

#### Fix #5: Message Buffer Resource Leak
**Severity**: CRITICAL - Unbounded memory growth
**Time Estimate**: 2 hours
**File**: `lib/jido_foundation/bridge/coordination_manager.ex`

**Current Code** (missing functionality):
```elixir
# Current: Messages are buffered but never drained
defp buffer_message(agent_id, message, state) do
  buffer = Map.get(state.message_buffers, agent_id, [])
  new_buffer = [message | buffer]
  
  # PROBLEM: No size limit, no draining
  %{state | message_buffers: Map.put(state.message_buffers, agent_id, new_buffer)}
end
```

**Fixed Code** (add new functions):
```elixir
@max_buffer_size 1000  # Prevent unbounded growth

defp buffer_message(agent_id, message, state) do
  buffer = Map.get(state.message_buffers, agent_id, [])
  
  # Add size limit
  new_buffer = if length(buffer) >= @max_buffer_size do
    Logger.warning("Message buffer full for agent #{agent_id}, dropping oldest messages")
    [message | Enum.take(buffer, @max_buffer_size - 1)]
  else
    [message | buffer]
  end
  
  %{state | message_buffers: Map.put(state.message_buffers, agent_id, new_buffer)}
end

# Add this handler for when circuit closes
def handle_info({:circuit_closed, agent_id}, state) do
  # Drain buffered messages
  state = drain_message_buffer(agent_id, state)
  {:noreply, state}
end

defp drain_message_buffer(agent_id, state) do
  case Map.get(state.message_buffers, agent_id, []) do
    [] -> 
      state
      
    buffered_messages ->
      # Send messages in original order
      Enum.reverse(buffered_messages)
      |> Enum.each(fn %{sender: sender, message: message} ->
        # Attempt delivery
        attempt_message_delivery(sender, agent_id, message, state)
      end)
      
      # Clear the buffer
      %{state | message_buffers: Map.delete(state.message_buffers, agent_id)}
  end
end

# Hook into circuit state changes
defp monitor_circuit_state(agent_id, state) do
  # Set up monitoring for circuit state changes
  CircuitBreaker.subscribe(agent_id, self())
  state
end
```

**Memory Test** to add:
```elixir
test "message buffer has bounded size" do
  {:ok, manager} = CoordinationManager.start_link([])
  
  # Simulate circuit open
  GenServer.cast(manager, {:circuit_opened, "test_agent"})
  
  # Send more messages than buffer limit
  for i <- 1..2000 do
    GenServer.cast(manager, {:buffer_message, "test_agent", %{id: i}})
  end
  
  # Get state to check buffer size
  state = :sys.get_state(manager)
  buffer = Map.get(state.message_buffers, "test_agent", [])
  
  assert length(buffer) <= 1000
end
```

---

### 🟡 MEDIUM PRIORITY - Day 4 Fixes

#### Fix #6: Misleading AtomicTransaction Module
**Severity**: MEDIUM - API confusion risk
**Time Estimate**: 1 hour
**Files**:
- `lib/foundation/atomic_transaction.ex`
- `lib/mabeam/agent_registry.ex`
- Any other files using AtomicTransaction

**Step 1**: Rename the module
```bash
# Rename file
mv lib/foundation/atomic_transaction.ex lib/foundation/serial_operations.ex
```

**Step 2**: Update module definition in `lib/foundation/serial_operations.ex`:
```elixir
defmodule Foundation.SerialOperations do
  @moduledoc """
  Provides serial execution of operations through a GenServer.
  
  IMPORTANT: This module does NOT provide atomicity or rollback capabilities.
  It only ensures operations are executed one at a time (serially) to prevent
  race conditions.
  
  For true atomic operations with rollback, consider using:
  - Database transactions
  - Ecto.Multi for database operations
  - Saga pattern for distributed transactions
  """
  
  # Update all internal references from AtomicTransaction to SerialOperations
end
```

**Step 3**: Update all usages:
```elixir
# In lib/mabeam/agent_registry.ex
# Change:
Foundation.AtomicTransaction.execute(...)
# To:
Foundation.SerialOperations.execute(...)
```

**Step 4**: Add deprecation warning (temporary):
```elixir
# Create lib/foundation/atomic_transaction.ex with deprecation
defmodule Foundation.AtomicTransaction do
  @deprecated "Use Foundation.SerialOperations instead"
  
  defdelegate execute(operations, tx_id), to: Foundation.SerialOperations
  defdelegate execute_with_retry(operations, tx_id, opts), to: Foundation.SerialOperations
end
```

---

#### Fix #7: Replace Raw send/2 with GenServer calls
**Severity**: MEDIUM - Message delivery not guaranteed
**Time Estimate**: 2 hours
**File**: `lib/jido_foundation/bridge/coordination_manager.ex`

**Current Code**:
```elixir
defp deliver_message(receiver_pid, message) do
  send(receiver_pid, message)  # Fire and forget!
  :ok
end
```

**Fixed Code**:
```elixir
defp deliver_message(receiver_pid, message) do
  try do
    # Use GenServer call for guaranteed delivery
    GenServer.call(receiver_pid, {:coordination_message, message}, 5000)
  catch
    :exit, {:timeout, _} ->
      {:error, :delivery_timeout}
    :exit, {:noproc, _} ->
      {:error, :receiver_not_found}
    :exit, reason ->
      {:error, {:delivery_failed, reason}}
  end
end

# Agents need to handle this new message
def handle_call({:coordination_message, message}, _from, state) do
  # Process coordination message
  new_state = process_coordination_message(message, state)
  {:reply, :ok, new_state}
end
```

---

#### Fix #8: Cache Race Condition
**Severity**: MEDIUM - Incorrect telemetry, potential crashes
**Time Estimate**: 1 hour
**File**: `lib/foundation/infrastructure/cache.ex`

**Current Code** (line ~89):
```elixir
def get(cache_name, key, opts \\ []) do
  table = get_table_name(cache_name)
  current_time = System.monotonic_time(:millisecond)
  
  # PROBLEM: Two separate ETS operations = race condition
  case :ets.select(table, [{{:"$1", :"$2", :"$3"}, 
                           [{:andalso, {:==, :"$1", key}, 
                                      {:>, :"$3", current_time}}], 
                           [:"$2"]}]) do
    [] ->
      # Another operation might insert here!
      case :ets.lookup(table, key) do
        [] -> 
          record_miss(cache_name, :not_found)
          {:error, :not_found}
        [{^key, _value, exp}] when exp <= current_time ->
          record_miss(cache_name, :expired)
          {:error, :expired}
      end
    [value] ->
      record_hit(cache_name)
      {:ok, value}
  end
end
```

**Fixed Code**:
```elixir
def get(cache_name, key, opts \\ []) do
  table = get_table_name(cache_name)
  current_time = System.monotonic_time(:millisecond)
  
  # Single atomic operation
  case :ets.lookup(table, key) do
    [] -> 
      record_miss(cache_name, :not_found)
      {:error, :not_found}
      
    [{^key, value, expiry}] ->
      if expiry > current_time do
        record_hit(cache_name)
        {:ok, value}
      else
        record_miss(cache_name, :expired)
        # Optionally clean up expired entry
        :ets.delete(table, key)
        {:error, :expired}
      end
  end
end
```

---

## Testing Strategy

### Phase 1 Test Execution Plan

1. **Baseline Test Run**:
   ```bash
   mix test > test_baseline.log 2>&1
   grep -E "(tests|failures)" test_baseline.log
   ```

2. **After Each Fix**:
   ```bash
   # Run specific test file
   mix test test/path/to/specific_test.exs
   
   # Run full suite
   mix test
   
   # Check for new failures
   mix test | grep -A5 "failure"
   ```

3. **Memory Leak Tests** (after fixes #1, #5):
   ```elixir
   # Add to test/foundation/memory_test.exs
   @tag :memory
   test "no memory leaks under load" do
     initial_memory = :erlang.memory(:total)
     
     # Run operations that previously leaked
     for _ <- 1..10_000 do
       # Trigger monitor leak scenario
       # Trigger message buffer scenario
     end
     
     :erlang.garbage_collect()
     final_memory = :erlang.memory(:total)
     
     # Allow some growth but not excessive
     assert final_memory < initial_memory * 1.1
   end
   ```

4. **Supervision Tests** (after fix #2):
   ```bash
   # These tests might fail after stricttr supervision
   mix test test/jido_system/application_test.exs
   mix test test/foundation/application_test.exs
   ```

## Rollback Plan

Each fix can be reverted independently:

1. **Git Commit Strategy**:
   ```bash
   # Commit each fix separately
   git add -p  # Stage specific changes
   git commit -m "Fix #1: Add Process.demonitor for unknown refs"
   ```

2. **Feature Flags** (for risky changes):
   ```elixir
   # In config/config.exs
   config :foundation,
     use_strict_supervision: true,
     use_supervised_tasks_only: true
   ```

3. **Gradual Rollout**:
   - Deploy to staging first
   - Monitor error rates and memory usage
   - Roll back specific fixes if issues arise

## Success Criteria

Phase 1 is complete when:

1. **All fixes implemented** and committed separately
2. **Test suite passes** with same or fewer failures than baseline
3. **Memory leak tests pass** - no unbounded growth
4. **Performance tests pass** - no blocking operations
5. **No new warnings** from compiler or dialyzer
6. **Documentation updated** for renamed modules

## Next Steps

After Phase 1 completion:
1. Run 4-hour load test to verify stability
2. Document any new patterns established
3. Proceed to Phase 2: State Persistence Foundation

## Troubleshooting Guide

### Common Issues

1. **"TaskSupervisor not running" errors**:
   - Ensure Foundation.Application is started in test_helper.exs
   - Check supervision tree with `:observer.start()`

2. **Tests failing after supervision fix**:
   - Look for tests that expect multiple restarts
   - Move those to use TestSupervisor
   - Add `async: false` to tests that manipulate supervisors

3. **Circuit breaker timeout errors**:
   - Increase timeout in tests
   - Ensure TaskSupervisor has enough capacity
   - Check for deadlocks in function execution

4. **Memory test failures**:
   - Run `:erlang.garbage_collect()` before measuring
   - Account for ETS table overhead
   - Use `:recon` library for detailed memory analysis

## Appendix: Code Search Commands

Useful commands for finding affected code:

```bash
# Find all Task.async_stream usage
grep -r "Task\.async_stream" lib/ test/

# Find all send/2 usage
grep -r "send(" lib/ --include="*.ex" | grep -v "send_"

# Find AtomicTransaction usage
grep -r "AtomicTransaction" lib/ test/

# Find process monitoring
grep -r "Process\.monitor" lib/

# Find ETS operations
grep -r ":ets\." lib/ | grep -E "(select|lookup)"
```

---

This completes the Phase 1 OTP Fixes Implementation Guide. Each fix is documented with specific code changes, tests, and rollback procedures. Follow this guide systematically to eliminate all critical OTP violations before proceeding to Phase 2.