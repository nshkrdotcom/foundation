# Foundation Perimeter ContractRegistry Implementation

## Context

Foundation Perimeter implements a Four-Zone Architecture for BEAM-native AI systems. The ContractRegistry is the central orchestrator that manages contract definitions, discovers available contracts, and provides optimized contract lookup for the ValidationService across all zones.

## Task

Implement `Foundation.Perimeter.ContractRegistry` as a GenServer that provides contract discovery, registration, and optimized access patterns for the Four-Zone Architecture.

## Requirements

### Architecture
- GenServer implementation with proper OTP supervision
- ETS-based contract caching with fast lookup patterns
- Dynamic contract discovery and registration
- Zone-aware contract categorization
- Hot-reloading support for development environments

### Test-Driven Implementation
Follow Foundation's event-driven testing philosophy - no `Process.sleep/1` allowed. Use `Foundation.UnifiedTestFoundation` with `:registry` isolation mode for proper test isolation.

### Performance Targets
- Contract lookup: <1ms for cached contracts
- Contract discovery: <50ms for full module scan
- Memory efficiency: <10MB for typical contract sets
- Concurrent access with zero contention for reads

## Implementation Specification

### Module Structure
```elixir
defmodule Foundation.Perimeter.ContractRegistry do
  @moduledoc """
  Central registry for Foundation Perimeter contract definitions.
  Manages contract discovery, caching, and zone-aware access patterns.
  """
  
  use GenServer
  require Logger
  
  alias Foundation.Perimeter.ValidationService
  alias Foundation.Telemetry
  
  defstruct [
    :contract_cache,
    :module_index,
    :zone_mappings,
    :discovery_cache,
    :hot_reload_enabled
  ]
end
```

### API Functions Required
- `start_link/1` - Start registry with configuration
- `register_contract/3` - Register a contract with zone classification
- `get_contract/2` - Retrieve contract definition with caching
- `discover_contracts/1` - Discover contracts in given modules/paths
- `list_contracts_by_zone/1` - Get all contracts for a specific zone
- `invalidate_cache/1` - Clear cache for specific contract or all
- `get_registry_stats/0` - Retrieve performance and usage metrics

### State Management
```elixir
@type state :: %__MODULE__{
  contract_cache: :ets.tid(),
  module_index: :ets.tid(),
  zone_mappings: zone_mappings(),
  discovery_cache: map(),
  hot_reload_enabled: boolean()
}

@type zone_mappings :: %{
  external: [contract_ref()],
  strategic: [contract_ref()],
  coupling: [contract_ref()],
  core: [contract_ref()]
}

@type contract_ref :: {module(), atom()}

@type contract_definition :: %{
  module: module(),
  name: atom(),
  zone: zone_type(),
  fields: [field_definition()],
  metadata: map(),
  compiled_validator: function()
}

@type zone_type :: :external | :strategic | :coupling | :core
@type field_definition :: %{name: atom(), type: atom(), constraints: map()}
```

### Core Functionality

#### Contract Registration
```elixir
def register_contract(contract_module, contract_name, opts \\ []) do
  GenServer.call(__MODULE__, {:register_contract, contract_module, contract_name, opts})
end

def handle_call({:register_contract, contract_module, contract_name, opts}, _from, state) do
  zone = determine_contract_zone(contract_module, opts)
  
  case build_contract_definition(contract_module, contract_name, zone) do
    {:ok, contract_def} ->
      cache_key = {contract_module, contract_name}
      
      # Store in ETS cache
      :ets.insert(state.contract_cache, {cache_key, contract_def})
      
      # Update zone mappings
      new_zone_mappings = update_zone_mappings(state.zone_mappings, zone, cache_key)
      
      # Update module index for fast discovery
      :ets.insert(state.module_index, {contract_module, contract_name})
      
      new_state = %{state | zone_mappings: new_zone_mappings}
      
      Telemetry.emit([:foundation, :perimeter, :contract, :registered], %{
        contract_count: :ets.info(state.contract_cache, :size)
      }, %{
        module: contract_module,
        name: contract_name,
        zone: zone
      })
      
      {:reply, {:ok, contract_def}, new_state}
    
    {:error, reason} = error ->
      Telemetry.emit([:foundation, :perimeter, :contract, :registration_failed], %{}, %{
        module: contract_module,
        name: contract_name,
        reason: reason
      })
      
      {:reply, error, state}
  end
end
```

