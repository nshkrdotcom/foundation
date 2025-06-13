defmodule Foundation.Logic.ConfigLogicTest do
  use ExUnit.Case, async: true

  alias Foundation.Types.Config
  alias Foundation.Logic.ConfigLogic

  describe "updatable_paths/0" do
    test "returns list of updatable configuration paths" do
      paths = ConfigLogic.updatable_paths()

      assert is_list(paths)
      assert [:ai, :planning, :sampling_rate] in paths
      assert [:dev, :debug_mode] in paths
      # Not updatable at runtime
      refute [:ai, :provider] in paths
    end
  end

  describe "updatable_path?/1" do
    test "returns true for updatable paths" do
      assert ConfigLogic.updatable_path?([:dev, :debug_mode])
      assert ConfigLogic.updatable_path?([:ai, :planning, :sampling_rate])
    end

    test "returns false for non-updatable paths" do
      refute ConfigLogic.updatable_path?([:ai, :provider])
      refute ConfigLogic.updatable_path?([:storage, :hot, :max_events])
    end
  end

  describe "update_config/3" do
    test "updates valid configuration path" do
      config = Config.new()

      assert {:ok, updated_config} = ConfigLogic.update_config(config, [:dev, :debug_mode], true)
      assert updated_config.dev.debug_mode == true
    end

    test "rejects update to non-updatable path" do
      config = Config.new()

      assert {:error, error} = ConfigLogic.update_config(config, [:ai, :provider], :openai)
      assert error.error_type == :config_update_forbidden
    end

    test "validates updated configuration" do
      config = Config.new()

      # Try to set invalid sampling rate
      assert {:error, error} =
               ConfigLogic.update_config(config, [:ai, :planning, :sampling_rate], 2.0)

      assert error.error_type == :range_error
    end
  end

  describe "get_config_value/2" do
    test "returns configuration value for valid path" do
      config = Config.new()

      assert {:ok, :mock} = ConfigLogic.get_config_value(config, [:ai, :provider])
      assert {:ok, false} = ConfigLogic.get_config_value(config, [:dev, :debug_mode])
    end

    test "returns entire config for empty path" do
      config = Config.new()

      assert {:ok, ^config} = ConfigLogic.get_config_value(config, [])
    end

    test "returns error for invalid path" do
      config = Config.new()

      assert {:error, error} = ConfigLogic.get_config_value(config, [:nonexistent, :path])
      assert error.error_type == :config_path_not_found
    end

    test "handles mid-path termination on non-map values gracefully" do
      # This test reproduces DSPEx defensive code scenario - Test Case 4
      # Trying to access a key inside a non-map value should not crash
      config = Config.new()

      # First set debug_mode to a boolean value
      {:ok, updated_config} = ConfigLogic.update_config(config, [:dev, :debug_mode], true)

      # Now try to access a nested key inside the boolean value
      # This should return :config_path_not_found, not crash
      assert {:error, error} =
               ConfigLogic.get_config_value(updated_config, [:dev, :debug_mode, :nested_key])

      assert error.error_type == :config_path_not_found
      assert String.contains?(error.message, "Configuration path not found")

      # Test with integer value as well
      {:ok, updated_config2} =
        ConfigLogic.update_config(config, [:ai, :planning, :sampling_rate], 0.5)

      assert {:error, error2} =
               ConfigLogic.get_config_value(updated_config2, [
                 :ai,
                 :planning,
                 :sampling_rate,
                 :sub_key
               ])

      assert error2.error_type == :config_path_not_found
    end
  end

  describe "merge_env_config/2" do
    test "merges environment configuration" do
      config = Config.new()

      env_config = [
        ai: [provider: :openai],
        dev: [debug_mode: true]
      ]

      merged = ConfigLogic.merge_env_config(config, env_config)

      assert merged.ai.provider == :openai
      assert merged.dev.debug_mode == true
      # Other defaults should remain
      assert merged.capture.ring_buffer.size == 1024
    end
  end

  describe "diff_configs/2" do
    test "creates diff between configurations" do
      config1 = Config.new()
      config2 = Config.new(dev: %{debug_mode: true}, ai: %{provider: :openai})

      diff = ConfigLogic.diff_configs(config1, config2)

      assert Map.has_key?(diff, :dev)
      assert Map.has_key?(diff, :ai)
      # Unchanged
      refute Map.has_key?(diff, :capture)
    end

    test "returns empty diff for identical configs" do
      config = Config.new()

      diff = ConfigLogic.diff_configs(config, config)

      assert diff == %{}
    end
  end
end
