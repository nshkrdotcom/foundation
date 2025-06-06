# Architectural Diagrams

This document provides comprehensive architectural diagrams for the Foundation library, illustrating the system's layered architecture, supervision structure, data flows, and key operational patterns.

## Overview

The Foundation library follows a layered architecture pattern with clear separation of concerns:

- **Public API Layer:** Clean interfaces for configuration, events, telemetry, infrastructure, and service registry
- **Logic & Validation Layer:** Pure functions for business logic and data validation
- **Service Layer:** Stateful GenServers managing application state
- **Infrastructure Layer:** Wrappers around external libraries with unified interfaces

This architecture ensures maintainability, testability, and fault tolerance while providing a consistent developer experience.

## Architectural Diagrams

### 1. High-Level Architecture

This diagram illustrates the layered architecture of the Foundation library, showing the separation of concerns from the Public API down to the Infrastructure layer.

```mermaid
graph LR
    subgraph "Public API Layer"
        A1["Foundation.Config"]
        A2["Foundation.Events"]
        A3["Foundation.Telemetry"]
        A4["Foundation.Infrastructure"]
        A5["Foundation.ServiceRegistry"]
    end

    subgraph "Logic&nbsp;&&nbsp;Validation&nbsp;Layer&nbsp;(Pure&nbsp;Functions)"
        B1["Foundation.Logic.ConfigLogic"]
        B2["Foundation.Logic.EventLogic"]
        B3["Foundation.Validation.ConfigValidator"]
        B4["Foundation.Validation.EventValidator"]
    end

    subgraph "Service&nbsp;Layer&nbsp;(Stateful&nbsp;GenServers)"
        C1["Foundation.Services.ConfigServer"]
        C2["Foundation.Services.EventStore"]
        C3["Foundation.Services.TelemetryService"]
    end

    subgraph "Infrastructure&nbsp;&&nbsp;External&nbsp;Libs&nbsp;Layer"
        D1["Foundation.ProcessRegistry (using Elixir Registry)"]
        D2["Foundation.Infrastructure.CircuitBreaker (wraps :fuse)"]
        D3["Foundation.Infrastructure.RateLimiter (wraps :hammer)"]
        D4["Foundation.Infrastructure.ConnectionManager (wraps :poolboy)"]
    end

    A1 --> C1
    A2 --> C2
    A3 --> C3
    A4 --> D2
    A4 --> D3
    A4 --> D4
    A5 --> D1

    C1 --> B1
    C1 --> B3
    C2 --> B2
    C2 --> B4
    C2 --> A3

    style A1 fill:#cce5ff,stroke:#333,stroke-width:2,color:#000
    style A2 fill:#cce5ff,stroke:#333,stroke-width:2,color:#000
    style A3 fill:#cce5ff,stroke:#333,stroke-width:2,color:#000
    style A4 fill:#cce5ff,stroke:#333,stroke-width:2,color:#000
    style A5 fill:#cce5ff,stroke:#333,stroke-width:2,color:#000

    style B1 fill:#d4edda,stroke:#333,stroke-width:2,color:#000
    style B2 fill:#d4edda,stroke:#333,stroke-width:2,color:#000
    style B3 fill:#d4edda,stroke:#333,stroke-width:2,color:#000
    style B4 fill:#d4edda,stroke:#333,stroke-width:2,color:#000

    style C1 fill:#f8d7da,stroke:#333,stroke-width:2,color:#000
    style C2 fill:#f8d7da,stroke:#333,stroke-width:2,color:#000
    style C3 fill:#f8d7da,stroke:#333,stroke-width:2,color:#000

    style D1 fill:#fff3cd,stroke:#333,stroke-width:2,color:#000
    style D2 fill:#fff3cd,stroke:#333,stroke-width:2,color:#000
    style D3 fill:#fff3cd,stroke:#333,stroke-width:2,color:#000
    style D4 fill:#fff3cd,stroke:#333,stroke-width:2,color:#000
```

## Application Supervision Tree

This diagram shows the supervision structure defined in `Foundation.Application`, outlining which processes are started and managed for fault tolerance.

