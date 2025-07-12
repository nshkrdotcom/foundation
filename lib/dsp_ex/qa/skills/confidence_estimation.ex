defmodule DSPEx.QA.Skills.ConfidenceEstimation do
  @moduledoc """
  Skill for estimating confidence in generated answers.
  """

  use Jido.Skill,
    name: "confidence_estimation",
    description: "Estimate confidence in generated answers",
    opts_key: :confidence_estimation

  def estimate_confidence(answer, context) do
    # Confidence estimation logic - will be implemented later
    {:ok, 0.8}
  end
end