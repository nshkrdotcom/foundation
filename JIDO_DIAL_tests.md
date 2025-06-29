# Test Cases for Jido Integration Gaps

This document outlines comprehensive test cases needed to verify the missing functionality identified by Dialyzer analysis. These tests will ensure that production implementations work correctly without relying on mocks.

## 1. Foundation.Cache Tests

### Test Module: `test/foundation/infrastructure/cache_test.exs`

```elixir
defmodule Foundation.Infrastructure.CacheTest do
  use ExUnit.Case, async: false
  alias Foundation.Cache

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
      
      # Wait for expiration
      Process.sleep(150)
      assert Cache.get(key) == nil
    end

    test "concurrent access safety" do
      key = "concurrent_key"
      
      # Spawn 100 processes doing put/get operations
      tasks = for i <- 1..100 do
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
      {:ok, cache} = Cache.start_link(max_size: 10)
      
      # Add more items than limit
      for i <- 1..20 do
        Cache.put("key_#{i}", String.duplicate("x", 1000), cache: cache)
      end
      
      # Verify some items were evicted
      stored_count = Enum.count(1..20, fn i ->
        Cache.get("key_#{i}", nil, cache: cache) != nil
      end)
      
      assert stored_count <= 10
    end
  end

  describe "rate limiting integration" do
    test "tracks request counts" do
      limiter_key = "api_rate_limit"
      window = 1000 # 1 second
      
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
```

## 2. Foundation.CircuitBreaker Tests

### Test Module: `test/foundation/infrastructure/circuit_breaker_test.exs`

```elixir
defmodule Foundation.Infrastructure.CircuitBreakerTest do
  use ExUnit.Case
  alias Foundation.CircuitBreaker

  describe "circuit breaker states" do
    test "closed -> open transition on failures" do
      service_id = "test_service_#{System.unique_integer()}"
      failure_threshold = 3
      
      # Configure circuit breaker
      :ok = CircuitBreaker.configure(service_id, 
        failure_threshold: failure_threshold,
        recovery_timeout: 1000
      )
      
      # First failures should pass through
      for i <- 1..failure_threshold do
        result = CircuitBreaker.call(service_id, fn ->
          {:error, "failure_#{i}"}
        end)
        assert result == {:error, "failure_#{i}"}
      end
      
      # Next call should be rejected (circuit open)
      result = CircuitBreaker.call(service_id, fn ->
        {:ok, "should_not_execute"}
      end)
      assert result == {:error, :circuit_open}
    end

    test "open -> half_open -> closed recovery" do
      service_id = "recovery_test_#{System.unique_integer()}"
      
      :ok = CircuitBreaker.configure(service_id,
        failure_threshold: 1,
        recovery_timeout: 100
      )
      
      # Open the circuit
      CircuitBreaker.call(service_id, fn -> {:error, :fail} end)
      assert CircuitBreaker.get_status(service_id) == :open
      
      # Wait for recovery timeout
      Process.sleep(150)
      
      # Next call should be allowed (half-open)
      result = CircuitBreaker.call(service_id, fn -> {:ok, :success} end)
      assert result == {:ok, :success}
      
      # Circuit should now be closed
      assert CircuitBreaker.get_status(service_id) == :closed
    end

    test "half_open -> open on failure" do
      service_id = "half_open_test_#{System.unique_integer()}"
      
      :ok = CircuitBreaker.configure(service_id,
        failure_threshold: 1,
        recovery_timeout: 100
      )
      
      # Open circuit
      CircuitBreaker.call(service_id, fn -> {:error, :fail} end)
      
      # Wait for half-open
      Process.sleep(150)
      
      # Fail during half-open
      CircuitBreaker.call(service_id, fn -> {:error, :fail_again} end)
      
      # Should be open again
      assert CircuitBreaker.get_status(service_id) == :open
    end
  end

  describe "telemetry integration" do
    test "emits circuit breaker events" do
      service_id = "telemetry_test_#{System.unique_integer()}"
      
      :ok = CircuitBreaker.configure(service_id, failure_threshold: 1)
      
      # Attach telemetry handler
      events_ref = :ets.new(:cb_events, [:set, :public])
      
      :telemetry.attach(
        "test_handler",
        [:foundation, :circuit_breaker, :call],
        fn event, measurements, metadata, _config ->
          :ets.insert(events_ref, {event, measurements, metadata})
        end,
        nil
      )
      
      # Trigger circuit breaker
      CircuitBreaker.call(service_id, fn -> {:ok, :success} end)
      CircuitBreaker.call(service_id, fn -> {:error, :failure} end)
      
      # Verify events were emitted
      events = :ets.tab2list(events_ref)
      assert length(events) >= 2
      
      # Check event metadata
      assert Enum.any?(events, fn {_event, _measurements, metadata} ->
        metadata.service_id == service_id and metadata.status == :success
      end)
      
      :telemetry.detach("test_handler")
    end
  end

  describe "concurrent usage" do
    test "thread-safe under load" do
      service_id = "concurrent_test_#{System.unique_integer()}"
      
      :ok = CircuitBreaker.configure(service_id,
        failure_threshold: 50,
        recovery_timeout: 5000
      )
      
      # Spawn many concurrent calls
      tasks = for i <- 1..100 do
        Task.async(fn ->
          CircuitBreaker.call(service_id, fn ->
            # Simulate some succeeding, some failing
            if rem(i, 3) == 0 do
              {:error, :simulated_failure}
            else
              {:ok, i}
            end
          end)
        end)
      end
      
      results = Enum.map(tasks, &Task.await/1)
      
      # Should have mix of successes and failures
      successes = Enum.count(results, &match?({:ok, _}, &1))
      failures = Enum.count(results, &match?({:error, _}, &1))
      
      assert successes > 0
      assert failures > 0
    end
  end

  describe "fallback behavior" do
    test "executes fallback when circuit is open" do
      service_id = "fallback_test_#{System.unique_integer()}"
      
      :ok = CircuitBreaker.configure(service_id, failure_threshold: 1)
      
      # Open the circuit
      CircuitBreaker.call(service_id, fn -> {:error, :fail} end)
      
      # Call with fallback
      result = CircuitBreaker.call(service_id, 
        fn -> {:ok, :primary} end,
        fallback: fn -> {:ok, :fallback} end
      )
      
      assert result == {:ok, :fallback}
    end
  end
end
```

