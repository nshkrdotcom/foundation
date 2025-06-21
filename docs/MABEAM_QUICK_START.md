# MABEAM Quick Start Guide

## Getting Started with MABEAM Implementation

This guide provides a quick overview of implementing MABEAM (Multi-Agent BEAM) in Foundation using the TDD approach outlined in the phase documents.

## Prerequisites

- Elixir 1.14+
- Existing Foundation codebase
- Understanding of OTP principles
- Familiarity with TDD practices

## Implementation Order

Follow this exact order to ensure dependencies are met:

1. **Phase 1**: Core Infrastructure (`MABEAM_PHASE_01_CORE.md`)
2. **Phase 2**: Agent Registry (`MABEAM_PHASE_02_AGENT_REGISTRY.md`)
3. **Phase 3**: Basic Coordination (`MABEAM_PHASE_03_COORDINATION.md`)
4. **Phase 4**: Advanced Coordination (`MABEAM_PHASE_04_ADVANCED_COORD.md`)
5. **Phase 5**: Telemetry (`MABEAM_PHASE_05_TELEMETRY.md`)
6. **Phase 6**: Integration (`MABEAM_PHASE_06_INTEGRATION.md`)

## Quality Gates Command Sequence

Before each human review checkpoint, run these commands in order:

```bash
# 1. Format all code
mix format

# 2. Compile with warnings as errors
mix compile --warnings-as-errors

# 3. Run dialyzer for type checking
mix dialyzer

# 4. Run strict credo analysis
mix credo --strict

# 5. Run all tests
mix test

# 6. Check test coverage
mix test --cover
```

All commands must pass before proceeding to the next step.

## Starting Phase 1

1. **Read the Phase 1 document**: `foundation/docs/MABEAM_PHASE_01_CORE.md`
2. **Start with Step 1.1**: Type Definitions and Specifications
3. **Follow TDD cycle**: Red → Green → Refactor
4. **Run quality gates**: Ensure all checks pass
5. **Human review**: Review and commit stable increment

## File Creation Order

Create files in this order to maintain dependencies:

### Phase 1 Files
```
lib/foundation/mabeam/types.ex              # First - type definitions
test/foundation/mabeam/types_test.exs       # Test for types
lib/foundation/mabeam/core.ex               # Core orchestrator
test/foundation/mabeam/core_test.exs        # Core tests
```

### Phase 2 Files
```
lib/foundation/mabeam/agent_registry.ex     # Agent registry
test/foundation/mabeam/agent_registry_test.exs  # Registry tests
```

### Phase 3 Files
```
lib/foundation/mabeam/coordination.ex       # Basic coordination
test/foundation/mabeam/coordination_test.exs    # Coordination tests
```

## Key TDD Principles

1. **Write failing tests first** (Red)
2. **Write minimal code to pass** (Green)
3. **Refactor for quality** (Refactor)
4. **Maintain quality gates** at each step
5. **Stop for human review** at each checkpoint

## Common Pitfalls to Avoid

- ❌ Skipping quality gates
- ❌ Writing implementation before tests
- ❌ Proceeding with dialyzer warnings
- ❌ Ignoring credo violations
- ❌ Moving to next phase without completing current phase
- ❌ Not following the TDD cycle

## Success Indicators

✅ All quality gates pass consistently
✅ Test coverage remains >95%
✅ Each step builds incrementally
✅ Human reviews result in stable commits
✅ Integration between phases works seamlessly

## Getting Help

- Review the main implementation plan: `MABEAM_TDD_IMPLEMENTATION.md`
- Check specific phase documentation for detailed guidance
- Ensure all prerequisites are met before starting each phase
- Follow the TDD cycle religiously

## Next Steps

1. Start with Phase 1, Step 1.1
2. Create the types module and tests
3. Run quality gates
4. Proceed incrementally through each step
5. Complete human review at each checkpoint

Remember: **Stability before progress**. Each step must be rock-solid before moving forward. 