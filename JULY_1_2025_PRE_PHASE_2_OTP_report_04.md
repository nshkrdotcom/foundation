# OTP Refactor Plan - Document 04: Error Handling & System Architecture
Generated: July 1, 2025

## Executive Summary

This document unifies the fragmented error handling systems and establishes consistent architectural patterns across the codebase. We'll create a single, coherent approach to errors, remove competing systems, and ensure proper fault isolation.

**Time Estimate**: 5-7 days
**Risk**: Medium - touches error paths throughout system
**Impact**: Consistent error handling, better debugging, proper fault isolation

## Context & Required Reading

1. `JULY_1_2025_PRE_PHASE_2_OTP_report_gem_02a.md` - CRITICAL FLAW #9 on competing error systems
2. Review current error modules:
   - `lib/foundation/error.ex` (desired end state)
   - `lib/foundation/error_handling.ex` (to be refactored)
   - `lib/foundation/error_context.ex` (to be integrated)

## The Core Problems

1. **Three competing error systems** that don't compose
2. **Context loss** at system boundaries
3. **Overly broad exception handling** that prevents "let it crash"
4. **Inconsistent error propagation** making recovery impossible

## Stage 4.1: Unify Error Systems (Days 1-2)

### Current State Analysis

```elixir
# System 1: Rich structured errors (GOOD - keep this)
%Foundation.Error{
  code: :validation_failed,
  message: "Invalid input",
  details: %{field: :email},
  category: :validation,
  severity: :error,
  timestamp: ~U[2025-01-01 00:00:00Z],
  context: %{operation_id: "123", correlation_id: "abc"}
}

# System 2: Simple tuples (REFACTOR to System 1)
{:error, :timeout}
{:error, "connection failed"}

# System 3: Process dict context (INTEGRATE into System 1)
ErrorContext.with_context(%{operation: "user_signup"}, fn ->
  # Adds breadcrumbs but only for exceptions
end)
```

### Step 1: Enhance Foundation.Error

**File**: `lib/foundation/error.ex`

