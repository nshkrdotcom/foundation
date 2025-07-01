defmodule Foundation.Infrastructure.Cache do
  @moduledoc """
  ETS-based cache implementation with TTL support for Foundation infrastructure.

  Provides high-performance caching with automatic expiration, thread-safe operations,
  and optional memory limits with eviction policies.
  """

  use GenServer
  require Logger
  alias Foundation.Telemetry
  require Foundation.ErrorHandling
  alias Foundation.ErrorHandling

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
  # Set reasonable default limit
  @default_max_size 100_000

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
    start_time = System.monotonic_time()

    try do
      cache = Keyword.get(opts, :cache, __MODULE__)
      table = get_table_name(cache)
      now = System.monotonic_time(:millisecond)

      # Use atomic select to get non-expired values
      match_spec = [
        {
          {key, :"$1", :"$2"},
          [{:orelse, {:==, :"$2", :infinity}, {:>, :"$2", now}}],
          [{{:"$1", :"$2"}}]
        }
      ]

      case :ets.select(table, match_spec) do
        [{value, _expiry}] ->
          emit_cache_event(:hit, key, start_time)
          value

        [] ->
          # Check if it was expired or not found
          case :ets.lookup(table, key) do
            [{^key, _value, expiry}] when expiry != :infinity and expiry <= now ->
              # Atomically delete expired entry
              :ets.select_delete(table, [{{key, :"$1", :"$2"}, [{:"=<", :"$2", now}], [true]}])
              emit_cache_event(:miss, key, start_time, %{reason: :expired})
              default

            [] ->
              emit_cache_event(:miss, key, start_time, %{reason: :not_found})
              default
          end
      end
    rescue
      ArgumentError ->
        emit_cache_event(:error, key, start_time, %{error: :cache_unavailable})
        # Return default on cache unavailable
        default
    end
  end

  @doc """
  Stores a value in the cache with optional TTL.

  ## Options

    * `:ttl` - Time to live in milliseconds (default: infinity)
    * `:cache` - The cache process to use (default: Foundation.Infrastructure.Cache)
  """
  @spec put(any(), any(), keyword()) :: :ok | {:error, term()}
  def put(key, value, opts \\ []) do
    start_time = System.monotonic_time()

    try do
      case validate_key(key) do
        :ok ->
          cache = Keyword.get(opts, :cache, __MODULE__)
          ttl = Keyword.get(opts, :ttl, @default_ttl)

          result = GenServer.call(cache, {:put, key, value, ttl})
          emit_cache_event(:put, key, start_time, %{ttl: ttl})
          result

        {:error, reason} ->
          emit_cache_event(:error, key, start_time, %{error: reason, operation: :put})
          ErrorHandling.normalize_error({:error, reason})
      end
    rescue
      exception ->
        emit_cache_event(:error, key, start_time, %{error: :cache_unavailable, operation: :put})
        ErrorHandling.exception_to_error(exception)
    end
  end

  @doc """
  Removes a value from the cache.
  """
  @spec delete(any(), keyword()) :: :ok | {:error, term()}
  def delete(key, opts \\ []) do
    start_time = System.monotonic_time()

    try do
      case validate_key(key) do
        :ok ->
          cache = Keyword.get(opts, :cache, __MODULE__)
          table = get_table_name(cache)
          existed = :ets.member(table, key)
          :ets.delete(table, key)
          emit_cache_event(:delete, key, start_time, %{existed: existed})
          :ok

        {:error, reason} ->
          emit_cache_event(:error, key, start_time, %{error: reason, operation: :delete})
          ErrorHandling.normalize_error({:error, reason})
      end
    rescue
      ArgumentError ->
        emit_cache_event(:error, key, start_time, %{error: :cache_unavailable, operation: :delete})
        ErrorHandling.service_unavailable_error(:cache)
    end
  end

  @doc """
  Clears all entries from the cache.
  """
  @spec clear(keyword()) :: :ok
  def clear(opts \\ []) do
    start_time = System.monotonic_time()
    cache = Keyword.get(opts, :cache, __MODULE__)

    try do
      table = get_table_name(cache)
      count = :ets.info(table, :size)
      :ets.delete_all_objects(table)

      Telemetry.emit(
        [:foundation, :cache, :cleared],
        %{
          duration: System.monotonic_time() - start_time,
          count: count
        },
        %{cache: cache}
      )

      :ok
    rescue
      ArgumentError ->
        ErrorHandling.emit_telemetry_safe(
          [:foundation, :cache, :error],
          %{duration: System.monotonic_time() - start_time},
          %{cache: cache, error: :cache_unavailable, operation: :clear}
        )

        ErrorHandling.service_unavailable_error(:cache)
    end
  end

  # Server callbacks

  @impl true
  def init(opts) do
    table_name = Keyword.get(opts, :table_name, generate_table_name())
    max_size = Keyword.get(opts, :max_size, @default_max_size)
    cleanup_interval = Keyword.get(opts, :cleanup_interval, @cleanup_interval)

    :ets.new(table_name, @table_options)

    # Register table with ResourceManager if available
    if Process.whereis(Foundation.ResourceManager) do
      Foundation.ResourceManager.monitor_table(table_name)
    end

    # Schedule periodic cleanup
    cleanup_timer =
      if cleanup_interval != :infinity do
        schedule_cleanup(cleanup_interval)
      else
        nil
      end

    state = %{
      table: table_name,
      max_size: max_size,
      cleanup_interval: cleanup_interval,
      cleanup_timer: cleanup_timer
    }

    Telemetry.emit(
      [:foundation, :cache, :started],
      %{timestamp: System.system_time()},
      %{
        table: table_name,
        max_size: max_size,
        cleanup_interval: cleanup_interval
      }
    )

    {:ok, state}
  end

  @impl true
  def handle_call({:put, key, value, ttl}, _from, state) do
    %{table: table, max_size: max_size} = state

    # Check size limit and evict if necessary
    if max_size != :infinity and :ets.info(table, :size) >= max_size do
      evicted_key = evict_oldest(table)

      if evicted_key != nil do
        Telemetry.emit(
          [:foundation, :cache, :evicted],
          %{timestamp: System.system_time()},
          %{key: evicted_key, reason: :size_limit}
        )
      end
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
    new_timer = schedule_cleanup(interval)

    {:noreply, %{state | cleanup_timer: new_timer}}
  end

  @impl true
  def terminate(_reason, state) do
    # Cancel cleanup timer if it exists
    if state.cleanup_timer do
      Process.cancel_timer(state.cleanup_timer)
    end

    # Delete ETS table - named tables need explicit cleanup
    try do
      :ets.delete(state.table)
    rescue
      # Table already deleted
      ArgumentError -> :ok
    end

    :ok
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

  defp validate_key(nil), do: ErrorHandling.invalid_field_error(:key, :cannot_be_nil)
  defp validate_key(_key), do: :ok

  defp calculate_expiry(:infinity), do: :infinity

  defp calculate_expiry(ttl) when is_integer(ttl) and ttl > 0 do
    System.monotonic_time(:millisecond) + ttl
  end

  defp calculate_expiry(_), do: :infinity

  # Removed expired? functions as they're no longer used with atomic operations

  defp schedule_cleanup(interval) do
    Process.send_after(self(), :cleanup_expired, interval)
  end

  defp cleanup_expired_entries(table) do
    start_time = System.monotonic_time()
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
      Telemetry.emit(
        [:foundation, :cache, :cleanup],
        %{
          duration: System.monotonic_time() - start_time,
          expired_count: length(expired_keys),
          timestamp: System.system_time()
        },
        %{table: table}
      )

      Logger.debug("Cache cleanup: removed #{length(expired_keys)} expired entries")
    end
  end

  defp evict_oldest(table) do
    # Simple FIFO eviction - remove the first entry
    # In production, might want LRU or other strategies
    case :ets.first(table) do
      :"$end_of_table" ->
        nil

      key ->
        :ets.delete(table, key)
        key
    end
  end

  # Telemetry helper
  defp emit_cache_event(operation, key, start_time, metadata \\ %{}) do
    duration = System.monotonic_time() - start_time

    ErrorHandling.emit_telemetry_safe(
      [:foundation, :cache, operation],
      %{duration: duration, timestamp: System.system_time()},
      Map.merge(metadata, %{key: key})
    )
  end
end
