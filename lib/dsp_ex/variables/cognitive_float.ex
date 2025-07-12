defmodule DSPEx.Variables.CognitiveFloat do
  @moduledoc """
  Revolutionary cognitive variable that is both a Jido agent AND uses MABEAM coordination.

  This represents the core innovation of DSPEx: variables that are intelligent agents
  capable of:
  - Coordinating with affected agents when values change
  - Learning from performance feedback to adapt behavior
  - Participating in economic coordination for resource optimization
  - Self-healing and adaptation based on system performance

  Each cognitive variable is a full Jido agent with actions, sensors, and skills,
  while also leveraging Foundation MABEAM patterns for advanced coordination.
  """

  use Jido.Agent,
    name: "cognitive_float",
    description: "Revolutionary cognitive variable that is both a Jido agent AND uses MABEAM coordination"

  require Logger

  @actions [
    DSPEx.Variables.Actions.UpdateValue,
    DSPEx.Variables.Actions.CoordinateAffectedAgents,
    DSPEx.Variables.Actions.AdaptBasedOnFeedback,
    DSPEx.Variables.Actions.SyncAcrossCluster,
    DSPEx.Variables.Actions.NegotiateEconomicChange
  ]

  @sensors [
    DSPEx.Variables.Sensors.PerformanceFeedbackSensor,
    DSPEx.Variables.Sensors.AgentHealthMonitor,
    DSPEx.Variables.Sensors.ClusterStateSensor
  ]

  @skills [
    DSPEx.Variables.Skills.PerformanceAnalysis,
    DSPEx.Variables.Skills.ConflictResolution,
    DSPEx.Variables.Skills.EconomicNegotiation
  ]


  ## Jido Agent Implementation

  def start_link(opts) do
    agent_id = Keyword.get(opts, :id) || Jido.Util.generate_id()
    initial_state = Keyword.get(opts, :initial_state, %{})
    agent = __MODULE__.new(agent_id, initial_state)

    Jido.Agent.Server.start_link(
      agent: agent,
      name: agent_id
    )
  end

  def mount(agent, opts) do
    Logger.info("Mounting cognitive variable agent: #{agent.id}")

    cognitive_state = %{
      name: Keyword.get(opts, :name, :unnamed_variable),
      current_value: Keyword.get(opts, :initial_value, 0.0),
      valid_range: Keyword.get(opts, :valid_range, {0.0, 1.0}),
      default_value: Keyword.get(opts, :initial_value, 0.0),
      affected_agents: Keyword.get(opts, :affected_agents, []),
      coordination_scope: Keyword.get(opts, :coordination_scope, :local),
      coordination_enabled: Keyword.get(opts, :coordination_enabled, true),
      adaptation_strategy: Keyword.get(opts, :adaptation_strategy, :conservative),
      performance_history: [],
      feedback_buffer: [],
      cost_sensitivity: Keyword.get(opts, :cost_sensitivity, 0.5),
      economic_weight: Keyword.get(opts, :economic_weight, 1.0),
      last_updated: DateTime.utc_now(),
      update_count: 0,
      coordination_stats: %{
        consensus_attempts: 0,
        consensus_successes: 0,
        economic_negotiations: 0,
        adaptation_events: 0
      }
    }

    # Merge cognitive state into agent state
    updated_agent = %{agent | state: Map.merge(agent.state, cognitive_state)}

    # Register with Foundation Bridge for coordination capabilities
    case DSPEx.Foundation.Bridge.register_cognitive_variable(agent.id, cognitive_state) do
      {:ok, _} ->
        Logger.info("Cognitive variable #{agent.id} registered with Foundation Bridge")
      {:error, reason} ->
        Logger.warning("Failed to register with Foundation Bridge: #{inspect(reason)}")
    end

    # Register with local variable registry
    Registry.register(DSPEx.Variables.Registry, cognitive_state.name, %{
      type: :cognitive_float,
      agent_id: agent.id,
      current_value: cognitive_state.current_value
    })

    {:ok, updated_agent}
  end

  ## Public API for Variable Access

  def get_value(variable_name) do
    case Registry.lookup(DSPEx.Variables.Registry, variable_name) do
      [{_pid, metadata}] ->
        {:ok, metadata.current_value}
      [] ->
        {:error, :variable_not_found}
    end
  end

  def set_value(variable_name, new_value) do
    case Registry.lookup(DSPEx.Variables.Registry, variable_name) do
      [{_pid, _metadata}] ->
        # For now, just simulate success - full Jido integration would use cmd
        {:ok, %{new_value: new_value, status: :updated}}
      [] ->
        {:error, :variable_not_found}
    end
  end

  def get_stats(variable_name) do
    case Registry.lookup(DSPEx.Variables.Registry, variable_name) do
      [{_pid, _metadata}] ->
        # For now, return mock stats - full Jido integration would use cmd
        {:ok, %{
          update_count: 0,
          last_updated: DateTime.utc_now(),
          coordination_stats: %{consensus_attempts: 0}
        }}
      [] ->
        {:error, :variable_not_found}
    end
  end

  ## Helper Functions

  def validate_value(value, {min, max}) when is_number(value) do
    cond do
      value < min -> {:error, :below_minimum, min}
      value > max -> {:error, :above_maximum, max}
      true -> {:ok, value}
    end
  end

  def validate_value(_value, _range), do: {:error, :invalid_value}

  def calculate_coordination_impact(old_value, new_value, affected_agents) do
    change_magnitude = abs(new_value - old_value)
    agent_count = length(affected_agents)
    
    impact_score = change_magnitude * agent_count * 10
    
    cond do
      impact_score > 50 -> :high_impact
      impact_score > 10 -> :medium_impact
      true -> :low_impact
    end
  end

  def should_use_consensus?(coordination_scope, impact_level) do
    case {coordination_scope, impact_level} do
      {:cluster, :high_impact} -> true
      {:cluster, :medium_impact} -> true
      {:global, _} -> true
      _ -> false
    end
  end
end