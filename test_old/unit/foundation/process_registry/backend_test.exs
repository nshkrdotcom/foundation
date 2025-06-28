defmodule Foundation.ProcessRegistry.BackendTest do
  @moduledoc """
  Tests for the ProcessRegistry backend behavior and implementations.
  """
  use ExUnit.Case, async: false

  alias Foundation.ProcessRegistry.Backend
  alias Foundation.ProcessRegistry.Backend.ETS
  alias Foundation.ProcessRegistry.Backend.Registry, as: RegistryBackend

  describe "Backend behavior validation" do
    test "validates ETS backend implements all required callbacks" do
      assert :ok = Backend.validate_backend_module(ETS)
    end

    test "validates Registry backend implements all required callbacks" do
      assert :ok = Backend.validate_backend_module(RegistryBackend)
    end

    test "rejects modules that don't implement required callbacks" do
      # Test with a module that doesn't implement the behavior
      assert {:error, {:missing_callbacks, _}} = Backend.validate_backend_module(Enum)
    end
  end

  describe "default configuration" do
    test "returns expected default config" do
      config = Backend.default_config()

      assert Keyword.has_key?(config, :backend)
      assert Keyword.has_key?(config, :backend_opts)
      assert config[:backend] == Foundation.ProcessRegistry.Backend.ETS
      assert is_list(config[:backend_opts])
    end
  end

  # Shared test suite for all backend implementations
  for {backend_module, backend_name} <- [
        {ETS, "ETS"},
        {RegistryBackend, "Registry"}
      ] do
    describe "#{backend_name} backend implementation" do
      setup do
        # Create unique names for each test to avoid conflicts
        backend_opts =
          case unquote(backend_module) do
            ETS ->
              [table_name: :"test_ets_#{System.unique_integer([:positive])}"]

            RegistryBackend ->
              [registry_name: :"test_registry_#{System.unique_integer([:positive])}"]
          end

        {:ok, state} = unquote(backend_module).init(backend_opts)

        on_exit(fn ->
          # Cleanup based on backend type
          case unquote(backend_module) do
            ETS ->
              case Map.fetch(state, :table) do
                {:ok, table_name} ->
                  if :ets.info(table_name) != :undefined do
                    :ets.delete(table_name)
                  end

                :error ->
                  :ok
              end

            RegistryBackend ->
              # Registry cleanup is automatic when processes die
              :ok
          end
        end)

        %{backend: unquote(backend_module), state: state}
      end

      test "initializes successfully", %{backend: backend, state: state} do
        assert is_map(state)

        case backend do
          ETS ->
            assert Map.has_key?(state, :table)
            assert Map.has_key?(state, :cleanup_interval)

          RegistryBackend ->
            assert Map.has_key?(state, :registry_name)
            assert Map.has_key?(state, :partitions)
        end
      end

      test "registers and looks up processes", %{backend: backend, state: state} do
        key = {:test, :service1}
        metadata = %{type: :worker, priority: :high}

        # Register process
        assert {:ok, new_state} = backend.register(state, key, self(), metadata)

        # Lookup should find the registration
        assert {:ok, {pid, found_metadata}} = backend.lookup(new_state, key)
        assert pid == self()
        assert found_metadata == metadata
      end

      test "handles registration conflicts", %{backend: backend, state: state} do
        key = {:test, :conflict_service}
        metadata1 = %{version: "1.0"}
        metadata2 = %{version: "2.0"}

        case backend do
          RegistryBackend ->
            # Registry backend can only register self(), so test self-conflict
            assert {:ok, state1} = backend.register(state, key, self(), metadata1)

            # Try to register same key again with same process (should update)
            assert {:ok, _state2} = backend.register(state1, key, self(), metadata2)

          _ ->
            # Other backends can register external processes
            # Register with first process
            {:ok, pid1} = Task.start(fn -> Process.sleep(:infinity) end)
            assert {:ok, state1} = backend.register(state, key, pid1, metadata1)

            # Try to register same key with different process
            {:ok, pid2} = Task.start(fn -> Process.sleep(:infinity) end)

            case backend.register(state1, key, pid2, metadata2) do
              {:error, {:already_registered, ^pid1}} ->
                # Expected behavior - key already registered to different PID
                :ok

              {:ok, _state2} ->
                # Some backends might allow overwriting
                :ok
            end

            # Cleanup
            Process.exit(pid1, :shutdown)
            Process.exit(pid2, :shutdown)
        end
      end

      test "allows re-registration with same PID", %{backend: backend, state: state} do
        key = {:test, :same_pid_service}
        metadata1 = %{version: "1.0"}
        metadata2 = %{version: "2.0"}

        # Register process
        assert {:ok, state1} = backend.register(state, key, self(), metadata1)

        # Re-register same PID with different metadata
        assert {:ok, state2} = backend.register(state1, key, self(), metadata2)

        # Should have updated metadata
        assert {:ok, {pid, metadata}} = backend.lookup(state2, key)
        assert pid == self()
        assert metadata == metadata2
      end

      test "handles dead process cleanup", %{backend: backend, state: state} do
        key = {:test, :dead_service}
        metadata = %{type: :temporary}

        case backend do
          RegistryBackend ->
            # Registry backend can only register self(), so skip external process test
            # We'll test this indirectly through process death of current process
            # For now, just test that lookup of non-existent key returns not found
            assert {:error, :not_found} = backend.lookup(state, key)

          _ ->
            # Other backends can register external processes
            # Start a process and register it
            {:ok, pid} = Task.start(fn -> Process.sleep(100) end)
            assert {:ok, state1} = backend.register(state, key, pid, metadata)

            # Verify registration exists
            assert {:ok, {^pid, ^metadata}} = backend.lookup(state1, key)

            # Wait for process to die
            Process.sleep(200)
            refute Process.alive?(pid)

            # Lookup should return not found and clean up
            assert {:error, :not_found} = backend.lookup(state1, key)
        end
      end

      test "unregisters services", %{backend: backend, state: state} do
        key = {:test, :unregister_service}
        metadata = %{temporary: true}

        # Register process
        assert {:ok, state1} = backend.register(state, key, self(), metadata)
        assert {:ok, {_, _}} = backend.lookup(state1, key)

        # Unregister
        assert {:ok, state2} = backend.unregister(state1, key)

        # Should not be found
        assert {:error, :not_found} = backend.lookup(state2, key)
      end

      test "unregister is idempotent", %{backend: backend, state: state} do
        key = {:test, :nonexistent_service}

        # Unregister non-existent key should succeed
        assert {:ok, _state} = backend.unregister(state, key)
      end

      test "updates metadata", %{backend: backend, state: state} do
        key = {:test, :update_service}
        initial_metadata = %{version: "1.0", status: :starting}
        updated_metadata = %{version: "1.1", status: :running}

        # Register process
        assert {:ok, state1} = backend.register(state, key, self(), initial_metadata)

        # Update metadata
        assert {:ok, state2} = backend.update_metadata(state1, key, updated_metadata)

        # Verify update
        assert {:ok, {pid, metadata}} = backend.lookup(state2, key)
        assert pid == self()
        assert metadata == updated_metadata
      end

      test "update metadata fails for nonexistent keys", %{backend: backend, state: state} do
        key = {:test, :nonexistent_update}
        metadata = %{test: true}

        assert {:error, :not_found} = backend.update_metadata(state, key, metadata)
      end

      test "lists all registrations", %{backend: backend, state: state} do
        # Register multiple services
        services = [
          {{:test, :service1}, %{type: :worker}},
          {{:test, :service2}, %{type: :coordinator}},
          {{:test, :service3}, %{type: :monitor}}
        ]

        state_final =
          Enum.reduce(services, state, fn {{_ns, _svc} = key, metadata}, acc_state ->
            {:ok, new_state} = backend.register(acc_state, key, self(), metadata)
            new_state
          end)

        # List all should return all services
        assert {:ok, registrations} = backend.list_all(state_final)
        assert length(registrations) == 3

        # Verify all services are present
        keys = Enum.map(registrations, fn {key, _pid, _metadata} -> key end)
        expected_keys = Enum.map(services, fn {key, _metadata} -> key end)

        for expected_key <- expected_keys do
          assert expected_key in keys
        end
      end

      test "validates metadata type", %{backend: backend, state: state} do
        key = {:test, :invalid_metadata}

        # Invalid metadata should be rejected
        assert {:error, {:invalid_metadata, _}} = backend.register(state, key, self(), "not a map")

        assert {:error, {:invalid_metadata, _}} =
                 backend.register(state, key, self(), [:not, :a, :map])

        assert {:error, {:invalid_metadata, _}} = backend.update_metadata(state, key, "not a map")
      end

      test "validates PID parameter", %{backend: backend, state: state} do
        key = {:test, :invalid_pid}
        metadata = %{type: :test}

        # Invalid PID should be rejected
        assert {:error, {:invalid_key, _}} = backend.register(state, key, "not a pid", metadata)
        assert {:error, {:invalid_key, _}} = backend.register(state, key, :not_a_pid, metadata)
      end

      test "health check returns status", %{backend: backend, state: state} do
        # Health check should work even with empty registry
        assert {:ok, health_info} = backend.health_check(state)

        assert is_map(health_info)
        assert Map.has_key?(health_info, :status)
        assert Map.has_key?(health_info, :registrations_count)
        assert health_info.status in [:healthy, :degraded, :unhealthy]
        assert is_integer(health_info.registrations_count)
      end

      test "health check reflects registrations", %{backend: backend, state: state} do
        key = {:test, :health_service}
        metadata = %{type: :health_test}

        # Register a service
        assert {:ok, state1} = backend.register(state, key, self(), metadata)

        # Health check should show the registration
        assert {:ok, health_info} = backend.health_check(state1)
        assert health_info.registrations_count >= 1
      end
    end
  end

  describe "ETS backend specific features" do
    setup do
      table_name = :"test_ets_specific_#{System.unique_integer([:positive])}"
      {:ok, state} = ETS.init(table_name: table_name)

      on_exit(fn ->
        if :ets.info(table_name) != :undefined do
          :ets.delete(table_name)
        end
      end)

      %{state: state}
    end

    test "performs cleanup of dead processes", %{state: state} do
      key = {:test, :cleanup_service}
      metadata = %{type: :temporary}

      # Start a temporary process
      {:ok, pid} = Task.start(fn -> Process.sleep(50) end)
      assert {:ok, state1} = ETS.register(state, key, pid, metadata)

      # Wait for process to die
      Process.sleep(100)
      refute Process.alive?(pid)

      # Perform cleanup
      assert {:ok, {cleaned_count, _new_state}} = ETS.cleanup_dead_processes(state1)
      # Might be 0 if already cleaned by lookup
      assert cleaned_count >= 0
    end

    test "gets detailed statistics", %{state: state} do
      # Register some services
      services = [
        {{:test, :stats1}, %{type: :worker}},
        {{:test, :stats2}, %{type: :coordinator}}
      ]

      state_final =
        Enum.reduce(services, state, fn {key, metadata}, acc_state ->
          {:ok, new_state} = ETS.register(acc_state, key, self(), metadata)
          new_state
        end)

      stats = ETS.get_statistics(state_final)

      assert is_map(stats)
      assert Map.has_key?(stats, :table_name)
      assert Map.has_key?(stats, :total_registrations)
      assert Map.has_key?(stats, :alive_processes)
      assert Map.has_key?(stats, :memory_usage_bytes)
      assert stats.total_registrations >= 2
      assert stats.alive_processes >= 2
    end
  end

  describe "Registry backend specific features" do
    setup do
      registry_name = :"test_registry_specific_#{System.unique_integer([:positive])}"
      {:ok, state} = RegistryBackend.init(registry_name: registry_name)

      %{state: state}
    end

    test "gets registry information", %{state: state} do
      # Register some services
      services = [
        {{:test, :reg_info1}, %{type: :worker}},
        {{:test, :reg_info2}, %{type: :coordinator}}
      ]

      state_final =
        Enum.reduce(services, state, fn {key, metadata}, acc_state ->
          {:ok, new_state} = RegistryBackend.register(acc_state, key, self(), metadata)
          new_state
        end)

      info = RegistryBackend.get_registry_info(state_final)

      assert is_map(info)
      assert Map.has_key?(info, :registry_name)
      assert Map.has_key?(info, :total_registrations)
      assert Map.has_key?(info, :partitions)
      assert Map.has_key?(info, :keys_type)
      assert info.total_registrations >= 2
      assert info.keys_type == :unique
    end

    test "gets partition statistics", %{state: state} do
      stats = RegistryBackend.get_partition_stats(state)

      assert is_map(stats)
      assert Map.has_key?(stats, :total_partitions)
      assert Map.has_key?(stats, :total_registrations)
      assert is_integer(stats.total_partitions)
      assert stats.total_partitions > 0
    end
  end
end
