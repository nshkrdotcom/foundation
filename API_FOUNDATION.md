# Foundation API Contracts for Agent-Aware Backport

## Executive Summary

This document defines the comprehensive API contracts required for integrating agent-aware capabilities into the existing Foundation infrastructure. The contracts are designed to maintain **100% backward compatibility** while adding powerful new agent-centric functionality through additive APIs.

## Design Principles

1. **Backward Compatibility**: All existing APIs remain unchanged and functional
2. **Additive Enhancement**: New functionality added through new methods, not modifications
3. **Consistent Patterns**: Agent-aware APIs follow established Foundation patterns
4. **Type Safety**: Comprehensive type specifications for all interfaces
5. **Error Handling**: Unified error handling across all agent-aware APIs
6. **Documentation**: Complete documentation with examples for all contracts

## Core Type Definitions

### Agent Types

```elixir
@type agent_id :: atom() | String.t()
@type capability :: atom()
@type health_status :: :healthy | :degraded | :unhealthy | :unknown
@type agent_state :: :initializing | :ready | :active | :idle | :degraded | :maintenance | :stopping | :stopped

@type resource_usage :: %{
  memory: float(),           # 0.0 to 1.0 (percentage)
  cpu: float(),             # 0.0 to 1.0 (percentage)  
  network: non_neg_integer(), # connections count
  storage: float(),         # 0.0 to 1.0 (percentage)
  custom: %{atom() => any()} # Custom resource types
}

@type agent_metadata :: %{
  type: :agent | :service | :coordination_service,
  capabilities: [capability()],
  health: health_status(),
  state: agent_state(),
  resource_usage: resource_usage(),
  coordination_state: %{
    active_consensus: [atom()],
    active_barriers: [atom()],
    held_locks: [String.t()],
    leadership_roles: [atom()]
  },
  last_health_check: DateTime.t(),
  configuration: map(),
  metadata: map()
}

@type agent_context :: %{
  agent_id: agent_id(),
  current_capability: capability() | nil,
  health_status: health_status(),
  resource_state: resource_usage(),
  coordination_active: boolean()
}
```

### Error Types

```elixir
@type agent_error :: %Foundation.Types.Error{
  code: 3000..3999,
  error_type: :agent_not_found | :agent_unhealthy | :agent_capability_missing | 
              :agent_resource_exhausted | :agent_coordination_failed,
  message: String.t(),
  severity: :low | :medium | :high | :critical,
  context: map(),
  agent_context: agent_context() | nil
}
```

## 1. ProcessRegistry Agent-Aware API

### Enhanced Registration API

```elixir
defmodule Foundation.ProcessRegistry.AgentAPI do
  @moduledoc """
  Agent-aware extensions to Foundation ProcessRegistry.
  
  Provides enhanced registration and discovery capabilities for agents
  while maintaining full backward compatibility with existing APIs.
  """
  
  @doc """
  Register an agent with comprehensive metadata.
  
  Extends the basic registration with agent-specific metadata including
  capabilities, health status, resource usage, and coordination state.
  
  ## Parameters
  - `namespace`: Registry namespace (:production, {:test, ref})
  - `agent_id`: Unique identifier for the agent
  - `pid`: Process ID of the agent
  - `agent_metadata`: Agent-specific metadata and state information
  
  ## Examples
  
      agent_metadata = %{
        type: :ml_agent,
        capabilities: [:nlp, :classification, :generation],
        health: :healthy,
        state: :ready,
        resource_usage: %{memory: 0.7, cpu: 0.4},
        coordination_state: %{
          active_consensus: [],
          active_barriers: [],
          held_locks: [],
          leadership_roles: []
        },
        last_health_check: DateTime.utc_now(),
        configuration: %{model_type: "transformer"},
        metadata: %{version: "1.0", deployment: "production"}
      }
      
      :ok = ProcessRegistry.register_agent(
        :production, 
        :ml_agent_1, 
        pid, 
        agent_metadata
      )
  """
  @spec register_agent(namespace(), agent_id(), pid(), agent_metadata()) :: 
    :ok | {:error, Foundation.Types.Error.t()}
  def register_agent(namespace, agent_id, pid, agent_metadata)
  
  @doc """
  Look up an agent with full metadata.
  
  Returns the agent process and complete metadata including current
  health status, capabilities, and coordination state.
  
  ## Examples
  
      {:ok, {pid, metadata}} = ProcessRegistry.lookup_agent(:production, :ml_agent_1)
      
      # Access agent capabilities
      capabilities = metadata.capabilities
      
      # Check agent health
      if metadata.health == :healthy do
        # Proceed with agent interaction
      end
  """
  @spec lookup_agent(namespace(), agent_id()) :: 
    {:ok, {pid(), agent_metadata()}} | {:error, Foundation.Types.Error.t()}
  def lookup_agent(namespace, agent_id)
  
  @doc """
  Find agents by capability.
  
  Returns all agents that have the specified capability, useful for
  dynamic agent discovery and load balancing.
  
  ## Examples
  
      # Find all NLP-capable agents
      nlp_agents = ProcessRegistry.lookup_agents_by_capability(:production, :nlp)
      
      # Find coordination agents
      coordinators = ProcessRegistry.lookup_agents_by_capability(:production, :coordination)
  """
  @spec lookup_agents_by_capability(namespace(), capability()) :: 
    [{agent_id(), pid(), agent_metadata()}]
  def lookup_agents_by_capability(namespace, capability)
  
  @doc """
  Find agents by health status.
  
  Returns all agents matching the specified health status, useful for
  health monitoring and load balancing decisions.
  
  ## Examples
  
      # Find all healthy agents
      healthy_agents = ProcessRegistry.lookup_agents_by_health(:production, :healthy)
      
      # Find degraded agents for maintenance
      degraded_agents = ProcessRegistry.lookup_agents_by_health(:production, :degraded)
  """
  @spec lookup_agents_by_health(namespace(), health_status()) :: 
    [{agent_id(), pid(), agent_metadata()}]
  def lookup_agents_by_health(namespace, health_status)
  
  @doc """
  Update agent metadata.
  
  Updates the metadata for an existing agent, typically used for
  health status updates, capability changes, or state transitions.
  
  ## Examples
  
      # Update agent health status
      updated_metadata = %{existing_metadata | 
        health: :degraded,
        last_health_check: DateTime.utc_now()
      }
      
      :ok = ProcessRegistry.update_agent_metadata(
        :production, 
        :ml_agent_1, 
        updated_metadata
      )
  """
  @spec update_agent_metadata(namespace(), agent_id(), agent_metadata()) :: 
    :ok | {:error, Foundation.Types.Error.t()}
  def update_agent_metadata(namespace, agent_id, agent_metadata)
  
  @doc """
  Get comprehensive agent statistics.
  
  Returns detailed statistics about agents in the registry including
  health distribution, capability distribution, and resource usage.
  
  ## Examples
  
      stats = ProcessRegistry.get_agent_stats(:production)
      # => %{
      #   total_agents: 45,
      #   health_distribution: %{healthy: 40, degraded: 4, unhealthy: 1},
      #   capability_distribution: %{nlp: 15, coordination: 5, inference: 25},
      #   average_resource_usage: %{memory: 0.65, cpu: 0.45}
      # }
  """
  @spec get_agent_stats(namespace()) :: %{
    total_agents: non_neg_integer(),
    health_distribution: %{health_status() => non_neg_integer()},
    capability_distribution: %{capability() => non_neg_integer()},
    average_resource_usage: resource_usage()
  }
  def get_agent_stats(namespace)
end
```

