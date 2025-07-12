# Foundation Perimeter Testing Strategy

## Overview

Comprehensive testing strategy for Foundation Perimeter implementation ensuring reliability, performance, and correctness across all four zones. This document outlines testing patterns, performance benchmarks, and validation strategies specific to Foundation's BEAM-native AI architecture.

## Testing Architecture

### Test Structure

```
test/foundation/perimeter/
├── unit/                           # Unit tests for individual components
│   ├── validation_service_test.exs
│   ├── contract_registry_test.exs
│   ├── external_contracts_test.exs
│   └── service_boundaries_test.exs
├── integration/                    # Integration tests across zones
│   ├── zone_transition_test.exs
│   ├── foundation_service_test.exs
│   └── jido_integration_test.exs
├── performance/                    # Performance and load testing
│   ├── validation_benchmark_test.exs
│   ├── zone_performance_test.exs
│   └── load_testing_test.exs
├── property/                       # Property-based testing
│   ├── contract_properties_test.exs
│   └── validation_properties_test.exs
└── support/                        # Test support modules
    ├── contract_fixtures.ex
    ├── performance_helpers.ex
    └── foundation_test_helpers.ex
```

## Unit Testing Patterns

### ValidationService Testing

```elixir
defmodule Foundation.Perimeter.ValidationServiceTest do
  use ExUnit.Case, async: true
  use Foundation.TestCase
  
  alias Foundation.Perimeter.ValidationService
  alias Foundation.Perimeter.Error
  
  setup do
    {:ok, pid} = ValidationService.start_link([])
    %{service: pid}
  end
  
  describe "validation with caching" do
    test "caches successful validations", %{service: service} do
      contract_module = TestContracts.External
      contract_name = :test_contract
      data = %{name: "test", value: 42}
      
      # First validation should be a cache miss
      assert {:ok, result1} = ValidationService.validate(contract_module, contract_name, data)
      
      # Second validation should be a cache hit
      assert {:ok, result2} = ValidationService.validate(contract_module, contract_name, data)
      
      assert result1 == result2
      
      # Verify cache hit metrics
      stats = ValidationService.get_performance_stats()
      assert stats.cache_hits >= 1
    end
    
    test "handles cache expiration correctly", %{service: service} do
      # Configure short cache TTL for testing
      ValidationService.update_enforcement_config(%{cache_ttl: 100})
      
      contract_module = TestContracts.External
      contract_name = :test_contract
      data = %{name: "test", value: 42}
      
      # First validation
      assert {:ok, _} = ValidationService.validate(contract_module, contract_name, data)
      
      # Wait for cache expiration
      Process.sleep(150)
      
      # Second validation should be cache miss due to expiration
      assert {:ok, _} = ValidationService.validate(contract_module, contract_name, data)
      
      stats = ValidationService.get_performance_stats()
      assert stats.cache_misses >= 2
    end
  end
  
  describe "enforcement levels" do
    test "strict enforcement returns errors for invalid data", %{service: service} do
      ValidationService.update_enforcement_config(%{external_level: :strict})
      
      contract_module = TestContracts.External
      contract_name = :test_contract
      invalid_data = %{name: "", value: "not_a_number"}
      
      assert {:error, %Error{}} = ValidationService.validate(contract_module, contract_name, invalid_data)
    end
    
    test "none enforcement bypasses validation", %{service: service} do
      ValidationService.update_enforcement_config(%{external_level: :none})
      
      contract_module = TestContracts.External
      contract_name = :test_contract
      invalid_data = %{completely: "invalid", data: "structure"}
      
      # Should pass through without validation
      assert {:ok, ^invalid_data} = ValidationService.validate(contract_module, contract_name, invalid_data)
    end
  end
  
  describe "performance tracking" do
    test "tracks validation performance metrics", %{service: service} do
      contract_module = TestContracts.External
      contract_name = :test_contract
      data = %{name: "test", value: 42}
      
      # Perform several validations
      for _ <- 1..10 do
        ValidationService.validate(contract_module, contract_name, data)
      end
      
      stats = ValidationService.get_performance_stats()
      assert stats.total_validations >= 10
      assert stats.average_validation_time > 0
    end
  end
end
```

### Contract Registry Testing

