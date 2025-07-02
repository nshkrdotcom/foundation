# OTP Implementation Plan - Stage 2: Test Suite Remediation
Generated: July 2, 2025
Duration: Weeks 2-3 (10 days)
Status: Ready for Implementation

## Overview

This document details Stage 2 of the OTP remediation plan, focusing on eliminating test anti-patterns that create flaky, slow, and unreliable tests. This stage transforms the test suite to use deterministic, OTP-compliant patterns.

## Context Documents
- **Parent Plan**: `AUDIT_02_plan.md` - Full remediation strategy
- **Stage 1**: `AUDIT_02_planSteps_01.md` - Enforcement infrastructure (must be completed first)
- **Original Audit**: `JULY_1_2025_PRE_PHASE_2_OTP_report_01_AUDIT_01.md` - Initial findings
- **Test Guide**: `test/TESTING_GUIDE_OTP.md` - Acknowledgment of test issues
- **Test Helpers**: `test/support/async_test_helpers.ex` - Existing deterministic helpers

## Current State

### Process.sleep Usage (26 occurrences in 6 files)
- `test/foundation/race_condition_test.exs` - 9 occurrences
- `test/foundation/monitor_leak_test.exs` - 7 occurrences  
- `test/foundation/telemetry/load_test_test.exs` - 5 occurrences
- `test/foundation/telemetry/sampler_test.exs` - 3 occurrences
- `test/mabeam/agent_registry_test.exs` - 1 occurrence
- `test/telemetry_performance_comparison.exs` - 1 occurrence

### Other Anti-patterns
- **Raw spawning**: 13+ files using `spawn/1` without supervision
- **GenServer.call without timeouts**: 17+ files
- **Direct state access**: `:sys.get_state/1` usage
- **Missing isolation**: Tests using global processes
- **Resource leaks**: ETS tables and processes not cleaned up

## Stage 2 Deliverables

### 2.1 Process.sleep Elimination
**Priority: CRITICAL**  
**Time Estimate: 5 days**

#### Step 1: Create Migration Guide
**Location**: `test/SLEEP_MIGRATION_GUIDE.md`

```markdown
# Process.sleep Migration Guide

## Why This Matters
Process.sleep creates flaky tests that:
- Fail randomly under load
- Waste time on fast systems  
- Hide real race conditions
- Make CI unreliable

## Migration Patterns

### Pattern 1: Waiting for Process Restart
**Symptom**: Sleep after killing a process to wait for supervisor restart

#### Before:
```elixir
Process.exit(manager_pid, :kill)
Process.sleep(200)  # Hope it restarted
new_pid = Process.whereis(MyServer)
```

#### After:
```elixir
import Foundation.AsyncTestHelpers

old_pid = manager_pid
Process.exit(old_pid, :kill)

# Wait for supervisor to start new process
new_pid = wait_for(fn ->
  case Process.whereis(MyServer) do
    pid when is_pid(pid) and pid != old_pid -> pid
    _ -> nil
  end
end, 5000)  # 5 second timeout

assert new_pid != old_pid
```

### Pattern 2: Waiting for State Change
**Symptom**: Sleep after triggering action, then check state

#### Before:
```elixir
CircuitBreaker.record_failure(service)
Process.sleep(50)  # Wait for state update
{:ok, :open} = CircuitBreaker.get_status(service)
```

#### After:
```elixir
import Foundation.AsyncTestHelpers

CircuitBreaker.record_failure(service)

# Wait for specific state
wait_for(fn ->
  case CircuitBreaker.get_status(service) do
    {:ok, :open} -> true
    _ -> false
  end
end, 1000)

{:ok, :open} = CircuitBreaker.get_status(service)
```

### Pattern 3: Rate Limit Window Expiry
**Symptom**: Sleep to wait for time window to pass

#### Before:
```elixir
# Use up rate limit
for _ <- 1..5, do: RateLimiter.check(key)
Process.sleep(60)  # Wait for window
assert :ok = RateLimiter.check(key)
```

#### After:
```elixir
import Foundation.AsyncTestHelpers

# Use up rate limit
for _ <- 1..5, do: RateLimiter.check(key)

# Wait for window to actually expire
wait_for(fn ->
  case RateLimiter.check(key) do
    :ok -> true
    {:error, :rate_limited} -> false
  end
end, 100)  # Should be quick

assert :ok = RateLimiter.check(key)
```

### Pattern 4: Telemetry Events
**Symptom**: Sleep hoping telemetry event was emitted

#### Before:
```elixir
MyModule.do_work()
Process.sleep(50)
# Manually check telemetry was called
```

#### After:
```elixir
import Foundation.AsyncTestHelpers

