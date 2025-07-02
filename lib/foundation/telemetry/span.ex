defmodule Foundation.Telemetry.Span do
  @moduledoc """
  Distributed tracing support for Foundation telemetry.

  This module provides span-based tracing capabilities that integrate with
  OpenTelemetry and other distributed tracing systems. It allows tracking
  operations across multiple services and processes.

  ## Usage

      import Foundation.Telemetry.Span

      with_span :cache_operation, %{cache_key: "user:123"} do
        # Your code here
        {:ok, result}
      end

  ## Span Attributes

  Common attributes added to spans:
  - `service.name` - The service generating the span
  - `span.kind` - Type of span (internal, client, server)
  - `foundation.component` - Which Foundation component
  - Custom attributes passed in metadata
  """

  require Logger
  alias Foundation.Telemetry.SpanManager
  alias Foundation.FeatureFlags

  @type span_name :: atom() | String.t()
  @type span_metadata :: map()
  @type span_ref :: reference()

  @doc """
  Executes a function within a traced span.

  ## Examples

      with_span :database_query, %{query: "SELECT * FROM users"} do
        Database.query("SELECT * FROM users")
      end

      # With explicit status
      with_span :api_call, %{endpoint: "/users"} do
        case HTTP.get("/users") do
          {:ok, response} -> {:ok, response}
          {:error, reason} -> {:error, reason}
        end
      end
  """
  defmacro with_span(name, metadata \\ Macro.escape(%{}), do: block) do
    quote do
      Foundation.Telemetry.Span.start_span(unquote(name), unquote(metadata))

      try do
        result = unquote(block)
        Foundation.Telemetry.Span.end_span(:ok, %{})
        result
      rescue
        exception ->
          Foundation.Telemetry.Span.end_span(
            :error,
            %{
              error: Exception.format(:error, exception),
              stacktrace: Exception.format_stacktrace(__STACKTRACE__)
            }
          )

          reraise exception, __STACKTRACE__
      catch
        kind, reason ->
          Foundation.Telemetry.Span.end_span(
            :error,
            %{
              error: Exception.format(kind, reason),
              stacktrace: Exception.format_stacktrace(__STACKTRACE__)
            }
          )

          :erlang.raise(kind, reason, __STACKTRACE__)
      end
    end
  end

  @doc """
  Function version of with_span for tests and programmatic usage.
  Executes a function within a traced span.
  """
  @spec with_span_fun(span_name(), span_metadata(), (-> term())) :: term()
  def with_span_fun(name, metadata, fun) when is_function(fun, 0) do
    span_id = start_span(name, metadata)
    
    try do
      result = fun.()
      end_span(span_id)
      result
    rescue
      exception ->
        end_span(:error, %{
          error: Exception.format(:error, exception),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        })
        reraise exception, __STACKTRACE__
    catch
      kind, reason ->
        end_span(:error, %{
          error: Exception.format(kind, reason),
          stacktrace: Exception.format_stacktrace(__STACKTRACE__)
        })
        :erlang.raise(kind, reason, __STACKTRACE__)
    end
  end


  @doc """
  Starts a new span and pushes it onto the span stack.
  """
  @spec start_span(span_name(), span_metadata()) :: span_ref()
  def start_span(name, metadata \\ %{}) do
    span_id = make_ref()
    start_time = System.monotonic_time()
    parent_span = current_span()

    span = %{
      id: span_id,
      name: name,
      start_time: start_time,
      metadata: metadata,
      parent_id: parent_span[:id],
      trace_id: parent_span[:trace_id] || generate_trace_id()
    }

    # Push onto span stack using either SpanManager or Process dictionary
    if FeatureFlags.enabled?(:use_genserver_span_management) do
      SpanManager.push_span(span)
    else
      push_span_legacy(span)
    end

    # Emit span started event
    :telemetry.execute(
      [:foundation, :span, :start],
      %{timestamp: System.system_time()},
      Map.merge(metadata, %{
        span_id: span_id,
        span_name: name,
        parent_id: span[:parent_id],
        trace_id: span[:trace_id]
      })
    )

    span_id
  end

  @doc """
  Ends a specific span by span_id (simplified API for tests).
  """
  @spec end_span(span_ref()) :: :ok
  def end_span(span_id) when is_reference(span_id) do
    end_span(:ok, %{target_span_id: span_id})
  end

  @doc """
  Ends the current span and pops it from the stack.
  """
  @spec end_span(atom(), map()) :: :ok
  def end_span(status \\ :ok, additional_metadata \\ %{}) do
    span = if FeatureFlags.enabled?(:use_genserver_span_management) do
      SpanManager.pop_span()
    else
      pop_span_legacy()
    end

    case span do
      nil ->
        Logger.warning("No active span to end")
        :ok

      span ->
        duration = System.monotonic_time() - span.start_time

        # Emit span end event
        :telemetry.execute(
          [:foundation, :span, :stop],
          %{
            duration: duration,
            timestamp: System.system_time()
          },
          Map.merge(
            span.metadata,
            Map.merge(additional_metadata, %{
              span_id: span.id,
              span_name: span.name,
              parent_id: span.parent_id,
              trace_id: span.trace_id,
              status: status
            })
          )
        )

        :ok
    end
  end

  @doc """
  Adds attributes to the current span.
  """
  @spec add_attributes(map()) :: :ok
  def add_attributes(attributes) do
    case SpanManager.update_top_span(fn span ->
           %{span | metadata: Map.merge(span.metadata, attributes)}
         end) do
      :error ->
        Logger.warning("No active span to add attributes to")
        :ok

      :ok ->
        # Get current span to emit event with proper metadata
        case current_span() do
          nil ->
            :ok

          span ->
            # Emit attribute event
            :telemetry.execute(
              [:foundation, :span, :attributes],
              %{timestamp: System.system_time()},
              Map.merge(attributes, %{
                span_id: span.id,
                span_name: span.name
              })
            )

            :ok
        end
    end
  end

  @doc """
  Records an event within the current span.
  """
  @spec record_event(String.t() | atom(), map()) :: :ok
  def record_event(name, attributes \\ %{}) do
    case current_span() do
      nil ->
        Logger.warning("No active span to record event in")
        :ok

      span ->
        :telemetry.execute(
          [:foundation, :span, :event],
          %{timestamp: System.system_time()},
          Map.merge(attributes, %{
            span_id: span.id,
            span_name: span.name,
            event_name: name
          })
        )

        :ok
    end
  end

  @doc """
  Returns the current active span or nil.
  """
  @spec current_span() :: map() | nil
  def current_span do
    stack = if FeatureFlags.enabled?(:use_genserver_span_management) do
      SpanManager.get_stack()
    else
      get_stack_legacy()
    end

    case stack do
      [] -> nil
      [span | _] -> span
    end
  end

  @doc """
  Returns the current trace ID or nil.
  """
  @spec current_trace_id() :: String.t() | nil
  def current_trace_id do
    case current_span() do
      nil -> nil
      span -> span.trace_id
    end
  end

  @doc """
  Propagates span context to another process.

  ## Example

      Task.async(fn ->
        Foundation.Telemetry.Span.with_propagated_context(context, fn ->
          # This runs with the same trace context
          do_work()
        end)
      end)
  """
  @spec propagate_context() ::
          %{trace_id: String.t(), parent_id: reference(), span_stack: list()} | %{}
  def propagate_context do
    case current_span() do
      nil ->
        %{}

      span ->
        stack = if FeatureFlags.enabled?(:use_genserver_span_management) do
          SpanManager.get_stack()
        else
          get_stack_legacy()
        end

        %{
          trace_id: span.trace_id,
          parent_id: span.id,
          span_stack: stack
        }
    end
  end

  @doc """
  Executes a function with propagated span context.
  """
  @spec with_propagated_context(map(), (-> any())) :: any()
  def with_propagated_context(context, fun) do
    case context do
      %{span_stack: stack} ->
        SpanManager.set_stack(stack)
        fun.()

      _ ->
        fun.()
    end
  end

  @doc """
  Creates a span link to another trace.
  """
  @spec link_span(String.t(), String.t(), map()) :: :ok
  def link_span(trace_id, span_id, attributes \\ %{}) do
    case current_span() do
      nil ->
        Logger.warning("No active span to create link from")
        :ok

      span ->
        :telemetry.execute(
          [:foundation, :span, :link],
          %{timestamp: System.system_time()},
          Map.merge(attributes, %{
            span_id: span.id,
            linked_trace_id: trace_id,
            linked_span_id: span_id
          })
        )

        :ok
    end
  end

  # Private functions

  defp generate_trace_id do
    :crypto.strong_rand_bytes(16)
    |> Base.encode16(case: :lower)
  end

  # Legacy process dictionary implementations (for feature flag fallback)
  
  @span_stack_key {__MODULE__, :span_stack}

  defp get_stack_legacy do
    Process.get(@span_stack_key, [])
  end

  defp set_stack_legacy(stack) do
    Process.put(@span_stack_key, stack)
  end

  defp push_span_legacy(span) do
    stack = get_stack_legacy()
    set_stack_legacy([span | stack])
  end

  defp pop_span_legacy do
    case get_stack_legacy() do
      [] -> nil
      [span | rest] ->
        set_stack_legacy(rest)
        span
    end
  end
end
