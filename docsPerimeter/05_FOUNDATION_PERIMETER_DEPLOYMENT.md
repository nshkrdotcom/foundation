# Foundation Perimeter Production Deployment Guide

## Overview

This document provides comprehensive guidance for deploying Foundation Perimeter in production environments. It covers configuration management, monitoring, performance tuning, and operational considerations for BEAM-native AI systems at scale.

## Production Architecture

### Deployment Topology

```
Production Foundation Cluster
├── Load Balancer (Zone 1 Entry Point)
│   └── SSL Termination + Rate Limiting
├── Foundation Gateway Nodes (Zone 1)
│   ├── Foundation.Perimeter.External.*
│   ├── Input validation & sanitization
│   └── Request routing
├── Foundation Service Nodes (Zone 2)
│   ├── Foundation.Perimeter.Services.*
│   ├── Foundation.Registry
│   ├── Foundation.Coordination
│   └── Foundation.MABEAM.*
├── Foundation Compute Nodes (Zone 3-4)
│   ├── Foundation.Core.*
│   ├── Jido agents
│   └── ML pipeline execution
└── Foundation Monitoring & Telemetry
    ├── Perimeter metrics
    ├── Performance monitoring
    └── Alert management
```

## Configuration Management

### Production Configuration

```elixir
# config/prod.exs
import Config

# Foundation Perimeter Configuration
config :foundation, Foundation.Perimeter,
  # Zone-specific enforcement levels
  enforcement_config: %{
    external_level: :strict,
    service_level: :optimized,
    coupling_level: :none,
    core_level: :none
  },
  
  # Performance optimization
  validation_cache: %{
    enabled: true,
    ttl: 300_000,        # 5 minutes
    max_size: 50_000,    # Maximum cache entries
    cleanup_interval: 60_000  # Cleanup every minute
  },
  
  # Contract registry
  contract_registry: %{
    preload_contracts: true,
    auto_discovery: true,
    compilation_timeout: 30_000
  },
  
  # Error handling
  error_handling: %{
    detailed_errors: false,  # Simplified errors for production
    error_reporting: true,
    circuit_breaker: %{
      enabled: true,
      failure_threshold: 50,
      recovery_timeout: 30_000
    }
  },
  
  # Telemetry and monitoring
  telemetry: %{
    enabled: true,
    zone_metrics: true,
    contract_metrics: true,
    performance_tracking: true,
    export_interval: 10_000
  }

# Foundation service configuration with Perimeter
config :foundation, Foundation.Services,
  perimeter_enabled: true,
  validation_mode: :production,
  performance_mode: :optimized

# Clustering configuration
config :foundation, Foundation.Cluster,
  perimeter_coordination: true,
  cross_node_validation: false,  # Optimize for performance
  validation_delegation: true

# Jido integration configuration
config :jido_system, JidoSystem,
  foundation_perimeter: true,
  validation_level: :strategic,
  error_recovery: :automatic
```

### Environment-Specific Configuration

```elixir
# config/prod/staging.exs
import Config

config :foundation, Foundation.Perimeter,
  enforcement_config: %{
    external_level: :strict,
    service_level: :warn,     # More lenient for staging
    coupling_level: :log,
    core_level: :none
  },
  
  error_handling: %{
    detailed_errors: true,    # Detailed errors for debugging
    error_reporting: true,
    circuit_breaker: %{
      enabled: true,
      failure_threshold: 20,  # Lower threshold for early detection
      recovery_timeout: 15_000
    }
  }

# config/prod/production.exs
import Config

config :foundation, Foundation.Perimeter,
  enforcement_config: %{
    external_level: :strict,
    service_level: :optimized,
    coupling_level: :none,
    core_level: :none
  },
  
  error_handling: %{
    detailed_errors: false,
    error_reporting: true,
    circuit_breaker: %{
      enabled: true,
      failure_threshold: 100,  # Higher threshold for stability
      recovery_timeout: 60_000
    }
  }
```

## Performance Tuning

### Zone-Specific Optimization

#### Zone 1 (External Perimeter) Optimization

