# Foundation Perimeter Migration Guide

## Overview

This guide provides step-by-step instructions for migrating existing Foundation/Jido systems to use Foundation Perimeter. It covers gradual adoption strategies, compatibility considerations, and migration patterns that minimize disruption to production systems.

## Migration Strategy

### Phased Approach

The migration follows a **four-phase approach** that aligns with Perimeter's zone architecture:

```
Phase 1: Foundation Infrastructure (Weeks 1-2)
├── Install Perimeter services
├── Configure basic validation
└── Establish monitoring

Phase 2: External Perimeter (Weeks 3-4)  
├── Migrate external APIs to Zone 1
├── Add external contract validation
└── Test with production traffic

Phase 3: Service Boundaries (Weeks 5-6)
├── Migrate Foundation services to Zone 2
├── Add strategic boundary validation
└── Optimize performance

Phase 4: Coupling Optimization (Weeks 7-8)
├── Enable Zone 3 productive coupling
├── Remove artificial boundaries
└── Achieve full performance benefits
```

## Pre-Migration Assessment

### Current System Analysis

Before starting migration, assess your current Foundation/Jido system:

```elixir
defmodule Foundation.Perimeter.Migration.Assessment do
  @moduledoc """
  Pre-migration assessment tool for Foundation systems.
  """
  
  def analyze_current_system do
    %{
      foundation_services: analyze_foundation_services(),
      jido_agents: analyze_jido_agents(),
      validation_patterns: analyze_validation_patterns(),
      performance_metrics: collect_performance_baseline(),
      integration_points: identify_integration_points(),
      risk_factors: assess_migration_risks()
    }
  end
  
  defp analyze_foundation_services do
    services = Foundation.Registry.list_all_services()
    
    Enum.map(services, fn {service_id, service_spec} ->
      %{
        id: service_id,
        type: service_spec.type,
        validation_complexity: estimate_validation_complexity(service_spec),
        external_interfaces: count_external_interfaces(service_spec),
        internal_dependencies: count_internal_dependencies(service_spec),
        migration_priority: determine_migration_priority(service_spec)
      }
    end)
  end
  
  defp analyze_jido_agents do
    agents = JidoSystem.list_agents()
    
    Enum.map(agents, fn agent ->
      %{
        id: agent.id,
        type: agent.type,
        capabilities: agent.capabilities,
        foundation_integration: analyze_foundation_integration(agent),
        validation_requirements: estimate_validation_requirements(agent),
        migration_complexity: estimate_migration_complexity(agent)
      }
    end)
  end
  
  defp analyze_validation_patterns do
    # Scan codebase for existing validation patterns
    modules = :code.all_loaded()
    |> Enum.filter(fn {module, _} -> 
      String.starts_with?(Atom.to_string(module), "Foundation") or
      String.starts_with?(Atom.to_string(module), "Jido")
    end)
    
    validation_patterns = Enum.reduce(modules, %{}, fn {module, _}, acc ->
      patterns = extract_validation_patterns(module)
      Map.put(acc, module, patterns)
    end)
    
    %{
      total_modules: length(modules),
      modules_with_validation: count_modules_with_validation(validation_patterns),
      validation_types: categorize_validation_types(validation_patterns),
      complexity_distribution: analyze_complexity_distribution(validation_patterns)
    }
  end
  
  defp collect_performance_baseline do
    # Collect current performance metrics for comparison
    %{
      average_request_time: Foundation.Metrics.get_average("request.duration"),
      validation_overhead: Foundation.Metrics.get_average("validation.overhead"),
      error_rates: Foundation.Metrics.get_rates("errors"),
      throughput: Foundation.Metrics.get_throughput(),
      memory_usage: :erlang.memory(:total),
      process_count: :erlang.system_info(:process_count)
    }
  end
  
  def generate_migration_plan(assessment) do
    %{
      high_priority_services: filter_high_priority(assessment.foundation_services),
      migration_phases: plan_migration_phases(assessment),
      risk_mitigation: plan_risk_mitigation(assessment.risk_factors),
      testing_strategy: plan_testing_strategy(assessment),
      rollback_strategy: plan_rollback_strategy(assessment),
      timeline_estimate: estimate_timeline(assessment)
    }
  end
end
```

