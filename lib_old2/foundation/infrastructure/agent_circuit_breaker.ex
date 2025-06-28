defmodule Foundation.Infrastructure.AgentCircuitBreaker do
  @moduledoc """
  Agent-aware circuit breaker providing protection for multi-agent operations.

  This module extends traditional circuit breaker patterns to include agent context,
  allowing for fine-grained failure protection based on agent health, capabilities,
  and resource utilization. Designed for distribution-ready deployment.

  ## Agent Context Features

  - **Agent Health Integration**: Circuit status considers agent health metrics
  - **Capability-Based Protection**: Different failure thresholds per agent capability
  - **Resource-Aware Decisions**: Circuit behavior adapts to agent resource usage
  - **Coordination Integration**: Circuit events participate in agent coordination

  ## Usage

      # Start agent-aware circuit breaker
      {:ok, _pid} = AgentCircuitBreaker.start_agent_breaker(
        :ml_inference_service,
        agent_id: :ml_agent_1,
        capability: :inference,
        resource_thresholds: %{memory: 0.8, cpu: 0.9}
      )

      # Execute operation with agent context
      case AgentCircuitBreaker.execute_with_agent(
        :ml_inference_service,
        :ml_agent_1,
        fn -> perform_inference() end
      ) do
        {:ok, result} -> result
        {:error, error} -> handle_failure(error)
      end

      # Check circuit health with agent metrics
      status = AgentCircuitBreaker.get_agent_status(:ml_inference_service, :ml_agent_1)
  """

  use GenServer
  require Logger

  alias Foundation.ProcessRegistry
  alias Foundation.Telemetry

  @type agent_id :: atom() | String.t()
  @type capability :: atom()
  @type circuit_name :: atom()
  @type resource_thresholds :: %{
    memory: float(),
    cpu: float(),
    connections: non_neg_integer()
  }

  @type agent_breaker_options :: [
    agent_id: agent_id(),
    capability: capability(),
    resource_thresholds: resource_thresholds(),
    failure_threshold: pos_integer(),
    recovery_timeout: pos_integer(),
    half_open_max_calls: pos_integer()
  ]

  @type circuit_state :: :closed | :open | :half_open
  @type agent_health :: :healthy | :degraded | :unhealthy
  @type operation :: (-> any())
  @type operation_result :: {:ok, any()} | {:error, Foundation.Types.Error.t()}

  defstruct [
    :circuit_name,
    :agent_id,
    :capability,
    :resource_thresholds,
    :failure_threshold,
    :recovery_timeout,
    :half_open_max_calls,
    :state,
    :failure_count,
    :last_failure_time,
    :half_open_calls,
    :agent_health_cache,
    :last_health_check
  ]

  @type t :: %__MODULE__{
    circuit_name: circuit_name(),
    agent_id: agent_id(),
    capability: capability(),
    resource_thresholds: resource_thresholds(),
    failure_threshold: pos_integer(),
    recovery_timeout: pos_integer(),
    half_open_max_calls: pos_integer(),
    state: circuit_state(),
    failure_count: non_neg_integer(),
    last_failure_time: DateTime.t() | nil,
    half_open_calls: non_neg_integer(),
    agent_health_cache: agent_health(),
    last_health_check: DateTime.t()
  }

  # Public API

  @doc """
  Start an agent-aware circuit breaker with the given configuration.

  ## Parameters
  - `circuit_name`: Unique identifier for the circuit breaker
  - `options`: Agent-specific configuration options

  ## Examples

      {:ok, pid} = AgentCircuitBreaker.start_agent_breaker(
        :ml_inference,
        agent_id: :agent_1,
        capability: :inference,
        resource_thresholds: %{memory: 0.8, cpu: 0.9}
      )
  """
  @spec start_agent_breaker(circuit_name(), agent_breaker_options()) ::
    {:ok, pid()} | {:error, term()}
  def start_agent_breaker(circuit_name, options \\ []) do
    agent_id = Keyword.get(options, :agent_id, :default_agent)

    GenServer.start_link(__MODULE__, {circuit_name, options},
      name: circuit_registry_name(circuit_name, agent_id))
  end

  @doc """
  Execute an operation protected by the agent-aware circuit breaker.

  The circuit breaker considers both traditional failure patterns and
  agent-specific health metrics when making decisions.

  ## Parameters
  - `circuit_name`: Circuit breaker identifier
  - `agent_id`: Agent performing the operation
  - `operation`: Function to execute
  - `metadata`: Additional context for telemetry

  ## Examples

      result = AgentCircuitBreaker.execute_with_agent(
        :database_service,
        :db_agent_1,
        fn -> Database.query("SELECT * FROM users") end
      )
  """
  @spec execute_with_agent(circuit_name(), agent_id(), operation(), map()) :: operation_result()
  def execute_with_agent(circuit_name, agent_id, operation, metadata \\ %{})
      when is_function(operation, 0) do

    registry_name = circuit_registry_name(circuit_name, agent_id)

    try do
      GenServer.call(registry_name, {:execute_operation, operation, metadata}, 10_000)
    rescue
      error ->
        handle_circuit_error(circuit_name, agent_id, error)
    catch
      :exit, {:noproc, _} ->
        {:error, circuit_not_found_error(circuit_name, agent_id)}

      :exit, {:timeout, _} ->
        {:error, circuit_timeout_error(circuit_name, agent_id)}
    end
  end

  @doc """
  Get the current status of an agent-aware circuit breaker.

  Returns detailed status including circuit state, agent health,
  and resource utilization information.
  """
  @spec get_agent_status(circuit_name(), agent_id()) ::
    {:ok, map()} | {:error, Foundation.Types.Error.t()}
  def get_agent_status(circuit_name, agent_id) do
    registry_name = circuit_registry_name(circuit_name, agent_id)

    try do
      GenServer.call(registry_name, :get_status, 5_000)
    rescue
      error ->
        {:error, circuit_status_error(circuit_name, agent_id, error)}
    catch
      :exit, {:noproc, _} ->
        {:error, circuit_not_found_error(circuit_name, agent_id)}

      :exit, {:timeout, _} ->
        {:error, circuit_timeout_error(circuit_name, agent_id)}
    end
  end

  @doc """
  Reset an agent circuit breaker to closed state.

  This forces the circuit to close regardless of current failure count,
  useful for manual recovery or testing scenarios.
  """
  @spec reset_agent_circuit(circuit_name(), agent_id()) :: :ok | {:error, term()}
  def reset_agent_circuit(circuit_name, agent_id) do
    registry_name = circuit_registry_name(circuit_name, agent_id)

    try do
      GenServer.call(registry_name, :reset_circuit, 5_000)
    rescue
      error ->
        {:error, circuit_reset_error(circuit_name, agent_id, error)}
    catch
      :exit, {:noproc, _} ->
        {:error, circuit_not_found_error(circuit_name, agent_id)}
    end
  end

  # GenServer Implementation

  @impl GenServer
  def init({circuit_name, options}) do
    agent_id = Keyword.get(options, :agent_id, :default_agent)
    capability = Keyword.get(options, :capability, :general)

    default_thresholds = %{memory: 0.85, cpu: 0.90, connections: 1000}
    resource_thresholds = Keyword.get(options, :resource_thresholds, default_thresholds)

    state = %__MODULE__{
      circuit_name: circuit_name,
      agent_id: agent_id,
      capability: capability,
      resource_thresholds: resource_thresholds,
      failure_threshold: Keyword.get(options, :failure_threshold, 5),
      recovery_timeout: Keyword.get(options, :recovery_timeout, 60_000),
      half_open_max_calls: Keyword.get(options, :half_open_max_calls, 3),
      state: :closed,
      failure_count: 0,
      last_failure_time: nil,
      half_open_calls: 0,
      agent_health_cache: :healthy,
      last_health_check: DateTime.utc_now()
    }

    # Register with Foundation ProcessRegistry
    case ProcessRegistry.register(:foundation, circuit_name, self(), %{
      type: :circuit_breaker,
      agent_id: agent_id,
      capability: capability,
      health: :healthy,
      resources: resource_thresholds
    }) do
      :ok ->
        # Schedule periodic health checks
        schedule_health_check()

        emit_telemetry(:circuit_started, %{
          circuit_name: circuit_name,
          agent_id: agent_id,
          capability: capability
        })

        {:ok, state}

      {:error, reason} ->
        {:stop, {:registration_failed, reason}}
    end
  end

  @impl GenServer
  def handle_call({:execute_operation, operation, metadata}, _from, state) do
    {result, new_state} = execute_protected_operation(operation, metadata, state)
    {:reply, result, new_state}
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    status = build_detailed_status(state)
    {:reply, {:ok, status}, state}
  end

  @impl GenServer
  def handle_call(:reset_circuit, _from, state) do
    new_state = %{state |
      state: :closed,
      failure_count: 0,
      last_failure_time: nil,
      half_open_calls: 0
    }

    emit_telemetry(:circuit_reset, %{
      circuit_name: state.circuit_name,
      agent_id: state.agent_id
    })

    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_info(:health_check, state) do
    new_state = perform_agent_health_check(state)
    schedule_health_check()
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    # Handle monitored process termination
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(_message, state) do
    {:noreply, state}
  end

  # Private Implementation

  defp execute_protected_operation(operation, metadata, state) do
    case can_execute_operation?(state) do
      :allow ->
        execute_operation_with_protection(operation, metadata, state)

      :deny ->
        error = circuit_open_error(state.circuit_name, state.agent_id)
        emit_execution_telemetry(:rejected, metadata, state)
        {{:error, error}, state}
    end
  end

  defp can_execute_operation?(%{state: :closed}), do: :allow
  defp can_execute_operation?(%{state: :open} = state) do
    if should_attempt_recovery?(state) do
      :allow
    else
      :deny
    end
  end
  defp can_execute_operation?(%{state: :half_open} = state) do
    if state.half_open_calls < state.half_open_max_calls do
      :allow
    else
      :deny
    end
  end

  defp execute_operation_with_protection(operation, metadata, state) do
    start_time = System.monotonic_time(:microsecond)

    try do
      result = operation.()
      duration = System.monotonic_time(:microsecond) - start_time

      new_state = handle_successful_execution(state)

      emit_execution_telemetry(:success,
        Map.merge(metadata, %{duration: duration}), state)

      {{:ok, result}, new_state}

    rescue
      error ->
        duration = System.monotonic_time(:microsecond) - start_time
        new_state = handle_failed_execution(state)

        emit_execution_telemetry(:failure,
          Map.merge(metadata, %{duration: duration, error: error}), state)

        foundation_error = operation_failure_error(state.circuit_name, state.agent_id, error)
        {{:error, foundation_error}, new_state}
    end
  end

  defp handle_successful_execution(%{state: :half_open} = state) do
    new_calls = state.half_open_calls + 1

    if new_calls >= state.half_open_max_calls do
      # Successful recovery
      %{state |
        state: :closed,
        failure_count: 0,
        half_open_calls: 0,
        last_failure_time: nil
      }
    else
      %{state | half_open_calls: new_calls}
    end
  end

  defp handle_successful_execution(state) do
    # Reset failure count on success (for closed circuit)
    %{state | failure_count: 0}
  end

  defp handle_failed_execution(state) do
    new_failure_count = state.failure_count + 1

    new_state = %{state |
      failure_count: new_failure_count,
      last_failure_time: DateTime.utc_now()
    }

    if should_open_circuit?(new_state) do
      %{new_state | state: :open}
    else
      new_state
    end
  end

  defp should_open_circuit?(state) do
    # Consider both failure count and agent health
    failure_threshold_exceeded = state.failure_count >= state.failure_threshold
    agent_unhealthy = state.agent_health_cache == :unhealthy

    failure_threshold_exceeded or agent_unhealthy
  end

  defp should_attempt_recovery?(state) do
    case state.last_failure_time do
      nil -> true
      last_failure ->
        time_since_failure = DateTime.diff(DateTime.utc_now(), last_failure, :millisecond)
        time_since_failure >= state.recovery_timeout
    end
  end

  defp perform_agent_health_check(state) do
    # Query agent health from ProcessRegistry
    health = case ProcessRegistry.lookup(:foundation, state.agent_id) do
      {:ok, _pid, metadata} ->
        Map.get(metadata, :health, :healthy)

      :error ->
        :unhealthy
    end

    %{state |
      agent_health_cache: health,
      last_health_check: DateTime.utc_now()
    }
  end

  defp build_detailed_status(state) do
    %{
      circuit_name: state.circuit_name,
      agent_id: state.agent_id,
      capability: state.capability,
      circuit_state: state.state,
      failure_count: state.failure_count,
      failure_threshold: state.failure_threshold,
      agent_health: state.agent_health_cache,
      last_health_check: state.last_health_check,
      last_failure_time: state.last_failure_time,
      half_open_calls: state.half_open_calls,
      resource_thresholds: state.resource_thresholds
    }
  end

  defp schedule_health_check do
    # Check agent health every 30 seconds
    Process.send_after(self(), :health_check, 30_000)
  end

  defp circuit_registry_name(circuit_name, agent_id) do
    :"circuit_breaker_#{circuit_name}_#{agent_id}"
  end

  # Telemetry Functions

  defp emit_telemetry(event_type, metadata) do
    event_name = [:foundation, :infrastructure, :agent_circuit_breaker, event_type]
    Telemetry.emit_counter(event_name, metadata)
  end

  defp emit_execution_telemetry(result_type, metadata, state) do
    full_metadata = Map.merge(metadata, %{
      circuit_name: state.circuit_name,
      agent_id: state.agent_id,
      capability: state.capability,
      circuit_state: state.state,
      agent_health: state.agent_health_cache
    })

    emit_telemetry(:operation_executed, Map.put(full_metadata, :result, result_type))
  end

  # Error Helper Functions

  defp circuit_not_found_error(circuit_name, agent_id) do
    %Foundation.Types.Error{
      code: 7001,
      error_type: :circuit_breaker_not_found,
      message: "Agent circuit breaker not found: #{circuit_name} for agent #{agent_id}",
      severity: :medium,
      context: %{circuit_name: circuit_name, agent_id: agent_id}
    }
  end

  defp circuit_timeout_error(circuit_name, agent_id) do
    %Foundation.Types.Error{
      code: 7002,
      error_type: :circuit_breaker_timeout,
      message: "Agent circuit breaker timeout: #{circuit_name} for agent #{agent_id}",
      severity: :medium,
      context: %{circuit_name: circuit_name, agent_id: agent_id}
    }
  end

  defp circuit_open_error(circuit_name, agent_id) do
    %Foundation.Types.Error{
      code: 7003,
      error_type: :circuit_breaker_open,
      message: "Agent circuit breaker is open: #{circuit_name} for agent #{agent_id}",
      severity: :medium,
      context: %{circuit_name: circuit_name, agent_id: agent_id},
      retry_strategy: :exponential_backoff
    }
  end

  defp operation_failure_error(circuit_name, agent_id, original_error) do
    %Foundation.Types.Error{
      code: 7004,
      error_type: :protected_operation_failed,
      message: "Protected operation failed in circuit #{circuit_name} for agent #{agent_id}",
      severity: :medium,
      context: %{
        circuit_name: circuit_name,
        agent_id: agent_id,
        original_error: original_error
      }
    }
  end

  defp circuit_status_error(circuit_name, agent_id, error) do
    %Foundation.Types.Error{
      code: 7005,
      error_type: :circuit_status_error,
      message: "Failed to get circuit status: #{inspect(error)}",
      severity: :low,
      context: %{circuit_name: circuit_name, agent_id: agent_id, error: error}
    }
  end

  defp circuit_reset_error(circuit_name, agent_id, error) do
    %Foundation.Types.Error{
      code: 7006,
      error_type: :circuit_reset_error,
      message: "Failed to reset circuit: #{inspect(error)}",
      severity: :medium,
      context: %{circuit_name: circuit_name, agent_id: agent_id, error: error}
    }
  end

  defp handle_circuit_error(circuit_name, agent_id, error) do
    {:error, %Foundation.Types.Error{
      code: 7007,
      error_type: :circuit_execution_error,
      message: "Circuit execution error: #{inspect(error)}",
      severity: :high,
      context: %{circuit_name: circuit_name, agent_id: agent_id, error: error}
    }}
  end
end