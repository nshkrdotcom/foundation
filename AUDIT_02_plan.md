# OTP Implementation Audit Report 02 - Detailed Remediation Plan
Generated: July 2, 2025
Status: Comprehensive Plan for Test Suite and Production Code Quality

## Executive Summary

This document provides a structured, actionable plan to address the OTP violations and test anti-patterns identified in AUDIT_01. The plan is organized into three stages:

1. **Stage 1: Quality & Enforcement Infrastructure** - Prevent regression
2. **Stage 2: Test Suite Remediation** - Fix existing test anti-patterns  
3. **Stage 3: Production Code Hardening** - Eliminate OTP violations in lib/

## Current State Analysis

### Test Suite Issues (26 files affected)
- **Process.sleep abuse**: 26 occurrences across 6 files
- **Raw spawning**: 13+ files with unsupervised processes
- **GenServer.call without timeouts**: 17+ files
- **Direct state access**: :sys.get_state usage
- **Missing error assertions**: Widespread
- **Resource leaks**: ETS tables, processes not properly cleaned up

### Production Code Issues (17 files affected)
- **Raw send() usage**: 41 occurrences, ~15 critical
- **Missing supervision**: Some processes bypass OTP
- **Inconsistent patterns**: Mix of proper OTP and anti-patterns

### Existing Assets (To Be Leveraged)
- ✅ `Foundation.AsyncTestHelpers` - wait_for/3, assert_telemetry_event
- ✅ `Foundation.UnifiedTestFoundation` - Isolation framework
- ✅ `Foundation.TestIsolation` - Resource cleanup
- ✅ `JidoFoundation.CoordinationManager` - Supervised messaging

---

## Stage 1: Quality & Enforcement Infrastructure (Week 1)

### Goal: Prevent regression through automated enforcement

### 1.1 Create Credo Configuration
**Priority: CRITICAL**
**Time: 2 hours**

Create `.credo.exs`:
```elixir
%{
  configs: [
    %{
      name: "default",
      files: %{
        included: ["lib/", "test/"],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/test/support/"]
      },
      requires: ["./lib/foundation/credo_checks/"],
      strict: true,
      color: true,
      checks: [
        # Banned functions
        {Credo.Check.Warning.ForbiddenModule, 
         modules: [
           {Process, [:spawn, :spawn_link, :spawn_monitor], "Use Task.Supervisor or DynamicSupervisor"},
           {Process, [:put, :get, :get_keys], "Use GenServer state instead of process dictionary"},
           {:erlang, [:send], "Use GenServer.cast or JidoFoundation.CoordinationManager"}
         ]},
        
        # Custom checks
        {Foundation.CredoChecks.NoRawSend, []},
        {Foundation.CredoChecks.NoProcessSleep, []},
        {Foundation.CredoChecks.GenServerTimeout, []},
        
        # Standard checks with strict settings
        {Credo.Check.Refactor.Nesting, max_nesting: 2},
        {Credo.Check.Warning.UnusedEnumOperation, []},
        {Credo.Check.Warning.UnusedKeywordOperation, []},
        {Credo.Check.Warning.UnusedListOperation, []},
        {Credo.Check.Warning.UnusedStringOperation, []},
        {Credo.Check.Warning.UnusedTupleOperation, []},
        
        # Disable checks that conflict with OTP patterns
        {Credo.Check.Refactor.ModuleDependencies, false}
      ]
    }
  ]
}
```

### 1.2 Implement Custom Credo Checks
**Priority: CRITICAL**
**Time: 4 hours**

Create `lib/foundation/credo_checks/`:

#### a) `no_raw_send.ex`:
```elixir
defmodule Foundation.CredoChecks.NoRawSend do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Raw send() calls bypass OTP supervision and monitoring.
      
      Instead of:
          send(pid, message)
      
      Use one of:
          GenServer.cast(pid, message)
          JidoFoundation.CoordinationManager.send_supervised(pid, message)
          Process.send(pid, message, [:noconnect])  # If you must use send
      
      Exceptions:
      - Sending to self(): send(self(), message) is allowed
      - Test support modules
      """
    ]

  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end
  
  defp traverse({:send, meta, [target, _message]} = ast, issues, issue_meta) do
    if not sending_to_self?(target) and not in_test_support?(issue_meta) do
      issue = issue_for(issue_meta, meta[:line], "send")
      {ast, [issue | issues]}
    else
      {ast, issues}
    end
  end
  
  defp traverse(ast, issues, _issue_meta), do: {ast, issues}
  
  defp sending_to_self?({:self, _, _}), do: true
  defp sending_to_self?(_), do: false
  
  defp in_test_support?(issue_meta) do
    String.contains?(issue_meta.filename, "test/support/")
  end
end
```

