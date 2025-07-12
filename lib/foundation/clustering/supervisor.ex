defmodule Foundation.Clustering.Supervisor do
  @moduledoc """
  Supervisor for agent-native clustering - every clustering function as intelligent Jido agent.
  
  Revolutionary approach where traditional clustering services are replaced with:
  - Node Discovery Agent: Intelligent network topology management
  - Load Balancer Agent: Adaptive traffic distribution
  - Health Monitor Agent: Predictive health monitoring with anomaly detection
  - Cluster Orchestrator Agent: Master coordination using consensus protocols
  
  No service layers, no defensive abstractions - pure agent intelligence.
  """
  
  use Supervisor
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    clustering_config = Keyword.get(opts, :clustering_config, [])
    
    children = [
      # Core clustering agents - everything is an agent
      {Foundation.Clustering.Agents.NodeDiscovery, clustering_config[:node_discovery] || []},
      {Foundation.Clustering.Agents.LoadBalancer, clustering_config[:load_balancer] || []},
      {Foundation.Clustering.Agents.HealthMonitor, clustering_config[:health_monitor] || []},
      {Foundation.Clustering.Agents.ClusterOrchestrator, clustering_config[:orchestrator] || []},
      
      # Specialized clustering agents
      {Foundation.Clustering.Agents.FailureDetector, clustering_config[:failure_detector] || []},
      {Foundation.Clustering.Agents.ResourceManager, clustering_config[:resource_manager] || []},
      {Foundation.Clustering.Agents.NetworkPartitionHandler, clustering_config[:partition_handler] || []}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  @doc """
  Get the status of all clustering agents.
  """
  def cluster_status do
    children = Supervisor.which_children(__MODULE__)
    
    Enum.map(children, fn {agent_type, pid, _type, _modules} ->
      if Process.alive?(pid) do
        try do
          status = GenServer.call(pid, {:get_status}, 1000)
          {agent_type, :active, status}
        catch
          :exit, reason -> {agent_type, :error, reason}
        end
      else
        {agent_type, :dead, %{}}
      end
    end)
  end
end