### Compatibility Matrix

```elixir
defmodule Foundation.Perimeter.Migration.Compatibility do
  @moduledoc """
  Compatibility checking for Foundation Perimeter migration.
  """
  
  @foundation_versions [
    "1.0.0", "1.1.0", "1.2.0", "2.0.0"
  ]
  
  @jido_versions [
    "0.8.0", "0.9.0", "1.0.0"
  ]
  
  def check_compatibility do
    %{
      foundation_version: check_foundation_compatibility(),
      jido_version: check_jido_compatibility(),
      elixir_version: check_elixir_compatibility(),
      otp_version: check_otp_compatibility(),
      dependencies: check_dependency_compatibility(),
      custom_code: check_custom_code_compatibility()
    }
  end
  
  defp check_foundation_compatibility do
    current_version = Foundation.version()
    
    case Version.compare(current_version, "2.0.0") do
      :gt -> 
        %{status: :compatible, version: current_version}
      :eq ->
        %{status: :compatible, version: current_version}
      :lt ->
        %{
          status: :requires_upgrade,
          current: current_version,
          required: "2.0.0",
          upgrade_path: determine_upgrade_path(current_version, "2.0.0")
        }
    end
  end
  
  defp check_jido_compatibility do
    current_version = JidoSystem.version()
    
    case Version.compare(current_version, "1.0.0") do
      :gt -> 
        %{status: :compatible, version: current_version}
      :eq ->
        %{status: :compatible, version: current_version}
      :lt ->
        %{
          status: :requires_upgrade,
          current: current_version,
          required: "1.0.0",
          upgrade_path: determine_jido_upgrade_path(current_version)
        }
    end
  end
  
  defp check_custom_code_compatibility do
    # Scan for patterns that might conflict with Perimeter
    incompatible_patterns = [
      :direct_validation_calls,
      :hardcoded_type_checks,
      :bypassed_service_boundaries,
      :manual_error_handling
    ]
    
    found_patterns = scan_for_patterns(incompatible_patterns)
    
    %{
      status: if(Enum.empty?(found_patterns), do: :compatible, else: :requires_changes),
      incompatible_patterns: found_patterns,
      remediation_suggestions: suggest_remediations(found_patterns)
    }
  end
end
```

## Phase 1: Foundation Infrastructure

### Installing Perimeter Services

First, add Perimeter to your Foundation application:

```elixir
# mix.exs
defp deps do
  [
    # Existing dependencies...
    {:foundation_perimeter, "~> 1.0"},
    {:stream_data, "~> 0.5", only: [:test]},  # For property-based testing
  ]
end
```

### Enhanced Application Structure

```elixir
# lib/foundation/application.ex
defmodule Foundation.Application do
  use Application
  
  def start(_type, _args) do
    # Determine if Perimeter should be enabled
    perimeter_enabled = Application.get_env(:foundation, :perimeter_enabled, false)
    
    children = base_children() ++ perimeter_children(perimeter_enabled)
    
    opts = [strategy: :one_for_one, name: Foundation.Supervisor]
    Supervisor.start_link(children, opts)
  end
  
  defp base_children do
    [
      {Foundation.Registry, []},
      {Foundation.Telemetry, []},
      {Foundation.Coordination, []},
      {Foundation.MABEAM.Supervisor, []}
    ]
  end
  
  defp perimeter_children(true) do
    [
      {Foundation.Perimeter.ValidationService, []},
      {Foundation.Perimeter.ContractRegistry, []},
      {Foundation.Perimeter.ErrorHandler, []},
      {Foundation.Perimeter.PerformanceMonitor, []}
    ]
  end
  
  defp perimeter_children(false), do: []
end
```

### Initial Configuration

