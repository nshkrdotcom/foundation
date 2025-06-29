defmodule Foundation.TestFoundation do
  @moduledoc """
  Advanced test configuration patterns for Foundation tests with full isolation.

  Use this module for tests that need complete service isolation and contamination prevention.
  This complements the existing Foundation.TestConfig module.
  """

  defmacro __using__(opts) do
    quote do
      use ExUnit.Case, unquote(opts)
      alias Foundation.TestIsolation
      import Foundation.TestFoundation

      # Ensure tests don't run concurrently if they use global state
      # Remove this if using proper isolation
      @moduletag :serial
    end
  end

  @doc """
  Standard setup for tests that need isolated Foundation services.

  ## Example

      setup do
        isolated_foundation_setup()
      end

      test "my test", %{test_context: context} do
        # Use context.signal_bus_name, context.registry_name, etc.
      end
  """
  def isolated_foundation_setup(opts \\ []) do
    {:ok, supervisor, test_context} = Foundation.TestIsolation.start_isolated_test(opts)

    ExUnit.Callbacks.on_exit(fn ->
      Foundation.TestIsolation.stop_isolated_test(supervisor)
    end)

    %{test_context: test_context, supervisor: supervisor}
  end

  @doc """
  Setup for tests that need signal routing capabilities.
  """
  def signal_routing_setup(opts \\ []) do
    test_setup = isolated_foundation_setup(opts)

    # Add signal routing specific setup
    test_context = test_setup.test_context

    # Start test-scoped signal router
    {:ok, router_pid} = start_test_signal_router(test_context)

    # Add router cleanup
    ExUnit.Callbacks.on_exit(fn ->
      if Process.alive?(router_pid) do
        GenServer.stop(router_pid)
      end
    end)

    Map.merge(test_setup, %{
      router_pid: router_pid,
      signal_bus_name: test_context.signal_bus_name
    })
  end

  @doc """
  Helper to start a test-scoped signal router.
  """
  def start_test_signal_router(_test_context) do
    # This would start your test signal router with test-scoped name
    # Implementation depends on your SignalRouter module
    # Placeholder
    {:ok, spawn(fn -> :timer.sleep(:infinity) end)}
  end
end
