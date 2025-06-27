# Byzantine Consensus & Advanced Coordination - Technical Implementation Specification

## Executive Summary

This document provides the comprehensive technical specification for implementing the event handlers in Foundation MABEAM's advanced coordination algorithms. The current implementation has complete API structures but placeholder event handlers that need full Byzantine PBFT, weighted voting, and iterative refinement logic.

## Current Implementation Status

### ✅ What's Complete
- **API Layer**: All function signatures (`start_byzantine_consensus/3`, `start_weighted_consensus/3`, `start_iterative_consensus/3`)
- **Session Management**: Initialization, configuration validation, session lifecycle
- **Type System**: Proper type specifications and integration with Foundation services
- **Infrastructure**: Process supervision, telemetry emission, error handling

### ❌ What's Missing - Event Handler Logic
```elixir
# Current placeholders in /lib/foundation/mabeam/coordination.ex
defp handle_byzantine_event(session, _event_type, _event_data, state) do
  # TODO: Implement Byzantine consensus event handling
  {:ok, session, state}
end

defp handle_weighted_event(session, _event_type, _event_data, state) do
  # TODO: Implement weighted consensus event handling
  {:ok, session, state}
end

defp handle_iterative_event(session, _event_type, _event_data, state) do
  # TODO: Implement iterative consensus event handling
  {:ok, session, state}
end
```

## Part 1: Byzantine Fault Tolerant (PBFT) Consensus Implementation

### 1.1 Technical Requirements

**Core PBFT Algorithm Components:**
- **Three-Phase Protocol**: Pre-prepare, Prepare, Commit
- **View Changes**: Leader failure detection and new leader election
- **Message Authentication**: Ensure message integrity and authenticity
- **Fault Tolerance**: Handle up to `f = (n-1)/3` Byzantine failures
- **Safety**: Never commit conflicting values
- **Liveness**: Eventually make progress under favorable conditions

**Performance Requirements:**
- Support 4-100 agents (minimum 4 for `f=1` fault tolerance)
- Sub-second consensus for simple proposals
- Memory-efficient message storage with cleanup
- Graceful handling of network partitions

### 1.2 State Structure Design

```elixir
# Enhanced byzantine_state for session.state
%{
  # PBFT Core State
  view_number: non_neg_integer(),           # Current view number
  sequence_number: non_neg_integer(),       # Current sequence number
  primary: agent_id(),                      # Current primary agent
  phase: :pre_prepare | :prepare | :commit | :decided | :view_change,
  
  # Current Proposal Processing
  current_proposal: term(),                 # Proposal being processed
  proposal_digest: binary(),                # Hash of current proposal
  
  # Message Storage
  pre_prepare_messages: %{sequence_number() => message()},
  prepare_messages: %{agent_id() => %{sequence_number() => message()}},
  commit_messages: %{agent_id() => %{sequence_number() => message()}},
  view_change_messages: %{agent_id() => message()},
  new_view_messages: %{agent_id() => message()},
  
  # Fault Tolerance Configuration
  n: pos_integer(),                         # Total number of agents
  f: non_neg_integer(),                     # Maximum Byzantine failures
  commit_threshold: pos_integer(),          # 2f + 1 threshold
  
  # Timing and Timeouts
  view_change_timeout: pos_integer(),       # Timeout for view changes
  last_activity: DateTime.t(),              # Track liveness
  
  # Decision State
  decided_value: term() | nil,              # Final decided value
  decision_proof: [message()] | nil,        # Proof of decision
  
  # Agent Management
  participants: [agent_id()],               # All participating agents
  suspected_faulty: MapSet.t(agent_id()),   # Agents suspected of Byzantine behavior
  
  # Message Authentication
  message_log: [message()],                 # Complete message history
  authenticated_agents: MapSet.t(agent_id()) # Agents with valid authentication
}
```

### 1.3 Message Format Specification

