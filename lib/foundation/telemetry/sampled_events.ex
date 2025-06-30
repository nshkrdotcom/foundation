defmodule Foundation.Telemetry.SampledEvents do
  @moduledoc """
  Convenience module for emitting sampled telemetry events.

  This module provides macros and functions to easily emit telemetry events
  with automatic sampling, reducing boilerplate code.

  ## Usage

      defmodule MyModule do
        use Foundation.Telemetry.SampledEvents, prefix: [:my_app]
        
        def process_request(request) do
          emit_start(:request_processing, %{request_id: request.id})
          
          result = do_processing(request)
          
          emit_stop(:request_processing, 
            %{request_id: request.id},
            %{status: :success}
          )
          
          result
        end
        
        def batch_operation(items) do
          # Use span for automatic start/stop
          span :batch_processing, %{batch_size: length(items)} do
            Enum.map(items, &process_item/1)
          end
        end
      end
  """

  @doc false
  defmacro __using__(opts) do
    prefix = Keyword.get(opts, :prefix, [])

    quote do
      import Foundation.Telemetry.SampledEvents

      @telemetry_prefix unquote(prefix)

      @doc false
      def __telemetry_prefix__, do: @telemetry_prefix
    end
  end

  @doc """
  Emits a start event with sampling.

  ## Example

      emit_start(:operation, %{user_id: 123})
  """
  defmacro emit_start(event_name, metadata \\ quote(do: %{})) do
    quote do
      event = __telemetry_prefix__() ++ [unquote(event_name), :start]
      measurements = %{timestamp: System.system_time()}
      Foundation.Telemetry.Sampler.execute(event, measurements, unquote(metadata))
    end
  end

  @doc """
  Emits a stop event with sampling.

  ## Example

      start_time = System.monotonic_time()
      # ... do work ...
      emit_stop(:operation, 
        %{duration: System.monotonic_time() - start_time},
        %{user_id: 123, status: :success}
      )
  """
  defmacro emit_stop(event_name, measurements \\ quote(do: %{}), metadata \\ quote(do: %{})) do
    quote do
      event = __telemetry_prefix__() ++ [unquote(event_name), :stop]
      default_measurements = %{timestamp: System.system_time()}
      final_measurements = Map.merge(default_measurements, unquote(measurements))
      Foundation.Telemetry.Sampler.execute(event, final_measurements, unquote(metadata))
    end
  end

  @doc """
  Emits a single event with sampling.

  ## Example

      emit_event(:cache_hit, 
        %{latency: 150},
        %{key: "user:123", hit: true}
      )
  """
  defmacro emit_event(event_name, measurements \\ quote(do: %{}), metadata \\ quote(do: %{})) do
    quote do
      event = __telemetry_prefix__() ++ [unquote(event_name)]
      Foundation.Telemetry.Sampler.execute(event, unquote(measurements), unquote(metadata))
    end
  end

  @doc """
  Executes a block of code with automatic start/stop events.

  ## Example

      span :database_query, %{query: "SELECT *"} do
        # Your code here
        {:ok, results}
      end
  """
  defmacro span(event_name, metadata \\ quote(do: %{}), do: block) do
    quote do
      start_time = System.monotonic_time()
      start_metadata = Map.put(unquote(metadata), :span_id, make_ref())

      emit_start(unquote(event_name), start_metadata)

      try do
        result = unquote(block)

        emit_stop(
          unquote(event_name),
          %{duration: System.monotonic_time() - start_time},
          Map.merge(start_metadata, %{status: :ok})
        )

        result
      rescue
        exception ->
          emit_stop(
            unquote(event_name),
            %{duration: System.monotonic_time() - start_time},
            Map.merge(start_metadata, %{
              status: :error,
              error: Exception.format(:error, exception)
            })
          )

          reraise exception, __STACKTRACE__
      end
    end
  end

  @doc """
  Conditionally emits an event based on a condition.

  ## Example

      emit_if slow_query?, :slow_query_detected,
        %{duration: query_time},
        %{query: sql, threshold: 1000}
  """
  defmacro emit_if(
             condition,
             event_name,
             measurements \\ quote(do: %{}),
             metadata \\ quote(do: %{})
           ) do
    quote do
      if unquote(condition) do
        emit_event(unquote(event_name), unquote(measurements), unquote(metadata))
      end
    end
  end

  @doc """
  Emits an event only if it hasn't been emitted recently (deduplication).

  ## Example

      emit_once_per :error_notification, :timer.minutes(5),
        %{timestamp: System.system_time()},
        %{error_type: :database_connection_failed}
  """
  def emit_once_per(event_name, interval_ms, measurements, metadata, prefix \\ []) do
    key = {prefix ++ [event_name], metadata}
    now = System.monotonic_time(:millisecond)

    case Process.get({:telemetry_dedup, key}) do
      nil ->
        # First time
        Process.put({:telemetry_dedup, key}, now)
        event = prefix ++ [event_name]
        Foundation.Telemetry.Sampler.execute(event, measurements, metadata)

      last_emit when now - last_emit >= interval_ms ->
        # Enough time has passed
        Process.put({:telemetry_dedup, key}, now)
        event = prefix ++ [event_name]
        Foundation.Telemetry.Sampler.execute(event, measurements, metadata)

      _ ->
        # Too soon, skip
        :ok
    end
  end

  @doc """
  Batches multiple events and emits a summary.

  ## Example

      batch_events :item_processed, 100, :timer.seconds(5) do
        %{
          count: batch_size,
          avg_duration: avg_duration,
          timestamp: System.system_time()
        }
      end
  """
  defmacro batch_events(event_name, batch_size, timeout_ms, do: summary_fn) do
    quote do
      batch_key = {:telemetry_batch, __telemetry_prefix__() ++ [unquote(event_name)]}

      {batch, last_emit} = Process.get(batch_key, {[], System.monotonic_time(:millisecond)})
      now = System.monotonic_time(:millisecond)

      new_batch = [unquote(summary_fn) | batch]

      if length(new_batch) >= unquote(batch_size) or now - last_emit >= unquote(timeout_ms) do
        # Emit batch summary
        summary = summarize_batch(new_batch)
        emit_event(unquote(event_name), summary, %{batch_size: length(new_batch)})

        # Reset batch
        Process.put(batch_key, {[], now})
      else
        # Add to batch
        Process.put(batch_key, {new_batch, last_emit})
      end
    end
  end
end
