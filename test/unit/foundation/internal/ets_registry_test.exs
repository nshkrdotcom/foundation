defmodule Foundation.Internal.ETSRegistryTest do
  use ExUnit.Case, async: false

  alias Foundation.CircuitBreaker.Registry
  alias Foundation.Internal.RegistryOwner
  alias Foundation.RateLimit.BackoffWindow
  alias Foundation.Semaphore.Counting

  @registries [Registry, BackoffWindow, Counting]

  test "default registries belong to one supervised owner and survive requesting worker exits" do
    parent = self()

    {worker, ref} =
      spawn_monitor(fn ->
        registries = Enum.map(@registries, & &1.default_registry())
        send(parent, {:registries, registries})
      end)

    assert_receive {:registries, registries}
    assert_receive {:DOWN, ^ref, :process, ^worker, :normal}
    owner = Process.whereis(RegistryOwner)
    assert is_pid(owner)
    refute owner == Process.whereis(:init)

    for {module, table} <- Enum.zip(@registries, registries) do
      assert :ets.info(table, :owner) == owner
      assert :ets.info(table, :heir) == :none
      assert module.default_registry() == table
    end
  end

  test "simultaneous first callers share exactly one table per primitive" do
    restart_owner()
    owner = Process.whereis(RegistryOwner)
    parent = self()

    tasks =
      for _ <- 1..32 do
        Task.async(fn ->
          send(parent, {:ready, self()})

          receive do
            :start -> Enum.map(@registries, & &1.default_registry())
          end
        end)
      end

    for _ <- tasks, do: assert_receive({:ready, _})
    Enum.each(tasks, &send(&1.pid, :start))
    results = Task.await_many(tasks)
    assert length(Enum.uniq(results)) == 1
    tables = :ets.all() |> Enum.filter(&(:ets.info(&1, :owner) == owner))
    assert Enum.sort(tables) == Enum.sort(hd(results))
  end

  test "explicit anonymous and named registries disappear when their owner exits" do
    parent = self()

    {worker, ref} =
      spawn_monitor(fn ->
        tables = [
          Registry.new_registry(),
          BackoffWindow.new_registry(),
          Counting.new_registry(name: :foundation_owned_registry_test)
        ]

        send(parent, {:tables, tables})

        receive do
          :finish -> :ok
        end
      end)

    assert_receive {:tables, tables}

    for table <- tables do
      assert :ets.info(table, :owner) == worker
      assert :ets.info(table, :heir) == :none
    end

    send(worker, :finish)
    assert_receive {:DOWN, ^ref, :process, ^worker, :normal}
    for table <- tables, do: assert(:ets.info(table) == :undefined)
  end

  test "supervised owner restart replaces stale caches and frees old tables" do
    old = Enum.map(@registries, & &1.default_registry())
    restart_owner()
    for table <- old, do: assert(:ets.info(table) == :undefined)
    fresh = Enum.map(@registries, & &1.default_registry())

    for {before, after_restart} <- Enum.zip(old, fresh) do
      refute before == after_restart
      assert :ets.info(after_restart, :owner) == Process.whereis(RegistryOwner)
    end
  end

  defp restart_owner do
    :ok = Supervisor.terminate_child(Foundation.Supervisor, RegistryOwner)
    {:ok, _} = Supervisor.restart_child(Foundation.Supervisor, RegistryOwner)
  end
end
