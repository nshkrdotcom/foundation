# Foundation Distributed Tracing Guide

This guide explains how to use Foundation's distributed tracing capabilities to track operations across services and processes.

## Overview

Foundation provides span-based distributed tracing that integrates with OpenTelemetry and other tracing systems. This allows you to:

- Track operations across multiple services
- Understand request flow and latencies
- Debug complex distributed systems
- Monitor performance bottlenecks

## Basic Usage

### Simple Spans

```elixir
import Foundation.Telemetry.Span

# Basic span
with_span :database_query do
  Database.query("SELECT * FROM users")
end

# Span with metadata
with_span :api_request, %{endpoint: "/users", method: "GET"} do
  HTTP.get("/users")
end
```

### Nested Spans

```elixir
with_span :handle_request, %{request_id: request_id} do
  # Validate request
  with_span :validate_request do
    validate(params)
  end
  
  # Process business logic
  with_span :process_business_logic do
    result = process(params)
    
    # Add attributes to current span
    add_attributes(%{
      items_processed: length(result),
      processing_status: "success"
    })
    
    result
  end
  
  # Send response
  with_span :send_response do
    send_response(conn, result)
  end
end
```

### Recording Events

```elixir
with_span :long_operation do
  # Record checkpoints
  record_event(:started_processing)
  
  data = fetch_data()
  record_event(:data_fetched, %{record_count: length(data)})
  
  result = process_data(data)
  record_event(:processing_complete, %{duration_ms: 1234})
  
  result
end
```

## Cross-Process Tracing

### Propagating Context

```elixir
# Parent process
with_span :parent_operation do
  context = propagate_context()
  
  # Send to another process
  GenServer.call(worker, {:process, data, context})
  
  # Or use with Task
  Task.async(fn ->
    with_propagated_context(context, fn ->
      with_span :async_operation do
        do_work()
      end
    end)
  end)
end

# Worker process
def handle_call({:process, data, context}, _from, state) do
  with_propagated_context(context, fn ->
    with_span :worker_processing do
      result = process_data(data)
      {:reply, result, state}
    end
  end)
end
```

### HTTP Request Tracing

```elixir
defmodule MyApp.HTTPClient do
  import Foundation.Telemetry.Span
  
  def request(method, url, body, headers \\ []) do
    with_span :http_request, %{method: method, url: url} do
      # Add trace headers
      trace_headers = build_trace_headers()
      headers = headers ++ trace_headers
      
      # Make request
      case HTTP.request(method, url, body, headers) do
        {:ok, %{status: status} = response} ->
          add_attributes(%{
            status_code: status,
            response_size: byte_size(response.body)
          })
          {:ok, response}
          
        {:error, reason} = error ->
          add_attributes(%{error: reason})
          error
      end
    end
  end
  
  defp build_trace_headers do
    case current_trace_id() do
      nil -> []
      trace_id -> [{"x-trace-id", trace_id}]
    end
  end
end
```

## Integration with Cache

```elixir
defmodule MyApp.Cache do
  import Foundation.Telemetry.Span
  
  def get(key) do
    with_span :cache_get, %{cache_key: key} do
      case Foundation.Infrastructure.Cache.get(key) do
        nil ->
          add_attributes(%{cache_hit: false})
          
          # Fetch from source
          with_span :fetch_from_source do
            value = fetch_from_database(key)
            
            # Store in cache
            with_span :cache_put do
              Foundation.Infrastructure.Cache.put(key, value)
            end
            
            value
          end
          
        value ->
          add_attributes(%{cache_hit: true})
          value
      end
    end
  end
end
```

## OpenTelemetry Integration

### Setup

1. Add dependencies:

```elixir
defp deps do
  [
    {:opentelemetry, "~> 1.3"},
    {:opentelemetry_exporter, "~> 1.3"},
    {:opentelemetry_api, "~> 1.2"}
  ]
end
```

2. Configure OpenTelemetry:

```elixir
# config/config.exs
config :opentelemetry, :resource, [
  service: [
    name: "my-service",
    version: "1.0.0"
  ]
]

config :opentelemetry,
  span_processor: :batch,
  traces_exporter: :otlp

config :opentelemetry_exporter,
  otlp_protocol: :grpc,
  otlp_endpoint: "http://localhost:4317"

# Enable Foundation bridge
config :foundation, :opentelemetry,
  enabled: true,
  service_name: "my-service"
```

