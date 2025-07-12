# Foundation Perimeter ValidationService Implementation

## Context

Foundation Perimeter implements a Four-Zone Architecture for BEAM-native AI systems. The ValidationService is the core component that manages validation caching, performance monitoring, and contract enforcement across all zones.

## Task

Implement `Foundation.Perimeter.ValidationService` as a GenServer that provides high-performance validation with caching, telemetry integration, and Foundation-specific optimizations.

## Requirements

### Architecture
- GenServer implementation with proper OTP supervision
- ETS-based validation caching with TTL support
- Performance monitoring and telemetry integration
- Foundation-specific enforcement levels per zone
- Circuit breaker protection against validation failures

### Test-Driven Implementation
Follow Foundation's event-driven testing philosophy - no `Process.sleep/1` allowed. Use `Foundation.UnifiedTestFoundation` with appropriate isolation mode.

### Performance Targets
- Zone 1 (External): <15ms average validation time
- Zone 2 (Strategic): <5ms average validation time  
- Cache hit rate: >80% for repeated validations
- Concurrent validation support with minimal contention

## Implementation Specification

### Module Structure
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
end
```

### API Functions Required
- `start_link/1` - Start service with configuration
- `validate/4` - Synchronous validation with caching
- `validate_async/4` - Asynchronous validation for non-blocking operations
- `get_performance_stats/0` - Retrieve performance metrics
- `update_enforcement_config/1` - Runtime configuration updates
- `clear_cache/0` - Manual cache clearing

### State Management
```elixir
@type state :: %__MODULE__{
  validation_cache: :ets.tid(),
  performance_stats: performance_stats(),
  enforcement_config: enforcement_config(),
  contract_cache: map()
}

@type performance_stats :: %{
  total_validations: non_neg_integer(),
  cache_hits: non_neg_integer(),
  cache_misses: non_neg_integer(),
  average_validation_time: float(),
  error_rate: float()
}

@type enforcement_config :: %{
  external_level: enforcement_level(),
  service_level: enforcement_level(),
  coupling_level: enforcement_level(),
  core_level: enforcement_level(),
  cache_ttl: pos_integer(),
  max_cache_size: pos_integer()
}

