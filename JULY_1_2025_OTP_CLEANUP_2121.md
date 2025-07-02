# OTP Cleanup Plan - Process Dictionary Elimination
Generated: July 2, 2025

## Executive Summary

This document provides a comprehensive plan to eliminate all Process dictionary usage from the Foundation/Jido codebase, replacing it with proper OTP patterns. This addresses the 37 violations found during CI compliance checks and establishes architectural foundations for long-term maintainability.

**Time Estimate**: 5-7 days
**Risk**: Medium - touches core functionality but follows established patterns
**Impact**: Eliminates anti-patterns, improves testability, enables proper supervision

## Context & Required Reading

Based on analysis of existing OTP refactor documentation:
1. `JULY_1_2025_PRE_PHASE_2_OTP_report_01.md` - Banned primitives and enforcement
2. `JULY_1_2025_PRE_PHASE_2_OTP_report_02.md` - State management patterns  
3. `JULY_1_2025_PRE_PHASE_2_OTP_report_05.md` - Feature flags and deployment
4. `test/SUPERVISION_TESTING_GUIDE.md` - Proper OTP testing patterns

## The Problem

CI found 37 instances of `Process.put/get` usage across the codebase:

### **Anti-Pattern Categories**

1. **Registry State** (12 violations)
   - `lib/foundation/protocols/registry_any.ex` - Agent registry using process dictionary
   - `lib/mabeam/agent_registry_impl.ex` - Cache using process state

2. **Error Context** (2 violations)  
   - `lib/foundation/error_context.ex` - Error context stored in process dictionary

3. **Telemetry Caching/Coordination** (15 violations)
   - `lib/foundation/telemetry/sampled_events.ex` - Event deduplication and batching
   - `lib/foundation/telemetry/span.ex` - Span stack tracking
   - `lib/foundation/telemetry/load_test.ex` - Test coordination

4. **Test State Management** (8 violations)
   - Various test files using process dictionary for coordination

## Stage 1: Create Infrastructure (Day 1)

### 1.1: Add Process Dictionary Bans to Credo

**File**: `.credo.exs`

Add to the `checks` section:

```elixir
# Ban process dictionary for state management
{Credo.Check.Warning.ProcessDict, []},

# Custom check for Process.put/get usage
{Foundation.CredoChecks.NoProcessDict, [
  # Allow in specific whitelisted modules
  allowed_modules: [
    "Foundation.Telemetry.Span",  # Temporary - will be fixed
    "Foundation.Telemetry.SampledEvents"  # Temporary - will be fixed
  ]
]}
```

### 1.2: Create Custom Credo Check

**File**: `lib/foundation/credo_checks/no_process_dict.ex`

```elixir
defmodule Foundation.CredoChecks.NoProcessDict do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Process dictionary bypasses OTP supervision and makes testing difficult.
      Use GenServer state, ETS tables, or explicit parameter passing instead.
      """
    ]

  def run(source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    allowed_modules = Params.get(params, :allowed_modules, [])
    
    if should_check_file?(source_file, allowed_modules) do
      Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
    else
      []
    end
  end
  
  defp should_check_file?(source_file, allowed_modules) do
    filename = source_file.filename
    not Enum.any?(allowed_modules, fn module ->
      String.contains?(filename, String.replace(module, ".", "/"))
    end)
  end
  
  defp traverse({{:., _, [{:__aliases__, _, [:Process]}, func]}, meta, _args} = ast, issues, issue_meta) 
       when func in [:put, :get] do
    issue = format_issue(issue_meta,
      message: "Avoid Process.#{func}/2 - use GenServer state or ETS instead",
      line_no: meta[:line]
    )
    {ast, [issue | issues]}
  end
  
  defp traverse(ast, issues, _), do: {ast, issues}
end
```

### 1.3: Update CI Pipeline

**File**: `.github/workflows/elixir.yml`

Update the OTP compliance check:

```yaml
- name: Check OTP compliance - ban dangerous patterns
  run: |
    echo "Checking for banned Process.spawn usage..."
    ! grep -r "Process\.spawn\|spawn(" lib/ --include="*.ex" || (echo "ERROR: Found Process.spawn usage!" && exit 1)
    
    echo "Checking for Process.put/get usage..."
    ! grep -r "Process\.put\|Process\.get" lib/ --include="*.ex" --exclude-dir=telemetry || (echo "ERROR: Found Process dictionary usage!" && exit 1)
    
    echo "OTP compliance checks passed!"
```

## Stage 2: Replace Registry Anti-Patterns (Days 2-3)

### 2.1: Fix Foundation.Protocols.RegistryAny

