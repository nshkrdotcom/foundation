defmodule MABEAM.Coordination do
  @moduledoc """
  Domain-specific coordination APIs for agents using atomic discovery.

  All participant selection uses optimized multi-criteria queries to ensure
  only capable and healthy agents participate in coordination activities.

  ## Coordination Patterns Supported

  - **Consensus**: Multi-agent decision making with capability filtering
  - **Resource Allocation**: Coordinated resource distribution among agents
  - **Load Balancing**: Dynamic agent selection based on current load
  - **Capability-Based Selection**: Automatic participant filtering

  ## Performance Characteristics

  - Participant selection: O(1) via atomic ETS queries
  - Capability filtering: Built into selection queries
  - Health checking: Integrated into all coordination
  - Resource awareness: Automatic load balancing
  """

  require Logger
  alias Foundation.Telemetry

  # --- Capability-Based Coordination ---

  @doc """
  Coordinates agents with specific capability using atomic participant selection.

  ## Parameters
  - `capability`: Required capability for participants
  - `coordination_type`: Type of coordination (`:consensus`, `:barrier`, etc.)
  - `proposal`: The coordination proposal/data
  - `impl`: Optional explicit implementation

  ## Returns
  - `{:ok, coordination_ref}` on successful coordination start
  - `{:error, :no_capable_agents}` if no suitable agents found
  - `{:error, reason}` for other failures

  ## Examples
      # Start consensus among inference agents
      {:ok, ref} = MABEAM.Coordination.coordinate_capable_agents(
        :inference,
        :consensus,
        %{action: :scale_model, target_replicas: 3}
      )

      # Create barrier for training agents
      {:ok, barrier_id} = MABEAM.Coordination.coordinate_capable_agents(
        :training,
        :barrier,
        %{checkpoint: "epoch_10"}
      )
  """
  @spec coordinate_capable_agents(
          capability :: atom(),
          coordination_type :: atom(),
          proposal :: term(),
          impl :: term() | nil
        ) ::
          {:ok, term()} | {:error, term()}
  def coordinate_capable_agents(capability, coordination_type, proposal, impl \\ nil) do
    start_time = System.monotonic_time()

    case MABEAM.Discovery.find_capable_and_healthy(capability, impl) do
      {:ok, []} ->
        Logger.warning("No capable agents found for coordination: #{inspect(capability)}")

        Telemetry.emit(
          [:foundation, :mabeam, :coordination, :failed],
          %{duration: System.monotonic_time() - start_time},
          %{
            capability: capability,
            coordination_type: coordination_type,
            reason: :no_capable_agents
          }
        )

        {:error, :no_capable_agents}

      {:ok, agents} ->
        participant_ids = Enum.map(agents, fn {id, _pid, _metadata} -> id end)

        Logger.warning(
          "Starting #{coordination_type} coordination with #{length(participant_ids)} #{capability} agents"
        )

        Telemetry.emit(
          [:foundation, :mabeam, :coordination, :started],
          %{
            duration: System.monotonic_time() - start_time,
            participant_count: length(participant_ids)
          },
          %{
            capability: capability,
            coordination_type: coordination_type
          }
        )

        handle_coordination_type(coordination_type, participant_ids, proposal, impl)

      {:error, reason} ->
        Logger.warning("Failed to find capable agents for coordination: #{inspect(reason)}")

        Telemetry.emit(
          [:foundation, :mabeam, :coordination, :failed],
          %{duration: System.monotonic_time() - start_time},
          %{
            capability: capability,
            coordination_type: coordination_type,
            reason: reason
          }
        )

        {:error, reason}
    end
  end

  @doc """
  Coordinates resource allocation using sophisticated agent selection.

  This function uses atomic queries to find agents with sufficient resources
  and coordinates allocation among them based on the specified strategy.

  ## Parameters
  - `required_resources`: Map specifying minimum resource requirements
  - `allocation_strategy`: Strategy for resource allocation (`:greedy`, `:balanced`, `:random`)
  - `impl`: Optional explicit implementation

  ## Resource Requirements Format
      %{
        memory: 0.5,           # Minimum 50% memory available
        cpu: 0.3,              # Minimum 30% CPU available
        network_bandwidth: 100  # Minimum 100 Mbps available
      }

  ## Allocation Strategies
  - `:greedy` - Select agents with most available resources
  - `:balanced` - Select agents to maintain load balance
  - `:random` - Random selection from eligible agents

  ## Returns
  - `{:ok, consensus_ref}` with allocation coordination reference
  - `{:error, :insufficient_resources}` if no agents meet requirements
  - `{:error, reason}` for other failures
  """
  @spec coordinate_resource_allocation(
          required_resources :: map(),
          allocation_strategy :: atom(),
          impl :: term() | nil
        ) ::
          {:ok, term()} | {:error, term()}
  def coordinate_resource_allocation(required_resources, allocation_strategy, impl \\ nil) do
    start_time = System.monotonic_time()
    min_memory = Map.get(required_resources, :memory, 0.0)
    min_cpu = Map.get(required_resources, :cpu, 0.0)

    case MABEAM.Discovery.find_agents_with_resources(min_memory, min_cpu, impl) do
      {:ok, []} ->
        Logger.warning("No agents meet resource requirements: #{inspect(required_resources)}")

        Telemetry.emit(
          [:foundation, :mabeam, :coordination, :resource_allocation_failed],
          %{duration: System.monotonic_time() - start_time},
          %{
            required_resources: required_resources,
            allocation_strategy: allocation_strategy,
            reason: :insufficient_resources
          }
        )

        {:error, :insufficient_resources}

      {:ok, eligible_agents} ->
        # Apply allocation strategy to select optimal participants
        selected_agents =
          apply_allocation_strategy(eligible_agents, allocation_strategy, required_resources)

        participant_ids = Enum.map(selected_agents, fn {id, _pid, _metadata} -> id end)

        proposal = %{
          type: :resource_allocation,
          required_resources: required_resources,
          allocation_strategy: allocation_strategy,
          eligible_agents: participant_ids,
          selected_agents: participant_ids
        }

        Logger.info(
          "Starting resource allocation coordination with #{length(participant_ids)} agents using #{allocation_strategy} strategy"
        )

        Telemetry.emit(
          [:foundation, :mabeam, :coordination, :resource_allocation],
          %{
            duration: System.monotonic_time() - start_time,
            eligible_count: length(eligible_agents),
            selected_count: length(selected_agents)
          },
          %{
            allocation_strategy: allocation_strategy,
            min_memory: min_memory,
            min_cpu: min_cpu
          }
        )

        Foundation.start_consensus(participant_ids, proposal, 30_000, impl)

      {:error, reason} ->
        Logger.warning("Failed to find agents with resources: #{inspect(reason)}")

        Telemetry.emit(
          [:foundation, :mabeam, :coordination, :resource_allocation_failed],
          %{duration: System.monotonic_time() - start_time},
          %{
            required_resources: required_resources,
            allocation_strategy: allocation_strategy,
            reason: reason
          }
        )

        {:error, reason}
    end
  end

  @doc """
  Coordinates load balancing by selecting least loaded agents with specific capability.

  ## Parameters
  - `capability`: Required capability
  - `target_load`: Target load level (0.0 to 1.0)
  - `rebalance_threshold`: Threshold for triggering rebalancing (default: 0.2)
  - `impl`: Optional explicit implementation

  ## Returns
  - `{:ok, coordination_ref}` on successful load balancing coordination
  - `{:error, :no_rebalancing_needed}` if system is already balanced
  - `{:error, reason}` for other failures
  """
  @spec coordinate_load_balancing(
          capability :: atom(),
          target_load :: float(),
          rebalance_threshold :: float(),
          impl :: term() | nil
        ) ::
          {:ok, term()} | {:error, term()}
  def coordinate_load_balancing(capability, target_load, _rebalance_threshold \\ 0.2, impl \\ nil) do
    case MABEAM.Discovery.find_capable_and_healthy(capability, impl) do
      {:ok, agents} ->
        case analyze_load_distribution(agents, target_load) do
          {:needs_rebalancing, overloaded, underloaded} ->
            proposal = %{
              type: :load_balancing,
              capability: capability,
              target_load: target_load,
              overloaded_agents: Enum.map(overloaded, fn {id, _pid, _metadata} -> id end),
              underloaded_agents: Enum.map(underloaded, fn {id, _pid, _metadata} -> id end)
            }

            all_participants = Enum.map(agents, fn {id, _pid, _metadata} -> id end)

            Logger.info(
              "Starting load balancing coordination for #{length(all_participants)} #{capability} agents"
            )

            Foundation.start_consensus(all_participants, proposal, 45_000, impl)

          :balanced ->
            Logger.debug("Load balancing not needed for #{capability} agents - system is balanced")
            {:error, :no_rebalancing_needed}

          :insufficient_agents ->
            Logger.warning("Insufficient #{capability} agents for load balancing")
            {:error, :insufficient_agents}
        end

      {:error, reason} ->
        Logger.warning("Failed to find capable agents for load balancing: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Coordinates agent capability expansion/contraction based on system needs.

  ## Parameters
  - `source_capability`: Current capability to transition from
  - `target_capability`: Desired capability to transition to
  - `transition_count`: Number of agents to transition
  - `impl`: Optional explicit implementation

  ## Returns
  - `{:ok, coordination_ref}` on successful capability coordination
  - `{:error, reason}` for failures
  """
  @spec coordinate_capability_transition(
          source_capability :: atom(),
          target_capability :: atom(),
          transition_count :: pos_integer(),
          impl :: term() | nil
        ) ::
          {:ok, term()} | {:error, term()}
  def coordinate_capability_transition(
        source_capability,
        target_capability,
        transition_count,
        impl \\ nil
      ) do
    # Find agents with source capability who could potentially transition
    case MABEAM.Discovery.find_capable_and_healthy(source_capability, impl) do
      {:ok, source_agents} ->
        if length(source_agents) < transition_count do
          {:error, {:insufficient_source_agents, length(source_agents), transition_count}}
        else
          # Select least loaded agents for transition
          case MABEAM.Discovery.find_least_loaded_agents(source_capability, transition_count, impl) do
            {:ok, transition_candidates} ->
              participant_ids = Enum.map(transition_candidates, fn {id, _pid, _metadata} -> id end)

              proposal = %{
                type: :capability_transition,
                source_capability: source_capability,
                target_capability: target_capability,
                transition_agents: participant_ids,
                transition_count: transition_count
              }

              Logger.info(
                "Starting capability transition coordination: #{source_capability} -> #{target_capability} for #{length(participant_ids)} agents"
              )

              Foundation.start_consensus(participant_ids, proposal, 60_000, impl)

            {:error, reason} ->
              Logger.warning(
                "Failed to find least loaded agents for capability transition: #{inspect(reason)}"
              )

              {:error, reason}
          end
        end

      {:error, reason} ->
        Logger.warning("Failed to find source agents for capability transition: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # --- Multi-Agent Synchronization ---

  @doc """
  Creates a capability-based barrier for agent synchronization.

  ## Parameters
  - `capability`: Required capability for barrier participants
  - `barrier_id`: Unique identifier for the barrier
  - `additional_filters`: Optional additional filtering criteria
  - `impl`: Optional explicit implementation

  ## Returns
  - `{:ok, {barrier_id, participant_count}}` on successful barrier creation
  - `{:error, reason}` for failures
  """
  @spec create_capability_barrier(
          capability :: atom(),
          barrier_id :: term(),
          additional_filters :: map(),
          impl :: term() | nil
        ) ::
          {:ok, {term(), pos_integer()}} | {:error, term()}
  def create_capability_barrier(capability, barrier_id, additional_filters \\ %{}, impl \\ nil) do
    agents_result =
      if map_size(additional_filters) > 0 do
        apply_additional_filters(capability, additional_filters, impl)
      else
        MABEAM.Discovery.find_capable_and_healthy(capability, impl)
      end

    case agents_result do
      {:ok, agents} ->
        participant_count = length(agents)

        if participant_count == 0 do
          {:error, :no_eligible_participants}
        else
          case Foundation.create_barrier(barrier_id, participant_count, impl) do
            :ok ->
              Logger.info(
                "Created barrier #{inspect(barrier_id)} for #{participant_count} #{capability} agents"
              )

              {:ok, {barrier_id, participant_count}}

            error ->
              error
          end
        end

      {:error, reason} ->
        Logger.warning("Failed to find agents for barrier creation: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # --- Private Helper Functions ---

  defp handle_coordination_type(:consensus, participant_ids, proposal, impl) do
    Foundation.start_consensus(participant_ids, proposal, 30_000, impl)
  end

  defp handle_coordination_type(:barrier, participant_ids, _proposal, impl) do
    barrier_id = generate_barrier_id()

    case Foundation.create_barrier(barrier_id, length(participant_ids), impl) do
      :ok -> {:ok, barrier_id}
      error -> error
    end
  end

  defp handle_coordination_type(:resource_allocation, participant_ids, proposal, impl) do
    coordinate_resource_allocation_among_agents(participant_ids, proposal, impl)
  end

  defp handle_coordination_type(coordination_type, _participant_ids, _proposal, _impl) do
    {:error, {:unsupported_coordination_type, coordination_type}}
  end

  defp coordinate_resource_allocation_among_agents(participant_ids, proposal, impl) do
    enhanced_proposal =
      Map.merge(proposal, %{
        type: :resource_allocation,
        participants: participant_ids,
        coordination_timestamp: System.system_time(:millisecond)
      })

    Foundation.start_consensus(participant_ids, enhanced_proposal, 30_000, impl)
  end

  defp apply_allocation_strategy(eligible_agents, :greedy, _required_resources) do
    # Select agents with most available resources
    eligible_agents
    |> Enum.sort_by(fn {_id, _pid, metadata} ->
      resources = Map.get(metadata, :resources, %{})
      memory_available = Map.get(resources, :memory_available, 0.0)
      cpu_available = Map.get(resources, :cpu_available, 0.0)
      # Negative for descending sort
      -(memory_available + cpu_available)
    end)
    # Take top half + 1
    |> Enum.take(div(length(eligible_agents), 2) + 1)
  end

  defp apply_allocation_strategy(eligible_agents, :balanced, _required_resources) do
    # Select agents to maintain balanced load distribution
    avg_load = calculate_average_load(eligible_agents)

    eligible_agents
    |> Enum.filter(fn {_id, _pid, metadata} ->
      current_load = calculate_agent_load(metadata)
      # Within 10% of average
      current_load <= avg_load * 1.1
    end)
  end

  defp apply_allocation_strategy(eligible_agents, :random, _required_resources) do
    # Random selection from eligible agents
    # Select about 1/3
    count = max(1, div(length(eligible_agents), 3))
    Enum.take_random(eligible_agents, count)
  end

  defp apply_allocation_strategy(eligible_agents, _unknown_strategy, _required_resources) do
    # Default to greedy strategy
    apply_allocation_strategy(eligible_agents, :greedy, %{})
  end

  defp analyze_load_distribution(agents, _target_load) when length(agents) < 2 do
    :insufficient_agents
  end

  defp analyze_load_distribution(agents, target_load) do
    loads =
      Enum.map(agents, fn {_id, _pid, metadata} ->
        {metadata, calculate_agent_load(metadata)}
      end)

    {overloaded, underloaded} =
      Enum.split_with(loads, fn {_metadata, load} ->
        load > target_load
      end)

    if length(overloaded) > 0 and length(underloaded) > 0 do
      overloaded_agents =
        Enum.map(overloaded, fn {metadata, _load} ->
          find_agent_by_metadata(agents, metadata)
        end)
        |> Enum.filter(& &1)

      underloaded_agents =
        Enum.map(underloaded, fn {metadata, _load} ->
          find_agent_by_metadata(agents, metadata)
        end)
        |> Enum.filter(& &1)

      {:needs_rebalancing, overloaded_agents, underloaded_agents}
    else
      :balanced
    end
  end

  defp calculate_average_load(agents) do
    if Enum.empty?(agents) do
      0.0
    else
      total_load =
        Enum.reduce(agents, 0.0, fn {_id, _pid, metadata}, acc ->
          acc + calculate_agent_load(metadata)
        end)

      total_load / length(agents)
    end
  end

  defp calculate_agent_load(metadata) do
    resources = Map.get(metadata, :resources, %{})
    memory_usage = Map.get(resources, :memory_usage, 0.0)
    cpu_usage = Map.get(resources, :cpu_usage, 0.0)

    # Combined load score (can be customized based on requirements)
    (memory_usage + cpu_usage) / 2.0
  end

  defp find_agent_by_metadata(agents, target_metadata) do
    Enum.find(agents, fn {_id, _pid, metadata} ->
      metadata == target_metadata
    end)
  end

  defp apply_additional_filters(capability, filters, impl) do
    case MABEAM.Discovery.find_capable_and_healthy(capability, impl) do
      {:ok, base_agents} ->
        filtered_agents =
          Enum.filter(base_agents, fn {_id, _pid, metadata} ->
            Enum.all?(filters, fn {key, expected_value} ->
              Map.get(metadata, key) == expected_value
            end)
          end)

        {:ok, filtered_agents}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp generate_barrier_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16()
  end
end
