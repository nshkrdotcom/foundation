defmodule Foundation.SupervisionTestHelpers do
  @moduledoc """
  Helper functions for testing supervision crash recovery with isolated supervision trees.

  Provides utilities for:
  - Creating isolated JidoFoundation supervision trees
  - Accessing services within test supervision context
  - Monitoring process lifecycle in test environment
  - Verifying supervision behavior without global contamination

  ## Usage with UnifiedTestFoundation

  This module is designed to work with `Foundation.UnifiedTestFoundation` in 
  `:supervision_testing` mode:

      defmodule MySupervisionTest do
        use Foundation.UnifiedTestFoundation, :supervision_testing
        
        test "crash recovery", %{supervision_tree: sup_tree} do
          {:ok, task_pid} = get_service(sup_tree, :task_pool_manager)
          Process.exit(task_pid, :kill)
          
          {:ok, new_pid} = wait_for_service_restart(sup_tree, :task_pool_manager, task_pid)
          assert new_pid != task_pid
        end
      end

  ## Service Access

  Services are accessed through isolated registries using service names:
  - `:task_pool_manager` - JidoFoundation.TaskPoolManager
  - `:system_command_manager` - JidoFoundation.SystemCommandManager
  - `:coordination_manager` - JidoFoundation.CoordinationManager
  - `:scheduler_manager` - JidoFoundation.SchedulerManager

  ## Supervision Order

  The helpers understand the supervision order from JidoSystem.Application:
  1. SchedulerManager (starts first)
  2. TaskPoolManager
  3. SystemCommandManager
  4. CoordinationManager (starts last)

  With `:rest_for_one` strategy, killing TaskPoolManager will restart
  SystemCommandManager and CoordinationManager, but not SchedulerManager.
  """

  import Foundation.AsyncTestHelpers
  import ExUnit.Assertions
  require Logger

  @typedoc """
  Service name atoms used for accessing services in isolated supervision trees.
  
  Maps to the corresponding JidoFoundation service modules:
  - :task_pool_manager -> JidoFoundation.TaskPoolManager
  - :system_command_manager -> JidoFoundation.SystemCommandManager
  - :coordination_manager -> JidoFoundation.CoordinationManager
  - :scheduler_manager -> JidoFoundation.SchedulerManager
  """
  @type service_name :: 
          :task_pool_manager 
          | :system_command_manager 
          | :coordination_manager 
          | :scheduler_manager

  @typedoc """
  Result of service lookup operations.
  
  - {:ok, pid} - Service found and running
  - {:error, :service_not_found} - Service not registered
  - {:error, :service_not_alive} - Service registered but process not alive
  - {:error, {:unknown_service, atom}} - Service name not recognized
  """
  @type service_result :: 
          {:ok, pid()} 
          | {:error, :service_not_found | :service_not_alive | {:unknown_service, atom()}}

  @typedoc """
  Monitor information for process lifecycle tracking.
  
  Maps service names to {pid, monitor_ref} tuples for tracking
  process termination and restart events.
  """
  @type monitor_map :: %{service_name() => {pid(), reference()}}

  @typedoc """
  Service call result from isolated service interactions.
  
  - term() - Successful service call result
  - {:error, {:service_not_available, service_name, reason}} - Service call failed
  """
  @type service_call_result :: 
          term() 
          | {:error, {:service_not_available, service_name(), term()}}

  @typedoc """
  Import the supervision context type from the setup module.
  """
  @type supervision_context :: Foundation.SupervisionTestSetup.supervision_context()

  # Service name to module mappings for isolated testing
  # These map to the original JidoFoundation modules for registry lookup
  @service_modules %{
    task_pool_manager: JidoFoundation.TaskPoolManager,
    system_command_manager: JidoFoundation.SystemCommandManager,
    coordination_manager: JidoFoundation.CoordinationManager,
    scheduler_manager: JidoFoundation.SchedulerManager
  }

  # Supervision order from JidoSystem.Application (critical for rest_for_one testing)
  @supervision_order [
    :scheduler_manager,
    :task_pool_manager,
    :system_command_manager,
    :coordination_manager
  ]

  @spec get_service(supervision_context(), service_name()) :: service_result()
  @doc """
  Get a service PID from the test supervision tree.

  ## Parameters

  - `supervision_context` - The supervision context from test setup
  - `service_name` - Atom representing the service (e.g., `:task_pool_manager`)

  ## Returns

  - `{:ok, pid}` - If service is found and running
  - `{:error, :service_not_found}` - If service is not registered
  - `{:error, :service_not_alive}` - If service is registered but not alive

  ## Examples

      test "service access", %{supervision_tree: sup_tree} do
        {:ok, task_pid} = get_service(sup_tree, :task_pool_manager)
        assert is_pid(task_pid)
        assert Process.alive?(task_pid)
      end
  """
  def get_service(supervision_context, service_name) do
    service_module = Map.get(@service_modules, service_name)

    if service_module do
      case supervision_context.registry
           |> Registry.lookup({:service, service_module}) do
        [{pid, _}] when is_pid(pid) ->
          if Process.alive?(pid) do
            {:ok, pid}
          else
            {:error, :service_not_alive}
          end

        [] ->
          {:error, :service_not_found}
      end
    else
      {:error, {:unknown_service, service_name}}
    end
  end

  @spec wait_for_service_restart(supervision_context(), service_name(), pid(), timeout()) :: 
          {:ok, pid()}
  @doc """
  Wait for a service to restart after crash in isolated supervision tree.

  This function polls the registry until the service is available with a 
  different PID than the original, indicating a successful restart.

  ## Parameters

  - `supervision_context` - The supervision context from test setup
  - `service_name` - Atom representing the service
  - `old_pid` - The PID of the crashed service
  - `timeout` - Maximum time to wait in milliseconds (default: 5000)

  ## Returns

  - `{:ok, new_pid}` - Service restarted with new PID
  - Raises ExUnit.AssertionError on timeout

  ## Examples

      test "restart behavior", %{supervision_tree: sup_tree} do
        {:ok, old_pid} = get_service(sup_tree, :task_pool_manager)
        Process.exit(old_pid, :kill)
        
        {:ok, new_pid} = wait_for_service_restart(sup_tree, :task_pool_manager, old_pid)
        assert new_pid != old_pid
        assert Process.alive?(new_pid)
      end
  """
  def wait_for_service_restart(supervision_context, service_name, old_pid, timeout \\ 5000) do
    wait_for(
      fn ->
        case get_service(supervision_context, service_name) do
          {:ok, new_pid} when new_pid != old_pid and is_pid(new_pid) ->
            {:ok, new_pid}

          _ ->
            nil
        end
      end,
      timeout
    )
  end

  @spec monitor_all_services(supervision_context()) :: monitor_map()
  @doc """
  Monitor all processes in supervision tree for proper shutdown cascade testing.

  Returns a map of service_name => {pid, monitor_ref} for easy assertion.
  This is useful for testing `:rest_for_one` supervision behavior where
  killing one service should cause specific other services to restart.

  ## Parameters

  - `supervision_context` - The supervision context from test setup

  ## Returns

  - Map of `%{service_name => {pid, monitor_ref}}`

  ## Examples

      test "monitor all services", %{supervision_tree: sup_tree} do
        monitors = monitor_all_services(sup_tree)
        
        assert Map.has_key?(monitors, :task_pool_manager)
        assert Map.has_key?(monitors, :system_command_manager)
        
        {pid, ref} = monitors[:task_pool_manager]
        assert is_pid(pid)
        assert is_reference(ref)
      end
  """
  def monitor_all_services(supervision_context) do
    services = Map.keys(@service_modules)

    for service <- services, into: %{} do
      case get_service(supervision_context, service) do
        {:ok, pid} ->
          ref = Process.monitor(pid)
          {service, {pid, ref}}

        {:error, _reason} ->
          Logger.warning("Service #{service} not available for monitoring")
          {service, {nil, nil}}
      end
    end
    |> Enum.filter(fn {_service, {pid, _ref}} -> pid != nil end)
    |> Enum.into(%{})
  end

  @spec verify_rest_for_one_cascade(monitor_map(), service_name()) :: :ok
  @doc """
  Verify rest_for_one supervision behavior in isolated environment.

  This function understands the supervision order from JidoSystem.Application
  and verifies that when a service crashes, only services that start after it
  in the supervision tree are restarted (rest_for_one behavior).

  ## Supervision Order

  1. SchedulerManager
  2. TaskPoolManager  
  3. SystemCommandManager
  4. CoordinationManager

  ## Parameters

  - `monitors` - Map from `monitor_all_services/1`
  - `crashed_service` - The service that was intentionally crashed

  ## Examples

      test "rest_for_one cascade", %{supervision_tree: sup_tree} do
        monitors = monitor_all_services(sup_tree)
        
        # Kill TaskPoolManager 
        {task_pid, _} = monitors[:task_pool_manager]
        Process.exit(task_pid, :kill)
        
        # Verify cascade: SystemCommandManager + CoordinationManager restart
        # SchedulerManager should NOT restart (starts before TaskPoolManager)
        verify_rest_for_one_cascade(monitors, :task_pool_manager)
      end
  """
  def verify_rest_for_one_cascade(monitors, crashed_service) do
    crashed_index = Enum.find_index(@supervision_order, &(&1 == crashed_service))

    if crashed_index == nil do
      raise ArgumentError,
            "Unknown service: #{crashed_service}. Expected one of: #{inspect(Map.keys(@service_modules))}"
    end

    # Services started before crashed service should remain alive
    services_before = Enum.take(@supervision_order, crashed_index)
    # Services started after crashed service should restart
    services_after = Enum.drop(@supervision_order, crashed_index + 1)

    # Wait for crashed service DOWN message
    case Map.get(monitors, crashed_service) do
      {crashed_pid, crashed_ref} when is_pid(crashed_pid) ->
        receive do
          {:DOWN, ^crashed_ref, :process, ^crashed_pid, :killed} ->
            :ok
        after
          2000 ->
            raise ExUnit.AssertionError,
                  "Expected #{crashed_service} to be killed within 2000ms"
        end

      _ ->
        raise ArgumentError, "Service #{crashed_service} was not being monitored"
    end

    # Wait for dependent services DOWN messages (supervisor shutdown)
    for service <- services_after do
      case Map.get(monitors, service) do
        {service_pid, service_ref} when is_pid(service_pid) ->
          receive do
            {:DOWN, ^service_ref, :process, ^service_pid, down_reason} ->
              assert down_reason in [:shutdown, :killed],
                     "Expected #{service} to be shut down by supervisor, got: #{down_reason}"
          after
            2000 ->
              raise ExUnit.AssertionError,
                    "Expected #{service} to shut down within 2000ms"
          end

        _ ->
          # Service wasn't running, that's ok
          :ok
      end
    end

    # Verify services before crashed service remain alive
    for service <- services_before do
      case Map.get(monitors, service) do
        {service_pid, _service_ref} when is_pid(service_pid) ->
          assert Process.alive?(service_pid),
                 "#{service} should remain alive (started before crashed service #{crashed_service})"

        _ ->
          # Service wasn't running to begin with
          :ok
      end
    end

    :ok
  end

  @spec wait_for_services_restart(supervision_context(), %{service_name() => pid()}, timeout()) :: 
          {:ok, %{service_name() => pid()}}
  @doc """
  Wait for all services in a supervision tree to be restarted after a cascade.

  This is useful after calling `verify_rest_for_one_cascade/2` to wait for
  the supervisor to restart the affected services with new PIDs.

  ## Parameters

  - `supervision_context` - The supervision context from test setup
  - `old_pids` - Map of service_name => old_pid before restart
  - `timeout` - Maximum time to wait (default: 8000ms)

  ## Returns

  - `{:ok, new_pids}` - Map of service_name => new_pid after restart
  - Raises ExUnit.AssertionError on timeout

  ## Examples

      test "wait for restart", %{supervision_tree: sup_tree} do
        # Get initial PIDs
        {:ok, task_pid} = get_service(sup_tree, :task_pool_manager)
        {:ok, sys_pid} = get_service(sup_tree, :system_command_manager)
        old_pids = %{task_pool_manager: task_pid, system_command_manager: sys_pid}
        
        # Crash and wait for restart
        Process.exit(task_pid, :kill)
        {:ok, new_pids} = wait_for_services_restart(sup_tree, old_pids)
        
        assert new_pids.task_pool_manager != task_pid
        assert new_pids.system_command_manager != sys_pid
      end
  """
  def wait_for_services_restart(supervision_context, old_pids, timeout \\ 8000) do
    wait_for(
      fn ->
        new_pids =
          for {service, old_pid} <- old_pids, into: %{} do
            case get_service(supervision_context, service) do
              {:ok, new_pid} when new_pid != old_pid ->
                {service, new_pid}

              _ ->
                {service, nil}
            end
          end

        # Check if all services have new PIDs
        if Enum.all?(new_pids, fn {_service, pid} -> pid != nil end) do
          {:ok, new_pids}
        else
          nil
        end
      end,
      timeout
    )
  end

  @spec call_service(supervision_context(), service_name(), term(), timeout()) :: 
          service_call_result()
  @doc """
  Call a service function in isolated supervision tree.

  This is a convenience function for making GenServer calls to services
  in the isolated supervision context. It automatically looks up the
  service PID and makes the call.

  ## Parameters

  - `supervision_context` - The supervision context from test setup
  - `service_name` - Atom representing the service
  - `call_or_function` - GenServer call term or function atom
  - `timeout` - Call timeout (default: 5000ms)

  ## Examples

      test "service calls", %{supervision_tree: sup_tree} do
        # Call with function atom
        stats = call_service(sup_tree, :task_pool_manager, :get_all_stats)
        assert is_map(stats)
        
        # Call with tuple
        result = call_service(sup_tree, :task_pool_manager, 
          {:create_pool, [:test_pool, %{max_concurrency: 4}]})
        assert result == :ok
      end
  """
  def call_service(supervision_context, service_name, call_or_function, timeout \\ 5000) do
    case get_service(supervision_context, service_name) do
      {:ok, pid} ->
        case call_or_function do
          atom when is_atom(atom) ->
            GenServer.call(pid, atom, timeout)

          {function, args} when is_atom(function) and is_list(args) ->
            GenServer.call(pid, {function, args}, timeout)

          _ ->
            GenServer.call(pid, call_or_function, timeout)
        end

      {:error, reason} ->
        {:error, {:service_not_available, service_name, reason}}
    end
  end

  @spec cast_service(supervision_context(), service_name(), term()) :: 
          :ok | {:error, {:service_not_available, service_name(), term()}}
  @doc """
  Cast a message to a service in isolated supervision tree.

  Similar to `call_service/4` but for GenServer casts.

  ## Examples

      test "service casts", %{supervision_tree: sup_tree} do
        :ok = cast_service(sup_tree, :task_pool_manager, {:update_config, %{timeout: 10000}})
      end
  """
  def cast_service(supervision_context, service_name, message) do
    case get_service(supervision_context, service_name) do
      {:ok, pid} ->
        GenServer.cast(pid, message)
        :ok

      {:error, reason} ->
        {:error, {:service_not_available, service_name, reason}}
    end
  end

  @spec get_supervision_order() :: [service_name()]
  @doc """
  Get the supervision order for services.

  Returns the order in which services are started in the supervision tree.
  This is useful for understanding `:rest_for_one` behavior.

  ## Examples

      iex> Foundation.SupervisionTestHelpers.get_supervision_order()
      [:scheduler_manager, :task_pool_manager, :system_command_manager, :coordination_manager]
  """
  def get_supervision_order, do: @supervision_order

  @spec get_supported_services() :: [service_name()]
  @doc """
  Get all supported service names.

  ## Examples

      iex> Foundation.SupervisionTestHelpers.get_supported_services()
      [:task_pool_manager, :system_command_manager, :coordination_manager, :scheduler_manager]
  """
  def get_supported_services, do: Map.keys(@service_modules)

  @spec service_name_to_module(service_name()) :: module() | nil
  @doc """
  Convert service name to module.

  ## Examples

      iex> Foundation.SupervisionTestHelpers.service_name_to_module(:task_pool_manager)
      JidoFoundation.TaskPoolManager
  """
  def service_name_to_module(service_name), do: Map.get(@service_modules, service_name)

  @spec wait_for_services_ready(supervision_context(), [service_name()] | nil, timeout()) :: 
          [service_name()]
  @doc """
  Wait for a specific number of services to be available in the supervision context.

  This is useful during test setup to ensure all required services are ready
  before starting the actual test.

  ## Parameters

  - `supervision_context` - The supervision context from test setup
  - `service_names` - List of service names to wait for (default: all services)
  - `timeout` - Maximum time to wait (default: 10000ms)

  ## Examples

      setup do
        context = create_isolated_supervision()
        wait_for_services_ready(context, [:task_pool_manager, :system_command_manager])
        context
      end
  """
  def wait_for_services_ready(supervision_context, service_names \\ nil, timeout \\ 10000) do
    services_to_check = service_names || Map.keys(@service_modules)

    wait_for(
      fn ->
        ready_services =
          for service <- services_to_check do
            case get_service(supervision_context, service) do
              {:ok, _pid} -> service
              _ -> nil
            end
          end
          |> Enum.filter(& &1)

        if length(ready_services) == length(services_to_check) do
          ready_services
        else
          nil
        end
      end,
      timeout
    )
  end

  @spec validate_supervision_context(supervision_context()) :: 
          :ok | {:error, {:missing_fields, [atom()]}}
  @doc """
  Validate that the supervision context has the required structure.

  This is a helper for test setup validation to ensure the supervision
  context has all required fields.

  ## Examples

      test "context validation", %{supervision_tree: sup_tree} do
        assert validate_supervision_context(sup_tree) == :ok
      end
  """
  def validate_supervision_context(supervision_context) do
    required_fields = [:test_id, :registry, :registry_pid, :supervisor, :supervisor_pid]

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
      :ok
    else
      {:error, {:missing_fields, missing_fields}}
    end
  end
end
