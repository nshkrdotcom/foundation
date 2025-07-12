# Phoenix: Fault Tolerance and Partition Handling
**Date**: 2025-07-12  
**Version**: 1.0  
**Series**: Distributed Agent System - Part 4 (Fault Tolerance)

## Executive Summary

This document provides comprehensive specifications for fault tolerance and partition handling in the Phoenix distributed agent system. Drawing from distributed systems research, production BEAM patterns, and chaos engineering principles, Phoenix implements a **multi-layered resilience architecture** that gracefully handles various failure modes while maintaining system availability and data consistency.

**Key Innovation**: Phoenix employs **adaptive fault tolerance** where the system automatically adjusts its resilience strategies based on detected failure patterns, network conditions, and application criticality levels.

## Table of Contents

1. [Fault Model and Failure Classification](#fault-model-and-failure-classification)
2. [Circuit Breaker Patterns](#circuit-breaker-patterns)
3. [Bulkhead Isolation Strategies](#bulkhead-isolation-strategies)
4. [Network Partition Detection](#network-partition-detection)
5. [Partition Response Strategies](#partition-response-strategies)
6. [Recovery and Reconciliation](#recovery-and-reconciliation)
7. [Graceful Degradation](#graceful-degradation)
8. [Chaos Engineering Integration](#chaos-engineering-integration)

---

## Fault Model and Failure Classification

### Comprehensive Failure Taxonomy

```elixir
defmodule Phoenix.FaultModel do
  @moduledoc """
  Comprehensive classification of failure modes in distributed agent systems.
  
  Failure Categories:
  1. **Process Failures**: Agent crashes, memory exhaustion, deadlocks
  2. **Node Failures**: Hardware failures, OS crashes, resource exhaustion  
  3. **Network Failures**: Partitions, high latency, packet loss
  4. **Software Failures**: Bugs, race conditions, resource leaks
  5. **Byzantine Failures**: Malicious behavior, corruption, inconsistent responses
  """
  
  @type failure_type ::
    :process_crash |
    :process_hang |
    :memory_exhaustion |
    :node_crash |
    :node_unreachable |
    :network_partition |
    :high_latency |
    :packet_loss |
    :software_bug |
    :resource_leak |
    :byzantine_behavior |
    :data_corruption
    
  @type failure_severity :: :low | :medium | :high | :critical
  @type failure_scope :: :local | :node | :cluster | :global
  
  defstruct [
    :type,
    :severity,
    :scope,
    :affected_components,
    :detection_time,
    :probable_cause,
    :recovery_strategy,
    :impact_assessment
  ]
  
  @doc """
  Classify detected failure and determine response strategy.
  """
  def classify_failure(failure_symptoms, context \\ %{}) do
    failure_type = determine_failure_type(failure_symptoms)
    severity = assess_severity(failure_type, failure_symptoms, context)
    scope = determine_scope(failure_type, failure_symptoms, context)
    
    %__MODULE__{
      type: failure_type,
      severity: severity,
      scope: scope,
      affected_components: identify_affected_components(failure_symptoms),
      detection_time: DateTime.utc_now(),
      probable_cause: analyze_probable_cause(failure_symptoms, context),
      recovery_strategy: select_recovery_strategy(failure_type, severity, scope),
      impact_assessment: assess_impact(failure_symptoms, context)
    }
  end
  
  @doc """
  Determine appropriate response based on failure classification.
  """
  def determine_response(failure_classification) do
    case {failure_classification.severity, failure_classification.scope} do
      {:critical, :global} -> :emergency_response
      {:critical, :cluster} -> :cluster_failover
      {:high, :node} -> :node_isolation
      {:medium, :local} -> :local_restart
      {:low, _} -> :graceful_degradation
    end
  end
  
  defp determine_failure_type(symptoms) do
    cond do
      symptoms.process_exit_reason -> classify_process_failure(symptoms)
      symptoms.node_down_event -> :node_crash
      symptoms.network_timeout -> classify_network_failure(symptoms)
      symptoms.resource_exhaustion -> classify_resource_failure(symptoms)
      symptoms.inconsistent_state -> :byzantine_behavior
      true -> :unknown_failure
    end
  end
  
  defp assess_severity(failure_type, symptoms, context) do
    base_severity = base_severity_for_type(failure_type)
    
    # Adjust severity based on context
    severity_adjustments = [
      criticality_adjustment(context),
      cascade_risk_adjustment(symptoms),
      recovery_difficulty_adjustment(failure_type)
    ]
    
    apply_severity_adjustments(base_severity, severity_adjustments)
  end
end
```

### Failure Detection System

```elixir
defmodule Phoenix.FailureDetector do
  @moduledoc """
  Comprehensive failure detection system using multiple detection mechanisms.
  
  Detection Methods:
  1. **Heartbeat Monitoring**: Regular health checks
  2. **Performance Monitoring**: Latency and throughput tracking
  3. **Resource Monitoring**: CPU, memory, disk usage
  4. **Network Monitoring**: Connection quality and reachability
  5. **Application Monitoring**: Business logic health indicators
  """
  
  use GenServer
  
  defstruct [
    :node_id,
    :monitored_components,
    :detection_thresholds,
    :failure_history,
    :active_detectors,
    :escalation_policies
  ]
  
  @heartbeat_interval 5_000  # 5 seconds
  @failure_threshold 3       # Failed checks before marking as failed
  @recovery_threshold 2      # Successful checks before marking as recovered
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    state = %__MODULE__{
      node_id: Keyword.get(opts, :node_id, node()),
      monitored_components: %{},
      detection_thresholds: default_thresholds(),
      failure_history: [],
      active_detectors: %{},
      escalation_policies: default_escalation_policies()
    }
    
    # Start monitoring subsystems
    start_heartbeat_monitoring()
    start_performance_monitoring()
    start_resource_monitoring()
    
    {:ok, state}
  end
  
  @doc """
  Register component for failure detection monitoring.
  """
  def monitor_component(component_id, component_spec) do
    GenServer.call(__MODULE__, {:monitor_component, component_id, component_spec})
  end
  
  @doc """
  Report suspected failure for investigation.
  """
  def report_suspected_failure(component_id, symptoms) do
    GenServer.cast(__MODULE__, {:suspected_failure, component_id, symptoms})
  end
  
  @doc """
  Get current health status of all monitored components.
  """
  def health_status() do
    GenServer.call(__MODULE__, :health_status)
  end
  
  def handle_call({:monitor_component, component_id, component_spec}, _from, state) do
    # Add component to monitoring
    new_monitored = Map.put(state.monitored_components, component_id, %{
      spec: component_spec,
      status: :healthy,
      last_check: DateTime.utc_now(),
      failure_count: 0,
      recovery_count: 0
    })
    
    # Start detector for this component
    detector_pid = start_component_detector(component_id, component_spec)
    new_detectors = Map.put(state.active_detectors, component_id, detector_pid)
    
    new_state = %{state | 
      monitored_components: new_monitored,
      active_detectors: new_detectors
    }
    
    {:reply, :ok, new_state}
  end
  
  def handle_call(:health_status, _from, state) do
    health_report = state.monitored_components
    |> Enum.map(fn {component_id, component_info} ->
      {component_id, %{
        status: component_info.status,
        last_check: component_info.last_check,
        failure_count: component_info.failure_count
      }}
    end)
    |> Enum.into(%{})
    
    {:reply, health_report, state}
  end
  
  def handle_cast({:suspected_failure, component_id, symptoms}, state) do
    # Investigate suspected failure
    case Map.get(state.monitored_components, component_id) do
      nil ->
        # Unknown component, ignore
        {:noreply, state}
        
      component_info ->
        # Verify failure and update state
        new_state = investigate_failure(component_id, symptoms, component_info, state)
        {:noreply, new_state}
    end
  end
  
  def handle_info({:heartbeat_timeout, component_id}, state) do
    # Component failed to respond to heartbeat
    symptoms = %{
      type: :heartbeat_timeout,
      component_id: component_id,
      timestamp: DateTime.utc_now()
    }
    
    new_state = handle_heartbeat_failure(component_id, symptoms, state)
    {:noreply, new_state}
  end
  
  def handle_info({:performance_degradation, component_id, metrics}, state) do
    # Component showing performance issues
    symptoms = %{
      type: :performance_degradation,
      component_id: component_id,
      metrics: metrics,
      timestamp: DateTime.utc_now()
    }
    
    new_state = investigate_failure(component_id, symptoms, Map.get(state.monitored_components, component_id), state)
    {:noreply, new_state}
  end
  
  defp investigate_failure(component_id, symptoms, component_info, state) do
    # Classify the failure
    failure_classification = Phoenix.FaultModel.classify_failure(symptoms, %{
      component_type: component_info.spec.type,
      criticality: component_info.spec.criticality
    })
    
    # Update failure count
    new_failure_count = component_info.failure_count + 1
    
    # Determine if component should be marked as failed
    if new_failure_count >= @failure_threshold do
      # Mark component as failed and trigger response
      new_component_info = %{component_info | 
        status: :failed,
        failure_count: new_failure_count,
        last_check: DateTime.utc_now()
      }
      
      # Trigger failure response
      trigger_failure_response(component_id, failure_classification)
      
      # Update state
      new_monitored = Map.put(state.monitored_components, component_id, new_component_info)
      new_history = [failure_classification | state.failure_history] |> Enum.take(100)
      
      %{state | 
        monitored_components: new_monitored,
        failure_history: new_history
      }
    else
      # Increment failure count but don't mark as failed yet
      new_component_info = %{component_info | 
        failure_count: new_failure_count,
        last_check: DateTime.utc_now()
      }
      
      new_monitored = Map.put(state.monitored_components, component_id, new_component_info)
      %{state | monitored_components: new_monitored}
    end
  end
  
  defp trigger_failure_response(component_id, failure_classification) do
    response_strategy = Phoenix.FaultModel.determine_response(failure_classification)
    
    case response_strategy do
      :emergency_response -> 
        Phoenix.Emergency.trigger_emergency_response(component_id, failure_classification)
      :cluster_failover -> 
        Phoenix.Cluster.Failover.initiate_failover(component_id, failure_classification)
      :node_isolation -> 
        Phoenix.Node.Isolation.isolate_node(component_id, failure_classification)
      :local_restart -> 
        Phoenix.Local.Recovery.restart_component(component_id, failure_classification)
      :graceful_degradation -> 
        Phoenix.Degradation.enable_degraded_mode(component_id, failure_classification)
    end
  end
  
  defp start_heartbeat_monitoring() do
    # Start heartbeat monitoring process
    spawn_link(fn -> heartbeat_loop() end)
  end
  
  defp heartbeat_loop() do
    # Send heartbeats to all monitored components
    monitored_components = GenServer.call(__MODULE__, :get_monitored_components)
    
    Enum.each(monitored_components, fn {component_id, _spec} ->
      send_heartbeat(component_id)
    end)
    
    :timer.sleep(@heartbeat_interval)
    heartbeat_loop()
  end
end
```

---

## Circuit Breaker Patterns

### Advanced Circuit Breaker Implementation

```elixir
defmodule Phoenix.CircuitBreaker do
  @moduledoc """
  Advanced circuit breaker implementation with multiple states and adaptive thresholds.
  
  States:
  - **Closed**: Normal operation, requests pass through
  - **Open**: Failure threshold exceeded, requests rejected immediately
  - **Half-Open**: Testing recovery, limited requests allowed
  - **Forced-Open**: Manual override, all requests rejected
  - **Forced-Closed**: Manual override, all requests allowed
  """
  
  use GenServer
  
  defstruct [
    :name,
    :state,
    :failure_count,
    :success_count,
    :failure_threshold,
    :success_threshold,
    :timeout,
    :last_failure_time,
    :request_count,
    :adaptive_threshold,
    :window_size,
    :metrics
  ]
  
  @type circuit_state :: :closed | :open | :half_open | :forced_open | :forced_closed
  @type circuit_config :: %{
    failure_threshold: pos_integer(),
    success_threshold: pos_integer(),
    timeout: pos_integer(),
    window_size: pos_integer(),
    adaptive: boolean()
  }
  
  @default_config %{
    failure_threshold: 5,
    success_threshold: 3,
    timeout: 30_000,
    window_size: 100,
    adaptive: true
  }
  
  def start_link(name, config \\ %{}) do
    merged_config = Map.merge(@default_config, config)
    
    GenServer.start_link(__MODULE__, {name, merged_config}, name: via_tuple(name))
  end
  
  def init({name, config}) do
    state = %__MODULE__{
      name: name,
      state: :closed,
      failure_count: 0,
      success_count: 0,
      failure_threshold: config.failure_threshold,
      success_threshold: config.success_threshold,
      timeout: config.timeout,
      last_failure_time: nil,
      request_count: 0,
      adaptive_threshold: config.adaptive,
      window_size: config.window_size,
      metrics: Phoenix.CircuitBreaker.Metrics.new()
    }
    
    {:ok, state}
  end
  
  @doc """
  Execute operation through circuit breaker with protection.
  """
  def call(circuit_name, operation, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5000)
    fallback = Keyword.get(opts, :fallback)
    
    case GenServer.call(via_tuple(circuit_name), :check_state, timeout) do
      :allow ->
        execute_with_monitoring(circuit_name, operation, fallback)
        
      :reject ->
        case fallback do
          nil -> {:error, :circuit_open}
          fallback_fn when is_function(fallback_fn) -> 
            {:ok, fallback_fn.()}
          fallback_value -> 
            {:ok, fallback_value}
        end
    end
  end
  
  @doc """
  Force circuit breaker to specific state (for testing/emergency).
  """
  def force_state(circuit_name, forced_state) when forced_state in [:open, :closed, :reset] do
    GenServer.call(via_tuple(circuit_name), {:force_state, forced_state})
  end
  
  @doc """
  Get current circuit breaker state and metrics.
  """
  def state(circuit_name) do
    GenServer.call(via_tuple(circuit_name), :get_state)
  end
  
  def handle_call(:check_state, _from, state) do
    case state.state do
      :closed ->
        {:reply, :allow, increment_request_count(state)}
        
      :open ->
        if should_attempt_reset?(state) do
          new_state = %{state | state: :half_open}
          {:reply, :allow, increment_request_count(new_state)}
        else
          {:reply, :reject, state}
        end
        
      :half_open ->
        {:reply, :allow, increment_request_count(state)}
        
      :forced_open ->
        {:reply, :reject, state}
        
      :forced_closed ->
        {:reply, :allow, increment_request_count(state)}
    end
  end
  
  def handle_call({:force_state, forced_state}, _from, state) do
    new_state = case forced_state do
      :open -> %{state | state: :forced_open}
      :closed -> %{state | state: :forced_closed}
      :reset -> reset_circuit_breaker(state)
    end
    
    {:reply, :ok, new_state}
  end
  
  def handle_call(:get_state, _from, state) do
    state_info = %{
      state: state.state,
      failure_count: state.failure_count,
      success_count: state.success_count,
      request_count: state.request_count,
      failure_threshold: state.failure_threshold,
      last_failure_time: state.last_failure_time,
      metrics: Phoenix.CircuitBreaker.Metrics.summary(state.metrics)
    }
    
    {:reply, state_info, state}
  end
  
  def handle_cast({:record_success, execution_time}, state) do
    new_metrics = Phoenix.CircuitBreaker.Metrics.record_success(state.metrics, execution_time)
    new_state = %{state | 
      success_count: state.success_count + 1,
      metrics: new_metrics
    }
    
    # Check if circuit should close
    final_state = case state.state do
      :half_open ->
        if new_state.success_count >= state.success_threshold do
          reset_circuit_breaker(new_state)
        else
          new_state
        end
      _ ->
        new_state
    end
    
    # Update adaptive threshold if enabled
    final_state = if state.adaptive_threshold do
      update_adaptive_threshold(final_state)
    else
      final_state
    end
    
    {:noreply, final_state}
  end
  
  def handle_cast({:record_failure, error, execution_time}, state) do
    new_metrics = Phoenix.CircuitBreaker.Metrics.record_failure(state.metrics, error, execution_time)
    new_state = %{state | 
      failure_count: state.failure_count + 1,
      last_failure_time: System.monotonic_time(:millisecond),
      metrics: new_metrics
    }
    
    # Check if circuit should open
    final_state = case state.state do
      :closed ->
        if new_state.failure_count >= state.failure_threshold do
          %{new_state | state: :open}
        else
          new_state
        end
      :half_open ->
        # Failure during half-open immediately opens circuit
        %{new_state | state: :open}
      _ ->
        new_state
    end
    
    # Update adaptive threshold if enabled
    final_state = if state.adaptive_threshold do
      update_adaptive_threshold(final_state)
    else
      final_state
    end
    
    {:noreply, final_state}
  end
  
  defp execute_with_monitoring(circuit_name, operation, fallback) do
    start_time = System.monotonic_time(:microsecond)
    
    try do
      result = operation.()
      execution_time = System.monotonic_time(:microsecond) - start_time
      
      GenServer.cast(via_tuple(circuit_name), {:record_success, execution_time})
      {:ok, result}
      
    rescue
      error ->
        execution_time = System.monotonic_time(:microsecond) - start_time
        GenServer.cast(via_tuple(circuit_name), {:record_failure, error, execution_time})
        
        case fallback do
          nil -> {:error, error}
          fallback_fn when is_function(fallback_fn) -> 
            {:ok, fallback_fn.()}
          fallback_value -> 
            {:ok, fallback_value}
        end
    end
  end
  
  defp should_attempt_reset?(state) do
    case state.last_failure_time do
      nil -> false
      last_failure ->
        current_time = System.monotonic_time(:millisecond)
        current_time - last_failure >= state.timeout
    end
  end
  
  defp reset_circuit_breaker(state) do
    %{state | 
      state: :closed,
      failure_count: 0,
      success_count: 0,
      last_failure_time: nil
    }
  end
  
  defp increment_request_count(state) do
    %{state | request_count: state.request_count + 1}
  end
  
  defp update_adaptive_threshold(state) do
    # Adjust threshold based on recent performance
    recent_failure_rate = calculate_recent_failure_rate(state.metrics)
    
    new_threshold = cond do
      recent_failure_rate > 0.3 -> 
        # High failure rate, lower threshold
        max(2, state.failure_threshold - 1)
      recent_failure_rate < 0.1 -> 
        # Low failure rate, raise threshold
        min(20, state.failure_threshold + 1)
      true -> 
        state.failure_threshold
    end
    
    %{state | failure_threshold: new_threshold}
  end
  
  defp calculate_recent_failure_rate(metrics) do
    Phoenix.CircuitBreaker.Metrics.failure_rate(metrics, window: :recent)
  end
  
  defp via_tuple(name) do
    {:via, Registry, {Phoenix.CircuitBreaker.Registry, name}}
  end
end
```

### Circuit Breaker Metrics

```elixir
defmodule Phoenix.CircuitBreaker.Metrics do
  @moduledoc """
  Comprehensive metrics collection for circuit breaker performance analysis.
  """
  
  defstruct [
    :total_requests,
    :successful_requests,
    :failed_requests,
    :recent_window,
    :response_times,
    :error_types,
    :state_transitions
  ]
  
  @window_size 100
  
  def new() do
    %__MODULE__{
      total_requests: 0,
      successful_requests: 0,
      failed_requests: 0,
      recent_window: :queue.new(),
      response_times: [],
      error_types: %{},
      state_transitions: []
    }
  end
  
  def record_success(metrics, execution_time) do
    new_window = add_to_window(metrics.recent_window, {:success, execution_time})
    
    %{metrics |
      total_requests: metrics.total_requests + 1,
      successful_requests: metrics.successful_requests + 1,
      recent_window: new_window,
      response_times: [execution_time | metrics.response_times] |> Enum.take(1000)
    }
  end
  
  def record_failure(metrics, error, execution_time) do
    error_type = classify_error(error)
    new_window = add_to_window(metrics.recent_window, {:failure, error_type, execution_time})
    
    current_error_count = Map.get(metrics.error_types, error_type, 0)
    new_error_types = Map.put(metrics.error_types, error_type, current_error_count + 1)
    
    %{metrics |
      total_requests: metrics.total_requests + 1,
      failed_requests: metrics.failed_requests + 1,
      recent_window: new_window,
      error_types: new_error_types,
      response_times: [execution_time | metrics.response_times] |> Enum.take(1000)
    }
  end
  
  def failure_rate(metrics, opts \\ []) do
    window = Keyword.get(opts, :window, :total)
    
    case window do
      :total ->
        if metrics.total_requests > 0 do
          metrics.failed_requests / metrics.total_requests
        else
          0.0
        end
        
      :recent ->
        recent_items = :queue.to_list(metrics.recent_window)
        total_recent = length(recent_items)
        
        if total_recent > 0 do
          failures = Enum.count(recent_items, fn
            {:failure, _, _} -> true
            _ -> false
          end)
          failures / total_recent
        else
          0.0
        end
    end
  end
  
  def average_response_time(metrics) do
    if length(metrics.response_times) > 0 do
      Enum.sum(metrics.response_times) / length(metrics.response_times)
    else
      0.0
    end
  end
  
  def percentile_response_time(metrics, percentile) do
    if length(metrics.response_times) > 0 do
      sorted_times = Enum.sort(metrics.response_times)
      index = round(length(sorted_times) * percentile / 100) - 1
      index = max(0, min(index, length(sorted_times) - 1))
      Enum.at(sorted_times, index)
    else
      0.0
    end
  end
  
  def summary(metrics) do
    %{
      total_requests: metrics.total_requests,
      success_rate: success_rate(metrics),
      failure_rate: failure_rate(metrics),
      recent_failure_rate: failure_rate(metrics, window: :recent),
      average_response_time: average_response_time(metrics),
      p95_response_time: percentile_response_time(metrics, 95),
      p99_response_time: percentile_response_time(metrics, 99),
      error_distribution: metrics.error_types
    }
  end
  
  defp success_rate(metrics) do
    if metrics.total_requests > 0 do
      metrics.successful_requests / metrics.total_requests
    else
      0.0
    end
  end
  
  defp add_to_window(window, item) do
    new_window = :queue.in(item, window)
    
    if :queue.len(new_window) > @window_size do
      {_removed, trimmed_window} = :queue.out(new_window)
      trimmed_window
    else
      new_window
    end
  end
  
  defp classify_error(error) do
    case error do
      %{__exception__: true} -> error.__struct__
      {:timeout, _} -> :timeout
      {:error, reason} -> reason
      _ -> :unknown
    end
  end
end
```

---

## Bulkhead Isolation Strategies

### Resource Pool Implementation

```elixir
defmodule Phoenix.Bulkhead.ResourcePool do
  @moduledoc """
  Resource pool implementation for bulkhead isolation.
  
  Features:
  - Configurable pool sizes per resource type
  - Queue management with timeouts
  - Resource health monitoring
  - Spillover to other pools when exhausted
  - Circuit breaker integration
  """
  
  use GenServer
  
  defstruct [
    :pool_name,
    :resource_type,
    :max_size,
    :current_size,
    :available_resources,
    :checked_out_resources,
    :waiting_queue,
    :health_monitor,
    :spillover_pools,
    :circuit_breaker
  ]
  
  @default_timeout 5_000
  @health_check_interval 10_000
  
  def start_link(opts) do
    pool_name = Keyword.fetch!(opts, :pool_name)
    
    GenServer.start_link(__MODULE__, opts, name: via_tuple(pool_name))
  end
  
  def init(opts) do
    pool_name = Keyword.fetch!(opts, :pool_name)
    resource_type = Keyword.fetch!(opts, :resource_type)
    max_size = Keyword.get(opts, :max_size, 10)
    
    state = %__MODULE__{
      pool_name: pool_name,
      resource_type: resource_type,
      max_size: max_size,
      current_size: 0,
      available_resources: :queue.new(),
      checked_out_resources: %{},
      waiting_queue: :queue.new(),
      health_monitor: Phoenix.ResourceHealthMonitor.new(),
      spillover_pools: Keyword.get(opts, :spillover_pools, []),
      circuit_breaker: Keyword.get(opts, :circuit_breaker)
    }
    
    # Pre-populate pool with initial resources
    initial_size = Keyword.get(opts, :initial_size, min(3, max_size))
    populated_state = populate_pool(state, initial_size)
    
    # Start health monitoring
    schedule_health_check()
    
    {:ok, populated_state}
  end
  
  @doc """
  Checkout resource from pool with timeout.
  """
  def checkout(pool_name, timeout \\ @default_timeout) do
    GenServer.call(via_tuple(pool_name), {:checkout, self()}, timeout)
  end
  
  @doc """
  Return resource to pool.
  """
  def checkin(pool_name, resource) do
    GenServer.cast(via_tuple(pool_name), {:checkin, resource})
  end
  
  @doc """
  Execute operation with automatic resource management.
  """
  def with_resource(pool_name, operation, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)
    
    case checkout(pool_name, timeout) do
      {:ok, resource} ->
        try do
          operation.(resource)
        after
          checkin(pool_name, resource)
        end
        
      {:error, :timeout} ->
        # Try spillover pools
        attempt_spillover(pool_name, operation, opts)
        
      error ->
        error
    end
  end
  
  @doc """
  Get pool statistics.
  """
  def stats(pool_name) do
    GenServer.call(via_tuple(pool_name), :stats)
  end
  
  def handle_call({:checkout, caller_pid}, from, state) do
    case :queue.out(state.available_resources) do
      {{:value, resource}, new_available} ->
        # Resource available immediately
        monitor_ref = Process.monitor(caller_pid)
        new_checked_out = Map.put(state.checked_out_resources, monitor_ref, {resource, caller_pid})
        
        new_state = %{state | 
          available_resources: new_available,
          checked_out_resources: new_checked_out
        }
        
        {:reply, {:ok, resource}, new_state}
        
      {:empty, _} ->
        # No resources available
        cond do
          state.current_size < state.max_size ->
            # Can create new resource
            case create_resource(state.resource_type) do
              {:ok, resource} ->
                monitor_ref = Process.monitor(caller_pid)
                new_checked_out = Map.put(state.checked_out_resources, monitor_ref, {resource, caller_pid})
                
                new_state = %{state | 
                  current_size: state.current_size + 1,
                  checked_out_resources: new_checked_out
                }
                
                {:reply, {:ok, resource}, new_state}
                
              {:error, _reason} ->
                # Queue the request
                new_waiting = :queue.in(from, state.waiting_queue)
                {:noreply, %{state | waiting_queue: new_waiting}}
            end
            
          true ->
            # Pool at capacity, queue the request
            new_waiting = :queue.in(from, state.waiting_queue)
            {:noreply, %{state | waiting_queue: new_waiting}}
        end
    end
  end
  
  def handle_call(:stats, _from, state) do
    stats = %{
      pool_name: state.pool_name,
      max_size: state.max_size,
      current_size: state.current_size,
      available: :queue.len(state.available_resources),
      checked_out: map_size(state.checked_out_resources),
      waiting: :queue.len(state.waiting_queue),
      utilization: map_size(state.checked_out_resources) / state.max_size
    }
    
    {:reply, stats, state}
  end
  
  def handle_cast({:checkin, resource}, state) do
    # Resource returned to pool
    case :queue.out(state.waiting_queue) do
      {{:value, waiting_caller}, new_waiting} ->
        # Someone is waiting, give resource directly
        GenServer.reply(waiting_caller, {:ok, resource})
        {:noreply, %{state | waiting_queue: new_waiting}}
        
      {:empty, _} ->
        # No one waiting, return to pool
        new_available = :queue.in(resource, state.available_resources)
        {:noreply, %{state | available_resources: new_available}}
    end
  end
  
  def handle_info({:DOWN, monitor_ref, :process, _pid, _reason}, state) do
    # Process that checked out resource died
    case Map.pop(state.checked_out_resources, monitor_ref) do
      {{resource, _pid}, new_checked_out} ->
        # Return resource to pool (may need cleanup)
        cleaned_resource = cleanup_resource(resource)
        new_available = :queue.in(cleaned_resource, state.available_resources)
        
        new_state = %{state | 
          available_resources: new_available,
          checked_out_resources: new_checked_out
        }
        
        {:noreply, new_state}
        
      {nil, _} ->
        # Unknown monitor reference
        {:noreply, state}
    end
  end
  
  def handle_info(:health_check, state) do
    # Perform health check on available resources
    {healthy_resources, unhealthy_count} = health_check_resources(state.available_resources)
    
    # Replace unhealthy resources
    new_state = if unhealthy_count > 0 do
      replace_unhealthy_resources(state, unhealthy_count, healthy_resources)
    else
      %{state | available_resources: healthy_resources}
    end
    
    schedule_health_check()
    {:noreply, new_state}
  end
  
  defp attempt_spillover(pool_name, operation, opts) do
    # Get spillover pools configuration
    spillover_pools = GenServer.call(via_tuple(pool_name), :get_spillover_pools)
    
    # Try each spillover pool
    Enum.find_value(spillover_pools, fn spillover_pool ->
      case with_resource(spillover_pool, operation, opts) do
        {:error, :timeout} -> nil
        result -> result
      end
    end) || {:error, :resource_unavailable}
  end
  
  defp populate_pool(state, count) do
    resources = for _ <- 1..count do
      case create_resource(state.resource_type) do
        {:ok, resource} -> resource
        {:error, _} -> nil
      end
    end
    |> Enum.filter(&(&1 != nil))
    
    new_available = Enum.reduce(resources, state.available_resources, fn resource, acc ->
      :queue.in(resource, acc)
    end)
    
    %{state | 
      available_resources: new_available,
      current_size: length(resources)
    }
  end
  
  defp create_resource(resource_type) do
    case resource_type do
      :database_connection -> create_database_connection()
      :http_client -> create_http_client()
      :worker_process -> create_worker_process()
      _ -> {:error, :unknown_resource_type}
    end
  end
  
  defp cleanup_resource(resource) do
    # Cleanup resource state before returning to pool
    # Implementation depends on resource type
    resource
  end
  
  defp health_check_resources(available_resources) do
    resources_list = :queue.to_list(available_resources)
    
    {healthy, unhealthy_count} = Enum.reduce(resources_list, {[], 0}, fn resource, {healthy_acc, unhealthy_count} ->
      if resource_healthy?(resource) do
        {[resource | healthy_acc], unhealthy_count}
      else
        {healthy_acc, unhealthy_count + 1}
      end
    end)
    
    healthy_queue = Enum.reduce(healthy, :queue.new(), fn resource, acc ->
      :queue.in(resource, acc)
    end)
    
    {healthy_queue, unhealthy_count}
  end
  
  defp schedule_health_check() do
    Process.send_after(self(), :health_check, @health_check_interval)
  end
  
  defp via_tuple(pool_name) do
    {:via, Registry, {Phoenix.Bulkhead.ResourcePool.Registry, pool_name}}
  end
  
  # Placeholder implementations
  defp create_database_connection(), do: {:ok, :db_connection}
  defp create_http_client(), do: {:ok, :http_client}
  defp create_worker_process(), do: {:ok, :worker_process}
  defp resource_healthy?(_resource), do: true
end
```

### Isolation Boundaries

```elixir
defmodule Phoenix.Bulkhead.IsolationBoundary do
  @moduledoc """
  Defines and enforces isolation boundaries between different system components.
  
  Features:
  - Resource quotas per isolation boundary
  - Traffic shaping and rate limiting
  - Priority-based resource allocation
  - Cascading failure prevention
  """
  
  defstruct [
    :boundary_name,
    :resource_quotas,
    :current_usage,
    :priority_levels,
    :rate_limiters,
    :circuit_breakers
  ]
  
  @doc """
  Define isolation boundary with resource constraints.
  """
  def define_boundary(boundary_name, config) do
    %__MODULE__{
      boundary_name: boundary_name,
      resource_quotas: Map.get(config, :quotas, %{}),
      current_usage: %{},
      priority_levels: Map.get(config, :priorities, %{}),
      rate_limiters: initialize_rate_limiters(config),
      circuit_breakers: initialize_circuit_breakers(config)
    }
  end
  
  @doc """
  Check if operation is allowed within isolation boundary.
  """
  def check_allowance(boundary, operation_spec) do
    with :ok <- check_resource_quota(boundary, operation_spec),
         :ok <- check_rate_limits(boundary, operation_spec),
         :ok <- check_circuit_breakers(boundary, operation_spec) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end
  
  @doc """
  Execute operation within isolation boundary with resource tracking.
  """
  def execute_within_boundary(boundary, operation, operation_spec) do
    case check_allowance(boundary, operation_spec) do
      :ok ->
        # Reserve resources
        updated_boundary = reserve_resources(boundary, operation_spec)
        
        try do
          result = operation.()
          
          # Record successful execution
          record_execution_success(updated_boundary, operation_spec)
          {:ok, result}
          
        rescue
          error ->
            # Record failure and release resources
            record_execution_failure(updated_boundary, operation_spec, error)
            {:error, error}
        after
          # Always release resources
          release_resources(updated_boundary, operation_spec)
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end
  
  defp check_resource_quota(boundary, operation_spec) do
    required_resources = Map.get(operation_spec, :resources, %{})
    
    Enum.find_value(required_resources, :ok, fn {resource_type, required_amount} ->
      quota = Map.get(boundary.resource_quotas, resource_type, :unlimited)
      current = Map.get(boundary.current_usage, resource_type, 0)
      
      case quota do
        :unlimited -> nil
        quota_limit when current + required_amount <= quota_limit -> nil
        _exceeded -> {:error, {:quota_exceeded, resource_type}}
      end
    end)
  end
  
  defp check_rate_limits(boundary, operation_spec) do
    operation_type = Map.get(operation_spec, :type, :default)
    
    case Map.get(boundary.rate_limiters, operation_type) do
      nil -> :ok
      rate_limiter -> 
        Phoenix.RateLimiter.check_limit(rate_limiter, operation_spec)
    end
  end
  
  defp check_circuit_breakers(boundary, operation_spec) do
    operation_type = Map.get(operation_spec, :type, :default)
    
    case Map.get(boundary.circuit_breakers, operation_type) do
      nil -> :ok
      circuit_breaker -> 
        case Phoenix.CircuitBreaker.state(circuit_breaker) do
          %{state: :open} -> {:error, :circuit_open}
          _ -> :ok
        end
    end
  end
  
  defp reserve_resources(boundary, operation_spec) do
    required_resources = Map.get(operation_spec, :resources, %{})
    
    new_usage = Enum.reduce(required_resources, boundary.current_usage, fn {resource_type, amount}, acc ->
      current = Map.get(acc, resource_type, 0)
      Map.put(acc, resource_type, current + amount)
    end)
    
    %{boundary | current_usage: new_usage}
  end
  
  defp release_resources(boundary, operation_spec) do
    required_resources = Map.get(operation_spec, :resources, %{})
    
    new_usage = Enum.reduce(required_resources, boundary.current_usage, fn {resource_type, amount}, acc ->
      current = Map.get(acc, resource_type, 0)
      Map.put(acc, resource_type, max(0, current - amount))
    end)
    
    %{boundary | current_usage: new_usage}
  end
  
  defp initialize_rate_limiters(config) do
    rate_limits = Map.get(config, :rate_limits, %{})
    
    Enum.map(rate_limits, fn {operation_type, limit_config} ->
      {operation_type, Phoenix.RateLimiter.new(limit_config)}
    end)
    |> Enum.into(%{})
  end
  
  defp initialize_circuit_breakers(config) do
    circuit_configs = Map.get(config, :circuit_breakers, %{})
    
    Enum.map(circuit_configs, fn {operation_type, breaker_config} ->
      breaker_name = "#{config.boundary_name}_#{operation_type}"
      {:ok, _pid} = Phoenix.CircuitBreaker.start_link(breaker_name, breaker_config)
      {operation_type, breaker_name}
    end)
    |> Enum.into(%{})
  end
  
  defp record_execution_success(boundary, operation_spec) do
    # Record metrics for successful execution
    Phoenix.Metrics.increment("bulkhead.execution.success", %{
      boundary: boundary.boundary_name,
      operation_type: Map.get(operation_spec, :type, :default)
    })
  end
  
  defp record_execution_failure(boundary, operation_spec, error) do
    # Record metrics for failed execution
    Phoenix.Metrics.increment("bulkhead.execution.failure", %{
      boundary: boundary.boundary_name,
      operation_type: Map.get(operation_spec, :type, :default),
      error_type: classify_error(error)
    })
  end
  
  defp classify_error(error) do
    case error do
      %{__exception__: true} -> error.__struct__
      _ -> :unknown
    end
  end
end
```

---

## Network Partition Detection

### Partition Detection Algorithm

```elixir
defmodule Phoenix.PartitionDetector do
  @moduledoc """
  Network partition detection using multiple detection mechanisms.
  
  Detection Methods:
  1. **Heartbeat Monitoring**: Node-to-node heartbeats
  2. **Connectivity Probing**: Direct network connectivity tests
  3. **Consensus Participation**: Monitoring consensus protocol participation
  4. **External Witnesses**: Third-party partition detection services
  5. **Application-Level Indicators**: Business logic health checks
  """
  
  use GenServer
  
  defstruct [
    :node_id,
    :cluster_nodes,
    :heartbeat_intervals,
    :connectivity_map,
    :partition_history,
    :detection_thresholds,
    :external_witnesses
  ]
  
  @heartbeat_interval 2_000     # 2 seconds
  @partition_threshold 3        # Failed heartbeats before partition suspected
  @connectivity_timeout 1_000   # 1 second for connectivity probes
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    node_id = Keyword.get(opts, :node_id, node())
    cluster_nodes = Keyword.get(opts, :cluster_nodes, [node()])
    
    state = %__MODULE__{
      node_id: node_id,
      cluster_nodes: cluster_nodes,
      heartbeat_intervals: %{},
      connectivity_map: %{},
      partition_history: [],
      detection_thresholds: default_thresholds(),
      external_witnesses: Keyword.get(opts, :external_witnesses, [])
    }
    
    # Initialize connectivity monitoring
    initialize_monitoring(state)
    
    # Start heartbeat process
    schedule_heartbeat()
    
    {:ok, state}
  end
  
  @doc """
  Add node to partition monitoring.
  """
  def monitor_node(node) do
    GenServer.cast(__MODULE__, {:monitor_node, node})
  end
  
  @doc """
  Remove node from partition monitoring.
  """
  def stop_monitoring_node(node) do
    GenServer.cast(__MODULE__, {:stop_monitoring_node, node})
  end
  
  @doc """
  Get current partition status.
  """
  def partition_status() do
    GenServer.call(__MODULE__, :partition_status)
  end
  
  @doc """
  Trigger manual partition check.
  """
  def check_partitions() do
    GenServer.cast(__MODULE__, :check_partitions)
  end
  
  def handle_call(:partition_status, _from, state) do
    status = %{
      node_id: state.node_id,
      monitored_nodes: state.cluster_nodes,
      connectivity_map: state.connectivity_map,
      recent_partitions: Enum.take(state.partition_history, 10),
      detection_active: true
    }
    
    {:reply, status, state}
  end
  
  def handle_cast({:monitor_node, node}, state) do
    if node not in state.cluster_nodes do
      new_cluster_nodes = [node | state.cluster_nodes]
      new_connectivity_map = Map.put(state.connectivity_map, node, %{
        status: :unknown,
        last_heartbeat: nil,
        failed_heartbeats: 0,
        last_connectivity_check: nil
      })
      
      new_state = %{state | 
        cluster_nodes: new_cluster_nodes,
        connectivity_map: new_connectivity_map
      }
      
      {:noreply, new_state}
    else
      {:noreply, state}
    end
  end
  
  def handle_cast({:stop_monitoring_node, node}, state) do
    new_cluster_nodes = List.delete(state.cluster_nodes, node)
    new_connectivity_map = Map.delete(state.connectivity_map, node)
    
    new_state = %{state | 
      cluster_nodes: new_cluster_nodes,
      connectivity_map: new_connectivity_map
    }
    
    {:noreply, new_state}
  end
  
  def handle_cast(:check_partitions, state) do
    new_state = perform_partition_detection(state)
    {:noreply, new_state}
  end
  
  def handle_info(:heartbeat, state) do
    # Send heartbeats to all monitored nodes
    new_state = send_heartbeats(state)
    
    schedule_heartbeat()
    {:noreply, new_state}
  end
  
  def handle_info({:heartbeat_response, from_node}, state) do
    # Received heartbeat response from node
    new_state = record_heartbeat_response(state, from_node)
    {:noreply, new_state}
  end
  
  def handle_info({:heartbeat_timeout, node}, state) do
    # Heartbeat timeout for specific node
    new_state = handle_heartbeat_timeout(state, node)
    {:noreply, new_state}
  end
  
  def handle_info(:connectivity_check, state) do
    # Perform direct connectivity checks
    new_state = perform_connectivity_checks(state)
    
    schedule_connectivity_check()
    {:noreply, new_state}
  end
  
  defp perform_partition_detection(state) do
    # Multi-method partition detection
    detection_results = %{
      heartbeat_detection: detect_partitions_by_heartbeat(state),
      connectivity_detection: detect_partitions_by_connectivity(state),
      consensus_detection: detect_partitions_by_consensus(state),
      witness_detection: detect_partitions_by_witnesses(state)
    }
    
    # Aggregate detection results
    partition_decision = aggregate_detection_results(detection_results, state.detection_thresholds)
    
    case partition_decision do
      {:partition_detected, partitioned_nodes} ->
        # Partition detected, trigger response
        partition_event = %{
          type: :partition_detected,
          timestamp: DateTime.utc_now(),
          partitioned_nodes: partitioned_nodes,
          detection_methods: detection_results,
          detector_node: state.node_id
        }
        
        # Record partition in history
        new_history = [partition_event | state.partition_history] |> Enum.take(100)
        
        # Trigger partition response
        Phoenix.PartitionHandler.handle_partition(partition_event)
        
        %{state | partition_history: new_history}
        
      {:partition_healed, healed_nodes} ->
        # Partition healed, trigger recovery
        heal_event = %{
          type: :partition_healed,
          timestamp: DateTime.utc_now(),
          healed_nodes: healed_nodes,
          detector_node: state.node_id
        }
        
        # Record heal in history
        new_history = [heal_event | state.partition_history] |> Enum.take(100)
        
        # Trigger heal response
        Phoenix.PartitionHandler.handle_partition_heal(heal_event)
        
        %{state | partition_history: new_history}
        
      :no_partition ->
        # No partition detected
        state
    end
  end
  
  defp detect_partitions_by_heartbeat(state) do
    # Check heartbeat failures
    partitioned_nodes = state.connectivity_map
    |> Enum.filter(fn {_node, info} ->
      info.failed_heartbeats >= @partition_threshold
    end)
    |> Enum.map(fn {node, _info} -> node end)
    
    if length(partitioned_nodes) > 0 do
      {:partition_detected, partitioned_nodes}
    else
      :no_partition
    end
  end
  
  defp detect_partitions_by_connectivity(state) do
    # Perform direct connectivity tests
    unreachable_nodes = state.cluster_nodes
    |> Enum.filter(fn node -> node != state.node_id end)
    |> Enum.filter(fn node -> not node_reachable?(node) end)
    
    if length(unreachable_nodes) > 0 do
      {:partition_detected, unreachable_nodes}
    else
      :no_partition
    end
  end
  
  defp detect_partitions_by_consensus(state) do
    # Check consensus protocol participation
    case Phoenix.Consensus.get_cluster_status() do
      {:ok, status} ->
        non_participating_nodes = status.cluster_nodes -- status.participating_nodes
        
        if length(non_participating_nodes) > 0 do
          {:partition_detected, non_participating_nodes}
        else
          :no_partition
        end
        
      {:error, _reason} ->
        # Consensus system unavailable
        :consensus_unavailable
    end
  end
  
  defp detect_partitions_by_witnesses(state) do
    # Query external witnesses
    witness_results = Enum.map(state.external_witnesses, fn witness ->
      query_witness(witness, state.cluster_nodes)
    end)
    
    # Aggregate witness responses
    aggregate_witness_results(witness_results)
  end
  
  defp aggregate_detection_results(results, thresholds) do
    # Combine results from different detection methods
    detections = results
    |> Enum.filter(fn {_method, result} -> 
      match?({:partition_detected, _}, result)
    end)
    |> Enum.map(fn {_method, {:partition_detected, nodes}} -> nodes end)
    
    if length(detections) >= Map.get(thresholds, :min_detection_methods, 2) do
      # Multiple methods agree on partition
      common_nodes = find_common_nodes(detections)
      
      if length(common_nodes) > 0 do
        {:partition_detected, common_nodes}
      else
        :no_partition
      end
    else
      :no_partition
    end
  end
  
  defp send_heartbeats(state) do
    # Send heartbeat to each monitored node
    Enum.each(state.cluster_nodes, fn node ->
      if node != state.node_id do
        send_heartbeat_to_node(node)
      end
    end)
    
    state
  end
  
  defp send_heartbeat_to_node(node) do
    # Send heartbeat message with timeout
    spawn(fn ->
      try do
        :rpc.call(node, Phoenix.PartitionDetector, :receive_heartbeat, [node()], @connectivity_timeout)
        send(Phoenix.PartitionDetector, {:heartbeat_response, node})
      catch
        _, _ ->
          send(Phoenix.PartitionDetector, {:heartbeat_timeout, node})
      end
    end)
  end
  
  def receive_heartbeat(from_node) do
    # Heartbeat receiver function (called by remote nodes)
    send(Phoenix.PartitionDetector, {:heartbeat_response, from_node})
    :ok
  end
  
  defp record_heartbeat_response(state, from_node) do
    # Update connectivity info for responding node
    case Map.get(state.connectivity_map, from_node) do
      nil -> state  # Node not monitored
      info ->
        updated_info = %{info | 
          status: :reachable,
          last_heartbeat: DateTime.utc_now(),
          failed_heartbeats: 0
        }
        
        new_connectivity_map = Map.put(state.connectivity_map, from_node, updated_info)
        %{state | connectivity_map: new_connectivity_map}
    end
  end
  
  defp handle_heartbeat_timeout(state, node) do
    # Handle heartbeat timeout for specific node
    case Map.get(state.connectivity_map, node) do
      nil -> state  # Node not monitored
      info ->
        updated_info = %{info | 
          failed_heartbeats: info.failed_heartbeats + 1
        }
        
        # Check if partition threshold reached
        if updated_info.failed_heartbeats >= @partition_threshold do
          updated_info = %{updated_info | status: :partitioned}
        end
        
        new_connectivity_map = Map.put(state.connectivity_map, node, updated_info)
        %{state | connectivity_map: new_connectivity_map}
    end
  end
  
  defp node_reachable?(node) do
    # Direct connectivity test
    try do
      :net_adm.ping(node) == :pong
    catch
      _, _ -> false
    end
  end
  
  defp schedule_heartbeat() do
    Process.send_after(self(), :heartbeat, @heartbeat_interval)
  end
  
  defp schedule_connectivity_check() do
    Process.send_after(self(), :connectivity_check, @heartbeat_interval * 2)
  end
  
  defp initialize_monitoring(state) do
    # Initialize connectivity map for all nodes
    initial_connectivity = Enum.reduce(state.cluster_nodes, %{}, fn node, acc ->
      if node != state.node_id do
        Map.put(acc, node, %{
          status: :unknown,
          last_heartbeat: nil,
          failed_heartbeats: 0,
          last_connectivity_check: nil
        })
      else
        acc
      end
    end)
    
    %{state | connectivity_map: initial_connectivity}
  end
  
  defp default_thresholds() do
    %{
      min_detection_methods: 2,
      heartbeat_threshold: @partition_threshold,
      connectivity_threshold: @connectivity_timeout
    }
  end
  
  # Placeholder implementations
  defp query_witness(_witness, _nodes), do: :no_partition
  defp aggregate_witness_results(_results), do: :no_partition
  defp find_common_nodes(node_lists) do
    case node_lists do
      [] -> []
      [first | rest] -> 
        Enum.reduce(rest, first, fn nodes, acc ->
          Enum.filter(acc, &(&1 in nodes))
        end)
    end
  end
end
```

---

## Partition Response Strategies

### Multi-Strategy Partition Handler

```elixir
defmodule Phoenix.PartitionHandler do
  @moduledoc """
  Comprehensive partition response strategies based on system configuration and partition characteristics.
  
  Strategies:
  1. **Pause Minority**: Minority partition stops operations
  2. **Continue All**: All partitions continue with conflict resolution later  
  3. **Primary Partition**: Only primary partition continues operations
  4. **Quorum-Based**: Operations continue only with quorum
  5. **Application-Specific**: Custom business logic for partition handling
  """
  
  use GenServer
  
  defstruct [
    :node_id,
    :partition_strategy,
    :cluster_membership,
    :partition_state,
    :active_partitions,
    :strategy_config
  ]
  
  @type partition_strategy :: 
    :pause_minority |
    :continue_all |
    :primary_partition |
    :quorum_based |
    :application_specific
    
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    state = %__MODULE__{
      node_id: Keyword.get(opts, :node_id, node()),
      partition_strategy: Keyword.get(opts, :strategy, :quorum_based),
      cluster_membership: %{},
      partition_state: :normal,
      active_partitions: [],
      strategy_config: Keyword.get(opts, :strategy_config, %{})
    }
    
    {:ok, state}
  end
  
  @doc """
  Handle detected network partition.
  """
  def handle_partition(partition_event) do
    GenServer.cast(__MODULE__, {:handle_partition, partition_event})
  end
  
  @doc """
  Handle partition healing.
  """
  def handle_partition_heal(heal_event) do
    GenServer.cast(__MODULE__, {:handle_partition_heal, heal_event})
  end
  
  @doc """
  Get current partition status.
  """
  def partition_status() do
    GenServer.call(__MODULE__, :partition_status)
  end
  
  @doc """
  Override partition strategy temporarily.
  """
  def set_strategy(strategy, config \\ %{}) do
    GenServer.call(__MODULE__, {:set_strategy, strategy, config})
  end
  
  def handle_call(:partition_status, _from, state) do
    status = %{
      partition_state: state.partition_state,
      active_partitions: state.active_partitions,
      strategy: state.partition_strategy,
      node_id: state.node_id
    }
    
    {:reply, status, state}
  end
  
  def handle_call({:set_strategy, strategy, config}, _from, state) do
    new_state = %{state | 
      partition_strategy: strategy,
      strategy_config: Map.merge(state.strategy_config, config)
    }
    
    {:reply, :ok, new_state}
  end
  
  def handle_cast({:handle_partition, partition_event}, state) do
    # Determine partition response based on strategy
    response_plan = determine_response_plan(partition_event, state)
    
    # Execute response plan
    new_state = execute_partition_response(response_plan, partition_event, state)
    
    {:noreply, new_state}
  end
  
  def handle_cast({:handle_partition_heal, heal_event}, state) do
    # Handle partition healing
    new_state = execute_partition_heal(heal_event, state)
    
    {:noreply, new_state}
  end
  
  defp determine_response_plan(partition_event, state) do
    case state.partition_strategy do
      :pause_minority ->
        plan_pause_minority_response(partition_event, state)
        
      :continue_all ->
        plan_continue_all_response(partition_event, state)
        
      :primary_partition ->
        plan_primary_partition_response(partition_event, state)
        
      :quorum_based ->
        plan_quorum_based_response(partition_event, state)
        
      :application_specific ->
        plan_application_specific_response(partition_event, state)
    end
  end
  
  defp plan_pause_minority_response(partition_event, state) do
    all_nodes = get_all_cluster_nodes()
    reachable_nodes = all_nodes -- partition_event.partitioned_nodes
    
    if length(reachable_nodes) <= length(all_nodes) / 2 do
      # We're in minority, pause operations
      %{
        action: :pause_operations,
        reason: :minority_partition,
        affected_nodes: [state.node_id],
        recovery_condition: :partition_heal
      }
    else
      # We're in majority, continue operations
      %{
        action: :continue_operations,
        reason: :majority_partition,
        affected_nodes: partition_event.partitioned_nodes,
        pause_nodes: partition_event.partitioned_nodes
      }
    end
  end
  
  defp plan_continue_all_response(partition_event, state) do
    # All partitions continue, conflicts resolved later
    %{
      action: :continue_operations,
      reason: :conflict_resolution_strategy,
      affected_nodes: [],
      conflict_resolution: :enabled,
      reconciliation: :on_heal
    }
  end
  
  defp plan_primary_partition_response(partition_event, state) do
    primary_nodes = Map.get(state.strategy_config, :primary_nodes, [])
    
    if state.node_id in primary_nodes do
      # We're in primary partition, continue operations
      %{
        action: :continue_operations,
        reason: :primary_partition,
        affected_nodes: partition_event.partitioned_nodes,
        pause_nodes: partition_event.partitioned_nodes -- primary_nodes
      }
    else
      # We're not in primary partition, pause operations
      %{
        action: :pause_operations,
        reason: :non_primary_partition,
        affected_nodes: [state.node_id],
        recovery_condition: :primary_accessible
      }
    end
  end
  
  defp plan_quorum_based_response(partition_event, state) do
    all_nodes = get_all_cluster_nodes()
    reachable_nodes = all_nodes -- partition_event.partitioned_nodes
    quorum_size = Map.get(state.strategy_config, :quorum_size, div(length(all_nodes), 2) + 1)
    
    if length(reachable_nodes) >= quorum_size do
      # We have quorum, continue operations
      %{
        action: :continue_operations,
        reason: :quorum_maintained,
        affected_nodes: partition_event.partitioned_nodes,
        quorum_size: quorum_size,
        reachable_nodes: reachable_nodes
      }
    else
      # No quorum, pause operations
      %{
        action: :pause_operations,
        reason: :quorum_lost,
        affected_nodes: reachable_nodes,
        recovery_condition: :quorum_restored
      }
    end
  end
  
  defp plan_application_specific_response(partition_event, state) do
    # Custom application logic for partition handling
    handler_module = Map.get(state.strategy_config, :handler_module)
    
    if handler_module do
      handler_module.handle_partition(partition_event, state)
    else
      # Fall back to quorum-based strategy
      plan_quorum_based_response(partition_event, state)
    end
  end
  
  defp execute_partition_response(response_plan, partition_event, state) do
    case response_plan.action do
      :pause_operations ->
        execute_pause_operations(response_plan, state)
        
      :continue_operations ->
        execute_continue_operations(response_plan, state)
    end
    
    # Update partition state
    new_partition_state = case response_plan.action do
      :pause_operations -> :paused
      :continue_operations -> :degraded
    end
    
    new_active_partitions = [partition_event | state.active_partitions]
    
    %{state | 
      partition_state: new_partition_state,
      active_partitions: new_active_partitions
    }
  end
  
  defp execute_pause_operations(response_plan, state) do
    # Pause critical operations
    Phoenix.Agent.Supervisor.pause_all_agents()
    Phoenix.Signal.Bus.pause_signal_processing()
    Phoenix.Cluster.Registry.enter_readonly_mode()
    
    # Emit partition event
    :telemetry.execute([:phoenix, :partition, :operations_paused], %{}, %{
      node: state.node_id,
      reason: response_plan.reason
    })
    
    Logger.warn("Phoenix operations paused due to partition: #{inspect(response_plan.reason)}")
  end
  
  defp execute_continue_operations(response_plan, state) do
    # Continue operations with degraded mode
    Phoenix.Agent.Supervisor.enable_degraded_mode()
    Phoenix.Signal.Bus.enable_partition_mode()
    Phoenix.Cluster.Registry.enable_partition_tolerance()
    
    # Emit partition event
    :telemetry.execute([:phoenix, :partition, :degraded_mode], %{}, %{
      node: state.node_id,
      reason: response_plan.reason
    })
    
    Logger.info("Phoenix entering degraded mode due to partition: #{inspect(response_plan.reason)}")
  end
  
  defp execute_partition_heal(heal_event, state) do
    # Resume normal operations
    Phoenix.Agent.Supervisor.resume_normal_mode()
    Phoenix.Signal.Bus.resume_normal_mode()
    Phoenix.Cluster.Registry.exit_readonly_mode()
    
    # Trigger reconciliation if needed
    if requires_reconciliation?(state) do
      Phoenix.StateReconciliation.trigger_reconciliation(heal_event)
    end
    
    # Clear active partitions
    %{state | 
      partition_state: :normal,
      active_partitions: []
    }
  end
  
  defp get_all_cluster_nodes() do
    [node() | Node.list()]
  end
  
  defp requires_reconciliation?(state) do
    # Check if state reconciliation is needed after partition heal
    state.partition_state in [:degraded, :paused] and 
    length(state.active_partitions) > 0
  end
end
```

---

## Recovery and Reconciliation

### State Reconciliation Engine

```elixir
defmodule Phoenix.StateReconciliation do
  @moduledoc """
  Comprehensive state reconciliation after partition healing.
  
  Features:
  - CRDT-based automatic reconciliation
  - Vector clock conflict detection
  - Manual conflict resolution for critical data
  - Incremental reconciliation for large datasets
  - Rollback capabilities for failed reconciliation
  """
  
  use GenServer
  
  defstruct [
    :reconciliation_id,
    :participating_nodes,
    :reconciliation_state,
    :conflict_registry,
    :resolution_strategies,
    :progress_tracker
  ]
  
  @type reconciliation_state :: :idle | :collecting | :analyzing | :resolving | :applying | :complete | :failed
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    state = %__MODULE__{
      reconciliation_id: nil,
      participating_nodes: [],
      reconciliation_state: :idle,
      conflict_registry: %{},
      resolution_strategies: default_resolution_strategies(),
      progress_tracker: %{}
    }
    
    {:ok, state}
  end
  
  @doc """
  Trigger state reconciliation after partition heal.
  """
  def trigger_reconciliation(heal_event) do
    GenServer.call(__MODULE__, {:trigger_reconciliation, heal_event})
  end
  
  @doc """
  Get reconciliation status.
  """
  def reconciliation_status() do
    GenServer.call(__MODULE__, :reconciliation_status)
  end
  
  @doc """
  Register custom conflict resolution strategy.
  """
  def register_resolution_strategy(data_type, strategy_fn) do
    GenServer.call(__MODULE__, {:register_strategy, data_type, strategy_fn})
  end
  
  def handle_call({:trigger_reconciliation, heal_event}, _from, state) do
    if state.reconciliation_state == :idle do
      # Start new reconciliation process
      reconciliation_id = generate_reconciliation_id()
      participating_nodes = determine_participating_nodes(heal_event)
      
      new_state = %{state | 
        reconciliation_id: reconciliation_id,
        participating_nodes: participating_nodes,
        reconciliation_state: :collecting,
        conflict_registry: %{},
        progress_tracker: initialize_progress_tracker(participating_nodes)
      }
      
      # Start reconciliation process
      spawn_link(fn -> execute_reconciliation(new_state) end)
      
      {:reply, {:ok, reconciliation_id}, new_state}
    else
      {:reply, {:error, :reconciliation_in_progress}, state}
    end
  end
  
  def handle_call(:reconciliation_status, _from, state) do
    status = %{
      reconciliation_id: state.reconciliation_id,
      state: state.reconciliation_state,
      participating_nodes: state.participating_nodes,
      conflicts_detected: map_size(state.conflict_registry),
      progress: calculate_progress(state.progress_tracker)
    }
    
    {:reply, status, state}
  end
  
  def handle_call({:register_strategy, data_type, strategy_fn}, _from, state) do
    new_strategies = Map.put(state.resolution_strategies, data_type, strategy_fn)
    {:reply, :ok, %{state | resolution_strategies: new_strategies}}
  end
  
  def handle_cast({:reconciliation_progress, phase, node, status}, state) do
    # Update progress tracking
    new_progress = update_progress(state.progress_tracker, phase, node, status)
    
    new_state = %{state | progress_tracker: new_progress}
    
    # Check if phase is complete
    if phase_complete?(new_progress, phase, state.participating_nodes) do
      advance_to_next_phase(state.reconciliation_state, state)
    end
    
    {:noreply, new_state}
  end
  
  def handle_cast({:reconciliation_complete, result}, state) do
    case result do
      :success ->
        Logger.info("State reconciliation completed successfully: #{state.reconciliation_id}")
        :telemetry.execute([:phoenix, :reconciliation, :success], %{}, %{
          reconciliation_id: state.reconciliation_id,
          participating_nodes: length(state.participating_nodes),
          conflicts_resolved: map_size(state.conflict_registry)
        })
        
      {:failure, reason} ->
        Logger.error("State reconciliation failed: #{state.reconciliation_id}, reason: #{inspect(reason)}")
        :telemetry.execute([:phoenix, :reconciliation, :failure], %{}, %{
          reconciliation_id: state.reconciliation_id,
          reason: reason
        })
    end
    
    # Reset state
    reset_state = %{state | 
      reconciliation_id: nil,
      participating_nodes: [],
      reconciliation_state: :idle,
      conflict_registry: %{},
      progress_tracker: %{}
    }
    
    {:noreply, reset_state}
  end
  
  defp execute_reconciliation(state) do
    try do
      # Phase 1: Collect states from all nodes
      collected_states = collect_states_from_nodes(state.participating_nodes)
      update_reconciliation_state(:analyzing)
      
      # Phase 2: Analyze for conflicts
      conflicts = analyze_state_conflicts(collected_states)
      update_conflict_registry(conflicts)
      update_reconciliation_state(:resolving)
      
      # Phase 3: Resolve conflicts
      resolutions = resolve_conflicts(conflicts, state.resolution_strategies)
      update_reconciliation_state(:applying)
      
      # Phase 4: Apply resolutions
      apply_resolutions(resolutions, state.participating_nodes)
      update_reconciliation_state(:complete)
      
      # Notify completion
      GenServer.cast(__MODULE__, {:reconciliation_complete, :success})
      
    rescue
      error ->
        Logger.error("Reconciliation error: #{inspect(error)}")
        update_reconciliation_state(:failed)
        GenServer.cast(__MODULE__, {:reconciliation_complete, {:failure, error}})
    end
  end
  
  defp collect_states_from_nodes(nodes) do
    # Collect state snapshots from all participating nodes
    collection_tasks = Enum.map(nodes, fn node ->
      Task.async(fn ->
        case :rpc.call(node, Phoenix.StateSnapshot, :create_snapshot, [], 30_000) do
          {:badrpc, reason} -> {:error, {node, reason}}
          snapshot -> {:ok, {node, snapshot}}
        end
      end)
    end)
    
    # Wait for all collections to complete
    results = Task.await_many(collection_tasks, 60_000)
    
    # Separate successful and failed collections
    {successful, failed} = Enum.split_with(results, fn
      {:ok, _} -> true
      {:error, _} -> false
    end)
    
    if length(failed) > 0 do
      Logger.warn("Failed to collect states from nodes: #{inspect(failed)}")
    end
    
    successful
    |> Enum.map(fn {:ok, {node, snapshot}} -> {node, snapshot} end)
    |> Enum.into(%{})
  end
  
  defp analyze_state_conflicts(collected_states) do
    # Compare states to identify conflicts
    all_data_keys = collected_states
    |> Map.values()
    |> Enum.flat_map(&Map.keys/1)
    |> Enum.uniq()
    
    conflicts = Enum.reduce(all_data_keys, %{}, fn data_key, acc ->
      values_by_node = collected_states
      |> Enum.map(fn {node, state} -> {node, Map.get(state, data_key)} end)
      |> Enum.filter(fn {_node, value} -> value != nil end)
      |> Enum.into(%{})
      
      if conflicting_values?(values_by_node) do
        Map.put(acc, data_key, values_by_node)
      else
        acc
      end
    end)
    
    conflicts
  end
  
  defp conflicting_values?(values_by_node) when map_size(values_by_node) <= 1, do: false
  defp conflicting_values?(values_by_node) do
    # Check if values are different across nodes
    unique_values = values_by_node
    |> Map.values()
    |> Enum.uniq()
    
    length(unique_values) > 1
  end
  
  defp resolve_conflicts(conflicts, resolution_strategies) do
    # Resolve each conflict using appropriate strategy
    Enum.map(conflicts, fn {data_key, conflicting_values} ->
      data_type = determine_data_type(data_key)
      strategy = Map.get(resolution_strategies, data_type, :last_writer_wins)
      
      resolution = case strategy do
        :last_writer_wins -> resolve_lww(conflicting_values)
        :vector_clock -> resolve_vector_clock(conflicting_values)
        :crdt_merge -> resolve_crdt_merge(conflicting_values)
        :manual -> queue_for_manual_resolution(data_key, conflicting_values)
        custom_fn when is_function(custom_fn) -> custom_fn.(conflicting_values)
      end
      
      {data_key, resolution}
    end)
  end
  
  defp apply_resolutions(resolutions, nodes) do
    # Apply resolved values to all nodes
    application_tasks = Enum.map(nodes, fn node ->
      Task.async(fn ->
        case :rpc.call(node, Phoenix.StateSnapshot, :apply_resolutions, [resolutions], 30_000) do
          {:badrpc, reason} -> {:error, {node, reason}}
          :ok -> {:ok, node}
        end
      end)
    end)
    
    # Wait for all applications to complete
    results = Task.await_many(application_tasks, 60_000)
    
    # Check for failures
    failed_applications = Enum.filter(results, fn
      {:error, _} -> true
      _ -> false
    end)
    
    if length(failed_applications) > 0 do
      raise "Failed to apply resolutions to nodes: #{inspect(failed_applications)}"
    end
    
    :ok
  end
  
  defp resolve_lww(conflicting_values) do
    # Last-writer-wins resolution based on timestamps
    conflicting_values
    |> Enum.max_by(fn {_node, value} -> get_timestamp(value) end)
    |> elem(1)
  end
  
  defp resolve_vector_clock(conflicting_values) do
    # Vector clock based resolution
    vector_clocks = Enum.map(conflicting_values, fn {node, value} ->
      {node, get_vector_clock(value)}
    end)
    
    # Find causally latest value
    find_causally_latest(vector_clocks, conflicting_values)
  end
  
  defp resolve_crdt_merge(conflicting_values) do
    # CRDT merge resolution
    values = Map.values(conflicting_values)
    
    case values do
      [] -> nil
      [single_value] -> single_value
      [first | rest] -> 
        Enum.reduce(rest, first, &Phoenix.CRDT.merge/2)
    end
  end
  
  defp queue_for_manual_resolution(data_key, conflicting_values) do
    # Queue conflict for manual resolution
    Phoenix.ConflictResolution.queue_manual_conflict(%{
      data_key: data_key,
      conflicting_values: conflicting_values,
      timestamp: DateTime.utc_now()
    })
    
    # Return placeholder resolution
    {:manual_resolution_pending, data_key}
  end
  
  # Helper functions
  defp generate_reconciliation_id() do
    "reconciliation_#{System.system_time(:microsecond)}_#{node()}"
  end
  
  defp determine_participating_nodes(heal_event) do
    # Determine which nodes should participate in reconciliation
    all_nodes = [node() | Node.list()]
    healed_nodes = Map.get(heal_event, :healed_nodes, [])
    
    [node() | healed_nodes] |> Enum.uniq() |> Enum.filter(&(&1 in all_nodes))
  end
  
  defp default_resolution_strategies() do
    %{
      agent_state: :crdt_merge,
      configuration: :last_writer_wins,
      metrics: :crdt_merge,
      logs: :vector_clock
    }
  end
  
  defp update_reconciliation_state(new_state) do
    GenServer.cast(__MODULE__, {:update_state, new_state})
  end
  
  defp update_conflict_registry(conflicts) do
    GenServer.cast(__MODULE__, {:update_conflicts, conflicts})
  end
  
  defp determine_data_type(data_key) do
    # Determine data type from key pattern
    cond do
      String.contains?(to_string(data_key), "agent") -> :agent_state
      String.contains?(to_string(data_key), "config") -> :configuration
      String.contains?(to_string(data_key), "metric") -> :metrics
      String.contains?(to_string(data_key), "log") -> :logs
      true -> :unknown
    end
  end
  
  defp get_timestamp(value) do
    # Extract timestamp from value metadata
    case value do
      %{metadata: %{timestamp: ts}} -> ts
      %{timestamp: ts} -> ts
      _ -> 0
    end
  end
  
  defp get_vector_clock(value) do
    # Extract vector clock from value metadata
    case value do
      %{metadata: %{vector_clock: vc}} -> vc
      %{vector_clock: vc} -> vc
      _ -> Phoenix.VectorClock.new(node())
    end
  end
  
  defp find_causally_latest(vector_clocks, conflicting_values) do
    # Find the value with the causally latest vector clock
    # This is a simplified implementation
    {_node, latest_clock} = Enum.max_by(vector_clocks, fn {_node, clock} ->
      Phoenix.VectorClock.sum(clock)
    end)
    
    # Return the value associated with the latest clock
    Enum.find_value(conflicting_values, fn {node, value} ->
      if Map.get(vector_clocks, node) == latest_clock do
        value
      end
    end)
  end
  
  defp initialize_progress_tracker(nodes) do
    phases = [:collecting, :analyzing, :resolving, :applying]
    
    for phase <- phases, node <- nodes, into: %{} do
      {{phase, node}, :pending}
    end
  end
  
  defp update_progress(tracker, phase, node, status) do
    Map.put(tracker, {phase, node}, status)
  end
  
  defp calculate_progress(tracker) do
    completed = tracker |> Map.values() |> Enum.count(&(&1 == :completed))
    total = map_size(tracker)
    
    if total > 0 do
      completed / total
    else
      0.0
    end
  end
  
  defp phase_complete?(tracker, phase, nodes) do
    Enum.all?(nodes, fn node ->
      Map.get(tracker, {phase, node}) == :completed
    end)
  end
  
  defp advance_to_next_phase(current_phase, state) do
    next_phase = case current_phase do
      :collecting -> :analyzing
      :analyzing -> :resolving
      :resolving -> :applying
      :applying -> :complete
      _ -> current_phase
    end
    
    GenServer.cast(__MODULE__, {:update_state, next_phase})
  end
end
```

---

## Graceful Degradation

### Degradation Mode Manager

```elixir
defmodule Phoenix.GracefulDegradation do
  @moduledoc """
  Manages graceful degradation of system functionality during fault conditions.
  
  Degradation Levels:
  1. **Normal**: Full functionality available
  2. **Limited**: Non-critical features disabled
  3. **Essential**: Only core features available
  4. **Emergency**: Minimal functionality for safety
  5. **Shutdown**: Graceful system shutdown
  """
  
  use GenServer
  
  defstruct [
    :current_level,
    :degradation_policies,
    :feature_registry,
    :active_degradations,
    :recovery_conditions
  ]
  
  @type degradation_level :: :normal | :limited | :essential | :emergency | :shutdown
  
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    state = %__MODULE__{
      current_level: :normal,
      degradation_policies: load_degradation_policies(opts),
      feature_registry: %{},
      active_degradations: [],
      recovery_conditions: %{}
    }
    
    {:ok, state}
  end
  
  @doc """
  Register feature with degradation policy.
  """
  def register_feature(feature_name, degradation_policy) do
    GenServer.call(__MODULE__, {:register_feature, feature_name, degradation_policy})
  end
  
  @doc """
  Trigger degradation to specified level.
  """
  def degrade_to_level(level, reason \\ :manual) do
    GenServer.call(__MODULE__, {:degrade_to_level, level, reason})
  end
  
  @doc """
  Get current degradation status.
  """
  def degradation_status() do
    GenServer.call(__MODULE__, :degradation_status)
  end
  
  @doc """
  Check if feature is available at current degradation level.
  """
  def feature_available?(feature_name) do
    GenServer.call(__MODULE__, {:feature_available, feature_name})
  end
  
  @doc """
  Attempt recovery to higher level.
  """
  def attempt_recovery() do
    GenServer.cast(__MODULE__, :attempt_recovery)
  end
  
  def handle_call({:register_feature, feature_name, policy}, _from, state) do
    new_registry = Map.put(state.feature_registry, feature_name, policy)
    {:reply, :ok, %{state | feature_registry: new_registry}}
  end
  
  def handle_call({:degrade_to_level, target_level, reason}, _from, state) do
    if should_allow_degradation?(state.current_level, target_level) do
      new_state = execute_degradation(state, target_level, reason)
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :degradation_not_allowed}, state}
    end
  end
  
  def handle_call(:degradation_status, _from, state) do
    status = %{
      current_level: state.current_level,
      active_degradations: state.active_degradations,
      available_features: get_available_features(state),
      degraded_features: get_degraded_features(state)
    }
    
    {:reply, status, state}
  end
  
  def handle_call({:feature_available, feature_name}, _from, state) do
    available = is_feature_available?(feature_name, state.current_level, state)
    {:reply, available, state}
  end
  
  def handle_cast(:attempt_recovery, state) do
    new_state = attempt_level_recovery(state)
    {:noreply, new_state}
  end
  
  defp execute_degradation(state, target_level, reason) do
    # Apply degradation policies
    degradation_actions = determine_degradation_actions(state.current_level, target_level, state)
    
    # Execute degradation actions
    Enum.each(degradation_actions, &execute_degradation_action/1)
    
    # Record degradation
    degradation_record = %{
      from_level: state.current_level,
      to_level: target_level,
      reason: reason,
      timestamp: DateTime.utc_now(),
      actions: degradation_actions
    }
    
    new_active_degradations = [degradation_record | state.active_degradations]
    
    # Update recovery conditions
    new_recovery_conditions = determine_recovery_conditions(target_level, reason)
    
    # Emit telemetry
    :telemetry.execute([:phoenix, :degradation, :level_changed], %{}, %{
      from_level: state.current_level,
      to_level: target_level,
      reason: reason
    })
    
    Logger.warn("System degraded from #{state.current_level} to #{target_level}, reason: #{reason}")
    
    %{state | 
      current_level: target_level,
      active_degradations: new_active_degradations,
      recovery_conditions: new_recovery_conditions
    }
  end
  
  defp determine_degradation_actions(from_level, to_level, state) do
    # Determine what actions to take based on degradation level change
    level_order = [:normal, :limited, :essential, :emergency, :shutdown]
    
    from_index = Enum.find_index(level_order, &(&1 == from_level))
    to_index = Enum.find_index(level_order, &(&1 == to_level))
    
    if to_index > from_index do
      # Degrading - disable features
      levels_to_disable = Enum.slice(level_order, (from_index + 1)..to_index)
      
      Enum.flat_map(levels_to_disable, fn level ->
        get_features_for_level(level, state)
        |> Enum.map(fn feature -> {:disable_feature, feature} end)
      end)
    else
      # Recovering - enable features
      levels_to_enable = Enum.slice(level_order, to_index..(from_index - 1))
      
      Enum.flat_map(levels_to_enable, fn level ->
        get_features_for_level(level, state)
        |> Enum.map(fn feature -> {:enable_feature, feature} end)
      end)
    end
  end
  
  defp execute_degradation_action({:disable_feature, feature}) do
    case feature.type do
      :agent_pool -> 
        Phoenix.Agent.Supervisor.disable_pool(feature.name)
      :signal_processor -> 
        Phoenix.Signal.Bus.disable_processor(feature.name)
      :registry_service -> 
        Phoenix.Cluster.Registry.disable_service(feature.name)
      :custom -> 
        if feature.disable_callback do
          feature.disable_callback.()
        end
    end
    
    Logger.info("Disabled feature: #{feature.name}")
  end
  
  defp execute_degradation_action({:enable_feature, feature}) do
    case feature.type do
      :agent_pool -> 
        Phoenix.Agent.Supervisor.enable_pool(feature.name)
      :signal_processor -> 
        Phoenix.Signal.Bus.enable_processor(feature.name)
      :registry_service -> 
        Phoenix.Cluster.Registry.enable_service(feature.name)
      :custom -> 
        if feature.enable_callback do
          feature.enable_callback.()
        end
    end
    
    Logger.info("Enabled feature: #{feature.name}")
  end
  
  defp attempt_level_recovery(state) do
    # Check if conditions are met for recovery
    current_conditions = evaluate_recovery_conditions(state.recovery_conditions)
    
    case determine_recovery_level(current_conditions, state.current_level) do
      {:recover_to, new_level} ->
        execute_degradation(state, new_level, :recovery)
        
      :no_recovery ->
        state
    end
  end
  
  defp evaluate_recovery_conditions(conditions) do
    # Evaluate current system state against recovery conditions
    Enum.map(conditions, fn {condition_type, condition_spec} ->
      result = case condition_type do
        :node_connectivity -> check_node_connectivity(condition_spec)
        :resource_availability -> check_resource_availability(condition_spec)
        :error_rate -> check_error_rate(condition_spec)
        :custom -> evaluate_custom_condition(condition_spec)
      end
      
      {condition_type, result}
    end)
    |> Enum.into(%{})
  end
  
  defp determine_recovery_level(conditions, current_level) do
    # Determine if recovery is possible based on condition results
    recovery_possible = Enum.all?(conditions, fn {_type, result} -> result == :ok end)
    
    if recovery_possible do
      case current_level do
        :emergency -> {:recover_to, :essential}
        :essential -> {:recover_to, :limited}
        :limited -> {:recover_to, :normal}
        _ -> :no_recovery
      end
    else
      :no_recovery
    end
  end
  
  defp should_allow_degradation?(current_level, target_level) do
    # Check if degradation transition is allowed
    level_order = [:normal, :limited, :essential, :emergency, :shutdown]
    
    current_index = Enum.find_index(level_order, &(&1 == current_level))
    target_index = Enum.find_index(level_order, &(&1 == target_level))
    
    target_index != nil and current_index != nil
  end
  
  defp get_available_features(state) do
    state.feature_registry
    |> Enum.filter(fn {feature_name, _policy} ->
      is_feature_available?(feature_name, state.current_level, state)
    end)
    |> Enum.map(fn {feature_name, _policy} -> feature_name end)
  end
  
  defp get_degraded_features(state) do
    state.feature_registry
    |> Enum.filter(fn {feature_name, _policy} ->
      not is_feature_available?(feature_name, state.current_level, state)
    end)
    |> Enum.map(fn {feature_name, _policy} -> feature_name end)
  end
  
  defp is_feature_available?(feature_name, current_level, state) do
    case Map.get(state.feature_registry, feature_name) do
      nil -> false
      policy -> 
        required_level = Map.get(policy, :required_level, :normal)
        level_allows_feature?(current_level, required_level)
    end
  end
  
  defp level_allows_feature?(current_level, required_level) do
    level_order = [:normal, :limited, :essential, :emergency, :shutdown]
    
    current_index = Enum.find_index(level_order, &(&1 == current_level))
    required_index = Enum.find_index(level_order, &(&1 == required_level))
    
    current_index <= required_index
  end
  
  defp get_features_for_level(level, state) do
    state.feature_registry
    |> Enum.filter(fn {_name, policy} ->
      Map.get(policy, :required_level) == level
    end)
    |> Enum.map(fn {name, policy} -> Map.put(policy, :name, name) end)
  end
  
  defp load_degradation_policies(opts) do
    # Load degradation policies from configuration
    Keyword.get(opts, :policies, default_degradation_policies())
  end
  
  defp default_degradation_policies() do
    %{
      network_partition: %{
        trigger_level: :essential,
        recovery_conditions: [:node_connectivity]
      },
      resource_exhaustion: %{
        trigger_level: :limited,
        recovery_conditions: [:resource_availability]
      },
      high_error_rate: %{
        trigger_level: :limited,
        recovery_conditions: [:error_rate]
      }
    }
  end
  
  defp determine_recovery_conditions(level, reason) do
    # Determine what conditions must be met for recovery
    case {level, reason} do
      {:essential, :network_partition} ->
        %{node_connectivity: %{min_nodes: 2}}
      {:limited, :resource_exhaustion} ->
        %{resource_availability: %{min_memory: 80, min_cpu: 20}}
      _ ->
        %{}
    end
  end
  
  # Placeholder condition checkers
  defp check_node_connectivity(_spec), do: :ok
  defp check_resource_availability(_spec), do: :ok
  defp check_error_rate(_spec), do: :ok
  defp evaluate_custom_condition(_spec), do: :ok
end
```

---

## Chaos Engineering Integration

### Fault Injection Framework

```elixir
defmodule Phoenix.ChaosEngineering do
  @moduledoc """
  Chaos engineering framework for testing fault tolerance capabilities.
  
  Features:
  - Configurable fault injection scenarios
  - Safe fault boundaries and rollback mechanisms
  - Automated experiment orchestration
  - Metrics collection and analysis
  - Integration with monitoring systems
  """
  
  use GenServer
  
  defstruct [
    :experiment_registry,
    :active_experiments,
    :fault_injectors,
    :safety_monitors,
    :experiment_results
  ]
  
  @doc """
  Start chaos engineering system.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(opts) do
    state = %__MODULE__{
      experiment_registry: %{},
      active_experiments: %{},
      fault_injectors: initialize_fault_injectors(),
      safety_monitors: initialize_safety_monitors(),
      experiment_results: []
    }
    
    {:ok, state}
  end
  
  @doc """
  Define chaos experiment.
  """
  def define_experiment(experiment_spec) do
    GenServer.call(__MODULE__, {:define_experiment, experiment_spec})
  end
  
  @doc """
  Run chaos experiment.
  """
  def run_experiment(experiment_id, opts \\ []) do
    GenServer.call(__MODULE__, {:run_experiment, experiment_id, opts})
  end
  
  @doc """
  Stop running experiment.
  """
  def stop_experiment(experiment_id) do
    GenServer.call(__MODULE__, {:stop_experiment, experiment_id})
  end
  
  @doc """
  Get experiment results.
  """
  def get_experiment_results(experiment_id) do
    GenServer.call(__MODULE__, {:get_results, experiment_id})
  end
  
  def handle_call({:define_experiment, experiment_spec}, _from, state) do
    experiment_id = generate_experiment_id()
    
    validated_spec = validate_experiment_spec(experiment_spec)
    
    case validated_spec do
      {:ok, spec} ->
        new_registry = Map.put(state.experiment_registry, experiment_id, spec)
        {:reply, {:ok, experiment_id}, %{state | experiment_registry: new_registry}}
        
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call({:run_experiment, experiment_id, opts}, _from, state) do
    case Map.get(state.experiment_registry, experiment_id) do
      nil ->
        {:reply, {:error, :experiment_not_found}, state}
        
      experiment_spec ->
        case start_experiment(experiment_spec, opts, state) do
          {:ok, experiment_state} ->
            new_active = Map.put(state.active_experiments, experiment_id, experiment_state)
            {:reply, {:ok, experiment_id}, %{state | active_experiments: new_active}}
            
          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
    end
  end
  
  def handle_call({:stop_experiment, experiment_id}, _from, state) do
    case Map.get(state.active_experiments, experiment_id) do
      nil ->
        {:reply, {:error, :experiment_not_active}, state}
        
      experiment_state ->
        stop_result = stop_experiment_execution(experiment_state)
        new_active = Map.delete(state.active_experiments, experiment_id)
        
        {:reply, {:ok, stop_result}, %{state | active_experiments: new_active}}
    end
  end
  
  def handle_call({:get_results, experiment_id}, _from, state) do
    results = Enum.filter(state.experiment_results, fn result ->
      result.experiment_id == experiment_id
    end)
    
    {:reply, results, state}
  end
  
  defp start_experiment(experiment_spec, opts, state) do
    # Check safety conditions
    case check_safety_conditions(experiment_spec, state) do
      :safe ->
        # Start fault injection
        {:ok, injector_state} = start_fault_injection(experiment_spec)
        
        # Start monitoring
        {:ok, monitor_state} = start_experiment_monitoring(experiment_spec)
        
        experiment_state = %{
          spec: experiment_spec,
          injector_state: injector_state,
          monitor_state: monitor_state,
          start_time: DateTime.utc_now(),
          status: :running
        }
        
        {:ok, experiment_state}
        
      {:unsafe, reason} ->
        {:error, {:safety_violation, reason}}
    end
  end
  
  defp check_safety_conditions(experiment_spec, state) do
    # Check if it's safe to run the experiment
    safety_checks = [
      :cluster_health_check,
      :resource_availability_check,
      :concurrent_experiment_check,
      :blast_radius_check
    ]
    
    Enum.find_value(safety_checks, :safe, fn check ->
      case perform_safety_check(check, experiment_spec, state) do
        :ok -> nil
        {:error, reason} -> {:unsafe, reason}
      end
    end)
  end
  
  defp perform_safety_check(:cluster_health_check, _spec, _state) do
    # Check overall cluster health
    case Phoenix.HealthMonitor.cluster_health() do
      :healthy -> :ok
      :degraded -> {:error, :cluster_degraded}
      :unhealthy -> {:error, :cluster_unhealthy}
    end
  end
  
  defp perform_safety_check(:resource_availability_check, spec, _state) do
    # Check if enough resources are available
    required_resources = Map.get(spec, :required_resources, %{})
    available_resources = Phoenix.ResourceMonitor.available_resources()
    
    sufficient = Enum.all?(required_resources, fn {resource, amount} ->
      Map.get(available_resources, resource, 0) >= amount
    end)
    
    if sufficient do
      :ok
    else
      {:error, :insufficient_resources}
    end
  end
  
  defp perform_safety_check(:concurrent_experiment_check, _spec, state) do
    # Check if too many experiments are running
    max_concurrent = 3
    
    if map_size(state.active_experiments) < max_concurrent do
      :ok
    else
      {:error, :too_many_concurrent_experiments}
    end
  end
  
  defp perform_safety_check(:blast_radius_check, spec, _state) do
    # Check if experiment blast radius is acceptable
    blast_radius = Map.get(spec, :blast_radius, :unknown)
    
    case blast_radius do
      :node -> :ok
      :service -> :ok
      :cluster -> {:error, :blast_radius_too_large}
      :unknown -> {:error, :blast_radius_undefined}
    end
  end
  
  defp start_fault_injection(experiment_spec) do
    fault_type = Map.get(experiment_spec, :fault_type)
    fault_config = Map.get(experiment_spec, :fault_config, %{})
    
    case fault_type do
      :network_partition ->
        Phoenix.FaultInjection.NetworkPartition.start(fault_config)
        
      :process_kill ->
        Phoenix.FaultInjection.ProcessKill.start(fault_config)
        
      :resource_exhaustion ->
        Phoenix.FaultInjection.ResourceExhaustion.start(fault_config)
        
      :latency_injection ->
        Phoenix.FaultInjection.LatencyInjection.start(fault_config)
        
      :message_loss ->
        Phoenix.FaultInjection.MessageLoss.start(fault_config)
        
      custom_type ->
        {:error, {:unsupported_fault_type, custom_type}}
    end
  end
  
  defp start_experiment_monitoring(experiment_spec) do
    # Start monitoring for experiment metrics
    metrics_to_monitor = Map.get(experiment_spec, :metrics, default_metrics())
    
    monitor_state = %{
      metrics: metrics_to_monitor,
      baseline_values: collect_baseline_metrics(metrics_to_monitor),
      monitoring_pid: spawn_monitor_process(metrics_to_monitor)
    }
    
    {:ok, monitor_state}
  end
  
  defp stop_experiment_execution(experiment_state) do
    # Stop fault injection
    stop_fault_injection(experiment_state.injector_state)
    
    # Stop monitoring and collect results
    final_metrics = collect_final_metrics(experiment_state.monitor_state)
    
    # Calculate experiment results
    experiment_result = %{
      experiment_id: experiment_state.spec.id,
      start_time: experiment_state.start_time,
      end_time: DateTime.utc_now(),
      baseline_metrics: experiment_state.monitor_state.baseline_values,
      final_metrics: final_metrics,
      fault_type: experiment_state.spec.fault_type,
      outcome: determine_experiment_outcome(experiment_state, final_metrics)
    }
    
    # Store results
    GenServer.cast(__MODULE__, {:store_result, experiment_result})
    
    experiment_result
  end
  
  defp determine_experiment_outcome(experiment_state, final_metrics) do
    # Determine if experiment showed expected resilience
    baseline = experiment_state.monitor_state.baseline_values
    success_criteria = Map.get(experiment_state.spec, :success_criteria, default_success_criteria())
    
    criteria_met = Enum.all?(success_criteria, fn {metric, criteria} ->
      baseline_value = Map.get(baseline, metric, 0)
      final_value = Map.get(final_metrics, metric, 0)
      
      evaluate_success_criteria(metric, baseline_value, final_value, criteria)
    end)
    
    if criteria_met do
      :success  # System showed expected resilience
    else
      :failure  # System did not meet resilience expectations
    end
  end
  
  defp evaluate_success_criteria(metric, baseline, final, criteria) do
    case criteria.type do
      :max_degradation ->
        degradation = abs(final - baseline) / baseline
        degradation <= criteria.threshold
        
      :recovery_time ->
        # This would need time-series data
        true  # Simplified for example
        
      :availability ->
        final >= criteria.min_value
    end
  end
  
  # Helper functions and placeholders
  defp generate_experiment_id() do
    "chaos_#{System.system_time(:microsecond)}"
  end
  
  defp validate_experiment_spec(spec) do
    required_fields = [:fault_type, :target, :duration]
    
    missing_fields = Enum.filter(required_fields, fn field ->
      not Map.has_key?(spec, field)
    end)
    
    if Enum.empty?(missing_fields) do
      {:ok, spec}
    else
      {:error, {:missing_fields, missing_fields}}
    end
  end
  
  defp initialize_fault_injectors() do
    %{
      network_partition: Phoenix.FaultInjection.NetworkPartition,
      process_kill: Phoenix.FaultInjection.ProcessKill,
      resource_exhaustion: Phoenix.FaultInjection.ResourceExhaustion,
      latency_injection: Phoenix.FaultInjection.LatencyInjection,
      message_loss: Phoenix.FaultInjection.MessageLoss
    }
  end
  
  defp initialize_safety_monitors() do
    %{}  # Implementation would include various safety monitors
  end
  
  defp default_metrics() do
    [:response_time, :error_rate, :throughput, :availability]
  end
  
  defp default_success_criteria() do
    %{
      response_time: %{type: :max_degradation, threshold: 0.5},  # 50% max degradation
      error_rate: %{type: :max_degradation, threshold: 0.1},    # 10% max increase
      availability: %{type: :availability, min_value: 0.95}     # 95% minimum availability
    }
  end
  
  defp collect_baseline_metrics(_metrics) do
    # Collect baseline metrics before experiment
    %{
      response_time: 100.0,
      error_rate: 0.01,
      throughput: 1000.0,
      availability: 0.99
    }
  end
  
  defp collect_final_metrics(_monitor_state) do
    # Collect final metrics after experiment
    %{
      response_time: 120.0,
      error_rate: 0.02,
      throughput: 950.0,
      availability: 0.98
    }
  end
  
  defp spawn_monitor_process(_metrics) do
    spawn(fn -> monitor_metrics_loop() end)
  end
  
  defp monitor_metrics_loop() do
    # Monitoring loop implementation
    :timer.sleep(1000)
    monitor_metrics_loop()
  end
  
  defp stop_fault_injection(_injector_state) do
    # Stop fault injection
    :ok
  end
end
```

---

## Summary and Integration

### Fault Tolerance Architecture Summary

Phoenix's fault tolerance system provides comprehensive resilience through:

1. **Multi-Layered Detection**: Heartbeat, performance, resource, and application-level monitoring
2. **Adaptive Circuit Breakers**: Dynamic thresholds with performance metrics
3. **Resource Isolation**: Bulkhead patterns with configurable resource pools
4. **Intelligent Partition Handling**: Multiple strategies based on system requirements
5. **Automated Recovery**: State reconciliation with CRDT-based conflict resolution
6. **Graceful Degradation**: Configurable degradation levels with automatic recovery
7. **Chaos Engineering**: Built-in fault injection for resilience testing

### Integration Points

- **CRDT System**: Fault tolerance leverages CRDT state management for conflict-free recovery
- **Communication Layer**: Circuit breakers protect communication protocols
- **Agent Management**: Degradation policies control agent availability during faults
- **Monitoring System**: Comprehensive telemetry for fault detection and analysis

### Next Document Preview

The next document will cover **Performance Optimization and Scaling**, providing detailed specifications for:

- Adaptive load balancing algorithms
- Resource-aware agent placement strategies
- Performance monitoring and optimization
- Horizontal scaling patterns and automation

**This fault tolerance foundation ensures Phoenix maintains availability and consistency even under adverse conditions, providing the reliability required for production distributed agent systems.**

---

**Document Version**: 1.0  
**Next Review**: 2025-07-19  
**Implementation Priority**: High  
**Dependencies**: Phoenix CRDT State Management (Part 3)