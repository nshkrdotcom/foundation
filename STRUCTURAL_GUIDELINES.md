# Foundation Structural Guidelines
**Source of Truth for New Codebase Development**

## Core Principles

### 1. **Test-Driven Development (Mandatory)**
- **Red-Green-Refactor**: Write failing test first, minimal implementation, then refactor
- **95% Coverage Minimum**: All code must have comprehensive test coverage
- **No Code Without Tests**: Zero tolerance for untested code in production

### 2. **OTP Compliance (Zero Tolerance)**
- **Supervised Processes Only**: No `spawn/1`, `spawn_link/1`, or `Task.start/1` in application code
- **Use Task.Supervisor**: All concurrent work must go through `Task.Supervisor.start_child/2`
- **Proper GenServer Structure**: Complete child_spec, init, and proper restart strategies

### 3. **No Sleep for Coordination (Forbidden)**
- **Message-Based Coordination**: Use `receive`/`send` patterns instead of `Process.sleep/1`
- **Event-Driven Architecture**: Leverage telemetry events for state synchronization
- **Deterministic Testing**: Replace all `Process.sleep/1` in tests with condition polling

## Forbidden Patterns

### ❌ **Never Use These**
```elixir
# Unsupervised processes
spawn(fn -> work() end)
Task.start(fn -> background_task() end)
spawn_link(fn -> coordination_loop() end)

# Sleep for coordination
Process.sleep(100)
:timer.sleep(50)

# Mixed supervisor behaviors
defmodule BadSupervisor do
  use DynamicSupervisor
  def handle_call(...), do: ...  # Wrong!
end

# Synchronous bottlenecks
GenServer.call(pid, :complex_operation, :infinity)  # No timeout + blocking
```

## Required Patterns

### ✅ **Always Use These**
```elixir
# Supervised processes
Task.Supervisor.start_child(AppName.TaskSupervisor, fn -> work() end)

# Message-based coordination
def wait_for_ready(pid) do
  receive do
    {:ready, ^pid} -> :ok
  after
    5000 -> {:error, :timeout}
  end
end

# Proper GenServer structure
defmodule AppName.Service do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end
end

# Asynchronous communication preferred
GenServer.cast(worker_pid, {:process_data, data})
GenServer.call(worker_pid, request, 5000)  # Always specify timeout
```

## Module Structure Standards

### **Complete Module Template**
```elixir
defmodule Foundation.ComponentName do
  @moduledoc """
  Clear, concise purpose statement.
  
  ## Examples
  
      iex> Foundation.ComponentName.function(arg)
      {:ok, result}
  """
  
  # 1. Module attributes and types
  @enforce_keys [:required_field]
  defstruct @enforce_keys ++ [optional_field: nil]
  
  @type t :: %__MODULE__{
    required_field: String.t(),
    optional_field: term() | nil
  }
  
  # 2. Client API (public interface)
  @spec function(String.t()) :: {:ok, t()} | {:error, Foundation.Types.Error.t()}
  def function(arg) when is_binary(arg) do
    # Implementation
  end
  
  # 3. GenServer callbacks (if applicable)
  @impl true
  def init(opts), do: {:ok, initial_state(opts)}
  
  # 4. Private helper functions
  defp initial_state(opts), do: %{}
end
```

### **Type Specifications (Mandatory)**
```elixir
# Every struct needs @type t
@type t :: %__MODULE__{field: type()}

# Every public function needs @spec
@spec register(pid(), metadata()) :: {:ok, t()} | {:error, Foundation.Types.Error.t()}

# Domain-specific types
@type agent_id :: String.t()
@type capability :: atom()
@type result(success_type) :: {:ok, success_type} | {:error, Foundation.Types.Error.t()}
```

### **Error Handling Standards**
```elixir
# Use Foundation.Types.Error everywhere
alias Foundation.Types.Error

def risky_operation(data) do
  with {:ok, validated} <- validate(data),
       {:ok, processed} <- process(validated),
       {:ok, result} <- finalize(processed) do
    {:ok, result}
  else
    {:error, %Error{} = error} -> {:error, error}
    {:error, reason} -> {:error, Error.new(:operation, :failed, inspect(reason))}
  end
end
```

## Supervision Architecture

### **Required Supervision Tree**
```elixir
# Application root
Foundation.Application (Supervisor)
├── Foundation.ProcessRegistry (GenServer)
├── Foundation.ServiceRegistry (GenServer)  
├── Foundation.TaskSupervisor (DynamicSupervisor)
├── Foundation.HealthMonitor (GenServer)
└── Foundation.ServiceMonitor (GenServer)

# No unsupervised processes anywhere
```

