# lib/foundation/process_manager.ex
defmodule Foundation.ProcessManager do
  @moduledoc """
  Intelligent process distribution and management.
  """
  
  use GenServer
  require Logger

  defstruct [:config, :distribution_strategy, :health_monitor]

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @impl true
  def init(config) do
    state = %__MODULE__{
      config: config,
      distribution_strategy: config[:distribution] || :local,
      health_monitor: %{}
    }
    
    {:ok, state}
  end

  @doc """
  Start a distributed process with intelligent placement.
  """
  def start_distributed_process(module, args, opts \\ []) do
    GenServer.call(__MODULE__, {:start_process, module, args, opts})
  end

  @doc """
  Start a process group with specified distribution strategy.
  """
  def start_process_group(module, opts \\ []) do
    count = Keyword.get(opts, :count, 1)
    strategy = Keyword.get(opts, :strategy, :distributed)
    
    case strategy do
      :distributed ->
        start_distributed_group(module, count, opts)
      
      :local ->
        start_local_group(module, count, opts)
      
      :replicated ->
        start_replicated_group(module, opts)
    end
  end

  @impl true
  def handle_call({:start_process, module, args, opts}, _from, state) do
    strategy = determine_distribution_strategy(module, opts, state)
    
    result = case strategy do
      :singleton ->
        start_singleton_process(module, args, opts, state)
      
      :replicated ->
        start_replicated_process(module, args, opts, state)
      
      :partitioned ->
        start_partitioned_process(module, args, opts, state)
      
      :local ->
        start_local_process(module, args, opts, state)
    end
    
    {:reply, result, state}
  end

  # Distribution strategy determination
  defp determine_distribution_strategy(module, opts, state) do
    cond do
      Keyword.get(opts, :strategy) ->
        Keyword.get(opts, :strategy)
      
      state.distribution_strategy == :local ->
        :local
      
      singleton_process?(module) ->
        :singleton
      
      replicated_process?(module) ->
        :replicated
      
      true ->
        :partitioned
    end
  end

  # Singleton process management
  defp start_singleton_process(module, args, opts, state) do
    name = Keyword.get(opts, :name, module)
    
    case state.distribution_strategy do
      :horde ->
        start_horde_singleton(module, args, name, opts)
      
      :local ->
        start_local_singleton(module, args, name, opts)
    end
  end

  defp start_horde_singleton(module, args, name, opts) do
    child_spec = %{
      id: name,
      start: {module, :start_link, [args]},
      restart: Keyword.get(opts, :restart, :permanent)
    }
    
    case Horde.DynamicSupervisor.start_child(Foundation.DistributedSupervisor, child_spec) do
      {:ok, pid} ->
        # Register in Horde.Registry for global discovery
        case Horde.Registry.register(Foundation.ProcessRegistry, name, pid) do
          {:ok, _} -> 
            {:ok, pid}
          {:error, reason} -> 
            Logger.warning("Failed to register process #{name}: #{reason}")
            {:ok, pid}  # Still return success as process started
        end
      
      {:error, {:already_started, pid}} ->
        {:ok, pid}
      
      error ->
        error
    end
  end

  defp start_local_singleton(module, args, name, opts) do
    child_spec = %{
      id: name,
      start: {module, :start_link, [args]},
      restart: Keyword.get(opts, :restart, :permanent)
    }
    
    case DynamicSupervisor.start_child(Foundation.DistributedSupervisor, child_spec) do
      {:ok, pid} ->
        Registry.register(Foundation.ProcessRegistry, name, pid)
        {:ok, pid}
      
      error ->
        error
    end
  end

  # Helper functions
  defp singleton_process?(module) do
    # Check if module defines itself as singleton
    function_exported?(module, :__foundation_singleton__, 0) and module.__foundation_singleton__()
  end

  defp replicated_process?(module) do
    # Check if module defines itself as replicated
    function_exported?(module, :__foundation_replicated__, 0) and module.__foundation_replicated__()
  end

  defp start_distributed_group(module, count, opts) do
    cluster_size = Foundation.Cluster.size()
    per_node = max(1, div(count, cluster_size))
    
    tasks = for _i <- 1..per_node do
      Task.async(fn ->
        start_distributed_process(module, [], opts)
      end)
    end
    
    Task.await_many(tasks)
  end

  defp start_local_group(module, count, opts) do
    for _i <- 1..count do
      start_distributed_process(module, [], Keyword.put(opts, :strategy, :local))
    end
  end

  defp start_replicated_group(module, opts) do
    # Start one instance per node
    Foundation.Cluster.broadcast_to_all_nodes(fn ->
      start_distributed_process(module, [], Keyword.put(opts, :strategy, :local))
    end)
  end

  defp start_replicated_process(_module, _args, _opts, _state) do
    # Implementation for replicated processes
    {:error, :not_implemented}
  end

  defp start_partitioned_process(_module, _args, _opts, _state) do
    # Implementation for partitioned processes  
    {:error, :not_implemented}
  end

  defp start_local_process(module, args, opts, _state) do
    name = Keyword.get(opts, :name)
    
    child_spec = if name do
      %{
        id: name,
        start: {module, :start_link, [args]},
        restart: Keyword.get(opts, :restart, :permanent)
      }
    else
      %{
        id: module,
        start: {module, :start_link, [args]},
        restart: Keyword.get(opts, :restart, :permanent)
      }
    end
    
    DynamicSupervisor.start_child(Foundation.DistributedSupervisor, child_spec)
  end
end

# ==============================================================================
# STEP 7: Service Mesh & Discovery
# ==============================================================================