```elixir
defmodule Foundation.Perimeter.Production.Zone1 do
  @moduledoc """
  Production optimization for Zone 1 external perimeter.
  """
  
  use Foundation.Perimeter
  
  # Pre-compiled validation for performance
  @external_contracts [
    :create_dspex_program,
    :deploy_jido_agent,
    :execute_ml_pipeline,
    :coordinate_agents,
    :optimize_variables
  ]
  
  # Compile validation functions at startup
  def __after_compile__(env, _bytecode) do
    Enum.each(@external_contracts, fn contract ->
      compile_optimized_validator(contract)
    end)
  end
  
  # Rate limiting configuration
  def rate_limit_config do
    %{
      global_rate: {1000, :per_second},
      per_contract_rate: %{
        create_dspex_program: {100, :per_minute},
        deploy_jido_agent: {50, :per_minute},
        execute_ml_pipeline: {500, :per_minute},
        coordinate_agents: {200, :per_minute},
        optimize_variables: {100, :per_minute}
      },
      burst_allowance: 50
    }
  end
  
  # Input sanitization for security
  def sanitize_external_input(input) do
    input
    |> sanitize_strings()
    |> validate_size_limits()
    |> remove_dangerous_content()
  end
  
  defp sanitize_strings(input) when is_map(input) do
    Map.new(input, fn
      {key, value} when is_binary(value) ->
        {key, String.trim(value) |> String.slice(0, 10_000)}
      {key, value} ->
        {key, value}
    end)
  end
  
  defp validate_size_limits(input) do
    input_size = :erlang.external_size(input)
    
    if input_size > 1_000_000 do  # 1MB limit
      raise ArgumentError, "Input size exceeds limit: #{input_size} bytes"
    end
    
    input
  end
  
  defp remove_dangerous_content(input) do
    # Remove potentially dangerous content
    # Implementation would include SQL injection, XSS prevention, etc.
    input
  end
end
```

#### Zone 2 (Strategic Boundaries) Optimization

```elixir
defmodule Foundation.Perimeter.Production.Zone2 do
  @moduledoc """
  Production optimization for Zone 2 strategic boundaries.
  """
  
  # Cache frequently accessed validations
  def optimized_service_validation(contract, data) do
    cache_key = generate_cache_key(contract, data)
    
    case :ets.lookup(:zone2_validation_cache, cache_key) do
      [{^cache_key, result, expiry}] when expiry > :erlang.system_time(:millisecond) ->
        Foundation.Telemetry.increment([:foundation, :perimeter, :zone2, :cache_hit])
        result
      
      _ ->
        Foundation.Telemetry.increment([:foundation, :perimeter, :zone2, :cache_miss])
        result = perform_validation(contract, data)
        store_in_cache(cache_key, result)
        result
    end
  end
  
  # Pre-validate service specifications
  def prevalidate_service_specs do
    Foundation.Registry.list_services()
    |> Enum.each(fn {service_id, spec} ->
      case validate_service_specification(spec) do
        :ok -> 
          :ets.insert(:prevalidated_services, {service_id, :valid})
        {:error, _} ->
          Logger.warning("Invalid service specification: #{service_id}")
      end
    end)
  end
  
  # Fast path for known valid services
  def fast_path_validation(service_id, operation) do
    case :ets.lookup(:prevalidated_services, service_id) do
      [{^service_id, :valid}] ->
        {:ok, :fast_path}
      _ ->
        {:error, :requires_full_validation}
    end
  end
end
```

### Memory and CPU Optimization

