defmodule Foundation.Types.EnhancedErrorTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Foundation.Types.Error

  describe "Error.new/3 with enhanced functionality" do
    test "creates error with standard format" do
      error = Error.new(:validation, :invalid_config, "Configuration is invalid")
      
      assert error.category == :validation
      assert error.code == :invalid_config
      assert error.message == "Configuration is invalid"
      assert error.severity == :error  # default
      assert error.node == Node.self()
      assert %DateTime{} = error.timestamp
      assert is_binary(error.process_id)
    end

    test "creates error with optional fields" do
      context = %{
        module: __MODULE__,
        function: :test_function,
        line: 42,
        request_id: "req-123",
        user_id: "user-456",
        additional: %{custom: "data"}
      }
      
      error = Error.new(:authentication, :token_expired, "Token has expired", 
        severity: :warning,
        context: context,
        retry_info: %{
          attempt: 1,
          max_attempts: 3,
          backoff_strategy: :exponential
        }
      )
      
      assert error.category == :authentication
      assert error.severity == :warning
      assert error.context.module == __MODULE__
      assert error.context.request_id == "req-123"
      assert error.retry_info.attempt == 1
    end
    
    test "generates unique correlation_id when not provided" do
      error1 = Error.new(:network, :timeout, "Connection timeout")
      error2 = Error.new(:network, :timeout, "Connection timeout")
      
      assert error1.correlation_id != error2.correlation_id
      assert is_binary(error1.correlation_id)
      assert String.length(error1.correlation_id) > 10
    end
    
    test "uses provided correlation_id when specified" do
      correlation_id = "custom-correlation-123"
      error = Error.new(:network, :timeout, "Connection timeout", 
        correlation_id: correlation_id
      )
      
      assert error.correlation_id == correlation_id
    end
  end

  describe "Error.wrap/3 for error chaining" do
    test "wraps simple error with enhanced context" do
      original_error = Error.new(:validation, :missing_field, "Field is required")
      
      wrapped_error = Error.wrap(
        original_error,
        :agent_management, 
        :agent_creation_failed,
        "Agent creation failed due to validation error",
        context: %{agent_id: "agent-123"}
      )
      
      assert wrapped_error.category == :agent_management
      assert wrapped_error.code == :agent_creation_failed
      assert wrapped_error.caused_by == original_error
      assert wrapped_error.context.agent_id == "agent-123"
      # Correlation ID should be preserved from original
      assert wrapped_error.correlation_id == original_error.correlation_id
    end
    
    test "chains multiple error wrappings" do
      error1 = Error.new(:network, :connection_refused, "Connection refused")
      error2 = Error.wrap(error1, :external, :service_unavailable, "Service is down")
      error3 = Error.wrap(error2, :coordination, :auction_failed, "Auction coordination failed")
      
      assert error3.caused_by == error2
      assert error3.caused_by.caused_by == error1
      assert error3.correlation_id == error1.correlation_id
    end
  end

  describe "Error.to_external/1 for cross-layer communication" do
    test "converts to Jido-compatible format" do
      error = Error.new(:agent_communication, :signal_failed, "Signal dispatch failed",
        context: %{signal_type: :command, target_agent: "agent-1"}
      )
      
      jido_format = Error.to_external(error, :jido)
      
      assert jido_format.type == :error
      assert jido_format.reason == :signal_failed
      assert jido_format.message == "Signal dispatch failed"
      assert jido_format.metadata.category == :agent_communication
      assert jido_format.metadata.correlation_id == error.correlation_id
    end
    
    test "converts to DSPEx-compatible format" do
      error = Error.new(:ml_processing, :optimization_failed, "SIMBA optimization failed",
        context: %{program_id: "prog-123", iteration: 5}
      )
      
      dspex_format = Error.to_external(error, :dspex)
      
      assert dspex_format.type == :optimization_error
      assert dspex_format.code == :optimization_failed
      assert dspex_format.details.program_id == "prog-123"
      assert dspex_format.details.iteration == 5
    end
  end

  describe "Error.from_external/2 for error conversion" do
    test "converts from Jido error format" do
      jido_error = %{
        type: :error,
        reason: :timeout,
        message: "Agent timeout",
        metadata: %{agent_id: "agent-123"}
      }
      
      foundation_error = Error.from_external(jido_error, :jido)
      
      assert foundation_error.category == :agent_communication
      assert foundation_error.code == :timeout
      assert foundation_error.message == "Agent timeout"
      assert foundation_error.context.additional.agent_id == "agent-123"
    end
    
    test "converts from raw error tuples" do
      raw_error = {:error, :econnrefused}
      
      foundation_error = Error.from_external(raw_error, :erlang)
      
      assert foundation_error.category == :network
      assert foundation_error.code == :connection_refused
      assert foundation_error.severity == :error
    end
  end

  describe "Error.retryable?/1" do
    test "identifies retryable errors" do
      network_error = Error.new(:network, :timeout, "Network timeout")
      assert Error.retryable?(network_error)
      
      service_error = Error.new(:external, :service_unavailable, "Service down")
      assert Error.retryable?(service_error)
    end
    
    test "identifies non-retryable errors" do
      validation_error = Error.new(:validation, :invalid_format, "Invalid format")
      refute Error.retryable?(validation_error)
      
      auth_error = Error.new(:authentication, :invalid_credentials, "Bad credentials")
      refute Error.retryable?(auth_error)
    end
  end

  describe "Error.should_escalate?/1" do
    test "escalates critical errors" do
      critical_error = Error.new(:internal, :system_failure, "System failure", 
        severity: :critical
      )
      assert Error.should_escalate?(critical_error)
    end
    
    test "does not escalate low severity errors" do
      debug_error = Error.new(:validation, :warning, "Minor validation issue", 
        severity: :debug
      )
      refute Error.should_escalate?(debug_error)
    end
  end

  describe "Error.get_retry_delay/2" do
    test "calculates exponential backoff delay" do
      error = Error.new(:network, :timeout, "Timeout", 
        retry_info: %{backoff_strategy: :exponential}
      )
      
      delay1 = Error.get_retry_delay(error, 1)
      delay2 = Error.get_retry_delay(error, 2)
      delay3 = Error.get_retry_delay(error, 3)
      
      assert delay2 > delay1
      assert delay3 > delay2
      assert delay1 == 1000  # Base delay
      assert delay2 == 2000  # 2^1 * base
      assert delay3 == 4000  # 2^2 * base
    end
    
    test "calculates linear backoff delay" do
      error = Error.new(:external, :rate_limited, "Rate limited", 
        retry_info: %{backoff_strategy: :linear}
      )
      
      delay1 = Error.get_retry_delay(error, 1)
      delay2 = Error.get_retry_delay(error, 2)
      delay3 = Error.get_retry_delay(error, 3)
      
      assert delay1 == 1000
      assert delay2 == 2000
      assert delay3 == 3000
    end
  end

  describe "Error.format_for_logging/1" do
    test "formats error for structured logging" do
      error = Error.new(:coordination, :auction_failed, "Auction failed",
        context: %{
          auction_id: "auction-123",
          participants: 5,
          additional: %{reason: "timeout"}
        }
      )
      
      log_format = Error.format_for_logging(error)
      
      assert log_format.level == :error
      assert log_format.category == :coordination
      assert log_format.code == :auction_failed
      assert log_format.message == "Auction failed"
      assert log_format.correlation_id == error.correlation_id
      assert log_format.metadata.auction_id == "auction-123"
      assert log_format.metadata.participants == 5
    end
  end

  describe "Error.emit_telemetry/1" do
    test "emits telemetry event for error tracking" do
      error = Error.new(:agent_management, :registration_failed, "Registration failed")
      
      # This would normally emit to :telemetry
      # For testing, we'll just verify the function exists and returns :ok
      assert Error.emit_telemetry(error) == :ok
    end
  end

  # Property-based tests for robustness
  property "error creation is consistent with valid inputs" do
    check all category <- member_of([
      :validation, :authentication, :network, :agent_management,
      :coordination, :ml_processing, :external
    ]),
    code <- atom(:alphanumeric),
    message <- string(:printable, min_length: 1, max_length: 200),
    severity <- member_of([:debug, :info, :warning, :error, :critical]) do
      
      error = Error.new(category, code, message, severity: severity)
      
      assert error.category == category
      assert error.code == code
      assert error.message == message
      assert error.severity == severity
      assert %DateTime{} = error.timestamp
      assert is_binary(error.correlation_id)
    end
  end

  property "error wrapping preserves correlation ID" do
    check all category1 <- member_of([:validation, :network]),
    category2 <- member_of([:agent_management, :coordination]),
    code1 <- atom(:alphanumeric),
    code2 <- atom(:alphanumeric),
    message1 <- string(:printable, min_length: 1),
    message2 <- string(:printable, min_length: 1) do
      
      error1 = Error.new(category1, code1, message1)
      error2 = Error.wrap(error1, category2, code2, message2)
      
      assert error2.correlation_id == error1.correlation_id
      assert error2.caused_by == error1
    end
  end
end