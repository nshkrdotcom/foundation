## Codebase Design: Integrating BEAM Primitives with Partisan Distribution

### 1. Overview

- **Goal:** This document outlines how Foundation 2.0 will synergize its advanced BEAM primitives (such as process ecosystems and fine-grained memory management) with the Partisan-based distributed computing layer. The aim is to create a cohesive framework where applications can seamlessly scale from single-node concurrent operation to large, resilient distributed systems.
- **Core Idea:** The design philosophy is to combine the inherent strengths of the BEAM VM for local concurrency, fault isolation, and efficient process management with Partisan's capabilities for scalable clustering, robust multi-channel communication, and dynamic network topologies. This integration will enable developers to build applications that are both deeply BEAM-native and enterprise-grade distributed.

### 2. Distributed Process Ecosystems

- **Concept:** Extend the `Foundation.BEAM.Processes` module to allow "Process Ecosystems" (coordinated groups of processes working towards a common goal) to span multiple nodes within a Partisan cluster. This allows for greater computational resources, fault tolerance (by distributing work), and data locality.

- **Key Modules:**
    - `Foundation.BEAM.Processes`: Primary module for defining and managing ecosystems. Will require enhancements for distribution.
    - `Foundation.BEAM.Distribution`: Provides the underlying mechanism for cross-node process interaction (spawning, messaging) via Partisan.

