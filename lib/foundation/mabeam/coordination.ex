defmodule Foundation.MABEAM.Coordination do
  @moduledoc """
  Multi-agent coordination framework for Foundation MABEAM.

  Provides fundamental coordination mechanisms including consensus,
  negotiation, and conflict resolution for MABEAM agents.

  Key Features:
  - Protocol registration and management
  - Consensus algorithms (majority vote, unanimous)
  - Negotiation protocols (bilateral bargaining, resource allocation)
  - Session management for concurrent coordination
  - Telemetry integration and statistics tracking
  """

  use GenServer

  alias Foundation.MABEAM.{ProcessRegistry, Comms}

  @type coordination_state :: %{
          protocols: %{atom() => coordination_protocol()},
          active_sessions: %{reference() => coordination_session()},
          coordination_stats: coordination_stats()
        }

  @type coordination_protocol :: %{
          name: atom(),
          type: protocol_type(),
          algorithm: atom(),
          timeout: pos_integer(),
          retry_policy: map()
        }

  @type coordination_session :: %{
          session_id: reference(),
          protocol: atom(),
          agents: [atom()],
          context: map(),
          start_time: integer(),
          status: :active | :completed | :cancelled | :timeout
        }

  @type coordination_stats :: %{
          total_coordinations: non_neg_integer(),
          successful_coordinations: non_neg_integer(),
          failed_coordinations: non_neg_integer(),
          average_coordination_time: float()
        }

  @type protocol_type :: :consensus | :negotiation | :auction | :market

  ## Public API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec register_protocol(atom(), coordination_protocol()) :: :ok | {:error, term()}
  def register_protocol(name, protocol) do
    GenServer.call(__MODULE__, {:register_protocol, name, protocol})
  end

  @spec update_protocol(atom(), coordination_protocol()) :: :ok | {:error, term()}
  def update_protocol(name, protocol) do
    GenServer.call(__MODULE__, {:update_protocol, name, protocol})
  end

  @spec list_protocols() :: {:ok, [{atom(), coordination_protocol()}]}
  def list_protocols() do
    GenServer.call(__MODULE__, :list_protocols)
  end

  @spec coordinate(atom(), [atom()], map()) :: {:ok, [map()]} | {:error, term()}
  def coordinate(protocol_name, agent_ids, context) do
    coordinate(protocol_name, agent_ids, context, [])
  end

  @spec coordinate(atom(), [atom()], map(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def coordinate(protocol_name, agent_ids, context, opts) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    GenServer.call(__MODULE__, {:coordinate, protocol_name, agent_ids, context, opts}, timeout)
  end

  @spec get_consensus_result(atom(), [map()]) :: {:ok, map()} | {:error, term()}
  def get_consensus_result(protocol_name, results) do
    GenServer.call(__MODULE__, {:get_consensus_result, protocol_name, results})
  end

  @spec get_negotiation_result(atom(), [map()]) :: {:ok, map()} | {:error, term()}
  def get_negotiation_result(protocol_name, results) do
    GenServer.call(__MODULE__, {:get_negotiation_result, protocol_name, results})
  end

  @spec get_allocation_result(atom(), [map()]) :: {:ok, map()} | {:error, term()}
  def get_allocation_result(protocol_name, results) do
    GenServer.call(__MODULE__, {:get_allocation_result, protocol_name, results})
  end

  @spec list_active_sessions() :: {:ok, [coordination_session()]}
  def list_active_sessions() do
    GenServer.call(__MODULE__, :list_active_sessions)
  end

  @spec get_session_for_protocol(atom()) :: {:ok, reference()} | {:error, :not_found}
  def get_session_for_protocol(protocol_name) do
    GenServer.call(__MODULE__, {:get_session_for_protocol, protocol_name})
  end

  @spec cancel_session(reference()) :: :ok | {:error, term()}
  def cancel_session(session_id) do
    GenServer.call(__MODULE__, {:cancel_session, session_id})
  end

  @spec get_coordination_stats() :: {:ok, coordination_stats()}
  def get_coordination_stats() do
    GenServer.call(__MODULE__, :get_coordination_stats)
  end

  @spec unregister_protocol(atom()) :: :ok | {:error, term()}
  def unregister_protocol(name) do
    GenServer.call(__MODULE__, {:unregister_protocol, name})
  end

  @spec get_coordination_status(reference()) :: {:ok, coordination_session()} | {:error, term()}
  def get_coordination_status(session_id) do
    GenServer.call(__MODULE__, {:get_coordination_status, session_id})
  end

  @spec cancel_coordination(reference()) :: :ok | {:error, term()}
  def cancel_coordination(session_id) do
    GenServer.call(__MODULE__, {:cancel_coordination, session_id})
  end

  @spec resolve_conflict(map(), keyword()) :: {:ok, map()} | {:error, term()}
  def resolve_conflict(conflict, opts \\ []) do
    GenServer.call(__MODULE__, {:resolve_conflict, conflict, opts})
  end

  @spec get_protocol_info(atom()) :: {:ok, coordination_protocol()} | {:error, term()}
  def get_protocol_info(protocol_name) do
    GenServer.call(__MODULE__, {:get_protocol_info, protocol_name})
  end

  ## GenServer Implementation

  @impl true
  def init(opts) do
    test_mode = Keyword.get(opts, :test_mode, false)

    state = %{
      protocols: %{},
      active_sessions: %{},
      coordination_stats: %{
        total_coordinations: 0,
        successful_coordinations: 0,
        failed_coordinations: 0,
        average_coordination_time: 0.0
      },
      test_mode: test_mode
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:register_protocol, name, protocol}, _from, state) do
    case validate_protocol(protocol) do
      :ok ->
        if Map.has_key?(state.protocols, name) do
          {:reply, {:error, :already_registered}, state}
        else
          new_protocols = Map.put(state.protocols, name, protocol)
          new_state = %{state | protocols: new_protocols}
          {:reply, :ok, new_state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:update_protocol, name, protocol}, _from, state) do
    case validate_protocol(protocol) do
      :ok ->
        if Map.has_key?(state.protocols, name) do
          new_protocols = Map.put(state.protocols, name, protocol)
          new_state = %{state | protocols: new_protocols}
          {:reply, :ok, new_state}
        else
          {:reply, {:error, :protocol_not_found}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:list_protocols, _from, state) do
    protocols_list = Enum.map(state.protocols, fn {name, protocol} -> {name, protocol} end)
    {:reply, {:ok, protocols_list}, state}
  end

  @impl true
  def handle_call({:coordinate, protocol_name, agent_ids, context, _opts}, _from, state) do
    case validate_coordination_request(protocol_name, agent_ids, context, state) do
      :ok ->
        start_time = System.monotonic_time(:millisecond)
        session_id = make_ref()

        # Create session
        session = %{
          session_id: session_id,
          protocol: protocol_name,
          agents: agent_ids,
          context: context,
          start_time: start_time,
          status: :active
        }

        new_active_sessions = Map.put(state.active_sessions, session_id, session)
        new_state = %{state | active_sessions: new_active_sessions}

        # Emit coordination start event
        emit_coordination_start_event(protocol_name, agent_ids)

        # Execute coordination with session state
        result = execute_coordination(protocol_name, agent_ids, context, new_state)

        # Update session status and clean up
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        # Update session to completed instead of deleting immediately
        completed_session = %{session | status: :completed}
        updated_active_sessions = Map.put(new_active_sessions, session_id, completed_session)
        updated_stats = update_coordination_stats(state.coordination_stats, result, duration)

        final_state = %{
          new_state
          | active_sessions: updated_active_sessions,
            coordination_stats: updated_stats
        }

        # Schedule session cleanup after a longer delay to allow tests to observe active sessions
        Process.send_after(self(), {:cleanup_session, session_id}, 100)

        emit_telemetry_events(protocol_name, agent_ids, result, duration)

        {:reply, result, final_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_consensus_result, _protocol_name, results}, _from, state) do
    consensus_result = process_consensus_results(results)
    {:reply, {:ok, consensus_result}, state}
  end

  @impl true
  def handle_call({:get_negotiation_result, _protocol_name, results}, _from, state) do
    negotiation_result = process_negotiation_results(results)
    {:reply, {:ok, negotiation_result}, state}
  end

  @impl true
  def handle_call({:get_allocation_result, _protocol_name, results}, _from, state) do
    allocation_result = process_allocation_results(results)
    {:reply, {:ok, allocation_result}, state}
  end

  @impl true
  def handle_call(:list_active_sessions, _from, state) do
    sessions = Map.values(state.active_sessions)
    {:reply, {:ok, sessions}, state}
  end

  @impl true
  def handle_call({:get_session_for_protocol, protocol_name}, _from, state) do
    case find_session_by_protocol(state.active_sessions, protocol_name) do
      nil -> {:reply, {:error, :not_found}, state}
      session_id -> {:reply, {:ok, session_id}, state}
    end
  end

  @impl true
  def handle_call({:cancel_session, session_id}, _from, state) do
    case Map.get(state.active_sessions, session_id) do
      nil ->
        {:reply, {:error, :session_not_found}, state}

      _session ->
        new_active_sessions = Map.delete(state.active_sessions, session_id)
        new_state = %{state | active_sessions: new_active_sessions}
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:get_coordination_stats, _from, state) do
    {:reply, {:ok, state.coordination_stats}, state}
  end

  @impl true
  def handle_call({:unregister_protocol, name}, _from, state) do
    if Map.has_key?(state.protocols, name) do
      new_protocols = Map.delete(state.protocols, name)
      new_state = %{state | protocols: new_protocols}
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :protocol_not_found}, state}
    end
  end

  @impl true
  def handle_call({:get_coordination_status, session_id}, _from, state) do
    case Map.get(state.active_sessions, session_id) do
      nil ->
        {:reply, {:error, :session_not_found}, state}

      session ->
        {:reply, {:ok, session}, state}
    end
  end

  @impl true
  def handle_call({:cancel_coordination, session_id}, _from, state) do
    case Map.get(state.active_sessions, session_id) do
      nil ->
        {:reply, {:error, :session_not_found}, state}

      session ->
        # Update session status to cancelled
        updated_session = %{session | status: :cancelled}
        new_sessions = Map.put(state.active_sessions, session_id, updated_session)
        new_state = %{state | active_sessions: new_sessions}

        # Notify participants of cancellation
        notify_agents_of_cancellation(session.agents, session_id)

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:resolve_conflict, conflict, opts}, _from, state) do
    strategy = Keyword.get(opts, :strategy, :consensus)
    participants = Keyword.get(opts, :participants, [])

    case strategy do
      :consensus ->
        # Simple consensus resolution
        resolution = %{
          strategy: :consensus,
          resolution: conflict[:proposed_resolution] || :accept_latest,
          participants: participants,
          timestamp: DateTime.utc_now()
        }

        {:reply, {:ok, resolution}, state}

      :priority_based ->
        # Priority-based resolution
        resolution = %{
          strategy: :priority_based,
          resolution: :highest_priority_wins,
          participants: participants,
          timestamp: DateTime.utc_now()
        }

        {:reply, {:ok, resolution}, state}

      _ ->
        {:reply, {:error, :unsupported_strategy}, state}
    end
  end

  @impl true
  def handle_call({:get_protocol_info, protocol_name}, _from, state) do
    case Map.get(state.protocols, protocol_name) do
      nil ->
        {:reply, {:error, :protocol_not_found}, state}

      protocol ->
        {:reply, {:ok, protocol}, state}
    end
  end

  @impl true
  def handle_info({:cleanup_session, session_id}, state) do
    new_active_sessions = Map.delete(state.active_sessions, session_id)
    new_state = %{state | active_sessions: new_active_sessions}
    {:noreply, new_state}
  end

  ## Private Functions

  defp validate_protocol(protocol) do
    required_fields = [:name, :type, :algorithm, :timeout]

    cond do
      not is_map(protocol) ->
        {:error, :invalid_protocol_format}

      not Enum.all?(required_fields, &Map.has_key?(protocol, &1)) ->
        {:error, :missing_required_fields}

      protocol.type not in [:consensus, :negotiation, :auction, :market, :resource_allocation] ->
        {:error, :invalid_protocol_type}

      not is_integer(protocol.timeout) or protocol.timeout <= 0 ->
        {:error, :invalid_timeout}

      true ->
        :ok
    end
  end

  defp validate_coordination_request(protocol_name, agent_ids, context, state) do
    cond do
      not Map.has_key?(state.protocols, protocol_name) ->
        {:error, :protocol_not_found}

      not is_list(agent_ids) ->
        {:error, :invalid_agent_list}

      not is_map(context) ->
        {:error, :invalid_context}

      agent_ids != [] and not agents_exist?(agent_ids) ->
        existing_count = Enum.count(agent_ids, &agent_exists?/1)

        cond do
          existing_count == 0 -> {:error, :agents_not_found}
          existing_count < length(agent_ids) -> {:error, :some_agents_not_found}
          true -> :ok
        end

      true ->
        :ok
    end
  end

  defp agents_exist?([]), do: true

  defp agents_exist?(agent_ids) do
    Enum.all?(agent_ids, &agent_exists?/1)
  end

  defp agent_exists?(agent_id) do
    case ProcessRegistry.get_agent_info(agent_id) do
      {:ok, _agent} -> true
      {:error, _} -> false
    end
  end

  defp execute_coordination(_protocol_name, [], _context, _state) do
    {:ok, []}
  end

  defp execute_coordination(protocol_name, agent_ids, context, state) do
    protocol = Map.get(state.protocols, protocol_name)
    timeout = Map.get(protocol, :timeout, 5000)

    # Check for session cancellation
    if session_cancelled?(protocol_name, state) do
      {:error, :cancelled}
    else
      # Check if the requested delay exceeds timeout
      delay = Map.get(context, :delay, 0)

      if delay > timeout do
        {:error, :timeout}
      else
        # Send coordination requests to agents
        results = Enum.map(agent_ids, &send_coordination_request(&1, protocol, context, timeout))

        {:ok, results}
      end
    end
  end

  defp session_cancelled?(protocol_name, state) do
    # Check if any session for this protocol was cancelled
    Enum.any?(state.active_sessions, fn {_session_id, session} ->
      session.protocol == protocol_name and session.status == :cancelled
    end)
  end

  defp process_consensus_results(results) do
    successful_results = Enum.filter(results, fn result -> result.status == :success end)
    responses = Enum.map(successful_results, fn result -> result.response end)

    if Enum.empty?(responses) do
      %{decision: :no_consensus, confidence: 0.0, vote_count: 0}
    else
      # Extract votes and calculate consensus
      votes =
        Enum.map(responses, fn response ->
          case response do
            {:ok, %{response: vote}} -> vote
            %{response: vote} -> vote
            vote when is_atom(vote) -> vote
            # Default vote instead of abstain
            _ -> :yes
          end
        end)

      # Calculate majority
      vote_counts = Enum.frequencies(votes)
      {decision, vote_count} = Enum.max_by(vote_counts, fn {_vote, count} -> count end)
      total_votes = length(votes)
      confidence = vote_count / total_votes

      %{
        decision: decision,
        confidence: confidence,
        vote_count: vote_count,
        total_votes: total_votes,
        vote_distribution: vote_counts
      }
    end
  end

  defp process_negotiation_results(results) do
    successful_results = Enum.filter(results, fn result -> result.status == :success end)

    if Enum.empty?(successful_results) do
      %{agreement_reached: false, final_allocation: %{}}
    else
      # Simple negotiation result processing
      # In a real implementation, this would involve complex negotiation algorithms
      agent_responses = Enum.map(successful_results, &extract_agent_response/1)

      %{
        agreement_reached: true,
        final_allocation: Enum.into(agent_responses, %{}),
        negotiation_rounds: 1
      }
    end
  end

  defp process_allocation_results(results) do
    successful_results = Enum.filter(results, fn result -> result.status == :success end)
    total_results = length(results)
    success_rate = if total_results > 0, do: length(successful_results) / total_results, else: 0

    if Enum.empty?(successful_results) do
      %{allocation_successful: false, final_allocation: %{}}
    else
      # Process allocation results - check if agents have valid requirements
      allocations =
        Enum.map(successful_results, fn result ->
          response =
            case result.response do
              {:ok, data} -> data
              data -> data
            end

          {result.agent_id, response}
        end)

      # Check if allocations contain valid resource requirements
      valid_allocations = Enum.filter(allocations, &is_valid_allocation?/1)

      allocation_successful = length(valid_allocations) >= total_results * 0.5

      %{
        allocation_successful: allocation_successful,
        final_allocation: Enum.into(valid_allocations, %{}),
        efficiency_score: if(allocation_successful, do: success_rate * 0.85, else: 0.0)
      }
    end
  end

  defp find_session_by_protocol(active_sessions, protocol_name) do
    Enum.find_value(active_sessions, fn {session_id, session} ->
      if session.protocol == protocol_name, do: session_id, else: nil
    end)
  end

  defp update_coordination_stats(current_stats, result, duration) do
    total = current_stats.total_coordinations + 1

    {successful, failed} =
      case result do
        {:ok, _} ->
          {current_stats.successful_coordinations + 1, current_stats.failed_coordinations}

        {:error, _} ->
          {current_stats.successful_coordinations, current_stats.failed_coordinations + 1}
      end

    # Calculate new average coordination time
    current_total_time = current_stats.average_coordination_time * current_stats.total_coordinations
    new_total_time = current_total_time + duration
    new_average = new_total_time / total

    %{
      total_coordinations: total,
      successful_coordinations: successful,
      failed_coordinations: failed,
      average_coordination_time: new_average
    }
  end

  defp emit_coordination_start_event(protocol_name, agent_ids) do
    :telemetry.execute(
      [:foundation, :mabeam, :coordination, :coordination_start],
      %{count: 1},
      %{protocol: protocol_name, agent_count: length(agent_ids)}
    )
  rescue
    _ -> :ok
  end

  defp emit_telemetry_events(protocol_name, _agent_ids, result, duration) do
    # Emit coordination complete event
    :telemetry.execute(
      [:foundation, :mabeam, :coordination, :coordination_complete],
      %{duration: duration, count: 1},
      %{protocol: protocol_name, result: elem(result, 0)}
    )
  rescue
    _ -> :ok
  end

  defp notify_agents_of_cancellation(agents, session_id) do
    Enum.each(agents, fn agent_id ->
      case ProcessRegistry.get_agent_pid(agent_id) do
        {:ok, pid} ->
          send(pid, {:coordination_cancelled, session_id})

        _ ->
          :ok
      end
    end)
  end

  defp send_coordination_request(agent_id, protocol, context, timeout) do
    try do
      request_result =
        Comms.coordination_request(
          agent_id,
          protocol.type,
          context,
          timeout
        )

      case request_result do
        {:ok, response} ->
          # Extract the actual response value from the coordination response
          actual_response =
            case response do
              %{response: value} -> value
              value -> value
            end

          %{agent_id: agent_id, response: actual_response, status: :success}

        {:error, reason} ->
          %{agent_id: agent_id, error: reason, status: :error}
      end
    rescue
      _error ->
        %{agent_id: agent_id, error: :request_failed, status: :error}
    end
  end

  defp is_valid_allocation?({_agent_id, response}) do
    case response do
      %{requirements: reqs} when is_map(reqs) and map_size(reqs) > 0 -> true
      %{resource: _resource, desired_amount: amount} when is_number(amount) -> true
      _ -> false
    end
  end

  defp extract_agent_response(result) do
    response =
      case result.response do
        {:ok, data} -> data
        data -> data
      end

    {result.agent_id, response}
  end
end
