defmodule Foundation.RateLimit.BackoffWindowTest do
  use ExUnit.Case, async: true

  alias Foundation.RateLimit.BackoffWindow

  describe "registry and limiter management" do
    test "returns the same limiter for the same key" do
      registry = BackoffWindow.new_registry()

      limiter_1 = BackoffWindow.for_key(registry, :api_key)
      limiter_2 = BackoffWindow.for_key(registry, :api_key)

      assert limiter_1 == limiter_2
    end
  end

  describe "backoff windows" do
    test "reports backoff status based on monotonic time" do
      registry = BackoffWindow.new_registry()
      limiter = BackoffWindow.for_key(registry, :service)

      assert false == BackoffWindow.should_backoff?(limiter, time_fun: fn _ -> 0 end)

      assert :ok = BackoffWindow.set(limiter, 100, time_fun: fn _ -> 0 end)

      assert true == BackoffWindow.should_backoff?(limiter, time_fun: fn _ -> 50 end)
      assert false == BackoffWindow.should_backoff?(limiter, time_fun: fn _ -> 150 end)
    end

    test "wait sleeps for the remaining backoff duration" do
      registry = BackoffWindow.new_registry()
      limiter = BackoffWindow.for_key(registry, :service)
      ref = make_ref()
      parent = self()
      counter = :atomics.new(1, signed: true)

      time_fun = fn :millisecond -> :atomics.get(counter, 1) end

      sleep_fun = fn ms ->
        send(parent, {:slept, ref, ms})
        :atomics.add_get(counter, 1, ms)
      end

      :atomics.put(counter, 1, 0)
      assert :ok = BackoffWindow.set(limiter, 100, time_fun: time_fun)
      :atomics.put(counter, 1, 20)
      assert :ok = BackoffWindow.wait(limiter, time_fun: time_fun, sleep_fun: sleep_fun)

      assert_received {:slept, ^ref, 80}
    end

    test "set/3 does not shorten an existing backoff window" do
      registry = BackoffWindow.new_registry()
      limiter = BackoffWindow.for_key(registry, make_ref())
      counter = :atomics.new(1, signed: true)
      time_fun = fn :millisecond -> :atomics.get(counter, 1) end

      assert :ok = BackoffWindow.set(limiter, 100, time_fun: time_fun)

      :atomics.put(counter, 1, 10)
      assert :ok = BackoffWindow.set(limiter, 5, time_fun: time_fun)

      :atomics.put(counter, 1, 50)
      assert BackoffWindow.should_backoff?(limiter, time_fun: time_fun)

      :atomics.put(counter, 1, 101)
      refute BackoffWindow.should_backoff?(limiter, time_fun: time_fun)
    end

    test "wait/2 re-checks when the backoff window is extended while sleeping" do
      registry = BackoffWindow.new_registry()
      limiter = BackoffWindow.for_key(registry, make_ref())
      counter = :atomics.new(1, signed: true)
      parent = self()

      time_fun = fn :millisecond -> :atomics.get(counter, 1) end

      assert :ok = BackoffWindow.set(limiter, 100, time_fun: time_fun)

      sleep_fun = fn ms ->
        send(parent, {:slept, ms})
        now = :atomics.add_get(counter, 1, ms)

        if now == 100 do
          BackoffWindow.set(limiter, 50, time_fun: fn :millisecond -> now end)
        end
      end

      assert :ok = BackoffWindow.wait(limiter, time_fun: time_fun, sleep_fun: sleep_fun)
      assert_received {:slept, 100}
      assert_received {:slept, 50}
    end
  end
end
