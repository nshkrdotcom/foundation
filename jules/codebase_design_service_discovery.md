## Codebase Design: Intelligent Service Discovery

### 1. Overview
The purpose of intelligent service discovery within Foundation 2.0 is to provide a robust, dynamic, and cluster-aware mechanism for locating and connecting to services. This goes beyond simple node discovery by incorporating service capabilities, health status, versioning, and potentially network topology or load considerations. The key module responsible for this functionality is `Foundation.Distributed.Discovery`, which will leverage Partisan for inter-node communication.

### 2. `Foundation.Distributed.Discovery` Module

- **Purpose:** This module acts as a distributed registry and query engine for services running within the Foundation cluster. It manages the lifecycle of service registrations, provides a rich query interface for discovering services, and incorporates health and capability awareness.

- **State Management (GenServer `defstruct` from `FOUNDATION2_04_PARTISAN_DISTRO_REVO.md`):**
  The GenServer will manage several pieces of state, likely backed by ETS tables for concurrent access and efficiency, especially in a busy cluster.
  ```elixir
  defmodule Foundation.Distributed.Discovery do
    use GenServer

    defstruct [
      :discovery_strategies, # List of atoms like [:local, :cluster, :external], defining search order/scope.
      :service_cache,        # Name of ETS table: {service_id_tuple, node_registered_on} -> service_info_map. service_id_tuple = {service_name, service_instance_id_or_node}
      :health_monitors,      # ETS table or map: service_id_tuple -> health_check_pid_or_ref (for active checks) or last_heartbeat_timestamp.
      :capability_index,     # Name of ETS table: capability_atom -> list_of_service_id_tuples.
      :subscribers           # ETS table or map: subscription_criteria_hash -> list_of_subscriber_pids.
    ]

    # ... GenServer callbacks ...
  end
  ```
  *Note on ETS tables:* Using named ETS tables owned by the GenServer process allows other processes (e.g., health checkers) to read/write concurrently if necessary, while the GenServer can still act as the primary mutator or coordinator.

