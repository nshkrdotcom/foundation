defmodule Foundation.MABEAM.ProcessRegistry do
  @moduledoc """
  Advanced process lifecycle management for MABEAM agents.

  Provides fault-tolerant agent registration, lifecycle management, and discovery
  with pluggable backend storage. Designed for single-node deployment with
  future distribution readiness.

  ## Features

  - Agent registration with validation
  - Agent lifecycle management (start, stop, restart)
  - Capability-based agent discovery
  - Health monitoring and status tracking
  - Pluggable backend storage
  - Fault-tolerant operations with OTP supervision
  - Telemetry integration

  ## Usage

      # Start the registry
      {:ok, pid} = ProcessRegistry.start_link([])

      # Register an agent
      config = Types.new_agent_config(:worker, MyWorker, [])
      :ok = ProcessRegistry.register_agent(config)

      # Start the agent
      {:ok, agent_pid} = ProcessRegistry.start_agent(:worker)

      # Find agents by capability
      {:ok, agents} = ProcessRegistry.find_agents_by_capability([:nlp])
  """

  use GenServer
  require Logger

  alias Foundation.MABEAM.{Types, ProcessRegistry.Backend.LocalETS}

  @type agent_info :: map()
  @type agent_status :: :registered | :starting | :running | :stopping | :stopped | :failed

  # Public API

  @doc """
  Start the ProcessRegistry with optional configuration.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register an agent configuration in the registry.
  """
  @spec register_agent(Types.agent_config()) :: :ok | {:error, term()}
  def register_agent(config) do
    GenServer.call(__MODULE__, {:register_agent, config})
  end

  @doc """
  Start a registered agent.
  """
  @spec start_agent(Types.agent_id()) :: {:ok, pid()} | {:error, term()}
  def start_agent(agent_id) do
    GenServer.call(__MODULE__, {:start_agent, agent_id})
  end

  @doc """
  Stop a running agent.
  """
  @spec stop_agent(Types.agent_id()) :: :ok | {:error, term()}
  def stop_agent(agent_id) do
    GenServer.call(__MODULE__, {:stop_agent, agent_id})
  end

  @doc """
  Get agent information.
  """
  @spec get_agent_info(Types.agent_id()) :: {:ok, agent_info()} | {:error, :not_found}
  def get_agent_info(agent_id) do
    GenServer.call(__MODULE__, {:get_agent_info, agent_id})
  end

  @doc """
  Get agent status.
  """
  @spec get_agent_status(Types.agent_id()) :: {:ok, agent_status()} | {:error, :not_found}
  def get_agent_status(agent_id) do
    GenServer.call(__MODULE__, {:get_agent_status, agent_id})
  end

  @doc """
  List all registered agents.
  """
  @spec list_agents() :: {:ok, [agent_info()]}
  def list_agents do
    GenServer.call(__MODULE__, {:list_agents, []})
  end

  @doc """
  List agents with optional filters.
  """
  @spec list_agents(keyword()) :: {:ok, [agent_info()]} | {:error, :not_supported}
  def list_agents(filters) when is_list(filters) do
    GenServer.call(__MODULE__, {:list_agents, filters})
  end

  @doc """
  Find agents by capability.
  """
  @spec find_agents_by_capability([atom()]) :: {:ok, [Types.agent_id()]} | {:error, term()}
  def find_agents_by_capability(capabilities) when is_list(capabilities) do
    GenServer.call(__MODULE__, {:find_agents_by_capability, capabilities})
  end

  @spec find_by_capability([atom()]) :: [Types.agent_id()]
  def find_by_capability(capabilities) when is_list(capabilities) do
    case find_agents_by_capability(capabilities) do
      {:ok, agent_ids} -> agent_ids
      {:error, _} -> []
    end
  end

  @doc """
  Get agent statistics (if implemented).
  """
  @spec get_agent_stats(Types.agent_id()) :: {:ok, map()} | {:error, :not_implemented | :not_found}
  def get_agent_stats(agent_id) do
    GenServer.call(__MODULE__, {:get_agent_stats, agent_id})
  end

  @doc """
  Get the PID of a running agent.
  """
  @spec get_agent_pid(Types.agent_id()) :: {:ok, pid()} | {:error, :not_found | :not_running}
  def get_agent_pid(agent_id) do
    GenServer.call(__MODULE__, {:get_agent_pid, agent_id})
  end

  @doc """
  Restart a stopped or failed agent.
  """
  @spec restart_agent(Types.agent_id()) :: :ok | {:error, term()}
  def restart_agent(agent_id) do
    GenServer.call(__MODULE__, {:restart_agent, agent_id})
  end

  @doc """
  Find agents by their type.
  """
  @spec find_agents_by_type(Types.agent_type()) :: {:ok, [Types.agent_id()]} | {:error, term()}
  def find_agents_by_type(agent_type) do
    GenServer.call(__MODULE__, {:find_agents_by_type, agent_type})
  end

  @doc """
  Get the health status of an agent.
  """
  @spec get_agent_health(Types.agent_id()) ::
          {:ok, :healthy | :degraded | :unhealthy} | {:error, term()}
  def get_agent_health(agent_id) do
    GenServer.call(__MODULE__, {:get_agent_health, agent_id})
  end

  # GenServer Callbacks

  @impl true
  def init(opts) do
    # Initialize backend
    backend_module = Keyword.get(opts, :backend, LocalETS)
    backend_opts = Keyword.get(opts, :backend_opts, [])

    case backend_module.init(backend_opts) do
      {:ok, backend_state} ->
        # Start dynamic supervisor for agents
        supervisor_name = Module.concat(__MODULE__, DynamicSupervisor)

        {:ok, supervisor_pid} =
          DynamicSupervisor.start_link(
            name: supervisor_name,
            strategy: :one_for_one
          )

        state = %{
          backend: backend_module,
          backend_state: backend_state,
          supervisor: supervisor_pid,
          # pid -> {agent_id, monitor_ref}
          agent_monitors: %{},
          # agent_id -> pid
          agent_pids: %{}
        }

        {:ok, state}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:register_agent, config}, _from, state) do
    case validate_and_register_agent(config, state) do
      {:ok, new_state} ->
        emit_telemetry(:registration, %{agent_id: config.id})
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:start_agent, agent_id}, _from, state) do
    case start_agent_process(agent_id, state) do
      {:ok, pid, new_state} ->
        emit_telemetry(:start, %{agent_id: agent_id, pid: pid})
        {:reply, {:ok, pid}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:stop_agent, agent_id}, _from, state) do
    case stop_agent_process(agent_id, state) do
      {:ok, new_state} ->
        emit_telemetry(:stop, %{agent_id: agent_id})
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_agent_info, agent_id}, _from, state) do
    case state.backend.get_agent(agent_id) do
      {:ok, agent_entry} -> {:reply, {:ok, agent_entry}, state}
      {:error, :not_found} -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_agent_status, agent_id}, _from, state) do
    case state.backend.get_agent(agent_id) do
      {:ok, agent_entry} -> {:reply, {:ok, agent_entry.status}, state}
      {:error, :not_found} -> {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:list_agents, []}, _from, state) do
    agents = state.backend.list_all_agents()
    {:reply, {:ok, agents}, state}
  end

  @impl true
  def handle_call({:list_agents, filters}, _from, state) do
    case apply_filters(filters, state) do
      {:ok, filtered_agents} -> {:reply, {:ok, filtered_agents}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:find_agents_by_capability, capabilities}, _from, state) do
    case state.backend.find_agents_by_capability(capabilities) do
      {:ok, agent_ids} -> {:reply, {:ok, agent_ids}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_agent_stats, _agent_id}, _from, state) do
    # Stats not yet implemented
    {:reply, {:error, :not_implemented}, state}
  end

  @impl true
  def handle_call({:get_agent_pid, agent_id}, _from, state) do
    case Map.get(state.agent_pids, agent_id) do
      nil ->
        # Check if agent exists but not running
        case state.backend.get_agent(agent_id) do
          {:ok, _agent_entry} -> {:reply, {:error, :not_running}, state}
          {:error, :not_found} -> {:reply, {:error, :not_found}, state}
        end

      pid ->
        {:reply, {:ok, pid}, state}
    end
  end

  @impl true
  def handle_call({:restart_agent, agent_id}, _from, state) do
    case state.backend.get_agent(agent_id) do
      {:ok, agent_entry} ->
        case agent_entry.status do
          :running ->
            restart_running_agent(agent_id, state)

          status when status in [:stopped, :failed] ->
            case start_agent_process(agent_id, state) do
              {:ok, _pid, new_state} ->
                emit_telemetry(:restart, %{agent_id: agent_id})
                {:reply, :ok, new_state}

              {:error, reason} ->
                {:reply, {:error, reason}, state}
            end

          :registered ->
            {:reply, {:error, :not_started}, state}

          other_status ->
            {:reply, {:error, {:invalid_status, other_status}}, state}
        end

      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:find_agents_by_type, agent_type}, _from, state) do
    agents = state.backend.list_all_agents()

    matching_agents =
      Enum.filter(agents, fn agent ->
        agent.config.type == agent_type
      end)

    agent_ids = Enum.map(matching_agents, fn agent -> agent.id end)
    {:reply, {:ok, agent_ids}, state}
  end

  @impl true
  def handle_call({:get_agent_health, agent_id}, _from, state) do
    case state.backend.get_agent(agent_id) do
      {:ok, agent_entry} ->
        health_status =
          determine_agent_health(agent_entry, state, agent_id)

        {:reply, {:ok, health_status}, state}

      {:error, :not_found} ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_info({:DOWN, monitor_ref, :process, pid, reason}, state) do
    case Map.get(state.agent_monitors, pid) do
      {agent_id, ^monitor_ref} ->
        Logger.info("Agent #{agent_id} crashed with reason: #{inspect(reason)}")

        # Update agent status in backend
        state.backend.update_agent_status(agent_id, :failed, nil)

        # Clean up monitoring state
        new_agent_monitors = Map.delete(state.agent_monitors, pid)
        new_agent_pids = Map.delete(state.agent_pids, agent_id)

        new_state = %{state | agent_monitors: new_agent_monitors, agent_pids: new_agent_pids}

        emit_telemetry(:crash, %{agent_id: agent_id, reason: reason})

        {:noreply, new_state}

      nil ->
        # Unknown process crashed
        {:noreply, state}
    end
  end

  # Private Functions

  defp validate_and_register_agent(config, state) do
    # Basic type check first
    if is_map(config) do
      case Types.validate_agent_config(config) do
        {:ok, validated_config} ->
          # Create agent entry
          entry = %{
            id: validated_config.id,
            config: validated_config,
            pid: nil,
            status: :registered,
            started_at: nil,
            stopped_at: nil,
            metadata: validated_config.metadata,
            node: node()
          }

          # Register in backend
          case state.backend.register_agent(entry) do
            :ok -> {:ok, state}
            {:error, reason} -> {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, {:invalid_config, "must be a map"}}
    end
  end

  defp start_agent_process(agent_id, state) do
    case state.backend.get_agent(agent_id) do
      {:ok, agent_entry} ->
        handle_agent_start(agent_entry, agent_id, state)

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  defp handle_agent_start(agent_entry, agent_id, state) do
    case agent_entry.status do
      status when status in [:registered, :stopped] ->
        start_and_monitor_agent(agent_entry, agent_id, state)

      :running ->
        {:error, :already_running}

      other_status ->
        {:error, {:invalid_status, other_status}}
    end
  end

  defp start_and_monitor_agent(agent_entry, agent_id, state) do
    case start_supervised_agent(agent_entry, state) do
      {:ok, pid} ->
        setup_agent_monitoring(pid, agent_id, state)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp setup_agent_monitoring(pid, agent_id, state) do
    # Update backend with new status and pid
    state.backend.update_agent_status(agent_id, :running, pid)

    # Set up monitoring
    monitor_ref = Process.monitor(pid)
    new_agent_monitors = Map.put(state.agent_monitors, pid, {agent_id, monitor_ref})
    new_agent_pids = Map.put(state.agent_pids, agent_id, pid)

    new_state = %{
      state
      | agent_monitors: new_agent_monitors,
        agent_pids: new_agent_pids
    }

    {:ok, pid, new_state}
  end

  defp start_supervised_agent(agent_entry, state) do
    child_spec = %{
      id: agent_entry.id,
      start: {agent_entry.config.module, :start_link, [agent_entry.config.args]},
      # We handle restarts at registry level
      restart: :temporary,
      type: :worker
    }

    DynamicSupervisor.start_child(state.supervisor, child_spec)
  end

  defp stop_agent_process(agent_id, state) do
    case Map.get(state.agent_pids, agent_id) do
      nil ->
        handle_stop_non_running_agent(agent_id, state)

      pid ->
        handle_stop_running_agent(agent_id, pid, state)
    end
  end

  defp handle_stop_non_running_agent(agent_id, state) do
    # Check if agent is registered but not running
    case state.backend.get_agent(agent_id) do
      {:ok, _agent_entry} -> {:error, :not_running}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  defp handle_stop_running_agent(agent_id, pid, state) do
    # Stop the process
    DynamicSupervisor.terminate_child(state.supervisor, pid)

    # Update backend status
    state.backend.update_agent_status(agent_id, :stopped, nil)

    # Clean up monitoring
    case Map.get(state.agent_monitors, pid) do
      {^agent_id, monitor_ref} ->
        Process.demonitor(monitor_ref, [:flush])

      _ ->
        :ok
    end

    new_agent_monitors = Map.delete(state.agent_monitors, pid)
    new_agent_pids = Map.delete(state.agent_pids, agent_id)

    new_state = %{state | agent_monitors: new_agent_monitors, agent_pids: new_agent_pids}

    {:ok, new_state}
  end

  defp apply_filters(filters, state) do
    cond do
      Keyword.has_key?(filters, :status) ->
        status = Keyword.get(filters, :status)

        case state.backend.get_agents_by_status(status) do
          {:ok, agents} -> {:ok, agents}
          {:error, reason} -> {:error, reason}
        end

      Keyword.has_key?(filters, :metadata) ->
        # Metadata filtering not yet fully implemented in backend
        {:error, :not_supported}

      true ->
        # No filters, return all agents
        agents = state.backend.list_all_agents()
        {:ok, agents}
    end
  end

  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:foundation, :mabeam, :agent, event],
      %{count: 1},
      metadata
    )
  end

  # Child Spec for Supervision

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  defp restart_running_agent(agent_id, state) do
    # Stop first, then start
    case stop_agent_process(agent_id, state) do
      {:ok, intermediate_state} ->
        case start_agent_process(agent_id, intermediate_state) do
          {:ok, _pid, new_state} ->
            emit_telemetry(:restart, %{agent_id: agent_id})
            {:reply, :ok, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, intermediate_state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  defp determine_agent_health(agent_entry, state, agent_id) do
    case agent_entry.status do
      :running ->
        check_running_agent_health(state, agent_id)

      # Not started yet but healthy
      :registered ->
        :healthy

      # Intentionally stopped
      :stopped ->
        :degraded

      # Failed state
      :failed ->
        :unhealthy

      # Unknown state
      _ ->
        :degraded
    end
  end

  defp check_running_agent_health(state, agent_id) do
    case Map.get(state.agent_pids, agent_id) do
      # Should be running but no PID
      nil ->
        :unhealthy

      pid ->
        if Process.alive?(pid) do
          :healthy
        else
          # Process died but not yet cleaned up
          :unhealthy
        end
    end
  end
end
