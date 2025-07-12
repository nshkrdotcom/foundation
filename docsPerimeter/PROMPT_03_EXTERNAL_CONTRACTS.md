# Foundation Perimeter External Contracts Implementation

## Context

Foundation Perimeter implements a Four-Zone Architecture for BEAM-native AI systems. Zone 1 (External Perimeter) provides the strictest validation and contracts for external API interactions, user inputs, and system boundaries. This zone enforces comprehensive data validation with detailed error reporting.

## Task

Implement Foundation Perimeter External Contract system with comprehensive validation functions, compile-time optimization, and proper integration with ValidationService and ContractRegistry.

## Requirements

### Architecture
- Macro-based DSL for external contract definition
- Compile-time validation function generation
- Comprehensive field validation with constraints
- Structured error handling with detailed feedback
- Integration with Foundation telemetry and error tracking

### Test-Driven Implementation
Follow Foundation's event-driven testing philosophy - no `Process.sleep/1` allowed. Use `Foundation.UnifiedTestFoundation` with `:basic` isolation mode for pure function testing.

### Performance Targets
- Validation speed: <15ms for typical external payloads
- Compile-time generation: Zero runtime reflection overhead
- Memory efficiency: Minimal allocation for validation functions
- Error reporting: Detailed but lightweight error structures

## Implementation Specification

### Module Structure
```elixir
defmodule Foundation.Perimeter.External do
  @moduledoc """
  Zone 1 - External Perimeter contracts for Foundation systems.
  Provides strictest validation for external inputs with comprehensive error reporting.
  """
  
  alias Foundation.Perimeter.{ValidationService, Error}
  alias Foundation.Telemetry
  
  @doc """
  Defines an external contract with strict validation rules.
  
  ## Example
  
      external_contract :user_registration do
        field :email, :string, required: true, format: :email
        field :password, :string, required: true, length: 8..128
        field :name, :string, required: true, length: 1..100
        field :age, :integer, required: false, range: 13..120
      end
  """
  defmacro external_contract(name, do: body) do
    quote do
      @contract_name unquote(name)
      @contract_zone :external
      @fields []
      
      unquote(body)
      
      Foundation.Perimeter.External.__compile_contract__(@contract_name, @fields, @contract_zone)
    end
  end
  
  @doc """
  Defines a field in an external contract with validation constraints.
  """
  defmacro field(name, type, opts \\ []) do
    quote do
      @fields [{unquote(name), unquote(type), unquote(opts)} | @fields]
    end
  end
  
  @doc false
  def __compile_contract__(name, fields, zone) do
    # This will be called at compile time to generate validation functions
    compile_validation_functions(name, fields, zone)
  end
end
```

