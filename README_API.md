Here are the public and private API documentation sets, created from the provided codebase.

***

# Public API Documentation

This documentation outlines the stable, public-facing APIs for the Foundation and JidoSystem frameworks. These are the primary interfaces intended for developers building applications on this platform.

---

## 1. Foundation Framework

The core, framework-agnostic protocol platform for building distributed systems.

### **Module `Foundation`**

A stateless facade providing convenient access to the application's default protocol implementations. This is the recommended entry point for most common operations.

**Key Functions:**

*   **`register(key, pid, metadata, impl \\ nil)`**
    *   Registers a process with its metadata.
    *   `@spec register(key :: term(), pid(), metadata :: map(), impl :: module() | nil) :: :ok | {:error, term()}`

*   **`lookup(key, impl \\ nil)`**
    *   Looks up a process by its key.
    *   `@spec lookup(key :: term(), impl :: module() | nil) :: {:ok, {pid(), map()}} | :error`

*   **`find_by_attribute(attribute, value, impl \\ nil)`**
    *   Finds processes by a specific indexed attribute value.
    *   `@spec find_by_attribute(attribute :: atom(), value :: term(), impl :: module() | nil) :: {:ok, list({key :: term(), pid(), map()})} | {:error, term()}`

*   **`query(criteria, impl \\ nil)`**
    *   Performs an atomic query with multiple criteria.
    *   `@spec query(criteria :: [Foundation.Registry.criterion()], impl :: module() | nil) :: {:ok, list({key :: term(), pid(), map()})} | {:error, term()}`

*   **`unregister(key, impl \\ nil)`**
    *   Unregisters a process.
    *   `@spec unregister(key :: term(), impl :: module() | nil) :: :ok | {:error, term()}`

*   **`execute_protected(service_id, function, context \\ %{}, impl \\ nil)`**
    *   Executes a function with circuit breaker protection.
    *   `@spec execute_protected(service_id :: term(), function :: (-> any()), context :: map(), impl :: module() | nil) :: {:ok, result :: any()} | {:error, term()}`

*   **`start_consensus(participants, proposal, timeout \\ 30_000, impl \\ nil)`**
    *   Starts a consensus process among participants.
    *   `@spec start_consensus(participants :: [term()], proposal :: term(), timeout(), impl :: module() | nil) :: {:ok, consensus_ref :: term()} | {:error, term()}`

### **Module `Foundation.Application`**

The main application entry point for the Foundation platform. It starts all core services and supervisors.

**Key Functions:**

*   **`start(_type, _args)`**
    *   The application start callback. Initializes and validates configuration, then starts the supervision tree.

### **Module `FoundationJidoSupervisor`**

The recommended top-level supervisor for applications using both `Foundation` and `JidoSystem`. It ensures the correct startup order, with Foundation services starting before JidoSystem components that depend on them.

**Key Functions:**

*   **`start_link(opts \\ [])`**
    *   Starts the supervisor.
    *   `@spec start_link(keyword()) :: Supervisor.on_start()`

---

## 2. Foundation Protocols

These modules define the core contracts that custom implementations must adhere to.

### **Protocol `Foundation.Registry`**
A universal protocol for process/service registration and discovery.

**Key Functions:**
*   `register(impl, key, pid, metadata)`
*   `lookup(impl, key)`
*   `find_by_attribute(impl, attribute, value)`
*   `query(impl, criteria)`
*   `unregister(impl, key)`
*   `count(impl)`
*   `protocol_version(impl)`

### **Protocol `Foundation.Coordination`**
A universal protocol for distributed coordination primitives like consensus, barriers, and locks.

**Key Functions:**
*   `start_consensus(impl, participants, proposal, timeout)`
*   `create_barrier(impl, barrier_id, participant_count)`
*   `wait_for_barrier(impl, barrier_id, timeout)`
*   `acquire_lock(impl, lock_id, holder, timeout)`
*   `release_lock(impl, lock_ref)`
*   `protocol_version(impl)`

### **Protocol `Foundation.Infrastructure`**
A universal protocol for infrastructure protection patterns like circuit breakers, rate limiting, and resource management.

