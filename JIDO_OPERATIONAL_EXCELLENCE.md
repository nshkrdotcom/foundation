# JidoSystem Operational Excellence Guide

## Executive Summary

This guide outlines the operational practices, monitoring strategies, and runbooks needed to operate JidoSystem in production with excellence. It addresses the gap between "code complete" and "production ready" by focusing on Day 2 operations.

## Operational Maturity Model

### Level 1: Basic Operations (Current State)
- Manual deployments
- Basic logging
- Reactive incident response
- Limited visibility

### Level 2: Managed Operations (Target - 3 months)
- Automated deployments
- Structured logging
- Proactive monitoring
- Clear runbooks

### Level 3: Advanced Operations (Target - 6 months)
- Self-healing systems
- Predictive analytics
- Automated remediation
- Full observability

### Level 4: Excellence (Target - 12 months)
- AI-driven operations
- Zero-downtime everything
- Predictive scaling
- Business-aware automation

## Observability Stack

### 1. Metrics Architecture

```elixir
defmodule JidoSystem.Metrics do
  @moduledoc """
  Comprehensive metrics collection and reporting.
  """
  
  # Golden Signals
  def golden_signals do
    %{
      latency: [
        "jido.agent.instruction.duration",
        "jido.action.execution.duration",
        "jido.workflow.completion.duration"
      ],
      traffic: [
        "jido.agent.instructions.rate",
        "jido.signals.published.rate",
        "jido.api.requests.rate"
      ],
      errors: [
        "jido.agent.errors.rate",
        "jido.action.failures.rate",
        "jido.circuit_breaker.opens.rate"
      ],
      saturation: [
        "jido.agent.queue.size",
        "jido.resource.usage.percentage",
        "jido.connection_pool.active"
      ]
    }
  end
  
  # Business Metrics
  def business_metrics do
    %{
      throughput: "jido.business.transactions.completed",
      value: "jido.business.revenue.processed",
      quality: "jido.business.sla.compliance",
      efficiency: "jido.business.cost.per_transaction"
    }
  end
  
  # SLI Definitions
  def sli_definitions do
    [
      %{
        name: "api_availability",
        query: "sum(rate(http_requests_total{status!~'5..'}[5m])) / sum(rate(http_requests_total[5m]))",
        target: 0.999
      },
      %{
        name: "agent_success_rate",
        query: "sum(rate(agent_instructions_success[5m])) / sum(rate(agent_instructions_total[5m]))",
        target: 0.995
      },
      %{
        name: "p99_latency",
        query: "histogram_quantile(0.99, agent_instruction_duration_seconds)",
        target: 0.1 # 100ms
      }
    ]
  end
end
```

### 2. Logging Strategy

```elixir
defmodule JidoSystem.Logging do
  @moduledoc """
  Structured logging with correlation and context.
  """
  
  defmacro __using__(_opts) do
    quote do
      require Logger
      import JidoSystem.Logging
      
      @before_compile JidoSystem.Logging
    end
  end
  
  defmacro __before_compile__(_env) do
    quote do
      defoverridable [handle_event: 4]
      
      def handle_event(event, measurements, metadata, config) do
        # Add correlation ID
        metadata = add_correlation_id(metadata)
        
        # Add context
        metadata = add_context(metadata)
        
        # Structure log entry
        log_entry = %{
          timestamp: DateTime.utc_now(),
          level: log_level(event),
          event: event,
          measurements: measurements,
          metadata: metadata,
          context: get_context()
        }
        
        # Send to logging pipeline
        Logger.info(Jason.encode!(log_entry))
        
        # Call original handler
        super(event, measurements, metadata, config)
      end
    end
  end
  
  # Correlation across distributed system
  def with_correlation_id(correlation_id, fun) do
    Process.put(:correlation_id, correlation_id)
    
    try do
      fun.()
    after
      Process.delete(:correlation_id)
    end
  end
  
  # Rich context for debugging
  def with_context(context, fun) do
    current = Process.get(:log_context, %{})
    Process.put(:log_context, Map.merge(current, context))
    
    try do
      fun.()
    after
      Process.put(:log_context, current)
    end
  end
end
```

### 3. Distributed Tracing

