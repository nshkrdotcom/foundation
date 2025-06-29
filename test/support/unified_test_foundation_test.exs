defmodule Foundation.UnifiedTestFoundationTest do
  @moduledoc """
  Test suite to validate the unified test foundation infrastructure.
  """

  use Foundation.UnifiedTestFoundation, :contamination_detection

  describe "unified test foundation infrastructure" do
    test "basic mode provides minimal setup", %{test_context: context} do
      assert context.test_id
      # Since we're using contamination_detection mode
      assert context.mode == :contamination_detection
      assert context.contamination_detection == true
    end

    test "contamination detection captures system state", %{
      test_context: context,
      initial_state: state
    } do
      assert state.test_id == context.test_id
      assert state.timestamp
      assert state.processes
      assert state.telemetry
      assert state.ets
      assert state.memory
    end

    test "isolated services are properly scoped", %{test_context: context} do
      # Verify test-scoped names are generated
      assert String.contains?(to_string(context.signal_bus_name), "test_signal_bus_")
      assert String.contains?(to_string(context.registry_name), "test_registry_")
      assert String.contains?(to_string(context.supervisor_name), "test_supervisor_")

      # Verify services are actually running with scoped names
      assert Process.whereis(context.supervisor_name) != nil
    end
  end
end
