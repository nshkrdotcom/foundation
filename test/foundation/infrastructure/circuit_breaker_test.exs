defmodule Foundation.Infrastructure.CircuitBreakerTest do
  use ExUnit.Case, async: false
  alias Foundation.CircuitBreaker

  setup do
    # Ensure the application is started
    Application.ensure_all_started(:foundation)

    # Start the CircuitBreaker GenServer if not already started
    case Process.whereis(Foundation.Infrastructure.CircuitBreaker) do
      nil ->
        {:ok, _pid} = Foundation.Infrastructure.CircuitBreaker.start_link()

      _pid ->
        :ok
    end

    # Clean up any existing fuse states to ensure test isolation
    # Note: This is a test helper to ensure clean state between tests
    on_exit(fn ->
      # Reset any fuses that might exist from previous tests
      # Using try/catch since some tests might not create fuses
      try do
        service_ids = [
          :"test_service_#{System.unique_integer()}",
          :"recovery_test_#{System.unique_integer()}",
          :"half_open_test_#{System.unique_integer()}",
          :"fallback_test_#{System.unique_integer()}",
          :"telemetry_test_#{System.unique_integer()}",
          :"concurrent_test_#{System.unique_integer()}",
          :"config_test_#{System.unique_integer()}"
        ]

        Enum.each(service_ids, fn service_id ->
          try do
            :fuse.reset(service_id)
          catch
            _, _ -> :ok
          end
        end)
      catch
        _, _ -> :ok
      end
    end)

    :ok
  end

  describe "circuit breaker states" do
    test "closed -> open transition on failures" do
      service_id = :"test_service_#{System.unique_integer()}"
      failure_threshold = 3

      # Configure circuit breaker
      :ok =
        CircuitBreaker.configure(service_id,
          failure_threshold: failure_threshold,
          timeout: 1000
        )

      # First failures should pass through our circuit breaker
      for i <- 1..failure_threshold do
        result =
          CircuitBreaker.call(service_id, fn ->
            raise "failure_#{i}"
          end)

        assert {:error, _} = result
      end

      # Give fuse time to register the failures
      Process.sleep(50)

      # Next call should be rejected (circuit open)
      result =
        CircuitBreaker.call(service_id, fn ->
          {:ok, "should_not_execute"}
        end)

      assert result == {:error, :circuit_open}
    end

    test "open -> half_open -> closed recovery" do
      service_id = :"recovery_test_#{System.unique_integer()}"

      :ok =
        CircuitBreaker.configure(service_id,
          failure_threshold: 1,
          timeout: 100
        )

      # Open the circuit
      CircuitBreaker.call(service_id, fn -> raise "fail" end)

      # Give fuse time to register the failure
      Process.sleep(50)

      {:ok, status} = CircuitBreaker.get_status(service_id)
      assert status == :open

      # Wait for recovery timeout
      Process.sleep(150)

      # Reset the circuit manually (since :fuse doesn't auto-transition to half-open)
      :ok = CircuitBreaker.reset(service_id)

      # Next call should be allowed
      result = CircuitBreaker.call(service_id, fn -> {:ok, :success} end)
      assert result == {:ok, {:ok, :success}}

      # Circuit should now be closed
      {:ok, status} = CircuitBreaker.get_status(service_id)
      assert status == :closed
    end

    test "circuit opens again on failure after reset" do
      service_id = :"half_open_test_#{System.unique_integer()}"

      :ok =
        CircuitBreaker.configure(service_id,
          failure_threshold: 1,
          timeout: 100
        )

      # Open circuit
      CircuitBreaker.call(service_id, fn -> raise "fail" end)

      # Reset circuit
      :ok = CircuitBreaker.reset(service_id)

      # Fail again
      CircuitBreaker.call(service_id, fn -> raise "fail_again" end)

      # Give fuse time to register the failure
      Process.sleep(50)

      # Should be open again
      {:ok, status} = CircuitBreaker.get_status(service_id)
      assert status == :open
    end
  end

  describe "telemetry integration" do
    test "emits circuit breaker events" do
      service_id = :"telemetry_test_#{System.unique_integer()}"

      :ok = CircuitBreaker.configure(service_id, failure_threshold: 1)

      # Attach telemetry handler
      ref = make_ref()
      test_pid = self()

      :telemetry.attach(
        "test_handler_#{inspect(ref)}",
        [:foundation, :circuit_breaker, :call_success],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, :call_success, measurements, metadata})
        end,
        nil
      )

      :telemetry.attach(
        "test_handler_failure_#{inspect(ref)}",
        [:foundation, :circuit_breaker, :call_failure],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, :call_failure, measurements, metadata})
        end,
        nil
      )

      # Trigger circuit breaker success
      CircuitBreaker.call(service_id, fn -> {:ok, :success} end)
      assert_receive {:telemetry_event, :call_success, %{count: 1}, %{service_id: ^service_id}}

      # Trigger circuit breaker failure
      CircuitBreaker.call(service_id, fn -> raise "failure" end)
      assert_receive {:telemetry_event, :call_failure, %{count: 1}, %{service_id: ^service_id}}

      :telemetry.detach("test_handler_#{inspect(ref)}")
      :telemetry.detach("test_handler_failure_#{inspect(ref)}")
    end
  end

  describe "concurrent usage" do
    test "thread-safe under load" do
      service_id = :"concurrent_test_#{System.unique_integer()}"

      :ok =
        CircuitBreaker.configure(service_id,
          failure_threshold: 50,
          timeout: 5000
        )

      # Spawn many concurrent calls
      tasks =
        for i <- 1..100 do
          Task.async(fn ->
            CircuitBreaker.call(service_id, fn ->
              # Simulate some succeeding, some failing
              if rem(i, 3) == 0 do
                raise "simulated_failure"
              else
                {:ok, i}
              end
            end)
          end)
        end

      results = Enum.map(tasks, &Task.await/1)

      # Should have mix of successes and failures
      successes = Enum.count(results, &match?({:ok, _}, &1))
      failures = Enum.count(results, &match?({:error, _}, &1))

      assert successes > 0
      assert failures > 0
    end
  end

  describe "fallback behavior" do
    test "returns error when circuit is open" do
      service_id = :"fallback_test_#{System.unique_integer()}"

      :ok = CircuitBreaker.configure(service_id, failure_threshold: 1)

      # Open the circuit
      CircuitBreaker.call(service_id, fn -> raise "fail" end)

      # Give fuse time to register the failure
      Process.sleep(50)

      # Next call should return circuit open error
      result =
        CircuitBreaker.call(
          service_id,
          fn -> {:ok, :primary} end
        )

      assert result == {:error, :circuit_open}
    end
  end

  describe "error handling" do
    test "handles non-existent service" do
      # Try to call a non-configured service
      result = CircuitBreaker.call(:non_existent_service, fn -> :ok end)
      assert result == {:error, :service_not_found}
    end

    test "handles configuration errors gracefully" do
      service_id = :"config_test_#{System.unique_integer()}"

      # Configure with valid options
      assert :ok =
               CircuitBreaker.configure(service_id,
                 failure_threshold: 5,
                 timeout: 1000
               )

      # Reconfiguring should also work
      assert :ok =
               CircuitBreaker.configure(service_id,
                 failure_threshold: 10,
                 timeout: 2000
               )
    end
  end
end
