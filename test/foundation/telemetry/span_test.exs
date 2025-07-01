defmodule Foundation.Telemetry.SpanTest do
  use ExUnit.Case, async: true
  use Foundation.TelemetryTestHelpers

  import Foundation.Telemetry.Span

  setup do
    # Clean up any existing span stack
    Process.delete(:foundation_telemetry_span_stack)
    :ok
  end

  describe "with_span/3" do
    test "executes block and emits start/stop events" do
      test_pid = self()
      ref = make_ref()

      # Attach handlers
      :telemetry.attach(
        "test-span-start",
        [:foundation, :span, :start],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {ref, :start, measurements, metadata})
        end,
        %{}
      )

      :telemetry.attach(
        "test-span-stop",
        [:foundation, :span, :stop],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {ref, :stop, measurements, metadata})
        end,
        %{}
      )

      # Execute span
      result =
        with_span :test_operation, %{user_id: 123} do
          # Do some actual work to ensure measurable duration
          _result = Enum.reduce(1..1000, 0, fn i, acc -> acc + i end)
          {:ok, "result"}
        end

      # Verify result
      assert result == {:ok, "result"}

      # Verify start event
      assert_receive {^ref, :start, _start_measurements, start_metadata}
      assert start_metadata.span_name == :test_operation
      assert start_metadata.user_id == 123
      assert start_metadata.trace_id != nil
      assert start_metadata.parent_id == nil

      # Verify stop event
      assert_receive {^ref, :stop, stop_measurements, stop_metadata}
      assert stop_metadata.span_name == :test_operation
      assert stop_metadata.status == :ok
      assert stop_measurements.duration > 0

      # Cleanup
      :telemetry.detach("test-span-start")
      :telemetry.detach("test-span-stop")
    end

    test "handles exceptions and sets error status" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-span-error",
        [:foundation, :span, :stop],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {ref, :stop, metadata})
        end,
        %{}
      )

      # Execute span that raises
      assert_raise RuntimeError, "test error", fn ->
        # Wrap in a function to avoid pattern matching warning
        failing_function = fn ->
          raise "test error"
        end

        with_span :failing_operation do
          failing_function.()
        end
      end

      # Verify error status
      assert_receive {^ref, :stop, metadata}
      assert metadata.status == :error
      assert metadata.error =~ "test error"

      :telemetry.detach("test-span-error")
    end

    test "supports nested spans" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-nested-spans",
        [:foundation, :span, :start],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {ref, :start, metadata.span_name, metadata.parent_id})
        end,
        %{}
      )

      with_span :outer_span do
        assert_receive {^ref, :start, :outer_span, nil}

        with_span :inner_span do
          assert_receive {^ref, :start, :inner_span, parent_id}
          assert parent_id != nil
        end
      end

      :telemetry.detach("test-nested-spans")
    end
  end

  describe "add_attributes/1" do
    test "adds attributes to current span" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-attributes",
        [:foundation, :span, :attributes],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {ref, :attributes, metadata})
        end,
        %{}
      )

      with_span :test_span do
        add_attributes(%{status_code: 200, response_size: 1024})

        assert_receive {^ref, :attributes, metadata}
        assert metadata.status_code == 200
        assert metadata.response_size == 1024
      end

      :telemetry.detach("test-attributes")
    end

    test "logs warning when no active span" do
      import ExUnit.CaptureLog

      assert capture_log(fn ->
               add_attributes(%{foo: "bar"})
             end) =~ "No active span to add attributes to"
    end
  end

  describe "record_event/2" do
    test "records event within span" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-span-event",
        [:foundation, :span, :event],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {ref, :event, metadata})
        end,
        %{}
      )

      with_span :test_span do
        record_event(:checkpoint_reached, %{checkpoint: "validation"})

        assert_receive {^ref, :event, metadata}
        assert metadata.event_name == :checkpoint_reached
        assert metadata.checkpoint == "validation"
        assert metadata.span_name == :test_span
      end

      :telemetry.detach("test-span-event")
    end
  end

  describe "current_span/0" do
    test "returns nil when no active span" do
      assert current_span() == nil
    end

    test "returns current span when active" do
      with_span :test_span, %{test: true} do
        span = current_span()
        assert span != nil
        assert span.name == :test_span
        assert span.metadata.test == true
      end
    end
  end

  describe "current_trace_id/0" do
    test "returns nil when no active span" do
      assert current_trace_id() == nil
    end

    test "returns trace ID when span active" do
      with_span :test_span do
        trace_id = current_trace_id()
        assert trace_id != nil
        assert is_binary(trace_id)
        # 16 bytes hex encoded
        assert byte_size(trace_id) == 32
      end
    end

    test "maintains trace ID across nested spans" do
      with_span :outer do
        outer_trace_id = current_trace_id()

        with_span :inner do
          inner_trace_id = current_trace_id()
          assert inner_trace_id == outer_trace_id
        end
      end
    end
  end

  describe "propagate_context/0 and with_propagated_context/2" do
    test "propagates span context to another process" do
      test_pid = self()

      with_span :parent_span, %{request_id: "123"} do
        parent_trace_id = current_trace_id()
        context = propagate_context()

        task =
          Task.async(fn ->
            with_propagated_context(context, fn ->
              # Should have same trace ID
              child_trace_id = current_trace_id()
              send(test_pid, {:trace_id, child_trace_id})

              # Start a new span in child process
              with_span :child_span do
                :ok
              end
            end)
          end)

        Task.await(task)

        assert_receive {:trace_id, child_trace_id}
        assert child_trace_id == parent_trace_id
      end
    end
  end

  describe "link_span/3" do
    test "creates span link" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-span-link",
        [:foundation, :span, :link],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {ref, :link, metadata})
        end,
        %{}
      )

      with_span :test_span do
        link_span("external-trace-123", "external-span-456", %{
          relationship: "caused_by"
        })

        assert_receive {^ref, :link, metadata}
        assert metadata.linked_trace_id == "external-trace-123"
        assert metadata.linked_span_id == "external-span-456"
        assert metadata.relationship == "caused_by"
      end

      :telemetry.detach("test-span-link")
    end
  end

  describe "error handling" do
    test "handles throw in span" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-throw",
        [:foundation, :span, :stop],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {ref, :stop, metadata})
        end,
        %{}
      )

      catch_throw(
        with_span :throwing_span do
          throw(:test_throw)
        end
      )

      assert_receive {^ref, :stop, metadata}
      assert metadata.status == :error
      assert metadata.error =~ "throw"

      :telemetry.detach("test-throw")
    end

    test "handles exit in span" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test-exit",
        [:foundation, :span, :stop],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {ref, :stop, metadata})
        end,
        %{}
      )

      Process.flag(:trap_exit, true)

      catch_exit(
        with_span :exiting_span do
          exit(:test_exit)
        end
      )

      assert_receive {^ref, :stop, metadata}
      assert metadata.status == :error

      :telemetry.detach("test-exit")
    end
  end
end
