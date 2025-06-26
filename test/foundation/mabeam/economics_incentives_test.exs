defmodule Foundation.MABEAM.EconomicsIncentivesTest do
  @moduledoc """
  Comprehensive test suite for Phase 3.3: Economic Incentive Alignment Mechanisms.

  Tests cover:
  - Reputation-based incentive systems
  - Market-based coordination mechanisms  
  - Incentive-compatible consensus algorithms
  - Cost-benefit optimization
  - Dynamic pricing mechanisms
  - Economic fault tolerance
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Foundation.MABEAM.Economics

  setup do
    case Economics.start_link(test_mode: true) do
      {:ok, pid} -> %{economics_pid: pid}
      {:error, {:already_started, pid}} -> %{economics_pid: pid}
    end
  end

  describe "reputation-based incentive systems" do
    test "calculates reputation-based rewards for high-performing agents", %{economics_pid: _pid} do
      # Initialize agent with baseline reputation
      agent_id = :test_agent_high_performer

      initial_reputation = %{
        initial_score: 0.8,
        specializations: [:text_generation, :code_review],
        performance_standards: %{
          quality_threshold: 0.85,
          cost_efficiency_threshold: 0.75,
          response_time_threshold: 5000
        }
      }

      :ok = Economics.initialize_agent_reputation(agent_id, initial_reputation)

      # Record consistently high performance
      performance_records = [
        %{
          task_id: "task_001",
          task_type: :text_generation,
          quality_score: 0.95,
          cost_efficiency: 0.88,
          completion_time_ms: 3500,
          client_satisfaction: 0.92
        },
        %{
          task_id: "task_002",
          task_type: :code_review,
          quality_score: 0.91,
          cost_efficiency: 0.85,
          completion_time_ms: 4200,
          client_satisfaction: 0.89
        },
        %{
          task_id: "task_003",
          task_type: :text_generation,
          quality_score: 0.93,
          cost_efficiency: 0.82,
          completion_time_ms: 3800,
          client_satisfaction: 0.94
        }
      ]

      # Update reputation with performance data
      Enum.each(performance_records, fn record ->
        :ok = Economics.update_agent_reputation(agent_id, record)
      end)

      # Calculate reputation-based incentive reward
      incentive_config = %{
        base_reward: 100.0,
        reputation_multiplier: 2.0,
        consistency_bonus: 0.2,
        specialization_bonus: 0.15,
        performance_threshold_bonus: 0.25
      }

      {:ok, agent_reputation} = Economics.get_agent_reputation(agent_id)

      performance_metrics = %{
        recent_quality_avg: 0.93,
        recent_efficiency_avg: 0.85,
        task_completion_rate: 1.0,
        consistency_score: 0.95
      }

      {:ok, reward} =
        Economics.calculate_reputation_based_reward(
          agent_id,
          incentive_config,
          performance_metrics
        )

      # Verify reward calculation includes all bonuses
      assert reward > incentive_config.base_reward

      assert reward >=
               100.0 *
                 (1 + agent_reputation.reputation_score * incentive_config.reputation_multiplier)

      # Verify reputation improvement
      assert agent_reputation.reputation_score > initial_reputation.initial_score
      assert length(agent_reputation.performance_history) == 3
    end

    test "applies reputation-based penalties for poor performing agents", %{economics_pid: _pid} do
      agent_id = :test_agent_poor_performer
      initial_reputation = %{initial_score: 0.7}

      :ok = Economics.initialize_agent_reputation(agent_id, initial_reputation)

      # Record poor performance
      poor_performance = %{
        task_id: "poor_task_001",
        task_type: :text_generation,
        quality_score: 0.45,
        cost_efficiency: 0.3,
        completion_time_ms: 15000,
        client_satisfaction: 0.25
      }

      :ok = Economics.update_agent_reputation(agent_id, poor_performance)

      # Calculate penalty-adjusted reward
      incentive_config = %{
        base_reward: 100.0,
        reputation_multiplier: 2.0,
        performance_penalty_threshold: 0.5,
        penalty_multiplier: 0.5
      }

      performance_metrics = %{
        recent_quality_avg: 0.45,
        recent_efficiency_avg: 0.3,
        task_completion_rate: 1.0,
        consistency_score: 0.2
      }

      {:ok, reward} =
        Economics.calculate_reputation_based_reward(
          agent_id,
          incentive_config,
          performance_metrics
        )

      # Verify penalty application
      assert reward < incentive_config.base_reward

      {:ok, updated_reputation} = Economics.get_agent_reputation(agent_id)
      assert updated_reputation.reputation_score < initial_reputation.initial_score
    end

    test "implements progressive reputation recovery system", %{economics_pid: _pid} do
      agent_id = :test_agent_recovery

      # Start with damaged reputation
      initial_reputation = %{initial_score: 0.3}
      :ok = Economics.initialize_agent_reputation(agent_id, initial_reputation)

      # Record gradual improvement over multiple tasks
      improvement_records = [
        %{
          task_id: "recovery_001",
          quality_score: 0.6,
          cost_efficiency: 0.5,
          client_satisfaction: 0.6
        },
        %{
          task_id: "recovery_002",
          quality_score: 0.7,
          cost_efficiency: 0.65,
          client_satisfaction: 0.7
        },
        %{
          task_id: "recovery_003",
          quality_score: 0.8,
          cost_efficiency: 0.75,
          client_satisfaction: 0.8
        },
        %{
          task_id: "recovery_004",
          quality_score: 0.85,
          cost_efficiency: 0.8,
          client_satisfaction: 0.85
        }
      ]

      final_scores =
        Enum.map(improvement_records, fn record ->
          :ok = Economics.update_agent_reputation(agent_id, record)
          {:ok, reputation} = Economics.get_agent_reputation(agent_id)
          reputation.reputation_score
        end)

      # Verify progressive improvement
      assert Enum.all?(Enum.chunk_every(final_scores, 2, 1, :discard), fn [a, b] -> b >= a end)
      assert List.last(final_scores) > initial_reputation.initial_score
    end

    property "reputation scores remain bounded between 0 and 1" do
      check all(
              quality_score <- float(min: 0.0, max: 1.0),
              cost_efficiency <- float(min: 0.0, max: 1.0),
              client_satisfaction <- float(min: 0.0, max: 1.0),
              initial_score <- float(min: 0.0, max: 1.0)
            ) do
        agent_id = :property_test_agent
        Economics.initialize_agent_reputation(agent_id, %{initial_score: initial_score})

        performance_data = %{
          task_id: "prop_test_#{System.unique_integer()}",
          quality_score: quality_score,
          cost_efficiency: cost_efficiency,
          client_satisfaction: client_satisfaction,
          completion_time_ms: 5000
        }

        Economics.update_agent_reputation(agent_id, performance_data)
        {:ok, reputation} = Economics.get_agent_reputation(agent_id)

        assert reputation.reputation_score >= 0.0
        assert reputation.reputation_score <= 1.0
      end
    end
  end

  describe "market-based coordination mechanisms" do
    test "creates incentive-aligned task auctions with performance bonuses", %{economics_pid: _pid} do
      # Create specialized auction with incentive alignment
      auction_spec = %{
        type: :incentive_aligned_english,
        item: %{
          task: :ml_model_optimization,
          dataset_size: 500_000,
          performance_target: 0.92,
          max_budget: 1000.0,
          deadline_hours: 24
        },
        incentive_structure: %{
          base_payment: 500.0,
          # $10 per 0.01 above target
          performance_bonus_rate: 10.0,
          # $5 per hour under deadline
          speed_bonus_rate: 5.0,
          # Minimum quality for payment
          quality_threshold: 0.88,
          # 10% bonus for high reputation
          reputation_multiplier: 0.1
        },
        reputation_requirements: %{
          minimum_score: 0.6,
          required_specializations: [:ml_optimization, :model_tuning]
        }
      }

      {:ok, auction_id} = Economics.create_incentive_aligned_auction(auction_spec)

      # High reputation agent places bid
      high_rep_agent = :high_rep_ml_agent

      Economics.initialize_agent_reputation(high_rep_agent, %{
        initial_score: 0.9,
        specializations: [:ml_optimization, :model_tuning, :performance_analysis]
      })

      bid_spec = %{
        price: 450.0,
        performance_guarantee: 0.94,
        estimated_completion_hours: 18,
        reputation_score: 0.9
      }

      {:ok, _bid_id} = Economics.place_incentive_aligned_bid(auction_id, high_rep_agent, bid_spec)

      # Simulate auction completion with performance results
      completion_results = %{
        actual_performance: 0.96,
        actual_completion_hours: 16,
        quality_score: 0.95,
        client_satisfaction: 0.93
      }

      {:ok, settlement} =
        Economics.settle_incentive_aligned_auction(
          auction_id,
          completion_results
        )

      # Verify incentive calculations
      expected_performance_bonus =
        (0.96 - 0.92) * 100 * auction_spec.incentive_structure.performance_bonus_rate

      expected_speed_bonus = (24 - 16) * auction_spec.incentive_structure.speed_bonus_rate

      expected_reputation_bonus =
        bid_spec.price * auction_spec.incentive_structure.reputation_multiplier

      assert settlement.total_payment > bid_spec.price
      assert settlement.performance_bonus == expected_performance_bonus
      assert settlement.speed_bonus == expected_speed_bonus
      assert settlement.reputation_bonus == expected_reputation_bonus
      assert settlement.winner == high_rep_agent
    end

    test "implements reputation-gated marketplace access", %{economics_pid: _pid} do
      # Create premium marketplace with reputation requirements
      marketplace_spec = %{
        name: "Premium ML Services Exchange",
        categories: [:advanced_ml, :research_services],
        reputation_gates: %{
          minimum_score: 0.8,
          required_specializations: [:advanced_ml],
          performance_history_length: 10,
          consistency_requirement: 0.85
        },
        fee_structure: %{
          # Reduced for high reputation
          listing_fee: 0.02,
          transaction_fee: 0.01,
          reputation_discount_rate: 0.5
        }
      }

      {:ok, marketplace_id} = Economics.create_reputation_gated_marketplace(marketplace_spec)

      # High reputation agent should gain access
      qualified_agent = :premium_agent

      Economics.initialize_agent_reputation(qualified_agent, %{
        initial_score: 0.85,
        specializations: [:advanced_ml, :deep_learning],
        performance_history:
          Enum.map(1..12, fn i ->
            %{task_id: "task_#{i}", quality_score: 0.9, client_satisfaction: 0.88}
          end)
      })

      service_spec = %{
        provider: qualified_agent,
        service_type: :advanced_ml,
        capabilities: [:neural_architecture_search, :hyperparameter_optimization],
        pricing: %{base_rate: 50.0, premium_rate: 75.0}
      }

      {:ok, listing_id} =
        Economics.list_service_with_reputation_gate(
          marketplace_id,
          service_spec
        )

      # Verify listing creation and fee calculation
      {:ok, marketplace} = Economics.get_marketplace(marketplace_id)
      {:ok, agent_reputation} = Economics.get_agent_reputation(qualified_agent)

      listing = Map.get(marketplace.active_listings, listing_id)
      assert listing.provider == qualified_agent
      assert listing.reputation_verified == true

      # Verify reputation-based fee discount
      expected_fee =
        marketplace_spec.fee_structure.listing_fee *
          (1 -
             agent_reputation.reputation_score *
               marketplace_spec.fee_structure.reputation_discount_rate)

      assert listing.actual_listing_fee <= expected_fee

      # Unqualified agent should be rejected
      unqualified_agent = :basic_agent
      Economics.initialize_agent_reputation(unqualified_agent, %{initial_score: 0.4})

      assert {:error, :insufficient_reputation} =
               Economics.list_service_with_reputation_gate(
                 marketplace_id,
                 %{service_spec | provider: unqualified_agent}
               )
    end

    test "coordinates multi-agent task allocation with reputation weighting", %{economics_pid: _pid} do
      # Create complex task requiring multiple agents with different specializations
      task_spec = %{
        task_id: "complex_ml_pipeline",
        subtasks: [
          %{id: :data_preprocessing, specialization: :data_engineering, complexity: :medium},
          %{id: :model_development, specialization: :ml_engineering, complexity: :high},
          %{id: :model_evaluation, specialization: :ml_validation, complexity: :medium},
          %{id: :deployment_optimization, specialization: :ml_ops, complexity: :high}
        ],
        coordination_budget: 2000.0,
        deadline_hours: 48,
        quality_requirements: %{minimum_overall: 0.9, minimum_individual: 0.85}
      }

      # Initialize diverse agent pool with different specializations and reputations
      agent_pool = [
        {:data_engineer_1, 0.85, [:data_engineering, :etl_optimization]},
        {:data_engineer_2, 0.78, [:data_engineering, :data_validation]},
        {:ml_engineer_1, 0.92, [:ml_engineering, :deep_learning]},
        {:ml_engineer_2, 0.88, [:ml_engineering, :ensemble_methods]},
        {:validator_1, 0.81, [:ml_validation, :statistical_analysis]},
        {:mlops_specialist, 0.87, [:ml_ops, :deployment_optimization]}
      ]

      Enum.each(agent_pool, fn {agent_id, rep_score, specializations} ->
        Economics.initialize_agent_reputation(agent_id, %{
          initial_score: rep_score,
          specializations: specializations
        })
      end)

      {:ok, allocation_result} =
        Economics.coordinate_multi_agent_task_allocation(
          task_spec,
          Enum.map(agent_pool, &elem(&1, 0))
        )

      # Verify optimal allocation based on reputation and specialization matching
      assert length(allocation_result.agent_assignments) == length(task_spec.subtasks)
      assert allocation_result.total_cost <= task_spec.coordination_budget

      # Verify each subtask assigned to appropriately specialized agent
      Enum.each(allocation_result.agent_assignments, fn assignment ->
        {:ok, agent_rep} = Economics.get_agent_reputation(assignment.agent_id)
        subtask = Enum.find(task_spec.subtasks, &(&1.id == assignment.subtask_id))

        assert subtask.specialization in agent_rep.specializations
        # Quality threshold
        assert agent_rep.reputation_score >= 0.75
      end)

      # Verify reputation-weighted cost allocation
      total_reputation_weight =
        allocation_result.agent_assignments
        |> Enum.map(fn assignment ->
          {:ok, rep} = Economics.get_agent_reputation(assignment.agent_id)
          rep.reputation_score
        end)
        |> Enum.sum()

      Enum.each(allocation_result.agent_assignments, fn assignment ->
        {:ok, agent_rep} = Economics.get_agent_reputation(assignment.agent_id)
        expected_weight = agent_rep.reputation_score / total_reputation_weight

        # Higher reputation agents should get proportionally higher compensation
        assert assignment.compensation_weight >= expected_weight * 0.8
      end)
    end
  end

  describe "incentive-compatible consensus mechanisms" do
    test "implements truthful bidding mechanisms with revelation principle", %{economics_pid: _pid} do
      # Create Vickrey-Clarke-Groves (VCG) auction for truthful bidding
      vcg_auction_spec = %{
        type: :vcg_mechanism,
        items: [
          %{id: :compute_resource_a, value_range: {100, 500}, capacity: 1000},
          %{id: :compute_resource_b, value_range: {200, 800}, capacity: 2000},
          %{id: :storage_resource, value_range: {50, 300}, capacity: 5000}
        ],
        mechanism_properties: %{
          truthful_bidding_required: true,
          individual_rationality: true,
          budget_balance: :approximate,
          social_welfare_optimization: true
        }
      }

      {:ok, vcg_auction_id} = Economics.create_vcg_mechanism_auction(vcg_auction_spec)

      # Agents submit truthful valuations
      agents_valuations = [
        {:agent_alpha, %{compute_resource_a: 450, compute_resource_b: 650, storage_resource: 200}},
        {:agent_beta, %{compute_resource_a: 380, compute_resource_b: 720, storage_resource: 280}},
        {:agent_gamma, %{compute_resource_a: 420, compute_resource_b: 600, storage_resource: 150}}
      ]

      _vcg_bids =
        Enum.map(agents_valuations, fn {agent_id, valuations} ->
          {:ok, bid_id} = Economics.submit_vcg_truthful_bid(vcg_auction_id, agent_id, valuations)
          {agent_id, bid_id, valuations}
        end)

      {:ok, vcg_results} = Economics.resolve_vcg_mechanism(vcg_auction_id)

      # Verify VCG properties
      assert vcg_results.mechanism_properties.truthful_equilibrium == true
      assert vcg_results.mechanism_properties.individual_rationality_satisfied == true
      assert vcg_results.total_social_welfare > 0

      # Verify each winner pays their externality (VCG pricing)
      Enum.each(vcg_results.allocations, fn allocation ->
        agent_payment = allocation.vcg_payment
        agent_valuation = allocation.agent_valuation

        # Payment should be externality imposed on others
        assert agent_payment <= agent_valuation
        assert agent_payment >= 0

        # Verify no agent has incentive to misreport (truthfulness)
        assert allocation.utility >= 0
      end)
    end

    test "implements mechanism design for honest effort reporting", %{economics_pid: _pid} do
      # Create mechanism for agents to honestly report effort and outcomes
      effort_reporting_spec = %{
        mechanism_type: :effort_revelation,
        task_parameters: %{
          base_payment: 100.0,
          effort_cost_function: %{type: :quadratic, coefficient: 2.0},
          outcome_probability_function: %{type: :linear, effort_coefficient: 0.8},
          information_structure: :private_effort_costs
        },
        incentive_scheme: %{
          type: :optimal_contract,
          effort_verification: :statistical_detection,
          punishment_mechanism: :reputation_penalty,
          bonus_structure: :performance_contingent
        }
      }

      {:ok, mechanism_id} = Economics.create_effort_revelation_mechanism(effort_reporting_spec)

      # Agent reports private effort cost and chooses effort level
      agent_id = :honest_effort_agent
      Economics.initialize_agent_reputation(agent_id, %{initial_score: 0.8})

      # Agent's true private information
      _private_effort_cost = 25.0
      # Honest reporting (should be optimal)
      reported_effort_cost = 25.0
      chosen_effort_level = 0.7

      {:ok, _contract_terms} =
        Economics.submit_effort_report(
          mechanism_id,
          agent_id,
          %{
            reported_effort_cost: reported_effort_cost,
            chosen_effort_level: chosen_effort_level,
            # 0.8 * 0.7
            expected_outcome_probability: 0.56
          }
        )

      # Simulate task execution with actual outcome
      actual_outcome = :success

      actual_effort_evidence = %{
        completion_time_distribution: :consistent_with_reported,
        quality_indicators: :high,
        process_markers: :normal_effort_pattern
      }

      {:ok, settlement} =
        Economics.settle_effort_revelation_contract(
          mechanism_id,
          agent_id,
          %{
            actual_outcome: actual_outcome,
            effort_evidence: actual_effort_evidence,
            outcome_quality: 0.92
          }
        )

      # Verify incentive compatibility - honest reporting should be optimal
      assert settlement.contract_fulfilled == true
      assert settlement.final_payment >= effort_reporting_spec.task_parameters.base_payment
      assert settlement.effort_honesty_score >= 0.9

      # Verify no statistical detection of effort misreporting
      assert settlement.statistical_manipulation_detected == false

      # Test dishonest reporting scenario
      dishonest_agent = :dishonest_effort_agent
      Economics.initialize_agent_reputation(dishonest_agent, %{initial_score: 0.8})

      # Agent under-reports effort cost to get better contract terms
      _true_cost = 30.0
      # Lie to get better terms
      false_reported_cost = 15.0

      {:ok, _dishonest_contract} =
        Economics.submit_effort_report(
          mechanism_id,
          dishonest_agent,
          %{
            reported_effort_cost: false_reported_cost,
            # Lower effort due to actual higher cost
            chosen_effort_level: 0.5,
            expected_outcome_probability: 0.4
          }
        )

      # Lower effort leads to failure
      dishonest_outcome = :failure

      dishonest_evidence = %{
        completion_time_distribution: :inconsistent_with_reported,
        quality_indicators: :low,
        process_markers: :suspicious_effort_pattern
      }

      {:ok, dishonest_settlement} =
        Economics.settle_effort_revelation_contract(
          mechanism_id,
          dishonest_agent,
          %{
            actual_outcome: dishonest_outcome,
            effort_evidence: dishonest_evidence,
            outcome_quality: 0.3
          }
        )

      # Verify mechanism catches dishonesty
      assert dishonest_settlement.statistical_manipulation_detected == true
      assert dishonest_settlement.effort_honesty_score < 0.5
      assert dishonest_settlement.final_payment < effort_reporting_spec.task_parameters.base_payment

      # Verify reputation penalty applied
      {:ok, updated_dishonest_rep} = Economics.get_agent_reputation(dishonest_agent)
      assert updated_dishonest_rep.reputation_score < 0.8
    end

    test "creates collusion-resistant consensus mechanisms", %{economics_pid: _pid} do
      # Create mechanism resistant to agent collusion
      collusion_resistant_spec = %{
        mechanism_type: :collusion_resistant_consensus,
        consensus_task: %{
          type: :parameter_estimation,
          true_value_range: {50, 150},
          noise_level: 0.1,
          strategic_voting_incentive: :high
        },
        anti_collusion_measures: %{
          randomized_scoring: true,
          pivot_mechanism: true,
          information_partitioning: true,
          anonymous_reporting: true,
          sybil_resistance: :reputation_staking
        },
        payment_structure: %{
          base_payment: 50.0,
          accuracy_bonus_rate: 2.0,
          consensus_bonus: 20.0,
          collusion_penalty: 100.0
        }
      }

      {:ok, consensus_id} = Economics.create_collusion_resistant_consensus(collusion_resistant_spec)

      # Initialize agents with different information and incentives
      agents_info = [
        {:agent_1, %{private_signal: 75, signal_quality: 0.9, reputation_stake: 50}},
        {:agent_2, %{private_signal: 82, signal_quality: 0.85, reputation_stake: 45}},
        {:agent_3, %{private_signal: 68, signal_quality: 0.95, reputation_stake: 60}},
        {:agent_4, %{private_signal: 79, signal_quality: 0.8, reputation_stake: 40}},
        {:agent_5, %{private_signal: 73, signal_quality: 0.88, reputation_stake: 55}}
      ]

      # Agents attempt to collude (coordinate on inflated estimate)
      colluding_agents = [:agent_1, :agent_2]
      non_colluding_agents = [:agent_3, :agent_4, :agent_5]

      # Colluding agents coordinate to submit inflated estimates
      # Coordinated higher than their signals suggest
      collusion_estimate = 95

      Enum.each(colluding_agents, fn agent_id ->
        agent_info = Enum.find(agents_info, &(elem(&1, 0) == agent_id)) |> elem(1)

        Economics.initialize_agent_reputation(agent_id, %{
          initial_score: 0.8,
          reputation_stake: agent_info.reputation_stake
        })

        {:ok, _report_id} =
          Economics.submit_consensus_report(
            consensus_id,
            agent_id,
            %{
              estimated_value: collusion_estimate,
              confidence_level: 0.7,
              information_quality: agent_info.signal_quality
            }
          )
      end)

      # Non-colluding agents report honestly
      Enum.each(non_colluding_agents, fn agent_id ->
        agent_info = Enum.find(agents_info, &(elem(&1, 0) == agent_id)) |> elem(1)

        Economics.initialize_agent_reputation(agent_id, %{
          initial_score: 0.8,
          reputation_stake: agent_info.reputation_stake
        })

        {:ok, _report_id} =
          Economics.submit_consensus_report(
            consensus_id,
            agent_id,
            %{
              estimated_value: agent_info.private_signal,
              confidence_level: 0.9,
              information_quality: agent_info.signal_quality
            }
          )
      end)

      # Resolve consensus with collusion detection
      # Actual parameter value
      true_value = 76

      {:ok, consensus_result} =
        Economics.resolve_collusion_resistant_consensus(
          consensus_id,
          true_value
        )

      # Verify collusion detection and penalties
      assert consensus_result.collusion_detected == true
      assert length(consensus_result.suspected_colluders) >= 2
      assert :agent_1 in consensus_result.suspected_colluders
      assert :agent_2 in consensus_result.suspected_colluders

      # Verify honest agents receive higher payments
      honest_agent_payments =
        consensus_result.final_payments
        |> Enum.filter(fn {agent_id, _payment} -> agent_id in non_colluding_agents end)
        |> Enum.map(&elem(&1, 1))

      colluding_agent_payments =
        consensus_result.final_payments
        |> Enum.filter(fn {agent_id, _payment} -> agent_id in colluding_agents end)
        |> Enum.map(&elem(&1, 1))

      avg_honest_payment = Enum.sum(honest_agent_payments) / length(honest_agent_payments)
      avg_colluding_payment = Enum.sum(colluding_agent_payments) / length(colluding_agent_payments)

      assert avg_honest_payment > avg_colluding_payment

      assert Enum.all?(
               colluding_agent_payments,
               &(&1 < collusion_resistant_spec.payment_structure.base_payment)
             )

      # Verify reputation penalties for colluders
      Enum.each(colluding_agents, fn agent_id ->
        {:ok, updated_rep} = Economics.get_agent_reputation(agent_id)
        assert updated_rep.reputation_score < 0.8
      end)
    end
  end

  describe "cost-benefit optimization" do
    test "optimizes multi-objective cost-performance trade-offs", %{economics_pid: _pid} do
      # Define complex optimization problem with multiple objectives
      optimization_spec = %{
        optimization_type: :multi_objective_pareto,
        objectives: [
          %{name: :cost_minimization, weight: 0.4, direction: :minimize},
          %{name: :quality_maximization, weight: 0.35, direction: :maximize},
          %{name: :speed_maximization, weight: 0.25, direction: :maximize}
        ],
        constraints: [
          %{type: :budget_limit, value: 1000.0},
          %{type: :quality_threshold, value: 0.8},
          %{type: :deadline_hours, value: 24}
        ],
        agent_pool_characteristics: %{
          cost_distribution: %{min: 10, max: 100, distribution: :log_normal},
          quality_distribution: %{min: 0.6, max: 0.98, distribution: :beta},
          speed_distribution: %{min: 0.5, max: 2.0, distribution: :gamma}
        }
      }

      # Generate diverse agent pool with different cost-performance profiles
      agent_profiles = [
        {:budget_agent, %{cost_per_hour: 15, quality_score: 0.82, speed_multiplier: 0.8}},
        {:premium_agent, %{cost_per_hour: 75, quality_score: 0.95, speed_multiplier: 1.5}},
        {:balanced_agent, %{cost_per_hour: 35, quality_score: 0.88, speed_multiplier: 1.1}},
        {:speed_agent, %{cost_per_hour: 55, quality_score: 0.85, speed_multiplier: 1.8}},
        {:quality_agent, %{cost_per_hour: 65, quality_score: 0.96, speed_multiplier: 1.0}}
      ]

      Enum.each(agent_profiles, fn {agent_id, profile} ->
        Economics.initialize_agent_reputation(agent_id, %{
          initial_score: 0.8,
          cost_profile: profile,
          specializations: [:general_task_execution]
        })
      end)

      task_spec = %{
        estimated_hours: 12,
        quality_requirement: 0.85,
        urgency_level: :medium,
        complexity: :high
      }

      {:ok, optimization_result} =
        Economics.optimize_multi_objective_allocation(
          optimization_spec,
          Enum.map(agent_profiles, &elem(&1, 0)),
          task_spec
        )

      # Verify Pareto optimal solution
      assert optimization_result.solution_type == :pareto_optimal
      assert optimization_result.selected_agents != []

      # Verify constraint satisfaction
      total_cost = optimization_result.allocation_summary.total_cost
      expected_quality = optimization_result.allocation_summary.expected_quality
      expected_completion_time = optimization_result.allocation_summary.expected_completion_hours

      assert total_cost <=
               optimization_spec.constraints
               |> Enum.find(&(&1.type == :budget_limit))
               |> Map.get(:value)

      assert expected_quality >=
               optimization_spec.constraints
               |> Enum.find(&(&1.type == :quality_threshold))
               |> Map.get(:value)

      assert expected_completion_time <=
               optimization_spec.constraints
               |> Enum.find(&(&1.type == :deadline_hours))
               |> Map.get(:value)

      # Verify multi-objective optimization
      objective_scores = optimization_result.objective_scores
      assert Map.has_key?(objective_scores, :cost_minimization)
      assert Map.has_key?(objective_scores, :quality_maximization)
      assert Map.has_key?(objective_scores, :speed_maximization)

      # Verify trade-off analysis
      assert optimization_result.trade_off_analysis.pareto_frontier != []
      assert optimization_result.trade_off_analysis.dominated_solutions != []
    end

    test "implements dynamic cost-performance rebalancing", %{economics_pid: _pid} do
      # Create scenario requiring real-time rebalancing due to changing conditions
      initial_allocation = %{
        agents: [:agent_a, :agent_b, :agent_c],
        tasks: [
          %{id: :task_1, agent: :agent_a, estimated_cost: 100, quality_target: 0.9},
          %{id: :task_2, agent: :agent_b, estimated_cost: 150, quality_target: 0.85},
          %{id: :task_3, agent: :agent_c, estimated_cost: 200, quality_target: 0.92}
        ],
        total_budget: 500,
        performance_targets: %{average_quality: 0.89, completion_rate: 1.0}
      }

      {:ok, allocation_id} = Economics.create_dynamic_allocation(initial_allocation)

      # Simulate execution with performance feedback
      execution_updates = [
        %{
          timestamp: DateTime.utc_now(),
          agent_id: :agent_a,
          task_id: :task_1,
          progress: 0.3,
          # Below target
          current_quality: 0.88,
          # Above expected
          cost_burn_rate: 1.2,
          estimated_completion: DateTime.add(DateTime.utc_now(), 8, :hour)
        },
        %{
          timestamp: DateTime.utc_now(),
          agent_id: :agent_b,
          task_id: :task_2,
          progress: 0.6,
          # Above target  
          current_quality: 0.91,
          # Below expected
          cost_burn_rate: 0.8,
          estimated_completion: DateTime.add(DateTime.utc_now(), 4, :hour)
        },
        %{
          timestamp: DateTime.utc_now(),
          agent_id: :agent_c,
          task_id: :task_3,
          progress: 0.1,
          # Above target
          current_quality: 0.95,
          # Significantly above expected
          cost_burn_rate: 1.5,
          estimated_completion: DateTime.add(DateTime.utc_now(), 16, :hour)
        }
      ]

      Enum.each(execution_updates, fn update ->
        :ok = Economics.update_allocation_performance(allocation_id, update)
      end)

      # Trigger dynamic rebalancing
      rebalancing_options = %{
        rebalancing_triggers: %{
          cost_variance_threshold: 0.2,
          quality_variance_threshold: 0.1,
          schedule_slip_threshold: 4
        },
        rebalancing_strategies: [
          :agent_substitution,
          :task_redistribution,
          :budget_reallocation,
          :quality_requirement_adjustment
        ]
      }

      {:ok, rebalancing_result} =
        Economics.trigger_dynamic_rebalancing(
          allocation_id,
          rebalancing_options
        )

      # Verify rebalancing decisions
      assert rebalancing_result.rebalancing_triggered == true
      assert length(rebalancing_result.rebalancing_actions) > 0

      # Verify cost overrun mitigation for agent_c
      agent_c_actions =
        Enum.filter(
          rebalancing_result.rebalancing_actions,
          &(&1.target_agent == :agent_c)
        )

      assert length(agent_c_actions) > 0

      cost_mitigation_action =
        Enum.find(
          agent_c_actions,
          &(&1.action_type in [:agent_substitution, :budget_reallocation])
        )

      assert cost_mitigation_action != nil

      # Verify quality improvement for agent_a
      agent_a_actions =
        Enum.filter(
          rebalancing_result.rebalancing_actions,
          &(&1.target_agent == :agent_a)
        )

      quality_improvement_action =
        Enum.find(
          agent_a_actions,
          &(&1.action_type in [:additional_support, :quality_enhancement])
        )

      assert quality_improvement_action != nil

      # Verify updated allocation maintains constraints
      {:ok, updated_allocation} = Economics.get_updated_allocation(allocation_id)
      assert updated_allocation.projected_total_cost <= initial_allocation.total_budget * 1.1

      assert updated_allocation.projected_average_quality >=
               initial_allocation.performance_targets.average_quality
    end
  end

  describe "dynamic pricing mechanisms" do
    test "implements supply-demand responsive pricing", %{economics_pid: _pid} do
      # Create dynamic marketplace with real-time pricing
      marketplace_spec = %{
        name: "Dynamic ML Services Market",
        pricing_model: :dynamic_supply_demand,
        price_adjustment_parameters: %{
          base_adjustment_rate: 0.1,
          demand_elasticity: -0.8,
          supply_elasticity: 1.2,
          price_stability_factor: 0.95,
          maximum_price_change: 0.5
        },
        market_conditions_tracking: %{
          update_frequency_seconds: 30,
          demand_indicators: [:active_requests, :queue_length, :urgency_levels],
          supply_indicators: [:available_agents, :agent_utilization, :capacity_reserve]
        }
      }

      {:ok, marketplace_id} = Economics.create_dynamic_pricing_marketplace(marketplace_spec)

      # Simulate varying market conditions throughout day
      market_scenarios = [
        %{
          scenario: :high_demand_low_supply,
          timestamp: DateTime.utc_now(),
          active_requests: 50,
          available_agents: 10,
          average_urgency: 0.8,
          expected_price_direction: :increase
        },
        %{
          scenario: :low_demand_high_supply,
          timestamp: DateTime.add(DateTime.utc_now(), 2, :hour),
          active_requests: 5,
          available_agents: 25,
          average_urgency: 0.3,
          expected_price_direction: :decrease
        },
        %{
          scenario: :balanced_market,
          timestamp: DateTime.add(DateTime.utc_now(), 4, :hour),
          active_requests: 20,
          available_agents: 18,
          average_urgency: 0.5,
          expected_price_direction: :stable
        }
      ]

      price_history =
        Enum.map(market_scenarios, fn scenario ->
          :ok = Economics.update_market_conditions(marketplace_id, scenario)
          {:ok, pricing_update} = Economics.calculate_dynamic_pricing_update(marketplace_id)

          {scenario.scenario, pricing_update.new_base_price, pricing_update.price_change_factor}
        end)

      # Verify price responsiveness to market conditions
      [
        {_, high_demand_price, high_demand_change},
        {_, low_demand_price, low_demand_change},
        {_, balanced_price, balanced_change}
      ] = price_history

      # High demand should increase prices
      assert high_demand_change > 1.0
      assert high_demand_price > balanced_price

      # Low demand should decrease prices  
      assert low_demand_change < 1.0
      assert low_demand_price < balanced_price

      # Balanced market should have minimal price change
      assert abs(balanced_change - 1.0) < 0.1

      # Verify price stability constraints
      Enum.each(price_history, fn {_, _, change_factor} ->
        # Maximum 50% increase
        assert change_factor <= 1.5
        # Maximum 50% decrease
        assert change_factor >= 0.5
      end)
    end

    test "implements agent-specific performance-based pricing", %{economics_pid: _pid} do
      # Create pricing system that adjusts based on individual agent performance
      performance_pricing_spec = %{
        pricing_strategy: :performance_adjusted,
        base_pricing: %{
          text_generation: 0.02,
          code_generation: 0.05,
          data_analysis: 0.03
        },
        performance_adjustments: %{
          quality_multiplier_range: {0.5, 2.0},
          speed_multiplier_range: {0.7, 1.8},
          reliability_multiplier_range: {0.6, 1.5},
          learning_curve_factor: 0.95
        },
        adjustment_triggers: %{
          minimum_tasks_for_adjustment: 5,
          performance_review_frequency_hours: 24,
          significant_change_threshold: 0.1
        }
      }

      {:ok, pricing_system_id} =
        Economics.create_performance_based_pricing_system(performance_pricing_spec)

      # Initialize agents with different performance characteristics
      agent_performance_data = [
        {:high_performer,
         %{
           completed_tasks: 25,
           average_quality: 0.94,
           # 30% faster than baseline
           average_speed_ratio: 1.3,
           reliability_score: 0.96,
           service_type: :text_generation
         }},
        {:average_performer,
         %{
           completed_tasks: 15,
           average_quality: 0.82,
           average_speed_ratio: 1.0,
           reliability_score: 0.88,
           service_type: :text_generation
         }},
        {:inconsistent_performer,
         %{
           completed_tasks: 20,
           average_quality: 0.75,
           average_speed_ratio: 0.8,
           reliability_score: 0.65,
           service_type: :text_generation
         }}
      ]

      performance_pricing_results =
        Enum.map(agent_performance_data, fn {agent_id, perf_data} ->
          Economics.initialize_agent_reputation(agent_id, %{
            initial_score: 0.8,
            performance_history: [perf_data],
            specializations: [perf_data.service_type]
          })

          {:ok, personalized_pricing} =
            Economics.calculate_performance_adjusted_pricing(
              pricing_system_id,
              agent_id,
              perf_data.service_type
            )

          {agent_id, personalized_pricing}
        end)

      # Verify performance-based pricing adjustments
      base_price = performance_pricing_spec.base_pricing.text_generation

      [
        {:high_performer, high_perf_pricing},
        {:average_performer, avg_perf_pricing},
        {:inconsistent_performer, low_perf_pricing}
      ] = performance_pricing_results

      # High performer should get premium pricing
      assert high_perf_pricing.adjusted_price > base_price
      assert high_perf_pricing.quality_multiplier > 1.0
      assert high_perf_pricing.speed_multiplier > 1.0
      assert high_perf_pricing.reliability_multiplier > 1.0

      # Average performer should get near-base pricing
      assert abs(avg_perf_pricing.adjusted_price - base_price) < base_price * 0.2

      # Inconsistent performer should get discounted pricing
      assert low_perf_pricing.adjusted_price < base_price
      assert low_perf_pricing.reliability_multiplier < 1.0

      # Verify continuous learning adjustment
      # Simulate high performer completing more tasks with continued excellence
      additional_performance = %{
        completed_tasks: 10,
        average_quality: 0.96,
        average_speed_ratio: 1.4,
        reliability_score: 0.98
      }

      :ok = Economics.update_agent_performance_data(:high_performer, additional_performance)

      {:ok, updated_pricing} =
        Economics.calculate_performance_adjusted_pricing(
          pricing_system_id,
          :high_performer,
          :text_generation
        )

      # Updated pricing should reflect continued improvement
      assert updated_pricing.adjusted_price >= high_perf_pricing.adjusted_price
      assert updated_pricing.confidence_level > high_perf_pricing.confidence_level
    end
  end

  describe "economic fault tolerance" do
    test "implements financial penalties for malicious behavior", %{economics_pid: _pid} do
      # Create system with staking and slashing for fault tolerance
      fault_tolerance_spec = %{
        stake_requirements: %{
          minimum_stake: 100.0,
          stake_multiplier_by_reputation: %{
            # 20% discount for high reputation
            high: 0.8,
            medium: 1.0,
            # 50% penalty for low reputation
            low: 1.5
          }
        },
        slashing_conditions: [
          %{violation: :task_abandonment, penalty_rate: 0.1},
          %{violation: :quality_fraud, penalty_rate: 0.25},
          %{violation: :timing_manipulation, penalty_rate: 0.15},
          %{violation: :collusion_detected, penalty_rate: 0.3},
          %{violation: :sybil_attack, penalty_rate: 0.5}
        ],
        recovery_mechanisms: %{
          reputation_recovery_enabled: true,
          stake_restoration_period_days: 30,
          progressive_penalty_reduction: 0.1
        }
      }

      {:ok, fault_system_id} =
        Economics.create_economic_fault_tolerance_system(fault_tolerance_spec)

      # Initialize agents with stakes
      agents_with_stakes = [
        # High rep discount
        {:reliable_agent, %{reputation: 0.9, stake_amount: 80.0}},
        # Standard stake
        {:average_agent, %{reputation: 0.7, stake_amount: 100.0}},
        # Low rep penalty
        {:risky_agent, %{reputation: 0.4, stake_amount: 150.0}}
      ]

      Enum.each(agents_with_stakes, fn {agent_id, agent_data} ->
        Economics.initialize_agent_reputation(agent_id, %{
          initial_score: agent_data.reputation
        })

        {:ok, stake_id} =
          Economics.stake_agent_funds(
            fault_system_id,
            agent_id,
            agent_data.stake_amount
          )

        assert stake_id != nil
      end)

      # Simulate malicious behavior and apply slashing
      malicious_scenarios = [
        %{
          agent_id: :risky_agent,
          violation: :quality_fraud,
          evidence: %{
            submitted_quality: 0.9,
            actual_quality: 0.3,
            fraud_confidence: 0.95
          },
          expected_penalty_rate: 0.25
        },
        %{
          agent_id: :average_agent,
          violation: :task_abandonment,
          evidence: %{
            task_progress: 0.6,
            abandonment_reason: :better_offer_elsewhere,
            notice_period_hours: 0
          },
          expected_penalty_rate: 0.1
        }
      ]

      slashing_results =
        Enum.map(malicious_scenarios, fn scenario ->
          {:ok, violation_id} =
            Economics.report_violation(
              fault_system_id,
              scenario.agent_id,
              scenario.violation,
              scenario.evidence
            )

          {:ok, slashing_result} = Economics.execute_slashing(fault_system_id, violation_id)

          {scenario.agent_id, scenario.violation, slashing_result}
        end)

      # Verify slashing execution
      [
        {_risky_agent_result, _quality_fraud, risky_slashing},
        {_average_agent_result, _task_abandonment, average_slashing}
      ] = slashing_results

      # Verify quality fraud penalty
      assert risky_slashing.penalty_applied == true
      assert risky_slashing.slashed_amount >= 150.0 * 0.25
      assert risky_slashing.remaining_stake < 150.0

      # Verify task abandonment penalty  
      assert average_slashing.penalty_applied == true
      assert average_slashing.slashed_amount >= 100.0 * 0.1
      assert average_slashing.remaining_stake < 100.0

      # Verify reputation impact
      {:ok, risky_rep_after} = Economics.get_agent_reputation(:risky_agent)
      {:ok, avg_rep_after} = Economics.get_agent_reputation(:average_agent)

      assert risky_rep_after.reputation_score < 0.4
      assert avg_rep_after.reputation_score < 0.7

      # Test recovery mechanism
      # Simulate halfway through recovery period
      recovery_period_days = 15

      {:ok, recovery_status} =
        Economics.check_stake_recovery_eligibility(
          fault_system_id,
          :average_agent,
          recovery_period_days
        )

      assert recovery_status.eligible_for_partial_recovery == true
      assert recovery_status.potential_recovery_amount > 0
      assert recovery_status.remaining_recovery_days > 0
    end

    test "implements insurance and compensation mechanisms", %{economics_pid: _pid} do
      # Create insurance system for protection against agent failures
      insurance_spec = %{
        insurance_pool_size: 10000.0,
        coverage_types: [
          %{type: :task_completion_failure, coverage_rate: 0.8, premium_rate: 0.02},
          %{type: :quality_shortfall, coverage_rate: 0.6, premium_rate: 0.015},
          %{type: :deadline_miss, coverage_rate: 0.7, premium_rate: 0.01},
          %{type: :data_breach, coverage_rate: 1.0, premium_rate: 0.05}
        ],
        claim_requirements: %{
          minimum_evidence_confidence: 0.8,
          claim_review_period_hours: 48,
          appeals_allowed: 2
        },
        risk_assessment: %{
          agent_reputation_factor: 0.4,
          task_complexity_factor: 0.3,
          historical_failure_rate: 0.3
        }
      }

      {:ok, insurance_system_id} = Economics.create_insurance_system(insurance_spec)

      # Client purchases insurance for critical task
      critical_task = %{
        task_id: "critical_ml_model_training",
        client_id: :enterprise_client,
        estimated_value: 5000.0,
        completion_deadline: DateTime.add(DateTime.utc_now(), 72, :hour),
        quality_requirements: %{minimum_accuracy: 0.92},
        assigned_agent: :specialist_agent
      }

      Economics.initialize_agent_reputation(:specialist_agent, %{
        initial_score: 0.85,
        specializations: [:ml_model_training],
        failure_history: []
      })

      # Calculate insurance premium based on risk assessment
      {:ok, _risk_assessment} =
        Economics.assess_task_risk(
          insurance_system_id,
          critical_task
        )

      {:ok, insurance_policy_id} =
        Economics.purchase_task_insurance(
          insurance_system_id,
          critical_task,
          [:task_completion_failure, :quality_shortfall, :deadline_miss]
        )

      # Simulate agent failure scenario
      failure_scenario = %{
        failure_type: :quality_shortfall,
        responsible_agent: :specialist_agent,
        actual_outcome: %{
          task_completed: true,
          # Below 0.92 requirement
          actual_accuracy: 0.87,
          completion_time: DateTime.add(DateTime.utc_now(), 71, :hour),
          quality_gap: 0.05
        },
        evidence: %{
          model_evaluation_results: %{accuracy: 0.87, precision: 0.89, recall: 0.85},
          independent_validation: true,
          client_acceptance: false
        }
      }

      {:ok, claim_id} =
        Economics.file_insurance_claim(
          insurance_system_id,
          insurance_policy_id,
          failure_scenario
        )

      # Process claim
      {:ok, claim_decision} =
        Economics.process_insurance_claim(
          insurance_system_id,
          claim_id
        )

      # Verify claim processing
      assert claim_decision.claim_approved == true
      assert claim_decision.payout_amount > 0

      coverage_type = Enum.find(insurance_spec.coverage_types, &(&1.type == :quality_shortfall))
      # Proportional to quality gap
      expected_payout =
        critical_task.estimated_value * coverage_type.coverage_rate *
          failure_scenario.actual_outcome.quality_gap / 0.05

      assert claim_decision.payout_amount >= expected_payout * 0.8
      assert claim_decision.payout_amount <= expected_payout * 1.2

      # Verify insurance pool impact and agent penalties
      {:ok, pool_status} = Economics.get_insurance_pool_status(insurance_system_id)
      assert pool_status.total_claims_paid > 0
      assert pool_status.remaining_pool_size < insurance_spec.insurance_pool_size

      # Verify agent reputation and stake impact
      {:ok, agent_rep_after_claim} = Economics.get_agent_reputation(:specialist_agent)
      assert agent_rep_after_claim.reputation_score < 0.85
      assert length(agent_rep_after_claim.failure_history) == 1
    end

    test "implements systemic risk protection and circuit breakers", %{economics_pid: _pid} do
      # Create system-wide protection against cascading failures
      systemic_protection_spec = %{
        circuit_breaker_thresholds: %{
          # 15% of agents failing
          agent_failure_rate: 0.15,
          # 30% price swings
          market_volatility: 0.3,
          # 20% coordination failures
          coordination_failure_rate: 0.2,
          # Average reputation below 0.4
          reputation_collapse_threshold: 0.4
        },
        protection_mechanisms: [
          :emergency_agent_pool_activation,
          :dynamic_task_redistribution,
          :pricing_stabilization,
          :reputation_score_freezing,
          :insurance_pool_emergency_funding
        ],
        recovery_procedures: %{
          gradual_reactivation: true,
          system_health_verification: true,
          post_incident_analysis: true
        }
      }

      {:ok, protection_system_id} =
        Economics.create_systemic_protection_system(systemic_protection_spec)

      # Simulate systemic stress conditions
      stress_scenario = %{
        scenario_type: :market_shock,
        initial_conditions: %{
          active_agents: 50,
          average_reputation: 0.75,
          market_stability: 0.8,
          coordination_success_rate: 0.9
        },
        stress_events: [
          %{
            event: :mass_agent_exodus,
            impact: %{agent_count_reduction: 0.4, reputation_impact: -0.1}
          },
          %{
            event: :coordination_system_bug,
            impact: %{coordination_failure_spike: 0.35, market_confidence: -0.3}
          },
          %{
            event: :reputation_attack,
            impact: %{targeted_reputation_damage: -0.5, affected_agents: 15}
          }
        ]
      }

      # Execute stress scenario
      Enum.each(stress_scenario.stress_events, fn stress_event ->
        :ok = Economics.simulate_stress_event(protection_system_id, stress_event)
      end)

      # Check if circuit breakers are triggered
      {:ok, system_health} = Economics.assess_system_health(protection_system_id)

      # Verify circuit breaker activation
      triggered_breakers = system_health.triggered_circuit_breakers
      assert length(triggered_breakers) > 0
      assert :agent_failure_rate in triggered_breakers
      assert :coordination_failure_rate in triggered_breakers

      # Verify protection mechanism activation
      {:ok, protection_status} = Economics.get_active_protection_mechanisms(protection_system_id)

      assert protection_status.emergency_agent_pool_activated == true
      assert protection_status.task_redistribution_active == true
      assert protection_status.pricing_stabilization_active == true

      # Test system recovery
      recovery_actions = [
        :restore_agent_pool,
        :fix_coordination_bugs,
        :implement_reputation_recovery,
        :stabilize_market_conditions
      ]

      Enum.each(recovery_actions, fn action ->
        :ok = Economics.execute_recovery_action(protection_system_id, action)
      end)

      # Verify gradual system recovery
      {:ok, recovery_status} = Economics.assess_recovery_progress(protection_system_id)

      assert recovery_status.system_health_score > system_health.overall_health_score
      assert recovery_status.circuit_breakers_cleared > 0
      assert recovery_status.protection_mechanisms_deactivated > 0

      # Verify post-incident analysis
      {:ok, incident_report} = Economics.generate_incident_analysis(protection_system_id)

      assert incident_report.root_causes != []
      assert incident_report.impact_assessment != nil
      assert incident_report.prevention_recommendations != []
      assert incident_report.system_improvements != []
    end
  end
end
