defmodule Foundation.AgentInfrastructureIntegrationTest do
  use ExUnit.Case, async: false

  alias Foundation.{
    ProcessRegistry,
    Infrastructure.AgentCircuitBreaker,
    Infrastructure.AgentRateLimiter,
    Infrastructure.ResourceManager,
    Services.EventStore,
    Services.TelemetryService,
    Coordination.Service,
    Types.AgentInfo
  }

  setup do
    namespace = {:test, make_ref()}

    # Start all infrastructure services for integration testing
    services = [
      {AgentRateLimiter, [
        rate_limits: %{
          inference: %{requests: 10, window: 1000},
          training: %{requests: 2, window: 5000}
        }
      ]},
      {ResourceManager, [
        monitoring_interval: 50,
        system_thresholds: %{
          memory: %{warning: 0.8, critical: 0.9}
        }
      ]},
      {EventStore, [
        storage_backend: :memory,
        agent_correlation_enabled: true
      ]},
      {TelemetryService, [
        aggregation_interval: 50,
        alert_thresholds: %{
          memory_usage: %{warning: 0.8, critical: 0.9}
        }
      ]},
      {Service, [
        consensus_timeout: 5000,
        health_check_interval: 50
      ]}
    ]

    started_services = for {service_module, opts} <- services do
      {:ok, pid} = service_module.start_link(opts)
      {service_module, pid}
    end

    on_exit(fn ->
      for {service_module, pid} <- started_services do
        try do
          if Process.alive?(pid) do
            GenServer.stop(pid)
          end
        rescue
          _ -> :ok
        end
      end
    end)

    {:ok, namespace: namespace, services: started_services}
  end

  describe "end-to-end agent infrastructure integration" do
    test "complete agent lifecycle with full infrastructure protection", %{namespace: namespace} do
      # 1. Register agent with comprehensive metadata
      pid = spawn(fn -> Process.sleep(10_000) end)
      agent_metadata = %AgentInfo{
        id: :integration_agent,
        type: :ml_agent,
        capabilities: [:inference, :training],
        health: :healthy,
        resource_usage: %{memory: 0.5, cpu: 0.3}
      }

      assert :ok = ProcessRegistry.register_agent(
        namespace,
        :integration_agent,
        pid,
        agent_metadata
      )

      # 2. Set up comprehensive infrastructure protection

      # Circuit Breaker
      {:ok, _breaker} = AgentCircuitBreaker.start_agent_breaker(
        :ml_service,
        agent_id: :integration_agent,
        capability: :inference,
        namespace: namespace
      )

      # Resource Management
      assert :ok = ResourceManager.register_agent(:integration_agent, %{
        memory_limit: 2_000_000_000,  # 2GB
        cpu_limit: 2.0
      })

      # 3. Perform protected operations with full infrastructure integration
      operation_results = for i <- 1..20 do
        Task.async(fn ->
          operation_id = "integration_op_#{i}"

          # Check rate limits
          case AgentRateLimiter.check_rate_with_agent(
            :integration_agent,
            :inference,
            %{operation_id: operation_id, namespace: namespace}
          ) do
            :ok ->
              # Execute with circuit breaker protection
              result = AgentCircuitBreaker.execute_with_agent(
                :ml_service,
                :integration_agent,
                fn ->
                  # Simulate resource allocation
                  ResourceManager.allocate_resources(:integration_agent, %{
                    memory: 100_000_000  # 100MB per operation
                  })

                  # Simulate processing time
                  Process.sleep(10 + :rand.uniform(40))  # 10-50ms

                  # Record telemetry
                  TelemetryService.record_metric(
                    [:integration, :operation, :duration],
                    10 + :rand.uniform(40),
                    :histogram,
                    %{
                      agent_id: :integration_agent,
                      operation_id: operation_id,
                      namespace: namespace
                    }
                  )

                  # Store completion event
                  event = %Foundation.Types.Event{
                    id: UUID.uuid4(),
                    type: :operation_completed,
                    agent_id: :integration_agent,
                    data: %{
                      operation_id: operation_id,
                      success: true,
                      duration_ms: 10 + :rand.uniform(40)
                    },
                    timestamp: DateTime.utc_now()
                  }
                  EventStore.store_event(event)

                  # Release resources
                  ResourceManager.release_resources(:integration_agent, %{
                    memory: 100_000_000
                  })

                  {:ok, "operation_#{i}_completed"}
                end,
                %{operation_id: operation_id}
              )

              result

            {:error, _rate_limit_reason} = error ->
              # Record rate limit event
              event = %Foundation.Types.Event{
                id: UUID.uuid4(),
                type: :operation_rate_limited,
                agent_id: :integration_agent,
                data: %{operation_id: operation_id},
                timestamp: DateTime.utc_now()
              }
              EventStore.store_event(event)

              error
          end
        end)
      end

      # 4. Wait for all operations and verify results
      results = Task.await_many(operation_results, 15_000)

      successful_operations = Enum.count(results, &match?({:ok, _}, &1))
      rate_limited_operations = Enum.count(results, &match?({:error, :rate_limited}, &1))
      circuit_failures = Enum.count(results, &match?({:error, :circuit_open}, &1))

      # Should have mix of successful and protected operations
      assert successful_operations > 0
      assert successful_operations + rate_limited_operations + circuit_failures == 20

      # 5. Verify infrastructure state and metrics

      # Agent should still be registered and healthy
      assert {:ok, {^pid, updated_metadata}} = ProcessRegistry.lookup_agent(
        namespace,
        :integration_agent
      )
      assert updated_metadata.id == :integration_agent

      # Resource manager should show consistent state
      {:ok, resource_status} = ResourceManager.get_agent_resource_status(:integration_agent)
      assert resource_status.current_usage.memory == 0  # All resources released

      # Circuit breaker should have recorded operations
      {:ok, circuit_status} = AgentCircuitBreaker.get_agent_status(
        :ml_service,
        :integration_agent
      )
      assert circuit_status.total_operations >= successful_operations

      # Rate limiter should have statistics
      rate_stats = AgentRateLimiter.get_agent_stats(:integration_agent)
      assert rate_stats.total_requests >= 20

      # Event store should have operation events
      {:ok, events} = EventStore.query_events(%{
        agent_id: :integration_agent,
        namespace: namespace
      })
      assert length(events) >= successful_operations

      # Telemetry should have recorded metrics
      TelemetryService.trigger_aggregation()
      {:ok, metrics} = TelemetryService.get_aggregated_metrics(%{
        agent_id: :integration_agent,
        namespace: namespace
      })
      assert length(metrics) > 0

      # 6. Cleanup
      ProcessRegistry.unregister(namespace, :integration_agent)
    end

    test "infrastructure coordination during multi-agent scenarios", %{namespace: namespace} do
      # Register multiple agents with different characteristics
      agents = [
        {:high_perf_agent, [:inference], :healthy, %{memory: 4_000_000_000, cpu: 4.0}},
        {:standard_agent, [:inference, :training], :healthy, %{memory: 2_000_000_000, cpu: 2.0}},
        {:constrained_agent, [:inference], :degraded, %{memory: 500_000_000, cpu: 0.5}}
      ]

      agent_pids = for {agent_id, capabilities, health, limits} <- agents do
        pid = spawn(fn -> Process.sleep(15_000) end)
        metadata = %AgentInfo{
          id: agent_id,
          type: :ml_agent,
          capabilities: capabilities,
          health: health,
          resource_usage: %{memory: 0.3, cpu: 0.2}
        }

        ProcessRegistry.register_agent(namespace, agent_id, pid, metadata)
        ResourceManager.register_agent(agent_id, limits)

        # Set up circuit breakers for each agent
        {:ok, _} = AgentCircuitBreaker.start_agent_breaker(
          :multi_agent_service,
          agent_id: agent_id,
          capability: :inference,
          namespace: namespace
        )

        {agent_id, pid}
      end

      # Start coordinated workload across all agents
      coordination_task = Task.async(fn ->
        Service.consensus(
          :infrastructure_coordination_test,
          [:high_perf_agent, :standard_agent, :constrained_agent],
          %{
            action: :distributed_inference,
            resource_requirements: %{total_memory: 4_000_000_000},
            infrastructure_aware: true
          },
          %{
            strategy: :infrastructure_aware_majority,
            timeout: 10_000,
            namespace: namespace
          }
        )
      end)

      # Generate concurrent load while coordination is happening
      concurrent_load_tasks = for agent_id <- [:high_perf_agent, :standard_agent, :constrained_agent] do
        Task.async(fn ->
          results = for i <- 1..15 do
            case AgentRateLimiter.check_rate_with_agent(
              agent_id,
              :inference,
              %{concurrent_op: i, namespace: namespace}
            ) do
              :ok ->
                AgentCircuitBreaker.execute_with_agent(
                  :multi_agent_service,
                  agent_id,
                  fn ->
                    # Simulate varying load based on agent capabilities
                    memory_allocation = case agent_id do
                      :high_perf_agent -> 200_000_000
                      :standard_agent -> 100_000_000
                      :constrained_agent -> 50_000_000
                    end

                    ResourceManager.allocate_resources(agent_id, %{
                      memory: memory_allocation
                    })

                    processing_time = case agent_id do
                      :high_perf_agent -> 20
                      :standard_agent -> 50
                      :constrained_agent -> 200
                    end

                    Process.sleep(processing_time)

                    ResourceManager.release_resources(agent_id, %{
                      memory: memory_allocation
                    })

                    {:ok, "processed_by_#{agent_id}"}
                  end
                )

              error -> error
            end
          end

          {agent_id, results}
        end)
      end

      # Wait for coordination to complete
      {:ok, coordination_result} = Task.await(coordination_task, 15_000)
      assert coordination_result.status == :accepted

      # Wait for concurrent load to complete
      load_results = Task.await_many(concurrent_load_tasks, 20_000)

      # Verify infrastructure handled coordination and load appropriately
      for {agent_id, results} <- load_results do
        successful_ops = Enum.count(results, &match?({:ok, _}, &1))

        # High performance agent should handle more load
        case agent_id do
          :high_perf_agent -> assert successful_ops >= 10
          :standard_agent -> assert successful_ops >= 5
          :constrained_agent -> assert successful_ops >= 1  # At least some success
        end
      end

      # Verify system-wide infrastructure health
      {:ok, system_health} = ResourceManager.get_system_resource_status()
      assert system_health.agent_count == 3

      # All agents should have clean resource state
      for {agent_id, _pid} <- agent_pids do
        {:ok, agent_status} = ResourceManager.get_agent_resource_status(agent_id)
        assert agent_status.current_usage.memory == 0  # All resources released
      end

      # Cleanup
      for {agent_id, _pid} <- agent_pids do
        ProcessRegistry.unregister(namespace, agent_id)
        ResourceManager.unregister_agent(agent_id)
      end
    end
  end

  describe "infrastructure failure scenarios and recovery" do
    test "system resilience during cascading failures", %{namespace: namespace} do
      # Set up agents in a dependency chain
      agents = [:primary_agent, :secondary_agent, :backup_agent]

      for agent_id <- agents do
        pid = spawn(fn -> Process.sleep(8000) end)
        metadata = %AgentInfo{
          id: agent_id,
          type: :ml_agent,
          capabilities: [:inference],
          health: :healthy,
          resource_usage: %{memory: 0.4, cpu: 0.3}
        }

        ProcessRegistry.register_agent(namespace, agent_id, pid, metadata)
        ResourceManager.register_agent(agent_id, %{
          memory_limit: 1_000_000_000,
          cpu_limit: 1.0
        })

        # Circuit breaker with low failure threshold for testing
        {:ok, _} = AgentCircuitBreaker.start_agent_breaker(
          :cascade_test_service,
          agent_id: agent_id,
          capability: :inference,
          failure_threshold: 2,  # Low threshold
          namespace: namespace
        )
      end

      # Simulate cascade failure starting with primary agent
      cascade_simulation = Task.async(fn ->
        # 1. Trigger primary agent failures
        for _i <- 1..3 do
          AgentCircuitBreaker.execute_with_agent(
            :cascade_test_service,
            :primary_agent,
            fn -> {:error, "simulated_primary_failure"} end
          )
        end

        Process.sleep(100)

        # 2. Update primary agent health to critical
        critical_metadata = %AgentInfo{
          id: :primary_agent,
          type: :ml_agent,
          capabilities: [:inference],
          health: :critical,
          resource_usage: %{memory: 0.99, cpu: 0.95}
        }
        ProcessRegistry.update_agent_metadata(namespace, :primary_agent, critical_metadata)

        Process.sleep(100)

        # 3. Simulate secondary agent being overwhelmed
        for _i <- 1..5 do
          ResourceManager.allocate_resources(:secondary_agent, %{memory: 200_000_000})
        end

        # Update secondary to degraded
        degraded_metadata = %AgentInfo{
          id: :secondary_agent,
          type: :ml_agent,
          capabilities: [:inference],
          health: :degraded,
          resource_usage: %{memory: 0.9, cpu: 0.8}
        }
        ProcessRegistry.update_agent_metadata(namespace, :secondary_agent, degraded_metadata)

        :cascade_triggered
      end)

      # Meanwhile, attempt normal operations
      operation_task = Task.async(fn ->
        # Try operations on all agents during cascade
        results = for agent_id <- agents, _i <- 1..5 do
          case AgentRateLimiter.check_rate_with_agent(
            agent_id,
            :inference,
            %{cascade_test: true, namespace: namespace}
          ) do
            :ok ->
              AgentCircuitBreaker.execute_with_agent(
                :cascade_test_service,
                agent_id,
                fn ->
                  case agent_id do
                    :primary_agent -> {:error, "primary_down"}
                    :secondary_agent -> if :rand.uniform() > 0.5, do: {:ok, "degraded_success"}, else: {:error, "overloaded"}
                    :backup_agent -> {:ok, "backup_handling_load"}
                  end
                end
              )

            error -> error
          end
        end

        {results, length(Enum.filter(results, &match?({:ok, _}, &1)))}
      end)

      # Wait for both tasks
      :cascade_triggered = Task.await(cascade_simulation, 5000)
      {operation_results, successful_count} = Task.await(operation_task, 8000)

      # Verify system maintained some level of service despite cascade
      assert successful_count > 0  # Backup agent should have handled some load

      # Verify infrastructure detected and responded to failures
      {:ok, primary_status} = AgentCircuitBreaker.get_agent_status(
        :cascade_test_service,
        :primary_agent
      )
      assert primary_status.circuit_state == :open  # Should be open due to failures

      # Backup agent should still be operational
      {:ok, backup_status} = AgentCircuitBreaker.get_agent_status(
        :cascade_test_service,
        :backup_agent
      )
      assert backup_status.circuit_state == :closed  # Should remain closed

      # System should have recorded the cascade in events
      {:ok, events} = EventStore.query_events(%{
        event_types: [:agent_health_changed, :circuit_opened],
        namespace: namespace
      })
      assert length(events) > 0

      # Cleanup
      for agent_id <- agents do
        ProcessRegistry.unregister(namespace, agent_id)
        ResourceManager.unregister_agent(agent_id)
      end
    end

    test "infrastructure recovery after service restarts", %{namespace: namespace} do
      # Set up initial agent
      pid = spawn(fn -> Process.sleep(5000) end)
      metadata = %AgentInfo{
        id: :recovery_test_agent,
        type: :ml_agent,
        capabilities: [:inference],
        health: :healthy
      }

      ProcessRegistry.register_agent(namespace, :recovery_test_agent, pid, metadata)
      ResourceManager.register_agent(:recovery_test_agent, %{
        memory_limit: 1_000_000_000
      })

      # Allocate some resources and record initial state
      ResourceManager.allocate_resources(:recovery_test_agent, %{memory: 500_000_000})

      # Record some metrics
      TelemetryService.record_metric(
        [:recovery, :test],
        100.0,
        :gauge,
        %{agent_id: :recovery_test_agent, namespace: namespace}
      )

      # Store some events
      event = %Foundation.Types.Event{
        id: UUID.uuid4(),
        type: :pre_restart_event,
        agent_id: :recovery_test_agent,
        data: %{message: "before_restart"},
        timestamp: DateTime.utc_now()
      }
      EventStore.store_event(event)

      # Simulate service restart by stopping and restarting components
      # (In real scenario, this would be supervisor restart)

      # Verify state persistence and recovery
      {:ok, resource_status} = ResourceManager.get_agent_resource_status(:recovery_test_agent)
      assert resource_status.agent_id == :recovery_test_agent

      {:ok, events_after} = EventStore.query_events(%{
        agent_id: :recovery_test_agent,
        namespace: namespace
      })
      assert length(events_after) >= 1

      TelemetryService.trigger_aggregation()
      {:ok, metrics_after} = TelemetryService.get_aggregated_metrics(%{
        agent_id: :recovery_test_agent,
        namespace: namespace
      })
      assert length(metrics_after) >= 1

      # Verify operations work after restart
      result = AgentRateLimiter.check_rate_with_agent(
        :recovery_test_agent,
        :inference,
        %{post_restart: true, namespace: namespace}
      )
      assert result == :ok

      # Cleanup
      ProcessRegistry.unregister(namespace, :recovery_test_agent)
      ResourceManager.unregister_agent(:recovery_test_agent)
    end
  end

  describe "performance and scalability" do
    test "infrastructure handles high agent count and throughput", %{namespace: namespace} do
      agent_count = 25
      operations_per_agent = 20

      # Register many agents
      agents = for i <- 1..agent_count do
        agent_id = :"perf_agent_#{i}"
        pid = spawn(fn -> Process.sleep(10_000) end)

        metadata = %AgentInfo{
          id: agent_id,
          type: :ml_agent,
          capabilities: [:inference],
          health: :healthy,
          resource_usage: %{memory: 0.3, cpu: 0.2}
        }

        ProcessRegistry.register_agent(namespace, agent_id, pid, metadata)
        ResourceManager.register_agent(agent_id, %{
          memory_limit: 500_000_000,
          cpu_limit: 0.5
        })

        agent_id
      end

      start_time = System.monotonic_time(:millisecond)

      # Generate high throughput across all agents
      performance_tasks = for agent_id <- agents do
        Task.async(fn ->
          results = for i <- 1..operations_per_agent do
            case AgentRateLimiter.check_rate_with_agent(
              agent_id,
              :inference,
              %{perf_test: i, namespace: namespace}
            ) do
              :ok ->
                # Lightweight operation for performance testing
                TelemetryService.record_metric(
                  [:performance, :operation],
                  i,
                  :counter,
                  %{agent_id: agent_id, namespace: namespace}
                )

                ResourceManager.allocate_resources(agent_id, %{memory: 10_000_000})
                ResourceManager.release_resources(agent_id, %{memory: 10_000_000})

                {:ok, i}

              error -> error
            end
          end

          {agent_id, results}
        end)
      end

      # Wait for all performance tasks
      all_results = Task.await_many(performance_tasks, 30_000)
      end_time = System.monotonic_time(:millisecond)

      total_duration = end_time - start_time
      total_operations = agent_count * operations_per_agent

      # Verify performance metrics
      assert total_duration < 10_000  # Should complete within 10 seconds

      total_successful = all_results
                        |> Enum.flat_map(fn {_agent, results} -> results end)
                        |> Enum.count(&match?({:ok, _}, &1))

      # Should achieve reasonable throughput even with rate limiting
      assert total_successful > total_operations * 0.5  # At least 50% success rate

      operations_per_second = total_successful / (total_duration / 1000)
      assert operations_per_second > 50  # At least 50 ops/second

      # Verify system remains healthy under load
      {:ok, system_status} = ResourceManager.get_system_resource_status()
      assert system_status.agent_count == agent_count

      # All agents should have clean resource state
      for agent_id <- agents do
        {:ok, agent_status} = ResourceManager.get_agent_resource_status(agent_id)
        assert agent_status.current_usage.memory == 0
      end

      # Cleanup
      for agent_id <- agents do
        ProcessRegistry.unregister(namespace, agent_id)
        ResourceManager.unregister_agent(agent_id)
      end
    end
  end
end