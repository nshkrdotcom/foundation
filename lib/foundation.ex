defmodule Foundation do
  @moduledoc """
  Foundation - Ground-up Jido-native distributed ML platform.
  
  This is a complete rewrite built on Jido-first principles where everything
  is an agent with actions, sensors, and skills. No defensive abstractions,
  no complex service layers - just intelligent agents coordinating via signals.
  
  ## Core Architecture
  
  - **Jido Agents**: Everything is a Jido agent (Variables, Clustering, Coordination)
  - **Signal Communication**: All coordination via native Jido signals
  - **Cognitive Variables**: ML parameters as intelligent coordination primitives
  - **Agent-Native Clustering**: Distributed systems as coordinated agents
  - **Economic Coordination**: Cost optimization through agent economics
  
  ## Key Innovations
  
  - Variables that actively coordinate other agents
  - Clustering functions as intelligent agents
  - Real-time adaptation and learning
  - Distributed intelligence across BEAM clusters
  """
  
  use Application
  
  @doc """
  Start the Foundation application with Jido-native architecture.
  """
  def start(_type, _args) do
    children = [
      # Foundation agents - everything is an agent
      {Foundation.Supervisor, []}
    ]
    
    opts = [strategy: :one_for_one, name: Foundation.RootSupervisor]
    Supervisor.start_link(children, opts)
  end
end