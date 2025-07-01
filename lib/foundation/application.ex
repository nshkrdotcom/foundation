defmodule Foundation.Application do
  @moduledoc """
  Foundation application supervisor for protocol-based platform.

  This minimal application supervisor provides a foundation for protocol-based
  infrastructure components. Individual implementations are registered and started
  as needed by consuming applications.

  ## Application Configuration

  Configure implementations in your application config:

      config :foundation,
        registry_impl: YourApp.Registry,
        coordination_impl: YourApp.Coordination,
        infrastructure_impl: YourApp.Infrastructure

  ## Supervision Strategy

  The Foundation application uses a minimal supervision strategy since most
  actual services are provided by implementation modules in consuming applications.

  The Foundation itself provides only:
  - Protocol definitions
  - Stateless facade functions
  - Configuration management
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting Foundation Protocol Platform v2.1")

    # Foundation supervision tree with service layer architecture
    children = [
      # Task supervisor for Foundation async operations
      {Task.Supervisor, name: Foundation.TaskSupervisor},

      # Performance monitor for metrics collection
      Foundation.PerformanceMonitor,

      # Resource management for production safety
      Foundation.ResourceManager,

      # Service layer supervisor for Foundation services
      Foundation.Services.Supervisor
      
      # NOTE: JidoSystem.Application removed to break circular dependency
      # JidoSystem should be started as a separate application or
      # included in the host application's supervision tree
    ]

    opts = [strategy: :one_for_one, name: Foundation.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("Foundation Protocol Platform started successfully")
        log_configuration()
        Foundation.ConfigValidator.validate_and_log()
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start Foundation Protocol Platform: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def stop(_state) do
    Logger.info("Foundation Protocol Platform stopping")
    :ok
  end

  # --- Private Helper Functions ---

  defp log_configuration do
    registry_impl = Application.get_env(:foundation, :registry_impl)
    coordination_impl = Application.get_env(:foundation, :coordination_impl)
    infrastructure_impl = Application.get_env(:foundation, :infrastructure_impl)

    Logger.debug("""
    Foundation Protocol Platform Configuration:
    - Registry Implementation: #{inspect(registry_impl)}
    - Coordination Implementation: #{inspect(coordination_impl)}
    - Infrastructure Implementation: #{inspect(infrastructure_impl)}
    """)

    # Warn about missing implementations
    if is_nil(registry_impl) do
      Logger.warning(
        "No registry implementation configured. Foundation.Registry functions will raise errors."
      )
    end

    if is_nil(coordination_impl) do
      Logger.warning(
        "No coordination implementation configured. Foundation.Coordination functions will raise errors."
      )
    end

    if is_nil(infrastructure_impl) do
      Logger.warning(
        "No infrastructure implementation configured. Foundation.Infrastructure functions will raise errors."
      )
    end
  end
end
