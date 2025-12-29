# Changelog

## 0.2.0 - 2025-12-27
- Reset docs references and refocus Foundation on resilience primitives.
- Remove legacy infrastructure wrappers and dependencies (fuse/hammer/poolboy).
- Prepare for Backoff/Retry/RateLimit/CircuitBreaker/Semaphore primitives.
- Add lightweight telemetry helpers with optional telemetry_reporter integration.
- Remove outdated config/test scaffolding and the cloned semaphore reference.
- Add retry configuration/handler helpers and HTTP retry utilities.
- Add semaphore limiter and layered dispatch limiter primitives.
- Add generic retry runner and polling helper for long-running workflows.
