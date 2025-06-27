# Foundation OS Migration Guide
**Version 1.0 - Step-by-Step Migration from Current to Target Architecture**  
**Date: June 27, 2025**

## Executive Summary

This guide provides detailed, actionable steps for migrating from the current Foundation/MABEAM architecture to the new dependency-based, multi-agent platform. The migration prioritizes zero-downtime transitions, data preservation, and team productivity throughout the transformation.

**Migration Approach**: Incremental, backward-compatible transformation  
**Estimated Downtime**: Zero (rolling deployment)  
**Data Migration**: Automated with manual verification checkpoints  
**Rollback Time**: <30 minutes at any stage

## Pre-Migration Assessment

### Current System Inventory

Before beginning migration, conduct a comprehensive inventory of your current system:

```bash
# 1. Catalog existing foundation.mabeam usage
find . -name "*.ex" -exec grep -l "Foundation\.MABEAM\." {} \;

# 2. Identify agent implementations
find . -name "*.ex" -exec grep -l "Agent\." {} \;

# 3. Catalog custom coordination logic
find . -name "*.ex" -exec grep -l "Coordination\." {} \;

# 4. Identify error handling patterns
find . -name "*.ex" -exec grep -l "Error\." {} \;
```

### Compatibility Check

Run the pre-migration compatibility checker:

```elixir
# Add to mix.exs temporarily
{:foundation_migration_checker, "~> 0.1.0", only: [:dev]}

# Run compatibility check
mix foundation.check_migration_readiness
```

### Backup Procedures

**Critical**: Always backup before migration:

```bash
# 1. Code backup
git tag pre-migration-backup-$(date +%Y%m%d-%H%M%S)
git push origin --tags

# 2. Database backup (if applicable)
pg_dump your_database > pre_migration_backup.sql

# 3. Configuration backup
cp -r config/ config_backup/
```

---

## Phase 1: Foundation Purification Migration
**Target Completion: Week 1-4 of Implementation Roadmap**

### Step 1.1: Add Jido Dependencies

```elixir
# mix.exs - Add these dependencies
defp deps do
  [
    # ... existing dependencies ...
    
    # Jido ecosystem
    {:jido, "~> 0.1.0"},
    {:jido_action, "~> 0.1.0"},
    {:jido_signal, "~> 0.1.0"},
    
    # Migration helpers (temporary)
    {:foundation_migration_tools, "~> 0.1.0", only: [:dev]}
  ]
end
```

```bash
# Install dependencies
mix deps.get
mix deps.compile

# Verify compilation
mix compile --warnings-as-errors
```

### Step 1.2: Error System Migration

**Automated Migration Script**:

```elixir
# Run the error migration script
mix foundation.migrate.errors

# Manual verification
find lib/ -name "*.ex" -exec grep -l "EnhancedError" {} \;
# Should return empty after migration
```

**Manual Error Migration** (if automated script unavailable):

```elixir
# Before: lib/your_module.ex
defmodule YourModule do
  alias Foundation.Types.EnhancedError
  
  def some_function do
    {:error, EnhancedError.new(:validation_failed, "Invalid input")}
  end
end

# After: lib/your_module.ex
defmodule YourModule do
  alias Foundation.Types.Error
  
  def some_function do
    {:error, Error.new(:validation_failed, "Invalid input")}
  end
end
```

### Step 1.3: Deprecate foundation.mabeam Usage

**Automated Deprecation Script**:

```bash
# Run deprecation markers
mix foundation.deprecate.mabeam

# This will:
# 1. Add @deprecated to all foundation.mabeam functions
# 2. Add compiler warnings
# 3. Generate migration notices
```

**Manual Deprecation Pattern**:

```elixir
# Before: lib/foundation/mabeam/agent.ex
defmodule Foundation.MABEAM.Agent do
  def register_agent(config) do
    # ... implementation
  end
end

# After: lib/foundation/mabeam/agent.ex
defmodule Foundation.MABEAM.Agent do
  @deprecated "Use FoundationJido.Agent.register_agent/1 instead"
  def register_agent(config) do
    IO.warn("Foundation.MABEAM.Agent.register_agent/1 is deprecated. " <>
            "Use FoundationJido.Agent.register_agent/1 instead.")
    # ... existing implementation (unchanged)
  end
end
```

### Step 1.4: Update Existing Code (Gradual)

**Create Migration Helpers**:

