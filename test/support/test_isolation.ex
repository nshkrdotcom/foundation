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
    test_id = :erlang.unique_integer([:positive])
    
    # Create unique names for all services in this test
    test_context = %{
      test_id: test_id,
      signal_bus_name: :"test_signal_bus_#{test_id}",
      router_name: :"test_signal_router_#{test_id}",
      registry_name: :"test_registry_#{test_id}",
      telemetry_prefix: "test_#{test_id}"
    }
    
    # Define test-scoped supervision tree
    children = [
      # Test-scoped signal bus
      {JidoFoundation.Bridge, [name: test_context.signal_bus_name]},
      
      # Test-scoped registry if needed
      {Registry, keys: :unique, name: test_context.registry_name},
      
      # Add other services as needed
    ]
    
    supervisor_opts = [
      strategy: :one_for_one,
      name: :"test_supervisor_#{test_id}"
    ]
    
    case Supervisor.start_link(children, supervisor_opts) do
      {:ok, supervisor} ->
        {:ok, supervisor, test_context}
        
      {:error, reason} ->
        {:error, reason}
    end
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
    :exit, {:noproc, _} -> :ok  # Already stopped
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