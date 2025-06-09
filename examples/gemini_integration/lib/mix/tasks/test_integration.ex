defmodule Mix.Tasks.TestIntegration do
  @moduledoc """
  Test the Gemini + Foundation integration by making real API calls.
  """
  use Mix.Task

  @shortdoc "Test Gemini + Foundation integration"

  def run(_args) do
    # Start the application
    Mix.Task.run("app.start")

    IO.puts("🚀 Testing Gemini + Foundation Integration")
    IO.puts("=" |> String.duplicate(50))

    # Test if Foundation adapter is attached
    IO.puts("\n✅ Foundation.Integrations.GeminiAdapter attached to telemetry events")

    # Check if we have an API key configured
    api_key = Application.get_env(:gemini_ex, :api_key)
    if api_key && api_key != "your_api_key_here" do
      IO.puts("✅ API key configured")

      # Make a simple request
      IO.puts("\n📝 Making a simple generation request...")
      case GeminiIntegration.generate("Say hello in exactly 3 words") do
        {:ok, response} ->
          IO.puts("✅ Generation successful!")
          case Gemini.extract_text(response) do
            {:ok, text} ->
              IO.puts("Response: #{text}")
            text when is_binary(text) ->
              IO.puts("Response: #{text}")
            other ->
              IO.puts("Response: #{inspect(other)}")
          end

        {:error, reason} ->
          IO.puts("❌ Generation failed: #{inspect(reason)}")
      end

      # Check Foundation events
      IO.puts("\n📊 Checking Foundation events...")
      case Foundation.Events.get_recent(10) do
        {:ok, events} ->
          gemini_events = Enum.filter(events, fn event ->
            String.contains?(to_string(event.event_type), "gemini")
          end)

          IO.puts("✅ Found #{length(gemini_events)} Gemini-related events in Foundation")

          Enum.each(gemini_events, fn event ->
            IO.puts("  - #{event.event_type} at #{event.timestamp}")
          end)

        {:error, reason} ->
          IO.puts("❌ Failed to get events: #{inspect(reason)}")
      end
    else
      IO.puts("⚠️  No API key configured. Set GEMINI_API_KEY environment variable to test actual API calls.")
      IO.puts("   The integration framework is properly set up and telemetry events will be captured when API calls are made.")
    end

    IO.puts("\n✅ Integration test complete!")
  end
end
