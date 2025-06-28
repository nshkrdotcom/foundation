# test/unit/foundation/error_context_test.exs (Fixed)
defmodule Foundation.ErrorContextTest do
  use ExUnit.Case, async: true

  alias Foundation.ErrorContext
  # Use the correct Error module
  alias Foundation.Error

  describe "ErrorContext.new/3" do
    test "creates a valid error context with basic parameters" do
      context = ErrorContext.new(__MODULE__, :test_function, metadata: %{user: "test"})

      assert %ErrorContext{} = context
      assert context.module == __MODULE__
      assert context.function == :test_function
      assert context.metadata.user == "test"
      assert is_integer(context.operation_id)
      assert is_binary(context.correlation_id)
      assert is_list(context.breadcrumbs)
      assert is_integer(context.start_time)
      assert is_nil(context.parent_context)
    end

    test "creates context with module and function parameters" do
      context = ErrorContext.new(__MODULE__, :test_function, metadata: %{test: true})

      assert context.module == __MODULE__
      assert context.function == :test_function
      assert context.metadata.test == true
    end

    test "generates unique operation and correlation IDs" do
      context1 = ErrorContext.new(__MODULE__, :operation1, metadata: %{})
      context2 = ErrorContext.new(__MODULE__, :operation2, metadata: %{})

      assert context1.operation_id != context2.operation_id
      assert context1.correlation_id != context2.correlation_id
    end

    test "accepts custom correlation_id in options" do
      custom_correlation = "custom-correlation-123"
      context = ErrorContext.new(__MODULE__, :test_function, correlation_id: custom_correlation)

      assert context.correlation_id == custom_correlation
    end

    test "includes initial breadcrumb" do
      context = ErrorContext.new(__MODULE__, :test_function)

      assert length(context.breadcrumbs) == 1
      breadcrumb = List.first(context.breadcrumbs)
      assert breadcrumb.module == __MODULE__
      assert breadcrumb.function == :test_function
      assert is_integer(breadcrumb.timestamp)
    end
  end

  describe "ErrorContext.child_context/4" do
    test "creates child context with parent reference" do
      parent = ErrorContext.new(__MODULE__, :parent_function, metadata: %{parent: true})
      child = ErrorContext.child_context(parent, __MODULE__, :child_function, %{child: true})

      assert child.parent_context == parent
      assert child.correlation_id == parent.correlation_id
      assert child.metadata.child == true
      # Should inherit parent metadata
      assert child.metadata.parent == true
      assert length(child.breadcrumbs) == 2
    end

    test "preserves correlation ID from parent" do
      parent = ErrorContext.new(__MODULE__, :parent_func, correlation_id: "shared-correlation")
      child = ErrorContext.child_context(parent, TestModule, :child_func, %{})

      assert child.correlation_id == "shared-correlation"
    end

    test "adds breadcrumb trail from parent" do
      parent = ErrorContext.new(ParentModule, :parent_func, metadata: %{})
      child = ErrorContext.child_context(parent, ChildModule, :child_func, %{})

      assert length(child.breadcrumbs) == 2

      parent_breadcrumb = Enum.at(child.breadcrumbs, 0)
      child_breadcrumb = Enum.at(child.breadcrumbs, 1)

      assert parent_breadcrumb.module == ParentModule
      assert parent_breadcrumb.function == :parent_func
      assert child_breadcrumb.module == ChildModule
      assert child_breadcrumb.function == :child_func
    end
  end

  describe "ErrorContext.add_breadcrumb/4" do
    test "adds breadcrumb to existing context" do
      context = ErrorContext.new(__MODULE__, :initial_function)
      initial_count = length(context.breadcrumbs)

      updated_context =
        ErrorContext.add_breadcrumb(
          context,
          NewModule,
          :new_function,
          %{step: "processing"}
        )

      assert length(updated_context.breadcrumbs) == initial_count + 1
      new_breadcrumb = List.last(updated_context.breadcrumbs)
      assert new_breadcrumb.module == NewModule
      assert new_breadcrumb.function == :new_function
      assert new_breadcrumb.metadata.step == "processing"
    end

    test "adds breadcrumb with default metadata" do
      context = ErrorContext.new(__MODULE__, :initial_function)
      updated_context = ErrorContext.add_breadcrumb(context, TestModule, :test_func)

      breadcrumb = List.last(updated_context.breadcrumbs)
      assert breadcrumb.metadata == %{}
    end

    test "preserves existing breadcrumbs when adding new ones" do
      context = ErrorContext.new(InitialModule, :initial_func, metadata: %{})

      updated_context =
        ErrorContext.add_breadcrumb(
          context,
          SecondModule,
          :second_func,
          %{step: 2}
        )

      assert length(updated_context.breadcrumbs) == 2

      first_breadcrumb = Enum.at(updated_context.breadcrumbs, 0)
      second_breadcrumb = Enum.at(updated_context.breadcrumbs, 1)

      assert first_breadcrumb.module == InitialModule
      assert second_breadcrumb.module == SecondModule
      assert second_breadcrumb.metadata.step == 2
    end
  end

  describe "ErrorContext.enhance_error/2" do
    test "enhances error with context information" do
      context = ErrorContext.new(__MODULE__, :test_operation, metadata: %{user: "test_user"})

      # Use Error.new/1 which exists
      original_error = Error.new(:invalid_config_value)

      enhanced_error = ErrorContext.enhance_error(original_error, context)

      # Check error structure
      assert enhanced_error.error_type == :invalid_config_value
      assert Map.has_key?(enhanced_error.context, :operation_context)

      operation_context = enhanced_error.context.operation_context
      assert operation_context.operation_id == context.operation_id
      assert operation_context.correlation_id == context.correlation_id
    end

    test "preserves original error context and adds operation context" do
      # Create an error with existing context using Error.new/1 then add context manually
      original_error = Error.new(:invalid_config_value)
      error_with_context = %{original_error | context: %{field: "username", value: "invalid"}}

      context = ErrorContext.new(__MODULE__, :user_registration, metadata: %{source: "web_form"})
      enhanced_error = ErrorContext.enhance_error(error_with_context, context)

      # Original context should be preserved
      assert enhanced_error.context.field == "username"
      assert enhanced_error.context.value == "invalid"

      # Operation context should be added
      assert Map.has_key?(enhanced_error.context, :operation_context)
      operation_context = enhanced_error.context.operation_context
      assert operation_context.operation_id == context.operation_id
      assert operation_context.metadata.source == "web_form"
    end

    test "includes breadcrumb information in enhanced error" do
      context = ErrorContext.new(TestModule, :test_function, metadata: %{})
      context = ErrorContext.add_breadcrumb(context, ValidationModule, :validate_input)

      original_error = Error.new(:invalid_config_value)
      enhanced_error = ErrorContext.enhance_error(original_error, context)

      operation_context = enhanced_error.context.operation_context
      assert length(operation_context.breadcrumbs) == 2

      first_breadcrumb = Enum.at(operation_context.breadcrumbs, 0)
      second_breadcrumb = Enum.at(operation_context.breadcrumbs, 1)

      assert first_breadcrumb.module == TestModule
      assert first_breadcrumb.function == :test_function
      assert second_breadcrumb.module == ValidationModule
      assert second_breadcrumb.function == :validate_input
    end
  end

  describe "ErrorContext.format_breadcrumbs/1" do
    test "formats breadcrumbs as human-readable string" do
      context = ErrorContext.new(FirstModule, :first_function, metadata: %{})
      context = ErrorContext.add_breadcrumb(context, SecondModule, :second_function)
      context = ErrorContext.add_breadcrumb(context, ThirdModule, :third_function)

      formatted = ErrorContext.format_breadcrumbs(context)

      assert is_binary(formatted)
      assert String.contains?(formatted, "FirstModule.first_function")
      assert String.contains?(formatted, "SecondModule.second_function")
      assert String.contains?(formatted, "ThirdModule.third_function")
    end

    test "formats empty breadcrumbs gracefully" do
      # Create a context using the proper constructor and then clear breadcrumbs
      context = ErrorContext.new(__MODULE__, :test_function, metadata: %{})
      empty_context = %{context | breadcrumbs: []}

      formatted = ErrorContext.format_breadcrumbs(empty_context)

      # Empty breadcrumbs should return empty string
      assert formatted == ""
    end

    test "includes timestamps in formatted output" do
      context = ErrorContext.new(__MODULE__, :test_function, metadata: %{})
      formatted = ErrorContext.format_breadcrumbs(context)

      # Should contain some indication of relative time
      assert String.contains?(formatted, "ago") or String.contains?(formatted, "at")
    end
  end

  describe "ErrorContext.with_context/2" do
    test "executes function and returns result on success" do
      context = ErrorContext.new(__MODULE__, :test_operation)

      result =
        ErrorContext.with_context(context, fn ->
          {:ok, "success"}
        end)

      assert result == {:ok, "success"}
    end

    test "captures and enhances exceptions" do
      context = ErrorContext.new(__MODULE__, :failing_operation, metadata: %{user: "test"})

      result =
        ErrorContext.with_context(context, fn ->
          raise RuntimeError, "Intentional test error"
        end)

      assert {:error, enhanced_error} = result
      assert enhanced_error.error_type == :internal_error
      assert String.contains?(enhanced_error.message, "Intentional test error")

      # Should have operation context
      assert Map.has_key?(enhanced_error.context, :operation_context)
      operation_context = enhanced_error.context.operation_context
      assert operation_context.operation_id == context.operation_id
      assert operation_context.metadata.user == "test"
    end

    test "handles various exception types" do
      context = ErrorContext.new(__MODULE__, :error_test)

      # Test ArgumentError
      result1 =
        ErrorContext.with_context(context, fn ->
          raise ArgumentError, "Invalid argument"
        end)

      assert {:error, error1} = result1
      assert error1.error_type == :internal_error

      # Test error tuple handling
      result2 =
        ErrorContext.with_context(context, fn ->
          {:error, :simulated_exit}
        end)

      # Should return the error tuple, not exit the process
      assert result2 == {:error, :simulated_exit}
    end

    test "preserves stacktrace information" do
      context = ErrorContext.new(__MODULE__, :stacktrace_test)

      result =
        ErrorContext.with_context(context, fn ->
          raise "Test error"
        end)

      assert {:error, error} = result
      assert is_list(error.stacktrace) or is_nil(error.stacktrace)
    end
  end

  describe "ErrorContext.get_current_context/0" do
    test "returns nil when no context is set" do
      # Ensure no context is set
      Process.delete(:error_context)

      assert ErrorContext.get_current_context() == nil
    end

    test "returns current context when set" do
      context = ErrorContext.new(__MODULE__, :current_operation)
      Process.put(:error_context, context)

      current = ErrorContext.get_current_context()
      assert current == context

      # Cleanup
      Process.delete(:error_context)
    end
  end

  describe "ErrorContext thread safety and isolation" do
    test "context is isolated per process" do
      context1 = ErrorContext.new(__MODULE__, :operation1)
      context2 = ErrorContext.new(__MODULE__, :operation2)

      # Set context in current process
      Process.put(:error_context, context1)

      # Spawn another process and verify isolation
      task =
        Task.async(fn ->
          # Should not see context from parent process
          assert ErrorContext.get_current_context() == nil

          # Set different context in child process
          Process.put(:error_context, context2)
          ErrorContext.get_current_context()
        end)

      child_context = Task.await(task)
      parent_context = ErrorContext.get_current_context()

      assert parent_context == context1
      assert child_context == context2

      # Cleanup
      Process.delete(:error_context)
    end

    test "with_context properly manages context lifecycle" do
      # Ensure no context initially
      Process.delete(:error_context)
      assert ErrorContext.get_current_context() == nil

      context = ErrorContext.new(__MODULE__, :managed_operation)

      result =
        ErrorContext.with_context(context, fn ->
          # Context should be available inside the function
          current = ErrorContext.get_current_context()
          assert current == context
          :test_result
        end)

      # Context should be cleaned up after function execution
      assert ErrorContext.get_current_context() == nil
      assert result == :test_result
    end
  end

  describe "ErrorContext metadata management" do
    test "adds metadata to existing context" do
      context = ErrorContext.new(__MODULE__, :operation, metadata: %{source: "web", user_id: 123})
      additional_metadata = %{session_id: "abc", request_id: "xyz"}

      # Use add_metadata function
      merged_context = ErrorContext.add_metadata(context, additional_metadata)

      assert merged_context.metadata.source == "web"
      assert merged_context.metadata.user_id == 123
      assert merged_context.metadata.session_id == "abc"
      assert merged_context.metadata.request_id == "xyz"
    end

    test "overwrites existing metadata keys" do
      context =
        ErrorContext.new(__MODULE__, :operation, metadata: %{environment: "dev", version: "1.0"})

      new_metadata = %{environment: "prod", feature_flag: true}

      merged_context = ErrorContext.add_metadata(context, new_metadata)

      assert merged_context.metadata.environment == "prod"
      assert merged_context.metadata.version == "1.0"
      assert merged_context.metadata.feature_flag == true
    end

    test "handles empty metadata gracefully" do
      context = ErrorContext.new(__MODULE__, :operation, metadata: %{existing: "data"})

      merged_context = ErrorContext.add_metadata(context, %{})

      assert merged_context.metadata.existing == "data"
      assert merged_context == context
    end
  end

  describe "ErrorContext operation duration" do
    test "calculates operation duration" do
      context = ErrorContext.new(__MODULE__, :timed_operation)

      # Sleep briefly to ensure some time passes
      Process.sleep(1)

      duration = ErrorContext.get_operation_duration(context)

      assert is_integer(duration)
      assert duration > 0
    end

    test "duration increases over time" do
      context = ErrorContext.new(__MODULE__, :duration_test)

      duration1 = ErrorContext.get_operation_duration(context)
      Process.sleep(5)
      duration2 = ErrorContext.get_operation_duration(context)

      assert duration2 > duration1
    end
  end
end
