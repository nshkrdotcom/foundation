# Foundation Library - Complete Public API Documentation

## Table of Contents

1.  [Overview](#overview)
2.  [Getting Started](#getting-started)
3.  [Core Foundation API (`Foundation`)](#core-foundation-api-foundation)
4.  [Configuration API (`Foundation.Config`)](#configuration-api-foundation-config)
5.  [Events API (`Foundation.Events`)](#events-api-foundation-events)
6.  [Telemetry API (`Foundation.Telemetry`)](#telemetry-api-foundation-telemetry)
7.  [Utilities API (`Foundation.Utils`)](#utilities-api-foundation-utils)
8.  [Service Registry API (`Foundation.ServiceRegistry`)](#service-registry-api-foundation-serviceregistry)
9.  [Process Registry API (`Foundation.ProcessRegistry`)](#process-registry-api-foundation-processregistry)
10. [Infrastructure Protection API (`Foundation.Infrastructure`)](#infrastructure-protection-api-foundation-infrastructure)
11. [Error Context API (`Foundation.ErrorContext`)](#error-context-api-foundation-errorcontext)
12. [Error Handling & Types (`Foundation.Error`, `Foundation.Types.Error`)](#error-handling-types-foundation-error-foundation-types-error)
13. [Performance Considerations](#performance-considerations)
14. [Best Practices](#best-practices)
15. [Complete Examples](#complete-examples)
16. [Migration Guide](#migration-guide)
17. [Support and Resources](#support-and-resources)

## Overview

The Foundation Library provides core utilities, configuration management, event handling, telemetry, service registration, infrastructure protection patterns, and robust error handling for Elixir applications. It offers a clean, well-documented API designed for both ease of use and enterprise-grade performance.

### Key Features

- **🔧 Configuration Management** - Runtime configuration with validation and hot-reloading
- **📦 Event System** - Structured event creation, storage, and querying
- **📊 Telemetry Integration** - Comprehensive metrics collection and monitoring
- **🔗 Service & Process Registry** - Namespaced service discovery and management
- **🛡️ Infrastructure Protection** - Circuit breakers, rate limiters, connection pooling
- **✨ Error Context** - Enhanced error reporting with operational context
- **🛠️ Core Utilities** - Essential helper functions for common tasks
- **⚡ High Performance** - Optimized for low latency and high throughput
- **🧪 Test-Friendly** - Built-in support for isolated testing and namespacing

### System Requirements

- Elixir 1.15+ and OTP 26+
- Memory: Variable, base usage ~5MB + resources per service/event
- CPU: Optimized for multi-core systems

### Performance Characteristics

| Operation | Time Complexity | Typical Latency | Memory Usage |
|-----------|----------------|-----------------|--------------|
| Config Get | O(1) | < 1μs | Minimal |
| Config Update | O(1) + validation | < 100μs | Minimal |
| Event Creation | O(1) | < 10μs | ~200 bytes |
| Event Storage | O(1) | < 50μs | ~500 bytes |
| Event Query | O(log n) to O(n) | < 1ms | Variable |
| Service Lookup | O(1) | < 1μs | Minimal |
| Telemetry Emit | O(1) | < 5μs | ~100 bytes |
| Registry Operations | O(1) | < 1μs | ~100 bytes |

---

## Getting Started

### Installation

Add Foundation to your `mix.exs`:

```elixir
def deps do
  [
    {:foundation, "~> 0.1.0"} # Or the latest version
  ]
end
```

### Basic Setup (in your Application's `start/2` callback)

```elixir
def start(_type, _args) do
  # Start Foundation's supervision tree
  children = [
    Foundation.Application # Starts all Foundation services
  ]

  # Alternatively, if you need to initialize Foundation manually:
  # {:ok, _} = Foundation.initialize()

  # ... your application's children
  opts = [strategy: :one_for_one, name: MyApp.Supervisor]
  Supervisor.start_link(children, opts)
end
```

### Quick Example

```elixir
# Ensure Foundation is initialized (typically done by Foundation.Application)
# Foundation.initialize()

# Configure a setting  
:ok = Foundation.Config.update([:ai, :planning, :sampling_rate], 0.8)

# Create and store an event
correlation_id = Foundation.Utils.generate_correlation_id()
{:ok, event} = Foundation.Events.new_event(:user_action, %{action: "login"}, correlation_id: correlation_id)
{:ok, event_id} = Foundation.Events.store(event)

# Emit telemetry
:ok = Foundation.Telemetry.emit_counter([:myapp, :user, :login_attempts], %{user_id: 123})

# Use a utility
unique_op_id = Foundation.Utils.generate_id()

# Register a service
:ok = Foundation.ServiceRegistry.register(:production, :my_service, self())

# Use infrastructure protection
result = Foundation.Infrastructure.execute_protected(
  :external_api_call,
  [circuit_breaker: :api_fuse, rate_limiter: {:api_user_rate, "user_123"}],
  fn -> ExternalAPI.call() end
)
```

---

## Core Foundation API (`Foundation`)

The `Foundation` module is the main entry point for managing the Foundation layer itself.

### initialize/1

Initialize the entire Foundation layer. This typically ensures `Config`, `Events`, and `Telemetry` services are started. Often called by `Foundation.Application`.

```elixir
@spec initialize(opts :: keyword()) :: :ok | {:error, Error.t()}
```
**Parameters:**
- `opts` (optional) - Initialization options for each service (e.g., `config: [debug_mode: true]`).

**Example:**
```elixir
:ok = Foundation.initialize(config: [debug_mode: true])
# To initialize with defaults:
:ok = Foundation.initialize()
```

### status/0

Get comprehensive status of all core Foundation services (`Config`, `Events`, `Telemetry`).

```elixir
@spec status() :: {:ok, map()} | {:error, Error.t()}
```
**Returns:**
- `{:ok, status_map}` where `status_map` contains individual statuses.

**Example:**
```elixir
{:ok, status} = Foundation.status()
# status might be:
# %{
#   config: %{status: :running, uptime_ms: 3600000},
#   events: %{status: :running, event_count: 15000},
#   telemetry: %{status: :running, metrics_count: 50}
# }
```

### available?/0

Check if all core Foundation services (`Config`, `Events`, `Telemetry`) are available.

```elixir
@spec available?() :: boolean()
```
**Example:**
```elixir
if Foundation.available?() do
  IO.puts("Foundation layer is ready.")
end
```

### health/0

Get detailed health information for monitoring, including service status, Elixir/OTP versions.

```elixir
@spec health() :: {:ok, map()} | {:error, Error.t()}
```
**Returns:**
- `{:ok, health_map}` with keys like `:status` (`:healthy`, `:degraded`), `:timestamp`, `:services`, etc.

**Example:**
```elixir
{:ok, health_info} = Foundation.health()
IO.inspect(health_info.status) # :healthy
```

### version/0

Get the version string of the Foundation library.

```elixir
@spec version() :: String.t()
```
**Example:**
```elixir
version_string = Foundation.version()
# "0.1.0"
```

### shutdown/0

Gracefully shut down the Foundation layer and its services. This is typically managed by the application's supervision tree.

```elixir
@spec shutdown() :: :ok
```

---

## Configuration API (`Foundation.Config`)

The Configuration API provides centralized configuration management with runtime updates, validation, and subscriber notifications.

### initialize/0, initialize/1

Initialize the configuration service. Usually called by `Foundation.initialize/1`.

```elixir
@spec initialize() :: :ok | {:error, Error.t()}
@spec initialize(opts :: keyword()) :: :ok | {:error, Error.t()}
```

**Parameters:**
- `opts` (optional) - Configuration options

**Returns:**
- `:ok` on success
- `{:error, Error.t()}` on failure

**Example:**
```elixir
# Initialize with defaults
:ok = Foundation.Config.initialize()

# Initialize with custom options
:ok = Foundation.Config.initialize(cache_size: 1000)
```

### status/0

Get the status of the configuration service.

```elixir
@spec status() :: {:ok, map()} | {:error, Error.t()}
```

**Example:**
```elixir
{:ok, status} = Foundation.Config.status()
# Returns: {:ok, %{
#   status: :running,
#   uptime_ms: 3600000,
#   updates_count: 15,
#   subscribers_count: 3
# }}
```

### get/0, get/1

Retrieve the entire configuration or a specific value by path.

```elixir
@spec get() :: {:ok, Foundation.Types.Config.t()} | {:error, Error.t()}
@spec get(path :: [atom()]) :: {:ok, term()} | {:error, Error.t()}
```

**Parameters:**
- `path` (optional) - Configuration path as list of atoms

**Returns:**
- `{:ok, value}` - Configuration value
- `{:error, Error.t()}` - Error if path not found or service unavailable

**Examples:**
```elixir
# Get complete configuration
{:ok, config} = Foundation.Config.get()

# Get specific value
{:ok, provider} = Foundation.Config.get([:ai, :provider])
# Returns: {:ok, :mock}

# Get nested value
{:ok, timeout} = Foundation.Config.get([:interface, :query_timeout])
# Returns: {:ok, 10000}

# Handle missing path
{:error, error} = Foundation.Config.get([:nonexistent, :path])
# Returns: {:error, %Error{error_type: :config_path_not_found}}
```

### get_with_default/2

Retrieve a configuration value, returning a default if the path is not found.

```elixir
@spec get_with_default(path :: [atom()], default :: term()) :: term()
```

**Example:**
```elixir
timeout = Foundation.Config.get_with_default([:my_feature, :timeout_ms], 5000)
```

### update/2

Update a configuration value at runtime. Only affects paths listed by `updatable_paths/0`.

```elixir
@spec update(path :: [atom()], value :: term()) :: :ok | {:error, Error.t()}
```

**Parameters:**
- `path` - Configuration path (must be in updatable paths)
- `value` - New value

**Returns:**
- `:ok` on successful update
- `{:error, Error.t()}` on validation failure or forbidden path

**Examples:**
```elixir
# Update sampling rate
:ok = Foundation.Config.update([:ai, :planning, :sampling_rate], 0.8)

# Update debug mode
:ok = Foundation.Config.update([:dev, :debug_mode], true)

# Try to update forbidden path
{:error, error} = Foundation.Config.update([:ai, :api_key], "secret")
# Returns: {:error, %Error{error_type: :config_update_forbidden}}
```

### safe_update/2

Update configuration if the path is updatable and not forbidden, otherwise return an error.

```elixir
@spec safe_update(path :: [atom()], value :: term()) :: :ok | {:error, Error.t()}
```

### updatable_paths/0

Get a list of configuration paths that can be updated at runtime.

```elixir
@spec updatable_paths() :: [[atom(), ...], ...]
```

**Returns:**
- List of updatable configuration paths

**Example:**
```elixir
paths = Foundation.Config.updatable_paths()
# Returns: [
#   [:ai, :planning, :sampling_rate],
#   [:ai, :planning, :performance_target],
#   [:capture, :processing, :batch_size],
#   [:dev, :debug_mode],
#   ...
# ]
```

### subscribe/0, unsubscribe/0

Subscribe/unsubscribe the calling process to/from configuration change notifications.

```elixir
@spec subscribe() :: :ok | {:error, Error.t()}
@spec unsubscribe() :: :ok | {:error, Error.t()}
```

**Returns:**
- `:ok` on success
- `{:error, Error.t()}` on failure

Messages are received as `{:config_notification, {:config_updated, path, new_value}}`.

**Example:**
```elixir
# Subscribe to config changes
:ok = Foundation.Config.subscribe()

# You'll receive messages like:
# {:config_notification, {:config_updated, [:dev, :debug_mode], true}}

# Unsubscribe
:ok = Foundation.Config.unsubscribe()
```

### available?/0

Check if the configuration service is available.

```elixir
@spec available?() :: boolean()
```

**Example:**
```elixir
true = Foundation.Config.available?()
```

### reset/0

Reset configuration to its default values.

```elixir
@spec reset() :: :ok | {:error, Error.t()}
```

---

## Events API (`Foundation.Events`)

The Events API provides structured event creation, storage, querying, and serialization capabilities.

### initialize/0, status/0

Initialize/get status of the event store service.

```elixir
@spec initialize() :: :ok | {:error, Error.t()}
@spec status() :: {:ok, map()} | {:error, Error.t()}
```

**Examples:**
```elixir
# Initialize events system
:ok = Foundation.Events.initialize()

# Get status
{:ok, status} = Foundation.Events.status()
# Returns: {:ok, %{status: :running, event_count: 1500, next_id: 1501}}
```

### new_event/2, new_event/3

Create a new structured event. The 2-arity version uses default options. The 3-arity version accepts `opts` like `:correlation_id`, `:parent_id`.

```elixir
@spec new_event(event_type :: atom(), data :: term()) :: {:ok, Event.t()} | {:error, Error.t()}
@spec new_event(event_type :: atom(), data :: term(), opts :: keyword()) :: {:ok, Event.t()} | {:error, Error.t()}
```

**Parameters:**
- `event_type` - Event type atom
- `data` - Event data (any term)
- `opts` - Optional parameters (correlation_id, parent_id, etc.)

**Returns:**
- `{:ok, Event.t()}` - Created event
- `{:error, Error.t()}` - Validation error

**Examples:**
```elixir
# Simple event
{:ok, event} = Foundation.Events.new_event(:user_login, %{user_id: 123})

# Event with correlation ID
{:ok, event} = Foundation.Events.new_event(
  :payment_processed,
  %{amount: 100.0, currency: "USD"},
  correlation_id: "req-abc-123"
)

# Event with parent relationship
{:ok, parent_event} = Foundation.Events.new_event(
  :request_start,
  %{path: "/api/users"},
  correlation_id: "req-abc-123"
)
{:ok, child_event} = Foundation.Events.new_event(
  :validation_step,
  %{step: "auth"},
  correlation_id: "req-abc-123",
  parent_id: parent_event.event_id
)
```

### store/1, store_batch/1

Store events in the event store.

```elixir
@spec store(event :: Event.t()) :: {:ok, event_id :: Event.event_id()} | {:error, Error.t()}
@spec store_batch(events :: [Event.t()]) :: {:ok, [event_id :: Event.event_id()]} | {:error, Error.t()}
```

**Parameters:**
- `event` - Event to store
- `events` - List of events for batch storage

**Returns:**
- `{:ok, event_id}` or `{:ok, [event_ids]}` - Assigned event IDs
- `{:error, Error.t()}` - Storage error

**Examples:**
```elixir
# Store single event
{:ok, event} = Foundation.Events.new_event(:user_action, %{action: "click"})
{:ok, event_id} = Foundation.Events.store(event)

# Store multiple events atomically
{:ok, events} = create_multiple_events()
{:ok, event_ids} = Foundation.Events.store_batch(events)
```

### get/1

Retrieve a stored event by its ID.

```elixir
@spec get(event_id :: Event.event_id()) :: {:ok, Event.t()} | {:error, Error.t()}
```

**Example:**
```elixir
{:ok, event} = Foundation.Events.get(12345)
```

### query/1

Query stored events.

```elixir
@spec query(query_params :: map() | keyword()) :: {:ok, [Event.t()]} | {:error, Error.t()}
```

**Query Parameters (as map keys or keyword list):**
- `:event_type` - Filter by event type
- `:time_range` - `{start_time, end_time}` tuple
- `:limit` - Maximum number of results
- `:offset` - Number of results to skip
- `:order_by` - `:event_id` or `:timestamp`

**Examples:**
```elixir
# Query by event type
{:ok, events} = Foundation.Events.query(%{
  event_type: :user_login,
  limit: 100
})

# Query with time range
start_time = System.monotonic_time() - 3600_000_000_000  # 1 hour ago in nanoseconds
end_time = System.monotonic_time()
{:ok, events} = Foundation.Events.query(%{
  time_range: {start_time, end_time},
  limit: 500
})

# Query recent events
{:ok, recent_events} = Foundation.Events.query(%{
  limit: 50,
  order_by: :timestamp
})
```

### get_by_correlation/1

Retrieve all events matching a correlation ID, sorted by timestamp.

```elixir
@spec get_by_correlation(correlation_id :: String.t()) :: {:ok, [Event.t()]} | {:error, Error.t()}
```

**Example:**
```elixir
{:ok, related_events} = Foundation.Events.get_by_correlation("req-abc-123")
# Returns all events that share the correlation ID, sorted by timestamp
```

### Convenience Event Creators

#### function_entry/5
Creates a `:function_entry` event.

```elixir
@spec function_entry(module :: module(), function :: atom(), arity :: arity(), args :: [term()], opts :: keyword()) :: {:ok, Event.t()} | {:error, Error.t()}
```

#### function_exit/7
Creates a `:function_exit` event.

```elixir
@spec function_exit(module :: module(), function :: atom(), arity :: arity(), call_id :: Event.event_id(), result :: term(), duration_ns :: non_neg_integer(), exit_reason :: atom()) :: {:ok, Event.t()} | {:error, Error.t()}
```

#### state_change/5
Creates a `:state_change` event.

```elixir
@spec state_change(server_pid :: pid(), callback :: atom(), old_state :: term(), new_state :: term(), opts :: keyword()) :: {:ok, Event.t()} | {:error, Error.t()}
```

**Examples:**
```elixir
# Create function entry event
{:ok, entry_event} = Foundation.Events.function_entry(
  MyModule, :my_function, 2, [arg1, arg2]
)

# Create function exit event
{:ok, exit_event} = Foundation.Events.function_exit(
  MyModule, :my_function, 2, call_id, result, duration_ns, :normal
)

# Create state change event
{:ok, state_event} = Foundation.Events.state_change(
  server_pid, :handle_call, old_state, new_state
)
```

### Other Convenience Queries

#### get_correlation_chain/1
Retrieves events for a correlation ID, sorted.

```elixir
@spec get_correlation_chain(correlation_id :: String.t()) :: {:ok, [Event.t()]} | {:error, Error.t()}
```

#### get_time_range/2
Retrieves events in a monotonic time range.

```elixir
@spec get_time_range(start_time :: integer(), end_time :: integer()) :: {:ok, [Event.t()]} | {:error, Error.t()}
```

#### get_recent/1
Retrieves the most recent N events.

```elixir
@spec get_recent(limit :: non_neg_integer()) :: {:ok, [Event.t()]} | {:error, Error.t()}
```

**Examples:**
```elixir
# Get correlation chain
{:ok, chain} = Foundation.Events.get_correlation_chain("req-abc-123")

# Get events in time range
{:ok, events} = Foundation.Events.get_time_range(start_time, end_time)

# Get recent events
{:ok, recent} = Foundation.Events.get_recent(100)
```

### Serialization

#### serialize/1
Serializes an event to binary.

```elixir
@spec serialize(event :: Event.t()) :: {:ok, binary()} | {:error, Error.t()}
```

#### deserialize/1
Deserializes binary to an event.

```elixir
@spec deserialize(binary :: binary()) :: {:ok, Event.t()} | {:error, Error.t()}
```

#### serialized_size/1
Calculates the size of a serialized event.

```elixir
@spec serialized_size(event :: Event.t()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
```

**Examples:**
```elixir
# Serialize event to binary
{:ok, event} = Foundation.Events.new_event(:test, %{data: "example"})
{:ok, binary} = Foundation.Events.serialize(event)

# Deserialize binary to event
{:ok, restored_event} = Foundation.Events.deserialize(binary)

# Calculate serialized size
{:ok, size_bytes} = Foundation.Events.serialized_size(event)
```

### Storage Management

#### stats/0
Get storage statistics.

```elixir
@spec stats() :: {:ok, map()} | {:error, Error.t()}
```

#### prune_before/1
Prune events older than a monotonic timestamp.

```elixir
@spec prune_before(cutoff_timestamp :: integer()) :: {:ok, non_neg_integer()} | {:error, Error.t()}
```

**Examples:**
```elixir
# Get storage statistics
{:ok, stats} = Foundation.Events.stats()
# Returns: {:ok, %{
#   current_event_count: 15000,
#   events_stored: 50000,
#   events_pruned: 1000,
#   memory_usage_estimate: 15728640,
#   uptime_ms: 3600000
# }}

# Prune old events
cutoff_time = System.monotonic_time() - 86400_000_000_000  # 24 hours ago in nanoseconds
{:ok, pruned_count} = Foundation.Events.prune_before(cutoff_time)
```

### available?/0

Check if the event store service is available.

```elixir
@spec available?() :: boolean()
```

---

## Telemetry API (`Foundation.Telemetry`)

Provides metrics collection, event measurement, and monitoring integration.

### initialize/0, status/0

Initialize/get status of the telemetry service.

```elixir
@spec initialize() :: :ok | {:error, Error.t()}
@spec status() :: {:ok, map()} | {:error, Error.t()}
```

**Examples:**
```elixir
# Initialize telemetry system
:ok = Foundation.Telemetry.initialize()

# Get status
{:ok, status} = Foundation.Telemetry.status()
# Returns: {:ok, %{status: :running, metrics_count: 50, handlers_count: 5}}
```

### execute/3

Execute a telemetry event with measurements and metadata. This is the core emission function.

```elixir
@spec execute(event_name :: [atom()], measurements :: map(), metadata :: map()) :: :ok
```

**Parameters:**
- `event_name` - List of atoms defining the event name hierarchy
- `measurements` - Map of measurement values
- `metadata` - Map of additional context

**Example:**
```elixir
Foundation.Telemetry.execute(
  [:myapp, :request, :duration],
  %{value: 120, unit: :milliseconds},
  %{path: "/users", method: "GET", status: 200}
)
```

### measure/3

Measure the execution time of a function and emit a telemetry event.

```elixir
@spec measure(event_name :: [atom()], metadata :: map(), fun :: (-> result)) :: result when result: var
```

**Example:**
```elixir
result = Foundation.Telemetry.measure(
  [:myapp, :db_query],
  %{table: "users", operation: "select"},
  fn -> Repo.all(User) end
)
# Automatically emits timing telemetry for the function execution
```

### emit_counter/2

Emit a counter metric (increments by 1).

```elixir
@spec emit_counter(event_name :: [atom()], metadata :: map()) :: :ok
```

**Example:**
```elixir
:ok = Foundation.Telemetry.emit_counter(
  [:myapp, :user, :login_attempts],
  %{user_id: 123, ip: "192.168.1.1"}
)
```

### emit_gauge/3

Emit a gauge metric (absolute value).

```elixir
@spec emit_gauge(event_name :: [atom()], value :: number(), metadata :: map()) :: :ok
```

**Example:**
```elixir
:ok = Foundation.Telemetry.emit_gauge(
  [:myapp, :database, :connection_pool_size],
  25,
  %{pool: "main"}
)
```

### get_metrics/0

Retrieve all collected metrics.

```elixir
@spec get_metrics() :: {:ok, map()} | {:error, Error.t()}
```

**Example:**
```elixir
{:ok, metrics} = Foundation.Telemetry.get_metrics()
# Returns a map of all collected metrics with their values and metadata
```

### attach_handlers/1, detach_handlers/1

Attach/detach custom handlers for specific telemetry event names. Primarily for internal use or advanced scenarios.

```elixir
@spec attach_handlers(event_names :: [[atom()]]) :: :ok | {:error, Error.t()}
@spec detach_handlers(event_names :: [[atom()]]) :: :ok
```

**Example:**
```elixir
# Attach custom handlers
:ok = Foundation.Telemetry.attach_handlers([
  [:myapp, :request, :duration],
  [:myapp, :database, :query]
])

# Detach handlers
:ok = Foundation.Telemetry.detach_handlers([
  [:myapp, :request, :duration]
])
```

### Convenience Telemetry Emitters

#### time_function/3
Measures execution of `fun`, names event based on `module`/`function`.

```elixir
@spec time_function(module :: module(), function :: atom(), fun :: (-> result)) :: result when result: var
```

**Example:**
```elixir
result = Foundation.Telemetry.time_function(
  MyModule,
  :expensive_operation,
  fn -> MyModule.expensive_operation() end
)
# Emits timing under [:foundation, :function_timing, MyModule, :expensive_operation]
```

#### emit_performance/3
Emits a gauge under `[:foundation, :performance, metric_name]`.

```elixir
@spec emit_performance(metric_name :: atom(), value :: number(), metadata :: map()) :: :ok
```

**Example:**
```elixir
:ok = Foundation.Telemetry.emit_performance(
  :memory_usage,
  1024 * 1024 * 50,  # 50MB
  %{component: "event_store"}
)
```

#### emit_system_event/2
Emits a counter under `[:foundation, :system, event_type]`.

```elixir
@spec emit_system_event(event_type :: atom(), metadata :: map()) :: :ok
```

**Example:**
```elixir
:ok = Foundation.Telemetry.emit_system_event(
  :service_started,
  %{service: "config_server", pid: self()}
)
```

#### get_metrics_for/1
Retrieves metrics matching a specific prefix pattern.

```elixir
@spec get_metrics_for(event_pattern :: [atom()]) :: {:ok, map()} | {:error, Error.t()}
```

**Example:**
```elixir
{:ok, app_metrics} = Foundation.Telemetry.get_metrics_for([:myapp])
# Returns only metrics that start with [:myapp]
```

### available?/0

Check if the telemetry service is available.

```elixir
@spec available?() :: boolean()
```

---

## Utilities API (`Foundation.Utils`)

Provides general-purpose helper functions used within the Foundation layer and potentially useful for applications integrating with Foundation.

### generate_id/0

Generates a unique positive integer ID, typically for events or operations.

```elixir
@spec generate_id() :: pos_integer()
```

**Example:**
```elixir
unique_id = Foundation.Utils.generate_id()
# Returns: 123456789
```

### monotonic_timestamp/0

Returns the current monotonic time in nanoseconds. Suitable for duration calculations.

```elixir
@spec monotonic_timestamp() :: integer()
```

**Example:**
```elixir
start_time = Foundation.Utils.monotonic_timestamp()
# ... do work ...
end_time = Foundation.Utils.monotonic_timestamp()
duration_ns = end_time - start_time
```

### wall_timestamp/0

Returns the current system (wall clock) time in nanoseconds.

```elixir
@spec wall_timestamp() :: integer()
```

### generate_correlation_id/0

Generates a UUID v4 string, suitable for correlating events across operations or systems.

```elixir
@spec generate_correlation_id() :: String.t()
```

**Example:**
```elixir
correlation_id = Foundation.Utils.generate_correlation_id()
# Returns: "550e8400-e29b-41d4-a716-446655440000"
```

### truncate_if_large/1, truncate_if_large/2

Truncates a term if its serialized size exceeds a limit (default 10KB). Returns a map with truncation info if truncated.

```elixir
@spec truncate_if_large(term :: term()) :: term()
@spec truncate_if_large(term :: term(), max_size :: pos_integer()) :: term()
```

**Examples:**
```elixir
# Use default limit (10KB)
result = Foundation.Utils.truncate_if_large(large_data)

# Use custom limit
result = Foundation.Utils.truncate_if_large(large_data, 5000)
# If truncated, returns: %{truncated: true, original_size: 15000, truncated_size: 5000}
```

### safe_inspect/1

Inspects a term, limiting recursion and printable length to prevent overly long strings. Returns `<uninspectable>` on error.

```elixir
@spec safe_inspect(term :: term()) :: String.t()
```

**Example:**
```elixir
safe_string = Foundation.Utils.safe_inspect(complex_data)
# Safely converts any term to a readable string
```

### deep_merge/2

Recursively merges two maps.

```elixir
@spec deep_merge(left :: map(), right :: map()) :: map()
```

**Example:**
```elixir
merged = Foundation.Utils.deep_merge(
  %{a: %{b: 1, c: 2}},
  %{a: %{c: 3, d: 4}}
)
# Returns: %{a: %{b: 1, c: 3, d: 4}}
```

### format_duration/1

Formats a duration (in nanoseconds) into a human-readable string.

```elixir
@spec format_duration(nanoseconds :: non_neg_integer()) :: String.t()
```

**Example:**
```elixir
formatted = Foundation.Utils.format_duration(1_500_000_000)
# Returns: "1.5s"
```

### format_bytes/1

Formats a byte size into a human-readable string.

```elixir
@spec format_bytes(bytes :: non_neg_integer()) :: String.t()
```

**Example:**
```elixir
formatted = Foundation.Utils.format_bytes(1536)
# Returns: "1.5 KB"
```

### measure/1

Measures the execution time of a function.

```elixir
@spec measure(func :: (-> result)) :: {result, duration_microseconds :: non_neg_integer()} when result: any()
```

**Example:**
```elixir
{result, duration_us} = Foundation.Utils.measure(fn ->
  :timer.sleep(100)
  :completed
end)
# Returns: {:completed, 100000} (approximately)
```

### measure_memory/1

Measures memory consumption change due to a function's execution.

```elixir
@spec measure_memory(func :: (-> result)) :: {result, {before_bytes :: non_neg_integer(), after_bytes :: non_neg_integer(), diff_bytes :: integer()}} when result: any()
```

### system_stats/0

Returns a map of current system statistics (process count, memory, schedulers).

```elixir
@spec system_stats() :: map()
```

**Example:**
```elixir
stats = Foundation.Utils.system_stats()
# Returns: %{
#   process_count: 1234,
#   memory_total: 104857600,
#   memory_processes: 52428800,
#   schedulers_online: 8
# }
```

---

## Service Registry API (`Foundation.ServiceRegistry`)

High-level API for service registration and discovery, built upon `ProcessRegistry`.

### register/3

Registers a service PID under a specific name within a namespace.

```elixir
@spec register(namespace :: namespace(), service_name :: service_name(), pid :: pid()) :: :ok | {:error, {:already_registered, pid()}}
```

**Parameters:**
- `namespace` - `:production` or `{:test, reference()}`
- `service_name` - An atom like `:config_server`, `:event_store`
- `pid` - Process ID to register

**Example:**
```elixir
:ok = Foundation.ServiceRegistry.register(:production, :my_service, self())
```

### lookup/2

Looks up a registered service PID.

```elixir
@spec lookup(namespace :: namespace(), service_name :: service_name()) :: {:ok, pid()} | {:error, Error.t()}
```

**Example:**
```elixir
{:ok, pid} = Foundation.ServiceRegistry.lookup(:production, :my_service)
```

### unregister/2

Unregisters a service.

```elixir
@spec unregister(namespace :: namespace(), service_name :: service_name()) :: :ok
```

### list_services/1

Lists all service names registered in a namespace.

```elixir
@spec list_services(namespace :: namespace()) :: [service_name()]
```

**Example:**
```elixir
services = Foundation.ServiceRegistry.list_services(:production)
# Returns: [:config_server, :event_store, :telemetry_service]
```

### health_check/3

Checks if a service is registered, alive, and optionally passes a custom health check function.

```elixir
@spec health_check(namespace :: namespace(), service_name :: service_name(), opts :: keyword()) :: {:ok, pid()} | {:error, term()}
```

**Options:**
- `:health_check` - Custom health check function
- `:timeout` - Timeout in milliseconds

**Example:**
```elixir
{:ok, pid} = Foundation.ServiceRegistry.health_check(
  :production,
  :my_service,
  health_check: fn pid -> GenServer.call(pid, :health) end,
  timeout: 5000
)
```

### wait_for_service/3

Waits for a service to become available, up to a timeout.

```elixir
@spec wait_for_service(namespace :: namespace(), service_name :: service_name(), timeout_ms :: pos_integer()) :: {:ok, pid()} | {:error, :timeout}
```

### via_tuple/2

Generates a `{:via, Registry, ...}` tuple for GenServer registration with the underlying ProcessRegistry.

```elixir
@spec via_tuple(namespace :: namespace(), service_name :: service_name()) :: {:via, Registry, {module(), {namespace(), service_name()}}}
```

**Example:**
```elixir
via_tuple = Foundation.ServiceRegistry.via_tuple(:production, :my_service)
GenServer.start_link(MyService, [], name: via_tuple)
```

### get_service_info/1

Get detailed information about all services in a namespace.

```elixir
@spec get_service_info(namespace :: namespace()) :: map()
```

### cleanup_test_namespace/1

Specifically for testing: terminates and unregisters all services within a `{:test, ref}` namespace.

```elixir
@spec cleanup_test_namespace(test_ref :: reference()) :: :ok
```

---

## Process Registry API (`Foundation.ProcessRegistry`)

Lower-level, ETS-based process registry providing namespaced registration. Generally, `ServiceRegistry` is preferred for direct use.

### register/3

Registers a PID with a name in a namespace directly in the registry.

```elixir
@spec register(namespace :: namespace(), service_name :: service_name(), pid :: pid()) :: :ok | {:error, {:already_registered, pid()}}
```

### lookup/2

Looks up a PID directly from the registry.

```elixir
@spec lookup(namespace :: namespace(), service_name :: service_name()) :: {:ok, pid()} | :error
```

### via_tuple/2

Generates a `{:via, Registry, ...}` tuple for `GenServer.start_link` using this registry.

```elixir
@spec via_tuple(namespace :: namespace(), service_name :: service_name()) :: {:via, Registry, {module(), {namespace(), service_name()}}}
```

---

## Infrastructure Protection API (`Foundation.Infrastructure`)

Unified facade for applying protection patterns like circuit breakers, rate limiting, and connection pooling.

### initialize_all_infra_components/0

Initializes all underlying infrastructure components (Fuse for circuit breakers, Hammer for rate limiting). Typically called during application startup.

```elixir
@spec initialize_all_infra_components() :: {:ok, []} | {:error, term()}
```

### execute_protected/3

Executes a function with specified protection layers.

```elixir
@spec execute_protected(protection_key :: atom(), options :: keyword(), fun :: (-> term())) :: {:ok, term()} | {:error, term()}
```

**Options (examples):**
- `circuit_breaker: :my_api_breaker`
- `rate_limiter: {:api_calls_per_user, "user_id_123"}`
- `connection_pool: :http_client_pool` (if ConnectionManager is used for this)

**Example:**
```elixir
result = Foundation.Infrastructure.execute_protected(
  :external_api_call,
  [circuit_breaker: :api_fuse, rate_limiter: {:api_user_rate, "user_123"}],
  fn -> HTTPoison.get("https://api.example.com/data") end
)

case result do
  {:ok, response} -> handle_success(response)
  {:error, :circuit_open} -> handle_circuit_breaker()
  {:error, :rate_limited} -> handle_rate_limit()
  {:error, reason} -> handle_other_error(reason)
end
```

### configure_protection/2

Configures protection rules for a given key (e.g., circuit breaker thresholds, rate limits).

```elixir
@spec configure_protection(protection_key :: atom(), config :: map()) :: :ok | {:error, term()}
```

**Config Example:**
```elixir
:ok = Foundation.Infrastructure.configure_protection(
  :external_api_call,
  %{
    circuit_breaker: %{failure_threshold: 3, recovery_time: 15_000},
    rate_limiter: %{scale: 60_000, limit: 50}
  }
)
```

### get_protection_config/1

Retrieves the current protection configuration for a key.

```elixir
@spec get_protection_config(protection_key :: atom()) :: {:ok, map()} | {:error, :not_found | term()}
```

---

## Error Context API (`Foundation.ErrorContext`)

Provides a way to build up contextual information for operations, which can then be used to enrich errors.

### new/3

Creates a new error context for an operation.

```elixir
@spec new(module :: module(), function :: atom(), opts :: keyword()) :: ErrorContext.t()
```

**Options:** `:correlation_id`, `:metadata`, `:parent_context`.

**Example:**
```elixir
context = Foundation.ErrorContext.new(
  MyModule,
  :complex_operation,
  correlation_id: "req-123",
  metadata: %{user_id: 456}
)
```

### child_context/4

Creates a new error context that inherits from a parent context.

```elixir
@spec child_context(parent_context :: ErrorContext.t(), module :: module(), function :: atom(), metadata :: map()) :: ErrorContext.t()
```

### add_breadcrumb/4

Adds a breadcrumb (a step in an operation) to the context.

```elixir
@spec add_breadcrumb(context :: ErrorContext.t(), module :: module(), function :: atom(), metadata :: map()) :: ErrorContext.t()
```

### add_metadata/2

Adds or merges metadata into an existing context.

```elixir
@spec add_metadata(context :: ErrorContext.t(), new_metadata :: map()) :: ErrorContext.t()
```

### with_context/2

Executes a function, automatically capturing exceptions and enhancing them with the provided error context.

```elixir
@spec with_context(context :: ErrorContext.t(), fun :: (-> term())) :: term() | {:error, Error.t()}
```

**Example:**
```elixir
context = Foundation.ErrorContext.new(MyModule, :complex_op)
result = Foundation.ErrorContext.with_context(context, fn ->
  # ... operations that might fail ...
  context = Foundation.ErrorContext.add_breadcrumb(
    context, MyModule, :validation_step, %{step: 1}
  )
  
  if some_condition_fails do
    raise "Specific failure"
  end
  
  :ok
end)

case result do
  {:error, %Error{context: err_ctx}} -> 
    IO.inspect(err_ctx.operation_context) # Will include breadcrumbs, etc.
  result -> 
    # success
    result
end
```

### enhance_error/2

Adds the operational context from `ErrorContext.t()` to an existing `Error.t()`.

```elixir
@spec enhance_error(error :: Error.t(), context :: ErrorContext.t()) :: Error.t()
@spec enhance_error({:error, Error.t()}, context :: ErrorContext.t()) :: {:error, Error.t()}
@spec enhance_error({:error, term()}, context :: ErrorContext.t()) :: {:error, Error.t()}
```

---

## Error Handling & Types (`Foundation.Error`, `Foundation.Types.Error`)

The Foundation layer uses a structured error system for consistent error handling across all components.

### `Foundation.Types.Error` (Struct)

This is the data structure for all errors in the Foundation layer.

```elixir
%Foundation.Types.Error{
  code: pos_integer(),                # Hierarchical error code
  error_type: atom(),                 # Specific error identifier (e.g., :config_path_not_found)
  message: String.t(),
  severity: :low | :medium | :high | :critical,
  context: map() | nil,               # Additional error context
  correlation_id: String.t() | nil,
  timestamp: DateTime.t() | nil,
  stacktrace: list() | nil,           # Formatted stacktrace
  category: atom() | nil,             # E.g., :config, :system, :data
  subcategory: atom() | nil,          # E.g., :validation, :access
  retry_strategy: atom() | nil,       # E.g., :no_retry, :fixed_delay
  recovery_actions: [String.t()] | nil # Suggested actions
}
```

### Error Categories and Codes

| Category | Code Range | Examples |
|----------|------------|----------|
| System | 1000-1999 | Service unavailable, initialization failures |
| Configuration | 2000-2999 | Invalid paths, update failures |
| Data/Events | 3000-3999 | Event validation, storage errors |
| Network/External | 4000-4999 | API failures, timeouts |
| Security | 5000-5999 | Authentication, authorization |
| Validation | 6000-6999 | Input validation, type errors |

### `Foundation.Error` (Module)

Provides functions for working with `Types.Error` structs.

#### new/3

Creates a new `Error.t()` struct based on a predefined error type or a custom definition.

```elixir
@spec new(error_type :: atom(), message :: String.t() | nil, opts :: keyword()) :: Error.t()
```

**Options:** `:context`, `:correlation_id`, `:stacktrace`, etc. (to populate `Types.Error` fields).

**Example:**
```elixir
error = Foundation.Error.new(
  :config_path_not_found,
  "Configuration path [:ai, :provider] not found",
  context: %{path: [:ai, :provider]},
  correlation_id: "req-123"
)
```

#### error_result/3

Convenience function to create an `{:error, Error.t()}` tuple.

```elixir
@spec error_result(error_type :: atom(), message :: String.t() | nil, opts :: keyword()) :: {:error, Error.t()}
```

#### wrap_error/4

Wraps an existing error result (either `{:error, Error.t()}` or `{:error, reason}`) with a new `Error.t()`, preserving context.

```elixir
@spec wrap_error(result :: term(), error_type :: atom(), message :: String.t() | nil, opts :: keyword()) :: term()
```

**Example:**
```elixir
result = some_operation()
wrapped = Foundation.Error.wrap_error(
  result,
  :operation_failed,
  "Failed to complete operation",
  context: %{operation: "data_processing"}
)
```

#### to_string/1

Converts an `Error.t()` struct to a human-readable string.

```elixir
@spec to_string(error :: Error.t()) :: String.t()
```

#### is_retryable?/1

Checks if an error suggests a retry strategy.

```elixir
@spec is_retryable?(error :: Error.t()) :: boolean()
```

#### collect_error_metrics/1

Emits telemetry for an error. This is often called internally by error-aware functions.

```elixir
@spec collect_error_metrics(error :: Error.t()) :: :ok
```

---

## Performance Considerations

- Prefer `:ok` / `:error` tuples for return values in critical paths.
- Use `:telemetry` for high-frequency events; batch low-frequency events.
- Configure `:logger` for asynchronous logging in production.
- Use `:circuit_breaker` and `:rate_limiter` judiciously to protect resources.
- Monitor `:memory` and `:cpu` usage; optimize NIFs and ports as needed.
- Leverage `:poolboy` or similar for managing external connections.

## Best Practices

### Configuration Management Guidelines

**Configuration Structure:**
- Use nested configuration structures with clear namespaces
- Validate configuration at startup and runtime updates
- Implement configuration migrations for schema changes
- Use environment-specific configurations for development, staging, and production

```elixir
# Good: Well-structured configuration
config = %{
  parsing: %{
    batch_size: 1000,
    timeout_ms: 5000,
    retry_attempts: 3
  },
  storage: %{
    max_events: 100_000,
    retention_days: 30
  }
}

# Subscribe to configuration changes for dynamic updates
:ok = Foundation.Config.subscribe()
```

**Configuration Best Practices:**
- Always validate configuration values before applying them
- Use descriptive configuration keys and document their purpose
- Implement configuration rollback for critical settings
- Monitor configuration changes with telemetry events
- Use type specifications for configuration schemas

### Event System Guidelines

**Event Design Patterns:**
- Use consistent event types and structured data schemas
- Include correlation IDs for request tracking and debugging
- Implement event relationships for complex workflows
- Design events for both immediate processing and historical analysis

```elixir
# Good: Well-structured event
{:ok, event} = Foundation.Events.new_event(
  :user_authentication,
  %{
    user_id: 12345,
    authentication_method: "oauth2",
    ip_address: "192.168.1.100",
    user_agent: "Mozilla/5.0...",
    success: true
  },
  correlation_id: correlation_id,
  metadata: %{
    service: "auth_service",
    version: "1.2.3"
  }
)
```

**Event Storage and Querying:**
- Use appropriate query filters for performance
- Implement event pruning strategies for storage management
- Design event schemas that support future querying needs
- Use event relationships to track complex workflows

### Telemetry and Monitoring Guidelines

**Metrics Collection Strategy:**
- Emit telemetry for all critical operations and state changes
- Use appropriate metric types (counters, gauges, histograms)
- Include relevant metadata for filtering and aggregation
- Monitor both business and technical metrics

```elixir
# Business metrics
:ok = Foundation.Telemetry.emit_counter(
  [:myapp, :orders, :completed], 
  %{payment_method: "credit_card", amount_usd: 99.99}
)

# Technical metrics
:ok = Foundation.Telemetry.emit_gauge(
  [:myapp, :database, :connection_pool_size],
  pool_size,
  %{database: "primary", environment: "production"}
)
```

**Performance Monitoring:**
- Set up telemetry handlers for automatic metrics collection
- Monitor service health and availability continuously
- Track performance trends and set up regression detection
- Use distributed tracing for complex request flows

### Infrastructure Protection Patterns

**Circuit Breaker Usage:**
- Implement circuit breakers for external service calls
- Configure appropriate failure thresholds and timeouts
- Monitor circuit breaker state changes
- Design fallback strategies for when circuits are open

```elixir
# Protected external API call
result = Foundation.Infrastructure.execute_protected(
  :payment_api_call,
  [
    circuit_breaker: :payment_service_breaker,
    rate_limiter: {:payment_api_rate, user_id}
  ],
  fn -> PaymentAPI.process_payment(payment_data) end
)
```

**Rate Limiting Strategy:**
- Implement rate limiting for resource-intensive operations
- Use hierarchical rate limiting (global, per-user, per-IP)
- Monitor rate limit violations and adjust limits dynamically
- Provide meaningful error messages when limits are exceeded

### Testing Best Practices

**Test Structure and Organization:**
- Follow the testing pyramid: many unit tests, fewer integration tests
- Use descriptive test names that explain the scenario being tested
- Group related tests in `describe` blocks for better organization
- Isolate tests to avoid dependencies between test cases

**Property-Based Testing:**
- Use property-based testing for complex business logic
- Test invariants that should always hold true
- Generate realistic test data that covers edge cases
- Implement custom generators for domain-specific data types

```elixir
# Property-based test example
property "configuration roundtrip serialization" do
  check all config <- ConfigGenerator.valid_config() do
    serialized = :erlang.term_to_binary(config)
    deserialized = :erlang.binary_to_term(serialized)
    assert config == deserialized
  end
end
```

**Integration Testing:**
- Test service interactions and data flow between components
- Verify error propagation and recovery scenarios
- Test configuration changes and their effects on running services
- Validate telemetry events and metrics collection

**Performance Testing:**
- Establish performance baselines for regression detection
- Test with realistic data volumes and concurrent load
- Monitor resource usage (CPU, memory, I/O) during tests
- Implement automated performance regression detection

### Error Handling Strategies

**Structured Error Management:**
- Use the Foundation Error module for consistent error handling
- Attach operational context to errors for better debugging
- Implement error recovery strategies appropriate to the failure mode
- Log errors with sufficient context for troubleshooting

```elixir
# Good error handling with context
case Foundation.Error.try(
  fn -> ExternalService.risky_operation(data) end,
  log: true
) do
  {:ok, result} -> 
    process_result(result)
  {:error, error} ->
    # Add operational context
    enhanced_error = Foundation.ErrorContext.add_context(error, %{
      operation: "external_service_call",
      user_id: user_id,
      attempt_number: retry_count
    })
    handle_error(enhanced_error)
end
```

### Service Registry and Process Management

**Service Registration:**
- Use meaningful service names and appropriate namespaces
- Register services after they are fully initialized
- Implement health checks for registered services
- Clean up registrations during graceful shutdown

**Process Lifecycle Management:**
- Follow OTP principles for supervision and fault tolerance
- Implement graceful shutdown procedures for all services
- Use appropriate restart strategies for different failure modes
- Monitor process memory usage and implement cleanup procedures

### Security and Compliance

**Data Protection:**
- Validate all inputs at system boundaries
- Sanitize data before logging or storing events
- Implement appropriate access controls for sensitive operations
- Use secure defaults for all configuration settings

**Operational Security:**
- Monitor for suspicious patterns in telemetry data
- Implement rate limiting to prevent abuse
- Log security-relevant events for audit purposes
- Regularly review and rotate credentials

### Development and Maintenance

**Code Quality:**
- Use type specifications (`@spec`) for all public functions
- Follow Elixir naming conventions and style guidelines
- Document public APIs with comprehensive examples
- Implement comprehensive unit tests for all modules

**Dependency Management:**
- Keep dependencies up to date with security patches
- Use precise version specifications in `mix.exs`
- Monitor for deprecated functions and upgrade paths
- Test applications with updated dependencies before deployment

**Operational Excellence:**
- Implement comprehensive logging for troubleshooting
- Set up monitoring and alerting for critical metrics
- Document runbooks for common operational procedures
- Practice disaster recovery procedures regularly

## Complete Examples

### Example 1: Basic Configuration and Event Handling

```elixir
# Ensure Foundation is initialized
:ok = Foundation.initialize()

# Configure the application
:ok = Foundation.Config.update([:dev, :debug_mode], true)

# Create and store an event
correlation_id = Foundation.Utils.generate_correlation_id()
{:ok, event} = Foundation.Events.new_event(:user_action, %{action: "login"}, correlation_id: correlation_id)
{:ok, event_id} = Foundation.Events.store(event)

# Emit a telemetry metric
:ok = Foundation.Telemetry.emit_counter([:myapp, :user, :login_attempts], %{user_id: 123})

# Register a service
:ok = Foundation.ServiceRegistry.register(:production, :my_service, self())

# Use infrastructure protection to call an external API
result = Foundation.Infrastructure.execute_protected(
  :external_api_call,
  [circuit_breaker: :api_fuse, rate_limiter: {:api_user_rate, "user_123"}],
  fn -> ExternalAPI.call() end
)
```

### Example 2: Advanced Configuration with Subscribers

```elixir
# Ensure Foundation is initialized
:ok = Foundation.initialize()

# Subscribe to configuration changes
:ok = Foundation.Config.subscribe()

# Update a configuration value
:ok = Foundation.Config.update([:ai, :planning, :sampling_rate], 0.8)

# The subscriber process will receive a notification:
# {:config_notification, {:config_updated, [:ai, :planning, :sampling_rate], 0.8}}

# Unsubscribe from configuration changes
:ok = Foundation.Config.unsubscribe()
```

### Example 3: Error Handling with Context

```elixir
# Ensure Foundation is initialized
:ok = Foundation.initialize()

# Set the user context for error reporting
:ok = Foundation.ErrorContext.set_user_context(123)

# Try a risky operation
result = Foundation.Error.try(
  fn -> ExternalAPI.call() end,
  log: true
)

# Handle the result
case result do
  {:ok, data} ->
    # Process the data
  {:error, error} ->
    # Log and handle the error
    :ok = Foundation.ErrorContext.log_error(error)
end

# Clear the user context
:ok = Foundation.ErrorContext.clear_user_context()
```

---

## Migration Guide

### Using Foundation Library

Foundation is a standalone library that can be added to any Elixir application:

1. Add `{:foundation, "~> 0.1.0"}` to your `mix.exs` dependencies
2. Start `Foundation.Application` in your supervision tree
3. Use Foundation modules directly (e.g., `Foundation.Config`, `Foundation.Events`)

### Configuration Structure

The Foundation library uses a structured configuration with the following top-level sections:
- `:ai` - AI provider and analysis settings (for applications that use AI features)
- `:capture` - Event capture and buffering configuration
- `:storage` - Storage and retention policies for events and data
- `:interface` - Query and API interface settings
- `:dev` - Development and debugging options
- `:infrastructure` - Rate limiting, circuit breakers, and connection pooling

**Note:** Foundation provides a complete configuration structure that applications can use as needed. Not all sections are required - applications can use only the parts relevant to their use case.

### Service Architecture

Foundation provides three core services:
- `Foundation.Services.ConfigServer` - Configuration management
- `Foundation.Services.EventStore` - Event storage and querying
- `Foundation.Services.TelemetryService` - Metrics collection

These services are automatically started by `Foundation.Application` and can be accessed through the high-level APIs.

---

## Support and Resources

- **GitHub Repository**: [https://github.com/nshkrdotcom/foundation](https://github.com/nshkrdotcom/foundation)
- **Issue Tracker**: [https://github.com/nshkrdotcom/foundation/issues](https://github.com/nshkrdotcom/foundation/issues)
- **Documentation**: [https://hexdocs.pm/foundation](https://hexdocs.pm/foundation)
- **Local Documentation**: Run `mix docs` to generate local documentation