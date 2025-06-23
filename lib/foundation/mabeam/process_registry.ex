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

  @doc """
  Get agent statistics (if implemented).
  """
  @spec get_agent_stats(Types.agent_id()) :: {:ok, map()} | {:error, :not_implemented | :not_found}
  def get_agent_stats(agent_id) do
    GenServer.call(__MODULE__, {:get_agent_stats, agent_id})
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
        {:ok, supervisor_pid} = DynamicSupervisor.start_link(
          name: supervisor_name,
          strategy: :one_for_one
        )
        
        state = %{
          backend: backend_module,
          backend_state: backend_state,
          supervisor: supervisor_pid,
          agent_monitors: %{},  # pid -> {agent_id, monitor_ref}
          agent_pids: %{}       # agent_id -> pid
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
  def handle_info({:DOWN, monitor_ref, :process, pid, reason}, state) do
    case Map.get(state.agent_monitors, pid) do
      {agent_id, ^monitor_ref} ->
        Logger.info("Agent #{agent_id} crashed with reason: #{inspect(reason)}")
        
        # Update agent status in backend
        state.backend.update_agent_status(agent_id, :failed, nil)
        
        # Clean up monitoring state
        new_agent_monitors = Map.delete(state.agent_monitors, pid)
        new_agent_pids = Map.delete(state.agent_pids, agent_id)
        
        new_state = %{state | 
          agent_monitors: new_agent_monitors,
          agent_pids: new_agent_pids
        }
        
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
    if not is_map(config) do
      {:error, {:invalid_config, "must be a map"}}
    else
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
    end
  end

  defp start_agent_process(agent_id, state) do
    case state.backend.get_agent(agent_id) do
      {:ok, agent_entry} ->
        case agent_entry.status do
          status when status in [:registered, :stopped] ->
            case start_supervised_agent(agent_entry, state) do
              {:ok, pid} ->
                # Update backend with new status and pid
                state.backend.update_agent_status(agent_id, :running, pid)
                
                # Set up monitoring
                monitor_ref = Process.monitor(pid)
                new_agent_monitors = Map.put(state.agent_monitors, pid, {agent_id, monitor_ref})
                new_agent_pids = Map.put(state.agent_pids, agent_id, pid)
                
                new_state = %{state |
                  agent_monitors: new_agent_monitors,
                  agent_pids: new_agent_pids
                }
                
                {:ok, pid, new_state}
                
              {:error, reason} ->
                {:error, reason}
            end
            
          :running ->
            {:error, :already_running}
            
          other_status ->
            {:error, {:invalid_status, other_status}}
        end
        
      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  defp start_supervised_agent(agent_entry, state) do
    child_spec = %{
      id: agent_entry.id,
      start: {agent_entry.config.module, :start_link, [agent_entry.config.args]},
      restart: :temporary,  # We handle restarts at registry level
      type: :worker
    }
    
    DynamicSupervisor.start_child(state.supervisor, child_spec)
  end

  defp stop_agent_process(agent_id, state) do
    case Map.get(state.agent_pids, agent_id) do
      nil ->
        # Check if agent is registered but not running
        case state.backend.get_agent(agent_id) do
          {:ok, _agent_entry} -> {:error, :not_running}
          {:error, :not_found} -> {:error, :not_found}
        end
        
      pid ->
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
        
        new_state = %{state |
          agent_monitors: new_agent_monitors,
          agent_pids: new_agent_pids
        }
        
        {:ok, new_state}
    end
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
end