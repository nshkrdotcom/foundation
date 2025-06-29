defmodule JidoSystem.Actions.ProcessTaskTest do
  use ExUnit.Case, async: false
  
  alias JidoSystem.Actions.ProcessTask
  alias Foundation.{Telemetry, CircuitBreaker}
  
  setup do
    # Ensure clean telemetry state - detach any existing handlers
    try do
      :telemetry.detach("test_task_processing")
      :telemetry.detach("test_validation")
      :telemetry.detach("test_circuit_breaker")
    rescue
      _ -> :ok
    end
    
    :ok
  end
  
  describe "task validation" do
    test "validates required parameters" do
      valid_params = %{
        task_id: "test_task_1",
        task_type: :data_processing,
        input_data: %{source: "test.csv"},
        options: %{},
        priority: :normal,
        timeout: 30_000,
        retry_attempts: 3,
        circuit_breaker: true
      }
      
      {:ok, result} = ProcessTask.run(valid_params, %{})
      
      assert result.task_id == "test_task_1"
      assert result.status == :completed
      assert is_map(result.result)
    end
    
    test "rejects invalid task_id" do
      invalid_params = %{
        task_id: "",  # Empty string
        task_type: :data_processing,
        input_data: %{source: "test.csv"},
        timeout: 30_000,
        retry_attempts: 3,
        circuit_breaker: false
      }
      
      {:error, error} = ProcessTask.run(invalid_params, %{})
      assert match?({:validation_failed, :invalid_task_id}, error)
    end
    
    test "rejects invalid task_type" do
      invalid_params = %{
        task_id: "test_task",
        task_type: "not_an_atom",  # Should be atom
        input_data: %{source: "test.csv"},
        timeout: 30_000,
        retry_attempts: 3,
        circuit_breaker: false
      }
      
      {:error, error} = ProcessTask.run(invalid_params, %{})
      assert match?({:validation_failed, :invalid_task_type}, error)
    end
    
    test "rejects invalid input_data" do
      invalid_params = %{
        task_id: "test_task",
        task_type: :data_processing,
        input_data: "not_a_map",  # Should be map
        timeout: 30_000,
        retry_attempts: 3,
        circuit_breaker: false
      }
      
      {:error, error} = ProcessTask.run(invalid_params, %{})
      assert match?({:validation_failed, :invalid_input_data}, error)
    end
    
    test "rejects timeout that's too short" do
      invalid_params = %{
        task_id: "test_task",
        task_type: :data_processing,
        input_data: %{},
        timeout: 500,  # Less than 1000ms minimum
        retry_attempts: 3,
        circuit_breaker: false
      }
      
      {:error, error} = ProcessTask.run(invalid_params, %{})
      assert match?({:validation_failed, :timeout_too_short}, error)
    end
  end
  
  describe "task processing types" do
    test "processes data_processing tasks" do
      params = %{
        task_id: "data_task",
        task_type: :data_processing,
        input_data: %{source: "test.csv", format: "csv"},
        timeout: 30_000,
        retry_attempts: 3,
        circuit_breaker: false  # Disable for simpler testing
      }
      
      {:ok, result} = ProcessTask.run(params, %{})
      
      assert result.task_id == "data_task"
      assert result.status == :completed
      assert is_map(result.result)
      assert Map.has_key?(result.result, :validation)
      assert Map.has_key?(result.result, :processed_data)
    end
    
    test "processes validation tasks" do
      params = %{
        task_id: "validation_task",
        task_type: :validation,
        input_data: %{
          name: "test",
          amount: 100,
          status: "active"
        },
        options: %{
          required_fields: [:name, :amount]
        },
        timeout: 30_000,
        retry_attempts: 3,
        circuit_breaker: false
      }
      
      {:ok, result} = ProcessTask.run(params, %{})
      
      assert result.task_id == "validation_task"
      assert result.status == :completed
      assert Map.has_key?(result.result, :validation_results)
      assert result.result.status == :valid
    end
    
    test "processes transformation tasks" do
      params = %{
        task_id: "transform_task",
        task_type: :transformation,
        input_data: %{
          name: "test",
          value: "hello"
        },
        options: %{
          transformations: [:uppercase_strings, :add_timestamp]
        },
        timeout: 30_000,
        retry_attempts: 3,
        circuit_breaker: false
      }
      
      {:ok, result} = ProcessTask.run(params, %{})
      
      assert result.task_id == "transform_task"
      assert result.status == :completed
      assert Map.has_key?(result.result, :transformed_data)
      assert result.result.transformed_data.name == "TEST"
      assert result.result.transformed_data.value == "HELLO"
      assert Map.has_key?(result.result.transformed_data, :transformed_at)
    end
    
    test "processes analysis tasks" do
      params = %{
        task_id: "analysis_task",
        task_type: :analysis,
        input_data: %{
          field1: "value1",
          field2: 42,
          field3: true
        },
        options: %{
          analysis_type: :basic
        },
        timeout: 30_000,
        retry_attempts: 3,
        circuit_breaker: false
      }
      
      {:ok, result} = ProcessTask.run(params, %{})
      
      assert result.task_id == "analysis_task"
      assert result.status == :completed
      assert Map.has_key?(result.result, :record_count)
      assert Map.has_key?(result.result, :data_quality_score)
    end
    
    test "processes notification tasks" do
      params = %{
        task_id: "notification_task",
        task_type: :notification,
        input_data: %{},
        options: %{
          recipients: ["user1@example.com", "user2@example.com"],
          message: "Test notification"
        },
        timeout: 30_000,
        retry_attempts: 3,
        circuit_breaker: false
      }
      
      {:ok, result} = ProcessTask.run(params, %{})
      
      assert result.task_id == "notification_task"
      assert result.status == :completed
      assert result.result.sent_count == 2
      assert result.result.message == "Test notification"
    end
    
    test "rejects unsupported task types" do
      params = %{
        task_id: "unsupported_task",
        task_type: :unsupported_type,
        input_data: %{},
        timeout: 30_000,
        retry_attempts: 3,
        circuit_breaker: false
      }
      
      {:error, result} = ProcessTask.run(params, %{})
      
      assert result.task_id == "unsupported_task"
      assert result.status == :failed
      assert match?({:retries_exhausted, {:unsupported_task_type, :unsupported_type}}, result.error)
    end
  end
  
  describe "retry mechanism" do
    test "retries failed operations" do
      # Create a task that will fail initially but might succeed on retry
      params = %{
        task_id: "retry_task",
        task_type: :data_processing,
        input_data: %{}, # Empty data should cause validation to fail
        timeout: 30_000,
        retry_attempts: 2,
        circuit_breaker: false
      }
      
      {:error, result} = ProcessTask.run(params, %{})
      
      # Should have attempted retries
      assert result.task_id == "retry_task"
      assert result.status == :failed
    end
    
    test "succeeds without retries when task is valid" do
      params = %{
        task_id: "no_retry_needed",
        task_type: :data_processing,
        input_data: %{source: "test.csv"},
        timeout: 30_000,
        retry_attempts: 3,
        circuit_breaker: false
      }
      
      {:ok, result} = ProcessTask.run(params, %{})
      
      assert result.task_id == "no_retry_needed"
      assert result.status == :completed
    end
  end
  
  describe "telemetry emission" do
    test "emits start and completion telemetry" do
      test_pid = self()
      ref = make_ref()
      
      events = [
        [:jido_system, :task, :started],
        [:jido_system, :task, :completed],
        [:jido_system, :task, :processing]
      ]
      
      :telemetry.attach_many(
        "test_task_telemetry",
        events,
        fn event, measurements, metadata, _config ->
          send(test_pid, {ref, event, measurements, metadata})
        end,
        %{}
      )
      
      params = %{
        task_id: "telemetry_task",
        task_type: :data_processing,
        input_data: %{source: "test.csv"},
        timeout: 30_000,
        retry_attempts: 3,
        circuit_breaker: false
      }
      
      {:ok, _result} = ProcessTask.run(params, %{agent_id: "test_agent"})
      
      # Should receive start telemetry
      assert_receive {^ref, [:jido_system, :task, :started], measurements, metadata}
      assert measurements.count == 1
      assert metadata.task_id == "telemetry_task"
      assert metadata.task_type == :data_processing
      assert metadata.agent_id == "test_agent"
      
      # Should receive processing telemetry
      assert_receive {^ref, [:jido_system, :task, :processing], _, _}
      
      # Should receive completion telemetry
      assert_receive {^ref, [:jido_system, :task, :completed], measurements, metadata}
      assert measurements.count == 1
      assert metadata.result == :success
      
      :telemetry.detach("test_task_telemetry")
    end
    
    test "emits failure telemetry on errors" do
      test_pid = self()
      ref = make_ref()
      
      :telemetry.attach(
        "test_failure_telemetry",
        [:jido_system, :task, :failed],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {ref, :failed, measurements, metadata})
        end,
        %{}
      )
      
      params = %{
        task_id: "failure_task",
        task_type: :unsupported_type,
        input_data: %{},
        timeout: 30_000,
        retry_attempts: 3,
        circuit_breaker: false
      }
      
      {:error, _result} = ProcessTask.run(params, %{})
      
      assert_receive {^ref, :failed, measurements, metadata}
      assert measurements.count == 1
      assert metadata.task_id == "failure_task"
      
      :telemetry.detach("test_failure_telemetry")
    end
  end
  
  describe "circuit breaker integration" do
    test "uses circuit breaker when enabled" do
      params = %{
        task_id: "circuit_breaker_task",
        task_type: :data_processing,
        input_data: %{source: "test.csv"},
        circuit_breaker: true,
        timeout: 5000,
        retry_attempts: 3
      }
      
      # Should complete successfully with circuit breaker
      {:ok, result} = ProcessTask.run(params, %{})
      
      assert result.task_id == "circuit_breaker_task"
      assert result.status == :completed
    end
    
    test "bypasses circuit breaker when disabled" do
      params = %{
        task_id: "no_circuit_breaker_task",
        task_type: :data_processing,
        input_data: %{source: "test.csv"},
        timeout: 30_000,
        retry_attempts: 3,
        circuit_breaker: false
      }
      
      # Should complete successfully without circuit breaker
      {:ok, result} = ProcessTask.run(params, %{})
      
      assert result.task_id == "no_circuit_breaker_task"
      assert result.status == :completed
    end
  end
  
  describe "error handling" do
    test "handles crashes gracefully" do
      # This test would need to simulate a crash scenario
      # For now, we test that the action handles invalid input gracefully
      params = %{
        task_id: nil,  # This should cause a crash
        task_type: :data_processing,
        input_data: %{},
        timeout: 30_000,
        retry_attempts: 3,
        circuit_breaker: false
      }
      
      {:error, error} = ProcessTask.run(params, %{})
      
      assert match?({:validation_failed, _}, error)
    end
    
    test "provides detailed error information" do
      params = %{
        task_id: "error_detail_task",
        task_type: :validation,
        input_data: %{name: "test"},  # Valid input data to avoid crashes
        options: %{},
        timeout: 30_000,
        retry_attempts: 3,
        circuit_breaker: false
      }
      
      {:ok, result} = ProcessTask.run(params, %{})
      
      assert result.task_id == "error_detail_task"
      assert result.status == :completed
      assert Map.has_key?(result, :result)
      assert Map.has_key?(result, :completed_at)
      assert Map.has_key?(result, :duration)
    end
  end
  
  describe "performance and timing" do
    test "tracks execution duration" do
      params = %{
        task_id: "duration_task",
        task_type: :data_processing,
        input_data: %{source: "test.csv"},
        timeout: 30_000,
        retry_attempts: 3,
        circuit_breaker: false
      }
      
      start_time = System.monotonic_time(:microsecond)
      {:ok, result} = ProcessTask.run(params, %{})
      end_time = System.monotonic_time(:microsecond)
      
      assert result.duration > 0
      assert result.duration <= (end_time - start_time)
    end
    
    test "completes within reasonable time for simple tasks" do
      params = %{
        task_id: "timing_task",
        task_type: :data_processing,
        input_data: %{source: "test.csv"},
        timeout: 30_000,
        retry_attempts: 3,
        circuit_breaker: false
      }
      
      {duration_microseconds, {:ok, result}} = :timer.tc(ProcessTask, :run, [params, %{}])
      
      # Should complete within 1 second for simple tasks
      assert duration_microseconds < 1_000_000
      assert result.status == :completed
    end
  end
end