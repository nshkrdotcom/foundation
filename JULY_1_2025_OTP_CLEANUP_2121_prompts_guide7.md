Of course. Here is a guide for Prompt 7, summarizing the outcomes of Prompts 1-6 and outlining exactly what needs to be checked and cleaned up in the test suite.

---

### A Guide for Prompt 7: Cleaning Up Test Anti-Patterns

**Objective**: To eliminate all `Process.put/get` usage from the `test/` directory by replacing it with modern, reliable OTP testing patterns.

This guide provides the necessary context from the refactoring work done in Prompts 1-6. The test suite currently relies on the Process Dictionary (`pdict`) to "peek" into the internal state of modules, set up test conditions, and coordinate asynchronous events. Now that the underlying implementations have been refactored, these tests must be updated to use proper APIs and message-passing techniques.

### Summary of Changes from Prompts 1-6

Here is what was changed in the `lib/` directory and why it impacts the tests:

| Prompt | Component Refactored | Old Anti-Pattern (in `lib/`) | New OTP Pattern (in `lib/`) | **Testing Implication for Prompt 7** |
| :--- | :--- | :--- | :--- | :--- |
| **1: Credo** | CI/CD Enforcement | No enforcement for `pdict`. | Custom `NoProcessDict` Credo check added. | The ultimate goal is to remove the test-related `pdict` usage so we can enable this check globally. |
| **2: Foundation Registry** | `lib/foundation/protocols/registry_any.ex` | `Process.put(:registered_agents, ...)` | `GenServer` with an ETS table (`RegistryETS`). | Tests likely assert registry state with `Process.get(:registered_agents)`. This must be replaced with API calls like `Foundation.Registry.lookup/1`. |
| **3: MABEAM Cache** | `lib/mabeam/agent_registry_impl.ex` | `Process.put(cache_key, ...)` | A new `MABEAM.TableCache` module with TTL. | Tests may use `pdict` to prime or check the cache. This must be replaced with API calls and proper setup/teardown. |
| **4. Error Context** | `lib/foundation/error_context.ex` | `Process.put(:error_context, ...)` | `Logger.metadata` for context storage. | Tests use `pdict` to set up and verify error context. This must be replaced with calls to the `ErrorContext` API and checks on `Logger.metadata`. |
| **5: Telemetry Events** | `lib/foundation/telemetry/sampled_events.ex`| `Process.get({:telemetry_dedup, ...})` and `Process.get(batch_key, ...)` | `GenServer`/ETS for deduplication and batching state. | Tests likely use `pdict` to simulate previous events for deduplication checks. This must be replaced with message-passing or state-setup calls to the new GenServer. |
| **6: Telemetry Spans** | `lib/foundation/telemetry/span.ex` | `Process.put(@span_stack_key, ...)` | Per-process span stacks managed in ETS. | Tests for nested spans directly manipulate the `pdict` stack. This must be replaced with calls to the public `Span` API. |

### Consolidated Guide for Refactoring Tests

Based on the changes above, the `pdict` usage in your `test/` directory falls into two main anti-patterns: **State Inspection/Manipulation** and **Asynchronous Coordination**.

#### 1. Anti-Pattern: State Inspection/Manipulation

This is the most common anti-pattern, where tests use `pdict` to bypass public APIs and directly check or set internal state.

**What to look for:**
*   `assert Process.get(:registered_agents) == ...` in registry tests.
*   `Process.put(cache_key, ...)` to set up a cache state for a test.
*   `assert Process.get(@span_stack_key) == ...` to check the telemetry span stack.

**How to fix it:**
*   **Use Public APIs**: Replace `Process.get` assertions with calls to the module's public functions (`Foundation.Registry.lookup/1`, `Foundation.Telemetry.Span.current_span/0`, etc.).
*   **Proper Setup**: Replace `Process.put` setups with calls to the module's state-changing functions (`Foundation.Registry.register/3`, etc.) inside `setup` blocks.

#### 2. Anti-Pattern: Asynchronous Coordination

This pattern uses the `pdict` as a shared flag between the main test process and an asynchronous process (like a `Task` or a a `telemetry` event handler) to signal that an event has occurred.

**What to look for:**
*   A telemetry handler function doing `Process.put(:event_received, true)`.
*   The test process doing a `wait_for` loop that repeatedly calls `Process.get(:event_received)`.
*   Using `pdict` to pass a value from an async callback back to the main test process.

**How to fix it:**
*   **Use Message Passing**: This is the correct OTP pattern. The test process should `assert_receive` a message sent from the async handler.
*   **The `self()` Pattern**: The test process (`self()`) is the coordinator. Pass `self()` to the code that will eventually trigger the async event. The async handler then uses that PID to `send` a message back.
*   **Create Test Helpers**: Build helpers in `test/support/async_test_helpers.ex` to make this pattern clean and reusable.

### Actionable Tasks for Prompt 7

Based on this guide, here are the concrete steps to take:

1.  **Audit All Test Files**: Systematically go through every file in `test/` and identify every instance of `Process.put` and `Process.get`. Categorize each usage as either "State Inspection" or "Async Coordination".

2.  **Create `test/support/async_test_helpers.ex`**: This is your new toolkit.
    *   **`wait_for/2`**: A function that waits for a condition to be true, but *without* using `pdict`. It should use message passing or polling with a timeout.
    *   **`assert_receive_event/3`**: A helper for telemetry tests. It should attach a temporary handler that sends a message like `{:telemetry_event, event, measurements, metadata}` to the test process (`self()`), and then use `assert_receive` to match on it. This replaces the `Process.put(:event_received, true)` pattern.

3.  **Refactor Telemetry Tests (Prompts 5 & 6)**: This is the most critical part of the cleanup.
    *   Modify tests for `SampledEvents` and `Span`.
    *   Replace `Process.get` checks with `assert_receive_event`.
    *   Ensure tests for deduplication and batching now interact with the new `GenServer`/ETS implementation, likely through synchronous API calls for setup and assertions.

4.  **Refactor Registry and Cache Tests (Prompts 2 & 3)**:
    *   Remove all `Process.get/put` calls related to `:registered_agents` and MABEAM cache keys.
    *   Use `Foundation.Registry.register/3` and `Foundation.Registry.lookup/1` for setup and assertions.
    *   Create tests for both states of the `use_ets_agent_registry` feature flag to ensure both the legacy `pdict` and new ETS paths work correctly.

5.  **Refactor ErrorContext Tests (Prompt 4)**:
    *   Remove `Process.get/put` on `:error_context`.
    *   Use the `Foundation.ErrorContext.set_context/1` and `get_context/0` APIs.
    *   In tests, you might need to check `Logger.metadata` directly to confirm the new implementation works.
    *   Test both states of the `use_logger_error_context` feature flag.

By following this guide, you will systematically eliminate the test anti-patterns and align the test suite with modern OTP practices, making it more reliable, deterministic, and maintainable.