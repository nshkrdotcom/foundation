defmodule Examples.CacheLoadTest do
  @moduledoc """
  Example load test for Foundation.Infrastructure.Cache.
  
  This demonstrates how to create a comprehensive load test that simulates
  realistic cache usage patterns with multiple scenarios.
  
  ## Running the test
  
      # Basic run with default settings
      Examples.CacheLoadTest.run()
      
      # Custom configuration
      Examples.CacheLoadTest.run(
        duration: :timer.minutes(5),
        concurrency: 100,
        ramp_up: :timer.seconds(30)
      )
      
      # Run with monitoring
      Examples.CacheLoadTest.run_with_monitoring()
  """
  
  use Foundation.Telemetry.LoadTest
  
  @user_id_range 1..10_000
  @product_id_range 1..1_000
  @session_ttl :timer.seconds(300)
  @product_ttl :timer.hours(1)
  
  @impl true
  def scenarios do
    [
      # User session lookups - most common operation
      %{
        name: :user_session_read,
        weight: 40,
        run: fn _ctx ->
          user_id = Enum.random(@user_id_range)
          key = "session:user:#{user_id}"
          
          case Foundation.Infrastructure.Cache.get(key) do
            nil -> {:ok, :miss}
            _session -> {:ok, :hit}
          end
        end
      },
      
      # User session writes
      %{
        name: :user_session_write,
        weight: 10,
        run: fn _ctx ->
          user_id = Enum.random(@user_id_range)
          key = "session:user:#{user_id}"
          
          session = %{
            user_id: user_id,
            created_at: DateTime.utc_now(),
            last_active: DateTime.utc_now(),
            ip_address: random_ip(),
            user_agent: random_user_agent()
          }
          
          Foundation.Infrastructure.Cache.put(key, session, ttl: @session_ttl)
          {:ok, :written}
        end
      },
      
      # Product catalog reads - cached from database
      %{
        name: :product_read,
        weight: 30,
        run: fn _ctx ->
          product_id = Enum.random(@product_id_range)
          key = "product:#{product_id}"
          
          case Foundation.Infrastructure.Cache.get(key) do
            nil ->
              # Simulate database fetch and cache
              product = fetch_product_from_db(product_id)
              Foundation.Infrastructure.Cache.put(key, product, ttl: @product_ttl)
              {:ok, :miss_and_cached}
              
            product ->
              {:ok, :hit}
          end
        end
      },
      
      # Shopping cart operations
      %{
        name: :cart_update,
        weight: 15,
        run: fn _ctx ->
          user_id = Enum.random(@user_id_range)
          key = "cart:user:#{user_id}"
          
          # Get current cart
          cart = Foundation.Infrastructure.Cache.get(key) || %{items: [], total: 0}
          
          # Add random item
          product_id = Enum.random(@product_id_range)
          updated_cart = add_to_cart(cart, product_id)
          
          # Save back
          Foundation.Infrastructure.Cache.put(key, updated_cart, ttl: :timer.hours(24))
          {:ok, :updated}
        end
      },
      
      # Cache invalidation
      %{
        name: :cache_invalidate,
        weight: 5,
        run: fn _ctx ->
          # Simulate various invalidation patterns
          case :rand.uniform(3) do
            1 ->
              # Single key invalidation
              product_id = Enum.random(@product_id_range)
              Foundation.Infrastructure.Cache.delete("product:#{product_id}")
              {:ok, :single_invalidation}
              
            2 ->
              # User session cleanup
              user_id = Enum.random(@user_id_range)
              Foundation.Infrastructure.Cache.delete("session:user:#{user_id}")
              Foundation.Infrastructure.Cache.delete("cart:user:#{user_id}")
              {:ok, :user_cleanup}
              
            3 ->
              # Pattern-based invalidation (if supported)
              # For now just delete a few related keys
              category_id = Enum.random(1..50)
              Enum.each(1..10, fn i ->
                Foundation.Infrastructure.Cache.delete("product:category:#{category_id}:#{i}")
              end)
              {:ok, :batch_invalidation}
          end
        end
      }
    ]
  end
  
  @impl true
  def setup(context) do
    # Pre-populate some data for more realistic testing
    Logger.info("Pre-populating cache with sample data...")
    
    # Add some products
    Enum.each(1..100, fn id ->
      product = %{
        id: id,
        name: "Product #{id}",
        price: :rand.uniform(10000) / 100,
        category_id: rem(id, 10) + 1
      }
      Foundation.Infrastructure.Cache.put("product:#{id}", product, ttl: @product_ttl)
    end)
    
    # Add some active sessions
    Enum.each(1..50, fn id ->
      session = %{
        user_id: id,
        created_at: DateTime.utc_now(),
        last_active: DateTime.utc_now()
      }
      Foundation.Infrastructure.Cache.put("session:user:#{id}", session, ttl: @session_ttl)
    end)
    
    {:ok, Map.put(context, :preloaded_data, true)}
  end
  
  @impl true
  def teardown(context) do
    Logger.info("Load test completed. Cleaning up...")
    # Could clean up test data here if needed
    :ok
  end
  
  # Public API
  
  @doc """
  Run the cache load test with default settings.
  """
  def run(opts \\ []) do
    default_opts = [
      duration: :timer.seconds(60),
      concurrency: 50,
      ramp_up: :timer.seconds(5),
      report_interval: :timer.seconds(10)
    ]
    
    Foundation.Telemetry.LoadTest.run(__MODULE__, Keyword.merge(default_opts, opts))
  end
  
  @doc """
  Run the load test with telemetry monitoring attached.
  """
  def run_with_monitoring(opts \\ []) do
    # Attach cache telemetry monitoring
    :telemetry.attach_many(
      "cache-load-test-monitor",
      [
        [:foundation, :cache, :get, :stop],
        [:foundation, :cache, :put, :stop],
        [:foundation, :cache, :delete, :stop]
      ],
      &handle_cache_telemetry/4,
      %{}
    )
    
    result = run(opts)
    
    # Detach monitoring
    :telemetry.detach("cache-load-test-monitor")
    
    result
  end
  
  # Private helpers
  
  defp fetch_product_from_db(product_id) do
    # Simulate database fetch with some delay
    Process.sleep(:rand.uniform(5))
    
    %{
      id: product_id,
      name: "Product #{product_id}",
      price: :rand.uniform(10000) / 100,
      category_id: rem(product_id, 10) + 1,
      description: "Description for product #{product_id}",
      stock: :rand.uniform(1000),
      created_at: DateTime.utc_now()
    }
  end
  
  defp add_to_cart(cart, product_id) do
    # Simulate adding product to cart
    item = %{
      product_id: product_id,
      quantity: :rand.uniform(3),
      added_at: DateTime.utc_now()
    }
    
    %{cart | 
      items: [item | cart.items],
      total: cart.total + item.quantity * :rand.uniform(100)
    }
  end
  
  defp random_ip do
    "#{:rand.uniform(255)}.#{:rand.uniform(255)}.#{:rand.uniform(255)}.#{:rand.uniform(255)}"
  end
  
  defp random_user_agent do
    agents = [
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/91.0",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) Safari/14.1",
      "Mozilla/5.0 (X11; Linux x86_64) Firefox/89.0"
    ]
    Enum.random(agents)
  end
  
  defp handle_cache_telemetry(_event, measurements, metadata, _config) do
    if measurements.duration > 1_000_000 do  # > 1ms
      Logger.warning("Slow cache operation: #{metadata.operation} took #{measurements.duration / 1_000}μs")
    end
  end
end