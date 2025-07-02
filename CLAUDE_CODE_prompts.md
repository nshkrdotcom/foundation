# CLAUDE CODE Implementation Prompts

**Purpose**: Self-contained prompts for completing remaining OTP hardening phases  
**Context**: Foundation Jido System OTP compliance implementation  
**Date**: 2025-07-02

---

## PHASE 3 PROMPT: MonitorManager System Implementation

### Context & Current State

You are implementing **PHASE 3** of the Foundation Jido System OTP hardening project. **PHASES 1 and 2 are COMPLETE**:

- ✅ **PHASE 1**: SupervisedSend infrastructure with delivery monitoring and dead letter queue
- ✅ **PHASE 2**: All critical raw send() calls migrated to SupervisedSend
- 🔄 **PHASE 3**: **YOUR TASK** - Implement MonitorManager system with automatic cleanup and leak detection

### Required Reading

**MUST READ** these files to understand context:
1. `CLAUDE_CODE_worklog.md` - Implementation history and current status
2. `CLAUDECODE.md` - Overall plan and phase definitions  
3. `AUDIT_02_planSteps_03.md` - Detailed Stage 3 requirements and MonitorManager specification
4. `test/OTP_ASYNC_APPROACHES_20250701.md` - Testing patterns (avoid Process.sleep, use test sync messages)

### Problem Statement

The Foundation codebase has **monitor leaks** - Process.monitor() calls without proper cleanup leading to:
- Memory leaks from uncleaned monitor references
- Process mailbox pollution from orphaned DOWN messages
- Difficulty debugging monitor-related issues
- No visibility into active monitors

### Implementation Requirements

#### Core MonitorManager Module
**Location**: `lib/foundation/monitor_manager.ex`

**Features Required**:
1. **Centralized Monitor Tracking**: Track all monitors with metadata (caller, target, creation time, stack trace)
2. **Automatic Cleanup**: Clean up monitors when either monitored process or caller process dies
3. **Leak Detection**: Find monitors older than threshold that might be leaked
4. **Telemetry Integration**: Emit events for monitor creation, cleanup, and leak detection
5. **Stats Interface**: Provide statistics for monitoring and debugging

**API Requirements**:
```elixir
# Client API
{:ok, ref} = MonitorManager.monitor(pid, :my_feature)
:ok = MonitorManager.demonitor(ref)
monitors = MonitorManager.list_monitors()
stats = MonitorManager.get_stats()
leaks = MonitorManager.find_leaks(age_ms \\ :timer.minutes(5))
```

#### Monitor Migration Helper
**Location**: `lib/foundation/monitor_migration.ex`

**Features Required**:
1. **Macro Helper**: `monitor_with_cleanup/3` for automatic cleanup
2. **GenServer Migration**: Helper to migrate existing GenServer modules
3. **Code Analysis**: Functions to identify and migrate Process.monitor calls

#### Integration Requirements

1. **Supervision**: MonitorManager must be started under Foundation supervision tree
2. **Zero Production Overhead**: No performance impact when not debugging
3. **Test Integration**: Proper test patterns using sync messages (NOT Process.sleep)
4. **ETS Storage**: Use ETS for fast lookups and concurrent access

### Test Requirements

**Location**: `test/foundation/monitor_manager_test.exs`

**Test Categories Required**:
1. **Basic Operations**: monitor/demonitor lifecycle
2. **Automatic Cleanup**: Process death triggers cleanup
3. **Caller Cleanup**: Monitor cleanup when caller dies
4. **Leak Detection**: Find old monitors
5. **Statistics**: Track creation/cleanup counts
6. **Concurrency**: Multiple processes creating monitors

