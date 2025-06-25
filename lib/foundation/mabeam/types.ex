defmodule Foundation.MABEAM.Types do
  @moduledoc """
  Comprehensive type definitions for Foundation MABEAM multi-agent system.

  This module defines all types used across the MABEAM platform, with special focus on:
  - ML/LLM-specific coordination types for premier platform capabilities
  - Distribution-ready serializable types for transparent scaling
  - Performance and cost optimization primitives
  - Advanced coordination algorithm types

  All types are designed to be serializable across nodes and support the complete
  ML/LLM workflow lifecycle from development to production deployment.
  """

  # ============================================================================
  # Core Agent Types
  # ============================================================================

  @type agent_id :: atom() | String.t()
  @type agent_type :: atom()
  @type node_id :: atom()
  @type cluster_id :: String.t()

  @type agent_status ::
          :registered
          | :starting
          | :running
          | :stopping
          | :stopped
          | :failed
          | :suspended
          | :migrating
          | :retiring

  @type agent_capability ::
          :reasoning
          | :computation
          | :coordination
          | :llm_inference
          | :tool_execution
          | :data_processing
          | :model_training
          | :ensemble_learning
          | :hyperparameter_optimization
          | :federated_learning
          | :cost_optimization

  @type agent_specialization ::
          :gpt_specialist
          | :claude_specialist
          | :reasoning_expert
          | :code_generator
          | :data_analyst
          | :research_assistant
          | :creative_writer
          | :mathematical_solver
          | :tool_orchestrator
          | :ensemble_coordinator
          | :cost_optimizer

  @type agent_config :: %{
          id: agent_id(),
          module: module(),
          args: list(),
          type: agent_type(),
          capabilities: [agent_capability()],
          metadata: map(),
          restart_policy: :permanent | :temporary | :transient,
          created_at: DateTime.t()
        }

  @type universal_variable :: %{
          name: atom(),
          value: term(),
          version: pos_integer(),
          last_modifier: agent_id(),
          conflict_resolution: :last_write_wins | :consensus | {:custom, module(), atom()},
          metadata: map(),
          constraints: map(),
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @type coordination_request :: %{
          protocol: atom(),
          type: atom(),
          params: map(),
          correlation_id: String.t(),
          created_at: DateTime.t()
        }

  @type auction_spec :: %{
          type: auction_type(),
          resource_id: atom(),
          participants: [agent_id()],
          starting_price: float() | nil,
          payment_rule: :first_price | :second_price,
          auction_params: map(),
          created_at: DateTime.t()
        }

  # ============================================================================
  # ML/LLM-Specific Types
  # ============================================================================

  @type ml_coordination_type ::
          :ensemble_learning
          | :hyperparameter_search
          | :model_selection
          | :federated_training
          | :chain_of_thought
          | :tool_orchestration
          | :multi_modal_fusion
          | :reasoning_consensus
          | :cost_optimization
          | :performance_benchmarking
          | :a_b_testing

  @type llm_provider :: :openai | :anthropic | :google | :cohere | :local | :custom

  @type llm_model_config :: %{
          provider: llm_provider(),
          model_name: String.t(),
          context_window: pos_integer(),
          cost_per_input_token: float(),
          cost_per_output_token: float(),
          rate_limit_rpm: pos_integer(),
          rate_limit_tpm: pos_integer(),
          capabilities: [atom()],
          specializations: [agent_specialization()],
          performance_metrics: map()
        }

  @type reasoning_strategy ::
          :chain_of_thought
          | :tree_of_thought
          | :react
          | :reflexion
          | :self_consistency
          | :program_of_thought
          | :least_to_most
          | :ensemble_reasoning
          | :debate_reasoning
          | :iterative_refinement

  @type ml_task_type ::
          :text_generation
          | :text_classification
          | :summarization
          | :translation
          | :question_answering
          | :code_generation
          | :mathematical_reasoning
          | :creative_writing
          | :data_analysis
          | :research
          | :planning
          | :tool_use
          | :multi_modal
          | :ensemble_prediction

  # ============================================================================
  # Advanced Coordination Types
  # ============================================================================

  @type coordination_algorithm ::
          :consensus
          | :auction
          | :negotiation
          | :voting
          | :optimization
          | :market_based
          | :evolutionary
          | :swarm
          | :hierarchical
          | :byzantine_fault_tolerant
          | :weighted_consensus
          | :iterative_refinement

  @type consensus_type ::
          :simple_majority
          | :supermajority
          | :unanimous
          | :weighted_voting
          | :expertise_weighted
          | :performance_weighted
          | :cost_weighted
          | :byzantine_consensus
          | :practical_byzantine_ft
          | :raft_consensus

  @type auction_type ::
          :english
          | :dutch
          | :sealed_bid
          | :vickrey
          | :combinatorial
          | :continuous_double
          | :multi_attribute
          | :reverse

  @type market_mechanism ::
          :auction
          | :bargaining
          | :posted_price
          | :exchange
          | :prediction_market
          | :reputation_based
          | :stake_weighted
          | :performance_based

  # ============================================================================
  # Distribution and Clustering Types
  # ============================================================================

  @type distribution_strategy ::
          :single_node
          | :multi_node
          | :multi_cluster
          | :geo_distributed
          | :edge_cloud
          | :hybrid_cloud
          | :federated

  @type node_role ::
          :coordinator
          | :worker
          | :storage
          | :gateway
          | :monitor
          | :load_balancer
          | :consensus_leader
          | :backup_coordinator

  @type cluster_topology ::
          :star | :ring | :mesh | :hierarchical | :tree | :graph | :hybrid

  @type network_partition_strategy ::
          :fail_fast
          | :eventual_consistency
          | :split_brain_resolution
          | :majority_partition
          | :coordinator_based
          | :consensus_based

  # ============================================================================
  # Performance and Resource Types
  # ============================================================================

  @type resource_type ::
          :cpu
          | :memory
          | :gpu
          | :network
          | :storage
          | :cost_budget
          | :api_quota
          | :rate_limit
          | :token_limit
          | :compute_credits

  @type performance_metric ::
          :latency
          | :throughput
          | :accuracy
          | :cost_efficiency
          | :resource_utilization
          | :error_rate
          | :availability
          | :user_satisfaction
          | :model_quality
          | :reasoning_depth

  @type cost_model :: %{
          provider: llm_provider(),
          pricing_type: :per_token | :per_request | :per_minute | :subscription,
          base_cost: float(),
          volume_discounts: map(),
          rate_limits: map(),
          quality_adjustments: map()
        }

  @type optimization_objective ::
          :minimize_cost
          | :maximize_accuracy
          | :minimize_latency
          | :maximize_throughput
          | :balance_cost_quality
          | :maximize_user_satisfaction
          | :minimize_resource_usage
          | :maximize_model_diversity

  # ============================================================================
  # Coordination Session Types
  # ============================================================================

  @type coordination_session :: %{
          id: String.t(),
          type: coordination_algorithm(),
          participants: [agent_id()],
          coordinator: agent_id(),
          status: coordination_status(),
          config: coordination_config(),
          state: map(),
          results: coordination_results() | nil,
          metadata: coordination_metadata(),
          created_at: DateTime.t(),
          updated_at: DateTime.t(),
          expires_at: DateTime.t() | nil
        }

  @type coordination_status ::
          :initializing
          | :recruiting
          | :active
          | :voting
          | :finalizing
          | :completed
          | :failed
          | :timeout
          | :cancelled
          | :suspended

  @type coordination_config :: %{
          algorithm: coordination_algorithm(),
          timeout_ms: pos_integer(),
          min_participants: pos_integer(),
          max_participants: pos_integer(),
          consensus_threshold: float(),
          cost_limit: float() | nil,
          quality_threshold: float() | nil,
          retry_policy: retry_policy(),
          failure_handling: failure_handling_policy()
        }

  @type coordination_results :: %{
          decision: term(),
          confidence: float(),
          participants: [agent_id()],
          voting_breakdown: map(),
          cost_incurred: float(),
          execution_time_ms: pos_integer(),
          quality_metrics: map(),
          consensus_rounds: pos_integer(),
          final_votes: map()
        }

  @type coordination_metadata :: %{
          session_type: ml_coordination_type(),
          task_specification: map(),
          resource_requirements: map(),
          expected_cost: float(),
          expected_duration_ms: pos_integer(),
          priority: :low | :normal | :high | :critical,
          tags: [String.t()],
          requester: agent_id(),
          budget_constraints: map()
        }

  # ============================================================================
  # Task and Workflow Types
  # ============================================================================

  @type ml_task :: %{
          id: String.t(),
          type: ml_task_type(),
          specification: task_specification(),
          requirements: task_requirements(),
          constraints: task_constraints(),
          status: task_status(),
          results: task_results() | nil,
          assigned_agents: [agent_id()],
          coordination_sessions: [String.t()],
          created_at: DateTime.t(),
          deadline: DateTime.t() | nil
        }

  @type task_specification :: %{
          input: term(),
          expected_output_format: atom(),
          quality_criteria: map(),
          performance_requirements: map(),
          reasoning_requirements: [reasoning_strategy()],
          tools_required: [atom()],
          domain_knowledge: [atom()],
          complexity_level: :simple | :moderate | :complex | :expert
        }

  @type task_requirements :: %{
          min_agents: pos_integer(),
          preferred_agents: pos_integer(),
          max_agents: pos_integer(),
          required_capabilities: [agent_capability()],
          preferred_specializations: [agent_specialization()],
          resource_limits: map(),
          cost_budget: float() | nil,
          quality_threshold: float(),
          deadline: DateTime.t() | nil
        }

  @type task_constraints :: %{
          cost_limit: float() | nil,
          time_limit_ms: pos_integer() | nil,
          resource_limits: map(),
          provider_restrictions: [llm_provider()],
          model_restrictions: [String.t()],
          geographic_constraints: [String.t()],
          security_requirements: [atom()],
          compliance_requirements: [atom()]
        }

  @type task_status ::
          :pending
          | :recruiting
          | :assigned
          | :in_progress
          | :coordinating
          | :reviewing
          | :completed
          | :failed
          | :cancelled
          | :timeout

  @type task_results :: %{
          output: term(),
          confidence: float(),
          quality_score: float(),
          cost_incurred: float(),
          execution_time_ms: pos_integer(),
          agents_involved: [agent_id()],
          coordination_summary: map(),
          performance_metrics: map(),
          error_details: map() | nil
        }

  # ============================================================================
  # Economic and Market Types
  # ============================================================================

  @type economic_agent :: %{
          agent_id: agent_id(),
          reputation_score: float(),
          performance_history: [performance_record()],
          cost_efficiency: float(),
          specialization_scores: map(),
          availability: availability_schedule(),
          pricing_model: pricing_model(),
          resource_capacity: map()
        }

  @type performance_record :: %{
          task_id: String.t(),
          task_type: ml_task_type(),
          quality_score: float(),
          cost_efficiency: float(),
          completion_time_ms: pos_integer(),
          client_satisfaction: float(),
          timestamp: DateTime.t()
        }

  @type availability_schedule :: %{
          timezone: String.t(),
          available_hours: map(),
          maintenance_windows: [time_window()],
          peak_performance_hours: [time_window()],
          capacity_schedule: map()
        }

  @type time_window :: %{
          start_time: Time.t(),
          end_time: Time.t(),
          days_of_week: [1..7],
          capacity_percentage: float()
        }

  @type pricing_model :: %{
          base_rate: float(),
          complexity_multipliers: map(),
          quality_bonuses: map(),
          volume_discounts: map(),
          rush_surcharges: map(),
          currency: :usd | :eur | :tokens | :credits
        }

  @type auction :: %{
          id: String.t(),
          type: auction_type(),
          task: ml_task(),
          bids: [bid()],
          status: auction_status(),
          winner: agent_id() | nil,
          winning_bid: bid() | nil,
          started_at: DateTime.t(),
          ends_at: DateTime.t(),
          config: auction_config()
        }

  @type bid :: %{
          bidder: agent_id(),
          amount: float(),
          quality_guarantee: float(),
          delivery_time_ms: pos_integer(),
          conditions: map(),
          submitted_at: DateTime.t()
        }

  @type auction_status ::
          :open | :closing | :closed | :awarded | :cancelled | :disputed

  @type auction_config :: %{
          reserve_price: float() | nil,
          buy_now_price: float() | nil,
          increment_minimum: float(),
          extension_rules: map(),
          evaluation_criteria: [evaluation_criterion()],
          payment_terms: payment_terms()
        }

  @type evaluation_criterion :: %{
          name: atom(),
          weight: float(),
          scoring_function: atom(),
          min_threshold: float() | nil
        }

  @type payment_terms :: %{
          payment_method: :escrow | :direct | :milestone_based,
          payment_schedule: [payment_milestone()],
          penalty_clauses: map(),
          bonus_clauses: map()
        }

  @type payment_milestone :: %{
          percentage: float(),
          trigger: :start | :progress | :completion | :acceptance,
          due_offset_ms: pos_integer()
        }

  # ============================================================================
  # Telemetry and Analytics Types
  # ============================================================================

  @type telemetry_event :: %{
          event_name: atom(),
          measurements: map(),
          metadata: map(),
          timestamp: DateTime.t(),
          source: agent_id() | node_id(),
          tags: [String.t()]
        }

  @type metric_type ::
          :counter
          | :gauge
          | :histogram
          | :summary
          | :timer
          | :cost_tracker
          | :quality_tracker
          | :performance_tracker

  @type analytics_model ::
          :linear_regression
          | :decision_tree
          | :neural_network
          | :ensemble
          | :time_series
          | :anomaly_detection
          | :clustering
          | :reinforcement_learning

  @type predictive_model :: %{
          model_type: analytics_model(),
          training_data_size: pos_integer(),
          accuracy_score: float(),
          feature_importance: map(),
          prediction_confidence: float(),
          last_trained: DateTime.t(),
          next_training: DateTime.t(),
          model_artifacts: map()
        }

  @type anomaly_detection_config :: %{
          algorithm: :isolation_forest | :one_class_svm | :lstm | :statistical,
          sensitivity: float(),
          training_window_hours: pos_integer(),
          detection_threshold: float(),
          alert_policies: [alert_policy()]
        }

  @type alert_policy :: %{
          severity: :info | :warning | :error | :critical,
          channels: [notification_channel()],
          escalation_rules: [escalation_rule()],
          suppression_rules: [suppression_rule()]
        }

  @type notification_channel ::
          :log | :email | :slack | :webhook | :sms | :dashboard

  @type escalation_rule :: %{
          trigger_after_ms: pos_integer(),
          escalate_to: notification_channel(),
          escalation_message: String.t()
        }

  @type suppression_rule :: %{
          condition: String.t(),
          duration_ms: pos_integer(),
          reason: String.t()
        }

  # ============================================================================
  # Error Handling and Resilience Types
  # ============================================================================

  @type error_classification ::
          :transient
          | :permanent
          | :resource_exhaustion
          | :network
          | :authentication
          | :authorization
          | :rate_limit
          | :service_unavailable
          | :data_corruption
          | :timeout
          | :configuration
          | :unknown

  @type retry_policy :: %{
          max_attempts: pos_integer(),
          initial_delay_ms: pos_integer(),
          backoff_strategy: :linear | :exponential | :fibonacci | :constant,
          backoff_multiplier: float(),
          max_delay_ms: pos_integer(),
          jitter: boolean(),
          retry_on: [error_classification()]
        }

  @type failure_handling_policy :: %{
          on_agent_failure: :retry | :replace | :degrade | :abort,
          on_coordination_failure: :retry | :simplify | :abort,
          on_resource_exhaustion: :wait | :scale | :degrade | :abort,
          on_network_partition: :wait | :split_brain_resolution | :abort,
          fallback_strategies: [fallback_strategy()]
        }

  @type fallback_strategy :: %{
          trigger_condition: String.t(),
          strategy: :cached_response | :simplified_algorithm | :human_escalation | :best_effort,
          configuration: map()
        }

  @type circuit_breaker_config :: %{
          failure_threshold: pos_integer(),
          recovery_timeout_ms: pos_integer(),
          half_open_max_calls: pos_integer(),
          state_change_listeners: [atom()]
        }

  # ============================================================================
  # Security and Compliance Types
  # ============================================================================

  @type security_level :: :public | :internal | :confidential | :restricted | :top_secret

  @type access_control :: %{
          read_roles: [atom()],
          write_roles: [atom()],
          execute_roles: [atom()],
          admin_roles: [atom()],
          data_classification: security_level(),
          geographic_restrictions: [String.t()],
          time_restrictions: [time_window()]
        }

  @type compliance_requirement ::
          :gdpr | :hipaa | :sox | :pci_dss | :iso_27001 | :fedramp | :custom

  @type audit_event :: %{
          event_type: atom(),
          actor: agent_id(),
          resource: String.t(),
          action: atom(),
          outcome: :success | :failure | :partial,
          metadata: map(),
          timestamp: DateTime.t(),
          session_id: String.t() | nil
        }

  # ============================================================================
  # Configuration and Environment Types
  # ============================================================================

  @type environment :: :development | :testing | :staging | :production

  @type deployment_config :: %{
          environment: environment(),
          cluster_size: pos_integer(),
          node_roles: map(),
          resource_limits: map(),
          scaling_policies: [scaling_policy()],
          monitoring_config: monitoring_config(),
          feature_flags: map()
        }

  @type scaling_policy :: %{
          metric: performance_metric(),
          threshold: float(),
          action: :scale_up | :scale_down | :scale_out | :scale_in,
          cooldown_ms: pos_integer(),
          min_instances: pos_integer(),
          max_instances: pos_integer()
        }

  @type monitoring_config :: %{
          metrics_retention_days: pos_integer(),
          log_level: :debug | :info | :warning | :error,
          sampling_rate: float(),
          alert_channels: [notification_channel()],
          dashboard_config: map()
        }

  # ============================================================================
  # Utility Types and Guards
  # ============================================================================

  @type result(success_type, error_type) :: {:ok, success_type} | {:error, error_type}
  @type maybe(type) :: type | nil
  @type timestamp :: DateTime.t() | NaiveDateTime.t() | pos_integer()

  # Type guards for runtime validation
  defguard is_agent_id(term) when is_atom(term) or is_binary(term)
  defguard is_positive_number(term) when is_number(term) and term > 0
  defguard is_percentage(term) when is_number(term) and term >= 0.0 and term <= 1.0
  defguard is_valid_timeout(term) when is_integer(term) and term > 0
  defguard is_cost_amount(term) when is_number(term) and term >= 0.0

  # ============================================================================
  # Type Validation Functions
  # ============================================================================

  @doc """
  Validates that a term conforms to the agent_id type.
  """
  @spec validate_agent_id(term()) :: {:ok, agent_id()} | {:error, String.t()}
  def validate_agent_id(term) when is_agent_id(term), do: {:ok, term}
  def validate_agent_id(term), do: {:error, "Invalid agent_id: #{inspect(term)}"}

  @doc """
  Validates coordination configuration.
  """
  @spec validate_coordination_config(map()) :: {:ok, coordination_config()} | {:error, String.t()}
  def validate_coordination_config(%{algorithm: algo, timeout_ms: timeout} = config)
      when is_atom(algo) and is_valid_timeout(timeout) do
    # Additional validation logic here
    {:ok, config}
  end

  def validate_coordination_config(config) do
    {:error, "Invalid coordination config: #{inspect(config)}"}
  end

  @doc """
  Validates ML task specification.
  """
  @spec validate_ml_task(map()) :: {:ok, ml_task()} | {:error, String.t()}
  def validate_ml_task(%{id: id, type: type} = task)
      when is_binary(id) and is_atom(type) do
    case type in [
           :text_generation,
           :text_classification,
           :summarization,
           :translation,
           :question_answering,
           :code_generation,
           :mathematical_reasoning,
           :creative_writing,
           :data_analysis,
           :research,
           :planning,
           :tool_use,
           :multi_modal,
           :ensemble_prediction
         ] do
      true -> {:ok, task}
      false -> {:error, "Invalid ML task type: #{type}"}
    end
  end

  def validate_ml_task(task) do
    {:error, "Invalid ML task: #{inspect(task)}"}
  end

  @doc """
  Validates cost model configuration.
  """
  @spec validate_cost_model(map()) :: {:ok, cost_model()} | {:error, String.t()}
  def validate_cost_model(%{provider: provider, pricing_type: pricing, base_cost: cost} = model)
      when is_atom(provider) and is_atom(pricing) and is_cost_amount(cost) do
    {:ok, model}
  end

  def validate_cost_model(model) do
    {:error, "Invalid cost model: #{inspect(model)}"}
  end

  @doc """
  Creates a default coordination config with sensible defaults.
  """
  @spec default_coordination_config(coordination_algorithm()) :: coordination_config()
  def default_coordination_config(algorithm) do
    %{
      algorithm: algorithm,
      timeout_ms: 30_000,
      min_participants: 1,
      max_participants: 10,
      consensus_threshold: 0.6,
      cost_limit: nil,
      quality_threshold: 0.8,
      retry_policy: default_retry_policy(),
      failure_handling: default_failure_handling_policy()
    }
  end

  @doc """
  Creates a default retry policy.
  """
  def default_retry_policy() do
    %{
      max_attempts: 3,
      initial_delay_ms: 1000,
      backoff_strategy: :exponential,
      backoff_multiplier: 2.0,
      max_delay_ms: 10_000,
      jitter: true,
      retry_on: [:transient, :network, :timeout, :service_unavailable]
    }
  end

  @doc """
  Creates a default failure handling policy.
  """
  @spec default_failure_handling_policy() :: failure_handling_policy()
  def default_failure_handling_policy() do
    %{
      on_agent_failure: :replace,
      on_coordination_failure: :retry,
      on_resource_exhaustion: :scale,
      on_network_partition: :wait,
      fallback_strategies: [
        %{
          trigger_condition: "high_cost",
          strategy: :simplified_algorithm,
          configuration: %{cost_reduction_factor: 0.5}
        },
        %{
          trigger_condition: "low_quality",
          strategy: :human_escalation,
          configuration: %{escalation_timeout_ms: 300_000}
        }
      ]
    }
  end

  # ============================================================================
  # Constructor Functions
  # ============================================================================

  @doc """
  Creates a new agent configuration.
  """
  @spec new_agent_config(agent_id(), module(), list(), keyword()) :: agent_config()
  def new_agent_config(id, module, args, opts \\ []) do
    %{
      id: id,
      module: module,
      args: args,
      type: Keyword.get(opts, :type, :worker),
      capabilities: Keyword.get(opts, :capabilities, []),
      metadata: Keyword.get(opts, :metadata, %{}),
      restart_policy: Keyword.get(opts, :restart_policy, :permanent),
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Creates a new universal variable.
  """
  @spec new_variable(atom(), term(), agent_id(), keyword()) :: universal_variable()
  def new_variable(name, value, modifier, opts \\ []) do
    now = DateTime.utc_now()

    %{
      name: name,
      value: value,
      version: 1,
      last_modifier: modifier,
      conflict_resolution: Keyword.get(opts, :conflict_resolution, :last_write_wins),
      metadata: Keyword.get(opts, :metadata, %{}),
      constraints: Keyword.get(opts, :constraints, %{}),
      created_at: now,
      updated_at: now
    }
  end

  @doc """
  Creates a new coordination request.
  """
  @spec new_coordination_request(atom(), atom(), map()) :: coordination_request()
  def new_coordination_request(protocol, type, params) do
    %{
      protocol: protocol,
      type: type,
      params: params,
      correlation_id: generate_correlation_id(),
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Creates a new auction specification.
  """
  @spec new_auction_spec(auction_type(), atom(), [agent_id()], keyword()) :: auction_spec()
  def new_auction_spec(type, resource_id, participants, opts \\ []) do
    %{
      type: type,
      resource_id: resource_id,
      participants: participants,
      starting_price: Keyword.get(opts, :starting_price),
      payment_rule: Keyword.get(opts, :payment_rule, :first_price),
      auction_params: Map.new(Keyword.drop(opts, [:starting_price, :payment_rule])),
      created_at: DateTime.utc_now()
    }
  end

  # ============================================================================
  # Validation Functions for Constructor Results
  # ============================================================================

  @doc """
  Validates an agent configuration.
  """
  @spec validate_agent_config(map()) :: {:ok, agent_config()} | {:error, term()}
  def validate_agent_config(%{id: id, module: module, args: args} = config)
      when is_atom(id) and is_atom(module) and is_list(args) and not is_nil(id) do
    {:ok, config}
  end

  def validate_agent_config(%{id: id}) when is_nil(id) or not is_atom(id) do
    {:error, {:invalid_agent_id, "Agent ID must be an atom"}}
  end

  def validate_agent_config(config) do
    {:error, {:invalid_agent_config, "Missing required fields: #{inspect(config)}"}}
  end

  @doc """
  Validates a universal variable.
  """
  @spec validate_variable(map()) :: {:ok, universal_variable()} | {:error, term()}
  def validate_variable(%{name: name, version: version} = var)
      when is_atom(name) and is_integer(version) and version > 0 and not is_nil(name) do
    {:ok, var}
  end

  def validate_variable(%{name: name}) when is_nil(name) or not is_atom(name) do
    {:error, {:invalid_variable_name, "Variable name must be an atom"}}
  end

  def validate_variable(%{version: version}) when not is_integer(version) or version <= 0 do
    {:error, {:invalid_version, "Version must be a positive integer"}}
  end

  def validate_variable(var) do
    {:error, {:invalid_variable, "Missing required fields: #{inspect(var)}"}}
  end

  @doc """
  Validates a coordination request.
  """
  @spec validate_coordination_request(map()) :: {:ok, coordination_request()} | {:error, term()}
  def validate_coordination_request(%{protocol: protocol, type: type, params: params} = request)
      when is_atom(protocol) and is_atom(type) and is_map(params) do
    {:ok, request}
  end

  def validate_coordination_request(request) do
    {:error, {:invalid_coordination_request, "Invalid coordination request: #{inspect(request)}"}}
  end

  @doc """
  Validates an auction specification.
  """
  @spec validate_auction_spec(map()) :: {:ok, auction_spec()} | {:error, term()}
  def validate_auction_spec(%{type: type, participants: participants} = spec)
      when type in [:sealed_bid, :english, :dutch] and is_list(participants) and
             length(participants) > 0 do
    {:ok, spec}
  end

  def validate_auction_spec(%{type: type}) when type not in [:sealed_bid, :english, :dutch] do
    {:error, {:invalid_auction_type, "Invalid auction type: #{type}"}}
  end

  def validate_auction_spec(%{participants: []}) do
    {:error, {:no_participants, "Auction must have at least one participant"}}
  end

  def validate_auction_spec(spec) do
    {:error, {:invalid_auction_spec, "Invalid auction specification: #{inspect(spec)}"}}
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp generate_correlation_id() do
    :crypto.strong_rand_bytes(16) |> Base.encode64(padding: false)
  end
end
