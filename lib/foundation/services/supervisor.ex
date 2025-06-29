defmodule Foundation.Services.Supervisor do
  @moduledoc """
  Supervisor for Foundation service layer components.

  This supervisor manages the service layer of the Foundation architecture,
  providing a proper supervision tree for all service components while
  maintaining the protocol-based architecture.

  ## Service Architecture

  The services supervised by this module form the service layer:
  ```
  Foundation.Services.Supervisor
  ├── Foundation.Services.RetryService
  ├── Foundation.Services.ConnectionManager
  ├── Foundation.Services.RateLimiter
  ├── Foundation.Services.SignalBus
  ├── Foundation.ServiceIntegration.DependencyManager
  ├── Foundation.ServiceIntegration.HealthChecker
  ├── Foundation.Services.ConfigService (future)
  ├── Foundation.Services.ServiceDiscovery (future)
  ├── Foundation.Services.TelemetryService (future)
  └── Foundation.Services.EventStore (future)
  ```

  ## Service Integration Architecture (SIA)

  Added SIA components for service coordination and health monitoring:
  - **DependencyManager**: Service dependency registration and startup orchestration
  - **HealthChecker**: Unified health checking across all service boundaries
  - **ContractValidator**: (Stateless - used via module calls)
  - **SignalCoordinator**: (Stateless - used for test coordination)

  ## Supervision Strategy

  Uses `:one_for_one` strategy where:
  - Each service can restart independently
  - Service failures don't affect other services
  - Graceful degradation when services are unavailable

  ## Usage

  This supervisor is typically started by Foundation.Application
  but can be started independently for testing:

      {:ok, pid} = Foundation.Services.Supervisor.start_link([])
  """

  use Supervisor
  require Logger

  @doc """
  Starts the Foundation services supervisor.

  ## Options

  - `:name` - The name to register the supervisor under (default: __MODULE__)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    Logger.debug("Initializing Foundation Services Supervisor")

    # Check if this is a test supervisor with custom naming
    is_test_supervisor =
      Keyword.has_key?(opts, :name) &&
        Keyword.get(opts, :name) != __MODULE__

    children =
      if is_test_supervisor do
        # For test supervisors, start services with unique names to avoid conflicts
        supervisor_id = Keyword.get(opts, :name, __MODULE__)

        [
          # Core service: Retry service for resilient operations with unique name
          {Foundation.Services.RetryService, [name: :"#{supervisor_id}_retry_service"]},
          # Infrastructure service: HTTP connection manager with unique name
          {Foundation.Services.ConnectionManager, [name: :"#{supervisor_id}_connection_manager"]},
          # Infrastructure service: Rate limiter with unique name
          {Foundation.Services.RateLimiter, [name: :"#{supervisor_id}_rate_limiter"]},
          # Signal service: Jido Signal Bus for event routing
          {Foundation.Services.SignalBus, [name: :"#{supervisor_id}_signal_bus"]}
        ] ++ get_sia_children(true, supervisor_id)
      else
        [
          # Core service: Retry service for resilient operations
          {Foundation.Services.RetryService, []},
          # Infrastructure service: HTTP connection manager
          {Foundation.Services.ConnectionManager, []},
          # Infrastructure service: Rate limiter
          {Foundation.Services.RateLimiter, []},
          # Signal service: Jido Signal Bus for event routing
          {Foundation.Services.SignalBus, []}
        ] ++ get_sia_children(false, nil)
      end

    # Use one_for_one strategy - services can fail independently
    supervisor_opts = [
      strategy: :one_for_one,
      max_restarts: 3,
      max_seconds: 5
    ]

    Logger.info("Foundation Services Supervisor initialized with #{length(children)} services")
    Supervisor.init(children, supervisor_opts)
  end

  @doc """
  Get the list of currently supervised services.
  """
  def which_services do
    __MODULE__
    |> Supervisor.which_children()
    |> Enum.map(fn {id, _pid, _type, _modules} -> id end)
  end

  @doc """
  Check if a specific service is running.
  """
  def service_running?(service_module) do
    __MODULE__
    |> Supervisor.which_children()
    |> Enum.any?(fn {id, pid, _type, _modules} ->
      id == service_module and is_pid(pid) and Process.alive?(pid)
    end)
  end

  ## Private Functions

  # Gets SIA (Service Integration Architecture) children based on module availability.
  # Gracefully handles cases where SIA modules may not be loaded in test environments.
  defp get_sia_children(is_test_supervisor, supervisor_id) do
    sia_children = []
    
    # Add DependencyManager if available
    sia_children = 
      if Code.ensure_loaded?(Foundation.ServiceIntegration.DependencyManager) do
        opts = if is_test_supervisor do
          [name: :"#{supervisor_id}_dependency_manager", 
           table_name: :"#{supervisor_id}_dependency_table"]
        else
          []
        end
        
        [{Foundation.ServiceIntegration.DependencyManager, opts} | sia_children]
      else
        Logger.debug("Foundation.ServiceIntegration.DependencyManager not available, skipping")
        sia_children
      end
    
    # Add HealthChecker if available  
    sia_children =
      if Code.ensure_loaded?(Foundation.ServiceIntegration.HealthChecker) do
        opts = if is_test_supervisor do
          [name: :"#{supervisor_id}_health_checker"]
        else
          []
        end
        
        [{Foundation.ServiceIntegration.HealthChecker, opts} | sia_children]
      else
        Logger.debug("Foundation.ServiceIntegration.HealthChecker not available, skipping")
        sia_children
      end
    
    # Reverse to maintain expected order (DependencyManager first, then HealthChecker)
    Enum.reverse(sia_children)
  end
end
