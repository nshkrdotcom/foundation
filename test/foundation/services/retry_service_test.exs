defmodule Foundation.Services.RetryServiceTest do
  use ExUnit.Case, async: true

  alias Foundation.Services.RetryService

  describe "RetryService" do
    test "starts successfully with unique name" do
      unique_name = :"test_retry_#{System.unique_integer()}"
      assert {:ok, pid} = RetryService.start_link(name: unique_name)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "get_stats returns service statistics with unique name" do
      unique_name = :"test_retry_#{System.unique_integer()}"
      {:ok, pid} = RetryService.start_link(name: unique_name)

      assert {:ok, stats} = GenServer.call(pid, :get_stats)
      assert Map.has_key?(stats, :retry_budget)
      assert Map.has_key?(stats, :configured_policies)
      assert Map.has_key?(stats, :config)

      GenServer.stop(pid)
    end

    test "configure_policy adds custom policy with unique name" do
      unique_name = :"test_retry_#{System.unique_integer()}"
      {:ok, pid} = RetryService.start_link(name: unique_name)

      custom_config = %{max_retries: 5, delay: 1000}
      assert :ok = GenServer.call(pid, {:configure_policy, :custom_policy, custom_config})

      {:ok, stats} = GenServer.call(pid, :get_stats)
      assert :custom_policy in stats.configured_policies

      GenServer.stop(pid)
    end

    test "handles basic functionality with unique name" do
      unique_name = :"test_retry_#{System.unique_integer()}"
      {:ok, pid} = RetryService.start_link(name: unique_name)

      # Test that the service responds to basic calls
      assert {:ok, _stats} = GenServer.call(pid, :get_stats)

      GenServer.stop(pid)
    end

    test "integrates with existing Foundation.Services.RetryService" do
      # Test that the main RetryService is running under Foundation.Services.Supervisor
      assert Foundation.Services.Supervisor.service_running?(Foundation.Services.RetryService)

      # Test that we can get stats from the main service
      assert {:ok, stats} = GenServer.call(Foundation.Services.RetryService, :get_stats)
      assert is_map(stats)
    end

    test "service properly configured under supervisor" do
      # Verify the service is properly configured in the supervision tree
      children = Supervisor.which_children(Foundation.Services.Supervisor)

      retry_service_child =
        Enum.find(children, fn {id, _pid, _type, _modules} ->
          id == Foundation.Services.RetryService
        end)

      assert retry_service_child != nil
      {_id, pid, _type, _modules} = retry_service_child
      assert Process.alive?(pid)
    end
  end

  describe "RetryService integration" do
    test "restarts properly under supervision" do
      # Get the RetryService pid from the main Foundation supervisor
      children = Supervisor.which_children(Foundation.Services.Supervisor)

      {_, retry_pid, _, _} =
        Enum.find(children, fn {id, _, _, _} ->
          id == Foundation.Services.RetryService
        end)

      # Store the original pid
      original_pid = retry_pid

      # Kill the RetryService
      Process.exit(retry_pid, :kill)

      # Wait a moment for restart
      Process.sleep(200)

      # Verify it restarted with a new pid
      new_children = Supervisor.which_children(Foundation.Services.Supervisor)

      {_, new_retry_pid, _, _} =
        Enum.find(new_children, fn {id, _, _, _} ->
          id == Foundation.Services.RetryService
        end)

      assert new_retry_pid != original_pid
      assert Process.alive?(new_retry_pid)
    end

    test "can start additional instances with unique names" do
      unique_name = :"additional_retry_#{System.unique_integer()}"

      # Start additional instance
      {:ok, additional_pid} = Foundation.Services.RetryService.start_link(name: unique_name)

      # Both should be running
      assert Process.alive?(additional_pid)
      assert Foundation.Services.Supervisor.service_running?(Foundation.Services.RetryService)

      # Clean up additional instance
      GenServer.stop(additional_pid)
    end
  end
end