- **Proposed Core Functions (Elixir syntax, based on `FOUNDATION2_04_PARTISAN_DISTRO_REVO.md`):**
  ```elixir
  defmodule Foundation.Distributed.Discovery do
    use GenServer

    @doc """
    Starts the Service Discovery manager GenServer.
    Initializes ETS tables and loads configured discovery strategies.
    """
    def start_link(opts \\ []) do
      # Default strategies: [:local, :cluster]
      # Opts could override strategies or provide ETS table names/options.
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @impl true
    def init(opts) do
      # Initialize ETS tables
      service_cache_tid = :ets.new(:service_cache, [:set, :protected, :named_table, read_concurrency: true])
      capability_index_tid = :ets.new(:capability_index, [:bag, :protected, :named_table, read_concurrency: true]) # :bag for multiple services per capability
      health_monitors_tid = :ets.new(:health_monitors, [:set, :protected, :named_table, read_concurrency: true])
      subscribers_tid = :ets.new(:discovery_subscribers, [:set, :protected, :named_table, read_concurrency: true])

      state = %{
        discovery_strategies: Keyword.get(opts, :discovery_strategies, [:local, :cluster]),
        service_cache: service_cache_tid,
        health_monitors: health_monitors_tid,
        capability_index: capability_index_tid,
        subscribers: subscribers_tid
      }
      {:ok, state}
    end

    @doc """
    Registers a service with its name, PID, capabilities, and other metadata.
    The service is registered on the local node and this registration is broadcast
    to other discovery managers in the cluster.
    """
    def register_service(service_name :: atom(), pid :: pid(), capabilities :: list(atom()), metadata :: map() \\ %{}) :: :ok | {:error, any()} do
      node = Node.self()
      service_id = {service_name, node} # Assuming one instance of a named service per node for simplicity here. Could be more complex.
      service_info = %{
        name: service_name,
        node: node,
        pid: pid,
        capabilities: Enum.uniq(capabilities),
        version: Map.get(metadata, :version),
        metadata: metadata,
        health_status: :unknown, # Initial status, to be updated by health monitoring
        registered_at: System.monotonic_time(:millisecond)
      }
      GenServer.call(__MODULE__, {:register_service, service_id, service_info})
    end

    @doc """
    Deregisters a service instance previously registered with `service_name` on the given `node`.
    Typically called when a service shuts down gracefully.
    """
    def deregister_service(service_name :: atom(), node :: atom() \\ Node.self()) :: :ok | {:error, any()} do
      service_id = {service_name, node}
      GenServer.call(__MODULE__, {:deregister_service, service_id})
    end

    @doc """
    Discovers services based on a set of criteria.
    Criteria can include :service_name, :capabilities (list, all must match),
    :health_status, :version_match (string or regex), :node, etc.
    """
    def discover_services(criteria :: Keyword.t() | map()) :: {:ok, list(map())} | {:error, any()} do
      # This call will be handled by the GenServer, which implements the discover_with_criteria/2 logic.
      GenServer.call(__MODULE__, {:discover_services, criteria})
    end

    @doc """
    Gets the current health status of a specific service instance.
    """
    def get_service_health(service_name :: atom(), node :: atom()) :: {:ok, atom()} | {:error, any()} do
      service_id = {service_name, node}
      GenServer.call(__MODULE__, {:get_service_health, service_id})
    end

    @doc """
    Subscribes the calling process to receive messages when services matching
    the given criteria are registered or deregistered, or their health status changes.
    """
    def subscribe(criteria :: Keyword.t() | map()) :: :ok do
      # The GenServer will store {hashed_criteria, self()} in :subscribers table/map.
      GenServer.cast(__MODULE__, {:subscribe, criteria, self()})
    end

    # ... GenServer handle_call/handle_cast implementations ...
    # handle_call for :register_service would write to ETS, update index, and broadcast.
    # handle_call for :discover_services would query ETS tables based on criteria.
  end
  ```

### 3. Data Structures

- **Service Information (`service_info_map` stored in `:service_cache` ETS table):**
  The value associated with a `service_id` key in the `:service_cache`.
  ```elixir
  %{
    name: :my_db_server,                # Atom: The logical name of the service type
    instance_id: "worker_73a",          # Optional: A unique ID for this instance if multiple of the same name exist on a node
    node: :node1@example.com,           # Atom: The node where the service is running
    pid: #PID<0.1234.0>,                # PID: The process identifier of the service
    capabilities: [:read_replica, :ha, :timeseries_optimized], # List of atoms: Features this service instance offers
    version: "1.2.3",                   # String: Version of the service software
    metadata: %{                        # Map: Application-specific metadata
      region: "us-east-1",
      load_factor: 0.3,
      shards_managed: [1, 5, 7]
    },
    health_status: :healthy,            # Atom: e.g., :healthy, :degraded, :unhealthy, :unknown
    registered_at: 1678886400123,       # Integer: System.monotonic_time(:millisecond) at registration
    last_health_update: 1678886460345   # Integer: Timestamp of last health status update
  }
  ```

- **Capability Index (`:capability_index` ETS table - type `:bag`):**
  - **Key:** `capability_atom` (e.g., `:read_replica`)
  - **Value:** `service_id` (e.g., `{{:my_db_server, "worker_73a"}, :node1@example.com}`)
  A `:bag` table allows multiple services to be associated with the same capability.

### 4. Service Registration and Deregistration

- **Registration (`register_service/4`):**
    1.  The calling service invokes `Foundation.Distributed.Discovery.register_service(...)` on its local node.
    2.  The local `Foundation.Distributed.Discovery` GenServer receives the request.
    3.  It validates the data and inserts/updates the `service_info_map` in its local `:service_cache` ETS table.
    4.  For each capability in `service_info.capabilities`, it adds an entry to the local `:capability_index` ETS table: `{capability, service_id}`.
    5.  The local manager then broadcasts the complete `service_info_map` to all other known `Foundation.Distributed.Discovery` managers in the cluster (e.g., using Partisan broadcast on a dedicated `:discovery_events` channel).
    6.  Remote `Foundation.Distributed.Discovery` instances receive this broadcast and update their local caches and indices accordingly.
    7.  Relevant subscribers are notified.

