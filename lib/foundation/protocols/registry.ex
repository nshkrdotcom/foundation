defprotocol Foundation.Registry do
  @moduledoc """
  Universal protocol for process/service registration and discovery.

  ## Protocol Version
  Current version: 1.1

  ## Version History
  - 1.0: Initial protocol definition
  - 1.1: Added indexed_attributes/1 and query/2 functions

  ## Common Error Returns
  - `{:error, :not_found}`
  - `{:error, :already_exists}`
  - `{:error, :invalid_metadata}`
  - `{:error, :backend_unavailable}`
  - `{:error, :unsupported_attribute}`
  - `{:error, :invalid_criteria}`
  """

  @fallback_to_any true

  @doc """
  Registers a process with its metadata.

  ## Parameters
  - `impl`: The registry implementation (process PID or module)
  - `key`: Unique identifier for the process
  - `pid`: The process PID to register
  - `metadata`: Map containing process metadata

  ## Returns
  - `:ok` on successful registration
  - `{:error, :already_exists}` if key already registered
  - `{:error, :invalid_metadata}` if metadata is invalid
  """
  @spec register(t(), key :: term(), pid(), metadata :: map()) ::
          :ok | {:error, term()}
  def register(impl, key, pid, metadata \\ %{})

  @doc """
  Looks up a process by its key.

  ## Parameters
  - `impl`: The registry implementation
  - `key`: The process key to look up

  ## Returns
  - `{:ok, {pid, metadata}}` if found
  - `:error` if not found
  """
  @spec lookup(t(), key :: term()) ::
          {:ok, {pid(), map()}} | :error
  def lookup(impl, key)

  @doc """
  Finds processes by a specific attribute value.

  ## Parameters
  - `impl`: The registry implementation
  - `attribute`: The attribute to search on (must be indexed)
  - `value`: The value to match

  ## Returns
  - `{:ok, [{key, pid, metadata}]}` with matching processes
  - `{:error, :unsupported_attribute}` if attribute not indexed
  """
  @spec find_by_attribute(t(), attribute :: atom(), value :: term()) ::
          {:ok, list({key :: term(), pid(), map()})} | {:error, term()}
  def find_by_attribute(impl, attribute, value)

  @doc """
  Performs an atomic query with multiple criteria.

  ## Parameters
  - `impl`: The registry implementation
  - `criteria`: List of criterion tuples

  ## Criterion Format
  Each criterion is a tuple: `{path, value, operation}`
  - `path`: List of atoms representing nested map access (e.g., `[:metadata, :capability]`)
  - `value`: The value to compare against
  - `operation`: Comparison operation (`:eq`, `:neq`, `:gt`, `:lt`, `:gte`, `:lte`, `:in`, `:not_in`)

  ## Returns
  - `{:ok, [{key, pid, metadata}]}` with matching processes
  - `{:error, :invalid_criteria}` if criteria format is invalid
  """
  @spec query(t(), [criterion]) ::
          {:ok, list({key :: term(), pid(), map()})} | {:error, term()}
  def query(impl, criteria)

  @doc """
  Returns the list of attributes that are indexed for fast lookup.

  ## Parameters
  - `impl`: The registry implementation

  ## Returns
  List of atoms representing indexed attributes
  """
  @spec indexed_attributes(t()) :: [atom()]
  def indexed_attributes(impl)

  @doc """
  Lists all registered processes, optionally filtered.

  ## Parameters
  - `impl`: The registry implementation
  - `filter`: Optional function to filter results by metadata

  ## Returns
  List of `{key, pid, metadata}` tuples
  """
  @spec list_all(t(), filter :: (map() -> boolean()) | nil) ::
          list({key :: term(), pid(), map()})
  def list_all(impl, filter \\ nil)

  @doc """
  Updates the metadata for a registered process.

  ## Parameters
  - `impl`: The registry implementation
  - `key`: The process key
  - `metadata`: New metadata map

  ## Returns
  - `:ok` on successful update
  - `{:error, :not_found}` if key not registered
  - `{:error, :invalid_metadata}` if metadata is invalid
  """
  @spec update_metadata(t(), key :: term(), metadata :: map()) ::
          :ok | {:error, term()}
  def update_metadata(impl, key, metadata)

  @doc """
  Unregisters a process.

  ## Parameters
  - `impl`: The registry implementation
  - `key`: The process key to unregister

  ## Returns
  - `:ok` on successful unregistration
  - `{:error, :not_found}` if key not registered
  """
  @spec unregister(t(), key :: term()) ::
          :ok | {:error, term()}
  def unregister(impl, key)

  @type criterion :: {
          path :: [atom()],
          value :: term(),
          op :: :eq | :neq | :gt | :lt | :gte | :lte | :in | :not_in
        }

  @doc """
  Returns the protocol version supported by this implementation.

  ## Returns
  - `{:ok, version_string}` - The supported protocol version
  - `{:error, :version_unsupported}` - If version checking is not supported

  ## Examples
      {:ok, "1.1"} = Foundation.Registry.protocol_version(registry_impl)
  """
  @spec protocol_version(t()) :: {:ok, String.t()} | {:error, term()}
  def protocol_version(impl)
end
