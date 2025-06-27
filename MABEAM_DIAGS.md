I'll create comprehensive Mermaid diagrams that expose MABEAM's internal architecture and concurrency patterns for senior BEAM/OTP engineers. Let me analyze the codebase and create detailed diagrams showing key data structures, process relationships, and message flows.

## 1. Overall System Architecture & Process Hierarchy

```mermaid
graph TB
    subgraph "MABEAM Application Supervision Tree"
        App["MABEAM.Application<br/>(Supervisor)"] 
        
        App --> Core["MABEAM.Core<br/>(GenServer)"]
        App --> AgentReg["MABEAM.AgentRegistry<br/>(GenServer)"]
        App --> AgentSup["MABEAM.AgentSupervisor<br/>(DynamicSupervisor)"]
        App --> Coord["MABEAM.Coordination<br/>(GenServer)"]
        App --> CoordSup["MABEAM.CoordinationSupervisor<br/>(DynamicSupervisor)"]
        App --> Comms["MABEAM.Comms<br/>(GenServer)"]
        App --> LoadBal["MABEAM.LoadBalancer<br/>(GenServer)"]
        App --> PerfMon["MABEAM.PerformanceMonitor<br/>(GenServer)"]
        App --> Telemetry["MABEAM.Telemetry<br/>(GenServer)"]
        
        subgraph "Process Registry Subsystem"
            App --> ProcReg["MABEAM.ProcessRegistry<br/>(Supervisor)"]
            ProcReg --> ProcRegServer["MABEAM.ProcessRegistry.Server<br/>(GenServer)"]
            ProcReg --> ProcRegAgentSup["MABEAM.ProcessRegistry.AgentSupervisor<br/>(DynamicSupervisor)"]
        end
        
        subgraph "Dynamic Agent Processes"
            AgentSup --> Agent1["Agent Process 1<br/>(GenServer)"]
            AgentSup --> Agent2["Agent Process 2<br/>(GenServer)"]
            AgentSup --> AgentN["Agent Process N<br/>(GenServer)"]
        end
        
        subgraph "Dynamic Coordination Workers"
            CoordSup --> CoordWorker1["MABEAM.CoordinationWorker<br/>(GenServer)"]
            CoordSup --> CoordWorker2["MABEAM.CoordinationWorker<br/>(GenServer)"]
        end
    end
    
    subgraph "Foundation Integration"
        Foundation["Foundation.ProcessRegistry<br/>(External)"]
        AgentReg -.-> Foundation
        ProcRegServer -.-> Foundation
        Telemetry -.-> Foundation
    end
    
    classDef supervisor fill:#e1f5fe,stroke:#0277bd,color:#000
    classDef genserver fill:#f3e5f5,stroke:#7b1fa2,color:#000
    classDef dynamic fill:#fff3e0,stroke:#ef6c00,color:#000
    classDef external fill:#e8f5e8,stroke:#388e3c,color:#000
    
    class App,ProcReg supervisor
    class Core,AgentReg,Coord,Comms,LoadBal,PerfMon,Telemetry,ProcRegServer genserver
    class AgentSup,CoordSup,ProcRegAgentSup,Agent1,Agent2,AgentN,CoordWorker1,CoordWorker2 dynamic
    class Foundation external
```

## 2. Agent Lifecycle & State Management

```mermaid
stateDiagram-v2
    [*] --> Unregistered
    
    Unregistered --> Registered: "AgentRegistry.register_agent/2"
    Registered --> Starting: "AgentRegistry.start_agent/1"
    Starting --> Running: "Agent process started successfully"
    Starting --> Failed: "Start failure"
    
    Running --> Stopping: "AgentRegistry.stop_agent/1"
    Running --> Failed: "Process crash/DOWN message"
    Running --> Migrating: "Node migration (future)"
    
    Stopping --> Stopped: "Graceful shutdown complete"
    Stopping --> Failed: "Forced termination"
    
    Stopped --> Starting: "Restart request"
    Failed --> Starting: "Restart/recovery"
    Failed --> Retired: "Permanent failure"
    
    Migrating --> Running: "Migration complete"
    Migrating --> Failed: "Migration failure"
    
    note right of Registered
        State: %{
          id: agent_id(),
          config: agent_config(),
          status: :registered,
          pid: nil,
          started_at: nil,
          restart_count: 0,
          metadata: map()
        }
    end note
    
    note right of Running
        State: %{
          status: :running,
          pid: actual_pid,
          started_at: DateTime.t(),
          monitors: {pid, ref}
        }
    end note
```

