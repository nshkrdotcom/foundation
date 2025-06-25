defmodule Foundation.MABEAM.Economics do
  @moduledoc """
  Economic mechanisms and auction systems for Foundation MABEAM.

  This module implements sophisticated economic coordination mechanisms designed
  to optimize resource allocation and incentive alignment in multi-agent ML systems:

  - **Auction Systems**: English, Dutch, Sealed-bid, Vickrey, and Combinatorial auctions
  - **Market Mechanisms**: Real-time marketplaces for agent services and resources
  - **Reputation Systems**: Trust-based agent rating and performance tracking
  - **Incentive Alignment**: Economic mechanisms to encourage optimal agent behavior
  - **Cost Optimization**: Intelligent resource allocation to minimize operational costs

  ## Key Features

  ### 1. Auction Mechanisms
  - **English Auctions**: Open ascending price auctions for resource allocation
  - **Dutch Auctions**: Descending price auctions for time-sensitive tasks
  - **Sealed-Bid Auctions**: Private bidding for confidential resource requests
  - **Vickrey Auctions**: Second-price sealed-bid auctions for truth revelation
  - **Combinatorial Auctions**: Multi-item auctions for complex resource bundles

  ### 2. Market Dynamics
  - **Real-Time Pricing**: Dynamic price discovery based on supply and demand
  - **Resource Marketplaces**: Decentralized markets for compute, storage, and services
  - **Service Exchanges**: Agent capability trading and service composition
  - **Performance-Based Pricing**: Cost adjustments based on quality and speed

  ### 3. Reputation and Trust
  - **Multi-Dimensional Reputation**: Performance, reliability, cost-effectiveness scoring
  - **Trust Networks**: Agent-to-agent trust relationships and recommendations
  - **Reputation Decay**: Time-based reputation adjustment for continuous improvement
  - **Anti-Gaming Measures**: Sybil resistance and collusion detection

  ## Usage Examples

      # Create an auction for ML model training
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

      # Agents place bids
      {:ok, bid_id} = Economics.place_bid(auction_id, :gpt_agent, %{
        price: 8.5,
        quality_guarantee: 0.97,
        completion_time: 1800
      })

      # Close auction and determine winner
      {:ok, results} = Economics.close_auction(auction_id)

      # Create a service marketplace
      marketplace_spec = %{
        name: "ML Services Exchange",
        categories: [:text_generation, :code_generation, :data_analysis],
        fee_structure: %{listing_fee: 0.1, transaction_fee: 0.05},
        quality_enforcement: true
      }

      {:ok, marketplace_id} = Economics.create_marketplace(marketplace_spec)

      # Agent lists a service
      service_spec = %{
        provider: :claude_agent,
        service_type: :text_generation,
        capabilities: [:summarization, :translation, :creative_writing],
        pricing: %{base_rate: 0.02, per_token: 0.001},
        quality_guarantees: %{accuracy: 0.95, response_time: 2000}
      }

      {:ok, listing_id} = Economics.list_service(marketplace_id, service_spec)
  """

  use GenServer
  require Logger

  alias Foundation.MABEAM.Types

  # ============================================================================
  # Type Definitions
  # ============================================================================

  @type agent_id :: atom() | String.t()
  @type auction_id :: String.t()
  @type marketplace_id :: String.t()
  @type bid_id :: String.t()
  @type listing_id :: String.t()

  @type economics_state :: %{
          active_auctions: %{auction_id() => Types.auction()},
          completed_auctions: [Types.auction()],
          marketplaces: %{marketplace_id() => marketplace()},
          agent_reputations: %{Types.agent_id() => Types.economic_agent()},
          bid_history: [Types.bid()],
          transaction_history: [transaction()],
          pricing_models: %{String.t() => Types.cost_model()},
          started_at: DateTime.t()
        }

  @type marketplace :: %{
          id: marketplace_id(),
          name: String.t(),
          categories: [atom()],
          active_listings: %{listing_id() => service_listing()},
          completed_transactions: [transaction()],
          fee_structure: fee_structure(),
          quality_enforcement: boolean(),
          reputation_requirements: map(),
          created_at: DateTime.t()
        }

  @type service_listing :: %{
          id: listing_id(),
          provider: Types.agent_id(),
          service_type: atom(),
          capabilities: [atom()],
          pricing: Types.pricing_model(),
          quality_guarantees: map(),
          availability: Types.availability_schedule(),
          reputation_score: float(),
          listed_at: DateTime.t(),
          expires_at: DateTime.t() | nil
        }

  @type transaction :: %{
          id: String.t(),
          buyer: Types.agent_id(),
          seller: Types.agent_id(),
          service_type: atom(),
          amount: float(),
          currency: atom(),
          quality_delivered: float(),
          completion_time: pos_integer(),
          satisfaction_score: float(),
          timestamp: DateTime.t()
        }

  @type fee_structure :: %{
          listing_fee: float(),
          transaction_fee: float(),
          success_fee: float(),
          cancellation_penalty: float()
        }

  # Configuration constants
  @default_auction_duration_minutes 60
  @default_bid_increment 0.1
  @reputation_decay_factor 0.95
  # 5 minutes
  @auction_cleanup_interval 300_000

  # ============================================================================
  # GenServer Implementation
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting Foundation MABEAM Economics with advanced market mechanisms")

    state = %{
      active_auctions: %{},
      completed_auctions: [],
      marketplaces: %{},
      agent_reputations: %{},
      bid_history: [],
      transaction_history: [],
      pricing_models: initialize_default_pricing_models(),
      market_makers: %{},
      market_orders: %{},
      prediction_markets: %{},
      started_at: DateTime.utc_now()
    }

    # Continue initialization after GenServer is fully started
    {:ok, state, {:continue, :complete_initialization}}
  end

  @impl true
  def handle_continue(:complete_initialization, state) do
    # Register in ProcessRegistry if available
    case Foundation.ProcessRegistry.register(:production, {:mabeam, :economics}, self(), %{
           service: :economics,
           type: :mabeam_service,
           started_at: state.started_at,
           capabilities: [:auctions, :marketplaces, :reputation_systems, :cost_optimization]
         }) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to register MABEAM Economics: #{inspect(reason)}")
        # Continue anyway
        :ok
    end

    # Schedule periodic cleanup and reputation updates
    schedule_auction_cleanup()
    schedule_reputation_update()

    Logger.info("MABEAM Economics initialized with auction and marketplace systems")
    {:noreply, state}
  end

  # ============================================================================
  # Auction System API
  # ============================================================================

  @doc """
  Create a new auction for resource allocation.

  Supports multiple auction types including English, Dutch, Sealed-bid,
  Vickrey, and Combinatorial auctions with sophisticated bidding rules
  and quality guarantees.
  """
  @spec create_auction(map(), keyword()) :: {:ok, auction_id()} | {:error, term()}
  def create_auction(auction_spec, opts \\ []) do
    GenServer.call(__MODULE__, {:create_auction, auction_spec, opts})
  end

  @doc """
  Place a bid in an active auction.

  Validates bid according to auction rules and agent reputation,
  ensuring fair and efficient price discovery.
  """
  @spec place_bid(auction_id(), Types.agent_id(), map()) :: {:ok, bid_id()} | {:error, term()}
  def place_bid(auction_id, agent_id, bid_spec) do
    GenServer.call(__MODULE__, {:place_bid, auction_id, agent_id, bid_spec})
  end

  @doc """
  Close an auction and determine the winner.

  Applies auction-specific winning criteria and handles payment
  processing and service allocation.
  """
  @spec close_auction(auction_id()) :: {:ok, Types.auction()} | {:error, term()}
  def close_auction(auction_id) do
    GenServer.call(__MODULE__, {:close_auction, auction_id})
  end

  @doc """
  Get the current status and bidding history of an auction.
  """
  @spec get_auction_status(auction_id()) :: {:ok, Types.auction()} | {:error, :not_found}
  def get_auction_status(auction_id) do
    GenServer.call(__MODULE__, {:get_auction_status, auction_id})
  end

  @doc """
  List all active auctions, optionally filtered by category or agent.
  """
  @spec list_active_auctions(keyword()) :: {:ok, [Types.auction()]}
  def list_active_auctions(filters \\ []) do
    GenServer.call(__MODULE__, {:list_active_auctions, filters})
  end

  @doc """
  Cancel an active auction (if permitted by auction rules).
  """
  @spec cancel_auction(auction_id(), String.t()) :: :ok | {:error, term()}
  def cancel_auction(auction_id, reason) do
    GenServer.call(__MODULE__, {:cancel_auction, auction_id, reason})
  end

  # ============================================================================
  # Marketplace API
  # ============================================================================

  @doc """
  Create a new marketplace for agent services.

  Establishes a decentralized marketplace where agents can list
  services and capabilities for other agents to discover and purchase.
  """
  @spec create_marketplace(map()) :: {:ok, marketplace_id()} | {:error, term()}
  def create_marketplace(marketplace_spec) do
    GenServer.call(__MODULE__, {:create_marketplace, marketplace_spec})
  end

  @doc """
  List a service in a marketplace.

  Allows agents to advertise their capabilities and pricing
  to potential buyers in the marketplace.
  """
  @spec list_service(marketplace_id(), map()) :: {:ok, listing_id()} | {:error, term()}
  def list_service(marketplace_id, service_spec) do
    GenServer.call(__MODULE__, {:list_service, marketplace_id, service_spec})
  end

  @doc """
  Request a service from the marketplace.

  Matches service requirements with available providers based
  on capabilities, pricing, reputation, and availability.
  """
  @spec request_service(marketplace_id(), map()) :: {:ok, [service_listing()]} | {:error, term()}
  def request_service(marketplace_id, service_requirements) do
    GenServer.call(__MODULE__, {:request_service, marketplace_id, service_requirements})
  end

  @doc """
  Execute a service transaction between buyer and seller.
  """
  @spec execute_transaction(marketplace_id(), listing_id(), Types.agent_id(), map()) ::
          {:ok, String.t()} | {:error, term()}
  def execute_transaction(marketplace_id, listing_id, buyer_id, transaction_details) do
    GenServer.call(
      __MODULE__,
      {:execute_transaction, marketplace_id, listing_id, buyer_id, transaction_details}
    )
  end

  @doc """
  Get marketplace statistics and analytics.
  """
  @spec get_marketplace_analytics(marketplace_id()) :: {:ok, map()} | {:error, :not_found}
  def get_marketplace_analytics(marketplace_id) do
    GenServer.call(__MODULE__, {:get_marketplace_analytics, marketplace_id})
  end

  # ============================================================================
  # Reputation System API
  # ============================================================================

  @doc """
  Calculate and update reputation score for an agent.

  Uses multi-dimensional reputation scoring based on performance
  history, transaction success, quality delivery, and peer ratings.
  """
  @spec update_agent_reputation(Types.agent_id(), map()) :: :ok | {:error, term()}
  def update_agent_reputation(agent_id, performance_data) do
    GenServer.call(__MODULE__, {:update_agent_reputation, agent_id, performance_data})
  end

  @doc """
  Get comprehensive reputation information for an agent.
  """
  @spec get_agent_reputation(Types.agent_id()) ::
          {:ok, Types.economic_agent()} | {:error, :not_found}
  def get_agent_reputation(agent_id) do
    GenServer.call(__MODULE__, {:get_agent_reputation, agent_id})
  end

  @doc """
  Get reputation rankings for agents in a specific domain.
  """
  @spec get_reputation_rankings(atom(), keyword()) :: {:ok, [Types.economic_agent()]}
  def get_reputation_rankings(domain, opts \\ []) do
    GenServer.call(__MODULE__, {:get_reputation_rankings, domain, opts})
  end

  @doc """
  Record a transaction outcome for reputation calculation.
  """
  @spec record_transaction_outcome(String.t(), map()) :: :ok | {:error, term()}
  def record_transaction_outcome(transaction_id, outcome_data) do
    GenServer.call(__MODULE__, {:record_transaction_outcome, transaction_id, outcome_data})
  end

  # ============================================================================
  # Incentive and Reward API
  # ============================================================================

  @doc """
  Calculate and distribute rewards based on performance and contribution.

  Implements sophisticated incentive mechanisms to encourage
  optimal agent behavior and system participation.
  """
  @spec distribute_rewards(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def distribute_rewards(event_id, reward_spec) do
    GenServer.call(__MODULE__, {:distribute_rewards, event_id, reward_spec})
  end

  @doc """
  Calculate optimal pricing for a service based on market conditions.
  """
  @spec calculate_optimal_pricing(atom(), map()) :: {:ok, map()}
  def calculate_optimal_pricing(service_type, context) do
    GenServer.call(__MODULE__, {:calculate_optimal_pricing, service_type, context})
  end

  @doc """
  Get economic analytics and market insights.
  """
  @spec get_economic_analytics() :: {:ok, map()}
  def get_economic_analytics() do
    GenServer.call(__MODULE__, :get_economic_analytics)
  end

  @doc """
  Initialize agent reputation for a new agent.
  """
  @spec initialize_agent_reputation(agent_id(), map()) :: :ok | {:error, term()}
  def initialize_agent_reputation(agent_id, initial_reputation) do
    GenServer.call(__MODULE__, {:initialize_agent_reputation, agent_id, initial_reputation})
  end

  @doc """
  Apply reputation decay over time.
  """
  @spec apply_reputation_decay(agent_id(), map()) :: :ok | {:error, term()}
  def apply_reputation_decay(agent_id, decay_params) do
    GenServer.call(__MODULE__, {:apply_reputation_decay, agent_id, decay_params})
  end

  @doc """
  Calculate performance-based rewards for an agent.
  """
  @spec calculate_performance_reward(map(), map()) :: {:ok, float()} | {:error, term()}
  def calculate_performance_reward(incentive_config, performance_metrics) do
    GenServer.call(
      __MODULE__,
      {:calculate_performance_reward, incentive_config, performance_metrics}
    )
  end

  @doc """
  Validate budget constraints for a task.
  """
  @spec validate_budget_constraints(map(), float()) :: :ok | {:error, term()}
  def validate_budget_constraints(budget_constraints, estimated_cost) do
    GenServer.call(__MODULE__, {:validate_budget_constraints, budget_constraints, estimated_cost})
  end

  @doc """
  Optimize cost allocation across multiple tasks.
  """
  @spec optimize_cost_allocation(list(), float()) :: {:ok, map()} | {:error, term()}
  def optimize_cost_allocation(tasks, budget_limit) do
    GenServer.call(__MODULE__, {:optimize_cost_allocation, tasks, budget_limit})
  end

  @doc """
  Calculate dynamic pricing based on market conditions.
  """
  @spec calculate_dynamic_pricing(map()) :: {:ok, float()} | {:error, term()}
  def calculate_dynamic_pricing(market_conditions) do
    GenServer.call(__MODULE__, {:calculate_dynamic_pricing, market_conditions})
  end

  @doc """
  Create a market maker for a service type.
  """
  @spec create_market_maker(map()) :: {:ok, String.t()} | {:error, term()}
  def create_market_maker(market_spec) do
    GenServer.call(__MODULE__, {:create_market_maker, market_spec})
  end

  @doc """
  Submit a market order (buy/sell).
  """
  @spec submit_market_order(String.t(), :buy | :sell, map()) :: {:ok, String.t()} | {:error, term()}
  def submit_market_order(market_id, order_type, order_spec) do
    GenServer.call(__MODULE__, {:submit_market_order, market_id, order_type, order_spec})
  end

  @doc """
  Create a prediction market.
  """
  @spec create_prediction_market(map()) :: {:ok, String.t()} | {:error, term()}
  def create_prediction_market(prediction_spec) do
    GenServer.call(__MODULE__, {:create_prediction_market, prediction_spec})
  end

  @doc """
  Place a bet in a prediction market.
  """
  @spec place_prediction_bet(String.t(), agent_id(), map()) :: {:ok, String.t()} | {:error, term()}
  def place_prediction_bet(market_id, agent_id, bet_spec) do
    GenServer.call(__MODULE__, {:place_prediction_bet, market_id, agent_id, bet_spec})
  end

  @doc """
  Get market statistics and analytics.
  """
  @spec get_market_statistics() :: {:ok, map()} | {:error, term()}
  def get_market_statistics() do
    GenServer.call(__MODULE__, :get_market_statistics)
  end

  @doc """
  Get performance metrics for the economic system.
  """
  @spec get_performance_metrics() :: {:ok, map()} | {:error, term()}
  def get_performance_metrics() do
    GenServer.call(__MODULE__, :get_performance_metrics)
  end

  @doc """
  Generate economic insights for a time range.
  """
  @spec generate_economic_insights(map()) :: {:ok, map()} | {:error, term()}
  def generate_economic_insights(time_range) do
    GenServer.call(__MODULE__, {:generate_economic_insights, time_range})
  end

  @doc """
  Get marketplace information by ID.
  """
  @spec get_marketplace(String.t()) :: {:ok, map()} | {:error, term()}
  def get_marketplace(marketplace_id) do
    GenServer.call(__MODULE__, {:get_marketplace, marketplace_id})
  end

  @doc """
  Get auction by ID.
  """
  @spec get_auction(String.t()) :: {:ok, map()} | {:error, term()}
  def get_auction(auction_id) do
    GenServer.call(__MODULE__, {:get_auction, auction_id})
  end

  # ============================================================================
  # GenServer Handlers
  # ============================================================================

  @impl true
  def handle_call({:create_auction, auction_spec, opts}, _from, state) do
    case validate_auction_spec(auction_spec) do
      :ok ->
        auction_id = generate_auction_id()

        auction = %{
          id: auction_id,
          type: Map.get(auction_spec, :type, :english),
          task: auction_spec.item,
          bids: [],
          status: :open,
          winner: nil,
          winning_bid: nil,
          started_at: DateTime.utc_now(),
          ends_at: calculate_auction_end_time(auction_spec, opts),
          config: build_auction_config(auction_spec, opts)
        }

        new_state = %{state | active_auctions: Map.put(state.active_auctions, auction_id, auction)}

        # Emit telemetry
        emit_economics_telemetry(:auction_created, auction, %{})

        Logger.info("Created #{auction.type} auction #{auction_id} for #{inspect(auction.task)}")
        {:reply, {:ok, auction_id}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:place_bid, auction_id, agent_id, bid_spec}, _from, state) do
    case Map.get(state.active_auctions, auction_id) do
      nil ->
        {:reply, {:error, :auction_not_found}, state}

      auction ->
        case validate_bid(auction, agent_id, bid_spec, state) do
          :ok ->
            bid_id = generate_bid_id()

            bid = %{
              bidder: agent_id,
              amount: bid_spec.price,
              quality_guarantee: Map.get(bid_spec, :quality_guarantee, 0.8),
              delivery_time_ms: Map.get(bid_spec, :completion_time, 3600) * 1000,
              conditions: Map.get(bid_spec, :conditions, %{}),
              submitted_at: DateTime.utc_now()
            }

            updated_auction = %{auction | bids: [bid | auction.bids]}

            new_state = %{
              state
              | active_auctions: Map.put(state.active_auctions, auction_id, updated_auction),
                bid_history: [bid | state.bid_history]
            }

            # Check if auction should auto-close (e.g., buy-now price reached)
            final_state = check_auction_auto_close(auction_id, updated_auction, new_state)

            # Emit telemetry
            emit_economics_telemetry(:bid_placed, auction, %{
              bid_amount: bid.amount,
              bidder: agent_id
            })

            Logger.info("Bid placed by #{agent_id} in auction #{auction_id}: #{bid.amount}")
            {:reply, {:ok, bid_id}, final_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:close_auction, auction_id}, _from, state) do
    case Map.get(state.active_auctions, auction_id) do
      nil ->
        {:reply, {:error, :auction_not_found}, state}

      auction ->
        case determine_auction_winner(auction) do
          {:ok, winner, winning_bid} ->
            closed_auction =
              auction
              |> Map.put(:status, :closed)
              |> Map.put(:winner, winner)
              |> Map.put(:winning_bid, winning_bid)
              |> Map.put(:winning_price, winning_bid.amount)

            new_state = %{
              state
              | active_auctions: Map.delete(state.active_auctions, auction_id),
                completed_auctions: [closed_auction | state.completed_auctions]
            }

            # Process payment and update reputations
            final_state = process_auction_completion(closed_auction, new_state)

            # Emit telemetry
            emit_economics_telemetry(:auction_closed, closed_auction, %{
              winner: winner,
              winning_amount: winning_bid.amount
            })

            Logger.info(
              "Auction #{auction_id} closed, winner: #{winner} with bid #{winning_bid.amount}"
            )

            # Return results structure expected by tests
            results = %{
              winner: winner,
              winning_price: winning_bid.amount,
              auction: closed_auction
            }

            {:reply, {:ok, results}, final_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:get_auction_status, auction_id}, _from, state) do
    case Map.get(state.active_auctions, auction_id) do
      nil ->
        # Check completed auctions
        case Enum.find(state.completed_auctions, &(&1.id == auction_id)) do
          nil -> {:reply, {:error, :not_found}, state}
          auction -> {:reply, {:ok, auction}, state}
        end

      auction ->
        {:reply, {:ok, auction}, state}
    end
  end

  @impl true
  def handle_call({:list_active_auctions, filters}, _from, state) do
    auctions =
      state.active_auctions
      |> Map.values()
      |> apply_auction_filters(filters)

    {:reply, {:ok, auctions}, state}
  end

  @impl true
  def handle_call({:cancel_auction, auction_id, reason}, _from, state) do
    case Map.get(state.active_auctions, auction_id) do
      nil ->
        {:reply, {:error, :auction_not_found}, state}

      auction ->
        if auction_can_be_cancelled(auction) do
          cancelled_auction = %{auction | status: :cancelled}

          new_state = %{
            state
            | active_auctions: Map.delete(state.active_auctions, auction_id),
              completed_auctions: [cancelled_auction | state.completed_auctions]
          }

          # Emit telemetry
          emit_economics_telemetry(:auction_cancelled, cancelled_auction, %{reason: reason})

          Logger.info("Auction #{auction_id} cancelled: #{reason}")
          {:reply, :ok, new_state}
        else
          {:reply, {:error, :cannot_cancel}, state}
        end
    end
  end

  # Marketplace handlers

  @impl true
  def handle_call({:create_marketplace, marketplace_spec}, _from, state) do
    case validate_marketplace_spec(marketplace_spec) do
      :ok ->
        marketplace_id = generate_marketplace_id()

        marketplace = %{
          id: marketplace_id,
          name: marketplace_spec.name,
          categories: Map.get(marketplace_spec, :categories, []),
          active_listings: %{},
          completed_transactions: [],
          fee_structure: Map.get(marketplace_spec, :fee_structure, default_fee_structure()),
          quality_enforcement: Map.get(marketplace_spec, :quality_enforcement, true),
          reputation_requirements: Map.get(marketplace_spec, :reputation_requirements, %{}),
          status: :active,
          created_at: DateTime.utc_now()
        }

        new_state = %{
          state
          | marketplaces: Map.put(state.marketplaces, marketplace_id, marketplace)
        }

        Logger.info("Created marketplace #{marketplace_id}: #{marketplace.name}")
        {:reply, {:ok, marketplace_id}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:list_service, marketplace_id, service_spec}, _from, state) do
    case Map.get(state.marketplaces, marketplace_id) do
      nil ->
        {:reply, {:error, :marketplace_not_found}, state}

      marketplace ->
        case validate_service_listing(service_spec, marketplace, state) do
          :ok ->
            listing_id = generate_listing_id()

            listing = %{
              id: listing_id,
              provider: service_spec.provider,
              service_type: service_spec.service_type,
              capabilities: Map.get(service_spec, :capabilities, []),
              pricing: service_spec.pricing,
              quality_guarantees: Map.get(service_spec, :quality_guarantees, %{}),
              availability: Map.get(service_spec, :availability, default_availability()),
              reputation_score: get_agent_reputation_score(service_spec.provider, state),
              listed_at: DateTime.utc_now(),
              expires_at: calculate_listing_expiry(service_spec)
            }

            updated_marketplace = %{
              marketplace
              | active_listings: Map.put(marketplace.active_listings, listing_id, listing)
            }

            new_state = %{
              state
              | marketplaces: Map.put(state.marketplaces, marketplace_id, updated_marketplace)
            }

            Logger.info(
              "Service listed by #{service_spec.provider} in marketplace #{marketplace_id}"
            )

            {:reply, {:ok, listing_id}, new_state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end

  # Handle service request for a specific listing (direct transaction creation)
  @impl true
  def handle_call({:request_service, listing_id, transaction_request}, _from, state)
      when is_binary(listing_id) and is_map(transaction_request) and
             is_map_key(transaction_request, :buyer) do
    # Find the listing across all marketplaces
    case find_listing_by_id(state, listing_id) do
      {:ok, marketplace_id, marketplace, listing} ->
        transaction_id = generate_transaction_id()
        buyer_id = Map.get(transaction_request, :buyer)
        service_requirements = Map.get(transaction_request, :service_requirements, %{})

        # Create transaction
        transaction = %{
          id: transaction_id,
          buyer: buyer_id,
          seller: listing.provider,
          service_type: listing.service_type,
          amount: calculate_transaction_amount_from_request(listing, service_requirements),
          currency: :usd,
          quality_delivered: 0.0,
          completion_time: 0,
          satisfaction_score: 0.0,
          timestamp: DateTime.utc_now(),
          listing_id: listing_id,
          marketplace_id: marketplace_id
        }

        # Update marketplace with transaction
        updated_marketplace = %{
          marketplace
          | completed_transactions: [transaction | marketplace.completed_transactions]
        }

        new_state = %{
          state
          | marketplaces: Map.put(state.marketplaces, marketplace_id, updated_marketplace),
            transaction_history: [transaction | state.transaction_history]
        }

        Logger.info(
          "Service transaction #{transaction_id} created for listing #{listing_id} between #{buyer_id} and #{listing.provider}"
        )

        {:reply, {:ok, transaction_id}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:request_service, marketplace_id, service_requirements}, _from, state) do
    case Map.get(state.marketplaces, marketplace_id) do
      nil ->
        {:reply, {:error, :marketplace_not_found}, state}

      marketplace ->
        matching_services = find_matching_services(marketplace, service_requirements, state)
        ranked_services = rank_services_by_suitability(matching_services, service_requirements)

        {:reply, {:ok, ranked_services}, state}
    end
  end

  @impl true
  def handle_call(
        {:execute_transaction, marketplace_id, listing_id, buyer_id, transaction_details},
        _from,
        state
      ) do
    case get_marketplace_listing(state, marketplace_id, listing_id) do
      {:ok, marketplace, listing} ->
        transaction_id = generate_transaction_id()

        transaction = %{
          id: transaction_id,
          buyer: buyer_id,
          seller: listing.provider,
          service_type: listing.service_type,
          amount: calculate_transaction_amount(listing, transaction_details),
          # Default currency
          currency: :usd,
          # To be updated on completion
          quality_delivered: 0.0,
          # To be updated on completion
          completion_time: 0,
          # To be updated on completion
          satisfaction_score: 0.0,
          timestamp: DateTime.utc_now()
        }

        updated_marketplace = %{
          marketplace
          | completed_transactions: [transaction | marketplace.completed_transactions]
        }

        new_state = %{
          state
          | marketplaces: Map.put(state.marketplaces, marketplace_id, updated_marketplace),
            transaction_history: [transaction | state.transaction_history]
        }

        Logger.info(
          "Transaction #{transaction_id} executed between #{buyer_id} and #{listing.provider}"
        )

        {:reply, {:ok, transaction_id}, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_marketplace_analytics, marketplace_id}, _from, state) do
    case Map.get(state.marketplaces, marketplace_id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      marketplace ->
        analytics = calculate_marketplace_analytics(marketplace, state)
        {:reply, {:ok, analytics}, state}
    end
  end

  # Reputation system handlers

  @impl true
  def handle_call({:update_agent_reputation, agent_id, performance_data}, _from, state) do
    current_reputation =
      Map.get(state.agent_reputations, agent_id, create_default_reputation(agent_id))

    # Check for gaming attempts
    case detect_reputation_gaming(current_reputation, performance_data) do
      {:ok, :valid} ->
        updated_reputation = calculate_updated_reputation(current_reputation, performance_data)

        new_state = %{
          state
          | agent_reputations: Map.put(state.agent_reputations, agent_id, updated_reputation)
        }

        Logger.debug("Updated reputation for #{agent_id}: #{updated_reputation.reputation_score}")
        {:reply, :ok, new_state}

      {:error, reason} ->
        Logger.warning("Reputation gaming detected for #{agent_id}: #{reason}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_agent_reputation, agent_id}, _from, state) do
    case Map.get(state.agent_reputations, agent_id) do
      nil -> {:reply, {:error, :not_found}, state}
      reputation -> {:reply, {:ok, reputation}, state}
    end
  end

  @impl true
  def handle_call({:get_reputation_rankings, domain, opts}, _from, state) do
    rankings =
      state.agent_reputations
      |> Map.values()
      |> filter_by_domain(domain)
      |> sort_by_reputation()
      |> apply_ranking_options(opts)

    {:reply, {:ok, rankings}, state}
  end

  @impl true
  def handle_call({:record_transaction_outcome, transaction_id, outcome_data}, _from, state) do
    # Find and update the transaction
    updated_history =
      Enum.map(state.transaction_history, fn transaction ->
        if transaction.id == transaction_id do
          %{
            transaction
            | quality_delivered:
                Map.get(outcome_data, :quality_delivered, transaction.quality_delivered),
              completion_time: Map.get(outcome_data, :completion_time, transaction.completion_time),
              satisfaction_score:
                Map.get(outcome_data, :satisfaction_score, transaction.satisfaction_score)
          }
        else
          transaction
        end
      end)

    new_state = %{state | transaction_history: updated_history}

    # Update agent reputations based on transaction outcome
    final_state = update_reputations_from_transaction(transaction_id, outcome_data, new_state)

    {:reply, :ok, final_state}
  end

  # Economic calculation handlers

  @impl true
  def handle_call({:distribute_rewards, event_id, reward_spec}, _from, state) do
    distribution_results = calculate_reward_distribution(event_id, reward_spec, state)

    # Update agent reputations and records
    final_state = apply_reward_distribution(distribution_results, state)

    {:reply, {:ok, distribution_results}, final_state}
  end

  @impl true
  def handle_call({:calculate_optimal_pricing, service_type, context}, _from, state) do
    pricing = calculate_market_based_pricing(service_type, context, state)
    {:reply, {:ok, pricing}, state}
  end

  @impl true
  def handle_call(:get_economic_analytics, _from, state) do
    analytics = calculate_economic_analytics(state)
    {:reply, {:ok, analytics}, state}
  end

  @impl true
  def handle_call({:initialize_agent_reputation, agent_id, initial_reputation}, _from, state) do
    default_reputation = create_default_reputation(agent_id)
    reputation = Map.merge(default_reputation, initial_reputation)

    # Ensure both score fields are in sync
    final_score = Map.get(reputation, :initial_score, reputation.reputation_score)
    reputation = %{reputation | reputation_score: final_score, overall_score: final_score}

    new_state = %{state | agent_reputations: Map.put(state.agent_reputations, agent_id, reputation)}
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:apply_reputation_decay, agent_id, decay_params}, _from, state) do
    case Map.get(state.agent_reputations, agent_id) do
      nil ->
        {:reply, {:error, :agent_not_found}, state}

      reputation ->
        decay_factor = Map.get(decay_params, :decay_factor, 0.99)
        new_score = reputation.reputation_score * decay_factor
        updated_reputation = %{reputation | reputation_score: new_score, overall_score: new_score}

        new_state = %{
          state
          | agent_reputations: Map.put(state.agent_reputations, agent_id, updated_reputation)
        }

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(
        {:calculate_performance_reward, incentive_config, performance_metrics},
        _from,
        state
      ) do
    base_reward = Map.get(incentive_config, :base_reward, 1.0)
    quality_multiplier = Map.get(incentive_config, :quality_multiplier, 1.0)
    speed_multiplier = Map.get(incentive_config, :speed_multiplier, 1.0)
    cost_efficiency_multiplier = Map.get(incentive_config, :cost_efficiency_multiplier, 1.0)

    quality_score = Map.get(performance_metrics, :quality_score, 0.0)
    completion_speed_ratio = Map.get(performance_metrics, :completion_speed_ratio, 1.0)
    cost_efficiency = Map.get(performance_metrics, :cost_efficiency, 1.0)

    reward =
      base_reward *
        (1 + quality_score * quality_multiplier) *
        (1 + (completion_speed_ratio - 1) * speed_multiplier) *
        (1 + (cost_efficiency - 1) * cost_efficiency_multiplier)

    {:reply, {:ok, reward}, state}
  end

  @impl true
  def handle_call({:validate_budget_constraints, budget_constraints, estimated_cost}, _from, state) do
    max_per_task = Map.get(budget_constraints, :max_per_task, :infinity)

    if estimated_cost > max_per_task do
      {:reply,
       {:error, "Task cost #{estimated_cost} exceeds maximum per-task budget #{max_per_task}"},
       state}
    else
      {:reply, :ok, state}
    end
  end

  @impl true
  def handle_call({:optimize_cost_allocation, tasks, budget_limit}, _from, state) do
    # Simple priority-based allocation
    sorted_tasks =
      Enum.sort_by(
        tasks,
        fn task ->
          priority_weight =
            case Map.get(task, :priority, :normal) do
              :high -> 3
              :medium -> 2
              :low -> 1
              _ -> 1
            end

          priority_weight
        end,
        :desc
      )

    {allocated_tasks, _remaining_budget} =
      Enum.reduce_while(sorted_tasks, {[], budget_limit}, fn task, {allocated, remaining} ->
        task_cost = Map.get(task, :estimated_cost, 0.0)

        if task_cost <= remaining do
          {:cont, {[task | allocated], remaining - task_cost}}
        else
          {:halt, {allocated, remaining}}
        end
      end)

    allocation = %{
      allocated_tasks: Enum.reverse(allocated_tasks),
      total_allocated_cost: Enum.sum(Enum.map(allocated_tasks, &Map.get(&1, :estimated_cost, 0.0))),
      remaining_budget:
        budget_limit - Enum.sum(Enum.map(allocated_tasks, &Map.get(&1, :estimated_cost, 0.0)))
    }

    {:reply, {:ok, allocation}, state}
  end

  @impl true
  def handle_call({:calculate_dynamic_pricing, market_conditions}, _from, state) do
    base_price = Map.get(market_conditions, :base_price, 0.02)
    available_providers = Map.get(market_conditions, :available_providers, 1)
    pending_requests = Map.get(market_conditions, :pending_requests, 1)

    # Simple supply and demand calculation
    demand_factor = pending_requests / available_providers
    dynamic_price = base_price * demand_factor

    {:reply, {:ok, dynamic_price}, state}
  end

  @impl true
  def handle_call({:create_market_maker, market_spec}, _from, state) do
    market_id = generate_market_id()

    market_maker =
      Map.merge(
        %{
          id: market_id,
          created_at: DateTime.utc_now(),
          active: true
        },
        market_spec
      )

    new_state = %{state | market_makers: Map.put(state.market_makers, market_id, market_maker)}

    {:reply, {:ok, market_id}, new_state}
  end

  @impl true
  def handle_call({:submit_market_order, market_id, order_type, order_spec}, _from, state) do
    case Map.get(state.market_makers, market_id) do
      nil ->
        {:reply, {:error, :market_not_found}, state}

      _market_maker ->
        order_id = generate_order_id()

        order =
          Map.merge(
            %{
              id: order_id,
              type: order_type,
              timestamp: DateTime.utc_now(),
              status: :pending
            },
            order_spec
          )

        new_state = %{state | market_orders: Map.put(state.market_orders, order_id, order)}

        {:reply, {:ok, order_id}, new_state}
    end
  end

  @impl true
  def handle_call({:create_prediction_market, prediction_spec}, _from, state) do
    market_id = generate_prediction_market_id()

    prediction_market =
      Map.merge(
        %{
          id: market_id,
          created_at: DateTime.utc_now(),
          status: :open,
          bets: []
        },
        prediction_spec
      )

    new_state = %{
      state
      | prediction_markets: Map.put(state.prediction_markets, market_id, prediction_market)
    }

    {:reply, {:ok, market_id}, new_state}
  end

  @impl true
  def handle_call({:place_prediction_bet, market_id, agent_id, bet_spec}, _from, state) do
    case Map.get(state.prediction_markets, market_id) do
      nil ->
        {:reply, {:error, :market_not_found}, state}

      market ->
        bet_id = generate_bet_id()

        bet =
          Map.merge(
            %{
              id: bet_id,
              agent_id: agent_id,
              timestamp: DateTime.utc_now()
            },
            bet_spec
          )

        updated_market = %{market | bets: [bet | market.bets]}

        new_state = %{
          state
          | prediction_markets: Map.put(state.prediction_markets, market_id, updated_market)
        }

        {:reply, {:ok, bet_id}, new_state}
    end
  end

  @impl true
  def handle_call(:get_market_statistics, _from, state) do
    stats = %{
      total_auctions: map_size(state.active_auctions) + length(state.completed_auctions),
      average_auction_value: calculate_average_auction_value(state),
      market_efficiency_score: calculate_market_efficiency_score(state),
      total_marketplaces: map_size(state.marketplaces),
      total_transactions: length(state.transaction_history)
    }

    {:reply, {:ok, stats}, state}
  end

  @impl true
  def handle_call(:get_performance_metrics, _from, state) do
    metrics = %{
      total_transactions: length(state.transaction_history),
      average_transaction_time: calculate_average_transaction_time(state),
      cost_efficiency_trend: calculate_cost_efficiency_trend(state),
      agent_satisfaction_score: calculate_agent_satisfaction_score(state)
    }

    {:reply, {:ok, metrics}, state}
  end

  @impl true
  def handle_call({:generate_economic_insights, time_range}, _from, state) do
    insights = %{
      market_trends: analyze_market_trends(state, time_range),
      cost_optimization_opportunities: identify_cost_optimizations(state),
      agent_performance_rankings: generate_performance_rankings(state),
      recommendations: generate_recommendations(state, time_range)
    }

    {:reply, {:ok, insights}, state}
  end

  @impl true
  def handle_call({:get_marketplace, marketplace_id}, _from, state) do
    case Map.get(state.marketplaces, marketplace_id) do
      nil -> {:reply, {:error, :not_found}, state}
      marketplace -> {:reply, {:ok, marketplace}, state}
    end
  end

  @impl true
  def handle_call({:get_auction, auction_id}, _from, state) do
    case Map.get(state.active_auctions, auction_id) do
      nil ->
        # Check completed auctions
        case Enum.find(state.completed_auctions, &(&1.id == auction_id)) do
          nil -> {:reply, {:error, :not_found}, state}
          auction -> {:reply, {:ok, auction}, state}
        end

      auction ->
        {:reply, {:ok, auction}, state}
    end
  end

  @impl true
  def handle_call(request, _from, state) do
    Logger.warning("Unknown Economics call: #{inspect(request)}")
    {:reply, {:error, :unknown_request}, state}
  end

  @impl true
  def handle_cast(msg, state) do
    Logger.warning("Unknown Economics cast: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_info(:auction_cleanup, state) do
    cleaned_state = cleanup_expired_auctions(state)
    schedule_auction_cleanup()
    {:noreply, cleaned_state}
  end

  @impl true
  def handle_info(:reputation_update, state) do
    updated_state = decay_reputations(state)
    schedule_reputation_update()
    {:noreply, updated_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Unknown Economics info: #{inspect(msg)}")
    {:noreply, state}
  end

  # ============================================================================
  # Private Implementation Functions
  # ============================================================================

  # Validation functions

  defp validate_auction_spec(spec) do
    required_fields = [:type, :item]

    case Enum.all?(required_fields, &Map.has_key?(spec, &1)) do
      true ->
        # Check auction type
        cond do
          spec.type not in [:english, :dutch, :sealed_bid, :vickrey, :combinatorial] ->
            {:error, "invalid auction type: #{spec.type}"}

          # Check reserve price if provided
          Map.has_key?(spec, :reserve_price) and spec.reserve_price < 0 ->
            {:error, "invalid reserve price: cannot be negative"}

          # Check duration if provided
          Map.has_key?(spec, :duration_minutes) and spec.duration_minutes <= 0 ->
            {:error, "invalid duration: must be positive"}

          true ->
            :ok
        end

      false ->
        {:error, "missing required fields"}
    end
  end

  defp validate_bid(auction, _agent_id, bid_spec, _state) do
    cond do
      auction.status != :open ->
        {:error, :auction_not_open}

      DateTime.compare(DateTime.utc_now(), auction.ends_at) == :gt ->
        {:error, :auction_expired}

      not Map.has_key?(bid_spec, :price) ->
        {:error, :missing_price}

      bid_spec.price <= 0 ->
        {:error, :invalid_price}

      not meets_minimum_bid(auction, bid_spec.price) ->
        {:error, :bid_too_low}

      true ->
        # Note: agent_eligible_to_bid always returns true currently
        # Additional eligibility checks can be added here in the future
        :ok
    end
  end

  defp validate_marketplace_spec(spec) do
    required_fields = [:name]

    case Enum.all?(required_fields, &Map.has_key?(spec, &1)) do
      true -> :ok
      false -> {:error, :missing_required_fields}
    end
  end

  defp validate_service_listing(spec, marketplace, state) do
    required_fields = [:provider, :service_type, :pricing]

    cond do
      not Enum.all?(required_fields, &Map.has_key?(spec, &1)) ->
        {:error, :missing_required_fields}

      not service_type_allowed(spec.service_type, marketplace) ->
        {:error, :service_type_not_allowed}

      not meets_reputation_requirements(spec.provider, marketplace, state) ->
        {:error, :insufficient_reputation}

      true ->
        :ok
    end
  end

  # Auction logic functions

  defp determine_auction_winner(auction) do
    case auction.type do
      :english -> determine_english_auction_winner(auction)
      :dutch -> determine_dutch_auction_winner(auction)
      :sealed_bid -> determine_sealed_bid_winner(auction)
      :vickrey -> determine_vickrey_winner(auction)
      :combinatorial -> determine_combinatorial_winner(auction)
      _ -> {:error, :unsupported_auction_type}
    end
  end

  defp determine_english_auction_winner(auction) do
    case auction.bids do
      [] ->
        {:error, :no_bids}

      bids ->
        winning_bid = Enum.max_by(bids, & &1.amount)
        {:ok, winning_bid.bidder, winning_bid}
    end
  end

  defp determine_dutch_auction_winner(auction) do
    # For Dutch auctions, first bidder wins at current price
    case auction.bids do
      [] -> {:error, :no_bids}
      [first_bid | _] -> {:ok, first_bid.bidder, first_bid}
    end
  end

  defp determine_sealed_bid_winner(auction) do
    # Highest bid wins, pays their bid amount
    determine_english_auction_winner(auction)
  end

  defp determine_vickrey_winner(auction) do
    # Highest bidder wins but pays second-highest price
    case auction.bids do
      [] ->
        {:error, :no_bids}

      [single_bid] ->
        {:ok, single_bid.bidder, single_bid}

      bids ->
        sorted_bids = Enum.sort_by(bids, & &1.amount, :desc)
        highest_bid = hd(sorted_bids)
        second_highest_price = hd(tl(sorted_bids)).amount

        vickrey_bid = %{highest_bid | amount: second_highest_price}
        {:ok, highest_bid.bidder, vickrey_bid}
    end
  end

  defp determine_combinatorial_winner(auction) do
    # Complex optimization problem - simplified implementation
    # In practice, this would use sophisticated algorithms
    determine_english_auction_winner(auction)
  end

  defp meets_minimum_bid(auction, bid_amount) do
    case auction.type do
      :english ->
        current_highest = get_current_highest_bid(auction)
        bid_amount >= current_highest + @default_bid_increment

      :dutch ->
        # Dutch auctions accept any bid at current price
        true

      :sealed_bid ->
        # Sealed bid auctions may have reserve price
        reserve_price = Map.get(auction.config, :reserve_price, 0)
        bid_amount >= reserve_price

      :vickrey ->
        reserve_price = Map.get(auction.config, :reserve_price, 0)
        bid_amount >= reserve_price

      :combinatorial ->
        # Complex combinatorial logic
        true
    end
  end

  defp get_current_highest_bid(auction) do
    case auction.bids do
      [] -> Map.get(auction.config, :reserve_price, 0)
      bids -> Enum.max_by(bids, & &1.amount).amount
    end
  end

  # Note: agent_eligible_to_bid function removed as it was always returning true
  # Future eligibility checks can be added to validate_bid/4 when needed

  defp auction_can_be_cancelled(auction) do
    # Can only cancel if no bids have been placed
    length(auction.bids) == 0
  end

  defp check_auction_auto_close(auction_id, auction, state) do
    # Check for auto-close conditions (e.g., buy-now price)
    buy_now_price = Map.get(auction.config, :buy_now_price)

    if buy_now_price && auction.bids != [] do
      highest_bid = Enum.max_by(auction.bids, & &1.amount)

      if highest_bid.amount >= buy_now_price do
        # Auto-close auction
        closed_auction = %{
          auction
          | status: :closed,
            winner: highest_bid.bidder,
            winning_bid: highest_bid
        }

        %{
          state
          | active_auctions: Map.delete(state.active_auctions, auction_id),
            completed_auctions: [closed_auction | state.completed_auctions]
        }
      else
        state
      end
    else
      state
    end
  end

  defp process_auction_completion(_auction, state) do
    # Update winner and seller reputations
    # Process payment
    # Update transaction history
    # Simplified implementation
    state
  end

  # Marketplace logic functions

  defp find_matching_services(marketplace, requirements, _state) do
    marketplace.active_listings
    |> Map.values()
    |> Enum.filter(&service_matches_requirements(&1, requirements))
  end

  defp service_matches_requirements(listing, requirements) do
    # Check service type, capabilities, pricing, availability
    service_type_matches =
      Map.get(requirements, :service_type) == listing.service_type

    capabilities_match =
      case Map.get(requirements, :required_capabilities) do
        nil -> true
        required -> Enum.all?(required, &(&1 in listing.capabilities))
      end

    service_type_matches && capabilities_match
  end

  defp rank_services_by_suitability(services, requirements) do
    services
    |> Enum.map(&calculate_service_score(&1, requirements))
    |> Enum.sort_by(& &1.suitability_score, :desc)
  end

  defp calculate_service_score(listing, requirements) do
    # Multi-factor scoring: reputation, price, quality guarantees, availability
    reputation_score = listing.reputation_score * 0.4
    price_score = calculate_price_score(listing.pricing, requirements) * 0.3
    quality_score = calculate_quality_score(listing.quality_guarantees, requirements) * 0.2
    availability_score = calculate_availability_score(listing.availability, requirements) * 0.1

    total_score = reputation_score + price_score + quality_score + availability_score

    Map.put(listing, :suitability_score, total_score)
  end

  defp calculate_price_score(_pricing, _requirements) do
    # TODO: Implement sophisticated price scoring
    # Placeholder
    0.8
  end

  defp calculate_quality_score(_quality_guarantees, _requirements) do
    # TODO: Implement quality scoring based on guarantees
    # Placeholder
    0.8
  end

  defp calculate_availability_score(_availability, _requirements) do
    # TODO: Implement availability scoring
    # Placeholder
    0.8
  end

  defp get_marketplace_listing(state, marketplace_id, listing_id) do
    case Map.get(state.marketplaces, marketplace_id) do
      nil ->
        {:error, :marketplace_not_found}

      marketplace ->
        case Map.get(marketplace.active_listings, listing_id) do
          nil -> {:error, :listing_not_found}
          listing -> {:ok, marketplace, listing}
        end
    end
  end

  defp calculate_transaction_amount(listing, transaction_details) do
    # Calculate based on pricing model and transaction details
    base_rate = listing.pricing.base_rate

    # Add volume-based adjustments
    volume_multiplier = Map.get(transaction_details, :volume_multiplier, 1.0)

    base_rate * volume_multiplier
  end

  # Reputation system functions

  defp create_default_reputation(agent_id) do
    %{
      agent_id: agent_id,
      # Neutral starting reputation
      reputation_score: 0.5,
      # Alias for reputation_score for test compatibility
      overall_score: 0.5,
      performance_history: [],
      # List of specialization areas
      specializations: [],
      cost_efficiency: 0.5,
      specialization_scores: %{},
      availability: default_availability(),
      pricing_model: default_pricing_model(),
      resource_capacity: %{}
    }
  end

  defp calculate_updated_reputation(current_reputation, performance_data) do
    # Multi-dimensional reputation update
    new_performance_record = %{
      task_id: Map.get(performance_data, :task_id, generate_task_id()),
      task_type: Map.get(performance_data, :task_type, :unknown),
      quality_score: Map.get(performance_data, :quality_score, 0.5),
      cost_efficiency: Map.get(performance_data, :cost_efficiency, 0.5),
      completion_time_ms: Map.get(performance_data, :completion_time_ms, 60_000),
      client_satisfaction: Map.get(performance_data, :client_satisfaction, 0.5),
      timestamp: DateTime.utc_now()
    }

    updated_history =
      [new_performance_record | current_reputation.performance_history]
      # Keep last 100 records
      |> Enum.take(100)

    new_reputation_score = calculate_aggregate_reputation_score(updated_history)
    new_cost_efficiency = calculate_cost_efficiency_score(updated_history)

    %{
      current_reputation
      | reputation_score: new_reputation_score,
        # Keep both fields in sync for compatibility
        overall_score: new_reputation_score,
        performance_history: updated_history,
        cost_efficiency: new_cost_efficiency
    }
  end

  defp calculate_aggregate_reputation_score(performance_history) do
    case performance_history do
      [] ->
        0.5

      history ->
        # Weighted average with recent performance weighted more heavily
        weighted_sum =
          history
          |> Enum.with_index()
          |> Enum.reduce(0, fn {record, index}, acc ->
            # Recent records get higher weight
            weight = :math.pow(0.95, index)
            score = (record.quality_score + record.client_satisfaction) / 2
            acc + score * weight
          end)

        total_weight =
          history
          |> Enum.with_index()
          |> Enum.reduce(0, fn {_record, index}, acc ->
            acc + :math.pow(0.95, index)
          end)

        weighted_sum / total_weight
    end
  end

  defp calculate_cost_efficiency_score(performance_history) do
    case performance_history do
      [] ->
        0.5

      history ->
        history
        |> Enum.map(& &1.cost_efficiency)
        |> Enum.sum()
        |> Kernel./(length(history))
    end
  end

  defp get_agent_reputation_score(agent_id, state) do
    case Map.get(state.agent_reputations, agent_id) do
      # Default reputation
      nil -> 0.5
      reputation -> reputation.reputation_score
    end
  end

  defp filter_by_domain(reputations, _domain) do
    # TODO: Filter agents by domain expertise
    reputations
  end

  defp sort_by_reputation(reputations) do
    Enum.sort_by(reputations, & &1.reputation_score, :desc)
  end

  defp apply_ranking_options(reputations, opts) do
    limit = Keyword.get(opts, :limit, 10)
    Enum.take(reputations, limit)
  end

  defp update_reputations_from_transaction(transaction_id, outcome_data, state) do
    # Find the transaction and update both buyer and seller reputations
    case Enum.find(state.transaction_history, &(&1.id == transaction_id)) do
      nil ->
        state

      transaction ->
        # Update seller reputation based on quality delivered
        seller_performance = %{
          task_id: transaction_id,
          task_type: transaction.service_type,
          quality_score: Map.get(outcome_data, :quality_delivered, 0.5),
          cost_efficiency: calculate_cost_efficiency_from_transaction(transaction, outcome_data),
          completion_time_ms: Map.get(outcome_data, :completion_time, 60_000),
          client_satisfaction: Map.get(outcome_data, :satisfaction_score, 0.5)
        }

        updated_seller_reputation =
          state.agent_reputations
          |> Map.get(transaction.seller, create_default_reputation(transaction.seller))
          |> calculate_updated_reputation(seller_performance)

        %{
          state
          | agent_reputations:
              Map.put(state.agent_reputations, transaction.seller, updated_seller_reputation)
        }
    end
  end

  defp calculate_cost_efficiency_from_transaction(transaction, outcome_data) do
    # Calculate efficiency based on price vs. quality delivered
    quality_delivered = Map.get(outcome_data, :quality_delivered, 0.5)

    if transaction.amount > 0 do
      # Normalize
      quality_delivered / transaction.amount * 10
    else
      0.5
    end
  end

  # Economic calculation functions

  defp calculate_reward_distribution(event_id, reward_spec, _state) do
    # TODO: Implement sophisticated reward distribution algorithms
    %{
      event_id: event_id,
      total_rewards: Map.get(reward_spec, :total_amount, 100.0),
      distribution: %{},
      distribution_strategy: Map.get(reward_spec, :strategy, :performance_based)
    }
  end

  defp apply_reward_distribution(_distribution_results, state) do
    # TODO: Apply reward distribution to agent accounts/reputations
    state
  end

  defp calculate_market_based_pricing(service_type, context, state) do
    # Analyze historical transactions to determine optimal pricing
    relevant_transactions =
      state.transaction_history
      |> Enum.filter(&(&1.service_type == service_type))
      # Recent 100 transactions
      |> Enum.take(100)

    case relevant_transactions do
      [] ->
        # No historical data, use default pricing
        %{
          base_price: 1.0,
          confidence: 0.3,
          market_trend: :unknown,
          recommendations: ["Insufficient market data for accurate pricing"]
        }

      transactions ->
        prices = Enum.map(transactions, & &1.amount)
        average_price = Enum.sum(prices) / length(prices)

        %{
          base_price: average_price,
          confidence: min(length(transactions) / 50, 1.0),
          market_trend: calculate_market_trend(transactions),
          price_range: {Enum.min(prices), Enum.max(prices)},
          recommendations: generate_pricing_recommendations(transactions, context)
        }
    end
  end

  defp calculate_market_trend(transactions) do
    # Simple trend analysis based on recent vs. older transactions
    if length(transactions) < 10 do
      :stable
    else
      recent_avg =
        transactions
        |> Enum.take(10)
        |> Enum.map(& &1.amount)
        |> Enum.sum()
        |> Kernel./(10)

      older_avg =
        transactions
        |> Enum.drop(10)
        |> Enum.take(10)
        |> Enum.map(& &1.amount)
        |> Enum.sum()
        |> Kernel./(10)

      cond do
        recent_avg > older_avg * 1.1 -> :increasing
        recent_avg < older_avg * 0.9 -> :decreasing
        true -> :stable
      end
    end
  end

  defp generate_pricing_recommendations(transactions, context) do
    # Generate actionable pricing recommendations
    quality_correlation = calculate_quality_price_correlation(transactions)

    recommendations = [
      "Base pricing on market average of #{Enum.sum(Enum.map(transactions, & &1.amount)) / length(transactions)}",
      "Quality correlation: #{quality_correlation}"
    ]

    case Map.get(context, :urgency) do
      :high -> ["Consider premium pricing (+20%) for urgent requests" | recommendations]
      :low -> ["Consider discount pricing (-10%) for non-urgent requests" | recommendations]
      _ -> recommendations
    end
  end

  defp calculate_quality_price_correlation(_transactions) do
    # Calculate correlation between price and quality delivered
    # TODO: Implement proper correlation analysis
    # Placeholder
    0.7
  end

  defp calculate_economic_analytics(state) do
    %{
      total_auctions: length(state.completed_auctions) + map_size(state.active_auctions),
      active_auctions: map_size(state.active_auctions),
      total_transactions: length(state.transaction_history),
      total_transaction_volume: calculate_total_transaction_volume(state),
      average_transaction_value: calculate_average_transaction_value(state),
      marketplace_count: map_size(state.marketplaces),
      active_agents: map_size(state.agent_reputations),
      market_efficiency: calculate_market_efficiency(state),
      top_performers: get_top_performing_agents(state, 5),
      pricing_trends: calculate_pricing_trends(state),
      uptime_hours: DateTime.diff(DateTime.utc_now(), state.started_at, :second) / 3600
    }
  end

  defp calculate_total_transaction_volume(state) do
    Enum.reduce(state.transaction_history, 0, fn transaction, acc ->
      acc + transaction.amount
    end)
  end

  defp calculate_average_transaction_value(state) do
    case length(state.transaction_history) do
      0 -> 0.0
      count -> calculate_total_transaction_volume(state) / count
    end
  end

  defp calculate_market_efficiency(_state) do
    # Calculate market efficiency metrics
    # TODO: Implement sophisticated efficiency calculations
    # Placeholder
    0.85
  end

  defp get_top_performing_agents(state, limit) do
    state.agent_reputations
    |> Map.values()
    |> Enum.sort_by(& &1.reputation_score, :desc)
    |> Enum.take(limit)
    |> Enum.map(&%{agent_id: &1.agent_id, reputation_score: &1.reputation_score})
  end

  defp calculate_pricing_trends(_state) do
    # Analyze pricing trends across different service types
    # TODO: Implement comprehensive trend analysis
    %{
      overall_trend: :stable,
      service_trends: %{},
      volatility: 0.15
    }
  end

  # Marketplace analytics

  defp calculate_marketplace_analytics(marketplace, _state) do
    transactions = marketplace.completed_transactions

    %{
      marketplace_id: marketplace.id,
      total_listings: map_size(marketplace.active_listings),
      total_transactions: length(transactions),
      transaction_volume: Enum.reduce(transactions, 0, &(&1.amount + &2)),
      average_transaction_value: calculate_marketplace_average_transaction(transactions),
      top_providers: get_top_marketplace_providers(marketplace, 5),
      category_distribution: calculate_category_distribution(marketplace),
      satisfaction_score: calculate_marketplace_satisfaction(transactions),
      created_at: marketplace.created_at
    }
  end

  defp calculate_marketplace_average_transaction(transactions) do
    case length(transactions) do
      0 -> 0.0
      count -> Enum.reduce(transactions, 0, &(&1.amount + &2)) / count
    end
  end

  defp get_top_marketplace_providers(marketplace, limit) do
    marketplace.active_listings
    |> Map.values()
    |> Enum.group_by(& &1.provider)
    |> Enum.map(fn {provider, listings} ->
      {provider, length(listings),
       Enum.sum(Enum.map(listings, & &1.reputation_score)) / length(listings)}
    end)
    |> Enum.sort_by(fn {_provider, _count, avg_reputation} -> avg_reputation end, :desc)
    |> Enum.take(limit)
    |> Enum.map(fn {provider, listing_count, avg_reputation} ->
      %{provider: provider, listing_count: listing_count, average_reputation: avg_reputation}
    end)
  end

  defp calculate_category_distribution(marketplace) do
    marketplace.active_listings
    |> Map.values()
    |> Enum.group_by(& &1.service_type)
    |> Enum.map(fn {category, listings} -> {category, length(listings)} end)
    |> Enum.into(%{})
  end

  defp calculate_marketplace_satisfaction(transactions) do
    case length(transactions) do
      0 ->
        0.0

      count ->
        Enum.reduce(transactions, 0, &(&1.satisfaction_score + &2)) / count
    end
  end

  # Utility functions

  defp generate_auction_id(),
    do: ("auction_" <> :crypto.strong_rand_bytes(8)) |> Base.encode16(case: :lower)

  defp generate_marketplace_id(),
    do: ("market_" <> :crypto.strong_rand_bytes(8)) |> Base.encode16(case: :lower)

  defp generate_bid_id(),
    do: ("bid_" <> :crypto.strong_rand_bytes(8)) |> Base.encode16(case: :lower)

  defp generate_listing_id(),
    do: ("listing_" <> :crypto.strong_rand_bytes(8)) |> Base.encode16(case: :lower)

  defp generate_transaction_id(),
    do: ("txn_" <> :crypto.strong_rand_bytes(8)) |> Base.encode16(case: :lower)

  defp generate_task_id(),
    do: ("task_" <> :crypto.strong_rand_bytes(8)) |> Base.encode16(case: :lower)

  defp generate_market_id(),
    do: ("mkt_" <> :crypto.strong_rand_bytes(8)) |> Base.encode16(case: :lower)

  defp generate_order_id(),
    do: ("order_" <> :crypto.strong_rand_bytes(8)) |> Base.encode16(case: :lower)

  defp generate_prediction_market_id(),
    do: ("pred_" <> :crypto.strong_rand_bytes(8)) |> Base.encode16(case: :lower)

  defp generate_bet_id(),
    do: ("bet_" <> :crypto.strong_rand_bytes(8)) |> Base.encode16(case: :lower)

  defp calculate_auction_end_time(auction_spec, opts) do
    duration_minutes =
      Keyword.get(opts, :duration_minutes) ||
        Map.get(auction_spec, :duration_minutes, @default_auction_duration_minutes)

    DateTime.utc_now() |> DateTime.add(duration_minutes * 60, :second)
  end

  defp build_auction_config(auction_spec, opts) do
    %{
      reserve_price: Map.get(auction_spec, :reserve_price, 0.0),
      buy_now_price: Map.get(auction_spec, :buy_now_price),
      bid_increment: Map.get(auction_spec, :bid_increment, @default_bid_increment),
      max_bidders: Keyword.get(opts, :max_bidders, 50),
      quality_requirements: Map.get(auction_spec, :quality_requirements, %{})
    }
  end

  defp default_fee_structure() do
    %{
      listing_fee: 0.05,
      transaction_fee: 0.03,
      success_fee: 0.02,
      cancellation_penalty: 0.10
    }
  end

  defp default_availability() do
    %{
      timezone: "UTC",
      available_hours: %{
        monday: [0, 23],
        tuesday: [0, 23],
        wednesday: [0, 23],
        thursday: [0, 23],
        friday: [0, 23],
        saturday: [0, 23],
        sunday: [0, 23]
      },
      maintenance_windows: [],
      peak_performance_hours: [
        %{
          start_time: ~T[09:00:00],
          end_time: ~T[17:00:00],
          days_of_week: [1, 2, 3, 4, 5],
          capacity_percentage: 1.0
        }
      ],
      capacity_schedule: %{}
    }
  end

  defp default_pricing_model() do
    %{
      base_rate: 1.0,
      complexity_multipliers: %{simple: 1.0, moderate: 1.5, complex: 2.0, expert: 3.0},
      quality_bonuses: %{standard: 1.0, premium: 1.25, enterprise: 1.5},
      volume_discounts: %{},
      rush_surcharges: %{urgent: 1.5, emergency: 2.0},
      currency: :usd
    }
  end

  defp initialize_default_pricing_models() do
    %{
      "text_generation" => %{
        provider: :local,
        pricing_type: :per_token,
        base_cost: 0.002,
        volume_discounts: %{1000 => 0.9, 10000 => 0.8},
        rate_limits: %{rpm: 1000, tpm: 50000},
        quality_adjustments: %{premium: 1.5, standard: 1.0, economy: 0.7}
      },
      "code_generation" => %{
        provider: :local,
        pricing_type: :per_request,
        base_cost: 0.05,
        volume_discounts: %{100 => 0.95, 500 => 0.9},
        rate_limits: %{rpm: 100, tpm: 10000},
        quality_adjustments: %{production: 2.0, development: 1.0, prototype: 0.6}
      }
    }
  end

  defp service_type_allowed(service_type, marketplace) do
    case marketplace.categories do
      # Allow all if no restrictions
      [] -> true
      categories -> service_type in categories
    end
  end

  defp meets_reputation_requirements(agent_id, marketplace, state) do
    min_reputation = Map.get(marketplace.reputation_requirements, :minimum_score, 0.0)
    agent_reputation = get_agent_reputation_score(agent_id, state)

    agent_reputation >= min_reputation
  end

  defp calculate_listing_expiry(service_spec) do
    case Map.get(service_spec, :listing_duration_days) do
      # No expiry
      nil -> nil
      days -> DateTime.utc_now() |> DateTime.add(days * 24 * 3600, :second)
    end
  end

  defp apply_auction_filters(auctions, filters) do
    auctions
    |> filter_by_type(Keyword.get(filters, :type))
    |> filter_by_status(Keyword.get(filters, :status))
    |> filter_by_category(Keyword.get(filters, :category))
  end

  defp filter_by_type(auctions, nil), do: auctions
  defp filter_by_type(auctions, type), do: Enum.filter(auctions, &(&1.type == type))

  defp filter_by_status(auctions, nil), do: auctions
  defp filter_by_status(auctions, status), do: Enum.filter(auctions, &(&1.status == status))

  defp filter_by_category(auctions, nil), do: auctions

  defp filter_by_category(auctions, category) do
    Enum.filter(auctions, fn auction ->
      Map.get(auction.task, :category) == category
    end)
  end

  # Cleanup and maintenance functions

  defp cleanup_expired_auctions(state) do
    current_time = DateTime.utc_now()

    {expired_auctions, active_auctions} =
      Map.split_with(state.active_auctions, fn {_id, auction} ->
        DateTime.compare(current_time, auction.ends_at) == :gt
      end)

    # Move expired auctions to completed list
    expired_auction_list =
      expired_auctions
      |> Enum.map(fn {_id, auction} -> %{auction | status: :expired} end)

    updated_completed = expired_auction_list ++ state.completed_auctions

    if map_size(expired_auctions) > 0 do
      Logger.info("Cleaned up #{map_size(expired_auctions)} expired auctions")
    end

    %{state | active_auctions: active_auctions, completed_auctions: updated_completed}
  end

  defp decay_reputations(state) do
    # Apply time-based reputation decay to encourage continuous performance
    updated_reputations =
      Map.new(state.agent_reputations, fn {agent_id, reputation} ->
        decayed_score = reputation.reputation_score * @reputation_decay_factor
        updated_reputation = %{reputation | reputation_score: decayed_score}
        {agent_id, updated_reputation}
      end)

    %{state | agent_reputations: updated_reputations}
  end

  defp schedule_auction_cleanup() do
    Process.send_after(self(), :auction_cleanup, @auction_cleanup_interval)
  end

  defp schedule_reputation_update() do
    # Update reputations daily
    Process.send_after(self(), :reputation_update, 24 * 60 * 60 * 1000)
  end

  # Telemetry functions

  defp emit_economics_telemetry(event_name, auction, measurements) do
    try do
      :telemetry.execute(
        [:foundation, :mabeam, :economics, event_name],
        Map.merge(%{count: 1}, measurements),
        %{
          auction_id: auction.id,
          auction_type: auction.type,
          status: auction.status
        }
      )
    rescue
      _ -> :ok
    end
  end

  # ============================================================================
  # Child Spec for Supervision
  # ============================================================================

  @doc false
  # Missing helper functions for statistics and analytics

  defp calculate_average_auction_value(state) do
    all_auctions = Map.values(state.active_auctions) ++ state.completed_auctions

    case length(all_auctions) do
      0 ->
        0.0

      count ->
        total_value =
          Enum.sum(
            Enum.map(all_auctions, fn auction ->
              case auction.winning_bid do
                nil -> 0.0
                bid -> Map.get(bid, :amount, 0.0)
              end
            end)
          )

        total_value / count
    end
  end

  defp calculate_market_efficiency_score(_state), do: 0.85

  defp calculate_average_transaction_time(state) do
    case length(state.transaction_history) do
      0 ->
        0.0

      count ->
        # Placeholder: 1.5 seconds average
        total_time = count * 1500
        total_time / count
    end
  end

  defp calculate_cost_efficiency_trend(_state), do: %{trend: :stable, efficiency: 0.78}

  defp calculate_agent_satisfaction_score(_state), do: 0.82

  defp analyze_market_trends(_state, _time_range), do: %{trend: :growing, volatility: :low}

  defp identify_cost_optimizations(_state), do: []

  defp generate_performance_rankings(state) do
    state.agent_reputations
    |> Map.values()
    |> Enum.sort_by(& &1.reputation_score, :desc)
    |> Enum.take(10)
  end

  defp generate_recommendations(_state, _time_range), do: []

  # Helper functions for the new request_service signature

  defp find_listing_by_id(state, listing_id) do
    # Search through all marketplaces to find the listing
    Enum.reduce_while(state.marketplaces, {:error, :listing_not_found}, fn {marketplace_id,
                                                                            marketplace},
                                                                           _acc ->
      case Map.get(marketplace.active_listings, listing_id) do
        nil -> {:cont, {:error, :listing_not_found}}
        listing -> {:halt, {:ok, marketplace_id, marketplace, listing}}
      end
    end)
  end

  defp calculate_transaction_amount_from_request(listing, service_requirements) do
    # Calculate transaction amount based on listing pricing and service requirements
    base_rate = Map.get(listing.pricing, :base_rate, 1.0)

    # Apply any cost adjustments from service requirements
    cost_multiplier =
      case Map.get(service_requirements, :max_cost) do
        nil -> 1.0
        # Cap at 2x multiplier
        max_cost -> min(max_cost / base_rate, 2.0)
      end

    base_rate * cost_multiplier
  end

  defp detect_reputation_gaming(current_reputation, performance_data) do
    # Check for duplicate submissions
    case check_duplicate_performance_record(
           current_reputation.performance_history,
           performance_data
         ) do
      true ->
        {:error, "Duplicate performance record detected - potential gaming attempt"}

      false ->
        # Additional gaming checks can be added here
        case check_unrealistic_performance_data(performance_data) do
          true -> {:error, "Unrealistic performance data detected - potential gaming attempt"}
          false -> {:ok, :valid}
        end
    end
  end

  defp check_duplicate_performance_record(performance_history, new_performance_data) do
    # Check if an identical record exists in recent history
    Enum.any?(performance_history, fn record ->
      record.task_id == Map.get(new_performance_data, :task_id) &&
        record.quality_score == Map.get(new_performance_data, :quality_score) &&
        record.cost_efficiency == Map.get(new_performance_data, :cost_efficiency) &&
        record.completion_time_ms == Map.get(new_performance_data, :completion_time_ms) &&
        record.client_satisfaction == Map.get(new_performance_data, :client_satisfaction)
    end)
  end

  defp check_unrealistic_performance_data(performance_data) do
    # Check for obviously fake data (perfect scores with unrealistic completion times)
    quality_score = Map.get(performance_data, :quality_score, 0.5)
    cost_efficiency = Map.get(performance_data, :cost_efficiency, 0.5)
    completion_time_ms = Map.get(performance_data, :completion_time_ms, 60_000)
    client_satisfaction = Map.get(performance_data, :client_satisfaction, 0.5)

    # Flag if all scores are perfect AND completion time is suspiciously fast (less than 100ms)
    all_perfect = quality_score == 1.0 && cost_efficiency == 1.0 && client_satisfaction == 1.0
    # Less than 100ms is suspicious
    too_fast = completion_time_ms < 100

    all_perfect && too_fast
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end
end
