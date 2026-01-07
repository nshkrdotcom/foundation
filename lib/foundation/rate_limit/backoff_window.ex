defmodule Foundation.RateLimit.BackoffWindow do
  @moduledoc """
  Shared backoff windows keyed by arbitrary identifiers.
  """

  @default_registry_key {__MODULE__, :default_registry}

  @type registry :: :ets.tid() | atom()
  @type limiter :: :atomics.atomics_ref()

  @doc """
  Return the default registry (anonymous ETS table).
  """
  @spec default_registry() :: registry()
  def default_registry do
    case :persistent_term.get(@default_registry_key, nil) do
      nil ->
        heir = heir_pid()

        table =
          :ets.new(__MODULE__, [
            :set,
            :public,
            {:read_concurrency, true},
            {:write_concurrency, true},
            {:heir, heir, :none}
          ])

        :persistent_term.put(@default_registry_key, table)
        table

      table ->
        table
    end
  end

  @doc """
  Create a new registry. Use `name: :my_table` for a named ETS table.
  """
  @spec new_registry(keyword()) :: registry()
  def new_registry(opts \\ []) do
    heir = heir_pid()

    case Keyword.get(opts, :name) do
      nil ->
        :ets.new(__MODULE__, [
          :set,
          :public,
          {:read_concurrency, true},
          {:write_concurrency, true},
          {:heir, heir, :none}
        ])

      name when is_atom(name) ->
        case :ets.whereis(name) do
          :undefined ->
            :ets.new(name, [
              :set,
              :public,
              :named_table,
              {:read_concurrency, true},
              {:write_concurrency, true},
              {:heir, heir, :none}
            ])

          _tid ->
            name
        end
    end
  end

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
    :atomics.put(limiter, 1, backoff_until)
    :ok
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
    backoff_until = :atomics.get(limiter, 1)

    if backoff_until != 0 do
      now = time_fun.(:millisecond)
      wait_ms = backoff_until - now

      if wait_ms > 0 do
        sleep_fun.(wait_ms)
      end
    end

    :ok
  end

  defp resolve_registry(registry) when is_atom(registry) do
    case :ets.whereis(registry) do
      :undefined ->
        _ = new_registry(name: registry)
        registry

      _tid ->
        registry
    end
  end

  defp resolve_registry(registry), do: registry

  defp heir_pid do
    Process.whereis(:init) || self()
  end
end