```mermaid
graph LR
    subgraph "Foundation.Application"
        Supervisor["Foundation.Supervisor (strategy: :one_for_one)"]
    end

    subgraph "Core&nbsp;Services&nbsp;&&nbsp;Infrastructure"
        Reg["Foundation.ProcessRegistry"]
        CfgSrv["Foundation.Services.ConfigServer"]
        EvtStore["Foundation.Services.EventStore"]
        TelSrv["Foundation.Services.TelemetryService"]
        ConnMgr["Foundation.Infrastructure.ConnectionManager"]
        Hammer["Foundation.Infrastructure.RateLimiter.HammerBackend"]
        TaskSup["Foundation.TaskSupervisor (Task.Supervisor)"]
    end

    subgraph "Test-Mode Only"
        TestSup["Foundation.TestSupport.TestSupervisor"]
    end

    Supervisor --> Reg
    Supervisor --> CfgSrv
    Supervisor --> EvtStore
    Supervisor --> TelSrv
    Supervisor --> ConnMgr
    Supervisor --> Hammer
    Supervisor --> TaskSup
    Supervisor --> TestSup

    style Supervisor fill:#b3d1ff,stroke:#333,stroke-width:2,color:#000
    style Reg fill:#d4edda,stroke:#333,stroke-width:2,color:#000
    style CfgSrv fill:#d4edda,stroke:#333,stroke-width:2,color:#000
    style EvtStore fill:#d4edda,stroke:#333,stroke-width:2,color:#000
    style TelSrv fill:#d4edda,stroke:#333,stroke-width:2,color:#000
    style ConnMgr fill:#d4edda,stroke:#333,stroke-width:2,color:#000
    style Hammer fill:#d4edda,stroke:#333,stroke-width:2,color:#000
    style TaskSup fill:#d4edda,stroke:#333,stroke-width:2,color:#000
    style TestSup fill:#f8d7da,stroke:#333,stroke-width:2,stroke-dasharray: 5 5,color:#000
```

## Configuration Update Flow

This diagram details the sequence of interactions that occur when a configuration value is updated, showing how the change propagates through the logic, service, event, and telemetry layers.

```mermaid
graph TD
    Client["Client Code"] -- "update(path, value)" --> F_Config["Foundation.Config"]
    F_Config -- "Delegates to Service" --> F_ConfigServer["Services.ConfigServer"]
    
    subgraph "ConfigServer Logic"
        A["GenServer receives :update_config call"] --> B["Calls ConfigLogic.update_config(..)"]
        B --> C["ConfigLogic checks if path is updatable"]
        C --> D["ConfigValidator validates new config structure"]
        D -- ":ok" --> E{"Update successful"}
        C -- "Error" --> F{"Update fails"}
        D -- "Error" --> F
    end

    F_ConfigServer --> A
    E -- "Update state & notify subscribers" --> F_ConfigServer
    E -- "Emit :config_updated event" --> F_EventStore["Services.EventStore"]
    E -- "Emit :config_updates metric" --> F_Telemetry["Services.TelemetryService"]
    F_EventStore --> E
    F_Telemetry --> E
    F_ConfigServer -- ":ok" --> F_Config
    F_Config -- "Success" --> Client

    F -- "{:error, reason}" --> F_ConfigServer
    F_ConfigServer -- "Error" --> F_Config
    F_Config -- "Failure" --> Client

    style Client fill:#e9ecef,stroke:#333,stroke-width:2,color:#000
    style F_Config fill:#cce5ff,stroke:#333,stroke-width:2,color:#000
    style F_ConfigServer fill:#f8d7da,stroke:#333,stroke-width:2,color:#000
    style F_EventStore fill:#f8d7da,stroke:#333,stroke-width:2,color:#000
    style F_Telemetry fill:#f8d7da,stroke:#333,stroke-width:2,color:#000
    style A fill:#fff3cd,stroke:#333,stroke-width:2,color:#000
    style B fill:#fff3cd,stroke:#333,stroke-width:2,color:#000
    style C fill:#fff3cd,stroke:#333,stroke-width:2,color:#000
    style D fill:#fff3cd,stroke:#333,stroke-width:2,color:#000
    style E fill:#d4edda,stroke:#333,stroke-width:2,color:#000
    style F fill:#f5c6cb,stroke:#333,stroke-width:2,color:#000
```

