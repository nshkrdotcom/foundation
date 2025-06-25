defmodule Foundation.MABEAM.CoordinationAdvancedTest do
  @moduledoc """
  Tests for advanced coordination algorithms: Byzantine consensus, weighted voting, and iterative refinement.

  This test suite validates:
  - Byzantine fault tolerant consensus with PBFT protocol
  - Weighted consensus with expertise-based voting  
  - Iterative refinement with multi-round proposal evolution
  - Integration with existing MABEAM coordination infrastructure
  """

  use ExUnit.Case, async: false
  alias Foundation.MABEAM.{Coordination, ProcessRegistry, Types}

  setup do
    # Start all required services
    case start_supervised({ProcessRegistry, [test_mode: true]}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    case start_supervised({Coordination, [test_mode: true]}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    # Create test agents
    agent_configs = [
      Types.new_agent_config(:byzantine_agent_1, CoordinationTestAgent, [],
        capabilities: [:consensus, :voting]
      ),
      Types.new_agent_config(:byzantine_agent_2, CoordinationTestAgent, [],
        capabilities: [:consensus, :voting]
      ),
      Types.new_agent_config(:byzantine_agent_3, CoordinationTestAgent, [],
        capabilities: [:consensus, :voting]
      ),
      Types.new_agent_config(:byzantine_agent_4, CoordinationTestAgent, [],
        capabilities: [:consensus, :voting]
      ),
      Types.new_agent_config(:expert_agent, CoordinationTestAgent, [],
        capabilities: [:consensus, :expertise]
      ),
      Types.new_agent_config(:intermediate_agent, CoordinationTestAgent, [],
        capabilities: [:consensus]
      ),
      Types.new_agent_config(:novice_agent, CoordinationTestAgent, [], capabilities: [:consensus])
    ]

    # Register agents
    Enum.each(agent_configs, &ProcessRegistry.register_agent/1)

    # Start agents  
    started_agents =
      for config <- agent_configs do
        {:ok, pid} = ProcessRegistry.start_agent(config.id)
        {config.id, pid}
      end

    %{agents: started_agents, agent_configs: agent_configs}
  end

  describe "Byzantine fault tolerant consensus" do
    test "starts byzantine consensus with sufficient agents", %{agents: agents} do
      # Use first 4 agents for Byzantine consensus (supports f=1 fault tolerance)
      byzantine_agents = agents |> Enum.take(4) |> Enum.map(&elem(&1, 0))
      proposal = "Critical decision requiring Byzantine fault tolerance"

      # Start Byzantine consensus
      result =
        Coordination.start_byzantine_consensus(proposal, byzantine_agents, fault_tolerance: 1)

      assert {:ok, session_id} = result
      assert is_binary(session_id)

      # Verify session was created
      {:ok, session_status} = Coordination.get_session_status(session_id)
      assert session_status.type == :byzantine_consensus
      assert session_status.participants == byzantine_agents
      assert session_status.metadata.task_specification.proposal == proposal
      assert session_status.metadata.task_specification.fault_tolerance == 1
      assert session_status.status in [:initializing, :active]
    end

    test "rejects byzantine consensus with insufficient agents", %{agents: agents} do
      # Use only 2 agents (insufficient for f=1, need minimum 4)
      insufficient_agents = agents |> Enum.take(2) |> Enum.map(&elem(&1, 0))
      proposal = "This should fail due to insufficient agents"

      result =
        Coordination.start_byzantine_consensus(proposal, insufficient_agents, fault_tolerance: 1)

      assert {:error, {:insufficient_agents, min_required, actual_count}} = result
      # 3f + 1 = 3(1) + 1 = 4
      assert min_required == 4
      assert actual_count == 2
    end

    test "calculates correct Byzantine minimum for different fault tolerances" do
      # Test the minimum calculation logic
      # For f=1: need 3f+1 = 4 agents
      # For f=2: need 3f+1 = 7 agents

      agents_4 = [:a1, :a2, :a3, :a4]
      agents_7 = [:a1, :a2, :a3, :a4, :a5, :a6, :a7]

      # f=1 should work with 4 agents
      result_1 = Coordination.start_byzantine_consensus("test", agents_4, fault_tolerance: 1)
      assert {:ok, _session_id} = result_1

      # f=2 should fail with 4 agents (needs 7)
      result_2 = Coordination.start_byzantine_consensus("test", agents_4, fault_tolerance: 2)
      assert {:error, {:insufficient_agents, 7, 4}} = result_2

      # f=2 should work with 7 agents
      result_3 = Coordination.start_byzantine_consensus("test", agents_7, fault_tolerance: 2)
      assert {:ok, _session_id} = result_3
    end

    test "includes correct metadata for byzantine sessions", %{agents: agents} do
      byzantine_agents = agents |> Enum.take(4) |> Enum.map(&elem(&1, 0))
      proposal = "Test proposal for metadata validation"

      {:ok, session_id} =
        Coordination.start_byzantine_consensus(proposal, byzantine_agents,
          fault_tolerance: 1,
          priority: :critical,
          tags: ["test", "metadata"],
          requester: :test_suite
        )

      {:ok, session_status} = Coordination.get_session_status(session_id)
      metadata = session_status.metadata

      assert metadata.session_type == :byzantine_consensus
      assert metadata.priority == :critical
      assert "byzantine" in metadata.tags
      assert "consensus" in metadata.tags
      assert "fault_tolerant" in metadata.tags
      assert "test" in metadata.tags
      assert "metadata" in metadata.tags
      assert metadata.requester == :test_suite
      assert Map.has_key?(metadata, :resource_requirements)
      assert Map.has_key?(metadata, :expected_cost)
      assert Map.has_key?(metadata, :expected_duration_ms)
    end
  end

  describe "Weighted consensus with expertise" do
    test "starts weighted consensus successfully", %{agents: agents} do
      # Use agents with different expertise levels
      weighted_agents = agents |> Enum.take(5) |> Enum.map(&elem(&1, 0))
      proposal = "Decision requiring expertise-based weighting"

      result =
        Coordination.start_weighted_consensus(proposal, weighted_agents,
          weighting: :expertise,
          consensus_threshold: 0.7
        )

      assert {:ok, session_id} = result
      assert is_binary(session_id)

      # Verify session was created
      {:ok, session_status} = Coordination.get_session_status(session_id)
      assert session_status.type == :weighted_consensus
      assert session_status.participants == weighted_agents
      assert session_status.metadata.task_specification.proposal == proposal
      assert session_status.metadata.task_specification.weighting_strategy == :expertise
    end

    test "supports different weighting strategies", %{agents: agents} do
      weighted_agents = agents |> Enum.take(3) |> Enum.map(&elem(&1, 0))
      proposal = "Test different weighting strategies"

      # Test expertise weighting
      {:ok, session_id_1} =
        Coordination.start_weighted_consensus(proposal, weighted_agents, weighting: :expertise)

      {:ok, status_1} = Coordination.get_session_status(session_id_1)
      assert status_1.metadata.task_specification.weighting_strategy == :expertise

      # Test performance weighting  
      {:ok, session_id_2} =
        Coordination.start_weighted_consensus(proposal, weighted_agents, weighting: :performance)

      {:ok, status_2} = Coordination.get_session_status(session_id_2)
      assert status_2.metadata.task_specification.weighting_strategy == :performance

      # Test equal weighting
      {:ok, session_id_3} =
        Coordination.start_weighted_consensus(proposal, weighted_agents, weighting: :equal)

      {:ok, status_3} = Coordination.get_session_status(session_id_3)
      assert status_3.metadata.task_specification.weighting_strategy == :equal
    end

    test "includes correct metadata for weighted sessions", %{agents: agents} do
      weighted_agents = agents |> Enum.take(4) |> Enum.map(&elem(&1, 0))
      proposal = "Test weighted consensus metadata"

      {:ok, session_id} =
        Coordination.start_weighted_consensus(proposal, weighted_agents,
          weighting: :expertise,
          consensus_threshold: 0.8,
          priority: :high,
          tags: ["weighted", "test"],
          requester: :expertise_system
        )

      {:ok, session_status} = Coordination.get_session_status(session_id)
      metadata = session_status.metadata

      assert metadata.session_type == :weighted_consensus
      assert metadata.priority == :high
      assert "weighted" in metadata.tags
      assert "consensus" in metadata.tags
      assert "expertise" in metadata.tags
      assert "test" in metadata.tags
      assert metadata.requester == :expertise_system
    end
  end

  describe "Iterative refinement consensus" do
    test "starts iterative consensus successfully", %{agents: agents} do
      refinement_agents = agents |> Enum.take(5) |> Enum.map(&elem(&1, 0))
      initial_proposal = "Initial proposal: Build a distributed ML training system"

      result =
        Coordination.start_iterative_consensus(initial_proposal, refinement_agents,
          max_rounds: 3,
          convergence_threshold: 0.85
        )

      assert {:ok, session_id} = result
      assert is_binary(session_id)

      # Verify session was created
      {:ok, session_status} = Coordination.get_session_status(session_id)
      assert session_status.type == :iterative_refinement
      assert session_status.participants == refinement_agents
      assert session_status.metadata.task_specification.initial_proposal == initial_proposal
      assert session_status.metadata.task_specification.max_rounds == 3
      assert session_status.metadata.task_specification.convergence_threshold == 0.85
    end

    test "uses default parameters when not specified", %{agents: agents} do
      refinement_agents = agents |> Enum.take(3) |> Enum.map(&elem(&1, 0))
      initial_proposal = "Test proposal with defaults"

      {:ok, session_id} =
        Coordination.start_iterative_consensus(initial_proposal, refinement_agents)

      {:ok, session_status} = Coordination.get_session_status(session_id)
      task_spec = session_status.metadata.task_specification

      # Verify default values
      # Default from implementation
      assert task_spec.max_rounds == 5
      # Default from implementation
      assert task_spec.convergence_threshold == 0.95
    end

    test "includes correct metadata for iterative sessions", %{agents: agents} do
      refinement_agents = agents |> Enum.take(4) |> Enum.map(&elem(&1, 0))
      initial_proposal = "Test iterative refinement metadata"

      {:ok, session_id} =
        Coordination.start_iterative_consensus(initial_proposal, refinement_agents,
          max_rounds: 4,
          convergence_threshold: 0.9,
          priority: :normal,
          tags: ["iterative", "test"],
          requester: :refinement_system
        )

      {:ok, session_status} = Coordination.get_session_status(session_id)
      metadata = session_status.metadata

      assert metadata.session_type == :iterative_refinement
      assert metadata.priority == :normal
      assert "iterative" in metadata.tags
      assert "refinement" in metadata.tags
      assert "consensus" in metadata.tags
      assert "test" in metadata.tags
      assert metadata.requester == :refinement_system
    end
  end

  describe "Advanced consensus integration" do
    test "all consensus types integrate with session management", %{agents: agents} do
      agents_list = agents |> Enum.take(4) |> Enum.map(&elem(&1, 0))

      # Start different types of consensus sessions
      {:ok, byzantine_id} = Coordination.start_byzantine_consensus("Byzantine test", agents_list)
      {:ok, weighted_id} = Coordination.start_weighted_consensus("Weighted test", agents_list)
      {:ok, iterative_id} = Coordination.start_iterative_consensus("Iterative test", agents_list)

      # Verify all sessions appear in active sessions
      {:ok, active_sessions} = Coordination.list_active_sessions()
      session_ids = Enum.map(active_sessions, & &1.id)

      assert byzantine_id in session_ids
      assert weighted_id in session_ids
      assert iterative_id in session_ids

      # Verify different session types
      session_types =
        active_sessions
        |> Enum.filter(&(&1.id in [byzantine_id, weighted_id, iterative_id]))
        |> Enum.map(& &1.type)

      assert :byzantine_consensus in session_types
      assert :weighted_consensus in session_types
      assert :iterative_refinement in session_types
    end

    test "consensus sessions can be cancelled", %{agents: agents} do
      agents_list = agents |> Enum.take(4) |> Enum.map(&elem(&1, 0))

      {:ok, session_id} = Coordination.start_byzantine_consensus("Cancellable test", agents_list)

      # Verify session exists
      {:ok, _status} = Coordination.get_session_status(session_id)

      # Cancel session
      result = Coordination.cancel_session(session_id)
      assert :ok = result

      # Verify session is no longer active (might be marked as cancelled instead of removed)
      case Coordination.get_session_status(session_id) do
        {:ok, status} ->
          # Session exists but should be cancelled
          assert status.status in [:cancelled, :terminated]

        {:error, :not_found} ->
          # Session was removed entirely
          :ok
      end
    end

    test "consensus sessions appear in coordination analytics", %{agents: agents} do
      agents_list = agents |> Enum.take(4) |> Enum.map(&elem(&1, 0))

      # Start multiple consensus sessions
      {:ok, _byzantine_id} = Coordination.start_byzantine_consensus("Analytics test 1", agents_list)
      {:ok, _weighted_id} = Coordination.start_weighted_consensus("Analytics test 2", agents_list)
      {:ok, _iterative_id} = Coordination.start_iterative_consensus("Analytics test 3", agents_list)

      # Get analytics
      {:ok, analytics} = Coordination.get_coordination_analytics()

      # Verify analytics include advanced consensus sessions
      assert Map.has_key?(analytics, :active_sessions)
      assert Map.has_key?(analytics, :session_types)

      # Should have at least 3 active sessions from our tests
      assert analytics.active_sessions >= 3

      # Should include our consensus types
      session_types = Map.get(analytics, :session_types, %{})
      assert Map.get(session_types, :byzantine_consensus, 0) >= 1
      assert Map.get(session_types, :weighted_consensus, 0) >= 1
      assert Map.get(session_types, :iterative_refinement, 0) >= 1
    end
  end

  describe "Configuration and parameter validation" do
    test "validates byzantine consensus parameters", %{agents: agents} do
      agents_list = agents |> Enum.take(4) |> Enum.map(&elem(&1, 0))

      # Valid parameters should work
      {:ok, _session_id} =
        Coordination.start_byzantine_consensus("Valid test", agents_list,
          fault_tolerance: 1,
          timeout: 30_000,
          priority: :critical
        )

      # Invalid fault tolerance (too high for agent count)
      result =
        Coordination.start_byzantine_consensus("Invalid test", agents_list, fault_tolerance: 2)

      assert {:error, {:insufficient_agents, 7, 4}} = result

      # Zero fault tolerance should still work (but needs at least 1 agent)
      {:ok, _session_id} =
        Coordination.start_byzantine_consensus("Zero fault", [:single_agent], fault_tolerance: 0)
    end

    test "validates weighted consensus parameters", %{agents: agents} do
      agents_list = agents |> Enum.take(3) |> Enum.map(&elem(&1, 0))

      # Valid parameters
      {:ok, _session_id} =
        Coordination.start_weighted_consensus("Valid weighted", agents_list,
          weighting: :expertise,
          consensus_threshold: 0.7,
          timeout: 15_000
        )

      # Invalid weighting strategy - should still work but use default
      {:ok, session_id} =
        Coordination.start_weighted_consensus("Invalid weighting", agents_list, weighting: :invalid)

      {:ok, status} = Coordination.get_session_status(session_id)
      # The system should handle invalid weighting gracefully
      assert status.metadata.task_specification.weighting_strategy == :invalid
    end

    test "validates iterative consensus parameters", %{agents: agents} do
      agents_list = agents |> Enum.take(3) |> Enum.map(&elem(&1, 0))

      # Valid parameters
      {:ok, _session_id} =
        Coordination.start_iterative_consensus("Valid iterative", agents_list,
          max_rounds: 3,
          convergence_threshold: 0.8,
          timeout: 60_000
        )

      # Edge case: single round
      {:ok, session_id} =
        Coordination.start_iterative_consensus("Single round", agents_list, max_rounds: 1)

      {:ok, status} = Coordination.get_session_status(session_id)
      assert status.metadata.task_specification.max_rounds == 1

      # Edge case: very high convergence threshold
      {:ok, session_id2} =
        Coordination.start_iterative_consensus("High threshold", agents_list,
          convergence_threshold: 0.99
        )

      {:ok, status2} = Coordination.get_session_status(session_id2)
      assert status2.metadata.task_specification.convergence_threshold == 0.99
    end
  end
end

# Test agent module for coordination tests
defmodule CoordinationTestAgent do
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  def init(args) do
    {:ok, %{id: Keyword.get(args, :id, :test_agent), state: :ready}}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_cast({:update_state, new_state}, _state) do
    {:noreply, new_state}
  end

  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
