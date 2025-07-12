# Foundation Clustering Architecture: Enterprise Jido Distribution
**Date**: 2025-07-11  
**Status**: Clustering Design  
**Scope**: Enterprise clustering architecture for Jido agents

## Executive Summary

Based on comprehensive analysis of Jido's capabilities, **Foundation's primary value proposition is enterprise clustering and distributed coordination**. Jido provides exceptional single-node agent capabilities, while Foundation transforms these into enterprise-grade distributed systems. This document outlines the architecture for clustering Jido agents across BEAM nodes with Foundation's infrastructure.

## Clustering Architecture Overview

### Core Principle: Foundation as Clustering Infrastructure

```
┌─────────────────────────────────────────────────────────────┐
│                  Foundation Cluster Layer                   │
│  Enterprise Infrastructure & Distributed Coordination      │
├─────────────────────────────────────────────────────────────┤
│  Node Discovery │ Load Balancing │ Fault Tolerance         │
│  Resource Mgmt  │ Monitoring     │ Security & Isolation    │
│  Consensus      │ Circuit Breaker│ Distributed Registry    │
└─────────────────────────────────────────────────────────────┘
                            ▲▼ Clustering Interface
┌─────────────────────────────────────────────────────────────┐
│                    Jido Agent Layer                         │
│  Sophisticated Agent Runtime & Execution                   │
├─────────────────────────────────────────────────────────────┤
│  Agent Lifecycle │ Action System │ Signal Routing          │
│  Skills & Sensors│ State Mgmt    │ Local Coordination      │
│  Tool Conversion │ Persistence   │ Process Supervision     │
└─────────────────────────────────────────────────────────────┘
```

## Foundation Clustering Services

### 1. Cluster Formation & Node Management

#### 1.1 Automatic Node Discovery
```elixir
defmodule Foundation.Clustering.Discovery do
  @moduledoc """
  Automatic BEAM cluster formation with health monitoring
  """
  
  use GenServer
  require Logger
  
  # Integration with libcluster for various discovery strategies
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    strategy = opts[:strategy] || :multicast
    
    cluster_config = [
      strategy: strategy,
      config: build_cluster_config(strategy, opts),
      connect: {__MODULE__, :on_connect, []},
      disconnect: {__MODULE__, :on_disconnect, []},
      list_nodes: {__MODULE__, :list_nodes, []}
    ]
    
    # Start libcluster with Foundation monitoring
    {:ok, _pid} = Cluster.start_link([cluster_config])
    
    state = %{
      strategy: strategy,
      connected_nodes: [Node.self()],
      node_metadata: %{Node.self() => collect_node_metadata()},
      last_health_check: DateTime.utc_now()
    }
    
    # Schedule regular health checks
    Process.send_after(self(), :health_check, 30_000)
    
    {:ok, state}
  end
  
  def on_connect(node) do
    Logger.info("Node connected to cluster: #{node}")
    
    # Exchange node metadata
    metadata = collect_node_metadata()
    :rpc.call(node, __MODULE__, :register_node_metadata, [Node.self(), metadata])
    
    # Notify cluster coordinator
    Foundation.Clustering.Coordinator.node_joined(node)
    
    # Emit telemetry
    :telemetry.execute(
      [:foundation, :clustering, :node_connected],
      %{node_count: length(Node.list()) + 1},
      %{node: node}
    )
  end
  
  def on_disconnect(node) do
    Logger.warning("Node disconnected from cluster: #{node}")
    
    # Trigger failover procedures
    Foundation.Clustering.Failover.handle_node_loss(node)
    
    # Emit telemetry
    :telemetry.execute(
      [:foundation, :clustering, :node_disconnected],
      %{node_count: length(Node.list()) + 1},
      %{node: node}
    )
  end
  
  defp collect_node_metadata do
    %{
      node: Node.self(),
      capabilities: Foundation.NodeCapabilities.get_capabilities(),
      resources: Foundation.ResourceMonitor.current_usage(),
      agent_count: Foundation.AgentRegistry.count_local_agents(),
      load_average: Foundation.SystemMetrics.load_average(),
      timestamp: DateTime.utc_now()
    }
  end
end
```

