# MABEAM Production Configuration Guide

## Overview

This guide provides comprehensive configuration recommendations for deploying MABEAM (Multi-Agent Beam) services in production environments. All MABEAM services now use Foundation's ServiceBehaviour for enhanced lifecycle management and production readiness.

## Service Configuration

### MABEAM Core (Foundation.MABEAM.Core)

The core orchestrator coordinates universal variables and manages agent coordination.

**Default Configuration:**
```elixir
%{
  max_variables: 1000,
  coordination_timeout: 5000,
  history_retention: 100,
  telemetry_enabled: true,
  health_check_interval: 30_000,
  graceful_shutdown_timeout: 10_000,
  dependencies: [Foundation.ProcessRegistry, Foundation.ServiceRegistry, Foundation.Telemetry]
}
```

**Production Tuning:**
```elixir
# In config/prod.exs
config :foundation, Foundation.MABEAM.Core,
  max_variables: 5000,           # Increase for large-scale deployments
  coordination_timeout: 10_000,   # Longer timeout for complex coordinations
  history_retention: 1000,       # More history for analysis
  health_check_interval: 15_000  # More frequent health checks
```

### MABEAM Agent Registry (Foundation.MABEAM.AgentRegistry)

Manages agent lifecycle, registration, and monitoring.

**Default Configuration:**
```elixir
%{
  max_agents: 1000,
  health_check_interval: 30_000,
  telemetry_enabled: true,
  auto_restart: true,
  resource_monitoring: true,
  graceful_shutdown_timeout: 10_000,
  dependencies: [Foundation.ProcessRegistry, Foundation.MABEAM.Core]
}
```

**Production Tuning:**
```elixir
# In config/prod.exs
config :foundation, Foundation.MABEAM.AgentRegistry,
  max_agents: 10_000,            # Scale for production workloads
  health_check_interval: 20_000, # More frequent monitoring
  auto_restart: true,            # Always enable in production
  restart_strategy: :permanent   # Ensure agents restart on failure
```

### MABEAM Coordination (Foundation.MABEAM.Coordination)

Handles multi-agent coordination protocols including consensus, auctions, and markets.

**Default Configuration:**
```elixir
%{
  default_timeout: 5_000,
  max_concurrent_coordinations: 100,
  telemetry_enabled: true,
  metrics_enabled: true,
  protocol_timeout: 10_000,
  health_check_interval: 30_000,
  graceful_shutdown_timeout: 15_000,
  dependencies: [Foundation.MABEAM.AgentRegistry]
}
```

**Production Tuning:**
```elixir
# In config/prod.exs
config :foundation, Foundation.MABEAM.Coordination,
  max_concurrent_coordinations: 500,  # Higher concurrency for production
  protocol_timeout: 15_000,           # Longer timeout for complex protocols
  auction_cleanup_interval: 60_000,   # Regular cleanup of completed auctions
  market_update_frequency: 5_000      # Frequent market state updates
```

### MABEAM Telemetry (Foundation.MABEAM.Telemetry)

Provides comprehensive observability for MABEAM systems.

**Default Configuration:**
```elixir
%{
  retention_minutes: 60,
  cleanup_interval_ms: 30_000,
  anomaly_detection: true,
  anomaly_threshold: 2.0,
  telemetry_enabled: true,
  metrics_enabled: true,
  health_check_interval: 30_000,
  graceful_shutdown_timeout: 5_000,
  dependencies: [Foundation.ProcessRegistry]
}
```

**Production Tuning:**
```elixir
# In config/prod.exs
config :foundation, Foundation.MABEAM.Telemetry,
  retention_minutes: 1440,        # 24 hours of data retention
  cleanup_interval_ms: 300_000,   # Clean up every 5 minutes
  anomaly_threshold: 1.5,         # More sensitive anomaly detection
  export_interval: 60_000,        # Export metrics every minute
  dashboard_enabled: true         # Enable dashboard in production
```

## Performance Optimization

### Memory Management

**Recommended Settings:**
```elixir
# In config/prod.exs
config :foundation, :mabeam_performance,
  memory_limit_mb: 512,           # Per-service memory limit
  gc_frequency: 30_000,           # Garbage collection frequency
  metrics_retention: 86_400_000   # 24 hours in milliseconds
```

### Health Check Intervals

**Production Recommendations:**
- **Critical Services** (Core, AgentRegistry): 15-30 seconds
- **Support Services** (Coordination, Telemetry): 30-60 seconds
- **Development**: 60+ seconds for reduced noise