```elixir
# config/config.exs
import Config

# Enable Perimeter in development/testing
config :foundation,
  perimeter_enabled: true

# Perimeter configuration
config :foundation, Foundation.Perimeter,
  # Start with lenient enforcement for migration
  enforcement_config: %{
    external_level: :log,      # Log violations but don't fail
    service_level: :log,
    coupling_level: :none,
    core_level: :none
  },
  
  # Migration-friendly settings
  migration_mode: true,
  legacy_compatibility: true,
  detailed_logging: true
```

### Migration Testing Framework

```elixir
defmodule Foundation.Perimeter.Migration.TestFramework do
  @moduledoc """
  Testing framework for Perimeter migration validation.
  """
  
  use ExUnit.CaseTemplate
  
  using do
    quote do
      use ExUnit.Case
      import Foundation.Perimeter.Migration.TestFramework
      
      setup do
        # Enable Perimeter for testing
        Application.put_env(:foundation, :perimeter_enabled, true)
        
        # Start with migration-friendly settings
        Foundation.Perimeter.ValidationService.update_enforcement_config(%{
          external_level: :log,
          service_level: :log,
          coupling_level: :none,
          core_level: :none
        })
        
        on_exit(fn ->
          Application.put_env(:foundation, :perimeter_enabled, false)
        end)
        
        :ok
      end
    end
  end
  
  def assert_backward_compatibility(module, function, args) do
    # Test that existing functionality still works
    legacy_result = apply(module, function, args)
    
    # Enable Perimeter
    perimeter_result = with_perimeter_enabled(fn ->
      apply(module, function, args)
    end)
    
    assert legacy_result == perimeter_result,
           "Backward compatibility failed for #{module}.#{function}/#{length(args)}"
  end
  
  def assert_no_performance_regression(module, function, args, max_overhead_percent \\ 20) do
    # Measure performance before and after Perimeter
    legacy_time = measure_execution_time(fn ->
      apply(module, function, args)
    end)
    
    perimeter_time = with_perimeter_enabled(fn ->
      measure_execution_time(fn ->
        apply(module, function, args)
      end)
    end)
    
    overhead_percent = ((perimeter_time - legacy_time) / legacy_time) * 100
    
    assert overhead_percent <= max_overhead_percent,
           "Performance regression: #{Float.round(overhead_percent, 2)}% overhead (max: #{max_overhead_percent}%)"
  end
  
  defp with_perimeter_enabled(fun) do
    original_setting = Application.get_env(:foundation, :perimeter_enabled)
    Application.put_env(:foundation, :perimeter_enabled, true)
    
    try do
      fun.()
    after
      Application.put_env(:foundation, :perimeter_enabled, original_setting)
    end
  end
  
  defp measure_execution_time(fun) do
    start_time = System.monotonic_time(:microsecond)
    fun.()
    end_time = System.monotonic_time(:microsecond)
    end_time - start_time
  end
end
```

## Phase 2: External Perimeter Migration

### Migrating External APIs

Start by wrapping existing external APIs with Perimeter validation:

```elixir
# lib/foundation/api/migration_wrapper.ex
defmodule Foundation.API.MigrationWrapper do
  @moduledoc """
  Migration wrapper for existing Foundation APIs.
  Gradually introduces Perimeter validation while maintaining backward compatibility.
  """
  
  use Foundation.Perimeter
  
  # Wrap existing DSPEx program creation
  external_contract :create_dspex_program_wrapper do
    field :name, :string, required: true, length: 1..100
    field :description, :string, length: 0..1000, default: ""
    field :schema_fields, {:list, :map}, required: true, validate: &validate_schema_fields/1
    
    # Legacy field support
    field :legacy_format, :boolean, default: false
    
    validate :ensure_legacy_compatibility
  end
  
  def create_dspex_program(params) do
    # Check if this is a legacy request
    if params[:legacy_format] do
      # Route to legacy implementation
      create_dspex_program_legacy(params)
    else
      # Use new Perimeter validation
      create_dspex_program_perimeter(params)
    end
  end
  
  defp create_dspex_program_perimeter(params) do
    # Validate with Perimeter
    case __validate_external__(:create_dspex_program_wrapper, params) do
      {:ok, validated_params} ->
        # Call actual implementation
        Foundation.DSPEx.create_program(validated_params)
      
      {:error, violations} ->
        # Handle validation errors
        {:error, format_validation_errors(violations)}
    end
  end
  
  defp create_dspex_program_legacy(params) do
    # Preserve legacy behavior
    Foundation.DSPEx.create_program_legacy(params)
  end
  
  defp ensure_legacy_compatibility(params) do
    # Ensure legacy fields are handled properly
    if params[:legacy_format] and not legacy_fields_present?(params) do
      {:error, "Legacy format specified but legacy fields missing"}
    else
      {:ok, params}
    end
  end
end
```