## 2. Circuit Breaker Agent-Aware API

```elixir
defmodule Foundation.Infrastructure.AgentCircuitBreaker.API do
  @moduledoc """
  Agent-aware circuit breaker API that integrates agent health and
  resource status into circuit breaker decisions.
  """
  
  @type circuit_name :: atom()
  @type circuit_options :: [
    agent_id: agent_id(),
    capability: capability(),
    resource_thresholds: %{
      memory: float(),
      cpu: float()
    },
    failure_threshold: pos_integer(),
    recovery_timeout: pos_integer(),
    health_check_interval: pos_integer()
  ]
  
  @doc """
  Start an agent-aware circuit breaker.
  
  Creates a circuit breaker that considers both traditional failure patterns
  and agent-specific health metrics when making decisions.
  
  ## Parameters
  - `circuit_name`: Unique identifier for the circuit breaker
  - `options`: Circuit breaker configuration with agent context
  
  ## Examples
  
      {:ok, pid} = AgentCircuitBreaker.start_agent_breaker(
        :ml_inference_service,
        agent_id: :ml_agent_1,
        capability: :inference,
        resource_thresholds: %{memory: 0.8, cpu: 0.9},
        failure_threshold: 5,
        recovery_timeout: 60_000
      )
  """
  @spec start_agent_breaker(circuit_name(), circuit_options()) :: 
    {:ok, pid()} | {:error, Foundation.Types.Error.t()}
  def start_agent_breaker(circuit_name, options)
  
  @doc """
  Execute operation with agent-aware circuit protection.
  
  Executes the operation through the circuit breaker, considering both
  circuit state and agent health when making execution decisions.
  
  ## Parameters
  - `circuit_name`: Circuit breaker identifier
  - `agent_id`: Agent performing the operation
  - `operation`: Function to execute (0-arity)
  - `metadata`: Additional context for telemetry and logging
  
  ## Examples
  
      result = AgentCircuitBreaker.execute_with_agent(
        :ml_service,
        :ml_agent_1,
        fn -> perform_ml_inference(data) end,
        %{request_id: "req_123", priority: :high}
      )
      
      case result do
        {:ok, inference_result} -> 
          # Process successful result
          inference_result
          
        {:error, %{error_type: :circuit_breaker_open}} ->
          # Circuit is open due to failures or agent health
          fallback_response()
          
        {:error, %{error_type: :agent_unhealthy}} ->
          # Agent health check failed
          route_to_healthy_agent()
      end
  """
  @spec execute_with_agent(circuit_name(), agent_id(), (() -> any()), map()) :: 
    {:ok, any()} | {:error, Foundation.Types.Error.t()}
  def execute_with_agent(circuit_name, agent_id, operation, metadata \\ %{})
  
  @doc """
  Get agent circuit breaker status.
  
  Returns detailed status including circuit state, agent health,
  failure counts, and resource utilization.
  
  ## Examples
  
      {:ok, status} = AgentCircuitBreaker.get_agent_status(
        :ml_service, 
        :ml_agent_1
      )
      
      # => %{
      #   circuit_name: :ml_service,
      #   agent_id: :ml_agent_1,
      #   circuit_state: :closed,
      #   agent_health: :healthy,
      #   failure_count: 2,
      #   resource_usage: %{memory: 0.7, cpu: 0.4},
      #   last_health_check: ~U[2024-01-01 12:00:00Z]
      # }
  """
  @spec get_agent_status(circuit_name(), agent_id()) :: 
    {:ok, map()} | {:error, Foundation.Types.Error.t()}
  def get_agent_status(circuit_name, agent_id)
  
  @doc """
  Reset agent circuit breaker.
  
  Forces the circuit to close and resets failure counts, useful for
  manual recovery or after resolving underlying issues.
  
  ## Examples
  
      :ok = AgentCircuitBreaker.reset_agent_circuit(:ml_service, :ml_agent_1)
  """
  @spec reset_agent_circuit(circuit_name(), agent_id()) :: 
    :ok | {:error, Foundation.Types.Error.t()}
  def reset_agent_circuit(circuit_name, agent_id)
end
```

