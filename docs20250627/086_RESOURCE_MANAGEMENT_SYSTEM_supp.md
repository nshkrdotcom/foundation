# RESOURCE_MANAGEMENT_SYSTEM_supp.md

## Executive Summary

This supplementary document provides comprehensive designs for agent resource management, quota enforcement, and resource optimization in the Foundation MABEAM system. It includes detailed specifications for resource limits, enforcement mechanisms, monitoring systems, and graceful degradation strategies to ensure fair resource allocation and system stability.

**Scope**: Complete resource management system with quota enforcement and optimization
**Target**: Production-ready resource governance for multi-agent environments

## 1. Resource Management Architecture

### 1.1 Resource Types and Hierarchies

#### Resource Type Definitions
```elixir
defmodule Foundation.ResourceManagement.Types do
  @moduledoc """
  Comprehensive resource type definitions for multi-agent resource management.
  """
  
  @type resource_type :: 
    :memory | :cpu | :disk | :network | :processes | :files | :connections | :custom
  
  @type resource_unit ::
    :bytes | :percentage | :milliseconds | :count | :bytes_per_second | :custom_unit
  
  @type resource_spec :: %{
    type: resource_type(),
    unit: resource_unit(),
    total_available: non_neg_integer(),
    reserved_system: non_neg_integer(),
    allocatable: non_neg_integer()
  }
  
  @type resource_limit :: %{
    type: resource_type(),
    soft_limit: non_neg_integer(),
    hard_limit: non_neg_integer(),
    burst_limit: non_neg_integer(),
    enforcement_action: enforcement_action()
  }
  
  @type enforcement_action ::
    :warn | :throttle | :suspend | :terminate | :scale_down | :custom_handler
  
  # System resource specifications
  @system_resources %{
    memory: %{
      type: :memory,
      unit: :bytes,
      total_available: :erlang.memory(:total),
      reserved_system: div(:erlang.memory(:total), 4),  # 25% reserved
      allocatable: div(:erlang.memory(:total) * 3, 4)   # 75% allocatable
    },
    cpu: %{
      type: :cpu,
      unit: :percentage,
      total_available: 100 * :erlang.system_info(:logical_processors),
      reserved_system: 20 * :erlang.system_info(:logical_processors),  # 20% reserved
      allocatable: 80 * :erlang.system_info(:logical_processors)       # 80% allocatable
    },
    processes: %{
      type: :processes,
      unit: :count,
      total_available: :erlang.system_info(:process_limit),
      reserved_system: div(:erlang.system_info(:process_limit), 10),   # 10% reserved
      allocatable: div(:erlang.system_info(:process_limit) * 9, 10)    # 90% allocatable
    },
    files: %{
      type: :files,
      unit: :count,
      total_available: 10_000,  # Configurable
      reserved_system: 1_000,   # 10% reserved
      allocatable: 9_000        # 90% allocatable
    },
    network: %{
      type: :network,
      unit: :bytes_per_second,
      total_available: 1_000_000_000,  # 1 Gbps
      reserved_system: 100_000_000,    # 100 Mbps reserved
      allocatable: 900_000_000         # 900 Mbps allocatable
    }
  }
  
  @spec get_system_resource_spec(resource_type()) :: {:ok, resource_spec()} | {:error, :not_found}
  def get_system_resource_spec(resource_type) do
    case Map.get(@system_resources, resource_type) do
      nil -> {:error, :not_found}
      spec -> {:ok, spec}
    end
  end
  
  @spec calculate_available_resources() :: %{resource_type() => non_neg_integer()}
  def calculate_available_resources() do
    Enum.map(@system_resources, fn {type, spec} ->
      current_usage = get_current_resource_usage(type)
      available = max(0, spec.allocatable - current_usage)
      {type, available}
    end)
    |> Map.new()
  end
  
  defp get_current_resource_usage(:memory) do
    :erlang.memory(:processes)
  end
  
  defp get_current_resource_usage(:processes) do
    length(Process.list())
  end
  
  defp get_current_resource_usage(:cpu) do
    # CPU usage calculation would require monitoring
    calculate_cpu_usage()
  end
  
  defp get_current_resource_usage(_type) do
    0  # Placeholder for other resource types
  end
end
```

### 1.2 Resource Quota Management

