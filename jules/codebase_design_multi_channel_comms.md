## Codebase Design: Multi-Channel Communication

### 1. Overview
The purpose of integrating multi-channel communication is to leverage Partisan's capability to define distinct communication pathways for different types of traffic. This approach is crucial for eliminating head-of-line blocking, where a slow or voluminous message on one "logical" channel can delay urgent messages. By segregating traffic (e.g., high-priority coordination messages, bulk data transfer, gossip/maintenance messages, application events), we can ensure better performance, reliability, and predictability in a distributed system. The key module responsible for managing this in Foundation 2.0 will be `Foundation.Distributed.Channels`.

### 2. `Foundation.Distributed.Channels` Module

- **Purpose:** To abstract and manage Partisan's multi-channel communication features, providing a structured way for Foundation applications to utilize different channels with varying Quality of Service (QoS) characteristics.

- **Key Responsibilities:**
    - **Configuration & Setup:** Loading channel definitions from application configuration and using these to set up corresponding Partisan channels with their specific properties (e.g., priority, reliability, Partisan-specific options).
    - **API Provision:** Offering functions to send messages to specific destinations (nodes, processes) or broadcast messages across the cluster over a designated channel.
    - **QoS & Prioritization:** Ensuring that the configured QoS and prioritization settings for each channel are correctly mapped to Partisan's underlying channel mechanisms.
    - **Intelligent Routing Support:** Providing infrastructure (like a routing table) for future enhancements where messages could be automatically routed to appropriate channels based on their type or metadata.
    - **Monitoring (Potential):** Collecting and exposing performance metrics (e.g., message volume, latency, queue lengths) for each channel to aid in diagnostics and optimization.

- **State Management (GenServer `defstruct` based on `FOUNDATION2_04_PARTISAN_DISTRO_REVO.md`):**
  This GenServer will manage the state related to channel configurations and runtime information.
  ```elixir
  defmodule Foundation.Distributed.Channels do
    use GenServer

    defstruct [
      :channel_registry,    # Could be an ETS table or map holding dynamic info/status about registered Partisan channels.
      :routing_table,       # Map or list of rules for intelligent/automatic channel selection based on message properties.
      :performance_metrics, # Map to store metrics like message counts, error rates, or latency per channel.
      :channel_configs,     # Stores the initial channel configurations loaded from app config.
      :load_balancer        # Potentially for routing messages to specific service instances if this module handles service-level routing (less likely, could be a higher-level concern).
    ]

    # ... GenServer callbacks ...
  end
  ```