```elixir
@type pbft_message :: %{
  type: :pre_prepare | :prepare | :commit | :view_change | :new_view,
  view: non_neg_integer(),
  sequence: non_neg_integer(),
  agent_id: agent_id(),
  proposal: term(),
  proposal_digest: binary(),
  timestamp: DateTime.t(),
  signature: binary() | nil,  # For authentication
  # Type-specific fields
  committed_proposals: [proposal()] | nil,  # For view-change messages
  view_change_set: [message()] | nil        # For new-view messages
}
```

### 1.4 Event Handler Implementation Plan

#### Phase 1: Core PBFT Message Processing

**File**: `/lib/foundation/mabeam/coordination.ex`

```elixir
defp handle_byzantine_event(session, event_type, event_data, state) do
  case event_type do
    :pre_prepare -> handle_pbft_pre_prepare(session, event_data, state)
    :prepare -> handle_pbft_prepare(session, event_data, state)
    :commit -> handle_pbft_commit(session, event_data, state)
    :view_change -> handle_pbft_view_change(session, event_data, state)
    :new_view -> handle_pbft_new_view(session, event_data, state)
    :timeout -> handle_pbft_timeout(session, event_data, state)
    :proposal_submission -> handle_pbft_proposal_submission(session, event_data, state)
    _ -> {:error, {:unknown_byzantine_event, event_type}}
  end
end
```

#### Phase 2: Individual Event Handlers

**Pre-Prepare Phase Implementation:**
```elixir
defp handle_pbft_pre_prepare(session, event_data, state) do
  byzantine_state = session.state
  message = event_data[:message]
  
  # Validate pre-prepare message
  case validate_pre_prepare_message(message, byzantine_state) do
    {:ok, validated_message} ->
      # Store pre-prepare message
      updated_pre_prepares = Map.put(
        byzantine_state.pre_prepare_messages,
        validated_message.sequence,
        validated_message
      )
      
      # Broadcast prepare message to all agents
      prepare_message = create_prepare_message(validated_message, session)
      broadcast_message(prepare_message, byzantine_state.participants)
      
      # Update session state
      updated_byzantine_state = %{
        byzantine_state 
        | phase: :prepare,
          current_proposal: validated_message.proposal,
          proposal_digest: validated_message.proposal_digest,
          pre_prepare_messages: updated_pre_prepares,
          sequence_number: validated_message.sequence,
          last_activity: DateTime.utc_now()
      }
      
      updated_session = %{session | state: updated_byzantine_state}
      {:ok, updated_session, state}
      
    {:error, reason} ->
      Logger.warning("Invalid pre-prepare message: #{inspect(reason)}")
      # Possibly trigger view change if primary is sending invalid messages
      handle_byzantine_fault_detection(session, state, :invalid_pre_prepare)
  end
end
```

**Prepare Phase Implementation:**
```elixir
defp handle_pbft_prepare(session, event_data, state) do
  byzantine_state = session.state
  message = event_data[:message]
  
  # Validate prepare message
  case validate_prepare_message(message, byzantine_state) do
    {:ok, validated_message} ->
      # Store prepare message
      agent_prepares = Map.get(byzantine_state.prepare_messages, message.agent_id, %{})
      updated_agent_prepares = Map.put(agent_prepares, message.sequence, validated_message)
      updated_prepare_messages = Map.put(
        byzantine_state.prepare_messages,
        message.agent_id,
        updated_agent_prepares
      )
      
      # Check if we have enough prepare messages (2f + 1)
      prepare_count = count_matching_prepares(
        updated_prepare_messages,
        message.sequence,
        message.proposal_digest
      )
      
      if prepare_count >= byzantine_state.commit_threshold do
        # Move to commit phase
        commit_message = create_commit_message(validated_message, session)
        broadcast_message(commit_message, byzantine_state.participants)
        
        updated_byzantine_state = %{
          byzantine_state
          | phase: :commit,
            prepare_messages: updated_prepare_messages,
            last_activity: DateTime.utc_now()
        }
      else
        # Still collecting prepare messages
        updated_byzantine_state = %{
          byzantine_state
          | prepare_messages: updated_prepare_messages,
            last_activity: DateTime.utc_now()
        }
      end
      
      updated_session = %{session | state: updated_byzantine_state}
      {:ok, updated_session, state}
      
    {:error, reason} ->
      Logger.warning("Invalid prepare message: #{inspect(reason)}")
      {:ok, session, state}
  end
end
```

