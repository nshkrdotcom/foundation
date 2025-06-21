defmodule Foundation.Infrastructure.PoolWorkers.HttpWorker do
  @moduledoc """
  Sample HTTP connection pool worker for demonstrating connection pooling patterns.

  This worker maintains persistent HTTP connections and provides a reusable
  template for implementing custom pool workers for different resource types.

  ## Usage

      # Start pool with HTTP workers
      ConnectionManager.start_pool(:http_pool, [
        size: 10,
        max_overflow: 5,
        worker_module: Foundation.Infrastructure.PoolWorkers.HttpWorker,
        worker_args: [base_url: "https://api.example.com", timeout: 30_000]
      ])

      # Use pooled connection
      ConnectionManager.with_connection(:http_pool, fn worker ->
        HttpWorker.get(worker, "/users/123")
      end)

  ## Worker Configuration

  - `:base_url` - Base URL for HTTP requests
  - `:timeout` - Request timeout in milliseconds
  - `:headers` - Default headers for all requests
  - `:max_redirects` - Maximum number of redirects to follow
  """

  use GenServer
  require Logger

  @type worker_config :: [
          base_url: String.t(),
          timeout: timeout(),
          headers: [{String.t(), String.t()}],
          max_redirects: non_neg_integer()
        ]

  @default_config [
    timeout: 30_000,
    headers: [{"User-Agent", "Foundation/1.0"}],
    max_redirects: 5
  ]

  ## Public API

  @doc """
  Starts an HTTP worker with the given configuration.

  This function is called by Poolboy to create worker instances.
  """
  @spec start_link(worker_config()) :: GenServer.on_start()
  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  @doc """
  Performs a GET request using the pooled worker.

  ## Parameters
  - `worker` - Worker PID from the pool
  - `path` - Request path (relative to base_url)
  - `options` - Request options (headers, params, etc.)

  ## Returns
  - `{:ok, response}` - Request successful
  - `{:error, reason}` - Request failed
  """
  @spec get(pid(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def get(worker, path, options \\ []) do
    GenServer.call(worker, {:get, path, options})
  end

  @doc """
  Performs a POST request using the pooled worker.

  ## Parameters
  - `worker` - Worker PID from the pool
  - `path` - Request path (relative to base_url)
  - `body` - Request body (will be JSON encoded)
  - `options` - Request options (headers, etc.)

  ## Returns
  - `{:ok, response}` - Request successful
  - `{:error, reason}` - Request failed
  """
  @spec post(pid(), String.t(), term(), keyword()) :: {:ok, map()} | {:error, term()}
  def post(worker, path, body, options \\ []) do
    GenServer.call(worker, {:post, path, body, options})
  end

  @doc """
  Gets the current status and configuration of the worker.

  ## Parameters
  - `worker` - Worker PID from the pool

  ## Returns
  - `{:ok, status}` - Worker status information
  """
  @spec get_status(pid()) :: {:ok, map()}
  def get_status(worker) do
    GenServer.call(worker, :get_status)
  end

  ## GenServer Implementation

  @typep state :: %{
           base_url: String.t(),
           timeout: timeout(),
           headers: [{String.t(), String.t()}],
           max_redirects: non_neg_integer(),
           stats: %{
             requests_made: non_neg_integer(),
             last_request_at: DateTime.t() | nil,
             errors: non_neg_integer()
           }
         }

  @impl GenServer
  def init(config) do
    merged_config = Keyword.merge(@default_config, config)

    case Keyword.get(merged_config, :base_url) do
      nil ->
        {:stop, {:invalid_config, :missing_base_url}}

      base_url ->
        # Basic URL validation
        case validate_base_url(base_url) do
          :ok ->
            state = %{
              base_url: base_url,
              timeout: Keyword.get(merged_config, :timeout),
              headers: Keyword.get(merged_config, :headers),
              max_redirects: Keyword.get(merged_config, :max_redirects),
              stats: %{
                requests_made: 0,
                last_request_at: nil,
                errors: 0
              }
            }

            Logger.debug("HTTP worker started for #{state.base_url}")
            {:ok, state}

          {:error, reason} ->
            {:stop, {:invalid_config, reason}}
        end
    end
  end

  @impl GenServer
  def handle_call({:get, path, options}, _from, state) do
    case do_http_request(:get, path, nil, options, state) do
      {:ok, response, new_state} ->
        {:reply, {:ok, response}, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl GenServer
  def handle_call({:post, path, body, options}, _from, state) do
    case do_http_request(:post, path, body, options, state) do
      {:ok, response, new_state} ->
        {:reply, {:ok, response}, new_state}

      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end

  @impl GenServer
  def handle_call(:get_status, _from, state) do
    status = %{
      base_url: state.base_url,
      timeout: state.timeout,
      headers: state.headers,
      stats: state.stats,
      uptime: get_uptime()
    }

    {:reply, {:ok, status}, state}
  end

  ## Private Functions

  @spec do_http_request(atom(), String.t(), term(), keyword(), state()) ::
          {:ok, map(), state()} | {:error, term(), state()}
  defp do_http_request(method, path, body, options, state) do
    base_url = build_url(state.base_url, path)

    # Handle query parameters
    url =
      case Keyword.get(options, :params) do
        nil ->
          base_url

        params when is_list(params) ->
          query_string = URI.encode_query(params)

          if String.contains?(base_url, "?") do
            "#{base_url}&#{query_string}"
          else
            "#{base_url}?#{query_string}"
          end

        _ ->
          base_url
      end

    headers = merge_headers(state.headers, Keyword.get(options, :headers, []))

    request_options = [
      timeout: state.timeout,
      max_redirects: state.max_redirects
    ]

    start_time = System.monotonic_time()

    try do
      case perform_request(method, url, body, headers, request_options) do
        {:ok, response} ->
          duration = System.monotonic_time() - start_time
          new_state = update_stats(state, :success, duration)

          Logger.debug("HTTP #{method} #{url} completed in #{duration}μs")
          {:ok, response, new_state}

        {:error, reason} ->
          duration = System.monotonic_time() - start_time
          new_state = update_stats(state, :error, duration)

          Logger.warning("HTTP #{method} #{url} failed: #{inspect(reason)}")
          {:error, reason, new_state}
      end
    rescue
      error ->
        duration = System.monotonic_time() - start_time
        new_state = update_stats(state, :error, duration)

        Logger.error("HTTP #{method} #{url} exception: #{inspect(error)}")
        {:error, {:exception, error}, new_state}
    end
  end

  @spec build_url(String.t(), String.t()) :: String.t()
  defp build_url(base_url, path) do
    base_url = String.trim_trailing(base_url, "/")
    path = String.trim_leading(path, "/")
    "#{base_url}/#{path}"
  end

  @spec merge_headers([{String.t(), String.t()}], [{String.t(), String.t()}]) ::
          [{String.t(), String.t()}]
  defp merge_headers(default_headers, request_headers) do
    # Request headers override default headers
    default_map = Enum.into(default_headers, %{})
    request_map = Enum.into(request_headers, %{})

    Map.merge(default_map, request_map)
    |> Enum.to_list()
  end

  @spec perform_request(atom(), String.t(), term(), [{String.t(), String.t()}], keyword()) ::
          {:ok, map()} | {:error, term()}
  defp perform_request(method, url, body, headers, options) do
    # This is a mock implementation - in real usage, you'd use HTTPoison, Finch, etc.
    # For demonstration purposes, we'll simulate HTTP requests with deterministic behavior

    # Check for timeout scenarios first
    timeout = Keyword.get(options, :timeout, 30_000)

    cond do
      String.contains?(url, "/delay/") ->
        # Extract delay seconds from URL pattern like /delay/5
        delay_match = Regex.run(~r"/delay/(\d+)", url)

        delay_seconds =
          case delay_match do
            [_, seconds_str] -> String.to_integer(seconds_str)
            _ -> 0
          end

        # Convert to milliseconds and check against timeout
        delay_ms = delay_seconds * 1000

        if delay_ms > timeout do
          {:error, :timeout}
        else
          Process.sleep(delay_ms)
          response_body = create_mock_response_body(method, url, headers, body)
          json_body = Jason.encode!(response_body)

          response = %{
            status_code: 200,
            headers: [{"content-type", "application/json"}],
            body: json_body
          }

          {:ok, response}
        end

      String.contains?(url, "/status/") ->
        # Extract status code from URL pattern like /status/404
        status_match = Regex.run(~r"/status/(\d+)", url)

        status_code =
          case status_match do
            [_, code_str] -> String.to_integer(code_str)
            _ -> 200
          end

        # Simulate network latency
        Process.sleep(Enum.random(10..100))

        response_body = create_mock_response_body(method, url, headers, body)
        json_body = Jason.encode!(response_body)

        response = %{
          status_code: status_code,
          headers: [{"content-type", "application/json"}],
          body: json_body
        }

        {:ok, response}

      String.contains?(url, "/bytes/") ->
        # Extract byte count from URL pattern like /bytes/10_000
        bytes_match = Regex.run(~r"/bytes/(\d+)", url)

        byte_count =
          case bytes_match do
            [_, count_str] -> String.to_integer(count_str)
            _ -> 1024
          end

        # Simulate network latency
        Process.sleep(Enum.random(10..100))

        # Return raw bytes (not JSON)
        response = %{
          status_code: 200,
          headers: [{"content-type", "application/octet-stream"}],
          body: :crypto.strong_rand_bytes(byte_count)
        }

        {:ok, response}

      String.contains?(url, "/xml") ->
        # Simulate network latency
        Process.sleep(Enum.random(10..100))

        xml_response = """
        <?xml version="1.0" encoding="UTF-8"?>
        <response>
          <method>#{method}</method>
          <url>#{url}</url>
        </response>
        """

        response = %{
          status_code: 200,
          headers: [{"content-type", "application/xml"}],
          body: xml_response
        }

        {:ok, response}

      String.contains?(url, "/nonexistent") ->
        # Simulate network latency
        Process.sleep(Enum.random(10..100))

        response_body = create_mock_response_body(method, url, headers, body)
        json_body = Jason.encode!(response_body)

        response = %{
          status_code: 404,
          headers: [{"content-type", "application/json"}],
          body: json_body
        }

        {:ok, response}

      String.contains?(url, "invalid://") ->
        {:error, :invalid_url}

      String.contains?(url, "definitely-will-cause-error") ->
        {:error, {:http_error, 404, "Not Found"}}

      String.contains?(url, "invalid-network-request") ->
        {:error, :timeout}

      true ->
        # Simulate network latency
        Process.sleep(Enum.random(10..100))

        # Default success response - simulate httpbin.org behavior
        response_body = create_httpbin_response(method, url, headers, body)
        json_body = Jason.encode!(response_body)

        response = %{
          status_code: 200,
          headers: [{"content-type", "application/json"}],
          body: json_body
        }

        {:ok, response}
    end
  end

  # Helper function to create httpbin.org-style response
  defp create_httpbin_response(method, url, headers, body) do
    # Parse URL to extract query parameters
    uri = URI.parse(url)

    query_params =
      case uri.query do
        nil -> %{}
        query_string -> URI.decode_query(query_string)
      end

    # Convert headers list to map, ensuring proper key-value format
    headers_map =
      headers
      |> Enum.into(%{}, fn
        {key, value} when is_binary(key) and is_binary(value) -> {key, value}
        other -> {"unknown", inspect(other)}
      end)

    case method do
      :get ->
        %{
          "args" => query_params,
          "headers" => headers_map,
          "origin" => "127.0.0.1",
          "url" => url
        }

      :post ->
        # Handle string vs map body encoding
        data_string =
          case body do
            body when is_binary(body) -> body
            body -> Jason.encode!(body)
          end

        %{
          "args" => query_params,
          "data" => data_string,
          "files" => %{},
          "form" => %{},
          "headers" => headers_map,
          "json" => if(is_binary(body), do: nil, else: body),
          "origin" => "127.0.0.1",
          "url" => url
        }
    end
  end

  # Helper function to create basic mock response body
  defp create_mock_response_body(method, url, headers, body) do
    # Convert headers to a safe format for JSON encoding
    headers_map =
      headers
      |> Enum.into(%{}, fn
        {key, value} when is_binary(key) and is_binary(value) -> {key, value}
        other -> {"unknown", inspect(other)}
      end)

    %{
      method: method,
      url: url,
      timestamp: DateTime.utc_now(),
      headers: headers_map,
      body: body
    }
  end

  @spec update_stats(state(), :success | :error, integer()) :: state()
  defp update_stats(state, result, _duration) do
    new_stats = %{
      state.stats
      | requests_made: state.stats.requests_made + 1,
        last_request_at: DateTime.utc_now(),
        errors:
          case result do
            :success -> state.stats.errors
            :error -> state.stats.errors + 1
          end
    }

    %{state | stats: new_stats}
  end

  @spec validate_base_url(String.t()) :: :ok | {:error, term()}
  defp validate_base_url(base_url) do
    cond do
      is_nil(base_url) or base_url == "" ->
        {:error, :empty_base_url}

      not is_binary(base_url) ->
        {:error, :invalid_base_url_type}

      not String.starts_with?(base_url, ["http://", "https://"]) ->
        {:error, :invalid_scheme}

      true ->
        :ok
    end
  end

  @spec get_uptime() :: integer()
  defp get_uptime do
    # This is a simplified uptime calculation
    # In practice, you might store the start time in the state
    System.monotonic_time()
  end
end
