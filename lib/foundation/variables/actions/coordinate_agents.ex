defmodule Foundation.Variables.Actions.CoordinateAgents do
  @moduledoc """
  Action for coordinating with other agents when variable values change.
  
  This action handles the coordination aspect of Cognitive Variables,
  ensuring affected agents are notified of changes and can react accordingly.
  """
  
  use Jido.Action,
    name: "coordinate_agents", 
    description: "Coordinates with affected agents during variable changes",
    category: "coordination",
    tags: ["coordination", "agents", "ml", "optimization"],
    schema: [
      affected_agents: [type: {:list, :pid}, required: true, doc: "PIDs of agents to coordinate with"],
      variable_name: [type: :atom, required: true, doc: "Name of the variable that changed"],
      old_value: [type: :any, required: true, doc: "Previous value"],
      new_value: [type: :any, required: true, doc: "New value"],
      context: [type: :map, default: %{}, doc: "Additional coordination context"],
      coordination_mode: [type: :atom, default: :notify, doc: "Mode: :notify, :sync, or :async"]
    ]

  require Logger

  @doc """
  Coordinates with affected agents about variable changes.
  
  ## Parameters
  - params: Map containing coordination parameters
  - agent: The cognitive variable agent initiating coordination
  
  ## Returns
  - {:ok, state, []} - Coordination completed, no state changes
  """
  def run(params, agent) do
    affected_agents = params.affected_agents
    variable_name = params.variable_name
    old_value = params.old_value
    new_value = params.new_value
    context = Map.get(params, :context, %{})
    mode = Map.get(params, :coordination_mode, :notify)
    
    Logger.debug("CoordinateAgents action: #{variable_name} changed #{old_value} -> #{new_value}, coordinating with #{length(affected_agents)} agents")
    
    case mode do
      :notify ->
        coordinate_via_notification(affected_agents, variable_name, old_value, new_value, context, agent)
      
      :sync ->
        coordinate_synchronously(affected_agents, variable_name, old_value, new_value, context, agent)
      
      :async ->
        coordinate_asynchronously(affected_agents, variable_name, old_value, new_value, context, agent)
      
      unknown_mode ->
        Logger.warning("Unknown coordination mode #{unknown_mode}, falling back to :notify")
        coordinate_via_notification(affected_agents, variable_name, old_value, new_value, context, agent)
    end
    
    # No state changes, just coordination
    {:ok, agent.state, []}
  end

  # Private coordination functions

  defp coordinate_via_notification(affected_agents, variable_name, old_value, new_value, context, agent) do
    notification = %{
      type: :variable_changed,
      variable_name: variable_name,
      old_value: old_value,
      new_value: new_value,
      context: context,
      coordination_scope: agent.state.coordination_scope,
      source_agent_id: "unknown",
      timestamp: DateTime.utc_now()
    }
    
    # Send notifications to all affected agents
    results = Enum.map(affected_agents, fn agent_pid ->
      if Process.alive?(agent_pid) do
        send(agent_pid, {:variable_notification, notification})
        {:ok, agent_pid}
      else
        Logger.warning("Agent #{inspect(agent_pid)} not alive, skipping notification")
        {:error, {:agent_not_alive, agent_pid}}
      end
    end)
    
    success_count = Enum.count(results, &match?({:ok, _}, &1))
    Logger.debug("Sent notifications to #{success_count}/#{length(affected_agents)} agents for #{variable_name}")
    
    :ok
  end

  defp coordinate_synchronously(affected_agents, variable_name, old_value, new_value, context, agent) do
    # Create a signal for synchronous coordination
    signal = Jido.Signal.new!(%{
      type: "cognitive_variable.coordination.sync",
      source: "agent:unknown",
      subject: "jido://agent/cognitive_variable/unknown",
      data: %{
        variable_name: variable_name,
        old_value: old_value,
        new_value: new_value,
        context: context,
        coordination_scope: agent.state.coordination_scope
      }
    })
    
    # Send to each agent and wait for responses
    results = Enum.map(affected_agents, fn agent_pid ->
      try do
        case Jido.Agent.Server.call(agent_pid, signal, 5000) do
          {:ok, response} ->
            Logger.debug("Synchronous coordination success with #{inspect(agent_pid)}")
            {:ok, agent_pid, response}
          {:error, reason} ->
            Logger.warning("Synchronous coordination failed with #{inspect(agent_pid)}: #{inspect(reason)}")
            {:error, agent_pid, reason}
        end
      rescue
        error ->
          Logger.warning("Exception during synchronous coordination with #{inspect(agent_pid)}: #{inspect(error)}")
          {:error, agent_pid, error}
      end
    end)
    
    success_count = Enum.count(results, &match?({:ok, _, _}, &1))
    Logger.info("Synchronous coordination completed for #{variable_name}: #{success_count}/#{length(affected_agents)} successful")
    
    :ok
  end

  defp coordinate_asynchronously(affected_agents, variable_name, old_value, new_value, context, agent) do
    # Create a signal for asynchronous coordination
    signal = Jido.Signal.new!(%{
      type: "cognitive_variable.coordination.async",
      source: "agent:unknown",
      subject: "jido://agent/cognitive_variable/unknown",
      data: %{
        variable_name: variable_name,
        old_value: old_value,
        new_value: new_value,
        context: context,
        coordination_scope: agent.state.coordination_scope
      }
    })
    
    # Send asynchronously to each agent
    results = Enum.map(affected_agents, fn agent_pid ->
      try do
        case Jido.Agent.Server.cast(agent_pid, signal) do
          {:ok, signal_id} ->
            Logger.debug("Asynchronous coordination sent to #{inspect(agent_pid)}, signal_id: #{signal_id}")
            {:ok, agent_pid, signal_id}
          {:error, reason} ->
            Logger.warning("Asynchronous coordination failed with #{inspect(agent_pid)}: #{inspect(reason)}")
            {:error, agent_pid, reason}
        end
      rescue
        error ->
          Logger.warning("Exception during asynchronous coordination with #{inspect(agent_pid)}: #{inspect(error)}")
          {:error, agent_pid, error}
      end
    end)
    
    success_count = Enum.count(results, &match?({:ok, _, _}, &1))
    Logger.info("Asynchronous coordination initiated for #{variable_name}: #{success_count}/#{length(affected_agents)} successful")
    
    :ok
  end
end