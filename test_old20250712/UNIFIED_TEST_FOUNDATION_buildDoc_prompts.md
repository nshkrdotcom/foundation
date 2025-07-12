# Unified Test Foundation Migration - Implementation Prompts
## Complete Test Isolation for Supervision Crash Recovery Tests

**Document Version**: 1.0  
**Date**: 2025-07-02  
**Purpose**: Self-contained prompts for implementing complete test isolation  
**Target**: Eliminate supervision test contamination with proper OTP patterns

---

## PROMPT 1: Foundation Infrastructure Setup - SupervisionTestHelpers

### Context Files to Read

**Implementation Guide:**
```
test/UNIFIED_TEST_FOUNDATION_buildDoc.md
```

**Current Test Analysis:**
```
test/jido_foundation/supervision_crash_recovery_test.exs
```

**Existing Foundation Support:**
```
test/support/unified_test_foundation.ex
test/support/async_test_helpers.ex
test/support/test_isolation.ex
```

**JidoSystem Supervision Structure:**
```
lib/jido_system/application.ex
```

**Current Services:**
```
lib/jido_foundation/task_pool_manager.ex
lib/jido_foundation/system_command_manager.ex
lib/jido_foundation/coordination_manager.ex
lib/jido_foundation/scheduler_manager.ex
```

### Task

Create `test/support/supervision_test_helpers.ex` with complete helper functions for isolated supervision testing.

**Requirements:**

1. **Service Access Functions:**
   - `get_service(supervision_context, service_name)` - Get service PID from test supervision tree
   - `wait_for_service_restart(supervision_context, service_name, old_pid, timeout)` - Wait for service restart
   - `monitor_all_services(supervision_context)` - Monitor all services for cascade testing

2. **Supervision Testing Functions:**
   - `verify_rest_for_one_cascade(monitors, crashed_service)` - Verify rest_for_one behavior
   - Service name to module mapping helpers
   - Process lifecycle verification utilities

3. **Integration Requirements:**
   - Must work with existing `Foundation.AsyncTestHelpers.wait_for/3`
   - Should handle the supervision order: `SchedulerManager → TaskPoolManager → SystemCommandManager → CoordinationManager`
   - Proper error handling for service not found scenarios
   - Clear documentation with examples

4. **OTP Compliance:**
   - Follow proper process monitoring patterns
   - Use `assert_receive` for deterministic testing
   - Handle supervision cascade timing correctly
   - Support isolated registry-based service discovery

**Deliverables:**
- Complete `test/support/supervision_test_helpers.ex` file
- All functions documented with examples
- Error handling for edge cases
- Integration with existing async test patterns

---

p1 done

---

## PROMPT 2: Supervision Test Setup Infrastructure

### Context Files to Read

**Implementation Guide:**
```
test/UNIFIED_TEST_FOUNDATION_buildDoc.md
```

**Previous Deliverable:**
```
test/support/supervision_test_helpers.ex
```

**Existing Foundation Support:**
```
test/support/unified_test_foundation.ex
test/support/async_test_helpers.ex
test/support/test_isolation.ex
```

**JidoSystem Application Structure:**
```
lib/jido_system/application.ex
lib/jido_foundation/monitor_supervisor.ex
lib/jido_system/supervisors/workflow_supervisor.ex
lib/jido_system/agents/state_supervisor.ex
lib/jido_system/error_store.ex
lib/jido_system/health_monitor.ex
```

**Registry Usage Examples:**
```
lib/jido_foundation/bridge.ex
```

### Task

Create `test/support/supervision_test_setup.ex` that creates completely isolated JidoFoundation supervision trees for testing.

**Requirements:**

1. **Isolated Supervision Creation:**
   - `create_isolated_supervision()` - Main setup function
   - Creates unique test-specific registries and supervisors
   - Starts complete JidoSystem.Application child tree in isolation
   - Returns supervision context with all necessary references

2. **Registry Management:**
   - Test-specific Registry instances for service discovery
   - Proper service registration with `{:service, module_name}` keys
   - Cleanup and resource management