### Gradual API Transition

```elixir
defmodule Foundation.API.GradualTransition do
  @moduledoc """
  Manages gradual transition from legacy APIs to Perimeter-protected APIs.
  """
  
  @transition_percentage_key :perimeter_transition_percentage
  
  def route_request(api_function, params) do
    transition_percentage = get_transition_percentage()
    
    if should_use_perimeter?(transition_percentage) do
      route_to_perimeter(api_function, params)
    else
      route_to_legacy(api_function, params)
    end
  end
  
  defp should_use_perimeter?(percentage) do
    # Use hash of request parameters for consistent routing
    hash = :erlang.phash2(System.unique_integer())
    rem(hash, 100) < percentage
  end
  
  defp route_to_perimeter(api_function, params) do
    # Add telemetry to track Perimeter usage
    Foundation.Telemetry.increment([:foundation, :api, :perimeter_usage])
    
    case apply(Foundation.API.MigrationWrapper, api_function, [params]) do
      {:ok, result} ->
        Foundation.Telemetry.increment([:foundation, :api, :perimeter_success])
        {:ok, result}
      
      {:error, reason} ->
        Foundation.Telemetry.increment([:foundation, :api, :perimeter_error])
        
        # Fallback to legacy for errors during migration
        if Application.get_env(:foundation, :perimeter_fallback_enabled, true) do
          route_to_legacy(api_function, params)
        else
          {:error, reason}
        end
    end
  end
  
  defp route_to_legacy(api_function, params) do
    Foundation.Telemetry.increment([:foundation, :api, :legacy_usage])
    
    # Call legacy implementation
    legacy_module = Module.concat([Foundation.API.Legacy, api_function |> Atom.to_string() |> Macro.camelize()])
    apply(legacy_module, :call, [params])
  end
  
  def increase_transition_percentage(increment \\ 10) do
    current = get_transition_percentage()
    new_percentage = min(current + increment, 100)
    
    Application.put_env(:foundation, @transition_percentage_key, new_percentage)
    
    Logger.info("Increased Perimeter transition percentage to #{new_percentage}%")
    new_percentage
  end
  
  defp get_transition_percentage do
    Application.get_env(:foundation, @transition_percentage_key, 0)
  end
end
```

## Phase 3: Service Boundaries Migration

### Migrating Foundation Services

Gradually add strategic boundaries to Foundation services:

```elixir
# lib/foundation/registry_migration.ex
defmodule Foundation.RegistryMigration do
  @moduledoc """
  Migrates Foundation.Registry to use Perimeter strategic boundaries.
  """
  
  use Foundation.Perimeter
  
  # Add strategic boundaries gradually
  strategic_boundary :register_service_v2 do
    field :service_id, :string, required: true, format: :uuid
    field :service_spec, :map, required: true, validate: &validate_service_spec/1
    field :registry_scope, :atom, values: [:local, :cluster, :global], default: :local
    
    validate :ensure_service_id_unique
  end
  
  def register_service(service_id, service_spec, opts \\ []) do
    # Check if Perimeter validation is enabled
    if perimeter_enabled?() do
      register_service_with_perimeter(service_id, service_spec, opts)
    else
      register_service_legacy(service_id, service_spec, opts)
    end
  end
  
  defp register_service_with_perimeter(service_id, service_spec, opts) do
    params = %{
      service_id: service_id,
      service_spec: service_spec,
      registry_scope: Keyword.get(opts, :scope, :local)
    }
    
    case __validate_strategic__(:register_service_v2, params) do
      {:ok, validated_params} ->
        # Call actual registration logic
        do_register_service(validated_params)
      
      {:error, violations} ->
        handle_validation_error(violations)
    end
  end
  
  defp register_service_legacy(service_id, service_spec, opts) do
    # Preserve existing behavior
    Foundation.Registry.register_service_legacy(service_id, service_spec, opts)
  end
  
  defp perimeter_enabled? do
    Application.get_env(:foundation, :perimeter_enabled, false)
  end
  
  defp validate_service_spec(%{type: type, capabilities: capabilities} = spec) do
    with :ok <- validate_service_type(type),
         :ok <- validate_capabilities(capabilities),
         :ok <- validate_configuration(spec[:configuration]) do
      :ok
    else
      error -> error
    end
  end
  
  defp ensure_service_id_unique(params) do
    case Foundation.Registry.lookup(params.service_id) do
      {:ok, _} -> {:error, "Service ID already exists"}
      {:error, :not_found} -> {:ok, params}
    end
  end
end
```

