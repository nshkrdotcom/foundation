defmodule MABEAM.TelemetryTest do
  @moduledoc """
  Comprehensive test suite for MABEAM.Telemetry.

  Tests all telemetry collection, analytics, alerting, and integration
  functionality following TDD best practices.
  """

  use ExUnit.Case, async: false

  alias MABEAM.Telemetry

  # ============================================================================
  # Test Setup and Helpers
  # ============================================================================

  setup do
    # Clear any existing metrics to ensure clean test state
    Telemetry.clear_metrics()
    :ok
  end

  # ============================================================================
  # Metric Collection Tests
  # ============================================================================

  describe "agent metric collection" do
    test "records agent performance metrics successfully" do
      # Record various agent metrics
      assert :ok = Telemetry.record_agent_metric(:test_agent, :response_time, 150.5)
      assert :ok = Telemetry.record_agent_metric(:test_agent, :success_rate, 0.95)
      assert :ok = Telemetry.record_agent_metric(:test_agent, :error_count, 2)
      assert :ok = Telemetry.record_agent_metric(:test_agent, :resource_usage, 75.2)

      # Should be able to retrieve agent metrics
      {:ok, metrics} = Telemetry.get_agent_metrics(:test_agent)
      assert is_map(metrics)
      assert is_list(metrics.response_times)
      assert is_list(metrics.success_rates)
      assert is_list(metrics.error_counts)
      assert is_list(metrics.resource_usage)
      assert length(metrics.response_times) == 1
      assert hd(metrics.response_times) == 150.5
    end

    test "handles multiple metrics for same agent" do
      agent_id = :multi_metric_agent

      # Record multiple response times
      response_times = [100, 150, 200, 120, 180]

      Enum.each(response_times, fn time ->
        assert :ok = Telemetry.record_agent_metric(agent_id, :response_time, time)
      end)

      {:ok, metrics} = Telemetry.get_agent_metrics(agent_id)
      assert length(metrics.response_times) == 5
      assert Enum.reverse(metrics.response_times) == response_times
    end

    test "maintains metrics history with capacity limits" do
      agent_id = :capacity_test_agent

      # Record more than 100 metrics (the internal limit)
      Enum.each(1..150, fn i ->
        assert :ok = Telemetry.record_agent_metric(agent_id, :response_time, i)
      end)

      {:ok, metrics} = Telemetry.get_agent_metrics(agent_id)
      # Should cap at 100 entries
      assert length(metrics.response_times) == 100
      # Should keep the most recent entries
      assert hd(metrics.response_times) == 150
    end

    test "handles metrics with metadata" do
      metadata = %{
        tags: ["performance", "critical"],
        source: "load_test",
        environment: "staging"
      }

      assert :ok = Telemetry.record_agent_metric(:meta_agent, :response_time, 200, metadata)

      {:ok, metrics} = Telemetry.get_agent_metrics(:meta_agent)
      assert is_map(metrics)
      assert metrics.last_updated != nil
    end

    test "returns error for non-existent agent" do
      assert {:error, :agent_not_found} = Telemetry.get_agent_metrics(:non_existent_agent)
    end
  end

  describe "coordination metric collection" do
    test "records coordination protocol metrics successfully" do
      protocol_name = "consensus_protocol"

      assert :ok = Telemetry.record_coordination_metric(protocol_name, :success_rate, 0.92)
      assert :ok = Telemetry.record_coordination_metric(protocol_name, :duration, 250.0)
      assert :ok = Telemetry.record_coordination_metric(protocol_name, :participants, 5)

      {:ok, metrics} = Telemetry.get_coordination_metrics(protocol_name)
      assert metrics.protocol_name == protocol_name
      assert metrics.success_rate == 0.92
      assert metrics.average_duration == 250.0
      assert metrics.participant_count == 5
    end

    test "handles multiple coordination protocols" do
      protocols = [
        {"consensus_protocol", :success_rate, 0.95},
        {"leader_election", :duration, 100.0},
        {"resource_allocation", :completion_rate, 0.88}
      ]

      Enum.each(protocols, fn {protocol, metric, value} ->
        assert :ok = Telemetry.record_coordination_metric(protocol, metric, value)
      end)

      {:ok, all_metrics} = Telemetry.get_coordination_metrics()
      assert map_size(all_metrics) >= 3
      assert Map.has_key?(all_metrics, "consensus_protocol")
      assert Map.has_key?(all_metrics, "leader_election")
      assert Map.has_key?(all_metrics, "resource_allocation")
    end

    test "returns error for non-existent protocol" do
      assert {:error, :protocol_not_found} =
               Telemetry.get_coordination_metrics("non_existent_protocol")
    end
  end

  describe "system metric collection" do
    test "records system-wide metrics successfully" do
      assert :ok = Telemetry.record_system_metric(:cpu_usage, 45.2)
      assert :ok = Telemetry.record_system_metric(:memory_usage, 1024.5)
      assert :ok = Telemetry.record_system_metric(:active_connections, 150)

      {:ok, system_metrics} = Telemetry.get_system_metrics()
      assert is_map(system_metrics)
      assert Map.has_key?(system_metrics, :cpu_usage)
      assert Map.has_key?(system_metrics, :memory_usage)
      assert Map.has_key?(system_metrics, :active_connections)
    end

    test "includes comprehensive system information" do
      {:ok, system_metrics} = Telemetry.get_system_metrics()

      # Should include system health
      assert Map.has_key?(system_metrics, :system_health)
      system_health = system_metrics.system_health
      assert system_health.overall_status in [:healthy, :degraded, :critical]

      # Should include counters
      assert is_number(system_metrics.total_agents)
      assert is_number(system_metrics.total_protocols)
      assert is_number(system_metrics.total_metrics_collected)
      assert is_number(system_metrics.uptime_seconds)
    end
  end

  # ============================================================================
  # Query and Analytics Tests
  # ============================================================================

  describe "metric querying" do
    test "queries metrics with flexible filtering" do
      # Record some test metrics
      Telemetry.record_agent_metric(:query_agent1, :response_time, 100)
      Telemetry.record_agent_metric(:query_agent2, :response_time, 200)
      Telemetry.record_coordination_metric("test_protocol", :success_rate, 0.9)

      # Query all metrics
      {:ok, all_metrics} = Telemetry.query_metrics(%{})
      assert is_list(all_metrics)
      assert length(all_metrics) >= 3
    end

    test "provides agent analytics" do
      agent_id = :analytics_agent

      # Record metrics for analytics
      Enum.each([100, 150, 200, 120, 180], fn time ->
        Telemetry.record_agent_metric(agent_id, :response_time, time)
      end)

      {:ok, analytics} = Telemetry.get_agent_analytics(agent_id, :last_hour)
      assert analytics.agent_id == agent_id
      assert analytics.time_window == :last_hour
      assert is_number(analytics.average_response_time)
      assert is_number(analytics.success_rate)
      assert is_number(analytics.error_rate)
    end

    test "provides coordination analytics" do
      protocol_name = "analytics_protocol"

      # Record coordination metrics
      Telemetry.record_coordination_metric(protocol_name, :success_rate, 0.95)
      Telemetry.record_coordination_metric(protocol_name, :duration, 150.0)

      {:ok, analytics} = Telemetry.get_coordination_analytics(protocol_name)
      assert analytics.protocol_name == protocol_name
      assert is_number(analytics.total_coordinations)
      assert is_number(analytics.success_rate)
      assert is_number(analytics.average_duration)
    end

    test "provides system analytics" do
      # Record some system activity
      Telemetry.record_agent_metric(:sys_agent1, :response_time, 100)
      Telemetry.record_agent_metric(:sys_agent2, :response_time, 200)
      Telemetry.record_coordination_metric("sys_protocol", :success_rate, 0.9)

      {:ok, analytics} = Telemetry.get_system_analytics()
      assert is_number(analytics.total_agents_tracked)
      assert is_number(analytics.total_protocols_tracked)
      assert is_number(analytics.total_metrics_collected)
      assert is_number(analytics.uptime_hours)
      assert is_number(analytics.metrics_per_hour)
      assert is_number(analytics.storage_efficiency)
    end
  end

  # ============================================================================
  # Alert Management Tests
  # ============================================================================

  describe "alert management" do
    test "adds alert configuration successfully" do
      alert_config = %{
        id: "high_response_time",
        metric: :response_time,
        threshold: 500,
        comparison: :greater_than,
        action: :notify
      }

      assert :ok = Telemetry.add_alert_config(alert_config)

      {:ok, configs} = Telemetry.list_alert_configs()
      assert alert_config in configs
    end

    test "validates alert configuration" do
      invalid_config = %{
        metric: :response_time,
        threshold: 500
        # Missing required fields: id, comparison, action
      }

      assert {:error, :missing_required_fields} =
               Telemetry.add_alert_config(invalid_config)
    end

    test "removes alert configuration" do
      alert_config = %{
        id: "removable_alert",
        metric: :error_rate,
        threshold: 0.1,
        comparison: :greater_than,
        action: :log
      }

      assert :ok = Telemetry.add_alert_config(alert_config)
      {:ok, configs_before} = Telemetry.list_alert_configs()
      assert alert_config in configs_before

      assert :ok = Telemetry.remove_alert_config("removable_alert")
      {:ok, configs_after} = Telemetry.list_alert_configs()
      refute alert_config in configs_after
    end
  end

  # ============================================================================
  # Telemetry Event Integration Tests
  # ============================================================================

  describe "telemetry event integration" do
    test "processes incoming telemetry events" do
      test_pid = self()

      # Attach a test handler to verify events are processed
      :telemetry.attach(
        "telemetry_test_handler",
        [:foundation, :mabeam, :agent, :registered],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry_received, event, measurements, metadata})
        end,
        nil
      )

      # Emit a test event
      :telemetry.execute(
        [:foundation, :mabeam, :agent, :registered],
        %{count: 1},
        %{agent_id: :test_integration_agent}
      )

      # Should receive the event
      assert_receive {:telemetry_received, [:foundation, :mabeam, :agent, :registered], _, _}

      # Cleanup
      :telemetry.detach("telemetry_test_handler")
    end

    test "automatically tracks agent lifecycle events" do
      # Record initial metrics count
      {:ok, initial_metrics} = Telemetry.get_system_metrics()
      initial_count = initial_metrics.total_metrics_collected

      # Emit agent lifecycle events
      :telemetry.execute(
        [:foundation, :mabeam, :agent, :started],
        %{count: 1},
        %{agent_id: :lifecycle_test_agent}
      )

      :telemetry.execute(
        [:foundation, :mabeam, :agent, :stopped],
        %{count: 1},
        %{agent_id: :lifecycle_test_agent}
      )

      # Allow time for processing
      Process.sleep(100)

      # Should have recorded the events
      {:ok, updated_metrics} = Telemetry.get_system_metrics()
      assert updated_metrics.total_metrics_collected > initial_count
    end
  end

  # ============================================================================
  # Health and Service Integration Tests
  # ============================================================================

  describe "health monitoring" do
    test "provides comprehensive health status" do
      {:ok, health} = Telemetry.system_health()

      assert is_map(health)
      # Should include system health information
      system_health = health.system_health
      assert system_health.overall_status in [:healthy, :degraded, :critical]
      assert is_number(system_health.agent_health_score)
      assert is_number(system_health.coordination_health_score)
    end

    test "health status reflects system load" do
      # Record some metrics to affect health calculation
      Enum.each(1..10, fn i ->
        Telemetry.record_agent_metric(:load_test_agent, :response_time, i * 10)
      end)

      {:ok, _health_before} = Telemetry.system_health()

      # Record many more metrics to test capacity handling
      Enum.each(1..100, fn i ->
        Telemetry.record_system_metric("load_metric_#{i}", i)
      end)

      {:ok, health_after} = Telemetry.system_health()

      # Health should still be reasonable
      assert health_after.system_health.overall_status in [:healthy, :degraded, :critical]
    end
  end

  # ============================================================================
  # Data Management and Cleanup Tests
  # ============================================================================

  describe "data management" do
    test "clears all metrics successfully" do
      # Record some metrics
      Telemetry.record_agent_metric(:clear_test_agent, :response_time, 100)
      Telemetry.record_coordination_metric("clear_test_protocol", :success_rate, 0.9)
      Telemetry.record_system_metric(:clear_test_metric, 50)

      # Verify metrics exist
      {:ok, agent_metrics} = Telemetry.get_agent_metrics(:clear_test_agent)
      assert length(agent_metrics.response_times) > 0

      # Clear all metrics
      assert :ok = Telemetry.clear_metrics()

      # Verify metrics are cleared
      assert {:error, :agent_not_found} = Telemetry.get_agent_metrics(:clear_test_agent)
      {:ok, system_metrics} = Telemetry.get_system_metrics()
      assert system_metrics.total_metrics_collected == 0
    end

    test "handles large volumes of metrics efficiently" do
      start_time = System.monotonic_time(:millisecond)

      # Record a large number of metrics
      Enum.each(1..1000, fn i ->
        # 10 different agents
        agent_id = :"perf_agent_#{rem(i, 10)}"
        Telemetry.record_agent_metric(agent_id, :response_time, i)
      end)

      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time

      # Should handle 1000 metrics reasonably quickly (under 5 seconds)
      assert duration < 5000

      # System should still be responsive
      {:ok, _health} = Telemetry.system_health()
      {:ok, _metrics} = Telemetry.get_agent_metrics(:perf_agent_1)
    end

    test "respects metric retention limits" do
      # This test verifies the automatic cleanup functionality
      # Since cleanup runs periodically, we test the capacity limits instead

      agent_id = :retention_test_agent

      # Record metrics beyond the capacity limit
      Enum.each(1..150, fn i ->
        Telemetry.record_agent_metric(agent_id, :response_time, i)
      end)

      {:ok, metrics} = Telemetry.get_agent_metrics(agent_id)
      # Should respect the 100-item limit for agent metric lists
      assert length(metrics.response_times) <= 100
    end
  end

  # ============================================================================
  # Error Handling and Edge Cases
  # ============================================================================

  describe "error handling" do
    test "handles invalid metric values gracefully" do
      # These should still work - the system should be flexible
      assert :ok = Telemetry.record_agent_metric(:robust_agent, :response_time, -1)
      assert :ok = Telemetry.record_agent_metric(:robust_agent, :response_time, 0)
      assert :ok = Telemetry.record_agent_metric(:robust_agent, :response_time, 99999)

      {:ok, metrics} = Telemetry.get_agent_metrics(:robust_agent)
      assert length(metrics.response_times) == 3
    end

    test "maintains system stability under stress" do
      # Concurrent metric recording
      tasks =
        Enum.map(1..50, fn i ->
          Task.async(fn ->
            agent_id = :"stress_agent_#{i}"

            Enum.each(1..20, fn j ->
              Telemetry.record_agent_metric(agent_id, :response_time, j)
            end)
          end)
        end)

      # Wait for all tasks to complete
      Enum.each(tasks, &Task.await/1)

      # System should still be functional
      {:ok, _health} = Telemetry.system_health()
      {:ok, _analytics} = Telemetry.get_system_analytics()
    end

    test "handles unknown requests gracefully" do
      # The system should not crash with unknown requests
      assert {:error, :unknown_request} =
               GenServer.call(Telemetry, :unknown_request)
    end
  end

  # ============================================================================
  # Performance and Scalability Tests
  # ============================================================================

  describe "performance" do
    test "metric recording performance is acceptable" do
      # Measure time for recording metrics
      {time_microseconds, :ok} =
        :timer.tc(fn ->
          Enum.each(1..100, fn i ->
            Telemetry.record_agent_metric(:perf_test_agent, :response_time, i)
          end)
        end)

      # Should be able to record 100 metrics in reasonable time (under 1 second)
      assert time_microseconds < 1_000_000
    end

    test "metric retrieval performance is acceptable" do
      # Record some metrics first
      Enum.each(1..100, fn i ->
        Telemetry.record_agent_metric(:retrieval_test_agent, :response_time, i)
      end)

      # Measure retrieval time
      {time_microseconds, {:ok, _metrics}} =
        :timer.tc(fn ->
          Telemetry.get_agent_metrics(:retrieval_test_agent)
        end)

      # Should retrieve metrics quickly (under 100ms)
      assert time_microseconds < 100_000
    end
  end
end
