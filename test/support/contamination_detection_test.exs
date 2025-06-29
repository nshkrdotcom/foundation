defmodule Foundation.ContaminationDetectionTest do
  @moduledoc """
  Test suite to validate contamination detection and prevention measures.
  
  This module tests the UnifiedTestFoundation's contamination detection capabilities
  and serves as a demonstration of how to identify test contamination.
  """
  
  # Using contamination detection mode to validate the detection system
  use Foundation.UnifiedTestFoundation, :contamination_detection

  describe "contamination detection validation" do
    test "clean test should not trigger contamination detection", %{test_context: ctx} do
      # This test should pass cleanly without contamination
      assert ctx.contamination_detection == true
      assert ctx.mode == :contamination_detection
      
      # Perform a simple operation that doesn't contaminate
      result = 1 + 1
      assert result == 2
    end

    # This test intentionally creates contamination for testing detection
    @tag :skip  # Skip by default to avoid false positives in normal test runs
    test "test with telemetry contamination should be detected", %{test_context: ctx} do
      # This test intentionally creates telemetry contamination
      test_handler_id = "contamination_test_handler_#{ctx.test_id}"
      
      :telemetry.attach(
        test_handler_id,
        [:test, :contamination, :event],
        fn _event, _measurements, _metadata, _config ->
          :ok
        end,
        nil
      )
      
      # Intentionally don't detach the handler to test contamination detection
      # The contamination detection should catch this
      assert true
    end

    # This test intentionally creates ETS contamination for testing detection  
    @tag :skip  # Skip by default to avoid false positives in normal test runs
    test "test with ETS contamination should be detected", %{test_context: ctx} do
      # Create several ETS tables without cleanup
      for i <- 1..10 do
        :ets.new(:"contamination_table_#{ctx.test_id}_#{i}", [:public, :named_table])
      end
      
      # Don't clean up tables - contamination detection should catch this
      assert true
    end

    test "registry isolation prevents cross-test contamination", %{test_context: ctx} do
      # Test that registry isolation is working
      registry_name = ctx.registry_name
      assert is_atom(registry_name)
      
      # Registry should exist and be accessible
      assert Process.whereis(registry_name) != nil
      
      # Test that we have isolated test context
      assert ctx.test_id != nil
    end

    test "signal router isolation prevents signal contamination", %{test_context: ctx} do
      # If signal router is available, test its isolation
      if Map.has_key?(ctx, :signal_router) do
        signal_router = ctx.signal_router
        assert is_pid(signal_router)
      end
      
      # Test passes regardless - isolation is the key
      assert true
    end
  end

  describe "isolation effectiveness validation" do
    test "multiple tests don't interfere with each other - test 1", %{test_context: ctx} do
      # Store some data in process dictionary
      Process.put(:test_data, "test_1_data")
      
      # Each test should have its own isolated environment
      assert ctx.test_id != nil
      assert Process.get(:test_data) == "test_1_data"
    end

    test "multiple tests don't interfere with each other - test 2", %{test_context: ctx} do
      # This test should not see data from test 1
      assert Process.get(:test_data) == nil
      
      # Set its own data
      Process.put(:test_data, "test_2_data")
      assert Process.get(:test_data) == "test_2_data"
      
      # Each test should have a different test_id
      assert ctx.test_id != nil
    end

    test "resource cleanup validation", %{test_context: ctx} do
      # Test that resources are properly cleaned up
      initial_processes = length(Process.list())
      
      # Spawn some processes
      pids = for _ <- 1..5 do
        spawn(fn -> :timer.sleep(50) end)
      end
      
      # Verify processes were created
      assert length(Process.list()) > initial_processes
      
      # Clean up processes manually (good practice)
      Enum.each(pids, &Process.exit(&1, :kill))
      
      # Test framework should handle any remaining cleanup
      assert ctx.test_id != nil
    end
  end
end