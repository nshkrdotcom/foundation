# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.1.0]: https://github.com/nshkrdotcom/foundation/releases/tag/v0.1.0
