defmodule Foundation.Telemetry.LoadTest.Worker do
  @moduledoc """
  Worker process that executes load test scenarios.

  Each worker continuously executes scenarios based on their configured weights,
  emitting telemetry events for each execution.
  """

  use GenServer
  require Logger

  defmodule State do
    @moduledoc false
    defstruct [
      :scenario_distribution,
      :context,
      :telemetry_prefix,
      :worker_id,
      :execution_count
    ]
  end

  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  # GenServer callbacks

  @impl true
  def init(config) do
    state = %State{
      scenario_distribution: config.scenario_distribution,
      context: config.context,
      telemetry_prefix: config.telemetry_prefix,
      worker_id: generate_worker_id(),
      execution_count: 0
    }

    # Debug logging
    if Enum.empty?(config.scenario_distribution) do
      Logger.error("Worker initialized with empty scenario distribution!")
    else
      Logger.debug(
        "Worker #{state.worker_id} initialized with #{length(config.scenario_distribution)} scenarios"
      )
    end

    # Start executing immediately
    send(self(), :execute)

    {:ok, state}
  end

  @impl true
  def handle_info(:execute, state) do
    # Select and execute a scenario
    case select_scenario(state.scenario_distribution) do
      nil ->
        Logger.error(
          "Worker #{state.worker_id} failed to select scenario from distribution: #{inspect(state.scenario_distribution)}"
        )

        # Try again after a short delay
        Process.send_after(self(), :execute, 100)
        {:noreply, state}

      scenario ->
        # Execute with telemetry tracking
        start_time = System.monotonic_time()

        metadata = %{
          worker_id: state.worker_id,
          scenario_name: scenario.name,
          test_id: state.context.test_id
        }

        # Emit start event
        :telemetry.execute(
          state.telemetry_prefix ++ [:scenario, :start],
          %{timestamp: System.system_time()},
          metadata
        )

        # Execute scenario
        result = execute_scenario(scenario, state)

        # Calculate duration
        duration = System.monotonic_time() - start_time

        # Emit stop event
        {status, error} =
          case result do
            {:ok, _} -> {:ok, nil}
            {:error, reason} -> {:error, inspect(reason)}
            {:exit, reason} -> {:error, "exit: #{inspect(reason)}"}
            {:throw, value} -> {:error, "throw: #{inspect(value)}"}
          end

        :telemetry.execute(
          state.telemetry_prefix ++ [:scenario, :stop],
          %{
            duration: duration,
            timestamp: System.system_time()
          },
          Map.merge(metadata, %{
            status: status,
            error: error
          })
        )

        # Continue executing immediately
        send(self(), :execute)

        {:noreply, %{state | execution_count: state.execution_count + 1}}
    end
  end

  # Private functions

  defp select_scenario(distribution) do
    rand = :rand.uniform()

    Enum.find_value(distribution, fn {lower, upper, scenario} ->
      if rand >= lower and rand < upper do
        scenario
      end
    end)
  end

  defp execute_scenario(scenario, state) do
    # Build execution context
    exec_context =
      Map.merge(state.context, %{
        worker_id: state.worker_id,
        execution_count: state.execution_count,
        scenario_name: scenario.name
      })

    # Debug logging for first execution
    if state.execution_count == 0 do
      Logger.debug("Worker #{state.worker_id} executing first scenario #{scenario.name}")
    end

    # Run setup if defined
    exec_context =
      if scenario[:setup] do
        case scenario.setup.(exec_context) do
          {:ok, updated_context} -> Map.merge(exec_context, updated_context)
          _ -> exec_context
        end
      else
        exec_context
      end

    # Execute with timeout in an unlinked task to prevent crashes from propagating
    timeout = state.context.opts[:scenario_timeout]
    parent = self()
    ref = make_ref()

    # Use Task.start instead of Task.async to avoid linking
    {:ok, task_pid} =
      Task.start(fn ->
        result =
          try do
            scenario.run.(exec_context)
          catch
            kind, reason ->
              {:caught, kind, reason}
          end

        send(parent, {ref, result})
      end)

    # Wait for result with timeout
    result =
      receive do
        {^ref, {:caught, :throw, value}} ->
          {:throw, value}

        {^ref, {:caught, :error, reason}} ->
          {:error, reason}

        {^ref, {:caught, :exit, reason}} ->
          {:exit, reason}

        {^ref, result} ->
          {:ok, result}
      after
        timeout ->
          Process.exit(task_pid, :kill)
          {:error, :timeout}
      end

    # Run teardown if defined
    if scenario[:teardown] do
      scenario.teardown.(exec_context)
    end

    result
  end

  defp generate_worker_id do
    :crypto.strong_rand_bytes(4)
    |> Base.encode16(case: :lower)
  end
end
