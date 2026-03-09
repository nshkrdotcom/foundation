defmodule Foundation.Semaphore.CountingDefaultRegistryTest do
  use ExUnit.Case, async: false

  alias Foundation.Semaphore.Counting

  @default_registry_key {Counting, :default_registry}

  test "default_registry/0 stays valid after the original owner exits" do
    previous = :persistent_term.get(@default_registry_key, :undefined)

    on_exit(fn ->
      case previous do
        :undefined -> :persistent_term.erase(@default_registry_key)
        registry -> :persistent_term.put(@default_registry_key, registry)
      end
    end)

    :persistent_term.erase(@default_registry_key)
    parent = self()

    {_owner_pid, owner_ref} =
      spawn_monitor(fn ->
        send(parent, {:registry, Counting.default_registry()})
      end)

    assert_receive {:registry, original_registry}
    assert_receive {:DOWN, ^owner_ref, :process, _pid, :normal}

    assert Enum.member?(:ets.all(), original_registry)
    assert Counting.default_registry() == original_registry
  end
end
