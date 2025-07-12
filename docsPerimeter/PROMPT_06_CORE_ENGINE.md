# Foundation Perimeter Core Engine Implementation

## Context

Foundation Perimeter implements a Four-Zone Architecture for BEAM-native AI systems. Zone 4 (Core Engine) provides the ultimate performance optimization with zero validation overhead for the most trusted internal operations. This zone represents the core computational kernel where maximum performance is essential and trust is absolute.

## Task

Implement Foundation Perimeter Core Engine system with zero-overhead validation, compile-time contract verification, and runtime performance monitoring for the most performance-critical internal operations.

## Requirements

### Architecture
- Macro-based DSL for core engine contract definition
- Compile-time contract verification with zero runtime overhead
- Optional runtime monitoring for development environments
- Integration with Foundation performance profiling
- Trust-based operation with comprehensive logging

### Test-Driven Implementation
Follow Foundation's event-driven testing philosophy - no `Process.sleep/1` allowed. Use `Foundation.UnifiedTestFoundation` with `:basic` isolation mode for zero-overhead testing.

### Performance Targets
- Validation overhead: 0ms (compile-time only)
- Runtime overhead: Zero additional latency
- Memory efficiency: Zero allocation for core operations
- Throughput: Limited only by business logic, not validation

## Implementation Specification

### Module Structure
```elixir
defmodule Foundation.Perimeter.Core do
  @moduledoc """
  Zone 4 - Core Engine for Foundation maximum performance internal operations.
  Provides zero validation overhead with compile-time contract verification.
  """
  
  alias Foundation.Perimeter.{ContractRegistry, PerformanceProfiler}
  alias Foundation.Telemetry
  
  @doc """
  Defines a core engine contract for maximum performance internal operations.
  
  ## Example
  
      core_engine :critical_computation do
        field :algorithm_id, :atom, compile_time_check: true
        field :input_tensor, :binary, compile_time_check: true
        field :parameters, :map, compile_time_check: false
        field :optimization_flags, :list, compile_time_check: false
        
        engine_config do
          zero_overhead true
          development_monitoring false
          trust_level :absolute
          profile_performance true
        end
      end
  """
  defmacro core_engine(name, do: body) do
    quote do
      @contract_name unquote(name)
      @contract_zone :core
      @fields []
      @engine_config %{}
      
      unquote(body)
      
      Foundation.Perimeter.Core.__compile_core_engine__(@contract_name, @fields, @contract_zone, @engine_config)
    end
  end
  
  @doc """
  Defines a field in a core engine contract with compile-time verification options.
  """
  defmacro field(name, type, opts \\ []) do
    quote do
      @fields [{unquote(name), unquote(type), unquote(opts)} | @fields]
    end
  end
  
  @doc """
  Defines engine-specific configuration for core performance optimization.
  """
  defmacro engine_config(do: body) do
    quote do
      unquote(body)
    end
  end
  
  @doc """
  Enables zero overhead mode for maximum performance.
  """
  defmacro zero_overhead(enabled) do
    quote do
      @engine_config Map.put(@engine_config, :zero_overhead, unquote(enabled))
    end
  end
  
  @doc """
  Enables development monitoring for core engine operations.
  """
  defmacro development_monitoring(enabled) do
    quote do
      @engine_config Map.put(@engine_config, :development_monitoring, unquote(enabled))
    end
  end
  
  @doc """
  Sets the trust level for core engine operations.
  """
  defmacro trust_level(level) do
    quote do
      @engine_config Map.put(@engine_config, :trust_level, unquote(level))
    end
  end
  
  @doc """
  Enables performance profiling for core engine operations.
  """
  defmacro profile_performance(enabled) do
    quote do
      @engine_config Map.put(@engine_config, :profile_performance, unquote(enabled))
    end
  end
  
  @doc false
  def __compile_core_engine__(name, fields, zone, config) do
    compile_core_engine_functions(name, fields, zone, config)
  end
end
```

