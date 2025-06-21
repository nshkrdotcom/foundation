# test/foundation/types/enhanced_error_test.exs
defmodule Foundation.Types.EnhancedErrorTest do
  use ExUnit.Case, async: true

  alias Foundation.Types.{Error, EnhancedError}

  describe "MABEAM error creation" do
    test "creates agent lifecycle error" do
      error = EnhancedError.new_enhanced(:agent_start_failed, "Custom message")

      assert %Error{} = error
      assert error.code == 5001
      assert error.message == "Custom message"
      assert error.severity == :high
      assert error.error_type == :agent_start_failed
    end

    test "creates agent lifecycle error with default message" do
      error = EnhancedError.new_enhanced(:agent_start_failed)

      assert %Error{} = error
      assert error.code == 5001
      assert error.message == "Agent failed to start"
      assert error.severity == :high
    end

    test "creates coordination consensus error" do
      error = EnhancedError.new_enhanced(:consensus_failed, "Consensus timeout")

      assert %Error{} = error
      assert error.code == 6001
      assert error.message == "Consensus timeout"
      assert error.severity == :high
    end

    test "creates orchestration variable error" do
      error = EnhancedError.new_enhanced(:variable_conflict, "Variable collision")

      assert %Error{} = error
      assert error.code == 7002
      assert error.message == "Variable collision"
      assert error.severity == :high
    end

    test "creates service lifecycle error" do
      error = EnhancedError.new_enhanced(:service_start_failed, "Service init failed")

      assert %Error{} = error
      assert error.code == 8001
      assert error.message == "Service init failed"
      assert error.severity == :critical
    end

    test "creates distributed network error" do
      error = EnhancedError.new_enhanced(:network_partition, "Split brain detected")

      assert %Error{} = error
      assert error.code == 9002
      assert error.message == "Split brain detected"
      assert error.severity == :critical
    end
  end

  describe "error creation with options" do
    test "creates error with custom context" do
      context = %{node: Node.self(), attempt: 3}

      error =
        EnhancedError.new_enhanced(
          :message_delivery_failed,
          "Failed to deliver",
          context: context
        )

      assert error.context == context
    end

    test "creates error with correlation ID" do
      correlation_id = "test-correlation-123"

      error =
        EnhancedError.new_enhanced(
          :negotiation_failed,
          "Negotiation timeout",
          correlation_id: correlation_id
        )

      assert error.correlation_id == correlation_id
    end
  end

  describe "error chains and correlation" do
    test "creates error chain" do
      errors = [
        EnhancedError.new_enhanced(:agent_start_failed),
        EnhancedError.new_enhanced(:dependency_unavailable)
      ]

      correlation = EnhancedError.create_error_chain(errors, "chain-123")

      assert correlation.correlation_id == "chain-123"
      assert length(correlation.causation_chain) == 2
      assert correlation.distributed_context.originating_node == Node.self()
    end

    test "adds error to existing chain" do
      initial_error = EnhancedError.new_enhanced(:consensus_failed)
      correlation = EnhancedError.create_error_chain([initial_error], "chain-456")

      new_error = EnhancedError.new_enhanced(:connection_lost)
      updated_correlation = EnhancedError.add_to_chain(correlation, new_error)

      assert length(updated_correlation.causation_chain) == 2
      assert updated_correlation.correlation_id == "chain-456"
    end
  end

  describe "error propagation" do
    test "propagates error across nodes" do
      error = EnhancedError.new_enhanced(:cluster_split)
      target_nodes = [Node.self()]

      {:ok, correlation} = EnhancedError.propagate_error(error, target_nodes)

      assert correlation.distributed_context.originating_node == Node.self()
      assert correlation.distributed_context.affected_nodes == target_nodes
      assert is_binary(correlation.correlation_id)
    end
  end

  describe "fallback for unknown error types" do
    test "handles unknown error type gracefully" do
      error = EnhancedError.new_enhanced(:unknown_error_type, "Unknown error")

      assert %Error{} = error
      assert error.code == 4999
      assert error.message == "Unknown error"
      assert error.error_type == :unknown_error_type
    end
  end

  describe "error categories and severity" do
    test "categorizes agent errors correctly" do
      agent_error = EnhancedError.new_enhanced(:agent_crashed)
      assert agent_error.code >= 5000 and agent_error.code < 6000
    end

    test "categorizes coordination errors correctly" do
      coord_error = EnhancedError.new_enhanced(:auction_failed)
      assert coord_error.code >= 6000 and coord_error.code < 7000
    end

    test "categorizes orchestration errors correctly" do
      orch_error = EnhancedError.new_enhanced(:resource_exhausted)
      assert orch_error.code >= 7000 and orch_error.code < 8000
    end

    test "categorizes service errors correctly" do
      service_error = EnhancedError.new_enhanced(:health_check_failed)
      assert service_error.code >= 8000 and service_error.code < 9000
    end

    test "categorizes distributed errors correctly" do
      dist_error = EnhancedError.new_enhanced(:state_corruption)
      assert dist_error.code >= 9000 and dist_error.code < 10000
    end
  end

  describe "integration with Foundation.Types.Error" do
    test "enhanced errors are compatible with base Error type" do
      error = EnhancedError.new_enhanced(:agent_not_found)

      # Should have all the base Error fields
      assert is_integer(error.code)
      assert is_atom(error.error_type)
      assert is_binary(error.message)
      assert error.severity in [:low, :medium, :high, :critical]
      assert is_struct(error.timestamp, DateTime)
      assert is_map(error.context)
    end

    test "enhanced errors work with standard error handling" do
      error = EnhancedError.new_enhanced(:service_crashed, "Service died")

      # Should be able to pattern match as Error
      case error do
        %Error{severity: :critical} -> assert true
        _ -> flunk("Should match as Error struct")
      end
    end
  end
end
