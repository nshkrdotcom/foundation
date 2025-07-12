defmodule Foundation.Variables.Actions.GradientFeedback do
  @moduledoc """
  Action for processing gradient feedback in Cognitive Float variables.
  
  This action implements gradient-based optimization with momentum, enabling
  intelligent parameter updates based on gradient information.
  """
  
  use Jido.Action,
    name: "gradient_feedback",
    description: "Processes gradient feedback for gradient-based optimization",
    category: "ml_optimization",
    tags: ["ml", "optimization", "gradient", "momentum"],
    schema: [
      gradient: [type: :float, required: true, doc: "Gradient value for optimization"],
      source: [type: :atom, doc: "Source of the gradient feedback"],
      timestamp: [type: :any, doc: "Timestamp of the gradient calculation"],
      context: [type: :map, default: %{}, doc: "Additional gradient context"],
      learning_rate_override: [type: :float, doc: "Override the agent's learning rate"],
      momentum_override: [type: :float, doc: "Override the agent's momentum"]
    ]

  require Logger

  @doc """
  Processes gradient feedback and updates the float value using momentum-based optimization.
  
  ## Parameters
  - params: Map containing gradient and optimization parameters
  - context: Jido action context containing agent and other data
  
  ## Returns
  - {:ok, result} - Result containing new state and gradient information
  """
  def run(%{gradient: gradient} = params, context) do
    # Extract agent from context - Jido provides state directly
    agent = case context do
      %{agent: agent} -> agent
      %{state: state} -> %{id: "unknown", state: state}
      _ -> %{id: "unknown", state: %{}}
    end
    source = Map.get(params, :source, :unknown)
    context = Map.get(params, :context, %{})
    lr_override = Map.get(params, :learning_rate_override)
    momentum_override = Map.get(params, :momentum_override)
    
    Logger.debug("GradientFeedback action for #{agent.state.name}: gradient=#{gradient}, source=#{source}")
    
    # Use overrides if provided, otherwise use agent's parameters
    learning_rate = lr_override || agent.state.learning_rate
    momentum = momentum_override || agent.state.momentum
    
    with {:ok, updated_state} <- apply_gradient_update(agent.state, gradient, learning_rate, momentum),
         {:ok, final_state} <- apply_bounds_constraints(updated_state),
         {:ok, history_state} <- record_optimization_step(final_state, gradient, params) do
      
      old_value = agent.state.current_value
      new_value = history_state.current_value
      
      # Trigger coordination directly
      coordinate_gradient_change(agent, old_value, new_value, history_state, context)
      
      Logger.info("Cognitive Float #{agent.state.name} gradient update: #{old_value} -> #{new_value} (gradient: #{gradient})")
      
      # Return result with new state for agent to update
      {:ok, %{
        action: "gradient_feedback",
        variable_name: agent.state.name,
        old_value: old_value,
        new_value: new_value,
        gradient: gradient,
        new_state: history_state,
        optimization_metrics: %{
          learning_rate: learning_rate,
          momentum: momentum,
          velocity: history_state.velocity,
          gradient_estimate: history_state.gradient_estimate
        },
        timestamp: DateTime.utc_now()
      }}
    else
      {:error, reason} = error ->
        Logger.warning("Gradient feedback failed for #{agent.state.name}: #{inspect(reason)}")
        error
    end
  end

  # Private optimization functions

  defp apply_gradient_update(state, gradient, learning_rate, momentum) do
    # Check for numerical stability
    if abs(gradient) > 1000.0 do
      {:error, {:gradient_overflow, gradient}}
    else
      # Update gradient estimate with momentum-based smoothing
      smoothed_gradient = momentum * state.gradient_estimate + (1 - momentum) * gradient
      
      # Update velocity using momentum (direct gradient application)
      # Positive gradient -> increase value, negative gradient -> decrease value
      new_velocity = momentum * state.velocity + learning_rate * smoothed_gradient
      
      # Calculate new value
      proposed_value = state.current_value + new_velocity
      
      # Check for numerical instability in velocity
      if abs(new_velocity) > 10.0 do
        Logger.warning("Large velocity detected (#{new_velocity}), clamping to prevent instability")
        clamped_velocity = max(-10.0, min(10.0, new_velocity))
        proposed_value = state.current_value + clamped_velocity
        
        updated_state = %{state |
          current_value: proposed_value,
          gradient_estimate: smoothed_gradient,
          velocity: clamped_velocity
        }
        
        {:ok, updated_state}
      else
        updated_state = %{state |
          current_value: proposed_value,
          gradient_estimate: smoothed_gradient,
          velocity: new_velocity
        }
        
        {:ok, updated_state}
      end
    end
  end

  defp apply_bounds_constraints(state) do
    {min, max} = state.range
    current_value = state.current_value
    bounds_behavior = state.bounds_behavior
    
    final_value = case bounds_behavior do
      :clamp ->
        max(min, min(max, current_value))
      
      :wrap ->
        cond do
          current_value < min -> max - (min - current_value)
          current_value > max -> min + (current_value - max)
          true -> current_value
        end
      
      :reject ->
        if current_value >= min and current_value <= max do
          current_value
        else
          # Reset to center and reduce velocity
          center_value = (min + max) / 2
          Logger.warning("Value #{current_value} rejected, resetting to center #{center_value}")
          center_value
        end
    end
    
    # If value was changed by bounds behavior, adjust velocity to prevent oscillation
    velocity_adjustment = if final_value != current_value do
      case bounds_behavior do
        :reject -> 0.0  # Reset velocity on rejection
        _ -> state.velocity * 0.5  # Reduce velocity to prevent immediate re-violation
      end
    else
      state.velocity
    end
    
    final_state = %{state |
      current_value: final_value,
      velocity: velocity_adjustment
    }
    
    {:ok, final_state}
  end

  defp record_optimization_step(state, gradient, params) do
    optimization_step = %{
      timestamp: Map.get(params, :timestamp, DateTime.utc_now()),
      old_value: state.current_value,  # This is actually the new value now
      gradient: gradient,
      velocity: state.velocity,
      gradient_estimate: state.gradient_estimate,
      source: Map.get(params, :source, :unknown),
      learning_rate: state.learning_rate,
      momentum: state.momentum
    }
    
    # Keep only the last 100 optimization steps to prevent memory growth
    updated_history = [optimization_step | state.optimization_history]
    |> Enum.take(100)
    
    updated_state = %{state | optimization_history: updated_history}
    {:ok, updated_state}
  end

  defp coordinate_gradient_change(agent, old_value, new_value, new_state, context) do
    # Handle coordination directly if value changed significantly
    if length(agent.state.affected_agents) > 0 and abs(new_value - old_value) > 0.001 do
      coordinate_affected_agents(agent, old_value, new_value, new_state, context)
    end
    
    # Handle global coordination via signals
    if agent.state.coordination_scope == :global and abs(new_value - old_value) > 0.001 do
      notify_gradient_change(agent, old_value, new_value, new_state, context)
    end
    
    :ok
  end
  
  defp coordinate_affected_agents(agent, old_value, new_value, new_state, context) do
    notification = %{
      type: :variable_changed,
      variable_name: agent.state.name,
      old_value: old_value,
      new_value: new_value,
      coordination_scope: agent.state.coordination_scope,
      source_agent_id: "unknown",
      optimization_info: %{
        gradient_estimate: new_state.gradient_estimate,
        velocity: new_state.velocity,
        learning_rate: new_state.learning_rate,
        optimization_type: :gradient_feedback
      },
      context: context,
      timestamp: DateTime.utc_now()
    }
    
    Enum.each(agent.state.affected_agents, fn agent_pid ->
      if Process.alive?(agent_pid) do
        send(agent_pid, {:variable_notification, notification})
      end
    end)
    
    :ok
  end
  
  defp notify_gradient_change(agent, old_value, new_value, new_state, context) do
    signal = Jido.Signal.new!(%{
      type: "cognitive_float.gradient.updated",
      source: "agent:unknown",
      subject: "jido://agent/cognitive_float/unknown",
      data: %{
        variable_name: agent.state.name,
        old_value: old_value,
        new_value: new_value,
        gradient_estimate: new_state.gradient_estimate,
        velocity: new_state.velocity,
        learning_rate: new_state.learning_rate,
        context: context,
        agent_id: "unknown"
      },
      jido_dispatch: case agent.state.coordination_scope do
        :global -> {:pubsub, topic: "cognitive_floats_global"}
        :local -> {:logger, level: :debug}
        _ -> {:logger, level: :debug}
      end
    })
    
    Jido.Signal.Dispatch.dispatch(signal, signal.jido_dispatch)
    :ok
  end
end