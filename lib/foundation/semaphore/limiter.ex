defmodule Foundation.Semaphore.Limiter do
  @moduledoc """
  Blocking counting semaphore with exponential backoff.
  """

  alias Foundation.Backoff
  alias Foundation.Semaphore.Counting

  @default_backoff_base_ms 2
  @default_backoff_max_ms 50
  @default_backoff_jitter 0.25
  @default_max_backoff_exponent 20

  @type semaphore_name :: {__MODULE__, term(), pos_integer()}

  @doc """
  Return the semaphore name for the default key and max connections.
  """
  @spec get_semaphore(pos_integer()) :: semaphore_name()
  def get_semaphore(max_connections) when is_integer(max_connections) and max_connections > 0 do
    get_semaphore(:default, max_connections)
  end

  @doc """
  Return the semaphore name for a key and max connections.
  """
  @spec get_semaphore(term(), pos_integer()) :: semaphore_name()
  def get_semaphore(key, max_connections)
      when is_integer(max_connections) and max_connections > 0 do
    {__MODULE__, key, max_connections}
  end

  @doc """
  Execute `fun` while holding a semaphore for `max_connections`.
  """
  @spec with_semaphore(pos_integer(), (-> result)) :: result when result: any()
  def with_semaphore(max_connections, fun) when is_function(fun, 0) do
    with_semaphore(:default, max_connections, [], fun)
  end

  @doc """
  Execute `fun` while holding a semaphore for `max_connections`, with options.
  """
  @spec with_semaphore(pos_integer(), keyword(), (-> result)) :: result when result: any()
  def with_semaphore(max_connections, opts, fun)
      when is_integer(max_connections) and max_connections > 0 and is_list(opts) and
             is_function(fun, 0) do
    with_semaphore(:default, max_connections, opts, fun)
  end

  @doc false
  @spec with_semaphore(term(), pos_integer(), (-> result)) :: result when result: any()
  def with_semaphore(key, max_connections, fun)
      when is_integer(max_connections) and max_connections > 0 and is_function(fun, 0) do
    with_semaphore(key, max_connections, [], fun)
  end

  @doc """
  Execute `fun` while holding a keyed semaphore with options.

  Options:
    * `:registry` - counting semaphore registry (default: `Counting.default_registry/0`)
    * `:backoff` - backoff options or `Backoff.Policy` (default: exponential 2ms-50ms, 25% jitter)
    * `:sleep_fun` - sleep function (default: `&Process.sleep/1`)
    * `:max_backoff_exponent` - cap for exponential backoff attempts (default: 20)
  """
  @spec with_semaphore(term(), pos_integer(), keyword(), (-> result)) :: result when result: any()
  def with_semaphore(key, max_connections, opts, fun)
      when is_integer(max_connections) and max_connections > 0 and is_list(opts) and
             is_function(fun, 0) do
    registry = Keyword.get(opts, :registry, Counting.default_registry())
    name = get_semaphore(key, max_connections)
    backoff = build_backoff(Keyword.get(opts, :backoff, []))
    sleep_fun = Keyword.get(opts, :sleep_fun, &Process.sleep/1)
    max_exponent = Keyword.get(opts, :max_backoff_exponent, @default_max_backoff_exponent)

    acquire_blocking(registry, name, max_connections, backoff, sleep_fun, max_exponent)

    try do
      fun.()
    after
      Counting.release(registry, name)
    end
  end

  defp acquire_blocking(registry, name, max_connections, backoff, sleep_fun, max_exponent) do
    do_acquire_blocking(registry, name, max_connections, backoff, sleep_fun, max_exponent, 0)
  end

  defp do_acquire_blocking(
         registry,
         name,
         max_connections,
         backoff,
         sleep_fun,
         max_exponent,
         attempt
       ) do
    if Counting.acquire(registry, name, max_connections) do
      :ok
    else
      capped_attempt = min(attempt, max_exponent)
      sleep_fun.(Backoff.delay(backoff, capped_attempt))

      do_acquire_blocking(
        registry,
        name,
        max_connections,
        backoff,
        sleep_fun,
        max_exponent,
        attempt + 1
      )
    end
  end

  defp build_backoff(%Backoff.Policy{} = backoff), do: backoff

  defp build_backoff(opts) when is_map(opts) do
    opts
    |> Map.to_list()
    |> build_backoff()
  end

  defp build_backoff(opts) when is_list(opts) do
    base_ms =
      positive_or_default(
        Keyword.get(opts, :base_ms, @default_backoff_base_ms),
        @default_backoff_base_ms
      )

    max_ms =
      opts
      |> Keyword.get(:max_ms, @default_backoff_max_ms)
      |> then(&positive_or_default(&1, @default_backoff_max_ms))
      |> max(base_ms)

    jitter = normalize_jitter(Keyword.get(opts, :jitter, @default_backoff_jitter))
    rand_fun = Keyword.get(opts, :rand_fun, &:rand.uniform/0)

    Backoff.Policy.new(
      strategy: :exponential,
      base_ms: base_ms,
      max_ms: max_ms,
      jitter_strategy: :factor,
      jitter: jitter,
      rand_fun: rand_fun
    )
  end

  defp build_backoff(_), do: build_backoff([])

  defp positive_or_default(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_or_default(_value, default), do: default

  defp normalize_jitter(value) when is_float(value) and value >= 0 and value <= 1, do: value
  defp normalize_jitter(value) when is_integer(value) and value in [0, 1], do: value * 1.0
  defp normalize_jitter(_value), do: @default_backoff_jitter
end
