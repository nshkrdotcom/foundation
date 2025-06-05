defmodule Foundation.Services.ConfigServerTest do
  use ExUnit.Case, async: false

  alias Foundation.Services.ConfigServer
  # , Error}
  alias Foundation.Types.{Config}

  setup do
    # Use our modern test helper instead of TestProcessManager
    Foundation.TestHelpers.setup_foundation_test()

    # Wait for services to be ready (should be quick)
    case Foundation.TestHelpers.wait_for_services(2000) do
      :ok ->
        :ok

      {:error, :timeout} ->
        raise "Foundation services not available within timeout"
    end

    on_exit(fn ->
      Foundation.TestHelpers.cleanup_foundation_test()
    end)

    :ok
  end

  describe "get/0" do
    test "returns current configuration" do
      assert {:ok, %Config{}} = ConfigServer.get()
    end
  end

  describe "get/1" do
    test "returns configuration value for valid path" do
      assert {:ok, :mock} = ConfigServer.get([:ai, :provider])
      assert {:ok, false} = ConfigServer.get([:dev, :debug_mode])
    end

    test "returns error for invalid path" do
      assert {:error, error} = ConfigServer.get([:invalid, :path])
      assert error.error_type == :config_path_not_found
    end
  end

  describe "update/2" do
    test "updates valid configuration path" do
      assert :ok = ConfigServer.update([:dev, :debug_mode], true)
      assert {:ok, true} = ConfigServer.get([:dev, :debug_mode])
    end

    test "rejects update to non-updatable path" do
      assert {:error, error} = ConfigServer.update([:ai, :provider], :openai)
      assert error.error_type == :config_update_forbidden
    end

    test "validates updated configuration" do
      assert {:error, error} = ConfigServer.update([:ai, :planning, :sampling_rate], 2.0)
      assert error.error_type == :range_error
    end
  end

  describe "reset/0" do
    test "resets configuration to defaults" do
      # First update something
      :ok = ConfigServer.update([:dev, :debug_mode], true)
      assert {:ok, true} = ConfigServer.get([:dev, :debug_mode])

      # Then reset
      assert :ok = ConfigServer.reset()
      assert {:ok, false} = ConfigServer.get([:dev, :debug_mode])
    end
  end

  describe "state isolation" do
    test "each test starts with clean state" do
      # This test verifies that state doesn't leak between tests
      # First, verify default state
      assert {:ok, false} = ConfigServer.get([:dev, :debug_mode])

      # Update something
      :ok = ConfigServer.update([:dev, :debug_mode], true)
      assert {:ok, true} = ConfigServer.get([:dev, :debug_mode])

      # The next test should start fresh due to our setup/teardown
    end

    test "state reset works correctly" do
      # Update configuration
      :ok = ConfigServer.update([:dev, :debug_mode], true)
      assert {:ok, true} = ConfigServer.get([:dev, :debug_mode])

      # Reset state manually
      :ok = ConfigServer.reset_state()

      # Should be back to defaults
      assert {:ok, false} = ConfigServer.get([:dev, :debug_mode])
    end
  end

  describe "subscription mechanism" do
    test "notifies subscribers of configuration changes" do
      # Subscribe to notifications
      :ok = ConfigServer.subscribe()

      # Update configuration
      :ok = ConfigServer.update([:dev, :debug_mode], true)

      # Should receive notification
      assert_receive {:config_notification, {:config_updated, [:dev, :debug_mode], true}}, 1000
    end

    test "handles subscriber process death" do
      # Start a process that subscribes and then dies
      test_pid = self()

      subscriber_pid =
        spawn(fn ->
          # In test mode, we need to set the test process context to find the right server
          Process.put(:foundation_test_process, test_pid)

          result = ConfigServer.subscribe()

          case result do
            :ok -> send(test_pid, :subscribed)
            {:error, _} -> send(test_pid, :subscription_failed)
          end

          receive do
            :die -> exit(:normal)
          after
            5000 -> exit(:timeout)
          end
        end)

      # Wait for subscription
      assert_receive :subscribed, 1000

      # Kill the subscriber
      send(subscriber_pid, :die)
      # Give time for cleanup
      Process.sleep(50)

      # Update configuration - should not crash the server
      assert :ok = ConfigServer.update([:dev, :debug_mode], true)
    end
  end

  describe "available?/0" do
    test "returns true when server is running" do
      assert ConfigServer.available?()
    end
  end

  describe "service management" do
    test "can check service status" do
      assert {:ok, status} = ConfigServer.status()
      assert status.status == :running
      assert is_integer(status.uptime_ms)
      assert status.uptime_ms >= 0
    end

    test "reset_state only works in test mode" do
      # Should work since we're in test mode
      assert :ok = ConfigServer.reset_state()

      # Temporarily disable test mode
      Application.put_env(:foundation, :test_mode, false)

      assert {:error, error} = ConfigServer.reset_state()
      assert error.error_type == :operation_forbidden

      # Re-enable test mode
      Application.put_env(:foundation, :test_mode, true)
    end
  end