```elixir
defmodule Foundation.Error do
  @moduledoc """
  Unified error system for the Foundation platform.
  ALL errors must use this structure.
  """
  
  defstruct [
    :code,          # Atom - machine readable
    :message,       # String - human readable
    :details,       # Map - additional data
    :category,      # Atom - :validation, :infrastructure, :business, :system
    :severity,      # Atom - :error, :critical, :warning
    :timestamp,     # DateTime
    :context,       # Map - operation context
    :stacktrace,    # List - if from exception
    :original       # Original error if wrapped
  ]
  
  @type t :: %__MODULE__{
    code: atom(),
    message: String.t(),
    details: map(),
    category: error_category(),
    severity: error_severity(),
    timestamp: DateTime.t(),
    context: map(),
    stacktrace: list() | nil,
    original: term() | nil
  }
  
  @type error_category :: :validation | :infrastructure | :business | :system
  @type error_severity :: :warning | :error | :critical
  
  # Constructors for common cases
  
  def validation_error(message, details \\ %{}) do
    new(:validation_failed, message, details, :validation)
  end
  
  def infrastructure_error(code, message, details \\ %{}) do
    new(code, message, details, :infrastructure)
  end
  
  def business_error(code, message, details \\ %{}) do
    new(code, message, details, :business)
  end
  
  def system_error(code, message, details \\ %{}) do
    new(code, message, details, :system, :critical)
  end
  
  # Main constructor
  def new(code, message, details \\ %{}, category \\ :system, severity \\ :error) do
    %__MODULE__{
      code: code,
      message: message,
      details: details,
      category: category,
      severity: severity,
      timestamp: DateTime.utc_now(),
      context: get_current_context()
    }
  end
  
  # Convert any error to Foundation.Error
  def normalize(error, context \\ %{})
  
  def normalize(%__MODULE__{} = error, context) do
    %{error | context: Map.merge(error.context, context)}
  end
  
  def normalize({:error, %__MODULE__{} = error}, context) do
    normalize(error, context)
  end
  
  def normalize({:error, reason}, context) when is_atom(reason) do
    # Convert simple error atoms
    code = reason
    message = reason |> to_string() |> String.replace("_", " ") |> String.capitalize()
    
    new(code, message, %{}, categorize_error(reason))
    |> Map.put(:context, Map.merge(get_current_context(), context))
  end
  
  def normalize({:error, message}, context) when is_binary(message) do
    new(:generic_error, message, %{}, :system)
    |> Map.put(:context, Map.merge(get_current_context(), context))
  end
  
  def normalize(%{__exception__: true} = exception, context) do
    %__MODULE__{
      code: error_code_from_exception(exception),
      message: Exception.message(exception),
      details: exception_details(exception),
      category: categorize_exception(exception),
      severity: :error,
      timestamp: DateTime.utc_now(),
      context: Map.merge(get_current_context(), context),
      stacktrace: Process.info(self(), :current_stacktrace),
      original: exception
    }
  end
  
  def normalize(other, context) do
    new(:unknown_error, inspect(other), %{original: other}, :system)
    |> Map.put(:context, Map.merge(get_current_context(), context))
  end
  
  # Context management (replaces ErrorContext)
  
  def with_context(context, fun) when is_map(context) and is_function(fun, 0) do
    old_context = Process.get(:foundation_error_context, %{})
    merged_context = Map.merge(old_context, context)
    
    Process.put(:foundation_error_context, merged_context)
    
    try do
      case fun.() do
        {:error, error} -> {:error, normalize(error)}
        {:ok, _} = ok -> ok
        other -> other
      end
    rescue
      exception ->
        error = normalize(exception)
        {:error, error}
    after
      Process.put(:foundation_error_context, old_context)
    end
  end
  
  defp get_current_context do
    Process.get(:foundation_error_context, %{})
  end
  
  # Helpers
  
  defp categorize_error(reason) do
    cond do
      reason in [:timeout, :noproc, :noconnection] -> :infrastructure
      reason in [:invalid, :not_found, :unauthorized] -> :validation
      reason in [:insufficient_funds, :limit_exceeded] -> :business
      true -> :system
    end
  end
  
  defp categorize_exception(exception) do
    cond do
      match?(%DBConnection.ConnectionError{}, exception) -> :infrastructure
      match?(%Jason.DecodeError{}, exception) -> :validation
      match?(%ArgumentError{}, exception) -> :validation
      true -> :system
    end
  end
  
  defp error_code_from_exception(exception) do
    exception.__struct__
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> String.to_atom()
  end
  
  defp exception_details(exception) do
    exception
    |> Map.from_struct()
    |> Map.drop([:__struct__, :__exception__])
  end
end
```

### Step 2: Create Error Boundary Module

**File**: `lib/foundation/error_boundary.ex`

```elixir
defmodule Foundation.ErrorBoundary do
  @moduledoc """
  Provides error boundaries for different types of operations.
  Only catches EXPECTED errors, lets unexpected ones crash.
  """
  
  alias Foundation.Error
  
  @doc """
  Boundary for network operations - catches network errors only.
  """
  def with_network_error_handling(fun) do
    try do
      fun.()
    rescue
      error in [Mint.HTTPError, Finch.Error, :hackney_error] ->
        {:error, Error.infrastructure_error(:network_error, Exception.message(error))}
    end
  end
  
  @doc """
  Boundary for database operations - catches DB errors only.
  """
  def with_database_error_handling(fun) do
    try do
      fun.()
    rescue
      error in [DBConnection.ConnectionError, Postgrex.Error] ->
        {:error, Error.infrastructure_error(:database_error, Exception.message(error))}
    end
  end
  
  @doc """
  Boundary for JSON operations - catches parsing errors only.
  """
  def with_json_error_handling(fun) do
    try do
      fun.()
    rescue
      error in [Jason.DecodeError, Jason.EncodeError] ->
        {:error, Error.validation_error("Invalid JSON", %{error: Exception.message(error)})}
    end
  end
  
  @doc """
  For operations that should NEVER fail. Use sparingly!
  """
  def protect_critical_path(fun, fallback_result) do
    try do
      fun.()
    rescue
      exception ->
        # Log but don't crash critical paths like telemetry
        Logger.error("Critical path error: #{Exception.format(:error, exception)}")
        fallback_result
    end
  end
  
  @doc """
  NEVER USE THIS! Here as an example of what NOT to do.
  """
  @deprecated "Use specific error boundaries instead"
  def catch_all(fun) do
    # This is what we're REMOVING from the codebase
    raise "Do not use catch-all error handling!"
  end
end
```

