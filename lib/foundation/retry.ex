defmodule Foundation.Retry do
  @moduledoc """
  Generic retry orchestration with configurable policies.
  """

  alias Foundation.Backoff

  defmodule Policy do
    @moduledoc """
    Retry policy configuration.
    """

    @type retry_on_fun :: (term() -> boolean())
    @type retry_after_fun :: (term() -> non_neg_integer() | nil)

    @type t :: %__MODULE__{
            max_attempts: non_neg_integer() | :infinity,
            max_elapsed_ms: non_neg_integer() | nil,
            backoff: Backoff.Policy.t(),
            retry_on: retry_on_fun(),
            progress_timeout_ms: non_neg_integer() | nil,
            retry_after_ms_fun: retry_after_fun() | nil
          }

    defstruct max_attempts: 0,
              max_elapsed_ms: nil,
              backoff: nil,
              retry_on: nil,
              progress_timeout_ms: nil,
              retry_after_ms_fun: nil

    @spec new(keyword()) :: t()
    def new(opts \\ []) do
      %__MODULE__{
        max_attempts: normalize_max_attempts(Keyword.get(opts, :max_attempts, 0)),
        max_elapsed_ms: normalize_max_elapsed(Keyword.get(opts, :max_elapsed_ms, nil)),
        backoff: Keyword.get(opts, :backoff, Backoff.Policy.new()),
        retry_on: normalize_retry_on(Keyword.get(opts, :retry_on, fn _result -> false end)),
        progress_timeout_ms: normalize_timeout(Keyword.get(opts, :progress_timeout_ms, nil)),
        retry_after_ms_fun: normalize_retry_after(Keyword.get(opts, :retry_after_ms_fun, nil))
      }
    end

    defp normalize_max_attempts(:infinity), do: :infinity

    defp normalize_max_attempts(value) when is_integer(value) and value >= 0, do: value

    defp normalize_max_attempts(value) do
      raise ArgumentError,
            "max_attempts must be a non-negative integer or :infinity, got: #{inspect(value)}"
    end

    defp normalize_max_elapsed(nil), do: nil
    defp normalize_max_elapsed(:infinity), do: nil

    defp normalize_max_elapsed(value) when is_integer(value) and value >= 0, do: value

    defp normalize_max_elapsed(value) do
      raise ArgumentError,
            "max_elapsed_ms must be a non-negative integer or nil, got: #{inspect(value)}"
    end

    defp normalize_timeout(nil), do: nil
    defp normalize_timeout(:infinity), do: nil

    defp normalize_timeout(value) when is_integer(value) and value >= 0, do: value

    defp normalize_timeout(value) do
      raise ArgumentError,
            "progress_timeout_ms must be a non-negative integer or nil, got: #{inspect(value)}"
    end

    defp normalize_retry_on(fun) when is_function(fun, 1), do: fun
    defp normalize_retry_on(_), do: fn _result -> false end

    defp normalize_retry_after(nil), do: nil
    defp normalize_retry_after(fun) when is_function(fun, 1), do: fun
    defp normalize_retry_after(_), do: nil
  end

  defmodule State do
    @moduledoc """
    Retry state tracking.
    """

    @type t :: %__MODULE__{
            attempt: non_neg_integer(),
            start_time_ms: integer(),
            last_progress_ms: integer() | nil
          }

    defstruct attempt: 0,
              start_time_ms: nil,
              last_progress_ms: nil

    @spec new(keyword()) :: t()
    def new(opts \\ []) do
      time_fun = Keyword.get(opts, :time_fun, &System.monotonic_time/1)
      now = time_fun.(:millisecond)

      %__MODULE__{
        attempt: Keyword.get(opts, :attempt, 0),
        start_time_ms: Keyword.get(opts, :start_time_ms, now),
        last_progress_ms: Keyword.get(opts, :last_progress_ms, now)
      }
    end
  end

  @type retry_result ::
          {:retry, non_neg_integer(), State.t()}
          | {:halt, term(), State.t()}

  @doc """
  Run a function with retry semantics.
  """
  @spec run((-> term()), Policy.t(), keyword()) :: {term(), State.t()}
  def run(fun, %Policy{} = policy, opts \\ []) when is_function(fun, 0) do
    sleep_fun = Keyword.get(opts, :sleep_fun, &Process.sleep/1)
    time_fun = Keyword.get(opts, :time_fun, &System.monotonic_time/1)
    state = Keyword.get(opts, :state, State.new(time_fun: time_fun))

    do_run(fun, policy, state, sleep_fun, time_fun)
  end

  @doc """
  Decide whether to retry based on the policy and current result.
  """
  @spec step(State.t(), Policy.t(), term(), keyword()) :: retry_result()
  def step(%State{} = state, %Policy{} = policy, result, opts \\ []) do
    time_fun = Keyword.get(opts, :time_fun, &System.monotonic_time/1)
    now = time_fun.(:millisecond)

    case check_timeouts(state, policy, time_fun: time_fun, now: now) do
      {:error, reason} ->
        {:halt, {:error, reason}, state}

      :ok ->
        if retryable?(state, policy, result) do
          delay_ms = retry_delay(policy, state, result)
          {:retry, delay_ms, %{state | attempt: state.attempt + 1}}
        else
          {:halt, result, state}
        end
    end
  end

  @doc """
  Check whether progress or elapsed-time limits have been exceeded.
  """
  @spec check_timeouts(State.t(), Policy.t(), keyword()) :: :ok | {:error, atom()}
  def check_timeouts(%State{} = state, %Policy{} = policy, opts \\ []) do
    time_fun = Keyword.get(opts, :time_fun, &System.monotonic_time/1)
    now = Keyword.get(opts, :now, time_fun.(:millisecond))

    cond do
      progress_timeout?(state, policy, now) -> {:error, :progress_timeout}
      max_elapsed?(state, policy, now) -> {:error, :max_elapsed}
      true -> :ok
    end
  end

  @doc """
  Record progress to reset the progress timeout window.
  """
  @spec record_progress(State.t(), keyword()) :: State.t()
  def record_progress(%State{} = state, opts \\ []) do
    time_fun = Keyword.get(opts, :time_fun, &System.monotonic_time/1)
    %{state | last_progress_ms: time_fun.(:millisecond)}
  end

  defp do_run(fun, policy, state, sleep_fun, time_fun) do
    case check_timeouts(state, policy, time_fun: time_fun) do
      {:error, reason} ->
        {{:error, reason}, state}

      :ok ->
        result = fun.()

        case step(state, policy, result, time_fun: time_fun) do
          {:retry, delay_ms, next_state} ->
            sleep_fun.(delay_ms)
            do_run(fun, policy, next_state, sleep_fun, time_fun)

          {:halt, final_result, final_state} ->
            {final_result, final_state}
        end
    end
  end

  defp retryable?(%State{} = state, %Policy{max_attempts: max}, _result)
       when is_integer(max) and state.attempt >= max do
    false
  end

  defp retryable?(_state, %Policy{retry_on: retry_on}, result) do
    retry_on.(result)
  end

  defp retry_delay(%Policy{retry_after_ms_fun: nil, backoff: backoff}, state, _result) do
    Backoff.delay(backoff, state.attempt)
  end

  defp retry_delay(%Policy{retry_after_ms_fun: fun, backoff: backoff}, state, result) do
    case fun.(result) do
      ms when is_integer(ms) and ms >= 0 -> ms
      _ -> Backoff.delay(backoff, state.attempt)
    end
  end

  defp progress_timeout?(
         %State{attempt: attempt, last_progress_ms: _last_progress_ms},
         %Policy{progress_timeout_ms: nil},
         _now
       )
       when attempt >= 0 do
    false
  end

  defp progress_timeout?(
         %State{attempt: attempt, last_progress_ms: last_progress_ms},
         %Policy{progress_timeout_ms: timeout_ms},
         now
       )
       when attempt > 0 and is_integer(timeout_ms) and not is_nil(last_progress_ms) do
    now - last_progress_ms > timeout_ms
  end

  defp progress_timeout?(_state, _policy, _now), do: false

  defp max_elapsed?(
         %State{start_time_ms: start_time_ms},
         %Policy{max_elapsed_ms: nil},
         _now
       )
       when is_integer(start_time_ms) do
    false
  end

  defp max_elapsed?(
         %State{start_time_ms: start_time_ms},
         %Policy{max_elapsed_ms: max_elapsed_ms},
         now
       )
       when is_integer(start_time_ms) and is_integer(max_elapsed_ms) do
    now - start_time_ms > max_elapsed_ms
  end
end