```elixir
defmodule Foundation.Perimeter.Production.Optimization do
  @moduledoc """
  Production memory and CPU optimization for Foundation Perimeter.
  """
  
  # Memory pool for validation results
  def initialize_memory_pools do
    :ets.new(:validation_result_pool, [
      :set, :public, :named_table,
      {:write_concurrency, true},
      {:read_concurrency, true}
    ])
    
    :ets.new(:contract_compilation_cache, [
      :set, :public, :named_table,
      {:read_concurrency, true}
    ])
  end
  
  # CPU optimization through parallel validation
  def parallel_validation(contracts_and_data) when length(contracts_and_data) > 1 do
    tasks = Enum.map(contracts_and_data, fn {contract, data} ->
      Task.async(fn ->
        Foundation.Perimeter.ValidationService.validate(contract, data)
      end)
    end)
    
    Task.await_many(tasks, 5_000)
  end
  
  # Memory cleanup scheduling
  def schedule_memory_cleanup do
    Process.send_after(self(), :cleanup_memory, 300_000)  # Every 5 minutes
  end
  
  def handle_info(:cleanup_memory, state) do
    cleanup_expired_cache_entries()
    cleanup_validation_pools()
    force_garbage_collection()
    schedule_memory_cleanup()
    {:noreply, state}
  end
  
  defp cleanup_expired_cache_entries do
    current_time = :erlang.system_time(:millisecond)
    
    # Clean validation cache
    :ets.select_delete(:foundation_validation_cache, [
      {{:_, :_, :"$1"}, [{:<, :"$1", current_time}], [true]}
    ])
    
    # Clean zone 2 cache
    :ets.select_delete(:zone2_validation_cache, [
      {{:_, :_, :"$1"}, [{:<, :"$1", current_time}], [true]}
    ])
  end
  
  defp cleanup_validation_pools do
    # Remove old validation results
    pool_size = :ets.info(:validation_result_pool, :size)
    
    if pool_size > 10_000 do
      # Remove oldest 25% of entries
      entries_to_remove = div(pool_size, 4)
      
      :ets.foldl(fn entry, acc ->
        if length(acc) < entries_to_remove do
          :ets.delete_object(:validation_result_pool, entry)
          [entry | acc]
        else
          acc
        end
      end, [], :validation_result_pool)
    end
  end
  
  defp force_garbage_collection do
    # Force garbage collection on high memory usage
    memory_usage = :erlang.memory(:total)
    memory_limit = 2_000_000_000  # 2GB
    
    if memory_usage > memory_limit do
      :erlang.garbage_collect()
      Logger.info("Forced garbage collection due to high memory usage: #{memory_usage}")
    end
  end
end
```

## Monitoring and Observability

### Telemetry Integration

