# OTP Cleanup Integration Tests

This directory contains comprehensive integration tests for the Process dictionary cleanup migration in the Foundation/Jido system.

## Overview

The OTP cleanup migration eliminates Process dictionary usage in favor of proper OTP patterns:
- **ETS tables** for caching and registry operations
- **GenServer state** for process-local storage
- **Logger metadata** for error context
- **Explicit parameter passing** instead of implicit state

## Test Structure

### 🧪 Test Files

#### Core Integration Tests
1. **`otp_cleanup_integration_test.exs`** - Main integration tests
   - Process dictionary elimination validation
   - Feature flag integration tests  
   - Error context migration tests
   - Registry migration tests
   - Telemetry migration tests
   - System integration tests

2. **`otp_cleanup_e2e_test.exs`** - End-to-end functionality tests
   - Complete agent registration flow
   - Complex workflow integration
   - Migration workflow tests
   - Production simulation tests

3. **`otp_cleanup_performance_test.exs`** - Performance regression tests
   - Registry performance benchmarks
   - Error context performance tests
   - Telemetry performance tests
   - Combined workload performance tests
   - Performance comparison matrix

4. **`otp_cleanup_stress_test.exs`** - Concurrency and stress tests
   - Concurrent registry access
   - Error context stress tests
   - Telemetry stress tests
   - Combined system stress tests

5. **`otp_cleanup_feature_flag_test.exs`** - Feature flag integration tests
   - Feature flag toggle tests
   - Migration stage tests
   - Percentage rollout tests
   - Flag interaction tests

6. **`otp_cleanup_failure_recovery_test.exs`** - Failure and recovery tests
   - ETS table failure recovery
   - GenServer crash recovery
   - Process death and cleanup
   - Memory leak prevention
   - Network and external failure simulation

7. **`otp_cleanup_observability_test.exs`** - Monitoring and observability tests
   - Telemetry event continuity
   - Error reporting and context
   - Performance monitoring
   - Observability integration tests

#### Development Tests
8. **`otp_cleanup_basic_test.exs`** - Basic functionality validation
   - Current state validation
   - Testing infrastructure validation
   - Mock implementation tests
   - Foundation integration readiness

### 🎯 Test Categories

#### By Purpose
- **Integration**: End-to-end system functionality
- **Performance**: Benchmarking and regression detection
- **Stress**: High-load and concurrency testing
- **Feature Flags**: Implementation switching and rollbacks
- **Failure Recovery**: Error scenarios and recovery
- **Observability**: Telemetry and monitoring continuity

#### By Implementation Stage
- **Stage 0**: Legacy implementation (Process dictionary)
- **Stage 1**: ETS registry only
- **Stage 2**: Logger error context
- **Stage 3**: GenServer telemetry
- **Stage 4**: Full enforcement

## Running Tests

### 🚀 Quick Start

```bash
# Run basic tests (working today)
mix test test/foundation/otp_cleanup_basic_test.exs

# Run comprehensive test suite (when implementations are ready)
elixir test/run_otp_cleanup_tests.exs
```

### 📋 Test Runner Options

```bash
# Run all tests
elixir test/run_otp_cleanup_tests.exs

# Run specific test suite
elixir test/run_otp_cleanup_tests.exs --suite "Performance Regression"

# Performance tests only
elixir test/run_otp_cleanup_tests.exs --performance-only

# Skip slow tests for quick validation
elixir test/run_otp_cleanup_tests.exs --skip-slow --verbose

# Run individual test files
mix test test/foundation/otp_cleanup_integration_test.exs
mix test test/foundation/otp_cleanup_e2e_test.exs --trace
```

### 🏷️ Test Tags

Tests are tagged for selective execution:

- `@moduletag :integration` - Integration tests
- `@moduletag :e2e` - End-to-end tests  
- `@moduletag :performance` - Performance tests
- `@moduletag :stress` - Stress tests
- `@moduletag :feature_flags` - Feature flag tests
- `@moduletag :failure_recovery` - Failure recovery tests
- `@moduletag :observability` - Observability tests

```bash
# Run only performance tests
mix test --include performance --exclude integration

# Run only integration tests
mix test --include integration --exclude performance
```

## Test Development Status

### ✅ Available Now
- **Basic Tests**: Core functionality validation that works with current codebase
- **Mock Tests**: Simulated implementations for development validation
- **Infrastructure Tests**: Testing framework and helper validation

