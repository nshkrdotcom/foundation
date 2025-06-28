defmodule Foundation.Services.AgentTelemetryServiceTest do
  use ExUnit.Case, async: false

  alias Foundation.Services.TelemetryService
  alias Foundation.ProcessRegistry
  alias Foundation.Types.AgentInfo

  setup do
    namespace = {:test, make_ref()}
    
    # Start TelemetryService with test configuration
    {:ok, _pid} = TelemetryService.start_link([
      aggregation_interval: 100,  # Fast aggregation for testing
      metric_retention_days: 1,
      alert_thresholds: %{
        memory_usage: %{warning: 0.8, critical: 0.9},
        cpu_usage: %{warning: 0.7, critical: 0.85},
        error_rate: %{warning: 0.05, critical: 0.1}
      },
      namespace: namespace
    ])

    # Register test agents
    agents = [
      {:ml_agent_1, [:inference, :classification], :healthy},
      {:ml_agent_2, [:training, :inference], :healthy},
      {:coord_agent, [:coordination], :healthy}
    ]

    for {agent_id, capabilities, health} <- agents do
      pid = spawn(fn -> Process.sleep(2000) end)
      metadata = %AgentInfo{
        id: agent_id,
        type: :ml_agent,
        capabilities: capabilities,
        health: health,
        resource_usage: %{memory: 0.5, cpu: 0.3}
      }
      ProcessRegistry.register_agent(namespace, agent_id, pid, metadata)
    end

    on_exit(fn ->
      try do
        TelemetryService.clear_all_metrics()
        for {agent_id, _, _} <- agents do
          ProcessRegistry.unregister(namespace, agent_id)
        end
      rescue
        _ -> :ok
      end
    end)

    {:ok, namespace: namespace}
  end

  describe "agent-specific metrics collection" do
    test "records agent performance metrics with context", %{namespace: namespace} do
      # Record various agent metrics
      TelemetryService.record_metric(
        [:foundation, :agent, :task_duration],
        250.5,
        :histogram,
        %{
          agent_id: :ml_agent_1,
          task_type: :inference,
          model: "gpt-4",
          namespace: namespace
        }
      )

      TelemetryService.record_metric(
        [:foundation, :agent, :memory_usage],
        0.75,
        :gauge,
        %{
          agent_id: :ml_agent_1,
          namespace: namespace
        }
      )

      TelemetryService.record_metric(
        [:foundation, :agent, :error_count],
        1,
        :counter,
        %{
          agent_id: :ml_agent_1,
          error_type: "timeout",
          namespace: namespace
        }
      )

      # Trigger aggregation
      TelemetryService.trigger_aggregation()

      # Query aggregated metrics for agent
      {:ok, metrics} = TelemetryService.get_aggregated_metrics(%{
        agent_id: :ml_agent_1,
        namespace: namespace
      })

      assert length(metrics) >= 3

      # Verify task duration metric
      duration_metric = Enum.find(metrics, &(&1.name == [:foundation, :agent, :task_duration]))
      assert duration_metric != nil
      assert duration_metric.type == :histogram
      assert duration_metric.agent_context.agent_id == :ml_agent_1
      assert duration_metric.agent_context.task_type == :inference

      # Verify memory usage metric
      memory_metric = Enum.find(metrics, &(&1.name == [:foundation, :agent, :memory_usage]))
      assert memory_metric != nil
      assert memory_metric.last_value == 0.75
      assert memory_metric.type == :gauge

      # Verify error counter
      error_metric = Enum.find(metrics, &(&1.name == [:foundation, :agent, :error_count]))
      assert error_metric != nil
      assert error_metric.total_count >= 1
      assert error_metric.type == :counter
    end

    test "enriches metrics with agent metadata on collection", %{namespace: namespace} do
      # Record metric with minimal context
      TelemetryService.record_metric(
        [:foundation, :agent, :inference_latency],
        120.0,
        :histogram,
        %{agent_id: :ml_agent_1, namespace: namespace}
      )

      TelemetryService.trigger_aggregation()

      {:ok, [metric]} = TelemetryService.get_aggregated_metrics(%{
        metric_name: [:foundation, :agent, :inference_latency],
        namespace: namespace
      })

      # Should be enriched with agent metadata from ProcessRegistry
      assert metric.agent_metadata != nil
      assert metric.agent_metadata.capabilities == [:inference, :classification]
      assert metric.agent_metadata.health == :healthy
      assert metric.agent_metadata.type == :ml_agent
    end

    test "handles metrics for unknown agents gracefully", %{namespace: namespace} do
      # Record metric for unknown agent
      TelemetryService.record_metric(
        [:foundation, :agent, :unknown_metric],
        42.0,
        :gauge,
        %{agent_id: :unknown_agent, namespace: namespace}
      )

      TelemetryService.trigger_aggregation()

      {:ok, [metric]} = TelemetryService.get_aggregated_metrics(%{
        agent_id: :unknown_agent,
        namespace: namespace
      })

      assert metric.agent_id == :unknown_agent
      assert metric.agent_metadata == nil  # No metadata for unknown agent
      assert metric.last_value == 42.0
    end
  end

  describe "agent-specific alerting" do
    test "creates and triggers alerts based on agent thresholds", %{namespace: namespace} do
      # Create agent-specific alert
      alert_spec = %{
        name: :agent_high_memory,
        metric_path: [:foundation, :agent, :memory_usage],
        agent_id: :ml_agent_1,
        threshold: 0.9,
        condition: :greater_than,
        severity: :warning
      }

      assert :ok = TelemetryService.create_alert(alert_spec)

      # Set up alert handler
      alerts_received = Agent.start_link(fn -> [] end)
      TelemetryService.register_alert_handler(fn alert ->
        Agent.update(alerts_received, fn acc -> [alert | acc] end)
      end)

      # Record high memory usage
      TelemetryService.record_metric(
        [:foundation, :agent, :memory_usage],
        0.95,  # Above threshold
        :gauge,
        %{agent_id: :ml_agent_1, namespace: namespace}
      )

      # Trigger aggregation and alert evaluation
      TelemetryService.trigger_aggregation()
      Process.sleep(50)  # Allow alert processing

      # Verify alert was triggered
      captured_alerts = Agent.get(alerts_received, & &1)
      assert length(captured_alerts) > 0

      memory_alert = Enum.find(captured_alerts, &(&1.alert_name == :agent_high_memory))
      assert memory_alert != nil
      assert memory_alert.agent_id == :ml_agent_1
      assert memory_alert.current_value == 0.95
      assert memory_alert.threshold == 0.9
      assert memory_alert.severity == :warning
    end

    test "escalates alerts to critical when thresholds are exceeded", %{namespace: namespace} do
      # Create multi-level alert
      warning_alert = %{
        name: :agent_cpu_warning,
        metric_path: [:foundation, :agent, :cpu_usage],
        agent_id: :ml_agent_2,
        threshold: 0.7,
        condition: :greater_than,
        severity: :warning
      }

      critical_alert = %{
        name: :agent_cpu_critical,
        metric_path: [:foundation, :agent, :cpu_usage],
        agent_id: :ml_agent_2,
        threshold: 0.85,
        condition: :greater_than,
        severity: :critical
      }

      TelemetryService.create_alert(warning_alert)
      TelemetryService.create_alert(critical_alert)

      alerts_received = Agent.start_link(fn -> [] end)
      TelemetryService.register_alert_handler(fn alert ->
        Agent.update(alerts_received, fn acc -> [alert | acc] end)
      end)

      # Record critical CPU usage
      TelemetryService.record_metric(
        [:foundation, :agent, :cpu_usage],
        0.9,  # Above both thresholds
        :gauge,
        %{agent_id: :ml_agent_2, namespace: namespace}
      )

      TelemetryService.trigger_aggregation()
      Process.sleep(50)

      captured_alerts = Agent.get(alerts_received, & &1)
      
      # Should have both warning and critical alerts
      warning = Enum.find(captured_alerts, &(&1.severity == :warning))
      critical = Enum.find(captured_alerts, &(&1.severity == :critical))
      
      assert warning != nil
      assert critical != nil
      assert critical.current_value == 0.9
    end

    test "provides capability-based alerting", %{namespace: namespace} do
      # Create alert for all inference agents
      inference_alert = %{
        name: :inference_agents_high_latency,
        metric_path: [:foundation, :agent, :inference_latency],
        agent_capabilities: [:inference],
        threshold: 500.0,
        condition: :greater_than,
        severity: :warning
      }

      TelemetryService.create_alert(inference_alert)

      alerts_received = Agent.start_link(fn -> [] end)
      TelemetryService.register_alert_handler(fn alert ->
        Agent.update(alerts_received, fn acc -> [alert | acc] end)
      end)

      # Record high latency for inference agents
      for agent_id <- [:ml_agent_1, :ml_agent_2] do  # Both have inference capability
        TelemetryService.record_metric(
          [:foundation, :agent, :inference_latency],
          600.0,  # Above threshold
          :histogram,
          %{agent_id: agent_id, namespace: namespace}
        )
      end

      # Record normal latency for coordination agent (no inference capability)
      TelemetryService.record_metric(
        [:foundation, :agent, :inference_latency],
        300.0,  # Below threshold
        :histogram,
        %{agent_id: :coord_agent, namespace: namespace}
      )

      TelemetryService.trigger_aggregation()
      Process.sleep(50)

      captured_alerts = Agent.get(alerts_received, & &1)
      
      # Should have alerts for inference agents only
      inference_alerts = Enum.filter(captured_alerts, &(&1.alert_name == :inference_agents_high_latency))
      assert length(inference_alerts) == 2
      
      alert_agents = Enum.map(inference_alerts, & &1.agent_id)
      assert :ml_agent_1 in alert_agents
      assert :ml_agent_2 in alert_agents
      refute :coord_agent in alert_agents
    end
  end

  describe "metrics aggregation and analysis" do
    test "aggregates metrics across time windows", %{namespace: namespace} do
      # Generate metrics over time
      base_time = System.monotonic_time(:microsecond)
      
      for i <- 1..20 do
        TelemetryService.record_metric(
          [:foundation, :agent, :request_rate],
          50 + i,  # Increasing rate
          :gauge,
          %{
            agent_id: :ml_agent_1,
            timestamp: base_time + (i * 1000),  # 1ms intervals
            namespace: namespace
          }
        )
      end

      TelemetryService.trigger_aggregation()

      # Get time-series data
      {:ok, time_series} = TelemetryService.get_metric_time_series(
        [:foundation, :agent, :request_rate],
        %{
          agent_id: :ml_agent_1,
          start_time: base_time,
          end_time: base_time + 25000,
          granularity: :second,
          namespace: namespace
        }
      )

      assert length(time_series) > 0
      
      # Verify aggregation includes statistical measures
      first_point = hd(time_series)
      assert Map.has_key?(first_point, :avg_value)
      assert Map.has_key?(first_point, :min_value)
      assert Map.has_key?(first_point, :max_value)
      assert Map.has_key?(first_point, :count)
      assert first_point.agent_id == :ml_agent_1
    end

    test "provides cross-agent metric comparison", %{namespace: namespace} do
      # Record same metric type for different agents
      agents_data = [
        {:ml_agent_1, 0.85},  # High CPU
        {:ml_agent_2, 0.45},  # Medium CPU
        {:coord_agent, 0.25}  # Low CPU
      ]

      for {agent_id, cpu_usage} <- agents_data do
        TelemetryService.record_metric(
          [:foundation, :agent, :cpu_utilization],
          cpu_usage,
          :gauge,
          %{agent_id: agent_id, namespace: namespace}
        )
      end

      TelemetryService.trigger_aggregation()

      # Get cross-agent comparison
      {:ok, comparison} = TelemetryService.get_cross_agent_metrics(
        [:foundation, :agent, :cpu_utilization],
        %{namespace: namespace}
      )

      assert length(comparison.agent_metrics) == 3
      
      # Should be sorted by value (highest first)
      [highest, medium, lowest] = comparison.agent_metrics
      assert highest.agent_id == :ml_agent_1
      assert highest.current_value == 0.85
      assert lowest.agent_id == :coord_agent
      assert lowest.current_value == 0.25

      # Should include statistical summary
      assert comparison.statistics.avg_value ≈ 0.52  # (0.85 + 0.45 + 0.25) / 3
      assert comparison.statistics.max_value == 0.85
      assert comparison.statistics.min_value == 0.25
    end

    test "calculates metric correlations between agents", %{namespace: namespace} do
      # Generate correlated metrics (when agent 1 CPU goes up, agent 2 memory goes up)
      for i <- 1..10 do
        cpu_usage = 0.3 + (i * 0.05)  # 0.35 to 0.8
        memory_usage = 0.4 + (i * 0.04)  # 0.44 to 0.76

        TelemetryService.record_metric(
          [:foundation, :agent, :cpu_usage],
          cpu_usage,
          :gauge,
          %{agent_id: :ml_agent_1, timestamp: i, namespace: namespace}
        )

        TelemetryService.record_metric(
          [:foundation, :agent, :memory_usage],
          memory_usage,
          :gauge,
          %{agent_id: :ml_agent_2, timestamp: i, namespace: namespace}
        )
      end

      TelemetryService.trigger_aggregation()

      # Calculate correlation
      {:ok, correlation} = TelemetryService.get_metric_correlation(
        {[:foundation, :agent, :cpu_usage], :ml_agent_1},
        {[:foundation, :agent, :memory_usage], :ml_agent_2},
        %{namespace: namespace}
      )

      assert correlation.correlation_coefficient > 0.9  # Strong positive correlation
      assert correlation.sample_size == 10
      assert correlation.significance_level < 0.05  # Statistically significant
    end
  end

  describe "agent health metric integration" do
    test "automatically tracks agent health changes", %{namespace: namespace} do
      # Update agent health in ProcessRegistry
      degraded_metadata = %AgentInfo{
        id: :ml_agent_1,
        type: :ml_agent,
        capabilities: [:inference, :classification],
        health: :degraded,
        resource_usage: %{memory: 0.85, cpu: 0.7}
      }

      ProcessRegistry.update_agent_metadata(namespace, :ml_agent_1, degraded_metadata)

      # TelemetryService should automatically detect and record health change
      Process.sleep(150)  # Allow health monitoring cycle

      {:ok, health_metrics} = TelemetryService.get_aggregated_metrics(%{
        metric_name: [:foundation, :agent, :health_status],
        agent_id: :ml_agent_1,
        namespace: namespace
      })

      assert length(health_metrics) > 0
      
      health_metric = hd(health_metrics)
      assert health_metric.current_value == "degraded"
      assert health_metric.agent_context.health == :degraded
    end

    test "correlates performance metrics with health changes", %{namespace: namespace} do
      agent_id = :ml_agent_2

      # Record performance metrics before health change
      for _i <- 1..5 do
        TelemetryService.record_metric(
          [:foundation, :agent, :task_duration],
          200.0,  # Good performance
          :histogram,
          %{agent_id: agent_id, namespace: namespace}
        )
      end

      # Change agent health
      unhealthy_metadata = %AgentInfo{
        id: agent_id,
        type: :ml_agent,
        capabilities: [:training, :inference],
        health: :unhealthy,
        resource_usage: %{memory: 0.95, cpu: 0.9}
      }

      ProcessRegistry.update_agent_metadata(namespace, agent_id, unhealthy_metadata)
      Process.sleep(100)

      # Record performance metrics after health change
      for _i <- 1..5 do
        TelemetryService.record_metric(
          [:foundation, :agent, :task_duration],
          800.0,  # Degraded performance
          :histogram,
          %{agent_id: agent_id, namespace: namespace}
        )
      end

      TelemetryService.trigger_aggregation()

      # Analyze health-performance correlation
      {:ok, analysis} = TelemetryService.get_health_performance_analysis(
        agent_id,
        %{namespace: namespace}
      )

      assert analysis.performance_degradation_detected == true
      assert analysis.avg_performance_before < analysis.avg_performance_after
      assert analysis.health_change_timestamp != nil
      assert analysis.correlation_strength > 0.7  # Strong correlation
    end
  end

  describe "capability-based metric analysis" do
    test "aggregates metrics by agent capability groups", %{namespace: namespace} do
      # Record metrics for agents with different capabilities
      capability_metrics = [
        {[:ml_agent_1, :ml_agent_2], :inference, :inference_latency, 150.0},
        {[:ml_agent_1], :classification, :classification_accuracy, 0.95},
        {[:ml_agent_2], :training, :training_loss, 0.12},
        {[:coord_agent], :coordination, :consensus_time, 2.5}
      ]

      for {agent_ids, capability, metric_suffix, value} <- capability_metrics do
        for agent_id <- agent_ids do
          TelemetryService.record_metric(
            [:foundation, :agent, metric_suffix],
            value,
            :gauge,
            %{
              agent_id: agent_id,
              capability: capability,
              namespace: namespace
            }
          )
        end
      end

      TelemetryService.trigger_aggregation()

      # Get capability-grouped metrics
      {:ok, capability_groups} = TelemetryService.get_metrics_by_capability(%{
        namespace: namespace
      })

      assert Map.has_key?(capability_groups, :inference)
      assert Map.has_key?(capability_groups, :classification)
      assert Map.has_key?(capability_groups, :training)
      assert Map.has_key?(capability_groups, :coordination)

      # Verify inference capability group
      inference_group = capability_groups[:inference]
      assert length(inference_group.agents) == 2
      assert :ml_agent_1 in inference_group.agent_ids
      assert :ml_agent_2 in inference_group.agent_ids
      
      # Should have aggregated statistics
      assert inference_group.avg_inference_latency == 150.0
      assert inference_group.agent_count == 2
    end

    test "identifies capability performance outliers", %{namespace: namespace} do
      # Create inference agents with varying performance
      inference_agents = [
        {:fast_agent, 100.0},    # Fast
        {:normal_agent_1, 200.0}, # Normal
        {:normal_agent_2, 220.0}, # Normal
        {:slow_agent, 800.0}     # Outlier - slow
      ]

      for {agent_id, latency} <- inference_agents do
        # Register agent first
        pid = spawn(fn -> Process.sleep(1000) end)
        metadata = %AgentInfo{
          id: agent_id,
          type: :ml_agent,
          capabilities: [:inference],
          health: :healthy
        }
        ProcessRegistry.register_agent(namespace, agent_id, pid, metadata)

        # Record performance metric
        TelemetryService.record_metric(
          [:foundation, :agent, :inference_latency],
          latency,
          :histogram,
          %{agent_id: agent_id, namespace: namespace}
        )
      end

      TelemetryService.trigger_aggregation()

      # Identify outliers within inference capability
      {:ok, outliers} = TelemetryService.get_capability_outliers(
        :inference,
        [:foundation, :agent, :inference_latency],
        %{namespace: namespace}
      )

      assert length(outliers.slow_outliers) == 1
      assert hd(outliers.slow_outliers).agent_id == :slow_agent
      assert hd(outliers.slow_outliers).deviation_factor > 2.0  # Significantly slower

      assert length(outliers.fast_outliers) == 1
      assert hd(outliers.fast_outliers).agent_id == :fast_agent
    end
  end

  describe "real-time metric streaming" do
    test "streams metrics in real-time for monitoring dashboards", %{namespace: namespace} do
      # Start metric stream
      {:ok, stream_pid} = TelemetryService.start_metric_stream(%{
        agent_id: :ml_agent_1,
        metric_patterns: [[:foundation, :agent, :*]],
        buffer_size: 5,
        namespace: namespace
      })

      # Collect streamed metrics
      metrics_received = Agent.start_link(fn -> [] end)
      
      TelemetryService.register_stream_handler(stream_pid, fn metric ->
        Agent.update(metrics_received, fn acc -> [metric | acc] end)
      end)

      # Generate metrics rapidly
      for i <- 1..3 do
        TelemetryService.record_metric(
          [:foundation, :agent, :live_metric],
          i * 10.0,
          :gauge,
          %{agent_id: :ml_agent_1, sequence: i, namespace: namespace}
        )
        
        Process.sleep(20)
      end

      # Wait for streaming
      Process.sleep(100)

      # Verify metrics were streamed
      received = Agent.get(metrics_received, & &1)
      assert length(received) == 3
      
      # Should maintain order
      sequences = received |> Enum.reverse() |> Enum.map(&(&1.metadata.sequence))
      assert sequences == [1, 2, 3]
    end

    test "provides filtered metric streams by agent capabilities", %{namespace: namespace} do
      # Start stream for inference agents only
      {:ok, stream_pid} = TelemetryService.start_capability_metric_stream(%{
        capabilities: [:inference],
        metric_patterns: [[:foundation, :agent, :task_*]],
        namespace: namespace
      })

      metrics_received = Agent.start_link(fn -> [] end)
      
      TelemetryService.register_stream_handler(stream_pid, fn metric ->
        Agent.update(metrics_received, fn acc -> [metric | acc] end)
      end)

      # Record metrics for different agent types
      TelemetryService.record_metric(
        [:foundation, :agent, :task_completed],
        1,
        :counter,
        %{agent_id: :ml_agent_1, namespace: namespace}  # Has inference capability
      )

      TelemetryService.record_metric(
        [:foundation, :agent, :task_completed],
        1,
        :counter,
        %{agent_id: :coord_agent, namespace: namespace}  # No inference capability
      )

      Process.sleep(50)

      # Should only receive metrics from inference agents
      received = Agent.get(metrics_received, & &1)
      assert length(received) == 1
      assert hd(received).agent_id == :ml_agent_1
    end
  end

  describe "metric retention and cleanup" do
    test "automatically cleans up old metrics based on retention policy" do
      # Record old metrics
      old_timestamp = System.os_time(:second) - (2 * 24 * 60 * 60)  # 2 days ago
      
      TelemetryService.record_metric(
        [:foundation, :agent, :old_metric],
        42.0,
        :gauge,
        %{
          agent_id: :ml_agent_1,
          timestamp: old_timestamp
        }
      )

      # Record recent metrics
      TelemetryService.record_metric(
        [:foundation, :agent, :recent_metric],
        84.0,
        :gauge,
        %{agent_id: :ml_agent_1}
      )

      TelemetryService.trigger_aggregation()

      # Run cleanup (retention: 1 day)
      TelemetryService.cleanup_old_metrics()

      # Query metrics - should only have recent ones
      {:ok, metrics} = TelemetryService.get_aggregated_metrics(%{
        agent_id: :ml_agent_1
      })

      metric_names = Enum.map(metrics, & &1.name)
      assert [:foundation, :agent, :recent_metric] in metric_names
      refute [:foundation, :agent, :old_metric] in metric_names
    end

    test "provides telemetry service health and statistics" do
      # Generate various metrics for statistics
      for i <- 1..50 do
        TelemetryService.record_metric(
          [:test, :metric],
          i,
          :counter,
          %{agent_id: :ml_agent_1}
        )
      end

      TelemetryService.trigger_aggregation()

      # Get service statistics
      {:ok, stats} = TelemetryService.get_service_statistics()

      assert stats.total_metrics_recorded >= 50
      assert stats.active_alerts_count >= 0
      assert stats.agents_being_monitored >= 1
      assert is_number(stats.avg_processing_latency_ms)
      assert is_number(stats.storage_size_bytes)
      assert Map.has_key?(stats.metrics_by_type, :counter)
    end
  end

  describe "error handling and resilience" do
    test "handles invalid metric data gracefully" do
      # Test with invalid metric values
      invalid_metrics = [
        {[:invalid, :metric], "not_a_number", :gauge},
        {[:another, :invalid], :infinity, :histogram},
        {[], 42.0, :gauge},  # Empty metric name
        {[:valid, :metric], 42.0, :invalid_type}  # Invalid type
      ]

      for {name, value, type} <- invalid_metrics do
        result = TelemetryService.record_metric(
          name,
          value,
          type,
          %{agent_id: :ml_agent_1}
        )
        
        assert {:error, _reason} = result
      end

      # Valid metric should still work
      result = TelemetryService.record_metric(
        [:valid, :metric],
        42.0,
        :gauge,
        %{agent_id: :ml_agent_1}
      )
      
      assert :ok = result
    end

    test "maintains metric integrity during high load" do
      # Generate high volume of concurrent metrics
      tasks = for i <- 1..100 do
        Task.async(fn ->
          TelemetryService.record_metric(
            [:load, :test],
            i,
            :counter,
            %{agent_id: :ml_agent_1, sequence: i}
          )
        end)
      end

      # Wait for all metrics to be recorded
      results = Task.await_many(tasks, 5000)
      
      # All should succeed
      assert Enum.all?(results, &(&1 == :ok))

      TelemetryService.trigger_aggregation()

      # Verify all metrics were recorded correctly
      {:ok, [metric]} = TelemetryService.get_aggregated_metrics(%{
        metric_name: [:load, :test],
        agent_id: :ml_agent_1
      })

      assert metric.total_count == 100
      # Sum should be 1+2+...+100 = 5050
      assert metric.total_value == 5050
    end
  end
end