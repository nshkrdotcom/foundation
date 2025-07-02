defmodule FoundationJidoSupervisor do
  @moduledoc """
  Top-level supervisor for applications using both Foundation and JidoSystem.

  This supervisor ensures proper startup order and breaks the circular dependency
  between Foundation and JidoSystem. Foundation services start first, then JidoSystem
  can safely depend on them.

  ## Usage

  Add this to your application's supervision tree:

      def start(_type, _args) do
        children = [
          FoundationJidoSupervisor,
          # ... your other children
        ]
        
        Supervisor.start_link(children, strategy: :one_for_one)
      end
      
  Or if you need custom configuration:

      children = [
        {FoundationJidoSupervisor, [
          foundation_opts: [registry_impl: MyApp.Registry],
          jido_opts: [environment: :test]
        ]},
        # ... your other children
      ]

  ## Supervision Strategy

  Uses :rest_for_one strategy to ensure:
  1. Foundation starts first and provides core services
  2. JidoSystem starts second and can safely use Foundation services
  3. If Foundation crashes, JidoSystem is also restarted
  4. If JidoSystem crashes, Foundation remains running
  """

  use Supervisor
  require Logger

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Start all Foundation children first, then all JidoSystem children
    # This provides the same startup order as the applications would have
    children = [
      # Foundation services (copied from Foundation.Application)
      {Task.Supervisor, name: Foundation.TaskSupervisor},
      Foundation.PerformanceMonitor,
      Foundation.ResourceManager,
      Foundation.Services.Supervisor,

      # JidoSystem services (copied from JidoSystem.Application)
      {DynamicSupervisor, name: JidoSystem.AgentSupervisor, strategy: :one_for_one},
      JidoSystem.ErrorStore,
      JidoSystem.HealthMonitor,
      {Registry, keys: :unique, name: JidoFoundation.MonitorRegistry},
      JidoFoundation.MonitorSupervisor,
      JidoFoundation.CoordinationManager,
      JidoFoundation.SchedulerManager,
      JidoFoundation.TaskPoolManager,
      JidoFoundation.SystemCommandManager
    ]

    # Use rest_for_one: if Foundation crashes, JidoSystem restarts too
    # This ensures JidoSystem always has Foundation services available
    #
    # Shutdown order (reverse of startup):
    # 1. JidoSystem services shutdown first (SystemCommandManager -> JidoSystem.AgentSupervisor)
    # 2. Foundation services shutdown last (Services.Supervisor -> TaskSupervisor)
    # This prevents JidoSystem from trying to use Foundation services during shutdown
    # Use Application environment instead of Mix.env for runtime compatibility
    test_env? = Application.get_env(:foundation, :test_mode, false)
    
    supervisor_flags = %{
      strategy: :rest_for_one,
      max_restarts: if(test_env?, do: 10, else: 3),
      max_seconds: 5
    }

    Logger.info("Starting FoundationJidoSupervisor with proper dependency order")
    {:ok, {supervisor_flags, children}}
  end

  @doc """
  Returns a child specification for including this supervisor in another supervision tree.
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor,
      restart: :permanent,
      shutdown: :infinity
    }
  end
end
