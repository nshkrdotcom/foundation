## Codebase Design: Partisan Integration & Libcluster Replacement

### 1. Overview
The primary goal of this design is to replace the traditional Distributed Erlang and libcluster-based topology management with Partisan. This shift aims to achieve significantly greater scalability, targeting support for 1000+ nodes, and to leverage Partisan's advanced features for more robust and flexible distributed applications. The core integration point for Partisan within the Foundation framework will be the `Foundation.BEAM.Distribution` module. This module will abstract Partisan's functionalities, providing a cohesive interface for the rest of the Foundation ecosystem.

### 2. `Foundation.BEAM.Distribution` Module

- **Purpose:** To act as the primary interface for Partisan-based distribution, abstracting the underlying Partisan library and providing a consistent API for Foundation applications.

- **Key Responsibilities:**
    - Initialize and manage the Partisan instance, including its lifecycle (start/stop).
    - Provide functions for node connection, disconnection, and querying the list of connected nodes.
    - Expose APIs for sending messages to remote processes and broadcasting messages across the cluster using Partisan's capabilities.
    - Handle Partisan event subscriptions, particularly for membership changes (e.g., node up/down events), and relaying these to relevant Foundation services.

- **Proposed Functions (Elixir syntax):**
  ```elixir
  defmodule Foundation.BEAM.Distribution do
    @doc """
    Starts and configures the Partisan layer for the current node.
    This typically involves starting the Partisan application and its
    associated services like the peer service manager.
    Options can include Partisan-specific settings or pointers to
    application configuration.
    """
    def start_link(opts \\ []) do
      # Implementation might involve:
      # - Ensuring Partisan application is started.
      # - Configuring Partisan based on opts or application environment.
      # - Starting partisan_peer_service_manager or similar.
      # - Returning {:ok, pid} or an appropriate GenServer tuple.
      :partisan.start_link(opts) # Simplified example
    end

    @doc """
    Stops the Partisan layer on the current node.
    """
    def stop() do
      # Implementation might involve:
      # - Stopping the Partisan application or its relevant services.
      :application.stop(:partisan) # Simplified example
    end

    @doc """
    Returns a list of connected nodes (members) in the Partisan cluster.
    """
    def node_list() :: list(atom()) do
      # Example using partisan_peer_service
      case :partisan_peer_service.members() do
        {:ok, members} -> members
        _ -> []
      end
    end

    @doc """
    Sends a message to a remote process (identified by PID or registered name)
    on a specific destination node using Partisan's message forwarding.
    """
    def send(dest_node :: atom(), remote_pid_or_name :: atom() | pid(), message :: term()) do
      # Partisan offers various functions like partisan:forward_message/3 or /4.
      # The choice depends on whether a specific channel or options are needed.
      :partisan.forward_message(dest_node, remote_pid_or_name, message)
    end

    @doc """
    Broadcasts a message to all nodes in the cluster, potentially via a specific
    Partisan channel if Foundation.Distributed.Channels is not used directly.
    """
    def broadcast(channel :: atom(), message :: term()) do
      # This could delegate to a more specialized module like Foundation.Distributed.Channels
      # or directly use Partisan's broadcast capabilities if appropriate for the given channel.
      # For example, using a default broadcast mechanism or a specific channel:
      # :partisan.broadcast(channel_name_from_foundation_channel(channel), message)
      # Or, more likely, this is handled by Foundation.Distributed.Channels.
      Foundation.Distributed.Channels.broadcast(channel, message)
    end

    @doc """
    Registers the calling process to receive Partisan membership change events
    (e.g., node_join, node_leave).
    """
    def subscribe_membership_events() do
      # Partisan provides mechanisms to subscribe to peer service events.
      # Example: :partisan_config.subscribe({:partisan_peer_service_manager, :node_join, :_})
      # The actual implementation would involve handling these events and possibly
      # translating them into Foundation-specific event formats.
      :ok # Placeholder
    end
  end
  ```

### 3. Partisan Configuration Management

- **Location:** Partisan's core configuration will reside within the standard Elixir application environment configuration (e.g., `config/config.exs`, `config/runtime.exs`). `Foundation.BEAM.Distribution` will load and apply these settings.

