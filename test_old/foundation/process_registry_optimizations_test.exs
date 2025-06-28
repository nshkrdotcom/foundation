defmodule Foundation.ProcessRegistry.OptimizationsTest do
  @moduledoc """
  Tests for ProcessRegistry optimization features.
  """
  use ExUnit.Case, async: false

  alias Foundation.ProcessRegistry
  alias Foundation.ProcessRegistry.Optimizations

  setup do
    # Create unique test namespace for this test run
    test_namespace = {:test, make_ref()}

    # Initialize optimizations
    Optimizations.initialize_optimizations()

    # Clean up any existing test data
    cleanup_test_services(test_namespace)

    on_exit(fn ->
      cleanup_test_services(test_namespace)
      Optimizations.cleanup_optimizations()
    end)

    {:ok, test_namespace: test_namespace}
  end

  describe "metadata indexing" do
    test "indexes metadata fields for fast lookup", %{test_namespace: test_namespace} do
      # Register services with indexed metadata
      service_configs = [
        {:worker1, %{type: :mabeam_agent, agent_type: :worker, capabilities: [:ml, :computation]}},
        {:worker2, %{type: :mabeam_agent, agent_type: :worker, capabilities: [:communication]}},
        {:coordinator1,
         %{type: :mabeam_agent, agent_type: :coordinator, capabilities: [:coordination]}}
      ]

      for {service_name, metadata} <- service_configs do
        pid = spawn(fn -> Process.sleep(:infinity) end)

        assert :ok =
                 Optimizations.register_with_indexing(test_namespace, service_name, pid, metadata)
      end

      # Test indexed searches

      # Search by agent_type
      workers = Optimizations.find_by_indexed_metadata(test_namespace, :agent_type, :worker)
      assert length(workers) == 2

      assert Enum.all?(workers, fn {_service, _pid, metadata} ->
               metadata[:agent_type] == :worker
             end)

      # Search by capability (list field)
      ml_agents = Optimizations.find_by_indexed_metadata(test_namespace, :capabilities, :ml)
      assert length(ml_agents) == 1
      assert hd(ml_agents) |> elem(0) == :worker1

      coordination_agents =
        Optimizations.find_by_indexed_metadata(test_namespace, :capabilities, :coordination)

      assert length(coordination_agents) == 1
      assert hd(coordination_agents) |> elem(0) == :coordinator1

      # Search by type
      mabeam_agents = Optimizations.find_by_indexed_metadata(test_namespace, :type, :mabeam_agent)
      assert length(mabeam_agents) == 3
    end

    test "handles services with missing metadata fields", %{test_namespace: test_namespace} do
      # Register service with minimal metadata
      pid = spawn(fn -> Process.sleep(:infinity) end)
      minimal_metadata = %{name: "test_service"}

      assert :ok =
               Optimizations.register_with_indexing(
                 test_namespace,
                 :minimal_service,
                 pid,
                 minimal_metadata
               )

      # Searches for non-existent fields should return empty results
      assert [] = Optimizations.find_by_indexed_metadata(test_namespace, :type, :mabeam_agent)
      assert [] = Optimizations.find_by_indexed_metadata(test_namespace, :capabilities, :ml)
    end

    test "automatically removes dead processes from index", %{test_namespace: test_namespace} do
      # Register a service
      pid = spawn(fn -> Process.sleep(:infinity) end)
      metadata = %{type: :mabeam_agent, agent_type: :worker}

      assert :ok =
               Optimizations.register_with_indexing(test_namespace, :test_service, pid, metadata)

      # Verify it appears in index
      workers = Optimizations.find_by_indexed_metadata(test_namespace, :agent_type, :worker)
      assert length(workers) == 1

      # Kill the process
      Process.exit(pid, :kill)
      # Allow process to die
      Process.sleep(10)

      # Should no longer appear in index results
      workers_after = Optimizations.find_by_indexed_metadata(test_namespace, :agent_type, :worker)
      assert length(workers_after) == 0
    end
  end

  describe "cached lookups" do
    test "caches lookup results for performance", %{test_namespace: test_namespace} do
      # Register a service
      pid = spawn(fn -> Process.sleep(:infinity) end)
      assert :ok = ProcessRegistry.register(test_namespace, :cached_service, pid)

      # First lookup should populate cache
      assert {:ok, ^pid} = Optimizations.cached_lookup(test_namespace, :cached_service)

      # Second lookup should use cache (we can't directly test this, but the function should work)
      assert {:ok, ^pid} = Optimizations.cached_lookup(test_namespace, :cached_service)

      # Verify service is still accessible
      assert Process.alive?(pid)
    end

    test "invalidates cache when process dies", %{test_namespace: test_namespace} do
      # Register a service
      pid = spawn(fn -> Process.sleep(:infinity) end)
      assert :ok = ProcessRegistry.register(test_namespace, :dying_service, pid)

      # Lookup to populate cache
      assert {:ok, ^pid} = Optimizations.cached_lookup(test_namespace, :dying_service)

      # Kill the process
      Process.exit(pid, :kill)
      # Allow process to die
      Process.sleep(10)

      # Next lookup should detect dead process and return error
      assert :error = Optimizations.cached_lookup(test_namespace, :dying_service)
    end

    test "handles services not in registry", %{test_namespace: test_namespace} do
      # Lookup non-existent service
      assert :error = Optimizations.cached_lookup(test_namespace, :nonexistent_service)
    end
  end

  describe "bulk operations" do
    test "efficiently registers multiple services", %{test_namespace: test_namespace} do
      # Prepare bulk registrations
      registrations =
        for i <- 1..50 do
          service_name = :"bulk_service_#{i}"
          pid = spawn(fn -> Process.sleep(:infinity) end)

          metadata = %{
            type: :mabeam_agent,
            agent_type: :worker,
            index: i,
            capabilities: [:bulk_test]
          }

          {test_namespace, service_name, pid, metadata}
        end

      # Perform bulk registration
      {time_ms, results} =
        :timer.tc(fn ->
          Optimizations.bulk_register(registrations)
        end)

      time_ms = time_ms / 1000

      # All should succeed
      assert length(results) == 50
      assert Enum.all?(results, fn {result, _service} -> result == :ok end)

      # Should be reasonably fast
      assert time_ms < 100, "Bulk registration took #{time_ms}ms"

      # Verify all services are registered and indexed
      workers = Optimizations.find_by_indexed_metadata(test_namespace, :agent_type, :worker)
      assert length(workers) == 50

      bulk_test_agents =
        Optimizations.find_by_indexed_metadata(test_namespace, :capabilities, :bulk_test)

      assert length(bulk_test_agents) == 50
    end

    test "handles mixed success/failure in bulk operations", %{test_namespace: test_namespace} do
      # Register one service first to create a conflict
      existing_pid = spawn(fn -> Process.sleep(:infinity) end)
      assert :ok = ProcessRegistry.register(test_namespace, :conflicting_service, existing_pid)

      # Prepare registrations including one that will conflict
      registrations = [
        {test_namespace, :new_service_1, spawn(fn -> Process.sleep(:infinity) end), %{type: :new}},
        {test_namespace, :conflicting_service, spawn(fn -> Process.sleep(:infinity) end),
         %{type: :conflict}},
        {test_namespace, :new_service_2, spawn(fn -> Process.sleep(:infinity) end), %{type: :new}}
      ]

      # Perform bulk registration
      results = Optimizations.bulk_register(registrations)

      # Check results
      assert length(results) == 3

      # First and third should succeed, second should fail
      [{result1, :new_service_1}, {result2, :conflicting_service}, {result3, :new_service_2}] =
        results

      assert result1 == :ok
      assert match?({:error, _}, result2)
      assert result3 == :ok

      # Verify successful registrations are indexed
      new_services = Optimizations.find_by_indexed_metadata(test_namespace, :type, :new)
      assert length(new_services) == 2
    end
  end

  describe "performance statistics" do
    test "provides optimization statistics", %{test_namespace: test_namespace} do
      # Register some services to populate indices
      for i <- 1..10 do
        pid = spawn(fn -> Process.sleep(:infinity) end)
        metadata = %{type: :mabeam_agent, index: i}
        Optimizations.register_with_indexing(test_namespace, :"service_#{i}", pid, metadata)
      end

      # Do some cached lookups to populate cache
      Optimizations.cached_lookup(test_namespace, :service_1)
      Optimizations.cached_lookup(test_namespace, :service_2)

      # Get statistics
      stats = Optimizations.get_optimization_stats()

      assert is_integer(stats.metadata_index_size)
      assert stats.metadata_index_size > 0

      assert is_integer(stats.cache_size)
      assert stats.cache_size >= 0

      # Cache hit rate is not implemented yet, should be nil
      assert is_nil(stats.cache_hit_rate)
    end
  end

  describe "integration with existing ProcessRegistry" do
    test "optimizations work alongside regular ProcessRegistry operations", %{
      test_namespace: test_namespace
    } do
      # Register services using both methods
      pid1 = spawn(fn -> Process.sleep(:infinity) end)
      pid2 = spawn(fn -> Process.sleep(:infinity) end)

      # Regular registration
      assert :ok =
               ProcessRegistry.register(test_namespace, :regular_service, pid1, %{type: :regular})

      # Optimized registration
      assert :ok =
               Optimizations.register_with_indexing(test_namespace, :optimized_service, pid2, %{
                 type: :optimized
               })

      # Both should be discoverable via regular lookup
      assert {:ok, ^pid1} = ProcessRegistry.lookup(test_namespace, :regular_service)
      assert {:ok, ^pid2} = ProcessRegistry.lookup(test_namespace, :optimized_service)

      # Both should be discoverable via cached lookup
      assert {:ok, ^pid1} = Optimizations.cached_lookup(test_namespace, :regular_service)
      assert {:ok, ^pid2} = Optimizations.cached_lookup(test_namespace, :optimized_service)

      # Optimized service should appear in metadata index
      optimized_services = Optimizations.find_by_indexed_metadata(test_namespace, :type, :optimized)
      assert length(optimized_services) == 1

      # Regular service won't appear in metadata index (not indexed)
      regular_services = Optimizations.find_by_indexed_metadata(test_namespace, :type, :regular)
      assert length(regular_services) == 0
    end
  end

  defp cleanup_test_services(test_namespace) do
    try do
      # Get all test services and unregister them
      all_services = ProcessRegistry.get_all_services(test_namespace)

      for {service_name, _pid} <- all_services do
        ProcessRegistry.unregister(test_namespace, service_name)
      end

      # Kill any remaining test processes
      Process.sleep(10)
    rescue
      _ -> :ok
    end
  end
end
