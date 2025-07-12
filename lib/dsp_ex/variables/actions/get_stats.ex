defmodule DSPEx.Variables.Actions.GetStats do
  @moduledoc """
  Action to retrieve statistics and performance data from a cognitive variable.
  """

  use Jido.Action,
    name: "get_cognitive_variable_stats",
    description: "Retrieve statistics and performance data from cognitive variable",
    schema: []

  @impl true
  def run(_agent, _params, state) do
    stats = %{
      name: state.name,
      current_value: state.current_value,
      valid_range: state.valid_range,
      last_updated: state.last_updated,
      update_count: state.update_count,
      coordination_enabled: state.coordination_enabled,
      coordination_scope: state.coordination_scope,
      coordination_stats: state.coordination_stats,
      performance_history_size: length(state.performance_history),
      affected_agents_count: length(state.affected_agents),
      adaptation_strategy: state.adaptation_strategy
    }

    {:ok, stats, state}
  end
end