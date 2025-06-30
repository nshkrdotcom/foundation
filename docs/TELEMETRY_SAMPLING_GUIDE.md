# Foundation Telemetry Sampling Guide

This guide explains how to use telemetry sampling to maintain observability in high-throughput systems without overwhelming your monitoring infrastructure.

## Overview

Telemetry sampling allows you to:
- Reduce telemetry overhead in high-volume scenarios
- Maintain statistical accuracy while processing fewer events
- Dynamically adjust sampling based on system load
- Apply different strategies for different event types

## When to Use Sampling

Consider sampling when:
- Your system processes thousands of events per second
- Telemetry overhead becomes significant (>1% of processing time)
- Your monitoring infrastructure struggles with data volume
- You need to control monitoring costs

## Sampling Strategies

### 1. Random Sampling

Randomly samples a percentage of events.

```elixir
Foundation.Telemetry.Sampler.configure_event(
  [:my_app, :high_volume, :event],
  strategy: :random,
  rate: 0.1  # Sample 10% of events
)
```

**Use when:** You want a representative sample of all events
**Pros:** Simple, unbiased, predictable overhead reduction
**Cons:** May miss rare events

### 2. Rate Limiting

Limits events to a maximum per second.

```elixir
Foundation.Telemetry.Sampler.configure_event(
  [:my_app, :api, :request],
  strategy: :rate_limited,
  max_per_second: 1000
)
```

**Use when:** You need to cap absolute telemetry volume
**Pros:** Predictable maximum load on monitoring systems
**Cons:** May miss bursts of activity

### 3. Adaptive Sampling

Dynamically adjusts sampling rate based on volume.

```elixir
Foundation.Telemetry.Sampler.configure_event(
  [:my_app, :cache, :operation],
  strategy: :adaptive,
  rate: 0.5,  # Initial rate
  adaptive_config: %{
    target_rate: 100,  # Target events per second
    adjustment_interval: 5000,
    increase_factor: 1.1,
    decrease_factor: 0.9
  }
)
```

**Use when:** Load varies significantly over time
**Pros:** Maintains consistent telemetry volume
**Cons:** More complex, sampling rate changes

### 4. Reservoir Sampling

Maintains a fixed-size sample over time.

```elixir
Foundation.Telemetry.Sampler.configure_event(
  [:my_app, :user, :action],
  strategy: :reservoir,
  reservoir_size: 1000  # Keep last 1000 samples
)
```

**Use when:** You need a fixed sample size regardless of volume
**Pros:** Guaranteed sample size, good for statistical analysis
**Cons:** Older events get displaced

### 5. Always/Never

Simple on/off strategies.

```elixir
# Always sample errors
Foundation.Telemetry.Sampler.configure_event(
  [:my_app, :error],
  strategy: :always
)

# Never sample debug events in production
Foundation.Telemetry.Sampler.configure_event(
  [:my_app, :debug],
  strategy: :never
)
```

## Configuration

### Application Config

Configure default sampling in your config files:

```elixir
# config/config.exs
config :foundation, :telemetry_sampling,
  enabled: true,
  default_strategy: :random,
  default_rate: 1.0,  # 100% by default
  
  event_configs: [
    # High-volume events
    {[:my_app, :cache, :get], strategy: :random, rate: 0.01},
    {[:my_app, :http, :request], strategy: :random, rate: 0.05},
    
    # Rate limit background jobs
    {[:my_app, :job, :processed], strategy: :rate_limited, max_per_second: 100},
    
    # Always sample errors and warnings
    {[:my_app, :error], strategy: :always},
    {[:my_app, :warning], strategy: :always},
    
    # Adaptive sampling for variable load
    {[:my_app, :api, :graphql], strategy: :adaptive, target_rate: 500}
  ]

# config/prod.exs
config :foundation, :telemetry_sampling,
  enabled: true,
  default_rate: 0.1  # More aggressive sampling in production
```

