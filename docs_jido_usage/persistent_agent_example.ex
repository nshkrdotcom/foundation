defmodule JidoSystem.Agents.PersistentAgentExample do
  @moduledoc """
  Example of implementing state persistence in Jido agents without framework modifications.
  
  This demonstrates how to use the available lifecycle hooks to persist and restore agent state.
  """
  
  use Jido.Agent,
    name: "persistent_agent",
    description: "Example agent with state persistence",
    category: "example",
    schema: [
      counter: [type: :integer, default: 0],
      history: [type: {:list, :string}, default: []],
      last_saved: [type: :string, required: false]
    ]
  
  # Override mount to restore persisted state
  @impl true
  def mount(%{agent: agent} = server_state, _opts) do
    case load_persisted_state(agent.id) do
      {:ok, persisted_state} ->
        # Merge persisted state with agent state
        restored_agent = %{agent | state: Map.merge(agent.state, persisted_state)}
        {:ok, %{server_state | agent: restored_agent}}
      
      {:error, :not_found} ->
        # No persisted state, use defaults
        {:ok, server_state}
      
      {:error, reason} ->
        # Log but don't fail - use defaults
        require Logger
        Logger.warning("Failed to load persisted state: #{inspect(reason)}")
        {:ok, server_state}
    end
  end
  
  # Override shutdown to save state
  @impl true
  def shutdown(%{agent: agent} = server_state, _reason) do
    save_state(agent.id, agent.state)
    {:ok, server_state}
  end
  
  # Hook into state validation to persist on every change
  @impl true
  def on_after_validate_state(agent) do
    # Save state after every successful validation
    save_state(agent.id, agent.state)
    {:ok, agent}
  end
  
  # Alternative: Hook into after_run to save state after actions
  @impl true
  def on_after_run(agent, _result, _metadata) do
    save_state(agent.id, agent.state)
    {:ok, agent}
  end
  
  # Persistence implementation (example using ETS)
  defp save_state(agent_id, state) do
    table_name = persistence_table()
    ensure_table_exists(table_name)
    
    state_with_timestamp = Map.put(state, :last_saved, DateTime.utc_now() |> to_string())
    :ets.insert(table_name, {agent_id, state_with_timestamp})
    :ok
  end
  
  defp load_persisted_state(agent_id) do
    table_name = persistence_table()
    ensure_table_exists(table_name)
    
    case :ets.lookup(table_name, agent_id) do
      [{^agent_id, state}] -> {:ok, state}
      [] -> {:error, :not_found}
    end
  end
  
  defp ensure_table_exists(table_name) do
    case :ets.whereis(table_name) do
      :undefined ->
        :ets.new(table_name, [:set, :public, :named_table])
      _tid ->
        :ok
    end
  end
  
  defp persistence_table do
    :persistent_agent_states
  end
  
  # Example of using initial_state when starting the agent
  def start_with_state(id, saved_state) do
    start_link(id: id, initial_state: saved_state)
  end
end