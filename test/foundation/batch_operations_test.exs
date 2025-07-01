defmodule Foundation.BatchOperationsTest do
  use Foundation.UnifiedTestFoundation, :registry

  alias Foundation.BatchOperations

  describe "batch_register/2" do
    test "registers multiple agents successfully", %{registry: registry} do
      {agents, pids} =
        for i <- 1..10 do
          pid = spawn(fn -> :timer.sleep(:infinity) end)
          {{"batch_agent_#{i}", pid, test_metadata()}, pid}
        end
        |> Enum.unzip()

      on_exit(fn ->
        Enum.each(pids, fn pid ->
          if Process.alive?(pid), do: Process.exit(pid, :kill)
        end)
      end)

      assert {:ok, registered_ids} = BatchOperations.batch_register(agents, registry: registry)
      assert length(registered_ids) == 10

      # Verify all agents are registered
      Enum.each(registered_ids, fn id ->
        assert {:ok, _} = Foundation.Registry.lookup(registry, id)
      end)
    end

    test "handles batch with errors when on_error is :continue", %{registry: registry} do
      pid1 = spawn(fn -> :timer.sleep(:infinity) end)
      # Spawn and monitor a process that will die immediately
      ref = Process.monitor(dead_pid = spawn(fn -> :ok end))
      # Wait for process to die
      assert_receive {:DOWN, ^ref, :process, ^dead_pid, :normal}, 1000

      on_exit(fn ->
        if Process.alive?(pid1), do: Process.exit(pid1, :kill)
      end)

      agents = [
        {"valid_agent", pid1, test_metadata()},
        # Will fail
        {"invalid_agent", dead_pid, test_metadata()},
        {"another_valid", pid1, test_metadata()}
      ]

      assert {:partial, registered_ids} =
               BatchOperations.batch_register(agents, on_error: :continue, registry: registry)

      assert "valid_agent" in registered_ids
      refute "invalid_agent" in registered_ids
    end

    test "stops on first error when on_error is :stop", %{registry: registry} do
      # Spawn and monitor a process that will die immediately
      ref = Process.monitor(dead_pid = spawn(fn -> :ok end))
      # Wait for process to die
      assert_receive {:DOWN, ^ref, :process, ^dead_pid, :normal}, 1000

      pid2 = spawn(fn -> :timer.sleep(:infinity) end)

      on_exit(fn ->
        if Process.alive?(pid2), do: Process.exit(pid2, :kill)
      end)

      agents = [
        {"will_fail", dead_pid, test_metadata()},
        {"wont_process", pid2, test_metadata()}
      ]

      result = BatchOperations.batch_register(agents, on_error: :stop, registry: registry)
      assert match?({:error, _}, result) or match?({:error, _, _}, result)
      assert :error = Foundation.Registry.lookup(registry, "wont_process")
    end

    test "respects batch_size option", %{registry: registry} do
      # This test mainly verifies the batching doesn't break functionality
      {agents, pids} =
        for i <- 1..25 do
          pid = spawn(fn -> :timer.sleep(:infinity) end)
          {{"batch_size_#{i}", pid, test_metadata()}, pid}
        end
        |> Enum.unzip()

      on_exit(fn ->
        Enum.each(pids, fn pid ->
          if Process.alive?(pid), do: Process.exit(pid, :kill)
        end)
      end)

      assert {:ok, registered_ids} =
               BatchOperations.batch_register(agents, batch_size: 5, registry: registry)

      assert length(registered_ids) == 25
    end
  end

  describe "batch_update_metadata/2" do
    setup %{registry: registry} do
      # Pre-register some agents
      pids =
        for i <- 1..5 do
          pid = spawn(fn -> :timer.sleep(:infinity) end)
          :ok = GenServer.call(registry, {:register, "update_test_#{i}", pid, test_metadata()})
          {i, pid}
        end

      on_exit(fn ->
        Enum.each(pids, fn {_i, pid} ->
          if Process.alive?(pid), do: Process.exit(pid, :kill)
        end)
      end)

      {:ok, pids: pids}
    end

    test "updates metadata for multiple agents", %{registry: registry} do
      updates =
        for i <- 1..5 do
          {"update_test_#{i}", test_metadata(:degraded)}
        end

      assert {:ok, updated_ids} = BatchOperations.batch_update_metadata(updates, registry: registry)
      assert length(updated_ids) == 5

      # Verify updates
      Enum.each(updated_ids, fn id ->
        assert {:ok, {_pid, metadata}} = Foundation.Registry.lookup(registry, id)
        assert metadata.health_status == :degraded
      end)
    end

    test "parallel updates", %{registry: registry} do
      updates =
        for i <- 1..5 do
          {"update_test_#{i}", test_metadata(:unhealthy)}
        end

      assert {:ok, _} =
               BatchOperations.batch_update_metadata(updates, parallel: true, registry: registry)

      # Verify all were updated
      for i <- 1..5 do
        assert {:ok, {_pid, metadata}} = Foundation.Registry.lookup(registry, "update_test_#{i}")
        assert metadata.health_status == :unhealthy
      end
    end
  end

  describe "batch_query/2" do
    setup %{registry: registry} do
      # Register diverse agents for querying
      pids =
        for i <- 1..20 do
          pid = spawn(fn -> :timer.sleep(:infinity) end)
          capability = if rem(i, 2) == 0, do: :data, else: :compute
          status = if rem(i, 3) == 0, do: :degraded, else: :healthy

          metadata = %{
            capability: capability,
            health_status: status,
            node: :"node_#{rem(i, 4)}",
            resources: %{memory_usage: i * 0.05}
          }

          :ok = GenServer.call(registry, {:register, "query_agent_#{i}", pid, metadata})
          pid
        end

      on_exit(fn ->
        Enum.each(pids, fn pid ->
          if Process.alive?(pid), do: Process.exit(pid, :kill)
        end)
      end)

      :ok
    end

    test "queries with multiple criteria", %{registry: registry} do
      criteria = [
        {[:capability], :data, :eq},
        {[:health_status], :healthy, :eq}
      ]

      assert {:ok, agents} = BatchOperations.batch_query(criteria, registry: registry)

      # Verify all results match criteria
      Enum.each(agents, fn {_id, _pid, metadata} ->
        assert metadata.capability == :data
        assert metadata.health_status == :healthy
      end)
    end

    test "queries with pagination", %{registry: registry} do
      criteria = [{[:capability], :compute, :eq}]

      # Get first page
      assert {:ok, page1} =
               BatchOperations.batch_query(criteria, limit: 5, offset: 0, registry: registry)

      assert length(page1) <= 5

      # Get second page
      assert {:ok, page2} =
               BatchOperations.batch_query(criteria, limit: 5, offset: 5, registry: registry)

      # Ensure no overlap
      page1_ids = Enum.map(page1, &elem(&1, 0))
      page2_ids = Enum.map(page2, &elem(&1, 0))
      assert MapSet.disjoint?(MapSet.new(page1_ids), MapSet.new(page2_ids))
    end

    test "empty query results", %{registry: registry} do
      # Query for non-existent combination
      criteria = [
        {[:capability], :nonexistent, :eq}
      ]

      assert {:ok, []} = BatchOperations.batch_query(criteria, registry: registry)
    end
  end

  describe "stream_query/2" do
    setup %{registry: registry} do
      # Register many agents for streaming
      pids =
        for i <- 1..100 do
          pid = spawn(fn -> :timer.sleep(:infinity) end)

          metadata = %{
            capability: :streaming,
            health_status: :healthy,
            node: node(),
            resources: %{memory_usage: 0.5},
            index: i
          }

          :ok = GenServer.call(registry, {:register, "stream_agent_#{i}", pid, metadata})
          pid
        end

      on_exit(fn ->
        Enum.each(pids, fn pid ->
          if Process.alive?(pid), do: Process.exit(pid, :kill)
        end)
      end)

      :ok
    end

    test "streams query results", %{registry: registry} do
      criteria = [{[:capability], :streaming, :eq}]

      # Take only first 10 from stream
      results =
        BatchOperations.stream_query(criteria, chunk_size: 5, registry: registry)
        |> Enum.take(10)

      assert length(results) == 10

      assert Enum.all?(results, fn {_id, _pid, metadata} ->
               metadata.capability == :streaming
             end)
    end

    test "stream handles transformations", %{registry: registry} do
      criteria = [{[:capability], :streaming, :eq}]

      # Transform stream results
      indices =
        BatchOperations.stream_query(criteria, registry: registry)
        |> Stream.map(fn {_id, _pid, metadata} -> metadata.index end)
        |> Stream.filter(fn index -> rem(index, 2) == 0 end)
        |> Enum.take(5)

      assert length(indices) == 5
      assert Enum.all?(indices, fn i -> rem(i, 2) == 0 end)
    end
  end

  describe "batch_unregister/2" do
    setup %{registry: registry} do
      # Pre-register agents
      {agent_ids, pids} =
        for i <- 1..10 do
          pid = spawn(fn -> :timer.sleep(:infinity) end)
          id = "unregister_test_#{i}"
          :ok = GenServer.call(registry, {:register, id, pid, test_metadata()})
          {id, pid}
        end
        |> Enum.unzip()

      on_exit(fn ->
        Enum.each(pids, fn pid ->
          if Process.alive?(pid), do: Process.exit(pid, :kill)
        end)
      end)

      {:ok, agent_ids: agent_ids}
    end

    test "unregisters multiple agents", %{registry: registry, agent_ids: agent_ids} do
      assert {:ok, unregistered} = BatchOperations.batch_unregister(agent_ids, registry: registry)
      assert length(unregistered) == length(agent_ids)

      # Verify all are gone
      Enum.each(agent_ids, fn id ->
        assert :error = Foundation.Registry.lookup(registry, id)
      end)
    end

    test "handles missing agents with ignore_missing", %{registry: registry, agent_ids: agent_ids} do
      mixed_ids = agent_ids ++ ["nonexistent_1", "nonexistent_2"]

      assert {:ok, unregistered} =
               BatchOperations.batch_unregister(mixed_ids, ignore_missing: true, registry: registry)

      assert length(unregistered) == length(mixed_ids)
    end
  end

  describe "parallel_map/3" do
    setup %{registry: registry} do
      # Register agents with PIDs we can interact with
      agent_pids =
        for i <- 1..10 do
          _test_pid = self()

          pid =
            spawn(fn ->
              receive do
                {:ping, from} -> send(from, {:pong, i})
              end
            end)

          :ok = GenServer.call(registry, {:register, "parallel_#{i}", pid, test_metadata()})
          {i, pid}
        end

      on_exit(fn ->
        Enum.each(agent_pids, fn {_i, pid} ->
          if Process.alive?(pid), do: Process.exit(pid, :kill)
        end)
      end)

      {:ok, agent_pids: agent_pids}
    end

    test "executes function on matching agents in parallel", %{
      registry: registry,
      agent_pids: agent_pids
    } do
      criteria = [{[:capability], :test, :eq}]

      results =
        BatchOperations.parallel_map(
          criteria,
          fn {id, _pid, _metadata} ->
            # Simple transformation
            String.replace(id, "parallel_", "processed_")
          end,
          max_concurrency: 5,
          registry: registry
        )

      successful =
        Enum.filter(results, fn
          {:ok, _} -> true
          _ -> false
        end)

      # The number of registered agents from setup
      expected_count = length(agent_pids)
      assert length(successful) == expected_count

      assert Enum.all?(successful, fn {:ok, result} ->
               String.starts_with?(result, "processed_")
             end)
    end
  end

  describe "telemetry events" do
    test "emits batch operation telemetry", %{registry: registry} do
      :telemetry.attach(
        "test-batch-telemetry",
        [:foundation, :batch_operations, :batch_register],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      pid = spawn(fn -> :timer.sleep(:infinity) end)

      on_exit(fn ->
        if Process.alive?(pid), do: Process.exit(pid, :kill)
      end)

      agents = [
        {"telemetry_test", pid, test_metadata()}
      ]

      BatchOperations.batch_register(agents, registry: registry)

      assert_receive {:telemetry, [:foundation, :batch_operations, :batch_register], measurements,
                      _}

      assert measurements.count == 1
      assert measurements.success_count == 1
      assert measurements.duration > 0

      :telemetry.detach("test-batch-telemetry")
    end
  end

  # Helper functions

  defp test_metadata(status \\ :healthy) do
    %{
      capability: :test,
      health_status: status,
      node: node(),
      resources: %{memory_usage: 0.5}
    }
  end
end
