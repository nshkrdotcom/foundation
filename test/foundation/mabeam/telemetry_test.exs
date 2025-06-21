defmodule Foundation.MABEAM.TelemetryTest do
  @moduledoc """
  Tests for MABEAM-specific telemetry and monitoring functionality.

  This module tests the comprehensive observability features for multi-agent systems
  including agent performance metrics, coordination analytics, and system health monitoring.
  """

  use ExUnit.Case, async: false

  alias Foundation.MABEAM.Telemetry

  setup do
    # Start telemetry for testing
    {:ok, pid} = Telemetry.start_link()

    # Clear any existing metrics
    Telemetry.clear_metrics()

    on_exit(fn ->
      if Process.alive?(pid) do
        Telemetry.clear_metrics()
        GenServer.stop(pid)
      end
    end)

    :ok
  end

  describe "agent performance metrics" do
    test "records and retrieves agent execution metrics" do
      agent_id = "test_agent_001"

      # Record some execution metrics
      :ok = Telemetry.record_agent_metric(agent_id, :execution_time, 150)
      :ok = Telemetry.record_agent_metric(agent_id, :memory_usage, 1024)
      :ok = Telemetry.record_agent_metric(agent_id, :cpu_usage, 0.25)

      # Verify metrics are recorded
      {:ok, metrics} = Telemetry.get_agent_metrics(agent_id)
      assert metrics.execution_time.latest == 150
      assert metrics.memory_usage.latest == 1024
      assert metrics.cpu_usage.latest == 0.25
    end

    test "aggregates metrics over time windows" do
      agent_id = "test_agent_002"

      # Record multiple response time metrics
      response_times = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]

      Enum.each(response_times, fn time ->
        :ok = Telemetry.record_agent_metric(agent_id, :response_time, time)
      end)

      # Get aggregated statistics
      {:ok, stats} = Telemetry.get_agent_statistics(agent_id, :response_time, window: :last_minute)

      assert stats.count == 10
      assert stats.average == 55.0
      assert stats.min == 10
      assert stats.max == 100
      assert stats.median == 55.0
    end

    test "tracks agent success and failure rates" do
      agent_id = "test_agent_003"

      # Record successful operations
      :ok = Telemetry.record_agent_outcome(agent_id, :success, %{operation: "process_request"})
      :ok = Telemetry.record_agent_outcome(agent_id, :success, %{operation: "process_request"})

      :ok =
        Telemetry.record_agent_outcome(agent_id, :failure, %{
          operation: "process_request",
          error: "timeout"
        })

      # Check success rate
      {:ok, rates} = Telemetry.get_agent_success_rate(agent_id)
      # 2/3 rounded
      assert rates.success_rate == 0.667
      assert rates.total_operations == 3
      assert rates.successful_operations == 2
      assert rates.failed_operations == 1
    end

    test "measures variable optimization performance" do
      agent_id = "test_agent_004"
      variable_id = "test_variable"

      # Record variable optimization metrics
      :ok =
        Telemetry.record_variable_optimization(agent_id, variable_id, %{
          initial_value: 0.5,
          optimized_value: 0.8,
          optimization_time: 250,
          iterations: 15
        })

      {:ok, metrics} = Telemetry.get_variable_optimization_metrics(agent_id, variable_id)
      assert_in_delta metrics.improvement, 0.3, 0.001
      assert metrics.optimization_time == 250
      assert metrics.iterations == 15
    end
  end

  describe "coordination analytics" do
    test "tracks coordination protocol performance" do
      protocol_id = "consensus_protocol"

      # Record coordination metrics
      :ok =
        Telemetry.record_coordination_event(protocol_id, :start, %{
          participants: ["agent1", "agent2", "agent3"],
          coordination_type: :consensus
        })

      :ok =
        Telemetry.record_coordination_event(protocol_id, :complete, %{
          duration: 1500,
          success: true,
          consensus_reached: true
        })

      {:ok, metrics} = Telemetry.get_coordination_metrics(protocol_id)
      assert metrics.total_coordinations == 1
      assert metrics.successful_coordinations == 1
      assert metrics.average_duration == 1500
    end

    test "measures auction coordination performance" do
      auction_id = "test_auction_001"

      # Record auction metrics
      :ok =
        Telemetry.record_auction_event(auction_id, :start, %{
          auction_type: :sealed_bid,
          participants: 5,
          items: ["resource_1", "resource_2"]
        })

      # Record multiple bids
      Enum.each(1..8, fn i ->
        :ok =
          Telemetry.record_auction_event(auction_id, :bid_received, %{
            bidder: "agent_#{i}",
            item: "resource_1",
            bid_amount: 100 + i * 10
          })
      end)

      :ok =
        Telemetry.record_auction_event(auction_id, :complete, %{
          duration: 2000,
          total_bids: 8,
          revenue: 350,
          efficiency: 0.85
        })

      {:ok, metrics} = Telemetry.get_auction_metrics(auction_id)
      assert metrics.total_bids == 8
      assert metrics.revenue == 350
      assert metrics.efficiency == 0.85
    end

    test "tracks market coordination metrics" do
      market_id = "test_market_001"

      # Record market activity
      :ok =
        Telemetry.record_market_event(market_id, :trade_executed, %{
          buyer: "agent_1",
          seller: "agent_2",
          price: 50.0,
          quantity: 10,
          equilibrium_price: 48.5
        })

      {:ok, metrics} = Telemetry.get_market_metrics(market_id)
      assert metrics.total_trades == 1
      assert metrics.average_price == 50.0
      assert metrics.price_efficiency > 0.9
    end
  end

  describe "system health monitoring" do
    test "monitors MABEAM component health" do
      # Get health status for all components
      {:ok, health} = Telemetry.get_system_health()

      assert Map.has_key?(health, :agent_registry)
      assert Map.has_key?(health, :coordination)
      assert Map.has_key?(health, :core_orchestrator)

      # Each component should have health metrics
      Enum.each(health, fn {_component, status} ->
        assert Map.has_key?(status, :status)
        assert Map.has_key?(status, :uptime)
        assert Map.has_key?(status, :resource_usage)
      end)
    end

    test "tracks resource utilization" do
      # Record resource usage
      # 100MB
      :ok = Telemetry.record_resource_usage(:memory, 1024 * 1024 * 100)
      # 45% CPU
      :ok = Telemetry.record_resource_usage(:cpu, 0.45)
      # 50KB network
      :ok = Telemetry.record_resource_usage(:network, 1024 * 50)

      {:ok, usage} = Telemetry.get_resource_utilization()
      assert usage.memory >= 100_000_000
      assert usage.cpu == 0.45
      assert usage.network >= 50_000
    end

    test "detects performance anomalies" do
      agent_id = "test_agent_anomaly"

      # Record normal response times
      Enum.each(1..20, fn _ ->
        Telemetry.record_agent_metric(agent_id, :response_time, 100 + :rand.uniform(20))
      end)

      # Record anomalous response time
      Telemetry.record_agent_metric(agent_id, :response_time, 1000)

      {:ok, anomalies} = Telemetry.detect_anomalies(agent_id, :response_time)
      assert length(anomalies) > 0
      assert Enum.any?(anomalies, fn anomaly -> anomaly.value == 1000 end)
    end
  end

  describe "alerting and notifications" do
    test "configures performance thresholds" do
      # Configure alerting thresholds
      :ok =
        Telemetry.configure_alert(:response_time_threshold, %{
          metric: :response_time,
          threshold: 500,
          comparison: :greater_than,
          action: :notify
        })

      {:ok, config} = Telemetry.get_alert_configuration(:response_time_threshold)
      assert config.threshold == 500
      assert config.comparison == :greater_than
    end

    test "triggers alerts based on thresholds" do
      # Set up alert handler
      test_pid = self()

      Telemetry.set_alert_handler(fn alert ->
        send(test_pid, {:alert_triggered, alert})
      end)

      # Configure threshold
      Telemetry.configure_alert(:test_threshold, %{
        metric: :response_time,
        threshold: 200,
        comparison: :greater_than,
        action: :notify
      })

      # Trigger alert
      Telemetry.record_agent_metric("test_agent", :response_time, 300)

      # Verify alert was triggered
      assert_receive {:alert_triggered, alert}, 1000
      assert alert.metric == :response_time
      assert alert.value == 300
      assert alert.threshold == 200
    end
  end

  describe "dashboard integration" do
    test "provides dashboard data in structured format" do
      # Record some sample data
      Telemetry.record_agent_metric("agent1", :response_time, 100)
      Telemetry.record_agent_metric("agent2", :response_time, 150)
      Telemetry.record_coordination_event("coord1", :complete, %{duration: 500, success: true})

      # Get dashboard data
      {:ok, dashboard_data} = Telemetry.get_dashboard_data()

      assert Map.has_key?(dashboard_data, :agent_metrics)
      assert Map.has_key?(dashboard_data, :coordination_metrics)
      assert Map.has_key?(dashboard_data, :system_health)
      assert Map.has_key?(dashboard_data, :recent_events)
    end

    test "exports metrics in various formats" do
      # Record sample metrics
      Telemetry.record_agent_metric("agent1", :response_time, 100)

      # Test JSON export
      {:ok, json_data} = Telemetry.export_metrics(:json)
      assert is_binary(json_data)

      # Test Prometheus format
      {:ok, prometheus_data} = Telemetry.export_metrics(:prometheus)
      assert is_binary(prometheus_data)
      assert String.contains?(prometheus_data, "# HELP")
    end
  end

  describe "telemetry event emission" do
    test "emits structured telemetry events" do
      # Set up event collector
      test_pid = self()

      :telemetry.attach(
        "test_handler",
        [:foundation, :mabeam, :agent, :metric],
        fn event_name, measurements, metadata, _config ->
          send(test_pid, {:telemetry_event, event_name, measurements, metadata})
        end,
        nil
      )

      # Record a metric
      Telemetry.record_agent_metric("test_agent", :response_time, 150)

      # Verify telemetry event was emitted
      assert_receive {:telemetry_event, [:foundation, :mabeam, :agent, :metric], measurements,
                      metadata},
                     1000

      assert measurements.value == 150
      assert metadata.agent_id == "test_agent"
      assert metadata.metric_type == :response_time

      # Cleanup
      :telemetry.detach("test_handler")
    end
  end

  describe "performance and scalability" do
    test "handles high-volume metrics efficiently" do
      agent_id = "high_volume_agent"

      # Record large number of metrics
      start_time = System.monotonic_time(:millisecond)

      Enum.each(1..1000, fn i ->
        Telemetry.record_agent_metric(agent_id, :response_time, i)
      end)

      end_time = System.monotonic_time(:millisecond)
      total_time = end_time - start_time

      # Should complete within reasonable time (less than 1 second)
      assert total_time < 1000

      # Verify all metrics were recorded
      {:ok, stats} = Telemetry.get_agent_statistics(agent_id, :response_time)
      assert stats.count == 1000
    end

    test "properly manages memory usage" do
      agent_id = "memory_test_agent"

      # Record metrics and verify memory doesn't grow unboundedly
      initial_memory = :erlang.memory(:total)

      Enum.each(1..5000, fn i ->
        Telemetry.record_agent_metric(agent_id, :response_time, i)
      end)

      final_memory = :erlang.memory(:total)
      memory_growth = final_memory - initial_memory

      # Memory growth should be reasonable (less than 50MB)
      assert memory_growth < 50 * 1024 * 1024
    end
  end

  describe "error handling and resilience" do
    test "handles invalid metric types gracefully" do
      agent_id = "test_agent_errors"

      # Try to record invalid metric
      result = Telemetry.record_agent_metric(agent_id, :invalid_metric, "not_a_number")
      assert {:error, _reason} = result
    end

    test "continues functioning after errors" do
      agent_id = "test_agent_recovery"

      # Record invalid metric
      {:error, _} = Telemetry.record_agent_metric(agent_id, :response_time, "invalid")

      # Verify valid metrics still work
      :ok = Telemetry.record_agent_metric(agent_id, :response_time, 100)

      {:ok, metrics} = Telemetry.get_agent_metrics(agent_id)
      assert metrics.response_time.latest == 100
    end
  end
end
