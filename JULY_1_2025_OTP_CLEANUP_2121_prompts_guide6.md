Of course. Based on the provided codebase and the context of `PROMPT 6`, here are the two documents you requested.

---

### Document 1: Distributed Tracing Patterns and Span Context Management

This document provides a conceptual overview of distributed tracing and context management, tailored to the problem of refactoring `foundation/telemetry/span.ex`.

#### 1. What is Distributed Tracing?

Distributed tracing allows you to follow a single request or operation as it travels through multiple services, processes, and components in your system. It's essential for debugging, performance analysis, and understanding complex system behavior.

**Key Concepts:**

*   **Trace:** The complete journey of a request. A trace is a collection of all the spans related to a single operation. It is identified by a unique `Trace ID`.
*   **Span:** A single, named, timed unit of work within a trace. A span represents an operation like an HTTP call, a database query, or a function execution. It has a `Span ID`, a `Trace ID`, a start time, and a duration.
*   **Parent-Child Relationship:** Spans can be nested to represent sub-operations. A span that initiates another operation is the **parent**, and the new operation's span is the **child**. This relationship is maintained by storing the `Parent Span ID` in the child span.
*   **Span Context:** This is the critical piece of information that ties everything together. It typically includes:
    *   `Trace ID`: Shared by all spans in the same trace.
    *   `Span ID`: Unique identifier for the current span.
    *   `Parent Span ID`: The ID of the parent span, linking the child to its parent.

#### 2. The Problem of Span Context Management

Within a single Elixir process, if you have nested operations, you need a way to manage the "current" active span. This is what the `span stack` is for.

*   When `operation_A` starts, its span is pushed onto the stack. `current_span` is now `span_A`.
*   If `operation_A` calls `operation_B`, `span_B` is started. It sees `span_A` as its parent and is pushed onto the stack. `current_span` is now `span_B`.
*   When `operation_B` finishes, its span is popped off the stack. `current_span` is `span_A` again.
*   When `operation_A` finishes, its span is popped, and the stack is empty.

#### 3. Why the Current `Process` Dictionary Approach is Flawed

The existing implementation in `foundation/telemetry/span.ex` uses the `Process` dictionary (`Process.put/get`) to store this span stack. This is a well-known OTP anti-pattern for several reasons:

*   **Invisible State:** The state is hidden inside the process and is not part of the formal `GenServer` state. This makes debugging difficult, as the state doesn't appear in `sys.get_state/1` or crash reports.
*   **No Supervision or Cleanup:** If a process crashes while it has spans in its process dictionary, that data is lost, but more importantly, there is no supervisor mechanism to observe or clean up related resources. If spans were managed by a central process, that manager could monitor the client process and clean up its data upon exit.
*   **Testing Difficulties:** It's very difficult to test code that relies on the process dictionary. You have to set up the pdict state before calling the function and then inspect it afterward, which is brittle and couples tests to implementation details.
*   **Bypasses OTP Principles:** It sidesteps the explicit state management and message-passing paradigms that make OTP robust.

#### 4. The Recommended ETS + GenServer Pattern

The prompt suggests migrating to a `GenServer` and `ETS` table pattern. This is the correct, modern OTP approach.

*   **GenServer (`SpanManager`):** A single, supervised `GenServer` acts as the coordinator. It is responsible for monitoring processes that have active spans.
*   **ETS Table:** A single ETS table, owned by the `SpanManager`, stores the span stacks.
    *   **Key:** The Process ID (PID) of the worker process.
    *   **Value:** The stack of spans for that specific process (e.g., `[span_B, span_A]`).
*   **Process Monitoring:**
    1.  When a process (`PID_A`) starts its first span, the `SpanManager` is notified.
    2.  The `SpanManager` calls `Process.monitor(PID_A)`.
    3.  If `PID_A` dies for any reason, the `SpanManager` will receive a `:DOWN` message.
    4.  Upon receiving the `:DOWN` message, the `SpanManager` can safely delete the entry for `PID_A` from the ETS table, preventing memory leaks.

This pattern solves all the problems of the process dictionary: state is explicit (in ETS), centrally managed, and automatically cleaned up, making the system far more robust and observable.

---

### Document 2: Review of Existing Span Usage (`foundation/telemetry/span.ex`)