## 3. Rate Limiter Agent-Aware API

```elixir
defmodule Foundation.Infrastructure.AgentRateLimiter.API do
  @moduledoc """
  Agent-aware rate limiting with capability-based throttling and
  health-adaptive rate limits.
  """
  
  @type operation_type :: atom()
  @type rate_limit :: {pos_integer(), pos_integer()}  # {count, window_ms}
  
  @doc """
  Check rate limit with agent context.
  
  Evaluates rate limits considering agent capabilities, health status,
  and current resource utilization to make intelligent throttling decisions.
  
  ## Parameters
  - `agent_id`: Agent requesting the operation
  - `operation_type`: Type of operation being rate limited
  - `metadata`: Additional context for rate limiting decisions
  
  ## Examples
  
      case AgentRateLimiter.check_rate_with_agent(
        :ml_agent_1, 
        :inference_request,
        %{model: "gpt-4", complexity: :high}
      ) do
        :ok -> 
          # Proceed with operation
          perform_inference()
          
        {:error, %{error_type: :agent_rate_limit_exceeded}} ->
          # Rate limit exceeded for this agent
          queue_request_for_later()
          
        {:error, %{error_type: :agent_unhealthy}} ->
          # Agent health too poor for operation
          route_to_healthy_agent()
      end
  """
  @spec check_rate_with_agent(agent_id(), operation_type(), map()) :: 
    :ok | {:error, Foundation.Types.Error.t()}
  def check_rate_with_agent(agent_id, operation_type, metadata \\ %{})
  
  @doc """
  Execute operation with rate limiting protection.
  
  Combines rate limit checking with operation execution, providing
  automatic backpressure based on agent context.
  
  ## Examples
  
      result = AgentRateLimiter.execute_with_limit(
        :ml_agent_1,
        :training_step,
        fn -> execute_training_step(batch_data) end,
        %{batch_size: 32, epoch: 5}
      )
  """
  @spec execute_with_limit(agent_id(), operation_type(), (() -> any()), map()) :: 
    {:ok, any()} | {:error, Foundation.Types.Error.t()}
  def execute_with_limit(agent_id, operation_type, operation, metadata \\ %{})
  
  @doc """
  Update agent-specific rate limits.
  
  Allows dynamic adjustment of rate limits based on agent performance,
  system load, or operational requirements.
  
  ## Examples
  
      # Increase rate limit for high-performing agent
      :ok = AgentRateLimiter.update_agent_limits(
        :ml_agent_1, 
        :inference, 
        {200, 60_000}  # 200 requests per minute
      )
      
      # Decrease rate limit for degraded agent
      :ok = AgentRateLimiter.update_agent_limits(
        :degraded_agent, 
        :inference, 
        {50, 60_000}   # 50 requests per minute
      )
  """
  @spec update_agent_limits(agent_id(), capability(), rate_limit()) :: 
    :ok | {:error, Foundation.Types.Error.t()}
  def update_agent_limits(agent_id, capability, rate_limit)
  
  @doc """
  Get current rate limiting status for an agent.
  
  Returns detailed information about current usage, limits,
  and agent-specific adjustments.
  
  ## Examples
  
      {:ok, status} = AgentRateLimiter.get_agent_status(:ml_agent_1)
      
      # => %{
      #   agent_id: :ml_agent_1,
      #   current_limits: %{inference: {100, 60_000}, training: {10, 60_000}},
      #   current_usage: %{inference: 45, training: 2},
      #   health_adjustment: 1.0,
      #   resource_adjustment: 0.8
      # }
  """
  @spec get_agent_status(agent_id()) :: 
    {:ok, map()} | {:error, Foundation.Types.Error.t()}
  def get_agent_status(agent_id)
end
```

## 4. Configuration Server Agent-Aware API

