# Gemini_ex Telemetry Instrumentation Requirements

## Overview

The Foundation library includes a pre-built `Foundation.Integrations.GeminiAdapter` that can automatically capture telemetry events from the `gemini_ex` library. However, the `gemini_ex` library currently **does not emit telemetry events**. This document outlines the telemetry instrumentation that needs to be added to `gemini_ex` to enable the integration.

## Current Status

✅ **Foundation Side**: Complete  
- `Foundation.Integrations.GeminiAdapter` is implemented and ready
- Telemetry event handlers are configured
- Event storage and processing is working

❌ **Gemini_ex Side**: Missing  
- No telemetry events are currently emitted
- No `:telemetry` dependency
- No instrumentation in HTTP client calls

## Required Changes to gemini_ex

### 1. Add Telemetry Dependency

In `gemini_ex/mix.exs`, add telemetry to dependencies:

```elixir
defp deps do
  [
    # ... existing deps ...
    {:telemetry, "~> 1.2"}
  ]
end
```

### 2. Telemetry Events to Implement

The following telemetry events need to be emitted by `gemini_ex`:

#### Request Events
- `[:gemini, :request, :start]` - When an API request begins
- `[:gemini, :request, :stop]` - When an API request completes successfully  
- `[:gemini, :request, :exception]` - When an API request fails

#### Streaming Events
- `[:gemini, :stream, :start]` - When a streaming request begins
- `[:gemini, :stream, :chunk]` - When a streaming chunk is received
- `[:gemini, :stream, :stop]` - When a streaming request completes
- `[:gemini, :stream, :exception]` - When a streaming request fails

### 3. Implementation Locations

#### 3.1 HTTP Client Instrumentation (`lib/gemini/client/http.ex`)

Add telemetry around HTTP requests in the `post/3` function:

```elixir
def post(url, body, headers \\ []) do
  start_time = System.monotonic_time()
  
  metadata = %{
    url: url,
    method: :post,
    headers: headers
  }
  
  measurements = %{
    system_time: System.system_time()
  }
  
  :telemetry.execute([:gemini, :request, :start], measurements, metadata)
  
  try do
    case Req.post(url, json: body, headers: headers, **config()) do
      {:ok, %{status: status} = response} when status in 200..299 ->
        end_time = System.monotonic_time()
        duration = System.convert_time_unit(end_time - start_time, :native, :millisecond)
        
        stop_measurements = %{
          duration: duration,
          status: status
        }
        
        :telemetry.execute([:gemini, :request, :stop], stop_measurements, metadata)
        
        {:ok, response.body}
        
      {:ok, response} ->
        error = {:http_error, response.status}
        :telemetry.execute([:gemini, :request, :exception], measurements, Map.put(metadata, :reason, error))
        {:error, error}
        
      {:error, reason} = error ->
        :telemetry.execute([:gemini, :request, :exception], measurements, Map.put(metadata, :reason, reason))
        error
    end
  rescue
    exception ->
      :telemetry.execute([:gemini, :request, :exception], measurements, Map.put(metadata, :reason, exception))
      reraise exception, __STACKTRACE__
  end
end
```

#### 3.2 Streaming Client Instrumentation (`lib/gemini/client/http_streaming.ex`)

Add telemetry around streaming requests:

```elixir
def stream_post(url, body, headers \\ []) do
  start_time = System.monotonic_time()
  
  metadata = %{
    url: url,
    method: :post,
    headers: headers,
    stream_id: generate_stream_id()
  }
  
  measurements = %{
    system_time: System.system_time()
  }
  
  :telemetry.execute([:gemini, :stream, :start], measurements, metadata)
  
  try do
    # When chunks are received:
    chunk_handler = fn chunk ->
      chunk_measurements = %{
        chunk_size: byte_size(chunk),
        system_time: System.system_time()
      }
      
      :telemetry.execute([:gemini, :stream, :chunk], chunk_measurements, metadata)
      
      # Process chunk...
    end
    
    # When stream completes:
    end_time = System.monotonic_time()
    duration = System.convert_time_unit(end_time - start_time, :native, :millisecond)
    
    stop_measurements = %{
      total_duration: duration,
      total_chunks: chunk_count
    }
    
    :telemetry.execute([:gemini, :stream, :stop], stop_measurements, metadata)
    
  rescue
    exception ->
      :telemetry.execute([:gemini, :stream, :exception], measurements, Map.put(metadata, :reason, exception))
      reraise exception, __STACKTRACE__
  end
end
```

