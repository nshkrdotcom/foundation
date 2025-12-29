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

      sleep_fun = fn ms -> send(parent, {:slept, ref, ms}) end

      assert :ok = BackoffWindow.set(limiter, 100, time_fun: fn _ -> 0 end)
      assert :ok = BackoffWindow.wait(limiter, time_fun: fn _ -> 20 end, sleep_fun: sleep_fun)

      assert_received {:slept, ^ref, 80}
    end
  end
end