### Dual-Mode Operation

Enable services to operate in both legacy and Perimeter modes:

```elixir
defmodule Foundation.Service.DualMode do
  @moduledoc """
  Enables Foundation services to operate in both legacy and Perimeter modes.
  """
  
  defmacro __using__(opts) do
    quote do
      use Foundation.Perimeter
      
      @dual_mode_enabled Keyword.get(unquote(opts), :dual_mode, true)
      
      def handle_request(request, mode \\ :auto) do
        effective_mode = determine_mode(mode)
        
        case effective_mode do
          :perimeter -> handle_request_perimeter(request)
          :legacy -> handle_request_legacy(request)
        end
      end
      
      defp determine_mode(:auto) do
        if perimeter_enabled_for_module?(__MODULE__) do
          :perimeter
        else
          :legacy
        end
      end
      
      defp determine_mode(explicit_mode), do: explicit_mode
      
      defp perimeter_enabled_for_module?(module) do
        Application.get_env(:foundation, :perimeter_enabled, false) and
        not module_in_legacy_list?(module)
      end
      
      defp module_in_legacy_list?(module) do
        legacy_modules = Application.get_env(:foundation, :perimeter_legacy_modules, [])
        module in legacy_modules
      end
      
      # Subclasses must implement these
      def handle_request_perimeter(request) do
        raise "handle_request_perimeter/1 must be implemented"
      end
      
      def handle_request_legacy(request) do
        raise "handle_request_legacy/1 must be implemented"
      end
      
      defoverridable handle_request_perimeter: 1, handle_request_legacy: 1
    end
  end
end
```

## Phase 4: Coupling Optimization

### Enabling Productive Coupling

Remove artificial boundaries between Foundation and Jido:

```elixir
defmodule Foundation.Jido.CouplingOptimization do
  @moduledoc """
  Optimizes coupling between Foundation and Jido systems.
  """
  
  # Enable direct function calls in coupling zone
  def optimize_foundation_jido_coupling do
    if coupling_zone_enabled?() do
      enable_direct_coupling()
    else
      maintain_boundary_validation()
    end
  end
  
  defp enable_direct_coupling do
    # Replace boundary-heavy calls with direct function calls
    
    # Before: Multiple validation layers
    # Foundation.API.call -> Foundation.Services.validate -> Jido.API.validate -> Jido.Agent.execute
    
    # After: Direct coupling
    # Foundation.API.call -> Jido.Agent.execute (with perimeter validation at entry only)
    
    configure_direct_routes()
  end
  
  defp configure_direct_routes do
    # Configure routing table for direct calls
    routing_config = %{
      # Foundation -> Jido direct routes
      {Foundation.Coordination, :coordinate_agents} => {Jido.Coordination, :execute_directly},
      {Foundation.Registry, :lookup_agent} => {Jido.Registry, :get_directly},
      {Foundation.MABEAM, :optimize_variables} => {Jido.Optimization, :optimize_directly}
    }
    
    Application.put_env(:foundation, :direct_routing, routing_config)
  end
  
  defp coupling_zone_enabled? do
    Application.get_env(:foundation, :coupling_zone_enabled, false)
  end
end
```