**Problem**: Uses `Process.put/get(:registered_agents, %{})` for agent registry.

**File**: `lib/foundation/protocols/registry_any.ex`

**Current Anti-Pattern**:
```elixir
agents = Process.get(:registered_agents, %{})
Process.put(:registered_agents, new_agents)
```

**Solution**: Replace with proper ETS-based registry.

**New Implementation**:

```elixir
defmodule Foundation.Protocols.RegistryAny do
  @table_name :foundation_agent_registry
  
  def register_agent(agent_id, pid) when is_pid(pid) do
    ensure_table_exists()
    
    # Monitor the process for cleanup
    ref = Process.monitor(pid)
    
    :ets.insert(@table_name, {agent_id, pid, ref})
    
    # Store reverse lookup for cleanup
    :ets.insert(@table_name, {{:monitor, ref}, agent_id})
    
    :ok
  end
  
  def get_agent(agent_id) do
    ensure_table_exists()
    
    case :ets.lookup(@table_name, agent_id) do
      [{^agent_id, pid, _ref}] when is_pid(pid) ->
        if Process.alive?(pid) do
          {:ok, pid}
        else
          # Clean up dead process
          unregister_agent(agent_id)
          {:error, :not_found}
        end
      [] ->
        {:error, :not_found}
    end
  end
  
  def list_agents do
    ensure_table_exists()
    
    :ets.select(@table_name, [
      {{:"$1", :"$2", :"$3"}, [{:is_atom, :"$1"}], [{{:"$1", :"$2"}}]}
    ])
    |> Enum.filter(fn {_id, pid} -> Process.alive?(pid) end)
  end
  
  def unregister_agent(agent_id) do
    ensure_table_exists()
    
    case :ets.lookup(@table_name, agent_id) do
      [{^agent_id, _pid, ref}] ->
        Process.demonitor(ref, [:flush])
        :ets.delete(@table_name, agent_id)
        :ets.delete(@table_name, {:monitor, ref})
        :ok
      [] ->
        :ok
    end
  end
  
  # Handle process death cleanup
  def handle_down_message({:DOWN, ref, :process, _pid, _reason}) do
    case :ets.lookup(@table_name, {:monitor, ref}) do
      [{{:monitor, ^ref}, agent_id}] ->
        :ets.delete(@table_name, agent_id)
        :ets.delete(@table_name, {:monitor, ref})
        :ok
      [] ->
        :ok
    end
  end
  
  defp ensure_table_exists do
    case :ets.whereis(@table_name) do
      :undefined ->
        :ets.new(@table_name, [
          :set, 
          :public, 
          :named_table,
          {:read_concurrency, true},
          {:write_concurrency, true}
        ])
      _ ->
        @table_name
    end
  end
end
```

### 2.2: Fix MABEAM.AgentRegistryImpl Cache

**File**: `lib/mabeam/agent_registry_impl.ex`

**Problem**: Uses `Process.put/get(cache_key, tables)` for caching.

**Solution**: Replace with ETS-based cache with TTL.

```elixir
defmodule MABEAM.AgentRegistryImpl do
  @cache_table :mabeam_registry_cache
  @cache_ttl :timer.minutes(5)
  
  # Replace cache lookup
  defp get_cached_tables(cache_key) do
    ensure_cache_table()
    
    case :ets.lookup(@cache_table, cache_key) do
      [{^cache_key, tables, expires_at}] ->
        if :erlang.monotonic_time(:millisecond) < expires_at do
          tables
        else
          :ets.delete(@cache_table, cache_key)
          nil
        end
      [] ->
        nil
    end
  end
  
  defp cache_tables(cache_key, tables) do
    ensure_cache_table()
    expires_at = :erlang.monotonic_time(:millisecond) + @cache_ttl
    :ets.insert(@cache_table, {cache_key, tables, expires_at})
    tables
  end
  
  defp ensure_cache_table do
    case :ets.whereis(@cache_table) do
      :undefined ->
        :ets.new(@cache_table, [:set, :public, :named_table])
      _ ->
        @cache_table
    end
  end
end
```

## Stage 3: Replace Error Context Anti-Pattern (Day 3)

### 3.1: Fix Foundation.ErrorContext

**File**: `lib/foundation/error_context.ex`

**Problem**: Uses process dictionary to store error context.

**Current Anti-Pattern**:
```elixir
Process.put(:error_context, context)
Process.get(:error_context)
```

**Solution**: Use Logger metadata and explicit context passing.

