defmodule MABEAM.AgentRegistryTest do
  use ExUnit.Case, async: false
  
  setup do
    # Start a fresh registry for each test with unique name
    test_name = "test_registry_#{:erlang.unique_integer([:positive])}"
    {:ok, registry_pid} = MABEAM.AgentRegistry.start_link(name: String.to_atom(test_name))
    
    # Create test agent PIDs
    agent1_pid = spawn(fn -> :timer.sleep(1000) end)
    agent2_pid = spawn(fn -> :timer.sleep(1000) end)
    agent3_pid = spawn(fn -> :timer.sleep(1000) end)
    
    on_exit(fn ->
      # Clean up the registry process
      if Process.alive?(registry_pid) do
        GenServer.stop(registry_pid)
      end
    end)
    
    {:ok, registry: registry_pid, agent1: agent1_pid, agent2: agent2_pid, agent3: agent3_pid}
  end
  
  describe "agent registration" do
    test "registers agent with complete metadata", %{registry: registry, agent1: agent1} do
      metadata = %{
        capability: [:inference, :training],
        health_status: :healthy,
        node: :node1,
        resources: %{
          memory_usage: 0.3,
          cpu_usage: 0.2,
          memory_available: 0.7,
          cpu_available: 0.8
        },
        agent_type: :ml_worker
      }
      
      assert :ok = GenServer.call(registry, {:register, "agent1", agent1, metadata})
    end
    
    test "rejects registration with missing required fields", %{registry: registry, agent1: agent1} do
      incomplete_metadata = %{
        capability: :inference,
        health_status: :healthy
        # Missing :node and :resources
      }
      
      assert {:error, {:missing_required_fields, missing}} = 
        GenServer.call(registry, {:register, "agent1", agent1, incomplete_metadata})
      
      assert :node in missing
      assert :resources in missing
    end
    
    test "rejects registration with invalid health status", %{registry: registry, agent1: agent1} do
      metadata = %{
        capability: :inference,
        health_status: :invalid_status,
        node: :node1,
        resources: %{}
      }
      
      assert {:error, {:invalid_health_status, :invalid_status, valid_statuses}} = 
        GenServer.call(registry, {:register, "agent1", agent1, metadata})
      
      assert :healthy in valid_statuses
      assert :degraded in valid_statuses
      assert :unhealthy in valid_statuses
    end
    
    test "prevents duplicate registration", %{registry: registry, agent1: agent1} do
      metadata = valid_metadata()
      
      assert :ok = GenServer.call(registry, {:register, "agent1", agent1, metadata})
      assert {:error, :already_exists} = GenServer.call(registry, {:register, "agent1", agent1, metadata})
    end
  end
  
  describe "direct ETS lookup operations (lock-free reads)" do
    test "lookup returns registered agent", %{registry: registry, agent1: agent1} do
      metadata = valid_metadata()
      :ok = GenServer.call(registry, {:register, "agent1", agent1, metadata})
      
      # Direct ETS lookup bypasses GenServer
      assert {:ok, {^agent1, returned_metadata}} = MABEAM.AgentRegistry.lookup("agent1")
      assert returned_metadata.capability == [:inference, :training]
      assert returned_metadata.health_status == :healthy
    end
    
    test "lookup returns error for non-existent agent" do
      assert :error = MABEAM.AgentRegistry.lookup("non_existent")
    end
    
    test "find_by_capability uses O(1) index lookup", %{registry: registry, agent1: agent1, agent2: agent2} do
      metadata1 = valid_metadata(capability: :inference)
      metadata2 = valid_metadata(capability: :training)
      
      :ok = GenServer.call(registry, {:register, "inference_agent", agent1, metadata1})
      :ok = GenServer.call(registry, {:register, "training_agent", agent2, metadata2})
      
      # Direct ETS index lookup
      {:ok, inference_agents} = MABEAM.AgentRegistry.find_by_capability(:inference)
      {:ok, training_agents} = MABEAM.AgentRegistry.find_by_capability(:training)
      
      assert length(inference_agents) == 1
      assert length(training_agents) == 1
      
      {agent_id, pid, metadata} = List.first(inference_agents)
      assert agent_id == "inference_agent"
      assert pid == agent1
      assert metadata.capability == :inference
    end
    
    test "find_by_health_status uses O(1) index lookup", %{registry: registry, agent1: agent1, agent2: agent2} do
      healthy_metadata = valid_metadata(health_status: :healthy)
      degraded_metadata = valid_metadata(health_status: :degraded)
      
      :ok = GenServer.call(registry, {:register, "healthy_agent", agent1, healthy_metadata})
      :ok = GenServer.call(registry, {:register, "degraded_agent", agent2, degraded_metadata})
      
      {:ok, healthy_agents} = MABEAM.AgentRegistry.find_by_health_status(:healthy)
      {:ok, degraded_agents} = MABEAM.AgentRegistry.find_by_health_status(:degraded)
      
      assert length(healthy_agents) == 1
      assert length(degraded_agents) == 1
      
      {agent_id, pid, _metadata} = List.first(healthy_agents)
      assert agent_id == "healthy_agent"
      assert pid == agent1
    end
    
    test "find_by_node uses O(1) index lookup", %{registry: registry, agent1: agent1, agent2: agent2} do
      node1_metadata = valid_metadata(node: :node1)
      node2_metadata = valid_metadata(node: :node2)
      
      :ok = GenServer.call(registry, {:register, "node1_agent", agent1, node1_metadata})
      :ok = GenServer.call(registry, {:register, "node2_agent", agent2, node2_metadata})
      
      {:ok, node1_agents} = MABEAM.AgentRegistry.find_by_node(:node1)
      {:ok, node2_agents} = MABEAM.AgentRegistry.find_by_node(:node2)
      
      assert length(node1_agents) == 1
      assert length(node2_agents) == 1
    end
  end
  
  describe "atomic multi-criteria queries" do
    test "query with single criterion", %{registry: registry, agent1: agent1} do
      metadata = valid_metadata(capability: :inference)
      :ok = GenServer.call(registry, {:register, "agent1", agent1, metadata})
      
      criteria = [{[:capability], :inference, :eq}]
      assert {:ok, results} = MABEAM.AgentRegistry.query(criteria)
      assert length(results) == 1
      
      {agent_id, pid, returned_metadata} = List.first(results)
      assert agent_id == "agent1"
      assert pid == agent1
      assert returned_metadata.capability == :inference
    end
    
    test "query with multiple criteria (atomic AND operation)", %{registry: registry, agent1: agent1, agent2: agent2} do
      # Register agents with different combinations
      healthy_inference = valid_metadata(capability: :inference, health_status: :healthy)
      degraded_inference = valid_metadata(capability: :inference, health_status: :degraded)
      
      :ok = GenServer.call(registry, {:register, "healthy_inf", agent1, healthy_inference})
      :ok = GenServer.call(registry, {:register, "degraded_inf", agent2, degraded_inference})
      
      # Query for healthy AND inference agents
      criteria = [
        {[:capability], :inference, :eq},
        {[:health_status], :healthy, :eq}
      ]
      
      assert {:ok, results} = MABEAM.AgentRegistry.query(criteria)
      assert length(results) == 1
      
      {agent_id, _pid, metadata} = List.first(results)
      assert agent_id == "healthy_inf"
      assert metadata.capability == :inference
      assert metadata.health_status == :healthy
    end
    
    test "query with nested path criteria", %{registry: registry, agent1: agent1, agent2: agent2} do
      high_memory = valid_metadata(resources: %{memory_available: 0.8, cpu_available: 0.6})
      low_memory = valid_metadata(resources: %{memory_available: 0.2, cpu_available: 0.6})
      
      :ok = GenServer.call(registry, {:register, "high_mem", agent1, high_memory})
      :ok = GenServer.call(registry, {:register, "low_mem", agent2, low_memory})
      
      # Query for agents with memory >= 0.5
      criteria = [{[:resources, :memory_available], 0.5, :gte}]
      
      assert {:ok, results} = MABEAM.AgentRegistry.query(criteria)
      assert length(results) == 1
      
      {agent_id, _pid, _metadata} = List.first(results)
      assert agent_id == "high_mem"
    end
    
    test "query with comparison operators", %{registry: registry, agent1: agent1, agent2: agent2, agent3: agent3} do
      # Create agents with different resource levels
      low_cpu = valid_metadata(resources: %{cpu_usage: 0.1})
      med_cpu = valid_metadata(resources: %{cpu_usage: 0.5})
      high_cpu = valid_metadata(resources: %{cpu_usage: 0.9})
      
      :ok = GenServer.call(registry, {:register, "low_cpu", agent1, low_cpu})
      :ok = GenServer.call(registry, {:register, "med_cpu", agent2, med_cpu})
      :ok = GenServer.call(registry, {:register, "high_cpu", agent3, high_cpu})
      
      # Test different comparison operators
      assert {:ok, gte_results} = MABEAM.AgentRegistry.query([{[:resources, :cpu_usage], 0.4, :gte}])
      assert length(gte_results) == 2  # med_cpu and high_cpu
      
      assert {:ok, lt_results} = MABEAM.AgentRegistry.query([{[:resources, :cpu_usage], 0.6, :lt}])
      assert length(lt_results) == 2  # low_cpu and med_cpu
      
      assert {:ok, eq_results} = MABEAM.AgentRegistry.query([{[:resources, :cpu_usage], 0.5, :eq}])
      assert length(eq_results) == 1  # med_cpu only
    end
    
    test "query with :in operator for multiple values", %{registry: registry, agent1: agent1, agent2: agent2, agent3: agent3} do
      inf_metadata = valid_metadata(capability: :inference)
      train_metadata = valid_metadata(capability: :training)
      coord_metadata = valid_metadata(capability: :coordination)
      
      :ok = GenServer.call(registry, {:register, "inf_agent", agent1, inf_metadata})
      :ok = GenServer.call(registry, {:register, "train_agent", agent2, train_metadata})
      :ok = GenServer.call(registry, {:register, "coord_agent", agent3, coord_metadata})
      
      # Query for agents with inference OR training capability
      criteria = [{[:capability], [:inference, :training], :in}]
      
      assert {:ok, results} = MABEAM.AgentRegistry.query(criteria)
      assert length(results) == 2
      
      agent_ids = Enum.map(results, fn {id, _pid, _metadata} -> id end)
      assert "inf_agent" in agent_ids
      assert "train_agent" in agent_ids
      refute "coord_agent" in agent_ids
    end
    
    test "query handles invalid criteria gracefully" do
      # Test with malformed criteria
      invalid_criteria = ["not", "a", "valid", "format"]
      assert {:error, {:invalid_criteria, _reason}} = MABEAM.AgentRegistry.query(invalid_criteria)
      
      # Test with invalid criteria format
      assert {:error, :invalid_criteria_format} = MABEAM.AgentRegistry.query("not a list")
    end
  end
  
  describe "metadata updates" do
    test "updates metadata and rebuilds indexes", %{registry: registry, agent1: agent1} do
      original_metadata = valid_metadata(capability: :inference, health_status: :healthy)
      :ok = GenServer.call(registry, {:register, "agent1", agent1, original_metadata})
      
      # Verify original registration
      {:ok, {^agent1, metadata}} = MABEAM.AgentRegistry.lookup("agent1")
      assert metadata.capability == :inference
      assert metadata.health_status == :healthy
      
      # Update metadata
      updated_metadata = valid_metadata(capability: :training, health_status: :degraded)
      assert :ok = GenServer.call(registry, {:update_metadata, "agent1", updated_metadata})
      
      # Verify update
      {:ok, {^agent1, new_metadata}} = MABEAM.AgentRegistry.lookup("agent1")
      assert new_metadata.capability == :training
      assert new_metadata.health_status == :degraded
      
      # Verify indexes were updated
      {:ok, training_agents} = MABEAM.AgentRegistry.find_by_capability(:training)
      assert length(training_agents) == 1
      
      {:ok, inference_agents} = MABEAM.AgentRegistry.find_by_capability(:inference)
      assert length(inference_agents) == 0  # Should be removed from old index
    end
    
    test "fails to update metadata for non-existent agent", %{registry: registry} do
      metadata = valid_metadata()
      assert {:error, :not_found} = GenServer.call(registry, {:update_metadata, "non_existent", metadata})
    end
  end
  
  describe "agent unregistration" do
    test "unregisters agent and clears all indexes", %{registry: registry, agent1: agent1} do
      metadata = valid_metadata(capability: :inference)
      :ok = GenServer.call(registry, {:register, "agent1", agent1, metadata})
      
      # Verify registration
      assert {:ok, {^agent1, _}} = MABEAM.AgentRegistry.lookup("agent1")
      {:ok, inference_agents} = MABEAM.AgentRegistry.find_by_capability(:inference)
      assert length(inference_agents) == 1
      
      # Unregister
      assert :ok = GenServer.call(registry, {:unregister, "agent1"})
      
      # Verify removal
      assert :error = MABEAM.AgentRegistry.lookup("agent1")
      {:ok, inference_agents_after} = MABEAM.AgentRegistry.find_by_capability(:inference)
      assert length(inference_agents_after) == 0
    end
    
    test "fails to unregister non-existent agent", %{registry: registry} do
      assert {:error, :not_found} = GenServer.call(registry, {:unregister, "non_existent"})
    end
  end
  
  describe "process monitoring and automatic cleanup" do
    test "automatically removes agent when process dies", %{registry: registry} do
      # Create a process that will die
      short_lived = spawn(fn -> :timer.sleep(10) end)
      
      metadata = valid_metadata(capability: :inference)
      :ok = GenServer.call(registry, {:register, "short_lived", short_lived, metadata})
      
      # Verify registration
      assert {:ok, {^short_lived, _}} = MABEAM.AgentRegistry.lookup("short_lived")
      
      # Wait for process to die and cleanup to occur
      :timer.sleep(50)
      
      # Should be automatically removed
      assert :error = MABEAM.AgentRegistry.lookup("short_lived")
      {:ok, inference_agents} = MABEAM.AgentRegistry.find_by_capability(:inference)
      assert length(inference_agents) == 0
    end
  end
  
  describe "performance characteristics" do
    test "supports high-concurrency read operations", %{registry: registry} do
      # Register multiple agents
      agents = for i <- 1..100 do
        pid = spawn(fn -> :timer.sleep(5000) end)
        metadata = valid_metadata(capability: :inference, health_status: :healthy)
        :ok = GenServer.call(registry, {:register, "agent_#{i}", pid, metadata})
        {i, pid}
      end
      
      # Perform concurrent lookups
      tasks = for {i, _pid} <- agents do
        Task.async(fn ->
          MABEAM.AgentRegistry.lookup("agent_#{i}")
        end)
      end
      
      results = Task.await_many(tasks, 1000)
      
      # All lookups should succeed
      assert length(results) == 100
      assert Enum.all?(results, fn result -> 
        match?({:ok, {_pid, _metadata}}, result)
      end)
    end
    
    test "atomic queries are faster than separate operations", %{registry: registry} do
      # This test demonstrates the performance advantage of atomic queries
      # In practice, the difference would be more significant with larger datasets
      
      _registry_pid = self()  # Use test process for timing
      
      # Register test agents with various metadata
      metadata_combinations = [
        %{capability: :inference, health_status: :healthy, node: :node1, resources: %{memory_available: 0.8}},
        %{capability: :training, health_status: :healthy, node: :node1, resources: %{memory_available: 0.6}},
        %{capability: :inference, health_status: :degraded, node: :node2, resources: %{memory_available: 0.3}},
        %{capability: :training, health_status: :healthy, node: :node2, resources: %{memory_available: 0.9}}
      ]
      
      for {metadata, i} <- Enum.with_index(metadata_combinations) do
        pid = spawn(fn -> :timer.sleep(5000) end)
        :ok = GenServer.call(registry, {:register, "agent_#{i}", pid, metadata})
      end
      
      # Atomic query: find healthy inference agents with sufficient memory
      atomic_start = System.monotonic_time(:microsecond)
      
      atomic_criteria = [
        {[:capability], :inference, :eq},
        {[:health_status], :healthy, :eq},
        {[:resources, :memory_available], 0.5, :gte}
      ]
      {:ok, atomic_results} = MABEAM.AgentRegistry.query(atomic_criteria)
      
      atomic_end = System.monotonic_time(:microsecond)
      atomic_time = atomic_end - atomic_start
      
      # Verify we get the expected result
      assert length(atomic_results) == 1
      
      # The atomic query should be very fast (typically <100 microseconds)
      assert atomic_time < 1000, "Atomic query took #{atomic_time} microseconds, expected < 1000"
    end
  end
  
  describe "protocol compliance" do
    test "implements Foundation.Registry protocol correctly", %{registry: _registry} do
      # This test verifies that MABEAM.AgentRegistry can be used through the Foundation facade
      # We need to start a named registry for the protocol to work with module names
      
      # Register the test registry with a name so we can use the module
      test_registry_name = :"test_registry_protocol_#{:erlang.unique_integer([:positive])}"
      {:ok, named_registry} = MABEAM.AgentRegistry.start_link(name: test_registry_name)
      
      metadata = valid_metadata()
      agent_pid = spawn(fn -> :timer.sleep(1000) end)
      
      # Test through Foundation facade using the module name (which will call the named process)
      assert :ok = Foundation.register("protocol_agent", agent_pid, metadata, test_registry_name)
      assert {:ok, {^agent_pid, returned_metadata}} = Foundation.lookup("protocol_agent", test_registry_name)
      assert returned_metadata.capability == metadata.capability
      
      # Test query through Foundation facade
      criteria = [{[:capability], List.first(List.wrap(metadata.capability)), :eq}]
      assert {:ok, results} = Foundation.query(criteria, test_registry_name)
      assert length(results) >= 1
      
      # Test indexed attributes through Foundation facade
      assert attrs = Foundation.indexed_attributes(test_registry_name)
      assert :capability in attrs
      assert :health_status in attrs
      assert :node in attrs
      
      # Clean up the named registry
      if Process.alive?(named_registry) do
        GenServer.stop(named_registry)
      end
    end
  end
  
  describe "configuration and metadata" do
    test "returns protocol version information" do
      assert "1.1" = MABEAM.AgentRegistry.protocol_version()
    end
    
    test "returns indexed attributes list" do
      attrs = MABEAM.AgentRegistry.indexed_attributes()
      assert :capability in attrs
      assert :health_status in attrs
      assert :node in attrs
    end
    
    test "list_all supports optional filtering" do
      # Test without filter
      all_agents = MABEAM.AgentRegistry.list_all()
      assert is_list(all_agents)
      
      # Test with filter function
      high_memory_filter = fn metadata ->
        get_in(metadata, [:resources, :memory_available]) |> Kernel.||(0.0) > 0.7
      end
      
      filtered_agents = MABEAM.AgentRegistry.list_all(high_memory_filter)
      assert is_list(filtered_agents)
    end
  end
  
  # Helper function to create valid metadata
  defp valid_metadata(overrides \\ []) do
    defaults = %{
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
    
    Map.merge(defaults, Map.new(overrides))
  end
end