- **Details:**
    - **Partisan Environment Variables:** Key Partisan settings such as `:partisan_peer_service_manager`, `:partisan_channel_manager`, `:partisan_pluggable_peer_service_manager_name`, overlay strategies (e.g., HyParView, full-mesh), and channel definitions will be configured here.
      ```elixir
      # Example config/config.exs
      config :partisan,
        partisan_peer_service_manager: Partisan.PeerService.Manager,
        partisan_channel_manager: Partisan.Channel.Manager,
        channels: [
          # Default channels or channels required by Foundation
          %{name: :control_plane, parallel_dispatch: true, max_queue_len: 1000},
          %{name: :data_plane, parallel_dispatch: false, max_queue_len: 5000}
        ],
        overlays: [
          # Example default overlay
          %{id: :default_hyparview, module: Partisan.Overlay.HyParView, config: [active_random_walk_len: 5]}
        ]
      ```
    - **Foundation-to-Partisan Translation:** `Foundation.BEAM.Distribution` (or higher-level modules like `Foundation.Distributed.Topology`) will be responsible for translating Foundation's desired state (e.g., "connect to these seed nodes," "use this topology strategy") into the corresponding Partisan configurations or runtime calls. For instance, Foundation might have a simplified configuration for "topology_strategy: :hyparview" which then translates to specific Partisan overlay settings.
    - **Environment Detection:** As mentioned in `BATTLE_PLAN_LIBCLUSTER_PARTISAN.md`, the system should support different Partisan configurations based on the runtime environment (dev, test, prod). This can be achieved using Elixir's standard `config/dev.exs`, `config/test.exs`, `config/prod.exs` (or `config/runtime.exs` for releases). For example, `dev` might use a simple local full-mesh, while `prod` uses a more complex HyParView configuration with specific seed nodes.

### 4. Libcluster API Compatibility Layer

- **Purpose:** To provide a transitional path for applications currently using `libcluster`, enabling them to migrate to Foundation 2.0 and its Partisan-based distribution without requiring immediate, extensive code changes to their clustering logic.

- **Module (Proposed):** `Foundation.Compat.Libcluster`

- **Approach:**
    - This module will expose a public API that mirrors the most commonly used functions from `libcluster` and `Cluster.Strategy.*` modules.
    - Internally, calls to these compatibility functions will be translated into operations on Foundation's Partisan-based distribution layer (primarily `Foundation.BEAM.Distribution` and `Foundation.Distributed.Topology`).
    - The layer will not instantiate `libcluster` itself but will simulate its behavior using Partisan data.

    - **Example:**
      ```elixir
      defmodule Foundation.Compat.Libcluster do
        @doc """
        Mirrors libcluster.topologies/0.
        It fetches topology information from Foundation's Partisan setup
        and formats it to resemble the output of libcluster.topologies().
        """
        def topologies() do
          # This would involve:
          # 1. Getting current topology strategy from Foundation.Distributed.Topology.
          # 2. Getting node list from Foundation.BEAM.Distribution.node_list().
          # 3. Formatting this data into a structure similar to libcluster's output.
          # Example:
          # current_strategy = Foundation.Distributed.Topology.get_current_strategy_name()
          # nodes = Foundation.BEAM.Distribution.node_list()
          # [{current_strategy, nodes}]
          # The actual formatting might need to be more detailed based on how apps use this.
          [{Foundation.Distributed.Topology.get_current_strategy_name(), node_list(:default)}]
        end

        @doc """
        Mirrors Cluster.Strategy.Strategy.node_list/1 or similar libcluster functions
        that provide a list of nodes for a given (or default) topology.
        The strategy_name argument might be ignored if Foundation manages a single
        unified Partisan topology, or it could be mapped to a specific Partisan overlay if relevant.
        """
        def node_list(_strategy_name \\ :default) do
          Foundation.BEAM.Distribution.node_list()
        end

        @doc "Mirrors Cluster.Strategy.connect_nodes/1"
        def connect_nodes(_strategy_name) do
          # Partisan typically handles connections automatically based on its configuration.
          # This function might become a no-op or log a warning,
          # or trigger a health check of Partisan's connections.
          :ok
        end

        @doc "Mirrors Cluster.Strategy.disconnect_nodes/1"
        def disconnect_nodes(_strategy_name) do
          # Similar to connect_nodes, direct control might not be applicable.
          # Could trigger a graceful shutdown of Partisan connections if such a concept exists
          # or simply be a no-op.
          :ok
        end
      end
      ```

