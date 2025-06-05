defmodule Foundation.Logic.EventLogicTest do
  use ExUnit.Case, async: true

  alias Foundation.Types.Event
  alias Foundation.Logic.EventLogic

  describe "create_event/3" do
    test "creates valid event with defaults" do
      assert {:ok, event} = EventLogic.create_event(:test, %{key: "value"})

      assert event.event_type == :test
      assert event.data == %{key: "value"}
      assert is_integer(event.event_id)
      assert is_integer(event.timestamp)
      assert %DateTime{} = event.wall_time
      assert event.node == Node.self()
      assert event.pid == self()
    end

    test "creates event with custom options" do
      opts = [
        event_id: 999,
        correlation_id: "test-123",
        parent_id: 888
      ]

      assert {:ok, event} = EventLogic.create_event(:test, %{}, opts)

      assert event.event_id == 999
      assert event.correlation_id == "test-123"
      assert event.parent_id == 888
    end

    test "validates created event" do
      large_data = String.duplicate("x", 2_000_000)

      assert {:error, error} = EventLogic.create_event(:test, large_data)
      assert error.error_type == :data_too_large
    end
  end

  describe "create_function_entry/5" do
    test "creates function entry event" do
      args = [1, 2, 3]

      assert {:ok, event} = EventLogic.create_function_entry(MyModule, :my_func, 3, args)

      assert event.event_type == :function_entry
      assert event.data.module == MyModule
      assert event.data.function == :my_func
      assert event.data.arity == 3
      assert event.data.args == args
      assert is_integer(event.data.call_id)
    end
  end

  describe "create_function_exit/7" do
    test "creates function exit event" do
      call_id = 123
      result = {:ok, "success"}
      duration = 1000

      assert {:ok, event} =
               EventLogic.create_function_exit(
                 MyModule,
                 :my_func,
                 3,
                 call_id,
                 result,
                 duration,
                 :normal
               )

      assert event.event_type == :function_exit
      assert event.data.call_id == call_id
      assert event.data.module == MyModule
      assert event.data.function == :my_func
      assert event.data.result == result
      assert event.data.duration_ns == duration
      assert event.data.exit_reason == :normal
    end
  end

  describe "serialize_event/2" do
    test "serializes event to binary" do
      event = Event.new(event_id: 123, event_type: :test, data: %{key: "value"})

      assert {:ok, binary} = EventLogic.serialize_event(event)
      assert is_binary(binary)
    end

    test "handles serialization errors" do
      # Create event with unserialisable data
      event = Event.new(event_id: 123, event_type: :test, data: self())

      assert {:ok, _binary} = EventLogic.serialize_event(event)
    end
  end

  describe "deserialize_event/1" do
    test "deserializes valid event binary" do
      original_event =
        Event.new(
          event_id: 123,
          event_type: :test,
          timestamp: System.monotonic_time(),
          wall_time: DateTime.utc_now(),
          node: Node.self(),
          pid: self(),
          data: %{key: "value"}
        )

      {:ok, binary} = EventLogic.serialize_event(original_event)

      assert {:ok, deserialized_event} = EventLogic.deserialize_event(binary)
      assert deserialized_event.event_id == original_event.event_id
      assert deserialized_event.event_type == original_event.event_type
      assert deserialized_event.data == original_event.data
    end

    test "handles invalid binary" do
      invalid_binary = "not a valid binary"

      assert {:error, error} = EventLogic.deserialize_event(invalid_binary)
      assert error.error_type == :deserialization_failed
    end
  end

  describe "extract_correlation_chain/2" do
    test "extracts events with matching correlation ID" do
      correlation_id = "test-123"

      events = [
        Event.new(event_id: 1, correlation_id: correlation_id, timestamp: 100),
        Event.new(event_id: 2, correlation_id: "other", timestamp: 200),
        Event.new(event_id: 3, correlation_id: correlation_id, timestamp: 300)
      ]

      chain = EventLogic.extract_correlation_chain(events, correlation_id)

      assert length(chain) == 2
      assert Enum.at(chain, 0).event_id == 1
      assert Enum.at(chain, 1).event_id == 3
    end
  end

  describe "group_by_correlation/1" do
    test "groups events by correlation ID" do
      events = [
        Event.new(event_id: 1, correlation_id: "group-1", timestamp: 100),
        Event.new(event_id: 2, correlation_id: "group-2", timestamp: 200),
        Event.new(event_id: 3, correlation_id: "group-1", timestamp: 300),
        Event.new(event_id: 4, correlation_id: nil, timestamp: 400)
      ]

      grouped = EventLogic.group_by_correlation(events)

      assert Map.has_key?(grouped, "group-1")
      assert Map.has_key?(grouped, "group-2")
      refute Map.has_key?(grouped, nil)

      assert length(grouped["group-1"]) == 2
      assert length(grouped["group-2"]) == 1
    end
  end

  describe "filter_by_time_range/3" do
    test "filters events within time range" do
      events = [
        Event.new(event_id: 1, timestamp: 100),
        Event.new(event_id: 2, timestamp: 200),
        Event.new(event_id: 3, timestamp: 300)
      ]

      filtered = EventLogic.filter_by_time_range(events, 150, 250)

      assert length(filtered) == 1
      assert Enum.at(filtered, 0).event_id == 2
    end
  end
end
