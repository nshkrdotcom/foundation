defmodule Foundation.Variables.CognitiveVariableTest do
  use ExUnit.Case
  import Foundation.TestHelper
  
  describe "Cognitive Variable Agent" do
    test "initializes as Jido agent with correct state" do
      {:ok, variable_pid} = create_test_cognitive_variable(:test_var, :float, [
        range: {0.0, 1.0},
        default: 0.5,
        coordination_scope: :local
      ])
      
      # Verify agent is alive and responsive
      assert Process.alive?(variable_pid)
      assert :ok = wait_for_agent(variable_pid)
      
      # Test getting variable status using proper Jido Action
      status = get_agent_status(variable_pid)
      assert status.name == :test_var
      assert status.type == :float
      assert status.current_value == 0.5
      assert status.coordination_scope == :local
      
      # Clean up
      GenServer.stop(variable_pid)
    end
    
    test "handles value change requests" do
      {:ok, variable_pid} = create_test_cognitive_variable(:test_change, :float, [
        range: {0.0, 2.0},
        default: 1.0,
        affected_agents: [self()]  # Add test process as affected agent
      ])
      
      # Request value change using proper Jido Action
      :ok = change_agent_value(variable_pid, 1.5, %{requester: :test})
      
      # Should receive value change notification
      receive do
        {:variable_notification, notification} ->
          assert notification.type == :variable_changed
          assert notification.variable_name == :test_change
          assert notification.old_value == 1.0
          assert notification.new_value == 1.5
      after 1000 ->
        flunk("Timeout waiting for value change notification")
      end
      
      GenServer.stop(variable_pid)
    end
    
    test "validates value ranges" do
      {:ok, variable_pid} = create_test_cognitive_variable(:test_validation, :float, [
        range: {0.0, 1.0},
        default: 0.5,
        bounds_behavior: :reject
      ])
      
      # Try to set value outside range using proper Jido Action
      :ok = change_agent_value(variable_pid, 2.0, %{requester: self()})
      
      # Give time for processing and validation
      :timer.sleep(100)
      
      # Check that value was rejected and corrected
      status = get_agent_status(variable_pid)
      # With reject behavior, should be reset to center of range
      assert status.current_value == 0.5  # (0.0 + 1.0) / 2
      
      GenServer.stop(variable_pid)
    end
    
    test "handles performance feedback for adaptation" do
      {:ok, variable_pid} = create_test_cognitive_variable(:test_adaptation, :float, [
        range: {0.0, 2.0},
        default: 1.0,
        adaptation_strategy: :performance_feedback
      ])
      
      # Send performance feedback indicating poor performance
      feedback = %{
        performance: 0.3,  # Poor performance
        cost: 0.1,
        timestamp: DateTime.utc_now()
      }
      
      :ok = send_performance_feedback(variable_pid, feedback)
      
      # Variable should adapt (might change value based on performance)
      # Note: Adaptation might not always result in value change
      # This test verifies the feedback is processed without error
      
      :timer.sleep(100)  # Give time for processing
      
      assert Process.alive?(variable_pid)
      
      GenServer.stop(variable_pid)
    end
    
    test "coordinates with affected agents" do
      # Create variable with affected agents
      {:ok, variable_pid} = create_test_cognitive_variable(:test_coordination, :float, [
        range: {0.0, 1.0},
        default: 0.5,
        affected_agents: [self()],  # Use test process as affected agent
        coordination_scope: :local
      ])
      
      # Change value to trigger coordination
      :ok = change_agent_value(variable_pid, 0.8, %{requester: :test})
      
      # Should receive coordination notification
      receive do
        {:variable_notification, notification} ->
          assert notification.type == :variable_changed
          assert notification.variable_name == :test_coordination
          assert notification.new_value == 0.8
      after 1000 ->
        flunk("Timeout waiting for coordination notification")
      end
      
      GenServer.stop(variable_pid)
    end
  end
  
  describe "Cognitive Variable Types" do
    test "supports different variable types" do
      # Test float variable
      {:ok, float_var} = create_test_cognitive_variable(:float_test, :float, [
        range: {0.0, 1.0},
        default: 0.5
      ])
      
      # Test integer variable
      {:ok, int_var} = create_test_cognitive_variable(:int_test, :integer, [
        range: {1, 10},
        default: 5
      ])
      
      # Test choice variable
      {:ok, choice_var} = create_test_cognitive_variable(:choice_test, :choice, [
        choices: [:option_a, :option_b, :option_c],
        default: :option_a
      ])
      
      # Verify all are alive
      assert Process.alive?(float_var)
      assert Process.alive?(int_var)
      assert Process.alive?(choice_var)
      
      # Clean up
      GenServer.stop(float_var)
      GenServer.stop(int_var)
      GenServer.stop(choice_var)
    end
  end
  
  describe "CognitiveFloat Gradient Optimization" do
    test "handles gradient feedback for optimization" do
      {:ok, float_var} = create_test_cognitive_variable(:gradient_test, :float, [
        range: {0.0, 2.0},
        default: 1.0,
        learning_rate: 0.1,
        momentum: 0.9
      ])
      
      # Send gradient feedback
      :ok = send_gradient_feedback(float_var, -0.5, %{source: :test_optimizer})
      
      # Give time for processing
      :timer.sleep(100)
      
      # Check that value was updated based on gradient
      status = get_agent_status(float_var)
      
      # Value should have decreased due to negative gradient
      assert status.current_value < 1.0
      
      GenServer.stop(float_var)
    end
    
    test "maintains numerical stability with large gradients" do
      {:ok, float_var} = create_test_cognitive_variable(:stability_test, :float, [
        range: {0.0, 10.0},
        default: 5.0,
        learning_rate: 0.01,
        momentum: 0.9
      ])
      
      # Send extremely large gradient (should be clamped)
      :ok = send_gradient_feedback(float_var, 2000.0, %{source: :stress_test})
      
      # Give time for processing
      :timer.sleep(100)
      
      # Agent should still be alive and stable
      assert Process.alive?(float_var)
      
      status = get_agent_status(float_var)
      # Value should still be within bounds despite large gradient
      assert status.current_value >= 0.0
      assert status.current_value <= 10.0
      
      GenServer.stop(float_var)
    end
    
    test "applies bounds behavior correctly" do
      {:ok, float_var} = create_test_cognitive_variable(:bounds_test, :float, [
        range: {0.0, 1.0},
        default: 0.9,
        bounds_behavior: :clamp,
        learning_rate: 0.5  # Large learning rate to test bounds
      ])
      
      # Send gradient that would push value outside bounds
      :ok = send_gradient_feedback(float_var, 1.0, %{source: :bounds_test})
      
      # Give time for processing
      :timer.sleep(100)
      
      status = get_agent_status(float_var)
      # Value should increase due to positive gradient but may not hit bound with momentum
      assert status.current_value > 0.9
      assert status.current_value <= 1.0  # Within bounds
      
      GenServer.stop(float_var)
    end
  end
  
  describe "Signal-based Coordination" do
    test "sends proper signals for global coordination" do
      {:ok, float_var} = create_test_cognitive_variable(:signal_test, :float, [
        range: {0.0, 1.0},
        default: 0.5,
        coordination_scope: :global
      ])
      
      # Change value to trigger signal dispatch
      :ok = change_agent_value(float_var, 0.8, %{requester: :signal_test})
      
      # Give time for signal processing
      :timer.sleep(100)
      
      # Verify agent is still functioning
      assert Process.alive?(float_var)
      
      status = get_agent_status(float_var)
      assert status.current_value == 0.8
      
      GenServer.stop(float_var)
    end
  end
end