```elixir
defmodule Foundation.Perimeter.ContractRegistryTest do
  use ExUnit.Case, async: true
  use Foundation.TestCase
  
  alias Foundation.Perimeter.ContractRegistry
  
  setup do
    {:ok, pid} = ContractRegistry.start_link([])
    %{registry: pid}
  end
  
  describe "contract registration" do
    test "registers and retrieves contracts correctly", %{registry: registry} do
      module = TestContracts.External
      contract_name = :test_contract
      contract_spec = %{
        fields: [
          {:required, :name, :string, []},
          {:required, :value, :integer, [min: 0]}
        ],
        validators: []
      }
      
      assert :ok = ContractRegistry.register_contract(module, contract_name, contract_spec)
      assert {:ok, ^contract_spec} = ContractRegistry.get_contract(module, contract_name)
    end
    
    test "compiles validator functions", %{registry: registry} do
      module = TestContracts.External
      contract_name = :test_contract
      contract_spec = %{
        fields: [
          {:required, :name, :string, []},
          {:required, :value, :integer, [min: 0]}
        ],
        validators: []
      }
      
      ContractRegistry.register_contract(module, contract_name, contract_spec)
      
      assert {:ok, validator_fn} = ContractRegistry.compile_validator(module, contract_name)
      assert is_function(validator_fn, 1)
    end
  end
  
  describe "contract discovery" do
    test "auto-discovers contracts from modules" do
      # This test would verify the auto-discovery mechanism
      contracts = ContractRegistry.list_contracts(TestContracts.External)
      assert length(contracts) > 0
    end
  end
end
```

### External Contracts Testing

```elixir
defmodule Foundation.Perimeter.External.DSPExTest do
  use ExUnit.Case, async: true
  use Foundation.TestCase
  
  alias Foundation.Perimeter.External.DSPEx
  
  describe "create_dspex_program contract" do
    test "validates correct DSPEx program creation request" do
      valid_params = %{
        name: "TestProgram",
        description: "A test DSPEx program",
        schema_fields: [
          %{name: :input, type: :string, required: true},
          %{name: :output, type: :string, required: true}
        ],
        signature_spec: %{
          input: %{type: :string},
          output: %{type: :string}
        },
        foundation_context: %{
          node: node(),
          cluster_id: "test_cluster",
          telemetry_scope: :test
        },
        variable_space: [
          %{name: :temperature, type: :float, bounds: %{type: :float, min: 0.0, max: 2.0}}
        ],
        optimization_config: %{
          strategy: :simba,
          generations: 10
        }
      }
      
      assert {:ok, validated} = DSPEx.create_dspex_program(valid_params)
      assert validated.name == "TestProgram"
      assert length(validated.schema_fields) == 2
    end
    
    test "rejects invalid schema fields" do
      invalid_params = %{
        name: "TestProgram",
        schema_fields: [
          %{name: :input, type: :invalid_type, required: true}
        ],
        signature_spec: %{
          input: %{type: :string},
          output: %{type: :string}
        },
        foundation_context: %{
          node: node(),
          cluster_id: "test_cluster",
          telemetry_scope: :test
        }
      }
      
      assert {:error, error} = DSPEx.create_dspex_program(invalid_params)
      assert error.zone == :external
      assert error.contract == :create_dspex_program
    end
    
    test "validates schema-signature compatibility" do
      incompatible_params = %{
        name: "TestProgram",
        schema_fields: [
          %{name: :input, type: :string, required: true},
          %{name: :missing_output, type: :string, required: true}
        ],
        signature_spec: %{
          input: %{type: :string},
          output: %{type: :string}  # Different field name
        },
        foundation_context: %{
          node: node(),
          cluster_id: "test_cluster",
          telemetry_scope: :test
        }
      }
      
      assert {:error, error} = DSPEx.create_dspex_program(incompatible_params)
      assert String.contains?(error.reason, "Schema fields not covered by signature")
    end
  end
end
```

## Integration Testing

### Zone Transition Testing

