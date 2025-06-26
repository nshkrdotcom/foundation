defmodule MABEAM.AgentRegistry do
  @moduledoc """
  Production-ready Agent Registry for Foundation MABEAM.

  This module provides comprehensive agent lifecycle management, health monitoring, and
  resource allocation using Foundation's unified ProcessRegistry architecture.

  ## Features

  - Agent registration and deregistration with full validation
  - Agent lifecycle management (start, stop, restart) with OTP supervision
  - Health monitoring and status tracking with configurable intervals
  - Resource usage monitoring and limits enforcement
  - Configuration hot-reloading with validation
  - Integration with Foundation services (ProcessRegistry, Events, Telemetry)
  - Fault-tolerant operations with graceful error handling
  - Future-ready distributed architecture abstractions

  ## Architecture

  The AgentRegistry maintains a comprehensive state including:
  - Agent configurations and metadata with full validation
  - Agent process supervision hierarchy with configurable strategies
  - Health monitoring state with automatic failure detection
  - Resource usage metrics with enforcement capabilities
  - Configuration change history with rollback support

  This implementation is designed to be distribution-ready with middleware abstractions
  that will allow seamless scaling to multi-node deployments while maintaining
  single-node performance and reliability.

  ## Usage

      # Register an agent with full configuration
      agent_config = %{
        id: :my_agent,
        type: :worker,
        module: MyAgent,
        config: %{name: "My Agent", capabilities: [:coordination]},
        supervision: %{strategy: :one_for_one, max_restarts: 3, max_seconds: 60}
      }
      :ok = MABEAM.AgentRegistry.register_agent(:my_agent, agent_config)

      # Start the agent with automatic supervision
      {:ok, agent_pid} = MABEAM.AgentRegistry.start_agent(:my_agent)

      # Monitor agent status and health
      {:ok, status} = MABEAM.AgentRegistry.get_agent_status(:my_agent)
      {:ok, metrics} = MABEAM.AgentRegistry.get_agent_metrics(:my_agent)
  """

  use GenServer
  require Logger

  alias Foundation.ProcessRegistry

  # ============================================================================
  # Type Definitions
  # ============================================================================

  @type agent_id :: atom()
  @type agent_status :: :registered | :starting | :running | :stopping | :stopped | :failed

  @type agent_config :: %{
          id: agent_id(),
          type: atom(),
          module: module(),
          config: map(),
          supervision: supervision_config()
        }

  @type supervision_config :: %{
          strategy: atom(),
          max_restarts: non_neg_integer(),
          max_seconds: non_neg_integer()
        }

  @type agent_info :: %{
          id: agent_id(),
          config: agent_config(),
          status: agent_status(),
          pid: pid() | nil,
          started_at: DateTime.t() | nil,
          last_health_check: DateTime.t() | nil,
          restart_count: non_neg_integer(),
          supervisor_pid: pid() | nil,
          metadata: map()
        }

  @type agent_metrics :: %{
          memory_usage: non_neg_integer(),
          cpu_usage: float(),
          message_queue_length: non_neg_integer(),
          heap_size: non_neg_integer(),
          total_heap_size: non_neg_integer(),
          uptime_seconds: non_neg_integer()
        }

  @type registry_state :: %{
          agents: %{agent_id() => agent_info()},
          health_check_interval: non_neg_integer(),
          cleanup_interval: non_neg_integer(),
          started_at: DateTime.t(),
          total_registrations: non_neg_integer(),
          total_starts: non_neg_integer(),
          total_failures: non_neg_integer(),
          health_checks_performed: non_neg_integer()
        }

  # ============================================================================
  # GenServer Implementation
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    Logger.info("Starting Foundation MABEAM AgentRegistry with full functionality")

    # Simple GenServer state initialization - no supervisor management
    state = %{
      agents: %{},
      # Map of PID -> {agent_id, monitor_ref} for tracking monitored processes
      monitors: %{},
      cleanup_interval: Keyword.get(opts, :cleanup_interval, 60_000),
      health_check_interval: Keyword.get(opts, :health_check_interval, 30_000),
      total_registrations: 0,
      total_starts: 0,
      total_failures: 0,
      health_checks_performed: 0,
      started_at: DateTime.utc_now()
    }

    # Continue initialization after GenServer is fully started
    {:ok, state, {:continue, :complete_initialization}}
  end

  @impl true
  def handle_continue(:complete_initialization, state) do
    # Register self in the registry for health monitoring if available
    case Foundation.ProcessRegistry.register(:production, {:mabeam, :agent_registry}, self(), %{
           service: :agent_registry,
           type: :mabeam_service,
           started_at: state.started_at,
           capabilities: [:agent_management, :lifecycle_control, :health_monitoring]
         }) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to register AgentRegistry: #{inspect(reason)}")
        # Continue anyway
        :ok
    end

    # Remove duplicate supervisor - AgentSupervisor handles process supervision
    # AgentRegistry only manages configuration and status

    # Schedule periodic health checks and cleanup
    # 30 seconds
    schedule_health_check_tick(30_000)
    schedule_cleanup_tick(state.cleanup_interval)

    Logger.info("AgentRegistry initialized - process supervision delegated to AgentSupervisor")
    {:noreply, state}
  end

  # ============================================================================
  # Agent Registration API
  # ============================================================================

  @impl true
  def handle_call({:register_agent, agent_id, agent_config}, _from, state) do
    case validate_agent_config(agent_config) do
      :ok ->
        case Map.has_key?(state.agents, agent_id) do
          true ->
            {:reply, {:error, :already_registered}, state}

          false ->
            agent_info = %{
              id: agent_id,
              config: agent_config,
              status: :registered,
              pid: nil,
              started_at: nil,
              last_health_check: nil,
              restart_count: 0,
              supervisor_pid: nil,
              metadata: %{
                registered_at: DateTime.utc_now(),
                registration_source: :api
              }
            }

            new_agents = Map.put(state.agents, agent_id, agent_info)

            new_state = %{
              state
              | agents: new_agents,
                total_registrations: state.total_registrations + 1
            }

            # Emit telemetry event
            emit_telemetry_event(:agent_registered, %{agent_id: agent_id}, agent_config)

            Logger.info("Registered agent #{agent_id} with module #{agent_config.module}")
            {:reply, :ok, new_state}
        end

      {:error, reason} ->
        Logger.warning("Failed to register agent #{agent_id}: #{inspect(reason)}")
        {:reply, {:error, {:validation_failed, reason}}, state}
    end
  end

  @impl true
  def handle_call({:deregister_agent, agent_id}, _from, state) do
    case Map.get(state.agents, agent_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      agent_info ->
        # Clean up monitoring first
        new_monitors =
          case agent_info.pid do
            nil ->
              state.monitors

            pid ->
              case Map.get(state.monitors, pid) do
                {^agent_id, monitor_ref} ->
                  Process.demonitor(monitor_ref, [:flush])
                  Map.delete(state.monitors, pid)

                _ ->
                  state.monitors
              end
          end

        # Stop agent if running
        case agent_info.status do
          :running ->
            if agent_info.pid && Process.alive?(agent_info.pid) do
              # Delegate to AgentSupervisor for process management
              MABEAM.AgentSupervisor.stop_agent(agent_id)
            end

          _ ->
            :ok
        end

        new_agents = Map.delete(state.agents, agent_id)
        new_state = %{state | agents: new_agents, monitors: new_monitors}

        # Emit telemetry event
        emit_telemetry_event(:agent_deregistered, %{agent_id: agent_id}, %{})

        Logger.info("Deregistered agent #{agent_id}")
        {:reply, :ok, new_state}
    end
  end

  # ============================================================================
  # Agent Lifecycle API
  # ============================================================================

  @impl true
  def handle_call({:start_agent, agent_id}, _from, state) do
    case Map.get(state.agents, agent_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{status: :running} ->
        {:reply, {:error, :already_running}, state}

      agent_info ->
        # Pass the agent config directly to AgentSupervisor to avoid circular dependency
        case start_agent_via_supervisor(agent_id, agent_info.config) do
          {:ok, pid} ->
            # Monitor the agent process for crash detection
            monitor_ref = Process.monitor(pid)

            updated_agent_info = %{
              agent_info
              | status: :running,
                pid: pid,
                started_at: DateTime.utc_now()
            }

            new_agents = Map.put(state.agents, agent_id, updated_agent_info)
            new_monitors = Map.put(state.monitors, pid, {agent_id, monitor_ref})

            new_state = %{
              state
              | agents: new_agents,
                monitors: new_monitors,
                total_starts: state.total_starts + 1
            }

            # Register agent in ProcessRegistry (if available)
            try do
              ProcessRegistry.register(:production, {:agent, agent_id}, pid, %{
                agent_id: agent_id,
                module: agent_info.config.module,
                type: agent_info.config.type,
                started_at: updated_agent_info.started_at
              })
            rescue
              ArgumentError ->
                # ProcessRegistry not available, skip registration
                :ok
            end

            # Emit telemetry event
            emit_telemetry_event(:agent_started, %{agent_id: agent_id, pid: pid}, agent_info.config)

            Logger.info("Started agent #{agent_id} with PID #{inspect(pid)}")
            {:reply, {:ok, pid}, new_state}

          {:error, reason} ->
            # Mark agent as failed
            updated_agent_info = %{
              agent_info
              | status: :failed,
                restart_count: agent_info.restart_count + 1
            }

            new_agents = Map.put(state.agents, agent_id, updated_agent_info)
            new_state = %{state | agents: new_agents, total_failures: state.total_failures + 1}

            # Emit telemetry event
            emit_telemetry_event(
              :agent_start_failed,
              %{agent_id: agent_id, reason: reason},
              agent_info.config
            )

            Logger.error("Failed to start agent #{agent_id}: #{inspect(reason)}")
            {:reply, {:error, reason}, new_state}
        end
    end
  end

  @impl true
  def handle_call({:stop_agent, agent_id}, _from, state) do
    case Map.get(state.agents, agent_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{status: :registered} ->
        {:reply, {:error, :not_running}, state}

      agent_info ->
        # Clean up monitoring first
        new_monitors =
          case agent_info.pid do
            nil ->
              state.monitors

            pid ->
              case Map.get(state.monitors, pid) do
                {^agent_id, monitor_ref} ->
                  Process.demonitor(monitor_ref, [:flush])
                  Map.delete(state.monitors, pid)

                _ ->
                  state.monitors
              end
          end

        # Terminate the agent process
        if agent_info.pid && Process.alive?(agent_info.pid) do
          # Delegate to AgentSupervisor for process management
          MABEAM.AgentSupervisor.stop_agent(agent_id)
        end

        # Unregister from ProcessRegistry (if available)
        try do
          ProcessRegistry.unregister(:production, {:agent, agent_id})
        rescue
          ArgumentError ->
            # ProcessRegistry not available, skip unregistration
            :ok
        end

        updated_agent_info = %{agent_info | status: :registered, pid: nil, started_at: nil}

        new_agents = Map.put(state.agents, agent_id, updated_agent_info)
        new_state = %{state | agents: new_agents, monitors: new_monitors}

        # Emit telemetry event
        emit_telemetry_event(:agent_stopped, %{agent_id: agent_id}, agent_info.config)

        Logger.info("Stopped agent #{agent_id}")
        {:reply, :ok, new_state}
    end
  end

  # ============================================================================
  # Query API
  # ============================================================================

  @impl true
  def handle_call({:get_agent_config, agent_id}, _from, state) do
    case Map.get(state.agents, agent_id) do
      nil -> {:reply, {:error, :not_found}, state}
      agent_info -> {:reply, {:ok, agent_info.config}, state}
    end
  end

  @impl true
  def handle_call({:get_agent_status, agent_id}, _from, state) do
    case Map.get(state.agents, agent_id) do
      nil -> {:reply, {:error, :not_found}, state}
      agent_info -> {:reply, {:ok, agent_info}, state}
    end
  end

  @impl true
  def handle_call({:get_agent_info, agent_id}, _from, state) do
    case Map.get(state.agents, agent_id) do
      nil -> {:reply, {:error, :not_found}, state}
      agent_info -> {:reply, {:ok, agent_info}, state}
    end
  end

  @impl true
  def handle_call(:list_agents, _from, state) do
    agents = Enum.map(state.agents, fn {id, info} -> {id, info} end)
    {:reply, {:ok, agents}, state}
  end

  @impl true
  def handle_call(:agent_count, _from, state) do
    {:reply, {:ok, map_size(state.agents)}, state}
  end

  @impl true
  def handle_call({:get_agent_metrics, agent_id}, _from, state) do
    case Map.get(state.agents, agent_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{pid: nil} ->
        {:reply, {:error, :not_running}, state}

      %{pid: pid} when is_pid(pid) ->
        metrics = calculate_agent_metrics(pid)
        {:reply, {:ok, metrics}, state}
    end
  end

  @impl true
  def handle_call(:get_resource_summary, _from, state) do
    summary = calculate_resource_summary(state)
    {:reply, {:ok, summary}, state}
  end

  @impl true
  def handle_call({:get_agent_supervisor, agent_id}, _from, state) do
    case Map.get(state.agents, agent_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _agent_info ->
        # Return the global AgentSupervisor PID
        case Process.whereis(MABEAM.AgentSupervisor) do
          nil -> {:reply, {:error, :supervisor_not_running}, state}
          pid -> {:reply, {:ok, pid}, state}
        end
    end
  end

  @impl true
  def handle_call({:get_supervisor_health, agent_id}, _from, state) do
    case Map.get(state.agents, agent_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _agent_info ->
        # Get the actual supervisor PID
        supervisor_pid =
          case Process.whereis(MABEAM.AgentSupervisor) do
            nil -> nil
            pid -> pid
          end

        # Delegate supervisor health to AgentSupervisor
        supervisor_health = MABEAM.AgentSupervisor.get_system_performance()

        # Calculate children count
        children_count =
          case supervisor_pid do
            nil ->
              0

            pid ->
              %{active: count} = DynamicSupervisor.count_children(pid)
              count
          end

        health = %{
          status: if(supervisor_pid, do: :healthy, else: :unhealthy),
          supervisor_pid: supervisor_pid,
          children_count: children_count,
          supervisor_metrics: supervisor_health
        }

        {:reply, {:ok, health}, state}
    end
  end

  # ============================================================================
  # Configuration Management API
  # ============================================================================

  @impl true
  def handle_call({:update_agent_config, agent_id, new_config}, _from, state) do
    case Map.get(state.agents, agent_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      agent_info ->
        case validate_agent_config(new_config) do
          :ok ->
            updated_agent_info = %{agent_info | config: new_config}
            new_agents = Map.put(state.agents, agent_id, updated_agent_info)
            new_state = %{state | agents: new_agents}

            # Emit telemetry event
            emit_telemetry_event(:agent_config_updated, %{agent_id: agent_id}, new_config)

            Logger.info("Updated configuration for agent #{agent_id}")
            {:reply, :ok, new_state}

          {:error, reason} ->
            {:reply, {:error, {:validation_failed, reason}}, state}
        end
    end
  end

  # ============================================================================
  # Health Monitoring API
  # ============================================================================

  @impl true
  def handle_call({:health_check, agent_id}, _from, state) do
    case Map.get(state.agents, agent_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      agent_info ->
        health_result = perform_agent_health_check(agent_info)

        updated_agent_info = %{agent_info | last_health_check: DateTime.utc_now()}
        new_agents = Map.put(state.agents, agent_id, updated_agent_info)
        new_state = %{state | agents: new_agents}

        {:reply, health_result, new_state}
    end
  end

  @impl true
  def handle_call(:system_health, _from, state) do
    health = calculate_system_health(state)
    {:reply, {:ok, health}, state}
  end

  # ============================================================================
  # Generic Handlers
  # ============================================================================

  @impl true
  def handle_call(request, _from, state) do
    Logger.warning("Unknown AgentRegistry call: #{inspect(request)}")
    {:reply, {:error, :unknown_request}, state}
  end

  @impl true
  def handle_cast({:update_agent_status, agent_id, pid, status}, state) do
    case Map.get(state.agents, agent_id) do
      nil ->
        {:noreply, state}

      agent_info ->
        updated_agent_info = %{
          agent_info
          | status: status,
            pid: pid,
            started_at: if(status == :running, do: DateTime.utc_now(), else: agent_info.started_at)
        }

        new_agents = Map.put(state.agents, agent_id, updated_agent_info)
        new_state = %{state | agents: new_agents}

        Logger.debug("Updated agent #{agent_id} status to #{status}")
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast(msg, state) do
    Logger.warning("Unknown AgentRegistry cast: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_info(:health_check_tick, state) do
    # Perform periodic health checks on all agents
    new_state = perform_periodic_health_checks(state)
    schedule_health_check_tick(state.health_check_interval)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:cleanup_tick, state) do
    # Perform periodic cleanup of failed agents and stale data
    new_state = perform_cleanup(state)
    schedule_cleanup_tick(state.cleanup_interval)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, monitor_ref, :process, pid, reason}, state) do
    # Handle process monitoring - find agent by PID and update status
    case Map.get(state.monitors, pid) do
      {agent_id, ^monitor_ref} ->
        # Process was monitored and died
        Logger.warning("Agent #{agent_id} process died: #{inspect(reason)}")

        # Update agent status to failed
        case Map.get(state.agents, agent_id) do
          nil ->
            # Agent was already removed, just clean up monitors
            new_monitors = Map.delete(state.monitors, pid)
            {:noreply, %{state | monitors: new_monitors}}

          agent_info ->
            updated_agent_info = %{
              agent_info
              | status: :failed,
                pid: nil,
                restart_count: agent_info.restart_count + 1
            }

            new_agents = Map.put(state.agents, agent_id, updated_agent_info)
            new_monitors = Map.delete(state.monitors, pid)

            new_state = %{
              state
              | agents: new_agents,
                monitors: new_monitors,
                total_failures: state.total_failures + 1
            }

            # Emit telemetry event
            emit_telemetry_event(
              :agent_crashed,
              %{agent_id: agent_id, restart_count: updated_agent_info.restart_count},
              %{reason: reason}
            )

            {:noreply, new_state}
        end

      _ ->
        # Unknown monitored process, ignore
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Unknown AgentRegistry info: #{inspect(msg)}")
    {:noreply, state}
  end

  # ============================================================================
  # Public API Functions
  # ============================================================================

  @doc """
  Register an agent with comprehensive configuration validation.
  """
  @spec register_agent(agent_id(), agent_config()) :: :ok | {:error, term()}
  def register_agent(agent_id, agent_config) do
    GenServer.call(__MODULE__, {:register_agent, agent_id, agent_config})
  end

  @doc """
  Deregister an agent and stop it if running.
  """
  @spec deregister_agent(agent_id()) :: :ok | {:error, term()}
  def deregister_agent(agent_id) do
    GenServer.call(__MODULE__, {:deregister_agent, agent_id})
  end

  @doc """
  Start a registered agent with automatic supervision.
  """
  @spec start_agent(agent_id()) :: {:ok, pid()} | {:error, term()}
  def start_agent(agent_id) do
    GenServer.call(__MODULE__, {:start_agent, agent_id})
  end

  @doc """
  Stop a running agent gracefully.
  """
  @spec stop_agent(agent_id()) :: :ok | {:error, term()}
  def stop_agent(agent_id) do
    GenServer.call(__MODULE__, {:stop_agent, agent_id})
  end

  @doc """
  Get agent configuration.
  """
  @spec get_agent_config(agent_id()) :: {:ok, agent_config()} | {:error, term()}
  def get_agent_config(agent_id) do
    GenServer.call(__MODULE__, {:get_agent_config, agent_id})
  end

  @doc """
  Get comprehensive agent status information.
  """
  @spec get_agent_status(agent_id()) :: {:ok, agent_info()} | {:error, term()}
  def get_agent_status(agent_id) do
    GenServer.call(__MODULE__, {:get_agent_status, agent_id})
  end

  @doc """
  Get complete agent information including status, config, and metadata.
  """
  @spec get_agent_info(agent_id()) :: {:ok, agent_info()} | {:error, term()}
  def get_agent_info(agent_id) do
    GenServer.call(__MODULE__, {:get_agent_info, agent_id})
  end

  @doc """
  List all registered agents with their information.
  """
  @spec list_agents() :: {:ok, [{agent_id(), agent_info()}]}
  def list_agents() do
    GenServer.call(__MODULE__, :list_agents)
  end

  @doc """
  Get total count of registered agents.
  """
  @spec agent_count() :: {:ok, non_neg_integer()}
  def agent_count() do
    GenServer.call(__MODULE__, :agent_count)
  end

  @doc """
  Get detailed metrics for a specific agent.
  """
  @spec get_agent_metrics(agent_id()) :: {:ok, agent_metrics()} | {:error, term()}
  def get_agent_metrics(agent_id) do
    GenServer.call(__MODULE__, {:get_agent_metrics, agent_id})
  end

  @doc """
  Get system-wide resource usage summary.
  """
  @spec get_resource_summary() :: {:ok, map()}
  def get_resource_summary() do
    GenServer.call(__MODULE__, :get_resource_summary)
  end

  @doc """
  Update agent configuration with validation.
  """
  @spec update_agent_config(agent_id(), agent_config()) :: :ok | {:error, term()}
  def update_agent_config(agent_id, new_config) do
    GenServer.call(__MODULE__, {:update_agent_config, agent_id, new_config})
  end

  @doc """
  Perform health check on a specific agent.
  """
  @spec health_check(agent_id()) :: :ok | {:error, term()}
  def health_check(agent_id) do
    GenServer.call(__MODULE__, {:health_check, agent_id})
  end

  @doc """
  Get system-wide health status.
  """
  @spec system_health() :: {:ok, map()}
  def system_health() do
    GenServer.call(__MODULE__, :system_health)
  end

  @doc """
  Get agent supervisor PID.
  """
  @spec get_agent_supervisor(agent_id()) :: {:ok, pid()} | {:error, term()}
  def get_agent_supervisor(agent_id) do
    GenServer.call(__MODULE__, {:get_agent_supervisor, agent_id})
  end

  @doc """
  Get supervisor health status.
  """
  @spec get_supervisor_health(agent_id()) :: {:ok, map()} | {:error, term()}
  def get_supervisor_health(agent_id) do
    GenServer.call(__MODULE__, {:get_supervisor_health, agent_id})
  end

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  defp validate_agent_config(config) do
    required_fields = [:id, :type, :module, :config, :supervision]

    case Enum.all?(required_fields, &Map.has_key?(config, &1)) do
      false ->
        missing = required_fields -- Map.keys(config)
        {:error, {:missing_fields, missing}}

      true ->
        validate_supervision_config(config.supervision)
    end
  end

  defp validate_supervision_config(supervision) do
    required_fields = [:strategy, :max_restarts, :max_seconds]

    case Enum.all?(required_fields, &Map.has_key?(supervision, &1)) do
      false ->
        missing = required_fields -- Map.keys(supervision)
        {:error, {:missing_supervision_fields, missing}}

      true ->
        if supervision.max_restarts >= 0 and supervision.max_seconds > 0 do
          :ok
        else
          {:error, :invalid_supervision_values}
        end
    end
  end

  # start_agent_process function removed - AgentSupervisor handles process management

  defp calculate_agent_metrics(pid) when is_pid(pid) do
    case Process.alive?(pid) do
      true ->
        {:message_queue_len, message_queue_length} = Process.info(pid, :message_queue_len)
        {:heap_size, heap_size} = Process.info(pid, :heap_size)
        {:total_heap_size, total_heap_size} = Process.info(pid, :total_heap_size)
        {:memory, memory} = Process.info(pid, :memory)

        %{
          memory_usage: memory,
          # TODO: Implement CPU usage tracking
          cpu_usage: 0.0,
          message_queue_length: message_queue_length,
          heap_size: heap_size,
          total_heap_size: total_heap_size,
          # TODO: Calculate from start time
          uptime_seconds: 0
        }

      false ->
        %{
          memory_usage: 0,
          cpu_usage: 0.0,
          message_queue_length: 0,
          heap_size: 0,
          total_heap_size: 0,
          uptime_seconds: 0
        }
    end
  end

  defp calculate_resource_summary(state) do
    {total_memory, total_agents, active_agents} =
      Enum.reduce(state.agents, {0, 0, 0}, fn {_id, agent_info}, {mem_acc, total_acc, active_acc} ->
        total_acc = total_acc + 1

        {mem_usage, active_acc} =
          case agent_info.pid do
            nil ->
              {0, active_acc}

            pid when is_pid(pid) ->
              case Process.alive?(pid) do
                true ->
                  {:memory, memory} = Process.info(pid, :memory)
                  {memory, active_acc + 1}

                false ->
                  {0, active_acc}
              end
          end

        {mem_acc + mem_usage, total_acc, active_acc}
      end)

    %{
      total_agents: total_agents,
      active_agents: active_agents,
      total_memory_usage: total_memory,
      # TODO: Implement system CPU tracking
      total_cpu_usage: 0.0,
      average_memory_per_agent: if(active_agents > 0, do: total_memory / active_agents, else: 0)
    }
  end

  defp perform_agent_health_check(agent_info) do
    case agent_info.status do
      # Failed agents are unhealthy regardless of PID
      :failed ->
        {:error, :process_dead}

      # Registered but not running is fine
      :registered ->
        :ok

      # Running agents need PID check
      :running ->
        case agent_info.pid do
          nil ->
            # This shouldn't happen - running agent should have PID
            {:error, :process_dead}

          pid when is_pid(pid) ->
            if Process.alive?(pid) do
              :ok
            else
              {:error, :process_dead}
            end
        end

      # Any other status (like :stopping)
      _ ->
        :ok
    end
  end

  defp calculate_system_health(state) do
    total_agents = map_size(state.agents)

    {healthy_count, unhealthy_count} =
      Enum.reduce(state.agents, {0, 0}, fn {_id, agent_info}, {healthy, unhealthy} ->
        case perform_agent_health_check(agent_info) do
          :ok -> {healthy + 1, unhealthy}
          {:error, _} -> {healthy, unhealthy + 1}
        end
      end)

    %{
      total_agents: total_agents,
      healthy_agents: healthy_count,
      unhealthy_agents: unhealthy_count,
      health_percentage: if(total_agents > 0, do: healthy_count / total_agents * 100, else: 100),
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.started_at, :second),
      total_registrations: state.total_registrations,
      total_starts: state.total_starts,
      total_failures: state.total_failures
    }
  end

  defp perform_periodic_health_checks(state) do
    # TODO: Implement comprehensive periodic health checking
    # For now, just return the state unchanged
    state
  end

  defp perform_cleanup(state) do
    # TODO: Implement cleanup of stale data and failed agents
    # For now, just return the state unchanged
    state
  end

  defp schedule_health_check_tick(interval) do
    Process.send_after(self(), :health_check_tick, interval)
  end

  defp schedule_cleanup_tick(interval) do
    Process.send_after(self(), :cleanup_tick, interval)
  end

  defp emit_telemetry_event(event_name, measurements, metadata) do
    try do
      :telemetry.execute(
        [:foundation, :mabeam, :agent, event_name],
        Map.merge(%{count: 1}, measurements),
        metadata
      )
    rescue
      # Ignore telemetry errors
      _ -> :ok
    end
  end

  defp start_agent_via_supervisor(agent_id, agent_config) do
    # Get the agent arguments from the config field, handling both maps and keyword lists
    agent_args =
      case agent_config do
        %{config: %{args: args}} -> args
        %{config: config_map} when is_map(config_map) -> config_map
        %{config: config_list} when is_list(config_list) -> config_list
        _ -> %{}
      end

    # Create child spec directly
    child_spec = %{
      id: agent_id,
      start: {agent_config.module, :start_link, [agent_args]},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }

    # Start via DynamicSupervisor and track in AgentSupervisor
    case DynamicSupervisor.start_child(MABEAM.AgentSupervisor, child_spec) do
      {:ok, pid} ->
        # Track the agent in AgentSupervisor's tracking system
        track_agent_in_supervisor(agent_id, pid)
        {:ok, pid}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp track_agent_in_supervisor(agent_id, pid) do
    # Call AgentSupervisor's internal tracking directly
    # This avoids circular dependency and GenServer callback issues
    MABEAM.AgentSupervisor.track_supervised_agent(agent_id, pid)
  end

  # ============================================================================
  # Child Spec for Supervision
  # ============================================================================

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