```elixir
defmodule Foundation.Services.ConfigServer.AgentAPI do
  @moduledoc """
  Agent-aware configuration management with hierarchical overrides
  and agent-specific configuration support.
  """
  
  @type config_path :: [atom() | String.t()]
  @type config_value :: any()
  @type config_scope :: :global | :namespace | :agent | :runtime
  
  @doc """
  Get effective configuration for an agent.
  
  Returns configuration value with agent-specific overrides applied.
  Follows hierarchy: global → namespace → agent → runtime.
  
  ## Parameters
  - `agent_id`: Agent requesting configuration
  - `config_path`: Path to configuration value
  - `namespace`: Configuration namespace (optional, defaults to :foundation)
  
  ## Examples
  
      # Get effective model temperature for specific agent
      {:ok, temperature} = ConfigServer.get_effective_config(
        :ml_agent_1, 
        [:model, :temperature]
      )
      
      # Get agent-specific inference configuration
      {:ok, config} = ConfigServer.get_effective_config(
        :ml_agent_1, 
        [:inference, :batch_size]
      )
  """
  @spec get_effective_config(agent_id(), config_path(), atom()) :: 
    {:ok, config_value()} | {:error, Foundation.Types.Error.t()}
  def get_effective_config(agent_id, config_path, namespace \\ :foundation)
  
  @doc """
  Set agent-specific configuration override.
  
  Creates an agent-specific configuration override that takes precedence
  over global and namespace configurations for the specified agent.
  
  ## Examples
  
      # Set agent-specific model temperature
      :ok = ConfigServer.set_agent_config(
        :ml_agent_1, 
        [:model, :temperature], 
        0.8
      )
      
      # Set agent-specific resource limits
      :ok = ConfigServer.set_agent_config(
        :ml_agent_1, 
        [:resources, :memory_limit], 
        2_000_000_000  # 2GB
      )
  """
  @spec set_agent_config(agent_id(), config_path(), config_value(), atom()) :: 
    :ok | {:error, Foundation.Types.Error.t()}
  def set_agent_config(agent_id, config_path, config_value, namespace \\ :foundation)
  
  @doc """
  Subscribe to agent-specific configuration changes.
  
  The calling process will receive messages when configuration
  affecting the specified agent changes.
  
  ## Examples
  
      # Subscribe to all config changes affecting agent
      :ok = ConfigServer.subscribe_to_agent_changes(:ml_agent_1)
      
      # Subscribe to specific config path for agent
      :ok = ConfigServer.subscribe_to_agent_changes(
        :ml_agent_1, 
        [:model, :temperature]
      )
      
      # Receive change notifications
      receive do
        {:agent_config_changed, agent_id, config_path, old_value, new_value} ->
          handle_config_change(agent_id, config_path, new_value)
      end
  """
  @spec subscribe_to_agent_changes(agent_id(), config_path() | nil, atom()) :: 
    :ok | {:error, Foundation.Types.Error.t()}
  def subscribe_to_agent_changes(agent_id, config_path \\ nil, namespace \\ :foundation)
  
  @doc """
  Get configuration change history for an agent.
  
  Returns recent configuration changes that affected the specified agent,
  useful for debugging and auditing.
  
  ## Examples
  
      {:ok, changes} = ConfigServer.get_agent_config_history(:ml_agent_1, 10)
      
      # => [
      #   %{
      #     path: [:model, :temperature],
      #     old_value: 0.7,
      #     new_value: 0.8,
      #     scope: :agent,
      #     timestamp: ~U[2024-01-01 12:00:00Z]
      #   }
      # ]
  """
  @spec get_agent_config_history(agent_id(), non_neg_integer(), atom()) :: 
    {:ok, [map()]} | {:error, Foundation.Types.Error.t()}
  def get_agent_config_history(agent_id, limit \\ 100, namespace \\ :foundation)
end
```

## 5. Event Store Agent-Aware API

