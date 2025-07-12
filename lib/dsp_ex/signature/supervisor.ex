defmodule DSPEx.Signature.Supervisor do
  @moduledoc """
  Supervisor for DSPy signature syntax support components.
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Signature registry for compiled signatures
      {Registry, keys: :unique, name: DSPEx.Signature.Registry}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end