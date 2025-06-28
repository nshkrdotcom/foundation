defmodule MABEAM.Agents.Marketplace do
  @moduledoc """
  Economic marketplace agent for continuous resource trading and market mechanisms.
  
  This agent implements sophisticated market-based coordination for Jido agents,
  providing continuous trading, price discovery, and market-driven resource allocation.
  Unlike the Auctioneer which handles discrete auctions, the Marketplace provides
  ongoing market infrastructure for agent-to-agent trading.
  
  Key capabilities:
  - Continuous double-sided market for resources
  - Dynamic pricing based on supply and demand
  - Market maker functionality for liquidity
  - Trading reputation and credit systems
  - Real-time market analytics and insights
  - Integration with Foundation economic primitives
  
  Market mechanisms implemented:
  - **Order Book Management**: Bid/ask order matching
  - **Price Discovery**: Market-driven price formation
  - **Liquidity Provision**: Market maker algorithms
  - **Credit Systems**: Agent credit limits and reputation
  - **Market Analytics**: Real-time market statistics
  
  ## Usage Examples
  
      # Start marketplace agent
      {:ok, marketplace} = Marketplace.start_link(
        agent_id: :resource_marketplace,
        capabilities: [:order_matching, :price_discovery, :market_making],
        role: :coordinator
      )
      
      # Create a new market for GPU resources
      market_spec = %{
        resource_type: :gpu,
        market_type: :continuous,
        min_trade_size: 1,
        max_trade_size: 8,
        price_bounds: %{min: 1.0, max: 100.0},
        market_maker_enabled: true
      }
      
      {:ok, market_id} = Marketplace.create_market(marketplace, market_spec)
      
      # Agent places buy order
      buy_order = %{
        order_type: :buy,
        quantity: 2,
        price: 15.0,
        trader_id: :training_agent
      }
      
      {:ok, order_id} = Marketplace.place_order(marketplace, market_id, buy_order)
  """

  use Jido.Agent

  alias Foundation.Coordination.ResourceNegotiation
  alias JidoFoundation.AgentBridge
  alias JidoFoundation.SignalBridge
  alias JidoFoundation.InfrastructureBridge
  require Logger

  @type resource_type :: :cpu | :memory | :gpu | :storage | :network | :bandwidth | :custom
  @type order_type :: :buy | :sell | :market | :limit
  @type market_type :: :continuous | :call | :hybrid

  @type market_spec :: %{
          resource_type: resource_type(),
          market_type: market_type(),
          min_trade_size: pos_integer(),
          max_trade_size: pos_integer(),
          price_bounds: %{min: float(), max: float()},
          market_maker_enabled: boolean(),
          trading_session: map()
        }

  @type order :: %{
          order_id: String.t(),
          trader_id: atom(),
          order_type: order_type(),
          quantity: pos_integer(),
          price: float() | nil,  # nil for market orders
          timestamp: DateTime.t(),
          status: :pending | :partially_filled | :filled | :cancelled,
          filled_quantity: pos_integer(),
          remaining_quantity: pos_integer()
        }

  @type trade :: %{
          trade_id: String.t(),
          buyer_id: atom(),
          seller_id: atom(),
          quantity: pos_integer(),
          price: float(),
          timestamp: DateTime.t(),
          market_id: String.t()
        }

  @type market_state :: %{
          market_id: String.t(),
          spec: market_spec(),
          order_book: %{bids: [order()], asks: [order()]},
          recent_trades: [trade()],
          market_stats: map(),
          active_traders: MapSet.t(),
          market_maker_state: map(),
          last_trade_price: float() | nil
        }

  @impl Jido.Agent
  def init(config) do
    agent_id = config[:agent_id] || :marketplace
    
    # Initialize marketplace state
    state = %{
      agent_id: agent_id,
      active_markets: %{},
      global_order_book: %{},
      trader_accounts: %{},
      trading_history: %{},
      market_analytics: %{},
      credit_system: %{},
      foundation_registry: get_foundation_registry(),
      configuration: build_marketplace_configuration(config)
    }

    # Register with Foundation through JidoFoundation bridge
    case register_with_foundation(agent_id, config) do
      {:ok, _ref} ->
        Logger.info("Marketplace agent registered", agent_id: agent_id)
        
        # Start market monitoring and analytics
        schedule_market_monitoring()
        schedule_analytics_update()
        
        {:ok, state}
        
      {:error, reason} ->
        Logger.error("Failed to register Marketplace", 
          agent_id: agent_id, 
          reason: reason
        )
        {:error, reason}
    end
  end

  @impl Jido.Agent
  def handle_action(:create_market, params, state) do
    market_spec = params.market_spec
    initial_liquidity = params.initial_liquidity || %{}
    
    # Validate market specification
    case validate_market_spec(market_spec) do
      :ok ->
        market_id = generate_market_id(market_spec.resource_type)
        
        # Create market with Foundation protection
        market_creation_operation = fn ->
          create_market_with_foundation_protection(market_id, market_spec, initial_liquidity, state)
        end
        
        protection_spec = %{
          circuit_breaker: %{failure_threshold: 3, recovery_time: 30_000},
          timeout: 10_000
        }
        
        case InfrastructureBridge.execute_protected_action(
               :create_market,
               %{market_id: market_id, spec: market_spec},
               protection_spec,
               agent_id: state.agent_id
             ) do
          {:ok, market_state} ->
            # Add market to active markets
            updated_state = %{state | 
              active_markets: Map.put(state.active_markets, market_id, market_state)
            }
            
            # Initialize market maker if enabled
            if market_spec.market_maker_enabled do
              initialize_market_maker(market_id, market_spec, updated_state)
            end
            
            # Emit market creation signal
            signal = create_market_signal(:created, market_state)
            
            Logger.info("Market created",
              market_id: market_id,
              resource_type: market_spec.resource_type,
              market_type: market_spec.market_type
            )
            
            {:ok, %{market_id: market_id, market_state: market_state}, updated_state, signal}
            
          {:error, reason} = error ->
            Logger.error("Failed to create market",
              market_spec: market_spec,
              reason: reason
            )
            error
        end
        
      {:error, validation_error} ->
        Logger.warning("Invalid market specification", error: validation_error)
        {:error, {:invalid_market_spec, validation_error}}
    end
  end

  @impl Jido.Agent
  def handle_action(:place_order, params, state) do
    market_id = params.market_id
    order_spec = params.order_spec
    trader_id = params.trader_id
    
    case Map.get(state.active_markets, market_id) do
      nil ->
        {:error, {:market_not_found, market_id}}
        
      market_state ->
        # Validate trader and order
        order_validation_operation = fn ->
          validate_and_process_order(market_state, order_spec, trader_id, state)
        end
        
        protection_spec = %{
          rate_limiter: %{requests_per_second: 20, burst_size: 10},
          timeout: 5000
        }
        
        case InfrastructureBridge.execute_protected_action(
               :place_order,
               %{market_id: market_id, trader: trader_id, order: order_spec},
               protection_spec,
               agent_id: state.agent_id
             ) do
          {:ok, order_result} ->
            # Update market state with new order and any matches
            {updated_market, trades} = process_order_and_matching(market_state, order_result.order)
            
            updated_state = %{state | 
              active_markets: Map.put(state.active_markets, market_id, updated_market),
              trading_history: update_trading_history(state.trading_history, trades)
            }
            
            # Emit order and trade signals
            order_signal = create_order_signal(:placed, market_id, order_result.order)
            trade_signals = Enum.map(trades, &create_trade_signal(:executed, market_id, &1))
            
            all_signals = [order_signal | trade_signals]
            
            Logger.info("Order placed and processed",
              market_id: market_id,
              order_id: order_result.order.order_id,
              trader: trader_id,
              matches: length(trades)
            )
            
            {:ok, %{order: order_result.order, trades: trades}, updated_state, all_signals}
            
          {:error, reason} = error ->
            Logger.warning("Order rejected",
              market_id: market_id,
              trader: trader_id,
              reason: reason
            )
            error
        end
    end
  end

  @impl Jido.Agent
  def handle_action(:get_market_data, params, state) do
    market_id = params.market_id
    data_type = params.data_type || :full  # :full, :order_book, :recent_trades, :stats
    
    case Map.get(state.active_markets, market_id) do
      nil ->
        {:error, {:market_not_found, market_id}}
        
      market_state ->
        market_data = case data_type do
          :full -> 
            build_full_market_data(market_state, state)
          :order_book -> 
            %{order_book: market_state.order_book, last_update: DateTime.utc_now()}
          :recent_trades -> 
            %{recent_trades: market_state.recent_trades, trade_count: length(market_state.recent_trades)}
          :stats -> 
            calculate_market_statistics(market_state)
        end
        
        {:ok, market_data}
    end
  end

  @impl Jido.Agent
  def handle_action(:run_market_making, params, state) do
    market_id = params.market_id
    market_making_config = params.config || %{}
    
    case Map.get(state.active_markets, market_id) do
      nil ->
        {:error, {:market_not_found, market_id}}
        
      market_state ->
        if not market_state.spec.market_maker_enabled do
          {:error, :market_making_not_enabled}
        else
          # Execute market making algorithm with Foundation protection
          market_making_operation = fn ->
            execute_market_making_algorithm(market_state, market_making_config, state)
          end
          
          protection_spec = %{
            circuit_breaker: %{failure_threshold: 5, recovery_time: 60_000},
            timeout: 30_000
          }
          
          case InfrastructureBridge.execute_protected_action(
                 :run_market_making,
                 %{market_id: market_id, config: market_making_config},
                 protection_spec,
                 agent_id: state.agent_id
               ) do
            {:ok, market_making_result} ->
              # Update market state with market maker orders
              updated_market = apply_market_maker_orders(market_state, market_making_result.orders)
              updated_state = %{state | 
                active_markets: Map.put(state.active_markets, market_id, updated_market)
              }
              
              signal = create_market_making_signal(:executed, market_id, market_making_result)
              
              Logger.info("Market making executed",
                market_id: market_id,
                orders_placed: length(market_making_result.orders),
                spread_adjustment: market_making_result.spread_adjustment
              )
              
              {:ok, market_making_result, updated_state, signal}
              
            {:error, reason} = error ->
              Logger.error("Market making failed",
                market_id: market_id,
                reason: reason
              )
              error
          end
        end
    end
  end

  @impl Jido.Agent
  def handle_action(:calculate_market_price, params, state) do
    market_id = params.market_id
    pricing_method = params.method || :mid_price  # :mid_price, :last_trade, :vwap
    
    case Map.get(state.active_markets, market_id) do
      nil ->
        {:error, {:market_not_found, market_id}}
        
      market_state ->
        price_result = case pricing_method do
          :mid_price ->
            calculate_mid_price(market_state.order_book)
          :last_trade ->
            %{price: market_state.last_trade_price, method: :last_trade}
          :vwap ->
            calculate_vwap(market_state.recent_trades)
          :twap ->
            calculate_twap(market_state.recent_trades, params.time_window || 300)
        end
        
        case price_result do
          {:ok, price_data} ->
            # Update market analytics
            updated_analytics = update_price_analytics(state.market_analytics, market_id, price_data)
            updated_state = %{state | market_analytics: updated_analytics}
            
            {:ok, price_data, updated_state}
            
          {:error, reason} ->
            {:error, {:price_calculation_failed, reason}}
        end
    end
  end

  @impl Jido.Agent
  def handle_signal(signal, state) do
    case signal.type do
      "market.order.update" ->
        handle_order_update_signal(signal, state)
        
      "market.trade.executed" ->
        handle_trade_execution_signal(signal, state)
        
      "market.liquidity.low" ->
        handle_low_liquidity_signal(signal, state)
        
      "trader.credit.warning" ->
        handle_credit_warning_signal(signal, state)
        
      _ ->
        Logger.debug("Unhandled signal received", 
          signal_type: signal.type, 
          marketplace: state.agent_id
        )
        {:ok, state}
    end
  end

  # Private implementation functions

  defp register_with_foundation(agent_id, config) do
    agent_config = %{
      agent_id: agent_id,
      agent_module: __MODULE__,
      capabilities: config[:capabilities] || [:order_matching, :price_discovery, :market_making],
      role: :coordinator,
      resource_requirements: config[:resource_requirements] || %{cpu: 0.4, memory: 512},
      communication_interfaces: [:jido_signal, :foundation_events],
      coordination_variables: config[:coordination_variables] || [],
      foundation_namespace: :jido,
      auto_register: true
    }
    
    AgentBridge.register_jido_agent(__MODULE__, agent_config)
  end

  defp get_foundation_registry do
    JidoFoundation.Application.foundation_registry()
  end

  defp build_marketplace_configuration(config) do
    defaults = %{
      market_monitoring_interval: 5_000,
      analytics_update_interval: 30_000,
      max_order_size: 1000,
      price_precision: 2,
      default_market_maker_spread: 0.02,
      credit_check_enabled: true
    }
    
    Map.merge(defaults, Map.new(config))
  end

  defp schedule_market_monitoring do
    interval = 5_000  # 5 seconds
    Process.send_after(self(), :market_monitoring_tick, interval)
  end

  defp schedule_analytics_update do
    interval = 30_000  # 30 seconds
    Process.send_after(self(), :analytics_update_tick, interval)
  end

  defp validate_market_spec(spec) do
    required_fields = [:resource_type, :market_type, :min_trade_size, :max_trade_size]
    
    case Enum.all?(required_fields, &Map.has_key?(spec, &1)) do
      true -> validate_market_values(spec)
      false -> {:error, :missing_required_fields}
    end
  end

  defp validate_market_values(spec) do
    cond do
      spec.min_trade_size <= 0 -> {:error, :invalid_min_trade_size}
      spec.max_trade_size < spec.min_trade_size -> {:error, :invalid_max_trade_size}
      spec.market_type not in [:continuous, :call, :hybrid] -> {:error, :invalid_market_type}
      true -> :ok
    end
  end

  defp create_market_with_foundation_protection(market_id, market_spec, initial_liquidity, _state) do
    market_state = %{
      market_id: market_id,
      spec: market_spec,
      order_book: %{bids: [], asks: []},
      recent_trades: [],
      market_stats: initialize_market_stats(),
      active_traders: MapSet.new(),
      market_maker_state: %{},
      last_trade_price: nil,
      created_at: DateTime.utc_now()
    }
    
    # Add initial liquidity if provided
    final_market_state = if Map.size(initial_liquidity) > 0 do
      add_initial_liquidity(market_state, initial_liquidity)
    else
      market_state
    end
    
    {:ok, final_market_state}
  end

  defp initialize_market_maker(market_id, market_spec, state) do
    # Initialize market maker algorithms for this market
    market_maker_config = %{
      spread: state.configuration.default_market_maker_spread,
      max_position: calculate_max_market_maker_position(market_spec),
      rebalance_threshold: 0.1,
      price_skew_factor: 0.02
    }
    
    Logger.info("Market maker initialized", 
      market_id: market_id, 
      config: market_maker_config
    )
    
    :ok
  end

  defp validate_and_process_order(market_state, order_spec, trader_id, state) do
    # Validate order parameters
    cond do
      order_spec.quantity < market_state.spec.min_trade_size ->
        {:error, :quantity_below_minimum}
        
      order_spec.quantity > market_state.spec.max_trade_size ->
        {:error, :quantity_above_maximum}
        
      not validate_trader_credit(trader_id, order_spec, state.credit_system) ->
        {:error, :insufficient_credit}
        
      not validate_order_price(order_spec, market_state.spec) ->
        {:error, :invalid_price}
        
      true ->
        order = %{
          order_id: generate_order_id(),
          trader_id: trader_id,
          order_type: order_spec.order_type,
          quantity: order_spec.quantity,
          price: order_spec.price,
          timestamp: DateTime.utc_now(),
          status: :pending,
          filled_quantity: 0,
          remaining_quantity: order_spec.quantity
        }
        
        {:ok, %{order: order, validation_result: :accepted}}
    end
  end

  defp process_order_and_matching(market_state, order) do
    # Add order to order book and execute matching
    updated_order_book = add_order_to_book(market_state.order_book, order)
    
    # Execute matching algorithm
    {final_order_book, trades} = execute_order_matching(updated_order_book, order)
    
    # Update market state
    updated_market = %{market_state |
      order_book: final_order_book,
      recent_trades: add_trades_to_recent(market_state.recent_trades, trades),
      last_trade_price: get_last_trade_price(trades, market_state.last_trade_price),
      active_traders: add_trader_to_active(market_state.active_traders, order.trader_id)
    }
    
    {updated_market, trades}
  end

  # Complex trading and matching algorithms (simplified implementations)

  defp add_order_to_book(order_book, order) do
    case order.order_type do
      :buy -> %{order_book | bids: insert_order_sorted(order_book.bids, order, :desc)}
      :sell -> %{order_book | asks: insert_order_sorted(order_book.asks, order, :asc)}
      _ -> order_book
    end
  end

  defp execute_order_matching(order_book, new_order) do
    case new_order.order_type do
      :buy -> match_buy_order(order_book, new_order)
      :sell -> match_sell_order(order_book, new_order)
      _ -> {order_book, []}
    end
  end

  defp match_buy_order(order_book, buy_order) do
    # Match buy order against asks (sell orders)
    {matched_asks, remaining_asks, trades} = match_orders(buy_order, order_book.asks, [])
    
    final_order_book = %{order_book | asks: remaining_asks}
    {final_order_book, trades}
  end

  defp match_sell_order(order_book, sell_order) do
    # Match sell order against bids (buy orders)
    {matched_bids, remaining_bids, trades} = match_orders(sell_order, order_book.bids, [])
    
    final_order_book = %{order_book | bids: remaining_bids}
    {final_order_book, trades}
  end

  defp match_orders(order, [], trades), do: {[], [], trades}
  defp match_orders(order, potential_matches, trades) when order.remaining_quantity <= 0, 
    do: {[], potential_matches, trades}
  defp match_orders(order, [match_candidate | rest], trades) do
    if orders_can_match?(order, match_candidate) do
      trade_quantity = min(order.remaining_quantity, match_candidate.remaining_quantity)
      trade_price = determine_trade_price(order, match_candidate)
      
      trade = %{
        trade_id: generate_trade_id(),
        buyer_id: if(order.order_type == :buy, do: order.trader_id, else: match_candidate.trader_id),
        seller_id: if(order.order_type == :sell, do: order.trader_id, else: match_candidate.trader_id),
        quantity: trade_quantity,
        price: trade_price,
        timestamp: DateTime.utc_now(),
        market_id: "current_market"  # Would be passed in properly
      }
      
      # Update remaining quantities
      updated_order = %{order | remaining_quantity: order.remaining_quantity - trade_quantity}
      updated_match = %{match_candidate | remaining_quantity: match_candidate.remaining_quantity - trade_quantity}
      
      remaining_matches = if updated_match.remaining_quantity > 0, do: [updated_match | rest], else: rest
      
      match_orders(updated_order, remaining_matches, [trade | trades])
    else
      {[], [match_candidate | rest], trades}
    end
  end

  # Signal creation helpers
  defp create_market_signal(event_type, market_state) do
    Jido.Signal.new!(%{
      type: "market.#{event_type}",
      source: "/agents/marketplace",
      data: %{
        market_id: market_state.market_id,
        resource_type: market_state.spec.resource_type,
        market_state: market_state,
        timestamp: DateTime.utc_now()
      }
    })
  end

  defp create_order_signal(event_type, market_id, order) do
    Jido.Signal.new!(%{
      type: "market.order.#{event_type}",
      source: "/agents/marketplace",
      data: %{
        market_id: market_id,
        order: order,
        timestamp: DateTime.utc_now()
      }
    })
  end

  defp create_trade_signal(event_type, market_id, trade) do
    Jido.Signal.new!(%{
      type: "market.trade.#{event_type}",
      source: "/agents/marketplace",
      data: %{
        market_id: market_id,
        trade: trade,
        timestamp: DateTime.utc_now()
      }
    })
  end

  defp create_market_making_signal(event_type, market_id, result) do
    Jido.Signal.new!(%{
      type: "market.making.#{event_type}",
      source: "/agents/marketplace",
      data: %{
        market_id: market_id,
        result: result,
        timestamp: DateTime.utc_now()
      }
    })
  end

  # Placeholder implementations for complex functions
  defp initialize_market_stats, do: %{total_volume: 0, trade_count: 0, avg_price: 0.0}
  defp add_initial_liquidity(market_state, _liquidity), do: market_state
  defp calculate_max_market_maker_position(_spec), do: 100
  defp validate_trader_credit(_trader_id, _order_spec, _credit_system), do: true
  defp validate_order_price(_order_spec, _market_spec), do: true
  defp insert_order_sorted(orders, new_order, _direction), do: [new_order | orders]
  defp orders_can_match?(_order1, _order2), do: true
  defp determine_trade_price(_order1, order2), do: order2.price || 10.0
  defp add_trades_to_recent(recent, new_trades), do: new_trades ++ recent
  defp get_last_trade_price([], current), do: current
  defp get_last_trade_price([trade | _], _current), do: trade.price
  defp add_trader_to_active(active_set, trader_id), do: MapSet.put(active_set, trader_id)
  defp update_trading_history(history, _trades), do: history
  defp build_full_market_data(market_state, _state), do: market_state
  defp calculate_market_statistics(_market_state), do: %{}
  defp execute_market_making_algorithm(_market_state, _config, _state), do: {:ok, %{orders: [], spread_adjustment: 0.01}}
  defp apply_market_maker_orders(market_state, _orders), do: market_state
  defp calculate_mid_price(_order_book), do: {:ok, %{price: 10.0, method: :mid_price}}
  defp calculate_vwap(_trades), do: {:ok, %{price: 10.0, method: :vwap}}
  defp calculate_twap(_trades, _window), do: {:ok, %{price: 10.0, method: :twap}}
  defp update_price_analytics(analytics, _market_id, _price_data), do: analytics

  # Signal handlers (placeholder implementations)
  defp handle_order_update_signal(_signal, state), do: {:ok, state}
  defp handle_trade_execution_signal(_signal, state), do: {:ok, state}
  defp handle_low_liquidity_signal(_signal, state), do: {:ok, state}
  defp handle_credit_warning_signal(_signal, state), do: {:ok, state}

  # ID generators
  defp generate_market_id(resource_type), do: "market_#{resource_type}_" <> (:crypto.strong_rand_bytes(6) |> Base.encode16())
  defp generate_order_id, do: "order_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16())
  defp generate_trade_id, do: "trade_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16())
end