## Protected Operation Flow

This diagram illustrates the flow of a protected operation using `Foundation.Infrastructure.execute_protected`, showing how the different protection layers (Rate Limiter, Circuit Breaker, Connection Pool) are applied in sequence.

```mermaid
graph TD
    subgraph "Infrastructure.execute_protected"
        Start["Start"]
        RateLimiter["Check Rate Limiter"]
        CircuitBreaker["Check Circuit Breaker"]
        ConnectionPool["Checkout Connection from Pool"]
        Operation["Execute User Function"]
        Checkin["Checkin Connection to Pool"]
        Stop["Stop (Success)"]
    end

    subgraph "Failure Paths"
        RateLimited["Stop (Rate Limited Error)"]
        CircuitOpen["Stop (Circuit Open Error)"]
        PoolTimeout["Stop (Pool Checkout Timeout Error)"]
        OpFails["Stop (Operation Failure)"]
    end

    Start --> RateLimiter
    RateLimiter -- "Allowed" --> CircuitBreaker
    RateLimiter -- "Denied" --> RateLimited
    CircuitBreaker -- "Closed (Healthy)" --> ConnectionPool
    CircuitBreaker -- "Open (Tripped)" --> CircuitOpen
    ConnectionPool -- "Success" --> Operation
    ConnectionPool -- "Timeout" --> PoolTimeout
    Operation -- "Success" --> Checkin
    Operation -- "Failure (Exception)" --> OpFails
    Checkin --> Stop

    style Start fill:#d4edda,stroke:#333,stroke-width:2,color:#000
    style Stop fill:#d4edda,stroke:#333,stroke-width:2,color:#000
    style RateLimited fill:#f8d7da,stroke:#333,stroke-width:2,color:#000
    style CircuitOpen fill:#f8d7da,stroke:#333,stroke-width:2,color:#000
    style PoolTimeout fill:#f8d7da,stroke:#333,stroke-width:2,color:#000
    style OpFails fill:#f8d7da,stroke:#333,stroke-width:2,color:#000
    style RateLimiter fill:#fff3cd,stroke:#333,stroke-width:2,color:#000
    style CircuitBreaker fill:#fff3cd,stroke:#333,stroke-width:2,color:#000
    style ConnectionPool fill:#fff3cd,stroke:#333,stroke-width:2,color:#000
    style Operation fill:#cce5ff,stroke:#333,stroke-width:2,color:#000
    style Checkin fill:#d1ecf1,stroke:#333,stroke-width:2,color:#000
```

## Service Registration & Lookup Architecture

This diagram explains the dual-mechanism approach to service registration and lookup, involving both the native Elixir `Registry` for supervised processes and a backup ETS table for manual registrations.

```mermaid
graph TD
    subgraph "Service Registration"
        A["Client starts GenServer using `via_tuple`"] --> B["ProcessRegistry.via_tuple(ns, service)"]
        B --> C["Elixir Registry"]
        C -- "Stores `{ns, service} -> pid`" --> D["Live, supervised processes stored here"]

        E["Client calls ServiceRegistry.register(ns, service, pid)"] --> F["ProcessRegistry.register(ns, service, pid)"]
        F --> G["Backup ETS Table"]
        G -- "Stores `{ns, service} -> pid`" --> H["Manually registered or test processes stored here"]
    end

    subgraph "Service Lookup"
        I["Client calls ServiceRegistry.lookup(ns, service)"] --> J["ProcessRegistry.lookup(ns, service)"]
        J -- "Tries Elixir Registry" --> C
        C -- "Found/Not Found" --> J
        J -- "Tries Backup ETS on failure" --> G
        G -- "Found/Not Found" --> J
        J -- "Returns final result" --> I
    end

    style A fill:#e9ecef,stroke:#333,stroke-width:2,color:#000
    style E fill:#e9ecef,stroke:#333,stroke-width:2,color:#000
    style I fill:#e9ecef,stroke:#333,stroke-width:2,color:#000
    style B fill:#cce5ff,stroke:#333,stroke-width:2,color:#000
    style F fill:#cce5ff,stroke:#333,stroke-width:2,color:#000
    style J fill:#cce5ff,stroke:#333,stroke-width:2,color:#000
    style C fill:#d4edda,stroke:#333,stroke-width:2,color:#000
    style G fill:#d4edda,stroke:#333,stroke-width:2,color:#000
    style D fill:#d1ecf1,stroke:#333,stroke-width:2,color:#000
    style H fill:#d1ecf1,stroke:#333,stroke-width:2,color:#000
```

