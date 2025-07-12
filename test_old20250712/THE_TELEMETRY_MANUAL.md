# The Foundation Telemetry Manual

## Overview

The Foundation telemetry system provides comprehensive observability for Elixir applications, enabling event-driven testing, performance monitoring, and system health tracking without relying on sleep-based timing hacks.

## Quick Start

### 1. Basic Event Emission

```elixir
# Import the telemetry module
alias Foundation.Telemetry

# Emit a simple event
Telemetry.emit([:my_app, :user, :created], %{count: 1}, %{user_id: 123})

# Emit a service lifecycle event
Telemetry.service_started(MyApp.Worker, %{config: config})

# Track async operations
Telemetry.async_started(:data_import, %{file: "users.csv"})
# ... perform operation ...
Telemetry.async_completed(:data_import, duration_ms, %{records: 1000})
```

### 2. Event-Driven Testing

```elixir
# Use the test helpers
use Foundation.TelemetryTestHelpers

test "service emits proper events" do
  # Assert a specific event is emitted
  assert_telemetry_event [:foundation, :cache, :hit],
    %{},  # Expected measurements (can use pattern matching)
    %{key: :my_key} do  # Expected metadata
    
    Cache.get(:my_key)
  end
end

test "complex operation emits events in order" do
  # Assert multiple events occur in sequence
  assert_telemetry_order [
    [:foundation, :request, :start],
    [:foundation, :auth, :verified],
    [:foundation, :request, :complete]
  ] do
    handle_authenticated_request()
  end
end
```

## Core Concepts

### Event Structure

Every telemetry event consists of three parts:

1. **Event Name** - A list of atoms identifying the event
   - Convention: `[:foundation, :component, :action]`
   - Examples: `[:foundation, :cache, :hit]`, `[:foundation, :circuit_breaker, :opened]`

2. **Measurements** - Numeric values associated with the event
   - Common measurements: `:duration`, `:count`, `:size`, `:queue_length`
   - Always include units in microseconds for duration

3. **Metadata** - Additional context about the event
   - Common metadata: `:service`, `:node`, `:trace_id`, error details
   - Keep metadata serializable (no PIDs, functions, etc.)

### Event Categories

#### Service Lifecycle Events
- `[:foundation, :service, :started]` - Service initialization complete
- `[:foundation, :service, :stopped]` - Service shutdown
- `[:foundation, :service, :error]` - Service encountered an error

#### Async Operation Events
- `[:foundation, :async, :started]` - Async operation began
- `[:foundation, :async, :completed]` - Async operation succeeded
- `[:foundation, :async, :failed]` - Async operation failed

#### Resource Management Events
- `[:foundation, :resource, :acquired]` - Resource obtained
- `[:foundation, :resource, :released]` - Resource returned
- `[:foundation, :resource, :exhausted]` - No resources available

#### Performance Events
- `[:foundation, :metrics, :response_time]` - Response time measurement
- `[:foundation, :circuit_breaker, :state_change]` - Circuit breaker state transition

## Test Helpers

### Event Assertion

```elixir
# Basic assertion
assert_telemetry_event [:my_app, :task, :completed] do
  MyApp.run_task()
end

# With measurement assertions
assert_telemetry_event [:my_app, :api, :call],
  %{duration: duration} when duration < 1000,
  %{endpoint: "/users"} do
  
  make_api_call("/users")
end

# With timeout
assert_telemetry_event [:my_app, :slow, :operation],
  %{}, %{}, timeout: 5000 do
  
  slow_operation()
end
```

### Event Capture

```elixir
# Capture all events during execution
{events, result} = with_telemetry_capture do
  complex_operation()
end

# Capture specific events
{events, result} = with_telemetry_capture events: [[:foundation, :cache, :_]] do
  cache_operations()
end

# Analyze captured events
hits = Enum.count(events, fn {event, _, _, _} -> 
  event == [:foundation, :cache, :hit] 
end)
```

### Waiting for Events

```elixir
# Wait for a single event
{:ok, {event, measurements, metadata}} = wait_for_telemetry_event(
  [:my_app, :job, :completed],
  timeout: 2000
)

# Wait for multiple events
{:ok, events} = wait_for_telemetry_events([
  [:my_app, :step, :one],
  [:my_app, :step, :two],
  [:my_app, :step, :three]
], timeout: 5000)
```

### Performance Measurement

```elixir
# Measure operation performance
metrics = measure_telemetry_performance [:foundation, :db, :query] do
  Enum.map(1..100, &query_user/1)
end

assert metrics.count == 100
assert metrics.average_duration < 10_000  # microseconds
```

### Refuting Events

```elixir
# Ensure an event is NOT emitted
refute_telemetry_event [:my_app, :error, :critical] do
  safe_operation()
end
```

## Service Instrumentation

### Instrumenting a GenServer

```elixir
defmodule MyApp.Worker do
  use GenServer
  alias Foundation.Telemetry

  def init(args) do
    Telemetry.service_started(__MODULE__, %{args: args})
    {:ok, initial_state}
  end

  def terminate(reason, state) do
    Telemetry.service_stopped(__MODULE__, %{reason: reason})
  end

  def handle_call(:work, _from, state) do
    Telemetry.span [:my_app, :worker, :work], %{request_id: state.request_id} do
      # Automatically tracks start, stop, and exceptions
      perform_work(state)
    end
  end
end
```

