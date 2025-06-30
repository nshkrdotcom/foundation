defmodule JidoSystem.ErrorStore do
  @moduledoc """
  Persistent error tracking service for JidoSystem agents.

  Provides centralized error persistence and metrics collection,
  separate from business logic state management. This follows
  the separation of concerns principle outlined in SUPERVISION_STRAT_ERROR.md.

  ## Features

  - Persistent error count tracking across agent restarts
  - Error history and analytics
  - Configurable error retention policies
  - Integration with telemetry for monitoring

  ## Usage

      # Record an error for an agent
      JidoSystem.ErrorStore.record_error("agent_123", %{type: :validation_error})

      # Get current error count
      {:ok, count} = JidoSystem.ErrorStore.get_error_count("agent_123")

      # Initialize agent with persistent error count
      count = JidoSystem.ErrorStore.initialize_agent_errors("agent_123")
  """

  use GenServer
  require Logger

  defstruct [
    # %{agent_id => count}
    :error_counts,
    # %{agent_id => [error_records]}
    :error_history,
    # %{max_history: 1000, max_age_hours: 24}
    :retention_policy,
    :cleanup_timer
  ]

  @default_retention %{
    max_history: 1000,
    max_age_hours: 24
  }

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records an error for the specified agent.
  """
  def record_error(agent_id, error) do
    GenServer.cast(__MODULE__, {:record_error, agent_id, error})
  end

  @doc """
  Gets the current error count for an agent.
  """
  def get_error_count(agent_id) do
    GenServer.call(__MODULE__, {:get_error_count, agent_id})
  end

  @doc """
  Initializes error count for a new agent from persistent store.
  """
  def initialize_agent_errors(agent_id) do
    case get_error_count(agent_id) do
      {:ok, count} -> count
      {:error, :not_found} -> 0
    end
  end

  @doc """
  Resets error count for an agent (e.g., after manual intervention).
  """
  def reset_errors(agent_id) do
    GenServer.call(__MODULE__, {:reset_errors, agent_id})
  end

  @doc """
  Gets error history for an agent.
  """
  def get_error_history(agent_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    GenServer.call(__MODULE__, {:get_error_history, agent_id, limit})
  end

  # Server Implementation

  def init(opts) do
    retention_policy = Keyword.get(opts, :retention_policy, @default_retention)
    cleanup_interval = Keyword.get(opts, :cleanup_interval, 60_000)

    state = %__MODULE__{
      error_counts: %{},
      error_history: %{},
      retention_policy: retention_policy,
      cleanup_timer: nil
    }

    # Schedule periodic cleanup
    timer = Process.send_after(self(), :cleanup, cleanup_interval)

    Logger.info("JidoSystem.ErrorStore started with retention policy: #{inspect(retention_policy)}")

    {:ok, %{state | cleanup_timer: timer}}
  end

  def handle_call({:get_error_count, agent_id}, _from, state) do
    count = Map.get(state.error_counts, agent_id, 0)
    result = if count > 0, do: {:ok, count}, else: {:error, :not_found}
    {:reply, result, state}
  end

  def handle_call({:reset_errors, agent_id}, _from, state) do
    new_counts = Map.delete(state.error_counts, agent_id)
    new_history = Map.delete(state.error_history, agent_id)

    new_state = %{state | error_counts: new_counts, error_history: new_history}

    Logger.info("Reset error count for agent #{agent_id}")
    {:reply, :ok, new_state}
  end

  def handle_call({:get_error_history, agent_id, limit}, _from, state) do
    history = Map.get(state.error_history, agent_id, [])
    limited_history = Enum.take(history, limit)
    {:reply, {:ok, limited_history}, state}
  end

  def handle_cast({:record_error, agent_id, error}, state) do
    # Increment error count
    current_count = Map.get(state.error_counts, agent_id, 0)
    new_count = current_count + 1
    new_counts = Map.put(state.error_counts, agent_id, new_count)

    # Add to error history
    error_record = %{
      error: error,
      timestamp: DateTime.utc_now(),
      count: new_count
    }

    current_history = Map.get(state.error_history, agent_id, [])
    new_history_list = [error_record | current_history]

    # Apply retention policy
    max_history = state.retention_policy.max_history
    trimmed_history = Enum.take(new_history_list, max_history)

    new_history = Map.put(state.error_history, agent_id, trimmed_history)

    new_state = %{state | error_counts: new_counts, error_history: new_history}

    # Emit telemetry
    :telemetry.execute(
      [:jido_system, :error_store, :error_recorded],
      %{count: new_count},
      %{agent_id: agent_id, error_type: classify_error(error)}
    )

    {:noreply, new_state}
  end

  def handle_info(:cleanup, state) do
    Logger.debug("JidoSystem.ErrorStore performing cleanup")

    # Clean up old error history based on age
    max_age_ms = state.retention_policy.max_age_hours * 60 * 60 * 1000
    cutoff_time = DateTime.add(DateTime.utc_now(), -max_age_ms, :millisecond)

    new_history =
      Map.new(state.error_history, fn {agent_id, history} ->
        filtered_history =
          Enum.filter(history, fn record ->
            DateTime.compare(record.timestamp, cutoff_time) == :gt
          end)

        {agent_id, filtered_history}
      end)

    # Remove agents with no recent errors
    new_counts =
      Map.filter(state.error_counts, fn {agent_id, _count} ->
        Map.get(new_history, agent_id, []) != []
      end)

    # Schedule next cleanup  
    # 1 minute
    cleanup_interval = 60_000
    timer = Process.send_after(self(), :cleanup, cleanup_interval)

    new_state = %{
      state
      | error_counts: new_counts,
        error_history: new_history,
        cleanup_timer: timer
    }

    {:noreply, new_state}
  end

  # Private helpers

  defp classify_error(error) do
    case error do
      %{type: type} -> type
      %Jido.Error{type: type} -> type
      {:validation_failed, _} -> :validation_error
      {:unsupported_task_type, _} -> :task_error
      _ -> :unknown
    end
  end
end
