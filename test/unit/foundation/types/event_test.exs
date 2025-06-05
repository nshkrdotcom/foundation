defmodule Foundation.Types.EventTest do
  use ExUnit.Case, async: true

  alias Foundation.Types.Event

  describe "new/0" do
    test "creates event with default values" do
      event = Event.new()

      assert %Event{} = event
      assert is_integer(event.event_id)
      assert event.event_type == :default
      assert is_integer(event.timestamp)
    end
  end

  describe "empty/0" do
    test "creates empty event structure with nil values" do
      event = Event.empty()

      assert %Event{} = event
      assert is_nil(event.event_id)
      assert is_nil(event.event_type)
      assert is_nil(event.timestamp)
    end
  end

  describe "new/1" do
    test "creates event with provided fields" do
      fields = [
        event_id: 123,
        event_type: :test,
        timestamp: 456_789,
        data: %{key: "value"}
      ]

      event = Event.new(fields)

      assert event.event_id == 123
      assert event.event_type == :test
      assert event.timestamp == 456_789
      assert event.data == %{key: "value"}
    end
  end
end
