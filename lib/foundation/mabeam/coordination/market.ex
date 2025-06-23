defmodule Foundation.MABEAM.Coordination.Market do
  @moduledoc """
  Market-based coordination mechanisms for MABEAM agents.

  Provides market simulation, equilibrium finding, and resource allocation
  through market mechanisms for distributed agent coordination.

  ## Features

  - Market creation and management
  - Supply and demand matching
  - Price discovery mechanisms
  - Equilibrium calculation
  - Market simulation
  - Economic efficiency analysis
  """

  use GenServer
  require Logger

  alias Foundation.MABEAM.Types

  @type agent_id :: Types.agent_id()
  @type market_order :: %{
          agent_id: agent_id(),
          type: :buy | :sell,
          quantity: number(),
          price: number() | :market,
          metadata: map()
        }
  @type trade :: %{
          buyer: agent_id(),
          seller: agent_id(),
          quantity: number(),
          price: number(),
          timestamp: DateTime.t()
        }
  @type market_result :: %{
          trades: [trade()],
          clearing_price: number() | nil,
          total_volume: number(),
          market_efficiency: float(),
          participants: [agent_id()],
          metadata: map()
        }
  @type market_equilibrium :: %{
          equilibrium_price: number(),
          equilibrium_quantity: number(),
          consumer_surplus: number(),
          producer_surplus: number(),
          total_welfare: number()
        }
  @type market_spec :: %{
          name: atom(),
          commodity: atom(),
          market_type: :continuous | :call | :sealed_bid,
          price_mechanism: :auction | :negotiation | :fixed,
          participants: [agent_id()],
          metadata: map()
        }

  ## Public API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec create_market(market_spec()) :: {:ok, reference()} | {:error, term()}
  def create_market(market_spec) do
    GenServer.call(__MODULE__, {:create_market, market_spec})
  end

  @spec close_market(reference()) :: {:ok, market_result()} | {:error, term()}
  def close_market(market_id) do
    GenServer.call(__MODULE__, {:close_market, market_id})
  end

  @spec submit_order(reference(), market_order()) :: :ok | {:error, term()}
  def submit_order(market_id, order) do
    GenServer.call(__MODULE__, {:submit_order, market_id, order})
  end

  @spec place_order(reference(), agent_id(), market_order()) ::
          {:ok, reference()} | {:error, term()}
  def place_order(market_id, agent_id, order) do
    order_with_agent = Map.put(order, :agent_id, agent_id)

    case submit_order(market_id, order_with_agent) do
      # Return order reference
      :ok -> {:ok, make_ref()}
      error -> error
    end
  end

  @spec cancel_order(reference(), reference()) :: :ok | {:error, term()}
  def cancel_order(market_id, order_id) do
    GenServer.call(__MODULE__, {:cancel_order, market_id, order_id})
  end

  @spec find_equilibrium(reference()) :: {:ok, market_equilibrium()} | {:error, term()}
  def find_equilibrium(market_id) do
    GenServer.call(__MODULE__, {:find_equilibrium, market_id})
  end

  @spec find_equilibrium([market_order()], [market_order()]) ::
          {:ok, market_equilibrium()} | {:error, term()}
  def find_equilibrium(supply_orders, demand_orders) do
    GenServer.call(__MODULE__, {:find_equilibrium_from_orders, supply_orders, demand_orders})
  end

  @spec simulate_market(market_spec(), [market_order()], keyword()) ::
          {:ok, market_result()} | {:error, term()}
  def simulate_market(market_spec, orders, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    GenServer.call(__MODULE__, {:simulate_market, market_spec, orders, opts}, timeout)
  end

  @spec get_market_status(reference()) :: {:ok, map()} | {:error, term()}
  def get_market_status(market_id) do
    GenServer.call(__MODULE__, {:get_market_status, market_id})
  end

  @spec list_active_markets() :: {:ok, [reference()]} | {:error, term()}
  def list_active_markets() do
    GenServer.call(__MODULE__, :list_active_markets)
  end

  @spec get_market_statistics() :: {:ok, map()} | {:error, term()}
  def get_market_statistics() do
    GenServer.call(__MODULE__, :get_statistics)
  end

  ## GenServer Implementation

  @impl true
  def init(opts) do
    state = %{
      active_markets: %{},
      market_history: [],
      statistics: %{
        total_markets: 0,
        successful_markets: 0,
        failed_markets: 0,
        total_trades: 0,
        total_volume: 0.0,
        average_efficiency: 0.0
      },
      test_mode: Keyword.get(opts, :test_mode, false)
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:create_market, market_spec}, _from, state) do
    case validate_market_spec(market_spec) do
      :ok ->
        market_id = make_ref()

        market_state = %{
          id: market_id,
          spec: market_spec,
          orders: [],
          trades: [],
          status: :active,
          created_at: DateTime.utc_now()
        }

        new_markets = Map.put(state.active_markets, market_id, market_state)

        new_state = %{
          state
          | active_markets: new_markets,
            statistics: %{state.statistics | total_markets: state.statistics.total_markets + 1}
        }

        {:reply, {:ok, market_id}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:close_market, market_id}, _from, state) do
    case Map.get(state.active_markets, market_id) do
      nil ->
        {:reply, {:error, :market_not_found}, state}

      market_state ->
        # Process any remaining orders and calculate final result
        final_result = calculate_market_result(market_state)

        # Update market status
        updated_market = %{market_state | status: :closed}
        new_markets = Map.put(state.active_markets, market_id, updated_market)

        # Update statistics
        new_stats = update_market_statistics(state.statistics, final_result)

        # Add to history
        history_entry = Map.put(final_result, :market_id, market_id)
        new_history = [history_entry | state.market_history] |> Enum.take(100)

        new_state = %{
          state
          | active_markets: new_markets,
            statistics: new_stats,
            market_history: new_history
        }

        {:reply, {:ok, final_result}, new_state}
    end
  end

  @impl true
  def handle_call({:submit_order, market_id, order}, _from, state) do
    case Map.get(state.active_markets, market_id) do
      nil ->
        {:reply, {:error, :market_not_found}, state}

      market_state ->
        case validate_order(order) do
          :ok ->
            # Add order to market
            new_orders = [order | market_state.orders]

            # Try to match orders if it's a continuous market
            {updated_orders, new_trades} =
              if market_state.spec.market_type == :continuous do
                match_orders(new_orders, market_state.trades)
              else
                {new_orders, market_state.trades}
              end

            updated_market = %{market_state | orders: updated_orders, trades: new_trades}

            new_markets = Map.put(state.active_markets, market_id, updated_market)
            new_state = %{state | active_markets: new_markets}

            {:reply, :ok, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:find_equilibrium, market_id}, _from, state) do
    case Map.get(state.active_markets, market_id) do
      nil ->
        {:reply, {:error, :market_not_found}, state}

      market_state ->
        equilibrium = calculate_equilibrium(market_state.orders)
        {:reply, {:ok, equilibrium}, state}
    end
  end

  @impl true
  def handle_call({:find_equilibrium_from_orders, supply_orders, demand_orders}, _from, state) do
    all_orders = supply_orders ++ demand_orders
    equilibrium = calculate_equilibrium(all_orders)
    {:reply, {:ok, equilibrium}, state}
  end

  @impl true
  def handle_call({:cancel_order, market_id, _order_id}, _from, state) do
    case Map.get(state.active_markets, market_id) do
      nil ->
        {:reply, {:error, :market_not_found}, state}

      _market_state ->
        # For simplicity, we'll just return success since order tracking by ID
        # would require more complex order management
        {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:simulate_market, market_spec, orders, _opts}, _from, state) do
    case validate_market_spec(market_spec) do
      :ok ->
        # Create temporary market for simulation
        market_state = %{
          spec: market_spec,
          orders: orders,
          trades: [],
          status: :simulation
        }

        # Run market simulation
        case run_market_simulation(market_state) do
          {:ok, result} ->
            # Update statistics for simulation
            new_stats = update_market_statistics(state.statistics, result)
            new_state = %{state | statistics: new_stats}
            {:reply, {:ok, result}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_market_status, market_id}, _from, state) do
    case Map.get(state.active_markets, market_id) do
      nil ->
        {:reply, {:error, :market_not_found}, state}

      market_state ->
        status = %{
          id: market_state.id,
          status: market_state.status,
          order_count: length(market_state.orders),
          trade_count: length(market_state.trades),
          created_at: market_state.created_at,
          spec: market_state.spec
        }

        {:reply, {:ok, status}, state}
    end
  end

  @impl true
  def handle_call(:list_active_markets, _from, state) do
    active_market_ids = Map.keys(state.active_markets)
    {:reply, {:ok, active_market_ids}, state}
  end

  @impl true
  def handle_call(:get_statistics, _from, state) do
    {:reply, {:ok, state.statistics}, state}
  end

  ## Private Functions

  defp validate_market_spec(market_spec) do
    required_fields = [:name, :commodity, :market_type, :price_mechanism]

    cond do
      not is_map(market_spec) ->
        {:error, :invalid_market_spec}

      not Enum.all?(required_fields, &Map.has_key?(market_spec, &1)) ->
        {:error, :missing_required_fields}

      market_spec.market_type not in [:continuous, :call, :sealed_bid] ->
        {:error, :invalid_market_type}

      market_spec.price_mechanism not in [:auction, :negotiation, :fixed] ->
        {:error, :invalid_price_mechanism}

      true ->
        :ok
    end
  end

  defp validate_order(order) do
    required_fields = [:agent_id, :type, :quantity, :price]

    cond do
      not is_map(order) ->
        {:error, :invalid_order_format}

      not Enum.all?(required_fields, &Map.has_key?(order, &1)) ->
        {:error, :missing_required_fields}

      order.type not in [:buy, :sell] ->
        {:error, :invalid_order_type}

      not is_number(order.quantity) or order.quantity <= 0 ->
        {:error, :invalid_quantity}

      order.price != :market and (not is_number(order.price) or order.price <= 0) ->
        {:error, :invalid_price}

      true ->
        :ok
    end
  end

  defp match_orders(orders, existing_trades) do
    # Separate buy and sell orders
    {buy_orders, sell_orders} = Enum.split_with(orders, fn order -> order.type == :buy end)

    # Sort orders for matching (buy orders by price descending, sell orders by price ascending)
    sorted_buy_orders =
      Enum.sort_by(
        buy_orders,
        fn order ->
          if order.price == :market, do: 999_999, else: order.price
        end,
        :desc
      )

    sorted_sell_orders =
      Enum.sort_by(
        sell_orders,
        fn order ->
          if order.price == :market, do: 0, else: order.price
        end,
        :asc
      )

    # Match orders
    {remaining_orders, new_trades} =
      match_order_pairs(sorted_buy_orders, sorted_sell_orders, existing_trades)

    {remaining_orders, new_trades}
  end

  defp match_order_pairs(buy_orders, sell_orders, trades) do
    match_order_pairs(buy_orders, sell_orders, [], trades)
  end

  defp match_order_pairs([], sell_orders, unmatched_buy_orders, trades) do
    {unmatched_buy_orders ++ sell_orders, trades}
  end

  defp match_order_pairs(buy_orders, [], unmatched_buy_orders, trades) do
    {unmatched_buy_orders ++ buy_orders, trades}
  end

  defp match_order_pairs([buy_order | rest_buy], [sell_order | rest_sell], unmatched_buy, trades) do
    buy_price = if buy_order.price == :market, do: 999_999, else: buy_order.price
    sell_price = if sell_order.price == :market, do: 0, else: sell_order.price

    if buy_price >= sell_price do
      # Orders can be matched
      trade_quantity = min(buy_order.quantity, sell_order.quantity)
      # Simple price discovery
      trade_price = (buy_price + sell_price) / 2

      trade = %{
        buyer: buy_order.agent_id,
        seller: sell_order.agent_id,
        quantity: trade_quantity,
        price: trade_price,
        timestamp: DateTime.utc_now()
      }

      # Update order quantities
      updated_buy_order = %{buy_order | quantity: buy_order.quantity - trade_quantity}
      updated_sell_order = %{sell_order | quantity: sell_order.quantity - trade_quantity}

      # Continue matching with updated orders
      remaining_buy =
        if updated_buy_order.quantity > 0, do: [updated_buy_order | rest_buy], else: rest_buy

      remaining_sell =
        if updated_sell_order.quantity > 0, do: [updated_sell_order | rest_sell], else: rest_sell

      match_order_pairs(remaining_buy, remaining_sell, unmatched_buy, [trade | trades])
    else
      # No match possible, move buy order to unmatched
      match_order_pairs(rest_buy, [sell_order | rest_sell], [buy_order | unmatched_buy], trades)
    end
  end

  defp calculate_equilibrium(orders) do
    # Separate and sort orders
    {buy_orders, sell_orders} = Enum.split_with(orders, fn order -> order.type == :buy end)

    # Create demand and supply curves
    demand_curve = create_demand_curve(buy_orders)
    supply_curve = create_supply_curve(sell_orders)

    # Find intersection point
    case find_curve_intersection(demand_curve, supply_curve) do
      {:ok, {eq_price, eq_quantity}} ->
        consumer_surplus = calculate_consumer_surplus(demand_curve, eq_price, eq_quantity)
        producer_surplus = calculate_producer_surplus(supply_curve, eq_price, eq_quantity)

        %{
          equilibrium_price: eq_price,
          equilibrium_quantity: eq_quantity,
          consumer_surplus: consumer_surplus,
          producer_surplus: producer_surplus,
          total_welfare: consumer_surplus + producer_surplus
        }

      {:error, _reason} ->
        %{
          equilibrium_price: 0.0,
          equilibrium_quantity: 0.0,
          consumer_surplus: 0.0,
          producer_surplus: 0.0,
          total_welfare: 0.0
        }
    end
  end

  defp create_demand_curve(buy_orders) do
    # Sort buy orders by price descending
    sorted_orders =
      Enum.sort_by(
        buy_orders,
        fn order ->
          if order.price == :market, do: 999_999, else: order.price
        end,
        :desc
      )

    # Create cumulative demand curve
    {curve, _} =
      Enum.reduce(sorted_orders, {[], 0}, fn order, {curve, cumulative_qty} ->
        price = if order.price == :market, do: 999_999, else: order.price
        new_cumulative = cumulative_qty + order.quantity
        {[{price, new_cumulative} | curve], new_cumulative}
      end)

    Enum.reverse(curve)
  end

  defp create_supply_curve(sell_orders) do
    # Sort sell orders by price ascending
    sorted_orders =
      Enum.sort_by(
        sell_orders,
        fn order ->
          if order.price == :market, do: 0, else: order.price
        end,
        :asc
      )

    # Create cumulative supply curve
    {curve, _} =
      Enum.reduce(sorted_orders, {[], 0}, fn order, {curve, cumulative_qty} ->
        price = if order.price == :market, do: 0, else: order.price
        new_cumulative = cumulative_qty + order.quantity
        {[{price, new_cumulative} | curve], new_cumulative}
      end)

    Enum.reverse(curve)
  end

  defp find_curve_intersection(demand_curve, supply_curve) do
    # Simple intersection finding - in reality this would be more sophisticated
    case {demand_curve, supply_curve} do
      {[], _} ->
        {:error, :no_demand}

      {_, []} ->
        {:error, :no_supply}

      {[{d_price, d_qty} | _], [{s_price, s_qty} | _]} ->
        # Simple approximation
        eq_price = (d_price + s_price) / 2
        eq_quantity = min(d_qty, s_qty)
        {:ok, {eq_price, eq_quantity}}
    end
  end

  defp calculate_consumer_surplus(demand_curve, eq_price, eq_quantity) do
    # Simplified consumer surplus calculation
    case demand_curve do
      [] ->
        0.0

      [{max_price, _} | _] ->
        if max_price > eq_price do
          (max_price - eq_price) * eq_quantity / 2
        else
          0.0
        end
    end
  end

  defp calculate_producer_surplus(supply_curve, eq_price, eq_quantity) do
    # Simplified producer surplus calculation
    case supply_curve do
      [] ->
        0.0

      [{min_price, _} | _] ->
        if eq_price > min_price do
          (eq_price - min_price) * eq_quantity / 2
        else
          0.0
        end
    end
  end

  defp run_market_simulation(market_state) do
    # Validate market state
    cond do
      not Map.has_key?(market_state, :spec) ->
        {:error, :missing_market_spec}

      not Map.has_key?(market_state, :orders) ->
        {:error, :missing_orders}

      true ->
        # Run the market mechanism based on market type
        case market_state.spec.market_type do
          :continuous ->
            {_remaining_orders, trades} = match_orders(market_state.orders, [])

            result = %{
              trades: trades,
              clearing_price: calculate_clearing_price(trades),
              total_volume: calculate_total_volume(trades),
              market_efficiency: calculate_market_efficiency(trades, market_state.orders),
              participants: get_participants(market_state.orders),
              metadata: %{market_type: :continuous}
            }

            {:ok, result}

          :call ->
            # Call market: collect all orders then clear at once
            equilibrium = calculate_equilibrium(market_state.orders)
            trades = simulate_clearing_trades(market_state.orders, equilibrium.equilibrium_price)

            result = %{
              trades: trades,
              clearing_price: equilibrium.equilibrium_price,
              total_volume: calculate_total_volume(trades),
              market_efficiency: calculate_market_efficiency(trades, market_state.orders),
              participants: get_participants(market_state.orders),
              metadata: %{market_type: :call, equilibrium: equilibrium}
            }

            {:ok, result}

          :sealed_bid ->
            # Sealed bid market: similar to call but with different price discovery
            result = simulate_sealed_bid_market(market_state.orders)
            {:ok, result}

          _ ->
            {:error, :unsupported_market_type}
        end
    end
  end

  defp calculate_clearing_price(trades) do
    if Enum.empty?(trades) do
      nil
    else
      total_value = Enum.sum(Enum.map(trades, fn trade -> trade.price * trade.quantity end))
      total_quantity = Enum.sum(Enum.map(trades, fn trade -> trade.quantity end))
      if total_quantity > 0, do: total_value / total_quantity, else: 0.0
    end
  end

  defp calculate_total_volume(trades) do
    Enum.sum(Enum.map(trades, fn trade -> trade.quantity end))
  end

  defp calculate_market_efficiency(trades, orders) do
    if Enum.empty?(trades) or Enum.empty?(orders) do
      0.0
    else
      # Simple efficiency metric: ratio of traded volume to total order volume
      total_order_volume = Enum.sum(Enum.map(orders, fn order -> order.quantity end))
      traded_volume = calculate_total_volume(trades)
      if total_order_volume > 0, do: traded_volume / total_order_volume, else: 0.0
    end
  end

  defp get_participants(orders) do
    orders
    |> Enum.map(fn order -> order.agent_id end)
    |> Enum.uniq()
  end

  defp simulate_clearing_trades(orders, clearing_price) do
    {buy_orders, sell_orders} = Enum.split_with(orders, fn order -> order.type == :buy end)

    # Filter orders that would trade at clearing price
    valid_buy_orders =
      Enum.filter(buy_orders, fn order ->
        order.price == :market or order.price >= clearing_price
      end)

    valid_sell_orders =
      Enum.filter(sell_orders, fn order ->
        order.price == :market or order.price <= clearing_price
      end)

    # Match orders at clearing price
    total_buy_quantity = Enum.sum(Enum.map(valid_buy_orders, fn order -> order.quantity end))
    total_sell_quantity = Enum.sum(Enum.map(valid_sell_orders, fn order -> order.quantity end))

    trade_quantity = min(total_buy_quantity, total_sell_quantity)

    # Create trades (simplified - in reality would need more sophisticated allocation)
    if trade_quantity > 0 and not Enum.empty?(valid_buy_orders) and
         not Enum.empty?(valid_sell_orders) do
      buyer = hd(valid_buy_orders).agent_id
      seller = hd(valid_sell_orders).agent_id

      [
        %{
          buyer: buyer,
          seller: seller,
          quantity: trade_quantity,
          price: clearing_price,
          timestamp: DateTime.utc_now()
        }
      ]
    else
      []
    end
  end

  defp simulate_sealed_bid_market(orders) do
    # Sealed bid market simulation
    equilibrium = calculate_equilibrium(orders)
    trades = simulate_clearing_trades(orders, equilibrium.equilibrium_price)

    %{
      trades: trades,
      clearing_price: equilibrium.equilibrium_price,
      total_volume: calculate_total_volume(trades),
      market_efficiency: calculate_market_efficiency(trades, orders),
      participants: get_participants(orders),
      metadata: %{market_type: :sealed_bid, equilibrium: equilibrium}
    }
  end

  defp calculate_market_result(market_state) do
    %{
      trades: market_state.trades,
      clearing_price: calculate_clearing_price(market_state.trades),
      total_volume: calculate_total_volume(market_state.trades),
      market_efficiency: calculate_market_efficiency(market_state.trades, market_state.orders),
      participants: get_participants(market_state.orders),
      metadata: %{
        market_spec: market_state.spec,
        total_orders: length(market_state.orders),
        created_at: market_state.created_at,
        closed_at: DateTime.utc_now()
      }
    }
  end

  defp update_market_statistics(current_stats, market_result) do
    trade_count = length(market_result.trades)
    is_successful = trade_count > 0

    %{
      total_markets: current_stats.total_markets,
      successful_markets:
        if(is_successful,
          do: current_stats.successful_markets + 1,
          else: current_stats.successful_markets
        ),
      failed_markets:
        if(is_successful, do: current_stats.failed_markets, else: current_stats.failed_markets + 1),
      total_trades: current_stats.total_trades + trade_count,
      total_volume: current_stats.total_volume + market_result.total_volume,
      average_efficiency: calculate_new_average_efficiency(current_stats, market_result)
    }
  end

  defp calculate_new_average_efficiency(current_stats, market_result) do
    if current_stats.total_markets == 0 do
      market_result.market_efficiency
    else
      current_total = current_stats.average_efficiency * current_stats.total_markets
      new_total = current_total + market_result.market_efficiency
      new_total / (current_stats.total_markets + 1)
    end
  end
end
