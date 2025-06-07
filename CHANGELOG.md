# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.3] - 2025-06-07

### Fixed
- **Events API Pipe Chain Support**: Fixed critical bug where `Foundation.Events.new_event(...) |> Foundation.Events.store()` pattern crashed with `FunctionClauseError`
- **Event Store Contract**: Updated `Foundation.Services.EventStore.store/1` to accept both `Event.t()` and `{:ok, Event.t()}` for pipe-friendly usage
- **API Documentation Compliance**: The documented pipe chain pattern now works as advertised in all API examples
- **Event Type Validation**: Added `:test_event` to allowed event types for better test coverage

### Improved
- **Developer Experience**: Foundation Events API now supports both traditional and pipe chain usage patterns without breaking existing code
- **Backward Compatibility**: All existing code using `{:ok, event} = new_event(...); store(event)` pattern continues to work unchanged
- **Error Handling**: Enhanced `store/1` function with proper validation for invalid input types
- **API Consistency**: Foundation now delivers on its documented promise of pipe-friendly Elixir APIs

### Developer Impact
- **No Breaking Changes**: Existing code continues to work exactly as before
- **Enhanced Usability**: Users can now use the more natural pipe chain pattern as documented
- **Better Test Coverage**: Fixed gap where documentation examples weren't being tested in practice

## [0.1.2] - 2025-06-07

### Added
- **Circuit Breaker Initialization**: Added missing `Foundation.Infrastructure.initialize_circuit_breaker/1` and `initialize_circuit_breaker/2` functions for proper circuit breaker setup
- **Telemetry Histogram API**: Implemented complete histogram metrics API with `Foundation.Telemetry.emit_histogram/2` and `emit_histogram/3` functions
- **Comprehensive Documentation**: Added detailed `@doc` annotations with examples for all new public APIs
- **Input Validation**: Added robust validation for circuit breaker configurations and telemetry event names
- **Test Coverage**: Implemented comprehensive test suites using Test-Driven Development (TDD) approach

### Fixed
- **Type Specifications**: Corrected Dialyzer type specifications for non-empty event name lists (`[atom(), ...]`)
- **Behaviour Compliance**: Updated `Foundation.Contracts.Telemetry` behaviour to include histogram callback definitions
- **Error Handling**: Enhanced error messages with proper `Foundation.Types.Error` structures and context information
- **Test Isolation**: Fixed circuit breaker test conflicts by using unique identifiers for test instances

### Improved
- **Code Quality**: All implementations now fully comply with Foundation's code quality standards including proper module documentation, type specifications, and error handling patterns
- **API Consistency**: Histogram API follows the same patterns as existing counter and gauge functions
- **Validation Strictness**: Enhanced input validation with clear error messages for invalid event names, configuration values, and parameter types

### Developer Experience
- **Complete API Coverage**: Foundation now provides a fully functional infrastructure and telemetry API without gaps
- **Better Error Messages**: Detailed validation errors help developers quickly identify and fix configuration issues
- **Comprehensive Examples**: All public functions include practical usage examples in their documentation

## [0.1.1] - 2025-06-06

### Added
- Enhanced ProcessRegistry error handling for better test isolation and system resilience
- Comprehensive security validation for configuration paths and values
- Improved chaos resilience testing with proper failure handling and recovery verification
- Debug logging and monitoring capabilities for test execution

### Fixed
- **Test Configuration**: Modified test configuration to include security tests by default (only excluding `:slow` tests)
- **ProcessRegistry Stability**: Enhanced ProcessRegistry availability detection and automatic restart mechanisms
- **Chaos Resilience Test**: Fixed stress test to properly handle expected failures during service disruption, including:
  - Proper handling of ProcessRegistry being unavailable during chaos testing
  - Graceful chaos monkey operation when services are down
  - Realistic recovery procedures after catastrophic failures
  - Improved recovery metrics verification to handle complete system disruption
- **Test Isolation**: Enhanced test helpers to ensure Foundation application is properly restarted between tests
- **EventStore Security**: Added proper error handling for unauthorized operations (delete, update, clear_all)
- **Security Validation**: Enhanced path and value validation to block malicious configuration attempts
- **Data Consistency Test**: Fixed event correlation ID filtering to prevent test interference

### Improved
- Test stability across integration, security, and stress test suites
- Error handling during service failures and recovery scenarios
- Test helper functions for better Foundation application lifecycle management
- Security test assertions to handle expected security blocks gracefully
- Recovery verification to distinguish between system failures and expected chaos disruption

### Security
- Enhanced configuration path validation to prevent injection attacks
- Improved value sanitization for oversized data and malicious structures
- Added security error responses for unsupported EventStore operations
- Strengthened privilege escalation prevention in security tests

## [0.1.0] - 2025-06-05

### Added

Initial release of Foundation - A comprehensive Elixir infrastructure and observability library.

#### Core Features
- **Configuration Management**: Dynamic configuration updates with subscriber notifications, nested structures with validation, environment-specific configurations, and runtime changes with rollback support
- **Event System**: Structured event creation and storage, querying and correlation tracking, batch operations, event relationships and workflow tracking, in-memory event store with pruning
- **Telemetry & Monitoring**: Metrics collection (counters, gauges, histograms), event measurement and timing, integration with `:telemetry` ecosystem, custom metric handlers
- **Infrastructure Protection**: Circuit breaker patterns (via `:fuse`), rate limiting (via `:hammer`), connection pool management (via `:poolboy`), fault tolerance patterns
- **Service Discovery**: Service registration and lookup, health checking, process registry with supervision, namespace-based service organization

#### Modules
- `Foundation.Application` - Application supervisor and startup
- `Foundation.Config` - Configuration management with graceful degradation
- `Foundation.Events` - Event storage and retrieval system
- `Foundation.Telemetry` - Metrics collection and monitoring
- `Foundation.Infrastructure` - Circuit breakers, rate limiting, and connection pooling
- `Foundation.ServiceRegistry` - Service discovery and health checking
- `Foundation.ProcessRegistry` - Process registration and management
- `Foundation.Types` - Type definitions for configuration, events, and errors
- `Foundation.Validation` - Input validation for configurations and events
- `Foundation.Utils` - Utility functions and helpers

#### Documentation
- Comprehensive API documentation
- Architecture documentation with Mermaid diagrams
- Infrastructure component guides
- Usage examples and best practices

[0.1.3]: https://github.com/nshkrdotcom/foundation/releases/tag/v0.1.3
[0.1.2]: https://github.com/nshkrdotcom/foundation/releases/tag/v0.1.2
[0.1.1]: https://github.com/nshkrdotcom/foundation/releases/tag/v0.1.1
[0.1.0]: https://github.com/nshkrdotcom/foundation/releases/tag/v0.1.0
