defmodule JidoFoundation.Bridge.AgentManager do
  @moduledoc """
  Manages Jido agent registration, discovery, and metadata within the Foundation framework.

  This module handles all agent-related operations that were previously in the Bridge module,
  providing a focused interface for agent management.
  """

  require Logger

  @doc """
  Registers a Jido agent with Foundation's registry.

  ## Options

  - `:capabilities` - List of agent capabilities (required)
  - `:metadata` - Additional metadata to store
  - `:health_check` - Custom health check function
  - `:registry` - Specific registry to use (defaults to configured)

  ## Examples

      JidoFoundation.Bridge.AgentManager.register(agent_pid,
        capabilities: [:planning, :execution],
        metadata: %{version: "1.0"}
      )
  """
  def register(agent_pid, opts \\ []) when is_pid(agent_pid) do
    capabilities = Keyword.get(opts, :capabilities, [])
    metadata = build_agent_metadata(agent_pid, capabilities, opts)
    registry = extract_registry(opts)

    # Use agent PID as the key for simplicity
    case Foundation.register(agent_pid, agent_pid, metadata, registry) do
      :ok ->
        Logger.info("Registered Jido agent #{inspect(agent_pid)} with Foundation")

        unless Keyword.get(opts, :skip_monitoring, false) do
          case setup_monitoring(agent_pid, opts) do
            :ok ->
              :ok

            {:error, reason} = error ->
              # Monitoring failed, unregister the agent to maintain consistency
              Logger.warning(
                "Monitoring setup failed for #{inspect(agent_pid)}: #{inspect(reason)}, unregistering agent"
              )

              Foundation.unregister(agent_pid, registry)
              error
          end
        else
          :ok
        end

      {:error, reason} = error ->
        Logger.error("Failed to register Jido agent: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Unregisters a Jido agent from Foundation.
  """
  def unregister(agent_pid, opts \\ []) when is_pid(agent_pid) do
    registry = extract_registry(opts)
    Foundation.unregister(agent_pid, registry)
  end

  @doc """
  Updates metadata for a registered Jido agent.
  """
  def update_metadata(agent_pid, updates, opts \\ []) when is_map(updates) do
    registry = extract_registry(opts)

    case Foundation.lookup(agent_pid, registry) do
      {:ok, {^agent_pid, current_metadata}} ->
        new_metadata = Map.merge(current_metadata, updates)
        Foundation.update_metadata(agent_pid, new_metadata, registry)

      :error ->
        {:error, :agent_not_registered}
    end
  end

  @doc """
  Finds Jido agents by capability using Foundation's registry.

  ## Examples

      {:ok, agents} = find_by_capability(:planning)
  """
  def find_by_capability(capability, opts \\ []) do
    registry = extract_registry(opts)

    # Get all Jido agents first, then filter by capability membership
    case Foundation.query([{[:framework], :jido, :eq}], registry) do
      {:ok, agents} ->
        # Filter agents that have the capability in their capability list
        matching_agents =
          Enum.filter(agents, fn {_key, _pid, metadata} ->
            capability in Map.get(metadata, :capability, [])
          end)

        {:ok, matching_agents}

      error ->
        error
    end
  end

  @doc """
  Finds Jido agents matching multiple criteria.

  ## Examples

      {:ok, agents} = find_agents([
        {[:capability], :execution, :eq},
        {[:health_status], :healthy, :eq}
      ])
  """
  def find_agents(criteria, opts \\ []) do
    registry = extract_registry(opts)

    # Check if we have capability criteria that need special handling
    {capability_criteria, other_criteria} =
      Enum.split_with(criteria, fn
        {[:capability], _value, :eq} -> true
        _ -> false
      end)

    # Start with Jido framework filter and other non-capability criteria
    base_criteria = [{[:framework], :jido, :eq} | other_criteria]

    case Foundation.query(base_criteria, registry) do
      {:ok, agents} ->
        # Apply capability filters manually for list membership
        filtered_agents =
          Enum.reduce(capability_criteria, agents, fn {[:capability], capability, :eq}, acc ->
            Enum.filter(acc, fn {_key, _pid, metadata} ->
              capability in Map.get(metadata, :capability, [])
            end)
          end)

        {:ok, filtered_agents}

      error ->
        error
    end
  end

  @doc """
  Registers multiple Jido agents in a single batch.

  ## Examples

      agents = [
        {agent1_pid, [capabilities: [:planning]]},
        {agent2_pid, [capabilities: [:execution]]}
      ]

      {:ok, registered} = batch_register(agents)
  """
  def batch_register(agents, opts \\ []) when is_list(agents) do
    batch_data =
      Enum.map(agents, fn {agent_pid, agent_opts} ->
        capabilities = Keyword.get(agent_opts, :capabilities, [])
        metadata = build_agent_metadata(agent_pid, capabilities, agent_opts)
        {agent_pid, agent_pid, metadata}
      end)

    Foundation.BatchOperations.batch_register(batch_data, opts)
  end

  @doc """
  Finds agents by capability and coordination requirements.

  Extends the basic agent discovery to include MABEAM coordination metadata.

  ## Examples

      {:ok, collaborative_agents} = find_coordinating_agents(
        capabilities: [:data_processing],
        coordination_type: :collaborative,
        max_agents: 5
      )
  """
  def find_coordinating_agents(criteria, opts \\ []) do
    registry = extract_registry(opts)
    max_agents = Keyword.get(opts, :max_agents, 10)
    coordination_type = Keyword.get(opts, :coordination_type)

    # Build search criteria
    base_criteria =
      case Keyword.get(criteria, :capabilities) do
        nil ->
          []

        capabilities when is_list(capabilities) ->
          Enum.map(capabilities, fn cap -> {[:capability], cap, :eq} end)

        capability ->
          [{[:capability], capability, :eq}]
      end

    # Add coordination criteria if specified
    coordination_criteria =
      if coordination_type do
        [{[:mabeam_enabled], true, :eq} | base_criteria]
      else
        base_criteria
      end

    # Add Jido framework filter
    jido_criteria = [{[:framework], :jido, :eq} | coordination_criteria]

    case Foundation.query(jido_criteria, registry) do
      {:ok, results} ->
        # Limit results if requested
        limited_results = Enum.take(results, max_agents)
        {:ok, limited_results}

      error ->
        error
    end
  end

  @doc """
  Starts a Jido agent and automatically registers it with Foundation.

  This is a convenience function that combines agent startup with registration.

  ## Examples

      {:ok, agent} = start_and_register(MyAgent, %{config: value},
        capabilities: [:planning, :execution]
      )
  """
  def start_and_register(agent_module, agent_config, bridge_opts \\ []) do
    with {:ok, agent_pid} <- agent_module.start_link(agent_config),
         :ok <- register(agent_pid, bridge_opts) do
      {:ok, agent_pid}
    else
      {:error, reason} = error ->
        Logger.error("Failed to start and register agent: #{inspect(reason)}")
        error
    end
  end

  # Private functions

  # Extract registry from either :registry or :supervision_tree option
  defp extract_registry(opts) do
    case {Keyword.get(opts, :registry), Keyword.get(opts, :supervision_tree)} do
      {nil, %{registry: registry}} -> registry
      {registry, _} -> registry
      {nil, nil} -> nil
    end
  end

  defp build_agent_metadata(_agent_pid, capabilities, opts) do
    base_metadata = %{
      framework: :jido,
      capability: capabilities,
      health_status: :healthy,
      node: node(),
      resources: %{memory_usage: 0.0},
      registered_at: DateTime.utc_now()
    }

    # Merge with any additional metadata
    custom_metadata = Keyword.get(opts, :metadata, %{})
    Map.merge(base_metadata, custom_metadata)
  end

  def setup_monitoring(agent_pid, opts) do
    # Use the supervised monitoring system
    case JidoFoundation.MonitorSupervisor.start_monitoring(agent_pid, opts) do
      {:ok, _monitor_pid} ->
        :ok

      {:error, reason} ->
        Logger.error(
          "Failed to start monitoring for agent #{inspect(agent_pid)}: #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @doc """
  Stops monitoring for a Jido agent.

  This cleanly terminates the supervised monitoring process.
  """
  def stop_monitoring(agent_pid) when is_pid(agent_pid) do
    JidoFoundation.MonitorSupervisor.stop_monitoring(agent_pid)
  end
end