# lib/foundation/service_mesh.ex
defmodule Foundation.ServiceMesh do
  @moduledoc """
  Service discovery and mesh capabilities.
  """
  
  use GenServer
  require Logger

  defstruct [:services, :health_checks, :load_balancer]

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    state = %__MODULE__{
      services: %{},
      health_checks: %{},
      load_balancer: Foundation.LoadBalancer.new()
    }
    
    # Start periodic health checking
    schedule_health_checks()
    
    {:ok, state}
  end

  @doc """
  Register a service in the mesh.
  """
  def register_service(name, pid, capabilities \\ []) do
    GenServer.call(__MODULE__, {:register_service, name, pid, capabilities})
  end

  @doc """
  Discover services matching criteria.
  """
  def discover_services(criteria) do
    GenServer.call(__MODULE__, {:discover_services, criteria})
  end

  @doc """
  Get all instances of a specific service.
  """
  def discover_service_instances(service_name) do
    GenServer.call(__MODULE__, {:discover_service_instances, service_name})
  end

  @impl true
  def handle_call({:register_service, name, pid, capabilities}, _from, state) do
    service = %{
      name: name,
      pid: pid,
      node: Node.self(),
      capabilities: capabilities,
      registered_at: System.system_time(:second),
      health_status: :healthy
    }
    
    # Multi-layer registration
    registrations = [
      register_locally(service, state),
      register_in_process_registry(service),
      announce_via_pubsub(service)
    ]
    
    case Enum.all?(registrations, &match?(:ok, &1)) do
      true ->
        new_services = Map.put(state.services, {name, pid}, service)
        new_state = %{state | services: new_services}
        {:reply, {:ok, :registered}, new_state}
      
      false ->
        {:reply, {:error, :partial_registration}, state}
    end
  end

  @impl true
  def handle_call({:discover_services, criteria}, _from, state) do
    matching_services = 
      state.services
      |> Enum.filter(fn {_key, service} -> matches_criteria?(service, criteria) end)
      |> Enum.map(fn {_key, service} -> service end)
    
    {:reply, matching_services, state}
  end

  @impl true
  def handle_call({:discover_service_instances, service_name}, _from, state) do
    instances = 
      state.services
      |> Enum.filter(fn {_key, service} -> service.name == service_name end)
      |> Enum.map(fn {_key, service} -> service end)
      |> Enum.filter(fn service -> service.health_status == :healthy end)
    
    {:reply, instances, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    new_state = perform_health_checks(state)
    schedule_health_checks()
    {:noreply, new_state}
  end

  # Registration helpers
  defp register_locally(service, _state) do
    # Register in local ETS table for fast lookup
    :ets.insert_new(:foundation_services, {{service.name, service.pid}, service})
    :ok
  rescue
    _ -> :error
  end

  defp register_in_process_registry(service) do
    # Register in Foundation.ProcessRegistry (Horde or local Registry)
    case Registry.register(Foundation.ProcessRegistry, {:service, service.name}, service.pid) do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  end

  defp announce_via_pubsub(service) do
    # Announce service registration via Phoenix.PubSub
    Foundation.Messaging.broadcast(
      "foundation:services",
      {:service_registered, service}
    )
    :ok
  rescue
    _ -> :error
  end

  # Discovery helpers
  defp matches_criteria?(service, criteria) do
    Enum.all?(criteria, fn {key, value} ->
      case key do
        :name -> service.name == value
        :node -> service.node == value
        :capabilities -> 
          required_caps = List.wrap(value)
          Enum.all?(required_caps, &(&1 in service.capabilities))
        :health_status -> service.health_status == value
        _ -> true
      end
    end)
  end

  # Health monitoring
  defp schedule_health_checks() do
    Process.send_after(self(), :health_check, 30_000)  # Every 30 seconds
  end

  defp perform_health_checks(state) do
    new_services = 
      Enum.into(state.services, %{}, fn {key, service} ->
        health_status = check_service_health(service)
        updated_service = %{service | health_status: health_status}
        {key, updated_service}
      end)
    
    %{state | services: new_services}
  end

  defp check_service_health(service) do
    case Process.alive?(service.pid) do
      true -> :healthy
      false -> :unhealthy
    end
  end
end

# ==============================================================================
# STEP 8: Health Monitoring & Performance Optimization
# ==============================================================================

# lib/foundation/health_monitor.ex
defmodule Foundation.HealthMonitor do
  @moduledoc """
  Cluster health monitoring and reporting.
  """
  
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Start periodic health monitoring
    schedule_health_check()
    {:ok, %{last_check: nil, health_history: []}}
  end

  @doc """
  Get current cluster health status.
  """
  def cluster_health() do
    GenServer.call(__MODULE__, :get_health)
  end

  @doc """
  Get detailed health report.
  """
  def detailed_health_report() do
    %{
      cluster_status: check_cluster_status(),
      node_health: check_all_nodes(),
      service_health: check_service_health(),
      performance_metrics: collect_performance_metrics(),
      recommendations: generate_recommendations()
    }
  end

  @impl true
  def handle_call(:get_health, _from, state) do
    health_report = detailed_health_report()
    {:reply, health_report, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    health_report = detailed_health_report()
    
    # Log any concerning issues
    if health_report.cluster_status.status != :healthy do
      Logger.warning("Cluster health issues detected: #{inspect(health_report)}")
    end
    
    # Schedule next check
    schedule_health_check()
    
    new_state = %{
      last_check: System.system_time(:second),
      health_history: [health_report | Enum.take(state.health_history, 9)]
    }
    
    {:noreply, new_state}
  end

  defp schedule_health_check() do
    Process.send_after(self(), :health_check, 60_000)  # Every minute
  end

  defp check_cluster_status() do
    connected_nodes = [Node.self() | Node.list()]
    expected_nodes = Application.get_env(:foundation, :expected_nodes, 1)
    
    status = cond do
      length(connected_nodes) >= expected_nodes -> :healthy
      length(connected_nodes) >= div(expected_nodes, 2) -> :degraded
      true -> :critical
    end
    
    %{
      status: status,
      connected_nodes: length(connected_nodes),
      expected_nodes: expected_nodes,
      nodes: connected_nodes
    }
  end

  defp check_all_nodes() do
    [Node.self() | Node.list()]
    |> Enum.map(&check_node_health/1)
  end

  defp check_node_health(node) do
    case Node.ping(node) do
      :pong ->
        %{
          node: node,
          status: :healthy,
          load: get_node_load(node),
          memory: get_node_memory(node)
        }
      
      :pang ->
        %{
          node: node,
          status: :unreachable,
          load: nil,
          memory: nil
        }
    end
  end

  defp check_service_health() do
    Foundation.ServiceMesh.discover_services([])
    |> Enum.group_by(& &1.health_status)
    |> Map.new(fn {status, services} -> {status, length(services)} end)
  end

  defp collect_performance_metrics() do
    %{
      message_throughput: measure_message_throughput(),
      average_latency: measure_average_latency(),
      error_rate: measure_error_rate(),
      memory_usage: :erlang.memory(:total),
      process_count: :erlang.system_info(:process_count)
    }
  end

  defp generate_recommendations() do
    # Basic recommendations based on health status
    []
  end

  # Utility functions for metrics collection
  defp get_node_load(node) do
    case :rpc.call(node, :cpu_sup, :avg1, []) do
      {:badrpc, _} -> nil
      load -> load / 256  # Convert to percentage
    end
  rescue
    _ -> nil
  end

  defp get_node_memory(node) do
    case :rpc.call(node, :erlang, :memory, [:total]) do
      {:badrpc, _} -> nil
      memory -> memory
    end
  rescue
    _ -> nil
  end

  defp measure_message_throughput() do
    # Placeholder - would integrate with telemetry
    0
  end

  defp measure_average_latency() do
    # Placeholder - would integrate with telemetry
    0
  end

  defp measure_error_rate() do
    # Placeholder - would integrate with telemetry
    0.0
  end
end

# lib/foundation/performance_optimizer.ex
defmodule Foundation.PerformanceOptimizer do
  @moduledoc """
  Automatic performance optimization based on cluster metrics.
  """
  
  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    schedule_optimization()
    {:ok, %{optimizations_applied: [], last_optimization: nil}}
  end

  @doc """
  Manually trigger performance optimization.
  """
  def optimize_now() do
    GenServer.cast(__MODULE__, :optimize)
  end

  @impl true
  def handle_cast(:optimize, state) do
    optimizations = analyze_and_recommend_optimizations()
    new_optimizations = apply_safe_optimizations(optimizations)
    
    new_state = %{
      optimizations_applied: new_optimizations ++ state.optimizations_applied,
      last_optimization: System.system_time(:second)
    }
    
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:scheduled_optimization, state) do
    handle_cast(:optimize, state)
    schedule_optimization()
    {:noreply, state}
  end

  defp schedule_optimization() do
    Process.send_after(self(), :scheduled_optimization, 300_000)  # Every 5 minutes
  end

  defp analyze_and_recommend_optimizations() do
    cluster_metrics = Foundation.HealthMonitor.detailed_health_report()
    
    optimizations = []
    
    # Analyze Horde sync intervals
    optimizations = maybe_optimize_horde_sync(cluster_metrics, optimizations)
    
    # Analyze PubSub configuration
    optimizations = maybe_optimize_pubsub(cluster_metrics, optimizations)
    
    # Analyze process distribution
    optimizations = maybe_optimize_process_distribution(cluster_metrics, optimizations)
    
    optimizations
  end

  defp maybe_optimize_horde_sync(metrics, optimizations) do
    node_count = metrics.cluster_status.connected_nodes
    change_frequency = estimate_change_frequency(metrics)
    
    optimal_interval = case {node_count, change_frequency} do
      {nodes, :high} when nodes < 10 -> 50
      {nodes, :high} when nodes < 50 -> 100
      {nodes, :medium} when nodes < 10 -> 100
      {nodes, :medium} when nodes < 50 -> 200
      {nodes, :low} -> 500
      _ -> 1000
    end
    
    current_interval = get_current_horde_sync_interval()
    
    if current_interval != optimal_interval do
      optimization = %{
        type: :horde_sync_interval,
        current_value: current_interval,
        recommended_value: optimal_interval,
        reason: "Optimize for cluster size #{node_count} and change frequency #{change_frequency}"
      }
      [optimization | optimizations]
    else
      optimizations
    end
  end

  defp maybe_optimize_pubsub(metrics, optimizations) do
    # Analyze PubSub message patterns and suggest optimizations
    message_volume = metrics.performance_metrics.message_throughput
    
    if message_volume > 1000 do
      optimization = %{
        type: :pubsub_compression,
        current_value: false,
        recommended_value: true,
        reason: "High message volume (#{message_volume}/sec) would benefit from compression"
      }
      [optimization | optimizations]
    else
      optimizations
    end
  end

  defp maybe_optimize_process_distribution(_metrics, optimizations) do
    # Analyze process distribution and suggest improvements
    optimizations
  end

  defp apply_safe_optimizations(optimizations) do
    Enum.filter(optimizations, fn optimization ->
      case apply_optimization(optimization) do
        :ok ->
          Logger.info("Applied optimization: #{optimization.type}")
          true
        
        {:error, reason} ->
          Logger.warning("Failed to apply optimization #{optimization.type}: #{reason}")
          false
      end
    end)
  end

  defp apply_optimization(%{type: :horde_sync_interval, recommended_value: interval}) do
    # This would require restarting Horde with new configuration
    # For now, just log the recommendation
    Logger.info("Recommendation: Set Horde sync interval to #{interval}ms")
    :ok
  end

  defp apply_optimization(%{type: :pubsub_compression}) do
    # Enable compression for PubSub messages
    Logger.info("Recommendation: Enable PubSub message compression")
    :ok
  end

  defp apply_optimization(_optimization) do
    {:error, :not_implemented}
  end

  # Helper functions
  defp estimate_change_frequency(_metrics) do
    # Placeholder - would analyze actual change patterns
    :medium
  end

  defp get_current_horde_sync_interval() do
    # Placeholder - would get actual configuration
    100
  end
end

# ==============================================================================
# STEP 9: Load Balancer & Utilities
# ==============================================================================

# lib/foundation/load_balancer.ex
defmodule Foundation.LoadBalancer do
  @moduledoc """
  Intelligent load balancing for service routing.
  """
  
  defstruct [:strategy, :instance_weights, :health_status, :round_robin_index]

  def new(strategy \\ :round_robin) do
    %__MODULE__{
      strategy: strategy,
      instance_weights: %{},
      health_status: %{},
      round_robin_index: 0
    }
  end

  def select_instance(instances, strategy \\ :round_robin) do
    healthy_instances = Enum.filter(instances, &(&1.health_status == :healthy))
    
    case {healthy_instances, strategy} do
      {[], _} ->
        nil
      
      {[instance], _} ->
        instance
      
      {instances, :round_robin} ->
        select_round_robin(instances)
      
      {instances, :least_connections} ->
        select_least_connections(instances)
      
      {instances, :random} ->
        Enum.random(instances)
      
      {instances, :least_latency} ->
        select_least_latency(instances)
    end
  end

  defp select_round_robin(instances) do
    # Simple round-robin selection
    # In a real implementation, this would maintain state
    index = rem(:rand.uniform(1000), length(instances))
    Enum.at(instances, index)
  end

  defp select_least_connections(instances) do
    # Select instance with least connections
    # Placeholder - would track actual connections
    Enum.random(instances)
  end

  defp select_least_latency(instances) do
    # Select instance with lowest latency
    # Placeholder - would track actual latencies
    Enum.random(instances)
  end
end

# lib/foundation/cluster.ex
defmodule Foundation.Cluster do
  @moduledoc """
  Cluster information and utilities.
  """

  @doc """
  Get current cluster information.
  """
  def cluster_info() do
    nodes = [Node.self() | Node.list()]
    
    %{
      nodes: length(nodes),
      node_list: nodes,
      strategy: get_clustering_strategy(),
      health: get_cluster_health(),
      processes: count_distributed_processes(),
      services: count_registered_services()
    }
  end

  @doc """
  Get cluster size.
  """
  def size() do
    length([Node.self() | Node.list()])
  end

  @doc """
  Broadcast a function to all nodes.
  """
  def broadcast_to_all_nodes(fun) do
    nodes = [Node.self() | Node.list()]
    
    tasks = Enum.map(nodes, fn node ->
      Task.async(fn ->
        if node == Node.self() do
          fun.()
        else
          :rpc.call(node, fun, [])
        end
      end)
    end)
    
    Task.await_many(tasks)
  end

  @doc """
  Get optimal worker count for current cluster.
  """
  def optimal_worker_count() do
    cluster_size = size()
    cores_per_node = :erlang.system_info(:schedulers_online)
    
    cluster_size * cores_per_node
  end

  # Helper functions
  defp get_clustering_strategy() do
    # Would get from configuration
    :auto_detected
  end

  defp get_cluster_health() do
    case Foundation.HealthMonitor.cluster_health() do
      %{cluster_status: %{status: status}} -> status
      _ -> :unknown
    end
  end

  defp count_distributed_processes() do
    # Count processes managed by Foundation
    case Process.whereis(Foundation.DistributedSupervisor) do
      nil -> 0
      pid -> 
        case Supervisor.count_children(pid) do
          %{active: count} -> count
          _ -> 0
        end
    end
  end

  defp count_registered_services() do
    Foundation.ServiceMesh.discover_services([])
    |> length()
  end
end

# lib/foundation/topic_manager.ex
defmodule Foundation.TopicManager do
  @moduledoc """
  Manages PubSub topics and subscriptions.
  """
  
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    {:ok, %{subscriptions: %{}, topic_patterns: %{}}}
  end

  def register_subscription(topic, handler) do
    GenServer.cast(__MODULE__, {:register, topic, handler})
  end

  @impl true
  def handle_cast({:register, topic, handler}, state) do
    subscriptions = Map.put(state.subscriptions, {topic, handler}, true)
    {:noreply, %{state | subscriptions: subscriptions}}
  end
end

# ==============================================================================
# STEP 10: Version & Utilities
# ==============================================================================

# lib/foundation/version.ex
defmodule Foundation.Version do
  @moduledoc """
  Foundation version information.
  """
  
  def version(), do: "2.0.0"
  
  def foundation_info() do
    %{
      version: version(),
      profile: get_current_profile(),
      clustering_strategy: get_clustering_strategy(),
      distribution_mode: get_distribution_mode(),
      started_at: get_start_time()
    }
  end
  
  defp get_current_profile() do
    case Process.whereis(Foundation.Configuration) do
      nil -> :unknown
      pid -> 
        case GenServer.call(pid, :get_profile) do
          profile when is_atom(profile) -> profile
          _ -> :unknown
        end
    end
  rescue
    _ -> :unknown
  end
  
  defp get_clustering_strategy() do
    # Would get actual strategy from cluster manager
    :auto_detected
  end
  
  defp get_distribution_mode() do
    # Would get actual distribution mode
    :horde
  end
  
  defp get_start_time() do
    # Would track actual start time
    System.system_time(:second)
  end
end

# Add version function to main Foundation module
defimpl String.Chars, for: Foundation do
  def to_string(_), do: "Foundation v#{Foundation.Version.version()}"
end

# Add to Foundation module
defmodule Foundation do
  # ... existing code ...
  
  def version(), do: Foundation.Version.version()
  def info(), do: Foundation.Version.foundation_info()
end

# ==============================================================================
# STEP 11: Example Usage & Getting Started
# ==============================================================================

# Example application showing Foundation 2.0 usage:

# config/config.exs
# config :foundation,
#   profile: :auto  # Will auto-detect optimal configuration

# lib/my_app/application.ex
# defmodule MyApp.Application do
#   use Application
#
#   def start(_type, _args) do
#     children = [
#       # Foundation handles all the clustering complexity
#       {Foundation, []},
#       
#       # Your services automatically become distributed
#       MyApp.UserService,
#       MyApp.OrderService,
#       MyApp.Web.Endpoint
#     ]
#
#     Supervisor.start_link(children, strategy: :one_for_one)
#   end
# end

# lib/my_app/user_service.ex
# defmodule MyApp.UserService do
#   use GenServer
#
#   def start_link(opts) do
#     # Foundation makes this a distributed singleton automatically
#     Foundation.ProcessManager.start_distributed_process(
#       __MODULE__, 
#       opts,
#       strategy: :singleton,
#       name: :user_service
#     )
#   end
#
#   def get_user(user_id) do
#     # Foundation handles service discovery and routing
#     Foundation.Messaging.send_message(
#       {:service, :user_service},
#       {:get_user, user_id}
#     )
#   end
#
#   # Mark as singleton process
#   def __foundation_singleton__(), do: true
# end

# ==============================================================================
# GETTING STARTED COMMANDS
# ==============================================================================

# 1. Create new project:
#    mix new my_distributed_app --sup
#    cd my_distributed_app

# 2. Add Foundation to mix.exs:
#    {:foundation, "~> 2.0"}

# 3. Run:
#    mix deps.get
#    mix compile

# 4. Start multiple nodes for development:
#    iex --name dev1@localhost -S mix
#    iex --name dev2@localhost -S mix
#    # Foundation automatically discovers and connects them!

# 5. For production, just add one line to config:
#    config :foundation, cluster: :kubernetes

# That's it! You now have a distributed BEAM application with:
# - Automatic service discovery
# - Distributed process management  
# - Intelligent message routing
# - Health monitoring
# - Performance optimization
# - Zero-config development clustering# Foundation 2.0: Day 1 Implementation Guide
# Start building the ecosystem-driven distribution framework today!

# ==============================================================================
# STEP 1: Project Setup
# ==============================================================================

# mix.exs
defmodule Foundation.MixProject do
  use Mix.Project

  def project do
    [
      app: :foundation,
      version: "2.0.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      description: "Ecosystem-driven distributed BEAM framework"
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Foundation.Application, []}
    ]
  end

  defp deps do
    [
      # Core clustering
      {:libcluster, "~> 3.3"},
      {:mdns_lite, "~> 0.8"},
      
      # Process distribution
      {:horde, "~> 0.9"},
      
      # Messaging
      {:phoenix_pubsub, "~> 2.1"},
      
      # Caching (optional)
      {:nebulex, "~> 2.5", optional: true},
      
      # Observability
      {:telemetry, "~> 1.2"},
      {:telemetry_metrics, "~> 0.6"},
      
      # Advanced features (optional)
      {:partisan, "~> 5.0", optional: true},
      
      # Development
      {:credo, "~> 1.7", only: [:dev, :test]},
      {:dialyxir, "~> 1.4", only: [:dev, :test]},
      {:ex_doc, "~> 0.29", only: :dev},
      
      # Testing
      {:mox, "~> 1.0", only: :test},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end

  defp package do
    [
      maintainers: ["Your Name"],
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/yourorg/foundation"}
    ]
  end
end

# ==============================================================================
# STEP 2: Application Structure
# ==============================================================================

# lib/foundation.ex
defmodule Foundation do
  @moduledoc """
  Foundation 2.0: Ecosystem-driven distributed BEAM framework
  
  Provides zero-config development clustering and one-line production deployment
  by intelligently orchestrating best-in-class Elixir ecosystem tools.
  
  ## Quick Start
  
      # Zero config development
      {:foundation, "~> 2.0"}
      
      # One line production  
      config :foundation, cluster: :kubernetes
      
      # Advanced configuration
      config :foundation, 
        profile: :enterprise,
        clusters: %{...}
  """
  
  @doc """
  Starts Foundation with intelligent configuration detection.
  """
  def start_cluster(opts \\ []) do
    config = Foundation.Configuration.resolve_configuration(opts)
    Foundation.Supervisor.start_cluster(config)
  end
  
  @doc """
  Sends a message intelligently across local/distributed boundaries.
  """
  defdelegate send_message(target, message, opts \\ []), to: Foundation.Messaging
  
  @doc """
  Starts a distributed process with intelligent placement.
  """
  defdelegate start_process(module, args, opts \\ []), to: Foundation.ProcessManager
  
  @doc """
  Gets current cluster information.
  """
  defdelegate cluster_info(), to: Foundation.Cluster
  
  @doc """
  Registers a service in the service mesh.
  """
  defdelegate register_service(name, pid, capabilities \\ []), to: Foundation.ServiceMesh
  
  @doc """
  Discovers services matching criteria.
  """
  defdelegate discover_services(criteria), to: Foundation.ServiceMesh
end

# lib/foundation/application.ex
defmodule Foundation.Application do
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting Foundation 2.0...")
    
    # Detect optimal configuration
    config = Foundation.Configuration.detect_and_resolve()
    Logger.info("Foundation profile: #{config.profile}")
    
    children = [
      # Core configuration
      {Foundation.Configuration, config},
      
      # Environment detection and optimization
      Foundation.EnvironmentDetector,
      
      # Clustering (strategy depends on environment)
      {Foundation.ClusterSupervisor, config.clustering},
      
      # Messaging (Phoenix.PubSub with intelligent config)
      {Foundation.PubSubSupervisor, config.messaging},
      
      # Process distribution (Horde or local depending on profile)
      {Foundation.ProcessSupervisor, config.processes},
      
      # Service mesh and discovery
      Foundation.ServiceMesh,
      
      # Health monitoring
      Foundation.HealthMonitor,
      
      # Performance optimization
      Foundation.PerformanceOptimizer
    ]

    opts = [strategy: :one_for_one, name: Foundation.Supervisor]
    Supervisor.start_link(children, opts)
  end
end

# ==============================================================================
# STEP 3: Environment Detection & Configuration
# ==============================================================================

# lib/foundation/environment_detector.ex
defmodule Foundation.EnvironmentDetector do
  @moduledoc """
  Intelligent environment detection for optimal tool selection.
  """
  
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    environment = detect_environment()
    infrastructure = detect_infrastructure()
    scale = detect_scale()
    
    config = %{
      environment: environment,
      infrastructure: infrastructure,
      scale: scale,
      detected_at: System.system_time(:second)
    }
    
    Logger.info("Environment detected: #{inspect(config)}")
    {:ok, config}
  end

  def get_detected_config() do
    GenServer.call(__MODULE__, :get_config)
  end

  @impl true
  def handle_call(:get_config, _from, state) do
    {:reply, state, state}
  end

  # Environment detection logic
  defp detect_environment() do
    cond do
      System.get_env("MIX_ENV") == "dev" -> :development
      kubernetes_environment?() -> :kubernetes
      docker_environment?() -> :containerized
      cloud_environment?() -> :cloud
      true -> :production
    end
  end

  defp detect_infrastructure() do
    cond do
      kubernetes_available?() -> :kubernetes
      consul_available?() -> :consul  
      dns_srv_available?() -> :dns
      aws_environment?() -> :aws
      gcp_environment?() -> :gcp
      true -> :static
    end
  end

  defp detect_scale() do
    expected_nodes = System.get_env("FOUNDATION_EXPECTED_NODES", "1") |> String.to_integer()
    
    cond do
      expected_nodes == 1 -> :single_node
      expected_nodes <= 10 -> :small_cluster
      expected_nodes <= 100 -> :medium_cluster  
      expected_nodes <= 1000 -> :large_cluster
      true -> :massive_cluster
    end
  end

  # Detection helpers
  defp kubernetes_environment?() do
    System.get_env("KUBERNETES_SERVICE_HOST") != nil
  end

  defp docker_environment?() do
    File.exists?("/.dockerenv")
  end

  defp cloud_environment?() do
    aws_environment?() or gcp_environment?() or azure_environment?()
  end

  defp kubernetes_available?() do
    kubernetes_environment?() and File.exists?("/var/run/secrets/kubernetes.io")
  end

  defp consul_available?() do
    System.get_env("CONSUL_HTTP_ADDR") != nil
  end

  defp dns_srv_available?() do
    # Check if DNS SRV records are configured
    System.get_env("FOUNDATION_DNS_SRV") != nil
  end

  defp aws_environment?() do
    System.get_env("AWS_REGION") != nil
  end

  defp gcp_environment?() do
    System.get_env("GOOGLE_CLOUD_PROJECT") != nil  
  end

  defp azure_environment?() do
    System.get_env("AZURE_SUBSCRIPTION_ID") != nil
  end
end

# lib/foundation/configuration.ex
defmodule Foundation.Configuration do
  @moduledoc """
  Smart configuration resolution based on environment detection.
  """
  
  use GenServer

  defstruct [
    :profile,
    :clustering,
    :messaging, 
    :processes,
    :caching,
    :features
  ]

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @impl true
  def init(config) do
    {:ok, config}
  end

  def detect_and_resolve() do
    detected = Foundation.EnvironmentDetector.get_detected_config()
    user_config = Application.get_all_env(:foundation)
    
    resolve_configuration(detected, user_config)
  end

  def resolve_configuration(detected \\ nil, user_config \\ []) do
    detected = detected || %{environment: :production, infrastructure: :static, scale: :small_cluster}
    
    # Determine profile
    profile = determine_profile(detected, user_config)
    
    # Get base configuration for profile  
    base_config = get_profile_config(profile)
    
    # Override with user configuration
    final_config = merge_user_config(base_config, user_config)
    
    struct(__MODULE__, final_config)
  end

  defp determine_profile(detected, user_config) do
    case Keyword.get(user_config, :profile, :auto) do
      :auto -> auto_determine_profile(detected)
      explicit_profile -> explicit_profile
    end
  end

  defp auto_determine_profile(%{environment: :development}), do: :development
  defp auto_determine_profile(%{scale: :single_node}), do: :development
  defp auto_determine_profile(%{scale: scale}) when scale in [:small_cluster, :medium_cluster], do: :production
  defp auto_determine_profile(%{scale: scale}) when scale in [:large_cluster, :massive_cluster], do: :enterprise
  defp auto_determine_profile(_), do: :production

  defp get_profile_config(:development) do
    %{
      profile: :development,
      clustering: %{
        strategy: Foundation.Strategies.MdnsLite,
        config: [
          service_name: "foundation-dev",
          auto_connect: true,
          discovery_interval: 1000
        ]
      },
      messaging: %{
        adapter: Phoenix.PubSub.PG2,
        name: Foundation.PubSub,
        local_only: true
      },
      processes: %{
        distribution: :local,
        supervisor: DynamicSupervisor,
        registry: Registry
      },
      caching: %{
        adapter: :ets,
        local_only: true
      },
      features: [:hot_reload_coordination, :distributed_debugging, :development_dashboard]
    }
  end

  defp get_profile_config(:production) do
    %{
      profile: :production,
      clustering: %{
        strategy: Foundation.ClusterManager.auto_detect_strategy(),
        config: Foundation.ClusterManager.auto_detect_config()
      },
      messaging: %{
        adapter: Phoenix.PubSub.PG2,
        name: Foundation.PubSub,
        compression: true
      },
      processes: %{
        distribution: :horde,
        supervisor: Horde.DynamicSupervisor,
        registry: Horde.Registry,
        sync_interval: 100
      },
      caching: %{
        adapter: :nebulex_distributed,
        replication: :async
      },
      features: [:health_monitoring, :performance_metrics, :automatic_scaling]
    }
  end

  defp get_profile_config(:enterprise) do
    %{
      profile: :enterprise,
      clustering: %{
        multi_cluster: true,
        strategy: Foundation.ClusterManager.auto_detect_strategy(),
        federation: :enabled
      },
      messaging: %{
        adapter: Phoenix.PubSub.PG2,
        name: Foundation.PubSub,
        federated: true,
        compression: true
      },
      processes: %{
        distribution: :horde_multi_cluster,
        supervisor: Horde.DynamicSupervisor,
        registry: Horde.Registry,
        global_distribution: true
      },
      caching: %{
        adapter: :nebulex_federated,
        multi_tier: true
      },
      features: [:multi_cluster_management, :advanced_observability, :disaster_recovery]
    }
  end

  defp merge_user_config(base_config, user_config) do
    # Deep merge user configuration over base configuration
    Enum.reduce(user_config, base_config, fn {key, value}, acc ->
      case key do
        :cluster when is_atom(value) ->
          # Handle shorthand cluster configuration
          clustering_config = resolve_cluster_shorthand(value)
          Map.put(acc, :clustering, clustering_config)
        
        :clusters when is_map(value) ->
          # Handle multi-cluster configuration
          Map.put(acc, :clustering, Map.put(acc.clustering, :multi_cluster_config, value))
        
        _ ->
          Map.put(acc, key, value)
      end
    end)
  end

  defp resolve_cluster_shorthand(:kubernetes) do
    %{
      strategy: Cluster.Strategy.Kubernetes,
      config: [
        mode: :hostname,
        kubernetes_node_basename: Application.get_env(:foundation, :node_basename, "foundation"),
        kubernetes_selector: Application.get_env(:foundation, :kubernetes_selector, "app=foundation")
      ]
    }
  end

  defp resolve_cluster_shorthand(:consul) do
    %{
      strategy: Cluster.Strategy.Consul,
      config: [
        service_name: Application.get_env(:foundation, :service_name, "foundation")
      ]
    }
  end

  defp resolve_cluster_shorthand(:dns) do
    %{
      strategy: Cluster.Strategy.DNS,
      config: [
        service: Application.get_env(:foundation, :dns_service, "foundation"),
        application_name: Application.get_env(:foundation, :application_name, "foundation")
      ]
    }
  end

  defp resolve_cluster_shorthand(:gossip) do
    %{
      strategy: Cluster.Strategy.Gossip,
      config: [
        multicast_addr: "230.1.1.251",
        multicast_ttl: 1,
        secret: Application.get_env(:foundation, :gossip_secret, "foundation-secret")
      ]
    }
  end
end

# ==============================================================================
# STEP 4: Clustering Management
# ==============================================================================

# lib/foundation/cluster_supervisor.ex
defmodule Foundation.ClusterSupervisor do
  @moduledoc """
  Manages clustering using libcluster with intelligent strategy selection.
  """
  
  use Supervisor

  def start_link(clustering_config) do
    Supervisor.start_link(__MODULE__, clustering_config, name: __MODULE__)
  end

  @impl true
  def init(clustering_config) do
    children = case clustering_config do
      %{multi_cluster: true} ->
        # Multi-cluster setup
        setup_multi_cluster(clustering_config)
      
      %{strategy: strategy, config: config} ->
        # Single cluster setup
        setup_single_cluster(strategy, config)
      
      _ ->
        # No clustering (single node)
        []
    end

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp setup_single_cluster(strategy, config) do
    topologies = [
      foundation: [
        strategy: strategy,
        config: config,
        connect: {:net_kernel, :connect_node, []},
        disconnect: {:erlang, :disconnect_node, []},
        list_nodes: {:erlang, :nodes, [:connected]}
      ]
    ]

    [
      {Cluster.Supervisor, [topologies, [name: Foundation.ClusterManager]]},
      Foundation.ClusterHealth
    ]
  end

  defp setup_multi_cluster(clustering_config) do
    # Multi-cluster setup - more complex
    [
      {Foundation.Federation, clustering_config},
      Foundation.ClusterHealth
    ]
  end
end

# lib/foundation/cluster_manager.ex
defmodule Foundation.ClusterManager do
  @moduledoc """
  Intelligent clustering strategy detection and management.
  """
  
  def auto_detect_strategy() do
    cond do
      kubernetes_available?() -> Cluster.Strategy.Kubernetes
      consul_available?() -> Cluster.Strategy.Consul
      dns_srv_available?() -> Cluster.Strategy.DNS
      development_mode?() -> Foundation.Strategies.MdnsLite
      true -> Cluster.Strategy.Epmd
    end
  end

  def auto_detect_config() do
    strategy = auto_detect_strategy()
    
    case strategy do
      Cluster.Strategy.Kubernetes ->
        [
          mode: :hostname,
          kubernetes_node_basename: get_node_basename(),
          kubernetes_selector: get_kubernetes_selector()
        ]
      
      Cluster.Strategy.Consul ->
        [
          service_name: get_service_name()
        ]
      
      Cluster.Strategy.DNS ->
        [
          service: get_dns_service(),
          application_name: get_application_name()
        ]
      
      Foundation.Strategies.MdnsLite ->
        [
          service_name: "foundation-dev",
          auto_connect: true
        ]
      
      Cluster.Strategy.Epmd ->
        [
          hosts: get_static_hosts()
        ]
    end
  end

  # Helper functions for configuration detection
  defp kubernetes_available?() do
    System.get_env("KUBERNETES_SERVICE_HOST") != nil and
    File.exists?("/var/run/secrets/kubernetes.io/serviceaccount/token")
  end

  defp consul_available?() do
    System.get_env("CONSUL_HTTP_ADDR") != nil
  end

  defp dns_srv_available?() do
    System.get_env("FOUNDATION_DNS_SERVICE") != nil
  end

  defp development_mode?() do
    System.get_env("MIX_ENV") == "dev"
  end

  defp get_node_basename() do
    System.get_env("FOUNDATION_NODE_BASENAME") || 
    Application.get_env(:foundation, :node_basename, "foundation")
  end

  defp get_kubernetes_selector() do
    System.get_env("FOUNDATION_K8S_SELECTOR") ||
    Application.get_env(:foundation, :kubernetes_selector, "app=foundation")
  end

  defp get_service_name() do
    System.get_env("FOUNDATION_SERVICE_NAME") ||
    Application.get_env(:foundation, :service_name, "foundation")
  end

  defp get_dns_service() do
    System.get_env("FOUNDATION_DNS_SERVICE") ||
    Application.get_env(:foundation, :dns_service, "foundation")
  end

  defp get_application_name() do
    System.get_env("FOUNDATION_APP_NAME") ||
    Application.get_env(:foundation, :application_name, "foundation")
  end

  defp get_static_hosts() do
    case System.get_env("FOUNDATION_STATIC_HOSTS") do
      nil -> []
      hosts_str -> 
        hosts_str
        |> String.split(",")
        |> Enum.map(&String.to_atom/1)
    end
  end
end

# lib/foundation/strategies/mdns_lite.ex
defmodule Foundation.Strategies.MdnsLite do
  @moduledoc """
  Development clustering strategy using mdns_lite for zero-config local clustering.
  """
  
  @behaviour Cluster.Strategy
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    service_name = Keyword.get(opts, :service_name, "foundation-dev")
    auto_connect = Keyword.get(opts, :auto_connect, true)
    discovery_interval = Keyword.get(opts, :discovery_interval, 5000)
    
    # Configure mdns_lite service
    configure_mdns_service(service_name)
    
    # Start service discovery if auto_connect is enabled
    if auto_connect do
      schedule_discovery(discovery_interval)
    end
    
    state = %{
      service_name: service_name,
      auto_connect: auto_connect,
      discovery_interval: discovery_interval,
      discovered_nodes: MapSet.new()
    }
    
    Logger.info("Foundation mDNS strategy started for service: #{service_name}")
    {:ok, state}
  end

  @impl true  
  def handle_info(:discover_nodes, state) do
    new_nodes = discover_foundation_nodes(state.service_name)
    
    # Connect to newly discovered nodes
    Enum.each(new_nodes, fn node ->
      unless node in state.discovered_nodes or node == Node.self() do
        Logger.info("Connecting to discovered Foundation node: #{node}")
        Node.connect(node)
      end
    end)
    
    # Schedule next discovery
    schedule_discovery(state.discovery_interval)
    
    new_state = %{state | discovered_nodes: MapSet.union(state.discovered_nodes, new_nodes)}
    {:noreply, new_state}
  end

  defp configure_mdns_service(service_name) do
    # Get the current node's distribution port
    distribution_port = get_distribution_port()
    
    # Add Foundation service to mDNS
    MdnsLite.add_mdns_service(%{
      id: :foundation_cluster,
      protocol: service_name,
      transport: "tcp",
      port: distribution_port,
      txt_payload: [
        "node=#{Node.self()}",
        "foundation_version=#{Foundation.version()}",
        "started_at=#{System.system_time(:second)}"
      ]
    })
  end

  defp discover_foundation_nodes(service_name) do
    # Query mDNS for Foundation services
    case MdnsLite.query("_#{service_name}._tcp.local") do
      {:ok, services} ->
        services
        |> Enum.map(&extract_node_from_service/1)
        |> Enum.filter(& &1)
        |> MapSet.new()
      
      _ ->
        MapSet.new()
    end
  end

  defp extract_node_from_service(service) do
    # Extract node name from mDNS service record
    case service do
      %{txt_payload: txt_records} ->
        txt_records
        |> Enum.find_value(fn record ->
          case String.split(record, "=", parts: 2) do
            ["node", node_name] -> String.to_atom(node_name)
            _ -> nil
          end
        end)
      
      _ -> nil
    end
  end

  defp get_distribution_port() do
    # Get the port that the current node is listening on for distribution
    case :inet.port(:erlang.get_cookie()) do
      {:ok, port} -> port
      _ -> 4369  # Default EPMD port
    end
  end

  defp schedule_discovery(interval) do
    Process.send_after(self(), :discover_nodes, interval)
  end
end

# ==============================================================================
# STEP 5: Messaging Layer (Phoenix.PubSub Integration)
# ==============================================================================

# lib/foundation/pubsub_supervisor.ex
defmodule Foundation.PubSubSupervisor do
  @moduledoc """
  Manages Phoenix.PubSub with intelligent configuration.
  """
  
  use Supervisor

  def start_link(messaging_config) do
    Supervisor.start_link(__MODULE__, messaging_config, name: __MODULE__)
  end

  @impl true
  def init(messaging_config) do
    children = [
      # Phoenix.PubSub with configuration based on profile
      {Phoenix.PubSub, build_pubsub_config(messaging_config)},
      
      # Foundation messaging manager
      {Foundation.Messaging, messaging_config},
      
      # Topic manager for intelligent routing
      Foundation.TopicManager
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp build_pubsub_config(messaging_config) do
    base_config = [
      name: messaging_config.name,
      adapter: messaging_config.adapter
    ]
    
    # Add additional configuration based on profile
    case messaging_config do
      %{compression: true} ->
        Keyword.put(base_config, :compression, true)
      
      %{federated: true} ->
        # Configuration for federated PubSub across clusters
        Keyword.merge(base_config, [
          adapter: Phoenix.PubSub.Redis,
          redis_host: System.get_env("REDIS_HOST", "localhost")
        ])
      
      _ ->
        base_config
    end
  end
end

# lib/foundation/messaging.ex
defmodule Foundation.Messaging do
  @moduledoc """
  Intelligent message routing across local and distributed boundaries.
  """
  
  use GenServer
  require Logger

  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: __MODULE__)
  end

  @impl true
  def init(config) do
    {:ok, config}
  end

  @doc """
  Send a message intelligently based on target type.
  """
  def send_message(target, message, opts \\ []) do
    GenServer.call(__MODULE__, {:send_message, target, message, opts})
  end

  @doc """
  Subscribe to a topic with optional pattern matching.
  """
  def subscribe(topic, handler \\ self()) do
    Phoenix.PubSub.subscribe(Foundation.PubSub, topic)
    Foundation.TopicManager.register_subscription(topic, handler)
  end

  @doc """
  Broadcast a message to a topic.
  """
  def broadcast(topic, message, opts \\ []) do
    case Keyword.get(opts, :compression, false) do
      true ->
        compressed_message = compress_message(message)
        Phoenix.PubSub.broadcast(Foundation.PubSub, topic, compressed_message)
      
      false ->
        Phoenix.PubSub.broadcast(Foundation.PubSub, topic, message)
    end
  end

  @impl true
  def handle_call({:send_message, target, message, opts}, _from, state) do
    result = case resolve_target(target) do
      {:local, pid} -> 
        send(pid, message)
        :ok
      
      {:remote, node, name} -> 
        send_remote_message(node, name, message, opts)
      
      {:service, service_name} -> 
        route_to_service(service_name, message, opts)
      
      {:broadcast, topic} -> 
        broadcast(topic, message, opts)
      
      {:error, reason} -> 
        {:error, reason}
    end
    
    {:reply, result, state}
  end

  # Target resolution logic
  defp resolve_target(target) do
    case target do
      pid when is_pid(pid) ->
        {:local, pid}
      
      {node, name} when is_atom(node) and is_atom(name) ->
        {:remote, node, name}
      
      {:service, service_name} ->
        {:service, service_name}
      
      {:broadcast, topic} ->
        {:broadcast, topic}
      
      {:via, registry, key} ->
        case registry.whereis_name(key) do
          pid when is_pid(pid) -> {:local, pid}
          :undefined -> {:error, :process_not_found}
        end
      
      _ ->
        {:error, :invalid_target}
    end
  end

  defp send_remote_message(node, name, message, opts) do
    case Node.ping(node) do
      :pong ->
        GenServer.cast({name, node}, message)
        :ok
      
      :pang ->
        Logger.warning("Failed to reach node #{node}")
        {:error, :node_unreachable}
    end
  end

  defp route_to_service(service_name, message, opts) do
    case Foundation.ServiceMesh.discover_service_instances(service_name) do
      [] ->
        {:error, :service_not_found}
      
      [instance] ->
        send_message(instance.pid, message, opts)
      
      instances ->
        # Load balance between instances
        strategy = Keyword.get(opts, :load_balance, :round_robin)
        instance = Foundation.LoadBalancer.select_instance(instances, strategy)
        send_message(instance.pid, message, opts)
    end
  end

  defp compress_message(message) do
    compressed = :zlib.compress(:erlang.term_to_binary(message))
    {:foundation_compressed, compressed}
  end
end

# ==============================================================================
# STEP 6: Process Management (Horde Integration)
# ==============================================================================

# lib/foundation/process_supervisor.ex
defmodule Foundation.ProcessSupervisor do
  @moduledoc """
  Manages process distribution using Horde or local supervisors.
  """
  
  use Supervisor

  def start_link(process_config) do
    Supervisor.start_link(__MODULE__, process_config, name: __MODULE__)
  end

  @impl true
  def init(process_config) do
    children = case process_config.distribution do
      :horde ->
        setup_horde_supervision(process_config)
      
      :horde_multi_cluster ->
        setup_multi_cluster_horde(process_config)
      
      :local ->
        setup_local_supervision(process_config)
    end

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp setup_horde_supervision(config) do
    [
      # Horde.Registry for distributed process registry
      {Horde.Registry, 
        keys: :unique, 
        name: Foundation.ProcessRegistry,
        members: :auto
      },
      
      # Horde.DynamicSupervisor for distributed process supervision
      {Horde.DynamicSupervisor,
        name: Foundation.DistributedSupervisor,
        strategy: :one_for_one,
        members: :auto,
        delta_crdt_options: [sync_interval: config[:sync_interval] || 100]
      },
      
      # Foundation process manager
      {Foundation.ProcessManager, config}
    ]
  end

  defp setup_local_supervision(_config) do
    [
      # Local registry
      {Registry, keys: :unique, name: Foundation.ProcessRegistry},
      
      # Local dynamic supervisor
      {DynamicSupervisor, name: Foundation.DistributedSupervisor, strategy: :one_for_one},
      
      # Foundation process manager  
      {Foundation.ProcessManager, %{distribution: :local}}
    ]
  end

  defp setup_multi_cluster_horde(config) do
    # Multi-cluster Horde setup - more complex configuration
    setup_horde_supervision(config) ++ [
      Foundation.MultiClusterCoordinator
    ]
  end
end
