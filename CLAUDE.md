# Claude Code Helper for Foundation Project

## Project Overview
Foundation is an Elixir library providing a foundational layer for Elixir applications with configuration management, event storage, telemetry, and infrastructure services.

## Key Commands
- **Run tests**: `mix test`
- **Run specific test categories**: 
  - `mix test --only contract`
  - `mix test --only smoke` 
  - `mix test --only integration`
  - `mix test --only stress`
  - `mix test --only benchmark`
- **Check deps**: `mix deps.get`
- **Compile**: `mix compile`

## Test Structure
- `test/contract/` - Contract/behavior compliance tests
- `test/smoke/` - Basic system health tests
- `test/integration/` - Service interaction tests  
- `test/stress/` - Load and chaos testing
- `test/benchmark/` - Performance baselines
- `test/property/` - Property-based tests
- `test/unit/` - Unit tests

## Architecture
4-layer architecture:
1. **Public API**: Foundation.{Config,Events,Telemetry,Utils}
2. **Business Logic**: Foundation.Logic.*
3. **Service Layer**: Foundation.Services.*
4. **Infrastructure**: Foundation.Infrastructure.*

## Current Status
Working on implementing expanded test suite from TESTS.md and TESTS_githubCopilotSonnet4.md. Contract and smoke tests are completed and passing (25 tests total).

## Next Tasks
Continue with integration tests, stress tests, and other test categories to build comprehensive test coverage.