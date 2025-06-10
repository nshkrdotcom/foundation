# Foundation 2.0: The Synthesis Architecture
## Smart Facades on a Pragmatic Core

### Core Philosophy: Layers of Abstraction with No Lock-in

Foundation 2.0 will provide **three levels of interaction** that developers can mix and match freely:

1. **Pragmatic Core**: Lightweight orchestration of best-in-class tools
2. **Smart Facades**: Convenient patterns for common use cases  
3. **Direct Tool Access**: Full power of underlying libraries when needed

### The Three-Layer Developer Experience

#### Layer 1: Pragmatic Core (The Foundation)
```elixir
# Foundation sets up and configures the best tools
config :foundation,
  # Mortal Mode (Zero Config)
  cluster: true  # Uses mdns_lite for dev, auto-detects for prod
  
  # Apprentice Mode (Simple Config)  
  cluster: :kubernetes  # Translates to optimal libcluster config
  
  # Wizard Mode (Full Control)
  # Foundation detects existing libcluster config and steps aside
```

**What Foundation Does**:
- Intelligent environment detection and tool selection
- Optimal configuration of libcluster, Horde, Phoenix.PubSub
- Supervision and health monitoring of configured tools
- **What Foundation Doesn't Do**: Hide or replace the underlying tools

#### Layer 2: Smart Facades (Convenience Patterns)
```elixir
# Optional convenience functions that encode best practices
defmodule MyApp.UserService do
  def start_link(opts) do
    # Facade for common pattern: singleton process across cluster
    Foundation.ProcessManager.start_singleton(__MODULE__, opts, name: :user_service)
    # This is just sugar over: Horde.DynamicSupervisor.start_child + Horde.Registry.register
  end
end

# Service discovery with built-in load balancing
Foundation.ServiceMesh.route_to_service(:user_service, message)
# This is sugar over: Horde.Registry.lookup + simple load balancing logic
```

**What Smart Facades Do**:
- Encode common distributed patterns (singleton, replicated, partitioned)
- Handle multi-step operations (start + register, lookup + load balance)
- Provide clear error messages and logging
- **What Smart Facades Don't Do**: Hide the underlying tool APIs

#### Layer 3: Direct Tool Access (Full Power)
```elixir
# When you need advanced features, drop to the tool level
Horde.DynamicSupervisor.start_child(Foundation.DistributedSupervisor, complex_child_spec)
Horde.Registry.register(Foundation.ProcessRegistry, key, complex_metadata)
Phoenix.PubSub.broadcast(Foundation.PubSub, topic, message)

# Foundation never prevents direct access to configured tools
```

## Revised Implementation: Pragmatic Core First

### Phase 1: The Pragmatic Core (Weeks 1-4)

#### Week 1: Environment Detection & Configuration Translation
```elixir
# lib/foundation/cluster_config.ex
defmodule Foundation.ClusterConfig do
  @doc """
  Translates simple Foundation config to optimal libcluster topology.
  
  Supports three modes:
  - Mortal: `cluster: true` -> auto-detect best strategy
  - Apprentice: `cluster: :kubernetes` -> translate to libcluster config  
  - Wizard: Detects existing libcluster config and defers to it
  """
  def resolve_cluster_config() do
    case detect_existing_libcluster_config() do
      :none -> translate_foundation_config()
      existing_config -> {:wizard_mode, existing_config}
    end
  end
  
  defp translate_foundation_config() do
    foundation_config = Application.get_env(:foundation, :cluster)
    
    case foundation_config do
      true -> {:mortal_mode, auto_detect_strategy()}
      :kubernetes -> {:apprentice_mode, translate_kubernetes_config()}
      :consul -> {:apprentice_mode, translate_consul_config()}
      :dns -> {:apprentice_mode, translate_dns_config()}
      false -> {:no_clustering, []}
    end
  end
  
  defp auto_detect_strategy() do
    cond do
      mdns_lite_available?() and development_mode?() ->
        foundation_mdns_strategy()
      kubernetes_environment?() ->
        translate_kubernetes_config()
      consul_available?() ->
        translate_consul_config()
      true ->
        translate_gossip_config()
    end
  end
  
  defp translate_kubernetes_config() do
    [
      foundation_k8s: [
        strategy: Cluster.Strategy.Kubernetes,
        config: [
          mode: :hostname,
          kubernetes_node_basename: get_app_name(),
          kubernetes_selector: "app=#{get_app_name()}"
        ]
      ]
    ]
  end
end
```

