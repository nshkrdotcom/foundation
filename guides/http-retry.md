# HTTP Retry Helpers

`Foundation.Retry.HTTP` provides status-code classification, `Retry-After`
header parsing, and method-aware retry decisions for HTTP clients.

## Status Classification

```elixir
alias Foundation.Retry.HTTP

HTTP.retryable_status?(429)  # true  - rate limited
HTTP.retryable_status?(500)  # true  - server error
HTTP.retryable_status?(503)  # true  - service unavailable
HTTP.retryable_status?(408)  # true  - request timeout
HTTP.retryable_status?(409)  # true  - conflict
HTTP.retryable_status?(400)  # false - client error
HTTP.retryable_status?(200)  # false - success
```

The default set covers 408, 409, 429, and all 5xx codes.

## Retry-After Parsing

Parse `Retry-After` headers into milliseconds:

```elixir
# Delta-seconds
HTTP.parse_retry_after([{"Retry-After", "120"}])
# => 120_000

# HTTP-date (IMF-fixdate, RFC 850, asctime)
HTTP.parse_retry_after([{"Retry-After", "Wed, 31 Dec 2099 23:59:59 GMT"}])
# => milliseconds until that time

# Millisecond header (used by some APIs)
HTTP.parse_retry_after([{"retry-after-ms", "500"}])
# => 500

# Default when header is missing
HTTP.parse_retry_after([])
# => 1_000 (default)

HTTP.parse_retry_after([], 5_000)
# => 5_000 (custom default)
```

## Should-Retry Decisions

Check whether a response should be retried based on status and headers:

```elixir
HTTP.should_retry?(%{status: 429, headers: []})     # true
HTTP.should_retry?(%{status: 200, headers: []})     # false
HTTP.should_retry?(503)                              # true
HTTP.should_retry?({429, [{"Retry-After", "60"}]})  # true
```

The `x-should-retry` header overrides status-code classification:

```elixir
HTTP.should_retry?(%{status: 500, headers: [{"x-should-retry", "false"}]})
# => false (header overrides)
```

## Method-Aware Rules

Different HTTP methods often have different retry semantics. For example,
you might retry `GET` on 500 but not `POST`:

```elixir
rules = [
  all: [429],                 # retry 429 for any method
  get: [500, 502, 503],       # retry server errors for GET
  delete: [500, 502, 503]     # retry server errors for DELETE
]

HTTP.should_retry_for_method?(:get, %{status: 503, headers: []}, rules)
# => true

HTTP.should_retry_for_method?(:post, %{status: 500, headers: []}, rules)
# => false (POST not in rules for 500)

HTTP.should_retry_for_method?(:post, %{status: 429, headers: []}, rules)
# => true (429 matches :all)
```

Rules accept both keyword lists and maps, and methods can be atoms or
strings.

## Retry Delay Calculation

`HTTP.retry_delay/1` provides exponential backoff with jitter, designed for
HTTP retry loops:

```elixir
HTTP.retry_delay(0)  # ~375-500ms
HTTP.retry_delay(1)  # ~750-1000ms
HTTP.retry_delay(2)  # ~1500-2000ms
```

Customize the initial and max delays:

```elixir
HTTP.retry_delay(0, 1_000, 30_000)  # start at 1s, cap at 30s
```

## Combining with Retry

Wire HTTP helpers into a retry policy:

```elixir
alias Foundation.{Backoff, Retry}
alias Foundation.Retry.HTTP

policy = Retry.Policy.new(
  max_attempts: 5,
  backoff: Backoff.Policy.new(strategy: :exponential, base_ms: 500, max_ms: 30_000),
  retry_on: fn
    {:ok, %{status: status}} -> HTTP.retryable_status?(status)
    {:error, _} -> true
    _ -> false
  end,
  retry_after_ms_fun: fn
    {:ok, %{status: 429, headers: headers}} -> HTTP.parse_retry_after(headers)
    _ -> nil
  end
)

{result, _state} = Retry.run(fn -> make_request() end, policy)
```
