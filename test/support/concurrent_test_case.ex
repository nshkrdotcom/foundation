defmodule Foundation.TestSupport.ConcurrentTestCase do
  @moduledoc """
  Test case template for concurrent testing with service isolation.

  Provides isolated namespaces per test using our Registry-based architecture
  to enable concurrent testing without interference.

  ## Examples

      defmodule MyTest do
        use Foundation.ConcurrentTestCase

        test "config operations work in isolation", %{namespace: ns} do
          # Your test code here with isolated services
          assert {:ok, _} = ConfigServer.get([:ai, :provider])
        end
      end
  """

  @doc """
  When used, this module will set up async testing with isolated services.
  """
  defmacro __using__(_opts) do
    quote do
      use ExUnit.Case, async: true

      alias Foundation.ServiceRegistry
      alias Foundation.TestSupport.TestSupervisor
      alias Foundation.Services.{ConfigServer, EventStore}

      setup do
        # Create unique namespace for this test
        test_ref = make_ref()
        namespace = {:test, test_ref}

        # Start isolated services for this test
        case TestSupervisor.start_isolated_services(test_ref) do
          {:ok, pids} ->
            # Wait for services to be ready
            :ok = TestSupervisor.wait_for_services_ready(test_ref, 2000)

            # Cleanup on exit
            on_exit(fn ->
              TestSupervisor.cleanup_namespace(test_ref)
            end)

            {:ok, test_ref: test_ref, namespace: namespace, service_pids: pids}

          {:error, reason} ->
            flunk("Failed to start isolated services: #{inspect(reason)}")
        end
      end

      @doc """
      Safely interact with a service in the test namespace.
      """
      def with_service(namespace, service, fun) do
        case ServiceRegistry.lookup(namespace, service) do
          {:ok, pid} ->
            fun.(pid)

          {:error, reason} ->
            flunk(
              "Service #{service} not found in namespace #{inspect(namespace)}: #{inspect(reason)}"
            )
        end
      end

      @doc """
      Wait for a service to become available in the test namespace.
      """
      def wait_for_service(namespace, service, timeout \\ 1000) do
        case ServiceRegistry.wait_for_service(namespace, service, timeout) do
          {:ok, pid} ->
            pid

          {:error, :timeout} ->
            flunk("Timeout waiting for service #{service} in namespace #{inspect(namespace)}")

          {:error, reason} ->
            flunk("Failed to wait for service #{service}: #{inspect(reason)}")
        end
      end

      @doc """
      Assert that the test namespace is properly isolated.
      """
      def assert_service_isolated(namespace) do
        services = ServiceRegistry.list_services(namespace)
        assert length(services) > 0, "Expected isolated services in namespace #{inspect(namespace)}"

        # Verify services don't conflict with production
        production_services = ServiceRegistry.list_services(:production)

        # Services in test namespace should not affect production namespace
        assert MapSet.disjoint?(MapSet.new(services), MapSet.new(production_services)),
               "Test namespace services should not conflict with production"
      end

      @doc """
      Measure performance of concurrent operations.
      """
      def measure_concurrent_ops(namespace, operations, concurrency_level \\ 10) do
        start_time = System.monotonic_time(:microsecond)

        tasks =
          1..concurrency_level
          |> Enum.map(fn _ ->
            Task.async(fn ->
              Enum.map(operations, fn operation ->
                operation.(namespace)
              end)
            end)
          end)

        results = Task.await_many(tasks, 5000)
        end_time = System.monotonic_time(:microsecond)

        duration_ms = (end_time - start_time) / 1000

        %{
          duration_ms: duration_ms,
          operations_count: concurrency_level * length(operations),
          ops_per_second: concurrency_level * length(operations) / (duration_ms / 1000),
          results: List.flatten(results)
        }
      end

      @doc """
      Simulate a service crash for chaos testing.
      """
      def simulate_service_crash(namespace, service) do
        case ServiceRegistry.lookup(namespace, service) do
          {:ok, pid} ->
            Process.exit(pid, :kill)
            # Wait a moment for supervisor to restart
            Process.sleep(100)
            # Verify service restarted
            wait_for_service(namespace, service, 2000)

          {:error, reason} ->
            flunk("Cannot crash service #{service}: #{inspect(reason)}")
        end
      end
    end
  end
end