#### Week 2: Custom MdnsLite Strategy for Zero-Config Development
```elixir
# lib/foundation/strategies/mdns_lite.ex
defmodule Foundation.Strategies.MdnsLite do
  @behaviour Cluster.Strategy
  use GenServer
  
  @doc """
  Custom libcluster strategy using mdns_lite for zero-config development clustering.
  
  This allows developers to start multiple nodes with `iex --name dev1@localhost -S mix`
  and have them automatically discover each other on the local network.
  """
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(opts) do
    service_name = Keyword.get(opts, :service_name, get_app_name())
    
    # Register this node's service
    MdnsLite.add_mdns_service(%{
      id: :foundation_cluster,
      protocol: service_name,
      transport: "tcp",
      port: get_epmd_port(),
      txt_payload: ["node=#{Node.self()}", "foundation=true"]
    })
    
    # Start discovery process
    schedule_discovery()
    
    {:ok, %{service_name: service_name, discovered_nodes: MapSet.new()}}
  end
  
  @impl true
  def handle_info(:discover, state) do
    # Query for other Foundation nodes
    discovered = discover_foundation_nodes(state.service_name)
    new_nodes = MapSet.difference(discovered, state.discovered_nodes)
    
    # Connect to newly discovered nodes
    Enum.each(new_nodes, fn node ->
      unless node == Node.self() do
        Logger.info("Foundation: Connecting to discovered node #{node}")
        Node.connect(node)
      end
    end)
    
    schedule_discovery()
    {:noreply, %{state | discovered_nodes: MapSet.union(state.discovered_nodes, discovered)}}
  end
  
  defp discover_foundation_nodes(service_name) do
    # Use mdns_lite to discover other Foundation nodes
    case MdnsLite.query("_#{service_name}._tcp.local") do
      {:ok, services} ->
        services
        |> Enum.map(&extract_node_name/1)
        |> Enum.filter(& &1)
        |> MapSet.new()
      _ ->
        MapSet.new()
    end
  end
end
```

#### Week 3: Application-Layer Channels via Phoenix.PubSub
```elixir
# lib/foundation/channels.ex
defmodule Foundation.Channels do
  @moduledoc """
  Application-layer channels that mitigate Distributed Erlang's head-of-line blocking.
  
  Uses Phoenix.PubSub topics to separate different types of cluster communication:
  - :control - High-priority coordination messages
  - :events - Application events and notifications  
  - :telemetry - Metrics and monitoring data
  - :data - Bulk data transfer
  """
  
  @pubsub Foundation.PubSub
  
  def broadcast(channel, message, opts \\ []) do
    topic = "foundation:#{channel}"
    
    case Keyword.get(opts, :compression, false) do
      true ->
        compressed = compress_message(message)
        Phoenix.PubSub.broadcast(@pubsub, topic, compressed)
      false ->
        Phoenix.PubSub.broadcast(@pubsub, topic, message)
    end
  end
  
  def subscribe(channel, handler \\ self()) do
    topic = "foundation:#{channel}"
    :ok = Phoenix.PubSub.subscribe(@pubsub, topic)
    
    if handler != self() do
      # Register handler for message forwarding
      Foundation.ChannelRegistry.register_handler(topic, handler)
    end
  end
  
  @doc """
  Route a message based on its priority and type.
  
  Examples:
    Foundation.Channels.route_message(urgent_control_msg, priority: :high)
    Foundation.Channels.route_message(large_data, channel: :data, compression: true)
  """
  def route_message(message, opts \\ []) do
    channel = determine_channel(message, opts)
    broadcast(channel, message, opts)
  end
  
  defp determine_channel(message, opts) do
    case Keyword.get(opts, :channel) do
      nil -> infer_channel_from_message(message, opts)
      explicit_channel -> explicit_channel
    end
  end
  
  defp infer_channel_from_message(message, opts) do
    cond do
      Keyword.get(opts, :priority) == :high -> :control
      large_message?(message) -> :data
      telemetry_message?(message) -> :telemetry
      true -> :events
    end
  end
end
```

