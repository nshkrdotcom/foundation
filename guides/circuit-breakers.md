# Circuit Breakers

`Foundation.CircuitBreaker` protects downstream services from cascading
failures. When a service starts failing, the circuit opens and rejects calls
immediately, giving the service time to recover.

## States

A circuit breaker has three states:

| State | Behavior |
|-------|----------|
| **Closed** | Requests pass through. Failures are counted. |
| **Open** | Requests are rejected immediately with `{:error, :circuit_open}`. |
| **Half-Open** | A limited number of probe requests are allowed to test recovery. |

The circuit opens when failures reach `failure_threshold`. After
`reset_timeout_ms`, it transitions to half-open. A success in half-open
closes the circuit; a failure re-opens it. Ignored outcomes leave breaker
health unchanged and release any half-open probe capacity.

## Functional API

The functional API is stateless -- you manage the circuit breaker struct
yourself:

```elixir
alias Foundation.CircuitBreaker

cb = CircuitBreaker.new("payment_service",
  failure_threshold: 3,
  reset_timeout_ms: 30_000,
  half_open_max_calls: 1
)

# Execute through the circuit breaker
{result, cb} = CircuitBreaker.call(cb, fn ->
  PaymentService.charge(amount)
end)
```

`call/3` returns `{result, updated_cb}` where `result` is either the
function's return value or `{:error, :circuit_open}`.

### Custom Success Detection

By default, `{:ok, _}` is considered a success. You can customize this:

```elixir
{result, cb} = CircuitBreaker.call(cb, fn ->
  HTTPClient.post(url, body)
end, success?: fn
  {:ok, %{status: status}} when status in 200..299 -> true
  _ -> false
end)
```

The callback may return:

- `true` or `:success` to record success
- `false` or `:failure` to record failure
- `:ignore` to skip breaker accounting for that outcome

`:ignore` is useful when an HTTP client wants `429` to drive shared backoff
without counting it as a downstream health failure.

### Manual State Management

```elixir
# Check if the circuit allows requests
CircuitBreaker.allow_request?(cb)  # true when closed or half-open with capacity

# Get the current state
CircuitBreaker.state(cb)  # :closed | :open | :half_open

# Record outcomes manually
cb = CircuitBreaker.record_success(cb)
cb = CircuitBreaker.record_failure(cb)
cb = CircuitBreaker.record_ignored(cb)

# Force reset
cb = CircuitBreaker.reset(cb)
```

## Registry API

For shared circuit breakers across processes, use
`Foundation.CircuitBreaker.Registry`:

```elixir
alias Foundation.CircuitBreaker.Registry

# Create a registry (ETS-backed)
registry = Registry.new_registry(name: MyApp.CircuitBreakers)

# Execute through a named circuit breaker
result = Registry.call(registry, "payment_service", fn ->
  PaymentService.charge(amount)
end)
```

The registry automatically creates circuit breakers on first use and shares
state across all callers. Half-open probes are serialized with CAS updates
to prevent multiple processes from probing simultaneously.

### Breaker Creation Options

```elixir
registry = Registry.new_registry(name: MyApp.CircuitBreakers)

result =
  Registry.call(registry, "payment_service", fn ->
    PaymentService.charge(amount)
  end,
    failure_threshold: 5,
    reset_timeout_ms: 60_000,
    half_open_max_calls: 2
  )
```

`new_registry/1` only creates the ETS table. Circuit-breaker options are
applied when a named breaker is first created via `call/4`, and later calls
reuse the existing breaker state for that name.
