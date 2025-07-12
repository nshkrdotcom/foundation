defmodule Foundation.TestConfig do
  @moduledoc """
  Centralized test configuration to ensure parallel test safety.

  This module ensures tests never use Application.put_env/delete_env
  for registry configuration, which causes race conditions in parallel tests.
  """

  @doc """
  Setup hook for tests that need a registry.

  Usage in your test module:

      use Foundation.TestConfig, :registry

      test "something", %{registry: registry} do
        # registry is available here
        Foundation.register("key", self(), %{}, registry)
      end
  """
  defmacro __using__(:registry) do
    quote do
      setup context do
        # Generate unique registry name
        test_name =
          Map.get(context, :test, "unknown")
          |> to_string()
          |> String.replace(~r/[^a-zA-Z0-9_]/, "_")

        module_name =
          __MODULE__
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

        {:ok, registry: registry}
      end
    end
  end

  @doc """
  Ensures a function call includes the registry parameter.
  """
  def with_registry(registry, fun) when is_function(fun, 1) do
    fun.(registry)
  end

  @doc """
  Helper to update opts with registry.
  """
  def add_registry_opt(opts, registry) when is_list(opts) do
    Keyword.put(opts, :registry, registry)
  end
end
