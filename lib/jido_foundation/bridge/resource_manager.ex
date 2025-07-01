defmodule JidoFoundation.Bridge.ResourceManager do
  @moduledoc """
  Manages resource acquisition and release for Jido agents within Foundation.

  This module provides a simple interface to Foundation's ResourceManager
  for Jido agents to safely acquire and release resources.
  """

  @doc """
  Acquires a resource token before executing a Jido action.

  ## Examples

      with {:ok, token} <- acquire(:heavy_computation, %{agent: agent_pid}),
           {:ok, result} <- execute_action(agent_pid, :compute, params),
           :ok <- release(token) do
        {:ok, result}
      end
  """
  def acquire(resource_type, metadata \\ %{}) do
    Foundation.ResourceManager.acquire_resource(resource_type, metadata)
  end

  @doc """
  Releases a previously acquired resource token.
  """
  def release(token) do
    Foundation.ResourceManager.release_resource(token)
  end
end
