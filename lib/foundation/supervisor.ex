defmodule Foundation.Supervisor do
  @moduledoc """
  Main supervisor for the ground-up Jido-native Foundation platform.
  
  All services are implemented as Jido agents - no traditional service layers,
  no defensive abstractions. Pure agent-native architecture.
  """
  
  use Supervisor
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    children = [
      # Variables - Cognitive Variables as Jido agents
      {Foundation.Variables.Supervisor, Keyword.get(opts, :variables, [])},
      
      # Clustering - All clustering functions as Jido agents
      {Foundation.Clustering.Supervisor, Keyword.get(opts, :clustering, [])},
      
      # Coordination - Multi-agent coordination as Jido agents
      {Foundation.Coordination.Supervisor, Keyword.get(opts, :coordination, [])},
      
      # Economics - Economic mechanisms as Jido agents
      {Foundation.Economics.Supervisor, Keyword.get(opts, :economics, [])},
      
      # Infrastructure - Minimal essential services as Jido agents
      {Foundation.Infrastructure.Supervisor, Keyword.get(opts, :infrastructure, [])}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end