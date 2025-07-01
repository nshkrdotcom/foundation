defmodule JidoSystem.Agents.StateSupervisor do
  @moduledoc """
  Supervisor that owns ETS tables for agent state persistence.
  
  This ensures that ETS tables survive agent crashes and provides
  a stable owner process for the tables.
  """
  
  use Supervisor
  
  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    # Initialize ETS tables
    JidoSystem.Agents.StatePersistence.init_tables()
    
    # We don't need any child processes, just a stable supervisor
    # to own the ETS tables
    children = []
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end