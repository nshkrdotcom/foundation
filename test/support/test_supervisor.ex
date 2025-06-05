defmodule Foundation.TestSupport.TestSupervisor do
  @moduledoc """
  DynamicSupervisor for test isolation in Foundation layer.

  Allows starting isolated service instances per test to prevent
  test interference and enable concurrent testing.

  ## Examples

      # Start isolated services for a test
      test_ref = make_ref()
      {:ok, pids} = TestSupervisor.start_isolated_services(test_ref)

      # Cleanup test namespace
      :ok = TestSupervisor.cleanup_namespace(test_ref)
  """

  use DynamicSupervisor
  require Logger

  alias Foundation.{ProcessRegistry, ServiceRegistry}
  alias Foundation.Services.{ConfigServer, EventStore, TelemetryService}

  @type test_ref :: reference()
  @type namespace :: {:test, test_ref()}

  @doc """
  Start the TestSupervisor.

  ## Examples

      {:ok, pid} = TestSupervisor.start_link([])
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  @spec init(term()) :: {:ok, DynamicSupervisor.sup_flags()}
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start isolated services for a test.

  Creates a unique namespace for the test and starts all Foundation
  services within that namespace.

  ## Parameters
  - `test_ref`: Unique reference for the test (usually from make_ref())

  ## Returns
  - `{:ok, [pid()]}` - List of started service PIDs
  - `{:error, reason}` - If any service fails to start

  ## Examples

      test_ref = make_ref()
      {:ok, pids} = TestSupervisor.start_isolated_services(test_ref)
  """
  @spec start_isolated_services(test_ref()) :: {:ok, [pid()]} | {:error, term()}
  def start_isolated_services(test_ref) when is_reference(test_ref) do
    namespace = {:test, test_ref}

    Logger.debug("Starting isolated services for test namespace #{inspect(namespace)}")

    # Define the services to start with their configurations
    service_specs = [
      {ConfigServer, [namespace: namespace]},
      {EventStore, [namespace: namespace]},
      {TelemetryService, [namespace: namespace]}
    ]

    # Start each service and collect results
    results =
      Enum.map(service_specs, fn {module, opts} ->
        case DynamicSupervisor.start_child(__MODULE__, {module, opts}) do
          {:ok, pid} ->
            Logger.debug(
              "Started #{module} for test namespace #{inspect(namespace)}: #{inspect(pid)}"
            )

            {:ok, pid}

          {:error, {:already_started, pid}} ->
            Logger.warning(
              "Service #{module} already started for namespace #{inspect(namespace)}: #{inspect(pid)}"
            )

            {:ok, pid}

          {:error, reason} = error ->
            Logger.error(
              "Failed to start #{module} for namespace #{inspect(namespace)}: #{inspect(reason)}"
            )

            error
        end
      end)

    # Check if all services started successfully
    case Enum.split_with(results, &match?({:ok, _}, &1)) do
      {successes, []} ->
        pids = Enum.map(successes, fn {:ok, pid} -> pid end)

        Logger.info(
          "Successfully started #{length(pids)} services for test namespace #{inspect(namespace)}"
        )

        {:ok, pids}

      {_successes, failures} ->
        # If any failed, cleanup what we started and return error
        cleanup_namespace(test_ref)
        first_error = List.first(failures)

        Logger.error(
          "Failed to start isolated services for test namespace #{inspect(namespace)}: #{inspect(first_error)}"
        )

        first_error
    end
  end

  @doc """
  Cleanup all services in a test namespace.

  Terminates all services started for the given test reference
  and cleans up the namespace.

  ## Parameters
  - `test_ref`: The test reference used when starting services

  ## Returns
  - `:ok` after cleanup is complete

  ## Examples

      test_ref = make_ref()
      # ... start services ...
      :ok = TestSupervisor.cleanup_namespace(test_ref)
  """
  @spec cleanup_namespace(test_ref()) :: :ok
  def cleanup_namespace(test_ref) when is_reference(test_ref) do
    namespace = {:test, test_ref}

    # Only log cleanup debug for non-empty namespaces
    services = ProcessRegistry.get_all_services(namespace)

    if map_size(services) > 0 do
      # Terminate each service through the DynamicSupervisor
      Enum.each(services, fn {_service_name, pid} ->
        if Process.alive?(pid) do
          case DynamicSupervisor.terminate_child(__MODULE__, pid) do
            :ok ->
              # No debug log for successful termination to reduce noise
              :ok

            {:error, :not_found} ->
              # Process might have already died, try direct termination
              Process.exit(pid, :shutdown)
          end
        end
      end)

      # Wait a moment for cleanup to complete
      Process.sleep(50)

      # Use ProcessRegistry cleanup as backup
      ProcessRegistry.cleanup_test_namespace(test_ref)
    end

    # Only log completion for non-empty cleanups
    :ok
  end

  @doc """
  Get information about all test namespaces currently active.

  ## Returns
  - Map with test namespace information

  ## Examples

      iex> TestSupervisor.get_test_namespaces_info()
      %{
        active_namespaces: 3,
        total_test_services: 9,
        namespaces: [...]
      }
  """
  @spec get_test_namespaces_info() :: %{
          active_children: non_neg_integer(),
          test_namespaces: non_neg_integer(),
          total_test_services: number(),
          supervisor_pid: nil | pid()
        }
  def get_test_namespaces_info() do
    # Get all children of the DynamicSupervisor
    children = DynamicSupervisor.which_children(__MODULE__)

    # Get registry stats
    registry_stats = ProcessRegistry.stats()

    %{
      active_children: length(children),
      test_namespaces: registry_stats.test_namespaces,
      total_test_services: registry_stats.total_services - registry_stats.production_services,
      supervisor_pid: Process.whereis(__MODULE__)
    }
  end

  @doc """
  Wait for all services in a test namespace to be ready.

  ## Parameters
  - `test_ref`: The test reference
  - `timeout`: Maximum time to wait in milliseconds (default: 5000)

  ## Returns
  - `:ok` if all services are ready
  - `{:error, :timeout}` if timeout is reached

  ## Examples

      test_ref = make_ref()
      {:ok, _pids} = TestSupervisor.start_isolated_services(test_ref)
      :ok = TestSupervisor.wait_for_services_ready(test_ref)
  """
  @spec wait_for_services_ready(reference(), pos_integer()) :: :ok | {:error, :timeout}
  def wait_for_services_ready(test_ref, timeout \\ 5000) when is_reference(test_ref) do
    namespace = {:test, test_ref}

    Logger.debug("Waiting for services to be ready in namespace #{inspect(namespace)}")

    # Only check for services we actually start (now including TelemetryService)
    services_to_check = [:config_server, :event_store, :telemetry_service]

    start_time = System.monotonic_time(:millisecond)
    wait_for_services_loop(namespace, services_to_check, timeout, start_time)
  end

  @doc """
  Check if a test namespace has all expected services running.

  ## Parameters
  - `test_ref`: The test reference

  ## Returns
  - `true` if all services are running
  - `false` if any service is missing or dead

  ## Examples

      iex> TestSupervisor.namespace_healthy?(test_ref)
      true
  """
  @spec namespace_healthy?(test_ref()) :: boolean()
  def namespace_healthy?(test_ref) when is_reference(test_ref) do
    namespace = {:test, test_ref}
    expected_services = [:config_server, :event_store, :telemetry_service]

    Enum.all?(expected_services, fn service ->
      case ServiceRegistry.health_check(namespace, service) do
        {:ok, _pid} -> true
        {:error, _reason} -> false
      end
    end)
  end

  ## Private Functions

  @spec wait_for_services_loop(namespace(), [atom()], pos_integer(), integer()) ::
          :ok | {:error, :timeout}
  defp wait_for_services_loop(namespace, services, timeout, start_time) do
    elapsed = System.monotonic_time(:millisecond) - start_time

    if elapsed >= timeout do
      Logger.warning(
        "Timeout waiting for services in namespace #{inspect(namespace)} after #{elapsed}ms"
      )

      {:error, :timeout}
    else
      case check_all_services_ready(namespace, services) do
        :ok ->
          Logger.debug("All services ready in namespace #{inspect(namespace)} after #{elapsed}ms")
          :ok

        {:error, _service} ->
          # Wait a bit and retry
          Process.sleep(10)
          wait_for_services_loop(namespace, services, timeout, start_time)
      end
    end
  end

  @spec check_all_services_ready(namespace(), [atom()]) :: :ok | {:error, atom()}
  defp check_all_services_ready(namespace, services) do
    Enum.reduce_while(services, :ok, fn service, :ok ->
      case ServiceRegistry.health_check(namespace, service) do
        {:ok, _pid} ->
          {:cont, :ok}

        {:error, _reason} ->
          {:halt, {:error, service}}
      end
    end)
  end
end
