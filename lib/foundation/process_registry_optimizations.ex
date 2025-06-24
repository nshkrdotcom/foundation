defmodule Foundation.ProcessRegistry.Optimizations do
  @moduledoc """
  Performance optimizations for Foundation.ProcessRegistry for large agent systems.

  Provides enhanced functionality including:
  - Metadata indexing for faster searches
  - Lookup caching for frequently accessed services  
  - Bulk operations for improved throughput
  - Memory-efficient storage strategies
  """

  alias Foundation.ProcessRegistry

  @doc """
  Initialize optimization features for ProcessRegistry.

  This sets up additional ETS tables for indexing and caching.
  """
  @spec initialize_optimizations() :: :ok
  def initialize_optimizations() do
    # Create metadata index table
    case :ets.info(:process_registry_metadata_index) do
      :undefined ->
        :ets.new(:process_registry_metadata_index, [
          :bag,
          :public,
          :named_table,
          {:read_concurrency, true},
          {:write_concurrency, true}
        ])

      _ ->
        :ok
    end

    # Create lookup cache table
    case :ets.info(:process_registry_cache) do
      :undefined ->
        :ets.new(:process_registry_cache, [
          :set,
          :public,
          :named_table,
          {:read_concurrency, true},
          {:write_concurrency, false}
        ])

      _ ->
        :ok
    end

    :ok
  end

  @doc """
  Register a service with metadata indexing support.

  This wraps ProcessRegistry.register/4 and adds metadata indexing for
  faster searches.
  """
  @spec register_with_indexing(
          ProcessRegistry.namespace(),
          ProcessRegistry.service_name(),
          pid(),
          map()
        ) :: :ok | {:error, :invalid_metadata | {:already_registered, pid()}}
  def register_with_indexing(namespace, service, pid, metadata \\ %{}) do
    # Use direct ETS operations to avoid circular dependency with ProcessRegistry
    registry_key = {namespace, service}
    
    # Ensure backup registry exists
    ensure_backup_registry()
    
    # Check if already registered
    case :ets.lookup(:process_registry_backup, registry_key) do
      [{^registry_key, existing_pid, _existing_metadata}] ->
        if Process.alive?(existing_pid) do
          if existing_pid == pid do
            # Already registered correctly, just update indexing
            add_to_metadata_index(namespace, service, pid, metadata)
            invalidate_cache_entry(namespace, service)
            :ok
          else
            {:error, {:already_registered, existing_pid}}
          end
        else
          # Dead process, replace it
          :ets.insert(:process_registry_backup, {registry_key, pid, metadata})
          add_to_metadata_index(namespace, service, pid, metadata)
          invalidate_cache_entry(namespace, service)
          :ok
        end

      [] ->
        # Not registered, add new registration
        :ets.insert(:process_registry_backup, {registry_key, pid, metadata})
        add_to_metadata_index(namespace, service, pid, metadata)
        invalidate_cache_entry(namespace, service)
        :ok
    end
  end

  @doc """
  Optimized lookup with caching.

  For frequently accessed services, this provides cached lookups
  with automatic cache invalidation when processes die.
  """
  @spec cached_lookup(ProcessRegistry.namespace(), ProcessRegistry.service_name()) ::
          {:ok, pid()} | :error
  def cached_lookup(namespace, service) do
    cache_key = {namespace, service}

    case :ets.lookup(:process_registry_cache, cache_key) do
      [{^cache_key, pid, _timestamp}] ->
        # Verify process is still alive
        if Process.alive?(pid) do
          {:ok, pid}
        else
          # Process died, invalidate cache and do fresh lookup
          invalidate_cache_entry(namespace, service)
          fresh_lookup_and_cache(namespace, service)
        end

      [] ->
        # Not in cache, do fresh lookup
        fresh_lookup_and_cache(namespace, service)
    end
  end

  @doc """
  Highly optimized metadata search using indexing.

  For searches on indexed fields, this provides much faster results
  than scanning the entire backup table.
  """
  @spec find_by_indexed_metadata(
          ProcessRegistry.namespace(),
          atom(),
          term()
        ) :: [{ProcessRegistry.service_name(), pid(), map()}]
  def find_by_indexed_metadata(namespace, field, value) do
    initialize_optimizations()
    index_key = {namespace, field, value}

    case :ets.lookup(:process_registry_metadata_index, index_key) do
      [] ->
        []

      results ->
        # Filter out dead processes and return valid results
        results
        |> Enum.filter(fn {_key, _service, pid, _metadata} -> Process.alive?(pid) end)
        |> Enum.map(fn {_key, service, pid, metadata} -> {service, pid, metadata} end)
    end
  end

  @doc """
  Bulk register multiple services efficiently.

  This optimizes the registration of many services by batching
  operations and reducing overhead.
  """
  @spec bulk_register([
          {ProcessRegistry.namespace(), ProcessRegistry.service_name(), pid(), map()}
        ]) :: [{:ok | {:error, term()}, ProcessRegistry.service_name()}]
  def bulk_register(registrations) do
    initialize_optimizations()

    # Process registrations in batches for better performance
    Enum.map(registrations, fn {namespace, service, pid, metadata} ->
      result = register_with_indexing(namespace, service, pid, metadata)
      {result, service}
    end)
  end

  @doc """
  Get performance statistics for the registry optimizations.
  """
  @spec get_optimization_stats() :: %{
          metadata_index_size: non_neg_integer(),
          cache_size: non_neg_integer(),
          cache_hit_rate: float() | nil
        }
  def get_optimization_stats() do
    initialize_optimizations()

    %{
      metadata_index_size: get_table_size(:process_registry_metadata_index),
      cache_size: get_table_size(:process_registry_cache),
      # Would need to track hits/misses in production
      cache_hit_rate: nil
    }
  end

  @doc """
  Clean up optimization tables and resources.
  """
  @spec cleanup_optimizations() :: :ok
  def cleanup_optimizations() do
    try do
      :ets.delete(:process_registry_metadata_index)
    rescue
      _ -> :ok
    end

    try do
      :ets.delete(:process_registry_cache)
    rescue
      _ -> :ok
    end

    :ok
  end

  ## Private Functions

  defp add_to_metadata_index(namespace, service, pid, metadata) do
    initialize_optimizations()

    # Index common metadata fields for fast lookup
    indexable_fields = [:type, :agent_type, :priority, :capabilities, :category, :tier, :region]

    for field <- indexable_fields do
      case Map.get(metadata, field) do
        nil ->
          :ok

        list when is_list(list) ->
          # For list fields like capabilities, index each item
          for item <- list do
            index_key = {namespace, field, item}
            :ets.insert(:process_registry_metadata_index, {index_key, service, pid, metadata})
          end

        value ->
          # For scalar fields, index the value directly
          index_key = {namespace, field, value}
          :ets.insert(:process_registry_metadata_index, {index_key, service, pid, metadata})
      end
    end

    :ok
  end

  defp fresh_lookup_and_cache(namespace, service) do
    # Use direct ETS lookup to avoid circular dependency
    registry_key = {namespace, service}
    ensure_backup_registry()
    
    case :ets.lookup(:process_registry_backup, registry_key) do
      [{^registry_key, pid, _metadata}] ->
        if Process.alive?(pid) do
          # Add to cache with timestamp
          cache_key = {namespace, service}
          timestamp = System.monotonic_time(:millisecond)
          :ets.insert(:process_registry_cache, {cache_key, pid, timestamp})
          {:ok, pid}
        else
          # Clean up dead process and return error
          :ets.delete(:process_registry_backup, registry_key)
          :error
        end

      # Handle legacy 2-tuple format for backward compatibility
      [{^registry_key, pid}] ->
        if Process.alive?(pid) do
          cache_key = {namespace, service}
          timestamp = System.monotonic_time(:millisecond)
          :ets.insert(:process_registry_cache, {cache_key, pid, timestamp})
          {:ok, pid}
        else
          :ets.delete(:process_registry_backup, registry_key)
          :error
        end

      [] ->
        :error
    end
  end

  defp ensure_backup_registry do
    case :ets.info(:process_registry_backup) do
      :undefined ->
        :ets.new(:process_registry_backup, [:named_table, :public, :set])
        :ok
      _ ->
        :ok
    end
  end


  defp invalidate_cache_entry(namespace, service) do
    cache_key = {namespace, service}
    :ets.delete(:process_registry_cache, cache_key)
    :ok
  end

  defp get_table_size(table_name) do
    case :ets.info(table_name, :size) do
      :undefined -> 0
      size -> size
    end
  end
end
