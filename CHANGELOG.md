# Changelog

## [0.2.0] - 2026-01-08

Complete rewrite focusing on lightweight, composable resilience primitives.

### Added

#### Backoff (`Foundation.Backoff`)
- Configurable backoff policies with exponential, linear, and constant strategies
- Jitter support: none, factor, additive, and range strategies
- Pluggable random functions for deterministic testing

#### Retry (`Foundation.Retry`)
- Generic retry orchestration with `Policy` and `State` structs
- Configurable max attempts, elapsed time limits, and progress timeouts
- Support for custom `retry_on` predicates and `retry_after_ms_fun` callbacks

#### Retry Helpers (`Foundation.Retry.*`)
- `Config` - retry configuration struct with sensible defaults
- `Handler` - stateful retry handler built from config
- `HTTP` - HTTP-specific utilities: status classification, `Retry-After` parsing
- `Runner` - generic retry runner with telemetry hooks and exception handling

#### Polling (`Foundation.Poller`)
- Generic polling loop with backoff, timeout, and max-attempts controls
- Async execution via `Task` with graceful shutdown
- Custom exception handlers

#### Rate Limiting (`Foundation.RateLimit.BackoffWindow`)
- Shared backoff windows for rate-limited APIs
- ETS-backed per-key state with expiration

#### Circuit Breaker (`Foundation.CircuitBreaker`)
- Pure functional circuit breaker state machine (closed/open/half-open)
- Configurable failure threshold, reset timeout, and half-open call limits
- `Foundation.CircuitBreaker.Registry` - GenServer-backed registry with ETS heir support

#### Semaphores (`Foundation.Semaphore.*`)
- `Counting` - ETS-backed counting semaphore with blocking acquire
- `Weighted` - GenServer-backed weighted semaphore for byte budgets
- `Limiter` - simple process-based semaphore for quick concurrency limits

#### Dispatch (`Foundation.Dispatch`)
- Layered dispatch limiter combining concurrency, throttling, and byte budgets
- Automatic throttle mode under backoff pressure
- Configurable byte penalty multipliers

#### Telemetry (`Foundation.Telemetry`)
- Lightweight wrappers around `:telemetry.execute/3`
- `measure/3` helper for timing function execution
- Optional `telemetry_reporter` integration for reporter lifecycle management

### Changed
- Minimum Elixir version is now 1.15
- Only runtime dependency is `telemetry ~> 1.2`

### Removed
- Legacy infrastructure wrappers (fuse, hammer, poolboy integrations)
- Configuration server and event store services
- Process registry and service registry modules
- All 0.1.x application supervision tree and runtime services
