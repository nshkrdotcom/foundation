
# Performance Testing Discussion Points

This document outlines key strategic points for discussion to improve our performance testing framework. The goal is to move from fixing individual test issues to establishing a robust, reliable, and insightful performance testing strategy.

### 1. Memory Testing: From Reclamation to Leak Detection

*   **Current State:** Our tests focus on immediate memory reclamation after cleanup, using imprecise global measurements. This is flaky and doesn't reflect the BEAM's GC behavior.
*   **Discussion Point:** Should we shift our focus from asserting memory *reclamation* to detecting memory *leaks*? We could adopt a model where we run a process or ecosystem through multiple cycles and assert that its baseline memory usage remains stable, allowing for a small, acceptable overhead.

### 2. Latency & Throughput: Adopting a Statistical Standard

*   **Current State:** We use manual timing (`:timer.tc`, `System.monotonic_time`), which provides only an average and is susceptible to noise.
*   **Discussion Point:** I propose we standardize on the `Benchee` library for all latency and throughput testing. This would give us statistically sound metrics like mean, median, and percentiles. Do we agree, and what should our primary SLO metric be (e.g., 99th percentile)?

### 3. Test Reliability: Eliminating Sleeps and Polling

*   **Current State:** Our tests are littered with `Process.sleep` and polling helpers (`assert_eventually`) to wait for asynchronous events. This makes tests slow and unreliable.
*   **Discussion Point:** Can we commit to an event-driven testing paradigm? This would involve using process monitors and explicit messages to deterministically await outcomes, making our tests faster and removing race conditions. What is our strategy to refactor existing tests to follow this model?

### 4. Test Realism: Simulating Real-World Workloads

*   **Current State:** Our test workers are empty `GenServer`s. Our performance tests measure process overhead, not behavior under actual load.
*   **Discussion Point:** How can we define a set of standard, representative workloads (e.g., CPU-intensive, memory-intensive, I/O-bound) for our test workers? This would allow us to test how our systems perform under conditions that more closely resemble production.

### 5. Fault Tolerance: Measuring Recovery Time (TTR)

*   **Current State:** Our fault-tolerance tests confirm that the system *survives* a crash, but not how *quickly* it recovers.
*   **Discussion Point:** Should we define and test a "Time to Recover" (TTR) SLO? For example, we could assert that after a critical process crashes, the system is fully operational again within a specific, aggressive timeframe (e.g., 500ms).

### 6. Scalability: Defining a Clear Performance Model

*   **Current State:** Our scaling test uses a very loose and arbitrary scaling factor (`* 10`).
*   **Discussion Point:** We need to define a clear performance model for our core components. Should we assert near-linear scalability (e.g., a scaling factor of 1.5-2x) and treat deviations as a P1 bug? This would force us to address architectural bottlenecks proactively.

### 7. Test Suite Optimization: Maximizing Parallelism

*   **Current State:** The entire performance test file runs serially (`async: false`), slowing down the feedback loop.
*   **Discussion Point:** What is our process for auditing and refactoring our test suites to enable maximum parallelism? We should aggressively isolate tests with shared state so that `async: true` can be the default for all new tests.

### 8. Back-Pressure and Overload Behavior

*   **Current State:** We only test with small, controlled bursts of messages.
*   **Discussion Point:** We have no insight into how the system behaves under sustained load or when message queues begin to grow. Should we develop a standard suite of stress tests to identify how our systems handle overload and back-pressure?

### 9. Configuration and Environment Consistency

*   **Current State:** Performance tests may be run in inconsistent local or CI environments, leading to noisy and unreliable results.
*   **Discussion Point:** How do we establish a standardized, containerized environment (e.g., using Docker) for all performance tests? This would ensure that results are reproducible and comparable over time by controlling variables like OS, library versions, and resource allocation.

### 10. CI/CD Integration and Performance Budgeting

*   **Current State:** Performance tests are run manually or on a schedule, but they don't automatically prevent regressions from being merged.
*   **Discussion Point:** Should we integrate performance tests directly into the pull request workflow? We could define a "performance budget" (e.g., "p99 latency must not increase by more than 5%") that, if exceeded, would fail the build and block the merge.

### 11. Benchmarking Against Production Metrics

*   **Current State:** Our test scenarios are based on developer assumptions, not real-world usage patterns.
*   **Discussion Point:** Can we create a feedback loop from our production observability platform (e.g., Prometheus, Datadog) into our testing framework? This would allow us to generate test workloads that mirror actual user behavior and validate our performance against production realities.

### 12. Data Generation for Performance Tests

*   **Current State:** Tests use small, simplistic data sets that may not trigger edge cases related to data size and shape.
*   **Discussion Point:** What is our strategy for generating realistic, large-scale data for performance tests? Should we invest in a dedicated data generation library or service that can create varied and production-like datasets on demand?

### 13. Performance of the Test Suite Itself

*   **Current State:** We don't monitor the performance of our test suite. Slow tests hinder developer productivity and can mask regressions in the application itself.
*   **Discussion Point:** Should we implement tooling to monitor and report on the execution time of our test suite? We could set SLOs for the test suite itself to ensure it remains fast and efficient.

### 14. Visualizing Performance Trends

*   **Current State:** Performance test results are ephemeral, logged only in the output of a specific CI run.
*   **Discussion Point:** How can we store and visualize performance metrics over time? A dashboard showing trends in latency, memory usage, and other key metrics would allow us to spot gradual degradations that might be missed by individual test runs.

### 15. Defining "Performance Bug" Severity

*   **Current State:** There is no clear, shared definition of what constitutes a performance bug, leading to inconsistent prioritization.
*   **Discussion Point:** Can we establish a formal system for classifying performance regressions (e.g., P0-P3) based on their user impact and the magnitude of the regression? This would create a shared understanding and ensure that critical performance issues are addressed promptly.