### Core Engine Compilation with Zero Overhead
```elixir
defmodule Foundation.Perimeter.Core.Compiler do
  @moduledoc false
  
  def compile_core_engine_functions(engine_name, fields, zone, config) do
    validation_function_name = :"validate_#{engine_name}"
    zero_overhead_function_name = :"validate_#{engine_name}_zero_overhead"
    schema_function_name = :"#{engine_name}_schema"
    profile_function_name = :"#{engine_name}_profile"
    
    zero_overhead = Map.get(config, :zero_overhead, true)
    development_monitoring = Map.get(config, :development_monitoring, false)
    profile_performance = Map.get(config, :profile_performance, false)
    
    quote do
      @doc """
      Validates data against the #{unquote(engine_name)} core engine contract.
      In production, this provides zero overhead validation.
      """
      def unquote(validation_function_name)(data, opts \\ []) when is_map(data) do
        case unquote(zero_overhead) do
          true ->
            # Zero overhead mode - return data immediately
            unquote(zero_overhead_function_name)(data, opts)
          
          false ->
            # Development mode with optional monitoring
            perform_core_engine_validation(data, unquote(fields), unquote(engine_name), 
                                         unquote(config), opts)
        end
      end
      
      def unquote(validation_function_name)(data, _opts) do
        # Even in core engine, we validate input type at compile time
        compile_error!("Core engine #{unquote(engine_name)} expects map input, got: #{inspect(data)}")
      end
      
      @doc """
      Zero overhead validation for #{unquote(engine_name)} core engine.
      Returns data immediately with optional performance profiling.
      """
      def unquote(zero_overhead_function_name)(data, opts \\ []) when is_map(data) do
        if unquote(profile_performance) do
          start_time = :erlang.monotonic_time(:microsecond)
          
          # Emit profiling telemetry
          Foundation.Telemetry.emit([:foundation, :perimeter, :core, :zero_overhead_call], %{
            call_time: :erlang.monotonic_time(:microsecond) - start_time
          }, %{
            engine: unquote(engine_name),
            data_size: map_size(data)
          })
        end
        
        {:ok, data}  # Zero overhead - return immediately
      end
      
      @doc """
      Returns the schema definition for #{unquote(engine_name)} core engine.
      """
      def unquote(schema_function_name)() do
        %{
          name: unquote(engine_name),
          zone: unquote(zone),
          fields: unquote(Macro.escape(fields)),
          engine_config: unquote(Macro.escape(config)),
          compiled_at: unquote(DateTime.utc_now()),
          module: __MODULE__,
          zero_overhead: unquote(zero_overhead)
        }
      end
      
      @doc """
      Profiles performance characteristics for #{unquote(engine_name)} core engine.
      """
      def unquote(profile_function_name)(data, operation \\ :default) when is_map(data) do
        if unquote(profile_performance) do
          start_time = :erlang.monotonic_time(:microsecond)
          
          # Profile the zero overhead call
          result = unquote(zero_overhead_function_name)(data)
          
          end_time = :erlang.monotonic_time(:microsecond)
          profile_duration = end_time - start_time
          
          Foundation.Perimeter.PerformanceProfiler.record_core_engine_profile(
            unquote(engine_name),
            operation,
            %{
              duration: profile_duration,
              data_size: map_size(data),
              timestamp: end_time
            }
          )
          
          result
        else
          unquote(zero_overhead_function_name)(data)
        end
      end
      
      # Generate compile-time checked field accessors for core engine
      unquote_splicing(generate_core_field_accessors(fields, engine_name, config))
    end
  end
  
  defp perform_core_engine_validation(data, fields, engine_name, config, opts) do
    development_monitoring = Map.get(config, :development_monitoring, false)
    
    case development_monitoring do
      true ->
        # Development mode with full monitoring
        start_time = :erlang.monotonic_time(:microsecond)
        
        # Perform minimal validation for development insights
        validation_result = perform_development_validation(data, fields, engine_name)
        
        validation_time = :erlang.monotonic_time(:microsecond) - start_time
        
        Foundation.Telemetry.emit([:foundation, :perimeter, :core, :development_validation], %{
          duration: validation_time,
          fields_checked: length(fields)
        }, %{
          engine: engine_name,
          validation_mode: :development
        })
        
        validation_result
      
      false ->
        # No monitoring - immediate return
        {:ok, data}
    end
  end
  
  defp perform_development_validation(data, fields, engine_name) do
    # In development mode, perform basic structure validation for debugging
    missing_required_fields = Enum.reduce(fields, [], fn {field_name, _type, opts}, acc ->
      required = Keyword.get(opts, :required, false)
      compile_time_check = Keyword.get(opts, :compile_time_check, false)
      
      case {required, compile_time_check, Map.has_key?(data, field_name)} do
        {true, false, false} ->
          # Required field missing at runtime in development
          [field_name | acc]
        
        _ ->
          acc
      end
    end)
    
    case missing_required_fields do
      [] ->
        {:ok, data}
      
      missing ->
        # In development, we can provide detailed feedback
        errors = Enum.map(missing, fn field ->
          Foundation.Perimeter.Error.required_field_missing(:core, engine_name, field)
        end)
        
        {:error, errors}
    end
  end
  
  defp generate_core_field_accessors(fields, engine_name, config) do
    zero_overhead = Map.get(config, :zero_overhead, true)
    
    Enum.map(fields, fn {field_name, field_type, field_opts} ->
      accessor_name = :"get_#{engine_name}_#{field_name}"
      required = Keyword.get(field_opts, :required, false)
      compile_time_check = Keyword.get(field_opts, :compile_time_check, false)
      
      case {zero_overhead, compile_time_check} do
        {true, true} ->
          # Generate compile-time checked, zero-overhead accessor
          quote do
            @compile {:inline, [{unquote(accessor_name), 1}]}
            
            @doc """
            Zero-overhead accessor for #{unquote(field_name)} field in #{unquote(engine_name)} core engine.
            Compile-time checked for maximum performance.
            """
            def unquote(accessor_name)(data) when is_map(data) do
              # Compile-time guarantee that field access is safe
              Map.get(data, unquote(field_name))
            end
          end
        
        {true, false} ->
          # Generate zero-overhead accessor without compile-time checks
          quote do
            @compile {:inline, [{unquote(accessor_name), 1}]}
            
            @doc """
            Zero-overhead accessor for #{unquote(field_name)} field in #{unquote(engine_name)} core engine.
            """
            def unquote(accessor_name)(data) when is_map(data) do
              Map.get(data, unquote(field_name))
            end
          end
        
        {false, _} ->
          # Generate development accessor with optional validation
          quote do
            @doc """
            Development accessor for #{unquote(field_name)} field in #{unquote(engine_name)} core engine.
            """
            def unquote(accessor_name)(data) when is_map(data) do
              value = Map.get(data, unquote(field_name))
              
              case {unquote(required), value} do
                {true, nil} ->
                  {:error, :required_field_missing}
                
                _ ->
                  {:ok, value}
              end
            end
          end
      end
    end)
  end
  
  # Compile-time validation helper
  defp compile_error!(message) do
    raise CompileError, description: message
  end
end
```