- **Deregistration (`deregister_service/2`):**
    1.  Follows a similar pattern: local ETS removal, then broadcast of the `service_id` to be deregistered.
    2.  Remote instances remove the service from their caches and capability index.
    3.  Relevant subscribers are notified.

- **Handling Node Failures (Partisan Integration):**
    1.  `Foundation.Distributed.Discovery` (or a dedicated process it supervises) should subscribe to Partisan's node membership events (e.g., `node_down` from `Foundation.BEAM.Distribution`).
    2.  Upon receiving a `node_down` event for a particular node, the local Discovery manager iterates through its `:service_cache` and removes all services registered from that downed node.
    3.  These local removals also update the `:capability_index`.
    4.  This cleanup is local based on the Partisan event; no separate broadcast is needed as all nodes receive the same Partisan `node_down` event and perform cleanup independently. Subscribers are notified of the effective deregistration.

### 5. Discovery Logic (`discover_with_criteria/2` implemented in GenServer)

The `discover_services` call triggers logic that queries the local ETS tables:

1.  **Initial Set from Name/Capability:**
    - If `criteria[:service_name]` is provided, fetch services matching that name.
    - If `criteria[:capabilities]` are provided, use the `:capability_index` to get a list of services for each capability. Find the intersection of these lists (services that have ALL specified capabilities).
    - If both are provided, use the intersection of results from name lookup and capability indexing.
    - If neither, start with a broader list (e.g., all services, though this should be discouraged for performance).

2.  **Filtering by Other Criteria:**
    - Iterate through the initial set of `service_info_map`s.
    - **Health Status:** Filter out services whose `:health_status` does not match `criteria[:health_status]` (defaulting to `:healthy` if not specified).
    - **Version:** If `criteria[:version_match]` is given, filter by string equality or regex match against `service_info.version`.
    - **Node:** If `criteria[:node]` is given, filter for services on that specific node.
    - **Metadata:** If `criteria[:metadata_match]` (e.g., `%{region: "us-east-1"}`) is provided, perform sub-map matching against `service_info.metadata`.

3.  **Topology/Proximity Awareness (Advanced):**
    - After basic filtering, if multiple candidates remain, apply proximity rules:
        - Prefer services on `Node.self()`.
        - If network topology information is available (e.g., from `Foundation.Distributed.Topology` or external config like AWS AZ), prefer services in the same logical grouping (rack, AZ, region).
        - This requires `service_info.node` and potentially `service_info.metadata` (e.g., `region`) to be queryable.

4.  **Load Balancing Integration (Optional):**
    - If multiple suitable, healthy, and proximate services remain, a simple strategy is random selection.
    - For more advanced load balancing:
        - The `service_info.metadata` might include a `load_factor` or `queue_depth`.
        - `Foundation.Distributed.Discovery` could select the instance with the lowest reported load.
        - Alternatively, it could return a list of suitable candidates to a client-side load balancer or a dedicated load balancing module. The mention of `:load_balancer` in `Foundation.Distributed.Channels` suggests that routing/load balancing might be a separate concern that `Discovery` could feed into.

5.  **Return:** A list of `service_info_map`s for the selected services.

### 6. Health Monitoring

- **Mechanism Options:**
    1.  **Active Polling:**
        - `Foundation.Distributed.Discovery` (or worker processes it spawns, stored in `:health_monitors`) periodically calls a standardized health check function on each registered service's `pid`.
        - Services can implement a `Foundation.Contracts.HealthCheck` behaviour (e.g., `check_health() -> :healthy | :degraded | :unhealthy`).
    2.  **Passive Heartbeating:**
        - Registered services periodically send a heartbeat message (e.g., via `GenServer.cast` or `send`) to their local `Foundation.Distributed.Discovery` manager.
        - The manager tracks the `last_heartbeat_timestamp` in `:health_monitors`. If a heartbeat is missed for a configurable timeout, the service is marked `:unhealthy` or `:unknown`.
    - A combination might be used (e.g., heartbeats, with polling as a fallback).

