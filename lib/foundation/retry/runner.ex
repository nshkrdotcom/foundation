defmodule Foundation.Retry.Runner do
  @moduledoc """
  Generic retry runner backed by `Foundation.Retry.Handler`.
  """

  alias Foundation.Retry.Handler

  @type telemetry_events :: %{
          optional(:start) => [atom()],
          optional(:stop) => [atom()],
          optional(:retry) => [atom()],
          optional(:failed) => [atom()]
        }

  @doc """
  Execute `fun` with retry semantics.

  Options:
    * `:handler` - `Foundation.Retry.Handler` to use
    * `:config` - config struct implementing `to_handler_opts/1`
    * `:handler_opts` - keyword options for `Handler.new/1`
    * `:sleep_fun` - sleep function (default: `&Process.sleep/1`)
    * `:before_attempt` - function invoked with the attempt number
    * `:retry_on` - function determining retry eligibility
    * `:delay_fun` - function to compute delay (arity 2: result, handler)
    * `:max_elapsed_ms` - maximum elapsed time before halting retries
    * `:time_fun` - time function (default: `&System.monotonic_time/1`)
    * `:rescue_exceptions` - whether to rescue exceptions (default: true)
    * `:telemetry_events` - map of telemetry event names
    * `:telemetry_metadata` - metadata merged into telemetry events
  """
  @spec run((-> result), keyword()) :: {:ok, term()} | {:error, term()}
        when result: term()
  def run(fun, opts \\ []) when is_function(fun, 0) do
    handler = build_handler(opts)
    context = build_context(opts)

    do_retry(fun, handler, context)
  end

  defp do_retry(fun, handler, context) do
    cond do
      Handler.progress_timeout?(handler) ->
        {:error, :progress_timeout}

      max_elapsed?(context) ->
        {:error, :max_elapsed}

      true ->
        execute_attempt(fun, handler, context)
    end
  end

  defp execute_attempt(fun, handler, context) do
    maybe_before_attempt(context.before_attempt, handler.attempt)

    attempt_metadata = Map.put(context.telemetry_metadata, :attempt, handler.attempt)

    emit_telemetry(
      context.telemetry_events[:start],
      %{system_time: System.system_time()},
      attempt_metadata
    )

    start_time = System.monotonic_time()

    result =
      if context.rescue_exceptions do
        try do
          fun.()
        rescue
          exception ->
            {:exception, exception, __STACKTRACE__}
        end
      else
        fun.()
      end

    duration = System.monotonic_time() - start_time

    case result do
      {:ok, value} ->
        emit_telemetry(
          context.telemetry_events[:stop],
          %{duration: duration},
          Map.put(attempt_metadata, :result, :ok)
        )

        {:ok, value}

      {:error, _reason} ->
        handle_retry(
          result,
          fun,
          handler,
          duration,
          context,
          attempt_metadata
        )

      {:exception, _exception, _stacktrace} ->
        handle_retry(
          result,
          fun,
          handler,
          duration,
          context,
          attempt_metadata
        )

      other ->
        emit_telemetry(
          context.telemetry_events[:stop],
          %{duration: duration},
          Map.put(attempt_metadata, :result, :ok)
        )

        {:ok, other}
    end
  end

  defp handle_retry(result, fun, handler, duration, context, metadata) do
    if should_retry?(handler, result, context.retry_on) do
      delay = retry_delay(result, handler, context)

      emit_telemetry(
        context.telemetry_events[:retry],
        %{duration: duration, delay_ms: delay},
        Map.merge(metadata, retry_metadata(result))
      )

      context.sleep_fun.(delay)
      handler = Handler.increment_attempt(handler)
      do_retry(fun, handler, context)
    else
      emit_telemetry(
        context.telemetry_events[:failed],
        %{duration: duration},
        Map.merge(metadata, failure_metadata(result))
      )

      {:error, unwrap_error(result)}
    end
  end

  defp unwrap_error({:error, reason}), do: reason
  defp unwrap_error({:exception, exception, _}), do: exception

  defp retry_metadata({:error, reason}), do: %{error: reason}
  defp retry_metadata({:exception, exception, _}), do: %{exception: exception}

  defp failure_metadata({:error, reason}), do: %{result: :failed, error: reason}

  defp failure_metadata({:exception, exception, _}),
    do: %{result: :exception, exception: exception}

  defp should_retry?(handler, result, retry_on) when is_function(retry_on, 2) do
    retry_on.(result, handler)
  end

  defp should_retry?(_handler, result, retry_on) when is_function(retry_on, 1) do
    retry_on.(result)
  end

  defp should_retry?(handler, {:error, reason}, _retry_on), do: Handler.retry?(handler, reason)

  defp should_retry?(handler, {:exception, exception, _}, _retry_on),
    do: Handler.retry?(handler, exception)

  defp maybe_before_attempt(fun, attempt) when is_function(fun, 1), do: fun.(attempt)
  defp maybe_before_attempt(_fun, _attempt), do: :ok

  defp emit_telemetry(nil, _measurements, _metadata), do: :ok

  defp emit_telemetry(event, measurements, metadata) when is_list(event) do
    :telemetry.execute(event, measurements, metadata)
    :ok
  end

  defp retry_delay(result, handler, %{delay_fun: fun}) when is_function(fun, 2) do
    normalize_delay(fun.(result, handler), handler)
  end

  defp retry_delay(_result, handler, %{delay_fun: fun}) when is_function(fun, 1) do
    normalize_delay(fun.(handler), handler)
  end

  defp retry_delay(_result, handler, _context), do: Handler.next_delay(handler)

  defp normalize_delay(value, _handler) when is_integer(value) and value >= 0, do: value
  defp normalize_delay(_value, handler), do: Handler.next_delay(handler)

  defp max_elapsed?(%{max_elapsed_ms: max}) when max in [nil, :infinity], do: false

  defp max_elapsed?(%{max_elapsed_ms: max, time_fun: time_fun, start_time: start_time})
       when is_integer(max) and max >= 0 do
    time_fun.(:millisecond) - start_time > max
  end

  defp max_elapsed?(_context), do: false

  defp build_context(opts) do
    time_fun = Keyword.get(opts, :time_fun, &System.monotonic_time/1)

    %{
      sleep_fun: Keyword.get(opts, :sleep_fun, &Process.sleep/1),
      before_attempt: Keyword.get(opts, :before_attempt, nil),
      retry_on: Keyword.get(opts, :retry_on, nil),
      delay_fun: Keyword.get(opts, :delay_fun, nil),
      max_elapsed_ms: Keyword.get(opts, :max_elapsed_ms, nil),
      time_fun: time_fun,
      start_time: time_fun.(:millisecond),
      rescue_exceptions: Keyword.get(opts, :rescue_exceptions, true),
      telemetry_events: Keyword.get(opts, :telemetry_events, %{}),
      telemetry_metadata: Keyword.get(opts, :telemetry_metadata, %{})
    }
  end

  defp build_handler(opts) do
    cond do
      match?(%Handler{}, opts[:handler]) -> opts[:handler]
      is_struct(opts[:config]) -> Handler.from_config(opts[:config])
      true -> Handler.new(Keyword.get(opts, :handler_opts, []))
    end
  end
end
