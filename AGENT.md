# Foundation Library - Agent Guide

## Build/Test Commands
- **Build**: `mix compile`
- **Test all**: `mix test` or `mix test.all`
- **Test single file**: `mix test test/path/to/test_file.exs`
- **Test with pattern**: `mix test --grep "pattern"`
- **Unit tests**: `mix test.unit`
- **Integration tests**: `mix test.integration` 
- **Quality checks**: `mix qa.all` (format, credo, dialyzer)
- **Development workflow**: `mix dev.check` (format, credo, compile, smoke tests)

## Architecture
Foundation is a protocol-based Elixir infrastructure library with three core protocols:
- **Registry**: Service discovery, process registration, metadata management
- **Coordination**: Distributed consensus, barriers, locks, timeouts
- **Infrastructure**: Circuit breakers, rate limiting, fault tolerance

Key modules: Configuration management, Event system (in-memory store), Telemetry/monitoring, Error handling with structured types. Uses `:fuse` (circuit breakers), `:hammer` (rate limiting), `:poolboy` (connection pools).

## Code Style
- **Format**: 100 char line length (`.formatter.exs`), strict Credo checks
- **Imports**: Alias order enforced, avoid nested aliases >2 levels
- **Naming**: snake_case functions, PascalCase modules, predicate functions end with `?`
- **Types**: Use typespecs, avoid warnings-as-errors in CI
- **Error handling**: Use structured error types with context, avoid raw exceptions
- **Testing**: ExUnit with Mox for mocking, test support in `test/support/`