#### 1.2 Cluster Topology Management
```elixir
defmodule Foundation.Clustering.Topology do
  @moduledoc """
  Manages cluster topology and optimal agent placement
  """
  
  use GenServer
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def get_cluster_topology do
    GenServer.call(__MODULE__, :get_topology)
  end
  
  def select_optimal_node(agent_spec, strategy \\ :load_balanced) do
    GenServer.call(__MODULE__, {:select_node, agent_spec, strategy})
  end
  
  def handle_call(:get_topology, _from, state) do
    topology = %{
      nodes: get_node_details(),
      connections: get_connection_matrix(),
      partitions: detect_network_partitions(),
      leader: get_cluster_leader(),
      total_agents: count_cluster_agents()
    }
    
    {:reply, topology, state}
  end
  
  def handle_call({:select_node, agent_spec, strategy}, _from, state) do
    node = case strategy do
      :load_balanced -> select_least_loaded_node(agent_spec)
      :capability_matched -> select_capable_node(agent_spec)
      :leader_only -> get_cluster_leader()
      :random -> Enum.random(Node.list([:visible]) ++ [Node.self()])
      :local_preferred -> Node.self()
    end
    
    {:reply, {:ok, node}, state}
  end
  
  defp select_least_loaded_node(_agent_spec) do
    Node.list([:visible])
    |> Enum.map(fn node ->
      load = :rpc.call(node, Foundation.ResourceMonitor, :current_load, [])
      {node, load}
    end)
    |> Enum.min_by(fn {_node, load} -> load end, fn -> {Node.self(), 0.0} end)
    |> elem(0)
  end
  
  defp select_capable_node(agent_spec) do
    required_capabilities = agent_spec[:required_capabilities] || []
    
    Node.list([:visible])
    |> Enum.find(fn node ->
      capabilities = :rpc.call(node, Foundation.NodeCapabilities, :get_capabilities, [])
      Enum.all?(required_capabilities, &(&1 in capabilities))
    end) || Node.self()
  end
end
```

### 2. Distributed Agent Registry

#### 2.1 Cluster-Wide Agent Discovery
```elixir
defmodule Foundation.DistributedAgentRegistry do
  @moduledoc """
  Distributed registry for Jido agents across cluster nodes
  """
  
  use GenServer
  require Logger
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def register_agent(agent_id, pid, metadata \\ %{}) do
    node = Node.self()
    
    # Register locally
    Foundation.AgentRegistry.register_local(agent_id, pid, metadata)
    
    # Replicate across cluster with consensus
    agent_info = %{
      id: agent_id,
      pid: pid,
      node: node,
      metadata: Map.merge(metadata, %{
        registered_at: DateTime.utc_now(),
        capabilities: extract_agent_capabilities(pid)
      })
    }
    
    Foundation.Consensus.propose_update(:agent_registry, {:register, agent_id, agent_info})
  end
  
  def lookup_agent(agent_id) do
    case :ets.lookup(:distributed_agents, agent_id) do
      [{^agent_id, agent_info}] ->
        if agent_info.node == Node.self() do
          # Local agent
          {:ok, agent_info}
        else
          # Remote agent - verify it's still alive
          case :rpc.call(agent_info.node, Process, :alive?, [agent_info.pid]) do
            true -> {:ok, agent_info}
            false -> 
              # Clean up stale entry
              unregister_agent(agent_id)
              {:error, :not_found}
            {:badrpc, _} ->
              {:error, :node_unavailable}
          end
        end
        
      [] ->
        {:error, :not_found}
    end
  end
  
  def find_agents_by_capability(capability) do
    :ets.tab2list(:distributed_agents)
    |> Enum.filter(fn {_id, agent_info} ->
      capability in (agent_info.metadata.capabilities || [])
    end)
    |> Enum.map(fn {id, agent_info} -> {id, agent_info} end)
  end
  
  def get_cluster_agents do
    :ets.tab2list(:distributed_agents)
    |> Enum.group_by(fn {_id, agent_info} -> agent_info.node end)
    |> Enum.map(fn {node, agents} ->
      {node, length(agents), agents}
    end)
  end
  
  defp extract_agent_capabilities(pid) do
    try do
      case :rpc.call(Node.self(), GenServer, :call, [pid, :get_capabilities]) do
        capabilities when is_list(capabilities) -> capabilities
        _ -> [:general_purpose]
      end
    rescue
      _ -> [:general_purpose]
    end
  end
end
```

