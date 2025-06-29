# Function Specification Alignment Fixes

## 📋 Overview

This document outlines the identified misalignments between function specifications (`@spec`) and actual implementations in the Foundation codebase, along with detailed fix plans for each issue.

## 🎯 Objectives

1. **Ensure Dialyzer Compliance** - All function specifications must match actual implementations
2. **Improve Type Safety** - Consistent and accurate type annotations throughout codebase
3. **Standardize Error Handling** - Uniform error return patterns across modules
4. **Complete Specification Coverage** - All public functions have proper `@spec` annotations

## 🔥 CRITICAL FIXES (Immediate Action Required)

### 1. Foundation.ex - Count Function Return Type Mismatch

**File**: `lib/foundation.ex:286-290`  
**Issue**: `@spec` specifies `{:ok, non_neg_integer()}` but implementation returns raw protocol result

```elixir
# CURRENT (BROKEN):
@spec count(impl :: term() | nil) :: {:ok, non_neg_integer()}
def count(impl \\ nil) do
  actual_impl = impl || registry_impl()
  Foundation.Registry.count(actual_impl)  # Returns whatever protocol returns
end

# FIX OPTION 1 - Wrap result to match spec:
@spec count(impl :: term() | nil) :: {:ok, non_neg_integer()}
def count(impl \\ nil) do
  actual_impl = impl || registry_impl()
  case Foundation.Registry.count(actual_impl) do
    count when is_integer(count) and count >= 0 -> {:ok, count}
    {:ok, count} -> {:ok, count}
    {:error, reason} -> {:error, reason}
    other -> {:error, {:invalid_count_result, other}}
  end
end

# FIX OPTION 2 - Update spec to match implementation:
@spec count(impl :: term() | nil) :: non_neg_integer() | {:error, term()}
def count(impl \\ nil) do
  actual_impl = impl || registry_impl()
  Foundation.Registry.count(actual_impl)
end
```

**Recommendation**: Use Fix Option 1 to maintain API consistency with other Foundation functions that return `{:ok, result}` tuples.

### 2. Foundation.Infrastructure.CircuitBreaker - Protocol Implementation Mismatch

**File**: `lib/foundation/infrastructure/circuit_breaker.ex:348-360`  
**Issue**: Functions return `{:error, :not_implemented}` but protocol specs don't include this

```elixir
# CURRENT (INCOMPLETE):
@impl Foundation.Infrastructure
def setup_rate_limiter(_impl, _limiter_id, _config) do
  {:error, :not_implemented}  # Not in protocol spec
end

# FIX - Update protocol specs to include :not_implemented:
# In lib/foundation/protocols/infrastructure.ex:
@spec setup_rate_limiter(t(), limiter_id :: term(), config :: map()) ::
        :ok | {:error, term() | :not_implemented}

# And update all similar functions consistently
```

### 3. Foundation.Protocols.Infrastructure - Default Parameter in Protocol

**File**: `lib/foundation/protocols/infrastructure.ex:59`  
**Issue**: Protocol spec has default value for parameter, which is problematic in protocols

```elixir
# CURRENT (PROBLEMATIC):
@spec execute_protected(t(), service_id :: term(), function :: (-> any()), context :: map()) ::
        {:ok, result :: any()} | {:error, term()}
def execute_protected(impl, service_id, function, context \\ %{})

# FIX - Remove default from protocol, add wrapper function:
@spec execute_protected(t(), service_id :: term(), function :: (-> any()), context :: map()) ::
        {:ok, result :: any()} | {:error, term()}
def execute_protected(impl, service_id, function, context)

# Add convenience function with default:
@spec execute_protected(t(), service_id :: term(), function :: (-> any())) ::
        {:ok, result :: any()} | {:error, term()}
def execute_protected(impl, service_id, function) do
  execute_protected(impl, service_id, function, %{})
end
```

### 4. Undefined timeout() Type Usage

**Files**: Multiple files using `timeout()` type without definition  
**Issue**: Uses `timeout()` type but doesn't define it

```elixir
# CURRENT (UNDEFINED):
@spec start_consensus(t(), participants :: [term()], proposal :: term(), timeout()) ::
        {:ok, consensus_ref :: term()} | {:error, term()}

# FIX - Replace with standard Elixir timeout type:
@spec start_consensus(t(), participants :: [term()], proposal :: term(), timeout :: non_neg_integer() | :infinity) ::
        {:ok, consensus_ref :: term()} | {:error, term()}

# OR define the type globally in Foundation:
# In lib/foundation.ex:
@type timeout :: non_neg_integer() | :infinity
```

### 5. Foundation.ErrorContext - Conflicting Spec Overloads

**File**: `lib/foundation/error_context.ex:305-350`  
**Issue**: Multiple conflicting `@spec` definitions for same function

```elixir
# CURRENT (CONFLICTING):
@spec add_context(term(), t() | map(), map()) :: term()
@spec add_context(:ok, t() | map(), map()) :: :ok
@spec add_context({:ok, term()}, t() | map(), map()) :: {:ok, term()}

# FIX - Use single comprehensive spec with union types:
@spec add_context(
        result :: term(),
        context :: t() | map(),
        metadata :: map()
      ) :: term()
  when result: :ok | {:ok, term()} | {:error, term()} | term()
```

## ⚠️ MEDIUM PRIORITY FIXES

### 6. Missing @spec Annotations

**Files**: Various files missing specifications on public functions

