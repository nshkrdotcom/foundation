defmodule Foundation.MABEAM.CoordinationTest do
  use ExUnit.Case, async: false

  alias Foundation.MABEAM.{Comms, Coordination, ProcessRegistry, Types}

  setup do
    # Start all required services (handle already started services gracefully)
    case start_supervised({ProcessRegistry, [test_mode: true]}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    case start_supervised({Comms, [test_mode: true]}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    case start_supervised({Coordination, [test_mode: true]}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    # Register test agents for coordination
    agent_configs = [
      Types.new_agent_config(:coordinator_1, CoordinationTestAgent, [],
        capabilities: [:consensus, :voting]
      ),
      Types.new_agent_config(:coordinator_2, CoordinationTestAgent, [],
        capabilities: [:consensus, :voting]
      ),
      Types.new_agent_config(:coordinator_3, CoordinationTestAgent, [],
        capabilities: [:consensus, :voting]
      ),
      Types.new_agent_config(:negotiator_1, NegotiationTestAgent, [],
        capabilities: [:negotiation, :bidding]
      ),
      Types.new_agent_config(:negotiator_2, NegotiationTestAgent, [],
        capabilities: [:negotiation, :bidding]
      )
    ]

    Enum.each(agent_configs, &ProcessRegistry.register_agent/1)

    # Start the agents
    started_agents =
      for config <- agent_configs do
        {:ok, pid} = ProcessRegistry.start_agent(config.id)
        {config.id, pid}
      end

    %{agents: started_agents, configs: agent_configs}
  end

  describe "protocol registration and management" do
    test "registers coordination protocol successfully" do
      protocol = %{
        name: :simple_consensus,
        type: :consensus,
        algorithm: :majority_vote,
        timeout: 5000,
        retry_policy: %{max_retries: 3, backoff: :exponential}
      }

      assert :ok = Coordination.register_protocol(:simple_consensus, protocol)

      {:ok, protocols} = Coordination.list_protocols()
      assert :simple_consensus in Enum.map(protocols, fn {name, _} -> name end)
    end

    test "rejects invalid protocol registration" do
      invalid_protocols = [
        # Missing required fields
        %{name: :invalid},
        # Invalid type
        %{type: :unknown, algorithm: :test},
        # Not a map
        nil,
        # Invalid name
        %{name: nil, type: :consensus}
      ]

      for {invalid_protocol, index} <- Enum.with_index(invalid_protocols) do
        protocol_name = :"invalid_#{index}"
        assert {:error, _reason} = Coordination.register_protocol(protocol_name, invalid_protocol)
      end
    end

    test "prevents duplicate protocol registration" do
      protocol = %{
        name: :duplicate_test,
        type: :consensus,
        algorithm: :unanimous,
        timeout: 3000
      }

      assert :ok = Coordination.register_protocol(:duplicate_test, protocol)

      assert {:error, :already_registered} =
               Coordination.register_protocol(:duplicate_test, protocol)
    end

    test "allows protocol updates" do
      original_protocol = %{
        name: :updatable,
        type: :consensus,
        algorithm: :majority_vote,
        timeout: 5000
      }

      updated_protocol = %{
        name: :updatable,
        type: :consensus,
        algorithm: :unanimous,
        timeout: 10_000
      }

      assert :ok = Coordination.register_protocol(:updatable, original_protocol)
      assert :ok = Coordination.update_protocol(:updatable, updated_protocol)

      {:ok, protocols} = Coordination.list_protocols()
      {_, retrieved_protocol} = List.keyfind(protocols, :updatable, 0)
      assert retrieved_protocol.algorithm == :unanimous
      assert retrieved_protocol.timeout == 10_000
    end
  end

  describe "basic consensus coordination" do
    test "coordinates with empty agent list" do
      protocol = create_consensus_protocol()
      :ok = Coordination.register_protocol(:empty_consensus, protocol)

      assert {:ok, []} = Coordination.coordinate(:empty_consensus, [], %{decision: :test})
    end

    test "coordinates with single agent", %{agents: agents} do
      protocol = create_consensus_protocol()
      :ok = Coordination.register_protocol(:single_consensus, protocol)

      {agent_id, _pid} = List.keyfind(agents, :coordinator_1, 0)

      assert {:ok, results} =
               Coordination.coordinate(:single_consensus, [agent_id], %{
                 question: "Proceed with action?",
                 options: [:yes, :no]
               })

      assert length(results) == 1
      [result] = results
      assert result.agent_id == agent_id
      assert result.response in [:yes, :no]
    end

    test "coordinates with multiple agents using majority vote", %{agents: agents} do
      protocol = create_consensus_protocol(%{algorithm: :majority_vote})
      :ok = Coordination.register_protocol(:majority_consensus, protocol)

      coordinator_agents =
        agents
        |> Enum.filter(fn {id, _} -> id |> to_string() |> String.starts_with?("coordinator_") end)
        |> Enum.map(fn {id, _} -> id end)

      assert {:ok, results} =
               Coordination.coordinate(:majority_consensus, coordinator_agents, %{
                 question: "Should we proceed with task X?",
                 options: [:yes, :no]
               })

      assert length(results) == length(coordinator_agents)

      # Verify consensus was reached
      assert {:ok, consensus_result} =
               Coordination.get_consensus_result(:majority_consensus, results)

      assert consensus_result.decision in [:yes, :no]
      assert consensus_result.confidence >= 0.0
      assert consensus_result.confidence <= 1.0
    end

    test "handles consensus timeout gracefully", %{agents: agents} do
      # Very short timeout
      protocol = create_consensus_protocol(%{timeout: 100})
      :ok = Coordination.register_protocol(:timeout_consensus, protocol)

      {slow_agent, _} = List.keyfind(agents, :coordinator_1, 0)

      # This should timeout due to short timeout
      assert {:error, :timeout} =
               Coordination.coordinate(:timeout_consensus, [slow_agent], %{
                 question: "Very slow question?",
                 # Longer than timeout
                 delay: 200
               })
    end

    test "requires unanimous consent for unanimous algorithm", %{agents: agents} do
      protocol = create_consensus_protocol(%{algorithm: :unanimous})
      :ok = Coordination.register_protocol(:unanimous_consensus, protocol)

      coordinator_agents =
        agents
        |> Enum.filter(fn {id, _} -> id |> to_string() |> String.starts_with?("coordinator_") end)
        |> Enum.map(fn {id, _} -> id end)

      assert {:ok, results} =
               Coordination.coordinate(:unanimous_consensus, coordinator_agents, %{
                 question: "Must all agents agree?",
                 options: [:yes, :no],
                 force_unanimous: true
               })

      assert {:ok, _consensus_result} =
               Coordination.get_consensus_result(:unanimous_consensus, results)

      # All agents should have the same response for unanimous
      responses = Enum.map(results, & &1.response)
      assert Enum.uniq(responses) |> length() == 1
    end
  end

  describe "negotiation coordination" do
    test "simple two-party negotiation", %{agents: agents} do
      protocol = create_negotiation_protocol()
      :ok = Coordination.register_protocol(:simple_negotiation, protocol)

      negotiators =
        agents
        |> Enum.filter(fn {id, _} -> id |> to_string() |> String.starts_with?("negotiator_") end)
        |> Enum.map(fn {id, _} -> id end)
        |> Enum.take(2)

      assert {:ok, results} =
               Coordination.coordinate(:simple_negotiation, negotiators, %{
                 resource: :compute_time,
                 total_available: 100,
                 initial_offers: %{
                   "negotiator_1" => 60,
                   "negotiator_2" => 40
                 }
               })

      assert length(results) == 2

      # Verify negotiation reached agreement
      assert {:ok, negotiation_result} =
               Coordination.get_negotiation_result(:simple_negotiation, results)

      assert negotiation_result.agreement_reached == true
      assert is_map(negotiation_result.final_allocation)
    end

    test "multi-party resource allocation", %{agents: agents} do
      protocol = create_negotiation_protocol(%{type: :resource_allocation})
      :ok = Coordination.register_protocol(:resource_allocation, protocol)

      all_agents = Enum.map(agents, fn {id, _} -> id end)

      assert {:ok, results} =
               Coordination.coordinate(:resource_allocation, all_agents, %{
                 resources: %{
                   cpu: 100,
                   memory: 1000,
                   storage: 500
                 },
                 agent_requirements: %{
                   "coordinator_1" => %{cpu: 20, memory: 200},
                   "coordinator_2" => %{cpu: 30, memory: 300},
                   "coordinator_3" => %{cpu: 25, memory: 250},
                   "negotiator_1" => %{cpu: 15, memory: 150},
                   "negotiator_2" => %{cpu: 10, memory: 100}
                 }
               })

      assert length(results) == length(all_agents)

      assert {:ok, allocation_result} =
               Coordination.get_allocation_result(:resource_allocation, results)

      # Results should be structured properly for allocation
      assert allocation_result.allocation_successful == true
      assert is_map(allocation_result.final_allocation)
    end
  end

  describe "coordination session management" do
    test "tracks active coordination sessions" do
      protocol = create_consensus_protocol()
      :ok = Coordination.register_protocol(:session_tracking, protocol)

      # Get initial session count
      {:ok, initial_sessions} = Coordination.list_active_sessions()
      initial_count = length(initial_sessions)

      # Start coordination - use async version to immediately return session ID
      # Add some delay to keep session active longer for testing
      {:ok, session_id} =
        Coordination.coordinate_async(:session_tracking, [:coordinator_1], %{
          question: "Long running?",
          delay: 100
        })

      # Check that session is tracked as active
      # Give time for session to start
      Process.sleep(20)

      {:ok, active_sessions} = Coordination.list_active_sessions()
      assert length(active_sessions) > initial_count

      # Wait for session completion
      wait_for_session_completion(session_id)

      # Session should be cleaned up after some time
      # Wait longer than cleanup delay
      Process.sleep(150)
      {:ok, active_sessions_after} = Coordination.list_active_sessions()
      assert length(active_sessions_after) <= initial_count
    end

    test "cancels coordination session" do
      # Long timeout
      protocol = create_consensus_protocol(%{timeout: 10_000})
      :ok = Coordination.register_protocol(:cancellable, protocol)

      # Start long-running coordination
      task =
        Task.async(fn ->
          Coordination.coordinate(:cancellable, [:coordinator_1], %{
            question: "Very long question?",
            # Shorter delay to ensure session is found
            delay: 200
          })
        end)

      # Let it start
      Process.sleep(20)

      # Find and cancel the coordination session
      case Coordination.get_session_for_protocol(:cancellable) do
        {:ok, session_id} ->
          assert :ok = Coordination.cancel_session(session_id)
          # Should return cancellation error or normal result (race condition)
          result = Task.await(task)

          case result do
            {:error, :cancelled} -> :ok
            {:ok, [%{agent_id: :coordinator_1, status: :success}]} -> :ok
            {:ok, results} when is_list(results) -> :ok
            _ -> flunk("Unexpected result: #{inspect(result)}")
          end

        {:error, :not_found} ->
          # Session completed too quickly, just wait for result
          {:ok, _results} = Task.await(task)
      end
    end

    test "handles concurrent coordination sessions", %{agents: agents} do
      protocol = create_consensus_protocol()
      :ok = Coordination.register_protocol(:concurrent, protocol)

      coordinator_agents =
        agents
        |> Enum.filter(fn {id, _} -> id |> to_string() |> String.starts_with?("coordinator_") end)
        |> Enum.map(fn {id, _} -> id end)

      # Start multiple concurrent coordinations
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            Coordination.coordinate(:concurrent, coordinator_agents, %{
              question: "Concurrent question #{i}?",
              session_id: "session_#{i}"
            })
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All should succeed
      assert Enum.all?(results, &match?({:ok, _}, &1))
      assert length(results) == 5
    end
  end

  describe "error handling and edge cases" do
    test "handles non-existent protocol" do
      assert {:error, :protocol_not_found} =
               Coordination.coordinate(:nonexistent, [:coordinator_1], %{})
    end

    test "handles non-existent agents" do
      protocol = create_consensus_protocol()
      :ok = Coordination.register_protocol(:nonexistent_agents, protocol)

      assert {:error, :agents_not_found} =
               Coordination.coordinate(:nonexistent_agents, [:nonexistent_agent], %{})
    end

    test "handles mixed existent and non-existent agents", %{agents: agents} do
      protocol = create_consensus_protocol()
      :ok = Coordination.register_protocol(:mixed_agents, protocol)

      {real_agent, _} = List.keyfind(agents, :coordinator_1, 0)
      mixed_agents = [real_agent, :nonexistent_agent]

      assert {:error, :some_agents_not_found} =
               Coordination.coordinate(:mixed_agents, mixed_agents, %{})
    end

    test "handles agent failures during coordination", %{agents: agents} do
      protocol = create_consensus_protocol(%{fault_tolerance: :continue_on_failure})
      :ok = Coordination.register_protocol(:fault_tolerant, protocol)

      {agent_id, _} = List.keyfind(agents, :coordinator_1, 0)

      # Coordination should handle agent failure gracefully
      assert {:ok, results} =
               Coordination.coordinate(:fault_tolerant, [agent_id], %{
                 question: "Question with failure?",
                 simulate_failure: true
               })

      # Should get partial results or failure indication
      assert is_list(results)
    end

    test "validates coordination context" do
      protocol = create_consensus_protocol()
      :ok = Coordination.register_protocol(:context_validation, protocol)

      invalid_contexts = [
        nil,
        "string_context",
        123,
        []
      ]

      for invalid_context <- invalid_contexts do
        assert {:error, :invalid_context} =
                 Coordination.coordinate(:context_validation, [:coordinator_1], invalid_context)
      end
    end
  end

  describe "telemetry and monitoring" do
    test "emits telemetry events for coordination lifecycle" do
      # Set up telemetry capture
      test_pid = self()
      events = [:coordination_start, :coordination_complete, :consensus_reached]

      for event <- events do
        :telemetry.attach(
          "test-#{event}",
          [:foundation, :mabeam, :coordination, event],
          fn _event, _measurements, _metadata, _config ->
            send(test_pid, {:telemetry, event})
          end,
          %{}
        )
      end

      protocol = create_consensus_protocol()
      :ok = Coordination.register_protocol(:telemetry_test, protocol)

      {:ok, _results} =
        Coordination.coordinate(:telemetry_test, [:coordinator_1], %{
          question: "Telemetry question?"
        })

      # Should receive telemetry events
      assert_receive {:telemetry, :coordination_start}, 1000
      assert_receive {:telemetry, :coordination_complete}, 1000

      # Cleanup
      for event <- events do
        :telemetry.detach("test-#{event}")
      end
    end

    test "provides coordination statistics" do
      protocol = create_consensus_protocol()
      :ok = Coordination.register_protocol(:stats_test, protocol)

      # Get initial stats
      {:ok, initial_stats} = Coordination.get_coordination_stats()

      # Perform some coordinations
      for i <- 1..3 do
        {:ok, _} =
          Coordination.coordinate(:stats_test, [:coordinator_1], %{question: "Stats #{i}?"})
      end

      # Check updated stats
      {:ok, final_stats} = Coordination.get_coordination_stats()

      assert final_stats.total_coordinations > initial_stats.total_coordinations
      assert final_stats.successful_coordinations > initial_stats.successful_coordinations
      assert is_number(final_stats.average_coordination_time)
    end
  end

  describe "performance and scalability" do
    test "handles high-volume coordination requests", %{agents: agents} do
      protocol = create_consensus_protocol()
      :ok = Coordination.register_protocol(:high_volume, protocol)

      coordinator_agents =
        agents
        |> Enum.filter(fn {id, _} -> id |> to_string() |> String.starts_with?("coordinator_") end)
        |> Enum.map(fn {id, _} -> id end)

      # Perform many coordinations concurrently
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            Coordination.coordinate(:high_volume, coordinator_agents, %{
              question: "High volume question #{i}?",
              options: [:yes, :no]
            })
          end)
        end

      start_time = System.monotonic_time(:millisecond)
      results = Task.await_many(tasks, 10_000)
      end_time = System.monotonic_time(:millisecond)

      # All should succeed
      success_count = Enum.count(results, &match?({:ok, _}, &1))
      assert success_count == 50

      # Should complete in reasonable time (less than 5 seconds for 50 coordinations)
      assert end_time - start_time < 5000
    end

    test "coordination memory usage remains stable" do
      protocol = create_consensus_protocol()
      :ok = Coordination.register_protocol(:memory_test, protocol)

      # Monitor memory before
      initial_memory = :erlang.memory(:total)

      # Perform many coordinations
      for i <- 1..100 do
        {:ok, _} =
          Coordination.coordinate(:memory_test, [:coordinator_1], %{question: "Memory #{i}?"})
      end

      # Force garbage collection
      :erlang.garbage_collect()
      Process.sleep(10)

      final_memory = :erlang.memory(:total)

      # Memory growth should be minimal (less than 10MB)
      memory_growth = final_memory - initial_memory
      assert memory_growth < 10_485_760
    end
  end

  # Helper functions

  defp create_consensus_protocol(overrides \\ %{}) do
    defaults = %{
      name: :test_consensus,
      type: :consensus,
      algorithm: :majority_vote,
      timeout: 5000,
      retry_policy: %{max_retries: 3, backoff: :linear}
    }

    Map.merge(defaults, overrides)
  end

  defp create_negotiation_protocol(overrides \\ %{}) do
    defaults = %{
      name: :test_negotiation,
      type: :negotiation,
      algorithm: :bilateral_bargaining,
      timeout: 10_000,
      retry_policy: %{max_retries: 5, backoff: :exponential}
    }

    Map.merge(defaults, overrides)
  end

  defp wait_for_session_completion(session_id, max_attempts \\ 50) do
    wait_for_session_completion(session_id, 0, max_attempts)
  end

  defp wait_for_session_completion(_session_id, attempts, max_attempts)
       when attempts >= max_attempts do
    :timeout
  end

  defp wait_for_session_completion(session_id, attempts, max_attempts) do
    case Coordination.get_session_results(session_id) do
      {:ok, _results} ->
        :ok

      {:error, :session_active} ->
        Process.sleep(100)
        wait_for_session_completion(session_id, attempts + 1, max_attempts)

      {:error, _} ->
        :error
    end
  end
end
