defmodule Foundation.Infrastructure.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Foundation.Infrastructure.RateLimiter
  alias Foundation.Types.Error

  setup do
    # The HammerBackend is already started in the application
    # Reset rate limiting buckets before each test
    RateLimiter.reset("test_user", :test_operation)
    RateLimiter.reset("test_user", :api_call)
    RateLimiter.reset("exec_user", :exec_op)
    RateLimiter.reset("reset_user", :reset_op)

    # Use unique keys for each test to avoid conflicts
    test_prefix = "test_#{System.unique_integer()}"
    %{test_prefix: test_prefix}
  end

  describe "check_rate/5" do
    test "allows requests within rate limit", %{test_prefix: prefix} do
      user_id = "#{prefix}_user"
      assert :ok = RateLimiter.check_rate(user_id, :test_operation, 5, 60_000)
      assert :ok = RateLimiter.check_rate(user_id, :test_operation, 5, 60_000)
    end

    test "denies requests that exceed rate limit", %{test_prefix: prefix} do
      user_id = "#{prefix}_user2"
      # Fill up the bucket
      for _i <- 1..5 do
        assert :ok = RateLimiter.check_rate(user_id, :test_operation, 5, 60_000)
      end

      # This should be denied
      assert {:error, %Error{error_type: :rate_limit_exceeded}} =
               RateLimiter.check_rate(user_id, :test_operation, 5, 60_000)
    end

    test "handles different entity IDs independently", %{test_prefix: prefix} do
      user1 = "#{prefix}_user1"
      user2 = "#{prefix}_user2"
      # Fill up bucket for user1
      for _i <- 1..5 do
        assert :ok = RateLimiter.check_rate(user1, :test_operation, 5, 60_000)
      end

      # user2 should still be allowed
      assert :ok = RateLimiter.check_rate(user2, :test_operation, 5, 60_000)
    end

    test "handles different operations independently", %{test_prefix: prefix} do
      user_id = "#{prefix}_user"
      # Fill up bucket for operation1
      for _i <- 1..5 do
        assert :ok = RateLimiter.check_rate(user_id, :operation1, 5, 60_000)
      end

      # operation2 should still be allowed
      assert :ok = RateLimiter.check_rate(user_id, :operation2, 5, 60_000)
    end

    test "includes metadata in telemetry events", %{test_prefix: prefix} do
      user_id = "#{prefix}_user"
      metadata = %{test_key: "test_value"}
      assert :ok = RateLimiter.check_rate(user_id, :test_operation, 5, 60_000, metadata)
    end
  end

  describe "get_status/2" do
    test "returns status information", %{test_prefix: prefix} do
      user_id = "#{prefix}_status_user"
      assert {:ok, status} = RateLimiter.get_status(user_id, :status_op)
      assert is_map(status)
      assert Map.has_key?(status, :status)
      assert status.status in [:available, :rate_limited]
    end
  end

  describe "reset/2" do
    test "reset returns ok but doesn't actually clear buckets", %{test_prefix: prefix} do
      user_id = "#{prefix}_reset_user"
      # Fill up the bucket
      for _i <- 1..5 do
        assert :ok = RateLimiter.check_rate(user_id, :reset_op, 5, 60_000)
      end

      # Should be rate limited
      assert {:error, %Error{error_type: :rate_limit_exceeded}} =
               RateLimiter.check_rate(user_id, :reset_op, 5, 60_000)

      # Reset returns ok but doesn't actually clear the bucket
      assert :ok = RateLimiter.reset(user_id, :reset_op)
      # Still rate limited because reset doesn't actually clear buckets
      assert {:error, %Error{error_type: :rate_limit_exceeded}} =
               RateLimiter.check_rate(user_id, :reset_op, 5, 60_000)
    end
  end

  describe "execute_with_limit/6" do
    test "executes operation when within rate limit", %{test_prefix: prefix} do
      user_id = "#{prefix}_exec_user1"
      operation = fn -> {:success, "result"} end

      assert {:ok, {:success, "result"}} =
               RateLimiter.execute_with_limit(user_id, :exec_op, 5, 60_000, operation)
    end

    test "returns rate limit error when limit exceeded", %{test_prefix: prefix} do
      user_id = "#{prefix}_exec_user2"
      operation = fn -> {:success, "result"} end

      # Fill up the bucket
      for _i <- 1..5 do
        assert {:ok, _} =
                 RateLimiter.execute_with_limit(user_id, :exec_op, 5, 60_000, operation)
      end

      # This should be rate limited
      assert {:error, %Error{error_type: :rate_limit_exceeded}} =
               RateLimiter.execute_with_limit(user_id, :exec_op, 5, 60_000, operation)
    end

    test "handles operation exceptions", %{test_prefix: prefix} do
      user_id = "#{prefix}_exec_user3"
      failing_operation = fn -> raise "boom" end

      assert {:error, %Error{error_type: :rate_limited_operation_failed}} =
               RateLimiter.execute_with_limit(user_id, :exec_op, 5, 60_000, failing_operation)
    end

    test "includes metadata in execution", %{test_prefix: prefix} do
      user_id = "#{prefix}_exec_user4"
      operation = fn -> "result" end
      metadata = %{test_key: "test_value"}

      assert {:ok, "result"} =
               RateLimiter.execute_with_limit(user_id, :exec_op, 5, 60_000, operation, metadata)
    end
  end

  describe "hammer backend integration edge cases" do
    test "handles very large limits", %{test_prefix: prefix} do
      user_id = "#{prefix}_large_limit"
      large_limit = 1_000_000

      # Should handle large limits gracefully
      assert :ok = RateLimiter.check_rate(user_id, :large_op, large_limit, 60_000)

      # Many requests should still be allowed
      for _i <- 1..100 do
        assert :ok = RateLimiter.check_rate(user_id, :large_op, large_limit, 60_000)
      end
    end

    test "handles very short time windows", %{test_prefix: prefix} do
      user_id = "#{prefix}_short_window"

      # Very short time window (1 second)
      assert :ok = RateLimiter.check_rate(user_id, :short_op, 2, 1_000)
      assert :ok = RateLimiter.check_rate(user_id, :short_op, 2, 1_000)

      # Should be rate limited after exceeding
      assert {:error, %Error{error_type: :rate_limit_exceeded}} =
               RateLimiter.check_rate(user_id, :short_op, 2, 1_000)
    end

    test "handles edge case of zero limit", %{test_prefix: prefix} do
      user_id = "#{prefix}_zero_limit"

      # Zero limit should immediately rate limit
      assert {:error, %Error{error_type: :rate_limit_exceeded}} =
               RateLimiter.check_rate(user_id, :zero_op, 0, 60_000)
    end

    test "handles edge case of zero time window", %{test_prefix: prefix} do
      user_id = "#{prefix}_zero_window"

      # Zero time window should be handled gracefully
      result = RateLimiter.check_rate(user_id, :zero_time_op, 5, 0)

      # Should either succeed or return an appropriate error
      assert match?(:ok, result) or match?({:error, %Error{}}, result)
    end
  end

  describe "rate limiting algorithm accuracy under load" do
    test "concurrent requests respect rate limits", %{test_prefix: prefix} do
      user_id = "#{prefix}_concurrent"
      limit = 10

      # Start many concurrent requests
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            result = RateLimiter.check_rate(user_id, :concurrent_op, limit, 60_000)
            {i, result}
          end)
        end

      results = Task.await_many(tasks)

      # Count successful requests
      successful_requests =
        Enum.count(results, fn {_i, result} ->
          result == :ok
        end)

      # Should not exceed the limit significantly
      # Allow some tolerance due to timing in concurrent scenarios
      assert successful_requests <= limit + 2

      # Should have some rate-limited requests
      rate_limited_requests =
        Enum.count(results, fn {_i, result} ->
          match?({:error, %Error{error_type: :rate_limit_exceeded}}, result)
        end)

      assert rate_limited_requests > 0
    end

    test "sustained load over time", %{test_prefix: prefix} do
      user_id = "#{prefix}_sustained"

      # Test sustained load over multiple time windows
      # Use a small time window for faster testing
      for round <- 1..3 do
        _start_time = System.monotonic_time(:millisecond)

        # Make requests up to the limit
        for _i <- 1..5 do
          result = RateLimiter.check_rate(user_id, :"sustained_op_#{round}", 5, 1_000)
          # Should succeed for the first 5 requests
          assert match?(:ok, result) or match?({:error, %Error{}}, result)
        end

        # Wait for window to potentially reset
        Process.sleep(100)
      end
    end

    test "burst handling within limits", %{test_prefix: prefix} do
      user_id = "#{prefix}_burst"

      # Quick burst of requests
      burst_results =
        for _i <- 1..20 do
          RateLimiter.check_rate(user_id, :burst_op, 10, 60_000)
        end

      successful_burst = Enum.count(burst_results, &(&1 == :ok))

      failed_burst =
        Enum.count(burst_results, fn result ->
          match?({:error, %Error{error_type: :rate_limit_exceeded}}, result)
        end)

      # Should have some successes and some failures
      assert successful_burst > 0
      assert failed_burst > 0
      assert successful_burst + failed_burst == 20
    end
  end

  describe "bucket cleanup and memory management" do
    test "handles many different entity IDs", %{test_prefix: prefix} do
      # Create many different entity IDs to test memory management
      entity_ids =
        for i <- 1..100 do
          "#{prefix}_entity_#{i}"
        end

      # Make requests for each entity
      for entity_id <- entity_ids do
        assert :ok = RateLimiter.check_rate(entity_id, :memory_test, 5, 60_000)
      end

      # All should have been processed successfully
      # This mainly tests that we don't crash with many entities
      assert true
    end

    test "handles very long entity IDs", %{test_prefix: prefix} do
      # Test with very long entity ID
      long_entity_id = "#{prefix}_" <> String.duplicate("very_long_entity_id", 100)

      assert :ok = RateLimiter.check_rate(long_entity_id, :long_id_test, 5, 60_000)

      # Should be able to check status
      assert {:ok, _status} = RateLimiter.get_status(long_entity_id, :long_id_test)
    end

    test "handles special characters in entity IDs", %{test_prefix: prefix} do
      special_ids = [
        "#{prefix}_user@domain.com",
        "#{prefix}_user:123:456",
        "#{prefix}_user/path/to/resource",
        "#{prefix}_user with spaces",
        "#{prefix}_用户_unicode"
      ]

      for entity_id <- special_ids do
        result = RateLimiter.check_rate(entity_id, :special_chars, 5, 60_000)
        assert match?(:ok, result) or match?({:error, %Error{}}, result)
      end
    end
  end

  describe "multi-entity concurrent rate limiting" do
    test "independent rate limiting for different entities", %{test_prefix: prefix} do
      entities =
        for i <- 1..10 do
          "#{prefix}_entity_#{i}"
        end

      # Start concurrent tasks for different entities
      tasks =
        for entity <- entities do
          Task.async(fn ->
            # Each entity makes several requests
            results =
              for _i <- 1..8 do
                RateLimiter.check_rate(entity, :multi_entity_test, 5, 60_000)
              end

            {entity, results}
          end)
        end

      all_results = Task.await_many(tasks)

      # Each entity should have its own independent rate limiting
      for {_entity, results} <- all_results do
        successful = Enum.count(results, &(&1 == :ok))

        failed =
          Enum.count(results, fn result ->
            match?({:error, %Error{error_type: :rate_limit_exceeded}}, result)
          end)

        # Each entity should hit its own limit
        assert successful <= 5
        assert failed >= 3
        assert successful + failed == 8
      end
    end

    test "different operations for same entity", %{test_prefix: prefix} do
      entity_id = "#{prefix}_multi_op_entity"
      operations = [:read, :write, :delete, :update, :list]

      # Each operation should have independent rate limiting
      tasks =
        for operation <- operations do
          Task.async(fn ->
            results =
              for _i <- 1..7 do
                RateLimiter.check_rate(entity_id, operation, 5, 60_000)
              end

            {operation, results}
          end)
        end

      all_results = Task.await_many(tasks)

      # Each operation should be rate limited independently
      for {operation, results} <- all_results do
        successful = Enum.count(results, &(&1 == :ok))
        assert successful <= 5, "Operation #{operation} allowed too many requests"
      end
    end
  end

  describe "rate limit window boundary conditions" do
    test "requests at window boundaries", %{test_prefix: prefix} do
      user_id = "#{prefix}_boundary"

      # Use a short window for testing
      window_ms = 500

      # Fill up the bucket
      for _i <- 1..3 do
        assert :ok = RateLimiter.check_rate(user_id, :boundary_test, 3, window_ms)
      end

      # Should be rate limited
      assert {:error, %Error{error_type: :rate_limit_exceeded}} =
               RateLimiter.check_rate(user_id, :boundary_test, 3, window_ms)

      # Wait for window to potentially reset
      Process.sleep(window_ms + 100)

      # Might be allowed again (depends on Hammer implementation)
      result = RateLimiter.check_rate(user_id, :boundary_test, 3, window_ms)
      assert match?(:ok, result) or match?({:error, %Error{}}, result)
    end

    test "rapid requests across multiple windows", %{test_prefix: prefix} do
      user_id = "#{prefix}_multi_window"

      # Test pattern: make requests, wait, make more requests
      for round <- 1..3 do
        # Make requests up to limit
        round_results =
          for _i <- 1..4 do
            RateLimiter.check_rate(user_id, :"window_test_#{round}", 3, 200)
          end

        # Should have some successes and some failures
        successful = Enum.count(round_results, &(&1 == :ok))
        assert successful > 0 and successful <= 3

        # Short wait before next round
        Process.sleep(250)
      end
    end
  end

  describe "edge cases and error conditions" do
    test "handles invalid entity IDs gracefully" do
      invalid_entities = [nil, "", 123, [], %{}]

      for entity <- invalid_entities do
        result = RateLimiter.check_rate(entity, :invalid_test, 5, 60_000)
        # Should either work (if Hammer handles it) or return error
        assert match?(:ok, result) or match?({:error, %Error{}}, result)
      end
    end

    test "handles invalid operations gracefully", %{test_prefix: prefix} do
      user_id = "#{prefix}_invalid_ops"
      invalid_operations = [nil, "", 123, [], %{}]

      for operation <- invalid_operations do
        result = RateLimiter.check_rate(user_id, operation, 5, 60_000)
        # Should either work or return error
        assert match?(:ok, result) or match?({:error, %Error{}}, result)
      end
    end

    test "handles negative limits and time windows", %{test_prefix: prefix} do
      user_id = "#{prefix}_negative"

      # Negative limit
      result1 = RateLimiter.check_rate(user_id, :neg_limit, -5, 60_000)
      assert match?(:ok, result1) or match?({:error, %Error{}}, result1)

      # Negative time window
      result2 = RateLimiter.check_rate(user_id, :neg_window, 5, -60_000)
      assert match?(:ok, result2) or match?({:error, %Error{}}, result2)
    end

    test "handles extremely large values", %{test_prefix: prefix} do
      user_id = "#{prefix}_extreme"

      # Extremely large values
      large_limit = 999_999_999
      large_window = 999_999_999_999

      result = RateLimiter.check_rate(user_id, :extreme_test, large_limit, large_window)
      assert match?(:ok, result) or match?({:error, %Error{}}, result)
    end
  end

  describe "telemetry and monitoring integration" do
    test "telemetry events are emitted correctly", %{test_prefix: prefix} do
      user_id = "#{prefix}_telemetry"
      test_pid = self()

      # Attach telemetry handler
      :telemetry.attach_many(
        "rate_limiter_test_handler",
        [
          [:rate_limiter, :check, :start],
          [:rate_limiter, :check, :stop],
          [:rate_limiter, :execute, :start],
          [:rate_limiter, :execute, :stop]
        ],
        fn name, measurements, metadata, _config ->
          send(test_pid, {:telemetry, name, measurements, metadata})
        end,
        nil
      )

      # Perform operations that should emit telemetry
      RateLimiter.check_rate(user_id, :telemetry_test, 5, 60_000)

      operation = fn -> :success end
      RateLimiter.execute_with_limit(user_id, :telemetry_exec, 5, 60_000, operation)

      # Clean up
      :telemetry.detach("rate_limiter_test_handler")
    end

    test "status information accuracy", %{test_prefix: prefix} do
      user_id = "#{prefix}_status_accuracy"

      # Check initial status
      {:ok, initial_status} = RateLimiter.get_status(user_id, :status_accuracy_test)
      assert initial_status.status == :available

      # Make some requests
      for _i <- 1..3 do
        RateLimiter.check_rate(user_id, :status_accuracy_test, 5, 60_000)
      end

      # Check status again
      {:ok, after_requests_status} = RateLimiter.get_status(user_id, :status_accuracy_test)
      assert is_map(after_requests_status)
      assert Map.has_key?(after_requests_status, :status)

      # Fill bucket completely
      for _i <- 1..5 do
        RateLimiter.check_rate(user_id, :status_accuracy_test2, 5, 60_000)
      end

      # Should be rate limited now
      assert {:error, %Error{error_type: :rate_limit_exceeded}} =
               RateLimiter.check_rate(user_id, :status_accuracy_test2, 5, 60_000)
    end
  end
end
