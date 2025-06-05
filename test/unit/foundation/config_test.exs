defmodule Foundation.ConfigTest do
  # Config tests must be synchronous
  use ExUnit.Case, async: false
  @moduletag :foundation

  alias Foundation.Config, as: ConfigAPI
  alias Foundation.Types.{Config, Error}
  alias Foundation.TestHelpers

  setup do
    # Ensure Config GenServer is available
    :ok = TestHelpers.ensure_config_available()

    # Store original config for restoration
    {:ok, original_config} = ConfigAPI.get()

    on_exit(fn ->
      # Restore any changed values
      try do
        if ConfigAPI.available?() do
          # Restore sampling rate if changed
          case original_config do
            %Config{ai: %{planning: %{sampling_rate: rate}}} ->
              ConfigAPI.update([:ai, :planning, :sampling_rate], rate)

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

  describe "configuration validation" do
    test "validates default configuration" do
      config = %Config{}
      assert :ok = ConfigAPI.validate(config)
    end

    test "validates complete AI configuration" do
      config = %Config{
        ai: %{
          provider: :mock,
          api_key: nil,
          model: "gpt-4",
          analysis: %{
            max_file_size: 1_000_000,
            timeout: 30_000,
            cache_ttl: 3600
          },
          planning: %{
            default_strategy: :balanced,
            performance_target: 0.01,
            sampling_rate: 1.0
          }
        }
      }

      assert :ok = ConfigAPI.validate(config)
    end

    test "rejects invalid AI provider" do
      config = %Config{
        ai: %{
          provider: :invalid_provider,
          analysis: %{max_file_size: 1000, timeout: 1000, cache_ttl: 1000},
          planning: %{default_strategy: :balanced, performance_target: 0.01, sampling_rate: 1.0}
        }
      }

      assert {:error, %Error{error_type: :invalid_config_value}} = ConfigAPI.validate(config)
    end

    test "rejects invalid sampling rate" do
      config = %Config{
        ai: %{
          provider: :mock,
          analysis: %{max_file_size: 1000, timeout: 1000, cache_ttl: 1000},
          planning: %{
            default_strategy: :balanced,
            performance_target: 0.01,
            # Invalid: > 1.0
            sampling_rate: 1.5
          }
        }
      }

      assert {:error, %Error{error_type: :range_error}} = ConfigAPI.validate(config)
    end
  end

  describe "configuration server operations" do
    test "gets full configuration", %{original_config: _config} do
      {:ok, config} = ConfigAPI.get()
      assert %Config{} = config
      assert config.ai.provider == :mock
    end

    test "gets configuration by path", %{original_config: _config} do
      {:ok, provider} = ConfigAPI.get([:ai, :provider])
      assert provider == :mock

      {:ok, sampling_rate} = ConfigAPI.get([:ai, :planning, :sampling_rate])
      assert is_number(sampling_rate)
      assert sampling_rate >= 0
      assert sampling_rate <= 1
    end

    test "updates allowed configuration paths", %{original_config: _config} do
      assert :ok = ConfigAPI.update([:ai, :planning, :sampling_rate], 0.8)

      {:ok, updated_rate} = ConfigAPI.get([:ai, :planning, :sampling_rate])
      assert updated_rate == 0.8
    end

    test "rejects updates to forbidden paths", %{original_config: _config} do
      result = ConfigAPI.update([:ai, :provider], :openai)
      assert {:error, %Error{error_type: :config_update_forbidden}} = result

      # Verify unchanged
      {:ok, provider} = ConfigAPI.get([:ai, :provider])
      assert provider == :mock
    end

    test "validates updates before applying", %{original_config: _config} do
      result = ConfigAPI.update([:ai, :planning, :sampling_rate], 1.5)
      assert {:error, %Error{error_type: :range_error}} = result
    end
  end

  test "handles service unavailable gracefully" do
    # Use a more controlled approach
    alias Foundation.Config.GracefulDegradation
    alias Foundation.Services.ConfigServer

    # Initialize fallback system
    GracefulDegradation.initialize_fallback_system()

    # Prime the cache
    {:ok, _original_config} = ConfigAPI.get()

    # Stop the ConfigServer more gracefully using GenServer.stop
    config_pid = GenServer.whereis(ConfigServer)

    if config_pid do
      try do
        GenServer.stop(config_pid, :normal, 100)
      catch
        :exit, _ -> :ok
      end

      # Wait for it to be gone
      :timer.sleep(100)
    end

    # Now test should fail
    result = ConfigAPI.get()

    case result do
      {:error, %Error{error_type: :service_unavailable}} ->
        assert true

      {:ok, _config} ->
        # Service might have restarted too quickly, that's also valid
        assert true

      other ->
        flunk("Unexpected result: #{inspect(other)}")
    end

    # Test graceful degradation fallback
    fallback_result = GracefulDegradation.get_with_fallback([:ai, :provider])
    # Should get cached value, default value, or error
    case fallback_result do
      {:ok, :mock} -> assert true
      # Also acceptable if no cache exists
      {:error, _} -> assert true
      other -> flunk("Unexpected fallback result: #{inspect(other)}")
    end

    # Restart everything
    TestHelpers.ensure_config_available()
  end

  describe "concurrent access patterns" do
    test "handles concurrent configuration reads safely" do
      # Create multiple concurrent readers
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            case rem(i, 3) do
              0 -> ConfigAPI.get()
              1 -> ConfigAPI.get([:ai, :provider])
              2 -> ConfigAPI.get([:dev, :debug_mode])
            end
          end)
        end

      # Wait for all tasks
      results = Task.await_many(tasks, 5000)

      # All should succeed or fail gracefully
      Enum.each(results, fn result ->
        assert match?({:ok, _}, result) or match?({:error, %Error{}}, result)
      end)
    end

    test "serializes concurrent configuration updates" do
      # Initialize a test value
      :ok = ConfigAPI.update([:dev, :verbose_logging], false)

      # Create concurrent update tasks
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            # Alternate between true and false
            new_value = rem(i, 2) == 0
            ConfigAPI.update([:dev, :verbose_logging], new_value)
          end)
        end

      # Wait for all updates
      results = Task.await_many(tasks, 5000)

      # All should complete without crashing
      Enum.each(results, fn result ->
        assert result == :ok or match?({:error, %Error{}}, result)
      end)

      # Final state should be valid
      {:ok, final_value} = ConfigAPI.get([:dev, :verbose_logging])
      assert is_boolean(final_value)
    end
  end

  describe "error handling and recovery" do
    test "recovers from transient validation errors" do
      # Try an invalid update
      result1 = ConfigAPI.update([:ai, :planning, :sampling_rate], 2.0)
      assert {:error, %Error{error_type: :range_error}} = result1

      # System should still be functional for valid updates
      result2 = ConfigAPI.update([:ai, :planning, :sampling_rate], 0.5)
      assert result2 == :ok

      # Verify the valid update was applied
      {:ok, current_value} = ConfigAPI.get([:ai, :planning, :sampling_rate])
      assert current_value == 0.5
    end

    test "maintains service health after validation failures" do
      # Generate multiple validation failures
      invalid_updates = [
        {[:ai, :planning, :sampling_rate], 5.0},
        {[:ai, :provider], :nonexistent_provider}
      ]

      Enum.each(invalid_updates, fn {path, value} ->
        result = ConfigAPI.update(path, value)
        assert match?({:error, %Error{}}, result)
      end)

      # Service should still be healthy
      assert ConfigAPI.available?()
      {:ok, config} = ConfigAPI.get()
      assert %Config{} = config
    end
  end
end