### 1.5 Test-Driven Development Plan

#### Layer 1: Unit Tests for Message Validation
**File**: `/test/foundation/mabeam/pbft_message_validation_test.exs`

```elixir
defmodule Foundation.MABEAM.PBFTMessageValidationTest do
  use ExUnit.Case
  
  describe "validate_pre_prepare_message/2" do
    test "accepts valid pre-prepare from primary" do
      # Test valid pre-prepare message structure
    end
    
    test "rejects pre-prepare from non-primary" do
      # Test rejection of pre-prepare from backup agents
    end
    
    test "rejects pre-prepare with invalid sequence number" do
      # Test sequence number validation
    end
    
    test "rejects pre-prepare with malformed proposal" do
      # Test proposal format validation
    end
  end
  
  describe "validate_prepare_message/2" do
    # Similar comprehensive validation tests for prepare messages
  end
  
  describe "validate_commit_message/2" do
    # Commit message validation tests
  end
end
```

#### Layer 2: Integration Tests for PBFT Phases
**File**: `/test/foundation/mabeam/pbft_consensus_test.exs`

```elixir
defmodule Foundation.MABEAM.PBFTConsensusTest do
  use ExUnit.Case, async: false
  
  describe "Byzantine consensus happy path" do
    test "4 agents reach consensus with honest primary" do
      # Test complete PBFT execution with 4 agents, f=1
    end
    
    test "7 agents reach consensus with honest primary" do
      # Test scaling with 7 agents, f=2
    end
  end
  
  describe "Byzantine fault scenarios" do
    test "consensus despite silent primary failure" do
      # Test view change when primary stops responding
    end
    
    test "consensus despite Byzantine primary" do
      # Test view change when primary sends conflicting messages
    end
    
    test "handles up to f Byzantine agents" do
      # Test maximum fault tolerance
    end
  end
  
  describe "Performance and edge cases" do
    test "handles concurrent proposals" do
      # Test sequence number management
    end
    
    test "cleans up old messages" do
      # Test memory management
    end
  end
end
```

#### Layer 3: Property-Based Testing
**File**: `/test/foundation/mabeam/pbft_properties_test.exs`

```elixir
defmodule Foundation.MABEAM.PBFTPropertiesTest do
  use ExUnit.Case
  use StreamData
  
  property "PBFT safety: never commits conflicting values" do
    # Property test ensuring safety under all conditions
  end
  
  property "PBFT liveness: eventually makes progress" do
    # Property test for liveness guarantees
  end
  
  property "Byzantine threshold: tolerates up to f failures" do
    # Property test for fault tolerance limits
  end
end
```

## Part 2: Weighted Voting with Expertise Scoring

### 2.1 Technical Requirements

**Weighted Voting Components:**
- **Dynamic Weight Calculation**: Real-time expertise assessment
- **Multi-Criteria Scoring**: Accuracy, consistency, domain knowledge, past performance
- **Adaptive Learning**: Weight adjustment based on recent performance
- **Early Consensus Detection**: Stop voting when threshold reached
- **Reputation System**: Long-term agent performance tracking

**Performance Requirements:**
- Support 1-50 agents with different expertise levels
- Sub-100ms weight recalculation
- Persistent expertise scores across sessions
- Fair weight distribution (no single agent >50% unless warranted)

### 2.2 State Structure Design

