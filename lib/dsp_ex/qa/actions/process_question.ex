defmodule DSPEx.QA.Actions.ProcessQuestion do
  @moduledoc """
  Core action for processing questions with cognitive variable coordination.

  This action demonstrates the complete DSPEx pipeline:
  1. Get current variable values (e.g., temperature)
  2. Validate input against DSPy signature  
  3. Process using coordinated variables
  4. Validate output against signature
  5. Update performance statistics
  """

  use Jido.Action,
    name: "process_question",
    description: "Process questions with cognitive variable coordination",
    schema: [
      question: [type: :string, required: true, doc: "Question to process"],
      context: [type: :string, default: "", doc: "Optional context for the question"]
    ]

  require Logger

  alias DSPEx.QA.BasicQA
  alias DSPEx.Signature

  @impl true
  def run(%{question: question} = params, context) do
    question_context = Map.get(params, :context, "")
    
    Logger.debug("Processing question: #{String.slice(question, 0, 50)}...")

    with {:ok, input_data} <- prepare_input_data(question, question_context),
         {:ok, validated_input} <- validate_input(input_data),
         {:ok, current_vars} <- get_current_variables(),
         {:ok, answer_data} <- generate_answer(validated_input, current_vars),
         {:ok, validated_output} <- validate_answer_output(answer_data) do
      
      Logger.info("Successfully processed question with confidence: #{validated_output.confidence}")
      {:ok, validated_output}
    else
      {:error, reason} = error ->
        Logger.warning("Failed to process question: #{inspect(reason)}")
        error
    end
  end

  ## Private Implementation

  defp prepare_input_data(question, context) do
    input_data = %{
      question: question
    }
    
    # Only add context if it's provided and non-empty
    input_data = if context != "" do
      Map.put(input_data, :context, context)
    else
      input_data
    end
    
    {:ok, input_data}
  end

  defp validate_input(input_data) do
    signature = BasicQA.__signature__()
    
    case Signature.validate_input(signature, input_data) do
      {:ok, validated} -> {:ok, validated}
      {:error, reason} -> {:error, "Input validation failed: #{reason}"}
    end
  end

  defp get_current_variables() do
    # Get current temperature from cognitive variable
    case DSPEx.Variables.CognitiveFloat.get_value(:temperature) do
      {:ok, temperature} ->
        variables = %{
          temperature: temperature,
          timestamp: DateTime.utc_now()
        }
        {:ok, variables}
        
      {:error, reason} ->
        Logger.warning("Failed to get temperature variable: #{inspect(reason)}")
        # Use default temperature
        {:ok, %{temperature: 0.7, timestamp: DateTime.utc_now()}}
    end
  end

  defp generate_answer(input_data, variables) do
    # Mock LLM processing with variable coordination
    question = input_data.question
    context = Map.get(input_data, :context, "")
    temperature = variables.temperature

    # Simulate processing time based on temperature
    # Higher temperature = more creative = longer processing
    processing_time = trunc(50 + (temperature * 100))
    Process.sleep(processing_time)

    # Generate mock answer with temperature influence
    {answer, confidence} = generate_mock_answer(question, context, temperature)

    answer_data = %{
      answer: answer,
      confidence: confidence,
      processing_time_ms: processing_time,
      temperature_used: temperature,
      model_type: :mock_llm
    }

    {:ok, answer_data}
  end

  defp generate_mock_answer(question, context, temperature) do
    # Simple mock implementation that varies with temperature
    base_answers = [
      "Based on the information provided, the answer is that this is a demonstration of DSPEx cognitive variables.",
      "The DSPEx system uses revolutionary cognitive variables to coordinate AI processing.",
      "This question demonstrates the integration of Jido agents with MABEAM coordination patterns.",
      "The answer involves advanced multi-agent coordination using Foundation infrastructure."
    ]

    # Temperature affects creativity and confidence
    # Lower temperature = more deterministic, higher confidence
    # Higher temperature = more creative, variable confidence
    
    answer_index = if temperature < 0.3 do
      0  # Always first answer for low temperature
    else
      # Random selection for higher temperatures
      :rand.uniform(length(base_answers)) - 1
    end

    base_answer = Enum.at(base_answers, answer_index)
    
    # Add context if provided
    answer = if context != "" and context != nil do
      "#{base_answer} Context: #{String.slice(context, 0, 100)}"
    else
      base_answer
    end

    # Confidence inversely related to temperature for demo
    confidence = max(0.1, min(1.0, 1.0 - (temperature * 0.3)))

    {answer, confidence}
  end

  defp validate_answer_output(answer_data) do
    signature = BasicQA.__signature__()
    
    output_data = %{
      answer: answer_data.answer,
      confidence: answer_data.confidence
    }
    
    case Signature.validate_output(signature, output_data) do
      {:ok, validated} ->
        # Add back the extra metadata
        result = Map.merge(validated, %{
          processing_time_ms: answer_data.processing_time_ms,
          temperature_used: answer_data.temperature_used,
          model_type: answer_data.model_type
        })
        {:ok, result}
        
      {:error, reason} -> 
        {:error, "Output validation failed: #{reason}"}
    end
  end

end