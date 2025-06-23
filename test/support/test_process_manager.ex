defmodule Foundation.TestProcessManager do
  @moduledoc """
  Utility module for managing Foundation layer processes during tests.

  Provides systematic cleanup and state management for test isolation.
  This module should only be used in test environments.
  """

  require Logger
  alias Foundation.Types.Error

  @foundation_services [
    Foundation.Services.ConfigServer,
    Foundation.Services.EventStore,
    Foundation.Services.TelemetryService
  ]

  @doc """
  Clean up all Foundation layer processes.

  Systematically stops all Foundation services and cleans up any
  orphaned processes. This is designed for test cleanup.
  """
  @spec cleanup_all_foundation_processes() :: :ok | {:error, Error.t()}
  def cleanup_all_foundation_processes do
    if Application.get_env(:foundation, :test_mode, false) do
      Logger.debug("Starting Foundation process cleanup")

      try do
        # Reset state of all services first
        reset_all_service_states()

        # Stop all services gracefully
        stop_all_services()

        # Clean up any orphaned processes
        cleanup_orphaned_processes()

        # Give processes time to fully shutdown
        Process.sleep(50)

        Logger.debug("Foundation process cleanup completed")
        :ok
      rescue
        error ->
          Logger.warning("Error during Foundation cleanup: #{inspect(error)}")

          {:error,
           Error.new(
             code: 9001,
             error_type: :cleanup_failed,
             message: "Failed to clean up Foundation processes",
             severity: :medium,
             context: %{error: inspect(error)},
             category: :test,
             subcategory: :cleanup
           )}
      end
    else
      {:error,
       Error.new(
         code: 9000,
         error_type: :operation_forbidden,
         message: "Process cleanup only allowed in test mode",
         severity: :high,
         category: :security,
         subcategory: :authorization
       )}
    end
  end

  @doc """
  Reset the state of all Foundation services.

  Calls reset_state/0 on each service to clear accumulated data.
  """
  @spec reset_all_service_states() :: :ok | [Error.t()]
  def reset_all_service_states do
    if Application.get_env(:foundation, :test_mode, false) do
      errors = collect_service_reset_errors()

      case errors do
        [] -> :ok
        errors -> errors
      end
    else
      [
        {:error,
         Error.new(
           code: 9000,
           error_type: :operation_forbidden,
           message: "State reset only allowed in test mode",
           severity: :high,
           category: :security,
           subcategory: :authorization
         )}
      ]
    end
  end

  @doc """
  Stop all Foundation services gracefully.

  Attempts to stop each service using its stop/0 function,
  with fallback to Process.exit/2 if needed.
  """
  @spec stop_all_services() :: :ok
  def stop_all_services do
    Enum.each(@foundation_services, fn service_module ->
      stop_service(service_module)
    end)

    :ok
  end

  @doc """
  Wait for all Foundation services to be available.

  Useful for test setup to ensure services are ready before proceeding.
  """
  @spec wait_for_all_services(non_neg_integer()) :: :ok | :timeout
  def wait_for_all_services(timeout_ms \\ 5000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    wait_for_services_available(deadline)
  end

  @doc """
  Check if all Foundation services are available.
  """
  @spec all_services_available?() :: boolean()
  def all_services_available? do
    results =
      Enum.map(@foundation_services, fn service_module ->
        available = service_module.available?()
        Logger.debug("Service #{inspect(service_module)} available: #{available}")
        {service_module, available}
      end)

    all_available = Enum.all?(results, fn {_service, available} -> available end)
    Logger.debug("All services available: #{all_available}")
    all_available
  end

  @doc """
  Get the current status of all Foundation services.

  Returns a map with service names as keys and their status as values.
  """
  @spec get_services_status() :: %{atom() => map()}
  def get_services_status do
    Enum.reduce(@foundation_services, %{}, fn service_module, acc ->
      service_name = service_module |> Module.split() |> List.last() |> String.to_atom()

      status =
        case service_module.status() do
          {:ok, status_info} -> status_info
          {:error, error} -> %{status: :error, error: error}
        end

      Map.put(acc, service_name, status)
    end)
  end

  @doc """
  Initialize all Foundation services with test configuration.

  Starts services in the correct order with test-appropriate settings.
  """
  @spec initialize_test_services(keyword()) :: :ok | {:error, Error.t()}
  def initialize_test_services(opts \\ []) do
    if Application.get_env(:foundation, :test_mode, false) do
      test_opts = Keyword.merge([test_mode: true], opts)

      # Initialize services in dependency order
      case initialize_services_in_order(test_opts) do
        :ok ->
          # Wait for all services to be ready
          case wait_for_all_services(5000) do
            :ok ->
              :ok

            :timeout ->
              create_initialization_timeout_error()
          end

        {:error, _} = error ->
          error
      end
    else
      {:error,
       Error.new(
         code: 9000,
         error_type: :operation_forbidden,
         message: "Test service initialization only allowed in test mode",
         severity: :high,
         category: :security,
         subcategory: :authorization
       )}
    end
  end

  ## Private Functions

  @spec reset_service_state(module()) :: :ok | {:error, Error.t()}
  defp reset_service_state(service_module) do
    if function_exported?(service_module, :reset_state, 0) do
      try do
        service_module.reset_state()
      rescue
        error ->
          {:error,
           Error.new(
             code: 9003,
             error_type: :state_reset_failed,
             message: "Failed to reset service state",
             severity: :medium,
             context: %{service: service_module, error: inspect(error)},
             category: :test,
             subcategory: :cleanup
           )}
      end
    else
      Logger.debug("Service #{inspect(service_module)} does not support state reset")
      :ok
    end
  end

  @spec stop_service(module()) :: :ok
  defp stop_service(service_module) do
    try do
      # First try to find the actual process name
      process_name = get_service_process_name(service_module)

      case GenServer.whereis(process_name) do
        nil ->
          # Process not running, nothing to stop
          Logger.debug("Service #{inspect(service_module)} not running")
          :ok

        pid ->
          # Try graceful stop first
          if function_exported?(service_module, :stop, 0) do
            try do
              service_module.stop()
            rescue
              _ -> Process.exit(pid, :kill)
            catch
              :exit, _ -> Process.exit(pid, :kill)
            end
          else
            Process.exit(pid, :kill)
          end

          :ok
      end
    rescue
      error ->
        Logger.debug("Error stopping service #{inspect(service_module)}: #{inspect(error)}")
        :ok
    end
  end

  @spec get_service_process_name(module()) :: atom()
  defp get_service_process_name(service_module) do
    if Application.get_env(:foundation, :test_mode, false) do
      # In test mode, services use dynamic names
      # We need to find them by scanning registered processes
      registered_processes = Process.registered()
      service_name_pattern = Atom.to_string(service_module)

      found_process =
        Enum.find(registered_processes, fn name ->
          name_string = Atom.to_string(name)
          String.starts_with?(name_string, service_name_pattern)
        end)

      found_process || service_module
    else
      service_module
    end
  end

  @spec cleanup_orphaned_processes() :: :ok
  defp cleanup_orphaned_processes do
    # Find any processes that might be related to Foundation but not properly managed
    registered_processes = Process.registered()

    # List of essential processes that should NOT be killed
    essential_processes = [
      :"Foundation.Supervisor",
      :"Foundation.TaskSupervisor"
    ]

    foundation_related =
      Enum.filter(registered_processes, fn name ->
        name_string = Atom.to_string(name)
        # Don't kill any supervisor processes
        String.contains?(name_string, "Foundation") and
          name not in essential_processes and
          not String.contains?(name_string, "Supervisor")
      end)

    Enum.each(foundation_related, fn name ->
      case GenServer.whereis(name) do
        nil ->
          :ok

        pid ->
          # Cleanup orphaned processes silently to reduce log noise
          Process.exit(pid, :kill)
      end
    end)

    :ok
  end

  @spec wait_for_services_available(integer()) :: :ok | :timeout
  defp wait_for_services_available(deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      :timeout
    else
      if all_services_available?() do
        :ok
      else
        Process.sleep(10)
        wait_for_services_available(deadline)
      end
    end
  end

  @spec initialize_services_in_order(keyword()) :: :ok | {:error, Error.t()}
  defp initialize_services_in_order(opts) do
    # Initialize in dependency order: ConfigServer -> EventStore -> TelemetryService
    service_init_order = [
      Foundation.Services.ConfigServer,
      Foundation.Services.EventStore,
      Foundation.Services.TelemetryService
    ]

    Enum.reduce_while(service_init_order, :ok, fn service_module, :ok ->
      case service_module.initialize(opts) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp collect_service_reset_errors() do
    Enum.reduce(@foundation_services, [], fn service_module, acc_errors ->
      case reset_service_state(service_module) do
        :ok -> acc_errors
        {:error, error} -> [error | acc_errors]
      end
    end)
  end

  defp create_initialization_timeout_error() do
    {:error,
     Error.new(
       code: 9002,
       error_type: :initialization_timeout,
       message: "Services failed to start within timeout",
       severity: :high,
       category: :test,
       subcategory: :initialization
     )}
  end
end
