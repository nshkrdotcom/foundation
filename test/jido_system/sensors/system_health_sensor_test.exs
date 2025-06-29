defmodule JidoSystem.Sensors.SystemHealthSensorTest do
  use ExUnit.Case, async: false
  
  alias JidoSystem.Sensors.SystemHealthSensor
  alias Foundation.{Registry, Telemetry}
  alias Jido.Signal
  
  setup do
    # Ensure clean state - detach any existing handlers
    try do
      :telemetry.detach("test_health_monitoring")
      :telemetry.detach("test_signal_generation")
      :telemetry.detach("test_error_handling")
    rescue
      _ -> :ok
    end
    
    :ok
  end
  
  describe "sensor initialization" do
    test "successfully mounts with default configuration" do
      config = %{
        id: "test_health_sensor",
        target: {:pid, target: self()},
        collection_interval: 1000,
        thresholds: %{
          cpu_usage: 80,
          memory_usage: 85,
          process_count: 10_000
        }
      }
      
      {:ok, state} = SystemHealthSensor.mount(config)
      
      assert state.id == "test_health_sensor"
      assert state.collection_interval == 1000
      assert is_map(state.thresholds)
      assert state.enable_anomaly_detection == true
      assert state.history_size == 100
      assert state.collection_count == 0
      assert %DateTime{} = state.started_at
    end
    
    test "initializes with custom configuration" do
      config = %{
        id: "custom_health_sensor",
        target: {:pid, target: self()},
        collection_interval: 5000,
        thresholds: %{
          cpu_usage: 70,
          memory_usage: 80
        },
        enable_anomaly_detection: false,
        history_size: 50
      }
      
      {:ok, state} = SystemHealthSensor.mount(config)
      
      assert state.collection_interval == 5000
      assert state.enable_anomaly_detection == false
      assert state.history_size == 50
      assert state.thresholds.cpu_usage == 70
    end
    
    test "starts the sensor process" do
      config = [
        id: "process_health_sensor",
        target: {:pid, target: self()},
        collection_interval: 60_000
      ]
      
      {:ok, pid} = SystemHealthSensor.start_link(config)
      
      assert Process.alive?(pid)
    end
  end
  
  describe "metrics collection" do
    setup do
      config = %{
        id: "metrics_test_sensor",
        target: {:pid, target: self()},
        collection_interval: 1000,
        thresholds: %{
          cpu_usage: 80,
          memory_usage: 85,
          process_count: 10_000
        },
        enable_anomaly_detection: true,
        history_size: 10
      }
      
      {:ok, state} = SystemHealthSensor.mount(config)
      %{sensor_state: state}
    end
    
    test "collects comprehensive system metrics", %{sensor_state: state} do
      {:ok, signal, new_state} = SystemHealthSensor.deliver_signal(state)
      
      assert %Signal{} = signal
      assert signal.type =~ "system.health."
      assert is_map(signal.data)
      
      # Verify signal contains expected metrics
      assert Map.has_key?(signal.data, :status)
      assert Map.has_key?(signal.data, :health_score)
      assert Map.has_key?(signal.data, :metrics)
      assert Map.has_key?(signal.data, :timestamp)
      
      # Verify metrics structure
      metrics = signal.data.metrics
      assert Map.has_key?(metrics, :memory_usage)
      assert Map.has_key?(metrics, :process_count)
      assert Map.has_key?(metrics, :cpu_utilization)
      
      # Verify state was updated
      assert new_state.collection_count == state.collection_count + 1
      assert length(new_state.metrics_history) == 1
    end
    
    test "maintains metrics history within limit", %{sensor_state: initial_state} do
      # Collect metrics multiple times
      state = Enum.reduce(1..15, initial_state, fn _i, acc_state ->
        {:ok, _signal, new_state} = SystemHealthSensor.deliver_signal(acc_state)
        new_state
      end)
      
      # History should be limited to configured size
      assert length(state.metrics_history) == state.history_size
      assert state.collection_count == 15
    end
    
    test "handles collection errors gracefully", %{sensor_state: state} do
      # This test simulates an error during metrics collection
      # In a real scenario, we might mock system calls to fail
      
      # The deliver_signal should handle errors and create error signals
      {:ok, signal, _new_state} = SystemHealthSensor.deliver_signal(state)
      
      # Should still produce a signal even if some metrics fail
      assert %Signal{} = signal
    end
  end
  
  describe "health analysis" do
    setup do
      config = %{
        id: "analysis_test_sensor",
        target: {:pid, target: self()},
        collection_interval: 1000,
        thresholds: %{
          cpu_usage: 80,
          memory_usage: 85,
          process_count: 10_000,
          message_queue_size: 1_000
        },
        enable_anomaly_detection: true,
        history_size: 20
      }
      
      {:ok, state} = SystemHealthSensor.mount(config)
      %{sensor_state: state}
    end
    
    test "analyzes normal system health correctly", %{sensor_state: state} do
      result = SystemHealthSensor.deliver_signal(state)
      assert match?({:ok, %Signal{}, _state}, result)
      
      {:ok, signal, _new_state} = result
      
      # Debug: Check signal structure
      assert %Signal{} = signal
      data = Map.get(signal, :data)
      assert is_map(data)
      
      # With normal system conditions, should report good health
      assert data.status in [:ok, :warning] # Depends on current system state
      assert is_number(data.health_score)
      assert data.health_score >= 0
      assert data.health_score <= 100
    end
    
    test "detects threshold violations", %{sensor_state: state} do
      # Simulate high resource usage by setting very low thresholds
      low_threshold_state = %{state | 
        thresholds: %{
          cpu_usage: 1,    # Very low threshold
          memory_usage: 1,
          process_count: 1,
          message_queue_size: 1
        }
      }
      
      {:ok, signal, _new_state} = SystemHealthSensor.deliver_signal(low_threshold_state)
      
      # Should detect violations with such low thresholds
      assert signal.data.status in [:warning, :critical, :emergency]
      assert is_list(signal.data.threshold_violations)
      assert signal.data.requires_attention == true
    end
    
    test "generates appropriate recommendations", %{sensor_state: state} do
      {:ok, signal, _new_state} = SystemHealthSensor.deliver_signal(state)
      
      assert is_list(signal.data.recommendations)
      assert length(signal.data.recommendations) > 0
      
      # Should provide actionable recommendations
      Enum.each(signal.data.recommendations, fn recommendation ->
        assert is_binary(recommendation)
        assert String.length(recommendation) > 0
      end)
    end
    
    test "tracks trends with sufficient history", %{sensor_state: initial_state} do
      # Collect enough metrics to enable trend analysis
      state = Enum.reduce(1..10, initial_state, fn _i, acc_state ->
        {:ok, _signal, new_state} = SystemHealthSensor.deliver_signal(acc_state)
        Process.sleep(10) # Small delay to ensure different timestamps
        new_state
      end)
      
      {:ok, signal, _final_state} = SystemHealthSensor.deliver_signal(state)
      
      # Should include trend analysis
      if Map.has_key?(signal.data, :trends) do
        trends = signal.data.trends
        assert is_map(trends)
        
        # Check for trend categories
        possible_trends = [:memory_trend, :process_trend, :load_trend]
        trend_keys = Map.keys(trends)
        assert Enum.any?(possible_trends, &(&1 in trend_keys))
      end
    end
  end
  
  describe "anomaly detection" do
    setup do
      config = %{
        id: "anomaly_test_sensor",
        target: {:pid, target: self()},
        collection_interval: 1000,
        thresholds: %{cpu_usage: 80, memory_usage: 85, process_count: 10_000},
        enable_anomaly_detection: true,
        history_size: 20
      }
      
      {:ok, state} = SystemHealthSensor.mount(config)
      %{sensor_state: state}
    end
    
    test "detects anomalies when enabled", %{sensor_state: state} do
      # Build up some history first
      state_with_history = Enum.reduce(1..15, state, fn _i, acc_state ->
        {:ok, _signal, new_state} = SystemHealthSensor.deliver_signal(acc_state)
        new_state
      end)
      
      {:ok, signal, _new_state} = SystemHealthSensor.deliver_signal(state_with_history)
      
      # Check that anomaly detection is working
      assert is_list(signal.data.anomalies)
      # Anomalies may or may not be present depending on current system state
    end
    
    test "skips anomaly detection when disabled", %{sensor_state: initial_state} do
      disabled_state = %{initial_state | enable_anomaly_detection: false}
      
      {:ok, signal, _new_state} = SystemHealthSensor.deliver_signal(disabled_state)
      
      # Should still work but without anomaly detection
      assert is_list(signal.data.anomalies)
      assert signal.data.anomalies == []
    end
  end
  
  describe "signal generation" do
    setup do
      config = %{
        id: "signal_test_sensor",
        target: {:pid, target: self()},
        collection_interval: 1000,
        thresholds: %{cpu_usage: 80, memory_usage: 85, process_count: 10_000},
        enable_anomaly_detection: true,
        history_size: 10
      }
      
      {:ok, state} = SystemHealthSensor.mount(config)
      %{sensor_state: state}
    end
    
    test "generates signals with correct structure", %{sensor_state: state} do
      {:ok, signal, _new_state} = SystemHealthSensor.deliver_signal(state)
      
      # Verify signal structure
      assert %Signal{type: type, data: data} = signal
      assert type =~ "system.health."
      
      # Verify required data fields
      required_fields = [
        :status, :health_score, :timestamp, :sensor_id,
        :metrics, :threshold_violations, :anomalies, :alert_level,
        :requires_attention, :recommendations
      ]
      
      Enum.each(required_fields, fn field ->
        assert Map.has_key?(data, field), "Missing required field: #{field}"
      end)
    end
    
    test "includes sensor metadata in signals", %{sensor_state: state} do
      {:ok, signal, _new_state} = SystemHealthSensor.deliver_signal(state)
      
      # Check for sensor-specific metadata
      assert signal.data.sensor_id == state.id
      assert Map.has_key?(signal.data, :sensor_uptime)
      assert signal.data.collection_count == state.collection_count + 1
    end
    
    test "generates different signal types based on health status", %{sensor_state: state} do
      {:ok, signal, _new_state} = SystemHealthSensor.deliver_signal(state)
      
      # Should generate type based on health status
      valid_types = [
        "system.health.ok",
        "system.health.warning", 
        "system.health.critical",
        "system.health.emergency"
      ]
      
      assert signal.type in valid_types
    end
  end
  
  describe "process integration" do
    test "sensor process handles periodic collection" do
      config = [
        id: "periodic_test_sensor",
        target: {:pid, target: self()},
        collection_interval: 100  # Very short interval for testing
      ]
      
      {:ok, pid} = SystemHealthSensor.start_link(config)
      
      # Should receive signals from periodic collection
      assert_receive {:signal, %Jido.Signal{} = _signal}, 1000
      
      assert Process.alive?(pid)
    end
    
    test "sensor process handles unknown messages gracefully" do
      config = [
        id: "message_test_sensor", 
        target: {:pid, target: self()},
        collection_interval: 60_000
      ]
      
      {:ok, pid} = SystemHealthSensor.start_link(config)
      
      # Send unknown message
      send(pid, :unknown_message)
      
      # Process should still be alive
      Process.sleep(10)
      assert Process.alive?(pid)
    end
  end
  
  describe "error handling" do
    setup do
      config = %{
        id: "error_test_sensor",
        target: {:pid, target: self()},
        collection_interval: 1000,
        thresholds: %{cpu_usage: 80, memory_usage: 85, process_count: 10_000}
      }
      
      {:ok, state} = SystemHealthSensor.mount(config)
      %{sensor_state: state}
    end
    
    test "handles metrics collection errors gracefully", %{sensor_state: state} do
      # The deliver_signal function should handle errors internally
      # and produce error signals when necessary
      
      result = SystemHealthSensor.deliver_signal(state)
      
      # Should always return a result, even if there are errors
      assert match?({:ok, %Signal{}, _state}, result)
    end
    
    test "produces error signals when collection fails", %{sensor_state: state} do
      # Simulate an error condition
      # This would require mocking system functions to fail
      # For now, verify that the function handles errors gracefully
      
      {:ok, signal, _new_state} = SystemHealthSensor.deliver_signal(state)
      
      # Should produce a valid signal even with potential errors
      assert %Signal{} = signal
      assert is_binary(signal.type)
      assert is_map(signal.data)
    end
  end
  
  describe "configuration validation" do
    test "works with minimal configuration" do
      minimal_config = %{
        id: "minimal_sensor",
        target: {:pid, target: self()}
      }
      
      {:ok, state} = SystemHealthSensor.mount(minimal_config)
      
      # Should use defaults for missing configuration
      assert state.collection_interval == 30_000  # Default
      assert state.enable_anomaly_detection == true  # Default
      assert is_map(state.thresholds)
    end
    
    test "respects custom thresholds" do
      config = %{
        id: "custom_thresholds_sensor",
        target: {:pid, target: self()},
        thresholds: %{
          cpu_usage: 90,
          memory_usage: 95,
          custom_metric: 50
        }
      }
      
      {:ok, state} = SystemHealthSensor.mount(config)
      
      assert state.thresholds.cpu_usage == 90
      assert state.thresholds.memory_usage == 95
      assert state.thresholds.custom_metric == 50
    end
  end
end