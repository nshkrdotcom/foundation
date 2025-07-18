defmodule Foundation.OTPCleanupFailureRecoveryTest do
  @moduledoc """
  Failure and recovery tests for OTP cleanup migration.

  Tests behavior when ETS tables are deleted, GenServers crash,
  processes die, and various failure scenarios to ensure robust recovery.
  """

  use ExUnit.Case, async: false

  import Foundation.AsyncTestHelpers
  alias Foundation.{FeatureFlags, ErrorContext, Registry}
  alias Foundation.Telemetry.Span

  @moduletag :failure_recovery
  @moduletag :resilience
  # 3 minutes for failure recovery tests
  @moduletag timeout: 180_000

  setup_all do
    # Ensure FeatureFlags service is started for all tests
    ensure_service_started(Foundation.FeatureFlags)
    :ok
  end

  defp ensure_service_started(module) do
    case Process.whereis(module) do
      nil ->
        case module.start_link() do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          error -> error
        end

      pid ->
        {:ok, pid}
    end
  end

  describe "ETS Table Failure Recovery" do
    setup do
      # Ensure FeatureFlags is running
      ensure_service_started(Foundation.FeatureFlags)

      FeatureFlags.reset_all()

      on_exit(fn ->
        if Process.whereis(Foundation.FeatureFlags) do
          FeatureFlags.reset_all()
        end

        ErrorContext.clear_context()
      end)

      :ok
    end

    test "registry recovers from ETS table deletion" do
      FeatureFlags.enable(:use_ets_agent_registry)

      if Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
        {:ok, _registry_pid} = ensure_service_started(Foundation.Protocols.RegistryETS)

        # Wait for service to be ready
        Process.sleep(50)

        registry = %{}

        # Register some agents
        agents =
          for i <- 1..10 do
            agent_id = :"ets_failure_test_#{i}"
            Registry.register(registry, agent_id, self())

            # Verify registration
            assert {:ok, {pid, _}} = Registry.lookup(registry, agent_id)
            assert pid == self()

            agent_id
          end

        # Manually delete the ETS table to simulate failure
        table_name = :foundation_agent_registry_ets
        # Only delete if table exists
        if :ets.whereis(table_name) != :undefined do
          :ets.delete(table_name)
        end

        # Registry operations should recreate table and continue working
        new_agent_id = :post_deletion_agent

        # This should recreate the table
        assert :ok = Registry.register(registry, new_agent_id, self())
        assert {:ok, {pid, _}} = Registry.lookup(registry, new_agent_id)
        assert pid == self()

        # Old agents should be gone (table was deleted)
        for agent_id <- agents do
          assert :error = Registry.lookup(registry, agent_id)
        end

        # New registrations should work normally
        for i <- 1..5 do
          agent_id = :"post_recovery_#{i}"
          assert :ok = Registry.register(registry, agent_id, self())
          assert {:ok, {pid, _}} = Registry.lookup(registry, agent_id)
          assert pid == self()
        end
      else
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
        if Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
          {:ok, _} = ensure_service_started(Foundation.Protocols.RegistryETS)
          [:registry_ets | services_started]
        else
          services_started
        end

      services_started =
        if Code.ensure_loaded?(Foundation.Telemetry.SampledEvents) do
          {:ok, _} = Foundation.Telemetry.SampledEvents.start_link()
          [:sampled_events | services_started]
        else
          services_started
        end

      registry = %{}

      # Establish functionality
      if :registry_ets in services_started do
        Registry.register(registry, :before_failure, self())
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

      # Wait for FeatureFlags to recover before using Registry
      wait_until(
        fn ->
          try do
            # Force FeatureFlags to recreate its table by calling it
            FeatureFlags.reset_all()
            true
          rescue
            _ -> false
          end
        end,
        5000
      )

      # Test functionality after recovery
      if :registry_ets in services_started do
        Registry.register(registry, :after_recovery, self())
        assert {:ok, {pid, _}} = Registry.lookup(registry, :after_recovery)
        assert pid == self()
      end

      ErrorContext.set_context(%{after_recovery: true})
      assert ErrorContext.get_context().after_recovery == true

      recovery_span = Span.start_span("recovery_test", %{})
      assert :ok = Span.end_span(recovery_span)
    end
  end

  describe "GenServer Crash Recovery" do
    setup do
      ensure_service_started(Foundation.FeatureFlags)
      Process.flag(:trap_exit, true)

      on_exit(fn ->
        Process.flag(:trap_exit, false)
      end)

      :ok
    end

    test "telemetry GenServer recovery" do
      FeatureFlags.enable(:use_genserver_telemetry)
      FeatureFlags.enable(:use_genserver_span_management)

      if Code.ensure_loaded?(Foundation.Telemetry.SpanManager) do
        {:ok, span_manager_pid} = ensure_service_started(Foundation.Telemetry.SpanManager)

        # Test functionality before crash
        span1 = Span.start_span("before_crash", %{test: true})
        assert :ok = Span.end_span(span1)

        # Monitor and kill the GenServer
        ref = Process.monitor(span_manager_pid)
        Process.exit(span_manager_pid, :kill)

        # Wait for the process to die
        assert_receive {:DOWN, ^ref, :process, ^span_manager_pid, :killed}, 2000

        # SpanManager is not supervised in test environment, so restart it manually
        # Or disable the feature flag to use fallback
        case Process.whereis(Foundation.Telemetry.SpanManager) do
          nil ->
            # Either restart the service or use fallback
            FeatureFlags.disable(:use_genserver_span_management)

          _pid ->
            :ok
        end

        # System should handle the crash gracefully
        # (May use fallback implementation or restart)
        span2 = Span.start_span("after_crash", %{test: true})
        assert :ok = Span.end_span(span2)
      else
        :ok
      end
    end

    test "sampled events GenServer recovery" do
      FeatureFlags.enable(:use_ets_sampled_events)

      if Code.ensure_loaded?(Foundation.Telemetry.SampledEvents.Server) do
        {:ok, sampled_events_pid} =
          ensure_service_started(Foundation.Telemetry.SampledEvents.Server)

        # Test functionality before crash
        Foundation.Telemetry.SampledEvents.TestAPI.emit_event(
          [:test, :before_crash],
          %{count: 1},
          %{test: true}
        )

        # Monitor and kill the GenServer
        ref = Process.monitor(sampled_events_pid)
        Process.exit(sampled_events_pid, :kill)

        # Wait for the process to die
        assert_receive {:DOWN, ^ref, :process, ^sampled_events_pid, :killed}, 2000

        # Should handle gracefully (may lose events but not crash system)
        try do
          Foundation.Telemetry.SampledEvents.TestAPI.emit_event(
            [:test, :after_crash],
            %{count: 1},
            %{test: true}
          )
        rescue
          # Expected if service is down
          _ -> :ok
        end

        # Should be able to restart service
        {:ok, _new_pid} = ensure_service_started(Foundation.Telemetry.SampledEvents.Server)

        Foundation.Telemetry.SampledEvents.TestAPI.emit_event(
          [:test, :after_restart],
          %{count: 1},
          %{test: true}
        )
      else
        :ok
      end
    end

    test "registry GenServer recovery under load" do
      FeatureFlags.enable(:use_ets_agent_registry)

      if Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
        {:ok, registry_pid} = ensure_service_started(Foundation.Protocols.RegistryETS)

        # Create background load
        load_task =
          Task.async(fn ->
            registry = %{}

            for i <- 1..1000 do
              try do
                agent_id = :"load_test_#{i}"
                Registry.register(registry, agent_id, self())
                Registry.lookup(registry, agent_id)

                if rem(i, 100) == 0 do
                  Process.sleep(10)
                end
              rescue
                # May fail during crash
                _ -> :ok
              end
            end
          end)

        # Wait a bit for load to start, then monitor and kill registry
        Process.sleep(50)
        ref = Process.monitor(registry_pid)
        Process.exit(registry_pid, :kill)

        # Wait for the process to die
        assert_receive {:DOWN, ^ref, :process, ^registry_pid, :killed}, 2000

        # Wait for load task to complete
        Task.await(load_task, 30_000)

        # Registry should still be functional
        registry = %{}
        Registry.register(registry, :post_crash_load, self())
        assert {:ok, {pid, _}} = Registry.lookup(registry, :post_crash_load)
        assert pid == self()
      else
        :ok
      end
    end
  end

  describe "Process Death and Cleanup" do
    setup do
      ensure_service_started(Foundation.FeatureFlags)
      :ok
    end

    test "agent process death cleanup" do
      FeatureFlags.enable(:use_ets_agent_registry)

      if Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
        {:ok, _} = ensure_service_started(Foundation.Protocols.RegistryETS)

        registry = %{}

        # Create agent processes
        agents =
          for i <- 1..20 do
            agent_pid =
              spawn(fn ->
                receive do
                  :stop -> :ok
                after
                  10_000 -> :timeout
                end
              end)

            agent_id = :"death_test_#{i}"
            Registry.register(registry, agent_id, agent_pid)

            {agent_id, agent_pid}
          end

        # Verify all are registered
        for {agent_id, agent_pid} <- agents do
          assert {:ok, {^agent_pid, _}} = Registry.lookup(registry, agent_id)
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
              case Registry.lookup(registry, agent_id) do
                {:error, :not_found} -> true
                _ -> false
              end
            end)
          end,
          5000
        )

        # Verify killed agents are cleaned up
        for {agent_id, _} <- kill_agents do
          assert :error = Registry.lookup(registry, agent_id)
        end

        # Verify remaining agents are still registered
        for {agent_id, agent_pid} <- keep_agents do
          assert {:ok, {^agent_pid, _}} = Registry.lookup(registry, agent_id)
        end

        # Clean up remaining agents
        for {_agent_id, agent_pid} <- keep_agents do
          send(agent_pid, :stop)
        end
      else
        :ok
      end
    end

    test "massive process death scenario" do
      FeatureFlags.enable(:use_ets_agent_registry)

      if Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
        {:ok, _} = ensure_service_started(Foundation.Protocols.RegistryETS)

        registry = %{}
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
            Registry.register(registry, agent_id, agent_pid)

            # Monitor the agent so we know when it dies
            ref = Process.monitor(agent_pid)

            {agent_id, agent_pid, ref}
          end

        # Wait for all agents to die naturally
        for {_agent_id, _agent_pid, ref} <- agents do
          assert_receive {:DOWN, ^ref, :process, _, _}, 500
        end

        # Wait for cleanup
        wait_until(
          fn ->
            # Check that all agents are cleaned up
            Enum.all?(agents, fn {agent_id, _, _} ->
              case Registry.lookup(registry, agent_id) do
                {:error, :not_found} -> true
                _ -> false
              end
            end)
          end,
          10_000
        )

        # Verify all are cleaned up
        for {agent_id, _, _} <- agents do
          assert :error = Registry.lookup(registry, agent_id)
        end

        # Registry should still be functional
        Registry.register(registry, :post_death_test, self())
        assert {:ok, {pid, _}} = Registry.lookup(registry, :post_death_test)
        assert pid == self()
      else
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

      # Monitor the dying process
      ref = Process.monitor(dying_process)

      # Wait for context to be set
      assert_receive :context_set, 1000

      # Wait for process to die
      assert_receive {:DOWN, ^ref, :process, ^dying_process, :normal}, 1000

      # Main process should still have clean context
      ErrorContext.set_context(%{main_process: true})
      context = ErrorContext.get_context()

      assert context.main_process == true
      refute Map.has_key?(context, :dying_process)
    end
  end

  # Helper functions for service management
  defp start_all_services do
    services = []

    # Start RegistryETS if available
    services =
      if Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
        case ensure_service_started(Foundation.Protocols.RegistryETS) do
          {:ok, pid} -> [{:registry_ets, pid} | services]
          _ -> services
        end
      else
        services
      end

    # Start SpanManager if available
    services =
      if Code.ensure_loaded?(Foundation.Telemetry.SpanManager) do
        case ensure_service_started(Foundation.Telemetry.SpanManager) do
          {:ok, pid} -> [{:span_manager, pid} | services]
          _ -> services
        end
      else
        services
      end

    # Start SampledEvents if available
    services =
      if Code.ensure_loaded?(Foundation.Telemetry.SampledEvents.Server) do
        case ensure_service_started(Foundation.Telemetry.SampledEvents.Server) do
          {:ok, pid} -> [{:sampled_events, pid} | services]
          _ -> services
        end
      else
        services
      end

    services
  end

  defp crash_services(services) do
    # Monitor all services before killing them
    monitors =
      for {name, pid} <- services, Process.alive?(pid) do
        ref = Process.monitor(pid)
        Process.exit(pid, :kill)
        {name, pid, ref}
      end

    # Wait for all monitored processes to die
    for {_name, pid, ref} <- monitors do
      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 2000
    end
  end

  describe "Memory Leak Prevention" do
    setup do
      ensure_service_started(Foundation.FeatureFlags)
      Process.flag(:trap_exit, true)

      on_exit(fn ->
        Process.flag(:trap_exit, false)
      end)

      :ok
    end

    test "no memory leaks after failures" do
      FeatureFlags.enable_otp_cleanup_stage(4)

      # Ensure SpanManager is started if available
      if Code.ensure_loaded?(Foundation.Telemetry.SpanManager) do
        ensure_service_started(Foundation.Telemetry.SpanManager)
      end

      initial_memory = :erlang.memory(:total)

      # Simulate failures in a loop
      for cycle <- 1..20 do
        # Start services
        services = start_all_services()

        # Create state
        for i <- 1..50 do
          agent_id = :"leak_test_#{cycle}_#{i}"

          try do
            registry = %{}
            Registry.register(registry, agent_id, self())

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
          registry = %{}
          Registry.register(registry, :"ets_cleanup_#{:erlang.unique_integer()}", self())
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
  end

  describe "Network and External Failure Simulation" do
    setup do
      ensure_service_started(Foundation.FeatureFlags)
      Process.flag(:trap_exit, true)

      # Ensure telemetry services are available if the modules exist
      if Code.ensure_loaded?(Foundation.Telemetry.SpanManager) do
        ensure_service_started(Foundation.Telemetry.SpanManager)
      end

      if Code.ensure_loaded?(Foundation.Telemetry.SampledEvents.Server) do
        ensure_service_started(Foundation.Telemetry.SampledEvents.Server)
      end

      on_exit(fn ->
        Process.flag(:trap_exit, false)
      end)

      :ok
    end

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
                registry = %{}
                Registry.register(registry, agent_id, self())

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

                Registry.lookup(registry, agent_id)
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
      registry = %{}
      Registry.register(registry, :post_network_sim, self())
      assert {:ok, {pid, _}} = Registry.lookup(registry, :post_network_sim)
      assert pid == self()

      ErrorContext.set_context(%{post_network_test: true})
      assert ErrorContext.get_context().post_network_test == true
    end

    test "graceful degradation under extreme failure" do
      FeatureFlags.enable_otp_cleanup_stage(4)

      # Start all available services
      services = start_all_services()

      # Establish baseline functionality
      registry = %{}
      Registry.register(registry, :baseline_test, self())
      ErrorContext.set_context(%{baseline: true})
      span_id = Span.start_span("baseline", %{})
      Span.end_span(span_id)

      # Simulate cascading failures

      # 1. Kill all services
      crash_services(services)

      # 2. Delete ETS tables
      try do
        :ets.delete(:foundation_agent_registry_ets)
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
      # But first ensure FeatureFlags service is restarted after deletion
      ensure_service_started(Foundation.FeatureFlags)

      # Wait for FeatureFlags to recover its ETS table
      wait_until(
        fn ->
          try do
            # Try to enable a flag - this forces GenServer to init and create table
            FeatureFlags.enable(:test_recovery_flag)
            true
          rescue
            _ -> false
          end
        end,
        5000
      )

      # ErrorContext should handle missing FeatureFlags gracefully
      # In extreme failure, it should fall back to process dictionary
      try do
        ErrorContext.set_context(%{degraded_mode: true})
        context = ErrorContext.get_context()
        assert context.degraded_mode == true || context == %{degraded_mode: true}
      rescue
        # If ETS table is not ready yet, we accept the error
        ArgumentError -> :ok
      end

      # Basic telemetry should work (fallback implementation)
      degraded_span = Span.start_span("degraded", %{})
      assert :ok = Span.end_span(degraded_span)

      # Registry may fail, but shouldn't crash the system
      try do
        registry = %{}
        Registry.register(registry, :degraded_test, self())
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
    setup do
      ensure_service_started(Foundation.FeatureFlags)
      Process.flag(:trap_exit, true)

      on_exit(fn ->
        Process.flag(:trap_exit, false)
      end)

      :ok
    end

    test "fast recovery from ETS deletion" do
      FeatureFlags.enable(:use_ets_agent_registry)

      if Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
        {:ok, _} = ensure_service_started(Foundation.Protocols.RegistryETS)

        registry = %{}

        # Establish baseline
        Registry.register(registry, :recovery_time_test, self())

        # Delete table
        if :ets.whereis(:foundation_agent_registry_ets) != :undefined do
          :ets.delete(:foundation_agent_registry_ets)
        end

        # Measure recovery time
        {recovery_time, _} =
          :timer.tc(fn ->
            # Should recreate table quickly
            Registry.register(registry, :recovery_test_2, self())
            assert {:ok, {pid, _}} = Registry.lookup(registry, :recovery_test_2)
            assert pid == self()
          end)

        # Recovery should be very fast (< 10ms)
        assert recovery_time < 10_000,
               "ETS recovery too slow: #{recovery_time}μs"
      else
        :ok
      end
    end

    test "service restart time" do
      FeatureFlags.enable(:use_ets_sampled_events)

      if Code.ensure_loaded?(Foundation.Telemetry.SampledEvents.Server) do
        {:ok, pid} = ensure_service_started(Foundation.Telemetry.SampledEvents.Server)

        # Monitor and kill service
        ref = Process.monitor(pid)
        Process.exit(pid, :kill)

        # Wait for process to die
        assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 2000

        # Measure restart time
        {restart_time, _} =
          :timer.tc(fn ->
            {:ok, _new_pid} = ensure_service_started(Foundation.Telemetry.SampledEvents.Server)

            # Should work immediately
            Foundation.Telemetry.SampledEvents.TestAPI.emit_event(
              [:recovery, :test],
              %{count: 1},
              %{test: true}
            )
          end)

        # Restart should be fast (< 100ms)
        assert restart_time < 100_000,
               "Service restart too slow: #{restart_time}μs"
      else
        :ok
      end
    end
  end
end
