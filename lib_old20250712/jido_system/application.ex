defmodule JidoSystem.Application do
  @moduledoc """
  JidoSystem application supervisor for proper agent supervision.

  Provides supervision infrastructure for JidoSystem agents following
  OTP best practices and proper separation of concerns.

  ## Supervision Strategy

  Uses a :rest_for_one strategy to ensure proper dependency ordering:
  - State persistence must start before any agents
  - Registries must start before services that use them
  - Infrastructure services must start before agents
  - If a dependency crashes, all dependent services restart

  ## Integration with Foundation

  JidoSystem depends on Foundation services and must be started after Foundation.

  Use one of these approaches:

  ### Option 1: Use FoundationJidoSupervisor (Recommended)

      # In your application.ex
      def start(_type, _args) do
        children = [
          FoundationJidoSupervisor,
          # ... your other children
        ]
        
        Supervisor.start_link(children, strategy: :one_for_one)
      end

  ### Option 2: Manual supervision tree

      # Ensure Foundation starts first
      children = [
        Foundation.Application,
        JidoSystem.Application,
        # ... your other children
      ]
      
      # Use :rest_for_one to ensure proper restart order
      Supervisor.start_link(children, strategy: :rest_for_one)

  ### Option 3: Separate OTP applications

  Configure in mix.exs to ensure Foundation starts before JidoSystem:

      def application do
        [
          extra_applications: [:foundation, :jido_system]
        ]
      end
  """

  use Application
  require Logger

  def start(_type, _args) do
    Logger.info("Starting JidoSystem Agent Infrastructure")

    # CRITICAL: Order matters with :rest_for_one strategy!
    # If a child crashes, all children started after it will be restarted
    children = [
      # 1. State persistence supervisor - MUST start first
      # This owns the ETS tables for agent state persistence
      JidoSystem.Agents.StateSupervisor,

      # 2. Registries - needed by many other processes
      {Registry, keys: :unique, name: JidoFoundation.MonitorRegistry},
      {Registry, keys: :unique, name: JidoSystem.WorkflowRegistry},

      # 3. Core infrastructure services
      JidoSystem.ErrorStore,
      JidoSystem.HealthMonitor,

      # 4. Manager services (depend on registries)
      JidoFoundation.SchedulerManager,
      JidoFoundation.TaskPoolManager,
      JidoFoundation.SystemCommandManager,
      JidoFoundation.CoordinationManager,

      # 5. Supervisors that use the managers
      JidoFoundation.MonitorSupervisor,
      JidoSystem.Supervisors.WorkflowSupervisor,

      # 6. Dynamic supervisor for agents - LAST
      # Agents depend on all infrastructure being available
      {DynamicSupervisor, name: JidoSystem.AgentSupervisor, strategy: :one_for_one}
    ]

    # FIXED: Use consistent supervision strategy for all environments
    # Tests should use Foundation.TestSupervisor for controlled crashes
    opts = [
      # CRITICAL: Dependencies respected!
      strategy: :rest_for_one,
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
