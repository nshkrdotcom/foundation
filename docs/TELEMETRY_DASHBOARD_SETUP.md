# Foundation Telemetry Dashboard Setup Guide

This guide explains how to set up monitoring dashboards for Foundation telemetry using Prometheus and Grafana.

## Prerequisites

- Docker and Docker Compose (recommended)
- Or manually installed Prometheus and Grafana

## Quick Start with Docker Compose

1. Create a `docker-compose.yml` file:

```yaml
version: '3.8'

services:
  prometheus:
    image: prom/prometheus:latest
    container_name: foundation-prometheus
    volumes:
      - ./config/prometheus.yml:/etc/prometheus/prometheus.yml
      - ./config/alerts:/etc/prometheus/alerts
      - prometheus_data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.path=/prometheus'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
      - '--web.enable-lifecycle'
    ports:
      - "9090:9090"
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    container_name: foundation-grafana
    volumes:
      - grafana_data:/var/lib/grafana
      - ./config/grafana/provisioning:/etc/grafana/provisioning
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
      - GF_USERS_ALLOW_SIGN_UP=false
    ports:
      - "3000:3000"
    restart: unless-stopped
    depends_on:
      - prometheus

  alertmanager:
    image: prom/alertmanager:latest
    container_name: foundation-alertmanager
    volumes:
      - ./config/alertmanager.yml:/etc/alertmanager/alertmanager.yml
      - alertmanager_data:/alertmanager
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
      - '--storage.path=/alertmanager'
    ports:
      - "9093:9093"
    restart: unless-stopped

volumes:
  prometheus_data:
  grafana_data:
  alertmanager_data:
```

2. Start the monitoring stack:
```bash
docker-compose up -d
```

3. Access the services:
   - Prometheus: http://localhost:9090
   - Grafana: http://localhost:3000 (admin/admin)
   - Alertmanager: http://localhost:9093

## Elixir Application Setup

### 1. Add Dependencies

Add to your `mix.exs`:

```elixir
defp deps do
  [
    {:telemetry, "~> 1.2"},
    {:telemetry_metrics, "~> 0.6"},
    {:telemetry_metrics_prometheus, "~> 1.1"},
    {:telemetry_poller, "~> 1.0"}
  ]
end
```

### 2. Configure Telemetry Metrics

Add to your application supervision tree:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      # ... other children ...
      
      # Telemetry metrics reporter
      {TelemetryMetricsPrometheus,
       [
         metrics: Foundation.Telemetry.Metrics.metrics(),
         port: 9568,
         path: "/metrics",
         name: :foundation_metrics
       ]},
      
      # Telemetry poller for VM metrics
      {:telemetry_poller,
       measurements: [
         {Foundation.Telemetry, :dispatch_vm_metrics, []}
       ],
       period: 10_000,
       name: :foundation_poller}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### 3. Add VM Metrics Collection

Create a module to collect VM metrics:

```elixir
defmodule Foundation.Telemetry do
  def dispatch_vm_metrics do
    memory = :erlang.memory()
    
    :telemetry.execute(
      [:vm, :memory],
      %{
        total: memory[:total],
        processes: memory[:processes],
        system: memory[:system],
        atom: memory[:atom],
        binary: memory[:binary],
        ets: memory[:ets]
      },
      %{}
    )
    
    :telemetry.execute(
      [:vm, :system_info],
      %{
        process_count: :erlang.system_info(:process_count),
        port_count: :erlang.system_info(:port_count),
        ets_count: :erlang.system_info(:ets_count)
      },
      %{}
    )
  end
end
```

## Grafana Dashboard Import

1. Log into Grafana (http://localhost:3000)
2. Add Prometheus data source:
   - Go to Configuration → Data Sources
   - Add data source → Prometheus
   - URL: http://prometheus:9090
   - Save & Test

3. Import the Foundation dashboard:
   - Go to Create → Import
   - Upload `config/telemetry_dashboard.json`
   - Select the Prometheus data source
   - Import

## Customizing Metrics

### Adding Custom Metrics

```elixir
# In your application code
:telemetry.execute(
  [:my_app, :custom, :metric],
  %{value: 42, duration: 1000},
  %{tag: "important"}
)

# Add to Foundation.Telemetry.Metrics
Metrics.counter("my_app.custom.metric.total",
  event_name: [:my_app, :custom, :metric],
  tags: [:tag]
)
```

### Creating Custom Dashboards

Use Grafana's query builder with these common patterns:

```promql
# Rate of events
rate(foundation_cache_hit_total[5m])

# Histogram percentiles
histogram_quantile(0.95, rate(foundation_cache_duration_microseconds_bucket[5m]))

# Gauge values
foundation_resource_manager_active_tokens

# Aggregations
sum(rate(jido_system_task_completed_total[5m])) by (task_type)
```

## Alerting Setup

### Configure Alertmanager

Create `config/alertmanager.yml`:

```yaml
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 10s
  group_interval: 10s
  repeat_interval: 12h
  receiver: 'default'
  
receivers:
  - name: 'default'
    webhook_configs:
      - url: 'http://your-webhook-url'
        send_resolved: true
```

### Testing Alerts

1. Check active alerts in Prometheus: http://localhost:9090/alerts
2. View alert history in Alertmanager: http://localhost:9093
3. Test webhook delivery with a test receiver

## Performance Considerations

1. **Metric Cardinality**: Avoid high-cardinality labels (e.g., user IDs)
2. **Sampling**: For high-volume events, consider sampling:
   ```elixir
   if :rand.uniform() < 0.1 do  # 10% sampling
     :telemetry.execute([:high, :volume, :event], %{}, %{})
   end
   ```

3. **Metric Retention**: Configure Prometheus retention:
   ```yaml
   # In prometheus.yml
   global:
     external_labels:
       monitor: 'foundation'
   
   # Start with --storage.tsdb.retention.time=30d
   ```

## Troubleshooting

### No Metrics Appearing

1. Check if metrics endpoint is accessible:
   ```bash
   curl http://localhost:9568/metrics
   ```

2. Verify Prometheus is scraping:
   - Go to http://localhost:9090/targets
   - Check if your target is UP

3. Check application logs for telemetry errors

### Missing Metrics

1. Ensure events are being emitted:
   ```elixir
   :telemetry.attach("debug", [:foundation, :cache, :hit], fn event, measures, meta, _ ->
     IO.inspect({event, measures, meta})
   end, nil)
   ```

2. Verify metric definitions match event names

### High Memory Usage

1. Reduce metric cardinality
2. Increase Prometheus scrape interval
3. Implement metric aggregation in application

## Best Practices

1. **Use Consistent Naming**: Follow the pattern `app.component.action.unit`
2. **Add Descriptions**: Always include metric descriptions
3. **Choose Appropriate Types**:
   - Counter: For counts that only increase
   - Gauge: For values that can go up and down
   - Histogram: For measuring distributions (latencies, sizes)
   - Summary: For pre-calculated percentiles

4. **Label Guidelines**:
   - Keep label cardinality low
   - Use static labels for grouping
   - Avoid user-specific or request-specific labels

5. **Dashboard Organization**:
   - Group related metrics
   - Use consistent time ranges
   - Add helpful annotations
   - Include alert thresholds on graphs

## Additional Resources

- [Prometheus Best Practices](https://prometheus.io/docs/practices/)
- [Grafana Dashboard Best Practices](https://grafana.com/docs/grafana/latest/best-practices/dashboard-best-practices/)
- [Telemetry.Metrics Documentation](https://hexdocs.pm/telemetry_metrics/)
- [Foundation Telemetry Reference](/test/TELEMETRY_EVENT_REFERENCE.md)