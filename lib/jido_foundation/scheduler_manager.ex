defmodule JidoFoundation.SchedulerManager do
  @moduledoc """
  Supervised GenServer for managing agent scheduling and periodic operations.

  This module replaces agent self-scheduling patterns with proper OTP supervision,
  providing centralized timer management, coordinated shutdown, and resource cleanup.

  ## Features

  - Centralized scheduling for all agent periodic operations
  - Proper OTP supervision integration
  - Graceful shutdown with timer cleanup
  - Schedule registration and deregistration
  - Health monitoring and agent lifecycle awareness
  - Configurable intervals and scheduling policies

  ## Architecture

  Instead of agents managing their own timers with `Process.send_after(self(), ...)`,
  this module provides a supervised scheduling service that:
  1. Manages all agent timers centrally
  2. Coordinates with OTP supervision trees
  3. Handles agent death gracefully
  4. Provides proper shutdown procedures
  5. Offers timer cancellation and rescheduling

  ## Usage

      # Register for periodic health checks
      JidoFoundation.SchedulerManager.register_periodic(
        agent_pid,
        :health_check,
        30_000,
        :collect_metrics
      )

      # Register for workflow monitoring
      JidoFoundation.SchedulerManager.register_periodic(
        agent_pid,
        :workflow_monitor,
        60_000,
        :monitor_workflows
      )

      # Unregister when agent stops
      JidoFoundation.SchedulerManager.unregister_agent(agent_pid)
  """

  use GenServer
  require Logger
  alias Foundation.SupervisedSend

  defstruct [
    # %{agent_pid => %{schedule_id => %{timer_ref, interval, message, last_run}}}
    :scheduled_operations,
    # %{agent_pid => monitor_ref}
    :monitored_agents,
    :stats
  ]

  @type t :: %__MODULE__{}

  # Client API

  @doc """
  Starts the scheduler manager GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers a periodic operation for an agent.

  ## Parameters

  - `agent_pid` - PID of the agent
  - `schedule_id` - Unique identifier for this schedule
  - `interval` - Interval in milliseconds
  - `message` - Message to send to the agent

  ## Returns

  - `:ok` - Schedule registered successfully
  - `{:error, reason}` - Failed to register schedule
  """
  @spec register_periodic(pid(), atom(), non_neg_integer(), term()) :: :ok | {:error, term()}
  def register_periodic(agent_pid, schedule_id, interval, message)
      when is_pid(agent_pid) and is_atom(schedule_id) and is_integer(interval) and interval > 0 do
    GenServer.call(__MODULE__, {:register_periodic, agent_pid, schedule_id, interval, message})
  end

  @doc """
  Unregisters a specific periodic operation for an agent.
  """
  @spec unregister_periodic(pid(), atom()) :: :ok | {:error, :not_found}
  def unregister_periodic(agent_pid, schedule_id)
      when is_pid(agent_pid) and is_atom(schedule_id) do
    GenServer.call(__MODULE__, {:unregister_periodic, agent_pid, schedule_id})
  end

  @doc """
  Unregisters all periodic operations for an agent.

  This is typically called when an agent is stopping.
  """
  @spec unregister_agent(pid()) :: :ok
  def unregister_agent(agent_pid) when is_pid(agent_pid) do
    GenServer.call(__MODULE__, {:unregister_agent, agent_pid})
  end

  @doc """
  Updates the interval for an existing schedule.
  """
  @spec update_interval(pid(), atom(), non_neg_integer()) :: :ok | {:error, :not_found}
  def update_interval(agent_pid, schedule_id, new_interval)
      when is_pid(agent_pid) and is_atom(schedule_id) and is_integer(new_interval) and
             new_interval > 0 do
    GenServer.call(__MODULE__, {:update_interval, agent_pid, schedule_id, new_interval})
  end

  @doc """
  Forces immediate execution of a scheduled operation.
  """
  @spec force_execution(pid(), atom()) :: :ok | {:error, :not_found}
  def force_execution(agent_pid, schedule_id)
      when is_pid(agent_pid) and is_atom(schedule_id) do
    GenServer.call(__MODULE__, {:force_execution, agent_pid, schedule_id})
  end

  @doc """
  Gets scheduling statistics and status.
  """
  @spec get_stats() :: map()
  def get_stats do
    GenServer.call(__MODULE__, :get_stats)
  end

  @doc """
  Lists all schedules for a specific agent.
  """
  @spec list_agent_schedules(pid()) :: {:ok, [map()]} | {:error, :not_found}
  def list_agent_schedules(agent_pid) when is_pid(agent_pid) do
    GenServer.call(__MODULE__, {:list_agent_schedules, agent_pid})
  end

  # GenServer implementation

  @impl true
  def init(_opts) do
    # Set up process monitoring for itself
    Process.flag(:trap_exit, true)

    state = %__MODULE__{
      scheduled_operations: %{},
      monitored_agents: %{},
      stats: %{
        total_schedules: 0,
        active_agents: 0,
        messages_sent: 0,
        schedule_failures: 0
      }
    }

    Logger.info("JidoFoundation.SchedulerManager started")
    {:ok, state}
  end

  @impl true
  def handle_call({:register_periodic, agent_pid, schedule_id, interval, message}, _from, state) do
    # Check if agent is alive
    if Process.alive?(agent_pid) do
      # Monitor agent if not already monitored
      new_state = ensure_monitored(agent_pid, state)

      # Cancel existing timer if there is one
      new_state = cancel_existing_timer(agent_pid, schedule_id, new_state)

      # Schedule first execution
      timer_ref = Process.send_after(self(), {:execute_schedule, agent_pid, schedule_id}, interval)

      # Create schedule info
      schedule_info = %{
        timer_ref: timer_ref,
        interval: interval,
        message: message,
        last_run: nil,
        created_at: DateTime.utc_now()
      }

      # Update schedules
      agent_schedules = Map.get(new_state.scheduled_operations, agent_pid, %{})
      updated_agent_schedules = Map.put(agent_schedules, schedule_id, schedule_info)

      new_scheduled_operations =
        Map.put(new_state.scheduled_operations, agent_pid, updated_agent_schedules)

      # Update stats
      new_stats = Map.update!(new_state.stats, :total_schedules, &(&1 + 1))

      final_state = %{
        new_state
        | scheduled_operations: new_scheduled_operations,
          stats: new_stats
      }

      Logger.debug(
        "Registered periodic schedule #{schedule_id} for agent #{inspect(agent_pid)} with interval #{interval}ms"
      )

      {:reply, :ok, final_state}
    else
      {:reply, {:error, :agent_not_alive}, state}
    end
  end

  def handle_call({:unregister_periodic, agent_pid, schedule_id}, _from, state) do
    case get_in(state.scheduled_operations, [agent_pid, schedule_id]) do
      nil ->
        {:reply, {:error, :not_found}, state}

      schedule_info ->
        # Cancel timer
        Process.cancel_timer(schedule_info.timer_ref)

        # Remove schedule
        new_agent_schedules = Map.delete(state.scheduled_operations[agent_pid], schedule_id)

        new_scheduled_operations =
          if map_size(new_agent_schedules) == 0 do
            Map.delete(state.scheduled_operations, agent_pid)
          else
            Map.put(state.scheduled_operations, agent_pid, new_agent_schedules)
          end

        # Update stats
        new_stats = Map.update!(state.stats, :total_schedules, &(&1 - 1))

        new_state = %{
          state
          | scheduled_operations: new_scheduled_operations,
            stats: new_stats
        }

        Logger.debug(
          "Unregistered periodic schedule #{schedule_id} for agent #{inspect(agent_pid)}"
        )

        {:reply, :ok, new_state}
    end
  end

  def handle_call({:unregister_agent, agent_pid}, _from, state) do
    case Map.get(state.scheduled_operations, agent_pid) do
      nil ->
        {:reply, :ok, state}

      agent_schedules ->
        # Cancel all timers for this agent
        Enum.each(agent_schedules, fn {_schedule_id, schedule_info} ->
          Process.cancel_timer(schedule_info.timer_ref)
        end)

        # Remove agent from schedules
        new_scheduled_operations = Map.delete(state.scheduled_operations, agent_pid)

        # Stop monitoring agent
        case Map.get(state.monitored_agents, agent_pid) do
          nil -> :ok
          monitor_ref -> Process.demonitor(monitor_ref, [:flush])
        end

        new_monitored_agents = Map.delete(state.monitored_agents, agent_pid)

        # Update stats
        schedule_count = map_size(agent_schedules)

        new_stats = %{
          state.stats
          | total_schedules: state.stats.total_schedules - schedule_count,
            active_agents: map_size(new_monitored_agents)
        }

        new_state = %{
          state
          | scheduled_operations: new_scheduled_operations,
            monitored_agents: new_monitored_agents,
            stats: new_stats
        }

        Logger.debug("Unregistered all schedules for agent #{inspect(agent_pid)}")

        {:reply, :ok, new_state}
    end
  end

  def handle_call({:update_interval, agent_pid, schedule_id, new_interval}, _from, state) do
    case get_in(state.scheduled_operations, [agent_pid, schedule_id]) do
      nil ->
        {:reply, {:error, :not_found}, state}

      schedule_info ->
        # Cancel current timer
        Process.cancel_timer(schedule_info.timer_ref)

        # Schedule with new interval
        new_timer_ref =
          Process.send_after(self(), {:execute_schedule, agent_pid, schedule_id}, new_interval)

        # Update schedule info
        updated_schedule_info = %{schedule_info | timer_ref: new_timer_ref, interval: new_interval}

        # Update state
        updated_agent_schedules =
          Map.put(state.scheduled_operations[agent_pid], schedule_id, updated_schedule_info)

        new_scheduled_operations =
          Map.put(state.scheduled_operations, agent_pid, updated_agent_schedules)

        new_state = %{state | scheduled_operations: new_scheduled_operations}

        Logger.debug("Updated interval for schedule #{schedule_id} to #{new_interval}ms")

        {:reply, :ok, new_state}
    end
  end

  def handle_call({:force_execution, agent_pid, schedule_id}, _from, state) do
    case get_in(state.scheduled_operations, [agent_pid, schedule_id]) do
      nil ->
        {:reply, {:error, :not_found}, state}

      _schedule_info ->
        # Send message immediately
        send(self(), {:execute_schedule, agent_pid, schedule_id})

        Logger.debug("Forced execution of schedule #{schedule_id} for agent #{inspect(agent_pid)}")

        {:reply, :ok, state}
    end
  end

  def handle_call(:get_stats, _from, state) do
    enhanced_stats =
      Map.merge(state.stats, %{
        active_agents: map_size(state.monitored_agents),
        total_active_schedules: count_active_schedules(state.scheduled_operations)
      })

    {:reply, enhanced_stats, state}
  end

  def handle_call({:list_agent_schedules, agent_pid}, _from, state) do
    case Map.get(state.scheduled_operations, agent_pid) do
      nil ->
        {:reply, {:error, :not_found}, state}

      agent_schedules ->
        schedule_list =
          Enum.map(agent_schedules, fn {schedule_id, schedule_info} ->
            %{
              schedule_id: schedule_id,
              interval: schedule_info.interval,
              message: schedule_info.message,
              last_run: schedule_info.last_run,
              created_at: schedule_info.created_at
            }
          end)

        {:reply, {:ok, schedule_list}, state}
    end
  end

  @impl true
  def handle_info({:execute_schedule, agent_pid, schedule_id}, state) do
    case get_in(state.scheduled_operations, [agent_pid, schedule_id]) do
      nil ->
        # Schedule no longer exists, ignore
        {:noreply, state}

      schedule_info ->
        # Check if agent is still alive
        if Process.alive?(agent_pid) do
          try do
            # Send the scheduled message to the agent with supervision
            result = SupervisedSend.send_supervised(
              agent_pid,
              schedule_info.message,
              timeout: 10_000,
              retries: Map.get(schedule_info, :retry_count, 1),
              on_error: :log,
              metadata: %{
                schedule_id: schedule_id,
                scheduled_at: DateTime.utc_now(),
                message_type: schedule_info.message
              }
            )
            
            # Log errors if delivery failed
            case result do
              {:error, reason} ->
                Logger.error("Scheduled message delivery failed",
                  agent_pid: inspect(agent_pid),
                  schedule_id: schedule_id,
                  reason: reason
                )
              :ok ->
                :ok
            end

            # Update last run timestamp regardless of success/failure
            updated_schedule_info = %{schedule_info | last_run: DateTime.utc_now()}

            # Schedule next execution
            new_timer_ref =
              Process.send_after(
                self(),
                {:execute_schedule, agent_pid, schedule_id},
                schedule_info.interval
              )

            final_schedule_info = %{updated_schedule_info | timer_ref: new_timer_ref}

            # Update state
            updated_agent_schedules =
              Map.put(state.scheduled_operations[agent_pid], schedule_id, final_schedule_info)

            new_scheduled_operations =
              Map.put(state.scheduled_operations, agent_pid, updated_agent_schedules)

            # Update stats
            new_stats = Map.update!(state.stats, :messages_sent, &(&1 + 1))

            new_state = %{
              state
              | scheduled_operations: new_scheduled_operations,
                stats: new_stats
            }

            Logger.debug("Executed schedule #{schedule_id} for agent #{inspect(agent_pid)}")

            {:noreply, new_state}
          catch
            kind, reason ->
              Logger.warning(
                "Failed to send scheduled message to agent #{inspect(agent_pid)}: #{kind} #{inspect(reason)}"
              )

              # Update failure stats
              new_stats = Map.update!(state.stats, :schedule_failures, &(&1 + 1))

              # Reschedule anyway (agent might recover)
              new_timer_ref =
                Process.send_after(
                  self(),
                  {:execute_schedule, agent_pid, schedule_id},
                  schedule_info.interval
                )

              updated_schedule_info = %{schedule_info | timer_ref: new_timer_ref}

              updated_agent_schedules =
                Map.put(state.scheduled_operations[agent_pid], schedule_id, updated_schedule_info)

              new_scheduled_operations =
                Map.put(state.scheduled_operations, agent_pid, updated_agent_schedules)

              new_state = %{
                state
                | scheduled_operations: new_scheduled_operations,
                  stats: new_stats
              }

              {:noreply, new_state}
          end
        else
          Logger.info(
            "Agent #{inspect(agent_pid)} is no longer alive, cancelling schedule #{schedule_id}"
          )

          # Agent is dead, remove all its schedules
          send(self(), {:agent_died, agent_pid})
          {:noreply, state}
        end
    end
  end

  def handle_info({:agent_died, agent_pid}, state) do
    # Clean up all schedules for the dead agent
    case unregister_agent_internal(agent_pid, state) do
      new_state ->
        Logger.info("Cleaned up schedules for dead agent #{inspect(agent_pid)}")
        {:noreply, new_state}
    end
  end

  def handle_info({:DOWN, _ref, :process, agent_pid, reason}, state) do
    Logger.info("Monitored agent #{inspect(agent_pid)} went down: #{inspect(reason)}")

    # Clean up schedules for this agent
    new_state = unregister_agent_internal(agent_pid, state)
    {:noreply, new_state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("SchedulerManager terminating: #{inspect(reason)}")

    # Cancel all active timers
    Enum.each(state.scheduled_operations, fn {_agent_pid, agent_schedules} ->
      Enum.each(agent_schedules, fn {_schedule_id, schedule_info} ->
        Process.cancel_timer(schedule_info.timer_ref)
      end)
    end)

    # Clean up all process monitors
    Enum.each(state.monitored_agents, fn {_agent_pid, monitor_ref} ->
      Process.demonitor(monitor_ref, [:flush])
    end)

    :ok
  end

  # Private helper functions

  defp ensure_monitored(agent_pid, state) do
    case Map.get(state.monitored_agents, agent_pid) do
      nil ->
        # Not monitored, start monitoring
        monitor_ref = Process.monitor(agent_pid)
        new_monitored_agents = Map.put(state.monitored_agents, agent_pid, monitor_ref)
        new_stats = Map.put(state.stats, :active_agents, map_size(new_monitored_agents))

        Logger.debug("Started monitoring agent #{inspect(agent_pid)}")

        %{state | monitored_agents: new_monitored_agents, stats: new_stats}

      _existing ->
        # Already monitored
        state
    end
  end

  defp cancel_existing_timer(agent_pid, schedule_id, state) do
    case get_in(state.scheduled_operations, [agent_pid, schedule_id]) do
      nil ->
        state

      schedule_info ->
        Process.cancel_timer(schedule_info.timer_ref)

        # Remove the old schedule
        agent_schedules = Map.delete(state.scheduled_operations[agent_pid], schedule_id)

        new_scheduled_operations =
          if map_size(agent_schedules) == 0 do
            Map.delete(state.scheduled_operations, agent_pid)
          else
            Map.put(state.scheduled_operations, agent_pid, agent_schedules)
          end

        %{state | scheduled_operations: new_scheduled_operations}
    end
  end

  defp unregister_agent_internal(agent_pid, state) do
    # Cancel all timers for this agent
    case Map.get(state.scheduled_operations, agent_pid) do
      nil ->
        state

      agent_schedules ->
        Enum.each(agent_schedules, fn {_schedule_id, schedule_info} ->
          Process.cancel_timer(schedule_info.timer_ref)
        end)

        # Remove agent from schedules
        new_scheduled_operations = Map.delete(state.scheduled_operations, agent_pid)

        # Stop monitoring agent
        case Map.get(state.monitored_agents, agent_pid) do
          nil -> :ok
          monitor_ref -> Process.demonitor(monitor_ref, [:flush])
        end

        new_monitored_agents = Map.delete(state.monitored_agents, agent_pid)

        # Update stats
        schedule_count = map_size(agent_schedules)

        new_stats = %{
          state.stats
          | total_schedules: state.stats.total_schedules - schedule_count,
            active_agents: map_size(new_monitored_agents)
        }

        %{
          state
          | scheduled_operations: new_scheduled_operations,
            monitored_agents: new_monitored_agents,
            stats: new_stats
        }
    end
  end

  defp count_active_schedules(scheduled_operations) do
    Enum.reduce(scheduled_operations, 0, fn {_agent_pid, agent_schedules}, acc ->
      acc + map_size(agent_schedules)
    end)
  end
end
