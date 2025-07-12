defmodule DSPEx.QA.Sensors.PerformanceMonitor do
  @moduledoc """
  Sensor for monitoring QA processing performance.
  """

  use Jido.Sensor,
    name: "qa_performance_monitor",
    description: "Monitor QA processing performance"

  @impl true
  def sense(_agent, _state) do
    # Performance monitoring - will be implemented later
    {:ok, %{status: :monitoring}}
  end
end