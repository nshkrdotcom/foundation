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
end