```elixir
# Enhanced weighted_state for session.state
%{
  # Voting Configuration
  proposal: term(),                         # The proposal being voted on
  consensus_threshold: float(),             # e.g., 0.6 for 60% weighted agreement
  voting_deadline: DateTime.t(),            # When voting closes
  
  # Agent Weights and Expertise
  agent_weights: %{agent_id() => float()}, # Current weight for each agent
  baseline_weights: %{agent_id() => float()}, # Starting weights
  expertise_history: %{agent_id() => [expertise_metric()]},
  weight_adjustments: %{agent_id() => [weight_adjustment()]},
  
  # Vote Collection
  votes: %{agent_id() => vote_data()},      # Collected votes with metadata
  weighted_total: float(),                  # Running weighted vote total
  max_possible_weight: float(),             # Sum of all agent weights
  
  # Consensus State
  consensus_reached: boolean(),             # Whether threshold met
  final_decision: term() | nil,             # Final weighted decision
  confidence_score: float(),                # Confidence in the decision
  
  # Dynamic Assessment
  real_time_metrics: %{agent_id() => current_performance()},
  assessment_strategy: :static | :dynamic | :adaptive,
  last_weight_update: DateTime.t(),
  
  # Fairness and Validation
  weight_distribution_stats: %{            # Track weight concentration
    gini_coefficient: float(),             # Measure of inequality
    max_individual_weight: float(),        # Highest single agent weight
    weight_entropy: float()                # Diversity of weights
  }
}

@type vote_data :: %{
  vote: term(),                            # The actual vote value
  weight: float(),                         # Agent's weight at vote time
  confidence: float(),                     # Agent's confidence in their vote
  reasoning: String.t() | nil,             # Optional reasoning
  timestamp: DateTime.t(),                 # When vote was cast
  weighted_value: float()                  # weight * confidence * vote_numeric_value
}

@type expertise_metric :: %{
  accuracy: float(),                       # Historical accuracy rate
  consistency: float(),                    # Consistency of responses
  domain_knowledge: float(),               # Domain-specific expertise
  past_performance: float(),               # Overall past performance
  recency_weight: float(),                 # How recent this data is
  measured_at: DateTime.t()
}
```

### 2.3 Event Handler Implementation Plan

```elixir
defp handle_weighted_event(session, event_type, event_data, state) do
  case event_type do
    :vote_submission -> handle_weighted_vote_submission(session, event_data, state)
    :weight_update_request -> handle_weight_update_request(session, event_data, state)
    :expertise_assessment -> handle_expertise_assessment(session, event_data, state)
    :consensus_check -> handle_weighted_consensus_check(session, event_data, state)
    :voting_deadline -> handle_weighted_voting_deadline(session, event_data, state)
    :performance_feedback -> handle_performance_feedback(session, event_data, state)
    _ -> {:error, {:unknown_weighted_event, event_type}}
  end
end

defp handle_weighted_vote_submission(session, event_data, state) do
  weighted_state = session.state
  agent_id = event_data[:agent_id]
  vote = event_data[:vote]
  confidence = event_data[:confidence] || 1.0
  reasoning = event_data[:reasoning]
  
  # Get current agent weight
  agent_weight = Map.get(weighted_state.agent_weights, agent_id, 1.0)
  
  # Calculate numeric vote value
  vote_numeric = convert_vote_to_numeric(vote, session.proposal)
  
  # Calculate weighted contribution
  weighted_contribution = agent_weight * confidence * vote_numeric
  
  # Store vote data
  vote_data = %{
    vote: vote,
    weight: agent_weight,
    confidence: confidence,
    reasoning: reasoning,
    timestamp: DateTime.utc_now(),
    weighted_value: weighted_contribution
  }
  
  # Update state
  updated_votes = Map.put(weighted_state.votes, agent_id, vote_data)
  new_weighted_total = weighted_state.weighted_total + weighted_contribution
  
  # Check for early consensus
  consensus_reached = check_early_consensus(
    new_weighted_total,
    weighted_state.max_possible_weight,
    weighted_state.consensus_threshold
  )
  
  updated_weighted_state = %{
    weighted_state
    | votes: updated_votes,
      weighted_total: new_weighted_total,
      consensus_reached: consensus_reached
  }
  
  # If consensus reached, finalize
  if consensus_reached do
    finalize_weighted_consensus(updated_weighted_state, session, state)
  else
    updated_session = %{session | state: updated_weighted_state}
    {:ok, updated_session, state}
  end
end
```

### 2.4 Expertise Scoring Algorithm

