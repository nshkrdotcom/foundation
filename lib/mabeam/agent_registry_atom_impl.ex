defimpl Foundation.Registry, for: Atom do
  @moduledoc """
  Foundation.Registry protocol implementation for Atom (module names).
  
  This allows using MABEAM.AgentRegistry as a module name in Foundation calls.
  The implementation will call the module's functions directly.
  """
  
  defp is_agent_registry?(module_or_name) do
    # Check if it's the MABEAM.AgentRegistry module or a named process
    case module_or_name do
      MABEAM.AgentRegistry -> true
      name when is_atom(name) ->
        # Check if it's a registered process that implements AgentRegistry behavior
        case Process.whereis(name) do
          nil -> false
          pid when is_pid(pid) -> 
            # For test purposes, assume named processes are AgentRegistry instances
            # In production, you might want more sophisticated checking
            true
        end
      _ -> false
    end
  end
  
  def register(module, key, pid, metadata) do
    if is_agent_registry?(module) do
      GenServer.call(module, {:register, key, pid, metadata})
    else
      {:error, :unsupported_module}
    end
  end
  
  def lookup(module, key) do
    if is_agent_registry?(module) do
      MABEAM.AgentRegistry.lookup(key)
    else
      {:error, :unsupported_module}
    end
  end
  
  def find_by_attribute(module, attribute, value) do
    if is_agent_registry?(module) do
      MABEAM.AgentRegistry.find_by_attribute(attribute, value)
    else
      {:error, :unsupported_module}
    end
  end
  
  def query(module, criteria) do
    if is_agent_registry?(module) do
      MABEAM.AgentRegistry.query(criteria)
    else
      {:error, :unsupported_module}
    end
  end
  
  def indexed_attributes(module) do
    if is_agent_registry?(module) do
      MABEAM.AgentRegistry.indexed_attributes()
    else
      []
    end
  end
  
  def list_all(module, filter) do
    if is_agent_registry?(module) do
      MABEAM.AgentRegistry.list_all(filter)
    else
      []
    end
  end
  
  def update_metadata(module, key, metadata) do
    if is_agent_registry?(module) do
      GenServer.call(module, {:update_metadata, key, metadata})
    else
      {:error, :unsupported_module}
    end
  end
  
  def unregister(module, key) do
    if is_agent_registry?(module) do
      GenServer.call(module, {:unregister, key})
    else
      {:error, :unsupported_module}
    end
  end
end