#### 2.2 Consensus-Based Registry Updates
```elixir
defmodule Foundation.Consensus do
  @moduledoc """
  Distributed consensus for cluster-wide state management
  """
  
  use GenServer
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def propose_update(domain, operation) do
    GenServer.call(__MODULE__, {:propose, domain, operation})
  end
  
  def handle_call({:propose, domain, operation}, _from, state) do
    proposal_id = generate_proposal_id()
    
    # Phase 1: Prepare - send to all nodes
    prepare_responses = broadcast_prepare(proposal_id, domain, operation)
    
    if consensus_reached?(prepare_responses) do
      # Phase 2: Commit - apply the operation
      commit_responses = broadcast_commit(proposal_id, domain, operation)
      
      if consensus_reached?(commit_responses) do
        # Apply locally
        apply_operation(domain, operation)
        {:reply, {:ok, proposal_id}, state}
      else
        {:reply, {:error, :commit_failed}, state}
      end
    else
      {:reply, {:error, :prepare_failed}, state}
    end
  end
  
  defp broadcast_prepare(proposal_id, domain, operation) do
    nodes = Node.list([:visible])
    
    Enum.map(nodes, fn node ->
      case :rpc.call(node, __MODULE__, :handle_prepare, [proposal_id, domain, operation]) do
        {:ok, _} -> {:ok, node}
        error -> {:error, node, error}
      end
    end)
  end
  
  defp consensus_reached?(responses) do
    success_count = Enum.count(responses, fn 
      {:ok, _} -> true
      _ -> false
    end)
    
    total_nodes = length(Node.list([:visible])) + 1  # +1 for self
    success_count >= div(total_nodes, 2) + 1  # Majority
  end
  
  def handle_prepare(proposal_id, domain, operation) do
    # Validate operation and check if it can be applied
    case validate_operation(domain, operation) do
      :ok ->
        # Store proposal for commit phase
        :ets.insert(:consensus_proposals, {proposal_id, domain, operation})
        {:ok, proposal_id}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp apply_operation(:agent_registry, {:register, agent_id, agent_info}) do
    :ets.insert(:distributed_agents, {agent_id, agent_info})
    
    # Emit telemetry
    :telemetry.execute(
      [:foundation, :registry, :agent_registered],
      %{total_agents: :ets.info(:distributed_agents, :size)},
      %{agent_id: agent_id, node: agent_info.node}
    )
  end
  
  defp apply_operation(:agent_registry, {:unregister, agent_id}) do
    :ets.delete(:distributed_agents, agent_id)
    
    :telemetry.execute(
      [:foundation, :registry, :agent_unregistered],
      %{total_agents: :ets.info(:distributed_agents, :size)},
      %{agent_id: agent_id}
    )
  end
end
```

### 3. Distributed Agent Coordination

