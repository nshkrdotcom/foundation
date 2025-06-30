defmodule Foundation.Telemetry.LoadTest.Coordinator do
  @moduledoc """
  Coordinates load generation for telemetry-based load tests.

  This module manages worker processes that execute test scenarios according
  to configured concurrency levels and scenario weights.
  """

  use GenServer
  require Logger

  defmodule State do
    @moduledoc false
    defstruct [
      :context,
      :workers,
      :scenario_distribution,
      :active,
      :start_time,
      :ramp_up_ref
    ]
  end

  def start_link(context) do
    GenServer.start_link(__MODULE__, context)
  end

  def start_load(coordinator) do
    GenServer.call(coordinator, :start_load)
  end

  def stop_load(coordinator) do
    GenServer.call(coordinator, :stop_load)
  end

  def get_stats(coordinator) do
    GenServer.call(coordinator, :get_stats)
  end

  # GenServer callbacks

  @impl true
  def init(context) do
    state = %State{
      context: context,
      workers: [],
      scenario_distribution: build_scenario_distribution(context.scenarios),
      active: false,
      start_time: nil,
      ramp_up_ref: nil
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:start_load, _from, state) do
    if state.active do
      {:reply, {:error, :already_started}, state}
    else
      new_state = start_load_generation(state)
      {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:stop_load, _from, state) do
    new_state = stop_load_generation(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      active: state.active,
      worker_count: length(state.workers),
      uptime_ms: if(state.start_time, do: System.monotonic_time() - state.start_time, else: 0)
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_info({:ramp_up, target_workers}, state) do
    current_workers = length(state.workers)

    if current_workers < target_workers do
      # Add more workers
      workers_to_add = min(10, target_workers - current_workers)
      new_workers = start_workers(workers_to_add, state)

      # Schedule next ramp-up
      ref = Process.send_after(self(), {:ramp_up, target_workers}, 100)

      {:noreply, %{state | workers: state.workers ++ new_workers, ramp_up_ref: ref}}
    else
      # Ramp-up complete
      Logger.info("Load test ramp-up complete: #{target_workers} workers active")
      {:noreply, %{state | ramp_up_ref: nil}}
    end
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    if state.active and pid in state.workers do
      # Worker crashed, restart it
      case reason do
        :killed ->
          Logger.debug("Load test worker #{inspect(pid)} was killed, restarting...")

        :shutdown ->
          Logger.debug("Load test worker #{inspect(pid)} shutdown, not restarting")

        _ ->
          Logger.warning("Load test worker crashed: #{inspect(reason)}, restarting...")
      end

      # Only restart if still active and not shutdown
      if state.active and reason != :shutdown do
        new_worker = start_worker(state)
        new_workers = [new_worker | List.delete(state.workers, pid)]
        {:noreply, %{state | workers: new_workers}}
      else
        new_workers = List.delete(state.workers, pid)
        {:noreply, %{state | workers: new_workers}}
      end
    else
      {:noreply, state}
    end
  end

  # Private functions

  defp start_load_generation(state) do
    target_workers = state.context.opts[:concurrency]
    ramp_up = state.context.opts[:ramp_up]

    if ramp_up > 0 do
      # Start with 1 worker and ramp up
      workers = start_workers(1, state)
      ref = Process.send_after(self(), {:ramp_up, target_workers}, 100)

      %{
        state
        | active: true,
          start_time: System.monotonic_time(),
          workers: workers,
          ramp_up_ref: ref
      }
    else
      # Start all workers immediately
      workers = start_workers(target_workers, state)

      %{state | active: true, start_time: System.monotonic_time(), workers: workers}
    end
  end

  defp stop_load_generation(state) do
    # Cancel ramp-up if in progress
    if state.ramp_up_ref do
      Process.cancel_timer(state.ramp_up_ref)
    end

    # Stop all workers with shutdown signal
    Enum.each(state.workers, &Process.exit(&1, :shutdown))

    %{state | active: false, workers: [], ramp_up_ref: nil}
  end

  defp start_workers(count, state) do
    Enum.map(1..count, fn _ -> start_worker(state) end)
  end

  defp start_worker(state) do
    config = %{
      scenario_distribution: state.scenario_distribution,
      context: state.context,
      telemetry_prefix: state.context.opts[:telemetry_prefix]
    }

    if Enum.empty?(state.scenario_distribution) do
      Logger.error("Coordinator starting worker with empty scenario distribution!")
    end

    {:ok, pid} = Foundation.Telemetry.LoadTest.Worker.start_link(config)

    Process.monitor(pid)
    pid
  end

  defp build_scenario_distribution(scenarios) do
    if Enum.empty?(scenarios) do
      Logger.error("Building distribution with empty scenarios!")
      []
    else
      total_weight = Enum.sum(Enum.map(scenarios, & &1.weight))

      scenarios
      |> Enum.reduce({[], 0}, fn scenario, {acc, cumulative} ->
        upper_bound = cumulative + scenario.weight / total_weight
        entry = {cumulative, upper_bound, scenario}
        {[entry | acc], upper_bound}
      end)
      |> elem(0)
      |> Enum.reverse()
    end
  end
end
