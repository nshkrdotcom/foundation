# OTP Cleanup Migration Runbook

This runbook provides step-by-step procedures for executing the OTP cleanup migration using the Feature Flag system. It enables safe, gradual transition from Process dictionary to OTP patterns with rollback capability.

## Overview

The migration consists of 4 stages, each introducing incremental changes with reduced risk:

1. **Stage 1** - Registry Migration (Low Risk)
2. **Stage 2** - Error Context Migration (Medium Risk)  
3. **Stage 3** - Telemetry Migration (High Risk)
4. **Stage 4** - Enforcement (Critical Risk)

## Prerequisites

### Before Starting Migration

1. **System Health Check**
   ```elixir
   # Verify system is healthy
   Foundation.MigrationControl.status()
   
   # Check readiness for migration
   Foundation.MigrationControl.validate_readiness_for_stage(1)
   ```

2. **Backup Current State**
   ```bash
   # Backup database/persistent state if applicable
   pg_dump production_db > backup_$(date +%Y%m%d_%H%M).sql
   ```

3. **Team Notification**
   - Notify development team
   - Ensure rollback person is available
   - Set up monitoring alerts

4. **Testing Prerequisites**
   ```bash
   # Ensure all tests pass
   mix test
   
   # Run credo checks
   mix credo
   
   # Verify no compilation warnings
   mix compile --warnings-as-errors
   ```

## Migration Stages

### Stage 1: Registry Migration (Low Risk)

**What it does**: Switches from Process dictionary to ETS-based agent registry.

**Flags enabled**:
- `use_ets_agent_registry`
- `enable_migration_monitoring`

**Execution**:
```elixir
# 1. Validate readiness
Foundation.MigrationControl.validate_readiness_for_stage(1)

# 2. Execute migration
{:ok, result} = Foundation.MigrationControl.migrate_to_stage(1)

# 3. Verify migration
status = Foundation.MigrationControl.status()
IO.inspect(status, label: "Stage 1 Status")
```

**Monitoring Checklist**:
- [ ] Error rate remains < 1%
- [ ] No registry lookup failures
- [ ] Agent registration working normally
- [ ] ETS memory usage within normal bounds

**Success Criteria**:
- All agent operations work normally
- No increase in error rates
- Registry lookups succeed consistently

**Duration**: Monitor for 30 minutes

### Stage 2: Error Context Migration (Medium Risk)

**What it does**: Switches from Process dictionary to Logger metadata for error context.

**Flags enabled**:
- `use_logger_error_context`

**Execution**:
```elixir
# 1. Validate readiness (must be at stage 1)
Foundation.MigrationControl.validate_readiness_for_stage(2)

# 2. Execute migration
{:ok, result} = Foundation.MigrationControl.migrate_to_stage(2)

# 3. Verify error context works
Foundation.ErrorContext.set_context(%{test: "migration_test"})
context = Foundation.ErrorContext.get_context()
Logger.metadata() |> IO.inspect(label: "Logger Metadata")
```

**Monitoring Checklist**:
- [ ] Error context properly stored in Logger metadata
- [ ] Error enrichment working correctly
- [ ] No context loss during process transitions
- [ ] Structured logging includes context

**Success Criteria**:
- Error context visible in all log messages
- Context propagation works across processes
- No context-related errors

**Duration**: Monitor for 2 hours

### Stage 3: Telemetry Migration (High Risk)

**What it does**: Switches from Process dictionary to GenServer/ETS for telemetry operations.

**Flags enabled**:
- `use_genserver_telemetry`
- `use_genserver_span_management`
- `use_ets_sampled_events`

**Execution**:
```elixir
# 1. Validate readiness (must be at stage 2)
Foundation.MigrationControl.validate_readiness_for_stage(3)

# 2. Execute migration
{:ok, result} = Foundation.MigrationControl.migrate_to_stage(3)

# 3. Verify telemetry works
Foundation.Telemetry.Span.with_span(:test_span, %{test: true}) do
  Foundation.Telemetry.SampledEvents.emit_event([:test], %{count: 1}, %{source: "migration_test"})
  :ok
end
```