```elixir
# lib/migration_helpers.ex (temporary file)
defmodule MigrationHelpers do
  @moduledoc """
  Temporary helpers for smooth migration.
  Remove after migration complete.
  """
  
  def bridge_agent_registration(config) do
    # Bridge old calls to new system
    case foundation_jido_available?() do
      true -> FoundationJido.Agent.register_agent(config)
      false -> Foundation.MABEAM.Agent.register_agent(config)
    end
  end
  
  defp foundation_jido_available? do
    Code.ensure_loaded?(FoundationJido.Agent)
  end
end
```

**Update Client Code Gradually**:

```elixir
# Before: lib/your_agent.ex
defmodule YourAgent do
  def start do
    Foundation.MABEAM.Agent.register_agent(%{...})
  end
end

# During Migration: lib/your_agent.ex  
defmodule YourAgent do
  def start do
    MigrationHelpers.bridge_agent_registration(%{...})
  end
end

# After Migration: lib/your_agent.ex
defmodule YourAgent do
  def start do
    FoundationJido.Agent.register_agent(%{...})
  end
end
```

### Phase 1 Verification

```bash
# 1. All tests pass
mix test

# 2. No compilation warnings
mix compile --warnings-as-errors

# 3. Deprecation warnings present
mix compile 2>&1 | grep "deprecated"

# 4. System functional
mix foundation.health_check
```

---

## Phase 2: Integration Layer Migration
**Target Completion: Week 5-9 of Implementation Roadmap**

### Step 2.1: Create FoundationJido Structure

```bash
# Create integration layer directories
mkdir -p lib/foundation_jido/{agent,signal,action,coordination}
mkdir -p test/foundation_jido/{agent,signal,action,coordination}
```

### Step 2.2: Migrate Agent Registration

**Create New Agent Registry Adapter**:

```elixir
# lib/foundation_jido/agent/registry_adapter.ex
defmodule FoundationJido.Agent.RegistryAdapter do
  @moduledoc """
  Bridges Jido agents with Foundation.ProcessRegistry
  """
  
  alias Foundation.ProcessRegistry
  alias Foundation.Types.Error
  
  def register_agent(config) do
    with {:ok, metadata} <- build_agent_metadata(config),
         {:ok, pid} <- start_jido_agent(config),
         {:ok, _} <- ProcessRegistry.register(pid, metadata) do
      {:ok, pid}
    else
      {:error, reason} -> {:error, Error.new(:agent_registration_failed, reason)}
    end
  end
  
  defp build_agent_metadata(config) do
    # Convert Jido agent config to Foundation metadata format
    metadata = %{
      type: :agent,
      capabilities: Map.get(config, :capabilities, []),
      name: Map.get(config, :name),
      restart_policy: Map.get(config, :restart_policy, :permanent)
    }
    {:ok, metadata}
  end
  
  defp start_jido_agent(config) do
    # Start Jido agent with Foundation integration
    Jido.Agent.start_link(config)
  end
end
```

### Step 2.3: Create Signal Integration

**JidoSignal to Foundation Bridge**:

```elixir
# lib/foundation_jido/signal/foundation_dispatch.ex
defmodule FoundationJido.Signal.FoundationDispatch do
  @moduledoc """
  JidoSignal dispatch adapter using Foundation services
  """
  
  alias Foundation.Infrastructure.CircuitBreaker
  alias Foundation.Telemetry
  alias Foundation.Types.Error
  
  def dispatch(signal, adapter_config) do
    Telemetry.execute([:signal, :dispatch, :start], %{}, %{signal: signal})
    
    result = case adapter_config.type do
      :http -> dispatch_http(signal, adapter_config)
      :pid -> dispatch_pid(signal, adapter_config)
      _ -> {:error, Error.new(:unsupported_adapter, adapter_config.type)}
    end
    
    Telemetry.execute([:signal, :dispatch, :complete], %{}, %{
      signal: signal,
      result: result
    })
    
    result
  end
  
  defp dispatch_http(signal, config) do
    CircuitBreaker.execute(:signal_http, fn ->
      # Use Foundation's circuit breaker for HTTP calls
      JidoSignal.Dispatch.HttpAdapter.dispatch(signal, config)
    end)
  end
  
  defp dispatch_pid(signal, config) do
    # Use Foundation's process registry for PID lookups
    case Foundation.ProcessRegistry.lookup(config.target) do
      {:ok, pid} -> JidoSignal.Dispatch.PidAdapter.dispatch(signal, %{config | target: pid})
      {:error, reason} -> {:error, Error.new(:target_not_found, reason)}
    end
  end
end
```

### Step 2.4: Migrate Coordination Logic

**Move Auction Logic**:

