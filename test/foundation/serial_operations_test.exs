defmodule Foundation.SerialOperationsTest do
  use Foundation.UnifiedTestFoundation, :registry

  alias Foundation.SerialOperations

  describe "transact/1" do
    test "executes successful transaction with multiple operations", %{registry: registry} do
      pid1 = spawn(fn -> :timer.sleep(:infinity) end)
      pid2 = spawn(fn -> :timer.sleep(:infinity) end)

      result =
        SerialOperations.transact(registry, fn tx ->
          tx
          |> SerialOperations.register_agent("agent_1", pid1, test_metadata())
          |> SerialOperations.register_agent("agent_2", pid2, test_metadata())
          |> SerialOperations.update_metadata("agent_1", test_metadata(:degraded))
        end)

      assert {:ok, _tx} = result

      # Verify operations were applied
      assert {:ok, {^pid1, metadata}} = Foundation.Registry.lookup(registry, "agent_1")
      assert metadata.health_status == :degraded
      assert {:ok, {^pid2, _}} = Foundation.Registry.lookup(registry, "agent_2")
    end

    test "rolls back transaction on failure", %{registry: registry} do
      pid1 = spawn(fn -> :timer.sleep(:infinity) end)

      # First register an agent
      :ok = GenServer.call(registry, {:register, "existing", pid1, test_metadata()})

      # Try transaction that will fail
      result =
        SerialOperations.transact(registry, fn tx ->
          tx
          |> SerialOperations.register_agent("new_agent", pid1, test_metadata())
          # This will fail
          |> SerialOperations.register_agent("existing", pid1, test_metadata())
          |> SerialOperations.update_metadata("new_agent", test_metadata(:degraded))
        end)

      assert {:error, _} = result

      # Verify rollback - new_agent should not exist
      assert :error = Foundation.Registry.lookup(registry, "new_agent")
      # Existing agent should be unchanged
      assert {:ok, {^pid1, metadata}} = Foundation.Registry.lookup(registry, "existing")
      assert metadata.health_status == :healthy
    end

    test "handles empty transaction", %{registry: registry} do
      result = SerialOperations.transact(registry, fn tx -> tx end)
      assert {:ok, _tx} = result
    end

    test "supports unregister operations", %{registry: registry} do
      pid1 = spawn(fn -> :timer.sleep(:infinity) end)
      pid2 = spawn(fn -> :timer.sleep(:infinity) end)

      # Setup initial agents
      :ok = GenServer.call(registry, {:register, "agent_1", pid1, test_metadata()})
      :ok = GenServer.call(registry, {:register, "agent_2", pid2, test_metadata()})

      # Transaction with unregister
      result =
        SerialOperations.transact(registry, fn tx ->
          tx
          |> SerialOperations.unregister("agent_1")
          |> SerialOperations.update_metadata("agent_2", test_metadata(:degraded))
        end)

      assert {:ok, _tx} = result

      # Verify operations
      assert :error = Foundation.Registry.lookup(registry, "agent_1")
      assert {:ok, {^pid2, metadata}} = Foundation.Registry.lookup(registry, "agent_2")
      assert metadata.health_status == :degraded
    end

    test "transaction with custom registry", %{registry: registry} do
      pid = spawn(fn -> :timer.sleep(:infinity) end)

      result =
        SerialOperations.transact(registry, fn tx ->
          tx
          |> SerialOperations.register_agent("custom_agent", pid, test_metadata())
        end)

      assert {:ok, _tx} = result
      assert {:ok, {^pid, _}} = Foundation.Registry.lookup(registry, "custom_agent")
    end
  end

  describe "complex scenarios" do
    test "handles process death during transaction", %{registry: registry} do
      # Create a process that will die
      pid = spawn(fn -> :ok end)
      # Ensure process is dead by monitoring it
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1000

      result =
        SerialOperations.transact(registry, fn tx ->
          tx
          |> SerialOperations.register_agent("dead_agent", pid, test_metadata())
        end)

      assert {:error, _} = result
      assert :error = Foundation.Registry.lookup(registry, "dead_agent")
    end

    test "concurrent transactions are serialized", %{registry: registry} do
      # Start multiple transactions concurrently
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            pid = spawn(fn -> :timer.sleep(:infinity) end)

            SerialOperations.transact(registry, fn tx ->
              tx
              |> SerialOperations.register_agent("concurrent_#{i}", pid, test_metadata())
            end)
          end)
        end

      # Wait for all to complete
      results = Task.await_many(tasks)

      # All should succeed
      assert Enum.all?(results, fn
               {:ok, _} -> true
               _ -> false
             end)

      # Verify all agents exist
      for i <- 1..10 do
        assert {:ok, _} = Foundation.Registry.lookup(registry, "concurrent_#{i}")
      end
    end

    test "transaction with metadata validation failure", %{registry: registry} do
      pid = spawn(fn -> :timer.sleep(:infinity) end)

      result =
        SerialOperations.transact(registry, fn tx ->
          tx
          # Missing required fields
          |> SerialOperations.register_agent("invalid", pid, %{})
        end)

      assert {:error, _} = result
      assert :error = Foundation.Registry.lookup(registry, "invalid")
    end
  end

  describe "telemetry events" do
    test "emits telemetry events for successful transaction", %{registry: registry} do
      test_pid = self()

      :telemetry.attach(
        "test-success",
        [:foundation, :transaction, :committed],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, measurements, metadata})
        end,
        nil
      )

      pid = spawn(fn -> :timer.sleep(:infinity) end)

      SerialOperations.transact(registry, fn tx ->
        tx
        |> SerialOperations.register_agent("telemetry_test", pid, test_metadata())
      end)

      assert_receive {:telemetry, measurements, metadata}
      assert measurements[:duration] > 0
      assert measurements[:operation_count] == 1
      assert metadata[:transaction_id] =~ "tx_"

      :telemetry.detach("test-success")
    end

    test "emits telemetry events for rolled back transaction", %{registry: registry} do
      :telemetry.attach(
        "test-rollback",
        [:foundation, :transaction, :rolled_back],
        fn _event, measurements, metadata, _config ->
          send(self(), {:telemetry, measurements, metadata})
        end,
        nil
      )

      pid = spawn(fn -> :timer.sleep(:infinity) end)
      :ok = GenServer.call(registry, {:register, "existing", pid, test_metadata()})

      SerialOperations.transact(registry, fn tx ->
        tx
        # Will fail
        |> SerialOperations.register_agent("existing", pid, test_metadata())
      end)

      assert_receive {:telemetry, measurements, metadata}
      assert measurements[:duration] > 0
      assert measurements[:operation_count] == 1
      assert metadata[:transaction_id] =~ "tx_"

      :telemetry.detach("test-rollback")
    end
  end

  # Helper functions

  defp test_metadata(status \\ :healthy) do
    %{
      capability: [:test],
      health_status: status,
      node: node(),
      resources: %{memory_usage: 0.5}
    }
  end
end