#### b) `no_process_sleep.ex`:
```elixir
defmodule Foundation.CredoChecks.NoProcessSleep do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Process.sleep in tests indicates flaky, timing-dependent tests.
      
      Instead of:
          Process.sleep(100)
          assert something
      
      Use:
          import Foundation.AsyncTestHelpers
          wait_for(fn -> something end)
      
      Or for telemetry:
          assert_telemetry_event [:my, :event] do
            trigger_action()
          end
      """
    ]

  def run(source_file, params \\ []) do
    if String.contains?(source_file.filename, "/test/") do
      issue_meta = IssueMeta.for(source_file, params)
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end
  
  defp traverse({{:., _, [{:__aliases__, _, [:Process]}, :sleep]}, meta, _} = ast, 
                issues, issue_meta) do
    issue = issue_for(issue_meta, meta[:line], "Process.sleep")
    {ast, [issue | issues]}
  end
  
  defp traverse(ast, issues, _issue_meta), do: {ast, issues}
end
```

#### c) `genserver_timeout.ex`:
```elixir
defmodule Foundation.CredoChecks.GenServerTimeout do
  use Credo.Check,
    base_priority: :medium,
    category: :warning,
    explanations: [
      check: """
      GenServer.call without explicit timeout uses default 5000ms.
      
      Instead of:
          GenServer.call(server, request)
      
      Use:
          GenServer.call(server, request, :timer.seconds(10))
      
      This makes timeouts explicit and prevents unexpected failures.
      """
    ]

  def run(source_file, params \\ []) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end
  
  defp traverse({{:., _, [{:__aliases__, _, [:GenServer]}, :call]}, meta, args} = ast,
                issues, issue_meta) do
    if length(args) == 2 do  # Missing timeout parameter
      issue = issue_for(issue_meta, meta[:line], "GenServer.call without timeout")
      {ast, [issue | issues]}
    else
      {ast, issues}
    end
  end
  
  defp traverse(ast, issues, _issue_meta), do: {ast, issues}
end
```

### 1.3 CI Pipeline Integration
**Priority: HIGH**
**Time: 2 hours**

Create `.github/workflows/otp_compliance.yml`:
```yaml
name: OTP Compliance Check

on:
  pull_request:
  push:
    branches: [main, develop]

jobs:
  otp-compliance:
    runs-on: ubuntu-latest
    
    steps:
      - uses: actions/checkout@v3
      
      - name: Set up Elixir
        uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.15'
          otp-version: '26'
          
      - name: Install dependencies
        run: |
          mix deps.get
          mix deps.compile
          
      - name: Run Credo strict mode
        run: mix credo --strict
        
      - name: Check for banned patterns
        run: |
          # Check for Process.spawn
          if grep -r "Process\.spawn[^_]" lib/ --include="*.ex"; then
            echo "ERROR: Found Process.spawn usage"
            exit 1
          fi
          
          # Check for process dictionary
          if grep -r "Process\.\(get\|put\)" lib/ --include="*.ex"; then
            echo "ERROR: Found process dictionary usage"
            exit 1
          fi
          
          # Count raw sends (excluding test support)
          SEND_COUNT=$(grep -r "send(" lib/ --include="*.ex" | grep -v "test/support" | wc -l)
          echo "Raw send() usage: $SEND_COUNT occurrences"
          if [ $SEND_COUNT -gt 41 ]; then
            echo "ERROR: Raw send usage increased!"
            exit 1
          fi
          
      - name: Run OTP violation tests
        run: |
          mix test test/foundation/otp_compliance_test.exs
```

### 1.4 Create OTP Compliance Test Suite
**Priority: HIGH**
**Time: 3 hours**

