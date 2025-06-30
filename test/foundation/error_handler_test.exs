defmodule Foundation.ErrorHandlerTest do
  use ExUnit.Case, async: true

  alias Foundation.ErrorHandler
  alias Foundation.ErrorHandler.Error

  describe "with_recovery/2" do
    test "returns success for successful operations" do
      result =
        ErrorHandler.with_recovery(fn ->
          {:ok, :success}
        end)

      assert result == {:ok, :success}
    end

    @tag :slow
    test "retries transient errors" do
      counter = :counters.new(1, [])

      result =
        ErrorHandler.with_recovery(
          fn ->
            count = :counters.get(counter, 1)
            :counters.add(counter, 1, 1)

            if count < 2 do
              {:error, ErrorHandler.create_error(:transient, :temporary_failure)}
            else
              {:ok, :success_after_retries}
            end
          end,
          max_retries: 2
        )

      assert result == {:ok, :success_after_retries}
      assert :counters.get(counter, 1) == 3
    end

    test "stops retrying permanent errors" do
      counter = :counters.new(1, [])

      result =
        ErrorHandler.with_recovery(fn ->
          :counters.add(counter, 1, 1)
          {:error, ErrorHandler.create_error(:permanent, :unrecoverable)}
        end)

      assert {:error, %Error{category: :permanent}} = result
      # Only tried once
      assert :counters.get(counter, 1) == 1
    end

    @tag :slow
    test "respects max retries" do
      counter = :counters.new(1, [])

      result =
        ErrorHandler.with_recovery(
          fn ->
            :counters.add(counter, 1, 1)
            {:error, ErrorHandler.create_error(:transient, :always_fails)}
          end,
          max_retries: 2
        )

      assert {:error, %Error{}} = result
      # Initial + 2 retries
      assert :counters.get(counter, 1) == 3
    end

    test "uses fallback value on error" do
      result =
        ErrorHandler.with_recovery(
          fn ->
            {:error, ErrorHandler.create_error(:permanent, :api_down)}
          end,
          category: :permanent,
          fallback: {:ok, :default_value}
        )

      assert result == {:ok, :default_value}
    end

    test "uses fallback function on error" do
      result =
        ErrorHandler.with_recovery(
          fn ->
            {:error, ErrorHandler.create_error(:permanent, :api_down)}
          end,
          category: :permanent,
          fallback: fn -> {:ok, :computed_fallback} end
        )

      assert result == {:ok, :computed_fallback}
    end

    test "handles exceptions" do
      result =
        ErrorHandler.with_recovery(fn ->
          raise "Something went wrong"
        end)

      assert {:error, %Error{category: :system}} = result
    end

    test "handles throws" do
      result =
        ErrorHandler.with_recovery(fn ->
          throw(:bad_thing)
        end)

      assert {:error, %Error{category: :system}} = result
    end
  end

  describe "circuit breaker" do
    test "circuit breaker opens after failures" do
      breaker_name = :"test_breaker_#{System.unique_integer()}"

      # Cause multiple failures
      for _ <- 1..5 do
        ErrorHandler.with_recovery(
          fn ->
            {:error, ErrorHandler.create_error(:transient, :service_error)}
          end,
          strategy: :circuit_break,
          circuit_breaker: breaker_name
        )
      end

      # Circuit should be open now
      result =
        ErrorHandler.with_recovery(
          fn ->
            {:ok, :should_not_execute}
          end,
          strategy: :circuit_break,
          circuit_breaker: breaker_name
        )

      assert {:error, %Error{reason: :circuit_breaker_open}} = result
    end

    test "circuit breaker with fallback" do
      breaker_name = :"test_breaker_fallback_#{System.unique_integer()}"

      # Open the circuit
      for _ <- 1..5 do
        ErrorHandler.with_recovery(
          fn ->
            {:error, ErrorHandler.create_error(:transient, :service_error)}
          end,
          strategy: :circuit_break,
          circuit_breaker: breaker_name
        )
      end

      # Should use fallback when circuit is open
      result =
        ErrorHandler.with_recovery(
          fn ->
            {:ok, :should_not_execute}
          end,
          strategy: :circuit_break,
          circuit_breaker: breaker_name,
          fallback: {:ok, :fallback_value}
        )

      assert result == {:ok, :fallback_value}
    end
  end

  describe "compensation" do
    test "runs compensation on error" do
      test_pid = self()

      result =
        ErrorHandler.with_recovery(
          fn ->
            {:error, ErrorHandler.create_error(:system, :needs_cleanup)}
          end,
          strategy: :compensate,
          compensation: fn error ->
            send(test_pid, {:compensation_ran, error.reason})
            :ok
          end
        )

      assert {:error, %Error{}} = result
      assert_receive {:compensation_ran, :needs_cleanup}
    end
  end

  describe "error creation and wrapping" do
    test "creates error with context" do
      error =
        ErrorHandler.create_error(:validation, :invalid_input, %{
          field: :email,
          value: "not-an-email"
        })

      assert %Error{
               category: :validation,
               reason: :invalid_input,
               context: %{field: :email, value: "not-an-email"}
             } = error

      assert error.timestamp
      assert error.retry_count == 0
    end

    test "wraps existing error with additional context" do
      original = ErrorHandler.create_error(:transient, :timeout, %{service: :api})
      wrapped = ErrorHandler.wrap_error(original, %{attempt: 1, endpoint: "/users"})

      assert wrapped.category == :transient
      assert wrapped.reason == :timeout
      assert wrapped.context == %{service: :api, attempt: 1, endpoint: "/users"}
    end

    test "wraps non-error values" do
      wrapped = ErrorHandler.wrap_error(:some_error, %{location: :here})

      assert %Error{
               category: :system,
               reason: :some_error,
               context: %{location: :here}
             } = wrapped
    end
  end

  describe "telemetry events" do
    test "emits success telemetry" do
      :telemetry.attach(
        "test-success",
        [:foundation, :error_handler, :success],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      ErrorHandler.with_recovery(
        fn ->
          {:ok, :result}
        end,
        telemetry_metadata: %{operation: :test}
      )

      assert_receive {:telemetry, [:foundation, :error_handler, :success], measurements, metadata}
      assert measurements.duration >= 0
      assert measurements.retry_count == 0
      assert metadata.operation == :test

      :telemetry.detach("test-success")
    end

    @tag :slow
    test "emits retry telemetry" do
      :telemetry.attach(
        "test-retry",
        [:foundation, :error_handler, :retry],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      counter = :counters.new(1, [])

      ErrorHandler.with_recovery(fn ->
        count = :counters.get(counter, 1)
        :counters.add(counter, 1, 1)

        if count < 2 do
          {:error, ErrorHandler.create_error(:transient, :retry_me)}
        else
          {:ok, :done}
        end
      end)

      assert_receive {:telemetry, [:foundation, :error_handler, :retry], measurements, metadata}
      assert measurements.retry_count >= 0
      assert measurements.backoff_ms > 0
      assert metadata.error_category == :transient
      assert metadata.error_reason == :retry_me

      :telemetry.detach("test-retry")
    end

    test "emits error telemetry" do
      :telemetry.attach(
        "test-error",
        [:foundation, :error_handler, :error],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      ErrorHandler.with_recovery(fn ->
        {:error, ErrorHandler.create_error(:permanent, :bad_thing)}
      end)

      assert_receive {:telemetry, [:foundation, :error_handler, :error], measurements, metadata}
      assert measurements.duration > 0
      assert metadata.error_category == :permanent
      assert metadata.error_reason == :bad_thing

      :telemetry.detach("test-error")
    end
  end

  describe "retryable?" do
    test "transient errors are retryable" do
      error = ErrorHandler.create_error(:transient, :timeout)
      assert ErrorHandler.retryable?(error)
    end

    test "resource errors are retryable" do
      error = ErrorHandler.create_error(:resource, :rate_limited)
      assert ErrorHandler.retryable?(error)
    end

    test "permanent errors are not retryable" do
      error = ErrorHandler.create_error(:permanent, :not_found)
      refute ErrorHandler.retryable?(error)
    end

    test "validation errors are not retryable" do
      error = ErrorHandler.create_error(:validation, :invalid_format)
      refute ErrorHandler.retryable?(error)
    end

    test "non-error values are not retryable" do
      refute ErrorHandler.retryable?(:some_atom)
      refute ErrorHandler.retryable?("error string")
    end
  end
end
