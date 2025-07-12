# Foundation Perimeter Implementation Guide

## Overview

This document provides the complete implementation strategy for integrating Perimeter into Foundation's architecture. It covers the technical implementation details, supervision tree integration, performance optimization, and production deployment considerations.

## Implementation Architecture

### Foundation Service Integration

```elixir
# Enhanced Foundation.Application with Perimeter services
defmodule Foundation.Application do
  use Application
  
  def start(_type, _args) do
    children = [
      # Core Foundation services
      {Foundation.Registry, []},
      {Foundation.Telemetry, []},
      
      # Perimeter services integration
      {Foundation.Perimeter.ValidationService, []},
      {Foundation.Perimeter.ContractRegistry, []},
      {Foundation.Perimeter.ErrorHandler, []},
      
      # Enhanced Foundation services with Perimeter
      {Foundation.Services.Supervisor, [perimeter_enabled: true]},
      {Foundation.MABEAM.Supervisor, [validation_mode: :strategic]},
      
      # Jido integration with Perimeter protection
      {JidoSystem.Supervisor, [foundation_perimeter: true]}
    ]
    
    opts = [strategy: :one_for_one, name: Foundation.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### Core Perimeter Modules

#### Foundation.Perimeter.ValidationService

```elixir
defmodule Foundation.Perimeter.ValidationService do
  @moduledoc """
  Central validation service for Foundation Perimeter system.
  Manages validation caching, performance monitoring, and contract enforcement.
  """
  
  use GenServer
  require Logger
  
  alias Foundation.Perimeter.{ContractRegistry, ErrorHandler}
  alias Foundation.Telemetry
  
  defstruct [
    :validation_cache,
    :performance_stats,
    :enforcement_config,
    :contract_cache
  ]
  
  # Client API
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def validate(contract_module, contract_name, data, opts \\ []) do
    GenServer.call(__MODULE__, {:validate, contract_module, contract_name, data, opts})
  end
  
  def validate_async(contract_module, contract_name, data, opts \\ []) do
    GenServer.cast(__MODULE__, {:validate_async, contract_module, contract_name, data, opts})
  end
  
  def get_performance_stats do
    GenServer.call(__MODULE__, :get_performance_stats)
  end
  
  def update_enforcement_config(config) do
    GenServer.call(__MODULE__, {:update_enforcement_config, config})
  end
  
  # Server callbacks
  
  def init(opts) do
    # Initialize ETS cache for validation results
    validation_cache = :ets.new(:foundation_validation_cache, [
      :set, :public, :named_table,
      {:read_concurrency, true},
      {:write_concurrency, true}
    ])
    
    # Initialize performance tracking
    performance_stats = %{
      total_validations: 0,
      cache_hits: 0,
      cache_misses: 0,
      average_validation_time: 0.0,
      error_rate: 0.0
    }
    
    # Default enforcement configuration
    enforcement_config = %{
      external_level: :strict,
      service_level: :optimized,
      coupling_level: :none,
      core_level: :none,
      cache_ttl: 300_000,  # 5 minutes
      max_cache_size: 10_000
    }
    
    state = %__MODULE__{
      validation_cache: validation_cache,
      performance_stats: performance_stats,
      enforcement_config: enforcement_config,
      contract_cache: %{}
    }
    
    # Schedule periodic cache cleanup
    Process.send_after(self(), :cleanup_cache, 60_000)
    
    {:ok, state}
  end
  
  def handle_call({:validate, contract_module, contract_name, data, opts}, _from, state) do
    start_time = System.monotonic_time(:microsecond)
    
    case perform_validation_with_cache(contract_module, contract_name, data, opts, state) do
      {:ok, result} = success ->
        end_time = System.monotonic_time(:microsecond)
        validation_time = end_time - start_time
        
        new_state = update_performance_stats(state, :success, validation_time)
        
        Telemetry.emit([:foundation, :perimeter, :validation, :success], %{
          duration: validation_time
        }, %{
          contract_module: contract_module,
          contract_name: contract_name
        })
        
        {:reply, success, new_state}
      
      {:error, _reason} = error ->
        end_time = System.monotonic_time(:microsecond)
        validation_time = end_time - start_time
        
        new_state = update_performance_stats(state, :error, validation_time)
        
        Telemetry.emit([:foundation, :perimeter, :validation, :error], %{
          duration: validation_time
        }, %{
          contract_module: contract_module,
          contract_name: contract_name
        })
        
        {:reply, error, new_state}
    end
  end
  
  def handle_call(:get_performance_stats, _from, state) do
    {:reply, state.performance_stats, state}
  end
  
  def handle_call({:update_enforcement_config, config}, _from, state) do
    new_state = %{state | enforcement_config: config}
    {:reply, :ok, new_state}
  end
  
  def handle_info(:cleanup_cache, state) do
    cleanup_expired_cache_entries(state)
    Process.send_after(self(), :cleanup_cache, 60_000)
    {:noreply, state}
  end
  
  # Private implementation
  
  defp perform_validation_with_cache(contract_module, contract_name, data, opts, state) do
    cache_key = generate_cache_key(contract_module, contract_name, data)
    enforcement_level = get_enforcement_level(contract_module, state.enforcement_config)
    
    case enforcement_level do
      :none ->
        {:ok, data}  # No validation in none mode
      
      level when level in [:strict, :optimized] ->
        case check_cache(cache_key, state) do
          {:hit, result} ->
            Telemetry.increment([:foundation, :perimeter, :cache_hit])
            {:ok, result}
          
          :miss ->
            Telemetry.increment([:foundation, :perimeter, :cache_miss])
            case perform_validation(contract_module, contract_name, data, opts) do
              {:ok, result} = success ->
                store_in_cache(cache_key, result, state)
                success
              
              error ->
                error
            end
        end
    end
  end
  
  defp perform_validation(contract_module, contract_name, data, _opts) do
    try do
      case contract_module.__validate_external__(contract_name, data) do
        {:ok, validated_data} ->
          {:ok, validated_data}
        
        {:error, violations} ->
          {:error, %Foundation.Perimeter.Error{
            zone: :external,
            contract: contract_name,
            violations: violations,
            timestamp: DateTime.utc_now()
          }}
      end
    rescue
      error ->
        {:error, %Foundation.Perimeter.Error{
          zone: :external,
          contract: contract_name,
          violations: [%{error: "Validation exception: #{inspect(error)}"}],
          timestamp: DateTime.utc_now()
        }}
    end
  end
  
  defp generate_cache_key(contract_module, contract_name, data) do
    :crypto.hash(:sha256, :erlang.term_to_binary({contract_module, contract_name, data}))
    |> Base.encode16()
  end
  
  defp check_cache(cache_key, state) do
    case :ets.lookup(state.validation_cache, cache_key) do
      [{^cache_key, result, expiry_time}] ->
        if System.system_time(:millisecond) < expiry_time do
          {:hit, result}
        else
          :ets.delete(state.validation_cache, cache_key)
          :miss
        end
      
      [] ->
        :miss
    end
  end
  
  defp store_in_cache(cache_key, result, state) do
    expiry_time = System.system_time(:millisecond) + state.enforcement_config.cache_ttl
    :ets.insert(state.validation_cache, {cache_key, result, expiry_time})
  end
  
  defp get_enforcement_level(contract_module, config) do
    cond do
      String.contains?(Atom.to_string(contract_module), "External") -> config.external_level
      String.contains?(Atom.to_string(contract_module), "Services") -> config.service_level
      String.contains?(Atom.to_string(contract_module), "Coupling") -> config.coupling_level
      true -> config.core_level
    end
  end
  
  defp update_performance_stats(state, result_type, validation_time) do
    stats = state.performance_stats
    
    new_total = stats.total_validations + 1
    new_avg_time = (stats.average_validation_time * stats.total_validations + validation_time) / new_total
    
    new_error_count = case result_type do
      :error -> get_error_count(stats) + 1
      _ -> get_error_count(stats)
    end
    
    new_error_rate = new_error_count / new_total
    
    new_stats = %{
      stats |
      total_validations: new_total,
      average_validation_time: new_avg_time,
      error_rate: new_error_rate
    }
    
    %{state | performance_stats: new_stats}
  end
  
  defp get_error_count(stats) do
    round(stats.error_rate * stats.total_validations)
  end
  
  defp cleanup_expired_cache_entries(state) do
    current_time = System.system_time(:millisecond)
    
    :ets.select_delete(state.validation_cache, [
      {{:_, :_, :"$1"}, [{:<, :"$1", current_time}], [true]}
    ])
  end