#### Week 4: Tool Orchestration & Supervision
```elixir
# lib/foundation/supervisor.ex
defmodule Foundation.Supervisor do
  use Supervisor
  
  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end
  
  @impl true
  def init(_init_arg) do
    {cluster_mode, cluster_config} = Foundation.ClusterConfig.resolve_cluster_config()
    
    children = [
      # Core Phoenix.PubSub for application-layer channels
      {Phoenix.PubSub, name: Foundation.PubSub, adapter: Phoenix.PubSub.PG2},
      
      # Channel management
      Foundation.ChannelRegistry,
      
      # Clustering (if configured)
      clustering_child_spec(cluster_mode, cluster_config),
      
      # Distributed process management (if clustering enabled)
      distributed_processes_child_spec(cluster_mode),
      
      # Health monitoring
      Foundation.HealthMonitor
    ]
    |> Enum.filter(& &1)  # Remove nil entries
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  defp clustering_child_spec(:no_clustering, _), do: nil
  defp clustering_child_spec({mode, config}, _) do
    {Cluster.Supervisor, [config, [name: Foundation.ClusterSupervisor]]}
  end
  
  defp distributed_processes_child_spec(:no_clustering), do: nil
  defp distributed_processes_child_spec(_) do
    [
      # Horde for distributed processes
      {Horde.Registry, keys: :unique, name: Foundation.ProcessRegistry, members: :auto},
      {Horde.DynamicSupervisor, name: Foundation.DistributedSupervisor, strategy: :one_for_one, members: :auto}
    ]
  end
end
```

### Phase 2: Smart Facades (Weeks 5-8)

Now we build **thin, stateless convenience layers** on top of the configured tools:

#### Week 5: Process Management Facade
```elixir
# lib/foundation/process_manager.ex
defmodule Foundation.ProcessManager do
  @moduledoc """
  Smart Facade providing convenience functions for distributed process patterns.
  
  This module is a thin wrapper around Horde operations. When you need
  advanced Horde features, call Horde functions directly.
  """
  
  @registry Foundation.ProcessRegistry
  @supervisor Foundation.DistributedSupervisor
  
  @doc """
  Starts a globally unique process (singleton) across the cluster.
  
  This is convenience sugar over:
  1. Horde.DynamicSupervisor.start_child
  2. Horde.Registry.register (if name provided)
  """
  def start_singleton(module, args, opts \\ []) do
    name = Keyword.get(opts, :name, module)
    child_spec = build_child_spec(module, args, name, opts)
    
    case Horde.DynamicSupervisor.start_child(@supervisor, child_spec) do
      {:ok, pid} ->
        register_result = if opts[:name] do
          Horde.Registry.register(@registry, name, %{
            pid: pid,
            node: Node.self(),
            started_at: System.system_time(:second)
          })
        else
          :ok
        end
        
        case register_result do
          :ok -> {:ok, pid}
          {:error, reason} -> 
            Logger.warning("Process started but registration failed: #{reason}")
            {:ok, pid}
        end
      
      {:error, {:already_started, existing_pid}} ->
        Logger.debug("Singleton #{name} already exists")
        {:ok, existing_pid}
      
      error -> error
    end
  end
  
  @doc """
  Starts a replicated process - one instance per node.
  
  Uses Horde's distribution to ensure one process per node.
  """
  def start_replicated(module, args, opts \\ []) do
    # Implementation that leverages Horde's distribution strategies
    nodes = [Node.self() | Node.list()]
    
    tasks = Enum.map(nodes, fn node ->
      Task.async(fn ->
        if node == Node.self() do
          start_singleton(module, args, Keyword.put(opts, :name, {module, node}))
        else
          :rpc.call(node, __MODULE__, :start_singleton, [module, args, Keyword.put(opts, :name, {module, node})])
        end
      end)
    end)
    
    Task.await_many(tasks, 10_000)
  end
  
  @doc """
  Lookup a registered singleton process.
  
  Thin wrapper over Horde.Registry.lookup.
  """
  def lookup_singleton(name) do
    case Horde.Registry.lookup(@registry, name) do
      [{pid, _metadata}] -> {:ok, pid}
      [] -> :not_found
    end
  end
  
  # Helper function to build child specs
  defp build_child_spec(module, args, name, opts) do
    restart = Keyword.get(opts, :restart, :permanent)
    
    %{
      id: name,
      start: {module, :start_link, [args]},
      restart: restart,
      type: :worker
    }
  end
end
```

