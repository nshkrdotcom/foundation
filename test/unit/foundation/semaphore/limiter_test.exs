defmodule Foundation.Semaphore.LimiterTest do
  use ExUnit.Case, async: true

  alias Foundation.Semaphore.Counting
  alias Foundation.Semaphore.Limiter

  test "with_semaphore/3 acquires and releases for the default key" do
    registry = Counting.new_registry()
    name = Limiter.get_semaphore(1)
    parent = self()

    result =
      Limiter.with_semaphore(
        1,
        [registry: registry, backoff: [base_ms: 1, max_ms: 1, jitter: 0]],
        fn ->
          send(parent, {:counts, Counting.count(registry, name)})
          :ok
        end
      )

    assert result == :ok
    assert_received {:counts, 1}
    assert Counting.count(registry, name) == 0
  end

  test "with_semaphore/4 isolates keyed semaphores" do
    registry = Counting.new_registry()
    name = Limiter.get_semaphore(:alpha, 2)
    parent = self()

    result =
      Limiter.with_semaphore(
        :alpha,
        2,
        [registry: registry, backoff: [base_ms: 1, max_ms: 1, jitter: 0]],
        fn ->
          send(parent, {:counts, Counting.count(registry, name)})
          :ok
        end
      )

    assert result == :ok
    assert_received {:counts, 1}
    assert Counting.count(registry, name) == 0
  end

  test "with_semaphore/3 sleeps and retries when capacity is full" do
    registry = Counting.new_registry()
    name = Limiter.get_semaphore(1)
    parent = self()

    assert Counting.acquire(registry, name, 1)

    sleep_fun = fn _ms ->
      send(parent, :slept)
      Counting.release(registry, name)
    end

    task =
      Task.async(fn ->
        Limiter.with_semaphore(
          1,
          [
            registry: registry,
            backoff: [base_ms: 1, max_ms: 1, jitter: 0],
            sleep_fun: sleep_fun,
            max_backoff_exponent: 0
          ],
          fn ->
            send(parent, :acquired)
            :ok
          end
        )
      end)

    assert_receive :slept
    assert_receive :acquired
    assert Task.await(task) == :ok
  end
end
