defmodule JidoFoundation.AgentBridge do
  @moduledoc """
  Bridge between Jido agents and Foundation.ProcessRegistry.
  
  This module provides seamless integration between Jido agent lifecycle
  and Foundation's process registration and discovery services.
  
  Key capabilities:
  - Automatic registration of Jido agents with Foundation registry
  - Agent discovery through Foundation registry protocols
  - Agent metadata synchronization between frameworks
  - Agent lifecycle event bridging
  - Health monitoring integration
  
  ## Usage Examples
  
      # Register a Jido agent with Foundation
      {:ok, agent_ref} = AgentBridge.register_jido_agent(
        MyApp.CoderAgent,
        agent_id: :python_coder,
        capabilities: [:code_generation, :code_review],
        role: :executor
      )
      
      # Discover agents by capability
      {:ok, agents} = AgentBridge.find_agents_by_capability(:code_generation)
      
      # Start an agent with full Foundation integration
      {:ok, pid} = AgentBridge.start_agent_with_foundation(
        MyApp.ReviewerAgent,
        agent_id: :code_reviewer,
        foundation_namespace: :jido,
        auto_register: true
      )
  """

  alias Foundation.AgentRegistry
  alias Foundation.ProcessRegistry
  require Logger

  @type agent_config :: %{
          agent_id: atom(),
          agent_module: module(),
          capabilities: [atom()],
          role: atom(),
          resource_requirements: map(),
          communication_interfaces: [atom()],
          coordination_variables: [atom()],
          foundation_namespace: atom(),
          auto_register: boolean(),
          opts: keyword()
        }

  @type agent_reference :: {atom(), pid()}
  @type bridge_result :: {:ok, term()} | {:error, term()}

  @doc """
  Registers a Jido agent with Foundation's AgentRegistry.
  
  ## Parameters
  - `agent_module`: The Jido agent module
  - `config`: Agent configuration map
  
  ## Returns
  - `{:ok, agent_reference}` if registration successful
  - `{:error, reason}` if registration failed
  
  ## Configuration Options
  - `:agent_id` - Unique agent identifier (required)
  - `:capabilities` - List of agent capabilities (default: [])
  - `:role` - Agent role (default: :executor)
  - `:resource_requirements` - Resource requirements map (default: %{})
  - `:communication_interfaces` - Supported interfaces (default: [:jido_signal])
  - `:coordination_variables` - Variables this agent responds to (default: [])
  - `:foundation_namespace` - Foundation namespace (default: :jido)
  - `:auto_register` - Auto-register with Foundation (default: true)
  """
  @spec register_jido_agent(module(), agent_config()) :: bridge_result()
  def register_jido_agent(agent_module, config) do
    with {:ok, validated_config} <- validate_agent_config(config),
         {:ok, pid} <- start_jido_agent(agent_module, validated_config),
         {:ok, agent_metadata} <- build_agent_metadata(agent_module, validated_config, pid) do
      
      if validated_config.auto_register do
        case register_with_foundation(validated_config, pid, agent_metadata) do
          :ok ->
            Logger.info("Jido agent registered with Foundation", 
              agent_id: validated_config.agent_id,
              module: agent_module
            )
            {:ok, {validated_config.agent_id, pid}}
            
          {:error, reason} = error ->
            Logger.error("Failed to register Jido agent with Foundation",
              agent_id: validated_config.agent_id,
              reason: reason
            )
            # Stop the agent since registration failed
            if Process.alive?(pid), do: GenServer.stop(pid)
            error
        end
      else
        {:ok, {validated_config.agent_id, pid}}
      end
    end
  end

  @doc """
  Starts a Jido agent with full Foundation integration.
  
  This is a convenience function that combines agent startup with
  automatic Foundation registration and monitoring setup.
  
  ## Parameters
  - `agent_module`: The Jido agent module
  - `opts`: Start options and configuration
  
  ## Returns
  - `{:ok, pid}` if agent started successfully
  - `{:error, reason}` if startup failed
  """
  @spec start_agent_with_foundation(module(), keyword()) :: bridge_result()
  def start_agent_with_foundation(agent_module, opts) do
    config = build_config_from_opts(opts)
    
    case register_jido_agent(agent_module, config) do
      {:ok, {_agent_id, pid}} -> {:ok, pid}
      error -> error
    end
  end

  @doc """
  Discovers Jido agents by capability through Foundation registry.
  
  ## Parameters
  - `capability`: The capability to search for
  - `opts`: Search options
  
  ## Returns
  - `{:ok, [agent_reference()]}` with matching agents
  - `{:error, reason}` if search failed
  """
  @spec find_agents_by_capability(atom(), keyword()) :: bridge_result()
  def find_agents_by_capability(capability, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, :jido)
    registry = get_foundation_registry()
    
    case AgentRegistry.find_agents_by_capability(registry, namespace, capability) do
      {:ok, agents} ->
        # Filter to only return Jido agents
        jido_agents = Enum.filter(agents, &is_jido_agent?/1)
        {:ok, jido_agents}
        
      error -> error
    end
  end

  @doc """
  Discovers Jido agents by role through Foundation registry.
  
  ## Parameters
  - `role`: The role to search for
  - `opts`: Search options
  
  ## Returns
  - `{:ok, [agent_reference()]}` with matching agents
  - `{:error, reason}` if search failed
  """
  @spec find_agents_by_role(atom(), keyword()) :: bridge_result()
  def find_agents_by_role(role, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, :jido)
    registry = get_foundation_registry()
    
    case AgentRegistry.find_agents_by_role(registry, namespace, role) do
      {:ok, agents} ->
        jido_agents = Enum.filter(agents, &is_jido_agent?/1)
        {:ok, jido_agents}
        
      error -> error
    end
  end

  @doc """
  Gets comprehensive information about a Jido agent from Foundation registry.
  
  ## Parameters
  - `agent_id`: The agent identifier
  - `opts`: Query options
  
  ## Returns
  - `{:ok, agent_info}` with agent information
  - `{:error, reason}` if agent not found
  """
  @spec get_agent_info(atom(), keyword()) :: bridge_result()
  def get_agent_info(agent_id, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, :jido)
    registry = get_foundation_registry()
    
    case AgentRegistry.lookup_agent(registry, namespace, agent_id) do
      {:ok, {pid, metadata}} ->
        # Enhance with Jido-specific information
        enhanced_info = enhance_agent_info(pid, metadata)
        {:ok, enhanced_info}
        
      :error -> {:error, {:agent_not_found, agent_id}}
    end
  end

  @doc """
  Updates agent status in Foundation registry.
  
  ## Parameters
  - `agent_id`: The agent identifier
  - `status`: New agent status
  - `opts`: Update options
  
  ## Returns
  - `:ok` if update successful
  - `{:error, reason}` if update failed
  """
  @spec update_agent_status(atom(), atom(), keyword()) :: bridge_result()
  def update_agent_status(agent_id, status, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, :jido)
    registry = get_foundation_registry()
    
    case AgentRegistry.update_agent_status(registry, namespace, agent_id, status) do
      :ok ->
        Logger.debug("Agent status updated", agent_id: agent_id, status: status)
        :ok
        
      error -> error
    end
  end

  @doc """
  Unregisters a Jido agent from Foundation registry.
  
  ## Parameters
  - `agent_id`: The agent identifier
  - `opts`: Unregistration options
  
  ## Returns
  - `:ok` if unregistration successful
  - `{:error, reason}` if unregistration failed
  """
  @spec unregister_jido_agent(atom(), keyword()) :: bridge_result()
  def unregister_jido_agent(agent_id, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, :jido)
    registry = get_foundation_registry()
    
    case AgentRegistry.unregister_agent(registry, namespace, agent_id) do
      :ok ->
        Logger.info("Jido agent unregistered from Foundation", agent_id: agent_id)
        :ok
        
      error -> error
    end
  end

  @doc """
  Lists all active Jido agents in Foundation registry.
  
  ## Parameters
  - `opts`: Listing options
  
  ## Returns
  - `{:ok, [agent_reference()]}` with active agents
  - `{:error, reason}` if listing failed
  """
  @spec list_active_jido_agents(keyword()) :: bridge_result()
  def list_active_jido_agents(opts \\ []) do
    namespace = Keyword.get(opts, :namespace, :jido)
    registry = get_foundation_registry()
    
    case AgentRegistry.list_active_agents(registry, namespace) do
      {:ok, agents} ->
        # Filter to only Jido agents
        jido_agents = Enum.filter(agents, &is_jido_agent?/1)
        {:ok, jido_agents}
        
      error -> error
    end
  end

  @doc """
  Gets agent statistics from Foundation registry.
  
  ## Parameters
  - `opts`: Statistics options
  
  ## Returns
  - `{:ok, stats}` with agent statistics
  - `{:error, reason}` if statistics collection failed
  """
  @spec get_agent_statistics(keyword()) :: bridge_result()
  def get_agent_statistics(opts \\ []) do
    namespace = Keyword.get(opts, :namespace, :jido)
    registry = get_foundation_registry()
    
    case AgentRegistry.get_agent_stats(registry, namespace) do
      {:ok, stats} ->
        # Enhance with Jido-specific statistics
        enhanced_stats = enhance_agent_statistics(stats)
        {:ok, enhanced_stats}
        
      error -> error
    end
  end

  # Private implementation functions

  defp validate_agent_config(config) do
    required_fields = [:agent_id, :agent_module]
    
    case check_required_fields(config, required_fields) do
      :ok -> 
        validated_config = apply_defaults(config)
        {:ok, validated_config}
      error -> error
    end
  end

  defp check_required_fields(config, required_fields) do
    missing = Enum.reject(required_fields, &Map.has_key?(config, &1))
    
    case missing do
      [] -> :ok
      fields -> {:error, {:missing_required_fields, fields}}
    end
  end

  defp apply_defaults(config) do
    defaults = %{
      capabilities: [],
      role: :executor,
      resource_requirements: %{},
      communication_interfaces: [:jido_signal],
      coordination_variables: [],
      foundation_namespace: :jido,
      auto_register: true,
      opts: []
    }
    
    Map.merge(defaults, config)
  end

  defp start_jido_agent(agent_module, config) do
    # In a real implementation, this would start the Jido agent
    # For now, we'll simulate starting an agent process
    agent_opts = [
      agent_id: config.agent_id,
      name: {:via, Registry, {JidoFoundation.AgentRegistry, config.agent_id}}
    ] ++ config.opts

    case apply(agent_module, :start_link, [agent_opts]) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  rescue
    UndefinedFunctionError ->
      # Fallback to GenServer if agent doesn't have start_link/1
      {:error, {:invalid_agent_module, agent_module}}
  end

  defp build_agent_metadata(agent_module, config, pid) do
    metadata = %{
      agent_id: config.agent_id,
      agent_module: agent_module,
      capabilities: config.capabilities,
      role: config.role,
      status: :starting,
      resource_requirements: config.resource_requirements,
      communication_interfaces: config.communication_interfaces,
      coordination_variables: config.coordination_variables,
      performance_metrics: %{},
      bridge_type: :jido_foundation,
      jido_version: get_jido_version(),
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now(),
      pid: pid
    }
    
    {:ok, metadata}
  end

  defp register_with_foundation(config, pid, metadata) do
    registry = get_foundation_registry()
    namespace = config.foundation_namespace
    
    AgentRegistry.register_agent(registry, namespace, config.agent_id, pid, metadata)
  end

  defp build_config_from_opts(opts) do
    # Extract configuration from keyword list
    %{
      agent_id: Keyword.fetch!(opts, :agent_id),
      agent_module: opts[:agent_module] || raise("agent_module required"),
      capabilities: Keyword.get(opts, :capabilities, []),
      role: Keyword.get(opts, :role, :executor),
      resource_requirements: Keyword.get(opts, :resource_requirements, %{}),
      communication_interfaces: Keyword.get(opts, :communication_interfaces, [:jido_signal]),
      coordination_variables: Keyword.get(opts, :coordination_variables, []),
      foundation_namespace: Keyword.get(opts, :foundation_namespace, :jido),
      auto_register: Keyword.get(opts, :auto_register, true),
      opts: Keyword.drop(opts, [
        :agent_id, :agent_module, :capabilities, :role, :resource_requirements,
        :communication_interfaces, :coordination_variables, :foundation_namespace, :auto_register
      ])
    }
  end

  defp get_foundation_registry do
    # Get the configured Foundation registry implementation
    JidoFoundation.Application.foundation_registry() ||
      raise "No Foundation registry implementation configured"
  end

  defp is_jido_agent?({_agent_id, pid}) when is_pid(pid) do
    # Check if the process is a Jido agent
    try do
      case Process.info(pid, :dictionary) do
        {:dictionary, dict} ->
          Enum.any?(dict, fn
            {:jido_agent, true} -> true
            _ -> false
          end)
        _ -> false
      end
    rescue
      _ -> false
    end
  end

  defp is_jido_agent?(_), do: false

  defp enhance_agent_info(pid, metadata) do
    # Add Jido-specific information to agent info
    jido_info = get_jido_agent_info(pid)
    
    Map.merge(metadata, %{
      jido_info: jido_info,
      health_status: get_agent_health(pid),
      current_state: get_agent_state(pid),
      message_queue_length: get_message_queue_length(pid)
    })
  end

  defp enhance_agent_statistics(stats) do
    # Add Jido-specific statistics
    Map.merge(stats, %{
      jido_agents: count_jido_agents(stats),
      bridge_performance: get_bridge_performance_stats(),
      integration_health: assess_integration_health()
    })
  end

  defp get_jido_version do
    # Get Jido version if available
    case Application.spec(:jido, :vsn) do
      vsn when is_list(vsn) -> List.to_string(vsn)
      _ -> "unknown"
    end
  end

  # Placeholder functions for Jido-specific operations
  defp get_jido_agent_info(_pid), do: %{}
  defp get_agent_health(_pid), do: :healthy
  defp get_agent_state(_pid), do: :idle
  defp get_message_queue_length(pid) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, len} -> len
      _ -> 0
    end
  end
  defp count_jido_agents(_stats), do: 0
  defp get_bridge_performance_stats, do: %{}
  defp assess_integration_health, do: :healthy
end