assert_telemetry_event [:my_module, :work_done], %{result: :ok} do
  MyModule.do_work()
end
```

### Pattern 5: Message Processing
**Symptom**: Sleep to allow GenServer to process messages

#### Before:
```elixir
GenServer.cast(server, :do_something)
Process.sleep(50)  # Let it process
assert GenServer.call(server, :get_state) == :expected
```

#### After:
```elixir
# Option 1: Use call instead of cast
result = GenServer.call(server, :do_something_sync)
assert result == :expected

# Option 2: Add sync function
GenServer.cast(server, :do_something)
:ok = GenServer.call(server, :sync)  # Waits for cast to process
assert GenServer.call(server, :get_state) == :expected

# Option 3: Use wait_for
GenServer.cast(server, :do_something)
wait_for(fn ->
  GenServer.call(server, :get_state) == :expected
end)
```

### Pattern 6: Clearing State
**Symptom**: Sleep to "clear" state between tests

#### Before:
```elixir
Process.sleep(10)  # Clear any existing state
```

#### After:
```elixir
# Option 1: Explicit cleanup
:ok = RateLimiter.reset_all()

# Option 2: Wait for specific clean state
wait_for(fn ->
  RateLimiter.get_metrics() == %{requests: 0}
end, 100)

# Option 3: Use isolated test setup
use Foundation.UnifiedTestFoundation, :full_isolation
```

## Special Cases

### Load Testing
Load tests may need controlled timing. Use Process.yield() instead:

```elixir
# Before
Process.sleep(1)  # Simulate fast operation

# After  
Process.yield()  # Let scheduler run other processes
```

### Benchmarking
For benchmarks that need consistent timing:

```elixir
# Use :timer.tc/1 for measurements instead of sleep
{time, result} = :timer.tc(fn -> do_work() end)
assert time < 1000  # microseconds
```

## Verification
After migrating a test file:
1. Run it 100 times: `for i in {1..100}; do mix test path/to/test.exs || break; done`
2. Run under load: `mix test --max-cases 32 path/to/test.exs`
3. Check it's faster: Compare before/after run times
```

#### Step 2: Systematic File Migration

For each file, follow this process:

##### File 1: `test/foundation/race_condition_test.exs` (9 sleeps)
**Time: 4 hours**

```elixir
# Add at top of test module
import Foundation.AsyncTestHelpers

# Migration for each sleep pattern:

# BEFORE: Clear state sleep
test "handles concurrent requests correctly" do
  Process.sleep(10)  # Clear any existing state
  
# AFTER: Deterministic state verification  
test "handles concurrent requests correctly" do
  # Wait for clean state
  wait_for(fn ->
    RateLimiter.get_window_count(:test_concurrent, "user1") == 0
  end, 100)

# BEFORE: Window expiry sleep
Process.sleep(60)  # Wait for window to expire

# AFTER: Check actual expiry
wait_for(fn ->
  RateLimiter.window_expired?(:test_window, "user1")
end, 100)

# BEFORE: Burst completion sleep
# Fire requests
Process.sleep(10)  # Let them complete

# AFTER: Wait for actual completion
# Fire requests in tasks
tasks = for i <- 1..20 do
  Task.async(fn -> 
    RateLimiter.check_rate_limit(:burst_test, "user_#{i}")
  end)
end

# Wait for all to complete
results = Task.await_many(tasks)
```

##### File 2: `test/foundation/monitor_leak_test.exs` (7 sleeps)
**Time: 3 hours**

```elixir
# BEFORE: Wait for subscription
send(router, {:subscribe, "test.*", self()})
Process.sleep(50)  # Wait for subscription

# AFTER: Synchronous subscription
:ok = SignalRouter.subscribe_sync(router, "test.*", self())

# BEFORE: Wait for cleanup  
Process.exit(pid, :normal)
Process.sleep(200)  # Wait for cleanup

# AFTER: Verify cleanup completed
ref = Process.monitor(pid)
Process.exit(pid, :normal)
assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000

# Verify cleanup actually happened
wait_for(fn ->
  SignalRouter.get_subscriber_count(router, "test.*") == 99
end)

# BEFORE: Batch operation completion
Enum.each(pids, &Process.exit(&1, :kill))
Process.sleep(300)  # Wait for all cleanup

# AFTER: Monitor all and wait
refs = Enum.map(pids, &Process.monitor/1)
Enum.each(pids, &Process.exit(&1, :kill))

for ref <- refs do
  assert_receive {:DOWN, ^ref, :process, _, :killed}, 1000
end

wait_for(fn ->
  SignalRouter.get_subscriber_count(router, "test.*") == 0
end)
```

