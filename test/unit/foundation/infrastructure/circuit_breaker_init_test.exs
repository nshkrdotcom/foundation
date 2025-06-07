defmodule Foundation.Infrastructure.CircuitBreakerInitTest do
  @moduledoc """
  Test-driven development for circuit breaker initialization functionality.

  These tests document the expected behavior of the initialize_circuit_breaker
  functions that we're implementing to address the API gaps in Foundation.Infrastructure.
  """

  use ExUnit.Case, async: false

  alias Foundation.Infrastructure
  alias Foundation.Types.Error

  setup do
    # Generate unique test names to avoid conflicts
    test_id = :erlang.unique_integer([:positive])
    %{test_id: test_id}
  end

  describe "initialize_circuit_breaker/2" do
    test "initializes a circuit breaker with given configuration", %{test_id: test_id} do
      breaker_name = :"test_breaker_#{test_id}"

      breaker_config = %{
        failure_threshold: 5,
        recovery_time: 30_000
      }

      # This function should exist and now works
      assert :ok = Infrastructure.initialize_circuit_breaker(breaker_name, breaker_config)
    end

    test "returns error for invalid circuit breaker configuration", %{test_id: test_id} do
      breaker_name = :"invalid_breaker_#{test_id}"

      invalid_config = %{
        failure_threshold: "invalid"
        # missing recovery_time
      }

      assert {:error, %Error{error_type: :invalid_configuration}} =
               Infrastructure.initialize_circuit_breaker(breaker_name, invalid_config)
    end

    test "allows using initialized circuit breaker in execute_protected", %{test_id: test_id} do
      breaker_name = :"api_breaker_#{test_id}"

      breaker_config = %{
        failure_threshold: 3,
        recovery_time: 1000
      }

      # Initialize the circuit breaker
      assert :ok = Infrastructure.initialize_circuit_breaker(breaker_name, breaker_config)

      # Should be able to use it in execute_protected
      operation = fn -> {:ok, "success"} end

      assert {:ok, {:ok, "success"}} =
               Infrastructure.execute_protected(
                 :api_test,
                 [circuit_breaker: breaker_name],
                 operation
               )
    end

    test "validates circuit breaker name" do
      breaker_config = %{
        failure_threshold: 5,
        recovery_time: 30_000
      }

      # Should reject invalid names
      assert {:error, %Error{error_type: :invalid_name}} =
               Infrastructure.initialize_circuit_breaker(nil, breaker_config)

      assert {:error, %Error{error_type: :invalid_arguments}} =
               Infrastructure.initialize_circuit_breaker("", breaker_config)
    end

    test "validates required configuration fields", %{test_id: test_id} do
      breaker_name1 = :"test_breaker_missing_threshold_#{test_id}"
      breaker_name2 = :"test_breaker_missing_recovery_#{test_id}"

      # Missing failure_threshold
      incomplete_config = %{
        recovery_time: 30_000
      }

      assert {:error, %Error{error_type: :invalid_configuration}} =
               Infrastructure.initialize_circuit_breaker(breaker_name1, incomplete_config)

      # Missing recovery_time
      incomplete_config2 = %{
        failure_threshold: 5
      }

      assert {:error, %Error{error_type: :invalid_configuration}} =
               Infrastructure.initialize_circuit_breaker(breaker_name2, incomplete_config2)
    end

    test "prevents duplicate circuit breaker names", %{test_id: test_id} do
      breaker_name = :"duplicate_test_#{test_id}"

      breaker_config = %{
        failure_threshold: 5,
        recovery_time: 30_000
      }

      # First initialization should succeed
      assert :ok = Infrastructure.initialize_circuit_breaker(breaker_name, breaker_config)

      # Second initialization with same name should fail
      assert {:error, %Error{error_type: :already_exists}} =
               Infrastructure.initialize_circuit_breaker(breaker_name, breaker_config)
    end
  end

  describe "initialize_circuit_breaker/1 (with defaults)" do
    test "initializes circuit breaker with default configuration", %{test_id: test_id} do
      breaker_name = :"default_breaker_#{test_id}"
      # Should provide reasonable defaults
      assert :ok = Infrastructure.initialize_circuit_breaker(breaker_name)
    end

    test "default configuration works with execute_protected", %{test_id: test_id} do
      breaker_name = :"default_test_breaker_#{test_id}"
      assert :ok = Infrastructure.initialize_circuit_breaker(breaker_name)

      operation = fn -> {:ok, "default_test"} end

      assert {:ok, {:ok, "default_test"}} =
               Infrastructure.execute_protected(
                 :default_test,
                 [circuit_breaker: breaker_name],
                 operation
               )
    end
  end
end
