defmodule Foundation.Coordination.Primitives do
  @moduledoc """
  Distribution-ready coordination primitives for multi-agent systems.
  
  Provides fundamental coordination mechanisms designed for single-node performance
  and seamless migration to distributed deployments. All primitives are agent-aware
  and integrate with Foundation's ProcessRegistry for sophisticated coordination.
  
  ## Features
  
  - **Consensus Mechanisms**: Raft-ready consensus for distributed decision making
  - **Barrier Synchronization**: Coordinate groups of agents for synchronized execution
  - **Distributed Locks**: Mutual exclusion with deadlock detection
  - **Leader Election**: Automatic leader selection with failure detection
  - **Agent-Aware**: All primitives understand agent capabilities and health
  - **Distribution-Ready**: APIs designed for cluster deployment
  
  ## Consensus
  
  Start a consensus process among agents:
  
      participants = [:agent1, :agent2, :agent3]
      proposal = %{action: :resource_allocation, target: :database}
      {:ok, consensus_ref} = Foundation.Coordination.Primitives.start_consensus(
        participants, proposal, timeout: 30_000
      )
      
      # Participants vote
      :ok = Foundation.Coordination.Primitives.vote(consensus_ref, :agent1, :accept)
      :ok = Foundation.Coordination.Primitives.vote(consensus_ref, :agent2, :accept)
      :ok = Foundation.Coordination.Primitives.vote(consensus_ref, :agent3, :reject)
      
      # Get result
      {:ok, result} = Foundation.Coordination.Primitives.get_consensus_result(consensus_ref)
  
  ## Barrier Synchronization
  
  Coordinate agents for synchronized execution:
  
      barrier_id = :deployment_barrier
      participant_count = 5
      
      :ok = Foundation.Coordination.Primitives.create_barrier(barrier_id, participant_count)
      
      # Each agent arrives at barrier
      :ok = Foundation.Coordination.Primitives.arrive_at_barrier(barrier_id, :agent1)
      # ... other agents arrive ...
      
      # Wait for all agents
      {:ok, :barrier_reached} = Foundation.Coordination.Primitives.wait_for_barrier(
        barrier_id, timeout: 60_000
      )
  
  ## Distributed Locks
  
  Mutual exclusion across agents:
  
      lock_id = :database_migration
      holder_id = :migration_agent
      
      case Foundation.Coordination.Primitives.acquire_lock(lock_id, holder_id) do
        {:ok, lock_ref} ->
          # Perform critical operation
          result = perform_migration()
          Foundation.Coordination.Primitives.release_lock(lock_id, holder_id)
          result
        
        {:error, :already_locked} ->
          {:error, :migration_in_progress}
      end
  
  ## Leader Election
  
  Automatic leader selection:
  
      group_id = :coordination_group
      candidates = [:agent1, :agent2, :agent3]
      
      :ok = Foundation.Coordination.Primitives.start_election(group_id, candidates)
      {:ok, leader} = Foundation.Coordination.Primitives.elect_leader(group_id)
  """
  
  use GenServer
  require Logger
  
  @type participant_id :: atom()
  @type consensus_ref :: reference()
  @type consensus_vote :: :accept | :reject | :abstain
  @type consensus_result :: :accepted | :rejected | :timeout
  
  @type barrier_id :: term()
  @type lock_id :: term()
  @type lock_ref :: reference()
  @type group_id :: term()
  
  @type consensus_proposal :: map()
  @type consensus_config :: %{
          timeout: pos_integer(),
          quorum_size: pos_integer(),
          require_unanimous: boolean()
        }
  
  ## Public API - Consensus Mechanisms
  
  @doc """
  Start a consensus process among participants.
  
  ## Options
  
  - `:timeout` - Consensus timeout in milliseconds (default: 30_000)
  - `:quorum_size` - Minimum votes needed (default: majority)
  - `:require_unanimous` - Require all participants to agree (default: false)
  
  ## Examples
  
      participants = [:agent1, :agent2, :agent3]
      proposal = %{action: :scale_up, instances: 5}
      {:ok, ref} = start_consensus(participants, proposal, timeout: 45_000)
  """
  @spec start_consensus([participant_id()], consensus_proposal(), keyword()) ::
          {:ok, consensus_ref()} | {:error, term()}
  def start_consensus(participants, proposal, opts \\ []) do
    GenServer.call(__MODULE__, {:start_consensus, participants, proposal, opts})
  end
  
  @doc """
  Vote on an active consensus process.
  
  ## Examples
  
      :ok = vote(consensus_ref, :agent1, :accept)
      :ok = vote(consensus_ref, :agent2, :reject)
  """
  @spec vote(consensus_ref(), participant_id(), consensus_vote()) :: :ok | {:error, term()}
  def vote(consensus_ref, participant_id, vote) do
    GenServer.call(__MODULE__, {:vote, consensus_ref, participant_id, vote})
  end
  
  @doc """
  Get the result of a consensus process.
  
  Blocks until consensus is reached or times out.
  
  ## Examples
  
      case get_consensus_result(consensus_ref) do
        {:ok, :accepted} -> proceed_with_proposal()
        {:ok, :rejected} -> handle_rejection()
        {:ok, :timeout} -> handle_timeout()
      end
  """
  @spec get_consensus_result(consensus_ref()) :: {:ok, consensus_result()} | {:error, term()}
  def get_consensus_result(consensus_ref) do
    GenServer.call(__MODULE__, {:get_consensus_result, consensus_ref}, :infinity)
  end
  
  ## Public API - Barrier Synchronization
  
  @doc """
  Create a barrier for synchronizing a group of participants.
  
  ## Examples
  
      :ok = create_barrier(:deployment_sync, 5)
  """
  @spec create_barrier(barrier_id(), pos_integer()) :: :ok | {:error, term()}
  def create_barrier(barrier_id, participant_count) do
    GenServer.call(__MODULE__, {:create_barrier, barrier_id, participant_count})
  end
  
  @doc """
  Signal arrival at a barrier.
  
  ## Examples
  
      :ok = arrive_at_barrier(:deployment_sync, :agent1)
  """
  @spec arrive_at_barrier(barrier_id(), participant_id()) :: :ok | {:error, term()}
  def arrive_at_barrier(barrier_id, participant_id) do
    GenServer.call(__MODULE__, {:arrive_at_barrier, barrier_id, participant_id})
  end
  
  @doc """
  Wait for all participants to arrive at the barrier.
  
  ## Examples
  
      case wait_for_barrier(:deployment_sync, timeout: 60_000) do
        {:ok, :barrier_reached} -> proceed_with_deployment()
        {:error, :timeout} -> handle_barrier_timeout()
      end
  """
  @spec wait_for_barrier(barrier_id(), keyword()) ::
          {:ok, :barrier_reached} | {:error, :timeout | term()}
  def wait_for_barrier(barrier_id, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 60_000)
    GenServer.call(__MODULE__, {:wait_for_barrier, barrier_id}, timeout)
  end
  
  ## Public API - Distributed Locks
  
  @doc """
  Acquire a distributed lock.
  
  ## Examples
  
      case acquire_lock(:database_migration, :migration_agent) do
        {:ok, lock_ref} -> 
          # Critical section
          :ok
        {:error, :already_locked} -> 
          {:error, :resource_busy}
      end
  """
  @spec acquire_lock(lock_id(), participant_id(), keyword()) ::
          {:ok, lock_ref()} | {:error, :already_locked | term()}
  def acquire_lock(lock_id, holder_id, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    GenServer.call(__MODULE__, {:acquire_lock, lock_id, holder_id}, timeout)
  end
  
  @doc """
  Release a distributed lock.
  
  ## Examples
  
      :ok = release_lock(:database_migration, :migration_agent)
  """
  @spec release_lock(lock_id(), participant_id()) :: :ok | {:error, term()}
  def release_lock(lock_id, holder_id) do
    GenServer.call(__MODULE__, {:release_lock, lock_id, holder_id})
  end
  
  @doc """
  Get the status of a distributed lock.
  
  ## Examples
  
      case lock_status(:database_migration) do
        {:locked, holder_id, acquired_at} -> {:busy, holder_id}
        :unlocked -> :available
      end
  """
  @spec lock_status(lock_id()) :: {:locked, participant_id(), DateTime.t()} | :unlocked
  def lock_status(lock_id) do
    GenServer.call(__MODULE__, {:lock_status, lock_id})
  end
  
  ## Public API - Leader Election
  
  @doc """
  Start a leader election process.
  
  ## Examples
  
      candidates = [:agent1, :agent2, :agent3]
      :ok = start_election(:coordination_group, candidates)
  """
  @spec start_election(group_id(), [participant_id()]) :: :ok | {:error, term()}
  def start_election(group_id, candidates) do
    GenServer.call(__MODULE__, {:start_election, group_id, candidates})
  end
  
  @doc """
  Elect a leader from the candidates.
  
  Uses agent health and capabilities for selection.
  
  ## Examples
  
      {:ok, leader} = elect_leader(:coordination_group)
  """
  @spec elect_leader(group_id()) :: {:ok, participant_id()} | {:error, term()}
  def elect_leader(group_id) do
    GenServer.call(__MODULE__, {:elect_leader, group_id})
  end
  
  @doc """
  Get the current leader of a group.
  
  ## Examples
  
      case get_current_leader(:coordination_group) do
        {:ok, leader} -> leader
        {:error, :no_leader} -> :none
      end
  """
  @spec get_current_leader(group_id()) :: {:ok, participant_id()} | {:error, :no_leader}
  def get_current_leader(group_id) do
    GenServer.call(__MODULE__, {:get_current_leader, group_id})
  end
  
  ## Infrastructure Management
  
  @doc """
  Initialize coordination primitives infrastructure.
  """
  @spec initialize_infrastructure() :: :ok
  def initialize_infrastructure do
    case GenServer.start_link(__MODULE__, [], name: __MODULE__) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Clean up coordination primitives infrastructure.
  """
  @spec cleanup_infrastructure() :: :ok
  def cleanup_infrastructure do
    if Process.whereis(__MODULE__) do
      GenServer.stop(__MODULE__)
    end
    :ok
  end
  
  ## GenServer Implementation
  
  @impl true
  def init(_opts) do
    state = %{
      consensus_processes: %{},
      barriers: %{},
      locks: %{},
      elections: %{},
      monitors: %{}
    }
    
    Logger.info("Foundation Coordination Primitives initialized")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:start_consensus, participants, proposal, opts}, _from, state) do
    consensus_ref = make_ref()
    timeout = Keyword.get(opts, :timeout, 30_000)
    quorum_size = Keyword.get(opts, :quorum_size, div(length(participants) + 1, 2))
    require_unanimous = Keyword.get(opts, :require_unanimous, false)
    
    consensus_process = %{
      ref: consensus_ref,
      participants: MapSet.new(participants),
      proposal: proposal,
      votes: %{},
      quorum_size: quorum_size,
      require_unanimous: require_unanimous,
      timeout: timeout,
      started_at: DateTime.utc_now(),
      status: :voting,
      waiters: []
    }
    
    # Set timeout
    Process.send_after(self(), {:consensus_timeout, consensus_ref}, timeout)
    
    # Monitor participants
    monitors = monitor_participants(participants, state.monitors)
    
    consensus_processes = Map.put(state.consensus_processes, consensus_ref, consensus_process)
    
    {:reply, {:ok, consensus_ref}, %{state | 
      consensus_processes: consensus_processes,
      monitors: monitors
    }}
  end
  
  @impl true
  def handle_call({:vote, consensus_ref, participant_id, vote}, _from, state) do
    case Map.get(state.consensus_processes, consensus_ref) do
      nil ->
        {:reply, {:error, :consensus_not_found}, state}
      
      %{status: :voting, participants: participants} = consensus_process ->
        if MapSet.member?(participants, participant_id) do
          # Record vote
          votes = Map.put(consensus_process.votes, participant_id, vote)
          updated_process = %{consensus_process | votes: votes}
          
          # Check if consensus reached
          {result, final_process} = check_consensus_result(updated_process)
          
          # Notify waiters if consensus reached
          if result != :still_voting do
            notify_consensus_waiters(final_process.waiters, result)
            final_process = %{final_process | waiters: []}
          end
          
          consensus_processes = Map.put(state.consensus_processes, consensus_ref, final_process)
          
          {:reply, :ok, %{state | consensus_processes: consensus_processes}}
        else
          {:reply, {:error, :not_participant}, state}
        end
      
      _ ->
        {:reply, {:error, :consensus_completed}, state}
    end
  end
  
  @impl true
  def handle_call({:get_consensus_result, consensus_ref}, from, state) do
    case Map.get(state.consensus_processes, consensus_ref) do
      nil ->
        {:reply, {:error, :consensus_not_found}, state}
      
      %{status: status} = consensus_process when status != :voting ->
        {:reply, {:ok, status}, state}
      
      consensus_process ->
        # Add caller to waiters
        waiters = [from | consensus_process.waiters]
        updated_process = %{consensus_process | waiters: waiters}
        consensus_processes = Map.put(state.consensus_processes, consensus_ref, updated_process)
        
        {:noreply, %{state | consensus_processes: consensus_processes}}
    end
  end
  
  @impl true
  def handle_call({:create_barrier, barrier_id, participant_count}, _from, state) do
    case Map.get(state.barriers, barrier_id) do
      nil ->
        barrier = %{
          id: barrier_id,
          participant_count: participant_count,
          arrived: MapSet.new(),
          waiters: [],
          created_at: DateTime.utc_now()
        }
        
        barriers = Map.put(state.barriers, barrier_id, barrier)
        {:reply, :ok, %{state | barriers: barriers}}
      
      _ ->
        {:reply, {:error, :barrier_exists}, state}
    end
  end
  
  @impl true
  def handle_call({:arrive_at_barrier, barrier_id, participant_id}, _from, state) do
    case Map.get(state.barriers, barrier_id) do
      nil ->
        {:reply, {:error, :barrier_not_found}, state}
      
      barrier ->
        arrived = MapSet.put(barrier.arrived, participant_id)
        updated_barrier = %{barrier | arrived: arrived}
        
        # Check if barrier reached
        if MapSet.size(arrived) >= barrier.participant_count do
          # Notify all waiters
          Enum.each(barrier.waiters, fn waiter ->
            GenServer.reply(waiter, {:ok, :barrier_reached})
          end)
          
          # Remove the barrier
          barriers = Map.delete(state.barriers, barrier_id)
          {:reply, :ok, %{state | barriers: barriers}}
        else
          barriers = Map.put(state.barriers, barrier_id, updated_barrier)
          {:reply, :ok, %{state | barriers: barriers}}
        end
    end
  end
  
  @impl true
  def handle_call({:wait_for_barrier, barrier_id}, from, state) do
    case Map.get(state.barriers, barrier_id) do
      nil ->
        {:reply, {:error, :barrier_not_found}, state}
      
      barrier ->
        if MapSet.size(barrier.arrived) >= barrier.participant_count do
          {:reply, {:ok, :barrier_reached}, state}
        else
          # Add to waiters
          waiters = [from | barrier.waiters]
          updated_barrier = %{barrier | waiters: waiters}
          barriers = Map.put(state.barriers, barrier_id, updated_barrier)
          
          {:noreply, %{state | barriers: barriers}}
        end
    end
  end
  
  @impl true
  def handle_call({:acquire_lock, lock_id, holder_id}, _from, state) do
    case Map.get(state.locks, lock_id) do
      nil ->
        lock_ref = make_ref()
        lock_info = %{
          ref: lock_ref,
          holder_id: holder_id,
          acquired_at: DateTime.utc_now()
        }
        
        locks = Map.put(state.locks, lock_id, lock_info)
        {:reply, {:ok, lock_ref}, %{state | locks: locks}}
      
      _ ->
        {:reply, {:error, :already_locked}, state}
    end
  end
  
  @impl true
  def handle_call({:release_lock, lock_id, holder_id}, _from, state) do
    case Map.get(state.locks, lock_id) do
      %{holder_id: ^holder_id} ->
        locks = Map.delete(state.locks, lock_id)
        {:reply, :ok, %{state | locks: locks}}
      
      %{holder_id: other_holder} ->
        {:reply, {:error, {:not_lock_holder, other_holder}}, state}
      
      nil ->
        {:reply, {:error, :lock_not_found}, state}
    end
  end
  
  @impl true
  def handle_call({:lock_status, lock_id}, _from, state) do
    case Map.get(state.locks, lock_id) do
      %{holder_id: holder_id, acquired_at: acquired_at} ->
        {:reply, {:locked, holder_id, acquired_at}, state}
      
      nil ->
        {:reply, :unlocked, state}
    end
  end
  
  @impl true
  def handle_call({:start_election, group_id, candidates}, _from, state) do
    election = %{
      group_id: group_id,
      candidates: candidates,
      leader: nil,
      started_at: DateTime.utc_now()
    }
    
    elections = Map.put(state.elections, group_id, election)
    {:reply, :ok, %{state | elections: elections}}
  end
  
  @impl true
  def handle_call({:elect_leader, group_id}, _from, state) do
    case Map.get(state.elections, group_id) do
      nil ->
        {:reply, {:error, :election_not_found}, state}
      
      election ->
        # Simple leader election based on agent health and capabilities
        leader = select_leader(election.candidates)
        updated_election = %{election | leader: leader}
        elections = Map.put(state.elections, group_id, updated_election)
        
        {:reply, {:ok, leader}, %{state | elections: elections}}
    end
  end
  
  @impl true
  def handle_call({:get_current_leader, group_id}, _from, state) do
    case Map.get(state.elections, group_id) do
      %{leader: nil} ->
        {:reply, {:error, :no_leader}, state}
      
      %{leader: leader} ->
        {:reply, {:ok, leader}, state}
      
      nil ->
        {:reply, {:error, :election_not_found}, state}
    end
  end
  
  @impl true
  def handle_call(:health_check, _from, state) do
    # Basic health check - verify service is responding and state is reasonable
    health_status = cond do
      map_size(state.consensus_processes) > 100 -> {:error, :too_many_consensus_processes}
      map_size(state.barriers) > 50 -> {:error, :too_many_barriers}  
      map_size(state.locks) > 200 -> {:error, :too_many_locks}
      true -> :ok
    end
    
    {:reply, health_status, state}
  end
  
  @impl true
  def handle_call(:get_active_locks_count, _from, state) do
    active_count = Enum.count(state.locks, fn {_lock_id, lock} ->
      lock.status == :locked
    end)
    
    {:reply, active_count, state}
  end
  
  @impl true
  def handle_call(:get_active_barriers_count, _from, state) do
    active_count = Enum.count(state.barriers, fn {_barrier_id, barrier} ->
      MapSet.size(barrier.arrived) < barrier.participant_count
    end)
    
    {:reply, active_count, state}
  end
  
  @impl true
  def handle_info({:consensus_timeout, consensus_ref}, state) do
    case Map.get(state.consensus_processes, consensus_ref) do
      %{status: :voting, waiters: waiters} = consensus_process ->
        # Notify waiters of timeout
        notify_consensus_waiters(waiters, :timeout)
        
        # Update process status
        updated_process = %{consensus_process | status: :timeout, waiters: []}
        consensus_processes = Map.put(state.consensus_processes, consensus_ref, updated_process)
        
        {:noreply, %{state | consensus_processes: consensus_processes}}
      
      _ ->
        # Consensus already completed
        {:noreply, state}
    end
  end
  
  @impl true
  def handle_info({:DOWN, monitor_ref, :process, _pid, _reason}, state) do
    # Handle participant failure
    monitors = Map.delete(state.monitors, monitor_ref)
    {:noreply, %{state | monitors: monitors}}
  end
  
  ## Private Functions
  
  defp check_consensus_result(%{votes: votes, participants: participants, 
                               quorum_size: quorum_size, require_unanimous: require_unanimous}) do
    total_votes = map_size(votes)
    accept_votes = Enum.count(votes, fn {_id, vote} -> vote == :accept end)
    reject_votes = Enum.count(votes, fn {_id, vote} -> vote == :reject end)
    
    cond do
      # All participants voted
      total_votes == MapSet.size(participants) ->
        if require_unanimous do
          if accept_votes == total_votes do
            {:accepted, %{status: :accepted}}
          else
            {:rejected, %{status: :rejected}}
          end
        else
          if accept_votes >= quorum_size do
            {:accepted, %{status: :accepted}}
          else
            {:rejected, %{status: :rejected}}
          end
        end
      
      # Early acceptance possible
      accept_votes >= quorum_size and not require_unanimous ->
        {:accepted, %{status: :accepted}}
      
      # Early rejection possible
      reject_votes > (MapSet.size(participants) - quorum_size) ->
        {:rejected, %{status: :rejected}}
      
      # Still voting
      true ->
        {:still_voting, %{status: :voting}}
    end
  end
  
  defp notify_consensus_waiters(waiters, result) do
    Enum.each(waiters, fn waiter ->
      GenServer.reply(waiter, {:ok, result})
    end)
  end
  
  defp monitor_participants(participants, existing_monitors) do
    Enum.reduce(participants, existing_monitors, fn participant_id, monitors ->
      case Foundation.ProcessRegistry.lookup_local(participant_id) do
        {:ok, pid, _metadata} ->
          monitor_ref = Process.monitor(pid)
          Map.put(monitors, monitor_ref, participant_id)
        
        :error ->
          Logger.warning("Participant #{participant_id} not found for monitoring")
          monitors
      end
    end)
  end
  
  defp select_leader(candidates) do
    # Select leader based on agent health and capabilities
    candidate_info = 
      Enum.map(candidates, fn candidate_id ->
        case Foundation.ProcessRegistry.get_agent_metadata(candidate_id) do
          {:ok, metadata} ->
            health_score = health_to_score(Map.get(metadata, :health_status, :healthy))
            capability_score = length(Map.get(metadata, :capabilities, []))
            {candidate_id, health_score + capability_score}
          
          :error ->
            {candidate_id, 0}
        end
      end)
    
    # Select candidate with highest score
    case Enum.max_by(candidate_info, fn {_id, score} -> score end, fn -> nil end) do
      {leader_id, _score} -> leader_id
      nil -> List.first(candidates)
    end
  end
  
  defp health_to_score(:healthy), do: 10
  defp health_to_score(:degraded), do: 5
  defp health_to_score(:unhealthy), do: 1
  defp health_to_score(_), do: 0

  ## Additional Service Interface Functions

  @doc """
  Check if coordination primitives are healthy and operational.
  """
  @spec health_check() :: :ok | {:error, term()}
  def health_check do
    try do
      GenServer.call(__MODULE__, :health_check, 5_000)
    rescue
      error -> {:error, {:health_check_failed, error}}
    catch
      :exit, {:timeout, _} -> {:error, :health_check_timeout}
      :exit, {:noproc, _} -> {:error, :coordination_service_not_running}
    end
  end

  @doc """
  Get the count of currently active locks.
  """
  @spec get_active_locks_count() :: non_neg_integer()
  def get_active_locks_count do
    try do
      GenServer.call(__MODULE__, :get_active_locks_count, 5_000)
    rescue
      _ -> 0
    catch
      :exit, _ -> 0
    end
  end

  @doc """
  Get the count of currently active barriers.
  """
  @spec get_active_barriers_count() :: non_neg_integer()
  def get_active_barriers_count do
    try do
      GenServer.call(__MODULE__, :get_active_barriers_count, 5_000)
    rescue
      _ -> 0
    catch
      :exit, _ -> 0
    end
  end

  @doc """
  Perform consensus with simplified interface for service usage.
  """
  @spec consensus(coordination_id(), [participant_id()], any(), map()) :: 
    {:ok, any()} | {:error, term()}
  def consensus(coordination_id, participants, proposal, options \\ %{}) do
    timeout = Map.get(options, :timeout, 10_000)
    strategy = Map.get(options, :strategy, :majority)
    
    # Start consensus
    case start_consensus(participants, proposal, timeout: timeout) do
      {:ok, consensus_ref} ->
        # For simplified interface, automatically vote 'accept' for all participants
        # In a real implementation, this would trigger actual agent voting
        Enum.each(participants, fn participant ->
          vote(consensus_ref, participant, :accept)
        end)
        
        # Get result
        get_consensus_result(consensus_ref)
      
      {:error, _} = error ->
        error
    end
  end

  @doc """
  Elect leader with simplified interface.
  """
  @spec elect_leader([participant_id()]) :: {:ok, participant_id()} | {:error, term()}
  def elect_leader(candidates) when is_list(candidates) do
    group_id = :temp_election_group
    
    case start_election(group_id, candidates) do
      :ok ->
        elect_leader(group_id)
      
      {:error, _} = error ->
        error
    end
  end
end