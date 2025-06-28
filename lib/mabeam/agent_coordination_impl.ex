defimpl Foundation.Coordination, for: MABEAM.AgentCoordination do
  @moduledoc """
  Foundation.Coordination protocol implementation for MABEAM.AgentCoordination.

  All operations are delegated to the GenServer process to ensure
  consistency and proper state management.
  """

  # --- Consensus Operations ---

  def start_consensus(coordination_pid, participants, proposal, timeout) do
    GenServer.call(coordination_pid, {:start_consensus, participants, proposal, timeout})
  end

  def vote(coordination_pid, consensus_ref, participant, vote) do
    GenServer.call(coordination_pid, {:vote, consensus_ref, participant, vote})
  end

  def get_consensus_result(coordination_pid, consensus_ref) do
    GenServer.call(coordination_pid, {:get_consensus_result, consensus_ref})
  end

  # --- Barrier Operations ---

  def create_barrier(coordination_pid, barrier_id, participant_count) do
    GenServer.call(coordination_pid, {:create_barrier, barrier_id, participant_count})
  end

  def arrive_at_barrier(coordination_pid, barrier_id, participant) do
    GenServer.call(coordination_pid, {:arrive_at_barrier, barrier_id, participant})
  end

  def wait_for_barrier(coordination_pid, barrier_id, timeout) do
    GenServer.call(coordination_pid, {:wait_for_barrier, barrier_id, timeout}, timeout + 1000)
  end

  # --- Lock Operations ---

  def acquire_lock(coordination_pid, lock_id, holder, timeout) do
    GenServer.call(coordination_pid, {:acquire_lock, lock_id, holder, timeout}, timeout + 1000)
  end

  def release_lock(coordination_pid, lock_ref) do
    GenServer.call(coordination_pid, {:release_lock, lock_ref})
  end

  def get_lock_status(coordination_pid, lock_id) do
    GenServer.call(coordination_pid, {:get_lock_status, lock_id})
  end

  def protocol_version(_coordination_pid) do
    {:ok, "1.0"}
  end
end
