defmodule Foundation.Services.AgentEventStoreTest do
  use ExUnit.Case, async: false

  alias Foundation.Services.EventStore
  alias Foundation.Types.Event
  alias Foundation.Types.AgentInfo
  alias Foundation.ProcessRegistry

  setup do
    namespace = {:test, make_ref()}
    
    # Start EventStore with test configuration
    {:ok, _pid} = EventStore.start_link([
      storage_backend: :memory,  # Use memory for testing
      agent_correlation_enabled: true,
      real_time_subscriptions: true,
      namespace: namespace
    ])

    # Register test agents
    agents = [
      {:ml_agent_1, [:inference, :classification], :healthy},
      {:ml_agent_2, [:training, :inference], :healthy},
      {:coord_agent, [:coordination], :healthy}
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
        EventStore.clear_all_events()
        for {agent_id, _, _} <- agents do
          ProcessRegistry.unregister(namespace, agent_id)
        end
      rescue
        _ -> :ok
      end
    end)

    {:ok, namespace: namespace}
  end

  describe "agent event correlation" do
    test "stores events with comprehensive agent context", %{namespace: namespace} do
      event_data = %Event{
        id: UUID.uuid4(),
        type: :agent_health_changed,
        agent_id: :ml_agent_1,
        data: %{
          old_health: :healthy,
          new_health: :degraded,
          reason: "high_memory_usage",
          resource_usage: %{memory: 0.95, cpu: 0.8}
        },
        correlation_id: "health-check-123",
        timestamp: DateTime.utc_now(),
        metadata: %{
          severity: :warning,
          automatic: true,
          source: "resource_monitor"
        }
      }

      assert :ok = EventStore.store_event(event_data)

      # Query events by agent
      {:ok, agent_events} = EventStore.query_events(%{
        agent_id: :ml_agent_1,
        namespace: namespace
      })

      assert length(agent_events) == 1
      event = hd(agent_events)
      assert event.agent_id == :ml_agent_1
      assert event.type == :agent_health_changed
      assert event.correlation_id == "health-check-123"
      assert event.data.old_health == :healthy
      assert event.metadata.severity == :warning
    end

    test "enriches events with agent metadata on storage", %{namespace: namespace} do
      # Store event without full agent context
      basic_event = %Event{
        id: UUID.uuid4(),
        type: :task_completed,
        agent_id: :ml_agent_1,
        data: %{task_id: "inference_001", duration_ms: 250}
      }

      EventStore.store_event(basic_event)

      # Retrieved event should be enriched with agent metadata
      {:ok, [enriched_event]} = EventStore.query_events(%{
        agent_id: :ml_agent_1,
        namespace: namespace
      })

      assert enriched_event.agent_context != nil
      assert enriched_event.agent_context.capabilities == [:inference, :classification]
      assert enriched_event.agent_context.health == :healthy
      assert enriched_event.agent_context.type == :ml_agent
    end

    test "handles events for unknown agents gracefully" do
      unknown_agent_event = %Event{
        id: UUID.uuid4(),
        type: :unknown_agent_activity,
        agent_id: :nonexistent_agent,
        data: %{activity: "mysterious_operation"}
      }

      # Should store event even if agent is unknown
      assert :ok = EventStore.store_event(unknown_agent_event)

      {:ok, [stored_event]} = EventStore.query_events(%{agent_id: :nonexistent_agent})
      assert stored_event.agent_id == :nonexistent_agent
      assert stored_event.agent_context == nil  # No context for unknown agent
    end
  end

  describe "real-time event subscriptions with agent filtering" do
    test "subscribes to agent-specific events", %{namespace: namespace} do
      # Subscribe to health events for specific agent
      {:ok, subscription_id} = EventStore.subscribe_to_events(%{
        agent_id: :ml_agent_1,
        event_types: [:agent_health_changed],
        namespace: namespace
      })

      # Store relevant event
      health_event = %Event{
        id: UUID.uuid4(),
        type: :agent_health_changed,
        agent_id: :ml_agent_1,
        data: %{old_health: :healthy, new_health: :degraded}
      }

      EventStore.store_event(health_event)

      # Should receive notification
      assert_receive {:event_notification, ^subscription_id, event}, 1000
      assert event.agent_id == :ml_agent_1
      assert event.type == :agent_health_changed

      # Store event for different agent - should not receive notification
      other_agent_event = %Event{
        id: UUID.uuid4(),
        type: :agent_health_changed,
        agent_id: :ml_agent_2,
        data: %{old_health: :healthy, new_health: :degraded}
      }

      EventStore.store_event(other_agent_event)

      # Should not receive notification for other agent
      refute_receive {:event_notification, ^subscription_id, _}, 500
    end

    test "subscribes to events by capability", %{namespace: namespace} do
      # Subscribe to all inference-related events
      {:ok, subscription_id} = EventStore.subscribe_to_events(%{
        agent_capabilities: [:inference],
        event_types: [:task_completed],
        namespace: namespace
      })

      # Store event from agent with inference capability
      inference_event = %Event{
        id: UUID.uuid4(),
        type: :task_completed,
        agent_id: :ml_agent_1,  # Has inference capability
        data: %{task_type: :text_classification}
      }

      EventStore.store_event(inference_event)

      # Should receive notification
      assert_receive {:event_notification, ^subscription_id, event}, 1000
      assert event.agent_id == :ml_agent_1

      # Store event from agent without inference capability
      coord_event = %Event{
        id: UUID.uuid4(),
        type: :task_completed,
        agent_id: :coord_agent,  # Only has coordination capability
        data: %{task_type: :consensus_reached}
      }

      EventStore.store_event(coord_event)

      # Should not receive notification
      refute_receive {:event_notification, ^subscription_id, _}, 500
    end

    test "filters events by multiple criteria", %{namespace: namespace} do
      # Complex subscription with multiple filters
      {:ok, subscription_id} = EventStore.subscribe_to_events(%{
        agent_id: :ml_agent_2,
        event_types: [:task_started, :task_completed],
        metadata_filters: %{priority: :high},
        namespace: namespace
      })

      # Event that matches all criteria
      matching_event = %Event{
        id: UUID.uuid4(),
        type: :task_started,
        agent_id: :ml_agent_2,
        data: %{task_id: "training_001"},
        metadata: %{priority: :high, estimated_duration: 3600}
      }

      EventStore.store_event(matching_event)
      assert_receive {:event_notification, ^subscription_id, _}, 1000

      # Event that doesn't match metadata filter
      non_matching_event = %Event{
        id: UUID.uuid4(),
        type: :task_started,
        agent_id: :ml_agent_2,
        data: %{task_id: "training_002"},
        metadata: %{priority: :low}  # Doesn't match filter
      }

      EventStore.store_event(non_matching_event)
      refute_receive {:event_notification, ^subscription_id, _}, 500
    end
  end

  describe "correlated event tracking across agents" do
    test "tracks multi-agent coordination workflows", %{namespace: namespace} do
      correlation_id = "coordination-session-#{System.unique_integer()}"

      # Sequence of events in a coordination workflow
      coordination_events = [
        %Event{
          id: UUID.uuid4(),
          type: :consensus_started,
          agent_id: :coord_agent,
          data: %{
            participants: [:ml_agent_1, :ml_agent_2],
            proposal: %{action: :model_selection, models: ["gpt-4", "claude-3"]}
          },
          correlation_id: correlation_id,
          timestamp: DateTime.utc_now()
        },
        %Event{
          id: UUID.uuid4(),
          type: :consensus_vote,
          agent_id: :ml_agent_1,
          data: %{vote: :accept, reasoning: "good accuracy metrics"},
          correlation_id: correlation_id,
          timestamp: DateTime.add(DateTime.utc_now(), 1, :second)
        },
        %Event{
          id: UUID.uuid4(),
          type: :consensus_vote,
          agent_id: :ml_agent_2,
          data: %{vote: :accept, reasoning: "cost effective"},
          correlation_id: correlation_id,
          timestamp: DateTime.add(DateTime.utc_now(), 2, :second)
        },
        %Event{
          id: UUID.uuid4(),
          type: :consensus_completed,
          agent_id: :coord_agent,
          data: %{
            result: :accepted,
            selected_model: "gpt-4",
            unanimous: true
          },
          correlation_id: correlation_id,
          timestamp: DateTime.add(DateTime.utc_now(), 3, :second)
        }
      ]

      # Store all events
      for event <- coordination_events do
        EventStore.store_event(event)
      end

      # Query correlated events
      {:ok, correlated_events} = EventStore.get_correlated_events(correlation_id)

      assert length(correlated_events) == 4
      assert Enum.all?(correlated_events, &(&1.correlation_id == correlation_id))

      # Events should be ordered by timestamp
      timestamps = Enum.map(correlated_events, & &1.timestamp)
      assert timestamps == Enum.sort(timestamps, DateTime)

      # Verify workflow progression
      [start_event, vote1, vote2, completion] = correlated_events
      assert start_event.type == :consensus_started
      assert vote1.type == :consensus_vote
      assert vote2.type == :consensus_vote
      assert completion.type == :consensus_completed
    end

    test "provides correlation analytics", %{namespace: namespace} do
      correlation_id = "analytics-test-#{System.unique_integer()}"

      # Create events with timing and agent participation data
      events = [
        %Event{
          type: :workflow_started, agent_id: :coord_agent,
          correlation_id: correlation_id,
          timestamp: ~U[2024-01-01 10:00:00Z]
        },
        %Event{
          type: :task_assigned, agent_id: :ml_agent_1,
          correlation_id: correlation_id,
          timestamp: ~U[2024-01-01 10:00:05Z]
        },
        %Event{
          type: :task_completed, agent_id: :ml_agent_1,
          correlation_id: correlation_id,
          timestamp: ~U[2024-01-01 10:02:30Z],
          data: %{duration_ms: 145_000}
        },
        %Event{
          type: :workflow_completed, agent_id: :coord_agent,
          correlation_id: correlation_id,
          timestamp: ~U[2024-01-01 10:03:00Z]
        }
      ]

      for event <- events do
        EventStore.store_event(event)
      end

      # Get correlation analytics
      {:ok, analytics} = EventStore.get_correlation_analytics(correlation_id)

      assert analytics.total_events == 4
      assert analytics.participating_agents == [:coord_agent, :ml_agent_1]
      assert analytics.duration_seconds == 180  # 3 minutes
      assert analytics.event_types == [:workflow_started, :task_assigned, :task_completed, :workflow_completed]
    end
  end

  describe "agent performance event tracking" do
    test "tracks agent performance metrics over time", %{namespace: namespace} do
      agent_id = :ml_agent_1
      
      # Generate performance events over time
      performance_events = for i <- 1..10 do
        %Event{
          id: UUID.uuid4(),
          type: :performance_metric,
          agent_id: agent_id,
          data: %{
            metric_type: :inference_latency,
            value: 100 + i * 10,  # Increasing latency over time
            unit: :milliseconds
          },
          timestamp: DateTime.add(DateTime.utc_now(), i, :second)
        }
      end

      for event <- performance_events do
        EventStore.store_event(event)
      end

      # Query performance timeline
      {:ok, timeline} = EventStore.get_agent_performance_timeline(
        agent_id,
        :inference_latency,
        DateTime.add(DateTime.utc_now(), -60, :second),
        DateTime.add(DateTime.utc_now(), 60, :second)
      )

      assert length(timeline) == 10
      
      # Verify performance trend analysis
      values = Enum.map(timeline, &(&1.data.value))
      assert values == Enum.sort(values)  # Should be increasing
      
      # Should include trend analysis
      assert timeline |> hd() |> Map.has_key?(:trend_analysis)
    end

    test "aggregates performance metrics by time windows", %{namespace: namespace} do
      agent_id = :ml_agent_2
      
      # Generate many performance events
      base_time = DateTime.utc_now()
      
      events = for i <- 1..100 do
        %Event{
          id: UUID.uuid4(),
          type: :performance_metric,
          agent_id: agent_id,
          data: %{
            metric_type: :task_throughput,
            value: :rand.uniform(50) + 25,  # Random 25-75 tasks/minute
            unit: :tasks_per_minute
          },
          timestamp: DateTime.add(base_time, i * 30, :second)  # Every 30 seconds
        }
      end

      for event <- events do
        EventStore.store_event(event)
      end

      # Get hourly aggregation
      {:ok, aggregated} = EventStore.get_agent_metrics_aggregation(
        agent_id,
        :task_throughput,
        :hourly,
        DateTime.add(base_time, -3600, :second),
        DateTime.add(base_time, 3600, :second)
      )

      assert length(aggregated) > 0
      
      first_window = hd(aggregated)
      assert Map.has_key?(first_window, :avg_value)
      assert Map.has_key?(first_window, :min_value)
      assert Map.has_key?(first_window, :max_value)
      assert Map.has_key?(first_window, :count)
      assert first_window.metric_type == :task_throughput
    end
  end

  describe "agent event streaming and real-time processing" do
    test "streams events in real-time for agent monitoring", %{namespace: namespace} do
      # Start event stream for specific agent
      {:ok, stream_pid} = EventStore.start_agent_event_stream(:ml_agent_1, %{
        buffer_size: 10,
        flush_interval: 100,
        namespace: namespace
      })

      # Collect streamed events
      events_received = Agent.start_link(fn -> [] end)
      
      # Register stream handler
      EventStore.register_stream_handler(stream_pid, fn event ->
        Agent.update(events_received, fn acc -> [event | acc] end)
      end)

      # Generate events rapidly
      events = for i <- 1..5 do
        event = %Event{
          id: UUID.uuid4(),
          type: :rapid_event,
          agent_id: :ml_agent_1,
          data: %{sequence: i},
          timestamp: DateTime.utc_now()
        }
        
        EventStore.store_event(event)
        event
      end

      # Wait for stream processing
      Process.sleep(200)

      # Verify events were streamed
      received = Agent.get(events_received, & &1)
      assert length(received) == 5
      
      # Events should maintain order
      sequences = received |> Enum.reverse() |> Enum.map(&(&1.data.sequence))
      assert sequences == [1, 2, 3, 4, 5]
    end

    test "provides event stream backpressure handling", %{namespace: namespace} do
      # Start stream with small buffer to test backpressure
      {:ok, stream_pid} = EventStore.start_agent_event_stream(:ml_agent_2, %{
        buffer_size: 3,
        backpressure_strategy: :drop_oldest,
        namespace: namespace
      })

      events_received = Agent.start_link(fn -> [] end)
      
      EventStore.register_stream_handler(stream_pid, fn event ->
        # Slow handler to trigger backpressure
        Process.sleep(50)
        Agent.update(events_received, fn acc -> [event | acc] end)
      end)

      # Generate more events than buffer can handle quickly
      for i <- 1..10 do
        event = %Event{
          id: UUID.uuid4(),
          type: :backpressure_test,
          agent_id: :ml_agent_2,
          data: %{sequence: i},
          timestamp: DateTime.utc_now()
        }
        
        EventStore.store_event(event)
        Process.sleep(10)  # Small delay between events
      end

      # Wait for processing
      Process.sleep(800)

      # Should have received some events but not necessarily all due to backpressure
      received = Agent.get(events_received, & &1)
      assert length(received) > 0
      assert length(received) <= 10  # Some may have been dropped
    end
  end

  describe "event store maintenance and optimization" do
    test "performs automatic event archival based on age", %{namespace: namespace} do
      # Create old events that should be archived
      old_time = DateTime.add(DateTime.utc_now(), -30, :day)
      
      old_events = for i <- 1..5 do
        %Event{
          id: UUID.uuid4(),
          type: :old_event,
          agent_id: :ml_agent_1,
          data: %{sequence: i},
          timestamp: DateTime.add(old_time, i, :minute)
        }
      end

      # Create recent events that should remain active
      recent_events = for i <- 1..3 do
        %Event{
          id: UUID.uuid4(),
          type: :recent_event,
          agent_id: :ml_agent_1,
          data: %{sequence: i},
          timestamp: DateTime.add(DateTime.utc_now(), -i, :hour)
        }
      end

      # Store all events
      for event <- old_events ++ recent_events do
        EventStore.store_event(event)
      end

      # Trigger archival process (events older than 7 days)
      EventStore.archive_old_events(7)

      # Query active events - should only have recent ones
      {:ok, active_events} = EventStore.query_events(%{
        agent_id: :ml_agent_1,
        namespace: namespace
      })

      active_types = Enum.map(active_events, & &1.type)
      assert :recent_event in active_types
      refute :old_event in active_types
    end

    test "provides event store statistics and health metrics" do
      # Generate diverse events for statistics
      for agent_id <- [:ml_agent_1, :ml_agent_2, :coord_agent] do
        for i <- 1..10 do
          event = %Event{
            id: UUID.uuid4(),
            type: Enum.random([:task_started, :task_completed, :health_check]),
            agent_id: agent_id,
            data: %{sequence: i},
            timestamp: DateTime.utc_now()
          }
          
          EventStore.store_event(event)
        end
      end

      # Get store statistics
      {:ok, stats} = EventStore.get_store_statistics()

      assert stats.total_events == 30
      assert stats.events_by_agent[:ml_agent_1] == 10
      assert stats.events_by_agent[:ml_agent_2] == 10
      assert stats.events_by_agent[:coord_agent] == 10
      assert Map.has_key?(stats.events_by_type, :task_started)
      assert is_number(stats.storage_size_bytes)
      assert is_number(stats.avg_event_size_bytes)
    end
  end

  describe "error handling and resilience" do
    test "handles malformed events gracefully" do
      # Event with missing required fields
      malformed_event = %{
        type: :malformed,
        # Missing id, agent_id, timestamp
        data: %{test: "data"}
      }

      result = EventStore.store_event(malformed_event)
      assert {:error, reason} = result
      assert reason =~ "invalid_event_format"
    end

    test "handles storage backend failures gracefully" do
      # Simulate storage backend failure
      EventStore.simulate_storage_failure()

      event = %Event{
        id: UUID.uuid4(),
        type: :test_during_failure,
        agent_id: :ml_agent_1,
        data: %{test: "resilience"}
      }

      # Should handle failure gracefully
      result = EventStore.store_event(event)
      assert {:error, reason} = result
      assert reason =~ "storage_unavailable"

      # Restore storage and verify recovery
      EventStore.restore_storage()
      
      result = EventStore.store_event(event)
      assert :ok = result
    end

    test "maintains data consistency during concurrent operations" do
      correlation_id = "consistency-test-#{System.unique_integer()}"
      
      # Launch concurrent event storage operations
      tasks = for i <- 1..20 do
        Task.async(fn ->
          event = %Event{
            id: UUID.uuid4(),
            type: :concurrent_test,
            agent_id: Enum.random([:ml_agent_1, :ml_agent_2]),
            data: %{sequence: i},
            correlation_id: correlation_id,
            timestamp: DateTime.utc_now()
          }
          
          EventStore.store_event(event)
        end)
      end

      # Wait for all operations to complete
      results = Task.await_many(tasks, 5000)
      
      # All operations should succeed
      assert Enum.all?(results, &(&1 == :ok))

      # Verify all events were stored correctly
      {:ok, stored_events} = EventStore.get_correlated_events(correlation_id)
      assert length(stored_events) == 20
      
      # Verify sequence integrity
      sequences = Enum.map(stored_events, &(&1.data.sequence))
      assert Enum.sort(sequences) == Enum.to_list(1..20)
    end
  end
end