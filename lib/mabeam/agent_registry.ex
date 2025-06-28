defmodule MABEAM.AgentRegistry do
  @moduledoc """
  High-performance agent registry with optimized read/write path separation.
  
  ## Concurrency Model
  
  **Read Operations** (`lookup`, `query`, `find_by_attribute`): 
  - Lock-free and perform directly on underlying ETS tables
  - Maximum concurrency with zero GenServer overhead
  - Typical latency: 1-10 microseconds
  
  **Write Operations** (`register`, `update_metadata`, `unregister`):
  - Serialized through GenServer process for consistency
  - Guarantees atomicity of index updates across all tables
  - Typical latency: 100-500 microseconds
  
  ## Scaling Considerations
  
  This implementation is highly safe and performant for most workloads.
  Systems expecting exceptionally high-volume concurrent registrations 
  (>10,000/sec) should consider a sharded registry implementation.
  
  Future versions may explore sharding the registry by `namespace` or 
  `agent_type` to distribute write load across multiple processes.
  
  ## Agent Metadata Schema
  
  All registered agents must have metadata containing:
  - `:capability` - List of capabilities (indexed)
  - `:health_status` - `:healthy`, `:degraded`, or `:unhealthy` (indexed)
  - `:node` - Node where agent is running (indexed)
  - `:resources` - Map with resource usage/availability
  - `:agent_type` - Type of agent (optional, for future sharding)
  """
  
  use GenServer
  require Logger
  
  defstruct [
    main_table: nil,
    capability_index: nil,
    health_index: nil,
    node_index: nil,
    resource_index: nil,
    monitors: nil
  ]
  
  # Required metadata fields for agents
  @required_fields [:capability, :health_status, :node, :resources]
  @valid_health_statuses [:healthy, :degraded, :unhealthy]
  
  # --- OTP Lifecycle ---
  
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end
  
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end
  
  def init(_opts) do
    # Clean up any existing tables from previous test runs
    try do
      :ets.delete(:agent_main)
    rescue
      ArgumentError -> :ok
    end
    
    try do
      :ets.delete(:agent_capability_idx)
    rescue
      ArgumentError -> :ok
    end
    
    try do
      :ets.delete(:agent_health_idx)
    rescue
      ArgumentError -> :ok
    end
    
    try do
      :ets.delete(:agent_node_idx)
    rescue
      ArgumentError -> :ok
    end
    
    try do
      :ets.delete(:agent_resource_idx)
    rescue
      ArgumentError -> :ok
    end
    
    table_opts = [:public, :named_table, read_concurrency: true, write_concurrency: true]
    
    state = %__MODULE__{
      main_table: :ets.new(:agent_main, [:set | table_opts]),
      capability_index: :ets.new(:agent_capability_idx, [:bag | table_opts]),
      health_index: :ets.new(:agent_health_idx, [:bag | table_opts]),
      node_index: :ets.new(:agent_node_idx, [:bag | table_opts]),
      resource_index: :ets.new(:agent_resource_idx, [:ordered_set | table_opts]),
      monitors: %{}
    }
    
    Logger.info("MABEAM.AgentRegistry started with optimized ETS tables")
    
    {:ok, state}
  end
  
  def terminate(_reason, state) do
    Logger.info("MABEAM.AgentRegistry terminating, cleaning up ETS tables")
    
    # Clean up ETS tables
    safe_ets_delete(state.main_table)
    safe_ets_delete(state.capability_index)
    safe_ets_delete(state.health_index) 
    safe_ets_delete(state.node_index)
    safe_ets_delete(state.resource_index)
    :ok
  end
  
  defp safe_ets_delete(table) do
    try do
      :ets.delete(table)
    rescue
      ArgumentError -> :ok  # Table already deleted
    end
  end
  
  # --- Public Read API (Direct ETS Access for Maximum Performance) ---
  
  @doc """
  Looks up an agent by ID. Direct ETS access - no GenServer call.
  """
  def lookup(agent_id) do
    case :ets.lookup(:agent_main, agent_id) do
      [{^agent_id, pid, metadata, _timestamp}] -> {:ok, {pid, metadata}}
      [] -> :error
    end
  end
  
  @doc """
  Finds agents by capability. Direct ETS index lookup - O(1) performance.
  """
  def find_by_capability(capability) do
    agent_ids = :ets.lookup(:agent_capability_idx, capability)
                |> Enum.map(&elem(&1, 1))
    
    batch_lookup_agents(agent_ids)
  end
  
  @doc """
  Finds agents by health status. Direct ETS index lookup - O(1) performance.
  """
  def find_by_health_status(health_status) do
    agent_ids = :ets.lookup(:agent_health_idx, health_status)
                |> Enum.map(&elem(&1, 1))
    
    batch_lookup_agents(agent_ids)
  end
  
  @doc """
  Finds agents by node. Direct ETS index lookup - O(1) performance.
  """
  def find_by_node(node) do
    agent_ids = :ets.lookup(:agent_node_idx, node)
                |> Enum.map(&elem(&1, 1))
    
    batch_lookup_agents(agent_ids)
  end
  
  @doc """
  Generic find by attribute function for protocol compliance.
  """
  def find_by_attribute(:capability, value), do: find_by_capability(value)
  def find_by_attribute(:health_status, value), do: find_by_health_status(value)
  def find_by_attribute(:node, value), do: find_by_node(value)
  def find_by_attribute(attribute, _value) do
    {:error, {:unsupported_attribute, attribute}}
  end
  
  @doc """
  Lists all agents, optionally filtered. Direct ETS scan.
  """
  def list_all(filter_fn \\ nil) do
    :ets.tab2list(:agent_main)
    |> Enum.map(fn {id, pid, metadata, _timestamp} -> {id, pid, metadata} end)
    |> apply_filter(filter_fn)
  end
  
  @doc """
  Returns indexed attributes for this implementation.
  """
  def indexed_attributes do
    [:capability, :health_status, :node]
  end
  
  @doc """
  Returns protocol version for compatibility checking.
  """
  def protocol_version do
    "1.1"
  end
  
  @doc """
  Performs atomic query with ETS match_spec generation.
  
  For now, this implementation falls back to application-level filtering
  for complex nested queries. Future versions could implement more sophisticated
  ETS match spec generation for common patterns.
  """
  def query(criteria) when is_list(criteria) do
    # Validate criteria format first
    case validate_criteria(criteria) do
      :ok ->
        try do
          # For now, use simple table scan with application-level filtering
          # This is less performant but more flexible for complex criteria
          all_agents = :ets.tab2list(:agent_main)
          
          filtered = Enum.filter(all_agents, fn {_id, _pid, metadata, _timestamp} ->
            Enum.all?(criteria, fn criterion ->
              matches_criterion?(metadata, criterion)
            end)
          end)
          
          formatted_results = Enum.map(filtered, fn {id, pid, metadata, _timestamp} -> 
            {id, pid, metadata} 
          end)
          
          {:ok, formatted_results}
        rescue
          e in [ArgumentError, MatchError] ->
            Logger.warning("Invalid query criteria: #{inspect(criteria)}, error: #{Exception.message(e)}")
            {:error, {:invalid_criteria, Exception.message(e)}}
        end
      
      {:error, reason} ->
        {:error, {:invalid_criteria, reason}}
    end
  end
  
  def query(_invalid_criteria) do
    {:error, :invalid_criteria_format}
  end
  
  # --- Private Read Helpers ---
  
  defp batch_lookup_agents(agent_ids) do
    results = 
      agent_ids
      |> Enum.map(&:ets.lookup(:agent_main, &1))
      |> List.flatten()
      |> Enum.map(fn {id, pid, metadata, _timestamp} -> {id, pid, metadata} end)
    
    {:ok, results}
  end
  
  defp apply_filter(results, nil), do: results
  defp apply_filter(results, filter_fn) do
    Enum.filter(results, fn {_id, _pid, metadata} -> filter_fn.(metadata) end)
  end
  
  # --- Application-Level Filtering for Complex Queries ---
  
  defp validate_criteria(criteria) do
    case Enum.find(criteria, fn criterion ->
      case criterion do
        {path, _value, op} when is_list(path) -> 
          not valid_operation?(op)
        _ -> 
          true
      end
    end) do
      nil -> :ok
      invalid_criterion -> {:error, "Invalid criterion format: #{inspect(invalid_criterion)}"}
    end
  end
  
  defp valid_operation?(op) do
    op in [:eq, :neq, :gt, :lt, :gte, :lte, :in, :not_in]
  end
  
  defp matches_criterion?(metadata, {path, value, op}) do
    actual_value = get_nested_value(metadata, path)
    apply_operation(actual_value, value, op)
  end
  
  defp get_nested_value(metadata, [key]) do
    Map.get(metadata, key)
  end
  
  defp get_nested_value(metadata, [key | rest]) do
    case Map.get(metadata, key) do
      nil -> nil
      nested_map when is_map(nested_map) -> get_nested_value(nested_map, rest)
      _ -> nil
    end
  end
  
  defp apply_operation(actual, expected, :eq), do: actual == expected
  defp apply_operation(actual, expected, :neq), do: actual != expected
  defp apply_operation(actual, expected, :gt), do: actual > expected
  defp apply_operation(actual, expected, :lt), do: actual < expected
  defp apply_operation(actual, expected, :gte), do: actual >= expected
  defp apply_operation(actual, expected, :lte), do: actual <= expected
  defp apply_operation(actual, expected_list, :in) when is_list(expected_list), do: actual in expected_list
  defp apply_operation(actual, expected_list, :not_in) when is_list(expected_list), do: actual not in expected_list
  
  # --- GenServer Implementation for Write Operations ---
  
  def handle_call({:register, agent_id, pid, metadata}, _from, state) do
    with :ok <- validate_agent_metadata(metadata) do
      entry = {agent_id, pid, metadata, :os.timestamp()}
      
      case :ets.insert_new(state.main_table, entry) do
        true ->
          # Update all indexes atomically
          update_all_indexes(state, agent_id, metadata)
          
          # Setup process monitoring
          monitor_ref = Process.monitor(pid)
          new_monitors = Map.put(state.monitors, monitor_ref, agent_id)
          
          Logger.debug("Registered agent #{inspect(agent_id)} with capabilities #{inspect(metadata.capability)}")
          
          {:reply, :ok, %{state | monitors: new_monitors}}
        false ->
          {:reply, {:error, :already_exists}, state}
      end
    else
      error -> {:reply, error, state}
    end
  end
  
  def handle_call({:update_metadata, agent_id, new_metadata}, _from, state) do
    with :ok <- validate_agent_metadata(new_metadata),
         [{^agent_id, pid, _old_metadata, _timestamp}] <- :ets.lookup(state.main_table, agent_id) do
      
      # Update main table
      :ets.insert(state.main_table, {agent_id, pid, new_metadata, :os.timestamp()})
      
      # Clear old indexes and rebuild
      clear_agent_from_indexes(state, agent_id)
      update_all_indexes(state, agent_id, new_metadata)
      
      Logger.debug("Updated metadata for agent #{inspect(agent_id)}")
      
      {:reply, :ok, state}
    else
      [] -> {:reply, {:error, :not_found}, state}
      error -> {:reply, error, state}
    end
  end
  
  def handle_call({:unregister, agent_id}, _from, state) do
    case :ets.lookup(state.main_table, agent_id) do
      [{^agent_id, _pid, _metadata, _timestamp}] ->
        :ets.delete(state.main_table, agent_id)
        clear_agent_from_indexes(state, agent_id)
        
        Logger.debug("Unregistered agent #{inspect(agent_id)}")
        
        {:reply, :ok, state}
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end
  
  def handle_info({:DOWN, monitor_ref, :process, _pid, reason}, state) do
    case Map.get(state.monitors, monitor_ref) do
      nil ->
        # Unknown monitor, ignore
        {:noreply, state}
      
      agent_id ->
        Logger.info("Agent #{inspect(agent_id)} process died (#{inspect(reason)}), cleaning up")
        
        # Clean up agent registration
        :ets.delete(state.main_table, agent_id)
        clear_agent_from_indexes(state, agent_id)
        
        # Remove from monitors
        new_monitors = Map.delete(state.monitors, monitor_ref)
        
        {:noreply, %{state | monitors: new_monitors}}
    end
  end
  
  # --- Private Write Helpers ---
  
  defp validate_agent_metadata(metadata) do
    case find_missing_fields(metadata) do
      [] -> 
        validate_health_status(metadata)
      missing_fields -> 
        {:error, {:missing_required_fields, missing_fields}}
    end
  end
  
  defp find_missing_fields(metadata) do
    Enum.filter(@required_fields, fn field -> 
      not Map.has_key?(metadata, field) 
    end)
  end
  
  defp validate_health_status(metadata) do
    health_status = Map.get(metadata, :health_status)
    
    if health_status in @valid_health_statuses do
      :ok
    else
      {:error, {:invalid_health_status, health_status, @valid_health_statuses}}
    end
  end
  
  defp update_all_indexes(state, agent_id, metadata) do
    # Capability index (handle both single capability and list)
    capabilities = List.wrap(Map.get(metadata, :capability, []))
    for capability <- capabilities do
      :ets.insert(state.capability_index, {capability, agent_id})
    end
    
    # Health index
    health_status = Map.get(metadata, :health_status, :unknown)
    :ets.insert(state.health_index, {health_status, agent_id})
    
    # Node index
    node = Map.get(metadata, :node, node())
    :ets.insert(state.node_index, {node, agent_id})
    
    # Resource index (ordered by memory usage for efficient range queries)
    resources = Map.get(metadata, :resources, %{})
    memory_usage = Map.get(resources, :memory_usage, 0.0)
    :ets.insert(state.resource_index, {{memory_usage, agent_id}, agent_id})
  end
  
  defp clear_agent_from_indexes(state, agent_id) do
    # Use match_delete for efficient cleanup
    :ets.match_delete(state.capability_index, {:_, agent_id})
    :ets.match_delete(state.health_index, {:_, agent_id})
    :ets.match_delete(state.node_index, {:_, agent_id})
    :ets.match_delete(state.resource_index, {{:_, agent_id}, agent_id})
  end
end