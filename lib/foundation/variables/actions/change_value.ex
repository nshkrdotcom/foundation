defmodule Foundation.Variables.Actions.ChangeValue do
  @moduledoc """
  Action for changing the value of a Cognitive Variable with validation and coordination.
  
  This action replaces the old GenServer handle_cast approach with proper Jido.Action
  implementation that supports state validation, coordination directives, and error handling.
  """
  
  use Jido.Action,
    name: "change_value",
    description: "Changes cognitive variable value with validation and coordination",
    category: "variable_management",
    tags: ["ml", "optimization", "coordination"],
    schema: [
      new_value: [type: :any, required: true, doc: "The new value to set"],
      context: [type: :map, default: %{}, doc: "Context information including requester"],
      force: [type: :boolean, default: false, doc: "Force change even if out of range"]
    ]

  require Logger

  @doc """
  Executes the value change with proper validation and coordination.
  
  ## Parameters
  - params: Map containing new_value, context, and optional force flag
  - context: Jido action context containing agent and other data
  
  ## Returns
  - {:ok, result} on success - result contains change information
  - {:error, reason} on validation failure
  """
  def run(%{new_value: new_value} = params, context) do
    # Extract agent from context - Jido provides state directly
    agent = case context do
      %{agent: agent} -> agent
      %{state: state} -> %{id: "unknown", state: state}
      _ -> %{id: "unknown", state: %{}}
    end
    context = Map.get(params, :context, %{})
    force = Map.get(params, :force, false)
    
    Logger.debug("ChangeValue action: #{agent.state.name} #{agent.state.current_value} -> #{new_value}")
    
    with {:ok, validated_value} <- validate_value(new_value, agent.state, force) do
      
      old_value = agent.state.current_value
      Logger.info("Cognitive Variable #{agent.state.name} value changed: #{old_value} -> #{validated_value}")
      
      # Trigger coordination directly
      coordinate_change(agent, old_value, validated_value, context)
      
      # Return result data only - state updates handled by agent
      {:ok, %{
        action: "change_value",
        variable_name: agent.state.name,
        old_value: old_value,
        new_value: validated_value,
        validated: true,
        timestamp: DateTime.utc_now()
      }}
    else
      {:error, reason} = error ->
        Logger.warning("Failed to change value for #{agent.state.name}: #{inspect(reason)}")
        
        # Send error to requester if available
        if Map.has_key?(context, :requester) and is_pid(context.requester) do
          send(context.requester, {:error, {:invalid_value, reason}})
        end
        
        error
    end
  end

  # Private validation functions

  defp validate_value(value, state, force) do
    case {state.type, state.range, force} do
      # Float validation with range
      {:float, {min, max}, false} when is_number(value) ->
        if value >= min and value <= max do
          {:ok, value}
        else
          {:error, {:out_of_range, value, {min, max}}}
        end
      
      # Integer validation with range  
      {:integer, {min, max}, false} when is_integer(value) ->
        if value >= min and value <= max do
          {:ok, value}
        else
          {:error, {:out_of_range, value, {min, max}}}
        end
      
      # Choice validation
      {:choice, choices, false} when is_list(choices) ->
        if value in choices do
          {:ok, value}
        else
          {:error, {:invalid_choice, value, choices}}
        end
      
      # Forced update (bypass validation)
      {_, _, true} ->
        Logger.warning("Forcing value change for #{state.name}, bypassing validation")
        {:ok, value}
      
      # Type mismatch
      {expected_type, _, false} ->
        {:error, {:type_mismatch, value, expected_type}}
      
      # No validation needed
      _ ->
        {:ok, value}
    end
  end

  defp coordinate_change(agent, old_value, new_value, context) do
    # Handle coordination directly in the action
    if length(agent.state.affected_agents) > 0 do
      coordinate_affected_agents(agent, old_value, new_value, context)
    end
    
    # Handle global coordination via signals
    if agent.state.coordination_scope == :global do
      notify_global_change(agent, old_value, new_value, context)
    end
    
    :ok
  end
  
  defp coordinate_affected_agents(agent, old_value, new_value, context) do
    notification = %{
      type: :variable_changed,
      variable_name: agent.state.name,
      old_value: old_value,
      new_value: new_value,
      context: context,
      coordination_scope: agent.state.coordination_scope,
      source_agent_id: "unknown",
      timestamp: DateTime.utc_now()
    }
    
    Enum.each(agent.state.affected_agents, fn agent_pid ->
      if Process.alive?(agent_pid) do
        send(agent_pid, {:variable_notification, notification})
      end
    end)
    
    :ok
  end
  
  defp notify_global_change(agent, old_value, new_value, context) do
    signal = Jido.Signal.new!(%{
      type: "cognitive_variable.value.changed",
      source: "agent:unknown",
      subject: "jido://agent/cognitive_variable/unknown",
      data: %{
        variable_name: agent.state.name,
        old_value: old_value,
        new_value: new_value,
        context: context,
        coordination_scope: agent.state.coordination_scope
      },
      jido_dispatch: {:pubsub, topic: "cognitive_variables_global"}
    })
    
    # Handle PubSub gracefully in test environments
    try do
      Jido.Signal.Dispatch.dispatch(signal, signal.jido_dispatch)
      :ok
    rescue
      ArgumentError -> 
        Logger.debug("PubSub not available, skipping global coordination signal")
        :ok
    end
  end
end