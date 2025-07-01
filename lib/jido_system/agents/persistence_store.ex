defmodule JidoSystem.Agents.PersistenceStore do
  @moduledoc """
  A simple GenServer that owns an ETS table for agent state persistence.
  This ensures the table survives when agents crash or restart.
  """
  use GenServer

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def save(agent_id, state, store \\ __MODULE__) do
    GenServer.call(store, {:save, agent_id, state})
  end

  def load(agent_id, store \\ __MODULE__) do
    GenServer.call(store, {:load, agent_id})
  end

  def clear(store \\ __MODULE__) do
    GenServer.call(store, :clear)
  end

  # GenServer callbacks

  @impl true
  def init(opts) do
    table_name = Keyword.get(opts, :table_name, :agent_persistence_store)
    table = :ets.new(table_name, [:set, :public, :named_table])
    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:save, agent_id, state}, _from, %{table: table} = state_map) do
    true = :ets.insert(table, {agent_id, state, DateTime.utc_now()})
    {:reply, :ok, state_map}
  end

  @impl true
  def handle_call({:load, agent_id}, _from, %{table: table} = state) do
    case :ets.lookup(table, agent_id) do
      [{^agent_id, saved_state, _timestamp}] ->
        {:reply, {:ok, saved_state}, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:clear, _from, %{table: table} = state) do
    true = :ets.delete_all_objects(table)
    {:reply, :ok, state}
  end
end
