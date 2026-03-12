# Rate Limiting

`Foundation.RateLimit.BackoffWindow` provides shared backoff windows for
rate-limited APIs. When an API returns a rate-limit signal (e.g., HTTP 429),
you set a backoff window. All callers sharing that limiter will wait until
the window passes.

## Creating a Limiter

Limiters are keyed by an arbitrary term and stored in an ETS-backed registry:

```elixir
alias Foundation.RateLimit.BackoffWindow

# Get or create a limiter for a key (uses default registry)
limiter = BackoffWindow.for_key(:openai_api)

# Multiple calls with the same key return the same limiter
limiter2 = BackoffWindow.for_key(:openai_api)
# limiter and limiter2 reference the same underlying atomics ref
```

## Setting Backoff

When you receive a rate-limit response, set a backoff window:

```elixir
# Back off for 30 seconds
BackoffWindow.set(limiter, 30_000)

# Check if backoff is active
BackoffWindow.should_backoff?(limiter)  # true

# Wait for the backoff to clear
BackoffWindow.wait(limiter)
```

Setting a new backoff while one is active extends the deadline (it never
shortens an active window):

```elixir
BackoffWindow.set(limiter, 30_000)
BackoffWindow.set(limiter, 5_000)   # ignored, original 30s window is longer
BackoffWindow.set(limiter, 60_000)  # extends to 60s from now
```

## Clearing Backoff

```elixir
BackoffWindow.clear(limiter)
BackoffWindow.should_backoff?(limiter)  # false
```

## Custom Registries

Use separate registries to isolate different groups of limiters:

```elixir
registry = BackoffWindow.new_registry(name: :my_rate_limiters)
limiter = BackoffWindow.for_key(registry, :stripe_api)
```

## Usage Pattern

A typical pattern for HTTP clients:

```elixir
alias Foundation.RateLimit.BackoffWindow

limiter = BackoffWindow.for_key(:my_api)

def call_api(limiter, request) do
  # Wait for any active backoff to clear
  BackoffWindow.wait(limiter)

  case HTTPClient.request(request) do
    {:ok, %{status: 429, headers: headers} = response} ->
      retry_after = Foundation.Retry.HTTP.parse_retry_after(headers)
      BackoffWindow.set(limiter, retry_after)
      {:error, {:rate_limited, response}}

    {:ok, %{status: status} = response} when status in 200..299 ->
      {:ok, response}

    error ->
      error
  end
end
```
