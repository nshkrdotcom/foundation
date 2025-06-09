defmodule GeminiIntegration.Application do
  @moduledoc """
  Sample application demonstrating Foundation and Gemini integration.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Foundation is started as a dependency, not as a child
      # Add your app's children here
      {GeminiIntegration.Worker, []}
    ]

    opts = [strategy: :one_for_one, name: GeminiIntegration.Supervisor]

    # Enable the integration after starting the supervision tree
    Foundation.Integrations.GeminiAdapter.setup()

    Supervisor.start_link(children, opts)
  end
end
