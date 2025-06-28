# Configure Foundation for testing environment
Application.put_env(:foundation, :registry_impl, nil)
Application.put_env(:foundation, :coordination_impl, nil)
Application.put_env(:foundation, :infrastructure_impl, nil)

# Start ExUnit
ExUnit.start()

# Add meck for mocking if needed in tests
Code.ensure_loaded(:meck)

# Test helper functions for creating mock implementations
defmodule TestHelpers do
  @moduledoc """
  Helper functions for Foundation tests.
  """

  def create_test_metadata(overrides \\ []) do
    defaults = %{
      capability: :test_capability,
      health_status: :healthy,
      node: :test_node,
      resources: %{
        memory_usage: 0.3,
        cpu_usage: 0.2,
        memory_available: 0.7,
        cpu_available: 0.8
      }
    }

    Map.merge(defaults, Map.new(overrides))
  end

  def create_test_agent_pid do
    spawn(fn ->
      Process.sleep(1000)
    end)
  end
end
