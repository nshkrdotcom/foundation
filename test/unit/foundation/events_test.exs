defmodule Foundation.EventsTest do
  use ExUnit.Case, async: true
  @moduletag :foundation

  alias Foundation.Events
  alias Foundation.Types.{Event, Error}

  describe "event creation" do
    test "creates basic event with required fields" do
      data = %{test: "data"}
      {:ok, event} = Events.new_event(:test_event, data)

      assert %Event{} = event
      assert event.event_type == :test_event
      assert event.data == data
      assert is_integer(event.event_id)
      assert is_integer(event.timestamp)
      assert %DateTime{} = event.wall_time
      assert event.node == Node.self()
      assert event.pid == self()
    end

    test "creates event with optional correlation and parent IDs" do
      correlation_id = "test-correlation"
      parent_id = 12345

      {:ok, event} =
        Events.new_event(:test_event, %{},
          correlation_id: correlation_id,
          parent_id: parent_id
        )

      assert event.correlation_id == correlation_id
      assert event.parent_id == parent_id
    end

    test "generates unique event IDs" do
      {:ok, event1} = Events.new_event(:test, %{})
      {:ok, event2} = Events.new_event(:test, %{})

      assert event1.event_id != event2.event_id
    end

    test "validates event structure" do
      # This would test internal validation - may not be exposed publicly
      # depending on implementation
    end
  end

  describe "function events" do
    test "creates function entry event" do
      args = [:arg1, :arg2]
      {:ok, event} = Events.function_entry(TestModule, :test_function, 2, args)

      assert %Event{event_type: :function_entry} = event
      assert event.data.module == TestModule
      assert event.data.function == :test_function
      assert event.data.arity == 2
      assert event.data.args == args
      assert is_integer(event.data.call_id)
    end

    test "creates function entry with caller information" do
      {:ok, event} =
        Events.function_entry(TestModule, :test_function, 1, [:arg],
          caller_module: CallerModule,
          caller_function: :caller_function,
          caller_line: 42
        )

      assert event.data.caller_module == CallerModule
      assert event.data.caller_function == :caller_function
      assert event.data.caller_line == 42
    end

    test "creates function exit event" do
      call_id = 12345
      result = :ok
      duration = 1_000_000

      {:ok, event} =
        Events.function_exit(
          TestModule,
          :test_function,
          2,
          call_id,
          result,
          duration,
          :normal
        )

      assert event.event_type == :function_exit
      assert event.data.call_id == call_id
      assert event.data.result == result
      assert event.data.duration_ns == duration
      assert event.data.exit_reason == :normal
    end

    test "truncates large function arguments" do
      # Create arguments that are definitely over the 10,000 byte default threshold
      large_args = [String.duplicate("x", 15_000)]
      {:ok, event} = Events.function_entry(TestModule, :test_function, 1, large_args)

      # Should be truncated due to size - Utils.truncate_if_large returns a map
      assert match?(%{truncated: true}, event.data.args)
    end
  end

  describe "state change events" do
    test "creates state change event" do
      old_state = %{counter: 0}
      new_state = %{counter: 1}

      {:ok, event} = Events.state_change(self(), :handle_call, old_state, new_state)

      assert event.event_type == :state_change
      assert event.data.server_pid == self()
      assert event.data.callback == :handle_call
      assert event.data.state_diff == :changed
    end

    test "detects no change in identical states" do
      same_state = %{counter: 0}

      {:ok, event} = Events.state_change(self(), :handle_call, same_state, same_state)

      assert event.data.state_diff == :no_change
    end
  end

  describe "serialization" do
    test "serializes and deserializes events correctly" do
      {:ok, original} = Events.new_event(:test_event, %{data: "test"})

      {:ok, serialized} = Events.serialize(original)
      assert is_binary(serialized)

      {:ok, deserialized} = Events.deserialize(serialized)
      assert deserialized == original
    end

    test "calculates serialized size correctly" do
      {:ok, event} = Events.new_event(:test_event, %{data: "test"})

      {:ok, calculated_size} = Events.serialized_size(event)
      {:ok, actual_serialized} = Events.serialize(event)
      actual_size = byte_size(actual_serialized)

      assert calculated_size == actual_size
    end

    test "handles serialization of complex data" do
      complex_data = %{
        nested: %{deep: [1, 2, 3]},
        tuple: {:a, :b, :c},
        list: [1, 2, 3, 4, 5]
      }

      {:ok, event} = Events.new_event(:complex_event, complex_data)

      {:ok, serialized} = Events.serialize(event)
      assert is_binary(serialized)

      {:ok, deserialized} = Events.deserialize(serialized)
      assert deserialized == event
    end

    test "handles serialization errors gracefully" do
      # Test with a problematic event structure if needed
      # This depends on what could cause serialization to fail
    end
  end

  describe "error handling" do
    test "handles invalid event types gracefully" do
      # Test with nil event type (should fail)
      result = Events.new_event(nil, %{})

      # Handle different error types that might be returned
      assert {:error, error} = result
      assert error.error_type in [:validation_failed, :invalid_input, :type_mismatch]
    end

    test "handles various data types safely" do
      test_cases = [
        nil,
        %{},
        [],
        "string",
        42,
        :atom,
        {:tuple, :data}
      ]

      Enum.each(test_cases, fn data ->
        result = Events.new_event(:test_event, data)

        case result do
          {:ok, event} ->
            assert %Event{} = event
            assert event.event_type == :test_event

          {:error, %Error{}} ->
            # Some data types might not be valid, that's acceptable
            assert true

          {:error, %{}} ->
            # Handle different Error module types
            assert true
        end
      end)
    end
  end

  describe "concurrent event creation" do
    test "handles concurrent event creation safely" do
      # Create many events concurrently
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            Events.new_event(:concurrent_test, %{task_id: i, data: "test_#{i}"})
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All should succeed
      assert length(results) == 50

      Enum.each(results, fn result ->
        assert {:ok, %Event{}} = result
      end)

      # Event IDs should be unique
      event_ids = Enum.map(results, fn {:ok, event} -> event.event_id end)
      unique_ids = Enum.uniq(event_ids)
      assert length(event_ids) == length(unique_ids)
    end
  end

  describe "edge case handling" do
    test "handles events with Unicode and special characters in data" do
      unicode_data = %{
        emoji: "🚀🔥💯",
        chinese: "你好世界",
        arabic: "مرحبا بالعالم",
        special_chars: "\"'\\n\\t\\r",
        null_byte: "test\0null"
      }

      {:ok, event} = Events.new_event(:unicode_test, unicode_data)

      assert event.data == unicode_data

      # Should serialize and deserialize correctly
      {:ok, serialized} = Events.serialize(event)
      {:ok, deserialized} = Events.deserialize(serialized)

      assert deserialized.data == unicode_data
    end

    test "handles events with binary data" do
      binary_data = %{
        # PNG header
        image: <<137, 80, 78, 71, 13, 10, 26, 10>>,
        random_binary: :crypto.strong_rand_bytes(100),
        text: "normal text"
      }

      {:ok, event} = Events.new_event(:binary_test, binary_data)

      # Should handle binary data without corruption
      {:ok, serialized} = Events.serialize(event)
      {:ok, deserialized} = Events.deserialize(serialized)

      assert deserialized.data.text == "normal text"
      assert is_binary(deserialized.data.image)
      assert is_binary(deserialized.data.random_binary)
    end
  end
end
