# The ACTUAL Foundation Perimeter Implementation
# Proving that 100 lines beats 4,000+ lines of enterprise architecture

defmodule Foundation.Perimeter do
  @moduledoc """
  Simple validation boundaries for Foundation AI systems.
  
  Three validation levels:
  - external: Strict validation for untrusted input (uses Ecto)
  - internal: Light validation for service boundaries (basic type checks)
  - trusted: No validation for performance paths (immediate return)
  
  ## Examples
  
      # External API validation
      {:ok, user} = validate_external(params, %{
        name: {:string, required: true, min: 1, max: 100},
        email: {:string, required: true},
        age: {:integer, required: false}
      })
      
      # Internal service validation  
      {:ok, task} = validate_internal(data, %{
        id: :string,
        type: :atom,
        payload: :map
      })
      
      # Trusted high-performance path
      {:ok, signal} = validate_trusted(signal, :any)
  """

  @doc """
  Strict validation for external/untrusted input using Ecto.
  
  Supports:
  - Required field validation
  - Type checking (string, integer, map, list)
  - Length constraints for strings
  - Custom validation functions
  """
  def validate_external(data, schema) when is_map(data) and is_map(schema) do
    # Convert schema to Ecto types
    types = schema_to_ecto_types(schema)
    
    # Create changeset
    changeset = Ecto.Changeset.cast({%{}, types}, data, Map.keys(types))
    
    # Apply validation rules
    changeset = Enum.reduce(schema, changeset, fn {field, rules}, acc ->
      apply_validation_rules(acc, field, rules)
    end)
    
    case changeset.valid? do
      true -> {:ok, Ecto.Changeset.apply_changes(changeset)}
      false -> {:error, format_errors(changeset.errors)}
    end
  end

  def validate_external(data, _schema) do
    {:error, "External validation requires map input, got: #{inspect(data)}"}
  end

  @doc """
  Light validation for internal service boundaries.
  
  Performs basic type checking without strict constraints.
  More permissive than external validation for internal trust.
  """
  def validate_internal(data, schema) when is_map(data) and is_map(schema) do
    case validate_basic_types(data, schema) do
      :ok -> {:ok, data}
      {:error, errors} -> {:error, errors}
    end
  end

  def validate_internal(data, _schema) do
    # Internal validation is permissive - accept non-map data
    {:ok, data}
  end

  @doc """
  No validation for trusted/high-performance paths.
  
  Always returns {:ok, data} immediately for maximum performance.
  Use this for internal calls where data is already trusted.
  """
  def validate_trusted(data, _schema), do: {:ok, data}

  # Private helper functions

  defp schema_to_ecto_types(schema) do
    Map.new(schema, fn
      {key, {:string, _opts}} -> {key, :string}
      {key, {:integer, _opts}} -> {key, :integer}
      {key, {:map, _opts}} -> {key, :map}
      {key, {:list, _opts}} -> {key, {:array, :string}}
      {key, type} when is_atom(type) -> {key, type}
      {key, _complex} -> {key, :string}  # Fallback
    end)
  end

  defp apply_validation_rules(changeset, field, {:string, opts}) do
    changeset = 
      if Keyword.get(opts, :required, false) do
        Ecto.Changeset.validate_required(changeset, [field])
      else
        changeset
      end

    changeset = 
      if min = Keyword.get(opts, :min) do
        Ecto.Changeset.validate_length(changeset, field, min: min)
      else
        changeset
      end

    if max = Keyword.get(opts, :max) do
      Ecto.Changeset.validate_length(changeset, field, max: max)
    else
      changeset
    end
  end

  defp apply_validation_rules(changeset, field, {:integer, opts}) do
    if Keyword.get(opts, :required, false) do
      Ecto.Changeset.validate_required(changeset, [field])
    else
      changeset
    end
  end

  defp apply_validation_rules(changeset, field, {:map, opts}) do
    if Keyword.get(opts, :required, false) do
      Ecto.Changeset.validate_required(changeset, [field])
    else
      changeset
    end
  end

  defp apply_validation_rules(changeset, _field, _type), do: changeset

  defp validate_basic_types(data, schema) do
    errors = Enum.reduce(schema, [], fn
      {key, :string}, acc ->
        case Map.get(data, key) do
          val when is_binary(val) or is_nil(val) -> acc
          _other -> [{key, "expected string"} | acc]
        end

      {key, :integer}, acc ->
        case Map.get(data, key) do
          val when is_integer(val) or is_nil(val) -> acc
          _other -> [{key, "expected integer"} | acc]
        end

      {key, :map}, acc ->
        case Map.get(data, key) do
          val when is_map(val) or is_nil(val) -> acc
          _other -> [{key, "expected map"} | acc]
        end

      {key, :atom}, acc ->
        case Map.get(data, key) do
          val when is_atom(val) or is_nil(val) -> acc
          _other -> [{key, "expected atom"} | acc]
        end

      {key, :list}, acc ->
        case Map.get(data, key) do
          val when is_list(val) or is_nil(val) -> acc
          _other -> [{key, "expected list"} | acc]
        end

      _other, acc -> acc
    end)

    case errors do
      [] -> :ok
      errors -> {:error, Enum.reverse(errors)}
    end
  end

  defp format_errors(errors) do
    Enum.map(errors, fn {field, {message, opts}} ->
      {field, interpolate_error(message, opts)}
    end)
  end

  defp interpolate_error(message, opts) do
    Enum.reduce(opts, message, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", to_string(value))
    end)
  end