## Error Context & Handling Flow

This diagram shows how `ErrorContext` is used to wrap an operation, provide context, and enhance any resulting errors with rich, debuggable information.

```mermaid
graph TD
    subgraph "ErrorContext.with_context"
        Start["Start Operation"]
        CreateContext["ErrorContext.new()"]
        WithContext["Call with_context(ctx, fun)"]
        PutContext["Process.put(:error_context, ctx)"]
        ExecuteFun["Execute user function fun"]
        DeleteContext["Process.delete(:error_context)"]
        Success["Return Success Result"]
    end

    subgraph "Exception Path"
        CatchException["rescue block catches exception"]
        EnhanceError["Create enhanced Foundation.Error struct with context (breadcrumbs, duration, etc.)"]
        EmitTelemetry["Error.collect_error_metrics(error)"]
        ErrorResult["Return {:error, enhanced_error}"]
    end

    Start --> CreateContext
    CreateContext --> WithContext
    WithContext --> PutContext
    PutContext --> ExecuteFun
    ExecuteFun -- "Success" --> DeleteContext
    DeleteContext --> Success
    ExecuteFun -- "Exception Thrown" --> CatchException
    CatchException --> EnhanceError
    EnhanceError --> EmitTelemetry
    EmitTelemetry --> ErrorResult
    ErrorResult --> DeleteContext

    style Start fill:#d4edda,stroke:#333,stroke-width:2,color:#000
    style Success fill:#d4edda,stroke:#333,stroke-width:2,color:#000
    style CatchException fill:#f8d7da,stroke:#333,stroke-width:2,color:#000
    style ErrorResult fill:#f8d7da,stroke:#333,stroke-width:2,color:#000
    style CreateContext fill:#fff3cd,stroke:#333,stroke-width:2,color:#000
    style WithContext fill:#fff3cd,stroke:#333,stroke-width:2,color:#000
    style PutContext fill:#fff3cd,stroke:#333,stroke-width:2,color:#000
    style ExecuteFun fill:#cce5ff,stroke:#333,stroke-width:2,color:#000
    style DeleteContext fill:#d1ecf1,stroke:#333,stroke-width:2,color:#000
    style EnhanceError fill:#f5c6cb,stroke:#333,stroke-width:2,color:#000
    style EmitTelemetry fill:#f5c6cb,stroke:#333,stroke-width:2,color:#000
```

## Test Isolation Architecture

This diagram explains the architecture that enables concurrent testing by isolating services within unique, per-test namespaces.