### 🚧 Implementation Dependent
- **Integration Tests**: Require foundation modules (FeatureFlags, ErrorContext, etc.)
- **E2E Tests**: Require complete implementation stack
- **Performance Tests**: Require both old and new implementations for comparison
- **Stress Tests**: Require production-ready implementations
- **Feature Flag Tests**: Require feature flag infrastructure
- **Recovery Tests**: Require fault-tolerant implementations
- **Observability Tests**: Require telemetry infrastructure

## Implementation Requirements

### Required Foundation Modules
- `Foundation.FeatureFlags` - Feature flag management
- `Foundation.ErrorContext` - Error context handling
- `Foundation.Registry` - Agent registry interface
- `Foundation.Telemetry.Span` - Span management
- `Foundation.Telemetry.SampledEvents` - Event sampling
- `Foundation.Protocols.RegistryETS` - ETS-based registry
- `Foundation.CredoChecks.NoProcessDict` - Credo enforcement

### Required Infrastructure
- ETS tables for registry and caching
- GenServer processes for telemetry
- Logger metadata for error context
- Telemetry event emission
- Process monitoring and cleanup

## Test Scenarios

### 🔄 Migration Scenarios
1. **Stage-by-stage migration** - Test each implementation stage
2. **Rollback scenarios** - Test rolling back to previous stages
3. **Emergency rollback** - Test emergency rollback to legacy
4. **Partial rollouts** - Test percentage-based rollouts

### 🏋️ Load Scenarios
1. **High concurrency** - 100+ concurrent processes
2. **High frequency** - 1000+ operations per second
3. **Memory pressure** - Large data structures and contexts
4. **Long duration** - Extended operation periods

### 💥 Failure Scenarios
1. **ETS table deletion** - Recovery from table loss
2. **GenServer crashes** - Process restart scenarios
3. **Process death** - Cleanup after process termination
4. **Resource exhaustion** - Recovery from resource limits
5. **Network simulation** - Simulated network failures

### 📊 Performance Scenarios
1. **Baseline benchmarks** - Current implementation performance
2. **Regression detection** - Performance comparison across implementations
3. **Scaling tests** - Performance under increasing load
4. **Memory efficiency** - Memory usage patterns and cleanup

## Expected Outcomes

### ✅ Success Criteria
- **Functionality**: Complete functional equivalence between old and new implementations
- **Performance**: No significant performance regressions (< 2x slowdown)
- **Reliability**: No memory leaks or resource exhaustion
- **Observability**: No loss of telemetry or error reporting
- **Recovery**: Graceful handling of all failure scenarios

### 📈 Performance Targets
- **Registry Operations**: < 1ms per operation
- **Error Context**: < 0.1ms per operation
- **Span Operations**: < 0.5ms per operation
- **Memory Growth**: < 100MB under load
- **Process Leaks**: < 50 extra processes

### 🔍 Quality Gates
- All integration tests pass with flags enabled and disabled
- No performance regressions detected in benchmarks
- No memory leaks under stress testing
- Proper cleanup verified in all failure scenarios
- Complete telemetry and observability continuity

## Contributing

### Adding New Tests
1. Choose appropriate test file based on test category
2. Follow existing patterns for setup/teardown
3. Use proper test tags for categorization
4. Include both positive and negative test cases
5. Add performance assertions where appropriate

### Test Development Guidelines
1. **Use realistic scenarios** - Test real-world usage patterns
2. **Test failure modes** - Include error and edge cases
3. **Validate cleanup** - Ensure resources are properly released
4. **Check performance** - Include timing and memory assertions
5. **Document expectations** - Clear assertions and error messages

### When Implementations Change
1. Update test expectations as implementations mature
2. Add new test scenarios for new features
3. Remove temporary workarounds as modules become available
4. Update performance baselines as optimizations are made

## Troubleshooting

### Common Issues
1. **Module not loaded**: Many tests skip functionality if modules aren't available yet
2. **Service not started**: Some tests require services to be running
3. **Timing issues**: Use proper wait conditions instead of fixed delays
4. **Resource cleanup**: Ensure proper cleanup in test teardown

### Debugging Tips
1. **Run with --trace**: See detailed test execution
2. **Use individual test files**: Isolate specific functionality
3. **Check module availability**: Verify required modules are loaded
4. **Monitor resource usage**: Watch memory and process counts
5. **Enable verbose output**: Use --verbose flag for detailed reporting

---

This comprehensive test suite ensures that the Process dictionary cleanup maintains functionality, performance, and reliability while eliminating anti-patterns and establishing proper OTP compliance.