### Validation Function Generation
```elixir
defmodule Foundation.Perimeter.External.Compiler do
  @moduledoc false
  
  def compile_validation_functions(contract_name, fields, zone) do
    validation_function_name = :"validate_#{contract_name}"
    schema_function_name = :"#{contract_name}_schema"
    
    quote do
      @doc """
      Validates data against the #{unquote(contract_name)} external contract.
      Returns {:ok, validated_data} or {:error, validation_errors}.
      """
      def unquote(validation_function_name)(data) when is_map(data) do
        start_time = System.monotonic_time(:microsecond)
        
        case perform_validation(data, unquote(fields), unquote(contract_name)) do
          {:ok, validated} = success ->
            validation_time = System.monotonic_time(:microsecond) - start_time
            
            Foundation.Telemetry.emit([:foundation, :perimeter, :external, :validation_success], %{
              duration: validation_time
            }, %{
              contract: unquote(contract_name),
              zone: unquote(zone),
              field_count: length(unquote(fields))
            })
            
            success
          
          {:error, errors} = failure ->
            validation_time = System.monotonic_time(:microsecond) - start_time
            
            Foundation.Telemetry.emit([:foundation, :perimeter, :external, :validation_failed], %{
              duration: validation_time,
              error_count: length(errors)
            }, %{
              contract: unquote(contract_name),
              zone: unquote(zone),
              errors: Enum.map(errors, & &1.field)
            })
            
            failure
        end
      end
      
      def unquote(validation_function_name)(data) do
        {:error, [Foundation.Perimeter.Error.type_error(:external_contract_input, data, :map)]}
      end
      
      @doc """
      Returns the schema definition for #{unquote(contract_name)} contract.
      """
      def unquote(schema_function_name)() do
        %{
          name: unquote(contract_name),
          zone: unquote(zone),
          fields: unquote(Macro.escape(fields)),
          compiled_at: unquote(DateTime.utc_now()),
          module: __MODULE__
        }
      end
      
      # Generate field-specific validation functions
      unquote_splicing(generate_field_validators(fields, contract_name))
    end
  end
  
  defp perform_validation(data, fields, contract_name) do
    validated_fields = %{}
    errors = []
    
    {validated, errors} = Enum.reduce(fields, {validated_fields, errors}, fn 
      {field_name, field_type, field_opts}, {acc_validated, acc_errors} ->
        case validate_field(data, field_name, field_type, field_opts, contract_name) do
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
  
  defp validate_field(data, field_name, field_type, field_opts, contract_name) do
    required = Keyword.get(field_opts, :required, false)
    default = Keyword.get(field_opts, :default)
    
    case Map.get(data, field_name, Map.get(data, to_string(field_name))) do
      nil when required ->
        {:error, Foundation.Perimeter.Error.required_field_missing(
          :external, contract_name, field_name
        )}
      
      nil when not is_nil(default) ->
        validate_field_type(default, field_name, field_type, field_opts, contract_name)
      
      nil ->
        {:ok, nil}
      
      value ->
        validate_field_type(value, field_name, field_type, field_opts, contract_name)
    end
  end
  
  defp validate_field_type(value, field_name, field_type, field_opts, contract_name) do
    with {:ok, typed_value} <- validate_base_type(value, field_type, field_name, contract_name),
         {:ok, constrained_value} <- validate_constraints(typed_value, field_opts, field_name, contract_name) do
      {:ok, constrained_value}
    end
  end
  
  defp validate_base_type(value, :string, field_name, contract_name) when is_binary(value), do: {:ok, value}
  defp validate_base_type(value, :integer, field_name, contract_name) when is_integer(value), do: {:ok, value}
  defp validate_base_type(value, :float, field_name, contract_name) when is_float(value), do: {:ok, value}
  defp validate_base_type(value, :number, field_name, contract_name) when is_number(value), do: {:ok, value}
  defp validate_base_type(value, :boolean, field_name, contract_name) when is_boolean(value), do: {:ok, value}
  defp validate_base_type(value, :atom, field_name, contract_name) when is_atom(value), do: {:ok, value}
  defp validate_base_type(value, :map, field_name, contract_name) when is_map(value), do: {:ok, value}
  defp validate_base_type(value, :list, field_name, contract_name) when is_list(value), do: {:ok, value}
  
  # DateTime validation
  defp validate_base_type(%DateTime{} = value, :datetime, _field_name, _contract_name), do: {:ok, value}
  defp validate_base_type(value, :datetime, field_name, contract_name) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> {:ok, datetime}
      {:error, reason} -> 
        {:error, Foundation.Perimeter.Error.type_error(:external, field_name, value, :datetime, reason)}
    end
  end
  
  # Type conversion attempts for common cases
  defp validate_base_type(value, :integer, field_name, contract_name) when is_binary(value) do
    case Integer.parse(value) do
      {int_val, ""} -> {:ok, int_val}
      _ -> {:error, Foundation.Perimeter.Error.type_error(:external, field_name, value, :integer)}
    end
  end
  
  defp validate_base_type(value, :float, field_name, contract_name) when is_binary(value) do
    case Float.parse(value) do
      {float_val, ""} -> {:ok, float_val}
      _ -> {:error, Foundation.Perimeter.Error.type_error(:external, field_name, value, :float)}
    end
  end
  
  # Fallback type error
  defp validate_base_type(value, expected_type, field_name, contract_name) do
    {:error, Foundation.Perimeter.Error.type_error(:external, field_name, value, expected_type)}
  end
  
  defp validate_constraints(value, field_opts, field_name, contract_name) do
    Enum.reduce_while(field_opts, {:ok, value}, fn
      {:required, _}, acc -> {:cont, acc}
      {:default, _}, acc -> {:cont, acc}
      
      {:length, range}, {:ok, val} when is_binary(val) ->
        validate_length_constraint(val, range, field_name, contract_name)
      
      {:range, range}, {:ok, val} when is_number(val) ->
        validate_range_constraint(val, range, field_name, contract_name)
      
      {:format, format}, {:ok, val} when is_binary(val) ->
        validate_format_constraint(val, format, field_name, contract_name)
      
      {:in, choices}, {:ok, val} ->
        validate_choice_constraint(val, choices, field_name, contract_name)
      
      {constraint_name, _constraint_value}, {:ok, _val} ->
        # Unknown constraint - log warning but continue
        Logger.warning("Unknown constraint #{constraint_name} for field #{field_name} in contract #{contract_name}")
        {:cont, {:ok, value}}
    end)
  end
  
  defp validate_length_constraint(value, min..max, field_name, contract_name) do
    length = String.length(value)
    if length >= min and length <= max do
      {:cont, {:ok, value}}
    else
      {:halt, {:error, Foundation.Perimeter.Error.constraint_error(
        :external, field_name, value, :length, "must be between #{min} and #{max} characters"
      )}}
    end
  end
  
  defp validate_length_constraint(value, exact_length, field_name, contract_name) when is_integer(exact_length) do
    if String.length(value) == exact_length do
      {:cont, {:ok, value}}
    else
      {:halt, {:error, Foundation.Perimeter.Error.constraint_error(
        :external, field_name, value, :length, "must be exactly #{exact_length} characters"
      )}}
    end
  end
  
  defp validate_range_constraint(value, min..max, field_name, contract_name) do
    if value >= min and value <= max do
      {:cont, {:ok, value}}
    else
      {:halt, {:error, Foundation.Perimeter.Error.constraint_error(
        :external, field_name, value, :range, "must be between #{min} and #{max}"
      )}}
    end
  end
  
  defp validate_format_constraint(value, :email, field_name, contract_name) do
    email_regex = ~r/^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/
    if Regex.match?(email_regex, value) do
      {:cont, {:ok, value}}
    else
      {:halt, {:error, Foundation.Perimeter.Error.constraint_error(
        :external, field_name, value, :format, "must be a valid email address"
      )}}
    end
  end
  
  defp validate_format_constraint(value, regex, field_name, contract_name) when is_struct(regex, Regex) do
    if Regex.match?(regex, value) do
      {:cont, {:ok, value}}
    else
      {:halt, {:error, Foundation.Perimeter.Error.constraint_error(
        :external, field_name, value, :format, "does not match required format"
      )}}
    end
  end
  
  defp validate_choice_constraint(value, choices, field_name, contract_name) when is_list(choices) do
    if value in choices do
      {:cont, {:ok, value}}
    else
      {:halt, {:error, Foundation.Perimeter.Error.constraint_error(
        :external, field_name, value, :choice, "must be one of: #{inspect(choices)}"
      )}}
    end
  end
  
  defp generate_field_validators(fields, contract_name) do
    Enum.map(fields, fn {field_name, field_type, field_opts} ->
      validator_name = :"validate_#{contract_name}_#{field_name}"
      
      quote do
        @doc """
        Validates the #{unquote(field_name)} field for #{unquote(contract_name)} contract.
        """
        def unquote(validator_name)(value) do
          validate_field_type(value, unquote(field_name), unquote(field_type), 
                             unquote(field_opts), unquote(contract_name))
        end
      end
    end)
  end
end
```

