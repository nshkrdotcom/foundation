defmodule Foundation.Property.ErrorPropertiesTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  # Property tests are inherently slow
  @moduletag :slow

  alias Foundation.Error

  # Generators for test data

  defp error_type_generator do
    one_of([
      # Known error types
      constant(:network_error),
      constant(:timeout),
      constant(:invalid_config_value),
      constant(:service_unavailable),
      constant(:resource_exhausted),
      constant(:data_corruption),
      constant(:external_service_error),
      constant(:internal_error),
      # Random atoms for unknown types
      atom(:alphanumeric)
    ])
  end

  defp message_generator do
    one_of([
      string(:printable),
      string(:alphanumeric),
      constant(""),
      string(:utf8, max_length: 1000),
      constant(nil)
    ])
  end

  defp context_generator do
    one_of([
      constant(%{}),
      map_of(atom(:alphanumeric), term()),
      map_of(string(:alphanumeric), term()),
      constant(nil)
    ])
  end

  defp stacktrace_generator do
    one_of([
      constant(nil),
      constant([]),
      list_of(stacktrace_entry_generator(), max_length: 20)
    ])
  end

  defp stacktrace_entry_generator do
    one_of([
      # Valid stacktrace entries
      tuple({
        # module
        atom(:alphanumeric),
        # function
        atom(:alphanumeric),
        # arity
        integer(0..10),
        # location
        list_of(tuple({atom(:alphanumeric), term()}))
      }),
      # Invalid entries to test robustness
      string(:printable),
      atom(:alphanumeric),
      integer(),
      tuple({atom(:alphanumeric)}),
      tuple({atom(:alphanumeric), atom(:alphanumeric)})
    ])
  end

  # Property Tests

  property "All Error.new(type) calls result in an error struct with a valid code and category" do
    check all(error_type <- error_type_generator()) do
      error = Error.new(error_type)

      assert %Error{} = error
      assert is_atom(error.error_type)
      assert error.error_type == error_type
      assert is_integer(error.code)
      assert error.code > 0
      assert is_atom(error.category)
      assert is_atom(error.subcategory)
    end
  end

  property "Error.new/3 with random messages never crashes regardless of input" do
    check all(
            error_type <- error_type_generator(),
            message <- message_generator()
          ) do
      error = Error.new(error_type, message)

      assert %Error{} = error
      assert error.error_type == error_type
      assert is_binary(error.message) or is_nil(error.message)
    end
  end

  property "Error.new/3 with random context maps preserves all provided context" do
    check all(
            error_type <- error_type_generator(),
            message <- message_generator(),
            context <- context_generator()
          ) do
      opts = if context, do: [context: context], else: []
      error = Error.new(error_type, message, opts)

      assert %Error{} = error

      case context do
        nil -> assert error.context == %{}
        %{} = ctx -> assert error.context == ctx
        _ -> assert error.context == %{}
      end
    end
  end

  property "Error.wrap_error/4 with nested error chains maintains error hierarchy" do
    check all(
            original_type <- error_type_generator(),
            wrapper_type <- error_type_generator(),
            original_context <- context_generator(),
            wrapper_context <- context_generator()
          ) do
      # Create original error
      original_opts = if original_context, do: [context: original_context], else: []
      original_error = Error.new(original_type, "Original error", original_opts)

      # Wrap the error
      wrapper_opts = if wrapper_context, do: [context: wrapper_context], else: []

      result =
        Error.wrap_error({:error, original_error}, wrapper_type, "Wrapped error", wrapper_opts)

      assert {:error, wrapped_error} = result
      assert %Error{} = wrapped_error

      # Original error type should be preserved
      assert wrapped_error.error_type == original_type
      assert wrapped_error.message == "Original error"

      # Wrapper information should be in context
      assert wrapped_error.context.wrapped_by == wrapper_type
      assert wrapped_error.context.wrapper_message == "Wrapped error"

      # Original context should be preserved
      if original_context && map_size(original_context) > 0 do
        Enum.each(original_context, fn {key, value} ->
          assert Map.get(wrapped_error.context, key) == value
        end)
      end
    end
  end

  property "Error.retry_delay/2 with random attempt numbers never returns negative values" do
    check all(
            error_type <- error_type_generator(),
            attempt <- integer(0..100)
          ) do
      error = Error.new(error_type)
      delay = Error.retry_delay(error, attempt)

      assert is_integer(delay) or delay == :infinity

      if is_integer(delay) do
        assert delay >= 0
      end
    end
  end

  property "Error.retry_delay/2 exponential backoff never exceeds maximum delay cap" do
    check all(attempt <- integer(0..20)) do
      # Known to use exponential backoff
      error = Error.new(:network_error)
      delay = Error.retry_delay(error, attempt)

      assert is_integer(delay)
      assert delay >= 0
      # Maximum cap from implementation
      assert delay <= 30_000
    end
  end

  property "Error.format_stacktrace/1 with malformed stacktraces never crashes" do
    check all(stacktrace <- stacktrace_generator()) do
      opts = if stacktrace, do: [stacktrace: stacktrace], else: []
      error = Error.new(:test_error, "Test", opts)

      # Should not crash and should produce some reasonable output
      assert is_list(error.stacktrace) or is_nil(error.stacktrace)

      if is_list(error.stacktrace) do
        # Should limit depth
        assert length(error.stacktrace) <= 10

        # Each entry should be either a map (formatted) or string (fallback)
        Enum.each(error.stacktrace, fn entry ->
          assert is_map(entry) or is_binary(entry)
        end)
      end
    end
  end

  property "Error.is_retryable?/1 with any error always returns boolean" do
    check all(error_type <- error_type_generator()) do
      error = Error.new(error_type)
      result = Error.is_retryable?(error)

      assert is_boolean(result)
    end
  end

  property "Error.suggest_recovery_actions/2 always returns list of strings" do
    check all(
            error_type <- error_type_generator(),
            context <- context_generator()
          ) do
      opts = if context, do: [context: context], else: []
      error = Error.new(error_type, "Test error", opts)

      actions = error.recovery_actions

      assert is_list(actions)

      Enum.each(actions, fn action ->
        assert is_binary(action)
        assert String.length(action) > 0
      end)
    end
  end

  property "Error serialization and deserialization roundtrip preserves all fields" do
    check all(
            error_type <- error_type_generator(),
            message <- message_generator(),
            context <- context_generator(),
            correlation_id <- one_of([constant(nil), string(:alphanumeric)])
          ) do
      opts = [
        context: context || %{},
        correlation_id: correlation_id
      ]

      original_error = Error.new(error_type, message, opts)

      # Serialize to Erlang term format
      serialized = :erlang.term_to_binary(original_error)
      deserialized = :erlang.binary_to_term(serialized)

      # All fields should be preserved
      assert deserialized.error_type == original_error.error_type
      assert deserialized.message == original_error.message
      assert deserialized.context == original_error.context
      assert deserialized.correlation_id == original_error.correlation_id
      assert deserialized.code == original_error.code
      assert deserialized.category == original_error.category
      assert deserialized.subcategory == original_error.subcategory
      assert deserialized.retry_strategy == original_error.retry_strategy
      assert deserialized.recovery_actions == original_error.recovery_actions

      # Timestamp should be preserved (DateTime structs)
      assert DateTime.compare(deserialized.timestamp, original_error.timestamp) == :eq
    end
  end
end