- **Configuration:**
    - An application would enable this compatibility layer via its main configuration file (e.g., `config/config.exs`).
      ```elixir
      config :my_app, foundation: [
        enable_libcluster_compat_layer: true
      ]
      ```
    - The `BATTLE_PLAN_LIBCLUSTER_PARTISAN.md` mentions a `libcluster_topologies` configuration setting. This suggests that Foundation could read existing `libcluster` topology configurations and attempt to map them to equivalent Partisan settings if the compatibility layer is enabled.
      ```elixir
      # Example from BATTLE_PLAN_LIBCLUSTER_PARTISAN.md
      config :foundation,
        libcluster_topologies: [
          k8s: [
            strategy: Cluster.Strategy.Kubernetes, # This would be interpreted by Foundation
            config: [kubernetes_selector: "app=myapp"]
          ]
        ]
      ```
      If `enable_libcluster_compat_layer: true`, `Foundation.BEAM.Distribution` or a dedicated setup routine would parse `libcluster_topologies` and configure Partisan accordingly (e.g., using Partisan's Kubernetes discovery if available, or a custom implementation that feeds Partisan).

### 5. Achieving 1000+ Node Scalability

This design directly contributes to achieving scalability for 1000+ nodes in several ways:
- **Partisan's Architecture:** Partisan is designed for larger-scale clusters and does not rely on Distributed Erlang's full-mesh network topology for all communication. It supports various overlay topologies (like HyParView) that offer better scalability and reduced connection overhead.
- **Offloading Clustering Logic:** By delegating the core clustering, membership, and message routing responsibilities to Partisan (written in Erlang and optimized for these tasks), the Elixir application code in Foundation can focus on business logic rather than low-level cluster management.
- **Efficient Message Handling:** Partisan's multi-channel communication and optimized message forwarding are more efficient than raw Distributed Erlang for many use cases, especially in large clusters.
- **Dynamic Topologies:** While detailed in a separate document (`dynamic_topology_management.md`), the ability of `Foundation.Distributed.Topology` to dynamically switch and manage Partisan overlays based on cluster size and health is crucial for maintaining performance and stability as the cluster grows. `Foundation.BEAM.Distribution` provides the foundational layer for these dynamic changes.

### 6. Future Considerations

- **Integration with `Foundation.Distributed.Topology`:** `Foundation.BEAM.Distribution` will work closely with `Foundation.Distributed.Topology`. While `F.B.Distribution` handles the raw Partisan interface (nodes, sending messages), `F.D.Topology` will manage higher-level concerns like selecting and configuring Partisan overlay strategies, and potentially triggering reconfigurations via `F.B.Distribution`.
- **Granular Partisan Channel Control:** The current design proposes that `Foundation.Distributed.Channels` would be the primary interface for channel-based communication. `Foundation.BEAM.Distribution`'s `broadcast` function is shown delegating to it. If more direct, low-level control over Partisan channels (e.g., creating temporary channels, specific QoS settings not exposed by `F.D.Channels`) is needed, relevant functions could be added to `Foundation.BEAM.Distribution`. However, the preference is to keep channel logic centralized in `Foundation.Distributed.Channels`.
- **Partisan Event Handling:** The `subscribe_membership_events` function is basic. A more robust mechanism for handling various Partisan events (beyond just membership) and dispatching them within the Foundation ecosystem (e.g., via `Foundation.Events`) will be necessary.
- **Security:** Configuration of Partisan's security features (e.g., TLS for communication, shared secrets) will need to be exposed through Foundation's configuration mechanisms and applied by `Foundation.BEAM.Distribution`.
