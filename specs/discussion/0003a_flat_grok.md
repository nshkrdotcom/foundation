Given your request for a detailed technical specification that embodies the perspective from the conversation, I’ve crafted a comprehensive specification for **Foundation**, a universal infrastructure library for BEAM (Erlang VM) applications, with a focus on Elixir. This specification reflects the need for a generic, reliable, and high-performance base layer that enhances OTP with essential components like configuration management, event storage, telemetry, service discovery, circuit breakers, and rate limiting. Below is the full technical specification.

---

### Foundation API Specification

#### 1. Introduction

**Foundation** is a universal infrastructure library designed for BEAM applications, particularly those written in Elixir. It provides a robust, generic foundation for building reliable distributed systems by enhancing OTP with essential primitives for process management, service discovery, and coordination. The library addresses timeless infrastructure challenges—configuration, event handling, telemetry, and service reliability—while remaining agnostic to specific application domains, making it suitable for everything from web servers to IoT systems.

**Design Principles:**
- **Generality**: APIs are designed to be broadly applicable, avoiding assumptions about higher-level application logic.
- **Performance**: Operations are optimized for speed and efficiency, with explicit performance targets.
- **Reliability**: Comprehensive error handling and fault tolerance are built into every component.
- **Composability**: Components integrate seamlessly, enabling higher-level systems to build on Foundation without modification.

---

#### 2. Configuration Management

**Module**: `Foundation.Config`

**Purpose**: Provides a centralized system for managing application configuration, supporting hot reloading from external sources (e.g., files, databases).

**API**:
- **`get(key, default \\ nil)`**
  - **Description**: Retrieves the value associated with `key`. Returns `default` if the key is not found.
  - **Input**: 
    - `key`: Atom or string.
    - `default`: Any type (optional, defaults to `nil`).
  - **Output**: The configuration value or `default`.
  - **Example**: 
    ```elixir
    Foundation.Config.get(:port, 8080) # Returns 8080 if :port is unset
    ```

- **`set(key, value)`**
  - **Description**: Sets the value for `key` in the configuration store.
  - **Input**: 
    - `key`: Atom or string.
    - `value`: Any type.
  - **Output**: `:ok` on success, `{:error, %Foundation.Error{}}` on failure.
  - **Example**: 
    ```elixir
    Foundation.Config.set(:port, 4000) # :ok
    ```

- **`reload()`**
  - **Description**: Triggers a hot reload of the configuration from its source.
  - **Output**: `:ok` on success, `{:error, %Foundation.Error{}}` on failure.
  - **Example**: 
    ```elixir
    Foundation.Config.reload() # :ok
    ```

**Performance Characteristics**:
- `get/2`: <10μs average case.
- `set/2`: <100μs.
- `reload/0`: <1ms.

**Error Handling**:
- Returns `{:error, %Foundation.Error{code: :config_error, message: "reason"}}` for failures (e.g., invalid key, source unavailable).

---

#### 3. Event Storage

**Module**: `Foundation.Events`

**Purpose**: Offers a structured system for storing and retrieving domain events, supporting any event type or domain logic.

**API**:
- **`store(event)`**
  - **Description**: Stores a structured event in the event store.
  - **Input**: 
    - `event`: Map or struct (e.g., `%{id: uuid, type: :user_created, data: %{}}`).
  - **Output**: `:ok` on success, `{:error, %Foundation.Error{}}` on failure.
  - **Example**: 
    ```elixir
    event = %{id: UUID.uuid4(), type: :order_placed, data: %{order_id: 123}}
    Foundation.Events.store(event) # :ok
    ```

- **`get(criteria)`**
  - **Description**: Retrieves events matching the given `criteria`.
  - **Input**: 
    - `criteria`: Map (e.g., `%{type: :order_placed, after: timestamp}`).
  - **Output**: `{:ok, [events]}` or `{:error, %Foundation.Error{}}`.
  - **Example**: 
    ```elixir
    Foundation.Events.get(%{type: :order_placed}) # {:ok, [event1, event2]}
    ```

**Performance Characteristics**:
- `store/1`: <100μs.
- `get/1`: <1ms for up to 1000 events.

**Error Handling**:
- Returns `{:error, %Foundation.Error{code: :event_error, message: "reason"}}` for failures (e.g., storage full, invalid criteria).

---

#### 4. Telemetry Integration

**Module**: `Foundation.Telemetry`

**Purpose**: Enables monitoring and metrics by emitting telemetry events, compatible with Elixir’s telemetry ecosystem.

**API**:
- **`execute(event_name, measurements, metadata)`**
  - **Description**: Emits a telemetry event with the specified name, measurements, and metadata.
  - **Input**: 
    - `event_name`: Atom (e.g., `:request_latency`).
    - `measurements`: Map (e.g., `%{duration: 50}`).
    - `metadata`: Map (e.g., `%{controller: "UserController"}`).
  - **Output**: `:ok`.
  - **Example**: 
    ```elixir
    Foundation.Telemetry.execute(:request_latency, %{duration: 50}, %{controller: "UserController"})
    ```

