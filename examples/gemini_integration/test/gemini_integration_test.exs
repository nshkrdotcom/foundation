defmodule GeminiIntegrationTest do
  use ExUnit.Case
  doctest GeminiIntegration

  test "Foundation integration is available" do
    # Test that Foundation services are available
    assert Foundation.available?()
  end

  test "Gemini adapter is properly setup" do
    # The adapter should be attached to telemetry events
    handlers = :telemetry.list_handlers([])
    adapter_handler = Enum.find(handlers, fn handler ->
      handler.id == "foundation-gemini-adapter"
    end)

    assert adapter_handler != nil
  end
end
