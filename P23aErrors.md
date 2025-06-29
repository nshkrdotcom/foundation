# Phase 2.3a Error Analysis and Fixes

## Summary
After Phase 2.3a implementation, we have 29 test failures that need systematic fixing.

## Error Categories

### 1. High Priority - Critical Function Errors

#### A. FunctionClauseError in Bridge.emit_signal/2
**Pattern**: `FunctionClauseError in Keyword.get/3`
**Root Cause**: Bridge.emit_signal/2 expects signal parameter to be a keyword list but receives a map/struct
**Files Affected**: 
- lib/jido_foundation/bridge.ex:550
- Multiple test files using emit_signal

**Error Example**:
```
** (FunctionClauseError) no function clause matching in Keyword.get/3
The following arguments were given to Keyword.get/3:
  # 1: %{data: %{result: "success", task_id: "task_1"}, id: -576460752303423100, type: "task.completed", time: ~U[2025-06-29 14:42:44.841693Z], source: "agent://#PID<0.1172.0>"}
  # 2: :bus
  # 3: :foundation_signal_bus
```

#### B. CaseClauseError in MABEAM.Coordination functions  
**Pattern**: `CaseClauseError: no case clause matching`
**Root Cause**: Coordination functions receive agent registry data but missing case clauses for different data structures
**Files Affected**:
- lib/mabeam/coordination.ex (multiple functions)
- Test file: test/mabeam/coordination_test.exs

**Error Example**:
```
** (CaseClauseError) no case clause matching: [{"inf_agent_1", :pid1, %{node: :node1, resources: %{...}, capability: :inference, health_status: :healthy}}]
```

### 2. Medium Priority - Code Quality Issues

#### C. Unused Variable Warnings in TaskAgent
**Files**: lib/jido_system/agents/task_agent.ex:264,255
**Variables**: `process_instruction`, `validate_instruction`

### 3. Low Priority - Test Code Warnings  
**Pattern**: Unused variables in test setup/helper functions
**Files**: Multiple test files with unused registry, agent, measurements variables

## Fix Plan

1. **Fix Bridge.emit_signal parameter handling** - Convert signal to proper format
2. **Add missing case clauses in MABEAM.Coordination** - Handle different agent registry structures  
3. **Fix unused variables in TaskAgent** - Use variables or prefix with underscore
4. **Clean up test warnings** - Prefix unused variables with underscore

## Expected Outcome
All 330 tests passing with 0 failures, 0 warnings.