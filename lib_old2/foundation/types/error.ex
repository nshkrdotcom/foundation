defmodule Foundation.Types.Error do
  @moduledoc """
  Unified error type system for the Foundation infrastructure.

  Provides a consistent error structure across all Foundation components,
  with support for error categorization, severity levels, and retry strategies.
  Designed for multi-agent environments with rich context information.

  ## Features

  - **Standardized Structure**: Consistent error format across all components
  - **Severity Classification**: Error prioritization for monitoring and alerting
  - **Retry Strategies**: Built-in guidance for automatic error recovery
  - **Rich Context**: Detailed information for debugging and telemetry
  - **Agent Awareness**: Error attribution to specific agents and capabilities
  - **Distribution Ready**: Serializable for cross-node error propagation

  ## Usage

      # Basic error creation
      error = Error.new(
        code: 1001,
        error_type: :validation_failed,
        message: "Invalid input parameters",
        severity: :medium
      )

      # Error with context and retry strategy
      error = Error.new(
        code: 2001,
        error_type: :service_unavailable,
        message: "Database connection failed",
        severity: :high,
        context: %{host: "db.example.com", port: 5432},
        retry_strategy: :exponential_backoff
      )

      # Agent-specific error
      error = Error.new(
        code: 3001,
        error_type: :agent_resource_exhausted,
        message: "Agent memory limit exceeded",
        severity: :critical,
        context: %{agent_id: :ml_agent_1, memory_usage: 0.95},
        agent_context: %{capability: :inference, health: :degraded}
      )
  """

  @type error_code :: pos_integer()
  @type error_type :: atom()
  @type severity :: :low | :medium | :high | :critical
  @type retry_strategy :: :none | :fixed_delay | :exponential_backoff | :linear_backoff | :custom
  @type context :: map()
  @type agent_context :: %{
    agent_id: atom() | String.t(),
    capability: atom(),
    health: :healthy | :degraded | :unhealthy,
    resource_usage: map()
  }

  defstruct [
    :code,
    :error_type,
    :message,
    :severity,
    :context,
    :agent_context,
    :retry_strategy,
    :timestamp,
    :correlation_id,
    :stack_trace
  ]

  @type t :: %__MODULE__{
    code: error_code(),
    error_type: error_type(),
    message: String.t(),
    severity: severity(),
    context: context(),
    agent_context: agent_context() | nil,
    retry_strategy: retry_strategy(),
    timestamp: DateTime.t(),
    correlation_id: String.t(),
    stack_trace: list() | nil
  }

  # Error Code Ranges
  @error_code_ranges %{
    # 1000-1999: General validation and input errors
    validation: 1000..1999,

    # 2000-2999: Service and infrastructure errors
    infrastructure: 2000..2999,

    # 3000-3999: Agent-specific errors
    agent: 3000..3999,

    # 4000-4999: Coordination and consensus errors
    coordination: 4000..4999,

    # 5000-5999: Circuit breaker and resilience errors
    circuit_breaker: 5000..5999,

    # 6000-6999: Rate limiting errors
    rate_limiting: 6000..6999,

    # 7000-7999: Process registry errors
    process_registry: 7000..7999,

    # 8000-8999: Telemetry and monitoring errors
    telemetry: 8000..8999,

    # 9000-9999: Unknown and system errors
    system: 9000..9999
  }

  @doc """
  Create a new Foundation error with the specified parameters.

  ## Parameters
  - `code`: Unique error code for identification and categorization
  - `error_type`: Semantic error type (atom)
  - `message`: Human-readable error description
  - `severity`: Error severity level
  - `context`: Additional error context (optional)
  - `agent_context`: Agent-specific context (optional)
  - `retry_strategy`: Suggested retry approach (optional)

  ## Examples

      iex> Error.new(
      ...>   code: 1001,
      ...>   error_type: :invalid_input,
      ...>   message: "Required field missing",
      ...>   severity: :medium
      ...> )
      %Error{code: 1001, error_type: :invalid_input, ...}
  """
  @spec new(keyword()) :: t()
  def new(options) do
    code = Keyword.fetch!(options, :code)
    error_type = Keyword.fetch!(options, :error_type)
    message = Keyword.fetch!(options, :message)
    severity = Keyword.get(options, :severity, :medium)

    context = Keyword.get(options, :context, %{})
    agent_context = Keyword.get(options, :agent_context, nil)
    retry_strategy = Keyword.get(options, :retry_strategy, :none)

    %__MODULE__{
      code: code,
      error_type: error_type,
      message: message,
      severity: severity,
      context: context,
      agent_context: agent_context,
      retry_strategy: retry_strategy,
      timestamp: DateTime.utc_now(),
      correlation_id: generate_correlation_id(),
      stack_trace: capture_stack_trace()
    }
  end

  @doc """
  Create an error from an exception with automatic categorization.

  Converts standard Elixir exceptions into Foundation error format,
  attempting to infer appropriate error codes and types.
  """
  @spec from_exception(Exception.t(), keyword()) :: t()
  def from_exception(exception, options \\ []) do
    {code, error_type} = categorize_exception(exception)

    base_options = [
      code: code,
      error_type: error_type,
      message: Exception.message(exception),
      severity: Keyword.get(options, :severity, :high),
      context: Map.merge(
        %{exception_type: exception.__struct__},
        Keyword.get(options, :context, %{})
      )
    ]

    merged_options = Keyword.merge(base_options, options)
    new(merged_options)
  end

  @doc """
  Add agent context to an existing error.

  Useful for enriching errors with agent-specific information
  as they propagate through the system.
  """
  @spec add_agent_context(t(), agent_context()) :: t()
  def add_agent_context(%__MODULE__{} = error, agent_context) do
    %{error | agent_context: agent_context}
  end

  @doc """
  Add additional context to an existing error.

  Merges new context with existing context, allowing for
  error enrichment as it moves through different layers.
  """
  @spec add_context(t(), context()) :: t()
  def add_context(%__MODULE__{} = error, additional_context) do
    merged_context = Map.merge(error.context, additional_context)
    %{error | context: merged_context}
  end

  @doc """
  Determine if an error is retryable based on its retry strategy.
  """
  @spec retryable?(t()) :: boolean()
  def retryable?(%__MODULE__{retry_strategy: :none}), do: false
  def retryable?(%__MODULE__{retry_strategy: _}), do: true

  @doc """
  Check if an error falls within a specific category.

  ## Examples

      iex> error = Error.new(code: 1001, error_type: :validation_failed, message: "test")
      iex> Error.category?(error, :validation)
      true
  """
  @spec category?(t(), atom()) :: boolean()
  def category?(%__MODULE__{code: code}, category) do
    case Map.get(@error_code_ranges, category) do
      nil -> false
      range -> code in range
    end
  end

  @doc """
  Get the error category based on the error code.
  """
  @spec get_category(t()) :: atom() | nil
  def get_category(%__MODULE__{code: code}) do
    @error_code_ranges
    |> Enum.find(fn {_category, range} -> code in range end)
    |> case do
      {category, _range} -> category
      nil -> :unknown
    end
  end

  @doc """
  Convert error to a map suitable for JSON serialization.

  Useful for API responses, logging, and cross-service communication.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = error) do
    %{
      code: error.code,
      error_type: error.error_type,
      message: error.message,
      severity: error.severity,
      context: error.context,
      agent_context: error.agent_context,
      retry_strategy: error.retry_strategy,
      timestamp: DateTime.to_iso8601(error.timestamp),
      correlation_id: error.correlation_id,
      category: get_category(error)
    }
  end

  @doc """
  Create an error from a serialized map.

  Inverse of `to_map/1`, useful for deserializing errors
  received from other services or storage.
  """
  @spec from_map(map()) :: t()
  def from_map(error_map) do
    timestamp = case Map.get(error_map, "timestamp") do
      nil -> DateTime.utc_now()
      iso_string when is_binary(iso_string) ->
        case DateTime.from_iso8601(iso_string) do
          {:ok, dt, _} -> dt
          _ -> DateTime.utc_now()
        end
      %DateTime{} = dt -> dt
    end

    %__MODULE__{
      code: Map.get(error_map, "code"),
      error_type: atomize_key(Map.get(error_map, "error_type")),
      message: Map.get(error_map, "message"),
      severity: atomize_key(Map.get(error_map, "severity")),
      context: Map.get(error_map, "context", %{}),
      agent_context: Map.get(error_map, "agent_context"),
      retry_strategy: atomize_key(Map.get(error_map, "retry_strategy")),
      timestamp: timestamp,
      correlation_id: Map.get(error_map, "correlation_id"),
      stack_trace: nil
    }
  end

  @doc """
  Check if an error should trigger an alert based on severity.
  """
  @spec alertable?(t()) :: boolean()
  def alertable?(%__MODULE__{severity: severity}) do
    severity in [:high, :critical]
  end

  @doc """
  Get suggested retry delay in milliseconds based on retry strategy.

  Returns suggested delay for the given attempt number.
  """
  @spec suggested_retry_delay(t(), pos_integer()) :: pos_integer() | nil
  def suggested_retry_delay(%__MODULE__{retry_strategy: :none}, _attempt), do: nil
  def suggested_retry_delay(%__MODULE__{retry_strategy: :fixed_delay}, _attempt), do: 1_000
  def suggested_retry_delay(%__MODULE__{retry_strategy: :linear_backoff}, attempt), do: attempt * 1_000
  def suggested_retry_delay(%__MODULE__{retry_strategy: :exponential_backoff}, attempt) do
    min(trunc(:math.pow(2, attempt) * 1_000), 30_000)
  end
  def suggested_retry_delay(%__MODULE__{retry_strategy: :custom}, _attempt), do: 5_000

  # Private Implementation

  defp categorize_exception(%ArgumentError{}), do: {1002, :invalid_argument}
  defp categorize_exception(%FunctionClauseError{}), do: {1003, :invalid_argument}
  defp categorize_exception(%MatchError{}), do: {1004, :pattern_match_failed}
  defp categorize_exception(%Protocol.UndefinedError{}), do: {1005, :protocol_undefined}
  defp categorize_exception(%UndefinedFunctionError{}), do: {1006, :function_undefined}
  defp categorize_exception(%RuntimeError{}), do: {9001, :runtime_error}
  defp categorize_exception(%SystemLimitError{}), do: {9002, :system_limit_exceeded}
  defp categorize_exception(%ErlangError{}), do: {9003, :erlang_error}
  defp categorize_exception(_), do: {9999, :unknown_exception}

  defp generate_correlation_id do
    # Generate a short, unique correlation ID
    :crypto.strong_rand_bytes(8)
    |> Base.url_encode64(padding: false)
    |> String.slice(0, 8)
  end

  defp capture_stack_trace do
    # Capture current stack trace, excluding this function
    case Process.info(self(), :current_stacktrace) do
      {:current_stacktrace, stacktrace} ->
        stacktrace
        |> Enum.drop(1)  # Remove this function from trace
        |> Enum.take(10) # Limit to top 10 frames

      _ -> nil
    end
  end

  defp atomize_key(nil), do: nil
  defp atomize_key(value) when is_atom(value), do: value
  defp atomize_key(value) when is_binary(value) do
    try do
      String.to_existing_atom(value)
    rescue
      ArgumentError -> String.to_atom(value)
    end
  end
  defp atomize_key(value), do: value
end