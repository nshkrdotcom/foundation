# Foundation 2.0: Implementation Patterns & Best Practices

# This document provides concrete implementation patterns that demonstrate
# the "Leaky Abstractions by Design" philosophy in action.

# ==============================================================================
# PATTERN 1: The Intentionally Leaky Facade
# ==============================================================================

defmodule Foundation.ProcessManager do
  @moduledoc """
  Smart Facade for distributed process patterns.
  
  ## Philosophy: Intentionally Leaky
  
  This module is designed as a leaky abstraction. It provides convenient
  functions for common patterns, but ALWAYS shows you what it's doing
  underneath. When you need more power, drop down to Horde directly.
  
  ## What This Module Does
  - Combines multi-step Horde operations into single function calls
  - Provides clear names for distributed patterns (singleton, replicated)
  - Handles error cases and provides better error messages
  
  ## What This Module Does NOT Do
  - Hide Horde's APIs or prevent direct access
  - Reimplement any core Horde functionality
  - Add significant performance overhead
  
  ## Examples of "Leakiness"
  
      # Facade: Simple and clear
      Foundation.ProcessManager.start_singleton(MyWorker, args)
      
      # What it actually does (visible in source):
      Horde.DynamicSupervisor.start_child(Foundation.DistributedSupervisor, child_spec)
      |> case do
        {:ok, pid} -> Horde.Registry.register(Foundation.ProcessRegistry, name, pid)
        error -> error
      end
      
      # Direct access when you need it:
      Horde.DynamicSupervisor.start_child(Foundation.DistributedSupervisor, complex_spec)
  """
  
  require Logger
  
  # LEAKY DESIGN: These are the actual tools we use, clearly exposed
  @horde_supervisor Foundation.DistributedSupervisor
  @horde_registry Foundation.ProcessRegistry
  
  @doc """
  Starts a globally unique process (singleton) across the cluster.
  
  ## What This Function Actually Does
  
  1. Creates a child_spec for Horde.DynamicSupervisor
  2. Starts the child with Horde.DynamicSupervisor.start_child/2
  3. Registers the process with Horde.Registry.register/3 (if name provided)
  4. Provides better error messages than raw Horde
  
  ## When to Use the Facade vs Raw Horde
  
  Use this facade when:
  - You want a simple singleton pattern
  - You want combined start+register operation
  - You want clearer error messages
  
  Use Horde directly when:
  - You need custom child_spec configuration
  - You need advanced Horde.Registry metadata
  - You're implementing a custom distribution pattern
  
  ## Examples
  
      # Simple singleton
      {:ok, pid} = Foundation.ProcessManager.start_singleton(MyWorker, [])
      
      # Singleton with name for discovery
      {:ok, pid} = Foundation.ProcessManager.start_singleton(
        MyWorker, 
        [], 
        name: :global_worker
      )
      
      # Custom restart strategy
      {:ok, pid} = Foundation.ProcessManager.start_singleton(
        MyWorker,
        [],
        name: :temp_worker,
        restart: :temporary
      )
  """
  @spec start_singleton(module(), list(), keyword()) :: {:ok, pid()} | {:error, term()}
  def start_singleton(module, args, opts \\ []) do
    name = Keyword.get(opts, :name)
    restart = Keyword.get(opts, :restart, :permanent)
    
    # LEAKY: We show exactly what child_spec we create
    child_spec = %{
      id: name || module,
      start: {module, :start_link, [args]},
      restart: restart,
      type: :worker
    }
    
    Logger.debug("Foundation.ProcessManager: Starting singleton #{inspect(name || module)}")
    Logger.debug("  Child spec: #{inspect(child_spec)}")
    Logger.debug("  Using Horde.DynamicSupervisor: #{@horde_supervisor}")
    
    # LEAKY: We show the exact Horde calls we make
    case Horde.DynamicSupervisor.start_child(@horde_supervisor, child_spec) do
      {:ok, pid} ->
        register_result = if name do
          Logger.debug("  Registering with Horde.Registry: #{@horde_registry}")
          
          metadata = %{
            pid: pid,
            node: Node.self(),
            started_at: System.system_time(:second),
            module: module
          }
          
          case Horde.Registry.register(@horde_registry, name, metadata) do
            :ok -> 
              Logger.info("Foundation.ProcessManager: Singleton #{name} started and registered")
              :ok
            {:error, reason} -> 
              Logger.warning("Singleton started but registration failed: #{inspect(reason)}")
              Logger.warning("Process is running but not discoverable via lookup_singleton/1")
              :ok  # Still return success since process started
          end
        else
          :ok
        end
        
        {:ok, pid}
      
      {:error, {:already_started, existing_pid}} ->
        Logger.debug("Singleton #{inspect(name || module)} already running")
        {:ok, existing_pid}
      
      {:error, reason} = error ->
        Logger.error("Failed to start singleton #{inspect(name || module)}: #{inspect(reason)}")
        Logger.error("You can try calling Horde.DynamicSupervisor.start_child/2 directly for more control")
        error
    end
  end
  
  @doc """
  Looks up a singleton process by name.
  
  ## What This Function Actually Does
  
  This is a thin wrapper around Horde.Registry.lookup/2 that:
  - Simplifies the return format for the common single-result case
  - Provides better error messages
  
  ## Equivalent Horde Call
  
      # This facade call:
      Foundation.ProcessManager.lookup_singleton(:my_service)
      
      # Is equivalent to:
      case Horde.Registry.lookup(Foundation.ProcessRegistry, :my_service) do
        [{pid, _metadata}] -> {:ok, pid}
        [] -> :not_found
      end
  """
  @spec lookup_singleton(term()) :: {:ok, pid()} | :not_found
  def lookup_singleton(name) do
    Logger.debug("Foundation.ProcessManager: Looking up singleton #{inspect(name)}")
    Logger.debug("  Using Horde.Registry: #{@horde_registry}")
    
    case Horde.Registry.lookup(@horde_registry, name) do
      [{pid, metadata}] ->
        Logger.debug("  Found: #{inspect(pid)} on #{metadata.node}")
        {:ok, pid}
      
      [] ->
        Logger.debug("  Not found")
        Logger.debug("  You can also call: Horde.Registry.lookup(#{@horde_registry}, #{inspect(name)})")
        :not_found
      
      multiple_results ->
        # This shouldn't happen with singleton pattern, but if it does, we're transparent
        Logger.warning("Multiple results for singleton lookup: #{inspect(multiple_results)}")
        Logger.warning("This suggests a bug in the singleton pattern or registry inconsistency")
        {:ok, elem(hd(multiple_results), 0)}  # Return first PID
    end
  end
  
  @doc """
  Starts a replicated process - one instance per node in the cluster.
  
  ## What This Function Actually Does
  
  This function coordinates starting a process on every node in the cluster:
  1. Gets list of all nodes with [Node.self() | Node.list()]
  2. Uses :rpc.call/4 to start the singleton on each node
  3. Returns results from all nodes
  
  This is NOT a Horde-specific pattern - it's a coordination pattern that
  uses singleton creation across multiple nodes.
  """
  @spec start_replicated(module(), list(), keyword()) :: 
    list({:ok, pid()} | {:error, term()})
  def start_replicated(module, args, opts \\ []) do
    base_name = Keyword.get(opts, :name, module)
    nodes = [Node.self() | Node.list()]
    
    Logger.info("Foundation.ProcessManager: Starting replicated #{module} on #{length(nodes)} nodes")
    
    # LEAKY: We show exactly how we coordinate across nodes
    tasks = Enum.map(nodes, fn node ->
      Task.async(fn ->
        # Create unique name per node to avoid conflicts
        node_name = {base_name, node}
        node_opts = Keyword.put(opts, :name, node_name)
        
        if node == Node.self() do
          # Local call
          start_singleton(module, args, node_opts)
        else
          # Remote call - transparently shown
          Logger.debug("  Making RPC call to #{node}")
          case :rpc.call(node, __MODULE__, :start_singleton, [module, args, node_opts]) do
            {:badrpc, reason} -> {:error, {:rpc_failed, node, reason}}
            result -> result
          end
        end
      end)
    end)
    
    results = Task.await_many(tasks, 30_000)
    
    Logger.info("Replicated start complete: #{inspect(results)}")
    results
  end
