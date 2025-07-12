defmodule Foundation.Variables.CognitiveFloat do
  @moduledoc """
  Cognitive Float Variable - Intelligent continuous parameter with gradient-based optimization.
  
  This is now a proper Jido.Agent that extends CognitiveVariable with specialized
  float-specific capabilities including gradient optimization and momentum-based updates.
  """
  
  use Jido.Agent,
    name: "cognitive_float",
    description: "Intelligent continuous parameter with gradient optimization",
    category: "ml_optimization",
    tags: ["ml", "optimization", "float", "gradient"],
    vsn: "1.0.0",
    schema: [
      name: [type: :atom, required: true],
      type: [type: :atom, default: :float],
      current_value: [type: :float, required: true],
      range: [type: :any, required: true],
      learning_rate: [type: :float, default: 0.01],
      momentum: [type: :float, default: 0.9],
      gradient_estimate: [type: :float, default: 0.0],
      velocity: [type: :float, default: 0.0],
      optimization_history: [type: {:list, :map}, default: []],
      bounds_behavior: [type: :atom, default: :clamp],
      coordination_scope: [type: :atom, default: :local],
      affected_agents: [type: {:list, :pid}, default: []],
      adaptation_strategy: [type: :atom, default: :gradient_optimization]
    ],
    actions: [
      Foundation.Variables.Actions.ChangeValue,
      Foundation.Variables.Actions.GradientFeedback,
      Foundation.Variables.Actions.PerformanceFeedback,
      Foundation.Variables.Actions.CoordinateAgents,
      Foundation.Variables.Actions.GetStatus
    ]

  require Logger

  @doc """
  Creates a new Cognitive Float agent with gradient optimization capabilities.
  
  ## Parameters
  - id: Unique identifier for the agent
  - initial_state: Map containing float variable configuration
  
  ## Examples
      agent = CognitiveFloat.new("learning_rate", %{
        name: :learning_rate,
        current_value: 0.01,
        range: {0.001, 0.1},
        learning_rate: 0.01,
        momentum: 0.9
      })
  """
  def create(id, initial_state \\ %{}) do
    # Set defaults specific to float optimization
    default_state = %{
      name: :float_variable,
      type: :float,
      current_value: 0.5,
      range: {0.0, 1.0},
      learning_rate: 0.01,
      momentum: 0.9,
      gradient_estimate: 0.0,
      velocity: 0.0,
      optimization_history: [],
      bounds_behavior: :clamp,
      coordination_scope: :local,
      affected_agents: [],
      adaptation_strategy: :gradient_optimization
    }
    
    merged_state = Map.merge(default_state, initial_state)
    
    # Create signal routes including gradient-specific actions
    routes = build_signal_routes()
    
    # Start agent server with explicit route configuration
    start_link([
      id: id,
      initial_state: merged_state,
      routes: routes
    ])
  end
  
  # Override start_link to support routes for CognitiveFloat
  def start_link(opts) do
    id = Keyword.get(opts, :id) || Jido.Util.generate_id()
    initial_state = Keyword.get(opts, :initial_state, %{})
    routes = Keyword.get(opts, :routes, [])
    
    # Set defaults specific to float optimization
    default_state = %{
      name: :float_variable,
      type: :float,
      current_value: 0.5,
      range: {0.0, 1.0},
      learning_rate: 0.01,
      momentum: 0.9,
      gradient_estimate: 0.0,
      velocity: 0.0,
      optimization_history: [],
      bounds_behavior: :clamp,
      coordination_scope: :local,
      affected_agents: [],
      adaptation_strategy: :gradient_optimization
    }
    
    merged_state = Map.merge(default_state, initial_state)
    
    # Create agent struct using the module's generated new/2 function
    agent = __MODULE__.new(id, merged_state)
    
    # Start the Jido server with the agent struct and routes
    Jido.Agent.Server.start_link([
      agent: agent,
      routes: routes
    ])
  end
  
  # Build signal routes including gradient-specific actions
  defp build_signal_routes do
    # Get base routes from CognitiveVariable
    base_routes = [
      {"change_value", Jido.Instruction.new!(
        action: Foundation.Variables.Actions.ChangeValue
      )},
      {"get_status", Jido.Instruction.new!(
        action: Foundation.Variables.Actions.GetStatus  
      )},
      {"performance_feedback", Jido.Instruction.new!(
        action: Foundation.Variables.Actions.PerformanceFeedback
      )},
      {"coordinate_agents", Jido.Instruction.new!(
        action: Foundation.Variables.Actions.CoordinateAgents
      )}
    ]
    
    # Add gradient-specific routes
    gradient_routes = [
      {"gradient_feedback", Jido.Instruction.new!(
        action: Foundation.Variables.Actions.GradientFeedback
      )}
    ]
    
    base_routes ++ gradient_routes
  end

  # Specialized lifecycle callbacks for gradient optimization

  @doc """
  Enhanced state validation for float-specific constraints.
  """
  def on_before_validate_state(agent) do
    # Validate float-specific constraints
    with {:ok, agent} <- validate_float_range(agent),
         {:ok, agent} <- validate_learning_parameters(agent),
         {:ok, agent} <- validate_bounds_behavior(agent) do
      {:ok, agent}
    end
  end

  @doc """
  Enhanced coordination after gradient optimization.
  """
  def on_after_run(agent, result, _directives) do
    Logger.debug("Cognitive Float #{agent.state.name} optimization step completed")
    
    # Handle state updates based on action results
    updated_agent = case result do
      # Handle gradient_feedback action results with full state update
      %{action: "gradient_feedback", new_state: new_state} ->
        Logger.info("Applying gradient feedback state update for #{agent.state.name}")
        %{agent | state: new_state}
      
      # Handle change_value action results
      %{action: "change_value", new_value: new_value, old_value: old_value} ->
        Logger.info("Updating agent state: #{old_value} -> #{new_value}")
        updated_state = %{agent.state | current_value: new_value}
        %{agent | state: updated_state}
      
      # No state changes for other actions (like get_status)
      _ ->
        agent
    end
    
    # Log optimization metrics if available
    if Map.has_key?(updated_agent.state, :optimization_history) and length(updated_agent.state.optimization_history) > 0 do
      latest = hd(updated_agent.state.optimization_history)
      Logger.debug("Optimization metrics: gradient=#{latest[:gradient]}, velocity=#{latest[:velocity]}")
    end
    
    {:ok, updated_agent}
  end

  @doc """
  Enhanced error handling with gradient-specific recovery.
  """
  def on_error(agent, error) do
    Logger.error("Cognitive Float #{agent.state.name} error: #{inspect(error)}")
    
    case error do
      {:gradient_overflow, _} ->
        # Reset gradient estimates and velocity
        safe_state = %{agent.state | 
          gradient_estimate: 0.0,
          velocity: 0.0,
          learning_rate: agent.state.learning_rate * 0.5  # Reduce learning rate
        }
        updated_agent = %{agent | state: safe_state}
        Logger.warning("Gradient overflow in #{agent.state.name}, resetting optimization state")
        {:ok, updated_agent}
      
      {:bounds_violation, value} ->
        # Apply bounds behavior
        corrected_value = apply_bounds_behavior(value, agent.state.range, agent.state.bounds_behavior)
        safe_state = %{agent.state | current_value: corrected_value}
        updated_agent = %{agent | state: safe_state}
        Logger.warning("Bounds violation in #{agent.state.name}, correcting to #{corrected_value}")
        {:ok, updated_agent}
      
      _ ->
        # Fall back to parent error handling
        super(agent, error)
    end
  end

  # Private validation functions

  defp validate_float_range(agent) do
    case agent.state.range do
      {min, max} when is_number(min) and is_number(max) and min < max ->
        value = agent.state.current_value
        if value >= min and value <= max do
          {:ok, agent}
        else
          corrected_value = apply_bounds_behavior(value, {min, max}, agent.state.bounds_behavior)
          updated_agent = %{agent | state: %{agent.state | current_value: corrected_value}}
          Logger.warning("Float #{agent.state.name} value corrected: #{value} -> #{corrected_value}")
          {:ok, updated_agent}
        end
      
      invalid_range ->
        Logger.error("Invalid range for float variable #{agent.state.name}: #{inspect(invalid_range)}")
        {:error, {:invalid_range, invalid_range}}
    end
  end

  defp validate_learning_parameters(agent) do
    lr = agent.state.learning_rate
    momentum = agent.state.momentum
    
    cond do
      not is_number(lr) or lr <= 0 ->
        {:error, {:invalid_learning_rate, lr}}
      
      not is_number(momentum) or momentum < 0 or momentum >= 1 ->
        {:error, {:invalid_momentum, momentum}}
      
      true ->
        {:ok, agent}
    end
  end

  defp validate_bounds_behavior(agent) do
    case agent.state.bounds_behavior do
      behavior when behavior in [:clamp, :wrap, :reject] ->
        {:ok, agent}
      
      invalid_behavior ->
        Logger.warning("Invalid bounds behavior #{invalid_behavior}, defaulting to :clamp")
        updated_agent = %{agent | state: %{agent.state | bounds_behavior: :clamp}}
        {:ok, updated_agent}
    end
  end

  # Private helper functions

  defp apply_bounds_behavior(value, {min, max}, behavior) do
    case behavior do
      :clamp ->
        max(min, min(max, value))
      
      :wrap ->
        cond do
          value < min -> max - (min - value)
          value > max -> min + (value - max)
          true -> value
        end
      
      :reject ->
        if value >= min and value <= max, do: value, else: (min + max) / 2
    end
  end

  # Dead code removal: coordinate_affected_agents/2, notify_gradient_change/2, and update_optimization_metrics/2
  # These functions were part of the old directive-based coordination system and are no longer used
  # in the new direct coordination approach where actions handle coordination directly
end