```elixir
defmodule JidoSystem.Tracing do
  @moduledoc """
  OpenTelemetry integration for distributed tracing.
  """
  
  def setup do
    # Configure OpenTelemetry
    :opentelemetry.register_tracer(:jido_system, "1.0.0")
    
    # Auto-instrument key modules
    attach_telemetry_handlers()
    
    # Custom span attributes
    OpenTelemetry.register_span_processor(&add_custom_attributes/1)
  end
  
  defp attach_telemetry_handlers do
    handlers = [
      {[:jido, :agent, :instruction, :start], &handle_instruction_start/4},
      {[:jido, :agent, :instruction, :stop], &handle_instruction_stop/4},
      {[:jido, :action, :execute, :start], &handle_action_start/4},
      {[:jido, :action, :execute, :stop], &handle_action_stop/4}
    ]
    
    for {event, handler} <- handlers do
      :telemetry.attach(
        "#{inspect(event)}-tracer",
        event,
        handler,
        nil
      )
    end
  end
  
  # Create span for agent instruction
  defp handle_instruction_start(_event, _measurements, metadata, _config) do
    span_name = "#{metadata.agent_type}.#{metadata.action}"
    
    OpenTelemetry.with_span span_name do
      OpenTelemetry.set_attributes(%{
        "agent.id" => metadata.agent_id,
        "agent.type" => metadata.agent_type,
        "instruction.id" => metadata.instruction_id,
        "instruction.action" => metadata.action
      })
    end
  end
end
```

## Monitoring and Alerting

### 1. Alert Definitions

```yaml
# alerts/jido_system.yml
groups:
  - name: jido_system_availability
    rules:
      - alert: AgentHighErrorRate
        expr: |
          rate(jido_agent_errors_total[5m]) > 0.05
        for: 5m
        labels:
          severity: warning
          team: platform
        annotations:
          summary: "Agent {{ $labels.agent_type }} has high error rate"
          description: "Error rate is {{ $value | humanizePercentage }}"
          runbook: https://runbooks.jido.io/agent-high-error-rate

      - alert: CircuitBreakerOpen
        expr: |
          jido_circuit_breaker_state == 2  # 2 = open
        for: 1m
        labels:
          severity: critical
          team: platform
        annotations:
          summary: "Circuit breaker {{ $labels.service }} is open"
          description: "Service {{ $labels.service }} circuit breaker opened"
          runbook: https://runbooks.jido.io/circuit-breaker-open

      - alert: AgentQueueBacklog
        expr: |
          jido_agent_queue_size > 1000
        for: 10m
        labels:
          severity: warning
          team: platform
        annotations:
          summary: "Agent {{ $labels.agent_id }} has large queue backlog"
          description: "Queue size is {{ $value }}"
          runbook: https://runbooks.jido.io/agent-queue-backlog

  - name: jido_system_performance
    rules:
      - alert: HighP99Latency
        expr: |
          histogram_quantile(0.99, 
            rate(jido_agent_instruction_duration_seconds_bucket[5m])
          ) > 0.5
        for: 10m
        labels:
          severity: warning
          team: platform
        annotations:
          summary: "High P99 latency for agent instructions"
          description: "P99 latency is {{ $value }}s"
          runbook: https://runbooks.jido.io/high-p99-latency

  - name: jido_system_resources
    rules:
      - alert: HighMemoryUsage
        expr: |
          jido_beam_memory_usage_bytes / jido_beam_memory_limit_bytes > 0.9
        for: 5m
        labels:
          severity: critical
          team: platform
        annotations:
          summary: "BEAM memory usage critical"
          description: "Memory usage is {{ $value | humanizePercentage }}"
          runbook: https://runbooks.jido.io/high-memory-usage
```

### 2. Dashboards