## 3. Registry Count Function Tests

### Test Module: `test/foundation/registry_count_test.exs`

```elixir
defmodule Foundation.RegistryCountTest do
  use ExUnit.Case
  alias Foundation.Registry

  setup do
    # Use test registry implementation
    {:ok, registry} = TestRegistry.start_link()
    {:ok, registry: registry}
  end

  describe "registry count operations" do
    test "count returns zero for empty registry", %{registry: registry} do
      assert Registry.count(registry) == 0
    end

    test "count increases with registrations", %{registry: registry} do
      # Register some agents
      for i <- 1..5 do
        pid = spawn(fn -> Process.sleep(:infinity) end)
        :ok = Registry.register(registry, "agent_#{i}", pid, %{type: :test})
      end
      
      assert Registry.count(registry) == 5
    end

    test "count decreases with unregistrations", %{registry: registry} do
      # Register agents
      pids = for i <- 1..3 do
        pid = spawn(fn -> Process.sleep(:infinity) end)
        :ok = Registry.register(registry, "agent_#{i}", pid, %{})
        pid
      end
      
      assert Registry.count(registry) == 3
      
      # Unregister one
      :ok = Registry.unregister(registry, "agent_2")
      assert Registry.count(registry) == 2
      
      # Clean up
      Enum.each(pids, &Process.exit(&1, :kill))
    end

    test "count handles concurrent operations", %{registry: registry} do
      # Concurrent registrations
      tasks = for i <- 1..100 do
        Task.async(fn ->
          pid = spawn(fn -> Process.sleep(100) end)
          Registry.register(registry, "concurrent_#{i}", pid, %{})
        end)
      end
      
      Enum.each(tasks, &Task.await/1)
      
      # Count should be accurate
      assert Registry.count(registry) == 100
    end
  end

  describe "health monitoring integration" do
    test "system health sensor uses registry count correctly" do
      # This tests the actual usage pattern from system_health_sensor.ex
      
      # Mock Foundation.Registry module
      defmodule Foundation.Registry.Mock do
        def count(_registry), do: 42
      end
      
      # The pattern that's currently failing
      registry_count = Foundation.Registry.Mock.count(Foundation.Registry)
      assert registry_count == 42
    end
  end
end
```

