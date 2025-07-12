# Foundation Perimeter Service Boundaries Implementation

## Context

Foundation Perimeter implements a Four-Zone Architecture for BEAM-native AI systems. Zone 2 (Strategic Boundaries) provides balanced validation for internal service interactions with performance optimization while maintaining security. This zone focuses on efficient service-to-service communication with configurable validation levels.

## Task

Implement Foundation Perimeter Service Boundary system with optimized validation functions, service discovery integration, and dynamic enforcement levels based on service trust relationships.

## Requirements

### Architecture
- Macro-based DSL for service boundary contract definition
- Compile-time optimization with runtime flexibility
- Service trust levels and adaptive validation
- Integration with Foundation service discovery
- Performance-optimized validation with caching

### Test-Driven Implementation
Follow Foundation's event-driven testing philosophy - no `Process.sleep/1` allowed. Use `Foundation.UnifiedTestFoundation` with `:registry` isolation mode for service interaction testing.

### Performance Targets
- Validation speed: <5ms for typical service payloads
- Cache hit rate: >90% for repeated service calls
- Service discovery: <10ms for trusted service lookup
- Memory efficiency: Optimized for high-throughput service communication

## Implementation Specification

### Module Structure
```elixir
defmodule Foundation.Perimeter.Services do
  @moduledoc """
  Zone 2 - Strategic Boundaries for Foundation service interactions.
  Provides balanced validation with performance optimization for internal services.
  """
  
  alias Foundation.Perimeter.{ValidationService, ContractRegistry, ServiceTrust}
  alias Foundation.Services.Discovery
  alias Foundation.Telemetry
  
  @doc """
  Defines a strategic boundary contract for service-to-service communication.
  
  ## Example
  
      strategic_boundary :task_execution do
        field :task_id, :string, required: true, format: :uuid
        field :task_type, :atom, required: true, in: [:compute, :io, :network]
        field :parameters, :map, required: false
        field :priority, :integer, required: false, range: 1..10, default: 5
        field :timeout_ms, :integer, required: false, range: 1000..300000, default: 30000
        
        service_metadata do
          trust_level :high
          cache_ttl 300
          bypass_validation_for [:internal_scheduler, :task_pool_manager]
        end
      end
  """
  defmacro strategic_boundary(name, do: body) do
    quote do
      @contract_name unquote(name)
      @contract_zone :strategic
      @fields []
      @service_metadata %{}
      
      unquote(body)
      
      Foundation.Perimeter.Services.__compile_boundary__(@contract_name, @fields, @contract_zone, @service_metadata)
    end
  end
  
  @doc """
  Defines a field in a service boundary contract with validation constraints.
  """
  defmacro field(name, type, opts \\ []) do
    quote do
      @fields [{unquote(name), unquote(type), unquote(opts)} | @fields]
    end
  end
  
  @doc """
  Defines service-specific metadata for performance and trust optimization.
  """
  defmacro service_metadata(do: body) do
    quote do
      unquote(body)
    end
  end
  
  @doc """
  Sets the trust level for this service boundary.
  """
  defmacro trust_level(level) do
    quote do
      @service_metadata Map.put(@service_metadata, :trust_level, unquote(level))
    end
  end
  
  @doc """
  Sets cache TTL for validation results.
  """
  defmacro cache_ttl(seconds) do
    quote do
      @service_metadata Map.put(@service_metadata, :cache_ttl, unquote(seconds))
    end
  end
  
  @doc """
  Defines services that can bypass validation for this boundary.
  """
  defmacro bypass_validation_for(services) do
    quote do
      @service_metadata Map.put(@service_metadata, :bypass_services, unquote(services))
    end
  end
  
  @doc false
  def __compile_boundary__(name, fields, zone, metadata) do
    compile_service_boundary_functions(name, fields, zone, metadata)
  end
end
```

