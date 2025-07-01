defmodule MABEAM.AgentRegistry.API do
  @moduledoc """
  Public API for agent registry operations.

  This module provides the recommended interface for interacting with the agent registry.
  Read operations use direct ETS access for maximum performance, while write operations
  go through the GenServer for consistency.

  ## Performance Characteristics

  - Read operations: Lock-free, O(1) or O(log n) depending on query
  - Write operations: Serialized through GenServer, ~100-500μs latency

  ## Usage

      # Initialize reader with table names (do this once)
      {:ok, tables} = MABEAM.AgentRegistry.API.init_reader()
      
      # Fast read operations
      {:ok, {pid, metadata}} = MABEAM.AgentRegistry.API.lookup(tables, agent_id)
      {:ok, agents} = MABEAM.AgentRegistry.API.find_by_capability(tables, :inference)
      
      # Write operations
      :ok = MABEAM.AgentRegistry.API.register(agent_id, self(), metadata)
      :ok = MABEAM.AgentRegistry.API.update_metadata(agent_id, new_metadata)
  """

  alias MABEAM.AgentRegistry
  alias MABEAM.AgentRegistry.Reader

  # Read Operations - Direct ETS Access

  @doc """
  Initializes a reader by getting table names from the registry.

  Call this once and cache the result for subsequent read operations.
  """
  @spec init_reader(GenServer.server()) :: {:ok, map()} | {:error, term()}
  def init_reader(registry \\ AgentRegistry) do
    Reader.get_table_names(registry)
  end

  @doc """
  Looks up an agent by ID using direct ETS access.
  """
  @spec lookup(map(), any()) :: {:ok, {pid(), map()}} | :error
  defdelegate lookup(tables, agent_id), to: Reader

  @doc """
  Finds agents by capability using direct ETS access.
  """
  @spec find_by_capability(map(), atom()) :: {:ok, list()}
  def find_by_capability(tables, capability) do
    Reader.find_by_attribute(tables, :capability, capability)
  end

  @doc """
  Finds agents by health status using direct ETS access.
  """
  @spec find_by_health_status(map(), atom()) :: {:ok, list()}
  def find_by_health_status(tables, status) do
    Reader.find_by_attribute(tables, :health_status, status)
  end

  @doc """
  Finds agents by node using direct ETS access.
  """
  @spec find_by_node(map(), node()) :: {:ok, list()}
  def find_by_node(tables, node) do
    Reader.find_by_attribute(tables, :node, node)
  end

  @doc """
  Lists all agents with optional filtering using direct ETS access.
  """
  @spec list_all(map(), nil | (map() -> boolean())) :: list()
  defdelegate list_all(tables, filter_fn \\ nil), to: Reader

  @doc """
  Queries agents with complex criteria using direct ETS access.
  """
  @spec query(map(), list()) ::
          {:ok, list()}
          | {:error,
             {:invalid_criteria, :criteria_must_be_list | binary() | {:invalid_criterion, term()}}}
  defdelegate query(tables, criteria), to: Reader

  @doc """
  Counts registered agents using direct ETS access.
  """
  @spec count(map()) :: {:ok, non_neg_integer()}
  defdelegate count(tables), to: Reader

  # Write Operations - Through GenServer

  @doc """
  Registers a new agent.

  Goes through GenServer for consistency and atomicity.
  """
  @spec register(any(), pid(), map(), GenServer.server()) ::
          :ok | {:error, term()}
  def register(agent_id, pid, metadata, registry \\ AgentRegistry) do
    GenServer.call(registry, {:register, agent_id, pid, metadata})
  end

  @doc """
  Unregisters an agent.
  """
  @spec unregister(any(), GenServer.server()) ::
          :ok | {:error, :not_found}
  def unregister(agent_id, registry \\ AgentRegistry) do
    GenServer.call(registry, {:unregister, agent_id})
  end

  @doc """
  Updates agent metadata.
  """
  @spec update_metadata(any(), map(), GenServer.server()) ::
          :ok | {:error, term()}
  def update_metadata(agent_id, new_metadata, registry \\ AgentRegistry) do
    GenServer.call(registry, {:update_metadata, agent_id, new_metadata})
  end

  @doc """
  Performs atomic transaction with multiple operations.
  """
  @spec atomic_transaction(list(), any(), GenServer.server()) ::
          {:ok, list()} | {:error, term(), list()}
  def atomic_transaction(operations, tx_id, registry \\ AgentRegistry) do
    GenServer.call(registry, {:atomic_transaction, operations, tx_id})
  end

  @doc """
  Batch registers multiple agents.
  """
  @spec batch_register(list(), GenServer.server()) ::
          {:ok, list()} | {:error, term(), list()}
  def batch_register(agents, registry \\ AgentRegistry) when is_list(agents) do
    GenServer.call(registry, {:batch_register, agents})
  end
end
