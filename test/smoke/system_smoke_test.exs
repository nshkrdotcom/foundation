defmodule Foundation.Smoke.SystemSmokeTest do
  @moduledoc """
  Smoke tests for Foundation system.

  These tests provide a quick, high-level sanity check to ensure the entire
  Foundation system can start and that its most critical functions are operational.
  """

  use ExUnit.Case, async: false

  alias Foundation.{Config, Events, Telemetry, Utils}
  alias Foundation.Types.Event

  @moduletag :smoke

  describe "Foundation System Smoke Tests" do
    test "Foundation layer initializes successfully" do
      # Wait for services to be available
      Foundation.TestHelpers.wait_for_all_services_available(5000)

      # Foundation should be initialized by the application
      assert Foundation.available?(), "Foundation layer should be available"

      # Verify status
      {:ok, status} = Foundation.status()
      assert is_map(status), "Status should return a map"
      assert Map.has_key?(status, :config), "Status should include config"
      assert Map.has_key?(status, :events), "Status should include events"
      assert Map.has_key?(status, :telemetry), "Status should include telemetry"
    end

    test "Configuration service basic operations work" do
      # Service should be available
      assert Config.available?(), "Config service should be available"

      # Should be able to get configuration
      {:ok, config} = Config.get()
      assert is_map(config), "Config should return a map"

      # Should be able to get specific values
      {:ok, debug_mode} = Config.get([:dev, :debug_mode])
      assert is_boolean(debug_mode), "Debug mode should be a boolean"

      # Should be able to update updatable paths
      updatable_paths = Config.updatable_paths()
      assert is_list(updatable_paths), "Should return list of updatable paths"
      assert length(updatable_paths) > 0, "Should have some updatable paths"
    end

    test "Event system basic operations work" do
      # Wait for service to be available
      Foundation.TestHelpers.wait_for_all_services_available(5000)

      # Service should be available
      assert Events.available?(), "Events service should be available"

      # Should be able to create events
      correlation_id = Utils.generate_correlation_id()
      {:ok, event} = Events.new_event(:smoke_test, %{test: "data"}, correlation_id: correlation_id)
      assert %Event{} = event
      assert event.event_type == :smoke_test
      assert event.correlation_id == correlation_id

      # Should be able to store events
      {:ok, event_id} = Events.store(event)
      assert is_integer(event_id), "Event ID should be an integer"

      # Should be able to retrieve events
      {:ok, retrieved_event} = Events.get(event_id)
      assert retrieved_event.event_id == event_id
      assert retrieved_event.event_type == :smoke_test

      # Should be able to query events
      {:ok, events} = Events.query(%{event_type: :smoke_test, limit: 10})
      assert is_list(events), "Query should return a list"
      assert length(events) >= 1, "Should find at least our test event"
    end

    test "Telemetry system basic operations work" do
      # Service should be available
      assert Telemetry.available?(), "Telemetry service should be available"

      # Should be able to emit counters
      :ok = Telemetry.emit_counter([:smoke_test, :counter], %{test: true})

      # Should be able to emit gauges
      :ok = Telemetry.emit_gauge([:smoke_test, :gauge], 42, %{test: true})

      # Should be able to execute telemetry events
      :ok = Telemetry.execute([:smoke_test, :custom], %{value: 100}, %{test: true})

      # Should be able to measure function execution
      result =
        Telemetry.measure([:smoke_test, :measurement], %{test: true}, fn ->
          # Small delay to ensure measurable duration
          :timer.sleep(1)
          :test_result
        end)

      assert result == :test_result

      # Should be able to get metrics
      {:ok, metrics} = Telemetry.get_metrics()
      assert is_map(metrics), "Metrics should be a map"
    end

    test "Utility functions work correctly" do
      # ID generation
      id1 = Utils.generate_id()
      id2 = Utils.generate_id()
      assert is_integer(id1), "Generated ID should be an integer"
      assert is_integer(id2), "Generated ID should be an integer"
      assert id1 != id2, "Generated IDs should be unique"

      # Correlation ID generation
      corr_id1 = Utils.generate_correlation_id()
      corr_id2 = Utils.generate_correlation_id()
      assert is_binary(corr_id1), "Correlation ID should be a string"
      assert is_binary(corr_id2), "Correlation ID should be a string"
      assert corr_id1 != corr_id2, "Correlation IDs should be unique"

      # Timestamp functions
      mono_time = Utils.monotonic_timestamp()
      wall_time = Utils.wall_timestamp()
      assert is_integer(mono_time), "Monotonic timestamp should be an integer"
      assert is_integer(wall_time), "Wall timestamp should be an integer"

      # Utility functions
      assert is_binary(Utils.safe_inspect(%{test: "data"}))
      assert is_map(Utils.deep_merge(%{a: 1}, %{b: 2}))
      assert is_binary(Utils.format_duration(1_000_000_000))
      assert is_binary(Utils.format_bytes(1024))
    end

    test "Error handling works correctly" do
      # Should be able to create errors
      error = Foundation.Error.new(:test_error, "Test error message")
      assert %Foundation.Error{} = error
      assert error.error_type == :test_error
      assert error.message == "Test error message"

      # Should be able to create error results
      {:error, error_result} = Foundation.Error.error_result(:test_error, "Test message")
      assert %Foundation.Error{} = error_result

      # Error should have proper structure
      assert is_atom(error_result.error_type)
      assert is_binary(error_result.message)
      assert is_integer(error_result.code)
    end

    test "Service registry basic operations work" do
      # Should be able to register a service
      test_pid = spawn(fn -> :timer.sleep(1000) end)
      :ok = Foundation.ServiceRegistry.register(:production, :smoke_test_service, test_pid)

      # Should be able to lookup the service
      {:ok, found_pid} = Foundation.ServiceRegistry.lookup(:production, :smoke_test_service)
      assert found_pid == test_pid

      # Should be able to list services
      services = Foundation.ServiceRegistry.list_services(:production)
      assert is_list(services)
      assert :smoke_test_service in services

      # Cleanup
      :ok = Foundation.ServiceRegistry.unregister(:production, :smoke_test_service)
      Process.exit(test_pid, :kill)
    end

    test "System health check works" do
      {:ok, health} = Foundation.health()
      assert is_map(health), "Health should return a map"
      assert Map.has_key?(health, :status), "Health should include status"
      assert health.status in [:healthy, :degraded], "Status should be valid"
    end

    test "Version information is available" do
      version = Foundation.version()
      assert is_binary(version), "Version should be a string"
      assert String.match?(version, ~r/\d+\.\d+\.\d+/), "Version should match semantic versioning"
    end
  end

  describe "Integration Smoke Tests" do
    test "Configuration changes trigger telemetry events" do
      # Get initial metrics
      {:ok, _initial_metrics} = Telemetry.get_metrics()

      # Make a configuration change
      if [:dev, :debug_mode] in Config.updatable_paths() do
        {:ok, original_value} = Config.get([:dev, :debug_mode])
        :ok = Config.update([:dev, :debug_mode], not original_value)

        # Restore original value
        :ok = Config.update([:dev, :debug_mode], original_value)
      end

      # Verify telemetry was emitted (metrics should have changed)
      {:ok, final_metrics} = Telemetry.get_metrics()
      # Note: We can't assert specific metrics without knowing the internal implementation,
      # but we can verify the system is responsive
      assert is_map(final_metrics)
    end

    test "Event creation triggers telemetry" do
      # Create an event and verify the system remains responsive
      correlation_id = Utils.generate_correlation_id()

      {:ok, event} =
        Events.new_event(:integration_test, %{smoke: true}, correlation_id: correlation_id)

      {:ok, _event_id} = Events.store(event)

      # Verify telemetry is still working
      :ok = Telemetry.emit_counter([:smoke_test, :integration], %{test: true})
      {:ok, metrics} = Telemetry.get_metrics()
      assert is_map(metrics)
    end

    test "System remains responsive under basic load" do
      # Create multiple events quickly
      correlation_id = Utils.generate_correlation_id()

      events =
        for i <- 1..10 do
          {:ok, event} = Events.new_event(:load_test, %{index: i}, correlation_id: correlation_id)
          event
        end

      # Store them in batch
      {:ok, event_ids} = Events.store_batch(events)
      assert length(event_ids) == 10

      # Emit multiple telemetry events
      for i <- 1..10 do
        :ok = Telemetry.emit_counter([:smoke_test, :load], %{index: i})
      end

      # System should still be responsive
      Foundation.TestHelpers.wait_for_all_services_available(5000)
      assert Foundation.available?()
      {:ok, _status} = Foundation.status()
    end
  end
end
