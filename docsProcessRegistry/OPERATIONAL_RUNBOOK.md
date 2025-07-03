# Process Dictionary Migration - Operational Runbook

**Purpose**: Step-by-step procedures for safely migrating from Process dictionary to OTP patterns in production.

## Pre-Migration Checklist

### System Requirements
- [ ] Elixir 1.14+ (for latest Logger metadata features)
- [ ] OTP 25+ (for ETS optimizations)
- [ ] Monitoring dashboard access
- [ ] Rollback procedures tested in staging
- [ ] Team notification sent

### Baseline Metrics Collection
```bash
# Collect 24-hour baseline before migration
mix run scripts/collect_baseline_metrics.exs

# Key metrics to track:
# - Registry operation latency (p50, p95, p99)
# - Error context overhead
# - Memory usage (ETS tables)
# - Process count
# - Telemetry event throughput
```

## Migration Sequence

### Stage 1: Enable Monitoring (Day 1)

```elixir
# In production console
Foundation.FeatureFlags.enable(:enable_migration_monitoring)

# Verify telemetry events
:telemetry.execute([:foundation, :migration, :status], %{stage: 1}, %{})
```

**Monitor for 4 hours**:
- Check dashboard for migration telemetry events
- Verify no performance degradation
- Confirm baseline metrics stable

**Rollback if needed**:
```elixir
Foundation.FeatureFlags.disable(:enable_migration_monitoring)
```

### Stage 2: Registry Migration (Day 2)

```elixir
# Enable ETS-based registry
Foundation.FeatureFlags.enable(:use_ets_agent_registry)

# Verify operation
Foundation.Protocols.RegistryAny.list_agents()
# Should return agent list from ETS
```

**Validation Steps**:
1. Register test agent:
   ```elixir
   test_pid = spawn(fn -> Process.sleep(60_000) end)
   Foundation.Protocols.RegistryAny.register_agent(:test_migration, test_pid)
   ```

2. Verify retrieval:
   ```elixir
   {:ok, ^test_pid} = Foundation.Protocols.RegistryAny.get_agent(:test_migration)
   ```

3. Check ETS table:
   ```elixir
   :ets.info(:foundation_agent_registry)
   # Should show table statistics
   ```

**Monitor for 24 hours**:
- Registry operation latency < 5ms p99
- No "agent not found" errors increase
- Memory usage stable (ETS table < 10MB)

**Rollback if needed**:
```elixir
Foundation.FeatureFlags.disable(:use_ets_agent_registry)
# Agents will revert to Process dictionary
```

### Stage 3: Error Context Migration (Day 3)

```elixir
# Enable Logger metadata for error context
Foundation.FeatureFlags.enable(:use_logger_error_context)

# Test context propagation
Foundation.ErrorContext.set_context(%{request_id: "test-123"})
Logger.info("Test message")
# Should include error_context in metadata
```

**Validation Steps**:
1. Create nested context:
   ```elixir
   Foundation.ErrorContext.with_context(%{operation: "validation"}, fn ->
     Foundation.ErrorContext.with_context(%{step: "parse"}, fn ->
       Logger.error("Test error with context")
     end)
   end)
   ```

2. Verify in logs:
   ```bash
   grep "error_context" /var/log/app/current | tail -20
   ```

**Monitor for 24 hours**:
- Log entries include error context
- No context loss during error propagation
- Logger performance acceptable

**Rollback if needed**:
```elixir
Foundation.FeatureFlags.disable(:use_logger_error_context)
```

### Stage 4: Telemetry Migration (Days 4-5)

#### 4A: Span Management (Day 4)

```elixir
# Start span GenServer
{:ok, _} = Foundation.Telemetry.Span.start_link()

# Enable GenServer-based spans
Foundation.FeatureFlags.enable(:use_genserver_span_management)

# Test span creation
span_id = Foundation.Telemetry.Span.start_span("test_operation", %{user_id: 123})
Process.sleep(100)
Foundation.Telemetry.Span.end_span(span_id)
```

**Validation**:
- Telemetry events fired for span start/end
- Span duration metrics accurate
- No span stack corruption

#### 4B: Event Deduplication (Day 5)

```elixir
# Start sampled events GenServer
{:ok, _} = Foundation.Telemetry.SampledEvents.start_link()

# Enable ETS-based deduplication
Foundation.FeatureFlags.enable(:use_ets_sampled_events)

# Test deduplication
Foundation.Telemetry.SampledEvents.emit_event(
  [:test, :event],
  %{count: 1},
  %{dedup_key: "test-123"}
)
```

**Monitor both telemetry components**:
- Event throughput maintained
- Deduplication working (no duplicate events)
- Batch processing on schedule
- Memory usage bounded

**Rollback if needed**:
```elixir
Foundation.FeatureFlags.disable(:use_genserver_span_management)
Foundation.FeatureFlags.disable(:use_ets_sampled_events)
```

### Stage 5: Full Enforcement (Day 8)

```elixir
# Enable all OTP patterns
Foundation.FeatureFlags.set(:use_ets_agent_registry, true)
Foundation.FeatureFlags.set(:use_logger_error_context, true)
Foundation.FeatureFlags.set(:use_genserver_telemetry, true)
Foundation.FeatureFlags.set(:use_genserver_span_management, true)
Foundation.FeatureFlags.set(:use_ets_sampled_events, true)

# Enable strict enforcement
Foundation.FeatureFlags.enable(:enforce_no_process_dict)
```

