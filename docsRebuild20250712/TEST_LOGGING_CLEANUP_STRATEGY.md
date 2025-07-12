# Test Logging Cleanup Strategy - Foundation Jido System

**Problem**: Clean test suite (18 tests, 0 failures) produces excessive error output  
**Goal**: Silent test runs for passing tests, verbose output only for actual failures  
**Approach**: Canonical Elixir/OTP logging configuration patterns

---

## 🎯 CANONICAL SOLUTIONS

### 1. **Test Environment Logger Configuration** (Primary Solution)

**File**: `config/test.exs`
```elixir
# Suppress normal termination logs during tests
config :logger, 
  level: :warning,  # Only show warnings and errors
  compile_time_purge_matching: [
    # Suppress Jido agent normal terminations
    [application: :jido, level_lower_than: :error],
    # Suppress normal Foundation agent terminations  
    [module: Foundation.Variables.CognitiveFloat, level_lower_than: :error],
    [module: Foundation.Variables.CognitiveVariable, level_lower_than: :error]
  ]

# Alternative: Completely silent tests
config :logger, level: :error
```

### 2. **ExUnit Capture Log Pattern** (Standard Practice)

**File**: `test/test_helper.exs`
```elixir
# Capture logs during tests to prevent console spam
ExUnit.start(capture_log: true)

# Or configure per-test basis:
ExUnit.configure(capture_log: true)
```

**Usage in Tests**:
```elixir
defmodule Foundation.Variables.CognitiveFloatTest do
  use ExUnit.Case
  import ExUnit.CaptureLog  # ← Add this
  
  test "some test that might log errors" do
    # Capture logs to prevent console output
    capture_log(fn ->
      {:ok, float_pid} = CognitiveFloat.create("test_float", %{...})
      # ... test logic ...
      GenServer.stop(float_pid)
    end)
  end
end
```

### 3. **Custom Test Logger Backend** (Advanced Solution)

**File**: `config/test.exs`
```elixir
# Custom backend that filters test noise
config :logger, 
  backends: [Foundation.TestLoggerBackend]

config :logger, Foundation.TestLoggerBackend,
  level: :error,
  format: "[$level] $message\n",
  # Filter out normal termination messages
  ignore_patterns: [
    ~r/server terminating.*:normal/,
    ~r/\*\* \(ErlangError\) Erlang error: :normal/
  ]
```

**Implementation**:
```elixir
# lib/foundation/test_logger_backend.ex
defmodule Foundation.TestLoggerBackend do
  @behaviour :gen_event

  def init(_) do
    {:ok, %{}}
  end

  def handle_event({level, _gl, {Logger, message, _timestamp, metadata}}, state) do
    ignore_patterns = Application.get_env(:logger, __MODULE__)[:ignore_patterns] || []
    
    unless should_ignore?(message, ignore_patterns) do
      IO.puts("#{format_level(level)} #{message}")
    end
    
    {:ok, state}
  end

  defp should_ignore?(message, patterns) do
    Enum.any?(patterns, &Regex.match?(&1, to_string(message)))
  end
end
```

### 4. **Process Flag Solution** (Most Targeted)

**File**: `test/support/test_helper.ex`
```elixir
defmodule Foundation.TestHelper do
  def create_silent_agent(module, id, state) do
    # Suppress error_logger for this process tree
    :proc_lib.spawn_link(fn ->
      Process.flag(:trap_exit, true)
      {:ok, pid} = module.create(id, state)
      
      receive do
        :stop -> GenServer.stop(pid, :normal)
      end
    end)
  end
  
  def stop_silent_agent(wrapper_pid) do
    send(wrapper_pid, :stop)
  end
end
```

---

## ⚡ IMMEDIATE IMPLEMENTATION (Recommended)

### **Quick Fix: Update test_helper.exs**

```elixir
# test/test_helper.exs
Application.put_env(:foundation, :test_mode, true)

# SOLUTION 1: Capture all logs during tests
ExUnit.start(capture_log: true)

# SOLUTION 2: Alternative - Silent logger for tests
# config :logger, level: :emergency  # Completely silent

# Ensure Jido is available for testing
Application.ensure_all_started(:jido)
```

### **Config Fix: Add to config/test.exs**

```elixir
# config/test.exs
import Config

# Suppress verbose logging during tests
config :logger, 
  level: :warning,
  compile_time_purge_matching: [
    [application: :jido, level_lower_than: :error]
  ]

# Test-specific configurations
config :foundation, :test_mode, true
```

---

## 🔧 IMPLEMENTATION STEPS

### Step 1: Immediate Test Silence
```bash
# Add to test/test_helper.exs
echo 'ExUnit.start(capture_log: true)' >> test/test_helper.exs
```

### Step 2: Run Tests (Should be silent)
```bash
mix test
```

### Step 3: Verify Only Test Results Show
Expected output:
```
Running ExUnit with seed: 123456, max_cases: 48
..................
Finished in 1.6 seconds (0.00s async, 1.6s sync)
18 tests, 0 failures
```

### Step 4: Enable Verbose Logging for Failures Only
```elixir
# For debugging specific tests:
test "some failing test" do
  assert capture_log(fn ->
    # Test code that might fail
  end) =~ "expected error message"
end
```

---

## 📊 LOGGING STRATEGIES COMPARISON

| Strategy | Pros | Cons | Use Case |
|----------|------|------|----------|
| `capture_log: true` | ✅ Simple, standard practice | ❌ Hides all logs, even failures | Most test suites |
| Logger level config | ✅ Granular control | ❌ Affects entire application | Specific log filtering |
| Custom backend | ✅ Maximum flexibility | ❌ Complex implementation | Advanced filtering needs |
| Process flags | ✅ Surgical precision | ❌ Requires wrapper code | Specific problematic processes |

---

## 🎯 RECOMMENDED APPROACH

### **For Foundation Jido System:**

1. **Primary**: Use `ExUnit.start(capture_log: true)` in `test_helper.exs`
2. **Secondary**: Configure logger level to `:warning` in `config/test.exs`  
3. **Tertiary**: Use `capture_log/1` for specific noisy tests

### **Implementation Priority:**
```elixir
# test/test_helper.exs (IMMEDIATE FIX)
ExUnit.start(capture_log: true)

# config/test.exs (ADDITIONAL CONTROL)
config :logger, level: :warning

# Individual tests (IF NEEDED)
capture_log(fn -> noisy_test_code() end)
```

---

## 🎖️ CANONICAL PATTERN

Most Elixir projects follow this pattern:

```elixir
# test/test_helper.exs
ExUnit.start(capture_log: true)

# config/test.exs
config :logger, level: :warning

# For debugging specific failures:
mix test --trace  # Shows detailed output including logs
```

This gives you:
- ✅ **Silent passing tests**
- ✅ **Visible failures with context**  
- ✅ **Debug capability when needed**
- ✅ **Standard Elixir community practice**

**Result**: Clean test output that only shows what matters - test results and actual failures.