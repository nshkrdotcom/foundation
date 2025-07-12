defmodule Foundation.Variables.Supervisor do
  @moduledoc """
  Supervisor for Cognitive Variables - revolutionary ML parameters as intelligent agents.
  
  Each Variable is a full Jido agent with:
  - Actions: UpdateValue, CoordinateAgents, AdaptBasedOnFeedback
  - Sensors: PerformanceFeedback, AgentHealth, ClusterState
  - Skills: PerformanceAnalysis, ConflictResolution, EconomicNegotiation
  
  No abstractions, no defensive boundaries - pure agent intelligence.
  """
  
  use DynamicSupervisor
  
  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
  
  @doc """
  Start a new Cognitive Variable agent.
  """
  def start_variable(variable_type, config) do
    child_spec = {variable_type, config}
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end
  
  @doc """
  Stop a Cognitive Variable agent.
  """
  def stop_variable(variable_pid) when is_pid(variable_pid) do
    DynamicSupervisor.terminate_child(__MODULE__, variable_pid)
  end
  
  @doc """
  List all active Cognitive Variables.
  """
  def list_variables do
    DynamicSupervisor.which_children(__MODULE__)
    |> Enum.map(fn {_, pid, _, _} -> pid end)
    |> Enum.filter(&Process.alive?/1)
  end
end