```elixir
defmodule Foundation.Perimeter.ZoneTransitionTest do
  use ExUnit.Case, async: false
  use Foundation.TestCase
  
  alias Foundation.Perimeter.{ValidationService, External, Services}
  
  setup do
    # Start Foundation services with Perimeter enabled
    start_supervised!({Foundation.Services.Supervisor, [perimeter_enabled: true]})
    :ok
  end
  
  describe "Zone 1 to Zone 2 transitions" do
    test "external validation passes data to service boundaries" do
      # Zone 1: External validation
      external_params = %{
        agent_spec: %{
          type: :task_agent,
          capabilities: [:nlp, :ml],
          initial_state: %{}
        },
        foundation_integration: %{
          registry_integration: true,
          telemetry_integration: true
        },
        deployment_config: %{
          strategy: :load_balanced,
          target_nodes: [node()]
        }
      }
      
      # This should validate at Zone 1 (External perimeter)
      assert {:ok, validated_external} = External.JidoAgent.deploy_jido_agent(external_params)
      
      # Zone 2: Service boundary validation
      service_params = %{
        agent_id: "agent_12345678",
        coordination_context: %{
          pattern: :consensus,
          participants: 3
        },
        optimization_variables: []
      }
      
      # This should validate at Zone 2 (Strategic boundary)
      assert {:ok, validated_service} = Services.MABEAM.coordinate_agent_system(service_params)
      
      # Verify data flowed correctly through zones
      assert validated_external.agent_spec.type == :task_agent
      assert validated_service.coordination_context.pattern == :consensus
    end
  end
  
  describe "Zone 2 to Zone 3 transitions" do
    test "service boundaries enable coupling zone operations" do
      # Zone 2: Strategic boundary
      service_params = %{
        service_id: "foundation_registry_abc12345",
        service_spec: %{
          type: :registry,
          capabilities: [:agent_coordination],
          configuration: %{}
        },
        registry_scope: :local
      }
      
      # Validate at service boundary
      assert {:ok, validated} = Services.Registry.register_foundation_service(service_params)
      
      # Zone 3: Coupling zone should have direct access
      # (This would be tested by verifying Foundation services can call each other directly)
      assert Foundation.Registry.lookup(validated.service_id) == {:ok, validated.service_spec}
    end
  end
end
```

### Foundation Service Integration Testing

```elixir
defmodule Foundation.Perimeter.FoundationServiceTest do
  use ExUnit.Case, async: false
  use Foundation.TestCase
  
  setup do
    start_supervised!({Foundation.Application, []})
    :ok
  end
  
  describe "Foundation.Registry with Perimeter" do
    test "registry operations respect perimeter validation" do
      # Valid registration should succeed
      valid_service_spec = %{
        type: :coordination,
        capabilities: [:agent_coordination],
        configuration: %{timeout: 5000}
      }
      
      assert :ok = Foundation.Registry.register("service_123", valid_service_spec)
      assert {:ok, ^valid_service_spec} = Foundation.Registry.lookup("service_123")
      
      # Invalid registration should fail at perimeter
      invalid_service_spec = %{
        type: :invalid_type,  # Not in allowed enum
        capabilities: [],
        configuration: %{}
      }
      
      assert {:error, _} = Foundation.Registry.register("service_456", invalid_service_spec)
    end
  end
  
  describe "Foundation.MABEAM with Perimeter" do
    test "MABEAM coordination respects strategic boundaries" do
      # Set up test agents
      agent_ids = ["agent_001", "agent_002", "agent_003"]
      
      coordination_params = %{
        agent_group: agent_ids,
        coordination_pattern: :consensus,
        coordination_config: %{
          timeout_ms: 30_000,
          consensus_threshold: 0.67
        },
        foundation_context: %{
          node: node(),
          cluster_id: "test_cluster",
          telemetry_scope: :test
        }
      }
      
      # Should validate at strategic boundary and execute
      assert {:ok, result} = Foundation.MABEAM.coordinate_agents(coordination_params)
      assert result.coordination_pattern == :consensus
    end
  end
end
```

## Performance Testing

### Validation Benchmark Testing

