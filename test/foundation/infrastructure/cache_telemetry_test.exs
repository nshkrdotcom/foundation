defmodule Foundation.Infrastructure.CacheTelemetryTest do
  use ExUnit.Case, async: true
  use Foundation.TelemetryTestHelpers

  alias Foundation.Infrastructure.Cache

  setup do
    {:ok, cache} = Cache.start_link(name: :"cache_telemetry_#{System.unique_integer()}")
    {:ok, cache: cache}
  end

  describe "cache telemetry events" do
    test "emits started event on initialization", %{cache: _cache} do
      # Start a new cache to capture the event
      assert_telemetry_event [:foundation, :cache, :started], %{}, %{} do
        {:ok, _} = Cache.start_link(name: :"cache_test_started_#{System.unique_integer()}")
      end
    end

    test "emits hit event on successful get", %{cache: cache} do
      Cache.put(:test_key, "test_value", cache: cache)

      {_event, measurements, _metadata, result} =
        assert_telemetry_event [:foundation, :cache, :hit],
                               %{},
                               %{key: :test_key} do
          Cache.get(:test_key, nil, cache: cache)
        end

      assert result == "test_value"
      assert is_integer(measurements.duration)
      assert measurements.duration > 0
    end

    test "emits miss event when key not found", %{cache: cache} do
      {_event, _measurements, metadata, result} =
        assert_telemetry_event [:foundation, :cache, :miss],
                               %{},
                               %{key: :missing_key, reason: :not_found} do
          Cache.get(:missing_key, :default, cache: cache)
        end

      assert result == :default
      assert metadata.reason == :not_found
    end

    test "emits miss event when key expired", %{cache: _cache} do
      # Create a cache with fast cleanup for this test
      {:ok, fast_cache} =
        Cache.start_link(
          name: :"cache_expiry_test_#{System.unique_integer()}",
          cleanup_interval: 200
        )

      Cache.put(:expiring_key, "value", cache: fast_cache, ttl: 10)

      # Wait just slightly longer than TTL to ensure expiry
      # This is the minimal sleep needed for time-based expiry
      :timer.sleep(15)

      {_event, _measurements, metadata, result} =
        assert_telemetry_event [:foundation, :cache, :miss],
                               %{},
                               %{key: :expiring_key, reason: :expired} do
          Cache.get(:expiring_key, :expired, cache: fast_cache)
        end

      assert result == :expired
      assert metadata.reason == :expired
    end

    test "emits put event on successful put", %{cache: cache} do
      {_event, measurements, metadata, result} =
        assert_telemetry_event [:foundation, :cache, :put],
                               %{},
                               %{key: :new_key, ttl: 1000} do
          Cache.put(:new_key, "new_value", cache: cache, ttl: 1000)
        end

      assert result == :ok
      assert is_integer(measurements.duration)
      assert metadata.ttl == 1000
    end

    test "emits delete event", %{cache: cache} do
      Cache.put(:delete_key, "value", cache: cache)

      {_event, _measurements, metadata, result} =
        assert_telemetry_event [:foundation, :cache, :delete],
                               %{},
                               %{key: :delete_key, existed: true} do
          Cache.delete(:delete_key, cache: cache)
        end

      assert result == :ok
      assert metadata.existed == true
    end

    test "emits cleared event", %{cache: cache} do
      Cache.put(:key1, "value1", cache: cache)
      Cache.put(:key2, "value2", cache: cache)
      Cache.put(:key3, "value3", cache: cache)

      {_event, measurements, _metadata, result} =
        assert_telemetry_event [:foundation, :cache, :cleared],
                               %{count: 3},
                               %{} do
          Cache.clear(cache: cache)
        end

      assert result == :ok
      assert measurements.count == 3
    end

    test "emits evicted event when cache is full", %{cache: _cache} do
      # Create a cache with max_size of 2
      {:ok, small_cache} =
        Cache.start_link(
          name: :"cache_eviction_#{System.unique_integer()}",
          max_size: 2
        )

      Cache.put(:key1, "value1", cache: small_cache)
      Cache.put(:key2, "value2", cache: small_cache)

      # This should trigger eviction of key1
      assert_telemetry_event [:foundation, :cache, :evicted],
                             %{},
                             %{key: :key1, reason: :size_limit} do
        Cache.put(:key3, "value3", cache: small_cache)
      end

      # Verify key1 was evicted
      assert Cache.get(:key1, nil, cache: small_cache) == nil
      assert Cache.get(:key2, nil, cache: small_cache) == "value2"
      assert Cache.get(:key3, nil, cache: small_cache) == "value3"
    end

    test "emits cleanup event during expiration cleanup" do
      # Create a cache with short cleanup interval
      {:ok, cleanup_cache} =
        Cache.start_link(
          name: :"cache_cleanup_#{System.unique_integer()}",
          cleanup_interval: 50
        )

      # Add some expiring entries
      Cache.put(:exp1, "value1", cache: cleanup_cache, ttl: 10)
      Cache.put(:exp2, "value2", cache: cleanup_cache, ttl: 10)
      Cache.put(:permanent, "value3", cache: cleanup_cache)

      # Wait for cleanup to trigger - the cleanup interval is 50ms
      # and entries expire after 10ms, so cleanup should find them
      {:ok, {_event, measurements, _metadata}} =
        wait_for_telemetry_event(
          [:foundation, :cache, :cleanup],
          timeout: 100
        )

      assert measurements.expired_count == 2
    end

    test "emits error event on invalid operations", %{cache: cache} do
      {_event, _measurements, metadata, result} =
        assert_telemetry_event [:foundation, :cache, :error],
                               %{},
                               %{error: :invalid_key, operation: :put} do
          Cache.put(nil, "value", cache: cache)
        end

      assert result == {:error, :invalid_key}
      assert metadata.error == :invalid_key
      assert metadata.operation == :put
    end
  end

  describe "telemetry performance tracking" do
    test "tracks operation durations", %{cache: cache} do
      # Measure multiple operations
      metrics =
        measure_telemetry_performance [:foundation, :cache, :put] do
          for i <- 1..10 do
            Cache.put(:"key_#{i}", "value_#{i}", cache: cache)
          end
        end

      assert metrics.count == 10
      assert metrics.average_duration > 0
      assert length(metrics.events) == 10
    end

    test "tracks cache hit rate", %{cache: cache} do
      # Populate cache
      for i <- 1..5 do
        Cache.put(:"key_#{i}", "value_#{i}", cache: cache)
      end

      # Track hits and misses
      {events, _} =
        with_telemetry_capture events: [
                                 [:foundation, :cache, :hit],
                                 [:foundation, :cache, :miss]
                               ] do
          # 5 hits
          for i <- 1..5 do
            Cache.get(:"key_#{i}", nil, cache: cache)
          end

          # 3 misses
          for i <- 6..8 do
            Cache.get(:"key_#{i}", nil, cache: cache)
          end
        end

      hits = Enum.count(events, fn {event, _, _, _} -> event == [:foundation, :cache, :hit] end)
      misses = Enum.count(events, fn {event, _, _, _} -> event == [:foundation, :cache, :miss] end)

      assert hits == 5
      assert misses == 3
    end
  end
end