**CRITICAL**: Use proper OTP async patterns from `test/OTP_ASYNC_APPROACHES_20250701.md`:
- Test sync messages (Approach #1) for async operation completion
- NO Process.sleep() calls
- Deterministic completion detection

### Reference Implementation Patterns

Based on existing Foundation patterns:

1. **Use SupervisedSend** for any inter-process communication
2. **Follow Foundation.DeadLetterQueue** patterns for ETS storage and GenServer design
3. **Use Application.get_env(:foundation, :test_pid)** for test notifications
4. **Follow existing telemetry patterns** from SupervisedSend

### Expected Deliverables

1. ✅ `lib/foundation/monitor_manager.ex` - Core monitor management
2. ✅ `lib/foundation/monitor_migration.ex` - Migration helpers  
3. ✅ `test/foundation/monitor_manager_test.exs` - Comprehensive test suite
4. ✅ All tests passing with zero warnings
5. ✅ Integration with Foundation supervision tree
6. ✅ Documentation and examples

### Success Criteria

- MonitorManager tracks all monitors with full metadata
- Automatic cleanup prevents monitor leaks
- Comprehensive test coverage with proper OTP patterns
- Zero production performance overhead
- Clear debugging and monitoring capabilities

---

phase 3 in progress!

---

## PHASE 4 PROMPT: Timeout Configuration & GenServer Call Migration

### Context & Current State

You are implementing **PHASE 4** of the Foundation Jido System OTP hardening project. **PHASES 1, 2, and 3 are COMPLETE**:

- ✅ **PHASE 1**: SupervisedSend infrastructure with delivery monitoring and dead letter queue
- ✅ **PHASE 2**: All critical raw send() calls migrated to SupervisedSend  
- ✅ **PHASE 3**: MonitorManager system with automatic cleanup and leak detection
- 🔄 **PHASE 4**: **YOUR TASK** - Add timeout configuration and migrate all GenServer.call/2 to include timeouts

### Required Reading

**MUST READ** these files to understand context:
1. `CLAUDE_CODE_worklog.md` - Implementation history and phases 1-3 completion
2. `CLAUDECODE.md` - Overall plan and current phase status
3. `AUDIT_02_planSteps_03.md` - Section 3.4 GenServer Timeout Enforcement requirements
4. `test/OTP_ASYNC_APPROACHES_20250701.md` - Testing patterns for infrastructure

### Problem Statement

The Foundation codebase has **GenServer.call/2 without explicit timeouts** leading to:
- Processes hanging indefinitely on dead/slow GenServers
- No consistent timeout policies across the application  
- Difficult debugging of timeout-related issues
- Default 5-second timeout may be inappropriate for different operations

### Implementation Requirements

#### Timeout Configuration Module
**Location**: `lib/foundation/timeout_config.ex`

**Features Required**:
1. **Centralized Configuration**: Service-specific and operation-specific timeouts
2. **Environment Overrides**: Runtime configuration via Application environment
3. **Pattern Matching**: Support for operation type patterns
4. **Macro Helper**: Easy timeout application in GenServer calls

**Configuration Structure**:
```elixir
@timeout_config %{
  # Service-specific timeouts
  "Foundation.ResourceManager" => @long_timeout,
  "Foundation.Services.ConnectionManager" => @long_timeout,
  
  # Operation-specific timeouts  
  batch_operation: @long_timeout,
  health_check: 1_000,
  sync_operation: @default_timeout,
  
  # Pattern-based timeouts
  {:data_processing, :*} => @long_timeout,
  {:network_call, :*} => @critical_timeout,
}
```

**API Requirements**:
```elixir
timeout = TimeoutConfig.get_timeout(MyServer)
timeout = TimeoutConfig.get_timeout(:batch_operation)
timeout = TimeoutConfig.get_timeout({:data_processing, :etl})

# Macro for easy use
TimeoutConfig.call_with_timeout(server, request, opts \\ [])
```

#### Migration Script
**Location**: `scripts/migrate_genserver_timeouts.exs`

**Features Required**:
1. **Pattern Recognition**: Find all GenServer.call/2 without timeouts
2. **Automatic Migration**: Convert to GenServer.call/3 with appropriate timeouts
3. **Import Addition**: Add TimeoutConfig imports where needed
4. **Report Generation**: Summary of changes made

#### Current Violations

Find and fix GenServer.call/2 patterns in these areas:
- Foundation services and infrastructure
- Jido agents and coordination
- MABEAM coordination patterns
- Test files (use appropriate test timeouts)

### Test Requirements

**Location**: `test/foundation/timeout_config_test.exs`

**Test Categories Required**:
1. **Configuration Loading**: Service and operation timeouts
2. **Pattern Matching**: Tuple pattern resolution
3. **Environment Overrides**: Runtime configuration changes
4. **Macro Functionality**: call_with_timeout behavior
5. **Default Handling**: Fallback timeout behavior

### Implementation Strategy

1. **Audit Current Usage**: Find all GenServer.call/2 instances
2. **Categorize Operations**: Group by service and operation type
3. **Define Timeout Policies**: Appropriate timeouts for each category
4. **Create Migration Script**: Automated conversion tool
5. **Test Integration**: Ensure all changes work correctly

### Reference Files

Current GenServer.call patterns to fix:
```bash
# Find current violations
grep -r "GenServer.call(" lib/ --include="*.ex" | grep -v ", [0-9]" | grep -v ":timer"
```

### Expected Deliverables

1. ✅ `lib/foundation/timeout_config.ex` - Centralized timeout configuration
2. ✅ `scripts/migrate_genserver_timeouts.exs` - Migration automation
3. ✅ `test/foundation/timeout_config_test.exs` - Comprehensive test suite
4. ✅ All GenServer.call/2 converted to GenServer.call/3
5. ✅ All tests passing with zero warnings
6. ✅ Documentation and usage examples

### Success Criteria

- All GenServer.call operations have explicit timeouts
- Consistent timeout policies across the application
- Easy configuration and runtime adjustment
- No hanging processes due to timeout issues
- Comprehensive test coverage

---

## PHASE 5 PROMPT: Comprehensive Testing & Final OTP Compliance Verification

### Context & Current State

You are implementing **PHASE 5** of the Foundation Jido System OTP hardening project. **PHASES 1-4 are COMPLETE**:

- ✅ **PHASE 1**: SupervisedSend infrastructure with delivery monitoring and dead letter queue
- ✅ **PHASE 2**: All critical raw send() calls migrated to SupervisedSend
- ✅ **PHASE 3**: MonitorManager system with automatic cleanup and leak detection  
- ✅ **PHASE 4**: Timeout configuration and all GenServer.call/2 migrated to include timeouts
- 🔄 **PHASE 5**: **YOUR TASK** - Comprehensive testing and final OTP compliance verification

### Required Reading

**MUST READ** these files to understand context:
1. `CLAUDE_CODE_worklog.md` - Complete implementation history of all phases
2. `CLAUDECODE.md` - Overall plan and success criteria
3. `AUDIT_02_planSteps_03.md` - Original audit findings and requirements
4. `test/OTP_ASYNC_APPROACHES_20250701.md` - Testing methodology and patterns
5. `JULY_1_2025_PRE_PHASE_2_OTP_report_01_AUDIT_01.md` - Original OTP violations audit

### Problem Statement

Complete **final verification** that all OTP violations have been eliminated and the system is production-ready:
- Verify zero raw send() calls to other processes
- Verify zero monitor leaks
- Verify all GenServer calls have timeouts
- Comprehensive load testing
- Integration testing across all components
- Performance regression verification

### Implementation Requirements

#### Integration Test Suite
**Location**: `test/foundation/otp_compliance_test.exs`

**Test Categories Required**:
1. **End-to-End OTP Compliance**: Full system behavior under load
2. **SupervisedSend Integration**: Cross-component message delivery
3. **MonitorManager Integration**: Monitor lifecycle across components
4. **Timeout Compliance**: All timeouts working under stress
5. **Performance Regression**: Verify no significant slowdown

#### Load Testing Suite  
**Location**: `test/load/otp_compliance_load_test.exs`

**Load Test Scenarios**:
1. **High Message Volume**: 1000+ messages/second through SupervisedSend
2. **Monitor Creation/Cleanup**: 100+ concurrent monitor operations
3. **Timeout Stress**: GenServer calls under high load
4. **Dead Letter Queue**: Verify DLQ performance under failure conditions
5. **Memory Stability**: No leaks under sustained load

#### Audit Verification Script
**Location**: `scripts/otp_final_audit.exs`

**Verification Checks**:
1. **Raw Send Audit**: Confirm zero `send(pid, message)` to other processes
2. **Monitor Audit**: Confirm all `Process.monitor` use MonitorManager
3. **Timeout Audit**: Confirm all `GenServer.call/2` have been migrated
4. **Code Quality**: Zero warnings, zero Credo violations
5. **Test Coverage**: Comprehensive coverage metrics

### Final Verification Requirements

#### Code Quality Gates
All must pass before completion:
```bash
# All tests pass
mix test --cover

# Zero warnings  
mix compile --warnings-as-errors

# Clean Dialyzer
mix dialyzer

# Zero Credo violations
mix credo --strict

# Clean format
mix format --check-formatted
```

#### Performance Benchmarks
Create benchmarks for:
1. **SupervisedSend vs Raw Send**: Verify acceptable overhead
2. **MonitorManager vs Direct Monitor**: Verify minimal overhead  
3. **Timeout Config vs Hardcoded**: Verify no performance loss
4. **End-to-End Latency**: Measure cross-component communication

#### Integration Tests

**Must Test**:
1. **Coordinator → Agent Communication**: Using SupervisedSend
2. **Signal Router → Handler Delivery**: With failure handling
3. **Coordination Patterns Broadcasting**: Multi-agent coordination
4. **Scheduler → Agent Delivery**: Scheduled task execution
5. **Monitor Lifecycle**: Creation, cleanup, leak detection

### Test File Structure

```
test/
├── foundation/
│   ├── supervised_send_test.exs          # ✅ Already complete
│   ├── dead_letter_queue_test.exs        # ✅ Already complete  
│   ├── monitor_manager_test.exs          # ✅ From Phase 3
│   ├── timeout_config_test.exs           # ✅ From Phase 4
│   └── otp_compliance_test.exs           # 🔄 Your task
├── integration/
│   ├── cross_component_test.exs          # 🔄 Your task
│   └── failure_scenarios_test.exs        # 🔄 Your task
├── load/
│   └── otp_compliance_load_test.exs      # 🔄 Your task
└── OTP_ASYNC_APPROACHES_20250701.md      # ✅ Testing methodology
```

### Reference Implementation Patterns

Based on **existing Foundation test patterns**:

1. **Use Test Sync Messages**: Follow `test/OTP_ASYNC_APPROACHES_20250701.md` Approach #1
2. **Proper Setup/Teardown**: Application.put_env for test configuration
3. **Deterministic Assertions**: No timing races or Process.sleep
4. **Resource Cleanup**: Proper test isolation and cleanup
5. **Comprehensive Coverage**: Edge cases, error conditions, concurrency

### Success Metrics

#### Functional Requirements ✅
- Zero raw send() calls to other processes (self-sends allowed)
- Zero monitor leaks under normal and stress conditions  
- All GenServer.call operations have explicit timeouts
- All error conditions properly handled
- Comprehensive telemetry and logging

#### Performance Requirements ✅  
- SupervisedSend overhead < 10% vs raw send
- MonitorManager overhead < 5% vs direct monitoring
- No memory leaks under sustained load
- Timeout configuration has zero runtime overhead
- Dead letter queue handles 1000+ failed messages efficiently

#### Quality Requirements ✅
- 281+ tests passing, 0 failures
- Zero compiler warnings
- Zero Dialyzer errors  
- Zero Credo violations
- >95% test coverage on new infrastructure

### Expected Deliverables

1. ✅ `test/foundation/otp_compliance_test.exs` - Integration test suite
2. ✅ `test/integration/cross_component_test.exs` - Cross-component integration
3. ✅ `test/integration/failure_scenarios_test.exs` - Failure handling tests
4. ✅ `test/load/otp_compliance_load_test.exs` - Load and stress tests
5. ✅ `scripts/otp_final_audit.exs` - Automated compliance verification
6. ✅ Performance benchmarks and reports
7. ✅ Final compliance documentation

### Final Success Criteria

**MISSION COMPLETE** when all criteria met:

#### ✅ Zero OTP Violations
- No raw send() to other processes
- No monitor leaks 
- No infinite timeouts

#### ✅ Production Ready
- Comprehensive error handling
- Full observability (telemetry, logging)
- Performance acceptable
- Memory stable under load

#### ✅ Test Coverage Complete
- All new infrastructure tested
- Integration scenarios covered
- Load testing completed
- Failure scenarios validated

#### ✅ Code Quality Excellent  
- Zero warnings/errors
- Clean Credo compliance
- Full Dialyzer type checking
- Comprehensive documentation

**DELIVERABLE**: Production-grade OTP-compliant Foundation Jido System ready for deployment.

---

## General Instructions for All Phases

### Working Method
1. **Read Required Files**: Understand context before coding
2. **Follow Existing Patterns**: Use Foundation SupervisedSend/DeadLetterQueue as examples
3. **Test-Driven Development**: Write failing tests first
4. **Proper OTP Patterns**: Use sync messages, not Process.sleep
5. **Update Worklog**: Document progress in `CLAUDE_CODE_worklog.md`

### Quality Standards
- All tests must pass before completion
- Zero compiler warnings
- Follow existing Foundation code style
- Comprehensive test coverage
- Proper documentation

### Success Verification
Each phase complete when:
- Implementation working correctly
- All tests passing
- No regressions in existing functionality  
- Worklog updated with progress
- Todo list updated

**Commit Only When All Quality Gates Pass**