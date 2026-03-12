# Polling

`Foundation.Poller` runs a function repeatedly until it completes, fails, or
times out. It is designed for long-running workflows where you need to check
status periodically.

## Basic Polling

```elixir
alias Foundation.Poller
alias Foundation.Backoff

{:ok, result} = Poller.run(
  fn attempt ->
    case check_job_status(job_id) do
      {:ok, :completed, data} -> {:ok, data}
      {:ok, :pending}         -> {:retry, :pending}
      {:ok, :failed, reason}  -> {:error, reason}
    end
  end,
  backoff: Backoff.Policy.new(strategy: :exponential, base_ms: 500, max_ms: 10_000),
  timeout_ms: 60_000,
  max_attempts: 20
)
```

## Step Function Return Values

The step function controls polling flow through its return value:

| Return | Behavior |
|--------|----------|
| `{:ok, value}` | Polling stops, returns `{:ok, value}` |
| `{:error, reason}` | Polling stops, returns `{:error, reason}` |
| `{:retry, reason}` | Polls again after backoff delay |
| `{:retry, reason, delay_ms}` | Polls again after the given delay (overrides backoff) |
| `:retry` | Polls again after backoff delay |
| Any other value | Treated as `{:ok, value}` |

## Backoff Options

```elixir
# Backoff policy struct
Poller.run(step_fun, backoff: Backoff.Policy.new(strategy: :linear, base_ms: 1_000))

# Shorthand tuple
Poller.run(step_fun, backoff: {:exponential, 500, 10_000})

# Custom function (receives attempt number)
Poller.run(step_fun, backoff: fn attempt -> min(1_000 * attempt, 30_000) end)

# No backoff (immediate retries)
Poller.run(step_fun, backoff: :none)
```

## Timeout and Attempt Limits

```elixir
Poller.run(step_fun,
  timeout_ms: 120_000,     # stop after 2 minutes
  max_attempts: 50          # stop after 50 attempts
)
```

Both default to `:infinity` if not specified.

## Async Polling

Run polling in a `Task` for concurrent workflows:

```elixir
task = Poller.async(fn attempt ->
  case check_status(job_id) do
    :done -> {:ok, :completed}
    :pending -> :retry
  end
end, backoff: {:exponential, 1_000, 30_000}, timeout_ms: 300_000)

# Do other work...

{:ok, result} = Poller.await(task)
```

`Poller.await/2` converts task exits into error tuples, so it will not raise.

## Exception Handling

By default, exceptions are caught and returned as `{:error, exception}`.
You can provide a custom handler:

```elixir
Poller.run(step_fun,
  exception_handler: fn exception ->
    Logger.error("Polling failed: #{Exception.message(exception)}")
    {:error, exception}
  end
)
```