### Step 3: Refactor ErrorHandling Module

**File**: `lib/foundation/error_handling.ex`

```elixir
defmodule Foundation.ErrorHandling do
  @moduledoc """
  Helper functions for working with Foundation.Error.
  This module is now a thin wrapper that ensures all errors are Foundation.Error structs.
  """
  
  alias Foundation.Error
  
  # Ensure all errors are Foundation.Error
  def handle_error({:error, %Error{}} = error), do: error
  def handle_error({:error, other}), do: {:error, Error.normalize(other)}
  def handle_error(error), do: {:error, Error.normalize(error)}
  
  # Logging with proper error structure
  def log_error({:error, %Error{} = error}, level \\ :error) do
    Logger.log(level, """
    Error: #{error.code} - #{error.message}
    Category: #{error.category}
    Severity: #{error.severity}
    Details: #{inspect(error.details)}
    Context: #{inspect(error.context)}
    """)
    
    {:error, error}
  end
  
  def log_error(other, level \\ :error) do
    handle_error(other) |> log_error(level)
  end
  
  # Chain operations with error handling
  def with_error_handling(operations) when is_list(operations) do
    Enum.reduce_while(operations, {:ok, %{}}, fn operation, {:ok, acc} ->
      case operation.(acc) do
        {:ok, result} -> {:cont, {:ok, result}}
        {:error, _} = error -> {:halt, handle_error(error)}
      end
    end)
  end
  
  # Telemetry emission for errors
  def emit_error_telemetry(%Error{} = error, metadata \\ %{}) do
    :telemetry.execute(
      [:foundation, :error],
      %{count: 1},
      Map.merge(metadata, %{
        code: error.code,
        category: error.category,
        severity: error.severity
      })
    )
  end
end
```

## Stage 4.2: Remove Dangerous Error Handling (Day 3)

### Find and Fix Overly Broad Try/Catch

**Script**: `scripts/find_dangerous_error_handling.exs`

```elixir
defmodule DangerousErrorHandlingFinder do
  @dangerous_patterns [
    # Catches all exceptions
    ~r/rescue\s*\n\s*\w+\s*->/,
    ~r/rescue\s+exception\s*->/,
    ~r/catch\s*\n\s*.*->/,
    # Generic error handling
    ~r/rescue\s+_\s*->/,
    ~r/catch\s+_.*->/
  ]
  
  def scan do
    Path.wildcard("lib/**/*.ex")
    |> Enum.flat_map(&scan_file/1)
    |> Enum.group_by(& &1.severity)
  end
  
  defp scan_file(path) do
    content = File.read!(path)
    lines = String.split(content, "\n")
    
    Enum.with_index(lines, 1)
    |> Enum.flat_map(fn {line, line_no} ->
      Enum.flat_map(@dangerous_patterns, fn pattern ->
        if Regex.match?(pattern, line) do
          [{path, line_no, line, severity_for(line)}]
        else
          []
        end
      end)
    end)
  end
  
  defp severity_for(line) do
    cond do
      String.contains?(line, "catch") -> :critical
      String.contains?(line, "rescue _") -> :high
      true -> :medium
    end
  end
end
```

### Example Fixes

#### Fix 1: ProcessTask Action

**File**: `lib/jido_system/actions/process_task.ex`

**BEFORE** (Dangerous):
```elixir
def run(params, context) do
  try do
    # Complex logic
    process_task_logic(params, context)
  rescue
    e -> 
      # BAD: Catches EVERYTHING including bugs
      Logger.error("Task processing failed: #{inspect(e)}")
      {:error, :processing_failed}
  end
end
```

