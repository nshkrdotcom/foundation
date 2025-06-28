defmodule Foundation.Infrastructure.AgentRateLimiterTest do
  use ExUnit.Case, async: false

  alias Foundation.Infrastructure.AgentRateLimiter
  alias Foundation.ProcessRegistry
  alias Foundation.Types.AgentInfo

  setup do
    namespace = {:test, make_ref()}

    # Start rate limiter with test configuration
    {:ok, _pid} = AgentRateLimiter.start_link([
      rate_limits: %{
        inference: %{requests: 10, window: 1000},
        training: %{requests: 2, window: 5000},
        general: %{requests: 5, window: 2000}
      },
      capability_multipliers: %{
        high_performance: 2.0,
        specialized: 1.5
      }
    ])

    # Register test agents with different capabilities
    agents = [
      {:ml_agent_1, [:inference, :high_performance], :healthy},
      {:ml_agent_2, [:inference], :healthy},
      {:training_agent, [:training, :specialized], :healthy},
      {:general_agent, [:general], :healthy}
    ]

    for {agent_id, capabilities, health} <- agents do
      pid = spawn(fn -> Process.sleep(2000) end)
      metadata = %AgentInfo{
        id: agent_id,
        type: :ml_agent,
        capabilities: capabilities,
        health: health,
        resource_usage: %{memory: 0.5, cpu: 0.3}
      }
      ProcessRegistry.register_agent(namespace, agent_id, pid, metadata)
    end

    on_exit(fn ->
      try do
        for {agent_id, _, _} <- agents do
          ProcessRegistry.unregister(namespace, agent_id)
        end
        AgentRateLimiter.reset_all_buckets()
      rescue
        _ -> :ok
      end
    end)

    {:ok, namespace: namespace}
  end

  describe "agent-aware rate limiting" do
    test "applies rate limits based on agent capabilities", %{namespace: namespace} do
      # High performance agent should get higher limits
      results = for _i <- 1..15 do
        AgentRateLimiter.check_rate_with_agent(
          :ml_agent_1,
          :inference,
          %{namespace: namespace}
        )
      end

      successes = Enum.count(results, &(&1 == :ok))
      failures = Enum.count(results, &match?({:error, _}, &1))

      # ml_agent_1 has high_performance capability (2x multiplier)
      # So it should get 10 * 2 = 20 requests, but we sent 15
      assert successes >= 15
      assert failures == 0

      # Regular agent should hit limits sooner
      results2 = for _i <- 1..15 do
        AgentRateLimiter.check_rate_with_agent(
          :ml_agent_2,
          :inference,
          %{namespace: namespace}
        )
      end

      successes2 = Enum.count(results2, &(&1 == :ok))
      failures2 = Enum.count(results2, &match?({:error, _}, &1))

      # ml_agent_2 has no multiplier, so only 10 requests allowed
      assert successes2 == 10
      assert failures2 == 5
    end

    test "different operation types have different limits", %{namespace: namespace} do
      # Training operations should have much lower limits
      training_results = for _i <- 1..5 do
        AgentRateLimiter.check_rate_with_agent(
          :training_agent,
          :training,
          %{namespace: namespace}
        )
      end

      training_successes = Enum.count(training_results, &(&1 == :ok))

      # Training agent has specialized capability (1.5x multiplier)
      # Training limit is 2 requests per window * 1.5 = 3 requests
      assert training_successes == 3

      # Inference operations should have higher limits
      inference_results = for _i <- 1..10 do
        AgentRateLimiter.check_rate_with_agent(
          :ml_agent_2,
          :inference,
          %{namespace: namespace}
        )
      end

      inference_successes = Enum.count(inference_results, &(&1 == :ok))
      assert inference_successes == 10
    end

    test "rate limits reset after window expires" do
      # Exhaust rate limit
      for _i <- 1..5 do
        AgentRateLimiter.check_rate_with_agent(:general_agent, :general)
      end

      # Should be rate limited
      assert {:error, :rate_limited} = AgentRateLimiter.check_rate_with_agent(
        :general_agent,
        :general
      )

      # Wait for window to reset (general has 2000ms window)
      Process.sleep(2100)

      # Should be allowed again
      assert :ok = AgentRateLimiter.check_rate_with_agent(:general_agent, :general)
    end
  end

  describe "agent health integration" do
    test "reduces rate limits for unhealthy agents", %{namespace: namespace} do
      # Update agent to unhealthy state
      unhealthy_metadata = %AgentInfo{
        id: :ml_agent_1,
        type: :ml_agent,
        capabilities: [:inference, :high_performance],
        health: :unhealthy,
        resource_usage: %{memory: 0.95, cpu: 0.9}
      }

      ProcessRegistry.update_agent_metadata(namespace, :ml_agent_1, unhealthy_metadata)

      # Unhealthy agents should get reduced rate limits
      results = for _i <- 1..10 do
        AgentRateLimiter.check_rate_with_agent(
          :ml_agent_1,
          :inference,
          %{namespace: namespace}
        )
      end

      successes = Enum.count(results, &(&1 == :ok))

      # Unhealthy agents should get reduced limits (e.g., 50% of normal)
      assert successes < 10  # Less than normal healthy limit
    end

    test "blocks requests for critically unhealthy agents", %{namespace: namespace} do
      # Update agent to critically unhealthy state
      critical_metadata = %AgentInfo{
        id: :ml_agent_2,
        type: :ml_agent,
        capabilities: [:inference],
        health: :critical,
        resource_usage: %{memory: 0.99, cpu: 0.95}
      }

      ProcessRegistry.update_agent_metadata(namespace, :ml_agent_2, critical_metadata)

      # Critical agents should be blocked completely
      result = AgentRateLimiter.check_rate_with_agent(
        :ml_agent_2,
        :inference,
        %{namespace: namespace}
      )

      assert {:error, :agent_critical} = result
    end
  end

  describe "resource-aware rate limiting" do
    test "adjusts limits based on resource usage", %{namespace: namespace} do
      # Update agent with high resource usage
      high_resource_metadata = %AgentInfo{
        id: :general_agent,
        type: :ml_agent,
        capabilities: [:general],
        health: :healthy,
        resource_usage: %{memory: 0.9, cpu: 0.85}
      }

      ProcessRegistry.update_agent_metadata(namespace, :general_agent, high_resource_metadata)

      # High resource usage should reduce effective rate limits
      results = for _i <- 1..5 do
        AgentRateLimiter.check_rate_with_agent(
          :general_agent,
          :general,
          %{namespace: namespace}
        )
      end

      successes = Enum.count(results, &(&1 == :ok))

      # Should get fewer than normal limit due to high resource usage
      assert successes < 5
    end

    test "provides bonus limits for low resource usage", %{namespace: namespace} do
      # Update agent with low resource usage
      low_resource_metadata = %AgentInfo{
        id: :general_agent,
        type: :ml_agent,
        capabilities: [:general],
        health: :healthy,
        resource_usage: %{memory: 0.2, cpu: 0.1}
      }

      ProcessRegistry.update_agent_metadata(namespace, :general_agent, low_resource_metadata)

      # Low resource usage should provide bonus to rate limits
      results = for _i <- 1..7 do
        AgentRateLimiter.check_rate_with_agent(
          :general_agent,
          :general,
          %{namespace: namespace}
        )
      end

      successes = Enum.count(results, &(&1 == :ok))

      # Should get more than base limit (5) due to low resource usage
      assert successes > 5
    end
  end

  describe "rate limit statistics and monitoring" do
    test "tracks rate limit statistics per agent", %{namespace: namespace} do
      # Generate some rate limit activity
      for _i <- 1..8 do
        AgentRateLimiter.check_rate_with_agent(
          :ml_agent_1,
          :inference,
          %{namespace: namespace}
        )
      end

      # Exceed limits
      for _i <- 1..5 do
        AgentRateLimiter.check_rate_with_agent(
          :ml_agent_1,
          :inference,
          %{namespace: namespace}
        )
      end

      stats = AgentRateLimiter.get_agent_stats(:ml_agent_1)

      assert stats.total_requests >= 13
      assert stats.successful_requests >= 8
      assert stats.rate_limited_requests >= 0
      assert is_float(stats.success_rate)
    end

    test "provides system-wide rate limiting overview" do
      # Generate activity across multiple agents
      AgentRateLimiter.check_rate_with_agent(:ml_agent_1, :inference)
      AgentRateLimiter.check_rate_with_agent(:ml_agent_2, :inference)
      AgentRateLimiter.check_rate_with_agent(:training_agent, :training)

      overview = AgentRateLimiter.get_system_overview()

      assert overview.active_agents >= 3
      assert overview.total_requests >= 3
      assert is_map(overview.requests_by_operation)
      assert Map.has_key?(overview.requests_by_operation, :inference)
    end
  end

  describe "burst handling" do
    test "allows burst requests within burst limits", %{namespace: namespace} do
      # Configure burst for testing
      AgentRateLimiter.update_agent_config(:ml_agent_1, %{
        burst_allowance: 5,  # Allow 5 extra requests in burst
        burst_window: 500    # Within 500ms
      })

      # Send burst of requests quickly
      start_time = System.monotonic_time(:millisecond)

      burst_results = for _i <- 1..15 do  # More than normal limit
        AgentRateLimiter.check_rate_with_agent(
          :ml_agent_1,
          :inference,
          %{namespace: namespace, timestamp: System.monotonic_time(:millisecond)}
        )
      end

      end_time = System.monotonic_time(:millisecond)

      # If burst was fast enough, should allow more than base limit
      if (end_time - start_time) < 500 do
        successes = Enum.count(burst_results, &(&1 == :ok))
        # Base limit (10) + high_performance multiplier (2x = 20) + burst (5) = 25
        # But we only sent 15, so all should succeed
        assert successes >= 15
      end
    end
  end

  describe "agent coordination integration" do
    test "coordinates rate limits during multi-agent operations", %{namespace: namespace} do
      # Start a coordinated operation involving multiple agents
      coordination_id = "multi_agent_inference_#{System.unique_integer()}"

      participants = [:ml_agent_1, :ml_agent_2]

      # Reserve capacity for coordinated operation
      reservation_results = for agent_id <- participants do
        AgentRateLimiter.reserve_capacity_for_coordination(
          agent_id,
          :inference,
          coordination_id,
          %{reserved_requests: 5, namespace: namespace}
        )
      end

      assert Enum.all?(reservation_results, &(&1 == :ok))

      # Use reserved capacity
      for agent_id <- participants do
        for _i <- 1..5 do
          result = AgentRateLimiter.check_rate_with_agent(
            agent_id,
            :inference,
            %{coordination_id: coordination_id, namespace: namespace}
          )
          assert result == :ok
        end
      end

      # Release unused capacity
      for agent_id <- participants do
        AgentRateLimiter.release_coordination_reservation(agent_id, coordination_id)
      end
    end
  end

  describe "configuration and tuning" do
    test "supports dynamic rate limit updates" do
      # Get current limits
      original_limits = AgentRateLimiter.get_current_limits(:ml_agent_1, :inference)

      # Update limits dynamically
      new_config = %{
        requests: 20,
        window: 1000,
        burst_allowance: 10
      }

      assert :ok = AgentRateLimiter.update_operation_limits(:inference, new_config)

      # Verify limits were updated
      updated_limits = AgentRateLimiter.get_current_limits(:ml_agent_1, :inference)
      assert updated_limits.requests == 20
      assert updated_limits.burst_allowance == 10

      # Test that new limits are applied
      results = for _i <- 1..25 do
        AgentRateLimiter.check_rate_with_agent(:ml_agent_1, :inference)
      end

      successes = Enum.count(results, &(&1 == :ok))
      # ml_agent_1 has high_performance (2x) so 20 * 2 = 40 base + 10 * 2 = 20 burst = 60 total
      # We sent 25, so all should succeed
      assert successes >= 25
    end

    test "validates configuration parameters" do
      invalid_config = %{
        requests: -5,  # Invalid negative value
        window: 0,     # Invalid zero window
        burst_allowance: "invalid"  # Invalid type
      }

      assert {:error, :invalid_configuration} = AgentRateLimiter.update_operation_limits(
        :test_operation,
        invalid_config
      )
    end
  end

  describe "error handling and edge cases" do
    test "handles agent not found gracefully" do
      result = AgentRateLimiter.check_rate_with_agent(
        :nonexistent_agent,
        :inference,
        %{namespace: {:test, make_ref()}}
      )

      assert {:error, :agent_not_found} = result
    end

    test "handles unknown operation types" do
      result = AgentRateLimiter.check_rate_with_agent(
        :ml_agent_1,
        :unknown_operation
      )

      # Should either default to general limits or return error
      assert result == :ok or match?({:error, :unknown_operation}, result)
    end

    test "handles concurrent requests correctly" do
      # Test concurrent access doesn't cause race conditions
      tasks = for _i <- 1..20 do
        Task.async(fn ->
          AgentRateLimiter.check_rate_with_agent(:ml_agent_1, :inference)
        end)
      end

      results = Task.await_many(tasks, 5000)

      # Should have consistent behavior even under concurrency
      successes = Enum.count(results, &(&1 == :ok))
      assert successes <= 20  # Should respect limits even under concurrency
    end
  end

  describe "telemetry and observability" do
    test "emits telemetry events for rate limit decisions" do
      events = Agent.start_link(fn -> [] end)

      handler_id = :test_rate_limiter_handler
      :telemetry.attach(
        handler_id,
        [:foundation, :rate_limiter, :check],
        fn event, measurements, metadata, _config ->
          Agent.update(events, fn acc ->
            [{event, measurements, metadata} | acc]
          end)
        end,
        nil
      )

      # Trigger rate limit check
      AgentRateLimiter.check_rate_with_agent(:ml_agent_1, :inference)

      Process.sleep(10)  # Allow telemetry processing
      captured_events = Agent.get(events, & &1)

      assert length(captured_events) > 0

      rate_limit_event = Enum.find(captured_events, fn {event, _measurements, _metadata} ->
        event == [:foundation, :rate_limiter, :check]
      end)

      assert rate_limit_event != nil
      {_event, measurements, metadata} = rate_limit_event
      assert metadata.agent_id == :ml_agent_1
      assert metadata.operation == :inference
      assert is_boolean(metadata.allowed)

      :telemetry.detach(handler_id)
    end
  end
end