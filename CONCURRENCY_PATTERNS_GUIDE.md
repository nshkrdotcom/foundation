
# Concurrency Patterns Guide

This guide outlines recommended concurrency patterns for the `foundation` project, emphasizing best practices for state management, asynchronous communication, and fault tolerance within an Elixir/OTP context. Adhering to these patterns will improve system reliability, performance, and maintainability.

## 1. Prefer Asynchronous Communication

*   **`GenServer.cast` over `GenServer.call`**: Use `cast` whenever an immediate response is not required. This frees the calling process and prevents bottlenecks in the `GenServer` handling the request. `call` should be reserved for operations that genuinely require a synchronous reply.
*   **Event-Driven Architecture**: For complex interactions, consider an event-driven approach. Processes can emit events (e.g., using `Phoenix.PubSub` or a custom event bus) that other interested processes can subscribe to and react asynchronously. This decouples components and improves responsiveness.
*   **Message Queues**: For inter-service communication or handling high-volume, durable messages, integrate with external message queues (e.g., RabbitMQ, Kafka). This provides robust asynchronous communication, back-pressure, and resilience.

## 2. State Management

*   **Encapsulate State in Processes**: All mutable state should be owned and managed by a single process (typically a `GenServer`). This eliminates race conditions and simplifies reasoning about data consistency.
*   **Avoid Shared Mutable Data**: Do not pass mutable data structures between processes. Instead, pass immutable data or messages. If a process needs to modify data, it should do so internally and then send the updated (immutable) data to other processes if necessary.
*   **ETS for Read-Heavy, Shared Data**: For data that is frequently read and rarely written, and needs to be accessible by many processes, consider using an Erlang Term Storage (ETS) table. ETS tables provide fast, concurrent read access. Write access should still be managed by a single owning process to maintain consistency.
*   **Persistent Storage**: For long-term or critical state, ensure proper persistence mechanisms are in place (e.g., databases, disk storage). Processes should interact with these through well-defined data access layers.

## 3. Fault Tolerance and Supervision

*   **Supervision Trees**: Every process in the application should be part of a supervision tree. This ensures that processes are automatically restarted if they crash, providing self-healing capabilities.
    *   **`Supervisor.start_link/2`**: Use this to start and link new supervisors.
    *   **`Supervisor.child_spec/2`**: Define clear child specifications for all supervised processes.
*   **`Task.Supervisor` for Short-Lived Tasks**: For transient, concurrent tasks that do not manage long-term state, use `Task.Supervisor`. This ensures that even short-lived operations are monitored and cleaned up properly.
*   **Link and Monitor**: Understand the difference between `Process.link/1` and `Process.monitor/1`. Use `link` when processes are tightly coupled and one crashing should bring down the other. Use `monitor` when you need to be notified of a process's termination without being affected by its crash.
*   **Graceful Shutdown**: Implement `terminate/2` callbacks in `GenServer`s to ensure proper resource cleanup during shutdown or crashes.

## 4. Concurrency Best Practices

*   **Delegate Long-Running Work**: A `GenServer` should never perform long-running or computationally intensive tasks directly in its `handle_call` or `handle_cast` callbacks. Instead, delegate such work to a separate `Task` (supervised by a `Task.Supervisor`) and have the `Task` report its result back to the `GenServer` asynchronously.
*   **Avoid Blocking Operations**: Minimize blocking operations within `GenServer` callbacks. If an external call is blocking, consider wrapping it in a `Task` or using a non-blocking client library.
*   **Back-Pressure**: Design systems to handle back-pressure. If a consumer cannot keep up with a producer, mechanisms should be in place to slow down the producer or queue messages, rather than crashing or dropping messages.
*   **Timeouts**: Always use timeouts for synchronous operations (`GenServer.call`, external API calls) to prevent indefinite blocking and ensure responsiveness.

## 5. Testing Concurrency

*   **Event-Driven Assertions**: Replace `Process.sleep` and polling with event-driven assertions using `assert_receive` or `refute_receive` to test asynchronous interactions reliably.
*   **Property-Based Testing**: Use property-based testing (e.g., with StreamData) to explore various concurrent scenarios and uncover subtle race conditions that might be missed by example-based tests.

By adopting these concurrency patterns, the `foundation` project can build a robust, scalable, and fault-tolerant system that leverages the full power of the BEAM VM.