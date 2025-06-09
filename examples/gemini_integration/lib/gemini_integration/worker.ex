defmodule GeminiIntegration.Worker do
  @moduledoc """
  A worker that demonstrates using Gemini with Foundation integration.
  """

  use GenServer
  require Logger

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    Logger.info("GeminiIntegration.Worker started")
    {:ok, %{}}
  end

  @doc """
  Makes a sample Gemini API request to generate content.
  This will trigger telemetry events that Foundation will capture.
  """
  def generate_content(prompt) when is_binary(prompt) do
    GenServer.call(__MODULE__, {:generate_content, prompt})
  end

  @doc """
  Makes a streaming request to demonstrate streaming telemetry.
  """
  def stream_content(prompt) when is_binary(prompt) do
    GenServer.call(__MODULE__, {:stream_content, prompt})
  end

  @impl true
  def handle_call({:generate_content, prompt}, _from, state) do
    Logger.info("Generating content for prompt: #{prompt}")

    try do
      # This should emit telemetry events that Foundation captures
      case Gemini.generate(prompt) do
        {:ok, response} ->
          Logger.info("Successfully generated content")
          {:reply, {:ok, response}, state}

        {:error, reason} ->
          Logger.error("Failed to generate content: #{inspect(reason)}")
          {:reply, {:error, reason}, state}
      end
    rescue
      error ->
        Logger.error("Exception generating content: #{inspect(error)}")
        {:reply, {:error, error}, state}
    end
  end

  def handle_call({:stream_content, prompt}, _from, state) do
    Logger.info("Streaming content for prompt: #{prompt}")

    try do
      # This should emit streaming telemetry events
      case Gemini.stream_generate(prompt) do
        {:ok, stream} ->
          Logger.info("Successfully initiated content stream")
          {:reply, {:ok, stream}, state}

        {:error, reason} ->
          Logger.error("Failed to stream content: #{inspect(reason)}")
          {:reply, {:error, reason}, state}
      end
    rescue
      error ->
        Logger.error("Exception streaming content: #{inspect(error)}")
        {:reply, {:error, error}, state}
    end
  end
end