```mermaid
graph TD
    subgraph "Test Execution"
        A["Test Case using `ConcurrentTestCase`"]
    end

    subgraph "Test Setup"
        B["setup block calls TestSupervisor.start_isolated_services(ref)"]
    end

    subgraph "TestSupervisor&nbsp;(DynamicSupervisor)"
        C["Starts child services with a unique test namespace"]
        D["- {ConfigServer, [namespace: {:test, ref}]}"]
        E["- {EventStore, [namespace: {:test, ref}]}"]
        F["- {TelemetryService, [namespace: {:test, ref}]}"]
    end

    subgraph "ProcessRegistry"
        G["Services register using via_tuple({:test, ref}, ...) or in the backup ETS table for that namespace"]
    end

    subgraph "Test Teardown"
        H["on_exit hook calls TestSupervisor.cleanup_namespace(ref)"]
        I["Terminates all child processes for the given ref"]
        J["Cleans up registry and ETS entries for the namespace"]
    end

    A -- "Generates unique ref" --> B
    B -- "Starts isolated services via Supervisor" --> C
    C --> D & E & F
    D & E & F -- "Services register in namespaced registry" --> G
    A -- "Test code interacts with services via ServiceRegistry.lookup({:test, ref}, ...)" --> G
    A -- "Test finishes" --> H
    H -- "Cleans up Supervisor children" --> I
    H -- "Cleans up Registry entries" --> J

    style A fill:#cce5ff,stroke:#333,stroke-width:2,color:#000
    style B fill:#d4edda,stroke:#333,stroke-width:2,color:#000
    style H fill:#f8d7da,stroke:#333,stroke-width:2,color:#000
    style C fill:#fff3cd,stroke:#333,stroke-width:2,color:#000
    style G fill:#fff3cd,stroke:#333,stroke-width:2,color:#000
    style I fill:#f5c6cb,stroke:#333,stroke-width:2,color:#000
    style J fill:#f5c6cb,stroke:#333,stroke-width:2,color:#000
```

## Core Data Model

This class diagram illustrates the primary data structures (`Config`, `Event`, `Error`) and their key fields, providing a static view of the library's data schema.

```mermaid
classDiagram
    direction LR

    class Config {
        +ai: ai_config
        +capture: capture_config
        +storage: storage_config
        +interface: interface_config
        +dev: dev_config
        +infrastructure: infrastructure_config
        +new(overrides) t
    }

    class Event {
        +event_id: event_id
        +event_type: atom
        +timestamp: integer
        +correlation_id: string
        +parent_id: event_id
        +data: term
        +new(fields) t
    }

    class Error {
        +code: integer
        +error_type: atom
        +message: string
        +severity: atom
        +context: map
        +category: atom
        +retry_strategy: atom
        +new(fields) t
    }

    class ConfigLogic {
        <<Logic>>
        +update_config(Config, path, value)
        +get_config_value(Config, path)
    }
    
    class EventLogic {
        <<Logic>>
        +create_event(type, data, opts)
        +serialize_event(Event)
        +deserialize_event(binary)
    }

    class ConfigValidator {
        <<Validation>>
        +validate(Config)
    }

    class EventValidator {
        <<Validation>>
        +validate(Event)
    }

    ConfigLogic ..> Config : uses
    ConfigLogic ..> Error : creates
    ConfigValidator ..> Config : validates
    ConfigValidator ..> Error : creates

    EventLogic ..> Event : creates
    EventLogic ..> Error : creates
    EventValidator ..> Event : validates
    EventValidator ..> Error : creates
```

## Connection Pool Flow (`with_connection`)

This sequence diagram details the process of executing a function using a pooled connection from the `ConnectionManager`. It highlights the automatic checkout and check-in of worker processes.

```mermaid
sequenceDiagram
    participant Client
    participant ConnMgr as ConnectionManager
    participant Poolboy as Internal Pool
    participant Worker

    Client->>ConnMgr: with_connection(pool_name, fun, timeout)
    activate ConnMgr
    
    ConnMgr->>Poolboy: checkout(pool_pid, true, timeout)
    activate Poolboy
    Poolboy-->>ConnMgr: worker_pid
    deactivate Poolboy
    
    Note right of ConnMgr: Telemetry event: checkout
    
    ConnMgr->>Worker: fun(worker_pid)
    activate Worker
    Worker-->>ConnMgr: fun_result
    deactivate Worker
    
    alt Successful Execution
        ConnMgr->>Poolboy: checkin(pool_pid, worker_pid)
        activate Poolboy
        Poolboy-->>ConnMgr: ok
        deactivate Poolboy
        Note right of ConnMgr: Telemetry event: checkin
        ConnMgr-->>Client: ok with fun_result
    else Exception in fun
        ConnMgr->>Poolboy: checkin(pool_pid, worker_pid) in rescue/after
        activate Poolboy
        Poolboy-->>ConnMgr: ok
        deactivate Poolboy
        Note right of ConnMgr: Telemetry event: checkin
        ConnMgr-->>Client: error with exception
    else Checkout Timeout
        Note right of ConnMgr: Telemetry event: timeout
        ConnMgr-->>Client: error checkout_timeout
    end
    
    deactivate ConnMgr
```

