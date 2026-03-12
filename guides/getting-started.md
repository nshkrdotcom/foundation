# Getting Started

Foundation provides composable building blocks for resilient Elixir
applications. This guide walks you through installation and your first
retry loop.

## Installation

Add `foundation` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:foundation, "~> 0.2.1"}
  ]
end
```

Then fetch the dependency:

```bash
mix deps.get
```

> **Note:** Foundation 0.2+ is a complete rewrite and is not compatible with
> the 0.1.x series. If you are upgrading, see the
> [Migration Guide](migrating-from-01x.md).

## Your First Retry Loop

The simplest way to add retry logic is with `Foundation.Retry`:

```elixir
alias Foundation.{Backoff, Retry}

# 1. Define a backoff policy
backoff = Backoff.Policy.new(
  strategy: :exponential,
  base_ms: 100,
  max_ms: 5_000
)

# 2. Define a retry policy
policy = Retry.Policy.new(
  max_attempts: 5,
  backoff: backoff,
  retry_on: fn
    {:error, :timeout} -> true
    {:error, :rate_limited} -> true
    _ -> false
  end
)

# 3. Run your function with automatic retries
{result, _state} = Retry.run(fn -> call_api() end, policy)
```

That's it. Foundation handles the delay calculation, attempt counting, and
timeout enforcement.

## What's Next?

Foundation is organized around a small set of focused primitives:

| Primitive | Use Case |
|-----------|----------|
| [Backoff & Retry](backoff-and-retry.md) | Retry failed operations with configurable delay strategies |
| [HTTP Retry](http-retry.md) | Status-code classification and `Retry-After` parsing |
| [Polling](polling.md) | Wait for long-running workflows to complete |
| [Rate Limiting](rate-limiting.md) | Shared backoff windows for API rate limits |
| [Circuit Breakers](circuit-breakers.md) | Protect downstream services from cascading failures |
| [Semaphores](semaphores.md) | Limit concurrent access to shared resources |
| [Dispatch](dispatch.md) | Combine concurrency, throttling, and byte budgets |
| [Telemetry](telemetry.md) | Emit and measure events with optional reporters |

Each guide includes complete examples and configuration options.
