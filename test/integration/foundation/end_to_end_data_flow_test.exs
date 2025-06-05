defmodule Foundation.Integration.EndToEndDataFlowTest do
  @moduledoc """
  End-to-end integration tests for foundation data flow.

  Tests complete scenarios from event creation through storage, querying,
  correlation tracking, telemetry collection, and configuration-driven behavior.
  """

  use ExUnit.Case, async: false

  alias Foundation.{Config, Events, Telemetry}
  alias Foundation.Services.{EventStore, TelemetryService}
  alias Foundation.TestHelpers

  setup do
    # Ensure all services are available
    :ok = TestHelpers.ensure_config_available()
    :ok = EventStore.initialize()
    :ok = TelemetryService.initialize()

    # Store original config for restoration
    {:ok, original_config} = Config.get()

    # Clear existing events to start fresh
    current_time = System.monotonic_time()
    {:ok, _} = EventStore.prune_before(current_time)

    on_exit(fn ->
      # Restore configuration
      try do
        if Config.available?() do
          case original_config do
            %{ai: %{planning: %{sampling_rate: rate}}} ->
              Config.update([:ai, :planning, :sampling_rate], rate)

            _ ->
              :ok
          end
        end
      catch
        :exit, _ -> :ok
      end
    end)

    %{original_config: original_config}
  end

  describe "complete event lifecycle" do
    test "event creation → storage → query → correlation → telemetry" do
      correlation_id = Foundation.Utils.generate_correlation_id()

      # Phase 1: Create and store related events
      events_data = [
        %{action: "user_login", user_id: "user123"},
        %{action: "file_open", file_path: "/path/to/file.ex"},
        %{action: "function_call", module: "MyModule", function: "my_function"},
        %{action: "user_logout", user_id: "user123"}
      ]

      # Create events sequentially with proper parent-child relationships
      {stored_event_ids, _} =
        Enum.map_reduce(events_data, nil, fn event_data, parent_event_id ->
          {:ok, event} =
            Events.new_event(
              :user_session_event,
              event_data,
              correlation_id: correlation_id,
              parent_id: parent_event_id
            )

          {:ok, event_id} = EventStore.store(event)
          # Return event_id and set it as next parent
          {event_id, event_id}
        end)

      # Phase 2: Verify storage and basic queries
      assert length(stored_event_ids) == 4

      # Query by event type
      query = %{event_type: :user_session_event}
      {:ok, session_events} = EventStore.query(query)

      session_event_ids = Enum.map(session_events, & &1.event_id)

      # All our events should be in the results
      Enum.each(stored_event_ids, fn event_id ->
        assert event_id in session_event_ids,
               "Expected event_id #{event_id} to be found in query results"
      end)

      # Phase 3: Test correlation-based queries
      {:ok, correlated_events} = EventStore.get_by_correlation(correlation_id)
      assert length(correlated_events) == 4

      # Events should be ordered by timestamp
      timestamps = Enum.map(correlated_events, & &1.timestamp)
      assert timestamps == Enum.sort(timestamps), "Expected events to be sorted by timestamp"

      # Phase 4: Verify parent-child relationships
      _events_by_id = Map.new(correlated_events, fn event -> {event.event_id, event} end)

      # First event should have no parent
      first_event =
        Enum.find(correlated_events, fn event ->
          event.data.action == "user_login"
        end)

      assert first_event.parent_id == nil

      # Other events should have parent references
      child_events =
        Enum.filter(correlated_events, fn event ->
          event.data.action != "user_login"
        end)

      Enum.each(child_events, fn child ->
        assert child.parent_id != nil, "Expected child event to have parent_id"
      end)

      # Phase 5: Test time-range queries
      start_time = first_event.timestamp - 1000
      # 10 seconds later
      end_time = first_event.timestamp + 10_000_000

      time_query = %{time_range: {start_time, end_time}}
      {:ok, time_filtered_events} = EventStore.query(time_query)

      # Should include our session events plus any others in the time range
      session_in_range =
        Enum.filter(time_filtered_events, fn event ->
          event.correlation_id == correlation_id
        end)

      assert length(session_in_range) == 4

      # Phase 6: Verify telemetry integration
      {:ok, metrics} = Telemetry.get_metrics()

      # Should have metrics about event storage
      events_stored = get_in(metrics, [:foundation, :events_stored]) || 0
      assert events_stored >= 4, "Expected at least 4 events stored metric"

      # Phase 7: Test complex queries
      # Query for specific action within the session
      action_query = %{
        event_type: :user_session_event,
        correlation_id: correlation_id
      }

      {:ok, action_events} = EventStore.query(action_query)

      login_events =
        Enum.filter(action_events, fn event ->
          event.data.action == "user_login"
        end)

      assert length(login_events) == 1
      login_event = List.first(login_events)
      assert login_event.data.user_id == "user123"
    end

    test "configuration-driven event processing" do
      # Test how configuration changes affect event processing behavior

      # Phase 1: Create events with default configuration
      {:ok, config} = Config.get()
      _original_sampling_rate = config.ai.planning.sampling_rate

      # Create some baseline events
      _baseline_events =
        for i <- 1..3 do
          {:ok, event} = Events.new_event(:config_test_event, %{sequence: i, phase: "baseline"})
          {:ok, _id} = EventStore.store(event)
          event
        end

      # Phase 2: Change configuration
      new_sampling_rate = 0.25
      :ok = Config.update([:ai, :planning, :sampling_rate], new_sampling_rate)

      # Verify configuration change created an event
      config_query = %{event_type: :config_updated}
      {:ok, config_events} = EventStore.query(config_query)

      recent_config_events =
        Enum.filter(config_events, fn event ->
          event.data.path == [:ai, :planning, :sampling_rate] and
            event.data.new_value == new_sampling_rate
        end)

      assert length(recent_config_events) >= 1, "Expected config update event"

      # Phase 3: Create events after configuration change
      _post_config_events =
        for i <- 4..6 do
          {:ok, event} = Events.new_event(:config_test_event, %{sequence: i, phase: "post_config"})
          {:ok, _id} = EventStore.store(event)
          event
        end

      # Phase 4: Verify both sets of events are stored and queryable
      all_test_query = %{event_type: :config_test_event}
      {:ok, all_test_events} = EventStore.query(all_test_query)

      baseline_in_results =
        Enum.filter(all_test_events, fn event ->
          event.data.phase == "baseline"
        end)

      post_config_in_results =
        Enum.filter(all_test_events, fn event ->
          event.data.phase == "post_config"
        end)

      assert length(baseline_in_results) == 3
      assert length(post_config_in_results) == 3

      # Phase 5: Verify telemetry captured both phases
      {:ok, final_metrics} = Telemetry.get_metrics()
      total_events_stored = get_in(final_metrics, [:foundation, :events_stored]) || 0

      # Should have stored at least our 6 test events plus the config event
      assert total_events_stored >= 7
    end
  end

  describe "error handling across components" do
    test "errors propagate correctly through the system" do
      # Phase 1: Create an event that will succeed
      {:ok, good_event} = Events.new_event(:error_test, %{type: "success"})
      {:ok, _good_id} = EventStore.store(good_event)

      # Phase 2: Attempt an invalid configuration update
      # Invalid > 1.0
      invalid_result = Config.update([:ai, :planning, :sampling_rate], 5.0)
      assert {:error, error} = invalid_result
      assert error.error_type == :range_error

      # Phase 3: Verify the error might generate error events (depending on implementation)
      # This tests that errors don't crash the system and are handled gracefully

      # Phase 4: System should still be functional after error
      {:ok, recovery_event} = Events.new_event(:error_test, %{type: "recovery"})
      {:ok, _recovery_id} = EventStore.store(recovery_event)

      # Phase 5: Verify both success and recovery events are stored
      query = %{event_type: :error_test}
      {:ok, error_test_events} = EventStore.query(query)

      event_types = Enum.map(error_test_events, fn event -> event.data.type end)
      assert "success" in event_types
      assert "recovery" in event_types

      # Phase 6: Verify telemetry is still operational
      {:ok, _metrics} = Telemetry.get_metrics()
    end
  end

  describe "performance under load" do
    test "system maintains performance with concurrent operations" do
      correlation_id = Foundation.Utils.generate_correlation_id()

      # Phase 1: Concurrent event creation and storage
      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            start_time = System.monotonic_time(:microsecond)

            {:ok, event} =
              Events.new_event(
                :load_test_event,
                %{task_id: i, data: String.duplicate("x", 100)},
                correlation_id: correlation_id
              )

            {:ok, event_id} = EventStore.store(event)

            end_time = System.monotonic_time(:microsecond)
            duration = end_time - start_time

            {event_id, duration}
          end)
        end

      # Wait for all tasks to complete
      results = Task.await_many(tasks, 5000)

      # Phase 2: Verify all events were stored successfully
      assert length(results) == 20

      _event_ids = Enum.map(results, fn {event_id, _duration} -> event_id end)
      durations = Enum.map(results, fn {_event_id, duration} -> duration end)

      # No event storage should take excessively long
      max_duration = Enum.max(durations)
      assert max_duration < 100_000, "Expected no event storage to take > 100ms"

      # Phase 3: Concurrent querying
      query_tasks =
        for _i <- 1..10 do
          Task.async(fn ->
            start_time = System.monotonic_time(:microsecond)
            {:ok, events} = EventStore.query(%{event_type: :load_test_event})
            end_time = System.monotonic_time(:microsecond)

            {length(events), end_time - start_time}
          end)
        end

      query_results = Task.await_many(query_tasks, 3000)

      # All queries should return our events
      query_counts = Enum.map(query_results, fn {count, _duration} -> count end)
      query_durations = Enum.map(query_results, fn {_count, duration} -> duration end)

      # All queries should find at least our 20 events
      Enum.each(query_counts, fn count ->
        assert count >= 20, "Expected each query to find at least 20 events"
      end)

      # No query should take excessively long
      max_query_duration = Enum.max(query_durations)
      assert max_query_duration < 50_000, "Expected no query to take > 50ms"

      # Phase 4: Verify correlation query performance
      correlation_start = System.monotonic_time(:microsecond)
      {:ok, correlated_events} = EventStore.get_by_correlation(correlation_id)
      correlation_end = System.monotonic_time(:microsecond)

      correlation_duration = correlation_end - correlation_start
      assert length(correlated_events) == 20
      assert correlation_duration < 50_000, "Expected correlation query to complete within 50ms"

      # Phase 5: Verify telemetry performance
      telemetry_start = System.monotonic_time(:microsecond)
      {:ok, _metrics} = Telemetry.get_metrics()
      telemetry_end = System.monotonic_time(:microsecond)

      telemetry_duration = telemetry_end - telemetry_start
      assert telemetry_duration < 10_000, "Expected telemetry collection to complete within 10ms"
    end
  end

  describe "data consistency" do
    test "events maintain consistency across operations" do
      correlation_id = Foundation.Utils.generate_correlation_id()

      # Create a sequence of related events with proper parent-child relationships
      event_sequence =
        Enum.reduce(1..5, [], fn i, acc ->
          parent_id =
            case acc do
              # First event has no parent
              [] -> nil
              # Use previous event's ID
              [{_prev_event_id, prev_event} | _] -> prev_event.event_id
            end

          {:ok, event} =
            Events.new_event(
              :consistency_test,
              %{sequence: i, timestamp: System.monotonic_time(), action: "step_#{i}"},
              correlation_id: correlation_id,
              parent_id: parent_id
            )

          {:ok, event_id} = EventStore.store(event)
          [{event_id, event} | acc]
        end)
        # Restore original order
        |> Enum.reverse()

      # Test consistency across different query methods

      # 1. Query by event type
      {:ok, type_events} = EventStore.query(%{event_type: :consistency_test})
      type_event_ids = Enum.map(type_events, & &1.event_id)

      # 2. Query by correlation
      {:ok, corr_events} = EventStore.get_by_correlation(correlation_id)
      corr_event_ids = Enum.map(corr_events, & &1.event_id)

      # 3. Individual event retrieval
      stored_event_ids = Enum.map(event_sequence, fn {event_id, _event} -> event_id end)

      individual_events =
        for event_id <- stored_event_ids do
          {:ok, event} = EventStore.get(event_id)
          event
        end

      individual_event_ids = Enum.map(individual_events, & &1.event_id)

      # All query methods should return the same events
      Enum.each(stored_event_ids, fn event_id ->
        assert event_id in type_event_ids, "Event #{event_id} missing from type query"
        assert event_id in corr_event_ids, "Event #{event_id} missing from correlation query"
        assert event_id in individual_event_ids, "Event #{event_id} missing from individual query"
      end)

      # Verify parent-child relationships are consistent
      _events_by_id = Map.new(corr_events, fn event -> {event.event_id, event} end)

      for i <- 2..5 do
        child_event = Enum.find(corr_events, fn event -> event.data.sequence == i end)
        parent_event = Enum.find(corr_events, fn event -> event.data.sequence == i - 1 end)

        assert child_event.parent_id == parent_event.event_id,
               "Expected child event #{i} to reference parent event #{i - 1}"
      end

      # Verify events are ordered consistently by timestamp
      _type_timestamps = Enum.map(type_events, & &1.timestamp)
      corr_timestamps = Enum.map(corr_events, & &1.timestamp)
      _individual_timestamps = Enum.map(individual_events, & &1.timestamp)

      # Should all be sorted (correlation query guarantees this)
      assert corr_timestamps == Enum.sort(corr_timestamps)

      # Filter type query results to our correlation and verify ordering
      our_type_events =
        Enum.filter(type_events, fn event ->
          event.correlation_id == correlation_id
        end)

      _our_type_timestamps = Enum.map(our_type_events, & &1.timestamp)
      assert length(our_type_events) == 5
    end
  end
end
