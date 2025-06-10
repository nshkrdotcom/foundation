## Codebase Design: Dynamic Topology Management

### 1. Overview
The purpose of dynamic topology management is to enable a Foundation 2.0 cluster to adapt its underlying network structure (topology) at runtime. This adaptation is driven by factors such as current cluster size, observed network performance (e.g., latency, connectivity), and potentially the specific workload characteristics of the application. By leveraging Partisan's support for various overlay networks, the system can switch to the most suitable topology, ensuring optimal performance, scalability, and resilience as conditions change. The key module responsible for this is `Foundation.Distributed.Topology`.

### 2. `Foundation.Distributed.Topology` Module

- **Purpose:** This GenServer module is responsible for managing the active Partisan network topology, monitoring its performance, and deciding when and how to switch to a different topology to better suit the cluster's current state or application needs.

- **State Management (GenServer `defstruct` from `FOUNDATION2_04_PARTISAN_DISTRO_REVO.md`):**
  ```elixir
  defmodule Foundation.Distributed.Topology do
    use GenServer

    defstruct [
      :current_topology,    # Atom representing the current strategy, e.g., :full_mesh, :hyparview
      :overlay_config,      # Map holding the specific Partisan configuration for the active overlay.
      :performance_metrics, # Map storing collected metrics like {latency_ms, connectivity_score, partition_count}.
      :topology_history,    # List of tuples like [{timestamp, old_topo, new_topo, reason}] to log changes.
      :switch_cooldown,     # Duration (e.g., in seconds) to wait before another automatic switch can occur.
      :last_switch_time     # Timestamp of the last topology switch.
    ]

    # ... GenServer callbacks ...
  end
  ```

