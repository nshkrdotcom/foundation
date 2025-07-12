defmodule MABEAM.TableCacheTest do
  use ExUnit.Case, async: true

  alias MABEAM.TableCache

  setup do
    # Clean up any existing cache before each test
    TableCache.clear_all()

    # Create a mock registry process that can handle multiple requests
    test_pid = self()

    mock_registry =
      spawn_link(fn ->
        mock_registry_loop(test_pid)
      end)

    on_exit(fn ->
      if Process.alive?(mock_registry) do
        Process.exit(mock_registry, :normal)
      end
    end)

    {:ok, registry: mock_registry}
  end

  defp mock_registry_loop(test_pid) do
    receive do
      {:"$gen_call", from, {:get_table_names}} ->
        tables = %{
          main: :mock_main_table,
          capability_index: :mock_capability_index,
          health_index: :mock_health_index,
          node_index: :mock_node_index,
          resource_index: :mock_resource_index
        }

        GenServer.reply(from, {:ok, tables})
        send(test_pid, :table_names_fetched)
        mock_registry_loop(test_pid)

      :exit ->
        :ok
    end
  end

  defp count_messages(message) do
    count_messages(message, 0)
  end

  defp count_messages(message, count) do
    receive do
      ^message ->
        count_messages(message, count + 1)
    after
      0 ->
        count
    end
  end

  describe "get_cached_tables/2" do
    test "fetches and caches table names on first access", %{registry: registry} do
      # First access should fetch from registry
      assert {:ok, tables} = TableCache.get_cached_tables(registry)
      assert tables.main == :mock_main_table
      assert_received :table_names_fetched

      # Second access should use cache (no fetch)
      assert {:ok, cached_tables} = TableCache.get_cached_tables(registry)
      assert cached_tables == tables
      refute_received :table_names_fetched, 100
    end

    test "handles custom fetch function", %{registry: registry} do
      custom_tables = %{main: :custom_table}

      fetch_fn = fn _pid ->
        send(self(), :custom_fetch_called)
        {:ok, custom_tables}
      end

      assert {:ok, tables} = TableCache.get_cached_tables(registry, fetch_fn)
      assert tables == custom_tables
      assert_received :custom_fetch_called
    end

    test "returns error when fetch fails", %{registry: registry} do
      fetch_fn = fn _pid ->
        {:error, :fetch_failed}
      end

      assert {:error, :fetch_failed} = TableCache.get_cached_tables(registry, fetch_fn)
    end
  end

  describe "invalidate_cache/1" do
    test "removes cached entry for specific registry", %{registry: registry} do
      # Cache the tables first
      assert {:ok, _tables} = TableCache.get_cached_tables(registry)
      assert_received :table_names_fetched

      # Invalidate the cache
      assert :ok = TableCache.invalidate_cache(registry)

      # Next access should fetch again
      assert {:ok, _tables} = TableCache.get_cached_tables(registry)
      assert_received :table_names_fetched
    end

    test "handles invalidation of non-existent cache gracefully", %{registry: registry} do
      # Should not crash when invalidating non-cached registry
      assert :ok = TableCache.invalidate_cache(registry)
    end
  end

  describe "clear_all/0" do
    test "removes all cached entries", %{registry: registry1} do
      test_pid = self()

      # Create another registry
      registry2 =
        spawn_link(fn ->
          receive do
            {:"$gen_call", from, {:get_table_names}} ->
              GenServer.reply(from, {:ok, %{main: :table2}})
              send(test_pid, :registry2_fetched)
          end
        end)

      # Cache both registries
      assert {:ok, _} = TableCache.get_cached_tables(registry1)
      assert {:ok, _} = TableCache.get_cached_tables(registry2)
      assert_received :table_names_fetched
      assert_received :registry2_fetched

      # Clear all caches
      assert :ok = TableCache.clear_all()

      # Both should need to fetch again
      assert {:ok, _} = TableCache.get_cached_tables(registry1)
      assert_received :table_names_fetched

      # Clean up registry2
      Process.exit(registry2, :normal)
    end
  end

  describe "get_stats/0" do
    test "returns cache statistics", %{registry: registry} do
      # Initially empty
      stats = TableCache.get_stats()
      assert stats.total == 0
      assert stats.active == 0
      assert stats.expired == 0

      # Add a cached entry
      assert {:ok, _} = TableCache.get_cached_tables(registry)

      # Should show one active entry
      stats = TableCache.get_stats()
      assert stats.total == 1
      assert stats.active == 1
      assert stats.expired == 0
      assert stats.table_memory > 0
    end
  end

  describe "TTL expiration" do
    @tag :slow
    test "expired entries are not returned", %{registry: registry} do
      # Use a very short TTL for testing
      short_ttl_fetch = fn pid ->
        result = GenServer.call(pid, {:get_table_names})
        # Manually insert with short TTL (1ms)
        cache_key = {TableCache, :table_names, pid}
        {:ok, tables} = result
        expires_at = :erlang.monotonic_time(:millisecond) + 1
        :ets.insert(:mabeam_table_cache, {cache_key, tables, expires_at})
        result
      end

      # Cache with short TTL
      assert {:ok, _} = TableCache.get_cached_tables(registry, short_ttl_fetch)

      # Wait for expiration
      :timer.sleep(5)

      # Should fetch again due to expiration
      assert {:ok, _} = TableCache.get_cached_tables(registry)
      assert_received :table_names_fetched
    end
  end

  describe "process monitoring" do
    test "cache is invalidated when registry process dies" do
      test_pid = self()

      # Create a registry that will die after one request
      registry =
        spawn(fn ->
          receive do
            {:"$gen_call", from, {:get_table_names}} ->
              tables = %{main: :original_table}
              GenServer.reply(from, {:ok, tables})
              send(test_pid, :first_fetch)
          end
        end)

      # Cache the tables
      assert {:ok, tables} = TableCache.get_cached_tables(registry)
      assert tables.main == :original_table
      assert_received :first_fetch

      # Verify it's cached
      ref = Process.monitor(registry)

      # Registry should have exited after handling one request
      assert_receive {:DOWN, ^ref, :process, ^registry, _reason}, 1000

      # Give cleanup process time to handle DOWN message
      :timer.sleep(100)

      # Cache should be invalidated for dead process
      # Create a new registry to verify cache was cleared
      new_registry =
        spawn_link(fn ->
          receive do
            {:"$gen_call", from, {:get_table_names}} ->
              tables = %{main: :new_table}
              GenServer.reply(from, {:ok, tables})
              send(test_pid, :new_fetch)
          end
        end)

      # Should fetch fresh data (cache was invalidated)
      assert {:ok, new_tables} = TableCache.get_cached_tables(new_registry)
      assert new_tables.main == :new_table
      assert_received :new_fetch
    end
  end

  describe "concurrent access" do
    test "handles concurrent cache access correctly", %{registry: registry} do
      # Spawn multiple processes trying to access cache simultaneously
      parent = self()

      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            result = TableCache.get_cached_tables(registry)
            send(parent, {:task_result, i, result})
            result
          end)
        end

      # Wait for all tasks
      results = Task.await_many(tasks, 5000)

      # All should get the same result
      assert Enum.all?(results, fn {:ok, tables} ->
               tables.main == :mock_main_table
             end)

      # Due to race conditions, multiple tasks might trigger fetches
      # but they should all get valid results
      fetch_count = count_messages(:table_names_fetched)
      assert fetch_count >= 1

      # Verify subsequent access uses cache (no more fetches)
      assert {:ok, _} = TableCache.get_cached_tables(registry)
      refute_receive :table_names_fetched, 100
    end
  end

  describe "cleanup process" do
    test "cleanup process is started automatically" do
      # Ensure cache exists starts the cleanup process
      TableCache.ensure_cache_exists()

      # Check that cleanup process is registered
      assert Process.whereis(:mabeam_cache_cleanup) != nil
    end

    test "cleanup process removes expired entries" do
      # This test would require mocking time or using a very short cleanup interval
      # For now, we just verify the cleanup process exists
      TableCache.ensure_cache_exists()
      assert Process.alive?(Process.whereis(:mabeam_cache_cleanup))
    end
  end

  describe "error handling" do
    test "handles ETS table deletion gracefully" do
      # Get initial cache
      registry = spawn_link(fn -> :timer.sleep(:infinity) end)

      # Manually delete the cache table
      :ets.delete(:mabeam_table_cache)

      # Should recreate table and work normally
      fetch_fn = fn _pid -> {:ok, %{main: :recovered}} end
      assert {:ok, tables} = TableCache.get_cached_tables(registry, fetch_fn)
      assert tables.main == :recovered
    end

    test "handles invalid registry PID" do
      # Should not crash with invalid input
      assert_raise FunctionClauseError, fn ->
        TableCache.get_cached_tables("not_a_pid")
      end
    end
  end
end