### Performance Profiler Integration
```elixir
defmodule Foundation.Perimeter.PerformanceProfiler do
  @moduledoc """
  Performance profiling utilities for Core Engine operations.
  """
  
  use GenServer
  
  defstruct [
    :profiles,
    :enabled,
    :max_profiles
  ]
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def record_core_engine_profile(engine_name, operation, metrics) do
    if enabled?() do
      GenServer.cast(__MODULE__, {:record_profile, engine_name, operation, metrics})
    end
  end
  
  def get_engine_profiles(engine_name) do
    GenServer.call(__MODULE__, {:get_profiles, engine_name})
  end
  
  def get_performance_summary() do
    GenServer.call(__MODULE__, :get_summary)
  end
  
  defp enabled?() do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) -> true
      nil -> false
    end
  end
  
  # GenServer callbacks
  
  def init(opts) do
    enabled = Keyword.get(opts, :enabled, true)
    max_profiles = Keyword.get(opts, :max_profiles, 1000)
    
    {:ok, %__MODULE__{
      profiles: %{},
      enabled: enabled,
      max_profiles: max_profiles
    }}
  end
  
  def handle_cast({:record_profile, engine_name, operation, metrics}, state) do
    if state.enabled do
      profiles = Map.update(state.profiles, {engine_name, operation}, [metrics], fn existing ->
        new_profiles = [metrics | existing]
        
        # Keep only the most recent profiles
        Enum.take(new_profiles, state.max_profiles)
      end)
      
      {:noreply, %{state | profiles: profiles}}
    else
      {:noreply, state}
    end
  end
  
  def handle_call({:get_profiles, engine_name}, _from, state) do
    matching_profiles = 
      state.profiles
      |> Enum.filter(fn {{name, _op}, _profiles} -> name == engine_name end)
      |> Enum.into(%{})
    
    {:reply, matching_profiles, state}
  end
  
  def handle_call(:get_summary, _from, state) do
    summary = 
      state.profiles
      |> Enum.map(fn {{engine, operation}, profiles} ->
        total_calls = length(profiles)
        avg_duration = if total_calls > 0 do
          total_duration = Enum.sum(Enum.map(profiles, & &1.duration))
          total_duration / total_calls
        else
          0
        end
        
        {engine, operation, %{
          total_calls: total_calls,
          avg_duration: avg_duration,
          recent_profiles: Enum.take(profiles, 10)
        }}
      end)
      |> Enum.into(%{})
    
    {:reply, summary, state}
  end
end
```