Create `test/foundation/otp_compliance_test.exs`:
```elixir
defmodule Foundation.OTPComplianceTest do
  use ExUnit.Case, async: true
  
  @banned_modules [
    {Process, [:spawn, :spawn_link, :spawn_monitor], "Use supervised processes"},
    {Process, [:put, :get], "Use GenServer state"},
    {:erlang, [:send], "Use GenServer.cast or supervised send"}
  ]
  
  describe "OTP compliance verification" do
    test "no banned function calls in production code" do
      lib_files = Path.wildcard("lib/**/*.ex")
      
      violations = 
        Enum.flat_map(lib_files, fn file ->
          check_file_for_violations(file)
        end)
        
      assert violations == [], 
        "Found OTP violations:\n#{format_violations(violations)}"
    end
    
    test "all GenServers implement proper callbacks" do
      genserver_modules = find_genserver_modules()
      
      for module <- genserver_modules do
        assert function_exported?(module, :init, 1),
          "#{module} missing init/1"
        assert function_exported?(module, :handle_call, 3) or
               function_exported?(module, :handle_cast, 2) or
               function_exported?(module, :handle_info, 2),
          "#{module} implements no message handlers"
      end
    end
    
    test "all processes are under supervision" do
      # This would check Application supervision trees
      # Implementation depends on your app structure
    end
  end
  
  defp check_file_for_violations(file) do
    content = File.read!(file)
    ast = Code.string_to_quoted!(content)
    
    {_, violations} = 
      Macro.prewalk(ast, [], fn
        {func, meta, args} = node, acc ->
          case check_banned_function(func, args) do
            {:banned, reason} ->
              {node, [{file, meta[:line], reason} | acc]}
            :ok ->
              {node, acc}
          end
        node, acc ->
          {node, acc}
      end)
      
    violations
  end
  
  defp check_banned_function(func, args) do
    # Implementation checking against @banned_modules
  end
end
```

---

## Stage 2: Test Suite Remediation (Weeks 2-3)

### Goal: Eliminate all test anti-patterns systematically

### 2.1 Process.sleep Elimination Campaign
**Priority: CRITICAL**
**Time: 1 week**

#### Phase 1: Create Migration Guide
Create `test/SLEEP_MIGRATION_GUIDE.md`:

```markdown
# Process.sleep Migration Guide

## Pattern 1: Waiting for Process Start/Restart

### Before:
```elixir
Process.exit(pid, :kill)
Process.sleep(200)
new_pid = Process.whereis(MyServer)
```

### After:
```elixir
import Foundation.AsyncTestHelpers

Process.exit(pid, :kill)
new_pid = wait_for(fn ->
  case Process.whereis(MyServer) do
    pid when is_pid(pid) and pid != old_pid -> pid
    _ -> nil
  end
end)
```

## Pattern 2: Waiting for State Change

### Before:
```elixir
MyServer.trigger_action()
Process.sleep(100)
assert MyServer.get_state() == :expected
```

### After:
```elixir
import Foundation.AsyncTestHelpers

MyServer.trigger_action()
wait_for(fn ->
  MyServer.get_state() == :expected
end)
```

## Pattern 3: Waiting for Telemetry

### Before:
```elixir
MyModule.do_work()
Process.sleep(50)
# Hope telemetry fired
```

### After:
```elixir
import Foundation.AsyncTestHelpers

assert_telemetry_event [:my, :event], %{count: 1} do
  MyModule.do_work()
end
```
```

#### Phase 2: Systematic File Updates

**Files to update (in order of priority):**

1. **High-impact files** (most sleeps):
   - `test/foundation/race_condition_test.exs` (9 sleeps)
   - `test/foundation/monitor_leak_test.exs` (7 sleeps)
   - `test/foundation/telemetry/load_test_test.exs` (5 sleeps)
   - `test/foundation/telemetry/sampler_test.exs` (3 sleeps)
   - `test/mabeam/agent_registry_test.exs` (1 sleep)
   - `test/telemetry_performance_comparison.exs` (1 sleep)