## 3. Agent Registry Internal Data Flow

```mermaid
graph TB
    subgraph "AgentRegistry State Structure"
        State["State: %{<br/>agents: %{agent_id => agent_info},<br/>monitors: %{pid => {agent_id, ref}},<br/>performance_metrics: map(),<br/>cleanup_interval: integer()<br/>}"]
    end
    
    subgraph "Registration Flow"
        RegCall["handle_call({:register_agent, id, config})"]
        ValidateConfig["validate_agent_config(config)"]
        CreateInfo["Create agent_info structure"]
        UpdateState["Update agents map"]
        RegisterFoundation["Register in Foundation.ProcessRegistry"]
        
        RegCall --> ValidateConfig
        ValidateConfig --> CreateInfo
        CreateInfo --> UpdateState
        UpdateState --> RegisterFoundation
    end
    
    subgraph "Start Flow"
        StartCall["handle_call({:start_agent, id})"]
        CheckStatus["Check agent status != :running"]
        StartViaSuper["start_agent_via_supervisor(id, config)"]
        MonitorProc["Process.monitor(pid)"]
        UpdateMonitors["Update monitors map"]
        UpdateFoundation["Update Foundation registry"]
        
        StartCall --> CheckStatus
        CheckStatus --> StartViaSuper
        StartViaSuper --> MonitorProc
        MonitorProc --> UpdateMonitors
        UpdateMonitors --> UpdateFoundation
    end
    
    subgraph "Monitor Flow"
        DownMsg["handle_info({:DOWN, ref, :process, pid, reason})"]
        LookupAgent["Map.get(monitors, pid)"]
        UpdateStatus["Update agent status to :failed"]
        CleanupMaps["Remove from monitors and update state"]
        EmitTelemetry["Emit crash telemetry"]
        
        DownMsg --> LookupAgent
        LookupAgent --> UpdateStatus
        UpdateStatus --> CleanupMaps
        CleanupMaps --> EmitTelemetry
    end
    
    classDef datastructure fill:#fff9c4,stroke:#f57f17,color:#000
    classDef process fill:#e8f5e8,stroke:#388e3c,color:#000
    classDef flow fill:#e3f2fd,stroke:#1976d2,color:#000
    
    class State datastructure
    class RegCall,StartCall,DownMsg process
    class ValidateConfig,CreateInfo,UpdateState,CheckStatus,StartViaSuper,MonitorProc,LookupAgent,UpdateStatus flow
```

## 4. Coordination Protocol State Machine

```mermaid
stateDiagram-v2
    [*] --> Idle
    
    Idle --> Creating: "coordinate_async/3"
    Creating --> Active: "Session created successfully"
    Creating --> Failed: "Session creation failed"
    
    Active --> Processing: "CoordinationWorker spawned"
    Processing --> Collecting: "Collecting agent responses"
    Collecting --> Analyzing: "All responses received"
    Collecting --> Timeout: "Coordination timeout"
    
    Analyzing --> Completed: "Consensus reached"
    Analyzing --> Failed: "Consensus failed"
    
    Completed --> Archived: "Results stored"
    Failed --> Archived: "Error details stored"
    Timeout --> Archived: "Timeout recorded"
    
    Archived --> Idle: "Session cleanup"
    
    note right of Active
        Session State: %{
          id: session_id,
          protocol_name: atom(),
          agent_ids: [agent_id()],
          context: map(),
          started_at: DateTime.t(),
          status: :active
        }
    end note
    
    note right of Processing
        Background Process:
        CoordinationWorker handles
        actual coordination logic
        while main GenServer
        tracks session state
    end note
```

## 5. Message Flow in Coordination System

