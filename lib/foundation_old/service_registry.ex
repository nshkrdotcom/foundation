defmodule Foundation.ServiceRegistry do
  @moduledoc """
  High-level service registration API for Foundation layer.

  Provides a clean interface for service registration and discovery,
  wrapping the lower-level ProcessRegistry with error handling,
  logging, and convenience functions.

  ## Examples

      # Register a service
      :ok = ServiceRegistry.register(:production, :config_server, self())

      # Lookup a service
      {:ok, pid} = ServiceRegistry.lookup(:production, :config_server)

      # List services in a namespace
      [:config_server, :event_store] = ServiceRegistry.list_services(:production)
  """

  require Logger

  alias Foundation.ProcessRegistry
  alias Foundation.Types.Error

  @type namespace :: :production | {:test, reference()}
  @type service_name ::
          :config_server
          | :event_store
          | :telemetry_service
          | :test_supervisor
          | {:agent, atom()}
          | atom()
  @type registration_result :: :ok | {:error, {:already_registered, pid()}}
  @type lookup_result :: {:ok, pid()} | {:error, Error.t()}

  @doc """
  Register a service in the given namespace with error handling and logging.

  ## Parameters
  - `namespace`: The namespace for service isolation
  - `service`: The service name to register
  - `pid`: The process PID to register

  ## Returns
  - `:ok` if registration succeeds
  - `{:error, reason}` if registration fails

  ## Examples

      iex> ServiceRegistry.register(:production, :config_server, self())
      :ok

      iex> ServiceRegistry.register(:production, :config_server, self())
      {:error, {:already_registered, #PID<0.123.0>}}
  """
  @spec register(namespace(), service_name(), pid()) :: registration_result()
  def register(namespace, service, pid) when is_pid(pid) do
    Logger.debug("Registering service #{inspect(service)} in namespace #{inspect(namespace)}")

    result =
      case ProcessRegistry.register(namespace, service, pid) do
        :ok ->
          Logger.info(
            "Successfully registered service #{inspect(service)} in namespace #{inspect(namespace)}"
          )

          :ok

        {:error, {:already_registered, existing_pid}} = error ->
          Logger.warning(
            "Failed to register service #{inspect(service)} in namespace #{inspect(namespace)}: " <>
              "already registered to PID #{inspect(existing_pid)}"
          )

          error
      end

    # Emit telemetry
    emit_registration_telemetry(namespace, service, result)

    result
  end

  @doc """
  Lookup a service with optional error handling and telemetry.

  Includes telemetry events for monitoring Registry performance and usage patterns.

  ## Parameters
  - `namespace`: The namespace to search in
  - `service`: The service name to lookup

  ## Returns
  - `{:ok, pid()}` if service is found and healthy
  - `{:error, Error.t()}` if service not found or unhealthy

  ## Telemetry Events
  - `[:foundation, :foundation, :registry, :lookup]` - Emitted for all lookup operations
    - Measurements: `%{duration: integer()}` (in native time units)
    - Metadata: `%{namespace: term(), service: atom(), result: :ok | :error}`

  ## Examples

      {:ok, pid} = ServiceRegistry.lookup(:production, :config_server)
      {:error, %Error{}} = ServiceRegistry.lookup(:production, :nonexistent)
  """
  @spec lookup(namespace(), service_name()) :: lookup_result()
  def lookup(namespace, service) do
    start_time = System.monotonic_time()

    result =
      case ProcessRegistry.lookup(namespace, service) do
        {:ok, pid} -> {:ok, pid}
        :error -> {:error, create_service_not_found_error(namespace, service)}
      end

    # Emit telemetry
    emit_lookup_telemetry(namespace, service, result, start_time)

    result
  end

  @doc """
  Safely unregister a service from the given namespace.

  ## Parameters
  - `namespace`: The namespace containing the service
  - `service`: The service name to unregister

  ## Returns
  - `:ok` regardless of whether service was registered

  ## Examples

      iex> ServiceRegistry.unregister(:production, :config_server)
      :ok
  """
  @spec unregister(namespace(), service_name()) :: :ok
  def unregister(namespace, service) do
    Logger.debug("Unregistering service #{inspect(service)} from namespace #{inspect(namespace)}")

    result = ProcessRegistry.unregister(namespace, service)

    Logger.info("Unregistered service #{inspect(service)} from namespace #{inspect(namespace)}")
    result
  end

  @doc """
  List all services registered in a namespace.

  ## Parameters
  - `namespace`: The namespace to list services for

  ## Returns
  - List of service names registered in the namespace

  ## Examples

      iex> ServiceRegistry.list_services(:production)
      [:config_server, :event_store, :telemetry_service]
  """
  @spec list_services(namespace()) :: [service_name()]
  def list_services(namespace) do
    Logger.debug("Listing services in namespace #{inspect(namespace)}")

    services = ProcessRegistry.list_services(namespace)

    Logger.debug("Found #{length(services)} services in namespace #{inspect(namespace)}")
    services
  end

  @doc """
  Check if a service is available and healthy in a namespace.

  This goes beyond simple registration checking - it verifies
  the process is alive and optionally calls a health check.

  ## Parameters
  - `namespace`: The namespace to check
  - `service`: The service name to check
  - `opts`: Options for health checking

  ## Options
  - `:health_check` - Function to call for health verification
  - `:timeout` - Timeout for health check (default: 5000ms)

  ## Returns
  - `{:ok, pid}` if service is healthy
  - `{:error, reason}` if service is unhealthy or not found

  ## Examples

      iex> ServiceRegistry.health_check(:production, :config_server)
      {:ok, #PID<0.123.0>}

      iex> ServiceRegistry.health_check(:production, :config_server,
      ...>   health_check: fn pid -> GenServer.call(pid, :health) end)
      {:ok, #PID<0.123.0>}
  """
  @spec health_check(namespace(), service_name(), keyword()) ::
          {:ok, pid()}
          | {:error,
             :health_check_timeout
             | :process_dead
             | {:health_check_crashed, term()}
             | {:health_check_error, term()}
             | {:health_check_failed, term()}
             | Error.t()}
  def health_check(namespace, service, opts \\ []) do
    log_health_check_start(namespace, service, opts)

    case lookup(namespace, service) do
      {:ok, pid} -> perform_health_check_on_pid(pid, service, opts)
      {:error, _reason} = error -> error
    end
  end

  defp log_health_check_start(namespace, service, opts) do
    if Keyword.get(opts, :debug_health_check, false) do
      Logger.debug("Health checking service #{inspect(service)} in namespace #{inspect(namespace)}")
    end
  end

  defp perform_health_check_on_pid(pid, service, opts) do
    if Process.alive?(pid) do
      execute_health_check_function(pid, service, opts)
    else
      Logger.warning("Service #{inspect(service)} found but process is dead")
      {:error, :process_dead}
    end
  end

  defp execute_health_check_function(pid, service, opts) do
    case Keyword.get(opts, :health_check) do
      nil ->
        {:ok, pid}

      health_check_fun when is_function(health_check_fun, 1) ->
        run_health_check_with_timeout(pid, service, health_check_fun, opts)
    end
  end

  defp run_health_check_with_timeout(pid, service, health_check_fun, opts) do
    timeout = Keyword.get(opts, :timeout, 5000)
    original_trap_exit = Process.flag(:trap_exit, true)

    try do
      task = create_health_check_task(health_check_fun, pid)
      handle_health_check_result(Task.await(task, timeout), pid, service)
    catch
      type, reason -> handle_health_check_exception(type, reason, service, timeout)
    after
      Process.flag(:trap_exit, original_trap_exit)
    end
  end

  defp create_health_check_task(health_check_fun, pid) do
    Task.async(fn ->
      start_time = System.monotonic_time(:microsecond)
      result = health_check_fun.(pid)
      end_time = System.monotonic_time(:microsecond)
      {end_time - start_time, result}
    end)
  end

  defp handle_health_check_result({time_us, result}, pid, service) do
    case result do
      :ok -> log_health_check_success(service, time_us, {:ok, pid})
      {:ok, _result} -> log_health_check_success(service, time_us, {:ok, pid})
      true -> log_health_check_success(service, time_us, {:ok, pid})
      false -> handle_health_check_failure(service, false)
      error -> handle_health_check_failure(service, error)
    end
  end

  defp log_health_check_success(service, time_us, result) do
    Logger.debug("Health check passed for #{inspect(service)} in #{time_us}μs")
    result
  end

  defp handle_health_check_failure(service, error) do
    Logger.warning("Health check failed for #{inspect(service)}: #{inspect(error)}")
    {:error, {:health_check_failed, error}}
  end

  defp handle_health_check_exception(:exit, {:timeout, _}, service, timeout) do
    Logger.warning("Health check timed out for #{inspect(service)} after #{timeout}ms")
    {:error, :health_check_timeout}
  end

  defp handle_health_check_exception(
         :exit,
         {{%RuntimeError{} = error, _}, {Task, :await, _}},
         service,
         _
       ) do
    Logger.warning("Health check errored for #{inspect(service)}: #{inspect(error)}")
    {:error, {:health_check_error, error}}
  end

  defp handle_health_check_exception(:exit, {{error, _}, {Task, :await, _}}, service, _) do
    Logger.warning("Health check crashed for #{inspect(service)}: #{inspect(error)}")
    {:error, {:health_check_crashed, error}}
  end

  defp handle_health_check_exception(:exit, {reason, {Task, :await, _}}, service, _) do
    Logger.warning("Health check crashed for #{inspect(service)}: #{inspect(reason)}")
    {:error, {:health_check_crashed, reason}}
  end

  defp handle_health_check_exception(:exit, reason, service, _) do
    Logger.warning("Health check crashed for #{inspect(service)}: #{inspect(reason)}")
    {:error, {:health_check_crashed, reason}}
  end

  defp handle_health_check_exception(:error, reason, service, _) do
    Logger.warning("Health check errored for #{inspect(service)}: #{inspect(reason)}")
    {:error, {:health_check_error, reason}}
  end

  @doc """
  Wait for a service to become available in a namespace.

  ## Parameters
  - `namespace`: The namespace to monitor
  - `service`: The service name to wait for
  - `timeout`: Maximum time to wait in milliseconds (default: 5000)

  ## Returns
  - `{:ok, pid}` if service becomes available
  - `{:error, :timeout}` if timeout is reached

  ## Examples

      iex> ServiceRegistry.wait_for_service(:production, :config_server, 1000)
      {:ok, #PID<0.123.0>}
  """
  @spec wait_for_service(namespace(), service_name(), pos_integer()) ::
          {:ok, pid()} | {:error, :timeout}
  def wait_for_service(namespace, service, timeout \\ 5000) do
    Logger.debug(
      "Waiting for service #{inspect(service)} in namespace #{inspect(namespace)} (timeout: #{timeout}ms)"
    )

    case lookup(namespace, service) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, _} ->
        ref = make_ref()
        Process.send_after(self(), {:service_check, ref, namespace, service}, 10)
        wait_for_service_receive(ref, namespace, service, timeout)
    end
  end

  defp wait_for_service_receive(ref, namespace, service, timeout) do
    receive do
      {:service_check, ^ref, ^namespace, ^service} ->
        case lookup(namespace, service) do
          {:ok, pid} ->
            {:ok, pid}

          {:error, _} when timeout > 10 ->
            new_ref = make_ref()
            Process.send_after(self(), {:service_check, new_ref, namespace, service}, 10)
            wait_for_service_receive(new_ref, namespace, service, timeout - 10)

          {:error, _} ->
            {:error, :timeout}
        end
    after
      timeout ->
        {:error, :timeout}
    end
  end

  @doc """
  Get comprehensive service information for a namespace.

  ## Parameters
  - `namespace`: The namespace to analyze

  ## Returns
  - Map with detailed service information

  ## Examples

      iex> ServiceRegistry.get_service_info(:production)
      %{
        namespace: :production,
        services: %{
          config_server: %{pid: #PID<0.123.0>, alive: true, uptime_ms: 12_345},
          event_store: %{pid: #PID<0.124.0>, alive: true, uptime_ms: 12344}
        },
        total_services: 2,
        healthy_services: 2
      }
  """
  @spec get_service_info(namespace()) :: %{
          namespace: namespace(),
          services: map(),
          total_services: non_neg_integer(),
          healthy_services: non_neg_integer()
        }
  def get_service_info(namespace) do
    # Only log debug info if debug_registry is explicitly enabled
    if Application.get_env(:foundation, :debug_registry, false) do
      Logger.debug("Getting service info for namespace #{inspect(namespace)}")
    end

    services_map = ProcessRegistry.get_all_services(namespace)

    service_details =
      Enum.into(services_map, %{}, fn {service, pid} ->
        {service, analyze_service(pid)}
      end)

    healthy_count =
      service_details
      |> Map.values()
      |> Enum.count(& &1.alive)

    %{
      namespace: namespace,
      services: service_details,
      total_services: map_size(service_details),
      healthy_services: healthy_count
    }
  end

  @doc """
  Cleanup services in a test namespace with detailed logging.

  ## Parameters
  - `test_ref`: The test reference used in namespace

  ## Returns
  - `:ok` after cleanup is complete

  ## Examples

      iex> test_ref = make_ref()
      iex> ServiceRegistry.cleanup_test_namespace(test_ref)
      :ok
  """
  @spec cleanup_test_namespace(reference()) :: :ok
  def cleanup_test_namespace(test_ref) do
    namespace = {:test, test_ref}

    # Only log if not in test mode
    test_mode = Application.get_env(:foundation, :test_mode, false)

    unless test_mode do
      Logger.info("Starting cleanup of test namespace #{inspect(namespace)}")
    end

    # Get service info before cleanup
    service_info = get_service_info(namespace)
    service_count = service_info.total_services

    if service_count > 0 do
      # Always log when there's actual work to do
      Logger.info("Cleaning up #{service_count} services in test namespace")
      ProcessRegistry.cleanup_test_namespace(test_ref)

      unless test_mode do
        Logger.info("Cleanup completed for test namespace #{inspect(namespace)}")
      end
    end

    :ok
  end

  @doc """
  Create a via tuple for service registration.

  Convenience wrapper around ProcessRegistry.via_tuple/2.

  ## Parameters
  - `namespace`: The namespace for the service
  - `service`: The service name

  ## Returns
  - Via tuple for GenServer registration
  """
  @spec via_tuple(namespace(), service_name()) ::
          {:via, Registry, {Foundation.ProcessRegistry, {namespace(), service_name()}}}
  def via_tuple(namespace, service) do
    ProcessRegistry.via_tuple(namespace, service)
  end

  ## Private Functions

  @spec analyze_service(pid()) :: %{pid: pid(), alive: boolean(), uptime_ms: integer()}
  defp analyze_service(pid) do
    alive = Process.alive?(pid)

    uptime_ms =
      if alive do
        case Process.info(pid, :reductions) do
          {_, _} ->
            # Process is alive, calculate approximate uptime
            # This is a rough estimate based on when we checked
            System.monotonic_time(:millisecond)

          nil ->
            0
        end
      else
        0
      end

    %{
      pid: pid,
      alive: alive,
      uptime_ms: uptime_ms
    }
  end

  @spec create_service_not_found_error(namespace(), service_name()) :: Error.t()
  defp create_service_not_found_error(namespace, service) do
    Error.new(
      code: 5001,
      error_type: :service_not_found,
      message: "Service #{inspect(service)} not found in namespace #{inspect(namespace)}",
      severity: :medium,
      category: :system,
      subcategory: :discovery,
      context: %{
        namespace: namespace,
        service: service
      }
    )
  end

  @spec emit_lookup_telemetry(namespace(), service_name(), lookup_result(), integer()) :: :ok
  defp emit_lookup_telemetry(namespace, service, result, start_time) do
    duration = System.monotonic_time() - start_time

    result_status =
      case result do
        {:ok, _} -> :ok
        {:error, _} -> :error
      end

    :telemetry.execute(
      [:foundation, :foundation, :registry, :lookup],
      %{duration: duration},
      %{namespace: namespace, service: service, result: result_status}
    )
  rescue
    # Don't let telemetry failures break Registry operations
    _ -> :ok
  end

  @spec emit_registration_telemetry(namespace(), service_name(), registration_result()) :: :ok
  defp emit_registration_telemetry(namespace, service, result) do
    result_status =
      case result do
        :ok -> :ok
        {:error, _} -> :error
      end

    :telemetry.execute(
      [:foundation, :foundation, :registry, :register],
      %{count: 1},
      %{namespace: namespace, service: service, result: result_status}
    )
  rescue
    _ -> :ok
  end
end
