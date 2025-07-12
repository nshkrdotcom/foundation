# JULY 2 PHASE 2 OTP IMPLEMENTATION PROMPTS
**Generated**: July 2, 2025
**Purpose**: Self-contained implementation prompts for completing OTP refactoring
**Priority**: Ordered by risk level and dependencies

## Overview

This document contains detailed, self-contained prompts for implementing the remaining OTP refactoring tasks identified in the audits. Each prompt includes all necessary context, file references, and acceptance criteria.

---

## PROMPT 1: Enable NoRawSend Credo Check [CRITICAL - 5 minutes]

### Context
The `Foundation.CredoChecks.NoRawSend` module exists and is well-implemented but is currently commented out in the Credo configuration. This check prevents the use of raw `send/2` which provides no delivery guarantees.

### Required Reading
1. `/home/home/p/g/n/elixir_ml/foundation/.credo.exs` - Lines 83, 169 (commented out checks)
2. `/home/home/p/g/n/elixir_ml/foundation/lib/foundation/credo_checks/no_raw_send.ex` - The implemented check
3. `/home/home/p/g/n/elixir_ml/foundation/JULY_1_2025_PRE_PHASE_2_OTP_report_01.md` - Stage 1.1 for context

### Task
1. Uncomment the `Foundation.CredoChecks.NoRawSend` check in `.credo.exs` (both configurations)
2. Run `mix credo --strict` to identify all raw send usage
3. For each violation found:
   - If it's a legitimate fire-and-forget case, add to the allowlist in the check
   - Otherwise, replace with `GenServer.call` or `GenServer.cast`
4. Document any allowed exceptions with comments explaining why raw send is necessary

### Acceptance Criteria
- [ ] NoRawSend check is active in both credo configurations
- [ ] `mix credo --strict` passes with no warnings
- [ ] All remaining raw sends have documented justification
- [ ] CI pipeline runs credo checks automatically

---

## PROMPT 2: Clarify and Implement Agent State Persistence [CRITICAL - 2 days]

### Context
TaskAgent and CoordinatorAgent currently use `FoundationAgent` but lack state persistence. The `PersistentFoundationAgent` module exists but isn't being used. This creates risk of data loss on crashes.

### Required Reading
1. `/home/home/p/g/n/elixir_ml/foundation/lib/jido_system/agents/task_agent.ex` - Current implementation
2. `/home/home/p/g/n/elixir_ml/foundation/lib/jido_system/agents/coordinator_agent.ex` - Current implementation
3. `/home/home/p/g/n/elixir_ml/foundation/lib/jido_system/agents/persistent_foundation_agent.ex` - Available persistence
4. `/home/home/p/g/n/elixir_ml/foundation/lib/jido_system/agents/foundation_agent.ex` - Base behavior
5. `/home/home/p/g/n/elixir_ml/foundation/JULY_1_2025_PRE_PHASE_2_OTP_report_02.md` - Stage 2.1 for implementation pattern

### Task
1. Analyze why agents use `FoundationAgent` instead of `PersistentFoundationAgent`
2. If there's a valid architectural reason, document it
3. Otherwise, migrate both agents to use `PersistentFoundationAgent`:
   ```elixir
   use JidoSystem.Agents.PersistentFoundationAgent,
     name: "task_agent",
     persistent_fields: [:task_queue, :processing_tasks, :completed_count, :error_count],
     schema: [...]
   ```
4. Implement serialization hooks for complex data types (like queues)
5. Add state recovery tests
6. Verify no performance regression

### Acceptance Criteria
- [ ] Clear documentation of persistence strategy choice
- [ ] Both agents persist critical state to ETS
- [ ] State survives process crashes
- [ ] Tests verify state recovery
- [ ] Performance impact < 5%

---

## PROMPT 3: Create Foundation.Test.Helpers [HIGH - 1 day]

### Context
Test suite uses `Process.sleep` in 58+ files and lacks unified testing utilities. This makes tests slow and flaky.

### Required Reading
1. `/home/home/p/g/n/elixir_ml/foundation/test/support/` - Existing scattered helpers
2. `/home/home/p/g/n/elixir_ml/foundation/JULY_1_2025_PRE_PHASE_2_OTP_report_03.md` - Stage 3.1 for implementation
3. Example test files with Process.sleep (run `grep -r "Process\.sleep" test/`)

### Task
Create `/home/home/p/g/n/elixir_ml/foundation/test/support/foundation_test_helpers.ex`:

```elixir
defmodule Foundation.Test.Helpers do
  @moduledoc """
  Unified test helpers eliminating Process.sleep and telemetry synchronization.
  """
  
  def wait_for(condition_fun, timeout \\ 1000)
  def wait_for_state(pid, state_check, timeout \\ 1000)
  def drain_mailbox(pid)
  def sync_operation(server, message, checker_fun, timeout \\ 1000)
  # ... implement as specified in report_03.md
end
```

