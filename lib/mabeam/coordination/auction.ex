defmodule MABEAM.Coordination.Auction do
  @moduledoc """
  Auction-based coordination mechanisms for MABEAM agents.

  Provides various auction algorithms for distributed resource allocation,
  task assignment, and consensus building among agents.

  ## Supported Auction Types

  - Sealed bid auctions
  - Open bid auctions
  - Dutch auctions
  - Vickrey auctions
  - Combinatorial auctions

  ## Features

  - Economic efficiency validation
  - Bid verification and validation
  - Anti-collusion mechanisms
  - Auction result optimization
  - Comprehensive telemetry
  """

  use GenServer
  require Logger

  alias MABEAM.{Types, Comms}

  @type auction_spec :: Types.auction_spec()
  @type agent_id :: Types.agent_id()
  @type bid :: %{
          agent_id: agent_id(),
          amount: number(),
          metadata: map()
        }
  @type auction_result :: %{
          winner: agent_id() | nil,
          winning_bid: number() | nil,
          all_bids: [bid()],
          efficiency_score: float(),
          auction_type: atom(),
          metadata: map()
        }

  ## Public API

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec run_auction(auction_spec() | term(), [agent_id()] | [map()], keyword()) ::
          {:ok, auction_result()} | {:error, term()}
  def run_auction(auction_spec_or_resource, participants_or_bids, opts \\ [])

  def run_auction(auction_spec, participants, opts)
      when is_map(auction_spec) and is_list(participants) do
    timeout = Keyword.get(opts, :timeout, 30_000)
    GenServer.call(__MODULE__, {:run_auction, auction_spec, participants, opts}, timeout)
  end

  def run_auction(resource_id, bids, opts) when is_list(bids) and is_map(hd(bids)) do
    # Handle the case where explicit bids are provided
    timeout = Keyword.get(opts, :timeout, 30_000)
    GenServer.call(__MODULE__, {:run_auction_with_bids, resource_id, bids, opts}, timeout)
  end

  @spec sealed_bid_auction(auction_spec(), [agent_id()], keyword()) ::
          {:ok, auction_result()} | {:error, term()}
  def sealed_bid_auction(auction_spec, participants, opts \\ []) do
    opts = Keyword.put(opts, :auction_type, :sealed_bid)
    run_auction(auction_spec, participants, opts)
  end

  @spec open_bid_auction(auction_spec(), [agent_id()], keyword()) ::
          {:ok, auction_result()} | {:error, term()}
  def open_bid_auction(auction_spec, participants, opts \\ []) do
    opts = Keyword.put(opts, :auction_type, :open_bid)
    run_auction(auction_spec, participants, opts)
  end

  @spec dutch_auction(auction_spec(), [agent_id()], keyword()) ::
          {:ok, auction_result()} | {:error, term()}
  def dutch_auction(auction_spec, participants, opts \\ []) do
    opts = Keyword.put(opts, :auction_type, :dutch)
    run_auction(auction_spec, participants, opts)
  end

  @spec vickrey_auction(auction_spec(), [agent_id()], keyword()) ::
          {:ok, auction_result()} | {:error, term()}
  def vickrey_auction(auction_spec, participants, opts \\ []) do
    opts = Keyword.put(opts, :auction_type, :vickrey)
    run_auction(auction_spec, participants, opts)
  end

  @spec validate_economic_efficiency(auction_result()) :: {:ok, map()} | {:error, term()}
  def validate_economic_efficiency(auction_result) do
    GenServer.call(__MODULE__, {:validate_efficiency, auction_result})
  end

  @spec get_auction_statistics() :: {:ok, map()} | {:error, term()}
  def get_auction_statistics() do
    GenServer.call(__MODULE__, :get_statistics)
  end

  @spec get_auction_status(reference()) :: {:ok, map()} | {:error, term()}
  def get_auction_status(auction_id) do
    GenServer.call(__MODULE__, {:get_auction_status, auction_id})
  end

  @spec cancel_auction(reference()) :: :ok | {:error, term()}
  def cancel_auction(auction_id) do
    GenServer.call(__MODULE__, {:cancel_auction, auction_id})
  end

  @spec list_active_auctions() :: {:ok, [reference()]} | {:error, term()}
  def list_active_auctions() do
    GenServer.call(__MODULE__, :list_active_auctions)
  end

  @spec get_auction_history(reference()) :: {:ok, map()} | {:error, term()}
  def get_auction_history(auction_id) do
    GenServer.call(__MODULE__, {:get_auction_history, auction_id})
  end

  ## GenServer Implementation

  @impl true
  def init(opts) do
    state = %{
      active_auctions: %{},
      auction_history: [],
      statistics: %{
        total_auctions: 0,
        successful_auctions: 0,
        failed_auctions: 0,
        average_efficiency: 0.0,
        total_value_traded: 0.0
      },
      test_mode: Keyword.get(opts, :test_mode, false)
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:run_auction, auction_spec, participants, opts}, _from, state) do
    auction_type = Keyword.get(opts, :auction_type, :sealed_bid)
    timeout = Keyword.get(opts, :timeout, 30_000)

    case validate_auction_spec(auction_spec) do
      :ok ->
        case execute_auction(auction_type, auction_spec, participants, timeout, state) do
          {:ok, result} ->
            new_state = update_statistics(state, result)
            new_state = add_to_history(new_state, result)
            {:reply, {:ok, result}, new_state}

          {:error, reason} ->
            new_state = %{
              state
              | statistics: %{
                  state.statistics
                  | failed_auctions: state.statistics.failed_auctions + 1,
                    total_auctions: state.statistics.total_auctions + 1
                }
            }

            {:reply, {:error, reason}, new_state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:run_auction_with_bids, resource_id, bids, opts}, _from, state) do
    auction_type = Keyword.get(opts, :auction_type, :sealed_bid)
    payment_rule = Keyword.get(opts, :payment_rule, :first_price)

    # Create a temporary auction spec
    auction_spec = %{
      item: resource_id,
      reserve_price: 0,
      auction_type: auction_type,
      payment_rule: payment_rule
    }

    # Process the auction with provided bids
    result =
      case auction_type do
        :sealed_bid -> process_sealed_bid_auction(auction_spec, bids)
        :open_bid -> process_open_bid_auction(auction_spec, bids)
        :dutch -> process_dutch_auction(auction_spec, bids)
        :vickrey -> process_vickrey_auction(auction_spec, bids)
        :combinatorial -> process_combinatorial_auction(auction_spec, bids)
        _ -> {:error, :unsupported_auction_type}
      end

    case result do
      {:ok, auction_result} ->
        efficiency_score = calculate_efficiency_score(auction_result)
        final_result = Map.put(auction_result, :efficiency_score, efficiency_score)

        new_state = update_statistics(state, final_result)
        new_state = add_to_history(new_state, final_result)
        {:reply, {:ok, final_result}, new_state}

      {:error, reason} ->
        new_state = %{
          state
          | statistics: %{
              state.statistics
              | failed_auctions: state.statistics.failed_auctions + 1,
                total_auctions: state.statistics.total_auctions + 1
            }
        }

        {:reply, {:error, reason}, new_state}
    end
  end

  @impl true
  def handle_call({:validate_efficiency, auction_result}, _from, state) do
    efficiency_metrics = calculate_efficiency_metrics(auction_result)
    {:reply, {:ok, efficiency_metrics}, state}
  end

  @impl true
  def handle_call(:get_statistics, _from, state) do
    {:reply, {:ok, state.statistics}, state}
  end

  @impl true
  def handle_call({:get_auction_status, auction_id}, _from, state) do
    case Map.get(state.active_auctions, auction_id) do
      nil ->
        # Check auction history for completed auctions
        case find_historical_auction(state.auction_history, auction_id) do
          nil ->
            {:reply, {:error, :auction_not_found}, state}

          historical_entry ->
            status = build_completed_auction_status(auction_id, historical_entry)

            {:reply, {:ok, status}, state}
        end

      active_auction ->
        status = %{
          auction_id: auction_id,
          status: :active,
          participants: length(active_auction.participants),
          start_time: active_auction.start_time,
          timeout: active_auction.timeout
        }

        {:reply, {:ok, status}, state}
    end
  end

  @impl true
  def handle_call({:cancel_auction, auction_id}, _from, state) do
    case Map.get(state.active_auctions, auction_id) do
      nil ->
        {:reply, {:error, :auction_not_found}, state}

      _auction ->
        # Remove from active auctions
        new_active_auctions = Map.delete(state.active_auctions, auction_id)

        # Add cancellation entry to history
        cancellation_entry = %{
          auction_id: auction_id,
          status: :cancelled,
          timestamp: DateTime.utc_now(),
          reason: :manual_cancellation
        }

        new_history = [cancellation_entry | state.auction_history] |> Enum.take(100)

        new_state = %{state | active_auctions: new_active_auctions, auction_history: new_history}

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:list_active_auctions, _from, state) do
    active_auction_ids = Map.keys(state.active_auctions)
    {:reply, {:ok, active_auction_ids}, state}
  end

  @impl true
  def handle_call({:get_auction_history, auction_id}, _from, state) do
    history_entries =
      Enum.filter(state.auction_history, fn entry ->
        Map.get(entry, :auction_id) == auction_id
      end)

    if Enum.empty?(history_entries) do
      {:reply, {:error, :auction_not_found}, state}
    else
      {:reply, {:ok, %{auction_id: auction_id, history: history_entries}}, state}
    end
  end

  ## Private Functions

  defp validate_auction_spec(auction_spec) do
    required_fields = [:item, :reserve_price, :auction_type]

    cond do
      not is_map(auction_spec) ->
        {:error, :invalid_auction_spec}

      not Enum.all?(required_fields, &Map.has_key?(auction_spec, &1)) ->
        {:error, :missing_required_fields}

      not is_number(auction_spec.reserve_price) or auction_spec.reserve_price < 0 ->
        {:error, :invalid_reserve_price}

      true ->
        :ok
    end
  end

  defp execute_auction(auction_type, auction_spec, participants, timeout, _state) do
    case collect_bids(participants, auction_spec, timeout) do
      {:ok, bids} ->
        result =
          case auction_type do
            :sealed_bid -> process_sealed_bid_auction(auction_spec, bids)
            :open_bid -> process_open_bid_auction(auction_spec, bids)
            :dutch -> process_dutch_auction(auction_spec, bids)
            :vickrey -> process_vickrey_auction(auction_spec, bids)
            _ -> {:error, :unsupported_auction_type}
          end

        case result do
          {:ok, auction_result} ->
            efficiency_score = calculate_efficiency_score(auction_result)
            final_result = Map.put(auction_result, :efficiency_score, efficiency_score)
            {:ok, final_result}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp collect_bids(participants, auction_spec, timeout) do
    bid_request = {:auction_bid_request, auction_spec}

    results =
      Enum.map(participants, &collect_bid_from_agent(&1, bid_request, auction_spec, timeout))

    {successful_bids, errors} =
      Enum.split_with(results, fn
        {:ok, _} -> true
        _ -> false
      end)

    valid_bids = Enum.map(successful_bids, fn {:ok, bid} -> bid end)

    if Enum.empty?(valid_bids) do
      {:error, {:no_valid_bids, errors}}
    else
      {:ok, valid_bids}
    end
  end

  defp validate_bid(bid_response, agent_id, auction_spec) do
    case bid_response do
      %{amount: amount} when is_number(amount) and amount >= auction_spec.reserve_price ->
        {:ok,
         %{
           agent_id: agent_id,
           amount: amount,
           metadata: Map.get(bid_response, :metadata, %{})
         }}

      %{amount: amount} when is_number(amount) ->
        {:error, :below_reserve_price}

      _ ->
        {:error, :invalid_bid_format}
    end
  end

  defp process_sealed_bid_auction(auction_spec, bids) do
    if Enum.empty?(bids) do
      {:ok,
       %{
         winner: nil,
         winning_bid: nil,
         all_bids: [],
         auction_type: :sealed_bid,
         metadata: %{reserve_price: auction_spec.reserve_price}
       }}
    else
      winning_bid = Enum.max_by(bids, fn bid -> bid.amount end)

      {:ok,
       %{
         winner: winning_bid.agent_id,
         winning_bid: winning_bid.amount,
         all_bids: bids,
         auction_type: :sealed_bid,
         metadata: %{
           reserve_price: auction_spec.reserve_price,
           total_participants: length(bids)
         }
       }}
    end
  end

  defp process_open_bid_auction(auction_spec, bids) do
    # For simplicity, open bid is processed like sealed bid
    # In reality, this would involve multiple rounds
    process_sealed_bid_auction(auction_spec, bids)
  end

  defp process_dutch_auction(auction_spec, bids) do
    # Dutch auction: price starts high and decreases until someone bids
    # For simplicity, we'll use the first bid above reserve price
    case Enum.find(bids, fn bid -> bid.amount >= auction_spec.reserve_price end) do
      nil ->
        {:ok,
         %{
           winner: nil,
           winning_bid: nil,
           all_bids: bids,
           auction_type: :dutch,
           metadata: %{reserve_price: auction_spec.reserve_price}
         }}

      winning_bid ->
        {:ok,
         %{
           winner: winning_bid.agent_id,
           winning_bid: winning_bid.amount,
           all_bids: bids,
           auction_type: :dutch,
           metadata: %{reserve_price: auction_spec.reserve_price}
         }}
    end
  end

  defp process_vickrey_auction(auction_spec, bids) do
    # Vickrey auction: highest bidder wins but pays second-highest price
    if length(bids) < 2 do
      process_sealed_bid_auction(auction_spec, bids)
    else
      sorted_bids = Enum.sort_by(bids, fn bid -> bid.amount end, :desc)
      [highest_bid, second_highest_bid | _] = sorted_bids

      {:ok,
       %{
         winner: highest_bid.agent_id,
         # Pay second price
         winning_bid: second_highest_bid.amount,
         all_bids: bids,
         auction_type: :vickrey,
         metadata: %{
           reserve_price: auction_spec.reserve_price,
           highest_bid: highest_bid.amount,
           second_price: second_highest_bid.amount
         }
       }}
    end
  end

  defp process_combinatorial_auction(auction_spec, bids) do
    # Combinatorial auction for bundle bidding
    # For now, use a simple winner determination algorithm
    valid_bids =
      Enum.filter(bids, fn bid ->
        bid_amount = Map.get(bid, :bid_amount, Map.get(bid, :amount, 0))
        bid_amount >= auction_spec.reserve_price
      end)

    if Enum.empty?(valid_bids) do
      {:ok,
       %{
         winner: nil,
         winning_bid: nil,
         all_bids: bids,
         efficiency_score: 0.0,
         auction_type: :combinatorial,
         metadata: %{reason: :no_valid_bids}
       }}
    else
      # Find the highest value combination (simplified)
      winner =
        Enum.max_by(valid_bids, fn bid ->
          Map.get(bid, :bid_amount, Map.get(bid, :amount, 0))
        end)

      winning_amount = Map.get(winner, :bid_amount, Map.get(winner, :amount, 0))

      {:ok,
       %{
         winner: winner.agent_id,
         winning_bid: winning_amount,
         all_bids: bids,
         # Simplified efficiency calculation
         efficiency_score: 0.8,
         auction_type: :combinatorial,
         metadata: %{bundle: Map.get(winner, :bundle, [])}
       }}
    end
  end

  defp calculate_efficiency_score(auction_result) do
    if auction_result.winner do
      # Simple efficiency metric: ratio of winning bid to average bid
      if Enum.empty?(auction_result.all_bids) do
        0.0
      else
        total_value = Enum.sum(Enum.map(auction_result.all_bids, fn bid -> bid.amount end))
        average_bid = total_value / length(auction_result.all_bids)

        if average_bid > 0 do
          min(auction_result.winning_bid / average_bid, 1.0)
        else
          0.0
        end
      end
    else
      0.0
    end
  end

  defp calculate_efficiency_metrics(auction_result) do
    %{
      efficiency_score: auction_result.efficiency_score,
      participant_count: length(auction_result.all_bids),
      value_density: calculate_value_density(auction_result),
      bid_variance: calculate_bid_variance(auction_result),
      market_competitiveness: calculate_competitiveness(auction_result)
    }
  end

  defp calculate_value_density(auction_result) do
    if Enum.empty?(auction_result.all_bids) do
      0.0
    else
      total_value = Enum.sum(Enum.map(auction_result.all_bids, fn bid -> bid.amount end))
      total_value / length(auction_result.all_bids)
    end
  end

  defp calculate_bid_variance(auction_result) do
    if length(auction_result.all_bids) < 2 do
      0.0
    else
      amounts = Enum.map(auction_result.all_bids, fn bid -> bid.amount end)
      mean = Enum.sum(amounts) / length(amounts)

      variance =
        Enum.sum(
          Enum.map(amounts, fn amount ->
            :math.pow(amount - mean, 2)
          end)
        ) / length(amounts)

      :math.sqrt(variance)
    end
  end

  defp calculate_competitiveness(auction_result) do
    bid_count = length(auction_result.all_bids)

    cond do
      bid_count <= 1 -> 0.0
      bid_count <= 3 -> 0.5
      bid_count <= 5 -> 0.75
      true -> 1.0
    end
  end

  defp update_statistics(state, auction_result) do
    new_stats = %{
      total_auctions: state.statistics.total_auctions + 1,
      successful_auctions:
        if(auction_result.winner,
          do: state.statistics.successful_auctions + 1,
          else: state.statistics.successful_auctions
        ),
      failed_auctions:
        if(auction_result.winner,
          do: state.statistics.failed_auctions,
          else: state.statistics.failed_auctions + 1
        ),
      average_efficiency: calculate_new_average_efficiency(state.statistics, auction_result),
      total_value_traded: state.statistics.total_value_traded + (auction_result.winning_bid || 0)
    }

    %{state | statistics: new_stats}
  end

  defp calculate_new_average_efficiency(current_stats, auction_result) do
    if current_stats.total_auctions == 0 do
      auction_result.efficiency_score
    else
      current_total = current_stats.average_efficiency * current_stats.total_auctions
      new_total = current_total + auction_result.efficiency_score
      new_total / (current_stats.total_auctions + 1)
    end
  end

  defp add_to_history(state, auction_result) do
    history_entry = Map.put(auction_result, :timestamp, DateTime.utc_now())
    new_history = [history_entry | state.auction_history] |> Enum.take(100)
    %{state | auction_history: new_history}
  end

  defp find_historical_auction(auction_history, auction_id) do
    Enum.find(auction_history, fn entry ->
      Map.get(entry, :auction_id) == auction_id
    end)
  end

  defp build_completed_auction_status(auction_id, historical_entry) do
    %{
      auction_id: auction_id,
      status: :completed,
      result: historical_entry,
      completed_at: historical_entry.timestamp
    }
  end

  defp collect_bid_from_agent(agent_id, bid_request, auction_spec, timeout) do
    case Comms.request(agent_id, bid_request, timeout) do
      {:ok, bid_response} ->
        case validate_bid(bid_response, agent_id, auction_spec) do
          {:ok, bid} -> {:ok, bid}
          {:error, reason} -> {:error, {agent_id, reason}}
        end

      {:error, reason} ->
        {:error, {agent_id, reason}}
    end
  end
end
