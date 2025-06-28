defmodule Foundation.AgentMetadataPropertiesTest do
  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Foundation.ProcessRegistry
  alias Foundation.Types.AgentInfo
  alias Foundation.Infrastructure.{AgentRateLimiter, ResourceManager}
  alias Foundation.Services.{EventStore, TelemetryService}

  describe "agent metadata properties" do
    property "agent registration maintains metadata consistency under concurrent operations" do
      check all(
        agent_count <- integer(1..20),
        capabilities_list <- list_of(
          list_of(atom(), min_length: 1, max_length: 5),
          min_length: 1,
          max_length: 10
        ),
        health_states <- list_of(member_of([:healthy, :degraded, :unhealthy]))
      ) do
        namespace = {:test, make_ref()}

        # Generate agent configurations
        agents = for i <- 1..agent_count do
          capabilities = Enum.at(capabilities_list, rem(i, length(capabilities_list)))
          health = Enum.at(health_states, rem(i, length(health_states)))
          
          {:"agent_#{i}", capabilities, health}
        end

        # Register all agents concurrently
        registration_tasks = for {agent_id, capabilities, health} <- agents do
          Task.async(fn ->
            pid = spawn(fn -> Process.sleep(1000) end)
            metadata = %AgentInfo{
              id: agent_id,
              type: :agent,
              capabilities: capabilities,
              health: health,
              resource_usage: %{
                memory: :rand.uniform(),
                cpu: :rand.uniform(),
                network: :rand.uniform(100),
                storage: :rand.uniform()
              }
            }

            ProcessRegistry.register_agent(namespace, agent_id, pid, metadata)
          end)
        end

        # Wait for all registrations
        registration_results = Task.await_many(registration_tasks, 5000)
        
        # All registrations should succeed
        assert Enum.all?(registration_results, &(&1 == :ok))

        # Verify all agents can be looked up with correct metadata
        for {agent_id, expected_capabilities, expected_health} <- agents do
          assert {:ok, {_pid, metadata}} = 
            ProcessRegistry.lookup_agent(namespace, agent_id)

          assert metadata.id == agent_id
          assert metadata.capabilities == expected_capabilities
          assert metadata.health == expected_health
          assert metadata.type == :agent
        end

        # Test capability-based queries work correctly
        for capability <- Enum.uniq(List.flatten(capabilities_list)) do
          agents_with_capability = ProcessRegistry.lookup_agents_by_capability(
            namespace, 
            capability
          )

          expected_count = Enum.count(agents, fn {_, caps, _} -> 
            capability in caps 
          end)

          assert length(agents_with_capability) == expected_count
        end

        # Test health-based queries
        for health_state <- Enum.uniq(health_states) do
          agents_with_health = ProcessRegistry.lookup_agents_by_health(
            namespace,
            health_state
          )

          expected_count = Enum.count(agents, fn {_, _, health} ->
            health == health_state
          end)

          assert length(agents_with_health) == expected_count
        end

        # Cleanup
        for {agent_id, _, _} <- agents do
          ProcessRegistry.unregister(namespace, agent_id)
        end
      end
    end

    property "agent metadata updates are atomic and consistent" do
      check all(
        update_count <- integer(1..50),
        health_transitions <- list_of(
          member_of([:healthy, :degraded, :unhealthy, :critical]),
          length: update_count
        ),
        resource_values <- list_of(
          tuple({float(min: 0.0, max: 1.0), float(min: 0.0, max: 1.0)}),
          length: update_count
        )
      ) do
        namespace = {:test, make_ref()}
        agent_id = :property_test_agent

        # Register initial agent
        pid = spawn(fn -> Process.sleep(5000) end)
        initial_metadata = %AgentInfo{
          id: agent_id,
          type: :agent,
          capabilities: [:test],
          health: :healthy,
          resource_usage: %{memory: 0.5, cpu: 0.5}
        }

        ProcessRegistry.register_agent(namespace, agent_id, pid, initial_metadata)

        # Perform concurrent metadata updates
        update_tasks = Enum.zip(health_transitions, resource_values)
        |> Enum.with_index()
        |> Enum.map(fn {{health, {memory, cpu}}, index} ->
          Task.async(fn ->
            updated_metadata = %AgentInfo{
              initial_metadata |
              health: health,
              resource_usage: %{memory: memory, cpu: cpu},
              metadata: %{update_sequence: index}
            }

            ProcessRegistry.update_agent_metadata(namespace, agent_id, updated_metadata)
          end)
        end)

        # Wait for all updates
        update_results = Task.await_many(update_tasks, 5000)
        
        # All updates should succeed
        assert Enum.all?(update_results, &(&1 == :ok))

        # Final state should be consistent
        {:ok, {^pid, final_metadata}} = ProcessRegistry.lookup_agent(namespace, agent_id)
        
        # Should have one of the update values
        assert final_metadata.health in health_transitions
        assert final_metadata.resource_usage.memory >= 0.0
        assert final_metadata.resource_usage.memory <= 1.0
        assert final_metadata.resource_usage.cpu >= 0.0
        assert final_metadata.resource_usage.cpu <= 1.0

        # Cleanup
        ProcessRegistry.unregister(namespace, agent_id)
      end
    end
  end

  describe "agent resource management properties" do
    property "resource allocations never exceed agent limits" do
      check all(
        memory_limit <- integer(1_000_000..10_000_000_000),  # 1MB to 10GB
        cpu_limit <- float(min: 0.1, max: 16.0),
        allocation_requests <- list_of(
          tuple({
            integer(1_000..memory_limit),
            float(min: 0.01, max: cpu_limit)
          }),
          min_length: 1,
          max_length: 50
        )
      ) do
        agent_id = :property_resource_agent

        # Register agent with limits
        ResourceManager.register_agent(agent_id, %{
          memory_limit: memory_limit,
          cpu_limit: cpu_limit
        })

        allocated_memory = 0
        allocated_cpu = 0.0

        # Perform allocations sequentially to track state
        for {memory_request, cpu_request} <- allocation_requests do
          case ResourceManager.allocate_resources(agent_id, %{
            memory: memory_request,
            cpu: cpu_request
          }) do
            :ok ->
              allocated_memory = allocated_memory + memory_request
              allocated_cpu = allocated_cpu + cpu_request
              
              # Verify we haven't exceeded limits
              assert allocated_memory <= memory_limit
              assert allocated_cpu <= cpu_limit
              
            {:error, _} ->
              # Allocation failed, which is expected when limits would be exceeded
              assert allocated_memory + memory_request > memory_limit or 
                     allocated_cpu + cpu_request > cpu_limit
          end
        end

        # Final verification
        {:ok, status} = ResourceManager.get_agent_resource_status(agent_id)
        assert status.current_usage.memory <= memory_limit
        assert status.current_usage.cpu <= cpu_limit

        # Cleanup
        ResourceManager.unregister_agent(agent_id)
      end
    end

    property "resource release operations maintain consistency" do
      check all(
        initial_memory <- integer(1_000_000..1_000_000_000),  # 1MB to 1GB
        initial_cpu <- float(min: 0.1, max: 4.0),
        release_operations <- list_of(
          tuple({
            integer(1_000..initial_memory),
            float(min: 0.01, max: initial_cpu)
          }),
          min_length: 1,
          max_length: 20
        )
      ) do
        agent_id = :property_release_agent

        # Register and allocate initial resources
        ResourceManager.register_agent(agent_id, %{
          memory_limit: initial_memory * 2,
          cpu_limit: initial_cpu * 2
        })

        ResourceManager.allocate_resources(agent_id, %{
          memory: initial_memory,
          cpu: initial_cpu
        })

        current_memory = initial_memory
        current_cpu = initial_cpu

        # Perform release operations
        for {memory_release, cpu_release} <- release_operations do
          case ResourceManager.release_resources(agent_id, %{
            memory: memory_release,
            cpu: cpu_release
          }) do
            :ok ->
              current_memory = max(0, current_memory - memory_release)
              current_cpu = max(0.0, current_cpu - cpu_release)
              
            {:error, _} ->
              # Release failed because we're trying to release more than allocated
              assert memory_release > current_memory or cpu_release > current_cpu
          end

          # Usage should never go negative
          {:ok, status} = ResourceManager.get_agent_resource_status(agent_id)
          assert status.current_usage.memory >= 0
          assert status.current_usage.cpu >= 0.0
        end

        # Cleanup
        ResourceManager.unregister_agent(agent_id)
      end
    end
  end

  describe "agent rate limiting properties" do
    property "rate limits are enforced consistently across agents" do
      check all(
        agent_count <- integer(1..10),
        requests_per_agent <- integer(1..50),
        time_window_ms <- integer(100..2000)
      ) do
        # Configure rate limiter with test limits
        rate_limit = max(1, div(requests_per_agent, 2))  # Set limit to half of requests
        
        AgentRateLimiter.update_operation_limits(:property_test_op, %{
          requests: rate_limit,
          window: time_window_ms
        })

        # Create agents
        agents = for i <- 1..agent_count do
          :"prop_agent_#{i}"
        end

        # Register agents
        for agent_id <- agents do
          namespace = {:test, make_ref()}
          pid = spawn(fn -> Process.sleep(1000) end)
          metadata = %AgentInfo{
            id: agent_id,
            type: :agent,
            capabilities: [:property_test],
            health: :healthy
          }
          ProcessRegistry.register_agent(namespace, agent_id, pid, metadata)
        end

        # Generate requests for each agent
        all_results = for agent_id <- agents do
          results = for _i <- 1..requests_per_agent do
            AgentRateLimiter.check_rate_with_agent(agent_id, :property_test_op)
          end
          {agent_id, results}
        end

        # Verify rate limiting is enforced for each agent
        for {agent_id, results} <- all_results do
          successful_requests = Enum.count(results, &(&1 == :ok))
          failed_requests = Enum.count(results, &match?({:error, :rate_limited}, &1))
          
          # Should have some successful requests
          assert successful_requests > 0
          
          # Should not exceed rate limit significantly
          assert successful_requests <= rate_limit + 2  # Allow small variance
          
          # Total requests should match
          assert successful_requests + failed_requests == requests_per_agent
        end

        # Cleanup
        for agent_id <- agents do
          try do
            AgentRateLimiter.reset_agent_bucket(agent_id)
          rescue
            _ -> :ok
          end
        end
      end
    end
  end

  describe "event correlation properties" do
    property "event correlation maintains referential integrity" do
      check all(
        correlation_id <- string(:alphanumeric, min_length: 5, max_length: 20),
        event_count <- integer(1..20),
        agent_ids <- list_of(atom(), min_length: 1, max_length: 5),
        event_types <- list_of(atom(), min_length: 1, max_length: 10)
      ) do
        # Generate correlated events
        events = for i <- 1..event_count do
          %Foundation.Types.Event{
            id: "event_#{i}_#{:rand.uniform(1000)}",
            type: Enum.random(event_types),
            agent_id: Enum.random(agent_ids),
            data: %{sequence: i, test_data: "property_test"},
            correlation_id: correlation_id,
            timestamp: DateTime.add(DateTime.utc_now(), i, :second)
          }
        end

        # Store all events
        for event <- events do
          EventStore.store_event(event)
        end

        # Retrieve correlated events
        {:ok, retrieved_events} = EventStore.get_correlated_events(correlation_id)

        # Verify correlation integrity
        assert length(retrieved_events) == event_count
        
        # All events should have the same correlation_id
        assert Enum.all?(retrieved_events, &(&1.correlation_id == correlation_id))
        
        # Events should be ordered by timestamp
        timestamps = Enum.map(retrieved_events, & &1.timestamp)
        assert timestamps == Enum.sort(timestamps, DateTime)
        
        # All original event data should be preserved
        retrieved_sequences = retrieved_events
                             |> Enum.map(&(&1.data.sequence))
                             |> Enum.sort()
        
        original_sequences = 1..event_count |> Enum.to_list()
        assert retrieved_sequences == original_sequences
      end
    end
  end

  describe "telemetry aggregation properties" do
    property "metric aggregations are mathematically consistent" do
      check all(
        metric_values <- list_of(float(min: 0.0, max: 1000.0), min_length: 5, max_length: 100),
        agent_ids <- list_of(atom(), min_length: 1, max_length: 5)
      ) do
        metric_name = [:property, :test, :metric]
        
        # Record metrics for random agents
        recorded_values = for value <- metric_values do
          agent_id = Enum.random(agent_ids)
          
          TelemetryService.record_metric(
            metric_name,
            value,
            :gauge,
            %{agent_id: agent_id, property_test: true}
          )
          
          {agent_id, value}
        end

        # Trigger aggregation
        TelemetryService.trigger_aggregation()

        # Get aggregated metrics
        {:ok, aggregated_metrics} = TelemetryService.get_aggregated_metrics(%{
          metric_name: metric_name
        })

        # Verify mathematical consistency
        for metric <- aggregated_metrics do
          agent_values = recorded_values
                        |> Enum.filter(fn {agent_id, _} -> agent_id == metric.agent_id end)
                        |> Enum.map(fn {_, value} -> value end)

          if length(agent_values) > 0 do
            # Verify statistical measures
            expected_min = Enum.min(agent_values)
            expected_max = Enum.max(agent_values)
            expected_avg = Enum.sum(agent_values) / length(agent_values)

            assert_in_delta metric.min_value, expected_min, 0.001
            assert_in_delta metric.max_value, expected_max, 0.001
            assert_in_delta metric.avg_value, expected_avg, 0.001
            assert metric.count == length(agent_values)
          end
        end
      end
    end
  end

  describe "system consistency properties" do
    property "system state remains consistent under random operations" do
      check all(
        operation_count <- integer(10..100),
        operations <- list_of(
          one_of([
            tuple({:register_agent, atom(), list_of(atom(), min_length: 1)}),
            tuple({:update_health, atom(), member_of([:healthy, :degraded, :unhealthy])}),
            tuple({:allocate_resource, atom(), integer(1_000_000..100_000_000)}),
            tuple({:record_metric, atom(), float(min: 0.0, max: 100.0)}),
            tuple({:store_event, atom(), atom()})
          ]),
          length: operation_count
        )
      ) do
        namespace = {:test, make_ref()}
        
        # Track system state
        registered_agents = MapSet.new()
        
        # Execute random operations
        final_agents = Enum.reduce(operations, registered_agents, fn operation, agents ->
          case operation do
            {:register_agent, agent_id, capabilities} ->
              if agent_id not in agents do
                pid = spawn(fn -> Process.sleep(1000) end)
                metadata = %AgentInfo{
                  id: agent_id,
                  type: :agent,
                  capabilities: capabilities,
                  health: :healthy
                }
                
                case ProcessRegistry.register_agent(namespace, agent_id, pid, metadata) do
                  :ok -> MapSet.put(agents, agent_id)
                  _ -> agents
                end
              else
                agents
              end
              
            {:update_health, agent_id, health} ->
              if agent_id in agents do
                {:ok, {_pid, metadata}} = ProcessRegistry.lookup_agent(namespace, agent_id)
                updated_metadata = %{metadata | health: health}
                ProcessRegistry.update_agent_metadata(namespace, agent_id, updated_metadata)
              end
              agents
              
            {:allocate_resource, agent_id, memory} ->
              if agent_id in agents do
                try do
                  # Try to register with ResourceManager if not already
                  ResourceManager.register_agent(agent_id, %{
                    memory_limit: memory * 2
                  })
                  ResourceManager.allocate_resources(agent_id, %{memory: memory})
                rescue
                  _ -> :ok  # Ignore failures for property testing
                end
              end
              agents
              
            {:record_metric, agent_id, value} ->
              if agent_id in agents do
                TelemetryService.record_metric(
                  [:property, :random, :metric],
                  value,
                  :gauge,
                  %{agent_id: agent_id, namespace: namespace}
                )
              end
              agents
              
            {:store_event, agent_id, event_type} ->
              if agent_id in agents do
                event = %Foundation.Types.Event{
                  id: "prop_#{:rand.uniform(10000)}",
                  type: event_type,
                  agent_id: agent_id,
                  data: %{random_operation: true},
                  timestamp: DateTime.utc_now()
                }
                EventStore.store_event(event)
              end
              agents
          end
        end)

        # Verify system consistency
        
        # All registered agents should be discoverable
        for agent_id <- final_agents do
          assert {:ok, {_pid, _metadata}} = ProcessRegistry.lookup_agent(namespace, agent_id)
        end

        # System should provide consistent counts
        {:ok, system_health} = ProcessRegistry.get_system_health_overview(namespace)
        assert system_health.total_agents == MapSet.size(final_agents)

        # Cleanup
        for agent_id <- final_agents do
          ProcessRegistry.unregister(namespace, agent_id)
          try do
            ResourceManager.unregister_agent(agent_id)
          rescue
            _ -> :ok
          end
        end
      end
    end
  end
end