- **Updates:** The health status is updated in the `:service_cache` for the specific service instance.
- **Event Broadcast:** Changes in health status (especially to `:unhealthy` or back to `:healthy`) should be broadcast to other nodes so their caches are updated. This ensures all nodes have a relatively consistent view of service health.
- **Discovery Impact:** Unhealthy services are typically filtered out from `discover_services` results unless the criteria explicitly request them (e.g., `health_status: :any` for diagnostic purposes).

### 7. Scalability for Thousands of Nodes

- **Distributed Cache & Local Reads:** Each node having a local ETS cache of (most) services means discovery queries are primarily local and fast, avoiding a centralized bottleneck.
- **Efficient Indexing:** The `:capability_index` (and potentially other indices on name, etc.) significantly speeds up the initial filtering phase of discovery.
- **Partisan for Eventual Consistency:** Registration, deregistration, and health update broadcasts use Partisan channels. This makes the system eventually consistent. The choice of Partisan overlay and channel configuration will impact propagation delay.
- **Challenges:**
    - **Cache Consistency Latency:** Updates take time to propagate across a large cluster. There might be brief periods where different nodes have slightly different views of available services. This is typical for eventually consistent systems.
    - **Broadcast Storms:** Mass registration/deregistration events (e.g., during a large deployment or a network partition healing) could lead to a surge in broadcast messages.
        - **Mitigation:** Batch updates, use efficient Partisan broadcast overlays (like Plumtree via `:pub_sub` topology if suitable for these events), potentially use delta updates instead of full `service_info_map`s for health changes.
    - **ETS Table Size:** On nodes with many services or in very large clusters, the ETS tables could grow large. Monitor memory usage. Partisan's `Node.list()` itself has scalability considerations.

### 8. Integration

- **`Foundation.ServiceRegistry`:** If `Foundation.ServiceRegistry` exists as a higher-level, simpler API (as hinted in `BATTLE_PLAN_LIBCLUSTER_PARTISAN.md`), it would likely be a client of `Foundation.Distributed.Discovery`, translating its API calls into criteria-based searches.
- **Client Applications:** Directly use `Foundation.Distributed.Discovery.discover_services/1` to find necessary backend services.
- **`Foundation.BEAM.Distribution` / Partisan:** Used for the underlying inter-node communication of registration/health broadcasts. Node up/down events from this layer are crucial for cleaning up stale service entries.
- **`Foundation.Distributed.Topology`:** Proximity-based service discovery would need to query the current topology or node metadata from this module.

### 9. Open Questions / Future Work

- **Consistency Models:** Explore options for stronger consistency if required by certain applications, though this typically impacts scalability (e.g., using Raft/Paxos for service registration, which Partisan might support via specific channels/modules).
- **Advanced Query Language:** For more complex discovery needs, a more expressive query language (beyond simple keyword lists) could be designed (e.g., supporting OR conditions, range queries on metadata).
- **External Discovery System Integration:**
    - **Push/Pull:** Mechanisms to synchronize service information with external systems like Consul, etcd, or Kubernetes service discovery. Foundation services could be published externally, or external services could be made discoverable within Foundation.
- **Service Versioning & Compatibility:** More sophisticated handling of service versions, allowing clients to request services compatible with a specific version range (e.g., `~> 1.2`).
- **Weighted/Priority-Based Discovery:** Allow services to register with a weight or priority, influencing their selection during discovery, especially for load balancing.
- **Security:** Secure service registration and discovery (e.g., ACLs on who can register/discover certain services). Authenticated broadcasts.
