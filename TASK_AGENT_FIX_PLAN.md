# TaskAgent Test Fix Plan - Eliminating Timing Dependencies

## The Problem

The TaskAgent test file has 8 instances of `poll_with_timeout` which is just Process.sleep in disguise. This creates:
- Flaky tests that fail under load
- Slow test execution (polling for up to 8 seconds in some cases!)
- False confidence - tests pass by luck, not correctness

## The Solution Pattern

### For Each Test Using poll_with_timeout:

1. **Identify what state change we're waiting for**
   - Error count increase
   - Status change (paused/idle/processing)
   - Queue size change
   - Metrics update

2. **Replace with proper OTP patterns**:
   - Use telemetry events where available
   - Add synchronous test APIs where needed
   - Use GenServer.call for synchronous operations
   - Use monitors/links for process lifecycle

3. **Test Helper Functions Needed**:
   - `process_task_and_wait/3` - Already created, uses telemetry
   - `process_invalid_task_and_wait/3` - Already created
   - `pause_and_confirm/2` - Already created
   - `resume_and_confirm/2` - Already created
   - `get_metrics_sync/1` - Need to create
   - `get_queue_size_sync/1` - Need to create
   - `wait_for_agent_ready/2` - Need to create

## Specific Fixes Required

### 1. "successfully initializes with correct capabilities" test (line 39)
- Polling for: Agent process to be alive
- Fix: Use Process.monitor and assert_receive {:DOWN...} pattern

### 2. "respects paused status" test (line 177)
- Polling for: No processing to occur while paused
- Fix: Already partially fixed, need to complete

### 3. "queues tasks with different priorities" test (line 227)
- Polling for: Queue to contain expected tasks
- Fix: Need synchronous queue inspection API

### 4. "respects queue size limits" test (line 270)
- Polling for: Queue to stabilize at max size
- Fix: Need synchronous queue size API

### 5. "tracks performance metrics correctly" test (line 324)
- Polling for: Metrics to be updated
- Fix: Need synchronous metrics API

### 6. "provides status information" test (line 358)
- Polling for: Status to change to idle
- Fix: Use telemetry or add status change notification

### 7. "handles processing errors gracefully" test (line 410)
- Polling for: Error count to increase
- Fix: Use process_invalid_task_and_wait helper

### 8. "pauses after too many errors" test (line 465)
- Polling for: Auto-pause after 10 errors
- Fix: Use telemetry for pause event

## Implementation Steps

1. First, add the missing test helper functions
2. Then systematically replace each poll_with_timeout usage
3. Run tests after each fix to ensure they still pass
4. Measure test execution time before/after to show improvement

## Expected Results

- Tests run in milliseconds instead of seconds
- No more timing-dependent failures
- Clear, deterministic test behavior
- Better understanding of actual system behavior