### Performance Optimization Migration

```elixir
defmodule Foundation.Perimeter.PerformanceOptimization do
  @moduledoc """
  Applies performance optimizations after Perimeter migration.
  """
  
  def apply_zone_optimizations do
    %{
      zone1: optimize_external_perimeter(),
      zone2: optimize_service_boundaries(),
      zone3: optimize_coupling_zone(),
      zone4: optimize_core_engine()
    }
  end
  
  defp optimize_external_perimeter do
    # Cache expensive validations
    :ets.new(:external_validation_cache, [
      :set, :public, :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
    
    # Pre-compile common validation patterns
    compile_common_validations()
    
    %{status: :optimized, cache_enabled: true}
  end
  
  defp optimize_service_boundaries do
    # Enable fast-path validation for known services
    enable_service_fast_paths()
    
    # Optimize inter-service communication
    optimize_service_protocols()
    
    %{status: :optimized, fast_paths: true}
  end
  
  defp optimize_coupling_zone do
    # Remove validation overhead between coupled components
    disable_internal_validation()
    
    # Enable direct function calls
    enable_direct_coupling()
    
    %{status: :optimized, validation_overhead: :removed}
  end
  
  defp optimize_core_engine do
    # Maximum performance for core operations
    enable_aggressive_optimizations()
    
    # Remove all validation in core paths
    configure_zero_overhead_mode()
    
    %{status: :optimized, overhead: :zero}
  end
end
```

## Migration Validation

### Testing Migration Success

```elixir
defmodule Foundation.Perimeter.MigrationValidation do
  @moduledoc """
  Validates successful migration to Foundation Perimeter.
  """
  
  def validate_migration_success do
    %{
      functionality: validate_functionality(),
      performance: validate_performance(),
      security: validate_security(),
      monitoring: validate_monitoring(),
      rollback_capability: validate_rollback(),
      overall_status: :pending  # Will be determined
    }
    |> determine_overall_migration_status()
  end
  
  defp validate_functionality do
    test_cases = [
      {Foundation.API, :create_dspex_program, [sample_dspex_params()]},
      {Foundation.API, :deploy_jido_agent, [sample_agent_params()]},
      {Foundation.Registry, :register_service, ["test-service", sample_service_spec()]},
      {Foundation.Coordination, :coordinate_agents, [sample_coordination_params()]}
    ]
    
    results = Enum.map(test_cases, fn {module, function, args} ->
      test_function_compatibility(module, function, args)
    end)
    
    success_rate = Enum.count(results, &(&1.status == :success)) / length(results)
    
    %{
      success_rate: success_rate,
      test_results: results,
      status: if(success_rate >= 0.95, do: :passed, else: :failed)
    }
  end
  
  defp validate_performance do
    performance_tests = [
      {:zone1_validation, &test_zone1_performance/0},
      {:zone2_validation, &test_zone2_performance/0},
      {:coupling_optimization, &test_coupling_performance/0},
      {:overall_throughput, &test_overall_throughput/0}
    ]
    
    results = Enum.map(performance_tests, fn {test_name, test_fn} ->
      {test_name, test_fn.()}
    end)
    
    all_passed = Enum.all?(results, fn {_name, result} -> result.status == :passed end)
    
    %{
      test_results: results,
      status: if(all_passed, do: :passed, else: :failed)
    }
  end
  
  defp validate_security do
    security_tests = [
      &test_external_input_validation/0,
      &test_injection_prevention/0,
      &test_access_controls/0,
      &test_audit_logging/0
    ]
    
    results = Enum.map(security_tests, & &1.())
    all_passed = Enum.all?(results, &(&1.status == :passed))
    
    %{
      test_results: results,
      status: if(all_passed, do: :passed, else: :failed)
    }
  end
  
  defp determine_overall_migration_status(validation_results) do
    statuses = [
      validation_results.functionality.status,
      validation_results.performance.status,
      validation_results.security.status,
      validation_results.monitoring.status,
      validation_results.rollback_capability.status
    ]
    
    overall_status = if Enum.all?(statuses, &(&1 == :passed)) do
      :migration_successful
    else
      :migration_incomplete
    end
    
    %{validation_results | overall_status: overall_status}
  end
end
```

