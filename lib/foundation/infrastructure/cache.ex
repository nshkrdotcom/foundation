defmodule Foundation.Infrastructure.Cache do
  @moduledoc """
  ETS-based cache implementation with TTL support for Foundation infrastructure.

  Provides high-performance caching with automatic expiration, thread-safe operations,
  and optional memory limits with eviction policies.
  """

  use GenServer
  require Logger

  @table_options [
    :set,
    :public,
    :named_table,
    {:read_concurrency, true},
    {:write_concurrency, true}
  ]
  # 1 minute
  @cleanup_interval 60_000
  @default_ttl :infinity
  @default_max_size :infinity

  # Client API

  @doc """
  Starts a cache process linked to the current process.

  ## Options

    * `:name` - The name to register the cache process under
    * `:max_size` - Maximum number of entries (default: unlimited)
    * `:cleanup_interval` - Interval for TTL cleanup in ms (default: 60000)
    * `:table_name` - ETS table name (default: auto-generated)
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Retrieves a value from the cache.

  Returns the cached value if found and not expired, otherwise returns
  the default value (nil if not specified).

  ## Options

    * `:cache` - The cache process to use (default: Foundation.Infrastructure.Cache)
  """
  @spec get(any(), any(), keyword()) :: any()
  def get(key, default \\ nil, opts \\ []) do
    cache = Keyword.get(opts, :cache, __MODULE__)
    table = get_table_name(cache)

    case :ets.lookup(table, key) do
      [{^key, value, expiry}] ->
        if expired?(expiry) do
          :ets.delete(table, key)
          default
        else
          value
        end

      [] ->
        default
    end
  rescue
    ArgumentError -> default
  end

  @doc """
  Stores a value in the cache with optional TTL.

  ## Options

    * `:ttl` - Time to live in milliseconds (default: infinity)
    * `:cache` - The cache process to use (default: Foundation.Infrastructure.Cache)
  """
  @spec put(any(), any(), keyword()) :: :ok | {:error, term()}
  def put(key, value, opts \\ []) do
    case validate_key(key) do
      :ok ->
        cache = Keyword.get(opts, :cache, __MODULE__)
        ttl = Keyword.get(opts, :ttl, @default_ttl)

        GenServer.call(cache, {:put, key, value, ttl})

      {:error, _} = error ->
        error
    end
  rescue
    _ -> {:error, :cache_unavailable}
  end

  @doc """
  Removes a value from the cache.
  """
  @spec delete(any(), keyword()) :: :ok | {:error, term()}
  def delete(key, opts \\ []) do
    case validate_key(key) do
      :ok ->
        cache = Keyword.get(opts, :cache, __MODULE__)
        table = get_table_name(cache)
        :ets.delete(table, key)
        :ok

      {:error, _} = error ->
        error
    end
  rescue
    ArgumentError -> {:error, :cache_unavailable}
  end

  @doc """
  Clears all entries from the cache.
  """
  @spec clear(keyword()) :: :ok
  def clear(opts \\ []) do
    cache = Keyword.get(opts, :cache, __MODULE__)
    table = get_table_name(cache)
    :ets.delete_all_objects(table)
    :ok
  rescue
    ArgumentError -> {:error, :cache_unavailable}
  end

  # Server callbacks

  @impl true
  def init(opts) do
    table_name = Keyword.get(opts, :table_name, generate_table_name())
    max_size = Keyword.get(opts, :max_size, @default_max_size)
    cleanup_interval = Keyword.get(opts, :cleanup_interval, @cleanup_interval)

    :ets.new(table_name, @table_options)

    # Schedule periodic cleanup
    if cleanup_interval != :infinity do
      schedule_cleanup(cleanup_interval)
    end

    state = %{
      table: table_name,
      max_size: max_size,
      cleanup_interval: cleanup_interval
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:put, key, value, ttl}, _from, state) do
    %{table: table, max_size: max_size} = state

    # Check size limit and evict if necessary
    if max_size != :infinity and :ets.info(table, :size) >= max_size do
      evict_oldest(table)
    end

    expiry = calculate_expiry(ttl)
    :ets.insert(table, {key, value, expiry})

    {:reply, :ok, state}
  end

  @impl true
  def handle_call(:get_table_name, _from, %{table: table} = state) do
    {:reply, table, state}
  end

  @impl true
  def handle_info(:cleanup_expired, state) do
    %{table: table, cleanup_interval: interval} = state

    cleanup_expired_entries(table)
    schedule_cleanup(interval)

    {:noreply, state}
  end

  # Helper functions

  defp get_table_name(cache) do
    GenServer.call(cache, :get_table_name)
  rescue
    e ->
      reraise ArgumentError,
              [message: "Cache process not available: #{Exception.message(e)}"],
              __STACKTRACE__
  end

  defp generate_table_name do
    String.to_atom("cache_#{:erlang.unique_integer([:positive])}")
  end

  defp validate_key(nil), do: {:error, :invalid_key}
  defp validate_key(_key), do: :ok

  defp calculate_expiry(:infinity), do: :infinity

  defp calculate_expiry(ttl) when is_integer(ttl) and ttl > 0 do
    System.monotonic_time(:millisecond) + ttl
  end

  defp calculate_expiry(_), do: :infinity

  defp expired?(:infinity), do: false

  defp expired?(expiry) do
    System.monotonic_time(:millisecond) > expiry
  end

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup_expired, interval)
  end

  defp cleanup_expired_entries(table) do
    now = System.monotonic_time(:millisecond)

    match_spec = [
      {
        {:"$1", :"$2", :"$3"},
        [{:andalso, {:"/=", :"$3", :infinity}, {:<, :"$3", now}}],
        [:"$1"]
      }
    ]

    expired_keys = :ets.select(table, match_spec)
    Enum.each(expired_keys, &:ets.delete(table, &1))

    if length(expired_keys) > 0 do
      Logger.debug("Cache cleanup: removed #{length(expired_keys)} expired entries")
    end
  end

  defp evict_oldest(table) do
    # Simple FIFO eviction - remove the first entry
    # In production, might want LRU or other strategies
    case :ets.first(table) do
      :"$end_of_table" -> :ok
      key -> :ets.delete(table, key)
    end
  end
end