@type enforcement_level :: :none | :log | :warn | :strict
```

### Core Functionality

#### Validation with Caching
```elixir
def validate(contract_module, contract_name, data, opts \\ []) do
  GenServer.call(__MODULE__, {:validate, contract_module, contract_name, data, opts})
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
```

#### Cache Management
```elixir
defp perform_validation_with_cache(contract_module, contract_name, data, opts, state) do
  cache_key = generate_cache_key(contract_module, contract_name, data)
  enforcement_level = get_enforcement_level(contract_module, state.enforcement_config)
  
  case enforcement_level do
    :none ->
      {:ok, data}  # No validation in none mode
    
    level when level in [:strict, :warn, :log] ->
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
```

## Testing Requirements

### Test Structure
```elixir
defmodule Foundation.Perimeter.ValidationServiceTest do
  use Foundation.UnifiedTestFoundation, :registry
  import Foundation.AsyncTestHelpers
  
  alias Foundation.Perimeter.ValidationService
  alias Foundation.Perimeter.Error
  
  @moduletag :perimeter_testing
  @moduletag timeout: 15_000
  
  describe "ValidationService functionality" do
    test "validates external contracts with caching", %{test_context: ctx} do
      # Start ValidationService in test context
      {:ok, service_pid} = start_supervised({ValidationService, [
        name: :"validation_service_#{ctx.test_id}",
        registry: ctx.registry_name
      ]})
      
      # Test contract and data
      contract_module = Foundation.Perimeter.External.TestContracts
      contract_name = :test_contract
      valid_data = %{name: "test", value: 42}
      
      # First validation should miss cache
      assert_telemetry_event [:foundation, :perimeter, :cache_miss], %{count: 1} do
        assert {:ok, validated} = ValidationService.validate(contract_module, contract_name, valid_data)
        assert validated.name == "test"
      end
      
      # Second validation should hit cache
      assert_telemetry_event [:foundation, :perimeter, :cache_hit], %{count: 1} do
        assert {:ok, validated} = ValidationService.validate(contract_module, contract_name, valid_data)
        assert validated.name == "test"
      end
      
      # Verify performance tracking
      stats = ValidationService.get_performance_stats()
      assert stats.total_validations >= 2
      assert stats.cache_hits >= 1
      assert stats.cache_misses >= 1
    end
    
    test "handles validation errors correctly", %{test_context: ctx} do
      {:ok, _service_pid} = start_supervised({ValidationService, [
        name: :"validation_service_#{ctx.test_id}",
        registry: ctx.registry_name
      ]})
      
      contract_module = Foundation.Perimeter.External.TestContracts
      contract_name = :test_contract
      invalid_data = %{name: "", value: "not_a_number"}
      
      # Should emit error telemetry
      assert_telemetry_event [:foundation, :perimeter, :validation, :error], 
        %{duration: duration} when duration > 0 do
        assert {:error, %Error{}} = ValidationService.validate(contract_module, contract_name, invalid_data)
      end
      
      # Error rate should be tracked
      stats = ValidationService.get_performance_stats()
      assert stats.error_rate > 0
    end
    
    test "enforces zone-specific validation levels", %{test_context: ctx} do
      {:ok, _service_pid} = start_supervised({ValidationService, [
        name: :"validation_service_#{ctx.test_id}",
        registry: ctx.registry_name
      ]})
      
      # Configure strict enforcement for external
      ValidationService.update_enforcement_config(%{
        external_level: :strict,
        service_level: :none
      })
      
      external_contract = Foundation.Perimeter.External.TestContracts
      service_contract = Foundation.Perimeter.Services.TestContracts
      invalid_data = %{invalid: "data"}
      
      # External should fail validation
      assert {:error, _} = ValidationService.validate(external_contract, :test_contract, invalid_data)
      
      # Service should bypass validation (none level)
      assert {:ok, ^invalid_data} = ValidationService.validate(service_contract, :test_contract, invalid_data)
    end
  end
  
  describe "ValidationService performance" do
    test "meets performance targets for zone validation", %{test_context: ctx} do
      {:ok, _service_pid} = start_supervised({ValidationService, [
        name: :"validation_service_#{ctx.test_id}",
        registry: ctx.registry_name
      ]})
      
      external_contract = Foundation.Perimeter.External.TestContracts
      strategic_contract = Foundation.Perimeter.Services.TestContracts
      valid_data = %{name: "test", value: 42}
      
      # Measure Zone 1 (External) performance
      {external_time, {:ok, _}} = :timer.tc(fn ->
        ValidationService.validate(external_contract, :test_contract, valid_data)
      end)
      
      # Measure Zone 2 (Strategic) performance  
      {strategic_time, {:ok, _}} = :timer.tc(fn ->
        ValidationService.validate(strategic_contract, :test_contract, valid_data)
      end)
      
      # Convert to milliseconds
      external_ms = external_time / 1000
      strategic_ms = strategic_time / 1000
      
      # Assert performance targets
      assert external_ms < 15.0, "Zone 1 validation took #{external_ms}ms, should be <15ms"
      assert strategic_ms < 5.0, "Zone 2 validation took #{strategic_ms}ms, should be <5ms"
    end
    
    test "cache hit rate exceeds target under load", %{test_context: ctx} do
      {:ok, _service_pid} = start_supervised({ValidationService, [
        name: :"validation_service_#{ctx.test_id}",
        registry: ctx.registry_name
      ]})
      
      contract_module = Foundation.Perimeter.External.TestContracts
      contract_name = :test_contract
      valid_data = %{name: "test", value: 42}
      
      # Perform many validations with same data
      for _i <- 1..100 do
        assert {:ok, _} = ValidationService.validate(contract_module, contract_name, valid_data)
      end
      
      stats = ValidationService.get_performance_stats()
      cache_hit_rate = stats.cache_hits / (stats.cache_hits + stats.cache_misses)
      
      assert cache_hit_rate > 0.8, "Cache hit rate #{Float.round(cache_hit_rate * 100, 1)}% should be >80%"
    end
  end
  
  describe "ValidationService supervision" do
    test "integrates with Foundation supervision tree", %{test_context: ctx} do
      # Start under test supervisor
      sup_spec = {ValidationService, [
        name: :"validation_service_#{ctx.test_id}",
        registry: ctx.registry_name
      ]}
      
      {:ok, service_pid} = start_supervised(sup_spec)
      assert Process.alive?(service_pid)
      
      # Test functionality
      contract_module = Foundation.Perimeter.External.TestContracts
      valid_data = %{name: "test", value: 42}
      
      assert {:ok, _} = ValidationService.validate(contract_module, :test_contract, valid_data)
      
      # Test restart behavior
      ref = Process.monitor(service_pid)
      Process.exit(service_pid, :kill)
      
      # Wait for restart
      assert_receive {:DOWN, ^ref, :process, ^service_pid, :killed}, 2000
      
      # Should restart and be functional
      wait_for(fn ->
        case ValidationService.validate(contract_module, :test_contract, valid_data) do
          {:ok, _} -> true
          _ -> nil
        end
      end, 5000)
    end
  end
end
```

### Test Support Modules
Create these supporting test modules:

```elixir
defmodule Foundation.Perimeter.External.TestContracts do
  use Foundation.Perimeter
  
  external_contract :test_contract do
    field :name, :string, required: true, length: 1..100
    field :value, :integer, required: true, range: 1..1000
  end
end

defmodule Foundation.Perimeter.Services.TestContracts do
  use Foundation.Perimeter
  
  strategic_boundary :test_contract do
    field :name, :string, required: true
    field :value, :integer, required: true
  end
end
```

## Success Criteria

1. **All tests pass** with zero `Process.sleep/1` usage
2. **Performance targets met**: Zone 1 <15ms, Zone 2 <5ms  
3. **Cache hit rate >80%** under load testing
4. **Proper OTP supervision** integration with restart capability
5. **Telemetry events emitted** for all validation operations
6. **Memory efficiency** with bounded cache growth
7. **Concurrent validation support** without contention issues

## Files to Create

1. `lib/foundation/perimeter/validation_service.ex` - Main implementation
2. `test/foundation/perimeter/validation_service_test.exs` - Comprehensive test suite
3. `test/support/perimeter_test_contracts.ex` - Test support contracts

Follow Foundation's testing standards: event-driven coordination, proper isolation, deterministic assertions, and comprehensive error handling.