### Runtime Configuration

Adjust sampling dynamically:

```elixir
# Increase sampling during debugging
Foundation.Telemetry.Sampler.configure_event(
  [:my_app, :suspicious, :activity],
  strategy: :random,
  rate: 1.0  # Temporarily sample everything
)

# Check current configuration
stats = Foundation.Telemetry.Sampler.get_stats()
IO.inspect(stats.event_stats)
```

## Using Sampled Events

### Direct Usage

```elixir
# Only emits if sampled
Foundation.Telemetry.Sampler.execute(
  [:my_app, :event],
  %{duration: 100},
  %{user_id: 123}
)

# Check if event should be sampled
if Foundation.Telemetry.Sampler.should_sample?([:my_app, :event]) do
  # Do expensive telemetry processing
  :telemetry.execute([:my_app, :event], measurements, metadata)
end
```

### Using SampledEvents Module

```elixir
defmodule MyApp.Service do
  use Foundation.Telemetry.SampledEvents, prefix: [:my_app, :service]
  
  def process_request(request) do
    # Automatic sampling
    span :process_request, %{request_id: request.id} do
      # Your code here
      do_processing(request)
    end
  end
  
  def handle_event(event) do
    # Conditional emission
    emit_if event.important?, :important_event,
      %{timestamp: System.system_time()},
      %{event_type: event.type}
      
    # Deduplication
    emit_once_per :duplicate_warning, :timer.minutes(5),
      %{count: event.duplicate_count},
      %{original_id: event.id}
  end
end
```

## Best Practices

### 1. Sample by Importance

```elixir
# High sampling for errors and anomalies
config :foundation, :telemetry_sampling,
  event_configs: [
    {[:my_app, :error], strategy: :always},
    {[:my_app, :warning], strategy: :random, rate: 0.5},
    {[:my_app, :info], strategy: :random, rate: 0.1},
    {[:my_app, :debug], strategy: :random, rate: 0.01}
  ]
```

### 2. Consider Event Correlation

When sampling related events, use consistent sampling decisions:

```elixir
defmodule MyApp.RequestHandler do
  def handle_request(request) do
    # Decide once for the entire request
    should_sample = Foundation.Telemetry.Sampler.should_sample?(
      [:my_app, :request], 
      %{request_id: request.id}
    )
    
    if should_sample do
      emit_start_event(request)
      result = process_request(request)
      emit_stop_event(request, result)
    else
      process_request(request)
    end
  end
end
```

### 3. Monitor Sampling Effectiveness

```elixir
defmodule MyApp.Monitoring do
  def check_sampling_health do
    stats = Foundation.Telemetry.Sampler.get_stats()
    
    for {event, event_stats} <- stats.event_stats do
      if event_stats.total > 10_000 and event_stats.sampling_rate_percent > 50 do
        Logger.warning("""
        High-volume event #{inspect(event)} has high sampling rate.
        Consider reducing from #{event_stats.sampling_rate_percent}%
        """)
      end
    end
  end
end
```

### 4. Test with Sampling

Ensure your tests work with sampling:

```elixir
defmodule MyApp.Test do
  use ExUnit.Case
  
  setup do
    # Disable sampling in tests for predictability
    original = Application.get_env(:foundation, :telemetry_sampling)
    Application.put_env(:foundation, :telemetry_sampling, enabled: false)
    
    on_exit(fn ->
      Application.put_env(:foundation, :telemetry_sampling, original)
    end)
  end
end
```

## Performance Considerations

### Overhead Measurement

