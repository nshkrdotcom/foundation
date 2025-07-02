# OTP Cleanup Implementation Prompts
Generated: July 2, 2025

This file contains isolated, self-contained prompts for implementing the Process dictionary cleanup plan. Each prompt includes full context and can be executed independently.

---

## PROMPT 1: Create Process Dictionary Enforcement Infrastructure

**Context**: You are implementing Phase 1 of the OTP cleanup plan to add enforcement mechanisms for Process dictionary usage.

**Required Reading**:
1. Read `JULY_1_2025_OTP_CLEANUP_2121.md` - Complete plan overview
2. Read `JULY_1_2025_PRE_PHASE_2_OTP_report_01.md` - Sections on banned primitives
3. Read current `.credo.exs` file to understand existing structure
4. Read `.github/workflows/elixir.yml` to understand CI structure

**Files to Examine**:
- `.credo.exs` - Current Credo configuration
- `.github/workflows/elixir.yml` - CI pipeline configuration
- Any existing files in `lib/foundation/credo_checks/` directory

**Task**: 
Create the enforcement infrastructure for banning Process dictionary usage:

1. **Update `.credo.exs`** to add Process dictionary checks with temporary whitelist for:
   - `Foundation.Telemetry.Span`
   - `Foundation.Telemetry.SampledEvents`

2. **Create `lib/foundation/credo_checks/no_process_dict.ex`** with a custom Credo check that:
   - Detects `Process.put` and `Process.get` usage
   - Allows whitelisted modules during migration
   - Provides helpful error messages suggesting alternatives

3. **Update `.github/workflows/elixir.yml`** to modify the OTP compliance check:
   - Keep existing spawn checks
   - Add Process dictionary checks that exclude telemetry directory temporarily
   - Ensure the check fails CI if violations found

**Success Criteria**:
- Credo runs without errors on current codebase (due to whitelist)
- CI pipeline includes Process dictionary detection
- Custom Credo check provides clear guidance on alternatives
- All existing tests still pass

**Expected Output**: Updated configuration files and new Credo check that establishes enforcement foundation for the cleanup.
---
1 done
---

## PROMPT 2: Fix Foundation Registry Anti-Pattern

**Context**: You are implementing Stage 2.1 of the OTP cleanup to replace Process dictionary usage in the agent registry with proper ETS patterns.

**Required Reading**:
1. Read `JULY_1_2025_OTP_CLEANUP_2121.md` - Section "Stage 2: Replace Registry Anti-Patterns"
2. Read `JULY_1_2025_PRE_PHASE_2_OTP_report_02.md` - State management patterns
3. Read `test/SUPERVISION_TESTING_GUIDE.md` - Sections on proper OTP patterns

**Files to Examine**:
- `lib/foundation/protocols/registry_any.ex` - Current implementation using Process dictionary
- `lib/foundation/feature_flags.ex` - Feature flag system (if exists)
- Any tests that use `Foundation.Protocols.RegistryAny`

**Current Problem**: 
The file `lib/foundation/protocols/registry_any.ex` uses these anti-patterns:
```elixir
agents = Process.get(:registered_agents, %{})
Process.put(:registered_agents, new_agents)
```

**Task**:
1. **Analyze the current implementation** to understand the exact interface and usage patterns

2. **Create a new ETS-based implementation** that:
   - Uses a public ETS table for agent registry
   - Monitors registered processes for automatic cleanup
   - Maintains the same public API
   - Handles process death gracefully with proper demonitor