##### File 3: `test/foundation/telemetry/load_test_test.exs` (5 sleeps)
**Time: 2 hours**

```elixir
# These sleeps simulate operation timing - different approach needed

# BEFORE: Simulate fast operation
run: fn _ctx ->
  Process.sleep(1)
  {:ok, :fast_result}
end

# AFTER: Use realistic operations or Process.yield
run: fn _ctx ->
  # Option 1: Do actual work
  _ = Enum.sum(1..100)
  {:ok, :fast_result}
  
  # Option 2: Just yield
  Process.yield()
  {:ok, :fast_result}
end

# BEFORE: Simulate slow operation  
Process.sleep(5)

# AFTER: Do actual work that takes time
run: fn _ctx ->
  # Simulate CPU work
  _ = Enum.reduce(1..10000, 0, fn i, acc ->
    :math.sqrt(i) + acc
  end)
  {:ok, :slow_result}
end
```

##### File 4: `test/foundation/telemetry/sampler_test.exs` (3 sleeps)
**Time: 2 hours**

```elixir
# BEFORE: Wait for window
Process.sleep(1100)  # Wait for next window

# AFTER: Use time manipulation or wait for window change
import Foundation.AsyncTestHelpers

# Get current window
window1 = Sampler.current_window(:test_adaptive)

# Wait for window to change
wait_for(fn ->
  Sampler.current_window(:test_adaptive) != window1
end, 1500)

# BEFORE: Simulate event rate
for _ <- 1..1000 do
  Sampler.should_sample?([:test, :adaptive])
  Process.sleep(1)  # ~1000 events/sec
end

# AFTER: Use Task.async for concurrency
tasks = for _ <- 1..1000 do
  Task.async(fn ->
    Sampler.should_sample?([:test, :adaptive])
  end)
end

Task.await_many(tasks, 5000)
```

##### File 5: `test/mabeam/agent_registry_test.exs` (1 sleep)
**Time: 1 hour**

```elixir
# Find and fix the single Process.sleep occurrence
# Similar pattern to above examples
```

##### File 6: `test/telemetry_performance_comparison.exs` (1 sleep)
**Time: 1 hour**

```elixir
# This might be legitimate for performance comparison
# Consider if it's actually needed or can use Process.yield()
```

### 2.2 Test Isolation Implementation
**Priority: HIGH**  
**Time Estimate: 3 days**

#### Step 1: Create Isolation Audit Script
**Location**: `scripts/test_isolation_audit.exs`

