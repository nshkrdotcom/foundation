defmodule Foundation.Services.RateLimiterTest do
  use ExUnit.Case, async: true

  alias Foundation.Services.RateLimiter
  import Foundation.AsyncTestHelpers

  describe "RateLimiter service" do
    test "starts successfully with unique name" do
      unique_name = :"test_rate_limiter_#{System.unique_integer()}"
      assert {:ok, pid} = RateLimiter.start_link(name: unique_name)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "configures rate limiter successfully" do
      unique_name = :"test_rate_limiter_#{System.unique_integer()}"
      {:ok, pid} = RateLimiter.start_link(name: unique_name)

      limiter_config = %{
        # 1 minute window
        scale_ms: 60_000,
        # 100 requests per minute
        limit: 100,
        # Clean up every 5 minutes
        cleanup_interval: 300_000
      }

      assert {:ok, :api_limiter} =
               GenServer.call(pid, {:configure_limiter, :api_limiter, limiter_config})

      GenServer.stop(pid)
    end

    test "checks rate limits correctly" do
      unique_name = :"test_rate_limiter_#{System.unique_integer()}"
      {:ok, pid} = RateLimiter.start_link(name: unique_name)

      # Configure a very restrictive limiter for testing
      limiter_config = %{
        scale_ms: 60_000,
        # Only 2 requests per minute
        limit: 2,
        cleanup_interval: 300_000
      }

      {:ok, :test_limiter} =
        GenServer.call(pid, {:configure_limiter, :test_limiter, limiter_config})

      identifier = "user_123"

      # First request should be allowed
      assert {:ok, :allowed} = GenServer.call(pid, {:check_rate_limit, :test_limiter, identifier})

      # Second request should be allowed
      assert {:ok, :allowed} = GenServer.call(pid, {:check_rate_limit, :test_limiter, identifier})

      # Third request should be denied
      assert {:ok, :denied} = GenServer.call(pid, {:check_rate_limit, :test_limiter, identifier})

      GenServer.stop(pid)
    end

    test "gets rate limiter statistics" do
      unique_name = :"test_rate_limiter_#{System.unique_integer()}"
      {:ok, pid} = RateLimiter.start_link(name: unique_name)

      assert {:ok, stats} = GenServer.call(pid, :get_stats)
      assert Map.has_key?(stats, :limiters)
      assert Map.has_key?(stats, :total_checks)
      assert Map.has_key?(stats, :total_denials)

      GenServer.stop(pid)
    end

    test "handles limiter status queries" do
      unique_name = :"test_rate_limiter_#{System.unique_integer()}"
      {:ok, pid} = RateLimiter.start_link(name: unique_name)

      limiter_config = %{
        scale_ms: 60_000,
        limit: 10,
        cleanup_interval: 300_000
      }

      {:ok, :status_limiter} =
        GenServer.call(pid, {:configure_limiter, :status_limiter, limiter_config})

      identifier = "user_456"

      # Check rate limit to create some usage
      {:ok, :allowed} = GenServer.call(pid, {:check_rate_limit, :status_limiter, identifier})

      # Get status for this identifier
      assert {:ok, status} =
               GenServer.call(pid, {:get_rate_limit_status, :status_limiter, identifier})

      assert Map.has_key?(status, :remaining)
      assert Map.has_key?(status, :reset_time)
      assert status.remaining >= 0

      GenServer.stop(pid)
    end

    test "integrates with existing Foundation.Services.RateLimiter" do
      # Test that the main RateLimiter is running under Foundation.Services.Supervisor
      assert Foundation.Services.Supervisor.service_running?(Foundation.Services.RateLimiter)

      # Test that we can get stats from the main service
      assert {:ok, stats} = GenServer.call(Foundation.Services.RateLimiter, :get_stats)
      assert is_map(stats)
    end

    test "service properly configured under supervisor" do
      # Verify the service is properly configured in the supervision tree
      children = Supervisor.which_children(Foundation.Services.Supervisor)

      rate_limiter_child =
        Enum.find(children, fn {id, _pid, _type, _modules} ->
          id == Foundation.Services.RateLimiter
        end)

      assert rate_limiter_child != nil
      {_id, pid, _type, _modules} = rate_limiter_child
      assert Process.alive?(pid)
    end
  end

  describe "RateLimiter advanced features" do
    test "supports multiple limiters with different configurations" do
      unique_name = :"test_rate_limiter_#{System.unique_integer()}"
      {:ok, pid} = RateLimiter.start_link(name: unique_name)

      # Configure different limiters
      api_config = %{scale_ms: 60_000, limit: 1000, cleanup_interval: 300_000}
      admin_config = %{scale_ms: 60_000, limit: 10000, cleanup_interval: 300_000}

      {:ok, :api_limiter} = GenServer.call(pid, {:configure_limiter, :api_limiter, api_config})

      {:ok, :admin_limiter} =
        GenServer.call(pid, {:configure_limiter, :admin_limiter, admin_config})

      # Test both limiters work independently
      assert {:ok, :allowed} = GenServer.call(pid, {:check_rate_limit, :api_limiter, "user_1"})
      assert {:ok, :allowed} = GenServer.call(pid, {:check_rate_limit, :admin_limiter, "admin_1"})

      {:ok, stats} = GenServer.call(pid, :get_stats)
      assert Map.has_key?(stats.limiters, :api_limiter)
      assert Map.has_key?(stats.limiters, :admin_limiter)

      GenServer.stop(pid)
    end

    test "handles cleanup and maintenance operations" do
      unique_name = :"test_rate_limiter_#{System.unique_integer()}"
      {:ok, pid} = RateLimiter.start_link(name: unique_name)

      limiter_config = %{
        # 1 second window for faster testing
        scale_ms: 1000,
        limit: 5,
        cleanup_interval: 2000
      }

      {:ok, :cleanup_limiter} =
        GenServer.call(pid, {:configure_limiter, :cleanup_limiter, limiter_config})

      # Make some requests
      for i <- 1..3 do
        GenServer.call(pid, {:check_rate_limit, :cleanup_limiter, "user_#{i}"})
      end

      # Trigger cleanup
      assert :ok = GenServer.call(pid, :trigger_cleanup)

      {:ok, stats} = GenServer.call(pid, :get_stats)
      assert is_integer(stats.total_checks)

      GenServer.stop(pid)
    end

    test "validates limiter configuration" do
      unique_name = :"test_rate_limiter_#{System.unique_integer()}"
      {:ok, pid} = RateLimiter.start_link(name: unique_name)

      # Invalid configuration (missing required fields)
      # Missing scale_ms
      invalid_config = %{limit: 100}

      assert {:error, _reason} =
               GenServer.call(pid, {:configure_limiter, :invalid_limiter, invalid_config})

      GenServer.stop(pid)
    end

    test "handles limiter removal" do
      unique_name = :"test_rate_limiter_#{System.unique_integer()}"
      {:ok, pid} = RateLimiter.start_link(name: unique_name)

      limiter_config = %{scale_ms: 60_000, limit: 100, cleanup_interval: 300_000}

      # Configure and then remove limiter
      {:ok, :removable_limiter} =
        GenServer.call(pid, {:configure_limiter, :removable_limiter, limiter_config})

      {:ok, stats_before} = GenServer.call(pid, :get_stats)
      assert Map.has_key?(stats_before.limiters, :removable_limiter)

      assert :ok = GenServer.call(pid, {:remove_limiter, :removable_limiter})

      {:ok, stats_after} = GenServer.call(pid, :get_stats)
      refute Map.has_key?(stats_after.limiters, :removable_limiter)

      GenServer.stop(pid)
    end
  end

  describe "RateLimiter integration" do
    test "restarts properly under supervision" do
      # Get the RateLimiter pid from the main Foundation supervisor
      children = Supervisor.which_children(Foundation.Services.Supervisor)

      {_, limiter_pid, _, _} =
        Enum.find(children, fn {id, _, _, _} ->
          id == Foundation.Services.RateLimiter
        end)

      # Store the original pid
      original_pid = limiter_pid

      # Kill the RateLimiter
      Process.exit(limiter_pid, :kill)

      # Wait for supervisor to restart with new pid
      new_limiter_pid =
        wait_for(
          fn ->
            new_children = Supervisor.which_children(Foundation.Services.Supervisor)

            case Enum.find(new_children, fn {id, _, _, _} ->
                   id == Foundation.Services.RateLimiter
                 end) do
              {_, pid, _, _} when pid != original_pid and is_pid(pid) -> pid
              _ -> nil
            end
          end,
          5000
        )

      assert new_limiter_pid != original_pid
      assert Process.alive?(new_limiter_pid)
    end

    test "can start additional instances with unique names" do
      unique_name = :"additional_rate_limiter_#{System.unique_integer()}"

      # Start additional instance
      {:ok, additional_pid} = Foundation.Services.RateLimiter.start_link(name: unique_name)

      # Both should be running
      assert Process.alive?(additional_pid)
      assert Foundation.Services.Supervisor.service_running?(Foundation.Services.RateLimiter)

      # Clean up additional instance
      GenServer.stop(additional_pid)
    end
  end
end
