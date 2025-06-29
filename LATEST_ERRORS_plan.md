# LATEST_ERRORS Implementation Plan

## Executive Summary

Based on comprehensive analysis of LATEST_ERRORS_cat.md, lib_old error handling implementations, and the fuse circuit breaker library, this plan provides a strategic approach to fixing the 20 test failures and establishing a robust error handling foundation.

**Priority Order**: Error Handler standardization → SystemHealthSensor fixes → Semantic issues → Circuit Breaker decision point

---

## Circuit Breaker Implementation Analysis

### **RECOMMENDATION: USE Fuse Library Directly**

After thorough analysis of the fuse Erlang library, the recommendation is to **USE** the fuse library directly rather than FORK or COPY/ADAPT.

#### **Why USE Fuse?**

1. **Battle-Tested**: 8+ years in production systems, extensive QuickCheck testing
2. **Performance**: 2.1M queries/second, sub-microsecond latency
3. **Robust Design**: 
   - Comprehensive EQC testing found and fixed subtle race conditions
   - Handles timer edge cases, administrative controls, and concurrent access
   - Built specifically for high-throughput Erlang/Elixir systems

4. **Complete Feature Set**:
   - Standard and fault injection fuses
   - Administrative disable/enable
   - Multiple monitoring backends (ETS, Prometheus, Folsom)
   - Proper alarm handling with hysteresis

5. **API Simplicity**:
   ```erlang
   % Install circuit breaker
   fuse:install(database_fuse, {{standard, 5, 10000}, {reset, 60000}}).
   
   % Use circuit breaker
   case fuse:ask(database_fuse, sync) of
     ok -> perform_operation();
     blown -> handle_circuit_open()
   end
   ```

#### **Integration Strategy**
- **Phase 1**: Replace Foundation.Infrastructure.CircuitBreaker with thin Elixir wrapper around fuse
- **Phase 2**: Integrate fuse telemetry with Foundation.Telemetry system
- **Phase 3**: Add Elixir-native configuration and supervision integration

---

## Error Handling Analysis

### **Current lib_old Implementation Assessment**

The lib_old error handling system shows **superior design patterns** compared to current Foundation implementation:

#### **lib_old Strengths**:
1. **Hierarchical Error Codes**: Structured `{category, subcategory, error_type}` system
2. **Rich Context**: ErrorContext with breadcrumbs, correlation IDs, operation tracking
3. **Recovery Strategies**: Built-in retry strategies and recovery action suggestions
4. **Telemetry Integration**: Automatic metrics collection and duration tracking

#### **Current Foundation Weaknesses**:
1. **Inconsistent Wrapping**: ErrorHandler sometimes wraps, sometimes propagates exceptions
2. **Poor Context**: Limited error context compared to lib_old capabilities
3. **No Recovery Strategy**: Missing retry and recovery guidance

### **RECOMMENDATION: Adopt lib_old Patterns with Modernization**

**Strategy**: Use lib_old error handling as foundation, modernize for current architecture.

---

## Implementation Plan

### **🔥 PHASE 1: Error Handler Standardization (Weeks 1-2)**

**Objective**: Replace inconsistent Foundation.ErrorHandler with standardized system based on lib_old patterns.

#### **1.1 Core Error Structure Implementation**
```elixir
# lib/foundation/error.ex - Based on lib_old/foundation/error.ex
defmodule Foundation.Error do
  @enforce_keys [:code, :error_type, :message, :severity]
  defstruct [
    :code,                    # Hierarchical error code (1101, 2401, etc.)
    :error_type,              # Specific error atom (:config_not_found, :timeout)
    :message,                 # Human readable message
    :severity,                # :low | :medium | :high | :critical
    :context,                 # Rich context map
    :correlation_id,          # Cross-system tracing
    :timestamp,               # Error occurrence time
    :stacktrace,              # Formatted stacktrace
    :category,                # :config | :system | :data | :external
    :subcategory,             # :structure | :validation | :access | :runtime
    :retry_strategy,          # :no_retry | :immediate | :fixed_delay | :exponential_backoff
    :recovery_actions         # List of suggested recovery steps
  ]

  # Error definitions with hierarchical codes
  @error_definitions %{
    {:config, :structure, :invalid_config_structure} => {1101, :high, "Configuration structure is invalid"},
    {:system, :runtime, :internal_error} => {2401, :critical, "Internal system error"},
    {:external, :timeout, :timeout} => {4301, :medium, "Operation timeout"},
    # ... (port from lib_old)
  }
end
```

