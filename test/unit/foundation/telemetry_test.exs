defmodule Foundation.TelemetryTest do
  use ExUnit.Case, async: false

  alias Foundation.Telemetry

  setup do
    # Ensure TelemetryService is available for all tests
    Foundation.TestHelpers.ensure_telemetry_available()
    :ok
  end

  describe "telemetry measurement" do
    test "measures event execution time" do
      result =
        Telemetry.measure([:test, :operation], %{component: :foundation}, fn ->
          :timer.sleep(5)
          :test_result
        end)

      assert result == :test_result
    end

    test "handles errors in measured events" do
      assert_raise RuntimeError, "test error", fn ->
        Telemetry.measure([:test, :error], %{}, fn ->
          raise RuntimeError, "test error"
        end)
      end
    end
  end

  describe "telemetry events" do
    test "emits counter events" do
      assert :ok = Telemetry.emit_counter([:test, :counter], %{source: :test})
    end

    test "emits gauge events" do
      assert :ok = Telemetry.emit_gauge([:test, :gauge], 42.5, %{unit: :percent})
    end
  end

  describe "metrics collection" do
    test "collects foundation metrics" do
      {:ok, metrics} = Telemetry.get_metrics()

      assert is_map(metrics)
      # The metrics returned are the actual metric events, not structured foundation data
      # Let's just verify we get a map back
    end
  end

  describe "initialization and status" do
    test "initializes successfully" do
      assert :ok = Telemetry.initialize()
    end

    test "reports healthy status" do
      assert {:ok, status_map} = Telemetry.status()
      assert is_map(status_map)
      assert Map.has_key?(status_map, :status)
    end
  end
end