```elixir
defmodule Foundation.Perimeter.Production.Telemetry do
  @moduledoc """
  Production telemetry and monitoring for Foundation Perimeter.
  """
  
  require Logger
  
  # Telemetry event definitions
  @telemetry_events [
    [:foundation, :perimeter, :validation, :start],
    [:foundation, :perimeter, :validation, :stop],
    [:foundation, :perimeter, :validation, :error],
    [:foundation, :perimeter, :cache, :hit],
    [:foundation, :perimeter, :cache, :miss],
    [:foundation, :perimeter, :zone, :transition],
    [:foundation, :perimeter, :contract, :violation],
    [:foundation, :perimeter, :performance, :degradation]
  ]
  
  def setup_telemetry do
    # Attach telemetry handlers
    Enum.each(@telemetry_events, &attach_handler/1)
    
    # Setup periodic metrics
    :telemetry.attach(
      "foundation-perimeter-metrics",
      [:foundation, :perimeter, :metrics],
      &handle_metrics/4,
      []
    )
    
    # Schedule periodic metrics emission
    schedule_metrics_emission()
  end
  
  defp attach_handler(event) do
    :telemetry.attach(
      "foundation-perimeter-#{Enum.join(event, "-")}",
      event,
      &handle_telemetry_event/4,
      %{event: event}
    )
  end
  
  def handle_telemetry_event(event, measurements, metadata, config) do
    case event do
      [:foundation, :perimeter, :validation, :start] ->
        handle_validation_start(measurements, metadata)
      
      [:foundation, :perimeter, :validation, :stop] ->
        handle_validation_stop(measurements, metadata)
      
      [:foundation, :perimeter, :validation, :error] ->
        handle_validation_error(measurements, metadata)
      
      [:foundation, :perimeter, :performance, :degradation] ->
        handle_performance_degradation(measurements, metadata)
      
      _ ->
        handle_generic_event(event, measurements, metadata)
    end
  end
  
  defp handle_validation_start(measurements, metadata) do
    # Record validation start metrics
    Foundation.Metrics.increment("foundation.perimeter.validations.started", %{
      zone: determine_zone(metadata.contract_module),
      contract: metadata.contract_name
    })
  end
  
  defp handle_validation_stop(measurements, metadata) do
    duration = measurements.duration
    
    # Record successful validation
    Foundation.Metrics.timing("foundation.perimeter.validation.duration", duration, %{
      zone: determine_zone(metadata.contract_module),
      contract: metadata.contract_name
    })
    
    Foundation.Metrics.increment("foundation.perimeter.validations.completed", %{
      zone: determine_zone(metadata.contract_module),
      contract: metadata.contract_name
    })
    
    # Check for performance degradation
    if duration > performance_threshold(metadata.contract_module) do
      :telemetry.execute(
        [:foundation, :perimeter, :performance, :degradation],
        %{duration: duration},
        metadata
      )
    end
  end
  
  defp handle_validation_error(measurements, metadata) do
    Foundation.Metrics.increment("foundation.perimeter.validations.failed", %{
      zone: determine_zone(metadata.contract_module),
      contract: metadata.contract_name,
      error_type: classify_error(metadata.error)
    })
    
    # Alert on high error rates
    error_rate = calculate_error_rate(metadata.contract_module, metadata.contract_name)
    
    if error_rate > 0.05 do  # 5% error rate threshold
      send_alert(:high_error_rate, %{
        contract_module: metadata.contract_module,
        contract_name: metadata.contract_name,
        error_rate: error_rate
      })
    end
  end
  
  defp handle_performance_degradation(measurements, metadata) do
    Logger.warning("Performance degradation detected", [
      contract_module: metadata.contract_module,
      contract_name: metadata.contract_name,
      duration: measurements.duration,
      threshold: performance_threshold(metadata.contract_module)
    ])
    
    send_alert(:performance_degradation, %{
      contract_module: metadata.contract_module,
      contract_name: metadata.contract_name,
      duration: measurements.duration
    })
  end
  
  # Metrics emission
  defp schedule_metrics_emission do
    Process.send_after(self(), :emit_metrics, 10_000)  # Every 10 seconds
  end
  
  def handle_info(:emit_metrics, state) do
    emit_zone_metrics()
    emit_cache_metrics()
    emit_system_metrics()
    schedule_metrics_emission()
    {:noreply, state}
  end
  
  defp emit_zone_metrics do
    zones = [:external, :strategic, :coupling, :core]
    
    Enum.each(zones, fn zone ->
      metrics = get_zone_performance_metrics(zone)
      
      Foundation.Metrics.gauge("foundation.perimeter.zone.average_duration", 
        metrics.average_duration, %{zone: zone})
      
      Foundation.Metrics.gauge("foundation.perimeter.zone.throughput", 
        metrics.throughput, %{zone: zone})
      
      Foundation.Metrics.gauge("foundation.perimeter.zone.error_rate", 
        metrics.error_rate, %{zone: zone})
    end)
  end
  
  defp emit_cache_metrics do
    cache_stats = Foundation.Perimeter.ValidationService.get_performance_stats()
    
    Foundation.Metrics.gauge("foundation.perimeter.cache.hit_rate", 
      cache_stats.cache_hits / (cache_stats.cache_hits + cache_stats.cache_misses))
    
    Foundation.Metrics.gauge("foundation.perimeter.cache.size", 
      :ets.info(:foundation_validation_cache, :size))
  end
  
  defp emit_system_metrics do
    # System resource metrics
    memory_usage = :erlang.memory(:total)
    process_count = :erlang.system_info(:process_count)
    
    Foundation.Metrics.gauge("foundation.perimeter.memory.usage", memory_usage)
    Foundation.Metrics.gauge("foundation.perimeter.processes.count", process_count)
  end
  
  # Helper functions
  defp determine_zone(contract_module) do
    module_string = Atom.to_string(contract_module)
    
    cond do
      String.contains?(module_string, "External") -> :external
      String.contains?(module_string, "Services") -> :strategic
      String.contains?(module_string, "Coupling") -> :coupling
      true -> :core
    end
  end
  
  defp performance_threshold(contract_module) do
    case determine_zone(contract_module) do
      :external -> 15_000    # 15ms
      :strategic -> 5_000    # 5ms
      :coupling -> 1_000     # 1ms
      :core -> 500           # 0.5ms
    end
  end
  
  defp classify_error(error) do
    cond do
      String.contains?(inspect(error), "validation") -> :validation_error
      String.contains?(inspect(error), "timeout") -> :timeout_error
      String.contains?(inspect(error), "circuit") -> :circuit_breaker_error
      true -> :unknown_error
    end
  end
  
  defp send_alert(alert_type, metadata) do
    # Integration with alerting system
    alert = %{
      type: alert_type,
      severity: determine_severity(alert_type),
      metadata: metadata,
      timestamp: DateTime.utc_now(),
      source: "foundation_perimeter"
    }
    
    Foundation.Alerts.send(alert)
  end
  
  defp determine_severity(alert_type) do
    case alert_type do
      :high_error_rate -> :warning
      :performance_degradation -> :warning
      :circuit_breaker_trip -> :critical
      _ -> :info
    end
  end
end
```

### Health Checks