- **Proposed Core Functions (Elixir syntax, based on `FOUNDATION2_04_PARTISAN_DISTRO_REVO.md`):**
  ```elixir
  defmodule Foundation.Distributed.Channels do
    use GenServer

    @doc """
    Starts the Foundation Channel Manager GenServer.
    It would load channel configurations and potentially initialize Partisan channels.
    """
    def start_link(opts \\ []) do
      GenServer.start_link(__MODULE__, opts, name: __MODULE__)
    end

    @impl true
    def init(opts) do
      channel_configs = Application.get_env(:foundation, __MODULE__, [])[:channels] || %{}
      # TODO: Initialize Partisan channels based on channel_configs if not done by Partisan itself.
      # This might involve validating configs and preparing runtime structures.
      state = %{
        channel_registry: :ets.new(:channel_registry, [:set, :protected, :named_table]),
        routing_table: %{}, # Initialize as empty or load from config
        performance_metrics: %{},
        channel_configs: channel_configs,
        load_balancer: nil # Or initialize if used
      }
      {:ok, state}
    end

    @doc """
    Sends a message on a specific channel to a destination node, process, or registered name.
    The 'opts' keyword list can include hints for delivery like :priority or :delivery_guarantee,
    though these are primarily determined by the channel's static configuration.
    """
    def send_message(channel_name :: atom(), destination :: node() | {atom(), node()} | pid(), message :: term(), opts :: Keyword.t()) :: :ok | {:error, any()} do
      # Implementation would look up Partisan channel properties from state.channel_configs
      # Then, use Partisan's API to forward the message, potentially specifying the Partisan channel name.
      # Example: partisan:forward_message(destination_node, destination_process_or_name, message, [partisan_channel: resolved_partisan_channel_name])
      # Actual Partisan function might vary.
      GenServer.call(__MODULE__, {:send_message, channel_name, destination, message, opts})
    end

    @doc """
    Broadcasts a message to all connected nodes on a specific Foundation channel.
    """
    def broadcast(channel_name :: atom(), message :: term(), opts :: Keyword.t()) :: :ok | {:error, any()} do
      # This would use Partisan's broadcast functionality, ensuring it's directed
      # over the correct underlying Partisan channel.
      # Example: partisan:broadcast(resolved_partisan_channel_name, message, partisan_opts_from_foundation_opts(opts))
      GenServer.call(__MODULE__, {:broadcast, channel_name, message, opts})
    end

    @doc """
    Configures message routing rules for intelligent/automatic channel selection.
    Rules might be a list of tuples like `[{match_pattern, channel_name}]`.
    """
    def configure_routing(rules :: list()) :: :ok do
      GenServer.cast(__MODULE__, {:configure_routing, rules})
    end

    @doc """
    Retrieves performance metrics for all channels or a specific channel.
    Metrics could include message counts, queue lengths (if available), error rates, etc.
    """
    def get_channel_metrics(channel_name :: atom() | :all) :: map() do
      GenServer.call(__MODULE__, {:get_channel_metrics, channel_name})
    end

    # --- GenServer Callbacks (simplified examples) ---
    @impl true
    def handle_call({:send_message, channel, dest, msg, _opts}, _from, state) do
      # Resolve Foundation channel_name to actual Partisan channel config/name
      # Perform Partisan send operation
      # Update performance_metrics
      {:reply, :ok, state}
    end

    @impl true
    def handle_call({:broadcast, channel, msg, _opts}, _from, state) do
      # Resolve Foundation channel_name to actual Partisan channel config/name
      # Perform Partisan broadcast operation
      # Update performance_metrics
      {:reply, :ok, state}
    end

    @impl true
    def handle_call({:get_channel_metrics, channel_name}, _from, state) do
      metrics = if channel_name == :all do
        state.performance_metrics
      else
        Map.get(state.performance_metrics, channel_name, %{})
      end
      {:reply, metrics, state}
    end

    @impl true
    def handle_cast({:configure_routing, rules}, state) do
      # Validate and transform rules if necessary
      new_routing_table = Enum.into(rules, %{}) # Simplified
      {:noreply, %{state | routing_table: new_routing_table}}
    end

  end
  ```

### 3. Channel Configuration

- **Source:** Channel definitions will be sourced from the Elixir application configuration system (e.g., `config/config.exs`, `config/{env}.exs`, `config/runtime.exs`).

- **Structure (based on `initialize_channel_configs()` in `FOUNDATION2_04_PARTISAN_DISTRO_REVO.md`):**
  The configuration defines properties for each Foundation channel. These properties are then used by `Foundation.Distributed.Channels` to correctly utilize or set up the underlying Partisan channels.
  ```elixir
  config :foundation, Foundation.Distributed.Channels,
    channels: %{
      # High-priority channel for critical cluster coordination messages (e.g., heartbeats, consensus)
      coordination: %{
        priority: :high,                # Abstract priority, maps to Partisan settings
        reliability: :guaranteed,       # Abstract reliability, maps to Partisan settings
        partisan_opts: [                # Direct Partisan channel options
          # Example: :partisan_channel_max_bytes, :max_queue_len, specific dispatchers
          parallel_dispatch: true
        ]
      },
      # Medium-priority channel for typical application data exchange
      data: %{
        priority: :medium,
        reliability: :best_effort,
        compression: true,              # Application-level flag, implies middleware or specific handling
        partisan_opts: []
      },
      # Low-priority channel for background tasks like topology gossip, telemetry synchronization
      gossip: %{
        priority: :low,
        reliability: :best_effort,
        partisan_opts: []
      },
      # Channel for business or system events
      events: %{
        priority: :medium,
        reliability: :at_least_once,   # Abstract, implies configuration for persistence or acking if supported
        partisan_opts: []
      }
    }
  ```

- **Loading:** The `Foundation.Distributed.Channels` GenServer, during its `init/1` callback, will load this configuration using `Application.get_env/3`. It will then store and use these definitions to interact with Partisan, ensuring that messages sent on a Foundation channel (e.g., `:coordination`) are routed over a Partisan channel configured with the appropriate characteristics.

### 4. Message Routing and Prioritization

- **Default Behavior:** When a developer uses `Foundation.Distributed.Channels.send_message/4` or `broadcast/3`, they explicitly specify the Foundation channel name (e.g., `:data`). The module then ensures this message is sent over the corresponding Partisan channel.

- **Intelligent Routing (Future Enhancement based on `:routing_table`):**
    - The `:routing_table` (managed by `configure_routing/1`) would allow defining rules to automatically select an appropriate channel if the sender doesn't specify one, or to override a sender's choice based on message properties.
    - Example rule: `{message_pattern: %{type: :critical_alert, urgency: _}, channel: :coordination}`.
    - This would require message inspection capabilities within the sending logic.

