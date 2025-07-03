# Developer Guidelines - OTP Patterns Instead of Process Dictionary

## Overview

This guide provides patterns and best practices for Foundation/Jido developers to use proper OTP patterns instead of Process dictionary anti-patterns. Following these guidelines ensures our codebase remains maintainable, testable, and fault-tolerant.

## ❌ What NOT to Do

### Anti-Pattern: Process Dictionary for State

```elixir
# ❌ NEVER DO THIS
defmodule BadExample do
  def store_state(key, value) do
    Process.put(key, value)  # Anti-pattern!
  end
  
  def get_state(key) do
    Process.get(key)  # Anti-pattern!
  end
end
```

**Why it's bad**:
- State is hidden and hard to track
- Cannot be supervised or recovered on crash
- Makes testing difficult and flaky
- Breaks when process dies
- No type safety or validation

## ✅ What to Do Instead

### Pattern 1: GenServer for Stateful Components

When you need to maintain state across multiple operations:

```elixir
defmodule GoodExample.StateManager do
  use GenServer
  
  # Client API
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def store_value(key, value) do
    GenServer.call(__MODULE__, {:store, key, value})
  end
  
  def get_value(key) do
    GenServer.call(__MODULE__, {:get, key})
  end
  
  # Server callbacks
  def init(_opts) do
    {:ok, %{}}
  end
  
  def handle_call({:store, key, value}, _from, state) do
    new_state = Map.put(state, key, value)
    {:reply, :ok, new_state}
  end
  
  def handle_call({:get, key}, _from, state) do
    {:reply, Map.get(state, key), state}
  end
end
```

**Benefits**:
- Supervised and fault-tolerant
- Clear API and state ownership
- Easy to test
- Can add logging, metrics, validation

### Pattern 2: ETS for Shared State

When you need concurrent access to shared state:

```elixir
defmodule GoodExample.SharedRegistry do
  @table_name :shared_registry
  
  def init do
    :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
  end
  
  def register(key, value) do
    :ets.insert(@table_name, {key, value})
  end
  
  def lookup(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, value}] -> {:ok, value}
      [] -> {:error, :not_found}
    end
  end
  
  def delete(key) do
    :ets.delete(@table_name, key)
  end
end
```

**When to use ETS**:
- High-concurrency reads
- Simple key-value storage
- Performance-critical lookups
- Cache implementations

### Pattern 3: Explicit Parameter Passing

For temporary context that doesn't need persistence:

```elixir
# ❌ Don't use Process dictionary for context
defmodule BadContext do
  def with_user(user_id, fun) do
    Process.put(:current_user, user_id)
    result = fun.()
    Process.delete(:current_user)
    result
  end
  
  def get_current_user do
    Process.get(:current_user)
  end
end

# ✅ Pass context explicitly
defmodule GoodContext do
  def with_user(user_id, fun) when is_function(fun, 1) do
    context = %{user_id: user_id}
    fun.(context)
  end
  
  def process_request(context) do
    # Use context.user_id directly
    validate_user(context.user_id)
  end
end
```

### Pattern 4: Logger Metadata for Debug Context

For debugging and tracing context:

```elixir
# ✅ Use Logger metadata for debugging context
defmodule GoodExample.RequestHandler do
  require Logger
  
  def handle_request(request_id, payload) do
    # Set metadata for all subsequent log messages
    Logger.metadata(request_id: request_id, module: __MODULE__)
    
    Logger.info("Processing request", payload: payload)
    
    # Metadata automatically included in all logs
    result = process_payload(payload)
    
    Logger.info("Request completed", result: result)
    result
  end
end
```

## Common Scenarios and Solutions

### Scenario 1: Caching Computation Results

```elixir
# ❌ Process dictionary cache
def expensive_computation(input) do
  case Process.get({:cache, input}) do
    nil ->
      result = do_expensive_work(input)
      Process.put({:cache, input}, result)
      result
    cached ->
      cached
  end
end

# ✅ ETS-based cache with TTL
defmodule Cache do
  @table :computation_cache
  @ttl :timer.minutes(5)
  
  def get_or_compute(input, compute_fn) do
    case lookup(input) do
      {:ok, value} -> value
      :miss -> 
        value = compute_fn.(input)
        store(input, value)
        value
    end
  end
  
  defp lookup(key) do
    case :ets.lookup(@table, key) do
      [{^key, value, expiry}] ->
        if :os.system_time(:millisecond) < expiry do
          {:ok, value}
        else
          :ets.delete(@table, key)
          :miss
        end
      [] ->
        :miss
    end
  end
  
  defp store(key, value) do
    expiry = :os.system_time(:millisecond) + @ttl
    :ets.insert(@table, {key, value, expiry})
  end
end
```

### Scenario 2: Request-Scoped Data

```elixir
# ❌ Process dictionary for request data
def handle_request(conn) do
  Process.put(:current_request, conn)
  # ... somewhere deep in the call stack
  conn = Process.get(:current_request)
end

# ✅ Pass conn through the call stack
def handle_request(conn) do
  conn
  |> authenticate_user()
  |> authorize_action()
  |> execute_action()
  |> render_response()
end

# OR use a context struct
defmodule RequestContext do
  defstruct [:conn, :user, :permissions, :metadata]
  
  def handle_request(conn) do
    context = %RequestContext{conn: conn}
    
    context
    |> authenticate_user()
    |> authorize_action()
    |> execute_action()
    |> render_response()
  end
end
```

### Scenario 3: Telemetry and Metrics

