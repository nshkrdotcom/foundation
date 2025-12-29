defmodule Foundation.CircuitBreaker do
  @moduledoc """
  Circuit breaker state machine for resilient calls.
  """

  defstruct [
    :name,
    :opened_at,
    state: :closed,
    failure_count: 0,
    failure_threshold: 5,
    reset_timeout_ms: 30_000,
    half_open_max_calls: 1,
    half_open_calls: 0
  ]

  @type state :: :closed | :open | :half_open

  @type t :: %__MODULE__{
          name: String.t(),
          state: state(),
          failure_count: non_neg_integer(),
          failure_threshold: pos_integer(),
          reset_timeout_ms: pos_integer(),
          half_open_max_calls: pos_integer(),
          half_open_calls: non_neg_integer(),
          opened_at: integer() | nil
        }

  @doc """
  Create a new circuit breaker.
  """
  @spec new(String.t(), keyword()) :: t()
  def new(name, opts \\ []) do
    %__MODULE__{
      name: name,
      failure_threshold: Keyword.get(opts, :failure_threshold, 5),
      reset_timeout_ms: Keyword.get(opts, :reset_timeout_ms, 30_000),
      half_open_max_calls: Keyword.get(opts, :half_open_max_calls, 1)
    }
  end

  @doc """
  Check if a request should be allowed.
  """
  @spec allow_request?(t()) :: boolean()
  def allow_request?(%__MODULE__{} = cb) do
    case state(cb) do
      :closed -> true
      :half_open -> cb.half_open_calls < cb.half_open_max_calls
      :open -> false
    end
  end

  @doc """
  Get the current circuit breaker state.
  """
  @spec state(t()) :: state()
  def state(%__MODULE__{state: :open, opened_at: opened_at, reset_timeout_ms: timeout}) do
    now = System.monotonic_time(:millisecond)

    if now - opened_at >= timeout do
      :half_open
    else
      :open
    end
  end

  def state(%__MODULE__{state: state}), do: state

  @doc """
  Record a successful call.
  """
  @spec record_success(t()) :: t()
  def record_success(%__MODULE__{} = cb) do
    case state(cb) do
      :closed ->
        %{cb | failure_count: 0}

      :half_open ->
        %{cb | state: :closed, failure_count: 0, half_open_calls: 0, opened_at: nil}

      :open ->
        cb
    end
  end

  @doc """
  Record a failed call.
  """
  @spec record_failure(t()) :: t()
  def record_failure(%__MODULE__{} = cb) do
    case state(cb) do
      :closed ->
        new_count = cb.failure_count + 1

        if new_count >= cb.failure_threshold do
          %{
            cb
            | state: :open,
              failure_count: new_count,
              opened_at: System.monotonic_time(:millisecond)
          }
        else
          %{cb | failure_count: new_count}
        end

      :half_open ->
        %{cb | state: :open, opened_at: System.monotonic_time(:millisecond), half_open_calls: 0}

      :open ->
        cb
    end
  end

  @doc """
  Execute a function through the circuit breaker.
  """
  @spec call(t(), (-> result), keyword()) :: {result | {:error, :circuit_open}, t()}
        when result: term()
  def call(%__MODULE__{} = cb, fun, opts \\ []) when is_function(fun, 0) do
    success_fn = Keyword.get(opts, :success?, &default_success?/1)

    case state(cb) do
      :open ->
        {{:error, :circuit_open}, cb}

      current_state ->
        cb =
          if current_state == :half_open do
            %{cb | half_open_calls: cb.half_open_calls + 1}
          else
            cb
          end

        result = fun.()

        if success_fn.(result) do
          {result, record_success(cb)}
        else
          {result, record_failure(cb)}
        end
    end
  end

  @doc """
  Reset the circuit breaker to a closed state.
  """
  @spec reset(t()) :: t()
  def reset(%__MODULE__{} = cb) do
    %{cb | state: :closed, failure_count: 0, half_open_calls: 0, opened_at: nil}
  end

  defp default_success?({:ok, _}), do: true
  defp default_success?(_), do: false
end
