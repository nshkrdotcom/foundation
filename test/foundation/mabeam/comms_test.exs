defmodule Foundation.MABEAM.CommsTest do
  use ExUnit.Case, async: false

  alias Foundation.MABEAM.{Comms, ProcessRegistry, Types}

  setup do
    # Start registry and communication system
    start_supervised!({ProcessRegistry, [test_mode: true]})
    start_supervised!({Comms, [test_mode: true]})
    
    # Register test agents
    agent_configs = [
      Types.new_agent_config(:responder, TestResponder, [], capabilities: [:responds]),
      Types.new_agent_config(:slow_responder, SlowTestResponder, [delay: 500], capabilities: [:responds]),
      Types.new_agent_config(:failing_responder, FailingTestResponder, [], capabilities: [:responds]),
      Types.new_agent_config(:echo_agent, EchoTestAgent, [], capabilities: [:echo])
    ]
    
    Enum.each(agent_configs, &ProcessRegistry.register_agent/1)
    
    # Start the agents
    started_agents = for config <- agent_configs do
      {:ok, pid} = ProcessRegistry.start_agent(config.id)
      {config.id, pid}
    end
    
    %{agents: started_agents, configs: agent_configs}
  end

  describe "basic communication" do
    test "successful request-response", %{agents: agents} do
      {responder_id, _pid} = List.keyfind(agents, :responder, 0)
      
      result = Comms.request(responder_id, {:echo, "hello world"})
      
      assert {:ok, "hello world"} = result
    end

    test "request with custom timeout", %{agents: agents} do
      {slow_id, _pid} = List.keyfind(agents, :slow_responder, 0)
      
      # Should timeout with short timeout
      result = Comms.request(slow_id, {:slow_echo, "test"}, 100)
      assert {:error, :timeout} = result
      
      # Should succeed with longer timeout
      result = Comms.request(slow_id, {:slow_echo, "test"}, 1000)
      assert {:ok, "test"} = result
    end

    test "fire-and-forget messaging", %{agents: agents} do
      {responder_id, _pid} = List.keyfind(agents, :responder, 0)
      
      # Send notification - should not wait for response
      start_time = System.monotonic_time(:millisecond)
      result = Comms.notify(responder_id, {:update_state, %{key: "value"}})
      end_time = System.monotonic_time(:millisecond)
      
      assert :ok = result
      # Should return immediately (within 50ms)
      assert end_time - start_time < 50
      
      # Verify the agent received the message
      state_result = Comms.request(responder_id, :get_state)
      assert {:ok, %{key: "value"}} = state_result
    end

    test "handles non-existent agents", %{agents: _agents} do
      result = Comms.request(:nonexistent_agent, {:test, "message"})
      assert {:error, :agent_not_found} = result
      
      result = Comms.notify(:nonexistent_agent, {:test, "message"})
      assert {:error, :agent_not_found} = result
    end

    test "handles agent failures gracefully", %{agents: agents} do
      {failing_id, failing_pid} = List.keyfind(agents, :failing_responder, 0)
      
      # Send request that will cause agent to crash
      result = Comms.request(failing_id, :crash_please)
      assert {:error, :agent_crashed} = result
      
      # Verify agent is dead
      refute Process.alive?(failing_pid)
      
      # Subsequent requests should fail with agent_not_found
      result = Comms.request(failing_id, {:test, "message"})
      assert {:error, :agent_not_found} = result
    end
  end

  describe "coordination requests" do
    test "successful coordination request", %{agents: agents} do
      {responder_id, _pid} = List.keyfind(agents, :responder, 0)
      
      result = Comms.coordination_request(
        responder_id,
        :consensus,
        %{question: "Proceed with action?", options: [:yes, :no]},
        5000
      )
      
      assert {:ok, %{response: :yes}} = result
    end

    test "coordination request timeout", %{agents: agents} do
      {slow_id, _pid} = List.keyfind(agents, :slow_responder, 0)
      
      result = Comms.coordination_request(
        slow_id,
        :consensus,
        %{question: "Slow question?", options: [:yes, :no]},
        100  # Short timeout
      )
      
      assert {:error, :timeout} = result
    end

    test "coordination request with invalid protocol", %{agents: agents} do
      {responder_id, _pid} = List.keyfind(agents, :responder, 0)
      
      result = Comms.coordination_request(
        responder_id,
        :unknown_protocol,
        %{data: "test"},
        1000
      )
      
      assert {:error, :unsupported_protocol} = result
    end
  end

  describe "performance and reliability" do
    test "handles high message volume", %{agents: agents} do
      {echo_id, _pid} = List.keyfind(agents, :echo_agent, 0)
      
      # Send many concurrent requests
      tasks = for i <- 1..100 do
        Task.async(fn ->
          Comms.request(echo_id, {:echo, "message_#{i}"})
        end)
      end
      
      start_time = System.monotonic_time(:millisecond)
      results = Task.await_many(tasks, 5000)
      end_time = System.monotonic_time(:millisecond)
      
      # All requests should succeed
      assert length(results) == 100
      success_count = Enum.count(results, &match?({:ok, _}, &1))
      assert success_count == 100
      
      # Should complete in reasonable time (less than 2 seconds for 100 requests)
      assert end_time - start_time < 2000
    end

    test "request deduplication", %{agents: agents} do
      {responder_id, _pid} = List.keyfind(agents, :responder, 0)
      
      # Send the same request multiple times rapidly
      request_id = "unique_#{:erlang.unique_integer()}"
      
      tasks = for _i <- 1..10 do
        Task.async(fn ->
          Comms.request(responder_id, {:dedupe_test, request_id})
        end)
      end
      
      results = Task.await_many(tasks)
      
      # All should succeed, but the agent should only process once
      assert length(results) == 10
      assert Enum.all?(results, &match?({:ok, _}, &1))
      
      # Verify agent only processed the request once
      {:ok, process_count} = Comms.request(responder_id, {:get_process_count, request_id})
      assert process_count == 1
    end

    test "message ordering guarantees", %{agents: agents} do
      {responder_id, _pid} = List.keyfind(agents, :responder, 0)
      
      # Send ordered sequence of messages
      sequence = 1..50
      
      # Send notifications in order
      for i <- sequence do
        :ok = Comms.notify(responder_id, {:sequence, i})
      end
      
      # Give time for all messages to be processed
      Process.sleep(100)
      
      # Verify order was preserved
      {:ok, received_sequence} = Comms.request(responder_id, :get_sequence)
      assert received_sequence == Enum.to_list(sequence)
    end
  end

  describe "error handling and edge cases" do
    test "handles malformed messages gracefully", %{agents: agents} do
      {responder_id, _pid} = List.keyfind(agents, :responder, 0)
      
      # Send various malformed messages
      malformed_cases = [
        nil,
        "",
        %{},
        {:incomplete_tuple},
        {:unknown_command, :with, :too, :many, :args}
      ]
      
      for malformed <- malformed_cases do
        result = Comms.request(responder_id, malformed)
        # Should get a response, even if it's an error
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end
    end

    test "communication during agent restart", %{agents: agents} do
      {responder_id, old_pid} = List.keyfind(agents, :responder, 0)
      
      # Send initial request to verify agent works
      {:ok, _} = Comms.request(responder_id, {:echo, "before_restart"})
      
      # Restart the agent
      :ok = ProcessRegistry.stop_agent(responder_id)
      Process.sleep(10)  # Brief pause
      {:ok, new_pid} = ProcessRegistry.start_agent(responder_id)
      
      assert old_pid != new_pid
      
      # Communication should work with new process
      result = Comms.request(responder_id, {:echo, "after_restart"})
      assert {:ok, "after_restart"} = result
    end

    test "request cancellation", %{agents: agents} do
      {slow_id, _pid} = List.keyfind(agents, :slow_responder, 0)
      
      # Start a long-running request
      task = Task.async(fn ->
        Comms.request(slow_id, {:very_slow_operation, 2000}, 5000)
      end)
      
      # Cancel it quickly
      Task.shutdown(task, :brutal_kill)
      
      # Agent should still be responsive
      result = Comms.request(slow_id, {:echo, "still_alive"})
      assert {:ok, "still_alive"} = result
    end

    test "memory cleanup after failed requests", %{agents: agents} do
      {failing_id, _pid} = List.keyfind(agents, :failing_responder, 0)
      
      # Monitor memory usage
      initial_memory = :erlang.memory(:total)
      
      # Send many requests that will fail
      for _i <- 1..100 do
        {:error, _} = Comms.request(failing_id, :guaranteed_failure)
      end
      
      # Force garbage collection
      :erlang.garbage_collect()
      Process.sleep(10)
      
      final_memory = :erlang.memory(:total)
      
      # Memory usage should not grow significantly
      memory_growth = final_memory - initial_memory
      # Allow for some growth, but not excessive (less than 1MB)
      assert memory_growth < 1_048_576
    end
  end

  describe "telemetry and monitoring" do
    test "emits telemetry events for requests", %{agents: agents} do
      # Attach telemetry handler for testing
      test_pid = self()
      
      handler_id = :test_comms_telemetry
      :telemetry.attach(
        handler_id,
        [:foundation, :mabeam, :comms, :request],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        %{}
      )
      
      {responder_id, _pid} = List.keyfind(agents, :responder, 0)
      
      # Make request
      {:ok, _} = Comms.request(responder_id, {:echo, "telemetry_test"})
      
      # Should receive telemetry event
      assert_receive {:telemetry_event, [:foundation, :mabeam, :comms, :request], measurements, metadata}
      
      assert Map.has_key?(measurements, :duration)
      assert Map.has_key?(metadata, :agent_id)
      assert metadata.agent_id == responder_id
      
      # Cleanup
      :telemetry.detach(handler_id)
    end

    test "tracks communication statistics", %{agents: agents} do
      {responder_id, _pid} = List.keyfind(agents, :responder, 0)
      
      # Get initial stats
      initial_stats = Comms.get_communication_stats()
      
      # Make several requests
      for i <- 1..5 do
        {:ok, _} = Comms.request(responder_id, {:echo, "stats_test_#{i}"})
      end
      
      # Get updated stats
      final_stats = Comms.get_communication_stats()
      
      # Should show increased activity
      assert final_stats.total_requests > initial_stats.total_requests
      assert final_stats.successful_requests > initial_stats.successful_requests
    end
  end

  describe "distributed communication preparation" do
    test "message serialization compatibility" do
      # All message types should be serializable for future distributed use
      test_messages = [
        {:echo, "simple string"},
        {:complex_data, %{list: [1, 2, 3], map: %{nested: true}}},
        {:tuple_message, {:nested, :tuple, 123}},
        {:binary_data, <<1, 2, 3, 4, 5>>},
        {:coordination_request, Types.new_coordination_request(
          :consensus,
          :voting,
          %{question: "test?", options: [:yes, :no]}
        )}
      ]
      
      for message <- test_messages do
        binary = :erlang.term_to_binary(message)
        deserialized = :erlang.binary_to_term(binary)
        assert message == deserialized
      end
    end

    test "node-agnostic agent addressing", %{agents: agents} do
      # Agent IDs should work regardless of which node they're on
      {responder_id, _pid} = List.keyfind(agents, :responder, 0)
      
      # Current implementation should work with atom IDs
      assert is_atom(responder_id)
      
      # Should also work with node-qualified addresses (for future)
      _node_qualified_id = {responder_id, node()}
      
      # This would work in distributed setup
      result = case Comms.request(responder_id, {:echo, "node_test"}) do
        {:ok, response} -> {:ok, response}
        error -> error
      end
      
      assert {:ok, "node_test"} = result
    end
  end
end