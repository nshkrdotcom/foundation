defmodule Foundation.ErrorContext do
  @moduledoc """
  Enhanced error context system with proper propagation and debugging support.

  Provides:
  - Nested context support with breadcrumbs
  - Operation tracking and correlation
  - Emergency context recovery
  - Enhanced error propagation patterns
  """

  alias Foundation.Error

  @type t :: %__MODULE__{
          operation_id: pos_integer(),
          module: module(),
          function: atom(),
          correlation_id: String.t(),
          start_time: integer(),
          metadata: map(),
          breadcrumbs: [breadcrumb()],
          parent_context: t() | nil
        }

  @type context :: t()

  @type breadcrumb :: %{
          module: module(),
          function: atom(),
          timestamp: integer(),
          metadata: map()
        }

  @enforce_keys [:operation_id, :module, :function, :correlation_id, :start_time]
  defstruct [
    # Unique ID for this operation
    :operation_id,
    # Module where operation started
    :module,
    # Function where operation started
    :function,
    # Cross-system correlation
    :correlation_id,
    # When operation began
    :start_time,
    # Additional context data
    metadata: %{},
    # Operation trail
    breadcrumbs: [],
    # Nested context support
    parent_context: nil
  ]

  ## Context Creation and Management

  @doc """
  Create a new error context for an operation.

  ## Parameters
  - `module`: The module where the operation starts
  - `function`: The function where the operation starts
  - `opts`: Options including correlation_id, metadata, parent_context

  ## Examples

      iex> ErrorContext.new(MyModule, :my_function)
      %ErrorContext{module: MyModule, function: :my_function, ...}
  """
  @spec new(module(), atom(), keyword()) :: t()
  def new(module, function, opts \\ []) do
    %__MODULE__{
      operation_id: generate_id(),
      module: module,
      function: function,
      correlation_id: Keyword.get(opts, :correlation_id, generate_correlation_id()),
      start_time: monotonic_timestamp(),
      metadata: Keyword.get(opts, :metadata, %{}),
      breadcrumbs: [
        %{
          module: module,
          function: function,
          timestamp: monotonic_timestamp(),
          metadata: %{}
        }
      ],
      parent_context: Keyword.get(opts, :parent_context)
    }
  end

  @doc """
  Create a child context inheriting from a parent context.

  ## Parameters
  - `parent`: The parent context
  - `module`: The module for the child operation
  - `function`: The function for the child operation
  - `metadata`: Additional metadata for the child context

  ## Examples

      iex> child = ErrorContext.child_context(parent, ChildModule, :child_function)
      %ErrorContext{parent_context: ^parent, ...}
  """
  @spec child_context(t(), module(), atom(), map()) :: t()
  def child_context(%__MODULE__{} = parent, module, function, metadata \\ %{}) do
    %__MODULE__{
      operation_id: generate_id(),
      module: module,
      function: function,
      correlation_id: parent.correlation_id,
      start_time: monotonic_timestamp(),
      metadata: Map.merge(parent.metadata, metadata),
      breadcrumbs:
        parent.breadcrumbs ++
          [
            %{
              module: module,
              function: function,
              timestamp: monotonic_timestamp(),
              metadata: metadata
            }
          ],
      parent_context: parent
    }
  end

  @doc """
  Add a breadcrumb to track operation flow.

  ## Parameters
  - `context`: The context to add breadcrumb to
  - `module`: Module name for the breadcrumb
  - `function`: Function name for the breadcrumb
  - `metadata`: Additional metadata for this step
  """
  @spec add_breadcrumb(t(), module(), atom(), map()) :: t()
  def add_breadcrumb(%__MODULE__{} = context, module, function, metadata \\ %{}) do
    breadcrumb = %{
      module: module,
      function: function,
      timestamp: monotonic_timestamp(),
      metadata: metadata
    }

    %{context | breadcrumbs: context.breadcrumbs ++ [breadcrumb]}
  end

  @doc """
  Add metadata to an existing context.

  ## Parameters
  - `context`: The context to add metadata to
  - `new_metadata`: Map of metadata to merge
  """
  @spec add_metadata(t(), map()) :: t()
  def add_metadata(%__MODULE__{} = context, new_metadata) when is_map(new_metadata) do
    %{context | metadata: Map.merge(context.metadata, new_metadata)}
  end

  ## Error Context Integration

  @doc """
  Execute a function with error context tracking.

  Automatically captures exceptions and enhances them with context information.

  ## Parameters
  - `context`: The context to use for the operation
  - `fun`: Zero-arity function to execute

  ## Returns
  - The result of the function, or {:error, enhanced_error} on exception
  """
  @spec with_context(t(), (-> term())) :: term() | {:error, Error.t()}
  def with_context(%__MODULE__{} = context, fun) when is_function(fun, 0) do
    # Store context in process dictionary for emergency access
    Process.put(:error_context, context)

    try do
      result = fun.()

      # Clean up and enhance successful results with context
      Process.delete(:error_context)
      enhance_result_with_context(result, context)
    rescue
      exception ->
        # Capture and enhance exception with full context
        enhanced_error = create_exception_error(exception, context, __STACKTRACE__)

        # Clean up
        Process.delete(:error_context)

        # Emit error telemetry
        Error.collect_error_metrics(enhanced_error)

        {:error, enhanced_error}
    end
  end

  @doc """
  Enhance an Error struct with additional context information.

  ## Parameters
  - `error`: The error to enhance
  - `context`: The context to add to the error
  """
  @spec enhance_error(Error.t(), t()) :: Error.t()
  def enhance_error(%Error{} = error, %__MODULE__{} = context) do
    # Enhance existing error with additional context
    enhanced_context =
      Map.merge(error.context, %{
        operation_context: %{
          operation_id: context.operation_id,
          correlation_id: context.correlation_id,
          breadcrumbs: context.breadcrumbs,
          duration_ns: monotonic_timestamp() - context.start_time,
          metadata: context.metadata
        }
      })

    %{
      error
      | context: enhanced_context,
        correlation_id: error.correlation_id || context.correlation_id
    }
  end

  @spec enhance_error({:error, Error.t()}, t()) :: {:error, Error.t()}
  def enhance_error({:error, %Error{} = error}, %__MODULE__{} = context) do
    {:error, enhance_error(error, context)}
  end

  @spec enhance_error({:error, term()}, t()) :: {:error, Error.t()}
  def enhance_error({:error, reason}, %__MODULE__{} = context) do
    # Convert raw error to structured error with context
    error =
      Error.new(:external_error, "External operation failed",
        context: %{
          original_reason: reason,
          operation_context: %{
            operation_id: context.operation_id,
            correlation_id: context.correlation_id,
            breadcrumbs: context.breadcrumbs,
            duration_ns: monotonic_timestamp() - context.start_time
          }
        },
        correlation_id: context.correlation_id
      )

    {:error, error}
  end

  @spec enhance_error(term(), t()) :: term()
  def enhance_error(result, _context), do: result

  ## Context Recovery and Debugging

  @doc """
  Get the current error context from the process dictionary.

  This is an emergency recovery mechanism for debugging.
  """
  @spec get_current_context() :: t() | nil
  def get_current_context do
    # Emergency context retrieval from process dictionary
    Process.get(:error_context)
  end

  @doc """
  Format breadcrumbs as a human-readable string.

  ## Parameters
  - `context`: The context containing breadcrumbs to format
  """
  @spec format_breadcrumbs(t()) :: String.t()
  def format_breadcrumbs(%__MODULE__{breadcrumbs: breadcrumbs}) do
    Enum.map_join(breadcrumbs, " -> ", fn %{module: mod, function: func, timestamp: ts} ->
      relative_time = monotonic_timestamp() - ts
      "#{mod}.#{func} (#{format_duration(relative_time)} ago)"
    end)
  end

  @doc """
  Get the duration of an operation in nanoseconds.

  ## Parameters
  - `context`: The context to calculate duration for
  """
  @spec get_operation_duration(t()) :: integer()
  def get_operation_duration(%__MODULE__{start_time: start_time}) do
    monotonic_timestamp() - start_time
  end

  ## Enhanced Error Context Integration

  @doc """
  Add context to an existing error or create a new one.
  Enhanced version with better error chaining and context preservation.

  ## Parameters
  - `result`: The result to potentially enhance with context
  - `context`: The context to add
  - `additional_info`: Additional context information
  """
  @spec add_context(term(), t() | map(), map()) :: term()
  def add_context(result, context, additional_info \\ %{})

  @spec add_context(:ok, t() | map(), map()) :: :ok
  def add_context(:ok, _context, _additional_info), do: :ok

  @spec add_context({:ok, term()}, t() | map(), map()) :: {:ok, term()}
  def add_context({:ok, _} = success, _context, _additional_info), do: success

  @spec add_context({:error, Error.t()}, t(), map()) :: {:error, Error.t()}
  def add_context({:error, %Error{} = error}, %__MODULE__{} = context, additional_info) do
    enhanced_error = enhance_error(error, context)
    additional_context = Map.merge(enhanced_error.context, additional_info)
    {:error, %{enhanced_error | context: additional_context}}
  end

  @spec add_context({:error, Error.t()}, map(), map()) :: {:error, Error.t()}
  def add_context({:error, %Error{} = error}, context, additional_info) when is_map(context) do
    # Handle legacy map-based context
    updated_context = Map.merge(error.context, Map.merge(context, additional_info))
    {:error, %{error | context: updated_context}}
  end

  @spec add_context({:error, term()}, t(), map()) :: {:error, Error.t()}
  def add_context({:error, reason}, %__MODULE__{} = context, additional_info) do
    full_context =
      Map.merge(additional_info, %{
        original_reason: reason,
        operation_context: %{
          operation_id: context.operation_id,
          correlation_id: context.correlation_id,
          breadcrumbs: context.breadcrumbs,
          duration_ns: get_operation_duration(context),
          metadata: context.metadata
        }
      })

    {:error, Error.new(:external_error, "External operation failed", context: full_context)}
  end

  @spec add_context({:error, term()}, map(), map()) :: {:error, Error.t()}
  def add_context({:error, reason}, context, additional_info) when is_map(context) do
    # Handle legacy map-based context
    full_context = Map.merge(context, Map.merge(additional_info, %{original_reason: reason}))
    {:error, Error.new(:external_error, "External operation failed", context: full_context)}
  end

  ## Private Helpers

  defp enhance_result_with_context(result, context) do
    # For successful results, we might want to add telemetry
    duration = get_operation_duration(context)

    Foundation.Telemetry.emit(
      [:foundation, :operations, :duration],
      %{duration: duration},
      %{
        module: context.module,
        function: context.function,
        correlation_id: context.correlation_id
      }
    )

    result
  end

  defp create_exception_error(exception, context, stacktrace) do
    Error.new(:internal_error, "Exception in operation: #{Exception.message(exception)}",
      context: %{
        exception_type: exception.__struct__,
        exception_message: Exception.message(exception),
        operation_context: %{
          operation_id: context.operation_id,
          correlation_id: context.correlation_id,
          breadcrumbs: context.breadcrumbs,
          duration_ns: get_operation_duration(context),
          metadata: context.metadata
        }
      },
      correlation_id: context.correlation_id,
      stacktrace: format_stacktrace(stacktrace)
    )
  end

  defp format_stacktrace(stacktrace) do
    stacktrace
    # Limit depth
    |> Enum.take(10)
    |> Enum.map(fn
      {module, function, arity, location} ->
        %{
          module: module,
          function: function,
          arity: arity,
          file: Keyword.get(location, :file),
          line: Keyword.get(location, :line)
        }

      entry ->
        %{raw: inspect(entry)}
    end)
  end

  # Utility functions - simplified implementations
  defp generate_id, do: :erlang.unique_integer([:positive])
  defp generate_correlation_id, do: "corr_#{System.unique_integer([:positive])}"
  defp monotonic_timestamp, do: System.monotonic_time(:nanosecond)
  defp format_duration(nanoseconds), do: "#{div(nanoseconds, 1_000_000)}ms"
end
