# Foundation Telemetry Event Reference

This document provides a comprehensive reference for all telemetry events emitted by the Foundation framework.

## Core Foundation Events

### Service Lifecycle Events

#### `[:foundation, :service, :started]`
Emitted when a Foundation service starts.

**Measurements:**
- `timestamp` - System time when service started

**Metadata:**
- `service` - Service module name
- `node` - Node where service is running

#### `[:foundation, :service, :stopped]`
Emitted when a Foundation service stops.

**Measurements:**
- `timestamp` - System time when service stopped
- `uptime` - How long the service was running (milliseconds)

**Metadata:**
- `service` - Service module name
- `reason` - Stop reason

### Async Operation Events

#### `[:foundation, :async, :started]`
Emitted when an async operation begins.

**Measurements:**
- `timestamp` - System time when operation started

**Metadata:**
- `operation` - Operation identifier
- `module` - Module performing the operation

#### `[:foundation, :async, :completed]`
Emitted when an async operation completes successfully.

**Measurements:**
- `duration` - Operation duration (microseconds)
- `timestamp` - System time when operation completed

**Metadata:**
- `operation` - Operation identifier
- `result` - Operation result (if applicable)

#### `[:foundation, :async, :failed]`
Emitted when an async operation fails.

**Measurements:**
- `duration` - Operation duration before failure (microseconds)
- `timestamp` - System time when operation failed

**Metadata:**
- `operation` - Operation identifier
- `error` - Error details

### Resource Management Events

#### `[:foundation, :resource_manager, :acquired]`
Emitted when a resource is successfully acquired.

**Measurements:**
- `duration` - Time to acquire resource (nanoseconds)
- `timestamp` - System time when acquired

**Metadata:**
- `resource_type` - Type of resource acquired
- `token_id` - Unique token identifier

#### `[:foundation, :resource_manager, :released]`
Emitted when a resource is released.

**Measurements:**
- `duration` - How long resource was held (nanoseconds)
- `active_tokens` - Number of active tokens after release
- `memory_mb` - Current memory usage

**Metadata:**
- `token_id` - Token being released
- `resource_type` - Type of resource

#### `[:foundation, :resource_manager, :denied]`
Emitted when resource acquisition is denied.

**Measurements:**
- `timestamp` - System time when denied

**Metadata:**
- `resource_type` - Type of resource requested
- `reason` - Denial reason (e.g., :limit_exceeded)

#### `[:foundation, :resource_manager, :cleanup]`
Emitted after resource cleanup cycle completes.

**Measurements:**
- `duration` - Cleanup duration (nanoseconds)
- `expired_tokens` - Number of tokens cleaned up
- `active_tokens` - Number of remaining active tokens
- `memory_mb` - Current memory usage

**Metadata:**
- `timestamp` - System time of cleanup

### Circuit Breaker Events

#### `[:foundation, :circuit_breaker, :opened]`
Emitted when a circuit breaker opens due to failures.

**Measurements:**
- `failure_count` - Number of failures that triggered opening
- `timestamp` - System time when opened

**Metadata:**
- `service` - Service protected by circuit breaker
- `threshold` - Failure threshold that was exceeded

#### `[:foundation, :circuit_breaker, :closed]`
Emitted when a circuit breaker closes after recovery.

**Measurements:**
- `recovery_time` - Time spent in open state (milliseconds)
- `timestamp` - System time when closed

**Metadata:**
- `service` - Service protected by circuit breaker

#### `[:foundation, :circuit_breaker, :half_open]`
Emitted when a circuit breaker enters half-open state.

**Measurements:**
- `timestamp` - System time when entered half-open

**Metadata:**
- `service` - Service protected by circuit breaker

## Cache Events

#### `[:foundation, :cache, :hit]`
Emitted on cache hit.

**Measurements:**
- `duration` - Lookup duration (nanoseconds)
- `timestamp` - System time of hit

**Metadata:**
- `key` - Cache key accessed

#### `[:foundation, :cache, :miss]`
Emitted on cache miss.

**Measurements:**
- `duration` - Lookup duration (nanoseconds)
- `timestamp` - System time of miss

**Metadata:**
- `key` - Cache key accessed
- `reason` - Miss reason (:not_found or :expired)

#### `[:foundation, :cache, :put]`
Emitted when value is stored in cache.

**Measurements:**
- `duration` - Store duration (nanoseconds)
- `timestamp` - System time of put

**Metadata:**
- `key` - Cache key stored
- `ttl` - Time-to-live (if set)

#### `[:foundation, :cache, :delete]`
Emitted when value is deleted from cache.

**Measurements:**
- `duration` - Delete duration (nanoseconds)
- `timestamp` - System time of delete

**Metadata:**
- `key` - Cache key deleted

#### `[:foundation, :cache, :cleanup]`
Emitted after cache cleanup cycle.

**Measurements:**
- `duration` - Cleanup duration (nanoseconds)
- `expired_count` - Number of expired entries removed
- `timestamp` - System time of cleanup

**Metadata:**
- None

## JidoSystem Task Events

#### `[:jido_system, :task, :started]`
Emitted when task processing begins.

**Measurements:**
- `timestamp` - System time when task started

**Metadata:**
- `task_id` - Unique task identifier
- `task_type` - Type of task
- `agent_id` - Agent processing the task

#### `[:jido_system, :task, :completed]`
Emitted when task completes successfully.

**Measurements:**
- `duration` - Task processing duration (microseconds)
- `timestamp` - System time when task completed

**Metadata:**
- `task_id` - Unique task identifier
- `result` - Task result (:success)
- `agent_id` - Agent that processed the task