3. **Supervision Tree Recreation:**
   - Recreate exact JidoSystem.Application children structure
   - Maintain same supervision strategy (`:rest_for_one`)
   - Use test-specific names to avoid global collisions
   - Proper dependency ordering

4. **Lifecycle Management:**
   - `wait_for_services_ready/2` - Ensure all services are stable
   - `cleanup_isolated_supervision/1` - Proper cleanup on test exit
   - Resource leak prevention
   - Graceful shutdown handling

5. **Context Structure:**
   ```elixir
   %{
     test_id: unique_integer,
     registry: registry_name,
     registry_pid: pid,
     supervisor: supervisor_name, 
     supervisor_pid: pid,
     services: [list_of_service_modules]
   }
   ```

**Deliverables:**
- Complete `test/support/supervision_test_setup.ex` file
- Isolated supervision tree creation
- Proper cleanup and resource management
- Integration with `on_exit` callbacks
- Documentation and error handling

---

p2 done


---

## PROMPT 3: UnifiedTestFoundation Enhancement

### Context Files to Read

**Implementation Guide:**
```
test/UNIFIED_TEST_FOUNDATION_buildDoc.md
```

**Previous Deliverables:**
```
test/support/supervision_test_helpers.ex
test/support/supervision_test_setup.ex
```

**Current UnifiedTestFoundation:**
```
test/support/unified_test_foundation.ex
```

**Existing Test Foundation Patterns:**
```
test/support/test_isolation.ex
test/support/async_test_helpers.ex
```

**Example Usage Patterns:**
```
test/foundation/services/connection_manager_test.exs
test/foundation/infrastructure/circuit_breaker_test.exs
```

### Task

Enhance `test/support/unified_test_foundation.ex` to add `:supervision_testing` mode for isolated supervision crash recovery testing.

**Requirements:**

1. **New Testing Mode:**
   - Add `:supervision_testing` mode to existing modes
   - Must coexist with existing `:registry`, `:telemetry`, `:full` modes
   - Use `async: false` for supervision tests (serialization required)

2. **Mode Implementation:**
   ```elixir
   defmacro __using__(mode) when mode == :supervision_testing do
     quote do
       use ExUnit.Case, async: false
       import Foundation.AsyncTestHelpers
       import Foundation.SupervisionTestHelpers
       
       setup do
         Foundation.SupervisionTestSetup.create_isolated_supervision()
       end
     end
   end
   ```

3. **Integration Requirements:**
   - Import both helper modules
   - Call supervision setup automatically
   - Return `%{supervision_tree: context}` for tests
   - Maintain compatibility with existing patterns

4. **Documentation:**
   - Update module documentation with new mode
   - Provide usage examples
   - Explain when to use `:supervision_testing` vs other modes
   - Migration guidance from `ExUnit.Case`

**Deliverables:**
- Enhanced `test/support/unified_test_foundation.ex`
- New `:supervision_testing` mode implementation
- Updated documentation
- Backward compatibility maintained
- Clear usage examples

---

p3 done


---

## PROMPT 4: Service Registry Support Implementation

### Context Files to Read

**Implementation Guide:**
```
test/UNIFIED_TEST_FOUNDATION_buildDoc.md
```

**Previous Deliverables:**
```
test/support/supervision_test_helpers.ex
test/support/supervision_test_setup.ex
test/support/unified_test_foundation.ex (enhanced)
```

**Target Services:**
```
lib/jido_foundation/task_pool_manager.ex
lib/jido_foundation/system_command_manager.ex
lib/jido_foundation/coordination_manager.ex
lib/jido_foundation/scheduler_manager.ex
```

**Registry Usage Examples:**
```
lib/jido_foundation/bridge.ex
test/support/test_isolation.ex
```

### Task

Enhance all JidoFoundation services to support test-specific registry registration while maintaining production compatibility.

**Requirements:**

1. **TaskPoolManager Enhancement:**
   - Modify `start_link/1` to accept `:registry` option
   - Register with test registry when provided: `Registry.register(registry, {:service, __MODULE__}, %{test_instance: true})`
   - Maintain global registration for production
   - Update `init/1` to handle registry parameter