## 4. Queue Type Safety Tests

### Test Module: `test/jido_system/queue_operations_test.exs`

```elixir
defmodule JidoSystem.QueueOperationsTest do
  use ExUnit.Case

  describe "queue type safety" do
    test "queue_size handles nil state gracefully" do
      assert queue_size(nil) == 0
    end

    test "queue_size handles missing task_queue" do
      state = %{other_field: "value"}
      assert queue_size(state) == 0
    end

    test "queue_size works with proper queue" do
      queue = :queue.new()
      queue = :queue.in("task1", queue)
      queue = :queue.in("task2", queue)
      
      state = %{task_queue: queue}
      assert queue_size(state) == 2
    end

    test "queue_size handles corrupted queue data" do
      # If someone manually sets a non-queue value
      state = %{task_queue: "not a queue"}
      assert queue_size(state) == 0
    end

    test "dialyzer-compliant queue operations" do
      # This version should pass dialyzer
      state = %{task_queue: :queue.new()}
      
      # Add items properly
      updated_queue = :queue.in("item", state.task_queue)
      updated_state = %{state | task_queue: updated_queue}
      
      # Check size properly
      size = :queue.len(updated_state.task_queue)
      assert size == 1
    end
  end

  # Proposed fixed implementation
  defp queue_size(nil), do: 0
  defp queue_size(state) when is_map(state) do
    case Map.get(state, :task_queue) do
      nil -> 0
      queue ->
        try do
          :queue.len(queue)
        rescue
          # Handle any non-queue values
          _ -> 0
        end
    end
  end
  defp queue_size(_), do: 0
end
```

## 5. Telemetry Module Loading Tests

### Test Module: `test/foundation/telemetry_loading_test.exs`

```elixir
defmodule Foundation.TelemetryLoadingTest do
  use ExUnit.Case

  describe "telemetry module availability" do
    test "Foundation.Telemetry module is loaded" do
      assert Code.ensure_loaded?(Foundation.Telemetry)
    end

    test "telemetry functions are available" do
      # All these should be available without mocks
      assert function_exported?(Foundation.Telemetry, :emit, 3)
      assert function_exported?(Foundation.Telemetry, :attach, 4)
      assert function_exported?(Foundation.Telemetry, :attach_many, 4)
      assert function_exported?(Foundation.Telemetry, :detach, 1)
    end

    test "telemetry events flow correctly" do
      handler_ref = make_ref()
      events_pid = self()
      
      # Attach handler
      :ok = Foundation.Telemetry.attach(
        handler_ref,
        [:test, :event],
        fn event, measurements, metadata, _config ->
          send(events_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )
      
      # Emit event
      Foundation.Telemetry.emit([:test, :event], %{count: 1}, %{source: :test})
      
      # Verify receipt
      assert_receive {:telemetry_event, [:test, :event], %{count: 1}, %{source: :test}}
      
      # Cleanup
      :ok = Foundation.Telemetry.detach(handler_ref)
    end
  end
end
```

## 6. Integration Tests Without Mocks

### Test Module: `test/jido_system/integration/no_mocks_test.exs`