#### `[:jido_system, :task, :failed]`
Emitted when task processing fails.

**Measurements:**
- `timestamp` - System time when task failed

**Metadata:**
- `task_id` - Unique task identifier
- `error` - Error details
- `agent_id` - Agent that attempted the task

## Agent Events

#### `[:jido_system, :agent, :started]`
Emitted when a JidoSystem agent starts.

**Measurements:**
- `timestamp` - System time when agent started

**Metadata:**
- `agent_id` - Agent identifier
- `agent_type` - Type of agent

#### `[:jido_system, :agent, :stopped]`
Emitted when a JidoSystem agent stops.

**Measurements:**
- `timestamp` - System time when agent stopped
- `uptime` - How long agent was running

**Metadata:**
- `agent_id` - Agent identifier
- `reason` - Stop reason

#### `[:jido_system, :agent, :error]`
Emitted when an agent encounters an error.

**Measurements:**
- `timestamp` - System time of error

**Metadata:**
- `agent_id` - Agent identifier
- `error` - Error details

## Sensor Events

#### `[:jido_system, :performance_sensor, :analysis_completed]`
Emitted when agent performance analysis completes.

**Measurements:**
- `duration` - Analysis duration (nanoseconds)
- `agents_analyzed` - Number of agents analyzed
- `issues_detected` - Number of performance issues found
- `timestamp` - System time of completion

**Metadata:**
- `sensor_id` - Sensor identifier
- `signal_type` - Type of signal generated

#### `[:jido_system, :performance_sensor, :agent_data_collected]`
Emitted when performance data is collected for an individual agent.

**Measurements:**
- `duration` - Collection duration (nanoseconds)
- `memory_mb` - Agent memory usage in MB
- `queue_length` - Message queue length
- `timestamp` - System time of collection

**Metadata:**
- `agent_id` - Agent identifier
- `agent_type` - Type of agent
- `is_responsive` - Whether agent is responsive

#### `[:jido_system, :health_sensor, :analysis_completed]`
Emitted when system health analysis completes.

**Measurements:**
- `duration` - Analysis duration (nanoseconds)
- `memory_usage_percent` - System memory usage percentage
- `process_count` - Number of processes
- `timestamp` - System time of completion

**Metadata:**
- `sensor_id` - Sensor identifier
- `health_status` - Overall health status
- `signal_type` - Type of signal generated

#### `[:jido_system, :health_monitor, :health_check]`
Emitted when health monitor checks an agent.

**Measurements:**
- `duration` - Check duration (milliseconds)

**Metadata:**
- `agent_pid` - Agent process ID
- `status` - Health status result

#### `[:jido_system, :health_monitor, :agent_died]`
Emitted when a monitored agent dies.

**Measurements:**
- None

**Metadata:**
- `agent_pid` - Agent process ID
- `reason` - Death reason

## Using Telemetry Events

### Attaching Handlers

```elixir
:telemetry.attach(
  "my-handler",
  [:foundation, :cache, :hit],
  fn event, measurements, metadata, config ->
    IO.puts("Cache hit for key: #{metadata.key}")
  end,
  %{}
)
```

### Test Helpers

The Foundation provides test helpers for working with telemetry:

```elixir
use Foundation.TelemetryTestHelpers

# Wait for an event
{:ok, {event, measurements, metadata}} = 
  wait_for_telemetry_event([:foundation, :cache, :cleanup], timeout: 1000)

# Assert an event is emitted
assert_telemetry_event [:foundation, :resource_manager, :acquired],
                       %{},
                       %{resource_type: :memory} do
  # Code that should emit the event
end
```

### Metrics Collection

Example of collecting metrics from telemetry events:

```elixir
defmodule MyApp.Metrics do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(_) do
    events = [
      [:foundation, :cache, :hit],
      [:foundation, :cache, :miss],
      [:foundation, :resource_manager, :acquired],
      [:foundation, :resource_manager, :denied]
    ]

    :telemetry.attach_many(
      "my-metrics",
      events,
      &__MODULE__.handle_event/4,
      %{}
    )

    {:ok, %{}}
  end

  def handle_event([:foundation, :cache, :hit], measurements, metadata, _config) do
    # Track cache hit rate
    :ok
  end

  def handle_event([:foundation, :cache, :miss], measurements, metadata, _config) do
    # Track cache miss rate
    :ok
  end

  def handle_event([:foundation, :resource_manager, :acquired], measurements, metadata, _config) do
    # Track resource acquisition latency
    :ok
  end

  def handle_event([:foundation, :resource_manager, :denied], measurements, metadata, _config) do
    # Track resource denial rate
    :ok
  end
end
```

## Best Practices

1. **Event Naming**: Follow the pattern `[:app, :component, :action]`
2. **Measurements**: Include timing information (duration, timestamp)
3. **Metadata**: Include contextual information for debugging
4. **Performance**: Keep handlers fast; offload heavy work to separate processes
5. **Error Handling**: Handlers should not crash; wrap in try/catch if needed

## Adding New Events

When adding new telemetry events:

1. Define the event in the appropriate module
2. Document it in this reference
3. Include meaningful measurements and metadata
4. Add test coverage using telemetry test helpers
5. Consider backwards compatibility

Example:

```elixir
def my_operation(args) do
  start_time = System.monotonic_time()
  
  result = do_work(args)
  
  :telemetry.execute(
    [:my_app, :my_component, :operation_completed],
    %{
      duration: System.monotonic_time() - start_time,
      timestamp: System.system_time()
    },
    %{
      operation: :my_operation,
      args: args,
      result: result
    }
  )
  
  result
end
```