- **Proposed Core Functions (Elixir syntax, based on `FOUNDATION2_04_PARTISAN_DISTRO_REVO.md`):**
  ```elixir
  defmodule Foundation.Distributed.Topology do
    use GenServer

    @doc """
    Starts the Topology Manager GenServer.
    Opts can include :initial_topology (atom), :switch_cooldown (seconds),
    and Partisan-specific configurations for the initial topology.
    """
    def start_link(opts \\ []) do
      # initial_topology = Keyword.get(opts, :initial_topology, :hyparview)
      # switch_cooldown = Keyword.get(opts, :switch_cooldown, 300) # 5 minutes
      # partisan_config = # Load or generate Partisan config for initial_topology
      # TODO: Apply initial Partisan configuration
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @impl true
    def init(opts) do
      initial_topology = Keyword.get(opts, :initial_topology, determine_initial_topology())
      overlay_config = get_overlay_config_for_topology(initial_topology)
      # TODO: Apply this overlay_config to Partisan at startup

      state = %{
        current_topology: initial_topology,
        overlay_config: overlay_config,
        performance_metrics: %{node_count: Node.list() |> length()},
        topology_history: [],
        switch_cooldown: Keyword.get(opts, :switch_cooldown, 300_000), # milliseconds
        last_switch_time: System.monotonic_time()
      }
      # Start periodic performance monitoring
      Process.send_after(self(), :monitor_performance, 60_000) # Monitor every minute
      {:ok, state}
    end

    @doc """
    Manually switches the cluster's Partisan overlay topology at runtime.
    The `new_topology` must be a supported strategy (e.g., :full_mesh, :hyparview).
    """
    def switch_topology(new_topology :: atom()) :: :ok | {:error, any()} do
      GenServer.call(__MODULE__, {:switch_topology, new_topology, :manual})
    end

    @doc """
    Requests the manager to evaluate and potentially switch to an optimal topology
    based on a general workload characteristic (e.g., :low_latency, :high_throughput).
    Returns the topology chosen or an error.
    """
    def optimize_for_workload(workload_type :: atom()) :: {:ok, atom()} | {:error, any()} do
      GenServer.call(__MODULE__, {:optimize_for_workload, workload_type})
    end

    @doc """
    Gets current topology information, node count, and a summary of performance metrics.
    """
    def current_topology_info() :: map() do
      GenServer.call(__MODULE__, :current_topology_info)
    end

    @doc """
    Triggers an immediate analysis of current topology performance, logs detailed findings,
    and may return recommendations for alternative topologies.
    """
    def analyze_performance() :: map() do
      GenServer.call(__MODULE__, :analyze_performance)
    end

    # --- Internal Processes & GenServer Callbacks ---
    @impl true
    def handle_info(:monitor_performance, state) do
      new_metrics = collect_performance_metrics(state)
      updated_state = %{state | performance_metrics: Map.merge(state.performance_metrics, new_metrics)}

      if should_auto_optimize?(updated_state) do
        # Determine best topology based on metrics
        # For simplicity, let's say it picks one based on node count for now
        suggested_topology = determine_optimal_topology(updated_state.performance_metrics)
        if suggested_topology != state.current_topology do
          # Call internal function to handle the switch
          # This avoids calling self(), which can be problematic.
          # Instead, we can directly call the logic or send a specific internal message.
          handle_call({:switch_topology, suggested_topology, :auto}, :internal, updated_state)
        else
          {:noreply, updated_state}
        end
      else
        # Reschedule monitoring
        Process.send_after(self(), :monitor_performance, 60_000)
        {:noreply, updated_state}
      end
    end

    @impl true
    def handle_call({:switch_topology, new_topology, type}, _from, state) do
      if new_topology == state.current_topology do
        {:reply, {:error, :already_current_topology}, state}
      else
        # Cooldown check for automatic switches
        elapsed_since_last_switch = System.monotonic_time() - state.last_switch_time
        if type == :auto && elapsed_since_last_switch < state.switch_cooldown do
          {:reply, {:error, :cooldown_active}, state}
        else
          case graceful_topology_transition(state.current_topology, new_topology, get_overlay_config_for_topology(new_topology)) do
            :ok ->
              new_history_entry = {System.os_time(), state.current_topology, new_topology, type}
              updated_state = %{state |
                current_topology: new_topology,
                overlay_config: get_overlay_config_for_topology(new_topology),
                topology_history: [new_history_entry | state.topology_history],
                last_switch_time: System.monotonic_time()
              }
              # Reschedule monitoring if it was an auto switch that landed here
              Process.send_after(self(), :monitor_performance, 60_000)
              {:reply, :ok, updated_state}
            {:error, reason} ->
              {:reply, {:error, reason}, state}
          end
        end
      end
    end

    # Other handle_call implementations for :optimize_for_workload, :current_topology_info, :analyze_performance

    defp determine_initial_topology() do
      node_count = Node.list() |> length()
      if node_count < 10, do: :full_mesh, else: :hyparview
    end

    defp get_overlay_config_for_topology(topology_atom) do
      # Returns Partisan-specific config map for the given topology
      # Example: if topology_atom == :hyparview, return [module: Partisan.Overlay.HyParView, config: [arwl: 5, ...]]
      Application.get_env(:partisan, :overlays, [])
      |> Enum.find(&(&1[:id] == topology_atom))
      || %{id: topology_atom, module: Partisan.Overlay.HyParView} # default fallback
    end

    defp collect_performance_metrics(state) do
      # Collects metrics as described in section 5
       %{node_count: Node.list() |> length()} # Simplified
    end

    defp should_auto_optimize?(state) do
      # Implements rules from section 4
      false # Placeholder
    end

    defp determine_optimal_topology(metrics) do
        # Based on metrics and rules
        if metrics.node_count < 10, do: :full_mesh, else: :hyparview # Simplified
    end

    defp graceful_topology_transition(old_topo, new_topo, new_config) do
        IO.puts("Switching from #{old_topo} to #{new_topo} with config #{inspect new_config}")
        # 1. Announce change (e.g., via Partisan broadcast on a control channel)
        # 2. Update Partisan's runtime configuration to use the new overlay.
        #    This is highly dependent on Partisan's API for dynamic reconfiguration.
        #    It might involve stopping and restarting Partisan with new config, or a more graceful update.
        #    Example: :application.set_env(:partisan, :overlays, [new_config], persistent: true)
        #             :partisan.reload_config() or specific API call.
        # 3. Verify health: check connectivity, node list stability after a short period.
        :ok # Placeholder
    end
  end
  ```

### 3. Topology Strategies and Partisan Overlays