```elixir
defmodule Foundation.Perimeter.ValidationBenchmarkTest do
  use ExUnit.Case, async: false
  use Foundation.TestCase
  
  alias Foundation.Perimeter.{ValidationService, External}
  
  setup do
    {:ok, _} = ValidationService.start_link([])
    :ok
  end
  
  describe "validation performance benchmarks" do
    @tag :benchmark
    test "Zone 1 external validation performance" do
      # Test data
      test_data = %{
        name: "BenchmarkProgram",
        description: "Performance testing DSPEx program",
        schema_fields: [
          %{name: :input, type: :string, required: true},
          %{name: :output, type: :string, required: true}
        ],
        signature_spec: %{
          input: %{type: :string},
          output: %{type: :string}
        },
        foundation_context: %{
          node: node(),
          cluster_id: "benchmark_cluster",
          telemetry_scope: :benchmark
        }
      }
      
      # Benchmark configuration
      iterations = 1000
      
      # Warmup
      for _ <- 1..10 do
        External.DSPEx.create_dspex_program(test_data)
      end
      
      # Benchmark
      start_time = System.monotonic_time(:microsecond)
      
      for _ <- 1..iterations do
        assert {:ok, _} = External.DSPEx.create_dspex_program(test_data)
      end
      
      end_time = System.monotonic_time(:microsecond)
      total_time = end_time - start_time
      avg_time = total_time / iterations
      
      # Performance assertions
      assert avg_time < 15_000, "Zone 1 validation should be under 15ms, got #{avg_time / 1000}ms"
      
      IO.puts("Zone 1 External Validation Performance:")
      IO.puts("  Average time: #{Float.round(avg_time / 1000, 2)}ms")
      IO.puts("  Total iterations: #{iterations}")
      IO.puts("  Total time: #{Float.round(total_time / 1_000_000, 2)}s")
    end
    
    @tag :benchmark
    test "Zone 2 strategic boundary performance" do
      # Similar benchmark for Zone 2 operations
      test_data = %{
        agent_system_id: "12345678-1234-1234-1234-123456789012",
        coordination_context: %{
          pattern: :consensus,
          participants: 3
        },
        optimization_variables: []
      }
      
      iterations = 5000  # More iterations for faster Zone 2
      
      # Warmup
      for _ <- 1..10 do
        Services.MABEAM.coordinate_agent_system(test_data)
      end
      
      # Benchmark
      start_time = System.monotonic_time(:microsecond)
      
      for _ <- 1..iterations do
        assert {:ok, _} = Services.MABEAM.coordinate_agent_system(test_data)
      end
      
      end_time = System.monotonic_time(:microsecond)
      total_time = end_time - start_time
      avg_time = total_time / iterations
      
      # Performance assertions
      assert avg_time < 5_000, "Zone 2 validation should be under 5ms, got #{avg_time / 1000}ms"
      
      IO.puts("Zone 2 Strategic Boundary Performance:")
      IO.puts("  Average time: #{Float.round(avg_time / 1000, 2)}ms")
      IO.puts("  Total iterations: #{iterations}")
    end
  end
  
  describe "cache performance" do
    @tag :benchmark
    test "validation caching effectiveness" do
      test_data = %{
        name: "CacheTest",
        schema_fields: [%{name: :test, type: :string, required: true}],
        signature_spec: %{test: %{type: :string}},
        foundation_context: %{node: node(), cluster_id: "cache", telemetry_scope: :cache}
      }
      
      iterations = 1000
      
      # First run - populate cache
      start_time = System.monotonic_time(:microsecond)
      for _ <- 1..iterations do
        External.DSPEx.create_dspex_program(test_data)
      end
      first_run_time = System.monotonic_time(:microsecond) - start_time
      
      # Second run - should hit cache
      start_time = System.monotonic_time(:microsecond)
      for _ <- 1..iterations do
        External.DSPEx.create_dspex_program(test_data)
      end
      second_run_time = System.monotonic_time(:microsecond) - start_time
      
      # Cache should provide significant speedup
      speedup_ratio = first_run_time / second_run_time
      assert speedup_ratio > 2.0, "Cache should provide at least 2x speedup, got #{Float.round(speedup_ratio, 2)}x"
      
      IO.puts("Cache Performance:")
      IO.puts("  First run (cache miss): #{Float.round(first_run_time / 1000, 2)}ms")
      IO.puts("  Second run (cache hit): #{Float.round(second_run_time / 1000, 2)}ms")
      IO.puts("  Speedup: #{Float.round(speedup_ratio, 2)}x")
    end
  end
end
```

### Load Testing

