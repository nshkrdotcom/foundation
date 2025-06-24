defmodule Foundation.ProcessRegistryPerformanceTest do
  @moduledoc """
  Performance tests for Foundation.ProcessRegistry optimizations.

  Tests the enhanced performance features for large agent systems including:
  - Indexed metadata searches
  - Bulk operations
  - Cache layer optimizations
  - Large scale agent registration and lookup
  """
  use ExUnit.Case, async: false

  alias Foundation.ProcessRegistry

  setup do
    # Create unique test namespace for this test run
    test_namespace = {:test, make_ref()}

    # Clean up any existing test data
    cleanup_test_services(test_namespace)

    on_exit(fn ->
      cleanup_test_services(test_namespace)
    end)

    {:ok, test_namespace: test_namespace}
  end

  describe "large scale agent registration" do
    test "handles registration of 1000 agents efficiently", %{test_namespace: test_namespace} do
      agent_count = 1000

      # Measure time to register many agents
      {time_ms, results} =
        :timer.tc(fn ->
          for i <- 1..agent_count do
            service_name = {:agent, :"test_agent_#{i}"}
            pid = spawn(fn -> Process.sleep(:infinity) end)

            metadata = %{
              type: :mabeam_agent,
              agent_type: :worker,
              index: i,
              capabilities: if(rem(i, 2) == 0, do: [:computation], else: [:communication])
            }

            result = ProcessRegistry.register(test_namespace, service_name, pid, metadata)
            {service_name, result}
          end
        end)

      # Convert to milliseconds
      time_ms = time_ms / 1000

      # All registrations should succeed
      assert Enum.all?(results, fn {_, result} -> result == :ok end)

      # Should complete within reasonable time (< 500ms for 1000 agents)
      assert time_ms < 500, "Registration took #{time_ms}ms for #{agent_count} agents"

      # Verify all agents are registered
      service_count = ProcessRegistry.count_services(test_namespace)
      assert service_count == agent_count
    end

    test "performs fast metadata-based searches on large agent sets", %{
      test_namespace: test_namespace
    } do
      agent_count = 500

      # Register agents with different metadata
      for i <- 1..agent_count do
        service_name = {:agent, :"search_agent_#{i}"}
        pid = spawn(fn -> Process.sleep(:infinity) end)

        # Create varied metadata for realistic testing
        metadata = %{
          type: :mabeam_agent,
          agent_type: if(rem(i, 3) == 0, do: :coordinator, else: :worker),
          priority: if(rem(i, 5) == 0, do: :high, else: :normal),
          capabilities:
            case rem(i, 4) do
              0 -> [:computation, :ml]
              1 -> [:communication, :coordination]
              2 -> [:storage, :persistence]
              3 -> [:monitoring, :telemetry]
            end,
          index: i
        }

        ProcessRegistry.register(test_namespace, service_name, pid, metadata)
      end

      # Test different search patterns and measure performance
      search_tests = [
        {fn meta -> meta[:agent_type] == :coordinator end, "coordinator agents"},
        {fn meta -> meta[:priority] == :high end, "high priority agents"},
        {fn meta -> :ml in (meta[:capabilities] || []) end, "ML capable agents"},
        {fn meta -> meta[:index] != nil and meta[:index] > 400 end, "high index agents"}
      ]

      for {search_fn, description} <- search_tests do
        {time_ms, results} =
          :timer.tc(fn ->
            ProcessRegistry.find_services_by_metadata(test_namespace, search_fn)
          end)

        time_ms = time_ms / 1000

        # Search should complete quickly (< 50ms)
        assert time_ms < 50, "#{description} search took #{time_ms}ms"

        # Verify results are reasonable
        assert is_list(results)
        assert length(results) > 0, "#{description} search returned no results"

        # Verify all results match the search criteria
        for {_service, _pid, metadata} <- results do
          assert search_fn.(metadata), "Result doesn't match search criteria for #{description}"
        end
      end
    end

    test "handles concurrent agent operations efficiently", %{test_namespace: test_namespace} do
      # Test concurrent registrations and lookups
      task_count = 50
      agents_per_task = 20

      # Create concurrent registration tasks
      registration_tasks =
        for task_id <- 1..task_count do
          Task.async(fn ->
            for agent_id <- 1..agents_per_task do
              service_name = {:agent, :"concurrent_agent_#{task_id}_#{agent_id}"}
              pid = spawn(fn -> Process.sleep(:infinity) end)

              metadata = %{
                type: :mabeam_agent,
                task_id: task_id,
                agent_id: agent_id,
                capabilities: [:concurrent_test]
              }

              ProcessRegistry.register(test_namespace, service_name, pid, metadata)
            end
          end)
        end

      # Wait for all registrations to complete
      {reg_time_ms, _} =
        :timer.tc(fn ->
          Task.await_many(registration_tasks, 10_000)
        end)

      reg_time_ms = reg_time_ms / 1000

      # Registrations should complete quickly
      total_agents = task_count * agents_per_task

      assert reg_time_ms < 1000,
             "Concurrent registration of #{total_agents} agents took #{reg_time_ms}ms"

      # Verify all agents were registered
      final_count = ProcessRegistry.count_services(test_namespace)
      assert final_count == total_agents

      # Test concurrent lookups
      lookup_tasks =
        for task_id <- 1..task_count do
          Task.async(fn ->
            for agent_id <- 1..agents_per_task do
              service_name = {:agent, :"concurrent_agent_#{task_id}_#{agent_id}"}

              case ProcessRegistry.lookup(test_namespace, service_name) do
                {:ok, pid} when is_pid(pid) -> :ok
                _ -> :error
              end
            end
          end)
        end

      # Measure lookup performance
      {lookup_time_ms, lookup_results} =
        :timer.tc(fn ->
          Task.await_many(lookup_tasks, 10_000)
        end)

      lookup_time_ms = lookup_time_ms / 1000

      # All lookups should succeed
      assert Enum.all?(lookup_results, fn results ->
               Enum.all?(results, fn result -> result == :ok end)
             end)

      # Lookups should be fast
      assert lookup_time_ms < 500,
             "Concurrent lookup of #{total_agents} agents took #{lookup_time_ms}ms"
    end
  end

  describe "bulk operations" do
    test "supports efficient bulk agent registration", %{test_namespace: test_namespace} do
      # Test registering many agents at once
      agent_specs =
        for i <- 1..200 do
          {
            {:agent, :"bulk_agent_#{i}"},
            spawn(fn -> Process.sleep(:infinity) end),
            %{
              type: :mabeam_agent,
              agent_type: :worker,
              bulk_index: i,
              capabilities: [:bulk_test]
            }
          }
        end

      {time_ms, results} =
        :timer.tc(fn ->
          # Use existing register function in loop for now
          # In the future, this could be optimized with a bulk_register function
          for {service_name, pid, metadata} <- agent_specs do
            ProcessRegistry.register(test_namespace, service_name, pid, metadata)
          end
        end)

      time_ms = time_ms / 1000

      # All should succeed
      assert Enum.all?(results, fn result -> result == :ok end)

      # Should be reasonably fast
      assert time_ms < 200, "Bulk registration took #{time_ms}ms"

      # Verify count
      count = ProcessRegistry.count_services(test_namespace)
      assert count == 200
    end

    test "efficiently filters large result sets", %{test_namespace: test_namespace} do
      # Register many agents with varied metadata
      for i <- 1..300 do
        service_name = {:agent, :"filter_agent_#{i}"}
        pid = spawn(fn -> Process.sleep(:infinity) end)

        metadata = %{
          type: :mabeam_agent,
          category:
            case rem(i, 5) do
              0 -> :ml_processing
              1 -> :data_storage
              2 -> :communication
              3 -> :monitoring
              4 -> :coordination
            end,
          tier: if(rem(i, 10) == 0, do: :premium, else: :standard),
          region: if(i <= 100, do: :us_east, else: if(i <= 200, do: :us_west, else: :eu))
        }

        ProcessRegistry.register(test_namespace, service_name, pid, metadata)
      end

      # Test complex filtering operations
      filter_tests = [
        {fn m -> m[:category] == :ml_processing end, "ML processing agents"},
        {fn m -> m[:tier] == :premium end, "Premium tier agents"},
        {fn m -> m[:region] == :us_east end, "US East region agents"},
        {fn m -> m[:category] == :coordination and m[:tier] == :premium end,
         "Premium coordination agents"}
      ]

      for {filter_fn, description} <- filter_tests do
        {time_ms, results} =
          :timer.tc(fn ->
            ProcessRegistry.find_services_by_metadata(test_namespace, filter_fn)
          end)

        time_ms = time_ms / 1000

        # Should be fast
        assert time_ms < 30, "#{description} filter took #{time_ms}ms"

        # Should return results
        assert is_list(results)

        # All results should match filter
        for {_service, _pid, metadata} <- results do
          assert filter_fn.(metadata), "Filter result doesn't match criteria for #{description}"
        end
      end
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
