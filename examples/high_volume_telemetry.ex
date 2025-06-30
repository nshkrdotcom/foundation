defmodule Examples.HighVolumeTelemetry do
  @moduledoc """
  Example demonstrating telemetry sampling for high-volume scenarios.
  
  This example shows how to use Foundation's telemetry sampling to maintain
  observability in high-throughput systems without overwhelming monitoring
  infrastructure.
  """
  
  use Foundation.Telemetry.SampledEvents, prefix: [:examples, :high_volume]
  
  require Logger
  
  @doc """
  Simulates a high-volume API endpoint with sampled telemetry.
  """
  def simulate_api_endpoint do
    # Configure sampling for different event types
    configure_sampling()
    
    # Start the sampler
    {:ok, _} = Foundation.Telemetry.Sampler.start_link()
    
    # Attach monitoring
    attach_monitoring()
    
    Logger.info("Starting high-volume simulation...")
    
    # Simulate concurrent requests
    tasks = for i <- 1..100 do
      Task.async(fn ->
        simulate_user_session(i)
      end)
    end
    
    # Wait for completion
    Enum.each(tasks, &Task.await(&1, :infinity))
    
    # Show statistics
    show_statistics()
    
    # Cleanup
    :telemetry.detach("high-volume-monitor")
  end
  
  @doc """
  Demonstrates different sampling strategies.
  """
  def sampling_strategy_comparison do
    strategies = [
      {:always, strategy: :always},
      {:random_10_percent, strategy: :random, rate: 0.1},
      {:random_1_percent, strategy: :random, rate: 0.01},
      {:rate_limited_1000, strategy: :rate_limited, max_per_second: 1000},
      {:reservoir_100, strategy: :reservoir, reservoir_size: 100}
    ]
    
    {:ok, _} = Foundation.Telemetry.Sampler.start_link()
    
    for {name, config} <- strategies do
      Logger.info("\nTesting strategy: #{name}")
      
      # Configure the strategy
      event = [:test, name]
      Foundation.Telemetry.Sampler.configure_event(event, config)
      
      # Generate 10,000 events
      start_time = System.monotonic_time(:millisecond)
      
      for _ <- 1..10_000 do
        Foundation.Telemetry.Sampler.should_sample?(event)
      end
      
      duration = System.monotonic_time(:millisecond) - start_time
      
      # Get stats
      stats = Foundation.Telemetry.Sampler.get_stats()
      event_stats = stats.event_stats[event]
      
      Logger.info("""
      Results for #{name}:
        Total events: #{event_stats.total}
        Sampled: #{event_stats.sampled}
        Sampling rate: #{event_stats.sampling_rate_percent}%
        Time taken: #{duration}ms
        Events/sec: #{round(10_000 / (duration / 1000))}
      """)
      
      # Reset for next test
      Foundation.Telemetry.Sampler.reset_stats()
    end
  end
  
  # Private functions
  
  defp configure_sampling do
    # High-frequency events get lower sampling rates
    Foundation.Telemetry.Sampler.configure_event(
      [:examples, :high_volume, :request, :start],
      strategy: :random,
      rate: 0.01  # 1% sampling
    )
    
    Foundation.Telemetry.Sampler.configure_event(
      [:examples, :high_volume, :request, :stop],
      strategy: :random,
      rate: 0.01  # 1% sampling
    )
    
    # Database queries - slightly higher sampling
    Foundation.Telemetry.Sampler.configure_event(
      [:examples, :high_volume, :database, :query],
      strategy: :random,
      rate: 0.05  # 5% sampling
    )
    
    # Errors - always sample
    Foundation.Telemetry.Sampler.configure_event(
      [:examples, :high_volume, :error],
      strategy: :always
    )
    
    # Cache hits - rate limited to prevent flood
    Foundation.Telemetry.Sampler.configure_event(
      [:examples, :high_volume, :cache, :hit],
      strategy: :rate_limited,
      max_per_second: 100
    )
    
    # Slow queries - adaptive sampling
    Foundation.Telemetry.Sampler.configure_event(
      [:examples, :high_volume, :slow_query],
      strategy: :adaptive,
      rate: 0.5,
      adaptive_config: %{
        target_rate: 10,  # Max 10 per second
        adjustment_interval: 5000,
        increase_factor: 1.2,
        decrease_factor: 0.8
      }
    )
  end
  
  defp simulate_user_session(user_id) do
    # Simulate 100 requests per user
    for request_id <- 1..100 do
      simulate_request(user_id, request_id)
      
      # Random delay between requests
      Process.sleep(:rand.uniform(10))
    end
  end
  
  defp simulate_request(user_id, request_id) do
    metadata = %{user_id: user_id, request_id: request_id}
    
    # Use span for automatic timing
    span :request, metadata do
      # Simulate cache lookup
      cache_result = simulate_cache_lookup(user_id)
      
      # Simulate database query if cache miss
      if cache_result == :miss do
        simulate_database_query(user_id)
      end
      
      # Random chance of slow query
      if :rand.uniform() < 0.01 do
        simulate_slow_query(user_id)
      end
      
      # Random chance of error
      if :rand.uniform() < 0.001 do
        emit_event(:error, %{}, Map.put(metadata, :error_type, :processing_error))
        {:error, :simulated_error}
      else
        {:ok, :success}
      end
    end
  end
  
  defp simulate_cache_lookup(user_id) do
    result = if :rand.uniform() < 0.8, do: :hit, else: :miss
    
    emit_event([:cache, result], 
      %{latency_us: :rand.uniform(100)},
      %{key: "user:#{user_id}"}
    )
    
    result
  end
  
  defp simulate_database_query(user_id) do
    query_time = 10 + :rand.uniform(50)
    Process.sleep(query_time)
    
    emit_event([:database, :query],
      %{duration_ms: query_time},
      %{query: "SELECT * FROM users WHERE id = #{user_id}"}
    )
  end
  
  defp simulate_slow_query(user_id) do
    query_time = 100 + :rand.uniform(400)
    Process.sleep(query_time)
    
    emit_event(:slow_query,
      %{duration_ms: query_time},
      %{query: "Complex query for user #{user_id}"}
    )
  end
  
  defp attach_monitoring do
    # Count actual emitted events
    :telemetry.attach_many(
      "high-volume-monitor",
      [
        [:examples, :high_volume, :request, :start],
        [:examples, :high_volume, :request, :stop],
        [:examples, :high_volume, :database, :query],
        [:examples, :high_volume, :cache, :hit],
        [:examples, :high_volume, :cache, :miss],
        [:examples, :high_volume, :error],
        [:examples, :high_volume, :slow_query]
      ],
      &handle_telemetry_event/4,
      %{counter: :counters.new(10, [:atomics])}
    )
  end
  
  defp handle_telemetry_event(event, _measurements, metadata, %{counter: counter}) do
    # Count events by type
    index = case event do
      [:examples, :high_volume, :request, :start] -> 1
      [:examples, :high_volume, :request, :stop] -> 2
      [:examples, :high_volume, :database, :query] -> 3
      [:examples, :high_volume, :cache, :hit] -> 4
      [:examples, :high_volume, :cache, :miss] -> 5
      [:examples, :high_volume, :error] -> 6
      [:examples, :high_volume, :slow_query] -> 7
      _ -> 10
    end
    
    :counters.add(counter, index, 1)
    
    # Log errors and slow queries
    case event do
      [:examples, :high_volume, :error] ->
        Logger.warning("Error detected: #{inspect(metadata)}")
        
      [:examples, :high_volume, :slow_query] ->
        Logger.warning("Slow query: #{metadata.query} took #{metadata.duration_ms}ms")
        
      _ ->
        :ok
    end
  end
  
  defp show_statistics do
    stats = Foundation.Telemetry.Sampler.get_stats()
    
    Logger.info("\n=== Sampling Statistics ===")
    
    for {event, event_stats} <- stats.event_stats do
      Logger.info("""
      Event: #{inspect(event)}
        Strategy: #{event_stats.strategy}
        Total generated: #{event_stats.total}
        Actually sampled: #{event_stats.sampled}
        Sampling rate: #{event_stats.sampling_rate_percent}%
      """)
    end
    
    Logger.info("\nUptime: #{stats.uptime_seconds} seconds")
  end
end