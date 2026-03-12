# Foundation

<p align="center">
  <img src="assets/foundation.svg" alt="Foundation logo" width="200" height="200">
</p>

<p align="center">
  <strong>Lightweight resilience primitives for Elixir</strong>
</p>

<p align="center">
  <a href="https://hex.pm/packages/foundation"><img src="https://img.shields.io/hexpm/v/foundation.svg" alt="Hex version"></a>
  <a href="https://hexdocs.pm/foundation"><img src="https://img.shields.io/badge/hex-docs-blue.svg" alt="Hex Docs"></a>
  <a href="https://github.com/nshkrdotcom/foundation/blob/main/LICENSE"><img src="https://img.shields.io/hexpm/l/foundation.svg" alt="License"></a>
</p>

---

Foundation provides composable building blocks for resilient Elixir applications:
backoff policies, retry loops, rate-limit windows, circuit breakers, semaphores,
and telemetry helpers.

## Installation

Add `foundation` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:foundation, "~> 0.2.1"}
  ]
end
```

> Foundation 0.2+ is a complete rewrite and is not compatible with the 0.1.x
> series. See the [Migration Guide](guides/migrating-from-01x.md) for details.

## Quick Start

```elixir
alias Foundation.{Backoff, Retry}

# Define backoff and retry policies
backoff = Backoff.Policy.new(strategy: :exponential, base_ms: 100, max_ms: 5_000)

policy = Retry.Policy.new(
  max_attempts: 5,
  backoff: backoff,
  retry_on: fn
    {:error, :timeout} -> true
    {:error, :rate_limited} -> true
    _ -> false
  end
)

# Run with automatic retries
{result, _state} = Retry.run(fn -> call_api() end, policy)
```

See the [Getting Started](guides/getting-started.md) guide for a full walkthrough.

## Features

| Feature | Module | Guide |
|---------|--------|-------|
| **Backoff** -- Exponential, linear, and constant strategies with jitter | `Foundation.Backoff` | [Backoff & Retry](guides/backoff-and-retry.md) |
| **Retry** -- Configurable retry loops with timeout and progress tracking | `Foundation.Retry` | [Backoff & Retry](guides/backoff-and-retry.md) |
| **HTTP Retry** -- Status classification and `Retry-After` parsing | `Foundation.Retry.HTTP` | [HTTP Retry](guides/http-retry.md) |
| **Polling** -- Long-running workflow polling with backoff and cancellation | `Foundation.Poller` | [Polling](guides/polling.md) |
| **Rate Limiting** -- Shared backoff windows for API rate limits | `Foundation.RateLimit.BackoffWindow` | [Rate Limiting](guides/rate-limiting.md) |
| **Circuit Breaker** -- Protect downstream services with automatic recovery | `Foundation.CircuitBreaker` | [Circuit Breakers](guides/circuit-breakers.md) |
| **Semaphores** -- Counting and weighted semaphores for concurrency control | `Foundation.Semaphore.*` | [Semaphores](guides/semaphores.md) |
| **Dispatch** -- Layered limiter combining concurrency, throttling, and byte budgets | `Foundation.Dispatch` | [Dispatch](guides/dispatch.md) |
| **Telemetry** -- Lightweight helpers with optional reporter integration | `Foundation.Telemetry` | [Telemetry](guides/telemetry.md) |

## Requirements

- Elixir 1.15+
- OTP 26+

## Documentation

Full documentation is available at [HexDocs](https://hexdocs.pm/foundation).

## License

Foundation is released under the MIT License. See [LICENSE](LICENSE) for details.
