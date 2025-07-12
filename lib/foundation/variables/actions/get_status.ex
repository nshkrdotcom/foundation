defmodule Foundation.Variables.Actions.GetStatus do
  @moduledoc """
  Action for retrieving the current status of a Cognitive Variable.
  
  This action replaces the old GenServer handle_call approach with proper Jido.Action
  implementation for querying agent state.
  """
  
  use Jido.Action,
    name: "get_status",
    description: "Retrieves current status and state of cognitive variable",
    category: "variable_query",
    tags: ["ml", "query", "status"],
    schema: [
      include_history: [type: :boolean, default: false, doc: "Include optimization history"],
      include_metadata: [type: :boolean, default: true, doc: "Include variable metadata"]
    ]

  require Logger

  @doc """
  Returns the current status of the cognitive variable.
  
  ## Parameters
  - params: Map with optional include_history and include_metadata flags
  - context: Jido action context containing agent and other data
  
  ## Returns
  - {:ok, status_map} - Status information
  """
  def run(params, context) do
    # Extract agent from context - Jido provides state directly
    agent = case context do
      %{agent: agent} -> agent
      %{state: state} -> %{id: "unknown", state: state}
      _ -> %{id: "unknown", state: %{}}
    end
    include_history = Map.get(params, :include_history, false)
    include_metadata = Map.get(params, :include_metadata, true)
    
    Logger.debug("GetStatus action for cognitive variable: #{agent.state.name}")
    
    # Build base status
    status = %{
      name: agent.state.name,
      type: agent.state.type,
      current_value: agent.state.current_value,
      coordination_scope: agent.state.coordination_scope,
      agent_id: agent.id
    }
    
    # Add optional fields based on parameters
    status = if include_metadata do
      Map.merge(status, %{
        range: agent.state.range,
        affected_agents: length(agent.state.affected_agents),
        adaptation_strategy: agent.state.adaptation_strategy
      })
    else
      status
    end
    
    # Add history if requested and available (for specialized variables)
    status = if include_history and Map.has_key?(agent.state, :optimization_history) do
      Map.put(status, :optimization_history, agent.state.optimization_history)
    else
      status
    end
    
    Logger.debug("Status retrieved for #{agent.state.name}: #{inspect(status)}")
    
    # Return status as the result - GetStatus doesn't change state
    {:ok, status}
  end
end