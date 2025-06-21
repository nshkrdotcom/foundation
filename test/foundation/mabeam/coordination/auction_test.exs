# test/foundation/mabeam/coordination/auction_test.exs
defmodule Foundation.MABEAM.Coordination.AuctionTest do
  @moduledoc """
  Comprehensive test suite for auction-based coordination mechanisms.

  Tests multiple auction types including:
  - Sealed-bid auctions (first and second price)
  - English (ascending) auctions 
  - Dutch (descending) auctions
  - Combinatorial auctions
  """

  use ExUnit.Case, async: false

  alias Foundation.MABEAM.Coordination.Auction

  setup do
    # Start AgentRegistry if not already started
    case Foundation.MABEAM.AgentRegistry.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Start Coordination service if not already started
    case Foundation.MABEAM.Coordination.start_link() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    # Register test agents for auction scenarios with proper agent_config format
    test_agents = [
      {:bidder1,
       %{
         id: :bidder1,
         type: :test_agent,
         module: TestAgent,
         config: %{priority: :high, budget: 100.0},
         supervision: %{strategy: :one_for_one, max_restarts: 3, max_seconds: 60}
       }},
      {:bidder2,
       %{
         id: :bidder2,
         type: :test_agent,
         module: TestAgent,
         config: %{priority: :medium, budget: 80.0},
         supervision: %{strategy: :one_for_one, max_restarts: 3, max_seconds: 60}
       }},
      {:bidder3,
       %{
         id: :bidder3,
         type: :test_agent,
         module: TestAgent,
         config: %{priority: :low, budget: 60.0},
         supervision: %{strategy: :one_for_one, max_restarts: 3, max_seconds: 60}
       }},
      {:bidder4,
       %{
         id: :bidder4,
         type: :test_agent,
         module: TestAgent,
         config: %{priority: :medium, budget: 90.0},
         supervision: %{strategy: :one_for_one, max_restarts: 3, max_seconds: 60}
       }}
    ]

    Enum.each(test_agents, fn {agent_id, config} ->
      Foundation.MABEAM.AgentRegistry.register_agent(agent_id, config)
    end)

    # Register auction protocol for integration tests
    Foundation.MABEAM.Coordination.Auction.register_auction_protocol(:auction_protocol,
      auction_type: :sealed_bid,
      payment_rule: :second_price
    )

    on_exit(fn ->
      # Clean up test agents
      Enum.each(test_agents, fn {agent_id, _config} ->
        try do
          Foundation.MABEAM.AgentRegistry.deregister_agent(agent_id)
        catch
          # Registry already stopped
          :exit, _ -> :ok
        end
      end)
    end)

    {:ok, agents: Keyword.keys(test_agents)}
  end

  describe "sealed bid auctions" do
    test "first price sealed bid auction selects highest bidder", %{agents: _agents} do
      bids = [
        {:bidder1, %{bid: 10.0, value: 0.8}},
        {:bidder2, %{bid: 15.0, value: 0.9}},
        {:bidder3, %{bid: 12.0, value: 0.7}}
      ]

      {:ok, result} =
        Auction.run_auction(:temperature_setting, bids,
          auction_type: :sealed_bid,
          payment_rule: :first_price
        )

      assert result.winner == :bidder2
      assert result.winning_value == 0.9
      assert result.payment == 15.0
      assert result.auction_type == :sealed_bid
      assert result.participants == 3
      assert result.efficiency > 0.0
    end

    test "second price sealed bid auction uses second highest bid for payment", %{agents: _agents} do
      bids = [
        {:bidder1, %{bid: 10.0, value: 0.8}},
        {:bidder2, %{bid: 15.0, value: 0.9}},
        {:bidder3, %{bid: 12.0, value: 0.7}}
      ]

      {:ok, result} =
        Auction.run_auction(:resource_allocation, bids,
          auction_type: :sealed_bid,
          payment_rule: :second_price
        )

      assert result.winner == :bidder2
      assert result.winning_value == 0.9
      # Second highest bid
      assert result.payment == 12.0
      assert result.auction_type == :sealed_bid
      assert result.participants == 3
    end

    test "sealed bid auction handles tie by selecting first bidder" do
      bids = [
        {:bidder1, %{bid: 15.0, value: 0.8}},
        {:bidder2, %{bid: 15.0, value: 0.9}},
        {:bidder3, %{bid: 12.0, value: 0.7}}
      ]

      {:ok, result} =
        Auction.run_auction(:tied_resource, bids,
          auction_type: :sealed_bid,
          payment_rule: :first_price
        )

      # First in tie wins
      assert result.winner == :bidder1
      assert result.payment == 15.0
      assert result.tie_broken == true
    end

    test "sealed bid auction handles empty bids" do
      {:ok, result} =
        Auction.run_auction(:empty_auction, [],
          auction_type: :sealed_bid,
          payment_rule: :first_price
        )

      assert result.winner == nil
      assert result.payment == 0.0
      assert result.participants == 0
      assert result.auction_type == :sealed_bid
    end

    test "sealed bid auction validates bid format" do
      invalid_bids = [
        # Missing bid
        {:bidder1, %{value: 0.8}},
        # Missing value
        {:bidder2, %{bid: 15.0}}
      ]

      assert {:error, :invalid_bid_format} =
               Auction.run_auction(:invalid_bids, invalid_bids,
                 auction_type: :sealed_bid,
                 payment_rule: :first_price
               )
    end
  end

  describe "english auctions" do
    test "ascending price auction with multiple rounds", %{agents: agents} do
      {:ok, result} =
        Auction.run_auction(:cpu_allocation, agents,
          auction_type: :english,
          starting_price: 5.0,
          increment: 1.0,
          max_rounds: 10
        )

      assert result.auction_type == :english
      assert result.payment >= 5.0
      assert result.rounds <= 10
      assert result.rounds > 0
      assert result.winner != nil
      assert result.participants == length(agents)
    end

    test "english auction stops when only one bidder remains" do
      {:ok, result} =
        Auction.run_auction(:quick_english, [:bidder1, :bidder2],
          auction_type: :english,
          # High starting price
          starting_price: 50.0,
          increment: 10.0,
          max_rounds: 5
        )

      assert result.auction_type == :english
      assert result.winner != nil
      assert result.rounds <= result.max_rounds
      assert result.payment >= 50.0
    end

    test "english auction handles max rounds reached" do
      {:ok, result} =
        Auction.run_auction(:stubborn_bidders, [:bidder1, :bidder2, :bidder3],
          auction_type: :english,
          starting_price: 1.0,
          increment: 1.0,
          # Limited rounds
          max_rounds: 3
        )

      assert result.auction_type == :english
      assert result.rounds == 3
      # Someone wins even at max rounds
      assert result.winner != nil
      assert result.payment >= 1.0
    end

    test "english auction with single bidder" do
      {:ok, result} =
        Auction.run_auction(:single_bidder, [:bidder1],
          auction_type: :english,
          starting_price: 10.0,
          increment: 5.0,
          max_rounds: 5
        )

      assert result.auction_type == :english
      assert result.winner == :bidder1
      # Starting price
      assert result.payment == 10.0
      assert result.rounds == 1
      assert result.participants == 1
    end
  end

  describe "dutch auctions" do
    test "descending price auction stops at first acceptance" do
      {:ok, result} =
        Auction.run_auction(:dutch_resource, [:bidder1, :bidder2, :bidder3],
          auction_type: :dutch,
          starting_price: 100.0,
          decrement: 5.0,
          reserve_price: 20.0,
          max_rounds: 20
        )

      assert result.auction_type == :dutch
      assert result.payment <= 100.0
      assert result.payment >= 20.0
      assert result.winner != nil
      assert result.rounds > 0
      assert result.rounds <= 20
    end

    test "dutch auction reaches reserve price" do
      {:ok, result} =
        Auction.run_auction(:high_reserve, [:bidder1, :bidder2],
          auction_type: :dutch,
          starting_price: 50.0,
          decrement: 10.0,
          # High reserve
          reserve_price: 45.0,
          max_rounds: 10
        )

      assert result.auction_type == :dutch
      # Should either win before reserve or fail to sell
      assert result.payment >= 45.0 or result.winner == nil
    end

    test "dutch auction with no acceptable price" do
      {:ok, result} =
        Auction.run_auction(:no_buyers, [:bidder1],
          auction_type: :dutch,
          # Very high starting price
          starting_price: 200.0,
          decrement: 5.0,
          # Still too high  
          reserve_price: 150.0,
          max_rounds: 10
        )

      assert result.auction_type == :dutch
      # No sale
      assert result.winner == nil
      assert result.payment == 0.0
      assert result.rounds <= 10
    end
  end

  describe "combinatorial auctions" do
    test "combinatorial auction allocates bundle of resources" do
      # Bids for combinations of resources
      combination_bids = [
        {:bidder1,
         %{
           bid: 25.0,
           bundle: [:cpu, :memory],
           value: 0.8
         }},
        {:bidder2,
         %{
           bid: 30.0,
           bundle: [:cpu, :memory, :storage],
           value: 0.9
         }},
        {:bidder3,
         %{
           bid: 15.0,
           bundle: [:memory],
           value: 0.7
         }}
      ]

      {:ok, result} =
        Auction.run_auction(:resource_bundle, combination_bids,
          auction_type: :combinatorial,
          available_resources: [:cpu, :memory, :storage]
        )

      assert result.auction_type == :combinatorial
      assert result.winner != nil
      assert result.allocated_bundle != nil
      assert result.payment > 0.0
      assert result.participants == 3
    end

    test "combinatorial auction handles conflicting bundles" do
      conflicting_bids = [
        {:bidder1,
         %{
           bid: 20.0,
           bundle: [:cpu, :memory],
           value: 0.8
         }},
        {:bidder2,
         %{
           bid: 25.0,
           # Conflicts on CPU
           bundle: [:cpu, :storage],
           value: 0.9
         }}
      ]

      {:ok, result} =
        Auction.run_auction(:conflicting_bundles, conflicting_bids,
          auction_type: :combinatorial,
          available_resources: [:cpu, :memory, :storage]
        )

      assert result.auction_type == :combinatorial
      assert result.winner != nil
      # Higher bidder should win
      assert result.winner == :bidder2
      assert result.allocated_bundle == [:cpu, :storage]
      assert result.payment == 25.0
    end

    test "combinatorial auction with insufficient resources" do
      resource_heavy_bids = [
        {:bidder1,
         %{
           bid: 50.0,
           bundle: [:cpu, :memory, :storage, :network],
           value: 0.9
         }}
      ]

      {:ok, result} =
        Auction.run_auction(:insufficient_resources, resource_heavy_bids,
          auction_type: :combinatorial,
          # Missing storage, network
          available_resources: [:cpu, :memory]
        )

      assert result.auction_type == :combinatorial
      # Cannot satisfy bundle
      assert result.winner == nil
      assert result.payment == 0.0
      assert result.reason == :insufficient_resources
    end
  end

  describe "auction metrics and efficiency" do
    test "calculates auction efficiency metrics" do
      bids = [
        {:bidder1, %{bid: 10.0, value: 0.8, true_value: 12.0}},
        {:bidder2, %{bid: 15.0, value: 0.9, true_value: 18.0}},
        {:bidder3, %{bid: 12.0, value: 0.7, true_value: 14.0}}
      ]

      {:ok, result} =
        Auction.run_auction(:efficiency_test, bids,
          auction_type: :sealed_bid,
          payment_rule: :second_price,
          calculate_efficiency: true
        )

      assert result.efficiency >= 0.0
      assert result.efficiency <= 1.0
      assert Map.has_key?(result, :social_welfare)
      assert Map.has_key?(result, :revenue)
    end

    test "tracks auction duration and performance" do
      bids = [
        {:bidder1, %{bid: 10.0, value: 0.8}},
        {:bidder2, %{bid: 15.0, value: 0.9}}
      ]

      {:ok, result} =
        Auction.run_auction(:performance_test, bids,
          auction_type: :sealed_bid,
          payment_rule: :first_price
        )

      assert Map.has_key?(result, :duration_ms)
      assert result.duration_ms >= 0
      assert Map.has_key?(result, :timestamp)
    end
  end

  describe "auction error handling" do
    test "handles invalid auction type" do
      bids = [{:bidder1, %{bid: 10.0, value: 0.8}}]

      assert {:error, :invalid_auction_type} =
               Auction.run_auction(:test, bids, auction_type: :invalid_type)
    end

    test "handles invalid payment rule" do
      bids = [{:bidder1, %{bid: 10.0, value: 0.8}}]

      assert {:error, :invalid_payment_rule} =
               Auction.run_auction(:test, bids,
                 auction_type: :sealed_bid,
                 payment_rule: :invalid_rule
               )
    end

    test "handles negative bids" do
      invalid_bids = [{:bidder1, %{bid: -10.0, value: 0.8}}]

      assert {:error, :invalid_bid_amount} =
               Auction.run_auction(:negative_bid, invalid_bids,
                 auction_type: :sealed_bid,
                 payment_rule: :first_price
               )
    end

    test "handles non-existent agents" do
      bids = [{:non_existent_agent, %{bid: 10.0, value: 0.8}}]

      assert {:error, :agent_not_found} =
               Auction.run_auction(:missing_agent, bids,
                 auction_type: :sealed_bid,
                 payment_rule: :first_price
               )
    end
  end

  describe "auction integration with coordination system" do
    test "integrates with existing coordination protocols" do
      # This test ensures auctions work with the main coordination system
      agents = [:bidder1, :bidder2, :bidder3]

      context = %{
        auction_type: :sealed_bid,
        payment_rule: :second_price,
        bids: [
          {:bidder1, %{bid: 10.0, value: 0.8}},
          {:bidder2, %{bid: 15.0, value: 0.9}},
          {:bidder3, %{bid: 12.0, value: 0.7}}
        ]
      }

      # Should be able to coordinate using auction mechanism
      assert {:ok, [result]} =
               Foundation.MABEAM.Coordination.coordinate(
                 :auction_protocol,
                 agents,
                 context
               )

      assert Map.has_key?(result, :winner)
      assert Map.has_key?(result, :payment)
    end
  end
end
