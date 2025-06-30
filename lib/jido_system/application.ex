defmodule JidoSystem.Application do
  @moduledoc """
  JidoSystem application supervisor for proper agent supervision.

  Provides supervision infrastructure for JidoSystem agents following
  OTP best practices and proper separation of concerns.

  ## Supervision Strategy

  Uses a :one_for_one strategy with proper supervisors for:
  - Critical agent supervision via DynamicSupervisor
  - Agent health monitoring services
  - Error persistence and metrics collection

  ## Integration with Foundation

  JidoSystem should be added to Foundation's supervision tree:

      Foundation.Supervisor
      ├── Foundation.Services.Supervisor
      ├── MABEAM.Supervisor  
      └── JidoSystem.Supervisor  # This module
          ├── JidoSystem.AgentSupervisor (DynamicSupervisor)
          ├── JidoSystem.ErrorStore
          └── JidoSystem.HealthMonitor
  """

  use Application
  require Logger

  def start(_type, _args) do
    Logger.info("Starting JidoSystem Agent Infrastructure")

    children = [
      # Dynamic supervisor for critical agents
      {DynamicSupervisor, name: JidoSystem.AgentSupervisor, strategy: :one_for_one},

      # Error persistence service
      JidoSystem.ErrorStore,

      # Agent health monitoring
      JidoSystem.HealthMonitor,

      # Registry for Bridge agent monitoring
      {Registry, keys: :unique, name: JidoFoundation.MonitorRegistry},

      # Bridge agent monitoring supervisor (OTP compliant replacement for unsupervised processes)
      JidoFoundation.MonitorSupervisor,

      # Agent coordination manager (OTP compliant replacement for raw message passing)
      JidoFoundation.CoordinationManager,

      # Scheduler manager (OTP compliant replacement for agent self-scheduling)
      JidoFoundation.SchedulerManager,

      # Task pool manager (OTP compliant replacement for Task.async_stream)
      JidoFoundation.TaskPoolManager,

      # System command manager (OTP compliant replacement for direct System.cmd usage)
      JidoFoundation.SystemCommandManager
    ]

    # Use more lenient restart limits for testing environments
    # Note: This must be determined at compile time since Mix is not available at runtime
    {max_restarts, max_seconds} =
      case Application.get_env(:foundation, :environment, :prod) do
        # Allow many restarts in tests
        :test -> {100, 10}
        # Production limits
        _ -> {3, 5}
      end

    opts = [
      strategy: :one_for_one,
      name: JidoSystem.Supervisor,
      max_restarts: max_restarts,
      max_seconds: max_seconds
    ]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("JidoSystem Agent Infrastructure started successfully")
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start JidoSystem: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def stop(_state) do
    Logger.info("JidoSystem Agent Infrastructure stopping")
    :ok
  end

  @doc """
  Returns the child specification for starting JidoSystem under a supervisor.

  This is useful when you want to include JidoSystem as part of your application's
  supervision tree rather than as a standalone application.

  ## Examples

      children = [
        JidoSystem.Application.child_spec(),
        # ... other children
      ]

      Supervisor.start_link(children, strategy: :one_for_one)
  """
  def child_spec(opts \\ []) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start, [:normal, opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: :infinity
    }
  end
end
