defmodule GeminiIntegration do
  @moduledoc """
  GeminiIntegration demonstrates how to use Foundation with Gemini.

  This example shows:
  - How Foundation automatically captures Gemini telemetry events
  - How to make both synchronous and streaming Gemini requests
  - How to view the captured events in Foundation
  """

  alias GeminiIntegration.Worker

  @doc """
  Makes a simple content generation request.
  The telemetry will be automatically captured by Foundation.
  """
  def generate(prompt) when is_binary(prompt) do
    Worker.generate_content(prompt)
  end

  @doc """
  Makes a streaming content generation request.
  """
  def stream(prompt) when is_binary(prompt) do
    Worker.stream_content(prompt)
  end

  @doc """
  Demonstrates the integration by making several requests and showing
  how Foundation captures the events.
  """
  def demo do
    IO.puts("🚀 Starting Gemini + Foundation Integration Demo")
    IO.puts("=" |> String.duplicate(50))

    # Make a simple request
    IO.puts("\n📝 Making a simple generation request...")
    case generate("Write a haiku about programming") do
      {:ok, response} ->
        IO.puts("✅ Generation successful!")
        IO.puts("Response: #{inspect(response)}")

      {:error, reason} ->
        IO.puts("❌ Generation failed: #{inspect(reason)}")
    end

    # Make a streaming request
    IO.puts("\n🌊 Making a streaming request...")
    case stream("Explain Elixir GenServers in 2 sentences") do
      {:ok, stream} ->
        IO.puts("✅ Stream initiated!")
        IO.puts("Stream: #{inspect(stream)}")

      {:error, reason} ->
        IO.puts("❌ Stream failed: #{inspect(reason)}")
    end

    # Show Foundation events (if available)
    IO.puts("\n📊 Foundation Events:")
    try do
      events = Foundation.Events.get_recent(10)
      IO.puts("Found #{length(events)} recent events:")
      Enum.each(events, fn event ->
        IO.puts("  - #{event.type} at #{event.timestamp}")
      end)
    rescue
      _ ->
        IO.puts("  Foundation events not available yet (expected in dev)")
    end

    IO.puts("\n✨ Demo complete!")
  end
end
