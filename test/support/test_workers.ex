defmodule Foundation.TestHelpers.TestWorker do
  @moduledoc """
  Basic test worker for registry testing.

  This is a simple GenServer that can be used in tests to simulate
  real processes being registered in the registry.
  """
  use GenServer

  @type state :: %{
          id: atom(),
          start_time: DateTime.t(),
          task_count: non_neg_integer()
        }

  def start_link(opts \\ []) do
    id = Keyword.get(opts, :id, :test_worker)
    GenServer.start_link(__MODULE__, [id: id], opts)
  end

  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  def simulate_work(pid, duration_ms \\ 100) do
    GenServer.cast(pid, {:simulate_work, duration_ms})
  end

  @impl GenServer
  def init(opts) do
    id = Keyword.get(opts, :id, :test_worker)

    state = %{
      id: id,
      start_time: DateTime.utc_now(),
      task_count: 0
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl GenServer
  def handle_cast({:simulate_work, duration_ms}, state) do
    Process.sleep(duration_ms)
    new_state = Map.update!(state, :task_count, &(&1 + 1))
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_cast(:shutdown, state) do
    {:stop, :shutdown, state}
  end

  @impl GenServer
  def handle_info(:timeout, state) do
    {:stop, :timeout, state}
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end

defmodule Foundation.TestHelpers.MLWorker do
  @moduledoc """
  ML-specific test worker for testing ML agent scenarios.
  """
  use GenServer

  @type state :: %{
          id: atom(),
          model_type: atom(),
          frameworks: [atom()],
          model_loaded: boolean(),
          inference_count: non_neg_integer(),
          start_time: DateTime.t()
        }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, [])
  end

  def load_model(pid) do
    GenServer.call(pid, :load_model)
  end

  def run_inference(pid, input) do
    GenServer.call(pid, {:run_inference, input})
  end

  def get_stats(pid) do
    GenServer.call(pid, :get_stats)
  end

  @impl GenServer
  def init(opts) do
    model_type = Keyword.get(opts, :model_type, :general)
    frameworks = Keyword.get(opts, :frameworks, [:pytorch])

    state = %{
      id: Keyword.get(opts, :id, :ml_worker),
      model_type: model_type,
      frameworks: frameworks,
      model_loaded: false,
      inference_count: 0,
      start_time: DateTime.utc_now()
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:load_model, _from, state) do
    # Simulate model loading time
    Process.sleep(50)
    new_state = Map.put(state, :model_loaded, true)
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call({:run_inference, _input}, _from, %{model_loaded: false} = state) do
    {:reply, {:error, :model_not_loaded}, state}
  end

  @impl GenServer
  def handle_call({:run_inference, input}, _from, state) do
    # Simulate inference time
    Process.sleep(10)

    # Generate fake output based on model type
    output =
      case state.model_type do
        :transformer -> "Generated text for: #{inspect(input)}"
        :cnn -> %{class: :cat, confidence: 0.95}
        :llm -> %{response: "AI response to: #{inspect(input)}", reasoning: "Because..."}
        _ -> %{result: "Processed: #{inspect(input)}"}
      end

    new_state = Map.update!(state, :inference_count, &(&1 + 1))
    {:reply, {:ok, output}, new_state}
  end

  @impl GenServer
  def handle_call(:get_stats, _from, state) do
    stats = %{
      model_type: state.model_type,
      frameworks: state.frameworks,
      model_loaded: state.model_loaded,
      inference_count: state.inference_count,
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.start_time, :second)
    }

    {:reply, stats, state}
  end

  @impl GenServer
  def handle_cast(:shutdown, state) do
    {:stop, :shutdown, state}
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end

