defmodule Foundation.ProcessRegistry.Backend.Registry do
  @moduledoc """
  Native Registry-based backend for Foundation.ProcessRegistry.

  This backend uses Elixir's native Registry module for storage, providing
  excellent performance and built-in process monitoring. It's suitable for
  applications that want to leverage Registry's optimized partitioning and
  built-in process lifecycle management.

  ## Features

  - **Native Integration**: Uses Elixir's built-in Registry module
  - **Automatic Partitioning**: CPU-optimized concurrent access
  - **Process Monitoring**: Automatic cleanup when processes die
  - **High Performance**: Optimized for concurrent read/write operations
  - **Fault Tolerant**: Survives individual process crashes

  ## Configuration

      config :foundation, Foundation.ProcessRegistry,
        backend: Foundation.ProcessRegistry.Backend.Registry,
        backend_opts: [
          registry_name: Foundation.ProcessRegistry.BackendRegistry,
          partitions: System.schedulers_online(),
          keys: :unique
        ]

  ## Storage Format

  Registry stores entries as:
  - Key: Registration key (typically `{namespace, service}`)
  - PID: Process PID
  - Value: Metadata map

  ## Performance Characteristics

  - **Lookup**: O(1), < 1ms
  - **Register**: O(1), < 1ms
  - **Unregister**: Automatic on process death
  - **List All**: O(n), where n is number of registrations
  - **Memory**: Minimal overhead per registration

  ## Limitations

  - No explicit metadata update (requires unregister/register)
  - Process must be alive for registration
  - Cannot register external processes easily
  """

  @behaviour Foundation.ProcessRegistry.Backend

  alias Foundation.ProcessRegistry.Backend

  @type backend_state :: %{
          registry_name: atom(),
          partitions: pos_integer(),
          keys: :unique | :duplicate
        }

  @default_registry_name Foundation.ProcessRegistry.BackendRegistry
  @default_partitions System.schedulers_online()
  @default_keys :unique

  @impl Backend
  def init(opts) do
    registry_name = Keyword.get(opts, :registry_name, @default_registry_name)
    partitions = Keyword.get(opts, :partitions, @default_partitions)
    keys = Keyword.get(opts, :keys, @default_keys)

    # Start the Registry if it doesn't exist
    case Registry.start_link(
           keys: keys,
           name: registry_name,
           partitions: partitions
         ) do
      {:ok, _pid} ->
        {:ok,
         %{
           registry_name: registry_name,
           partitions: partitions,
           keys: keys
         }}

      {:error, {:already_started, _pid}} ->
        # Registry already exists, use it
        {:ok,
         %{
           registry_name: registry_name,
           partitions: partitions,
           keys: keys
         }}

      {:error, reason} ->
        {:error, {:registry_start_failed, reason}}
    end
  end

  @impl Backend
  def register(state, key, pid, metadata) when is_pid(pid) and is_map(metadata) do
    registry_name = state.registry_name

    # Check if process is alive
    if Process.alive?(pid) do
      # Registry can only register the calling process (self())
      if pid == self() do
        case Registry.register(registry_name, key, metadata) do
          {:ok, _owner} ->
            {:ok, state}

          {:error, {:already_registered, existing_pid}} ->
            # Check if it's the same PID trying to re-register
            if existing_pid == pid do
              # Same PID, update metadata by unregistering and re-registering
              Registry.unregister(registry_name, key)

              case Registry.register(registry_name, key, metadata) do
                {:ok, _owner} -> {:ok, state}
                {:error, {:already_registered, _}} -> {:error, {:already_registered, existing_pid}}
              end
            else
              {:error, {:already_registered, existing_pid}}
            end
        end
      else
        # Registry backend cannot register external processes
        # This is a limitation of the Registry module itself
        {:error,
         {:cannot_register_external_process,
          "Registry backend can only register calling process (self())"}}
      end
    else
      {:error, {:dead_process, pid}}
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
    registry_name = state.registry_name

    case Registry.lookup(registry_name, key) do
      [{pid, metadata}] ->
        if Process.alive?(pid) do
          {:ok, {pid, metadata}}
        else
          # Process is dead, Registry should clean it up automatically
          {:error, :not_found}
        end

      [] ->
        {:error, :not_found}

      # Handle multiple entries (shouldn't happen with :unique keys)
      multiple when length(multiple) > 1 ->
        # Take the first alive process
        case Enum.find(multiple, fn {pid, _metadata} -> Process.alive?(pid) end) do
          {pid, metadata} -> {:ok, {pid, metadata}}
          nil -> {:error, :not_found}
        end
    end
  end

  @impl Backend
  def unregister(state, key) do
    registry_name = state.registry_name

    # Registry.unregister/2 is idempotent
    Registry.unregister(registry_name, key)
    {:ok, state}
  end

  @impl Backend
  def list_all(state) do
    registry_name = state.registry_name

    try do
      # Use Registry.select to get all entries
      registrations =
        Registry.select(registry_name, [
          {{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}
        ])
        |> Enum.filter(fn {_key, pid, _metadata} ->
          Process.alive?(pid)
        end)

      {:ok, registrations}
    rescue
      error ->
        {:error, {:backend_error, error}}
    end
  end

  @impl Backend
  def update_metadata(state, key, metadata) when is_map(metadata) do
    registry_name = state.registry_name

    # Registry doesn't support direct metadata updates
    # We need to unregister and re-register
    case Registry.lookup(registry_name, key) do
      [{pid, _old_metadata}] ->
        if Process.alive?(pid) do
          # Unregister and re-register with new metadata
          Registry.unregister(registry_name, key)

          case Registry.register(registry_name, key, metadata) do
            {:ok, _owner} ->
              {:ok, state}

            {:error, reason} ->
              {:error, reason}
          end
        else
          {:error, :not_found}
        end

      [] ->
        {:error, :not_found}

      # Handle multiple entries (shouldn't happen with :unique keys)
      multiple when length(multiple) > 1 ->
        # Find the first alive process and update it
        case Enum.find(multiple, fn {pid, _metadata} -> Process.alive?(pid) end) do
          {_pid, _old_metadata} ->
            Registry.unregister(registry_name, key)

            case Registry.register(registry_name, key, metadata) do
              {:ok, _owner} -> {:ok, state}
              {:error, reason} -> {:error, reason}
            end

          nil ->
            {:error, :not_found}
        end
    end
  end

  def update_metadata(_state, _key, metadata) when not is_map(metadata) do
    {:error, {:invalid_metadata, "Metadata must be a map"}}
  end

  @impl Backend
  def health_check(state) do
    registry_name = state.registry_name

    try do
      # Check if Registry is alive and responsive
      keys = Registry.select(registry_name, [{{:"$1", :"$2", :"$3"}, [], [:"$1"]}])
      registrations_count = length(keys)

      # Count unique keys (should be same as total for :unique registry)
      unique_keys = Enum.uniq(keys)
      unique_count = length(unique_keys)

      health_status =
        if unique_count == registrations_count do
          :healthy
        else
          # Duplicate keys found (shouldn't happen)
          :degraded
        end

      health_info = %{
        status: health_status,
        registrations_count: registrations_count,
        unique_registrations: unique_count,
        duplicate_keys: registrations_count - unique_count,
        registry_name: registry_name,
        partitions: state.partitions,
        keys_type: state.keys,
        backend_type: :registry
      }

      {:ok, health_info}
    rescue
      error ->
        {:error, {:health_check_failed, error}}
    end
  end

  @doc """
  Get detailed Registry information and statistics.

  ## Parameters
  - `state` - Current backend state

  ## Returns
  - Map with Registry-specific statistics and information
  """
  @spec get_registry_info(backend_state()) :: map()
  def get_registry_info(state) do
    registry_name = state.registry_name

    try do
      # Get all entries to analyze
      all_entries =
        Registry.select(registry_name, [
          {{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2", :"$3"}}]}
        ])

      alive_count =
        Enum.count(all_entries, fn {_key, pid, _metadata} ->
          Process.alive?(pid)
        end)

      dead_count = length(all_entries) - alive_count

      # Calculate average metadata size
      avg_metadata_size =
        if length(all_entries) > 0 do
          total_metadata_size =
            all_entries
            |> Enum.map(fn {_key, _pid, metadata} ->
              :erlang.external_size(metadata)
            end)
            |> Enum.sum()

          div(total_metadata_size, length(all_entries))
        else
          0
        end

      %{
        registry_name: registry_name,
        total_registrations: length(all_entries),
        alive_processes: alive_count,
        dead_processes: dead_count,
        partitions: state.partitions,
        keys_type: state.keys,
        average_metadata_size_bytes: avg_metadata_size,
        backend_version: "1.0.0"
      }
    rescue
      error ->
        %{
          error: "Failed to get Registry info",
          reason: error,
          registry_name: registry_name
        }
    end
  end

  @doc """
  Get partition distribution statistics.

  Shows how registrations are distributed across Registry partitions,
  which can be useful for performance analysis.

  ## Parameters
  - `state` - Current backend state

  ## Returns
  - Map with partition distribution information
  """
  @spec get_partition_stats(backend_state()) :: map()
  def get_partition_stats(state) do
    registry_name = state.registry_name

    try do
      # This is a simplified version - actual partition inspection
      # would require more advanced Registry internals access
      total_registrations = Registry.count(registry_name)
      expected_per_partition = div(total_registrations, state.partitions)

      %{
        total_partitions: state.partitions,
        total_registrations: total_registrations,
        expected_per_partition: expected_per_partition,
        # Note: Actual per-partition counts would require Registry internals
        actual_distribution: "Not available without Registry internals access"
      }
    rescue
      error ->
        %{
          error: "Failed to get partition stats",
          reason: error,
          registry_name: registry_name
        }
    end
  end
end