```elixir
defmodule Foundation.ErrorContext do
  @moduledoc """
  Error context management using Logger metadata instead of process dictionary.
  """
  
  @doc """
  Set error context in Logger metadata for the current process.
  This is automatically included in all log messages.
  """
  def set_context(context) when is_map(context) do
    # Use Logger metadata instead of process dictionary
    Logger.metadata(error_context: context)
    context
  end
  
  @doc """
  Get current error context from Logger metadata.
  """
  def get_context do
    case Logger.metadata()[:error_context] do
      nil -> %{}
      context when is_map(context) -> context
      _ -> %{}
    end
  end
  
  @doc """
  Execute function with error context, ensuring cleanup.
  """
  def with_context(context, fun) when is_map(context) and is_function(fun, 0) do
    old_context = get_context()
    
    try do
      set_context(Map.merge(old_context, context))
      fun.()
    after
      set_context(old_context)
    end
  end
  
  @doc """
  Add error context to an error struct.
  """
  def enrich_error(%Foundation.Error{} = error) do
    context = get_context()
    
    if map_size(context) > 0 do
      %{error | context: Map.merge(error.context || %{}, context)}
    else
      error
    end
  end
  
  @doc """
  Clear error context for current process.
  """
  def clear_context do
    Logger.metadata(error_context: nil)
    :ok
  end
end
```

## Stage 4: Replace Telemetry Anti-Patterns (Days 4-5)

### 4.1: Fix Foundation.Telemetry.SampledEvents

**File**: `lib/foundation/telemetry/sampled_events.ex`

**Problem**: Uses process dictionary for event deduplication and batching.

**Solution**: Use GenServer with ETS for state management.

```elixir
defmodule Foundation.Telemetry.SampledEvents do
  use GenServer
  
  @table_name :sampled_events_state
  @batch_interval 1000  # 1 second
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Create ETS table for deduplication and batching
    :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
    
    # Schedule batch processing
    Process.send_after(self(), :process_batches, @batch_interval)
    
    {:ok, %{}}
  end
  
  def emit_event(event_name, measurements, metadata) do
    key = {event_name, metadata[:dedup_key]}
    now = System.monotonic_time(:millisecond)
    
    # Atomic check and update for deduplication
    match_spec = [
      {{key, :"$1"}, [{:<, {:-, now, :"$1"}, 5000}], [false]},
      {{key, :"$1"}, [], [true]}
    ]
    
    case :ets.select(@table_name, match_spec) do
      [false] ->
        # Too recent, skip
        :ok
      _ ->
        # Update timestamp and emit
        :ets.insert(@table_name, {key, now})
        :telemetry.execute(event_name, measurements, metadata)
    end
  end
  
  def emit_batched(event_name, measurement, metadata) do
    batch_key = {:batch, event_name, metadata[:batch_key] || :default}
    
    # Add to batch atomically
    :ets.update_counter(@table_name, batch_key, {2, measurement}, {batch_key, 0, []})
    
    :ok
  end
  
  def handle_info(:process_batches, state) do
    # Process all batches
    batches = :ets.select(@table_name, [
      {{{:batch, :"$1", :"$2"}, :"$3", :"$4"}, [], [{{:"$1", :"$2", :"$3", :"$4"}}]}
    ])
    
    Enum.each(batches, fn {event_name, batch_key, count, events} ->
      if count > 0 do
        :telemetry.execute(
          [:batched | event_name],
          %{count: count},
          %{batch_key: batch_key, events: events}
        )
        
        # Clear batch
        :ets.delete(@table_name, {:batch, event_name, batch_key})
      end
    end)
    
    # Schedule next batch
    Process.send_after(self(), :process_batches, @batch_interval)
    
    {:noreply, state}
  end
end
```

### 4.2: Fix Foundation.Telemetry.Span

**File**: `lib/foundation/telemetry/span.ex`

**Problem**: Uses process dictionary for span stack tracking.

**Solution**: Use GenServer-based span context manager.

