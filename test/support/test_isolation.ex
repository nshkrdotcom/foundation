defmodule Foundation.TestIsolation do
  @moduledoc """
  Provides proper test isolation for Foundation tests by creating
  test-scoped supervision trees and avoiding global state contamination.

  This is the standard pattern for avoiding test contamination in OTP systems.
  """

  @doc """
  Creates a test-scoped supervision tree with isolated services.

  This ensures each test gets its own instances of:
  - Signal Bus
  - Telemetry handlers
  - Registry processes
  - Other stateful services

  ## Example

      setup do
        {:ok, supervisor, test_context} = TestIsolation.start_isolated_test()
        on_exit(fn -> TestIsolation.stop_isolated_test(supervisor) end)
        test_context
      end
  """
  def start_isolated_test(opts \\ []) do
    # Allow custom test context to be passed in
    test_context =
      case Keyword.get(opts, :test_context) do
        nil ->
          test_id = :erlang.unique_integer([:positive])

          %{
            test_id: test_id,
            signal_bus_name: :"test_signal_bus_#{test_id}",
            signal_router_name: :"test_signal_router_#{test_id}",
            registry_name: :"test_registry_#{test_id}",
            telemetry_prefix: "test_#{test_id}",
            supervisor_name: :"test_supervisor_#{test_id}"
          }

        custom_context ->
          custom_context
      end

    # Define test-scoped supervision tree
    children = build_isolated_children(test_context, opts)

    supervisor_opts = [
      strategy: :one_for_one,
      name: test_context.supervisor_name
    ]

    case Supervisor.start_link(children, supervisor_opts) do
      {:ok, supervisor} ->
        # Enhanced test context with supervisor reference
        enhanced_context = Map.put(test_context, :supervisor, supervisor)
        {:ok, supervisor, enhanced_context}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Builds the list of isolated child processes for the test supervision tree.
  """
  def build_isolated_children(test_context, opts \\ []) do
    base_children = [
      # Test-scoped MABEAM registry
      {MABEAM.AgentRegistry, [name: test_context.registry_name]},

      # Test-scoped ETS registry if needed
      {Registry, keys: :unique, name: :"ets_#{test_context.registry_name}"}
    ]

    # Conditionally add signal bus if requested
    signal_children =
      if Keyword.get(opts, :signal_bus, true) do
        [
          # Foundation Signal Bus for this test
          {Foundation.Services.SignalBus,
           [
             name: test_context.signal_bus_name,
             middleware: [{Jido.Signal.Bus.Middleware.Logger, []}]
           ]}
        ]
      else
        []
      end

    base_children ++ signal_children
  end

  @doc """
  Cleanly stops an isolated test supervision tree.
  """
  def stop_isolated_test(supervisor) when is_pid(supervisor) do
    # Get all children before stopping
    children = Supervisor.which_children(supervisor)

    # Stop supervisor (will stop all children)
    Supervisor.stop(supervisor, :normal, 5000)

    # Clean up any remaining telemetry handlers
    cleanup_telemetry_handlers(children)

    :ok
  catch
    # Already stopped
    :exit, {:noproc, _} -> :ok
  end

  @doc """
  Creates a test-scoped telemetry handler with automatic cleanup.
  """
  def attach_test_telemetry(test_id, event, handler_fun) do
    handler_id = "test_telemetry_#{test_id}_#{:erlang.unique_integer([:positive])}"

    :telemetry.attach(handler_id, event, handler_fun, nil)

    # Return detach function for cleanup
    fn ->
      try do
        :telemetry.detach(handler_id)
      catch
        _, _ -> :ok
      end
    end
  end

  # Private functions

  defp cleanup_telemetry_handlers(children) do
    # Extract test ID from any child name and clean up associated telemetry
    children
    |> Enum.each(fn {_id, pid, _type, _modules} ->
      if is_pid(pid) do
        # Clean up any telemetry handlers associated with this process
        # This is a best-effort cleanup
        try do
          :telemetry.list_handlers([])
          |> Enum.filter(&String.contains?(&1.id, "test_"))
          |> Enum.each(fn handler ->
            :telemetry.detach(handler.id)
          end)
        catch
          _, _ -> :ok
        end
      end
    end)
  end
end
