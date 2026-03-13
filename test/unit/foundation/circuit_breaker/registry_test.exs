defmodule Foundation.CircuitBreaker.RegistryTest do
  use ExUnit.Case, async: true

  alias Foundation.CircuitBreaker.Registry

  describe "call/4" do
    test "executes function through registry" do
      registry = Registry.new_registry()

      assert {:ok, :ok} =
               Registry.call(registry, "endpoint", fn -> {:ok, :ok} end)
    end

    test "opens circuit after failures and rejects calls" do
      registry = Registry.new_registry()

      failure_opts = [failure_threshold: 1, reset_timeout_ms: 30_000]

      assert {:error, :failed} =
               Registry.call(registry, "endpoint", fn -> {:error, :failed} end, failure_opts)

      assert {:error, :circuit_open} =
               Registry.call(registry, "endpoint", fn -> {:ok, :ok} end, failure_opts)
    end

    test "enforces half-open probe limits before executing concurrent calls" do
      registry = Registry.new_registry()

      opts = [failure_threshold: 1, reset_timeout_ms: 0, half_open_max_calls: 1]

      assert {:error, :failed} =
               Registry.call(registry, "endpoint", fn -> {:error, :failed} end, opts)

      parent = self()
      release_ref = make_ref()

      runner = fn ->
        send(parent, {:ready, self()})

        receive do
          :go -> :ok
        end

        Registry.call(
          registry,
          "endpoint",
          fn ->
            send(parent, {:entered, self()})

            receive do
              ^release_ref -> {:ok, :ok}
            end
          end,
          opts
        )
      end

      task_one = Task.async(runner)
      task_two = Task.async(runner)

      assert_receive {:ready, first_pid}
      assert_receive {:ready, second_pid}

      send(first_pid, :go)
      send(second_pid, :go)

      assert_receive {:entered, entered_pid}
      refute_receive {:entered, _other_pid}, 50

      send(entered_pid, release_ref)

      assert Enum.sort([Task.await(task_one), Task.await(task_two)]) ==
               Enum.sort([{:ok, :ok}, {:error, :circuit_open}])
    end

    test "ignored outcomes do not consume half-open probe capacity" do
      registry = Registry.new_registry()
      opts = [failure_threshold: 1, reset_timeout_ms: 0, half_open_max_calls: 1]

      assert {:error, :failed} =
               Registry.call(registry, "endpoint", fn -> {:error, :failed} end, opts)

      assert {:error, :rate_limited} =
               Registry.call(
                 registry,
                 "endpoint",
                 fn -> {:error, :rate_limited} end,
                 Keyword.put(opts, :success?, fn _result -> :ignore end)
               )

      assert {:ok, :recovered} =
               Registry.call(
                 registry,
                 "endpoint",
                 fn -> {:ok, :recovered} end,
                 Keyword.put(opts, :success?, fn _result -> true end)
               )

      assert Registry.state(registry, "endpoint") == :closed
    end
  end

  describe "state/2" do
    test "returns :closed for unknown circuits" do
      registry = Registry.new_registry()
      assert Registry.state(registry, "unknown") == :closed
    end
  end
end
