# Dispatch

`Foundation.Dispatch` is a layered limiter that combines concurrency control,
throttling under backoff pressure, and byte budgets into a single
coordinated unit. It is designed for high-throughput API clients that need
to respect rate limits without complex orchestration.

## How It Works

Dispatch manages three layers:

1. **Concurrency semaphore** -- limits total in-flight requests (default: 400)
2. **Throttled semaphore** -- tighter limit activated during backoff (default: 10)
3. **Byte budget** -- weighted semaphore limiting total bytes in flight

When no backoff is active, only the concurrency semaphore and byte budget are
enforced. When backoff is triggered (e.g., after a 429 response), the
throttled semaphore kicks in and byte costs are multiplied by a penalty
factor.

## Setup

```elixir
alias Foundation.Dispatch
alias Foundation.RateLimit.BackoffWindow

# Create a shared rate limiter
limiter = BackoffWindow.for_key(:my_api)

# Start dispatch
{:ok, dispatch} = Dispatch.start_link(
  limiter: limiter,
  key: :my_api,
  concurrency: 100,
  throttled_concurrency: 5,
  byte_budget: 5_000_000
)
```

## Executing Requests

```elixir
body = Jason.encode!(payload)

result = Dispatch.with_rate_limit(dispatch, byte_size(body), fn ->
  HTTPClient.post(url, body)
end)
```

`with_rate_limit/3` acquires the concurrency semaphore, optionally the
throttled semaphore, and the byte budget before executing the function.
All are released automatically when the function completes.

## Signaling Backoff

When you receive a rate-limit response, signal backoff:

```elixir
case result do
  {:ok, %{status: 429, headers: headers}} ->
    retry_after = Foundation.Retry.HTTP.parse_retry_after(headers)
    Dispatch.set_backoff(dispatch, retry_after)

  _ ->
    :ok
end
```

This triggers the throttled concurrency limit and byte penalty multiplier
for subsequent requests.

## Options

| Option | Default | Description |
|--------|---------|-------------|
| `:limiter` | *required* | A `BackoffWindow` limiter reference |
| `:key` | `:default` | Namespace for semaphore names |
| `:concurrency` | 400 | Max in-flight requests (normal mode) |
| `:throttled_concurrency` | 10 | Max in-flight requests (backoff mode) |
| `:byte_budget` | 5 MB | Total bytes allowed in flight |
| `:backoff_window_ms` | 10,000 | How long backoff state is considered "recent" |
| `:byte_penalty_multiplier` | 20 | Byte cost multiplier during backoff |
| `:acquire_backoff` | exponential | Backoff policy for semaphore acquisition |
| `:sleep_fun` | `Process.sleep/1` | Custom sleep function (for testing) |

## Inspecting State

```elixir
snapshot = Dispatch.snapshot(dispatch)
snapshot.backoff_active?  # true if currently in backoff mode
```