```elixir
defp calculate_expertise_weight(agent_id, expertise_metrics, context) do
  base_metrics = %{
    accuracy: get_accuracy_score(agent_id, context),
    consistency: get_consistency_score(agent_id, context),
    domain_knowledge: get_domain_knowledge_score(agent_id, context),
    past_performance: get_past_performance_score(agent_id)
  }
  
  # Weight the different factors based on context
  factor_weights = get_factor_weights(context)
  
  # Calculate weighted score
  raw_score = 
    base_metrics.accuracy * factor_weights.accuracy +
    base_metrics.consistency * factor_weights.consistency +
    base_metrics.domain_knowledge * factor_weights.domain_knowledge +
    base_metrics.past_performance * factor_weights.past_performance
  
  # Apply non-linear scaling to emphasize expertise differences
  scaled_score = apply_expertise_scaling(raw_score)
  
  # Ensure reasonable bounds (0.1 to 3.0)
  bounded_score = max(0.1, min(3.0, scaled_score))
  
  # Apply fairness constraints (no single agent >50% of total weight)
  apply_fairness_constraints(bounded_score, agent_id, context)
end

defp apply_expertise_scaling(raw_score) do
  # Use exponential scaling to emphasize high performers
  # while preventing extreme values
  cond do
    raw_score >= 0.8 -> :math.pow(raw_score, 0.7) * 2.0
    raw_score >= 0.6 -> raw_score * 1.5
    raw_score >= 0.4 -> raw_score * 1.2
    true -> raw_score
  end
end
```

## Part 3: Iterative Refinement Protocol

### 3.1 Technical Requirements

**Iterative Refinement Components:**
- **Multi-Round Proposal Evolution**: Proposals improve through feedback
- **Convergence Detection**: Automatic termination when proposals stabilize
- **Quality Assessment**: Scoring mechanism for proposal quality
- **Feedback Integration**: Structured feedback collection and application
- **Similarity Analysis**: Semantic comparison of proposals

**Performance Requirements:**
- Support 3-20 agents in refinement process
- 2-10 refinement rounds typical
- Sub-second proposal similarity calculation
- Memory-efficient proposal history storage

### 3.2 State Structure Design

```elixir
# Enhanced iterative_state for session.state
%{
  # Round Management
  current_round: pos_integer(),             # Current refinement round
  max_rounds: pos_integer(),                # Maximum allowed rounds
  round_timeout: pos_integer(),             # Timeout per round in ms
  
  # Proposal Evolution
  initial_proposal: term(),                 # Starting proposal
  current_proposal: term(),                 # Current best proposal
  proposals_history: [proposal_round()],    # Complete proposal evolution
  round_proposals: %{agent_id() => proposal_submission()},
  
  # Feedback System
  feedback_collection: %{agent_id() => %{target_agent() => feedback_data()}},
  feedback_weights: %{agent_id() => float()}, # Weight for each agent's feedback
  feedback_deadline: DateTime.t(),          # When feedback collection ends
  
  # Convergence Analysis
  convergence_threshold: float(),           # e.g., 0.9 similarity required
  convergence_score: float(),               # Current convergence level
  similarity_history: [float()],           # Track convergence progress
  convergence_method: :jaccard | :semantic | :custom,
  
  # Quality Assessment
  quality_scores: %{proposal_id() => quality_assessment()},
  quality_improvement: float(),             # Improvement per round
  quality_threshold: float(),               # Minimum acceptable quality
  
  # Termination Conditions
  termination_reason: :max_rounds | :convergence | :quality | :consensus | nil,
  early_termination_enabled: boolean(),
  
  # Phase Management
  current_phase: :proposal_collection | :feedback_collection | :analysis | :transition,
  phase_deadline: DateTime.t(),
  
  # Final Results
  final_proposal: term() | nil,
  consensus_level: float(),                 # Agreement on final proposal
  refinement_summary: refinement_summary() | nil
}

@type proposal_round :: %{
  round: pos_integer(),
  proposals: %{agent_id() => proposal_submission()},
  selected_proposal: term(),
  quality_score: float(),
  convergence_score: float(),
  feedback_summary: feedback_summary(),
  timestamp: DateTime.t()
}

@type proposal_submission :: %{
  proposal: term(),
  agent_id: agent_id(),
  confidence: float(),
  reasoning: String.t() | nil,
  based_on: [agent_id()],                   # Which previous proposals influenced this
  timestamp: DateTime.t(),
  estimated_quality: float() | nil
}

@type feedback_data :: %{
  target_proposal: term(),
  quality_score: float(),                   # 0.0 to 1.0
  specific_feedback: [feedback_item()],
  improvement_suggestions: [String.t()],
  overall_assessment: String.t() | nil,
  confidence: float(),
  timestamp: DateTime.t()
}

@type feedback_item :: %{
  aspect: :clarity | :accuracy | :completeness | :feasibility | :innovation,
  score: float(),
  comment: String.t() | nil
}
```