#### Quota Definition and Enforcement
```elixir
defmodule Foundation.ResourceManagement.QuotaManager do
  @moduledoc """
  Manages resource quotas for agents and enforces limits with configurable actions.
  """
  
  use GenServer
  alias Foundation.ResourceManagement.{Types, Monitor, Enforcer}
  
  @type agent_quota :: %{
    agent_id: String.t(),
    resource_limits: %{Types.resource_type() => Types.resource_limit()},
    current_usage: %{Types.resource_type() => non_neg_integer()},
    quota_group: atom(),
    priority: integer(),
    created_at: DateTime.t(),
    updated_at: DateTime.t()
  }
  
  @type quota_group :: %{
    name: atom(),
    description: String.t(),
    default_limits: %{Types.resource_type() => Types.resource_limit()},
    total_group_limit: %{Types.resource_type() => non_neg_integer()},
    scaling_policy: scaling_policy()
  }
  
  # Predefined quota groups for different agent types
  @quota_groups %{
    lightweight_agent: %{
      name: :lightweight_agent,
      description: "Lightweight agents with minimal resource requirements",
      default_limits: %{
        memory: %{soft_limit: 50_000_000, hard_limit: 100_000_000, enforcement_action: :warn},
        cpu: %{soft_limit: 5, hard_limit: 10, enforcement_action: :throttle},
        processes: %{soft_limit: 10, hard_limit: 20, enforcement_action: :suspend}
      },
      total_group_limit: %{memory: 1_000_000_000, cpu: 200, processes: 500}
    },
    standard_agent: %{
      name: :standard_agent,
      description: "Standard agents with moderate resource requirements",
      default_limits: %{
        memory: %{soft_limit: 200_000_000, hard_limit: 500_000_000, enforcement_action: :throttle},
        cpu: %{soft_limit: 15, hard_limit: 30, enforcement_action: :throttle},
        processes: %{soft_limit: 50, hard_limit: 100, enforcement_action: :scale_down}
      },
      total_group_limit: %{memory: 4_000_000_000, cpu: 600, processes: 2000}
    },
    heavy_computation_agent: %{
      name: :heavy_computation_agent,
      description: "Agents requiring significant computational resources",
      default_limits: %{
        memory: %{soft_limit: 1_000_000_000, hard_limit: 2_000_000_000, enforcement_action: :suspend},
        cpu: %{soft_limit: 40, hard_limit: 80, enforcement_action: :scale_down},
        processes: %{soft_limit: 100, hard_limit: 200, enforcement_action: :terminate}
      },
      total_group_limit: %{memory: 8_000_000_000, cpu: 1600, processes: 1000}
    }
  }
  
  # GenServer Implementation
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Initialize ETS tables for fast quota lookups
    :ets.new(:agent_quotas, [:named_table, :set, :public, {:read_concurrency, true}])
    :ets.new(:quota_groups, [:named_table, :set, :public, {:read_concurrency, true}])
    :ets.new(:resource_usage_cache, [:named_table, :set, :public, {:read_concurrency, true}])
    
    # Load predefined quota groups
    Enum.each(@quota_groups, fn {group_name, group_spec} ->
      :ets.insert(:quota_groups, {group_name, group_spec})
    end)
    
    # Start resource monitoring
    schedule_resource_monitoring()
    
    {:ok, %{
      monitoring_interval: 5_000,  # 5 seconds
      enforcement_enabled: true,
      quota_violations: %{}
    }}
  end
  
  # Public API
  @spec create_agent_quota(String.t(), atom(), keyword()) :: 
    {:ok, agent_quota()} | {:error, term()}
  def create_agent_quota(agent_id, quota_group, custom_limits \\ []) do
    GenServer.call(__MODULE__, {:create_agent_quota, agent_id, quota_group, custom_limits})
  end
  
  @spec get_agent_quota(String.t()) :: {:ok, agent_quota()} | {:error, :not_found}
  def get_agent_quota(agent_id) do
    case :ets.lookup(:agent_quotas, agent_id) do
      [{^agent_id, quota}] -> {:ok, quota}
      [] -> {:error, :not_found}
    end
  end
  
  @spec update_resource_usage(String.t(), %{Types.resource_type() => non_neg_integer()}) :: :ok
  def update_resource_usage(agent_id, usage_update) do
    GenServer.cast(__MODULE__, {:update_resource_usage, agent_id, usage_update})
  end
  
  @spec check_quota_compliance(String.t()) :: :ok | {:violation, [quota_violation()]}
  def check_quota_compliance(agent_id) do
    case get_agent_quota(agent_id) do
      {:ok, quota} ->
        violations = check_resource_violations(quota)
        case violations do
          [] -> :ok
          violations -> {:violation, violations}
        end
      {:error, :not_found} ->
        {:error, :agent_quota_not_found}
    end
  end
  
  # GenServer Handlers
  def handle_call({:create_agent_quota, agent_id, quota_group, custom_limits}, _from, state) do
    case :ets.lookup(:quota_groups, quota_group) do
      [{^quota_group, group_spec}] ->
        quota = build_agent_quota(agent_id, group_spec, custom_limits)
        :ets.insert(:agent_quotas, {agent_id, quota})
        
        {:reply, {:ok, quota}, state}
      [] ->
        {:reply, {:error, {:unknown_quota_group, quota_group}}, state}
    end
  end
  
  def handle_cast({:update_resource_usage, agent_id, usage_update}, state) do
    case :ets.lookup(:agent_quotas, agent_id) do
      [{^agent_id, quota}] ->
        updated_quota = update_quota_usage(quota, usage_update)
        :ets.insert(:agent_quotas, {agent_id, updated_quota})
        
        # Check for violations and enforce if necessary
        violations = check_resource_violations(updated_quota)
        if not Enum.empty?(violations) and state.enforcement_enabled do
          enforce_quota_violations(agent_id, violations)
        end
        
        {:noreply, state}
      [] ->
        Logger.warn("Received usage update for unknown agent", agent_id: agent_id)
        {:noreply, state}
    end
  end
  
  def handle_info(:monitor_resources, state) do
    # Periodic resource monitoring for all agents
    monitor_all_agent_resources()
    schedule_resource_monitoring()
    {:noreply, state}
  end
  
  # Private Functions
  defp build_agent_quota(agent_id, group_spec, custom_limits) do
    # Merge group defaults with custom limits
    resource_limits = Map.merge(group_spec.default_limits, Map.new(custom_limits))
    
    %{
      agent_id: agent_id,
      resource_limits: resource_limits,
      current_usage: %{},
      quota_group: group_spec.name,
      priority: 5,  # Default priority
      created_at: DateTime.utc_now(),
      updated_at: DateTime.utc_now()
    }
  end
  
  defp check_resource_violations(quota) do
    Enum.reduce(quota.resource_limits, [], fn {resource_type, limits}, violations ->
      current_usage = Map.get(quota.current_usage, resource_type, 0)
      
      cond do
        current_usage > limits.hard_limit ->
          [%{type: :hard_limit, resource: resource_type, current: current_usage, limit: limits.hard_limit} | violations]
        current_usage > limits.soft_limit ->
          [%{type: :soft_limit, resource: resource_type, current: current_usage, limit: limits.soft_limit} | violations]
        true ->
          violations
      end
    end)
  end
  
  defp schedule_resource_monitoring() do
    Process.send_after(self(), :monitor_resources, 5_000)
  end
end
```

