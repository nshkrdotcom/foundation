defmodule Foundation.MABEAM.CoordinationHelpers do
  @moduledoc """
  Comprehensive coordination test utilities for MABEAM system testing.

  Provides helper functions for:
  - Coordination protocol setup and management
  - Session lifecycle management and tracking
  - Consensus and negotiation testing utilities
  - Agent coordination behavior simulation
  - Result verification and assertion helpers
  - Performance testing for coordination scenarios
  """

  alias Foundation.MABEAM.Coordination

  # ============================================================================
  # Protocol Setup Helpers
  # ============================================================================

  @doc """
  Creates and registers a test consensus protocol with default settings.
  """
  @spec create_consensus_protocol(keyword()) :: map()
  def create_consensus_protocol(opts \\ []) do
    %{
      name: Keyword.get(opts, :name, :test_consensus),
      type: :consensus,
      algorithm: Keyword.get(opts, :algorithm, :majority_vote),
      timeout: Keyword.get(opts, :timeout, 5000),
      retry_policy: Keyword.get(opts, :retry_policy, %{max_retries: 3, backoff: :exponential}),
      confidence_threshold: Keyword.get(opts, :confidence_threshold, 0.6),
      metadata: %{created_for: :testing}
    }
  end

  @doc """
  Creates and registers a test negotiation protocol.
  """
  @spec create_negotiation_protocol(keyword()) :: map()
  def create_negotiation_protocol(opts \\ []) do
    %{
      name: Keyword.get(opts, :name, :test_negotiation),
      type: :negotiation,
      algorithm: Keyword.get(opts, :algorithm, :bilateral_bargaining),
      timeout: Keyword.get(opts, :timeout, 10000),
      rounds: Keyword.get(opts, :rounds, 5),
      resource_type: Keyword.get(opts, :resource_type, :cpu),
      metadata: %{created_for: :testing}
    }
  end

  @doc """
  Creates and registers a test auction protocol.
  """
  @spec create_auction_protocol(keyword()) :: map()
  def create_auction_protocol(opts \\ []) do
    auction_type = Keyword.get(opts, :auction_type, :sealed_bid)

    %{
      name: Keyword.get(opts, :name, :test_auction),
      type: :auction,
      auction_type: auction_type,
      timeout: Keyword.get(opts, :timeout, 15000),
      reserve_price: Keyword.get(opts, :reserve_price, 0),
      bid_increment: Keyword.get(opts, :bid_increment, 1),
      metadata: %{created_for: :testing, auction_type: auction_type}
    }
  end

  @doc """
  Registers multiple test protocols at once.
  """
  @spec setup_test_protocols(keyword()) :: {:ok, [atom()]} | {:error, term()}
  def setup_test_protocols(opts \\ []) do
    protocols = [
      {:consensus, create_consensus_protocol(Keyword.get(opts, :consensus, []))},
      {:negotiation, create_negotiation_protocol(Keyword.get(opts, :negotiation, []))},
      {:auction, create_auction_protocol(Keyword.get(opts, :auction, []))}
    ]

    results =
      for {type, protocol} <- protocols do
        protocol_name = :"test_#{type}"

        case Coordination.register_protocol(protocol_name, protocol) do
          :ok -> {:ok, protocol_name}
          error -> error
        end
      end

    case Enum.find(results, &match?({:error, _}, &1)) do
      nil ->
        protocol_names = Enum.map(results, fn {:ok, name} -> name end)
        {:ok, protocol_names}

      error ->
        error
    end
  end

  # ============================================================================
  # Session Management Helpers
  # ============================================================================

  @doc """
  Starts a coordination session and returns session tracking information.
  """
  @spec start_coordination_session(atom(), [atom()], map(), keyword()) ::
          {:ok, %{session_id: binary(), start_time: integer()}} | {:error, term()}
  def start_coordination_session(protocol_name, agent_ids, context, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)
    start_time = System.monotonic_time(:millisecond)

    case Coordination.coordinate(protocol_name, agent_ids, context, timeout: timeout) do
      {:ok, session_id} when is_binary(session_id) ->
        {:ok, %{session_id: session_id, start_time: start_time}}

      {:ok, result} ->
        # Immediate result, generate session info
        session_id = generate_session_id()
        {:ok, %{session_id: session_id, start_time: start_time, immediate_result: result}}

      error ->
        error
    end
  end

  @doc """
  Waits for coordination session to complete and returns result with timing.
  """
  @spec wait_for_coordination_result(binary(), non_neg_integer()) ::
          {:ok, %{result: term(), duration_ms: non_neg_integer()}} | {:error, :timeout}
  def wait_for_coordination_result(session_id, timeout \\ 10000) do
    start_time = System.monotonic_time(:millisecond)

    receive do
      {:mabeam_coordination_result, ^session_id, result} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time
        {:ok, %{result: result, duration_ms: duration}}
    after
      timeout ->
        {:error, :timeout}
    end
  end

  @doc """
  Runs a complete coordination session from start to finish.
  """
  @spec run_coordination_session(atom(), [atom()], map(), keyword()) ::
          {:ok, %{result: term(), duration_ms: non_neg_integer(), session_id: binary()}}
          | {:error, term()}
  def run_coordination_session(protocol_name, agent_ids, context, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 10000)

    case start_coordination_session(protocol_name, agent_ids, context, opts) do
      {:ok, %{session_id: session_id, immediate_result: result}} ->
        # Immediate result available
        {:ok, %{result: result, duration_ms: 0, session_id: session_id}}

      {:ok, %{session_id: session_id}} ->
        # Wait for async result
        case wait_for_coordination_result(session_id, timeout) do
          {:ok, %{result: result, duration_ms: duration}} ->
            {:ok, %{result: result, duration_ms: duration, session_id: session_id}}

          error ->
            error
        end

      error ->
        error
    end
  end

  # ============================================================================
  # Agent Behavior Simulation
  # ============================================================================

  @doc """
  Sets up agents with predetermined coordination behaviors.
  """
  @spec setup_agent_behaviors([{atom(), map()}]) :: :ok
  def setup_agent_behaviors(agent_behaviors) do
    for {agent_id, behavior} <- agent_behaviors do
      case Foundation.MABEAM.ProcessRegistry.get_agent_pid(agent_id) do
        {:ok, pid} ->
          GenServer.cast(pid, {:set_coordination_behavior, behavior})

        {:error, _} ->
          # Agent not found, skip
          :ok
      end
    end

    :ok
  end

  @doc """
  Creates consensus voting behaviors for agents.
  """
  @spec create_consensus_behaviors([atom()], map()) :: [{atom(), map()}]
  def create_consensus_behaviors(agent_ids, opts \\ %{}) do
    vote_distribution = Map.get(opts, :vote_distribution, %{yes: 0.7, no: 0.3})
    confidence_range = Map.get(opts, :confidence_range, {0.6, 0.9})

    for agent_id <- agent_ids do
      vote = weighted_random_choice(vote_distribution)
      confidence = random_in_range(confidence_range)

      behavior = %{
        type: :consensus,
        vote: vote,
        confidence: confidence,
        response_delay: Enum.random(10..100)
      }

      {agent_id, behavior}
    end
  end

  @doc """
  Creates negotiation behaviors for agents.
  """
  @spec create_negotiation_behaviors([atom()], map()) :: [{atom(), map()}]
  def create_negotiation_behaviors(agent_ids, opts \\ %{}) do
    strategy_distribution =
      Map.get(opts, :strategy_distribution, %{
        aggressive: 0.3,
        moderate: 0.5,
        conservative: 0.2
      })

    for agent_id <- agent_ids do
      strategy = weighted_random_choice(strategy_distribution)

      behavior = %{
        type: :negotiation,
        strategy: strategy,
        initial_offer: generate_negotiation_offer(strategy),
        concession_rate: generate_concession_rate(strategy),
        response_delay: Enum.random(50..200)
      }

      {agent_id, behavior}
    end
  end

  @doc """
  Creates auction bidding behaviors for agents.
  """
  @spec create_auction_behaviors([atom()], map()) :: [{atom(), map()}]
  def create_auction_behaviors(agent_ids, opts \\ %{}) do
    budget_range = Map.get(opts, :budget_range, {10, 100})

    strategy_distribution =
      Map.get(opts, :strategy_distribution, %{
        aggressive: 0.25,
        strategic: 0.5,
        conservative: 0.25
      })

    for agent_id <- agent_ids do
      strategy = weighted_random_choice(strategy_distribution)
      budget = random_in_range(budget_range)

      behavior = %{
        type: :auction,
        strategy: strategy,
        max_budget: budget,
        bid_increment: calculate_bid_increment(strategy, budget),
        response_delay: Enum.random(20..150)
      }

      {agent_id, behavior}
    end
  end

  # ============================================================================
  # Result Verification Helpers
  # ============================================================================

  @doc """
  Asserts that consensus was reached with expected outcome.
  """
  @spec assert_consensus_reached(term(), atom(), keyword()) :: :ok
  def assert_consensus_reached(result, expected_choice, opts \\ []) do
    min_confidence = Keyword.get(opts, :min_confidence, 0.5)

    case result do
      {:ok, %{consensus_reached: true, winning_choice: ^expected_choice, confidence: confidence}}
      when confidence >= min_confidence ->
        :ok

      {:ok, %{consensus_reached: true, winning_choice: actual_choice}} ->
        raise "Expected consensus choice #{expected_choice}, got #{actual_choice}"

      {:ok, %{consensus_reached: false}} ->
        raise "Expected consensus to be reached, but it failed"

      {:error, reason} ->
        raise "Expected successful consensus, got error: #{inspect(reason)}"

      other ->
        raise "Unexpected consensus result format: #{inspect(other)}"
    end
  end

  @doc """
  Asserts that negotiation completed successfully.
  """
  @spec assert_negotiation_success(term(), keyword()) :: :ok
  def assert_negotiation_success(result, opts \\ []) do
    min_satisfaction = Keyword.get(opts, :min_satisfaction, 0.5)

    case result do
      {:ok, %{agreement_reached: true, satisfaction_score: score}}
      when score >= min_satisfaction ->
        :ok

      {:ok, %{agreement_reached: false}} ->
        raise "Expected negotiation agreement to be reached"

      {:error, reason} ->
        raise "Expected successful negotiation, got error: #{inspect(reason)}"

      other ->
        raise "Unexpected negotiation result format: #{inspect(other)}"
    end
  end

  @doc """
  Asserts that auction completed with valid results.
  """
  @spec assert_auction_success(term(), keyword()) :: :ok
  def assert_auction_success(result, opts \\ []) do
    min_bids = Keyword.get(opts, :min_bids, 1)

    case result do
      {:ok, %{winner: winner, winning_bid: bid, total_bids: total}}
      when not is_nil(winner) and is_number(bid) and total >= min_bids ->
        :ok

      {:ok, %{winner: nil}} ->
        raise "Expected auction to have a winner"

      {:error, reason} ->
        raise "Expected successful auction, got error: #{inspect(reason)}"

      other ->
        raise "Unexpected auction result format: #{inspect(other)}"
    end
  end

  @doc """
  Asserts coordination performance meets requirements.
  """
  @spec assert_coordination_performance(non_neg_integer(), keyword()) :: :ok
  def assert_coordination_performance(duration_ms, opts \\ []) do
    max_duration = Keyword.get(opts, :max_duration_ms, 5000)
    min_duration = Keyword.get(opts, :min_duration_ms, 0)

    cond do
      duration_ms > max_duration ->
        raise "Coordination took #{duration_ms}ms, expected <= #{max_duration}ms"

      duration_ms < min_duration ->
        raise "Coordination took #{duration_ms}ms, expected >= #{min_duration}ms"

      true ->
        :ok
    end
  end

  # ============================================================================
  # Performance Testing Helpers
  # ============================================================================

  @doc """
  Runs concurrent coordination sessions and measures performance.
  """
  @spec benchmark_concurrent_coordination(atom(), [atom()], map(), non_neg_integer(), keyword()) ::
          %{success_rate: float(), avg_duration_ms: float(), results: [term()]}
  def benchmark_concurrent_coordination(
        protocol_name,
        agent_ids,
        context,
        session_count,
        opts \\ []
      ) do
    timeout = Keyword.get(opts, :timeout, 10000)

    start_time = System.monotonic_time(:millisecond)

    tasks =
      for _i <- 1..session_count do
        Task.async(fn ->
          run_coordination_session(protocol_name, agent_ids, context, timeout: timeout)
        end)
      end

    results = Task.await_many(tasks, timeout + 1000)
    end_time = System.monotonic_time(:millisecond)

    successes = Enum.count(results, &match?({:ok, _}, &1))
    success_rate = successes / session_count

    successful_durations =
      results
      |> Enum.filter(&match?({:ok, _}, &1))
      |> Enum.map(fn {:ok, %{duration_ms: duration}} -> duration end)

    avg_duration =
      if length(successful_durations) > 0 do
        Enum.sum(successful_durations) / length(successful_durations)
      else
        0.0
      end

    %{
      success_rate: success_rate,
      avg_duration_ms: avg_duration,
      total_time_ms: end_time - start_time,
      successful_sessions: successes,
      failed_sessions: session_count - successes,
      results: results
    }
  end

  @doc """
  Tests coordination scalability with increasing agent counts.
  """
  @spec test_coordination_scalability(atom(), [atom()], map(), keyword()) ::
          %{scalability_results: [map()], performance_degradation: float()}
  def test_coordination_scalability(protocol_name, available_agents, context, opts \\ []) do
    agent_counts = Keyword.get(opts, :agent_counts, [2, 5, 10, 20])
    sessions_per_test = Keyword.get(opts, :sessions_per_test, 5)

    results =
      for agent_count <- agent_counts do
        test_agents = Enum.take(available_agents, agent_count)

        benchmark_result =
          benchmark_concurrent_coordination(
            protocol_name,
            test_agents,
            context,
            sessions_per_test,
            opts
          )

        Map.put(benchmark_result, :agent_count, agent_count)
      end

    # Calculate performance degradation
    first_result = List.first(results)
    last_result = List.last(results)

    degradation =
      if first_result && last_result && first_result.avg_duration_ms > 0 do
        (last_result.avg_duration_ms - first_result.avg_duration_ms) / first_result.avg_duration_ms
      else
        0.0
      end

    %{
      scalability_results: results,
      performance_degradation: degradation
    }
  end

  # ============================================================================
  # Coordination State Helpers
  # ============================================================================

  @doc """
  Gets current coordination system state for testing.
  """
  @spec get_coordination_state() :: map()
  def get_coordination_state() do
    {:ok, stats} = Coordination.get_coordination_stats()
    {:ok, protocols} = Coordination.list_protocols()
    {:ok, sessions} = Coordination.list_active_sessions()

    %{
      statistics: stats,
      registered_protocols: protocols,
      active_sessions: sessions,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Compares coordination states to detect changes.
  """
  @spec compare_coordination_states(map(), map()) :: map()
  def compare_coordination_states(before_state, after_state) do
    %{
      time_diff_seconds: DateTime.diff(after_state.timestamp, before_state.timestamp, :second),
      stats_diff: calculate_stats_diff(before_state.statistics, after_state.statistics),
      protocol_changes:
        detect_protocol_changes(before_state.registered_protocols, after_state.registered_protocols),
      session_changes:
        detect_session_changes(before_state.active_sessions, after_state.active_sessions)
    }
  end

  # ============================================================================
  # Cleanup Helpers
  # ============================================================================

  @doc """
  Cleans up test coordination protocols and sessions.
  """
  @spec cleanup_coordination_test(keyword()) :: :ok
  def cleanup_coordination_test(opts \\ []) do
    protocols_to_cleanup = Keyword.get(opts, :protocols, [])
    sessions_to_cleanup = Keyword.get(opts, :sessions, [])

    # Cancel active sessions
    for session_id <- sessions_to_cleanup do
      Coordination.cancel_session(session_id)
    end

    # Unregister test protocols
    for protocol_name <- protocols_to_cleanup do
      Coordination.unregister_protocol(protocol_name)
    end

    :ok
  end

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  defp generate_session_id() do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp weighted_random_choice(distribution) do
    total_weight = distribution |> Map.values() |> Enum.sum()
    random_value = :rand.uniform() * total_weight

    {choice, _} =
      Enum.reduce_while(distribution, {nil, 0}, fn {choice, weight}, {_current, acc} ->
        new_acc = acc + weight

        if random_value <= new_acc do
          {:halt, {choice, new_acc}}
        else
          {:cont, {choice, new_acc}}
        end
      end)

    choice
  end

  defp random_in_range({min, max}) when is_number(min) and is_number(max) do
    min + :rand.uniform() * (max - min)
  end

  defp generate_negotiation_offer(:aggressive), do: Enum.random(80..100)
  defp generate_negotiation_offer(:moderate), do: Enum.random(50..80)
  defp generate_negotiation_offer(:conservative), do: Enum.random(20..50)

  defp generate_concession_rate(:aggressive), do: 0.1
  defp generate_concession_rate(:moderate), do: 0.05
  defp generate_concession_rate(:conservative), do: 0.02

  defp calculate_bid_increment(:aggressive, budget), do: trunc(budget * 0.15)
  defp calculate_bid_increment(:strategic, budget), do: trunc(budget * 0.10)
  defp calculate_bid_increment(:conservative, budget), do: trunc(budget * 0.05)

  defp calculate_stats_diff(before_stats, after_stats) do
    common_keys =
      MapSet.intersection(
        MapSet.new(Map.keys(before_stats)),
        MapSet.new(Map.keys(after_stats))
      )

    for key <- common_keys, into: %{} do
      before_val = Map.get(before_stats, key, 0)
      after_val = Map.get(after_stats, key, 0)

      diff =
        case {before_val, after_val} do
          {b, a} when is_number(b) and is_number(a) -> a - b
          {b, a} -> {b, a}
        end

      {key, diff}
    end
  end

  defp detect_protocol_changes(before_protocols, after_protocols) do
    before_set = MapSet.new(before_protocols)
    after_set = MapSet.new(after_protocols)

    %{
      added: MapSet.difference(after_set, before_set) |> MapSet.to_list(),
      removed: MapSet.difference(before_set, after_set) |> MapSet.to_list(),
      unchanged: MapSet.intersection(before_set, after_set) |> MapSet.to_list()
    }
  end

  defp detect_session_changes(before_sessions, after_sessions) do
    before_ids = MapSet.new(Enum.map(before_sessions, & &1.session_id))
    after_ids = MapSet.new(Enum.map(after_sessions, & &1.session_id))

    %{
      new_sessions: MapSet.difference(after_ids, before_ids) |> MapSet.to_list(),
      completed_sessions: MapSet.difference(before_ids, after_ids) |> MapSet.to_list(),
      ongoing_sessions: MapSet.intersection(before_ids, after_ids) |> MapSet.to_list()
    }
  end
end
