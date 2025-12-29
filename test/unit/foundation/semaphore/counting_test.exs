defmodule Foundation.Semaphore.CountingTest do
  use ExUnit.Case, async: true

  alias Foundation.Backoff
  alias Foundation.Semaphore.Counting

  defp constant_backoff(ms) do
    base = max(ms, 1)
    Backoff.Policy.new(strategy: :constant, base_ms: base, max_ms: base, jitter_strategy: :none)
  end

  describe "acquire/release" do
    test "acquires up to the max and releases" do
      registry = Counting.new_registry()
      name = {:test, make_ref()}

      assert Counting.acquire(registry, name, 2)
      assert Counting.acquire(registry, name, 2)
      refute Counting.acquire(registry, name, 2)

      assert Counting.count(registry, name) == 2
      assert :ok = Counting.release(registry, name)
      assert Counting.count(registry, name) == 1
    end
  end

  describe "with_acquire/4" do
    test "executes and releases on success" do
      registry = Counting.new_registry()
      name = {:with_acquire, make_ref()}

      assert {:ok, :done} =
               Counting.with_acquire(registry, name, 1, fn -> :done end)

      assert Counting.count(registry, name) == 0
    end

    test "returns :max when capacity is unavailable" do
      registry = Counting.new_registry()
      name = {:with_acquire, make_ref()}

      assert Counting.acquire(registry, name, 1)

      assert {:error, :max} =
               Counting.with_acquire(registry, name, 1, fn -> :done end)
    end
  end

  describe "acquire_blocking/5" do
    test "blocks and retries using backoff" do
      registry = Counting.new_registry()
      name = {:blocking, make_ref()}

      assert Counting.acquire(registry, name, 1)

      sleep_fun = fn _ms ->
        Counting.release(registry, name)
      end

      assert :ok =
               Counting.acquire_blocking(registry, name, 1, constant_backoff(0),
                 sleep_fun: sleep_fun
               )

      assert Counting.count(registry, name) == 1
    end
  end
end