#### Contract Lookup with Caching
```elixir
def get_contract(contract_module, contract_name) do
  GenServer.call(__MODULE__, {:get_contract, contract_module, contract_name})
end

def handle_call({:get_contract, contract_module, contract_name}, _from, state) do
  cache_key = {contract_module, contract_name}
  start_time = System.monotonic_time(:microsecond)
  
  case :ets.lookup(state.contract_cache, cache_key) do
    [{^cache_key, contract_def}] ->
      lookup_time = System.monotonic_time(:microsecond) - start_time
      
      Telemetry.emit([:foundation, :perimeter, :contract, :cache_hit], %{
        duration: lookup_time
      }, %{
        module: contract_module,
        name: contract_name
      })
      
      {:reply, {:ok, contract_def}, state}
    
    [] ->
      # Attempt dynamic discovery
      case discover_and_cache_contract(contract_module, contract_name, state) do
        {:ok, contract_def, new_state} ->
          lookup_time = System.monotonic_time(:microsecond) - start_time
          
          Telemetry.emit([:foundation, :perimeter, :contract, :cache_miss_discovered], %{
            duration: lookup_time
          }, %{
            module: contract_module,
            name: contract_name
          })
          
          {:reply, {:ok, contract_def}, new_state}
        
        {:error, :not_found} ->
          lookup_time = System.monotonic_time(:microsecond) - start_time
          
          Telemetry.emit([:foundation, :perimeter, :contract, :not_found], %{
            duration: lookup_time
          }, %{
            module: contract_module,
            name: contract_name
          })
          
          {:reply, {:error, :contract_not_found}, state}
      end
  end
end
```

#### Dynamic Contract Discovery
```elixir
def discover_contracts(module_pattern) do
  GenServer.call(__MODULE__, {:discover_contracts, module_pattern}, 10_000)
end

def handle_call({:discover_contracts, module_pattern}, _from, state) do
  start_time = System.monotonic_time(:microsecond)
  
  case perform_contract_discovery(module_pattern, state) do
    {:ok, discovered_contracts, new_state} ->
      discovery_time = System.monotonic_time(:microsecond) - start_time
      
      Telemetry.emit([:foundation, :perimeter, :discovery, :completed], %{
        duration: discovery_time,
        contracts_found: length(discovered_contracts)
      }, %{
        pattern: module_pattern
      })
      
      {:reply, {:ok, discovered_contracts}, new_state}
    
    {:error, reason} = error ->
      discovery_time = System.monotonic_time(:microsecond) - start_time
      
      Telemetry.emit([:foundation, :perimeter, :discovery, :failed], %{
        duration: discovery_time
      }, %{
        pattern: module_pattern,
        reason: reason
      })
      
      {:reply, error, state}
  end
end

defp perform_contract_discovery(module_pattern, state) do
  try do
    modules = discover_modules_matching(module_pattern)
    contracts = scan_modules_for_contracts(modules)
    
    # Cache discovered contracts
    new_state = cache_discovered_contracts(contracts, state)
    
    {:ok, contracts, new_state}
  rescue
    error ->
      {:error, {:discovery_failed, error}}
  end
end
```

## Testing Requirements