Then:
1. Consolidate helpers from `/test/support/` into this module
2. Update test files to use `Foundation.Test.Helpers`
3. Create migration script to find and suggest replacements for Process.sleep

### Acceptance Criteria
- [ ] Foundation.Test.Helpers module created with all core functions
- [ ] At least 10 test files migrated as examples
- [ ] Migration script identifies all Process.sleep usage
- [ ] Documentation includes migration guide
- [ ] Test suite runs 20%+ faster

---

## PROMPT 4: Implement Deployment Rollout Automation [HIGH - 2 days]

### Context
FeatureFlags system exists but lacks automation for gradual rollout and health monitoring.

### Required Reading
1. `/home/home/p/g/n/elixir_ml/foundation/lib/foundation/feature_flags.ex` - Existing system
2. `/home/home/p/g/n/elixir_ml/foundation/JULY_1_2025_PRE_PHASE_2_OTP_report_05.md` - Stage 5.3 for rollout plan
3. `/home/home/p/g/n/elixir_ml/foundation/docs/MABEAM_DEPLOYMENT_GUIDE.md` - Deployment documentation

### Task
Create deployment automation modules:

1. `/home/home/p/g/n/elixir_ml/foundation/lib/foundation/deployment/rollout_orchestrator.ex`:
   - Manages phased rollout using FeatureFlags
   - Monitors health metrics during rollout
   - Triggers automatic rollback on threshold violations

2. `/home/home/p/g/n/elixir_ml/foundation/lib/foundation/deployment/health_monitor.ex`:
   - Tracks error rates, restart frequency, performance metrics
   - Integrates with existing telemetry
   - Provides rollback recommendations

3. `/home/home/p/g/n/elixir_ml/foundation/scripts/deployment/rollout.exs`:
   - CLI interface for deployment operations
   - Pre-flight checks
   - Rollback commands

### Acceptance Criteria
- [ ] Automated rollout through 5 defined phases
- [ ] Health metrics trigger automatic rollback
- [ ] Manual rollback available at any time
- [ ] Deployment status dashboard/API
- [ ] Integration tests verify rollback scenarios

---

## PROMPT 5: Migrate ErrorContext to Logger Metadata [MEDIUM - 1 day]

### Context
ErrorContext supports both Process dictionary and Logger metadata, controlled by feature flag. Need to complete migration.

### Required Reading
1. `/home/home/p/g/n/elixir_ml/foundation/lib/foundation/error_context.ex` - Dual-mode implementation
2. `/home/home/p/g/n/elixir_ml/foundation/lib/foundation/feature_flags.ex` - Feature flag control
3. Files using Process dictionary (run `grep -r "Process\.put\|Process\.get" lib/`)

### Task
1. Enable `:use_logger_error_context` feature flag in development
2. Run test suite and fix any failures
3. Update all ErrorContext usage to be feature-flag aware
4. Create migration guide for users
5. Plan deprecation timeline for Process dictionary mode

### Acceptance Criteria
- [ ] All tests pass with Logger metadata mode enabled
- [ ] Performance comparison documented
- [ ] Migration guide created
- [ ] Deprecation warnings added to Process dict mode
- [ ] Feature flag rollout plan defined

---

## PROMPT 6: Create Error Boundary Patterns [MEDIUM - 1 day]

### Context
Error handling infrastructure exists but lacks specific boundary patterns for different error types.

### Required Reading
1. `/home/home/p/g/n/elixir_ml/foundation/lib/foundation/error.ex` - Current error system
2. `/home/home/p/g/n/elixir_ml/foundation/JULY_1_2025_PRE_PHASE_2_OTP_report_04.md` - Stage 4.1 Step 2

### Task
Create `/home/home/p/g/n/elixir_ml/foundation/lib/foundation/error_boundary.ex`:

```elixir
defmodule Foundation.ErrorBoundary do
  @moduledoc """
  Error boundaries for different operation types.
  Only catches EXPECTED errors, lets unexpected ones crash.
  """
  
  def with_network_error_handling(fun)
  def with_database_error_handling(fun)
  def with_json_error_handling(fun)
  def protect_critical_path(fun, fallback_result)
  # NO catch-all handlers!
end
```

Also create:
- `/home/home/p/g/n/elixir_ml/foundation/lib/foundation/retry_strategy.ex`
- `/home/home/p/g/n/elixir_ml/foundation/lib/foundation/operation_isolation.ex`

### Acceptance Criteria
- [ ] Error boundaries for all external service types
- [ ] Retry only infrastructure errors, not business errors
- [ ] Operation isolation with circuit breakers
- [ ] No catch-all error handlers
- [ ] Usage examples in documentation

