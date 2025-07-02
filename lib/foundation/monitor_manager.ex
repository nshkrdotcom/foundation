defmodule Foundation.MonitorManager do
  @moduledoc """
  Centralized monitor management to prevent monitor leaks.

  This module ensures all monitors are properly cleaned up and provides
  visibility into active monitors for debugging and monitoring.

  ## Features

  - Automatic cleanup on process termination
  - Monitor lifecycle tracking with full metadata
  - Telemetry integration for observability
  - Debug interface for finding leaks
  - Caller death detection and orphan cleanup
  - Stack trace capture for debugging

  ## Usage

      # Monitor a process
      {:ok, ref} = MonitorManager.monitor(pid, :my_feature)
      
      # Demonitor when done
      :ok = MonitorManager.demonitor(ref)
      
      # List all monitors
      monitors = MonitorManager.list_monitors()
      
      # Get statistics
      stats = MonitorManager.get_stats()
      
      # Find potential leaks
      leaks = MonitorManager.find_leaks(:timer.minutes(5))

  ## Integration with Test Mode

  In test mode, the MonitorManager will send completion notifications to the
  configured test PID using the same pattern as other Foundation services.
  """

  use GenServer
  require Logger

  @default_leak_age :timer.minutes(5)
  @leak_check_interval :timer.minutes(5)

  defstruct monitors: %{},
            reverse_lookup: %{},
            stats: %{created: 0, cleaned: 0, leaked: 0}

  # Client API

  @doc """
  Starts the MonitorManager service.
  Usually started as part of the Foundation supervision tree.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Monitor a process with automatic cleanup.

  The tag parameter helps identify the source of monitors for debugging.
  Returns `{:ok, ref}` on success or `{:error, reason}` on failure.

  ## Examples

      # Basic monitoring
      {:ok, ref} = MonitorManager.monitor(pid, :my_feature)
      
      # With descriptive tag for debugging
      {:ok, ref} = MonitorManager.monitor(worker_pid, :worker_pool_monitor)
  """
  @spec monitor(pid(), atom() | String.t()) :: {:ok, reference()} | {:error, term()}
  def monitor(pid, tag \\ :untagged) when is_pid(pid) do
    try do
      GenServer.call(__MODULE__, {:monitor, pid, tag, self()}, 5000)
    catch
      :exit, {:noproc, _} -> {:error, :monitor_manager_unavailable}
      :exit, {:timeout, _} -> {:error, :timeout}
    end
  end

  @doc """
  Demonitor a process and flush DOWN messages.

  Returns `:ok` on success or `{:error, :not_found}` if the monitor reference
  was not found in our tracking system.
  """
  @spec demonitor(reference()) :: :ok | {:error, :not_found}
  def demonitor(ref) when is_reference(ref) do
    try do
      GenServer.call(__MODULE__, {:demonitor, ref}, 5000)
    catch
      :exit, {:noproc, _} -> {:error, :monitor_manager_unavailable}
      :exit, {:timeout, _} -> {:error, :timeout}
    end
  end

  @doc """
  List all active monitors with metadata.

  Returns a list of maps containing monitor information including:
  - `ref`: The monitor reference
  - `pid`: The monitored process PID
  - `tag`: The descriptive tag
  - `caller`: The process that created the monitor
  - `age_ms`: How long the monitor has been active
  - `alive`: Whether the monitored process is still alive
  """
  @spec list_monitors() :: [map()]
  def list_monitors do
    try do
      GenServer.call(__MODULE__, :list_monitors, 5000)
    catch
      :exit, {:noproc, _} -> []
      :exit, {:timeout, _} -> []
    end
  end

  @doc """
  Get monitoring statistics.

  Returns a map with:
  - `created`: Total monitors created
  - `cleaned`: Total monitors cleaned up
  - `leaked`: Total leaks detected
  - `active`: Currently active monitors
  """
  @spec get_stats() :: map()
  def get_stats do
    try do
      GenServer.call(__MODULE__, :get_stats, 5000)
    catch
      :exit, {:noproc, _} -> %{created: 0, cleaned: 0, leaked: 0, active: 0}
      :exit, {:timeout, _} -> %{created: 0, cleaned: 0, leaked: 0, active: 0}
    end
  end

  @doc """
  Find potential monitor leaks (monitors older than specified age).

  A leak is defined as a monitor that:
  - Is older than the specified age
  - The monitored process is still alive
  - The caller process is still alive

  This indicates the monitor should have been cleaned up but wasn't.

  ## Examples

      # Find monitors older than 5 minutes (default)
      leaks = MonitorManager.find_leaks()
      
      # Find monitors older than 1 minute
      leaks = MonitorManager.find_leaks(:timer.minutes(1))
  """
  @spec find_leaks(timeout()) :: [map()]
  def find_leaks(age_ms \\ @default_leak_age) do
    try do
      GenServer.call(__MODULE__, {:find_leaks, age_ms}, 5000)
    catch
      :exit, {:noproc, _} -> []
      :exit, {:timeout, _} -> []
    end
  end

  # Server implementation

  @impl true
  def init(_opts) do
    # Schedule periodic leak detection
    schedule_leak_check()

    state = %__MODULE__{
      monitors: %{},
      reverse_lookup: %{},
      stats: %{created: 0, cleaned: 0, leaked: 0}
    }

    Logger.info("MonitorManager started successfully")

    {:ok, state}
  end

  @impl true
  def handle_call({:monitor, pid, tag, caller}, _from, state) do
    case Process.alive?(pid) do
      false ->
        {:reply, {:error, :noproc}, state}

      true ->
        # Create the actual monitor
        ref = Process.monitor(pid)

        # Also monitor the caller to clean up if they die
        caller_ref = Process.monitor(caller)

        # Store metadata with stack trace for debugging
        monitor_info = %{
          ref: ref,
          pid: pid,
          tag: tag,
          caller: caller,
          caller_ref: caller_ref,
          created_at: System.monotonic_time(:millisecond),
          stack_trace: get_caller_stack_trace()
        }

        # Monitor info is stored in GenServer state

        # Update state
        new_monitors = Map.put(state.monitors, ref, monitor_info)

        # Ensure reverse lookup structure exists
        new_reverse_lookup =
          state.reverse_lookup
          |> Map.put_new(pid, %{})
          |> put_in([pid, ref], true)
          |> Map.put_new(caller, %{})
          |> put_in([caller, caller_ref], true)

        new_stats = Map.update!(state.stats, :created, &(&1 + 1))

        new_state = %{
          state
          | monitors: new_monitors,
            reverse_lookup: new_reverse_lookup,
            stats: new_stats
        }

        # Emit telemetry
        :telemetry.execute(
          [:foundation, :monitor_manager, :monitor_created],
          %{count: 1},
          %{tag: tag, caller: inspect(caller)}
        )

        # Notify test if in test mode
        maybe_notify_test(:monitor_created, %{ref: ref, tag: tag})

        {:reply, {:ok, ref}, new_state}
    end
  end

  @impl true
  def handle_call({:demonitor, ref}, _from, state) do
    case Map.get(state.monitors, ref) do
      nil ->
        {:reply, {:error, :not_found}, state}

      monitor_info ->
        # Demonitor the process (flush any pending DOWN messages)
        Process.demonitor(ref, [:flush])

        # Demonitor the caller if still monitored
        if Process.demonitor(monitor_info.caller_ref, [:flush, :info]) != false do
          # Caller monitor was still active
        end

        # Monitor cleaned up from GenServer state below

        # Clean up state
        new_monitors = Map.delete(state.monitors, ref)

        new_reverse_lookup =
          state.reverse_lookup
          |> update_in([monitor_info.pid], &Map.delete(&1 || %{}, ref))
          |> update_in([monitor_info.caller], &Map.delete(&1 || %{}, monitor_info.caller_ref))

        new_stats = Map.update!(state.stats, :cleaned, &(&1 + 1))

        new_state = %{
          state
          | monitors: new_monitors,
            reverse_lookup: new_reverse_lookup,
            stats: new_stats
        }

        # Clean up empty entries in reverse lookup
        new_state = cleanup_reverse_lookup(new_state, monitor_info.pid)
        new_state = cleanup_reverse_lookup(new_state, monitor_info.caller)

        # Emit telemetry
        duration = System.monotonic_time(:millisecond) - monitor_info.created_at

        :telemetry.execute(
          [:foundation, :monitor_manager, :monitor_cleaned],
          %{duration: duration},
          %{tag: monitor_info.tag, manual_cleanup: true}
        )

        # Notify test if in test mode
        maybe_notify_test(:monitor_cleaned, %{ref: ref, tag: monitor_info.tag})

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:list_monitors, _from, state) do
    monitors =
      Enum.map(state.monitors, fn {ref, info} ->
        %{
          ref: ref,
          pid: info.pid,
          tag: info.tag,
          caller: info.caller,
          age_ms: System.monotonic_time(:millisecond) - info.created_at,
          alive: Process.alive?(info.pid),
          created_at: info.created_at,
          stack_trace: info.stack_trace
        }
      end)

    {:reply, monitors, state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = Map.put(state.stats, :active, map_size(state.monitors))
    {:reply, stats, state}
  end

  @impl true
  def handle_call({:find_leaks, age_ms}, _from, state) do
    leaks = find_leaks_internal(state, age_ms)
    {:reply, leaks, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    # Check if this is a monitored process or a caller
    new_state =
      cond do
        # It's a monitored process
        Map.has_key?(state.monitors, ref) ->
          handle_monitored_process_down(ref, pid, reason, state)

        # It's a caller process - clean up their monitors
        Map.has_key?(Map.get(state.reverse_lookup, pid, %{}), ref) ->
          handle_caller_down(pid, ref, state)

        # Unknown monitor (shouldn't happen but handle gracefully)
        true ->
          Logger.debug("Received DOWN for unknown monitor", ref: ref, pid: inspect(pid))
          state
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:check_for_leaks, state) do
    leaks = find_leaks_internal(state, @default_leak_age)

    if length(leaks) > 0 do
      Logger.warning("Monitor leaks detected",
        count: length(leaks),
        tags: Enum.map(leaks, & &1.tag) |> Enum.frequencies()
      )

      # Log details about leaks for debugging
      Enum.each(leaks, fn leak ->
        Logger.debug("Monitor leak details",
          ref: inspect(leak.ref),
          tag: leak.tag,
          age_ms: leak.age_ms,
          caller: inspect(leak.caller),
          stack_trace: Enum.take(leak.stack_trace, 3)
        )
      end)

      new_stats = Map.update!(state.stats, :leaked, &(&1 + length(leaks)))
      new_state = %{state | stats: new_stats}

      :telemetry.execute(
        [:foundation, :monitor_manager, :leaks_detected],
        %{count: length(leaks)},
        %{tags: Enum.map(leaks, & &1.tag)}
      )

      # Notify test if in test mode
      maybe_notify_test(:leaks_detected, %{count: length(leaks)})

      schedule_leak_check()
      {:noreply, new_state}
    else
      schedule_leak_check()
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("MonitorManager received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # Private functions

  defp handle_monitored_process_down(ref, pid, reason, state) do
    case Map.get(state.monitors, ref) do
      nil ->
        Logger.debug("DOWN message for unknown monitor", ref: ref, pid: inspect(pid))
        state

      monitor_info ->
        # Clean up the caller monitor
        Process.demonitor(monitor_info.caller_ref, [:flush, :info])

        # Monitor cleaned up from GenServer state below

        # Update state  
        new_monitors = Map.delete(state.monitors, ref)

        new_reverse_lookup =
          state.reverse_lookup
          |> update_in([pid], &Map.delete(&1 || %{}, ref))
          |> update_in([monitor_info.caller], &Map.delete(&1 || %{}, monitor_info.caller_ref))

        new_stats = Map.update!(state.stats, :cleaned, &(&1 + 1))

        new_state =
          %{state | monitors: new_monitors, reverse_lookup: new_reverse_lookup, stats: new_stats}
          |> cleanup_reverse_lookup(pid)
          |> cleanup_reverse_lookup(monitor_info.caller)

        # Emit telemetry
        duration = System.monotonic_time(:millisecond) - monitor_info.created_at

        :telemetry.execute(
          [:foundation, :monitor_manager, :monitor_cleaned],
          %{duration: duration},
          %{tag: monitor_info.tag, reason: reason, automatic: true}
        )

        # Notify test if in test mode
        maybe_notify_test(:automatic_cleanup, %{ref: ref, tag: monitor_info.tag, reason: reason})

        new_state
    end
  end

  defp handle_caller_down(caller_pid, _ref, state) do
    # Find all monitors created by this caller
    monitors_to_clean =
      state.monitors
      |> Enum.filter(fn {_ref, info} -> info.caller == caller_pid end)
      |> Enum.map(fn {ref, _info} -> ref end)

    Logger.debug("Cleaning up monitors for dead caller",
      caller: inspect(caller_pid),
      monitor_count: length(monitors_to_clean)
    )

    # Clean them all up
    new_state =
      Enum.reduce(monitors_to_clean, state, fn ref, acc_state ->
        case Map.get(acc_state.monitors, ref) do
          nil ->
            acc_state

          monitor_info ->
            # Demonitor the target process
            Process.demonitor(ref, [:flush])

            # Monitor cleaned up from GenServer state below

            # Clean up state
            new_monitors = Map.delete(acc_state.monitors, ref)

            new_reverse_lookup =
              update_in(acc_state.reverse_lookup, [monitor_info.pid], &Map.delete(&1 || %{}, ref))

            new_stats = Map.update!(acc_state.stats, :cleaned, &(&1 + 1))

            %{
              acc_state
              | monitors: new_monitors,
                reverse_lookup: new_reverse_lookup,
                stats: new_stats
            }
            |> cleanup_reverse_lookup(monitor_info.pid)
        end
      end)

    final_reverse_lookup = Map.delete(new_state.reverse_lookup, caller_pid)
    %{new_state | reverse_lookup: final_reverse_lookup}

    # Emit telemetry for caller cleanup
    :telemetry.execute(
      [:foundation, :monitor_manager, :caller_cleanup],
      %{monitor_count: length(monitors_to_clean)},
      %{caller: inspect(caller_pid)}
    )

    # Notify test if in test mode
    maybe_notify_test(:caller_cleanup, %{caller: caller_pid, count: length(monitors_to_clean)})

    new_state
  end

  defp cleanup_reverse_lookup(state, pid) do
    case get_in(state.reverse_lookup, [pid]) do
      nil ->
        state

      map when map_size(map) == 0 ->
        new_reverse_lookup = Map.delete(state.reverse_lookup, pid)
        %{state | reverse_lookup: new_reverse_lookup}

      _ ->
        state
    end
  end

  defp find_leaks_internal(state, age_ms) do
    now = System.monotonic_time(:millisecond)

    state.monitors
    |> Enum.filter(fn {_ref, info} ->
      now - info.created_at > age_ms and
        Process.alive?(info.pid) and
        Process.alive?(info.caller)
    end)
    |> Enum.map(fn {ref, info} ->
      %{
        ref: ref,
        pid: info.pid,
        tag: info.tag,
        caller: info.caller,
        age_ms: now - info.created_at,
        stack_trace: info.stack_trace,
        created_at: info.created_at
      }
    end)
  end

  defp get_caller_stack_trace do
    case Process.info(self(), :current_stacktrace) do
      {:current_stacktrace, trace} ->
        # Remove MonitorManager frames and take first 5 meaningful frames
        trace
        |> Enum.drop_while(fn {module, _fun, _arity, _location} ->
          module == __MODULE__ or module == GenServer
        end)
        |> Enum.take(5)
        |> Enum.map(&format_stack_frame/1)

      nil ->
        ["<stack trace unavailable>"]
    end
  end

  defp format_stack_frame({module, function, arity, location}) do
    file = Keyword.get(location, :file, "unknown")
    line = Keyword.get(location, :line, 0)
    "#{module}.#{function}/#{arity} (#{file}:#{line})"
  end

  defp schedule_leak_check do
    Process.send_after(self(), :check_for_leaks, @leak_check_interval)
  end

  # Test mode support following Foundation patterns
  defp maybe_notify_test(event_type, metadata) do
    if test_mode?() do
      case Application.get_env(:foundation, :test_pid) do
        pid when is_pid(pid) ->
          send(pid, {:monitor_manager, event_type, metadata})

        _ ->
          :ok
      end
    end
  end

  defp test_mode? do
    Application.get_env(:foundation, :test_mode, false)
  end
end
