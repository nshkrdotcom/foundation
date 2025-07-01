defmodule JidoFoundation.Bridge do
  @moduledoc """
  Minimal surgical integration bridge between Jido agents and Foundation infrastructure.

  This module provides a thin facade that delegates to specialized managers, enabling
  Jido agents to leverage Foundation's production-grade infrastructure without coupling 
  the frameworks.

  ## Design Principles

  - **Minimal Coupling**: No modifications to either Jido or Foundation
  - **Selective Integration**: Choose which Foundation services to use
  - **Zero Overhead**: Direct pass-through where possible
  - **Progressive Enhancement**: Can be adopted incrementally
  - **Single Responsibility**: Each manager handles one concern

  ## Integration Points

  1. **Agent Management**: Register and discover agents via `AgentManager`
  2. **Signal Routing**: Signal bus and subscriptions via `SignalManager`
  3. **Resource Management**: Resource acquisition/release via `ResourceManager`
  4. **Protected Execution**: Circuit breakers and retries via `ExecutionManager`
  5. **Coordination**: Multi-agent coordination via `CoordinationManager`

  ## Usage

      # Register a Jido agent with Foundation
      {:ok, agent} = Jido.Agent.start_link(MyAgent, config)
      :ok = JidoFoundation.Bridge.register_agent(agent, [:capability1, :capability2])

      # Execute protected action
      JidoFoundation.Bridge.execute_protected(agent, :risky_action, args)
  """

  require Logger
  
  # Delegate modules for specific concerns
  alias JidoFoundation.Bridge.{
    AgentManager,
    SignalManager,
    ResourceManager,
    ExecutionManager,
    CoordinationManager
  }

  # Agent registration functions - Delegated to AgentManager

  @doc """
  Registers a Jido agent with Foundation's registry.

  ## Options

  - `:capabilities` - List of agent capabilities (required)
  - `:metadata` - Additional metadata to store
  - `:health_check` - Custom health check function
  - `:registry` - Specific registry to use (defaults to configured)

  ## Examples

      JidoFoundation.Bridge.register_agent(agent_pid,
        capabilities: [:planning, :execution],
        metadata: %{version: "1.0"}
      )
  """
  defdelegate register_agent(agent_pid, opts \\ []), to: AgentManager, as: :register

  @doc """
  Unregisters a Jido agent from Foundation.
  """
  defdelegate unregister_agent(agent_pid, opts \\ []), to: AgentManager, as: :unregister

  @doc """
  Updates metadata for a registered Jido agent.
  """
  defdelegate update_agent_metadata(agent_pid, updates, opts \\ []), to: AgentManager, as: :update_metadata

  # Telemetry integration - Delegated to SignalManager

  @doc """
  Emits a Jido agent event through Foundation telemetry.

  ## Examples

      emit_agent_event(agent_pid, :action_completed, %{
        action: :process_request,
        duration: 150
      })
  """
  defdelegate emit_agent_event(agent_pid, event_type, measurements \\ %{}, metadata \\ %{}), to: SignalManager

  # Infrastructure integration - Delegated to ExecutionManager

  @doc """
  Executes a Jido action with Foundation circuit breaker protection.

  ## Options

  - `:timeout` - Action timeout in milliseconds
  - `:fallback` - Fallback value or function if circuit is open
  - `:service_id` - Circuit breaker identifier (defaults to agent PID)

  ## Examples

      JidoFoundation.Bridge.execute_protected(agent, fn ->
        Jido.Action.execute(agent, :external_api_call, params)
      end)
  """
  defdelegate execute_protected(agent_pid, action_fun, opts \\ []), to: ExecutionManager

  @doc """
  Executes a Jido action with retry logic and Foundation integration.

  ## Parameters

  - `action_module` - The action module to execute
  - `params` - Parameters to pass to the action (default: %{})
  - `context` - Execution context (default: %{})
  - `opts` - Execution options (default: [])

  ## Returns

  - `{:ok, result}` - On successful execution
  - `{:error, reason}` - On failure after all retries

  ## Examples

      {:ok, result} = execute_with_retry(MyAction, %{data: "test"})
      {:error, reason} = execute_with_retry(BadAction, %{})
  """
  defdelegate execute_with_retry(action_module, params \\ %{}, context \\ %{}, opts \\ []), to: ExecutionManager

  @doc """
  Sets up monitoring for a Jido agent.

  Automatically updates Foundation registry when agent health changes.

  This function now uses proper OTP supervision via JidoFoundation.MonitorSupervisor
  instead of spawning unsupervised processes.
  """
  defdelegate setup_monitoring(agent_pid, opts \\ []), to: AgentManager

  # Resource management integration - Delegated to ResourceManager

  @doc """
  Acquires a resource token before executing a Jido action.

  ## Examples

      with {:ok, token} <- acquire_resource(:heavy_computation, %{agent: agent_pid}),
           {:ok, result} <- execute_action(agent_pid, :compute, params),
           :ok <- release_resource(token) do
        {:ok, result}
      end
  """
  defdelegate acquire_resource(resource_type, metadata \\ %{}), to: ResourceManager, as: :acquire

  @doc """
  Releases a previously acquired resource token.
  """
  defdelegate release_resource(token), to: ResourceManager, as: :release

  # Query and discovery - Delegated to AgentManager

  @doc """
  Finds Jido agents by capability using Foundation's registry.

  ## Examples

      {:ok, agents} = find_agents_by_capability(:planning)
  """
  defdelegate find_agents_by_capability(capability, opts \\ []), to: AgentManager, as: :find_by_capability

  @doc """
  Finds Jido agents matching multiple criteria.

  ## Examples

      {:ok, agents} = find_agents([
        {[:capability], :execution, :eq},
        {[:health_status], :healthy, :eq}
      ])
  """
  defdelegate find_agents(criteria, opts \\ []), to: AgentManager

  # Batch operations - Delegated to AgentManager

  @doc """
  Registers multiple Jido agents in a single batch.

  ## Examples

      agents = [
        {agent1_pid, [capabilities: [:planning]]},
        {agent2_pid, [capabilities: [:execution]]}
      ]

      {:ok, registered} = batch_register_agents(agents)
  """
  defdelegate batch_register_agents(agents, opts \\ []), to: AgentManager, as: :batch_register


  @doc """
  Stops monitoring for a Jido agent.

  This cleanly terminates the supervised monitoring process.
  """
  defdelegate stop_monitoring(agent_pid), to: AgentManager

  # Signal integration and routing functions - Delegated to SignalManager

  @doc """
  Starts the Jido signal bus for Foundation agents.

  The signal bus provides production-grade signal routing for Jido agents
  with features like persistence, replay, and middleware support.

  ## Options

  - `:name` - Bus name (default: `:foundation_signal_bus`)
  - `:middleware` - List of middleware modules (default: logger middleware)

  ## Examples

      {:ok, bus_pid} = Bridge.start_signal_bus()
      {:ok, bus_pid} = Bridge.start_signal_bus(name: :my_bus, middleware: [{MyMiddleware, []}])
  """
  defdelegate start_signal_bus(opts \\ []), to: SignalManager, as: :start_bus

  @doc """
  Subscribes a handler to receive signals matching a specific path pattern.

  Uses Jido.Signal.Bus path patterns, which support wildcards and more
  sophisticated routing than the previous custom SignalRouter.

  ## Examples

      # Subscribe to exact signal type
      {:ok, subscription_id} = Bridge.subscribe_to_signals("agent.task.completed", handler_pid)

      # Subscribe to all task signals
      {:ok, subscription_id} = Bridge.subscribe_to_signals("agent.task.*", handler_pid)

      # Subscribe to all agent signals
      {:ok, subscription_id} = Bridge.subscribe_to_signals("agent.*", handler_pid)

  ## Returns

  - `{:ok, subscription_id}` - Unique subscription identifier for unsubscribing
  - `{:error, reason}` - If subscription fails
  """
  defdelegate subscribe_to_signals(signal_path, handler_pid, opts \\ []), to: SignalManager, as: :subscribe

  @doc """
  Unsubscribes a handler from receiving signals using the subscription ID.

  ## Examples

      {:ok, subscription_id} = Bridge.subscribe_to_signals("agent.task.*", handler_pid)
      :ok = Bridge.unsubscribe_from_signals(subscription_id)
  """
  defdelegate unsubscribe_from_signals(subscription_id, opts \\ []), to: SignalManager, as: :unsubscribe

  @doc """
  Gets signal replay from the bus for debugging and monitoring.

  ## Examples

      # Get all recent signals
      {:ok, signals} = Bridge.get_signal_history()

      # Get signals matching a specific path
      {:ok, signals} = Bridge.get_signal_history("agent.task.*")
  """
  defdelegate get_signal_history(path \\ "*", opts \\ []), to: SignalManager, as: :get_history

  @doc """
  Emits a Jido signal through the signal bus.

  This function publishes signals to the Jido.Signal.Bus, which provides
  proper signal routing to all subscribers with persistence and middleware support.

  ## Signal Format

  Signals should be Jido.Signal structs or maps with:
  - `:type` - Signal type (e.g., "agent.task.completed")
  - `:source` - Signal source (e.g., "/agent/task_processor")
  - `:data` - Signal payload
  - `:time` - ISO 8601 timestamp (optional, auto-generated)

  ## Examples

      # Emit a task completion signal
      signal = %Jido.Signal{
        type: "agent.task.completed",
        source: "/agent/task_processor",
        data: %{result: "success", duration: 150}
      }
      {:ok, [signal]} = Bridge.emit_signal(signal)

      # Emit using map format (will be converted to Jido.Signal)
      signal_map = %{
        type: "agent.error.occurred",
        source: "/agent/worker",
        data: %{error: "timeout", retry_count: 3}
      }
      {:ok, [signal]} = Bridge.emit_signal(agent_pid, signal_map)
  """
  defdelegate emit_signal(agent, signal, opts \\ []), to: SignalManager, as: :emit

  # Backward compatibility aliases

  @doc """
  Legacy alias for start_signal_bus/1. Prefer start_signal_bus/1 for new code.
  """
  def start_signal_router(opts \\ []) do
    start_signal_bus(opts)
  end

  @doc """
  Legacy alias for get_signal_history/2. Prefer get_signal_history/2 for new code.
  """
  def get_signal_subscriptions(opts \\ []) do
    case get_signal_history("*", opts) do
      {:ok, signals} -> signals
      {:error, _} -> []
    end
  end

  @doc """
  Converts a Jido signal to CloudEvents v1.0.2 format.

  ## Examples

      signal = %{id: 123, type: "task.completed", source: "agent://123", data: %{}}
      cloudevent = Bridge.signal_to_cloudevent(signal)
  """
  defdelegate signal_to_cloudevent(signal), to: SignalManager

  @doc """
  Emits a signal with protection against handler failures.

  This function ensures that even if signal handlers crash, the emission
  process continues gracefully.

  ## Examples

      result = Bridge.emit_signal_protected(agent_pid, signal)
      # => :ok (even if some handlers crash)
  """
  defdelegate emit_signal_protected(agent_pid, signal), to: SignalManager, as: :emit_protected

  # MABEAM coordination functions - Delegated to CoordinationManager

  @doc """
  Coordinates communication between two Jido agents.

  Sends a coordination message from one agent to another through
  the MABEAM coordination system.

  ## Examples

      coordination_message = %{action: :collaborate, task_type: :data_processing}
      Bridge.coordinate_agents(sender_agent, receiver_agent, coordination_message)
  """
  defdelegate coordinate_agents(sender_agent, receiver_agent, message), to: CoordinationManager

  @doc """
  Distributes a task from a coordinator agent to a worker agent.

  ## Examples

      task = %{id: "task_1", type: :data_analysis, data: %{records: 1000}}
      Bridge.distribute_task(coordinator_agent, worker_agent, task)
  """
  defdelegate distribute_task(coordinator_agent, worker_agent, task), to: CoordinationManager

  @doc """
  Delegates a task from a higher-level agent to a lower-level agent in a hierarchy.

  Similar to distribute_task but with hierarchical semantics.

  ## Examples

      task = %{id: "complex_task", type: :analysis, subtasks: [...]}
      Bridge.delegate_task(supervisor_agent, manager_agent, task)
  """
  defdelegate delegate_task(delegator_agent, delegate_agent, task), to: CoordinationManager

  @doc """
  Creates a MABEAM coordination context for multiple agents.

  This sets up a coordination environment where multiple agents can
  collaborate on complex tasks.

  ## Examples

      agents = [agent1, agent2, agent3]
      {:ok, coordination_context} = Bridge.create_coordination_context(agents, %{
        coordination_type: :collaborative,
        timeout: 30_000
      })
  """
  defdelegate create_coordination_context(agents, opts \\ []), to: CoordinationManager

  @doc """
  Finds agents by capability and coordination requirements.

  Extends the basic agent discovery to include MABEAM coordination metadata.

  ## Examples

      {:ok, collaborative_agents} = Bridge.find_coordinating_agents(
        capabilities: [:data_processing],
        coordination_type: :collaborative,
        max_agents: 5
      )
  """
  defdelegate find_coordinating_agents(criteria, opts \\ []), to: AgentManager

  # Convenience functions for common patterns

  @doc """
  Starts a Jido agent and automatically registers it with Foundation.

  This is a convenience function that combines agent startup with registration.

  ## Examples

      {:ok, agent} = start_and_register_agent(MyAgent, %{config: value},
        capabilities: [:planning, :execution]
      )
  """
  defdelegate start_and_register_agent(agent_module, agent_config, bridge_opts \\ []), to: AgentManager, as: :start_and_register

  @doc """
  Executes a distributed operation across multiple Jido agents.

  Finds agents with the specified capability and executes the operation
  on each in parallel.

  ## Examples

      results = distributed_execute(:data_processing, fn agent ->
        GenServer.call(agent, {:process, data_chunk})
      end)
  """
  defdelegate distributed_execute(capability, operation_fun, opts \\ []), to: ExecutionManager
end
