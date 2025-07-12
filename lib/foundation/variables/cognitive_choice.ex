defmodule Foundation.Variables.CognitiveChoice do
  @moduledoc """
  Cognitive Choice Variable - Intelligent categorical selection with multi-armed bandits.
  """
  
  use GenServer
  require Logger
  
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  def init(opts) do
    choices = Keyword.get(opts, :choices, [:option_a, :option_b])
    
    state = %{
      name: Keyword.get(opts, :name, :choice_variable),
      type: :choice,
      current_value: Keyword.get(opts, :default, hd(choices)),
      choices: choices,
      choice_weights: initialize_choice_weights(choices),
      selection_history: [],
      exploration_rate: Keyword.get(opts, :exploration_rate, 0.1),
      exploration_strategy: Keyword.get(opts, :exploration_strategy, :epsilon_greedy),
      coordination_scope: Keyword.get(opts, :coordination_scope, :local),
      affected_agents: Keyword.get(opts, :affected_agents, []),
      adaptation_strategy: Keyword.get(opts, :adaptation_strategy, :performance_feedback)
    }
    
    Logger.info("Cognitive Choice Variable initialized: #{state.name} with choices #{inspect(choices)}")
    {:ok, state}
  end
  
  def handle_call({:get_status}, _from, state) do
    status = %{
      name: state.name,
      type: state.type,
      current_value: state.current_value,
      choices: state.choices,
      exploration_rate: state.exploration_rate,
      exploration_strategy: state.exploration_strategy
    }
    {:reply, status, state}
  end
  
  def handle_call({:get_value}, _from, state) do
    {:reply, state.current_value, state}
  end
  
  def handle_call({:select_choice}, _from, state) do
    # Select choice based on exploration strategy
    selected_choice = case state.exploration_strategy do
      :epsilon_greedy ->
        epsilon_greedy_selection(state.choices, state)
      :ucb ->
        ucb_selection(state.choices, state)
      :thompson_sampling ->
        thompson_sampling_selection(state.choices, state)
      _ ->
        Enum.random(state.choices)
    end
    
    # Record selection
    selection_record = %{
      timestamp: DateTime.utc_now(),
      choice: selected_choice,
      strategy: state.exploration_strategy
    }
    
    updated_state = %{state |
      current_value: selected_choice,
      selection_history: [selection_record | state.selection_history] |> Enum.take(1000)
    }
    
    Logger.debug("Choice variable #{state.name} selected: #{selected_choice}")
    {:reply, selected_choice, updated_state}
  end
  
  def handle_cast({:choice_outcome, choice, outcome}, state) do
    # Update choice weights based on outcome
    current_weight = Map.get(state.choice_weights, choice, 0.5)
    
    # Simple weight update based on outcome (0.0 to 1.0)
    learning_rate = 0.1
    new_weight = current_weight + learning_rate * (outcome - current_weight)
    
    updated_weights = Map.put(state.choice_weights, choice, new_weight)
    
    updated_state = %{state | choice_weights: updated_weights}
    
    Logger.debug("Choice variable #{state.name} updated weight for #{choice}: #{current_weight} -> #{new_weight}")
    {:noreply, updated_state}
  end
  
  def handle_cast({:performance_feedback, feedback}, state) do
    if state.adaptation_strategy == :performance_feedback do
      # Update weight for current choice based on performance
      choice_outcome = feedback.performance
      handle_cast({:choice_outcome, state.current_value, choice_outcome}, state)
    else
      {:noreply, state}
    end
  end
  
  def handle_info(_msg, state) do
    {:noreply, state}
  end
  
  # === Private Implementation ===
  
  defp initialize_choice_weights(choices) do
    choices
    |> Enum.map(fn choice -> {choice, 0.5} end)
    |> Map.new()
  end
  
  defp epsilon_greedy_selection(choices, state) do
    if :rand.uniform() < state.exploration_rate do
      # Exploration: random choice
      Enum.random(choices)
    else
      # Exploitation: choose best known choice
      choices
      |> Enum.max_by(fn choice ->
        Map.get(state.choice_weights, choice, 0.0)
      end)
    end
  end
  
  defp ucb_selection(choices, state) do
    total_selections = length(state.selection_history)
    
    if total_selections == 0 do
      Enum.random(choices)
    else
      choices
      |> Enum.max_by(fn choice ->
        choice_count = count_choice_selections(choice, state.selection_history)
        average_reward = Map.get(state.choice_weights, choice, 0.0)
        
        if choice_count > 0 do
          confidence_interval = :math.sqrt(2 * :math.log(total_selections) / choice_count)
          average_reward + confidence_interval
        else
          Float.max_finite()  # Infinite confidence for unselected choices
        end
      end)
    end
  end
  
  defp thompson_sampling_selection(choices, state) do
    # Simplified Thompson sampling using Beta distribution approximation
    choices
    |> Enum.max_by(fn choice ->
      weight = Map.get(state.choice_weights, choice, 0.5)
      # Sample from approximated Beta distribution
      :rand.uniform() * weight
    end)
  end
  
  defp count_choice_selections(choice, history) do
    Enum.count(history, fn record -> record.choice == choice end)
  end
end