```elixir
defmodule Foundation.Services.EventStore.AgentAPI do
  @moduledoc """
  Agent-aware event storage with correlation, real-time subscriptions,
  and agent-specific event management.
  """
  
  @type event_type :: atom()
  @type correlation_id :: String.t()
  
  @doc """
  Store event with automatic agent context enrichment.
  
  Events are automatically enriched with agent context if agent_id
  is provided, including current health, capabilities, and state.
  
  ## Examples
  
      event = %{
        type: :agent_task_completed,
        agent_id: :ml_agent_1,
        data: %{
          task_type: :inference,
          duration: 250,
          success: true,
          result_size: 1024
        },
        correlation_id: "task_batch_456"
      }
      
      :ok = EventStore.store_agent_event(event)
  """
  @spec store_agent_event(map()) :: :ok | {:error, Foundation.Types.Error.t()}
  def store_agent_event(event_data)
  
  @doc """
  Query events by agent with rich filtering.
  
  Returns events related to the specified agent with optional filtering
  by event type, time range, and correlation ID.
  
  ## Parameters
  - `agent_id`: Agent to query events for
  - `filter`: Optional filter criteria
    - `:type` - Filter by event type
    - `:since` - Events after this timestamp
    - `:until` - Events before this timestamp
    - `:correlation_id` - Events with this correlation ID
    - `:limit` - Maximum number of events
  
  ## Examples
  
      # Get all events for agent in last hour
      one_hour_ago = DateTime.add(DateTime.utc_now(), -3600)
      {:ok, events} = EventStore.query_agent_events(:ml_agent_1, %{
        since: one_hour_ago,
        limit: 100
      })
      
      # Get task completion events for agent
      {:ok, task_events} = EventStore.query_agent_events(:ml_agent_1, %{
        type: :agent_task_completed,
        limit: 50
      })
  """
  @spec query_agent_events(agent_id(), map()) :: 
    {:ok, [map()]} | {:error, Foundation.Types.Error.t()}
  def query_agent_events(agent_id, filter \\ %{})
  
  @doc """
  Subscribe to real-time agent events.
  
  The calling process will receive messages of the form:
  `{:agent_event, subscription_id, event}` for matching events.
  
  ## Examples
  
      # Subscribe to all events for agent
      {:ok, sub_id} = EventStore.subscribe_to_agent_events(:ml_agent_1)
      
      # Subscribe to specific event types for agent
      {:ok, sub_id} = EventStore.subscribe_to_agent_events(:ml_agent_1, %{
        types: [:agent_health_changed, :agent_task_completed]
      })
      
      # Receive events
      receive do
        {:agent_event, ^sub_id, event} ->
          handle_agent_event(event)
      end
  """
  @spec subscribe_to_agent_events(agent_id(), map()) :: 
    {:ok, String.t()} | {:error, Foundation.Types.Error.t()}
  def subscribe_to_agent_events(agent_id, filter \\ %{})
  
  @doc """
  Get correlated events across multiple agents.
  
  Returns all events with the specified correlation ID, useful for
  tracing multi-agent workflows and coordination scenarios.
  
  ## Examples
  
      # Get all events for a coordination session
      {:ok, events} = EventStore.get_agent_correlated_events("coordination_session_789")
      
      # Events might include:
      # - consensus_started (coordinator agent)
      # - consensus_vote (participant agents)  
      # - consensus_completed (coordinator agent)
  """
  @spec get_agent_correlated_events(correlation_id()) :: 
    {:ok, [map()]} | {:error, Foundation.Types.Error.t()}
  def get_agent_correlated_events(correlation_id)
  
  @doc """
  Get agent event statistics and analytics.
  
  Returns comprehensive statistics about events for the specified agent,
  including event type distribution, frequency, and trends.
  
  ## Examples
  
      {:ok, stats} = EventStore.get_agent_event_stats(:ml_agent_1)
      
      # => %{
      #   total_events: 1247,
      #   event_type_distribution: %{
      #     agent_task_completed: 1100,
      #     agent_health_changed: 12,
      #     agent_error_occurred: 5
      #   },
      #   events_per_hour: 24.5,
      #   most_recent_event: ~U[2024-01-01 12:00:00Z]
      # }
  """
  @spec get_agent_event_stats(agent_id()) :: 
    {:ok, map()} | {:error, Foundation.Types.Error.t()}
  def get_agent_event_stats(agent_id)
end
```

## 6. Telemetry Service Agent-Aware API

```elixir
defmodule Foundation.Services.TelemetryService.AgentAPI do
  @moduledoc """
  Agent-aware telemetry with metric aggregation, alerting,
  and performance analytics for multi-agent systems.
  """
  
  @type metric_name :: [atom()]
  @type metric_value :: number()
  @type metric_type :: :counter | :gauge | :histogram
  
  @doc """
  Record agent-specific metric.
  
  Records a metric with automatic agent context enrichment for
  comprehensive agent performance monitoring.
  
  ## Examples
  
      # Record agent task duration
      TelemetryService.record_agent_metric(
        :ml_agent_1,
        [:agent, :task, :duration],
        250.5,
        :histogram,
        %{task_type: :inference, model: "gpt-4"}
      )
      
      # Record agent resource usage
      TelemetryService.record_agent_metric(
        :ml_agent_1,
        [:agent, :resource, :memory],
        0.75,
        :gauge
      )
  """
  @spec record_agent_metric(agent_id(), metric_name(), metric_value(), metric_type(), map()) :: 
    :ok
  def record_agent_metric(agent_id, metric_name, value, type, metadata \\ %{})
  
  @doc """
  Get aggregated metrics for an agent.
  
  Returns processed and aggregated metrics for the specified agent,
  including trends, averages, and performance indicators.
  
  ## Examples
  
      {:ok, metrics} = TelemetryService.get_agent_metrics(:ml_agent_1, %{
        since: DateTime.add(DateTime.utc_now(), -3600),  # Last hour
        metrics: [[:agent, :task, :duration], [:agent, :resource, :memory]]
      })
      
      # => [
      #   %{
      #     name: [:agent, :task, :duration],
      #     type: :histogram,
      #     count: 45,
      #     avg: 225.7,
      #     min: 150.2,
      #     max: 401.3,
      #     percentiles: %{p50: 220.1, p95: 350.8, p99: 385.2}
      #   }
      # ]
  """
  @spec get_agent_metrics(agent_id(), map()) :: 
    {:ok, [map()]} | {:error, Foundation.Types.Error.t()}
  def get_agent_metrics(agent_id, filter \\ %{})
  
  @doc """
  Create agent-specific alert.
  
  Sets up automatic alerting for agent metrics that exceed
  specified thresholds or meet certain conditions.
  
  ## Examples
  
      # Alert on high memory usage
      alert_spec = %{
        name: :agent_high_memory,
        agent_id: :ml_agent_1,
        metric_path: [:agent, :resource, :memory],
        threshold: 0.9,
        condition: :greater_than,
        window: 300_000  # 5 minutes
      }
      
      :ok = TelemetryService.create_agent_alert(alert_spec)
      
      # Alert on low task completion rate
      performance_alert = %{
        name: :agent_low_performance,
        agent_id: :ml_agent_1,
        metric_path: [:agent, :task, :completion_rate],
        threshold: 0.8,
        condition: :less_than,
        window: 600_000  # 10 minutes
      }
      
      :ok = TelemetryService.create_agent_alert(performance_alert)
  """
  @spec create_agent_alert(map()) :: 
    :ok | {:error, Foundation.Types.Error.t()}
  def create_agent_alert(alert_specification)
  
  @doc """
  Get agent performance analytics.
  
  Returns comprehensive performance analytics for the agent including
  trends, efficiency metrics, and comparative analysis.
  
  ## Examples
  
      {:ok, analytics} = TelemetryService.get_agent_analytics(:ml_agent_1, %{
        time_range: :last_24_hours,
        include_trends: true,
        compare_to_baseline: true
      })
      
      # => %{
      #   performance_score: 0.87,
      #   efficiency_trend: :improving,
      #   resource_utilization: %{
      #     memory: %{avg: 0.68, trend: :stable},
      #     cpu: %{avg: 0.45, trend: :decreasing}
      #   },
      #   task_metrics: %{
      #     completion_rate: 0.94,
      #     avg_duration: 235.8,
      #     error_rate: 0.02
      #   },
      #   recommendations: [
      #     "Consider increasing task batch size for better efficiency",
      #     "Memory usage is optimal"
      #   ]
      # }
  """
  @spec get_agent_analytics(agent_id(), map()) :: 
    {:ok, map()} | {:error, Foundation.Types.Error.t()}
  def get_agent_analytics(agent_id, options \\ %{})
end
```