**Update Strategy for each file:**
```elixir
# Step 1: Add import at top of test module
import Foundation.AsyncTestHelpers

# Step 2: Replace each Process.sleep pattern

# Pattern: Clear state + sleep
Process.sleep(10)  # Clear any existing state
# Becomes:
wait_for(fn -> 
  # Check that state is actually clear
  RateLimiter.get_state(key) == initial_state
end, 100)  # Short timeout for state clearing

# Pattern: Wait for window expiry  
Process.sleep(60)  # Wait for window to expire
# Becomes:
wait_for(fn ->
  RateLimiter.window_expired?(key)
end, 100)

# Pattern: Simulate operation timing
Process.sleep(1)  # Simulate fast operation
# Becomes:
# Either remove if not needed, or:
Process.yield()  # Allow other processes to run
```

### 2.2 Fix Test Isolation Issues
**Priority: HIGH**
**Time: 3 days**

#### Create Test Isolation Audit Script
`scripts/audit_test_isolation.exs`:
```elixir
defmodule TestIsolationAuditor do
  def run do
    test_files = Path.wildcard("test/**/*_test.exs")
    
    issues = Enum.flat_map(test_files, fn file ->
      analyze_file(file)
    end)
    
    generate_report(issues)
  end
  
  defp analyze_file(file) do
    content = File.read!(file)
    
    issues = []
    
    # Check for UnifiedTestFoundation usage
    if not String.contains?(content, "use Foundation.UnifiedTestFoundation") do
      issues = [{:missing_unified_foundation, file} | issues]
    end
    
    # Check for global process usage
    if Regex.match?(~r/Process\.whereis\([\w\.]+\)/, content) do
      issues = [{:global_process_usage, file} | issues]
    end
    
    # Check for raw spawn
    if Regex.match?(~r/spawn\(/, content) do
      issues = [{:raw_spawn, file} | issues]
    end
    
    issues
  end
end
```

#### Migration Plan for Each Pattern:

**Pattern 1: Add UnifiedTestFoundation**
```elixir
# Before:
defmodule MyTest do
  use ExUnit.Case
  
# After:
defmodule MyTest do
  use Foundation.UnifiedTestFoundation, :registry  # or :full_isolation
```

**Pattern 2: Replace Global Process Access**
```elixir
# Before:
test "something" do
  pid = Process.whereis(Foundation.SomeServer)
  
# After:
test "something", %{test_supervisor: supervisor} do
  {:ok, pid} = TestSupervisor.start_child(
    supervisor,
    {Foundation.SomeServer, name: unique_name()}
  )
```

### 2.3 Implement Deterministic Test Patterns
**Priority: HIGH**
**Time: 4 days**

#### Create Test Pattern Library
`test/support/deterministic_patterns.ex`:

```elixir
defmodule Foundation.DeterministicPatterns do
  @moduledoc """
  Common patterns for deterministic testing without Process.sleep
  """
  
  import Foundation.AsyncTestHelpers
  
  @doc """
  Wait for a GenServer to process all messages in its mailbox
  """
  def sync_genserver(server) do
    GenServer.call(server, :sync, :timer.seconds(5))
  end
  
  @doc """
  Wait for multiple processes to reach a specific state
  """
  def wait_for_all(servers, state_check_fun) do
    wait_for(fn ->
      Enum.all?(servers, fn server ->
        state_check_fun.(server)
      end)
    end)
  end
  
  @doc """
  Coordinate multiple processes with a barrier
  """
  def barrier_sync(processes) do
    parent = self()
    ref = make_ref()
    
    # Tell all processes to sync
    Enum.each(processes, fn pid ->
      send(pid, {:barrier_sync, parent, ref})
    end)
    
    # Wait for all confirmations
    Enum.each(processes, fn _pid ->
      assert_receive {:barrier_ready, ^ref}, 1000
    end)
  end
  
  @doc """
  Deterministic rate limit testing
  """
  def test_rate_limit(rate_limiter, key, limit) do
    # Clear state deterministically
    :ok = RateLimiter.reset(rate_limiter, key)
    
    # Fire exactly limit requests
    results = for _ <- 1..limit do
      RateLimiter.check_rate_limit(rate_limiter, key)
    end
    
    # All should pass
    assert Enum.all?(results, &(&1 == :ok))
    
    # Next one should fail
    assert {:error, :rate_limited} = 
      RateLimiter.check_rate_limit(rate_limiter, key)
  end
end
```