### 3.3 Event Handler Implementation Plan

```elixir
defp handle_iterative_event(session, event_type, event_data, state) do
  case event_type do
    :proposal_submission -> handle_iterative_proposal_submission(session, event_data, state)
    :feedback_submission -> handle_iterative_feedback_submission(session, event_data, state)
    :round_completion -> handle_iterative_round_completion(session, event_data, state)
    :convergence_check -> handle_iterative_convergence_check(session, event_data, state)
    :quality_assessment -> handle_iterative_quality_assessment(session, event_data, state)
    :phase_transition -> handle_iterative_phase_transition(session, event_data, state)
    :early_termination -> handle_iterative_early_termination(session, event_data, state)
    _ -> {:error, {:unknown_iterative_event, event_type}}
  end
end

defp handle_iterative_proposal_submission(session, event_data, state) do
  iterative_state = session.state
  agent_id = event_data[:agent_id]
  proposal = event_data[:proposal]
  confidence = event_data[:confidence] || 0.5
  reasoning = event_data[:reasoning]
  based_on = event_data[:based_on] || []
  
  # Validate submission timing and agent eligibility
  case validate_proposal_submission(agent_id, iterative_state) do
    :ok ->
      # Create proposal submission record
      submission = %{
        proposal: proposal,
        agent_id: agent_id,
        confidence: confidence,
        reasoning: reasoning,
        based_on: based_on,
        timestamp: DateTime.utc_now(),
        estimated_quality: nil  # Will be calculated later
      }
      
      # Store proposal
      updated_round_proposals = Map.put(
        iterative_state.round_proposals,
        agent_id,
        submission
      )
      
      # Check if all agents have submitted
      all_submitted = length(Map.keys(updated_round_proposals)) >= 
                      length(iterative_state.participants)
      
      updated_iterative_state = %{
        iterative_state
        | round_proposals: updated_round_proposals
      }
      
      if all_submitted do
        # Move to feedback collection phase
        transition_to_feedback_phase(updated_iterative_state, session, state)
      else
        updated_session = %{session | state: updated_iterative_state}
        {:ok, updated_session, state}
      end
      
    {:error, reason} ->
      Logger.warning("Invalid proposal submission: #{inspect(reason)}")
      {:ok, session, state}
  end
end

defp handle_iterative_feedback_submission(session, event_data, state) do
  iterative_state = session.state
  from_agent = event_data[:from_agent]
  target_agent = event_data[:target_agent]
  feedback = event_data[:feedback]
  
  # Validate feedback
  case validate_feedback_submission(from_agent, target_agent, feedback, iterative_state) do
    :ok ->
      # Store feedback
      from_agent_feedback = Map.get(iterative_state.feedback_collection, from_agent, %{})
      updated_from_agent_feedback = Map.put(from_agent_feedback, target_agent, feedback)
      updated_feedback_collection = Map.put(
        iterative_state.feedback_collection,
        from_agent,
        updated_from_agent_feedback
      )
      
      # Check if feedback collection is complete
      feedback_complete = check_feedback_completion(
        updated_feedback_collection,
        iterative_state.participants
      )
      
      updated_iterative_state = %{
        iterative_state
        | feedback_collection: updated_feedback_collection
      }
      
      if feedback_complete do
        # Move to analysis phase
        transition_to_analysis_phase(updated_iterative_state, session, state)
      else
        updated_session = %{session | state: updated_iterative_state}
        {:ok, updated_session, state}
      end
      
    {:error, reason} ->
      Logger.warning("Invalid feedback submission: #{inspect(reason)}")
      {:ok, session, state}
  end
end
```