```bash
# Move coordination modules
mv lib/foundation/mabeam/coordination/ lib/foundation_jido/coordination/

# Update module names
sed -i 's/Foundation\.MABEAM\.Coordination/FoundationJido.Coordination/g' \
  lib/foundation_jido/coordination/*.ex
```

**Refactor for Jido Integration**:

```elixir
# lib/foundation_jido/coordination/auction.ex
defmodule FoundationJido.Coordination.Auction do
  @moduledoc """
  Economic auction protocols for multi-agent coordination
  Migrated from Foundation.MABEAM.Coordination.Auction
  """
  
  alias FoundationJido.Agent.RegistryAdapter
  alias Foundation.Types.Error
  
  def run_auction(auction_spec, participants) do
    with {:ok, agents} <- resolve_participants(participants),
         {:ok, bids} <- collect_bids(agents, auction_spec),
         {:ok, winner} <- select_winner(bids, auction_spec) do
      notify_auction_result(participants, winner)
    else
      {:error, reason} -> {:error, Error.new(:auction_failed, reason)}
    end
  end
  
  defp resolve_participants(participant_specs) do
    # Use FoundationJido registry to resolve agent references
    Enum.reduce_while(participant_specs, {:ok, []}, fn spec, {:ok, acc} ->
      case RegistryAdapter.lookup_agent(spec) do
        {:ok, agent} -> {:cont, {:ok, [agent | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
  
  # ... rest of implementation
end
```

### Step 2.5: Create Migration Bridge

**Temporary Compatibility Layer**:

```elixir
# lib/foundation_jido/migration_bridge.ex
defmodule FoundationJido.MigrationBridge do
  @moduledoc """
  Temporary bridge for smooth migration.
  Provides backward compatibility during transition period.
  """
  
  # Delegate old calls to new implementations
  defdelegate register_agent(config), to: FoundationJido.Agent.RegistryAdapter
  defdelegate run_auction(spec, participants), to: FoundationJido.Coordination.Auction
  
  # Add logging for migration tracking
  def track_migration_call(function_name, args) do
    Foundation.Telemetry.execute([:migration, :bridge_call], %{count: 1}, %{
      function: function_name,
      args: inspect(args)
    })
  end
end
```

### Phase 2 Verification

```bash
# 1. Integration tests pass
mix test test/foundation_jido/

# 2. Bridge functionality works
mix foundation.test_bridge

# 3. Performance acceptable
mix foundation.benchmark_integration

# 4. Memory usage stable
mix foundation.memory_check
```

---

## Phase 3: DSPEx Enhancement Migration
**Target Completion: Week 10-13 of Implementation Roadmap**

### Step 3.1: Create DSPEx-Jido Bridge

**Program as Agent Wrapper**:

```elixir
# lib/dspex/jido/program_agent.ex
defmodule DSPEx.Jido.ProgramAgent do
  @moduledoc """
  Wraps DSPEx.Program as a Jido agent
  """
  
  use Jido.Agent,
    name: "dspex_program",
    schema: [
      program: [type: :any, required: true],
      optimization_state: [type: :map, default: %{}]
    ]
  
  alias DSPEx.Program
  alias FoundationJido.Agent.RegistryAdapter
  
  def mount(state, opts) do
    program = Keyword.fetch!(opts, :program)
    
    # Register as agent with ML capabilities
    {:ok, _} = RegistryAdapter.register_agent(%{
      name: Program.get_name(program),
      capabilities: [:ml_optimization, :program_execution],
      restart_policy: :permanent
    })
    
    {:ok, %{state | program: program}}
  end
  
  def handle_instruction(%{action: "run_program", params: params}, state) do
    result = Program.run(state.program, params)
    {:ok, %{result: result}, state}
  end
  
  def handle_instruction(%{action: "optimize", params: params}, state) do
    # Use DSPEx teleprompters for optimization
    optimized_program = DSPEx.Teleprompter.SIMBA.optimize(
      state.program, 
      params.training_data,
      params.options
    )
    
    {:ok, %{optimized: true}, %{state | program: optimized_program}}
  end
end
```

### Step 3.2: Create ML Action Library

**Optimization Actions**:

