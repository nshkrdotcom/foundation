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
  ├── Foundation.MonitorManager
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

    # Extract service options if provided (for customization, not just tests)
    service_opts = Keyword.get(opts, :service_opts, [])

    children =
      [
        # OTP Infrastructure: Monitor manager for leak prevention
        {Foundation.MonitorManager, service_opts[:monitor_manager] || []},
        # Core service: Retry service for resilient operations
        {Foundation.Services.RetryService, service_opts[:retry_service] || []},
        # Infrastructure service: HTTP connection manager
        {Foundation.Services.ConnectionManager, service_opts[:connection_manager] || []},
        # Infrastructure service: Rate limiter
        {Foundation.Services.RateLimiter, service_opts[:rate_limiter] || []},
        # Signal service: Jido Signal Bus for event routing
        {Foundation.Services.SignalBus, service_opts[:signal_bus] || []}
      ] ++
        get_otp_cleanup_children(service_opts) ++
        get_telemetry_children(service_opts) ++ get_sia_children(service_opts)

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

  # Gets OTP cleanup children (singleton services)
  # Only include if not in test mode or explicitly requested
  defp get_otp_cleanup_children(service_opts) do
    # Skip these in test mode unless explicitly included
    if Keyword.get(
         service_opts,
         :include_otp_cleanup,
         !Application.get_env(:foundation, :test_mode, false)
       ) do
      [
        # Feature flags service for gradual rollout
        {Foundation.FeatureFlags, service_opts[:feature_flags] || []},
        # ETS-based agent registry (OTP cleanup phase)
        {Foundation.Protocols.RegistryETS, service_opts[:registry_ets] || []}
      ]
    else
      []
    end
  end

  # Gets telemetry children (OTP cleanup phase)
  defp get_telemetry_children(service_opts) do
    if Keyword.get(
         service_opts,
         :include_telemetry,
         !Application.get_env(:foundation, :test_mode, false)
       ) do
      telemetry_children = []

      # Add SpanManager for span context management
      telemetry_children =
        if Code.ensure_loaded?(Foundation.Telemetry.SpanManager) do
          opts = service_opts[:span_manager] || []
          [{Foundation.Telemetry.SpanManager, opts} | telemetry_children]
        else
          telemetry_children
        end

      # Add SampledEvents server if module is available
      telemetry_children =
        if Code.ensure_loaded?(Foundation.Telemetry.SampledEvents.Server) do
          opts = service_opts[:sampled_events_server] || []
          [{Foundation.Telemetry.SampledEvents.Server, opts} | telemetry_children]
        else
          telemetry_children
        end

      # Add Telemetry.Sampler if available and configured
      telemetry_children =
        if Code.ensure_loaded?(Foundation.Telemetry.Sampler) and
             Application.get_env(:foundation, :telemetry_sampling, %{})[:enabled] do
          opts = service_opts[:telemetry_sampler] || []
          [{Foundation.Telemetry.Sampler, opts} | telemetry_children]
        else
          telemetry_children
        end

      telemetry_children
    else
      []
    end
  end

  # Gets SIA (Service Integration Architecture) children based on module availability.
  # Gracefully handles cases where SIA modules may not be loaded.
  defp get_sia_children(service_opts) do
    sia_children = []

    # Add DependencyManager if available
    sia_children =
      if Code.ensure_loaded?(Foundation.ServiceIntegration.DependencyManager) do
        opts = service_opts[:dependency_manager] || []
        [{Foundation.ServiceIntegration.DependencyManager, opts} | sia_children]
      else
        Logger.debug("Foundation.ServiceIntegration.DependencyManager not available, skipping")
        sia_children
      end

    # Add HealthChecker if available
    sia_children =
      if Code.ensure_loaded?(Foundation.ServiceIntegration.HealthChecker) do
        opts = service_opts[:health_checker] || []
        [{Foundation.ServiceIntegration.HealthChecker, opts} | sia_children]
      else
        Logger.debug("Foundation.ServiceIntegration.HealthChecker not available, skipping")
        sia_children
      end

    # Reverse to maintain expected order (DependencyManager first, then HealthChecker)
    Enum.reverse(sia_children)
  end
end