#### **1.2 Error Context Implementation**
```elixir
# lib/foundation/error_context.ex - Based on lib_old/foundation/error_context.ex
defmodule Foundation.ErrorContext do
  defstruct [
    :operation_id,            # Unique operation identifier
    :module,                  # Module where operation started
    :function,                # Function where operation started
    :correlation_id,          # Cross-system correlation
    :start_time,              # Operation start timestamp
    :metadata,                # Additional context data
    :breadcrumbs,             # Operation trail
    :parent_context           # Nested context support
  ]

  def with_context(context, fun) do
    # Execute function with error context tracking
    # Automatic exception enhancement with context
  end

  def add_breadcrumb(context, module, function, metadata \\ %{}) do
    # Track operation flow for debugging
  end
end
```

#### **1.3 Standardized Error Handling Patterns**
- **Consistent Wrapping**: All Foundation functions return `{:ok, result}` or `{:error, %Foundation.Error{}}`
- **Exception Enhancement**: Raw exceptions automatically wrapped with context
- **Telemetry Integration**: Automatic error metrics collection
- **Recovery Guidance**: Built-in retry strategies and recovery actions

#### **1.4 Migration Strategy**
1. **Replace Foundation.ErrorHandler**: Direct replacement with new Foundation.Error
2. **Update All Foundation Modules**: Consistent error return patterns
3. **Test Migration**: Update failing Foundation tests to expect new error format
4. **Backward Compatibility**: Temporary shim for gradual migration

**Expected Impact**: Fixes **FAILURE 1** (Foundation Configuration Error Handling)

---

### **🔧 PHASE 2: SystemHealthSensor Fixes (Weeks 3-4)**

**Objective**: Fix the 15/20 test failures caused by SystemHealthSensor malfunction.

#### **2.1 Root Cause Analysis**
Current failures stem from:
1. **Rigid Data Assumptions**: `get_average_cpu_utilization/1` expects specific tuple format
2. **Signal Format Inconsistency**: Mixed `%Signal{}` vs `{:ok, %Signal{}}` patterns
3. **No Error Recovery**: Crashes on unexpected data instead of graceful degradation

#### **2.2 Robust Input Validation**
```elixir
# lib/jido_system/sensors/system_health_sensor.ex - Enhanced
defmodule JidoSystem.Sensors.SystemHealthSensor do
  def get_average_cpu_utilization(scheduler_data) do
    case validate_scheduler_data(scheduler_data) do
      {:ok, validated_data} ->
        average = calculate_average(validated_data)
        {:ok, average}
      
      {:error, reason} ->
        Logger.warning("Invalid scheduler data: #{inspect(reason)}")
        {:ok, 0.0}  # Graceful degradation
    end
  end

  defp validate_scheduler_data(data) when is_list(data) do
    case Enum.all?(data, &valid_scheduler_tuple?/1) do
      true -> {:ok, data}
      false -> {:error, :invalid_tuple_format}
    end
  end
  defp validate_scheduler_data(_), do: {:error, :not_list}

  defp valid_scheduler_tuple?({_scheduler_id, usage}) when is_number(usage), do: true
  defp valid_scheduler_tuple?(_), do: false
end
```

#### **2.3 Consistent Signal Handling**
```elixir
# Standardize signal wrapping patterns
defp emit_signal(data, type) do
  signal = %Jido.Signal{
    data: data,
    type: type,
    timestamp: DateTime.utc_now(),
    metadata: %{sensor: __MODULE__}
  }
  
  # Always return consistent format
  {:ok, signal}
end

defp handle_error(error) do
  error_signal = %Jido.Signal{
    data: %{error: error},
    type: :error,
    timestamp: DateTime.utc_now(),
    metadata: %{sensor: __MODULE__}
  }
  
  {:ok, error_signal}  # Consistent error signal format
end
```

#### **2.4 Defensive Programming Patterns**
- **Graceful Degradation**: Return safe defaults on invalid data
- **Comprehensive Logging**: Log issues without crashing
- **Error Signal Format**: Consistent error signal structure
- **Input Validation**: Validate all inputs before processing

**Expected Impact**: Fixes **FAILURES 6-20** (SystemHealthSensor - 75% of all failures)

---

### **⚡ PHASE 3: Semantic Issues Resolution (Week 5)**

**Objective**: Address remaining semantic issues and code quality problems.

#### **3.1 Jido Agent Registration Enhancement**
```elixir
# Fix agent registration to handle dead processes
defp register_agent_with_retry(agent_info, max_retries \\ 3) do
  case Foundation.register(agent_info.key, agent_info.pid, agent_info.metadata) do
    :ok -> :ok
    {:error, %Foundation.Error{error_type: :process_not_alive}} ->
      if max_retries > 0 do
        Process.sleep(100)  # Brief delay
        register_agent_with_retry(agent_info, max_retries - 1)
      else
        Logger.warning("Failed to register agent after retries: #{inspect(agent_info)}")
        {:error, :registration_failed}
      end
    error -> error
  end
end
```