```json
// dashboards/jido_overview.json
{
  "dashboard": {
    "title": "JidoSystem Overview",
    "panels": [
      {
        "title": "Golden Signals",
        "type": "row"
      },
      {
        "title": "Request Rate",
        "targets": [{
          "expr": "sum(rate(jido_agent_instructions_total[5m]))"
        }]
      },
      {
        "title": "Error Rate",
        "targets": [{
          "expr": "sum(rate(jido_agent_errors_total[5m])) / sum(rate(jido_agent_instructions_total[5m]))"
        }]
      },
      {
        "title": "P50/P95/P99 Latency",
        "targets": [
          {"expr": "histogram_quantile(0.5, rate(jido_agent_instruction_duration_seconds_bucket[5m]))"},
          {"expr": "histogram_quantile(0.95, rate(jido_agent_instruction_duration_seconds_bucket[5m]))"},
          {"expr": "histogram_quantile(0.99, rate(jido_agent_instruction_duration_seconds_bucket[5m]))"}
        ]
      },
      {
        "title": "Resource Saturation",
        "targets": [{
          "expr": "avg(jido_agent_queue_size)"
        }]
      }
    ]
  }
}
```

## Runbooks

### 1. Agent High Error Rate

```markdown
# Agent High Error Rate Runbook

## Alert
`AgentHighErrorRate`

## Impact
- Degraded agent performance
- Potential data processing delays
- SLA violations

## Investigation Steps

1. **Check error types**
   ```bash
   kubectl logs -l app=jido-system,component=agent --tail=1000 | \
     grep ERROR | jq -r '.error_type' | sort | uniq -c
   ```

2. **Identify affected agents**
   ```bash
   curl -s prometheus:9090/api/v1/query?query=rate(jido_agent_errors_total[5m]) | \
     jq -r '.data.result[] | select(.value[1] | tonumber > 0.05) | .metric.agent_id'
   ```

3. **Check recent deployments**
   ```bash
   kubectl rollout history deployment/jido-system
   ```

4. **Verify external dependencies**
   ```bash
   # Check database connectivity
   kubectl exec -it deployment/jido-system -- \
     mix run -e "IO.inspect(Ecto.Repo.query!('SELECT 1'))"
   
   # Check external API health
   curl -s https://api.external-service.com/health
   ```

## Remediation Steps

1. **Immediate mitigation**
   ```bash
   # Scale up healthy agents
   kubectl scale deployment/jido-system --replicas=+2
   
   # Enable circuit breakers if not already
   kubectl exec -it deployment/jido-system -- \
     mix remote_console
   > JidoSystem.Config.update([:infrastructure, :circuit_breaker_enabled], true)
   ```

2. **Rollback if deployment-related**
   ```bash
   # Rollback to previous version
   kubectl rollout undo deployment/jido-system
   
   # Monitor recovery
   watch "kubectl get pods -l app=jido-system"
   ```

3. **Restart affected agents**
   ```elixir
   # In remote console
   affected_agents = [...]  # From investigation
   for agent <- affected_agents do
     JidoSystem.restart_agent(agent)
   end
   ```

## Prevention

1. Improve error handling in agent code
2. Add retry logic for transient failures
3. Implement circuit breakers for external calls
4. Add canary deployments
```

### 2. Circuit Breaker Open

```markdown
# Circuit Breaker Open Runbook

## Alert
`CircuitBreakerOpen`

## Impact
- Service calls being rejected
- Potential cascading failures
- User-facing errors

## Investigation Steps

1. **Identify the protected service**
   ```bash
   # Check which service triggered the circuit breaker
   curl -s prometheus:9090/api/v1/query?query=jido_circuit_breaker_state==2 | \
     jq -r '.data.result[].metric.service'
   ```

2. **Check service health**
   ```bash
   # For external HTTP service
   curl -w "\n%{http_code}\n%{time_total}\n" https://service.example.com/health
   
   # For internal service
   kubectl get pods -l app=dependent-service
   kubectl logs -l app=dependent-service --tail=100
   ```

3. **Review error patterns**
   ```elixir
   # In remote console
   Foundation.CircuitBreaker.get_statistics(:service_name)
   ```

## Remediation Steps

1. **Fix underlying service issue**
   - Restart unhealthy pods
   - Scale up if under load
   - Check database connections
   - Verify network connectivity

2. **Manual circuit reset (if service recovered)**
   ```elixir
   # In remote console
   Foundation.CircuitBreaker.reset(:service_name)
   ```

3. **Adjust circuit breaker settings if needed**
   ```elixir
   Foundation.CircuitBreaker.configure(:service_name,
     failure_threshold: 10,      # Increase threshold
     recovery_timeout: 60_000,   # Longer recovery time
     failure_rate_threshold: 0.5 # Allow 50% failure rate
   )
   ```

## Prevention

1. Implement health checks for all external services
2. Add service mesh for better resilience
3. Use adaptive circuit breaker thresholds
4. Monitor service dependencies proactively
```