### Test Structure
```elixir
defmodule Foundation.Perimeter.ContractRegistryTest do
  use Foundation.UnifiedTestFoundation, :registry
  import Foundation.AsyncTestHelpers
  
  alias Foundation.Perimeter.ContractRegistry
  alias Foundation.Perimeter.Error
  
  @moduletag :perimeter_testing
  @moduletag timeout: 10_000
  
  describe "ContractRegistry functionality" do
    test "registers and retrieves contracts efficiently", %{test_context: ctx} do
      # Start ContractRegistry in test context
      {:ok, registry_pid} = start_supervised({ContractRegistry, [
        name: :"contract_registry_#{ctx.test_id}",
        registry: ctx.registry_name
      ]})
      
      # Test contract module
      contract_module = Foundation.Perimeter.External.TestContracts
      contract_name = :user_registration
      
      # Register contract should emit telemetry
      assert_telemetry_event [:foundation, :perimeter, :contract, :registered],
        %{contract_count: count} when count > 0 do
        assert {:ok, contract_def} = ContractRegistry.register_contract(
          contract_module, 
          contract_name,
          zone: :external
        )
        assert contract_def.module == contract_module
        assert contract_def.name == contract_name
        assert contract_def.zone == :external
      end
      
      # Subsequent lookup should hit cache
      assert_telemetry_event [:foundation, :perimeter, :contract, :cache_hit],
        %{duration: duration} when duration < 1000 do
        assert {:ok, cached_def} = ContractRegistry.get_contract(contract_module, contract_name)
        assert cached_def.module == contract_module
      end
      
      # Verify performance stats
      stats = ContractRegistry.get_registry_stats()
      assert stats.total_contracts >= 1
      assert stats.cache_hits >= 1
    end
    
    test "discovers contracts dynamically", %{test_context: ctx} do
      {:ok, _registry_pid} = start_supervised({ContractRegistry, [
        name: :"contract_registry_#{ctx.test_id}",
        registry: ctx.registry_name
      ]})
      
      # Discovery should emit telemetry
      assert_telemetry_event [:foundation, :perimeter, :discovery, :completed],
        %{contracts_found: found} when found > 0 do
        assert {:ok, contracts} = ContractRegistry.discover_contracts(
          Foundation.Perimeter.External.*
        )
        assert is_list(contracts)
        assert length(contracts) > 0
      end
      
      # Discovered contracts should be cached
      first_contract = List.first(contracts)
      
      assert_telemetry_event [:foundation, :perimeter, :contract, :cache_hit], %{} do
        assert {:ok, cached} = ContractRegistry.get_contract(
          first_contract.module,
          first_contract.name
        )
        assert cached.module == first_contract.module
      end
    end
    
    test "organizes contracts by zone efficiently", %{test_context: ctx} do
      {:ok, _registry_pid} = start_supervised({ContractRegistry, [
        name: :"contract_registry_#{ctx.test_id}",
        registry: ctx.registry_name
      ]})
      
      # Register contracts in different zones
      external_contract = Foundation.Perimeter.External.TestContracts
      strategic_contract = Foundation.Perimeter.Services.TestContracts
      
      assert {:ok, _} = ContractRegistry.register_contract(
        external_contract, :test_contract, zone: :external
      )
      assert {:ok, _} = ContractRegistry.register_contract(
        strategic_contract, :test_contract, zone: :strategic
      )
      
      # Query by zone
      external_contracts = ContractRegistry.list_contracts_by_zone(:external)
      strategic_contracts = ContractRegistry.list_contracts_by_zone(:strategic)
      
      assert length(external_contracts) >= 1
      assert length(strategic_contracts) >= 1
      
      # Verify zone separation
      external_modules = Enum.map(external_contracts, & &1.module)
      strategic_modules = Enum.map(strategic_contracts, & &1.module)
      
      assert external_contract in external_modules
      assert strategic_contract in strategic_modules
      assert strategic_contract not in external_modules
    end
    
    test "handles contract not found gracefully", %{test_context: ctx} do
      {:ok, _registry_pid} = start_supervised({ContractRegistry, [
        name: :"contract_registry_#{ctx.test_id}",
        registry: ctx.registry_name
      ]})
      
      # Should emit not found telemetry
      assert_telemetry_event [:foundation, :perimeter, :contract, :not_found], %{} do
        assert {:error, :contract_not_found} = ContractRegistry.get_contract(
          NonExistent.Module,
          :nonexistent_contract
        )
      end
    end
  end
  
  describe "ContractRegistry performance" do
    test "meets lookup performance targets", %{test_context: ctx} do
      {:ok, _registry_pid} = start_supervised({ContractRegistry, [
        name: :"contract_registry_#{ctx.test_id}",
        registry: ctx.registry_name
      ]})
      
      # Register test contract
      contract_module = Foundation.Perimeter.External.TestContracts
      contract_name = :performance_test
      
      assert {:ok, _} = ContractRegistry.register_contract(
        contract_module, 
        contract_name,
        zone: :external
      )
      
      # Measure lookup performance
      {lookup_time, {:ok, _contract}} = :timer.tc(fn ->
        ContractRegistry.get_contract(contract_module, contract_name)
      end)
      
      # Convert to milliseconds
      lookup_ms = lookup_time / 1000
      
      # Assert performance target
      assert lookup_ms < 1.0, "Contract lookup took #{lookup_ms}ms, should be <1ms"
    end
    
    test "handles concurrent access efficiently", %{test_context: ctx} do
      {:ok, _registry_pid} = start_supervised({ContractRegistry, [
        name: :"contract_registry_#{ctx.test_id}",
        registry: ctx.registry_name
      ]})
      
      # Register test contract
      contract_module = Foundation.Perimeter.External.TestContracts
      contract_name = :concurrent_test
      
      assert {:ok, _} = ContractRegistry.register_contract(
        contract_module, 
        contract_name,
        zone: :external
      )
      
      # Perform concurrent lookups
      tasks = for i <- 1..20 do
        Task.async(fn ->
          ContractRegistry.get_contract(contract_module, contract_name)
        end)
      end
      
      # All tasks should succeed
      results = Task.await_many(tasks, 5000)
      
      for result <- results do
        assert {:ok, contract_def} = result
        assert contract_def.module == contract_module
      end
      
      # Verify no contention issues
      stats = ContractRegistry.get_registry_stats()
      assert stats.cache_hits >= 20
    end
    
    test "discovery performance meets targets", %{test_context: ctx} do
      {:ok, _registry_pid} = start_supervised({ContractRegistry, [
        name: :"contract_registry_#{ctx.test_id}",
        registry: ctx.registry_name
      ]})
      
      # Measure discovery performance
      {discovery_time, {:ok, contracts}} = :timer.tc(fn ->
        ContractRegistry.discover_contracts(Foundation.Perimeter.External.*)
      end)
      
      # Convert to milliseconds
      discovery_ms = discovery_time / 1000
      
      # Assert performance target
      assert discovery_ms < 50.0, "Discovery took #{discovery_ms}ms, should be <50ms"
      assert length(contracts) > 0, "Should discover at least one contract"
    end
  end
  
  describe "ContractRegistry supervision" do
    test "integrates with Foundation supervision tree", %{test_context: ctx} do
      # Start under test supervisor
      sup_spec = {ContractRegistry, [
        name: :"contract_registry_#{ctx.test_id}",
        registry: ctx.registry_name
      ]}
      
      {:ok, registry_pid} = start_supervised(sup_spec)
      assert Process.alive?(registry_pid)
      
      # Test functionality
      contract_module = Foundation.Perimeter.External.TestContracts
      contract_name = :supervision_test
      
      assert {:ok, _} = ContractRegistry.register_contract(
        contract_module, 
        contract_name,
        zone: :external
      )
      
      # Test restart behavior
      ref = Process.monitor(registry_pid)
      Process.exit(registry_pid, :kill)
      
      # Wait for restart
      assert_receive {:DOWN, ^ref, :process, ^registry_pid, :killed}, 2000
      
      # Should restart and be functional
      wait_for(fn ->
        case ContractRegistry.get_registry_stats() do
          %{total_contracts: 0} -> true  # Fresh start after restart
          _ -> nil
        end
      end, 5000)
    end
    
    test "preserves contract cache across restarts with persistence", %{test_context: ctx} do
      {:ok, _registry_pid} = start_supervised({ContractRegistry, [
        name: :"contract_registry_#{ctx.test_id}",
        registry: ctx.registry_name,
        persistence_enabled: true
      ]})
      
      # Register contract
      contract_module = Foundation.Perimeter.External.TestContracts
      contract_name = :persistence_test
      
      assert {:ok, _} = ContractRegistry.register_contract(
        contract_module, 
        contract_name,
        zone: :external
      )
      
      # Cache should be invalidated after supervisor restart
      # (Real persistence would require additional implementation)
    end
  end
end
```