```elixir
defmodule Foundation.Telemetry.Span do
  use GenServer
  
  @context_table :span_contexts
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    :ets.new(@context_table, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
    
    {:ok, %{}}
  end
  
  @doc """
  Start a new span for the current process.
  """
  def start_span(name, metadata \\ %{}) do
    process = self()
    span_id = make_ref()
    
    # Get current stack
    stack = get_span_stack(process)
    
    span = %{
      id: span_id,
      name: name,
      metadata: metadata,
      start_time: System.monotonic_time(:microsecond),
      parent: List.first(stack)
    }
    
    # Push to stack
    new_stack = [span | stack]
    :ets.insert(@context_table, {process, new_stack})
    
    # Emit start event
    :telemetry.execute(
      [:span, :start],
      %{count: 1},
      Map.merge(metadata, %{span_id: span_id, name: name})
    )
    
    span_id
  end
  
  @doc """
  End the current span for the current process.
  """
  def end_span(span_id) do
    process = self()
    stack = get_span_stack(process)
    
    case stack do
      [%{id: ^span_id} = span | rest] ->
        # Calculate duration
        duration = System.monotonic_time(:microsecond) - span.start_time
        
        # Update stack
        :ets.insert(@context_table, {process, rest})
        
        # Emit end event
        :telemetry.execute(
          [:span, :end],
          %{duration: duration},
          Map.merge(span.metadata, %{
            span_id: span_id,
            name: span.name
          })
        )
        
        :ok
        
      _ ->
        # Span not found or not current
        {:error, :span_not_found}
    end
  end
  
  @doc """
  Execute function within a span.
  """
  def with_span(name, metadata, fun) when is_function(fun, 0) do
    span_id = start_span(name, metadata)
    
    try do
      result = fun.()
      end_span(span_id)
      result
    rescue
      exception ->
        end_span(span_id)
        reraise exception, __STACKTRACE__
    end
  end
  
  defp get_span_stack(process) do
    case :ets.lookup(@context_table, process) do
      [{^process, stack}] -> stack
      [] -> []
    end
  end
end
```

## Stage 5: Replace Test Anti-Patterns (Day 6)

### 5.1: Update Test Infrastructure

Based on `test/SUPERVISION_TESTING_GUIDE.md`, replace process dictionary usage in tests with proper synchronization.

**Create**: `test/support/async_test_helpers.ex`

```elixir
defmodule Foundation.AsyncTestHelpers do
  @moduledoc """
  Async test helpers that don't rely on process dictionary.
  """
  
  @doc """
  Wait for a condition to be true, with timeout.
  Replaces Process.get based coordination.
  """
  def wait_for(condition_fun, timeout \\ 5000) when is_function(condition_fun, 0) do
    end_time = System.monotonic_time(:millisecond) + timeout
    wait_for_loop(condition_fun, end_time)
  end
  
  defp wait_for_loop(condition_fun, end_time) do
    if condition_fun.() do
      :ok
    else
      if System.monotonic_time(:millisecond) >= end_time do
        {:error, :timeout}
      else
        Process.sleep(10)
        wait_for_loop(condition_fun, end_time)
      end
    end
  end
  
  @doc """
  Wait for multiple events with proper synchronization.
  """
  def wait_for_events(event_specs, timeout \\ 5000) do
    parent = self()
    
    # Start collectors for each event
    collectors = Enum.map(event_specs, fn {name, pattern} ->
      collector_pid = spawn_link(fn ->
        receive do
          ^pattern -> send(parent, {:event_received, name})
        after
          timeout -> send(parent, {:event_timeout, name})
        end
      end)
      
      {name, collector_pid}
    end)
    
    # Wait for all events
    wait_for_all_events(collectors, timeout)
  end
  
  defp wait_for_all_events([], _timeout), do: :ok
  
  defp wait_for_all_events(collectors, timeout) do
    receive do
      {:event_received, name} ->
        remaining = List.keydelete(collectors, name, 0)
        wait_for_all_events(remaining, timeout)
        
      {:event_timeout, name} ->
        {:error, {:timeout, name}}
    after
      timeout -> {:error, :global_timeout}
    end
  end
end
```

### 5.2: Update Telemetry Tests

Replace process dictionary coordination in telemetry tests:

```elixir
# WRONG - Current pattern in tests
def test_telemetry_event do
  Process.put(:event_received, false)
  
  handler = fn _event, _measurements, _metadata, _ ->
    Process.put(:event_received, true)
  end
  
  :telemetry.attach("test", [:my, :event], handler, nil)
  emit_event()
  
  assert Process.get(:event_received) == true
end

# RIGHT - New pattern
def test_telemetry_event do
  parent = self()
  
  handler = fn _event, _measurements, _metadata, _ ->
    send(parent, :event_received)
  end
  
  :telemetry.attach("test", [:my, :event], handler, nil)
  emit_event()
  
  assert_receive :event_received, 1000
end
```

## Stage 6: Feature Flag Integration (Day 7)

### 6.1: Add Feature Flags

**File**: `lib/foundation/feature_flags.ex` (extend existing)

Add process dictionary cleanup flags:

```elixir
@otp_cleanup_flags %{
  use_ets_agent_registry: false,
  use_logger_error_context: false,
  use_genserver_telemetry: false,
  enforce_no_process_dict: false
}
```

### 6.2: Gradual Migration Strategy