#### Week 6: Service Discovery Facade
```elixir
# lib/foundation/service_mesh.ex
defmodule Foundation.ServiceMesh do
  @moduledoc """
  Smart Facade for service lifecycle and discovery.
  
  Uses Horde.Registry as the single source of truth, with Phoenix.PubSub
  for event notifications.
  """
  
  @registry Foundation.ProcessRegistry
  
  @doc """
  Register a service with capabilities and metadata.
  
  This performs:
  1. Registration in Horde.Registry (single source of truth)
  2. Announcement via Phoenix.PubSub (for reactive patterns)
  """
  def register_service(name, pid, capabilities \\ [], metadata \\ %{}) do
    service_info = %{
      pid: pid,
      node: Node.self(),
      capabilities: capabilities,
      metadata: metadata,
      registered_at: System.system_time(:second)
    }
    
    case Horde.Registry.register(@registry, {:service, name}, service_info) do
      :ok ->
        # Announce registration for reactive patterns
        Foundation.Channels.broadcast(:events, {:service_registered, name, service_info})
        :ok
      
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Discover services with optional filtering by capabilities.
  
  Returns list of service info maps.
  """
  def discover_services(opts \\ []) do
    # Use Horde.Registry.select for efficient querying
    pattern = build_service_pattern(opts)
    
    @registry
    |> Horde.Registry.select(pattern)
    |> Enum.map(fn {{:service, name}, service_info} ->
      Map.put(service_info, :name, name)
    end)
    |> filter_by_capabilities(opts[:capabilities])
    |> filter_by_health(opts[:health_check])
  end
  
  @doc """
  Route a message to a service instance using load balancing.
  
  This is sugar over discover_services + simple load balancing logic.
  """
  def route_to_service(service_name, message, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :random)
    
    case discover_services(name: service_name) do
      [] ->
        {:error, :service_not_found}
      
      [instance] ->
        send_to_instance(instance, message)
      
      instances ->
        instance = select_instance(instances, strategy)
        send_to_instance(instance, message)
    end
  end
  
  # Helper functions
  defp build_service_pattern(opts) do
    case opts[:name] do
      nil -> [{{:service, :"$1"}, :"$2", [], [{{:"$1", :"$2"}}]}]
      name -> [{{:service, name}, :"$1", [], [{{name, :"$1"}}]}]
    end
  end
  
  defp filter_by_capabilities(services, nil), do: services
  defp filter_by_capabilities(services, required_capabilities) do
    Enum.filter(services, fn service ->
      Enum.all?(required_capabilities, &(&1 in service.capabilities))
    end)
  end
  
  defp filter_by_health(services, nil), do: services
  defp filter_by_health(services, health_check_fn) when is_function(health_check_fn) do
    Enum.filter(services, health_check_fn)
  end
  
  defp select_instance(instances, :random), do: Enum.random(instances)
  defp select_instance(instances, :round_robin) do
    # Simple round-robin (stateless version)
    index = rem(:erlang.system_time(:microsecond), length(instances))
    Enum.at(instances, index)
  end
  
  defp send_to_instance(instance, message) do
    GenServer.cast(instance.pid, message)
    :ok
  end
end
```