This document analyzes the current implementation in `foundation/telemetry/span.ex` as requested.

#### 1. High-Level Overview

The `Foundation.Telemetry.Span` module provides a way to create and manage distributed tracing spans. It uses a **process-local stack** to handle nested spans. Its primary functions are to start, end, and add context to spans, emitting `:telemetry` events at each lifecycle stage.

The **central architectural problem** is its complete reliance on the `Process` dictionary for managing the span stack, identified by the module attribute `@span_stack_key`.

#### 2. Key Function Analysis

**`with_span/3` (Macro)**
This is the main public-facing API. It correctly wraps a code block in a `try...rescue...catch` block to ensure that a span is always ended, even if the code inside raises an error.

*   It calls `start_span/2` before executing the user's code.
*   It calls `end_span/2` after the code executes, correctly passing `:ok` or `:error` status.
*   This macro's external behavior should be preserved in the refactor.

**`start_span/2`**
This function is responsible for creating a new span and pushing it onto the stack.

*   **Problematic Code:**
    ```elixir
    stack = Process.get(@span_stack_key, [])
    Process.put(@span_stack_key, [span | stack])
    ```
*   **Logic:**
    1.  It gets the current parent span by calling `current_span()`, which also reads from the process dictionary.
    2.  It creates a new `span` map containing an `id`, `name`, `start_time`, `parent_id`, and `trace_id`.
    3.  It **reads the entire span stack from the process dictionary**.
    4.  It **writes a new stack with the new span prepended back to the process dictionary**.
    5.  It emits a `[:foundation, :span, :start]` telemetry event.

**`end_span/2`**
This function ends the current span and removes it from the stack.

*   **Problematic Code:**
    ```elixir
    case Process.get(@span_stack_key, []) do
      [] ->
        # ...
      [span | rest] ->
        Process.put(@span_stack_key, rest)
        # ...
    end
    ```
*   **Logic:**
    1.  It **reads the span stack from the process dictionary**.
    2.  If the stack is not empty, it pops the current span and **writes the rest of the stack back to the process dictionary**.
    3.  It calculates the `duration` of the span.
    4.  It emits a `[:foundation, :span, :stop]` telemetry event with the final status and duration.

**`current_span/0`**
This helper retrieves the most recent span from the stack.

*   **Problematic Code:**
    ```elixir
    case Process.get(@span_stack_key, []) do
      [] -> nil
      [span | _] -> span
    end
    ```
*   **Logic:** It simply reads from the process dictionary and returns the head of the list, or `nil` if the stack is empty. This is used to establish the parent-child relationship between spans.

#### 3. Context Propagation

The module includes functions for propagating the span context across process boundaries, which is crucial for distributed tracing.

**`propagate_context/0` and `with_propagated_context/2`**

*   **Problematic Code:** The context propagation mechanism works by reading the entire span stack from the pdict, and the receiving process writes it back to its own pdict.
    ```elixir
    # in propagate_context/0
    span_stack: Process.get(@span_stack_key, [])

    # in with_propagated_context/2
    Process.put(@span_stack_key, stack)
    ```
*   **Logic:** This allows a parent process (e.g., a `GenServer`) to start a `Task` and have the task continue the same trace by inheriting the parent's span stack. The refactored solution must also support this pattern, but by passing the context explicitly and managing it via the new `SpanManager`.

#### 4. Summary of Findings for Refactoring

*   **State Management:** All state is managed via `Process.get/put`. This is the primary target for the refactor.
*   **API Surface:** The public API (`with_span`, `start_span`, `end_span`, etc.) is well-defined and should be maintained. The internal implementation must change, but the function signatures and behaviors should remain the same.
*   **Telemetry:** The module correctly emits telemetry events at the start and end of spans. This behavior must be preserved.
*   **Data Structure:** The `span` is a simple map: `%{id, name, start_time, metadata, parent_id, trace_id}`. This structure can and should be kept.
*   **Core Logic:** The core logic of a LIFO stack for managing nested spans is correct. The refactor needs to reimplement this stack logic using ETS.
*   **Process Cleanup:** There is currently **no cleanup mechanism**. If a process dies mid-span, its state is simply lost. The new `SpanManager` must address this by monitoring processes.