## Testing Requirements

### Test Structure
```elixir
defmodule Foundation.Perimeter.ExternalTest do
  use Foundation.UnifiedTestFoundation, :basic
  import Foundation.AsyncTestHelpers
  
  alias Foundation.Perimeter.External.UserContracts
  alias Foundation.Perimeter.Error
  
  @moduletag :perimeter_testing
  @moduletag timeout: 5_000
  
  describe "External contract validation" do
    test "validates correct user registration data with telemetry" do
      valid_data = %{
        email: "user@example.com",
        password: "securepassword123",
        name: "John Doe",
        age: 25
      }
      
      # Should emit success telemetry
      assert_telemetry_event [:foundation, :perimeter, :external, :validation_success],
        %{duration: duration} when duration > 0 do
        assert {:ok, validated} = UserContracts.validate_user_registration(valid_data)
        
        assert validated.email == "user@example.com"
        assert validated.password == "securepassword123"
        assert validated.name == "John Doe"
        assert validated.age == 25
      end
    end
    
    test "rejects invalid user registration data with detailed errors" do
      invalid_data = %{
        email: "not-an-email",
        password: "short",
        name: "",
        age: 200
      }
      
      # Should emit failure telemetry
      assert_telemetry_event [:foundation, :perimeter, :external, :validation_failed],
        %{error_count: count} when count > 0 do
        assert {:error, errors} = UserContracts.validate_user_registration(invalid_data)
        
        assert is_list(errors)
        assert length(errors) >= 4  # All fields should have errors
        
        # Check specific error types
        email_error = Enum.find(errors, & &1.field == :email)
        password_error = Enum.find(errors, & &1.field == :password)
        name_error = Enum.find(errors, & &1.field == :name)
        age_error = Enum.find(errors, & &1.field == :age)
        
        assert email_error.constraint == :format
        assert password_error.constraint == :length
        assert name_error.constraint == :length
        assert age_error.constraint == :range
      end
    end
    
    test "handles missing required fields correctly" do
      incomplete_data = %{
        email: "user@example.com"
        # Missing password (required), name (required)
        # age is optional so should be OK
      }
      
      assert {:error, errors} = UserContracts.validate_user_registration(incomplete_data)
      
      error_fields = Enum.map(errors, & &1.field)
      assert :password in error_fields
      assert :name in error_fields
      assert :age not in error_fields  # Optional field
    end
    
    test "applies default values for optional fields" do
      data_with_defaults = %{
        email: "user@example.com",
        password: "securepassword123",
        name: "John Doe"
        # age not provided, should get default if specified
      }
      
      assert {:ok, validated} = UserContracts.validate_user_registration(data_with_defaults)
      # age should be nil or default value based on contract definition
      assert is_nil(validated.age) or is_integer(validated.age)
    end
    
    test "performs type conversion for compatible types" do
      data_with_strings = %{
        email: "user@example.com",
        password: "securepassword123", 
        name: "John Doe",
        age: "25"  # String that can be converted to integer
      }
      
      assert {:ok, validated} = UserContracts.validate_user_registration(data_with_strings)
      assert validated.age == 25
      assert is_integer(validated.age)
    end
    
    test "rejects non-map input with type error" do
      invalid_input = "not a map"
      
      assert {:error, [error]} = UserContracts.validate_user_registration(invalid_input)
      assert error.zone == :external_contract_input
      assert error.expected_type == :map
    end
  end
  
  describe "External contract performance" do
    test "meets validation performance targets" do
      valid_data = %{
        email: "performance@test.com",
        password: "testpassword123",
        name: "Performance Test",
        age: 30
      }
      
      # Measure validation time
      {validation_time, {:ok, _validated}} = :timer.tc(fn ->
        UserContracts.validate_user_registration(valid_data)
      end)
      
      # Convert to milliseconds
      validation_ms = validation_time / 1000
      
      # Assert performance target for Zone 1 (External)
      assert validation_ms < 15.0, "External validation took #{validation_ms}ms, should be <15ms"
    end
    
    test "handles batch validation efficiently" do
      valid_data = %{
        email: "batch@test.com",
        password: "batchpassword123",
        name: "Batch Test",
        age: 28
      }
      
      # Perform many validations
      {batch_time, results} = :timer.tc(fn ->
        for _i <- 1..100 do
          UserContracts.validate_user_registration(valid_data)
        end
      end)
      
      # All should succeed
      for result <- results do
        assert {:ok, _validated} = result
      end
      
      # Average time should still be fast
      avg_time_ms = (batch_time / 1000) / 100
      assert avg_time_ms < 5.0, "Average batch validation took #{avg_time_ms}ms, should be <5ms"
    end
  end
  
  describe "External contract schema generation" do
    test "generates correct schema information" do
      schema = UserContracts.user_registration_schema()
      
      assert schema.name == :user_registration
      assert schema.zone == :external
      assert schema.module == UserContracts
      assert is_list(schema.fields)
      assert %DateTime{} = schema.compiled_at
      
      # Check field definitions
      email_field = Enum.find(schema.fields, fn {name, _, _} -> name == :email end)
      {_name, type, opts} = email_field
      
      assert type == :string
      assert Keyword.get(opts, :required) == true
      assert Keyword.get(opts, :format) == :email
    end
    
    test "field-specific validators work correctly" do
      # Test individual field validators
      assert {:ok, "valid@email.com"} = UserContracts.validate_user_registration_email("valid@email.com")
      assert {:error, _} = UserContracts.validate_user_registration_email("invalid-email")
      
      assert {:ok, "validpassword"} = UserContracts.validate_user_registration_password("validpassword")
      assert {:error, _} = UserContracts.validate_user_registration_password("short")
      
      assert {:ok, 25} = UserContracts.validate_user_registration_age(25)
      assert {:error, _} = UserContracts.validate_user_registration_age(200)
    end
  end
  
  describe "External contract error handling" do
    test "provides detailed error information" do
      invalid_data = %{
        email: "bad-email",
        password: "x",
        name: "",
        age: -5
      }
      
      assert {:error, errors} = UserContracts.validate_user_registration(invalid_data)
      
      for error <- errors do
        assert %Foundation.Perimeter.Error{} = error
        assert error.zone == :external
        assert is_atom(error.field)
        assert is_atom(error.constraint)
        assert is_binary(error.message)
        assert error.value != nil
      end
    end
    
    test "groups errors by field appropriately" do
      # Test data that could have multiple errors per field
      invalid_data = %{
        email: "",  # Both required and format error possible
        password: "",  # Length error
        name: "",  # Length error  
        age: "not-a-number"  # Type conversion error
      }
      
      assert {:error, errors} = UserContracts.validate_user_registration(invalid_data)
      
      # Should have one error per field (first error wins)
      error_fields = Enum.map(errors, & &1.field)
      unique_fields = Enum.uniq(error_fields)
      
      assert length(error_fields) == length(unique_fields), 
             "Should have one error per field, got: #{inspect(error_fields)}"
    end
  end
end
```

