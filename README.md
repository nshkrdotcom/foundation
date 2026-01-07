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

## Features

- **Backoff** - Exponential, linear, and constant strategies with jitter
- **Retry** - Configurable retry loops with timeout and progress tracking
- **Polling** - Long-running workflow polling with backoff and cancellation
- **Rate Limiting** - Shared backoff windows for API rate limits
- **Circuit Breaker** - Protect downstream services with automatic recovery
- **Semaphores** - Counting and weighted semaphores for concurrency control
- **Dispatch** - Layered limiter combining concurrency, throttling, and byte budgets
- **Telemetry** - Lightweight helpers with optional reporter integration

## Requirements

- Elixir 1.15+
- OTP 26+

## Installation

Add `foundation` to your dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:foundation, "~> 0.2"}
  ]
end
```

## Usage

### Backoff and Retry

```elixir
alias Foundation.Backoff
alias Foundation.Retry

# Create a backoff policy
backoff = Backoff.Policy.new(
  strategy: :exponential,
  base_ms: 100,
  max_ms: 5_000,
  jitter_strategy: :factor,
  jitter: 0.1
)

# Create a retry policy
policy = Retry.Policy.new(
  max_attempts: 5,
  backoff: backoff,
  retry_on: fn
    {:error, :timeout} -> true
    {:error, :rate_limited} -> true
    _ -> false
  end
)

# Run with retry
{result, _state} = Retry.run(fn -> fetch_data() end, policy)
```

### Retry Runner with Telemetry

```elixir
alias Foundation.Retry.{Config, Handler, Runner}

config = Config.new(max_retries: 3, base_delay_ms: 100)
handler = Handler.from_config(config)

{:ok, result} = Runner.run(
  fn -> call_api() end,
  handler: handler,
  telemetry_events: %{
    start: [:my_app, :api, :start],
    stop: [:my_app, :api, :stop],
    retry: [:my_app, :api, :retry]
  }
)
```

### HTTP Retry Helpers

```elixir
alias Foundation.Retry.HTTP

HTTP.retryable_status?(429)  # true
HTTP.retryable_status?(500)  # true
HTTP.retryable_status?(400)  # false

# Parse Retry-After header
HTTP.parse_retry_after("120")  # {:ok, 120}
HTTP.parse_retry_after("Wed, 08 Jan 2026 12:00:00 GMT")  # {:ok, seconds_until}
```

### Polling

```elixir
alias Foundation.Poller
alias Foundation.Backoff

{:ok, result} = Poller.run(
  fn attempt ->
    case check_job_status(job_id) do
      {:ok, :completed, data} -> {:ok, data}
      {:ok, :pending} -> {:retry, :pending}
      {:ok, :failed, reason} -> {:error, reason}
    end
  end,
  backoff: Backoff.Policy.new(strategy: :exponential, base_ms: 500, max_ms: 10_000),
  timeout_ms: 60_000,
  max_attempts: 20
)
```

### Rate Limit Backoff Windows

```elixir
alias Foundation.RateLimit.BackoffWindow

# Get or create a limiter for a key
limiter = BackoffWindow.for_key(:openai_api)

# Set backoff after receiving 429
BackoffWindow.set(limiter, 30_000)

# Wait for backoff to clear before next request
BackoffWindow.wait(limiter)
```

### Circuit Breaker

```elixir
alias Foundation.CircuitBreaker

# Functional API (stateless)
cb = CircuitBreaker.new("payment_service", failure_threshold: 3, reset_timeout_ms: 30_000)

{result, cb} = CircuitBreaker.call(cb, fn ->
  PaymentService.charge(amount)
end)

# Registry API (stateful, for shared circuit breakers)
alias Foundation.CircuitBreaker.Registry

{:ok, _pid} = Registry.start_link(name: MyApp.CircuitBreakers)

result = Registry.call(MyApp.CircuitBreakers, "payment_service", fn ->
  PaymentService.charge(amount)
end)
```

### Semaphores

```elixir
# Counting semaphore (limit concurrent operations)
alias Foundation.Semaphore.Counting

registry = Counting.default_registry()

{:ok, result} = Counting.with_acquire(registry, :db_connections, 10, fn ->
  execute_query()
end)

# Weighted semaphore (byte budgets)
alias Foundation.Semaphore.Weighted

{:ok, sem} = Weighted.start_link(max_weight: 10_000_000)

Weighted.with_acquire(sem, byte_size(payload), fn ->
  upload_data(payload)
end)

# Simple limiter
alias Foundation.Semaphore.Limiter

Limiter.with_semaphore(5, fn ->
  process_item()
end)
```

### Layered Dispatch

```elixir
alias Foundation.Dispatch
alias Foundation.RateLimit.BackoffWindow

# Create a rate limiter
limiter = BackoffWindow.for_key(:api_dispatch)

# Start dispatch with concurrency, throttling, and byte limits
{:ok, dispatch} = Dispatch.start_link(
  limiter: limiter,
  key: :api,
  concurrency: 100,
  throttled_concurrency: 5,
  byte_budget: 5_000_000
)

# Execute with rate limiting
result = Dispatch.with_rate_limit(dispatch, byte_size(request), fn ->
  send_request(request)
end)

# Signal backoff (e.g., after 429 response)
Dispatch.set_backoff(dispatch, 30_000)
```

### Telemetry

```elixir
alias Foundation.Telemetry

# Emit events
Telemetry.execute([:my_app, :request, :complete], %{count: 1}, %{status: 200})

# Measure function duration
{:ok, result} = Telemetry.measure([:my_app, :db, :query], %{table: :users}, fn ->
  Repo.all(User)
end)

# Optional: Start a reporter (requires telemetry_reporter dependency)
{:ok, _pid} = Telemetry.start_reporter(name: :my_reporter, transport: MyTransport)

{:ok, handler_id} = Telemetry.attach_reporter(
  reporter: :my_reporter,
  events: [[:my_app, :request, :complete]]
)
```

## Documentation

Full documentation is available at [HexDocs](https://hexdocs.pm/foundation).

## License

Foundation is released under the MIT License. See [LICENSE](LICENSE) for details.