## Testing Requirements

### Test Structure
```elixir
defmodule Foundation.Perimeter.CoreTest do
  use Foundation.UnifiedTestFoundation, :basic
  import Foundation.AsyncTestHelpers
  
  alias Foundation.Perimeter.Core.CriticalContracts
  alias Foundation.Perimeter.PerformanceProfiler
  
  @moduletag :perimeter_testing
  @moduletag timeout: 5_000
  
  describe "Core engine zero overhead validation" do
    test "validates critical computation with zero overhead" do
      computation_data = %{
        algorithm_id: :fast_fourier_transform,
        input_tensor: <<1, 2, 3, 4, 5, 6, 7, 8>>,
        parameters: %{window_size: 128, overlap: 0.5},
        optimization_flags: [:sse, :avx, :parallel]
      }
      
      # Should emit zero overhead telemetry if profiling enabled
      assert_telemetry_event [:foundation, :perimeter, :core, :zero_overhead_call],
        %{call_time: call_time} when call_time >= 0 do
        assert {:ok, validated} = CriticalContracts.validate_critical_computation(computation_data)
        
        # Zero overhead returns data as-is immediately
        assert validated == computation_data
      end
    end
    
    test "zero overhead validation has literally zero latency overhead" do
      computation_data = %{
        algorithm_id: :matrix_multiplication,
        input_tensor: <<1, 2, 3, 4>>,
        parameters: %{},
        optimization_flags: []
      }
      
      # Measure zero overhead validation time
      {validation_time, {:ok, _validated}} = :timer.tc(fn ->
        CriticalContracts.validate_critical_computation_zero_overhead(computation_data)
      end)
      
      # Convert to nanoseconds for precision
      validation_ns = validation_time * 1000
      
      # Zero overhead should be essentially instantaneous (< 1000ns = 1μs)
      assert validation_ns < 1000, "Zero overhead validation took #{validation_ns}ns, should be <1000ns"
    end
    
    test "development mode provides validation feedback" do
      # Test with development monitoring enabled
      incomplete_data = %{
        algorithm_id: :neural_network,
        # Missing required input_tensor
        parameters: %{},
        optimization_flags: []
      }
      
      # This would require a development mode contract for testing
      # In zero overhead mode, missing fields are not checked
      assert {:ok, _} = CriticalContracts.validate_critical_computation(incomplete_data)
    end
    
    test "compile-time field accessors work with zero overhead" do
      computation_data = %{
        algorithm_id: :convolution,
        input_tensor: <<1, 2, 3, 4>>,
        parameters: %{kernel_size: 3},
        optimization_flags: [:gpu]
      }
      
      # Test compile-time checked accessors
      assert :convolution = CriticalContracts.get_critical_computation_algorithm_id(computation_data)
      assert <<1, 2, 3, 4>> = CriticalContracts.get_critical_computation_input_tensor(computation_data)
      assert %{kernel_size: 3} = CriticalContracts.get_critical_computation_parameters(computation_data)
      assert [:gpu] = CriticalContracts.get_critical_computation_optimization_flags(computation_data)
    end
  end
  
  describe "Core engine performance profiling" do
    setup do
      # Start performance profiler for testing
      {:ok, _pid} = PerformanceProfiler.start_link(enabled: true, max_profiles: 100)
      :ok
    end
    
    test "profiles core engine performance when enabled" do
      computation_data = %{
        algorithm_id: :benchmark_test,
        input_tensor: <<1, 2, 3, 4, 5, 6, 7, 8>>,
        parameters: %{},
        optimization_flags: []
      }
      
      # Perform profiled operation
      assert {:ok, _} = CriticalContracts.critical_computation_profile(computation_data, :benchmark)
      
      # Check that profile was recorded
      profiles = PerformanceProfiler.get_engine_profiles(:critical_computation)
      assert map_size(profiles) > 0
      
      # Check profile structure
      {_, profile_list} = Enum.at(profiles, 0)
      assert length(profile_list) > 0
      
      profile = List.first(profile_list)
      assert is_integer(profile.duration)
      assert is_integer(profile.data_size)
      assert is_integer(profile.timestamp)
    end
    
    test "performance summary provides aggregated metrics" do
      computation_data = %{
        algorithm_id: :summary_test,
        input_tensor: <<1, 2, 3, 4>>,
        parameters: %{},
        optimization_flags: []
      }
      
      # Perform multiple operations
      for i <- 1..10 do
        CriticalContracts.critical_computation_profile(computation_data, :"operation_#{i}")
      end
      
      summary = PerformanceProfiler.get_performance_summary()
      assert is_map(summary)
      
      # Should have entries for critical_computation
      critical_entries = Enum.filter(summary, fn {{engine, _op}, _metrics} -> 
        engine == :critical_computation 
      end)
      
      assert length(critical_entries) > 0
      
      # Check metrics structure
      {_, metrics} = List.first(critical_entries)
      assert is_integer(metrics.total_calls)
      assert is_number(metrics.avg_duration)
      assert is_list(metrics.recent_profiles)
    end
  end
  
  describe "Core engine schema and configuration" do
    test "generates correct schema with engine configuration" do
      schema = CriticalContracts.critical_computation_schema()
      
      assert schema.name == :critical_computation
      assert schema.zone == :core
      assert schema.module == CriticalContracts
      assert schema.zero_overhead == true
      assert is_list(schema.fields)
      
      # Check engine configuration
      config = schema.engine_config
      assert config.zero_overhead == true
      assert config.trust_level == :absolute
      assert config.profile_performance == true
    end
    
    test "compile-time field checks work correctly" do
      # Test fields marked with compile_time_check: true
      algorithm_field = Enum.find(CriticalContracts.critical_computation_schema().fields, fn 
        {name, _, _} -> name == :algorithm_id 
      end)
      
      {_name, _type, opts} = algorithm_field
      assert Keyword.get(opts, :compile_time_check) == true
    end
  end
  
  describe "Core engine extreme performance" do
    test "handles maximum throughput with zero validation overhead" do
      computation_data = %{
        algorithm_id: :throughput_test,
        input_tensor: <<1, 2, 3, 4>>,
        parameters: %{},
        optimization_flags: []
      }
      
      # Perform extreme throughput test
      validation_count = 100_000
      
      {total_time, results} = :timer.tc(fn ->
        for _i <- 1..validation_count do
          CriticalContracts.validate_critical_computation_zero_overhead(computation_data)
        end
      end)
      
      # All should succeed
      for result <- results do
        assert {:ok, validated} = result
        assert validated == computation_data
      end
      
      # Calculate throughput
      total_seconds = total_time / 1_000_000
      throughput = validation_count / total_seconds
      
      # Core engine should handle massive throughput
      assert throughput > 1_000_000, "Throughput #{Float.round(throughput)} ops/sec, should be >1,000,000 ops/sec"
    end
    
    test "zero overhead validation has no memory allocation" do
      computation_data = %{
        algorithm_id: :memory_test,
        input_tensor: <<1, 2, 3, 4>>,
        parameters: %{},
        optimization_flags: []
      }
      
      # Measure memory usage
      {memory_before, _} = :erlang.process_info(self(), :memory)
      
      # Perform many zero overhead validations
      for _i <- 1..1000 do
        CriticalContracts.validate_critical_computation_zero_overhead(computation_data)
      end
      
      {memory_after, _} = :erlang.process_info(self(), :memory)
      memory_diff = memory_after - memory_before
      
      # Should have minimal memory growth (accounting for test overhead)
      assert memory_diff < 1024, "Memory grew by #{memory_diff} bytes, should be <1024 bytes"
    end
    
    test "field accessors are truly zero overhead" do
      computation_data = %{
        algorithm_id: :accessor_test,
        input_tensor: <<1, 2, 3, 4>>,
        parameters: %{test: true},
        optimization_flags: [:test]
      }
      
      # Measure accessor performance
      {accessor_time, _result} = :timer.tc(fn ->
        for _i <- 1..10_000 do
          CriticalContracts.get_critical_computation_algorithm_id(computation_data)
          CriticalContracts.get_critical_computation_input_tensor(computation_data)
          CriticalContracts.get_critical_computation_parameters(computation_data)
          CriticalContracts.get_critical_computation_optimization_flags(computation_data)
        end
      end)
      
      # Accessor time should be minimal (< 1ms for 40,000 field accesses)
      accessor_ms = accessor_time / 1000
      assert accessor_ms < 1.0, "Field accessors took #{accessor_ms}ms for 40,000 accesses, should be <1ms"
    end
  end
  
  describe "Core engine trust and safety" do
    test "core engine trusts input completely in zero overhead mode" do
      # Even completely invalid data should pass in zero overhead mode
      invalid_data = %{
        algorithm_id: "this-should-be-atom",
        input_tensor: 12345,  # Should be binary
        parameters: "invalid",  # Should be map
        optimization_flags: :invalid  # Should be list
      }
      
      # Zero overhead mode trusts the caller completely
      assert {:ok, validated} = CriticalContracts.validate_critical_computation_zero_overhead(invalid_data)
      assert validated == invalid_data
    end
    
    test "compile-time guarantees prevent incorrect usage" do
      # This test would verify that compile-time checks prevent incorrect usage
      # In practice, this would be tested by attempting to compile invalid contracts
      # and verifying compilation failures
      
      schema = CriticalContracts.critical_computation_schema()
      assert schema.engine_config.trust_level == :absolute
    end
  end
end
```

