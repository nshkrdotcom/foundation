defmodule Foundation.RetryTest do
  use ExUnit.Case, async: true

  alias Foundation.Backoff
  alias Foundation.Retry

  defp constant_backoff(ms) do
    Backoff.Policy.new(strategy: :constant, base_ms: ms, max_ms: ms, jitter_strategy: :none)
  end

  describe "step/3" do
    test "retries until max_attempts is reached" do
      policy =
        Retry.Policy.new(
          max_attempts: 2,
          backoff: constant_backoff(10),
          retry_on: fn _result -> true end
        )

      state = Retry.State.new(start_time_ms: 0, last_progress_ms: 0, attempt: 0)

      assert {:retry, 10, state} =
               Retry.step(state, policy, {:error, :boom}, time_fun: fn _ -> 0 end)

      assert state.attempt == 1

      assert {:retry, 10, state} =
               Retry.step(state, policy, {:error, :boom}, time_fun: fn _ -> 0 end)

      assert state.attempt == 2

      assert {:halt, {:error, :boom}, _state} =
               Retry.step(state, policy, {:error, :boom}, time_fun: fn _ -> 0 end)
    end

    test "uses retry_after override when provided" do
      policy =
        Retry.Policy.new(
          max_attempts: 1,
          backoff: constant_backoff(10),
          retry_on: fn _result -> true end,
          retry_after_ms_fun: fn _result -> 123 end
        )

      state = Retry.State.new(start_time_ms: 0, last_progress_ms: 0, attempt: 0)

      assert {:retry, 123, _state} =
               Retry.step(state, policy, {:error, :boom}, time_fun: fn _ -> 0 end)
    end

    test "halts on progress timeout" do
      policy =
        Retry.Policy.new(
          max_attempts: 5,
          backoff: constant_backoff(10),
          retry_on: fn _result -> true end,
          progress_timeout_ms: 50
        )

      state = Retry.State.new(start_time_ms: 0, last_progress_ms: 0, attempt: 1)

      assert {:halt, {:error, :progress_timeout}, _state} =
               Retry.step(state, policy, {:error, :boom}, time_fun: fn _ -> 100 end)
    end
  end

  describe "check_timeouts/3" do
    test "returns progress timeout when exceeded" do
      policy =
        Retry.Policy.new(
          max_attempts: 5,
          backoff: constant_backoff(10),
          retry_on: fn _result -> true end,
          progress_timeout_ms: 50
        )

      state = Retry.State.new(start_time_ms: 0, last_progress_ms: 0, attempt: 1)

      assert {:error, :progress_timeout} =
               Retry.check_timeouts(state, policy, time_fun: fn _ -> 100 end)
    end
  end

  describe "run/3" do
    test "retries with sleep function until success" do
      policy =
        Retry.Policy.new(
          max_attempts: 5,
          backoff: constant_backoff(5),
          retry_on: fn result -> match?({:error, _}, result) end
        )

      parent = self()

      fun = fn ->
        attempt = Process.get(:attempt, 0)
        Process.put(:attempt, attempt + 1)
        send(parent, {:attempt, attempt})

        if attempt < 2 do
          {:error, :nope}
        else
          {:ok, :done}
        end
      end

      sleep_fun = fn ms ->
        send(parent, {:slept, ms})
      end

      assert {{:ok, :done}, state} =
               Retry.run(fun, policy, sleep_fun: sleep_fun, time_fun: fn _ -> 0 end)

      assert state.attempt == 2
      assert_received {:attempt, 0}
      assert_received {:attempt, 1}
      assert_received {:attempt, 2}
      assert_received {:slept, 5}
      assert_received {:slept, 5}
    end
  end
end
