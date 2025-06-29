defimpl Foundation.Registry, for: Any do
  @moduledoc """
  Fallback implementation for Foundation.Registry protocol.
  
  This implementation uses the process dictionary for storage,
  making it suitable for testing and simple use cases.
  """

  require Logger

  @doc """
  Registers a process using process dictionary storage.
  """
  def register(_impl, key, pid, metadata \\ %{}) do
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
  Looks up a process by key using process dictionary storage.
  """
  def lookup(_impl, key) do
    agents = Process.get(:registered_agents, %{})
    
    case Map.get(agents, key) do
      {pid, metadata} -> {:ok, {pid, metadata}}
      nil -> :error
    end
  end

  @doc """
  Finds processes by attribute using process dictionary storage.
  """
  def find_by_attribute(_impl, attribute, value) do
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
  Performs a query using process dictionary storage.
  """
  def query(_impl, criteria) when is_list(criteria) do
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
  Lists all registered processes using process dictionary storage.
  """
  def list_all(_impl, filter_fn \\ nil) do
    agents = Process.get(:registered_agents, %{})
    
    results = 
      agents
      |> Enum.map(fn {key, {pid, metadata}} -> {key, pid, metadata} end)
      |> apply_filter(filter_fn)
    
    results
  end

  @doc """
  Updates metadata for a process using process dictionary storage.
  """
  def update_metadata(_impl, key, new_metadata) do
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
  Unregisters a process using process dictionary storage.
  """
  def unregister(_impl, key) do
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
  Returns the count of registered processes using process dictionary storage.
  """
  def count(_impl) do
    agents = Process.get(:registered_agents, %{})
    {:ok, map_size(agents)}
  end

  @doc """
  Selects entries using a basic filter (simplified match spec).
  """
  def select(_impl, _match_spec) do
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
  defp apply_operation(actual, expected_list, :in) when is_list(expected_list), do: actual in expected_list
  defp apply_operation(actual, expected_list, :not_in) when is_list(expected_list), do: actual not in expected_list

  defp apply_filter(results, nil), do: results
  defp apply_filter(results, filter_fn) do
    Enum.filter(results, fn {_key, _pid, metadata} -> filter_fn.(metadata) end)
  end
end