**AFTER** (Correct):
```elixir
def run(params, context) do
  # Validate first - let validation errors bubble up
  with :ok <- validate_task_params(params),
       {:ok, task} <- prepare_task(params, context) do
    
    # Only catch EXPECTED infrastructure errors
    Foundation.ErrorBoundary.with_network_error_handling(fn ->
      process_task_with_external_service(task)
    end)
  end
end

# Let unexpected errors crash the process!
# The supervisor will restart it in a clean state
```

#### Fix 2: Safe Execute Removal

**File**: `lib/foundation/error_handler.ex`

**DELETE ENTIRELY** and replace usages with specific error boundaries:

```elixir
# BEFORE (using safe_execute)
safe_execute(fn ->
  complex_operation()
end)

# AFTER (using specific boundary)
Foundation.ErrorBoundary.with_network_error_handling(fn ->
  complex_operation()
end)

# OR just let it run (preferred for internal operations)
complex_operation()
```

## Stage 4.3: Process Isolation & Fault Tolerance (Days 4-5)

### Problem: Large GenServers Doing Too Much

When a GenServer does too much, a failure in one operation affects all operations.

### Pattern: Operation Isolation

```elixir
defmodule Foundation.OperationIsolation do
  @moduledoc """
  Patterns for isolating operations that might fail.
  """
  
  @doc """
  Runs operation in a separate, monitored process.
  Returns {:ok, result} or {:error, reason}.
  """
  def isolate(fun, timeout \\ 5000) do
    task = Task.Supervisor.async_nolink(
      Foundation.TaskSupervisor,
      fun
    )
    
    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} -> 
        result
        
      {:exit, reason} -> 
        {:error, Error.system_error(:isolated_operation_failed, 
          "Operation crashed: #{inspect(reason)}")}
        
      nil -> 
        {:error, Error.infrastructure_error(:timeout, 
          "Operation timed out after #{timeout}ms")}
    end
  end
  
  @doc """
  Runs operation with a circuit breaker for repeated failures.
  """
  def with_circuit_breaker(operation_name, fun) do
    case Foundation.Services.CircuitBreaker.call(operation_name, fun) do
      {:ok, result} -> 
        {:ok, result}
        
      {:error, :circuit_open} ->
        {:error, Error.infrastructure_error(:circuit_open,
          "Circuit breaker is open for #{operation_name}")}
          
      {:error, other} ->
        {:error, Error.normalize(other)}
    end
  end
end
```

### Apply to High-Risk Operations

```elixir
defmodule JidoSystem.Agents.TaskAgent do
  # Isolate external API calls
  def process_external_task(task) do
    Foundation.OperationIsolation.isolate(fn ->
      # This runs in a separate process
      # If it crashes, TaskAgent continues running
      ExternalAPI.process(task)
    end)
  end
  
  # Use circuit breaker for flaky services
  def submit_to_worker(task) do
    Foundation.OperationIsolation.with_circuit_breaker(
      "worker_submission",
      fn -> WorkerService.submit(task) end
    )
  end
end
```

## Stage 4.4: Implement Error Recovery Strategies (Days 6-7)

### Pattern 1: Exponential Backoff Retry

```elixir
defmodule Foundation.RetryStrategy do
  alias Foundation.Error
  
  @doc """
  Retries operation with exponential backoff.
  Only retries infrastructure errors, not business logic errors.
  """
  def with_retry(fun, opts \\ []) do
    max_attempts = Keyword.get(opts, :max_attempts, 3)
    base_delay = Keyword.get(opts, :base_delay, 100)
    max_delay = Keyword.get(opts, :max_delay, 5000)
    
    do_retry(fun, 1, max_attempts, base_delay, max_delay)
  end
  
  defp do_retry(fun, attempt, max_attempts, base_delay, max_delay) do
    case fun.() do
      {:ok, _} = success -> 
        success
        
      {:error, %Error{category: :infrastructure} = error} 
      when attempt < max_attempts ->
        delay = min(base_delay * :math.pow(2, attempt - 1), max_delay)
        |> round()
        
        Logger.info("Retrying after #{delay}ms (attempt #{attempt}/#{max_attempts})")
        Process.sleep(delay)
        
        do_retry(fun, attempt + 1, max_attempts, base_delay, max_delay)
        
      {:error, _} = error ->
        # Don't retry business errors or after max attempts
        error
    end
  end
end
```