### 2.4 Fix Process Management Anti-patterns
**Priority: MEDIUM**
**Time: 3 days**

#### Create Supervised Test Process Module
`test/support/supervised_test_process.ex`:

```elixir
defmodule Foundation.SupervisedTestProcess do
  @moduledoc """
  Replace raw spawn with supervised test processes
  """
  
  use GenServer
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts)
  end
  
  def spawn_supervised(fun, opts \\ []) do
    test_supervisor = Keyword.get(opts, :supervisor, Foundation.TestSupervisor)
    
    spec = %{
      id: {__MODULE__, System.unique_integer()},
      start: {__MODULE__, :start_link, [[callback: fun]]},
      restart: :temporary
    }
    
    DynamicSupervisor.start_child(test_supervisor, spec)
  end
  
  @impl true
  def init(opts) do
    callback = Keyword.get(opts, :callback)
    
    if callback do
      # Run callback in separate process to isolate failures
      Task.start_link(callback)
    end
    
    {:ok, %{}}
  end
end
```

**Migration for spawn patterns:**
```elixir
# Before:
pid = spawn(fn -> 
  receive do
    :stop -> :ok
  end
end)

# After:
{:ok, pid} = Foundation.SupervisedTestProcess.spawn_supervised(fn ->
  receive do
    :stop -> :ok
  end
end, supervisor: test_supervisor)
```

---

## Stage 3: Production Code Hardening (Weeks 4-5)

### Goal: Eliminate all OTP violations in production code

### 3.1 Raw Send Elimination Campaign
**Priority: CRITICAL**
**Time: 1 week**

#### Phase 1: Create Supervised Send Module
`lib/foundation/supervised_send.ex`:

```elixir
defmodule Foundation.SupervisedSend do
  @moduledoc """
  OTP-compliant message passing with monitoring and error handling
  """
  
  require Logger
  
  @doc """
  Send a message with delivery monitoring
  """
  def send_supervised(pid, message, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)
    
    case GenServer.call(__MODULE__, {:send, pid, message, timeout}) do
      :ok -> :ok
      {:error, reason} -> handle_send_error(pid, message, reason, opts)
    end
  end
  
  @doc """
  Broadcast to multiple processes with partial failure handling
  """
  def broadcast_supervised(recipients, message, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :best_effort)
    
    results = Enum.map(recipients, fn {_id, pid, _meta} ->
      {pid, send_supervised(pid, message, opts)}
    end)
    
    case strategy do
      :all_or_nothing ->
        if Enum.all?(results, fn {_, result} -> result == :ok end) do
          :ok
        else
          {:error, :partial_failure, results}
        end
        
      :best_effort ->
        {:ok, results}
    end
  end
end
```

#### Phase 2: Update Critical Modules

**Priority order for raw send() fixes:**

1. **coordinator_agent.ex** (5 sends):
```elixir
# Before:
send(pid, {:cancel_task, execution_id})

# After:
Foundation.SupervisedSend.send_supervised(
  pid, 
  {:cancel_task, execution_id},
  timeout: 5000,
  on_error: :log
)
```

2. **signal_router.ex** (1 critical send):
```elixir
# Before:
send(handler_pid, {:routed_signal, signal_type, measurements, metadata})

# After:
GenServer.cast(handler_pid, {:routed_signal, signal_type, measurements, metadata})
```

3. **coordination_patterns.ex** (2 broadcasts):
```elixir
# Before:
Enum.each(agents, fn {_id, pid, _meta} ->
  send(pid, {:hierarchy_broadcast, hierarchy_id, message})
end)

# After:
Foundation.SupervisedSend.broadcast_supervised(
  agents,
  {:hierarchy_broadcast, hierarchy_id, message},
  strategy: :best_effort
)
```

### 3.2 Create Migration Script
**Priority: HIGH**
**Time: 2 days**

