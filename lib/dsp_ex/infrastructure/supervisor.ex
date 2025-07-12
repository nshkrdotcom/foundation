defmodule DSPEx.Infrastructure.Supervisor do
  @moduledoc """
  Minimal essential infrastructure services for DSPEx.

  Provides only the core services needed for basic operation:
  - Registry for component discovery
  - Telemetry for observability
  - Basic error tracking
  """

  use Supervisor

  def start_link(init_arg) do
    Supervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    children = [
      # Component registry
      {Registry, keys: :unique, name: DSPEx.Registry},

      # Telemetry supervisor
      DSPEx.Infrastructure.TelemetrySupervisor
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end