defmodule Foundation.TestHelpers.CoordinationAgent do
  @moduledoc """
  Test coordination agent for testing multi-agent scenarios.
  """
  use GenServer

  @type state :: %{
          id: atom(),
          strategy: atom(),
          max_managed: pos_integer(),
          managed_agents: [pid()],
          task_queue: [term()],
          start_time: DateTime.t()
        }

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, [])
  end

  def add_managed_agent(coordinator_pid, agent_pid) do
    GenServer.call(coordinator_pid, {:add_managed_agent, agent_pid})
  end

  def remove_managed_agent(coordinator_pid, agent_pid) do
    GenServer.call(coordinator_pid, {:remove_managed_agent, agent_pid})
  end

  def assign_task(coordinator_pid, task) do
    GenServer.call(coordinator_pid, {:assign_task, task})
  end

  def get_status(coordinator_pid) do
    GenServer.call(coordinator_pid, :get_status)
  end

  @impl GenServer
  def init(opts) do
    strategy = Keyword.get(opts, :strategy, :round_robin)
    max_managed = Keyword.get(opts, :max_managed, 10)

    state = %{
      id: Keyword.get(opts, :id, :coordinator),
      strategy: strategy,
      max_managed: max_managed,
      managed_agents: [],
      task_queue: [],
      start_time: DateTime.utc_now()
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call({:add_managed_agent, agent_pid}, _from, state) do
    if length(state.managed_agents) >= state.max_managed do
      {:reply, {:error, :max_agents_reached}, state}
    else
      new_managed = [agent_pid | state.managed_agents]
      new_state = Map.put(state, :managed_agents, new_managed)
      {:reply, :ok, new_state}
    end
  end

  @impl GenServer
  def handle_call({:remove_managed_agent, agent_pid}, _from, state) do
    new_managed = List.delete(state.managed_agents, agent_pid)
    new_state = Map.put(state, :managed_agents, new_managed)
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call({:assign_task, task}, _from, state) do
    case select_agent(state) do
      nil ->
        # No agents available, queue the task
        new_queue = state.task_queue ++ [task]
        new_state = Map.put(state, :task_queue, new_queue)
        {:reply, {:queued, length(new_queue)}, new_state}

      agent_pid ->
        # Simulate task assignment
        send(agent_pid, {:task_assigned, task})
        {:reply, {:assigned, agent_pid}, state}
    end
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    status = %{
      id: state.id,
      strategy: state.strategy,
      managed_agents_count: length(state.managed_agents),
      max_managed: state.max_managed,
      queued_tasks: length(state.task_queue),
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.start_time, :second)
    }

    {:reply, status, state}
  end

  @impl GenServer
  def handle_cast(:shutdown, state) do
    {:stop, :shutdown, state}
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private helper to select an agent based on strategy
  defp select_agent(%{managed_agents: [], strategy: _}), do: nil

  defp select_agent(%{managed_agents: agents, strategy: :round_robin}) do
    # Simple round-robin: just take the first agent
    # In a real implementation, this would track position
    List.first(agents)
  end

  defp select_agent(%{managed_agents: agents, strategy: :random}) do
    Enum.random(agents)
  end

  defp select_agent(%{managed_agents: agents, strategy: _}) do
    # Default to first agent
    List.first(agents)
  end
end

defmodule Foundation.TestHelpers.FailingAgent do
  @moduledoc """
  Test agent that fails in predictable ways for error testing.
  """
  use GenServer

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, [])
  end

  @impl GenServer
  def init(opts) do
    failure_mode = Keyword.get(opts, :failure_mode, :immediate)
    failure_rate = Keyword.get(opts, :failure_rate, 1.0)
    recovery_time = Keyword.get(opts, :recovery_time, 1000)

    state = %{
      failure_mode: failure_mode,
      failure_rate: failure_rate,
      recovery_time: recovery_time,
      start_time: DateTime.utc_now()
    }

    # Handle immediate failure mode
    case failure_mode do
      :immediate ->
        {:stop, :intentional_failure}

      :delayed ->
        Process.send_after(self(), :delayed_failure, 100)
        {:ok, state}

      _ ->
        {:ok, state}
    end
  end

  @impl GenServer
  def handle_call(_request, _from, state) do
    case should_fail?(state) do
      true -> {:stop, :intentional_failure, {:error, :failure}, state}
      false -> {:reply, :ok, state}
    end
  end

  @impl GenServer
  def handle_cast(_request, state) do
    case should_fail?(state) do
      true -> {:stop, :intentional_failure, state}
      false -> {:noreply, state}
    end
  end

  @impl GenServer
  def handle_info(:delayed_failure, state) do
    {:stop, :delayed_failure, state}
  end

  @impl GenServer
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Determine if the agent should fail based on its configuration
  defp should_fail?(%{failure_mode: :never}), do: false
  defp should_fail?(%{failure_mode: :immediate}), do: true

  defp should_fail?(%{failure_mode: :random, failure_rate: rate}) do
    :rand.uniform() < rate
  end

  defp should_fail?(_), do: false
end
