defmodule JidoFoundation.RegistrySupportTest do
  @moduledoc """
  Tests for registry support in JidoFoundation services.

  Verifies that all services can register with test registries for proper test isolation.
  """

  use ExUnit.Case, async: true

  describe "TaskPoolManager registry support" do
    test "registers with test registry when provided" do
      # Start a test registry
      {:ok, registry} = Registry.start_link(keys: :unique, name: :test_registry_taskpool)

      # Start TaskPoolManager with registry option
      {:ok, pid} =
        JidoFoundation.TaskPoolManager.start_link(
          name: :test_taskpool,
          registry: :test_registry_taskpool
        )

      # Verify service is registered
      entries = Registry.lookup(:test_registry_taskpool, {:service, JidoFoundation.TaskPoolManager})
      assert length(entries) == 1
      assert {^pid, %{test_instance: true}} = hd(entries)

      # Clean up
      GenServer.stop(pid)
      GenServer.stop(registry)
    end

    test "works without registry option (backward compatibility)" do
      # Start TaskPoolManager without registry (standard behavior)
      {:ok, pid} = JidoFoundation.TaskPoolManager.start_link(name: :test_taskpool_no_registry)

      # Should work normally
      stats = JidoFoundation.TaskPoolManager.get_all_stats()
      assert is_map(stats)

      # Clean up
      GenServer.stop(pid)
    end
  end

  describe "SystemCommandManager registry support" do
    test "registers with test registry when provided" do
      # Start a test registry
      {:ok, registry} = Registry.start_link(keys: :unique, name: :test_registry_syscmd)

      # Start SystemCommandManager with registry option
      {:ok, pid} =
        JidoFoundation.SystemCommandManager.start_link(
          name: :test_syscmd,
          registry: :test_registry_syscmd
        )

      # Verify service is registered
      entries =
        Registry.lookup(:test_registry_syscmd, {:service, JidoFoundation.SystemCommandManager})

      assert length(entries) == 1
      assert {^pid, %{test_instance: true}} = hd(entries)

      # Clean up
      GenServer.stop(pid)
      GenServer.stop(registry)
    end

    test "works without registry option (backward compatibility)" do
      # Start SystemCommandManager without registry (standard behavior)
      {:ok, pid} = JidoFoundation.SystemCommandManager.start_link(name: :test_syscmd_no_registry)

      # Should work normally
      stats = JidoFoundation.SystemCommandManager.get_stats()
      assert is_map(stats)

      # Clean up
      GenServer.stop(pid)
    end
  end

  describe "CoordinationManager registry support" do
    test "registers with test registry when provided" do
      # Start a test registry
      {:ok, registry} = Registry.start_link(keys: :unique, name: :test_registry_coord)

      # Start CoordinationManager with registry option
      {:ok, pid} =
        JidoFoundation.CoordinationManager.start_link(
          name: :test_coord,
          registry: :test_registry_coord
        )

      # Verify service is registered
      entries =
        Registry.lookup(:test_registry_coord, {:service, JidoFoundation.CoordinationManager})

      assert length(entries) == 1
      assert {^pid, %{test_instance: true}} = hd(entries)

      # Clean up
      GenServer.stop(pid)
      GenServer.stop(registry)
    end

    test "works without registry option (backward compatibility)" do
      # Start CoordinationManager without registry (standard behavior)
      {:ok, pid} = JidoFoundation.CoordinationManager.start_link(name: :test_coord_no_registry)

      # Should work normally
      stats = JidoFoundation.CoordinationManager.get_stats()
      assert is_map(stats)

      # Clean up
      GenServer.stop(pid)
    end
  end

  describe "SchedulerManager registry support" do
    test "registers with test registry when provided" do
      # Start a test registry
      {:ok, registry} = Registry.start_link(keys: :unique, name: :test_registry_sched)

      # Start SchedulerManager with registry option
      {:ok, pid} =
        JidoFoundation.SchedulerManager.start_link(
          name: :test_sched,
          registry: :test_registry_sched
        )

      # Verify service is registered
      entries = Registry.lookup(:test_registry_sched, {:service, JidoFoundation.SchedulerManager})
      assert length(entries) == 1
      assert {^pid, %{test_instance: true}} = hd(entries)

      # Clean up
      GenServer.stop(pid)
      GenServer.stop(registry)
    end

    test "works without registry option (backward compatibility)" do
      # Start SchedulerManager without registry (standard behavior)
      {:ok, pid} = JidoFoundation.SchedulerManager.start_link(name: :test_sched_no_registry)

      # Should work normally
      stats = JidoFoundation.SchedulerManager.get_stats()
      assert is_map(stats)

      # Clean up
      GenServer.stop(pid)
    end
  end

  describe "registry integration with test isolation" do
    test "all services can register with same test registry" do
      # Start a shared test registry
      {:ok, registry} = Registry.start_link(keys: :unique, name: :test_registry_shared)

      # Start all services with the same registry
      {:ok, taskpool_pid} =
        JidoFoundation.TaskPoolManager.start_link(
          name: :shared_taskpool,
          registry: :test_registry_shared
        )

      {:ok, syscmd_pid} =
        JidoFoundation.SystemCommandManager.start_link(
          name: :shared_syscmd,
          registry: :test_registry_shared
        )

      {:ok, coord_pid} =
        JidoFoundation.CoordinationManager.start_link(
          name: :shared_coord,
          registry: :test_registry_shared
        )

      {:ok, sched_pid} =
        JidoFoundation.SchedulerManager.start_link(
          name: :shared_sched,
          registry: :test_registry_shared
        )

      # Verify all services are registered
      all_entries =
        Registry.select(:test_registry_shared, [
          {{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}
        ])

      # Should have 4 service registrations
      service_entries =
        Enum.filter(all_entries, fn
          {{:service, _module}, _pid, _metadata} -> true
          _ -> false
        end)

      assert length(service_entries) == 4

      # Clean up
      GenServer.stop(taskpool_pid)
      GenServer.stop(syscmd_pid)
      GenServer.stop(coord_pid)
      GenServer.stop(sched_pid)
      GenServer.stop(registry)
    end
  end
end
