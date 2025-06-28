defimpl Foundation.Registry, for: MABEAM.AgentRegistry do
  @moduledoc """
  Foundation.Registry protocol implementation for MABEAM.AgentRegistry.
  
  This implementation provides the bridge between the generic Foundation protocols
  and the agent-optimized MABEAM registry, with optimal read/write path separation.
  """
  
  require Logger
  
  # --- Write Operations (Go through GenServer for consistency) ---
  
  def register(registry_pid, agent_id, pid, metadata) do
    GenServer.call(registry_pid, {:register, agent_id, pid, metadata})
  end
  
  def update_metadata(registry_pid, agent_id, new_metadata) do
    GenServer.call(registry_pid, {:update_metadata, agent_id, new_metadata})
  end
  
  def unregister(registry_pid, agent_id) do
    GenServer.call(registry_pid, {:unregister, agent_id})
  end
  
  # --- Read Operations (Bypass GenServer for maximum performance) ---
  
  def lookup(_registry_pid, agent_id) do
    MABEAM.AgentRegistry.lookup(agent_id)
  end
  
  def find_by_attribute(_registry_pid, attribute, value) do
    MABEAM.AgentRegistry.find_by_attribute(attribute, value)
  end
  
  def query(_registry_pid, criteria) do
    MABEAM.AgentRegistry.query(criteria)
  end
  
  def indexed_attributes(_registry_pid) do
    MABEAM.AgentRegistry.indexed_attributes()
  end
  
  def list_all(_registry_pid, filter_fn) do
    MABEAM.AgentRegistry.list_all(filter_fn)
  end
end