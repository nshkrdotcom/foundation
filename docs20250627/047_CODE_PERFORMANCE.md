
# Code Performance Testing Technical Specification

## 1. Introduction

This document outlines the technical specification for performance test design within the Foundation project. The goal is to create a robust and reliable framework for performance testing that produces meaningful and actionable results. This will help us avoid flaky tests, accurately identify performance regressions, and ensure the system meets its performance targets.

## 2. Guiding Principles

*   **Isolate and Measure with Precision:** Performance tests must measure the specific component under test, avoiding noise from unrelated system activity.
*   **Realistic Scenarios:** Tests should reflect realistic usage patterns and workloads.
*   **Statistical Rigor:** Performance metrics should be analyzed statistically to distinguish true regressions from random fluctuations.
*   **Actionable Failures:** Test failures should provide clear, actionable information to developers.

## 3. Performance Test Design Framework

### 3.1. Test Structure

All performance tests should follow a consistent structure:

1.  **Setup:** Initialize the system to a known baseline state. This includes starting necessary services and warming up caches.
2.  **Measurement:** Execute the code under test and measure the relevant performance metrics.
3.  **Teardown:** Clean up any resources created during the test.
4.  **Analysis:** Compare the measured metrics against a baseline or a predefined threshold.

### 3.2. Memory Testing

*   **Measure Process Memory, Not System Memory:** When testing the memory usage of a specific process or set of processes, use `Process.info(pid, :memory)` to get the memory usage of that specific process. Avoid using `:erlang.memory(:total)` which is too broad and susceptible to noise.
*   **Account for Garbage Collection:** The BEAM's garbage collector can introduce variability. To mitigate this:
    *   Force garbage collection before and after the measurement phase using `:erlang.garbage_collect()`.
    *   Introduce a small `Process.sleep()` after garbage collection to allow the collector to run.
*   **Use Statistical Baselines:** Instead of asserting a fixed reduction in memory, establish a baseline memory usage for the component under test. The test should then assert that the memory usage does not exceed the baseline by a statistically significant margin.
*   **Example:**

    ```elixir
    test "component memory usage does not grow over time" do
      # 1. Setup and warm-up
      {:ok, pid} = Component.start_link()
      :erlang.garbage_collect(pid)
      Process.sleep(10)
      {:memory, initial_memory} = Process.info(pid, :memory)

      # 2. Run workload
      for _ <- 1..100 do
        Component.do_work(pid)
      end

      # 3. Measure final memory
      :erlang.garbage_collect(pid)
      Process.sleep(10)
      {:memory, final_memory} = Process.info(pid, :memory)

      # 4. Analysis
      memory_growth = final_memory - initial_memory
      assert memory_growth < 1024 * 10 # Allow for 10KB growth
    end
    ```

### 3.3. Latency and Throughput Testing

*   **Use Benchmarking Tools:** For latency and throughput testing, use dedicated benchmarking tools like `Benchee`. These tools provide statistical analysis of the results, making them more reliable than manual timing.
*   **Define Service Level Objectives (SLOs):** Each performance test should have a clear SLO. For example, "the 99th percentile latency for API endpoint X should be less than 100ms".
*   **Isolate External Dependencies:** When testing the performance of a specific component, mock or stub any external dependencies to avoid network latency and other external factors from influencing the results.

### 3.4. Property-Based Performance Testing

Property-based testing can be a powerful tool for performance testing, but it requires careful design:

*   **Focus on Relative Properties:** Instead of asserting absolute performance numbers, focus on relative properties. For example, "doubling the workload should not more than double the execution time".
*   **Model Realistic Behavior:** The properties should model the expected performance behavior of the system. Avoid overly simplistic or aggressive assertions.
*   **Use Statistical Assertions:** Instead of a simple `assert`, use statistical methods to verify the property. For example, you could collect multiple measurements and assert that the mean or median falls within an acceptable range.

## 4. Review and Maintenance

Performance tests should be reviewed regularly to ensure they remain relevant and reliable. When a performance test fails, the first step should be to analyze the test itself for flaws before investigating the code under test.