## Deployment Operations

### 1. Zero-Downtime Deployment Process

```elixir
defmodule JidoSystem.Deployment do
  @moduledoc """
  Orchestrates zero-downtime deployments.
  """
  
  def deploy(version, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, :rolling)
    
    case strategy do
      :rolling -> rolling_deployment(version, opts)
      :blue_green -> blue_green_deployment(version, opts)
      :canary -> canary_deployment(version, opts)
    end
  end
  
  defp rolling_deployment(version, opts) do
    with :ok <- pre_deployment_checks(),
         :ok <- create_deployment_record(version),
         :ok <- update_deployment_manifest(version),
         :ok <- wait_for_rollout(),
         :ok <- run_smoke_tests(),
         :ok <- post_deployment_verification() do
      {:ok, "Deployment successful"}
    else
      {:error, reason} ->
        rollback_deployment(version, reason)
        {:error, reason}
    end
  end
  
  defp canary_deployment(version, opts) do
    percentage = Keyword.get(opts, :initial_percentage, 10)
    
    with :ok <- deploy_canary(version, percentage),
         :ok <- monitor_canary_metrics(version),
         :ok <- progressive_rollout(version) do
      {:ok, "Canary deployment successful"}
    end
  end
end
```

### 2. Deployment Checklist

```yaml
# .deployment/checklist.yml
pre_deployment:
  - name: "Run tests"
    command: "mix test"
    required: true
    
  - name: "Run dialyzer"
    command: "mix dialyzer"
    required: true
    
  - name: "Check migrations"
    command: "mix ecto.migrations"
    required: true
    
  - name: "Build release"
    command: "mix release"
    required: true
    
  - name: "Security scan"
    command: "mix sobelow"
    required: false

deployment:
  - name: "Update ConfigMaps"
    command: "kubectl apply -f k8s/configmap.yml"
    
  - name: "Run migrations"
    command: "kubectl exec -it deploy/jido-system -- mix ecto.migrate"
    
  - name: "Deploy new version"
    command: "kubectl set image deployment/jido-system jido-system=jido:{{version}}"
    
  - name: "Wait for rollout"
    command: "kubectl rollout status deployment/jido-system"

post_deployment:
  - name: "Run smoke tests"
    command: "mix test.smoke"
    
  - name: "Check metrics"
    command: "scripts/check_deployment_metrics.sh"
    
  - name: "Verify SLOs"
    command: "scripts/verify_slos.sh"
```

## Incident Management

### 1. Incident Response Process

```elixir
defmodule JidoSystem.IncidentResponse do
  @moduledoc """
  Standardized incident response process.
  """
  
  defstruct [
    :id,
    :severity,
    :title,
    :description,
    :impact,
    :timeline,
    :responders,
    :status,
    :resolution,
    :postmortem_url
  ]
  
  def create_incident(severity, title, description) do
    incident = %__MODULE__{
      id: generate_incident_id(),
      severity: severity,
      title: title,
      description: description,
      timeline: [%{timestamp: DateTime.utc_now(), event: "Incident created"}],
      responders: [],
      status: :investigating
    }
    
    # Alert on-call
    alert_on_call(incident)
    
    # Create incident channel
    create_incident_channel(incident)
    
    # Start incident bot
    start_incident_bot(incident)
    
    incident
  end
  
  def update_incident(incident_id, updates) do
    incident = get_incident(incident_id)
    
    updated = struct(incident, updates)
    |> add_timeline_event("Updated: #{inspect(updates)}")
    
    broadcast_update(updated)
    
    updated
  end
end
```

### 2. On-Call Playbook

