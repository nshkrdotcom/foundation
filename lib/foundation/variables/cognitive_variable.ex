defmodule Foundation.Variables.CognitiveVariable do
  @moduledoc """
  Base Cognitive Variable - ML parameters as intelligent Jido agents.
  
  Revolutionary concept: Variables ARE agents that actively coordinate
  ML workflows instead of being passive configuration values.
  
  This is now a proper Jido.Agent implementation that uses:
  - Actions instead of GenServer handlers
  - Signal-based communication for coordination
  - Proper state validation through schema
  - Directive-based state management
  """
  
  use Jido.Agent,
    name: "cognitive_variable",
    description: "ML parameter as intelligent coordination primitive",
    category: "ml_optimization",
    tags: ["ml", "optimization", "coordination"],
    vsn: "1.0.0",
    schema: [
      name: [type: :atom, required: true],
      type: [type: :atom, default: :float],
      current_value: [type: :any, required: true],
      range: [type: :any],
      coordination_scope: [type: :atom, default: :local],
      affected_agents: [type: {:list, :pid}, default: []],
      adaptation_strategy: [type: :atom, default: :performance_feedback]
    ],
    actions: [
      Foundation.Variables.Actions.ChangeValue,
      Foundation.Variables.Actions.PerformanceFeedback,
      Foundation.Variables.Actions.CoordinateAgents,
      Foundation.Variables.Actions.GetStatus
    ]

  require Logger

  @doc """
  Creates a new Cognitive Variable agent with specified parameters.
  
  ## Parameters
  - id: Unique identifier for the agent
  - initial_state: Map containing variable configuration
  
  ## Examples
      agent = CognitiveVariable.create("temp_var", %{
        name: :temperature,
        type: :float,
        current_value: 0.7,
        range: {0.0, 2.0},
        coordination_scope: :local
      })
  """
  def create(id, initial_state \\ %{}) do
    # Set defaults for cognitive variable
    default_state = %{
      name: :default_variable,
      type: :float,
      current_value: 0.5,
      range: {0.0, 1.0},
      coordination_scope: :local,
      affected_agents: [],
      adaptation_strategy: :performance_feedback
    }
    
    merged_state = Map.merge(default_state, initial_state)
    
    # Create signal routes for all supported actions
    routes = build_signal_routes()
    
    # Start agent server with explicit route configuration
    # Note: Use start_link directly with routes instead of separate steps
    start_link([
      id: id,
      initial_state: merged_state,
      routes: routes
    ])
  end
  
  # Override start_link to support routes
  def start_link(opts) do
    id = Keyword.get(opts, :id) || Jido.Util.generate_id()
    initial_state = Keyword.get(opts, :initial_state, %{})
    routes = Keyword.get(opts, :routes, [])
    
    # Set defaults for cognitive variable  
    default_state = %{
      name: :default_variable,
      type: :float,
      current_value: 0.5,
      range: {0.0, 1.0},
      coordination_scope: :local,
      affected_agents: [],
      adaptation_strategy: :performance_feedback
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
  
  # Build signal routes that map signal types to action instructions
  defp build_signal_routes do
    [
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
  end

  # Lifecycle callbacks for agent coordination

  @doc """
  Called before state validation to ensure cognitive variable constraints.
  """
  def on_before_validate_state(agent) do
    # Ensure value is within range if range is specified
    case Map.get(agent.state, :range) do
      {min, max} when is_number(agent.state.current_value) ->
        if agent.state.current_value >= min and agent.state.current_value <= max do
          {:ok, agent}
        else
          Logger.warning("Cognitive variable #{agent.state.name} value #{agent.state.current_value} outside range #{inspect(agent.state.range)}")
          # Clamp to range
          clamped_value = max(min, min(max, agent.state.current_value))
          updated_agent = %{agent | state: %{agent.state | current_value: clamped_value}}
          {:ok, updated_agent}
        end
      _ ->
        {:ok, agent}
    end
  end

  @doc """
  Called after successful execution to handle state updates and coordination.
  """
  def on_after_run(agent, result, _directives) do
    Logger.debug("Cognitive Variable #{agent.state.name} executed successfully with result: #{inspect(result)}")
    
    # Handle state updates based on action results
    updated_agent = case result do
      # Handle change_value action results
      %{action: "change_value", new_value: new_value, old_value: old_value} ->
        Logger.info("Updating agent state: #{old_value} -> #{new_value}")
        updated_state = %{agent.state | current_value: new_value}
        %{agent | state: updated_state}
      
      # Handle gradient_feedback action results 
      %{action: "gradient_feedback", new_state: new_state} ->
        Logger.info("Applying gradient feedback state update")
        %{agent | state: new_state}
      
      # No state changes for other actions (like get_status)
      _ ->
        Logger.debug("No state update needed for result: #{inspect(result)}")
        agent
    end
    
    {:ok, updated_agent}
  end

  @doc """
  Called when errors occur during execution.
  """
  def on_error(agent, error) do
    Logger.error("Cognitive Variable #{agent.state.name} error: #{inspect(error)}")
    
    # Reset to safe state if needed
    case error do
      {:validation_error, _} ->
        # Reset to default value within range
        safe_value = get_safe_default_value(agent.state)
        updated_agent = %{agent | state: %{agent.state | current_value: safe_value}}
        {:ok, updated_agent}
      _ ->
        {:error, error}
    end
  end

  # Private helper functions

  # Dead code removal: coordinate_affected_agents/2 and notify_value_change/2
  # These functions were part of the old directive-based coordination system
  # and are no longer used in the new direct coordination approach

  defp get_safe_default_value(state) do
    case state.range do
      {min, max} -> (min + max) / 2
      _ -> 0.5
    end
  end
end