end
```

#### Foundation.Perimeter.ContractRegistry

```elixir
defmodule Foundation.Perimeter.ContractRegistry do
  @moduledoc """
  Registry for managing Foundation Perimeter contracts.
  Provides contract discovery, compilation, and runtime management.
  """
  
  use GenServer
  
  defstruct [
    :contracts,
    :compiled_validators,
    :contract_metadata
  ]
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def register_contract(module, contract_name, contract_spec) do
    GenServer.call(__MODULE__, {:register_contract, module, contract_name, contract_spec})
  end
  
  def get_contract(module, contract_name) do
    GenServer.call(__MODULE__, {:get_contract, module, contract_name})
  end
  
  def list_contracts(module \\ nil) do
    GenServer.call(__MODULE__, {:list_contracts, module})
  end
  
  def compile_validator(module, contract_name) do
    GenServer.call(__MODULE__, {:compile_validator, module, contract_name})
  end
  
  def init(_opts) do
    # Initialize contract storage
    contracts = :ets.new(:foundation_contracts, [
      :set, :public, :named_table,
      {:read_concurrency, true}
    ])
    
    state = %__MODULE__{
      contracts: contracts,
      compiled_validators: %{},
      contract_metadata: %{}
    }
    
    # Auto-discover and register existing contracts
    discover_and_register_contracts(state)
    
    {:ok, state}
  end
  
  def handle_call({:register_contract, module, contract_name, contract_spec}, _from, state) do
    contract_key = {module, contract_name}
    
    # Store contract specification
    :ets.insert(state.contracts, {contract_key, contract_spec})
    
    # Compile validator function
    compiled_validator = compile_contract_validator(contract_spec)
    new_compiled_validators = Map.put(state.compiled_validators, contract_key, compiled_validator)
    
    # Store metadata
    metadata = extract_contract_metadata(contract_spec)
    new_metadata = Map.put(state.contract_metadata, contract_key, metadata)
    
    new_state = %{
      state |
      compiled_validators: new_compiled_validators,
      contract_metadata: new_metadata
    }
    
    {:reply, :ok, new_state}
  end
  
  def handle_call({:get_contract, module, contract_name}, _from, state) do
    contract_key = {module, contract_name}
    
    case :ets.lookup(state.contracts, contract_key) do
      [{^contract_key, contract_spec}] ->
        {:reply, {:ok, contract_spec}, state}
      
      [] ->
        {:reply, {:error, :contract_not_found}, state}
    end
  end
  
  def handle_call({:compile_validator, module, contract_name}, _from, state) do
    contract_key = {module, contract_name}
    
    case Map.get(state.compiled_validators, contract_key) do
      nil ->
        {:reply, {:error, :contract_not_found}, state}
      
      validator ->
        {:reply, {:ok, validator}, state}
    end
  end
  
  defp discover_and_register_contracts(state) do
    # Scan for modules using Foundation.Perimeter
    :code.all_loaded()
    |> Enum.filter(fn {module, _} ->
      has_perimeter_contracts?(module)
    end)
    |> Enum.each(fn {module, _} ->
      register_module_contracts(module, state)
    end)
  end
  
  defp has_perimeter_contracts?(module) do
    try do
      function_exported?(module, :__external_contracts__, 0) or
      function_exported?(module, :__strategic_boundaries__, 0)
    rescue
      _ -> false
    end
  end
  
  defp register_module_contracts(module, state) do
    try do
      if function_exported?(module, :__external_contracts__, 0) do
        contracts = module.__external_contracts__()
        Enum.each(contracts, fn {name, spec} ->
          GenServer.call(__MODULE__, {:register_contract, module, name, spec})
        end)
      end
      
      if function_exported?(module, :__strategic_boundaries__, 0) do
        boundaries = module.__strategic_boundaries__()
        Enum.each(boundaries, fn {name, spec} ->
          GenServer.call(__MODULE__, {:register_contract, module, name, spec})
        end)
      end
    rescue
      error ->
        Logger.warning("Failed to register contracts for #{module}: #{inspect(error)}")
    end
  end
  
  defp compile_contract_validator(contract_spec) do
    # Generate optimized validation function from contract specification
    # This would contain the actual validation logic compilation
    fn data ->
      # Placeholder - actual implementation would generate optimized code
      {:ok, data}
    end
  end
  
  defp extract_contract_metadata(contract_spec) do
    %{
      fields: count_fields(contract_spec),
      validators: count_validators(contract_spec),
      complexity: estimate_complexity(contract_spec),
      created_at: DateTime.utc_now()
    }
  end
  
  defp count_fields(contract_spec) do
    # Count field definitions in contract
    length(contract_spec[:fields] || [])
  end
  
  defp count_validators(contract_spec) do
    # Count custom validators in contract
    length(contract_spec[:validators] || [])
  end
  
  defp estimate_complexity(contract_spec) do
    # Simple complexity estimation
    field_count = count_fields(contract_spec)
    validator_count = count_validators(contract_spec)
    
    cond do
      field_count + validator_count <= 5 -> :low
      field_count + validator_count <= 15 -> :medium
      true -> :high
    end
  end