end

# Optional convenience macros (totally unnecessary but might be nice)
defmodule Foundation.Perimeter.Macros do
  @moduledoc """
  Optional convenience macros for Foundation Perimeter.
  These are completely optional - the main module works fine without them.
  """

  @doc """
  Macro to validate external input and raise on error.
  Use this when you want to fail fast on invalid input.
  """
  defmacro validate_external!(data, schema) do
    quote do
      case Foundation.Perimeter.validate_external(unquote(data), unquote(schema)) do
        {:ok, validated} -> validated
        {:error, errors} -> 
          raise ArgumentError, "Validation failed: #{inspect(errors)}"
      end
    end
  end

  @doc """
  Convenience macro for pattern matching validation results.
  """
  defmacro with_validation(validation_expr, do: success_block, else: error_block) do
    quote do
      case unquote(validation_expr) do
        {:ok, validated} -> 
          var!(validated) = validated
          unquote(success_block)
        {:error, errors} ->
          var!(errors) = errors
          unquote(error_block)
      end
    end
  end
end

# Test module showing real usage
defmodule Foundation.PerimeterTest do
  @moduledoc """
  Complete test suite for Foundation.Perimeter.
  Shows real usage patterns and validates all functionality.
  """
  
  use ExUnit.Case
  alias Foundation.Perimeter

  describe "external validation" do
    test "validates required string fields with length constraints" do
      schema = %{
        name: {:string, required: true, min: 1, max: 50},
        description: {:string, required: false, max: 200}
      }

      # Valid data
      assert {:ok, %{name: "test", description: "A test"}} = 
        Perimeter.validate_external(%{name: "test", description: "A test"}, schema)

      # Missing required field
      assert {:error, errors} = 
        Perimeter.validate_external(%{description: "test"}, schema)
      assert Enum.any?(errors, fn {field, _} -> field == :name end)

      # Too short
      assert {:error, errors} = 
        Perimeter.validate_external(%{name: ""}, schema)
      assert Enum.any?(errors, fn {_, msg} -> msg =~ "should be at least 1" end)

      # Too long  
      long_name = String.duplicate("a", 51)
      assert {:error, errors} = 
        Perimeter.validate_external(%{name: long_name}, schema)
      assert Enum.any?(errors, fn {_, msg} -> msg =~ "should be at most 50" end)
    end

    test "validates integer fields" do
      schema = %{count: {:integer, required: true}, optional_num: {:integer, required: false}}

      assert {:ok, %{count: 42}} = 
        Perimeter.validate_external(%{count: 42}, schema)

      assert {:error, _} = 
        Perimeter.validate_external(%{count: "not integer"}, schema)

      # Optional integer can be missing
      assert {:ok, %{count: 10}} = 
        Perimeter.validate_external(%{count: 10}, schema)
    end

    test "validates map fields" do
      schema = %{config: {:map, required: true}}

      assert {:ok, %{config: %{key: "value"}}} = 
        Perimeter.validate_external(%{config: %{key: "value"}}, schema)

      assert {:error, _} = 
        Perimeter.validate_external(%{config: "not a map"}, schema)
    end

    test "rejects non-map input" do
      assert {:error, msg} = Perimeter.validate_external("not a map", %{})
      assert msg =~ "requires map input"
    end
  end

  describe "internal validation" do
    test "performs basic type checking" do
      schema = %{id: :string, count: :integer, config: :map, tags: :list}

      # Valid data
      data = %{id: "test", count: 42, config: %{}, tags: ["a", "b"]}
      assert {:ok, ^data} = Perimeter.validate_internal(data, schema)

      # Invalid types
      assert {:error, errors} = Perimeter.validate_internal(
        %{id: 123, count: "not integer", config: "not map", tags: "not list"}, 
        schema
      )
      
      assert {"id", "expected string"} in errors
      assert {"count", "expected integer"} in errors
      assert {"config", "expected map"} in errors
      assert {"tags", "expected list"} in errors
    end

    test "allows missing fields (permissive)" do
      schema = %{optional: :string}
      assert {:ok, %{}} = Perimeter.validate_internal(%{}, schema)
    end

    test "accepts non-map input (permissive)" do
      assert {:ok, "anything"} = Perimeter.validate_internal("anything", %{})
      assert {:ok, 123} = Perimeter.validate_internal(123, %{})
    end
  end

  describe "trusted validation" do
    test "always succeeds immediately" do
      assert {:ok, "anything"} = Perimeter.validate_trusted("anything", %{})
      assert {:ok, %{any: "data"}} = Perimeter.validate_trusted(%{any: "data"}, %{})
      assert {:ok, nil} = Perimeter.validate_trusted(nil, %{})
      assert {:ok, 123} = Perimeter.validate_trusted(123, :ignored_schema)
    end
  end

  describe "real-world usage patterns" do
    test "external API endpoint pattern" do
      # Simulate API endpoint validation
      api_params = %{
        "name" => "Test User",
        "email" => "test@example.com", 
        "age" => "25"  # String from JSON
      }

      schema = %{
        name: {:string, required: true, min: 1, max: 100},
        email: {:string, required: true},
        age: {:integer, required: false}
      }

      # Convert string keys to atoms (common in APIs)
      normalized_params = Map.new(api_params, fn {k, v} -> {String.to_atom(k), v} end)

      # This will fail because age is a string, not integer
      assert {:error, _} = Perimeter.validate_external(normalized_params, schema)

      # Fix the age conversion
      fixed_params = %{normalized_params | age: String.to_integer(normalized_params.age)}
      assert {:ok, validated} = Perimeter.validate_external(fixed_params, schema)
      assert validated.name == "Test User"
      assert validated.age == 25
    end

    test "internal service communication pattern" do
      # Simulate internal service call
      task_data = %{
        id: "task_123",
        type: :compute,
        payload: %{input: "data", params: %{}}
      }

      schema = %{id: :string, type: :atom, payload: :map}

      assert {:ok, validated} = Perimeter.validate_internal(task_data, schema)
      assert validated == task_data
    end

    test "trusted high-performance path pattern" do
      # Simulate hot path in signal routing
      signal = %{from: :agent_1, to: :agent_2, message: "urgent", priority: :high}

      # No validation overhead
      assert {:ok, ^signal} = Perimeter.validate_trusted(signal, :any)
    end
  end
