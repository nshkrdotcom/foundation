defmodule Foundation.ServiceIntegration.DependencyManager do
  @moduledoc """
  Rebuilds the lost DependencyManager addressing Dialyzer agent type system issues.
  
  This module provides service dependency management to prevent startup/integration
  failures. It uses Foundation.ResourceManager patterns for ETS management and
  follows Foundation supervision patterns.

  ## Purpose

  The DependencyManager handles:
  - Service dependency registration and validation
  - Circular dependency detection
  - Service startup/shutdown orchestration  
  - Dependency-aware service ordering

  ## Features

  - Explicit dependency declaration via module attributes
  - Automatic dependency ordering via topological sort
  - Circular dependency detection
  - Service startup/shutdown orchestration
  - Integration with Foundation.ResourceManager ETS patterns

  ## Usage

      # Start the dependency manager
      {:ok, _pid} = Foundation.ServiceIntegration.DependencyManager.start_link()

      # Register a service with its dependencies
      :ok = Foundation.ServiceIntegration.DependencyManager.register_service(
        MyService, 
        [Foundation.Services.RetryService, Foundation.Services.SignalBus]
      )

      # Get startup order for services
      {:ok, order} = Foundation.ServiceIntegration.DependencyManager.get_startup_order(
        [MyService, OtherService]
      )

      # Start services in dependency order
      :ok = Foundation.ServiceIntegration.DependencyManager.start_services_in_dependency_order(
        [MyService, OtherService]
      )
  """

  use GenServer
  require Logger

  # Follow Foundation.ResourceManager ETS patterns
  @table_name :service_integration_dependencies
  @table_opts [:set, :public, :named_table, read_concurrency: true]

  @type service_module :: module()
  @type dependency_list :: [service_module()]
  @type startup_order :: [service_module()]

  ## Client API

  @doc """
  Starts the DependencyManager GenServer.

  ## Options

  - `:name` - Process name (default: __MODULE__)
  - `:table_name` - ETS table name (default: #{@table_name})
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Registers a service with its dependencies.

  Addresses Dialyzer agent type system confusion with defensive patterns.
  Uses validated dependency storage following Foundation patterns.

  ## Parameters

  - `service_module` - The service module to register (must be an atom)
  - `dependencies` - List of modules this service depends on

  ## Returns

  - `:ok` - Service registered successfully
  - `{:error, reason}` - Registration failed
  """
  @spec register_service(service_module(), dependency_list()) :: 
    :ok | {:error, term()}
  def register_service(service_module, dependencies) when is_atom(service_module) do
    GenServer.call(__MODULE__, {:register_service, service_module, dependencies})
  end

  @doc """
  Validates all registered service dependencies.

  Detects circular dependencies and ensures all referenced services are valid.

  ## Returns

  - `:ok` - All dependencies are valid
  - `{:error, {:circular_dependencies, cycles}}` - Circular dependencies detected
  - `{:error, {:missing_services, services}}` - Referenced services don't exist
  """
  @spec validate_dependencies() :: :ok | {:error, term()}
  def validate_dependencies do
    GenServer.call(__MODULE__, :validate_dependencies)
  end

  @doc """
  Calculates the proper startup order for given services.

  Uses topological sorting to determine the order in which services should
  be started to respect their dependencies.

  ## Parameters

  - `services` - List of service modules to order

  ## Returns

  - `{:ok, startup_order}` - Services ordered by dependencies
  - `{:error, reason}` - Could not determine order (circular deps, etc.)
  """
  @spec get_startup_order([service_module()]) :: 
    {:ok, startup_order()} | {:error, term()}
  def get_startup_order(services) when is_list(services) do
    GenServer.call(__MODULE__, {:get_startup_order, services})
  end

  @doc """
  Starts services in dependency order.

  Orchestrates service startup ensuring dependencies are started before
  services that depend on them.

  ## Parameters

  - `services` - List of service modules to start

  ## Returns

  - `:ok` - All services started successfully
  - `{:error, reason}` - Some services failed to start
  """
  @spec start_services_in_dependency_order([service_module()]) :: 
    :ok | {:error, term()}
  def start_services_in_dependency_order(services) when is_list(services) do
    GenServer.call(__MODULE__, {:start_services_in_dependency_order, services}, 30_000)
  end

  @doc """
  Gets all registered services and their dependencies.
  """
  @spec get_all_dependencies() :: map()
  def get_all_dependencies do
    GenServer.call(__MODULE__, :get_all_dependencies)
  end

  @doc """
  Removes a service registration.
  """
  @spec unregister_service(service_module()) :: :ok
  def unregister_service(service_module) when is_atom(service_module) do
    GenServer.call(__MODULE__, {:unregister_service, service_module})
  end

  ## GenServer Implementation

  defstruct [
    :table_name,
    :dependency_graph
  ]

  @impl GenServer
  def init(opts) do
    # Generate unique table name based on process name to avoid conflicts
    process_name = Keyword.get(opts, :name, __MODULE__)
    default_table_name = :"#{@table_name}_#{:erlang.phash2(process_name)}"
    table_name = Keyword.get(opts, :table_name, default_table_name)
    
    # Create ETS table following Foundation.ResourceManager patterns
    case :ets.new(table_name, @table_opts) do
      ^table_name ->
        Logger.info("Foundation.ServiceIntegration.DependencyManager started",
          table_name: table_name)
        
        {:ok, %__MODULE__{
          table_name: table_name,
          dependency_graph: %{}
        }}
        
      {:error, reason} ->
        Logger.error("Failed to create DependencyManager ETS table",
          table_name: table_name, reason: reason)
        {:stop, {:ets_creation_failed, reason}}
    end
  end

  @impl GenServer
  def handle_call({:register_service, service_module, dependencies}, _from, state) do
    try do
      # Address Dialyzer agent type system confusion with defensive patterns
      validated_deps = validate_service_dependencies(service_module, dependencies)
      
      # Store in ETS table
      case store_service_dependencies(state.table_name, service_module, validated_deps) do
        :ok ->
          # Update in-memory graph
          new_graph = Map.put(state.dependency_graph, service_module, validated_deps)
          new_state = %{state | dependency_graph: new_graph}
          
          Logger.debug("Registered service dependencies",
            service: service_module, 
            dependencies: validated_deps)
          
          {:reply, :ok, new_state}
          
        {:error, reason} ->
          {:reply, {:error, {:dependency_storage_failed, reason}}, state}
      end
    rescue
      exception ->
        Logger.error("Exception registering service dependencies",
          service: service_module,
          exception: inspect(exception))
        {:reply, {:error, {:registration_exception, exception}}, state}
    end
  end

  @impl GenServer
  def handle_call(:validate_dependencies, _from, state) do
    result = try do
      # Check for circular dependencies
      case detect_circular_dependencies(state.dependency_graph) do
        [] ->
          # Check for missing services
          case find_missing_services(state.dependency_graph) do
            [] -> :ok
            missing -> {:error, {:missing_services, missing}}
          end
          
        cycles ->
          {:error, {:circular_dependencies, cycles}}
      end
    rescue
      exception ->
        {:error, {:validation_exception, exception}}
    end
    
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:get_startup_order, services}, _from, state) do
    result = try do
      # Build subgraph for requested services
      subgraph = build_subgraph(state.dependency_graph, services)
      
      # Perform topological sort
      case topological_sort(subgraph) do
        {:ok, sorted} ->
          # Filter to only requested services
          filtered = Enum.filter(sorted, &(&1 in services))
          {:ok, filtered}
          
        {:error, reason} ->
          {:error, reason}
      end
    rescue
      exception ->
        {:error, {:sort_exception, exception}}
    end
    
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:start_services_in_dependency_order, services}, _from, state) do
    result = try do
      # Get startup order
      case get_startup_order_internal(state.dependency_graph, services) do
        {:ok, order} ->
          # Start services in order
          start_services_in_order(order)
          
        {:error, reason} ->
          {:error, reason}
      end
    rescue
      exception ->
        {:error, {:startup_exception, exception}}
    end
    
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(:get_all_dependencies, _from, state) do
    # Return copy of dependency graph
    {:reply, Map.new(state.dependency_graph), state}
  end

  @impl GenServer
  def handle_call({:unregister_service, service_module}, _from, state) do
    # Remove from ETS
    :ets.delete(state.table_name, service_module)
    
    # Remove from graph
    new_graph = Map.delete(state.dependency_graph, service_module)
    new_state = %{state | dependency_graph: new_graph}
    
    Logger.debug("Unregistered service", service: service_module)
    
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    # Clean up ETS table
    if state.table_name && :ets.whereis(state.table_name) != :undefined do
      :ets.delete(state.table_name)
    end
    :ok
  end

  ## Private Functions

  defp validate_service_dependencies(_service_module, dependencies) do
    # Store dependencies as-is for later validation
    # Don't filter them here - let validation detect missing services
    dependencies
  end

  defp validate_jido_agent_safely(agent_module) do
    # Defensive validation addressing Dialyzer callback_type_mismatch issues
    try do
      Code.ensure_loaded?(agent_module) and
      function_exported?(agent_module, :__struct__, 0)
    rescue
      _ -> false
    end
  end

  defp store_service_dependencies(table_name, service_module, dependencies) do
    try do
      :ets.insert(table_name, {service_module, dependencies})
      :ok
    rescue
      exception ->
        {:error, {:ets_insert_failed, exception}}
    end
  end

  defp detect_circular_dependencies(dependency_graph) do
    # Use DFS to detect cycles
    all_services = Map.keys(dependency_graph)
    
    Enum.reduce(all_services, [], fn service, acc ->
      case dfs_detect_cycle(dependency_graph, service, [], MapSet.new()) do
        nil -> acc
        cycle -> [cycle | acc]
      end
    end)
  end

  defp dfs_detect_cycle(graph, current, path, visited) do
    cond do
      current in path ->
        # Found cycle
        cycle_start = Enum.find_index(path, &(&1 == current))
        Enum.drop(path, cycle_start) ++ [current]
        
      MapSet.member?(visited, current) ->
        # Already visited, no cycle from this path
        nil
        
      true ->
        # Continue DFS
        new_path = [current | path]
        new_visited = MapSet.put(visited, current)
        dependencies = Map.get(graph, current, [])
        
        Enum.find_value(dependencies, fn dep ->
          dfs_detect_cycle(graph, dep, new_path, new_visited)
        end)
    end
  end

  defp find_missing_services(dependency_graph) do
    all_registered = MapSet.new(Map.keys(dependency_graph))
    all_referenced = dependency_graph
                    |> Map.values()
                    |> List.flatten()
                    |> MapSet.new()
    
    # Find dependencies that are neither registered nor exist as modules
    missing_from_registry = MapSet.difference(all_referenced, all_registered)
    
    # Check if missing dependencies are actual modules that exist
    missing_from_registry
    |> Enum.filter(fn dep ->
      not dependency_exists?(dep)
    end)
  end
  
  defp dependency_exists?(dep) do
    cond do
      # Foundation services - always valid
      String.starts_with?(to_string(dep), "Elixir.Foundation") -> 
        Code.ensure_loaded?(dep)
      # Jido agents - use defensive validation due to type system issues
      String.contains?(to_string(dep), "Agent") -> 
        validate_jido_agent_safely(dep)
      # Other services - standard validation
      true -> 
        Code.ensure_loaded?(dep)
    end
  end

  defp build_subgraph(dependency_graph, services) do
    # Include all transitive dependencies
    all_deps = collect_all_dependencies(dependency_graph, services, MapSet.new())
    
    dependency_graph
    |> Map.take(MapSet.to_list(all_deps))
  end

  defp collect_all_dependencies(graph, services, collected) do
    new_deps = services
               |> Enum.flat_map(&Map.get(graph, &1, []))
               |> MapSet.new()
               |> MapSet.difference(collected)
    
    if MapSet.size(new_deps) == 0 do
      MapSet.union(collected, MapSet.new(services))
    else
      new_collected = MapSet.union(collected, MapSet.new(services))
      collect_all_dependencies(graph, MapSet.to_list(new_deps), new_collected)
    end
  end

  defp topological_sort(graph) do
    try do
      # Kahn's algorithm for topological sorting
      in_degrees = calculate_in_degrees(graph)
      queue = Enum.filter(Map.keys(graph), &(Map.get(in_degrees, &1, 0) == 0))
      
      topological_sort_kahn(graph, in_degrees, queue, [])
    rescue
      exception ->
        {:error, {:topological_sort_failed, exception}}
    end
  end

  defp calculate_in_degrees(graph) do
    all_nodes = Map.keys(graph)
    initial_degrees = Map.new(all_nodes, &{&1, 0})
    
    Enum.reduce(graph, initial_degrees, fn {_node, deps}, acc ->
      Enum.reduce(deps, acc, fn dep, acc2 ->
        Map.update(acc2, dep, 1, &(&1 + 1))
      end)
    end)
  end

  defp topological_sort_kahn(graph, _in_degrees, [], result) do
    if length(result) == map_size(graph) do
      {:ok, result}  # Don't reverse - Kahn's algorithm builds in correct dependency order
    else
      {:error, :circular_dependency_detected}
    end
  end

  defp topological_sort_kahn(graph, in_degrees, [current | rest_queue], result) do
    # Add current to result
    new_result = [current | result]
    
    # Reduce in-degree for all dependents
    dependencies = Map.get(graph, current, [])
    {new_in_degrees, new_queue} = 
      Enum.reduce(dependencies, {in_degrees, rest_queue}, fn dep, {degrees, queue} ->
        new_degree = Map.get(degrees, dep, 0) - 1
        updated_degrees = Map.put(degrees, dep, new_degree)
        
        if new_degree == 0 do
          {updated_degrees, [dep | queue]}
        else
          {updated_degrees, queue}
        end
      end)
    
    topological_sort_kahn(graph, new_in_degrees, new_queue, new_result)
  end

  defp get_startup_order_internal(dependency_graph, services) do
    # Build subgraph for requested services
    subgraph = build_subgraph(dependency_graph, services)
    
    # Perform topological sort
    case topological_sort(subgraph) do
      {:ok, sorted} ->
        # Filter to only requested services
        filtered = Enum.filter(sorted, &(&1 in services))
        {:ok, filtered}
        
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp start_services_in_order(services) do
    results = Enum.map(services, fn service ->
      try do
        case service.start_link() do
          {:ok, _pid} -> 
            Logger.debug("Started service", service: service)
            {:ok, service}
          {:error, {:already_started, _pid}} -> 
            Logger.debug("Service already started", service: service)
            {:ok, service}
          {:error, reason} -> 
            Logger.warning("Failed to start service", service: service, reason: reason)
            {:error, {service, reason}}
        end
      rescue
        exception -> 
          Logger.error("Exception starting service", service: service, exception: inspect(exception))
          {:error, {service, {:start_exception, exception}}}
      end
    end)
    
    failed = Enum.filter(results, &match?({:error, _}, &1))
    
    case failed do
      [] -> :ok
      failures -> {:error, {:service_startup_failures, failures}}
    end
  end
end