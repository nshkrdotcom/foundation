defmodule Foundation.MigrationControlTest do
  use ExUnit.Case, async: false
  
  alias Foundation.{MigrationControl, FeatureFlags}

  setup do
    # Start FeatureFlags if not already started
    case GenServer.whereis(FeatureFlags) do
      nil -> FeatureFlags.start_link()
      _ -> :ok
    end

    # Reset to clean state
    FeatureFlags.reset_all()
    
    # Clean up migration history
    case :ets.whereis(:migration_history) do
      :undefined -> :ok
      _ -> :ets.delete_all_objects(:migration_history)
    end
    
    :ok
  end

  describe "migration stage information" do
    test "lists all migration stages" do
      stages = MigrationControl.list_stages()
      
      assert map_size(stages) == 4
      assert stages[1].name == "Registry Migration"
      assert stages[2].name == "Error Context Migration"
      assert stages[3].name == "Telemetry Migration"
      assert stages[4].name == "Enforcement"
      
      Enum.each(stages, fn {_stage, info} ->
        assert is_binary(info.name)
        assert is_binary(info.description)
        assert is_list(info.flags)
        assert info.risk_level in [:low, :medium, :high, :critical]
      end)
    end

    test "provides current migration status" do
      # Start with no migration
      status = MigrationControl.status()
      
      assert status.current_stage == 0
      assert is_nil(status.stage_info)
      assert is_map(status.flags)
      assert is_map(status.system_health)
      assert is_list(status.migration_history)
      
      # Migrate to stage 1
      FeatureFlags.enable_otp_cleanup_stage(1)
      
      status = MigrationControl.status()
      assert status.current_stage == 1
      assert status.stage_info.name == "Registry Migration"
      assert status.next_stage_info.name == "Error Context Migration"
    end
  end

  describe "migration execution" do
    test "can migrate to next stage" do
      # Migrate to stage 1
      assert {:ok, result} = MigrationControl.migrate_to_stage(1)
      assert result.stage == 1
      assert result.info.name == "Registry Migration"
      
      status = FeatureFlags.migration_status()
      assert status.stage == 1
      assert status.flags.use_ets_agent_registry == true
    end

    test "cannot skip stages" do
      assert {:error, msg} = MigrationControl.migrate_to_stage(3)
      assert msg =~ "Cannot skip stages"
    end

    test "cannot migrate backwards" do
      FeatureFlags.enable_otp_cleanup_stage(2)
      
      assert {:error, msg} = MigrationControl.migrate_to_stage(1)
      assert msg =~ "Cannot migrate backwards"
    end

    test "sequential migration through all stages" do
      # Stage 1
      assert {:ok, _} = MigrationControl.migrate_to_stage(1)
      status = FeatureFlags.migration_status()
      assert status.stage == 1
      
      # Stage 2
      assert {:ok, _} = MigrationControl.migrate_to_stage(2)
      status = FeatureFlags.migration_status()
      assert status.stage == 2
      
      # Stage 3
      assert {:ok, _} = MigrationControl.migrate_to_stage(3)
      status = FeatureFlags.migration_status()
      assert status.stage == 3
      
      # Stage 4
      assert {:ok, _} = MigrationControl.migrate_to_stage(4)
      status = FeatureFlags.migration_status()
      assert status.stage == 4
    end
  end

  describe "rollback functionality" do
    test "can rollback to previous stage" do
      # Go to stage 3
      FeatureFlags.enable_otp_cleanup_stage(3)
      
      # Rollback to stage 1
      assert :ok = MigrationControl.rollback_to_stage(1)
      
      status = FeatureFlags.migration_status()
      assert status.stage == 1
    end

    test "cannot rollback to current or future stage" do
      FeatureFlags.enable_otp_cleanup_stage(2)
      
      assert {:error, msg} = MigrationControl.rollback_to_stage(2)
      assert msg =~ "Cannot rollback to current or future stage"
      
      assert {:error, msg} = MigrationControl.rollback_to_stage(3)
      assert msg =~ "Cannot rollback to current or future stage"
    end

    test "emergency rollback works from any stage" do
      FeatureFlags.enable_otp_cleanup_stage(3)
      
      assert :ok = MigrationControl.emergency_rollback("Test emergency")
      
      status = FeatureFlags.migration_status()
      assert status.stage == 0
      
      # All flags should be disabled
      Enum.each(status.flags, fn {_flag, value} ->
        refute value
      end)
    end
  end

  describe "readiness validation" do
    test "validates readiness for stage 1" do
      # Should be ready from stage 0
      assert :ok = MigrationControl.validate_readiness_for_stage(1)
    end

    test "validates readiness for stage 2" do
      # Should not be ready without stage 1
      assert {:error, failed_validations} = MigrationControl.validate_readiness_for_stage(2)
      assert Enum.any?(failed_validations, fn {name, _} -> name == :current_stage end)
      
      # Should be ready after stage 1
      FeatureFlags.enable_otp_cleanup_stage(1)
      assert :ok = MigrationControl.validate_readiness_for_stage(2)
    end
  end

  describe "health monitoring" do
    test "provides system health metrics" do
      status = MigrationControl.status()
      health = status.system_health
      
      assert is_number(health.error_rate)
      assert is_number(health.restart_frequency)
      assert is_number(health.response_time)
      assert is_integer(health.memory_usage)
      assert is_integer(health.process_count)
      assert is_integer(health.ets_usage)
    end

    test "health check with good health returns ok" do
      assert {:ok, _health} = MigrationControl.check_health_and_rollback()
    end

    test "can start health monitoring when enabled" do
      FeatureFlags.enable(:enable_migration_monitoring)
      
      assert {:ok, _pid} = MigrationControl.start_health_monitoring(100)
    end

    test "health monitoring disabled when flag is off" do
      FeatureFlags.disable(:enable_migration_monitoring)
      
      assert {:error, :monitoring_disabled} = MigrationControl.start_health_monitoring(100)
    end
  end

  describe "metrics collection" do
    test "provides migration metrics" do
      metrics = MigrationControl.metrics()
      
      assert is_map(metrics.flag_usage)
      assert is_map(metrics.performance_impact)
      assert is_map(metrics.error_rates)
      assert is_map(metrics.rollback_frequency)
    end
  end

  describe "migration history tracking" do
    test "records migration events" do
      # Perform migration
      MigrationControl.migrate_to_stage(1)
      
      status = MigrationControl.status()
      history = status.migration_history
      
      assert length(history) > 0
      
      # Should have migration_start and migration_complete events
      event_types = Enum.map(history, & &1.type)
      assert :migration_start in event_types
      assert :migration_complete in event_types
    end

    test "records rollback events" do
      # Migrate and rollback
      FeatureFlags.enable_otp_cleanup_stage(2)
      MigrationControl.rollback_to_stage(1)
      
      status = MigrationControl.status()
      history = status.migration_history
      
      rollback_events = Enum.filter(history, & &1.type == :rollback)
      assert length(rollback_events) > 0
      
      rollback_event = hd(rollback_events)
      assert rollback_event.from_stage == 2
      assert rollback_event.to_stage == 1
    end

    test "records emergency rollback events" do
      FeatureFlags.enable_otp_cleanup_stage(2)
      MigrationControl.emergency_rollback("Test emergency")
      
      status = MigrationControl.status()
      history = status.migration_history
      
      emergency_events = Enum.filter(history, & &1.type == :emergency_rollback)
      assert length(emergency_events) > 0
      
      emergency_event = hd(emergency_events)
      assert emergency_event.description =~ "Test emergency"
    end
  end

  describe "telemetry events" do
    test "emits telemetry for migration events" do
      test_pid = self()
      
      handler = fn [:foundation, :migration, :stage_enabled], measurements, metadata, _ ->
        send(test_pid, {:migration_telemetry, measurements, metadata})
      end
      
      :telemetry.attach("test-migration-handler", [:foundation, :migration, :stage_enabled], handler, nil)
      
      MigrationControl.migrate_to_stage(1)
      
      assert_receive {:migration_telemetry, measurements, _metadata}
      assert measurements.stage == 1
      
      :telemetry.detach("test-migration-handler")
    end

    test "emits telemetry for rollback events" do
      test_pid = self()
      
      handler = fn [:foundation, :migration, :rollback], measurements, metadata, _ ->
        send(test_pid, {:rollback_telemetry, measurements, metadata})
      end
      
      :telemetry.attach("test-rollback-handler", [:foundation, :migration, :rollback], handler, nil)
      
      FeatureFlags.enable_otp_cleanup_stage(2)
      MigrationControl.rollback_to_stage(1)
      
      assert_receive {:rollback_telemetry, measurements, _metadata}
      assert measurements.from_stage == 2
      assert measurements.to_stage == 1
      
      :telemetry.detach("test-rollback-handler")
    end

    test "emits telemetry for emergency rollback" do
      test_pid = self()
      
      handler = fn [:foundation, :migration, :emergency_rollback], measurements, metadata, _ ->
        send(test_pid, {:emergency_telemetry, measurements, metadata})
      end
      
      :telemetry.attach("test-emergency-handler", [:foundation, :migration, :emergency_rollback], handler, nil)
      
      FeatureFlags.enable_otp_cleanup_stage(2)
      MigrationControl.emergency_rollback("Test emergency")
      
      assert_receive {:emergency_telemetry, %{count: 1}, metadata}
      assert metadata.reason == "Test emergency"
      
      :telemetry.detach("test-emergency-handler")
    end

    test "emits telemetry for alert events" do
      test_pid = self()
      
      handler = fn [:foundation, :migration, :alert], measurements, metadata, _ ->
        send(test_pid, {:alert_telemetry, measurements, metadata})
      end
      
      :telemetry.attach("test-alert-handler", [:foundation, :migration, :alert], handler, nil)
      
      # Emergency rollback should trigger alert
      FeatureFlags.enable_otp_cleanup_stage(1)
      MigrationControl.emergency_rollback("Test alert")
      
      assert_receive {:alert_telemetry, %{count: 1}, metadata}
      assert metadata.alert_type == :emergency_rollback
      
      :telemetry.detach("test-alert-handler")
    end
  end

  describe "error conditions" do
    test "handles ETS table creation for history tracking" do
      # Should work even if migration_history table doesn't exist
      status = MigrationControl.status()
      assert is_list(status.migration_history)
      
      # Perform migration to create events
      MigrationControl.migrate_to_stage(1)
      
      status = MigrationControl.status()
      assert length(status.migration_history) > 0
    end
  end

  describe "integration with feature flags" do
    test "migration control affects feature flag state" do
      refute FeatureFlags.enabled?(:use_ets_agent_registry)
      
      MigrationControl.migrate_to_stage(1)
      
      assert FeatureFlags.enabled?(:use_ets_agent_registry)
      assert FeatureFlags.enabled?(:enable_migration_monitoring)
    end

    test "feature flag operations are reflected in migration status" do
      FeatureFlags.enable_otp_cleanup_stage(2)
      
      status = MigrationControl.status()
      assert status.current_stage == 2
      assert status.flags.use_logger_error_context == true
    end
  end
end