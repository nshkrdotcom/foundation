defmodule Foundation.Services.ConnectionManagerTest do
  use ExUnit.Case, async: true

  alias Foundation.Services.ConnectionManager
  import Foundation.AsyncTestHelpers

  describe "ConnectionManager service" do
    test "starts successfully with unique name" do
      unique_name = :"test_connection_manager_#{System.unique_integer()}"
      assert {:ok, pid} = ConnectionManager.start_link(name: unique_name)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "configures HTTP pool successfully" do
      unique_name = :"test_connection_manager_#{System.unique_integer()}"
      {:ok, pid} = ConnectionManager.start_link(name: unique_name)

      pool_config = %{
        scheme: :https,
        host: "api.example.com",
        port: 443,
        size: 10,
        max_connections: 50
      }

      assert {:ok, :test_pool} = GenServer.call(pid, {:configure_pool, :test_pool, pool_config})

      GenServer.stop(pid)
    end

    test "gets pool statistics" do
      unique_name = :"test_connection_manager_#{System.unique_integer()}"
      {:ok, pid} = ConnectionManager.start_link(name: unique_name)

      assert {:ok, stats} = GenServer.call(pid, :get_stats)
      assert Map.has_key?(stats, :pools)
      assert Map.has_key?(stats, :total_connections)
      assert Map.has_key?(stats, :active_requests)

      GenServer.stop(pid)
    end

    test "handles pool configuration validation" do
      unique_name = :"test_connection_manager_#{System.unique_integer()}"
      {:ok, pid} = ConnectionManager.start_link(name: unique_name)

      # Invalid configuration (missing required fields)
      invalid_config = %{size: 10}

      assert {:error, _reason} =
               GenServer.call(pid, {:configure_pool, :invalid_pool, invalid_config})

      GenServer.stop(pid)
    end

    test "integrates with existing Foundation.Services.ConnectionManager" do
      # Test that the main ConnectionManager is running under Foundation.Services.Supervisor
      assert Foundation.Services.Supervisor.service_running?(Foundation.Services.ConnectionManager)

      # Test that we can get stats from the main service
      assert {:ok, stats} = GenServer.call(Foundation.Services.ConnectionManager, :get_stats)
      assert is_map(stats)
    end

    test "service properly configured under supervisor" do
      # Verify the service is properly configured in the supervision tree
      children = Supervisor.which_children(Foundation.Services.Supervisor)

      connection_manager_child =
        Enum.find(children, fn {id, _pid, _type, _modules} ->
          id == Foundation.Services.ConnectionManager
        end)

      assert connection_manager_child != nil
      {_id, pid, _type, _modules} = connection_manager_child
      assert Process.alive?(pid)
    end
  end

  describe "ConnectionManager HTTP operations" do
    test "supports making HTTP requests with pool" do
      unique_name = :"test_connection_manager_#{System.unique_integer()}"
      {:ok, pid} = ConnectionManager.start_link(name: unique_name)

      # Configure a test pool
      pool_config = %{
        scheme: :https,
        host: "httpbin.org",
        port: 443,
        size: 5,
        max_connections: 20
      }

      {:ok, :test_pool} = GenServer.call(pid, {:configure_pool, :test_pool, pool_config})

      # Create a simple HTTP request
      request = %{
        method: :get,
        path: "/status/200",
        headers: [{"accept", "application/json"}],
        body: nil
      }

      # Make request through connection manager using public API
      assert {:ok, response} = ConnectionManager.execute_request(:test_pool, request, pid)
      assert response.status == 200

      GenServer.stop(pid)
    end

    test "handles connection failures gracefully" do
      unique_name = :"test_connection_manager_#{System.unique_integer()}"
      {:ok, pid} = ConnectionManager.start_link(name: unique_name)

      # Configure a pool to non-existent host
      pool_config = %{
        scheme: :https,
        host: "non-existent-host.invalid",
        port: 443,
        size: 1,
        max_connections: 5
      }

      {:ok, :failure_pool} = GenServer.call(pid, {:configure_pool, :failure_pool, pool_config})

      request = %{
        method: :get,
        path: "/",
        headers: [],
        body: nil
      }

      # Should handle connection failure gracefully
      assert {:error, _reason} = ConnectionManager.execute_request(:failure_pool, request, pid)

      GenServer.stop(pid)
    end

    test "pool management operations work correctly" do
      unique_name = :"test_connection_manager_#{System.unique_integer()}"
      {:ok, pid} = ConnectionManager.start_link(name: unique_name)

      pool_config = %{
        scheme: :https,
        host: "api.example.com",
        port: 443,
        size: 5,
        max_connections: 25
      }

      # Configure pool
      {:ok, :management_pool} =
        GenServer.call(pid, {:configure_pool, :management_pool, pool_config})

      # Check pool exists
      {:ok, stats} = GenServer.call(pid, :get_stats)
      assert Map.has_key?(stats.pools, :management_pool)

      # Remove pool
      assert :ok = GenServer.call(pid, {:remove_pool, :management_pool})

      # Verify pool removed
      {:ok, updated_stats} = GenServer.call(pid, :get_stats)
      refute Map.has_key?(updated_stats.pools, :management_pool)

      GenServer.stop(pid)
    end
  end

  describe "ConnectionManager integration" do
    test "restarts properly under supervision" do
      # Get the ConnectionManager pid from the main Foundation supervisor
      children = Supervisor.which_children(Foundation.Services.Supervisor)

      {_, manager_pid, _, _} =
        Enum.find(children, fn {id, _, _, _} ->
          id == Foundation.Services.ConnectionManager
        end)

      # Store the original pid
      original_pid = manager_pid

      # Kill the ConnectionManager
      Process.exit(manager_pid, :kill)

      # Wait for supervisor to restart with new pid
      new_manager_pid =
        wait_for(
          fn ->
            new_children = Supervisor.which_children(Foundation.Services.Supervisor)

            case Enum.find(new_children, fn {id, _, _, _} ->
                   id == Foundation.Services.ConnectionManager
                 end) do
              {_, pid, _, _} when pid != original_pid and is_pid(pid) -> pid
              _ -> nil
            end
          end,
          5000
        )

      assert new_manager_pid != original_pid
      assert Process.alive?(new_manager_pid)
    end

    test "can start additional instances with unique names" do
      unique_name = :"additional_connection_manager_#{System.unique_integer()}"

      # Start additional instance
      {:ok, additional_pid} = Foundation.Services.ConnectionManager.start_link(name: unique_name)

      # Both should be running
      assert Process.alive?(additional_pid)
      assert Foundation.Services.Supervisor.service_running?(Foundation.Services.ConnectionManager)

      # Clean up additional instance
      GenServer.stop(additional_pid)
    end
  end
end
