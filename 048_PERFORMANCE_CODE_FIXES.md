# Performance Code Fixes

This document outlines performance-related issues found in `test/property/foundation/beam/processes_properties_test.exs` and provides concise recommendations for each.

1.  **Brittle Memory Assertion**
    The test asserts a fixed 50% memory reduction, which is unreliable. Replace this with a baseline comparison that allows for minor, stable memory overhead.

2.  **Inaccurate Global Memory Measurement**
    The test uses `:erlang.memory(:total)`, which is noisy. It should measure process-specific memory with `Process.info(pid, :memory)` for accuracy.

3.  **Manual Latency Timing**
    The message response test uses manual timing, which is imprecise. It should be replaced with a statistical benchmarking library like Benchee.

4.  **Inefficient Polling in Helpers**
    `TestHelpers.assert_eventually` likely uses an inefficient polling loop. Replace its usage with event-driven checks using monitors and `assert_receive`.

5.  **Arbitrary `Process.sleep(1)` for GC**
    A 1ms sleep is not guaranteed to be sufficient for GC to complete. Use a more reliable mechanism or a longer, configurable sleep time.

6.  **Global `async: false`**
    The entire test file runs sequentially, slowing down the suite. Isolate tests that require sequential execution and enable `async: true` for all others.

7.  **Ineffective Fault-Tolerance Timing**
    The crash-test property checks for survival but not recovery time. It should assert that the system is fully recovered within a defined SLO.

8.  **Unrealistic Worker Load**
    The test workers perform no meaningful work, measuring only process overhead. They should simulate a more realistic workload for valuable metrics.

9.  **Arbitrary Scaling Factor**
    The creation time test uses a lenient `* 10` scaling factor. This should be a tighter, more statistically justified bound (e.g., `* 2` for near-linear).

10. **No Back-Pressure Testing**
    The message response test sends a single burst of messages. It should also test system performance under sustained load and with growing message queues.

11. **Hardcoded `max_runs`**
    The number of runs for each property is hardcoded. This should be configurable to allow for quick developer runs and more thorough CI checks.

12. **Inefficient Cleanup Fallback**
    The `cleanup_ecosystem` function has a slow manual fallback. The primary `shutdown_ecosystem` function should be made robust enough to not need it.

13. **Overly Lenient Timeouts**
    Many tests use generous, fixed timeouts (e.g., `2000ms`). These should be tightened to the maximum expected response time to fail faster.