```elixir
defmodule MyApp.TelemetryBenchmark do
  def measure_sampling_overhead do
    # Without sampling
    no_sampling_time = :timer.tc(fn ->
      for _ <- 1..100_000 do
        :telemetry.execute([:test, :event], %{value: 1}, %{})
      end
    end) |> elem(0)
    
    # With sampling at 10%
    {:ok, _} = Foundation.Telemetry.Sampler.start_link()
    Foundation.Telemetry.Sampler.configure_event(
      [:test, :event],
      strategy: :random,
      rate: 0.1
    )
    
    sampling_time = :timer.tc(fn ->
      for _ <- 1..100_000 do
        Foundation.Telemetry.Sampler.execute(
          [:test, :event], 
          %{value: 1}, 
          %{}
        )
      end
    end) |> elem(0)
    
    IO.puts("No sampling: #{no_sampling_time}μs")
    IO.puts("With 10% sampling: #{sampling_time}μs")
    IO.puts("Overhead: #{(sampling_time - no_sampling_time * 0.1) / 1000}μs per event")
  end
end
```

### Memory Usage

The sampler maintains counters and rate limiters in memory:
- ~100 bytes per unique event type
- Rate limiters reset every second
- Reservoir sampling stores N events in memory

## Troubleshooting

### Events Not Being Sampled

1. Check if sampling is enabled:
```elixir
stats = Foundation.Telemetry.Sampler.get_stats()
IO.inspect(stats.enabled)
```

2. Verify event configuration:
```elixir
# Check specific event
Application.get_env(:foundation, :telemetry_sampling)[:event_configs]
|> Enum.find(fn {event, _} -> event == [:my_app, :event] end)
```

3. Check sampling statistics:
```elixir
stats = Foundation.Telemetry.Sampler.get_stats()
IO.inspect(stats.event_stats[[:my_app, :event]])
```

### High Memory Usage

If the sampler uses too much memory:

1. Reduce reservoir sizes
2. Limit the number of unique events
3. Use more aggressive sampling rates
4. Reset statistics periodically:

```elixir
# Reset every hour
Process.send_after(self(), :reset_sampler, :timer.hours(1))

def handle_info(:reset_sampler, state) do
  Foundation.Telemetry.Sampler.reset_stats()
  Process.send_after(self(), :reset_sampler, :timer.hours(1))
  {:noreply, state}
end
```

## Integration with Monitoring Systems

### Adjusting Metrics for Sampling

When using sampling, adjust your metrics:

```elixir
defmodule MyApp.Metrics do
  def request_rate(sampled_count, sampling_rate) do
    # Extrapolate actual rate
    sampled_count / sampling_rate
  end
  
  def percentile_latency(sampled_latencies) do
    # Percentiles remain accurate with random sampling
    calculate_percentile(sampled_latencies, 0.95)
  end
end
```

### Grafana Dashboard Adjustments

```promql
# Adjust for 10% sampling rate
rate(http_requests_total[5m]) * 10

# Percentiles remain accurate
histogram_quantile(0.95, 
  rate(http_request_duration_seconds_bucket[5m])
)
```

## Example: Production Configuration

```elixir
# config/prod.exs
config :foundation, :telemetry_sampling,
  enabled: true,
  default_strategy: :random,
  default_rate: 0.1,
  
  event_configs: [
    # Critical business metrics - higher sampling
    {[:api, :payment, :processed], strategy: :random, rate: 1.0},
    {[:api, :user, :signup], strategy: :random, rate: 1.0},
    
    # High-volume, low-value events
    {[:cache, :hit], strategy: :random, rate: 0.001},
    {[:cache, :miss], strategy: :random, rate: 0.01},
    
    # Rate limit background noise
    {[:health, :check], strategy: :rate_limited, max_per_second: 10},
    {[:metrics, :collected], strategy: :rate_limited, max_per_second: 100},
    
    # Errors and warnings - always capture
    {[:error], strategy: :always},
    {[:warning], strategy: :random, rate: 0.5},
    
    # Adaptive for variable load
    {[:api, :request], strategy: :adaptive, 
      adaptive_config: %{target_rate: 1000}},
    
    # Debug events - mostly disabled
    {[:debug], strategy: :random, rate: 0.0001}
  ]
```

This configuration balances observability with performance, ensuring critical events are captured while preventing telemetry overload.