---

## PROMPT 7: Fix Unsupervised Processes [MEDIUM - 4 hours]

### Context
Load test modules use unsupervised processes that can leak resources.

### Required Reading
1. `/home/home/p/g/n/elixir_ml/foundation/lib/foundation/telemetry/load_test/worker.ex` - Line 161-162
2. `/home/home/p/g/n/elixir_ml/foundation/lib/foundation/telemetry/load_test.ex` - Lines 292, 298
3. OTP supervision principles documentation

### Task
1. Replace `Task.start/1` with `Task.Supervisor.start_child/2`
2. Replace `GenServer.start/2` with `GenServer.start_link/3` under a supervisor
3. Create `Foundation.LoadTest.Supervisor` to manage test processes
4. Ensure all processes are properly linked and supervised

### Acceptance Criteria
- [ ] No unsupervised process spawning in load tests
- [ ] Load test supervisor properly configured
- [ ] Resource cleanup verified under failure scenarios
- [ ] Load test still functions correctly

---

## PROMPT 8: Create Pre-Integration Validation [LOW - 4 hours]

### Context
No automated validation exists to ensure OTP compliance before deployment.

### Required Reading
1. `/home/home/p/g/n/elixir_ml/foundation/JULY_1_2025_PRE_PHASE_2_OTP_report_05.md` - Stage 5.1
2. `/home/home/p/g/n/elixir_ml/foundation/.github/workflows/` - Current CI setup

### Task
Create `/home/home/p/g/n/elixir_ml/foundation/scripts/pre_integration_check.exs` with checks for:
- Banned primitives (Process.spawn, raw send, Process.put)
- Monitor/demonitor pairing
- State persistence verification
- Test pattern compliance
- Error handling patterns

Add to CI pipeline for automatic validation.

### Acceptance Criteria
- [ ] Script validates all OTP compliance rules
- [ ] Clear pass/fail output with specific issues
- [ ] Integrated into CI/CD pipeline
- [ ] Documentation of all checks
- [ ] Extensible for future rules

---

## PROMPT 9: Replace Infinity Timeouts [LOW - 2 hours]

### Context
Multiple files use `:infinity` timeout in GenServer calls, which can cause system hangs.

### Required Reading
1. Files with infinity timeouts (run `grep -r ":infinity" lib/`)
2. GenServer timeout best practices

### Task
1. Identify all `:infinity` timeouts in GenServer calls
2. Replace with reasonable timeouts (typically 5000-30000ms)
3. Add timeout configuration where appropriate
4. Handle timeout errors gracefully

### Acceptance Criteria
- [ ] No `:infinity` timeouts in production code
- [ ] Timeouts are configurable where sensible
- [ ] Timeout errors handled appropriately
- [ ] Performance not negatively impacted

---

## PROMPT 10: Document State Persistence Architecture [LOW - 2 hours]

### Context
Current state persistence approach differs from original plan and needs clear documentation.

### Required Reading
1. `/home/home/p/g/n/elixir_ml/foundation/lib/jido_system/agents/foundation_agent.ex`
2. `/home/home/p/g/n/elixir_ml/foundation/lib/jido_system/agents/persistent_foundation_agent.ex`
3. Current agent implementations

### Task
Create `/home/home/p/g/n/elixir_ml/foundation/docs/STATE_PERSISTENCE_ARCHITECTURE.md`:
- Explain FoundationAgent vs PersistentFoundationAgent design choice
- Document when to use each approach
- Provide migration guide for adding persistence
- Include fault tolerance guarantees
- Add sequence diagrams for state recovery

### Acceptance Criteria
- [ ] Clear explanation of architecture choices
- [ ] Usage guidelines for developers
- [ ] Performance implications documented
- [ ] Code examples for common patterns
- [ ] Reviewed by team lead

---

## Implementation Priority Matrix

### Week 1 (Critical + High Impact)
1. **Day 1**: Enable NoRawSend (5 min) + Start Agent Persistence
2. **Day 2**: Complete Agent Persistence + Create Test Helpers
3. **Day 3**: Start Deployment Automation
4. **Day 4**: Complete Deployment Automation
5. **Day 5**: Error Context Migration + Error Boundaries

### Week 2 (Medium + Low Priority)
1. **Day 1**: Fix Unsupervised Processes + Infinity Timeouts
2. **Day 2**: Pre-Integration Validation
3. **Day 3**: Documentation + Review
4. **Day 4-5**: Integration testing and refinement

## Success Metrics
- Zero data loss on agent crashes
- Test suite 30% faster
- Automated deployment with < 1% error rate
- All Credo checks passing
- 100% OTP compliance validation

---

**Note**: Each prompt is self-contained and can be assigned independently. However, the suggested order optimizes for risk reduction and dependency management.