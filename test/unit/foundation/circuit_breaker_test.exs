defmodule Foundation.CircuitBreakerTest do
  use ExUnit.Case, async: true

  alias Foundation.CircuitBreaker

  describe "new/2" do
    test "creates a circuit breaker with defaults" do
      cb = CircuitBreaker.new("test-endpoint")
      assert cb.name == "test-endpoint"
      assert cb.state == :closed
      assert cb.failure_count == 0
      assert cb.failure_threshold == 5
      assert cb.reset_timeout_ms == 30_000
      assert cb.half_open_max_calls == 1
    end

    test "creates a circuit breaker with custom options" do
      cb =
        CircuitBreaker.new("custom",
          failure_threshold: 3,
          reset_timeout_ms: 10_000,
          half_open_max_calls: 2
        )

      assert cb.failure_threshold == 3
      assert cb.reset_timeout_ms == 10_000
      assert cb.half_open_max_calls == 2
    end
  end

  describe "record_failure/1" do
    test "opens circuit when threshold reached" do
      cb =
        CircuitBreaker.new("test", failure_threshold: 2)
        |> CircuitBreaker.record_failure()
        |> CircuitBreaker.record_failure()

      assert cb.state == :open
      assert cb.opened_at != nil
    end
  end

  describe "state/1" do
    test "returns half_open after reset timeout" do
      cb =
        CircuitBreaker.new("test", failure_threshold: 1, reset_timeout_ms: 0)
        |> CircuitBreaker.record_failure()

      Process.sleep(10)

      assert CircuitBreaker.state(cb) == :half_open
    end
  end

  describe "call/3" do
    test "returns circuit_open when open" do
      cb =
        CircuitBreaker.new("test", failure_threshold: 1)
        |> CircuitBreaker.record_failure()

      {result, _cb} = CircuitBreaker.call(cb, fn -> {:ok, :ok} end)
      assert {:error, :circuit_open} = result
    end

    test "records failures based on custom success classifier" do
      cb = CircuitBreaker.new("test", failure_threshold: 5)

      {_, updated_cb} =
        CircuitBreaker.call(
          cb,
          fn -> {:error, %{status: 400}} end,
          success?: fn
            {:ok, _} -> true
            {:error, %{status: status}} when status < 500 -> true
            _ -> false
          end
        )

      assert updated_cb.failure_count == 0
    end
  end
end
