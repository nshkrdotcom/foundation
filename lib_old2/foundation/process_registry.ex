defmodule Foundation.ProcessRegistry do
  @moduledoc """
  Distribution-ready Process Registry with agent-aware capabilities.
  
  Provides unified process registration and lookup with rich metadata support,
  designed for single-node performance and seamless cluster migration.
  
  ## Features
  
  - Distribution-ready process identification: `{namespace, node, id}`
  - Agent metadata support: capabilities, health, resources, coordination variables
  - Agent-specific lookup functions (by capability, type, health status)
  - Future Horde integration points for cluster deployment
  - Optimized for multi-agent coordination patterns
  - Health monitoring and status tracking
  
  ## Process Identification
  
  Processes are identified by `{namespace, node, local_id}` tuples to support
  seamless migration to distributed deployments:
  
      process_id = {:production, node(), :my_agent}
      Foundation.ProcessRegistry.register(process_id, pid, metadata)
  
  For single-node convenience, local registration is also supported:
  
      Foundation.ProcessRegistry.register_local(:my_agent, pid, metadata)
  
  ## Agent Metadata
  
  Rich metadata enables sophisticated coordination:
  
      metadata = %{
        type: :agent,
        capabilities: [:coordination, :planning, :execution],
        resources: %{memory_mb: 100, cpu_percent: 25},
        coordination_variables: [:system_load, :agent_count],
        health_status: :healthy,
        node_affinity: [node()],
        created_at: DateTime.utc_now()
      }
  
  ## Agent-Specific Functions
  
  Find agents by capability:
      {:ok, agents} = Foundation.ProcessRegistry.find_by_capability(:coordination)
  
  Find agents by type:
      {:ok, agents} = Foundation.ProcessRegistry.find_by_type(:agent)
  
  Update agent health:
      :ok = Foundation.ProcessRegistry.update_agent_health(:my_agent, :degraded)
  """
  
  use GenServer
  require Logger
  
  # Timeout constants from formal specification
  @registration_timeout_ms 10_000
  @lookup_timeout_ms 5_000
  @query_timeout_ms 10_000
  @health_update_timeout_ms 5_000
  @cleanup_window_ms 100
  @max_memory_bytes 100_000_000  # 100MB limit
  
  @type namespace :: atom()
  @type local_id :: term()
  @type process_id :: {namespace(), node(), local_id()}
  
  @type agent_type :: :agent | :service | :coordinator | :resource_manager
  @type health_status :: :healthy | :degraded | :unhealthy
  @type capability :: atom()
  
  @type agent_metadata :: %{
          optional(:type) => agent_type(),
          optional(:capabilities) => [capability()],
          optional(:resources) => map(),
          optional(:coordination_variables) => [atom()],
          optional(:health_status) => health_status(),
          optional(:node_affinity) => [node()],
          optional(:created_at) => DateTime.t(),
          optional(:last_health_check) => DateTime.t(),
          optional(:custom) => map()
        }
  
  @type registry_entry :: {pid(), agent_metadata()}
  @type lookup_result :: {:ok, pid()} | {:ok, pid(), agent_metadata()} | :error
  
  ## Public API
  
  @doc """
  Start the ProcessRegistry GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @doc """
  Register a process with full distribution-ready identification.
  
  ## Examples
  
      process_id = {:production, node(), :my_agent}
      metadata = %{type: :agent, capabilities: [:coordination]}
      :ok = Foundation.ProcessRegistry.register(process_id, self(), metadata)
  """
  @spec register(process_id(), pid(), agent_metadata()) :: :ok | {:error, term()}
  def register(process_id, pid, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:register, process_id, pid, metadata}, @registration_timeout_ms)
  end
  
  @doc """
  Register a process with local convenience syntax.
  
  Automatically uses default namespace and current node.
  
  ## Examples
  
      :ok = Foundation.ProcessRegistry.register_local(:my_agent, self(), metadata)
  """
  @spec register_local(local_id(), pid(), agent_metadata()) :: :ok | {:error, term()}
  def register_local(local_id, pid, metadata \\ %{}) do
    namespace = Application.get_env(:foundation, :default_namespace, :production)
    process_id = {namespace, node(), local_id}
    register(process_id, pid, metadata)
  end
  
  @doc """
  Look up a process by full process ID.
  
  ## Examples
  
      case Foundation.ProcessRegistry.lookup({:production, node(), :my_agent}) do
        {:ok, pid} -> send(pid, :hello)
        :error -> :not_found
      end
  """
  @spec lookup(process_id()) :: lookup_result()
  def lookup(process_id) do
    GenServer.call(__MODULE__, {:lookup, process_id}, @lookup_timeout_ms)
  end
  
  @doc """
  Look up a process by local ID (convenience function).
  
  ## Examples
  
      case Foundation.ProcessRegistry.lookup_local(:my_agent) do
        {:ok, pid, metadata} -> {pid, metadata}
        :error -> :not_found
      end
  """
  @spec lookup_local(local_id(), namespace()) :: lookup_result()
  def lookup_local(local_id, namespace \\ nil) do
    namespace = namespace || Application.get_env(:foundation, :default_namespace, :production)
    process_id = {namespace, node(), local_id}
    lookup(process_id)
  end
  
  @doc """
  Find all processes with a specific capability.
  
  ## Examples
  
      {:ok, coordination_agents} = Foundation.ProcessRegistry.find_by_capability(:coordination)
      Enum.each(coordination_agents, fn {pid, metadata} ->
        send(pid, {:coordinate, :consensus})
      end)
  """
  @spec find_by_capability(capability()) :: {:ok, [registry_entry()]} | {:error, term()}
  def find_by_capability(capability) do
    GenServer.call(__MODULE__, {:find_by_capability, capability}, @query_timeout_ms)
  end
  
  @doc """
  Find all processes of a specific type.
  
  ## Examples
  
      {:ok, all_agents} = Foundation.ProcessRegistry.find_by_type(:agent)
      agent_count = length(all_agents)
  """
  @spec find_by_type(agent_type()) :: {:ok, [registry_entry()]} | {:error, term()}
  def find_by_type(type) do
    GenServer.call(__MODULE__, {:find_by_type, type}, @query_timeout_ms)
  end
  
  @doc """
  Find all processes with a specific health status.
  
  ## Examples
  
      {:ok, unhealthy_agents} = Foundation.ProcessRegistry.find_by_health(:unhealthy)
      Enum.each(unhealthy_agents, fn {pid, metadata} ->
        Logger.warning("Unhealthy agent: \#{inspect(metadata)}")
      end)
  """
  @spec find_by_health(health_status()) :: {:ok, [registry_entry()]} | {:error, term()}
  def find_by_health(health_status) do
    GenServer.call(__MODULE__, {:find_by_health, health_status})
  end
  
  @doc """
  List all registered processes in a namespace.
  
  ## Examples
  
      {:ok, all_processes} = Foundation.ProcessRegistry.list_all(:production)
  """
  @spec list_all(namespace()) :: {:ok, [registry_entry()]} | {:error, term()}
  def list_all(namespace \\ :production) do
    GenServer.call(__MODULE__, {:list_all, namespace})
  end
  
  @doc """
  Register an agent with enhanced agent-specific metadata.
  
  ## Examples
  
      agent_config = %{
        type: :agent,
        capabilities: [:coordination, :planning],
        resources: %{memory_mb: 100, cpu_percent: 25},
        coordination_variables: [:system_load]
      }
      :ok = Foundation.ProcessRegistry.register_agent(:my_agent, self(), agent_config)
  """
  @spec register_agent(local_id(), pid(), agent_metadata()) :: :ok | {:error, term()}
  def register_agent(agent_id, pid, agent_config) do
    enhanced_metadata = 
      agent_config
      |> Map.put(:type, :agent)
      |> Map.put(:created_at, DateTime.utc_now())
      |> Map.put(:last_health_check, DateTime.utc_now())
      |> Map.put_new(:health_status, :healthy)
      |> Map.put_new(:node_affinity, [node()])
    
    register_local(agent_id, pid, enhanced_metadata)
  end
  
  @doc """
  Update the health status of an agent.
  
  ## Examples
  
      :ok = Foundation.ProcessRegistry.update_agent_health(:my_agent, :degraded)
  """
  @spec update_agent_health(local_id(), health_status()) :: :ok | {:error, term()}
  def update_agent_health(agent_id, health_status) do
    GenServer.call(__MODULE__, {:update_agent_health, agent_id, health_status}, @health_update_timeout_ms)
  end
  
  @doc """
  Get the metadata for a specific agent.
  
  ## Examples
  
      case Foundation.ProcessRegistry.get_agent_metadata(:my_agent) do
        {:ok, metadata} -> metadata.capabilities
        :error -> []
      end
  """
  @spec get_agent_metadata(local_id()) :: {:ok, agent_metadata()} | :error
  def get_agent_metadata(agent_id) do
    case lookup_local(agent_id) do
      {:ok, _pid, metadata} -> {:ok, metadata}
      {:ok, _pid} -> {:ok, %{}}
      :error -> :error
    end
  end
  
  @doc """
  Unregister a process.
  
  ## Examples
  
      :ok = Foundation.ProcessRegistry.unregister({:production, node(), :my_agent})
  """
  @spec unregister(process_id()) :: :ok
  def unregister(process_id) do
    GenServer.call(__MODULE__, {:unregister, process_id})
  end
  
  @doc """
  Unregister a process by local ID.
  """
  @spec unregister_local(local_id(), namespace()) :: :ok
  def unregister_local(local_id, namespace \\ nil) do
    namespace = namespace || Application.get_env(:foundation, :default_namespace, :production)
    process_id = {namespace, node(), local_id}
    unregister(process_id)
  end
  
  ## Future Distribution Support
  
  @doc """
  Look up a process across the entire cluster (Future: Horde integration).
  
  Currently delegates to local lookup but provides API for future enhancement.
  """
  @spec cluster_lookup(process_id()) :: lookup_result()
  def cluster_lookup(process_id) do
    # Future: Integrate with Horde or libcluster for distributed lookup
    lookup(process_id)
  end
  
  @doc """
  Migrate an agent to a target node (Future: Distribution support).
  
  Currently returns error but provides API for future enhancement.
  """
  @spec migrate_agent(local_id(), node()) :: :ok | {:error, term()}
  def migrate_agent(_agent_id, _target_node) do
    # Future: Implement agent migration for distributed deployments
    {:error, :not_implemented}
  end
  
  ## Optimization and Maintenance
  
  @doc """
  Initialize ProcessRegistry optimizations for large agent systems.
  """
  @spec initialize_optimizations() :: :ok
  def initialize_optimizations do
    # Future: Add ETS table optimizations, indexing, etc.
    :ok
  end
  
  @doc """
  Clean up ProcessRegistry optimizations.
  """
  @spec cleanup_optimizations() :: :ok
  def cleanup_optimizations do
    # Future: Clean up optimization resources
    :ok
  end
  
  ## GenServer Implementation
  
  @impl true
  def init(_opts) do
    # Create ETS table for fast lookups
    table = :ets.new(__MODULE__, [
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])
    
    # Create indexes for agent-specific lookups
    capability_index = :ets.new(:"#{__MODULE__}.capabilities", [
      :duplicate_bag,
      :public,
      read_concurrency: true
    ])
    
    type_index = :ets.new(:"#{__MODULE__}.types", [
      :duplicate_bag,
      :public,
      read_concurrency: true
    ])
    
    health_index = :ets.new(:"#{__MODULE__}.health", [
      :duplicate_bag,
      :public,
      read_concurrency: true
    ])
    
    state = %{
      table: table,
      capability_index: capability_index,
      type_index: type_index,
      health_index: health_index,
      monitors: %{}
    }
    
    Logger.info("Foundation ProcessRegistry started with agent-aware capabilities")
    
    {:ok, state}
  end
  
  @impl true
  def handle_call({:register, process_id, pid, metadata}, _from, state) do
    with :ok <- validate_registration_inputs(process_id, pid, metadata),
         true <- :ets.insert_new(state.table, {process_id, pid, metadata}) do
      # Atomic registration succeeded, now update indexes and monitor
      try do
        # Update indexes
        update_indexes(process_id, pid, metadata, state)
        
        # Monitor the process
        monitor_ref = Process.monitor(pid)
        monitors = Map.put(state.monitors, monitor_ref, process_id)
        
        # Emit telemetry
        :telemetry.execute(
          [:foundation, :process_registry, :registered],
          %{count: 1},
          %{process_id: process_id, metadata: metadata}
        )
        
        Logger.debug("Registered process #{inspect(process_id)} with metadata: #{inspect(metadata)}")
        
        {:reply, :ok, %{state | monitors: monitors}}
      rescue
        error ->
          # Rollback: remove from main table if index update failed
          :ets.delete(state.table, process_id)
          Logger.error("Registration rollback for #{inspect(process_id)}: #{inspect(error)}")
          {:reply, {:error, :registration_failed}, state}
      end
    else
      false ->
        # :ets.insert_new returned false - already exists
        {:reply, {:error, :already_registered}, state}
      
      {:error, reason} ->
        # Validation failed
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:lookup, process_id}, _from, state) do
    case :ets.lookup(state.table, process_id) do
      [{^process_id, pid, metadata}] ->
        if Process.alive?(pid) do
          {:reply, {:ok, pid, metadata}, state}
        else
          # Clean up dead process
          cleanup_process(process_id, state)
          {:reply, :error, state}
        end
      
      [] ->
        {:reply, :error, state}
    end
  end
  
  @impl true
  def handle_call({:find_by_capability, capability}, _from, state) do
    entries = :ets.lookup(state.capability_index, capability)
    
    results = 
      Enum.flat_map(entries, fn {_, process_id} ->
        case :ets.lookup(state.table, process_id) do
          [{^process_id, pid, metadata}] ->
            if Process.alive?(pid) do
              [{pid, metadata}]
            else
              []
            end
          _ ->
            []
        end
      end)
    
    {:reply, {:ok, results}, state}
  end
  
  @impl true
  def handle_call({:find_by_type, type}, _from, state) do
    entries = :ets.lookup(state.type_index, type)
    
    results = 
      Enum.flat_map(entries, fn {_, process_id} ->
        case :ets.lookup(state.table, process_id) do
          [{^process_id, pid, metadata}] ->
            if Process.alive?(pid) do
              [{pid, metadata}]
            else
              []
            end
          _ ->
            []
        end
      end)
    
    {:reply, {:ok, results}, state}
  end
  
  @impl true
  def handle_call({:find_by_health, health_status}, _from, state) do
    entries = :ets.lookup(state.health_index, health_status)
    
    results = 
      Enum.flat_map(entries, fn {_, process_id} ->
        case :ets.lookup(state.table, process_id) do
          [{^process_id, pid, metadata}] ->
            if Process.alive?(pid) do
              [{pid, metadata}]
            else
              []
            end
          _ ->
            []
        end
      end)
    
    {:reply, {:ok, results}, state}
  end
  
  @impl true
  def handle_call({:list_all, namespace}, _from, state) do
    pattern = {{namespace, :_, :_}, :_, :_}
    entries = :ets.match_object(state.table, pattern)
    
    results = 
      Enum.flat_map(entries, fn {_process_id, pid, metadata} ->
        if Process.alive?(pid) do
          [{pid, metadata}]
        else
          []
        end
      end)
    
    {:reply, {:ok, results}, state}
  end
  
  @impl true
  def handle_call({:update_agent_health, agent_id, health_status}, _from, state) do
    namespace = Application.get_env(:foundation, :default_namespace, :production)
    process_id = {namespace, node(), agent_id}
    
    case :ets.lookup(state.table, process_id) do
      [{^process_id, pid, metadata}] ->
        # Update metadata
        updated_metadata = 
          metadata
          |> Map.put(:health_status, health_status)
          |> Map.put(:last_health_check, DateTime.utc_now())
        
        # Update main table
        :ets.insert(state.table, {process_id, pid, updated_metadata})
        
        # Update health index
        old_health = Map.get(metadata, :health_status, :healthy)
        :ets.delete_object(state.health_index, {old_health, process_id})
        :ets.insert(state.health_index, {health_status, process_id})
        
        Logger.debug("Updated health for #{agent_id}: #{old_health} -> #{health_status}")
        
        {:reply, :ok, state}
      
      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end
  
  @impl true
  def handle_call({:unregister, process_id}, _from, state) do
    cleanup_process(process_id, state)
    {:reply, :ok, state}
  end
  
  @impl true
  def handle_info({:DOWN, monitor_ref, :process, _pid, _reason}, state) do
    case Map.get(state.monitors, monitor_ref) do
      nil ->
        {:noreply, state}
      
      process_id ->
        Logger.debug("Process #{inspect(process_id)} went down, cleaning up")
        cleanup_process(process_id, state)
        monitors = Map.delete(state.monitors, monitor_ref)
        {:noreply, %{state | monitors: monitors}}
    end
  end
  
  ## Validation Functions
  
  defp validate_registration_inputs(process_id, pid, metadata) do
    with :ok <- validate_process_id(process_id),
         :ok <- validate_pid(pid),
         :ok <- validate_metadata(metadata) do
      :ok
    end
  end
  
  defp validate_process_id({namespace, node, local_id}) 
    when is_atom(namespace) and is_atom(node) and local_id != nil do
    :ok
  end
  defp validate_process_id(_), do: {:error, :invalid_process_id}
  
  defp validate_pid(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      :ok
    else
      {:error, :dead_process}
    end
  end
  defp validate_pid(_), do: {:error, :invalid_pid}
  
  defp validate_metadata(metadata) when is_map(metadata) do
    # Validate against agent_metadata() typespec
    with :ok <- validate_metadata_type(metadata),
         :ok <- validate_metadata_capabilities(metadata),
         :ok <- validate_metadata_health(metadata) do
      :ok
    end
  end
  defp validate_metadata(_), do: {:error, :invalid_metadata}
  
  defp validate_metadata_type(%{type: type}) when type in [:agent, :service, :coordinator, :resource_manager], do: :ok
  defp validate_metadata_type(%{}), do: :ok  # type is optional
  defp validate_metadata_type(_), do: {:error, :invalid_type}
  
  defp validate_metadata_capabilities(%{capabilities: capabilities}) when is_list(capabilities) do
    if Enum.all?(capabilities, &is_atom/1) do
      :ok
    else
      {:error, :invalid_capabilities}
    end
  end
  defp validate_metadata_capabilities(%{}), do: :ok  # capabilities is optional
  defp validate_metadata_capabilities(_), do: {:error, :invalid_capabilities}
  
  defp validate_metadata_health(%{health_status: health}) when health in [:healthy, :degraded, :unhealthy], do: :ok
  defp validate_metadata_health(%{}), do: :ok  # health_status is optional
  defp validate_metadata_health(_), do: {:error, :invalid_health_status}
  
  ## Private Functions
  
  defp update_indexes(process_id, _pid, metadata, state) do
    # Update capability index
    capabilities = Map.get(metadata, :capabilities, [])
    Enum.each(capabilities, fn capability ->
      :ets.insert(state.capability_index, {capability, process_id})
    end)
    
    # Update type index
    if type = Map.get(metadata, :type) do
      :ets.insert(state.type_index, {type, process_id})
    end
    
    # Update health index
    health_status = Map.get(metadata, :health_status, :healthy)
    :ets.insert(state.health_index, {health_status, process_id})
  end
  
  defp cleanup_process(process_id, state) do
    case :ets.lookup(state.table, process_id) do
      [{^process_id, _pid, metadata}] ->
        # Atomic cleanup: collect all operations first
        cleanup_operations = build_cleanup_operations(process_id, metadata, state)
        
        try do
          # Execute all cleanup operations atomically
          Enum.each(cleanup_operations, fn {table, operation, args} ->
            apply(:ets, operation, [table | args])
          end)
          
          # Emit telemetry
          :telemetry.execute(
            [:foundation, :process_registry, :cleanup],
            %{count: 1},
            %{process_id: process_id, metadata: metadata}
          )
          
          Logger.debug("Cleaned up process #{inspect(process_id)}")
          :ok
        rescue
          error ->
            Logger.error("Cleanup failed for #{inspect(process_id)}: #{inspect(error)}")
            # Attempt partial recovery - at least remove from main table
            :ets.delete(state.table, process_id)
            {:error, :cleanup_failed}
        end
      
      [] ->
        :ok
    end
  end
  
  defp build_cleanup_operations(process_id, metadata, state) do
    operations = [
      # Remove from main table first
      {state.table, :delete, [process_id]}
    ]
    
    # Add capability index cleanup
    capability_ops = 
      metadata
      |> Map.get(:capabilities, [])
      |> Enum.map(fn capability ->
        {state.capability_index, :delete_object, [{capability, process_id}]}
      end)
    
    # Add type index cleanup
    type_ops = 
      case Map.get(metadata, :type) do
        nil -> []
        type -> [{state.type_index, :delete_object, [{type, process_id}]}]
      end
    
    # Add health index cleanup
    health_status = Map.get(metadata, :health_status, :healthy)
    health_ops = [{state.health_index, :delete_object, [{health_status, process_id}]}]
    
    operations ++ capability_ops ++ type_ops ++ health_ops
  end
end