## 2. Resource Monitoring and Measurement

### 2.1 Real-Time Resource Monitoring

#### Resource Monitor Implementation
```elixir
defmodule Foundation.ResourceManagement.Monitor do
  @moduledoc """
  Real-time resource monitoring for agents with efficient measurement and reporting.
  """
  
  use GenServer
  alias Foundation.ResourceManagement.{Types, QuotaManager}
  
  @type measurement :: %{
    agent_id: String.t(),
    resource_type: Types.resource_type(),
    value: non_neg_integer(),
    timestamp: DateTime.t(),
    measurement_method: atom()
  }
  
  @type monitoring_config :: %{
    agent_id: String.t(),
    resources_to_monitor: [Types.resource_type()],
    measurement_interval: pos_integer(),
    aggregation_window: pos_integer(),
    alerting_thresholds: %{Types.resource_type() => alert_threshold()}
  }
  
  # Agent Resource Monitor Process
  def start_link(agent_id, config \\ %{}) do
    GenServer.start_link(__MODULE__, {agent_id, config}, name: via_tuple(agent_id))
  end
  
  def init({agent_id, config}) do
    # Initialize monitoring state
    default_config = %{
      resources_to_monitor: [:memory, :cpu, :processes],
      measurement_interval: 1_000,    # 1 second
      aggregation_window: 60_000,     # 1 minute
      alerting_thresholds: %{}
    }
    
    monitoring_config = Map.merge(default_config, config)
    
    # Start periodic monitoring
    schedule_resource_measurement(monitoring_config.measurement_interval)
    
    state = %{
      agent_id: agent_id,
      config: monitoring_config,
      measurements: [],
      agent_pid: find_agent_process(agent_id),
      last_alert_times: %{}
    }
    
    {:ok, state}
  end
  
  def handle_info(:measure_resources, state) do
    # Measure all configured resources for the agent
    measurements = measure_agent_resources(state.agent_pid, state.config.resources_to_monitor)
    
    # Update measurements buffer
    updated_measurements = add_measurements_to_buffer(state.measurements, measurements, state.config.aggregation_window)
    
    # Update quota manager with current usage
    current_usage = calculate_current_usage(measurements)
    QuotaManager.update_resource_usage(state.agent_id, current_usage)
    
    # Check alerting thresholds
    check_alerting_thresholds(measurements, state)
    
    # Schedule next measurement
    schedule_resource_measurement(state.config.measurement_interval)
    
    {:noreply, %{state | measurements: updated_measurements}}
  end
  
  # Resource Measurement Functions
  defp measure_agent_resources(agent_pid, resource_types) when is_pid(agent_pid) do
    Enum.map(resource_types, fn resource_type ->
      value = measure_resource_for_process(agent_pid, resource_type)
      
      %{
        resource_type: resource_type,
        value: value,
        timestamp: DateTime.utc_now(),
        measurement_method: get_measurement_method(resource_type)
      }
    end)
  end
  
  defp measure_agent_resources(nil, _resource_types) do
    # Agent process not found
    []
  end
  
  defp measure_resource_for_process(pid, :memory) do
    case Process.info(pid, :memory) do
      {:memory, memory_bytes} -> memory_bytes
      nil -> 0
    end
  end
  
  defp measure_resource_for_process(pid, :message_queue_len) do
    case Process.info(pid, :message_queue_len) do
      {:message_queue_len, queue_len} -> queue_len
      nil -> 0
    end
  end
  
  defp measure_resource_for_process(pid, :reductions) do
    case Process.info(pid, :reductions) do
      {:reductions, reductions} -> reductions
      nil -> 0
    end
  end
  
  defp measure_resource_for_process(pid, :processes) do
    # Count child processes spawned by this agent
    count_agent_child_processes(pid)
  end
  
  defp measure_resource_for_process(pid, :cpu) do
    # CPU measurement requires more sophisticated tracking
    measure_cpu_usage_for_process(pid)
  end
  
  defp measure_cpu_usage_for_process(pid) do
    case :ets.lookup(:process_cpu_tracking, pid) do
      [{^pid, %{last_reductions: last_reds, last_timestamp: last_ts}}] ->
        {:reductions, current_reds} = Process.info(pid, :reductions)
        current_ts = :erlang.monotonic_time(:millisecond)
        
        # Calculate CPU percentage based on reductions
        time_diff = current_ts - last_ts
        reds_diff = current_reds - last_reds
        
        cpu_percentage = if time_diff > 0 do
          (reds_diff / time_diff) * 100  # Simplified CPU calculation
        else
          0
        end
        
        # Update tracking
        :ets.insert(:process_cpu_tracking, {pid, %{
          last_reductions: current_reds,
          last_timestamp: current_ts
        }})
        
        cpu_percentage
      [] ->
        # Initialize tracking for this process
        {:reductions, current_reds} = Process.info(pid, :reductions)
        current_ts = :erlang.monotonic_time(:millisecond)
        
        :ets.insert(:process_cpu_tracking, {pid, %{
          last_reductions: current_reds,
          last_timestamp: current_ts
        }})
        
        0  # No previous measurement
    end
  end
  
  defp count_agent_child_processes(agent_pid) do
    # Count processes that have this agent as their parent
    all_processes = Process.list()
    
    Enum.count(all_processes, fn pid ->
      case Process.info(pid, :parent) do
        {:parent, ^agent_pid} -> true
        _ -> false
      end
    end)
  end
  
  # Alerting and Threshold Checking
  defp check_alerting_thresholds(measurements, state) do
    Enum.each(measurements, fn measurement ->
      case Map.get(state.config.alerting_thresholds, measurement.resource_type) do
        nil -> :ok
        threshold ->
          if measurement.value > threshold.critical_level do
            maybe_send_alert(:critical, measurement, threshold, state)
          elsif measurement.value > threshold.warning_level do
            maybe_send_alert(:warning, measurement, threshold, state)
          end
      end
    end)
  end
  
  defp maybe_send_alert(level, measurement, threshold, state) do
    alert_key = {measurement.resource_type, level}
    last_alert_time = Map.get(state.last_alert_times, alert_key, 0)
    current_time = :erlang.monotonic_time(:second)
    
    # Rate limit alerts (minimum 60 seconds between same alert)
    if current_time - last_alert_time > 60 do
      send_resource_alert(level, measurement, threshold, state.agent_id)
      
      # Update last alert time
      updated_alert_times = Map.put(state.last_alert_times, alert_key, current_time)
      {:noreply, %{state | last_alert_times: updated_alert_times}}
    else
      {:noreply, state}
    end
  end
  
  defp send_resource_alert(level, measurement, threshold, agent_id) do
    alert_data = %{
      level: level,
      agent_id: agent_id,
      resource_type: measurement.resource_type,
      current_value: measurement.value,
      threshold: threshold,
      timestamp: measurement.timestamp
    }
    
    Foundation.Events.publish("resource_management.alert.#{level}", alert_data)
    
    Logger.warn("Resource alert triggered", 
      level: level,
      agent_id: agent_id,
      resource: measurement.resource_type,
      value: measurement.value,
      threshold: threshold
    )
  end
  
  # Helper Functions
  defp via_tuple(agent_id) do
    {:via, Registry, {Foundation.ResourceManagement.MonitorRegistry, agent_id}}
  end
  
  defp find_agent_process(agent_id) do
    case Foundation.ProcessRegistry.lookup(agent_id) do
      {:ok, pid} -> pid
      {:error, :not_found} -> nil
    end
  end
  
  defp schedule_resource_measurement(interval) do
    Process.send_after(self(), :measure_resources, interval)
  end
end
```

