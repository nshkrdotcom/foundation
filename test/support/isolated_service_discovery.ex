defmodule Foundation.IsolatedServiceDiscovery do
  @moduledoc """
  Service discovery utilities for transparent access to JidoFoundation services in isolated supervision testing.
  
  This module provides transparent access to JidoFoundation services running in isolated
  supervision trees during testing, enabling tests to call service functions without
  needing to know about the underlying Registry-based service discovery mechanism.
  
  ## Features
  
  - Transparent service function calls in isolated test environments
  - GenServer call and cast operations with proper error handling
  - Timeout support and error propagation
  - Integration with existing test infrastructure
  - Clear error messages for debugging test issues
  
  ## Usage
  
  This module is designed to work with `Foundation.UnifiedTestFoundation` in 
  `:supervision_testing` mode and integrates with existing `Foundation.SupervisionTestHelpers`.
  
      defmodule MySupervisionTest do
        use Foundation.UnifiedTestFoundation, :supervision_testing
        
        test "service calls", %{supervision_tree: sup_tree} do
          # Call service functions transparently
          stats = call_service(sup_tree, TaskPoolManager, :get_all_stats)
          assert is_map(stats)
          
          # Call with arguments
          result = call_service(sup_tree, TaskPoolManager, :create_pool, 
            [:test_pool, %{max_concurrency: 4}])
          assert result == :ok
          
          # Cast messages to services
          :ok = cast_service(sup_tree, TaskPoolManager, {:update_config, %{timeout: 10000}})
        end
      end
  
  ## API Compatibility
  
  This module provides compatibility with normal service calls:
  
      # Instead of:
      TaskPoolManager.get_all_stats()
      
      # Use in isolated tests:
      call_service(sup_tree, TaskPoolManager, :get_all_stats)
      
      # With arguments:
      call_service(sup_tree, TaskPoolManager, :create_pool, [:test_pool, %{max_concurrency: 4}])
  
  ## Error Handling
  
  - Clear error messages for missing services
  - Timeout handling for long operations
  - Proper GenServer call/cast error propagation
  - Integration with test failure mechanisms
  
  ## Service Registration Pattern
  
  Services register in test registries using:
      Registry.register(registry, {:service, Module}, %{test_instance: true})
  
  This module looks up services using:
      Registry.lookup(registry, {:service, Module})
  
  ## Integration with Test Infrastructure
  
  - Works with supervision context from `Foundation.SupervisionTestSetup`
  - Compatible with existing `Foundation.SupervisionTestHelpers`
  - Supports async operations with proper waiting via `Foundation.AsyncTestHelpers`
  """
  
  require Logger
  
  @doc """
  Call a JidoFoundation service function in isolated test environment.
  
  Automatically routes calls to the correct isolated service instance based on the 
  current test's supervision context. This provides transparent access to services
  without needing to know about Registry mechanics.
  
  ## Parameters
  
  - `supervision_context` - The supervision context from test setup (contains `:registry`)
  - `service_module` - The service module (e.g., `JidoFoundation.TaskPoolManager`)  
  - `function` - Function atom or call tuple to execute
  - `args` - Function arguments (optional, default: [])
  - `timeout` - Call timeout in milliseconds (optional, default: 5000)
  
  ## Function Call Formats
  
  ### Simple function call:
      call_service(sup_tree, TaskPoolManager, :get_all_stats)
      # Calls: GenServer.call(pid, :get_all_stats)
  
  ### Function with arguments:
      call_service(sup_tree, TaskPoolManager, :create_pool, 
        [:test_pool, %{max_concurrency: 4}])
      # Calls: GenServer.call(pid, {:create_pool, [:test_pool, %{max_concurrency: 4}]})
  
  ### Direct tuple call:
      call_service(sup_tree, TaskPoolManager, {:create_pool, [:test_pool, %{max_concurrency: 4}]})
      # Calls: GenServer.call(pid, {:create_pool, [:test_pool, %{max_concurrency: 4}]})
  
  ## Returns
  
  - `result` - Whatever the service function returns
  - `{:error, {:service_not_found, module}}` - Service not registered in test registry
  - `{:error, {:service_not_alive, module}}` - Service registered but process dead
  - `{:error, {:call_failed, module, reason}}` - GenServer.call failed
  
  ## Examples
  
      test "task pool operations", %{supervision_tree: sup_tree} do
        # Get statistics
        stats = call_service(sup_tree, JidoFoundation.TaskPoolManager, :get_all_stats)
        assert is_map(stats)
        
        # Create a pool  
        result = call_service(sup_tree, JidoFoundation.TaskPoolManager, :create_pool,
          [:test_pool, %{max_concurrency: 4}])
        assert result == :ok
        
        # Execute batch operation
        {:ok, stream} = call_service(sup_tree, JidoFoundation.TaskPoolManager, :execute_batch,
          [:test_pool, [1, 2, 3], fn x -> x * 2 end, [timeout: 1000]])
        
        results = Enum.to_list(stream)
        assert length(results) == 3
      end
  """
  @spec call_service(map(), module(), atom() | tuple(), list(), timeout()) :: 
    term() | {:error, term()}
  def call_service(supervision_context, service_module, function, args \\ [], timeout \\ 5000) do
    case find_service_pid(supervision_context, service_module) do
      {:ok, pid} ->
        try do
          call_term = prepare_call_term(function, args)
          GenServer.call(pid, call_term, timeout)
        catch
          :exit, {:timeout, _} ->
            {:error, {:call_timeout, service_module, timeout}}
          :exit, {:noproc, _} ->
            {:error, {:service_not_alive, service_module}}
          :exit, reason ->
            {:error, {:call_failed, service_module, reason}}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Cast a message to a JidoFoundation service in isolated test environment.
  
  Sends an asynchronous message to a service without waiting for a response.
  This is useful for configuration updates, notifications, or fire-and-forget operations.
  
  ## Parameters
  
  - `supervision_context` - The supervision context from test setup
  - `service_module` - The service module to cast to
  - `message` - Message term to send
  
  ## Returns
  
  - `:ok` - Message cast successfully
  - `{:error, {:service_not_found, module}}` - Service not found
  - `{:error, {:service_not_alive, module}}` - Service process dead
  
  ## Examples
  
      test "service configuration", %{supervision_tree: sup_tree} do
        # Update service configuration
        :ok = cast_service(sup_tree, JidoFoundation.TaskPoolManager, 
          {:update_config, %{default_timeout: 10000}})
        
        # Send notification
        :ok = cast_service(sup_tree, JidoFoundation.CoordinationManager,
          {:agent_status_update, agent_pid, :healthy})
      end
  """
  @spec cast_service(map(), module(), term()) :: :ok | {:error, term()}
  def cast_service(supervision_context, service_module, message) do
    case find_service_pid(supervision_context, service_module) do
      {:ok, pid} ->
        try do
          GenServer.cast(pid, message)
          :ok
        catch
          :exit, {:noproc, _} ->
            {:error, {:service_not_alive, service_module}}
          :exit, reason ->
            {:error, {:cast_failed, service_module, reason}}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  @doc """
  Find and return the PID of a service in the isolated supervision tree.
  
  This is a lower-level function that looks up service PIDs directly from the
  test registry. Most tests should use `call_service/4` or `cast_service/3` instead.
  
  ## Parameters
  
  - `supervision_context` - The supervision context from test setup
  - `service_module` - The service module to find
  
  ## Returns
  
  - `{:ok, pid}` - Service found and alive
  - `{:error, {:service_not_found, module}}` - Service not registered
  - `{:error, {:service_not_alive, module}}` - Service registered but dead
  - `{:error, {:invalid_context, reason}}` - Invalid supervision context
  
  ## Examples
  
      test "direct service access", %{supervision_tree: sup_tree} do
        {:ok, task_pid} = find_service_pid(sup_tree, JidoFoundation.TaskPoolManager)
        assert is_pid(task_pid)
        assert Process.alive?(task_pid)
      end
  """
  @spec find_service_pid(map(), module()) :: {:ok, pid()} | {:error, term()}
  def find_service_pid(supervision_context, service_module) do
    case validate_supervision_context(supervision_context) do
      :ok ->
        registry = supervision_context.registry
        
        case Registry.lookup(registry, {:service, service_module}) do
          [{pid, _metadata}] when is_pid(pid) ->
            if Process.alive?(pid) do
              {:ok, pid}
            else
              {:error, {:service_not_alive, service_module}}
            end
            
          [] ->
            {:error, {:service_not_found, service_module}}
            
          other ->
            Logger.warning("Unexpected registry lookup result for #{service_module}: #{inspect(other)}")
            {:error, {:unexpected_registry_result, service_module, other}}
        end
        
      {:error, reason} ->
        {:error, {:invalid_context, reason}}
    end
  end
  
  @doc """
  List all services available in the isolated supervision tree.
  
  Returns information about all registered services, including their PIDs,
  registration metadata, and alive status.
  
  ## Parameters
  
  - `supervision_context` - The supervision context from test setup
  
  ## Returns
  
  - `{:ok, services}` - List of service information maps
  - `{:error, reason}` - Failed to list services
  
  Each service info map contains:
  - `:module` - Service module name
  - `:pid` - Service process PID
  - `:alive` - Whether process is alive
  - `:metadata` - Registration metadata
  
  ## Examples
  
      test "service inventory", %{supervision_tree: sup_tree} do
        {:ok, services} = list_services(sup_tree)
        
        service_modules = Enum.map(services, & &1.module)
        assert JidoFoundation.TaskPoolManager in service_modules
        assert JidoFoundation.SystemCommandManager in service_modules
        
        # Check all services are alive
        all_alive = Enum.all?(services, & &1.alive)
        assert all_alive, "Some services are not alive"
      end
  """
  @spec list_services(map()) :: {:ok, [map()]} | {:error, term()}
  def list_services(supervision_context) do
    case validate_supervision_context(supervision_context) do
      :ok ->
        registry = supervision_context.registry
        
        try do
          # Get all registry entries that match the service pattern
          service_entries = Registry.select(registry, [
            # Match pattern: {{:service, module}, pid, metadata}
            {{{:service, :"$1"}, :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}
          ])
          
          services = for {module, pid, metadata} <- service_entries do
            %{
              module: module,
              pid: pid,
              alive: Process.alive?(pid),
              metadata: metadata
            }
          end
          
          {:ok, services}
        rescue
          error ->
            {:error, {:registry_error, error}}
        end
        
      {:error, reason} ->
        {:error, {:invalid_context, reason}}
    end
  end
  
  @doc """
  Wait for a service to become available in the isolated supervision tree.
  
  This is useful during test setup or after service restarts to ensure a service
  is ready before proceeding with test operations.
  
  ## Parameters
  
  - `supervision_context` - The supervision context from test setup
  - `service_module` - The service module to wait for
  - `timeout` - Maximum time to wait in milliseconds (default: 5000)
  - `check_interval` - How often to check in milliseconds (default: 100)
  
  ## Returns
  
  - `{:ok, pid}` - Service became available
  - `{:error, :timeout}` - Service not available within timeout
  - `{:error, reason}` - Other error
  
  ## Examples
  
      test "wait for restart", %{supervision_tree: sup_tree} do
        {:ok, old_pid} = find_service_pid(sup_tree, JidoFoundation.TaskPoolManager)
        Process.exit(old_pid, :kill)
        
        # Wait for supervisor to restart the service
        {:ok, new_pid} = wait_for_service(sup_tree, JidoFoundation.TaskPoolManager, 8000)
        assert new_pid != old_pid
        assert Process.alive?(new_pid)
      end
  """
  @spec wait_for_service(map(), module(), timeout(), pos_integer()) :: 
    {:ok, pid()} | {:error, term()}
  def wait_for_service(supervision_context, service_module, timeout \\ 5000, check_interval \\ 100) do
    end_time = System.monotonic_time(:millisecond) + timeout
    
    wait_for_service_loop(supervision_context, service_module, end_time, check_interval)
  end
  
  @doc """
  Call multiple services in parallel and collect results.
  
  This is useful for gathering information from multiple services simultaneously
  or coordinating operations across services.
  
  ## Parameters
  
  - `supervision_context` - The supervision context from test setup
  - `service_calls` - List of `{service_module, function, args}` tuples
  - `timeout` - Maximum time for all calls (default: 5000)
  
  ## Returns
  
  - `{:ok, results}` - All calls completed, results in same order as input
  - `{:error, reason}` - At least one call failed
  
  Results are maps with `:module`, `:result`, and `:status` keys.
  
  ## Examples
  
      test "parallel service calls", %{supervision_tree: sup_tree} do
        calls = [
          {JidoFoundation.TaskPoolManager, :get_all_stats, []},
          {JidoFoundation.SystemCommandManager, :get_stats, []},
          {JidoFoundation.CoordinationManager, :get_status, []}
        ]
        
        {:ok, results} = call_services_parallel(sup_tree, calls)
        
        assert length(results) == 3
        assert Enum.all?(results, & &1.status == :ok)
      end
  """
  @spec call_services_parallel(map(), [{module(), atom(), list()}], timeout()) :: 
    {:ok, [map()]} | {:error, term()}
  def call_services_parallel(supervision_context, service_calls, timeout \\ 5000) do
    case validate_supervision_context(supervision_context) do
      :ok ->
        tasks = for {service_module, function, args} <- service_calls do
          Task.async(fn ->
            case call_service(supervision_context, service_module, function, args, timeout) do
              {:error, reason} ->
                %{module: service_module, status: :error, result: reason}
              result ->
                %{module: service_module, status: :ok, result: result}
            end
          end)
        end
        
        try do
          results = Task.await_many(tasks, timeout)
          
          # Check if any calls failed
          failures = Enum.filter(results, & &1.status == :error)
          if failures == [] do
            {:ok, results}
          else
            {:error, {:some_calls_failed, failures}}
          end
        catch
          :exit, reason ->
            {:error, {:parallel_calls_failed, reason}}
        end
        
      {:error, reason} ->
        {:error, {:invalid_context, reason}}
    end
  end
  
  # Private helper functions
  
  @spec validate_supervision_context(map()) :: :ok | {:error, term()}
  defp validate_supervision_context(supervision_context) do
    cond do
      not is_map(supervision_context) ->
        {:error, :context_not_map}
      
      not Map.has_key?(supervision_context, :registry) ->
        {:error, :missing_registry}
      
      not is_atom(supervision_context.registry) ->
        {:error, :registry_not_atom}
      
      Process.whereis(supervision_context.registry) == nil ->
        {:error, :registry_not_running}
      
      true ->
        :ok
    end
  end
  
  @spec prepare_call_term(atom() | tuple(), list()) :: term()
  defp prepare_call_term(function, args) when is_atom(function) and args == [] do
    # Simple function call: call_service(ctx, Module, :function)
    function
  end
  
  defp prepare_call_term(function, args) when is_atom(function) and is_list(args) do
    # Function with args: call_service(ctx, Module, :function, [arg1, arg2])
    {function, args}
  end
  
  defp prepare_call_term(call_tuple, []) when is_tuple(call_tuple) do
    # Direct tuple call: call_service(ctx, Module, {:function, [args]})
    call_tuple
  end
  
  defp prepare_call_term(call_tuple, args) when is_tuple(call_tuple) and args != [] do
    # This case is ambiguous - log a warning and use the tuple
    Logger.warning("Ambiguous call: both tuple #{inspect(call_tuple)} and args #{inspect(args)} provided. Using tuple.")
    call_tuple
  end
  
  @spec wait_for_service_loop(map(), module(), integer(), pos_integer()) :: 
    {:ok, pid()} | {:error, term()}
  defp wait_for_service_loop(supervision_context, service_module, end_time, check_interval) do
    case find_service_pid(supervision_context, service_module) do
      {:ok, pid} ->
        {:ok, pid}
        
      {:error, _reason} ->
        current_time = System.monotonic_time(:millisecond)
        if current_time >= end_time do
          {:error, :timeout}
        else
          Process.sleep(check_interval)
          wait_for_service_loop(supervision_context, service_module, end_time, check_interval)
        end
    end
  end
end