### Service Boundary Compilation
```elixir
defmodule Foundation.Perimeter.Services.Compiler do
  @moduledoc false
  
  def compile_service_boundary_functions(boundary_name, fields, zone, metadata) do
    validation_function_name = :"validate_#{boundary_name}"
    schema_function_name = :"#{boundary_name}_schema"
    trust_function_name = :"#{boundary_name}_trust_check"
    
    quote do
      @doc """
      Validates data against the #{unquote(boundary_name)} service boundary.
      Includes service trust checking and adaptive validation.
      """
      def unquote(validation_function_name)(data, opts \\ []) when is_map(data) do
        start_time = System.monotonic_time(:microsecond)
        calling_service = Keyword.get(opts, :calling_service)
        enforcement_level = Keyword.get(opts, :enforcement_level, :default)
        
        case check_service_trust_and_validation_needs(calling_service, unquote(boundary_name), unquote(metadata)) do
          :bypass_validation ->
            validation_time = System.monotonic_time(:microsecond) - start_time
            
            Foundation.Telemetry.emit([:foundation, :perimeter, :services, :validation_bypassed], %{
              duration: validation_time
            }, %{
              boundary: unquote(boundary_name),
              calling_service: calling_service,
              zone: unquote(zone)
            })
            
            {:ok, data}  # Trusted service, return data as-is
          
          validation_mode when validation_mode in [:full, :minimal, :cached] ->
            perform_service_validation(data, unquote(fields), unquote(boundary_name), 
                                     unquote(metadata), validation_mode, calling_service, start_time)
        end
      end
      
      def unquote(validation_function_name)(data, _opts) do
        {:error, [Foundation.Perimeter.Error.type_error(:service_boundary_input, data, :map)]}
      end
      
      @doc """
      Returns the schema definition for #{unquote(boundary_name)} boundary.
      """
      def unquote(schema_function_name)() do
        %{
          name: unquote(boundary_name),
          zone: unquote(zone),
          fields: unquote(Macro.escape(fields)),
          service_metadata: unquote(Macro.escape(metadata)),
          compiled_at: unquote(DateTime.utc_now()),
          module: __MODULE__
        }
      end
      
      @doc """
      Checks trust level for calling service against this boundary.
      """
      def unquote(trust_function_name)(calling_service) do
        check_service_trust_and_validation_needs(calling_service, unquote(boundary_name), unquote(metadata))
      end
      
      # Generate optimized field validators for service boundaries
      unquote_splicing(generate_service_field_validators(fields, boundary_name))
    end
  end
  
  defp check_service_trust_and_validation_needs(calling_service, boundary_name, metadata) do
    bypass_services = Map.get(metadata, :bypass_services, [])
    trust_level = Map.get(metadata, :trust_level, :medium)
    
    cond do
      calling_service in bypass_services ->
        :bypass_validation
      
      trust_level == :high and is_trusted_service?(calling_service) ->
        :minimal
      
      has_recent_validation_cache?(calling_service, boundary_name, metadata) ->
        :cached
      
      true ->
        :full
    end
  end
  
  defp is_trusted_service?(service_name) do
    case Foundation.Services.Discovery.get_service_metadata(service_name) do
      {:ok, %{trust_level: level}} when level in [:high, :trusted] -> true
      {:ok, %{internal: true}} -> true
      _ -> false
    end
  end
  
  defp has_recent_validation_cache?(calling_service, boundary_name, metadata) do
    cache_ttl = Map.get(metadata, :cache_ttl, 60)  # Default 60 seconds
    cache_key = {calling_service, boundary_name, :validation_cache}
    
    case Foundation.Perimeter.ValidationService.get_cached_validation(cache_key) do
      {:ok, cached_at} ->
        age_seconds = System.system_time(:second) - cached_at
        age_seconds < cache_ttl
      
      {:error, :not_found} ->
        false
    end
  end
  
  defp perform_service_validation(data, fields, boundary_name, metadata, validation_mode, calling_service, start_time) do
    case validation_mode do
      :cached ->
        handle_cached_validation(data, boundary_name, calling_service, start_time)
      
      :minimal ->
        handle_minimal_validation(data, fields, boundary_name, calling_service, start_time)
      
      :full ->
        handle_full_validation(data, fields, boundary_name, metadata, calling_service, start_time)
    end
  end
  
  defp handle_cached_validation(data, boundary_name, calling_service, start_time) do
    validation_time = System.monotonic_time(:microsecond) - start_time
    
    Foundation.Telemetry.emit([:foundation, :perimeter, :services, :validation_cached], %{
      duration: validation_time
    }, %{
      boundary: boundary_name,
      calling_service: calling_service
    })
    
    {:ok, data}
  end
  
  defp handle_minimal_validation(data, fields, boundary_name, calling_service, start_time) do
    # Only validate required fields and basic types for trusted services
    required_fields = Enum.filter(fields, fn {_name, _type, opts} -> 
      Keyword.get(opts, :required, false) 
    end)
    
    case perform_field_validation(data, required_fields, boundary_name, :minimal) do
      {:ok, validated} = success ->
        validation_time = System.monotonic_time(:microsecond) - start_time
        
        Foundation.Telemetry.emit([:foundation, :perimeter, :services, :validation_minimal], %{
          duration: validation_time,
          fields_validated: length(required_fields)
        }, %{
          boundary: boundary_name,
          calling_service: calling_service
        })
        
        success
      
      {:error, errors} = failure ->
        validation_time = System.monotonic_time(:microsecond) - start_time
        
        Foundation.Telemetry.emit([:foundation, :perimeter, :services, :validation_failed], %{
          duration: validation_time,
          error_count: length(errors)
        }, %{
          boundary: boundary_name,
          calling_service: calling_service,
          validation_mode: :minimal
        })
        
        failure
    end
  end
  
  defp handle_full_validation(data, fields, boundary_name, metadata, calling_service, start_time) do
    case perform_field_validation(data, fields, boundary_name, :full) do
      {:ok, validated} = success ->
        validation_time = System.monotonic_time(:microsecond) - start_time
        
        # Cache successful validation
        cache_ttl = Map.get(metadata, :cache_ttl, 60)
        cache_key = {calling_service, boundary_name, :validation_cache}
        Foundation.Perimeter.ValidationService.cache_validation_result(cache_key, System.system_time(:second), cache_ttl)
        
        Foundation.Telemetry.emit([:foundation, :perimeter, :services, :validation_success], %{
          duration: validation_time,
          fields_validated: length(fields)
        }, %{
          boundary: boundary_name,
          calling_service: calling_service,
          validation_mode: :full
        })
        
        success
      
      {:error, errors} = failure ->
        validation_time = System.monotonic_time(:microsecond) - start_time
        
        Foundation.Telemetry.emit([:foundation, :perimeter, :services, :validation_failed], %{
          duration: validation_time,
          error_count: length(errors)
        }, %{
          boundary: boundary_name,
          calling_service: calling_service,
          validation_mode: :full
        })
        
        failure
    end
  end
  
  defp perform_field_validation(data, fields, boundary_name, validation_mode) do
    validated_fields = %{}
    errors = []
    
    {validated, errors} = Enum.reduce(fields, {validated_fields, errors}, fn 
      {field_name, field_type, field_opts}, {acc_validated, acc_errors} ->
        case validate_service_field(data, field_name, field_type, field_opts, boundary_name, validation_mode) do
          {:ok, value} ->
            {Map.put(acc_validated, field_name, value), acc_errors}
          
          {:error, field_errors} when is_list(field_errors) ->
            {acc_validated, acc_errors ++ field_errors}
          
          {:error, field_error} ->
            {acc_validated, [field_error | acc_errors]}
        end
    end)
    
    case errors do
      [] -> {:ok, validated}
      _ -> {:error, Enum.reverse(errors)}
    end
  end
  
  defp validate_service_field(data, field_name, field_type, field_opts, boundary_name, validation_mode) do
    required = Keyword.get(field_opts, :required, false)
    default = Keyword.get(field_opts, :default)
    
    case Map.get(data, field_name, Map.get(data, to_string(field_name))) do
      nil when required ->
        {:error, Foundation.Perimeter.Error.required_field_missing(
          :strategic, boundary_name, field_name
        )}
      
      nil when not is_nil(default) ->
        validate_service_field_type(default, field_name, field_type, field_opts, boundary_name, validation_mode)
      
      nil ->
        {:ok, nil}
      
      value ->
        validate_service_field_type(value, field_name, field_type, field_opts, boundary_name, validation_mode)
    end
  end
  
  defp validate_service_field_type(value, field_name, field_type, field_opts, boundary_name, validation_mode) do
    # For service boundaries, we can be more lenient with type conversion
    # and constraint checking based on validation mode
    
    with {:ok, typed_value} <- validate_service_base_type(value, field_type, field_name, boundary_name),
         {:ok, constrained_value} <- validate_service_constraints(typed_value, field_opts, field_name, boundary_name, validation_mode) do
      {:ok, constrained_value}
    end
  end
  
  # Service boundary type validation - more lenient than external contracts
  defp validate_service_base_type(value, :string, _field_name, _boundary_name) when is_binary(value), do: {:ok, value}
  defp validate_service_base_type(value, :string, _field_name, _boundary_name) when is_atom(value), do: {:ok, Atom.to_string(value)}
  
  defp validate_service_base_type(value, :atom, _field_name, _boundary_name) when is_atom(value), do: {:ok, value}
  defp validate_service_base_type(value, :atom, _field_name, _boundary_name) when is_binary(value) do
    try do
      {:ok, String.to_existing_atom(value)}
    rescue
      ArgumentError -> {:ok, String.to_atom(value)}  # More lenient for services
    end
  end
  
  defp validate_service_base_type(value, :integer, _field_name, _boundary_name) when is_integer(value), do: {:ok, value}
  defp validate_service_base_type(value, :integer, field_name, boundary_name) when is_binary(value) do
    case Integer.parse(value) do
      {int_val, ""} -> {:ok, int_val}
      _ -> {:error, Foundation.Perimeter.Error.type_error(:strategic, field_name, value, :integer)}
    end
  end
  
  defp validate_service_base_type(value, :map, _field_name, _boundary_name) when is_map(value), do: {:ok, value}
  defp validate_service_base_type(value, :list, _field_name, _boundary_name) when is_list(value), do: {:ok, value}
  
  # UUID format validation for service boundaries
  defp validate_service_base_type(value, :uuid, field_name, boundary_name) when is_binary(value) do
    uuid_regex = ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    if Regex.match?(uuid_regex, value) do
      {:ok, value}
    else
      {:error, Foundation.Perimeter.Error.type_error(:strategic, field_name, value, :uuid)}
    end
  end
  
  # Fallback
  defp validate_service_base_type(value, expected_type, field_name, boundary_name) do
    {:error, Foundation.Perimeter.Error.type_error(:strategic, field_name, value, expected_type)}
  end
  
  defp validate_service_constraints(value, field_opts, field_name, boundary_name, validation_mode) do
    # In minimal validation mode, skip non-critical constraints
    constraints_to_check = case validation_mode do
      :minimal -> [:required, :in]  # Only check critical constraints
      _ -> field_opts  # Check all constraints
    end
    
    Enum.reduce_while(constraints_to_check, {:ok, value}, fn
      {:required, _}, acc -> {:cont, acc}
      {:default, _}, acc -> {:cont, acc}
      
      {:in, choices}, {:ok, val} ->
        if val in choices do
          {:cont, {:ok, val}}
        else
          {:halt, {:error, Foundation.Perimeter.Error.constraint_error(
            :strategic, field_name, val, :choice, "must be one of: #{inspect(choices)}"
          )}}
        end
      
      {:range, range}, {:ok, val} when is_number(val) and validation_mode != :minimal ->
        validate_service_range_constraint(val, range, field_name, boundary_name)
      
      {:format, format}, {:ok, val} when is_binary(val) and validation_mode != :minimal ->
        validate_service_format_constraint(val, format, field_name, boundary_name)
      
      {_constraint_name, _constraint_value}, {:ok, _val} ->
        {:cont, {:ok, value}}  # Skip other constraints in minimal mode or unknown constraints
    end)
  end
  
  defp validate_service_range_constraint(value, min..max, field_name, boundary_name) do
    if value >= min and value <= max do
      {:cont, {:ok, value}}
    else
      {:halt, {:error, Foundation.Perimeter.Error.constraint_error(
        :strategic, field_name, value, :range, "must be between #{min} and #{max}"
      )}}
    end
  end
  
  defp validate_service_format_constraint(value, :uuid, field_name, boundary_name) do
    uuid_regex = ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    if Regex.match?(uuid_regex, value) do
      {:cont, {:ok, value}}
    else
      {:halt, {:error, Foundation.Perimeter.Error.constraint_error(
        :strategic, field_name, value, :format, "must be a valid UUID"
      )}}
    end
  end
  
  defp validate_service_format_constraint(value, regex, field_name, boundary_name) when is_struct(regex, Regex) do
    if Regex.match?(regex, value) do
      {:cont, {:ok, value}}
    else
      {:halt, {:error, Foundation.Perimeter.Error.constraint_error(
        :strategic, field_name, value, :format, "does not match required format"
      )}}
    end
  end
  
  defp generate_service_field_validators(fields, boundary_name) do
    Enum.map(fields, fn {field_name, field_type, field_opts} ->
      validator_name = :"validate_#{boundary_name}_#{field_name}"
      
      quote do
        @doc """
        Validates the #{unquote(field_name)} field for #{unquote(boundary_name)} service boundary.
        """
        def unquote(validator_name)(value, opts \\ []) do
          validation_mode = Keyword.get(opts, :validation_mode, :full)
          validate_service_field_type(value, unquote(field_name), unquote(field_type), 
                                     unquote(field_opts), unquote(boundary_name), validation_mode)
        end
      end
    end)
  end
end
```

