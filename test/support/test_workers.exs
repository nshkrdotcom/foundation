defmodule Foundation.MABEAM.TestWorker do
  @moduledoc """
  Basic test worker for ProcessRegistry testing.
  """
  
  use GenServer

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(args) do
    state = %{
      id: Keyword.get(args, :id, :test_worker),
      started_at: DateTime.utc_now(),
      messages: []
    }
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:test_message, data}, _from, state) do
    {:reply, {:ok, "received: #{data}"}, state}
  end

  @impl true
  def handle_cast({:add_message, message}, state) do
    updated_state = %{state | messages: [message | state.messages]}
    {:noreply, updated_state}
  end

  @impl true
  def handle_info(:stop, state) do
    {:stop, :normal, state}
  end
end

defmodule Foundation.MABEAM.MLTestWorker do
  @moduledoc """
  ML-specific test worker with NLP and classification capabilities.
  """
  
  use GenServer

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(args) do
    state = %{
      id: Keyword.get(args, :id, :ml_test_worker),
      model_type: Keyword.get(args, :model_type, :bert),
      capabilities: [:nlp, :classification],
      started_at: DateTime.utc_now(),
      processed_requests: 0
    }
    {:ok, state}
  end

  @impl true
  def handle_call(:get_capabilities, _from, state) do
    {:reply, state.capabilities, state}
  end

  @impl true
  def handle_call({:classify, text}, _from, state) do
    # Mock classification
    result = %{
      text: text,
      classification: :positive,
      confidence: 0.85,
      model: state.model_type
    }
    
    updated_state = %{state | processed_requests: state.processed_requests + 1}
    {:reply, {:ok, result}, updated_state}
  end

  @impl true
  def handle_call({:extract_entities, _text}, _from, state) do
    # Mock NLP entity extraction
    entities = [
      %{type: :person, text: "test", start: 0, end: 4}
    ]
    
    updated_state = %{state | processed_requests: state.processed_requests + 1}
    {:reply, {:ok, entities}, updated_state}
  end

  @impl true
  def handle_call(:get_stats, _from, state) do
    stats = %{
      processed_requests: state.processed_requests,
      uptime: DateTime.diff(DateTime.utc_now(), state.started_at, :second)
    }
    {:reply, stats, state}
  end
end

defmodule Foundation.MABEAM.CrashingTestWorker do
  @moduledoc """
  Test worker that crashes after a specified time for crash testing.
  """
  
  use GenServer

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(args) do
    crash_after = Keyword.get(args, :crash_after, 1000)
    
    # Schedule crash
    Process.send_after(self(), :crash, crash_after)
    
    state = %{
      crash_after: crash_after,
      started_at: DateTime.utc_now()
    }
    
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(:crash, state) do
    # Intentionally crash
    raise "Intentional crash for testing"
    {:noreply, state}
  end
end