#### **3.2 Telemetry Handler Optimization**
```elixir
# Convert anonymous functions to named module functions
defmodule Foundation.TelemetryHandlers do
  def handle_jido_events(event, measurements, metadata, config) do
    # Named function for better performance
    Logger.info("Jido event: #{inspect(event)}", 
      measurements: measurements, 
      metadata: metadata
    )
  end
end

# In tests, use named handler
:telemetry.attach("test-jido-events", 
  [:jido, :agent, :event], 
  &Foundation.TelemetryHandlers.handle_jido_events/4, 
  %{}
)
```

#### **3.3 Code Quality Fixes**
- **Remove Unused Variables**: Prefix with underscore or remove entirely
- **Fix Unreachable Clauses**: Correct pattern matching order
- **Update Test Expectations**: Align with new error formats

**Expected Impact**: Fixes remaining semantic issues, improves code quality

---

### **🚧 PHASE 4: Circuit Breaker Implementation Decision Point**

**At this point, pause for decision on circuit breaker strategy.**

#### **Option A: Use Fuse Library (RECOMMENDED)**
- **Pros**: Battle-tested, high performance, comprehensive features
- **Cons**: Erlang dependency, learning curve for team
- **Implementation**: 1-2 weeks for Elixir wrapper and integration

#### **Option B: Reimplement Based on Fuse**
- **Pros**: Pure Elixir, full control, integrated with Foundation
- **Cons**: 4-6 weeks development, need to reimplement battle-tested logic
- **Risk**: Subtle race conditions, timer handling edge cases

#### **Option C: Minimal Circuit Breaker**
- **Pros**: Quick implementation, minimal dependencies
- **Cons**: Limited features, potential production issues
- **Scope**: Basic state machine without advanced features

### **RECOMMENDATION: Option A (Use Fuse)**
The analysis strongly favors using the fuse library directly due to its proven reliability and comprehensive testing.

---

## Success Metrics

### **Phase 1 Success Criteria**
- [ ] All Foundation.ErrorHandler tests pass with new error format
- [ ] Foundation configuration error handling returns proper `{:error, %Foundation.Error{}}` tuples
- [ ] Error context tracking works across module boundaries
- [ ] **FAILURE 1** resolved

### **Phase 2 Success Criteria**
- [ ] All 15 SystemHealthSensor tests pass
- [ ] Sensor handles invalid data gracefully without crashes
- [ ] Consistent signal format across all sensor operations
- [ ] **FAILURES 6-20** resolved

### **Phase 3 Success Criteria**
- [ ] Agent registration handles dead processes gracefully
- [ ] Telemetry handlers use named functions
- [ ] All compiler warnings resolved
- [ ] Remaining semantic issues addressed

### **Overall Success Target**
- [ ] **20/20 test failures resolved**
- [ ] **Error handling standardized** across Foundation
- [ ] **Circuit breaker strategy decided** and implementation path clear
- [ ] **Code quality improved** with comprehensive error context

---

## Risk Assessment

### **High Risk Items**
1. **Error Format Migration**: Changing error formats may break dependent code
2. **SystemHealthSensor Refactor**: Critical monitoring component, must maintain functionality
3. **Circuit Breaker Integration**: Fuse library integration complexity

### **Mitigation Strategies**
1. **Gradual Migration**: Maintain backward compatibility during transition
2. **Comprehensive Testing**: Test each phase thoroughly before proceeding
3. **Documentation**: Document new error patterns and migration guide
4. **Rollback Plan**: Ability to revert changes if issues arise

### **Timeline Risk**
- **Conservative Estimate**: 6-8 weeks total
- **Optimistic Estimate**: 4-5 weeks total
- **Contingency**: Additional 2 weeks for unforeseen issues

---

## Conclusion

This plan provides a systematic approach to resolving the Foundation's structural issues while establishing robust error handling patterns. The decision to use the fuse library represents a strategic choice favoring proven reliability over custom implementation.

**Key Success Factors**:
1. **Standardized Error Handling**: Foundation.Error based on lib_old patterns
2. **Robust Sensor Design**: SystemHealthSensor with defensive programming
3. **Battle-Tested Circuit Breaker**: Fuse library integration
4. **Quality Code Patterns**: Comprehensive error context and recovery

**Next Action**: Begin Phase 1 (Error Handler Standardization) after plan approval.