#### 3.1 Cross-Node Signal Routing
```elixir
defmodule Foundation.DistributedSignaling do
  @moduledoc """
  Routes Jido signals across cluster nodes with delivery guarantees
  """
  
  use GenServer
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def route_signal(signal, target_selector) do
    case resolve_target(target_selector) do
      {:local, local_targets} ->
        # Route locally via Jido.Signal.Bus
        Enum.each(local_targets, fn target ->
          Jido.Signal.Bus.send_signal(target, signal)
        end)
        
      {:remote, remote_targets} ->
        # Route to remote nodes
        Enum.each(remote_targets, fn {node, targets} ->
          route_to_remote_node(node, targets, signal)
        end)
        
      {:broadcast, :cluster} ->
        # Broadcast to all cluster nodes
        broadcast_signal(signal)
    end
  end
  
  defp resolve_target({:agent_id, agent_id}) do
    case Foundation.DistributedAgentRegistry.lookup_agent(agent_id) do
      {:ok, agent_info} ->
        if agent_info.node == Node.self() do
          {:local, [agent_info.pid]}
        else
          {:remote, [{agent_info.node, [agent_info.pid]}]}
        end
        
      {:error, :not_found} ->
        {:error, :agent_not_found}
    end
  end
  
  defp resolve_target({:capability, capability}) do
    agents = Foundation.DistributedAgentRegistry.find_agents_by_capability(capability)
    
    {local, remote} = Enum.split_with(agents, fn {_id, agent_info} ->
      agent_info.node == Node.self()
    end)
    
    result = []
    result = if local != [], do: [local: Enum.map(local, fn {_id, info} -> info.pid end)] ++ result, else: result
    
    if remote != [] do
      remote_by_node = Enum.group_by(remote, fn {_id, agent_info} -> agent_info.node end)
      remote_targets = Enum.map(remote_by_node, fn {node, agents} ->
        pids = Enum.map(agents, fn {_id, info} -> info.pid end)
        {node, pids}
      end)
      [{:remote, remote_targets} | result]
    else
      result
    end
  end
  
  defp route_to_remote_node(node, targets, signal) do
    # Use supervised send for reliability
    Foundation.SupervisedSend.send_supervised(
      {Foundation.DistributedSignaling, node},
      {:receive_remote_signal, targets, signal},
      timeout: 5000,
      retries: 3,
      on_error: :log
    )
  end
  
  def handle_cast({:receive_remote_signal, targets, signal}, state) do
    # Deliver to local targets
    Enum.each(targets, fn target ->
      Jido.Signal.Bus.send_signal(target, signal)
    end)
    
    {:noreply, state}
  end
  
  defp broadcast_signal(signal) do
    nodes = Node.list([:visible])
    
    # Use Phoenix.PubSub for efficient broadcasting
    Phoenix.PubSub.broadcast(
      Foundation.PubSub,
      "cluster_signals",
      {:cluster_signal, signal}
    )
  end
end
```

#### 3.2 Distributed Coordination Primitives
```elixir
defmodule Foundation.DistributedCoordination do
  @moduledoc """
  Advanced coordination primitives for distributed Jido agents
  """
  
  def distributed_barrier(barrier_id, participants, timeout \\ 30_000) do
    coordinator_node = select_coordinator_node()
    
    if coordinator_node == Node.self() do
      # Act as coordinator
      coordinate_barrier(barrier_id, participants, timeout)
    else
      # Join barrier on coordinator node
      join_barrier(coordinator_node, barrier_id, participants, timeout)
    end
  end
  
  def coordinate_agents(agent_group, coordination_pattern, opts \\ []) do
    case coordination_pattern do
      :consensus ->
        coordinate_consensus(agent_group, opts)
        
      :pipeline ->
        coordinate_pipeline(agent_group, opts)
        
      :map_reduce ->
        coordinate_map_reduce(agent_group, opts)
        
      :leader_follower ->
        coordinate_leader_follower(agent_group, opts)
    end
  end
  
  defp coordinate_consensus(agent_group, opts) do
    # Distributed consensus coordination
    proposal = opts[:proposal]
    timeout = opts[:timeout] || 30_000
    
    # Gather votes from all agents
    votes = Enum.map(agent_group, fn agent_id ->
      case Foundation.DistributedAgentRegistry.lookup_agent(agent_id) do
        {:ok, agent_info} ->
          vote_signal = %Jido.Signal{
            source: self(),
            type: "consensus.vote_request",
            data: %{proposal: proposal, barrier_id: generate_barrier_id()}
          }
          
          Foundation.DistributedSignaling.route_signal(vote_signal, {:agent_id, agent_id})
          
          # Wait for response
          receive do
            {:vote_response, ^agent_id, vote} -> {agent_id, vote}
          after
            timeout -> {agent_id, :timeout}
          end
          
        {:error, _} ->
          {agent_id, :unavailable}
      end
    end)
    
    # Determine consensus result
    positive_votes = Enum.count(votes, fn {_id, vote} -> vote == :yes end)
    total_agents = length(agent_group)
    
    if positive_votes >= div(total_agents, 2) + 1 do
      notify_consensus_result(agent_group, :accepted)
      {:ok, :consensus_reached}
    else
      notify_consensus_result(agent_group, :rejected)
      {:error, :consensus_failed}
    end
  end
  
  defp coordinate_pipeline(agent_group, opts) do
    # Pipeline coordination with ordered execution
    input_data = opts[:input_data]
    
    Enum.reduce_while(agent_group, {:ok, input_data}, fn agent_id, {:ok, data} ->
      case Foundation.DistributedAgentRegistry.lookup_agent(agent_id) do
        {:ok, _agent_info} ->
          signal = %Jido.Signal{
            source: self(),
            type: "pipeline.process",
            data: %{input: data, stage: agent_id}
          }
          
          Foundation.DistributedSignaling.route_signal(signal, {:agent_id, agent_id})
          
          # Wait for processing result
          receive do
            {:pipeline_result, ^agent_id, {:ok, result}} ->
              {:cont, {:ok, result}}
              
            {:pipeline_result, ^agent_id, {:error, reason}} ->
              {:halt, {:error, {agent_id, reason}}}
          after
            30_000 -> {:halt, {:error, {:timeout, agent_id}}}
          end
          
        {:error, reason} ->
          {:halt, {:error, {agent_id, reason}}}
      end
    end)
  end
end
```