### Instrumenting Operations

```elixir
defmodule MyApp.DataProcessor do
  alias Foundation.Telemetry

  def process_batch(items) do
    trace_id = Telemetry.generate_trace_id()
    
    Telemetry.async_started(:batch_processing, 
      Telemetry.with_trace(trace_id, %{
        batch_size: length(items)
      })
    )
    
    start_time = System.monotonic_time()
    
    try do
      results = Enum.map(items, &process_item/1)
      duration = System.monotonic_time() - start_time
      
      Telemetry.async_completed(:batch_processing, duration,
        Telemetry.with_trace(trace_id, %{
          success_count: length(results)
        })
      )
      
      {:ok, results}
    rescue
      error ->
        Telemetry.async_failed(:batch_processing, error,
          Telemetry.with_trace(trace_id, %{
            failed_at: "processing"
          })
        )
        {:error, error}
    end
  end
end
```

## Best Practices

### 1. Event Naming
- Use consistent hierarchical naming
- Start with your app name or `:foundation`
- Use descriptive action names
- Keep names under 5 atoms

### 2. Measurements
- Always include units (e.g., `duration_ms`, `size_bytes`)
- Use native time units from `System.monotonic_time()`
- Keep measurements numeric
- Avoid calculating rates in events (do it in consumers)

### 3. Metadata
- Include enough context to debug issues
- Add trace IDs for distributed tracing
- Keep metadata lightweight
- Avoid including large data structures

### 4. Testing
- Replace ALL `Process.sleep()` with event assertions
- Use appropriate timeouts (default 5 seconds is usually enough)
- Test both success and failure scenarios
- Verify event ordering for complex flows

### 5. Performance
- Telemetry has minimal overhead (~1-2 microseconds)
- But avoid emitting events in tight loops
- Consider sampling for high-frequency events
- Batch events when appropriate

## Common Patterns

### Circuit Breaker Protection

```elixir
test "circuit breaker opens after failures" do
  # Force failures
  for _ <- 1..5 do
    MyApp.risky_operation()
  end
  
  # Assert circuit opened
  assert_telemetry_event [:foundation, :circuit_breaker, :state_change],
    %{},
    %{from_state: :closed, to_state: :open} do
    
    MyApp.risky_operation()
  end
end
```

### Resource Pool Monitoring

```elixir
test "connection pool handles load" do
  # Monitor pool metrics
  assert poll_with_telemetry fn ->
    {:ok, metrics} = get_latest_telemetry_metrics([:foundation, :pool, :stats])
    metrics.available_connections > 0
  end, timeout: 2000
  
  # Verify no exhaustion
  refute_telemetry_event [:foundation, :resource, :exhausted] do
    tasks = for _ <- 1..10, do: Task.async(&use_connection/0)
    Task.await_many(tasks)
  end
end
```

### Multi-Service Coordination

```elixir
test "services coordinate properly" do
  # Capture all coordination events
  {events, _result} = with_telemetry_capture events: [
    [:foundation, :service, :_],
    [:foundation, :coordination, :_]
  ] do
    MyApp.coordinate_services()
  end
  
  # Verify coordination pattern
  assert service_started_before_coordination?(events)
  assert all_services_participated?(events)
end
```

## Troubleshooting

### Event Not Emitted
1. Check event name spelling
2. Verify the code path is executed
3. Ensure telemetry is properly initialized
4. Check for try/rescue blocks swallowing errors

### Timeout in Tests
1. Increase timeout in assertion options
2. Check if operation is actually async
3. Verify event names match exactly
4. Look for race conditions

### Performance Issues
1. Check event emission frequency
2. Look for synchronous event handlers
3. Verify no heavy computation in handlers
4. Consider event sampling

## Migration Guide

### Replacing Process.sleep

```elixir
# OLD - Brittle and slow
test "cache expires entries" do
  Cache.put(:key, "value", ttl: 100)
  Process.sleep(150)  # Bad!
  assert Cache.get(:key) == nil
end

# NEW - Event-driven and fast
test "cache expires entries" do
  Cache.put(:key, "value", ttl: 100)
  
  assert_telemetry_event [:foundation, :cache, :miss],
    %{},
    %{key: :key, reason: :expired} do
    
    # Wait for expiration using events
    wait_for_telemetry_event([:foundation, :cache, :cleanup], timeout: 200)
    Cache.get(:key)
  end
end
```

### Adding Telemetry to Existing Code

1. Identify key operations and state changes
2. Add telemetry events at operation boundaries
3. Include relevant measurements and metadata
4. Write tests using telemetry assertions
5. Remove any Process.sleep calls
6. Add performance tracking where needed

## Summary

The Foundation telemetry system transforms testing from sleep-based hoping to event-driven certainty. By instrumenting your code with telemetry events and using the comprehensive test helpers, you can:

- Write faster, more reliable tests
- Gain visibility into system behavior
- Track performance automatically
- Debug issues with rich context
- Build observable, production-ready systems

Remember: If you're using `Process.sleep` in a test, you're doing it wrong. There's always a telemetry event you can wait for instead!