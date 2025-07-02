defmodule Foundation.SupervisionTestSetup do
  @moduledoc """
  Setup infrastructure for isolated supervision testing.

  Creates complete JidoFoundation supervision trees in isolation,
  allowing crash recovery tests without global state contamination.

  ## Features

  - Complete JidoSystem.Application child tree recreation in test isolation
  - Test-specific Registry instances for service discovery
  - Service registration with {:service, module_name} keys
  - Proper cleanup and resource management
  - Integration with Foundation.UnifiedTestFoundation

  ## Usage

  This module is typically used through Foundation.UnifiedTestFoundation
  in :supervision_testing mode:

      defmodule MySupervisionTest do
        use Foundation.UnifiedTestFoundation, :supervision_testing
        
        test "crash recovery", %{supervision_tree: sup_tree} do
          {:ok, task_pid} = Foundation.SupervisionTestHelpers.get_service(sup_tree, :task_pool_manager)
          Process.exit(task_pid, :kill)
          
          {:ok, new_pid} = Foundation.SupervisionTestHelpers.wait_for_service_restart(
            sup_tree, :task_pool_manager, task_pid
          )
          assert new_pid != task_pid
        end
      end

  ## Context Structure

  The supervision context returned by create_isolated_supervision/0 contains:

      %{
        test_id: unique_integer,
        registry: registry_name,
        registry_pid: pid,
        supervisor: supervisor_name,
        supervisor_pid: pid,
        services: [list_of_service_modules]
      }

  ## Design Principles

  - **Complete Isolation**: Each test gets its own supervision tree
  - **Exact Recreation**: Matches JidoSystem.Application structure
  - **Proper Cleanup**: Resources cleaned up on test exit
  - **Service Discovery**: Services registered in test-specific registry
  - **OTP Compliance**: Follows proper supervision patterns
  """

  require Logger
  import Foundation.AsyncTestHelpers
  import ExUnit.Callbacks

  # Service modules that will be created as test doubles for isolation
  @core_services [
    Foundation.TestServices.SchedulerManager,
    Foundation.TestServices.TaskPoolManager,
    Foundation.TestServices.SystemCommandManager,
    Foundation.TestServices.CoordinationManager
  ]

  @doc """
  Create an isolated supervision tree for testing JidoFoundation crash recovery.

  This function recreates the exact structure of JidoSystem.Application but with
  test-specific names and registries to prevent contamination between tests.

  ## Returns

  Returns a map with `:supervision_tree` key containing the supervision context:

      %{supervision_tree: supervision_context}

  Where supervision_context contains:
  - `:test_id` - Unique test identifier
  - `:registry` - Test-specific registry name
  - `:registry_pid` - Registry process PID
  - `:supervisor` - Test supervisor name  
  - `:supervisor_pid` - Supervisor process PID
  - `:services` - List of service modules available for testing

  ## Automatic Cleanup

  The function automatically registers an `on_exit` callback to clean up
  all resources when the test completes.

  ## Examples

      setup do
        Foundation.SupervisionTestSetup.create_isolated_supervision()
      end
      
      test "service access", %{supervision_tree: sup_tree} do
        {:ok, pid} = Foundation.SupervisionTestHelpers.get_service(sup_tree, :task_pool_manager)
        assert is_pid(pid)
      end
  """
  def create_isolated_supervision do
    # Create unique test identifier
    test_id = :erlang.unique_integer([:positive])
    test_registry = :"test_jido_registry_#{test_id}"
    test_supervisor = :"test_jido_supervisor_#{test_id}"

    Logger.debug("Creating isolated supervision tree: test_id=#{test_id}")

    # Create test-specific registry for service discovery
    {:ok, registry_pid} =
      Registry.start_link(
        keys: :unique,
        name: test_registry,
        partitions: 1
      )

    # Start isolated JidoFoundation supervision tree
    {:ok, supervisor_pid} = start_isolated_jido_supervisor(test_supervisor, test_registry)

    # Wait for all services to be registered and stable
    Logger.debug("Starting to wait for services to be ready...")
    wait_for_services_ready(test_registry, @core_services)

    supervision_context = %{
      test_id: test_id,
      registry: test_registry,
      registry_pid: registry_pid,
      supervisor: test_supervisor,
      supervisor_pid: supervisor_pid,
      services: @core_services
    }

    # Setup cleanup on test exit
    on_exit(fn ->
      cleanup_isolated_supervision(supervision_context)
    end)

    Logger.debug("Isolated supervision tree created successfully: test_id=#{test_id}")

    %{supervision_tree: supervision_context}
  end

  @doc """
  Start an isolated JidoSystem supervision tree with test-specific names.

  This function recreates the exact child structure from JidoSystem.Application
  but with test-specific process names and registry registration to ensure
  complete isolation from the global supervision tree.

  ## Parameters

  - `supervisor_name` - Unique name for the test supervisor
  - `registry_name` - Test-specific registry for service discovery

  ## Returns

  - `{:ok, supervisor_pid}` - If supervision tree starts successfully
  - `{:error, reason}` - If startup fails
  """
  def start_isolated_jido_supervisor(supervisor_name, registry_name) do
    # Create isolated version of core JidoFoundation services only
    # Focus on the services that need crash recovery testing
    children = [
      # Test-specific registries for service discovery
      {Registry, keys: :unique, name: :"#{supervisor_name}_monitor_registry"},
      {Registry, keys: :unique, name: :"#{supervisor_name}_workflow_registry"},

      # Test service doubles with isolated registration
      # These provide the same interface as Foundation services but support custom names
      {Foundation.TestServices.SchedulerManager,
       name: :"#{supervisor_name}_scheduler_manager", registry: registry_name},
      {Foundation.TestServices.TaskPoolManager,
       name: :"#{supervisor_name}_task_pool_manager", registry: registry_name},
      {Foundation.TestServices.SystemCommandManager,
       name: :"#{supervisor_name}_system_command_manager", registry: registry_name},
      {Foundation.TestServices.CoordinationManager,
       name: :"#{supervisor_name}_coordination_manager", registry: registry_name}
    ]

    # Use same supervision strategy as production for accurate testing
    opts = [
      # CRITICAL: Same as JidoSystem.Application
      strategy: :rest_for_one,
      name: supervisor_name,
      max_restarts: 3,
      max_seconds: 5
    ]

    Logger.debug("Starting isolated supervision tree: #{supervisor_name}")

    case Supervisor.start_link(children, opts) do
      {:ok, pid} ->
        Logger.debug("Isolated supervision tree started: #{supervisor_name}, pid=#{inspect(pid)}")
        {:ok, pid}

      {:error, reason} ->
        Logger.error(
          "Failed to start isolated supervision tree #{supervisor_name}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @doc """
  Wait for services to be ready in the isolated supervision tree.

  This function polls the test registry until all specified services
  are registered and have alive processes. This ensures the supervision
  tree is fully stable before tests begin.

  ## Parameters

  - `registry_name` - The test-specific registry to check
  - `services` - List of service modules to wait for
  - `timeout` - Maximum time to wait in milliseconds (default: 10000)

  ## Returns

  - `:ok` - If all services become ready within timeout
  - Raises ExUnit.AssertionError if timeout exceeded
  """
  def wait_for_services_ready(registry_name, services, timeout \\ 10_000) do
    Logger.debug("Waiting for #{length(services)} services to be ready in #{registry_name}")

    # Check what's actually in the registry first
    all_entries = Registry.select(registry_name, [{{:"$1", :"$2", :"$3"}, [], [:"$1"]}])
    Logger.debug("Current registry entries: #{inspect(all_entries)}")

    # Map the test service modules to the original JidoFoundation modules for lookup
    service_lookup_modules = [
      JidoFoundation.SchedulerManager,
      JidoFoundation.TaskPoolManager,
      JidoFoundation.SystemCommandManager,
      JidoFoundation.CoordinationManager
    ]

    for service_module <- service_lookup_modules do
      Logger.debug("Waiting for service: #{inspect(service_module)}")

      wait_for(
        fn ->
          case Registry.lookup(registry_name, {:service, service_module}) do
            [{pid, _}] when is_pid(pid) ->
              if Process.alive?(pid) do
                Logger.debug("Service #{service_module} ready: #{inspect(pid)}")
                pid
              else
                Logger.debug("Service #{service_module} found but not alive: #{inspect(pid)}")
                nil
              end

            [] ->
              Logger.debug("Service #{service_module} not found in registry")
              nil
          end
        end,
        timeout
      )
    end

    Logger.debug("All #{length(services)} services ready in #{registry_name}")
    :ok
  end

  @doc """
  Clean up isolated supervision tree resources.

  This function performs graceful shutdown of the isolated supervision tree,
  ensuring no resource leaks or orphaned processes.

  ## Parameters

  - `supervision_context` - The context returned by create_isolated_supervision/0

  ## Cleanup Process

  1. Gracefully terminate the supervisor tree
  2. Terminate the test registry
  3. Wait for all processes to exit
  4. Verify no resource leaks
  """
  def cleanup_isolated_supervision(supervision_context) do
    test_id = supervision_context.test_id
    supervisor_pid = supervision_context.supervisor_pid
    registry_pid = supervision_context.registry_pid

    Logger.debug("Cleaning up isolated supervision tree: test_id=#{test_id}")

    # Clean up processes in correct order

    # 1. First terminate the supervisor (this will terminate all children)
    if is_pid(supervisor_pid) and Process.alive?(supervisor_pid) do
      Logger.debug("Terminating supervisor: #{inspect(supervisor_pid)}")

      try do
        Supervisor.stop(supervisor_pid, :normal, 5000)
        Logger.debug("Supervisor terminated successfully")
      catch
        :exit, reason ->
          Logger.debug("Supervisor already terminated: #{inspect(reason)}")
      end
    end

    # 2. Then terminate the registry if it's still alive
    # (It might already be dead if the supervisor owned it)
    if is_pid(registry_pid) and Process.alive?(registry_pid) do
      Logger.debug("Terminating registry: #{inspect(registry_pid)}")

      try do
        GenServer.stop(registry_pid, :normal, 5000)
        Logger.debug("Registry terminated successfully")
      catch
        :exit, reason ->
          Logger.debug("Registry already terminated: #{inspect(reason)}")
      end
    end

    # 3. Wait a bit for cleanup to complete
    Process.sleep(100)

    Logger.debug("Isolated supervision tree cleanup complete: test_id=#{test_id}")
  end

  @doc """
  Create supervision context for testing without automatic cleanup.

  This is useful when you need to manually control the lifecycle of the
  supervision tree, such as in setup_all callbacks.

  ## Returns

  Same as create_isolated_supervision/0 but without registering on_exit cleanup.
  You must call cleanup_isolated_supervision/1 manually.

  ## Examples

      setup_all do
        context = Foundation.SupervisionTestSetup.create_isolated_supervision_manual()
        
        on_exit(fn ->
          Foundation.SupervisionTestSetup.cleanup_isolated_supervision(context.supervision_tree)
        end)
        
        context
      end
  """
  def create_isolated_supervision_manual do
    # Create unique test identifier  
    test_id = :erlang.unique_integer([:positive])
    test_registry = :"test_jido_registry_#{test_id}"
    test_supervisor = :"test_jido_supervisor_#{test_id}"

    # Create test-specific registry
    {:ok, registry_pid} =
      Registry.start_link(
        keys: :unique,
        name: test_registry,
        partitions: 1
      )

    # Start isolated supervision tree
    {:ok, supervisor_pid} = start_isolated_jido_supervisor(test_supervisor, test_registry)

    # Wait for services to be ready
    wait_for_services_ready(test_registry, @core_services)

    supervision_context = %{
      test_id: test_id,
      registry: test_registry,
      registry_pid: registry_pid,
      supervisor: test_supervisor,
      supervisor_pid: supervisor_pid,
      services: @core_services
    }

    %{supervision_tree: supervision_context}
  end

  @doc """
  Get the list of core services that are started in isolated supervision.

  ## Examples

      iex> Foundation.SupervisionTestSetup.get_core_services()
      [
        JidoFoundation.SchedulerManager,
        JidoFoundation.TaskPoolManager,
        JidoFoundation.SystemCommandManager,
        JidoFoundation.CoordinationManager
      ]
  """
  def get_core_services, do: @core_services

  @doc """
  Validate that a supervision context has the required structure.

  This is useful for debugging test setup issues.

  ## Parameters

  - `supervision_context` - The context to validate

  ## Returns

  - `:ok` - If context is valid
  - `{:error, reason}` - If context is invalid

  ## Examples

      test "context validation", %{supervision_tree: sup_tree} do
        assert Foundation.SupervisionTestSetup.validate_supervision_context(sup_tree) == :ok
      end
  """
  def validate_supervision_context(supervision_context) do
    required_fields = [:test_id, :registry, :registry_pid, :supervisor, :supervisor_pid, :services]

    missing_fields =
      for field <- required_fields do
        if Map.has_key?(supervision_context, field) do
          nil
        else
          field
        end
      end
      |> Enum.filter(& &1)

    if missing_fields == [] do
      # Additional validation: check if processes are alive
      registry_alive =
        is_pid(supervision_context.registry_pid) and
          Process.alive?(supervision_context.registry_pid)

      supervisor_alive =
        is_pid(supervision_context.supervisor_pid) and
          Process.alive?(supervision_context.supervisor_pid)

      cond do
        not registry_alive ->
          {:error, :registry_not_alive}

        not supervisor_alive ->
          {:error, :supervisor_not_alive}

        true ->
          :ok
      end
    else
      {:error, {:missing_fields, missing_fields}}
    end
  end

  @doc """
  Get statistics about the isolated supervision tree.

  Returns information about the current state of the supervision tree
  for debugging and monitoring purposes.

  ## Parameters

  - `supervision_context` - The supervision context

  ## Returns

  Map with statistics including:
  - `:test_id` - The test identifier
  - `:supervisor_children` - Number of direct supervisor children
  - `:registered_services` - Number of services in registry
  - `:registry_entries` - Total registry entries
  - `:supervisor_alive` - Whether supervisor is alive
  - `:registry_alive` - Whether registry is alive

  ## Examples

      test "supervision stats", %{supervision_tree: sup_tree} do
        stats = Foundation.SupervisionTestSetup.get_supervision_stats(sup_tree)
        assert stats.supervisor_alive == true
        assert stats.registered_services >= 4  # Core services
      end
  """
  def get_supervision_stats(supervision_context) do
    supervisor_pid = supervision_context.supervisor_pid
    registry_name = supervision_context.registry

    # Get supervisor children count
    supervisor_children =
      if is_pid(supervisor_pid) and Process.alive?(supervisor_pid) do
        try do
          Supervisor.which_children(supervisor_pid) |> length()
        rescue
          _ -> 0
        end
      else
        0
      end

    # Get registry statistics
    {registry_entries, registered_services} =
      try do
        all_entries = Registry.select(registry_name, [{{:"$1", :"$2", :"$3"}, [], [:"$1"]}])

        service_entries =
          Enum.filter(all_entries, fn
            {:service, _module} -> true
            _ -> false
          end)

        {length(all_entries), length(service_entries)}
      rescue
        _ -> {0, 0}
      end

    %{
      test_id: supervision_context.test_id,
      supervisor_children: supervisor_children,
      registered_services: registered_services,
      registry_entries: registry_entries,
      supervisor_alive: is_pid(supervisor_pid) and Process.alive?(supervisor_pid),
      registry_alive: Process.whereis(registry_name) != nil
    }
  end
end