```elixir
defmodule Foundation.Protocols.RegistryAny do
  def register_agent(agent_id, pid) do
    if Foundation.FeatureFlags.enabled?(:use_ets_agent_registry) do
      register_agent_ets(agent_id, pid)
    else
      register_agent_legacy(agent_id, pid)
    end
  end
  
  # New ETS implementation
  defp register_agent_ets(agent_id, pid) do
    # Implementation from Stage 2.1
  end
  
  # Legacy process dictionary implementation
  defp register_agent_legacy(agent_id, pid) do
    agents = Process.get(:registered_agents, %{})
    Process.put(:registered_agents, Map.put(agents, agent_id, pid))
  end
end
```

## Testing Strategy

### Unit Tests

```elixir
defmodule Foundation.ProcessDictCleanupTest do
  use ExUnit.Case
  import Foundation.AsyncTestHelpers
  
  describe "ETS-based agent registry" do
    test "registers and retrieves agents" do
      Foundation.Protocols.RegistryAny.register_agent(:test_agent, self())
      
      assert {:ok, pid} = Foundation.Protocols.RegistryAny.get_agent(:test_agent)
      assert pid == self()
    end
    
    test "cleans up dead processes" do
      dead_pid = spawn(fn -> :ok end)
      Process.sleep(10)  # Let it die
      
      Foundation.Protocols.RegistryAny.register_agent(:dead_agent, dead_pid)
      
      # Should clean up automatically
      assert {:error, :not_found} = Foundation.Protocols.RegistryAny.get_agent(:dead_agent)
    end
  end
  
  describe "error context with logger metadata" do
    test "sets and retrieves context" do
      context = %{request_id: "123", user_id: "456"}
      
      Foundation.ErrorContext.set_context(context)
      assert Foundation.ErrorContext.get_context() == context
    end
    
    test "context is included in errors" do
      Foundation.ErrorContext.set_context(%{request_id: "123"})
      
      error = Foundation.Error.business_error(:invalid_input, "Bad data")
      enriched = Foundation.ErrorContext.enrich_error(error)
      
      assert enriched.context[:request_id] == "123"
    end
  end
end
```

### Integration Tests

```elixir
defmodule Foundation.ProcessDictIntegrationTest do
  use ExUnit.Case
  
  test "no process dictionary usage in production code" do
    # Scan all lib files
    lib_files = Path.wildcard("lib/**/*.ex")
    
    violations = Enum.flat_map(lib_files, fn file ->
      content = File.read!(file)
      
      case Regex.scan(~r/Process\.(put|get)/, content, return: :index) do
        [] -> []
        matches -> [{file, matches}]
      end
    end)
    
    # Allow only in whitelisted files during migration
    allowed_files = [
      "lib/foundation/telemetry/span.ex",  # Will be fixed
      "lib/foundation/telemetry/sampled_events.ex"  # Will be fixed
    ]
    
    unexpected_violations = Enum.reject(violations, fn {file, _} ->
      Enum.any?(allowed_files, &String.contains?(file, &1))
    end)
    
    assert unexpected_violations == [],
           "Found unexpected Process.put/get usage in: #{inspect(unexpected_violations)}"
  end
end
```

## Rollout Plan

### Phase 1: Infrastructure (Day 1)
- Add Credo checks
- Update CI pipeline
- Create test helpers

### Phase 2: Registry Fixes (Days 2-3)  
- Fix RegistryAny with feature flag
- Fix MABEAM cache with feature flag
- Test in staging

### Phase 3: Error Context (Day 3)
- Replace with Logger metadata
- Update all error handling code
- Test error enrichment

### Phase 4: Telemetry (Days 4-5)
- GenServer-based span management
- ETS-based event deduplication
- Update all telemetry tests

### Phase 5: Test Cleanup (Day 6)
- Remove process dictionary from tests
- Use proper async helpers
- Verify all tests pass

### Phase 6: Enable Enforcement (Day 7)
- Enable all feature flags
- Remove legacy code paths
- Update Credo to strict mode

## Success Metrics

1. **Zero Process Dictionary Usage**: CI checks pass completely
2. **All Tests Pass**: No regressions in functionality
3. **Performance Maintained**: < 5% performance impact
4. **Improved Testability**: Tests run reliably without flakes

## Summary

This plan systematically eliminates all Process dictionary usage by:

1. **Establishing enforcement** through Credo and CI
2. **Replacing with proper patterns**: ETS, GenServer, explicit passing
3. **Maintaining safety** through feature flags and gradual rollout
4. **Ensuring quality** through comprehensive testing

The result will be a codebase that fully embraces OTP principles, making it more reliable, testable, and maintainable.

**Next Steps**: Execute plan phase by phase, monitoring for regressions and celebrating the elimination of this significant anti-pattern!