end

# ==============================================================================
# PATTERN 2: The Transparent Channel Abstraction
# ==============================================================================

defmodule Foundation.Channels do
  @moduledoc """
  Application-layer channels using Phoenix.PubSub.
  
  ## Philosophy: Solve Head-of-Line Blocking Transparently
  
  Distributed Erlang has a head-of-line blocking problem: a large message
  on the TCP connection can block small, urgent messages. 
  
  This module solves it by using Phoenix.PubSub topics as logical "channels"
  over the same underlying Distributed Erlang connection.
  
  ## Leaky Design: You Can See Exactly What We Do
  
  - :control messages -> Phoenix.PubSub topic "foundation:control"
  - :events messages -> Phoenix.PubSub topic "foundation:events"
  - :data messages -> Phoenix.PubSub topic "foundation:data"
  - :telemetry messages -> Phoenix.PubSub topic "foundation:telemetry"
  
  ## When to Use Channels vs Direct PubSub
  
  Use Foundation.Channels when:
  - You want standard channel semantics
  - You want automatic channel selection based on message type
  - You want the convenience of compression and routing
  
  Use Phoenix.PubSub directly when:
  - You need custom topics
  - You need advanced PubSub features (local vs distributed)
  - You're building your own messaging patterns
  """
  
  require Logger
  
  # LEAKY: The exact PubSub process we use is clearly exposed
  @pubsub Foundation.PubSub
  
  # LEAKY: The topic mapping is explicit and simple
  @topic_mapping %{
    control: "foundation:control",
    events: "foundation:events", 
    data: "foundation:data",
    telemetry: "foundation:telemetry"
  }
  
  @doc """
  Broadcast a message on a logical channel.
  
  ## What This Function Actually Does
  
  1. Maps channel atom to Phoenix.PubSub topic string
  2. Optionally compresses message if requested
  3. Calls Phoenix.PubSub.broadcast/3
  
  ## Equivalent Phoenix.PubSub Call
  
      # This facade call:
      Foundation.Channels.broadcast(:events, my_message)
      
      # Is equivalent to:
      Phoenix.PubSub.broadcast(Foundation.PubSub, "foundation:events", my_message)
  
  ## Channel to Topic Mapping
  
  #{inspect(@topic_mapping, pretty: true)}
  """
  @spec broadcast(atom(), term(), keyword()) :: :ok | {:error, term()}
  def broadcast(channel, message, opts \\ []) do
    topic = Map.get(@topic_mapping, channel)
    
    unless topic do
      available_channels = Map.keys(@topic_mapping)
      raise ArgumentError, """
      Invalid channel: #{inspect(channel)}
      Available channels: #{inspect(available_channels)}
      
      Or use Phoenix.PubSub.broadcast(#{@pubsub}, "your-custom-topic", message)
      """
    end
    
    Logger.debug("Foundation.Channels: Broadcasting to #{channel} (topic: #{topic})")
    
    final_message = case Keyword.get(opts, :compression, false) do
      true ->
        compressed = compress_message(message)
        Logger.debug("  Message compressed: #{byte_size(:erlang.term_to_binary(message))} -> #{byte_size(compressed)} bytes")
        {:foundation_compressed, compressed}
      
      false ->
        message
    end
    
    # LEAKY: Show the exact Phoenix.PubSub call
    Logger.debug("  Phoenix.PubSub.broadcast(#{@pubsub}, #{inspect(topic)}, ...)")
    
    case Phoenix.PubSub.broadcast(@pubsub, topic, final_message) do
      :ok -> 
        Logger.debug("  Broadcast successful")
        :ok
      
      {:error, reason} = error ->
        Logger.error("Channel broadcast failed: #{inspect(reason)}")
        Logger.error("You can try Phoenix.PubSub.broadcast/3 directly if needed")
        error
    end
  end
  
  @doc """
  Subscribe to a logical channel.
  
  ## What This Function Actually Does
  
  1. Maps channel atom to Phoenix.PubSub topic
  2. Calls Phoenix.PubSub.subscribe/2
  3. Optionally registers a message handler
  
  ## Equivalent Phoenix.PubSub Call
  
      # This:
      Foundation.Channels.subscribe(:events)
      
      # Is equivalent to:
      Phoenix.PubSub.subscribe(Foundation.PubSub, "foundation:events")
  """
  @spec subscribe(atom(), pid()) :: :ok | {:error, term()}
  def subscribe(channel, handler \\ self()) do
    topic = Map.get(@topic_mapping, channel)
    
    unless topic do
      available_channels = Map.keys(@topic_mapping)
      raise ArgumentError, "Invalid channel: #{inspect(channel)}. Available: #{inspect(available_channels)}"
    end
    
    Logger.debug("Foundation.Channels: Subscribing to #{channel} (topic: #{topic})")
    Logger.debug("  Phoenix.PubSub.subscribe(#{@pubsub}, #{inspect(topic)})")
    
    case Phoenix.PubSub.subscribe(@pubsub, topic) do
      :ok ->
        if handler != self() do
          # Register custom handler (implementation would store this mapping)
          Logger.debug("  Registered custom handler: #{inspect(handler)}")
        end
        :ok
      
      {:error, reason} = error ->
        Logger.error("Channel subscription failed: #{inspect(reason)}")
        error
    end
  end
  
  @doc """
  Intelligently route a message to the appropriate channel.
  
  ## What This Function Actually Does
  
  This function demonstrates "smart" behavior while being completely transparent:
  1. Analyzes message content and options
  2. Selects appropriate channel based on heuristics
  3. Calls broadcast/3 with selected channel
  
  ## Intelligence Rules (Completely Visible)
  
  - If opts[:priority] == :high -> :control channel
  - If message size > 10KB -> :data channel  
  - If message matches telemetry pattern -> :telemetry channel
  - Otherwise -> :events channel
  """
  def route_message(message, opts \\ []) do
    channel = determine_channel(message, opts)
    
    Logger.debug("Foundation.Channels: Auto-routing message to #{channel} channel")
    Logger.debug("  Routing logic: #{explain_routing_decision(message, opts, channel)}")
    
    broadcast(channel, message, opts)
  end
  
  # LEAKY: All routing logic is visible and simple
  defp determine_channel(message, opts) do
    cond do
      Keyword.get(opts, :priority) == :high ->
        :control
      
      large_message?(message) ->
        :data
      
      telemetry_message?(message) ->
        :telemetry
      
      true ->
        :events
    end
  end
  
  defp explain_routing_decision(message, opts, channel) do
    cond do
      Keyword.get(opts, :priority) == :high ->
        "High priority specified -> control"
      
      large_message?(message) ->
        "Large message (#{estimate_size(message)} bytes) -> data"
      
      telemetry_message?(message) ->
        "Telemetry pattern detected -> telemetry"
      
      true ->
        "Default routing -> events"
    end
  end
  
  defp large_message?(message) do
    estimate_size(message) > 10_240  # 10KB threshold
  end
  
  defp telemetry_message?(message) do
    case message do
      {:telemetry, _} -> true
      %{type: :metric} -> true
      %{type: :measurement} -> true
      _ -> false
    end
  end
  
  defp estimate_size(message) do
    byte_size(:erlang.term_to_binary(message))
  end
  
  defp compress_message(message) do
    :zlib.compress(:erlang.term_to_binary(message))
  end
