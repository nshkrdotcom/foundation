# Configure Foundation for testing environment
Application.put_env(:foundation, :registry_impl, nil)
Application.put_env(:foundation, :coordination_impl, nil)
Application.put_env(:foundation, :infrastructure_impl, nil)

# Start ExUnit
ExUnit.start()

# Add meck for mocking if needed in tests
Code.ensure_loaded(:meck)

# Ensure protocol implementations are loaded
# The protocol implementation is in test/support which is compiled in test env
# We need to ensure the protocol itself is loaded
Code.ensure_loaded!(Foundation.Registry)

# In CI, protocols might be consolidated before test support files are available
# Explicitly compile the implementation module to ensure it's available
if Mix.env() == :test do
  # Check if the PID implementation is already available
  impl_module = Foundation.Registry.impl_for(self())
  
  # Only compile if not already loaded
  if impl_module == Foundation.Registry.Any do
    support_path = Path.join([__DIR__, "support"])
    impl_file = Path.join(support_path, "agent_registry_pid_impl.ex")
    
    if File.exists?(impl_file) do
      Code.compile_file(impl_file)
    end
  end
end

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