end

# defmodule Foundation.Services.ConfigServerTest do
#   use ExUnit.Case, async: false

#   alias Foundation.Services.ConfigServer
#   alias Foundation.Logic.ConfigLogic
#   alias Foundation.Types.{Config, Error}
#   alias Foundation.{Events, Telemetry}

#   setup do
#     # Start ConfigServer for testing
#     {:ok, pid} = GenServer.start_link(ConfigServer, [], name: :test_config_server)

#     on_exit(fn ->
#       if Process.alive?(pid) do
#         GenServer.stop(pid, :normal)
#       end
#     end)

#     %{server: :test_config_server}
#   end

#   describe "initialization" do
#     test "ConfigServer.init/1 logs successful initialization" do
#       # Capture logs
#       import ExUnit.CaptureLog

#       log = capture_log(fn ->
#         {:ok, _state} = ConfigServer.init([])
#       end)

#       assert log =~ "ConfigServer initialized successfully"
#     end

#     test "ConfigServer.init/1 fails and stops if ConfigLogic.build_config returns an error" do
#       # Mock ConfigLogic.build_config to return an error
#       # Note: This would require mocking in a real implementation
#       # For now, we'll test the happy path and document the expected behavior

#       # Normal initialization should succeed
#       assert {:ok, state} = ConfigServer.init([])
#       assert %{config: %Config{}} = state
#       assert is_map(state.subscribers)
#     end
#   end

#   describe "handle_call/3 - config operations" do
#     test "handle_call({:get_config_path, valid_path_to_nil_value}, ...) returns {:ok, nil}", %{server: server} do
#       # First set up a config path that resolves to nil
#       {:ok, _} = GenServer.call(server, {:update_config, [:telemetry, :nonexistent_key], nil})

#       # Now get that path
#       result = GenServer.call(server, {:get_config_path, [:telemetry, :nonexistent_key]})
#       assert {:ok, nil} == result
#     end

#     test "handle_call({:update_config, ...}) when ConfigLogic.update_config errors, replies with error and state is unchanged", %{server: server} do
#       # Get initial state
#       {:ok, initial_config} = GenServer.call(server, :get_config)

#       # Try to update with invalid data
#       result = GenServer.call(server, {:update_config, [:invalid_section, :invalid_key], "invalid"})
#       assert {:error, %Error{}} = result

#       # Verify state is unchanged
#       {:ok, current_config} = GenServer.call(server, :get_config)
#       assert initial_config == current_config
#     end

#     test "handle_call(:reset_config, ...) updates state to ConfigLogic.reset_config()", %{server: server} do
#       # First make some changes
#       {:ok, _} = GenServer.call(server, {:update_config, [:telemetry, :enable_vm_metrics], false})

#       # Reset config
#       result = GenServer.call(server, :reset_config)
#       assert :ok == result

#       # Verify config was reset to default
#       {:ok, config} = GenServer.call(server, :get_config)
#       default_config = Config.new()
#       assert config.telemetry.enable_vm_metrics == default_config.telemetry.enable_vm_metrics
#     end

#     test "handle_call(:reset_config, ...) notifies subscribers with {:config_reset, new_config}", %{server: server} do
#       # Subscribe to notifications
#       GenServer.call(server, {:subscribe, self()})

#       # Reset config
#       :ok = GenServer.call(server, :reset_config)

#       # Check for notification
#       assert_receive {:config_reset, %Config{}}
#     end

#     test "handle_call(:reset_config, ...) emits config_reset event and telemetry", %{server: server} do
#       # Initialize the event store and telemetry service
#       {:ok, _} = GenServer.start_link(Foundation.Services.EventStore, [], name: Foundation.EventStore)
#       {:ok, _} = GenServer.start_link(Foundation.Services.TelemetryService, [], name: Foundation.TelemetryService)

#       # Reset config
#       :ok = GenServer.call(server, :reset_config)

#       # Check that events and telemetry were emitted
#       # Note: This would require checking the actual EventStore and TelemetryService
#       # For now, we verify the call completes successfully
#       assert true
#     end

#     test "handle_call(:get_metrics, ...) returns a map including :current_time", %{server: server} do
#       result = GenServer.call(server, :get_metrics)
#       assert {:ok, metrics} = result
#       assert is_map(metrics)
#       assert Map.has_key?(metrics, :current_time)
#       assert Map.has_key?(metrics, :subscriber_count)
#     end
#   end