## Circuit Breaker State Machine

This state diagram visualizes the behavior of the `CircuitBreaker` wrapper around the `:fuse` library. It shows the transitions between the `Closed` (healthy), `Open` (tripped), and `HalfOpen` (recovering) states.

```mermaid
stateDiagram-v2
    ClosedHealthy : Closed (Healthy)
    OpenTripped : Open (Tripped)
    HalfOpenRecovering : Half-Open (Recovering)
    
    note right of ClosedHealthy
        Operations are executed.
        Successes reset failure count.
        Failures increment failure count.
    end note
    
    note right of OpenTripped
        Operations are immediately rejected.
        No external calls are made.
        Waits for refresh timeout to elapse.
    end note

    note right of HalfOpenRecovering
        Allows one test operation to execute.
        Success transitions to Closed.
        Failure transitions back to Open.
    end note
    
    state ManualReset {
        direction LR
        [*] --> ResetOk
    }
    
    [*] --> ClosedHealthy: Initial State

    ClosedHealthy --> ClosedHealthy: Operation Succeeds
    ClosedHealthy --> OpenTripped: Failure count >= tolerance
    
    OpenTripped --> HalfOpenRecovering: refresh timeout expires
    
    HalfOpenRecovering --> ClosedHealthy: Test Operation Succeeds
    HalfOpenRecovering --> OpenTripped: Test Operation Fails

    OpenTripped --> ManualReset: CircuitBreaker.reset()
    ClosedHealthy --> ManualReset: CircuitBreaker.reset()
    ManualReset --> ClosedHealthy
```

## Config Graceful Degradation Flow

This flowchart illustrates the logic within `Config.GracefulDegradation.get_with_fallback`, showing how it attempts to retrieve configuration from the primary service and falls back to a cache if the service is unavailable.

```mermaid
flowchart TD
    Start["Start get_with_fallback(path)"] --> A{"Config.get(path) successful?"}
    
    A -- "Yes" --> B["Cache value in ETS with timestamp"]
    B --> C["Return {:ok, value}"]
    
    A -- "No (Service Unavailable)" --> D{"Get from ETS cache by path"}
    D --> E{"Found in cache?"}
    
    E -- "Yes" --> F{"Cache expired? (now - timestamp > TTL)"}
    F -- "No" --> G["Return {:ok, cached_value}"]
    F -- "Yes" --> H["Delete expired entry from cache"]
    H --> I["Return {:error, :config_unavailable}"]
    
    E -- "No" --> I

    style Start fill:#cce5ff,stroke:#333,stroke-width:2,color:#000
    style A fill:#fff3cd,stroke:#333,stroke-width:2,color:#000
    style E fill:#fff3cd,stroke:#333,stroke-width:2,color:#000
    style F fill:#fff3cd,stroke:#333,stroke-width:2,color:#000
    style B fill:#d1ecf1,stroke:#333,stroke-width:2,color:#000
    style D fill:#d1ecf1,stroke:#333,stroke-width:2,color:#000
    style H fill:#f8d7da,stroke:#333,stroke-width:2,color:#000
    style C fill:#d4edda,stroke:#333,stroke-width:2,color:#000
    style G fill:#d4edda,stroke:#333,stroke-width:2,color:#000
    style I fill:#f5c6cb,stroke:#333,stroke-width:2,color:#000
```

## Summary

These architectural diagrams illustrate the Foundation library's comprehensive design principles:

- **Layered Architecture:** Clear separation between API, logic, services, and infrastructure layers
- **Fault Tolerance:** Supervision trees and circuit breakers ensure system resilience
- **Observability:** Telemetry and event tracking provide visibility into system behavior
- **Testability:** Test isolation architecture enables reliable testing
- **Graceful Degradation:** Systems continue operating with reduced functionality when dependencies fail

The Foundation library provides a robust, observable, and maintainable foundation for Elixir applications, with clear architectural patterns that promote best practices in distributed system design.