### 4. High-Level API Instrumentation

#### 4.1 Generate Module (`lib/gemini/generate.ex`)

Add telemetry to the main content generation functions:

```elixir
def content(contents, opts \\ []) do
  metadata = %{
    function: :generate_content,
    model: Keyword.get(opts, :model, Config.default_model()),
    contents_type: classify_contents(contents)
  }
  
  case Generate.build_generate_request(contents, opts) do
    {:ok, request} ->
      HTTP.post(generate_url(metadata.model), request)
      
    {:error, _} = error ->
      error
  end
end

def stream_content(contents, opts \\ []) do
  metadata = %{
    function: :stream_generate_content,
    model: Keyword.get(opts, :model, Config.default_model()),
    contents_type: classify_contents(contents)
  }
  
  case Generate.build_generate_request(contents, opts) do
    {:ok, request} ->
      HTTPStreaming.stream_post(generate_url(metadata.model), request)
      
    {:error, _} = error ->
      error
  end
end
```

### 5. Metadata Fields to Include

#### Request Metadata
- `url` - API endpoint URL
- `method` - HTTP method (:post, :get, etc.)
- `model` - Gemini model being used
- `function` - High-level function being called (:generate_content, :stream_generate, etc.)
- `contents_type` - Type of content (text, multimodal, etc.)

#### Measurements
- `system_time` - System timestamp when event occurred
- `duration` - Request duration in milliseconds (for :stop events)
- `status` - HTTP status code (for :stop events)
- `chunk_size` - Size of streaming chunk in bytes (for :chunk events)
- `total_chunks` - Total number of chunks received (for stream :stop events)
- `total_duration` - Total streaming duration (for stream :stop events)

#### Exception Metadata
- `reason` - Exception or error reason

### 6. Helper Functions Needed

```elixir
# Generate unique stream IDs
defp generate_stream_id do
  :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
end

# Classify content types for metadata
defp classify_contents(contents) when is_binary(contents), do: :text
defp classify_contents(contents) when is_list(contents) do
  if Enum.any?(contents, &has_non_text_parts?/1) do
    :multimodal
  else
    :text
  end
end

defp has_non_text_parts?(%{parts: parts}) do
  Enum.any?(parts, fn
    %{text: _} -> false
    _ -> true
  end)
end
```

### 7. Configuration Option

Add a configuration option to enable/disable telemetry:

```elixir
# In config.exs
config :gemini,
  telemetry_enabled: true  # default: true
```

```elixir
# In telemetry execution
if Config.telemetry_enabled?() do
  :telemetry.execute(event, measurements, metadata)
end
```

## Testing the Integration

Once telemetry is implemented in `gemini_ex`, you can test the integration:

1. **Start the example app**: `cd examples/gemini_integration && mix test_integration`
2. **Check Foundation events**: Events should appear in Foundation.Events
3. **Monitor telemetry**: Use `:telemetry_test` to capture events in tests

## Benefits of This Integration

1. **Automatic Observability**: All Gemini API calls automatically logged
2. **Performance Monitoring**: Request duration and throughput tracking
3. **Error Tracking**: Failed requests and exceptions captured
4. **Streaming Analytics**: Chunk-level metrics for streaming requests
5. **Foundation Integration**: Events stored in Foundation's event system
6. **Zero Configuration**: Works automatically when both libraries are present

## Example Output

After implementation, you should see logs like:

```
[info] Foundation.Integrations.GeminiAdapter: Successfully attached to Gemini telemetry events
[debug] Captured Gemini request start: %{model: "gemini-2.0-flash", function: :generate_content}
[debug] Captured Gemini request stop: duration=1250ms
```

And Foundation events like:

```elixir
[
  %Foundation.Event{type: :gemini_request_start, data: %{model: "gemini-2.0-flash", ...}},
  %Foundation.Event{type: :gemini_request_stop, data: %{duration: 1250, ...}}
]
```
