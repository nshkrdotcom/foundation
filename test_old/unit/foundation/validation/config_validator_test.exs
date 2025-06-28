defmodule Foundation.Validation.ConfigValidatorTest do
  use ExUnit.Case, async: true

  alias Foundation.Types.Config
  alias Foundation.Validation.ConfigValidator

  describe "validate/1" do
    test "validates correct configuration" do
      config = Config.new()

      assert :ok = ConfigValidator.validate(config)
    end

    test "rejects invalid AI provider" do
      config = Config.new(ai: %{provider: :invalid_provider})

      assert {:error, error} = ConfigValidator.validate(config)
      assert error.error_type == :invalid_config_value
      assert error.category == :config
    end

    test "rejects negative ring buffer size" do
      config =
        Config.new(
          capture: %{ring_buffer: %{size: -1, max_events: 1000, overflow_strategy: :drop_oldest}}
        )

      assert {:error, error} = ConfigValidator.validate(config)
      assert error.error_type == :validation_failed
    end

    test "rejects invalid sampling rate" do
      config =
        Config.new(
          ai: %{
            planning: %{sampling_rate: 1.5, performance_target: 0.01, default_strategy: :balanced}
          }
        )

      assert {:error, error} = ConfigValidator.validate(config)
      assert error.error_type == :range_error
    end
  end

  describe "validate_ai_config/1" do
    test "validates valid AI configuration" do
      ai_config = %{
        provider: :openai,
        analysis: %{max_file_size: 1000, timeout: 5000, cache_ttl: 3600},
        planning: %{performance_target: 0.01, sampling_rate: 0.8, default_strategy: :balanced}
      }

      assert :ok = ConfigValidator.validate_ai_config(ai_config)
    end

    test "rejects invalid strategy" do
      ai_config = %{
        provider: :openai,
        analysis: %{max_file_size: 1000, timeout: 5000, cache_ttl: 3600},
        planning: %{performance_target: 0.01, sampling_rate: 0.8, default_strategy: :invalid}
      }

      assert {:error, error} = ConfigValidator.validate_ai_config(ai_config)
      assert error.error_type == :invalid_config_value
    end
  end
end