#### Week 7: Enhanced Core Services Integration
```elixir
# lib/foundation/config.ex (Enhanced)
defmodule Foundation.Config do
  # Keep all existing Foundation 1.x APIs unchanged
  
  @doc """
  Set a configuration value across the entire cluster with consensus.
  
  This is an optional enhanced API - the original APIs still work.
  """
  def set_cluster_wide(path, value, opts \\ []) do
    # Validate locally first
    case validate_config_change(path, value) do
      :ok ->
        consensus_result = request_cluster_consensus({:config_change, path, value}, opts)
        apply_consensus_result(consensus_result, path, value)
      
      error ->
        error
    end
  end
  
  defp request_cluster_consensus(proposal, opts) do
    timeout = Keyword.get(opts, :timeout, 5000)
    required_nodes = Keyword.get(opts, :quorum, :majority)
    
    # Use the control channel for high-priority consensus
    Foundation.Channels.broadcast(:control, {:consensus_request, proposal, Node.self()})
    
    # Collect responses (simplified version)
    collect_consensus_responses(proposal, required_nodes, timeout)
  end
  
  defp collect_consensus_responses(proposal, required_nodes, timeout) do
    # Implementation would collect responses from other nodes
    # For now, simplified version
    {:ok, :consensus_reached}
  end
  
  defp apply_consensus_result({:ok, :consensus_reached}, path, value) do
    # Apply the change locally and broadcast to cluster
    Foundation.Config.update(path, value)
    Foundation.Channels.broadcast(:config, {:config_updated, path, value})
    :ok
  end
end
```

## Why This Synthesis Approach is Superior

### 1. **No Lock-in**: Developers can always drop to the tool level
```elixir
# Start with the facade
Foundation.ProcessManager.start_singleton(MyWorker, [])

# Need advanced features? Drop to Horde directly
Horde.DynamicSupervisor.start_child(Foundation.DistributedSupervisor, complex_child_spec)

# Foundation never prevents direct tool access
```

### 2. **Gradual Learning Curve**: Three levels of sophistication
- **Mortal**: `cluster: true` just works
- **Apprentice**: `cluster: :kubernetes` is simple but powerful  
- **Wizard**: Full libcluster configuration available

### 3. **Ecosystem Alignment**: Leverages best-in-class tools
- **libcluster**: Battle-tested clustering with 20+ strategies
- **Horde**: CRDT-based distributed processes
- **Phoenix.PubSub**: Reliable distributed messaging
- **mdns_lite**: Zero-config local discovery

### 4. **Maintainability**: Foundation's responsibility is focused
- **Does**: Environment detection, configuration translation, tool orchestration
- **Doesn't**: Reimplement distributed systems primitives

### 5. **Migration Path**: Easy adoption
```elixir
# Existing libcluster users: Foundation detects and defers
# No change required

# New users: Start simple, grow complex
config :foundation, cluster: true  # Development
config :foundation, cluster: :kubernetes  # Production
```

## Integration with Your Projects

### ElixirScope: Distributed Debugging
```elixir
# ElixirScope uses Foundation's facades for common patterns
Foundation.ProcessManager.start_singleton(ElixirScope.TraceCoordinator, [])

# But drops to tool level for advanced features
Horde.Registry.register(Foundation.ProcessRegistry, {:trace_session, session_id}, trace_metadata)

# Uses application-layer channels for coordination
Foundation.Channels.broadcast(:control, {:start_trace, session_id, trace_config})
```

### DSPEx: Distributed AI Optimization
```elixir
# Use Foundation for worker distribution
workers = for _i <- 1..Foundation.Cluster.size() do
  Foundation.ProcessManager.start_singleton(DSPEx.Worker, [], name: {:worker, i})
end

# Use Horde directly for complex work distribution
Horde.Registry.dispatch(Foundation.ProcessRegistry, :optimization_workers, fn workers ->
  # Custom work distribution logic
end)
```

This synthesis approach gives us the best of both worlds: **ease of use without lock-in, power without complexity, and ecosystem alignment without reinvention**.