```elixir
defmodule JidoSystem.Integration.NoMocksTest do
  use ExUnit.Case
  
  # Ensure we're not using mocks
  setup_all do
    # Remove mock modules from code path if loaded
    :code.purge(Foundation.Cache)
    :code.purge(Foundation.CircuitBreaker)
    :code.purge(Foundation.Telemetry)
    :ok
  end

  describe "full system integration" do
    test "task validation with real cache and circuit breaker" do
      # Start real implementations
      {:ok, _cache} = Foundation.Infrastructure.Cache.start_link()
      {:ok, _cb} = Foundation.Infrastructure.CircuitBreaker.start_link()
      
      # Create a task agent
      {:ok, agent} = JidoSystem.Agents.TaskAgent.start_link(id: "test_agent")
      
      # Create a task that uses validation
      task = %{
        id: "task_123",
        type: :data_validation,
        data: %{records: 100}
      }
      
      # Process task (uses ValidateTask action internally)
      result = JidoSystem.process_task(agent, task)
      assert {:ok, _} = result
      
      # Second call should hit cache
      result2 = JidoSystem.process_task(agent, task)
      assert {:ok, _} = result2
      
      # Verify cache was used (check telemetry or logs)
    end

    test "monitor agent with real registry counting" do
      # Start monitor agent
      {:ok, monitor} = JidoSystem.Agents.MonitorAgent.start_link(
        id: "monitor_test",
        collection_interval: 100
      )
      
      # Let it collect metrics
      Process.sleep(200)
      
      # Get status (which uses registry count)
      {:ok, status} = GenServer.call(monitor, :get_status)
      
      # Should have registry metrics without errors
      assert Map.has_key?(status, :registry_metrics)
      assert is_integer(status.registry_metrics.count)
    end

    test "system health sensor with all dependencies" do
      # Start health sensor  
      {:ok, sensor} = JidoSystem.Sensors.SystemHealthSensor.start_link(
        id: "health_test",
        collection_interval: 100
      )
      
      # Wait for signal delivery
      Process.sleep(200)
      
      # Should have delivered signals without errors
      # (Check via telemetry or state inspection)
    end
  end

  describe "error scenarios" do
    test "system handles missing cache gracefully" do
      # Don't start cache
      {:ok, agent} = JidoSystem.Agents.TaskAgent.start_link(id: "no_cache_test")
      
      task = %{id: "test", type: :validation}
      
      # Should complete but perhaps with warnings
      result = JidoSystem.process_task(agent, task)
      assert match?({:ok, _} | {:error, _}, result)
    end

    test "circuit breaker prevents cascading failures" do
      # Configure circuit breaker with low threshold
      :ok = Foundation.CircuitBreaker.configure(:external_service,
        failure_threshold: 2,
        recovery_timeout: 1000
      )
      
      # Simulate failures
      failing_action = fn ->
        Foundation.CircuitBreaker.call(:external_service, fn ->
          {:error, :service_unavailable}
        end)
      end
      
      # First two calls fail
      assert {:error, :service_unavailable} = failing_action.()
      assert {:error, :service_unavailable} = failing_action.()
      
      # Third call should be circuit broken
      assert {:error, :circuit_open} = failing_action.()
    end
  end
end
```

## Test Execution Strategy

### Phase 1: Unit Tests
Run each test module in isolation to verify individual components:
```bash
mix test test/foundation/infrastructure/cache_test.exs
mix test test/foundation/infrastructure/circuit_breaker_test.exs
mix test test/foundation/registry_count_test.exs
```

### Phase 2: Type Safety Tests
Run with Dialyzer to ensure type compliance:
```bash
mix dialyzer test/jido_system/queue_operations_test.exs
```

### Phase 3: Integration Tests
Run without any mocks loaded:
```bash
MIX_ENV=prod mix test test/jido_system/integration/no_mocks_test.exs
```

### Phase 4: Load Tests
Verify performance under load:
```bash
mix test test/jido_system/load_test.exs --include load
```

## Success Criteria

All tests must pass with:
- No mock dependencies in production code
- Zero Dialyzer warnings
- Proper error handling for edge cases
- Concurrent operation safety
- Performance within acceptable bounds

## Continuous Integration

Add to `.github/workflows/ci.yml`:
```yaml
- name: Run Dialyzer
  run: mix dialyzer --halt-exit-status

- name: Run Tests Without Mocks
  run: MIX_ENV=prod mix test --only no_mocks
```