2. **Apply Same Pattern to All Services:**
   - `SystemCommandManager`
   - `CoordinationManager`  
   - `SchedulerManager`

3. **Implementation Pattern:**
   ```elixir
   def start_link(opts \\ []) do
     name = Keyword.get(opts, :name, __MODULE__)
     registry = Keyword.get(opts, :registry, nil)
     GenServer.start_link(__MODULE__, {opts, registry}, name: name)
   end
   
   def init({opts, registry}) do
     if registry do
       Registry.register(registry, {:service, __MODULE__}, %{test_instance: true})
     end
     # ... existing init logic
   end
   ```

4. **Backward Compatibility:**
   - No changes to existing production usage
   - Registry parameter is optional
   - Default behavior unchanged
   - All existing tests continue to work

5. **Error Handling:**
   - Handle registry registration failures gracefully
   - Proper error messages for debugging
   - Fallback behavior for missing registry

**Deliverables:**
- Enhanced `lib/jido_foundation/task_pool_manager.ex`
- Enhanced `lib/jido_foundation/system_command_manager.ex`
- Enhanced `lib/jido_foundation/coordination_manager.ex`
- Enhanced `lib/jido_foundation/scheduler_manager.ex`
- Backward compatibility maintained
- Test registry support added

---

p4 done

---

## PROMPT 5: Isolated Service Discovery Utilities

### Context Files to Read

**Implementation Guide:**
```
test/UNIFIED_TEST_FOUNDATION_buildDoc.md
```

**Previous Deliverables:**
```
test/support/supervision_test_helpers.ex
test/support/supervision_test_setup.ex
test/support/unified_test_foundation.ex (enhanced)
lib/jido_foundation/task_pool_manager.ex (enhanced)
lib/jido_foundation/system_command_manager.ex (enhanced)
lib/jido_foundation/coordination_manager.ex (enhanced)
lib/jido_foundation/scheduler_manager.ex (enhanced)
```

**Current Service APIs:**
```
lib/jido_foundation/task_pool_manager.ex
lib/jido_foundation/system_command_manager.ex
lib/jido_foundation/coordination_manager.ex
lib/jido_foundation/scheduler_manager.ex
```

### Task

Create `test/support/isolated_service_discovery.ex` for transparent access to JidoFoundation services in isolated supervision testing.

**Requirements:**

1. **Service Call Functions:**
   - `call_service(supervision_context, service_module, function, args)` - Call service functions
   - `cast_service(supervision_context, service_module, message)` - Cast to services
   - Handle both simple calls and calls with arguments

2. **Registry Integration:**
   - Use `Registry.lookup(registry, {:service, module})` pattern
   - Handle service not found errors gracefully
   - Support the service registration pattern from enhanced services

3. **API Compatibility:**
   ```elixir
   # Instead of:
   TaskPoolManager.get_all_stats()
   
   # Use in isolated tests:
   call_service(sup_tree, TaskPoolManager, :get_all_stats)
   
   # With arguments:
   call_service(sup_tree, TaskPoolManager, :create_pool, [:test_pool, %{max_concurrency: 4}])
   ```

4. **Error Handling:**
   - Clear error messages for missing services
   - Timeout handling for long operations
   - Proper GenServer call/cast error propagation

5. **Integration with Test Helpers:**
   - Work with supervision context from `SupervisionTestSetup`
   - Compatible with existing `SupervisionTestHelpers`
   - Support for async operations with proper waiting

**Deliverables:**
- Complete `test/support/isolated_service_discovery.ex` file
- Transparent service access functions
- Error handling and timeout support
- Documentation with usage examples
- Integration with existing test infrastructure

---

p5 done

---

## PROMPT 6: Test Migration - Phase 1 (Basic Tests)

### Context Files to Read

**Implementation Guide:**
```
test/UNIFIED_TEST_FOUNDATION_buildDoc.md
```

**Complete Infrastructure:**
```
test/support/supervision_test_helpers.ex
test/support/supervision_test_setup.ex
test/support/unified_test_foundation.ex (enhanced)
test/support/isolated_service_discovery.ex
```

