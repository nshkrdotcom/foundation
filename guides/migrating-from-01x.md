# Migrating from 0.1.x

Foundation 0.2+ is a complete rewrite. It is **not compatible** with the
0.1.x series, and there is no automated upgrade path. Treat 0.2+ as a new
library with a different API surface and runtime model.

## What Changed

### Removed

The following 0.1.x modules and features were removed entirely:

- **Infrastructure wrappers**: Fuse, Hammer, and Poolboy integrations
- **Configuration server**: `Foundation.Config` GenServer
- **Event store**: `Foundation.Events` event publishing and querying
- **Process registry**: Service and process registry modules
- **Supervision tree**: All 0.1.x application-level supervision

### Replaced

| 0.1.x | 0.2.x |
|-------|-------|
| `Foundation.Infrastructure` circuit breakers (via Fuse) | `Foundation.CircuitBreaker` (pure Elixir, no dependencies) |
| `Foundation.Infrastructure` rate limiting (via Hammer) | `Foundation.RateLimit.BackoffWindow` (ETS + atomics) |
| `Foundation.Infrastructure` connection pools (via Poolboy) | `Foundation.Semaphore.Counting` / `Foundation.Semaphore.Weighted` |
| N/A | `Foundation.Backoff` -- configurable backoff policies |
| N/A | `Foundation.Retry` -- retry orchestration |
| N/A | `Foundation.Poller` -- polling loops |
| N/A | `Foundation.Dispatch` -- layered dispatch limiter |

### Dependencies

0.2.x has a single runtime dependency: `telemetry ~> 1.2`. All external
resilience libraries (Fuse, Hammer, Poolboy) have been removed.

## How to Migrate

1. **Do not bump the version constraint.** Add `{:foundation, "~> 0.2.1"}`
   as a new dependency alongside your existing 0.1.x usage, or plan a
   full replacement.

2. **Audit your usage.** Search for `Foundation.Config`, `Foundation.Events`,
   and `Foundation.Infrastructure` in your codebase. Each call site needs
   to be rewritten.

3. **Replace patterns incrementally.** Start with circuit breakers or retry
   logic, then move to rate limiting and concurrency control.

4. **Remove 0.1.x supervision.** Foundation 0.2.x does not start an
   application supervision tree. Remove any `Foundation` entries from your
   application's `children` list.

## Requirements

- Elixir 1.15+ (was 1.14+ in 0.1.x)
- OTP 26+