```elixir
defmodule TestIsolationAuditor do
  @moduledoc """
  Identifies tests that need isolation improvements.
  Run with: mix run scripts/test_isolation_audit.exs
  """
  
  def run do
    IO.puts("=== Test Isolation Audit ===\n")
    
    test_files = Path.wildcard("test/**/*_test.exs")
    issues = analyze_files(test_files)
    
    generate_report(issues)
    generate_fix_script(issues)
  end
  
  defp analyze_files(files) do
    files
    |> Enum.map(&analyze_file/1)
    |> Enum.reject(fn {_, issues} -> issues == [] end)
    |> Map.new()
  end
  
  defp analyze_file(file) do
    content = File.read!(file)
    
    issues = []
    
    # Check for UnifiedTestFoundation usage
    if not String.contains?(content, "use Foundation.UnifiedTestFoundation") do
      issues = [{:missing_foundation, nil} | issues]
    end
    
    # Check for global process usage
    global_matches = Regex.scan(~r/Process\.whereis\(([\w\.:]+)\)/, content)
    if length(global_matches) > 0 do
      processes = Enum.map(global_matches, fn [_, process] -> process end)
      issues = [{:global_process, processes} | issues]
    end
    
    # Check for raw spawn
    spawn_matches = Regex.scan(~r/spawn\(/, content)
    if length(spawn_matches) > 0 do
      issues = [{:raw_spawn, length(spawn_matches)} | issues]
    end
    
    # Check for :sys.get_state
    if String.contains?(content, ":sys.get_state") do
      issues = [{:sys_get_state, nil} | issues]
    end
    
    # Check for ETS without cleanup
    if String.contains?(content, ":ets.new") and 
       not String.contains?(content, ":ets.delete") do
      issues = [{:ets_leak, nil} | issues]
    end
    
    {file, issues}
  end
  
  defp generate_report(issues) do
    IO.puts("Found #{map_size(issues)} files with isolation issues:\n")
    
    Enum.each(issues, fn {file, file_issues} ->
      IO.puts("#{file}:")
      Enum.each(file_issues, &print_issue/1)
      IO.puts("")
    end)
    
    IO.puts("\nSummary:")
    IO.puts("- Files needing UnifiedTestFoundation: #{count_issue(issues, :missing_foundation)}")
    IO.puts("- Files using global processes: #{count_issue(issues, :global_process)}")
    IO.puts("- Files with raw spawn: #{count_issue(issues, :raw_spawn)}")
    IO.puts("- Files using :sys.get_state: #{count_issue(issues, :sys_get_state)}")
    IO.puts("- Files with potential ETS leaks: #{count_issue(issues, :ets_leak)}")
  end
  
  defp print_issue({:missing_foundation, _}) do
    IO.puts("  ❌ Not using Foundation.UnifiedTestFoundation")
  end
  
  defp print_issue({:global_process, processes}) do
    IO.puts("  ❌ Using global processes: #{Enum.join(processes, ", ")}")
  end
  
  defp print_issue({:raw_spawn, count}) do
    IO.puts("  ❌ Raw spawn usage: #{count} occurrences")
  end
  
  defp print_issue({:sys_get_state, _}) do
    IO.puts("  ❌ Using :sys.get_state (breaks encapsulation)")
  end
  
  defp print_issue({:ets_leak, _}) do
    IO.puts("  ❌ ETS table creation without cleanup")
  end
  
  defp count_issue(issues, type) do
    issues
    |> Enum.count(fn {_, file_issues} ->
      Enum.any?(file_issues, fn {issue_type, _} -> issue_type == type end)
    end)
  end
  
  defp generate_fix_script(issues) do
    File.write!("test_isolation_fixes.exs", """
    # Auto-generated test isolation fixes
    # Review each change before applying
    
    defmodule TestIsolationFixer do
      def fix_all do
        #{Enum.map_join(issues, "\n    ", &generate_fix_call/1)}
      end
      
      #{Enum.map_join(issues, "\n  ", &generate_fix_function/1)}
    end
    
    TestIsolationFixer.fix_all()
    """)
    
    IO.puts("\nGenerated test_isolation_fixes.exs - Review before running!")
  end
  
  defp generate_fix_call({file, _issues}) do
    ~s|fix_file("#{file}")|
  end
  
  defp generate_fix_function({file, issues}) do
    """
    def fix_file("#{file}") do
      content = File.read!("#{file}")
      
      #{Enum.map_join(issues, "\n    ", &generate_fix_for_issue/1)}
      
      File.write!("#{file}", content)
      IO.puts("Fixed: #{file}")
    end
    """
  end
  
  defp generate_fix_for_issue({:missing_foundation, _}) do
    """
    # Add UnifiedTestFoundation
    content = Regex.replace(
      ~r/use ExUnit\.Case(, async: true)?/,
      content,
      "use Foundation.UnifiedTestFoundation, :registry"
    )
    """
  end
  
  defp generate_fix_for_issue(_), do: "# Manual fix needed"
end

# Run the audit
TestIsolationAuditor.run()
```

#### Step 2: Migration Patterns for Test Isolation

##### Pattern 1: Adding UnifiedTestFoundation
**Files affected**: All test files not using it

```elixir
# BEFORE:
defmodule MyTest do
  use ExUnit.Case, async: true
  
  setup do
    # Manual setup
    {:ok, pid} = GenServer.start_link(MyServer, [])
    {:ok, server: pid}
  end

# AFTER:
defmodule MyTest do
  use Foundation.UnifiedTestFoundation, :registry
  
  setup %{registry: registry} do
    # Use isolated registry
    {:ok, pid} = Registry.register(registry, MyServer, [])
    {:ok, server: pid}
  end
```

##### Pattern 2: Replacing Global Process Access
**Files affected**: Tests using Process.whereis

```elixir
# BEFORE:
test "interacts with global process" do
  pid = Process.whereis(Foundation.SomeServer)
  GenServer.call(pid, :action)
end

# AFTER:
test "interacts with isolated process", %{test_supervisor: supervisor} do
  # Start isolated instance
  {:ok, pid} = TestSupervisor.start_child(
    supervisor,
    {Foundation.SomeServer, name: unique_name()}
  )
  
  GenServer.call(pid, :action)
end

# Helper function
defp unique_name do
  :"#{__MODULE__}_#{System.unique_integer()}"
end
```

##### Pattern 3: Supervised Test Processes
**Files affected**: Tests using raw spawn

Create helper module `test/support/supervised_test_process.ex`:

