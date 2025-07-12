defmodule DSPEx.QA.BasicQA do
  @moduledoc """
  Basic QA signature demonstrating native DSPy syntax in ElixirML.

  This is the "Hello World" for the revolutionary AI platform - proving that
  native DSPy signature syntax works in Elixir with full variable coordination.
  """

  use DSPEx.Signature

  @doc """
  Answer questions with optional context using cognitive variable coordination.
  
  Inputs:
  - question: The question to answer (required)
  - context: Additional context to help with answering (optional)
  
  Outputs:
  - answer: The generated answer
  - confidence: Confidence score (0.0-1.0)
  """
  signature "question: str, context?: str -> answer: str, confidence: float"
end