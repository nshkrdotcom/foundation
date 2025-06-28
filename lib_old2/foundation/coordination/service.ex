defmodule Foundation.Coordination.Service do
  @moduledoc """
  Coordination service wrapper for Foundation coordination primitives.

  Provides a GenServer-based service interface to the coordination primitives,
  offering lifecycle management, health monitoring, and service discovery
  integration. Acts as the primary entry point for coordination operations
  in the Foundation infrastructure.

  ## Features

  - **Service Lifecycle**: Proper OTP supervision and health monitoring
  - **Primitive Management**: Centralized access to all coordination primitives
  - **Agent Integration**: Coordination operations with agent context awareness
  - **Performance Monitoring**: Telemetry and metrics for coordination operations
  - **Error Recovery**: Automatic recovery from coordination failures
  - **Distribution Ready**: Prepared for multi-node coordination scenarios

  ## Coordination Operations Provided

  - **Consensus**: Multi-agent consensus with various voting strategies
  - **Barriers**: Synchronization points for coordinated agent execution
  - **Locks**: Distributed locking with deadlock prevention
  - **Leader Election**: Automatic leader selection based on agent capabilities
  - **Resource Allocation**: Coordinated resource assignment across agents

  ## Usage

      # Service is typically started by Foundation.Application
      # Direct usage examples:

      # Consensus operation
      {:ok, result} = CoordinationService.consensus(
        :model_selection,
        [:agent_1, :agent_2, :agent_3],
        %{strategy: :majority, timeout: 5_000}
      )

      # Barrier synchronization
      CoordinationService.create_barrier(:training_complete, [:agent_1, :agent_2])
      CoordinationService.wait_for_barrier(:training_complete, :agent_1)

      # Distributed locking
      {:ok, lock} = CoordinationService.acquire_lock(:shared_resource, :agent_1)
      CoordinationService.release_lock(lock)

      # Leader election
      {:ok, leader} = CoordinationService.elect_leader([:agent_1, :agent_2, :agent_3])
  """

  use GenServer
  require Logger

  alias Foundation.Coordination.Primitives
  alias Foundation.ProcessRegistry
  alias Foundation.Telemetry
  alias Foundation.Types.Error

  @type agent_id :: atom() | String.t()
  @type coordination_id :: atom() | String.t()
  @type consensus_strategy :: :unanimous | :majority | :quorum
  @type lock_id :: String.t()
  @type barrier_id :: atom() | String.t()

  @type consensus_options :: %{
    strategy: consensus_strategy(),
    timeout: pos_integer(),
    quorum_size: pos_integer() | nil
  }

  @type coordination_result :: {:ok, any()} | {:error, Error.t()}
  @type service_stats :: %{
    consensus_operations: non_neg_integer(),
    barrier_operations: non_neg_integer(),
    lock_operations: non_neg_integer(),
    election_operations: non_neg_integer(),
    active_locks: non_neg_integer(),
    active_barriers: non_neg_integer(),
    uptime: pos_integer()
  }

  defstruct [
    :namespace,
    :health_check_interval,
    :operation_timeout,
    :coordination_stats,
    :active_operations,
    :service_start_time
  ]

  @type t :: %__MODULE__{
    namespace: atom(),
    health_check_interval: pos_integer(),
    operation_timeout: pos_integer(),
    coordination_stats: map(),
    active_operations: :ets.tid(),
    service_start_time: DateTime.t()
  }

  # Default configuration
  @default_health_check_interval 30_000
  @default_operation_timeout 10_000

  # Public API

  @doc """
  Start the coordination service.

  Typically called by Foundation.Application during startup.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(options \\ []) do
    namespace = Keyword.get(options, :namespace, :foundation)
    GenServer.start_link(__MODULE__, options, name: service_name(namespace))
  end

  @doc """
  Perform consensus operation among specified agents.

  Initiates a consensus process where participating agents vote on a proposal.
  The result depends on the consensus strategy specified.

  ## Parameters
  - `coordination_id`: Unique identifier for this consensus operation
  - `participants`: List of agent IDs that will participate in consensus
  - `proposal`: The proposal data to vote on
  - `options`: Consensus configuration options

  ## Examples

      # Majority consensus for model selection
      {:ok, selected_model} = CoordinationService.consensus(
        :model_selection_round_1,
        [:ml_agent_1, :ml_agent_2, :ml_agent_3],
        %{models: ["gpt-4", "claude-3", "llama-2"]},
        %{strategy: :majority, timeout: 5_000}
      )

      # Unanimous consensus for critical decision
      {:ok, :approved} = CoordinationService.consensus(
        :safety_approval,
        [:safety_agent, :compliance_agent, :lead_agent],
        %{action: :deploy_to_production},
        %{strategy: :unanimous, timeout: 10_000}
      )
  """
  @spec consensus(coordination_id(), [agent_id()], any(), consensus_options(), atom()) ::
    coordination_result()
  def consensus(coordination_id, participants, proposal, options \\ %{}, namespace \\ :foundation) do
    GenServer.call(
      service_name(namespace),
      {:consensus, coordination_id, participants, proposal, options},
      get_operation_timeout(options)
    )
  rescue
    error -> {:error, coordination_service_error("consensus failed", error)}
  end

  @doc """
  Create a barrier for coordinated synchronization.

  Creates a synchronization barrier that agents can wait on. The barrier
  is satisfied when all specified participants have reached it.

  ## Examples

      # Create barrier for training completion
      :ok = CoordinationService.create_barrier(
        :training_phase_1_complete,
        [:trainer_1, :trainer_2, :trainer_3]
      )
  """
  @spec create_barrier(barrier_id(), [agent_id()], atom()) :: :ok | {:error, Error.t()}
  def create_barrier(barrier_id, participants, namespace \\ :foundation) do
    GenServer.call(
      service_name(namespace),
      {:create_barrier, barrier_id, participants}
    )
  rescue
    error -> {:error, coordination_service_error("create_barrier failed", error)}
  end

  @doc """
  Wait for a barrier to be satisfied.

  Blocks until all participants have reached the specified barrier.

  ## Examples

      # Wait for all agents to complete training
      :ok = CoordinationService.wait_for_barrier(:training_complete, :ml_agent_1)
  """
  @spec wait_for_barrier(barrier_id(), agent_id(), pos_integer(), atom()) ::
    :ok | {:error, Error.t()}
  def wait_for_barrier(barrier_id, agent_id, timeout \\ @default_operation_timeout, namespace \\ :foundation) do
    GenServer.call(
      service_name(namespace),
      {:wait_for_barrier, barrier_id, agent_id},
      timeout
    )
  rescue
    error -> {:error, coordination_service_error("wait_for_barrier failed", error)}
  end

  @doc """
  Acquire a distributed lock.

  Attempts to acquire an exclusive lock for the specified resource.
  Returns a lock identifier that must be used to release the lock.

  ## Examples

      # Acquire lock on shared model
      {:ok, lock_id} = CoordinationService.acquire_lock(
        :shared_model_weights,
        :ml_agent_1,
        5_000  # timeout
      )

      # Use the resource...

      # Release the lock
      :ok = CoordinationService.release_lock(lock_id)
  """
  @spec acquire_lock(coordination_id(), agent_id(), pos_integer(), atom()) ::
    {:ok, lock_id()} | {:error, Error.t()}
  def acquire_lock(resource_id, agent_id, timeout \\ @default_operation_timeout, namespace \\ :foundation) do
    GenServer.call(
      service_name(namespace),
      {:acquire_lock, resource_id, agent_id},
      timeout
    )
  rescue
    error -> {:error, coordination_service_error("acquire_lock failed", error)}
  end

  @doc """
  Release a previously acquired lock.

  ## Examples

      :ok = CoordinationService.release_lock("lock_abc123")
  """
  @spec release_lock(lock_id(), atom()) :: :ok | {:error, Error.t()}
  def release_lock(lock_id, namespace \\ :foundation) do
    GenServer.call(service_name(namespace), {:release_lock, lock_id})
  rescue
    error -> {:error, coordination_service_error("release_lock failed", error)}
  end

  @doc """
  Elect a leader from a group of candidate agents.

  Performs leader election based on agent health, capabilities, and
  current load. Returns the elected leader agent ID.

  ## Examples

      # Elect coordinator from available agents
      {:ok, leader_id} = CoordinationService.elect_leader([
        :agent_1, :agent_2, :agent_3
      ])
  """
  @spec elect_leader([agent_id()], atom()) :: {:ok, agent_id()} | {:error, Error.t()}
  def elect_leader(candidates, namespace \\ :foundation) do
    GenServer.call(service_name(namespace), {:elect_leader, candidates})
  rescue
    error -> {:error, coordination_service_error("elect_leader failed", error)}
  end

  @doc """
  Get coordination service statistics and health information.

  Returns comprehensive statistics about coordination operations,
  active locks, barriers, and service health.
  """
  @spec get_service_stats(atom()) :: {:ok, service_stats()} | {:error, Error.t()}
  def get_service_stats(namespace \\ :foundation) do
    GenServer.call(service_name(namespace), :get_service_stats)
  rescue
    error -> {:error, coordination_service_error("get_service_stats failed", error)}
  end

  @doc """
  Check if the coordination service is healthy and operational.
  """
  @spec health_check(atom()) :: :ok | {:error, Error.t()}
  def health_check(namespace \\ :foundation) do
    GenServer.call(service_name(namespace), :health_check)
  rescue
    error -> {:error, coordination_service_error("health_check failed", error)}
  end

  # GenServer Implementation

  @impl GenServer
  def init(options) do
    namespace = Keyword.get(options, :namespace, :foundation)
    health_check_interval = Keyword.get(options, :health_check_interval, @default_health_check_interval)
    operation_timeout = Keyword.get(options, :operation_timeout, @default_operation_timeout)

    # Create ETS table for tracking active operations
    active_operations = :ets.new(:coordination_operations, [
      :set, :private, {:write_concurrency, true}, {:read_concurrency, true}
    ])

    state = %__MODULE__{
      namespace: namespace,
      health_check_interval: health_check_interval,
      operation_timeout: operation_timeout,
      coordination_stats: initialize_stats(),
      active_operations: active_operations,
      service_start_time: DateTime.utc_now()
    }

    # Initialize coordination primitives
    case Primitives.initialize_infrastructure() do
      :ok ->
        # Register with ProcessRegistry
        case ProcessRegistry.register(namespace, __MODULE__, self(), %{
          type: :coordination_service,
          health: :healthy,
          operations_supported: [:consensus, :barrier, :lock, :election]
        }) do
          :ok ->
            # Schedule periodic health checks
            schedule_health_check(health_check_interval)

            Telemetry.emit_counter(
              [:foundation, :coordination, :service_started],
              %{namespace: namespace}
            )

            {:ok, state}

          {:error, reason} ->
            {:stop, {:registration_failed, reason}}
        end

      {:error, reason} ->
        {:stop, {:primitives_init_failed, reason}}
    end
  end

  @impl GenServer
  def handle_call({:consensus, coordination_id, participants, proposal, options}, from, state) do
    operation_id = generate_operation_id()

    # Track the operation
    operation_info = %{
      id: operation_id,
      type: :consensus,
      coordination_id: coordination_id,
      participants: participants,
      from: from,
      started_at: DateTime.utc_now()
    }

    :ets.insert(state.active_operations, {operation_id, operation_info})

    # Perform consensus asynchronously
    task = Task.async(fn ->
      result = Primitives.consensus(coordination_id, participants, proposal, options)
      {operation_id, result}
    end)

    # Store task reference for cleanup
    :ets.update_element(state.active_operations, operation_id, {7, task})

    new_stats = increment_stat(state.coordination_stats, :consensus_operations)
    new_state = %{state | coordination_stats: new_stats}

    {:noreply, new_state}
  end

  @impl GenServer
  def handle_call({:create_barrier, barrier_id, participants}, _from, state) do
    result = Primitives.create_barrier(barrier_id, participants)

    emit_coordination_telemetry(:barrier_created, %{
      barrier_id: barrier_id,
      participant_count: length(participants)
    })

    new_stats = increment_stat(state.coordination_stats, :barrier_operations)
    new_state = %{state | coordination_stats: new_stats}

    {:reply, result, new_state}
  end

  @impl GenServer
  def handle_call({:wait_for_barrier, barrier_id, agent_id}, _from, state) do
    result = Primitives.wait_for_barrier(barrier_id, agent_id)

    case result do
      :ok ->
        emit_coordination_telemetry(:barrier_satisfied, %{
          barrier_id: barrier_id,
          agent_id: agent_id
        })

      {:error, _} ->
        emit_coordination_telemetry(:barrier_timeout, %{
          barrier_id: barrier_id,
          agent_id: agent_id
        })
    end

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:acquire_lock, resource_id, agent_id}, _from, state) do
    result = Primitives.acquire_lock(resource_id, agent_id)

    case result do
      {:ok, lock_id} ->
        emit_coordination_telemetry(:lock_acquired, %{
          resource_id: resource_id,
          agent_id: agent_id,
          lock_id: lock_id
        })

        new_stats = increment_stat(state.coordination_stats, :lock_operations)
        new_state = %{state | coordination_stats: new_stats}
        {:reply, result, new_state}

      {:error, _} ->
        emit_coordination_telemetry(:lock_failed, %{
          resource_id: resource_id,
          agent_id: agent_id
        })

        {:reply, result, state}
    end
  end

  @impl GenServer
  def handle_call({:release_lock, lock_id}, _from, state) do
    result = Primitives.release_lock(lock_id)

    emit_coordination_telemetry(:lock_released, %{lock_id: lock_id})

    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:elect_leader, candidates}, _from, state) do
    result = Primitives.elect_leader(candidates)

    case result do
      {:ok, leader_id} ->
        emit_coordination_telemetry(:leader_elected, %{
          leader_id: leader_id,
          candidate_count: length(candidates)
        })

        new_stats = increment_stat(state.coordination_stats, :election_operations)
        new_state = %{state | coordination_stats: new_stats}
        {:reply, result, new_state}

      {:error, _} ->
        emit_coordination_telemetry(:election_failed, %{
          candidate_count: length(candidates)
        })

        {:reply, result, state}
    end
  end

  @impl GenServer
  def handle_call(:get_service_stats, _from, state) do
    stats = build_service_stats(state)
    {:reply, {:ok, stats}, state}
  end

  @impl GenServer
  def handle_call(:health_check, _from, state) do
    health_result = perform_health_check(state)
    {:reply, health_result, state}
  end

  @impl GenServer
  def handle_info({ref, {operation_id, result}}, state) when is_reference(ref) do
    # Handle async consensus result
    case :ets.lookup(state.active_operations, operation_id) do
      [{^operation_id, operation_info}] ->
        GenServer.reply(operation_info.from, result)
        :ets.delete(state.active_operations, operation_id)

        # Emit telemetry
        emit_coordination_telemetry(:consensus_completed, %{
          coordination_id: operation_info.coordination_id,
          participant_count: length(operation_info.participants),
          duration: DateTime.diff(DateTime.utc_now(), operation_info.started_at, :millisecond)
        })

      [] ->
        # Operation already cleaned up
        :ok
    end

    # Clean up the task
    Process.demonitor(ref, [:flush])

    {:noreply, state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    # Handle task process termination
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:health_check, state) do
    # Perform periodic health check
    health_result = perform_health_check(state)

    case health_result do
      :ok ->
        emit_coordination_telemetry(:health_check_passed, %{})

      {:error, _} ->
        emit_coordination_telemetry(:health_check_failed, %{})
    end

    schedule_health_check(state.health_check_interval)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_message, state) do
    {:noreply, state}
  end

  # Private Implementation

  defp initialize_stats do
    %{
      consensus_operations: 0,
      barrier_operations: 0,
      lock_operations: 0,
      election_operations: 0
    }
  end

  defp increment_stat(stats, stat_name) do
    Map.update(stats, stat_name, 1, &(&1 + 1))
  end

  defp build_service_stats(state) do
    active_operations_count = :ets.info(state.active_operations, :size)
    uptime_seconds = DateTime.diff(DateTime.utc_now(), state.service_start_time, :second)

    # Get current coordination primitive states
    active_locks = Primitives.get_active_locks_count()
    active_barriers = Primitives.get_active_barriers_count()

    Map.merge(state.coordination_stats, %{
      active_operations: active_operations_count,
      active_locks: active_locks,
      active_barriers: active_barriers,
      uptime: uptime_seconds,
      service_start_time: state.service_start_time
    })
  end

  defp perform_health_check(state) do
    try do
      # Check if coordination primitives are responding
      case Primitives.health_check() do
        :ok ->
          # Check if we have reasonable performance
          active_ops = :ets.info(state.active_operations, :size)

          if active_ops < 100 do  # Reasonable operation count
            :ok
          else
            {:error, coordination_service_error("too many active operations", %{active_ops: active_ops})}
          end

        {:error, _} = error ->
          error
      end
    rescue
      error ->
        {:error, coordination_service_error("health check exception", error)}
    end
  end

  defp get_operation_timeout(options) do
    Map.get(options, :timeout, @default_operation_timeout) + 5_000  # Add buffer for service overhead
  end

  defp generate_operation_id do
    :crypto.strong_rand_bytes(8)
    |> Base.url_encode64(padding: false)
  end

  defp schedule_health_check(interval) do
    Process.send_after(self(), :health_check, interval)
  end

  defp emit_coordination_telemetry(event_type, metadata) do
    Telemetry.emit_coordination_event(event_type, metadata)
  end

  defp service_name(namespace) do
    :"Foundation.Coordination.Service.#{namespace}"
  end

  # Error Helper Functions

  defp coordination_service_error(message, error) do
    Error.new(
      code: 4101,
      error_type: :coordination_service_error,
      message: "Coordination service error: #{message}",
      severity: :medium,
      context: %{error: error}
    )
  end
end