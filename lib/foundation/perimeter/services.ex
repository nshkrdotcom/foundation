defmodule Foundation.Perimeter.Services do
  @moduledoc """
  Internal service validation contracts for Foundation.
  Uses light validation for trusted internal services.
  """

  def coordinate_agents(params) do
    Foundation.Perimeter.validate_internal(params, %{
      agent_group: :list,
      coordination_pattern: :atom,
      coordination_config: :map,
      timeout_ms: :integer
    })
  end

  def process_task(params) do
    Foundation.Perimeter.validate_internal(params, %{
      task_id: :string,
      task_type: :atom,
      payload: :map,
      priority: :atom
    })
  end

  def route_signal(signal) do
    Foundation.Perimeter.validate_trusted(signal, :any)
  end

  def register_agent(params) do
    Foundation.Perimeter.validate_internal(params, %{
      agent_id: :string,
      capabilities: :list,
      node: :atom
    })
  end

  def update_clustering_config(params) do
    Foundation.Perimeter.validate_internal(params, %{
      cluster_id: :string,
      config: :map,
      version: :integer
    })
  end
end