defmodule Foundation.Test.RegistryTestHelper do
  @moduledoc """
  Helper module for setting up isolated registries in tests.

  This module solves the parallel test execution problem by providing
  each test with its own registry instance instead of using global
  Application configuration.
  """

  @doc """
  Sets up an isolated registry for a test.

  Returns a map with:
  - registry: The registry PID
  - opts: Options to pass to Foundation functions

  ## Usage

      setup do
        Foundation.Test.RegistryTestHelper.setup_registry()
      end
      
      test "something", %{registry: registry, foundation_opts: opts} do
        Foundation.register("key", self(), %{}, opts)
      end
  """
  def setup_registry(context \\ %{}) do
    # Generate unique registry name based on test context
    test_name =
      Map.get(context, :test, "unknown_test")
      |> to_string()
      |> String.replace(" ", "_")
      |> String.replace(~r/[^a-zA-Z0-9_]/, "")

    unique_id = :"test_registry_#{test_name}_#{System.unique_integer([:positive])}"

    # Check if one is already running and stop it
    case Process.whereis(unique_id) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end

    # Start registry
    {:ok, registry} = MABEAM.AgentRegistry.start_link(name: unique_id)

    # Return both the registry and options for Foundation calls
    {:ok, registry: registry, foundation_opts: [impl: registry]}
  end

  @doc """
  Helper to cleanup registry on test exit.
  """
  def cleanup_registry(registry) when is_pid(registry) do
    if Process.alive?(registry) do
      GenServer.stop(registry)
    end
  end
end
