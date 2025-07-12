defmodule JidoFoundation.MonitorSupervisor do
  @moduledoc """
  DynamicSupervisor for managing JidoFoundation.AgentMonitor processes.

  This supervisor provides proper lifecycle management for agent monitoring
  processes, ensuring they are properly supervised and cleaned up.

  ## Features

  - Dynamic supervision of agent monitors
  - Automatic cleanup when agents die
  - Registry for monitor discovery
  - Proper shutdown procedures

  ## Usage

  This supervisor is typically started as part of the JidoSystem supervision tree:

      children = [
        JidoFoundation.MonitorSupervisor,
        # ... other children
      ]

  To start monitoring an agent:

      JidoFoundation.MonitorSupervisor.start_monitoring(agent_pid, opts)

  To stop monitoring:

      JidoFoundation.MonitorSupervisor.stop_monitoring(agent_pid)
  """

  use DynamicSupervisor
  require Logger

  @registry_name JidoFoundation.MonitorRegistry

  # Client API

  @doc """
  Starts the monitor supervisor.
  """
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts monitoring for a Jido agent.

  This replaces the unsupervised process spawning in Bridge.setup_monitoring/2.

  ## Options

  - `:health_check` - Health check function (default: process alive check)
  - `:health_check_interval` - Check interval in ms (default: 30,000)
  - `:registry` - Registry module for metadata updates (optional)

  ## Returns

  - `{:ok, monitor_pid}` - Monitor started successfully
  - `{:error, reason}` - Failed to start monitor
  """
  @spec start_monitoring(pid(), keyword()) :: DynamicSupervisor.on_start_child()
  def start_monitoring(agent_pid, opts \\ []) when is_pid(agent_pid) do
    # Check if already monitoring this agent
    case Registry.lookup(@registry_name, agent_pid) do
      [] ->
        # Not currently monitored, start new monitor
        monitor_opts =
          [
            agent_pid: agent_pid,
            health_check: Keyword.get(opts, :health_check),
            interval: Keyword.get(opts, :health_check_interval, 30_000),
            registry: Keyword.get(opts, :registry)
          ]
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)

        child_spec = JidoFoundation.AgentMonitor.child_spec(monitor_opts)

        case DynamicSupervisor.start_child(__MODULE__, child_spec) do
          {:ok, _monitor_pid} = success ->
            Logger.debug("Started agent monitor for #{inspect(agent_pid)}")
            success

          {:error, reason} = error ->
            Logger.error(
              "Failed to start agent monitor for #{inspect(agent_pid)}: #{inspect(reason)}"
            )

            error
        end

      [{monitor_pid, _}] ->
        # Already monitoring
        Logger.debug(
          "Agent #{inspect(agent_pid)} is already being monitored by #{inspect(monitor_pid)}"
        )

        {:ok, monitor_pid}
    end
  end

  @doc """
  Stops monitoring for a specific agent.
  """
  @spec stop_monitoring(pid()) :: :ok | {:error, :not_found}
  def stop_monitoring(agent_pid) when is_pid(agent_pid) do
    case Registry.lookup(@registry_name, agent_pid) do
      [{monitor_pid, _}] ->
        case DynamicSupervisor.terminate_child(__MODULE__, monitor_pid) do
          :ok ->
            Logger.debug("Stopped agent monitor for #{inspect(agent_pid)}")
            :ok

          {:error, reason} ->
            Logger.error(
              "Failed to stop agent monitor for #{inspect(agent_pid)}: #{inspect(reason)}"
            )

            {:error, reason}
        end

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Lists all currently monitored agents.
  """
  @spec list_monitored_agents() :: [pid()]
  def list_monitored_agents do
    @registry_name
    |> Registry.select([{{:"$1", :"$2", :"$3"}, [], [:"$1"]}])
  end

  @doc """
  Gets the number of currently active monitors.
  """
  @spec monitor_count() :: non_neg_integer()
  def monitor_count do
    Registry.count(@registry_name)
  end

  @doc """
  Forces a health check for all monitored agents.
  """
  @spec force_health_check_all() :: :ok
  def force_health_check_all do
    @registry_name
    |> Registry.select([{{:"$1", :"$2", :"$3"}, [], [:"$1"]}])
    |> Enum.each(&JidoFoundation.AgentMonitor.force_health_check/1)

    :ok
  end

  # DynamicSupervisor implementation

  @impl true
  def init(_opts) do
    Logger.info("JidoFoundation.MonitorSupervisor started")
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  # Utility functions

  @doc """
  Returns statistics about the monitor supervisor.
  """
  @spec stats() :: %{
          monitor_count: non_neg_integer(),
          active_monitors: non_neg_integer(),
          supervisor_pid: pid() | nil,
          registry_pid: pid() | nil
        }
  def stats do
    children = DynamicSupervisor.which_children(__MODULE__)

    %{
      monitor_count: length(children),
      active_monitors: Registry.count(@registry_name),
      supervisor_pid: Process.whereis(__MODULE__),
      registry_pid: Process.whereis(@registry_name)
    }
  end

  @doc """
  Performs health check on the monitor supervisor itself.
  """
  @spec health_check() :: :ok | {:error, :supervisor_not_alive | :registry_not_alive}
  def health_check do
    cond do
      not Process.alive?(Process.whereis(__MODULE__)) ->
        {:error, :supervisor_not_alive}

      not Process.alive?(Process.whereis(@registry_name)) ->
        {:error, :registry_not_alive}

      true ->
        :ok
    end
  end
end
