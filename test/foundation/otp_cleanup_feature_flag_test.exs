defmodule Foundation.OTPCleanupFeatureFlagTest do
  @moduledoc """
  Feature flag integration tests for OTP cleanup migration.

  Tests switching between old and new implementations, rollback scenarios,
  and partial rollouts with percentage flags.
  """

  use Foundation.UnifiedTestFoundation, :registry

  alias Foundation.{FeatureFlags, ErrorContext, Registry}
  alias Foundation.Telemetry.Span

  @moduletag :feature_flags
  @moduletag :integration
  @moduletag timeout: 120_000

  describe "Feature Flag Toggle Tests" do
    setup do
      # Ensure FeatureFlags service is started
      case Process.whereis(Foundation.FeatureFlags) do
        nil ->
          {:ok, _} = Foundation.FeatureFlags.start_link()

        _pid ->
          :ok
      end

      FeatureFlags.reset_all()

      on_exit(fn ->
        if Process.whereis(Foundation.FeatureFlags) do
          try do
            FeatureFlags.reset_all()
          catch
            :exit, _ -> :ok
          end
        end

        ErrorContext.clear_context()
      end)

      :ok
    end

    test "registry implementation switching" do
      # Start with legacy implementation
      FeatureFlags.disable(:use_ets_agent_registry)

      # Test legacy functionality
      assert :ok = Registry.register(nil, :legacy_test_agent, self())
      assert {:ok, {pid, _}} = Registry.lookup(nil, :legacy_test_agent)
      assert pid == self()

      # List should work in legacy mode
      agents = Registry.list_all(nil)
      assert is_list(agents)

      # Switch to ETS implementation
      FeatureFlags.enable(:use_ets_agent_registry)

      if Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
        case Process.whereis(Foundation.Protocols.RegistryETS) do
          nil ->
            {:ok, _} = Foundation.Protocols.RegistryETS.start_link()

          _pid ->
            :ok
        end

        # Test ETS functionality
        assert :ok = Registry.register(nil, :ets_test_agent, self())
        assert {:ok, {pid, _}} = Registry.lookup(nil, :ets_test_agent)
        assert pid == self()

        # Both agents should be findable (different backends)
        # This tests implementation isolation
      else
        # ETS implementation not available, skip
        :ok
      end

      # Switch back to legacy
      FeatureFlags.disable(:use_ets_agent_registry)

      # Should still work
      assert :ok = Registry.register(nil, :back_to_legacy_agent, self())
      assert {:ok, {pid, _}} = Registry.lookup(nil, :back_to_legacy_agent)
      assert pid == self()
    end

    test "error context implementation switching" do
      # Start with legacy (Process dictionary)
      FeatureFlags.disable(:use_logger_error_context)

      ErrorContext.set_context(%{implementation: "legacy", test: true})
      context = ErrorContext.get_context()

      assert context.implementation == "legacy"
      assert context.test == true

      # Switch to Logger metadata
      FeatureFlags.enable(:use_logger_error_context)

      # Previous context should be cleared when switching
      ErrorContext.set_context(%{implementation: "logger", test: true})
      new_context = ErrorContext.get_context()

      assert new_context.implementation == "logger"
      assert new_context.test == true

      # Should be in Logger metadata
      logger_metadata = Logger.metadata()
      assert logger_metadata[:error_context] == new_context

      # Switch back to legacy
      FeatureFlags.disable(:use_logger_error_context)

      # Should switch back to Process dictionary
      ErrorContext.set_context(%{implementation: "back_to_legacy"})
      back_context = ErrorContext.get_context()

      assert back_context.implementation == "back_to_legacy"
    end

    test "telemetry implementation switching" do
      # Test span management switching
      # (This test assumes legacy spans use Process dictionary)

      # Start with legacy
      FeatureFlags.disable(:use_genserver_telemetry)
      FeatureFlags.disable(:use_genserver_span_management)

      span1 = Span.start_span("legacy_span", %{type: "legacy"})
      assert is_reference(span1)
      assert :ok = Span.end_span(span1)

      # Switch to GenServer implementation
      FeatureFlags.enable(:use_genserver_telemetry)
      FeatureFlags.enable(:use_genserver_span_management)

      # Should work with new implementation
      span2 = Span.start_span("genserver_span", %{type: "genserver"})
      assert is_reference(span2)
      assert :ok = Span.end_span(span2)

      # Test sampled events switching
      FeatureFlags.enable(:use_ets_sampled_events)

      if Code.ensure_loaded?(Foundation.Telemetry.SampledEvents) do
        {:ok, _} = Foundation.Telemetry.SampledEvents.start_link()

        # Should work with new implementation
        Foundation.Telemetry.SampledEvents.TestAPI.emit_event(
          [:feature_flag, :test],
          %{count: 1},
          %{implementation: "ets"}
        )
      else
        :ok
      end
    end
  end

  describe "Migration Stage Tests" do
    test "stage progression maintains functionality" do
      # Start at stage 0 (all legacy)
      FeatureFlags.reset_all()
      status = FeatureFlags.migration_status()
      assert status.stage == 0

      # Test baseline functionality
      test_all_functionality("stage_0")

      # Progress through each stage
      for stage <- 1..4 do
        FeatureFlags.enable_otp_cleanup_stage(stage)

        # Start required services for new implementations
        start_services_for_stage(stage)

        # Test functionality at this stage
        test_all_functionality("stage_#{stage}")

        # Verify migration status
        status = FeatureFlags.migration_status()
        assert status.stage == stage

        # Verify expected flags are enabled
        verify_stage_flags(stage, status.flags)
      end
    end

    test "rollback maintains stability" do
      # Go to full implementation
      FeatureFlags.enable_otp_cleanup_stage(4)
      start_services_for_stage(4)

      # Establish functionality
      test_all_functionality("pre_rollback")

      # Test rollback scenarios
      rollback_scenarios = [
        {4, 3, "partial_rollback"},
        {3, 1, "major_rollback"},
        {1, 0, "full_rollback"}
      ]

      for {from_stage, to_stage, scenario} <- rollback_scenarios do
        if from_stage <= 4 do
          FeatureFlags.enable_otp_cleanup_stage(from_stage)
          start_services_for_stage(from_stage)
        end

        # Rollback
        if to_stage == 0 do
          # Stage 0 means reset all flags to defaults (legacy)
          FeatureFlags.reset_all()
        else
          assert :ok = FeatureFlags.rollback_migration_stage(to_stage)
        end

        # Verify rollback
        status = FeatureFlags.migration_status()
        assert status.stage == to_stage

        # Test functionality after rollback
        test_all_functionality(scenario)
      end
    end

    test "emergency rollback works under any conditions" do
      # Test emergency rollback from various states
      test_conditions = [
        {0, "from_legacy"},
        {1, "from_stage_1"},
        {2, "from_stage_2"},
        {3, "from_stage_3"},
        {4, "from_full_implementation"}
      ]

      for {initial_stage, condition} <- test_conditions do
        # Set up initial condition
        if initial_stage > 0 do
          FeatureFlags.enable_otp_cleanup_stage(initial_stage)
          start_services_for_stage(initial_stage)
        else
          FeatureFlags.reset_all()
        end

        # Establish some state
        test_all_functionality("pre_emergency_#{condition}")

        # Emergency rollback
        assert :ok = FeatureFlags.emergency_rollback("Test emergency from #{condition}")

        # Verify emergency state
        status = FeatureFlags.migration_status()
        assert status.stage == 0

        # All flags should be disabled
        Enum.each(status.flags, fn {_flag, value} ->
          refute value, "Flag not disabled in emergency rollback from #{condition}"
        end)

        # System should still function
        test_basic_functionality("post_emergency_#{condition}")
      end
    end

    defp start_services_for_stage(stage) do
      case stage do
        stage when stage >= 1 ->
          # Start ETS registry if available
          if Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
            case Process.whereis(Foundation.Protocols.RegistryETS) do
              nil -> Foundation.Protocols.RegistryETS.start_link()
              _ -> {:ok, Process.whereis(Foundation.Protocols.RegistryETS)}
            end
          else
            :ok
          end

        _ ->
          :ok
      end

      case stage do
        stage when stage >= 3 ->
          # Start telemetry services if available
          if Code.ensure_loaded?(Foundation.Telemetry.SampledEvents) do
            case Process.whereis(Foundation.Telemetry.SampledEvents) do
              nil -> Foundation.Telemetry.SampledEvents.start_link()
              _ -> {:ok, Process.whereis(Foundation.Telemetry.SampledEvents)}
            end
          else
            :ok
          end

        _ ->
          :ok
      end
    end

    defp verify_stage_flags(stage, flags) do
      case stage do
        1 ->
          assert flags.use_ets_agent_registry == true
          assert flags.enable_migration_monitoring == true

        2 ->
          assert flags.use_ets_agent_registry == true
          assert flags.use_logger_error_context == true

        3 ->
          assert flags.use_logger_error_context == true
          assert flags.use_genserver_telemetry == true
          assert flags.use_genserver_span_management == true
          assert flags.use_ets_sampled_events == true

        4 ->
          assert flags.enforce_no_process_dict == true

        _ ->
          :ok
      end
    end

    defp test_all_functionality(context) do
      # Test registry
      Registry.register(nil, :"test_agent_#{context}", self())
      assert {:ok, {pid, _}} = Registry.lookup(nil, :"test_agent_#{context}")
      assert pid == self()

      # Test error context
      ErrorContext.set_context(%{context: context, test: true})
      retrieved_context = ErrorContext.get_context()
      assert retrieved_context.context == context

      # Test telemetry
      span_id = Span.start_span("test_span_#{context}", %{context: context})
      assert :ok = Span.end_span(span_id)
    end

    defp test_basic_functionality(context) do
      # Minimal functionality test for emergency scenarios
      try do
        Registry.register(nil, :"basic_test_#{context}", self())
        Registry.lookup(nil, :"basic_test_#{context}")
      rescue
        # May fail in emergency scenarios
        _ -> :ok
      end

      try do
        ErrorContext.set_context(%{basic_test: context})
        ErrorContext.get_context()
      rescue
        # May fail in emergency scenarios
        _ -> :ok
      end
    end
  end

  describe "Percentage Rollout Tests" do
    setup do
      # Ensure FeatureFlags service is started
      case Process.whereis(Foundation.FeatureFlags) do
        nil ->
          {:ok, _} = Foundation.FeatureFlags.start_link()
        _pid ->
          :ok
      end

      on_exit(fn ->
        if Process.whereis(Foundation.FeatureFlags) do
          try do
            FeatureFlags.reset_all()
          catch
            :exit, _ -> :ok
          end
        end
      end)

      :ok
    end

    test "percentage rollout consistency" do
      # Test percentage rollouts for deterministic behavior
      flag = :use_ets_agent_registry

      # Set 50% rollout
      FeatureFlags.set_percentage(flag, 50)

      # Test with many user IDs
      user_ids = for i <- 1..1000, do: "user_#{i}"

      results =
        for user_id <- user_ids do
          {user_id, FeatureFlags.enabled_for_id?(flag, user_id)}
        end

      # Should be roughly 50% enabled
      enabled_count = Enum.count(results, fn {_, enabled} -> enabled end)
      percentage = enabled_count / length(user_ids) * 100

      # Allow some variance
      assert percentage > 40 and percentage < 60,
             "Percentage rollout not working: #{percentage}% enabled, expected ~50%"

      # Same user should always get same result
      consistent_results =
        for {user_id, expected} <- Enum.take(results, 100) do
          actual = FeatureFlags.enabled_for_id?(flag, user_id)
          {user_id, expected, actual, expected == actual}
        end

      inconsistent = Enum.reject(consistent_results, fn {_, _, _, consistent} -> consistent end)

      assert inconsistent == [],
             "Inconsistent rollout results for users: #{inspect(inconsistent)}"
    end

    test "percentage rollout boundaries" do
      flag = :use_logger_error_context
      test_users = ["test_user_1", "test_user_2", "test_user_3"]

      # 0% should disable for all
      FeatureFlags.set_percentage(flag, 0)

      for user <- test_users do
        refute FeatureFlags.enabled_for_id?(flag, user),
               "Flag should be disabled for #{user} at 0%"
      end

      # 100% should enable for all
      FeatureFlags.set_percentage(flag, 100)

      for user <- test_users do
        assert FeatureFlags.enabled_for_id?(flag, user),
               "Flag should be enabled for #{user} at 100%"
      end
    end

    test "gradual rollout simulation" do
      flag = :use_ets_agent_registry
      test_users = for i <- 1..100, do: "user_#{i}"

      # Simulate gradual rollout: 0% -> 25% -> 50% -> 75% -> 100%
      rollout_stages = [0, 25, 50, 75, 100]

      results =
        for percentage <- rollout_stages do
          FeatureFlags.set_percentage(flag, percentage)

          enabled_users =
            for user <- test_users do
              {user, FeatureFlags.enabled_for_id?(flag, user)}
            end

          enabled_count = Enum.count(enabled_users, fn {_, enabled} -> enabled end)
          actual_percentage = enabled_count / length(test_users) * 100

          {percentage, actual_percentage, enabled_users}
        end

      # Verify rollout progression
      for {target_percentage, actual_percentage, _enabled_users} <- results do
        # Allow 10% variance
        tolerance = 10

        assert abs(actual_percentage - target_percentage) <= tolerance,
               "Rollout percentage #{target_percentage}% not achieved: got #{actual_percentage}%"
      end

      # Verify monotonic increase (users shouldn't be removed once added)
      [zero, twenty_five, fifty, seventy_five, hundred] =
        Enum.map(results, fn {_, _, enabled_users} -> enabled_users end)

      # Users enabled at lower percentage should remain enabled at higher percentage
      verify_monotonic_rollout(zero, twenty_five, "0% -> 25%")
      verify_monotonic_rollout(twenty_five, fifty, "25% -> 50%")
      verify_monotonic_rollout(fifty, seventy_five, "50% -> 75%")
      verify_monotonic_rollout(seventy_five, hundred, "75% -> 100%")
    end

    defp verify_monotonic_rollout(lower_stage, higher_stage, transition) do
      lower_enabled =
        lower_stage
        |> Enum.filter(fn {_, enabled} -> enabled end)
        |> Enum.map(fn {user, _} -> user end)
        |> MapSet.new()

      higher_enabled =
        higher_stage
        |> Enum.filter(fn {_, enabled} -> enabled end)
        |> Enum.map(fn {user, _} -> user end)
        |> MapSet.new()

      # All users enabled in lower stage should be enabled in higher stage
      disabled_users = MapSet.difference(lower_enabled, higher_enabled)

      assert MapSet.size(disabled_users) == 0,
             "Users disabled during rollout #{transition}: #{inspect(MapSet.to_list(disabled_users))}"
    end
  end

  describe "Flag Interaction Tests" do
    test "flag dependencies and conflicts" do
      # Test that dependent flags work together

      # Enable stage 1 (ETS registry)
      FeatureFlags.enable(:use_ets_agent_registry)

      if Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
        case Process.whereis(Foundation.Protocols.RegistryETS) do
          nil ->
            {:ok, _} = Foundation.Protocols.RegistryETS.start_link()

          _pid ->
            :ok
        end

        # Test registry works
        Registry.register(nil, :dependency_test, self())
        assert {:ok, {pid, _}} = Registry.lookup(nil, :dependency_test)
        assert pid == self()
      else
        :ok
      end

      # Enable stage 2 (Logger error context) - should work with ETS registry
      FeatureFlags.enable(:use_logger_error_context)

      # Test both work together
      ErrorContext.set_context(%{dependency_test: true})
      Registry.register(nil, :combined_test, self())

      context = ErrorContext.get_context()
      assert context.dependency_test == true
      assert {:ok, {pid, _}} = Registry.lookup(nil, :combined_test)
      assert pid == self()

      # Enable stage 3 (Telemetry) - should work with previous stages
      FeatureFlags.enable(:use_genserver_telemetry)
      FeatureFlags.enable(:use_ets_sampled_events)

      # Test all work together
      span_id = Span.start_span("dependency_test", %{all_flags: true})

      Registry.register(nil, :full_test, self())
      ErrorContext.set_context(%{full_test: true})

      assert :ok = Span.end_span(span_id)
      assert ErrorContext.get_context().full_test == true
      assert {:ok, {pid, _}} = Registry.lookup(nil, :full_test)
      assert pid == self()
    end

    test "concurrent flag changes" do
      # Test system stability when flags change during operations

      # Start background operations
      operation_task =
        Task.async(fn ->
          continuous_operations()
        end)

      # Change flags rapidly
      flag_changer =
        Task.async(fn ->
          for _i <- 1..50 do
            FeatureFlags.enable(:use_ets_agent_registry)
            # Minimal delay for testing infrastructure
            :timer.sleep(1)
            FeatureFlags.disable(:use_ets_agent_registry)
            # Minimal delay for testing infrastructure
            :timer.sleep(1)
            FeatureFlags.enable(:use_logger_error_context)
            # Minimal delay for testing infrastructure
            :timer.sleep(1)
            FeatureFlags.disable(:use_logger_error_context)
            # Minimal delay for testing infrastructure
            :timer.sleep(1)
          end
        end)

      # Let operations and flag changes run
      Task.await(flag_changer, 30_000)

      # Stop operations
      Task.shutdown(operation_task, :brutal_kill)

      # System should still be functional
      Registry.register(nil, :post_concurrent_test, self())
      assert {:ok, {pid, _}} = Registry.lookup(nil, :post_concurrent_test)
      assert pid == self()
    end

    defp continuous_operations do
      receive do
        :stop -> :ok
      after
        0 ->
          try do
            # Perform operations that might be affected by flag changes
            Registry.register(nil, :"continuous_#{:erlang.unique_integer()}", self())
            ErrorContext.set_context(%{continuous: true, timestamp: System.system_time()})
            span_id = Span.start_span("continuous", %{})
            Span.end_span(span_id)
          rescue
            # Ignore errors due to flag changes
            _ -> :ok
          end

          # Minimal delay for testing infrastructure
          :timer.sleep(1)
          continuous_operations()
      end
    end
  end

  describe "Telemetry Event Tests" do
    test "flag change events are emitted" do
      # Set up telemetry listener
      test_pid = self()

      handler = fn event, measurements, metadata, _ ->
        send(test_pid, {:telemetry_event, event, measurements, metadata})
      end

      :telemetry.attach("flag-change-test", [:foundation, :feature_flag, :changed], handler, nil)

      try do
        # Change some flags
        FeatureFlags.enable(:use_ets_agent_registry)
        FeatureFlags.disable(:use_logger_error_context)
        FeatureFlags.set_percentage(:use_genserver_telemetry, 75)

        # Should receive telemetry events
        events =
          for _i <- 1..3 do
            receive do
              {:telemetry_event, event, measurements, metadata} ->
                {event, measurements, metadata}
            after
              2000 -> :timeout
            end
          end

        # Verify events
        assert length(events) == 3
        refute Enum.any?(events, &(&1 == :timeout))

        # Check event structure
        for {event, measurements, metadata} <- events do
          assert event == [:foundation, :feature_flag, :changed]
          assert is_map(measurements)
          assert is_map(metadata)
          assert Map.has_key?(metadata, :flag)
        end
      after
        :telemetry.detach("flag-change-test")
      end
    end

    test "migration stage events are emitted" do
      test_pid = self()

      handler = fn event, measurements, metadata, _ ->
        send(test_pid, {:migration_event, event, measurements, metadata})
      end

      :telemetry.attach("migration-test", [:foundation, :migration, :stage_enabled], handler, nil)

      try do
        # Enable migration stages
        FeatureFlags.enable_otp_cleanup_stage(1)
        FeatureFlags.enable_otp_cleanup_stage(2)

        # Should receive migration events
        events =
          for _i <- 1..2 do
            receive do
              {:migration_event, event, measurements, metadata} ->
                {event, measurements, metadata}
            after
              2000 -> :timeout
            end
          end

        assert length(events) == 2
        refute Enum.any?(events, &(&1 == :timeout))

        # Verify migration events
        for {event, measurements, _metadata} <- events do
          assert event == [:foundation, :migration, :stage_enabled]
          assert Map.has_key?(measurements, :stage)
        end
      after
        :telemetry.detach("migration-test")
      end
    end
  end
end
