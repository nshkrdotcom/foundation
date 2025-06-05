defmodule Foundation.Services.EventStoreTest do
  use ExUnit.Case, async: false

  alias Foundation.Services.EventStore
  alias Foundation.Types.Event
  alias FoundationTestHelper

  setup do
    # Use our modern test helper instead of manual service startup
    FoundationTestHelper.setup_foundation_test()

    # Wait for services to be ready (should be quick)
    case FoundationTestHelper.wait_for_services(2000) do
      :ok ->
        :ok

      {:error, :timeout} ->
        raise "Foundation services not available within timeout"
    end

    on_exit(fn ->
      FoundationTestHelper.cleanup_foundation_test()
    end)

    :ok
  end

  describe "store/1" do
    test "stores valid event and returns event ID" do
      event = create_test_event(123, :test, %{key: "value"})

      assert {:ok, 123} = EventStore.store(event)
    end

    test "rejects invalid event" do
      # Missing required fields
      invalid_event = Event.empty()

      assert {:error, error} = EventStore.store(invalid_event)
      assert error.error_type == :validation_failed
    end
  end

  describe "store_batch/1" do
    test "stores multiple valid events" do
      events = [
        create_test_event(1, :test1, %{data: 1}),
        create_test_event(2, :test2, %{data: 2}),
        create_test_event(3, :test3, %{data: 3})
      ]

      assert {:ok, [1, 2, 3]} = EventStore.store_batch(events)
    end

    test "rejects batch with invalid event" do
      events = [
        create_test_event(1, :test1, %{data: 1}),
        # Invalid event
        Event.empty(),
        create_test_event(3, :test3, %{data: 3})
      ]

      assert {:error, error} = EventStore.store_batch(events)
      assert error.error_type == :validation_failed
    end
  end

  describe "get/1" do
    test "retrieves stored event by ID" do
      event = create_test_event(123, :test, %{key: "value"})
      {:ok, _} = EventStore.store(event)

      assert {:ok, retrieved_event} = EventStore.get(123)
      assert retrieved_event.event_id == 123
      assert retrieved_event.event_type == :test
      assert retrieved_event.data == %{key: "value"}
    end

    test "returns error for non-existent event" do
      assert {:error, error} = EventStore.get(99999)
      assert %Foundation.Types.Error{error_type: :not_found} = error
    end
  end

  describe "query/1" do
    test "queries events by event type" do
      events = [
        create_test_event(1, :type_a, %{}),
        create_test_event(2, :type_b, %{}),
        create_test_event(3, :type_a, %{})
      ]

      Enum.each(events, &EventStore.store/1)

      query = %{event_type: :type_a}
      assert {:ok, results} = EventStore.query(query)

      assert length(results) == 2
      assert Enum.all?(results, fn event -> event.event_type == :type_a end)
    end

    test "queries events with time range" do
      base_time = System.monotonic_time()

      events = [
        create_test_event(1, :test, %{}, timestamp: base_time + 100),
        create_test_event(2, :test, %{}, timestamp: base_time + 200),
        create_test_event(3, :test, %{}, timestamp: base_time + 300)
      ]

      Enum.each(events, &EventStore.store/1)

      query = %{time_range: {base_time + 150, base_time + 250}}
      assert {:ok, results} = EventStore.query(query)

      assert length(results) == 1
      assert Enum.at(results, 0).event_id == 2
    end

    test "applies pagination" do
      events = for i <- 1..10, do: create_test_event(i, :test, %{})
      Enum.each(events, &EventStore.store/1)

      query = %{limit: 3, offset: 2, order_by: :event_id}
      assert {:ok, results} = EventStore.query(query)

      assert length(results) == 3
      assert Enum.at(results, 0).event_id == 3
      assert Enum.at(results, 1).event_id == 4
      assert Enum.at(results, 2).event_id == 5
    end
  end

  describe "get_by_correlation/1" do
    test "retrieves events by correlation ID" do
      correlation_id = "test-correlation-123"

      events = [
        create_test_event(1, :test, %{}, correlation_id: correlation_id),
        create_test_event(2, :test, %{}, correlation_id: "other"),
        create_test_event(3, :test, %{}, correlation_id: correlation_id)
      ]

      Enum.each(events, &EventStore.store/1)

      assert {:ok, results} = EventStore.get_by_correlation(correlation_id)

      assert length(results) == 2
      assert Enum.all?(results, fn event -> event.correlation_id == correlation_id end)
      # Should be sorted by timestamp
      assert Enum.at(results, 0).event_id == 1
      assert Enum.at(results, 1).event_id == 3
    end

    test "returns empty list for non-existent correlation ID" do
      assert {:ok, []} = EventStore.get_by_correlation("non-existent")
    end
  end

  describe "prune_before/1" do
    test "removes events older than cutoff time" do
      base_time = System.monotonic_time()

      events = [
        create_test_event(1, :test, %{}, timestamp: base_time - 200),
        create_test_event(2, :test, %{}, timestamp: base_time - 100),
        create_test_event(3, :test, %{}, timestamp: base_time + 100)
      ]

      Enum.each(events, &EventStore.store/1)

      cutoff_time = base_time - 50
      assert {:ok, pruned_count} = EventStore.prune_before(cutoff_time)

      assert pruned_count == 2

      # Only the newest event should remain
      assert {:error, _} = EventStore.get(1)
      assert {:error, _} = EventStore.get(2)
      assert {:ok, _} = EventStore.get(3)
    end
  end

  describe "stats/0" do
    test "returns storage statistics" do
      # Store some events
      events = for i <- 1..5, do: create_test_event(i, :test, %{})
      Enum.each(events, &EventStore.store/1)

      assert {:ok, stats} = EventStore.stats()

      assert stats.current_event_count == 5
      assert stats.events_stored == 5
      assert stats.events_pruned == 0
      assert is_integer(stats.uptime_ms)
      assert is_integer(stats.memory_usage_estimate)
    end
  end

  describe "available?/0" do
    test "returns true when server is running" do
      assert EventStore.available?()
    end
  end

  # Helper function to create test events
  defp create_test_event(event_id, event_type, data, opts \\ []) do
    Event.new(
      event_id: event_id,
      event_type: event_type,
      timestamp: Keyword.get(opts, :timestamp, System.monotonic_time()),
      wall_time: DateTime.utc_now(),
      node: Node.self(),
      pid: self(),
      correlation_id: Keyword.get(opts, :correlation_id),
      data: data
    )
  end
end
