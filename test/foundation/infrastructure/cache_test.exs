defmodule Foundation.Infrastructure.CacheTest do
  # Using registry isolation mode for Foundation Infrastructure Cache tests
  use Foundation.UnifiedTestFoundation, :registry
  alias Foundation.Infrastructure.Cache
  import Foundation.AsyncTestHelpers

  describe "basic cache operations" do
    test "get/put/delete cycle" do
      key = "test_key_#{System.unique_integer()}"
      value = %{data: "test_value"}

      # Initial get returns default
      assert Cache.get(key, :default) == :default

      # Put stores value
      assert :ok = Cache.put(key, value)

      # Get retrieves stored value
      assert Cache.get(key) == value

      # Delete removes value
      assert :ok = Cache.delete(key)
      assert Cache.get(key) == nil
    end

    test "TTL expiration" do
      key = "ttl_key_#{System.unique_integer()}"
      value = "expires_soon"

      # Put with 100ms TTL
      assert :ok = Cache.put(key, value, ttl: 100)
      assert Cache.get(key) == value

      # Wait for TTL expiration (deterministic check)
      wait_for(
        fn ->
          case Cache.get(key) do
            nil -> true
            _ -> nil
          end
        end,
        500
      )

      assert Cache.get(key) == nil
    end

    test "concurrent access safety" do
      key = "concurrent_key"

      # Spawn 100 processes doing put/get operations
      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            Cache.put("#{key}_#{i}", i)
            assert Cache.get("#{key}_#{i}") == i
          end)
        end

      # All should complete without errors
      Enum.each(tasks, &Task.await/1)
    end

    test "memory limits and eviction" do
      # Configure cache with small memory limit
      {:ok, _cache} = Cache.start_link(max_size: 10, name: :test_cache_limited)

      # Add more items than limit
      for i <- 1..20 do
        Cache.put("key_#{i}", String.duplicate("x", 1000), cache: :test_cache_limited)
      end

      # Verify some items were evicted
      stored_count =
        Enum.count(1..20, fn i ->
          Cache.get("key_#{i}", nil, cache: :test_cache_limited) != nil
        end)

      assert stored_count <= 10
    end
  end

  describe "rate limiting integration" do
    test "tracks request counts" do
      limiter_key = "api_rate_limit"
      # 1 second
      window = 1000

      # First request should succeed
      assert Cache.get(limiter_key, 0) == 0
      assert :ok = Cache.put(limiter_key, 1, ttl: window)

      # Increment counter
      current = Cache.get(limiter_key, 0)
      assert :ok = Cache.put(limiter_key, current + 1, ttl: window)
      assert Cache.get(limiter_key) == 2
    end
  end

  describe "error handling" do
    test "handles invalid keys gracefully" do
      assert Cache.get(nil, :default) == :default
      assert {:error, :invalid_key} = Cache.put(nil, "value")
      assert {:error, :invalid_key} = Cache.delete(nil)
    end

    test "handles large values" do
      key = "large_value"
      # 10MB value
      large_value = String.duplicate("x", 10_000_000)

      # Should either store or return error, not crash
      result = Cache.put(key, large_value)
      assert result == :ok or match?({:error, _}, result)
    end
  end
end
