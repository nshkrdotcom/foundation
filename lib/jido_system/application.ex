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
      JidoSystem.HealthMonitor
    ]

    opts = [
      strategy: :one_for_one,
      name: JidoSystem.Supervisor,
      max_restarts: 3,
      max_seconds: 5
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