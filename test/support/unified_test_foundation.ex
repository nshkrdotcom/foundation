defmodule Foundation.UnifiedTestFoundation do
  @moduledoc """
  Unified test configuration system for Foundation tests with multiple isolation levels.

  This module consolidates all test configuration patterns and provides a clean,
  consistent interface for test isolation and contamination prevention.

  ## Isolation Modes

  - `:basic` - Minimal isolation for simple tests
  - `:registry` - Registry isolation for MABEAM tests
  - `:signal_routing` - Full signal routing isolation
  - `:full_isolation` - Complete service isolation
  - `:contamination_detection` - Full isolation + contamination monitoring
  - `:service_integration` - Service Integration Architecture testing with SIA components

  ## Usage Examples

      # Basic registry isolation
      defmodule MyTest do
        use Foundation.UnifiedTestFoundation, :registry

        test "my test", %{registry: registry} do
          # registry is isolated per test
        end
      end

      # Full signal routing isolation
      defmodule SignalTest do
        use Foundation.UnifiedTestFoundation, :signal_routing

        test "signals", %{test_context: ctx, signal_router: router} do
          # Fully isolated signal routing
        end
      end

      # Contamination detection enabled
      defmodule RobustTest do
        use Foundation.UnifiedTestFoundation, :contamination_detection

        test "robust test", %{test_context: ctx} do
          # All services isolated + contamination monitoring
        end
      end

      # Service Integration Architecture testing
      defmodule ServiceIntegrationTest do
        use Foundation.UnifiedTestFoundation, :service_integration

        test "service integration", %{sia_context: ctx} do
          # SIA components available for testing
        end
      end
  """

  import ExUnit.Callbacks

  @doc """
  Main entry point for test configuration.
  """
  defmacro __using__(mode) do
    quote do
      use ExUnit.Case, async: unquote(can_run_async?(mode))
      import Foundation.UnifiedTestFoundation
      import ExUnit.Callbacks
      alias Foundation.TestIsolation

      setup do
        unquote(setup_for_mode(mode))
      end

      # Module-level configuration based on mode
      unquote(module_config_for_mode(mode))
    end
  end

  # Mode-specific setup functions

  @doc """
  Ensures Foundation application and services are available for tests.
  """
  def ensure_foundation_services do
    # Start Foundation application if not already started
    case Application.ensure_all_started(:foundation) do
      {:ok, _apps} -> :ok
      # May already be started
      {:error, _reason} -> :ok
    end

    # Verify critical services are available
    services_to_check = [
      Foundation.ResourceManager,
      Foundation.PerformanceMonitor
    ]

    Enum.each(services_to_check, fn service ->
      case Process.whereis(service) do
        nil ->
          # Try to start the service if it's not running
          case service.start_link() do
            {:ok, _pid} ->
              :ok

            {:error, {:already_started, _pid}} ->
              :ok

            {:error, reason} ->
              raise "Failed to start #{service}: #{inspect(reason)}"
          end

        _pid ->
          :ok
      end
    end)

    :ok
  end

  @doc """
  Basic setup with minimal isolation.
  """
  def basic_setup(_context) do
    ensure_foundation_services()
    test_id = :erlang.unique_integer([:positive])

    %{
      test_id: test_id,
      mode: :basic
    }
  end

  @doc """
  Registry isolation setup.
  """
  def registry_setup(context) do
    ensure_foundation_services()

    # Generate unique registry name using the proven pattern from Foundation.TestConfig
    test_name =
      Map.get(context, :test, "unknown")
      |> to_string()
      |> String.replace(~r/[^a-zA-Z0-9_]/, "_")

    module_name =
      context[:module]
      |> to_string()
      |> String.split(".")
      |> List.last()
      |> String.replace(~r/[^a-zA-Z0-9_]/, "_")

    unique_id = :"#{module_name}_#{test_name}_#{System.unique_integer([:positive])}"

    # Ensure no existing process with this name
    case Process.whereis(unique_id) do
      nil ->
        :ok

      pid ->
        Process.unregister(unique_id)
        GenServer.stop(pid)
    end

    # Start registry
    {:ok, registry} = MABEAM.AgentRegistry.start_link(name: unique_id)

    on_exit(fn ->
      try do
        if Process.alive?(registry) do
          GenServer.stop(registry, :normal, 5000)
        end
      catch
        :exit, {:noproc, _} -> :ok
        :exit, {:normal, _} -> :ok
        _, _ -> :ok
      end
    end)

    %{
      test_id: System.unique_integer([:positive]),
      mode: :registry,
      registry: registry,
      registry_name: unique_id
    }
  end

  @doc """
  Signal routing isolation setup.
  """
  def signal_routing_setup(context) do
    # Start with registry setup
    registry_result = registry_setup(context)
    test_id = registry_result.test_id

    # Create test-scoped signal router
    test_router_name = :"test_signal_router_#{test_id}"
    {:ok, router_pid} = start_test_signal_router(test_router_name)

    # Enhanced cleanup for signal routing
    on_exit(fn ->
      cleanup_signal_routing(router_pid, test_id)
    end)

    Map.merge(registry_result, %{
      mode: :signal_routing,
      signal_router: router_pid,
      signal_router_name: test_router_name,
      test_context: %{
        test_id: test_id,
        signal_router_name: test_router_name,
        registry_name: registry_result.registry_name
      }
    })
  end

  @doc """
  Full isolation setup with all services isolated.
  """
  def full_isolation_setup(context \\ %{}) do
    ensure_foundation_services()
    test_id = :erlang.unique_integer([:positive])

    # Create comprehensive test context
    test_context = %{
      test_id: test_id,
      signal_bus_name: :"test_signal_bus_#{test_id}",
      signal_router_name: :"test_signal_router_#{test_id}",
      registry_name: :"test_registry_#{test_id}",
      telemetry_prefix: "test_#{test_id}",
      supervisor_name: :"test_supervisor_#{test_id}"
    }

    # Start isolated services
    case Foundation.TestIsolation.start_isolated_test(test_context: test_context) do
      {:ok, supervisor, enhanced_context} ->
        # Only register cleanup if not being called from a parent setup
        unless Map.get(context, :skip_cleanup, false) do
          on_exit(fn ->
            Foundation.TestIsolation.stop_isolated_test(supervisor)
          end)
        end

        %{
          test_id: test_id,
          mode: :full_isolation,
          test_context: enhanced_context,
          supervisor: supervisor
        }

      {:error, reason} ->
        raise "Failed to start isolated test environment: #{inspect(reason)}"
    end
  end

  @doc """
  Contamination detection setup with full monitoring.
  """
  def contamination_detection_setup(context) do
    # Start with full isolation but skip its cleanup registration
    base_setup = full_isolation_setup(Map.put(context, :skip_cleanup, true))
    test_id = base_setup.test_id
    supervisor = base_setup.supervisor

    # Capture initial system state
    initial_state = capture_system_state(test_id)

    # Setup combined cleanup: contamination detection THEN supervisor cleanup
    on_exit(fn ->
      # First, capture final state and detect contamination
      final_state = capture_system_state(test_id)
      detect_contamination(initial_state, final_state, test_id)

      # Then clean up the supervisor
      Foundation.TestIsolation.stop_isolated_test(supervisor)
    end)

    # Merge the contamination detection data with the base setup
    Map.merge(base_setup, %{
      mode: :contamination_detection,
      initial_state: initial_state,
      contamination_detection: true
    })
    |> Map.put(
      :test_context,
      Map.merge(base_setup.test_context, %{
        mode: :contamination_detection,
        contamination_detection: true
      })
    )
  end

  @doc """
  Service Integration Architecture setup for testing SIA components.
  """
  def service_integration_setup(context) do
    # Start with full isolation as base
    base_setup = full_isolation_setup(context)
    test_id = base_setup.test_id

    # Initialize SIA components for testing
    sia_context = %{
      test_id: test_id,
      service_integration_enabled: true,

      # SIA component names (test-isolated)
      contract_validator_name: :"test_contract_validator_#{test_id}",
      dependency_manager_name: :"test_dependency_manager_#{test_id}",
      health_checker_name: :"test_health_checker_#{test_id}",
      signal_coordinator_name: :"test_signal_coordinator_#{test_id}",

      # Component configuration
      test_mode: true,
      mock_foundation_services: true
    }

    # Start test-isolated SIA components if available
    sia_services = start_sia_components_safely(sia_context)

    # Enhanced cleanup for SIA components
    on_exit(fn ->
      cleanup_sia_components(sia_services, test_id)
    end)

    # Merge with base setup
    Map.merge(base_setup, %{
      mode: :service_integration,
      sia_context: sia_context,
      sia_services: sia_services,
      service_integration: %{
        contract_validation: Map.get(sia_services, :contract_validator),
        dependency_management: Map.get(sia_services, :dependency_manager),
        health_checking: Map.get(sia_services, :health_checker),
        signal_coordination: Map.get(sia_services, :signal_coordinator)
      }
    })
    |> Map.put(
      :test_context,
      Map.merge(base_setup.test_context, %{
        mode: :service_integration,
        sia_enabled: true,
        sia_context: sia_context
      })
    )
  end

  # Helper functions

  @doc """
  Starts a test-scoped signal router.
  """
  def start_test_signal_router(router_name) do
    # Use the actual SignalRouter (not test-only module)
    JidoFoundation.SignalRouter.start_link(name: router_name)
  end

  @doc """
  Captures system state for contamination detection.
  """
  def capture_system_state(test_id) do
    %{
      test_id: test_id,
      timestamp: System.system_time(:microsecond),
      processes: Process.registered() |> Enum.filter(&test_process?(&1, test_id)),
      telemetry: :telemetry.list_handlers([]) |> Enum.filter(&test_handler?(&1, test_id)),
      ets: :ets.all() |> length(),
      memory: :erlang.memory()
    }
  end

  @doc """
  Detects contamination between initial and final system states.
  """
  def detect_contamination(initial_state, final_state, test_id) do
    contamination_issues = []

    # Check for leftover processes
    leftover_processes = final_state.processes -- initial_state.processes

    contamination_issues =
      if leftover_processes != [] do
        ["Leftover test processes: #{inspect(leftover_processes)}" | contamination_issues]
      else
        contamination_issues
      end

    # Check for leftover telemetry handlers
    leftover_handlers = final_state.telemetry -- initial_state.telemetry

    contamination_issues =
      if leftover_handlers != [] do
        handler_ids = Enum.map(leftover_handlers, & &1.id)
        ["Leftover telemetry handlers: #{inspect(handler_ids)}" | contamination_issues]
      else
        contamination_issues
      end

    # Check for significant ETS table growth
    ets_growth = final_state.ets - initial_state.ets

    contamination_issues =
      if ets_growth > 5 do
        ["Significant ETS table growth: +#{ets_growth} tables" | contamination_issues]
      else
        contamination_issues
      end

    # Report contamination if found
    unless contamination_issues == [] do
      IO.puts("\n⚠️  CONTAMINATION DETECTED in test_#{test_id}:")

      Enum.each(contamination_issues, fn issue ->
        IO.puts("   - #{issue}")
      end)

      IO.puts("")
    end

    :ok
  end

  @doc """
  Cleanup function for signal routing resources.
  """
  def cleanup_signal_routing(router_pid, test_id) do
    try do
      if Process.alive?(router_pid) do
        # Get telemetry handler ID before stopping
        {:ok, state} = GenServer.call(router_pid, :get_state)
        :telemetry.detach(state.telemetry_handler_id)
        GenServer.stop(router_pid)
      end
    catch
      _, _ -> :ok
    end

    # Clean up any remaining test-specific telemetry handlers
    cleanup_test_telemetry_handlers(test_id)
  end

  @doc """
  Cleans up telemetry handlers for a specific test.
  """
  def cleanup_test_telemetry_handlers(test_id) do
    try do
      :telemetry.list_handlers([])
      |> Enum.filter(&test_handler?(&1, test_id))
      |> Enum.each(fn handler ->
        :telemetry.detach(handler.id)
      end)
    catch
      _, _ -> :ok
    end
  end

  # Private helper functions

  defp can_run_async?(:basic), do: true
  # Registry tests often need serial execution
  defp can_run_async?(:registry), do: false
  # Signal routing needs careful isolation
  defp can_run_async?(:signal_routing), do: false
  # Fully isolated can run async
  defp can_run_async?(:full_isolation), do: true
  # Monitoring needs serial execution
  defp can_run_async?(:contamination_detection), do: false
  # SIA needs careful coordination
  defp can_run_async?(:service_integration), do: false

  defp setup_for_mode(:basic) do
    quote do
      Foundation.UnifiedTestFoundation.basic_setup(%{})
    end
  end

  defp setup_for_mode(:registry) do
    quote do
      Foundation.UnifiedTestFoundation.registry_setup(%{})
    end
  end

  defp setup_for_mode(:signal_routing) do
    quote do
      Foundation.UnifiedTestFoundation.signal_routing_setup(%{})
    end
  end

  defp setup_for_mode(:full_isolation) do
    quote do
      Foundation.UnifiedTestFoundation.full_isolation_setup(%{})
    end
  end

  defp setup_for_mode(:contamination_detection) do
    quote do
      Foundation.UnifiedTestFoundation.contamination_detection_setup(%{})
    end
  end

  defp setup_for_mode(:service_integration) do
    quote do
      Foundation.UnifiedTestFoundation.service_integration_setup(%{})
    end
  end

  defp module_config_for_mode(:contamination_detection) do
    quote do
      @moduletag :contamination_detection
      @moduletag :serial
    end
  end

  defp module_config_for_mode(:signal_routing) do
    quote do
      @moduletag :signal_routing
      @moduletag :serial
    end
  end

  defp module_config_for_mode(:service_integration) do
    quote do
      @moduletag :service_integration
      @moduletag :serial
    end
  end

  defp module_config_for_mode(_), do: quote(do: nil)

  defp test_process?(process_name, test_id) when is_atom(process_name) do
    process_name
    |> to_string()
    |> String.contains?("test_#{test_id}")
  end

  defp test_process?(_, _), do: false

  defp test_handler?(handler, test_id) do
    handler.id
    |> to_string()
    |> String.contains?("test_#{test_id}")
  end

  # SIA component management helpers

  @doc """
  Safely starts SIA components for testing, handling cases where modules may not be loaded.
  """
  def start_sia_components_safely(sia_context) do
    components = %{}

    # Try to start each SIA component, gracefully handling module loading issues
    components =
      try_start_component(
        components,
        :contract_validator,
        Foundation.ServiceIntegration.ContractValidator,
        name: sia_context.contract_validator_name
      )

    components =
      try_start_component(
        components,
        :dependency_manager,
        Foundation.ServiceIntegration.DependencyManager,
        name: sia_context.dependency_manager_name
      )

    components =
      try_start_component(
        components,
        :health_checker,
        Foundation.ServiceIntegration.HealthChecker,
        name: sia_context.health_checker_name
      )

    # SignalCoordinator is stateless, just note availability
    components =
      if Code.ensure_loaded?(Foundation.ServiceIntegration.SignalCoordinator) do
        Map.put(components, :signal_coordinator, Foundation.ServiceIntegration.SignalCoordinator)
      else
        Map.put(components, :signal_coordinator, :not_available)
      end

    components
  end

  defp try_start_component(components, key, module, opts) do
    if Code.ensure_loaded?(module) do
      try do
        case module.start_link(opts) do
          {:ok, pid} ->
            Map.put(components, key, pid)

          {:error, {:already_started, pid}} ->
            Map.put(components, key, pid)

          {:error, _reason} ->
            Map.put(components, key, :failed_to_start)
        end
      rescue
        _ ->
          Map.put(components, key, :start_exception)
      end
    else
      Map.put(components, key, :not_available)
    end
  end

  @doc """
  Cleans up SIA components after test completion.
  """
  def cleanup_sia_components(sia_services, test_id) do
    # Stop any running SIA component processes
    Enum.each(sia_services, fn {_key, service} ->
      case service do
        pid when is_pid(pid) ->
          try do
            if Process.alive?(pid) do
              GenServer.stop(pid, :normal, 5000)
            end
          catch
            _, _ -> :ok
          end

        _other ->
          :ok
      end
    end)

    # Clean up any SIA-specific telemetry handlers
    cleanup_sia_telemetry_handlers(test_id)
  end

  @doc """
  Cleans up SIA-specific telemetry handlers.
  """
  def cleanup_sia_telemetry_handlers(test_id) do
    try do
      :telemetry.list_handlers([])
      |> Enum.filter(&sia_test_handler?(&1, test_id))
      |> Enum.each(fn handler ->
        :telemetry.detach(handler.id)
      end)
    catch
      _, _ -> :ok
    end
  end

  defp sia_test_handler?(handler, test_id) do
    handler_id = to_string(handler.id)

    String.contains?(handler_id, "test_#{test_id}") and
      (String.contains?(handler_id, "service_integration") or
         String.contains?(handler_id, "contract_validator") or
         String.contains?(handler_id, "dependency_manager") or
         String.contains?(handler_id, "health_checker") or
         String.contains?(handler_id, "signal_coordinator"))
  end
end
