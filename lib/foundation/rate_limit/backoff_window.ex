defmodule Foundation.RateLimit.BackoffWindow do
  @moduledoc """
  Shared backoff windows keyed by arbitrary identifiers.
  """

  alias Foundation.Internal.ETSRegistry

  @default_registry_key {__MODULE__, :default_registry}

  @type registry :: :ets.tid() | atom()
  @type limiter :: :atomics.atomics_ref()

  @doc """
  Return the default registry (anonymous ETS table).
  """
  @spec default_registry() :: registry()
  def default_registry do
    ETSRegistry.default_registry(@default_registry_key, __MODULE__)
  end

  @doc """
  Create a new registry. Use `name: :my_table` for a named ETS table.
  """
  @spec new_registry(keyword()) :: registry()
  def new_registry(opts \\ []), do: ETSRegistry.new_registry(__MODULE__, opts)

  @doc """
  Get or create a limiter for the given key in the default registry.
  """
  @spec for_key(term()) :: limiter()
  def for_key(key), do: for_key(default_registry(), key)

  @doc """
  Get or create a limiter for the given key in the provided registry.
  """
  @spec for_key(registry(), term()) :: limiter()
  def for_key(registry, key) do
    table = resolve_registry(registry)
    limiter = :atomics.new(1, signed: true)

    case :ets.insert_new(table, {key, limiter}) do
      true ->
        limiter

      false ->
        case :ets.lookup(table, key) do
          [{^key, existing}] ->
            existing

          [] ->
            :ets.insert(table, {key, limiter})
            limiter
        end
    end
  end

  @doc """
  Determine whether a limiter is currently in a backoff window.
  """
  @spec should_backoff?(limiter(), keyword()) :: boolean()
  def should_backoff?(limiter, opts \\ []) do
    time_fun = Keyword.get(opts, :time_fun, &System.monotonic_time/1)
    backoff_until = :atomics.get(limiter, 1)

    backoff_until != 0 and time_fun.(:millisecond) < backoff_until
  end

  @doc """
  Set a backoff window in milliseconds.
  """
  @spec set(limiter(), non_neg_integer(), keyword()) :: :ok
  def set(limiter, duration_ms, opts \\ []) when is_integer(duration_ms) and duration_ms >= 0 do
    time_fun = Keyword.get(opts, :time_fun, &System.monotonic_time/1)
    backoff_until = time_fun.(:millisecond) + duration_ms

    put_max_deadline(limiter, backoff_until)
  end

  @doc """
  Clear any active backoff window.
  """
  @spec clear(limiter()) :: :ok
  def clear(limiter) do
    :atomics.put(limiter, 1, 0)
    :ok
  end

  @doc """
  Block until the backoff window has passed.
  """
  @spec wait(limiter(), keyword()) :: :ok
  def wait(limiter, opts \\ []) do
    time_fun = Keyword.get(opts, :time_fun, &System.monotonic_time/1)
    sleep_fun = Keyword.get(opts, :sleep_fun, &Process.sleep/1)
    do_wait(limiter, time_fun, sleep_fun)
  end

  defp resolve_registry(registry) when is_atom(registry) do
    ETSRegistry.resolve_registry(registry, __MODULE__)
  end

  defp resolve_registry(registry), do: registry

  defp do_wait(limiter, time_fun, sleep_fun) do
    case wait_ms(limiter, time_fun) do
      0 ->
        :ok

      remaining_ms ->
        sleep_fun.(remaining_ms)
        do_wait(limiter, time_fun, sleep_fun)
    end
  end

  defp wait_ms(limiter, time_fun) do
    backoff_until = :atomics.get(limiter, 1)

    if backoff_until == 0 do
      0
    else
      max(backoff_until - time_fun.(:millisecond), 0)
    end
  end

  defp put_max_deadline(limiter, new_deadline) do
    current_deadline = :atomics.get(limiter, 1)

    cond do
      current_deadline == 0 and :atomics.compare_exchange(limiter, 1, 0, new_deadline) == :ok ->
        :ok

      current_deadline == 0 ->
        put_max_deadline(limiter, new_deadline)

      current_deadline >= new_deadline ->
        :ok

      :atomics.compare_exchange(limiter, 1, current_deadline, new_deadline) == :ok ->
        :ok

      true ->
        put_max_deadline(limiter, new_deadline)
    end
  end
end