```elixir
# ❌ Process dictionary for metrics
def track_event(event) do
  events = Process.get(:events, [])
  Process.put(:events, [event | events])
end

# ✅ Use telemetry library
def track_event(event_name, measurements, metadata) do
  :telemetry.execute(
    [:myapp, event_name],
    measurements,
    metadata
  )
end

# With batching via GenServer
defmodule MetricsCollector do
  use GenServer
  
  def track_event(event) do
    GenServer.cast(__MODULE__, {:track, event})
  end
  
  def handle_cast({:track, event}, state) do
    new_state = buffer_event(state, event)
    
    if should_flush?(new_state) do
      flush_events(new_state.buffer)
      {:noreply, %{state | buffer: []}}
    else
      {:noreply, new_state}
    end
  end
end
```

## Testing Patterns

### Testing Async Operations

```elixir
# ❌ Process dictionary for test coordination
test "async operation" do
  Process.put(:callback_called, false)
  
  callback = fn ->
    Process.put(:callback_called, true)
  end
  
  trigger_async_operation(callback)
  :timer.sleep(100)
  assert Process.get(:callback_called)
end

# ✅ Use message passing
test "async operation" do
  parent = self()
  
  callback = fn ->
    send(parent, :callback_called)
  end
  
  trigger_async_operation(callback)
  assert_receive :callback_called, 1_000
end

# ✅ Or use test helpers
test "async operation" do
  {:ok, agent} = Agent.start_link(fn -> false end)
  
  callback = fn ->
    Agent.update(agent, fn _ -> true end)
  end
  
  trigger_async_operation(callback)
  
  assert eventually(fn ->
    Agent.get(agent, & &1) == true
  end)
end
```

## Code Review Checklist

When reviewing code, check for these anti-patterns:

- [ ] No `Process.put/2` or `Process.get/1-2` calls
- [ ] State is managed by supervised processes
- [ ] Context is passed explicitly through function parameters
- [ ] Async operations use message passing for coordination
- [ ] Shared state uses ETS or GenServer, not Process dictionary
- [ ] Debug context uses Logger metadata
- [ ] Tests don't rely on Process dictionary for coordination

## Migration Guide

If you encounter Process dictionary usage in existing code:

1. **Identify the pattern**: What is the Process dictionary being used for?
   - State storage → Use GenServer
   - Caching → Use ETS
   - Context propagation → Pass explicitly
   - Debug info → Use Logger metadata

2. **Check feature flags**: Is there a migration flag?
   ```elixir
   Foundation.FeatureFlags.enabled?(:use_ets_agent_registry)
   ```

3. **Use the safe abstraction**:
   ```elixir
   # Instead of direct Process dictionary access
   Foundation.Protocols.RegistryAny.register_agent(id, pid)
   ```

4. **Test both code paths**: Ensure tests cover both legacy and new implementations

## Performance Considerations

### GenServer vs ETS

**Use GenServer when**:
- State changes need to be serialized
- You need complex state transformations
- State needs to be supervised
- You want built-in backpressure

**Use ETS when**:
- High concurrent reads are needed
- Simple key-value storage suffices
- Performance is critical
- Data can be reconstructed if lost

### Benchmarking Example

```elixir
defmodule BenchmarkExample do
  def benchmark_implementations do
    Benchee.run(%{
      "process_dict" => fn input ->
        Process.put(:key, input)
        Process.get(:key)
      end,
      "ets" => fn input ->
        :ets.insert(:bench_table, {:key, input})
        :ets.lookup(:bench_table, :key)
      end,
      "genserver" => fn input ->
        GenServer.call(BenchServer, {:store_and_get, :key, input})
      end
    })
  end
end
```

## Common Pitfalls to Avoid

1. **Don't create ETS tables in tests without cleanup**
   ```elixir
   # ❌ Bad - leaks ETS tables
   test "something" do
     :ets.new(:test_table, [:set])
     # ...
   end
   
   # ✅ Good - proper cleanup
   test "something" do
     table = :ets.new(:test_table, [:set])
     try do
       # ... test code
     after
       :ets.delete(table)
     end
   end
   ```

2. **Don't assume Process dictionary survives process boundaries**
   ```elixir
   # ❌ This won't work
   Task.async(fn ->
     Process.get(:some_key)  # Will be nil!
   end)
   
   # ✅ Pass data explicitly
   value = get_value()
   Task.async(fn ->
     use_value(value)
   end)
   ```

3. **Don't use atoms for dynamic ETS keys**
   ```elixir
   # ❌ Can exhaust atom table
   :ets.insert(:table, {String.to_atom(user_input), value})
   
   # ✅ Use strings or other data types
   :ets.insert(:table, {user_input, value})
   ```

## Resources and Further Reading

- [GenServer Documentation](https://hexdocs.pm/elixir/GenServer.html)
- [ETS Documentation](https://erlang.org/doc/man/ets.html)
- [Logger Metadata Guide](https://hexdocs.pm/logger/Logger.html#module-metadata)
- [OTP Design Principles](https://erlang.org/doc/design_principles/des_princ.html)
- [Foundation OTP Cleanup Plan](../JULY_1_2025_OTP_CLEANUP_2121.md)

## Getting Help

- **Questions**: Ask in #platform-team Slack channel
- **Code Review**: Tag @platform-team for OTP pattern review
- **Examples**: See `test/examples/otp_patterns/` for working examples
- **Migration Help**: Check `Foundation.OTPCleanup` module documentation

Remember: **When in doubt, pass it explicitly!** Explicit parameter passing is always safer than hidden state.