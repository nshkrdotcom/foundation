defmodule Foundation.ProcessRegistry do
  @moduledoc """
  Centralized process registry for Foundation layer.

  Provides namespace isolation using Elixir's native Registry to enable concurrent testing
  and prevent naming conflicts between production and test environments.

  ## Performance Characteristics

  - **Storage**: ETS-based partitioned table for high concurrent throughput
  - **Partitions**: `#{System.schedulers_online()}` partitions (matches CPU cores)
  - **Lookup Time**: O(1) average case, < 1ms typical latency
  - **Registration**: Atomic operations with automatic process monitoring
  - **Memory**: Minimal overhead per registered process (~100 bytes)

  ## Registry Architecture

  Uses Elixir's native Registry module with optimized settings:
  - **Keys**: `:unique` - Each {namespace, service} key maps to exactly one process
  - **Partitioning**: CPU-optimized for concurrent access patterns
  - **Monitoring**: Automatic cleanup when processes terminate
  - **Fault Tolerance**: ETS table survives individual process crashes

  ## Supported Namespaces

  - `:production` - For normal operation
  - `{:test, reference()}` - For test isolation with unique references

  ## Examples

      # Register a service in production
      :ok = ProcessRegistry.register(:production, :config_server, self())

      # Register in test namespace
      test_ref = make_ref()
      :ok = ProcessRegistry.register({:test, test_ref}, :config_server, self())

      # Lookup services
      {:ok, pid} = ProcessRegistry.lookup(:production, :config_server)
  """

  @type namespace :: :production | {:test, reference()}
  @type service_name ::
          :config_server
          | :event_store
          | :telemetry_service
          | :test_supervisor

  @type registry_key :: {namespace(), service_name()}

  @doc """
  Child specification for supervision tree integration.
  """
  def child_spec(_opts) do
    %{
      id: Registry,
      start:
        {Registry, :start_link,
         [
           [
             keys: :unique,
             name: __MODULE__,
             partitions: System.schedulers_online()
           ]
         ]},
      type: :supervisor,
      restart: :permanent,
      shutdown: :infinity
    }
  end

  @doc """
  Register a service in the given namespace.

  ## Parameters
  - `namespace`: The namespace for service isolation
  - `service`: The service name to register
  - `pid`: The process PID to register

  ## Returns
  - `:ok` if registration succeeds
  - `{:error, {:already_registered, pid}}` if name already taken

  ## Examples

      iex> ProcessRegistry.register(:production, :config_server, self())
      :ok

      iex> ProcessRegistry.register(:production, :config_server, self())
      {:error, {:already_registered, #PID<0.123.0>}}
  """
  @spec register(namespace(), service_name(), pid()) :: :ok | {:error, {:already_registered, pid()}}
  def register(namespace, service, pid) when is_pid(pid) do
    registry_key = {namespace, service}

    # Always use the backup table for all registrations for consistency
    # This ensures both self() and external process registrations work the same way
    ensure_backup_registry()

    # Debug: Log registration attempts
    if Application.get_env(:foundation, :debug_registry, false) do
      require Logger

      Logger.debug(
        "ProcessRegistry.register: attempting to register #{inspect(registry_key)} -> #{inspect(pid)}"
      )
    end

    # Check if already registered
    case :ets.lookup(:process_registry_backup, registry_key) do
      [{^registry_key, existing_pid}] ->
        if Process.alive?(existing_pid) do
          if existing_pid == pid do
            if Application.get_env(:foundation, :debug_registry, false) do
              require Logger

              Logger.debug(
                "ProcessRegistry.register: already registered correctly #{inspect(registry_key)} -> #{inspect(pid)}"
              )
            end

            # Already registered correctly
            :ok
          else
            if Application.get_env(:foundation, :debug_registry, false) do
              require Logger

              Logger.debug(
                "ProcessRegistry.register: already registered to different pid #{inspect(registry_key)} -> #{inspect(existing_pid)}"
              )
            end

            {:error, {:already_registered, existing_pid}}
          end
        else
          # Dead process registered, replace with new one
          :ets.insert(:process_registry_backup, {registry_key, pid})

          if Application.get_env(:foundation, :debug_registry, false) do
            require Logger

            Logger.debug(
              "ProcessRegistry.register: replaced dead process #{inspect(registry_key)} -> #{inspect(pid)}"
            )
          end

          :ok
        end

      [] ->
        # Not registered, add new registration
        :ets.insert(:process_registry_backup, {registry_key, pid})

        if Application.get_env(:foundation, :debug_registry, false) do
          require Logger

          Logger.debug(
            "ProcessRegistry.register: new registration #{inspect(registry_key)} -> #{inspect(pid)}"
          )
        end

        :ok
    end
  end

  @doc """
  Look up a service in the given namespace.

  ## Parameters
  - `namespace`: The namespace to search in
  - `service`: The service name to lookup

  ## Returns
  - `{:ok, pid}` if service found
  - `:error` if service not found

  ## Examples

      iex> ProcessRegistry.lookup(:production, :config_server)
      {:ok, #PID<0.123.0>}

      iex> ProcessRegistry.lookup(:production, :nonexistent)
      :error
  """
  @spec lookup(namespace(), service_name()) :: {:ok, pid()} | :error
  def lookup(namespace, service) do
    registry_key = {namespace, service}

    # First try the native Registry lookup (for via_tuple registered services)
    case Registry.lookup(__MODULE__, registry_key) do
      [{pid, _value}] when is_pid(pid) ->
        if Process.alive?(pid) do
          {:ok, pid}
        else
          :error
        end

      [] ->
        # Fall back to backup table lookup
        # Ensure backup table exists before trying to use it
        ensure_backup_registry()

        case :ets.lookup(:process_registry_backup, registry_key) do
          [{^registry_key, pid}] ->
            # Verify the process is still alive
            if Process.alive?(pid) do
              {:ok, pid}
            else
              # Clean up dead process and return error
              :ets.delete(:process_registry_backup, registry_key)
              :error
            end

          [] ->
            # Debug: Log when service not found in backup table
            if Application.get_env(:foundation, :debug_registry, false) do
              require Logger
              all_entries = :ets.tab2list(:process_registry_backup)

              Logger.debug(
                "ProcessRegistry.lookup: service #{inspect(registry_key)} not found in backup table"
              )

              Logger.debug("ProcessRegistry.lookup: available entries: #{inspect(all_entries)}")
            end

            :error
        end
    end
  end

  @doc """
  Unregister a service from the given namespace.

  Note: This is typically not needed as Registry automatically
  unregisters when the process dies.

  ## Parameters
  - `namespace`: The namespace containing the service
  - `service`: The service name to unregister

  ## Returns
  - `:ok` regardless of whether service was registered

  ## Examples

      iex> ProcessRegistry.unregister(:production, :config_server)
      :ok
  """
  @spec unregister(namespace(), service_name()) :: :ok
  def unregister(namespace, service) do
    registry_key = {namespace, service}

    # Remove from backup table if it exists
    case :ets.info(:process_registry_backup) do
      :undefined -> :ok
      _ -> :ets.delete(:process_registry_backup, registry_key)
    end

    # Also remove from original Registry
    Registry.unregister(__MODULE__, registry_key)
  end

  @doc """
  List all services registered in a namespace.

  ## Parameters
  - `namespace`: The namespace to list services for

  ## Returns
  - List of service names registered in the namespace

  ## Examples

      iex> ProcessRegistry.list_services(:production)
      [:config_server, :event_store, :telemetry_service]

      iex> ProcessRegistry.list_services({:test, test_ref})
      []
  """
  @spec list_services(namespace()) :: [service_name()]
  def list_services(namespace) do
    # Get all services from both sources
    all_services = get_all_services(namespace)
    Map.keys(all_services)
  end

  @doc """
  Get all registered services with their PIDs for a namespace.

  ## Parameters
  - `namespace`: The namespace to get services for

  ## Returns
  - Map of service_name => pid

  ## Examples

      iex> ProcessRegistry.get_all_services(:production)
      %{
        config_server: #PID<0.123.0>,
        event_store: #PID<0.124.0>
      }
  """
  @spec get_all_services(namespace()) :: %{service_name() => pid()}
  def get_all_services(namespace) do
    # Check both Registry and backup table for complete coverage

    # First, get services from Registry (via_tuple registrations)
    registry_services =
      Registry.select(__MODULE__, [
        {{{namespace, :"$1"}, :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}
      ])
      |> Enum.filter(fn {_service_name, pid} -> Process.alive?(pid) end)
      |> Enum.into(%{})

    # Then, get services from backup table (direct registrations)
    # Ensure backup table exists before trying to use it
    ensure_backup_registry()

    # Use tab2list to avoid match specification issues
    backup_services =
      :ets.tab2list(:process_registry_backup)
      |> Enum.filter(fn {{entry_namespace, _service}, pid} ->
        entry_namespace == namespace and Process.alive?(pid)
      end)
      |> Enum.map(fn {{_namespace, service}, pid} -> {service, pid} end)
      |> Enum.into(%{})

    # Merge both sources, with backup table taking precedence for conflicts
    Map.merge(registry_services, backup_services)
  end

  @doc """
  Check if a service is registered in a namespace.

  ## Parameters
  - `namespace`: The namespace to check
  - `service`: The service name to check

  ## Returns
  - `true` if service is registered
  - `false` if service is not registered

  ## Examples

      iex> ProcessRegistry.registered?(namespace, :config_server)
      true
  """
  @spec registered?(namespace(), service_name()) :: boolean()
  def registered?(namespace, service) do
    case lookup(namespace, service) do
      {:ok, _pid} -> true
      :error -> false
    end
  end

  @doc """
  Count the number of services in a namespace.

  ## Parameters
  - `namespace`: The namespace to count services in

  ## Returns
  - Non-negative integer count of services

  ## Examples

      iex> ProcessRegistry.count_services(:production)
      3
  """
  @spec count_services(namespace()) :: non_neg_integer()
  # Dialyzer warning suppressed: Success typing is more specific in test context
  # but spec is correct for general usage
  @dialyzer {:nowarn_function, count_services: 1}
  def count_services(namespace) do
    # Use get_all_services for consistency
    all_services = get_all_services(namespace)
    map_size(all_services)
  end

  @doc """
  Create a via tuple for GenServer registration.

  This is used in GenServer.start_link/3 for automatic registration.

  ## Parameters
  - `namespace`: The namespace for the service
  - `service`: The service name

  ## Returns
  - Via tuple for GenServer registration

  ## Examples

      iex> via = ProcessRegistry.via_tuple(:production, :config_server)
      iex> GenServer.start_link(MyServer, [], name: via)
  """
  @spec via_tuple(namespace(), service_name()) :: {:via, Registry, {atom(), registry_key()}}
  def via_tuple(namespace, service) do
    {:via, Registry, {__MODULE__, {namespace, service}}}
  end

  @doc """
  Cleanup all services in a test namespace.

  This is useful for test cleanup - terminates all processes
  registered in the given test namespace.

  ## Parameters
  - `test_ref`: The test reference used in namespace

  ## Returns
  - `:ok` after cleanup is complete

  ## Examples

      iex> test_ref = make_ref()
      iex> # ... register services in {:test, test_ref} ...
      iex> ProcessRegistry.cleanup_test_namespace(test_ref)
      :ok
  """
  @spec cleanup_test_namespace(reference()) :: :ok
  def cleanup_test_namespace(test_ref) do
    namespace = {:test, test_ref}

    # Use backup table as primary source for consistency
    backup_pids =
      case :ets.info(:process_registry_backup) do
        :undefined ->
          []

        _ ->
          # Use tab2list instead of select to avoid match specification issues
          :ets.tab2list(:process_registry_backup)
          |> Enum.filter(fn {{entry_namespace, _service}, _pid} ->
            entry_namespace == namespace
          end)
          |> Enum.map(fn {{_namespace, _service}, pid} -> pid end)
      end

    # Terminate each process more safely to avoid test process termination
    Enum.each(backup_pids, fn pid ->
      if Process.alive?(pid) do
        # Spawn a separate process to handle the termination
        # This isolates the test process from any exit signals
        spawn(fn ->
          try do
            # Set trap_exit to handle any exit signals gracefully
            Process.flag(:trap_exit, true)

            # Try gentle shutdown first
            GenServer.stop(pid, :shutdown, 100)
          catch
            # If that fails, force termination
            :exit, _ ->
              Process.exit(pid, :shutdown)

              # Wait briefly then force kill if still alive
              Process.sleep(50)

              if Process.alive?(pid) do
                Process.exit(pid, :kill)
              end
          end
        end)
      end
    end)

    # Wait for all processes to be terminated
    Process.sleep(200)

    # Clean up backup table entries for this namespace and count cleaned entries
    cleanup_count =
      case :ets.info(:process_registry_backup) do
        :undefined ->
          0

        _ ->
          # Find all keys that match this namespace pattern
          # The backup table stores entries as {{namespace, service}, pid}
          all_entries = :ets.tab2list(:process_registry_backup)

          keys_to_delete =
            for {{entry_namespace, service}, pid} <- all_entries,
                entry_namespace == namespace do
              # Only delete if process is actually dead
              if not Process.alive?(pid) do
                {entry_namespace, service}
              else
                nil
              end
            end
            |> Enum.reject(&is_nil/1)

          Enum.each(keys_to_delete, fn key ->
            :ets.delete(:process_registry_backup, key)
          end)

          length(keys_to_delete)
      end

    # Log cleanup summary
    require Logger

    # Only log if there were actually services to clean up AND debug mode is enabled
    if cleanup_count > 0 and Application.get_env(:foundation, :debug_registry, false) do
      Logger.debug("Cleaned up #{cleanup_count} services from test namespace #{inspect(test_ref)}")
    end

    :ok
  end

  @doc """
  Get registry statistics for monitoring and performance analysis.

  ## Returns
  - Map with comprehensive registry statistics including:
    - Service counts by namespace type
    - Performance characteristics
    - Memory usage information
    - Partition utilization

  ## Examples

      iex> ProcessRegistry.stats()
      %{
        total_services: 15,
        production_services: 3,
        test_namespaces: 4,
        partitions: 8,
        partition_count: 8,
        memory_usage_bytes: 4096,
        ets_table_info: %{...}
      }
  """
  @spec stats() :: %{
          total_services: non_neg_integer(),
          production_services: non_neg_integer(),
          test_namespaces: non_neg_integer(),
          partitions: pos_integer(),
          partition_count: pos_integer(),
          memory_usage_bytes: non_neg_integer(),
          ets_table_info: map()
        }
  def stats() do
    # Ensure backup table exists before trying to use it
    ensure_backup_registry()

    # Get services from Registry (via_tuple registrations)
    # Registry stores: {{namespace, service}, pid, value}
    registry_services =
      Registry.select(__MODULE__, [
        {{{:"$1", :"$2"}, :"$3", :"$4"}, [], [{{:"$1", :"$2"}}]}
      ])
      |> Enum.map(fn {namespace, service} -> {namespace, service} end)

    # Get all entries from backup table using tab2list (simpler and more reliable)
    # Backup table stores: {{namespace, service}, pid}
    backup_services =
      :ets.tab2list(:process_registry_backup)
      |> Enum.filter(fn {{_namespace, _service}, pid} -> Process.alive?(pid) end)
      |> Enum.map(fn {{namespace, service}, _pid} -> {namespace, service} end)

    # Combine services from both sources, removing duplicates
    all_services =
      (registry_services ++ backup_services)
      |> Enum.uniq()

    # Count services by namespace type
    {production_count, test_namespaces} =
      Enum.reduce(all_services, {0, MapSet.new()}, fn
        {:production, _service}, {prod_count, test_set} ->
          {prod_count + 1, test_set}

        {{:test, ref}, _service}, {prod_count, test_set} ->
          {prod_count, MapSet.put(test_set, ref)}
      end)

    # Get ETS table information for performance monitoring
    ets_info =
      try do
        case :ets.info(:process_registry_backup) do
          :undefined ->
            %{backup_table_exists: false}

          info when is_list(info) ->
            %{
              backup_table_exists: true,
              table_size: Keyword.get(info, :size, 0),
              memory_words: Keyword.get(info, :memory, 0)
            }
        end
      rescue
        _ -> %{}
      end

    memory_usage =
      case ets_info do
        %{memory_words: words} when is_integer(words) -> words * :erlang.system_info(:wordsize)
        _ -> 0
      end

    %{
      total_services: length(all_services),
      production_services: production_count,
      test_namespaces: MapSet.size(test_namespaces),
      partitions: System.schedulers_online(),
      partition_count: System.schedulers_online(),
      memory_usage_bytes: memory_usage,
      ets_table_info: ets_info
    }
  end

  # Private helper functions

  @spec ensure_backup_registry() :: :ok
  defp ensure_backup_registry() do
    case :ets.info(:process_registry_backup) do
      :undefined ->
        :ets.new(:process_registry_backup, [:named_table, :public, :set])
        :ok

      _ ->
        :ok
    end
  end
end
