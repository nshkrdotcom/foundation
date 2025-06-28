defmodule Foundation.ProcessRegistry.Backend.ETS do
  @moduledoc """
  ETS-based backend for Foundation.ProcessRegistry.

  This backend provides local, in-memory storage using Erlang Term Storage (ETS).
  It's the default backend for single-node deployments and offers excellent
  performance characteristics.

  ## Features

  - **High Performance**: O(1) lookup time, < 1ms typical latency
  - **Concurrent Access**: Thread-safe operations with automatic locking
  - **Memory Efficient**: Minimal overhead per registration (~100 bytes)
  - **Automatic Cleanup**: Dead process detection and cleanup
  - **Crash Resilient**: Table survives individual process crashes

  ## Configuration

      config :foundation, Foundation.ProcessRegistry,
        backend: Foundation.ProcessRegistry.Backend.ETS,
        backend_opts: [
          table_name: :process_registry_ets,
          table_opts: [:named_table, :public, :set],
          cleanup_interval: 30_000  # 30 seconds
        ]

  ## Storage Format

  ETS table stores tuples in the format:
  `{key, pid, metadata, inserted_at}`

  Where:
  - `key` - Registration key (typically `{namespace, service}`)
  - `pid` - Process PID
  - `metadata` - Metadata map
  - `inserted_at` - Timestamp for cleanup purposes

  ## Performance Characteristics

  - **Lookup**: O(1), < 1ms
  - **Register**: O(1), < 1ms  
  - **Unregister**: O(1), < 1ms
  - **List All**: O(n), where n is number of registrations
  - **Memory**: ~100 bytes per registration + metadata size
  """

  @behaviour Foundation.ProcessRegistry.Backend

  alias Foundation.ProcessRegistry.Backend

  @type backend_state :: %{
          table: atom(),
          table_opts: [term()],
          cleanup_interval: non_neg_integer(),
          last_cleanup: DateTime.t() | nil
        }

  @default_table_name :foundation_process_registry_ets
  @default_table_opts [:named_table, :public, :set]
  # 30 seconds
  @default_cleanup_interval 30_000

  @impl Backend
  def init(opts) do
    table_name = Keyword.get(opts, :table_name, @default_table_name)
    table_opts = Keyword.get(opts, :table_opts, @default_table_opts)
    cleanup_interval = Keyword.get(opts, :cleanup_interval, @default_cleanup_interval)

    # Create ETS table if it doesn't exist
    case :ets.info(table_name) do
      :undefined ->
        try do
          :ets.new(table_name, table_opts)

          {:ok,
           %{
             table: table_name,
             table_opts: table_opts,
             cleanup_interval: cleanup_interval,
             last_cleanup: DateTime.utc_now()
           }}
        rescue
          error ->
            {:error, {:table_creation_failed, error}}
        end

      _info ->
        # Table already exists, use it
        {:ok,
         %{
           table: table_name,
           table_opts: table_opts,
           cleanup_interval: cleanup_interval,
           last_cleanup: DateTime.utc_now()
         }}
    end
  end

  @impl Backend
  def register(state, key, pid, metadata) when is_pid(pid) and is_map(metadata) do
    table = state.table
    timestamp = DateTime.utc_now()

    # Check if already registered
    case :ets.lookup(table, key) do
      [{^key, existing_pid, _metadata, _timestamp}] ->
        if Process.alive?(existing_pid) do
          if existing_pid == pid do
            # Update registration with new metadata and timestamp
            :ets.insert(table, {key, pid, metadata, timestamp})
            {:ok, state}
          else
            {:error, {:already_registered, existing_pid}}
          end
        else
          # Dead process, replace with new one
          :ets.insert(table, {key, pid, metadata, timestamp})
          {:ok, state}
        end

      [] ->
        # New registration
        :ets.insert(table, {key, pid, metadata, timestamp})
        {:ok, state}
    end
  end

  def register(_state, _key, pid, _metadata) when not is_pid(pid) do
    {:error, {:invalid_key, "PID must be a valid process identifier"}}
  end

  def register(_state, _key, _pid, metadata) when not is_map(metadata) do
    {:error, {:invalid_metadata, "Metadata must be a map"}}
  end

  @impl Backend
  def lookup(state, key) do
    table = state.table

    case :ets.lookup(table, key) do
      [{^key, pid, metadata, _timestamp}] ->
        if Process.alive?(pid) do
          {:ok, {pid, metadata}}
        else
          # Clean up dead process and return not found
          :ets.delete(table, key)
          {:error, :not_found}
        end

      [] ->
        {:error, :not_found}
    end
  end

  @impl Backend
  def unregister(state, key) do
    table = state.table
    :ets.delete(table, key)
    {:ok, state}
  end

  @impl Backend
  def list_all(state) do
    table = state.table

    try do
      registrations =
        :ets.tab2list(table)
        |> Enum.filter(fn {_key, pid, _metadata, _timestamp} ->
          Process.alive?(pid)
        end)
        |> Enum.map(fn {key, pid, metadata, _timestamp} ->
          {key, pid, metadata}
        end)

      # Clean up dead processes found during listing
      dead_keys =
        :ets.tab2list(table)
        |> Enum.reject(fn {_key, pid, _metadata, _timestamp} ->
          Process.alive?(pid)
        end)
        |> Enum.map(fn {key, _pid, _metadata, _timestamp} -> key end)

      Enum.each(dead_keys, fn key ->
        :ets.delete(table, key)
      end)

      {:ok, registrations}
    rescue
      error ->
        {:error, {:backend_error, error}}
    end
  end

  @impl Backend
  def update_metadata(state, key, metadata) when is_map(metadata) do
    table = state.table

    case :ets.lookup(table, key) do
      [{^key, pid, _old_metadata, _timestamp}] ->
        if Process.alive?(pid) do
          timestamp = DateTime.utc_now()
          :ets.insert(table, {key, pid, metadata, timestamp})
          {:ok, state}
        else
          # Clean up dead process and return not found
          :ets.delete(table, key)
          {:error, :not_found}
        end

      [] ->
        {:error, :not_found}
    end
  end

  def update_metadata(_state, _key, metadata) when not is_map(metadata) do
    {:error, {:invalid_metadata, "Metadata must be a map"}}
  end

  @impl Backend
  def health_check(state) do
    table = state.table

    try do
      # Get table info
      table_info = :ets.info(table)

      if table_info == :undefined do
        {:error, :table_not_found}
      else
        registrations_count = Keyword.get(table_info, :size, 0)
        memory_words = Keyword.get(table_info, :memory, 0)
        memory_bytes = memory_words * :erlang.system_info(:wordsize)

        # Count alive vs dead processes
        all_entries = :ets.tab2list(table)

        alive_count =
          Enum.count(all_entries, fn {_key, pid, _metadata, _timestamp} ->
            Process.alive?(pid)
          end)

        dead_count = registrations_count - alive_count

        health_status =
          cond do
            dead_count == 0 -> :healthy
            # < 10% dead
            dead_count / registrations_count < 0.1 -> :healthy
            # < 30% dead
            dead_count / registrations_count < 0.3 -> :degraded
            true -> :unhealthy
          end

        health_info = %{
          status: health_status,
          registrations_count: registrations_count,
          alive_processes: alive_count,
          dead_processes: dead_count,
          memory_usage_bytes: memory_bytes,
          last_cleanup: state.last_cleanup,
          table_name: table,
          backend_type: :ets
        }

        {:ok, health_info}
      end
    rescue
      error ->
        {:error, {:health_check_failed, error}}
    end
  end

  @doc """
  Perform cleanup of dead processes from the ETS table.

  This function is called periodically to remove registrations for
  processes that have died. It can also be called manually for
  immediate cleanup.

  ## Parameters
  - `state` - Current backend state

  ## Returns
  - `{:ok, {cleaned_count, new_state}}` - Cleanup successful
  - `{:error, reason}` - Cleanup failed
  """
  @spec cleanup_dead_processes(backend_state()) ::
          {:ok, {non_neg_integer(), backend_state()}} | {:error, term()}
  def cleanup_dead_processes(state) do
    table = state.table

    try do
      # Find all dead processes
      dead_keys =
        :ets.tab2list(table)
        |> Enum.reject(fn {_key, pid, _metadata, _timestamp} ->
          Process.alive?(pid)
        end)
        |> Enum.map(fn {key, _pid, _metadata, _timestamp} -> key end)

      # Remove dead process registrations
      cleaned_count = length(dead_keys)

      Enum.each(dead_keys, fn key ->
        :ets.delete(table, key)
      end)

      new_state = %{state | last_cleanup: DateTime.utc_now()}
      {:ok, {cleaned_count, new_state}}
    rescue
      error ->
        {:error, {:cleanup_failed, error}}
    end
  end

  @doc """
  Get detailed statistics about the ETS backend.

  ## Parameters  
  - `state` - Current backend state

  ## Returns
  - Map with detailed statistics including:
    - Table information
    - Process statistics
    - Memory usage
    - Performance metrics
  """
  @spec get_statistics(backend_state()) :: map()
  def get_statistics(state) do
    table = state.table

    try do
      table_info =
        case :ets.info(table) do
          :undefined -> []
          info when is_list(info) -> info
        end

      all_entries = :ets.tab2list(table)

      alive_processes =
        Enum.count(all_entries, fn {_key, pid, _metadata, _timestamp} ->
          Process.alive?(pid)
        end)

      dead_processes = length(all_entries) - alive_processes

      # Calculate average metadata size
      avg_metadata_size =
        if length(all_entries) > 0 do
          total_metadata_size =
            all_entries
            |> Enum.map(fn {_key, _pid, metadata, _timestamp} ->
              :erlang.external_size(metadata)
            end)
            |> Enum.sum()

          div(total_metadata_size, length(all_entries))
        else
          0
        end

      %{
        table_name: table,
        total_registrations: Keyword.get(table_info, :size, 0),
        alive_processes: alive_processes,
        dead_processes: dead_processes,
        memory_usage_bytes: Keyword.get(table_info, :memory, 0) * :erlang.system_info(:wordsize),
        average_metadata_size_bytes: avg_metadata_size,
        table_type: Keyword.get(table_info, :type, :unknown),
        last_cleanup: state.last_cleanup,
        cleanup_interval_ms: state.cleanup_interval,
        backend_version: "1.0.0"
      }
    rescue
      error ->
        %{
          error: "Failed to get statistics",
          reason: error,
          table_name: table
        }
    end
  end
end
