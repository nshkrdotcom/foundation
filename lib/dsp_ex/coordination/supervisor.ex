defmodule DSPEx.Coordination.Supervisor do
  @moduledoc """
  Supervisor for coordination components using Jido agents with MABEAM patterns.
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Coordination registry
      {Registry, keys: :unique, name: DSPEx.Coordination.Registry}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end