**Enhanced Services:**
```
lib/jido_foundation/task_pool_manager.ex (enhanced)
lib/jido_foundation/system_command_manager.ex (enhanced)
lib/jido_foundation/coordination_manager.ex (enhanced)
lib/jido_foundation/scheduler_manager.ex (enhanced)
```

**Current Test File:**
```
test/jido_foundation/supervision_crash_recovery_test.exs
```

**OTP Guidance:**
```
test/OTP_ASYNC_APPROACHES_20250701.md
test/TESTING_GUIDE_OTP.md
```

### Task

Migrate basic individual service crash recovery tests to use isolated supervision testing. **Create a backup first.**

**Requirements:**

1. **File Preparation:**
   ```bash
   cp test/jido_foundation/supervision_crash_recovery_test.exs \
      test/jido_foundation/supervision_crash_recovery_test.exs.backup
   ```

2. **Module Header Migration:**
   - Change from `use ExUnit.Case, async: false` to `use Foundation.UnifiedTestFoundation, :supervision_testing`
   - Update imports and aliases
   - Add `@moduletag :supervision_testing`

3. **Migrate These Tests First:**
   - `test "TaskPoolManager restarts after crash and maintains functionality"` (line 80)
   - `test "TaskPoolManager survives pool supervisor crashes"` (line 132)
   - `test "SystemCommandManager restarts after crash and maintains functionality"` (line 174)
   - `test "SystemCommandManager handles command execution failures gracefully"` (line 216)

4. **Test Pattern:**
   ```elixir
   test "TaskPoolManager restarts after crash and maintains functionality", 
        %{supervision_tree: sup_tree} do
     # Get service from isolated supervision tree
     {:ok, initial_pid} = get_service(sup_tree, :task_pool_manager)
     
     # Test with isolated service calls
     stats = call_service(sup_tree, TaskPoolManager, :get_all_stats)
     
     # ... rest of test logic
   end
   ```

5. **Service Call Conversion:**
   - Replace `TaskPoolManager.function()` with `call_service(sup_tree, TaskPoolManager, :function)`
   - Replace `Process.whereis(JidoFoundation.TaskPoolManager)` with `get_service(sup_tree, :task_pool_manager)`
   - Use `wait_for_service_restart/4` instead of manual waiting

**Deliverables:**
- Backup of original test file
- Migrated basic tests using isolated supervision
- Verification that migrated tests pass individually
- No regressions in test functionality
- Clear separation between migrated and unmigrated tests

---
6 done

---

## PROMPT 7: Test Migration - Phase 2 (Supervision Strategy Tests)

### Context Files to Read

**Implementation Guide:**
```
test/UNIFIED_TEST_FOUNDATION_buildDoc.md
```

**Previous Migration:**
```
test/jido_foundation/supervision_crash_recovery_test.exs (partially migrated)
test/jido_foundation/supervision_crash_recovery_test.exs.backup
```

**Complete Infrastructure:**
```
test/support/supervision_test_helpers.ex
test/support/supervision_test_setup.ex
test/support/unified_test_foundation.ex (enhanced)
test/support/isolated_service_discovery.ex
```

**JidoSystem Supervision Structure:**
```
lib/jido_system/application.ex
```

### Task

Migrate complex supervision strategy tests that verify `:rest_for_one` behavior and cross-supervisor crash recovery.

**Requirements:**

1. **Migrate These Tests:**
   - `test "JidoSystem supervisor children restart independently"` (line 293)
   - `test "Multiple simultaneous crashes don't bring down the system"` (line 355)
   - `test "Service failures cause proper dependent restarts with :rest_for_one"` (line 747)
   - `test "Error recovery workflow across all services"` (line 806)

2. **Complex Test Pattern:**
   ```elixir
   test "Service failures cause proper dependent restarts with :rest_for_one",
        %{supervision_tree: sup_tree} do
     # Monitor all services in isolated supervision tree
     monitors = monitor_all_services(sup_tree)
     
     # Kill service in isolated environment
     {task_pid, _} = monitors[:task_pool_manager]
     Process.exit(task_pid, :kill)
     
     # Verify rest_for_one cascade behavior
     verify_rest_for_one_cascade(monitors, :task_pool_manager)
   end
   ```

