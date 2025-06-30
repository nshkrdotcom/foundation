defmodule Foundation.TelemetryTest do
  use ExUnit.Case, async: true
  use Foundation.TelemetryTestHelpers

  alias Foundation.Telemetry

  describe "basic telemetry operations" do
    test "emit/3 sends telemetry events" do
      assert_telemetry_event [:test, :event], %{value: 42}, %{status: :ok} do
        Telemetry.emit([:test, :event], %{value: 42}, %{status: :ok})
      end
    end

    test "span/3 emits start, stop, and exception events" do
      # Test successful span
      {events, result} =
        with_telemetry_capture events: [[:test, :span, :start], [:test, :span, :stop]] do
          Telemetry.span([:test, :span], %{operation: :test}, fn ->
            {:ok, :success}
          end)
        end

      assert result == {:ok, :success}
      assert length(events) == 2

      [start_event, stop_event] = events
      assert elem(start_event, 0) == [:test, :span, :start]
      assert elem(stop_event, 0) == [:test, :span, :stop]

      # Verify duration is measured
      {_, stop_measurements, _, _} = stop_event
      assert stop_measurements.duration > 0
    end

    test "span/3 emits exception event on error" do
      assert_raise RuntimeError, "test error", fn ->
        with_telemetry_capture events: [[:test, :span, :exception]] do
          Telemetry.span([:test, :span], %{operation: :failing}, fn ->
            raise "test error"
          end)
        end
      end

      # Verify exception event was emitted
      {_event, measurements, metadata, _result} =
        assert_telemetry_event [:test, :span, :exception],
                               %{},
                               %{},
                               timeout: 100 do
          try do
            Telemetry.span([:test, :span], %{operation: :failing}, fn ->
              raise "test error"
            end)
          rescue
            _ -> :ok
          end
        end

      assert is_integer(measurements.duration) and measurements.duration > 0
      assert %RuntimeError{message: "test error"} = metadata.error
    end
  end

  describe "service lifecycle events" do
    test "service_started/2 emits proper event" do
      assert_telemetry_event [:foundation, :service, :started],
                             %{},
                             %{service: TestService, config: %{pool_size: 10}} do
        Telemetry.service_started(TestService, %{config: %{pool_size: 10}})
      end
    end

    test "service_stopped/2 emits proper event" do
      assert_telemetry_event [:foundation, :service, :stopped],
                             %{},
                             %{service: TestService, reason: :shutdown} do
        Telemetry.service_stopped(TestService, %{reason: :shutdown})
      end
    end

    test "service_error/3 emits proper event" do
      error = %RuntimeError{message: "service failure"}

      {_event, _measurements, metadata, _result} =
        assert_telemetry_event [:foundation, :service, :error],
                               %{},
                               %{service: TestService, operation: :handle_call} do
          Telemetry.service_error(TestService, error, %{operation: :handle_call})
        end

      assert metadata.error == error
    end
  end

  describe "async operation events" do
    test "async operation lifecycle" do
      operation_id = :data_import

      # Start event
      {_event, _measurements, metadata, _result} =
        assert_telemetry_event [:foundation, :async, :started],
                               %{},
                               %{operation: operation_id, batch_size: 1000} do
          Telemetry.async_started(operation_id, %{batch_size: 1000})
        end

      assert metadata.operation == operation_id

      # Complete event
      {_event, measurements, metadata, _result} =
        assert_telemetry_event [:foundation, :async, :completed],
                               %{duration: 50_000},
                               %{operation: operation_id, records: 1000} do
          Telemetry.async_completed(operation_id, 50_000, %{records: 1000})
        end

      assert measurements.duration == 50_000
      assert metadata.operation == operation_id

      # Failed event
      error = "import failed"

      {_event, _measurements, metadata, _result} =
        assert_telemetry_event [:foundation, :async, :failed],
                               %{},
                               %{operation: operation_id} do
          Telemetry.async_failed(operation_id, error, %{})
        end

      assert metadata.error == error
    end
  end

  describe "resource management events" do
    test "resource lifecycle" do
      resource = :db_connection

      # Acquire
      {_event, _measurements, metadata, _result} =
        assert_telemetry_event [:foundation, :resource, :acquired],
                               %{},
                               %{resource_type: resource, pool: :primary} do
          Telemetry.resource_acquired(resource, %{pool: :primary})
        end

      assert metadata.resource_type == resource

      # Release
      {_event, measurements, metadata, _result} =
        assert_telemetry_event [:foundation, :resource, :released],
                               %{hold_duration: 100_000},
                               %{resource_type: resource, pool: :primary} do
          Telemetry.resource_released(resource, 100_000, %{pool: :primary})
        end

      assert measurements.hold_duration == 100_000
      assert metadata.resource_type == resource

      # Exhausted
      {_event, _measurements, metadata, _result} =
        assert_telemetry_event [:foundation, :resource, :exhausted],
                               %{},
                               %{resource_type: resource, waiting: 5} do
          Telemetry.resource_exhausted(resource, %{waiting: 5})
        end

      assert metadata.resource_type == resource
      assert metadata.waiting == 5
    end
  end

  describe "circuit breaker events" do
    test "state change event" do
      {_event, _measurements, metadata, _result} =
        assert_telemetry_event [:foundation, :circuit_breaker, :state_change],
                               %{},
                               %{
                                 service: :payment_api,
                                 from_state: :closed,
                                 to_state: :open,
                                 error_count: 5
                               } do
          Telemetry.circuit_breaker_state_change(:payment_api, :closed, :open, %{error_count: 5})
        end

      assert metadata.service == :payment_api
      assert metadata.from_state == :closed
      assert metadata.to_state == :open
      assert metadata.error_count == 5
    end
  end

  describe "performance metrics" do
    test "record_metric/3" do
      {_event, measurements, metadata, _result} =
        assert_telemetry_event [:foundation, :metrics, :response_time],
                               %{value: 45.2},
                               %{endpoint: "/api/users"} do
          Telemetry.record_metric(:response_time, 45.2, %{endpoint: "/api/users"})
        end

      assert measurements.value == 45.2
      assert metadata.endpoint == "/api/users"
    end
  end

  describe "utility functions" do
    test "generate_trace_id creates unique IDs" do
      id1 = Telemetry.generate_trace_id()
      id2 = Telemetry.generate_trace_id()

      assert is_binary(id1)
      assert String.length(id1) == 32
      assert id1 != id2
    end

    test "with_trace adds trace_id to metadata" do
      trace_id = "abc123"
      metadata = %{operation: :test}

      result = Telemetry.with_trace(trace_id, metadata)
      assert result.trace_id == trace_id
      assert result.operation == :test
    end
  end

  describe "telemetry test helpers" do
    test "wait_for_telemetry_event" do
      # Emit event asynchronously without sleep
      Task.start(fn ->
        # Small delay to ensure wait_for_telemetry_event is called first
        :timer.sleep(10)
        Telemetry.emit([:test, :delayed], %{value: 1}, %{})
      end)

      assert {:ok, {[:test, :delayed], %{value: 1}, _}} =
               wait_for_telemetry_event([:test, :delayed], timeout: 200)
    end

    test "wait_for_telemetry_event timeout" do
      assert {:error, :timeout} =
               wait_for_telemetry_event([:test, :never_emitted], timeout: 50)
    end

    test "refute_telemetry_event" do
      refute_telemetry_event [:test, :should_not_happen], timeout: 50 do
        # Do nothing - event should not be emitted
        :ok
      end
    end

    test "assert_telemetry_order" do
      assert_telemetry_order [
        [:test, :first],
        [:test, :second],
        [:test, :third]
      ] do
        Telemetry.emit([:test, :first], %{}, %{})
        Telemetry.emit([:test, :second], %{}, %{})
        Telemetry.emit([:test, :third], %{}, %{})
      end
    end

    test "measure_telemetry_performance" do
      metrics =
        measure_telemetry_performance [:test, :perf] do
          Telemetry.emit([:test, :perf], %{duration: 100}, %{})
          Telemetry.emit([:test, :perf], %{duration: 200}, %{})
          Telemetry.emit([:test, :perf], %{duration: 300}, %{})
        end

      assert metrics.count == 3
      assert metrics.average_duration == 200.0
      assert metrics.total_duration == 600
    end

    test "poll_with_telemetry" do
      counter = :counters.new(1, [])
      ref = make_ref()

      Task.start(fn ->
        # Add small delay to ensure we're waiting before event is emitted
        :timer.sleep(10)
        # Use telemetry to signal when value is updated
        :counters.put(counter, 1, 5)
        Telemetry.emit([:test, :counter_updated], %{value: 5}, %{ref: ref})
      end)

      # First wait for the update event
      {:ok, _} = wait_for_telemetry_event([:test, :counter_updated], timeout: 200)

      # Then verify polling works
      assert poll_with_telemetry(
               fn ->
                 :counters.get(counter, 1) >= 5
               end,
               timeout: 100
             )
    end
  end
end