## 7. Coordination Service Agent-Aware API

```elixir
defmodule Foundation.Coordination.Service.AgentAPI do
  @moduledoc """
  Agent-aware coordination with intelligent participant selection,
  health-based decision making, and resource-aware coordination.
  """
  
  @type coordination_id :: atom() | String.t()
  @type consensus_strategy :: :unanimous | :majority | :quorum | :health_weighted
  
  @doc """
  Perform agent-aware consensus.
  
  Initiates consensus that considers agent health, capabilities, and
  current load when making decisions and selecting participants.
  
  ## Examples
  
      # Consensus with health-weighted voting
      {:ok, result} = CoordinationService.agent_consensus(
        :model_selection,
        [:ml_agent_1, :ml_agent_2, :ml_agent_3],
        %{models: ["gpt-4", "claude-3"], task: :classification},
        %{
          strategy: :health_weighted,
          timeout: 10_000,
          min_healthy_participants: 2,
          capability_required: :inference
        }
      )
      
      # Capability-based consensus
      {:ok, result} = CoordinationService.agent_consensus(
        :resource_allocation,
        :auto_select,  # Automatically select capable agents
        %{resources: [:gpu_1, :gpu_2], task: :training},
        %{
          strategy: :majority,
          required_capability: :training,
          min_participants: 3,
          exclude_degraded: true
        }
      )
  """
  @spec agent_consensus(coordination_id(), [agent_id()] | :auto_select, any(), map()) :: 
    {:ok, map()} | {:error, Foundation.Types.Error.t()}
  def agent_consensus(coordination_id, participants, proposal, options \\ %{})
  
  @doc """
  Create agent barrier with health monitoring.
  
  Creates a synchronization barrier that monitors participant health
  and can adapt to agent failures or degradation.
  
  ## Examples
  
      # Barrier with health monitoring
      :ok = CoordinationService.create_agent_barrier(
        :training_epoch_complete,
        [:trainer_1, :trainer_2, :trainer_3],
        %{
          health_check_interval: 5_000,
          auto_exclude_unhealthy: true,
          min_healthy_participants: 2
        }
      )
  """
  @spec create_agent_barrier(atom(), [agent_id()], map()) :: 
    :ok | {:error, Foundation.Types.Error.t()}
  def create_agent_barrier(barrier_id, participants, options \\ %{})
  
  @doc """
  Intelligent leader election based on agent capabilities.
  
  Elects a leader considering agent health, capabilities, current load,
  and coordination history for optimal leadership selection.
  
  ## Examples
  
      # Election with capability requirements
      {:ok, leader} = CoordinationService.elect_agent_leader(
        [:agent_1, :agent_2, :agent_3],
        %{
          required_capabilities: [:coordination, :monitoring],
          prefer_healthy: true,
          consider_load: true,
          exclude_overloaded: true
        }
      )
      
      # Election for specific role
      {:ok, coordinator} = CoordinationService.elect_agent_leader(
        :auto_select,  # Select from all available agents
        %{
          role: :training_coordinator,
          required_capabilities: [:training, :coordination],
          min_resource_availability: %{memory: 0.3, cpu: 0.4}
        }
      )
  """
  @spec elect_agent_leader([agent_id()] | :auto_select, map()) :: 
    {:ok, agent_id()} | {:error, Foundation.Types.Error.t()}
  def elect_agent_leader(candidates, options \\ %{})
  
  @doc """
  Resource-aware coordination with allocation management.
  
  Performs coordination while considering and managing resource
  allocation across participating agents.
  
  ## Examples
  
      # Coordination with resource allocation
      {:ok, result} = CoordinationService.coordinate_with_resources(
        :distributed_training,
        [:trainer_1, :trainer_2, :trainer_3],
        %{
          task: :model_training,
          dataset_size: 1_000_000,
          batch_size: 1000
        },
        %{
          resource_requirements: %{memory: 0.8, cpu: 0.6},
          auto_allocate_resources: true,
          fail_if_insufficient: true,
          coordination_type: :consensus
        }
      )
  """
  @spec coordinate_with_resources(coordination_id(), [agent_id()], any(), map()) :: 
    {:ok, map()} | {:error, Foundation.Types.Error.t()}
  def coordinate_with_resources(coordination_id, participants, task_spec, options \\ %{})
  
  @doc """
  Get coordination analytics for agents.
  
  Returns detailed analytics about agent coordination performance,
  participation rates, and collaboration effectiveness.
  
  ## Examples
  
      {:ok, analytics} = CoordinationService.get_agent_coordination_analytics(
        [:ml_agent_1, :ml_agent_2],
        %{time_range: :last_7_days}
      )
      
      # => %{
      #   agents: %{
      #     ml_agent_1: %{
      #       participation_rate: 0.89,
      #       leadership_rate: 0.25,
      #       consensus_agreement_rate: 0.93,
      #       avg_response_time: 150.5
      #     }
      #   },
      #   collaboration_matrix: %{
      #     {:ml_agent_1, :ml_agent_2} => %{
      #       coordination_count: 45,
      #       success_rate: 0.96,
      #       avg_duration: 2500
      #     }
      #   }
      # }
  """
  @spec get_agent_coordination_analytics([agent_id()], map()) :: 
    {:ok, map()} | {:error, Foundation.Types.Error.t()}
  def get_agent_coordination_analytics(agent_ids, options \\ %{})
end
```