```elixir
defmodule Foundation.Perimeter.LoadTest do
  use ExUnit.Case, async: false
  use Foundation.TestCase
  
  @tag :load_test
  test "concurrent validation load test" do
    # Start services
    start_supervised!({Foundation.Services.Supervisor, [perimeter_enabled: true]})
    
    # Test configuration
    concurrent_processes = 50
    validations_per_process = 100
    
    test_data = %{
      name: "LoadTestProgram",
      schema_fields: [%{name: :test, type: :string, required: true}],
      signature_spec: %{test: %{type: :string}},
      foundation_context: %{
        node: node(),
        cluster_id: "load_test",
        telemetry_scope: :load_test
      }
    }
    
    # Spawn concurrent validation processes
    tasks = for i <- 1..concurrent_processes do
      Task.async(fn ->
        process_start = System.monotonic_time(:microsecond)
        
        results = for j <- 1..validations_per_process do
          data = Map.put(test_data, :name, "LoadTest_#{i}_#{j}")
          
          case External.DSPEx.create_dspex_program(data) do
            {:ok, _} -> :success
            {:error, _} -> :error
          end
        end
        
        process_end = System.monotonic_time(:microsecond)
        process_time = process_end - process_start
        
        {results, process_time}
      end)
    end
    
    # Collect results
    start_time = System.monotonic_time(:microsecond)
    task_results = Task.await_many(tasks, 30_000)
    end_time = System.monotonic_time(:microsecond)
    
    total_time = end_time - start_time
    
    # Analyze results
    total_validations = concurrent_processes * validations_per_process
    successful_validations = task_results
    |> Enum.flat_map(fn {results, _time} -> results end)
    |> Enum.count(&(&1 == :success))
    
    success_rate = successful_validations / total_validations
    throughput = total_validations / (total_time / 1_000_000)  # validations per second
    
    # Assertions
    assert success_rate > 0.95, "Success rate should be > 95%, got #{Float.round(success_rate * 100, 2)}%"
    assert throughput > 1000, "Throughput should be > 1000 validations/sec, got #{Float.round(throughput, 2)}"
    
    IO.puts("Load Test Results:")
    IO.puts("  Concurrent processes: #{concurrent_processes}")
    IO.puts("  Validations per process: #{validations_per_process}")
    IO.puts("  Total validations: #{total_validations}")
    IO.puts("  Successful validations: #{successful_validations}")
    IO.puts("  Success rate: #{Float.round(success_rate * 100, 2)}%")
    IO.puts("  Total time: #{Float.round(total_time / 1_000_000, 2)}s")
    IO.puts("  Throughput: #{Float.round(throughput, 2)} validations/sec")
  end
end
```

## Property-Based Testing

### Contract Properties

```elixir
defmodule Foundation.Perimeter.ContractPropertiesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  
  alias Foundation.Perimeter.External.DSPEx
  
  describe "DSPEx contract properties" do
    property "valid DSPEx programs always validate successfully" do
      check all name <- string(:alphanumeric, min_length: 1, max_length: 100),
                description <- string(:printable, max_length: 1000),
                field_count <- integer(1..10),
                schema_fields <- list_of(valid_schema_field(), length: field_count) do
        
        params = %{
          name: name,
          description: description,
          schema_fields: schema_fields,
          signature_spec: generate_matching_signature(schema_fields),
          foundation_context: %{
            node: node(),
            cluster_id: "property_test",
            telemetry_scope: :property_test
          }
        }
        
        assert {:ok, _} = DSPEx.create_dspex_program(params)
      end
    end
    
    property "invalid names always cause validation failure" do
      check all invalid_name <- one_of([
                  string(:printable, max_length: 0),  # Empty string
                  string(:printable, min_length: 101), # Too long
                  constant("")                         # Empty
                ]) do
        
        params = %{
          name: invalid_name,
          schema_fields: [%{name: :test, type: :string, required: true}],
          signature_spec: %{test: %{type: :string}},
          foundation_context: %{
            node: node(),
            cluster_id: "property_test",
            telemetry_scope: :property_test
          }
        }
        
        assert {:error, _} = DSPEx.create_dspex_program(params)
      end
    end
  end
  
  # Property generators
  defp valid_schema_field do
    gen all name <- atom(:alphanumeric),
            type <- member_of([:string, :integer, :float, :boolean]),
            required <- boolean() do
      %{name: name, type: type, required: required}
    end
  end
  
  defp generate_matching_signature(schema_fields) do
    Enum.reduce(schema_fields, %{}, fn %{name: name, type: type}, acc ->
      Map.put(acc, name, %{type: type})
    end)
  end
end
```

## Test Support Modules

### Contract Fixtures

