defmodule DSPEx.QA.Agent do
  @moduledoc """
  QA Agent that processes questions using cognitive variable coordination.

  This agent demonstrates the revolutionary DSPEx architecture where:
  - Agent is a full Jido agent with actions, sensors, skills
  - Variable coordination affects processing behavior
  - Foundation supervision ensures reliability
  - Native DSPy signatures define the interface
  """

  use Jido.Agent,
    name: "qa_agent",
    description: "QA Agent that processes questions using cognitive variable coordination"

  require Logger

  @actions [
    DSPEx.QA.Actions.ProcessQuestion,
    DSPEx.QA.Actions.UpdateConfiguration
  ]

  @sensors [
    DSPEx.QA.Sensors.PerformanceMonitor,
    DSPEx.QA.Sensors.VariableMonitor
  ]

  @skills [
    DSPEx.QA.Skills.AnswerGeneration,
    DSPEx.QA.Skills.ConfidenceEstimation
  ]


  def mount(agent, opts) do
    Logger.info("Mounting QA Agent: #{agent.id}")

    qa_state = %{
      model_type: Keyword.get(opts, :model_type, :mock_llm),
      temperature: 0.7,  # Will be updated by cognitive variable
      max_tokens: Keyword.get(opts, :max_tokens, 1000),
      processing_stats: %{
        questions_processed: 0,
        total_processing_time: 0,
        average_confidence: 0.0
      },
      variable_subscriptions: []
    }

    # Merge QA state into agent state
    updated_agent = %{agent | state: Map.merge(agent.state, qa_state)}

    # Subscribe to temperature variable changes
    case subscribe_to_variable(:temperature) do
      {:ok, subscription} ->
        Logger.info("QA Agent subscribed to temperature variable")
        qa_state_with_subscription = %{qa_state | variable_subscriptions: [subscription]}
        final_agent = %{updated_agent | state: Map.merge(agent.state, qa_state_with_subscription)}
        {:ok, final_agent}
        
      {:error, reason} ->
        Logger.warning("Failed to subscribe to temperature variable: #{inspect(reason)}")
        {:ok, updated_agent}
    end
  end

  ## Public API

  def start_link(config) when is_map(config) do
    agent_id = Map.get(config, :id) || Jido.Util.generate_id()
    initial_state = Map.get(config, :initial_state, %{})
    agent = __MODULE__.new(agent_id, initial_state)

    Jido.Agent.Server.start_link(
      agent: agent,
      name: agent_id
    )
  end

  def start_link(config) when is_list(config) do
    agent_id = Keyword.get(config, :id) || Jido.Util.generate_id()
    initial_state = Keyword.get(config, :initial_state, %{})
    agent = __MODULE__.new(agent_id, initial_state)

    Jido.Agent.Server.start_link(
      agent: agent,
      name: agent_id
    )
  end

  @doc """
  Process a question using the BasicQA signature and current variable values.
  """
  def process_question(agent_pid, question, opts \\ []) do
    context = Keyword.get(opts, :context, "")
    
    # For now, simulate processing - full Jido integration would use cmd
    {:ok, result} = DSPEx.QA.Actions.ProcessQuestion.run(%{
      question: question,
      context: context
    }, %{})
    
    {:ok, result}
  end

  ## Private Functions

  defp subscribe_to_variable(variable_name) do
    # In a full implementation, this would use Jido's signal system
    # For now, we'll simulate subscription
    case DSPEx.Variables.CognitiveFloat.get_value(variable_name) do
      {:ok, current_value} ->
        subscription = %{
          variable: variable_name,
          current_value: current_value,
          subscribed_at: DateTime.utc_now()
        }
        {:ok, subscription}
        
      error -> error
    end
  end
end