### 2.2 Resource Usage Analytics

#### Analytics and Reporting System
```elixir
defmodule Foundation.ResourceManagement.Analytics do
  @moduledoc """
  Resource usage analytics, reporting, and optimization recommendations.
  """
  
  use GenServer
  alias Foundation.ResourceManagement.{Types, Monitor}
  
  @type usage_pattern :: %{
    agent_id: String.t(),
    resource_type: Types.resource_type(),
    pattern_type: :steady | :periodic | :bursty | :growing | :declining,
    confidence: float(),
    characteristics: map()
  }
  
  @type optimization_recommendation :: %{
    agent_id: String.t(),
    recommendation_type: :increase_quota | :decrease_quota | :change_group | :optimize_code,
    resource_type: Types.resource_type(),
    suggested_change: term(),
    rationale: String.t(),
    confidence: float()
  }
  
  # Analytics Engine
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Initialize analytics storage
    :ets.new(:resource_analytics, [:named_table, :set, :public])
    :ets.new(:usage_patterns, [:named_table, :bag, :public])
    :ets.new(:optimization_recommendations, [:named_table, :bag, :public])
    
    # Schedule periodic analytics
    schedule_analytics_run()
    
    {:ok, %{
      analytics_interval: 300_000,  # 5 minutes
      pattern_window: 3600_000,     # 1 hour
      recommendation_history: %{}
    }}
  end
  
  # Public API
  @spec analyze_usage_patterns(String.t()) :: {:ok, [usage_pattern()]} | {:error, term()}
  def analyze_usage_patterns(agent_id) do
    GenServer.call(__MODULE__, {:analyze_patterns, agent_id})
  end
  
  @spec get_optimization_recommendations(String.t()) :: {:ok, [optimization_recommendation()]}
  def get_optimization_recommendations(agent_id) do
    case :ets.lookup(:optimization_recommendations, agent_id) do
      [] -> {:ok, []}
      recommendations -> {:ok, Enum.map(recommendations, fn {_, rec} -> rec end)}
    end
  end
  
  @spec generate_resource_report(String.t() | :all, time_range()) :: {:ok, resource_report()}
  def generate_resource_report(agent_id, time_range) do
    GenServer.call(__MODULE__, {:generate_report, agent_id, time_range})
  end
  
  # GenServer Handlers
  def handle_call({:analyze_patterns, agent_id}, _from, state) do
    patterns = perform_pattern_analysis(agent_id, state.pattern_window)
    {:reply, {:ok, patterns}, state}
  end
  
  def handle_call({:generate_report, agent_id, time_range}, _from, state) do
    report = generate_detailed_report(agent_id, time_range)
    {:reply, {:ok, report}, state}
  end
  
  def handle_info(:run_analytics, state) do
    # Run analytics for all monitored agents
    run_comprehensive_analytics()
    schedule_analytics_run()
    {:noreply, state}
  end
  
  # Pattern Analysis Functions
  defp perform_pattern_analysis(agent_id, window_duration) do
    # Get recent measurements for the agent
    measurements = get_agent_measurements(agent_id, window_duration)
    
    # Group measurements by resource type
    grouped_measurements = Enum.group_by(measurements, & &1.resource_type)
    
    # Analyze each resource type
    Enum.map(grouped_measurements, fn {resource_type, resource_measurements} ->
      analyze_resource_pattern(agent_id, resource_type, resource_measurements)
    end)
  end
  
  defp analyze_resource_pattern(agent_id, resource_type, measurements) do
    values = Enum.map(measurements, & &1.value)
    timestamps = Enum.map(measurements, & &1.timestamp)
    
    # Statistical analysis
    mean_value = Enum.sum(values) / length(values)
    variance = calculate_variance(values, mean_value)
    trend = calculate_trend(values, timestamps)
    
    # Pattern classification
    pattern_type = classify_usage_pattern(values, mean_value, variance, trend)
    confidence = calculate_pattern_confidence(values, pattern_type)
    
    characteristics = %{
      mean: mean_value,
      variance: variance,
      trend: trend,
      peak_value: Enum.max(values),
      min_value: Enum.min(values),
      measurement_count: length(measurements)
    }
    
    %{
      agent_id: agent_id,
      resource_type: resource_type,
      pattern_type: pattern_type,
      confidence: confidence,
      characteristics: characteristics
    }
  end
  
  defp classify_usage_pattern(values, mean_value, variance, trend) do
    cond do
      # Growing pattern: consistent upward trend
      trend > 0.1 -> :growing
      
      # Declining pattern: consistent downward trend
      trend < -0.1 -> :declining
      
      # High variance indicates bursty usage
      variance > mean_value * 0.5 -> :bursty
      
      # Periodic pattern detection (simplified)
      has_periodic_pattern?(values) -> :periodic
      
      # Default to steady usage
      true -> :steady
    end
  end
  
  defp has_periodic_pattern?(values) do
    # Simple autocorrelation check for periodicity
    if length(values) < 10 do
      false
    else
      # Check for patterns with period of 4, 6, 8, 12 measurements
      periods_to_check = [4, 6, 8, 12]
      
      Enum.any?(periods_to_check, fn period ->
        correlation = calculate_autocorrelation(values, period)
        correlation > 0.6  # Strong periodic correlation
      end)
    end
  end
  
  defp calculate_autocorrelation(values, lag) do
    if length(values) <= lag do
      0.0
    else
      {first_part, second_part} = Enum.split(values, -lag)
      correlation_coefficient(first_part, second_part)
    end
  end
  
  # Optimization Recommendation Engine
  defp run_comprehensive_analytics() do
    # Get all monitored agents
    monitored_agents = get_all_monitored_agents()
    
    Enum.each(monitored_agents, fn agent_id ->
      # Analyze patterns
      {:ok, patterns} = analyze_usage_patterns(agent_id)
      
      # Generate recommendations
      recommendations = generate_optimization_recommendations(agent_id, patterns)
      
      # Store recommendations
      :ets.delete_all_objects(:optimization_recommendations)
      Enum.each(recommendations, fn rec ->
        :ets.insert(:optimization_recommendations, {agent_id, rec})
      end)
    end)
  end
  
  defp generate_optimization_recommendations(agent_id, patterns) do
    Enum.reduce(patterns, [], fn pattern, recommendations ->
      case analyze_pattern_for_optimization(agent_id, pattern) do
        nil -> recommendations
        recommendation -> [recommendation | recommendations]
      end
    end)
  end
  
  defp analyze_pattern_for_optimization(agent_id, pattern) do
    case pattern.pattern_type do
      :growing ->
        if pattern.characteristics.trend > 0.2 do
          %{
            agent_id: agent_id,
            recommendation_type: :increase_quota,
            resource_type: pattern.resource_type,
            suggested_change: calculate_quota_increase(pattern),
            rationale: "Resource usage showing consistent growth trend",
            confidence: pattern.confidence
          }
        else
          nil
        end
        
      :steady ->
        if pattern.characteristics.mean < get_current_quota(agent_id, pattern.resource_type) * 0.3 do
          %{
            agent_id: agent_id,
            recommendation_type: :decrease_quota,
            resource_type: pattern.resource_type,
            suggested_change: calculate_quota_decrease(pattern),
            rationale: "Resource usage consistently low, quota can be reduced",
            confidence: pattern.confidence
          }
        else
          nil
        end
        
      :bursty ->
        %{
          agent_id: agent_id,
          recommendation_type: :optimize_code,
          resource_type: pattern.resource_type,
          suggested_change: :reduce_variance,
          rationale: "High variance in resource usage suggests optimization opportunity",
          confidence: pattern.confidence * 0.8  # Lower confidence for code recommendations
        }
        
      _ -> nil
    end
  end
  
  # Helper Functions
  defp calculate_variance(values, mean) do
    sum_of_squares = Enum.reduce(values, 0, fn value, acc ->
      acc + :math.pow(value - mean, 2)
    end)
    sum_of_squares / length(values)
  end
  
  defp calculate_trend(values, timestamps) do
    if length(values) < 2 do
      0.0
    else
      # Simple linear regression slope
      n = length(values)
      sum_x = Enum.sum(1..n)
      sum_y = Enum.sum(values)
      sum_xy = Enum.zip(1..n, values) |> Enum.reduce(0, fn {x, y}, acc -> acc + x * y end)
      sum_x2 = Enum.reduce(1..n, 0, fn x, acc -> acc + x * x end)
      
      numerator = n * sum_xy - sum_x * sum_y
      denominator = n * sum_x2 - sum_x * sum_x
      
      if denominator == 0 do
        0.0
      else
        numerator / denominator
      end
    end
  end
  
  defp correlation_coefficient(list1, list2) do
    if length(list1) != length(list2) or length(list1) < 2 do
      0.0
    else
      n = length(list1)
      sum1 = Enum.sum(list1)
      sum2 = Enum.sum(list2)
      sum1_sq = Enum.reduce(list1, 0, fn x, acc -> acc + x * x end)
      sum2_sq = Enum.reduce(list2, 0, fn x, acc -> acc + x * x end)
      sum_products = Enum.zip(list1, list2) |> Enum.reduce(0, fn {x, y}, acc -> acc + x * y end)
      
      numerator = n * sum_products - sum1 * sum2
      denominator = :math.sqrt((n * sum1_sq - sum1 * sum1) * (n * sum2_sq - sum2 * sum2))
      
      if denominator == 0 do
        0.0
      else
        numerator / denominator
      end
    end
  end
  
  defp schedule_analytics_run() do
    Process.send_after(self(), :run_analytics, 300_000)  # 5 minutes
  end
end
```