**Monitoring Checklist**:
- [ ] Span stack management working correctly
- [ ] No span leaks or orphaned spans
- [ ] Event deduplication functioning
- [ ] Telemetry performance acceptable
- [ ] SpanManager GenServer stable

**Success Criteria**:
- All span operations work correctly
- No telemetry data loss
- Performance impact < 10%
- SpanManager process stable

**Duration**: Monitor for 4 hours

### Stage 4: Enforcement (Critical Risk)

**What it does**: Enables strict checking to prevent Process dictionary usage.

**Flags enabled**:
- `enforce_no_process_dict`

**Execution**:
```elixir
# 1. Validate readiness (must be at stage 3)
Foundation.MigrationControl.validate_readiness_for_stage(4)

# 2. Execute migration
{:ok, result} = Foundation.MigrationControl.migrate_to_stage(4)

# 3. Run comprehensive tests
System.cmd("mix", ["test"])
System.cmd("mix", ["credo"])
```

**Monitoring Checklist**:
- [ ] No Process dictionary violations detected
- [ ] All tests passing
- [ ] Credo checks clean
- [ ] No runtime errors from enforcement

**Success Criteria**:
- Zero Process dictionary usage violations
- All systems functioning normally
- Clean code quality checks

**Duration**: Monitor for 24 hours

## Rollback Procedures

### Automatic Rollback

The system automatically rolls back if:
- Error rate > 5%
- Restart frequency > 10/minute
- Response time degradation > 2x baseline

```elixir
# Check if automatic rollback triggered
{:rollback_triggered, violations} = Foundation.MigrationControl.check_health_and_rollback()
```

### Manual Rollback

#### Quick Rollback to Previous Stage
```elixir
# Rollback one stage
Foundation.MigrationControl.rollback_to_stage(current_stage - 1)
```

#### Emergency Rollback (All Stages)
```elixir
# Complete rollback to stage 0
Foundation.MigrationControl.emergency_rollback("Reason for rollback")
```

#### Command Line Emergency Rollback
```bash
# If system is unresponsive
./bin/foundation remote_console <<EOF
Foundation.MigrationControl.emergency_rollback("System unresponsive")
EOF
```

### Rollback Verification

After rollback, verify system health:
```elixir
# Check migration status
status = Foundation.MigrationControl.status()
IO.inspect(status.current_stage, label: "Current Stage")

# Verify system health
health = Foundation.MigrationControl.check_health_and_rollback()
IO.inspect(health, label: "System Health")

# Check all services
Foundation.Services.Supervisor.which_services()
```

## Monitoring and Alerts

### Key Metrics to Monitor

1. **Error Rates**
   ```elixir
   # Get current error rate
   status = Foundation.MigrationControl.status()
   status.system_health.error_rate
   ```

2. **Performance Impact**
   ```elixir
   # Get performance metrics
   metrics = Foundation.MigrationControl.metrics()
   metrics.performance_impact
   ```

3. **Feature Flag Usage**
   ```elixir
   # Monitor flag state
   Foundation.FeatureFlags.list_all()
   ```

### Telemetry Events

The system emits telemetry events for monitoring:
- `[:foundation, :migration, :stage_enabled]`
- `[:foundation, :migration, :rollback]`
- `[:foundation, :migration, :emergency_rollback]`
- `[:foundation, :feature_flag, :changed]`

### Health Monitoring

Enable continuous health monitoring:
```elixir
# Start health monitoring (checks every 30 seconds)
Foundation.MigrationControl.start_health_monitoring(30_000)
```

## Troubleshooting

### Common Issues

#### 1. Agent Registry Issues (Stage 1)
**Symptoms**: Agent registration/lookup failures
**Solution**:
```elixir
# Check ETS table status
Foundation.Protocols.RegistryETS.status()

# Restart registry if needed
Supervisor.restart_child(Foundation.Services.Supervisor, Foundation.Protocols.RegistryETS)
```

#### 2. Error Context Missing (Stage 2)
**Symptoms**: Error context not in logs
**Solution**:
```elixir
# Check Logger metadata
Logger.metadata() |> IO.inspect()

# Verify flag is enabled
Foundation.FeatureFlags.enabled?(:use_logger_error_context)
```

