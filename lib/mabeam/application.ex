defmodule MABEAM.Application do
  @moduledoc """
  MABEAM application supervisor for multi-agent BEAM infrastructure.

  Starts and supervises the MABEAM backend implementations for:
  - Agent Registry
  - Agent Coordination
  - Agent Infrastructure

  ## Configuration

  Configure the MABEAM application in your config:

      config :mabeam,
        registry_id: :production,
        coordination_id: :production,
        infrastructure_id: :production,
        start_backends: true

  Set `start_backends: false` if you want to manage the backends manually.

  ## Supervision Strategy

  Uses a `:rest_for_one` strategy to ensure dependencies are respected:
  1. Registry starts first (agents need to register)
  2. Coordination starts second (needs registry for agent lookup)
  3. Infrastructure starts third (may use both registry and coordination)
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    Logger.info("Starting MABEAM Multi-Agent Infrastructure")

    # Check if we should start backends
    start_backends = Application.get_env(:mabeam, :start_backends, true)

    children =
      if start_backends do
        [
          # Agent Registry - must start first
          {MABEAM.AgentRegistry,
           name: MABEAM.AgentRegistry, id: Application.get_env(:mabeam, :registry_id, :default)},

          # Agent Coordination - depends on registry
          {MABEAM.AgentCoordination,
           name: MABEAM.AgentCoordination,
           id: Application.get_env(:mabeam, :coordination_id, :default)},

          # Agent Infrastructure - may use both registry and coordination
          {MABEAM.AgentInfrastructure,
           name: MABEAM.AgentInfrastructure,
           id: Application.get_env(:mabeam, :infrastructure_id, :default)}
        ]
      else
        Logger.info("MABEAM backends disabled by configuration")
        []
      end

    # Configure Foundation to use MABEAM implementations
    configure_foundation()

    opts = [
      # If one crashes, restart it and all after it
      strategy: :rest_for_one,
      name: MABEAM.Supervisor,
      max_restarts: 3,
      max_seconds: 5
    ]

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.info("MABEAM Multi-Agent Infrastructure started successfully")
        log_configuration()
        {:ok, pid}

      {:error, reason} ->
        Logger.error("Failed to start MABEAM: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @impl true
  def stop(_state) do
    Logger.info("MABEAM Multi-Agent Infrastructure stopping")
    :ok
  end

  # --- Private Helper Functions ---

  defp configure_foundation do
    # Configure Foundation to use MABEAM implementations
    # This can be overridden in the application config

    current_registry = Application.get_env(:foundation, :registry_impl)
    current_coordination = Application.get_env(:foundation, :coordination_impl)
    current_infrastructure = Application.get_env(:foundation, :infrastructure_impl)

    if is_nil(current_registry) do
      Application.put_env(:foundation, :registry_impl, MABEAM.AgentRegistry)
      Logger.debug("Configured Foundation to use MABEAM.AgentRegistry")
    end

    if is_nil(current_coordination) do
      Application.put_env(:foundation, :coordination_impl, MABEAM.AgentCoordination)
      Logger.debug("Configured Foundation to use MABEAM.AgentCoordination")
    end

    if is_nil(current_infrastructure) do
      Application.put_env(:foundation, :infrastructure_impl, MABEAM.AgentInfrastructure)
      Logger.debug("Configured Foundation to use MABEAM.AgentInfrastructure")
    end
  end

  defp log_configuration do
    registry_id = Application.get_env(:mabeam, :registry_id, :default)
    coordination_id = Application.get_env(:mabeam, :coordination_id, :default)
    infrastructure_id = Application.get_env(:mabeam, :infrastructure_id, :default)

    Logger.debug("""
    MABEAM Configuration:
    - Registry ID: #{inspect(registry_id)}
    - Coordination ID: #{inspect(coordination_id)}
    - Infrastructure ID: #{inspect(infrastructure_id)}
    - Foundation Registry: #{inspect(Application.get_env(:foundation, :registry_impl))}
    - Foundation Coordination: #{inspect(Application.get_env(:foundation, :coordination_impl))}
    - Foundation Infrastructure: #{inspect(Application.get_env(:foundation, :infrastructure_impl))}
    """)
  end

  @doc """
  Returns the child specification for starting MABEAM under a supervisor.

  This is useful when you want to include MABEAM as part of your application's
  supervision tree rather than as a standalone application.

  ## Examples

      children = [
        MABEAM.Application.child_spec(),
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