## 3. Resource Enforcement and Actions

### 3.1 Enforcement Engine

#### Quota Enforcement Implementation
```elixir
defmodule Foundation.ResourceManagement.Enforcer do
  @moduledoc """
  Enforces resource quotas with configurable actions and graceful degradation.
  """
  
  use GenServer
  alias Foundation.ResourceManagement.{Types, QuotaManager, Monitor}
  
  @type enforcement_action :: 
    :warn | :throttle | :suspend | :terminate | :scale_down | :migrate | :custom
  
  @type enforcement_event :: %{
    agent_id: String.t(),
    resource_type: Types.resource_type(),
    violation_type: :soft_limit | :hard_limit | :burst_limit,
    current_usage: non_neg_integer(),
    limit: non_neg_integer(),
    action_taken: enforcement_action(),
    timestamp: DateTime.t(),
    success: boolean(),
    details: map()
  }
  
  # Enforcement Engine
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def init(_opts) do
    # Initialize enforcement tracking
    :ets.new(:enforcement_history, [:named_table, :bag, :public])
    :ets.new(:throttled_agents, [:named_table, :set, :public])
    :ets.new(:suspended_agents, [:named_table, :set, :public])
    
    {:ok, %{
      enforcement_enabled: true,
      grace_periods: %{},
      escalation_delays: %{
        warn: 0,
        throttle: 30_000,    # 30 seconds
        suspend: 300_000,    # 5 minutes
        terminate: 600_000   # 10 minutes
      }
    }}
  end
  
  # Public API
  @spec enforce_quota_violation(String.t(), [quota_violation()]) :: :ok
  def enforce_quota_violation(agent_id, violations) do
    GenServer.cast(__MODULE__, {:enforce_violations, agent_id, violations})
  end
  
  @spec get_enforcement_history(String.t()) :: [enforcement_event()]
  def get_enforcement_history(agent_id) do
    case :ets.lookup(:enforcement_history, agent_id) do
      [] -> []
      events -> Enum.map(events, fn {_, event} -> event end)
    end
  end
  
  @spec is_agent_throttled?(String.t()) :: boolean()
  def is_agent_throttled?(agent_id) do
    case :ets.lookup(:throttled_agents, agent_id) do
      [] -> false
      [_] -> true
    end
  end
  
  @spec is_agent_suspended?(String.t()) :: boolean()
  def is_agent_suspended?(agent_id) do
    case :ets.lookup(:suspended_agents, agent_id) do
      [] -> false
      [_] -> true
    end
  end
  
  # GenServer Handlers
  def handle_cast({:enforce_violations, agent_id, violations}, state) do
    if state.enforcement_enabled do
      Enum.each(violations, fn violation ->
        execute_enforcement_action(agent_id, violation, state)
      end)
    end
    
    {:noreply, state}
  end
  
  # Enforcement Action Execution
  defp execute_enforcement_action(agent_id, violation, state) do
    # Determine appropriate action based on violation and history
    action = determine_enforcement_action(agent_id, violation)
    
    # Check if we should delay enforcement (escalation delay)
    delay = Map.get(state.escalation_delays, action, 0)
    
    if delay > 0 do
      # Schedule delayed enforcement
      Process.send_after(self(), {:delayed_enforcement, agent_id, violation, action}, delay)
    else
      # Execute immediate enforcement
      perform_enforcement_action(agent_id, violation, action)
    end
  end
  
  defp determine_enforcement_action(agent_id, violation) do
    # Get enforcement action from quota configuration
    case QuotaManager.get_agent_quota(agent_id) do
      {:ok, quota} ->
        resource_limits = Map.get(quota.resource_limits, violation.resource)
        
        case violation.type do
          :hard_limit -> resource_limits.enforcement_action
          :soft_limit -> :warn
          :burst_limit -> :throttle
        end
      {:error, :not_found} ->
        :warn  # Default action
    end
  end
  
  defp perform_enforcement_action(agent_id, violation, action) do
    case action do
      :warn ->
        execute_warn_action(agent_id, violation)
        
      :throttle ->
        execute_throttle_action(agent_id, violation)
        
      :suspend ->
        execute_suspend_action(agent_id, violation)
        
      :terminate ->
        execute_terminate_action(agent_id, violation)
        
      :scale_down ->
        execute_scale_down_action(agent_id, violation)
        
      :migrate ->
        execute_migrate_action(agent_id, violation)
        
      :custom_handler ->
        execute_custom_action(agent_id, violation)
    end
    
    # Record enforcement event
    record_enforcement_event(agent_id, violation, action)
  end
  
  # Enforcement Action Implementations
  defp execute_warn_action(agent_id, violation) do
    Logger.warn("Resource quota warning", 
      agent_id: agent_id,
      resource: violation.resource,
      current: violation.current,
      limit: violation.limit
    )
    
    # Publish warning event
    Foundation.Events.publish("resource_management.quota.warning", %{
      agent_id: agent_id,
      violation: violation,
      action: :warn,
      timestamp: DateTime.utc_now()
    })
    
    {:ok, %{action: :warn, details: "Warning logged and event published"}}
  end
  
  defp execute_throttle_action(agent_id, violation) do
    # Add agent to throttled list
    throttle_config = %{
      started_at: DateTime.utc_now(),
      resource_type: violation.resource,
      throttle_factor: calculate_throttle_factor(violation)
    }
    
    :ets.insert(:throttled_agents, {agent_id, throttle_config})
    
    # Notify agent process about throttling
    case Foundation.ProcessRegistry.lookup(agent_id) do
      {:ok, agent_pid} ->
        send(agent_pid, {:throttle_notification, violation.resource, throttle_config.throttle_factor})
        {:ok, %{action: :throttle, details: "Agent throttled", throttle_factor: throttle_config.throttle_factor}}
      {:error, :not_found} ->
        {:error, :agent_process_not_found}
    end
  end
  
  defp execute_suspend_action(agent_id, violation) do
    # Add agent to suspended list
    suspension_config = %{
      started_at: DateTime.utc_now(),
      resource_type: violation.resource,
      reason: "Resource quota violation"
    }
    
    :ets.insert(:suspended_agents, {agent_id, suspension_config})
    
    # Suspend agent process
    case Foundation.ProcessRegistry.lookup(agent_id) do
      {:ok, agent_pid} ->
        # Send suspension signal to agent
        send(agent_pid, {:suspend_notification, violation.resource, suspension_config})
        
        # Use :sys.suspend to pause the process
        :sys.suspend(agent_pid)
        
        {:ok, %{action: :suspend, details: "Agent process suspended"}}
      {:error, :not_found} ->
        {:error, :agent_process_not_found}
    end
  end
  
  defp execute_terminate_action(agent_id, violation) do
    Logger.error("Terminating agent due to resource violation", 
      agent_id: agent_id,
      violation: violation
    )
    
    case Foundation.ProcessRegistry.lookup(agent_id) do
      {:ok, agent_pid} ->
        # Send termination notice
        send(agent_pid, {:termination_notice, violation.resource, "Resource quota violation"})
        
        # Allow graceful shutdown (5 seconds)
        Process.sleep(5_000)
        
        # Force termination if still alive
        if Process.alive?(agent_pid) do
          Process.exit(agent_pid, {:quota_violation, violation.resource})
        end
        
        # Clean up registrations
        Foundation.ProcessRegistry.unregister(agent_id)
        
        {:ok, %{action: :terminate, details: "Agent process terminated"}}
      {:error, :not_found} ->
        {:error, :agent_process_not_found}
    end
  end
  
  defp execute_scale_down_action(agent_id, violation) do
    # Attempt to scale down agent resource usage
    case Foundation.ProcessRegistry.lookup(agent_id) do
      {:ok, agent_pid} ->
        # Send scale down request
        scale_down_request = %{
          resource_type: violation.resource,
          current_usage: violation.current,
          target_usage: violation.limit * 0.8,  # Target 80% of limit
          deadline: DateTime.add(DateTime.utc_now(), 30, :second)
        }
        
        send(agent_pid, {:scale_down_request, scale_down_request})
        
        {:ok, %{action: :scale_down, details: "Scale down request sent", request: scale_down_request}}
      {:error, :not_found} ->
        {:error, :agent_process_not_found}
    end
  end
  
  defp execute_migrate_action(agent_id, violation) do
    # Attempt to migrate agent to a different node with more resources
    case find_suitable_migration_target(violation.resource) do
      {:ok, target_node} ->
        migrate_agent_to_node(agent_id, target_node)
      {:error, :no_suitable_target} ->
        # Fallback to suspension if migration not possible
        execute_suspend_action(agent_id, violation)
    end
  end
  
  # Helper Functions
  defp calculate_throttle_factor(violation) do
    # Calculate throttle factor based on how much the limit is exceeded
    excess_ratio = (violation.current - violation.limit) / violation.limit
    
    cond do
      excess_ratio > 1.0 -> 0.5   # Heavy throttling
      excess_ratio > 0.5 -> 0.7   # Moderate throttling
      excess_ratio > 0.2 -> 0.85  # Light throttling
      true -> 0.9                 # Minimal throttling
    end
  end
  
  defp record_enforcement_event(agent_id, violation, action) do
    event = %{
      agent_id: agent_id,
      resource_type: violation.resource,
      violation_type: violation.type,
      current_usage: violation.current,
      limit: violation.limit,
      action_taken: action,
      timestamp: DateTime.utc_now(),
      success: true,  # Assume success, would need actual result
      details: %{}
    }
    
    :ets.insert(:enforcement_history, {agent_id, event})
  end
  
  defp find_suitable_migration_target(resource_type) do
    # Find nodes with available capacity for the resource type
    available_nodes = Node.list()
    
    Enum.find_value(available_nodes, {:error, :no_suitable_target}, fn node ->
      case :rpc.call(node, Foundation.ResourceManagement.Types, :calculate_available_resources, []) do
        available_resources when is_map(available_resources) ->
          if Map.get(available_resources, resource_type, 0) > 0 do
            {:ok, node}
          else
            nil
          end
        _ ->
          nil
      end
    end)
  end
end
```

