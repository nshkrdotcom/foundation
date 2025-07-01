defmodule MABEAM.CoordinationPatterns do
  @moduledoc """
  Common multi-agent coordination patterns for MABEAM.

  This module provides reusable patterns for coordinating multiple agents
  in various scenarios. These patterns can be used with any agent framework
  (including Jido) through the Foundation infrastructure.

  ## Patterns Included

  1. **Leader Election** - Select a leader from a group of agents
  2. **Work Distribution** - Distribute tasks among available agents
  3. **Consensus Building** - Reach agreement among agents
  4. **Barrier Synchronization** - Synchronize agent phases
  5. **Resource Pooling** - Share resources among agents
  6. **Hierarchical Teams** - Organize agents in hierarchies

  ## Design Philosophy

  These patterns are framework-agnostic and work through Foundation's
  universal protocols. They can be used with Jido agents, custom agents,
  or any other agent implementation registered with Foundation.
  """

  require Logger
  alias Foundation.{Coordination, Registry}

  # Dialyzer annotations for intentional no-return functions
  @dialyzer {:no_return, execute_distributed: 2}
  @dialyzer {:no_return, execute_distributed: 3}

  # Leader Election Pattern

  @doc """
  Implements leader election among a group of agents.

  ## Options

  - `:election_timeout` - Timeout for election process (default: 5000ms)
  - `:criteria` - Function to evaluate agent fitness for leadership
  - `:heartbeat_interval` - Leader heartbeat interval (default: 1000ms)

  ## Examples

      {:ok, leader} = CoordinationPatterns.elect_leader(
        team_id: :data_processors,
        capability: :data_processing
      )
  """
  def elect_leader(opts \\ []) do
    team_id = Keyword.fetch!(opts, :team_id)
    capability = Keyword.get(opts, :capability)
    timeout = Keyword.get(opts, :election_timeout, 5000)
    criteria_fn = Keyword.get(opts, :criteria, &default_leader_criteria/1)

    # Find eligible agents
    candidates = find_eligible_agents(team_id, capability)

    case candidates do
      [] ->
        {:error, :no_eligible_agents}

      agents ->
        # Start consensus process
        _agent_ids = Enum.map(agents, fn {id, _pid, _meta} -> id end)

        # Each agent evaluates candidates and votes
        votes = collect_votes(agents, candidates, criteria_fn, timeout)

        # Tally votes and determine leader
        leader = determine_leader(votes, candidates)

        # Update leader metadata
        mark_as_leader(leader, team_id)

        {:ok, leader}
    end
  end

  @doc """
  Monitors leader health and triggers re-election if needed.
  """
  def monitor_leader(leader_pid, team_id, opts \\ []) do
    interval = Keyword.get(opts, :check_interval, 5000)

    {:ok, monitor_pid} =
      Foundation.TaskHelper.spawn_supervised(fn ->
        ref = Process.monitor(leader_pid)
        monitor_leader_loop(leader_pid, ref, team_id, interval, opts)
      end)

    monitor_pid
  end

  # Work Distribution Pattern

  @doc """
  Distributes work items among available agents based on their capacity.

  ## Strategies

  - `:round_robin` - Distribute evenly in order
  - `:least_loaded` - Assign to least loaded agent
  - `:capability_match` - Match work to agent capabilities
  - `:random` - Random distribution

  ## Examples

      {:ok, assignments} = CoordinationPatterns.distribute_work(
        work_items,
        strategy: :least_loaded,
        capability: :data_processing
      )
  """
  def distribute_work(work_items, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :round_robin)
    capability = Keyword.get(opts, :capability)

    # Find available agents
    {:ok, agents} = find_available_agents(capability)

    if agents == [] do
      {:error, :no_agents_available}
    else
      assignments =
        case strategy do
          :round_robin -> distribute_round_robin(work_items, agents)
          :least_loaded -> distribute_least_loaded(work_items, agents)
          :capability_match -> distribute_by_capability(work_items, agents)
          :random -> distribute_random(work_items, agents)
        end

      {:ok, assignments}
    end
  end

  @doc """
  Executes distributed work and collects results.
  """
  def execute_distributed(assignments, operation_fn, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    max_concurrency = Keyword.get(opts, :max_concurrency, length(assignments))

    # ALWAYS require supervisor - fail fast if not available
    case Process.whereis(Foundation.TaskSupervisor) do
      nil ->
        raise "Foundation.TaskSupervisor not running. Ensure Foundation.Application is started."

      supervisor when is_pid(supervisor) ->
        results =
          assignments
          |> Task.Supervisor.async_stream_nolink(
            Foundation.TaskSupervisor,
            fn {agent_pid, work_items} ->
              execute_agent_work(agent_pid, work_items, operation_fn, timeout)
            end,
            max_concurrency: max_concurrency,
            timeout: timeout + 1000
          )
          |> Enum.map(fn
            {:ok, result} -> result
            {:exit, reason} -> {:error, {:agent_timeout, reason}}
          end)

        {:ok, results}
    end
  end

  # Consensus Building Pattern

  @doc """
  Implements consensus building among agents for decision making.

  ## Options

  - `:consensus_type` - :majority, :unanimous, :quorum (default: :majority)
  - `:quorum_size` - Number of agents for quorum (if type is :quorum)
  - `:timeout` - Consensus timeout (default: 10000ms)

  ## Examples

      {:ok, decision} = CoordinationPatterns.build_consensus(
        proposal: {:scale_up, 3},
        agents: agent_list,
        consensus_type: :majority
      )
  """
  def build_consensus(opts) do
    proposal = Keyword.fetch!(opts, :proposal)
    agents = Keyword.fetch!(opts, :agents)
    consensus_type = Keyword.get(opts, :consensus_type, :majority)
    timeout = Keyword.get(opts, :timeout, 10_000)

    # Start Foundation consensus
    participants = Enum.map(agents, fn {id, _pid, _meta} -> id end)

    {:ok, consensus_ref} =
      Coordination.start_consensus(
        participants,
        proposal,
        timeout
      )

    # Collect votes from agents
    votes = collect_agent_votes(agents, proposal, consensus_ref)

    # Determine consensus based on type
    result =
      case consensus_type do
        :majority -> check_majority(votes, length(agents))
        :unanimous -> check_unanimous(votes, length(agents))
        :quorum -> check_quorum(votes, Keyword.get(opts, :quorum_size, div(length(agents), 2) + 1))
      end

    notify_agents(agents, result)
    result
  end

  # Barrier Synchronization Pattern

  @doc """
  Synchronizes multiple agents at a barrier point.

  ## Examples

      # Setup barrier for 5 agents
      {:ok, barrier_id} = CoordinationPatterns.setup_barrier(:phase1, 5)

      # In each agent:
      :ok = CoordinationPatterns.wait_at_barrier(:phase1, agent_id)
  """
  def setup_barrier(barrier_id, expected_count, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 60_000)

    case Coordination.create_barrier(Coordination, barrier_id, expected_count) do
      :ok ->
        # Setup barrier monitoring
        {:ok, _monitor_pid} =
          Foundation.TaskHelper.spawn_supervised(fn ->
            monitor_barrier(barrier_id, expected_count, timeout)
          end)

        {:ok, barrier_id}

      error ->
        error
    end
  end

  def wait_at_barrier(barrier_id, agent_id, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 60_000)

    # Signal arrival
    :ok = Coordination.arrive_at_barrier(Coordination, barrier_id, agent_id)

    # Wait for all agents
    Coordination.wait_for_barrier(barrier_id, timeout)
  end

  # Resource Pooling Pattern

  @doc """
  Creates a resource pool shared among agents.

  ## Examples

      {:ok, pool} = CoordinationPatterns.create_resource_pool(
        :connection_pool,
        resources: create_connections(10),
        checkout_timeout: 5000
      )
  """
  def create_resource_pool(pool_id, opts) do
    resources = Keyword.fetch!(opts, :resources)

    # Use Foundation registry to track pool
    pool_metadata = %{
      type: :resource_pool,
      resources: resources,
      available: resources,
      checked_out: %{},
      max_size: length(resources),
      checkout_timeout: Keyword.get(opts, :checkout_timeout, 5000)
    }

    case Foundation.register(pool_id, self(), pool_metadata) do
      :ok ->
        # Start pool manager
        {:ok, manager} = start_pool_manager(pool_id, pool_metadata)
        {:ok, %{pool_id: pool_id, manager: manager}}

      error ->
        error
    end
  end

  @doc """
  Checks out a resource from the pool.
  """
  def checkout_resource(pool_id, agent_id, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)

    GenServer.call(
      {:via, Registry, {Foundation.Registry, pool_id}},
      {:checkout, agent_id},
      timeout
    )
  end

  @doc """
  Returns a resource to the pool.
  """
  def checkin_resource(pool_id, agent_id, resource) do
    GenServer.cast(
      {:via, Registry, {Foundation.Registry, pool_id}},
      {:checkin, agent_id, resource}
    )
  end

  # Hierarchical Teams Pattern

  @doc """
  Organizes agents into hierarchical teams with supervisors and workers.

  ## Examples

      {:ok, hierarchy} = CoordinationPatterns.create_hierarchy(
        team_structure: %{
          supervisor: supervisor_agent,
          teams: [
            %{lead: team1_lead, members: team1_members},
            %{lead: team2_lead, members: team2_members}
          ]
        }
      )
  """
  def create_hierarchy(opts) do
    structure = Keyword.fetch!(opts, :team_structure)
    hierarchy_id = Keyword.get(opts, :hierarchy_id, generate_hierarchy_id())

    # Register supervisor
    supervisor = structure.supervisor
    :ok = tag_agent_role(supervisor, :supervisor, hierarchy_id)

    # Register team leads and members
    teams =
      Enum.map(structure.teams, fn team ->
        :ok = tag_agent_role(team.lead, :team_lead, hierarchy_id)

        Enum.each(team.members, fn member ->
          :ok = tag_agent_role(member, :team_member, hierarchy_id)
        end)

        %{lead: team.lead, members: team.members}
      end)

    # Setup communication channels
    setup_hierarchy_channels(supervisor, teams, hierarchy_id)

    {:ok,
     %{
       hierarchy_id: hierarchy_id,
       supervisor: supervisor,
       teams: teams
     }}
  end

  @doc """
  Broadcasts a message down the hierarchy.
  """
  def broadcast_hierarchical(hierarchy_id, message, opts \\ []) do
    level = Keyword.get(opts, :level, :all)

    agents =
      case level do
        :all -> get_all_hierarchy_agents(hierarchy_id)
        :leads -> get_hierarchy_leads(hierarchy_id)
        :members -> get_hierarchy_members(hierarchy_id)
      end

    # Broadcast to selected agents
    Enum.each(agents, fn {_id, pid, _meta} ->
      send(pid, {:hierarchy_broadcast, hierarchy_id, message})
    end)

    :ok
  end

  # Private helper functions

  defp find_eligible_agents(team_id, capability) do
    criteria = [
      {[:team_id], team_id, :eq},
      {[:health_status], :healthy, :eq}
    ]

    criteria =
      if capability do
        [{[:capability], capability, :eq} | criteria]
      else
        criteria
      end

    case Registry.query(Registry, criteria) do
      {:ok, agents} -> agents
      _ -> []
    end
  end

  defp find_available_agents(capability) do
    criteria = [{[:health_status], :healthy, :eq}]

    criteria =
      if capability do
        [{[:capability], capability, :eq} | criteria]
      else
        criteria
      end

    Registry.query(Registry, criteria)
  end

  defp default_leader_criteria({_id, _pid, metadata}) do
    # Simple criteria: prefer agents with more resources
    base_score = 50

    resource_score =
      case metadata[:resources] do
        %{memory_usage: usage} when usage < 0.5 -> 30
        %{memory_usage: usage} when usage < 0.8 -> 20
        _ -> 10
      end

    uptime_score =
      case metadata[:registered_at] do
        %DateTime{} = time ->
          # Prefer agents that have been running longer
          minutes = DateTime.diff(DateTime.utc_now(), time, :second) / 60
          min(minutes, 20)

        _ ->
          0
      end

    base_score + resource_score + uptime_score
  end

  defp collect_votes(agents, candidates, criteria_fn, _timeout) do
    # Simulate agent voting (in real implementation, agents would evaluate)
    Enum.map(agents, fn {id, _pid, _meta} ->
      # Each agent evaluates all candidates
      scores =
        Enum.map(candidates, fn candidate ->
          {elem(candidate, 0), criteria_fn.(candidate)}
        end)

      # Vote for highest scoring candidate
      {winner, _score} = Enum.max_by(scores, fn {_id, score} -> score end)
      {id, winner}
    end)
  end

  defp determine_leader(votes, candidates) do
    # Count votes
    vote_counts =
      Enum.reduce(votes, %{}, fn {_voter, candidate}, acc ->
        Map.update(acc, candidate, 1, &(&1 + 1))
      end)

    # Find candidate with most votes
    {leader_id, _count} = Enum.max_by(vote_counts, fn {_id, count} -> count end)

    # Find full agent info
    Enum.find(candidates, fn {id, _pid, _meta} -> id == leader_id end)
  end

  defp mark_as_leader({id, _pid, _meta} = leader, team_id) do
    Registry.update_metadata(Registry, id, %{
      role: :leader,
      team_id: team_id,
      leader_since: DateTime.utc_now()
    })

    leader
  end

  defp monitor_leader_loop(leader_pid, ref, team_id, interval, opts) do
    receive do
      {:DOWN, ^ref, :process, ^leader_pid, _reason} ->
        Logger.info(
          "Leader #{inspect(leader_pid)} for team #{team_id} died, triggering re-election"
        )

        elect_leader(Keyword.put(opts, :team_id, team_id))
    after
      interval ->
        # Check leader health
        if Process.alive?(leader_pid) do
          monitor_leader_loop(leader_pid, ref, team_id, interval, opts)
        else
          Logger.warning("Leader #{inspect(leader_pid)} unhealthy, triggering re-election")
          elect_leader(Keyword.put(opts, :team_id, team_id))
        end
    end
  end

  defp distribute_round_robin(work_items, agents) do
    work_items
    |> Enum.with_index()
    |> Enum.map(fn {item, idx} ->
      agent = Enum.at(agents, rem(idx, length(agents)))
      {elem(agent, 1), [item]}
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {agent_pid, work_lists} ->
      {agent_pid, List.flatten(work_lists)}
    end)
  end

  defp distribute_least_loaded(work_items, agents) do
    # Get current load for each agent
    agent_loads =
      Enum.map(agents, fn {_id, pid, metadata} ->
        load = get_in(metadata, [:resources, :current_load]) || 0
        {pid, load}
      end)
      |> Enum.sort_by(&elem(&1, 1))

    # Distribute to least loaded agents
    Enum.reduce(work_items, %{}, fn item, acc ->
      # Find least loaded agent
      {agent_pid, _load} = Enum.min_by(agent_loads, &elem(&1, 1))

      Map.update(acc, agent_pid, [item], &(&1 ++ [item]))
    end)
    |> Enum.to_list()
  end

  defp distribute_by_capability(work_items, agents) do
    # Group agents by capability
    agents_by_cap =
      Enum.group_by(agents, fn {_id, _pid, metadata} ->
        metadata[:capability]
      end)

    # Match work to capabilities (simplified - assumes work items have :required_capability)
    Enum.reduce(work_items, %{}, fn item, acc ->
      required_cap = item[:required_capability] || :any

      suitable_agents = agents_by_cap[required_cap] || agents
      agent = Enum.random(suitable_agents)
      agent_pid = elem(agent, 1)

      Map.update(acc, agent_pid, [item], &(&1 ++ [item]))
    end)
    |> Enum.to_list()
  end

  defp distribute_random(work_items, agents) do
    Enum.reduce(work_items, %{}, fn item, acc ->
      {_id, pid, _meta} = Enum.random(agents)
      Map.update(acc, pid, [item], &(&1 ++ [item]))
    end)
    |> Enum.to_list()
  end

  defp execute_agent_work(agent_pid, work_items, operation_fn, timeout) do
    GenServer.call(agent_pid, {:execute_work, work_items, operation_fn}, timeout)
  catch
    :exit, reason -> {:error, {:agent_error, reason}}
  end

  defp collect_agent_votes(agents, proposal, consensus_ref) do
    Enum.map(agents, fn {id, pid, _meta} ->
      # In real implementation, agent would evaluate proposal
      vote = evaluate_proposal(pid, proposal)
      :ok = Coordination.vote(Coordination, consensus_ref, id, vote)
      {id, vote}
    end)
  end

  defp evaluate_proposal(_pid, _proposal) do
    # Simplified - randomly approve or reject
    if :rand.uniform() > 0.3, do: :approve, else: :reject
  end

  defp check_majority(votes, total) do
    approvals = Enum.count(votes, fn {_id, vote} -> vote == :approve end)

    if approvals > total / 2 do
      {:ok, :consensus_reached}
    else
      {:error, :no_consensus}
    end
  end

  defp check_unanimous(votes, total) do
    approvals = Enum.count(votes, fn {_id, vote} -> vote == :approve end)

    if approvals == total do
      {:ok, :consensus_reached}
    else
      {:error, :no_consensus}
    end
  end

  defp check_quorum(votes, required) do
    approvals = Enum.count(votes, fn {_id, vote} -> vote == :approve end)

    if approvals >= required do
      {:ok, :consensus_reached}
    else
      {:error, :no_consensus}
    end
  end

  defp notify_agents(agents, result) do
    Enum.each(agents, fn {_id, pid, _meta} ->
      send(pid, {:consensus_result, result})
    end)
  end

  defp monitor_barrier(barrier_id, _expected_count, timeout) do
    # Monitor barrier completion
    Process.sleep(timeout)

    # Check if barrier completed
    # In real implementation, would check actual barrier state
    Logger.info("Barrier #{barrier_id} monitoring completed")
  end

  defp start_pool_manager(pool_id, initial_state) do
    # Simple pool manager (in production, use :poolboy or similar)
    GenServer.start_link(__MODULE__.PoolManager, {pool_id, initial_state},
      name: {:via, Registry, {Foundation.Registry, pool_id}}
    )
  end

  defp tag_agent_role(agent_pid, role, hierarchy_id) do
    case Registry.lookup(Registry, agent_pid) do
      {:ok, {^agent_pid, metadata}} ->
        Registry.update_metadata(
          Registry,
          agent_pid,
          Map.merge(metadata, %{
            hierarchy_role: role,
            hierarchy_id: hierarchy_id
          })
        )

      _ ->
        {:error, :agent_not_found}
    end
  end

  defp setup_hierarchy_channels(_supervisor, _teams, hierarchy_id) do
    # Setup communication subscriptions
    # In real implementation, would use PubSub or similar
    Logger.info("Set up hierarchy channels for #{hierarchy_id}")
  end

  defp generate_hierarchy_id do
    "hierarchy_#{System.unique_integer([:positive, :monotonic])}"
  end

  defp get_all_hierarchy_agents(hierarchy_id) do
    {:ok, agents} =
      Registry.query(Registry, [
        {[:hierarchy_id], hierarchy_id, :eq}
      ])

    agents
  end

  defp get_hierarchy_leads(hierarchy_id) do
    {:ok, agents} =
      Registry.query(Registry, [
        {[:hierarchy_id], hierarchy_id, :eq},
        {[:hierarchy_role], :team_lead, :eq}
      ])

    agents
  end

  defp get_hierarchy_members(hierarchy_id) do
    {:ok, agents} =
      Registry.query(Registry, [
        {[:hierarchy_id], hierarchy_id, :eq},
        {[:hierarchy_role], :team_member, :eq}
      ])

    agents
  end
end

# Simple pool manager for resource pooling
defmodule MABEAM.CoordinationPatterns.PoolManager do
  @moduledoc """
  Manager for agent pools in coordination patterns.
  Handles pool lifecycle and resource allocation.
  """
  use GenServer

  def init({_pool_id, initial_state}) do
    {:ok, initial_state}
  end

  def handle_call({:checkout, agent_id}, _from, state) do
    case state.available do
      [] ->
        {:reply, {:error, :no_resources_available}, state}

      [resource | rest] ->
        new_state = %{
          state
          | available: rest,
            checked_out: Map.put(state.checked_out, agent_id, resource)
        }

        {:reply, {:ok, resource}, new_state}
    end
  end

  def handle_cast({:checkin, agent_id, resource}, state) do
    case Map.get(state.checked_out, agent_id) do
      ^resource ->
        new_state = %{
          state
          | available: [resource | state.available],
            checked_out: Map.delete(state.checked_out, agent_id)
        }

        {:noreply, new_state}

      _ ->
        {:noreply, state}
    end
  end
end
