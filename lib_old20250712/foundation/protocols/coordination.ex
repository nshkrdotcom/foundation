defprotocol Foundation.Coordination do
  @moduledoc """
  Universal protocol for distributed coordination primitives.

  ## Protocol Version
  Current version: 1.0

  ## Common Error Returns
  - `{:error, :invalid_participants}`
  - `{:error, :consensus_timeout}`
  - `{:error, :barrier_timeout}`
  - `{:error, :lock_timeout}`
  - `{:error, :already_exists}`
  - `{:error, :not_found}`
  """

  @fallback_to_any true

  # --- Consensus Protocols ---

  @doc """
  Starts a consensus process among participants.

  ## Parameters
  - `impl`: The coordination implementation
  - `participants`: List of participant identifiers
  - `proposal`: The proposal to reach consensus on
  - `timeout`: Timeout in milliseconds

  ## Returns
  - `{:ok, consensus_ref}` with reference to track consensus
  - `{:error, :invalid_participants}` if participants list is invalid
  - `{:error, :insufficient_participants}` if not enough participants
  """
  @spec start_consensus(t(), participants :: [term()], proposal :: term(), timeout()) ::
          {:ok, consensus_ref :: term()} | {:error, term()}
  def start_consensus(impl, participants, proposal, timeout \\ 30_000)

  @doc """
  Submits a vote for an ongoing consensus.

  ## Parameters
  - `impl`: The coordination implementation
  - `consensus_ref`: Reference returned from start_consensus
  - `participant`: The participant submitting the vote
  - `vote`: The vote value

  ## Returns
  - `:ok` on successful vote submission
  - `{:error, :consensus_not_found}` if consensus reference is invalid
  - `{:error, :invalid_participant}` if participant not in consensus
  - `{:error, :consensus_closed}` if consensus already completed
  """
  @spec vote(t(), consensus_ref :: term(), participant :: term(), vote :: term()) ::
          :ok | {:error, term()}
  def vote(impl, consensus_ref, participant, vote)

  @doc """
  Gets the result of a consensus process.

  ## Parameters
  - `impl`: The coordination implementation
  - `consensus_ref`: Reference returned from start_consensus

  ## Returns
  - `{:ok, result}` if consensus completed successfully
  - `{:error, :consensus_in_progress}` if still ongoing
  - `{:error, :consensus_failed}` if consensus failed
  - `{:error, :consensus_not_found}` if reference is invalid
  """
  @spec get_consensus_result(t(), consensus_ref :: term()) ::
          {:ok, result :: term()} | {:error, term()}
  def get_consensus_result(impl, consensus_ref)

  # --- Barrier Synchronization ---

  @doc """
  Creates a barrier for participant synchronization.

  ## Parameters
  - `impl`: The coordination implementation
  - `barrier_id`: Unique identifier for the barrier
  - `participant_count`: Number of participants that must arrive

  ## Returns
  - `:ok` on successful barrier creation
  - `{:error, :already_exists}` if barrier_id already exists
  - `{:error, :invalid_participant_count}` if count is invalid
  """
  @spec create_barrier(t(), barrier_id :: term(), participant_count :: pos_integer()) ::
          :ok | {:error, term()}
  def create_barrier(impl, barrier_id, participant_count)

  @doc """
  Signals arrival at a barrier.

  ## Parameters
  - `impl`: The coordination implementation
  - `barrier_id`: The barrier identifier
  - `participant`: The arriving participant identifier

  ## Returns
  - `:ok` on successful arrival
  - `{:error, :barrier_not_found}` if barrier doesn't exist
  - `{:error, :already_arrived}` if participant already arrived
  - `{:error, :barrier_full}` if all participants already arrived
  """
  @spec arrive_at_barrier(t(), barrier_id :: term(), participant :: term()) ::
          :ok | {:error, term()}
  def arrive_at_barrier(impl, barrier_id, participant)

  @doc """
  Waits for all participants to arrive at a barrier.

  ## Parameters
  - `impl`: The coordination implementation
  - `barrier_id`: The barrier identifier
  - `timeout`: Maximum time to wait in milliseconds

  ## Returns
  - `:ok` when all participants have arrived
  - `{:error, :barrier_timeout}` if timeout exceeded
  - `{:error, :barrier_not_found}` if barrier doesn't exist
  """
  @spec wait_for_barrier(t(), barrier_id :: term(), timeout()) ::
          :ok | {:error, term()}
  def wait_for_barrier(impl, barrier_id, timeout \\ 60_000)

  # --- Distributed Locks ---

  @doc """
  Acquires a distributed lock.

  ## Parameters
  - `impl`: The coordination implementation
  - `lock_id`: Unique identifier for the lock
  - `holder`: The process/agent requesting the lock
  - `timeout`: Maximum time to wait for lock acquisition

  ## Returns
  - `{:ok, lock_ref}` with reference to the acquired lock
  - `{:error, :lock_timeout}` if timeout exceeded
  - `{:error, :lock_unavailable}` if lock cannot be acquired
  """
  @spec acquire_lock(t(), lock_id :: term(), holder :: term(), timeout()) ::
          {:ok, lock_ref :: term()} | {:error, term()}
  def acquire_lock(impl, lock_id, holder, timeout \\ 30_000)

  @doc """
  Releases a distributed lock.

  ## Parameters
  - `impl`: The coordination implementation
  - `lock_ref`: Reference returned from acquire_lock

  ## Returns
  - `:ok` on successful release
  - `{:error, :lock_not_found}` if lock reference is invalid
  - `{:error, :not_lock_holder}` if caller doesn't hold the lock
  """
  @spec release_lock(t(), lock_ref :: term()) ::
          :ok | {:error, term()}
  def release_lock(impl, lock_ref)

  @doc """
  Gets the current status of a lock.

  ## Parameters
  - `impl`: The coordination implementation
  - `lock_id`: The lock identifier

  ## Returns
  - `{:ok, :available}` if lock is available
  - `{:ok, {:held_by, holder}}` if lock is held
  - `{:error, :lock_not_found}` if lock doesn't exist
  """
  @spec get_lock_status(t(), lock_id :: term()) ::
          {:ok, :available | {:held_by, term()}} | {:error, term()}
  def get_lock_status(impl, lock_id)

  @doc """
  Returns the protocol version supported by this implementation.

  ## Returns
  - `{:ok, version_string}` - The supported protocol version
  - `{:error, :version_unsupported}` - If version checking is not supported

  ## Examples
      {:ok, "1.0"} = Foundation.Coordination.protocol_version(coordination_impl)
  """
  @spec protocol_version(t()) :: {:ok, String.t()} | {:error, term()}
  def protocol_version(impl)
end
