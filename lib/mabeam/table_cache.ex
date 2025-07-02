defmodule MABEAM.TableCache do
  @moduledoc """
  ETS-based cache for MABEAM registry table names with TTL expiration.

  This module replaces Process dictionary caching with a proper ETS-based solution
  that provides:
  - Thread-safe concurrent access
  - TTL-based expiration of cached entries
  - Automatic cleanup of expired entries
  - Better monitoring and observability
  """

  require Logger
  alias Foundation.Telemetry

  @cache_table :mabeam_table_cache
  @monitor_table :mabeam_cache_monitors
  @cleanup_interval :timer.minutes(5)
  @default_ttl :timer.minutes(10)

  # --- Cache Management ---

  @doc """
  Ensures the cache table exists. This is idempotent and safe to call multiple times.
  """
  def ensure_cache_exists do
    # Ensure cache table exists
    cache_tid =
      case :ets.whereis(@cache_table) do
        :undefined ->
          :ets.new(@cache_table, [
            :set,
            :public,
            :named_table,
            {:read_concurrency, true},
            {:write_concurrency, true}
          ])

        tid ->
          tid
      end

    # Ensure monitor table exists
    case :ets.whereis(@monitor_table) do
      :undefined ->
        :ets.new(@monitor_table, [
          :set,
          :public,
          :named_table,
          {:read_concurrency, true},
          {:write_concurrency, true}
        ])

      _tid ->
        :ok
    end

    # Start cleanup process if not already running
    ensure_cleanup_process()

    cache_tid
  end

  @doc """
  Gets cached table names for a registry, or fetches and caches them if not present.

  ## Parameters
    - registry_pid: The PID of the registry GenServer
    - fetch_fn: Function to call if cache miss (defaults to GenServer.call)
    
  ## Returns
    - {:ok, tables} on success
    - {:error, reason} on failure
  """
  def get_cached_tables(registry_pid, fetch_fn \\ nil) when is_pid(registry_pid) do
    ensure_cache_exists()

    cache_key = {__MODULE__, :table_names, registry_pid}
    now = :erlang.monotonic_time(:millisecond)

    case lookup_with_ttl(cache_key, now) do
      {:ok, tables} ->
        emit_cache_hit_telemetry(registry_pid)
        {:ok, tables}

      :expired ->
        # Monitor the registry process so we can clean up if it dies
        monitor_registry_process(registry_pid)
        fetch_and_cache_tables(registry_pid, cache_key, fetch_fn)
    end
  end

  @doc """
  Invalidates cached table names for a specific registry.
  """
  def invalidate_cache(registry_pid) when is_pid(registry_pid) do
    # Only try to delete if table exists (avoid crashes during cleanup)
    if :ets.whereis(@cache_table) != :undefined do
      cache_key = {__MODULE__, :table_names, registry_pid}
      :ets.delete(@cache_table, cache_key)
    end

    :ok
  end

  @doc """
  Clears all entries from the cache.
  """
  def clear_all do
    ensure_cache_exists()
    :ets.delete_all_objects(@cache_table)
    :ok
  end

  @doc """
  Gets cache statistics for monitoring.
  """
  def get_stats do
    ensure_cache_exists()

    entries = :ets.tab2list(@cache_table)
    now = :erlang.monotonic_time(:millisecond)

    stats =
      Enum.reduce(entries, %{total: 0, expired: 0, active: 0}, fn
        {_key, _value, expires_at}, acc ->
          if now >= expires_at do
            %{acc | total: acc.total + 1, expired: acc.expired + 1}
          else
            %{acc | total: acc.total + 1, active: acc.active + 1}
          end
      end)

    Map.put(stats, :table_memory, :ets.info(@cache_table, :memory))
  end

  # --- Private Functions ---

  defp lookup_with_ttl(cache_key, now) do
    case :ets.lookup(@cache_table, cache_key) do
      [{^cache_key, tables, expires_at}] when now < expires_at ->
        {:ok, tables}

      [{^cache_key, _tables, _expires_at}] ->
        # Entry expired, delete it
        :ets.delete(@cache_table, cache_key)
        :expired

      [] ->
        :expired
    end
  end

  defp fetch_and_cache_tables(registry_pid, cache_key, fetch_fn) do
    start_time = System.monotonic_time()

    # Use provided fetch function or default GenServer.call
    fetch_fn =
      fetch_fn ||
        fn pid ->
          GenServer.call(pid, {:get_table_names})
        end

    case fetch_fn.(registry_pid) do
      {:ok, tables} ->
        # Cache the result with TTL
        expires_at = :erlang.monotonic_time(:millisecond) + @default_ttl
        :ets.insert(@cache_table, {cache_key, tables, expires_at})

        emit_cache_miss_telemetry(registry_pid, System.monotonic_time() - start_time)

        {:ok, tables}

      error ->
        Logger.warning("Failed to fetch table names from registry: #{inspect(error)}")
        error
    end
  end

  defp emit_cache_hit_telemetry(registry_pid) do
    Telemetry.emit(
      [:foundation, :mabeam, :cache, :hit],
      %{count: 1},
      %{
        cache_type: :table_names,
        registry_pid: inspect(registry_pid)
      }
    )
  end

  defp emit_cache_miss_telemetry(registry_pid, duration) do
    Telemetry.emit(
      [:foundation, :mabeam, :cache, :miss],
      %{count: 1, duration: duration},
      %{
        cache_type: :table_names,
        registry_pid: inspect(registry_pid)
      }
    )
  end

  defp monitor_registry_process(registry_pid) do
    # Check if we're already monitoring this process
    case :ets.lookup(@monitor_table, registry_pid) do
      [] ->
        # Not monitoring yet, set up monitor
        ref = Process.monitor(registry_pid)
        :ets.insert(@monitor_table, {registry_pid, ref})
        :ets.insert(@monitor_table, {{:ref, ref}, registry_pid})

      [{^registry_pid, _ref}] ->
        # Already monitoring
        :ok
    end
  end

  # --- Cleanup Process ---

  defp ensure_cleanup_process do
    # Check if cleanup process is already registered
    case Process.whereis(:mabeam_cache_cleanup) do
      nil ->
        pid = spawn_link(__MODULE__, :cleanup_loop, [])
        Process.register(pid, :mabeam_cache_cleanup)

      _pid ->
        :ok
    end
  end

  @doc false
  def cleanup_loop do
    receive do
      :stop ->
        :ok

      {:DOWN, ref, :process, pid, _reason} ->
        handle_down_message(ref, pid)
        cleanup_loop()
    after
      @cleanup_interval ->
        cleanup_expired_entries()
        cleanup_loop()
    end
  end

  defp handle_down_message(ref, _pid) do
    # Clean up monitor entries
    case :ets.lookup(@monitor_table, {:ref, ref}) do
      [{{:ref, ^ref}, registry_pid}] ->
        # Remove monitor entries
        :ets.delete(@monitor_table, {:ref, ref})
        :ets.delete(@monitor_table, registry_pid)

        # Invalidate cache for this registry
        invalidate_cache(registry_pid)

        Logger.debug("Registry process #{inspect(registry_pid)} died, invalidated cache")

      [] ->
        # Unknown monitor, ignore
        :ok
    end

    # Always demonitor to prevent leaks
    Process.demonitor(ref, [:flush])
  end

  defp cleanup_expired_entries do
    now = :erlang.monotonic_time(:millisecond)

    # Use match spec to find expired entries
    match_spec = [
      {{:"$1", :"$2", :"$3"}, [{:"=<", :"$3", now}], [:"$1"]}
    ]

    expired_keys = :ets.select(@cache_table, match_spec)

    Enum.each(expired_keys, fn key ->
      :ets.delete(@cache_table, key)
    end)

    if length(expired_keys) > 0 do
      Logger.debug("Cleaned up #{length(expired_keys)} expired cache entries")

      Telemetry.emit(
        [:foundation, :mabeam, :cache, :cleanup],
        %{expired_count: length(expired_keys)},
        %{cache_type: :table_names}
      )
    end
  end
end
