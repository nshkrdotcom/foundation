defmodule Foundation.FeatureFlagsTest do
  use ExUnit.Case, async: false

  alias Foundation.FeatureFlags

  setup do
    # Start FeatureFlags if not already started
    case Process.whereis(FeatureFlags) do
      nil -> 
        {:ok, _pid} = FeatureFlags.start_link()
      _pid -> 
        :ok
    end

    # Reset to clean state
    FeatureFlags.reset_all()

    on_exit(fn ->
      # Clean up after test
      if Process.whereis(FeatureFlags) do
        try do
          FeatureFlags.reset_all()
        catch
          :exit, _ -> :ok
        end
      end
    end)

    :ok
  end

  describe "basic flag operations" do
    test "flags default to false" do
      refute FeatureFlags.enabled?(:use_ets_agent_registry)
      refute FeatureFlags.enabled?(:use_logger_error_context)
      refute FeatureFlags.enabled?(:use_genserver_telemetry)
    end

    test "can enable and disable flags" do
      assert :ok = FeatureFlags.enable(:use_ets_agent_registry)
      assert FeatureFlags.enabled?(:use_ets_agent_registry)

      assert :ok = FeatureFlags.disable(:use_ets_agent_registry)
      refute FeatureFlags.enabled?(:use_ets_agent_registry)
    end

    test "can set flags to specific values" do
      assert :ok = FeatureFlags.set(:use_logger_error_context, true)
      assert FeatureFlags.enabled?(:use_logger_error_context)

      assert :ok = FeatureFlags.set(:use_logger_error_context, false)
      refute FeatureFlags.enabled?(:use_logger_error_context)
    end

    test "rejects unknown flags" do
      assert {:error, :unknown_flag} = FeatureFlags.set(:unknown_flag, true)
    end
  end

  describe "percentage rollouts" do
    test "can set percentage rollouts" do
      assert :ok = FeatureFlags.set_percentage(:use_ets_agent_registry, 50)

      # Test with different IDs to verify consistent hashing
      id1_enabled = FeatureFlags.enabled_for_id?(:use_ets_agent_registry, "user1")
      id2_enabled = FeatureFlags.enabled_for_id?(:use_ets_agent_registry, "user2")

      # Should be consistent for the same ID
      assert id1_enabled == FeatureFlags.enabled_for_id?(:use_ets_agent_registry, "user1")
      assert id2_enabled == FeatureFlags.enabled_for_id?(:use_ets_agent_registry, "user2")
    end

    test "percentage 0 means disabled for all" do
      FeatureFlags.set_percentage(:use_ets_agent_registry, 0)

      refute FeatureFlags.enabled_for_id?(:use_ets_agent_registry, "user1")
      refute FeatureFlags.enabled_for_id?(:use_ets_agent_registry, "user2")
    end

    test "percentage 100 means enabled for all" do
      FeatureFlags.set_percentage(:use_ets_agent_registry, 100)

      assert FeatureFlags.enabled_for_id?(:use_ets_agent_registry, "user1")
      assert FeatureFlags.enabled_for_id?(:use_ets_agent_registry, "user2")
    end
  end

  describe "migration stage management" do
    test "can enable migration stages" do
      assert :ok = FeatureFlags.enable_otp_cleanup_stage(1)

      status = FeatureFlags.migration_status()
      assert status.stage == 1
      assert status.flags.use_ets_agent_registry == true
      assert status.flags.enable_migration_monitoring == true
    end

    test "stage 2 enables error context" do
      FeatureFlags.enable_otp_cleanup_stage(1)
      assert :ok = FeatureFlags.enable_otp_cleanup_stage(2)

      status = FeatureFlags.migration_status()
      assert status.stage == 2
      assert status.flags.use_logger_error_context == true
    end

    test "stage 3 enables telemetry flags" do
      FeatureFlags.enable_otp_cleanup_stage(2)
      assert :ok = FeatureFlags.enable_otp_cleanup_stage(3)

      status = FeatureFlags.migration_status()
      assert status.stage == 3
      assert status.flags.use_genserver_telemetry == true
      assert status.flags.use_genserver_span_management == true
      assert status.flags.use_ets_sampled_events == true
    end

    test "stage 4 enables enforcement" do
      FeatureFlags.enable_otp_cleanup_stage(3)
      assert :ok = FeatureFlags.enable_otp_cleanup_stage(4)

      status = FeatureFlags.migration_status()
      assert status.stage == 4
      assert status.flags.enforce_no_process_dict == true
    end
  end

  describe "rollback functionality" do
    test "can rollback to previous stage" do
      # Go to stage 3
      FeatureFlags.enable_otp_cleanup_stage(3)

      # Rollback to stage 1
      assert :ok = FeatureFlags.rollback_migration_stage(1)

      status = FeatureFlags.migration_status()
      assert status.stage == 1
      assert status.flags.use_ets_agent_registry == true
      assert status.flags.use_logger_error_context == false
      assert status.flags.use_genserver_telemetry == false
    end

    test "cannot rollback to current or future stage" do
      FeatureFlags.enable_otp_cleanup_stage(2)

      assert {:error, :invalid_rollback} = FeatureFlags.rollback_migration_stage(2)
      assert {:error, :invalid_rollback} = FeatureFlags.rollback_migration_stage(3)
    end

    test "emergency rollback disables all flags" do
      FeatureFlags.enable_otp_cleanup_stage(3)

      assert :ok = FeatureFlags.emergency_rollback("Test emergency")

      status = FeatureFlags.migration_status()
      assert status.stage == 0

      Enum.each(status.flags, fn {_flag, value} ->
        refute value
      end)
    end
  end

  describe "flag listing and status" do
    test "lists all flags with current values" do
      FeatureFlags.enable(:use_ets_agent_registry)
      FeatureFlags.disable(:use_logger_error_context)

      flags = FeatureFlags.list_all()

      assert flags.use_ets_agent_registry == true
      assert flags.use_logger_error_context == false
      assert is_boolean(flags.use_genserver_telemetry)
    end

    test "migration status includes all relevant information" do
      FeatureFlags.enable_otp_cleanup_stage(2)

      status = FeatureFlags.migration_status()

      assert is_integer(status.stage)
      assert is_integer(status.system_time)
      assert is_map(status.flags)

      # Should have timestamp when migration was performed
      assert is_integer(status.timestamp)
    end
  end

  describe "telemetry events" do
    test "emits telemetry when flags change" do
      # Attach test handler
      test_pid = self()

      handler = fn [:foundation, :feature_flag, :changed], measurements, metadata, _ ->
        send(test_pid, {:telemetry_event, measurements, metadata})
      end

      :telemetry.attach("test-handler", [:foundation, :feature_flag, :changed], handler, nil)

      FeatureFlags.enable(:use_ets_agent_registry)

      assert_receive {:telemetry_event, %{count: 1}, metadata}
      assert metadata.flag == :use_ets_agent_registry
      assert metadata.value == true

      :telemetry.detach("test-handler")
    end

    test "emits telemetry for migration events" do
      test_pid = self()

      handler = fn [:foundation, :migration, :stage_enabled], measurements, metadata, _ ->
        send(test_pid, {:migration_event, measurements, metadata})
      end

      :telemetry.attach(
        "test-migration-handler",
        [:foundation, :migration, :stage_enabled],
        handler,
        nil
      )

      FeatureFlags.enable_otp_cleanup_stage(1)

      assert_receive {:migration_event, %{stage: 1}, _metadata}

      :telemetry.detach("test-migration-handler")
    end
  end

  describe "flag integration with other modules" do
    test "ErrorContext uses feature flag" do
      # When flag is disabled, should use process dictionary
      FeatureFlags.disable(:use_logger_error_context)

      Foundation.ErrorContext.set_context(%{test: "value"})
      assert Foundation.ErrorContext.get_context() == %{test: "value"}

      # When flag is enabled, should use Logger metadata
      FeatureFlags.enable(:use_logger_error_context)

      Foundation.ErrorContext.set_context(%{test: "value2"})
      assert Foundation.ErrorContext.get_context() == %{test: "value2"}

      # Should be stored in Logger metadata
      assert Logger.metadata()[:error_context] == %{test: "value2"}
    end

    test "Registry uses feature flag" do
      # Test with flag disabled (legacy mode)
      FeatureFlags.disable(:use_ets_agent_registry)

      assert :ok = Foundation.Registry.register(nil, :test_agent, self())
      assert {:ok, {pid, _metadata}} = Foundation.Registry.lookup(nil, :test_agent)
      assert pid == self()

      # Test with flag enabled (ETS mode) - requires RegistryETS to be started
      FeatureFlags.enable(:use_ets_agent_registry)

      # Only test if RegistryETS is available
      if Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
        case Foundation.Protocols.RegistryETS.start_link() do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
        end

        assert :ok = Foundation.Registry.register(nil, :test_agent2, self())
        assert {:ok, {pid, _metadata}} = Foundation.Registry.lookup(nil, :test_agent2)
        assert pid == self()
      end
    end
  end

  describe "error conditions" do
    test "handles ETS table not existing gracefully" do
      # Manually delete the ETS table to simulate error condition
      table_name = :foundation_feature_flags
      :ets.delete(table_name)

      # Should recreate table and work normally
      assert :ok = FeatureFlags.enable(:use_ets_agent_registry)
      assert FeatureFlags.enabled?(:use_ets_agent_registry)
    end

    test "validates percentage values" do
      assert_raise FunctionClauseError, fn ->
        FeatureFlags.set_percentage(:use_ets_agent_registry, -1)
      end

      assert_raise FunctionClauseError, fn ->
        FeatureFlags.set_percentage(:use_ets_agent_registry, 101)
      end
    end
  end

  describe "concurrent access" do
    test "handles concurrent flag changes safely" do
      # Start multiple processes changing flags concurrently
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            for j <- 1..10 do
              flag =
                Enum.random([
                  :use_ets_agent_registry,
                  :use_logger_error_context,
                  :use_genserver_telemetry
                ])

              value = rem(i + j, 2) == 0
              FeatureFlags.set(flag, value)
              Process.sleep(1)
            end
          end)
        end

      # Wait for all tasks to complete
      Enum.each(tasks, &Task.await/1)

      # Should still be able to read flags
      flags = FeatureFlags.list_all()
      assert is_map(flags)

      Enum.each(flags, fn {flag, value} ->
        assert is_atom(flag)
        assert is_boolean(value)
      end)
    end
  end
end
