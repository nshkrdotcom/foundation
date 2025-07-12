defmodule DSPEx.Variables.Actions.CoordinateAffectedAgents do
  @moduledoc """
  Action for coordinating with affected agents when variable changes occur.
  """

  use Jido.Action,
    name: "coordinate_affected_agents",
    description: "Coordinate with affected agents when variable changes occur",
    schema: [
      coordination_type: [type: :atom, default: :value_change, doc: "Type of coordination"]
    ]

  require Logger

  @impl true
  def run(agent, params, state) do
    Logger.debug("Coordinating with affected agents for variable #{state.name}")

    coordination_request = %{
      variable_name: state.name,
      current_value: state.current_value,
      coordination_type: Map.get(params, :coordination_type, :value_change),
      timestamp: DateTime.utc_now()
    }

    # Use Foundation Bridge for advanced coordination
    case DSPEx.Foundation.Bridge.find_affected_agents(state.affected_agents) do
      {:ok, agents} ->
        Logger.info("Found #{length(agents)} affected agents for coordination")
        # In full implementation, would coordinate with each agent
        {:ok, state}
        
      {:error, reason} ->
        Logger.warning("Failed to find affected agents: #{inspect(reason)}")
        {:ok, state}
    end
  end
end