defmodule DSPEx.Variables.Sensors.AgentHealthMonitor do
  @moduledoc """
  Sensor for monitoring the health of affected agents.
  """

  use Jido.Sensor,
    name: "agent_health_monitor",
    description: "Monitor the health of affected agents"

  @impl true
  def sense(_agent, _state) do
    # Agent health monitoring logic - will be implemented later
    {:ok, %{status: :healthy}}
  end
end