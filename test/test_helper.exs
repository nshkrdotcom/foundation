# Test Helper for Ground-up Jido-native Foundation Platform

# Start the testing application
Application.put_env(:foundation, :test_mode, true)

# Configure test environment - capture logs to prevent console spam during tests
ExUnit.start(capture_log: true)

# Ensure Jido is available for testing
Application.ensure_all_started(:jido)

defmodule Foundation.TestHelper do
  @moduledoc """
  Test helper utilities for the ground-up Jido-native Foundation platform.
  """
  
  def start_test_application do
    # Start Foundation application in test mode
    {:ok, _pid} = Foundation.start(:normal, [])
  end
  
  def stop_test_application do
    # Clean shutdown for tests
    :ok = Application.stop(:foundation)
  end
  
  def wait_for_agent(agent_pid, timeout \\ 5000) do
    # Wait for Jido agent to be ready using proper Signal communication
    try do
      signal = Jido.Signal.new!(%{
        type: "get_status",
        source: "test",
        data: %{include_metadata: true}
      })
      
      case Jido.Agent.Server.call(agent_pid, signal, timeout) do
        {:ok, _response} -> :ok
        {:error, reason} -> {:error, reason}
      end
    catch
      :exit, reason -> {:error, reason}
    end
  end
  
  def create_test_cognitive_variable(name, type, opts \\ []) do
    # Helper to create test cognitive variables using proper Jido.Agent approach
    initial_state = %{
      name: name,
      type: type,
      current_value: Keyword.get(opts, :default, get_default_for_type(type)),
      coordination_scope: Keyword.get(opts, :coordination_scope, :local),
      range: Keyword.get(opts, :range),
      choices: Keyword.get(opts, :choices),
      affected_agents: Keyword.get(opts, :affected_agents, []),
      adaptation_strategy: Keyword.get(opts, :adaptation_strategy, :none)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
    
    case type do
      :float ->
        # Create CognitiveFloat with enhanced float capabilities
        enhanced_state = Map.merge(initial_state, %{
          learning_rate: Keyword.get(opts, :learning_rate, 0.01),
          momentum: Keyword.get(opts, :momentum, 0.9),
          gradient_estimate: 0.0,
          velocity: 0.0,
          optimization_history: [],
          bounds_behavior: Keyword.get(opts, :bounds_behavior, :clamp)
        })
        Foundation.Variables.CognitiveFloat.create("test_#{name}", enhanced_state)
      _ ->
        Foundation.Variables.CognitiveVariable.create("test_#{name}", initial_state)
    end
  end
  
  def get_agent_status(agent_pid) do
    # Helper to get agent status using proper Jido Action
    signal = Jido.Signal.new!(%{
      type: "get_status",
      source: "test",
      data: %{include_metadata: true, include_history: false}
    })
    
    case Jido.Agent.Server.call(agent_pid, signal, 5000) do
      {:ok, response} -> response
      {:error, reason} -> {:error, reason}
    end
  end
  
  def change_agent_value(agent_pid, new_value, context \\ %{}) do
    # Helper to change agent value using proper Jido Action
    signal = Jido.Signal.new!(%{
      type: "change_value",
      source: "test",
      data: %{
        new_value: new_value,
        requester: :test,
        context: context
      }
    })
    
    case Jido.Agent.Server.cast(agent_pid, signal) do
      {:ok, _signal_id} -> :ok
      error -> error
    end
  end
  
  def send_performance_feedback(agent_pid, feedback) do
    # Helper to send performance feedback using proper Jido Action
    signal = Jido.Signal.new!(%{
      type: "performance_feedback",
      source: "test",
      data: feedback
    })
    
    case Jido.Agent.Server.cast(agent_pid, signal) do
      {:ok, _signal_id} -> :ok
      error -> error
    end
  end
  
  def send_gradient_feedback(agent_pid, gradient, context \\ %{}) do
    # Helper to send gradient feedback for CognitiveFloat agents
    signal = Jido.Signal.new!(%{
      type: "gradient_feedback", 
      source: "test",
      data: %{
        gradient: gradient,
        source: :test,
        timestamp: DateTime.utc_now(),
        context: context
      }
    })
    
    case Jido.Agent.Server.cast(agent_pid, signal) do
      {:ok, _signal_id} -> :ok
      error -> error
    end
  end
  
  defp get_default_for_type(:float), do: 0.5
  defp get_default_for_type(:integer), do: 1
  defp get_default_for_type(:choice), do: :option_a
  defp get_default_for_type(_), do: nil
end