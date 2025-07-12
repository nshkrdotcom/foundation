defmodule DSPEx.Application do
  @moduledoc """
  DSPEx Application - Hybrid Jido-MABEAM Architecture for DSPy Platform

  This application implements the revolutionary DSPEx platform using:
  - Jido as the primary foundation (agents, signals, supervision)
  - Selective MABEAM integration for advanced coordination
  - Cognitive Variables as Jido agents
  - Native DSPy signature syntax support
  """

  use Application

  require Logger

  def start(_type, _args) do
    Logger.info("Starting DSPEx Application with hybrid Jido-MABEAM architecture")

    children = [
      # Foundation infrastructure (minimal essential services)
      DSPEx.Infrastructure.Supervisor,

      # Foundation MABEAM bridge (selective integration)
      DSPEx.Foundation.Bridge,

      # Core DSPEx components
      DSPEx.Variables.Supervisor,
      DSPEx.Signature.Supervisor,
      DSPEx.Coordination.Supervisor,

      # QA System components
      {DSPEx.QA.System, []}
    ]

    opts = [strategy: :one_for_one, name: DSPEx.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    Logger.info("DSPEx Application config changed: #{inspect(changed)}, removed: #{inspect(removed)}")
    :ok
  end
end