```elixir
# lib/dspex/jido/teleprompter_actions.ex
defmodule DSPEx.Jido.TeleprompterActions do
  @moduledoc """
  DSPEx optimization as Jido actions
  """
  
  defmodule OptimizeProgram do
    use JidoAction.Action,
      name: "optimize_program",
      description: "Optimize a DSPEx program using teleprompters"
    
    alias DSPEx.Teleprompter
    alias Foundation.Types.Error
    
    def run(params, context) do
      with {:ok, program} <- validate_program(params.program),
           {:ok, training_data} <- validate_training_data(params.training_data),
           {:ok, optimized} <- run_optimization(program, training_data, params.options) do
        {:ok, %{optimized_program: optimized}, context}
      else
        {:error, reason} -> {:error, Error.new(:optimization_failed, reason)}
      end
    end
    
    defp run_optimization(program, training_data, options) do
      strategy = Map.get(options, :strategy, :simba)
      
      case strategy do
        :simba -> Teleprompter.SIMBA.optimize(program, training_data, options)
        :beacon -> Teleprompter.BEACON.optimize(program, training_data, options)
        _ -> {:error, "Unknown optimization strategy: #{strategy}"}
      end
    end
    
    # ... validation helpers
  end
end
```

### Step 3.3: Multi-Agent Coordination

**Variable-Aware Coordination**:

```elixir
# lib/dspex/jido/coordination_bridge.ex
defmodule DSPEx.Jido.CoordinationBridge do
  @moduledoc """
  Bridge DSPEx variable system with multi-agent coordination
  """
  
  alias DSPEx.Variable
  alias FoundationJido.Coordination
  alias Foundation.Types.Error
  
  def coordinate_optimization(programs, shared_variables, options \\ []) do
    with {:ok, agent_specs} <- programs_to_agent_specs(programs),
         {:ok, coordination_spec} <- build_coordination_spec(shared_variables, options),
         {:ok, result} <- Coordination.Orchestrator.coordinate(agent_specs, coordination_spec) do
      extract_optimization_results(result)
    else
      {:error, reason} -> {:error, Error.new(:coordination_failed, reason)}
    end
  end
  
  defp programs_to_agent_specs(programs) do
    specs = Enum.map(programs, fn program ->
      %{
        agent_type: DSPEx.Jido.ProgramAgent,
        config: %{program: program},
        capabilities: Variable.Space.get_capabilities(program.variable_space)
      }
    end)
    {:ok, specs}
  end
  
  defp build_coordination_spec(shared_variables, options) do
    spec = %{
      coordination_type: Map.get(options, :coordination_type, :auction),
      shared_resources: Variable.Space.get_shared_resources(shared_variables),
      optimization_target: Map.get(options, :target, :maximize_performance)
    }
    {:ok, spec}
  end
  
  # ... rest of implementation
end
```

### Phase 3 Verification

```bash
# 1. DSPEx programs run as agents
mix test test/dspex/jido/

# 2. Multi-agent optimization works
mix dspex.test_multi_agent_optimization

# 3. Variable coordination functional
mix dspex.test_variable_coordination

# 4. Performance benchmarks met
mix dspex.benchmark_multi_agent
```

---

## Phase 4: Production Migration
**Target Completion: Week 14-16 of Implementation Roadmap**

### Step 4.1: Environment Preparation

**Staging Environment Setup**:

```bash
# 1. Create staging environment
terraform apply -var-file=staging.tfvars

# 2. Deploy current system to staging
mix deploy staging

# 3. Verify staging system health
mix foundation.health_check --env=staging
```

### Step 4.2: Blue-Green Deployment

**Deployment Script**:

```bash
#!/bin/bash
# deploy_migration.sh

set -e

# 1. Deploy new system to green environment
echo "Deploying to green environment..."
mix deploy green --version=migration-v1.0

# 2. Run smoke tests
echo "Running smoke tests..."
mix foundation.smoke_test --env=green

# 3. Gradually shift traffic
echo "Starting traffic shift..."
for percent in 10 25 50 75 100; do
  echo "Shifting $percent% traffic to green..."
  terraform apply -var="traffic_split=$percent"
  sleep 300  # Wait 5 minutes
  
  # Check health metrics
  if ! mix foundation.health_check --env=green; then
    echo "Health check failed! Rolling back..."
    terraform apply -var="traffic_split=0"
    exit 1
  fi
done

echo "Migration complete!"
```

### Step 4.3: Data Migration

**Agent State Migration**:

