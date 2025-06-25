defmodule TestAgent do
  @moduledoc """
  Test agent implementation for MABEAM testing.

  This is a simple GenServer-based agent that can be used to test
  the AgentRegistry functionality and agent lifecycle management.
  """

  use GenServer
  require Logger

  @type agent_config :: %{
          name: String.t(),
          capabilities: [atom()],
          resources: map(),
          test_mode: boolean()
        }

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Start the test agent with the given configuration.
  """
  @spec start_link(agent_config()) :: GenServer.on_start()
  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  @doc """
  Get the current state of the agent.
  """
  @spec get_state(pid()) :: {:ok, map()}
  def get_state(pid) do
    GenServer.call(pid, :get_state)
  end

  @doc """
  Send a message to the agent for testing.
  """
  @spec send_message(pid(), term()) :: :ok
  def send_message(pid, message) do
    GenServer.cast(pid, {:test_message, message})
  end

  @doc """
  Test agent health check.
  """
  @spec health_check(pid()) :: :ok | {:error, term()}
  def health_check(pid) do
    GenServer.call(pid, :health_check)
  end

  # ============================================================================
  # GenServer Callbacks
  # ============================================================================

  @impl true
  def init(config) do
    Logger.debug("Starting TestAgent with config: #{inspect(config)}")

    state = %{
      config: config,
      started_at: DateTime.utc_now(),
      messages_received: 0,
      last_health_check: nil,
      status: :active
    }

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    updated_state = %{state | last_health_check: DateTime.utc_now()}
    {:reply, :ok, updated_state}
  end

  @impl true
  def handle_call(request, _from, state) do
    Logger.warning("Unknown TestAgent call: #{inspect(request)}")
    {:reply, {:error, :unknown_request}, state}
  end

  @impl true
  def handle_cast({:test_message, message}, state) do
    Logger.debug("TestAgent received message: #{inspect(message)}")
    updated_state = %{state | messages_received: state.messages_received + 1}
    {:noreply, updated_state}
  end

  @impl true
  def handle_cast(msg, state) do
    Logger.warning("Unknown TestAgent cast: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Unknown TestAgent info: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.debug("TestAgent terminating: #{inspect(reason)}")
    :ok
  end

  # ============================================================================
  # Child Spec
  # ============================================================================

  @doc false
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :temporary,
      shutdown: 5000
    }
  end
end

defmodule CrashyTestAgent do
  @moduledoc """
  Test agent that crashes for testing failure scenarios.
  """

  use GenServer

  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  @impl true
  def init(_config) do
    # Crash immediately for testing
    {:stop, :intentional_crash}
  end
end

defmodule SlowTestAgent do
  @moduledoc """
  Test agent that responds slowly for timeout testing.
  """

  use GenServer

  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  @impl true
  def init(config) do
    delay = Map.get(config, :response_delay, 1000)
    Process.sleep(delay)
    {:ok, %{config: config, started_at: DateTime.utc_now()}}
  end

  @impl true
  def handle_call(:health_check, _from, state) do
    # Simulate slow health check
    delay = Map.get(state.config, :response_delay, 1000)
    Process.sleep(delay)
    {:reply, :ok, state}
  end

  @impl true
  def handle_call(_request, _from, state) do
    {:reply, {:error, :unknown_request}, state}
  end

  @impl true
  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