end

# ==============================================================================
# PATTERN 3: The Configuration Translation Layer
# ==============================================================================

defmodule Foundation.ClusterConfig do
  @moduledoc """
  Translates Foundation's simple configuration to libcluster topologies.
  
  ## Philosophy: Translation, Not Replacement
  
  This module never tries to replace libcluster's configuration system.
  Instead, it provides a simple front-end that translates to proper
  libcluster configuration.
  
  ## Transparency: You Can See The Translation
  
  Every translation function shows exactly what libcluster configuration
  it produces. This makes debugging easy and learning gradual.
  
  ## The Three Modes
  
  1. Mortal Mode: `cluster: true` -> Auto-detect best strategy
  2. Apprentice Mode: `cluster: :kubernetes` -> Translate to libcluster config
  3. Wizard Mode: Existing libcluster config -> Foundation steps aside
  """
  
  require Logger
  
  @doc """
  Resolves Foundation configuration to libcluster topology.
  
  ## What This Function Actually Does
  
  1. Checks if libcluster is already configured (Wizard mode)
  2. If not, looks at Foundation's :cluster config
  3. Translates Foundation config to libcluster topology
  4. Returns topology ready for Cluster.Supervisor
  
  ## Return Values
  
  - `{:wizard_mode, existing_config}` - libcluster already configured
  - `{:apprentice_mode, translated_config}` - simple config translated
  - `{:mortal_mode, auto_detected_config}` - auto-detected configuration
  - `{:no_clustering, []}` - clustering disabled
  """
  def resolve_cluster_config() do
    Logger.info("Foundation.ClusterConfig: Resolving cluster configuration...")
    
    # LEAKY: Show exactly how we detect existing libcluster config
    case Application.get_env(:libcluster, :topologies) do
      topologies when is_list(topologies) and topologies != [] ->
        Logger.info("  Found existing libcluster configuration (Wizard mode)")
        Logger.info("  Foundation will defer to: #{inspect(topologies)}")
        {:wizard_mode, topologies}
      
      _ ->
        # No existing libcluster config, check Foundation config
        foundation_config = Application.get_env(:foundation, :cluster, false)
        Logger.info("  Foundation cluster config: #{inspect(foundation_config)}")
        
        translate_foundation_config(foundation_config)
    end
  end
  
  # LEAKY: All translation logic is completely visible
  defp translate_foundation_config(false) do
    Logger.info("  Clustering disabled")
    {:no_clustering, []}
  end
  
  defp translate_foundation_config(true) do
    Logger.info("  Mortal mode: Auto-detecting best strategy...")
    strategy_result = auto_detect_strategy()
    Logger.info("  Auto-detected: #{inspect(strategy_result)}")
    {:mortal_mode, strategy_result}
  end
  
  defp translate_foundation_config(:kubernetes) do
    Logger.info("  Apprentice mode: Translating :kubernetes")
    config = translate_kubernetes_config()
    Logger.info("  Translated to: #{inspect(config)}")
    {:apprentice_mode, config}
  end
  
  defp translate_foundation_config(:consul) do
    Logger.info("  Apprentice mode: Translating :consul")
    config = translate_consul_config()
    Logger.info("  Translated to: #{inspect(config)}")
    {:apprentice_mode, config}
  end
  
  defp translate_foundation_config(:dns) do
    Logger.info("  Apprentice mode: Translating :dns")
    config = translate_dns_config()
    Logger.info("  Translated to: #{inspect(config)}")
    {:apprentice_mode, config}
  end
  
  defp translate_foundation_config([strategy: strategy] = opts) when is_atom(strategy) do
    Logger.info("  Apprentice mode: Translating strategy #{strategy} with opts")
    config = translate_strategy_with_opts(strategy, opts)
    Logger.info("  Translated to: #{inspect(config)}")
    {:apprentice_mode, config}
  end
  
  defp translate_foundation_config(other) do
    Logger.warning("  Unknown Foundation cluster config: #{inspect(other)}")
    Logger.warning("  Falling back to auto-detection")
    strategy_result = auto_detect_strategy()
    {:mortal_mode, strategy_result}
  end
  
  @doc """
  Auto-detects the best clustering strategy based on environment.
  
  ## Detection Logic (Completely Visible)
  
  1. Check if mdns_lite is available AND we're in development -> MdnsLite strategy
  2. Check if Kubernetes environment variables exist -> Kubernetes strategy  
  3. Check if Consul is available -> Consul strategy
  4. Fall back to Gossip strategy with default settings
  
  ## Environment Detection Methods
  
  - Kubernetes: Checks for KUBERNETES_SERVICE_HOST environment variable
  - Consul: Checks for CONSUL_HTTP_ADDR environment variable
  - Development: Checks MIX_ENV == "dev"
  - mdns_lite: Checks if :mdns_lite application is loaded
  """
  def auto_detect_strategy() do
    Logger.info("Foundation.ClusterConfig: Auto-detecting clustering strategy...")
    
    strategy = cond do
      mdns_lite_available?() and development_mode?() ->
        Logger.info("  Detected: Development mode with mdns_lite available")
        Logger.info("  Strategy: Foundation.Strategies.MdnsLite")
        foundation_mdns_strategy()
      
      kubernetes_environment?() ->
        Logger.info("  Detected: Kubernetes environment (KUBERNETES_SERVICE_HOST present)")
        Logger.info("  Strategy: Cluster.Strategy.Kubernetes")
        translate_kubernetes_config()
      
      consul_available?() ->
        Logger.info("  Detected: Consul available (CONSUL_HTTP_ADDR present)")
        Logger.info("  Strategy: Cluster.Strategy.Consul")
        translate_consul_config()
      
      true ->
        Logger.info("  Detected: Generic environment")
        Logger.info("  Strategy: Cluster.Strategy.Gossip (fallback)")
        translate_gossip_config()
    end
    
    Logger.info("  Final topology: #{inspect(strategy)}")
    strategy
  end
  
  # LEAKY: All environment detection logic is simple and visible
  defp mdns_lite_available?() do
    case Application.load(:mdns_lite) do
      :ok -> true
      {:error, {:already_loaded, :mdns_lite}} -> true
      _ -> false
    end
  end
  
  defp development_mode?() do
    System.get_env("MIX_ENV") == "dev"
  end
  
  defp kubernetes_environment?() do
    System.get_env("KUBERNETES_SERVICE_HOST") != nil
  end
  
  defp consul_available?() do
    System.get_env("CONSUL_HTTP_ADDR") != nil
  end
  
  # LEAKY: All translation functions show exact libcluster configuration
  
  @doc """
  Translates to Kubernetes strategy configuration.
  
  ## Generated libcluster Configuration
  
  ```elixir
  [
    foundation_k8s: [
      strategy: Cluster.Strategy.Kubernetes,
      config: [
        mode: :hostname,
        kubernetes_node_basename: "app-name",
        kubernetes_selector: "app=app-name"
      ]
    ]
  ]
  ```
  
  ## Configuration Sources
  
  - App name: FOUNDATION_APP_NAME env var or Application.get_application()
  - Selector: FOUNDATION_K8S_SELECTOR env var or "app=<app-name>"
  """
  def translate_kubernetes_config() do
    app_name = get_app_name()
    selector = System.get_env("FOUNDATION_K8S_SELECTOR", "app=#{app_name}")
    
    config = [
      foundation_k8s: [
        strategy: Cluster.Strategy.Kubernetes,
        config: [
          mode: :hostname,
          kubernetes_node_basename: app_name,
          kubernetes_selector: selector
        ]
      ]
    ]
    
    Logger.debug("Kubernetes config generated:")
    Logger.debug("  App name: #{app_name}")
    Logger.debug("  Selector: #{selector}")
    Logger.debug("  libcluster topology: #{inspect(config)}")
    
    config
  end
  
  @doc """
  Translates to Consul strategy configuration.
  
  ## Generated libcluster Configuration
  
  ```elixir
  [
    foundation_consul: [
      strategy: Cluster.Strategy.Consul,
      config: [
        service_name: "app-name"
      ]
    ]
  ]
  ```
  """
  def translate_consul_config() do
    service_name = System.get_env("FOUNDATION_SERVICE_NAME", get_app_name())
    
    config = [
      foundation_consul: [
        strategy: Cluster.Strategy.Consul,
        config: [
          service_name: service_name
        ]
      ]
    ]
    
    Logger.debug("Consul config generated: #{inspect(config)}")
    config
  end
  
  @doc """
  Translates to DNS strategy configuration.
  
  ## Generated libcluster Configuration
  
  ```elixir
  [
    foundation_dns: [
      strategy: Cluster.Strategy.DNS,
      config: [
        service: "app-name",
        application_name: "app-name"
      ]
    ]
  ]
  ```
  """
  def translate_dns_config() do
    app_name = get_app_name()
    service = System.get_env("FOUNDATION_DNS_SERVICE", app_name)
    
    config = [
      foundation_dns: [
        strategy: Cluster.Strategy.DNS,
        config: [
          service: service,
          application_name: app_name
        ]
      ]
    ]
    
    Logger.debug("DNS config generated: #{inspect(config)}")
    config
  end
  
  @doc """
  Translates to Gossip strategy configuration (fallback).
  
  ## Generated libcluster Configuration
  
  ```elixir
  [
    foundation_gossip: [
      strategy: Cluster.Strategy.Gossip,
      config: [
        multicast_addr: "230.1.1.251",
        multicast_ttl: 1,
        secret: "foundation-cluster"
      ]
    ]
  ]
  ```
  """
  def translate_gossip_config() do
    secret = System.get_env("FOUNDATION_GOSSIP_SECRET", "foundation-cluster")
    
    config = [
      foundation_gossip: [
        strategy: Cluster.Strategy.Gossip,
        config: [
          multicast_addr: "230.1.1.251",
          multicast_ttl: 1,
          secret: secret
        ]
      ]
    ]
    
    Logger.debug("Gossip config generated: #{inspect(config)}")
    config
  end
  
  @doc """
  Creates configuration for Foundation's custom MdnsLite strategy.
  
  ## Generated libcluster Configuration
  
  ```elixir
  [
    foundation_mdns: [
      strategy: Foundation.Strategies.MdnsLite,
      config: [
        service_name: "app-name-dev",
        discovery_interval: 5000
      ]
    ]
  ]
  ```
  """
  def foundation_mdns_strategy() do
    app_name = get_app_name()
    service_name = "#{app_name}-dev"
    
    config = [
      foundation_mdns: [
        strategy: Foundation.Strategies.MdnsLite,
        config: [
          service_name: service_name,
          discovery_interval: 5000
        ]
      ]
    ]
    
    Logger.debug("MdnsLite strategy config: #{inspect(config)}")
    config
  end
  
  defp translate_strategy_with_opts(strategy, opts) do
    # Handle explicit strategy with options
    base_config = case strategy do
      :gossip -> translate_gossip_config()
      :kubernetes -> translate_kubernetes_config()
      :consul -> translate_consul_config()
      :dns -> translate_dns_config()
    end
    
    # Could merge additional options here
    base_config
  end
  
  defp get_app_name() do
    System.get_env("FOUNDATION_APP_NAME") ||
    to_string(Application.get_application(__MODULE__) || "foundation-app")
  end