### Pattern 2: Graceful Degradation

```elixir
defmodule JidoSystem.GracefulDegradation do
  @doc """
  Provides fallback behavior when services are unavailable.
  """
  def with_fallback(primary_fun, fallback_fun) do
    case primary_fun.() do
      {:ok, _} = success -> 
        success
        
      {:error, %Error{category: :infrastructure}} ->
        Logger.warning("Primary operation failed, using fallback")
        fallback_fun.()
        
      {:error, _} = error ->
        # Don't fallback for business logic errors
        error
    end
  end
  
  @doc """
  Cache-aside pattern for resilience.
  """
  def with_cache(cache_key, ttl, fun) do
    case Foundation.Cache.get(cache_key) do
      {:ok, cached_value} ->
        {:ok, cached_value}
        
      :miss ->
        case fun.() do
          {:ok, value} = success ->
            Foundation.Cache.put(cache_key, value, ttl)
            success
            
          error ->
            # Check if we have a stale cached value
            case Foundation.Cache.get(cache_key, include_expired: true) do
              {:ok, stale_value} ->
                Logger.warning("Using stale cache due to error")
                {:ok, stale_value}
                
              :miss ->
                error
            end
        end
    end
  end
end
```

## Stage 4.5: Error Monitoring & Alerting

### Create Error Tracking

```elixir
defmodule Foundation.ErrorTracker do
  use GenServer
  
  @circuit_breaker_threshold 10
  @time_window :timer.minutes(5)
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def track_error(%Error{} = error) do
    GenServer.cast(__MODULE__, {:track_error, error})
  end
  
  def init(_opts) do
    :ets.new(:error_counts, [:named_table, :public, :set])
    schedule_cleanup()
    {:ok, %{}}
  end
  
  def handle_cast({:track_error, error}, state) do
    key = {error.code, error.category}
    timestamp = System.system_time(:millisecond)
    
    # Increment counter
    count = :ets.update_counter(:error_counts, key, {2, 1}, {key, 0})
    
    # Check if we should alert
    if count >= @circuit_breaker_threshold do
      emit_alert(error, count)
    end
    
    # Track for metrics
    :telemetry.execute(
      [:foundation, :error, :tracked],
      %{count: 1},
      %{
        code: error.code,
        category: error.category,
        severity: error.severity
      }
    )
    
    {:noreply, state}
  end
  
  defp emit_alert(error, count) do
    Logger.error("""
    ERROR THRESHOLD EXCEEDED
    Error: #{error.code}
    Category: #{error.category}
    Count: #{count} in #{@time_window}ms
    
    Recent context: #{inspect(error.context)}
    """)
    
    # Could also send to external monitoring
    # Sentry.capture_message("Error threshold exceeded", ...)
  end
end
```

## Success Metrics

1. **Single Error Type**: 100% of errors use Foundation.Error
2. **No Catch-All**: Zero instances of broad exception handling
3. **Proper Boundaries**: All external calls use error boundaries
4. **Context Preserved**: Error context available in logs/monitoring
5. **Let It Crash**: Unexpected errors cause process restart

## Integration Checklist

- [ ] All {:error, reason} converted to {:error, %Foundation.Error{}}
- [ ] ErrorContext functionality merged into Foundation.Error
- [ ] All safe_execute removed
- [ ] Error boundaries for all external services
- [ ] Retry strategies for infrastructure errors only
- [ ] Error tracking and alerting active
- [ ] CI checks for dangerous patterns

## Summary

Stage 4 establishes consistent error handling by:
1. Unifying three systems into one Foundation.Error
2. Removing dangerous catch-all error handling
3. Creating specific error boundaries for expected failures
4. Implementing proper retry and fallback strategies
5. Adding error tracking and monitoring

This creates a system where:
- **Expected errors** are handled gracefully
- **Unexpected errors** crash the process (let it crash!)
- **All errors** have consistent structure and context
- **Recovery strategies** are appropriate to error types

**Next Document**: `JULY_1_2025_PRE_PHASE_2_OTP_report_05.md` will cover the final integration, migration strategy, and production readiness checklist.