```elixir
defmodule Foundation.Perimeter.ContractFixtures do
  @moduledoc """
  Test fixtures for Foundation Perimeter contracts.
  """
  
  def valid_dspex_program_params do
    %{
      name: "TestProgram",
      description: "A test DSPEx program for unit testing",
      schema_fields: [
        %{name: :input, type: :string, required: true},
        %{name: :context, type: :string, required: false},
        %{name: :output, type: :string, required: true}
      ],
      signature_spec: %{
        input: %{type: :string},
        context: %{type: :string},
        output: %{type: :string}
      },
      foundation_context: %{
        node: node(),
        cluster_id: "test_cluster",
        telemetry_scope: :test
      },
      variable_space: [
        %{
          name: :temperature,
          type: :float,
          bounds: %{type: :float, min: 0.0, max: 2.0},
          default: 0.7
        }
      ],
      optimization_config: %{
        strategy: :simba,
        generations: 10,
        population_size: 20
      }
    }
  end
  
  def valid_jido_agent_params do
    %{
      agent_spec: %{
        type: :task_agent,
        capabilities: [:nlp, :ml, :reasoning],
        initial_state: %{status: :idle, tasks_completed: 0}
      },
      foundation_integration: %{
        registry_integration: true,
        telemetry_integration: true,
        coordination_patterns: [:consensus, :pipeline],
        protocol_bindings: [
          %{
            foundation_protocol: :foundation_coordination,
            agent_handler: :handle_coordination,
            transformation: :none
          }
        ]
      },
      deployment_config: %{
        strategy: :load_balanced,
        target_nodes: [node()],
        health_check_interval: 30_000
      },
      clustering_config: %{
        enabled: true,
        strategy: :capability_matched,
        nodes: 3,
        replication_factor: 2,
        consistency_level: :eventual
      }
    }
  end
  
  def invalid_dspex_program_params do
    %{
      name: "",  # Invalid: empty name
      schema_fields: [
        %{name: :input, type: :invalid_type, required: true}  # Invalid type
      ],
      signature_spec: %{
        different_field: %{type: :string}  # Mismatch with schema
      },
      foundation_context: %{
        # Missing required fields
        node: node()
      }
    }
  end
end
```

### Performance Helpers

```elixir
defmodule Foundation.Perimeter.PerformanceHelpers do
  @moduledoc """
  Helpers for performance testing and benchmarking.
  """
  
  def benchmark(name, iterations, fun) do
    # Warmup
    for _ <- 1..div(iterations, 10) do
      fun.()
    end
    
    # Actual benchmark
    start_time = System.monotonic_time(:microsecond)
    
    for _ <- 1..iterations do
      fun.()
    end
    
    end_time = System.monotonic_time(:microsecond)
    total_time = end_time - start_time
    avg_time = total_time / iterations
    
    %{
      name: name,
      iterations: iterations,
      total_time_us: total_time,
      average_time_us: avg_time,
      throughput_per_sec: 1_000_000 / avg_time
    }
  end
  
  def assert_performance(benchmark_result, max_avg_time_ms) do
    avg_time_ms = benchmark_result.average_time_us / 1000
    
    if avg_time_ms > max_avg_time_ms do
      ExUnit.Assertions.flunk(
        "Performance assertion failed for #{benchmark_result.name}: " <>
        "expected average time ≤ #{max_avg_time_ms}ms, got #{Float.round(avg_time_ms, 2)}ms"
      )
    end
    
    benchmark_result
  end
  
  def print_benchmark_results(results) when is_list(results) do
    IO.puts("\nBenchmark Results:")
    IO.puts(String.duplicate("=", 60))
    
    Enum.each(results, &print_benchmark_result/1)
  end
  
  def print_benchmark_result(result) do
    IO.puts("#{result.name}:")
    IO.puts("  Iterations: #{result.iterations}")
    IO.puts("  Total time: #{Float.round(result.total_time_us / 1_000_000, 3)}s")
    IO.puts("  Average time: #{Float.round(result.average_time_us / 1000, 3)}ms")
    IO.puts("  Throughput: #{Float.round(result.throughput_per_sec, 0)} ops/sec")
    IO.puts("")
  end
end
```

This comprehensive testing strategy ensures Foundation Perimeter maintains high quality, performance, and reliability standards while providing clear validation of the four-zone architecture's effectiveness.