- **Supported Topologies & Partisan Mapping:**
    - **`:full_mesh`**:
        - **Partisan Overlay:** Typically Partisan's built-in full-mesh capabilities or a specific `:full_mesh` overlay module if provided.
        - **Use Case:** Small clusters (<10-20 nodes) where direct connections are feasible and low latency is paramount. High connection overhead for larger clusters.
        - **Configuration:** Usually minimal, Partisan connects to all known peers.
    - **`:hyparview`**:
        - **Partisan Overlay:** `Partisan.Overlay.HyParView`.
        - **Use Case:** General-purpose topology for medium to large clusters (10-1000 nodes). Offers a good balance between connectivity, message propagation delay, and node overhead.
        - **Configuration:** Key parameters include Active View Size (`arwl` - Active Random Walk Length), Passive View Size (`prwl` - Passive Random Walk Length). These are configured in the Partisan overlay settings.
    - **`:client_server`**:
        - **Partisan Overlay:** Partisan's client-server overlay (module name to be confirmed from Partisan docs, e.g., `Partisan.Overlay.ClientServer`).
        - **Use Case:** Very large clusters (>1000 nodes) or where a hierarchical structure is beneficial. Clients connect only to designated server nodes, reducing overall connection load.
        - **Configuration:** Requires identifying which nodes act as servers. Clients need to know server addresses. Partisan config would specify roles and server lists.
    - **`:pub_sub`** (e.g., Epidemic Broadcast Trees like Plumtree):
        - **Partisan Overlay:** `Partisan.Overlay.Plumtree` or similar epidemic broadcast tree implementation.
        - **Use Case:** Optimized for efficient broadcast and event dissemination in large clusters. Suitable for event-driven architectures.
        - **Configuration:** Specific parameters for the tree construction algorithm (e.g., eager vs. lazy push thresholds).

- **Configuration Loading:** The `get_overlay_config_for_topology/1` internal function within `Foundation.Distributed.Topology` would be responsible for fetching or constructing the appropriate Partisan overlay configuration map based on the selected topology atom. These configurations are initially defined in the application's Partisan settings (e.g., `config/config.exs`).

### 4. Dynamic Switching Logic

- **Manual Switching:** Initiated by an administrator or deployment script calling `Foundation.Distributed.Topology.switch_topology(new_topology_atom)`. This provides direct control for planned changes or interventions.

- **Automatic Switching (driven by `handle_info(:monitor_performance, ...)` and `should_auto_optimize?/1`):**
    - **Inputs for Decision:**
        - Current `:performance_metrics`: Includes average message latency, partition event frequency, estimated bandwidth usage, and node count.
        - `Node.list()`: To get the current, accurate cluster size.
    - **Example Rules (from `FOUNDATION2_04_PARTISAN_DISTRO_REVO.md` and general best practices):**
        - If `current_topology == :hyparview` AND `node_count < 10` AND (`latency > threshold_low_node_latency` OR `connectivity_score < threshold_min_conn`), THEN switch to `:full_mesh`.
        - If `current_topology == :full_mesh` AND `node_count > 20` AND (`partition_count > threshold_partition_freq` OR `cpu_load_due_to_connections > high`), THEN switch to `:hyparview`.
        - If `node_count > 1000` AND `current_topology != :client_server` AND (`bandwidth_utilization > critical` OR `message_hop_count > max_hops`), THEN switch to `:client_server` (if server nodes can be designated).
        - If `workload_pattern == :event_driven` and `current_topology != :pub_sub`, THEN switch to `:pub_sub`.
    - **Cooldown (`:switch_cooldown` state field):** A configurable period (e.g., 5-10 minutes) must elapse after a topology switch before another automatic switch can be triggered. This prevents rapid, oscillating changes if metrics fluctuate around decision thresholds.

- **Graceful Transition (`graceful_topology_transition/3` internal function):**
    - **Announcement:** Before initiating the switch, the Topology Manager could broadcast a message to the cluster (e.g., on a control channel) announcing the impending change. This allows other nodes or services to prepare if needed.
    - **Partisan Reconfiguration:** This is the most critical step. It involves instructing Partisan to change its active overlay network. The exact mechanism depends on Partisan's API for dynamic reconfiguration (e.g., updating application environment variables and calling a reload function, or specific Partisan API calls).
    - **Verification:** After Partisan reports the change is complete (or after a timeout), the Topology Manager should verify the health of the new topology:
        - Check `Node.list()` against expected members.
        - Send test messages or pings to sample nodes.
        - Monitor for immediate partition events.
    - If verification fails, it might attempt a rollback or alert administrators.