**Key Functions:**
*   `register_circuit_breaker(impl, service_id, config)`
*   `execute_protected(impl, service_id, function, context)`
*   `setup_rate_limiter(impl, limiter_id, config)`
*   `check_rate_limit(impl, limiter_id, identifier)`
*   `monitor_resource(impl, resource_id, config)`
*   `protocol_version(impl)`

---

## 3. Foundation Abstractions

High-level modules providing access to common infrastructure patterns.

### **Module `Foundation.Cache`**
A convenience module providing a simple API for caching. Delegates to `Foundation.Infrastructure.Cache`.

**Key Functions:**
*   `get(key, default \\ nil, opts \\ [])`
*   `put(key, value, opts \\ [])`
*   `delete(key, opts \\ [])`
*   `clear(opts \\ [])`

### **Module `Foundation.CircuitBreaker`**
A convenience module for circuit breaker functionality. Delegates to `Foundation.Infrastructure.CircuitBreaker`.

**Key Functions:**
*   `start_link(opts \\ [])`
*   `configure(service_id, config \\ [])`
*   `call(service_id, function, opts \\ [])`
*   `get_status(service_id)`

### **Module `Foundation.Repository`**
A repository pattern for ETS-based storage, providing a consistent interface for CRUD operations. Use this as a base for creating custom repositories.

**Key Functions (in a `use Foundation.Repository` module):**
*   `start_link(opts \\ [])`
*   `insert(key, value, opts \\ [])`
*   `get(key, opts \\ [])`
*   `update(key, updates, opts \\ [])`
*   `delete(key, opts \\ [])`
*   `all(opts \\ [])`
*   `query()` (returns a `Foundation.Repository.Query` struct)

### **Module `Foundation.EventSystem`**
A unified event system adapter for routing events (metrics, signals, notifications) to the appropriate backend.

**Key Functions:**
*   `emit(type, name, data \\ %{})`
    *   Emits an event, routing it based on its type.
    *   `@spec emit(type :: :metric | :signal | :notification, name :: [atom()], data :: map()) :: :ok | {:error, term()}`
*   `subscribe(type, pattern, handler)`
    *   Subscribes to events of a specific type.
    *   `@spec subscribe(type :: :metric | :signal, pattern :: term(), handler :: pid() | function()) :: {:ok, term()} | {:error, term()}`

---

## 4. JidoSystem Framework

The main interface for the Jido agentic platform.

### **Module `JidoSystem`**

The main entry point for the Jido System. Provides top-level functions for creating agents, processing tasks, and managing the system.

**Key Functions:**
*   **`start(opts \\ [])`**
    *   Starts the JidoSystem application and all required services.
    *   `@spec start(keyword()) :: {:ok, pid()} | {:error, term()}`

*   **`create_agent(agent_type, opts \\ [])`**
    *   Creates a new agent of a specified type.
    *   `@spec create_agent(agent_type :: :task_agent | :monitor_agent | :coordinator_agent, keyword()) :: {:ok, pid()} | {:error, term()}`

*   **`process_task(agent, task, opts \\ [])`**
    *   Processes a task using the specified agent.
    *   `@spec process_task(agent :: pid() | term(), task :: map(), keyword()) :: {:ok, :enqueued} | {:error, term()}`

*   **`start_monitoring(opts \\ [])`**
    *   Starts comprehensive system monitoring.
    *   `@spec start_monitoring(keyword()) :: {:ok, map()} | {:error, term()}`

*   **`get_system_status()`**
    *   Gets a comprehensive status of the entire JidoSystem.
    *   `@spec get_system_status() :: {:ok, map()} | {:error, term()}`

### **Module `JidoSystem.Application`**

The application supervisor for JidoSystem, ensuring all agents and services are started in the correct order.

**Key Functions:**
*   **`start(_type, _args)`**
    *   The application start callback.

---

## 5. JidoFoundation Bridge

The integration layer connecting the Jido framework with the Foundation platform.

### **Module `JidoFoundation.Bridge`**

A facade that delegates to specialized managers, enabling Jido agents to leverage Foundation's infrastructure.

