defmodule JidoFoundation.Bridge do
  @moduledoc """
  Minimal surgical integration bridge between Jido agents and Foundation infrastructure.

  This module provides a thin integration layer that enables Jido agents to leverage
  Foundation's production-grade infrastructure without coupling the frameworks.

  ## Design Principles

  - **Minimal Coupling**: No modifications to either Jido or Foundation
  - **Selective Integration**: Choose which Foundation services to use
  - **Zero Overhead**: Direct pass-through where possible
  - **Progressive Enhancement**: Can be adopted incrementally

  ## Integration Points

  1. **Agent Registration**: Register Jido agents with Foundation.Registry
  2. **Telemetry**: Forward Jido events through Foundation telemetry
  3. **Circuit Breakers**: Protect Jido actions with Foundation infrastructure
  4. **Resource Management**: Integrate with Foundation.ResourceManager
  5. **Health Monitoring**: Unified health checks across frameworks

  ## Usage

      # Register a Jido agent with Foundation
      {:ok, agent} = Jido.Agent.start_link(MyAgent, config)
      :ok = JidoFoundation.Bridge.register_agent(agent, [:capability1, :capability2])
      
      # Execute protected action
      JidoFoundation.Bridge.execute_protected(agent, :risky_action, args)
  """

  require Logger

  # Agent registration functions

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
  def register_agent(agent_pid, opts \\ []) when is_pid(agent_pid) do
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
  def unregister_agent(agent_pid, opts \\ []) when is_pid(agent_pid) do
    registry = Keyword.get(opts, :registry)
    Foundation.unregister(agent_pid, registry)
  end

  @doc """
  Updates metadata for a registered Jido agent.
  """
  def update_agent_metadata(agent_pid, updates, opts \\ []) when is_map(updates) do
    registry = Keyword.get(opts, :registry)

    case Foundation.lookup(agent_pid, registry) do
      {:ok, {^agent_pid, current_metadata}} ->
        new_metadata = Map.merge(current_metadata, updates)
        Foundation.update_metadata(agent_pid, new_metadata, registry)

      :error ->
        {:error, :agent_not_registered}
    end
  end

  # Telemetry integration

  @doc """
  Emits a Jido agent event through Foundation telemetry.

  ## Examples

      emit_agent_event(agent_pid, :action_completed, %{
        action: :process_request,
        duration: 150
      })
  """
  def emit_agent_event(agent_pid, event_type, measurements \\ %{}, metadata \\ %{}) do
    :telemetry.execute(
      [:jido, :agent, event_type],
      measurements,
      Map.merge(metadata, %{
        agent_id: agent_pid,
        framework: :jido,
        timestamp: System.system_time(:microsecond)
      })
    )
  end

  # Infrastructure integration

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
  def execute_protected(agent_pid, action_fun, opts \\ []) when is_function(action_fun, 0) do
    service_id = Keyword.get(opts, :service_id, {:jido_agent, agent_pid})

    Foundation.ErrorHandler.with_recovery(
      action_fun,
      Keyword.merge(opts,
        strategy: :circuit_break,
        circuit_breaker: service_id,
        telemetry_metadata: %{
          agent_id: agent_pid,
          framework: :jido
        }
      )
    )
  end

  @doc """
  Sets up monitoring for a Jido agent.

  Automatically updates Foundation registry when agent health changes.
  """
  def setup_monitoring(agent_pid, opts \\ []) do
    health_check = Keyword.get(opts, :health_check, &default_health_check/1)
    interval = Keyword.get(opts, :health_check_interval, 30_000)
    registry = Keyword.get(opts, :registry)

    # Start a simple monitoring process
    monitor_pid =
      spawn(fn ->
        Process.flag(:trap_exit, true)
        monitor_agent_health(agent_pid, health_check, interval, registry)
      end)

    # Store monitor PID in process dictionary for testing
    Process.put({:monitor, agent_pid}, monitor_pid)

    :ok
  end

  # Resource management integration

  @doc """
  Acquires a resource token before executing a Jido action.

  ## Examples

      with {:ok, token} <- acquire_resource(:heavy_computation, %{agent: agent_pid}),
           {:ok, result} <- execute_action(agent_pid, :compute, params),
           :ok <- release_resource(token) do
        {:ok, result}
      end
  """
  def acquire_resource(resource_type, metadata \\ %{}) do
    Foundation.ResourceManager.acquire_resource(resource_type, metadata)
  end

  @doc """
  Releases a previously acquired resource token.
  """
  def release_resource(token) do
    Foundation.ResourceManager.release_resource(token)
  end

  # Query and discovery

  @doc """
  Finds Jido agents by capability using Foundation's registry.

  ## Examples

      {:ok, agents} = find_agents_by_capability(:planning)
  """
  def find_agents_by_capability(capability, opts \\ []) do
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

  # Batch operations

  @doc """
  Registers multiple Jido agents in a single batch.

  ## Examples

      agents = [
        {agent1_pid, [capabilities: [:planning]]},
        {agent2_pid, [capabilities: [:execution]]}
      ]
      
      {:ok, registered} = batch_register_agents(agents)
  """
  def batch_register_agents(agents, opts \\ []) when is_list(agents) do
    batch_data =
      Enum.map(agents, fn {agent_pid, agent_opts} ->
        capabilities = Keyword.get(agent_opts, :capabilities, [])
        metadata = build_agent_metadata(agent_pid, capabilities, agent_opts)
        {agent_pid, agent_pid, metadata}
      end)

    Foundation.BatchOperations.batch_register(batch_data, opts)
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

  defp default_health_check(agent_pid) do
    # Simple process alive check
    if Process.alive?(agent_pid) do
      :healthy
    else
      :unhealthy
    end
  end

  defp monitor_agent_health(agent_pid, health_check, interval, registry) do
    Process.monitor(agent_pid)

    receive do
      {:DOWN, _ref, :process, ^agent_pid, _reason} ->
        # Agent died, update status and stop monitoring
        try do
          update_agent_metadata(agent_pid, %{health_status: :unhealthy}, registry: registry)
        catch
          _, _ -> :ok
        end

        :ok

      {:EXIT, _pid, _reason} ->
        # Monitor process being terminated
        :ok
    after
      interval ->
        # Periodic health check
        case health_check.(agent_pid) do
          :healthy ->
            try do
              update_agent_metadata(agent_pid, %{health_status: :healthy}, registry: registry)
            catch
              _, _ -> :ok
            end

            monitor_agent_health(agent_pid, health_check, interval, registry)

          status when status in [:degraded, :unhealthy] ->
            try do
              update_agent_metadata(agent_pid, %{health_status: status}, registry: registry)
            catch
              _, _ -> :ok
            end

            monitor_agent_health(agent_pid, health_check, interval, registry)

          _ ->
            # Invalid status, continue monitoring
            monitor_agent_health(agent_pid, health_check, interval, registry)
        end
    end
  end

  # Convenience functions for common patterns

  @doc """
  Starts a Jido agent and automatically registers it with Foundation.

  This is a convenience function that combines agent startup with registration.

  ## Examples

      {:ok, agent} = start_and_register_agent(MyAgent, %{config: value},
        capabilities: [:planning, :execution]
      )
  """
  def start_and_register_agent(agent_module, agent_config, bridge_opts \\ []) do
    with {:ok, agent_pid} <- agent_module.start_link(agent_config),
         :ok <- register_agent(agent_pid, bridge_opts) do
      {:ok, agent_pid}
    else
      {:error, reason} = error ->
        Logger.error("Failed to start and register agent: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Executes a distributed operation across multiple Jido agents.

  Finds agents with the specified capability and executes the operation
  on each in parallel.

  ## Examples

      results = distributed_execute(:data_processing, fn agent ->
        GenServer.call(agent, {:process, data_chunk})
      end)
  """
  def distributed_execute(capability, operation_fun, opts \\ [])
      when is_function(operation_fun, 1) do
    max_concurrency = Keyword.get(opts, :max_concurrency, System.schedulers_online())

    with {:ok, agents} <- find_agents_by_capability(capability, opts) do
      agent_pids = Enum.map(agents, fn {_key, pid, _metadata} -> pid end)

      results =
        agent_pids
        |> Task.async_stream(operation_fun,
          max_concurrency: max_concurrency,
          on_timeout: :kill_task
        )
        |> Enum.map(fn
          {:ok, result} -> {:ok, result}
          {:exit, reason} -> {:error, reason}
        end)

      {:ok, results}
    end
  end
end
