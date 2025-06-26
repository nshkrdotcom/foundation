defmodule MABEAM.EconomicsTest do
  use ExUnit.Case, async: true

  alias MABEAM.Economics

  setup do
    case Economics.start_link(test_mode: true) do
      {:ok, pid} -> %{economics_pid: pid}
      {:error, {:already_started, pid}} -> %{economics_pid: pid}
    end
  end

  describe "auction management" do
    test "creates auction successfully", %{economics_pid: _pid} do
      auction_spec = %{
        type: :english,
        item: %{
          task: :model_training,
          dataset_size: 1_000_000,
          model_type: :neural_network,
          max_training_time: 3600,
          quality_threshold: 0.95
        },
        reserve_price: 10.0,
        duration_minutes: 30
      }

      {:ok, auction_id} = Economics.create_auction(auction_spec)
      assert is_binary(auction_id)

      {:ok, auction} = Economics.get_auction(auction_id)
      assert auction.type == :english
      assert auction.status == :open
    end

    test "places bid successfully", %{economics_pid: _pid} do
      auction_spec = %{
        type: :english,
        item: %{task: :model_training},
        reserve_price: 10.0,
        duration_minutes: 30
      }

      {:ok, auction_id} = Economics.create_auction(auction_spec)

      bid_spec = %{
        price: 15.0,
        quality_guarantee: 0.97,
        completion_time: 1800
      }

      {:ok, bid_id} = Economics.place_bid(auction_id, :test_agent, bid_spec)
      assert is_binary(bid_id)
    end

    test "closes auction and determines winner", %{economics_pid: _pid} do
      auction_spec = %{
        type: :english,
        item: %{task: :model_training},
        reserve_price: 10.0,
        duration_minutes: 30
      }

      {:ok, auction_id} = Economics.create_auction(auction_spec)

      {:ok, _bid_id1} =
        Economics.place_bid(auction_id, :agent1, %{
          price: 15.0,
          quality_guarantee: 0.95,
          completion_time: 2000
        })

      {:ok, _bid_id2} =
        Economics.place_bid(auction_id, :agent2, %{
          price: 20.0,
          quality_guarantee: 0.97,
          completion_time: 1800
        })

      {:ok, results} = Economics.close_auction(auction_id)
      assert results.winner == :agent2
      assert results.winning_price == 20.0
    end

    test "handles different auction types" do
      auction_types = [:english, :dutch, :sealed_bid, :vickrey, :combinatorial]

      for auction_type <- auction_types do
        auction_spec = %{
          type: auction_type,
          item: %{task: :model_training},
          reserve_price: 10.0,
          duration_minutes: 30
        }

        {:ok, auction_id} = Economics.create_auction(auction_spec)
        {:ok, auction} = Economics.get_auction(auction_id)
        assert auction.type == auction_type
      end
    end

    test "validates auction parameters" do
      invalid_spec = %{
        type: :invalid_type,
        item: %{task: :model_training},
        reserve_price: -10.0,
        duration_minutes: 0
      }

      {:error, reason} = Economics.create_auction(invalid_spec)
      assert reason =~ "invalid"
    end
  end

  describe "marketplace management" do
    test "creates marketplace successfully", %{economics_pid: _pid} do
      marketplace_spec = %{
        name: "ML Services Exchange",
        categories: [:text_generation, :code_generation, :data_analysis],
        fee_structure: %{listing_fee: 0.1, transaction_fee: 0.05},
        quality_enforcement: true
      }

      {:ok, marketplace_id} = Economics.create_marketplace(marketplace_spec)
      assert is_binary(marketplace_id)

      {:ok, marketplace} = Economics.get_marketplace(marketplace_id)
      assert marketplace.name == "ML Services Exchange"
      assert marketplace.status == :active
    end

    test "lists service in marketplace", %{economics_pid: _pid} do
      marketplace_spec = %{
        name: "Test Marketplace",
        categories: [:text_generation],
        fee_structure: %{listing_fee: 0.1, transaction_fee: 0.05},
        quality_enforcement: true
      }

      {:ok, marketplace_id} = Economics.create_marketplace(marketplace_spec)

      service_spec = %{
        provider: :claude_agent,
        service_type: :text_generation,
        capabilities: [:summarization, :translation],
        pricing: %{base_rate: 0.02, per_token: 0.001},
        quality_guarantees: %{accuracy: 0.95, response_time: 2000}
      }

      {:ok, listing_id} = Economics.list_service(marketplace_id, service_spec)
      assert is_binary(listing_id)
    end

    test "handles service transactions", %{economics_pid: _pid} do
      marketplace_spec = %{
        name: "Test Marketplace",
        categories: [:text_generation],
        fee_structure: %{listing_fee: 0.1, transaction_fee: 0.05},
        quality_enforcement: true
      }

      {:ok, marketplace_id} = Economics.create_marketplace(marketplace_spec)

      service_spec = %{
        provider: :claude_agent,
        service_type: :text_generation,
        capabilities: [:summarization],
        pricing: %{base_rate: 0.02, per_token: 0.001},
        quality_guarantees: %{accuracy: 0.95, response_time: 2000}
      }

      {:ok, listing_id} = Economics.list_service(marketplace_id, service_spec)

      transaction_request = %{
        buyer: :test_buyer,
        service_requirements: %{
          task: "Summarize this document",
          max_cost: 5.0,
          deadline: DateTime.add(DateTime.utc_now(), 3600)
        }
      }

      {:ok, transaction_id} = Economics.request_service(listing_id, transaction_request)
      assert is_binary(transaction_id)
    end
  end

  describe "reputation system" do
    test "tracks agent reputation", %{economics_pid: _pid} do
      # Initialize agent reputation
      :ok =
        Economics.initialize_agent_reputation(:test_agent, %{
          initial_score: 0.8,
          specializations: [:text_generation, :code_generation],
          performance_history: []
        })

      {:ok, reputation} = Economics.get_agent_reputation(:test_agent)
      assert reputation.overall_score == 0.8
      assert :text_generation in reputation.specializations
    end

    test "updates reputation based on performance", %{economics_pid: _pid} do
      :ok =
        Economics.initialize_agent_reputation(:test_agent, %{
          initial_score: 0.8,
          specializations: [:text_generation],
          performance_history: []
        })

      performance_record = %{
        task_id: "task_123",
        task_type: :text_generation,
        quality_score: 0.95,
        cost_efficiency: 0.9,
        completion_time_ms: 1500,
        client_satisfaction: 0.92,
        timestamp: DateTime.utc_now()
      }

      :ok = Economics.update_agent_reputation(:test_agent, performance_record)

      {:ok, updated_reputation} = Economics.get_agent_reputation(:test_agent)
      assert updated_reputation.overall_score > 0.8
      assert length(updated_reputation.performance_history) == 1
    end

    test "handles reputation decay over time", %{economics_pid: _pid} do
      :ok =
        Economics.initialize_agent_reputation(:test_agent, %{
          initial_score: 0.9,
          specializations: [:text_generation],
          performance_history: []
        })

      # Simulate reputation decay
      :ok =
        Economics.apply_reputation_decay(:test_agent, %{
          decay_factor: 0.99,
          time_period_days: 30
        })

      {:ok, reputation} = Economics.get_agent_reputation(:test_agent)
      assert reputation.overall_score < 0.9
    end

    test "prevents reputation gaming", %{economics_pid: _pid} do
      :ok =
        Economics.initialize_agent_reputation(:test_agent, %{
          initial_score: 0.5,
          specializations: [:text_generation],
          performance_history: []
        })

      # Try to submit multiple identical performance records (should be detected)
      performance_record = %{
        task_id: "task_123",
        task_type: :text_generation,
        quality_score: 1.0,
        cost_efficiency: 1.0,
        completion_time_ms: 100,
        client_satisfaction: 1.0,
        timestamp: DateTime.utc_now()
      }

      :ok = Economics.update_agent_reputation(:test_agent, performance_record)

      # Second identical submission should be rejected or heavily weighted down
      {:error, reason} = Economics.update_agent_reputation(:test_agent, performance_record)
      assert reason =~ "gaming"
    end
  end

  describe "incentive mechanisms" do
    test "implements performance-based rewards", %{economics_pid: _pid} do
      incentive_config = %{
        base_reward: 1.0,
        quality_multiplier: 2.0,
        speed_multiplier: 1.5,
        cost_efficiency_multiplier: 1.2
      }

      performance_metrics = %{
        quality_score: 0.95,
        completion_speed_ratio: 1.2,
        cost_efficiency: 0.9
      }

      {:ok, reward} = Economics.calculate_performance_reward(incentive_config, performance_metrics)
      # Should be higher than base reward
      assert reward > 1.0
    end

    test "handles budget constraints", %{economics_pid: _pid} do
      budget_constraints = %{
        total_budget: 100.0,
        max_per_task: 20.0,
        reserve_percentage: 0.1
      }

      task_cost_estimate = 25.0

      {:error, reason} =
        Economics.validate_budget_constraints(budget_constraints, task_cost_estimate)

      assert reason =~ "exceeds maximum per-task budget"
    end

    test "optimizes cost allocation", %{economics_pid: _pid} do
      tasks = [
        %{
          id: "task_1",
          estimated_cost: 10.0,
          priority: :high,
          deadline: DateTime.add(DateTime.utc_now(), 3600)
        },
        %{
          id: "task_2",
          estimated_cost: 15.0,
          priority: :medium,
          deadline: DateTime.add(DateTime.utc_now(), 7200)
        },
        %{
          id: "task_3",
          estimated_cost: 8.0,
          priority: :low,
          deadline: DateTime.add(DateTime.utc_now(), 10800)
        }
      ]

      budget_limit = 25.0

      {:ok, allocation} = Economics.optimize_cost_allocation(tasks, budget_limit)

      total_allocated =
        allocation.allocated_tasks
        |> Enum.map(& &1.estimated_cost)
        |> Enum.sum()

      assert total_allocated <= budget_limit
      assert length(allocation.allocated_tasks) > 0
    end
  end

  describe "market dynamics" do
    test "implements supply and demand pricing", %{economics_pid: _pid} do
      market_conditions = %{
        service_type: :text_generation,
        available_providers: 5,
        pending_requests: 20,
        average_quality: 0.9,
        base_price: 0.02
      }

      {:ok, dynamic_price} = Economics.calculate_dynamic_pricing(market_conditions)
      # High demand should increase price
      assert dynamic_price > market_conditions.base_price
    end

    test "handles market maker operations", %{economics_pid: _pid} do
      market_spec = %{
        service_type: :text_generation,
        initial_liquidity: 1000.0,
        spread_percentage: 0.05,
        max_position_size: 100.0
      }

      {:ok, market_id} = Economics.create_market_maker(market_spec)

      # Test buy order
      buy_order = %{
        quantity: 10,
        max_price: 0.025,
        urgency: :normal
      }

      {:ok, order_id} = Economics.submit_market_order(market_id, :buy, buy_order)
      assert is_binary(order_id)
    end

    test "implements prediction markets", %{economics_pid: _pid} do
      prediction_spec = %{
        question: "Will this ML model achieve >95% accuracy?",
        resolution_criteria: "Model performance on test set",
        resolution_deadline: DateTime.add(DateTime.utc_now(), 86400),
        initial_probability: 0.7
      }

      {:ok, market_id} = Economics.create_prediction_market(prediction_spec)

      # Place prediction bet
      bet_spec = %{
        outcome: :yes,
        amount: 10.0,
        odds: 0.8
      }

      {:ok, bet_id} = Economics.place_prediction_bet(market_id, :test_agent, bet_spec)
      assert is_binary(bet_id)
    end
  end

  describe "economics statistics and analytics" do
    test "provides market statistics", %{economics_pid: _pid} do
      # Create some market activity first
      auction_spec = %{
        type: :english,
        item: %{task: :model_training},
        reserve_price: 10.0,
        duration_minutes: 30
      }

      {:ok, _auction_id} = Economics.create_auction(auction_spec)

      {:ok, stats} = Economics.get_market_statistics()

      assert Map.has_key?(stats, :total_auctions)
      assert Map.has_key?(stats, :average_auction_value)
      assert Map.has_key?(stats, :market_efficiency_score)
      assert is_number(stats.total_auctions)
    end

    test "tracks economic performance metrics", %{economics_pid: _pid} do
      {:ok, metrics} = Economics.get_performance_metrics()

      assert Map.has_key?(metrics, :total_transactions)
      assert Map.has_key?(metrics, :average_transaction_time)
      assert Map.has_key?(metrics, :cost_efficiency_trend)
      assert Map.has_key?(metrics, :agent_satisfaction_score)
    end

    test "generates economic insights", %{economics_pid: _pid} do
      time_range = %{
        start_date: DateTime.add(DateTime.utc_now(), -86400),
        end_date: DateTime.utc_now()
      }

      {:ok, insights} = Economics.generate_economic_insights(time_range)

      assert Map.has_key?(insights, :market_trends)
      assert Map.has_key?(insights, :cost_optimization_opportunities)
      assert Map.has_key?(insights, :agent_performance_rankings)
      assert Map.has_key?(insights, :recommendations)
    end
  end

  describe "integration and error handling" do
    test "handles concurrent auction operations" do
      # Start multiple auctions concurrently
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            auction_spec = %{
              type: :english,
              item: %{task: "task_#{i}"},
              reserve_price: 10.0 + i,
              duration_minutes: 30
            }

            Economics.create_auction(auction_spec)
          end)
        end

      results = Task.await_many(tasks, 5000)

      # All should succeed
      assert Enum.all?(results, fn
               {:ok, _auction_id} -> true
               _ -> false
             end)
    end

    test "validates economic constraints", %{economics_pid: _pid} do
      # Test with invalid economic parameters
      invalid_specs = [
        %{type: :english, item: %{task: :test}, reserve_price: -10.0, duration_minutes: 30},
        %{type: :invalid, item: %{task: :test}, reserve_price: 10.0, duration_minutes: 30},
        %{type: :english, item: %{}, reserve_price: 10.0, duration_minutes: 0}
      ]

      for spec <- invalid_specs do
        {:error, _reason} = Economics.create_auction(spec)
      end
    end

    test "maintains economic system integrity under stress" do
      # Stress test the economic system
      num_operations = 100

      operations =
        for i <- 1..num_operations do
          Task.async(fn ->
            case rem(i, 3) do
              0 ->
                auction_spec = %{
                  type: :english,
                  item: %{task: "stress_task_#{i}"},
                  reserve_price: :rand.uniform(100),
                  duration_minutes: 30
                }

                Economics.create_auction(auction_spec)

              1 ->
                Economics.initialize_agent_reputation(String.to_atom("agent_#{i}"), %{
                  initial_score: :rand.uniform(),
                  specializations: [:text_generation],
                  performance_history: []
                })

              2 ->
                Economics.get_market_statistics()
            end
          end)
        end

      results = Task.await_many(operations, 10000)

      # Most operations should succeed (allowing for some validation failures)
      success_rate =
        Enum.count(results, fn
          {:ok, _} -> true
          :ok -> true
          _ -> false
        end) / length(results)

      assert success_rate > 0.8
    end
  end
end