defmodule Foundation.MABEAM.SlowTestWorker do
  @moduledoc """
  Test worker that responds slowly for timeout testing.
  """
  
  use GenServer

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(args) do
    state = %{
      delay: Keyword.get(args, :delay, 1000),
      started_at: DateTime.utc_now()
    }
    {:ok, state}
  end

  @impl true
  def handle_call(:slow_operation, _from, state) do
    # Simulate slow operation
    Process.sleep(state.delay)
    {:reply, {:ok, "slow result"}, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end
end

# Additional test workers for Communication layer testing

defmodule TestResponder do
  @moduledoc """
  Basic test agent that responds to various message types.
  """
  use GenServer

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(_args) do
    {:ok, %{
      state: %{},
      sequence: [],
      process_counts: %{}
    }}
  end

  @impl true
  def handle_call({:echo, message}, _from, state) do
    {:reply, message, state}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state.state, state}
  end

  def handle_call({:get_process_count, request_id}, _from, state) do
    count = Map.get(state.process_counts, request_id, 0)
    {:reply, count, state}
  end

  def handle_call(:get_sequence, _from, state) do
    {:reply, Enum.reverse(state.sequence), state}
  end

  def handle_call({:dedupe_test, request_id}, _from, state) do
    new_count = Map.get(state.process_counts, request_id, 0) + 1
    new_state = %{state | 
      process_counts: Map.put(state.process_counts, request_id, new_count)
    }
    {:reply, {:processed, new_count}, new_state}
  end

  # Coordination requests
  def handle_call({:mabeam_coordination_request, :consensus, _params}, _from, state) do
    # Simple test implementation - always responds :yes
    response = %{response: :yes, reasoning: "test response"}
    {:reply, {:ok, response}, state}
  end

  def handle_call({:mabeam_coordination_request, _protocol, _params}, _from, state) do
    {:reply, {:error, :unsupported_protocol}, state}
  end

  def handle_call(message, _from, state) do
    {:reply, {:error, {:unknown_message, message}}, state}
  end

  @impl true
  def handle_cast({:update_state, new_state}, state) do
    {:noreply, %{state | state: new_state}}
  end

  def handle_cast({:sequence, number}, state) do
    new_sequence = [number | state.sequence]
    {:noreply, %{state | sequence: new_sequence}}
  end

  def handle_cast(message, state) do
    # Log unknown cast messages but don't crash
    require Logger
    Logger.debug("TestResponder received unknown cast: #{inspect(message)}")
    {:noreply, state}
  end
end

defmodule SlowTestResponder do
  @moduledoc """
  Test agent that introduces delays for timeout testing.
  """
  use GenServer

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(args) do
    delay = Keyword.get(args, :delay, 1000)
    {:ok, %{delay: delay, state: %{}}}
  end

  @impl true
  def handle_call({:slow_echo, message}, _from, state) do
    Process.sleep(state.delay)
    {:reply, message, state}
  end

  def handle_call({:very_slow_operation, duration}, _from, state) do
    Process.sleep(duration)
    {:reply, :completed, state}
  end

  def handle_call({:echo, message}, _from, state) do
    {:reply, message, state}
  end

  def handle_call({:mabeam_coordination_request, _protocol, _params}, _from, state) do
    # Slow coordination response
    Process.sleep(state.delay)
    {:reply, {:ok, %{response: :yes}}, state}
  end

  def handle_call(message, _from, state) do
    {:reply, {:error, {:unknown_message, message}}, state}
  end

  @impl true
  def handle_cast({:update_state, new_state}, state) do
    {:noreply, %{state | state: new_state}}
  end

  def handle_cast(_message, state) do
    {:noreply, state}
  end
end

defmodule FailingTestResponder do
  @moduledoc """
  Test agent that crashes on certain messages.
  """
  use GenServer

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(_args) do
    {:ok, %{}}
  end

  @impl true
  def handle_call(:crash_please, _from, _state) do
    raise "Test crash as requested"
  end

  def handle_call(:guaranteed_failure, _from, state) do
    {:reply, {:error, :guaranteed_failure}, state}
  end

  def handle_call({:echo, message}, _from, state) do
    {:reply, message, state}
  end

  def handle_call(message, _from, state) do
    {:reply, {:error, {:unknown_message, message}}, state}
  end

  @impl true
  def handle_cast(_message, state) do
    {:noreply, state}
  end
end

defmodule EchoTestAgent do
  @moduledoc """
  High-performance echo agent for load testing.
  """
  use GenServer

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(_args) do
    {:ok, %{message_count: 0}}
  end

  @impl true
  def handle_call({:echo, message}, _from, state) do
    new_state = %{state | message_count: state.message_count + 1}
    {:reply, message, new_state}
  end

  def handle_call(:get_message_count, _from, state) do
    {:reply, state.message_count, state}
  end

  def handle_call(message, _from, state) do
    {:reply, {:error, {:unknown_message, message}}, state}
  end

  @impl true
  def handle_cast(_message, state) do
    {:noreply, state}
  end
end