defmodule Foundation.Retry.ConfigTest do
  use ExUnit.Case, async: true

  alias Foundation.Retry.Config

  test "new/1 applies defaults" do
    config = Config.new()

    assert config.max_retries == :infinity
    assert config.base_delay_ms == 500
    assert config.max_delay_ms == 10_000
    assert config.jitter_pct == 0.25
    assert config.progress_timeout_ms == 7_200_000
    assert config.max_connections == 1000
    assert config.enable_retry_logic == true
  end

  test "validate!/1 raises on invalid values" do
    assert_raise ArgumentError, fn ->
      Config.new(base_delay_ms: 0)
    end

    assert_raise ArgumentError, fn ->
      Config.new(max_delay_ms: 100, base_delay_ms: 200)
    end
  end

  test "to_handler_opts/1 returns handler options" do
    config =
      Config.new(
        max_retries: 3,
        base_delay_ms: 100,
        max_delay_ms: 1_000,
        jitter_pct: 0.1,
        progress_timeout_ms: 5_000
      )

    assert Config.to_handler_opts(config) == [
             max_retries: 3,
             base_delay_ms: 100,
             max_delay_ms: 1_000,
             jitter_pct: 0.1,
             progress_timeout_ms: 5_000
           ]
  end
end
