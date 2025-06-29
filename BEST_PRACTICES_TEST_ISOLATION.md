# Best Practices: Test Isolation in Elixir/OTP Systems

## Executive Summary

Test isolation failures are the **#1 cause of flaky tests** in Elixir applications. This document provides production-grade patterns for eliminating test contamination through proper OTP supervision, process naming, and state management.

## The Problem: Test Contamination

### **Symptoms**
- ✅ Tests pass individually 
- ❌ Tests fail in suite context
- 🔄 Intermittent failures
- ⏱️ Timeout assertions
- 📮 "Process mailbox is empty" errors

### **Root Causes**
1. **Shared Named Processes** - Multiple tests compete for same process names
2. **Global State Pollution** - ETS tables, registries, telemetry handlers
3. **Process Lifecycle Leakage** - Processes from previous tests interfere
4. **Resource Contention** - Shared application services

## The Solution: Test Supervision Trees

### **Core Principle**
> **Each test should run in complete isolation with its own supervision tree and zero shared state.**

### **Implementation Strategy**
1. **Test-Scoped Process Names** - Unique names per test
2. **Isolated Supervision Trees** - Each test gets own supervisor
3. **Automatic Cleanup** - OTP supervision handles process cleanup
4. **Resource Isolation** - Test-specific instances of all services

---

## Implementation Patterns

### **Pattern 1: Test Supervision Tree**

```elixir
defmodule Foundation.TestIsolation do
  @doc """
  Creates completely isolated test environment with own supervision tree.
  """
  def start_isolated_test(opts \\ []) do
    test_id = :erlang.unique_integer([:positive])
    
    test_context = %{
      test_id: test_id,
      signal_bus_name: :"test_signal_bus_#{test_id}",
      registry_name: :"test_registry_#{test_id}",
      router_name: :"test_router_#{test_id}",
      telemetry_prefix: "test_#{test_id}"
    }
    
    # Define test-scoped supervision tree
    children = [
      {MySignalBus, [name: test_context.signal_bus_name]},
      {Registry, [keys: :unique, name: test_context.registry_name]},
      {MyRouter, [name: test_context.router_name]},
      # Add other services as needed
    ]
    
    supervisor_opts = [
      strategy: :one_for_one,
      name: :"test_supervisor_#{test_id}"
    ]
    
    case Supervisor.start_link(children, supervisor_opts) do
      {:ok, supervisor} -> {:ok, supervisor, test_context}
      error -> error
    end
  end
  
  def stop_isolated_test(supervisor) do
    # Stop supervisor - automatically stops all children
    Supervisor.stop(supervisor, :normal, 5000)
    
    # Clean up any remaining global state
    cleanup_telemetry_handlers()
    cleanup_ets_tables()
    
    :ok
  catch
    :exit, {:noproc, _} -> :ok
  end
end
```

### **Pattern 2: Test-Scoped Process Names**

```elixir
# ❌ WRONG: Global names cause contamination
defmodule MyService do
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
end

# ✅ RIGHT: Test-scoped names
defmodule MyService do
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
end

# Usage in tests:
test_name = :"my_service_#{:erlang.unique_integer([:positive])}"
{:ok, pid} = MyService.start_link(name: test_name)
```

### **Pattern 3: Telemetry Handler Isolation**

```elixir
defmodule Foundation.TestTelemetry do
  @doc """
  Attaches test-scoped telemetry handler with automatic cleanup.
  """
  def attach_test_handler(test_id, event, handler_fun) do
    handler_id = "test_#{test_id}_#{:erlang.unique_integer([:positive])}"
    
    :telemetry.attach(handler_id, event, handler_fun, nil)
    
    # Return cleanup function
    fn -> 
      try do
        :telemetry.detach(handler_id)
      catch
        _, _ -> :ok
      end
    end
  end
  
  @doc """
  Cleans up all test telemetry handlers.
  """
  def cleanup_test_handlers(test_id) do
    :telemetry.list_handlers([])
    |> Enum.filter(&String.contains?(&1.id, "test_#{test_id}"))
    |> Enum.each(fn handler ->
      try do
        :telemetry.detach(handler.id)
      catch
        _, _ -> :ok
      end
    end)
  end
end
```

### **Pattern 4: ETS Table Isolation**

```elixir
# ❌ WRONG: Named ETS tables shared across tests
:ets.new(:my_table, [:named_table, :public])

# ✅ RIGHT: Test-scoped ETS tables
defmodule TestETSManager do
  def create_test_table(test_id, name) do
    table_name = :"#{name}_#{test_id}"
    :ets.new(table_name, [:named_table, :public])
    
    # Return cleanup function
    fn ->
      try do
        :ets.delete(table_name)
      catch
        _, _ -> :ok
      end
    end
  end
end
```

### **Pattern 5: Registry Isolation**

```elixir
# Test setup with isolated registry
setup do
  test_id = :erlang.unique_integer([:positive])
  registry_name = :"test_registry_#{test_id}"
  
  {:ok, _} = Registry.start_link(keys: :unique, name: registry_name)
  
  on_exit(fn ->
    if Process.whereis(registry_name) do
      GenServer.stop(registry_name)
    end
  end)
  
  %{registry: registry_name, test_id: test_id}
end
```

---

## Standard Test Configuration

### **Base Test Module**

