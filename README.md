# Foundation

<p align="center">
  <img src="assets/foundation.svg" alt="Foundation logo" width="240" height="240">
</p>

**Lightweight resilience primitives for backoff, retry, rate-limit windows, circuit breakers,
semaphores, and optional telemetry helpers.**

Version: 0.2.0

[![CI](https://github.com/nshkrdotcom/foundation/actions/workflows/elixir.yaml/badge.svg)](https://github.com/nshkrdotcom/foundation/actions/workflows/elixir.yaml)
[![Elixir](https://img.shields.io/badge/elixir-1.18.3-purple.svg)](https://elixir-lang.org)
[![OTP](https://img.shields.io/badge/otp-27.3.3-blue.svg)](https://www.erlang.org)
[![Hex version badge](https://img.shields.io/hexpm/v/foundation.svg)](https://hex.pm/packages/foundation)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## Scope
- Backoff policies and retry loops with deterministic testing hooks.
- Generic retry runner and polling helper for long-running workflows.
- HTTP retry helpers (status classification, Retry-After parsing, delay calculation).
- Shared backoff windows for rate-limited APIs.
- Circuit breakers with optional registries.
- Counting and weighted semaphores for concurrency and byte budgets.
- Layered dispatch limiter for concurrency + byte budgets under backoff pressure.
- Optional telemetry helpers with `telemetry_reporter` integration.

## Install
```elixir
def deps do
  [
    {:foundation, "~> 0.2"},
    {:telemetry_reporter, "~> 0.1", optional: true}
  ]
end
```

## Usage
Backoff and retry:
```elixir
alias Foundation.Backoff
alias Foundation.Retry
alias Foundation.Retry.{Config, Handler, HTTP, Runner}
alias Foundation.Poller

backoff = Backoff.Policy.new(strategy: :exponential, base_ms: 200, max_ms: 5_000)
policy =
  Retry.Policy.new(
    max_attempts: 3,
    backoff: backoff,
    retry_on: fn result -> match?({:error, _}, result) end
  )

{result, _state} = Retry.run(fn -> {:ok, :done} end, policy)

config = Config.new(max_retries: 5)
handler = Handler.from_config(config)
delay_ms = Handler.next_delay(handler)
{:ok, :done} = Runner.run(fn -> {:ok, :done} end, handler: handler)

HTTP.retryable_status?(429)
HTTP.retry_delay(0)

{:ok, :done} =
  Poller.run(fn attempt ->
    if attempt < 2, do: {:retry, :pending}, else: {:ok, :done}
  end,
    backoff: Backoff.Policy.new(strategy: :constant, base_ms: 50, max_ms: 50)
  )
```

Rate-limit backoff windows:
```elixir
alias Foundation.RateLimit.BackoffWindow

limiter = BackoffWindow.for_key(:api_key)
BackoffWindow.set(limiter, 1_000)
BackoffWindow.wait(limiter)
```

Circuit breaker (in-memory or registry):
```elixir
alias Foundation.CircuitBreaker
alias Foundation.CircuitBreaker.Registry

cb = CircuitBreaker.new("api", failure_threshold: 3)
{result, cb} = CircuitBreaker.call(cb, fn -> {:ok, :ok} end)

Registry.call("api", fn -> {:ok, :ok} end)
```

Semaphores:
```elixir
alias Foundation.Semaphore.Counting
alias Foundation.Semaphore.Limiter
alias Foundation.Semaphore.Weighted

registry = Counting.default_registry()
Counting.with_acquire(registry, :requests, 5, fn -> :ok end)

{:ok, sem} = Weighted.start_link(max_weight: 1_000)
Weighted.with_acquire(sem, 250, fn -> :ok end)

Limiter.with_semaphore(10, fn -> :ok end)
```

Telemetry helpers:
```elixir
Foundation.Telemetry.execute([:app, :event], %{count: 1}, %{tag: :ok})

Foundation.Telemetry.measure([:app, :work], %{op: :fetch}, fn ->
  :ok
end)

{:ok, _pid} =
  Foundation.Telemetry.start_reporter(
    name: :reporter,
    transport: MyTransport
  )

{:ok, handler_id} =
  Foundation.Telemetry.attach_reporter(
    reporter: :reporter,
    events: [[:app, :event]]
  )

Foundation.Telemetry.detach_reporter(handler_id)
```

Layered dispatch limiter:
```elixir
alias Foundation.Dispatch
alias Foundation.RateLimit.BackoffWindow

limiter = BackoffWindow.for_key(:dispatch)
{:ok, dispatch} = Dispatch.start_link(limiter: limiter, key: :dispatch)

Dispatch.with_rate_limit(dispatch, 1_024, fn ->
  :ok
end)
```