3. Start the bridge:

```elixir
children = [
  # ... other children ...
  Foundation.Telemetry.OpenTelemetryBridge
]
```

## Advanced Patterns

### Circuit Breaker with Tracing

```elixir
defmodule MyApp.ExternalService do
  import Foundation.Telemetry.Span
  
  def call_api(params) do
    with_span :external_api_call, %{service: "payment_api"} do
      Foundation.Services.CircuitBreaker.call(
        :payment_api,
        fn ->
          with_span :http_request do
            HTTP.post("/charge", params)
          end
        end,
        timeout: 5000
      )
    end
  end
end
```

### Retry with Tracing

```elixir
defmodule MyApp.DataProcessor do
  import Foundation.Telemetry.Span
  
  def process_with_retry(data) do
    with_span :data_processing, %{retry_enabled: true} do
      Foundation.Services.RetryService.retry(
        fn attempt ->
          record_event(:retry_attempt, %{attempt: attempt})
          
          with_span :process_attempt, %{attempt: attempt} do
            process_data(data)
          end
        end,
        max_attempts: 3,
        backoff: :exponential
      )
    end
  end
end
```

### Batch Processing

```elixir
defmodule MyApp.BatchProcessor do
  import Foundation.Telemetry.Span
  
  def process_batch(items) do
    with_span :batch_processing, %{batch_size: length(items)} do
      items
      |> Enum.with_index()
      |> Enum.map(fn {item, index} ->
        with_span :process_item, %{item_index: index} do
          try do
            result = process_item(item)
            add_attributes(%{status: "success"})
            {:ok, result}
          rescue
            e ->
              add_attributes(%{status: "error", error: inspect(e)})
              {:error, e}
          end
        end
      end)
    end
  end
end
```

## Monitoring and Visualization

### Jaeger

1. Run Jaeger:
```bash
docker run -d --name jaeger \
  -p 16686:16686 \
  -p 4317:4317 \
  jaegertracing/all-in-one:latest
```

2. View traces at http://localhost:16686

### Grafana Tempo

1. Add to docker-compose.yml:
```yaml
tempo:
  image: grafana/tempo:latest
  command: [ "-config.file=/etc/tempo.yaml" ]
  volumes:
    - ./tempo.yaml:/etc/tempo.yaml
    - tempo_data:/tmp/tempo
  ports:
    - "3200:3200"   # tempo
    - "4317:4317"   # otlp grpc
```

2. Configure Grafana data source to use Tempo

## Best Practices

### 1. Span Naming

Use descriptive, consistent names:
- ✅ `database.query`
- ✅ `cache.get`
- ✅ `http.request`
- ❌ `operation1`
- ❌ `do_stuff`

### 2. Attribute Guidelines

Include relevant context:
```elixir
with_span :api_request, %{
  # Good attributes
  endpoint: "/users",
  method: "GET",
  user_type: "premium",
  
  # Avoid high cardinality
  # user_id: user_id,  # Don't include unique IDs
}
```

### 3. Error Handling

Always let spans capture errors:
```elixir
# Good - span captures error
with_span :risky_operation do
  risky_function()  # May raise
end

# Bad - span doesn't see error
try do
  with_span :risky_operation do
    risky_function()
  end
rescue
  e -> handle_error(e)
end
```

### 4. Sampling

For high-volume operations:
```elixir
def should_trace? do
  # Sample 10% of requests
  :rand.uniform() < 0.1
end

def handle_request(params) do
  if should_trace?() do
    with_span :handle_request, %{sampled: true} do
      do_work(params)
    end
  else
    do_work(params)
  end
end
```

## Troubleshooting

### Missing Spans

1. Check if tracing is enabled:
```elixir
Application.get_env(:foundation, :opentelemetry)[:enabled]
```

2. Verify exporter configuration
3. Check for errors in logs

### Performance Impact

1. Monitor overhead with:
```elixir
:telemetry.attach("trace-overhead", [:foundation, :span, :stop], fn _, %{duration: d}, _, _ ->
  Logger.debug("Span overhead: #{d}μs")
end, nil)
```

2. Adjust sampling rate if needed
3. Use async export for better performance

### Context Propagation Issues

1. Ensure context is properly passed:
```elixir
# Debug context
context = propagate_context()
IO.inspect(context, label: "Trace context")
```

2. Check for process boundaries
3. Verify trace headers in HTTP requests