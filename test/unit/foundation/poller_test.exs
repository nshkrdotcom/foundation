defmodule Foundation.PollerTest do
  use ExUnit.Case, async: true

  alias Foundation.Backoff
  alias Foundation.Poller

  test "retries with backoff until success" do
    parent = self()

    step_fun = fn attempt ->
      send(parent, {:attempt, attempt})

      if attempt < 2 do
        {:retry, :pending}
      else
        {:ok, :done}
      end
    end

    backoff =
      Backoff.Policy.new(
        strategy: :constant,
        base_ms: 5,
        max_ms: 5,
        jitter_strategy: :none
      )

    sleep_fun = fn ms -> send(parent, {:slept, ms}) end

    assert {:ok, :done} = Poller.run(step_fun, backoff: backoff, sleep_fun: sleep_fun)
    assert_received {:attempt, 0}
    assert_received {:attempt, 1}
    assert_received {:attempt, 2}
    assert_received {:slept, 5}
    assert_received {:slept, 5}
  end

  test "halts when timeout is exceeded" do
    counter = :atomics.new(1, signed: true)

    time_fun = fn _unit ->
      :atomics.add_get(counter, 1, 10)
    end

    step_fun = fn _attempt -> {:retry, :pending} end

    assert {:error, :timeout} =
             Poller.run(step_fun, timeout_ms: 5, time_fun: time_fun, backoff: :none)
  end

  test "halts when max_attempts is reached" do
    step_fun = fn _attempt -> {:retry, :pending} end

    assert {:error, :max_attempts} =
             Poller.run(step_fun, max_attempts: 2, backoff: :none)
  end

  test "async/2 returns a task that can be awaited" do
    task = Poller.async(fn _attempt -> {:ok, :done} end)
    assert {:ok, :done} = Poller.await(task, 100)
  end
end