- **Design Points:**
    - **Spawning Across Nodes:**
        - The `Foundation.BEAM.Processes.spawn_ecosystem/1` function (and related `start_ecosystem/1`) will be enhanced to accept distribution options.
          ```elixir
          # Example
          Foundation.BEAM.Processes.spawn_ecosystem(
            coordinator: MyApp.MyCoordinator,
            workers: {MyApp.MyWorker, count: 100},
            strategy: :one_for_one,
            distribution: %{
              policy: :cluster_wide, # :explicit_nodes, :local_only
              nodes: [:node2@host, :node3@host], # if policy is :explicit_nodes
              placement_strategy: :round_robin # :least_loaded, :random
            }
          )
          ```
        - When the ecosystem's coordinator (itself potentially placed on a specific node) needs to spawn workers on remote nodes, it will not use `Node.spawn_link/4` directly. Instead, it will likely:
            1.  Interface with a local or remote "Process Factory" or "Ecosystem Placement Manager" service.
            2.  This service, running on each target node, would receive a request (via `Foundation.BEAM.Distribution.send/3`) to start a specific worker type.
            3.  The remote factory then uses its local `Foundation.BEAM.Processes` or standard OTP primitives to spawn and supervise the worker.
    - **Cross-Node Supervision:**
        - **Local Supervision:** Each worker process spawned on a remote node will be supervised by a local supervisor on that same node (part of the remote factory's responsibility). This ensures local BEAM fault tolerance.
        - **Coordinator-Worker Monitoring:** The ecosystem's coordinator (wherever it resides) will monitor its workers. This monitoring can be done via:
            - Standard Erlang/Elixir `monitor/2` if PIDs are directly known and Partisan handles proxying these monitors (less likely for scalability).
            - More likely, through an explicit check-in mechanism or by relying on Partisan's node/process liveness information relayed by `Foundation.BEAM.Distribution`.
        - **Node Failure Handling:** If a node hosting workers fails (detected via Partisan events propagated by `Foundation.BEAM.Distribution`), the coordinator is responsible for reacting according to the ecosystem's policy (e.g., attempting to re-spawn the lost workers on other available nodes).
    - **Communication within Distributed Ecosystems:**
        - Processes within an ecosystem (e.g., worker-to-coordinator, worker-to-worker) that reside on different nodes will use `Foundation.BEAM.Distribution.send/3` for communication.
        - The future `Foundation.BEAM.Messages` module will play a crucial role here. It will need to be Partisan-aware to select appropriate communication channels (via `Foundation.Distributed.Channels`) for different message types (e.g., control vs. data) and to optimize data serialization for cross-node traffic.
          ```elixir
          # Conceptual example within Foundation.BEAM.Messages
          def send_optimized(dest_pid_or_name_on_node, message, opts \\ []) do
            channel = Keyword.get(opts, :channel, :default_ecosystem_data) # Get from opts or default
            # Foundation.BEAM.Distribution.send(dest_node, remote_pid_or_name, message, channel_override: channel)
            # or directly use Foundation.Distributed.Channels
            Foundation.Distributed.Channels.send_message(channel, dest_pid_or_name_on_node, message, [])
          end
          ```

### 3. Distributed State Management for Ecosystems

- **Challenge:** Managing the state of the ecosystem coordinator (if it's stateful) and any shared state among distributed workers, especially when the coordinator might need to be restarted on a different node or when workers need consistent views of shared data.

- **Strategies:**
    - **Replicated State (for critical coordinator state):**
        - **CRDTs (Conflict-free Replicated Data Types):** For state that can tolerate eventual consistency and requires high availability, CRDTs can be replicated across multiple nodes (coordinator replicas or designated state nodes). Partisan channels can be used for CRDT state dissemination.
        - **Distributed Consensus (`Foundation.Distributed.Consensus`):** For state requiring strong consistency (e.g., leader election for a single active coordinator, critical configuration), a Raft or Paxos-like consensus protocol implemented over Partisan channels will be used. This is a planned Foundation 2.0 module.
    - **Distributed Cache:**
        - For less critical, eventually consistent shared data that workers might need, a distributed caching layer (potentially built using Partisan primitives like broadcast or gossip for cache updates/invalidations) can be employed. `Foundation.Distributed.Discovery` might also play a role if caches are registered as services.
    - **State Handoff / External Storage:**
        - For planned coordinator migration or recovery after a failure, the coordinator's state can be periodically checkpointed to durable external storage (e.g., a database, distributed file system). A new coordinator instance would load this state upon startup.
        - Alternatively, for live handoff, a more direct state transfer mechanism via Partisan could be used if the old coordinator is still alive.

### 4. Leveraging `Foundation.Distributed.*` Modules

The distributed nature of these enhanced BEAM primitives relies heavily on the capabilities provided by other Foundation 2.0 distribution modules:

- **`Foundation.Distributed.Channels`:**
    - Distributed ecosystems can define preferences for which Partisan channels their internal communications should use. For example:
        - Coordinator-to-worker control signals: High-priority, reliable channel (e.g., `:ecosystem_control`).
        - Inter-worker data exchange: Medium-priority, potentially best-effort channel optimized for throughput (e.g., `:ecosystem_data`).
    - The `spawn_ecosystem/1` function's `distribution` options could include these channel preferences, which would then be used by `Foundation.BEAM.Messages` or internal communication logic.

- **`Foundation.Distributed.Topology`:**
    - **Placement Strategy:** The decision of where to place workers in a distributed ecosystem (when `placement_strategy` is e.g., `:topology_aware`) can be influenced by the current cluster topology reported by `Foundation.Distributed.Topology`. For instance, preferring nodes that are "closer" in a HyParView sense to reduce communication latency.
    - **Adaptive Communication:** Ecosystems might query the current topology to adapt their communication patterns. For example, if the topology switches to one with higher latency characteristics, an ecosystem might opt for more batching of messages.

- **`Foundation.Distributed.Discovery`:**
    - **Ecosystem Registration:** A distributed process ecosystem (or its coordinator/entry point) can be registered as a discoverable service using `Foundation.Distributed.Discovery`. This allows other services or clients to find and interact with the ecosystem.
    - **Dependency Discovery:** Ecosystems themselves might need to discover other services (e.g., databases, external APIs, other collaborating ecosystems) and will use `Foundation.Distributed.Discovery` for this purpose.

### 5. Memory Management in a Distributed Context

- **Isolated Heaps (Local Benefit):** The core benefit of `Foundation.BEAM.Memory`'s focus on isolated heaps (e.g., per-process or per-group-of-processes) remains primarily a local-node optimization. It helps in reducing GC interference and improving memory management efficiency on each node where parts of the distributed ecosystem run.

- **Cross-Node Data Transfer & Serialization:**
    - **`Foundation.BEAM.Messages` (Future):** This module will be critical for optimizing data transfer between nodes. When messages are sent via Partisan:
        - **Efficient Serialization:** It should employ efficient serialization formats (e.g., Erlang External Term Format, Protocol Buffers, or custom binary formats) to minimize the size of data transmitted over the network.
        - **Minimize Copying:** Strategies to minimize data copying before network transmission will be important.
    - **Large Binaries/Blobs:** For transferring large data, consider:
        - **Reference Counting (if Partisan supports):** If Partisan could support a form of distributed reference counting for large binaries (highly advanced and unlikely without deep Partisan integration), it could avoid redundant transfers.
        - **Streaming/Chunking:** Transfer large data in chunks over Partisan channels designed for bulk transfer, rather than as single large messages.
        - **Out-of-Band Transfer:** For very large data, consider transferring it via a dedicated file/blob storage system and only sending references/notifications via Partisan.

### 6. Fault Tolerance and Self-Healing in Distributed Ecosystems

This is where the synergy of BEAM's local supervision and Partisan's cluster awareness truly shines.

- **Node Failure:**
    - **Detection:** `Foundation.BEAM.Distribution` (via Partisan events) signals that a node is down.
    - **Ecosystem Reaction:**
        - **Worker Re-spawning:** If workers were on the failed node, the ecosystem's coordinator (if still alive) is notified and, based on policy, attempts to re-spawn these workers on other available/healthy nodes. This process would use the distributed spawning mechanism.
        - **Coordinator Failure:** If the node hosting the ecosystem's coordinator fails:
            - A mechanism must exist to restart or failover the coordinator to another node. This might involve:
                - A supervising application or another meta-coordinator.
                - Leader election (via `Foundation.Distributed.Consensus`) among potential coordinator candidates if multiple instances can take over.
                - Loading state from persistent storage or a replica (see Distributed State Management).
- **Network Partitions:**
    - **Detection:** Partisan (via `Foundation.BEAM.Distribution`) provides information about network partitions (e.g., which nodes are unreachable).
    - **Ecosystem Strategy:** The ecosystem must decide how to behave during a partition:
        - **Degraded Operation:** Continue operating with reduced capacity or functionality within each partition if possible.
        - **Read-Only Mode:** Some parts might switch to read-only mode.
        - **Halt/Quorum:** Halt operations that require cross-partition consistency until the partition heals. `Foundation.Distributed.Consensus` is key for services that need to make decisions based on a quorum of nodes.
        - **Conflict Resolution:** If state diverges during a partition, a strategy for conflict resolution upon healing will be needed (e.g., last-write-wins, CRDT merge procedures).

### 7. Realizing "Intelligent Infrastructure Layer" for Scalability

The concepts from the battle plan's "Intelligent Infrastructure Layer" are enabled by this tight integration.

- **Adaptive Ecosystems (`Foundation.Intelligence.PredictiveScaling`):**
    - Distributed ecosystems can monitor their internal metrics (e.g., queue lengths of workers, processing latency, error rates of coordinator).
    - Based on these metrics or external triggers (e.g., increased request rate from an API gateway), an ecosystem's coordinator can decide to:
        - Request `Foundation.BEAM.Processes` to spawn more workers (distributed across the cluster).
        - Release/terminate idle workers.
    - This feedback loop allows ecosystems to dynamically scale their distributed workforce.

- **Self-Optimizing Topologies for Ecosystems (`Foundation.Intelligence.AdaptiveTopology` - Advanced):**
    - While `Foundation.Distributed.Topology` manages the global cluster topology, heavily communicating distributed ecosystems could potentially request or influence the formation of more direct communication paths or even specialized Partisan sub-overlays (if Partisan supports such a concept) to optimize their specific traffic patterns. This is a very advanced concept.

### 8. Scalability to Thousands of Nodes: Codebase Implications

- **Minimize Global State & Centralized Bottlenecks:** Design ecosystems and their coordination logic to be as decentralized as possible. Avoid relying on single processes for critical path operations across the entire cluster.
- **Efficient Communication Protocols:** Emphasize the use of `Foundation.Distributed.Channels` for targeted and prioritized messaging. `Foundation.BEAM.Messages` must ensure efficient serialization.
- **Asynchronous Operations:** Cross-node interactions (spawning, messaging, state updates) should predominantly be asynchronous to avoid blocking and improve responsiveness. Callbacks, promises, or event-driven patterns will be common.
- **Decentralized Decision Making:** Empower individual components of a distributed ecosystem (e.g., local supervisors, workers) to make decisions based on local information where feasible, reducing the need for constant coordination with a central point.
- **Robust and Aggregated Monitoring (`Foundation.Telemetry 2.0`):** Collecting, aggregating, and analyzing telemetry data from thousands of distributed processes (BEAM primitives) and Partisan nodes is crucial for understanding system behavior and enabling intelligent adaptations. This requires an efficient, cluster-aware telemetry pipeline.

### 9. Open Questions / Future Work

- **Distributed Process Registries:** How are named processes within a distributed ecosystem discovered by other processes across the cluster?
    - Partisan offers `partisan_process_registry`. Foundation might provide a higher-level API over this or integrate it with `Foundation.Distributed.Discovery`.
- **Security for Cross-Node Ecosystem Communication:**
    - Ensuring messages between ecosystem components on different nodes are encrypted and authenticated (leveraging Partisan's security features and `Foundation.Distributed.Channels` configurations).
    - Access control for spawning processes or invoking operations on remote parts of an ecosystem.
- **Debugging and Tracing Distributed Ecosystems:**
    - Developing tools and practices for tracing requests and debugging issues that span multiple processes across multiple nodes within an ecosystem. This will likely involve integration with distributed tracing systems and enhanced logging in Foundation modules.
- **Backpressure Across Distributed Ecosystems:** Implementing effective backpressure mechanisms that propagate across nodes when a part of a distributed ecosystem is overloaded. This needs to work in conjunction with Partisan's flow control and `Foundation.Distributed.Channels`.
