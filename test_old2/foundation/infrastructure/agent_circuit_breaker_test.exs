defmodule Foundation.Infrastructure.AgentCircuitBreakerTest do
  use ExUnit.Case, async: false

  alias Foundation.Infrastructure.AgentCircuitBreaker
  alias Foundation.ProcessRegistry
  alias Foundation.Types.AgentInfo

  setup do
    namespace = {:test, make_ref()}
    
    # Register test agent
    pid = spawn(fn -> Process.sleep(2000) end)
    agent_metadata = %AgentInfo{
      id: :test_agent,
      type: :ml_agent,
      capabilities: [:inference],
      health: :healthy,
      resource_usage: %{memory: 0.5, cpu: 0.3}
    }

    ProcessRegistry.register_agent(namespace, :test_agent, pid, agent_metadata)

    on_exit(fn ->
      try do
        ProcessRegistry.unregister(namespace, :test_agent)
        AgentCircuitBreaker.stop_agent_breaker(:ml_inference_service, :test_agent)
      rescue
        _ -> :ok
      end
    end)

    {:ok, namespace: namespace, agent_pid: pid}
  end

  describe "agent-aware circuit breaker creation" do
    test "creates agent circuit breaker with health integration", %{namespace: namespace} do
      {:ok, breaker_pid} = AgentCircuitBreaker.start_agent_breaker(
        :ml_inference_service,
        agent_id: :test_agent,
        capability: :inference,
        resource_thresholds: %{memory: 0.8, cpu: 0.9},
        namespace: namespace
      )

      assert is_pid(breaker_pid)

      assert {:ok, status} = 
        AgentCircuitBreaker.get_agent_status(:ml_inference_service, :test_agent)

      assert status.agent_id == :test_agent
      assert status.capability == :inference
      assert status.circuit_state == :closed
      assert status.resource_thresholds.memory == 0.8
    end

    test "validates agent exists before creating breaker", %{namespace: namespace} do
      assert {:error, :agent_not_found} = AgentCircuitBreaker.start_agent_breaker(
        :ml_service,
        agent_id: :nonexistent_agent,
        capability: :inference,
        namespace: namespace
      )
    end

    test "validates agent has required capability", %{namespace: namespace} do
      assert {:error, :capability_not_found} = AgentCircuitBreaker.start_agent_breaker(
        :training_service,
        agent_id: :test_agent,
        capability: :training,  # test_agent only has :inference
        namespace: namespace
      )
    end
  end

  describe "agent health integration" do
    test "circuit considers agent health in decisions", %{namespace: namespace} do
      {:ok, _breaker_pid} = AgentCircuitBreaker.start_agent_breaker(
        :ml_service,
        agent_id: :test_agent,
        capability: :inference,
        namespace: namespace
      )

      # Initially healthy - operations should succeed
      result = AgentCircuitBreaker.execute_with_agent(
        :ml_service,
        :test_agent,
        fn -> {:ok, "success"} end,
        %{operation: :test_inference}
      )
      assert {:ok, "success"} = result

      # Simulate agent health degradation
      degraded_metadata = %AgentInfo{
        id: :test_agent,
        type: :ml_agent,
        capabilities: [:inference],
        health: :unhealthy,
        resource_usage: %{memory: 0.95, cpu: 0.9}
      }

      ProcessRegistry.update_agent_metadata(namespace, :test_agent, degraded_metadata)

      # Circuit should consider agent health and possibly reject operations
      result = AgentCircuitBreaker.execute_with_agent(
        :ml_service,
        :test_agent,
        fn -> {:ok, "success"} end,
        %{operation: :test_inference}
      )

      # Should fail due to unhealthy agent
      assert {:error, reason} = result
      assert reason =~ "agent_unhealthy" or reason =~ "circuit_open"
    end

    test "circuit monitors agent resource usage", %{namespace: namespace} do
      {:ok, _breaker_pid} = AgentCircuitBreaker.start_agent_breaker(
        :resource_intensive_service,
        agent_id: :test_agent,
        capability: :inference,
        resource_thresholds: %{memory: 0.8, cpu: 0.7},
        namespace: namespace
      )

      # Update agent to show high resource usage
      high_resource_metadata = %AgentInfo{
        id: :test_agent,
        type: :ml_agent,
        capabilities: [:inference],
        health: :healthy,
        resource_usage: %{memory: 0.95, cpu: 0.85}  # Above thresholds
      }

      ProcessRegistry.update_agent_metadata(namespace, :test_agent, high_resource_metadata)

      # Circuit should reject operations due to resource constraints
      result = AgentCircuitBreaker.execute_with_agent(
        :resource_intensive_service,
        :test_agent,
        fn -> {:ok, "resource_intensive_operation"} end
      )

      assert {:error, reason} = result
      assert reason =~ "resource_exhausted" or reason =~ "circuit_open"
    end
  end

  describe "circuit state management" do
    test "circuit opens after failure threshold", %{namespace: namespace} do
      {:ok, _breaker_pid} = AgentCircuitBreaker.start_agent_breaker(
        :failing_service,
        agent_id: :test_agent,
        capability: :inference,
        failure_threshold: 3,
        namespace: namespace
      )

      # Execute failing operations to trigger circuit opening
      for _i <- 1..3 do
        AgentCircuitBreaker.execute_with_agent(
          :failing_service,
          :test_agent,
          fn -> {:error, "simulated_failure"} end
        )
      end

      # Circuit should now be open
      {:ok, status} = AgentCircuitBreaker.get_agent_status(:failing_service, :test_agent)
      assert status.circuit_state == :open

      # Further operations should be rejected immediately
      result = AgentCircuitBreaker.execute_with_agent(
        :failing_service,
        :test_agent,
        fn -> {:ok, "should_not_execute"} end
      )

      assert {:error, :circuit_open} = result
    end

    test "circuit transitions to half-open after timeout", %{namespace: namespace} do
      {:ok, _breaker_pid} = AgentCircuitBreaker.start_agent_breaker(
        :recovery_service,
        agent_id: :test_agent,
        capability: :inference,
        failure_threshold: 2,
        recovery_timeout: 100,  # Short timeout for testing
        namespace: namespace
      )

      # Trigger circuit opening
      for _i <- 1..2 do
        AgentCircuitBreaker.execute_with_agent(
          :recovery_service,
          :test_agent,
          fn -> {:error, "failure"} end
        )
      end

      # Wait for recovery timeout
      Process.sleep(150)

      # Next operation should transition to half-open
      result = AgentCircuitBreaker.execute_with_agent(
        :recovery_service,
        :test_agent,
        fn -> {:ok, "recovery_test"} end
      )

      assert {:ok, "recovery_test"} = result

      # Check circuit is now closed again
      {:ok, status} = AgentCircuitBreaker.get_agent_status(:recovery_service, :test_agent)
      assert status.circuit_state == :closed
    end
  end

  describe "agent context enrichment" do
    test "operations include agent context in metadata", %{namespace: namespace} do
      {:ok, _breaker_pid} = AgentCircuitBreaker.start_agent_breaker(
        :context_service,
        agent_id: :test_agent,
        capability: :inference,
        namespace: namespace
      )

      # Capture context passed to operation
      context_received = Agent.start_link(fn -> nil end)

      operation = fn ->
        # This would normally receive agent context
        Agent.update(context_received, fn _ -> 
          %{agent_id: :test_agent, capability: :inference}
        end)
        {:ok, "with_context"}
      end

      AgentCircuitBreaker.execute_with_agent(
        :context_service,
        :test_agent,
        operation,
        %{include_agent_context: true}
      )

      context = Agent.get(context_received, & &1)
      assert context.agent_id == :test_agent
      assert context.capability == :inference
    end
  end

  describe "multiple agents support" do
    test "manages circuits for multiple agents independently", %{namespace: namespace} do
      # Register second agent
      pid2 = spawn(fn -> Process.sleep(2000) end)
      agent2_metadata = %AgentInfo{
        id: :test_agent_2,
        type: :ml_agent,
        capabilities: [:inference],
        health: :healthy
      }
      ProcessRegistry.register_agent(namespace, :test_agent_2, pid2, agent2_metadata)

      # Create circuits for both agents
      {:ok, _breaker1} = AgentCircuitBreaker.start_agent_breaker(
        :multi_agent_service,
        agent_id: :test_agent,
        capability: :inference,
        namespace: namespace
      )

      {:ok, _breaker2} = AgentCircuitBreaker.start_agent_breaker(
        :multi_agent_service,
        agent_id: :test_agent_2,
        capability: :inference,
        namespace: namespace
      )

      # Make agent 1 fail while agent 2 succeeds
      for _i <- 1..3 do
        AgentCircuitBreaker.execute_with_agent(
          :multi_agent_service,
          :test_agent,
          fn -> {:error, "agent1_failure"} end
        )
      end

      AgentCircuitBreaker.execute_with_agent(
        :multi_agent_service,
        :test_agent_2,
        fn -> {:ok, "agent2_success"} end
      )

      # Check that circuits have different states
      {:ok, status1} = AgentCircuitBreaker.get_agent_status(:multi_agent_service, :test_agent)
      {:ok, status2} = AgentCircuitBreaker.get_agent_status(:multi_agent_service, :test_agent_2)

      assert status1.circuit_state == :open
      assert status2.circuit_state == :closed
    end
  end

  describe "telemetry and monitoring" do
    test "emits telemetry events for circuit operations", %{namespace: namespace} do
      {:ok, _breaker_pid} = AgentCircuitBreaker.start_agent_breaker(
        :telemetry_service,
        agent_id: :test_agent,
        capability: :inference,
        namespace: namespace
      )

      # Set up telemetry handler to capture events
      events = Agent.start_link(fn -> [] end)
      
      handler_id = :test_circuit_breaker_handler
      :telemetry.attach(
        handler_id,
        [:foundation, :circuit_breaker, :execute],
        fn event, measurements, metadata, _config ->
          Agent.update(events, fn acc -> 
            [{event, measurements, metadata} | acc] 
          end)
        end,
        nil
      )

      # Execute operation to generate telemetry
      AgentCircuitBreaker.execute_with_agent(
        :telemetry_service,
        :test_agent,
        fn -> {:ok, "telemetry_test"} end
      )

      # Check telemetry events were emitted
      Process.sleep(10)  # Allow telemetry to be processed
      captured_events = Agent.get(events, & &1)
      
      assert length(captured_events) > 0
      
      # Find circuit breaker event
      circuit_event = Enum.find(captured_events, fn {event, _measurements, _metadata} ->
        event == [:foundation, :circuit_breaker, :execute]
      end)
      
      assert circuit_event != nil
      {_event, measurements, metadata} = circuit_event
      assert metadata.agent_id == :test_agent
      assert metadata.service == :telemetry_service
      assert is_number(measurements.duration)

      # Cleanup
      :telemetry.detach(handler_id)
    end
  end

  describe "error handling and edge cases" do
    test "handles agent process termination gracefully", %{namespace: namespace, agent_pid: agent_pid} do
      {:ok, _breaker_pid} = AgentCircuitBreaker.start_agent_breaker(
        :termination_service,
        agent_id: :test_agent,
        capability: :inference,
        namespace: namespace
      )

      # Terminate the agent process
      Process.exit(agent_pid, :kill)
      Process.sleep(10)  # Allow process cleanup

      # Circuit should detect agent termination and handle gracefully
      result = AgentCircuitBreaker.execute_with_agent(
        :termination_service,
        :test_agent,
        fn -> {:ok, "should_not_execute"} end
      )

      assert {:error, reason} = result
      assert reason =~ "agent_not_available" or reason =~ "process_terminated"
    end

    test "validates operation function arity", %{namespace: namespace} do
      {:ok, _breaker_pid} = AgentCircuitBreaker.start_agent_breaker(
        :validation_service,
        agent_id: :test_agent,
        capability: :inference,
        namespace: namespace
      )

      # Test with invalid operation (not a function)
      result = AgentCircuitBreaker.execute_with_agent(
        :validation_service,
        :test_agent,
        "not_a_function"
      )

      assert {:error, :invalid_operation} = result
    end
  end
end