defmodule Foundation.RaceConditionTest do
  @moduledoc """
  Tests to verify race condition fixes in critical services.
  """
  use ExUnit.Case, async: true

  alias Foundation.Services.RateLimiter

  describe "RateLimiter race condition fix" do
    test "rate limiter has no race conditions under concurrent load" do
      # Use existing RateLimiter instance

      RateLimiter.configure_limiter(:test_limiter, %{
        scale_ms: 1000,
        limit: 100,
        cleanup_interval: 60_000
      })

      # Clear any existing state
      Process.sleep(10)

      # Spawn 200 concurrent requests (2x the limit)
      parent = self()

      tasks =
        for i <- 1..200 do
          Task.async(fn ->
            result = RateLimiter.check_rate_limit(:test_limiter, "user_1")
            send(parent, {:result, i, result})
            result
          end)
        end

      # Collect results
      results = for task <- tasks, do: Task.await(task)

      # Exactly 100 should be allowed, 100 denied
      allowed = Enum.count(results, &match?({:ok, :allowed}, &1))
      denied = Enum.count(results, &match?({:ok, :denied}, &1))

      assert allowed == 100
      assert denied == 100
    end

    test "rate limiter correctly handles rapid fire requests" do
      # Use existing RateLimiter instance

      RateLimiter.configure_limiter(:rapid_test, %{
        # 100ms window
        scale_ms: 100,
        limit: 10,
        cleanup_interval: 60_000
      })

      # Clear any existing state
      Process.sleep(10)

      # Fire 20 requests as fast as possible
      results =
        for _ <- 1..20 do
          RateLimiter.check_rate_limit(:rapid_test, "user_2")
        end

      allowed = Enum.count(results, &match?({:ok, :allowed}, &1))
      denied = Enum.count(results, &match?({:ok, :denied}, &1))

      assert allowed == 10
      assert denied == 10
    end

    test "rate limiter correctly resets after window expires" do
      # Use existing RateLimiter instance

      RateLimiter.configure_limiter(:window_test, %{
        # 50ms window
        scale_ms: 50,
        limit: 5,
        cleanup_interval: 60_000
      })

      # First batch - should allow 5
      first_batch =
        for _ <- 1..7 do
          RateLimiter.check_rate_limit(:window_test, "user_3")
        end

      first_allowed = Enum.count(first_batch, &match?({:ok, :allowed}, &1))
      assert first_allowed == 5

      # Wait for window to expire
      Process.sleep(60)

      # Second batch - should allow 5 more
      second_batch =
        for _ <- 1..7 do
          RateLimiter.check_rate_limit(:window_test, "user_3")
        end

      second_allowed = Enum.count(second_batch, &match?({:ok, :allowed}, &1))
      assert second_allowed == 5
    end

    test "rate limiter handles concurrent different keys" do
      # Use existing RateLimiter instance

      RateLimiter.configure_limiter(:multi_key_test, %{
        scale_ms: 1000,
        limit: 10,
        cleanup_interval: 60_000
      })

      # Clear any existing state
      Process.sleep(10)

      # Spawn concurrent requests for different users
      tasks =
        for user_id <- 1..5, _request <- 1..15 do
          Task.async(fn ->
            result = RateLimiter.check_rate_limit(:multi_key_test, "user_#{user_id}")
            {user_id, result}
          end)
        end

      # Collect and group results
      results = for task <- tasks, do: Task.await(task)
      grouped = Enum.group_by(results, fn {user_id, _} -> user_id end)

      # Each user should have exactly 10 allowed
      for {user_id, user_results} <- grouped do
        allowed =
          Enum.count(user_results, fn {_, result} ->
            match?({:ok, :allowed}, result)
          end)

        assert allowed == 10, "User #{user_id} should have exactly 10 allowed requests"
      end
    end
  end
end
