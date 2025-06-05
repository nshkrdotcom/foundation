defmodule Foundation.Property.EventCorrelationPropertiesTest do
  # EventStore operations affect shared state
  use ExUnit.Case, async: false
  use ExUnitProperties

  # Property tests are inherently slow
  @moduletag :slow

  alias Foundation.{Events}
  alias Foundation.Services.EventStore
  alias Foundation.Types.Event
  alias Foundation.TestHelpers

  setup do
    :ok = TestHelpers.ensure_config_available()
    :ok = EventStore.initialize()

    # Create a truly unique test session ID to isolate our events
    test_session_id = "test-#{System.unique_integer([:positive])}-#{:rand.uniform(1_000_000)}"

    # Clear ALL existing events to start completely fresh
    current_time = System.monotonic_time()
    # Clear everything
    {:ok, _} = EventStore.prune_before(current_time + 1_000_000)

    {:ok, test_session_id: test_session_id}
  end

  # Generators for test data

  defp event_type_generator do
    one_of([
      constant(:user_action),
      constant(:system_event),
      constant(:config_updated),
      constant(:error_occurred),
      constant(:metric_collected),
      constant(:service_started),
      constant(:data_processed),
      atom(:alphanumeric)
    ])
  end

  defp event_data_generator do
    one_of([
      constant(%{}),
      map_of(atom(:alphanumeric), term(), max_length: 10),
      map_of(string(:alphanumeric), term(), max_length: 10),
      serializable_nested_data_generator()
    ])
  end

  defp serializable_nested_data_generator do
    sized(fn size ->
      serializable_nested_data_generator(size)
    end)
  end

  defp serializable_nested_data_generator(0) do
    one_of([
      string(:alphanumeric),
      integer(),
      float(),
      boolean(),
      atom(:alphanumeric)
    ])
  end

  defp serializable_nested_data_generator(size) when size > 0 do
    one_of([
      string(:alphanumeric),
      integer(),
      float(),
      boolean(),
      atom(:alphanumeric),
      list_of(serializable_nested_data_generator(div(size, 2)), max_length: 5),
      map_of(
        atom(:alphanumeric),
        serializable_nested_data_generator(div(size, 2)),
        max_length: 5
      )
    ])
  end

  defp correlation_id_generator do
    one_of([
      constant(nil),
      bind(string(:alphanumeric, min_length: 8, max_length: 16), fn base ->
        constant("session-#{System.unique_integer([:positive])}-#{base}")
      end),
      bind(uuid_generator(), fn uuid ->
        constant("session-#{System.unique_integer([:positive])}-#{uuid}")
      end)
    ])
  end

  defp uuid_generator do
    constant(Foundation.Utils.generate_correlation_id())
  end

  defp query_generator do
    one_of([
      constant(%{}),
      map_of(atom(:alphanumeric), term(), max_length: 5),
      bind(event_type_generator(), fn event_type ->
        constant(%{event_type: event_type})
      end),
      bind(correlation_id_generator(), fn correlation_id ->
        if correlation_id do
          constant(%{correlation_id: correlation_id})
        else
          constant(%{})
        end
      end)
    ])
  end

  defp timestamp_range_generator do
    bind(integer(0..1000), fn offset ->
      base_time = System.monotonic_time()
      # microseconds
      start_time = base_time - offset * 1_000_000
      end_time = base_time + offset * 1_000_000
      constant({start_time, end_time})
    end)
  end

  # Property Tests

  property "Any event stored and retrieved from EventStore retains data integrity (for serializable data)" do
    check all(
            event_type <- event_type_generator(),
            event_data <- event_data_generator(),
            correlation_id <- correlation_id_generator()
          ) do
      # Create event
      {:ok, event} = Events.new_event(event_type, event_data, correlation_id: correlation_id)

      # Store event
      {:ok, event_id} = EventStore.store(event)

      # Retrieve event
      {:ok, retrieved_event} = EventStore.get(event_id)

      # Verify data integrity
      assert retrieved_event.event_type == event_type
      assert retrieved_event.data == event_data
      assert retrieved_event.correlation_id == correlation_id
      assert retrieved_event.event_id == event_id

      # Verify timestamp is preserved (within reasonable bounds)
      # microseconds
      assert abs(retrieved_event.timestamp - event.timestamp) < 1000

      # Verify structure is valid
      assert %Event{} = retrieved_event
    end
  end

  property "EventStore.store/1 with any valid event always succeeds or fails gracefully" do
    check all(
            event_type <- event_type_generator(),
            event_data <- event_data_generator(),
            correlation_id <- correlation_id_generator()
          ) do
      case Events.new_event(event_type, event_data, correlation_id: correlation_id) do
        {:ok, event} ->
          result = EventStore.store(event)

          # Should either succeed with an ID or fail gracefully
          case result do
            {:ok, event_id} ->
              assert is_integer(event_id)
              assert event_id > 0

            {:error, reason} ->
              assert is_atom(reason) or is_binary(reason) or is_tuple(reason)
          end

        {:error, _reason} ->
          # Event creation failed - that's fine for this test
          :ok
      end

      # EventStore should remain responsive
      assert EventStore.available?()
    end
  end

  property "EventStore.query/1 with random query parameters never crashes" do
    check all(query <- query_generator()) do
      result = EventStore.query(query)

      # Should not crash and return proper result
      assert match?({:ok, _}, result) or match?({:error, _}, result)

      case result do
        {:ok, events} ->
          assert is_list(events)

          # All returned events should be valid
          Enum.each(events, fn event ->
            assert %Event{} = event
            assert is_integer(event.event_id)
            assert is_atom(event.event_type)
            # Event data can be any term, not just maps
            assert event.data != nil
            assert is_integer(event.timestamp)
          end)

        {:error, _reason} ->
          # Query failed gracefully
          :ok
      end

      # EventStore should remain responsive
      assert EventStore.available?()
    end
  end

  property "EventStore.get_by_correlation/1 always returns events in chronological order" do
    check all(
            correlation_id <- filter(correlation_id_generator(), &(&1 != nil)),
            event_sequence <-
              list_of(
                tuple({event_type_generator(), event_data_generator()}),
                min_length: 2,
                max_length: 10
              )
          ) do
      # Create and store events with the same correlation ID
      stored_event_ids =
        Enum.map(event_sequence, fn {event_type, event_data} ->
          # Add small delay to ensure different timestamps
          Process.sleep(1)

          {:ok, event} = Events.new_event(event_type, event_data, correlation_id: correlation_id)
          {:ok, event_id} = EventStore.store(event)
          event_id
        end)

      # Retrieve by correlation
      {:ok, retrieved_events} = EventStore.get_by_correlation(correlation_id)

      # Should return all events
      assert length(retrieved_events) >= length(stored_event_ids)

      # Filter to only our events using event IDs for exact matching
      our_events =
        Enum.filter(retrieved_events, fn retrieved ->
          retrieved.event_id in stored_event_ids
        end)

      assert length(our_events) == length(stored_event_ids)

      # Events should be in chronological order
      timestamps = Enum.map(our_events, & &1.timestamp)
      assert timestamps == Enum.sort(timestamps)

      # Verify all have the same correlation ID
      Enum.each(our_events, fn event ->
        assert event.correlation_id == correlation_id
      end)
    end
  end

  property "Event parent-child relationships form valid tree structures" do
    check all(
            correlation_id <- filter(correlation_id_generator(), &(&1 != nil)),
            sequence_length <- integer(3..8)
          ) do
      # Create a unique session ID for this specific test run
      session_id = System.unique_integer([:positive])

      # Create event chain with parent-child relationships
      chain_event_ids =
        Enum.reduce(1..sequence_length, [], fn index, acc ->
          parent_id =
            case acc do
              [] -> nil
              [prev_id | _] -> prev_id
            end

          unique_data = %{
            sequence: index,
            session_id: session_id,
            test_type: :chain_event
          }

          {:ok, event} =
            Events.new_event(
              :chain_event,
              unique_data,
              correlation_id: correlation_id,
              parent_id: parent_id
            )

          {:ok, event_id} = EventStore.store(event)
          [event_id | acc]
        end)
        |> Enum.reverse()

      # Retrieve all events by correlation
      {:ok, retrieved_events} = EventStore.get_by_correlation(correlation_id)

      # Filter to ONLY our chain events using session_id for precise matching
      chain_events =
        Enum.filter(retrieved_events, fn event ->
          event.event_type == :chain_event and
            is_map(event.data) and
            Map.get(event.data, :session_id) == session_id and
            event.event_id in chain_event_ids
        end)
        |> Enum.sort_by(fn event -> event.data.sequence end)

      assert length(chain_events) == sequence_length

      # Verify parent-child relationships
      Enum.with_index(chain_events, fn event, index ->
        if index == 0 do
          # First event should have no parent
          assert event.parent_id == nil
        else
          # Other events should reference the previous event
          prev_event = Enum.at(chain_events, index - 1)
          assert event.parent_id == prev_event.event_id
        end
      end)

      # Verify no cycles exist
      verify_no_cycles(chain_events)
    end
  end

  property "Event correlation IDs are preserved through any number of related events" do
    check all(
            correlation_id <- filter(correlation_id_generator(), &(&1 != nil)),
            event_count <- integer(1..15)
          ) do
      # Create multiple events with same correlation ID
      _created_events =
        for i <- 1..event_count do
          # Small delay to ensure timestamp progression
          Process.sleep(1)

          {:ok, event} =
            Events.new_event(
              :correlation_test,
              %{index: i, timestamp: System.monotonic_time()},
              correlation_id: correlation_id
            )

          {:ok, _event_id} = EventStore.store(event)
          event
        end

      # Retrieve by correlation
      {:ok, retrieved_events} = EventStore.get_by_correlation(correlation_id)

      # Filter to our test events
      our_events =
        Enum.filter(retrieved_events, fn event ->
          event.event_type == :correlation_test
        end)

      assert length(our_events) >= event_count

      # All events should have the correct correlation ID
      Enum.each(our_events, fn event ->
        assert event.correlation_id == correlation_id
      end)

      # Verify we can retrieve each individual event and correlation is preserved
      Enum.each(our_events, fn event ->
        {:ok, individual_event} = EventStore.get(event.event_id)
        assert individual_event.correlation_id == correlation_id
      end)
    end
  end

  property "EventStore state after a series of stores and prunes is consistent with operations" do
    check all(
            operations <-
              list_of(
                one_of([
                  tuple(
                    {:store, event_type_generator(), event_data_generator(),
                     correlation_id_generator()}
                  ),
                  tuple({:prune, timestamp_range_generator()})
                ]),
                min_length: 5,
                max_length: 20
              )
          ) do
      # Track what should be in the store
      stored_events = []

      # Execute operations and track expected state
      final_expected_events =
        Enum.reduce(operations, stored_events, fn operation, acc ->
          case operation do
            {:store, event_type, event_data, correlation_id} ->
              case Events.new_event(event_type, event_data, correlation_id: correlation_id) do
                {:ok, event} ->
                  case EventStore.store(event) do
                    {:ok, event_id} ->
                      stored_event = %{event | event_id: event_id}
                      [stored_event | acc]

                    {:error, _} ->
                      acc
                  end

                {:error, _} ->
                  acc
              end

            {:prune, {_start_time, end_time}} ->
              # Remove events with timestamps before end_time
              # Only prune if the time range makes sense
              if end_time > 0 do
                :ok = EventStore.prune_before(end_time)
                # Filter out events that would have been pruned
                Enum.filter(acc, fn event ->
                  event.timestamp >= end_time
                end)
              else
                acc
              end
          end
        end)

      # Verify the store contains at least our expected events
      {:ok, all_events} = EventStore.query(%{})

      # We should have at least the events we expect to still exist
      expected_event_ids = Enum.map(final_expected_events, & &1.event_id)
      actual_event_ids = Enum.map(all_events, & &1.event_id)

      # Each expected event should exist in the store
      missing_events =
        Enum.filter(expected_event_ids, fn expected_id ->
          expected_id not in actual_event_ids
        end)

      # Only fail if there are missing events that should exist
      if length(missing_events) > 0 and length(final_expected_events) > 0 do
        # Double-check by trying to retrieve the missing events individually
        actually_missing =
          Enum.filter(missing_events, fn event_id ->
            case EventStore.get(event_id) do
              # Event exists
              {:ok, _} -> false
              # Event actually missing
              {:error, _} -> true
            end
          end)

        assert length(actually_missing) == 0,
               "Expected events #{inspect(actually_missing)} to be in store but they were missing"
      end

      # EventStore should remain functional
      assert EventStore.available?()
    end
  end

  property "Event timestamps are monotonic within correlation groups" do
    check all(
            correlation_id <- filter(correlation_id_generator(), &(&1 != nil)),
            event_count <- integer(3..10)
          ) do
      # Create a unique session ID for this specific test run
      session_id = System.unique_integer([:positive])

      # Create events sequentially to ensure different timestamps
      created_event_ids =
        for i <- 1..event_count do
          # Small delay to ensure timestamp progression
          Process.sleep(1)

          # Use unique data that includes the session ID
          unique_data = %{
            sequence: i,
            session_id: session_id,
            test_type: :monotonic_test,
            timestamp: System.monotonic_time()
          }

          {:ok, event} =
            Events.new_event(:monotonic_test, unique_data, correlation_id: correlation_id)

          {:ok, event_id} = EventStore.store(event)
          event_id
        end

      # Retrieve events by correlation
      {:ok, retrieved_events} = EventStore.get_by_correlation(correlation_id)

      # Filter to ONLY our test events using session_id for precise matching
      our_events =
        Enum.filter(retrieved_events, fn event ->
          event.event_type == :monotonic_test and
            is_map(event.data) and
            Map.get(event.data, :session_id) == session_id and
            event.event_id in created_event_ids
        end)
        |> Enum.sort_by(fn event -> event.data.sequence end)

      assert length(our_events) == event_count

      # Timestamps should be monotonic (non-decreasing)
      timestamps = Enum.map(our_events, & &1.timestamp)

      Enum.zip(timestamps, tl(timestamps))
      |> Enum.each(fn {prev_timestamp, curr_timestamp} ->
        assert curr_timestamp >= prev_timestamp,
               "Timestamps should be monotonic: #{prev_timestamp} <= #{curr_timestamp}"
      end)
    end
  end

  property "Event data serialization preserves complex nested structures" do
    check all(complex_data <- serializable_nested_data_generator()) do
      # Create event with complex data
      {:ok, event} = Events.new_event(:complex_data_test, complex_data)

      # Store and retrieve
      {:ok, event_id} = EventStore.store(event)
      {:ok, retrieved_event} = EventStore.get(event_id)

      # Data should be exactly preserved
      assert retrieved_event.data == complex_data

      # Verify deep equality for nested structures
      verify_deep_equality(retrieved_event.data, complex_data)
    end
  end

  property "EventStore concurrent operations maintain referential integrity" do
    check all(
            correlation_id <- filter(correlation_id_generator(), &(&1 != nil)),
            operation_count <- integer(5..15)
          ) do
      # Create a unique session ID for this specific test run
      session_id = System.unique_integer([:positive])

      # Create concurrent operations
      tasks =
        for i <- 1..operation_count do
          Task.async(fn ->
            # Random operation: store, retrieve, or query
            operation = Enum.random([:store, :retrieve, :query])

            case operation do
              :store ->
                unique_data = %{
                  task_id: i,
                  session_id: session_id,
                  timestamp: System.monotonic_time(),
                  test_type: :concurrent_test
                }

                {:ok, event} =
                  Events.new_event(:concurrent_test, unique_data, correlation_id: correlation_id)

                EventStore.store(event)

              :retrieve ->
                # Try to retrieve by correlation
                EventStore.get_by_correlation(correlation_id)

              :query ->
                # Query for our test events
                EventStore.query(%{event_type: :concurrent_test})
            end
          end)
        end

      # Wait for all operations to complete
      results = Task.await_many(tasks, 5000)

      # All operations should complete successfully or fail gracefully
      Enum.each(results, fn result ->
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end)

      # EventStore should remain functional and responsive
      assert EventStore.available?()

      # Final verification: retrieve all events and verify integrity
      {:ok, final_events} = EventStore.get_by_correlation(correlation_id)

      # Filter to ONLY our test events using session_id for precise matching
      concurrent_events =
        Enum.filter(final_events, fn event ->
          event.event_type == :concurrent_test and
            is_map(event.data) and
            Map.get(event.data, :session_id) == session_id
        end)

      # Count successful stores from results (only those that returned event IDs)
      successful_stores =
        Enum.count(results, fn
          {:ok, event_id} when is_integer(event_id) -> true
          _ -> false
        end)

      assert length(concurrent_events) == successful_stores

      # All events should be valid and have unique IDs
      if length(concurrent_events) > 0 do
        event_ids = Enum.map(concurrent_events, & &1.event_id)
        assert length(event_ids) == length(Enum.uniq(event_ids))
      end
    end
  end

  # Helper functions

  defp verify_no_cycles(events) do
    # Build parent-child map
    parent_map =
      events
      |> Enum.reject(fn event -> event.parent_id == nil end)
      |> Map.new(fn event -> {event.event_id, event.parent_id} end)

    # Check each event for cycles
    Enum.each(events, fn event ->
      visited = MapSet.new()
      current = event.event_id

      verify_no_cycle_from(current, parent_map, visited)
    end)
  end

  defp verify_no_cycle_from(nil, _parent_map, _visited), do: :ok

  defp verify_no_cycle_from(current_id, parent_map, visited) do
    assert not MapSet.member?(visited, current_id),
           "Cycle detected starting from #{current_id}"

    new_visited = MapSet.put(visited, current_id)
    parent_id = Map.get(parent_map, current_id)

    verify_no_cycle_from(parent_id, parent_map, new_visited)
  end

  defp verify_deep_equality(value1, value2) when is_map(value1) and is_map(value2) do
    assert Map.keys(value1) == Map.keys(value2)

    Enum.each(value1, fn {key, val1} ->
      val2 = Map.get(value2, key)
      verify_deep_equality(val1, val2)
    end)
  end

  defp verify_deep_equality(value1, value2) when is_list(value1) and is_list(value2) do
    assert length(value1) == length(value2)

    Enum.zip(value1, value2)
    |> Enum.each(fn {val1, val2} ->
      verify_deep_equality(val1, val2)
    end)
  end

  defp verify_deep_equality(value1, value2) do
    assert value1 == value2
  end
end
