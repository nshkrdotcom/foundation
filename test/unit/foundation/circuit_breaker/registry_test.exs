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
  end

  describe "state/2" do
    test "returns :closed for unknown circuits" do
      registry = Registry.new_registry()
      assert Registry.state(registry, "unknown") == :closed
    end
  end
end