```elixir
defmodule Foundation.SupervisedTestProcess do
  @moduledoc """
  Replaces raw spawn with supervised processes in tests.
  """
  
  use GenServer
  
  def spawn_supervised(fun, opts \\ []) do
    supervisor = Keyword.get(opts, :supervisor, Foundation.TestSupervisor)
    
    child_spec = %{
      id: make_ref(),
      start: {__MODULE__, :start_link, [[fun: fun]]},
      restart: :temporary
    }
    
    case DynamicSupervisor.start_child(supervisor, child_spec) do
      {:ok, pid} -> {:ok, pid}
      error -> error
    end
  end
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end
  
  @impl true
  def init(opts) do
    fun = Keyword.fetch!(opts, :fun)
    
    # Run in separate process to isolate crashes
    {:ok, task} = Task.start_link(fun)
    
    {:ok, %{task: task}}
  end
  
  @impl true
  def handle_info({:EXIT, task, reason}, %{task: task} = state) do
    # Task completed
    {:stop, reason, state}
  end
end
```

Usage in tests:

```elixir
# BEFORE:
test "spawns process" do
  pid = spawn(fn ->
    receive do
      :stop -> :ok
    end
  end)
  
  send(pid, :stop)
end

# AFTER:
test "spawns supervised process", %{test_supervisor: supervisor} do
  {:ok, pid} = SupervisedTestProcess.spawn_supervised(
    fn ->
      receive do
        :stop -> :ok
      end
    end,
    supervisor: supervisor
  )
  
  send(pid, :stop)
  
  # Process is automatically cleaned up
end
```

##### Pattern 4: Replacing :sys.get_state
**Files affected**: monitor_leak_test.exs and others

```elixir
# BEFORE:
test "checks internal state" do
  state = :sys.get_state(server)
  assert map_size(state.connections) == 5
end

# AFTER:
# Option 1: Add test-specific API
defmodule MyServer do
  # In the actual server module
  def get_connection_count(server) do
    GenServer.call(server, :get_connection_count)
  end
  
  def handle_call(:get_connection_count, _from, state) do
    {:reply, map_size(state.connections), state}
  end
end

test "checks connection count" do
  assert MyServer.get_connection_count(server) == 5
end

# Option 2: Use debug mode in tests
test "checks state", %{server: server} do
  # Enable debug mode for this test only
  :sys.replace_state(server, fn state ->
    put_in(state.test_mode, true)
  end)
  
  {:ok, test_state} = GenServer.call(server, :get_test_state)
  assert map_size(test_state.connections) == 5
end
```

### 2.3 Deterministic Test Patterns
**Priority: HIGH**  
**Time Estimate: 2 days**

#### Create Comprehensive Test Pattern Library
**Location**: `test/support/deterministic_patterns.ex`