### 3.4 Convergence Detection Algorithm

```elixir
defp calculate_convergence_score(current_proposals, previous_proposals, method) do
  case method do
    :jaccard ->
      calculate_jaccard_similarity(current_proposals, previous_proposals)
    
    :semantic ->
      calculate_semantic_similarity(current_proposals, previous_proposals)
    
    :custom ->
      calculate_custom_similarity(current_proposals, previous_proposals)
  end
end

defp calculate_jaccard_similarity(current_proposals, previous_proposals) do
  # Convert proposals to word sets for Jaccard index calculation
  current_words = extract_word_sets(current_proposals)
  previous_words = extract_word_sets(previous_proposals)
  
  # Calculate pairwise Jaccard similarities
  similarities = for {agent_id, current_set} <- current_words,
                     {^agent_id, previous_set} <- previous_words do
    intersection_size = MapSet.size(MapSet.intersection(current_set, previous_set))
    union_size = MapSet.size(MapSet.union(current_set, previous_set))
    
    if union_size > 0 do
      intersection_size / union_size
    else
      1.0  # Empty sets are considered identical
    end
  end
  
  # Return average similarity
  if length(similarities) > 0 do
    Enum.sum(similarities) / length(similarities)
  else
    0.0
  end
end

defp select_best_proposal(round_proposals, feedback_collection, quality_scores) do
  # Calculate composite scores for each proposal
  proposal_scores = for {agent_id, submission} <- round_proposals do
    # Base quality score
    base_quality = Map.get(quality_scores, agent_id, 0.5)
    
    # Feedback score (average of feedback from other agents)
    feedback_score = calculate_average_feedback_score(agent_id, feedback_collection)
    
    # Confidence score from submitter
    confidence_score = submission.confidence
    
    # Composite score with weights
    composite_score = 
      base_quality * 0.4 +
      feedback_score * 0.4 +
      confidence_score * 0.2
    
    {agent_id, submission.proposal, composite_score}
  end
  
  # Select highest scoring proposal
  case Enum.max_by(proposal_scores, fn {_, _, score} -> score end, fn -> nil end) do
    {best_agent, best_proposal, best_score} ->
      {:ok, best_proposal, best_agent, best_score}
    nil ->
      {:error, :no_proposals}
  end
end
```

## Part 4: Test-Driven Implementation Process

### 4.1 Implementation Phases

**Phase 1: Core Event Handler Structure (Week 1)**
1. Replace TODO placeholders with proper event type dispatching
2. Implement basic message validation functions
3. Add comprehensive error handling and logging
4. Create unit tests for event dispatching

**Phase 2: Byzantine PBFT Implementation (Week 2-3)**
1. Implement pre-prepare, prepare, commit message handlers
2. Add view change and new view protocols
3. Implement fault detection and primary selection
4. Create integration tests for full PBFT scenarios

**Phase 3: Weighted Voting Implementation (Week 3-4)**
1. Implement dynamic weight calculation algorithms
2. Add vote collection and aggregation logic
3. Implement expertise scoring and weight updates
4. Create property-based tests for fairness guarantees

**Phase 4: Iterative Refinement Implementation (Week 4-5)**
1. Implement proposal submission and feedback collection
2. Add convergence detection algorithms
3. Implement proposal selection and quality assessment
4. Create comprehensive scenario tests

**Phase 5: Integration and Performance Testing (Week 5-6)**
1. End-to-end integration tests across all algorithms
2. Performance benchmarking and optimization
3. Stress testing with large agent counts
4. Documentation and examples

### 4.2 Test Strategy

**Unit Tests (Target: 200+ tests)**
- Message validation functions
- State transition logic
- Mathematical calculations (weights, similarities, thresholds)
- Error handling edge cases

**Integration Tests (Target: 50+ tests)**
- Complete algorithm execution scenarios
- Multi-agent coordination workflows
- Fault injection and recovery testing
- Performance under load

**Property-Based Tests (Target: 20+ properties)**
- Byzantine fault tolerance guarantees
- Weighted voting fairness properties
- Iterative refinement convergence properties
- System invariants under all conditions

