defmodule Foundation.Types.Error do
  @moduledoc """
  Pure data structure for Foundation errors.

  Contains structured error information with hierarchical codes,
  context, and recovery suggestions. No business logic - just data.

  All errors must have a code, error type, message, and severity.
  Timestamp defaults to creation time if not provided.

  See `@type t` for the complete type specification.

  ## Examples

      iex> error = Foundation.Types.Error.new([
      ...>   code: 1001,
      ...>   error_type: :validation_failed,
      ...>   message: "Invalid configuration",
      ...>   severity: :high
      ...> ])
      iex> error.error_type
      :validation_failed
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

  @doc """
  Create a new error structure.

  ## Parameters
  - `fields`: Keyword list containing at minimum `:code`, `:error_type`, `:message`, and `:severity`

  ## Examples

      iex> error = Foundation.Types.Error.new([
      ...>   code: 2001,
      ...>   error_type: :network_timeout,
      ...>   message: "Connection timed out",
      ...>   severity: :medium,
      ...>   retry_strategy: :exponential_backoff
      ...> ])
      iex> error.error_type
      :network_timeout

      iex> error = Foundation.Types.Error.new([
      ...>   code: 3001,
      ...>   error_type: :data_corruption,
      ...>   message: "Data integrity check failed",
      ...>   severity: :critical,
      ...>   context: %{table: "events", checksum: "abc123"}
      ...> ])
      iex> error.severity
      :critical

  ## Raises
  - `KeyError` if required keys are missing
  """
  @spec new(keyword()) :: t()
  def new(fields \\ []) do
    defaults = [
      timestamp: DateTime.utc_now(),
      context: %{},
      recovery_actions: []
    ]

    struct(__MODULE__, Keyword.merge(defaults, fields))
  end
end