```markdown
# On-Call Playbook

## On-Call Responsibilities

1. **Primary On-Call**
   - First responder to alerts
   - Triage and initial investigation
   - Escalate if needed
   - Update status page

2. **Secondary On-Call**
   - Backup for primary
   - Major incident support
   - Cross-team coordination

## Alert Response SLA

| Severity | Response Time | Resolution Time |
|----------|--------------|-----------------|
| Critical | 5 minutes    | 1 hour         |
| High     | 15 minutes   | 4 hours        |
| Medium   | 1 hour       | 1 day          |
| Low      | 4 hours      | 1 week         |

## First Response Steps

1. **Acknowledge alert**
   ```bash
   pd-cli incident ack <incident-id>
   ```

2. **Join incident channel**
   - Slack: #incident-<id>
   - Zoom: [Incident Bridge](https://zoom/incident-bridge)

3. **Assess impact**
   - Check status dashboard
   - Review error budget
   - Determine customer impact

4. **Communicate status**
   - Update status page
   - Notify stakeholders
   - Post in #incidents channel

5. **Begin investigation**
   - Follow relevant runbook
   - Check recent changes
   - Review system metrics
```

## Capacity Planning

### 1. Resource Forecasting

```elixir
defmodule JidoSystem.CapacityPlanning do
  @moduledoc """
  Predictive capacity planning based on historical data.
  """
  
  def forecast_resources(horizon_days) do
    historical_data = fetch_historical_metrics(days: 90)
    
    forecasts = %{
      cpu: forecast_metric(historical_data.cpu_usage, horizon_days),
      memory: forecast_metric(historical_data.memory_usage, horizon_days),
      storage: forecast_metric(historical_data.storage_usage, horizon_days),
      agents: forecast_agent_count(historical_data.agent_count, horizon_days)
    }
    
    recommendations = generate_recommendations(forecasts)
    
    %{
      forecasts: forecasts,
      recommendations: recommendations,
      confidence: calculate_confidence(historical_data)
    }
  end
  
  defp generate_recommendations(forecasts) do
    recommendations = []
    
    if forecasts.cpu.max > 0.8 do
      recommendations ++ ["Add 2 more nodes within #{forecasts.cpu.days_until_threshold} days"]
    end
    
    if forecasts.memory.max > 0.9 do
      recommendations ++ ["Increase memory limits by 50%"]
    end
    
    if forecasts.agents.growth_rate > 0.1 do
      recommendations ++ ["Implement agent pooling for efficiency"]
    end
    
    recommendations
  end
end
```

### 2. Cost Optimization

```elixir
defmodule JidoSystem.CostOptimization do
  @moduledoc """
  Analyzes and optimizes operational costs.
  """
  
  def analyze_costs do
    %{
      compute: analyze_compute_costs(),
      storage: analyze_storage_costs(),
      network: analyze_network_costs(),
      external_services: analyze_external_service_costs()
    }
  end
  
  def optimization_recommendations do
    [
      %{
        category: :compute,
        recommendation: "Use spot instances for non-critical agents",
        potential_savings: "$2,400/month",
        implementation_effort: :medium
      },
      %{
        category: :storage,
        recommendation: "Archive logs older than 30 days",
        potential_savings: "$800/month",
        implementation_effort: :low
      },
      %{
        category: :network,
        recommendation: "Enable request compression",
        potential_savings: "$400/month",
        implementation_effort: :low
      }
    ]
  end
end
```

## Security Operations

### 1. Security Monitoring

```elixir
defmodule JidoSystem.SecurityOps do
  @moduledoc """
  Security monitoring and incident response.
  """
  
  def security_alerts do
    [
      %{
        name: "unauthorized_access_attempt",
        query: "sum(rate(auth_failures_total[5m])) > 10",
        severity: :high
      },
      %{
        name: "privilege_escalation",
        query: "jido_capability_granted{capability='admin'} == 1",
        severity: :critical
      },
      %{
        name: "unusual_data_access",
        query: "rate(data_access_bytes[5m]) > 1000000000", # 1GB/5min
        severity: :medium
      }
    ]
  end
  
  def audit_log(event, metadata) do
    entry = %{
      timestamp: DateTime.utc_now(),
      event: event,
      user: get_current_user(),
      ip_address: get_client_ip(),
      metadata: metadata,
      correlation_id: get_correlation_id()
    }
    
    # Write to immutable audit log
    AuditLog.write(entry)
    
    # Check for security patterns
    check_security_patterns(entry)
  end
end
```

### 2. Compliance Automation

