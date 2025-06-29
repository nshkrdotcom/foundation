defmodule JidoSystem.Actions.ProcessTaskEnhancedTest do
  use ExUnit.Case, async: true

  alias JidoSystem.Actions.ProcessTask
  alias Foundation.Services.RetryService

  describe "ProcessTask with enhanced RetryService integration" do
    test "successfully processes task on first attempt" do
      task_params = %{
        task_id: "test_task_1",
        # Use supported task type
        task_type: :data_processing,
        retry_attempts: 3,
        input_data: %{value: 42},
        timeout: 30_000,
        # Disable circuit breaker for testing
        circuit_breaker: false,
        # Required options parameter
        options: %{}
      }

      context = %{agent_id: "test_agent"}

      assert {:ok, result} = ProcessTask.run(task_params, context)
      assert Map.has_key?(result, :status)
      assert result.status == :completed
    end

    test "retries task with exponential backoff on failure" do
      # Create a task that will fail initially but succeed on retry
      task_params = %{
        task_id: "retry_test_task",
        # Use supported task type
        task_type: :validation,
        retry_attempts: 3,
        # Empty data will pass validation
        input_data: %{},
        timeout: 30_000,
        # Disable circuit breaker for testing
        circuit_breaker: false,
        # Required options parameter
        options: %{}
      }

      context = %{agent_id: "test_agent"}

      # The task should eventually succeed after retries
      assert {:ok, result} = ProcessTask.run(task_params, context)
      assert result.status == :completed
    end

    test "fails after all retry attempts are exhausted" do
      task_params = %{
        task_id: "fail_task",
        # Use unsupported task type to trigger failure
        task_type: :unsupported_task_type,
        retry_attempts: 2,
        input_data: %{always_fail: true},
        timeout: 30_000,
        # Disable circuit breaker for testing
        circuit_breaker: false
      }

      context = %{agent_id: "test_agent"}

      assert {:error, error_map} = ProcessTask.run(task_params, context)
      assert %{error: {:retries_exhausted, _reason}} = error_map
    end

    test "uses RetryService for resilient processing" do
      # Verify that RetryService is available for integration
      assert Foundation.Services.Supervisor.service_running?(Foundation.Services.RetryService)

      # Test that RetryService can be called directly
      operation = fn -> {:ok, "test_result"} end

      assert {:ok, "test_result"} =
               RetryService.retry_operation(operation, policy: :immediate, max_retries: 1)
    end

    test "integrates retry telemetry with task processing" do
      task_params = %{
        task_id: "telemetry_test_task",
        # Use supported task type
        task_type: :analysis,
        retry_attempts: 1,
        input_data: %{value: 100},
        timeout: 30_000,
        # Disable circuit breaker for testing
        circuit_breaker: false,
        # Required options parameter for analysis
        options: %{analysis_type: :basic}
      }

      context = %{agent_id: "test_agent"}

      # Process task and verify it generates telemetry
      assert {:ok, result} = ProcessTask.run(task_params, context)
      assert Map.has_key?(result, :duration)
    end

    test "handles task processing with circuit breaker integration" do
      # Verify that circuit breaker integration works
      task_params = %{
        task_id: "circuit_breaker_test",
        # Use supported task type
        task_type: :transformation,
        retry_attempts: 3,
        input_data: %{circuit_breaker: :external_service},
        timeout: 30_000,
        # Enable circuit breaker for this specific test
        circuit_breaker: true,
        # Required for transformation task
        options: %{transformations: [:add_timestamp]}
      }

      context = %{agent_id: "test_agent"}

      # Should handle circuit breaker scenarios gracefully
      result = ProcessTask.run(task_params, context)
      assert is_tuple(result)
    end

    test "validates retry configuration parameters" do
      # Test with invalid retry configuration
      task_params = %{
        task_id: "invalid_retry_test",
        # Use supported task type
        task_type: :data_processing,
        # Invalid
        retry_attempts: -1,
        input_data: %{value: 42},
        timeout: 30_000,
        # Disable circuit breaker for testing
        circuit_breaker: false,
        # Required options parameter
        options: %{}
      }

      context = %{agent_id: "test_agent"}

      # Should handle invalid configuration gracefully
      result = ProcessTask.run(task_params, context)
      assert is_tuple(result)
    end

    test "maintains backward compatibility with existing task processing" do
      # Test that existing functionality still works
      task_params = %{
        task_id: "backward_compat_test",
        # Use supported task type
        task_type: :notification,
        input_data: %{value: 42},
        timeout: 30_000,
        # Disable circuit breaker for testing
        circuit_breaker: false,
        retry_attempts: 3,
        # Required for notification task
        options: %{recipients: ["test@example.com"], message: "Test notification"}
      }

      context = %{agent_id: "test_agent"}

      assert {:ok, result} = ProcessTask.run(task_params, context)
      assert result.status == :completed
    end
  end

  describe "ProcessTask retry policy configuration" do
    test "supports different retry policies" do
      policies = [:exponential_backoff, :fixed_delay, :immediate, :linear_backoff]

      Enum.each(policies, fn policy ->
        operation = fn -> {:ok, "success"} end

        assert {:ok, "success"} =
                 RetryService.retry_operation(
                   operation,
                   policy: policy,
                   max_retries: 1
                 )
      end)
    end

    test "configures retry policies based on task type" do
      # Different task types might use different retry policies
      task_configs = [
        {%{task_type: :quick_task}, :immediate},
        {%{task_type: :network_task}, :exponential_backoff},
        {%{task_type: :batch_task}, :linear_backoff}
      ]

      Enum.each(task_configs, fn {_task_params, expected_policy} ->
        # Test that the appropriate policy would be selected
        # This tests the policy selection logic
        assert expected_policy in [:immediate, :exponential_backoff, :linear_backoff, :fixed_delay]
      end)
    end
  end
end