**Final Validation**:
1. Run integration test suite:
   ```bash
   mix test test/foundation/otp_cleanup_integration_test.exs
   ```

2. Check for Process dictionary usage:
   ```bash
   mix credo --strict
   # Should show 0 Process dictionary warnings
   ```

3. Performance validation:
   ```elixir
   Foundation.OTPCleanup.Benchmarks.run_all()
   # Compare with baseline metrics
   ```

## Monitoring During Migration

### Key Metrics to Watch

1. **System Health**
   ```elixir
   %{
     registry_size: length(Foundation.Protocols.RegistryAny.list_agents()),
     error_rate: ErrorTracker.rate_per_minute(),
     memory_usage: :erlang.memory(:ets),
     process_count: length(Process.list())
   }
   ```

2. **Performance Metrics**
   - Registry lookup latency (target: < 5ms p99)
   - Error context overhead (target: < 100μs)
   - Telemetry throughput (target: > 10k events/sec)
   - Memory growth rate (target: < 1MB/hour)

3. **Error Patterns**
   - Watch for "undefined function" errors
   - Monitor for ETS table not found errors
   - Check for GenServer timeout errors

### Alert Thresholds

Configure alerts for:
- Registry lookup latency > 10ms (p99)
- Error rate increase > 20%
- Memory usage > 500MB for ETS
- Process count increase > 50%

## Rollback Procedures

### Emergency Rollback (All Stages)

```elixir
# Disable all OTP features immediately
Foundation.OTPCleanup.emergency_rollback!()

# Verify rollback
Foundation.FeatureFlags.all()
|> Enum.filter(fn {k, v} -> String.contains?(to_string(k), "otp") end)
# All should be false
```

### Selective Rollback

For specific component issues:

```elixir
# Registry issues
Foundation.FeatureFlags.disable(:use_ets_agent_registry)

# Error context issues  
Foundation.FeatureFlags.disable(:use_logger_error_context)

# Telemetry issues
Foundation.FeatureFlags.disable(:use_genserver_telemetry)
Foundation.FeatureFlags.disable(:use_ets_sampled_events)
```

### Data Recovery

If ETS tables are corrupted:

```elixir
# Backup current state
Foundation.OTPCleanup.backup_ets_tables("/tmp/ets_backup")

# Clear and rebuild
Foundation.OTPCleanup.rebuild_ets_tables()

# Restore if needed
Foundation.OTPCleanup.restore_ets_tables("/tmp/ets_backup")
```

## Troubleshooting Guide

### Common Issues and Solutions

#### 1. "ETS table not found" errors
```elixir
# Check if table exists
:ets.whereis(:foundation_agent_registry)

# Recreate if missing
Foundation.Protocols.RegistryAny.ensure_table_exists()
```

#### 2. High memory usage from ETS
```elixir
# Check table sizes
:ets.all()
|> Enum.map(fn table -> {:ets.info(table, :name), :ets.info(table, :memory)} end)
|> Enum.sort_by(&elem(&1, 1), :desc)

# Clear stale entries
Foundation.OTPCleanup.cleanup_ets_tables()
```

#### 3. Logger metadata not propagating
```elixir
# Verify Logger configuration
Application.get_env(:logger, :metadata)
# Should include :error_context

# Check current metadata
Logger.metadata()
```

#### 4. GenServer timeouts
```elixir
# Increase timeout for heavy load
Application.put_env(:foundation, :span_genserver_timeout, 10_000)

# Check GenServer state
:sys.get_state(Foundation.Telemetry.Span)
```

### Debug Commands

```elixir
# Full system diagnostic
Foundation.OTPCleanup.Diagnostics.run_all()

# Component-specific checks
Foundation.OTPCleanup.Diagnostics.check_registry()
Foundation.OTPCleanup.Diagnostics.check_error_context()
Foundation.OTPCleanup.Diagnostics.check_telemetry()

# Generate diagnostic report
Foundation.OTPCleanup.Diagnostics.generate_report("/tmp/otp_diagnostic.html")
```

## Post-Migration Tasks

### 1. Remove Legacy Code (Day 10)
Once running stable for 48 hours:
```bash
# Remove Process dictionary code paths
mix otp_cleanup.remove_legacy

# Run tests to verify
mix test
```

### 2. Update Documentation
- Update API docs to reflect new patterns
- Remove Process dictionary examples
- Add OTP pattern examples

### 3. Team Training
- Conduct code review of new patterns
- Share performance impact analysis
- Document best practices

### 4. Metrics Analysis
```elixir
# Generate migration report
Foundation.OTPCleanup.Reports.generate_migration_summary(
  start_date: ~D[2025-07-01],
  end_date: ~D[2025-07-10]
)
```

## Contact Information

**On-Call Engineer**: Check PagerDuty  
**Migration Lead**: [Your Name]  
**Escalation Path**: 
1. On-call engineer
2. Platform team lead
3. CTO for emergency rollback approval

**Monitoring Dashboards**:
- System Health: https://monitoring/dashboards/foundation
- Migration Progress: https://monitoring/dashboards/otp-migration
- ETS Metrics: https://monitoring/dashboards/ets-usage

**Documentation**:
- Architecture Diagrams: `docsProcessRegistry/ARCHITECTURE.md`
- Developer Guide: `docsProcessRegistry/DEVELOPER_GUIDE.md`
- Migration Plan: `JULY_1_2025_OTP_CLEANUP_2121.md`