**Performance Tests (Target: 10+ benchmarks)**
- Consensus time vs. agent count
- Memory usage during long sessions
- Message throughput capacity
- CPU utilization profiling

### 4.3 Success Criteria

**Functional Requirements:**
- [ ] Byzantine consensus handles up to f=(n-1)/3 Byzantine failures
- [ ] Weighted voting produces fair outcomes with expertise consideration
- [ ] Iterative refinement converges to high-quality proposals
- [ ] All algorithms integrate seamlessly with existing MABEAM infrastructure

**Performance Requirements:**
- [ ] Byzantine consensus completes in <5 seconds for 10 agents
- [ ] Weighted voting handles 50 agents with <1 second response time
- [ ] Iterative refinement converges in <10 rounds for typical scenarios
- [ ] Memory usage remains stable during extended operation

**Quality Requirements:**
- [ ] Zero compilation warnings or errors
- [ ] Zero Dialyzer type warnings
- [ ] >95% test coverage on new code
- [ ] All property-based tests pass consistently

## Part 5: Integration with Foundation Services

### 5.1 ProcessRegistry Integration

The event handlers must integrate with Foundation's ProcessRegistry for agent discovery and communication:

```elixir
defp broadcast_message(message, participants) do
  for agent_id <- participants do
    case Foundation.ProcessRegistry.get_agent_status(agent_id) do
      {:ok, %{pid: pid}} when is_pid(pid) ->
        send(pid, {:coordination_message, message})
        
      {:ok, %{node: node, pid: pid}} when node != node() ->
        # Cross-node message sending
        send({pid, node}, {:coordination_message, message})
        
      {:error, :not_found} ->
        Logger.warning("Agent #{agent_id} not found in ProcessRegistry")
        
      error ->
        Logger.error("Failed to send message to #{agent_id}: #{inspect(error)}")
    end
  end
end
```

### 5.2 Telemetry Integration

Comprehensive telemetry emission for monitoring and debugging:

```elixir
defp emit_byzantine_telemetry(event_name, session_id, measurements, metadata \\ %{}) do
  :telemetry.execute(
    [:foundation, :mabeam, :coordination, :byzantine, event_name],
    Map.merge(%{count: 1}, measurements),
    Map.merge(%{session_id: session_id}, metadata)
  )
end

# Example telemetry events:
# [:foundation, :mabeam, :coordination, :byzantine, :pre_prepare_sent]
# [:foundation, :mabeam, :coordination, :byzantine, :consensus_reached]
# [:foundation, :mabeam, :coordination, :byzantine, :view_change_initiated]
# [:foundation, :mabeam, :coordination, :weighted, :vote_processed]
# [:foundation, :mabeam, :coordination, :iterative, :round_completed]
```

### 5.3 Error Handling and Recovery

Robust error handling patterns for production deployment:

```elixir
defp handle_coordination_error(error, session, state, context) do
  Logger.error("Coordination error in #{context}: #{inspect(error)}")
  
  # Emit error telemetry
  emit_coordination_telemetry(:coordination_error, session.id, %{}, %{
    error: error,
    context: context,
    algorithm: session.type
  })
  
  # Determine recovery strategy
  case error do
    {:timeout, _} ->
      # Handle timeouts gracefully
      handle_coordination_timeout(session, state)
      
    {:agent_failure, agent_id} ->
      # Remove failed agent and continue if possible
      handle_agent_failure(session, state, agent_id)
      
    {:invalid_message, _} ->
      # Log and continue (Byzantine fault tolerance)
      {:ok, session, state}
      
    {:insufficient_agents, _} ->
      # Cannot continue, fail the session
      fail_coordination_session(session, state, error)
      
    _ ->
      # Unknown error, fail safely
      fail_coordination_session(session, state, error)
  end
end
```

This comprehensive specification provides the foundation for implementing production-ready Byzantine consensus, weighted voting, and iterative refinement algorithms in the Foundation MABEAM system. The layered TDD approach ensures robust, well-tested implementations that integrate seamlessly with the existing infrastructure.