defmodule Foundation.Validation.EventValidatorTest do
  use ExUnit.Case, async: true

  alias Foundation.Types.Event
  alias Foundation.Validation.EventValidator

  describe "validate/1" do
    test "validates correct event" do
      event =
        Event.new(
          event_id: 123,
          event_type: :test,
          timestamp: System.monotonic_time(),
          wall_time: DateTime.utc_now(),
          node: Node.self(),
          pid: self(),
          data: %{key: "value"}
        )

      assert :ok = EventValidator.validate(event)
    end

    test "rejects event without required fields" do
      event = Event.empty()

      assert {:error, error} = EventValidator.validate(event)
      assert error.error_type == :validation_failed
      assert error.message == "Event ID cannot be nil"
    end

    test "rejects event with invalid field types" do
      event =
        Event.new(
          event_id: "not_an_integer",
          event_type: :test,
          timestamp: System.monotonic_time(),
          wall_time: DateTime.utc_now(),
          node: Node.self(),
          pid: self()
        )

      assert {:error, error} = EventValidator.validate(event)
      assert error.error_type == :type_mismatch
    end

    test "rejects event with too large data" do
      large_data = String.duplicate("x", 2_000_000)

      event =
        Event.new(
          event_id: 123,
          event_type: :test,
          timestamp: System.monotonic_time(),
          wall_time: DateTime.utc_now(),
          node: Node.self(),
          pid: self(),
          data: large_data
        )

      assert {:error, error} = EventValidator.validate(event)
      assert error.error_type == :data_too_large
    end
  end

  describe "validate_event_type/1" do
    test "validates allowed event types" do
      allowed_types = [:function_entry, :function_exit, :state_change, :spawn, :exit]

      for event_type <- allowed_types do
        assert :ok = EventValidator.validate_event_type(event_type)
      end
    end

    test "rejects invalid event type" do
      assert {:error, error} = EventValidator.validate_event_type(:invalid_type)
      assert error.error_type == :invalid_event_type
    end

    test "rejects non-atom event type" do
      assert {:error, error} = EventValidator.validate_event_type("not_atom")
      assert error.error_type == :type_mismatch
    end
  end
end