3. **Add feature flag integration** (create feature flag system if it doesn't exist):
   - `use_ets_agent_registry` flag to switch between old and new implementation
   - Gradual migration capability

4. **Create comprehensive tests** that verify:
   - Agent registration and retrieval works
   - Dead processes are cleaned up automatically
   - No monitor leaks occur
   - Performance is acceptable

5. **Update any existing tests** that might be affected by the change

**Success Criteria**:
- All existing functionality preserved
- No process dictionary usage in the new implementation
- Proper monitor cleanup with no leaks
- Feature flag allows safe rollback
- All tests pass with both old and new implementations

**Expected Output**: Refactored registry implementation using ETS with proper OTP patterns and feature flag integration.

---
2 done
---

## PROMPT 3: Fix MABEAM Agent Registry Cache

**Context**: You are implementing Stage 2.2 of the OTP cleanup to replace Process dictionary caching in the MABEAM agent registry.

**Required Reading**:
1. Read `JULY_1_2025_OTP_CLEANUP_2121.md` - Section 2.2 on MABEAM cache fix
2. Read current CI output showing Process dictionary violations
3. Read `lib/mabeam/agent_registry_impl.ex` to understand current caching pattern

**Files to Examine**:
- `lib/mabeam/agent_registry_impl.ex` - Current implementation with cache
- Related MABEAM registry files in `lib/mabeam/` directory
- Any tests for MABEAM agent registry functionality

**Current Problem**:
The file uses:
```elixir
case Process.get(cache_key) do
  # ... cache logic
Process.put(cache_key, tables)
```

**Task**:
1. **Analyze the current caching pattern** to understand:
   - What is being cached (tables)
   - Cache invalidation strategy
   - Performance requirements
   - Thread safety needs

2. **Replace with ETS-based cache** that:
   - Uses ETS table with TTL (time-to-live) expiration
   - Maintains same performance characteristics
   - Handles concurrent access properly
   - Includes automatic cleanup of expired entries

3. **Implement proper cache management**:
   - Cache creation and initialization
   - Atomic cache operations
   - TTL-based expiration
   - Memory management

4. **Add monitoring and metrics** if appropriate:
   - Cache hit/miss rates
   - Cache size monitoring
   - Performance tracking

5. **Create tests** that verify:
   - Cache stores and retrieves correctly
   - TTL expiration works properly
   - Concurrent access is safe
   - No memory leaks from expired entries

**Success Criteria**:
- No Process dictionary usage remains
- Cache performance is maintained or improved
- Proper TTL-based expiration
- Thread-safe concurrent access
- All existing MABEAM tests pass

**Expected Output**: ETS-based caching implementation for MABEAM agent registry with proper OTP patterns and comprehensive testing.

---
3 
---


## PROMPT 4: Replace Error Context Process Dictionary Usage

**Context**: You are implementing Stage 3 of the OTP cleanup to replace Process dictionary usage in error context management with Logger metadata.

**Required Reading**:
1. Read `JULY_1_2025_OTP_CLEANUP_2121.md` - Section "Stage 3: Replace Error Context Anti-Pattern"
2. Read `lib/foundation/error_context.ex` to understand current implementation
3. Read any code that uses `Foundation.ErrorContext`
4. Read `lib/foundation/error.ex` to understand error struct format

**Files to Examine**:
- `lib/foundation/error_context.ex` - Current implementation
- `lib/foundation/error.ex` - Error struct definition
- Search for all usages of `Foundation.ErrorContext` in the codebase
- Any error handling documentation

**Current Problem**:
```elixir
Process.put(:error_context, context)
Process.get(:error_context)
```

**Task**:
1. **Analyze current usage patterns**:
   - How error context is set and retrieved
   - What types of context data are stored
   - Integration with error reporting
   - Performance requirements

2. **Implement Logger metadata solution**:
   - Replace Process dictionary with `Logger.metadata`
   - Maintain backwards compatibility during transition
   - Ensure context is automatically included in log messages
   - Handle context inheritance for spawned processes

3. **Create context management functions**:
   - `set_context/1` using Logger metadata
   - `get_context/0` from Logger metadata
   - `with_context/2` for scoped context
   - `enrich_error/1` to add context to error structs
   - `clear_context/0` for cleanup

4. **Update error handling integration**:
   - Ensure errors automatically include context
   - Update any error reporting systems
   - Maintain structured logging benefits

5. **Add feature flag support**:
   - `use_logger_error_context` flag
   - Gradual migration capability
   - Rollback safety

6. **Create comprehensive tests**:
   - Context setting and retrieval
   - Context inheritance behavior
   - Error enrichment functionality
   - Performance compared to old implementation

**Success Criteria**:
- No Process dictionary usage in error context
- Error context appears in log messages automatically
- All error handling still works correctly
- Performance is maintained or improved
- Feature flag enables safe migration

**Expected Output**: Logger metadata-based error context system with proper OTP patterns and comprehensive testing.

---

## PROMPT 5: Replace Telemetry Process Dictionary Usage - Part 1 (SampledEvents)

**Context**: You are implementing Stage 4.1 of the OTP cleanup to replace Process dictionary usage in telemetry sampled events with GenServer and ETS patterns.

**Required Reading**:
1. Read `JULY_1_2025_OTP_CLEANUP_2121.md` - Section 4.1 on SampledEvents fix
2. Read `lib/foundation/telemetry/sampled_events.ex` to understand current implementation
3. Read OTP GenServer documentation for state management patterns
4. Examine how telemetry events are currently used throughout the codebase

**Files to Examine**:
- `lib/foundation/telemetry/sampled_events.ex` - Current implementation
- Any tests for sampled events functionality
- Usages of `Foundation.Telemetry.SampledEvents` throughout codebase
- `lib/foundation/application.ex` or similar for supervision structure

**Current Problem**:
Uses Process dictionary for:
- Event deduplication: `Process.get({:telemetry_dedup, key})`
- Event batching: `Process.get(batch_key, {[], timestamp})`

**Task**:
1. **Analyze current telemetry patterns**:
   - Event deduplication logic and timing
   - Batching strategy and intervals
   - Performance requirements
   - Concurrency patterns

2. **Design GenServer-based replacement**:
   - GenServer for managing batching and deduplication state
   - ETS table for high-performance concurrent access
   - Proper process lifecycle management
   - Integration with supervision tree

3. **Implement new SampledEvents module**:
   - GenServer with ETS table for state
   - Atomic deduplication using match specs
   - Batch processing with timed intervals
   - Proper cleanup and memory management

4. **Maintain API compatibility**:
   - Same public interface for `emit_event/3`
   - Same public interface for `emit_batched/3`
   - Same behavior for deduplication timing
   - Same behavior for batch processing

5. **Add to supervision tree**:
   - Include in Foundation application supervision
   - Proper startup and shutdown handling
   - Error recovery strategies

6. **Create comprehensive tests**:
   - Deduplication functionality
   - Batch processing timing
   - Concurrent access safety
   - Memory leak prevention
   - Performance benchmarks

**Success Criteria**:
- No Process dictionary usage in sampled events
- All telemetry functionality preserved
- Performance maintained or improved
- Proper supervision and error handling
- All existing telemetry tests pass

**Expected Output**: GenServer and ETS-based telemetry sampled events system with proper OTP patterns.

---

## PROMPT 6: Replace Telemetry Process Dictionary Usage - Part 2 (Span Management)

**Context**: You are implementing Stage 4.2 of the OTP cleanup to replace Process dictionary usage in telemetry span tracking with GenServer and ETS patterns.

**Required Reading**:
1. Read `JULY_1_2025_OTP_CLEANUP_2121.md` - Section 4.2 on Span fix
2. Read `lib/foundation/telemetry/span.ex` to understand current span stack implementation
3. Read about distributed tracing patterns and span context management
4. Review any existing span usage throughout the codebase

**Files to Examine**:
- `lib/foundation/telemetry/span.ex` - Current implementation
- Any tests for span functionality
- All usages of span functionality in the codebase
- Related telemetry infrastructure files

**Current Problem**:
Uses Process dictionary for span stack management:
```elixir
stack = Process.get(@span_stack_key, [])
Process.put(@span_stack_key, [span | stack])
```

**Task**:
1. **Analyze current span patterns**:
   - Span stack management per process
   - Span lifecycle (start, end, nesting)
   - Integration with telemetry events
   - Performance requirements for hot paths

2. **Design ETS-based span context management**:
   - ETS table keyed by process PID
   - Span stack storage and retrieval
   - Automatic cleanup when processes die
   - Efficient access patterns for span operations

3. **Implement new span management**:
   - GenServer for span context coordination
   - ETS table for per-process span stacks
   - Process monitoring for cleanup
   - Atomic span operations

4. **Maintain span API compatibility**:
   - `start_span/2` with same behavior
   - `end_span/1` with same behavior  
   - `with_span/3` for scoped spans
   - Same telemetry event emission

5. **Handle span lifecycle properly**:
   - Proper nesting and stack management
   - Duration calculation
   - Parent-child span relationships
   - Error handling in span operations

6. **Add process monitoring**:
   - Monitor processes that have spans
   - Automatic cleanup of dead process spans
   - Proper demonitor to prevent leaks

7. **Create comprehensive tests**:
   - Span nesting and stack behavior
   - Concurrent span operations
   - Process death cleanup
   - Performance of span operations
   - Memory leak prevention

**Success Criteria**:
- No Process dictionary usage in span management
- All span functionality preserved
- Proper process cleanup prevents memory leaks
- Performance suitable for hot code paths
- All existing span tests pass

**Expected Output**: ETS-based span context management system with proper process monitoring and cleanup.

---

## PROMPT 7: Clean Up Test Process Dictionary Usage

**Context**: You are implementing Stage 5 of the OTP cleanup to replace Process dictionary usage in tests with proper async testing patterns.

**Required Reading**:
1. Read `JULY_1_2025_OTP_CLEANUP_2121.md` - Section "Stage 5: Replace Test Anti-Patterns"
2. Read `test/SUPERVISION_TESTING_GUIDE.md` - Complete guide for proper OTP testing
3. Search for all Process.put/get usage in test files
4. Read `test/support/` directory for existing test infrastructure

**Files to Examine**:
- All test files containing `Process.put` or `Process.get`
- Current test support modules in `test/support/`
- Any existing async test helpers
- Telemetry test patterns that use process dictionary

**Current Problem**:
Tests use Process dictionary for:
- Event coordination: `Process.put(:event_received, true)`
- State sharing between test and async callbacks
- Synchronization in telemetry tests

**Task**:
1. **Audit all test Process dictionary usage**:
   - Find all files with `Process.put/get` in test directory
   - Categorize usage patterns (event sync, state sharing, etc.)
   - Identify which can be replaced with message passing
   - Document any complex cases requiring special handling

2. **Create `test/support/async_test_helpers.ex`**:
   - `wait_for/2` function for condition waiting
   - `wait_for_events/2` for multiple event coordination
   - Message-based synchronization helpers
   - Timeout handling and error reporting

3. **Replace telemetry test patterns**:
   - Convert process dictionary event flags to message passing
   - Use `assert_receive` instead of Process.get checks
   - Create helper functions for common telemetry test patterns
   - Ensure tests are deterministic and fast

4. **Update test synchronization patterns**:
   - Replace process dictionary coordination with proper messaging
   - Use GenServer calls for synchronous test operations
   - Implement proper timeouts and error handling
   - Maintain test isolation and independence

5. **Create pattern examples and documentation**:
   - Document proper async testing patterns
   - Show before/after examples for common cases
   - Create reusable test helper functions
   - Establish patterns for future test development

6. **Verify all tests still pass**:
   - Run complete test suite after changes
   - Ensure no flaky tests introduced
   - Verify test performance is maintained
   - Check for any timing-dependent issues

**Success Criteria**:
- No Process dictionary usage in any test files
- All tests pass reliably
- Test execution time maintained or improved
- Clear patterns established for future development
- Comprehensive async test helper library

**Expected Output**: Clean test suite using proper OTP async patterns with comprehensive helper library and documentation.

---

## PROMPT 8: Implement Feature Flag Migration System

**Context**: You are implementing Stage 6 of the OTP cleanup to create a feature flag system for gradual migration from Process dictionary usage to OTP patterns.

**Required Reading**:
1. Read `JULY_1_2025_OTP_CLEANUP_2121.md` - Section "Stage 6: Feature Flag Integration"
2. Read `JULY_1_2025_PRE_PHASE_2_OTP_report_05.md` - Feature flag system design
3. Examine if `lib/foundation/feature_flags.ex` already exists
4. and check `JULY_1_2025_OTP_CLEANUP_2121_prompts_1_thru_6.md` which was done during prompt 2
5. Review all the implementations from previous prompts in `JULY_1_2025_OTP_CLEANUP_2121_prompts_guide7.md` that need feature flag integration 

**Files to Examine**:
- `lib/foundation/feature_flags.ex` (if it exists)
- All files modified in previous prompts that need feature flag integration
- Application supervision structure
- Configuration files for feature flag defaults

**Current Need**:
Enable gradual migration from Process dictionary to OTP patterns with safe rollback capability.

**Task**:
1. **Create or extend feature flag system**:
   - If `Foundation.FeatureFlags` doesn't exist, create complete implementation
   - If it exists, extend with OTP cleanup flags
   - Support boolean flags and percentage rollouts
   - Persistent flag storage and runtime updates

2. **Add OTP cleanup feature flags**:
   - `use_ets_agent_registry` for registry migration
   - `use_logger_error_context` for error context migration  
   - `use_genserver_telemetry` for telemetry migration
   - `enforce_no_process_dict` for strict mode

3. **Integrate flags into all migrated code**:
   - Update `Foundation.Protocols.RegistryAny` to use registry flag
   - Update `Foundation.ErrorContext` to use error context flag
   - Update telemetry modules to use telemetry flag
   - Add fallback to legacy implementations when flags disabled

4. **Create migration control system**:
   - Admin interface for flag management
   - Monitoring of flag usage and performance
   - Automatic rollback triggers on errors
   - Migration status reporting

5. **Add flag-based testing**:
   - Test both new and legacy implementations
   - Verify flag switching works correctly
   - Test rollback scenarios
   - Performance testing with flags enabled/disabled

6. **Create migration runbook**:
   - Step-by-step flag enabling process
   - Monitoring checkpoints for each flag
   - Rollback procedures for each component
   - Success criteria for each migration step

7. **Add to supervision tree**:
   - Include FeatureFlags GenServer in supervision
   - Proper startup order dependencies
   - Handle flag service restarts gracefully

**Success Criteria**:
- Feature flag system works reliably
- All migrated code has both new and legacy paths
- Flags can be toggled safely in production
- Comprehensive testing covers both implementations
- Clear migration process with rollback capability

**Expected Output**: Complete feature flag migration system enabling safe, gradual transition from Process dictionary to OTP patterns.

---

## PROMPT 9: Create Comprehensive Integration Tests

**Context**: You are creating comprehensive integration tests to verify that the entire Process dictionary cleanup works correctly and doesn't introduce regressions.

**Required Reading**:
1. Read `JULY_1_2025_OTP_CLEANUP_2121.md` - Complete plan, especially testing strategy
2. Review all implementations from previous prompts
3. Read `test/SUPERVISION_TESTING_GUIDE.md` for integration testing patterns
4. Examine existing integration test structure

**Files to Examine**:
- All files modified in previous prompts
- Existing integration tests in `test/integration/` or similar
- Current test helper modules
- Application startup and supervision structure

**Task**:
1. **Create Process Dictionary Elimination Test**:
   - Scan all production code for Process.put/get usage
   - Verify only whitelisted modules have usage during migration
   - Ensure no new Process dictionary usage creeps in
   - Test that enforcement mechanisms work correctly

2. **Create End-to-End Functionality Tests**:
   - Test complete agent registration/retrieval flow
   - Test error context propagation through error handling
   - Test telemetry event flow with new implementations
   - Test span creation, nesting, and cleanup

3. **Create Performance Regression Tests**:
   - Benchmark registry operations (register, get, list)
   - Benchmark error context setting and retrieval
   - Benchmark telemetry event emission rates
   - Benchmark span creation and ending
   - Compare performance between old and new implementations

4. **Create Concurrency and Stress Tests**:
   - Concurrent agent registration/unregistration
   - High-frequency telemetry event emission
   - Rapid span creation and destruction
   - Memory leak detection under load
   - Process monitoring and cleanup validation

5. **Create Feature Flag Integration Tests**:
   - Test switching between old and new implementations
   - Verify behavior consistency across flag states
   - Test rollback scenarios
   - Test partial rollouts with percentage flags

6. **Create Failure and Recovery Tests**:
   - Test behavior when ETS tables are deleted
   - Test GenServer restart scenarios
   - Test process death cleanup
   - Test memory cleanup and leak prevention

7. **Create Monitoring and Observability Tests**:
   - Verify telemetry events are still emitted correctly
   - Test error reporting and context inclusion
   - Test span tracking and parent-child relationships
   - Verify no observability is lost in migration

**Success Criteria**:
- All integration tests pass with flags enabled and disabled
- No performance regressions detected
- No memory leaks under stress testing
- Proper cleanup verified in all scenarios
- Complete functional equivalence between old and new

**Expected Output**: Comprehensive integration test suite that validates the entire Process dictionary cleanup with performance, correctness, and reliability testing.

---

## PROMPT 10: Final Validation and Documentation

**Context**: You are performing final validation of the complete Process dictionary cleanup and creating documentation for the successful migration.

**Required Reading**:
1. Read `JULY_1_2025_OTP_CLEANUP_2121.md` - Complete plan for reference
2. Review all implementations from previous prompts
3. Run all tests and verify clean CI pipeline
4. Review the original CI error that started this cleanup

**Files to Examine**:
- All files modified throughout the cleanup process
- CI pipeline output and logs
- All test results
- Credo output with new enforcement rules

**Task**:
1. **Run Complete Validation Suite**:
   - Execute all tests with new implementations
   - Run Credo with strict Process dictionary checking
   - Run CI pipeline to verify compliance
   - Perform performance benchmarking
   - Execute stress tests and leak detection

2. **Verify Zero Process Dictionary Usage**:
   - Scan entire codebase for any remaining violations
   - Verify CI pipeline catches any new violations
   - Test that Credo rules prevent regressions
   - Confirm enforcement mechanisms work correctly

3. **Performance and Reliability Validation**:
   - Compare performance before and after cleanup
   - Verify memory usage patterns are healthy
   - Test system behavior under load
   - Validate error handling and recovery

4. **Create Migration Success Documentation**:
   - Document all changes made during cleanup
   - Create before/after comparison of architecture
   - Document performance impact measurements
   - Create best practices guide for avoiding future violations

5. **Create Operational Runbook**:
   - Feature flag rollout sequence
   - Monitoring checklist for each migration step  
   - Rollback procedures for each component
   - Troubleshooting guide for common issues

6. **Create Developer Guidelines**:
   - Patterns to use instead of Process dictionary
   - When to use ETS vs GenServer state
   - Proper testing patterns for async operations
   - Code review checklist for OTP compliance

7. **Update Architecture Documentation**:
   - Update system architecture diagrams
   - Document new OTP patterns used
   - Update API documentation where changed
   - Create training materials for team

**Success Criteria**:
- Zero Process dictionary violations in CI
- All tests pass reliably
- Performance is maintained or improved
- Complete documentation of changes
- Clear operational procedures established
- Team is trained on new patterns

**Expected Output**: 
1. Validation report confirming successful cleanup
2. Complete documentation of migration
3. Operational runbooks for production deployment
4. Developer guidelines for maintaining OTP compliance
5. Architecture updates reflecting new patterns

**Final Deliverable**: A codebase that is 100% free of Process dictionary anti-patterns, with proper OTP implementations, comprehensive testing, and complete documentation of the transformation.

---

## Execution Notes

**Order of Execution**: These prompts should be executed in sequence, as later prompts depend on implementations from earlier ones.

**Dependencies**: 
- Prompts 2-3 can be done in parallel after Prompt 1
- Prompts 5-6 can be done in parallel after Prompt 4  
- Prompt 7 depends on completion of Prompts 5-6
- Prompt 8 depends on completion of Prompts 2-7
- Prompts 9-10 depend on completion of all previous prompts

**Validation**: After each prompt, run the test suite and verify that existing functionality is preserved while Process dictionary usage is eliminated.

**Rollback**: Each prompt includes feature flag integration to enable safe rollback if issues are discovered.

**Success Metric**: The final goal is CI passing with zero Process dictionary violations and all tests passing reliably.