3. **Supervision Order Verification:**
   - Use the supervision order: `SchedulerManager → TaskPoolManager → SystemCommandManager → CoordinationManager`
   - Verify correct cascade behavior with `verify_rest_for_one_cascade/2`
   - Test both individual crashes and simultaneous crashes

4. **Process Monitoring:**
   - Use `monitor_all_services/1` for comprehensive monitoring
   - Replace manual `Process.monitor` with helper functions
   - Use `assert_receive` for deterministic DOWN message handling

5. **Service Discovery:**
   - Replace all `Process.whereis` calls with `get_service/2`
   - Use isolated service calls for functionality verification
   - Handle restart detection with `wait_for_service_restart/4`

**Deliverables:**
- Migrated complex supervision strategy tests
- Proper use of `monitor_all_services` and `verify_rest_for_one_cascade`
- Verification of `:rest_for_one` behavior in isolation
- All migrated tests pass individually
- Correct supervision cascade testing

---

p7 complete
---



## PROMPT 8: Test Migration - Phase 3 (Resource Management Tests)

### Context Files to Read

**Implementation Guide:**
```
test/UNIFIED_TEST_FOUNDATION_buildDoc.md
```

**Previous Migration:**
```
test/jido_foundation/supervision_crash_recovery_test.exs (mostly migrated)
test/jido_foundation/supervision_crash_recovery_test.exs.backup
```

**Complete Infrastructure:**
```
test/support/supervision_test_helpers.ex
test/support/supervision_test_setup.ex
test/support/unified_test_foundation.ex (enhanced)
test/support/isolated_service_discovery.ex
```

### Task

Migrate remaining resource management and cleanup tests to use isolated supervision testing.

**Requirements:**

1. **Migrate These Tests:**
   - `test "No process leaks after service crashes and restarts"` (line 421)
   - `test "ETS tables are properly cleaned up after crashes"` (line 482)
   - `test "Services shut down gracefully when supervisor terminates"` (line 530)
   - `test "Services maintain proper configuration after restarts"` (line 582)
   - `test "Service discovery works across restarts"` (line 650) - Already partially fixed

2. **Resource Leak Testing Pattern:**
   ```elixir
   test "No process leaks after service crashes and restarts", 
        %{supervision_tree: sup_tree} do
     initial_count = :erlang.system_info(:process_count)
     
     # Test crash/restart in isolated environment
     {:ok, task_pid} = get_service(sup_tree, :task_pool_manager)
     ref = Process.monitor(task_pid)
     Process.exit(task_pid, :kill)
     
     # Wait for restart in isolated supervision tree
     assert_receive {:DOWN, ^ref, :process, ^task_pid, :killed}, 1000
     {:ok, new_pid} = wait_for_service_restart(sup_tree, :task_pool_manager, task_pid)
     
     # Verify no leaks in isolated environment
     final_count = :erlang.system_info(:process_count)
     assert final_count - initial_count < 20
   end
   ```

3. **Configuration Persistence:**
   - Test service configuration in isolated environment
   - Verify service state after restart using isolated calls
   - Use `call_service/4` for configuration verification

4. **Graceful Shutdown:**
   - Test shutdown behavior in isolated supervision tree
   - Monitor process termination with proper timeout
   - Verify supervisor cleanup in test environment

5. **Service Discovery:**
   - Update the already-partially-fixed service discovery test
   - Use `get_service/2` for all service lookups
   - Verify service registration in test registry

**Deliverables:**
- Complete migration of all remaining tests
- Resource leak detection in isolated environment
- Configuration persistence testing with isolated services
- Graceful shutdown verification
- All tests using isolated supervision pattern

---
p8 complete

---

## PROMPT 9: Integration Verification and Optimization

### Context Files to Read

**Implementation Guide:**
```
test/UNIFIED_TEST_FOUNDATION_buildDoc.md
```

**Complete Migration:**
```
test/jido_foundation/supervision_crash_recovery_test.exs (fully migrated)
test/jido_foundation/supervision_crash_recovery_test.exs.backup
```