### 4. Fault Tolerance and Recovery

#### 4.1 Agent Failover Management
```elixir
defmodule Foundation.Clustering.Failover do
  @moduledoc """
  Handles agent failover and recovery across cluster nodes
  """
  
  use GenServer
  require Logger
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def handle_node_loss(lost_node) do
    GenServer.cast(__MODULE__, {:node_lost, lost_node})
  end
  
  def handle_cast({:node_lost, lost_node}, state) do
    Logger.warning("Handling failover for lost node: #{lost_node}")
    
    # Find all agents that were running on the lost node
    lost_agents = find_agents_on_node(lost_node)
    
    # Attempt to restart critical agents on other nodes
    Enum.each(lost_agents, fn {agent_id, agent_info} ->
      if agent_info.metadata.critical do
        restart_critical_agent(agent_id, agent_info)
      else
        mark_agent_unavailable(agent_id)
      end
    end)
    
    # Update cluster topology
    Foundation.Clustering.Topology.remove_node(lost_node)
    
    # Emit failover telemetry
    :telemetry.execute(
      [:foundation, :clustering, :failover_completed],
      %{lost_agents: length(lost_agents)},
      %{lost_node: lost_node}
    )
    
    {:noreply, state}
  end
  
  defp find_agents_on_node(node) do
    :ets.tab2list(:distributed_agents)
    |> Enum.filter(fn {_id, agent_info} -> agent_info.node == node end)
  end
  
  defp restart_critical_agent(agent_id, agent_info) do
    # Select new node for agent
    {:ok, target_node} = Foundation.Clustering.Topology.select_optimal_node(
      agent_info.metadata.agent_spec,
      :load_balanced
    )
    
    # Restart agent on target node
    case :rpc.call(target_node, Foundation.AgentManager, :start_agent, [
      agent_info.metadata.agent_spec,
      [id: agent_id, recovered: true]
    ]) do
      {:ok, new_pid} ->
        Logger.info("Successfully restarted critical agent #{agent_id} on #{target_node}")
        
        # Update registry
        Foundation.DistributedAgentRegistry.register_agent(
          agent_id,
          new_pid,
          Map.put(agent_info.metadata, :recovered_from, agent_info.node)
        )
        
      {:error, reason} ->
        Logger.error("Failed to restart critical agent #{agent_id}: #{inspect(reason)}")
        mark_agent_unavailable(agent_id)
    end
  end
  
  defp mark_agent_unavailable(agent_id) do
    Foundation.Consensus.propose_update(:agent_registry, {:mark_unavailable, agent_id})
  end
end
```

