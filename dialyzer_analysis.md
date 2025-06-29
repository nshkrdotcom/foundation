# Dialyzer Warning Analysis

## Summary of Issues

### 1. Callback Type Mismatches (High Priority)
- `mount/2` callback expects `%Jido.Agent{}` but receives `%Jido.Agent.Server.State{}`
- `shutdown/2` callback has same issue
- These affect TaskAgent, MonitorAgent, and CoordinatorAgent

### 2. Invalid Contract Warnings
- `do_validate/3` - spec doesn't match success typing
- `on_error/2` - spec expects `{:error, t()}` as possible return but implementation only returns `{:ok, t()}`
- `pending?/1` - spec expects boolean but returns non_neg_integer()
- `enqueue_instructions/2` - spec mismatch

### 3. Pattern Match Coverage
- FoundationAgent lines 239-241: case statement for `__MODULE__` can never match specific module names
- This is because `__MODULE__` is resolved at compile time in the macro context

### 4. Extra Range Warnings
- Action modules returning narrower types than their specs allow
- Sensor modules have similar issues

### 5. Unknown Type
- `Jido.Sensor.sensor_result/0` type not found

## Root Causes

1. **Macro Expansion Context**: The FoundationAgent macro expands in the using module's context, so `__MODULE__` refers to the wrong module
2. **Callback Argument Types**: Jido.Agent callbacks expect the agent struct, but server callbacks receive Server.State
3. **Return Type Strictness**: Some functions guarantee more specific returns than their specs indicate