```elixir
defmodule Foundation.Perimeter.Production.HealthCheck do
  @moduledoc """
  Health check system for Foundation Perimeter.
  """
  
  def check_perimeter_health do
    %{
      validation_service: check_validation_service(),
      contract_registry: check_contract_registry(),
      cache_system: check_cache_system(),
      zone_performance: check_zone_performance(),
      overall_status: :healthy  # Determined by individual checks
    }
    |> determine_overall_status()
  end
  
  defp check_validation_service do
    try do
      # Test validation service responsiveness
      test_data = %{test: "health_check"}
      
      start_time = System.monotonic_time(:microsecond)
      result = Foundation.Perimeter.ValidationService.validate(
        Foundation.Perimeter.External.DSPEx,
        :health_check,
        test_data
      )
      end_time = System.monotonic_time(:microsecond)
      
      duration = end_time - start_time
      
      case result do
        {:ok, _} ->
          %{status: :healthy, response_time: duration}
        
        {:error, _} ->
          %{status: :degraded, response_time: duration, reason: "validation_failed"}
      end
    rescue
      error ->
        %{status: :unhealthy, reason: "service_error", error: inspect(error)}
    end
  end
  
  defp check_contract_registry do
    try do
      # Check contract registry accessibility
      contracts = Foundation.Perimeter.ContractRegistry.list_contracts()
      
      %{
        status: :healthy,
        contract_count: length(contracts),
        registry_responsive: true
      }
    rescue
      error ->
        %{status: :unhealthy, reason: "registry_error", error: inspect(error)}
    end
  end
  
  defp check_cache_system do
    try do
      cache_size = :ets.info(:foundation_validation_cache, :size)
      cache_memory = :ets.info(:foundation_validation_cache, :memory)
      
      status = cond do
        cache_size > 100_000 -> :degraded  # Cache too large
        cache_memory > 100_000_000 -> :degraded  # Using too much memory (100MB)
        true -> :healthy
      end
      
      %{
        status: status,
        cache_size: cache_size,
        cache_memory: cache_memory
      }
    rescue
      error ->
        %{status: :unhealthy, reason: "cache_error", error: inspect(error)}
    end
  end
  
  defp check_zone_performance do
    zones = [:external, :strategic, :coupling, :core]
    
    zone_checks = Enum.map(zones, fn zone ->
      metrics = get_zone_performance_metrics(zone)
      threshold = performance_threshold_for_zone(zone)
      
      status = if metrics.average_duration > threshold do
        :degraded
      else
        :healthy
      end
      
      {zone, %{
        status: status,
        average_duration: metrics.average_duration,
        threshold: threshold
      }}
    end)
    
    Map.new(zone_checks)
  end
  
  defp determine_overall_status(health_report) do
    statuses = [
      health_report.validation_service.status,
      health_report.contract_registry.status,
      health_report.cache_system.status
    ] ++ Enum.map(health_report.zone_performance, fn {_zone, check} -> check.status end)
    
    overall_status = cond do
      Enum.any?(statuses, &(&1 == :unhealthy)) -> :unhealthy
      Enum.any?(statuses, &(&1 == :degraded)) -> :degraded
      true -> :healthy
    end
    
    %{health_report | overall_status: overall_status}
  end
  
  defp performance_threshold_for_zone(zone) do
    case zone do
      :external -> 15_000
      :strategic -> 5_000
      :coupling -> 1_000
      :core -> 500
    end
  end
end
```

## Deployment Scripts

### Docker Configuration

```dockerfile
# Dockerfile
FROM elixir:1.15-alpine AS builder

# Install build dependencies
RUN apk add --no-cache build-base git

# Set work directory
WORKDIR /app

# Install hex and rebar
RUN mix local.hex --force && \
    mix local.rebar --force

# Copy mix files
COPY mix.exs mix.lock ./

# Install dependencies
RUN mix deps.get --only prod

# Copy source code
COPY . .

# Compile application
RUN MIX_ENV=prod mix compile

# Create release
RUN MIX_ENV=prod mix release

# Create runtime image
FROM alpine:3.18

# Install runtime dependencies
RUN apk add --no-cache openssl ncurses-libs

# Create app user
RUN addgroup -g 1001 -S foundation && \
    adduser -S -u 1001 -G foundation foundation

# Set work directory
WORKDIR /app

# Copy release from builder
COPY --from=builder --chown=foundation:foundation /app/_build/prod/rel/foundation ./

# Switch to app user
USER foundation

# Expose port
EXPOSE 4000

# Set environment
ENV MIX_ENV=prod

# Start application
CMD ["./bin/foundation", "start"]
```

