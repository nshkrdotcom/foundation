# Dialyzer Error Fix Plan

## Overview
After analyzing the 97 dialyzer errors, they fall into several main categories:

1. **Type specification supertypes** - Specs too broad for actual return types
2. **Pattern match coverage** - Unreachable patterns due to type system understanding
3. **Callback type mismatches** - Implementation doesn't match behaviour expectations
4. **Contract violations** - Function specs don't match success typing
5. **Invalid contracts** - Extra types in specs or wrong return types

## Critical Issues Analysis

### Category 1: Service Integration Type Issues (High Priority)

**Files**: `lib/foundation/service_integration.ex`

**Issues**:
- `integration_status/0` and `validate_service_integration/0` have specs that are supertypes
- Functions can never return the broad `{:error, term()}` - they return specific error tuples

**Root Cause**: Exception handling patterns create specific error types, not generic terms.

**Fix Strategy**:
```elixir
# Current (too broad):
@spec integration_status() :: {:ok, map()} | {:error, term()}

# Should be (specific):
@spec integration_status() :: 
  {:ok, map()} | 
  {:error, {:integration_status_exception, Exception.t()}}
```

### Category 2: Jido Agent Callback Mismatches (Critical Priority)

**Files**: 
- `lib/jido_system/agents/foundation_agent.ex`
- `lib/jido_system/agents/coordinator_agent.ex`
- `lib/jido_system/agents/monitor_agent.ex` 
- `lib/jido_system/agents/task_agent.ex`

**Issues**:
- `on_error/2` callbacks return tuples instead of `Jido.Agent.t()`
- Pattern matching issues in `get_default_capabilities/0`
- Specs don't match actual return types

**Root Cause**: Foundation agents use different return patterns than pure Jido agents expect.

**Fix Strategy**:
1. Update callback implementations to return proper `Jido.Agent.t()` structs
2. Fix pattern matching to handle actual module types correctly
3. Remove unreachable error patterns

### Category 3: Sensor Signal Type Issues (Medium Priority)

**Files**:
- `lib/jido_system/sensors/agent_performance_sensor.ex`
- `lib/jido_system/sensors/system_health_sensor.ex`

**Issues**:
- `deliver_signal/1` returns wrapped signals instead of direct `Jido.Signal.t()`
- Signal dispatch calls with wrong argument types
- Mount/shutdown functions have extra error types that never occur

**Root Cause**: Sensor implementations wrap signals in additional tuples.

### Category 4: Bridge Pattern Matching (Low Priority)

**Files**: `lib/jido_foundation/bridge.ex`

**Issues**:
- Unreachable pattern `variable_other` in result handling

**Root Cause**: Previous patterns cover all possible types.

## Fix Implementation Plan

### Phase 1: Service Integration Fixes (30 minutes)

**Target**: Fix 2 errors in `service_integration.ex`

1. **Update `integration_status/0` spec**:
   ```elixir
   @spec integration_status() :: 
     {:ok, map()} | 
     {:error, {:integration_status_exception, Exception.t()}}
   ```

2. **Update `validate_service_integration/0` spec**:
   ```elixir
   @spec validate_service_integration() :: 
     {:ok, map()} | 
     {:error, {:contract_validation_failed, term()}} |
     {:error, {:validation_exception, Exception.t()}}
   ```

### Phase 2: Foundation Agent Callback Fixes (90 minutes)

**Target**: Fix 17+ errors across agent modules

1. **Fix `on_error/2` implementations** in all agent modules:
   - Ensure return type matches `{:ok | :error, Jido.Agent.t()}`
   - Update state handling to maintain agent struct

2. **Fix `get_default_capabilities/0` pattern matching**:
   - Replace `__MODULE__` pattern matching with actual module comparison
   - Remove unreachable catch-all pattern

3. **Update function specs** to match actual return types:
   - `do_validate/3`, `handle_signal/2`, `pending?/1`, `reset/1`, `transform_result/3`

### Phase 3: Sensor Implementation Fixes (60 minutes)

**Target**: Fix 18+ errors in sensor modules

1. **Fix `deliver_signal/1` implementations**:
   - Return `{:ok, Jido.Signal.t()}` directly, not wrapped tuples
   - Fix signal dispatch calls to use proper argument types

2. **Update mount/shutdown specs**:
   - Remove `{:error, _}` types that never occur
   - Match specs to actual success-only patterns

3. **Fix metadata function specs**:
   - Make specs more specific for `__sensor_metadata__/0` and `to_json/0`

### Phase 4: Bridge and System Cleanup (30 minutes)

**Target**: Fix remaining pattern matching issues

1. **Remove unreachable patterns** in:
   - `jido_foundation/bridge.ex`
   - `jido_system.ex`

2. **Fix process list handling** in system module

## Implementation Order and Testing

### Stage 1: Low-Risk Type Spec Updates
- Service integration specs
- Sensor metadata specs
- Bridge pattern cleanup

### Stage 2: Agent Callback Restructuring  
- Foundation agent base module fixes
- Individual agent implementations
- Pattern matching corrections

### Stage 3: Sensor Signal Flow Fixes
- Signal creation and delivery
- Dispatch call corrections
- Error handling alignment

### Stage 4: Integration Testing
- Run full test suite after each stage
- Verify dialyzer error count reduction
- Ensure no regressions in functionality

## Success Criteria

- **Zero dialyzer errors** - Target: 97 → 0
- **All tests passing** - Maintain current test coverage
- **No functionality regression** - All existing features work
- **Type safety improved** - More specific and accurate type specifications

## Risk Assessment

**Low Risk**: Type specification updates, unreachable pattern removal
**Medium Risk**: Sensor signal flow changes
**High Risk**: Agent callback restructuring (extensive interface changes)

## Estimated Timeline

- **Phase 1**: 30 minutes (2 fixes)
- **Phase 2**: 90 minutes (17+ fixes) 
- **Phase 3**: 60 minutes (18+ fixes)
- **Phase 4**: 30 minutes (remaining fixes)

**Total**: ~3.5 hours for complete dialyzer cleanup

## Dependencies

1. **Jido library updates** - Ensure all deps are on correct branches
2. **Test environment** - Full test suite must pass before starting
3. **Type documentation** - Update any affected API documentation

## Validation Plan

After each phase:
1. Run `mix dialyzer` to check error reduction
2. Run `mix test` to ensure no regressions  
3. Spot-check key functionality works
4. Commit working incremental fixes

Final validation:
- Zero dialyzer errors
- All 280+ tests passing
- Manual verification of agent and sensor behavior