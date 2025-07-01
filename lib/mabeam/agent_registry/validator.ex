defmodule MABEAM.AgentRegistry.Validator do
  @moduledoc """
  Validation logic for agent metadata and registration requirements.

  Extracted from MABEAM.AgentRegistry to follow single responsibility principle.
  Handles all validation of agent data including metadata structure, required fields,
  and health status validation.
  """

  # Required metadata fields for agents
  @required_fields [:capability, :health_status, :node, :resources]
  @valid_health_statuses [:healthy, :degraded, :unhealthy]

  @doc """
  Validates agent metadata to ensure all required fields are present and valid.

  ## Examples

      iex> validate_agent_metadata(%{capability: [:inference], health_status: :healthy, node: node(), resources: %{}})
      :ok
      
      iex> validate_agent_metadata(%{capability: [:inference]})
      {:error, {:missing_required_fields, [:health_status, :node, :resources]}}
  """
  @spec validate_agent_metadata(map()) :: :ok | {:error, term()}
  def validate_agent_metadata(metadata) do
    case find_missing_fields(metadata) do
      [] ->
        validate_health_status(metadata)

      missing_fields ->
        {:error, {:missing_required_fields, missing_fields}}
    end
  end

  @doc """
  Validates that a process is alive.
  """
  @spec validate_process_alive(pid()) :: :ok | {:error, :process_not_alive}
  def validate_process_alive(pid) do
    if Process.alive?(pid), do: :ok, else: {:error, :process_not_alive}
  end

  @doc """
  Validates that an agent does not already exist in the registry.
  """
  @spec validate_agent_not_exists(:ets.tab(), any()) :: :ok | {:error, :already_exists}
  def validate_agent_not_exists(table, agent_id) do
    if :ets.member(table, agent_id), do: {:error, :already_exists}, else: :ok
  end

  @doc """
  Returns list of required fields for agent metadata.
  """
  @spec required_fields() :: [:capability | :health_status | :node | :resources, ...]
  def required_fields, do: @required_fields

  @doc """
  Returns list of valid health statuses.
  """
  @spec valid_health_statuses() :: [:healthy | :degraded | :unhealthy, ...]
  def valid_health_statuses, do: @valid_health_statuses

  # Private functions

  defp find_missing_fields(metadata) do
    Enum.filter(@required_fields, fn field ->
      not Map.has_key?(metadata, field)
    end)
  end

  defp validate_health_status(metadata) do
    health_status = Map.get(metadata, :health_status)

    if health_status in @valid_health_statuses do
      :ok
    else
      {:error, {:invalid_health_status, health_status, @valid_health_statuses}}
    end
  end
end
