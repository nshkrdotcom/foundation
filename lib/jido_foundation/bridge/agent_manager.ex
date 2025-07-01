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
    registry = Keyword.get(opts, :registry)

    # Use agent PID as the key for simplicity
    case Foundation.register(agent_pid, agent_pid, metadata, registry) do
      :ok ->
        Logger.info("Registered Jido agent #{inspect(agent_pid)} with Foundation")

        unless Keyword.get(opts, :skip_monitoring, false) do
          setup_monitoring(agent_pid, opts)
        end

        :ok

      {:error, reason} = error ->
        Logger.error("Failed to register Jido agent: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Unregisters a Jido agent from Foundation.
  """
  def unregister(agent_pid, opts \\ []) when is_pid(agent_pid) do
    registry = Keyword.get(opts, :registry)
    Foundation.unregister(agent_pid, registry)
  end

  @doc """
  Updates metadata for a registered Jido agent.
  """
  def update_metadata(agent_pid, updates, opts \\ []) when is_map(updates) do
    registry = Keyword.get(opts, :registry)

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
    registry = Keyword.get(opts, :registry)

    case Foundation.find_by_attribute(:capability, capability, registry) do
      {:ok, results} ->
        # Filter for Jido agents only
        jido_agents =
          Enum.filter(results, fn {_key, _pid, metadata} ->
            metadata[:framework] == :jido
          end)

        {:ok, jido_agents}

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
    registry = Keyword.get(opts, :registry)

    # Add Jido framework filter
    jido_criteria = [{[:framework], :jido, :eq} | criteria]

    Foundation.query(jido_criteria, registry)
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
    registry = Keyword.get(opts, :registry)
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