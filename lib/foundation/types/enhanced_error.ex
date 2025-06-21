# lib/foundation/types/enhanced_error.ex
defmodule Foundation.Types.EnhancedError do
  @moduledoc """
  Enhanced error type system with hierarchical error codes and comprehensive error management.
  
  Extends the basic Foundation.Types.Error with additional capabilities needed for
  multi-agent coordination, including error propagation chains, distributed error
  handling, and coordination-specific error types.
  """

  alias Foundation.Types.Error

  # Additional error definitions for MABEAM and enhanced Foundation features
  @mabeam_error_definitions %{
    # Agent Management Errors (5000-5999)
    {:agent, :lifecycle, :agent_start_failed} => 
      {5001, :high, "Agent failed to start"},
    {:agent, :lifecycle, :agent_stop_failed} => 
      {5002, :medium, "Agent failed to stop gracefully"},
    {:agent, :lifecycle, :agent_crashed} => 
      {5003, :high, "Agent process crashed unexpectedly"},
    {:agent, :lifecycle, :agent_timeout} => 
      {5004, :medium, "Agent operation timed out"},
    
    {:agent, :registration, :agent_not_found} => 
      {5101, :medium, "Agent not found in registry"},
    {:agent, :registration, :agent_already_exists} => 
      {5102, :medium, "Agent already registered"},
    {:agent, :registration, :invalid_agent_config} => 
      {5103, :high, "Invalid agent configuration"},
    
    {:agent, :communication, :message_delivery_failed} => 
      {5201, :medium, "Failed to deliver message to agent"},
    {:agent, :communication, :response_timeout} => 
      {5202, :medium, "Agent response timeout"},
    {:agent, :communication, :invalid_message_format} => 
      {5203, :low, "Invalid message format"},

    # Coordination Errors (6000-6999)  
    {:coordination, :consensus, :consensus_failed} => 
      {6001, :high, "Consensus algorithm failed to reach agreement"},
    {:coordination, :consensus, :consensus_timeout} => 
      {6002, :medium, "Consensus algorithm timed out"},
    {:coordination, :consensus, :insufficient_participants} => 
      {6003, :medium, "Insufficient participants for consensus"},

    {:coordination, :negotiation, :negotiation_failed} => 
      {6101, :medium, "Negotiation failed to reach agreement"},
    {:coordination, :negotiation, :negotiation_deadlock} => 
      {6102, :medium, "Negotiation reached deadlock"},
    {:coordination, :negotiation, :invalid_offer} => 
      {6103, :low, "Invalid negotiation offer"},

    {:coordination, :auction, :auction_failed} => 
      {6201, :medium, "Auction process failed"},
    {:coordination, :auction, :no_valid_bids} => 
      {6202, :low, "No valid bids received"},
    {:coordination, :auction, :auction_timeout} => 
      {6203, :medium, "Auction timed out"},

    {:coordination, :market, :market_failure} => 
      {6301, :high, "Market mechanism failed"},
    {:coordination, :market, :price_discovery_failed} => 
      {6302, :medium, "Failed to discover market price"},
    {:coordination, :market, :no_market_equilibrium} => 
      {6303, :medium, "No market equilibrium found"},

    # Orchestration Errors (7000-7999)
    {:orchestration, :variable, :variable_not_found} => 
      {7001, :medium, "Orchestration variable not found"},
    {:orchestration, :variable, :variable_conflict} => 
      {7002, :high, "Conflicting orchestration variables"},
    {:orchestration, :variable, :invalid_variable_config} => 
      {7003, :high, "Invalid orchestration variable configuration"},

    {:orchestration, :resource, :resource_exhausted} => 
      {7101, :high, "System resources exhausted"},
    {:orchestration, :resource, :resource_allocation_failed} => 
      {7102, :high, "Failed to allocate required resources"},
    {:orchestration, :resource, :resource_conflict} => 
      {7103, :medium, "Resource allocation conflict"},

    {:orchestration, :execution, :execution_failed} => 
      {7201, :high, "Orchestration execution failed"},
    {:orchestration, :execution, :execution_timeout} => 
      {7202, :medium, "Orchestration execution timed out"},
    {:orchestration, :execution, :execution_cancelled} => 
      {7203, :low, "Orchestration execution cancelled"},

    # Service Enhancement Errors (8000-8999)
    {:service, :lifecycle, :service_start_failed} => 
      {8001, :critical, "Service failed to start"},
    {:service, :lifecycle, :service_stop_failed} => 
      {8002, :high, "Service failed to stop gracefully"},
    {:service, :lifecycle, :service_crashed} => 
      {8003, :critical, "Service process crashed"},

    {:service, :health, :health_check_failed} => 
      {8101, :medium, "Service health check failed"},
    {:service, :health, :health_check_timeout} => 
      {8102, :medium, "Service health check timed out"},
    {:service, :health, :service_degraded} => 
      {8103, :medium, "Service operating in degraded mode"},

    {:service, :dependency, :dependency_unavailable} => 
      {8201, :high, "Required service dependency unavailable"},
    {:service, :dependency, :dependency_timeout} => 
      {8202, :medium, "Service dependency timeout"},
    {:service, :dependency, :circular_dependency} => 
      {8203, :critical, "Circular service dependency detected"},

    # Distributed System Errors (9000-9999)
    {:distributed, :network, :node_unreachable} => 
      {9001, :high, "Network node unreachable"},
    {:distributed, :network, :network_partition} => 
      {9002, :critical, "Network partition detected"},
    {:distributed, :network, :connection_lost} => 
      {9003, :medium, "Network connection lost"},

    {:distributed, :cluster, :cluster_split} => 
      {9101, :critical, "Cluster split brain detected"},
    {:distributed, :cluster, :node_join_failed} => 
      {9102, :high, "Node failed to join cluster"},
    {:distributed, :cluster, :node_leave_failed} => 
      {9103, :medium, "Node failed to leave cluster gracefully"},

    {:distributed, :state, :state_sync_failed} => 
      {9201, :high, "Distributed state synchronization failed"},
    {:distributed, :state, :state_corruption} => 
      {9202, :critical, "Distributed state corruption detected"},
    {:distributed, :state, :state_conflict} => 
      {9203, :medium, "Distributed state conflict"}
  }

  @type error_chain :: [Error.t()]
  @type error_correlation :: %{
    correlation_id: String.t(),
    causation_chain: error_chain(),
    related_errors: [Error.t()],
    distributed_context: distributed_error_context()
  }

  @type distributed_error_context :: %{
    originating_node: node(),
    affected_nodes: [node()],
    cluster_state: :healthy | :degraded | :partitioned,
    propagation_path: [node()]
  }

  @doc """
  Create an enhanced error with correlation and distribution context.
  """
  @spec new_enhanced(atom(), String.t() | nil, keyword()) :: Error.t()
  def new_enhanced(error_type, message \\ nil, opts \\ []) do
    # Check if it's a MABEAM-specific error type
    base_error = case get_mabeam_error_definition(error_type) do
      {code, severity, default_message} ->
        {category, subcategory} = categorize_mabeam_error(error_type)
        
        Error.new(
          code: code,
          error_type: error_type,
          message: message || default_message,
          severity: severity,
          category: category,
          subcategory: subcategory,
          context: Keyword.get(opts, :context, %{}),
          correlation_id: Keyword.get(opts, :correlation_id),
          stacktrace: Keyword.get(opts, :stacktrace),
          retry_strategy: determine_retry_strategy(error_type, severity)
        )
      
      nil ->
        # Fallback to basic Error.new for non-MABEAM errors
        Error.new(error_type, message, opts)
    end

    # Enhance with distributed context if provided
    case Keyword.get(opts, :distributed_context) do
      nil -> base_error
      distributed_ctx -> add_distributed_context(base_error, distributed_ctx)
    end
  end

  @doc """
  Create an error chain showing causation relationships.
  """
  @spec create_error_chain([Error.t()], String.t()) :: error_correlation()
  def create_error_chain(errors, correlation_id) when is_list(errors) do
    %{
      correlation_id: correlation_id,
      causation_chain: errors,
      related_errors: [],
      distributed_context: %{
        originating_node: Node.self(),
        affected_nodes: [Node.self()],
        cluster_state: :healthy,
        propagation_path: [Node.self()]
      }
    }
  end

  @doc """
  Add an error to an existing error chain.
  """
  @spec add_to_chain(error_correlation(), Error.t()) :: error_correlation()
  def add_to_chain(%{causation_chain: chain} = correlation, error) do
    %{correlation | causation_chain: chain ++ [error]}
  end

  @doc """
  Propagate an error across distributed nodes.
  """
  @spec propagate_error(Error.t(), [node()]) :: {:ok, error_correlation()} | {:error, term()}
  def propagate_error(error, target_nodes) do
    correlation_id = error.correlation_id || Foundation.Utils.generate_correlation_id()
    
    distributed_context = %{
      originating_node: Node.self(),
      affected_nodes: target_nodes,
      cluster_state: determine_cluster_state(),
      propagation_path: [Node.self()]
    }

    enhanced_error = add_distributed_context(error, distributed_context)
    
    correlation = %{
      correlation_id: correlation_id,
      causation_chain: [enhanced_error],
      related_errors: [],
      distributed_context: distributed_context
    }

    # Propagate to target nodes (placeholder for actual distribution)
    # In real implementation, this would use distributed Erlang messaging
    propagation_results = Enum.map(target_nodes, fn node ->
      {node, :propagated}  # Placeholder
    end)

    {:ok, %{correlation | propagation_results: propagation_results}}
  end

  @doc """
  Analyze error patterns for predictive failure detection.
  """
  @spec analyze_error_patterns([Error.t()]) :: %{
    pattern_type: atom(),
    confidence: float(),
    predicted_failures: [atom()],
    recommendations: [String.t()]
  }
  def analyze_error_patterns(errors) when is_list(errors) do
    # Group errors by type and analyze frequency
    error_frequencies = 
      errors
      |> Enum.group_by(& &1.error_type)
      |> Enum.map(fn {type, type_errors} -> {type, length(type_errors)} end)
      |> Enum.into(%{})

    # Analyze temporal patterns
    temporal_pattern = analyze_temporal_patterns(errors)
    
    # Determine pattern type and confidence
    {pattern_type, confidence} = determine_pattern_type(error_frequencies, temporal_pattern)
    
    # Predict potential failures
    predicted_failures = predict_failures(pattern_type, error_frequencies)
    
    # Generate recommendations
    recommendations = generate_recommendations(pattern_type, predicted_failures)

    %{
      pattern_type: pattern_type,
      confidence: confidence,
      predicted_failures: predicted_failures,
      recommendations: recommendations
    }
  end

  @doc """
  Get error recovery strategies based on error type and context.
  """
  @spec get_recovery_strategies(Error.t()) :: [recovery_strategy()]
  def get_recovery_strategies(%Error{} = error) do
    base_strategies = case error.category do
      :agent -> agent_recovery_strategies(error)
      :coordination -> coordination_recovery_strategies(error)
      :orchestration -> orchestration_recovery_strategies(error)
      :service -> service_recovery_strategies(error)
      :distributed -> distributed_recovery_strategies(error)
      _ -> general_recovery_strategies(error)
    end

    # Add context-specific strategies
    context_strategies = case error.context do
      %{resource_exhaustion: true} -> [:scale_resources, :load_balancing]
      %{network_partition: true} -> [:wait_for_heal, :manual_intervention]
      %{circular_dependency: true} -> [:restructure_dependencies, :break_cycle]
      _ -> []
    end

    base_strategies ++ context_strategies
  end

  ## Private Functions

  defp get_mabeam_error_definition(error_type) do
    # Find the error definition by searching for matching error_type
    case Enum.find(@mabeam_error_definitions, fn {key, _value} ->
           case key do
             {_category, _subcategory, ^error_type} -> true
             _ -> false
           end
         end) do
      {_key, definition} -> definition
      nil -> nil
    end
  end

  defp categorize_mabeam_error(error_type) do
    case Enum.find(@mabeam_error_definitions, fn {key, _value} ->
           case key do
             {_category, _subcategory, ^error_type} -> true
             _ -> false
           end
         end) do
      {{category, subcategory, _error_type}, _definition} -> {category, subcategory}
      nil -> {:unknown, :unknown}
    end
  end

  defp add_distributed_context(error, distributed_context) do
    enhanced_context = Map.merge(error.context, %{distributed: distributed_context})
    %{error | context: enhanced_context}
  end

  defp determine_cluster_state do
    # Placeholder - in real implementation, this would check actual cluster health
    case Node.list() do
      [] -> :healthy
      nodes -> 
        # Check if nodes are responsive
        responsive_nodes = Enum.filter(nodes, fn node -> 
          :net_adm.ping(node) == :pong
        end)
        
        if length(responsive_nodes) == length(nodes) do
          :healthy
        else
          :degraded
        end
    end
  end

  defp determine_retry_strategy(error_type, severity) do
    case {error_type, severity} do
      # Agent errors
      {:agent_start_failed, _} -> :exponential_backoff
      {:agent_crashed, _} -> :immediate
      {:agent_timeout, _} -> :fixed_delay
      {:agent_not_found, _} -> :no_retry
      
      # Coordination errors
      {:consensus_timeout, _} -> :exponential_backoff
      {:negotiation_deadlock, _} -> :no_retry
      {:auction_timeout, _} -> :fixed_delay
      {:market_failure, _} -> :exponential_backoff
      
      # Orchestration errors
      {:resource_exhausted, _} -> :exponential_backoff
      {:execution_timeout, _} -> :fixed_delay
      {:variable_conflict, _} -> :no_retry
      
      # Service errors
      {:service_crashed, _} -> :immediate
      {:health_check_failed, _} -> :fixed_delay
      {:dependency_unavailable, _} -> :exponential_backoff
      
      # Distributed errors
      {:node_unreachable, _} -> :exponential_backoff
      {:network_partition, _} -> :no_retry
      {:state_sync_failed, _} -> :fixed_delay
      
      # Default based on severity
      {_, :critical} -> :no_retry
      {_, :high} -> :immediate
      {_, :medium} -> :fixed_delay
      {_, :low} -> :exponential_backoff
    end
  end

  defp analyze_temporal_patterns(errors) do
    # Group errors by time windows (last hour, last day, etc.)
    now = System.system_time(:second)
    one_hour_ago = now - 3600
    one_day_ago = now - 86400

    recent_errors = Enum.filter(errors, fn error ->
      error_time = DateTime.to_unix(error.timestamp || DateTime.utc_now())
      error_time >= one_hour_ago
    end)

    daily_errors = Enum.filter(errors, fn error ->
      error_time = DateTime.to_unix(error.timestamp || DateTime.utc_now())
      error_time >= one_day_ago
    end)

    %{
      recent_count: length(recent_errors),
      daily_count: length(daily_errors),
      error_rate: length(recent_errors) / 60,  # errors per minute
      trending: if(length(recent_errors) > length(daily_errors) / 24, do: :increasing, else: :stable)
    }
  end

  defp determine_pattern_type(error_frequencies, temporal_pattern) do
    # Analyze the most common error types
    sorted_frequencies = Enum.sort_by(error_frequencies, fn {_type, count} -> count end, :desc)
    
    cond do
      temporal_pattern.trending == :increasing ->
        {:escalating_failure, 0.8}
      
      length(sorted_frequencies) > 0 ->
        {most_common_type, count} = hd(sorted_frequencies)
        total_errors = Enum.sum(Enum.map(sorted_frequencies, fn {_, c} -> c end))
        
        if count / total_errors > 0.7 do
          {:dominant_error_type, 0.9}
        else
          {:distributed_failure, 0.6}
        end
      
      true ->
        {:unknown_pattern, 0.1}
    end
  end

  defp predict_failures(pattern_type, error_frequencies) do
    case pattern_type do
      :escalating_failure ->
        # Look for error types that commonly lead to cascading failures
        cascading_types = [:service_crashed, :resource_exhausted, :network_partition]
        Enum.filter(cascading_types, fn type -> Map.has_key?(error_frequencies, type) end)
      
      :dominant_error_type ->
        # Find the dominant error and predict related failures
        {dominant_type, _} = Enum.max_by(error_frequencies, fn {_, count} -> count end)
        get_related_failure_types(dominant_type)
      
      :distributed_failure ->
        # Predict system-wide failures
        [:cluster_split, :state_corruption, :coordination_failure]
      
      _ ->
        []
    end
  end

  defp get_related_failure_types(error_type) do
    case error_type do
      :agent_crashed -> [:agent_start_failed, :orchestration_failure]
      :resource_exhausted -> [:execution_timeout, :service_degraded]
      :network_partition -> [:node_unreachable, :cluster_split]
      :consensus_failed -> [:coordination_failure, :negotiation_failed]
      _ -> []
    end
  end

  defp generate_recommendations(pattern_type, predicted_failures) do
    base_recommendations = case pattern_type do
      :escalating_failure ->
        [
          "Implement circuit breakers to prevent cascade failures",
          "Scale resources proactively",
          "Enable graceful degradation modes",
          "Review and strengthen error boundaries"
        ]
      
      :dominant_error_type ->
        [
          "Focus on resolving the dominant error type",
          "Implement specific monitoring for this error pattern",
          "Review system design for this failure mode",
          "Add automated recovery for this error type"
        ]
      
      :distributed_failure ->
        [
          "Review distributed system health",
          "Check network connectivity and partition tolerance",
          "Verify cluster state and node health",
          "Implement distributed system monitoring"
        ]
      
      _ ->
        [
          "Establish baseline error monitoring",
          "Implement comprehensive logging",
          "Review system architecture for failure modes"
        ]
    end

    failure_recommendations = Enum.flat_map(predicted_failures, fn failure ->
      case failure do
        :cluster_split -> ["Implement split-brain protection", "Review quorum settings"]
        :state_corruption -> ["Enable state validation", "Implement state recovery procedures"]
        :coordination_failure -> ["Review coordination timeouts", "Implement coordination fallbacks"]
        _ -> []
      end
    end)

    base_recommendations ++ failure_recommendations
  end

  # Recovery strategy definitions
  @type recovery_strategy :: 
    :restart_component |
    :scale_resources |
    :load_balancing |
    :circuit_breaker |
    :graceful_degradation |
    :manual_intervention |
    :wait_for_heal |
    :restructure_dependencies |
    :break_cycle |
    :rollback_state |
    :resync_cluster

  defp agent_recovery_strategies(error) do
    case error.error_type do
      :agent_start_failed -> [:restart_component, :check_resources, :review_config]
      :agent_crashed -> [:restart_component, :increase_monitoring, :review_code]
      :agent_timeout -> [:increase_timeouts, :scale_resources, :optimize_processing]
      :agent_not_found -> [:restart_registry, :verify_registration, :manual_intervention]
      _ -> [:restart_component, :manual_intervention]
    end
  end

  defp coordination_recovery_strategies(error) do
    case error.error_type do
      :consensus_failed -> [:retry_consensus, :reduce_participants, :manual_decision]
      :negotiation_deadlock -> [:restart_negotiation, :change_strategy, :manual_arbitration]
      :auction_timeout -> [:extend_timeout, :restart_auction, :direct_allocation]
      :market_failure -> [:reset_market, :manual_pricing, :alternative_mechanism]
      _ -> [:restart_coordination, :manual_intervention]
    end
  end

  defp orchestration_recovery_strategies(error) do
    case error.error_type do
      :resource_exhausted -> [:scale_resources, :load_balancing, :prioritize_workload]
      :execution_timeout -> [:increase_timeouts, :optimize_execution, :parallel_processing]
      :variable_conflict -> [:resolve_conflicts, :priority_ordering, :manual_intervention]
      _ -> [:restart_orchestration, :manual_intervention]
    end
  end

  defp service_recovery_strategies(error) do
    case error.error_type do
      :service_crashed -> [:restart_component, :increase_monitoring, :review_logs]
      :health_check_failed -> [:restart_service, :review_health_logic, :manual_check]
      :dependency_unavailable -> [:wait_for_heal, :use_fallback, :manual_intervention]
      _ -> [:restart_component, :manual_intervention]
    end
  end

  defp distributed_recovery_strategies(error) do
    case error.error_type do
      :node_unreachable -> [:wait_for_heal, :remove_node, :check_network]
      :network_partition -> [:wait_for_heal, :manual_intervention, :split_brain_resolution]
      :state_sync_failed -> [:resync_cluster, :rollback_state, :manual_sync]
      _ -> [:wait_for_heal, :manual_intervention]
    end
  end

  defp general_recovery_strategies(_error) do
    [:restart_component, :review_logs, :manual_intervention]
  end
end
