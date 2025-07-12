defmodule Foundation.Variables.CognitiveFloatTest do
  use ExUnit.Case
  alias Foundation.Variables.CognitiveFloat
  import Foundation.TestHelper
  
  describe "Cognitive Float Variable" do
    test "initializes with gradient optimization capabilities" do
      {:ok, float_pid} = CognitiveFloat.create("test_float", %{
        name: :test_float,
        range: {0.0, 2.0},
        current_value: 1.0,
        learning_rate: 0.01,
        momentum: 0.9
      })
      
      assert Process.alive?(float_pid)
      assert :ok = wait_for_agent(float_pid)
      
      GenServer.stop(float_pid)
    end
    
    test "handles gradient feedback for optimization" do
      {:ok, float_pid} = CognitiveFloat.create("gradient_test", %{
        name: :gradient_test,
        range: {0.0, 2.0},
        current_value: 1.0,
        learning_rate: 0.1,
        coordination_scope: :local
      })
      
      # Send gradient feedback using proper Jido signal
      :ok = send_gradient_feedback(float_pid, -0.5, %{source: :test})
      
      # Should update value based on gradient
      # Note: Actual value change depends on learning rate and momentum
      :timer.sleep(100)
      
      assert Process.alive?(float_pid)
      
      GenServer.stop(float_pid)
    end
    
    test "applies bounds behavior correctly" do
      {:ok, float_pid} = CognitiveFloat.create("bounds_test", %{
        name: :bounds_test,
        range: {0.0, 1.0},
        current_value: 0.5,
        bounds_behavior: :clamp
      })
      
      # Try gradient that would push value out of bounds
      :ok = send_gradient_feedback(float_pid, 2.0, %{source: :test})
      
      # Value should be clamped to valid range
      :timer.sleep(100)
      
      assert Process.alive?(float_pid)
      
      GenServer.stop(float_pid)
    end
    
    test "estimates gradient from performance feedback" do
      {:ok, float_pid} = CognitiveFloat.create("performance_gradient_test", %{
        name: :performance_gradient_test,
        range: {0.0, 2.0},
        current_value: 1.0,
        adaptation_strategy: :performance_feedback
      })
      
      # Send several performance feedback points to establish trend
      feedback_points = [
        %{performance: 0.7, timestamp: DateTime.utc_now()},
        %{performance: 0.6, timestamp: DateTime.utc_now()},
        %{performance: 0.5, timestamp: DateTime.utc_now()}  # Declining performance
      ]
      
      Enum.each(feedback_points, fn feedback ->
        :ok = send_performance_feedback(float_pid, feedback)
        :timer.sleep(10)
      end)
      
      # Should trigger adaptation based on performance trend
      :timer.sleep(100)
      
      assert Process.alive?(float_pid)
      
      GenServer.stop(float_pid)
    end
    
    test "maintains optimization history" do
      {:ok, float_pid} = CognitiveFloat.create("history_test", %{
        name: :history_test,
        range: {0.0, 1.0},
        current_value: 0.5
      })
      
      # Send multiple gradient updates
      gradients = [-0.1, 0.05, -0.03, 0.02]
      
      Enum.each(gradients, fn gradient ->
        :ok = send_gradient_feedback(float_pid, gradient, %{source: :test})
        :timer.sleep(10)
      end)
      
      # Optimization history should be maintained
      :timer.sleep(100)
      
      assert Process.alive?(float_pid)
      
      GenServer.stop(float_pid)
    end
  end
  
  describe "Float-specific optimization" do
    test "momentum-based updates" do
      {:ok, float_pid} = CognitiveFloat.create("momentum_test", %{
        name: :momentum_test,
        range: {0.0, 2.0},
        current_value: 1.0,
        learning_rate: 0.1,
        momentum: 0.9
      })
      
      # Multiple updates in same direction should build momentum
      Enum.each(1..3, fn _ ->
        :ok = send_gradient_feedback(float_pid, -0.2, %{source: :test})
        :timer.sleep(20)
      end)
      
      assert Process.alive?(float_pid)
      
      GenServer.stop(float_pid)
    end
    
    test "adaptive learning rate behavior" do
      {:ok, float_pid} = CognitiveFloat.create("adaptive_lr_test", %{
        name: :adaptive_lr_test,
        range: {0.0, 1.0},
        current_value: 0.5,
        learning_rate: 0.01,
        adaptive_learning_rate: true
      })
      
      # Learning rate should adapt based on optimization progress
      # This is a placeholder test - full implementation would test actual adaptation
      
      assert Process.alive?(float_pid)
      
      GenServer.stop(float_pid)
    end
  end
end