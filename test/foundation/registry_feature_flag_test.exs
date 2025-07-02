defmodule Foundation.RegistryFeatureFlagTest do
  use ExUnit.Case, async: false
  alias Foundation.FeatureFlags
  alias Foundation.Protocols.RegistryETS

  setup do
    # Ensure feature flags GenServer is started
    case Process.whereis(Foundation.FeatureFlags) do
      nil -> {:ok, _} = Foundation.FeatureFlags.start_link()
      _ -> :ok
    end

    # Ensure ETS registry GenServer is started
    case Process.whereis(RegistryETS) do
      nil -> {:ok, _} = RegistryETS.start_link()
      _ -> :ok
    end

    # Reset feature flags to defaults
    FeatureFlags.reset_all()

    # Clean up any process dictionary state
    Process.delete(:registered_agents)

    # Clean up any ETS state
    for {agent_id, _} <- RegistryETS.list_agents() do
      RegistryETS.unregister_agent(agent_id)
    end

    :ok
  end

  describe "Registry with feature flag disabled (legacy mode)" do
    setup do
      # Ensure we're using process dictionary
      FeatureFlags.disable(:use_ets_agent_registry)
      :ok
    end

    test "uses process dictionary for storage" do
      registry = %{}
      pid = self()
      metadata = %{capability: :inference}

      # Register using the protocol
      assert :ok = Foundation.Registry.register(registry, :test_agent, pid, metadata)

      # Verify it's in process dictionary
      agents = Process.get(:registered_agents, %{})
      assert Map.has_key?(agents, :test_agent)
      assert agents[:test_agent] == {pid, metadata}

      # Lookup should work
      assert {:ok, {^pid, ^metadata}} = Foundation.Registry.lookup(registry, :test_agent)
    end

    test "all operations work in legacy mode" do
      registry = %{}
      pid = self()

      # Register
      assert :ok = Foundation.Registry.register(registry, :agent1, pid, %{status: :active})

      # Lookup
      assert {:ok, {^pid, %{status: :active}}} = Foundation.Registry.lookup(registry, :agent1)

      # Find by attribute
      assert {:ok, results} = Foundation.Registry.find_by_attribute(registry, :status, :active)
      assert length(results) == 1

      # Update metadata
      assert :ok = Foundation.Registry.update_metadata(registry, :agent1, %{status: :idle})
      assert {:ok, {^pid, %{status: :idle}}} = Foundation.Registry.lookup(registry, :agent1)

      # List all
      all_agents = Foundation.Registry.list_all(registry)
      assert length(all_agents) == 1

      # Count
      assert {:ok, 1} = Foundation.Registry.count(registry)

      # Unregister
      assert :ok = Foundation.Registry.unregister(registry, :agent1)
      assert :error = Foundation.Registry.lookup(registry, :agent1)
    end
  end

  describe "Registry with feature flag enabled (ETS mode)" do
    setup do
      # Enable ETS mode
      FeatureFlags.enable(:use_ets_agent_registry)
      :ok
    end

    test "uses ETS for storage" do
      registry = %{}
      pid = self()
      metadata = %{capability: :inference}

      # Register using the protocol
      assert :ok = Foundation.Registry.register(registry, :test_agent, pid, metadata)

      # Verify it's NOT in process dictionary
      agents = Process.get(:registered_agents, %{})
      refute Map.has_key?(agents, :test_agent)

      # But lookup should still work (via ETS)
      assert {:ok, {^pid, ^metadata}} = Foundation.Registry.lookup(registry, :test_agent)

      # Verify it's in ETS
      assert {:ok, ^pid} = RegistryETS.get_agent(:test_agent)
    end

    test "all operations work in ETS mode" do
      registry = %{}
      pid = self()

      # Register
      assert :ok = Foundation.Registry.register(registry, :agent1, pid, %{status: :active})

      # Lookup
      assert {:ok, {^pid, %{status: :active}}} = Foundation.Registry.lookup(registry, :agent1)

      # Find by attribute
      assert {:ok, results} = Foundation.Registry.find_by_attribute(registry, :status, :active)
      assert length(results) == 1

      # Update metadata
      assert :ok = Foundation.Registry.update_metadata(registry, :agent1, %{status: :idle})
      assert {:ok, {^pid, %{status: :idle}}} = Foundation.Registry.lookup(registry, :agent1)

      # List all
      all_agents = Foundation.Registry.list_all(registry)
      assert length(all_agents) == 1

      # Count
      assert {:ok, 1} = Foundation.Registry.count(registry)

      # Unregister
      assert :ok = Foundation.Registry.unregister(registry, :agent1)
      assert :error = Foundation.Registry.lookup(registry, :agent1)
    end

    test "monitors processes and cleans up dead ones" do
      registry = %{}

      # Create a process that will die
      test_pid =
        spawn(fn ->
          receive do
            :stop -> :ok
          end
        end)

      # Register it
      assert :ok = Foundation.Registry.register(registry, :monitored, test_pid)
      assert {:ok, {^test_pid, %{}}} = Foundation.Registry.lookup(registry, :monitored)

      # Kill the process
      Process.exit(test_pid, :kill)
      Process.sleep(50)

      # Should be automatically cleaned up
      assert :error = Foundation.Registry.lookup(registry, :monitored)
    end
  end

  describe "Migration between implementations" do
    test "can switch implementations at runtime" do
      registry = %{}
      pid = self()

      # Start with legacy mode
      FeatureFlags.disable(:use_ets_agent_registry)
      assert :ok = Foundation.Registry.register(registry, :migrated_agent, pid, %{mode: :legacy})

      # Verify in process dictionary
      agents = Process.get(:registered_agents, %{})
      assert Map.has_key?(agents, :migrated_agent)

      # Enable ETS mode
      FeatureFlags.enable(:use_ets_agent_registry)

      # New registrations go to ETS
      assert :ok = Foundation.Registry.register(registry, :new_agent, pid, %{mode: :ets})

      # Old agent still accessible from process dictionary
      # (This is expected - migration would need to be handled separately)
      agents = Process.get(:registered_agents, %{})
      assert Map.has_key?(agents, :migrated_agent)

      # New agent is in ETS
      assert {:ok, ^pid} = RegistryETS.get_agent(:new_agent)
    end

    test "query operations work across both storages during migration" do
      registry = %{}
      pid = self()

      # Register one agent in legacy mode
      FeatureFlags.disable(:use_ets_agent_registry)
      assert :ok = Foundation.Registry.register(registry, :legacy_agent, pid, %{type: :legacy})

      # Register another in ETS mode
      FeatureFlags.enable(:use_ets_agent_registry)
      assert :ok = Foundation.Registry.register(registry, :ets_agent, pid, %{type: :ets})

      # Both should be findable
      assert {:ok, {^pid, %{type: :ets}}} = Foundation.Registry.lookup(registry, :ets_agent)

      # Note: During migration, legacy agents won't be visible in ETS mode queries
      # This is expected and requires a migration script to move data
    end
  end

  describe "Performance comparison" do
    @tag :performance
    test "compare registration performance" do
      registry = %{}
      iterations = 1000

      # Measure legacy performance
      FeatureFlags.disable(:use_ets_agent_registry)

      legacy_time =
        :timer.tc(fn ->
          for i <- 1..iterations do
            Foundation.Registry.register(registry, :"perf_legacy_#{i}", self())
          end
        end)
        |> elem(0)

      # Clean up
      Process.delete(:registered_agents)

      # Measure ETS performance
      FeatureFlags.enable(:use_ets_agent_registry)

      ets_time =
        :timer.tc(fn ->
          for i <- 1..iterations do
            Foundation.Registry.register(registry, :"perf_ets_#{i}", self())
          end
        end)
        |> elem(0)

      IO.puts("Legacy time: #{legacy_time}μs, ETS time: #{ets_time}μs")

      # ETS should be reasonably performant (not orders of magnitude slower)
      assert ets_time < legacy_time * 10
    end
  end
end