```elixir
defmodule Foundation.TestConfig do
  defmacro __using__(type) do
    quote do
      use ExUnit.Case, async: false  # Start with serial, optimize later
      alias Foundation.TestIsolation
      import Foundation.TestConfig
      
      unquote(apply_test_type(type))
    end
  end
  
  defp apply_test_type(:isolated) do
    quote do
      setup do
        isolated_foundation_setup()
      end
    end
  end
  
  defp apply_test_type(:signal_routing) do
    quote do
      setup do
        signal_routing_setup()
      end
    end
  end
  
  def isolated_foundation_setup(opts \\ []) do
    {:ok, supervisor, test_context} = TestIsolation.start_isolated_test(opts)
    
    on_exit(fn ->
      TestIsolation.stop_isolated_test(supervisor)
    end)
    
    %{test_context: test_context, supervisor: supervisor}
  end
  
  def signal_routing_setup(opts \\ []) do
    base_setup = isolated_foundation_setup(opts)
    test_context = base_setup.test_context
    
    # Start test-scoped signal router
    {:ok, router_pid} = start_test_signal_router(test_context)
    
    on_exit(fn ->
      if Process.alive?(router_pid) do
        GenServer.stop(router_pid)
      end
    end)
    
    Map.merge(base_setup, %{
      router_pid: router_pid,
      signal_bus_name: test_context.signal_bus_name
    })
  end
end
```

### **Usage in Tests**

```elixir
defmodule MyFeatureTest do
  use Foundation.TestConfig, :signal_routing
  
  test "feature works correctly", %{test_context: ctx, signal_bus_name: bus} do
    # All services are isolated - no contamination possible
    agent = start_test_agent(ctx)
    
    Bridge.emit_signal(agent, %{type: "test"}, bus: bus)
    
    assert_receive {:signal_received, "test"}
  end
end
```

---

## Migration Strategy

### **Phase 1: Infrastructure Setup**
1. Create `TestIsolation` module
2. Create `TestConfig` base module  
3. Create isolated versions of core services
4. Set up cleanup helpers

### **Phase 2: Critical Path Migration**
1. Identify most problematic test files (flaky tests)
2. Convert to isolated pattern
3. Verify reliability improvement
4. Document patterns for team

### **Phase 3: Gradual Migration**
1. Convert test files one by one
2. Update CI to catch contamination
3. Add linting rules for global state usage
4. Training and documentation

### **Phase 4: Optimization**
1. Re-enable `async: true` for truly isolated tests
2. Performance profiling
3. Resource usage optimization
4. Advanced patterns (test pooling, etc.)

---

## Troubleshooting Guide

### **Common Issues**

| Symptom | Root Cause | Solution |
|---------|------------|----------|
| Tests pass individually, fail in suite | Shared process names | Use test-scoped names |
| "Process not alive" errors | Process cleanup race conditions | Use defensive cleanup with try/catch |
| Timeout assertions | Missing telemetry handlers | Use isolated telemetry setup |
| ETS table conflicts | Named ETS tables | Use test-scoped ETS table names |
| Registry conflicts | Shared registry processes | Create test-specific registries |

### **Debugging Test Contamination**

```elixir
# Add to failing tests to identify contamination
setup do
  # Log all named processes before test
  before_processes = Process.registered()
  
  # Log all telemetry handlers
  before_handlers = :telemetry.list_handlers([])
  
  on_exit(fn ->
    after_processes = Process.registered()
    after_handlers = :telemetry.list_handlers([])
    
    leaked_processes = after_processes -- before_processes
    leaked_handlers = after_handlers -- before_handlers
    
    if leaked_processes != [] do
      IO.puts("LEAKED PROCESSES: #{inspect(leaked_processes)}")
    end
    
    if leaked_handlers != [] do
      IO.puts("LEAKED HANDLERS: #{inspect(leaked_handlers)}")
    end
  end)
  
  :ok
end
```

---

## Production Examples

### **Phoenix Applications**
```elixir
# Phoenix uses this pattern for isolated channel tests
use MyAppWeb.ChannelCase  # Provides isolated PubSub, Endpoint
```

### **Ecto Applications**  
```elixir
# Ecto uses this for isolated database tests
use MyApp.DataCase  # Provides isolated database connection
```

### **OTP Applications**
```elixir
# Standard OTP pattern for service tests
use MyApp.ServiceCase  # Provides isolated supervision tree
```

---

## Best Practices Summary

### **✅ DO**
- Use test supervision trees for complete isolation
- Generate unique names for all test processes
- Clean up all resources in `on_exit` callbacks
- Start with `async: false`, optimize later
- Use defensive cleanup with try/catch
- Monitor test reliability metrics

### **❌ DON'T**
- Share named processes across tests
- Use global state (Application config, ETS, etc.)
- Rely on test ordering
- Use `Process.sleep()` for coordination
- Leave resources uncleaned
- Ignore intermittent test failures

### **🔧 TOOLS**
- `Supervisor.start_link/2` - Test supervision trees
- `:erlang.unique_integer/1` - Unique test IDs
- `on_exit/1` - Automatic cleanup
- `ExUnit.Case.async: false` - Serial execution when needed
- `:telemetry.list_handlers/1` - Debug telemetry state

---

## Conclusion

Proper test isolation is **essential** for reliable Elixir test suites. The patterns in this document eliminate test contamination through:

1. **Complete Process Isolation** - Each test gets own supervision tree
2. **Zero Shared State** - Test-scoped names for all resources  
3. **Automatic Cleanup** - OTP supervision handles process lifecycle
4. **Standard Patterns** - Production-proven approaches from major projects

**Result**: Reliable, fast, maintainable test suites that scale with your application.

**Implementation**: Start with critical path tests, migrate gradually, measure improvements.