**Key Functions:**
*   **`register_agent(agent_pid, opts \\ [])`**
    *   Registers a Jido agent with Foundation's registry.
    *   `@spec register_agent(pid(), keyword()) :: :ok | {:error, term()}`

*   **`unregister_agent(agent_pid, opts \\ [])`**
    *   Unregisters a Jido agent from Foundation.
    *   `@spec unregister_agent(pid(), keyword()) :: :ok | {:error, term()}`

*   **`emit_signal(agent, signal, opts \\ [])`**
    *   Emits a Jido signal through the signal bus.
    *   `@spec emit_signal(agent :: pid(), signal :: map() | Jido.Signal.t(), keyword()) :: {:ok, [Jido.Signal.Bus.RecordedSignal.t()]} | {:error, term()}`

*   **`execute_protected(agent_pid, action_fun, opts \\ [])`**
    *   Executes a Jido action with Foundation circuit breaker protection.
    *   `@spec execute_protected(pid(), (-> any()), keyword()) :: {:ok, any()} | {:error, term()}`

*   **`find_agents_by_capability(capability, opts \\ [])`**
    *   Finds Jido agents by capability.
    *   `@spec find_agents_by_capability(atom(), keyword()) :: {:ok, list({term(), pid(), map()})} | {:error, term()}`

***

# Private API Documentation

This documentation outlines the internal modules and implementation details of the Foundation and JidoSystem frameworks. **These APIs are subject to change and should not be used directly by application code.** They are provided for understanding the internal workings of the system.

---

## 1. Foundation Internals

### **Module `Foundation.Infrastructure.Cache`**
*   **Purpose:** The `GenServer` implementation for the ETS-based cache. Handles TTL cleanup and memory limits.
*   **Key Private Functions:** `init/1`, `handle_call/3` for `:put`, `handle_info/2` for `:cleanup_expired`.

### **Module `Foundation.Infrastructure.CircuitBreaker`**
*   **Purpose:** The `GenServer` implementation for the circuit breaker, wrapping the `:fuse` library.
*   **Key Private Functions:** `init/1`, `handle_call/3` for `:configure`, `:execute`, `:get_status`.

### **Module `Foundation.Services.Supervisor`**
*   **Purpose:** The main supervisor for all internal Foundation services (`RetryService`, `ConnectionManager`, `RateLimiter`, etc.).
*   **Key Private Functions:** `init/1` defines the child specifications for all core services.

### **Module `Foundation.Services.ConnectionManager`**
*   **Purpose:** The `GenServer` implementation for the HTTP connection manager, using Finch.
*   **Key Private Functions:** `init/1`, `handle_call({:execute_request, ...})`.

### **Module `Foundation.Services.RateLimiter`**
*   **Purpose:** The `GenServer` implementation for rate limiting, using an in-memory ETS-based approach.
*   **Key Private Functions:** `init/1`, `handle_call({:check_rate_limit, ...})`, `handle_info({:cleanup, ...})`.

### **Module `Foundation.Services.RetryService`**
*   **Purpose:** The `GenServer` implementation for the retry service, using the `elixir-retry` library.
*   **Key Private Functions:** `init/1`, `get_retry_policy/2`, `execute_with_retry/2`.

### **Module `Foundation.Services.SignalBus`**
*   **Purpose:** A `GenServer` wrapper for `Jido.Signal.Bus` to provide a standard service lifecycle within Foundation.
*   **Key Private Functions:** `init/1` starts the underlying `Jido.Signal.Bus`.

### **Module `Foundation.ETSHelpers.MatchSpecCompiler`**
*   **Purpose:** A private helper module to compile high-level query criteria into efficient ETS match specifications.
*   **Key Private Functions:** `compile/1`, `build_guards/2`, `build_operation_guard/3`.

---

## 2. JidoSystem Internals