### 5. Performance Monitoring

- **Metrics Collection (`collect_performance_metrics/0` internal function):**
    - **Node Count:** `length(Node.list())`.
    - **Message Latency:** This can be challenging. Options:
        - Active Pinging: Periodically send lightweight ping/pong messages between nodes (possibly a subset) and measure round-trip time (RTT).
        - Sampling: If messages have unique IDs and timestamps, sample application messages and log their end-to-end latency (requires collaboration from message senders/receivers).
    - **Connection Stability/Partition Events:** Subscribe to Partisan's event stream for node join/leave events, especially unexpected disconnections or network partition indications. Partisan might expose metrics on connection health directly.
    - **Bandwidth Utilization:** This is difficult to measure accurately from within Elixir alone. It might require OS-level tools (`sar`, `iftop`) or integration with external monitoring systems. For internal estimation, track bytes sent/received by key processes if possible.
    - **Message Queue Lengths (Partisan):** If Partisan exposes queue lengths for its channels or dispatchers, these are valuable indicators of congestion.

- These metrics are stored in the `:performance_metrics` state field and used by `should_auto_optimize?/1` to make decisions.

### 6. Scalability for Thousands of Nodes

- **How Dynamic Topology Supports Scalability:**
    - **Appropriate Overlays:** `:hyparview` and `:client_server` (or similar scalable overlays like Plumtree for broadcast) are specifically designed to handle much larger node counts than a full mesh by limiting direct connections and optimizing message routing paths.
    - **Adaptive Behavior:** As the cluster grows or shrinks, the system can automatically switch to a topology that is more efficient for that scale, preventing performance degradation associated with using an inappropriate topology (e.g., full mesh with 500 nodes).
- **Challenges:**
    - **Efficient Metrics Collection:** Gathering accurate performance data (especially latency and bandwidth) from thousands of nodes without overwhelming the network or the collection point is non-trivial. Sampling, aggregation, and decentralized collection might be needed.
    - **Graceful Transitions at Scale:** Reconfiguring the network topology of a large, live cluster without causing significant disruption (e.g., message loss, temporary unavailability) is complex. Partisan's capabilities for dynamic overlay changes are key here. Transitions must be carefully managed and possibly phased.
    - **Configuration Propagation:** Ensuring all nodes correctly adopt the new Partisan overlay configuration in a timely manner.

### 7. Integration with Other Modules

- **`Foundation.BEAM.Distribution`:**
    - This module, being the primary interface to Partisan, will be directly affected by topology changes. It might need to be re-initialized or re-queried by `Foundation.Distributed.Topology` after a switch to ensure it's aware of the new Partisan overlay's characteristics.
    - It might also be a source of low-level Partisan events that `Foundation.Distributed.Topology` consumes for its performance monitoring.
- **`Foundation.Distributed.Channels`:**
    - The performance and behavior of different communication channels can be significantly impacted by the underlying network topology (e.g., broadcast efficiency, point-to-point latency).
    - `Foundation.Distributed.Topology` might provide hints to `Foundation.Distributed.Channels` about the current topology to optimize channel behavior, or `Channels` might adjust its strategies based on topology events.

### 8. Open Questions / Future Work

- **Sophisticated Metrics:** Incorporating application-specific metrics or business KPIs into the topology switching decisions (e.g., if a particular service's response time degrades, consider a topology change).
- **Admin Interface:** Providing an administrative UI or CLI commands to:
    - View current topology, performance metrics, and history.
    - Manually trigger topology switches.
    - Adjust automatic switching rules and cooldown periods.
    - Simulate the impact of a topology switch.
- **Predictive Switching:** Using historical performance data and load forecasts to predictively switch topologies before performance degradation occurs, rather than just reactively.
- **Workload-Specific Profiles:** Allowing applications to define workload profiles (e.g., "batch_processing", "realtime_gaming") that map to preferred topology strategies and switching parameters.
- **A/B Testing Topologies:** A mechanism to test a new topology on a subset of the cluster before full rollout. (Highly advanced).
- **Partisan API for Dynamic Reconfiguration:** The feasibility and smoothness of `graceful_topology_transition` heavily depend on the specific APIs Partisan provides for runtime overlay changes. Detailed investigation into these Partisan features is critical.