```mermaid
sequenceDiagram
    participant Client
    participant Coordination as "MABEAM.Coordination"
    participant CoordSup as "CoordinationSupervisor"
    participant Worker as "CoordinationWorker"
    participant Agent1
    participant Agent2
    participant Comms as "MABEAM.Comms"
    
    Client->>Coordination: coordinate_async(protocol, agents, context)
    
    Note over Coordination: Generate session_id, validate inputs
    Coordination->>Coordination: Create session in active_sessions map
    
    Coordination->>CoordSup: start_coordination_process(protocol, agents, context, state)
    CoordSup->>Worker: DynamicSupervisor.start_child(child_spec)
    Worker-->>CoordSup: {:ok, pid}
    CoordSup-->>Coordination: {:ok, worker_pid}
    
    Coordination-->>Client: {:ok, session_id}
    
    Note over Worker: Async coordination execution begins
    Worker->>Worker: send(self(), :start_coordination)
    
    Worker->>Comms: request(agent1, coordination_request, timeout)
    Worker->>Comms: request(agent2, coordination_request, timeout)
    
    Comms->>Agent1: GenServer.call(pid, message, timeout)
    Comms->>Agent2: GenServer.call(pid, message, timeout)
    
    Agent1-->>Comms: response1
    Agent2-->>Comms: response2
    
    Comms-->>Worker: {:ok, response1}
    Comms-->>Worker: {:ok, response2}
    
    Note over Worker: Process responses, determine consensus
    
    Worker->>Coordination: send(coordination_server, {:coordination_result, result})
    
    Note over Coordination: handle_cast({:coordination_completed, session_id, results, session})
    Coordination->>Coordination: Move session to history, store results
    
    Worker->>Worker: {:stop, :normal, state}
    
    Note over Client: Client can poll for results using session_id
    Client->>Coordination: get_session_results(session_id)
    Coordination-->>Client: {:ok, results}
```

## 6. Communication System Internal Architecture

```mermaid
graph TB
    subgraph "MABEAM.Comms State"
        CommsState["State: %{<br/>total_requests: integer(),<br/>successful_requests: integer(),<br/>failed_requests: integer(),<br/>average_response_time: float(),<br/>active_requests: map()<br/>}"]
    end
    
    subgraph "Request Processing Pipeline"
        IncomingReq["handle_call({:request, agent_id, message, timeout})"]
        GetAgentPid["get_agent_pid(agent_id)"]
        ProcessReq["process_request(agent_pid, message, timeout)"]
        SendRequest["send_request_to_agent(agent_pid, message, timeout)"]
        UpdateStats["update_stats_and_emit_telemetry()"]
        
        IncomingReq --> GetAgentPid
        GetAgentPid --> ProcessReq
        ProcessReq --> SendRequest
        SendRequest --> UpdateStats
    end
    
    subgraph "Agent PID Resolution"
        CheckRegistry["ProcessRegistry.get_agent_info(agent_id)"]
        ValidatePid["Check if pid != nil and Process.alive?(pid)"]
        ReturnPid["Return {:ok, pid} or {:error, :not_found}"]
        
        CheckRegistry --> ValidatePid
        ValidatePid --> ReturnPid
    end
    
    subgraph "Deduplication Logic"
        CheckDupe["Check request_key in active_requests"]
        CacheResult["Store result for future duplicates"]
        ReturnCached["Return cached result for duplicates"]
        
        CheckDupe --> CacheResult
        CheckDupe --> ReturnCached
    end
    
    subgraph "Statistics Tracking"
        RequestCount["Increment total_requests"]
        ResponseTime["Calculate duration"]
        SuccessRate["Update success/failure counters"]
        AvgTime["Recalculate average_response_time"]
        
        RequestCount --> ResponseTime
        ResponseTime --> SuccessRate
        SuccessRate --> AvgTime
    end
    
    classDef state fill:#fff9c4,stroke:#f57f17,color:#000
    classDef process fill:#e8f5e8,stroke:#388e3c,color:#000
    classDef cache fill:#f3e5f5,stroke:#7b1fa2,color:#000
    classDef stats fill:#e1f5fe,stroke:#0277bd,color:#000
    
    class CommsState state
    class IncomingReq,GetAgentPid,CheckRegistry process
    class CheckDupe,CacheResult,ReturnCached cache
    class RequestCount,ResponseTime,SuccessRate,AvgTime stats
```

## 7. Load Balancer Agent Selection Algorithm

