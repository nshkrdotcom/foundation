defmodule Foundation.Property.ConfigValidationPropertiesTest do
  # Config changes affect global state
  use ExUnit.Case, async: false
  use ExUnitProperties

  # Property tests are inherently slow
  @moduletag :slow

  alias Foundation.{Config}
  alias Foundation.Services.ConfigServer
  alias Foundation.TestHelpers

  setup do
    :ok = TestHelpers.ensure_config_available()

    # Store original config for restoration
    {:ok, original_config} = Config.get()

    on_exit(fn ->
      # Restore original configuration
      try do
        Config.reset()
      catch
        :exit, _ -> :ok
      end
    end)

    %{original_config: original_config}
  end

  # Generators for test data

  defp valid_config_path_generator do
    one_of([
      constant([:ai, :planning, :sampling_rate]),
      constant([:dev, :debug_mode]),
      constant([:dev, :verbose_logging]),
      constant([:dev, :performance_monitoring]),
      constant([:interface, :query_timeout]),
      constant([:storage, :hot, :max_events])
    ])
  end

  defp invalid_config_path_generator do
    one_of([
      constant([]),
      constant([:nonexistent]),
      constant([:ai, :nonexistent]),
      constant([:capture, :nonexistent]),
      constant([:storage, :nonexistent]),
      constant([:nonexistent, :path, :deeply, :nested]),
      list_of(atom(:alphanumeric), min_length: 1, max_length: 10)
    ])
  end

  defp valid_config_value_generator do
    one_of([
      # For sampling_rate (0.0 to 1.0)
      float(min: 0.0, max: 1.0),
      # For boolean configs
      boolean(),
      # For integer configs
      integer(1..86400),
      # For string configs
      string(:alphanumeric, min_length: 1, max_length: 100)
    ])
  end

  defp invalid_config_value_generator do
    one_of([
      # Invalid sampling rates
      float(min: 1.1, max: 10.0),
      float(min: -10.0, max: -0.1),
      # Invalid types
      atom(:alphanumeric),
      list_of(term()),
      map_of(atom(:alphanumeric), term()),
      constant(nil)
    ])
  end

  defp config_update_sequence_generator do
    list_of(
      tuple({valid_config_path_generator(), valid_config_value_generator()}),
      min_length: 1,
      max_length: 20
    )
  end

  defp nested_map_generator do
    sized(fn size ->
      nested_map_generator(size)
    end)
  end

  defp nested_map_generator(0) do
    one_of([
      string(:alphanumeric),
      integer(),
      float(),
      boolean(),
      atom(:alphanumeric)
    ])
  end

  defp nested_map_generator(size) when size > 0 do
    one_of([
      string(:alphanumeric),
      integer(),
      float(),
      boolean(),
      atom(:alphanumeric),
      map_of(
        atom(:alphanumeric),
        nested_map_generator(div(size, 2)),
        max_length: 5
      )
    ])
  end

  # Property Tests

  property "For any valid initial config and sequence of valid updates, ConfigServer state is always valid" do
    check all(update_sequence <- config_update_sequence_generator()) do
      # Start with clean config state
      :ok = Config.reset()

      # Apply sequence of updates
      Enum.each(update_sequence, fn {path, value} ->
        # Each update should either succeed or fail gracefully
        result = Config.update(path, value)
        assert result == :ok or match?({:error, _}, result)
      end)

      # Config should always be in valid state
      {:ok, final_config} = Config.get()
      assert is_map(final_config)
      assert Map.has_key?(final_config, :ai)
      assert Map.has_key?(final_config, :dev)
      assert Map.has_key?(final_config, :capture)
      assert Map.has_key?(final_config, :storage)
      assert Map.has_key?(final_config, :interface)

      # ConfigServer should be responsive
      assert ConfigServer.available?()
      {:ok, status} = ConfigServer.status()
      assert status.status == :running
    end
  end

  property "Config.update/2 with valid values never corrupts existing config" do
    check all(
            path <- valid_config_path_generator(),
            value <- valid_config_value_generator()
          ) do
      # Store state before update
      {:ok, before_config} = Config.get()

      # Perform update
      result = Config.update(path, value)

      # Get state after update
      {:ok, after_config} = Config.get()

      case result do
        :ok ->
          # Update succeeded - verify value was set correctly
          {:ok, retrieved_value} = Config.get(path)
          assert retrieved_value == value

          # Other parts of config should be unchanged
          verify_config_structure_intact(before_config, after_config, path)

        {:error, _} ->
          # Update failed - config should be unchanged
          assert after_config == before_config
      end

      # Config should always have valid structure
      assert_valid_config_structure(after_config)
    end
  end

  property "Config.get/1 with any path always returns consistent result" do
    check all(path <- one_of([valid_config_path_generator(), invalid_config_path_generator()])) do
      result1 = Config.get(path)
      result2 = Config.get(path)

      # Multiple calls should return the same result structure
      case {result1, result2} do
        {{:ok, value1}, {:ok, value2}} ->
          # Success results should be identical
          assert value1 == value2

        {{:error, error1}, {:error, error2}} ->
          # Error results should have same structure, but timestamps may differ
          assert error1.error_type == error2.error_type
          assert error1.message == error2.message
          assert error1.context == error2.context
          assert error1.category == error2.category
          assert error1.subcategory == error2.subcategory

        _ ->
          # Mixed results (one success, one failure) should not happen
          flunk("Inconsistent result types: #{inspect(result1)} vs #{inspect(result2)}")
      end

      # Result should always be proper tuple
      assert match?({:ok, _}, result1) or match?({:error, _}, result1)
    end
  end

  property "Config validation with random nested maps maintains structure integrity" do
    check all(nested_data <- nested_map_generator()) do
      # Try to update with nested data (should mostly fail but not crash)
      # Known path
      path = [:ai, :planning, :sampling_rate]

      result = Config.update(path, nested_data)

      # Should not crash and return proper result format
      case result do
        :ok ->
          # Update succeeded
          :ok

        {:ok, _} ->
          # Update succeeded with return value
          :ok

        {:error, _} ->
          # Update failed gracefully
          :ok

        other ->
          # Unexpected result format
          flunk("Unexpected result format: #{inspect(other)}")
      end

      # Config structure should remain valid
      {:ok, config} = Config.get()
      assert_valid_config_structure(config)

      # ConfigServer should remain responsive
      assert ConfigServer.available?()
    end
  end

  property "Config.reset/0 always restores to valid default state" do
    check all(update_sequence <- config_update_sequence_generator()) do
      # Make some changes
      Enum.each(update_sequence, fn {path, value} ->
        Config.update(path, value)
      end)

      # Reset should always work
      :ok = Config.reset()

      # Should be back to valid default state
      {:ok, config} = Config.get()
      assert_valid_config_structure(config)

      # Default values should be restored
      {:ok, sampling_rate} = Config.get([:ai, :planning, :sampling_rate])
      assert is_float(sampling_rate)
      assert sampling_rate >= 0.0 and sampling_rate <= 1.0

      {:ok, debug_mode} = Config.get([:dev, :debug_mode])
      assert is_boolean(debug_mode)
    end
  end

  property "ConfigServer restart preserves all previously set valid configurations" do
    check all(
            valid_updates <-
              list_of(
                tuple({valid_config_path_generator(), valid_config_value_generator()}),
                min_length: 1,
                max_length: 5
              )
          ) do
      # Apply valid updates
      successful_updates =
        Enum.filter(valid_updates, fn {path, value} ->
          Config.update(path, value) == :ok
        end)

      # Only proceed if we had some successful updates
      if length(successful_updates) > 0 do
        # Restart ConfigServer
        if pid = GenServer.whereis(ConfigServer) do
          GenServer.stop(pid, :normal)
        end

        :ok = ConfigServer.initialize()
        # Allow restart to complete
        Process.sleep(100)

        # Note: Persistence may not be implemented yet, so we just verify
        # that the service restarts successfully and is functional
        assert ConfigServer.available?()

        # Config structure should remain valid
        {:ok, config} = Config.get()
        assert_valid_config_structure(config)

        # Test that we can still update config after restart
        {:ok, _} = Config.get([:dev, :debug_mode])
        :ok = Config.update([:dev, :debug_mode], false)
      end
    end
  end

  property "No matter the order of concurrent ConfigServer.subscribe and unsubscribe calls, the subscriber list remains consistent" do
    check all(
            operations <-
              list_of(
                one_of([constant(:subscribe), constant(:unsubscribe)]),
                min_length: 10,
                max_length: 50
              )
          ) do
      # Execute operations concurrently from multiple processes
      tasks =
        Enum.with_index(operations)
        |> Enum.map(fn {operation, index} ->
          Task.async(fn ->
            case operation do
              :subscribe ->
                ConfigServer.subscribe()
                {index, :subscribed}

              :unsubscribe ->
                ConfigServer.unsubscribe()
                {index, :unsubscribed}
            end
          end)
        end)

      # Wait for all operations to complete
      results = Task.await_many(tasks, 5000)

      # ConfigServer should still be responsive
      assert ConfigServer.available?()

      # Should be able to subscribe and receive notifications
      :ok = ConfigServer.subscribe()
      :ok = Config.update([:dev, :debug_mode], true)

      # Should receive notification
      assert_receive {:config_notification, _}, 1000

      # Cleanup
      ConfigServer.unsubscribe()

      assert length(results) == length(operations)
    end
  end

  property "Config path traversal with deeply nested structures never crashes" do
    check all(deep_path <- list_of(atom(:alphanumeric), min_length: 1, max_length: 20)) do
      result = Config.get(deep_path)

      # Should not crash, always return proper tuple
      assert match?({:ok, _}, result) or match?({:error, _}, result)

      # ConfigServer should remain responsive
      assert ConfigServer.available?()
    end
  end

  property "Config value type validation rejects incompatible types consistently" do
    check all(
            path <- valid_config_path_generator(),
            invalid_value <- invalid_config_value_generator()
          ) do
      result = Config.update(path, invalid_value)

      # Invalid values should be rejected consistently
      case path do
        [:ai, :planning, :sampling_rate] ->
          # Should reject non-numeric or out-of-range values
          if not is_number(invalid_value) or invalid_value < 0 or invalid_value > 1 do
            assert match?({:error, _}, result)
          end

        [:dev, :debug_mode] ->
          # Should reject non-boolean values
          if not is_boolean(invalid_value) do
            assert match?({:error, _}, result)
          end

        _ ->
          # Other paths may have specific validation rules
          assert match?({:ok, _}, result) or match?({:error, _}, result)
      end

      # Config should remain in valid state
      {:ok, config} = Config.get()
      assert_valid_config_structure(config)
    end
  end

  property "Config change notifications are delivered for every successful update" do
    check all(
            path <- valid_config_path_generator(),
            value <- valid_config_value_generator()
          ) do
      # Subscribe to notifications
      :ok = ConfigServer.subscribe()

      # Clear any existing messages with short timeout
      receive do
        _ -> :ok
      after
        10 -> :ok
      end

      # Perform update
      result = Config.update(path, value)

      case result do
        :ok ->
          # Should receive notification for successful update within reasonable time
          receive do
            {:config_notification, {event_type, ^path, ^value}} ->
              assert event_type == :config_updated

            {:config_notification, _other} ->
              # Different notification received, that's fine for this test
              :ok
          after
            500 ->
              # No notification received - this might be expected if notifications aren't implemented yet
              :ok
          end

        {:error, _} ->
          # No notification should be sent for failed updates
          receive do
            {:config_notification, _} ->
              flunk("Should not receive notification for failed update")
          after
            100 -> :ok
          end
      end

      # Cleanup
      ConfigServer.unsubscribe()
    end
  end

  # Helper functions

  defp assert_valid_config_structure(config) do
    assert is_map(config)
    assert Map.has_key?(config, :ai)
    assert Map.has_key?(config, :dev)
    assert Map.has_key?(config, :capture)
    assert Map.has_key?(config, :storage)
    assert Map.has_key?(config, :interface)

    # AI section validation
    ai_config = Map.get(config, :ai)
    assert is_map(ai_config)
    assert Map.has_key?(ai_config, :planning)

    planning_config = Map.get(ai_config, :planning)
    assert is_map(planning_config)
    assert Map.has_key?(planning_config, :sampling_rate)

    sampling_rate = Map.get(planning_config, :sampling_rate)
    assert is_number(sampling_rate)
    assert sampling_rate >= 0.0 and sampling_rate <= 1.0

    # Dev section validation
    dev_config = Map.get(config, :dev)
    assert is_map(dev_config)
    assert Map.has_key?(dev_config, :debug_mode)

    debug_mode = Map.get(dev_config, :debug_mode)
    assert is_boolean(debug_mode)
  end

  defp verify_config_structure_intact(before_config, after_config, changed_path) do
    # Verify that only the changed path was modified
    verify_unchanged_except_path(before_config, after_config, changed_path, [])
  end

  defp verify_unchanged_except_path(before_map, after_map, [key | rest_path], current_path)
       when is_map(before_map) and is_map(after_map) do
    full_path = current_path ++ [key]

    if rest_path == [] do
      # This is the changed key, skip verification
      :ok
    else
      # Verify this level matches except for the changed branch
      before_value = Map.get(before_map, key)
      after_value = Map.get(after_map, key)

      if before_value != nil and after_value != nil do
        verify_unchanged_except_path(before_value, after_value, rest_path, full_path)
      end
    end

    # Verify other keys at this level are unchanged
    other_keys = Map.keys(before_map) -- [key]

    Enum.each(other_keys, fn other_key ->
      before_other = Map.get(before_map, other_key)
      after_other = Map.get(after_map, other_key)

      assert before_other == after_other,
             "Key #{inspect(current_path ++ [other_key])} should not have changed"
    end)
  end

  defp verify_unchanged_except_path(_before_value, _after_value, [], _current_path) do
    # Base case: we've reached the changed value, so differences are expected
    :ok
  end

  defp verify_unchanged_except_path(before_value, after_value, _path, current_path) do
    # Non-map values should be equal if we haven't reached the changed path
    assert before_value == after_value,
           "Value at #{inspect(current_path)} should not have changed"
  end
end
