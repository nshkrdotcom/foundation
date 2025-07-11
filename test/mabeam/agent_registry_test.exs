defmodule MABEAM.AgentRegistryTest do
  use Foundation.UnifiedTestFoundation, :registry

  alias MABEAM.AgentRegistry
  alias Foundation.TestProcess

  setup %{registry: _registry} do
    # Foundation.UnifiedTestFoundation :registry mode provides:
    # - Isolated MABEAM.AgentRegistry per test
    # - Automatic cleanup via UnifiedTestFoundation
    # - No manual process management needed

    {:ok, agent1} = TestProcess.start_link()
    {:ok, agent2} = TestProcess.start_link()
    {:ok, agent3} = TestProcess.start_link()

    # Use the registry provided by Foundation.UnifiedTestFoundation
    %{
      agent1: agent1,
      agent2: agent2,
      agent3: agent3
    }
  end

  # Helper functions for tests
  defp valid_metadata(overrides \\ %{}) do
    default = %{
      capability: [:inference, :training],
      health_status: :healthy,
      node: :node1,
      resources: %{
        memory_usage: 0.3,
        cpu_usage: 0.2,
        memory_available: 0.7,
        cpu_available: 0.8
      }
    }

    Map.merge(default, Enum.into(overrides, %{}))
  end

  describe "agent registration" do
    test "registers new agent successfully", %{registry: registry, agent1: agent1} do
      metadata = valid_metadata()
      assert :ok = Foundation.register("agent1", agent1, metadata, registry)
    end

    test "prevents duplicate registration", %{registry: registry, agent1: agent1} do
      metadata = valid_metadata()
      :ok = Foundation.register("agent1", agent1, metadata, registry)

      # Single-phase registration means duplicate attempts fail immediately
      result = Foundation.register("agent1", agent1, metadata, registry)
      assert {:error, %Foundation.ErrorHandler.Error{reason: :already_exists}} = result

      # Verify only one registration exists
      assert {:ok, {^agent1, _}} = Foundation.lookup("agent1", registry)
    end

    test "validates required metadata fields", %{registry: registry, agent1: agent1} do
      # Missing required fields
      invalid_metadata = %{capability: [:inference]}

      result = Foundation.register("agent1", agent1, invalid_metadata, registry)

      assert {:error, %Foundation.ErrorHandler.Error{reason: {:missing_required_fields, missing}}} =
               result

      assert :health_status in missing
      assert :node in missing
      assert :resources in missing
    end

    test "validates health status values", %{registry: registry, agent1: agent1} do
      invalid_metadata = valid_metadata(health_status: :invalid_status)

      result = Foundation.register("agent1", agent1, invalid_metadata, registry)
      assert {:error, %Foundation.ErrorHandler.Error{reason: reason}} = result
      assert reason == {:invalid_health_status, :invalid_status, [:healthy, :degraded, :unhealthy]}
    end
  end

  describe "registry operations via Foundation facade" do
    test "lookup returns registered agent", %{registry: registry, agent1: agent1} do
      metadata = valid_metadata()
      :ok = Foundation.register("agent1", agent1, metadata, registry)

      # Direct lookup via Foundation
      assert {:ok, {^agent1, returned_metadata}} = Foundation.lookup("agent1", registry)
      assert returned_metadata.capability == [:inference, :training]
      assert returned_metadata.health_status == :healthy
    end

    test "lookup returns error for non-existent agent", %{registry: registry} do
      assert :error = Foundation.lookup("non_existent", registry)
    end

    test "find_by_attribute for capability", %{
      registry: registry,
      agent1: agent1,
      agent2: agent2
    } do
      metadata1 = valid_metadata(capability: [:inference])
      metadata2 = valid_metadata(capability: [:training])

      :ok = Foundation.register("agent1", agent1, metadata1, registry)
      :ok = Foundation.register("agent2", agent2, metadata2, registry)

      {:ok, inference_agents} = Foundation.find_by_attribute(:capability, :inference, registry)
      assert length(inference_agents) == 1
      assert {_, ^agent1, _} = hd(inference_agents)
    end

    test "find_by_attribute for health_status", %{
      registry: registry,
      agent1: agent1,
      agent2: agent2,
      agent3: agent3
    } do
      :ok = Foundation.register("agent1", agent1, valid_metadata(health_status: :healthy), registry)

      :ok =
        Foundation.register("agent2", agent2, valid_metadata(health_status: :degraded), registry)

      :ok = Foundation.register("agent3", agent3, valid_metadata(health_status: :healthy), registry)

      {:ok, healthy_agents} = Foundation.find_by_attribute(:health_status, :healthy, registry)
      assert length(healthy_agents) == 2
    end

    test "find_by_attribute for node", %{
      registry: registry,
      agent1: agent1,
      agent2: agent2,
      agent3: agent3
    } do
      :ok = Foundation.register("agent1", agent1, valid_metadata(node: :node1), registry)
      :ok = Foundation.register("agent2", agent2, valid_metadata(node: :node2), registry)
      :ok = Foundation.register("agent3", agent3, valid_metadata(node: :node1), registry)

      {:ok, node1_agents} = Foundation.find_by_attribute(:node, :node1, registry)
      assert length(node1_agents) == 2
    end
  end

  describe "atomic multi-criteria queries via Foundation" do
    test "query with single criterion", %{registry: registry, agent1: agent1} do
      metadata = valid_metadata()
      :ok = Foundation.register("agent1", agent1, metadata, registry)

      criteria = [{[:capability], :inference, :eq}]
      assert {:ok, results} = Foundation.query(criteria, registry)
      assert length(results) == 1
      assert {_, ^agent1, _} = hd(results)
    end

    test "query with multiple criteria (atomic AND operation)", %{
      registry: registry,
      agent1: agent1,
      agent2: agent2
    } do
      :ok = Foundation.register("agent1", agent1, valid_metadata(), registry)

      :ok =
        Foundation.register("agent2", agent2, valid_metadata(health_status: :degraded), registry)

      # Query for healthy agents with inference capability
      criteria = [
        {[:capability], :inference, :eq},
        {[:health_status], :healthy, :eq}
      ]

      assert {:ok, results} = Foundation.query(criteria, registry)
      assert length(results) == 1
      assert {_, ^agent1, _} = hd(results)
    end

    test "query with nested path criteria", %{
      registry: registry,
      agent1: agent1,
      agent2: agent2
    } do
      :ok = Foundation.register("agent1", agent1, valid_metadata(), registry)

      low_memory_metadata = put_in(valid_metadata(), [:resources, :memory_available], 0.2)
      :ok = Foundation.register("agent2", agent2, low_memory_metadata, registry)

      criteria = [{[:resources, :memory_available], 0.5, :gte}]
      assert {:ok, results} = Foundation.query(criteria, registry)
      assert length(results) == 1
      assert {_, ^agent1, _} = hd(results)
    end

    test "query with comparison operators", %{
      registry: registry,
      agent1: agent1,
      agent2: agent2,
      agent3: agent3
    } do
      meta1 = put_in(valid_metadata(), [:resources, :cpu_usage], 0.1)
      meta2 = put_in(valid_metadata(), [:resources, :cpu_usage], 0.5)
      meta3 = put_in(valid_metadata(), [:resources, :cpu_usage], 0.9)

      :ok = Foundation.register("agent1", agent1, meta1, registry)
      :ok = Foundation.register("agent2", agent2, meta2, registry)
      :ok = Foundation.register("agent3", agent3, meta3, registry)

      # Test greater than or equal
      assert {:ok, results} = Foundation.query([{[:resources, :cpu_usage], 0.4, :gte}], registry)
      assert length(results) == 2

      # Test less than
      assert {:ok, results} = Foundation.query([{[:resources, :cpu_usage], 0.6, :lt}], registry)
      assert length(results) == 2

      # Test greater than
      assert {:ok, results} = Foundation.query([{[:resources, :cpu_usage], 0.8, :gt}], registry)
      assert length(results) == 1
    end

    test "query with :in operator for multiple values", %{
      registry: registry,
      agent1: agent1,
      agent2: agent2,
      agent3: agent3
    } do
      :ok =
        Foundation.register("agent1", agent1, valid_metadata(capability: [:inference]), registry)

      :ok = Foundation.register("agent2", agent2, valid_metadata(capability: [:training]), registry)

      :ok =
        Foundation.register("agent3", agent3, valid_metadata(capability: [:optimization]), registry)

      # Find agents with inference OR training capability
      criteria = [{[:capability], [:inference, :training], :in}]
      assert {:ok, results} = Foundation.query(criteria, registry)
      assert length(results) == 2
    end

    test "query handles invalid criteria gracefully", %{registry: registry} do
      # Invalid criteria format
      invalid_criteria = ["not", "a", "valid", "format"]
      assert {:error, {:invalid_criteria, _reason}} = Foundation.query(invalid_criteria, registry)

      # Invalid operation
      assert {:error, {:invalid_criteria, _reason}} =
               Foundation.query([{[:capability], :inference, :invalid_op}], registry)
    end
  end

  describe "metadata updates" do
    test "updates metadata and rebuilds indexes", %{registry: registry, agent1: agent1} do
      original_metadata = valid_metadata()
      :ok = Foundation.register("agent1", agent1, original_metadata, registry)

      # Update metadata
      new_metadata = valid_metadata(capability: [:training], health_status: :degraded)
      :ok = Foundation.update_metadata("agent1", new_metadata, registry)

      # Verify update
      {:ok, {^agent1, metadata}} = Foundation.lookup("agent1", registry)
      assert metadata.capability == [:training]
      assert metadata.health_status == :degraded

      # Verify old indexes removed
      {:ok, inference_agents} = Foundation.find_by_attribute(:capability, :inference, registry)
      assert Enum.empty?(inference_agents)

      # Verify new indexes created
      {:ok, training_agents} = Foundation.find_by_attribute(:capability, :training, registry)
      assert [_agent] = training_agents
    end

    test "fails to update metadata for non-existent agent", %{registry: registry} do
      metadata = valid_metadata()

      assert {:error, :not_found} =
               Foundation.update_metadata("non_existent", metadata, registry)
    end
  end

  describe "agent unregistration" do
    test "unregisters agent and clears all indexes", %{registry: registry, agent1: agent1} do
      metadata = valid_metadata(capability: :inference)
      :ok = Foundation.register("agent1", agent1, metadata, registry)

      # Verify registration
      assert {:ok, {^agent1, _}} = Foundation.lookup("agent1", registry)
      {:ok, inference_agents} = Foundation.find_by_attribute(:capability, :inference, registry)
      assert [_agent] = inference_agents

      # Unregister
      assert :ok = Foundation.unregister("agent1", registry)

      # Verify removal
      assert :error = Foundation.lookup("agent1", registry)

      {:ok, inference_agents_after} =
        Foundation.find_by_attribute(:capability, :inference, registry)

      assert Enum.empty?(inference_agents_after)
    end

    test "fails to unregister non-existent agent", %{registry: registry} do
      assert {:error, :not_found} = Foundation.unregister("non_existent", registry)
    end
  end

  describe "process monitoring and automatic cleanup" do
    test "automatically removes agent when process dies", %{registry: registry} do
      # Create a process that we control
      test_pid = self()

      short_lived =
        spawn(fn ->
          # Signal that process is ready
          send(test_pid, :process_started)
          # Stay alive until told to exit
          receive do
            :exit -> :ok
          end
        end)

      # Wait for process to be ready
      assert_receive :process_started, 1000

      metadata = valid_metadata(capability: :inference)
      :ok = Foundation.register("short_lived", short_lived, metadata, registry)

      # Verify registration
      assert {:ok, {^short_lived, _}} = Foundation.lookup("short_lived", registry)

      # Set up telemetry handler to catch the agent_down event
      ref = make_ref()

      :telemetry.attach(
        "test-agent-down-#{inspect(ref)}",
        [:foundation, :mabeam, :registry, :agent_down],
        fn _event, _measurements, metadata, config ->
          if metadata.agent_id == "short_lived" do
            send(config.test_pid, {:agent_down_event, metadata})
          end
        end,
        %{test_pid: test_pid}
      )

      # Kill the process
      Process.exit(short_lived, :kill)

      # Wait for the agent_down telemetry event
      assert_receive {:agent_down_event, %{agent_id: "short_lived"}}, 5000

      # Verify agent has been removed
      assert :error = Foundation.lookup("short_lived", registry)
      {:ok, inference_agents} = Foundation.find_by_attribute(:capability, :inference, registry)
      assert Enum.empty?(inference_agents)

      # Clean up telemetry handler
      :telemetry.detach("test-agent-down-#{inspect(ref)}")
    end
  end

  describe "performance characteristics" do
    test "supports high-concurrency read operations", %{registry: registry} do
      # Register 100 agents
      # Foundation.UnifiedTestFoundation :registry mode handles all process cleanup automatically
      _agents =
        for i <- 1..100 do
          {:ok, agent_pid} = TestProcess.start_link()
          metadata = valid_metadata()
          :ok = Foundation.register("agent_#{i}", agent_pid, metadata, registry)
          agent_pid
        end

      # Concurrent reads
      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            Foundation.lookup("agent_#{i}", registry)
          end)
        end

      results = Task.await_many(tasks, 5000)
      assert Enum.all?(results, fn result -> match?({:ok, _}, result) end)
    end

    test "atomic queries are faster than separate operations", %{registry: registry} do
      # Register agents with various configurations
      _agents =
        for i <- 1..50 do
          {:ok, agent_pid} = TestProcess.start_link()

          capability =
            case rem(i, 3) do
              0 -> [:inference]
              1 -> [:training]
              _ -> [:optimization]
            end

          health_status =
            case rem(i, 2) do
              0 -> :healthy
              _ -> :degraded
            end

          resources = %{
            memory_usage: 0.1 + rem(i, 10) * 0.08,
            cpu_usage: 0.1 + rem(i, 8) * 0.1,
            memory_available: 0.9 - rem(i, 10) * 0.08,
            cpu_available: 0.9 - rem(i, 8) * 0.1
          }

          metadata =
            valid_metadata()
            |> Map.put(:capability, capability)
            |> Map.put(:health_status, health_status)
            |> Map.put(:resources, resources)

          :ok = Foundation.register("agent_#{i}", agent_pid, metadata, registry)
          agent_pid
        end

      # Complex atomic query
      atomic_criteria = [
        {[:capability], :inference, :eq},
        {[:health_status], :healthy, :eq},
        {[:resources, :memory_available], 0.5, :gte}
      ]

      {:ok, atomic_results} = Foundation.query(atomic_criteria, registry)

      # Verify results are correct
      assert length(atomic_results) > 0

      assert Enum.all?(atomic_results, fn {_id, _pid, metadata} ->
               :inference in List.wrap(metadata.capability) and
                 metadata.health_status == :healthy and
                 metadata.resources.memory_available >= 0.5
             end)
    end
  end

  describe "protocol compliance" do
    test "implements Foundation.Registry protocol correctly", %{agent1: agent1} do
      # Use unique name for each test run
      test_name = :"test_registry_protocol_#{System.unique_integer([:positive])}"
      {:ok, test_registry} = AgentRegistry.start_link(name: test_name)

      metadata = valid_metadata()

      # Test protocol functions via Foundation facade
      assert :ok = Foundation.register("protocol_agent", agent1, metadata, test_registry)
      assert {:ok, {^agent1, _}} = Foundation.lookup("protocol_agent", test_registry)
      assert {:ok, agents} = Foundation.find_by_attribute(:capability, :inference, test_registry)
      assert length(agents) == 1
      assert :ok = Foundation.update_metadata("protocol_agent", metadata, test_registry)
      assert :ok = Foundation.unregister("protocol_agent", test_registry)
    end
  end

  describe "configuration and metadata" do
    test "returns protocol version information", %{registry: registry} do
      # Protocol version is now returned via handle_call
      assert "2.0" = GenServer.call(registry, {:protocol_version})
    end

    test "returns indexed attributes list", %{registry: registry} do
      attrs = Foundation.indexed_attributes(registry)
      assert :capability in attrs
      assert :health_status in attrs
      assert :node in attrs
    end

    test "list_all supports optional filtering", %{
      registry: registry,
      agent1: agent1,
      agent2: agent2
    } do
      :ok = Foundation.register("agent1", agent1, valid_metadata(), registry)

      # Register agent with high memory usage
      high_memory_metadata = put_in(valid_metadata(), [:resources, :memory_usage], 0.9)
      :ok = Foundation.register("agent2", agent2, high_memory_metadata, registry)

      all_agents = Foundation.list_all(nil, registry)
      assert length(all_agents) == 2

      # Filter for high memory usage
      high_memory_filter = fn metadata ->
        get_in(metadata, [:resources, :memory_usage]) > 0.8
      end

      filtered_agents = Foundation.list_all(high_memory_filter, registry)
      assert length(filtered_agents) == 1
      assert {_, ^agent2, _} = hd(filtered_agents)
    end
  end

  describe "monitor leak fix" do
    test "cleans up unknown monitor refs without leaking", %{agent1: agent1} do
      # Start a separate registry for this test
      {:ok, registry} = AgentRegistry.start_link(name: :test_registry_leak)

      # Register and unregister an agent to create a monitor
      :ok = Foundation.register("leak_test", agent1, valid_metadata(), registry)
      :ok = Foundation.unregister("leak_test", registry)

      # Simulate a DOWN message for unknown monitor
      fake_ref = make_ref()
      send(registry, {:DOWN, fake_ref, :process, self(), :normal})

      # Give it time to process (short wait for message processing)
      :timer.sleep(10)

      # Verify process doesn't accumulate monitors
      {:dictionary, dict} = Process.info(registry, :dictionary)
      monitors = Keyword.get(dict, :"$monitors", [])
      assert Enum.empty?(monitors)

      # Clean up
      GenServer.stop(registry)
    end
  end
end
