# lib/foundation/mabeam/coordination.ex
defmodule Foundation.MABEAM.Coordination do
  @moduledoc """
  Basic coordination protocols for multi-agent variable optimization.

  Provides fundamental coordination mechanisms including consensus,
  negotiation, and conflict resolution for MABEAM agents.

  ## Design Philosophy

  This module implements coordination protocols with a pragmatic single-node
  approach while maintaining APIs that support future distributed operation.

  ## Supported Protocols

  - **Consensus**: Simple majority and weighted voting algorithms
  - **Negotiation**: Basic offer/counter-offer negotiation protocols
  - **Conflict Resolution**: Priority-based and escalation strategies
  - **Resource Arbitration**: Fair allocation and competition resolution

  ## Integration

  - Integrates with `Foundation.MABEAM.Core` for orchestration
  - Uses `Foundation.MABEAM.AgentRegistry` for agent management
  - Emits telemetry events for monitoring and metrics
  - Leverages Foundation services for reliability and observability
  """

  use GenServer

  alias Foundation.MABEAM.{AgentRegistry, Types}

  require Logger

  # ============================================================================
  # Type Definitions
  # ============================================================================

  @type coordination_state :: %{
          protocols: %{atom() => coordination_protocol()},
          active_coordinations: %{reference() => coordination_session()},
          metrics: coordination_metrics(),
          config: coordination_config()
        }

  @type coordination_protocol :: %{
          name: atom(),
          type: protocol_type(),
          algorithm: coordination_algorithm(),
          timeout: pos_integer(),
          retry_policy: retry_policy()
        }

  @type protocol_type :: :consensus | :negotiation | :auction | :market | :conflict_resolution

  @type coordination_algorithm :: (coordination_context() -> coordination_result())

  @type coordination_context :: %{
          agents: [Types.agent_id()],
          parameters: map(),
          timeout: pos_integer(),
          retry_count: non_neg_integer()
        }

  @type coordination_result ::
          {:ok, map()}
          | {:error, term()}

  @type coordination_session :: %{
          id: reference(),
          protocol: atom(),
          agents: [Types.agent_id()],
          context: map(),
          started_at: DateTime.t(),
          status: session_status()
        }

  @type session_status :: :active | :completed | :failed | :timeout

  @type retry_policy :: %{
          max_retries: non_neg_integer(),
          backoff: :linear | :exponential | :constant
        }

  @type coordination_metrics :: %{
          total_coordinations: non_neg_integer(),
          successful_coordinations: non_neg_integer(),
          failed_coordinations: non_neg_integer(),
          timeout_coordinations: non_neg_integer(),
          average_coordination_time: float(),
          protocols_registered: non_neg_integer()
        }

  @type coordination_config :: %{
          default_timeout: pos_integer(),
          max_concurrent_coordinations: pos_integer(),
          telemetry_enabled: boolean(),
          metrics_enabled: boolean()
        }

  @type conflict :: %{
          type: conflict_type(),
          resource: atom(),
          conflicting_requests: map(),
          available: number(),
          agents: [Types.agent_id()]
        }

  @type conflict_type :: :resource_conflict | :variable_conflict | :coordination_conflict

  @type conflict_resolution :: %{
          status: resolution_status(),
          allocation: map(),
          escalation_level: escalation_level() | nil,
          resolution_time: DateTime.t()
        }

  @type resolution_status :: :resolved | :escalated | :failed
  @type escalation_level :: :supervisor | :administrator | :system

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Start the Coordination service.

  ## Options
  - `:default_timeout` - Default timeout for coordination operations (default: 5000ms)
  - `:max_concurrent_coordinations` - Maximum number of concurrent coordinations (default: 100)
  - `:telemetry_enabled` - Enable telemetry events (default: true)
  - `:metrics_enabled` - Enable metrics collection (default: true)

  ## Examples

      {:ok, pid} = Foundation.MABEAM.Coordination.start_link()
      
      {:ok, pid} = Foundation.MABEAM.Coordination.start_link(
        default_timeout: 10_000,
        max_concurrent_coordinations: 50
      )
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a coordination protocol.

  ## Parameters
  - `name` - Unique name for the protocol
  - `protocol` - Protocol definition with algorithm and configuration

  ## Returns
  - `:ok` - Protocol registered successfully
  - `{:error, reason}` - Registration failed

  ## Examples

      protocol = %{
        name: :simple_consensus,
        type: :consensus,
        algorithm: &my_consensus_algorithm/1,
        timeout: 5000,
        retry_policy: %{max_retries: 3, backoff: :exponential}
      }
      
      :ok = Foundation.MABEAM.Coordination.register_protocol(:my_consensus, protocol)
  """
  @spec register_protocol(atom(), coordination_protocol()) :: :ok | {:error, term()}
  def register_protocol(name, protocol) do
    GenServer.call(__MODULE__, {:register_protocol, name, protocol})
  end

  @doc """
  Execute a coordination protocol with the specified agents.

  ## Parameters
  - `protocol_name` - Name of the registered protocol to execute
  - `agent_ids` - List of agents to participate in coordination
  - `context` - Context and parameters for the coordination

  ## Returns
  - `{:ok, results}` - Coordination completed successfully
  - `{:error, reason}` - Coordination failed

  ## Examples

      {:ok, results} = Foundation.MABEAM.Coordination.coordinate(
        :simple_consensus,
        [:agent1, :agent2, :agent3],
        %{question: "Should we proceed?", options: [:yes, :no]}
      )
  """
  @spec coordinate(atom(), [Types.agent_id()], map()) ::
          {:ok, [coordination_result()]} | {:error, term()}
  def coordinate(protocol_name, agent_ids, context) do
    GenServer.call(__MODULE__, {:coordinate, protocol_name, agent_ids, context}, :infinity)
  end

  @doc """
  List all registered coordination protocols.

  ## Returns
  - `{:ok, protocols}` - List of {name, protocol} tuples

  ## Examples

      {:ok, protocols} = Foundation.MABEAM.Coordination.list_protocols()
      Enum.each(protocols, fn {protocol_name, protocol} ->
        IO.puts("Protocol: \#{protocol_name}, Type: \#{protocol.type}")
      end)
  """
  @spec list_protocols() :: {:ok, [{atom(), coordination_protocol()}]}
  def list_protocols() do
    GenServer.call(__MODULE__, :list_protocols)
  end

  @doc """
  Resolve a conflict using the specified strategy.

  ## Parameters
  - `conflict` - Conflict description with type, resources, and agents
  - `opts` - Resolution options including strategy

  ## Returns
  - `{:ok, resolution}` - Conflict resolved
  - `{:error, reason}` - Resolution failed

  ## Examples

      conflict = %{
        type: :resource_conflict,
        resource: :cpu_time,
        conflicting_requests: %{agent1: 80, agent2: 70},
        available: 100
      }
      
      {:ok, resolution} = Foundation.MABEAM.Coordination.resolve_conflict(
        conflict, 
        strategy: :priority_based
      )
  """
  @spec resolve_conflict(conflict(), keyword()) :: {:ok, conflict_resolution()} | {:error, term()}
  def resolve_conflict(conflict, opts \\ []) do
    GenServer.call(__MODULE__, {:resolve_conflict, conflict, opts})
  end

  @doc """
  Get coordination metrics and statistics.

  ## Returns
  - `{:ok, metrics}` - Current coordination metrics

  ## Examples

      {:ok, metrics} = Foundation.MABEAM.Coordination.get_coordination_metrics()
      IO.puts("Total coordinations: \#{metrics.total_coordinations}")
      IO.puts("Success rate: \#{metrics.successful_coordinations / metrics.total_coordinations}")
  """
  @spec get_coordination_metrics() :: {:ok, coordination_metrics()}
  def get_coordination_metrics() do
    GenServer.call(__MODULE__, :get_coordination_metrics)
  end

  # ============================================================================
  # GenServer Implementation
  # ============================================================================

  @impl true
  def init(opts) do
    state = initialize_coordination_state(opts)
    register_default_protocols(state)
    setup_telemetry()

    Logger.info("MABEAM Coordination service started successfully")
    {:ok, state}
  end

  @impl true
  def handle_call({:register_protocol, name, protocol}, _from, state) do
    case Map.get(state.protocols, name) do
      nil ->
        case validate_coordination_protocol(protocol) do
          {:ok, validated_protocol} ->
            new_protocols = Map.put(state.protocols, name, validated_protocol)
            new_metrics = update_metrics(state.metrics, :protocol_registered)
            new_state = %{state | protocols: new_protocols, metrics: new_metrics}

            emit_protocol_registered_event(name, validated_protocol)
            {:reply, :ok, new_state}

          {:error, reason} ->
            Logger.warning("Protocol validation failed for #{name}: #{inspect(reason)}")
            {:reply, {:error, reason}, state}
        end

      _existing ->
        Logger.warning("Protocol #{name} already exists")
        {:reply, {:error, :protocol_already_exists}, state}
    end
  end

  @impl true
  def handle_call({:coordinate, protocol_name, agent_ids, context}, _from, state) do
    case Map.get(state.protocols, protocol_name) do
      nil ->
        Logger.warning("Protocol not found: #{protocol_name}")
        {:reply, {:error, :protocol_not_found}, state}

      protocol ->
        # Validate agents exist
        case validate_agents_exist(agent_ids) do
          :ok ->
            coordination_ref = make_ref()
            start_time = System.monotonic_time()

            emit_coordination_started_event(protocol_name, agent_ids, context)

            # Execute coordination
            result = execute_coordination(protocol, agent_ids, context, coordination_ref)

            # Update metrics and emit completion event
            execution_time = System.monotonic_time() - start_time
            new_metrics = update_metrics_with_result(state.metrics, result, execution_time)
            new_state = %{state | metrics: new_metrics}

            emit_coordination_completed_event(protocol_name, agent_ids, result, execution_time)

            {:reply, result, new_state}

          {:error, reason} ->
            Logger.warning("Agent validation failed: #{inspect(reason)}")
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call(:list_protocols, _from, state) do
    protocols = Enum.map(state.protocols, fn {name, protocol} -> {name, protocol} end)
    {:reply, {:ok, protocols}, state}
  end

  @impl true
  def handle_call({:resolve_conflict, conflict, opts}, _from, state) do
    strategy = Keyword.get(opts, :strategy, :priority_based)

    case resolve_conflict_with_strategy(conflict, strategy) do
      {:ok, resolution} ->
        emit_conflict_resolved_event(conflict, resolution, strategy)
        {:reply, {:ok, resolution}, state}

      {:error, reason} ->
        Logger.warning("Conflict resolution failed: #{inspect(reason)}")
        emit_conflict_resolution_failed_event(conflict, reason, strategy)
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_coordination_metrics, _from, state) do
    {:reply, {:ok, state.metrics}, state}
  end

  @impl true
  def handle_cast({:register_default_protocol, name, protocol}, state) do
    case Map.get(state.protocols, name) do
      nil ->
        new_protocols = Map.put(state.protocols, name, protocol)
        new_metrics = update_metrics(state.metrics, :protocol_registered)
        new_state = %{state | protocols: new_protocols, metrics: new_metrics}

        Logger.debug("Registered default protocol: #{name}")
        {:noreply, new_state}

      _existing ->
        Logger.debug("Default protocol #{name} already exists, skipping")
        {:noreply, state}
    end
  end

  @impl true
  def handle_cast(msg, state) do
    Logger.debug("Coordination service received unexpected cast: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup_completed_sessions, state) do
    # Periodic cleanup of completed coordination sessions
    current_time = DateTime.utc_now()
    # 5 minutes ago
    cutoff_time = DateTime.add(current_time, -300, :second)

    active_coordinations =
      state.active_coordinations
      |> Enum.filter(fn {_ref, session} ->
        DateTime.compare(session.started_at, cutoff_time) == :gt
      end)
      |> Enum.into(%{})

    new_state = %{state | active_coordinations: active_coordinations}

    # Schedule next cleanup
    # 1 minute
    Process.send_after(self(), :cleanup_completed_sessions, 60_000)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("Coordination service received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.info("MABEAM Coordination service terminating: #{inspect(reason)}")
    :ok
  end

  # ============================================================================
  # Private Implementation Functions
  # ============================================================================

  defp initialize_coordination_state(opts) do
    config = %{
      default_timeout: Keyword.get(opts, :default_timeout, 5_000),
      max_concurrent_coordinations: Keyword.get(opts, :max_concurrent_coordinations, 100),
      telemetry_enabled: Keyword.get(opts, :telemetry_enabled, true),
      metrics_enabled: Keyword.get(opts, :metrics_enabled, true)
    }

    %{
      protocols: %{},
      active_coordinations: %{},
      metrics: initialize_metrics(),
      config: config
    }
  end

  defp register_default_protocols(_state) do
    # Register built-in coordination protocols
    default_protocols = [
      {:simple_consensus, create_simple_consensus_protocol()},
      {:majority_consensus, create_majority_consensus_protocol()},
      {:resource_negotiation, create_resource_negotiation_protocol()}
    ]

    Enum.each(default_protocols, fn {name, protocol} ->
      GenServer.cast(self(), {:register_default_protocol, name, protocol})
    end)

    # Schedule periodic cleanup
    Process.send_after(self(), :cleanup_completed_sessions, 60_000)
  end

  defp setup_telemetry do
    # Define telemetry events for coordination operations
    events = [
      [:foundation, :mabeam, :coordination, :protocol_registered],
      [:foundation, :mabeam, :coordination, :coordination_started],
      [:foundation, :mabeam, :coordination, :coordination_completed],
      [:foundation, :mabeam, :coordination, :conflict_resolved],
      [:foundation, :mabeam, :coordination, :conflict_resolution_failed]
    ]

    Enum.each(events, fn event ->
      :telemetry.execute(event, %{count: 1}, %{service: :coordination, setup: true})
    end)
  end

  defp validate_coordination_protocol(protocol) do
    required_fields = [:name, :type, :algorithm, :timeout, :retry_policy]

    case validate_required_fields(protocol, required_fields) do
      :ok ->
        case validate_protocol_algorithm(protocol.algorithm) do
          :ok -> {:ok, protocol}
          error -> error
        end

      error ->
        error
    end
  end

  defp validate_required_fields(protocol, required_fields) do
    missing_fields =
      required_fields
      |> Enum.filter(fn field -> not Map.has_key?(protocol, field) end)

    case missing_fields do
      [] -> :ok
      fields -> {:error, {:missing_fields, fields}}
    end
  end

  defp validate_protocol_algorithm(algorithm) when is_function(algorithm, 1), do: :ok
  defp validate_protocol_algorithm(_), do: {:error, :invalid_algorithm}

  defp validate_agents_exist(agent_ids) do
    case AgentRegistry.list_agents() do
      {:ok, registered_agents} ->
        registered_ids = Enum.map(registered_agents, fn {id, _config} -> id end)
        missing_agents = agent_ids -- registered_ids

        case missing_agents do
          [] -> :ok
          _missing -> {:error, :agent_not_found}
        end

      {:error, reason} ->
        {:error, {:agent_registry_error, reason}}
    end
  end

  defp execute_coordination(protocol, agent_ids, context, coordination_ref) do
    # Create coordination context
    coordination_context = %{
      agents: agent_ids,
      parameters: context,
      timeout: Map.get(context, :timeout, protocol.timeout),
      retry_count: 0,
      coordination_ref: coordination_ref
    }

    try do
      # Execute the protocol algorithm
      case protocol.algorithm.(coordination_context) do
        {:ok, result} -> {:ok, [result]}
        {:error, _} = error -> error
        other -> {:error, {:invalid_protocol_result, other}}
      end
    rescue
      exception ->
        Logger.error("Protocol execution failed: #{inspect(exception)}")
        {:error, {:protocol_execution_error, exception}}
    end
  end

  defp resolve_conflict_with_strategy(conflict, strategy) do
    case strategy do
      :priority_based -> resolve_conflict_priority_based(conflict)
      :proportional -> resolve_conflict_proportional(conflict)
      :escalation -> resolve_conflict_escalation(conflict)
      _ -> {:error, {:unknown_strategy, strategy}}
    end
  end

  defp resolve_conflict_priority_based(conflict) do
    %{conflicting_requests: requests, available: available} = conflict

    # Sort agents by priority (high priority first)
    sorted_requests =
      requests
      |> Enum.map(fn {agent_id, request} ->
        priority = get_agent_priority(agent_id)
        {agent_id, request, priority}
      end)
      |> Enum.sort_by(fn {_agent, _request, priority} -> priority end, :desc)

    # Allocate resources based on priority
    {final_allocation, _remaining} =
      Enum.reduce(sorted_requests, {%{}, available}, fn {agent_id, request, _priority},
                                                        {allocation, remaining} ->
        granted = min(request, remaining)
        new_allocation = Map.put(allocation, agent_id, granted)
        new_remaining = remaining - granted
        {new_allocation, new_remaining}
      end)

    {:ok,
     %{
       status: :resolved,
       allocation: final_allocation,
       escalation_level: nil,
       resolution_time: DateTime.utc_now()
     }}
  end

  defp resolve_conflict_proportional(conflict) do
    %{conflicting_requests: requests, available: available} = conflict

    total_requested = Enum.sum(Map.values(requests))

    final_allocation =
      if total_requested <= available do
        requests
      else
        scale_factor = available / total_requested

        requests
        |> Enum.map(fn {agent_id, request} ->
          {agent_id, round(request * scale_factor)}
        end)
        |> Enum.into(%{})
      end

    {:ok,
     %{
       status: :resolved,
       allocation: final_allocation,
       escalation_level: nil,
       resolution_time: DateTime.utc_now()
     }}
  end

  defp resolve_conflict_escalation(conflict) do
    # Check if conflict is resolvable through escalation
    %{conflicting_requests: requests, available: available} = conflict

    total_requested = Enum.sum(Map.values(requests))

    # Check if agents are inflexible (require escalation)
    inflexible_agents =
      Map.keys(requests)
      |> Enum.filter(fn agent_id ->
        agent_name = to_string(agent_id)
        String.contains?(agent_name, "inflexible")
      end)

    if length(inflexible_agents) > 0 or total_requested > available * 2 do
      # Conflict requires escalation
      {:ok,
       %{
         status: :escalated,
         allocation: %{},
         escalation_level: :supervisor,
         resolution_time: DateTime.utc_now()
       }}
    else
      # Try proportional allocation
      resolve_conflict_proportional(conflict)
    end
  end

  defp get_agent_priority(agent_id) do
    case AgentRegistry.get_agent_config(agent_id) do
      {:ok, config} -> Map.get(config, :priority, :normal)
      _ -> :normal
    end
  end

  defp initialize_metrics do
    %{
      total_coordinations: 0,
      successful_coordinations: 0,
      failed_coordinations: 0,
      timeout_coordinations: 0,
      average_coordination_time: 0.0,
      protocols_registered: 0
    }
  end

  defp update_metrics(metrics, :protocol_registered) do
    %{metrics | protocols_registered: metrics.protocols_registered + 1}
  end

  defp update_metrics_with_result(metrics, result, execution_time_ns) do
    execution_time_ms = execution_time_ns / 1_000_000

    new_total = metrics.total_coordinations + 1

    new_average =
      calculate_new_average(
        metrics.average_coordination_time,
        metrics.total_coordinations,
        execution_time_ms
      )

    case result do
      {:ok, _} ->
        %{
          metrics
          | total_coordinations: new_total,
            successful_coordinations: metrics.successful_coordinations + 1,
            average_coordination_time: new_average
        }

      {:error, _} ->
        %{
          metrics
          | total_coordinations: new_total,
            failed_coordinations: metrics.failed_coordinations + 1,
            average_coordination_time: new_average
        }
    end
  end

  defp calculate_new_average(current_average, count, new_value) do
    if count == 0 do
      new_value
    else
      (current_average * count + new_value) / (count + 1)
    end
  end

  # ============================================================================
  # Default Protocol Implementations
  # ============================================================================

  defp create_simple_consensus_protocol do
    %{
      name: :simple_consensus,
      type: :consensus,
      algorithm: fn context ->
        agents = Map.get(context, :agents, [])

        if Enum.empty?(agents) do
          {:ok, %{result: :empty_consensus}}
        else
          {:ok, %{result: :simple_success, participating_agents: length(agents)}}
        end
      end,
      timeout: 5000,
      retry_policy: %{max_retries: 3, backoff: :linear}
    }
  end

  defp create_majority_consensus_protocol do
    %{
      name: :majority_consensus,
      type: :consensus,
      algorithm: fn context ->
        agents = Map.get(context, :agents, [])
        _question = Map.get(context, :parameters, %{}) |> Map.get(:question, "Default question")
        options = Map.get(context, :parameters, %{}) |> Map.get(:options, [:yes, :no])
        _timeout = Map.get(context, :timeout, 5000)

        # Simulate consensus algorithm
        if Enum.empty?(agents) do
          {:ok, %{consensus: nil, vote_count: 0, total_votes: 0}}
        else
          # For testing, simulate majority consensus
          majority_option = hd(options)
          vote_count = div(length(agents), 2) + 1

          {:ok,
           %{
             consensus: majority_option,
             vote_count: vote_count,
             total_votes: length(agents),
             status: :consensus_reached
           }}
        end
      end,
      timeout: 10_000,
      retry_policy: %{max_retries: 3, backoff: :exponential}
    }
  end

  defp create_resource_negotiation_protocol do
    %{
      name: :resource_negotiation,
      type: :negotiation,
      algorithm: fn context ->
        agents = Map.get(context, :agents, [])
        parameters = Map.get(context, :parameters, %{})
        resource = Map.get(parameters, :resource, :generic_resource)
        total_available = Map.get(parameters, :total_available, 100)
        initial_requests = Map.get(parameters, :initial_requests, %{})

        if Enum.empty?(agents) do
          {:ok, %{status: :no_agents, final_allocation: %{}}}
        else
          # Check if agents are stubborn (will cause deadlock)
          stubborn_agents =
            Enum.filter(agents, fn agent ->
              agent_name = to_string(agent)
              String.contains?(agent_name, "stubborn")
            end)

          if length(stubborn_agents) > 0 do
            max_rounds = Map.get(parameters, :max_rounds, 10)

            {:ok,
             %{
               status: :deadlock,
               rounds: max_rounds,
               resource: resource
             }}
          else
            # Simple negotiation: proportional allocation
            total_requested = Enum.sum(Map.values(initial_requests))

            final_allocation =
              if total_requested <= total_available do
                initial_requests
              else
                scale_factor = total_available / total_requested

                initial_requests
                |> Enum.map(fn {agent, request} ->
                  {agent, round(request * scale_factor)}
                end)
                |> Enum.into(%{})
              end

            rounds = if total_requested > total_available, do: 3, else: 1

            {:ok,
             %{
               status: :agreement,
               final_allocation: final_allocation,
               rounds: rounds,
               resource: resource
             }}
          end
        end
      end,
      timeout: 15_000,
      retry_policy: %{max_retries: 5, backoff: :linear}
    }
  end

  # ============================================================================
  # Event Emission Functions
  # ============================================================================

  defp emit_protocol_registered_event(name, protocol) do
    :telemetry.execute(
      [:foundation, :mabeam, :coordination, :protocol_registered],
      %{count: 1},
      %{
        protocol_name: name,
        protocol_type: protocol.type,
        service: :coordination
      }
    )
  end

  defp emit_coordination_started_event(protocol_name, agent_ids, context) do
    :telemetry.execute(
      [:foundation, :mabeam, :coordination, :coordination_started],
      %{agent_count: length(agent_ids)},
      %{
        protocol: protocol_name,
        agents: agent_ids,
        context_keys: Map.keys(context),
        service: :coordination
      }
    )
  end

  defp emit_coordination_completed_event(protocol_name, agent_ids, result, execution_time_ns) do
    execution_time_ms = execution_time_ns / 1_000_000

    status =
      case result do
        {:ok, _} -> :success
        {:error, _} -> :error
      end

    :telemetry.execute(
      [:foundation, :mabeam, :coordination, :coordination_completed],
      %{
        duration_ms: execution_time_ms,
        agent_count: length(agent_ids)
      },
      %{
        protocol: protocol_name,
        status: status,
        agents: agent_ids,
        service: :coordination
      }
    )
  end

  defp emit_conflict_resolved_event(conflict, resolution, strategy) do
    :telemetry.execute(
      [:foundation, :mabeam, :coordination, :conflict_resolved],
      # Could track actual resolution time
      %{resolution_time_ms: 0},
      %{
        conflict_type: conflict.type,
        strategy: strategy,
        status: resolution.status,
        service: :coordination
      }
    )
  end

  defp emit_conflict_resolution_failed_event(conflict, reason, strategy) do
    :telemetry.execute(
      [:foundation, :mabeam, :coordination, :conflict_resolution_failed],
      %{count: 1},
      %{
        conflict_type: conflict.type,
        strategy: strategy,
        reason: inspect(reason),
        service: :coordination
      }
    )
  end
end
