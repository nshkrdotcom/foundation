# This code lives inside the `foundation` project.

# The `Code.ensure_loaded?/1` check will only pass if the user's
# project has `gemini_ex` in its dependency list.
if Code.ensure_loaded?(Gemini) do
  defmodule Foundation.Integrations.GeminiAdapter do
    @moduledoc """
    Telemetry handler to connect `gemini_ex` events to `foundation`.
    This module is only compiled if `gemini_ex` is a dependency.

    ## Usage

    In your application's `start/2` function:

        def start(_type, _args) do
          children = [
            Foundation.Application,
            # ... your other children
          ]

          {:ok, pid} = Supervisor.start_link(children, opts)

          # Enable the integration. It just works!
          Foundation.Integrations.GeminiAdapter.setup()

          {:ok, pid}
        end

    ## Events Captured

    This adapter captures the following telemetry events from Gemini:

    - `[:gemini, :request, :start]` - When a Gemini API request begins
    - `[:gemini, :request, :stop]` - When a Gemini API request completes successfully
    - `[:gemini, :request, :exception]` - When a Gemini API request fails
    - `[:gemini, :stream, :start]` - When a streaming request begins
    - `[:gemini, :stream, :chunk]` - When a streaming chunk is received
    - `[:gemini, :stream, :stop]` - When a streaming request completes
    - `[:gemini, :stream, :exception]` - When a streaming request fails

    ## Foundation Events Generated

    Each telemetry event is translated into corresponding Foundation events:

    - `:gemini_request_start`
    - `:gemini_request_stop`
    - `:gemini_request_exception`
    - `:gemini_stream_start`
    - `:gemini_stream_chunk`
    - `:gemini_stream_stop`
    - `:gemini_stream_exception`
    """

    require Foundation.Events
    require Logger

    def setup do
      events = [
        [:gemini, :request, :start],
        [:gemini, :request, :stop],
        [:gemini, :request, :exception],
        [:gemini, :stream, :start],
        [:gemini, :stream, :chunk],
        [:gemini, :stream, :stop],
        [:gemini, :stream, :exception]
      ]

      :telemetry.attach_many(
        "foundation-gemini-adapter",
        events,
        &__MODULE__.handle_event/4,
        nil
      )

      Logger.info(
        "Foundation.Integrations.GeminiAdapter: Successfully attached to Gemini telemetry events"
      )

      :ok
    end

    def handle_event([:gemini, :request, :start], measurements, metadata, _config) do
      # Translate the telemetry event into a Foundation event
      data = Map.merge(measurements, metadata)

      try do
        Foundation.Events.new_event(:gemini_request_start, data)
        |> Foundation.Events.store()

        Logger.debug("Captured Gemini request start: #{inspect(metadata)}")
      rescue
        error ->
          Logger.error("Failed to store gemini_request_start event: #{inspect(error)}")
      end
    end

    def handle_event([:gemini, :request, :stop], measurements, metadata, _config) do
      data = Map.merge(measurements, metadata)

      try do
        Foundation.Events.new_event(:gemini_request_stop, data)
        |> Foundation.Events.store()

        # Also emit telemetry metrics if available
        if Map.has_key?(measurements, :duration) do
          Foundation.Telemetry.emit_histogram(
            [:gemini, :request, :duration],
            measurements.duration,
            metadata
          )
        end

        Logger.debug(
          "Captured Gemini request stop: duration=#{Map.get(measurements, :duration, "N/A")}ms"
        )
      rescue
        error ->
          Logger.error("Failed to store gemini_request_stop event: #{inspect(error)}")
      end
    end

    def handle_event([:gemini, :request, :exception], measurements, metadata, _config) do
      data = Map.merge(measurements, metadata)

      try do
        Foundation.Events.new_event(:gemini_request_exception, data)
        |> Foundation.Events.store()

        # Emit error counter
        Foundation.Telemetry.emit_counter([:gemini, :request, :errors], metadata)

        Logger.warning(
          "Captured Gemini request exception: #{inspect(Map.get(metadata, :reason, "unknown"))}"
        )
      rescue
        error ->
          Logger.error("Failed to store gemini_request_exception event: #{inspect(error)}")
      end
    end

    def handle_event([:gemini, :stream, :start], measurements, metadata, _config) do
      data = Map.merge(measurements, metadata)

      try do
        Foundation.Events.new_event(:gemini_stream_start, data)
        |> Foundation.Events.store()

        Logger.debug("Captured Gemini stream start: #{inspect(metadata)}")
      rescue
        error ->
          Logger.error("Failed to store gemini_stream_start event: #{inspect(error)}")
      end
    end

    def handle_event([:gemini, :stream, :chunk], measurements, metadata, _config) do
      data = Map.merge(measurements, metadata)

      try do
        Foundation.Events.new_event(:gemini_stream_chunk, data)
        |> Foundation.Events.store()

        # Track streaming throughput
        if Map.has_key?(measurements, :chunk_size) do
          Foundation.Telemetry.emit_histogram(
            [:gemini, :stream, :chunk_size],
            measurements.chunk_size,
            metadata
          )
        end

        Logger.debug(
          "Captured Gemini stream chunk: size=#{Map.get(measurements, :chunk_size, "N/A")} bytes"
        )
      rescue
        error ->
          Logger.error("Failed to store gemini_stream_chunk event: #{inspect(error)}")
      end
    end

    def handle_event([:gemini, :stream, :stop], measurements, metadata, _config) do
      data = Map.merge(measurements, metadata)

      try do
        Foundation.Events.new_event(:gemini_stream_stop, data)
        |> Foundation.Events.store()

        # Track total streaming metrics
        if Map.has_key?(measurements, :total_duration) do
          Foundation.Telemetry.emit_histogram(
            [:gemini, :stream, :duration],
            measurements.total_duration,
            metadata
          )
        end

        if Map.has_key?(measurements, :total_chunks) do
          Foundation.Telemetry.emit_histogram(
            [:gemini, :stream, :chunks],
            measurements.total_chunks,
            metadata
          )
        end

        Logger.debug(
          "Captured Gemini stream stop: duration=#{Map.get(measurements, :total_duration, "N/A")}ms, chunks=#{Map.get(measurements, :total_chunks, "N/A")}"
        )
      rescue
        error ->
          Logger.error("Failed to store gemini_stream_stop event: #{inspect(error)}")
      end
    end

    def handle_event([:gemini, :stream, :exception], measurements, metadata, _config) do
      data = Map.merge(measurements, metadata)

      try do
        Foundation.Events.new_event(:gemini_stream_exception, data)
        |> Foundation.Events.store()

        # Emit error counter for streaming
        Foundation.Telemetry.emit_counter([:gemini, :stream, :errors], metadata)

        Logger.warning(
          "Captured Gemini stream exception: #{inspect(Map.get(metadata, :reason, "unknown"))}"
        )
      rescue
        error ->
          Logger.error("Failed to store gemini_stream_exception event: #{inspect(error)}")
      end
    end
  end
else
  # This `else` block is crucial. If `gemini_ex` is NOT a dependency,
  # we still define the module with a no-op `setup/0` function.
  # This prevents compilation errors if the user tries to call it.
  defmodule Foundation.Integrations.GeminiAdapter do
    @moduledoc """
    A no-op version of the Gemini adapter.
    The `gemini_ex` library is not present in the project's dependencies.

    When called, `setup/0` will return `:noop` and log that Gemini integration
    is not available.
    """

    require Logger

    def setup do
      Logger.info(
        "Foundation.Integrations.GeminiAdapter: Gemini integration not available (gemini_ex not in dependencies)"
      )

      :noop
    end
  end
end
