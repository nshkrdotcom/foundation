defmodule JidoFoundation.Application do
  @moduledoc """
  JidoFoundation application supervisor for Jido-Foundation integration.
  
  This application provides the integration bridge between Foundation infrastructure
  and Jido agent framework, enabling seamless agent operations with Foundation services.
  
  ## Integration Services
  
  - AgentBridge: Integrates Jido agents with Foundation.ProcessRegistry
  - SignalBridge: Bridges JidoSignal with Foundation.Events
  - ErrorBridge: Standardizes error handling across frameworks
  - InfrastructureBridge: Enables Jido agents to use Foundation protection
  
  ## Application Configuration
  
      config :jido_foundation,
        foundation_registry: :default,
        auto_register_agents: true,
        signal_routing_enabled: true,
        error_standardization: true,
        telemetry_integration: true
  
  ## Supervision Strategy
  
  The JidoFoundation application starts integration services that bridge
  Jido agent operations with Foundation infrastructure services.
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting JidoFoundation Integration Bridge")

    # Verify Foundation dependencies
    unless foundation_available?() do
      raise "Foundation is not available - ensure Foundation application is started first"
    end

    children = [
      # Core bridge services
      {JidoFoundation.AgentBridge.Supervisor, []},
      {JidoFoundation.SignalBridge.Router, []},
      {JidoFoundation.ErrorBridge.Registry, []},
      {JidoFoundation.TelemetryBridge.Collector, []},
      
      # Infrastructure integration
      {JidoFoundation.InfrastructureBridge.Manager, []},
      
      # Agent lifecycle management
      {JidoFoundation.AgentLifecycle.Supervisor, []}
    ]

    opts = [strategy: :one_for_one, name: JidoFoundation.Supervisor]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("JidoFoundation Integration Bridge started successfully")
        log_configuration()
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start JidoFoundation Integration Bridge: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def stop(_state) do
    Logger.info("JidoFoundation Integration Bridge stopping")
    :ok
  end

  # --- Configuration Helpers ---

  @doc """
  Gets the configured Foundation registry implementation.
  """
  @spec foundation_registry() :: term() | nil
  def foundation_registry do
    case Application.get_env(:jido_foundation, :foundation_registry, :default) do
      :default -> default_foundation_registry()
      registry -> registry
    end
  end

  @doc """
  Checks if auto-registration of Jido agents is enabled.
  """
  @spec auto_register_agents?() :: boolean()
  def auto_register_agents? do
    Application.get_env(:jido_foundation, :auto_register_agents, true)
  end

  @doc """
  Checks if signal routing between Jido and Foundation is enabled.
  """
  @spec signal_routing_enabled?() :: boolean()
  def signal_routing_enabled? do
    Application.get_env(:jido_foundation, :signal_routing_enabled, true)
  end

  @doc """
  Checks if error standardization is enabled.
  """
  @spec error_standardization_enabled?() :: boolean()
  def error_standardization_enabled? do
    Application.get_env(:jido_foundation, :error_standardization, true)
  end

  @doc """
  Checks if telemetry integration is enabled.
  """
  @spec telemetry_integration_enabled?() :: boolean()
  def telemetry_integration_enabled? do
    Application.get_env(:jido_foundation, :telemetry_integration, true)
  end

  # --- Private Helper Functions ---

  defp foundation_available? do
    # Check if Foundation application is running
    case Application.started_applications() do
      apps when is_list(apps) ->
        Enum.any?(apps, fn {app, _desc, _vsn} -> app == :foundation end)
      _ -> false
    end
  end

  defp default_foundation_registry do
    # Try to find a running Foundation registry implementation
    cond do
      Process.whereis(Foundation.ProcessRegistry) -> Foundation.ProcessRegistry
      Process.whereis(MABEAM.AgentRegistry) -> MABEAM.AgentRegistry
      true -> nil
    end
  end

  defp log_configuration do
    registry = foundation_registry()
    
    Logger.debug("""
    JidoFoundation Integration Bridge Configuration:
    - Foundation Registry: #{inspect(registry)}
    - Auto-register Agents: #{auto_register_agents?()}
    - Signal Routing: #{signal_routing_enabled?()}
    - Error Standardization: #{error_standardization_enabled?()}
    - Telemetry Integration: #{telemetry_integration_enabled?()}
    """)

    # Warn about missing configurations
    if is_nil(registry) do
      Logger.warning(
        "No Foundation registry implementation found. Agent bridge will not function properly."
      )
    end

    unless jido_available?() do
      Logger.warning(
        "Jido framework not detected. Ensure Jido dependencies are available."
      )
    end
  end

  defp jido_available? do
    # Check if Jido modules are available
    try do
      Code.ensure_loaded?(Jido.Agent) and
      Code.ensure_loaded?(Jido.Action) and
      Code.ensure_loaded?(Jido.Signal)
    rescue
      _ -> false
    end
  end
end