```elixir
defmodule Foundation.DeterministicPatterns do
  @moduledoc """
  Common patterns for deterministic testing without timing dependencies.
  Import this module in tests that need deterministic coordination.
  """
  
  import ExUnit.Assertions
  import Foundation.AsyncTestHelpers
  
  @doc """
  Waits for a GenServer to process all pending messages.
  Adds a :sync handler to your GenServer for testing.
  """
  def sync_genserver(server, timeout \\ 5000) do
    ref = make_ref()
    GenServer.call(server, {:sync, ref}, timeout)
  end
  
  @doc """
  Starts multiple processes and waits for all to be ready.
  Each process should send {:ready, self()} when initialized.
  """
  def start_and_sync_processes(specs, timeout \\ 5000) do
    parent = self()
    
    pids = Enum.map(specs, fn spec ->
      {:ok, pid} = start_process(spec, parent)
      pid
    end)
    
    # Wait for all ready signals
    Enum.each(pids, fn pid ->
      assert_receive {:ready, ^pid}, timeout
    end)
    
    pids
  end
  
  @doc """
  Coordinates multiple concurrent operations with deterministic ordering.
  """
  def coordinate_concurrent(operations, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)
    ordered = Keyword.get(opts, :ordered, false)
    
    if ordered do
      # Sequential execution
      Enum.map(operations, fn op -> op.() end)
    else
      # Parallel with synchronization
      tasks = Enum.map(operations, fn op ->
        Task.async(op)
      end)
      
      Task.await_many(tasks, timeout)
    end
  end
  
  @doc """
  Tests rate limiting deterministically without time dependencies.
  """
  def test_rate_limit_window(rate_limiter, key, limit, window_ms) do
    # Clear any existing state
    :ok = RateLimiter.reset(rate_limiter, key)
    
    # Test 1: Exactly at limit
    results = for _ <- 1..limit do
      RateLimiter.check_rate_limit(rate_limiter, key)
    end
    assert Enum.all?(results, &(&1 == :ok))
    
    # Test 2: Over limit
    assert {:error, :rate_limited} = 
      RateLimiter.check_rate_limit(rate_limiter, key)
    
    # Test 3: Wait for window expiry using wait_for
    wait_for(
      fn ->
        case RateLimiter.check_rate_limit(rate_limiter, key) do
          :ok -> true
          _ -> false
        end
      end,
      window_ms + 100  # Small buffer
    )
  end
  
  @doc """
  Verifies message routing without timing assumptions.
  """
  def assert_routed_message(router, pattern, message, timeout \\ 1000) do
    # Subscribe first
    :ok = Router.subscribe(router, pattern, self())
    
    # Send message
    :ok = Router.route(router, message)
    
    # Assert receipt
    assert_receive ^message, timeout
  end
  
  @doc """
  Tests process monitoring and cleanup deterministically.
  """
  def test_monitor_cleanup(monitoring_process, monitored_pids) do
    # Monitor all processes
    refs = Enum.map(monitored_pids, fn pid ->
      GenServer.call(monitoring_process, {:monitor, pid})
    end)
    
    # Kill all monitored processes
    Enum.each(monitored_pids, fn pid ->
      Process.exit(pid, :kill)
    end)
    
    # Wait for all DOWN messages to be processed
    wait_for(fn ->
      GenServer.call(monitoring_process, :get_monitor_count) == 0
    end)
    
    # Verify cleanup
    assert GenServer.call(monitoring_process, :get_monitor_count) == 0
  end
  
  @doc """
  Barrier synchronization for multiple processes.
  All processes must reach the barrier before any can continue.
  """
  def barrier_sync(processes, barrier_name \\ :test_barrier) do
    parent = self()
    count = length(processes)
    
    # Send barrier instruction to all
    Enum.each(processes, fn pid ->
      send(pid, {:barrier, barrier_name, parent, count})
    end)
    
    # Collect ready signals
    ready_pids = for _ <- 1..count do
      assert_receive {:barrier_ready, ^barrier_name, pid}, 5000
      pid
    end
    
    # Release all processes
    Enum.each(ready_pids, fn pid ->
      send(pid, {:barrier_release, barrier_name})
    end)
    
    :ok
  end
  
  @doc """
  Test helper for verifying telemetry events with specific data.
  """
  def capture_telemetry_events(event_names, fun) do
    test_pid = self()
    ref = make_ref()
    
    handler_ids = Enum.map(event_names, fn event_name ->
      handler_id = {__MODULE__, ref, event_name}
      
      :telemetry.attach(
        handler_id,
        event_name,
        fn name, measurements, metadata, _ ->
          send(test_pid, {:telemetry_event, ref, name, measurements, metadata})
        end,
        nil
      )
      
      handler_id
    end)
    
    try do
      fun.()
      
      # Collect all events
      collect_telemetry_events(ref, length(event_names))
    after
      # Clean up handlers
      Enum.each(handler_ids, &:telemetry.detach/1)
    end
  end
  
  defp collect_telemetry_events(ref, count, timeout \\ 1000) do
    for _ <- 1..count do
      receive do
        {:telemetry_event, ^ref, name, measurements, metadata} ->
          {name, measurements, metadata}
      after
        timeout -> nil
      end
    end
    |> Enum.reject(&is_nil/1)
  end
  
  @doc """
  Helper for testing ETS-based operations deterministically.
  """
  def with_test_ets(fun, opts \\ []) do
    table_name = Keyword.get(opts, :name, :test_ets)
    table_opts = Keyword.get(opts, :table_opts, [:set, :public])
    
    table = :ets.new(table_name, table_opts)
    
    try do
      fun.(table)
    after
      :ets.delete(table)
    end
  end
  
  @doc """
  Deterministic testing of supervisor restart behavior.
  """
  def test_supervisor_restart(supervisor, child_spec, crash_fun) do
    # Start child
    {:ok, pid1} = DynamicSupervisor.start_child(supervisor, child_spec)
    
    # Monitor it
    ref = Process.monitor(pid1)
    
    # Cause crash
    crash_fun.(pid1)
    
    # Wait for death
    assert_receive {:DOWN, ^ref, :process, ^pid1, _reason}, 5000
    
    # Wait for restart
    wait_for(fn ->
      case DynamicSupervisor.which_children(supervisor) do
        [{_, pid, _, _}] when is_pid(pid) and pid != pid1 -> pid
        _ -> nil
      end
    end)
  end
  
  # Private helpers
  
  defp start_process({module, args}, parent) do
    # Start process with parent notification
    {:ok, _pid} = module.start_link(args ++ [notify: parent])
  end
end
```