## 4. Graceful Degradation and Recovery

### 4.1 Degradation Strategies

#### Graceful Degradation Framework
```elixir
defmodule Foundation.ResourceManagement.GracefulDegradation do
  @moduledoc """
  Implements graceful degradation strategies for resource-constrained environments.
  """
  
  @type degradation_strategy :: 
    :reduce_precision | :cache_aggressively | :batch_operations | 
    :drop_non_essential | :use_fallback_algorithm | :custom
  
  @type degradation_level :: :minimal | :moderate | :aggressive | :emergency
  
  @type degradation_plan :: %{
    agent_id: String.t(),
    resource_type: Types.resource_type(),
    current_level: degradation_level(),
    strategies: [degradation_strategy()],
    target_reduction: float(),
    timeline: pos_integer()
  }
  
  def create_degradation_plan(agent_id, resource_pressure) do
    # Analyze current resource pressure
    degradation_level = determine_degradation_level(resource_pressure)
    
    # Select appropriate strategies
    strategies = select_degradation_strategies(resource_pressure.resource_type, degradation_level)
    
    # Calculate target reduction
    target_reduction = calculate_target_reduction(resource_pressure, degradation_level)
    
    %{
      agent_id: agent_id,
      resource_type: resource_pressure.resource_type,
      current_level: degradation_level,
      strategies: strategies,
      target_reduction: target_reduction,
      timeline: calculate_degradation_timeline(degradation_level)
    }
  end
  
  defp determine_degradation_level(resource_pressure) do
    usage_ratio = resource_pressure.current_usage / resource_pressure.limit
    
    cond do
      usage_ratio > 1.5 -> :emergency     # 150% of limit
      usage_ratio > 1.2 -> :aggressive    # 120% of limit
      usage_ratio > 1.0 -> :moderate      # 100% of limit
      usage_ratio > 0.9 -> :minimal       # 90% of limit
      true -> :none
    end
  end
  
  defp select_degradation_strategies(:memory, degradation_level) do
    case degradation_level do
      :minimal -> [:cache_aggressively]
      :moderate -> [:cache_aggressively, :batch_operations]
      :aggressive -> [:cache_aggressively, :batch_operations, :reduce_precision]
      :emergency -> [:cache_aggressively, :batch_operations, :reduce_precision, :drop_non_essential]
    end
  end
  
  defp select_degradation_strategies(:cpu, degradation_level) do
    case degradation_level do
      :minimal -> [:batch_operations]
      :moderate -> [:batch_operations, :use_fallback_algorithm]
      :aggressive -> [:batch_operations, :use_fallback_algorithm, :reduce_precision]
      :emergency -> [:batch_operations, :use_fallback_algorithm, :reduce_precision, :drop_non_essential]
    end
  end
  
  # Strategy Implementation
  def implement_degradation_strategy(agent_pid, :reduce_precision, context) do
    send(agent_pid, {:degradation_strategy, :reduce_precision, %{
      precision_reduction: 0.5,
      affected_operations: [:calculations, :predictions],
      context: context
    }})
  end
  
  def implement_degradation_strategy(agent_pid, :cache_aggressively, context) do
    send(agent_pid, {:degradation_strategy, :cache_aggressively, %{
      cache_size_increase: 2.0,
      cache_duration_increase: 5.0,
      context: context
    }})
  end
  
  def implement_degradation_strategy(agent_pid, :batch_operations, context) do
    send(agent_pid, {:degradation_strategy, :batch_operations, %{
      batch_size_increase: 3.0,
      batch_delay: 1000,  # 1 second
      context: context
    }})
  end
  
  def implement_degradation_strategy(agent_pid, :drop_non_essential, context) do
    send(agent_pid, {:degradation_strategy, :drop_non_essential, %{
      operations_to_drop: [:detailed_logging, :metrics_collection, :optional_validations],
      context: context
    }})
  end
  
  # Recovery Management
  def create_recovery_plan(agent_id, degradation_history) do
    # Analyze degradation effectiveness
    effective_strategies = analyze_degradation_effectiveness(degradation_history)
    
    # Create gradual recovery plan
    %{
      agent_id: agent_id,
      recovery_stages: create_recovery_stages(effective_strategies),
      monitoring_checkpoints: create_monitoring_checkpoints(),
      rollback_plan: create_rollback_plan(degradation_history)
    }
  end
  
  defp create_recovery_stages(effective_strategies) do
    # Create stages to gradually remove degradation strategies
    Enum.reverse(effective_strategies)
    |> Enum.with_index()
    |> Enum.map(fn {strategy, index} ->
      %{
        stage: index + 1,
        action: :remove_strategy,
        strategy: strategy,
        delay: (index + 1) * 30_000,  # 30 seconds between stages
        success_criteria: %{
          resource_usage_below: 0.8,
          no_violations_for: 60_000
        }
      }
    end)
  end
end
```

## Conclusion

This comprehensive resource management system provides:

1. **Comprehensive Resource Types** - Memory, CPU, processes, files, network with configurable limits
2. **Quota Management** - Agent-specific quotas with group-based defaults and custom overrides  
3. **Real-Time Monitoring** - Efficient resource measurement with alerting and threshold checking
4. **Advanced Analytics** - Usage pattern analysis and optimization recommendations
5. **Flexible Enforcement** - Configurable enforcement actions from warnings to termination
6. **Graceful Degradation** - Smart degradation strategies based on resource pressure
7. **Recovery Management** - Systematic recovery plans with monitoring and rollback capabilities

**Key Features**:
- **Multi-Agent Fairness**: Prevents resource monopolization by individual agents
- **Production Scalability**: ETS-based caching for high-performance monitoring
- **Intelligent Enforcement**: Escalating enforcement actions with grace periods
- **System Stability**: Graceful degradation prevents system-wide failures
- **Operational Visibility**: Comprehensive analytics and reporting

**Implementation Priority**: MEDIUM - Important for production stability and fairness
**Dependencies**: Foundation.ProcessRegistry, Foundation.Events, Foundation.Telemetry
**Testing Requirements**: Load testing with resource pressure and enforcement validation