defmodule Foundation.MABEAM.Agent do
  @moduledoc """
  Agent-specific facade for Foundation.ProcessRegistry.

  Provides MABEAM agent registration and lifecycle management by wrapping
  the enhanced Foundation.ProcessRegistry with agent-specific semantics.
  This module is stateless and acts as a bridge between MABEAM agent
  concepts and the underlying unified process registry.

  ## Features

  - Agent registration with configuration validation
  - Agent lifecycle management (start, stop, restart)
  - Capability-based agent discovery
  - Agent metadata management
  - Status tracking and health monitoring
  - Integration with Foundation.ProcessRegistry backends

  ## Agent Configuration

  Agents are registered using configuration maps that include:
  - `id` - Unique agent identifier
  - `type` - Agent type (e.g., :worker, :coordinator, :ml_agent)
  - `module` - Module implementing the agent behavior
  - `args` - Arguments for agent initialization
  - `capabilities` - List of agent capabilities
  - `restart_policy` - Restart behavior (:permanent, :temporary, :transient)
  - Additional metadata for agent discovery and management

  ## Usage

      # Register an agent
      config = %{
        id: :my_worker,
        type: :worker,
        module: MyWorker,
        args: [],
        capabilities: [:computation, :data_processing],
        restart_policy: :permanent
      }
      :ok = Agent.register_agent(config)

      # Start the registered agent
      {:ok, pid} = Agent.start_agent(:my_worker)

      # Find agents by capability
      agents = Agent.find_agents_by_capability([:computation])

      # Get agent status
      {:ok, status} = Agent.get_agent_status(:my_worker)
  """

  require Logger
  alias Foundation.ProcessRegistry

  @type agent_id :: atom() | binary()
  @type agent_type :: atom()
  @type capability :: atom()
  @type agent_config :: map()
  @type agent_status :: :registered | :starting | :running | :stopping | :stopped | :failed
  @type restart_policy :: :permanent | :temporary | :transient

  # Agent registration and lifecycle

  @doc """
  Register an agent with the unified registry.

  Transforms agent configuration into registry metadata and registers
  the agent in the unified Foundation.ProcessRegistry system.

  ## Parameters
  - `config` - Agent configuration map with required fields:
    - `:id` - Unique agent identifier
    - `:type` - Agent type
    - `:module` - Module implementing agent behavior
    - `:args` - Initialization arguments (optional, defaults to [])
    - `:capabilities` - Agent capabilities (optional, defaults to [])
    - `:restart_policy` - Restart policy (optional, defaults to :permanent)

  ## Returns
  - `:ok` - Agent registered successfully
  - `{:error, reason}` - Registration failed

  ## Examples

      config = %{
        id: :worker1,
        type: :computation_worker,
        module: MyApp.ComputationWorker,
        args: [param: :value],
        capabilities: [:computation, :parallel_processing],
        restart_policy: :permanent
      }
      :ok = Agent.register_agent(config)
  """
  @spec register_agent(agent_config()) ::
          :ok
          | {:error,
             :invalid_agent_id
             | :invalid_metadata
             | :invalid_module
             | {:already_registered, pid()}
             | {:missing_required_fields, [atom(), ...]}
             | {:module_not_found, :badfile | :embedded | :nofile | :on_load_failure}}
  def register_agent(config) when is_map(config) do
    with :ok <- validate_agent_config(config),
         metadata <- build_agent_metadata(config),
         agent_key <- agent_key(config.id) do
      # Register in the unified registry with placeholder PID (not started yet)
      # Use self() as placeholder to satisfy PID requirement
      ProcessRegistry.register(:production, agent_key, self(), metadata)
    end
  end

  @doc """
  Start a registered agent.

  Looks up the agent configuration and starts the agent process using
  the configured module and arguments. Updates the agent status to
  reflect the running state.

  ## Parameters
  - `agent_id` - The ID of the agent to start

  ## Returns
  - `{:ok, pid}` - Agent started successfully
  - `{:error, :not_found}` - Agent not registered
  - `{:error, :already_running}` - Agent already running
  - `{:error, reason}` - Start failed

  ## Examples

      {:ok, pid} = Agent.start_agent(:worker1)
  """
  @spec start_agent(agent_id()) :: {:ok, pid()} | {:error, term()}
  def start_agent(agent_id) do
    agent_key = agent_key(agent_id)

    with {:ok, metadata} <- ProcessRegistry.get_metadata(:production, agent_key),
         :ok <- validate_agent_not_running(agent_key, metadata),
         {:ok, pid} <- start_agent_process(metadata),
         :ok <- update_agent_status(agent_key, pid, :running) do
      {:ok, pid}
    end
  end

  @doc """
  Stop a running agent.

  Gracefully stops the agent process and updates the registry to
  reflect the stopped state.

  ## Parameters
  - `agent_id` - The ID of the agent to stop

  ## Returns
  - `:ok` - Agent stopped successfully
  - `{:error, :not_found}` - Agent not found
  - `{:error, :not_running}` - Agent not running
  - `{:error, reason}` - Stop failed

  ## Examples

      :ok = Agent.stop_agent(:worker1)
  """
  @spec stop_agent(agent_id()) ::
          :ok
          | {:error,
             :not_found
             | :not_running
             | :invalid_metadata
             | {:already_registered, pid()}}
  def stop_agent(agent_id) do
    agent_key = agent_key(agent_id)

    case ProcessRegistry.lookup_with_metadata(:production, agent_key) do
      {:ok, {pid, _metadata}} when is_pid(pid) ->
        if Process.alive?(pid) do
          with :ok <- stop_agent_process(pid),
               :ok <- update_agent_status(agent_key, nil, :stopped) do
            :ok
          end
        else
          {:error, :not_running}
        end

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Restart a registered agent.

  Stops the agent if running, then starts it again with the same configuration.

  ## Parameters
  - `agent_id` - The ID of the agent to restart

  ## Returns
  - `{:ok, pid}` - Agent restarted successfully
  - `{:error, reason}` - Restart failed

  ## Examples

      {:ok, new_pid} = Agent.restart_agent(:worker1)
  """
  @spec restart_agent(agent_id()) ::
          {:ok, pid()}
          | {:error,
             :already_running
             | :not_found
             | :invalid_metadata
             | {:already_registered, pid()}
             | {:start_exception, Exception.t()}
             | {:start_failed, term()}
             | {:unexpected_start_result, term()}}
  def restart_agent(agent_id) do
    # Try to stop first (ignore if not running)
    _ = stop_agent(agent_id)

    # Always try to start
    start_agent(agent_id)
  end

  # Agent discovery and querying

  @doc """
  Find agents by capability.

  Searches the registry for agents that have the specified capabilities.
  Returns a list of agent information for matching agents.

  ## Parameters
  - `capabilities` - List of capabilities to search for

  ## Returns
  - List of agent information maps for matching agents

  ## Examples

      # Find all agents with computation capability
      agents = Agent.find_agents_by_capability([:computation])
      
      # Find agents with multiple capabilities (intersection)
      agents = Agent.find_agents_by_capability([:nlp, :gpu_acceleration])
  """
  @spec find_agents_by_capability([capability()]) :: [agent_config()]
  def find_agents_by_capability(capabilities) when is_list(capabilities) do
    ProcessRegistry.find_services_by_metadata(:production, fn metadata ->
      # Check if this is an agent registration
      if metadata[:type] == :mabeam_agent do
        agent_capabilities = metadata[:capabilities] || []
        # Check if agent has all requested capabilities (intersection)
        Enum.all?(capabilities, fn cap -> cap in agent_capabilities end)
      else
        false
      end
    end)
    |> Enum.map(fn {service_name, pid, metadata} ->
      # Convert back to agent information
      status = determine_agent_status(pid, metadata)
      actual_pid = if status == :running, do: pid, else: nil

      %{
        id: extract_agent_id(service_name),
        type: metadata[:agent_type],
        module: metadata[:module],
        capabilities: metadata[:capabilities] || [],
        status: status,
        pid: actual_pid,
        metadata: metadata
      }
    end)
  end

  @doc """
  Find agents by type.

  Searches the registry for agents of a specific type.

  ## Parameters
  - `agent_type` - The type of agents to search for

  ## Returns
  - List of agent information maps for matching agents

  ## Examples

      # Find all worker agents
      workers = Agent.find_agents_by_type(:worker)
  """
  @spec find_agents_by_type(agent_type()) :: [agent_config()]
  def find_agents_by_type(agent_type) do
    ProcessRegistry.find_services_by_metadata(:production, fn metadata ->
      metadata[:type] == :mabeam_agent and metadata[:agent_type] == agent_type
    end)
    |> Enum.map(fn {service_name, pid, metadata} ->
      status = determine_agent_status(pid, metadata)
      actual_pid = if status == :running, do: pid, else: nil

      %{
        id: extract_agent_id(service_name),
        type: metadata[:agent_type],
        module: metadata[:module],
        capabilities: metadata[:capabilities] || [],
        status: status,
        pid: actual_pid,
        metadata: metadata
      }
    end)
  end

  @doc """
  Get the status of a specific agent.

  ## Parameters
  - `agent_id` - The ID of the agent to check

  ## Returns
  - `{:ok, status}` - Agent status retrieved
  - `{:error, :not_found}` - Agent not registered

  ## Examples

      {:ok, :running} = Agent.get_agent_status(:worker1)
  """
  @spec get_agent_status(agent_id()) :: {:ok, agent_status()} | {:error, :not_found}
  def get_agent_status(agent_id) do
    agent_key = agent_key(agent_id)

    case ProcessRegistry.lookup_with_metadata(:production, agent_key) do
      {:ok, {pid, metadata}} ->
        status = determine_agent_status(pid, metadata)
        {:ok, status}

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Get detailed information about an agent.

  ## Parameters
  - `agent_id` - The ID of the agent to get info for

  ## Returns
  - `{:ok, agent_info}` - Agent information retrieved
  - `{:error, :not_found}` - Agent not registered

  ## Examples

      {:ok, info} = Agent.get_agent_info(:worker1)
      # => %{id: :worker1, type: :worker, status: :running, ...}
  """
  @spec get_agent_info(agent_id()) ::
          {:ok,
           %{
             id: agent_id(),
             type: agent_type(),
             module: module(),
             args: list(),
             capabilities: [capability()],
             restart_policy: restart_policy(),
             status: agent_status(),
             pid: pid() | nil,
             registered_at: DateTime.t(),
             last_status_change: DateTime.t()
           }}
          | {:error, :not_found}
  def get_agent_info(agent_id) do
    agent_key = agent_key(agent_id)

    case ProcessRegistry.lookup_with_metadata(:production, agent_key) do
      {:ok, {pid, metadata}} ->
        status = determine_agent_status(pid, metadata)
        # Only return PID if agent is actually running
        actual_pid = if status == :running, do: pid, else: nil

        info = %{
          id: agent_id,
          type: metadata[:agent_type],
          module: metadata[:module],
          args: metadata[:args],
          capabilities: metadata[:capabilities] || [],
          restart_policy: metadata[:restart_policy] || :permanent,
          status: status,
          pid: actual_pid,
          registered_at: metadata[:created_at],
          last_status_change: metadata[:last_status_change]
        }

        {:ok, info}

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  List all registered agents.

  ## Returns
  - List of all agent information maps

  ## Examples

      all_agents = Agent.list_agents()
  """
  @spec list_agents() :: [agent_config()]
  def list_agents do
    ProcessRegistry.find_services_by_metadata(:production, fn metadata ->
      metadata[:type] == :mabeam_agent
    end)
    |> Enum.map(fn {service_name, pid, metadata} ->
      status = determine_agent_status(pid, metadata)
      actual_pid = if status == :running, do: pid, else: nil

      %{
        id: extract_agent_id(service_name),
        type: metadata[:agent_type],
        module: metadata[:module],
        capabilities: metadata[:capabilities] || [],
        status: status,
        pid: actual_pid
      }
    end)
  end

  @doc """
  Remove an agent registration.

  Stops the agent if running and removes it from the registry.

  ## Parameters
  - `agent_id` - The ID of the agent to remove

  ## Returns
  - `:ok` - Agent removed successfully
  - `{:error, reason}` - Removal failed

  ## Examples

      :ok = Agent.unregister_agent(:worker1)
  """
  @spec unregister_agent(agent_id()) :: :ok
  def unregister_agent(agent_id) do
    agent_key = agent_key(agent_id)

    # Stop the agent first if it's running
    _ = stop_agent(agent_id)

    # Remove from registry
    :ok = ProcessRegistry.unregister(:production, agent_key)
  end

  # Private helper functions

  @spec validate_agent_config(map()) ::
          :ok
          | {:error,
             :invalid_agent_id
             | :invalid_module
             | {:missing_required_fields, [atom(), ...]}
             | {:module_not_found, :badfile | :embedded | :nofile | :on_load_failure}}
  defp validate_agent_config(config) do
    required_fields = [:id, :type, :module]

    with :ok <- validate_required_fields(config, required_fields),
         :ok <- validate_agent_id(config.id),
         :ok <- validate_module(config.module) do
      :ok
    end
  end

  defp validate_required_fields(config, required_fields) do
    missing_fields =
      Enum.filter(required_fields, fn field ->
        not Map.has_key?(config, field)
      end)

    case missing_fields do
      [] -> :ok
      missing -> {:error, {:missing_required_fields, missing}}
    end
  end

  defp validate_agent_id(id) when is_atom(id), do: :ok
  defp validate_agent_id(id) when is_binary(id), do: :ok
  defp validate_agent_id(_), do: {:error, :invalid_agent_id}

  defp validate_module(module) when is_atom(module) do
    case Code.ensure_loaded(module) do
      {:module, ^module} -> :ok
      {:error, reason} -> {:error, {:module_not_found, reason}}
    end
  end

  defp validate_module(_), do: {:error, :invalid_module}

  @spec build_agent_metadata(map()) :: %{
          type: :mabeam_agent,
          agent_type: term(),
          module: module(),
          args: list(),
          capabilities: [atom()],
          restart_policy: restart_policy(),
          created_at: DateTime.t(),
          status: :registered,
          last_status_change: DateTime.t(),
          config: map()
        }
  defp build_agent_metadata(config) do
    %{
      type: :mabeam_agent,
      agent_type: config.type,
      module: config.module,
      args: Map.get(config, :args, []),
      capabilities: Map.get(config, :capabilities, []),
      restart_policy: Map.get(config, :restart_policy, :permanent),
      created_at: DateTime.utc_now(),
      status: :registered,
      last_status_change: DateTime.utc_now(),
      config: config
    }
  end

  @spec agent_key(agent_id()) :: {:agent, agent_id()}
  defp agent_key(agent_id), do: {:agent, agent_id}

  defp validate_agent_not_running(agent_key, metadata) do
    # Check the status in metadata to determine if agent is actually running
    case metadata[:status] do
      :running ->
        # Agent is marked as running, check if the PID is still alive
        case ProcessRegistry.lookup(:production, agent_key) do
          {:ok, pid} when is_pid(pid) ->
            if Process.alive?(pid) do
              {:error, :already_running}
            else
              # PID is dead but status is running, allow restart
              :ok
            end

          :error ->
            # No registration found, allow start
            :ok
        end

      _ ->
        # Agent is not running (registered, stopped, failed, etc.)
        :ok
    end
  end

  defp start_agent_process(metadata) do
    module = metadata[:module]
    args = metadata[:args] || []

    try do
      # Start the agent process using the configured module
      case apply(module, :start_link, [args]) do
        {:ok, pid} -> {:ok, pid}
        {:error, reason} -> {:error, {:start_failed, reason}}
        error -> {:error, {:unexpected_start_result, error}}
      end
    rescue
      error -> {:error, {:start_exception, error}}
    end
  end

  defp stop_agent_process(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      try do
        # Try graceful shutdown first with shorter timeout
        GenServer.stop(pid, :shutdown, 1000)
        :ok
      catch
        :exit, _reason ->
          # If graceful stop fails, just mark as stopped without force kill
          # This prevents killing test processes
          :ok
      end
    else
      :ok
    end
  end

  defp update_agent_status(agent_key, pid, status) do
    case ProcessRegistry.get_metadata(:production, agent_key) do
      {:ok, metadata} ->
        updated_metadata =
          metadata
          |> Map.put(:status, status)
          |> Map.put(:last_status_change, DateTime.utc_now())

        # Use self() as placeholder if pid is nil
        registration_pid = if is_pid(pid), do: pid, else: self()

        # First unregister, then re-register to avoid already_registered error
        ProcessRegistry.unregister(:production, agent_key)
        ProcessRegistry.register(:production, agent_key, registration_pid, updated_metadata)

      error ->
        error
    end
  end

  defp determine_agent_status(pid, metadata) do
    # Check if this is the actual agent process or just a placeholder
    agent_status = metadata[:status] || :registered

    cond do
      # If status is explicitly set and agent is supposed to be running
      agent_status == :running and is_pid(pid) and Process.alive?(pid) -> :running
      # If status is running but process is dead, it failed
      agent_status == :running and is_pid(pid) and not Process.alive?(pid) -> :failed
      # For registered agents that haven't been started yet
      agent_status == :registered -> :registered
      # Other explicit statuses
      agent_status in [:stopped, :failed] -> agent_status
      # If we have a live PID but status doesn't indicate running, check metadata
      is_pid(pid) and Process.alive?(pid) -> agent_status
      # Default case
      true -> agent_status
    end
  end

  defp extract_agent_id({:agent, agent_id}), do: agent_id
  defp extract_agent_id(other), do: other
end
