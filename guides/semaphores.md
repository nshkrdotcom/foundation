# Semaphores

Foundation provides three semaphore types for controlling concurrent access
to shared resources.

## Counting Semaphore

`Foundation.Semaphore.Counting` is an ETS-backed semaphore that limits the
number of concurrent holders:

```elixir
alias Foundation.Semaphore.Counting

# Use the default registry
registry = Counting.default_registry()

# Execute with at most 10 concurrent holders
{:ok, result} = Counting.with_acquire(registry, :db_connections, 10, fn ->
  execute_query()
end)
# Returns {:error, :max} if the semaphore is full
```

### Manual Acquire/Release

```elixir
if Counting.acquire(registry, :db_connections, 10) do
  try do
    execute_query()
  after
    Counting.release(registry, :db_connections)
  end
else
  {:error, :too_many_connections}
end
```

### Blocking Acquire

Wait with backoff until a slot is available:

```elixir
alias Foundation.Backoff

backoff = Backoff.Policy.new(strategy: :exponential, base_ms: 2, max_ms: 50)

Counting.acquire_blocking(registry, :db_connections, 10, backoff)
# Returns :ok when acquired (blocks until available)
```

### Custom Registries

```elixir
registry = Counting.new_registry(name: :my_semaphores)
Counting.acquire(registry, :resource, 5)
```

## Weighted Semaphore

`Foundation.Semaphore.Weighted` limits by total weight rather than count.
This is useful for byte budgets or resources with variable costs:

```elixir
alias Foundation.Semaphore.Weighted

{:ok, sem} = Weighted.start_link(max_weight: 10_000_000)  # 10 MB budget

# Acquire weight proportional to payload size
Weighted.with_acquire(sem, byte_size(payload), fn ->
  upload_data(payload)
end)
```

The semaphore releases weight automatically when the function completes. An
acquire is allowed to drive the remaining budget negative; once that happens,
subsequent callers block until enough weight is released to bring the budget
back to zero or above.

## Limiter

`Foundation.Semaphore.Limiter` is a small convenience wrapper around
`Foundation.Semaphore.Counting` for quick concurrency limits:

```elixir
alias Foundation.Semaphore.Limiter

# Allow at most 5 concurrent executions
Limiter.with_semaphore(5, fn ->
  process_item()
end)
```

`Limiter` uses the default counting-semaphore registry plus a blocking
acquire loop with exponential backoff. It is suitable when you want a simple
API without managing registry names yourself.

## Choosing a Semaphore

| Type | Backing | Best For |
|------|---------|----------|
| `Counting` | ETS | Shared limits across processes, high throughput |
| `Weighted` | GenServer | Byte budgets, variable-cost resources |
| `Limiter` | ETS via `Counting` | Simple call-site level concurrency limits |
