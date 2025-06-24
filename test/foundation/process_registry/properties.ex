defmodule Foundation.ProcessRegistry.Properties do
  @moduledoc """
  Property-based tests for Foundation.ProcessRegistry.

  Tests the fundamental invariants that must hold for the registry system:
  - Uniqueness: Each service name can only be registered once per namespace
  - Concurrent operation safety: Multiple processes can safely operate concurrently
  - Metadata consistency: Metadata is preserved and retrievable
  - Agent lifecycle properties: Agent registration/unregistration behaves correctly

  Uses StreamData for property-based testing to generate edge cases and
  stress test the registry under various conditions.
  """

  use ExUnit.Case, async: false
  use ExUnitProperties

  alias Foundation.ProcessRegistry

  setup do
    # Create unique test namespace for this test run
    test_namespace = {:test, make_ref()}

    # Clean up any existing test data
    cleanup_test_namespace(test_namespace)

    on_exit(fn ->
      cleanup_test_namespace(test_namespace)
    end)

    {:ok, test_namespace: test_namespace}
  end

  describe "registry uniqueness invariants" do
    property "each service name can only be registered once per namespace", %{
      test_namespace: test_namespace
    } do
      check all(
              service_name <- atom(:alphanumeric),
              pid1 <- pid_generator(),
              pid2 <- pid_generator(),
              pid1 != pid2
            ) do
        # Register the first PID
        assert :ok = ProcessRegistry.register(test_namespace, service_name, pid1)

        # Attempting to register a different PID to the same service should fail
        case ProcessRegistry.register(test_namespace, service_name, pid2) do
          {:error, {:already_registered, ^pid1}} ->
            assert true

          :ok ->
            flunk("Expected registration to fail due to duplicate service name")

          other ->
            flunk("Unexpected result: #{inspect(other)}")
        end

        # Verify the original registration is still intact
        assert {:ok, ^pid1} = ProcessRegistry.lookup(test_namespace, service_name)
      end
    end

    property "registering the same PID to the same service should succeed", %{
      test_namespace: test_namespace
    } do
      check all(
              service_name <- atom(:alphanumeric),
              pid <- pid_generator(),
              metadata <- metadata_generator()
            ) do
        # Register the service
        assert :ok = ProcessRegistry.register(test_namespace, service_name, pid, metadata)

        # Re-registering the same PID should succeed
        assert :ok = ProcessRegistry.register(test_namespace, service_name, pid, metadata)

        # Verify the registration is still intact
        assert {:ok, ^pid} = ProcessRegistry.lookup(test_namespace, service_name)
      end
    end

    property "dead processes can be replaced in registration", %{
      test_namespace: test_namespace
    } do
      check all(
              service_name <- atom(:alphanumeric),
              metadata <- metadata_generator()
            ) do
        # Create and immediately kill a process
        dead_pid = spawn(fn -> :ok end)
        # Ensure process is dead
        Process.sleep(10)
        refute Process.alive?(dead_pid)

        # Register the dead process
        assert :ok = ProcessRegistry.register(test_namespace, service_name, dead_pid, metadata)

        # Create a new live process
        live_pid = spawn(fn -> Process.sleep(:infinity) end)

        # Should be able to replace the dead process
        assert :ok = ProcessRegistry.register(test_namespace, service_name, live_pid, metadata)

        # Verify the new registration
        assert {:ok, ^live_pid} = ProcessRegistry.lookup(test_namespace, service_name)

        # Clean up
        Process.exit(live_pid, :kill)
      end
    end
  end

  describe "concurrent operation safety" do
    property "concurrent registrations don't corrupt the registry", %{
      test_namespace: test_namespace
    } do
      check all(
              service_names <- list_of(atom(:alphanumeric), min_length: 5, max_length: 20),
              max_runs: 10
            ) do
        # Create unique service names to avoid conflicts
        unique_services = Enum.uniq(service_names)

        # Spawn multiple processes to register services concurrently
        tasks =
          unique_services
          |> Enum.with_index()
          |> Enum.map(fn {service_name, index} ->
            Task.async(fn ->
              pid = spawn(fn -> Process.sleep(:infinity) end)
              metadata = %{index: index, type: :test_agent}

              result = ProcessRegistry.register(test_namespace, service_name, pid, metadata)
              {service_name, pid, result}
            end)
          end)

        # Wait for all registrations to complete
        results = Task.await_many(tasks, 5000)

        # Verify all registrations succeeded
        for {service_name, pid, result} <- results do
          assert result == :ok
          assert {:ok, ^pid} = ProcessRegistry.lookup(test_namespace, service_name)
        end

        # Clean up spawned processes
        for {_service_name, pid, :ok} <- results do
          Process.exit(pid, :kill)
        end
      end
    end

    property "concurrent lookups return consistent results", %{
      test_namespace: test_namespace
    } do
      check all(
              service_name <- atom(:alphanumeric),
              lookup_count <- integer(10..50),
              max_runs: 5
            ) do
        # Register a service
        pid = spawn(fn -> Process.sleep(:infinity) end)
        metadata = %{type: :concurrent_test}
        assert :ok = ProcessRegistry.register(test_namespace, service_name, pid, metadata)

        # Perform concurrent lookups
        tasks =
          1..lookup_count
          |> Enum.map(fn _i ->
            Task.async(fn ->
              ProcessRegistry.lookup(test_namespace, service_name)
            end)
          end)

        # Wait for all lookups to complete
        results = Task.await_many(tasks, 5000)

        # All lookups should return the same result
        for result <- results do
          assert result == {:ok, pid}
        end

        # Clean up
        Process.exit(pid, :kill)
      end
    end
  end

  describe "metadata consistency" do
    property "metadata is preserved through registration and retrieval", %{
      test_namespace: test_namespace
    } do
      check all(
              service_name <- atom(:alphanumeric),
              metadata <- metadata_generator()
            ) do
        pid = spawn(fn -> Process.sleep(:infinity) end)

        # Register with metadata
        assert :ok = ProcessRegistry.register(test_namespace, service_name, pid, metadata)

        # Retrieve metadata and verify it matches
        case ProcessRegistry.lookup_with_metadata(test_namespace, service_name) do
          {:ok, {^pid, retrieved_metadata}} ->
            assert retrieved_metadata == metadata

          other ->
            flunk("Expected metadata lookup to succeed, got: #{inspect(other)}")
        end

        # Clean up
        Process.exit(pid, :kill)
      end
    end

    property "metadata searches work correctly", %{test_namespace: test_namespace} do
      check all(
              agent_configs <- list_of(agent_config_generator(), min_length: 3, max_length: 10),
              search_metadata <- metadata_generator(),
              max_runs: 5
            ) do
        # Register agents with various metadata
        registered_agents =
          agent_configs
          |> Enum.with_index()
          |> Enum.map(fn {{service_name, metadata}, index} ->
            pid = spawn(fn -> Process.sleep(:infinity) end)

            # Add search metadata to some agents randomly
            final_metadata =
              if rem(index, 2) == 0 do
                Map.merge(metadata, search_metadata)
              else
                metadata
              end

            assert :ok = ProcessRegistry.register(test_namespace, service_name, pid, final_metadata)
            {service_name, pid, final_metadata}
          end)

        # Find agents that should have the search metadata
        expected_matches =
          registered_agents
          |> Enum.filter(fn {_name, _pid, metadata} ->
            Map.take(metadata, Map.keys(search_metadata)) == search_metadata
          end)

        # Perform the search
        found_services =
          ProcessRegistry.find_services_by_metadata(test_namespace, fn metadata ->
            Map.take(metadata, Map.keys(search_metadata)) == search_metadata
          end)

        # Verify the search found the expected agents
        found_service_names = Enum.map(found_services, fn {name, _pid, _meta} -> name end)
        expected_service_names = Enum.map(expected_matches, fn {name, _pid, _meta} -> name end)

        assert Enum.sort(found_service_names) == Enum.sort(expected_service_names)

        # Clean up
        for {_name, pid, _meta} <- registered_agents do
          Process.exit(pid, :kill)
        end
      end
    end

    property "metadata updates work correctly", %{test_namespace: test_namespace} do
      check all(
              service_name <- atom(:alphanumeric),
              initial_metadata <- metadata_generator(),
              updated_metadata <- metadata_generator()
            ) do
        pid = spawn(fn -> Process.sleep(:infinity) end)

        # Register with initial metadata
        assert :ok = ProcessRegistry.register(test_namespace, service_name, pid, initial_metadata)

        # Update metadata
        assert :ok = ProcessRegistry.update_metadata(test_namespace, service_name, updated_metadata)

        # Verify the metadata was updated
        case ProcessRegistry.lookup_with_metadata(test_namespace, service_name) do
          {:ok, {^pid, retrieved_metadata}} ->
            assert retrieved_metadata == updated_metadata

          other ->
            flunk("Expected metadata lookup to succeed after update, got: #{inspect(other)}")
        end

        # Clean up
        Process.exit(pid, :kill)
      end
    end
  end

  describe "agent lifecycle properties" do
    property "agent registration/unregistration lifecycle", %{test_namespace: test_namespace} do
      check all(agent_configs <- list_of(agent_config_generator(), min_length: 1, max_length: 5)) do
        registered_pids = []

        try do
          # Register all agents
          registered_pids =
            for {service_name, metadata} <- agent_configs do
              pid = spawn(fn -> Process.sleep(:infinity) end)
              assert :ok = ProcessRegistry.register(test_namespace, service_name, pid, metadata)
              {service_name, pid}
            end

          # Verify all agents are registered and findable
          for {service_name, pid} <- registered_pids do
            assert {:ok, ^pid} = ProcessRegistry.lookup(test_namespace, service_name)
          end

          # Unregister half the agents
          {to_unregister, to_keep} = Enum.split(registered_pids, div(length(registered_pids), 2))

          for {service_name, _pid} <- to_unregister do
            assert :ok = ProcessRegistry.unregister(test_namespace, service_name)
          end

          # Verify unregistered agents are no longer findable
          for {service_name, _pid} <- to_unregister do
            assert :error = ProcessRegistry.lookup(test_namespace, service_name)
          end

          # Verify remaining agents are still findable
          for {service_name, pid} <- to_keep do
            assert {:ok, ^pid} = ProcessRegistry.lookup(test_namespace, service_name)
          end

          :ok
        after
          # Clean up all spawned processes
          for {_service_name, pid} <- registered_pids do
            Process.exit(pid, :kill)
          end
        end
      end
    end

    property "dead process cleanup works correctly", %{test_namespace: test_namespace} do
      check all(
              service_names <- list_of(atom(:alphanumeric), min_length: 2, max_length: 5),
              max_runs: 3
            ) do
        unique_services = Enum.uniq(service_names)

        # Register services with processes that will die
        registered_services =
          for service_name <- unique_services do
            # Dies after 100ms
            pid = spawn(fn -> Process.sleep(100) end)
            metadata = %{type: :temporary, service: service_name}
            assert :ok = ProcessRegistry.register(test_namespace, service_name, pid, metadata)
            {service_name, pid}
          end

        # Wait for processes to die
        Process.sleep(200)

        # Verify all processes are dead
        for {_service_name, pid} <- registered_services do
          refute Process.alive?(pid)
        end

        # Lookups should fail for dead processes (and clean them up)
        for {service_name, _pid} <- registered_services do
          assert :error = ProcessRegistry.lookup(test_namespace, service_name)
        end

        # Verify that new registrations for the same names work
        for {service_name, _old_pid} <- registered_services do
          new_pid = spawn(fn -> Process.sleep(:infinity) end)
          assert :ok = ProcessRegistry.register(test_namespace, service_name, new_pid)
          assert {:ok, ^new_pid} = ProcessRegistry.lookup(test_namespace, service_name)
          Process.exit(new_pid, :kill)
        end
      end
    end
  end

  # Property generators

  defp pid_generator do
    # Generate PIDs for testing (using spawn to create real PIDs)
    gen all(_x <- constant(:ok)) do
      spawn(fn -> Process.sleep(:infinity) end)
    end
  end

  defp metadata_generator do
    gen all(
          type <- member_of([:mabeam_agent, :service, :worker, :coordinator]),
          capabilities <- list_of(atom(:alphanumeric), max_length: 3),
          priority <- integer(1..10),
          custom_fields <-
            map_of(atom(:alphanumeric), one_of([integer(), string(:alphanumeric), boolean()]))
        ) do
      Map.merge(
        %{
          type: type,
          capabilities: capabilities,
          priority: priority
        },
        custom_fields
      )
    end
  end

  defp agent_config_generator do
    gen all(
          service_name <- atom(:alphanumeric),
          metadata <- metadata_generator()
        ) do
      {service_name, metadata}
    end
  end

  # Helper functions

  defp cleanup_test_namespace(namespace) do
    # List all services in the namespace
    try do
      services = ProcessRegistry.list_services_with_metadata(namespace)

      for {service_name, _pid, _metadata} <- services do
        ProcessRegistry.unregister(namespace, service_name)
      end
    rescue
      _ -> :ok
    end

    :ok
  end
end
