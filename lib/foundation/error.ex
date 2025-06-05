defmodule Foundation.Error do
  @moduledoc """
  Enhanced error handling with hierarchical error codes and comprehensive error management.

  Phase 1 Implementation:
  - Hierarchical error code system (C000-C999, S000-S999, etc.)
  - Enhanced error context and recovery strategies
  - Standardized error propagation patterns
  - Error metrics and analysis capabilities

  All errors must have a code, error_type, message, and severity.
  Other fields provide additional context and are optional.

  See `@type t` for the complete type specification.

  ## Examples

      iex> error = Foundation.Error.new(:config_not_found, "Config missing")
      iex> error.error_type
      :config_not_found

      iex> error = Foundation.Error.new(:network_error, nil, context: %{url: "http://example.com"})
      iex> is_map(error.context)
      true
  """

  @typedoc "Specific error type identifier"
  @type error_code :: atom()

  @typedoc "Additional context information for the error"
  @type error_context :: map()

  @typedoc "Stack trace information as a list of maps"
  @type stacktrace_info :: [map()]

  @typedoc "High-level error category"
  @type error_category :: :config | :system | :data | :external

  @typedoc "Specific error subcategory within a category"
  @type error_subcategory :: :structure | :validation | :access | :runtime

  @typedoc "Error severity level"
  @type error_severity :: :low | :medium | :high | :critical

  @typedoc "Strategy for retrying failed operations"
  @type retry_strategy :: :no_retry | :immediate | :fixed_delay | :exponential_backoff

  @enforce_keys [:code, :error_type, :message, :severity]
  defstruct [
    :code,
    :error_type,
    :message,
    :severity,
    :context,
    :correlation_id,
    :timestamp,
    :stacktrace,
    :category,
    :subcategory,
    :retry_strategy,
    :recovery_actions
  ]

  @type t :: %__MODULE__{
          code: pos_integer(),
          error_type: error_code(),
          message: String.t(),
          severity: error_severity(),
          context: error_context() | nil,
          correlation_id: String.t() | nil,
          timestamp: DateTime.t() | nil,
          stacktrace: stacktrace_info() | nil,
          category: error_category() | nil,
          subcategory: error_subcategory() | nil,
          retry_strategy: retry_strategy() | nil,
          recovery_actions: [String.t()] | nil
        }

  @error_definitions %{
    # Configuration Errors
    {:config, :structure, :invalid_config_structure} =>
      {1101, :high, "Configuration structure is invalid"},
    {:config, :structure, :missing_required_field} =>
      {1102, :high, "Required configuration field missing"},
    {:config, :validation, :invalid_config_value} =>
      {1201, :medium, "Configuration value failed validation"},
    {:config, :validation, :constraint_violation} =>
      {1202, :medium, "Configuration constraint violated"},
    {:config, :validation, :range_error} => {1203, :low, "Value outside acceptable range"},
    {:config, :access, :config_not_found} => {1301, :high, "Configuration not found"},
    {:config, :runtime, :config_update_forbidden} =>
      {1401, :medium, "Configuration update not allowed"},

    # System Errors
    {:system, :initialization, :initialization_failed} =>
      {2101, :critical, "System initialization failed"},
    {:system, :initialization, :service_unavailable} =>
      {2102, :high, "Required service unavailable"},
    {:system, :resources, :resource_exhausted} => {2201, :high, "System resources exhausted"},
    {:system, :dependencies, :dependency_failed} => {2301, :high, "Required dependency failed"},
    {:system, :runtime, :internal_error} => {2401, :critical, "Internal system error"},

    # Data Errors
    {:data, :serialization, :serialization_failed} => {3101, :medium, "Data serialization failed"},
    {:data, :serialization, :deserialization_failed} =>
      {3102, :medium, "Data deserialization failed"},
    {:data, :validation, :type_mismatch} => {3201, :low, "Data type mismatch"},
    {:data, :validation, :format_error} => {3202, :low, "Data format error"},
    {:data, :corruption, :data_corruption} => {3301, :critical, "Data corruption detected"},
    {:data, :not_found, :data_not_found} => {3401, :low, "Requested data not found"},

    # External Errors
    {:external, :network, :network_error} => {4101, :medium, "Network communication error"},
    {:external, :service, :external_service_error} => {4201, :medium, "External service error"},
    {:external, :timeout, :timeout} => {4301, :medium, "Operation timeout"},
    {:external, :auth, :authentication_failed} => {4401, :high, "Authentication failed"},

    # Validation-specific errors
    {:data, :validation, :validation_failed} => {3203, :medium, "Data validation failed"},
    {:data, :validation, :invalid_input} => {3204, :low, "Invalid input provided"}
  }

  # Additional error definitions needed by tests
  @additional_error_definitions %{
    {:system, :initialization, :service_unavailable} =>
      {2102, :high, "Required service unavailable"}
  }

  # Combined error definitions
  @all_error_definitions Map.merge(@error_definitions, @additional_error_definitions)

  @doc """
  Create a new error with the given error type and optional message.

  ## Parameters
  - `error_type`: The specific error type atom
  - `message`: Custom error message (optional, will use default if nil)
  - `opts`: Additional options including context, correlation_id, stacktrace

  ## Examples

      iex> error = Foundation.Error.new(:config_not_found)
      iex> error.error_type
      :config_not_found

      iex> error = Foundation.Error.new(:timeout, "Request timed out", context: %{timeout: 5000})
      iex> error.message
      "Request timed out"

  ## Raises
  - `KeyError` if required fields are missing
  """
  @spec new(error_code(), String.t() | nil, keyword()) :: t()
  def new(error_type, message \\ nil, opts \\ []) do
    {code, severity, default_message} = get_error_definition(error_type)
    {category, subcategory} = categorize_error(error_type)

    %__MODULE__{
      code: code,
      error_type: error_type,
      message: message || default_message,
      severity: severity,
      context: Keyword.get(opts, :context, %{}),
      correlation_id: Keyword.get(opts, :correlation_id),
      timestamp: DateTime.utc_now(),
      stacktrace: format_stacktrace(Keyword.get(opts, :stacktrace)),
      category: category,
      subcategory: subcategory,
      retry_strategy: determine_retry_strategy(error_type, severity),
      recovery_actions: suggest_recovery_actions(error_type, opts)
    }
  end

  @doc """
  Create an error result tuple.

  ## Parameters
  - `error_type`: The specific error type atom
  - `message`: Custom error message (optional)
  - `opts`: Additional options

  ## Examples

      iex> Foundation.Error.error_result(:data_not_found)
      {:error, %Foundation.Error{error_type: :data_not_found, ...}}
  """
  @spec error_result(error_code(), String.t() | nil, keyword()) :: {:error, t()}
  def error_result(error_type, message \\ nil, opts \\ []) do
    {:error, new(error_type, message, opts)}
  end

  @doc """
  Wrap an existing result with additional error context.

  ## Parameters
  - `result`: The result to potentially wrap
  - `error_type`: The wrapper error type
  - `message`: Custom error message (optional)
  - `opts`: Additional options

  ## Examples

      iex> result = {:error, :timeout}
      iex> Foundation.Error.wrap_error(result, :external_service_error)
      {:error, %Foundation.Error{...}}
  """
  @spec wrap_error(term(), error_code(), String.t() | nil, keyword()) :: term()
  def wrap_error(result, error_type, message \\ nil, opts \\ []) do
    case result do
      {:error, existing_error} when is_struct(existing_error, __MODULE__) ->
        # Chain errors while preserving original context
        enhanced_error = %{
          existing_error
          | context:
              Map.merge(existing_error.context || %{}, %{
                wrapped_by: error_type,
                wrapper_message: message,
                wrapper_context: Keyword.get(opts, :context, %{})
              })
        }

        {:error, enhanced_error}

      {:error, reason} ->
        # Wrap raw error reasons
        error_result(
          error_type,
          message,
          Keyword.put(
            opts,
            :context,
            Map.merge(
              Keyword.get(opts, :context, %{}),
              %{original_reason: reason}
            )
          )
        )

      other ->
        other
    end
  end

  ## Error Analysis and Recovery

  def is_retryable?(%__MODULE__{retry_strategy: strategy}) do
    strategy != :no_retry
  end

  def retry_delay(%__MODULE__{retry_strategy: :exponential_backoff}, attempt) do
    min(1000 * :math.pow(2, attempt), 30_000) |> round()
  end

  def retry_delay(%__MODULE__{retry_strategy: :fixed_delay}, _attempt), do: 1000
  def retry_delay(%__MODULE__{retry_strategy: :immediate}, _attempt), do: 0
  def retry_delay(%__MODULE__{retry_strategy: :no_retry}, _attempt), do: :infinity

  def should_escalate?(%__MODULE__{severity: severity}) do
    severity in [:high, :critical]
  end

  ## String Representation

  def to_string(%__MODULE__{} = error) do
    base = "[#{error.code}:#{error.error_type}] #{error.message}"

    context_str =
      if map_size(error.context) > 0 do
        " | Context: #{inspect(error.context, limit: 3)}"
      else
        ""
      end

    severity_str = " | Severity: #{error.severity}"

    base <> context_str <> severity_str
  end

  ## Error Metrics Collection

  def collect_error_metrics(%__MODULE__{} = error) do
    # Emit telemetry for error tracking
    Foundation.Telemetry.emit_counter(
      [:foundation, :errors, error.category, error.subcategory],
      %{
        error_type: error.error_type,
        severity: error.severity,
        code: error.code
      }
    )
  end

  ## Private Implementation

  @spec get_error_definition(error_code()) :: {pos_integer(), error_severity(), String.t()}
  defp get_error_definition(error_type) do
    # Find the error definition by searching for matching error_type
    case Enum.find(@all_error_definitions, fn {key, _value} ->
           case key do
             {_category, _subcategory, ^error_type} -> true
             _ -> false
           end
         end) do
      {_key, definition} -> definition
      nil -> {9999, :medium, "Unknown error"}
    end
  end

  @spec categorize_error(error_code()) :: {error_category(), error_subcategory()}
  defp categorize_error(error_type) do
    case Enum.find(@all_error_definitions, fn {key, _value} ->
           case key do
             {_category, _subcategory, ^error_type} -> true
             _ -> false
           end
         end) do
      {{category, subcategory, _error_type}, _definition} -> {category, subcategory}
      nil -> {:unknown, :unknown}
    end
  end

  @spec determine_retry_strategy(error_code(), error_severity()) :: retry_strategy()
  defp determine_retry_strategy(error_type, severity) do
    case {error_type, severity} do
      {:timeout, _} -> :exponential_backoff
      {:network_error, _} -> :exponential_backoff
      {:external_service_error, _} -> :fixed_delay
      {_, :critical} -> :no_retry
      {_, :high} -> :immediate
      # Config and data validation errors usually aren't retryable
      {:invalid_config_value, _} -> :no_retry
      {:data_corruption, _} -> :no_retry
      # Resource exhaustion should allow immediate retry
      {:resource_exhausted, _} -> :immediate
      _ -> :fixed_delay
    end
  end

  @spec suggest_recovery_actions(error_code(), keyword()) :: [String.t()]
  defp suggest_recovery_actions(error_type, opts) do
    base_actions =
      case error_type do
        :config_not_found ->
          ["Check configuration file", "Verify configuration path"]

        :invalid_config_value ->
          ["Check configuration format", "Validate against schema", "Review documentation"]

        :service_unavailable ->
          ["Check service health", "Verify network connectivity", "Review service logs"]

        :resource_exhausted ->
          ["Check memory usage", "Review resource limits", "Scale resources if needed"]

        :network_error ->
          ["Check network connectivity", "Retry with exponential backoff"]

        :timeout ->
          ["Increase timeout value", "Check network latency", "Review service performance"]

        :data_corruption ->
          ["Restore from backup", "Contact system administrator"]

        _ ->
          ["Check logs for details", "Review error context", "Contact support if needed"]
      end

    # Add context-specific actions
    context_actions =
      case Keyword.get(opts, :context) do
        %{operation: operation} -> ["Review #{operation} implementation"]
        _ -> []
      end

    base_actions ++ context_actions
  end

  @spec format_stacktrace(list() | nil) :: stacktrace_info() | nil
  defp format_stacktrace(nil), do: nil

  defp format_stacktrace(stacktrace) when is_list(stacktrace) do
    stacktrace
    # Limit stacktrace depth to 10 entries
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

      other ->
        inspect(other)
    end)
  end
end
