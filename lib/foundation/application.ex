defmodule Foundation.Application do
  @moduledoc """
  Foundation Application Supervisor
  Manages the lifecycle of all Foundation components in a supervised manner.
  The supervision tree is designed to be fault-tolerant and to restart
  components in the correct order if failures occur.
  """
  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting Foundation application...")

    base_children = [
      # Foundation Layer Services
      # Registry must start first for service discovery
      {Foundation.ProcessRegistry, []},

      # Core foundation services with production namespace
      {Foundation.Services.ConfigServer, [namespace: :production]},
      {Foundation.Services.EventStore, [namespace: :production]},
      {Foundation.Services.TelemetryService, [namespace: :production]},

      # Infrastructure protection components
      {Foundation.Infrastructure.ConnectionManager, []},
      {Foundation.Infrastructure.RateLimiter.HammerBackend, []},

      # Task supervisor for dynamic tasks
      {Task.Supervisor, name: Foundation.TaskSupervisor}

      # Future layers will be added here:
      # Layer 1: Core capture pipeline will be added here
      # {Foundation.Capture.PipelineManager, []},
      # Layer 2: Storage and correlation will be added here
      # {Foundation.Storage.QueryCoordinator, []},
      # Layer 4: AI components will be added here
      # {Foundation.AI.Orchestrator, []},
    ]

    children = base_children ++ test_children() ++ tidewave_children()

    opts = [strategy: :one_for_one, name: Foundation.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("Foundation application started successfully")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start Foundation application: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def stop(_state) do
    Logger.info("Stopping Foundation application...")
    :ok
  end

  # Private function to add test-specific children
  defp test_children do
    if Application.get_env(:foundation, :test_mode, false) do
      [{Foundation.TestSupport.TestSupervisor, []}]
    else
      []
    end
  end

  # Private function to add Tidewave in development
  defp tidewave_children do
    if Mix.env() == :dev and Code.ensure_loaded?(Tidewave) do
      [Foundation.TidewaveEndpoint]
    else
      []
    end
  end

end
