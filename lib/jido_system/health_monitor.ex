defmodule JidoSystem.HealthMonitor do
  @moduledoc """
  Health monitoring service for JidoSystem agents.

  Provides centralized health monitoring and alerting for all JidoSystem agents,
  following proper OTP supervision principles and separation of concerns.

  ## Features

  - Periodic health checks for registered agents
  - Automatic unhealthy agent detection and alerting
  - Integration with Foundation monitoring infrastructure
  - Configurable health check intervals and thresholds

  ## Usage

      # Register an agent for monitoring
      JidoSystem.HealthMonitor.register_agent(agent_pid, %{
        health_check: &custom_health_check/1,
        interval: 30_000
      })

      # Unregister an agent
      JidoSystem.HealthMonitor.unregister_agent(agent_pid)

      # Get health status
      {:ok, status} = JidoSystem.HealthMonitor.get_health_status(agent_pid)
  """

  use GenServer
  require Logger

  defstruct [
    :monitored_agents,  # %{agent_pid => %{health_check: fun, interval: ms, last_check: time}}
    :health_statuses,   # %{agent_pid => %{status: :healthy | :unhealthy, last_update: time}}
    :process_monitors   # %{monitor_ref => agent_pid}
  ]

  @default_health_check_interval 30_000
  @default_health_check &__MODULE__.default_health_check/1

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers an agent for health monitoring.
  """
  def register_agent(agent_pid, opts \\ []) do
    GenServer.call(__MODULE__, {:register_agent, agent_pid, opts})
  end

  @doc """
  Unregisters an agent from health monitoring.
  """
  def unregister_agent(agent_pid) do
    GenServer.call(__MODULE__, {:unregister_agent, agent_pid})
  end

  @doc """
  Gets the current health status of an agent.
  """
  def get_health_status(agent_pid) do
    GenServer.call(__MODULE__, {:get_health_status, agent_pid})
  end

  @doc """
  Gets health status for all monitored agents.
  """
  def get_all_health_statuses do
    GenServer.call(__MODULE__, :get_all_health_statuses)
  end

  @doc """
  Forces a health check for a specific agent.
  """
  def force_health_check(agent_pid) do
    GenServer.cast(__MODULE__, {:force_health_check, agent_pid})
  end

  @doc """
  Default health check implementation.
  """
  def default_health_check(agent_pid) do
    try do
      if Process.alive?(agent_pid) do
        # Try to get agent status - this will fail if agent is unresponsive
        case GenServer.call(agent_pid, :get_status, 5000) do
          {:ok, _status} -> :healthy
          _ -> :unhealthy
        end
      else
        :dead
      end
    catch
      :exit, {:timeout, _} -> :unresponsive
      :exit, {:noproc, _} -> :dead
      _, _ -> :unhealthy
    end
  end

  # Server Implementation

  def init(_opts) do
    state = %__MODULE__{
      monitored_agents: %{},
      health_statuses: %{},
      process_monitors: %{}
    }

    # Schedule periodic health checks
    schedule_health_checks()

    Logger.info("JidoSystem.HealthMonitor started")
    {:ok, state}
  end

  def handle_call({:register_agent, agent_pid, opts}, _from, state) do
    health_check = Keyword.get(opts, :health_check, @default_health_check)
    interval = Keyword.get(opts, :interval, @default_health_check_interval)

    # Set up process monitoring
    monitor_ref = Process.monitor(agent_pid)
    
    agent_config = %{
      health_check: health_check,
      interval: interval,
      last_check: nil,
      monitor_ref: monitor_ref
    }

    new_monitored = Map.put(state.monitored_agents, agent_pid, agent_config)
    new_monitors = Map.put(state.process_monitors, monitor_ref, agent_pid)
    
    # Initialize health status
    new_statuses = Map.put(state.health_statuses, agent_pid, %{
      status: :unknown,
      last_update: DateTime.utc_now()
    })

    new_state = %{state |
      monitored_agents: new_monitored,
      process_monitors: new_monitors,
      health_statuses: new_statuses
    }

    Logger.debug("Registered agent #{inspect(agent_pid)} for health monitoring")
    {:reply, :ok, new_state}
  end

  def handle_call({:unregister_agent, agent_pid}, _from, state) do
    case Map.get(state.monitored_agents, agent_pid) do
      nil ->
        {:reply, {:error, :not_found}, state}
        
      %{monitor_ref: monitor_ref} ->
        Process.demonitor(monitor_ref, [:flush])
        
        new_monitored = Map.delete(state.monitored_agents, agent_pid)
        new_monitors = Map.delete(state.process_monitors, monitor_ref)
        new_statuses = Map.delete(state.health_statuses, agent_pid)
        
        new_state = %{state |
          monitored_agents: new_monitored,
          process_monitors: new_monitors,
          health_statuses: new_statuses
        }
        
        Logger.debug("Unregistered agent #{inspect(agent_pid)} from health monitoring")
        {:reply, :ok, new_state}
    end
  end

  def handle_call({:get_health_status, agent_pid}, _from, state) do
    case Map.get(state.health_statuses, agent_pid) do
      nil -> {:reply, {:error, :not_monitored}, state}
      status -> {:reply, {:ok, status}, state}
    end
  end

  def handle_call(:get_all_health_statuses, _from, state) do
    {:reply, {:ok, state.health_statuses}, state}
  end

  def handle_cast({:force_health_check, agent_pid}, state) do
    case Map.get(state.monitored_agents, agent_pid) do
      nil ->
        Logger.warning("Cannot force health check for unmonitored agent #{inspect(agent_pid)}")
        {:noreply, state}
        
      agent_config ->
        new_state = perform_health_check(agent_pid, agent_config, state)
        {:noreply, new_state}
    end
  end

  def handle_info(:health_check_cycle, state) do
    # Perform health checks for all monitored agents
    new_state = Enum.reduce(state.monitored_agents, state, fn {agent_pid, agent_config}, acc_state ->
      should_check = should_perform_health_check?(agent_config)
      
      if should_check do
        perform_health_check(agent_pid, agent_config, acc_state)
      else
        acc_state
      end
    end)

    # Schedule next health check cycle
    schedule_health_checks()

    {:noreply, new_state}
  end

  def handle_info({:DOWN, monitor_ref, :process, _agent_pid, reason}, state) do
    case Map.get(state.process_monitors, monitor_ref) do
      nil ->
        {:noreply, state}
        
      agent_pid ->
        Logger.info("Monitored agent #{inspect(agent_pid)} went down: #{inspect(reason)}")
        
        # Update health status to dead
        new_statuses = Map.put(state.health_statuses, agent_pid, %{
          status: :dead,
          last_update: DateTime.utc_now(),
          reason: reason
        })
        
        # Clean up monitoring data
        new_monitored = Map.delete(state.monitored_agents, agent_pid)
        new_monitors = Map.delete(state.process_monitors, monitor_ref)
        
        new_state = %{state |
          monitored_agents: new_monitored,
          process_monitors: new_monitors,
          health_statuses: new_statuses
        }
        
        # Emit telemetry
        :telemetry.execute(
          [:jido_system, :health_monitor, :agent_died],
          %{},
          %{agent_pid: agent_pid, reason: reason}
        )
        
        {:noreply, new_state}
    end
  end

  # Private helpers

  defp schedule_health_checks do
    Process.send_after(self(), :health_check_cycle, 10_000)  # Every 10 seconds
  end

  defp should_perform_health_check?(%{last_check: nil}), do: true
  defp should_perform_health_check?(%{last_check: last_check, interval: interval}) do
    elapsed = System.monotonic_time(:millisecond) - last_check
    elapsed >= interval
  end

  defp perform_health_check(agent_pid, agent_config, state) do
    start_time = System.monotonic_time(:millisecond)
    
    try do
      health_status = agent_config.health_check.(agent_pid)
      
      # Update agent config with last check time
      updated_config = %{agent_config | last_check: start_time}
      new_monitored = Map.put(state.monitored_agents, agent_pid, updated_config)
      
      # Update health status
      status_record = %{
        status: health_status,
        last_update: DateTime.utc_now()
      }
      new_statuses = Map.put(state.health_statuses, agent_pid, status_record)
      
      # Emit telemetry
      :telemetry.execute(
        [:jido_system, :health_monitor, :health_check],
        %{duration: System.monotonic_time(:millisecond) - start_time},
        %{agent_pid: agent_pid, status: health_status}
      )
      
      # Alert on status changes
      previous_status = get_in(state.health_statuses, [agent_pid, :status])
      if previous_status && previous_status != health_status do
        Logger.warning("Agent #{inspect(agent_pid)} health status changed: #{previous_status} -> #{health_status}")
      end
      
      %{state |
        monitored_agents: new_monitored,
        health_statuses: new_statuses
      }
    rescue
      error ->
        Logger.error("Health check failed for agent #{inspect(agent_pid)}: #{Exception.message(error)}")
        
        # Mark as unhealthy
        status_record = %{
          status: :unhealthy,
          last_update: DateTime.utc_now(),
          error: Exception.message(error)
        }
        new_statuses = Map.put(state.health_statuses, agent_pid, status_record)
        
        %{state | health_statuses: new_statuses}
    end
  end
end