### 5. Resource Management and Load Balancing

#### 5.1 Cluster Resource Monitoring
```elixir
defmodule Foundation.ClusterResourceManager do
  @moduledoc """
  Manages resources across the cluster for optimal agent placement
  """
  
  use GenServer
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def get_cluster_resources do
    GenServer.call(__MODULE__, :get_cluster_resources)
  end
  
  def check_resource_availability(requirements) do
    GenServer.call(__MODULE__, {:check_resources, requirements})
  end
  
  def handle_call(:get_cluster_resources, _from, state) do
    cluster_resources = %{
      nodes: collect_node_resources(),
      total_agents: count_total_agents(),
      available_capacity: calculate_available_capacity(),
      resource_utilization: calculate_utilization()
    }
    
    {:reply, cluster_resources, state}
  end
  
  defp collect_node_resources do
    nodes = [Node.self() | Node.list([:visible])]
    
    Enum.map(nodes, fn node ->
      resources = case node do
        ^Node.self() ->
          Foundation.ResourceMonitor.current_usage()
          
        remote_node ->
          case :rpc.call(remote_node, Foundation.ResourceMonitor, :current_usage, []) do
            {:badrpc, _} -> %{available: false}
            result -> result
          end
      end
      
      {node, resources}
    end)
    |> Map.new()
  end
  
  def allocate_resources(agent_id, requirements) do
    case find_suitable_node(requirements) do
      {:ok, target_node} ->
        # Reserve resources on target node
        case :rpc.call(target_node, Foundation.ResourceManager, :reserve_resources, [
          agent_id, requirements
        ]) do
          {:ok, reservation_id} ->
            {:ok, target_node, reservation_id}
            
          {:error, reason} ->
            {:error, reason}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp find_suitable_node(requirements) do
    nodes = [Node.self() | Node.list([:visible])]
    
    suitable_nodes = Enum.filter(nodes, fn node ->
      case :rpc.call(node, Foundation.ResourceManager, :can_allocate?, [requirements]) do
        true -> true
        false -> false
        {:badrpc, _} -> false
      end
    end)
    
    case suitable_nodes do
      [] -> {:error, :no_suitable_nodes}
      nodes -> {:ok, select_best_node(nodes, requirements)}
    end
  end
  
  defp select_best_node(nodes, _requirements) do
    # Simple load-based selection (can be enhanced with more sophisticated algorithms)
    Enum.min_by(nodes, fn node ->
      case :rpc.call(node, Foundation.ResourceMonitor, :current_load, []) do
        load when is_number(load) -> load
        _ -> 1.0  # Assume high load if can't determine
      end
    end)
  end
end
```

## Integration with Jido

### Jido Agent Enhancement for Clustering
```elixir
defmodule Foundation.ClusteredJidoAgent do
  @moduledoc """
  Enhanced Jido agent with clustering capabilities
  """
  
  defmacro __using__(opts) do
    quote do
      use Jido.Agent, unquote(opts)
      
      # Override mount for cluster registration
      def mount(agent, opts) do
        # Standard Jido mount
        {:ok, agent} = super(agent, opts)
        
        # Register with Foundation cluster
        metadata = %{
          agent_spec: unquote(opts),
          capabilities: get_agent_capabilities(),
          critical: opts[:critical] || false,
          resource_requirements: opts[:resources] || %{}
        }
        
        Foundation.DistributedAgentRegistry.register_agent(
          agent.id,
          self(),
          metadata
        )
        
        # Subscribe to cluster signals
        Foundation.DistributedSignaling.subscribe_to_cluster_signals(self())
        
        {:ok, agent}
      end
      
      # Override shutdown for cluster cleanup
      def shutdown(agent, reason) do
        # Unregister from cluster
        Foundation.DistributedAgentRegistry.unregister_agent(agent.id)
        
        # Standard Jido shutdown
        super(agent, reason)
      end
      
      # Enhanced signal handling for distributed signals
      def handle_signal(signal, agent) do
        case signal.type do
          "cluster." <> _cluster_signal ->
            handle_cluster_signal(signal, agent)
            
          _ ->
            super(signal, agent)
        end
      end
      
      defp handle_cluster_signal(signal, agent) do
        # Default cluster signal handling
        {:ok, signal}
      end
      
      defoverridable mount: 2, shutdown: 2, handle_signal: 2, handle_cluster_signal: 2
    end
  end
  
  defp get_agent_capabilities do
    # Extract capabilities from agent definition
    [:general_purpose]
  end
end
```