## Testing Requirements

### Test Structure
```elixir
defmodule Foundation.Perimeter.ServicesTest do
  use Foundation.UnifiedTestFoundation, :registry
  import Foundation.AsyncTestHelpers
  
  alias Foundation.Perimeter.Services.TaskBoundaries
  alias Foundation.Perimeter.Error
  
  @moduletag :perimeter_testing
  @moduletag timeout: 10_000
  
  describe "Service boundary validation" do
    test "validates task execution boundary with full validation", %{test_context: ctx} do
      valid_task_data = %{
        task_id: "550e8400-e29b-41d4-a716-446655440000",
        task_type: :compute,
        parameters: %{input: "test", output_format: :json},
        priority: 5,
        timeout_ms: 30000
      }
      
      # Should emit success telemetry for full validation
      assert_telemetry_event [:foundation, :perimeter, :services, :validation_success],
        %{duration: duration, validation_mode: :full} when duration > 0 do
        assert {:ok, validated} = TaskBoundaries.validate_task_execution(valid_task_data)
        
        assert validated.task_id == "550e8400-e29b-41d4-a716-446655440000"
        assert validated.task_type == :compute
        assert validated.priority == 5
      end
    end
    
    test "bypasses validation for trusted services", %{test_context: ctx} do
      task_data = %{
        task_id: "invalid-uuid",  # Would normally fail validation
        task_type: :compute,
        parameters: %{},
        priority: 5
      }
      
      # Should emit bypass telemetry for trusted service
      assert_telemetry_event [:foundation, :perimeter, :services, :validation_bypassed],
        %{calling_service: :task_pool_manager} do
        assert {:ok, bypassed} = TaskBoundaries.validate_task_execution(
          task_data,
          calling_service: :task_pool_manager
        )
        
        # Data returned as-is without validation
        assert bypassed.task_id == "invalid-uuid"
      end
    end
    
    test "performs minimal validation for trusted services not in bypass list", %{test_context: ctx} do
      task_data = %{
        task_id: "550e8400-e29b-41d4-a716-446655440000",
        task_type: :compute,
        # Missing optional fields should be OK in minimal mode
        priority: 15  # Out of range but might be allowed in minimal mode
      }
      
      # Mock trusted service that's not in bypass list
      with_mock Foundation.Services.Discovery, [], [
        get_service_metadata: fn(:trusted_service) -> 
          {:ok, %{trust_level: :high, internal: true}} 
        end
      ] do
        
        assert_telemetry_event [:foundation, :perimeter, :services, :validation_minimal],
          %{calling_service: :trusted_service} do
          result = TaskBoundaries.validate_task_execution(
            task_data,
            calling_service: :trusted_service
          )
          
          # Should succeed with minimal validation
          assert {:ok, validated} = result
          assert validated.task_type == :compute
        end
      end
    end
    
    test "uses cached validation for repeat calls", %{test_context: ctx} do
      valid_task_data = %{
        task_id: "550e8400-e29b-41d4-a716-446655440000",
        task_type: :compute,
        parameters: %{},
        priority: 5
      }
      
      calling_service = :regular_service
      
      # First call should do full validation
      assert_telemetry_event [:foundation, :perimeter, :services, :validation_success],
        %{validation_mode: :full} do
        assert {:ok, _} = TaskBoundaries.validate_task_execution(
          valid_task_data,
          calling_service: calling_service
        )
      end
      
      # Second call within cache TTL should use cache
      assert_telemetry_event [:foundation, :perimeter, :services, :validation_cached],
        %{calling_service: ^calling_service} do
        assert {:ok, _} = TaskBoundaries.validate_task_execution(
          valid_task_data,
          calling_service: calling_service
        )
      end
    end
    
    test "handles service boundary validation errors", %{test_context: ctx} do
      invalid_task_data = %{
        task_id: "not-a-uuid",
        task_type: :invalid_type,
        parameters: "not-a-map",
        priority: 100  # Out of range
      }
      
      assert_telemetry_event [:foundation, :perimeter, :services, :validation_failed],
        %{error_count: count} when count > 0 do
        assert {:error, errors} = TaskBoundaries.validate_task_execution(invalid_task_data)
        
        assert is_list(errors)
        assert length(errors) > 0
        
        # Check for specific error types
        error_fields = Enum.map(errors, & &1.field)
        assert :task_id in error_fields
        assert :task_type in error_fields
      end
    end
  end
  
  describe "Service boundary performance" do
    test "meets performance targets for service validation", %{test_context: ctx} do
      valid_task_data = %{
        task_id: "550e8400-e29b-41d4-a716-446655440000",
        task_type: :compute,
        parameters: %{},
        priority: 5
      }
      
      # Measure validation time
      {validation_time, {:ok, _validated}} = :timer.tc(fn ->
        TaskBoundaries.validate_task_execution(valid_task_data)
      end)
      
      # Convert to milliseconds
      validation_ms = validation_time / 1000
      
      # Assert performance target for Zone 2 (Strategic)
      assert validation_ms < 5.0, "Service validation took #{validation_ms}ms, should be <5ms"
    end
    
    test "cache improves performance for repeated validations", %{test_context: ctx} do
      valid_task_data = %{
        task_id: "550e8400-e29b-41d4-a716-446655440000",
        task_type: :compute,
        parameters: %{},
        priority: 5
      }
      
      calling_service = :performance_test_service
      
      # First validation (full)
      {first_time, {:ok, _}} = :timer.tc(fn ->
        TaskBoundaries.validate_task_execution(valid_task_data, calling_service: calling_service)
      end)
      
      # Second validation (cached)
      {second_time, {:ok, _}} = :timer.tc(fn ->
        TaskBoundaries.validate_task_execution(valid_task_data, calling_service: calling_service)
      end)
      
      # Cached validation should be significantly faster
      first_ms = first_time / 1000
      second_ms = second_time / 1000
      
      assert second_ms < first_ms / 2, 
             "Cached validation (#{second_ms}ms) should be faster than first validation (#{first_ms}ms)"
    end
    
    test "handles high-throughput service calls efficiently", %{test_context: ctx} do
      valid_task_data = %{
        task_id: "550e8400-e29b-41d4-a716-446655440000",
        task_type: :compute,
        parameters: %{},
        priority: 5
      }
      
      # Simulate high-throughput service calls
      tasks = for i <- 1..50 do
        Task.async(fn ->
          TaskBoundaries.validate_task_execution(
            valid_task_data,
            calling_service: :"service_#{i}"
          )
        end)
      end
      
      # All tasks should complete successfully
      results = Task.await_many(tasks, 10_000)
      
      for result <- results do
        assert {:ok, validated} = result
        assert validated.task_type == :compute
      end
    end
  end
  
  describe "Service trust integration" do
    test "correctly identifies trusted services", %{test_context: ctx} do
      # Test trust checking function directly
      assert :bypass_validation = TaskBoundaries.task_execution_trust_check(:task_pool_manager)
      assert :bypass_validation = TaskBoundaries.task_execution_trust_check(:internal_scheduler)
    end
    
    test "handles unknown services with full validation", %{test_context: ctx} do
      task_data = %{
        task_id: "550e8400-e29b-41d4-a716-446655440000",
        task_type: :compute,
        parameters: %{},
        priority: 5
      }
      
      # Unknown service should get full validation
      assert_telemetry_event [:foundation, :perimeter, :services, :validation_success],
        %{validation_mode: :full} do
        assert {:ok, _} = TaskBoundaries.validate_task_execution(
          task_data,
          calling_service: :unknown_service
        )
      end
    end
  end
  
  describe "Service boundary schema and metadata" do
    test "generates correct schema with service metadata", %{test_context: ctx} do
      schema = TaskBoundaries.task_execution_schema()
      
      assert schema.name == :task_execution
      assert schema.zone == :strategic
      assert schema.module == TaskBoundaries
      assert is_list(schema.fields)
      
      # Check service metadata
      metadata = schema.service_metadata
      assert metadata.trust_level == :high
      assert metadata.cache_ttl == 300
      assert :internal_scheduler in metadata.bypass_services
      assert :task_pool_manager in metadata.bypass_services
    end
    
    test "field-specific validators work with validation modes", %{test_context: ctx} do
      # Test with full validation mode
      assert {:ok, "550e8400-e29b-41d4-a716-446655440000"} = 
        TaskBoundaries.validate_task_execution_task_id(
          "550e8400-e29b-41d4-a716-446655440000",
          validation_mode: :full
        )
      
      # Test with minimal validation mode
      assert {:ok, "550e8400-e29b-41d4-a716-446655440000"} = 
        TaskBoundaries.validate_task_execution_task_id(
          "550e8400-e29b-41d4-a716-446655440000",
          validation_mode: :minimal
        )
      
      # Invalid UUID should fail in both modes
      assert {:error, _} = TaskBoundaries.validate_task_execution_task_id("invalid-uuid")
    end
  end
end
```

