defmodule Foundation.Telemetry.Metrics do
  @moduledoc """
  Telemetry metrics definitions for Prometheus export.

  This module defines all the metrics that Foundation exposes for monitoring.
  It uses Telemetry.Metrics to define metrics that can be exported to Prometheus
  or other monitoring systems.

  ## Usage

  Add to your application supervision tree:

      children = [
        {TelemetryMetricsPrometheus, [metrics: Foundation.Telemetry.Metrics.metrics()]}
      ]

  Or with custom configuration:

      children = [
        {TelemetryMetricsPrometheus,
         [
           metrics: Foundation.Telemetry.Metrics.metrics(),
           port: 9568,
           path: "/metrics"
         ]}
      ]
  """

  alias Telemetry.Metrics

  @doc """
  Returns the list of all Foundation telemetry metrics.
  """
  def metrics do
    cache_metrics() ++
      resource_manager_metrics() ++
      circuit_breaker_metrics() ++
      task_metrics() ++
      sensor_metrics() ++
      service_metrics() ++
      async_metrics()
  end

  @doc """
  Cache-related metrics.
  """
  def cache_metrics do
    [
      # Cache operation counters
      Metrics.counter("foundation.cache.hit.total",
        event_name: [:foundation, :cache, :hit],
        description: "Total number of cache hits"
      ),
      Metrics.counter("foundation.cache.miss.total",
        event_name: [:foundation, :cache, :miss],
        description: "Total number of cache misses",
        tags: [:reason]
      ),
      Metrics.counter("foundation.cache.put.total",
        event_name: [:foundation, :cache, :put],
        description: "Total number of cache puts"
      ),
      Metrics.counter("foundation.cache.delete.total",
        event_name: [:foundation, :cache, :delete],
        description: "Total number of cache deletes"
      ),

      # Cache operation latencies
      Metrics.distribution("foundation.cache.duration.microseconds",
        event_name: [:foundation, :cache, :hit],
        measurement: :duration,
        unit: {:native, :microsecond},
        description: "Cache operation duration"
      ),
      Metrics.distribution("foundation.cache.duration.microseconds",
        event_name: [:foundation, :cache, :miss],
        measurement: :duration,
        unit: {:native, :microsecond},
        description: "Cache operation duration"
      ),

      # Cache cleanup metrics
      Metrics.last_value("foundation.cache.cleanup.expired_count",
        event_name: [:foundation, :cache, :cleanup],
        measurement: :expired_count,
        description: "Number of expired entries in last cleanup"
      ),
      Metrics.summary("foundation.cache.cleanup.duration.microseconds",
        event_name: [:foundation, :cache, :cleanup],
        measurement: :duration,
        unit: {:native, :microsecond},
        description: "Cache cleanup duration"
      )
    ]
  end

  @doc """
  Resource Manager metrics.
  """
  def resource_manager_metrics do
    [
      # Resource acquisition
      Metrics.counter("foundation.resource_manager.acquired.total",
        event_name: [:foundation, :resource_manager, :acquired],
        description: "Total resources acquired",
        tags: [:resource_type]
      ),
      Metrics.counter("foundation.resource_manager.released.total",
        event_name: [:foundation, :resource_manager, :released],
        description: "Total resources released",
        tags: [:resource_type]
      ),
      Metrics.counter("foundation.resource_manager.denied.total",
        event_name: [:foundation, :resource_manager, :denied],
        description: "Total resource acquisitions denied",
        tags: [:resource_type, :reason]
      ),

      # Resource state
      Metrics.last_value("foundation.resource_manager.active_tokens",
        event_name: [:foundation, :resource_manager, :cleanup],
        measurement: :active_tokens,
        description: "Number of active resource tokens"
      ),
      Metrics.last_value("foundation.resource_manager.memory_mb",
        event_name: [:foundation, :resource_manager, :cleanup],
        measurement: :memory_mb,
        description: "Memory usage in MB"
      ),

      # Resource timing
      Metrics.distribution("foundation.resource_manager.acquisition.duration.microseconds",
        event_name: [:foundation, :resource_manager, :acquired],
        measurement: :duration,
        unit: {:native, :microsecond},
        description: "Resource acquisition duration"
      )
    ]
  end

  @doc """
  Circuit breaker metrics.
  """
  def circuit_breaker_metrics do
    [
      Metrics.last_value("foundation.circuit_breaker.state",
        event_name: [:foundation, :circuit_breaker, :opened],
        measurement: fn _ -> 2 end,
        description: "Circuit breaker state (0=closed, 1=half_open, 2=open)",
        tags: [:service]
      ),
      Metrics.last_value("foundation.circuit_breaker.state",
        event_name: [:foundation, :circuit_breaker, :closed],
        measurement: fn _ -> 0 end,
        description: "Circuit breaker state (0=closed, 1=half_open, 2=open)",
        tags: [:service]
      ),
      Metrics.last_value("foundation.circuit_breaker.state",
        event_name: [:foundation, :circuit_breaker, :half_open],
        measurement: fn _ -> 1 end,
        description: "Circuit breaker state (0=closed, 1=half_open, 2=open)",
        tags: [:service]
      ),
      Metrics.counter("foundation.circuit_breaker.trips.total",
        event_name: [:foundation, :circuit_breaker, :opened],
        description: "Total circuit breaker trips",
        tags: [:service]
      )
    ]
  end

  @doc """
  Task processing metrics.
  """
  def task_metrics do
    [
      # Task counters
      Metrics.counter("jido_system.task.started.total",
        event_name: [:jido_system, :task, :started],
        description: "Total tasks started",
        tags: [:task_type]
      ),
      Metrics.counter("jido_system.task.completed.total",
        event_name: [:jido_system, :task, :completed],
        description: "Total tasks completed",
        tags: [:task_type]
      ),
      Metrics.counter("jido_system.task.failed.total",
        event_name: [:jido_system, :task, :failed],
        description: "Total tasks failed",
        tags: [:task_type]
      ),

      # Task timing
      Metrics.distribution("jido_system.task.completed.duration.microseconds",
        event_name: [:jido_system, :task, :completed],
        measurement: :duration,
        unit: {:native, :microsecond},
        description: "Task completion duration"
      )
    ]
  end

  @doc """
  Sensor metrics.
  """
  def sensor_metrics do
    [
      # Performance sensor
      Metrics.last_value("jido_system.performance_sensor.agents_analyzed",
        event_name: [:jido_system, :performance_sensor, :analysis_completed],
        measurement: :agents_analyzed,
        description: "Number of agents analyzed",
        tags: [:sensor_id]
      ),
      Metrics.last_value("jido_system.performance_sensor.issues_detected",
        event_name: [:jido_system, :performance_sensor, :analysis_completed],
        measurement: :issues_detected,
        description: "Number of performance issues detected",
        tags: [:sensor_id]
      ),
      Metrics.summary("jido_system.performance_sensor.analysis.duration.microseconds",
        event_name: [:jido_system, :performance_sensor, :analysis_completed],
        measurement: :duration,
        unit: {:native, :microsecond},
        description: "Performance analysis duration"
      ),

      # Health sensor
      Metrics.last_value("jido_system.health_sensor.memory_usage_percent",
        event_name: [:jido_system, :health_sensor, :analysis_completed],
        measurement: :memory_usage_percent,
        description: "System memory usage percentage",
        tags: [:sensor_id]
      ),
      Metrics.last_value("jido_system.health_sensor.process_count",
        event_name: [:jido_system, :health_sensor, :analysis_completed],
        measurement: :process_count,
        description: "System process count",
        tags: [:sensor_id]
      ),

      # Health monitor
      Metrics.summary("jido_system.health_monitor.check.duration.milliseconds",
        event_name: [:jido_system, :health_monitor, :health_check],
        measurement: :duration,
        unit: {:native, :millisecond},
        description: "Health check duration"
      ),
      Metrics.counter("jido_system.health_monitor.agent_died.total",
        event_name: [:jido_system, :health_monitor, :agent_died],
        description: "Total agents that died"
      )
    ]
  end

  @doc """
  Service lifecycle metrics.
  """
  def service_metrics do
    [
      Metrics.counter("foundation.service.started.total",
        event_name: [:foundation, :service, :started],
        description: "Total service starts",
        tags: [:service]
      ),
      Metrics.counter("foundation.service.stopped.total",
        event_name: [:foundation, :service, :stopped],
        description: "Total service stops",
        tags: [:service, :reason]
      ),
      Metrics.summary("foundation.service.uptime.seconds",
        event_name: [:foundation, :service, :stopped],
        measurement: :uptime,
        unit: {:native, :second},
        description: "Service uptime"
      )
    ]
  end

  @doc """
  Async operation metrics.
  """
  def async_metrics do
    [
      Metrics.counter("foundation.async.started.total",
        event_name: [:foundation, :async, :started],
        description: "Total async operations started",
        tags: [:operation]
      ),
      Metrics.counter("foundation.async.completed.total",
        event_name: [:foundation, :async, :completed],
        description: "Total async operations completed",
        tags: [:operation]
      ),
      Metrics.counter("foundation.async.failed.total",
        event_name: [:foundation, :async, :failed],
        description: "Total async operations failed",
        tags: [:operation]
      ),
      Metrics.distribution("foundation.async.duration.microseconds",
        event_name: [:foundation, :async, :completed],
        measurement: :duration,
        unit: {:native, :microsecond},
        description: "Async operation duration"
      )
    ]
  end

  @doc """
  Custom metrics for specific use cases.
  """
  def custom_metrics(event_patterns) do
    Enum.flat_map(event_patterns, fn pattern ->
      [
        Metrics.counter("#{Enum.join(pattern, ".")}.total",
          event_name: pattern,
          description: "Total #{Enum.join(pattern, " ")}"
        ),
        Metrics.summary("#{Enum.join(pattern, ".")}.duration.microseconds",
          event_name: pattern,
          measurement: :duration,
          unit: {:native, :microsecond},
          description: "#{Enum.join(pattern, " ")} duration"
        )
      ]
    end)
  end
end