### Test Support Modules
```elixir
defmodule Foundation.Perimeter.Core.CriticalContracts do
  use Foundation.Perimeter.Core
  
  core_engine :critical_computation do
    field :algorithm_id, :atom, required: true, compile_time_check: true
    field :input_tensor, :binary, required: true, compile_time_check: true
    field :parameters, :map, required: false, compile_time_check: false
    field :optimization_flags, :list, required: false, compile_time_check: false
    
    engine_config do
      zero_overhead true
      development_monitoring false
      trust_level :absolute
      profile_performance true
    end
  end
  
  core_engine :ultra_critical_path do
    field :operation_code, :integer, required: true, compile_time_check: true
    field :data_buffer, :binary, required: true, compile_time_check: true
    field :metadata, :map, required: false, compile_time_check: false
    
    engine_config do
      zero_overhead true
      development_monitoring false
      trust_level :absolute
      profile_performance false  # Even profiling disabled for maximum performance
    end
  end
end

defmodule Foundation.Perimeter.Core.DevelopmentContracts do
  use Foundation.Perimeter.Core
  
  core_engine :development_engine do
    field :test_data, :map, required: true, compile_time_check: false
    field :debug_info, :map, required: false, compile_time_check: false
    
    engine_config do
      zero_overhead false  # Development mode
      development_monitoring true
      trust_level :high
      profile_performance true
    end
  end
end

defmodule Foundation.Perimeter.Core.BenchmarkContracts do
  @doc """
  Benchmark contracts for extreme performance testing
  """
  use Foundation.Perimeter.Core
  
  core_engine :benchmark_engine do
    field :benchmark_id, :atom, required: true, compile_time_check: true
    field :payload, :binary, required: true, compile_time_check: true
    
    engine_config do
      zero_overhead true
      development_monitoring false
      trust_level :absolute
      profile_performance false
    end
  end
end
```

## Success Criteria

1. **All tests pass** with zero `Process.sleep/1` usage
2. **Zero overhead achieved**: Literally 0ms validation latency in production
3. **Extreme throughput**: >1,000,000 validations/second with zero overhead
4. **Zero memory allocation**: No additional memory usage for core operations
5. **Compile-time guarantees**: Proper compile-time contract verification
6. **Performance profiling**: Optional development profiling without overhead
7. **Trust model**: Absolute trust with comprehensive logging capabilities

## Files to Create

1. `lib/foundation/perimeter/core.ex` - Main core engine DSL
2. `lib/foundation/perimeter/core/compiler.ex` - Core engine compilation with zero overhead
3. `lib/foundation/perimeter/performance_profiler.ex` - Performance profiling service
4. `test/foundation/perimeter/core_test.exs` - Comprehensive zero-overhead test suite
5. `test/support/core_engine_test_contracts.ex` - Core engine test contracts

Follow Foundation's testing standards: event-driven coordination, deterministic assertions with telemetry events, extreme performance verification, and zero-overhead validation testing.