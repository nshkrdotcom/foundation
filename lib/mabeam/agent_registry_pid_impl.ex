defimpl Foundation.Registry, for: PID do
  @moduledoc """
  Foundation.Registry protocol implementation for PIDs.

  This allows using a registry GenServer PID directly with Foundation functions,
  delegating all operations through GenServer.call.
  """

  def register(registry_pid, agent_id, pid, metadata) do
    GenServer.call(registry_pid, {:register, agent_id, pid, metadata})
  end

  def update_metadata(registry_pid, agent_id, new_metadata) do
    GenServer.call(registry_pid, {:update_metadata, agent_id, new_metadata})
  end

  def unregister(registry_pid, agent_id) do
    GenServer.call(registry_pid, {:unregister, agent_id})
  end

  def lookup(registry_pid, agent_id) do
    GenServer.call(registry_pid, {:lookup, agent_id})
  end

  def find_by_attribute(registry_pid, attribute, value) do
    GenServer.call(registry_pid, {:find_by_attribute, attribute, value})
  end

  def query(registry_pid, criteria) do
    GenServer.call(registry_pid, {:query, criteria})
  end

  def indexed_attributes(registry_pid) do
    GenServer.call(registry_pid, {:indexed_attributes})
  end

  def list_all(registry_pid, filter_fn) do
    GenServer.call(registry_pid, {:list_all, filter_fn})
  end
end