**All Infrastructure:**
```
test/support/supervision_test_helpers.ex
test/support/supervision_test_setup.ex
test/support/unified_test_foundation.ex (enhanced)
test/support/isolated_service_discovery.ex
```

**Enhanced Services:**
```
lib/jido_foundation/task_pool_manager.ex (enhanced)
lib/jido_foundation/system_command_manager.ex (enhanced)
lib/jido_foundation/coordination_manager.ex (enhanced)
lib/jido_foundation/scheduler_manager.ex (enhanced)
```

### Task

Perform comprehensive verification of the complete migration and optimize performance.

**Requirements:**

1. **Individual Test Verification:**
   ```bash
   # Test each migrated test individually
   for test_line in 80 132 174 216 234 264 293 355 421 482 530 582 650 747 806; do
     echo "Testing isolated line $test_line"
     mix test test/jido_foundation/supervision_crash_recovery_test.exs:$test_line
   done
   ```

2. **Batch Test Verification (KEY SUCCESS METRIC):**
   ```bash
   # This should now pass without EXIT shutdown errors
   mix test test/jido_foundation/supervision_crash_recovery_test.exs --seed 123456
   
   # Test multiple runs for stability
   for i in {1..5}; do
     echo "Batch test run $i"
     mix test test/jido_foundation/supervision_crash_recovery_test.exs
   done
   ```

3. **Performance Analysis:**
   ```bash
   # Compare performance before/after migration
   echo "=== Original (should fail) ==="
   time mix test test/jido_foundation/supervision_crash_recovery_test.exs.backup
   
   echo "=== Migrated (should pass) ==="
   time mix test test/jido_foundation/supervision_crash_recovery_test.exs
   ```

4. **Integration Testing:**
   - Verify all tests pass both individually and in batch
   - Confirm no test contamination between runs
   - Validate proper resource cleanup
   - Check for any remaining `Process.sleep` anti-patterns

5. **Optimization Tasks:**
   - Identify any performance bottlenecks in supervision setup
   - Optimize service startup time in test environment
   - Reduce test execution time while maintaining correctness
   - Ensure proper memory cleanup

6. **Documentation Updates:**
   - Add usage examples to module documentation
   - Update any test-related documentation
   - Create migration guide for future supervision tests

**Deliverables:**
- ✅ All 15 tests pass individually
- ✅ All 15 tests pass in batch (eliminating EXIT shutdown)
- ✅ Performance similar or better than original
- ✅ Zero test contamination
- ✅ Complete resource cleanup
- ✅ Documentation updates
- 📊 Performance comparison report

---

9 done


---







## PROMPT 10: Final Documentation and Cleanup

### Context Files to Read

**Implementation Guide:**
```
test/UNIFIED_TEST_FOUNDATION_buildDoc.md
```

**Complete Implementation:**
```
test/jido_foundation/supervision_crash_recovery_test.exs (verified working)
test/support/supervision_test_helpers.ex
test/support/supervision_test_setup.ex
test/support/unified_test_foundation.ex (enhanced)
test/support/isolated_service_discovery.ex
```

**Enhanced Services:**
```
lib/jido_foundation/task_pool_manager.ex (enhanced)
lib/jido_foundation/system_command_manager.ex (enhanced)
lib/jido_foundation/coordination_manager.ex (enhanced)
lib/jido_foundation/scheduler_manager.ex (enhanced)
```

**Verification Results from Previous Prompt**

### Task

Create comprehensive documentation, cleanup temporary files, and establish patterns for future supervision testing.

**Requirements:**

1. **Success Metrics Documentation:**
   Create `test/SUPERVISION_MIGRATION_RESULTS.md` with:
   - Before/after test behavior comparison
   - Performance metrics
   - Test isolation verification
   - Resource usage analysis

2. **Usage Guide Creation:**
   Create `test/SUPERVISION_TESTING_GUIDE.md` with:
   - How to write new supervision tests using isolated patterns
   - Best practices for supervision testing
   - Common patterns and utilities
   - Migration guide from global to isolated testing

3. **Code Documentation:**
   - Add comprehensive module docs to all created files
   - Include usage examples in function documentation
   - Add type specs where appropriate
   - Document any limitations or considerations

