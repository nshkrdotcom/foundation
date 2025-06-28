defmodule Foundation.ProcessRegistry.Backend do
  @moduledoc """
  Behavior for pluggable process registry backends.

  This behavior defines the interface that process registry backends must implement
  to support different storage and distribution strategies. Backends are responsible
  for the actual storage and retrieval of process registrations with their metadata.

  ## Backend Implementations

  - `Foundation.ProcessRegistry.Backend.ETS` - Local ETS-based storage (default)
  - `Foundation.ProcessRegistry.Backend.Registry` - Native Registry-based storage
  - `Foundation.ProcessRegistry.Backend.Horde` - Distributed registry (future)

  ## Configuration

  Backends can be configured in application config:

      config :foundation, Foundation.ProcessRegistry,
        backend: Foundation.ProcessRegistry.Backend.ETS,
        backend_opts: [
          # Backend-specific options
        ]

  ## Backend State

  Each backend maintains its own state, initialized through the `init/1` callback.
  The state is passed to all backend operations and can be used to store
  configuration, connection information, or other backend-specific data.

  ## Error Handling

  All backend operations should return `{:ok, result}` for success or 
  `{:error, reason}` for failures. Common error reasons include:

  - `:not_found` - Key not found in backend
  - `:already_exists` - Key already exists (for unique constraints)
  - `:backend_error` - Internal backend error
  - `:timeout` - Operation timed out
  - `:unavailable` - Backend temporarily unavailable

  ## Thread Safety

  Backend implementations must be thread-safe and handle concurrent access
  appropriately. Multiple processes may call backend functions simultaneously.
  """

  @type key :: term()
  @type pid_or_name :: pid() | atom()
  @type metadata :: map()
  @type backend_state :: term()
  @type init_opts :: keyword()

  @type backend_error ::
          :not_found
          | :already_exists
          | :backend_error
          | :timeout
          | :unavailable
          | {:invalid_key, term()}
          | {:invalid_metadata, term()}

  @doc """
  Initialize the backend with the given options.

  This callback is called once when the backend is started and should
  return the initial state that will be passed to all other callbacks.

  ## Parameters
  - `opts` - Keyword list of initialization options

  ## Returns
  - `{:ok, state}` - Backend initialized successfully
  - `{:error, reason}` - Initialization failed

  ## Examples

      # ETS backend initialization
      {:ok, %{table: :process_registry_ets, opts: opts}}

      # Distributed backend initialization  
      {:ok, %{node_id: :primary, cluster: [:node1, :node2]}}
  """
  @callback init(opts :: init_opts()) :: {:ok, backend_state()} | {:error, term()}

  @doc """
  Register a process with metadata in the backend.

  ## Parameters
  - `state` - Current backend state
  - `key` - Unique key for the registration
  - `pid` - Process ID to register
  - `metadata` - Associated metadata map

  ## Returns
  - `{:ok, new_state}` - Registration successful
  - `{:error, reason}` - Registration failed

  ## Behavior Notes
  - Should fail if key already exists with different PID
  - Should allow re-registration with same PID (idempotent)
  - Should validate that PID is alive
  - Should store metadata exactly as provided
  """
  @callback register(backend_state(), key(), pid_or_name(), metadata()) ::
              {:ok, backend_state()} | {:error, backend_error()}

  @doc """
  Look up a registration by key.

  ## Parameters
  - `state` - Current backend state
  - `key` - Key to look up

  ## Returns
  - `{:ok, {pid, metadata}}` - Registration found
  - `{:error, :not_found}` - Key not found
  - `{:error, reason}` - Lookup failed

  ## Behavior Notes
  - Should return error if process is dead (and clean up if needed)
  - Should return exact metadata as stored
  - Should be fast (< 1ms for local backends)
  """
  @callback lookup(backend_state(), key()) ::
              {:ok, {pid_or_name(), metadata()}} | {:error, backend_error()}

  @doc """
  Unregister a key from the backend.

  ## Parameters
  - `state` - Current backend state
  - `key` - Key to unregister

  ## Returns
  - `{:ok, new_state}` - Unregistration successful (even if key didn't exist)
  - `{:error, reason}` - Unregistration failed

  ## Behavior Notes
  - Should be idempotent (success even if key doesn't exist)
  - Should clean up any associated resources
  - Should be fast and reliable
  """
  @callback unregister(backend_state(), key()) :: {:ok, backend_state()} | {:error, backend_error()}

  @doc """
  List all registrations in the backend.

  ## Parameters
  - `state` - Current backend state

  ## Returns
  - `{:ok, registrations}` - List of all registrations
  - `{:error, reason}` - Listing failed

  Where registrations is a list of `{key, pid, metadata}` tuples.

  ## Behavior Notes
  - Should only return registrations for alive processes
  - Should clean up dead processes during listing
  - May be expensive for large datasets
  - Should be consistent (no duplicates)
  """
  @callback list_all(backend_state()) ::
              {:ok, [{key(), pid_or_name(), metadata()}]} | {:error, backend_error()}

  @doc """
  Update metadata for an existing registration.

  ## Parameters
  - `state` - Current backend state
  - `key` - Key to update metadata for
  - `metadata` - New metadata (replaces existing completely)

  ## Returns
  - `{:ok, new_state}` - Update successful
  - `{:error, :not_found}` - Key not found
  - `{:error, reason}` - Update failed

  ## Behavior Notes
  - Should fail if key doesn't exist
  - Should replace metadata completely (not merge)
  - Should verify process is still alive
  - Should be atomic
  """
  @callback update_metadata(backend_state(), key(), metadata()) ::
              {:ok, backend_state()} | {:error, backend_error()}

  @doc """
  Get health information about the backend.

  ## Parameters
  - `state` - Current backend state

  ## Returns
  - `{:ok, health_info}` - Backend health information
  - `{:error, reason}` - Health check failed

  Health info should be a map containing:
  - `:status` - `:healthy` | `:degraded` | `:unhealthy`
  - `:registrations_count` - Number of active registrations
  - `:last_cleanup` - Timestamp of last cleanup operation
  - Backend-specific metrics

  ## Behavior Notes
  - Should be fast (< 100ms)
  - Should not affect normal operations
  - Used for monitoring and diagnostics
  """
  @callback health_check(backend_state()) :: {:ok, map()} | {:error, backend_error()}

  @optional_callbacks [health_check: 1]

  @doc """
  Helper function to validate that a module implements the Backend behavior.
  """
  @spec validate_backend_module(module()) :: :ok | {:error, {:missing_callbacks, [atom()]}}
  def validate_backend_module(module) do
    # Ensure the module is loaded before checking exports
    case Code.ensure_loaded(module) do
      {:module, ^module} ->
        required_callbacks = [
          {:init, 1},
          {:register, 4},
          {:lookup, 2},
          {:unregister, 2},
          {:list_all, 1},
          {:update_metadata, 3}
        ]

        missing_callbacks =
          required_callbacks
          |> Enum.reject(fn {fun, arity} ->
            function_exported?(module, fun, arity)
          end)

        case missing_callbacks do
          [] -> :ok
          missing -> {:error, {:missing_callbacks, missing}}
        end

      {:error, reason} ->
        {:error, {:module_load_failed, reason}}
    end
  end

  @doc """
  Get default backend configuration.
  """
  @spec default_config() :: keyword()
  def default_config do
    [
      backend: Foundation.ProcessRegistry.Backend.ETS,
      backend_opts: []
    ]
  end
end
