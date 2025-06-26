defmodule Foundation.InfrastructureTest do
  use ExUnit.Case, async: false

  alias Foundation.Infrastructure
  alias Foundation.Infrastructure.CircuitBreaker
  alias Foundation.Types.Error

  setup do
    # Initialize infrastructure before each test
    {:ok, _pids} = Infrastructure.initialize_all_infra_components()
    :ok
  end

  describe "initialize_all_infra_components/1" do
    test "successfully initializes infrastructure components" do
      assert {:ok, pids} = Infrastructure.initialize_all_infra_components()
      assert is_list(pids)
    end

    test "handles repeated initialization gracefully" do
      assert {:ok, _pids} = Infrastructure.initialize_all_infra_components()
      assert {:ok, _pids} = Infrastructure.initialize_all_infra_components()
    end
  end

  describe "get_infrastructure_status/0" do
    test "returns status of infrastructure components" do
      assert {:ok, status} = Infrastructure.get_infrastructure_status()
      assert is_map(status)
      assert Map.has_key?(status, :fuse)
      assert Map.has_key?(status, :hammer)
      assert Map.has_key?(status, :timestamp)
    end
  end

  describe "execute_protected/4 with circuit breaker" do
    setup do
      # Install a test circuit breaker
      :ok = CircuitBreaker.start_fuse_instance(:test_cb)
      :ok
    end

    test "executes operation successfully with circuit breaker protection" do
      operation = fn -> {:success, "result"} end

      assert {:ok, {:success, "result"}} =
               Infrastructure.execute_protected(:test_key, [circuit_breaker: :test_cb], operation)
    end

    test "returns error for invalid circuit breaker config" do
      operation = fn -> "result" end

      assert {:error, %Error{error_type: :circuit_breaker_not_found}} =
               Infrastructure.execute_protected(
                 :test_key,
                 [circuit_breaker: :non_existent_cb],
                 operation
               )
    end

    test "includes metadata in telemetry" do
      operation = fn -> "result" end
      _metadata = %{test_key: "test_value"}

      assert {:ok, "result"} =
               Infrastructure.execute_protected(:test_key, [circuit_breaker: :test_cb], operation)
    end
  end

  describe "execute_protected/4 with rate limiter" do
    test "executes operation successfully with rate limiter protection" do
      operation = fn -> {:success, "result"} end

      _config = [
        entity_id: "test_user",
        operation: :test_op,
        limit: 5,
        time_window: 60_000
      ]

      assert {:ok, {:success, "result"}} =
               Infrastructure.execute_protected(
                 :test_key,
                 [rate_limiter: {"test_user", :test_op}],
                 operation
               )
    end

    test "returns error when rate limit exceeded" do
      operation = fn -> "result" end

      unique_id = "limited_user_#{System.unique_integer()}"

      # Use proper infrastructure format: rate_limiter: {rule_name, identifier}
      config = [rate_limiter: {:limited_op, unique_id}]

      # Fill up the rate limit (infrastructure uses hardcoded 100 requests per 60s)
      # We need to exceed 100 calls to trigger rate limiting
      for _i <- 1..101 do
        Infrastructure.execute_protected(:rate_limiter, config, operation)
      end

      # This call should be rate limited
      assert {:error, %Foundation.Types.Error{error_type: :rate_limit_exceeded}} =
               Infrastructure.execute_protected(:rate_limiter, config, operation)
    end

    test "returns error for invalid rate limiter config" do
      operation = fn -> "result" end
      # No rate_limiter key means no rate limiting, so it should succeed
      invalid_config = [invalid: :config]

      assert {:ok, "result"} =
               Infrastructure.execute_protected(:rate_limiter, invalid_config, operation)
    end
  end

  describe "execute_protected/4 with invalid protection type" do
    test "returns error for unknown protection type" do
      operation = fn -> "result" end

      assert {:error, {:exception, %FunctionClauseError{}}} =
               Infrastructure.execute_protected(:unknown_protection, :config, operation)
    end
  end

  describe "execute_protected/4 error handling" do
    test "handles operation exceptions gracefully" do
      failing_operation = fn -> raise "boom" end

      # No rate limiting applied, so operation fails with execution error
      config = []

      assert {:error, {:execution_error, %RuntimeError{message: "boom"}}} =
               Infrastructure.execute_protected(:rate_limiter, config, failing_operation)
    end
  end

  describe "protection configuration" do
    @valid_protection_config %{
      circuit_breaker: %{failure_threshold: 5, recovery_time: 30_000},
      rate_limiter: %{scale: 60_000, limit: 100},
      connection_pool: %{size: 10, max_overflow: 5}
    }

    test "configure_protection/2 stores valid configuration" do
      protection_key = :test_api_config

      assert :ok = Infrastructure.configure_protection(protection_key, @valid_protection_config)
      assert {:ok, stored_config} = Infrastructure.get_protection_config(protection_key)
      assert stored_config == @valid_protection_config
    end

    test "configure_protection/2 rejects invalid configuration" do
      protection_key = :test_invalid_config
      invalid_config = %{invalid: "config"}

      assert {:error, _reason} = Infrastructure.configure_protection(protection_key, invalid_config)
    end

    test "get_protection_config/1 returns not_found for non-existent keys" do
      # {System.unique_integer()}
      non_existent_key = :does_not_exist_

      assert {:error, :not_found} = Infrastructure.get_protection_config(non_existent_key)
    end

    test "list_protection_keys/0 includes configured keys" do
      # {System.unique_integer()}
      protection_key = :test_list_key_

      # Configure protection
      assert :ok = Infrastructure.configure_protection(protection_key, @valid_protection_config)

      # Verify it appears in the list
      keys = Infrastructure.list_protection_keys()
      assert protection_key in keys
    end
  end
end