```elixir
defmodule JidoSystem.Compliance do
  @moduledoc """
  Automated compliance checking and reporting.
  """
  
  def run_compliance_checks do
    checks = [
      check_data_encryption(),
      check_access_controls(),
      check_audit_logging(),
      check_backup_procedures(),
      check_incident_response()
    ]
    
    report = %{
      timestamp: DateTime.utc_now(),
      checks: checks,
      overall_status: calculate_overall_status(checks),
      next_audit: calculate_next_audit_date()
    }
    
    store_compliance_report(report)
    notify_compliance_team(report)
    
    report
  end
end
```

## Disaster Recovery

### 1. Backup Strategy

```yaml
# backup/strategy.yml
backups:
  database:
    schedule: "0 */6 * * *"  # Every 6 hours
    retention: 30  # days
    type: incremental
    destination: s3://jido-backups/database/
    
  event_store:
    schedule: "0 0 * * *"  # Daily
    retention: 90  # days
    type: full
    destination: s3://jido-backups/events/
    
  configuration:
    schedule: "0 * * * *"  # Hourly
    retention: 7  # days
    type: full
    destination: s3://jido-backups/config/

recovery:
  rto: 4  # hours
  rpo: 1  # hour
  
test_schedule:
  frequency: monthly
  next_test: 2024-02-15
```

### 2. Recovery Procedures

```elixir
defmodule JidoSystem.DisasterRecovery do
  @moduledoc """
  Automated disaster recovery procedures.
  """
  
  def initiate_recovery(scenario) do
    case scenario do
      :regional_failure ->
        failover_to_secondary_region()
        
      :data_corruption ->
        restore_from_backup()
        
      :complete_failure ->
        full_system_recovery()
    end
  end
  
  defp failover_to_secondary_region do
    with :ok <- update_dns_records(),
         :ok <- activate_standby_cluster(),
         :ok <- verify_data_replication(),
         :ok <- run_smoke_tests() do
      notify_team("Failover completed successfully")
      {:ok, :failover_complete}
    end
  end
end
```

## Operational Excellence Metrics

### 1. Key Performance Indicators

```elixir
defmodule JidoSystem.OperationalKPIs do
  def calculate_kpis do
    %{
      availability: calculate_availability(),
      mttr: calculate_mttr(),
      deployment_frequency: calculate_deployment_frequency(),
      lead_time: calculate_lead_time(),
      error_budget: calculate_error_budget(),
      toil_percentage: calculate_toil_percentage()
    }
  end
  
  defp calculate_availability do
    uptime_seconds = get_uptime_seconds(last: :month)
    total_seconds = 30 * 24 * 60 * 60
    
    (uptime_seconds / total_seconds) * 100
  end
  
  defp calculate_mttr do
    incidents = get_incidents(last: :quarter)
    
    total_duration = Enum.reduce(incidents, 0, fn incident, acc ->
      acc + (incident.resolved_at - incident.created_at)
    end)
    
    total_duration / length(incidents)
  end
end
```

### 2. Continuous Improvement

```elixir
defmodule JidoSystem.ContinuousImprovement do
  @moduledoc """
  Tracks and drives operational improvements.
  """
  
  def improvement_initiatives do
    [
      %{
        title: "Reduce MTTR by 50%",
        current_value: "4 hours",
        target_value: "2 hours",
        actions: [
          "Implement automated rollback",
          "Improve runbook coverage",
          "Add predictive alerting"
        ],
        deadline: ~D[2024-06-30]
      },
      %{
        title: "Achieve 99.99% availability",
        current_value: "99.9%",
        target_value: "99.99%",
        actions: [
          "Implement multi-region failover",
          "Add chaos engineering tests",
          "Improve circuit breakers"
        ],
        deadline: ~D[2024-12-31]
      }
    ]
  end
end
```

## Conclusion

Operational excellence is not a destination but a journey. This guide provides the foundation for operating JidoSystem with excellence, focusing on:

1. **Observability**: See everything happening in the system
2. **Automation**: Reduce toil and human error
3. **Resilience**: Fail gracefully and recover quickly
4. **Continuous Improvement**: Always be getting better

The key to success is treating operations as a first-class concern, investing in tooling and processes that make the system easier to operate, and fostering a culture of operational excellence across the entire team.