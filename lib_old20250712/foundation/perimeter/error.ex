defmodule Foundation.Perimeter.Error do
  @moduledoc """
  Error struct for Foundation Perimeter validation failures.
  
  Provides structured error information for different perimeter zones
  with appropriate context for debugging and monitoring.
  """

  @type zone :: :external | :strategic | :coupling | :core
  @type contract :: atom()
  @type reason :: term()

  @type t :: %__MODULE__{
    zone: zone(),
    contract: contract(),
    reason: reason(),
    params: map() | nil,
    timestamp: DateTime.t(),
    context: map()
  }

  defstruct [
    :zone,
    :contract, 
    :reason,
    :params,
    :timestamp,
    context: %{}
  ]

  @doc """
  Creates a new perimeter error with current timestamp.
  """
  def new(zone, contract, reason, params \\ nil, context \\ %{}) do
    %__MODULE__{
      zone: zone,
      contract: contract,
      reason: reason,
      params: params,
      timestamp: DateTime.utc_now(),
      context: context
    }
  end

  @doc """
  Formats error for logging with appropriate detail level based on zone.
  """
  def format_for_logging(%__MODULE__{} = error) do
    base_info = %{
      zone: error.zone,
      contract: error.contract,
      reason: format_reason(error.reason),
      timestamp: error.timestamp
    }

    case error.zone do
      :external ->
        # Include more context for external errors (security relevant)
        Map.merge(base_info, %{
          params_included: not is_nil(error.params),
          context: error.context
        })

      :strategic ->
        # Include service context for boundary errors
        Map.merge(base_info, %{
          context: error.context
        })

      zone when zone in [:coupling, :core] ->
        # Minimal logging for internal zones (performance critical)
        base_info
    end
  end

  @doc """
  Converts error to user-friendly message for external APIs.
  """
  def to_external_message(%__MODULE__{zone: :external} = error) do
    case error.reason do
      {:validation_failed, field, details} ->
        "Validation failed for field '#{field}': #{details}"
      
      {:required_field_missing, field} ->
        "Required field '#{field}' is missing"
      
      {:invalid_format, field, expected} ->
        "Field '#{field}' has invalid format, expected: #{expected}"
      
      {:invalid_input, message} ->
        "Invalid input: #{message}"
      
      _ ->
        "Request validation failed"
    end
  end

  def to_external_message(%__MODULE__{}) do
    "Internal service error"
  end

  @doc """
  Creates error for validation failures with field-specific context.
  """
  def validation_error(zone, contract, field, reason, value \\ nil) do
    context = if value, do: %{field: field, value: inspect(value)}, else: %{field: field}
    
    new(zone, contract, {:validation_failed, field, reason}, nil, context)
  end

  @doc """
  Creates error for missing required fields.
  """
  def required_field_error(zone, contract, field) do
    new(zone, contract, {:required_field_missing, field}, nil, %{field: field})
  end

  @doc """
  Creates error for format validation failures.
  """
  def format_error(zone, contract, field, expected_format, value) do
    context = %{field: field, expected: expected_format, received: inspect(value)}
    new(zone, contract, {:invalid_format, field, expected_format}, nil, context)
  end

  defp format_reason({:validation_failed, field, details}), do: "#{field}: #{details}"
  defp format_reason({:required_field_missing, field}), do: "missing required field: #{field}"
  defp format_reason({:invalid_format, field, expected}), do: "#{field} format invalid, expected: #{expected}"
  defp format_reason({:invalid_input, message}), do: "invalid input: #{message}"
  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)
end