```mermaid
flowchart TD
    TaskReq["assign_task(task_spec)"]
    
    subgraph "Agent Filtering Pipeline"
        GetAgents["Get all registered agents from state.agents"]
        FilterCaps["Filter by required capabilities"]
        FilterOverload["Filter out overloaded agents (CPU > 0.9, etc.)"]
        FilterAlive["Filter by Process.alive?(pid) or test_mode"]
    end
    
    subgraph "Load Strategy Decision"
        CheckStrategy{"state.load_strategy"}
        RoundRobin["Round Robin:<br/>agent_list[task_counter % length]"]
        ResourceAware["Resource Aware:<br/>min_by(cpu_weight * 0.4 +<br/>memory_weight * 0.3 +<br/>task_weight * 0.3)"]
        CapabilityBased["Capability Based:<br/>max_by(matching_capabilities)"]
        PerformanceBased["Performance Based:<br/>min_by(average_task_duration)"]
    end
    
    subgraph "Assignment Tracking"
        UpdateCounter["Increment task_counter"]
        RecordAssignment["Add to assignment_history"]
        CreatePid["Create response_pid for test_mode"]
        UpdateState["Update state with new assignment"]
    end
    
    TaskReq --> GetAgents
    GetAgents --> FilterCaps
    FilterCaps --> FilterOverload
    FilterOverload --> FilterAlive
    
    FilterAlive --> CheckStrategy
    CheckStrategy -->|":round_robin"| RoundRobin
    CheckStrategy -->|":resource_aware"| ResourceAware
    CheckStrategy -->|":capability_based"| CapabilityBased
    CheckStrategy -->|":performance_weighted"| PerformanceBased
    
    RoundRobin --> UpdateCounter
    ResourceAware --> UpdateCounter
    CapabilityBased --> UpdateCounter
    PerformanceBased --> UpdateCounter
    
    UpdateCounter --> RecordAssignment
    RecordAssignment --> CreatePid
    CreatePid --> UpdateState
    
    UpdateState --> Return["Return {:ok, agent_id, pid}"]
    
    FilterAlive -->|"No suitable agents"| ErrorReturn["Return {:error, :no_suitable_agent}"]
    
    classDef filter fill:#e8f5e8,stroke:#388e3c,color:#000
    classDef strategy fill:#fff3e0,stroke:#ef6c00,color:#000
    classDef tracking fill:#e1f5fe,stroke:#0277bd,color:#000
    classDef decision fill:#fce4ec,stroke:#c2185b,color:#000
    
    class GetAgents,FilterCaps,FilterOverload,FilterAlive filter
    class RoundRobin,ResourceAware,CapabilityBased,PerformanceBased strategy
    class UpdateCounter,RecordAssignment,CreatePid,UpdateState tracking
    class CheckStrategy decision
```

## 8. Performance Monitor Data Flow

```mermaid
graph TB
    subgraph "Performance Monitor State"
        MonitorState["State: %{<br/>agent_metrics: %{agent_id => metrics},<br/>metrics_history: %{agent_id => [historical_metrics]},<br/>monitoring_status: %{agent_id => boolean},<br/>active_alerts: [alert],<br/>alert_thresholds: thresholds<br/>}"]
    end
    
    subgraph "Metrics Recording Flow"
        RecordCast["handle_cast({:record_metrics, agent_id, metrics})"]
        CheckMonitoring["Check monitoring_status[agent_id] or existing metrics"]
        AddTimestamp["Add timestamp to metrics"]
        UpdateCurrent["Update agent_metrics map"]
        UpdateHistory["Add to metrics_history with size limit"]
        CheckAlerts["check_and_update_alerts()"]
        
        RecordCast --> CheckMonitoring
        CheckMonitoring -->|"Monitoring enabled"| AddTimestamp
        CheckMonitoring -->|"Not monitored"| DropMetrics["Drop metrics (no recording)"]
        AddTimestamp --> UpdateCurrent
        UpdateCurrent --> UpdateHistory
        UpdateHistory --> CheckAlerts
    end
    
    subgraph "Alert Processing"
        CompareThresholds["Compare metrics vs alert_thresholds"]
        GenerateAlerts["Create new alert structs"]
        ResolveAlerts["Remove resolved alerts"]
        LogAlerts["Log new/resolved alerts"]
        UpdateActiveAlerts["Update active_alerts list"]
        
        CompareThresholds --> GenerateAlerts
        GenerateAlerts --> ResolveAlerts
        ResolveAlerts --> LogAlerts
        LogAlerts --> UpdateActiveAlerts
    end
    
    subgraph "Statistics Calculation"
        CalcStats["calculate_performance_statistics()"]
        CalcAvgCPU["Calculate average CPU across all agents"]
        CalcAvgMemory["Calculate average memory usage"]
        CalcTotals["Calculate totals and extremes"]
        
        CalcStats --> CalcAvgCPU
        CalcAvgCPU --> CalcAvgMemory
        CalcAvgMemory --> CalcTotals
    end
    
    classDef state fill:#fff9c4,stroke:#f57f17,color:#000
    classDef process fill:#e8f5e8,stroke:#388e3c,color:#000
    classDef alert fill:#ffebee,stroke:#d32f2f,color:#000
    classDef stats fill:#e1f5fe,stroke:#0277bd,color:#000
    
    class MonitorState state
    class RecordCast,CheckMonitoring,AddTimestamp,UpdateCurrent process
    class CompareThresholds,GenerateAlerts,ResolveAlerts,LogAlerts,UpdateActiveAlerts alert
    class CalcStats,CalcAvgCPU,CalcAvgMemory,CalcTotals stats
```

