defmodule Foundation.BackoffTest do
  use ExUnit.Case, async: true

  alias Foundation.Backoff
  alias Foundation.Backoff.Policy

  describe "delay/2" do
    test "computes exponential delays with caps" do
      policy =
        Policy.new(
          strategy: :exponential,
          base_ms: 100,
          max_ms: 1_000,
          jitter_strategy: :none
        )

      assert Backoff.delay(policy, 0) == 100
      assert Backoff.delay(policy, 3) == 800
      assert Backoff.delay(policy, 4) == 1_000
    end

    test "computes linear delays" do
      policy =
        Policy.new(
          strategy: :linear,
          base_ms: 100,
          max_ms: 500,
          jitter_strategy: :none
        )

      assert Backoff.delay(policy, 0) == 100
      assert Backoff.delay(policy, 1) == 200
      assert Backoff.delay(policy, 4) == 500
    end

    test "computes constant delays" do
      policy =
        Policy.new(
          strategy: :constant,
          base_ms: 250,
          max_ms: 1_000,
          jitter_strategy: :none
        )

      assert Backoff.delay(policy, 0) == 250
      assert Backoff.delay(policy, 10) == 250
    end
  end

  describe "jitter strategies" do
    test "applies factor jitter" do
      policy =
        Policy.new(
          strategy: :constant,
          base_ms: 1_000,
          jitter_strategy: :factor,
          jitter: 0.25,
          rand_fun: fn -> 0.0 end
        )

      assert Backoff.delay(policy, 0) == 750

      policy = %{policy | rand_fun: fn -> 1.0 end}
      assert Backoff.delay(policy, 0) == 1_000
    end

    test "applies additive jitter" do
      policy =
        Policy.new(
          strategy: :constant,
          base_ms: 1_000,
          jitter_strategy: :additive,
          jitter: 0.1,
          rand_fun: fn -> 1.0 end
        )

      assert Backoff.delay(policy, 0) == 1_100
    end

    test "supports integer rand_fun for additive jitter" do
      policy =
        Policy.new(
          strategy: :constant,
          base_ms: 1_000,
          jitter_strategy: :additive,
          jitter: 0.1,
          rand_fun: fn max -> max end
        )

      assert Backoff.delay(policy, 0) == 1_100
    end

    test "applies range jitter" do
      policy =
        Policy.new(
          strategy: :constant,
          base_ms: 1_000,
          jitter_strategy: :range,
          jitter: {0.75, 1.0},
          rand_fun: fn -> 0.0 end
        )

      assert Backoff.delay(policy, 0) == 750

      policy = %{policy | rand_fun: fn -> 1.0 end}
      assert Backoff.delay(policy, 0) == 1_000
    end
  end

  describe "sleep/3" do
    test "uses the provided sleep function" do
      policy =
        Policy.new(
          strategy: :constant,
          base_ms: 25,
          jitter_strategy: :none
        )

      ref = make_ref()
      parent = self()

      sleep_fun = fn ms ->
        send(parent, {:slept, ref, ms})
      end

      assert :ok = Backoff.sleep(policy, 0, sleep_fun)
      assert_received {:slept, ^ref, 25}
    end
  end
end