### Rollback Strategy

```elixir
defmodule Foundation.Perimeter.RollbackStrategy do
  @moduledoc """
  Provides rollback capabilities for Perimeter migration.
  """
  
  def create_rollback_point(name) do
    rollback_data = %{
      name: name,
      timestamp: DateTime.utc_now(),
      configuration: capture_current_configuration(),
      service_states: capture_service_states(),
      performance_baseline: capture_performance_metrics()
    }
    
    store_rollback_point(rollback_data)
  end
  
  def execute_rollback(rollback_point_name) do
    case get_rollback_point(rollback_point_name) do
      {:ok, rollback_data} ->
        perform_rollback(rollback_data)
      
      {:error, :not_found} ->
        {:error, "Rollback point not found: #{rollback_point_name}"}
    end
  end
  
  defp perform_rollback(rollback_data) do
    Logger.info("Starting rollback to: #{rollback_data.name}")
    
    # Disable Perimeter
    Application.put_env(:foundation, :perimeter_enabled, false)
    
    # Restore configuration
    restore_configuration(rollback_data.configuration)
    
    # Restart services with legacy configuration
    restart_services_legacy_mode()
    
    # Validate rollback success
    case validate_rollback_success(rollback_data) do
      :ok ->
        Logger.info("Rollback completed successfully")
        {:ok, :rollback_successful}
      
      {:error, reason} ->
        Logger.error("Rollback validation failed: #{reason}")
        {:error, :rollback_failed}
    end
  end
  
  defp validate_rollback_success(rollback_data) do
    # Verify systems are functioning in legacy mode
    functionality_check = test_basic_functionality()
    performance_check = compare_performance_to_baseline(rollback_data.performance_baseline)
    
    case {functionality_check, performance_check} do
      {:ok, :ok} -> :ok
      {error, _} -> error
      {_, error} -> error
    end
  end
end
```

## Migration Monitoring

### Migration Dashboard

```elixir
defmodule Foundation.Perimeter.MigrationDashboard do
  @moduledoc """
  Real-time dashboard for monitoring Perimeter migration progress.
  """
  
  def get_migration_status do
    %{
      overall_progress: calculate_overall_progress(),
      phase_status: get_phase_status(),
      performance_impact: measure_performance_impact(),
      error_rates: get_error_rates(),
      adoption_metrics: get_adoption_metrics(),
      risk_indicators: get_risk_indicators()
    }
  end
  
  defp calculate_overall_progress do
    phases = [:infrastructure, :external_perimeter, :service_boundaries, :coupling_optimization]
    
    progress_by_phase = Enum.map(phases, fn phase ->
      {phase, get_phase_progress(phase)}
    end)
    
    total_progress = progress_by_phase
    |> Enum.map(fn {_phase, progress} -> progress end)
    |> Enum.sum()
    |> div(length(phases))
    
    %{
      total_progress: total_progress,
      phases: Map.new(progress_by_phase)
    }
  end
  
  defp measure_performance_impact do
    baseline = get_performance_baseline()
    current = get_current_performance()
    
    %{
      validation_overhead: calculate_overhead_change(baseline, current),
      throughput_impact: calculate_throughput_impact(baseline, current),
      latency_impact: calculate_latency_impact(baseline, current),
      memory_impact: calculate_memory_impact(baseline, current)
    }
  end
  
  defp get_adoption_metrics do
    %{
      perimeter_enabled_services: count_perimeter_enabled_services(),
      apis_migrated: count_migrated_apis(),
      validation_coverage: calculate_validation_coverage(),
      contract_compliance: calculate_contract_compliance()
    }
  end
end
```

This comprehensive migration guide ensures a smooth, safe, and validated transition to Foundation Perimeter while maintaining system reliability and performance throughout the process.