#### JidoSystem.ex
```elixir
# ADD MISSING SPECS:
@spec list_agent_types() :: [module()]
def list_agent_types do
  # existing implementation
end

@spec list_sensor_types() :: [module()]  
def list_sensor_types do
  # existing implementation
end
```

#### Foundation.Services.RateLimiter.ex
```elixir
# ADD MISSING SPECS:
@spec trigger_cleanup() :: :ok
def trigger_cleanup do
  # existing implementation
end

@spec get_stats() :: map()
def get_stats do
  # existing implementation
end
```

### 7. Foundation.Registry Protocol - Inconsistent Return Types

**File**: `lib/foundation/protocols/registry.ex`  
**Issue**: `lookup/2` returns `:error` while others return `{:error, reason}`

```elixir
# CURRENT (INCONSISTENT):
@spec lookup(t(), key :: term()) ::
        {:ok, {pid(), map()}} | :error

# FIX - Standardize error format:
@spec lookup(t(), key :: term()) ::
        {:ok, {pid(), map()}} | {:error, :not_found}

# Update implementations accordingly
```

### 8. Foundation.AtomicTransaction - Complex Type Constraints

**File**: `lib/foundation/atomic_transaction.ex:64-71`  
**Issue**: Complex function specs that may not validate properly

```elixir
# CURRENT (COMPLEX):
@spec transact((t() -> t())) :: {:ok, any()} | {:error, any()}
@spec transact(pid() | nil, (t() -> t())) :: {:ok, any()} | {:error, any()}

# FIX - Simplify and clarify return types:
@spec transact(transaction_fun :: (t() -> t())) :: 
        {:ok, result :: any()} | {:error, reason :: term()}
@spec transact(pid() | nil, transaction_fun :: (t() -> t())) :: 
        {:ok, result :: any()} | {:error, reason :: term()}
```

## 📝 LOW PRIORITY FIXES

### 9. Foundation.Error - Type Name Inconsistency

**File**: `lib/foundation/error.ex`  
**Issue**: `@type error_code :: atom()` but field stores `pos_integer()`

```elixir
# CURRENT (CONFUSING):
@type error_code :: atom()
# But struct field:
code: pos_integer()

# FIX - Align type with usage:
@type error_code :: pos_integer()
# OR rename type:
@type error_status :: atom()
```

### 10. MABEAM.Discovery - Missing Error Cases

**File**: `lib/mabeam/discovery.ex`  
**Issue**: Some functions handle errors not documented in specs

```elixir
# ADD ERROR CASES TO SPECS:
@spec find_agents_by_capability(capability :: atom()) ::
        {:ok, [pid()]} | {:error, term()}  # Add | {:error, term()}
```

## 🛠️ IMPLEMENTATION PLAN

### Phase 1: Critical Fixes (Week 1)
1. **Fix Foundation.ex count function** - Wrap return value to match spec
2. **Update Infrastructure protocol specs** - Include `:not_implemented` in error types  
3. **Remove protocol defaults** - Add wrapper functions instead
4. **Define timeout type** - Add to Foundation module or use standard types
5. **Resolve ErrorContext spec conflicts** - Use union types

### Phase 2: Medium Priority (Week 2)  
1. **Add missing @spec annotations** - Complete public function coverage
2. **Standardize error return formats** - Consistent `{:error, reason}` patterns
3. **Simplify complex specs** - Make AtomicTransaction specs more precise
4. **Update Registry protocol** - Consistent error handling

### Phase 3: Low Priority (Week 3)
1. **Fix type name inconsistencies** - Align type names with usage
2. **Complete error case documentation** - All possible returns in specs
3. **Code review and validation** - Dialyzer analysis on all changes

## 🔧 TOOLING AND VALIDATION

### Dialyzer Integration
```bash
# Add to mix.exs:
def project do
  [
    # ... other config
    dialyzer: [
      plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
      plt_add_apps: [:mix, :ex_unit],
      flags: [:error_handling, :race_conditions, :underspecs, :unknown]
    ]
  ]
end

# Run validation:
mix dialyzer
```

### Spec Testing
```elixir
# Add to test_helper.exs:
ExUnit.configure(exclude: [skip: true], include: [spec_test: true])

# Create spec validation tests:
defmodule Foundation.SpecValidationTest do
  use ExUnit.Case, async: true
  
  @tag :spec_test
  test "all public functions have specs" do
    # Test implementation to verify @spec coverage
  end
end
```

## 📊 SUCCESS METRICS

### Completion Criteria
- [ ] All Critical fixes implemented and tested
- [ ] Dialyzer runs without spec-related errors
- [ ] 100% @spec coverage on public functions
- [ ] Consistent error return patterns across modules
- [ ] All tests passing with spec validation

### Quality Gates
1. **Zero Dialyzer Warnings** - Clean type checking
2. **Comprehensive Spec Coverage** - All public functions annotated  
3. **Consistent Error Handling** - Standardized return patterns
4. **Documentation Alignment** - Specs match actual behavior

## 🎯 DELIVERABLES

1. **Fixed Foundation.ex** - Proper count function return wrapping
2. **Updated Protocol Specs** - Complete error type coverage
3. **Comprehensive @spec Coverage** - All public functions annotated
4. **Dialyzer Configuration** - Integrated type checking in CI
5. **Validation Test Suite** - Automated spec compliance testing

---

**Status**: Ready for Implementation  
**Priority**: High - Required for production readiness  
**Timeline**: 3 weeks for complete implementation  
**Dependencies**: None - can start immediately