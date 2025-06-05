defmodule Foundation.Integration.CrossServiceIntegrationTest do
  @moduledoc """
  Advanced cross-service integration tests for Foundation layer.

  Tests complex scenarios involving multiple services working together,
  edge cases, and advanced integration patterns not covered by other tests.
  """

  use ExUnit.Case, async: false

  # , ErrorContext, GracefulDegradation}
  alias Foundation.{Config, Events, Telemetry}
  alias Foundation.Services.{ConfigServer, EventStore, TelemetryService}
  alias Foundation.TestHelpers

  setup do
    # Ensure all services are available
    :ok = TestHelpers.ensure_config_available()
    :ok = EventStore.initialize()
    :ok = TelemetryService.initialize()

    # Store original config for restoration
    {:ok, original_config} = Config.get()

    # Clear existing events to start fresh
    current_time = System.monotonic_time()
    {:ok, _} = EventStore.prune_before(current_time)

    on_exit(fn ->
      # Restore configuration
      try do
        if Config.available?() do
          case original_config do
            %{ai: %{planning: %{sampling_rate: rate}}} ->
              Config.update([:ai, :planning, :sampling_rate], rate)

            _ ->
              :ok
          end
        end
      catch
        :exit, _ -> :ok
      end
    end)

    %{original_config: original_config}
  end

  # Helper functions

  defp wait_for_service_available(module, max_attempts \\ 10) do
    Enum.reduce_while(1..max_attempts, false, fn attempt, _acc ->
      if module.available?() do
        {:halt, true}
      else
        # Exponential backoff
        Process.sleep(50 * attempt)
        {:cont, false}
      end
    end)
  end

  describe "cross-service transaction patterns" do
    test "config update triggers event chain with telemetry tracking" do
      # Start telemetry collection
      {:ok, initial_metrics} = Telemetry.get_metrics()

      # Perform a config update that should trigger multiple events
      correlation_id = Foundation.Utils.generate_correlation_id()

      # Config update
      :ok = Config.update([:ai, :planning, :sampling_rate], 0.85)
      Process.sleep(50)

      # Verify config event was created
      {:ok, config_events} = EventStore.query(%{event_type: :config_updated})

      config_event =
        Enum.find(config_events, fn event ->
          event.data.path == [:ai, :planning, :sampling_rate] and
            event.data.new_value == 0.85
        end)

      assert config_event != nil

      # Create related events using the same correlation pattern
      {:ok, validation_event} =
        Events.new_event(
          :config_validation_success,
          %{config_path: [:ai, :planning, :sampling_rate], validated_value: 0.85},
          correlation_id: correlation_id,
          parent_id: config_event.event_id
        )

      {:ok, _validation_id} = EventStore.store(validation_event)

      {:ok, application_event} =
        Events.new_event(
          :config_applied,
          %{config_path: [:ai, :planning, :sampling_rate], applied_value: 0.85},
          correlation_id: correlation_id,
          parent_id: validation_event.event_id
        )

      {:ok, _application_id} = EventStore.store(application_event)

      Process.sleep(100)

      # Verify telemetry tracked all operations
      {:ok, final_metrics} = Telemetry.get_metrics()

      # Should have at least one more config update and event storage operations
      final_config_updates = get_in(final_metrics, [:foundation, :config_updates]) || 0
      initial_config_updates = get_in(initial_metrics, [:foundation, :config_updates]) || 0
      assert final_config_updates > initial_config_updates

      final_events_stored = get_in(final_metrics, [:foundation, :events_stored]) || 0
      initial_events_stored = get_in(initial_metrics, [:foundation, :events_stored]) || 0
      # At least 2 new events
      assert final_events_stored >= initial_events_stored + 2

      # Verify event correlation chain
      {:ok, correlated_events} = EventStore.get_by_correlation(correlation_id)
      assert length(correlated_events) >= 2

      # Verify parent-child relationships in the chain (get events by type to ensure order)
      validation_events =
        Enum.filter(correlated_events, fn event ->
          event.event_type == :config_validation_success
        end)

      application_events =
        Enum.filter(correlated_events, fn event ->
          event.event_type == :config_applied
        end)

      assert length(validation_events) >= 1
      assert length(application_events) >= 1

      validation_event = List.first(validation_events)
      application_event = List.first(application_events)

      # Application event should have validation event as parent
      assert application_event.parent_id == validation_event.event_id
    end
  end

  describe "service resilience under load" do
    test "services maintain coordination under concurrent operations" do
      # Concurrent config updates, event creation, and telemetry collection
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            # Each task performs a sequence of operations
            # 0.2, 0.3, 0.4, 0.5, 0.6
            config_value = 0.1 + i * 0.1

            # Config update
            :ok = Config.update([:ai, :planning, :sampling_rate], config_value)

            # Event creation
            {:ok, event} =
              Events.new_event(:load_test_operation, %{
                task_id: i,
                config_value: config_value,
                timestamp: System.monotonic_time()
              })

            {:ok, _event_id} = EventStore.store(event)

            # Telemetry query
            {:ok, metrics} = Telemetry.get_metrics()

            {i, config_value, metrics}
          end)
        end

      # Wait for all tasks
      results = Task.await_many(tasks, 5000)

      # Verify all tasks completed successfully
      assert length(results) == 5

      # Verify final state consistency
      {:ok, final_config} = Config.get([:ai, :planning, :sampling_rate])
      # One of the values set - use tolerance for floating point comparison
      expected_values = [0.2, 0.3, 0.4, 0.5, 0.6]
      tolerance = 0.000001

      assert Enum.any?(expected_values, fn expected ->
               abs(final_config - expected) < tolerance
             end),
             "Expected final_config #{final_config} to be close to one of #{inspect(expected_values)}"

      # Verify all events were stored
      {:ok, load_events} = EventStore.query(%{event_type: :load_test_operation})
      task_ids = Enum.map(load_events, fn event -> event.data.task_id end)
      assert Enum.sort(task_ids) == [1, 2, 3, 4, 5]

      # Verify telemetry captured all operations
      {:ok, final_metrics} = Telemetry.get_metrics()
      assert is_map(final_metrics)
      config_updates = get_in(final_metrics, [:foundation, :config_updates]) || 0
      events_stored = get_in(final_metrics, [:foundation, :events_stored]) || 0
      assert config_updates >= 5
      assert events_stored >= 5
    end
  end

  describe "edge case handling" do
    test "rapid service restart maintains data consistency" do
      # Trap exits to prevent test crashes
      Process.flag(:trap_exit, true)

      # Create some baseline data
      correlation_id = Foundation.Utils.generate_correlation_id()

      {:ok, baseline_event} =
        Events.new_event(:restart_test, %{
          phase: "before_restart",
          correlation_id: correlation_id
        })

      {:ok, baseline_id} = EventStore.store(baseline_event)

      # Less aggressive restart sequence - restart one service at a time
      services = [TelemetryService, EventStore, ConfigServer]

      for service <- services do
        if pid = GenServer.whereis(service) do
          GenServer.stop(pid, :normal, 1000)
        end

        # Longer wait between operations
        Process.sleep(100)
        :ok = service.initialize()
        # Longer wait for stabilization
        Process.sleep(100)
      end

      # Verify services are functional after restart
      assert wait_for_service_available(ConfigServer),
             "ConfigServer should be available after restart"

      assert wait_for_service_available(EventStore), "EventStore should be available after restart"

      assert wait_for_service_available(TelemetryService),
             "TelemetryService should be available after restart"

      # Test data consistency after restart
      {:ok, after_restart_event} =
        Events.new_event(:restart_test, %{
          phase: "after_restart",
          correlation_id: correlation_id,
          previous_event_id: baseline_id
        })

      {:ok, _after_restart_id} = EventStore.store(after_restart_event)

      # Config operations should work
      {:ok, _config} = Config.get()
      :ok = Config.update([:ai, :planning, :sampling_rate], 0.75)

      # Telemetry should be collecting
      {:ok, metrics} = Telemetry.get_metrics()
      assert is_map(metrics)

      # Event correlation should work across restart
      {:ok, restart_events} = EventStore.query(%{event_type: :restart_test})
      assert length(restart_events) >= 2

      phases = Enum.map(restart_events, fn event -> event.data.phase end)
      assert "before_restart" in phases
      assert "after_restart" in phases

      # Restore exit trapping
      Process.flag(:trap_exit, false)
    end

    test "service recovery from partial failures" do
      # Trap exits to prevent test crashes
      Process.flag(:trap_exit, true)

      # Simulate partial failure by stopping only EventStore
      if pid = GenServer.whereis(EventStore) do
        GenServer.stop(pid, :shutdown, 1000)
      end

      # Longer wait for detection
      Process.sleep(200)

      # Config should still work
      assert ConfigServer.available?()
      {:ok, _config} = Config.get()

      # TelemetryService should still work
      assert TelemetryService.available?()
      {:ok, _metrics} = Telemetry.get_metrics()

      # Config updates should still work (without event emission)
      :ok = Config.update([:ai, :planning, :sampling_rate], 0.95)

      # Restart EventStore
      :ok = EventStore.initialize()
      # Longer wait for restart
      Process.sleep(300)

      # Full integration should be restored
      assert wait_for_service_available(EventStore), "EventStore should be available after restart"

      # Test full integration
      {:ok, recovery_event} =
        Events.new_event(:recovery_test, %{
          recovered_at: System.monotonic_time()
        })

      {:ok, _recovery_id} = EventStore.store(recovery_event)

      # Config with event emission should work again
      :ok = Config.update([:ai, :planning, :sampling_rate], 0.80)
      # Wait for event processing
      Process.sleep(100)

      {:ok, config_events} = EventStore.query(%{event_type: :config_updated})

      recent_config_events =
        Enum.filter(config_events, fn event ->
          event.data.new_value == 0.80
        end)

      assert length(recent_config_events) >= 1

      # Restore exit trapping
      Process.flag(:trap_exit, false)
    end
  end

  describe "complex event patterns" do
    test "hierarchical event structures with deep correlation" do
      # Create a complex hierarchy: Process -> Module -> Function -> Operation
      root_correlation = Foundation.Utils.generate_correlation_id()

      # Level 1: Process started
      {:ok, process_event} =
        Events.new_event(
          :process_started,
          %{
            process_name: "test_process",
            pid: self()
          },
          correlation_id: root_correlation
        )

      {:ok, process_id} = EventStore.store(process_event)

      # Level 2: Module loaded
      {:ok, module_event} =
        Events.new_event(
          :module_loaded,
          %{
            module: TestModule,
            process_name: "test_process"
          },
          correlation_id: root_correlation,
          parent_id: process_id
        )

      {:ok, module_id} = EventStore.store(module_event)

      # Level 3: Function called
      {:ok, function_event} =
        Events.new_event(
          :function_called,
          %{
            module: TestModule,
            function: :test_function,
            arity: 2
          },
          correlation_id: root_correlation,
          parent_id: module_id
        )

      {:ok, function_id} = EventStore.store(function_event)

      # Level 4: Multiple operations
      operations = [:initialize, :process, :validate, :complete]

      operation_ids =
        for {op, index} <- Enum.with_index(operations, 1) do
          {:ok, op_event} =
            Events.new_event(
              :operation_executed,
              %{
                operation: op,
                sequence: index,
                function_context: :test_function
              },
              correlation_id: root_correlation,
              parent_id: function_id
            )

          {:ok, op_id} = EventStore.store(op_event)
          op_id
        end

      # Verify the complete hierarchy
      {:ok, all_events} = EventStore.get_by_correlation(root_correlation)
      # 1 process + 1 module + 1 function + 4 operations
      assert length(all_events) == 7

      # Verify hierarchical structure
      events_by_id = Map.new(all_events, fn event -> {event.event_id, event} end)

      # Process event has no parent
      process_retrieved = events_by_id[process_id]
      assert process_retrieved.parent_id == nil

      # Module event has process as parent
      module_retrieved = events_by_id[module_id]
      assert module_retrieved.parent_id == process_id

      # Function event has module as parent
      function_retrieved = events_by_id[function_id]
      assert function_retrieved.parent_id == module_id

      # All operations have function as parent
      for op_id <- operation_ids do
        op_retrieved = events_by_id[op_id]
        assert op_retrieved.parent_id == function_id
      end

      # Verify temporal ordering
      timestamps = Enum.map(all_events, & &1.timestamp)
      assert timestamps == Enum.sort(timestamps)
    end
  end

  # describe "cross-service error handling and context" do
  #   test "ErrorContext correctly captures and enhances an error originating in ConfigLogic and passed through ConfigServer" do
  #     context = ErrorContext.new("config_update_operation", %{user: "test", action: "update"})

  #     result = ErrorContext.with_context(context, fn ->
  #       # Try to update a non-updatable path to trigger an error
  #       Config.update([:invalid, :path], "invalid_value")
  #     end)

  #     assert {:error, enhanced_error} = result
  #     assert enhanced_error.context[:operation_context] == context
  #     assert enhanced_error.context[:user] == "test"
  #   end

  #   test "EventStore pruning based on max_age_seconds (from config) triggers telemetry" do
  #     # Store some events first
  #     {:ok, _event_id1} = Events.store(%{event_type: :test_event, data: %{test: 1}})
  #     {:ok, _event_id2} = Events.store(%{event_type: :test_event, data: %{test: 2}})

  #     # Trigger pruning by setting a very short max_age
  #     :ok = Config.update([:event_store, :hot_storage, :max_age_seconds], 0)

  #     # Wait a bit for async pruning
  #     Process.sleep(100)

  #     # Check that telemetry was emitted for pruning
  #     {:ok, metrics} = Telemetry.get_metrics()
  #     assert Map.has_key?(metrics, [:foundation, :event_store, :events_pruned])
  #   end

  #   test "TelemetryService cleanup of old metrics uses metric_retention_ms from config" do
  #     # Emit some metrics
  #     :ok = Telemetry.emit_counter([:test, :metric1], 1)
  #     :ok = Telemetry.emit_counter([:test, :metric2], 1)

  #     # Set very short retention time
  #     :ok = Config.update([:telemetry, :metric_retention_ms], 1)

  #     # Wait for cleanup
  #     Process.sleep(100)

  #     # Verify metrics were cleaned up
  #     {:ok, metrics} = Telemetry.get_metrics()
  #     # Note: This test verifies the integration, exact assertion depends on implementation
  #     assert is_map(metrics)
  #   end

  #   test "complex operation using ErrorContext.with_context spanning ConfigServer and EventStore calls correctly aggregates breadcrumbs" do
  #     parent_context = ErrorContext.new("complex_operation", %{session_id: "12345"})

  #     result = ErrorContext.with_context(parent_context, fn ->
  #       # Add breadcrumb for config access
  #       ErrorContext.add_breadcrumb(:info, "config", "accessing config", %{path: [:telemetry, :enable_vm_metrics]})

  #       {:ok, vm_metrics_enabled} = Config.get([:telemetry, :enable_vm_metrics])

  #       # Add breadcrumb for event creation
  #       ErrorContext.add_breadcrumb(:info, "events", "creating event", %{type: :complex_operation})

  #       {:ok, event_id} = Events.store(%{
  #         event_type: :complex_operation,
  #         data: %{vm_metrics_enabled: vm_metrics_enabled, session_id: "12345"}
  #       })

  #       {:ok, event_id}
  #     end)

  #     assert {:ok, _event_id} = result

  #     # Verify context was properly maintained throughout
  #     context = ErrorContext.get_current_context()
  #     assert is_nil(context) # Should be cleaned up after with_context
  #   end
  # end

  # describe "graceful degradation integration" do
  #   test "GracefulDegradation for ConfigServer uses cached value, then pending update is retried and succeeds after ConfigServer restarts" do
  #     # Initialize graceful degradation
  #     :ok = GracefulDegradation.initialize_fallback_system()

  #     # Get a value to cache it
  #     {:ok, original_value} = GracefulDegradation.get_with_fallback([:telemetry, :enable_vm_metrics])

  #     # Simulate ConfigServer being down by stopping it
  #     :ok = GenServer.stop(Foundation.ConfigServer, :normal)

  #     # Should still get cached value
  #     {:ok, cached_value} = GracefulDegradation.get_with_fallback([:telemetry, :enable_vm_metrics])
  #     assert cached_value == original_value

  #     # Try to update while down - should cache the update
  #     :ok = GracefulDegradation.update_with_fallback([:telemetry, :enable_vm_metrics], false)

  #     # Restart the supervisor to bring ConfigServer back
  #     {:ok, _pid} = Supervisor.restart_child(Foundation.Supervisor, Foundation.ConfigServer)

  #     # Retry pending updates
  #     :ok = GracefulDegradation.retry_pending_updates()

  #     # Verify the update was applied
  #     {:ok, updated_value} = Config.get([:telemetry, :enable_vm_metrics])
  #     assert updated_value == false
  #   end

  #   test "GracefulDegradation for EventStore uses JSON fallback when primary serialization fails, then telemetry records the fallback" do
  #     # Create an event with potentially problematic data
  #     problematic_data = %{
  #       pid: self(),  # PIDs can't be JSON serialized
  #       reference: make_ref(),  # References can't be JSON serialized
  #       normal_data: "this is fine"
  #     }

  #     event = GracefulDegradation.new_event_safe(:test_event, problematic_data)

  #     # Try to serialize it - should use fallback
  #     serialized = GracefulDegradation.serialize_safe(event)
  #     assert is_binary(serialized)

  #     # Verify it can be deserialized
  #     {:ok, deserialized} = GracefulDegradation.deserialize_safe(serialized)
  #     assert deserialized.event_type == :test_event
  #     assert deserialized.data.normal_data == "this is fine"
  #     # PID and reference should be converted to safe representations
  #     assert is_binary(deserialized.data.pid)
  #     assert is_binary(deserialized.data.reference)

  #     # Check that telemetry was emitted for fallback usage
  #     {:ok, metrics} = Telemetry.get_metrics()
  #     # Note: The exact metric path depends on implementation
  #     assert is_map(metrics)
  #   end
  # end

  # describe "end-to-end service initialization and health" do
  #   test "Foundation.initialize/1 with custom config options correctly initializes all services with those options" do
  #     Foundation.shutdown()

  #     custom_opts = [
  #       config: [telemetry: [enable_vm_metrics: false]],
  #       event_store: [max_events: 500],
  #       telemetry: [metric_retention_ms: 30_000]
  #     ]

  #     :ok = Foundation.initialize(custom_opts)

  #     # Verify config was applied
  #     {:ok, vm_metrics} = Config.get([:telemetry, :enable_vm_metrics])
  #     assert vm_metrics == false

  #     # Verify services are healthy
  #     {:ok, health} = Foundation.health()
  #     assert health.status == :healthy
  #   end

  #   test "Foundation.health/0 reflects healthy status when all services are running" do
  #     {:ok, health} = Foundation.health()
  #     assert health.status == :healthy
  #     assert health.services.config == :running
  #     assert health.services.events == :running
  #     assert health.services.telemetry == :running
  #   end

  #   test "Foundation.health/0 reflects degraded status if a core service is down" do
  #     # Stop a core service
  #     :ok = GenServer.stop(Foundation.ConfigServer, :normal)

  #     # Wait a moment for the health check to reflect the change
  #     Process.sleep(50)

  #     {:ok, health} = Foundation.health()
  #     assert health.status == :degraded
  #     assert health.services.config == :stopped
  #   end
  # end
end
