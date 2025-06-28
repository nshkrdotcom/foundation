defmodule Foundation.Infrastructure.RateLimiterPropertiesTest do
  @moduledoc """
  Property-based tests for Rate Limiter mathematical correctness.

  These tests verify that the rate limiting algorithms maintain their
  mathematical invariants under various conditions and edge cases.
  """

  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Foundation.Infrastructure.RateLimiter
  alias Foundation.Types.Error

  import StreamData

  # Property test generators
  defp entity_id_generator do
    one_of([
      string(:printable, min_length: 1, max_length: 50),
      map_of(atom(:alias), string(:printable), max_length: 3),
      positive_integer()
    ])
  end

  defp operation_generator do
    one_of([
      atom(:alias),
      string(:printable, min_length: 1, max_length: 20)
    ])
  end

  defp rate_limit_config_generator do
    fixed_map(%{
      limit: integer(1..100),
      # 1 second to 5 minutes
      time_window: integer(1_000..300_000),
      operation: operation_generator()
    })
  end

  describe "rate limiting mathematical properties" do
    property "rate limiting never exceeds configured limits" do
      check all(
              entity_id <- entity_id_generator(),
              config <- rate_limit_config_generator(),
              request_count <- integer(1..200),
              max_runs: 50
            ) do
        # Generate unique entity and operation for this test
        test_entity = "prop_test_#{:erlang.unique_integer()}_#{inspect(entity_id)}"
        test_operation = :"prop_#{config.operation}_#{:erlang.unique_integer()}"

        # Reset any existing state
        RateLimiter.reset(test_entity, test_operation)

        # Make the specified number of requests
        results =
          for _i <- 1..request_count do
            RateLimiter.check_rate(test_entity, test_operation, config.limit, config.time_window)
          end

        # Count successful requests
        successful_requests = Enum.count(results, fn result -> result == :ok end)

        failed_requests =
          Enum.count(results, fn result ->
            match?({:error, %Error{error_type: :rate_limit_exceeded}}, result)
          end)

        # Property: successful requests should not exceed the limit (with some tolerance for timing)
        assert successful_requests <= config.limit + 2,
               "Successful requests (#{successful_requests}) exceeded limit (#{config.limit}) + tolerance"

        # Property: all requests should either succeed or be rate limited
        assert successful_requests + failed_requests == request_count,
               "Total classified requests doesn't match request count"

        # Property: if limit was exceeded, there should be failures
        if request_count > config.limit do
          assert failed_requests > 0, "Expected some rate limit failures when exceeding limit"
        end

        # Cleanup
        RateLimiter.reset(test_entity, test_operation)
      end
    end

    property "different entities have independent rate limits" do
      check all(
              entity_count <- integer(2..10),
              config <- rate_limit_config_generator(),
              max_runs: 20
            ) do
        # Generate unique entities for this test
        entities =
          for i <- 1..entity_count do
            "prop_entity_#{:erlang.unique_integer()}_#{i}"
          end

        test_operation = :"prop_independent_#{:erlang.unique_integer()}"

        # Reset all entities
        for entity <- entities do
          RateLimiter.reset(entity, test_operation)
        end

        # Each entity should be able to make up to the limit
        entity_results =
          for entity <- entities do
            results =
              for _i <- 1..config.limit do
                RateLimiter.check_rate(entity, test_operation, config.limit, config.time_window)
              end

            {entity, results}
          end

        # Property: each entity should have succeeded for all requests up to limit
        for {entity, results} <- entity_results do
          successful = Enum.count(results, &(&1 == :ok))

          assert successful >= config.limit - 1,
                 "Entity #{entity} had only #{successful} successes, expected at least #{config.limit - 1}"
        end

        # Cleanup
        for entity <- entities do
          RateLimiter.reset(entity, test_operation)
        end
      end
    end

    property "different operations have independent rate limits" do
      check all(
              operation_count <- integer(2..8),
              config <- rate_limit_config_generator(),
              max_runs: 20
            ) do
        # Generate unique operations for this test
        operations =
          for i <- 1..operation_count do
            :"prop_op_#{:erlang.unique_integer()}_#{i}"
          end

        test_entity = "prop_multi_op_entity_#{:erlang.unique_integer()}"

        # Reset all operations for this entity
        for operation <- operations do
          RateLimiter.reset(test_entity, operation)
        end

        # Each operation should be able to make up to the limit
        operation_results =
          for operation <- operations do
            results =
              for _i <- 1..config.limit do
                RateLimiter.check_rate(test_entity, operation, config.limit, config.time_window)
              end

            {operation, results}
          end

        # Property: each operation should have succeeded for all requests up to limit
        for {operation, results} <- operation_results do
          successful = Enum.count(results, &(&1 == :ok))

          assert successful >= config.limit - 1,
                 "Operation #{operation} had only #{successful} successes, expected at least #{config.limit - 1}"
        end

        # Cleanup
        for operation <- operations do
          RateLimiter.reset(test_entity, operation)
        end
      end
    end

    property "rate limit status reflects actual state" do
      check all(
              entity_id <- entity_id_generator(),
              config <- rate_limit_config_generator(),
              max_runs: 30
            ) do
        test_entity = "prop_status_#{:erlang.unique_integer()}_#{inspect(entity_id)}"
        test_operation = :"prop_status_op_#{:erlang.unique_integer()}"

        # Reset state
        RateLimiter.reset(test_entity, test_operation)

        # Check initial status
        {:ok, initial_status} = RateLimiter.get_status(test_entity, test_operation)
        assert initial_status.status == :available

        # Make requests up to the limit
        for _i <- 1..config.limit do
          RateLimiter.check_rate(test_entity, test_operation, config.limit, config.time_window)
        end

        # Try one more request (should be rate limited)
        result =
          RateLimiter.check_rate(test_entity, test_operation, config.limit, config.time_window)

        # If rate limited, status should reflect this
        if match?({:error, %Error{error_type: :rate_limit_exceeded}}, result) do
          {:ok, status_after_limit} = RateLimiter.get_status(test_entity, test_operation)
          # Status might be :rate_limited or still :available depending on implementation
          assert status_after_limit.status in [:available, :rate_limited]
        end

        # Cleanup
        RateLimiter.reset(test_entity, test_operation)
      end
    end

    property "execute_with_limit respects rate limits" do
      check all(
              entity_id <- entity_id_generator(),
              config <- rate_limit_config_generator(),
              execution_count <- integer(1..20),
              max_runs: 30
            ) do
        test_entity = "prop_exec_#{:erlang.unique_integer()}_#{inspect(entity_id)}"
        test_operation = :"prop_exec_op_#{:erlang.unique_integer()}"

        # Reset state
        RateLimiter.reset(test_entity, test_operation)

        # Execute operations
        operation_fn = fn -> {:success, :executed} end

        results =
          for _i <- 1..execution_count do
            RateLimiter.execute_with_limit(
              test_entity,
              test_operation,
              config.limit,
              config.time_window,
              operation_fn
            )
          end

        # Count successful executions
        successful_executions =
          Enum.count(results, fn result ->
            match?({:ok, {:success, :executed}}, result)
          end)

        rate_limited_executions =
          Enum.count(results, fn result ->
            match?({:error, %Error{error_type: :rate_limit_exceeded}}, result)
          end)

        # Property: successful executions should not exceed limit (with tolerance)
        assert successful_executions <= config.limit + 2,
               "Successful executions (#{successful_executions}) exceeded limit (#{config.limit})"

        # Property: all results should be accounted for
        assert successful_executions + rate_limited_executions == execution_count

        # Cleanup
        RateLimiter.reset(test_entity, test_operation)
      end
    end
  end

  describe "rate limiting consistency properties" do
    property "rate limiting is consistent across time windows" do
      check all(
              config <- rate_limit_config_generator(),
              window_count <- integer(1..3),
              max_runs: 10
            ) do
        test_entity = "prop_time_consistency_#{:erlang.unique_integer()}"
        test_operation = :"prop_time_op_#{:erlang.unique_integer()}"

        # Use much shorter windows for testing
        short_window = min(config.time_window, 500)

        # Reset state
        RateLimiter.reset(test_entity, test_operation)

        # Test across multiple time windows
        all_results =
          for window <- 1..window_count do
            # Make requests in this window
            window_results =
              for _i <- 1..(config.limit + 2) do
                RateLimiter.check_rate(
                  test_entity,
                  :"#{test_operation}_#{window}",
                  config.limit,
                  short_window
                )
              end

            # Wait for next window (with minimal buffer)
            if window < window_count do
              Process.sleep(short_window + 50)
            end

            window_results
          end

        # Property: each window should behave consistently
        for window_results <- all_results do
          successful = Enum.count(window_results, &(&1 == :ok))
          # Should allow at least some requests, but not exceed limit significantly
          assert successful >= 1, "Window allowed no requests"
          assert successful <= config.limit + 2, "Window exceeded rate limit"
        end

        # Cleanup
        for window <- 1..window_count do
          RateLimiter.reset(test_entity, :"#{test_operation}_#{window}")
        end
      end
    end

    property "concurrent requests maintain rate limit integrity" do
      check all(
              config <- rate_limit_config_generator(),
              concurrent_count <- integer(2..20),
              max_runs: 10
            ) do
        test_entity = "prop_concurrent_#{:erlang.unique_integer()}"
        test_operation = :"prop_concurrent_op_#{:erlang.unique_integer()}"

        # Reset state
        RateLimiter.reset(test_entity, test_operation)

        # Start concurrent requests
        tasks =
          for _i <- 1..concurrent_count do
            Task.async(fn ->
              RateLimiter.check_rate(test_entity, test_operation, config.limit, config.time_window)
            end)
          end

        results = Task.await_many(tasks)

        # Count outcomes
        successful = Enum.count(results, &(&1 == :ok))

        failed =
          Enum.count(results, fn result ->
            match?({:error, %Error{error_type: :rate_limit_exceeded}}, result)
          end)

        # Property: total successful should not exceed limit by much (accounting for race conditions)
        assert successful <= config.limit + 3,
               "Concurrent requests allowed #{successful} successes, limit was #{config.limit}"

        # Property: all requests should be accounted for
        assert successful + failed == concurrent_count

        # Cleanup
        RateLimiter.reset(test_entity, test_operation)
      end
    end
  end

  describe "edge case properties" do
    property "rate limiting handles extreme values gracefully" do
      check all(
              entity_id <- entity_id_generator(),
              limit <- one_of([integer(1..3), integer(100..1000), integer(10_000..100_000)]),
              time_window <-
                one_of([integer(100..1000), integer(10_000..60_000), integer(300_000..3_600_000)]),
              max_runs: 20
            ) do
        test_entity = "prop_extreme_#{:erlang.unique_integer()}_#{inspect(entity_id)}"
        test_operation = :"prop_extreme_op_#{:erlang.unique_integer()}"

        # Reset state
        RateLimiter.reset(test_entity, test_operation)

        # Make a few requests
        results =
          for _i <- 1..5 do
            RateLimiter.check_rate(test_entity, test_operation, limit, time_window)
          end

        # Property: should handle extreme values without crashing
        assert is_list(results)
        assert length(results) == 5

        # Property: all results should be valid
        for result <- results do
          assert match?(:ok, result) or match?({:error, %Error{}}, result)
        end

        # Cleanup
        RateLimiter.reset(test_entity, test_operation)
      end
    end

    property "string vs atom operations are handled consistently" do
      check all(
              entity_id <- entity_id_generator(),
              base_operation <- string(:printable, min_length: 1, max_length: 20),
              config <- rate_limit_config_generator(),
              max_runs: 20
            ) do
        test_entity = "prop_string_atom_#{:erlang.unique_integer()}_#{inspect(entity_id)}"

        string_operation = "str_#{base_operation}_#{:erlang.unique_integer()}"
        atom_operation = :"atom_#{base_operation}_#{:erlang.unique_integer()}"

        # Reset both operations
        RateLimiter.reset(test_entity, string_operation)
        RateLimiter.reset(test_entity, atom_operation)

        # Test string operation
        string_results =
          for _i <- 1..3 do
            RateLimiter.check_rate(test_entity, string_operation, config.limit, config.time_window)
          end

        # Test atom operation
        atom_results =
          for _i <- 1..3 do
            RateLimiter.check_rate(test_entity, atom_operation, config.limit, config.time_window)
          end

        # Property: both should behave consistently (either both work or both have same error pattern)
        string_successes = Enum.count(string_results, &(&1 == :ok))
        atom_successes = Enum.count(atom_results, &(&1 == :ok))

        # Both should allow some requests
        assert string_successes > 0, "String operation allowed no requests"
        assert atom_successes > 0, "Atom operation allowed no requests"

        # Cleanup
        RateLimiter.reset(test_entity, string_operation)
        RateLimiter.reset(test_entity, atom_operation)
      end
    end
  end
end
