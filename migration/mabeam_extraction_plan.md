# MABEAM Extraction Plan: Comprehensive Migration Strategy

## Executive Summary

This plan safely extracts MABEAM from `lib/foundation/` to top-level `lib/mabeam/` while maintaining full functionality and test coverage. The migration addresses critical circular dependencies and implements a clean pseudo-monorepo structure.

## Current State Analysis

### Critical Issues Identified
1. **Circular Dependency**: Foundation.Application directly supervises 8 MABEAM services (lines 135-198)
2. **Configuration Coupling**: Config references `Foundation.MABEAM.ProcessRegistry.Backend.LocalETS`
3. **Test Infrastructure**: MABEAM test helpers embedded in Foundation test support
4. **Namespace Conflicts**: Potential conflicts between Foundation and MABEAM modules

### Assets to Migrate
- **Source Files**: 17 modules in `lib/foundation/mabeam/`
- **Test Files**: 19 comprehensive test files with 332 passing tests
- **Configuration**: MABEAM-specific config in `config/config.exs`
- **Supervision**: 8 GenServer processes requiring supervision

## Migration Strategy: Safe Extraction with Integration Layer

### Phase 1: File Structure Migration
1. **Move Source Code**: `lib/foundation/mabeam/` → `lib/mabeam/`
2. **Move Tests**: `test/foundation/mabeam/` → `test/mabeam/`
3. **Update Namespaces**: `Foundation.MABEAM` → `MABEAM`
4. **Preserve Test Structure**: Maintain pseudo-monorepo test organization

### Phase 2: Dependency Resolution
1. **Break Circular Dependencies**: Update Foundation.Application to conditionally load MABEAM
2. **Configuration Migration**: Update config to reference new namespaces
3. **Integration Layer**: Create optional MABEAM integration for Foundation
4. **Test Infrastructure**: Extract MABEAM test helpers to appropriate location

### Phase 3: Supervision Architecture
1. **MABEAM Application**: Create `lib/mabeam/application.ex` for MABEAM supervision
2. **Foundation Integration**: Update Foundation.Application to optionally include MABEAM
3. **Service Discovery**: Ensure MABEAM services can discover Foundation services
4. **Graceful Degradation**: Foundation works with or without MABEAM

### Phase 4: Test Structure Enhancement
1. **Pseudo-Monorepo Support**: Organize tests by logical components
2. **Integration Tests**: Create cross-component integration test suite
3. **Test Helpers**: Properly distribute test utilities
4. **Coverage Maintenance**: Ensure all 332 tests continue passing

## Detailed Implementation Steps

### Step 1: Pre-Migration Validation
```bash
# Verify current test status
mix test
# Expected: 332 tests, 0 failures

# Backup current state
git add -A && git commit -m "Pre-MABEAM migration checkpoint"
```

### Step 2: File Movement and Namespace Updates
```bash
# Move source files
mv lib/foundation/mabeam lib/mabeam

# Move test files  
mkdir -p test/mabeam
mv test/foundation/mabeam/* test/mabeam/
rmdir test/foundation/mabeam

# Update all namespaces
find lib test -name "*.ex" -o -name "*.exs" | xargs sed -i 's/Foundation\.MABEAM/MABEAM/g'
```

### Step 3: Application Architecture Updates
```elixir
# lib/mabeam/application.ex (NEW)
defmodule MABEAM.Application do
  use Application
  
  def start(_type, _args) do
    children = [
      # All MABEAM services moved here
      {MABEAM.Core, name: :mabeam_core},
      {MABEAM.AgentRegistry, name: :mabeam_agent_registry},
      # ... other MABEAM services
    ]
    
    opts = [strategy: :one_for_one, name: MABEAM.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

# lib/foundation/application.ex (UPDATED)
defmodule Foundation.Application do
  # Remove MABEAM services from children list
  # Add conditional MABEAM integration if desired
end
```

### Step 4: Configuration Updates
```elixir
# config/config.exs
config :mabeam, [
  use_unified_registry: true,
  legacy_registry: [
    backend: MABEAM.ProcessRegistry.Backend.LocalETS,
    auto_start: false
  ]
]
```

### Step 5: Integration Layer (Optional)
```elixir
# lib/foundation/mabeam_integration.ex (NEW)
defmodule Foundation.MABEAMIntegration do
  @moduledoc """
  Optional integration layer for MABEAM services.
  Provides backward compatibility and service discovery.
  """
  
  def mabeam_available?, do: Code.ensure_loaded?(MABEAM.Core)
  
  def start_mabeam_services do
    if mabeam_available?() do
      MABEAM.Application.start(:normal, [])
    else
      {:error, :mabeam_not_available}
    end
  end
end
```

## Risk Mitigation

### Test Coverage Protection
- **Pre-migration**: Capture current test results
- **Post-migration**: Verify all tests still pass
- **Rollback Plan**: Git checkpoint before each major step

### Dependency Safety
- **Foundation Independence**: Ensure Foundation works without MABEAM
- **MABEAM Dependencies**: Maintain MABEAM's dependency on Foundation services
- **Service Discovery**: Use runtime checks for service availability

### Configuration Compatibility
- **Backward Compatibility**: Support old config structure during transition
- **Migration Warnings**: Log warnings for deprecated config
- **Documentation**: Clear upgrade path for users

## Validation Criteria

### Success Metrics
1. ✅ All 332 tests pass after migration
2. ✅ Foundation.Application starts successfully without MABEAM references
3. ✅ MABEAM services can be started independently
4. ✅ No circular dependencies between Foundation and MABEAM
5. ✅ Configuration properly references new namespaces
6. ✅ Test structure supports pseudo-monorepo pattern

### Post-Migration Verification
```bash
# Test compilation
mix compile

# Test suite execution  
mix test

# Dependency analysis
mix xref graph --format dot

# Module availability
iex -S mix -c "Code.ensure_loaded?(MABEAM.Core)"
```

## Rollback Strategy

If migration fails:
1. **Git Reset**: `git reset --hard HEAD~1` to checkpoint
2. **Dependency Check**: Verify all references restored
3. **Test Validation**: Ensure original test suite passes
4. **Issue Analysis**: Identify specific failure points

## Post-Migration Benefits

1. **Clean Architecture**: Clear separation of concerns
2. **Independent Development**: MABEAM can evolve independently
3. **Optional Integration**: Foundation users can choose MABEAM inclusion
4. **Better Testing**: Pseudo-monorepo structure supports better test organization
5. **Maintainability**: Reduced coupling improves long-term maintenance

## Timeline

- **Phase 1**: File Migration (30 minutes)
- **Phase 2**: Dependency Resolution (1 hour)
- **Phase 3**: Supervision Updates (45 minutes)  
- **Phase 4**: Test Structure (30 minutes)
- **Total**: ~2.5 hours with validation

## Next Steps

1. Execute the comprehensive migration script
2. Validate all tests pass
3. Update documentation to reflect new structure
4. Create integration examples for users
5. Plan for eventual MABEAM library extraction