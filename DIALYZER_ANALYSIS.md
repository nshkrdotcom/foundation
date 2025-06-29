# Dialyzer Error Analysis and Fix Plan

## Error Categories

### 1. **Critical: Undefined Functions** (MUST FIX)
These cause runtime failures in production:

#### Foundation Module Issues:
- `Foundation.start_link/0` - Foundation module has no supervision/start_link
- `Foundation.Registry.select/2` - Not in protocol 
- `Foundation.Registry.keys/2` - Not in protocol

#### Missing Module:
- `:scheduler.utilization/1` - Requires `:runtime_tools` in applications

### 2. **High Priority: Type Contract Violations**
These indicate logic errors:

#### Return Type Mismatches:
- `deliver_signal/1` returns `{:ok, term(), term()}` but code expects `{:error, reason}`
- `JidoFoundation.Bridge.delegate_task/3` returns `:ok | {:error, :delegation_failed}` but code expects `{:ok, result}`

### 3. **Medium Priority: Deprecated Functions**
- `Logger.warn/1` → `Logger.warning/2` (many occurrences)
- Single-quoted strings → ~c"" sigil

### 4. **Low Priority: Unused Variables/Aliases**
- Various unused variables (prefix with _)
- Unused aliases (remove)

## Implementation Plan

### Phase 1: Fix Critical Infrastructure (30 mins)

#### 1.1 Add Foundation.start_link/0
```elixir
# In lib/foundation.ex
def start_link(opts \\ []) do
  # Start any Foundation-wide services if needed
  {:ok, self()}
end
```

#### 1.2 Add Registry Protocol Functions
```elixir
# In lib/foundation/protocols/registry.ex
@callback select(impl :: t(), match_spec :: list()) :: list()
@callback keys(impl :: t(), pid :: pid()) :: list()
```

#### 1.3 Add :runtime_tools
```elixir
# In mix.exs application function
extra_applications: [:logger, :crypto, :fuse, :runtime_tools]
```

### Phase 2: Fix Type Violations (20 mins)

#### 2.1 Fix deliver_signal return type
- Find where deliver_signal is defined
- Either fix the function to return error tuples OR fix the callers

#### 2.2 Fix Bridge.delegate_task expectations
- Update callers to handle the actual return type
- OR update Bridge to return `{:ok, result}` format

### Phase 3: Fix Deprecations (10 mins)
- Global replace Logger.warn → Logger.warning
- Fix charlist syntax

### Phase 4: Clean up warnings (5 mins)
- Prefix unused variables with _
- Remove unused aliases

## Expected Outcome
- 0 Dialyzer errors
- Clean compilation (only informational warnings)
- All tests still passing