defmodule Foundation.Types.ErrorConsolidationTest do
  @moduledoc """
  Tests for consolidating EnhancedError functionality into the base Error module.

  Validates that the enhanced error capabilities (error chains, MABEAM-specific
  error codes, distributed error context) can be properly integrated into the
  unified Foundation.Types.Error module.
  """
  use ExUnit.Case, async: true

  alias Foundation.Types.Error

  describe "error code compatibility" do
    test "basic error codes are preserved from current Error module" do
      # Test existing basic error creation still works
      basic_error = %Error{
        code: 1001,
        error_type: :validation_failed,
        message: "Invalid configuration",
        severity: :high
      }

      assert basic_error.code == 1001
      assert basic_error.error_type == :validation_failed
      assert basic_error.severity == :high
    end

    test "enhanced error codes should be supported in consolidated module" do
      # These error definitions exist in EnhancedError and should be available
      # in the consolidated Error module

      # Agent Management Errors (5000-5999)
      agent_start_error = %Error{
        code: 5001,
        error_type: :agent_start_failed,
        message: "Agent failed to start",
        severity: :high,
        category: :agent,
        subcategory: :lifecycle
      }

      assert agent_start_error.code == 5001
      assert agent_start_error.error_type == :agent_start_failed

      # Coordination Errors (6000-6999)
      consensus_error = %Error{
        code: 6001,
        error_type: :consensus_failed,
        message: "Consensus algorithm failed to reach agreement",
        severity: :high,
        category: :coordination,
        subcategory: :consensus
      }

      assert consensus_error.code == 6001
      assert consensus_error.error_type == :consensus_failed

      # Orchestration Errors (7000-7999)
      variable_error = %Error{
        code: 7001,
        error_type: :variable_not_found,
        message: "Variable not found in scope",
        severity: :medium,
        category: :orchestration,
        subcategory: :variable
      }

      assert variable_error.code == 7001
      assert variable_error.error_type == :variable_not_found
    end
  end

  describe "enhanced error features" do
    test "error chains should be supported in consolidated module" do
      # Test error chaining capability from EnhancedError
      root_error = %Error{
        code: 1001,
        error_type: :config_invalid,
        message: "Configuration validation failed",
        severity: :medium
      }

      derived_error = %Error{
        code: 5001,
        error_type: :agent_start_failed,
        message: "Could not start agent due to configuration error",
        severity: :high,
        caused_by: root_error,
        correlation_id: "test-correlation-123"
      }

      assert derived_error.caused_by == root_error
      assert derived_error.correlation_id == "test-correlation-123"
    end

    test "distributed error context should be supported" do
      # Test distributed error features from EnhancedError
      distributed_error = %Error{
        code: 8001,
        error_type: :distributed_coordination_failed,
        message: "Failed to coordinate across nodes",
        severity: :high,
        context: %{
          node_id: :node1,
          cluster_state: :degraded,
          participating_nodes: [:node1, :node2, :node3],
          failed_nodes: [:node2]
        },
        distributed_context: %{
          originating_node: :node1,
          propagation_path: [:node1, :node2, :node3],
          cluster_view: %{total_nodes: 3, active_nodes: 2}
        }
      }

      assert distributed_error.context.node_id == :node1
      assert distributed_error.distributed_context.originating_node == :node1
      assert length(distributed_error.distributed_context.propagation_path) == 3
    end

    test "service and telemetry error codes should be supported" do
      # Service Errors (8000-8999)
      service_error = %Error{
        code: 8001,
        error_type: :service_unavailable,
        message: "Required service is not available",
        severity: :high,
        category: :service,
        subcategory: :availability
      }

      assert service_error.code == 8001
      assert service_error.category == :service

      # Distributed System Errors (9000-9999)
      partition_error = %Error{
        code: 9001,
        error_type: :network_partition,
        message: "Network partition detected",
        severity: :critical,
        category: :distributed,
        subcategory: :network
      }

      assert partition_error.code == 9001
      assert partition_error.severity == :critical
    end
  end

  describe "error recovery and retry strategies" do
    test "enhanced retry strategies should be preserved" do
      # Test enhanced retry capabilities
      retryable_error = %Error{
        code: 5002,
        error_type: :agent_stop_failed,
        message: "Agent failed to stop gracefully",
        severity: :medium,
        retry_strategy: :exponential_backoff,
        retry_count: 3,
        max_retries: 5,
        retry_context: %{
          base_delay: 1000,
          max_delay: 30000,
          backoff_factor: 2
        }
      }

      assert retryable_error.retry_strategy == :exponential_backoff
      assert retryable_error.retry_count == 3
      assert retryable_error.retry_context.base_delay == 1000
    end
  end

  describe "error creation helpers" do
    test "should support both basic and enhanced error creation patterns" do
      # Basic error creation (existing pattern)
      basic_error = %Error{
        code: 1001,
        error_type: :validation_failed,
        message: "Basic validation error",
        severity: :medium
      }

      assert basic_error.code == 1001

      # Enhanced error creation with full context
      enhanced_error = %Error{
        code: 6001,
        error_type: :consensus_failed,
        message: "Consensus failed in distributed coordination",
        severity: :high,
        category: :coordination,
        subcategory: :consensus,
        context: %{
          participants: [:agent1, :agent2, :agent3],
          protocol: :raft,
          round: 5
        },
        timestamp: DateTime.utc_now(),
        correlation_id: "consensus-round-5",
        retry_strategy: :fixed_delay,
        max_retries: 3
      }

      assert enhanced_error.code == 6001
      assert enhanced_error.category == :coordination
      assert enhanced_error.context.protocol == :raft
      assert enhanced_error.retry_strategy == :fixed_delay
    end
  end

  describe "backward compatibility" do
    test "existing Foundation.Error usage patterns should continue working" do
      # Test that existing error handling patterns are preserved
      # This ensures no breaking changes for current Foundation usage

      # Current Foundation.Error patterns should work
      config_error = %Error{
        code: 1001,
        error_type: :config_invalid,
        message: "Invalid configuration provided",
        severity: :high
      }

      system_error = %Error{
        code: 2001,
        error_type: :system_failure,
        message: "System component failed",
        severity: :critical
      }

      data_error = %Error{
        code: 3001,
        error_type: :data_corruption,
        message: "Data integrity check failed",
        severity: :high
      }

      external_error = %Error{
        code: 4001,
        error_type: :external_service_timeout,
        message: "External service request timed out",
        severity: :medium
      }

      # All should be valid Error structs
      assert %Error{} = config_error
      assert %Error{} = system_error
      assert %Error{} = data_error
      assert %Error{} = external_error

      # Code ranges should be preserved
      assert config_error.code >= 1000 and config_error.code < 2000
      assert system_error.code >= 2000 and system_error.code < 3000
      assert data_error.code >= 3000 and data_error.code < 4000
      assert external_error.code >= 4000 and external_error.code < 5000
    end
  end
end