### Test Support Modules
Create these supporting test modules:

```elixir
defmodule Foundation.Perimeter.External.UserContracts do
  use Foundation.Perimeter.External
  
  external_contract :user_registration do
    field :email, :string, required: true, format: :email
    field :password, :string, required: true, length: 8..128
    field :name, :string, required: true, length: 1..100
    field :age, :integer, required: false, range: 13..120
  end
  
  external_contract :api_request do
    field :endpoint, :string, required: true, length: 1..200
    field :method, :atom, required: true, in: [:get, :post, :put, :delete]
    field :headers, :map, required: false
    field :body, :string, required: false
    field :timeout, :integer, required: false, range: 1000..30000, default: 5000
  end
end

defmodule Foundation.Perimeter.External.ValidationBenchmark do
  @doc """
  Benchmark contract for performance testing
  """
  use Foundation.Perimeter.External
  
  external_contract :large_payload do
    field :id, :string, required: true, length: 1..50
    field :title, :string, required: true, length: 1..200
    field :description, :string, required: false, length: 0..2000
    field :tags, :list, required: false
    field :metadata, :map, required: false
    field :created_at, :datetime, required: true
    field :updated_at, :datetime, required: false
    field :priority, :integer, required: false, range: 1..10, default: 5
    field :status, :atom, required: true, in: [:draft, :published, :archived]
    field :score, :float, required: false, range: 0.0..1.0
  end
end
```

## Success Criteria

1. **All tests pass** with zero `Process.sleep/1` usage
2. **Performance targets met**: <15ms validation for external contracts
3. **Compile-time optimization**: Zero runtime reflection overhead
4. **Comprehensive validation**: Type checking, constraints, format validation
5. **Telemetry integration**: Success/failure events with performance metrics
6. **Detailed error reporting**: Structured errors with field-level detail
7. **Type conversion support**: Automatic conversion for compatible types

## Files to Create

1. `lib/foundation/perimeter/external.ex` - Main external contract DSL
2. `lib/foundation/perimeter/external/compiler.ex` - Compile-time validation generation
3. `test/foundation/perimeter/external_test.exs` - Comprehensive test suite
4. `test/support/external_test_contracts.ex` - Test contract definitions

Follow Foundation's testing standards: event-driven coordination, deterministic assertions with telemetry events, comprehensive validation testing, and performance verification.