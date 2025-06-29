defmodule Foundation.IsolatedSignalRoutingTest do
  @moduledoc """
  Example of properly isolated signal routing test using test supervision trees.

  This demonstrates the correct pattern for avoiding test contamination.
  """

  use ExUnit.Case
  alias Foundation.TestIsolation
  alias JidoFoundation.Bridge

  describe "Properly Isolated Signal Routing" do
    setup do
      # Start isolated test environment
      {:ok, supervisor, test_context} = TestIsolation.start_isolated_test()

      # Clean shutdown on test completion
      on_exit(fn ->
        TestIsolation.stop_isolated_test(supervisor)
      end)

      # Return test context with isolated services
      Map.put(test_context, :supervisor, supervisor)
    end

    test "signals route correctly in isolated environment", %{
      signal_bus_name: bus_name,
      test_id: test_id
    } do
      # Create test agent
      {:ok, agent} = Task.start_link(fn -> :timer.sleep(:infinity) end)

      # Set up test telemetry handler with automatic cleanup
      test_pid = self()

      detach_fn =
        TestIsolation.attach_test_telemetry(
          test_id,
          [:jido, :signal, :emitted],
          fn _event, measurements, metadata, _config ->
            send(test_pid, {:signal_emitted, measurements, metadata})
          end
        )

      # Clean up telemetry on exit
      on_exit(detach_fn)

      # Emit signal using isolated bus
      Bridge.emit_signal(
        agent,
        %{
          type: "test.signal",
          data: %{test: true}
        },
        bus: bus_name
      )

      # Verify signal was processed
      assert_receive {:signal_emitted, _measurements, metadata}
      assert metadata[:signal_type] == "test.signal"

      # Clean up agent
      Process.exit(agent, :normal)
    end
  end
end
