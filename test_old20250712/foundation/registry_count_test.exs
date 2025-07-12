defmodule Foundation.RegistryCountTest do
  use ExUnit.Case, async: true

  alias MABEAM.AgentRegistry

  setup do
    # Generate unique registry ID for each test to avoid conflicts
    registry_id = :"test_registry_#{:erlang.unique_integer([:positive])}"
    registry_name = :"test_registry_process_#{:erlang.unique_integer([:positive])}"
    {:ok, registry} = start_supervised({AgentRegistry, [id: registry_id, name: registry_name]})
    {:ok, registry: registry}
  end

  describe "Foundation.Registry.count/1" do
    test "returns {:ok, 0} for empty registry", %{registry: registry} do
      assert {:ok, 0} = Foundation.Registry.count(registry)
    end

    test "returns correct count after registrations", %{registry: registry} do
      # Register some agents
      metadata = %{
        capability: [:test],
        health_status: :healthy,
        node: node(),
        resources: %{}
      }

      assert :ok = Foundation.Registry.register(registry, :agent1, self(), metadata)
      assert {:ok, 1} = Foundation.Registry.count(registry)

      assert :ok = Foundation.Registry.register(registry, :agent2, self(), metadata)
      assert {:ok, 2} = Foundation.Registry.count(registry)

      assert :ok = Foundation.Registry.register(registry, :agent3, self(), metadata)
      assert {:ok, 3} = Foundation.Registry.count(registry)
    end

    test "decreases count after unregistration", %{registry: registry} do
      metadata = %{
        capability: [:test],
        health_status: :healthy,
        node: node(),
        resources: %{}
      }

      # Register 3 agents
      assert :ok = Foundation.Registry.register(registry, :agent1, self(), metadata)
      assert :ok = Foundation.Registry.register(registry, :agent2, self(), metadata)
      assert :ok = Foundation.Registry.register(registry, :agent3, self(), metadata)
      assert {:ok, 3} = Foundation.Registry.count(registry)

      # Unregister one
      assert :ok = Foundation.Registry.unregister(registry, :agent2)
      assert {:ok, 2} = Foundation.Registry.count(registry)

      # Unregister another
      assert :ok = Foundation.Registry.unregister(registry, :agent1)
      assert {:ok, 1} = Foundation.Registry.count(registry)
    end

    test "handles concurrent operations correctly", %{registry: registry} do
      metadata = %{
        capability: [:test],
        health_status: :healthy,
        node: node(),
        resources: %{}
      }

      # Spawn multiple processes to register agents concurrently
      parent = self()

      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            agent_id = :"agent_#{i}"
            # Create a new process for each agent
            {:ok, pid} = Agent.start_link(fn -> :ok end)
            result = Foundation.Registry.register(registry, agent_id, pid, metadata)
            send(parent, {:registered, agent_id, result})
            result
          end)
        end

      # Wait for all registrations to complete
      Enum.each(tasks, &Task.await/1)

      # Verify count
      assert {:ok, 100} = Foundation.Registry.count(registry)
    end
  end

  describe "Foundation facade count/1" do
    test "works with configured registry", %{registry: registry} do
      # Test with explicit implementation
      assert {:ok, 0} = Foundation.count(registry)

      metadata = %{
        capability: [:test],
        health_status: :healthy,
        node: node(),
        resources: %{}
      }

      Foundation.register(:test_agent, self(), metadata, registry)
      assert {:ok, 1} = Foundation.count(registry)
    end
  end

  describe "PID implementation" do
    test "count/1 works via GenServer call", %{registry: registry} do
      # The PID implementation should also work
      assert {:ok, 0} = GenServer.call(registry, {:count})
    end
  end

  describe "Any implementation" do
    test "count/1 works with process dictionary storage" do
      # Clear any existing state
      Process.delete(:registered_agents)

      # Test with a dummy implementation that triggers the Any protocol
      dummy_impl = :some_atom
      assert {:ok, 0} = Foundation.Registry.count(dummy_impl)

      # Register some agents using the Any implementation
      Foundation.Registry.register(dummy_impl, :agent1, self(), %{})
      assert {:ok, 1} = Foundation.Registry.count(dummy_impl)

      Foundation.Registry.register(dummy_impl, :agent2, self(), %{})
      Foundation.Registry.register(dummy_impl, :agent3, self(), %{})
      assert {:ok, 3} = Foundation.Registry.count(dummy_impl)
    end
  end
end
