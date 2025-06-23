defmodule Foundation.MABEAM.SupportInfrastructureTest do
  @moduledoc """
  Tests for Phase 4 Step 3: Support Infrastructure

  Verifies that coordination helpers and telemetry helpers work correctly
  for comprehensive MABEAM system testing.
  """

  use ExUnit.Case, async: false

  alias Foundation.MABEAM.CoordinationHelpers
  alias Foundation.MABEAM.TelemetryHelpers

  setup do
    # Clean up any existing state
    on_exit(fn ->
      # Cleanup any test artifacts
      :ok
    end)

    :ok
  end

  describe "coordination helpers functionality" do
    test "creates consensus protocol with default settings" do
      protocol = CoordinationHelpers.create_consensus_protocol()

      assert protocol.name == :test_consensus
      assert protocol.type == :consensus
      assert protocol.algorithm == :majority_vote
      assert protocol.timeout == 5000
      assert protocol.confidence_threshold == 0.6
      assert protocol.metadata.created_for == :testing
    end

    test "creates negotiation protocol with custom options" do
      opts = [
        name: :custom_negotiation,
        algorithm: :resource_allocation,
        timeout: 15_000,
        rounds: 10
      ]

      protocol = CoordinationHelpers.create_negotiation_protocol(opts)

      assert protocol.name == :custom_negotiation
      assert protocol.algorithm == :resource_allocation
      assert protocol.timeout == 15_000
      assert protocol.rounds == 10
    end

    test "creates auction protocol with different auction types" do
      sealed_bid = CoordinationHelpers.create_auction_protocol(auction_type: :sealed_bid)
      english = CoordinationHelpers.create_auction_protocol(auction_type: :english)
      dutch = CoordinationHelpers.create_auction_protocol(auction_type: :dutch)

      assert sealed_bid.auction_type == :sealed_bid
      assert english.auction_type == :english
      assert dutch.auction_type == :dutch
    end

    test "creates agent behaviors for different coordination types" do
      agent_ids = [:agent1, :agent2, :agent3]

      # Test consensus behaviors
      consensus_behaviors = CoordinationHelpers.create_consensus_behaviors(agent_ids)
      assert length(consensus_behaviors) == 3

      for {agent_id, behavior} <- consensus_behaviors do
        assert agent_id in agent_ids
        assert behavior.type == :consensus
        assert behavior.vote in [:yes, :no]
        assert behavior.confidence >= 0.6 and behavior.confidence <= 0.9
        assert is_integer(behavior.response_delay)
      end

      # Test negotiation behaviors
      negotiation_behaviors = CoordinationHelpers.create_negotiation_behaviors(agent_ids)
      assert length(negotiation_behaviors) == 3

      for {agent_id, behavior} <- negotiation_behaviors do
        assert agent_id in agent_ids
        assert behavior.type == :negotiation
        assert behavior.strategy in [:aggressive, :moderate, :conservative]
        assert is_number(behavior.initial_offer)
        assert is_float(behavior.concession_rate)
      end

      # Test auction behaviors
      auction_behaviors = CoordinationHelpers.create_auction_behaviors(agent_ids)
      assert length(auction_behaviors) == 3

      for {agent_id, behavior} <- auction_behaviors do
        assert agent_id in agent_ids
        assert behavior.type == :auction
        assert behavior.strategy in [:aggressive, :strategic, :conservative]
        assert is_number(behavior.max_budget)
        assert is_integer(behavior.bid_increment)
      end
    end

    test "performance testing utilities work correctly" do
      # Create a simple mock coordination scenario
      protocol_name = :test_performance
      agent_ids = [:perf_agent1, :perf_agent2]
      context = %{test: true}

      # Test benchmark function structure (won't actually run coordination)
      result =
        CoordinationHelpers.benchmark_concurrent_coordination(
          protocol_name,
          agent_ids,
          context,
          # session_count
          3,
          timeout: 1000
        )

      # Verify result structure
      assert is_map(result)
      assert Map.has_key?(result, :success_rate)
      assert Map.has_key?(result, :avg_duration_ms)
      assert Map.has_key?(result, :total_time_ms)
      assert Map.has_key?(result, :successful_sessions)
      assert Map.has_key?(result, :failed_sessions)
      assert Map.has_key?(result, :results)

      assert is_float(result.success_rate)
      assert is_number(result.avg_duration_ms)
      assert is_integer(result.total_time_ms)
      assert is_list(result.results)
    end
  end

  describe "telemetry helpers functionality" do
    test "captures telemetry events correctly" do
      # Set up event capture
      test_events = [
        [:foundation, :mabeam, :test, :event1],
        [:foundation, :mabeam, :test, :event2]
      ]

      handler_id = TelemetryHelpers.capture_telemetry_events(test_events)

      # Emit test events
      :telemetry.execute([:foundation, :mabeam, :test, :event1], %{count: 1}, %{test: true})
      :telemetry.execute([:foundation, :mabeam, :test, :event2], %{count: 1}, %{test: true})

      # Wait for events
      assert {:ok, event1_data} =
               TelemetryHelpers.wait_for_telemetry_event(
                 [:foundation, :mabeam, :test, :event1],
                 1000
               )

      assert {:ok, event2_data} =
               TelemetryHelpers.wait_for_telemetry_event(
                 [:foundation, :mabeam, :test, :event2],
                 1000
               )

      # Verify event structure
      assert event1_data.event == [:foundation, :mabeam, :test, :event1]
      assert event1_data.measurements.count == 1
      assert event1_data.metadata.test == true
      assert is_integer(event1_data.timestamp)

      assert event2_data.event == [:foundation, :mabeam, :test, :event2]

      # Cleanup
      TelemetryHelpers.cleanup_telemetry_handler(handler_id)
    end

    test "waits for multiple telemetry events" do
      test_events = [
        [:foundation, :mabeam, :test, :multi1],
        [:foundation, :mabeam, :test, :multi2],
        [:foundation, :mabeam, :test, :multi3]
      ]

      handler_id = TelemetryHelpers.capture_telemetry_events(test_events)

      # Emit events in separate process to avoid blocking
      spawn(fn ->
        Process.sleep(50)
        :telemetry.execute([:foundation, :mabeam, :test, :multi1], %{count: 1}, %{})
        Process.sleep(50)
        :telemetry.execute([:foundation, :mabeam, :test, :multi2], %{count: 2}, %{})
        Process.sleep(50)
        :telemetry.execute([:foundation, :mabeam, :test, :multi3], %{count: 3}, %{})
      end)

      # Wait for all events
      assert {:ok, events} = TelemetryHelpers.wait_for_telemetry_events(test_events, 2000)

      assert length(events) == 3
      event_names = Enum.map(events, & &1.event)
      assert Enum.all?(test_events, fn event -> event in event_names end)

      # Cleanup
      TelemetryHelpers.cleanup_telemetry_handler(handler_id)
    end

    test "analyzes performance metrics from events" do
      # Create test events with performance data
      events = [
        %{
          event: [:test, :duration1],
          measurements: %{duration: 100, count: 1},
          metadata: %{result: :success},
          timestamp: 1_000_000
        },
        %{
          event: [:test, :duration2],
          measurements: %{duration_ms: 200, count: 2},
          metadata: %{result: :success},
          timestamp: 1_000_001
        },
        %{
          event: [:test, :counter],
          measurements: %{counter: 5},
          metadata: %{},
          timestamp: 1_000_002
        }
      ]

      metrics = TelemetryHelpers.analyze_performance_metrics(events)

      assert metrics.total_events == 3
      assert metrics.duration_events == 2
      # (100 + 200) / 2
      assert metrics.average_duration == 150.0
      assert metrics.min_duration == 100
      assert metrics.max_duration == 200
      # 1 + 2 + 5
      assert metrics.total_count == 8
      assert is_map(metrics.event_types)
    end

    test "calculates success rates from events" do
      # Create events with success/error indicators
      events = [
        %{
          event: [:test, :completed],
          measurements: %{},
          metadata: %{result: :success},
          timestamp: 1_000_000
        },
        %{
          event: [:test, :successful],
          measurements: %{},
          metadata: %{},
          timestamp: 1_000_001
        },
        %{
          event: [:test, :failed],
          measurements: %{},
          metadata: %{result: :error},
          timestamp: 1_000_002
        },
        %{
          event: [:test, :error],
          measurements: %{},
          metadata: %{},
          timestamp: 1_000_003
        }
      ]

      rates = TelemetryHelpers.calculate_success_rates(events)

      assert rates.total_events == 4
      # completed, successful
      assert rates.success_events == 2
      # failed, error
      assert rates.error_events == 2
      assert rates.success_rate == 0.5
      assert rates.error_rate == 0.5
    end

    test "extracts coordination-specific metrics" do
      events = [
        %{
          event: [:foundation, :mabeam, :coordination, :start],
          measurements: %{duration: 100},
          metadata: %{result: :success},
          timestamp: 1_000_000
        },
        %{
          event: [:foundation, :mabeam, :coordination, :complete],
          measurements: %{duration: 150},
          metadata: %{result: :success},
          timestamp: 1_000_001
        },
        %{
          event: [:foundation, :mabeam, :session, :created],
          measurements: %{},
          metadata: %{},
          timestamp: 1_000_002
        },
        %{
          event: [:foundation, :mabeam, :consensus, :reached],
          measurements: %{},
          metadata: %{},
          timestamp: 1_000_003
        }
      ]

      coord_metrics = TelemetryHelpers.extract_coordination_metrics(events)

      assert coord_metrics.coordination_events == 2
      assert coord_metrics.session_events == 1
      assert coord_metrics.consensus_events == 1
      # (100 + 150) / 2
      assert coord_metrics.avg_coordination_time == 125.0
      assert coord_metrics.coordination_success_rate == 1.0
    end

    test "verifies Foundation telemetry integration" do
      # Test events that follow Foundation patterns
      valid_events = [
        %{
          event: [:foundation, :mabeam, :test, :event],
          measurements: %{count: 1},
          metadata: %{test: true},
          timestamp: 1_000_000
        }
      ]

      invalid_events = [
        %{
          event: [:invalid, :event],
          measurements: %{},
          metadata: %{},
          timestamp: 1_000_000
        }
      ]

      assert :ok = TelemetryHelpers.verify_foundation_integration(valid_events)

      assert {:error, :no_foundation_events} =
               TelemetryHelpers.verify_foundation_integration(invalid_events)
    end

    test "measures telemetry overhead" do
      # Test operation that should generate minimal telemetry
      operation = fn ->
        Process.sleep(10)
        :test_result
      end

      overhead_metrics = TelemetryHelpers.measure_telemetry_overhead(operation)

      assert is_map(overhead_metrics)
      assert Map.has_key?(overhead_metrics, :execution_time_ms)
      assert Map.has_key?(overhead_metrics, :telemetry_events)
      assert Map.has_key?(overhead_metrics, :overhead_ratio)
      assert Map.has_key?(overhead_metrics, :result)

      assert is_number(overhead_metrics.execution_time_ms)
      assert is_integer(overhead_metrics.telemetry_events)
      assert is_number(overhead_metrics.overhead_ratio)
      assert overhead_metrics.result == :test_result
    end
  end

  describe "integration between coordination and telemetry helpers" do
    test "coordination helpers work with telemetry capture" do
      # Set up telemetry capture for coordination events
      handler_id = TelemetryHelpers.capture_all_mabeam_events()

      # Create a simple coordination protocol
      protocol = CoordinationHelpers.create_consensus_protocol(name: :integration_test)

      # The protocol creation itself doesn't emit events, but we can verify the structure
      assert protocol.name == :integration_test
      assert protocol.type == :consensus

      # Create agent behaviors
      agent_ids = [:integration_agent1, :integration_agent2]
      behaviors = CoordinationHelpers.create_consensus_behaviors(agent_ids)

      assert length(behaviors) == 2

      # Emit a test coordination event to verify telemetry capture
      :telemetry.execute(
        [:foundation, :mabeam, :coordination, :test_integration],
        %{duration: 100, agent_count: 2},
        %{protocol: :integration_test, result: :success}
      )

      # Verify event was captured
      assert {:ok, event_data} =
               TelemetryHelpers.wait_for_telemetry_event(
                 [:foundation, :mabeam, :coordination, :test_integration],
                 1000
               )

      assert event_data.measurements.duration == 100
      assert event_data.measurements.agent_count == 2
      assert event_data.metadata.protocol == :integration_test
      assert event_data.metadata.result == :success

      # Cleanup
      TelemetryHelpers.cleanup_telemetry_handler(handler_id)
    end

    test "performance testing with telemetry monitoring" do
      # This test demonstrates how coordination helpers and telemetry helpers
      # work together for comprehensive performance testing

      handler_id = TelemetryHelpers.capture_all_mabeam_events()

      # Simulate some coordination activity by emitting events
      for i <- 1..5 do
        :telemetry.execute(
          [:foundation, :mabeam, :coordination, :performance_test],
          %{duration: i * 10, count: 1},
          %{iteration: i, test: true}
        )
      end

      # Collect events with sufficient time for processing
      Process.sleep(200)
      events = TelemetryHelpers.collect_telemetry_events(100)

      # Filter for our test events
      test_events =
        Enum.filter(events, fn event ->
          event.event == [:foundation, :mabeam, :coordination, :performance_test]
        end)

      # Analyze performance - should have at least our 5 events
      metrics = TelemetryHelpers.analyze_performance_metrics(test_events)

      assert metrics.total_events >= 5
      assert metrics.average_duration > 0

      # Cleanup
      TelemetryHelpers.cleanup_telemetry_handler(handler_id)
    end
  end
end
