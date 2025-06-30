defmodule JidoFoundation.AgentMonitor do
  @moduledoc """
  Supervised GenServer for monitoring Jido agent health and updating Foundation registry.

  This replaces the unsupervised monitoring processes previously spawned by Bridge,
  providing proper OTP supervision, graceful shutdown, and resource cleanup.

  ## Features

  - Proper GenServer lifecycle management
  - Health check scheduling with configurable intervals
  - Registry metadata updates on health status changes
  - Graceful shutdown with timer cleanup
  - Process monitoring with automatic cleanup

  ## Architecture

  Instead of spawning unsupervised processes with infinite receive loops,
  this module provides a proper GenServer that:
  1. Uses GenServer timer management
  2. Integrates with OTP supervision trees
  3. Handles termination gracefully
  4. Cleans up all resources on shutdown

  ## Usage

      # Start monitoring for an agent (handled by supervisor)
      {:ok, monitor_pid} = JidoFoundation.AgentMonitor.start_link([
        agent_pid: agent_pid,
        health_check: &custom_health_check/1,
        interval: 30_000,
        registry: Foundation.Registry
      ])

      # Stop monitoring (handled by supervisor)
      JidoFoundation.AgentMonitor.stop_monitoring(monitor_pid)
  """

  use GenServer
  require Logger

  @default_health_check &__MODULE__.default_health_check/1
  @default_interval 30_000

  defstruct [
    :agent_pid,
    :health_check,
    :interval,
    :registry,
    :monitor_ref,
    :timer_ref,
    :last_health_status
  ]

  @type t :: %__MODULE__{
          agent_pid: pid(),
          health_check: (pid() -> :healthy | :degraded | :unhealthy),
          interval: non_neg_integer(),
          registry: module() | nil,
          monitor_ref: reference() | nil,
          timer_ref: reference() | nil,
          last_health_status: :healthy | :degraded | :unhealthy | nil
        }

  # Client API

  @doc """
  Starts an agent monitor GenServer.

  ## Options

  - `:agent_pid` - PID of the agent to monitor (required)
  - `:health_check` - Health check function (default: process alive check)
  - `:interval` - Health check interval in milliseconds (default: 30,000)
  - `:registry` - Registry module for metadata updates (optional)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    agent_pid = Keyword.fetch!(opts, :agent_pid)

    # Generate unique name for this monitor
    name = {:via, Registry, {JidoFoundation.MonitorRegistry, agent_pid}}

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns a child specification for use in supervision trees.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    agent_pid = Keyword.fetch!(opts, :agent_pid)

    %{
      id: {__MODULE__, agent_pid},
      start: {__MODULE__, :start_link, [opts]},
      # Don't restart if agent is dead
      restart: :transient,
      shutdown: 5_000,
      type: :worker
    }
  end

  @doc """
  Stops monitoring for a specific agent.
  """
  @spec stop_monitoring(pid()) :: :ok
  def stop_monitoring(agent_pid) when is_pid(agent_pid) do
    case Registry.lookup(JidoFoundation.MonitorRegistry, agent_pid) do
      [{monitor_pid, _}] ->
        GenServer.stop(monitor_pid, :normal)

      [] ->
        # Already stopped
        :ok
    end
  end

  @doc """
  Gets the current health status for a monitored agent.
  """
  @spec get_health_status(pid()) :: {:ok, atom()} | {:error, :not_monitored}
  def get_health_status(agent_pid) when is_pid(agent_pid) do
    case Registry.lookup(JidoFoundation.MonitorRegistry, agent_pid) do
      [{monitor_pid, _}] ->
        GenServer.call(monitor_pid, :get_health_status)

      [] ->
        {:error, :not_monitored}
    end
  end

  @doc """
  Forces an immediate health check for a monitored agent.
  """
  @spec force_health_check(pid()) :: :ok | {:error, :not_monitored}
  def force_health_check(agent_pid) when is_pid(agent_pid) do
    case Registry.lookup(JidoFoundation.MonitorRegistry, agent_pid) do
      [{monitor_pid, _}] ->
        GenServer.cast(monitor_pid, :force_health_check)

      [] ->
        {:error, :not_monitored}
    end
  end

  @doc """
  Default health check implementation - simple process alive check.
  """
  @spec default_health_check(pid()) :: :healthy | :unhealthy
  def default_health_check(agent_pid) when is_pid(agent_pid) do
    if Process.alive?(agent_pid) do
      :healthy
    else
      :unhealthy
    end
  end

  # GenServer implementation

  @impl true
  def init(opts) do
    agent_pid = Keyword.fetch!(opts, :agent_pid)
    health_check = Keyword.get(opts, :health_check, @default_health_check)
    interval = Keyword.get(opts, :interval, @default_interval)
    registry = Keyword.get(opts, :registry)

    # Verify agent is alive before starting monitoring
    unless Process.alive?(agent_pid) do
      Logger.warning("Agent #{inspect(agent_pid)} is not alive, stopping monitor")
      {:stop, :agent_not_alive}
    else
      # Set up process monitoring
      monitor_ref = Process.monitor(agent_pid)

      state = %__MODULE__{
        agent_pid: agent_pid,
        health_check: health_check,
        interval: interval,
        registry: registry,
        monitor_ref: monitor_ref,
        timer_ref: nil,
        last_health_status: nil
      }

      # Schedule first health check
      timer_ref = Process.send_after(self(), :health_check, 0)
      state = %{state | timer_ref: timer_ref}

      Logger.debug("Started agent monitor for #{inspect(agent_pid)}")

      {:ok, state}
    end
  end

  @impl true
  def handle_call(:get_health_status, _from, state) do
    {:reply, {:ok, state.last_health_status}, state}
  end

  @impl true
  def handle_cast(:force_health_check, state) do
    # Cancel current timer and perform immediate check
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    send(self(), :health_check)
    {:noreply, %{state | timer_ref: nil}}
  end

  @impl true
  def handle_info(:health_check, state) do
    # Perform health check
    health_status = state.health_check.(state.agent_pid)

    # Update registry if status changed
    new_state = update_registry_if_changed(state, health_status)

    # Schedule next health check
    timer_ref = Process.send_after(self(), :health_check, state.interval)
    new_state = %{new_state | timer_ref: timer_ref, last_health_status: health_status}

    {:noreply, new_state}
  end

  def handle_info({:DOWN, ref, :process, agent_pid, reason}, %{monitor_ref: ref} = state) do
    Logger.info("Monitored agent #{inspect(agent_pid)} went down: #{inspect(reason)}")

    # Update registry to reflect agent death
    final_state = update_registry_if_changed(state, :unhealthy)

    # Stop monitoring since agent is dead
    {:stop, :normal, final_state}
  end

  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    # Different process went down, ignore
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    # Ignore unknown messages
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug("Agent monitor terminating: #{inspect(reason)}")

    # Cancel any pending timer
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    # Final registry update on shutdown
    if is_atom(state.registry) and not is_nil(state.registry) and
         state.last_health_status != :unhealthy do
      try do
        JidoFoundation.Bridge.update_agent_metadata(
          state.agent_pid,
          %{health_status: :unhealthy},
          registry: state.registry
        )
      catch
        _, _ -> :ok
      end
    end

    :ok
  end

  # Private helper functions

  defp update_registry_if_changed(state, new_health_status) do
    if is_atom(state.registry) and not is_nil(state.registry) and
         new_health_status != state.last_health_status do
      try do
        JidoFoundation.Bridge.update_agent_metadata(
          state.agent_pid,
          %{health_status: new_health_status},
          registry: state.registry
        )

        Logger.debug(
          "Updated agent #{inspect(state.agent_pid)} health status to #{new_health_status}"
        )
      catch
        kind, reason ->
          Logger.warning(
            "Failed to update registry for agent #{inspect(state.agent_pid)}: #{kind} #{inspect(reason)}"
          )
      end
    end

    state
  end
end
