defmodule Foundation.Retry.Config do
  @moduledoc """
  User-facing retry configuration with sensible defaults.
  """

  @enforce_keys []
  defstruct [
    :max_retries,
    :base_delay_ms,
    :max_delay_ms,
    :jitter_pct,
    :progress_timeout_ms,
    :max_connections,
    :enable_retry_logic
  ]

  @type t :: %__MODULE__{
          max_retries: non_neg_integer() | :infinity,
          base_delay_ms: pos_integer(),
          max_delay_ms: pos_integer(),
          jitter_pct: float(),
          progress_timeout_ms: pos_integer(),
          max_connections: pos_integer(),
          enable_retry_logic: boolean()
        }

  @default_max_retries :infinity
  @default_base_delay_ms 500
  @default_max_delay_ms 10_000
  @default_jitter_pct 0.25
  @default_progress_timeout_ms 7_200_000
  @default_max_connections 1000
  @default_enable_retry_logic true

  @doc """
  Build a retry configuration.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      max_retries: Keyword.get(opts, :max_retries, @default_max_retries),
      base_delay_ms: Keyword.get(opts, :base_delay_ms, @default_base_delay_ms),
      max_delay_ms: Keyword.get(opts, :max_delay_ms, @default_max_delay_ms),
      jitter_pct: Keyword.get(opts, :jitter_pct, @default_jitter_pct),
      progress_timeout_ms: Keyword.get(opts, :progress_timeout_ms, @default_progress_timeout_ms),
      max_connections: Keyword.get(opts, :max_connections, @default_max_connections),
      enable_retry_logic: Keyword.get(opts, :enable_retry_logic, @default_enable_retry_logic)
    }
    |> validate!()
  end

  @doc """
  Return the default retry configuration.
  """
  @spec default() :: t()
  def default, do: new()

  @doc """
  Validate a retry configuration, raising on invalid values.
  """
  @spec validate!(t()) :: t()
  def validate!(%__MODULE__{} = config) do
    validate_max_retries!(config.max_retries)
    validate_base_delay_ms!(config.base_delay_ms)
    validate_max_delay_ms!(config.max_delay_ms, config.base_delay_ms)
    validate_jitter_pct!(config.jitter_pct)
    validate_progress_timeout_ms!(config.progress_timeout_ms)
    validate_max_connections!(config.max_connections)
    validate_enable_retry_logic!(config.enable_retry_logic)
    config
  end

  @doc """
  Convert to Retry.Handler options.
  """
  @spec to_handler_opts(t()) :: keyword()
  def to_handler_opts(%__MODULE__{} = config) do
    [
      max_retries: config.max_retries,
      base_delay_ms: config.base_delay_ms,
      max_delay_ms: config.max_delay_ms,
      jitter_pct: config.jitter_pct,
      progress_timeout_ms: config.progress_timeout_ms
    ]
  end

  defp validate_max_retries!(max_retries) do
    unless (is_integer(max_retries) and max_retries >= 0) or max_retries == :infinity do
      raise ArgumentError,
            "max_retries must be a non-negative integer or :infinity, got: #{inspect(max_retries)}"
    end
  end

  defp validate_base_delay_ms!(base_delay_ms) do
    unless is_integer(base_delay_ms) and base_delay_ms > 0 do
      raise ArgumentError,
            "base_delay_ms must be a positive integer, got: #{inspect(base_delay_ms)}"
    end
  end

  defp validate_max_delay_ms!(max_delay_ms, base_delay_ms) do
    unless is_integer(max_delay_ms) and max_delay_ms >= base_delay_ms do
      raise ArgumentError,
            "max_delay_ms must be >= base_delay_ms, got: #{inspect(max_delay_ms)}"
    end
  end

  defp validate_jitter_pct!(jitter_pct) do
    unless is_float(jitter_pct) and jitter_pct >= 0.0 and jitter_pct <= 1.0 do
      raise ArgumentError,
            "jitter_pct must be a float between 0.0 and 1.0, got: #{inspect(jitter_pct)}"
    end
  end

  defp validate_progress_timeout_ms!(progress_timeout_ms) do
    unless is_integer(progress_timeout_ms) and progress_timeout_ms > 0 do
      raise ArgumentError,
            "progress_timeout_ms must be a positive integer, got: #{inspect(progress_timeout_ms)}"
    end
  end

  defp validate_max_connections!(max_connections) do
    unless is_integer(max_connections) and max_connections > 0 do
      raise ArgumentError,
            "max_connections must be a positive integer, got: #{inspect(max_connections)}"
    end
  end

  defp validate_enable_retry_logic!(enable_retry_logic) do
    unless is_boolean(enable_retry_logic) do
      raise ArgumentError,
            "enable_retry_logic must be a boolean, got: #{inspect(enable_retry_logic)}"
    end
  end
end
