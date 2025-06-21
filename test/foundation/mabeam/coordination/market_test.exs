# test/foundation/mabeam/coordination/market_test.exs
defmodule Foundation.MABEAM.Coordination.MarketTest do
  @moduledoc """
  Comprehensive test suite for market-based coordination mechanisms.

  Tests market mechanisms including:
  - Supply and demand modeling
  - Price discovery algorithms
  - Market equilibrium finding
  - Resource allocation through market mechanisms
  """

  use ExUnit.Case, async: false

  alias Foundation.MABEAM.Coordination.Market

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

    # Register test agents for market scenarios
    market_agents = [
      {:cpu_supplier,
       %{
         id: :cpu_supplier,
         type: :supplier_agent,
         module: SupplierAgent,
         config: %{resource: :cpu, supply: 100, min_price: 1.0, cost: 0.5},
         supervision: %{strategy: :one_for_one, max_restarts: 3, max_seconds: 60}
       }},
      {:memory_supplier,
       %{
         id: :memory_supplier,
         type: :supplier_agent,
         module: SupplierAgent,
         config: %{resource: :memory, supply: 200, min_price: 0.5, cost: 0.2},
         supervision: %{strategy: :one_for_one, max_restarts: 3, max_seconds: 60}
       }},
      {:compute_agent,
       %{
         id: :compute_agent,
         type: :consumer_agent,
         module: ConsumerAgent,
         config: %{resource: :cpu, demand: 80, max_price: 2.0, utility: 100},
         supervision: %{strategy: :one_for_one, max_restarts: 3, max_seconds: 60}
       }},
      {:storage_agent,
       %{
         id: :storage_agent,
         type: :consumer_agent,
         module: ConsumerAgent,
         config: %{resource: :memory, demand: 150, max_price: 1.0, utility: 80},
         supervision: %{strategy: :one_for_one, max_restarts: 3, max_seconds: 60}
       }}
    ]

    Enum.each(market_agents, fn {agent_id, config} ->
      Foundation.MABEAM.AgentRegistry.register_agent(agent_id, config)
    end)

    # Register market protocol for integration tests
    Foundation.MABEAM.Coordination.Market.register_market_protocol(:market_protocol,
      market_type: :resource_allocation
    )

    on_exit(fn ->
      # Clean up test agents
      Enum.each(market_agents, fn {agent_id, _config} ->
        try do
          Foundation.MABEAM.AgentRegistry.deregister_agent(agent_id)
        catch
          # Registry already stopped
          :exit, _ -> :ok
        end
      end)
    end)

    {:ok, suppliers: [:cpu_supplier, :memory_supplier], consumers: [:compute_agent, :storage_agent]}
  end

  describe "market equilibrium" do
    test "finds market equilibrium with balanced supply and demand" do
      suppliers = [
        {:cpu_supplier, %{supply: 100, min_price: 1.0}},
        {:memory_supplier, %{supply: 200, min_price: 0.5}}
      ]

      demanders = [
        {:compute_agent, %{demand: 80, max_price: 2.0}},
        {:storage_agent, %{demand: 150, max_price: 1.0}}
      ]

      {:ok, result} = Market.find_equilibrium(:resource_market, suppliers, demanders)

      assert result.equilibrium_found == true
      assert result.clearing_price > 0
      assert result.total_traded > 0
      assert result.market_efficiency >= 0.0
      assert result.market_efficiency <= 1.0
      assert result.participants == %{suppliers: 2, demanders: 2}
    end

    test "handles excess supply scenario" do
      suppliers = [
        {:cpu_supplier, %{supply: 200, min_price: 0.5}},
        {:memory_supplier, %{supply: 300, min_price: 0.3}}
      ]

      demanders = [
        {:compute_agent, %{demand: 50, max_price: 1.5}}
      ]

      {:ok, result} = Market.find_equilibrium(:excess_supply_market, suppliers, demanders)

      assert result.equilibrium_found == true
      # At least min price of supplier
      assert result.clearing_price >= 0.3
      # At most max price of demander
      assert result.clearing_price <= 1.5
      # Limited by demand
      assert result.total_traded <= 50
      assert result.market_status == :excess_supply
    end

    test "handles excess demand scenario" do
      suppliers = [
        {:cpu_supplier, %{supply: 50, min_price: 1.0}}
      ]

      demanders = [
        {:compute_agent, %{demand: 100, max_price: 2.0}},
        {:storage_agent, %{demand: 80, max_price: 1.8}}
      ]

      {:ok, result} = Market.find_equilibrium(:excess_demand_market, suppliers, demanders)

      assert result.equilibrium_found == true
      # At least min price of supplier
      assert result.clearing_price >= 1.0
      # Limited by supply
      assert result.total_traded <= 50
      assert result.market_status == :excess_demand
    end

    test "handles no feasible market scenario" do
      suppliers = [
        # High min price
        {:cpu_supplier, %{supply: 100, min_price: 3.0}}
      ]

      demanders = [
        # Low max price
        {:compute_agent, %{demand: 80, max_price: 1.0}}
      ]

      {:ok, result} = Market.find_equilibrium(:no_trade_market, suppliers, demanders)

      assert result.equilibrium_found == false
      assert result.clearing_price == 0.0
      assert result.total_traded == 0
      assert result.market_status == :no_trade
      assert result.reason == :price_gap_too_large
    end
  end

  describe "price discovery" do
    test "discovers price through iterative bidding" do
      market_config = %{
        max_iterations: 10,
        price_step: 0.1,
        convergence_threshold: 0.05
      }

      {:ok, result} = Market.discover_price(:cpu_time, market_config)

      assert result.final_price > 0
      assert result.iterations <= 10
      assert result.converged == true
      assert result.price_history |> length() > 0
    end

    test "handles price discovery with volatile market" do
      market_config = %{
        max_iterations: 20,
        price_step: 0.2,
        convergence_threshold: 0.01,
        volatility: :high
      }

      {:ok, result} = Market.discover_price(:volatile_resource, market_config)

      assert result.final_price > 0
      assert result.iterations <= 20
      # May or may not converge with high volatility
      assert is_boolean(result.converged)
      assert result.volatility_measure >= 0.0
    end

    test "price discovery with external shocks" do
      market_config = %{
        max_iterations: 15,
        price_step: 0.1,
        external_shocks: [
          %{iteration: 5, type: :supply_disruption, magnitude: 0.3},
          %{iteration: 10, type: :demand_surge, magnitude: 0.4}
        ]
      }

      {:ok, result} = Market.discover_price(:shocked_market, market_config)

      assert result.final_price > 0
      assert result.shocks_processed == 2
      assert length(result.price_history) > 0
    end
  end

  describe "resource allocation" do
    test "allocates resources efficiently through market mechanism" do
      allocation_request = %{
        resources: [:cpu, :memory, :storage],
        agents: [:compute_agent, :storage_agent],
        budget_constraints: %{
          compute_agent: 100.0,
          storage_agent: 80.0
        },
        resource_availability: %{
          cpu: 100,
          memory: 200,
          storage: 150
        }
      }

      {:ok, result} = Market.allocate_resources(:multi_resource_market, allocation_request)

      assert result.allocation_successful == true
      assert Map.has_key?(result.allocations, :compute_agent)
      assert Map.has_key?(result.allocations, :storage_agent)
      assert result.total_welfare > 0
      assert result.market_clearing == true
    end

    test "handles budget-constrained allocation" do
      allocation_request = %{
        resources: [:cpu],
        agents: [:compute_agent],
        budget_constraints: %{
          # Very limited budget
          compute_agent: 10.0
        },
        resource_availability: %{
          cpu: 100
        }
      }

      {:ok, result} = Market.allocate_resources(:budget_constrained_market, allocation_request)

      # Should still succeed but with limited allocation
      assert result.allocation_successful == true
      allocation = result.allocations.compute_agent
      assert allocation.cpu.quantity > 0
      # Respects budget constraint
      assert allocation.cpu.cost <= 10.0
    end
  end

  describe "market dynamics" do
    test "simulates market over multiple periods" do
      simulation_config = %{
        periods: 5,
        demand_variation: 0.1,
        supply_variation: 0.05,
        learning_enabled: true
      }

      {:ok, result} = Market.simulate_market(:dynamic_market, simulation_config)

      assert length(result.period_results) == 5
      assert result.overall_efficiency >= 0.0
      assert result.price_stability >= 0.0
      assert result.learning_effects |> Map.keys() |> length() > 0
    end

    test "models agent learning and adaptation" do
      learning_config = %{
        periods: 3,
        learning_rate: 0.1,
        adaptation_strategy: :gradient_based
      }

      {:ok, result} = Market.simulate_market_with_learning(:adaptive_market, learning_config)

      assert length(result.period_results) == 3
      assert result.agent_adaptations |> Map.keys() |> length() > 0

      # Check that agents improved over time
      first_period_welfare = hd(result.period_results).total_welfare
      last_period_welfare = List.last(result.period_results).total_welfare
      assert last_period_welfare >= first_period_welfare
    end
  end

  describe "market mechanisms" do
    test "double auction mechanism" do
      bids = [
        {:compute_agent, %{type: :buy, quantity: 50, price: 1.5}},
        {:storage_agent, %{type: :buy, quantity: 30, price: 1.2}}
      ]

      asks = [
        {:cpu_supplier, %{type: :sell, quantity: 60, price: 1.0}},
        {:memory_supplier, %{type: :sell, quantity: 40, price: 1.1}}
      ]

      {:ok, result} = Market.run_double_auction(:double_auction_market, bids, asks)

      assert result.trades |> length() > 0
      assert result.clearing_price > 0
      assert result.total_volume > 0
      assert result.market_efficiency >= 0.0
    end

    test "continuous trading mechanism" do
      trading_config = %{
        duration_ms: 1000,
        min_trade_size: 1,
        max_trade_size: 50
      }

      {:ok, result} = Market.run_continuous_trading(:continuous_market, trading_config)

      assert result.total_trades >= 0
      assert result.final_price > 0
      assert result.price_volatility >= 0.0
      assert result.trading_volume >= 0
    end
  end

  describe "market integration" do
    test "integrates with coordination system for resource allocation" do
      agents = [:compute_agent, :storage_agent]

      context = %{
        market_type: :resource_allocation,
        resources: [:cpu, :memory],
        allocation_strategy: :market_based,
        budget_limits: %{
          compute_agent: 100.0,
          storage_agent: 80.0
        }
      }

      # Should be able to coordinate using market mechanism
      {:ok, [result]} =
        Foundation.MABEAM.Coordination.coordinate(
          :market_protocol,
          agents,
          context
        )

      assert Map.has_key?(result, :allocations)
      assert Map.has_key?(result, :clearing_price)
      assert Map.has_key?(result, :market_efficiency)
    end
  end

  describe "error handling and edge cases" do
    test "handles empty market gracefully" do
      {:ok, result} = Market.find_equilibrium(:empty_market, [], [])

      assert result.equilibrium_found == false
      assert result.clearing_price == 0.0
      assert result.total_traded == 0
      assert result.market_status == :no_participants
    end

    test "handles invalid market parameters" do
      suppliers = [
        # Invalid negative values
        {:invalid_supplier, %{supply: -10, min_price: -1.0}}
      ]

      demanders = [
        # Invalid negative values
        {:invalid_demander, %{demand: -5, max_price: -0.5}}
      ]

      assert {:error, :invalid_market_parameters} =
               Market.find_equilibrium(:invalid_market, suppliers, demanders)
    end

    test "handles market timeouts" do
      market_config = %{
        # Very high
        max_iterations: 1000,
        # Very low timeout (1ms)
        timeout_ms: 1
      }

      {:ok, result} = Market.discover_price(:timeout_market, market_config)

      assert result.status == :timeout
      # Should have stopped early
      assert result.iterations < 1000
    end
  end
end