## 8. Resource Manager API

```elixir
defmodule Foundation.Infrastructure.ResourceManager.API do
  @moduledoc """
  Comprehensive resource management for agents with allocation,
  monitoring, and predictive management capabilities.
  """
  
  @type resource_limits :: %{
    memory: non_neg_integer(),      # Bytes
    cpu: float(),                   # Number of cores
    network_connections: non_neg_integer(),
    storage: non_neg_integer(),     # Bytes
    custom: %{atom() => any()}      # Custom resources
  }
  
  @doc """
  Register agent with resource requirements.
  
  Registers an agent with its resource requirements and limits,
  enabling comprehensive resource management and monitoring.
  
  ## Examples
  
      resource_limits = %{
        memory: 2_000_000_000,        # 2GB
        cpu: 2.0,                     # 2 cores
        network_connections: 100,
        storage: 10_000_000_000,      # 10GB
        custom: %{
          gpu_memory: 4_000_000_000,  # 4GB GPU
          model_slots: 5
        }
      }
      
      :ok = ResourceManager.register_agent(
        :ml_agent_1,
        resource_limits,
        %{priority: :high, preemptible: false}
      )
  """
  @spec register_agent(agent_id(), resource_limits(), map()) :: 
    :ok | {:error, Foundation.Types.Error.t()}
  def register_agent(agent_id, resource_limits, metadata \\ %{})
  
  @doc """
  Check resource availability for agent operation.
  
  Verifies if sufficient resources are available for the requested
  operation, considering current allocation and system constraints.
  
  ## Examples
  
      # Check if agent can allocate additional memory
      case ResourceManager.check_resource_availability(
        :ml_agent_1, 
        :memory, 
        500_000_000  # 500MB
      ) do
        :ok -> 
          # Sufficient memory available
          proceed_with_allocation()
          
        {:error, %{error_type: :agent_resource_limit_exceeded}} ->
          # Agent would exceed its memory limit
          cleanup_or_wait()
          
        {:error, %{error_type: :system_resource_critical}} ->
          # System memory critically low
          defer_operation()
      end
  """
  @spec check_resource_availability(agent_id(), atom(), any()) :: 
    :ok | {:error, Foundation.Types.Error.t()}
  def check_resource_availability(agent_id, resource_type, required_amount)
  
  @doc """
  Allocate resources to agent.
  
  Allocates specified resources to the agent and updates tracking
  to prevent over-allocation and enable monitoring.
  
  ## Examples
  
      # Allocate resources for training task
      :ok = ResourceManager.allocate_resources(:ml_agent_1, %{
        memory: 1_000_000_000,       # 1GB
        cpu: 1.5,                    # 1.5 cores
        custom: %{gpu_memory: 2_000_000_000}  # 2GB GPU
      })
  """
  @spec allocate_resources(agent_id(), resource_limits()) :: 
    :ok | {:error, Foundation.Types.Error.t()}
  def allocate_resources(agent_id, resource_allocation)
  
  @doc """
  Release resources from agent.
  
  Releases previously allocated resources, making them available
  for other agents and updating system resource tracking.
  
  ## Examples
  
      # Release resources after task completion
      :ok = ResourceManager.release_resources(:ml_agent_1, %{
        memory: 1_000_000_000,
        cpu: 1.5,
        custom: %{gpu_memory: 2_000_000_000}
      })
  """
  @spec release_resources(agent_id(), resource_limits()) :: :ok
  def release_resources(agent_id, resource_deallocation)
  
  @doc """
  Get comprehensive resource status for agent.
  
  Returns detailed resource utilization, allocation, and health
  information for the specified agent.
  
  ## Examples
  
      {:ok, status} = ResourceManager.get_agent_resource_status(:ml_agent_1)
      
      # => %{
      #   agent_id: :ml_agent_1,
      #   resource_limits: %{memory: 2_000_000_000, cpu: 2.0},
      #   current_usage: %{memory: 1_200_000_000, cpu: 1.2},
      #   utilization_percentage: %{memory: 0.6, cpu: 0.6},
      #   health_status: :healthy,
      #   recommendations: ["Consider increasing CPU allocation for optimal performance"]
      # }
  """
  @spec get_agent_resource_status(agent_id()) :: 
    {:ok, map()} | {:error, Foundation.Types.Error.t()}
  def get_agent_resource_status(agent_id)
  
  @doc """
  Update agent resource limits dynamically.
  
  Allows runtime adjustment of agent resource limits based on
  changing requirements or performance characteristics.
  
  ## Examples
  
      # Increase memory limit for high-performing agent
      :ok = ResourceManager.update_agent_limits(:ml_agent_1, %{
        memory: 4_000_000_000  # Increase to 4GB
      })
      
      # Decrease limits for underperforming agent
      :ok = ResourceManager.update_agent_limits(:slow_agent, %{
        cpu: 0.5  # Reduce to 0.5 cores
      })
  """
  @spec update_agent_limits(agent_id(), resource_limits()) :: 
    :ok | {:error, Foundation.Types.Error.t()}
  def update_agent_limits(agent_id, new_limits)
  
  @doc """
  Get system-wide resource status and analytics.
  
  Returns comprehensive system resource status including allocation
  efficiency, utilization trends, and optimization recommendations.
  
  ## Examples
  
      {:ok, system_status} = ResourceManager.get_system_resource_status()
      
      # => %{
      #   total_resources: %{memory: 32_000_000_000, cpu: 16.0},
      #   allocated_resources: %{memory: 24_000_000_000, cpu: 12.5},
      #   utilization: %{memory: 0.75, cpu: 0.78},
      #   agent_count: 12,
      #   resource_efficiency: 0.87,
      #   recommendations: [
      #     "Consider rebalancing CPU allocation",
      #     "Memory utilization is optimal"
      #   ]
      # }
  """
  @spec get_system_resource_status() :: 
    {:ok, map()} | {:error, Foundation.Types.Error.t()}
  def get_system_resource_status()
end
```

