defmodule Foundation.Poller do
  @moduledoc """
  Generic polling loop with backoff and timeout controls.
  """

  alias Foundation.Backoff

  @type step_result ::
          {:ok, term()}
          | {:retry, term()}
          | {:retry, term(), non_neg_integer()}
          | {:error, term()}
          | :retry

  @type backoff ::
          :none
          | Backoff.Policy.t()
          | {:exponential, pos_integer(), pos_integer()}
          | (non_neg_integer() -> non_neg_integer())

  @doc """
  Run a polling loop until completion, error, timeout, or max attempts.

  The `step_fun` receives the current attempt (0-based).
  """
  @spec run((non_neg_integer() -> step_result()), keyword()) ::
          {:ok, term()} | {:error, term()}
  def run(step_fun, opts \\ []) when is_function(step_fun, 1) do
    backoff = normalize_backoff(Keyword.get(opts, :backoff, :none))
    sleep_fun = Keyword.get(opts, :sleep_fun, &Process.sleep/1)
    time_fun = Keyword.get(opts, :time_fun, &System.monotonic_time/1)
    timeout_ms = Keyword.get(opts, :timeout_ms, :infinity)
    max_attempts = Keyword.get(opts, :max_attempts, :infinity)
    exception_handler = Keyword.get(opts, :exception_handler, &default_exception_handler/1)

    context = %{
      backoff: backoff,
      sleep_fun: sleep_fun,
      time_fun: time_fun,
      timeout_ms: timeout_ms,
      max_attempts: max_attempts,
      exception_handler: exception_handler
    }

    start_time = time_fun.(:millisecond)

    do_run(step_fun, 0, start_time, context)
  end

  @doc """
  Run a polling loop in a Task.
  """
  @spec async((non_neg_integer() -> step_result()), keyword()) :: Task.t()
  def async(step_fun, opts \\ []) when is_function(step_fun, 1) do
    Task.async(fn -> run(step_fun, opts) end)
  end

  @doc """
  Await a polling task, converting exits into error tuples.
  """
  @spec await(Task.t(), timeout()) :: {:ok, term()} | {:error, term()}
  def await(%Task{} = task, timeout \\ :infinity) do
    Task.await(task, timeout)
  catch
    :exit, {:timeout, _} ->
      Task.shutdown(task, :brutal_kill)
      {:error, :timeout}

    :exit, reason ->
      {:error, reason}
  end

  defp do_run(step_fun, attempt, start_time, context) do
    with :ok <- check_timeout(start_time, context.timeout_ms, context.time_fun),
         :ok <- check_attempts(attempt, context.max_attempts) do
      result =
        try do
          step_fun.(attempt)
        rescue
          exception ->
            context.exception_handler.(exception)
        end

      case normalize_result(result) do
        {:ok, value} ->
          {:ok, value}

        {:error, reason} ->
          {:error, reason}

        {:retry, reason} ->
          delay = retry_delay({:retry, reason}, context.backoff, attempt)
          maybe_sleep(delay, context.sleep_fun)
          do_run(step_fun, attempt + 1, start_time, context)

        {:retry, reason, delay_override} ->
          delay = retry_delay({:retry, reason, delay_override}, context.backoff, attempt)
          maybe_sleep(delay, context.sleep_fun)
          do_run(step_fun, attempt + 1, start_time, context)

        :retry ->
          delay = retry_delay(:retry, context.backoff, attempt)
          maybe_sleep(delay, context.sleep_fun)
          do_run(step_fun, attempt + 1, start_time, context)
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_result({:ok, _} = ok), do: ok
  defp normalize_result({:error, _} = error), do: error
  defp normalize_result({:retry, _} = retry), do: retry
  defp normalize_result({:retry, _reason, _delay} = retry), do: retry
  defp normalize_result(:retry), do: :retry
  defp normalize_result(other), do: {:ok, other}

  defp check_timeout(_start_time, :infinity, _time_fun), do: :ok

  defp check_timeout(start_time, timeout_ms, time_fun)
       when is_integer(timeout_ms) and timeout_ms >= 0 do
    elapsed = time_fun.(:millisecond) - start_time

    if elapsed > timeout_ms do
      {:error, :timeout}
    else
      :ok
    end
  end

  defp check_timeout(_start_time, _timeout_ms, _time_fun), do: :ok

  defp check_attempts(_attempt, :infinity), do: :ok

  defp check_attempts(attempt, max_attempts)
       when is_integer(max_attempts) and max_attempts >= 0 do
    if attempt >= max_attempts do
      {:error, :max_attempts}
    else
      :ok
    end
  end

  defp check_attempts(_attempt, _max_attempts), do: :ok

  defp normalize_backoff(:none), do: :none
  defp normalize_backoff(%Backoff.Policy{} = backoff), do: backoff

  defp normalize_backoff({:exponential, base_ms, max_ms})
       when is_integer(base_ms) and base_ms > 0 and is_integer(max_ms) and max_ms >= base_ms do
    Backoff.Policy.new(strategy: :exponential, base_ms: base_ms, max_ms: max_ms)
  end

  defp normalize_backoff(fun) when is_function(fun, 1), do: fun
  defp normalize_backoff(_), do: :none

  defp retry_delay({:retry, delay}, _backoff, _attempt)
       when is_integer(delay) and delay >= 0 do
    delay
  end

  defp retry_delay({:retry, _reason, delay}, _backoff, _attempt)
       when is_integer(delay) and delay >= 0 do
    delay
  end

  defp retry_delay(_result, :none, _attempt), do: 0

  defp retry_delay(_result, %Backoff.Policy{} = backoff, attempt),
    do: Backoff.delay(backoff, attempt)

  defp retry_delay(_result, fun, attempt) when is_function(fun, 1), do: fun.(attempt)

  defp maybe_sleep(delay, sleep_fun) when is_integer(delay) and delay > 0, do: sleep_fun.(delay)
  defp maybe_sleep(_delay, _sleep_fun), do: :ok

  defp default_exception_handler(exception), do: {:error, exception}
end