**Performance Characteristics**:
- <10μs overhead per event.

**Error Handling**:
- Fails silently to avoid disrupting the application; errors are logged internally if configured.

---

#### 5. Service Discovery

**Module**: `Foundation.ServiceRegistry`

**Purpose**: Provides a high-performance registry for registering and discovering services/processes across the BEAM cluster.

**API**:
- **`register(name, pid, metadata \\ %{})`**
  - **Description**: Registers a service with a unique `name` and associated `pid`.
  - **Input**: 
    - `name`: Atom or string.
    - `pid`: PID.
    - `metadata`: Map (optional, defaults to `%{}`).
  - **Output**: `:ok` on success, `{:error, %Foundation.Error{}}` if already registered.
  - **Example**: 
    ```elixir
    Foundation.ServiceRegistry.register("auth_service", self(), %{version: "1.0"})
    ```

- **`lookup(name)`**
  - **Description**: Looks up a service by `name`.
  - **Input**: 
    - `name`: Atom or string.
  - **Output**: `{:ok, pid, metadata}` if found, `{:error, :not_found}` otherwise.
  - **Example**: 
    ```elixir
    Foundation.ServiceRegistry.lookup("auth_service") # {:ok, #PID<0.123.0>, %{version: "1.0"}}
    ```

**Performance Characteristics**:
- `register/3`: O(1) average case (ETS-based).
- `lookup/1`: O(1) always.

**Error Handling**:
- `register/3`: Returns `{:error, %Foundation.Error{code: :already_registered, message: "service already registered"}}`.
- `lookup/1`: Returns `{:error, :not_found}` if the service is not registered.

---

#### 6. Circuit Breakers

**Module**: `Foundation.CircuitBreaker`

**Purpose**: Prevents cascading failures by wrapping operations in a circuit breaker pattern.

**API**:
- **`execute(function, options \\ [])`**
  - **Description**: Executes `function` with circuit breaker protection. Skips execution if the circuit is open.
  - **Input**: 
    - `function`: Anonymous function (e.g., `fn -> do_work() end`).
    - `options`: Keyword list (optional).
  - **Output**: Result of `function` or `{:error, %Foundation.Error{}}`.
  - **Example**: 
    ```elixir
    Foundation.CircuitBreaker.execute(fn -> risky_operation() end, timeout: 1000)
    ```

**Configuration Options**:
- `timeout`: Max execution time in ms (default: 5000).
- `max_failures`: Failures before opening the circuit (default: 5).
- `reset_timeout`: Time in ms to attempt closing the circuit (default: 10000).

**Error Handling**:
- `{:error, %Foundation.Error{code: :circuit_open, message: "circuit is open"}}` when the circuit is open.
- `{:error, %Foundation.Error{code: :timeout, message: "operation timed out"}}` on timeout.

---

#### 7. Rate Limiting

**Module**: `Foundation.RateLimiter`

**Purpose**: Controls resource usage by limiting the rate of operations.

**API**:
- **`execute(function, options \\ [])`**
  - **Description**: Executes `function` if within the rate limit.
  - **Input**: 
    - `function`: Anonymous function.
    - `options`: Keyword list (optional).
  - **Output**: Result of `function` or `{:error, %Foundation.Error{}}`.
  - **Example**: 
    ```elixir
    Foundation.RateLimiter.execute(fn -> process_request() end, max_requests: 50)
    ```

**Configuration Options**:
- `max_requests`: Max requests in the interval (default: 100).
- `interval`: Time window in ms (default: 60000).

**Error Handling**:
- `{:error, %Foundation.Error{code: :rate_limited, message: "rate limit exceeded"}}` when limits are exceeded.

---

#### 8. Error Handling

**Struct**: `%Foundation.Error{}`

**Purpose**: Ensures consistent error reporting across all components.

**Fields**:
- `code`: Atom (e.g., `:config_error`, `:circuit_open`).
- `message`: String (human-readable error description).
- `correlation_id`: String (unique ID for tracing).
- `context`: Map (additional context, e.g., stack trace).

**Example**:
```elixir
{:error, %Foundation.Error{
  code: :rate_limited,
  message: "rate limit exceeded",
  correlation_id: "abc123",
  context: %{requests: 101, interval: 60000}
}}
```

---

#### 9. Conclusion

**Foundation** delivers a reliable, generic infrastructure layer for BEAM applications. By providing essential components—configuration management, event storage, telemetry, service discovery, circuit breakers, and rate limiting—it enables developers to build robust systems without duplicating effort. Its focus on generality ensures compatibility with diverse use cases, while its performance and reliability make it production-ready. Higher-level systems can leverage Foundation’s APIs directly, maintaining simplicity and flexibility.

---

This specification captures the conversation’s emphasis on a universal, high-performance, and dependable infrastructure library for BEAM applications. Let me know if you’d like further details or adjustments!w