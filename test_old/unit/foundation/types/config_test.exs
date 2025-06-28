defmodule Foundation.Types.ConfigTest do
  use ExUnit.Case, async: true

  alias Foundation.Types.Config

  describe "new/0" do
    test "creates config with default values" do
      config = Config.new()

      assert config.ai.provider == :mock
      assert config.capture.ring_buffer.size == 1024
      assert config.storage.hot.max_events == 100_000
      assert config.interface.query_timeout == 10_000
      assert config.dev.debug_mode == false
    end
  end

  describe "new/1" do
    test "creates config with overrides" do
      config = Config.new(ai: %{provider: :openai}, dev: %{debug_mode: true})

      assert config.ai.provider == :openai
      assert config.dev.debug_mode == true
      # Defaults should still be present
      assert config.capture.ring_buffer.size == 1024
    end
  end

  describe "Access behavior" do
    test "supports get operation" do
      config = Config.new()

      assert config[:ai][:provider] == :mock
      assert config[:dev][:debug_mode] == false
    end

    test "supports update operation" do
      config = Config.new()
      updated = put_in(config, [:dev, :debug_mode], true)

      assert updated.dev.debug_mode == true
      # Original unchanged
      assert config.dev.debug_mode == false
    end

    test "supports get_and_update operation" do
      config = Config.new()

      {old_value, new_config} =
        get_and_update_in(config, [:dev, :debug_mode], fn
          current -> {current, not current}
        end)

      assert old_value == false
      assert new_config.dev.debug_mode == true
    end
  end
end
