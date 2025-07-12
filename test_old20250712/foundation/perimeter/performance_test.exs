defmodule Foundation.Perimeter.PerformanceTest do
  use ExUnit.Case
  
  @tag :performance
  test "external validation performance is acceptable" do
    data = %{
      name: "Performance Test",
      email: "bench@test.com",
      age: 30,
      config: %{setting: "value"},
      tags: ["tag1", "tag2"]
    }

    schema = %{
      name: {:string, required: true, min: 1, max: 100},
      email: {:string, required: true},
      age: {:integer, required: false},
      config: {:map, required: false},
      tags: {:list, required: false}
    }

    # Warm up
    for _i <- 1..100 do
      Foundation.Perimeter.validate_external(data, schema)
    end

    # Benchmark external validation
    {time_external, _} = :timer.tc(fn ->
      for _i <- 1..1000 do
        Foundation.Perimeter.validate_external(data, schema)
      end
    end)

    # Should be fast (< 5ms per 1000 operations = 5μs per operation)
    per_op_microseconds = time_external / 1000
    IO.puts "External validation: #{per_op_microseconds}μs per operation"
    assert per_op_microseconds < 5000  # Less than 5ms per 1000 ops
  end

  @tag :performance
  test "internal validation performance is very fast" do
    data = %{
      id: "test",
      count: 42,
      config: %{},
      tags: ["a", "b"]
    }

    schema = %{id: :string, count: :integer, config: :map, tags: :list}

    # Warm up
    for _i <- 1..100 do
      Foundation.Perimeter.validate_internal(data, schema)
    end

    # Benchmark internal validation  
    {time_internal, _} = :timer.tc(fn ->
      for _i <- 1..10000 do
        Foundation.Perimeter.validate_internal(data, schema)
      end
    end)

    # Should be very fast (< 1ms per 10000 operations = 0.1μs per operation)
    per_op_microseconds = time_internal / 10000
    IO.puts "Internal validation: #{per_op_microseconds}μs per operation"
    assert per_op_microseconds < 100  # Less than 0.1ms per 10000 ops
  end

  @tag :performance
  test "trusted validation performance is instant" do
    data = %{any: "data"}

    # Warm up
    for _i <- 1..100 do
      Foundation.Perimeter.validate_trusted(data, :any)
    end

    # Benchmark trusted (should be ~0)
    {time_trusted, _} = :timer.tc(fn ->
      for _i <- 1..100000 do
        Foundation.Perimeter.validate_trusted(data, :any)
      end
    end)

    # Should be instant (< 0.1ms per 100000 operations = 0.001μs per operation)
    per_op_microseconds = time_trusted / 100000
    IO.puts "Trusted validation: #{per_op_microseconds}μs per operation"
    assert per_op_microseconds < 1  # Less than 0.001ms per 100000 ops
  end

  @tag :performance
  test "external contracts performance is reasonable" do
    params = %{
      name: "Test Program",
      description: "Performance test",
      schema_fields: [%{name: :input, type: :string}],
      optimization_config: %{strategy: :simba}
    }

    # Warm up
    for _i <- 1..10 do
      Foundation.Perimeter.External.create_dspex_program(params)
    end

    # Benchmark external contract
    {time_contract, _} = :timer.tc(fn ->
      for _i <- 1..100 do
        Foundation.Perimeter.External.create_dspex_program(params)
      end
    end)

    # Should be reasonable (< 50ms per 100 operations = 0.5ms per operation)
    per_op_microseconds = time_contract / 100
    IO.puts "External contract validation: #{per_op_microseconds}μs per operation"
    assert per_op_microseconds < 50000  # Less than 50ms per 100 ops
  end
end