`scripts/migrate_raw_sends.exs`:
```elixir
defmodule SendMigrator do
  @moduledoc """
  Automated migration tool for raw send() usage
  """
  
  def run do
    files = find_files_with_sends()
    
    Enum.each(files, fn file ->
      migrate_file(file)
    end)
  end
  
  defp migrate_file(file) do
    content = File.read!(file)
    
    # Pattern 1: send to self - leave alone
    # Pattern 2: send to pid - replace with supervised
    # Pattern 3: test code - leave alone
    
    new_content = 
      content
      |> migrate_simple_sends()
      |> migrate_broadcast_patterns()
      |> add_imports_if_needed()
      
    if content != new_content do
      File.write!(file, new_content)
      IO.puts("Migrated: #{file}")
    end
  end
end
```

### 3.3 Monitor Leak Prevention
**Priority: HIGH**
**Time: 2 days**

Create `lib/foundation/monitor_manager.ex`:
```elixir
defmodule Foundation.MonitorManager do
  @moduledoc """
  Centralized monitor management to prevent leaks
  """
  
  use GenServer
  
  def monitor(pid, tag \\ nil) do
    GenServer.call(__MODULE__, {:monitor, pid, tag})
  end
  
  def demonitor(ref) do
    GenServer.call(__MODULE__, {:demonitor, ref})
  end
  
  def list_monitors do
    GenServer.call(__MODULE__, :list_monitors)
  end
  
  # Implementation handles cleanup on process death
  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    # Automatic cleanup
    new_state = remove_monitor(state, ref)
    
    # Notify interested parties
    notify_monitor_down(ref, pid, reason, state)
    
    {:noreply, new_state}
  end
end
```

---

## Implementation Schedule

### Week 1: Foundation
- Day 1-2: Implement Credo configuration and custom checks
- Day 3: Set up CI pipeline
- Day 4-5: Create OTP compliance test suite

### Week 2: Test Quick Wins
- Day 1-3: Eliminate all Process.sleep usage
- Day 4-5: Fix test isolation in high-value test files

### Week 3: Test Patterns
- Day 1-2: Implement deterministic test patterns
- Day 3-5: Fix process management anti-patterns

### Week 4: Production Hardening
- Day 1-3: Eliminate raw sends in critical paths
- Day 4-5: Implement monitor leak prevention

### Week 5: Verification & Documentation
- Day 1-2: Run full compliance verification
- Day 3-4: Update documentation
- Day 5: Final audit and sign-off

---

## Success Metrics

### Stage 1 Complete When:
- ✅ Credo runs in strict mode with 0 violations
- ✅ CI pipeline blocks PRs with OTP violations
- ✅ Custom checks detect all anti-patterns

### Stage 2 Complete When:
- ✅ 0 Process.sleep calls in test suite
- ✅ All tests use UnifiedTestFoundation
- ✅ Test suite runs 50% faster
- ✅ 0 flaky tests in CI

### Stage 3 Complete When:
- ✅ 0 raw send() calls (except self/test)
- ✅ All processes under supervision
- ✅ Monitor leak test passes
- ✅ Full OTP compliance certification

---

## Risk Mitigation

### Potential Issues:
1. **Test breakage during migration**
   - Mitigation: Run tests after each file change
   - Rollback strategy ready

2. **Performance regression from supervised sends**
   - Mitigation: Benchmark critical paths
   - Use GenServer.cast where appropriate

3. **Hidden dependencies on timing**
   - Mitigation: Use wait_for with longer timeouts initially
   - Log when timeouts are hit

### Rollback Plan:
- All changes in separate commits
- Feature flags for new patterns
- Gradual rollout with monitoring

---

## Appendix: Quick Reference

### Test Migration Cheatsheet:
```elixir
# Instead of Process.sleep
import Foundation.AsyncTestHelpers
wait_for(fn -> condition end)

# Instead of raw spawn  
{:ok, pid} = SupervisedTestProcess.spawn_supervised(fun)

# Instead of global process
use Foundation.UnifiedTestFoundation, :registry

# Instead of :sys.get_state
GenServer.call(server, :get_test_state)
```

### Production Migration Cheatsheet:
```elixir
# Instead of send(pid, msg)
Foundation.SupervisedSend.send_supervised(pid, msg)

# Instead of Process.spawn
Task.Supervisor.start_child(MyApp.TaskSupervisor, fun)

# Instead of raw monitors
ref = Foundation.MonitorManager.monitor(pid)
```

---

*Generated: July 2, 2025*
*Estimated effort: 5 weeks*
*Expected improvement: 50% faster tests, 100% OTP compliance*