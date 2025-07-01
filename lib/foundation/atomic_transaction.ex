defmodule Foundation.AtomicTransaction do
  @moduledoc """
  DEPRECATED: Use Foundation.SerialOperations instead.

  This module has been renamed to better reflect its actual behavior.
  It provides serial execution, NOT atomic transactions.
  """

  @deprecated "Use Foundation.SerialOperations instead"

  # Delegate all functions to the new module
  defdelegate transact(fun), to: Foundation.SerialOperations
  defdelegate transact(registry_pid, fun), to: Foundation.SerialOperations

  # Transaction operations need delegation too
  defdelegate register_agent(tx, agent_id, pid, metadata), to: Foundation.SerialOperations
  defdelegate update_metadata(tx, agent_id, metadata), to: Foundation.SerialOperations
  defdelegate unregister(tx, agent_id), to: Foundation.SerialOperations
end