### Test Support Modules
```elixir
defmodule Foundation.Perimeter.Services.TaskBoundaries do
  use Foundation.Perimeter.Services
  
  strategic_boundary :task_execution do
    field :task_id, :string, required: true, format: :uuid
    field :task_type, :atom, required: true, in: [:compute, :io, :network, :ml]
    field :parameters, :map, required: false, default: %{}
    field :priority, :integer, required: false, range: 1..10, default: 5
    field :timeout_ms, :integer, required: false, range: 1000..300000, default: 30000
    
    service_metadata do
      trust_level :high
      cache_ttl 300
      bypass_validation_for [:internal_scheduler, :task_pool_manager]
    end
  end
  
  strategic_boundary :agent_communication do
    field :from_agent, :string, required: true
    field :to_agent, :string, required: true
    field :message_type, :atom, required: true, in: [:request, :response, :notification]
    field :payload, :map, required: false
    field :correlation_id, :string, required: false, format: :uuid
    
    service_metadata do
      trust_level :medium
      cache_ttl 60
      bypass_validation_for []
    end
  end
end

defmodule Foundation.Perimeter.Services.MockServiceDiscovery do
  @doc """
  Mock service discovery for testing trust levels
  """
  def get_service_metadata(:task_pool_manager), do: {:ok, %{trust_level: :high, internal: true}}
  def get_service_metadata(:internal_scheduler), do: {:ok, %{trust_level: :high, internal: true}}
  def get_service_metadata(:trusted_service), do: {:ok, %{trust_level: :high, internal: true}}
  def get_service_metadata(_), do: {:ok, %{trust_level: :medium}}
end
```

## Success Criteria

1. **All tests pass** with zero `Process.sleep/1` usage
2. **Performance targets met**: <5ms validation for service boundaries
3. **Cache efficiency**: >90% hit rate for repeated service calls
4. **Trust integration**: Proper service trust level handling
5. **Telemetry coverage**: Events for all validation modes and outcomes
6. **Adaptive validation**: Different validation levels based on service trust
7. **Service discovery integration**: Proper integration with Foundation services

## Files to Create

1. `lib/foundation/perimeter/services.ex` - Main service boundary DSL
2. `lib/foundation/perimeter/services/compiler.ex` - Service boundary compilation
3. `test/foundation/perimeter/services_test.exs` - Comprehensive test suite
4. `test/support/service_boundary_test_contracts.ex` - Test service contracts

Follow Foundation's testing standards: event-driven coordination, proper isolation using `:registry` mode, deterministic assertions with telemetry events, and comprehensive service integration testing.