### Test Support Modules
Create these supporting test modules:

```elixir
defmodule Foundation.Perimeter.External.TestContracts do
  use Foundation.Perimeter
  
  external_contract :user_registration do
    field :email, :string, required: true, format: :email
    field :password, :string, required: true, length: 8..128
    field :name, :string, required: true, length: 1..100
    field :age, :integer, required: false, range: 13..120
  end
  
  external_contract :performance_test do
    field :data, :string, required: true
    field :value, :integer, required: true
  end
  
  external_contract :concurrent_test do
    field :id, :string, required: true
    field :timestamp, :datetime, required: true
  end
end

defmodule Foundation.Perimeter.Services.TestContracts do
  use Foundation.Perimeter
  
  strategic_boundary :test_contract do
    field :service_id, :string, required: true
    field :operation, :atom, required: true
    field :parameters, :map, required: false
  end
end
```

## Success Criteria

1. **All tests pass** with zero `Process.sleep/1` usage
2. **Performance targets met**: <1ms lookup, <50ms discovery
3. **Concurrent access support** without contention issues
4. **Proper OTP supervision** integration with restart capability
5. **Telemetry events emitted** for all contract operations
6. **Memory efficiency** with bounded cache growth
7. **Zone-aware organization** with fast zone-based queries

## Files to Create

1. `lib/foundation/perimeter/contract_registry.ex` - Main implementation
2. `test/foundation/perimeter/contract_registry_test.exs` - Comprehensive test suite
3. `test/support/perimeter_test_contracts.ex` - Extended test contract definitions

Follow Foundation's testing standards: event-driven coordination, proper isolation using `:registry` mode, deterministic assertions with telemetry events, and comprehensive error handling.