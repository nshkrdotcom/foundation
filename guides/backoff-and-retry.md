# Backoff & Retry

Foundation separates backoff calculation from retry orchestration, giving you
full control over delay strategies and retry conditions.

## Backoff Policies

A `Foundation.Backoff.Policy` controls how delays grow between attempts:

```elixir
alias Foundation.Backoff

# Exponential backoff (default): 100, 200, 400, 800, ...
backoff = Backoff.Policy.new(strategy: :exponential, base_ms: 100, max_ms: 5_000)

# Linear backoff: 100, 200, 300, 400, ...
backoff = Backoff.Policy.new(strategy: :linear, base_ms: 100, max_ms: 5_000)

# Constant backoff: 100, 100, 100, ...
backoff = Backoff.Policy.new(strategy: :constant, base_ms: 100)
```

### Jitter

Add randomness to prevent thundering herds:

```elixir
# Factor jitter: multiply delay by a random factor in [1-jitter, 1]
Backoff.Policy.new(
  strategy: :exponential,
  base_ms: 100,
  max_ms: 5_000,
  jitter_strategy: :factor,
  jitter: 0.25
)

# Additive jitter: add up to jitter * delay
Backoff.Policy.new(
  strategy: :exponential,
  base_ms: 100,
  jitter_strategy: :additive,
  jitter: 0.5
)

# Range jitter: multiply delay by a random factor in [min, max]
Backoff.Policy.new(
  strategy: :exponential,
  base_ms: 100,
  jitter_strategy: :range,
  jitter: {0.5, 1.5}
)
```

### Computing Delays Directly

```elixir
backoff = Backoff.Policy.new(strategy: :exponential, base_ms: 100, max_ms: 5_000)

Backoff.delay(backoff, 0)  # 100
Backoff.delay(backoff, 1)  # 200
Backoff.delay(backoff, 5)  # 3200
Backoff.delay(backoff, 10) # 5000 (capped at max_ms)
```

### Option Aliases

For readability, you can use `:base_delay_ms` and `:max_delay_ms` as aliases:

```elixir
Backoff.Policy.new(base_delay_ms: 200, max_delay_ms: 10_000)
```

String strategy names are also supported for configs loaded from external
sources:

```elixir
Backoff.Policy.new(strategy: "exponential", jitter_strategy: "factor")
```

## Retry Policies

A `Foundation.Retry.Policy` defines when and how to retry:

```elixir
alias Foundation.Retry

policy = Retry.Policy.new(
  max_attempts: 5,
  backoff: Backoff.Policy.new(strategy: :exponential, base_ms: 100),
  retry_on: fn
    {:error, :timeout} -> true
    {:error, :rate_limited} -> true
    _ -> false
  end
)

{result, state} = Retry.run(fn -> call_api() end, policy)
```

### Time Limits

```elixir
Retry.Policy.new(
  max_attempts: :infinity,
  max_elapsed_ms: 30_000,        # stop after 30 seconds total
  progress_timeout_ms: 10_000,   # stop if manual retries make no progress for 10 seconds
  backoff: backoff,
  retry_on: fn {:error, _} -> true; _ -> false end
)
```

`max_elapsed_ms` is enforced by `Retry.run/3`. `progress_timeout_ms` is most
useful when you drive retries manually with `Retry.step/4` and call
`Retry.record_progress/2` whenever the operation makes forward progress.

### Server-Directed Delays

If your service returns a retry delay (e.g., from a `Retry-After` header),
pass it via `:retry_after_ms_fun`:

```elixir
Retry.Policy.new(
  max_attempts: 5,
  backoff: backoff,
  retry_on: fn {:error, _} -> true; _ -> false end,
  retry_after_ms_fun: fn
    {:error, {:rate_limited, retry_after_ms}} -> retry_after_ms
    _ -> nil  # fall back to backoff policy
  end
)
```

### Step-by-Step Control

For custom retry loops, use `Retry.step/4` directly and record progress when
an attempt advances the work:

```elixir
state = Retry.State.new()
result = fetch_next_page()

state =
  case result do
    {:error, {:partial_progress, _page}} -> Retry.record_progress(state)
    _ -> state
  end

case Retry.step(state, policy, result) do
  {:retry, delay_ms, next_state} ->
    Process.sleep(delay_ms)
    # ... retry with next_state

  {:halt, final_result, _state} ->
    final_result
end
```

## Retry Runner

`Foundation.Retry.Runner` provides a higher-level runner with built-in
telemetry support:

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

See `Foundation.Retry.Config` and `Foundation.Retry.Handler` for all
available options.
