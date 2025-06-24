defmodule Foundation.MABEAM.PerformanceMonitorTest do
  @moduledoc """
  Tests for Foundation.MABEAM.PerformanceMonitor.

  Tests real-time agent performance monitoring and metrics collection including:
  - Agent performance metrics tracking
  - Resource utilization monitoring
  - Performance trend analysis
  - Alert generation for performance issues
  - Metrics aggregation and reporting
  """
  use ExUnit.Case, async: false

  alias Foundation.MABEAM.{Agent, PerformanceMonitor}

  setup do
    # Clear any existing state before each test
    PerformanceMonitor.clear_metrics()

    # Clean up any existing agents
    on_exit(fn ->
      cleanup_test_agents()
      PerformanceMonitor.clear_metrics()
    end)

    :ok
  end

  describe "metrics collection" do
    test "tracks agent performance metrics" do
      # Setup test agent
      agent_config = %{
        id: :perf_test_agent,
        type: :worker,
        module: Foundation.TestHelpers.TestWorker,
        capabilities: [:performance_testing]
      }

      assert :ok = Agent.register_agent(agent_config)

      # Start monitoring the agent
      assert :ok = PerformanceMonitor.start_monitoring(:perf_test_agent)

      # Record performance metrics
      metrics = %{
        cpu_usage: 0.45,
        # 256MB
        memory_usage: 256 * 1024 * 1024,
        # 1.5 seconds
        task_completion_time: 1500.0,
        # tasks per second
        throughput: 10.5,
        # 2% error rate
        error_rate: 0.02
      }

      assert :ok = PerformanceMonitor.record_metrics(:perf_test_agent, metrics)

      # Retrieve metrics
      {:ok, stored_metrics} = PerformanceMonitor.get_agent_metrics(:perf_test_agent)
      assert stored_metrics.cpu_usage == 0.45
      assert stored_metrics.memory_usage == 256 * 1024 * 1024
      assert stored_metrics.task_completion_time == 1500.0
      assert stored_metrics.throughput == 10.5
      assert stored_metrics.error_rate == 0.02
      assert %DateTime{} = stored_metrics.timestamp
    end

    test "handles non-existent agents gracefully" do
      metrics = %{cpu_usage: 0.5}
      assert :ok = PerformanceMonitor.record_metrics(:nonexistent_agent, metrics)

      assert {:error, :not_found} = PerformanceMonitor.get_agent_metrics(:nonexistent_agent)
    end

    test "tracks multiple metrics over time" do
      # Setup agent
      agent_config = %{
        id: :time_series_agent,
        type: :worker,
        module: Foundation.TestHelpers.TestWorker,
        capabilities: [:time_series_testing]
      }

      assert :ok = Agent.register_agent(agent_config)

      # Start monitoring the agent
      assert :ok = PerformanceMonitor.start_monitoring(:time_series_agent)

      # Record multiple metrics over time
      metrics_series = [
        %{cpu_usage: 0.3, throughput: 8.0},
        %{cpu_usage: 0.5, throughput: 10.0},
        %{cpu_usage: 0.7, throughput: 12.0}
      ]

      Enum.each(metrics_series, fn metrics ->
        :ok = PerformanceMonitor.record_metrics(:time_series_agent, metrics)
        # Small delay to ensure different timestamps
        Process.sleep(10)
      end)

      # Get metrics history
      {:ok, history} = PerformanceMonitor.get_metrics_history(:time_series_agent, limit: 5)
      assert length(history) == 3

      # Should be in reverse chronological order (newest first)
      cpu_values = Enum.map(history, & &1.cpu_usage)
      assert cpu_values == [0.7, 0.5, 0.3]
    end
  end

  describe "performance aggregation" do
    test "calculates performance statistics" do
      # Setup multiple agents
      agents = [
        {:agent1, %{cpu_usage: 0.2, throughput: 5.0, error_rate: 0.01}},
        {:agent2, %{cpu_usage: 0.6, throughput: 8.0, error_rate: 0.03}},
        {:agent3, %{cpu_usage: 0.4, throughput: 12.0, error_rate: 0.02}}
      ]

      Enum.each(agents, fn {agent_id, metrics} ->
        agent_config = %{
          id: agent_id,
          type: :worker,
          module: Foundation.TestHelpers.TestWorker,
          capabilities: [:stats_testing]
        }

        Agent.register_agent(agent_config)
        PerformanceMonitor.start_monitoring(agent_id)
        PerformanceMonitor.record_metrics(agent_id, metrics)
      end)

      # Get aggregated statistics
      stats = PerformanceMonitor.get_performance_statistics()

      assert stats.total_agents == 3
      # (0.2 + 0.6 + 0.4) / 3
      assert stats.average_cpu_usage == 0.4
      # (5.0 + 8.0 + 12.0) / 3
      assert_in_delta stats.average_throughput, 8.333333333333334, 0.000000001
      # (0.01 + 0.03 + 0.02) / 3
      assert stats.average_error_rate == 0.02
      assert stats.max_cpu_usage == 0.6
      assert stats.min_cpu_usage == 0.2
      assert %DateTime{} = stats.calculated_at
    end

    test "handles empty metrics gracefully" do
      stats = PerformanceMonitor.get_performance_statistics()

      assert stats.total_agents == 0
      assert stats.average_cpu_usage == 0.0
      assert stats.average_throughput == 0.0
      assert stats.average_error_rate == 0.0
      assert stats.max_cpu_usage == 0.0
      assert stats.min_cpu_usage == 0.0
    end
  end

  describe "performance alerts" do
    test "generates alerts for high CPU usage" do
      # Setup agent
      agent_config = %{
        id: :high_cpu_agent,
        type: :worker,
        module: Foundation.TestHelpers.TestWorker,
        capabilities: [:alert_testing]
      }

      assert :ok = Agent.register_agent(agent_config)

      # Start monitoring the agent
      assert :ok = PerformanceMonitor.start_monitoring(:high_cpu_agent)

      # Configure alert thresholds
      thresholds = %{
        high_cpu_threshold: 0.8,
        # 1GB
        high_memory_threshold: 1024 * 1024 * 1024,
        high_error_rate_threshold: 0.05,
        low_throughput_threshold: 1.0
      }

      :ok = PerformanceMonitor.set_alert_thresholds(thresholds)

      # Record high CPU usage
      metrics = %{cpu_usage: 0.95, memory_usage: 512 * 1024 * 1024}
      :ok = PerformanceMonitor.record_metrics(:high_cpu_agent, metrics)

      # Check for alerts
      alerts = PerformanceMonitor.get_active_alerts()
      assert length(alerts) == 1

      alert = hd(alerts)
      assert alert.agent_id == :high_cpu_agent
      assert alert.type == :high_cpu_usage
      assert alert.severity == :warning
      assert String.contains?(alert.message, "CPU usage")
      assert %DateTime{} = alert.triggered_at
    end

    test "generates alerts for low throughput" do
      # Setup agent
      agent_config = %{
        id: :low_throughput_agent,
        type: :worker,
        module: Foundation.TestHelpers.TestWorker,
        capabilities: [:throughput_testing]
      }

      assert :ok = Agent.register_agent(agent_config)

      # Start monitoring the agent
      assert :ok = PerformanceMonitor.start_monitoring(:low_throughput_agent)

      # Configure thresholds
      thresholds = %{low_throughput_threshold: 5.0}
      :ok = PerformanceMonitor.set_alert_thresholds(thresholds)

      # Record low throughput
      metrics = %{throughput: 0.5, cpu_usage: 0.1}
      :ok = PerformanceMonitor.record_metrics(:low_throughput_agent, metrics)

      # Check for alerts
      alerts = PerformanceMonitor.get_active_alerts()
      assert length(alerts) == 1

      alert = hd(alerts)
      assert alert.agent_id == :low_throughput_agent
      assert alert.type == :low_throughput
      assert alert.severity == :warning
    end

    test "clears resolved alerts" do
      # Setup agent and thresholds
      agent_config = %{
        id: :alert_resolution_agent,
        type: :worker,
        module: Foundation.TestHelpers.TestWorker,
        capabilities: [:resolution_testing]
      }

      assert :ok = Agent.register_agent(agent_config)

      # Start monitoring the agent
      assert :ok = PerformanceMonitor.start_monitoring(:alert_resolution_agent)

      thresholds = %{high_cpu_threshold: 0.8}
      :ok = PerformanceMonitor.set_alert_thresholds(thresholds)

      # Trigger alert
      high_metrics = %{cpu_usage: 0.95}
      :ok = PerformanceMonitor.record_metrics(:alert_resolution_agent, high_metrics)

      alerts = PerformanceMonitor.get_active_alerts()
      assert length(alerts) == 1

      # Resolve alert with normal metrics
      normal_metrics = %{cpu_usage: 0.3}
      :ok = PerformanceMonitor.record_metrics(:alert_resolution_agent, normal_metrics)

      # Alert should be cleared
      alerts_after = PerformanceMonitor.get_active_alerts()
      assert length(alerts_after) == 0
    end
  end

  describe "monitoring lifecycle" do
    test "starts and stops monitoring for agents" do
      # Setup agent
      agent_config = %{
        id: :lifecycle_agent,
        type: :worker,
        module: Foundation.TestHelpers.TestWorker,
        capabilities: [:lifecycle_testing]
      }

      assert :ok = Agent.register_agent(agent_config)

      # Start monitoring
      assert :ok = PerformanceMonitor.start_monitoring(:lifecycle_agent)

      # Verify monitoring is active
      assert {:ok, true} = PerformanceMonitor.monitoring?(:lifecycle_agent)

      # Stop monitoring
      assert :ok = PerformanceMonitor.stop_monitoring(:lifecycle_agent)

      # Verify monitoring is stopped
      assert {:ok, false} = PerformanceMonitor.monitoring?(:lifecycle_agent)
    end

    test "provides monitoring status for all agents" do
      # Setup multiple agents
      agents = [:status_agent1, :status_agent2, :status_agent3]

      Enum.each(agents, fn agent_id ->
        agent_config = %{
          id: agent_id,
          type: :worker,
          module: Foundation.TestHelpers.TestWorker,
          capabilities: [:status_testing]
        }

        Agent.register_agent(agent_config)
      end)

      # Start monitoring for some agents, explicitly mark status_agent2 as not monitored
      PerformanceMonitor.start_monitoring(:status_agent1)
      PerformanceMonitor.start_monitoring(:status_agent2)
      # Set to unmonitored state
      PerformanceMonitor.stop_monitoring(:status_agent2)
      PerformanceMonitor.start_monitoring(:status_agent3)

      # Get monitoring status
      status = PerformanceMonitor.get_monitoring_status()

      assert status.total_agents == 3
      assert status.monitored_agents == 2
      assert status.unmonitored_agents == 1
      assert :status_agent1 in status.agent_status[:monitored]
      assert :status_agent3 in status.agent_status[:monitored]
      assert :status_agent2 in status.agent_status[:unmonitored]
    end
  end

  describe "metrics export and reporting" do
    test "exports metrics in different formats" do
      # Setup agent with metrics
      agent_config = %{
        id: :export_agent,
        type: :worker,
        module: Foundation.TestHelpers.TestWorker,
        capabilities: [:export_testing]
      }

      assert :ok = Agent.register_agent(agent_config)

      # Start monitoring the agent
      assert :ok = PerformanceMonitor.start_monitoring(:export_agent)

      metrics = %{
        cpu_usage: 0.6,
        memory_usage: 512 * 1024 * 1024,
        throughput: 15.0,
        error_rate: 0.01
      }

      :ok = PerformanceMonitor.record_metrics(:export_agent, metrics)

      # Test JSON export
      {:ok, json_data} = PerformanceMonitor.export_metrics(:json)
      assert is_binary(json_data)
      parsed_data = Jason.decode!(json_data)
      assert is_map(parsed_data)
      assert Map.has_key?(parsed_data, "agents")

      # Test CSV export
      {:ok, csv_data} = PerformanceMonitor.export_metrics(:csv)
      assert is_binary(csv_data)
      assert String.contains?(csv_data, "agent_id,cpu_usage,memory_usage")

      # Test map export (for programmatic use)
      {:ok, map_data} = PerformanceMonitor.export_metrics(:map)
      assert is_map(map_data)
      assert Map.has_key?(map_data, :agents)
      assert Map.has_key?(map_data, :statistics)
      assert Map.has_key?(map_data, :exported_at)
    end
  end

  # Helper functions
  defp cleanup_test_agents do
    try do
      # Get all agents and clean them up
      agents = Agent.list_agents()

      for agent <- agents do
        case agent.id do
          id when is_atom(id) ->
            case Atom.to_string(id) do
              "perf_" <> _ -> Agent.unregister_agent(id)
              "time_series_" <> _ -> Agent.unregister_agent(id)
              "high_cpu_" <> _ -> Agent.unregister_agent(id)
              "low_throughput_" <> _ -> Agent.unregister_agent(id)
              "alert_resolution_" <> _ -> Agent.unregister_agent(id)
              "lifecycle_" <> _ -> Agent.unregister_agent(id)
              "status_agent" <> _ -> Agent.unregister_agent(id)
              "export_" <> _ -> Agent.unregister_agent(id)
              "agent" <> _ -> Agent.unregister_agent(id)
              _ -> :ok
            end

          _ ->
            :ok
        end
      end
    rescue
      _ -> :ok
    end
  end
end