### **GenServer Bottleneck Prevention**
```elixir
# ✅ Prefer asynchronous operations
GenServer.cast(pid, {:update, data})

# ✅ Use ETS for read-heavy operations
:ets.lookup(:config_cache, key)

# ✅ Delegate heavy work to Tasks
def handle_call({:complex_work, data}, from, state) do
  Task.Supervisor.start_child(MyApp.TaskSupervisor, fn ->
    result = do_complex_work(data)
    GenServer.reply(from, result)
  end)
  {:noreply, state}
end
```

## Testing Standards

### **TDD Structure**
```elixir
defmodule Foundation.ComponentTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  
  alias Foundation.Component
  
  describe "function/1" do
    test "succeeds with valid input" do
      assert {:ok, result} = Component.function("valid")
      assert result.field == expected
    end
    
    test "fails with invalid input" do
      assert {:error, %Foundation.Types.Error{}} = Component.function("invalid")
    end
    
    property "handles all valid inputs correctly" do
      check all input <- valid_input_generator() do
        assert {:ok, _result} = Component.function(input)
      end
    end
  end
end
```

### **Test Helpers for Deterministic Testing**
```elixir
# Instead of Process.sleep/1
def wait_for_condition(condition_fn, timeout \\ 5000) do
  end_time = System.monotonic_time(:millisecond) + timeout
  wait_loop(condition_fn, end_time)
end

defp wait_loop(condition_fn, end_time) do
  if condition_fn.() do
    :ok
  else
    if System.monotonic_time(:millisecond) >= end_time do
      {:error, :timeout}
    else
      Process.sleep(10)
      wait_loop(condition_fn, end_time)
    end
  end
end
```

## Architectural Boundaries

### **Decoupling Requirements**
```elixir
# ❌ Direct coupling
Foundation.ProcessRegistry.register(...)

# ✅ Interface-based decoupling
@behaviour Foundation.Registry
def register(registry \\ @default_registry, ...) do
  registry.register(...)
end
```

### **Configuration Standards**
```elixir
# config/config.exs - Each app owns its config
config :foundation,
  process_registry: [backend: Foundation.ProcessRegistry.ETS]

config :mabeam,  # Separate app config
  coordination: [strategy: :consensus]
```

### **Event System Decoupling**
```elixir
# ✅ Proper namespacing
:telemetry.execute([:foundation, :registry, :registered], %{count: 1})
:telemetry.execute([:mabeam, :agent, :started], %{agent_id: id})

# ❌ Cross-namespace pollution
:telemetry.execute([:foundation, :mabeam, :agent, :started], ...)  # Wrong!
```

## Quality Automation

### **Pre-commit Requirements**
```bash
# All must pass before commit
mix format --check-formatted
mix test --cover
mix credo --strict
mix dialyzer
./scripts/check_antipatterns.sh
```

### **Anti-pattern Detection**
```bash
# Check for forbidden patterns
grep -r "spawn(" lib/ --include="*.ex" | grep -v "# Approved:"
grep -r "Process.sleep" lib/ --include="*.ex"
grep -A 10 "use DynamicSupervisor" lib/**/*.ex | grep "handle_call"
```

## Development Workflow

### **Feature Development Process**
1. **Write failing test first** (Red)
2. **Minimal implementation** (Green)  
3. **Refactor while keeping tests green**
4. **Quality checks**: format, credo, dialyzer, anti-patterns
5. **Integration verification**

### **Performance Standards**
- **Process registry**: <1ms lookup latency
- **Service discovery**: <5ms resolution time  
- **Error creation**: <0.1ms overhead
- **No memory leaks**: Proper resource cleanup in all paths

## Context Window Optimization

### **Module Size Limits**
- **Maximum 500 lines per module** - Split larger modules
- **Maximum 50 lines per function** - Extract helper functions
- **Single responsibility** - One clear purpose per module

### **Documentation Requirements**
```elixir
@moduledoc """
Single paragraph describing exact purpose.

## Examples (Always include)

    iex> Module.function(input)
    expected_output
"""

@doc """
One sentence describing what function does.

Returns `{:ok, result}` on success, `{:error, reason}` on failure.
"""
@spec function(input()) :: {:ok, result()} | {:error, Foundation.Types.Error.t()}
```

## Summary Checklist

**Before writing any code:**
- [ ] Test written first (TDD)
- [ ] Uses supervised processes only
- [ ] No Process.sleep for coordination
- [ ] Proper @type t and @spec annotations
- [ ] Error handling via Foundation.Types.Error
- [ ] Async communication preferred
- [ ] Module under 500 lines
- [ ] Complete documentation

**This document is the single source of truth for all new Foundation development. Any deviation requires explicit justification and approval.**