#### Usage Examples for Teams

Create `test/examples/deterministic_test_example.exs`:

```elixir
defmodule DeterministicTestExample do
  use Foundation.UnifiedTestFoundation, :full_isolation
  import Foundation.DeterministicPatterns
  
  describe "rate limiter without Process.sleep" do
    test "handles burst traffic deterministically", %{test_context: ctx} do
      {:ok, limiter} = start_rate_limiter(ctx)
      
      # Test rate limit deterministically
      test_rate_limit_window(limiter, "user1", 10, 100)
    end
  end
  
  describe "concurrent operations" do
    test "coordinates multiple agents", %{test_context: ctx} do
      # Start multiple agents
      agents = start_and_sync_processes([
        {Agent1, [context: ctx]},
        {Agent2, [context: ctx]},
        {Agent3, [context: ctx]}
      ])
      
      # Coordinate operations
      results = coordinate_concurrent([
        fn -> Agent1.process(hd(agents)) end,
        fn -> Agent2.process(hd(tl(agents))) end,
        fn -> Agent3.process(hd(tl(tl(agents)))) end
      ])
      
      assert length(results) == 3
    end
  end
  
  describe "telemetry events" do
    test "captures all events in order" do
      events = capture_telemetry_events(
        [[:my_app, :start], [:my_app, :process], [:my_app, :complete]],
        fn ->
          MyApp.do_complex_operation()
        end
      )
      
      assert length(events) == 3
      assert {[:my_app, :start], _, _} = hd(events)
    end
  end
end
```

### 2.4 Create Test Migration Script
**Priority: MEDIUM**  
**Time Estimate: 1 day**

**Location**: `scripts/migrate_tests.exs`

```elixir
defmodule TestMigrator do
  @moduledoc """
  Automated test migration tool.
  Handles common patterns, flags complex cases for manual review.
  """
  
  def run do
    files = find_test_files_with_issues()
    
    Enum.each(files, fn file ->
      IO.puts("Migrating: #{file}")
      migrate_file(file)
    end)
    
    generate_report()
  end
  
  defp find_test_files_with_issues do
    Path.wildcard("test/**/*_test.exs")
    |> Enum.filter(&has_issues?/1)
  end
  
  defp has_issues?(file) do
    content = File.read!(file)
    
    String.contains?(content, "Process.sleep") or
    String.contains?(content, "spawn(") or
    String.contains?(content, ":sys.get_state") or
    not String.contains?(content, "Foundation.UnifiedTestFoundation")
  end
  
  defp migrate_file(file) do
    content = File.read!(file)
    original = content
    
    # Apply migrations
    content = content
    |> add_imports()
    |> migrate_sleeps()
    |> migrate_spawns()
    |> migrate_sys_get_state()
    |> add_unified_foundation()
    
    if content != original do
      # Backup original
      File.write!("#{file}.backup", original)
      
      # Write migrated version
      File.write!(file, content)
      
      # Try to format
      System.cmd("mix", ["format", file])
      
      log_migration(file, original, content)
    end
  end
  
  defp add_imports(content) do
    if String.contains?(content, "Process.sleep") and 
       not String.contains?(content, "import Foundation.AsyncTestHelpers") do
      # Add import after module declaration
      Regex.replace(
        ~r/(defmodule \w+ do\n)/,
        content,
        "\\1  import Foundation.AsyncTestHelpers\n"
      )
    else
      content
    end
  end
  
  defp migrate_sleeps(content) do
    content
    |> migrate_simple_sleeps()
    |> migrate_window_sleeps()
    |> migrate_state_sleeps()
  end
  
  defp migrate_simple_sleeps(content) do
    # Process.sleep(n) followed by assertion
    Regex.replace(
      ~r/Process\.sleep\(\d+\)\s*\n\s*(assert .+)/m,
      content,
      "wait_for(fn -> \\1 end)"
    )
  end
  
  defp migrate_window_sleeps(content) do
    # Common rate limit pattern
    Regex.replace(
      ~r/Process\.sleep\((\d+)\)\s*#\s*[Ww]ait for window/,
      content,
      "wait_for(fn -> RateLimiter.window_expired?(key) end, \\1 + 100)"
    )
  end
  
  defp migrate_state_sleeps(content) do
    # Mark complex cases for manual review
    Regex.replace(
      ~r/Process\.sleep\((\d+)\)/,
      content,
      "# TODO: Review Process.sleep(\\1) migration\n    Process.sleep(\\1)"
    )
  end
  
  defp migrate_spawns(content) do
    Regex.replace(
      ~r/spawn\(fn ->/,
      content,
      "# TODO: Use SupervisedTestProcess\n    spawn(fn ->"
    )
  end
  
  defp migrate_sys_get_state(content) do
    Regex.replace(
      ~r/:sys\.get_state\(/,
      content,
      "# TODO: Replace with test API\n    :sys.get_state("
    )
  end
  
  defp add_unified_foundation(content) do
    if not String.contains?(content, "Foundation.UnifiedTestFoundation") do
      Regex.replace(
        ~r/use ExUnit\.Case(, async: \w+)?/,
        content,
        "use Foundation.UnifiedTestFoundation, :registry"
      )
    else
      content
    end
  end
  
  defp log_migration(file, original, migrated) do
    changes = diff_summary(original, migrated)
    
    File.write!(
      "test_migration_log.md",
      """
      ## #{file}
      
      Changes:
      #{changes}
      
      ---
      
      """,
      [:append]
    )
  end
  
  defp diff_summary(original, migrated) do
    sleep_before = count_pattern(original, "Process.sleep")
    sleep_after = count_pattern(migrated, "Process.sleep")
    
    """
    - Process.sleep: #{sleep_before} -> #{sleep_after}
    - Added imports: #{String.contains?(migrated, "import Foundation")}
    - Added UnifiedTestFoundation: #{String.contains?(migrated, "UnifiedTestFoundation")}
    - TODOs added: #{count_pattern(migrated, "TODO:")}
    """
  end
  
  defp count_pattern(content, pattern) do
    content
    |> String.split(pattern)
    |> length()
    |> Kernel.-(1)
  end
  
  defp generate_report do
    IO.puts("""
    
    Migration complete!
    
    Next steps:
    1. Review test_migration_log.md for all changes
    2. Search for "TODO:" comments and fix manually
    3. Run tests to ensure they still pass
    4. Check for flaky tests by running multiple times
    5. Remove .backup files after verification
    """)
  end
end

# Run migration
TestMigrator.run()
```

