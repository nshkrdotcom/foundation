defmodule Foundation.Variables.Actions.PerformanceFeedback do
  @moduledoc """
  Action for processing performance feedback to enable adaptive optimization.
  
  This action allows Cognitive Variables to learn and adapt based on performance
  metrics, implementing various adaptation strategies.
  """
  
  use Jido.Action,
    name: "performance_feedback",
    description: "Processes performance feedback for adaptive optimization",
    category: "ml_optimization", 
    tags: ["ml", "optimization", "adaptation", "feedback"],
    schema: [
      performance: [type: :float, required: true, doc: "Performance metric (0.0-1.0)"],
      cost: [type: :float, doc: "Optional cost metric"],
      timestamp: [type: :any, doc: "Timestamp of the performance measurement"],
      context: [type: :map, default: %{}, doc: "Additional context information"],
      strategy_override: [type: :atom, doc: "Override the agent's adaptation strategy"]
    ]

  require Logger

  @doc """
  Processes performance feedback and potentially adapts the variable's value.
  
  ## Parameters
  - params: Map containing performance, cost, timestamp, and context
  - agent: The cognitive variable agent to potentially adapt
  
  ## Returns
  - {:ok, new_state, directives} - Updated state and coordination directives
  """
  def run(%{performance: performance} = params, agent) do
    strategy = Map.get(params, :strategy_override, agent.state.adaptation_strategy)
    
    Logger.debug("PerformanceFeedback action for #{agent.state.name}: performance=#{performance}, strategy=#{strategy}")
    
    case strategy do
      :performance_feedback ->
        process_performance_adaptation(params, agent)
      
      :gradient_estimation ->
        process_gradient_estimation(params, agent)
      
      :none ->
        # No adaptation, just log the feedback
        Logger.debug("Performance feedback received for #{agent.state.name} but adaptation disabled")
        {:ok, agent.state, []}
      
      unknown_strategy ->
        Logger.warning("Unknown adaptation strategy #{unknown_strategy} for #{agent.state.name}")
        {:ok, agent.state, []}
    end
  end

  # Private adaptation functions

  defp process_performance_adaptation(params, agent) do
    performance = params.performance
    
    # Simple adaptation logic: if performance is low, try to change the value
    case {performance, agent.state.type} do
      {perf, :float} when perf < 0.5 ->
        # Poor performance, try to adapt
        adapt_float_value(agent, performance, params)
      
      {perf, :choice} when perf < 0.5 ->
        # Poor performance with choice variable
        adapt_choice_value(agent, performance, params)
      
      _ ->
        # Good performance or unsupported type, no change
        Logger.debug("Performance #{performance} acceptable for #{agent.state.name}, no adaptation needed")
        {:ok, agent.state, []}
    end
  end

  defp adapt_float_value(agent, performance, params) do
    current_value = agent.state.current_value
    {min, max} = agent.state.range || {0.0, 1.0}
    
    # Simple adaptation: move away from current value based on performance
    # Lower performance = larger adjustment
    adjustment_magnitude = (1.0 - performance) * 0.1
    
    # Randomly choose direction for exploration
    direction = if :rand.uniform() > 0.5, do: 1, else: -1
    adjustment = direction * adjustment_magnitude * (max - min)
    
    new_value = current_value + adjustment
    clamped_value = max(min, min(max, new_value))
    
    if clamped_value != current_value do
      Logger.info("Adapting #{agent.state.name} due to poor performance #{performance}: #{current_value} -> #{clamped_value}")
      
      new_state = Map.put(agent.state, :current_value, clamped_value)
      
      # Handle coordination directly for adaptation
      coordinate_adaptation(agent, current_value, clamped_value, params)
      
      {:ok, new_state, []}
    else
      {:ok, agent.state, []}
    end
  end

  defp adapt_choice_value(agent, performance, params) do
    choices = agent.state.choices || []
    current_choice = agent.state.current_value
    
    if length(choices) > 1 do
      # Choose a different option for exploration
      other_choices = Enum.reject(choices, &(&1 == current_choice))
      new_choice = Enum.random(other_choices)
      
      Logger.info("Adapting choice #{agent.state.name} due to poor performance #{performance}: #{current_choice} -> #{new_choice}")
      
      new_state = Map.put(agent.state, :current_value, new_choice)
      
      # Handle coordination directly for choice adaptation
      coordinate_adaptation(agent, current_choice, new_choice, params)
      
      {:ok, new_state, []}
    else
      Logger.debug("Cannot adapt choice variable #{agent.state.name} - insufficient choices")
      {:ok, agent.state, []}
    end
  end

  defp process_gradient_estimation(params, agent) do
    # More sophisticated gradient-based adaptation
    # This could be implemented for specialized variables like CognitiveFloat
    Logger.debug("Gradient estimation adaptation for #{agent.state.name} - delegating to specialized handler")
    
    # For now, fall back to simple performance adaptation
    process_performance_adaptation(params, agent)
  end
  
  defp coordinate_adaptation(agent, old_value, new_value, params) do
    context = Map.merge(params[:context] || %{}, %{adaptation_reason: :performance_feedback})
    
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
end