## 9. Telemetry Event Processing Pipeline

```mermaid
graph LR
    subgraph "Event Sources"
        AgentEvents["Agent Lifecycle Events<br/>:registered, :started,<br/>:stopped, :failed"]
        CoordEvents["Coordination Events<br/>:started, :completed,<br/>:failed"]
        CustomMetrics["Custom Metrics<br/>record_agent_metric(),<br/>record_system_metric()"]
    end
    
    subgraph "Telemetry Handler Attachment"
        AttachHandlers["attach_telemetry_handlers()"]
        TelemetryEvents["[:foundation, :mabeam, :agent, :*]<br/>[:foundation, :mabeam, :coordination, :*]"]
        CallbackSetup[":telemetry.attach(event, &handle_telemetry_event/4)"]
        
        AttachHandlers --> TelemetryEvents
        TelemetryEvents --> CallbackSetup
    end
    
    subgraph "Event Processing in GenServer"
        IncomingEvent["handle_telemetry_event(event, measurements, metadata)"]
        CastToSelf["GenServer.cast(self(), {:telemetry_event, ...})"]
        ProcessEvent["process_telemetry_event(state, event, measurements, metadata)"]
        
        IncomingEvent --> CastToSelf
        CastToSelf --> ProcessEvent
    end
    
    subgraph "State Updates"
        UpdateMetrics["Update agent_metrics or coordination_metrics"]
        AddToHistory["Add metric_entry to metric_history"]
        CapacityLimit["Enforce max_history_size limit"]
        IncrementCounter["Increment total_metrics_collected"]
        
        UpdateMetrics --> AddToHistory
        AddToHistory --> CapacityLimit
        CapacityLimit --> IncrementCounter
    end
    
    subgraph "Data Structures"
        MetricEntry["metric_entry: %{<br/>agent_id: agent_id | nil,<br/>metric_name: atom,<br/>value: number,<br/>metadata: map,<br/>timestamp: DateTime.t,<br/>tags: [String.t]<br/>}"]
        
        AgentMetrics["agent_metrics: %{<br/>response_times: [float],<br/>success_rates: [float],<br/>error_counts: [integer],<br/>uptime_percentage: float<br/>}"]
    end
    
    AgentEvents --> IncomingEvent
    CoordEvents --> IncomingEvent
    CustomMetrics --> ProcessEvent
    
    ProcessEvent --> UpdateMetrics
    UpdateMetrics --> MetricEntry
    UpdateMetrics --> AgentMetrics
    
    classDef source fill:#e8f5e8,stroke:#388e3c,color:#000
    classDef handler fill:#fff3e0,stroke:#ef6c00,color:#000
    classDef process fill:#e3f2fd,stroke:#1976d2,color:#000
    classDef data fill:#fff9c4,stroke:#f57f17,color:#000
    
    class AgentEvents,CoordEvents,CustomMetrics source
    class AttachHandlers,TelemetryEvents,CallbackSetup handler
    class IncomingEvent,CastToSelf,ProcessEvent,UpdateMetrics process
    class MetricEntry,AgentMetrics data
```

