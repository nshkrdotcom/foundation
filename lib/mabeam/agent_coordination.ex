defmodule MABEAM.AgentCoordination do
  @moduledoc """
  GenServer-based coordination backend for multi-agent systems.

  Implements the Foundation.Coordination protocol with agent-specific
  optimizations for consensus, barriers, and distributed locks.

  ## Features

  - **Consensus**: Multi-phase voting with quorum support
  - **Barriers**: Synchronization points for agent coordination
  - **Distributed Locks**: Mutual exclusion for shared resources
  - **Timeout Management**: Automatic cleanup of stale coordination

  ## Implementation Details

  All coordination state is managed through ETS tables for performance,
  with the GenServer process handling state transitions and cleanup.
  """

  use GenServer
  require Logger

  defstruct consensus_table: nil,
            barrier_table: nil,
            lock_table: nil,
            coordination_id: nil,
            cleanup_interval: 60_000,
            cleanup_timer: nil

  # Consensus states - removed as unused

  # --- OTP Lifecycle ---

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  def init(opts) do
    # Generate unique coordination ID for table names
    coordination_id = Keyword.get(opts, :id, :default)
    cleanup_interval = Keyword.get(opts, :cleanup_interval, 60_000)

    # Create unique table names for this instance
    consensus_table_name = :"agent_consensus_#{coordination_id}"
    barrier_table_name = :"agent_barrier_#{coordination_id}"
    lock_table_name = :"agent_lock_#{coordination_id}"

    # Clean up any existing tables from previous runs
    [consensus_table_name, barrier_table_name, lock_table_name]
    |> Enum.each(&safe_ets_delete/1)

    # Tables are private to this process
    table_opts = [:private, read_concurrency: true, write_concurrency: true]

    state = %__MODULE__{
      consensus_table: :ets.new(consensus_table_name, [:set | table_opts]),
      barrier_table: :ets.new(barrier_table_name, [:set | table_opts]),
      lock_table: :ets.new(lock_table_name, [:set | table_opts]),
      coordination_id: coordination_id,
      cleanup_interval: cleanup_interval
    }

    # Register tables with ResourceManager if available
    if Process.whereis(Foundation.ResourceManager) do
      Foundation.ResourceManager.monitor_table(state.consensus_table)
      Foundation.ResourceManager.monitor_table(state.barrier_table)
      Foundation.ResourceManager.monitor_table(state.lock_table)
    end

    # Schedule periodic cleanup
    cleanup_timer = Process.send_after(self(), :cleanup_expired, cleanup_interval)

    Logger.info("MABEAM.AgentCoordination (#{coordination_id}) started")

    {:ok, %{state | cleanup_timer: cleanup_timer}}
  end

  def terminate(_reason, state) do
    Logger.info("MABEAM.AgentCoordination (#{state.coordination_id}) terminating")

    # Cancel cleanup timer
    if state.cleanup_timer do
      Process.cancel_timer(state.cleanup_timer)
    end

    # Clean up ETS tables
    safe_ets_delete(state.consensus_table)
    safe_ets_delete(state.barrier_table)
    safe_ets_delete(state.lock_table)
    :ok
  end

  defp safe_ets_delete(table) do
    :ets.delete(table)
  rescue
    ArgumentError -> :ok
  end

  # --- Consensus Implementation ---

  def handle_call({:start_consensus, participants, proposal, timeout}, _from, state) do
    if length(participants) < 1 do
      {:reply, {:error, :insufficient_participants}, state}
    else
      consensus_ref = generate_ref()
      deadline = System.monotonic_time(:millisecond) + timeout

      consensus_data = %{
        ref: consensus_ref,
        participants: MapSet.new(participants),
        proposal: proposal,
        votes: %{},
        state: :voting,
        deadline: deadline,
        started_at: System.monotonic_time(:millisecond)
      }

      :ets.insert(state.consensus_table, {consensus_ref, consensus_data})

      # Schedule timeout
      Process.send_after(self(), {:consensus_timeout, consensus_ref}, timeout)

      Logger.debug(
        "Started consensus #{inspect(consensus_ref)} with #{length(participants)} participants"
      )

      {:reply, {:ok, consensus_ref}, state}
    end
  end

  def handle_call({:vote, consensus_ref, participant, vote}, _from, state) do
    case :ets.lookup(state.consensus_table, consensus_ref) do
      [{^consensus_ref, consensus_data}] ->
        cond do
          consensus_data.state != :voting ->
            {:reply, {:error, :consensus_closed}, state}

          not MapSet.member?(consensus_data.participants, participant) ->
            {:reply, {:error, :invalid_participant}, state}

          Map.has_key?(consensus_data.votes, participant) ->
            {:reply, {:error, :already_voted}, state}

          true ->
            # Record vote
            updated_data = %{
              consensus_data
              | votes: Map.put(consensus_data.votes, participant, vote)
            }

            # Check if all votes are in and update accordingly
            finalize_consensus_if_complete(consensus_ref, updated_data, state)
            {:reply, :ok, state}
        end

      [] ->
        {:reply, {:error, :consensus_not_found}, state}
    end
  end

  def handle_call({:get_consensus_result, consensus_ref}, _from, state) do
    case :ets.lookup(state.consensus_table, consensus_ref) do
      [{^consensus_ref, consensus_data}] ->
        case consensus_data.state do
          :voting ->
            {:reply, {:error, :consensus_in_progress}, state}

          :completed ->
            # Calculate result based on votes
            result = calculate_consensus_result(consensus_data)
            {:reply, {:ok, result}, state}

          :failed ->
            {:reply, {:error, :consensus_failed}, state}

          :timeout ->
            {:reply, {:error, :consensus_timeout}, state}
        end

      [] ->
        {:reply, {:error, :consensus_not_found}, state}
    end
  end

  # --- Barrier Implementation ---

  def handle_call({:create_barrier, barrier_id, participant_count}, _from, state) do
    if participant_count < 1 do
      {:reply, {:error, :invalid_participant_count}, state}
    else
      case :ets.lookup(state.barrier_table, barrier_id) do
        [] ->
          barrier_data = %{
            id: barrier_id,
            required_count: participant_count,
            arrived: MapSet.new(),
            created_at: System.monotonic_time(:millisecond)
          }

          :ets.insert(state.barrier_table, {barrier_id, barrier_data})

          Logger.debug(
            "Created barrier #{inspect(barrier_id)} for #{participant_count} participants"
          )

          {:reply, :ok, state}

        _ ->
          {:reply, {:error, :already_exists}, state}
      end
    end
  end

  def handle_call({:arrive_at_barrier, barrier_id, participant}, _from, state) do
    case :ets.lookup(state.barrier_table, barrier_id) do
      [{^barrier_id, barrier_data}] ->
        cond do
          MapSet.member?(barrier_data.arrived, participant) ->
            {:reply, {:error, :already_arrived}, state}

          MapSet.size(barrier_data.arrived) >= barrier_data.required_count ->
            {:reply, {:error, :barrier_full}, state}

          true ->
            updated_data = %{barrier_data | arrived: MapSet.put(barrier_data.arrived, participant)}
            :ets.insert(state.barrier_table, {barrier_id, updated_data})

            Logger.debug(
              "Participant #{inspect(participant)} arrived at barrier #{inspect(barrier_id)}"
            )

            {:reply, :ok, state}
        end

      [] ->
        {:reply, {:error, :barrier_not_found}, state}
    end
  end

  def handle_call({:wait_for_barrier, barrier_id, timeout}, from, state) do
    case :ets.lookup(state.barrier_table, barrier_id) do
      [{^barrier_id, barrier_data}] ->
        if MapSet.size(barrier_data.arrived) >= barrier_data.required_count do
          # Barrier already complete
          {:reply, :ok, state}
        else
          # Schedule check with timeout
          Process.send_after(self(), {:check_barrier, barrier_id, from}, 100)
          Process.send_after(self(), {:barrier_timeout, barrier_id, from}, timeout)
          {:noreply, state}
        end

      [] ->
        {:reply, {:error, :barrier_not_found}, state}
    end
  end

  # --- Lock Implementation ---

  def handle_call({:acquire_lock, lock_id, holder, timeout}, from, state) do
    case :ets.lookup(state.lock_table, lock_id) do
      [] ->
        # Lock available, acquire it
        lock_ref = generate_ref()

        lock_data = %{
          id: lock_id,
          ref: lock_ref,
          holder: holder,
          acquired_at: System.monotonic_time(:millisecond)
        }

        :ets.insert(state.lock_table, {lock_id, lock_data})

        Logger.debug("Lock #{inspect(lock_id)} acquired by #{inspect(holder)}")

        {:reply, {:ok, lock_ref}, state}

      [{^lock_id, _existing_lock}] ->
        # Lock held, schedule retry with timeout
        Process.send_after(self(), {:retry_lock, lock_id, holder, from, timeout}, 100)
        Process.send_after(self(), {:lock_timeout, lock_id, from}, timeout)
        {:noreply, state}
    end
  end

  def handle_call({:release_lock, lock_ref}, _from, state) do
    # Find lock by ref
    case find_lock_by_ref(state.lock_table, lock_ref) do
      {lock_id, lock_data} ->
        if lock_data.ref == lock_ref do
          :ets.delete(state.lock_table, lock_id)
          Logger.debug("Lock #{inspect(lock_id)} released")
          {:reply, :ok, state}
        else
          {:reply, {:error, :not_lock_holder}, state}
        end

      nil ->
        {:reply, {:error, :lock_not_found}, state}
    end
  end

  def handle_call({:get_lock_status, lock_id}, _from, state) do
    case :ets.lookup(state.lock_table, lock_id) do
      [] ->
        {:reply, {:ok, :available}, state}

      [{^lock_id, lock_data}] ->
        {:reply, {:ok, {:held_by, lock_data.holder}}, state}
    end
  end

  # --- Periodic Cleanup ---

  def handle_info(:cleanup_expired, state) do
    now = System.monotonic_time(:millisecond)

    # Clean expired consensus
    cleanup_expired_consensus(state.consensus_table, now)

    # Clean old barriers (older than 1 hour)
    cleanup_old_barriers(state.barrier_table, now - 3_600_000)

    # Schedule next cleanup
    cleanup_timer = Process.send_after(self(), :cleanup_expired, state.cleanup_interval)

    {:noreply, %{state | cleanup_timer: cleanup_timer}}
  end

  # --- Consensus Timeout Handling ---

  def handle_info({:consensus_timeout, consensus_ref}, state) do
    case :ets.lookup(state.consensus_table, consensus_ref) do
      [{^consensus_ref, consensus_data}] ->
        if consensus_data.state == :voting do
          # Mark as timeout
          updated_data = %{consensus_data | state: :timeout}
          :ets.insert(state.consensus_table, {consensus_ref, updated_data})
          Logger.warning("Consensus #{inspect(consensus_ref)} timed out")
        end

      [] ->
        :ok
    end

    {:noreply, state}
  end

  # --- Barrier Checking ---

  def handle_info({:check_barrier, barrier_id, from}, state) do
    case :ets.lookup(state.barrier_table, barrier_id) do
      [{^barrier_id, barrier_data}] ->
        if MapSet.size(barrier_data.arrived) >= barrier_data.required_count do
          GenServer.reply(from, :ok)
        else
          # Check again later
          Process.send_after(self(), {:check_barrier, barrier_id, from}, 100)
        end

      [] ->
        GenServer.reply(from, {:error, :barrier_not_found})
    end

    {:noreply, state}
  end

  def handle_info({:barrier_timeout, _barrier_id, from}, state) do
    GenServer.reply(from, {:error, :barrier_timeout})
    {:noreply, state}
  end

  # --- Lock Retry Handling ---

  def handle_info({:retry_lock, lock_id, holder, from, timeout}, state) do
    case :ets.lookup(state.lock_table, lock_id) do
      [] ->
        # Lock now available
        lock_ref = generate_ref()

        lock_data = %{
          id: lock_id,
          ref: lock_ref,
          holder: holder,
          acquired_at: System.monotonic_time(:millisecond)
        }

        :ets.insert(state.lock_table, {lock_id, lock_data})
        GenServer.reply(from, {:ok, lock_ref})

      _ ->
        # Still held, retry
        Process.send_after(self(), {:retry_lock, lock_id, holder, from, timeout}, 100)
    end

    {:noreply, state}
  end

  def handle_info({:lock_timeout, _lock_id, from}, state) do
    GenServer.reply(from, {:error, :lock_timeout})
    {:noreply, state}
  end

  # --- Private Helpers ---

  defp finalize_consensus_if_complete(consensus_ref, consensus_data, state) do
    if map_size(consensus_data.votes) == MapSet.size(consensus_data.participants) do
      # Complete consensus
      final_data = %{consensus_data | state: :completed}
      :ets.insert(state.consensus_table, {consensus_ref, final_data})
      Logger.debug("Consensus #{inspect(consensus_ref)} completed with all votes")
    else
      :ets.insert(state.consensus_table, {consensus_ref, consensus_data})
    end
  end

  defp generate_ref do
    :erlang.make_ref()
  end

  defp calculate_consensus_result(consensus_data) do
    %{
      proposal: consensus_data.proposal,
      votes: consensus_data.votes,
      participant_count: MapSet.size(consensus_data.participants),
      vote_count: map_size(consensus_data.votes),
      duration_ms: System.monotonic_time(:millisecond) - consensus_data.started_at
    }
  end

  defp find_lock_by_ref(lock_table, lock_ref) do
    :ets.tab2list(lock_table)
    |> Enum.find(fn {_lock_id, lock_data} -> lock_data.ref == lock_ref end)
  end

  defp cleanup_expired_consensus(consensus_table, now) do
    :ets.tab2list(consensus_table)
    |> Enum.each(fn {ref, data} ->
      if data.deadline < now and data.state == :voting do
        updated_data = %{data | state: :timeout}
        :ets.insert(consensus_table, {ref, updated_data})
      end
    end)
  end

  defp cleanup_old_barriers(barrier_table, cutoff_time) do
    :ets.tab2list(barrier_table)
    |> Enum.each(fn {id, data} ->
      if data.created_at < cutoff_time do
        :ets.delete(barrier_table, id)
        Logger.debug("Cleaned up old barrier #{inspect(id)}")
      end
    end)
  end
end
