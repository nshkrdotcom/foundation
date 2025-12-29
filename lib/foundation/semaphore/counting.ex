defmodule Foundation.Semaphore.Counting do
  @moduledoc """
  ETS-backed counting semaphore.
  """

  alias Foundation.Backoff
  alias :ets, as: ETS

  @default_registry_key {__MODULE__, :default_registry}

  @type registry :: :ets.tid() | atom()
  @type name :: term()

  @doc """
  Return the default registry (anonymous ETS table).
  """
  @spec default_registry() :: registry()
  def default_registry do
    case :persistent_term.get(@default_registry_key, nil) do
      nil ->
        table = new_registry()
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
    case Keyword.get(opts, :name) do
      nil ->
        ETS.new(__MODULE__, [:set, :public, {:write_concurrency, true}])

      name when is_atom(name) ->
        case ETS.whereis(name) do
          :undefined ->
            ETS.new(name, [:set, :public, :named_table, {:write_concurrency, true}])

          _tid ->
            name
        end
    end
  end

  @doc """
  Acquire a semaphore in the default registry.
  """
  @spec acquire(name(), pos_integer()) :: boolean()
  def acquire(name, max), do: acquire(default_registry(), name, max)

  @doc """
  Acquire a semaphore in the provided registry.
  """
  @spec acquire(registry(), name(), pos_integer()) :: boolean()
  def acquire(registry, name, max) when is_integer(max) and max > 0 do
    table = resolve_registry(registry)

    case ETS.update_counter(table, name, [{2, 0}, {2, 1, max, max}], {name, 0}) do
      [^max, _] -> false
      _ -> true
    end
  end

  def acquire(_registry, _name, _max), do: false

  @doc """
  Attempt to acquire a semaphore without blocking.
  """
  @spec try_acquire(registry(), name(), pos_integer()) :: boolean()
  def try_acquire(registry, name, max), do: acquire(registry, name, max)

  @doc """
  Release a semaphore in the default registry.
  """
  @spec release(name()) :: :ok
  def release(name), do: release(default_registry(), name)

  @doc """
  Release a semaphore in the provided registry.
  """
  @spec release(registry(), name()) :: :ok
  def release(registry, name) do
    table = resolve_registry(registry)
    ETS.update_counter(table, name, {2, -1, 0, 0})
    :ok
  end

  @doc """
  Get the current count for a semaphore.
  """
  @spec count(registry(), name()) :: non_neg_integer()
  def count(registry, name) do
    table = resolve_registry(registry)

    case ETS.lookup(table, name) do
      [{^name, count}] -> count
      _ -> 0
    end
  end

  @doc """
  Execute a function while holding a semaphore.
  """
  @spec with_acquire(registry(), name(), pos_integer(), (-> result)) ::
          {:ok, result} | {:error, :max}
        when result: any()
  def with_acquire(registry, name, max, fun) when is_function(fun, 0) do
    if acquire(registry, name, max) do
      try do
        {:ok, fun.()}
      after
        release(registry, name)
      end
    else
      {:error, :max}
    end
  end

  @doc """
  Acquire a semaphore, retrying with backoff until available.
  """
  @spec acquire_blocking(registry(), name(), pos_integer(), Backoff.Policy.t(), keyword()) :: :ok
  def acquire_blocking(registry, name, max, %Backoff.Policy{} = backoff, opts \\ []) do
    sleep_fun = Keyword.get(opts, :sleep_fun, &Process.sleep/1)
    do_acquire_blocking(registry, name, max, backoff, sleep_fun, 0)
  end

  defp do_acquire_blocking(registry, name, max, backoff, sleep_fun, attempt) do
    if acquire(registry, name, max) do
      :ok
    else
      sleep_fun.(Backoff.delay(backoff, attempt))
      do_acquire_blocking(registry, name, max, backoff, sleep_fun, attempt + 1)
    end
  end

  defp resolve_registry(registry) when is_atom(registry) do
    case ETS.whereis(registry) do
      :undefined ->
        _ = new_registry(name: registry)
        registry

      _tid ->
        registry
    end
  end

  defp resolve_registry(registry), do: registry
end