4. **Cleanup Tasks:**
   ```bash
   # Remove backup file if tests are stable
   rm test/jido_foundation/supervision_crash_recovery_test.exs.backup
   
   # Verify no temporary files left
   find test/ -name "*.backup" -o -name "*.tmp"
   ```

5. **Integration with CI/CD:**
   - Ensure new tests work in CI environment
   - Update any CI-specific test configurations
   - Verify test isolation doesn't break parallel execution
   - Document any CI-specific considerations

6. **Future Testing Patterns:**
   - Document how to create new supervision tests
   - Provide template for supervision crash recovery testing
   - Establish patterns for other types of OTP testing
   - Integration guidelines with existing test suites

**Deliverables:**
- `test/SUPERVISION_MIGRATION_RESULTS.md` - Success metrics and analysis
- `test/SUPERVISION_TESTING_GUIDE.md` - Usage guide for future tests
- Complete documentation in all created modules
- Cleanup of temporary files
- CI/CD integration verification
- Template and patterns for future supervision testing

 


 ---



   ● PROMPT 11: Complete Sleep Anti-Pattern Migration - Remaining Medium & Low Priority Files

  Context Files to Read

  Sleep Audit Report:
  test/SLEEP_AUDIT_202507011900.md

  Migration Infrastructure & Patterns (Proven):
  test/20250701_MOCK_LIB_AND_MIGRATION_PATTERNS.md (Complete migration guide)
  test/support/test_process.ex (Foundation.TestProcess mock library)
  test/support/unified_test_foundation.ex (:supervision_testing mode)
  test/support/supervision_test_helpers.ex (wait_for patterns)
  test/support/async_test_helpers.ex (polling mechanisms)

  Successfully Migrated Reference Cases:
  test/foundation/monitor_manager_test.exs (✅ Complete - zero anti-patterns)
  test/jido_system/agents/task_agent_test.exs (✅ Complete - telemetry-based)
  test/foundation/batch_operations_test.exs (✅ Complete - TestProcess mocks)
  test/jido_foundation/supervision_crash_recovery_test.exs (✅ Complete reference)

  Medium-Priority Migration Targets (Category B - 35 files remaining):
  test/foundation/serial_operations_test.exs (Infinity sleep spawns)
  test/foundation/atomic_transaction_test.exs (Process placeholders)
  test/foundation/connection_manager_test.exs (Network timing)
  test/foundation/health_monitor_test.exs (Health check delays)
  test/foundation/resource_pool_test.exs (Pool coordination)
  test/foundation/circuit_breaker_test.exs (Failure simulation)
  test/foundation/rate_limiter_test.exs (Rate limiting waits)
  test/foundation/cache_manager_test.exs (Cache invalidation)
  test/jido_system/workflow_executor_test.exs (Workflow coordination)
  test/jido_system/state_machine_test.exs (State transitions)

  Low-Priority Migration Targets (Category C - 12 files remaining):
  test/foundation/telemetry_collector_test.exs (Metric collection delays)
  test/foundation/event_dispatcher_test.exs (Event propagation)
  test/foundation/registry_cluster_test.exs (Cluster coordination)
  test/foundation/distributed_lock_test.exs (Lock acquisition)

  Task

  Complete the remaining 49% of sleep anti-pattern migrations using the proven Foundation.TestProcess infrastructure and established patterns.

  Requirements:

  1. Phase 1: Medium-Priority Batch Migration (Target: 15 files):
     # Test current state for flakiness
     mix test test/foundation/serial_operations_test.exs --seed 987654
     mix test test/foundation/atomic_transaction_test.exs --seed 987654
     mix test test/foundation/connection_manager_test.exs --seed 987654

     # Batch stability check
     for file in serial_operations atomic_transaction connection_manager; do
       echo "Testing $file stability"
       mix test test/foundation/${file}_test.exs
     done

  2. Migration Implementation Using Proven Patterns:
     - Apply patterns from test/20250701_MOCK_LIB_AND_MIGRATION_PATTERNS.md
     - Use Foundation.TestProcess for all infinity sleep replacements
     - Replace Process.sleep with wait_for patterns from AsyncTestHelpers
     - Apply Foundation.UnifiedTestFoundation :supervision_testing mode
     - Use telemetry-based async testing where applicable

  3. Pattern Application Examples:
     # BEFORE: spawn(fn -> :timer.sleep(:infinity) end)
     # AFTER: {:ok, pid} = Foundation.TestProcess.start_link()

     # BEFORE: Process.sleep(50)
     # AFTER: wait_for(fn -> condition_met?() end, 2000)

     # BEFORE: :timer.sleep(100)
     # AFTER: Use telemetry-based waiting from TaskAgentTestHelpers

  4. Batch Processing Strategy:
     # Process files in groups of 5 for manageable verification
     GROUP_1="serial_operations atomic_transaction connection_manager health_monitor resource_pool"
     GROUP_2="circuit_breaker rate_limiter cache_manager workflow_executor state_machine"
     GROUP_3="telemetry_collector event_dispatcher registry_cluster distributed_lock"

     # Migrate each group and verify before proceeding
     for group in GROUP_1 GROUP_2 GROUP_3; do
       echo "Migrating group: $group"
       # Apply migrations
       # Verify all tests pass
       # Check stability
     done

  5. Comprehensive Post-Migration Verification:
     # Verify zero anti-patterns across all files
     find test/ -name "*_test.exs" -exec grep -l "Process.sleep\|:timer.sleep(:infinity)" {} \; || echo "✅ All clean"

     # Batch test all migrated files
     mix test test/foundation/ test/jido_system/ --exclude slow

     # Performance comparison (key metric)
     echo "=== Performance Analysis ==="
     time mix test test/foundation/ --exclude slow

     # Stability verification across random seeds
     for seed in 111111 222222 333333 444444 555555; do
       echo "Stability test with seed $seed"
       mix test test/foundation/ --seed $seed --exclude slow --max-failures 1
     done

  6. Final Anti-Pattern Elimination Audit:
     # Generate updated audit report
     ./scripts/audit_sleep_patterns.sh > test/SLEEP_AUDIT_FINAL_202507.md

     # Should show 0% anti-patterns remaining
     grep "Category B" test/SLEEP_AUDIT_FINAL_202507.md || echo "✅ All Category B eliminated"

  Deliverables:
  - ✅ All 47 remaining test files migrated (49% of original anti-patterns)
  - ✅ Foundation.TestProcess used consistently across all infinity sleep replacements
  - ✅ Zero Process.sleep and :timer.sleep(:infinity) anti-patterns remaining
  - ✅ All tests pass individually and in comprehensive batch mode
  - ✅ Performance maintained or improved (target: <10% time increase, >95% reliability)
  - ✅ Zero test contamination verified across multiple seed runs
  - ✅ Complete resource cleanup verified (no process leaks)
  - 📊 Final audit report showing 0% anti-patterns remaining
  - 📋 Migration completion metrics (files processed, reliability achieved, performance impact)
  - 📚 Updated migration patterns documentation with lessons learned

  Success Criteria:
  - Follow all patterns from test/20250701_MOCK_LIB_AND_MIGRATION_PATTERNS.md
  - Achieve 99%+ test reliability across entire Foundation test suite
  - Eliminate 100% of Category B and Category C anti-patterns
  - Maintain test execution performance within 10% of original times
  - Zero flaky test failures in comprehensive CI/CD pipeline
  - Complete Foundation test suite ready for production deployment

  Advanced Deliverables:
  - 🔄 CI/CD integration script to prevent sleep anti-pattern regressions
  - 📊 Comprehensive performance analysis comparing before/after metrics
  - 🎯 Test reliability dashboard showing Foundation test health
  - 📖 Best practices guide for future test development

  The key changes in PROMPT 11:
  1. References the comprehensive migration guide you created
  2. Builds upon the proven Foundation.TestProcess infrastructure
  3. Targets the remaining 49% of files identified in the audit
  4. Uses batch processing strategy for manageable implementation
  5. Includes comprehensive verification for production readiness
  6. Focuses on eliminating ALL remaining anti-patterns (Categories B & C)
  7. Emphasizes proven patterns from the successful migrations