- **Prioritization:**
    - Prioritization is primarily a feature of the underlying Partisan channels. Foundation's role is to configure these Partisan channels correctly (via `partisan_opts` in the channel definitions) to reflect the desired priorities (e.g., ensuring the `:coordination` channel in Partisan has higher dispatch priority than the `:data` channel).
    - `Foundation.Distributed.Channels` does not implement a separate prioritization queue on top of Partisan but ensures Partisan is set up to handle it.

### 5. Eliminating Head-of-Line Blocking
Head-of-line (HOL) blocking occurs when a sequence of messages is processed strictly in order, and a single slow-to-process message at the front of the queue delays all subsequent messages, even if those messages are small, urgent, and could be processed quickly.

By using multiple Partisan channels:
- **Isolation:** Each channel acts as an independent communication lane. A large data transfer on the `:data` channel will queue and transmit independently of messages on the `:coordination` channel.
- **Prioritized Processing:** If Partisan is configured with different priorities for its channels (e.g., different dispatchers or internal queue management), messages on high-priority channels (like `:coordination`) can bypass or be processed ahead of messages on lower-priority channels (like `:data` or `:gossip`).
- **Example:** A 1GB file transfer initiated on the `:data` channel will not prevent a critical 50-byte node heartbeat message on the `:coordination` channel from being promptly delivered and processed. The heartbeat uses its own dedicated, high-priority lane.

### 6. Scalability Considerations for Thousands of Nodes

- **Channel Configuration Management:** While the configuration itself is static, ensuring Partisan correctly establishes and maintains these distinct channels across 1000+ nodes requires robust Partisan overlay network management. The number of channels is typically small and fixed, so configuration dissemination is not the primary concern.
- **Partisan Channel Limits:** Partisan itself is designed for scalability. The limits would likely be related to system resources (memory for buffers, CPU for dispatching) rather than a hard limit on the number of channels (which is small) or nodes. Efficient Partisan configuration (e.g., appropriate buffer sizes per channel) is key.
- **Broadcast Impact:** Broadcasting on any channel to thousands of nodes can be resource-intensive. Partisan's broadcast mechanisms and the efficiency of its overlay network are critical here. For very frequent, large broadcasts, alternative patterns (e.g., pub-sub systems, targeted multicast if supported by Partisan overlays) might be considered. Foundation should encourage judicious use of broadcasts, especially on high-traffic channels.

### 7. Integration with `Foundation.BEAM.Distribution` and `Foundation.BEAM.Messages`

- `Foundation.BEAM.Distribution.broadcast/2`: This function, if it needs to be channel-aware, should delegate to `Foundation.Distributed.Channels.broadcast/3`.
- `Foundation.BEAM.Distribution.send/3`: For a unified API and to leverage multi-channel capabilities, this function should ideally also become channel-aware. This could mean its API changes to `send(dest_node, remote_pid_or_name, message, channel_name_or_opts)` or it intelligently selects a channel via `Foundation.Distributed.Channels`.
- **Channel-Aware BEAM Layer:** The note from `BATTLE_PLAN_LIBCLUSTER_PARTISAN.md` (`Foundation.BEAM.Messages.send_optimized(..., channel: :high_priority)`) strongly suggests that the BEAM-level modules themselves should be channel-aware. This is the preferred approach. `Foundation.BEAM.Messages` (and potentially `Foundation.BEAM.Processes` for inter-process communication) would then become clients of `Foundation.Distributed.Channels`.
  - `Foundation.BEAM.Messages.send_optimized(dest, msg, channel: :my_channel)` would internally call `Foundation.Distributed.Channels.send_message(:my_channel, dest, msg, [])`.

### 8. Open Questions / Future Work

- **Dynamic Channel Management:** The current design assumes statically configured channels. Support for dynamically adding or removing channels at runtime by applications could be a future enhancement, though it adds complexity to configuration and management across the cluster.
- **Granular Security Per Channel:** Investigating if Partisan allows, and then exposing, different security settings (e.g., encryption levels, authentication requirements) per channel.
- **Backpressure Mechanisms:** How channel-specific backpressure is handled by Partisan and how/if Foundation needs to expose or react to this.
- **Metrics Collection & Exposition:** Standardizing the performance metrics collected per channel and integrating their exposition with `Foundation.Telemetry`.
- **Advanced Routing Logic:** Developing a more sophisticated DSL or mechanism for the `:routing_table` to allow complex, content-based routing decisions.
