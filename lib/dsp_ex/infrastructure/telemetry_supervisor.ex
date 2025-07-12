defmodule DSPEx.Infrastructure.TelemetrySupervisor do
  @moduledoc """
  Basic telemetry infrastructure for DSPEx.
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Basic metrics collection will be added here as needed
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end