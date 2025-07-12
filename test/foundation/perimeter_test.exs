defmodule Foundation.PerimeterTest do
  use ExUnit.Case
  
  describe "external validation" do
    test "validates required string fields with length constraints" do
      schema = %{
        name: {:string, required: true, min: 1, max: 50},
        description: {:string, required: false, max: 200}
      }

      # Valid data
      assert {:ok, %{name: "test", description: "A test"}} = 
        Foundation.Perimeter.validate_external(%{name: "test", description: "A test"}, schema)

      # Missing required field
      assert {:error, errors} = 
        Foundation.Perimeter.validate_external(%{description: "test"}, schema)
      assert Enum.any?(errors, fn {field, _} -> field == :name end)

      # Too short
      assert {:error, errors} = 
        Foundation.Perimeter.validate_external(%{name: ""}, schema)
      assert Enum.any?(errors, fn {_, msg} -> msg =~ "should be at least 1" end)

      # Too long  
      long_name = String.duplicate("a", 51)
      assert {:error, errors} = 
        Foundation.Perimeter.validate_external(%{name: long_name}, schema)
      assert Enum.any?(errors, fn {_, msg} -> msg =~ "should be at most 50" end)
    end

    test "validates integer fields" do
      schema = %{count: {:integer, required: true}, optional_num: {:integer, required: false}}

      assert {:ok, %{count: 42}} = 
        Foundation.Perimeter.validate_external(%{count: 42}, schema)

      assert {:error, errors} = 
        Foundation.Perimeter.validate_external(%{count: "not integer"}, schema)
      assert Enum.any?(errors, fn {field, msg} -> field == :count and msg =~ "must be an integer" end)

      # Optional integer can be missing
      assert {:ok, %{count: 10}} = 
        Foundation.Perimeter.validate_external(%{count: 10}, schema)
    end

    test "validates map fields" do
      schema = %{config: {:map, required: true}}

      assert {:ok, %{config: %{key: "value"}}} = 
        Foundation.Perimeter.validate_external(%{config: %{key: "value"}}, schema)

      assert {:error, errors} = 
        Foundation.Perimeter.validate_external(%{config: "not a map"}, schema)
      assert Enum.any?(errors, fn {field, msg} -> field == :config and msg =~ "must be a map" end)
    end

    test "validates atom fields with values constraint" do
      schema = %{priority: {:atom, values: [:low, :normal, :high], default: :normal}}

      assert {:ok, %{priority: :high}} = 
        Foundation.Perimeter.validate_external(%{priority: :high}, schema)

      assert {:error, errors} = 
        Foundation.Perimeter.validate_external(%{priority: :invalid}, schema)
      assert Enum.any?(errors, fn {field, msg} -> field == :priority and msg =~ "must be one of" end)
    end

    test "applies defaults correctly" do
      schema = %{
        name: {:string, required: true},
        priority: {:atom, default: :normal}
      }

      assert {:ok, %{name: "test", priority: :normal}} = 
        Foundation.Perimeter.validate_external(%{name: "test"}, schema)
    end

    test "validates with custom validation function" do
      validate_email = fn
        nil -> :ok
        email when is_binary(email) ->
          if String.contains?(email, "@") do
            :ok
          else
            {:error, "must be a valid email"}
          end
        _ -> {:error, "must be a string"}
      end

      schema = %{
        email: {:string, required: true, validate: validate_email}
      }

      assert {:ok, %{email: "test@example.com"}} = 
        Foundation.Perimeter.validate_external(%{email: "test@example.com"}, schema)

      assert {:error, errors} = 
        Foundation.Perimeter.validate_external(%{email: "invalid-email"}, schema)
      assert Enum.any?(errors, fn {field, msg} -> field == :email and msg =~ "must be a valid email" end)
    end

    test "rejects non-map input" do
      assert {:error, msg} = Foundation.Perimeter.validate_external("not a map", %{})
      assert msg =~ "requires map input"
    end
  end

  describe "internal validation" do
    test "performs basic type checking" do
      schema = %{id: :string, count: :integer, config: :map, tags: :list}

      # Valid data
      data = %{id: "test", count: 42, config: %{}, tags: ["a", "b"]}
      assert {:ok, ^data} = Foundation.Perimeter.validate_internal(data, schema)

      # Invalid types
      assert {:error, errors} = Foundation.Perimeter.validate_internal(
        %{id: 123, count: "not integer", config: "not map", tags: "not list"}, 
        schema
      )
      
      assert Enum.any?(errors, fn {field, msg} -> field == :id and msg == "expected string" end)
      assert Enum.any?(errors, fn {field, msg} -> field == :count and msg == "expected integer" end)
      assert Enum.any?(errors, fn {field, msg} -> field == :config and msg == "expected map" end)
      assert Enum.any?(errors, fn {field, msg} -> field == :tags and msg == "expected list" end)
    end

    test "allows missing fields (permissive)" do
      schema = %{optional: :string}
      assert {:ok, %{}} = Foundation.Perimeter.validate_internal(%{}, schema)
    end

    test "accepts non-map input (permissive)" do
      assert {:ok, "anything"} = Foundation.Perimeter.validate_internal("anything", %{})
      assert {:ok, 123} = Foundation.Perimeter.validate_internal(123, %{})
    end
  end

  describe "trusted validation" do
    test "always succeeds immediately" do
      assert {:ok, "anything"} = Foundation.Perimeter.validate_trusted("anything", %{})
      assert {:ok, %{any: "data"}} = Foundation.Perimeter.validate_trusted(%{any: "data"}, %{})
      assert {:ok, nil} = Foundation.Perimeter.validate_trusted(nil, %{})
      assert {:ok, 123} = Foundation.Perimeter.validate_trusted(123, :ignored_schema)
    end
  end

  describe "real-world usage patterns" do
    test "external API endpoint pattern" do
      # Simulate API endpoint validation
      api_params = %{
        name: "Test User",
        email: "test@example.com", 
        age: 25
      }

      schema = %{
        name: {:string, required: true, min: 1, max: 100},
        email: {:string, required: true},
        age: {:integer, required: false}
      }

      assert {:ok, validated} = Foundation.Perimeter.validate_external(api_params, schema)
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

      assert {:ok, validated} = Foundation.Perimeter.validate_internal(task_data, schema)
      assert validated == task_data
    end

    test "trusted high-performance path pattern" do
      # Simulate hot path in signal routing
      signal = %{from: :agent_1, to: :agent_2, message: "urgent", priority: :high}

      # No validation overhead
      assert {:ok, ^signal} = Foundation.Perimeter.validate_trusted(signal, :any)
    end
  end
end