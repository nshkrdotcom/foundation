defmodule Foundation.Telemetry.OpenTelemetryBridge do
  @moduledoc """
  Bridge between Foundation telemetry and OpenTelemetry.

  This module automatically converts Foundation telemetry events into
  OpenTelemetry spans and metrics, enabling distributed tracing across
  services.

  ## Setup

  Add to your application supervision tree:

      children = [
        Foundation.Telemetry.OpenTelemetryBridge
      ]

  ## Configuration

      config :foundation, :opentelemetry,
        enabled: true,
        service_name: "my-service",
        resource_attributes: %{
          "service.version" => "1.0.0",
          "deployment.environment" => "production"
        }
  """

  use GenServer
  require Logger

  @span_events [
    [:foundation, :span, :start],
    [:foundation, :span, :stop],
    [:foundation, :span, :attributes],
    [:foundation, :span, :event],
    [:foundation, :span, :link]
  ]

  @metric_events [
    [:foundation, :cache, :hit],
    [:foundation, :cache, :miss],
    [:foundation, :resource_manager, :acquired],
    [:foundation, :resource_manager, :released],
    [:foundation, :resource_manager, :denied],
    [:jido_system, :task, :started],
    [:jido_system, :task, :completed],
    [:jido_system, :task, :failed]
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    if enabled?() do
      # Create ETS table for context storage
      :ets.new(:foundation_otel_contexts, [:set, :public, :named_table])

      # Register table with ResourceManager if available
      if Process.whereis(Foundation.ResourceManager) do
        Foundation.ResourceManager.monitor_table(:foundation_otel_contexts)
      end

      # Schedule periodic cleanup of stale contexts
      cleanup_timer = Process.send_after(self(), :cleanup_stale_contexts, 60_000)

      # Attach to span events
      :telemetry.attach_many(
        "foundation-otel-spans",
        @span_events,
        &__MODULE__.handle_span_event/4,
        %{}
      )

      # Attach to metric events
      :telemetry.attach_many(
        "foundation-otel-metrics",
        @metric_events,
        &__MODULE__.handle_metric_event/4,
        %{}
      )

      Logger.info("Foundation OpenTelemetry bridge started")

      {:ok,
       %{
         spans: %{},
         service_name: Keyword.get(opts, :service_name, service_name()),
         resource_attributes: Keyword.get(opts, :resource_attributes, %{}),
         max_context_age_ms: Keyword.get(opts, :max_context_age_ms, 300_000), # 5 minutes default
         cleanup_timer: cleanup_timer
       }}
    else
      Logger.info("Foundation OpenTelemetry bridge disabled")
      :ignore
    end
  end

  @impl true
  def terminate(_reason, state) do
    :telemetry.detach("foundation-otel-spans")
    :telemetry.detach("foundation-otel-metrics")
    
    # Cancel cleanup timer if it exists
    if is_map(state) and Map.has_key?(state, :cleanup_timer) and state.cleanup_timer do
      Process.cancel_timer(state.cleanup_timer)
    end
    
    # Clean up ETS table if it exists
    if :ets.whereis(:foundation_otel_contexts) != :undefined do
      :ets.delete(:foundation_otel_contexts)
    end
    
    :ok
  end

  # Span event handlers

  def handle_span_event([:foundation, :span, :start], measurements, metadata, _config) do
    if otel_available?() do
      # Create OpenTelemetry span
      span_name = to_string(metadata.span_name)

      # Set parent context if available
      parent_ctx =
        case metadata[:parent_id] do
          nil -> :undefined
          parent_id -> get_otel_context(parent_id)
        end

      # Start span
      ctx =
        otel_start_span(span_name, %{
          attributes: build_span_attributes(metadata),
          start_time: measurements.timestamp,
          parent: parent_ctx
        })

      # Store context mapping
      store_otel_context(metadata.span_id, ctx)

      # Set as current span
      otel_set_current_span(ctx)
    end
  rescue
    e ->
      Logger.debug("Error handling span start: #{inspect(e)}")
  end

  def handle_span_event([:foundation, :span, :stop], _measurements, metadata, _config) do
    if otel_available?() do
      # Get span context
      case get_otel_context(metadata.span_id) do
        nil ->
          Logger.debug("No OpenTelemetry context found for span #{metadata.span_id}")

        ctx ->
          # Set status
          status =
            case metadata.status do
              :ok -> :ok
              :error -> {:error, metadata[:error] || "Unknown error"}
              other -> other
            end

          otel_span_set_status(ctx, status)

          # End span
          otel_span_end_span(ctx)

          # Clean up context
          delete_otel_context(metadata.span_id)
      end
    end
  rescue
    e ->
      Logger.debug("Error handling span stop: #{inspect(e)}")
  end

  def handle_span_event([:foundation, :span, :attributes], _measurements, metadata, _config) do
    if otel_available?() do
      case get_otel_context(metadata.span_id) do
        nil ->
          :ok

        ctx ->
          attributes = Map.drop(metadata, [:span_id, :span_name])
          otel_span_set_attributes(ctx, attributes)
      end
    end
  rescue
    e ->
      Logger.debug("Error handling span attributes: #{inspect(e)}")
  end

  def handle_span_event([:foundation, :span, :event], measurements, metadata, _config) do
    if otel_available?() do
      case get_otel_context(metadata.span_id) do
        nil ->
          :ok

        ctx ->
          attributes = Map.drop(metadata, [:span_id, :span_name, :event_name])

          otel_span_add_event(
            ctx,
            to_string(metadata.event_name),
            attributes,
            measurements.timestamp
          )
      end
    end
  rescue
    e ->
      Logger.debug("Error handling span event: #{inspect(e)}")
  end

  def handle_span_event([:foundation, :span, :link], _measurements, metadata, _config) do
    if otel_available?() do
      case get_otel_context(metadata.span_id) do
        nil ->
          :ok

        ctx ->
          # Add link to span
          link = %{
            trace_id: metadata.linked_trace_id,
            span_id: metadata.linked_span_id,
            attributes: Map.drop(metadata, [:span_id, :linked_trace_id, :linked_span_id])
          }

          otel_span_add_link(ctx, link)
      end
    end
  rescue
    e ->
      Logger.debug("Error handling span link: #{inspect(e)}")
  end

  # Metric event handlers

  def handle_metric_event(event, measurements, metadata, _config) do
    if otel_available?() do
      metric_name = event_to_metric_name(event)

      # Record metric based on event type
      case event do
        [:foundation, :cache, action] when action in [:hit, :miss] ->
          # Counter metric
          counter =
            otel_meter_create_counter(
              metric_name,
              %{
                description: "Cache #{action} count",
                unit: "1"
              }
            )

          otel_meter_add(counter, 1, metadata)

          # Histogram for duration
          if measurements[:duration] do
            histogram =
              otel_meter_create_histogram(
                "#{metric_name}_duration",
                %{
                  description: "Cache #{action} duration",
                  unit: "us"
                }
              )

            otel_meter_record(histogram, measurements.duration, metadata)
          end

        [:foundation, :resource_manager, action] ->
          # Counter for resource events
          counter =
            otel_meter_create_counter(
              metric_name,
              %{
                description: "Resource #{action} count",
                unit: "1"
              }
            )

          otel_meter_add(counter, 1, metadata)

        [:jido_system, :task, action] ->
          # Counter for task events
          counter =
            otel_meter_create_counter(
              metric_name,
              %{
                description: "Task #{action} count",
                unit: "1"
              }
            )

          otel_meter_add(counter, 1, metadata)

          # Histogram for task duration
          if action == :completed and measurements[:duration] do
            histogram =
              otel_meter_create_histogram(
                "#{metric_name}_duration",
                %{
                  description: "Task completion duration",
                  unit: "us"
                }
              )

            otel_meter_record(histogram, measurements.duration, metadata)
          end

        _ ->
          :ok
      end
    end
  rescue
    e ->
      Logger.debug("Error handling metric event: #{inspect(e)}")
  end

  # Helper functions

  defp enabled? do
    Application.get_env(:foundation, :opentelemetry, [])
    |> Keyword.get(:enabled, false)
  end

  defp otel_available? do
    Code.ensure_loaded?(:otel_tracer) and Code.ensure_loaded?(:otel_span) and
      Code.ensure_loaded?(:otel_meter)
  end

  defp service_name do
    Application.get_env(:foundation, :opentelemetry, [])
    |> Keyword.get(:service_name, "foundation")
  end

  defp build_span_attributes(metadata) do
    base_attrs = %{
      "service.name" => service_name(),
      "span.kind" => "internal",
      "foundation.component" => extract_component(metadata)
    }

    # Add custom attributes
    custom_attrs = Map.drop(metadata, [:span_id, :span_name, :parent_id, :trace_id])

    Map.merge(base_attrs, stringify_keys(custom_attrs))
  end

  defp extract_component(metadata) do
    case metadata.span_name do
      name when is_atom(name) ->
        name
        |> Atom.to_string()
        |> String.split("_")
        |> List.first()

      name when is_binary(name) ->
        name
        |> String.split("_")
        |> List.first()

      _ ->
        "unknown"
    end
  end

  defp event_to_metric_name(event) do
    event
    |> Enum.join(".")
    |> String.replace("_", ".")
  end

  defp stringify_keys(map) do
    Map.new(map, fn {k, v} ->
      {to_string(k), stringify_value(v)}
    end)
  end

  defp stringify_value(v) when is_binary(v), do: v
  defp stringify_value(v) when is_atom(v), do: to_string(v)
  defp stringify_value(v) when is_number(v), do: v
  defp stringify_value(v), do: inspect(v)

  # Context storage using ETS

  defp store_otel_context(span_id, ctx) do
    timestamp = System.monotonic_time(:millisecond)
    :ets.insert(:foundation_otel_contexts, {span_id, {ctx, timestamp}})
  end

  defp get_otel_context(span_id) do
    case :ets.lookup(:foundation_otel_contexts, span_id) do
      [{^span_id, {ctx, _timestamp}}] -> ctx
      [] -> nil
    end
  end

  defp delete_otel_context(span_id) do
    :ets.delete(:foundation_otel_contexts, span_id)
  end

  @impl true
  def handle_call({:get_context, span_id}, _from, state) do
    {:reply, get_otel_context(span_id), state}
  end

  @impl true
  def handle_info(:cleanup_stale_contexts, state) do
    # Clean up contexts older than max_context_age_ms
    now = System.monotonic_time(:millisecond)
    max_age = state.max_context_age_ms
    
    # Find and delete stale contexts
    stale_contexts = :ets.foldl(
      fn {span_id, {_ctx, timestamp}}, acc ->
        if now - timestamp > max_age do
          [{span_id, timestamp} | acc]
        else
          acc
        end
      end,
      [],
      :foundation_otel_contexts
    )
    
    # Delete stale contexts
    Enum.each(stale_contexts, fn {span_id, _} ->
      :ets.delete(:foundation_otel_contexts, span_id)
    end)
    
    if length(stale_contexts) > 0 do
      Logger.debug("Cleaned up #{length(stale_contexts)} stale OpenTelemetry contexts")
    end
    
    # Schedule next cleanup
    new_timer = Process.send_after(self(), :cleanup_stale_contexts, 60_000)
    
    {:noreply, %{state | cleanup_timer: new_timer}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state) do
    # Clean up any orphaned contexts
    {:noreply, state}
  end

  # OpenTelemetry wrapper functions to avoid compile warnings

  defp otel_start_span(name, opts) do
    if function_exported?(:otel_tracer, :start_span, 2) do
      apply(:otel_tracer, :start_span, [name, opts])
    else
      nil
    end
  end

  defp otel_set_current_span(ctx) do
    if function_exported?(:otel_tracer, :set_current_span, 1) do
      apply(:otel_tracer, :set_current_span, [ctx])
    else
      :ok
    end
  end

  defp otel_span_set_status(ctx, status) do
    if function_exported?(:otel_span, :set_status, 2) do
      apply(:otel_span, :set_status, [ctx, status])
    else
      :ok
    end
  end

  defp otel_span_end_span(ctx) do
    if function_exported?(:otel_span, :end_span, 1) do
      apply(:otel_span, :end_span, [ctx])
    else
      :ok
    end
  end

  defp otel_span_set_attributes(ctx, attributes) do
    if function_exported?(:otel_span, :set_attributes, 2) do
      apply(:otel_span, :set_attributes, [ctx, attributes])
    else
      :ok
    end
  end

  defp otel_span_add_event(ctx, name, attributes, timestamp) do
    if function_exported?(:otel_span, :add_event, 4) do
      apply(:otel_span, :add_event, [ctx, name, attributes, timestamp])
    else
      :ok
    end
  end

  defp otel_span_add_link(ctx, link) do
    if function_exported?(:otel_span, :add_link, 2) do
      apply(:otel_span, :add_link, [ctx, link])
    else
      :ok
    end
  end

  defp otel_meter_create_counter(name, opts) do
    if function_exported?(:otel_meter, :create_counter, 2) do
      apply(:otel_meter, :create_counter, [name, opts])
    else
      %{}
    end
  end

  defp otel_meter_add(counter, value, metadata) do
    if function_exported?(:otel_meter, :add, 3) and is_map(counter) and map_size(counter) > 0 do
      apply(:otel_meter, :add, [counter, value, metadata])
    else
      :ok
    end
  end

  defp otel_meter_create_histogram(name, opts) do
    if function_exported?(:otel_meter, :create_histogram, 2) do
      apply(:otel_meter, :create_histogram, [name, opts])
    else
      %{}
    end
  end

  defp otel_meter_record(histogram, value, metadata) do
    if function_exported?(:otel_meter, :record, 3) and is_map(histogram) and map_size(histogram) > 0 do
      apply(:otel_meter, :record, [histogram, value, metadata])
    else
      :ok
    end
  end
end
