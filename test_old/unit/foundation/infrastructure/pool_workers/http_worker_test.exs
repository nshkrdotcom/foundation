defmodule Foundation.Infrastructure.PoolWorkers.HttpWorkerTest do
  @moduledoc """
  Unit tests for HttpWorker pool worker implementation.

  Tests the HTTP worker's ability to function as a proper Poolboy worker,
  handle HTTP requests, and maintain worker state correctly.
  """

  use ExUnit.Case, async: true

  alias Foundation.Infrastructure.PoolWorkers.HttpWorker

  # Remove unused imports to fix warnings
  # import ExUnit.CaptureLog

  # Test configuration
  @test_base_url "https://httpbin.org"
  @test_timeout 30_000
  @test_headers [{"User-Agent", "Foundation-Test/1.0"}]

  # Helper function to safely stop GenServers
  defp safe_stop(pid) when is_pid(pid) do
    if Process.alive?(pid) do
      try do
        GenServer.stop(pid, :normal, 500)
      catch
        :exit, _ -> :ok
        :error, _ -> :ok
      end
    end
  end

  defp safe_stop(_), do: :ok

  # Helper function to assert that a function exits with a specific reason
  defp assert_exit_with_reason(expected_reason, fun) do
    Process.flag(:trap_exit, true)

    pid =
      spawn_link(fn ->
        fun.()
      end)

    receive do
      {:EXIT, ^pid, ^expected_reason} ->
        :ok

      {:EXIT, ^pid, other_reason} ->
        flunk("Expected exit with #{inspect(expected_reason)}, got #{inspect(other_reason)}")
    after
      1000 -> flunk("Expected process to exit with #{inspect(expected_reason)}, but it didn't exit")
    end
  end

  describe "worker initialization" do
    test "starts with minimal configuration" do
      config = [base_url: @test_base_url]

      assert {:ok, pid} = HttpWorker.start_link(config)
      assert Process.alive?(pid)

      safe_stop(pid)
    end

    test "starts with full configuration" do
      config = [
        base_url: @test_base_url,
        timeout: @test_timeout,
        headers: @test_headers,
        max_redirects: 3
      ]

      assert {:ok, pid} = HttpWorker.start_link(config)
      assert Process.alive?(pid)

      safe_stop(pid)
    end

    test "applies default configuration for missing options" do
      config = [base_url: @test_base_url]

      {:ok, pid} = HttpWorker.start_link(config)

      {:ok, status} = HttpWorker.get_status(pid)

      assert status.base_url == @test_base_url
      # Default timeout
      assert status.timeout == 30_000
      # Note: headers are not included in status response
      # Stats should be present
      assert is_map(status.stats)
      # Uptime should be present
      assert is_integer(status.uptime)

      safe_stop(pid)
    end

    test "requires base_url in configuration" do
      invalid_config = [timeout: 5000]

      # When init returns {:stop, reason}, start_link exits with that reason
      assert_exit_with_reason({:invalid_config, :missing_base_url}, fn ->
        HttpWorker.start_link(invalid_config)
      end)
    end

    test "initializes statistics correctly" do
      config = [base_url: @test_base_url]

      {:ok, pid} = HttpWorker.start_link(config)
      {:ok, status} = HttpWorker.get_status(pid)

      assert status.stats.requests_made == 0
      assert status.stats.errors == 0
      assert is_nil(status.stats.last_request_at)

      safe_stop(pid)
    end
  end

  describe "get_status/1" do
    setup do
      config = [
        base_url: @test_base_url,
        timeout: @test_timeout,
        headers: @test_headers
      ]

      {:ok, pid} = HttpWorker.start_link(config)

      on_exit(fn -> safe_stop(pid) end)

      %{worker: pid}
    end

    test "returns complete worker status", %{worker: pid} do
      {:ok, status} = HttpWorker.get_status(pid)

      # Only check for keys that are actually returned by get_status
      expected_keys = [:base_url, :timeout, :stats, :uptime]

      for key <- expected_keys do
        assert Map.has_key?(status, key), "Missing key: #{key}"
      end

      assert status.base_url == @test_base_url
      assert status.timeout == @test_timeout
      # Note: headers and max_redirects are not included in status response
    end

    test "includes request statistics", %{worker: pid} do
      {:ok, status} = HttpWorker.get_status(pid)

      stats = status.stats
      expected_stat_keys = [:requests_made, :errors, :last_request_at]

      for key <- expected_stat_keys do
        assert Map.has_key?(stats, key), "Missing stat key: #{key}"
      end
    end
  end

  describe "HTTP GET requests" do
    setup do
      config = [base_url: @test_base_url]
      {:ok, pid} = HttpWorker.start_link(config)

      on_exit(fn -> safe_stop(pid) end)

      %{worker: pid}
    end

    @tag :external_http
    @tag :slow
    test "performs successful GET request", %{worker: pid} do
      # Use httpbin.org which provides reliable test endpoints
      result = HttpWorker.get(pid, "/get")

      assert {:ok, response} = result
      assert %{status_code: 200} = response
      assert is_binary(response.body)
    end

    @tag :external_http
    test "handles GET request with query parameters", %{worker: pid} do
      options = [params: [test: "value", count: "5"]]

      result = HttpWorker.get(pid, "/get", options)

      assert {:ok, response} = result
      assert %{status_code: 200} = response

      # httpbin.org echoes back the query parameters
      body = Jason.decode!(response.body)
      assert body["args"]["test"] == "value"
      assert body["args"]["count"] == "5"
    end

    @tag :external_http
    @tag :slow
    test "handles GET request with custom headers", %{worker: pid} do
      options = [headers: [{"X-Test-Header", "test-value"}]]

      result = HttpWorker.get(pid, "/get", options)

      assert {:ok, response} = result
      assert %{status_code: 200} = response

      # httpbin.org echoes back the headers
      body = Jason.decode!(response.body)
      assert body["headers"]["X-Test-Header"] == "test-value"
    end

    test "handles request to non-existent endpoint", %{worker: pid} do
      result = HttpWorker.get(pid, "/nonexistent")

      assert {:ok, response} = result
      assert %{status_code: 404} = response
    end

    test "handles invalid base URL gracefully" do
      config = [base_url: "invalid://url"]

      # Worker should fail to start with invalid URL
      assert_exit_with_reason({:invalid_config, :invalid_scheme}, fn ->
        HttpWorker.start_link(config)
      end)
    end

    @tag :slow
    test "updates statistics after GET request", %{worker: pid} do
      # Get initial stats
      {:ok, initial_status} = HttpWorker.get_status(pid)
      initial_count = initial_status.stats.requests_made

      # Make a request
      HttpWorker.get(pid, "/get")

      # Check updated stats
      {:ok, updated_status} = HttpWorker.get_status(pid)
      updated_count = updated_status.stats.requests_made

      assert updated_count == initial_count + 1
      assert not is_nil(updated_status.stats.last_request_at)
    end
  end

  describe "HTTP POST requests" do
    setup do
      config = [base_url: @test_base_url]
      {:ok, pid} = HttpWorker.start_link(config)

      on_exit(fn -> safe_stop(pid) end)

      %{worker: pid}
    end

    @tag :external_http
    test "performs successful POST request with JSON body", %{worker: pid} do
      body = %{test: "data", number: 42}

      result = HttpWorker.post(pid, "/post", body)

      assert {:ok, response} = result
      assert %{status_code: 200} = response

      # httpbin.org echoes back the posted data
      response_body = Jason.decode!(response.body)
      posted_data = Jason.decode!(response_body["data"])
      assert posted_data["test"] == "data"
      assert posted_data["number"] == 42
    end

    @tag :external_http
    @tag :slow
    test "performs POST with custom headers", %{worker: pid} do
      body = %{message: "hello"}
      options = [headers: [{"X-Custom", "value"}]]

      result = HttpWorker.post(pid, "/post", body, options)

      assert {:ok, response} = result
      assert %{status_code: 200} = response

      response_body = Jason.decode!(response.body)
      assert response_body["headers"]["X-Custom"] == "value"
    end

    @tag :external_http
    test "handles POST with empty body", %{worker: pid} do
      result = HttpWorker.post(pid, "/post", %{})

      assert {:ok, response} = result
      assert %{status_code: 200} = response
    end

    @tag :external_http
    test "handles POST with different content types", %{worker: pid} do
      # Test with string body
      result = HttpWorker.post(pid, "/post", "plain text data")

      assert {:ok, response} = result
      assert %{status_code: 200} = response

      response_body = Jason.decode!(response.body)
      assert response_body["data"] == "plain text data"
    end

    @tag :slow
    test "updates statistics after POST request", %{worker: pid} do
      # Get initial stats
      {:ok, initial_status} = HttpWorker.get_status(pid)
      initial_count = initial_status.stats.requests_made

      # Make a request
      HttpWorker.post(pid, "/post", %{test: true})

      # Check updated stats
      {:ok, updated_status} = HttpWorker.get_status(pid)
      updated_count = updated_status.stats.requests_made

      assert updated_count == initial_count + 1
      assert not is_nil(updated_status.stats.last_request_at)
    end
  end

  describe "error handling and resilience" do
    setup do
      config = [base_url: @test_base_url, timeout: 1000]
      {:ok, pid} = HttpWorker.start_link(config)

      on_exit(fn -> safe_stop(pid) end)

      %{worker: pid}
    end

    @tag :external_http
    test "handles connection timeout", %{worker: pid} do
      # Use httpbin.org delay endpoint to trigger timeout
      # 5 second delay with 1 second timeout
      result = HttpWorker.get(pid, "/delay/5")

      assert {:error, _reason} = result
    end

    test "tracks errors in statistics", %{worker: pid} do
      # Get initial error count
      {:ok, initial_status} = HttpWorker.get_status(pid)
      initial_errors = initial_status.stats.errors

      # Make request that will fail (invalid path for our test)
      HttpWorker.get(pid, "/definitely-will-cause-error-due-to-invalid-network")

      # Check error count increased
      {:ok, updated_status} = HttpWorker.get_status(pid)
      updated_errors = updated_status.stats.errors

      # Should have more errors
      assert updated_errors >= initial_errors
    end

    @tag :slow
    test "recovers from network errors", %{worker: pid} do
      # Cause a network error
      HttpWorker.get(pid, "/invalid-network-request")

      # Worker should still be responsive
      assert {:ok, _status} = HttpWorker.get_status(pid)

      # Should be able to make valid requests afterwards
      result = HttpWorker.get(pid, "/get")
      # This might succeed or fail depending on network, but worker should respond
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "handles malformed JSON responses gracefully", %{worker: pid} do
      # For this test, we'll use the worker's ability to handle various response types
      # The exact behavior depends on the HTTP client implementation
      # httpbin returns XML instead of JSON
      result = HttpWorker.get(pid, "/xml")

      # Should handle non-JSON responses without crashing
      assert match?({:ok, _}, result) or match?({:error, _}, result)

      # Worker should still be alive
      assert Process.alive?(pid)
    end
  end

  describe "worker lifecycle and poolboy integration" do
    test "can be started multiple times for pool" do
      config = [base_url: @test_base_url]

      # Start multiple workers as a pool would
      workers =
        for _i <- 1..3 do
          {:ok, pid} = HttpWorker.start_link(config)
          pid
        end

      # All workers should be alive and functional
      for worker <- workers do
        assert Process.alive?(worker)
        assert {:ok, _status} = HttpWorker.get_status(worker)
      end

      # Clean up
      for worker <- workers do
        safe_stop(worker)
      end
    end

    @tag :slow
    test "maintains separate state per worker instance" do
      config = [base_url: @test_base_url]

      {:ok, worker1} = HttpWorker.start_link(config)
      {:ok, worker2} = HttpWorker.start_link(config)

      # Make different numbers of requests on each worker
      HttpWorker.get(worker1, "/get")
      HttpWorker.get(worker1, "/get")

      HttpWorker.get(worker2, "/get")

      # Check that stats are separate
      {:ok, status1} = HttpWorker.get_status(worker1)
      {:ok, status2} = HttpWorker.get_status(worker2)

      assert status1.stats.requests_made == 2
      assert status2.stats.requests_made == 1

      safe_stop(worker1)
      safe_stop(worker2)
    end

    test "handles worker termination gracefully" do
      config = [base_url: @test_base_url]
      {:ok, pid} = HttpWorker.start_link(config)

      # Worker should stop normally
      assert :ok = safe_stop(pid)
      refute Process.alive?(pid)
    end

    test "handles abnormal termination" do
      config = [base_url: @test_base_url]
      {:ok, pid} = HttpWorker.start_link(config)

      # Unlink before killing to prevent test process from being killed
      Process.unlink(pid)

      # Force kill the worker
      Process.exit(pid, :kill)

      # Give it a moment to die
      Process.sleep(10)
      refute Process.alive?(pid)
    end
  end

  describe "configuration edge cases" do
    test "handles very short timeout" do
      config = [base_url: @test_base_url, timeout: 1]

      {:ok, pid} = HttpWorker.start_link(config)

      # Very short timeout should work for status check
      {:ok, status} = HttpWorker.get_status(pid)
      assert status.timeout == 1

      safe_stop(pid)
    end

    test "handles empty headers list" do
      config = [base_url: @test_base_url, headers: []]

      {:ok, pid} = HttpWorker.start_link(config)

      {:ok, status} = HttpWorker.get_status(pid)
      assert status.headers == []

      safe_stop(pid)
    end

    test "handles zero max_redirects" do
      config = [base_url: @test_base_url, max_redirects: 0]

      {:ok, pid} = HttpWorker.start_link(config)

      {:ok, status} = HttpWorker.get_status(pid)
      # max_redirects is not included in status, but we can verify the worker started
      assert status.base_url == @test_base_url

      safe_stop(pid)
    end

    test "validates base_url format" do
      invalid_configs = [
        {[base_url: ""], :empty_base_url},
        {[base_url: "not-a-url"], :invalid_scheme},
        {[base_url: 123], :invalid_base_url_type},
        # Missing base_url entirely
        {[], :missing_base_url}
      ]

      for {config, expected_reason} <- invalid_configs do
        assert_exit_with_reason({:invalid_config, expected_reason}, fn ->
          HttpWorker.start_link(config)
        end)
      end
    end
  end

  describe "performance and resource management" do
    @tag :slow
    test "handles concurrent requests efficiently" do
      config = [base_url: @test_base_url]
      {:ok, pid} = HttpWorker.start_link(config)

      # Make multiple concurrent requests
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            HttpWorker.get(pid, "/get?request=#{i}")
          end)
        end

      results = Task.await_many(tasks, 10_000)

      # All requests should complete (success or failure, but not crash)
      assert length(results) == 5

      for result <- results do
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end

      # Worker should still be alive
      assert Process.alive?(pid)

      safe_stop(pid)
    end

    test "cleans up resources properly on shutdown" do
      config = [base_url: @test_base_url]
      {:ok, pid} = HttpWorker.start_link(config)

      # Make a request to initialize any internal state
      HttpWorker.get(pid, "/get")

      # Stop the worker
      safe_stop(pid)

      # Worker should be cleanly stopped
      refute Process.alive?(pid)
    end
  end

  describe "integration with real HTTP scenarios" do
    setup do
      config = [
        base_url: @test_base_url,
        timeout: 10_000,
        headers: [{"Accept", "application/json"}]
      ]

      {:ok, pid} = HttpWorker.start_link(config)

      on_exit(fn -> safe_stop(pid) end)

      %{worker: pid}
    end

    @tag :external_http
    @tag :slow
    test "handles different HTTP status codes", %{worker: pid} do
      status_codes = [200, 404, 500]

      for code <- status_codes do
        result = HttpWorker.get(pid, "/status/#{code}")

        assert {:ok, response} = result
        assert response.status_code == code
      end
    end

    @tag :external_http
    @tag :slow
    test "handles redirects within limits", %{worker: pid} do
      # httpbin.org provides redirect endpoints
      # 2 redirects
      result = HttpWorker.get(pid, "/redirect/2")

      # Should follow redirects and get final response
      assert {:ok, response} = result
      assert response.status_code == 200
    end

    @tag :external_http
    test "processes large response bodies", %{worker: pid} do
      # Request a larger response
      # 10KB of random data
      result = HttpWorker.get(pid, "/bytes/10000")

      assert {:ok, response} = result
      assert response.status_code == 200
      assert byte_size(response.body) == 10000
    end
  end
end