## 10. Process Registry Backend & ETS Integration

```mermaid
graph TB
    subgraph "ProcessRegistry Architecture"
        ProcRegSup["MABEAM.ProcessRegistry<br/>(Supervisor)"]
        ProcRegServer["MABEAM.ProcessRegistry.Server<br/>(GenServer)"]
        AgentSupervisor["DynamicSupervisor<br/>(AgentSupervisor)"]
        
        ProcRegSup --> ProcRegServer
        ProcRegSup --> AgentSupervisor
    end
    
    subgraph "Backend ETS Tables"
        MainTable[":mabeam_process_registry<br/>(Main Agent Table)<br/>Key: agent_id<br/>Value: {agent_id, agent_entry}"]
        
        CapabilityTable[":mabeam_capability_index<br/>(Capability Index)<br/>Key: capability<br/>Value: {capability, agent_id}"]
        
        TableRegistry[":ets_backend_tables<br/>(Table Registry)<br/>Tracks table names globally"]
    end
    
    subgraph "Agent Entry Structure"
        AgentEntry["agent_entry: %{<br/>id: agent_id(),<br/>config: agent_config(),<br/>pid: pid() | nil,<br/>status: atom(),<br/>started_at: DateTime.t() | nil,<br/>stopped_at: DateTime.t() | nil,<br/>metadata: map(),<br/>node: node()<br/>}"]
    end
    
    subgraph "ETS Operations Flow"
        RegisterOp["register_agent(entry)"]
        ETSInsert[":ets.insert(main_table, {entry.id, entry})"]
        IndexCaps["Index capabilities in capability_table"]
        
        RegisterOp --> ETSInsert
        ETSInsert --> IndexCaps
        
        FindCaps["find_agents_by_capability(capabilities)"]
        ETSLookup[":ets.lookup(capability_table, capability)"]
        Intersection["MapSet intersection for multiple capabilities"]
        
        FindCaps --> ETSLookup
        ETSLookup --> Intersection
    end
    
    subgraph "Concurrent Access Configuration"
        ETSOptions["ETS Table Options:<br/>:named_table, :public, :set<br/>read_concurrency: true<br/>write_concurrency: true"]
        
        CapabilityOptions["Capability Table Options:<br/>:named_table, :public, :bag<br/>read_concurrency: true<br/>write_concurrency: true"]
    end
    
    ProcRegServer -.-> MainTable
    ProcRegServer -.-> CapabilityTable
    MainTable -.-> TableRegistry
    CapabilityTable -.-> TableRegistry
    
    MainTable --> AgentEntry
    
    classDef supervisor fill:#e1f5fe,stroke:#0277bd,color:#000
    classDef genserver fill:#f3e5f5,stroke:#7b1fa2,color:#000
    classDef ets fill:#fff9c4,stroke:#f57f17,color:#000
    classDef structure fill:#e8f5e8,stroke:#388e3c,color:#000
    classDef operations fill:#fff3e0,stroke:#ef6c00,color:#000
    
    class ProcRegSup supervisor
    class ProcRegServer genserver
    class MainTable,CapabilityTable,TableRegistry ets
    class AgentEntry structure
    class RegisterOp,ETSInsert,IndexCaps,FindCaps,ETSLookup,Intersection operations
```

This comprehensive set of diagrams exposes the key internal mechanisms of MABEAM:

1. **Overall architecture** shows the supervision tree and process relationships
2. **Agent lifecycle** reveals the state machine and transitions
3. **Registry data flow** exposes internal state management and monitoring
4. **Coordination state machine** shows protocol execution phases
5. **Message flow** demonstrates inter-process communication patterns
6. **Communication system** reveals request processing and deduplication
7. **Load balancer** shows agent selection algorithms and filtering
8. **Performance monitor** exposes metrics collection and alerting
9. **Telemetry pipeline** shows event processing and state updates
10. **Process registry backend** reveals ETS table structure and concurrent access patterns

Each diagram focuses on the critical data structures, concurrent access patterns, and message flows that senior BEAM/OTP engineers need to understand for debugging, optimization, and extending the system.
