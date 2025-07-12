defmodule MABEAM.AgentRegistry.IndexManager do
  @moduledoc """
  Manages ETS table indexes for efficient agent lookups.

  Extracted from MABEAM.AgentRegistry to handle all index-related operations.
  Maintains capability, health, node, and resource indexes for fast queries.
  """

  @doc """
  Updates all indexes for an agent with new metadata.

  This function updates the capability, health, node, and resource indexes
  to reflect the agent's current metadata.
  """
  @spec update_all_indexes(map(), any(), map()) :: :ok
  def update_all_indexes(tables, agent_id, metadata) do
    # Capability index (handle both single capability and list)
    capabilities = List.wrap(Map.get(metadata, :capability, []))

    for capability <- capabilities do
      :ets.insert(tables.capability_index, {capability, agent_id})
    end

    # Health index
    health_status = Map.get(metadata, :health_status, :unknown)
    :ets.insert(tables.health_index, {health_status, agent_id})

    # Node index
    node = Map.get(metadata, :node, node())
    :ets.insert(tables.node_index, {node, agent_id})

    # Resource index (ordered by memory usage for efficient range queries)
    resources = Map.get(metadata, :resources, %{})
    memory_usage = Map.get(resources, :memory_usage, 0.0)
    :ets.insert(tables.resource_index, {{memory_usage, agent_id}, agent_id})

    :ok
  end

  @doc """
  Clears all index entries for a specific agent.

  Removes the agent from capability, health, node, and resource indexes.
  Uses efficient match_delete operations.
  """
  @spec clear_agent_from_indexes(map(), any()) :: :ok
  def clear_agent_from_indexes(tables, agent_id) do
    # Use match_delete for efficient cleanup
    :ets.match_delete(tables.capability_index, {:_, agent_id})
    :ets.match_delete(tables.health_index, {:_, agent_id})
    :ets.match_delete(tables.node_index, {:_, agent_id})
    :ets.match_delete(tables.resource_index, {{:_, agent_id}, agent_id})
    :ok
  end

  @doc """
  Creates the ETS tables needed for agent registry indexes.

  Returns a map with all created table references.
  """
  @spec create_index_tables(atom()) :: map()
  def create_index_tables(_registry_id) do
    table_opts = [:public, read_concurrency: true, write_concurrency: true]

    %{
      main_table: :ets.new(:agent_main, [:set | table_opts]),
      capability_index: :ets.new(:agent_capability_idx, [:bag | table_opts]),
      health_index: :ets.new(:agent_health_idx, [:bag | table_opts]),
      node_index: :ets.new(:agent_node_idx, [:bag | table_opts]),
      resource_index: :ets.new(:agent_resource_idx, [:ordered_set | table_opts])
    }
  end

  @doc """
  Registers all tables with ResourceManager if available.
  """
  @spec register_tables_with_resource_manager(map()) :: :ok
  def register_tables_with_resource_manager(tables) do
    if Process.whereis(Foundation.ResourceManager) do
      Enum.each(tables, fn {_name, table} ->
        Foundation.ResourceManager.monitor_table(table)
      end)
    end

    :ok
  end
end