### Kubernetes Deployment

```yaml
# k8s/foundation-perimeter-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: foundation-perimeter
  labels:
    app: foundation-perimeter
    component: ai-infrastructure
spec:
  replicas: 3
  selector:
    matchLabels:
      app: foundation-perimeter
  template:
    metadata:
      labels:
        app: foundation-perimeter
        zone: foundation-services
    spec:
      containers:
      - name: foundation
        image: foundation/perimeter:latest
        ports:
        - containerPort: 4000
          name: http
        - containerPort: 4369
          name: epmd
        - containerPort: 9100
          name: metrics
        env:
        - name: MIX_ENV
          value: "prod"
        - name: FOUNDATION_CLUSTER_NAME
          value: "production"
        - name: FOUNDATION_PERIMETER_MODE
          value: "production"
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "2Gi"
            cpu: "2000m"
        livenessProbe:
          httpGet:
            path: /health/perimeter
            port: 4000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready/perimeter
            port: 4000
          initialDelaySeconds: 5
          periodSeconds: 5
        volumeMounts:
        - name: config
          mountPath: /app/config/runtime.exs
          subPath: runtime.exs
      volumes:
      - name: config
        configMap:
          name: foundation-perimeter-config
---
apiVersion: v1
kind: Service
metadata:
  name: foundation-perimeter-service
spec:
  selector:
    app: foundation-perimeter
  ports:
  - port: 80
    targetPort: 4000
    name: http
  - port: 9100
    targetPort: 9100
    name: metrics
  type: LoadBalancer
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: foundation-perimeter-config
data:
  runtime.exs: |
    import Config
    
    config :foundation, Foundation.Perimeter,
      enforcement_config: %{
        external_level: :strict,
        service_level: :optimized,
        coupling_level: :none,
        core_level: :none
      },
      validation_cache: %{
        enabled: true,
        ttl: 300_000,
        max_size: 50_000
      }
```

### Deployment Automation

```bash
#!/bin/bash
# deploy-foundation-perimeter.sh

set -e

echo "🚀 Starting Foundation Perimeter deployment..."

# Configuration
ENVIRONMENT=${1:-production}
CLUSTER_NAME=${2:-foundation-prod}
IMAGE_TAG=${3:-latest}

echo "Environment: $ENVIRONMENT"
echo "Cluster: $CLUSTER_NAME"
echo "Image Tag: $IMAGE_TAG"

# Pre-deployment checks
echo "📋 Running pre-deployment checks..."

# Check cluster connectivity
kubectl cluster-info
if [ $? -ne 0 ]; then
    echo "❌ Failed to connect to Kubernetes cluster"
    exit 1
fi

# Check Foundation prerequisites
kubectl get namespace foundation-system > /dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "🔧 Creating foundation-system namespace..."
    kubectl create namespace foundation-system
fi

# Deploy Perimeter configuration
echo "📝 Deploying Perimeter configuration..."
envsubst < k8s/foundation-perimeter-config.yaml | kubectl apply -f -

# Deploy Perimeter services
echo "🚀 Deploying Perimeter services..."
envsubst < k8s/foundation-perimeter-deployment.yaml | kubectl apply -f -

# Wait for deployment
echo "⏳ Waiting for deployment to be ready..."
kubectl rollout status deployment/foundation-perimeter -n foundation-system --timeout=300s

# Run health checks
echo "🏥 Running health checks..."
sleep 30

PERIMETER_URL=$(kubectl get service foundation-perimeter-service -n foundation-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
curl -f "http://$PERIMETER_URL/health/perimeter" > /dev/null
if [ $? -eq 0 ]; then
    echo "✅ Perimeter health check passed"
else
    echo "❌ Perimeter health check failed"
    exit 1
fi

# Run smoke tests
echo "🧪 Running smoke tests..."
./scripts/run-smoke-tests.sh $PERIMETER_URL

echo "🎉 Foundation Perimeter deployment completed successfully!"
echo "🔗 Perimeter URL: http://$PERIMETER_URL"
echo "📊 Metrics URL: http://$PERIMETER_URL:9100/metrics"
```

This comprehensive deployment guide ensures Foundation Perimeter can be successfully deployed and operated in production environments with enterprise-grade reliability, monitoring, and performance characteristics.