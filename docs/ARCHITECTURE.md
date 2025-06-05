# Foundation Architecture

This document describes the architecture of the Foundation library.

## System Overview

The Foundation library follows a layered architecture with clear separation of concerns:

```mermaid
graph TB
    A[Public API Layer] --> B[Business Logic Layer]
    B --> C[Service Layer]
    C --> D[Infrastructure Layer]
    
    A1[Foundation.Config] --> A
    A2[Foundation.Events] --> A
    A3[Foundation.Telemetry] --> A
    A4[Foundation.Infrastructure] --> A
    
    B1[Foundation.Logic.Config] --> B
    B2[Foundation.Logic.Event] --> B
    
    C1[Foundation.Services.ConfigServer] --> C
    C2[Foundation.Services.EventStore] --> C
    C3[Foundation.Services.TelemetryService] --> C
    
    D1[Foundation.ProcessRegistry] --> D
    D2[Foundation.ServiceRegistry] --> D
    D3[Foundation.Infrastructure.ConnectionManager] --> D
```

## Component Interactions

The following diagram shows how the main components interact:

```mermaid
sequenceDiagram
    participant Client
    participant Config
    participant Events
    participant Telemetry
    participant Infrastructure
    
    Client->>Config: get/update configuration
    Config->>Events: emit config events
    Events->>Telemetry: track metrics
    
    Client->>Infrastructure: execute protected operation
    Infrastructure->>Telemetry: record circuit breaker stats
    Infrastructure->>Events: log protection events
```

## Data Flow

```mermaid
flowchart LR
    Input[User Input] --> Validation[Validation Layer]
    Validation --> Logic[Business Logic]
    Logic --> Storage[Data Storage]
    Storage --> Events[Event Generation]
    Events --> Telemetry[Metrics Collection]
    Telemetry --> Monitoring[External Monitoring]
```
