defmodule Foundation do
  @moduledoc """
  Stateless facade for the Foundation Protocol Platform.

  This facade provides convenient access to the application-configured default
  implementations of Foundation protocols. For advanced scenarios requiring
  multiple implementations or dynamic dispatch, use the protocols directly.

  ## Configuration

  Configure implementations in your application config:

      # config/config.exs
      config :foundation,
        registry_impl: MyApp.AgentRegistry,
        coordination_impl: MyApp.AgentCoordination,
        infrastructure_impl: MyApp.AgentInfrastructure

  ## Usage Patterns

  ### Single Implementation (Most Common)

  Use the facade for convenient access to your configured defaults:

      # Uses the configured registry implementation
      Foundation.register("agent_1", pid, %{capability: :inference})
      Foundation.lookup("agent_1")

  ### Multiple Implementations

  Bypass the facade and use protocols directly when you need multiple backends:

      # Different registries for different agent types
      {:ok, ml_registry} = MLAgentRegistry.start_link()
      {:ok, http_registry} = HTTPWorkerRegistry.start_link()

      Foundation.Registry.register(ml_registry, "ml_agent", pid1, meta1)
      Foundation.Registry.register(http_registry, "worker", pid2, meta2)

  ### Testing

  The facade accepts an optional implementation parameter for testing:

      # In tests, pass a specific implementation
      test_registry = start_supervised!(TestRegistry)
      Foundation.register("key", pid, meta, test_registry)

  ## Protocol Versions

  - Foundation.Registry: v1.1
  - Foundation.Coordination: v1.0
  - Foundation.Infrastructure: v1.0
  """

  # --- Configuration Access ---

  defp registry_impl do
    case Application.get_env(:foundation, :registry_impl) do
      nil ->
        raise """
        Foundation.Registry implementation not configured.

        Add to your config:
            config :foundation, registry_impl: YourRegistryImpl

        Available MABEAM implementation:
            config :foundation, registry_impl: MABEAM.AgentRegistry

        For testing:
            config :foundation, registry_impl: MockRegistry
        """

      impl ->
        # Validate implementation is loadable
        unless Code.ensure_loaded?(impl) do
          raise """
          Registry implementation #{inspect(impl)} cannot be loaded.

          Please verify:
          1. Module exists and is compiled
          2. Dependencies are available
          3. Application is started

          Current load path: #{inspect(:code.get_path())}
          """
        end

        impl
    end
  end

  defp coordination_impl do
    Application.get_env(:foundation, :coordination_impl) ||
      raise """
      Foundation.Coordination implementation not configured.

      Add to your config:
      config :foundation, coordination_impl: YourCoordinationImpl
      """
  end

  defp infrastructure_impl do
    Application.get_env(:foundation, :infrastructure_impl) ||
      raise """
      Foundation.Infrastructure implementation not configured.

      Add to your config:
      config :foundation, infrastructure_impl: YourInfrastructureImpl
      """
  end

  # --- Registry API (Zero Overhead with Explicit Pass-Through) ---

  @doc """
  Registers a process with its metadata.

  ## Parameters
  - `key`: Unique identifier for the process
  - `pid`: The process PID to register
  - `metadata`: Map containing process metadata
  - `impl`: Optional explicit implementation (overrides config)

  ## Examples
      # Use configured implementation
      :ok = Foundation.register("agent_1", pid, %{capability: :inference})

      # Use explicit implementation (testing)
      :ok = Foundation.register("agent_1", pid, %{capability: :inference}, MockRegistry)
  """
  @spec register(key :: term(), pid(), metadata :: map(), impl :: term() | nil) ::
          :ok | {:error, term()}
  def register(key, pid, metadata, impl \\ nil) do
    actual_impl = impl || registry_impl()
    Foundation.Registry.register(actual_impl, key, pid, metadata)
  end

  @doc """
  Looks up a process by its key.

  ## Parameters
  - `key`: The process key to look up
  - `impl`: Optional explicit implementation (overrides config)

  ## Examples
      {:ok, {pid, metadata}} = Foundation.lookup("agent_1")
      {:ok, {pid, metadata}} = Foundation.lookup("agent_1", MockRegistry)
  """
  @spec lookup(key :: term(), impl :: term() | nil) ::
          {:ok, {pid(), map()}} | :error
  def lookup(key, impl \\ nil) do
    Foundation.PerformanceMonitor.time_operation(:registry_lookup, fn ->
      actual_impl = impl || registry_impl()
      Foundation.Registry.lookup(actual_impl, key)
    end)
  end

  @doc """
  Finds processes by a specific attribute value.

  ## Parameters
  - `attribute`: The attribute to search on (must be indexed)
  - `value`: The value to match
  - `impl`: Optional explicit implementation (overrides config)

  ## Examples
      {:ok, agents} = Foundation.find_by_attribute(:capability, :inference)
      {:ok, healthy} = Foundation.find_by_attribute(:health_status, :healthy)
  """
  @spec find_by_attribute(attribute :: atom(), value :: term(), impl :: term() | nil) ::
          {:ok, list({key :: term(), pid(), map()})} | {:error, term()}
  def find_by_attribute(attribute, value, impl \\ nil) do
    Foundation.PerformanceMonitor.time_operation(:registry_find_by_attribute, fn ->
      actual_impl = impl || registry_impl()
      Foundation.Registry.find_by_attribute(actual_impl, attribute, value)
    end)
  end

  @doc """
  Performs an atomic query with multiple criteria.

  ## Parameters
  - `criteria`: List of criterion tuples `{path, value, operation}`
  - `impl`: Optional explicit implementation (overrides config)

  ## Examples
      # Find healthy agents with inference capability
      criteria = [
        {[:capability], :inference, :eq},
        {[:health_status], :healthy, :eq}
      ]
      {:ok, agents} = Foundation.query(criteria)

      # Find agents with sufficient resources
      criteria = [
        {[:resources, :memory_available], 0.5, :gte},
        {[:resources, :cpu_available], 0.3, :gte}
      ]
      {:ok, agents} = Foundation.query(criteria)
  """
  @spec query([Foundation.Registry.criterion()], impl :: term() | nil) ::
          {:ok, list({key :: term(), pid(), map()})} | {:error, term()}
  def query(criteria, impl \\ nil) do
    Foundation.PerformanceMonitor.time_operation(:registry_query, fn ->
      actual_impl = impl || registry_impl()
      Foundation.Registry.query(actual_impl, criteria)
    end)
  end

  @doc """
  Returns the list of attributes that are indexed for fast lookup.

  ## Parameters
  - `impl`: Optional explicit implementation (overrides config)

  ## Examples
      attrs = Foundation.indexed_attributes()
      # => [:capability, :health_status, :node]
  """
  @spec indexed_attributes(impl :: term() | nil) :: [atom()]
  def indexed_attributes(impl \\ nil) do
    actual_impl = impl || registry_impl()
    Foundation.Registry.indexed_attributes(actual_impl)
  end

  @doc """
  Lists all registered processes, optionally filtered.

  ## Parameters
  - `filter`: Optional function to filter results by metadata
  - `impl`: Optional explicit implementation (overrides config)

  ## Examples
      all_agents = Foundation.list_all()

      # Filter by custom criteria
      high_memory_agents = Foundation.list_all(fn metadata ->
        get_in(metadata, [:resources, :memory_usage]) > 0.8
      end)
  """
  @spec list_all(filter :: (map() -> boolean()) | nil, impl :: term() | nil) ::
          list({key :: term(), pid(), map()})
  def list_all(filter \\ nil, impl \\ nil) do
    actual_impl = impl || registry_impl()
    Foundation.Registry.list_all(actual_impl, filter)
  end

  @doc """
  Updates the metadata for a registered process.

  ## Parameters
  - `key`: The process key
  - `metadata`: New metadata map
  - `impl`: Optional explicit implementation (overrides config)
  """
  @spec update_metadata(key :: term(), metadata :: map(), impl :: term() | nil) ::
          :ok | {:error, term()}
  def update_metadata(key, metadata, impl \\ nil) do
    actual_impl = impl || registry_impl()
    Foundation.Registry.update_metadata(actual_impl, key, metadata)
  end

  @doc """
  Unregisters a process.

  ## Parameters
  - `key`: The process key to unregister
  - `impl`: Optional explicit implementation (overrides config)
  """
  @spec unregister(key :: term(), impl :: term() | nil) ::
          :ok | {:error, term()}
  def unregister(key, impl \\ nil) do
    actual_impl = impl || registry_impl()
    Foundation.Registry.unregister(actual_impl, key)
  end

  # --- Coordination API with Explicit Pass-Through ---

  @doc """
  Starts a consensus process among participants.

  ## Parameters
  - `participants`: List of participant identifiers
  - `proposal`: The proposal to reach consensus on
  - `timeout`: Timeout in milliseconds (default: 30_000)
  - `impl`: Optional explicit implementation (overrides config)

  ## Examples
      {:ok, ref} = Foundation.start_consensus([:agent1, :agent2], %{action: :scale_up})
      {:ok, ref} = Foundation.start_consensus(participants, proposal, 60_000, MockCoordination)
  """
  @spec start_consensus(
          participants :: [term()],
          proposal :: term(),
          timeout(),
          impl :: term() | nil
        ) ::
          {:ok, consensus_ref :: term()} | {:error, term()}
  def start_consensus(participants, proposal, timeout \\ 30_000, impl \\ nil) do
    actual_impl = impl || coordination_impl()
    Foundation.Coordination.start_consensus(actual_impl, participants, proposal, timeout)
  end

  @doc """
  Submits a vote for an ongoing consensus.

  ## Parameters
  - `consensus_ref`: Reference returned from start_consensus
  - `participant`: The participant submitting the vote
  - `vote`: The vote value
  - `impl`: Optional explicit implementation (overrides config)
  """
  @spec vote(consensus_ref :: term(), participant :: term(), vote :: term(), impl :: term() | nil) ::
          :ok | {:error, term()}
  def vote(consensus_ref, participant, vote, impl \\ nil) do
    actual_impl = impl || coordination_impl()
    Foundation.Coordination.vote(actual_impl, consensus_ref, participant, vote)
  end

  @doc """
  Gets the result of a consensus process.

  ## Parameters
  - `consensus_ref`: Reference returned from start_consensus
  - `impl`: Optional explicit implementation (overrides config)
  """
  @spec get_consensus_result(consensus_ref :: term(), impl :: term() | nil) ::
          {:ok, result :: term()} | {:error, term()}
  def get_consensus_result(consensus_ref, impl \\ nil) do
    actual_impl = impl || coordination_impl()
    Foundation.Coordination.get_consensus_result(actual_impl, consensus_ref)
  end

  @doc """
  Creates a barrier for participant synchronization.

  ## Parameters
  - `barrier_id`: Unique identifier for the barrier
  - `participant_count`: Number of participants that must arrive
  - `impl`: Optional explicit implementation (overrides config)
  """
  @spec create_barrier(
          barrier_id :: term(),
          participant_count :: pos_integer(),
          impl :: term() | nil
        ) ::
          :ok | {:error, term()}
  def create_barrier(barrier_id, participant_count, impl \\ nil) do
    actual_impl = impl || coordination_impl()
    Foundation.Coordination.create_barrier(actual_impl, barrier_id, participant_count)
  end

  @doc """
  Signals arrival at a barrier.

  ## Parameters
  - `barrier_id`: The barrier identifier
  - `participant`: The arriving participant identifier
  - `impl`: Optional explicit implementation (overrides config)
  """
  @spec arrive_at_barrier(barrier_id :: term(), participant :: term(), impl :: term() | nil) ::
          :ok | {:error, term()}
  def arrive_at_barrier(barrier_id, participant, impl \\ nil) do
    actual_impl = impl || coordination_impl()
    Foundation.Coordination.arrive_at_barrier(actual_impl, barrier_id, participant)
  end

  @doc """
  Waits for all participants to arrive at a barrier.

  ## Parameters
  - `barrier_id`: The barrier identifier
  - `timeout`: Maximum time to wait in milliseconds (default: 60_000)
  - `impl`: Optional explicit implementation (overrides config)
  """
  @spec wait_for_barrier(barrier_id :: term(), timeout(), impl :: term() | nil) ::
          :ok | {:error, term()}
  def wait_for_barrier(barrier_id, timeout \\ 60_000, impl \\ nil) do
    actual_impl = impl || coordination_impl()
    Foundation.Coordination.wait_for_barrier(actual_impl, barrier_id, timeout)
  end

  @doc """
  Acquires a distributed lock.

  ## Parameters
  - `lock_id`: Unique identifier for the lock
  - `holder`: The process/agent requesting the lock
  - `timeout`: Maximum time to wait for lock acquisition (default: 30_000)
  - `impl`: Optional explicit implementation (overrides config)
  """
  @spec acquire_lock(lock_id :: term(), holder :: term(), timeout(), impl :: term() | nil) ::
          {:ok, lock_ref :: term()} | {:error, term()}
  def acquire_lock(lock_id, holder, timeout \\ 30_000, impl \\ nil) do
    actual_impl = impl || coordination_impl()
    Foundation.Coordination.acquire_lock(actual_impl, lock_id, holder, timeout)
  end

  @doc """
  Releases a distributed lock.

  ## Parameters
  - `lock_ref`: Reference returned from acquire_lock
  - `impl`: Optional explicit implementation (overrides config)
  """
  @spec release_lock(lock_ref :: term(), impl :: term() | nil) ::
          :ok | {:error, term()}
  def release_lock(lock_ref, impl \\ nil) do
    actual_impl = impl || coordination_impl()
    Foundation.Coordination.release_lock(actual_impl, lock_ref)
  end

  # --- Infrastructure API with Explicit Pass-Through ---

  @doc """
  Executes a function with circuit breaker protection.

  ## Parameters
  - `service_id`: The service identifier
  - `function`: Zero-arity function to execute
  - `context`: Additional context for the execution (default: %{})
  - `impl`: Optional explicit implementation (overrides config)

  ## Examples
      {:ok, result} = Foundation.execute_protected(:external_api, fn ->
        HTTPClient.get("/data")
      end)

      {:ok, result} = Foundation.execute_protected(:ml_service, fn ->
        MLModel.predict(data)
      end, %{agent_id: :agent1}, MockInfrastructure)
  """
  @spec execute_protected(
          service_id :: term(),
          function :: (-> any()),
          context :: map(),
          impl :: term() | nil
        ) ::
          {:ok, result :: any()} | {:error, term()}
  def execute_protected(service_id, function, context \\ %{}, impl \\ nil) do
    actual_impl = impl || infrastructure_impl()
    Foundation.Infrastructure.execute_protected(actual_impl, service_id, function, context)
  end

  @doc """
  Sets up a rate limiter for a resource.

  ## Parameters
  - `limiter_id`: Unique identifier for the rate limiter
  - `config`: Rate limiter configuration map
  - `impl`: Optional explicit implementation (overrides config)

  ## Examples
      :ok = Foundation.setup_rate_limiter(:api_calls, %{
        rate: 100,
        per: 60_000,  # per minute
        strategy: :token_bucket
      })
  """
  @spec setup_rate_limiter(limiter_id :: term(), config :: map(), impl :: term() | nil) ::
          :ok | {:error, term()}
  def setup_rate_limiter(limiter_id, config, impl \\ nil) do
    actual_impl = impl || infrastructure_impl()
    Foundation.Infrastructure.setup_rate_limiter(actual_impl, limiter_id, config)
  end

  @doc """
  Checks if a request is within rate limits.

  ## Parameters
  - `limiter_id`: The rate limiter identifier
  - `identifier`: Unique identifier for the requesting entity
  - `impl`: Optional explicit implementation (overrides config)

  ## Examples
      case Foundation.check_rate_limit(:api_calls, :agent1) do
        :ok -> make_api_call()
        {:error, :rate_limited} -> handle_rate_limit()
      end
  """
  @spec check_rate_limit(limiter_id :: term(), identifier :: term(), impl :: term() | nil) ::
          :ok | {:error, :rate_limited | :limiter_not_found}
  def check_rate_limit(limiter_id, identifier, impl \\ nil) do
    actual_impl = impl || infrastructure_impl()
    Foundation.Infrastructure.check_rate_limit(actual_impl, limiter_id, identifier)
  end

  # --- Protocol Versioning ---

  @doc """
  Returns protocol version information for all configured implementations.

  ## Returns
  Map containing version information for each protocol implementation.

  ## Examples
      %{
        registry: {:ok, "1.1"},
        coordination: {:ok, "1.0"},
        infrastructure: {:ok, "1.0"}
      } = Foundation.protocol_versions()
  """
  @spec protocol_versions() :: %{
          registry: {:ok, String.t()} | {:error, term()},
          coordination: {:ok, String.t()} | {:error, term()},
          infrastructure: {:ok, String.t()} | {:error, term()}
        }
  def protocol_versions do
    %{
      registry: get_protocol_version(:registry),
      coordination: get_protocol_version(:coordination),
      infrastructure: get_protocol_version(:infrastructure)
    }
  end

  @doc """
  Verifies that all configured implementations support required protocol versions.

  ## Parameters
  - `required_versions`: Map of protocol => minimum required version

  ## Examples
      required = %{registry: "1.1", coordination: "1.0"}
      case Foundation.verify_protocol_compatibility(required) do
        :ok -> start_application()
        {:error, incompatible} -> handle_version_error(incompatible)
      end
  """
  @spec verify_protocol_compatibility(map()) :: :ok | {:error, map()}
  def verify_protocol_compatibility(required_versions) do
    current_versions = protocol_versions()
    incompatible = find_incompatible_versions(required_versions, current_versions)

    if map_size(incompatible) == 0 do
      :ok
    else
      {:error, incompatible}
    end
  end

  # --- Private Helper Functions ---

  defp find_incompatible_versions(required_versions, current_versions) do
    Enum.reduce(required_versions, %{}, fn {protocol, required_version}, acc ->
      check_protocol_compatibility(protocol, required_version, current_versions, acc)
    end)
  end

  defp check_protocol_compatibility(protocol, required_version, current_versions, acc) do
    case Map.get(current_versions, protocol) do
      {:ok, current_version} ->
        if version_compatible?(current_version, required_version) do
          acc
        else
          Map.put(acc, protocol, {current_version, required_version})
        end
      {:error, reason} ->
        Map.put(acc, protocol, {:error, reason})
    end
  end

  defp get_protocol_version(:registry) do
    impl = registry_impl()
    Foundation.Registry.protocol_version(impl)
  rescue
    _ -> {:error, :implementation_not_configured}
  end

  defp get_protocol_version(:coordination) do
    impl = coordination_impl()
    if function_exported?(Foundation.Coordination, :protocol_version, 1) do
      Foundation.Coordination.protocol_version(impl)
    else
      {:ok, "1.0"}  # Default version if not implemented
    end
  rescue
    _ -> {:error, :implementation_not_configured}
  end

  defp get_protocol_version(:infrastructure) do
    impl = infrastructure_impl()
    if function_exported?(Foundation.Infrastructure, :protocol_version, 1) do
      Foundation.Infrastructure.protocol_version(impl)
    else
      {:ok, "1.0"}  # Default version if not implemented
    end
  rescue
    _ -> {:error, :implementation_not_configured}
  end

  defp version_compatible?(current, required) do
    # Simple version comparison - can be enhanced for semantic versioning
    Version.compare(current, required) != :lt
  rescue
    _ ->
      # Fallback for non-semver versions
      current >= required
  end
end
