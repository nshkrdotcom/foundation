defmodule Foundation.TestHelpers.TestModules do
  @moduledoc """
  Test helper modules for Foundation MABEAM tests.

  This module serves as a namespace for test-specific GenServer implementations
  used in MABEAM testing scenarios.
  """
end

defmodule Foundation.TestHelpers.TestWorker do
  @moduledoc """
  A simple test worker for AgentSupervisor tests.
  """
  use GenServer

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, [])
  end

  def init(args) do
    state = %{
      args: args,
      started_at: System.monotonic_time(:millisecond),
      message_count: 0
    }

    {:ok, state}
  end

  def handle_call(:health_status, _from, state) do
    {:reply, {:ok, :healthy}, state}
  end

  def handle_call(:ping, _from, state) do
    {:reply, :pong, state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(_request, _from, state) do
    {:reply, {:error, :unknown_request}, state}
  end

  def handle_cast(_msg, state) do
    new_state = %{state | message_count: state.message_count + 1}
    {:noreply, new_state}
  end

  def handle_info(_info, state) do
    {:noreply, state}
  end
end

defmodule Foundation.TestHelpers.FailingAgent do
  @moduledoc """
  An agent that fails immediately for testing supervision policies.
  """
  use GenServer

  def start_link(args \\ []) do
    failure_mode = Keyword.get(args, :failure_mode, :immediate)

    case failure_mode do
      :immediate -> {:error, :immediate_failure}
      _ -> GenServer.start_link(__MODULE__, args, [])
    end
  end

  def init(_args) do
    {:stop, :init_failure}
  end
end

defmodule Foundation.TestHelpers.MLWorker do
  @moduledoc """
  A test ML worker for testing complex metadata and agent capabilities.
  """
  use GenServer

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, [])
  end

  def init(args) do
    model_type = Keyword.get(args, :model_type, :default)

    state = %{
      args: args,
      model_type: model_type,
      started_at: System.monotonic_time(:millisecond),
      message_count: 0,
      ml_metadata: %{
        training_status: :ready,
        model_loaded: true
      }
    }

    {:ok, state}
  end

  def handle_call(:health_status, _from, state) do
    {:reply, {:ok, :healthy}, state}
  end

  def handle_call(:ping, _from, state) do
    {:reply, :pong, state}
  end

  def handle_call(:get_ml_metadata, _from, state) do
    {:reply, {:ok, state.ml_metadata}, state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(_request, _from, state) do
    {:reply, {:error, :unknown_request}, state}
  end

  def handle_cast(_msg, state) do
    new_state = %{state | message_count: state.message_count + 1}
    {:noreply, new_state}
  end

  def handle_info(_info, state) do
    {:noreply, state}
  end
end

defmodule Foundation.TestHelpers.CoordinationAgent do
  @moduledoc """
  A test coordination agent for testing multi-agent coordination and task distribution.
  """
  use GenServer

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, [])
  end

  def init(args) do
    state = %{
      args: args,
      started_at: System.monotonic_time(:millisecond),
      message_count: 0,
      coordinated_agents: [],
      task_queue: [],
      coordination_metadata: %{
        coordination_strategy: :round_robin,
        active_tasks: 0
      }
    }

    {:ok, state}
  end

  def handle_call(:health_status, _from, state) do
    {:reply, {:ok, :healthy}, state}
  end

  def handle_call(:ping, _from, state) do
    {:reply, :pong, state}
  end

  def handle_call(:get_coordination_metadata, _from, state) do
    {:reply, {:ok, state.coordination_metadata}, state}
  end

  def handle_call(:get_coordinated_agents, _from, state) do
    {:reply, {:ok, state.coordinated_agents}, state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, state}
  end

  def handle_call(_request, _from, state) do
    {:reply, {:error, :unknown_request}, state}
  end

  def handle_cast({:add_agent, agent_id}, state) do
    new_agents = [agent_id | state.coordinated_agents] |> Enum.uniq()
    new_state = %{state | coordinated_agents: new_agents, message_count: state.message_count + 1}
    {:noreply, new_state}
  end

  def handle_cast(_msg, state) do
    new_state = %{state | message_count: state.message_count + 1}
    {:noreply, new_state}
  end

  def handle_info(_info, state) do
    {:noreply, state}
  end
end
