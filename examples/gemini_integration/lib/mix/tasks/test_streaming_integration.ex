defmodule Mix.Tasks.TestStreamingIntegration do
  @moduledoc """
  Test the Gemini streaming + Foundation integration.
  """
  use Mix.Task

  @shortdoc "Test Gemini streaming + Foundation integration"

  def run(_args) do
    # Start the application
    Mix.Task.run("app.start")

    IO.puts("🌊 Testing Gemini Streaming + Foundation Integration")
    IO.puts("=" |> String.duplicate(55))

    # Check if we have an API key configured
    api_key = Application.get_env(:gemini_ex, :api_key)
    if api_key && api_key != "your_api_key_here" do
      IO.puts("✅ API key configured")

      # Make a streaming request
      IO.puts("\n🌊 Making a streaming generation request...")
      case GeminiIntegration.stream("Count from 1 to 5, one number per line") do
        {:ok, stream} ->
          IO.puts("✅ Streaming initiated!")
          IO.puts("Stream: #{inspect(stream)}")

        {:error, reason} ->
          IO.puts("❌ Streaming failed: #{inspect(reason)}")
      end

      # Wait a moment for events to be processed
      Process.sleep(1000)

      # Check Foundation events again
      IO.puts("\n📊 Checking Foundation events for telemetry capture...")
      case Foundation.Events.get_recent(20) do
        {:ok, events} ->
          gemini_events = Enum.filter(events, fn event ->
            event_type_str = to_string(event.event_type)
            String.contains?(event_type_str, "gemini") or String.contains?(event_type_str, "request") or String.contains?(event_type_str, "stream")
          end)

          IO.puts("✅ Found #{length(gemini_events)} potentially relevant events in Foundation")

          Enum.each(gemini_events, fn event ->
            IO.puts("  - #{event.event_type} at #{event.timestamp}")
          end)

          if length(gemini_events) == 0 do
            IO.puts("\n🔍 All recent events:")
            Enum.take(events, 5) |> Enum.each(fn event ->
              IO.puts("  - #{event.event_type} at #{event.timestamp}")
            end)
          end

        {:error, reason} ->
          IO.puts("❌ Failed to get events: #{inspect(reason)}")
      end
    else
      IO.puts("⚠️  No API key configured. Set GEMINI_API_KEY environment variable to test actual API calls.")
    end

    IO.puts("\n✅ Streaming integration test complete!")
  end
end
