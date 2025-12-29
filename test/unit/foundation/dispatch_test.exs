defmodule Foundation.DispatchTest do
  use ExUnit.Case, async: true

  alias Foundation.Dispatch
  alias Foundation.RateLimit.BackoffWindow
  alias Foundation.Semaphore.Counting

  test "with_rate_limit/3 acquires concurrency and bytes without throttling" do
    registry = Counting.new_registry()
    rate_registry = BackoffWindow.new_registry()
    limiter = BackoffWindow.for_key(rate_registry, :test_key)

    {:ok, pid} =
      Dispatch.start_link(
        key: :test_key,
        registry: registry,
        limiter: limiter,
        concurrency: 2,
        throttled_concurrency: 1,
        byte_budget: 100,
        byte_penalty_multiplier: 10,
        acquire_backoff: [base_ms: 1, max_ms: 1, jitter: 0]
      )

    snapshot = Dispatch.snapshot(pid)
    parent = self()

    result =
      Dispatch.with_rate_limit(pid, 10, fn ->
        concurrency = Counting.count(registry, snapshot.concurrency.name)
        throttled = Counting.count(registry, snapshot.throttled.name)
        %{current_weight: current_weight} = :sys.get_state(snapshot.bytes)

        send(parent, {:counts, concurrency, throttled, current_weight})
        :ok
      end)

    assert result == :ok
    assert_received {:counts, 1, 0, 90}
    assert Counting.count(registry, snapshot.concurrency.name) == 0
    assert Counting.count(registry, snapshot.throttled.name) == 0
  end

  test "with_rate_limit/3 applies throttling after backoff" do
    registry = Counting.new_registry()
    rate_registry = BackoffWindow.new_registry()
    limiter = BackoffWindow.for_key(rate_registry, :test_key)

    {:ok, pid} =
      Dispatch.start_link(
        key: :test_key,
        registry: registry,
        limiter: limiter,
        concurrency: 2,
        throttled_concurrency: 1,
        byte_budget: 100,
        byte_penalty_multiplier: 10,
        acquire_backoff: [base_ms: 1, max_ms: 1, jitter: 0]
      )

    :ok = Dispatch.set_backoff(pid, 100)
    snapshot = Dispatch.snapshot(pid)
    assert snapshot.backoff_active?
    assert BackoffWindow.should_backoff?(limiter)

    parent = self()

    result =
      Dispatch.with_rate_limit(pid, 5, fn ->
        concurrency = Counting.count(registry, snapshot.concurrency.name)
        throttled = Counting.count(registry, snapshot.throttled.name)
        %{current_weight: current_weight} = :sys.get_state(snapshot.bytes)

        send(parent, {:counts, concurrency, throttled, current_weight})
        :ok
      end)

    assert result == :ok
    assert_received {:counts, 1, 1, 50}
  end
end