## Verification Process

### After Each File Migration

1. **Run single test multiple times**:
```bash
# Run 100 times to check for flakes
for i in {1..100}; do
  mix test path/to/test.exs || break
done
```

2. **Run under load**:
```bash
# Stress test with parallelism
mix test path/to/test.exs --max-cases 32 --seed 0
```

3. **Measure improvement**:
```bash
# Before (with sleeps)
time mix test path/to/test.exs

# After (deterministic)
time mix test path/to/test.exs

# Should see significant speedup
```

### Full Test Suite Verification

1. **Run Credo checks**:
```bash
mix credo --strict
# Process.sleep violations should decrease
```

2. **Run all tests**:
```bash
# Full suite
mix test

# With coverage
mix test --cover
```

3. **CI verification**:
```bash
# Push to branch and check CI passes
git add .
git commit -m "Stage 2: Remove Process.sleep from tests"
git push origin test-cleanup-stage-2
```

## Common Issues & Solutions

### Issue: wait_for/1 timeouts
**Solution**: Increase timeout or check condition is achievable
```elixir
# Increase timeout for slow operations
wait_for(fn -> condition end, 10_000)  # 10 seconds
```

### Issue: Test is genuinely time-dependent
**Solution**: Use deterministic time control
```elixir
# For rate limiters, provide time injection
defmodule RateLimiter do
  def check_rate_limit(key, opts \\ []) do
    now = Keyword.get(opts, :now, System.system_time(:millisecond))
    # ... use injected time
  end
end
```

### Issue: Complex async coordination
**Solution**: Use the DeterministicPatterns helpers
```elixir
import Foundation.DeterministicPatterns

# Use barriers, coordinate_concurrent, etc.
```

## Success Criteria

Stage 2 is complete when:
- ✅ 0 Process.sleep calls remaining (down from 26)
- ✅ All tests use UnifiedTestFoundation where appropriate
- ✅ No :sys.get_state usage
- ✅ No raw spawn in tests
- ✅ Test suite runs 30-50% faster
- ✅ No flaky tests in CI (run 10 times successfully)
- ✅ All tests pass consistently

## Next Steps

After completing Stage 2:
1. Verify all tests pass reliably
2. Check test execution time improvement
3. Update CI to enforce no Process.sleep
4. Proceed to Stage 3 for production code fixes
5. Consider adding property-based tests

---

**Completion Checklist**:
- [ ] Sleep migration guide created
- [ ] All 26 Process.sleep calls removed
- [ ] Test isolation audit complete
- [ ] UnifiedTestFoundation added where needed
- [ ] Deterministic patterns library created
- [ ] Migration scripts run
- [ ] All tests passing
- [ ] CI verification complete
- [ ] Performance improvement measured