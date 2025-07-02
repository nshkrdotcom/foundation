defimpl Foundation.Registry, for: Any do
  @moduledoc """
  Fallback implementation for Foundation.Registry protocol.

  This implementation can use either process dictionary (legacy) or ETS (new)
  based on feature flags for gradual migration.
  """

  require Logger
  alias Foundation.FeatureFlags
  alias Foundation.Protocols.RegistryETS

  @doc """
  Registers a process using either process dictionary or ETS storage.
  """
  def register(_impl, key, pid, metadata \\ %{}) do
    start_time = System.monotonic_time()
    
    result = if FeatureFlags.enabled?(:use_ets_agent_registry) do
      register_ets(key, pid, metadata)
    else
      register_legacy(key, pid, metadata)
    end
    
    # Emit telemetry event
    end_time = System.monotonic_time()
    duration = end_time - start_time
    
    :telemetry.execute(
      [:foundation, :registry, :register],
      %{duration: duration, count: 1},
      %{
        key: key,
        pid: pid,
        metadata: metadata,
        implementation: if(FeatureFlags.enabled?(:use_ets_agent_registry), do: :ets, else: :legacy),
        result: result
      }
    )
    
    result
  end

  # New ETS implementation
  defp register_ets(key, pid, metadata) do
    case RegistryETS.register_agent(key, pid, metadata) do
      :ok -> :ok
      {:error, _} = error -> error
    end
  end

  # Legacy process dictionary implementation
  defp register_legacy(key, pid, metadata) do
    agents = Process.get(:registered_agents, %{})

    case Map.has_key?(agents, key) do
      true ->
        {:error, :already_exists}

      false ->
        new_agents = Map.put(agents, key, {pid, metadata})
        Process.put(:registered_agents, new_agents)
        :ok
    end
  end

  @doc """
  Looks up a process by key using either process dictionary or ETS storage.
  """
  def lookup(_impl, key) do
    if FeatureFlags.enabled?(:use_ets_agent_registry) do
      lookup_ets(key)
    else
      lookup_legacy(key)
    end
  end

  defp lookup_ets(key) do
    case RegistryETS.get_agent_with_metadata(key) do
      {:ok, {pid, metadata}} -> {:ok, {pid, metadata}}
      {:error, :not_found} -> :error
    end
  end

  defp lookup_legacy(key) do
    agents = Process.get(:registered_agents, %{})

    case Map.get(agents, key) do
      {pid, metadata} -> {:ok, {pid, metadata}}
      nil -> :error
    end
  end

  @doc """
  Finds processes by attribute using either process dictionary or ETS storage.
  """
  def find_by_attribute(_impl, attribute, value) do
    if FeatureFlags.enabled?(:use_ets_agent_registry) do
      find_by_attribute_ets(attribute, value)
    else
      find_by_attribute_legacy(attribute, value)
    end
  end

  defp find_by_attribute_ets(attribute, value) do
    results =
      RegistryETS.list_agents()
      |> Enum.map(fn {key, pid} ->
        case RegistryETS.get_agent_with_metadata(key) do
          {:ok, {^pid, metadata}} -> {key, pid, metadata}
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(fn {_key, _pid, metadata} ->
        Map.get(metadata, attribute) == value
      end)

    {:ok, results}
  end

  defp find_by_attribute_legacy(attribute, value) do
    agents = Process.get(:registered_agents, %{})

    results =
      agents
      |> Enum.filter(fn {_key, {_pid, metadata}} ->
        Map.get(metadata, attribute) == value
      end)
      |> Enum.map(fn {key, {pid, metadata}} -> {key, pid, metadata} end)

    {:ok, results}
  end

  @doc """
  Performs a query using either process dictionary or ETS storage.
  """
  def query(_impl, criteria) when is_list(criteria) do
    if FeatureFlags.enabled?(:use_ets_agent_registry) do
      query_ets(criteria)
    else
      query_legacy(criteria)
    end
  end

  defp query_ets(criteria) do
    results =
      RegistryETS.list_agents()
      |> Enum.map(fn {key, pid} ->
        case RegistryETS.get_agent_with_metadata(key) do
          {:ok, {^pid, metadata}} -> {key, pid, metadata}
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(fn {_key, _pid, metadata} ->
        Enum.all?(criteria, fn {path, value, op} ->
          actual_value = get_nested_value(metadata, path)
          apply_operation(actual_value, value, op)
        end)
      end)

    {:ok, results}
  end

  defp query_legacy(criteria) do
    agents = Process.get(:registered_agents, %{})

    results =
      agents
      |> Enum.filter(fn {_key, {_pid, metadata}} ->
        Enum.all?(criteria, fn {path, value, op} ->
          actual_value = get_nested_value(metadata, path)
          apply_operation(actual_value, value, op)
        end)
      end)
      |> Enum.map(fn {key, {pid, metadata}} -> {key, pid, metadata} end)

    {:ok, results}
  end

  @doc """
  Returns indexed attributes (empty for Any implementation).
  """
  def indexed_attributes(_impl) do
    []
  end

  @doc """
  Lists all registered processes using either process dictionary or ETS storage.
  """
  def list_all(_impl, filter_fn \\ nil) do
    if FeatureFlags.enabled?(:use_ets_agent_registry) do
      list_all_ets(filter_fn)
    else
      list_all_legacy(filter_fn)
    end
  end

  defp list_all_ets(filter_fn) do
    RegistryETS.list_agents()
    |> Enum.map(fn {key, pid} ->
      case RegistryETS.get_agent_with_metadata(key) do
        {:ok, {^pid, metadata}} -> {key, pid, metadata}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> apply_filter(filter_fn)
  end

  defp list_all_legacy(filter_fn) do
    agents = Process.get(:registered_agents, %{})

    results =
      agents
      |> Enum.map(fn {key, {pid, metadata}} -> {key, pid, metadata} end)
      |> apply_filter(filter_fn)

    results
  end

  @doc """
  Updates metadata for a process using either process dictionary or ETS storage.
  """
  def update_metadata(_impl, key, new_metadata) do
    if FeatureFlags.enabled?(:use_ets_agent_registry) do
      update_metadata_ets(key, new_metadata)
    else
      update_metadata_legacy(key, new_metadata)
    end
  end

  defp update_metadata_ets(key, new_metadata) do
    RegistryETS.update_metadata(key, new_metadata)
  end

  defp update_metadata_legacy(key, new_metadata) do
    agents = Process.get(:registered_agents, %{})

    case Map.get(agents, key) do
      {pid, _old_metadata} ->
        new_agents = Map.put(agents, key, {pid, new_metadata})
        Process.put(:registered_agents, new_agents)
        :ok

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Unregisters a process using either process dictionary or ETS storage.
  """
  def unregister(_impl, key) do
    if FeatureFlags.enabled?(:use_ets_agent_registry) do
      unregister_ets(key)
    else
      unregister_legacy(key)
    end
  end

  defp unregister_ets(key) do
    RegistryETS.unregister_agent(key)
  end

  defp unregister_legacy(key) do
    agents = Process.get(:registered_agents, %{})

    case Map.has_key?(agents, key) do
      true ->
        new_agents = Map.delete(agents, key)
        Process.put(:registered_agents, new_agents)
        :ok

      false ->
        {:error, :not_found}
    end
  end

  @doc """
  Returns the count of registered processes using either process dictionary or ETS storage.
  """
  def count(_impl) do
    if FeatureFlags.enabled?(:use_ets_agent_registry) do
      count_ets()
    else
      count_legacy()
    end
  end

  defp count_ets do
    count = length(RegistryETS.list_agents())
    {:ok, count}
  end

  defp count_legacy do
    agents = Process.get(:registered_agents, %{})
    {:ok, map_size(agents)}
  end

  @doc """
  Selects entries using a basic filter (simplified match spec).
  """
  def select(_impl, match_spec) do
    if FeatureFlags.enabled?(:use_ets_agent_registry) do
      select_ets(match_spec)
    else
      select_legacy(match_spec)
    end
  end

  defp select_ets(_match_spec) do
    # For ETS implementation, return all entries (simplified)
    RegistryETS.list_agents()
    |> Enum.map(fn {key, pid} ->
      case RegistryETS.get_agent_with_metadata(key) do
        {:ok, {^pid, metadata}} -> {key, pid, metadata}
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp select_legacy(_match_spec) do
    # For the Any implementation, we'll use a simplified approach
    # since ETS match specs are complex to implement generically
    agents = Process.get(:registered_agents, %{})

    # Convert to list format that ETS would return
    results =
      agents
      |> Enum.map(fn {key, {pid, metadata}} -> {key, pid, metadata} end)

    # Note: This is a simplified implementation that returns all entries
    # A full implementation would need to parse and apply the match_spec
    results
  end

  @doc """
  Returns protocol version.
  """
  def protocol_version(_impl) do
    {:ok, "1.0"}
  end

  # Private helper functions

  defp get_nested_value(metadata, [key]) do
    Map.get(metadata, key)
  end

  defp get_nested_value(metadata, [key | rest]) do
    case Map.get(metadata, key) do
      nil -> nil
      nested_map when is_map(nested_map) -> get_nested_value(nested_map, rest)
      _ -> nil
    end
  end

  defp apply_operation(actual, expected, :eq), do: actual == expected
  defp apply_operation(actual, expected, :neq), do: actual != expected
  defp apply_operation(actual, expected, :gt), do: actual > expected
  defp apply_operation(actual, expected, :lt), do: actual < expected
  defp apply_operation(actual, expected, :gte), do: actual >= expected
  defp apply_operation(actual, expected, :lte), do: actual <= expected

  defp apply_operation(actual, expected_list, :in) when is_list(expected_list),
    do: actual in expected_list

  defp apply_operation(actual, expected_list, :not_in) when is_list(expected_list),
    do: actual not in expected_list

  defp apply_filter(results, nil), do: results

  defp apply_filter(results, filter_fn) do
    Enum.filter(results, fn {_key, _pid, metadata} -> filter_fn.(metadata) end)
  end
end
