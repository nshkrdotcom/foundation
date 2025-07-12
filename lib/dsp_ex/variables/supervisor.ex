defmodule DSPEx.Variables.Supervisor do
  @moduledoc """
  Supervisor for Cognitive Variables as Jido agents.

  This supervisor manages cognitive variables that are implemented as Jido agents
  with MABEAM coordination capabilities.
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Variable registry
      {Registry, keys: :unique, name: DSPEx.Variables.Registry},

      # Global temperature variable (for QA system)
      %{
        id: "global_temperature",
        start: {DSPEx.Variables.CognitiveFloat, :start_link, [[
          name: :temperature,
          id: "global_temperature",
          initial_value: 0.7,
          valid_range: {0.0, 2.0},
          coordination_enabled: true
        ]]}
      }
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end