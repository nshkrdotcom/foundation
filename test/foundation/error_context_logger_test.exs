defmodule Foundation.ErrorContextLoggerTest do
  use ExUnit.Case, async: false
  alias Foundation.{ErrorContext, Error, FeatureFlags}
  require Logger

  setup_all do
    # Ensure FeatureFlags GenServer is started for all tests
    case Process.whereis(FeatureFlags) do
      nil ->
        {:ok, pid} = FeatureFlags.start_link()

        on_exit(fn ->
          if Process.alive?(pid), do: GenServer.stop(pid, :normal)
        end)

      _ ->
        :ok
    end

    :ok
  end

  describe "Logger metadata implementation" do
    setup do
      # Save original feature flag state
      original_flag = FeatureFlags.enabled?(:use_logger_error_context)

      # Enable Logger metadata mode
      FeatureFlags.enable(:use_logger_error_context)

      # Clear any existing context
      ErrorContext.clear_context()

      on_exit(fn ->
        # Restore original flag state
        if original_flag do
          FeatureFlags.enable(:use_logger_error_context)
        else
          FeatureFlags.disable(:use_logger_error_context)
        end

        ErrorContext.clear_context()
      end)

      :ok
    end

    test "set_context/1 stores context in Logger metadata" do
      context = %{request_id: "test-123", user_id: "user-456"}

      ErrorContext.set_context(context)

      # Verify context is in Logger metadata
      assert Logger.metadata()[:error_context] == context
    end

    test "get_context/0 retrieves context from Logger metadata" do
      context = %{operation: "test_operation", correlation_id: "corr-789"}

      Logger.metadata(error_context: context)

      assert ErrorContext.get_context() == context
    end

    test "clear_context/0 removes context from Logger metadata" do
      ErrorContext.set_context(%{test: "data"})
      ErrorContext.clear_context()

      assert ErrorContext.get_context() == nil
      assert Logger.metadata()[:error_context] == nil
    end

    test "with_temporary_context/2 restores previous context after execution" do
      original_context = %{original: true}
      temp_context = %{temporary: true}

      ErrorContext.set_context(original_context)

      result =
        ErrorContext.with_temporary_context(temp_context, fn ->
          # Inside the function, temporary context should be active
          assert ErrorContext.get_context() == temp_context
          :success
        end)

      # After execution, original context should be restored
      assert result == :success
      assert ErrorContext.get_context() == original_context
    end

    test "with_temporary_context/2 cleans up context when no original context exists" do
      # Start with no context
      ErrorContext.clear_context()

      ErrorContext.with_temporary_context(%{temp: true}, fn ->
        assert ErrorContext.get_context() == %{temp: true}
      end)

      # Should be cleared after execution
      assert ErrorContext.get_context() == nil
    end

    test "with_context/1 uses Logger metadata for storage" do
      context = ErrorContext.new(TestModule, :test_function, correlation_id: "test-corr")

      result =
        ErrorContext.with_context(context, fn ->
          # Verify context is in Logger metadata during execution
          assert Logger.metadata()[:error_context] == context
          {:ok, :result}
        end)

      assert result == {:ok, :result}
      # Context should be cleared after execution
      assert Logger.metadata()[:error_context] == nil
    end

    test "with_context/1 enhances errors with context on exception" do
      context = ErrorContext.new(TestModule, :failing_function, metadata: %{important: "data"})

      result =
        ErrorContext.with_context(context, fn ->
          raise "Test error"
        end)

      assert {:error, %Error{} = error} = result
      assert error.error_type == :internal_error
      assert error.context.operation_context.correlation_id == context.correlation_id
      assert error.context.operation_context.metadata == %{important: "data"}
    end

    test "enrich_error/1 adds current context from Logger metadata" do
      context = ErrorContext.new(EnrichModule, :enrich_test)
      ErrorContext.set_context(context)

      error = Error.new(:validation_failed, "Test validation error")
      enriched = ErrorContext.enrich_error(error)

      assert enriched.context.operation_context.operation_id == context.operation_id
      assert enriched.context.operation_context.correlation_id == context.correlation_id
    end

    test "enrich_error/1 works with error tuples" do
      context = %{source: "test", request_id: "req-123"}
      ErrorContext.set_context(context)

      {:error, enriched} = ErrorContext.enrich_error({:error, :some_reason})

      assert %Error{} = enriched
      assert enriched.context.source == "test"
      assert enriched.context.request_id == "req-123"
      assert enriched.context.original_reason == :some_reason
    end

    test "spawn_with_context/1 inherits context in spawned process" do
      parent_context = %{parent_id: self(), operation: "parent_op"}
      ErrorContext.set_context(parent_context)

      test_pid = self()

      _pid =
        ErrorContext.spawn_with_context(fn ->
          # Child process should have parent's context
          child_context = ErrorContext.get_context()
          send(test_pid, {:child_context, child_context})
        end)

      assert_receive {:child_context, context}, 1000
      assert context == parent_context

      # Parent should still have its context
      assert ErrorContext.get_context() == parent_context
    end

    test "spawn_link_with_context/1 inherits context in linked process" do
      parent_context = ErrorContext.new(ParentModule, :parent_func)
      ErrorContext.set_context(parent_context)

      test_pid = self()

      _pid =
        ErrorContext.spawn_link_with_context(fn ->
          context = ErrorContext.get_context()
          send(test_pid, {:linked_context, context})
        end)

      assert_receive {:linked_context, context}, 1000
      assert context == parent_context
    end

    test "context is available in Logger metadata" do
      ErrorContext.set_context(%{request_id: "log-test-123", user: "test-user"})

      # Context should be available in Logger metadata
      metadata = Logger.metadata()
      assert metadata[:error_context] == %{request_id: "log-test-123", user: "test-user"}

      # This context would be available to custom logger backends/formatters
      # that include metadata in their output
    end

    test "get_current_context/0 uses the new mechanism" do
      context = %{debug: true, trace_id: "trace-123"}
      ErrorContext.set_context(context)

      assert ErrorContext.get_current_context() == context
    end
  end

  describe "Process dictionary fallback" do
    setup do
      # Save original feature flag state
      original_flag = FeatureFlags.enabled?(:use_logger_error_context)

      # Disable Logger metadata mode to use process dictionary
      FeatureFlags.disable(:use_logger_error_context)

      # Clear any existing context
      ErrorContext.clear_context()

      on_exit(fn ->
        # Restore original flag state
        if original_flag do
          FeatureFlags.enable(:use_logger_error_context)
        else
          FeatureFlags.disable(:use_logger_error_context)
        end

        ErrorContext.clear_context()
      end)

      :ok
    end

    test "set_context/1 uses process dictionary when flag is disabled" do
      context = %{mode: "legacy", data: "test"}

      ErrorContext.set_context(context)

      # Should be in process dictionary, not Logger metadata
      assert Process.get(:error_context) == context
      assert Logger.metadata()[:error_context] == nil
    end

    test "get_context/0 retrieves from process dictionary when flag is disabled" do
      context = %{legacy: true}
      Process.put(:error_context, context)

      assert ErrorContext.get_context() == context
    end

    test "clear_context/0 clears process dictionary when flag is disabled" do
      Process.put(:error_context, %{test: "data"})

      ErrorContext.clear_context()

      assert Process.get(:error_context) == nil
    end
  end

  describe "Performance comparison" do
    setup do
      :ok
    end

    test "Logger metadata performance vs process dictionary" do
      iterations = 10_000
      context = %{test: "performance", data: :erlang.make_ref()}

      # Test Logger metadata performance
      FeatureFlags.enable(:use_logger_error_context)

      logger_time =
        :timer.tc(fn ->
          Enum.each(1..iterations, fn _ ->
            ErrorContext.set_context(context)
            ErrorContext.get_context()
            ErrorContext.clear_context()
          end)
        end)
        |> elem(0)

      # Test process dictionary performance
      FeatureFlags.disable(:use_logger_error_context)

      process_dict_time =
        :timer.tc(fn ->
          Enum.each(1..iterations, fn _ ->
            ErrorContext.set_context(context)
            ErrorContext.get_context()
            ErrorContext.clear_context()
          end)
        end)
        |> elem(0)

      # Logger metadata should have comparable performance
      # (within 2x slower is acceptable given the benefits)
      performance_ratio = logger_time / process_dict_time

      IO.puts("Performance ratio (Logger/Process): #{Float.round(performance_ratio, 2)}x")
      IO.puts("Logger time: #{logger_time}μs, Process dict time: #{process_dict_time}μs")

      # Assert reasonable performance (Logger shouldn't be more than 3x slower)
      assert performance_ratio < 3.0
    end
  end

  describe "Error handling edge cases" do
    setup do
      FeatureFlags.enable(:use_logger_error_context)
      ErrorContext.clear_context()

      on_exit(fn ->
        ErrorContext.clear_context()
      end)

      :ok
    end

    test "handles nil context gracefully" do
      ErrorContext.set_context(nil)
      assert ErrorContext.get_context() == nil
    end

    test "handles complex nested contexts" do
      nested_context = %{
        level1: %{
          level2: %{
            level3: %{
              data: "deep value",
              list: [1, 2, 3],
              tuple: {:ok, :nested}
            }
          }
        }
      }

      ErrorContext.set_context(nested_context)
      retrieved = ErrorContext.get_context()

      assert retrieved == nested_context
      assert retrieved.level1.level2.level3.data == "deep value"
    end

    test "context survives through multiple function calls" do
      context = ErrorContext.new(Module1, :function1)

      ErrorContext.with_context(context, fn ->
        # Add breadcrumb
        updated = ErrorContext.add_breadcrumb(context, Module2, :function2)
        ErrorContext.set_context(updated)

        # Nested call
        inner_result =
          ErrorContext.with_temporary_context(
            %{nested: true},
            fn -> ErrorContext.get_context() end
          )

        assert inner_result == %{nested: true}

        # Context should be restored to updated version
        final_context = ErrorContext.get_context()
        assert length(final_context.breadcrumbs) == 2
      end)
    end
  end
end
