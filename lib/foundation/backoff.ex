defmodule Foundation.Backoff do
  @moduledoc """
  Backoff delay calculation with configurable strategies and jitter.
  """

  defmodule Policy do
    @moduledoc """
    Backoff policy configuration.
    """

    @type strategy :: :exponential | :linear | :constant
    @type jitter_strategy :: :none | :factor | :additive | :range
    @type rand_fun :: (-> float()) | (pos_integer() -> pos_integer())

    @type t :: %__MODULE__{
            strategy: strategy(),
            base_ms: pos_integer(),
            max_ms: pos_integer() | nil,
            jitter_strategy: jitter_strategy(),
            jitter: float() | {float(), float()},
            rand_fun: rand_fun()
          }

    defstruct strategy: :exponential,
              base_ms: 1_000,
              max_ms: 10_000,
              jitter_strategy: :none,
              jitter: 0.0,
              rand_fun: &:rand.uniform/0

    @spec new(keyword()) :: t()
    def new(opts \\ []) do
      base_ms = positive_int!(Keyword.get(opts, :base_ms, 1_000), :base_ms)
      max_ms = Keyword.get(opts, :max_ms, 10_000)
      max_ms = normalize_max_ms(max_ms, base_ms)
      strategy = normalize_strategy(Keyword.get(opts, :strategy, :exponential))
      jitter_strategy = normalize_jitter_strategy(Keyword.get(opts, :jitter_strategy, :none))
      jitter = normalize_jitter(jitter_strategy, Keyword.get(opts, :jitter, 0.0))
      rand_fun = normalize_rand_fun(Keyword.get(opts, :rand_fun, &:rand.uniform/0))

      %__MODULE__{
        strategy: strategy,
        base_ms: base_ms,
        max_ms: max_ms,
        jitter_strategy: jitter_strategy,
        jitter: jitter,
        rand_fun: rand_fun
      }
    end

    defp positive_int!(value, _field) when is_integer(value) and value > 0, do: value

    defp positive_int!(value, field) do
      raise ArgumentError, "#{field} must be a positive integer, got: #{inspect(value)}"
    end

    defp normalize_max_ms(nil, _base_ms), do: nil
    defp normalize_max_ms(:infinity, _base_ms), do: nil

    defp normalize_max_ms(value, base_ms) when is_integer(value) and value >= base_ms do
      value
    end

    defp normalize_max_ms(value, _base_ms) do
      raise ArgumentError, "max_ms must be nil or >= base_ms, got: #{inspect(value)}"
    end

    defp normalize_strategy(:exponential), do: :exponential
    defp normalize_strategy(:linear), do: :linear
    defp normalize_strategy(:constant), do: :constant

    defp normalize_strategy(value) do
      raise ArgumentError, "invalid strategy: #{inspect(value)}"
    end

    defp normalize_jitter_strategy(:none), do: :none
    defp normalize_jitter_strategy(:factor), do: :factor
    defp normalize_jitter_strategy(:additive), do: :additive
    defp normalize_jitter_strategy(:range), do: :range

    defp normalize_jitter_strategy(value) do
      raise ArgumentError, "invalid jitter_strategy: #{inspect(value)}"
    end

    defp normalize_jitter(:none, _value), do: 0.0

    defp normalize_jitter(:range, {min, max})
         when is_number(min) and is_number(max) and min >= 0 and max >= min do
      {min * 1.0, max * 1.0}
    end

    defp normalize_jitter(:range, [min, max]) do
      normalize_jitter(:range, {min, max})
    end

    defp normalize_jitter(:range, value) do
      raise ArgumentError, "range jitter must be {min, max}, got: #{inspect(value)}"
    end

    defp normalize_jitter(_strategy, value) when is_number(value) and value >= 0 do
      value * 1.0
    end

    defp normalize_jitter(_strategy, value) do
      raise ArgumentError, "jitter must be a non-negative number, got: #{inspect(value)}"
    end

    defp normalize_rand_fun(fun) when is_function(fun, 0) or is_function(fun, 1), do: fun
    defp normalize_rand_fun(_), do: &:rand.uniform/0
  end

  @doc """
  Compute the delay for the given attempt based on policy.
  """
  @spec delay(Policy.t(), non_neg_integer()) :: non_neg_integer()
  def delay(%Policy{} = policy, attempt) when is_integer(attempt) and attempt >= 0 do
    base_delay = base_delay(policy, attempt)
    capped_delay = cap_delay(base_delay, policy.max_ms)
    jittered_delay = apply_jitter(capped_delay, policy)
    cap_delay(jittered_delay, policy.max_ms)
  end

  def delay(%Policy{}, attempt) do
    raise ArgumentError, "attempt must be a non-negative integer, got: #{inspect(attempt)}"
  end

  @doc """
  Sleep for the computed delay, using the provided sleep function.
  """
  @spec sleep(Policy.t(), non_neg_integer(), (non_neg_integer() -> any())) :: :ok
  def sleep(%Policy{} = policy, attempt, sleep_fun \\ &Process.sleep/1)
      when is_function(sleep_fun, 1) do
    sleep_fun.(delay(policy, attempt))
    :ok
  end

  defp base_delay(%Policy{strategy: :exponential, base_ms: base_ms}, attempt) do
    base_ms * :math.pow(2, attempt)
  end

  defp base_delay(%Policy{strategy: :linear, base_ms: base_ms}, attempt) do
    base_ms * (attempt + 1)
  end

  defp base_delay(%Policy{strategy: :constant, base_ms: base_ms}, _attempt) do
    base_ms
  end

  defp cap_delay(delay, nil), do: delay
  defp cap_delay(delay, max_ms), do: min(delay, max_ms)

  defp apply_jitter(delay, %Policy{jitter_strategy: :none}), do: round(delay)

  defp apply_jitter(delay, %Policy{jitter_strategy: :factor, jitter: jitter, rand_fun: _rand_fun})
       when jitter <= 0 do
    round(delay)
  end

  defp apply_jitter(delay, %Policy{jitter_strategy: :factor, jitter: jitter, rand_fun: rand_fun}) do
    factor = 1.0 - jitter + rand_float(rand_fun) * jitter
    normalize_delay(delay * factor)
  end

  defp apply_jitter(delay, %Policy{
         jitter_strategy: :additive,
         jitter: jitter,
         rand_fun: _rand_fun
       })
       when jitter <= 0 do
    round(delay)
  end

  defp apply_jitter(delay, %Policy{jitter_strategy: :additive, jitter: jitter, rand_fun: rand_fun}) do
    max_jitter = round(delay * jitter)

    jitter_amount =
      if is_function(rand_fun, 1) do
        if max_jitter <= 0, do: 0, else: rand_fun.(max_jitter)
      else
        rand_fun.() * (delay * jitter)
      end

    normalize_delay(delay + jitter_amount)
  end

  defp apply_jitter(delay, %Policy{
         jitter_strategy: :range,
         jitter: {min_f, max_f},
         rand_fun: rand_fun
       }) do
    factor = min_f + rand_float(rand_fun) * (max_f - min_f)
    normalize_delay(delay * factor)
  end

  defp rand_float(rand_fun) when is_function(rand_fun, 0), do: rand_fun.()

  defp rand_float(rand_fun) when is_function(rand_fun, 1) do
    max = 1_000_000
    rand_fun.(max) / max
  end

  defp normalize_delay(value) do
    value
    |> max(0)
    |> round()
  end
end