end
```

### Enhanced Foundation Services with Perimeter

#### Foundation.Services.Supervisor with Perimeter Integration

```elixir
defmodule Foundation.Services.Supervisor do
  @moduledoc """
  Enhanced Foundation services supervisor with Perimeter integration.
  """
  
  use Supervisor
  
  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    perimeter_enabled = Keyword.get(opts, :perimeter_enabled, false)
    
    base_children = [
      {Foundation.Registry, []},
      {Foundation.Coordination, []},
      {Foundation.MABEAM.Core, []},
      {Foundation.Telemetry, []}
    ]
    
    children = if perimeter_enabled do
      base_children ++ [
        {Foundation.Perimeter.ValidationService, []},
        {Foundation.Perimeter.ContractRegistry, []},
        {Foundation.Perimeter.ErrorHandler, []}
      ]
    else
      base_children
    end
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end
```

#### Enhanced Foundation.Registry with Perimeter Protection

```elixir
defmodule Foundation.Registry do
  @moduledoc """
  Foundation Registry with integrated Perimeter validation.
  """
  
  use GenServer
  use Foundation.Perimeter
  
  # Zone 2: Strategic boundary for registry operations
  strategic_boundary :register_service do
    field :service_id, :string, required: true, format: :uuid
    field :service_spec, :map, required: true, validate: &validate_service_specification/1
    field :registry_scope, :atom, values: [:local, :cluster, :global], default: :local
    
    validate :ensure_service_id_unique
    validate :ensure_service_spec_complete
  end
  
  strategic_boundary :lookup_service do
    field :service_id, :string, required: true, format: :uuid
    field :lookup_options, :map, validate: &validate_lookup_options/1
    
    validate :ensure_lookup_authorization
  end
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  # Public API with perimeter protection
  def register(service_id, service_spec, opts \\ []) do
    params = %{
      service_id: service_id,
      service_spec: service_spec,
      registry_scope: Keyword.get(opts, :scope, :local)
    }
    
    # Perimeter validation happens automatically via strategic_boundary
    GenServer.call(__MODULE__, {:register, params})
  end
  
  def lookup(service_id, opts \\ []) do
    params = %{
      service_id: service_id,
      lookup_options: Map.new(opts)
    }
    
    # Perimeter validation happens automatically via strategic_boundary
    GenServer.call(__MODULE__, {:lookup, params})
  end
  
  # Implementation with trust in validated data
  def handle_call({:register, params}, _from, state) do
    # No validation needed - strategic boundary guarantees valid data
    %{service_id: service_id, service_spec: service_spec} = params
    
    case do_register(service_id, service_spec, state) do
      {:ok, new_state} ->
        Foundation.Telemetry.emit([:foundation, :registry, :service_registered], %{}, %{
          service_id: service_id
        })
        {:reply, :ok, new_state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call({:lookup, params}, _from, state) do
    # No validation needed - strategic boundary guarantees valid data
    %{service_id: service_id} = params
    
    case do_lookup(service_id, state) do
      {:ok, service_spec} ->
        {:reply, {:ok, service_spec}, state}
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  # Validation functions for strategic boundaries
  defp validate_service_specification(%{type: type, capabilities: capabilities} = spec) 
    when is_atom(type) and is_list(capabilities) do
    # Validate service specification structure
    required_fields = [:type, :capabilities, :configuration]
    
    case Enum.all?(required_fields, &Map.has_key?(spec, &1)) do
      true -> :ok
      false -> {:error, "Missing required service specification fields"}
    end
  end
  defp validate_service_specification(_), do: {:error, "Invalid service specification format"}
  
  defp validate_lookup_options(options) when is_map(options) do
    allowed_keys = [:timeout, :scope, :include_metadata]
    
    case Enum.all?(Map.keys(options), &(&1 in allowed_keys)) do
      true -> :ok
      false -> {:error, "Invalid lookup options"}
    end
  end
  defp validate_lookup_options(_), do: {:error, "Lookup options must be a map"}
  
  defp ensure_service_id_unique(params) do
    # Check if service ID is already registered
    case lookup_existing_service(params.service_id) do
      {:ok, _} -> {:error, "Service ID already exists"}
      {:error, :not_found} -> {:ok, params}
    end
  end
  
  defp ensure_service_spec_complete(params) do
    # Additional business logic validation
    case validate_service_capabilities(params.service_spec.capabilities) do
      :ok -> {:ok, params}
      error -> error
    end
  end
  
  # ... rest of implementation
end
```

### Performance Optimization

#### Compile-Time Contract Optimization

```elixir
defmodule Foundation.Perimeter.Compiler do
  @moduledoc """
  Compile-time optimization for Foundation Perimeter contracts.
  """
  
  defmacro __before_compile__(env) do
    external_contracts = Module.get_attribute(env.module, :external_contracts, [])
    strategic_boundaries = Module.get_attribute(env.module, :strategic_boundaries, [])
    
    # Generate optimized validation functions
    external_validators = generate_optimized_validators(external_contracts, :external)
    boundary_validators = generate_optimized_validators(strategic_boundaries, :strategic)
    
    quote do
      unquote_splicing(external_validators)
      unquote_splicing(boundary_validators)
      
      # Contract introspection functions
      def __external_contracts__, do: unquote(Macro.escape(external_contracts))
      def __strategic_boundaries__, do: unquote(Macro.escape(strategic_boundaries))
    end
  end
  
  defp generate_optimized_validators(contracts, zone_type) do
    Enum.map(contracts, fn {name, contract_spec} ->
      generate_validator_function(name, contract_spec, zone_type)
    end)
  end
  
  defp generate_validator_function(name, contract_spec, zone_type) do
    function_name = :"__validate_#{zone_type}__"
    
    quote do
      def unquote(function_name)(unquote(name), data) when is_map(data) do
        # Generated optimized validation code
        unquote(generate_validation_ast(contract_spec))
      end
      
      def unquote(function_name)(unquote(name), _data) do
        {:error, [%{error: "Expected map input"}]}
      end
    end
  end
  
  defp generate_validation_ast(contract_spec) do
    # Generate optimized AST for validation
    # This would contain the actual validation code generation
    quote do
      {:ok, data}  # Placeholder
    end
  end
end
```

#### Runtime Performance Monitoring

```elixir
defmodule Foundation.Perimeter.PerformanceMonitor do
  @moduledoc """
  Real-time performance monitoring for Foundation Perimeter operations.
  """
  
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def record_validation(contract_module, contract_name, duration, result) do
    GenServer.cast(__MODULE__, {:record_validation, contract_module, contract_name, duration, result})
  end
  
  def get_performance_report do
    GenServer.call(__MODULE__, :get_performance_report)
  end
  
  def init(_opts) do
    # Initialize performance tracking
    state = %{
      validation_metrics: %{},
      zone_performance: %{
        external: %{total_time: 0, count: 0},
        strategic: %{total_time: 0, count: 0},
        coupling: %{total_time: 0, count: 0},
        core: %{total_time: 0, count: 0}
      },
      alerts: []
    }
    
    # Schedule periodic performance analysis
    Process.send_after(self(), :analyze_performance, 60_000)
    
    {:ok, state}
  end
  
  def handle_cast({:record_validation, contract_module, contract_name, duration, result}, state) do
    zone = determine_zone(contract_module)
    
    # Update zone performance
    zone_stats = state.zone_performance[zone]
    new_zone_stats = %{
      total_time: zone_stats.total_time + duration,
      count: zone_stats.count + 1
    }
    
    new_zone_performance = Map.put(state.zone_performance, zone, new_zone_stats)
    
    # Update contract-specific metrics
    contract_key = {contract_module, contract_name}
    contract_metrics = Map.get(state.validation_metrics, contract_key, %{
      total_time: 0,
      count: 0,
      errors: 0,
      min_time: duration,
      max_time: duration
    })
    
    new_contract_metrics = %{
      total_time: contract_metrics.total_time + duration,
      count: contract_metrics.count + 1,
      errors: contract_metrics.errors + (if result == :error, do: 1, else: 0),
      min_time: min(contract_metrics.min_time, duration),
      max_time: max(contract_metrics.max_time, duration)
    }
    
    new_validation_metrics = Map.put(state.validation_metrics, contract_key, new_contract_metrics)
    
    new_state = %{
      state |
      zone_performance: new_zone_performance,
      validation_metrics: new_validation_metrics
    }
    
    {:noreply, new_state}
  end
  
  def handle_call(:get_performance_report, _from, state) do
    report = generate_performance_report(state)
    {:reply, report, state}
  end
  
  def handle_info(:analyze_performance, state) do
    new_state = analyze_and_alert(state)
    Process.send_after(self(), :analyze_performance, 60_000)
    {:noreply, new_state}
  end
  
  defp determine_zone(contract_module) do
    module_string = Atom.to_string(contract_module)
    
    cond do
      String.contains?(module_string, "External") -> :external
      String.contains?(module_string, "Services") -> :strategic
      String.contains?(module_string, "Coupling") -> :coupling
      true -> :core
    end
  end
  
  defp generate_performance_report(state) do
    zone_averages = Map.new(state.zone_performance, fn {zone, stats} ->
      avg_time = if stats.count > 0, do: stats.total_time / stats.count, else: 0
      {zone, %{average_time: avg_time, total_validations: stats.count}}
    end)
    
    contract_averages = Map.new(state.validation_metrics, fn {contract_key, metrics} ->
      avg_time = if metrics.count > 0, do: metrics.total_time / metrics.count, else: 0
      error_rate = if metrics.count > 0, do: metrics.errors / metrics.count, else: 0
      
      {contract_key, %{
        average_time: avg_time,
        error_rate: error_rate,
        min_time: metrics.min_time,
        max_time: metrics.max_time,
        total_validations: metrics.count
      }}
    end)
    
    %{
      zone_performance: zone_averages,
      contract_performance: contract_averages,
      alerts: state.alerts,
      generated_at: DateTime.utc_now()
    }
  end
  
  defp analyze_and_alert(state) do
    # Analyze performance and generate alerts
    alerts = []
    
    # Check for slow zones
    zone_alerts = Enum.reduce(state.zone_performance, [], fn {zone, stats}, acc ->
      if stats.count > 0 do
        avg_time = stats.total_time / stats.count
        
        # Alert if average time exceeds thresholds
        threshold = case zone do
          :external -> 15_000    # 15ms
          :strategic -> 5_000    # 5ms
          :coupling -> 1_000     # 1ms (should be near zero)
          :core -> 500           # 0.5ms (should be near zero)
        end
        
        if avg_time > threshold do
          alert = %{
            type: :slow_zone,
            zone: zone,
            average_time: avg_time,
            threshold: threshold,
            timestamp: DateTime.utc_now()
          }
          [alert | acc]
        else
          acc
        end
      else
        acc
      end
    end)
    
    all_alerts = alerts ++ zone_alerts
    
    %{state | alerts: all_alerts}
  end
end
```

This implementation provides a comprehensive foundation for integrating Perimeter into Foundation's architecture while maintaining performance, reliability, and production readiness.