#### 3. Span Stack Issues (Stage 3)
**Symptoms**: Span warnings, memory leaks
**Solution**:
```elixir
# Check SpanManager status
Foundation.Telemetry.SpanManager.get_stack()

# Restart SpanManager if needed
Supervisor.restart_child(Foundation.Services.Supervisor, Foundation.Telemetry.SpanManager)
```

#### 4. Process Dictionary Violations (Stage 4)
**Symptoms**: Credo warnings, runtime errors
**Solution**:
```bash
# Find violations
grep -r "Process\.put\|Process\.get" lib/ --include="*.ex"

# Run credo check
mix credo --strict
```

### Emergency Procedures

#### System Unresponsive
1. Connect to remote console
2. Execute emergency rollback
3. Restart application if needed
4. Verify system recovery

#### Data Loss Concerns
1. Immediate emergency rollback
2. Check data integrity
3. Restore from backup if needed
4. Investigate root cause

#### Performance Degradation
1. Check system health metrics
2. Consider partial rollback
3. Monitor resource usage
4. Scale if necessary

## Post-Migration

### After Each Stage

1. **Update Documentation**
   - Record lessons learned
   - Update monitoring dashboards
   - Document any issues encountered

2. **Performance Analysis**
   ```elixir
   # Generate performance report
   metrics = Foundation.MigrationControl.metrics()
   
   # Check for regressions
   Foundation.MigrationControl.status().system_health
   ```

3. **Team Communication**
   - Notify team of successful migration
   - Share any observations
   - Plan next stage if applicable

### After Complete Migration (Stage 4)

1. **Remove Legacy Code** (after 1 week stable)
   - Delete Process dictionary fallback code
   - Remove temporary compatibility layers
   - Clean up unused modules

2. **Update CI/CD**
   ```bash
   # Enable strict Process dictionary checking
   grep -r "Process\.put\|Process\.get" lib/ --include="*.ex" && exit 1
   ```

3. **Documentation Updates**
   - Update architecture diagrams
   - Revise API documentation
   - Update operational runbooks

4. **Celebrate Success! 🎉**
   - The system is now fully OTP-compliant
   - Performance and reliability improved
   - Technical debt eliminated

## Configuration

### Feature Flag Configuration

Set default flags in `config/config.exs`:
```elixir
config :foundation, :feature_flags, %{
  use_ets_agent_registry: false,
  use_logger_error_context: false,
  use_genserver_telemetry: false,
  use_genserver_span_management: false,
  use_ets_sampled_events: false,
  enforce_no_process_dict: false,
  enable_migration_monitoring: false
}
```

### Environment-Specific Settings

```elixir
# config/prod.exs - Start with conservative settings
config :foundation, :feature_flags, %{
  enable_migration_monitoring: true
}

# config/staging.exs - Can be more aggressive
config :foundation, :feature_flags, %{
  use_ets_agent_registry: true,
  use_logger_error_context: true,
  enable_migration_monitoring: true
}
```

## Support Contacts

- **Development Team**: development@company.com
- **Operations Team**: ops@company.com
- **On-call Engineer**: +1-555-ON-CALL

## Appendix

### Useful Commands

```elixir
# Quick status check
Foundation.MigrationControl.status() |> Map.take([:current_stage, :flags])

# Full system health
Foundation.MigrationControl.status().system_health

# Migration history
Foundation.MigrationControl.status().migration_history |> Enum.take(5)

# Flag status
Foundation.FeatureFlags.list_all()

# Emergency rollback
Foundation.MigrationControl.emergency_rollback("Reason")
```

### Reference Links

- [OTP Cleanup Plan](JULY_1_2025_OTP_CLEANUP_2121.md)
- [Feature Flag Documentation](lib/foundation/feature_flags.ex)
- [Migration Control Documentation](lib/foundation/migration_control.ex)
- [Test Suite](test/foundation/feature_flags_test.exs)

---

**Remember**: This migration eliminates fundamental anti-patterns and aligns the system with 30+ years of battle-tested Erlang/OTP principles. Take your time, monitor carefully, and don't hesitate to rollback if anything looks suspicious.