## Deployment Architecture

### Production Cluster Deployment
```elixir
defmodule Foundation.ClusterDeployment do
  @moduledoc """
  Production deployment patterns for clustered Jido agents
  """
  
  def deploy_agent_cluster(cluster_spec) do
    # Phase 1: Initialize cluster
    {:ok, cluster} = Foundation.Clustering.Discovery.start_cluster(cluster_spec.nodes)
    
    # Phase 2: Deploy core services
    deploy_core_services(cluster_spec.core_services)
    
    # Phase 3: Deploy agents with placement strategy
    deploy_agents(cluster_spec.agents)
    
    # Phase 4: Verify cluster health
    verify_cluster_health()
  end
  
  defp deploy_agents(agent_specs) do
    Enum.map(agent_specs, fn agent_spec ->
      # Select optimal node
      {:ok, target_node} = Foundation.Clustering.Topology.select_optimal_node(
        agent_spec,
        agent_spec.placement_strategy || :load_balanced
      )
      
      # Deploy agent to selected node
      case :rpc.call(target_node, Foundation.AgentManager, :start_agent, [agent_spec]) do
        {:ok, pid} ->
          Logger.info("Deployed agent #{agent_spec.id} to node #{target_node}")
          {:ok, agent_spec.id, target_node, pid}
          
        {:error, reason} ->
          Logger.error("Failed to deploy agent #{agent_spec.id}: #{inspect(reason)}")
          {:error, agent_spec.id, reason}
      end
    end)
  end
  
  def scale_cluster(scaling_directive) do
    case scaling_directive.action do
      :scale_up ->
        add_nodes(scaling_directive.target_nodes)
        
      :scale_down ->
        remove_nodes(scaling_directive.target_nodes)
        
      :rebalance ->
        rebalance_agents(scaling_directive.strategy)
    end
  end
  
  defp rebalance_agents(strategy) do
    current_distribution = Foundation.DistributedAgentRegistry.get_cluster_agents()
    
    case strategy do
      :even_distribution ->
        rebalance_evenly(current_distribution)
        
      :load_based ->
        rebalance_by_load(current_distribution)
        
      :capability_based ->
        rebalance_by_capabilities(current_distribution)
    end
  end
end
```

## Conclusion

### Foundation's Essential Role: Clustering Excellence

This architecture demonstrates that **Foundation provides irreplaceable value for enterprise clustering**:

1. **Automatic cluster formation** with health monitoring
2. **Distributed agent placement** with intelligent load balancing  
3. **Consensus-based coordination** for cluster-wide operations
4. **Cross-node fault tolerance** with automatic failover
5. **Resource management** and optimization across cluster
6. **Enterprise monitoring** and observability

### Jido's Strengths Preserved

Foundation enhances rather than replaces Jido's capabilities:
- **Agent definition excellence** remains with Jido
- **Action-to-tool conversion** leveraged directly
- **Signal routing sophistication** extended across cluster
- **Skills and sensors** work seamlessly in clustered environment

### Strategic Value Proposition

**For enterprise clusters**: Foundation + Jido provides capabilities impossible with either alone
**For simple deployments**: Pure Jido remains the optimal choice

This clustering architecture enables **enterprise-grade distributed multi-agent systems** while preserving all of Jido's sophisticated single-node capabilities.