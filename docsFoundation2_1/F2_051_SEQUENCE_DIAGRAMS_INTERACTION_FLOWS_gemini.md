# Foundation 2.0: Sequence Diagrams & Interaction Flows

**Purpose**: To visualize the dynamic interactions between components for key operations. This clarifies timing, dependencies, and potential race conditions.

## 1. Flow: `Foundation.ProcessManager.start_singleton`

This shows the interaction to start a globally unique process.

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant PMF as ProcessManager Facade
    participant HDS as Horde.DynamicSupervisor
    participant HR as Horde.Registry

    Dev->>PMF: start_singleton(MyWorker, [], name: :worker1)
    PMF->>HDS: start_child(child_spec)
    activate HDS
    HDS-->>PMF: {:ok, pid}
    deactivate HDS
    
    PMF->>HR: register(:worker1, pid)
    activate HR
    HR-->>PMF: :ok
    deactivate HR
    
    PMF-->>Dev: {:ok, pid}

    Note right of HR: At this point, :worker1 is only <br/>registered on the local node's CRDT.

    participant Gossip as Horde Gossip Protocol
    HR->>Gossip: Broadcasts CRDT delta
    activate Gossip
    Gossip->>OtherNodeHR: Syncs delta
    deactivate Gossip

    Note right of HR: After gossip, :worker1 becomes <br/>globally discoverable.
```

## 2. Flow: Cluster Healing After Node Failure

This shows how a singleton process recovers when its node dies.

```mermaid
sequenceDiagram
    participant LibC as libcluster
    participant HealthM as HealthMonitor
    participant HDS as Horde.DynamicSupervisor
    participant HR as Horde.Registry
    
    Note over LibC, HR: Node C fails unexpectedly.

    LibC->>HealthM: Publishes `{:node_down, :nodeC@host}`
    activate HealthM
    HealthM->>HealthM: Logs critical event
    deactivate HealthM

    HDS->>HDS: Detects supervised process from Node C is down.
    Note over HDS: Horde's distributed supervision kicks in.
    
    HDS->>HDS: Selects new node (e.g., Node A) for restart.
    
    HDS->>NodeA: Starts new instance of the process.
    activate HDS
    NodeA-->>HDS: {:ok, new_pid}
    deactivate HDS

    HR->>HR: Detects registry entry for PID from Node C is stale.
    HR->>HR: Updates registry to point to `new_pid` on Node A.
    
    Note over HR: The service is now back online on a new node.
```

## 3. Flow: `set_cluster_wide` Configuration Change

This shows the simplified consensus flow for a distributed config update.

```mermaid
sequenceDiagram
    participant Dev as Developer
    participant ConfF as Config Facade
    participant Chan as Foundation.Channels
    participant OtherNodes as Other Nodes (Subscribers)
    
    Dev->>ConfF: set_cluster_wide(:feature, true)
    ConfF->>Chan: broadcast(:control, {:consensus_req, ...})
    activate Chan
    Note over Chan: Publishes to "foundation:control" topic.
    Chan-->>ConfF: :ok
    deactivate Chan
    
    Chan->>OtherNodes: Delivers consensus request message.
    activate OtherNodes
    OtherNodes->>Chan: broadcast(:control, {:consensus_ack, ...})
    deactivate OtherNodes
    
    ConfF->>ConfF: Collects ACKs within timeout.
    Note over ConfF: Assumes majority ACKs received.
    
    ConfF->>ConfF: Applies change locally.
    ConfF->>Chan: broadcast(:config, {:config_updated, ...})
    activate Chan
    Chan-->>ConfF: :ok
    deactivate Chan

    Chan->>OtherNodes: Delivers final config update.
    activate OtherNodes
    OtherNodes->>OtherNodes: Apply change locally.
    deactivate OtherNodes
    
    ConfF-->>Dev: :ok
```