```elixir
config :foundation, :health_monitoring,
  global_health_check_interval: 30_000,
  health_check_timeout: 5_000,
  unhealthy_threshold: 3,         # Mark unhealthy after 3 failures
  degraded_threshold: 1          # Mark degraded after 1 failure
```

### Concurrency Settings

```elixir
config :foundation, :mabeam_concurrency,
  max_agents_per_node: 10_000,
  coordination_pool_size: 100,
  telemetry_buffer_size: 1_000
```

## Monitoring and Alerting

### Key Metrics to Monitor

1. **Agent Health:**
   - Active agent count
   - Failed agent restarts
   - Average agent response time

2. **Coordination Performance:**
   - Coordination success rate
   - Average coordination time
   - Active protocol count

3. **System Resources:**
   - Memory usage per service
   - CPU utilization
   - Message queue lengths

4. **Telemetry Health:**
   - Metrics collection rate
   - Data retention efficiency
   - Export success rate

### Alert Configuration

```elixir
# In config/prod.exs
config :foundation, Foundation.MABEAM.Telemetry,
  alerts: [
    %{
      metric: :agent_failure_rate,
      threshold: 0.05,              # 5% failure rate
      comparison: :greater_than,
      action: :email
    },
    %{
      metric: :coordination_timeout_rate,
      threshold: 0.1,               # 10% timeout rate
      comparison: :greater_than,
      action: :log
    },
    %{
      metric: :memory_usage_mb,
      threshold: 400,               # 400MB per service
      comparison: :greater_than,
      action: :notify
    }
  ]
```

## Deployment Checklist

### Pre-Deployment

- [ ] Configure appropriate memory limits
- [ ] Set production health check intervals
- [ ] Enable telemetry and monitoring
- [ ] Configure alert thresholds
- [ ] Review dependency configurations
- [ ] Test graceful shutdown procedures

### Production Verification

- [ ] All MABEAM services start successfully
- [ ] Services register with ProcessRegistry
- [ ] Health checks respond within 1 second
- [ ] Memory usage under 10MB per service initially
- [ ] Telemetry data collection working
- [ ] Alert system functioning

### Performance Validation

Run the performance test suite to validate production readiness:

```bash
mix test test/foundation/mabeam/performance_test.exs --include performance
```

**Expected Results:**
- ✅ Service startup < 100ms
- ✅ Health check response < 10ms  
- ✅ Concurrent request handling (10+ concurrent)
- ✅ Memory usage < 10MB per service
- ✅ All ServiceBehaviour integration working

## Scaling Considerations

### Horizontal Scaling

When scaling MABEAM across multiple nodes:

1. **ProcessRegistry Distribution:** Configure distributed ProcessRegistry
2. **Agent Distribution:** Implement agent placement strategies
3. **Coordination Protocols:** Use distributed consensus algorithms
4. **Telemetry Aggregation:** Set up centralized metrics collection

### Vertical Scaling

For single-node scaling:

```elixir
# Increase resource limits
config :foundation, :mabeam_limits,
  max_agents: 50_000,
  max_coordinations: 1_000,
  max_variables: 10_000
```

## Troubleshooting

### Common Issues

1. **High Memory Usage:**
   - Reduce retention periods
   - Increase cleanup frequency
   - Check for agent leaks

2. **Slow Health Checks:**
   - Reduce health check complexity
   - Increase timeout values
   - Check system load

3. **Coordination Timeouts:**
   - Increase protocol timeouts
   - Reduce concurrent coordination limits
   - Check network latency

### Debug Configuration

For production debugging:

```elixir
config :foundation, :debug,
  log_level: :info,              # Reduce log verbosity
  telemetry_debug: false,        # Disable debug telemetry
  health_check_logging: true     # Enable health check logs
```

## Security Considerations

1. **Process Isolation:** Each agent runs in isolated process
2. **Resource Limits:** Configure memory and CPU limits
3. **Access Control:** Restrict service access to authorized processes
4. **Audit Logging:** Enable comprehensive audit trails
5. **Secure Communication:** Use encrypted inter-node communication

## Conclusion

This configuration guide ensures MABEAM services are production-ready with:

- ✅ **ServiceBehaviour Integration** for enhanced lifecycle management
- ✅ **Performance Optimization** with measured benchmarks
- ✅ **Comprehensive Monitoring** and alerting
- ✅ **Scalability Planning** for growth
- ✅ **Security Best Practices** for safe deployment

For questions or issues, refer to the troubleshooting section or consult the MABEAM implementation documentation.