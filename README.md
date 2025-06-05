# Foundation

**A comprehensive Elixir infrastructure and observability library providing essential services for building robust, scalable applications.**

[![CI](https://github.com/nshkrdotcom/foundation/actions/workflows/elixir.yaml/badge.svg)](https://github.com/nshkrdotcom/foundation/actions/workflows/elixir.yaml)
[![Elixir](https://img.shields.io/badge/elixir-1.18.3-purple.svg)](https://elixir-lang.org)
[![OTP](https://img.shields.io/badge/otp-27.3.3-blue.svg)](https://www.erlang.org)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

## 🚀 Overview

Foundation is a standalone library extracted from the ElixirScope project, designed to provide core infrastructure services including configuration management, event storage, telemetry, process management, and fault tolerance patterns.

### ✨ Key Features

### 🔧 **Configuration Management**
- Dynamic configuration updates with subscriber notifications
- Nested configuration structures with validation
- Environment-specific configurations
- Runtime configuration changes with rollback support
- Path-based configuration access and updates

### 📊 **Event System**
- Structured event creation and storage
- Event querying and correlation tracking
- Batch operations for high-throughput scenarios
- Event relationships and workflow tracking
- In-memory event store with pruning capabilities

### 📈 **Telemetry & Monitoring**
- Metrics collection (counters, gauges, histograms)
- Event measurement and timing
- Integration with `:telemetry` ecosystem
- Custom metric handlers and aggregation
- Performance monitoring and VM metrics

### 🛡️ **Infrastructure Protection**
- Circuit breaker patterns (via `:fuse`)
- Rate limiting (via `:hammer`)
- Connection pool management (via `:poolboy`)
- Fault tolerance and resilience patterns
- Unified protection facade for coordinated safeguards

### 🔍 **Service Discovery**
- Service registration and lookup
- Health checking for registered services
- Process registry with supervision
- Namespace-based service organization
- Registry performance monitoring

### 🚨 **Error Handling**
- Structured error types with context
- Error context tracking (user, request, operation)
- Error aggregation and reporting
- Comprehensive error logging
- Retry strategies and error recovery

### 🛠️ **Utilities**
- ID generation and correlation tracking
- Time measurement and formatting
- Memory usage tracking
- System statistics collection

## 📦 Installation

Add Foundation to your `mix.exs`:

```elixir
def deps do
  [
    {:foundation, "~> 0.1.0"}
  ]
end
```

Ensure Foundation starts before your application:

```elixir
def application do
  [
    mod: {MyApp.Application, []},
    extra_applications: [:foundation]
  ]
end
```

## 🏁 Quick Start

### Basic Usage

```elixir
# Initialize Foundation (typically done by your application supervisor)
:ok = Foundation.initialize()

# Configure your application
:ok = Foundation.Config.update([:app, :feature_flags, :new_ui], true)

# Create and store events
correlation_id = Foundation.Utils.generate_correlation_id()
{:ok, event} = Foundation.Events.new_event(
  :user_action, 
  %{action: "login", user_id: 123},
  correlation_id: correlation_id
)
{:ok, event_id} = Foundation.Events.store(event)

# Emit telemetry metrics
:ok = Foundation.Telemetry.emit_counter(
  [:myapp, :user, :login_attempts], 
  %{user_id: 123}
)

# Use infrastructure protection
result = Foundation.Infrastructure.execute_protected(
  :external_api_call,
  [circuit_breaker: :api_fuse, rate_limiter: {:api_user_rate, "user_123"}],
  fn -> ExternalAPI.call() end
)
```

### Configuration Management

```elixir
# Get configuration
{:ok, config} = Foundation.Config.get()
{:ok, value} = Foundation.Config.get([:ai, :provider])

# Update configuration
:ok = Foundation.Config.update([:dev, :debug_mode], true)

# Subscribe to configuration changes
:ok = Foundation.Config.subscribe()
# Receive: {:config_notification, {:config_updated, path, new_value}}

# Check updatable paths
{:ok, paths} = Foundation.Config.updatable_paths()
```

### Event Management

```elixir
# Create different types of events
{:ok, user_event} = Foundation.Events.new_user_event(123, :profile_updated, %{field: "email"})
{:ok, system_event} = Foundation.Events.new_system_event(:maintenance_started, %{duration: "2h"})
{:ok, error_event} = Foundation.Events.new_error_event(:api_timeout, %{service: "users"})

# Store events
{:ok, event_id} = Foundation.Events.store(user_event)

# Query events
{:ok, events} = Foundation.Events.query(%{event_type: :user_action})
{:ok, correlated} = Foundation.Events.get_by_correlation(correlation_id)
```

### Telemetry & Monitoring

```elixir
# Measure function execution
result = Foundation.Telemetry.measure(
  [:myapp, :database, :query],
  %{table: "users"},
  fn -> Database.fetch_users() end
)

# Emit different metric types
:ok = Foundation.Telemetry.emit_counter([:api, :requests], %{endpoint: "/users"})
:ok = Foundation.Telemetry.emit_gauge([:system, :memory], 1024, %{unit: :mb})

# Get collected metrics
{:ok, metrics} = Foundation.Telemetry.get_metrics()
```

### Infrastructure Protection

```elixir
# Configure protection for a service
Foundation.Infrastructure.configure_protection(:payment_service, %{
  circuit_breaker: %{
    failure_threshold: 5,
    recovery_time: 30_000
  },
  rate_limiter: %{
    scale: 60_000,  # 1 minute
    limit: 100      # 100 requests per minute
  }
})

# Execute protected operations
result = Foundation.Infrastructure.execute_protected(
  :payment_service,
  [circuit_breaker: :payment_breaker, rate_limiter: {:payment_api, user_id}],
  fn -> PaymentAPI.charge(amount) end
)
```

## 🏗️ Architecture

Foundation follows a layered architecture with clear separation of concerns:

```
┌─────────────────────────────────────────┐
│             Public API Layer            │
│   Foundation.{Config,Events,Telemetry}  │
├─────────────────────────────────────────┤
│           Business Logic Layer          │
│    Foundation.Logic.{Config,Event}      │
├─────────────────────────────────────────┤
│            Service Layer                │
│ Foundation.Services.{ConfigServer,      │
│   EventStore,TelemetryService}          │
├─────────────────────────────────────────┤
│         Infrastructure Layer            │
│ Foundation.{ProcessRegistry,            │
│   ServiceRegistry,Infrastructure}       │
└─────────────────────────────────────────┘
```

### Key Design Principles

- **Separation of Concerns**: Each layer has a specific responsibility
- **Contract-Based**: All services implement well-defined behaviors
- **Fault Tolerance**: Built-in error handling and recovery mechanisms
- **Observability**: Comprehensive telemetry and monitoring
- **Testability**: Extensive test coverage with different test types

## 📚 Documentation

- [Complete API Documentation](docs/API_FULL.md) - Comprehensive API reference
- [Architecture Guide](docs/01_foundation_enhance.md) - Design patterns and architecture
- [Migration Guide](docs/02_extract_plan.md) - Upgrade and migration information

## 🧪 Testing

Foundation includes comprehensive test coverage:

```bash
# Run all tests
mix test

# Run specific test suites
mix test.unit          # Unit tests
mix test.integration   # Integration tests
mix test.contract      # Contract tests
mix test.smoke         # Smoke tests

# Run with coverage
mix coveralls
mix coveralls.html     # Generate HTML coverage report
```

### Test Categories

- **Unit Tests**: Test individual modules in isolation
- **Integration Tests**: Test service interactions
- **Contract Tests**: Verify API contracts and behaviors
- **Smoke Tests**: Basic functionality verification
- **Property Tests**: Property-based testing with StreamData

## 🔧 Development

### Setup

```bash
# Get dependencies
mix deps.get

# Compile project
mix compile

# Setup development environment
mix setup

# Run development checks
mix dev.check
```

### Quality Assurance

```bash
# Format code
mix format

# Run static analysis
mix credo --strict
mix dialyzer

# Run full QA pipeline
mix qa.all
```

### Development Workflow

```bash
# Watch tests during development
mix test.watch

# Run development workflow
mix dev.workflow

# Validate architecture
mix validate_architecture
```

## 📊 Performance

Foundation is designed for high performance:

- **Event Storage**: In-memory store with configurable retention
- **Configuration**: Cached configuration with efficient updates
- **Telemetry**: Low-overhead metric collection
- **Circuit Breakers**: Fast failure detection
- **Rate Limiting**: Efficient token bucket implementation

### Benchmarks

```bash
# Run performance benchmarks
mix dev.benchmark
```

## 🔒 Security

- Input validation at all boundaries
- Secure configuration defaults
- Access control for sensitive operations
- Audit logging for security events
- Protection against common vulnerabilities

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run the full test suite
6. Submit a pull request

### Code Style

- Follow Elixir community conventions
- Use `mix format` for consistent formatting
- Add comprehensive documentation
- Include typespecs for all public functions

## 📋 Requirements

- **Elixir**: ~> 1.15
- **Erlang**: Compatible with Elixir requirements
- **Dependencies**: See `mix.exs` for complete list

### Core Dependencies

- `telemetry` - Telemetry events and metrics
- `jason` - JSON encoding/decoding
- `poolboy` - Connection pooling
- `hammer` - Rate limiting
- `fuse` - Circuit breakers

## 📄 License

See [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Issues**: Report bugs and request features on GitHub
- **Documentation**: Comprehensive API documentation available
- **Community**: Join the Elixir community discussions

---

**Foundation** - Building reliable Elixir applications from the ground up. 🏗️
