defmodule JidoSystem.Agents.StatePersistence do
  @moduledoc """
  Provides persistent state storage for agents using ETS tables.
  
  This module ensures that critical agent state survives process crashes
  by maintaining a write-through cache in ETS tables owned by a supervisor.
  """
  
  require Logger
  
  @coordinator_state_table :coordinator_agent_state
  @task_agent_state_table :task_agent_state
  
  @doc """
  Initializes ETS tables for state persistence.
  Should be called from a long-lived supervisor process.
  """
  def init_tables do
    # Create tables if they don't exist
    create_table_if_needed(@coordinator_state_table)
    create_table_if_needed(@task_agent_state_table)
    :ok
  end
  
  @doc """
  Saves coordinator agent state to ETS.
  """
  def save_coordinator_state(agent_id, state_fields) do
    save_state(@coordinator_state_table, agent_id, state_fields)
  end
  
  @doc """
  Loads coordinator agent state from ETS.
  Returns the stored state or empty map if not found.
  """
  def load_coordinator_state(agent_id) do
    load_state(@coordinator_state_table, agent_id, %{
      active_workflows: %{},
      task_queue: :queue.new(),
      agent_pool: %{},
      failure_recovery: %{
        retry_attempts: %{},
        failed_agents: %{},
        recovery_strategies: []
      }
    })
  end
  
  @doc """
  Saves task agent state to ETS.
  """
  def save_task_state(agent_id, state_fields) do
    save_state(@task_agent_state_table, agent_id, state_fields)
  end
  
  @doc """
  Loads task agent state from ETS.
  Returns the stored state or defaults if not found.
  """
  def load_task_state(agent_id) do
    load_state(@task_agent_state_table, agent_id, %{
      task_queue: :queue.new(),
      current_task: nil,
      performance_metrics: %{
        tasks_completed: 0,
        tasks_failed: 0,
        average_execution_time: 0,
        last_task_timestamp: nil
      }
    })
  end
  
  @doc """
  Clears all state for an agent (useful for cleanup).
  """
  def clear_coordinator_state(agent_id) do
    :ets.delete(@coordinator_state_table, agent_id)
  end
  
  def clear_task_state(agent_id) do
    :ets.delete(@task_agent_state_table, agent_id)
  end
  
  # Private functions
  
  defp create_table_if_needed(table_name) do
    case :ets.whereis(table_name) do
      :undefined ->
        :ets.new(table_name, [
          :set,
          :public,
          :named_table,
          {:write_concurrency, true},
          {:read_concurrency, true}
        ])
        Logger.info("Created ETS table #{table_name} for state persistence")
      _tid ->
        # Table already exists
        :ok
    end
  end
  
  defp save_state(table, key, state_fields) do
    # Only save the critical fields that need persistence
    persistent_fields = extract_persistent_fields(state_fields)
    :ets.insert(table, {key, persistent_fields, System.system_time(:second)})
    :ok
  rescue
    error ->
      Logger.error("Failed to save state to ETS: #{inspect(error)}")
      {:error, error}
  end
  
  defp load_state(table, key, defaults) do
    case :ets.lookup(table, key) do
      [{^key, state_data, _timestamp}] ->
        Map.merge(defaults, state_data)
      [] ->
        defaults
    end
  rescue
    error ->
      Logger.error("Failed to load state from ETS: #{inspect(error)}")
      defaults
  end
  
  defp extract_persistent_fields(%{} = state) do
    # Extract only the fields that need persistence
    Map.take(state, [
      :active_workflows,
      :task_queue,
      :agent_pool,
      :failure_recovery,
      :current_task,
      :performance_metrics
    ])
  end
end