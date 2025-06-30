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

    # Wrap the action function to handle crashes gracefully
    protected_fun = fn ->
      try do
        action_fun.()
      catch
        :exit, reason ->
          Logger.warning("Jido action process exited: #{inspect(reason)}")
          fallback = Keyword.get(opts, :fallback, {:error, :process_exit})
          if is_function(fallback, 0), do: fallback.(), else: fallback

        kind, reason ->
          Logger.warning("Jido action crashed: #{kind} #{inspect(reason)}")
          fallback = Keyword.get(opts, :fallback, {:error, :action_crash})
          if is_function(fallback, 0), do: fallback.(), else: fallback
      end
    end

    Foundation.ErrorHandler.with_recovery(
      protected_fun,
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
  @spec execute_with_retry(module(), map(), map(), keyword()) ::
          {:ok, any()} | {:error, any()}
  def execute_with_retry(action_module, params \\ %{}, context \\ %{}, opts \\ []) do
    try do
      # Enhance context with Foundation metadata
      enhanced_context =
        Map.merge(context, %{
          foundation_bridge: true,
          agent_framework: :jido,
          timestamp: System.system_time(:microsecond)
        })

      # Extract Jido.Exec options
      exec_opts = [
        max_retries: Keyword.get(opts, :max_retries, 3),
        backoff: Keyword.get(opts, :backoff, 250),
        timeout: Keyword.get(opts, :timeout, 30_000),
        log_level: Keyword.get(opts, :log_level, :info)
      ]

      # Use Jido.Exec for proper action execution with built-in retry
      case Jido.Exec.run(action_module, params, enhanced_context, exec_opts) do
        {:ok, result} = success ->
          Logger.debug("Jido action executed successfully via Bridge",
            action: action_module,
            result: inspect(result)
          )

          success

        {:error, reason} = error ->
          Logger.warning("Jido action failed after retries via Bridge",
            action: action_module,
            reason: inspect(reason)
          )

          error
      end
    rescue
      error ->
        Logger.error("Exception during Jido action execution via Bridge",
          action: action_module,
          error: inspect(error)
        )

        {:error, {:execution_exception, error}}
    catch
      kind, value ->
        Logger.error("Caught #{kind} during Jido action execution via Bridge",
          action: action_module,
          value: inspect(value)
        )

        {:error, {:execution_caught, {kind, value}}}
    end
  end

  @doc """
  Sets up monitoring for a Jido agent.

  Automatically updates Foundation registry when agent health changes.

  This function now uses proper OTP supervision via JidoFoundation.MonitorSupervisor
  instead of spawning unsupervised processes.
  """
  def setup_monitoring(agent_pid, opts \\ []) do
    # Use the new supervised monitoring system
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

  # REMOVED: default_health_check/1 - moved to JidoFoundation.AgentMonitor.default_health_check/1

  @doc """
  Stops monitoring for a Jido agent.

  This cleanly terminates the supervised monitoring process.
  """
  def stop_monitoring(agent_pid) when is_pid(agent_pid) do
    JidoFoundation.MonitorSupervisor.stop_monitoring(agent_pid)
  end

  # REMOVED: monitor_agent_health/4 - replaced by JidoFoundation.AgentMonitor GenServer
  # This eliminates the unsupervised recursive receive loop that violated OTP principles

  # Signal integration and routing functions

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
  def start_signal_bus(opts \\ []) do
    name = Keyword.get(opts, :name, :foundation_signal_bus)
    middleware = Keyword.get(opts, :middleware, [{Jido.Signal.Bus.Middleware.Logger, []}])

    # Start Jido Signal Bus with Foundation-specific configuration
    Jido.Signal.Bus.start_link(
      [
        name: name,
        middleware: middleware
      ] ++ Keyword.drop(opts, [:name, :middleware])
    )
  end

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
  def subscribe_to_signals(signal_path, handler_pid, opts \\ []) do
    bus_name = Keyword.get(opts, :bus, :foundation_signal_bus)

    # Configure dispatch to the handler process
    dispatch_opts = [
      dispatch: {:pid, [target: handler_pid, delivery_mode: :async]}
    ]

    subscription_opts = Keyword.merge(dispatch_opts, Keyword.drop(opts, [:bus]))

    Jido.Signal.Bus.subscribe(bus_name, signal_path, subscription_opts)
  end

  @doc """
  Unsubscribes a handler from receiving signals using the subscription ID.

  ## Examples

      {:ok, subscription_id} = Bridge.subscribe_to_signals("agent.task.*", handler_pid)
      :ok = Bridge.unsubscribe_from_signals(subscription_id)
  """
  def unsubscribe_from_signals(subscription_id, opts \\ []) do
    bus_name = Keyword.get(opts, :bus, :foundation_signal_bus)
    Jido.Signal.Bus.unsubscribe(bus_name, subscription_id)
  end

  @doc """
  Gets signal replay from the bus for debugging and monitoring.

  ## Examples

      # Get all recent signals
      {:ok, signals} = Bridge.get_signal_history()

      # Get signals matching a specific path
      {:ok, signals} = Bridge.get_signal_history("agent.task.*")
  """
  def get_signal_history(path \\ "*", opts \\ []) do
    bus_name = Keyword.get(opts, :bus, :foundation_signal_bus)
    start_timestamp = Keyword.get(opts, :since, 0)

    Jido.Signal.Bus.replay(bus_name, path, start_timestamp, opts)
  end

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
  def emit_signal(agent, signal, opts \\ []) do
    # Agent parameter is used in telemetry metadata
    bus_name = Keyword.get(opts, :bus, :foundation_signal_bus)

    # Preserve original signal ID for telemetry
    original_signal_id =
      case signal do
        %{id: id} -> id
        _ -> nil
      end

    # Ensure signal is in the proper format
    normalized_signal =
      case signal do
        %Jido.Signal{} = sig ->
          sig

        signal_map when is_map(signal_map) ->
          # Convert legacy signal format to Jido.Signal
          type =
            Map.get(signal_map, :type) ||
              Map.get(signal_map, :path) ||
              "unknown"

          source =
            Map.get(signal_map, :source) ||
              "/agent/foundation"

          data = Map.get(signal_map, :data, %{})

          # Preserve original ID if present
          signal_attrs = %{
            type: type,
            source: source,
            data: data,
            time: DateTime.utc_now() |> DateTime.to_iso8601()
          }

          # Add ID if it exists in the original signal (convert to string for Jido.Signal)
          signal_attrs =
            case Map.get(signal_map, :id) do
              nil -> signal_attrs
              id -> Map.put(signal_attrs, "id", to_string(id))
            end

          case Jido.Signal.new(signal_attrs) do
            {:ok, signal} ->
              signal

            {:error, _} ->
              # Fallback with minimal fields
              case Jido.Signal.new(%{type: type, source: source}) do
                {:ok, signal} -> %{signal | data: data}
                {:error, _} -> nil
              end
          end

        _ ->
          # Fallback for other formats
          case Jido.Signal.new(%{
                 type: "unknown",
                 source: "/agent/foundation",
                 data: signal
               }) do
            {:ok, signal} -> signal
            {:error, _} -> nil
          end
      end

    # Publish to the signal bus if signal creation succeeded
    case normalized_signal do
      nil ->
        {:error, :invalid_signal_format}

      signal ->
        # Get the bus name from Foundation Signal Bus service
        actual_bus_name =
          case Foundation.Services.SignalBus.get_bus_name() do
            bus when is_atom(bus) -> bus
            # fallback to provided bus_name
            {:error, :not_started} -> bus_name
          end

        case Jido.Signal.Bus.publish(actual_bus_name, [signal]) do
          {:ok, [published_signal]} = result ->
            # Extract signal data from RecordedSignal structure
            signal_data = published_signal.signal

            # Also emit traditional telemetry for backward compatibility
            # Use original signal ID if available, otherwise use the Jido.Signal ID
            telemetry_signal_id = original_signal_id || signal_data.id

            :telemetry.execute(
              [:jido, :signal, :emitted],
              %{signal_id: telemetry_signal_id},
              %{
                agent_id: agent,
                signal_type: signal_data.type,
                signal_source: signal_data.source,
                framework: :jido,
                timestamp: System.system_time(:microsecond)
              }
            )

            result

          error ->
            error
        end
    end
  end

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
  def signal_to_cloudevent(signal) do
    # Extract signal data
    signal_id = Map.get(signal, :id, System.unique_integer())
    signal_type = Map.get(signal, :type, "unknown")
    source = Map.get(signal, :source, "unknown")
    data = Map.get(signal, :data, %{})
    time = Map.get(signal, :time, DateTime.utc_now())
    metadata = Map.get(signal, :metadata, %{})

    # Build CloudEvent structure
    %{
      specversion: "1.0",
      type: signal_type,
      source: source,
      id: to_string(signal_id),
      time: DateTime.to_iso8601(time),
      datacontenttype: "application/json",
      data: data,
      subject: Map.get(metadata, :subject),
      extensions: Map.drop(metadata, [:subject])
    }
  end

  @doc """
  Emits a signal with protection against handler failures.

  This function ensures that even if signal handlers crash, the emission
  process continues gracefully.

  ## Examples

      result = Bridge.emit_signal_protected(agent_pid, signal)
      # => :ok (even if some handlers crash)
  """
  def emit_signal_protected(agent_pid, signal) do
    emit_signal(agent_pid, signal)
    :ok
  catch
    kind, reason ->
      Logger.warning("Signal emission failed: #{kind} #{inspect(reason)}")
      :ok
  end

  # MABEAM coordination functions

  @doc """
  Coordinates communication between two Jido agents.

  Sends a coordination message from one agent to another through
  the MABEAM coordination system.

  ## Examples

      coordination_message = %{action: :collaborate, task_type: :data_processing}
      Bridge.coordinate_agents(sender_agent, receiver_agent, coordination_message)
  """
  def coordinate_agents(sender_agent, receiver_agent, message) do
    # Use supervised coordination instead of raw send()
    JidoFoundation.CoordinationManager.coordinate_agents(sender_agent, receiver_agent, message)
  catch
    kind, reason ->
      Logger.warning("Agent coordination failed: #{kind} #{inspect(reason)}")
      {:error, :coordination_failed}
  end

  @doc """
  Distributes a task from a coordinator agent to a worker agent.

  ## Examples

      task = %{id: "task_1", type: :data_analysis, data: %{records: 1000}}
      Bridge.distribute_task(coordinator_agent, worker_agent, task)
  """
  def distribute_task(coordinator_agent, worker_agent, task) do
    # Use supervised coordination instead of raw send()
    JidoFoundation.CoordinationManager.distribute_task(coordinator_agent, worker_agent, task)
  catch
    kind, reason ->
      Logger.warning("Task distribution failed: #{kind} #{inspect(reason)}")
      {:error, :distribution_failed}
  end

  @doc """
  Delegates a task from a higher-level agent to a lower-level agent in a hierarchy.

  Similar to distribute_task but with hierarchical semantics.

  ## Examples

      task = %{id: "complex_task", type: :analysis, subtasks: [...]}
      Bridge.delegate_task(supervisor_agent, manager_agent, task)
  """
  def delegate_task(delegator_agent, delegate_agent, task) do
    # Use supervised coordination instead of raw send()
    JidoFoundation.CoordinationManager.delegate_task(delegator_agent, delegate_agent, task)
  catch
    kind, reason ->
      Logger.warning("Task delegation failed: #{kind} #{inspect(reason)}")
      {:error, :delegation_failed}
  end

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
  def create_coordination_context(agents, opts \\ []) do
    coordination_type = Keyword.get(opts, :coordination_type, :general)
    timeout = Keyword.get(opts, :timeout, 30_000)

    context = %{
      type: coordination_type,
      agents: agents,
      created_at: DateTime.utc_now(),
      timeout: timeout,
      status: :active
    }

    # Use supervised coordination instead of raw send()
    case JidoFoundation.CoordinationManager.create_coordination_context(agents, context) do
      :ok -> {:ok, context}
      {:error, reason} -> {:error, reason}
    end
  end

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
    timeout = Keyword.get(opts, :timeout, 30_000)

    with {:ok, agents} <- find_agents_by_capability(capability, opts) do
      agent_pids = Enum.map(agents, fn {_key, pid, _metadata} -> pid end)

      # Use supervised task pool instead of Task.async_stream
      case JidoFoundation.TaskPoolManager.execute_batch(
             :agent_operations,
             agent_pids,
             operation_fun,
             max_concurrency: max_concurrency,
             timeout: timeout,
             on_timeout: :kill_task
           ) do
        {:ok, stream} ->
          results =
            stream
            |> Enum.map(fn
              {:ok, result} -> {:ok, result}
              {:exit, reason} -> {:error, reason}
            end)

          {:ok, results}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end
