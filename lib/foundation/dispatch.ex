defmodule Foundation.Dispatch do
  @moduledoc """
  Layered dispatch limiter combining concurrency, throttling, and byte budgets.
  """

  use GenServer

  alias Foundation.Backoff
  alias Foundation.RateLimit.BackoffWindow
  alias Foundation.Semaphore.Counting
  alias Foundation.Semaphore.Weighted

  @default_concurrency 400
  @default_throttled_concurrency 10
  @default_byte_budget 5 * 1024 * 1024
  @default_backoff_window_ms 10_000
  @default_byte_penalty_multiplier 20
  @default_acquire_backoff_base_ms 2
  @default_acquire_backoff_max_ms 50
  @default_acquire_backoff_jitter 0.25

  @type snapshot :: %{
          concurrency: %{name: term(), limit: pos_integer()},
          throttled: %{name: term(), limit: pos_integer()},
          bytes: Weighted.t(),
          backoff_active?: boolean(),
          acquire_backoff: Backoff.Policy.t(),
          registry: Counting.registry(),
          sleep_fun: (non_neg_integer() -> any()),
          byte_penalty_multiplier: pos_integer()
        }

  @type option ::
          {:key, term()}
          | {:registry, Counting.registry()}
          | {:limiter, BackoffWindow.limiter()}
          | {:concurrency, pos_integer()}
          | {:throttled_concurrency, pos_integer()}
          | {:byte_budget, pos_integer()}
          | {:backoff_window_ms, pos_integer()}
          | {:byte_penalty_multiplier, pos_integer()}
          | {:acquire_backoff, Backoff.Policy.t() | keyword()}
          | {:sleep_fun, (non_neg_integer() -> any())}

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @doc """
  Execute `fun` while holding the layered dispatch semaphores.
  """
  @spec with_rate_limit(pid(), non_neg_integer(), (-> result)) :: result when result: any()
  def with_rate_limit(dispatch, estimated_bytes, fun) when is_function(fun, 0) do
    snapshot = snapshot(dispatch)
    execute_with_limits(snapshot, max(estimated_bytes, 0), fun)
  end

  @doc """
  Set a backoff window (in milliseconds) and mark the dispatch as recently throttled.
  """
  @spec set_backoff(pid(), non_neg_integer()) :: :ok
  def set_backoff(dispatch, duration_ms) when is_integer(duration_ms) and duration_ms >= 0 do
    GenServer.call(dispatch, {:set_backoff, duration_ms})
  end

  @doc """
  Return a snapshot of the dispatch state.
  """
  @spec snapshot(pid()) :: snapshot()
  def snapshot(dispatch) do
    GenServer.call(dispatch, :snapshot, :infinity)
  end

  @impl true
  def init(opts) do
    limiter = Keyword.fetch!(opts, :limiter)
    key = Keyword.get(opts, :key, :default)
    registry = Keyword.get(opts, :registry, Counting.default_registry())

    concurrency_limit = Keyword.get(opts, :concurrency, @default_concurrency)

    throttled_limit =
      Keyword.get(opts, :throttled_concurrency, @default_throttled_concurrency)

    byte_budget = Keyword.get(opts, :byte_budget, @default_byte_budget)
    backoff_window_ms = Keyword.get(opts, :backoff_window_ms, @default_backoff_window_ms)

    byte_penalty_multiplier =
      Keyword.get(opts, :byte_penalty_multiplier, @default_byte_penalty_multiplier)

    acquire_backoff = build_acquire_backoff(Keyword.get(opts, :acquire_backoff, []))
    sleep_fun = Keyword.get(opts, :sleep_fun, &Process.sleep/1)

    concurrency = %{name: concurrency_name(key, concurrency_limit), limit: concurrency_limit}
    throttled = %{name: throttled_name(key, throttled_limit), limit: throttled_limit}

    {:ok, bytes_semaphore} = Weighted.start_link(max_weight: byte_budget)

    {:ok,
     %{
       limiter: limiter,
       registry: registry,
       concurrency: concurrency,
       throttled: throttled,
       bytes: bytes_semaphore,
       last_backoff_until: nil,
       acquire_backoff: acquire_backoff,
       backoff_window_ms: backoff_window_ms,
       byte_penalty_multiplier: byte_penalty_multiplier,
       sleep_fun: sleep_fun
     }}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    {:reply, snapshot_state(state), state}
  end

  def handle_call({:set_backoff, duration_ms}, _from, state) do
    backoff_until = System.monotonic_time(:millisecond) + duration_ms
    :ok = BackoffWindow.set(state.limiter, duration_ms)
    {:reply, :ok, %{state | last_backoff_until: backoff_until}}
  end

  defp snapshot_state(state) do
    %{
      concurrency: state.concurrency,
      throttled: state.throttled,
      bytes: state.bytes,
      backoff_active?: recent_backoff?(state.last_backoff_until, state.backoff_window_ms),
      acquire_backoff: state.acquire_backoff,
      registry: state.registry,
      sleep_fun: state.sleep_fun,
      byte_penalty_multiplier: state.byte_penalty_multiplier
    }
  end

  defp recent_backoff?(nil, _window_ms), do: false

  defp recent_backoff?(backoff_until, window_ms) do
    now = System.monotonic_time(:millisecond)
    now < backoff_until or now - backoff_until < window_ms
  end

  defp execute_with_limits(snapshot, estimated_bytes, fun) do
    backoff_active? = snapshot.backoff_active?

    effective_bytes =
      if backoff_active?,
        do: estimated_bytes * snapshot.byte_penalty_multiplier,
        else: estimated_bytes

    acquire_counting(snapshot.concurrency, snapshot.acquire_backoff, snapshot)

    try do
      maybe_acquire_throttled(snapshot.throttled, backoff_active?, snapshot)

      try do
        Weighted.with_acquire(snapshot.bytes, effective_bytes, fun)
      after
        maybe_release_throttled(snapshot.throttled, backoff_active?, snapshot)
      end
    after
      release_counting(snapshot.concurrency, snapshot)
    end
  end

  defp acquire_counting(%{name: name, limit: limit}, backoff, snapshot) do
    Counting.acquire_blocking(snapshot.registry, name, limit, backoff,
      sleep_fun: snapshot.sleep_fun
    )
  end

  defp release_counting(%{name: name}, snapshot) do
    Counting.release(snapshot.registry, name)
  end

  defp maybe_acquire_throttled(_semaphore, false, _snapshot), do: :ok

  defp maybe_acquire_throttled(%{name: name, limit: limit}, true, snapshot) do
    Counting.acquire_blocking(snapshot.registry, name, limit, snapshot.acquire_backoff,
      sleep_fun: snapshot.sleep_fun
    )
  end

  defp maybe_release_throttled(_semaphore, false, _snapshot), do: :ok

  defp maybe_release_throttled(%{name: name}, true, snapshot) do
    Counting.release(snapshot.registry, name)
  end

  defp concurrency_name(key, limit) do
    {__MODULE__, key, :concurrency, limit}
  end

  defp throttled_name(key, limit) do
    {__MODULE__, key, :throttled, limit}
  end

  defp build_acquire_backoff(%Backoff.Policy{} = backoff), do: backoff

  defp build_acquire_backoff(opts) when is_map(opts) do
    opts
    |> Map.to_list()
    |> build_acquire_backoff()
  end

  defp build_acquire_backoff(opts) when is_list(opts) do
    base_ms =
      positive_or_default(
        Keyword.get(opts, :base_ms, @default_acquire_backoff_base_ms),
        @default_acquire_backoff_base_ms
      )

    max_ms =
      opts
      |> Keyword.get(:max_ms, @default_acquire_backoff_max_ms)
      |> then(&positive_or_default(&1, @default_acquire_backoff_max_ms))
      |> max(base_ms)

    jitter = normalize_jitter(Keyword.get(opts, :jitter, @default_acquire_backoff_jitter))
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

  defp build_acquire_backoff(_), do: build_acquire_backoff([])

  defp positive_or_default(value, _default) when is_integer(value) and value > 0, do: value
  defp positive_or_default(_value, default), do: default

  defp normalize_jitter(value) when is_float(value) and value >= 0 and value <= 1, do: value
  defp normalize_jitter(value) when is_integer(value) and value in [0, 1], do: value * 1.0
  defp normalize_jitter(_value), do: @default_acquire_backoff_jitter
end
