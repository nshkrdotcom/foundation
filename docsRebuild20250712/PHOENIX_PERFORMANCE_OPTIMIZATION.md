# Phoenix: Performance Optimization and Scaling
**Date**: 2025-07-12  
**Version**: 1.0  
**Series**: Distributed Agent System - Part 5 (Performance)

## Executive Summary

This document provides comprehensive specifications for performance optimization and horizontal scaling in the Phoenix distributed agent system. Drawing from high-performance distributed systems research, BEAM performance engineering, and production scaling patterns, Phoenix implements **adaptive performance optimization** that automatically adjusts system behavior based on real-time performance metrics and workload characteristics.

**Key Innovation**: Phoenix employs **predictive performance scaling** where the system uses machine learning techniques to anticipate performance bottlenecks and proactively adjust resource allocation, load balancing, and system configuration.

## Table of Contents

1. [Performance Architecture Overview](#performance-architecture-overview)
2. [Adaptive Load Balancing](#adaptive-load-balancing)
3. [Resource-Aware Agent Placement](#resource-aware-agent-placement)
4. [Performance Monitoring and Metrics](#performance-monitoring-and-metrics)
5. [Horizontal Scaling Automation](#horizontal-scaling-automation)
6. [Memory and CPU Optimization](#memory-and-cpu-optimization)
7. [Network Performance Optimization](#network-performance-optimization)
8. [Predictive Performance Management](#predictive-performance-management)

---

## Performance Architecture Overview

### Multi-Layered Performance System

```elixir
defmodule Phoenix.Performance do
  @moduledoc """
  Central performance management system coordinating all optimization strategies.
  
  Performance Layers:
  1. **Real-time Monitoring**: Sub-second performance metrics collection
  2. **Adaptive Optimization**: Dynamic system tuning based on workload
  3. **Predictive Scaling**: ML-based capacity planning and resource allocation
  4. **Resource Management**: Intelligent resource scheduling and allocation
  5. **Network Optimization**: Transport and protocol optimization
  """
  
  use GenServer
  
  defstruct [
    :node_id,
    :performance_targets,
    :current_metrics,
    :optimization_strategies,
    :scaling_policies,
    :resource_allocations,
    :prediction_models
  ]
  
  @performance_targets %{
    agent_response_time_p95: 50,      # 50ms 95th percentile
    message_throughput: 10_000,       # 10k messages/second
    cluster_availability: 0.999,      # 99.9% availability
    resource_utilization: 0.75,       # 75% max resource utilization
    scaling_response_time: 30         # 30 seconds to scale
  }
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    state = %__MODULE__{
      node_id: Keyword.get(opts, :node_id, node()),
      performance_targets: Map.merge(@performance_targets, Keyword.get(opts, :targets, %{})),
      current_metrics: %{},
      optimization_strategies: initialize_optimization_strategies(),
      scaling_policies: initialize_scaling_policies(),
      resource_allocations: %{},
      prediction_models: initialize_prediction_models()
    }
    
    # Start performance monitoring
    schedule_performance_collection()
    schedule_optimization_cycle()
    
    {:ok, state}
  end
  
  @doc """
  Get current performance status and recommendations.
  """
  def performance_status() do
    GenServer.call(__MODULE__, :performance_status)
  end
  
  @doc """
  Trigger immediate performance optimization.
  """
  def optimize_now() do
    GenServer.cast(__MODULE__, :optimize_now)
  end
  
  @doc """
  Update performance targets.
  """
  def update_targets(new_targets) do
    GenServer.call(__MODULE__, {:update_targets, new_targets})
  end
  
  def handle_call(:performance_status, _from, state) do
    status = %{
      current_metrics: state.current_metrics,
      target_compliance: calculate_target_compliance(state),
      active_optimizations: get_active_optimizations(state),
      scaling_recommendations: get_scaling_recommendations(state),
      performance_trend: get_performance_trend(state)
    }
    
    {:reply, status, state}
  end
  
  def handle_call({:update_targets, new_targets}, _from, state) do
    updated_targets = Map.merge(state.performance_targets, new_targets)
    {:reply, :ok, %{state | performance_targets: updated_targets}}
  end
  
  def handle_cast(:optimize_now, state) do
    new_state = execute_optimization_cycle(state)
    {:noreply, new_state}
  end
  
  def handle_info(:collect_metrics, state) do
    # Collect current performance metrics
    new_metrics = collect_performance_metrics()
    
    # Update prediction models with new data
    updated_models = update_prediction_models(state.prediction_models, new_metrics)
    
    new_state = %{state | 
      current_metrics: new_metrics,
      prediction_models: updated_models
    }
    
    schedule_performance_collection()
    {:noreply, new_state}
  end
  
  def handle_info(:optimization_cycle, state) do
    # Execute optimization cycle
    new_state = execute_optimization_cycle(state)
    
    schedule_optimization_cycle()
    {:noreply, new_state}
  end
  
  defp execute_optimization_cycle(state) do
    # Analyze current performance against targets
    performance_analysis = analyze_performance(state.current_metrics, state.performance_targets)
    
    # Generate optimization recommendations
    optimizations = generate_optimizations(performance_analysis, state)
    
    # Execute high-priority optimizations
    execute_optimizations(optimizations)
    
    # Update resource allocations
    new_allocations = update_resource_allocations(state.resource_allocations, optimizations)
    
    %{state | resource_allocations: new_allocations}
  end
  
  defp analyze_performance(current_metrics, targets) do
    Enum.map(targets, fn {metric, target_value} ->
      current_value = Map.get(current_metrics, metric, 0)
      compliance = calculate_compliance(current_value, target_value, metric)
      
      {metric, %{
        current: current_value,
        target: target_value,
        compliance: compliance,
        deviation: calculate_deviation(current_value, target_value, metric)
      }}
    end)
    |> Enum.into(%{})
  end
  
  defp generate_optimizations(analysis, state) do
    # Generate optimization strategies based on performance analysis
    optimizations = []
    
    # Check each metric for optimization opportunities
    optimizations = if analysis[:agent_response_time_p95].compliance < 0.9 do
      [generate_latency_optimization(analysis, state) | optimizations]
    else
      optimizations
    end
    
    optimizations = if analysis[:message_throughput].compliance < 0.8 do
      [generate_throughput_optimization(analysis, state) | optimizations]
    else
      optimizations
    end
    
    optimizations = if analysis[:resource_utilization].current > 0.8 do
      [generate_scaling_optimization(analysis, state) | optimizations]
    else
      optimizations
    end
    
    # Sort by priority and impact
    Enum.sort_by(optimizations, fn opt -> 
      {opt.priority, opt.estimated_impact} 
    end, :desc)
  end
  
  defp generate_latency_optimization(analysis, state) do
    %{
      type: :latency_optimization,
      priority: :high,
      estimated_impact: 0.8,
      actions: [
        {:enable_message_batching, %{batch_size: 10}},
        {:optimize_agent_placement, %{strategy: :latency_aware}},
        {:tune_network_buffers, %{buffer_size: 64_000}}
      ],
      target_metric: :agent_response_time_p95,
      expected_improvement: 0.3
    }
  end
  
  defp generate_throughput_optimization(analysis, state) do
    %{
      type: :throughput_optimization,
      priority: :high,
      estimated_impact: 0.9,
      actions: [
        {:increase_connection_pools, %{pool_size: 20}},
        {:enable_compression, %{algorithm: :lz4}},
        {:optimize_message_routing, %{strategy: :direct_routing}}
      ],
      target_metric: :message_throughput,
      expected_improvement: 0.4
    }
  end
  
  defp generate_scaling_optimization(analysis, state) do
    %{
      type: :scaling_optimization,
      priority: :medium,
      estimated_impact: 1.0,
      actions: [
        {:horizontal_scale_out, %{additional_nodes: 2}},
        {:rebalance_agents, %{strategy: :even_distribution}}
      ],
      target_metric: :resource_utilization,
      expected_improvement: 0.5
    }
  end
  
  defp execute_optimizations(optimizations) do
    Enum.each(optimizations, fn optimization ->
      case optimization.priority do
        :high -> execute_optimization_immediately(optimization)
        :medium -> schedule_optimization(optimization, delay: 5_000)
        :low -> schedule_optimization(optimization, delay: 30_000)
      end
    end)
  end
  
  defp execute_optimization_immediately(optimization) do
    Enum.each(optimization.actions, &execute_optimization_action/1)
  end
  
  defp execute_optimization_action({:enable_message_batching, config}) do
    Phoenix.MessageBatching.enable(config)
  end
  
  defp execute_optimization_action({:optimize_agent_placement, config}) do
    Phoenix.AgentPlacement.optimize(config)
  end
  
  defp execute_optimization_action({:tune_network_buffers, config}) do
    Phoenix.NetworkTuning.adjust_buffers(config)
  end
  
  defp execute_optimization_action({:increase_connection_pools, config}) do
    Phoenix.ConnectionPooling.resize_pools(config)
  end
  
  defp execute_optimization_action({:enable_compression, config}) do
    Phoenix.MessageCompression.enable(config)
  end
  
  defp execute_optimization_action({:horizontal_scale_out, config}) do
    Phoenix.AutoScaling.scale_out(config)
  end
  
  defp execute_optimization_action({:rebalance_agents, config}) do
    Phoenix.LoadBalancing.rebalance_agents(config)
  end
  
  # Helper functions and initialization
  defp collect_performance_metrics() do
    %{
      agent_response_time_p95: Phoenix.Metrics.get_percentile(:agent_response_time, 95),
      message_throughput: Phoenix.Metrics.get_rate(:message_throughput),
      cluster_availability: Phoenix.Metrics.get_availability(),
      resource_utilization: Phoenix.Metrics.get_resource_utilization(),
      scaling_response_time: Phoenix.Metrics.get_scaling_response_time()
    }
  end
  
  defp schedule_performance_collection() do
    Process.send_after(self(), :collect_metrics, 1_000)  # Every second
  end
  
  defp schedule_optimization_cycle() do
    Process.send_after(self(), :optimization_cycle, 10_000)  # Every 10 seconds
  end
  
  defp initialize_optimization_strategies() do
    %{
      latency: Phoenix.LatencyOptimization,
      throughput: Phoenix.ThroughputOptimization,
      resource: Phoenix.ResourceOptimization,
      network: Phoenix.NetworkOptimization
    }
  end
  
  defp initialize_scaling_policies() do
    %{
      cpu_threshold: 0.8,
      memory_threshold: 0.85,
      network_threshold: 0.9,
      scale_out_cooldown: 300,    # 5 minutes
      scale_in_cooldown: 600      # 10 minutes
    }
  end
  
  defp initialize_prediction_models() do
    %{
      workload_prediction: Phoenix.ML.WorkloadPredictor.new(),
      resource_prediction: Phoenix.ML.ResourcePredictor.new(),
      scaling_prediction: Phoenix.ML.ScalingPredictor.new()
    }
  end
  
  defp calculate_compliance(current, target, metric) do
    # Calculate how well current performance meets target
    case metric do
      metric when metric in [:agent_response_time_p95, :scaling_response_time] ->
        # Lower is better
        if current <= target, do: 1.0, else: target / current
        
      metric when metric in [:message_throughput, :cluster_availability] ->
        # Higher is better
        if current >= target, do: 1.0, else: current / target
        
      :resource_utilization ->
        # Target utilization (not too high, not too low)
        optimal = target
        if current <= optimal, do: current / optimal, else: (2 * optimal - current) / optimal
    end
  end
  
  defp calculate_deviation(current, target, metric) do
    case metric do
      metric when metric in [:agent_response_time_p95, :scaling_response_time] ->
        max(0, current - target) / target
        
      metric when metric in [:message_throughput, :cluster_availability] ->
        max(0, target - current) / target
        
      :resource_utilization ->
        abs(current - target) / target
    end
  end
  
  defp calculate_target_compliance(state) do
    analysis = analyze_performance(state.current_metrics, state.performance_targets)
    
    compliances = Enum.map(analysis, fn {_metric, data} -> data.compliance end)
    
    if Enum.empty?(compliances) do
      0.0
    else
      Enum.sum(compliances) / length(compliances)
    end
  end
  
  defp get_active_optimizations(_state) do
    # Return currently active optimizations
    []
  end
  
  defp get_scaling_recommendations(state) do
    # Generate scaling recommendations based on predictions
    predictions = predict_future_load(state.prediction_models)
    
    case predictions do
      {:scale_out, confidence} when confidence > 0.8 ->
        %{action: :scale_out, confidence: confidence, reason: :predicted_load_increase}
        
      {:scale_in, confidence} when confidence > 0.8 ->
        %{action: :scale_in, confidence: confidence, reason: :predicted_load_decrease}
        
      _ ->
        %{action: :no_action, confidence: 0.0, reason: :stable_load}
    end
  end
  
  defp get_performance_trend(state) do
    # Analyze performance trend over time
    recent_metrics = get_recent_metrics_history()
    
    if length(recent_metrics) >= 2 do
      latest = hd(recent_metrics)
      previous = Enum.at(recent_metrics, 1)
      
      trend = calculate_trend(latest, previous)
      %{direction: trend, confidence: 0.8}
    else
      %{direction: :stable, confidence: 0.0}
    end
  end
  
  defp predict_future_load(models) do
    # Use prediction models to forecast load
    {:no_action, 0.5}  # Simplified implementation
  end
  
  defp get_recent_metrics_history() do
    # Get recent metrics history for trend analysis
    []  # Simplified implementation
  end
  
  defp calculate_trend(latest, previous) do
    # Calculate trend direction
    :stable  # Simplified implementation
  end
  
  defp update_prediction_models(models, new_metrics) do
    # Update ML models with new performance data
    models  # Simplified implementation
  end
  
  defp update_resource_allocations(allocations, optimizations) do
    # Update resource allocations based on optimizations
    allocations  # Simplified implementation
  end
  
  defp schedule_optimization(optimization, opts) do
    delay = Keyword.get(opts, :delay, 0)
    
    Process.send_after(self(), {:execute_optimization, optimization}, delay)
  end
end
```

---

## Adaptive Load Balancing

### Intelligent Load Balancing Engine

```elixir
defmodule Phoenix.LoadBalancing do
  @moduledoc """
  Adaptive load balancing system that dynamically adjusts routing strategies
  based on real-time performance metrics and workload characteristics.
  
  Balancing Strategies:
  1. **Round Robin**: Simple round-robin with health checks
  2. **Weighted Round Robin**: Weight-based distribution
  3. **Least Connections**: Route to least loaded node
  4. **Response Time**: Route to fastest responding node
  5. **Resource Aware**: Consider CPU, memory, network load
  6. **Predictive**: ML-based routing predictions
  """
  
  use GenServer
  
  defstruct [
    :strategy,
    :node_pool,
    :node_metrics,
    :routing_weights,
    :performance_history,
    :load_predictor
  ]
  
  @strategies [:round_robin, :weighted_round_robin, :least_connections, 
               :response_time, :resource_aware, :predictive]
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    strategy = Keyword.get(opts, :strategy, :resource_aware)
    initial_nodes = Keyword.get(opts, :nodes, [node()])
    
    state = %__MODULE__{
      strategy: strategy,
      node_pool: initialize_node_pool(initial_nodes),
      node_metrics: %{},
      routing_weights: %{},
      performance_history: %{},
      load_predictor: Phoenix.ML.LoadPredictor.new()
    }
    
    # Start metrics collection
    schedule_metrics_collection()
    schedule_weight_adjustment()
    
    {:ok, state}
  end
  
  @doc """
  Route request to optimal node based on current strategy.
  """
  def route_request(request_spec) do
    GenServer.call(__MODULE__, {:route_request, request_spec})
  end
  
  @doc """
  Add node to load balancing pool.
  """
  def add_node(node, initial_weight \\ 1.0) do
    GenServer.call(__MODULE__, {:add_node, node, initial_weight})
  end
  
  @doc """
  Remove node from load balancing pool.
  """
  def remove_node(node) do
    GenServer.call(__MODULE__, {:remove_node, node})
  end
  
  @doc """
  Change load balancing strategy.
  """
  def set_strategy(new_strategy) when new_strategy in @strategies do
    GenServer.call(__MODULE__, {:set_strategy, new_strategy})
  end
  
  @doc """
  Get current load balancing statistics.
  """
  def get_stats() do
    GenServer.call(__MODULE__, :get_stats)
  end
  
  def handle_call({:route_request, request_spec}, _from, state) do
    # Select optimal node based on current strategy
    case select_node(request_spec, state) do
      {:ok, selected_node} ->
        # Update routing statistics
        new_state = update_routing_stats(state, selected_node, request_spec)
        {:reply, {:ok, selected_node}, new_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call({:add_node, node, weight}, _from, state) do
    new_pool = Map.put(state.node_pool, node, %{
      status: :healthy,
      weight: weight,
      connections: 0,
      last_request: nil
    })
    
    new_weights = Map.put(state.routing_weights, node, weight)
    
    new_state = %{state | 
      node_pool: new_pool,
      routing_weights: new_weights
    }
    
    {:reply, :ok, new_state}
  end
  
  def handle_call({:remove_node, node}, _from, state) do
    new_pool = Map.delete(state.node_pool, node)
    new_weights = Map.delete(state.routing_weights, node)
    new_metrics = Map.delete(state.node_metrics, node)
    
    new_state = %{state | 
      node_pool: new_pool,
      routing_weights: new_weights,
      node_metrics: new_metrics
    }
    
    {:reply, :ok, new_state}
  end
  
  def handle_call({:set_strategy, new_strategy}, _from, state) do
    Logger.info("Load balancing strategy changed from #{state.strategy} to #{new_strategy}")
    
    {:reply, :ok, %{state | strategy: new_strategy}}
  end
  
  def handle_call(:get_stats, _from, state) do
    stats = %{
      strategy: state.strategy,
      active_nodes: map_size(state.node_pool),
      node_pool: state.node_pool,
      routing_weights: state.routing_weights,
      recent_metrics: get_recent_metrics(state.node_metrics)
    }
    
    {:reply, stats, state}
  end
  
  def handle_info(:collect_metrics, state) do
    # Collect performance metrics from all nodes
    new_metrics = collect_node_metrics(state.node_pool)
    
    # Update performance history
    new_history = update_performance_history(state.performance_history, new_metrics)
    
    new_state = %{state | 
      node_metrics: new_metrics,
      performance_history: new_history
    }
    
    schedule_metrics_collection()
    {:noreply, new_state}
  end
  
  def handle_info(:adjust_weights, state) do
    # Adjust routing weights based on performance
    new_weights = calculate_adaptive_weights(state)
    
    new_state = %{state | routing_weights: new_weights}
    
    schedule_weight_adjustment()
    {:noreply, new_state}
  end
  
  defp select_node(request_spec, state) do
    healthy_nodes = get_healthy_nodes(state.node_pool)
    
    if Enum.empty?(healthy_nodes) do
      {:error, :no_healthy_nodes}
    else
      selected = case state.strategy do
        :round_robin -> 
          round_robin_select(healthy_nodes, state)
        :weighted_round_robin -> 
          weighted_round_robin_select(healthy_nodes, state)
        :least_connections -> 
          least_connections_select(healthy_nodes, state)
        :response_time -> 
          response_time_select(healthy_nodes, state)
        :resource_aware -> 
          resource_aware_select(healthy_nodes, state)
        :predictive -> 
          predictive_select(healthy_nodes, request_spec, state)
      end
      
      {:ok, selected}
    end
  end
  
  defp round_robin_select(nodes, _state) do
    # Simple round-robin selection
    node_index = :persistent_term.get({__MODULE__, :round_robin_index}, 0)
    selected_node = Enum.at(nodes, rem(node_index, length(nodes)))
    
    :persistent_term.put({__MODULE__, :round_robin_index}, node_index + 1)
    selected_node
  end
  
  defp weighted_round_robin_select(nodes, state) do
    # Weighted round-robin based on routing weights
    total_weight = nodes
    |> Enum.map(fn node -> Map.get(state.routing_weights, node, 1.0) end)
    |> Enum.sum()
    
    random_value = :rand.uniform() * total_weight
    
    select_weighted_node(nodes, state.routing_weights, random_value, 0.0)
  end
  
  defp select_weighted_node([node | rest], weights, target, accumulator) do
    weight = Map.get(weights, node, 1.0)
    new_accumulator = accumulator + weight
    
    if target <= new_accumulator do
      node
    else
      select_weighted_node(rest, weights, target, new_accumulator)
    end
  end
  
  defp select_weighted_node([], _weights, _target, _accumulator) do
    # Fallback to first node if something goes wrong
    hd(Map.keys(%{}))
  end
  
  defp least_connections_select(nodes, state) do
    # Select node with least active connections
    nodes
    |> Enum.min_by(fn node ->
      node_info = Map.get(state.node_pool, node, %{})
      Map.get(node_info, :connections, 0)
    end)
  end
  
  defp response_time_select(nodes, state) do
    # Select node with best response time
    nodes
    |> Enum.min_by(fn node ->
      metrics = Map.get(state.node_metrics, node, %{})
      Map.get(metrics, :response_time_avg, 999_999)
    end)
  end
  
  defp resource_aware_select(nodes, state) do
    # Select node based on comprehensive resource utilization
    nodes
    |> Enum.min_by(fn node ->
      calculate_resource_score(node, state.node_metrics)
    end)
  end
  
  defp predictive_select(nodes, request_spec, state) do
    # Use ML model to predict best node for request
    predictions = Enum.map(nodes, fn node ->
      score = Phoenix.ML.LoadPredictor.predict_score(
        state.load_predictor, 
        node, 
        request_spec
      )
      {node, score}
    end)
    
    {best_node, _score} = Enum.max_by(predictions, fn {_node, score} -> score end)
    best_node
  end
  
  defp calculate_resource_score(node, metrics) do
    node_metrics = Map.get(metrics, node, %{})
    
    # Composite score considering multiple factors
    cpu_score = Map.get(node_metrics, :cpu_utilization, 0.0)
    memory_score = Map.get(node_metrics, :memory_utilization, 0.0)
    network_score = Map.get(node_metrics, :network_utilization, 0.0)
    response_time_score = normalize_response_time(Map.get(node_metrics, :response_time_avg, 0))
    
    # Lower score is better (represents load)
    cpu_score * 0.3 + memory_score * 0.3 + network_score * 0.2 + response_time_score * 0.2
  end
  
  defp normalize_response_time(response_time) do
    # Normalize response time to 0-1 scale (lower is better)
    max_acceptable_time = 1000  # 1 second
    min(response_time / max_acceptable_time, 1.0)
  end
  
  defp calculate_adaptive_weights(state) do
    # Calculate new weights based on recent performance
    Map.keys(state.node_pool)
    |> Enum.map(fn node ->
      performance_score = calculate_performance_score(node, state)
      weight = performance_to_weight(performance_score)
      {node, weight}
    end)
    |> Enum.into(%{})
  end
  
  defp calculate_performance_score(node, state) do
    # Calculate performance score (higher is better)
    node_metrics = Map.get(state.node_metrics, node, %{})
    
    # Factors contributing to performance score
    availability = Map.get(node_metrics, :availability, 0.0)
    response_time = Map.get(node_metrics, :response_time_avg, 999_999)
    error_rate = Map.get(node_metrics, :error_rate, 1.0)
    throughput = Map.get(node_metrics, :throughput, 0.0)
    
    # Combine factors (higher score = better performance)
    availability_score = availability
    response_time_score = 1000 / max(response_time, 1)  # Inverse of response time
    error_rate_score = 1.0 - error_rate
    throughput_score = min(throughput / 1000, 1.0)  # Normalize throughput
    
    (availability_score + response_time_score + error_rate_score + throughput_score) / 4
  end
  
  defp performance_to_weight(performance_score) do
    # Convert performance score to routing weight
    # Performance score should be 0-1, weight should be 0.1-2.0
    max(0.1, min(2.0, performance_score * 2.0))
  end
  
  defp get_healthy_nodes(node_pool) do
    node_pool
    |> Enum.filter(fn {_node, info} -> info.status == :healthy end)
    |> Enum.map(fn {node, _info} -> node end)
  end
  
  defp collect_node_metrics(node_pool) do
    # Collect metrics from all nodes in parallel
    collection_tasks = Map.keys(node_pool)
    |> Enum.map(fn node ->
      Task.async(fn ->
        case collect_single_node_metrics(node) do
          {:ok, metrics} -> {node, metrics}
          {:error, _reason} -> {node, %{status: :unhealthy}}
        end
      end)
    end)
    
    # Wait for all collections with timeout
    Task.await_many(collection_tasks, 5_000)
    |> Enum.into(%{})
  end
  
  defp collect_single_node_metrics(node) do
    # Collect metrics from a single node
    try do
      metrics = case :rpc.call(node, Phoenix.Metrics, :get_node_metrics, [], 3_000) do
        {:badrpc, _reason} ->
          %{status: :unhealthy}
        node_metrics ->
          Map.put(node_metrics, :status, :healthy)
      end
      
      {:ok, metrics}
    catch
      _, _ -> {:error, :collection_failed}
    end
  end
  
  defp update_routing_stats(state, selected_node, _request_spec) do
    # Update connection count for selected node
    current_info = Map.get(state.node_pool, selected_node, %{})
    updated_info = %{current_info | 
      connections: Map.get(current_info, :connections, 0) + 1,
      last_request: DateTime.utc_now()
    }
    
    new_pool = Map.put(state.node_pool, selected_node, updated_info)
    
    %{state | node_pool: new_pool}
  end
  
  defp initialize_node_pool(nodes) do
    Enum.map(nodes, fn node ->
      {node, %{
        status: :healthy,
        weight: 1.0,
        connections: 0,
        last_request: nil
      }}
    end)
    |> Enum.into(%{})
  end
  
  defp schedule_metrics_collection() do
    Process.send_after(self(), :collect_metrics, 5_000)  # Every 5 seconds
  end
  
  defp schedule_weight_adjustment() do
    Process.send_after(self(), :adjust_weights, 30_000)  # Every 30 seconds
  end
  
  defp get_recent_metrics(node_metrics) do
    # Return recent metrics summary
    Map.new(node_metrics, fn {node, metrics} ->
      {node, %{
        cpu: Map.get(metrics, :cpu_utilization, 0.0),
        memory: Map.get(metrics, :memory_utilization, 0.0),
        response_time: Map.get(metrics, :response_time_avg, 0.0)
      }}
    end)
  end
  
  defp update_performance_history(history, new_metrics) do
    # Update performance history for trend analysis
    timestamp = DateTime.utc_now()
    
    # Add new metrics with timestamp
    updated_history = Map.put(history, timestamp, new_metrics)
    
    # Keep only last 100 entries
    updated_history
    |> Enum.sort_by(fn {timestamp, _} -> timestamp end, {:desc, DateTime})
    |> Enum.take(100)
    |> Enum.into(%{})
  end
end
```

---

## Resource-Aware Agent Placement

### Intelligent Agent Placement Engine

```elixir
defmodule Phoenix.AgentPlacement do
  @moduledoc """
  Resource-aware agent placement system that optimally distributes agents
  across the cluster based on resource requirements, constraints, and performance objectives.
  
  Placement Strategies:
  1. **Resource Matching**: Match agent requirements to node capabilities
  2. **Affinity Rules**: Co-locate or separate specific agent types
  3. **Load Balancing**: Distribute load evenly across nodes
  4. **Fault Tolerance**: Ensure redundancy and failover capabilities
  5. **Performance Optimization**: Minimize latency and maximize throughput
  """
  
  use GenServer
  
  defstruct [
    :cluster_topology,
    :node_resources,
    :agent_registry,
    :placement_policies,
    :optimization_objectives,
    :constraint_solver
  ]
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    state = %__MODULE__{
      cluster_topology: initialize_cluster_topology(),
      node_resources: %{},
      agent_registry: %{},
      placement_policies: load_placement_policies(opts),
      optimization_objectives: initialize_objectives(),
      constraint_solver: Phoenix.ConstraintSolver.new()
    }
    
    # Start resource monitoring
    schedule_resource_monitoring()
    
    {:ok, state}
  end
  
  @doc """
  Find optimal placement for agent based on requirements and constraints.
  """
  def find_placement(agent_spec) do
    GenServer.call(__MODULE__, {:find_placement, agent_spec})
  end
  
  @doc """
  Place agent on specified node with verification.
  """
  def place_agent(agent_id, node, agent_spec) do
    GenServer.call(__MODULE__, {:place_agent, agent_id, node, agent_spec})
  end
  
  @doc """
  Migrate agent to different node.
  """
  def migrate_agent(agent_id, target_node, migration_options \\ []) do
    GenServer.call(__MODULE__, {:migrate_agent, agent_id, target_node, migration_options})
  end
  
  @doc """
  Rebalance agents across cluster for optimal distribution.
  """
  def rebalance_cluster(rebalance_options \\ []) do
    GenServer.call(__MODULE__, {:rebalance_cluster, rebalance_options})
  end
  
  @doc """
  Get current placement statistics and recommendations.
  """
  def placement_stats() do
    GenServer.call(__MODULE__, :placement_stats)
  end
  
  def handle_call({:find_placement, agent_spec}, _from, state) do
    # Find optimal node for agent placement
    case find_optimal_node(agent_spec, state) do
      {:ok, selected_node, placement_score} ->
        {:reply, {:ok, selected_node, placement_score}, state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call({:place_agent, agent_id, node, agent_spec}, _from, state) do
    # Verify placement is valid and reserve resources
    case validate_placement(agent_spec, node, state) do
      {:ok, resource_reservation} ->
        # Reserve resources on target node
        new_node_resources = reserve_resources(state.node_resources, node, resource_reservation)
        
        # Register agent placement
        new_agent_registry = Map.put(state.agent_registry, agent_id, %{
          node: node,
          spec: agent_spec,
          placed_at: DateTime.utc_now(),
          resources: resource_reservation
        })
        
        new_state = %{state | 
          node_resources: new_node_resources,
          agent_registry: new_agent_registry
        }
        
        {:reply, {:ok, resource_reservation}, new_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call({:migrate_agent, agent_id, target_node, options}, _from, state) do
    case Map.get(state.agent_registry, agent_id) do
      nil ->
        {:reply, {:error, :agent_not_found}, state}
        
      agent_info ->
        case execute_migration(agent_id, agent_info, target_node, options, state) do
          {:ok, new_placement} ->
            # Update agent registry
            updated_info = %{agent_info | 
              node: target_node,
              placed_at: DateTime.utc_now(),
              migration_history: [agent_info.node | Map.get(agent_info, :migration_history, [])]
            }
            
            new_registry = Map.put(state.agent_registry, agent_id, updated_info)
            
            {:reply, {:ok, new_placement}, %{state | agent_registry: new_registry}}
            
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end
  
  def handle_call({:rebalance_cluster, options}, _from, state) do
    # Analyze current distribution and generate rebalancing plan
    rebalancing_plan = generate_rebalancing_plan(state, options)
    
    case execute_rebalancing_plan(rebalancing_plan, state) do
      {:ok, new_state} ->
        {:reply, {:ok, rebalancing_plan}, new_state}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call(:placement_stats, _from, state) do
    stats = %{
      total_agents: map_size(state.agent_registry),
      nodes_in_use: count_nodes_in_use(state.agent_registry),
      resource_utilization: calculate_resource_utilization(state.node_resources),
      placement_efficiency: calculate_placement_efficiency(state),
      constraint_violations: check_constraint_violations(state)
    }
    
    {:reply, stats, state}
  end
  
  def handle_info(:monitor_resources, state) do
    # Update node resource information
    new_resources = collect_cluster_resources()
    
    new_state = %{state | node_resources: new_resources}
    
    schedule_resource_monitoring()
    {:noreply, new_state}
  end
  
  defp find_optimal_node(agent_spec, state) do
    # Get candidate nodes that meet basic requirements
    candidate_nodes = filter_candidate_nodes(agent_spec, state)
    
    if Enum.empty?(candidate_nodes) do
      {:error, :no_suitable_nodes}
    else
      # Score each candidate node
      scored_candidates = Enum.map(candidate_nodes, fn node ->
        score = calculate_placement_score(agent_spec, node, state)
        {node, score}
      end)
      
      # Select node with highest score
      {best_node, best_score} = Enum.max_by(scored_candidates, fn {_node, score} -> score end)
      
      {:ok, best_node, best_score}
    end
  end
  
  defp filter_candidate_nodes(agent_spec, state) do
    # Filter nodes based on hard constraints
    Map.keys(state.node_resources)
    |> Enum.filter(fn node ->
      meets_resource_requirements?(agent_spec, node, state) and
      satisfies_placement_constraints?(agent_spec, node, state) and
      node_healthy?(node)
    end)
  end
  
  defp meets_resource_requirements?(agent_spec, node, state) do
    # Check if node has sufficient resources
    required_resources = Map.get(agent_spec, :resources, %{})
    available_resources = get_available_resources(node, state.node_resources)
    
    Enum.all?(required_resources, fn {resource_type, required_amount} ->
      available_amount = Map.get(available_resources, resource_type, 0)
      available_amount >= required_amount
    end)
  end
  
  defp satisfies_placement_constraints?(agent_spec, node, state) do
    # Check placement constraints (affinity, anti-affinity, etc.)
    constraints = Map.get(agent_spec, :placement_constraints, [])
    
    Enum.all?(constraints, fn constraint ->
      evaluate_constraint(constraint, agent_spec, node, state)
    end)
  end
  
  defp evaluate_constraint({:affinity, target_agents}, agent_spec, node, state) do
    # Agent should be placed on same node as target agents
    target_nodes = get_agent_nodes(target_agents, state.agent_registry)
    node in target_nodes
  end
  
  defp evaluate_constraint({:anti_affinity, avoid_agents}, agent_spec, node, state) do
    # Agent should NOT be placed on same node as avoid agents
    avoid_nodes = get_agent_nodes(avoid_agents, state.agent_registry)
    node not in avoid_nodes
  end
  
  defp evaluate_constraint({:node_selector, selector}, agent_spec, node, state) do
    # Agent should only be placed on nodes matching selector
    evaluate_node_selector(selector, node, state)
  end
  
  defp evaluate_constraint({:resource_ratio, ratios}, agent_spec, node, state) do
    # Node resource utilization should not exceed specified ratios
    utilization = calculate_node_utilization(node, state.node_resources)
    
    Enum.all?(ratios, fn {resource_type, max_ratio} ->
      current_ratio = Map.get(utilization, resource_type, 0.0)
      current_ratio <= max_ratio
    end)
  end
  
  defp calculate_placement_score(agent_spec, node, state) do
    # Calculate composite placement score
    resource_score = calculate_resource_score(agent_spec, node, state)
    affinity_score = calculate_affinity_score(agent_spec, node, state)
    load_balance_score = calculate_load_balance_score(node, state)
    performance_score = calculate_performance_score(node, state)
    
    # Weighted combination of scores
    weights = %{
      resource: 0.3,
      affinity: 0.2,
      load_balance: 0.3,
      performance: 0.2
    }
    
    resource_score * weights.resource +
    affinity_score * weights.affinity +
    load_balance_score * weights.load_balance +
    performance_score * weights.performance
  end
  
  defp calculate_resource_score(agent_spec, node, state) do
    # Score based on resource efficiency (higher = better fit)
    required_resources = Map.get(agent_spec, :resources, %{})
    available_resources = get_available_resources(node, state.node_resources)
    
    if Enum.empty?(required_resources) do
      1.0
    else
      resource_efficiencies = Enum.map(required_resources, fn {resource_type, required} ->
        available = Map.get(available_resources, resource_type, 0)
        if available > 0, do: min(1.0, required / available), else: 0.0
      end)
      
      Enum.sum(resource_efficiencies) / length(resource_efficiencies)
    end
  end
  
  defp calculate_affinity_score(agent_spec, node, state) do
    # Score based on affinity constraints satisfaction
    constraints = Map.get(agent_spec, :placement_constraints, [])
    
    affinity_constraints = Enum.filter(constraints, fn 
      {:affinity, _} -> true
      _ -> false
    end)
    
    if Enum.empty?(affinity_constraints) do
      0.5  # Neutral score
    else
      satisfied_count = Enum.count(affinity_constraints, fn constraint ->
        evaluate_constraint(constraint, agent_spec, node, state)
      end)
      
      satisfied_count / length(affinity_constraints)
    end
  end
  
  defp calculate_load_balance_score(node, state) do
    # Score based on load balancing (lower utilization = higher score)
    utilization = calculate_node_utilization(node, state.node_resources)
    average_utilization = calculate_average_utilization(utilization)
    
    # Invert utilization to get score (lower utilization = higher score)
    1.0 - average_utilization
  end
  
  defp calculate_performance_score(node, state) do
    # Score based on node performance metrics
    node_metrics = get_node_performance_metrics(node)
    
    # Combine various performance factors
    latency_score = 1.0 / max(Map.get(node_metrics, :avg_latency, 1), 1)
    throughput_score = Map.get(node_metrics, :throughput, 0) / 1000.0
    availability_score = Map.get(node_metrics, :availability, 0.0)
    
    (latency_score + throughput_score + availability_score) / 3
  end
  
  defp validate_placement(agent_spec, node, state) do
    # Validate that placement is possible and calculate resource reservation
    if meets_resource_requirements?(agent_spec, node, state) and
       satisfies_placement_constraints?(agent_spec, node, state) do
      
      required_resources = Map.get(agent_spec, :resources, %{})
      {:ok, required_resources}
    else
      {:error, :placement_validation_failed}
    end
  end
  
  defp execute_migration(agent_id, agent_info, target_node, options, state) do
    # Execute agent migration from current node to target node
    migration_strategy = Keyword.get(options, :strategy, :live_migration)
    
    case migration_strategy do
      :live_migration ->
        execute_live_migration(agent_id, agent_info, target_node, state)
      :checkpoint_restore ->
        execute_checkpoint_migration(agent_id, agent_info, target_node, state)
      :cold_migration ->
        execute_cold_migration(agent_id, agent_info, target_node, state)
    end
  end
  
  defp execute_live_migration(agent_id, agent_info, target_node, state) do
    # Live migration with minimal downtime
    try do
      # 1. Start agent on target node
      {:ok, _} = Phoenix.Agent.start_on_node(target_node, agent_id, agent_info.spec)
      
      # 2. Synchronize state
      :ok = Phoenix.Agent.sync_state(agent_id, agent_info.node, target_node)
      
      # 3. Switch traffic to new node
      :ok = Phoenix.MessageRouter.switch_target(agent_id, target_node)
      
      # 4. Stop agent on old node
      :ok = Phoenix.Agent.stop_on_node(agent_info.node, agent_id)
      
      # 5. Update resource allocations
      release_resources(state.node_resources, agent_info.node, agent_info.resources)
      reserve_resources(state.node_resources, target_node, agent_info.resources)
      
      {:ok, %{strategy: :live_migration, downtime: 0}}
      
    rescue
      error ->
        # Rollback on failure
        Phoenix.Agent.stop_on_node(target_node, agent_id)
        {:error, {:migration_failed, error}}
    end
  end
  
  defp execute_checkpoint_migration(agent_id, agent_info, target_node, state) do
    # Migration with checkpoint/restore
    try do
      # 1. Create checkpoint of agent state
      {:ok, checkpoint} = Phoenix.Agent.create_checkpoint(agent_id)
      
      # 2. Stop agent on current node
      :ok = Phoenix.Agent.stop_on_node(agent_info.node, agent_id)
      
      # 3. Start agent on target node from checkpoint
      {:ok, _} = Phoenix.Agent.restore_from_checkpoint(target_node, agent_id, checkpoint)
      
      # 4. Update resource allocations
      release_resources(state.node_resources, agent_info.node, agent_info.resources)
      reserve_resources(state.node_resources, target_node, agent_info.resources)
      
      {:ok, %{strategy: :checkpoint_restore, downtime: 5_000}}  # ~5 seconds downtime
      
    rescue
      error ->
        # Attempt to restart on original node
        Phoenix.Agent.start_on_node(agent_info.node, agent_id, agent_info.spec)
        {:error, {:migration_failed, error}}
    end
  end
  
  defp execute_cold_migration(agent_id, agent_info, target_node, state) do
    # Cold migration (stop, move, start)
    try do
      # 1. Stop agent on current node
      :ok = Phoenix.Agent.stop_on_node(agent_info.node, agent_id)
      
      # 2. Start agent on target node
      {:ok, _} = Phoenix.Agent.start_on_node(target_node, agent_id, agent_info.spec)
      
      # 3. Update resource allocations
      release_resources(state.node_resources, agent_info.node, agent_info.resources)
      reserve_resources(state.node_resources, target_node, agent_info.resources)
      
      {:ok, %{strategy: :cold_migration, downtime: 10_000}}  # ~10 seconds downtime
      
    rescue
      error ->
        # Attempt to restart on original node
        Phoenix.Agent.start_on_node(agent_info.node, agent_id, agent_info.spec)
        {:error, {:migration_failed, error}}
    end
  end
  
  defp generate_rebalancing_plan(state, options) do
    # Generate plan to rebalance agents across cluster
    target_distribution = Keyword.get(options, :target, :even_distribution)
    
    case target_distribution do
      :even_distribution ->
        generate_even_distribution_plan(state)
      :resource_optimization ->
        generate_resource_optimization_plan(state)
      :latency_optimization ->
        generate_latency_optimization_plan(state)
    end
  end
  
  defp generate_even_distribution_plan(state) do
    # Plan to distribute agents evenly across nodes
    total_agents = map_size(state.agent_registry)
    active_nodes = get_active_nodes(state.node_resources)
    target_agents_per_node = div(total_agents, length(active_nodes))
    
    current_distribution = calculate_current_distribution(state.agent_registry)
    
    # Find nodes that are over/under capacity
    moves = Enum.flat_map(current_distribution, fn {node, agent_count} ->
      if agent_count > target_agents_per_node do
        excess = agent_count - target_agents_per_node
        select_agents_to_move(node, excess, state)
      else
        []
      end
    end)
    
    %{
      type: :even_distribution,
      moves: moves,
      estimated_improvement: calculate_distribution_improvement(moves, state)
    }
  end
  
  # Helper functions
  defp get_available_resources(node, node_resources) do
    total_resources = Map.get(node_resources, node, %{total: %{}, used: %{}})
    total = Map.get(total_resources, :total, %{})
    used = Map.get(total_resources, :used, %{})
    
    Map.new(total, fn {resource_type, total_amount} ->
      used_amount = Map.get(used, resource_type, 0)
      {resource_type, total_amount - used_amount}
    end)
  end
  
  defp get_agent_nodes(agent_selectors, agent_registry) do
    # Get nodes where specified agents are running
    agent_registry
    |> Enum.filter(fn {agent_id, _info} ->
      agent_matches_selectors?(agent_id, agent_selectors)
    end)
    |> Enum.map(fn {_agent_id, info} -> info.node end)
    |> Enum.uniq()
  end
  
  defp agent_matches_selectors?(agent_id, selectors) do
    # Check if agent matches any of the selectors
    Enum.any?(selectors, fn selector ->
      case selector do
        {:agent_id, id} -> agent_id == id
        {:agent_type, type} -> agent_has_type?(agent_id, type)
        {:label, key, value} -> agent_has_label?(agent_id, key, value)
        _ -> false
      end
    end)
  end
  
  defp reserve_resources(node_resources, node, resource_reservation) do
    current_resources = Map.get(node_resources, node, %{total: %{}, used: %{}})
    current_used = Map.get(current_resources, :used, %{})
    
    new_used = Map.merge(current_used, resource_reservation, fn _key, current, additional ->
      current + additional
    end)
    
    updated_resources = Map.put(current_resources, :used, new_used)
    Map.put(node_resources, node, updated_resources)
  end
  
  defp release_resources(node_resources, node, resource_reservation) do
    current_resources = Map.get(node_resources, node, %{total: %{}, used: %{}})
    current_used = Map.get(current_resources, :used, %{})
    
    new_used = Map.merge(current_used, resource_reservation, fn _key, current, release ->
      max(0, current - release)
    end)
    
    updated_resources = Map.put(current_resources, :used, new_used)
    Map.put(node_resources, node, updated_resources)
  end
  
  defp initialize_cluster_topology() do
    # Initialize cluster topology information
    %{
      nodes: [node() | Node.list()],
      regions: %{},
      network_topology: %{}
    }
  end
  
  defp schedule_resource_monitoring() do
    Process.send_after(self(), :monitor_resources, 10_000)  # Every 10 seconds
  end
  
  defp collect_cluster_resources() do
    # Collect resource information from all nodes
    %{}  # Simplified implementation
  end
  
  defp load_placement_policies(opts) do
    # Load placement policies from configuration
    Keyword.get(opts, :policies, default_placement_policies())
  end
  
  defp default_placement_policies() do
    %{
      default_strategy: :resource_aware,
      affinity_weight: 0.2,
      resource_weight: 0.3,
      load_balance_weight: 0.3,
      performance_weight: 0.2
    }
  end
  
  defp initialize_objectives() do
    %{
      minimize_latency: 0.3,
      maximize_throughput: 0.3,
      balance_load: 0.2,
      minimize_cost: 0.2
    }
  end
  
  # Placeholder implementations for external dependencies
  defp node_healthy?(_node), do: true
  defp evaluate_node_selector(_selector, _node, _state), do: true
  defp calculate_node_utilization(_node, _resources), do: %{cpu: 0.5, memory: 0.6}
  defp calculate_average_utilization(utilization) do
    values = Map.values(utilization)
    if Enum.empty?(values), do: 0.0, else: Enum.sum(values) / length(values)
  end
  defp get_node_performance_metrics(_node), do: %{avg_latency: 10, throughput: 1000, availability: 0.99}
  defp count_nodes_in_use(registry) do
    registry |> Map.values() |> Enum.map(& &1.node) |> Enum.uniq() |> length()
  end
  defp calculate_resource_utilization(_resources), do: %{cpu: 0.6, memory: 0.7}
  defp calculate_placement_efficiency(_state), do: 0.85
  defp check_constraint_violations(_state), do: []
  defp agent_has_type?(_agent_id, _type), do: false
  defp agent_has_label?(_agent_id, _key, _value), do: false
  defp get_active_nodes(_resources), do: [node()]
  defp calculate_current_distribution(registry) do
    registry |> Enum.group_by(fn {_id, info} -> info.node end) |> Map.new(fn {node, agents} -> {node, length(agents)} end)
  end
  defp select_agents_to_move(_node, _count, _state), do: []
  defp calculate_distribution_improvement(_moves, _state), do: 0.1
  defp generate_resource_optimization_plan(state), do: generate_even_distribution_plan(state)
  defp generate_latency_optimization_plan(state), do: generate_even_distribution_plan(state)
  defp execute_rebalancing_plan(plan, state), do: {:ok, state}
end
```

---

## Performance Monitoring and Metrics

### Comprehensive Performance Monitoring System

```elixir
defmodule Phoenix.Metrics do
  @moduledoc """
  Comprehensive performance monitoring and metrics collection system.
  
  Metrics Categories:
  1. **Agent Performance**: Response times, throughput, error rates
  2. **System Resources**: CPU, memory, network, disk utilization
  3. **Cluster Health**: Node availability, partition status, consensus health
  4. **Application Metrics**: Business logic performance, custom metrics
  5. **Infrastructure Metrics**: Load balancer, message queue, database performance
  """
  
  use GenServer
  
  defstruct [
    :collectors,
    :metric_store,
    :aggregators,
    :alert_thresholds,
    :reporting_intervals,
    :metric_history
  ]
  
  @metric_types [:counter, :gauge, :histogram, :timer, :summary]
  @default_collection_interval 1_000  # 1 second
  @default_aggregation_interval 60_000  # 1 minute
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    state = %__MODULE__{
      collectors: initialize_collectors(),
      metric_store: :ets.new(:phoenix_metrics, [:set, :public, :named_table]),
      aggregators: initialize_aggregators(),
      alert_thresholds: load_alert_thresholds(opts),
      reporting_intervals: initialize_reporting_intervals(),
      metric_history: %{}
    }
    
    # Start metric collection
    schedule_metric_collection()
    schedule_metric_aggregation()
    
    {:ok, state}
  end
  
  @doc """
  Record a metric value.
  """
  def record_metric(metric_name, value, metadata \\ %{}) do
    timestamp = System.system_time(:microsecond)
    
    metric_entry = %{
      name: metric_name,
      value: value,
      timestamp: timestamp,
      metadata: metadata,
      node: node()
    }
    
    :ets.insert(:phoenix_metrics, {metric_name, timestamp, metric_entry})
    
    # Check for alert conditions
    check_alert_threshold(metric_name, value)
  end
  
  @doc """
  Increment a counter metric.
  """
  def increment(metric_name, amount \\ 1, metadata \\ %{}) do
    current_value = get_current_value(metric_name, 0)
    record_metric(metric_name, current_value + amount, metadata)
  end
  
  @doc """
  Record timing information.
  """
  def time(metric_name, fun) when is_function(fun, 0) do
    start_time = System.monotonic_time(:microsecond)
    
    try do
      result = fun.()
      execution_time = System.monotonic_time(:microsecond) - start_time
      record_metric(metric_name, execution_time, %{type: :timing, unit: :microseconds})
      {:ok, result}
    rescue
      error ->
        execution_time = System.monotonic_time(:microsecond) - start_time
        record_metric(metric_name, execution_time, %{type: :timing, unit: :microseconds, error: true})
        {:error, error}
    end
  end
  
  @doc """
  Get current metric value.
  """
  def get_metric(metric_name) do
    GenServer.call(__MODULE__, {:get_metric, metric_name})
  end
  
  @doc """
  Get metric statistics (min, max, avg, percentiles).
  """
  def get_metric_stats(metric_name, time_window \\ :last_hour) do
    GenServer.call(__MODULE__, {:get_metric_stats, metric_name, time_window})
  end
  
  @doc """
  Get all metrics for a specific node.
  """
  def get_node_metrics(node \\ node()) do
    GenServer.call(__MODULE__, {:get_node_metrics, node})
  end
  
  @doc """
  Get cluster-wide aggregated metrics.
  """
  def get_cluster_metrics() do
    GenServer.call(__MODULE__, :get_cluster_metrics)
  end
  
  def handle_call({:get_metric, metric_name}, _from, state) do
    latest_value = get_latest_metric_value(metric_name)
    {:reply, latest_value, state}
  end
  
  def handle_call({:get_metric_stats, metric_name, time_window}, _from, state) do
    stats = calculate_metric_statistics(metric_name, time_window)
    {:reply, stats, state}
  end
  
  def handle_call({:get_node_metrics, node}, _from, state) do
    node_metrics = collect_node_specific_metrics(node)
    {:reply, node_metrics, state}
  end
  
  def handle_call(:get_cluster_metrics, _from, state) do
    cluster_metrics = aggregate_cluster_metrics()
    {:reply, cluster_metrics, state}
  end
  
  def handle_info(:collect_metrics, state) do
    # Collect metrics from all registered collectors
    Enum.each(state.collectors, fn {collector_name, collector_module} ->
      spawn(fn ->
        try do
          metrics = collector_module.collect()
          store_collected_metrics(collector_name, metrics)
        rescue
          error ->
            Logger.error("Metric collection failed for #{collector_name}: #{inspect(error)}")
        end
      end)
    end)
    
    schedule_metric_collection()
    {:noreply, state}
  end
  
  def handle_info(:aggregate_metrics, state) do
    # Perform metric aggregation
    new_history = perform_metric_aggregation(state.metric_history)
    
    schedule_metric_aggregation()
    {:noreply, %{state | metric_history: new_history}}
  end
  
  defp get_latest_metric_value(metric_name) do
    case :ets.lookup(:phoenix_metrics, metric_name) do
      [] -> nil
      entries ->
        # Get most recent entry
        {_name, _timestamp, latest_entry} = Enum.max_by(entries, fn {_name, timestamp, _entry} -> 
          timestamp 
        end)
        latest_entry.value
    end
  end
  
  defp calculate_metric_statistics(metric_name, time_window) do
    cutoff_time = calculate_cutoff_time(time_window)
    
    # Get all metric entries within time window
    entries = :ets.lookup(:phoenix_metrics, metric_name)
    |> Enum.filter(fn {_name, timestamp, _entry} -> timestamp >= cutoff_time end)
    |> Enum.map(fn {_name, _timestamp, entry} -> entry.value end)
    
    if Enum.empty?(entries) do
      %{count: 0, min: nil, max: nil, avg: nil, percentiles: %{}}
    else
      sorted_values = Enum.sort(entries)
      
      %{
        count: length(entries),
        min: List.first(sorted_values),
        max: List.last(sorted_values),
        avg: Enum.sum(entries) / length(entries),
        percentiles: calculate_percentiles(sorted_values)
      }
    end
  end
  
  defp calculate_percentiles(sorted_values) do
    length = length(sorted_values)
    
    %{
      p50: percentile(sorted_values, length, 50),
      p95: percentile(sorted_values, length, 95),
      p99: percentile(sorted_values, length, 99)
    }
  end
  
  defp percentile(sorted_values, length, percentile) do
    index = round(length * percentile / 100) - 1
    index = max(0, min(index, length - 1))
    Enum.at(sorted_values, index)
  end
  
  defp collect_node_specific_metrics(node) do
    # Collect comprehensive node metrics
    base_metrics = %{
      cpu_utilization: get_cpu_utilization(node),
      memory_utilization: get_memory_utilization(node),
      network_utilization: get_network_utilization(node),
      disk_utilization: get_disk_utilization(node),
      process_count: get_process_count(node),
      agent_count: get_agent_count(node),
      message_queue_length: get_message_queue_length(node),
      response_time_avg: get_average_response_time(node),
      throughput: get_throughput(node),
      error_rate: get_error_rate(node),
      availability: get_availability(node)
    }
    
    # Add BEAM-specific metrics
    beam_metrics = if node == node() do
      %{
        beam_process_count: :erlang.system_info(:process_count),
        beam_memory_total: :erlang.memory(:total),
        beam_memory_processes: :erlang.memory(:processes),
        beam_memory_system: :erlang.memory(:system),
        beam_run_queue: :erlang.statistics(:run_queue),
        beam_reductions: elem(:erlang.statistics(:reductions), 0)
      }
    else
      get_remote_beam_metrics(node)
    end
    
    Map.merge(base_metrics, beam_metrics)
  end
  
  defp aggregate_cluster_metrics() do
    # Aggregate metrics across all cluster nodes
    all_nodes = [node() | Node.list()]
    
    node_metrics = Enum.map(all_nodes, fn node ->
      {node, collect_node_specific_metrics(node)}
    end)
    |> Enum.into(%{})
    
    # Calculate cluster-wide aggregations
    %{
      cluster_cpu_avg: calculate_cluster_average(node_metrics, :cpu_utilization),
      cluster_memory_avg: calculate_cluster_average(node_metrics, :memory_utilization),
      cluster_throughput_total: calculate_cluster_sum(node_metrics, :throughput),
      cluster_error_rate_avg: calculate_cluster_average(node_metrics, :error_rate),
      cluster_availability: calculate_cluster_availability(node_metrics),
      active_nodes: length(all_nodes),
      total_agents: calculate_cluster_sum(node_metrics, :agent_count),
      node_metrics: node_metrics
    }
  end
  
  defp calculate_cluster_average(node_metrics, metric_key) do
    values = Map.values(node_metrics)
    |> Enum.map(fn metrics -> Map.get(metrics, metric_key, 0) end)
    |> Enum.filter(&is_number/1)
    
    if Enum.empty?(values) do
      0.0
    else
      Enum.sum(values) / length(values)
    end
  end
  
  defp calculate_cluster_sum(node_metrics, metric_key) do
    Map.values(node_metrics)
    |> Enum.map(fn metrics -> Map.get(metrics, metric_key, 0) end)
    |> Enum.filter(&is_number/1)
    |> Enum.sum()
  end
  
  defp calculate_cluster_availability(node_metrics) do
    availabilities = Map.values(node_metrics)
    |> Enum.map(fn metrics -> Map.get(metrics, :availability, 0.0) end)
    
    if Enum.empty?(availabilities) do
      0.0
    else
      # Cluster availability is the product of node availabilities
      Enum.reduce(availabilities, 1.0, &(&1 * &2))
    end
  end
  
  defp check_alert_threshold(metric_name, value) do
    # Check if metric value exceeds alert thresholds
    thresholds = get_alert_thresholds(metric_name)
    
    Enum.each(thresholds, fn {level, threshold_value} ->
      if exceeds_threshold?(value, threshold_value) do
        trigger_alert(metric_name, value, level, threshold_value)
      end
    end)
  end
  
  defp exceeds_threshold?(value, threshold) when is_number(value) and is_number(threshold) do
    value > threshold
  end
  
  defp exceeds_threshold?(_value, _threshold), do: false
  
  defp trigger_alert(metric_name, value, level, threshold) do
    alert = %{
      metric: metric_name,
      value: value,
      threshold: threshold,
      level: level,
      timestamp: DateTime.utc_now(),
      node: node()
    }
    
    Phoenix.Alerting.send_alert(alert)
  end
  
  defp initialize_collectors() do
    %{
      system_metrics: Phoenix.Metrics.SystemCollector,
      agent_metrics: Phoenix.Metrics.AgentCollector,
      network_metrics: Phoenix.Metrics.NetworkCollector,
      application_metrics: Phoenix.Metrics.ApplicationCollector
    }
  end
  
  defp initialize_aggregators() do
    %{
      time_series: Phoenix.Metrics.TimeSeriesAggregator,
      statistical: Phoenix.Metrics.StatisticalAggregator,
      threshold: Phoenix.Metrics.ThresholdAggregator
    }
  end
  
  defp load_alert_thresholds(opts) do
    Keyword.get(opts, :alert_thresholds, default_alert_thresholds())
  end
  
  defp default_alert_thresholds() do
    %{
      cpu_utilization: [{:warning, 0.8}, {:critical, 0.95}],
      memory_utilization: [{:warning, 0.85}, {:critical, 0.95}],
      response_time_avg: [{:warning, 100}, {:critical, 500}],
      error_rate: [{:warning, 0.05}, {:critical, 0.1}]
    }
  end
  
  defp initialize_reporting_intervals() do
    %{
      real_time: 1_000,      # 1 second
      short_term: 60_000,    # 1 minute
      medium_term: 300_000,  # 5 minutes
      long_term: 3_600_000   # 1 hour
    }
  end
  
  defp calculate_cutoff_time(time_window) do
    now = System.system_time(:microsecond)
    
    case time_window do
      :last_minute -> now - 60_000_000      # 60 seconds
      :last_hour -> now - 3_600_000_000     # 1 hour
      :last_day -> now - 86_400_000_000     # 24 hours
      _ -> now - 3_600_000_000               # Default to 1 hour
    end
  end
  
  defp schedule_metric_collection() do
    Process.send_after(self(), :collect_metrics, @default_collection_interval)
  end
  
  defp schedule_metric_aggregation() do
    Process.send_after(self(), :aggregate_metrics, @default_aggregation_interval)
  end
  
  defp store_collected_metrics(collector_name, metrics) do
    timestamp = System.system_time(:microsecond)
    
    Enum.each(metrics, fn {metric_name, value, metadata} ->
      full_metric_name = "#{collector_name}.#{metric_name}"
      record_metric(full_metric_name, value, Map.put(metadata, :collector, collector_name))
    end)
  end
  
  defp perform_metric_aggregation(history) do
    # Perform time-based aggregation of metrics
    current_window = System.system_time(:microsecond)
    
    # Aggregate metrics by time windows
    aggregated = aggregate_time_windows(current_window)
    
    # Update history with new aggregations
    Map.put(history, current_window, aggregated)
    |> keep_recent_history(100)  # Keep last 100 aggregation windows
  end
  
  defp aggregate_time_windows(current_time) do
    # Implementation would aggregate metrics over time windows
    %{
      timestamp: current_time,
      aggregations: %{}
    }
  end
  
  defp keep_recent_history(history, max_entries) do
    history
    |> Enum.sort_by(fn {timestamp, _} -> timestamp end, :desc)
    |> Enum.take(max_entries)
    |> Enum.into(%{})
  end
  
  defp get_current_value(metric_name, default) do
    case get_latest_metric_value(metric_name) do
      nil -> default
      value -> value
    end
  end
  
  defp get_alert_thresholds(metric_name) do
    # Get alert thresholds for specific metric
    GenServer.call(__MODULE__, {:get_alert_thresholds, metric_name})
  end
  
  # Placeholder implementations for system metrics
  defp get_cpu_utilization(_node), do: 0.5
  defp get_memory_utilization(_node), do: 0.6
  defp get_network_utilization(_node), do: 0.3
  defp get_disk_utilization(_node), do: 0.4
  defp get_process_count(_node), do: 150
  defp get_agent_count(_node), do: 25
  defp get_message_queue_length(_node), do: 10
  defp get_average_response_time(_node), do: 50.0
  defp get_throughput(_node), do: 1000.0
  defp get_error_rate(_node), do: 0.02
  defp get_availability(_node), do: 0.99
  defp get_remote_beam_metrics(_node), do: %{}
end
```

---

## Horizontal Scaling Automation

### Auto-Scaling Engine

```elixir
defmodule Phoenix.AutoScaling do
  @moduledoc """
  Intelligent auto-scaling system that automatically adjusts cluster size
  based on performance metrics, workload predictions, and scaling policies.
  
  Scaling Strategies:
  1. **Reactive Scaling**: Scale based on current metrics
  2. **Predictive Scaling**: Scale based on ML predictions
  3. **Scheduled Scaling**: Scale based on time patterns
  4. **Event-Driven Scaling**: Scale based on external events
  5. **Hybrid Scaling**: Combine multiple strategies
  """
  
  use GenServer
  
  defstruct [
    :scaling_policies,
    :current_capacity,
    :target_capacity,
    :scaling_history,
    :workload_predictor,
    :scaling_cooldowns,
    :resource_pools
  ]
  
  @scale_out_cooldown 300_000    # 5 minutes
  @scale_in_cooldown 600_000     # 10 minutes
  @prediction_horizon 3600       # 1 hour prediction horizon
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    state = %__MODULE__{
      scaling_policies: load_scaling_policies(opts),
      current_capacity: get_current_cluster_capacity(),
      target_capacity: get_current_cluster_capacity(),
      scaling_history: [],
      workload_predictor: Phoenix.ML.WorkloadPredictor.new(),
      scaling_cooldowns: %{scale_out: 0, scale_in: 0},
      resource_pools: initialize_resource_pools(opts)
    }
    
    # Start scaling evaluation
    schedule_scaling_evaluation()
    schedule_predictive_scaling()
    
    {:ok, state}
  end
  
  @doc """
  Trigger immediate scaling evaluation.
  """
  def evaluate_scaling() do
    GenServer.cast(__MODULE__, :evaluate_scaling)
  end
  
  @doc """
  Manually scale cluster to specified capacity.
  """
  def scale_to(target_capacity, reason \\ :manual) do
    GenServer.call(__MODULE__, {:scale_to, target_capacity, reason})
  end
  
  @doc """
  Add scaling policy.
  """
  def add_scaling_policy(policy) do
    GenServer.call(__MODULE__, {:add_policy, policy})
  end
  
  @doc """
  Get current scaling status and recommendations.
  """
  def scaling_status() do
    GenServer.call(__MODULE__, :scaling_status)
  end
  
  def handle_call({:scale_to, target_capacity, reason}, _from, state) do
    case validate_scaling_request(target_capacity, state) do
      :ok ->
        case execute_scaling(state.current_capacity, target_capacity, reason, state) do
          {:ok, new_state} ->
            {:reply, :ok, new_state}
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call({:add_policy, policy}, _from, state) do
    new_policies = [policy | state.scaling_policies]
    {:reply, :ok, %{state | scaling_policies: new_policies}}
  end
  
  def handle_call(:scaling_status, _from, state) do
    status = %{
      current_capacity: state.current_capacity,
      target_capacity: state.target_capacity,
      scaling_policies: length(state.scaling_policies),
      recent_scaling_events: Enum.take(state.scaling_history, 10),
      cooldown_status: get_cooldown_status(state.scaling_cooldowns),
      predictions: get_scaling_predictions(state.workload_predictor)
    }
    
    {:reply, status, state}
  end
  
  def handle_cast(:evaluate_scaling, state) do
    new_state = perform_scaling_evaluation(state)
    {:noreply, new_state}
  end
  
  def handle_info(:scaling_evaluation, state) do
    new_state = perform_scaling_evaluation(state)
    
    schedule_scaling_evaluation()
    {:noreply, new_state}
  end
  
  def handle_info(:predictive_scaling, state) do
    new_state = perform_predictive_scaling(state)
    
    schedule_predictive_scaling()
    {:noreply, new_state}
  end
  
  def handle_info({:scaling_complete, scaling_result}, state) do
    # Update state after scaling operation completes
    new_state = handle_scaling_completion(scaling_result, state)
    {:noreply, new_state}
  end
  
  defp perform_scaling_evaluation(state) do
    # Collect current metrics
    current_metrics = collect_scaling_metrics()
    
    # Evaluate each scaling policy
    scaling_decisions = Enum.map(state.scaling_policies, fn policy ->
      evaluate_scaling_policy(policy, current_metrics, state)
    end)
    |> Enum.filter(fn decision -> decision != :no_action end)
    
    # Combine decisions and determine final action
    final_decision = resolve_scaling_decisions(scaling_decisions, state)
    
    case final_decision do
      {:scale_out, target_capacity, reasons} ->
        if can_scale_out?(state) do
          execute_scale_out(target_capacity, reasons, state)
        else
          state
        end
        
      {:scale_in, target_capacity, reasons} ->
        if can_scale_in?(state) do
          execute_scale_in(target_capacity, reasons, state)
        else
          state
        end
        
      :no_action ->
        state
    end
  end
  
  defp evaluate_scaling_policy(policy, metrics, state) do
    case policy.type do
      :threshold_based ->
        evaluate_threshold_policy(policy, metrics, state)
      :rate_based ->
        evaluate_rate_policy(policy, metrics, state)
      :queue_based ->
        evaluate_queue_policy(policy, metrics, state)
      :resource_based ->
        evaluate_resource_policy(policy, metrics, state)
      :composite ->
        evaluate_composite_policy(policy, metrics, state)
    end
  end
  
  defp evaluate_threshold_policy(policy, metrics, state) do
    metric_value = Map.get(metrics, policy.metric)
    
    cond do
      metric_value > policy.scale_out_threshold ->
        target = calculate_scale_out_target(policy, metric_value, state.current_capacity)
        {:scale_out, target, [policy.name]}
        
      metric_value < policy.scale_in_threshold ->
        target = calculate_scale_in_target(policy, metric_value, state.current_capacity)
        {:scale_in, target, [policy.name]}
        
      true ->
        :no_action
    end
  end
  
  defp evaluate_rate_policy(policy, metrics, state) do
    # Evaluate based on rate of change
    metric_history = get_metric_history(policy.metric, policy.evaluation_window)
    
    if length(metric_history) >= 2 do
      rate_of_change = calculate_rate_of_change(metric_history)
      
      cond do
        rate_of_change > policy.scale_out_rate ->
          target = state.current_capacity + policy.scale_increment
          {:scale_out, target, [policy.name]}
          
        rate_of_change < policy.scale_in_rate ->
          target = max(policy.min_capacity, state.current_capacity - policy.scale_decrement)
          {:scale_in, target, [policy.name]}
          
        true ->
          :no_action
      end
    else
      :no_action
    end
  end
  
  defp evaluate_queue_policy(policy, metrics, state) do
    # Evaluate based on queue lengths and processing times
    queue_length = Map.get(metrics, policy.queue_metric, 0)
    processing_rate = Map.get(metrics, policy.processing_rate_metric, 1)
    
    estimated_wait_time = queue_length / processing_rate
    
    cond do
      estimated_wait_time > policy.max_wait_time ->
        # Scale out to reduce wait time
        target_processing_rate = queue_length / policy.target_wait_time
        scale_factor = target_processing_rate / processing_rate
        target = round(state.current_capacity * scale_factor)
        {:scale_out, target, [policy.name]}
        
      estimated_wait_time < policy.min_utilization_wait_time ->
        # Scale in due to low utilization
        target = max(policy.min_capacity, round(state.current_capacity * 0.8))
        {:scale_in, target, [policy.name]}
        
      true ->
        :no_action
    end
  end
  
  defp evaluate_resource_policy(policy, metrics, state) do
    # Evaluate based on resource utilization across multiple dimensions
    resource_scores = Enum.map(policy.resources, fn {resource, thresholds} ->
      utilization = Map.get(metrics, resource, 0.0)
      
      cond do
        utilization > thresholds.scale_out -> {:scale_out, resource, utilization}
        utilization < thresholds.scale_in -> {:scale_in, resource, utilization}
        true -> {:no_action, resource, utilization}
      end
    end)
    
    # Determine action based on most constrained resource
    critical_resources = Enum.filter(resource_scores, fn {action, _, _} -> 
      action in [:scale_out, :scale_in] 
    end)
    
    if not Enum.empty?(critical_resources) do
      {action, resource, _} = Enum.max_by(critical_resources, fn {_, _, utilization} -> 
        utilization 
      end)
      
      target = case action do
        :scale_out -> state.current_capacity + policy.scale_increment
        :scale_in -> max(policy.min_capacity, state.current_capacity - policy.scale_decrement)
      end
      
      {action, target, [policy.name, resource]}
    else
      :no_action
    end
  end
  
  defp evaluate_composite_policy(policy, metrics, state) do
    # Evaluate composite policy that combines multiple conditions
    sub_decisions = Enum.map(policy.sub_policies, fn sub_policy ->
      evaluate_scaling_policy(sub_policy, metrics, state)
    end)
    
    case policy.combination_strategy do
      :any -> 
        # Any sub-policy triggering causes action
        Enum.find(sub_decisions, :no_action, &(&1 != :no_action))
        
      :all ->
        # All sub-policies must agree
        if Enum.all?(sub_decisions, &(&1 != :no_action)) do
          # Take the most aggressive action
          aggregate_decisions(sub_decisions)
        else
          :no_action
        end
        
      :majority ->
        # Majority of sub-policies must agree
        non_no_action = Enum.filter(sub_decisions, &(&1 != :no_action))
        
        if length(non_no_action) > length(policy.sub_policies) / 2 do
          aggregate_decisions(non_no_action)
        else
          :no_action
        end
    end
  end
  
  defp resolve_scaling_decisions(decisions, state) do
    if Enum.empty?(decisions) do
      :no_action
    else
      # Group decisions by action type
      {scale_out_decisions, scale_in_decisions} = Enum.split_with(decisions, fn
        {:scale_out, _, _} -> true
        _ -> false
      end)
      
      cond do
        not Enum.empty?(scale_out_decisions) ->
          # Prioritize scale out for performance
          {_, max_target, reasons} = Enum.max_by(scale_out_decisions, fn {_, target, _} -> 
            target 
          end)
          all_reasons = Enum.flat_map(scale_out_decisions, fn {_, _, reasons} -> reasons end)
          {:scale_out, max_target, all_reasons}
          
        not Enum.empty?(scale_in_decisions) ->
          # Scale in conservatively
          {_, min_target, reasons} = Enum.min_by(scale_in_decisions, fn {_, target, _} -> 
            target 
          end)
          all_reasons = Enum.flat_map(scale_in_decisions, fn {_, _, reasons} -> reasons end)
          {:scale_in, min_target, all_reasons}
          
        true ->
          :no_action
      end
    end
  end
  
  defp execute_scale_out(target_capacity, reasons, state) do
    Logger.info("Scaling out from #{state.current_capacity} to #{target_capacity}, reasons: #{inspect(reasons)}")
    
    scaling_event = %{
      type: :scale_out,
      from_capacity: state.current_capacity,
      to_capacity: target_capacity,
      reasons: reasons,
      timestamp: DateTime.utc_now()
    }
    
    # Execute scaling asynchronously
    spawn_link(fn ->
      result = perform_scale_out(state.current_capacity, target_capacity)
      send(__MODULE__, {:scaling_complete, result})
    end)
    
    # Update state
    new_history = [scaling_event | state.scaling_history] |> Enum.take(100)
    new_cooldowns = Map.put(state.scaling_cooldowns, :scale_out, System.monotonic_time(:millisecond) + @scale_out_cooldown)
    
    %{state | 
      target_capacity: target_capacity,
      scaling_history: new_history,
      scaling_cooldowns: new_cooldowns
    }
  end
  
  defp execute_scale_in(target_capacity, reasons, state) do
    Logger.info("Scaling in from #{state.current_capacity} to #{target_capacity}, reasons: #{inspect(reasons)}")
    
    scaling_event = %{
      type: :scale_in,
      from_capacity: state.current_capacity,
      to_capacity: target_capacity,
      reasons: reasons,
      timestamp: DateTime.utc_now()
    }
    
    # Execute scaling asynchronously
    spawn_link(fn ->
      result = perform_scale_in(state.current_capacity, target_capacity)
      send(__MODULE__, {:scaling_complete, result})
    end)
    
    # Update state
    new_history = [scaling_event | state.scaling_history] |> Enum.take(100)
    new_cooldowns = Map.put(state.scaling_cooldowns, :scale_in, System.monotonic_time(:millisecond) + @scale_in_cooldown)
    
    %{state | 
      target_capacity: target_capacity,
      scaling_history: new_history,
      scaling_cooldowns: new_cooldowns
    }
  end
  
  defp perform_scale_out(current_capacity, target_capacity) do
    additional_nodes = target_capacity - current_capacity
    
    try do
      # Provision additional nodes
      new_nodes = provision_nodes(additional_nodes)
      
      # Add nodes to cluster
      Enum.each(new_nodes, fn node ->
        :ok = add_node_to_cluster(node)
      end)
      
      # Rebalance agents across expanded cluster
      :ok = Phoenix.LoadBalancing.rebalance_agents()
      
      {:ok, %{
        action: :scale_out,
        new_nodes: new_nodes,
        new_capacity: target_capacity
      }}
      
    rescue
      error ->
        {:error, {:scale_out_failed, error}}
    end
  end
  
  defp perform_scale_in(current_capacity, target_capacity) do
    nodes_to_remove = current_capacity - target_capacity
    
    try do
      # Select nodes to remove (least loaded)
      candidate_nodes = select_nodes_for_removal(nodes_to_remove)
      
      # Drain agents from selected nodes
      Enum.each(candidate_nodes, fn node ->
        :ok = drain_node(node)
      end)
      
      # Remove nodes from cluster
      Enum.each(candidate_nodes, fn node ->
        :ok = remove_node_from_cluster(node)
      end)
      
      # Deprovision nodes
      :ok = deprovision_nodes(candidate_nodes)
      
      {:ok, %{
        action: :scale_in,
        removed_nodes: candidate_nodes,
        new_capacity: target_capacity
      }}
      
    rescue
      error ->
        {:error, {:scale_in_failed, error}}
    end
  end
  
  defp perform_predictive_scaling(state) do
    # Use ML model to predict future workload
    current_time = DateTime.utc_now()
    prediction_time = DateTime.add(current_time, @prediction_horizon, :second)
    
    predicted_workload = Phoenix.ML.WorkloadPredictor.predict(
      state.workload_predictor,
      prediction_time
    )
    
    # Calculate required capacity for predicted workload
    required_capacity = calculate_required_capacity(predicted_workload)
    
    # Check if pre-emptive scaling is needed
    current_capacity = state.current_capacity
    capacity_buffer = 0.2  # 20% buffer
    
    cond do
      required_capacity > current_capacity * (1 + capacity_buffer) ->
        # Pre-emptive scale out
        target = round(required_capacity * 1.1)  # 10% additional buffer
        
        Logger.info("Predictive scaling: scaling out to #{target} for predicted workload")
        execute_scale_out(target, [:predictive_scaling], state)
        
      required_capacity < current_capacity * (1 - capacity_buffer) ->
        # Pre-emptive scale in
        target = max(1, round(required_capacity))
        
        Logger.info("Predictive scaling: scaling in to #{target} for predicted workload")
        execute_scale_in(target, [:predictive_scaling], state)
        
      true ->
        # No action needed
        state
    end
  end
  
  defp can_scale_out?(state) do
    now = System.monotonic_time(:millisecond)
    cooldown_end = Map.get(state.scaling_cooldowns, :scale_out, 0)
    
    now >= cooldown_end
  end
  
  defp can_scale_in?(state) do
    now = System.monotonic_time(:millisecond)
    cooldown_end = Map.get(state.scaling_cooldowns, :scale_in, 0)
    
    now >= cooldown_end and state.current_capacity > 1
  end
  
  defp handle_scaling_completion(scaling_result, state) do
    case scaling_result do
      {:ok, %{new_capacity: new_capacity}} ->
        Logger.info("Scaling completed successfully, new capacity: #{new_capacity}")
        %{state | current_capacity: new_capacity}
        
      {:error, reason} ->
        Logger.error("Scaling failed: #{inspect(reason)}")
        # Revert target capacity to current capacity
        %{state | target_capacity: state.current_capacity}
    end
  end
  
  # Helper functions and initialization
  defp collect_scaling_metrics() do
    # Collect metrics relevant to scaling decisions
    Phoenix.Metrics.get_cluster_metrics()
  end
  
  defp get_current_cluster_capacity() do
    length([node() | Node.list()])
  end
  
  defp load_scaling_policies(opts) do
    Keyword.get(opts, :scaling_policies, default_scaling_policies())
  end
  
  defp default_scaling_policies() do
    [
      %{
        name: :cpu_threshold,
        type: :threshold_based,
        metric: :cluster_cpu_avg,
        scale_out_threshold: 0.8,
        scale_in_threshold: 0.3,
        min_capacity: 1,
        max_capacity: 20,
        scale_increment: 2
      },
      %{
        name: :memory_threshold,
        type: :threshold_based,
        metric: :cluster_memory_avg,
        scale_out_threshold: 0.85,
        scale_in_threshold: 0.4,
        min_capacity: 1,
        max_capacity: 20,
        scale_increment: 1
      }
    ]
  end
  
  defp initialize_resource_pools(opts) do
    Keyword.get(opts, :resource_pools, %{
      compute: %{min: 1, max: 50, current: 5},
      memory: %{min: 1, max: 100, current: 10}
    })
  end
  
  defp schedule_scaling_evaluation() do
    Process.send_after(self(), :scaling_evaluation, 30_000)  # Every 30 seconds
  end
  
  defp schedule_predictive_scaling() do
    Process.send_after(self(), :predictive_scaling, 300_000)  # Every 5 minutes
  end
  
  # Placeholder implementations
  defp validate_scaling_request(_target_capacity, _state), do: :ok
  defp execute_scaling(_current, _target, _reason, state), do: {:ok, state}
  defp get_cooldown_status(_cooldowns), do: %{scale_out: false, scale_in: false}
  defp get_scaling_predictions(_predictor), do: %{predicted_load: 0.5, confidence: 0.8}
  defp calculate_scale_out_target(_policy, _metric_value, current_capacity), do: current_capacity + 1
  defp calculate_scale_in_target(_policy, _metric_value, current_capacity), do: max(1, current_capacity - 1)
  defp get_metric_history(_metric, _window), do: [0.5, 0.6, 0.7]
  defp calculate_rate_of_change([_|_] = history), do: List.last(history) - hd(history)
  defp aggregate_decisions([decision | _]), do: decision
  defp calculate_required_capacity(_workload), do: 3
  defp provision_nodes(count), do: for i <- 1..count, do: :"node#{i}@localhost"
  defp add_node_to_cluster(_node), do: :ok
  defp select_nodes_for_removal(count), do: for i <- 1..count, do: :"node#{i}@localhost"
  defp drain_node(_node), do: :ok
  defp remove_node_from_cluster(_node), do: :ok
  defp deprovision_nodes(_nodes), do: :ok
end
```

---

## Summary and Implementation Roadmap

### Performance Optimization Summary

Phoenix's performance optimization system provides:

1. **Adaptive Performance Management**: Automatic tuning based on real-time metrics and ML predictions
2. **Intelligent Load Balancing**: Multiple strategies with dynamic weight adjustment
3. **Resource-Aware Placement**: Optimal agent distribution considering constraints and objectives
4. **Comprehensive Monitoring**: Multi-dimensional metrics collection and analysis
5. **Auto-Scaling**: Reactive and predictive scaling with multiple policy types

### Implementation Roadmap

<function_calls>
<invoke name="TodoWrite">
<parameter name="todos">[{"content": "Research modern distributed systems patterns and CAP theorem implications", "status": "completed", "priority": "high", "id": "1"}, {"content": "Analyze BEAM/OTP distribution capabilities and limitations", "status": "completed", "priority": "high", "id": "2"}, {"content": "Design core distributed agent primitives", "status": "completed", "priority": "high", "id": "3"}, {"content": "Create comprehensive architecture document", "status": "completed", "priority": "high", "id": "4"}, {"content": "Design communication patterns and protocols", "status": "completed", "priority": "high", "id": "5"}, {"content": "Define state management and consistency strategies", "status": "completed", "priority": "medium", "id": "6"}, {"content": "Create fault tolerance and partition handling design", "status": "completed", "priority": "medium", "id": "7"}, {"content": "Design performance optimization strategies", "status": "completed", "priority": "medium", "id": "8"}, {"content": "Create implementation roadmap and technical specifications", "status": "in_progress", "priority": "medium", "id": "9"}]