## Backward Compatibility Guarantees

### Preserved APIs (100% Compatible)

All existing Foundation APIs remain completely unchanged:

1. **ProcessRegistry**: `register/4`, `lookup/2`, `unregister/2`, `list_all/1`
2. **CircuitBreaker**: `start_fuse_instance/2`, `execute/3`, `get_status/1`
3. **RateLimiter**: `check_rate/4`, `execute_with_limit/6`, `get_status/2`
4. **ConfigServer**: `get/0`, `get/1`, `update/2`, `subscribe/1`
5. **EventStore**: `store/1`, `query/1`, `subscribe/1`
6. **TelemetryService**: `emit/3`, `get_stats/0`
7. **Coordination**: All existing primitive APIs

### Migration Strategy

1. **Additive Enhancement**: New functionality through new modules and methods
2. **Optional Parameters**: New optional parameters for enhanced functionality
3. **Graceful Fallback**: Agent-unaware calls work exactly as before
4. **Progressive Adoption**: Services can adopt agent-awareness incrementally

## Example Usage Patterns

### Basic Agent Registration and Discovery

```elixir
# Register an ML agent
agent_metadata = %{
  type: :ml_agent,
  capabilities: [:nlp, :classification],
  health: :healthy,
  state: :ready,
  resource_usage: %{memory: 0.6, cpu: 0.4}
}

:ok = ProcessRegistry.register_agent(:production, :ml_agent_1, pid, agent_metadata)

# Find agents by capability
nlp_agents = ProcessRegistry.lookup_agents_by_capability(:production, :nlp)

# Get effective configuration for agent
{:ok, model_config} = ConfigServer.get_effective_config(:ml_agent_1, [:model, :config])
```

### Protected Agent Operations

```elixir
# Set up infrastructure protection for agent
{:ok, _} = AgentCircuitBreaker.start_agent_breaker(
  :ml_service,
  agent_id: :ml_agent_1,
  capability: :inference
)

# Execute protected operation with rate limiting and circuit breaking
result = with :ok <- AgentRateLimiter.check_rate_with_agent(:ml_agent_1, :inference),
              {:ok, result} <- AgentCircuitBreaker.execute_with_agent(
                :ml_service, 
                :ml_agent_1,
                fn -> perform_ml_inference(data) end
              ) do
  {:ok, result}
else
  error -> error
end
```

### Agent Coordination

```elixir
# Intelligent consensus with agent health consideration
{:ok, result} = CoordinationService.agent_consensus(
  :model_selection,
  :auto_select,  # Automatically select capable, healthy agents
  %{task: :classification, models: ["bert", "roberta"]},
  %{
    strategy: :health_weighted,
    required_capability: :classification,
    min_healthy_participants: 3
  }
)

# Resource-aware coordination
{:ok, coordination_result} = CoordinationService.coordinate_with_resources(
  :distributed_training,
  [:trainer_1, :trainer_2, :trainer_3],
  %{dataset: "large_corpus", epochs: 10},
  %{
    resource_requirements: %{memory: 0.8, cpu: 0.7},
    auto_allocate_resources: true
  }
)
```

This comprehensive API specification provides a solid foundation for implementing agent-aware capabilities while maintaining complete backward compatibility with the existing Foundation infrastructure.