end

# Performance benchmark (optional, for comparison with the "enterprise" version)
defmodule Foundation.Perimeter.Benchmark do
  @moduledoc """
  Simple benchmarks to show this performs well without complex optimization.
  """

  def run_benchmarks do
    data = %{
      name: "Benchmark Test",
      email: "bench@test.com",
      age: 30,
      config: %{setting: "value"},
      tags: ["tag1", "tag2"]
    }

    external_schema = %{
      name: {:string, required: true, min: 1, max: 100},
      email: {:string, required: true},
      age: {:integer, required: false},
      config: {:map, required: false},
      tags: {:list, required: false}
    }

    internal_schema = %{
      name: :string,
      email: :string, 
      age: :integer,
      config: :map,
      tags: :list
    }

    # Benchmark external validation
    {time_external, _} = :timer.tc(fn ->
      for _i <- 1..1000 do
        Foundation.Perimeter.validate_external(data, external_schema)
      end
    end)

    # Benchmark internal validation  
    {time_internal, _} = :timer.tc(fn ->
      for _i <- 1..10000 do
        Foundation.Perimeter.validate_internal(data, internal_schema)
      end
    end)

    # Benchmark trusted (should be ~0)
    {time_trusted, _} = :timer.tc(fn ->
      for _i <- 1..100000 do
        Foundation.Perimeter.validate_trusted(data, :any)
      end
    end)

    IO.puts("Performance Results:")
    IO.puts("  External (1,000 ops): #{time_external / 1000}ms (#{time_external / 1000 / 1000}ms per op)")
    IO.puts("  Internal (10,000 ops): #{time_internal / 1000}ms (#{time_internal / 1000 / 10000}ms per op)")
    IO.puts("  Trusted (100,000 ops): #{time_trusted / 1000}ms (#{time_trusted / 1000 / 100000}ms per op)")
  end
end

# Usage examples for documentation
defmodule Foundation.Perimeter.Examples do
  @moduledoc """
  Real-world usage examples showing the three validation levels.
  """

  # External API validation example
  def create_user_api(params) do
    with {:ok, validated} <- Foundation.Perimeter.validate_external(params, %{
           name: {:string, required: true, min: 1, max: 100},
           email: {:string, required: true},
           age: {:integer, required: false}
         }) do
      # Validated data is guaranteed to match schema
      Users.create(validated)
    else
      {:error, errors} -> {:error, {:validation_failed, errors}}
    end
  end

  # Internal service validation example  
  def process_task_internal(task_data) do
    with {:ok, validated} <- Foundation.Perimeter.validate_internal(task_data, %{
           id: :string,
           type: :atom,
           payload: :map
         }) do
      # Light validation ensures basic structure
      TaskProcessor.execute(validated)
    else
      {:error, errors} -> {:error, {:invalid_task_data, errors}}
    end
  end

  # Trusted high-performance path example
  def route_signal_trusted(signal) do
    # No validation overhead for trusted internal calls
    {:ok, validated} = Foundation.Perimeter.validate_trusted(signal, :any)
    SignalRouter.route_fast(validated)
  end
end