### **Module `JidoSystem.Agents.*`**
*   **Purpose:** These modules (`TaskAgent`, `CoordinatorAgent`, `MonitorAgent`, `FoundationAgent`, `PersistentFoundationAgent`) are the concrete implementations of different agent types. They are not meant to be called directly but are started via `JidoSystem.create_agent/2`.
*   **Key Private Functions:** Each agent implements the `Jido.Agent` behaviour, including `mount/2`, `on_before_run/1`, `on_after_run/3`, and various `handle_...` functions for their specific actions.

### **Module `JidoSystem.Actions.*`**
*   **Purpose:** These modules define the logic for actions that can be executed by agents. They are dispatched via agent commands, not called directly.
*   **Key Private Functions:** Each action implements the `Jido.Action` behaviour, with the core logic in the `run/2` function.

### **Module `JidoSystem.Supervisors.*`**
*   **Purpose:** These modules (`WorkflowSupervisor`) are internal supervisors for managing specific types of processes within the JidoSystem.
*   **Key Private Functions:** `init/1` defines the supervision strategy and children.

### **Module `JidoSystem.Processes.WorkflowProcess`**
*   **Purpose:** A `GenServer` that manages the execution of a single workflow, isolating it from other workflows and the main coordinator.
*   **Key Private Functions:** `init/1`, `handle_info(:execute_task, ...)` manages the state machine of the workflow.

### **Module `JidoSystem.Sensors.*`**
*   **Purpose:** These modules (`AgentPerformanceSensor`, `SystemHealthSensor`) are implementations of the `Jido.Sensor` behaviour, responsible for collecting and analyzing system data.
*   **Key Private Functions:** Each sensor implements `mount/1` and `deliver_signal/1`.

---

## 3. JidoFoundation Bridge Internals

### **Module `JidoFoundation.Bridge.*`**
*   **Purpose:** These modules (`AgentManager`, `CoordinationManager`, `ExecutionManager`, `ResourceManager`, `SignalManager`) are the internal implementation modules for the `JidoFoundation.Bridge` facade. They contain the actual logic for integrating Jido agents with Foundation services.
*   **Key Private Functions:** These are simple modules with public functions that are delegated to by the `Bridge`. They are considered private because the `Bridge` is the intended entry point.

### **Module `JidoFoundation.MonitorSupervisor`**
*   **Purpose:** A `DynamicSupervisor` for managing `JidoFoundation.AgentMonitor` processes, ensuring each agent's health monitor is properly supervised.
*   **Key Private Functions:** `start_monitoring/2` is the main entry point to start a supervised monitor.

### **Module `JidoFoundation.AgentMonitor`**
*   **Purpose:** The `GenServer` implementation that actively monitors a single Jido agent's health and updates the Foundation registry.
*   **Key Private Functions:** `init/1` starts the monitoring loop, and `handle_info(:health_check, ...)` performs the periodic check.

---

## 4. MABEAM Internals

### **Module `MABEAM.AgentRegistry`**
*   **Purpose:** The core `GenServer` implementation of the MABEAM agent registry. It handles all write operations to ensure consistency.
*   **Key Private Functions:** `handle_call({:register, ...})`, `handle_call({:update_metadata, ...})`, `handle_info({:DOWN, ...})` for process cleanup.

### **Module `MABEAM.AgentRegistry.*`**
*   **Purpose:** These helper modules (`IndexManager`, `QueryEngine`, `Reader`, `Validator`) break out the responsibilities of the main `AgentRegistry` GenServer.
*   **Key Private Functions:**
    *   `IndexManager`: `update_all_indexes/3`, `clear_agent_from_indexes/2`.
    *   `QueryEngine`: `do_application_level_query/3`.
    *   `Reader`: Provides direct, high-performance read access to ETS tables.
    *   `Validator`: `validate_agent_metadata/1`.

### **Module `MABEAM.Coordination`**
*   **Purpose:** High-level, domain-specific coordination APIs for agents, built on top of the Foundation protocols.
*   **Key Private Functions:** `coordinate_capable_agents/4`, `coordinate_resource_allocation/3`.

### **Module `MABEAM.Discovery`**
*   **Purpose:** Provides composed, multi-criteria discovery APIs using atomic queries for high performance.
*   **Key Private Functions:** `find_capable_and_healthy/2`, `find_agents_with_resources/3`.