```elixir
# lib/migration/agent_state_migrator.ex
defmodule Migration.AgentStateMigrator do
  @moduledoc """
  Migrates agent state from old foundation.mabeam to new FoundationJido
  """
  
  def migrate_all_agents do
    with {:ok, old_agents} <- fetch_old_agent_states(),
         {:ok, migration_plan} <- build_migration_plan(old_agents),
         {:ok, results} <- execute_migration(migration_plan) do
      verify_migration(results)
    end
  end
  
  defp fetch_old_agent_states do
    # Extract state from old Foundation.MABEAM.ProcessRegistry
    Foundation.MABEAM.ProcessRegistry.list_all_agents()
  end
  
  defp build_migration_plan(agents) do
    plan = Enum.map(agents, fn agent ->
      %{
        old_state: agent,
        new_config: convert_to_jido_config(agent),
        migration_strategy: determine_strategy(agent)
      }
    end)
    {:ok, plan}
  end
  
  defp execute_migration(plan) do
    Enum.reduce_while(plan, {:ok, []}, fn item, {:ok, acc} ->
      case migrate_single_agent(item) do
        {:ok, result} -> {:cont, {:ok, [result | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
  
  # ... rest of implementation
end
```

### Step 4.4: Cleanup and Verification

**Remove Migration Helpers**:

```bash
# 1. Remove temporary files
rm lib/migration_helpers.ex
rm lib/foundation_jido/migration_bridge.ex

# 2. Remove deprecated modules
rm -rf lib/foundation/mabeam/

# 3. Update dependencies
# Remove {:foundation_migration_tools, ...} from mix.exs

# 4. Run final verification
mix foundation.verify_migration_complete
```

### Phase 4 Verification

```bash
# 1. All systems operational
mix foundation.health_check --env=production

# 2. No deprecated code in use
mix foundation.check_deprecated_usage

# 3. Performance targets met
mix foundation.benchmark_production

# 4. Error rates normal
mix foundation.check_error_rates
```

---

## Rollback Procedures

### Emergency Rollback (< 5 minutes)

```bash
# 1. Immediate traffic rollback
terraform apply -var="traffic_split=0"

# 2. Verify old system health  
mix foundation.health_check --env=blue

# 3. Notify team
mix foundation.notify_rollback "Emergency rollback executed"
```

### Planned Rollback (< 30 minutes)

```bash
# 1. Graceful agent shutdown
mix foundation.graceful_shutdown --timeout=300

# 2. Restore from backup
mix foundation.restore_from_backup --backup=pre-migration

# 3. Verify system state
mix foundation.verify_rollback_complete

# 4. Resume operations
mix foundation.start_all_services
```

## Post-Migration Validation

### Week 1 After Migration

```bash
# Daily health checks
mix foundation.health_check --detailed

# Performance monitoring
mix foundation.performance_report --days=7

# Error rate analysis
mix foundation.error_analysis --days=7
```

### Week 2-4 After Migration

```bash
# Weekly comprehensive review
mix foundation.migration_success_report --weeks=1

# Optimization opportunities
mix foundation.optimization_analysis

# Team feedback collection
mix foundation.collect_team_feedback
```

## Troubleshooting Guide

### Common Issues

**Issue 1: Agent Registration Failures**
```bash
# Symptom: Agents fail to register with new system
# Check: Registry service health
mix foundation.check_registry_health

# Solution: Restart registry service
mix foundation.restart_service ProcessRegistry
```

**Issue 2: Signal Dispatch Timeouts**
```bash
# Symptom: JidoSignal dispatches timing out
# Check: Circuit breaker status
mix foundation.check_circuit_breakers

# Solution: Reset circuit breakers
mix foundation.reset_circuit_breaker :signal_http
```

**Issue 3: Performance Degradation**
```bash
# Symptom: Response times increased after migration
# Check: Integration layer overhead
mix foundation.profile_integration_layer

# Solution: Optimize hot paths
mix foundation.optimize_integration --profile=production
```

### Getting Help

1. **Internal Team**: Check team wiki and internal documentation
2. **Jido Community**: https://github.com/agentjido/jido/discussions
3. **Expert Consultation**: Engage with Jido maintainers if needed
4. **Emergency Support**: Use established incident response procedures

## Conclusion

This migration guide provides a comprehensive, step-by-step approach to transforming your Foundation/MABEAM system into a world-class multi-agent platform. The incremental approach minimizes risk while ensuring system stability throughout the transition.

**Key Success Factors**:
- Follow the phases in order
- Verify each step before proceeding
- Maintain comprehensive backups
- Monitor system health continuously
- Have rollback procedures ready

**Post-Migration Benefits**:
- Clean, maintainable architecture
- Better separation of concerns
- Improved development velocity
- Production-ready observability
- Future-proof foundation for growth

The result will be a robust, scalable platform capable of supporting sophisticated multi-agent workflows while maintaining the reliability and performance your team depends on.