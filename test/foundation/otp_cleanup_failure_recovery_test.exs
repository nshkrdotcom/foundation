defmodule Foundation.OTPCleanupFailureRecoveryTest do
  @moduledoc """
  Failure and recovery tests for OTP cleanup migration.

  Tests behavior when ETS tables are deleted, GenServers crash,
  processes die, and various failure scenarios to ensure robust recovery.
  """

  use ExUnit.Case, async: false

  import Foundation.AsyncTestHelpers
  alias Foundation.{FeatureFlags, ErrorContext, Registry}
  alias Foundation.Telemetry.{Span, SampledEvents}

  @moduletag :failure_recovery
  @moduletag :resilience
  # 3 minutes for failure recovery tests
  @moduletag timeout: 180_000

  describe "ETS Table Failure Recovery" do
    setup do
      FeatureFlags.reset_all()

      on_exit(fn ->
        FeatureFlags.reset_all()
        ErrorContext.clear_context()
      end)

      :ok
    end

    test "registry recovers from ETS table deletion" do
      FeatureFlags.enable(:use_ets_agent_registry)

      case Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
        {:module, _} ->
          {:ok, _registry_pid} = Foundation.Protocols.RegistryETS.start_link()

          # Register some agents
          agents =
            for i <- 1..10 do
              agent_id = :"ets_failure_test_#{i}"
              Registry.register(nil, agent_id, self())

              # Verify registration
              assert {:ok, {pid, _}} = Registry.lookup(nil, agent_id)
              assert pid == self()

              agent_id
            end

          # Manually delete the ETS table to simulate failure
          table_name = :foundation_agent_registry
          :ets.delete(table_name)

          # Registry operations should recreate table and continue working
          new_agent_id = :post_deletion_agent

          # This should recreate the table
          assert :ok = Registry.register(nil, new_agent_id, self())
          assert {:ok, {pid, _}} = Registry.lookup(nil, new_agent_id)
          assert pid == self()

          # Old agents should be gone (table was deleted)
          for agent_id <- agents do
            assert {:error, :not_found} = Registry.lookup(nil, agent_id)
          end

          # New registrations should work normally
          for i <- 1..5 do
            agent_id = :"post_recovery_#{i}"
            assert :ok = Registry.register(nil, agent_id, self())
            assert {:ok, {pid, _}} = Registry.lookup(nil, agent_id)
            assert pid == self()
          end

        {:error, :nofile} ->
          :ok
      end
    end

    test "feature flags ETS recovery" do
      # Feature flags also use ETS
      FeatureFlags.enable(:use_ets_agent_registry)
      FeatureFlags.enable(:use_logger_error_context)

      # Verify flags are set
      assert FeatureFlags.enabled?(:use_ets_agent_registry)
      assert FeatureFlags.enabled?(:use_logger_error_context)

      # Delete feature flags ETS table
      table_name = :foundation_feature_flags
      :ets.delete(table_name)

      # Feature flags should recreate table and work
      # (may default to false until re-enabled)
      FeatureFlags.enable(:use_genserver_telemetry)
      assert FeatureFlags.enabled?(:use_genserver_telemetry)

      # Should be able to use all flag operations
      flags = FeatureFlags.list_all()
      assert is_map(flags)

      FeatureFlags.set_percentage(:use_ets_agent_registry, 50)
      assert FeatureFlags.enabled_for_id?(:use_ets_agent_registry, "test_user_1") in [true, false]
    end

    test "multiple ETS table failures" do
      FeatureFlags.enable_otp_cleanup_stage(4)

      # Start services that use ETS
      services_started = []

      services_started =
        case Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
          {:module, _} ->
            {:ok, _} = Foundation.Protocols.RegistryETS.start_link()
            [:registry_ets | services_started]

          {:error, :nofile} ->
            services_started
        end

      services_started =
        case Code.ensure_loaded?(Foundation.Telemetry.SampledEvents) do
          {:module, _} ->
            {:ok, _} = Foundation.Telemetry.SampledEvents.start_link()
            [:sampled_events | services_started]

          {:error, :nofile} ->
            services_started
        end

      # Establish functionality
      if :registry_ets in services_started do
        Registry.register(nil, :before_failure, self())
      end

      ErrorContext.set_context(%{before_failure: true})
      span_id = Span.start_span("before_failure", %{})
      Span.end_span(span_id)

      # Delete all ETS tables we can find
      ets_tables = :ets.all()

      foundation_tables =
        Enum.filter(ets_tables, fn table ->
          case :ets.info(table, :name) do
            name when is_atom(name) ->
              name_str = Atom.to_string(name)

              String.contains?(name_str, "foundation") or
                String.contains?(name_str, "sampled") or
                String.contains?(name_str, "feature")

            _ ->
              false
          end
        end)

      for table <- foundation_tables do
        try do
          :ets.delete(table)
        rescue
          # May fail if protected
          _ -> :ok
        end
      end

      # System should recover and recreate tables as needed
      wait_until(
        fn ->
          try do
            # Test basic functionality
            ErrorContext.set_context(%{recovery_test: true})
            ErrorContext.get_context().recovery_test == true
          rescue
            _ -> false
          end
        end,
        5000
      )

      # Test functionality after recovery
      if :registry_ets in services_started do
        Registry.register(nil, :after_recovery, self())
        assert {:ok, {pid, _}} = Registry.lookup(nil, :after_recovery)
        assert pid == self()
      end

      ErrorContext.set_context(%{after_recovery: true})
      assert ErrorContext.get_context().after_recovery == true

      recovery_span = Span.start_span("recovery_test", %{})
      assert :ok = Span.end_span(recovery_span)
    end
  end

  describe "GenServer Crash Recovery" do
    test "telemetry GenServer recovery" do
      FeatureFlags.enable(:use_genserver_telemetry)
      FeatureFlags.enable(:use_genserver_span_management)

      case Code.ensure_loaded?(Foundation.Telemetry.SpanManager) do
        {:module, _} ->
          {:ok, span_manager_pid} = Foundation.Telemetry.SpanManager.start_link()

          # Test functionality before crash
          span1 = Span.start_span("before_crash", %{test: true})
          assert :ok = Span.end_span(span1)

          # Kill the GenServer
          Process.exit(span_manager_pid, :kill)

          # Wait a moment for crash
          Process.sleep(100)

          # System should handle the crash gracefully
          # (May use fallback implementation or restart)
          span2 = Span.start_span("after_crash", %{test: true})
          assert :ok = Span.end_span(span2)

        {:error, :nofile} ->
          :ok
      end
    end

    test "sampled events GenServer recovery" do
      FeatureFlags.enable(:use_ets_sampled_events)

      case Code.ensure_loaded?(Foundation.Telemetry.SampledEvents) do
        {:module, _} ->
          {:ok, sampled_events_pid} = Foundation.Telemetry.SampledEvents.start_link()

          # Test functionality before crash
          SampledEvents.emit_event(
            [:test, :before_crash],
            %{count: 1},
            %{test: true}
          )

          # Kill the GenServer
          Process.exit(sampled_events_pid, :kill)

          # Wait for crash
          Process.sleep(100)

          # Should handle gracefully (may lose events but not crash system)
          try do
            SampledEvents.emit_event(
              [:test, :after_crash],
              %{count: 1},
              %{test: true}
            )
          rescue
            # Expected if service is down
            _ -> :ok
          end

          # Should be able to restart service
          {:ok, _new_pid} = Foundation.Telemetry.SampledEvents.start_link()

          SampledEvents.emit_event(
            [:test, :after_restart],
            %{count: 1},
            %{test: true}
          )

        {:error, :nofile} ->
          :ok
      end
    end

    test "registry GenServer recovery under load" do
      FeatureFlags.enable(:use_ets_agent_registry)

      case Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
        {:module, _} ->
          {:ok, registry_pid} = Foundation.Protocols.RegistryETS.start_link()

          # Create background load
          load_task =
            Task.async(fn ->
              for i <- 1..1000 do
                try do
                  agent_id = :"load_test_#{i}"
                  Registry.register(nil, agent_id, self())
                  Registry.lookup(nil, agent_id)

                  if rem(i, 100) == 0 do
                    Process.sleep(10)
                  end
                rescue
                  # May fail during crash
                  _ -> :ok
                end
              end
            end)

          # Kill registry during load
          Process.sleep(50)
          Process.exit(registry_pid, :kill)

          # Wait for load task to complete
          Task.await(load_task, 30_000)

          # Registry should still be functional
          Registry.register(nil, :post_crash_load, self())
          assert {:ok, {pid, _}} = Registry.lookup(nil, :post_crash_load)
          assert pid == self()

        {:error, :nofile} ->
          :ok
      end
    end
  end

  describe "Process Death and Cleanup" do
    test "agent process death cleanup" do
      FeatureFlags.enable(:use_ets_agent_registry)

      case Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
        {:module, _} ->
          {:ok, _} = Foundation.Protocols.RegistryETS.start_link()

          # Create agent processes
          agents =
            for i <- 1..20 do
              agent_pid =
                spawn_link(fn ->
                  receive do
                    :stop -> :ok
                  after
                    10_000 -> :timeout
                  end
                end)

              agent_id = :"death_test_#{i}"
              Registry.register(nil, agent_id, agent_pid)

              {agent_id, agent_pid}
            end

          # Verify all are registered
          for {agent_id, agent_pid} <- agents do
            assert {:ok, {^agent_pid, _}} = Registry.lookup(nil, agent_id)
          end

          # Kill half the agents
          {kill_agents, keep_agents} = Enum.split(agents, 10)

          for {_agent_id, agent_pid} <- kill_agents do
            Process.exit(agent_pid, :kill)
          end

          # Wait for cleanup
          wait_until(
            fn ->
              # Check that killed agents are cleaned up
              Enum.all?(kill_agents, fn {agent_id, _} ->
                case Registry.lookup(nil, agent_id) do
                  {:error, :not_found} -> true
                  _ -> false
                end
              end)
            end,
            5000
          )

          # Verify killed agents are cleaned up
          for {agent_id, _} <- kill_agents do
            assert {:error, :not_found} = Registry.lookup(nil, agent_id)
          end

          # Verify remaining agents are still registered
          for {agent_id, agent_pid} <- keep_agents do
            assert {:ok, {^agent_pid, _}} = Registry.lookup(nil, agent_id)
          end

          # Clean up remaining agents
          for {_agent_id, agent_pid} <- keep_agents do
            send(agent_pid, :stop)
          end

        {:error, :nofile} ->
          :ok
      end
    end

    test "massive process death scenario" do
      FeatureFlags.enable(:use_ets_agent_registry)

      case Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
        {:module, _} ->
          {:ok, _} = Foundation.Protocols.RegistryETS.start_link()

          num_agents = 100

          # Create many short-lived agents
          agents =
            for i <- 1..num_agents do
              agent_pid =
                spawn(fn ->
                  # Agent dies after random short time
                  :timer.sleep(Enum.random(10..100))
                end)

              agent_id = :"massive_death_#{i}"
              Registry.register(nil, agent_id, agent_pid)

              {agent_id, agent_pid}
            end

          # All should die naturally within 200ms
          Process.sleep(200)

          # Wait for cleanup
          wait_until(
            fn ->
              # Check that all agents are cleaned up
              Enum.all?(agents, fn {agent_id, _} ->
                case Registry.lookup(nil, agent_id) do
                  {:error, :not_found} -> true
                  _ -> false
                end
              end)
            end,
            10_000
          )

          # Verify all are cleaned up
          for {agent_id, _} <- agents do
            assert {:error, :not_found} = Registry.lookup(nil, agent_id)
          end

          # Registry should still be functional
          Registry.register(nil, :post_death_test, self())
          assert {:ok, {pid, _}} = Registry.lookup(nil, :post_death_test)
          assert pid == self()

        {:error, :nofile} ->
          :ok
      end
    end

    test "process death during error context operations" do
      FeatureFlags.enable(:use_logger_error_context)

      # Create process that sets error context then dies
      test_pid = self()

      dying_process =
        spawn(fn ->
          ErrorContext.set_context(%{
            dying_process: true,
            pid: self(),
            timestamp: System.system_time()
          })

          send(test_pid, :context_set)

          # Die with context set
          :timer.sleep(50)
        end)

      # Wait for context to be set
      assert_receive :context_set, 1000

      # Wait for process to die
      ref = Process.monitor(dying_process)
      assert_receive {:DOWN, ^ref, :process, ^dying_process, :normal}, 1000

      # Main process should still have clean context
      ErrorContext.set_context(%{main_process: true})
      context = ErrorContext.get_context()

      assert context.main_process == true
      refute Map.has_key?(context, :dying_process)
    end
  end

  describe "Memory Leak Prevention" do
    test "no memory leaks after failures" do
      FeatureFlags.enable_otp_cleanup_stage(4)

      initial_memory = :erlang.memory(:total)

      # Simulate failures in a loop
      for cycle <- 1..20 do
        # Start services
        services = start_all_services()

        # Create state
        for i <- 1..50 do
          agent_id = :"leak_test_#{cycle}_#{i}"

          try do
            Registry.register(nil, agent_id, self())

            ErrorContext.set_context(%{
              cycle: cycle,
              agent: i,
              large_data: String.duplicate("x", 1000)
            })

            span_id = Span.start_span("leak_test", %{cycle: cycle, agent: i})
            Span.end_span(span_id)
          rescue
            _ -> :ok
          end
        end

        # Simulate failures
        crash_services(services)

        # Clear contexts
        ErrorContext.clear_context()

        # Force garbage collection
        :erlang.garbage_collect()

        # Small delay to let cleanup complete
        Process.sleep(50)
      end

      # Final garbage collection
      :erlang.garbage_collect()
      Process.sleep(100)

      final_memory = :erlang.memory(:total)
      memory_growth = final_memory - initial_memory

      # Memory should not grow significantly
      # 100MB
      assert memory_growth < 100_000_000,
             "Memory leak detected after failures: #{memory_growth} bytes"
    end

    test "ETS table cleanup after failures" do
      initial_ets_count = :erlang.system_info(:ets_count)

      FeatureFlags.enable_otp_cleanup_stage(4)

      # Create and destroy services multiple times
      for _round <- 1..10 do
        services = start_all_services()

        # Use services to create ETS entries
        try do
          Registry.register(nil, :"ets_cleanup_#{:erlang.unique_integer()}", self())
          FeatureFlags.enable(:use_genserver_telemetry)
        rescue
          _ -> :ok
        end

        # Crash services
        crash_services(services)

        # Small delay
        Process.sleep(20)
      end

      # Wait for cleanup
      Process.sleep(1000)

      final_ets_count = :erlang.system_info(:ets_count)
      ets_growth = final_ets_count - initial_ets_count

      # ETS table count should not grow significantly
      assert ets_growth < 50,
             "ETS table leak detected: #{ets_growth} extra tables"
    end

    defp start_all_services do
      services = []

      services =
        case Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
          {:module, _} ->
            try do
              {:ok, pid} = Foundation.Protocols.RegistryETS.start_link()
              [{:registry_ets, pid} | services]
            rescue
              _ -> services
            end

          {:error, :nofile} ->
            services
        end

      services =
        case Code.ensure_loaded?(Foundation.Telemetry.SampledEvents) do
          {:module, _} ->
            try do
              {:ok, pid} = Foundation.Telemetry.SampledEvents.start_link()
              [{:sampled_events, pid} | services]
            rescue
              _ -> services
            end

          {:error, :nofile} ->
            services
        end

      services
    end

    defp crash_services(services) do
      for {_service_name, pid} <- services do
        if Process.alive?(pid) do
          Process.exit(pid, :kill)
        end
      end
    end
  end

  describe "Network and External Failure Simulation" do
    test "system resilience under simulated network failures" do
      FeatureFlags.enable_otp_cleanup_stage(4)

      # Simulate network issues by creating load and then introducing delays
      num_workers = 20

      # Create workers that perform operations
      workers =
        for i <- 1..num_workers do
          Task.async(fn ->
            for j <- 1..100 do
              try do
                # Simulate network-like delays
                if rem(j, 10) == 0 do
                  Process.sleep(Enum.random(50..200))
                end

                agent_id = :"network_sim_#{i}_#{j}"
                Registry.register(nil, agent_id, self())

                ErrorContext.set_context(%{
                  worker: i,
                  operation: j,
                  simulated_network_delay: rem(j, 10) == 0
                })

                span_id = Span.start_span("network_operation", %{worker: i, op: j})

                # Simulate network timeout
                if rem(j, 20) == 0 do
                  raise "simulated network timeout"
                end

                Registry.lookup(nil, agent_id)
                Span.end_span(span_id)
              rescue
                # Expected failures
                _ -> :ok
              end
            end
          end)
        end

      # Wait for all workers to complete
      Task.await_many(workers, 60_000)

      # System should still be functional
      Registry.register(nil, :post_network_sim, self())
      assert {:ok, {pid, _}} = Registry.lookup(nil, :post_network_sim)
      assert pid == self()

      ErrorContext.set_context(%{post_network_test: true})
      assert ErrorContext.get_context().post_network_test == true
    end

    test "graceful degradation under extreme failure" do
      FeatureFlags.enable_otp_cleanup_stage(4)

      # Start all available services
      services = start_all_services()

      # Establish baseline functionality
      Registry.register(nil, :baseline_test, self())
      ErrorContext.set_context(%{baseline: true})
      span_id = Span.start_span("baseline", %{})
      Span.end_span(span_id)

      # Simulate cascading failures

      # 1. Kill all services
      crash_services(services)

      # 2. Delete ETS tables
      try do
        :ets.delete(:foundation_agent_registry)
      rescue
        _ -> :ok
      end

      try do
        :ets.delete(:foundation_feature_flags)
      rescue
        _ -> :ok
      end

      # 3. System should gracefully degrade but not crash

      # Basic error context should still work (Logger metadata fallback)
      ErrorContext.set_context(%{degraded_mode: true})
      context = ErrorContext.get_context()
      assert context.degraded_mode == true

      # Basic telemetry should work (fallback implementation)
      degraded_span = Span.start_span("degraded", %{})
      assert :ok = Span.end_span(degraded_span)

      # Registry may fail, but shouldn't crash the system
      try do
        Registry.register(nil, :degraded_test, self())
      rescue
        # Expected in degraded mode
        _ -> :ok
      end

      # Feature flags should recreate tables and continue
      FeatureFlags.enable(:use_logger_error_context)
      assert FeatureFlags.enabled?(:use_logger_error_context)
    end
  end

  describe "Recovery Time Tests" do
    test "fast recovery from ETS deletion" do
      FeatureFlags.enable(:use_ets_agent_registry)

      case Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
        {:module, _} ->
          {:ok, _} = Foundation.Protocols.RegistryETS.start_link()

          # Establish baseline
          Registry.register(nil, :recovery_time_test, self())

          # Delete table
          :ets.delete(:foundation_agent_registry)

          # Measure recovery time
          {recovery_time, _} =
            :timer.tc(fn ->
              # Should recreate table quickly
              Registry.register(nil, :recovery_test_2, self())
              assert {:ok, {pid, _}} = Registry.lookup(nil, :recovery_test_2)
              assert pid == self()
            end)

          # Recovery should be very fast (< 10ms)
          assert recovery_time < 10_000,
                 "ETS recovery too slow: #{recovery_time}μs"

        {:error, :nofile} ->
          :ok
      end
    end

    test "service restart time" do
      FeatureFlags.enable(:use_ets_sampled_events)

      case Code.ensure_loaded?(Foundation.Telemetry.SampledEvents) do
        {:module, _} ->
          {:ok, pid} = Foundation.Telemetry.SampledEvents.start_link()

          # Kill service
          Process.exit(pid, :kill)

          # Measure restart time
          {restart_time, _} =
            :timer.tc(fn ->
              {:ok, _new_pid} = Foundation.Telemetry.SampledEvents.start_link()

              # Should work immediately
              SampledEvents.emit_event(
                [:recovery, :test],
                %{count: 1},
                %{test: true}
              )
            end)

          # Restart should be fast (< 100ms)
          assert restart_time < 100_000,
                 "Service restart too slow: #{restart_time}μs"

        {:error, :nofile} ->
          :ok
      end
    end
  end
end
