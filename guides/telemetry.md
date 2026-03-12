# Telemetry

`Foundation.Telemetry` provides lightweight wrappers around `:telemetry` for
emitting events and measuring function execution time. It optionally
integrates with `TelemetryReporter` for forwarding events to external
systems.

## Emitting Events

```elixir
alias Foundation.Telemetry

Telemetry.execute(
  [:my_app, :request, :complete],
  %{count: 1, bytes: 4096},
  %{status: 200, path: "/api/users"}
)
```

## Measuring Duration

`measure/3` times a function and emits a `[:stop]` event on success or an
`[:exception]` event on failure:

```elixir
result = Telemetry.measure(
  [:my_app, :db, :query],
  %{table: :users},
  fn -> Repo.all(User) end
)
```

This emits `[:my_app, :db, :query, :stop]` with `%{duration: microseconds}`
on success, or `[:my_app, :db, :query, :exception]` on failure (then
re-raises).

### Custom Time Units

```elixir
Telemetry.measure(
  [:my_app, :process],
  %{},
  fn -> expensive_work() end,
  time_unit: :millisecond
)
```

## Reporter Integration

If the optional `telemetry_reporter` package is available, Foundation can
start reporters and attach handlers:

```elixir
# Start a reporter
{:ok, reporter} = Telemetry.start_reporter(
  name: :my_reporter,
  transport: MyTransport
)

# Attach handlers that forward telemetry events to the reporter
{:ok, handler_id} = Telemetry.attach_reporter(
  reporter: reporter,
  events: [[:my_app, :request, :complete]]
)

# Log directly
Telemetry.log(reporter, "api_call", %{status: 200}, :info)

# Detach when done
Telemetry.detach_reporter(handler_id)
```

If `telemetry_reporter` is not installed, these functions return
`{:error, :missing_dependency}`.