end

# ==============================================================================
# PATTERN 4: The Self-Documenting Health Monitor
# ==============================================================================

defmodule Foundation.HealthMonitor do
  @moduledoc """
  Cluster health monitoring with complete transparency.
  
  ## Philosophy: Observable and Explainable
  
  This module collects health metrics from all Foundation components
  and underlying tools. Every metric source is clearly documented,
  and the health assessment logic is completely visible.
  
  ## What We Monitor (And How)
  
  - Cluster connectivity: Node.list() and ping tests
  - Horde health: Process counts and registry synchronization
  - Phoenix.PubSub: Message delivery and subscription counts  
  - Service availability: Registered services and health checks
  - Performance metrics: Message latency and throughput
  
  ## Leaky Design: All Assessment Logic is Visible
  
  The health assessment rules are implemented as simple, readable
  functions that you can inspect, understand, and modify.
  """
  
  use GenServer
  require Logger
  
  defstruct [
    :last_check_time,
    :health_history,
    :check_interval
  ]
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(opts) do
    check_interval = Keyword.get(opts, :check_interval, 30_000)  # 30 seconds
    
    # Start first health check after a brief delay
    Process.send_after(self(), :health_check, 5_000)
    
    state = %__MODULE__{
      last_check_time: nil,
      health_history: [],
      check_interval: check_interval
    }
    
    Logger.info("Foundation.HealthMonitor: Started with #{check_interval}ms check interval")
    {:ok, state}
  end
  
  @doc """
  Gets comprehensive cluster health information.
  
  ## Health Report Structure
  
  ```elixir
  %{
    overall_status: :healthy | :degraded | :critical,
    cluster: %{
      connected_nodes: 3,
      expected_nodes: 3,
      node_health: [%{node: :app@host, status: :healthy, ...}]
    },
    services: %{
      total_registered: 15,
      healthy: 14,
      unhealthy: 1,
      services: [%{name: :user_service, status: :healthy, ...}]
    },
    infrastructure: %{
      horde_status: :synchronized,
      pubsub_status: :healthy,
      message_queues: :normal
    },
    performance: %{
      avg_message_latency_ms: 12,
      message_throughput_per_sec: 1547,
      error_rate_percent: 0.02
    },
    recommendations: ["Consider adding more nodes", ...]
  }
  ```
  """
  def get_cluster_health() do
    GenServer.call(__MODULE__, :get_health, 10_000)
  end
  
  @impl true
  def handle_call(:get_health, _from, state) do
    health_report = perform_comprehensive_health_check()
    {:reply, health_report, state}
  end
  
  @impl true
  def handle_info(:health_check, state) do
    Logger.debug("Foundation.HealthMonitor: Performing scheduled health check")
    
    health_report = perform_comprehensive_health_check()
    
    # Store in history (keep last 10 checks)
    new_history = [health_report | Enum.take(state.health_history, 9)]
    
    # Log concerning issues
    case health_report.overall_status do
      :healthy -> 
        Logger.debug("Cluster health: OK")
      
      :degraded ->
        Logger.warning("Cluster health: DEGRADED")
        Logger.warning("Issues: #{inspect(health_report.issues)}")
      
      :critical ->
        Logger.error("Cluster health: CRITICAL")
        Logger.error("Critical issues: #{inspect(health_report.critical_issues)}")
    end
    
    # Schedule next check
    Process.send_after(self(), :health_check, state.check_interval)
    
    new_state = %{state |
      last_check_time: System.system_time(:millisecond),
      health_history: new_history
    }
    
    {:noreply, new_state}
  end
  
  # LEAKY: All health check logic is completely visible and simple
  
  defp perform_comprehensive_health_check() do
    Logger.debug("  Checking cluster connectivity...")
    cluster_health = check_cluster_connectivity()
    
    Logger.debug("  Checking service registry...")
    service_health = check_service_registry_health()
    
    Logger.debug("  Checking infrastructure components...")
    infrastructure_health = check_infrastructure_health()
    
    Logger.debug("  Collecting performance metrics...")
    performance_metrics = collect_performance_metrics()
    
    Logger.debug("  Analyzing overall status...")
    overall_status = determine_overall_status([
      cluster_health.status,
      service_health.status,
      infrastructure_health.status
    ])
    
    Logger.debug("  Generating recommendations...")
    recommendations = generate_health_recommendations(
      cluster_health, 
      service_health, 
      infrastructure_health,
      performance_metrics
    )
    
    %{
      overall_status: overall_status,
      cluster: cluster_health,
      services: service_health,
      infrastructure: infrastructure_health,
      performance: performance_metrics,
      recommendations: recommendations,
      checked_at: System.system_time(:millisecond),
      check_duration_ms: 0  # Would measure actual check time
    }
  end
  
  @doc """
  Checks cluster connectivity and node health.
  
  ## What This Function Actually Does
  
  1. Gets connected nodes with [Node.self() | Node.list()]
  2. Pings each node to verify connectivity
  3. Checks expected node count from configuration
  4. Assesses each node's basic health metrics
  
  ## Health Assessment Logic
  
  - :healthy: All expected nodes connected and responding
  - :degraded: Some nodes missing or slow to respond
  - :critical: Majority of nodes unreachable
  """
  def check_cluster_connectivity() do
    connected_nodes = [Node.self() | Node.list()]
    expected_nodes = get_expected_node_count()
    
    Logger.debug("    Connected nodes: #{length(connected_nodes)}")
    Logger.debug("    Expected nodes: #{expected_nodes}")
    
    # Test connectivity to each node
    node_health_results = Enum.map(connected_nodes, fn node ->
      check_individual_node_health(node)
    end)
    
    healthy_nodes = Enum.count(node_health_results, &(&1.status == :healthy))
    
    status = cond do
      healthy_nodes >= expected_nodes -> :healthy
      healthy_nodes >= div(expected_nodes, 2) -> :degraded
      true -> :critical
    end
    
    %{
      status: status,
      connected_nodes: length(connected_nodes),
      expected_nodes: expected_nodes,
      healthy_nodes: healthy_nodes,
      node_health: node_health_results
    }
  end
  
  defp check_individual_node_health(node) do
    start_time = System.monotonic_time(:microsecond)
    
    ping_result = if node == Node.self() do
      :pong  # Local node always responds
    else
      Node.ping(node)
    end
    
    ping_time_us = System.monotonic_time(:microsecond) - start_time
    
    case ping_result do
      :pong ->
        %{
          node: node,
          status: :healthy,
          ping_time_us: ping_time_us,
          load_avg: get_node_load_average(node),
          memory_usage: get_node_memory_usage(node)
        }
      
      :pang ->
        %{
          node: node,
          status: :unreachable,
          ping_time_us: nil,
          load_avg: nil,
          memory_usage: nil
        }
    end
  end
  
  # Simple RPC calls to get node metrics (with error handling)
  defp get_node_load_average(node) do
    case safe_rpc_call(node, :cpu_sup, :avg1, []) do
      {:ok, load} -> load / 256  # Convert to percentage
      _ -> nil
    end
  end
  
  defp get_node_memory_usage(node) do
    case safe_rpc_call(node, :erlang, :memory, [:total]) do
      {:ok, memory} -> memory
      _ -> nil
    end
  end
  
  defp safe_rpc_call(node, module, function, args) do
    case :rpc.call(node, module, function, args, 5000) do
      {:badrpc, _reason} -> {:error, :rpc_failed}
      result -> {:ok, result}
    end
  end
  
  defp get_expected_node_count() do
    # Try various sources for expected node count
    System.get_env("FOUNDATION_EXPECTED_NODES", "1") |> String.to_integer()
  rescue
    _ -> 1
  end
  
  defp determine_overall_status(component_statuses) do
    cond do
      Enum.any?(component_statuses, &(&1 == :critical)) -> :critical
      Enum.any?(component_statuses, &(&1 == :degraded)) -> :degraded
      true -> :healthy
    end
  end
  
  # Stub implementations for other health checks
  defp check_service_registry_health() do
    %{status: :healthy, total_registered: 0, healthy: 0, unhealthy: 0, services: []}
  end
  
  defp check_infrastructure_health() do
    %{status: :healthy, horde_status: :synchronized, pubsub_status: :healthy}
  end
  
  defp collect_performance_metrics() do
    %{
      avg_message_latency_ms: 0,
      message_throughput_per_sec: 0,
      error_rate_percent: 0.0
    }
  end
  
  defp generate_health_recommendations(_cluster, _services, _infra, _perf) do
    []
  end
end