#   describe "handle_info/2 - process monitoring" do
#     test "handle_info({:DOWN, ref, :process, pid, reason}, state) removes pid from state.subscribers", %{server: server} do
#       # Subscribe a process
#       test_pid = spawn(fn -> Process.sleep(1000) end)
#       GenServer.call(server, {:subscribe, test_pid})

#       # Kill the process
#       Process.exit(test_pid, :kill)

#       # Wait for the DOWN message to be processed
#       Process.sleep(50)

#       # Verify the subscriber was removed
#       {:ok, metrics} = GenServer.call(server, :get_metrics)
#       assert metrics.subscriber_count == 0
#     end
#   end

#   describe "private helper functions" do
#     test "emit_config_event correctly uses Foundation.Events.new_event/2" do
#       # Start the EventStore
#       {:ok, _} = GenServer.start_link(Foundation.Services.EventStore, [], name: Foundation.EventStore)

#       # This tests the internal function indirectly through a config update
#       result = GenServer.call(:test_config_server, {:update_config, [:telemetry, :enable_vm_metrics], false})
#       assert {:ok, _} = result

#       # Verify event was stored (indirectly)
#       {:ok, events} = Events.query(%{event_type: :config_updated})
#       assert length(events) >= 0  # Should have at least one event
#     end

#     test "emit_config_telemetry uses correct event names for TelemetryService" do
#       # Start the TelemetryService
#       {:ok, _} = GenServer.start_link(Foundation.Services.TelemetryService, [], name: Foundation.TelemetryService)

#       # This tests the internal function indirectly through a config update
#       result = GenServer.call(:test_config_server, {:update_config, [:telemetry, :enable_vm_metrics], true})
#       assert {:ok, _} = result

#       # Verify telemetry was emitted (indirectly)
#       {:ok, metrics} = Telemetry.get_metrics()
#       assert is_map(metrics)
#     end

#     test "create_service_error/1 creates an Error.t with specified severity and category" do
#       # This tests the error creation indirectly through an error scenario
#       result = GenServer.call(:test_config_server, {:update_config, [:nonexistent, :path], "value"})
#       assert {:error, %Error{} = error} = result
#       assert error.category == :config
#       assert error.severity in [:error, :warning, :info]
#     end
#   end

#   describe "subscription management" do
#     test "subscribe adds process to subscribers and monitors it", %{server: server} do
#       initial_metrics = GenServer.call(server, :get_metrics)
#       initial_count = initial_metrics[:subscriber_count] || 0

#       # Subscribe current process
#       result = GenServer.call(server, {:subscribe, self()})
#       assert :ok == result

#       # Check subscriber count increased
#       {:ok, metrics} = GenServer.call(server, :get_metrics)
#       assert metrics.subscriber_count == initial_count + 1
#     end

#     test "unsubscribe removes process from subscribers", %{server: server} do
#       # Subscribe first
#       :ok = GenServer.call(server, {:subscribe, self()})

#       # Unsubscribe
#       result = GenServer.call(server, {:unsubscribe, self()})
#       assert :ok == result

#       # Check subscriber count decreased
#       {:ok, metrics} = GenServer.call(server, :get_metrics)
#       assert metrics.subscriber_count == 0
#     end

#     test "subscribers receive notifications on config updates", %{server: server} do
#       # Subscribe
#       :ok = GenServer.call(server, {:subscribe, self()})

#       # Update config
#       {:ok, _} = GenServer.call(server, {:update_config, [:telemetry, :enable_vm_metrics], false})

#       # Check for notification
#       assert_receive {:config_updated, %{path: [:telemetry, :enable_vm_metrics], old_value: _, new_value: false}}
#     end
#   end

#   describe "error handling and edge cases" do
#     test "handles updatable_paths correctly" do
#       result = GenServer.call(:test_config_server, :get_updatable_paths)
#       assert {:ok, paths} = result
#       assert is_list(paths)
#       # Should include some known updatable paths
#       assert Enum.any?(paths, fn path -> path == [:telemetry, :enable_vm_metrics] end)
#     end

#     test "validates paths before updates" do
#       # Try to update a non-updatable path
#       result = GenServer.call(:test_config_server, {:update_config, [:system, :node_name], "new_name"})
#       assert {:error, %Error{error_type: :config_update_forbidden}} = result
#     end

#     test "handles concurrent updates safely" do
#       # Start multiple update tasks concurrently
#       tasks = for i <- 1..5 do
#         Task.async(fn ->
#           GenServer.call(:test_config_server, {:update_config, [:telemetry, :enable_vm_metrics], rem(i, 2) == 0})
#         end)
#       end

#       # Wait for all tasks to complete
#       results = Task.await_many(tasks)

#       # All should succeed (or fail predictably)
#       assert Enum.all?(results, fn
#         {:ok, _} -> true
#         {:error, %Error{}} -> true
#         _ -> false
#       end)
#     end
#   end
# end
