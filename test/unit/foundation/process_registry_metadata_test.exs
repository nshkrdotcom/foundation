defmodule Foundation.ProcessRegistry.MetadataTest do
  @moduledoc """
  Tests for Foundation.ProcessRegistry metadata support functionality.
  """
  use ExUnit.Case, async: false

  alias Foundation.ProcessRegistry

  setup do
    test_ref = make_ref()
    namespace = {:test, test_ref}

    on_exit(fn ->
      ProcessRegistry.cleanup_test_namespace(test_ref)
    end)

    %{namespace: namespace, test_ref: test_ref}
  end

  describe "register/4 with metadata" do
    test "register service with metadata", %{namespace: namespace} do
      metadata = %{type: :worker, capabilities: [:compute], version: "1.0"}

      assert :ok = ProcessRegistry.register(namespace, :test_service, self(), metadata)
      assert {:ok, pid} = ProcessRegistry.lookup(namespace, :test_service)
      assert pid == self()
    end

    test "register service without metadata (backward compatibility)", %{namespace: namespace} do
      assert :ok = ProcessRegistry.register(namespace, :test_service, self())
      assert {:ok, pid} = ProcessRegistry.lookup(namespace, :test_service)
      assert pid == self()
    end

    test "metadata is optional parameter", %{namespace: namespace} do
      # Test 3-arity call (existing behavior)
      assert :ok = ProcessRegistry.register(namespace, :service1, self())

      # Test 4-arity call with metadata
      metadata = %{test: true}
      assert :ok = ProcessRegistry.register(namespace, :service2, self(), metadata)

      # Both should be registered successfully
      assert {:ok, _} = ProcessRegistry.lookup(namespace, :service1)
      assert {:ok, _} = ProcessRegistry.lookup(namespace, :service2)
    end

    test "validates metadata structure", %{namespace: namespace} do
      # Valid metadata should work
      valid_metadata = %{type: :agent, id: "test-001"}
      assert :ok = ProcessRegistry.register(namespace, :valid_service, self(), valid_metadata)

      # Invalid metadata should be rejected
      assert {:error, :invalid_metadata} =
               ProcessRegistry.register(namespace, :invalid_service, self(), "not a map")

      assert {:error, :invalid_metadata} =
               ProcessRegistry.register(namespace, :invalid_service2, self(), [:not, :a, :map])
    end

    test "handles empty metadata", %{namespace: namespace} do
      assert :ok = ProcessRegistry.register(namespace, :empty_meta_service, self(), %{})
      assert {:ok, pid} = ProcessRegistry.lookup(namespace, :empty_meta_service)
      assert pid == self()
    end
  end

  describe "get_metadata/2" do
    test "retrieves metadata for registered service", %{namespace: namespace} do
      metadata = %{type: :worker, priority: :high}
      :ok = ProcessRegistry.register(namespace, :meta_service, self(), metadata)

      assert {:ok, ^metadata} = ProcessRegistry.get_metadata(namespace, :meta_service)
    end

    test "returns error for unregistered service", %{namespace: namespace} do
      assert {:error, :not_found} = ProcessRegistry.get_metadata(namespace, :nonexistent)
    end

    test "returns empty metadata for service registered without metadata", %{namespace: namespace} do
      :ok = ProcessRegistry.register(namespace, :no_meta_service, self())

      assert {:ok, %{}} = ProcessRegistry.get_metadata(namespace, :no_meta_service)
    end
  end

  describe "lookup_with_metadata/2" do
    test "returns pid and metadata together", %{namespace: namespace} do
      metadata = %{role: :coordinator, node: :local}
      :ok = ProcessRegistry.register(namespace, :coord_service, self(), metadata)

      assert {:ok, {pid, ^metadata}} =
               ProcessRegistry.lookup_with_metadata(namespace, :coord_service)

      assert pid == self()
    end

    test "returns error for unregistered service", %{namespace: namespace} do
      assert :error = ProcessRegistry.lookup_with_metadata(namespace, :missing_service)
    end

    test "returns empty metadata for service without metadata", %{namespace: namespace} do
      :ok = ProcessRegistry.register(namespace, :basic_service, self())

      assert {:ok, {pid, %{}}} = ProcessRegistry.lookup_with_metadata(namespace, :basic_service)
      assert pid == self()
    end
  end

  describe "update_metadata/3" do
    test "updates metadata for existing service", %{namespace: namespace} do
      initial_metadata = %{version: "1.0", status: :starting}
      :ok = ProcessRegistry.register(namespace, :update_service, self(), initial_metadata)

      updated_metadata = %{version: "1.1", status: :running}
      assert :ok = ProcessRegistry.update_metadata(namespace, :update_service, updated_metadata)

      assert {:ok, ^updated_metadata} = ProcessRegistry.get_metadata(namespace, :update_service)
    end

    test "returns error for unregistered service", %{namespace: namespace} do
      metadata = %{test: true}

      assert {:error, :not_found} =
               ProcessRegistry.update_metadata(namespace, :missing_service, metadata)
    end

    test "validates metadata structure in updates", %{namespace: namespace} do
      :ok = ProcessRegistry.register(namespace, :validate_service, self(), %{initial: true})

      # Valid update
      assert :ok = ProcessRegistry.update_metadata(namespace, :validate_service, %{updated: true})

      # Invalid update
      assert {:error, :invalid_metadata} =
               ProcessRegistry.update_metadata(namespace, :validate_service, "invalid")
    end

    test "supports partial metadata updates", %{namespace: namespace} do
      initial = %{a: 1, b: 2, c: 3}
      :ok = ProcessRegistry.register(namespace, :partial_service, self(), initial)

      # Update should replace entirely (not merge)
      partial_update = %{a: 10, d: 4}
      assert :ok = ProcessRegistry.update_metadata(namespace, :partial_service, partial_update)

      assert {:ok, ^partial_update} = ProcessRegistry.get_metadata(namespace, :partial_service)
    end
  end

  describe "list_services_with_metadata/1" do
    test "returns all services with their metadata", %{namespace: namespace} do
      # Register multiple services with different metadata
      :ok = ProcessRegistry.register(namespace, :service1, self(), %{type: :worker})

      {:ok, service2_pid} = Task.start(fn -> Process.sleep(:infinity) end)
      :ok = ProcessRegistry.register(namespace, :service2, service2_pid, %{type: :coordinator})

      :ok = ProcessRegistry.register(namespace, :service3, self(), %{})

      services = ProcessRegistry.list_services_with_metadata(namespace)

      assert is_map(services)
      assert map_size(services) == 3

      assert %{type: :worker} = services[:service1]
      assert %{type: :coordinator} = services[:service2]
      assert %{} = services[:service3]

      # Cleanup
      Process.exit(service2_pid, :shutdown)
    end

    test "returns empty map for namespace with no services", %{namespace: namespace} do
      assert %{} = ProcessRegistry.list_services_with_metadata(namespace)
    end
  end

  describe "metadata search functionality" do
    test "find_services_by_metadata/2", %{namespace: namespace} do
      # Register services with different metadata
      :ok = ProcessRegistry.register(namespace, :worker1, self(), %{type: :worker, priority: :high})

      {:ok, worker2_pid} = Task.start(fn -> Process.sleep(:infinity) end)

      :ok =
        ProcessRegistry.register(namespace, :worker2, worker2_pid, %{type: :worker, priority: :low})

      {:ok, coordinator_pid} = Task.start(fn -> Process.sleep(:infinity) end)

      :ok =
        ProcessRegistry.register(namespace, :coordinator, coordinator_pid, %{
          type: :coordinator,
          priority: :high
        })

      # Find services by type
      workers =
        ProcessRegistry.find_services_by_metadata(namespace, fn meta -> meta[:type] == :worker end)

      assert length(workers) == 2
      assert Enum.all?(workers, fn {_service, _pid, meta} -> meta[:type] == :worker end)

      # Find services by priority
      high_priority =
        ProcessRegistry.find_services_by_metadata(namespace, fn meta -> meta[:priority] == :high end)

      assert length(high_priority) == 2
      assert Enum.all?(high_priority, fn {_service, _pid, meta} -> meta[:priority] == :high end)

      # Cleanup
      Process.exit(worker2_pid, :shutdown)
      Process.exit(coordinator_pid, :shutdown)
    end
  end
end
