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

# Coordination test agents

defmodule CoordinationTestAgent do
  @moduledoc """
  Test agent for coordination protocols (consensus, voting).
  """
  use GenServer

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(_args) do
    {:ok, %{
      responses: [],
      consensus_preference: :random,
      vote_history: []
    }}
  end

  @impl true
  def handle_call({:mabeam_coordination_request, :consensus, params}, _from, state) do
    response = case params do
      %{question: _question, options: options} ->
        # Simulate decision-making process
        delay = Map.get(params, :delay, 0)
        if delay > 0, do: Process.sleep(delay)
        
        case Map.get(params, :force_unanimous) do
          true -> 
            # For unanimous tests, always vote yes
            {:ok, %{response: :yes, confidence: 1.0, reasoning: "Unanimous agreement"}}
          _ ->
            # Random choice for majority vote tests
            choice = Enum.random(options)
            confidence = :rand.uniform()
            {:ok, %{response: choice, confidence: confidence, reasoning: "Random choice"}}
        end
        
      %{simulate_failure: true} ->
        {:error, :simulated_failure}
        
      _ ->
        {:ok, %{response: :yes, confidence: 0.8, reasoning: "Default agreement"}}
    end
    
    new_state = %{state | 
      responses: [response | state.responses],
      vote_history: [params | state.vote_history]
    }
    
    {:reply, response, new_state}
  end

  def handle_call({:mabeam_coordination_request, protocol, _params}, _from, state) do
    {:reply, {:error, {:unsupported_protocol, protocol}}, state}
  end

  def handle_call(:get_vote_history, _from, state) do
    {:reply, state.vote_history, state}
  end

  def handle_call(:get_response_count, _from, state) do
    {:reply, length(state.responses), state}
  end

  def handle_call(message, _from, state) do
    {:reply, {:error, {:unknown_message, message}}, state}
  end

  @impl true
  def handle_cast(_message, state) do
    {:noreply, state}
  end
end

defmodule NegotiationTestAgent do
  @moduledoc """
  Test agent for negotiation and resource allocation protocols.
  """
  use GenServer

  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl true
  def init(_args) do
    {:ok, %{
      current_offers: %{},
      negotiation_history: [],
      resource_preferences: %{},
      allocation_satisfaction: 0.0
    }}
  end

  @impl true
  def handle_call({:mabeam_coordination_request, :negotiation, params}, _from, state) do
    response = case params do
      %{resource: resource, total_available: total, initial_offers: offers} ->
        agent_id = get_agent_id_from_offers(offers)
        my_offer = Map.get(offers, agent_id, total / 2)
        
        # Simple negotiation strategy: try to get 10% more than initial offer
        desired_amount = min(my_offer * 1.1, total * 0.6)
        
        {:ok, %{
          agent_id: agent_id,
          resource: resource,
          desired_amount: desired_amount,
          flexibility: 0.2,
          priority: :high
        }}
        
      %{resources: resources, agent_requirements: requirements} ->
        agent_id = extract_agent_id(requirements)
        my_requirements = Map.get(requirements, agent_id, %{})
        
        # Calculate satisfaction based on requirements vs available
        satisfaction = calculate_satisfaction(my_requirements, resources)
        
        {:ok, %{
          agent_id: agent_id,
          requirements: my_requirements,
          flexibility: satisfaction,
          alternative_proposals: generate_alternatives(my_requirements)
        }}
        
      _ ->
        {:ok, %{
          agent_id: :unknown,
          status: :ready_to_negotiate,
          preferences: %{fairness: 0.8, efficiency: 0.6}
        }}
    end
    
    new_state = %{state | 
      negotiation_history: [params | state.negotiation_history]
    }
    
    {:reply, response, new_state}
  end

  def handle_call({:mabeam_coordination_request, protocol, _params}, _from, state) do
    {:reply, {:error, {:unsupported_protocol, protocol}}, state}
  end

  def handle_call(:get_negotiation_history, _from, state) do
    {:reply, state.negotiation_history, state}
  end

  def handle_call(:get_current_offers, _from, state) do
    {:reply, state.current_offers, state}
  end

  def handle_call(message, _from, state) do
    {:reply, {:error, {:unknown_message, message}}, state}
  end

  @impl true
  def handle_cast(_message, state) do
    {:noreply, state}
  end

  # Helper functions

  defp get_agent_id_from_offers(offers) when is_map(offers) do
    offers |> Map.keys() |> List.first() || :unknown
  end

  defp extract_agent_id(requirements) when is_map(requirements) do
    requirements |> Map.keys() |> List.first() || :unknown
  end

  defp calculate_satisfaction(requirements, available) do
    if map_size(requirements) == 0 do
      0.5
    else
      # Simple satisfaction calculation
      total_req = requirements |> Map.values() |> Enum.sum()
      total_avail = available |> Map.values() |> Enum.sum()
      min(total_req / total_avail, 1.0)
    end
  end

  defp generate_alternatives(requirements) do
    # Generate some alternative proposals
    base_alternative = requirements |> Enum.map(fn {resource, amount} ->
      {resource, amount * 0.8}  # 20% reduction as alternative
    end) |> Enum.into(%{})
    
    [base_alternative]
  end
end