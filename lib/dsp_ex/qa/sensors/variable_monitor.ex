defmodule DSPEx.QA.Sensors.VariableMonitor do
  @moduledoc """
  Sensor for monitoring cognitive variable changes.
  """

  use Jido.Sensor,
    name: "variable_monitor",
    description: "Monitor cognitive variable changes"

  @impl true
  def sense(_agent, _state) do
    # Variable monitoring - will be implemented later
    {:ok, %{status: :monitoring}}
  end
end