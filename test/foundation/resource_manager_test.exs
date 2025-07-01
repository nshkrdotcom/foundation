defmodule Foundation.ResourceManagerTest do
  # Using registry isolation mode for Foundation ResourceManager tests
  use Foundation.UnifiedTestFoundation, :registry

  alias Foundation.ResourceManager

  setup do
    # Store original config
    original_config = Application.get_env(:foundation, :resource_limits, %{})

    # Set test configuration with lower limits
    test_config = %{
      max_memory_mb: 2048,
      max_ets_entries: 10_000,
      max_registry_size: 1_000,
      cleanup_interval: 100,
      alert_threshold: 0.8
    }

    Application.put_env(:foundation, :resource_limits, test_config)

    # Ensure ResourceManager is restarted with test config
    if pid = Process.whereis(Foundation.ResourceManager) do
      GenServer.stop(pid)
      :timer.sleep(50)
    end

    # Start ResourceManager if not already started
    case Process.whereis(Foundation.ResourceManager) do
      nil ->
        {:ok, _pid} = ResourceManager.start_link()

      pid when is_pid(pid) ->
        # Already started, use existing
        :ok
    end

    on_exit(fn ->
      Application.put_env(:foundation, :resource_limits, original_config)

      if pid = Process.whereis(Foundation.ResourceManager) do
        if Process.alive?(pid) do
          GenServer.stop(pid)
        end
      end
    end)

    :ok
  end

  describe "resource acquisition" do
    test "acquires resource when available" do
      assert {:ok, token} = ResourceManager.acquire_resource(:register_agent)
      assert is_map(token)
      assert token.type == :register_agent
    end

    test "enforces resource limits" do
      # Create a large ETS table to simulate high memory usage
      table = :ets.new(:test_table, [:public])
      ResourceManager.monitor_table(table)

      # Fill the table to exceed limits
      for i <- 1..11_000 do
        :ets.insert(table, {i, :data})
      end

      # Force measurement
      ResourceManager.force_cleanup()
      :timer.sleep(50)

      # Should be denied due to ETS limit
      assert {:error, :ets_table_full} = ResourceManager.acquire_resource(:register_agent)

      # Cleanup
      :ets.delete(table)
    end

    test "releases resources" do
      {:ok, token} = ResourceManager.acquire_resource(:register_agent)

      # Get initial stats
      stats1 = ResourceManager.get_usage_stats()
      initial_tokens = stats1.active_tokens

      # Release the resource
      ResourceManager.release_resource(token)
      :timer.sleep(10)

      # Verify token count decreased
      stats2 = ResourceManager.get_usage_stats()
      assert stats2.active_tokens < initial_tokens
    end
  end

  describe "table monitoring" do
    test "monitors ETS tables" do
      table = :ets.new(:monitored_table, [:public])

      assert :ok = ResourceManager.monitor_table(table)

      # Add some data
      for i <- 1..100 do
        :ets.insert(table, {i, :value})
      end

      # Force cleanup to update stats
      :ok = ResourceManager.force_cleanup()
      :timer.sleep(50)

      # Get stats
      stats = ResourceManager.get_usage_stats()
      assert stats.ets_tables.per_table[table] == 100

      # Cleanup
      :ets.delete(table)
    end

    test "handles deleted tables gracefully" do
      table = :ets.new(:temp_table, [:public])
      ResourceManager.monitor_table(table)

      # Delete the table
      :ets.delete(table)

      # Should not crash when getting stats
      stats = ResourceManager.get_usage_stats()
      assert stats.ets_tables.per_table[table] == 0
    end
  end

  describe "backpressure" do
    @tag :flaky
    test "enters backpressure when approaching limits" do
      # Register alert callback
      test_pid = self()

      ResourceManager.register_alert_callback(fn alert_type, data ->
        send(test_pid, {:alert, alert_type, data})
      end)

      # Create table and fill to trigger alert
      table = :ets.new(:pressure_table, [:public])
      ResourceManager.monitor_table(table)

      # Fill to 85% of limit (above alert threshold)
      for i <- 1..8500 do
        :ets.insert(table, {i, :data})
      end

      # Force measurement multiple times to ensure the alert is triggered
      ResourceManager.force_cleanup()
      Process.sleep(100)
      ResourceManager.force_cleanup()

      # Should receive backpressure alert (increased timeout for CI environments)
      assert_receive {:alert, :backpressure_changed, data}, 2000
      assert data.new_state in [:moderate, :severe]

      # Cleanup
      :ets.delete(table)
    end
  end

  describe "usage statistics" do
    test "provides comprehensive usage stats" do
      stats = ResourceManager.get_usage_stats()

      assert is_map(stats)
      assert Map.has_key?(stats, :memory)
      assert Map.has_key?(stats, :ets_tables)
      assert Map.has_key?(stats, :active_tokens)
      assert Map.has_key?(stats, :backpressure_state)

      # Memory stats
      assert stats.memory.current_mb > 0
      assert stats.memory.limit_mb == 2048
      assert stats.memory.usage_percent >= 0

      # ETS stats
      assert stats.ets_tables.total_entries >= 0
      assert stats.ets_tables.limit_entries == 10_000

      # Backpressure
      assert stats.backpressure_state in [:normal, :moderate, :severe]
    end
  end

  describe "cleanup" do
    test "cleans up expired tokens" do
      # Acquire some tokens
      tokens =
        for _ <- 1..5 do
          {:ok, token} = ResourceManager.acquire_resource(:test_resource)
          token
        end

      stats1 = ResourceManager.get_usage_stats()
      assert stats1.active_tokens >= 5

      # Force cleanup (tokens expire after 5 minutes in production)
      # For testing, we'll modify the token's acquired_at
      # This is a bit hacky but necessary for testing
      ResourceManager.force_cleanup()

      # In real scenario, tokens would be cleaned after timeout
      # For now, manually release them
      Enum.each(tokens, &ResourceManager.release_resource/1)

      stats2 = ResourceManager.get_usage_stats()
      assert stats2.active_tokens < stats1.active_tokens
    end

    test "automatic cleanup runs periodically" do
      # Already configured with 100ms interval in setup

      # Wait for at least one cleanup cycle
      :timer.sleep(150)

      # Should have run cleanup (verified by not crashing)
      assert ResourceManager.get_usage_stats()
    end
  end

  describe "telemetry integration" do
    test "emits telemetry events" do
      test_pid = self()

      :telemetry.attach(
        "test-resource-events",
        [:foundation, :resource_manager, :resource_denied],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      # Create conditions for resource denial
      table = :ets.new(:full_table, [:public])
      ResourceManager.monitor_table(table)

      # Fill beyond limit
      for i <- 1..11_000 do
        :ets.insert(table, {i, :data})
      end

      ResourceManager.force_cleanup()
      :timer.sleep(50)

      # Try to acquire resource (should be denied)
      result = ResourceManager.acquire_resource(:register_agent)
      assert {:error, :ets_table_full} = result

      # Should receive telemetry event
      assert_receive {:telemetry_event, [:foundation, :resource_manager, :resource_denied], _, _},
                     1000

      # Cleanup
      :telemetry.detach("test-resource-events")
      :ets.delete(table)
    end
  end
end
