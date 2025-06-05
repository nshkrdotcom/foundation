defmodule Foundation.Types.ErrorTest do
  use ExUnit.Case, async: true

  alias Foundation.Error

  describe "Error.new/3" do
    test "with unknown error_type uses default 'Unknown error' definition" do
      unknown_error = Error.new(:non_existent_error_type)

      assert unknown_error.error_type == :non_existent_error_type
      assert unknown_error.message == "Unknown error"
      assert unknown_error.category == :unknown
      assert unknown_error.subcategory == :unknown
      assert unknown_error.code == 9999
    end

    test "sets correlation_id from opts" do
      correlation_id = "test-correlation-123"

      error =
        Error.new(
          :invalid_config_value,
          "Test message",
          correlation_id: correlation_id
        )

      assert error.correlation_id == correlation_id
    end

    test "sets correlation_id to nil when not provided in opts" do
      error =
        Error.new(
          :invalid_config_value,
          "Test message"
        )

      assert error.correlation_id == nil
    end
  end

  describe "Error.wrap_error/4" do
    test "for existing Error.t correctly preserves and enhances context" do
      # Create an initial error with some context
      original_error =
        Error.new(
          :invalid_config_value,
          "Original validation failed",
          context: %{
            field: "username",
            value: "invalid",
            nested: %{
              rules: ["required", "min_length"],
              metadata: %{source: "form"}
            }
          }
        )

      # Wrap the error with additional context
      result =
        Error.wrap_error(
          {:error, original_error},
          :service_unavailable,
          "Wrapped validation error",
          context: %{
            wrapper_info: "additional_data",
            nested: %{
              # This should be added
              rules: ["max_length"],
              wrapper_meta: "new_info"
            },
            new_field: "new_value"
          }
        )

      assert {:error, wrapped_error} = result

      # Verify the wrapped error maintains original structure with additional wrapper context
      # Original error type preserved
      assert wrapped_error.error_type == :invalid_config_value
      # Original message preserved
      assert wrapped_error.message == "Original validation failed"

      # Verify context includes wrapper information
      assert wrapped_error.context.wrapped_by == :service_unavailable
      assert wrapped_error.context.wrapper_message == "Wrapped validation error"
      assert wrapped_error.context.wrapper_context.wrapper_info == "additional_data"

      # Verify original context is preserved
      assert wrapped_error.context.field == "username"
      assert wrapped_error.context.value == "invalid"
    end

    test "handles raw error reasons" do
      result =
        Error.wrap_error(
          {:error, :some_reason},
          :service_unavailable,
          "Wrapped error"
        )

      assert {:error, wrapped_error} = result
      assert wrapped_error.error_type == :service_unavailable
      assert wrapped_error.message == "Wrapped error"
      assert wrapped_error.context.original_reason == :some_reason
    end
  end

  describe "Error.retry_delay/2" do
    test "handles attempt 0 for exponential_backoff" do
      error = Error.new(:network_error, "Network timeout")

      # Attempt 0 should return the base delay
      delay = Error.retry_delay(error, 0)

      # For exponential backoff, attempt 0 should return base delay (1000ms)
      assert is_integer(delay)
      assert delay == 1000
    end

    test "exponential_backoff increases delay with attempt number" do
      error = Error.new(:network_error, "Network timeout")

      delay_0 = Error.retry_delay(error, 0)
      delay_1 = Error.retry_delay(error, 1)
      delay_2 = Error.retry_delay(error, 2)

      # Each subsequent attempt should have higher delay
      assert delay_1 > delay_0
      assert delay_2 > delay_1

      # Should follow exponential pattern: 1000, 2000, 4000, etc. (capped at 30000)
      assert delay_0 == 1000
      assert delay_1 == 2000
      assert delay_2 == 4000
    end

    test "fixed_delay strategy provides consistent intervals" do
      error = Error.new(:external_service_error, "Service error")

      delay_1 = Error.retry_delay(error, 1)
      delay_2 = Error.retry_delay(error, 2)
      delay_3 = Error.retry_delay(error, 3)

      # Fixed delay should be consistent
      assert delay_1 == 1000
      assert delay_2 == 1000
      assert delay_3 == 1000
    end

    test "no_retry strategy returns infinity" do
      error = Error.new(:invalid_config_value, "Invalid config")

      delay = Error.retry_delay(error, 1)
      assert delay == :infinity
    end
  end

  describe "Error.determine_retry_strategy/2" do
    test "covers all defined error_types" do
      # Test network errors use exponential backoff
      network_error = Error.new(:network_error, "Network failed")
      assert network_error.retry_strategy == :exponential_backoff

      # Test timeout errors use exponential backoff
      timeout_error = Error.new(:timeout, "Request timed out")
      assert timeout_error.retry_strategy == :exponential_backoff

      # Test service errors use fixed delay for low/medium severity
      service_error = Error.new(:external_service_error, "Service error")
      assert service_error.retry_strategy == :fixed_delay

      # Test validation errors are not retryable
      validation_error = Error.new(:invalid_config_value, "Invalid input")
      assert validation_error.retry_strategy == :no_retry

      # Test data corruption errors are not retryable
      corruption_error = Error.new(:data_corruption, "Data corrupted")
      assert corruption_error.retry_strategy == :no_retry

      # Test resource exhaustion uses immediate retry
      resource_error = Error.new(:resource_exhausted, "Out of memory")
      assert resource_error.retry_strategy == :immediate
    end

    test "critical severity errors default to no_retry" do
      # Create an error that would normally be retryable but has critical severity
      # Since we can't directly control severity in new/3, we'll test the private function's logic
      # by creating errors and checking their retry strategy

      # Critical errors should not be retryable regardless of type
      critical_error = Error.new(:internal_error, "Critical system error")
      assert critical_error.retry_strategy == :no_retry
      assert critical_error.severity == :critical
    end
  end

  describe "Error.suggest_recovery_actions/2" do
    test "provides distinct actions for different error_types" do
      # Config validation errors
      config_error = Error.new(:invalid_config_value, "Invalid config")
      assert "Check configuration format" in config_error.recovery_actions
      assert "Validate against schema" in config_error.recovery_actions

      # Service availability errors
      service_error = Error.new(:service_unavailable, "Service down")
      assert "Check service health" in service_error.recovery_actions
      assert "Verify network connectivity" in service_error.recovery_actions

      # Resource errors
      resource_error = Error.new(:resource_exhausted, "Out of memory")
      assert "Check memory usage" in resource_error.recovery_actions
      assert "Scale resources if needed" in resource_error.recovery_actions

      # Timeout errors
      timeout_error = Error.new(:timeout, "Operation timed out")
      assert "Increase timeout value" in timeout_error.recovery_actions
      assert "Check network latency" in timeout_error.recovery_actions

      # Verify actions are distinct between error types
      assert config_error.recovery_actions != service_error.recovery_actions
      assert service_error.recovery_actions != resource_error.recovery_actions
      assert resource_error.recovery_actions != timeout_error.recovery_actions
    end

    test "includes context-specific suggestions when context provided" do
      error =
        Error.new(
          :invalid_config_value,
          "Field validation failed",
          context: %{operation: "user_registration"}
        )

      # Should include both general validation actions and context-specific ones
      assert "Review user_registration implementation" in error.recovery_actions
      assert length(error.recovery_actions) >= 3
    end

    test "handles unknown error types gracefully" do
      unknown_error = Error.new(:completely_unknown, "Unknown error")

      assert "Check logs for details" in unknown_error.recovery_actions
      assert "Review error context" in unknown_error.recovery_actions
      assert "Contact support if needed" in unknown_error.recovery_actions
    end
  end

  describe "Error.format_stacktrace/1" do
    test "handles empty stacktrace list" do
      error = Error.new(:test_error, "Test", stacktrace: [])

      # Should handle empty stacktrace gracefully
      assert error.stacktrace == []
    end

    test "handles nil stacktrace" do
      error = Error.new(:test_error, "Test", stacktrace: nil)

      assert error.stacktrace == nil
    end

    test "correctly formats standard stacktrace entries" do
      standard_stacktrace = [
        {MyModule, :my_function, 2, [file: "lib/my_module.ex", line: 10]},
        {AnotherModule, :another_function, 3, [file: "lib/another.ex", line: 25]},
        {ThirdModule, :third_function, 0, [file: "lib/third.ex", line: 5]}
      ]

      error = Error.new(:test_error, "Test", stacktrace: standard_stacktrace)

      assert is_list(error.stacktrace)
      assert length(error.stacktrace) == 3

      # Check first entry formatting
      first_entry = List.first(error.stacktrace)
      assert first_entry.module == MyModule
      assert first_entry.function == :my_function
      assert first_entry.arity == 2
      assert first_entry.file == "lib/my_module.ex"
      assert first_entry.line == 10
    end

    test "correctly formats entries not matching {M,F,A,L} tuple" do
      # Test various non-standard stacktrace entries
      irregular_stacktrace = [
        # Standard format
        {Module, :function, 2, [file: "test.ex", line: 42]},
        # String instead of tuple
        "string_entry",
        # Single atom tuple
        {:atom_only},
        # Non-tuple entry
        42
      ]

      error = Error.new(:test_error, "Test", stacktrace: irregular_stacktrace)

      assert is_list(error.stacktrace)
      assert length(error.stacktrace) == 4

      # First entry should be properly formatted
      first_entry = List.first(error.stacktrace)
      assert first_entry.module == Module
      assert first_entry.function == :function

      # Other entries should be converted to string representations
      assert Enum.at(error.stacktrace, 1) == "\"string_entry\""
      assert Enum.at(error.stacktrace, 2) == "{:atom_only}"
      assert Enum.at(error.stacktrace, 3) == "42"
    end

    test "limits stacktrace depth to 10 entries" do
      # Create a stacktrace with more than 10 entries
      long_stacktrace =
        for i <- 1..15 do
          {Module, :function, i, [file: "file#{i}.ex", line: i]}
        end

      error = Error.new(:test_error, "Test", stacktrace: long_stacktrace)

      # Should be limited to 10 entries
      assert length(error.stacktrace) == 10
    end
  end

  describe "Error.is_retryable?/1" do
    test "returns false for no_retry strategy" do
      error = Error.new(:invalid_config_value, "Invalid config")
      refute Error.is_retryable?(error)
    end

    test "returns true for retryable strategies" do
      network_error = Error.new(:network_error, "Network failed")
      assert Error.is_retryable?(network_error)

      service_error = Error.new(:external_service_error, "Service error")
      assert Error.is_retryable?(service_error)

      resource_error = Error.new(:resource_exhausted, "Out of memory")
      assert Error.is_retryable?(resource_error)
    end
  end
end
