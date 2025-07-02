# Error Context Logger Metadata Migration Guide

## Overview

As part of the OTP cleanup initiative (Stage 3), the `Foundation.ErrorContext` module has been updated to use Logger metadata instead of the Process dictionary for storing error context. This change improves compliance with OTP patterns, enables better integration with logging infrastructure, and maintains backward compatibility through feature flags.

## Benefits of Logger Metadata

1. **OTP Compliance**: Eliminates Process dictionary anti-pattern
2. **Better Observability**: Context automatically appears in logs (with proper formatter)
3. **Standard Pattern**: Uses established Elixir/OTP patterns
4. **Performance**: Comparable performance to Process dictionary (within 1.16x)
5. **Integration**: Works seamlessly with existing Logger infrastructure

## Migration Guide

### Step 1: Enable Feature Flag

The migration is controlled by the `:use_logger_error_context` feature flag:

```elixir
# Enable Logger metadata mode
Foundation.FeatureFlags.enable(:use_logger_error_context)

# Check current mode
Foundation.FeatureFlags.enabled?(:use_logger_error_context)
# => true

# Disable to use legacy Process dictionary mode
Foundation.FeatureFlags.disable(:use_logger_error_context)
```

### Step 2: Update Application Configuration

You can also set the feature flag in your application configuration:

```elixir
# config/config.exs
config :foundation, :feature_flags, %{
  use_logger_error_context: true
}
```

### Step 3: Configure Logger Backend (Optional)

To see error context in your logs, configure your Logger backend to include metadata:

```elixir
# config/config.exs
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:error_context, :request_id, :user_id]
```

## API Usage

The API remains the same regardless of which mode is enabled:

### Setting Context

```elixir
# Set context (works with both modes)
context = %{request_id: "req-123", user_id: "user-456", operation: "payment"}
Foundation.ErrorContext.set_context(context)

# Create structured context
context = Foundation.ErrorContext.new(MyModule, :my_function,
  correlation_id: "corr-789",
  metadata: %{important: "data"}
)
Foundation.ErrorContext.set_context(context)
```

### Getting Context

```elixir
# Retrieve current context
context = Foundation.ErrorContext.get_context()
# => %{request_id: "req-123", user_id: "user-456", operation: "payment"}

# Works the same with structured contexts
context = Foundation.ErrorContext.get_current_context()
```

### Clearing Context

```elixir
# Clear context from current process
Foundation.ErrorContext.clear_context()
```

### Executing with Context

```elixir
# Execute function with automatic context management
result = Foundation.ErrorContext.with_context(context, fn ->
  # Context is available here
  do_operation()
end)

# On exception, context is automatically added to error
{:error, %Foundation.Error{} = error} = result
# error.context includes operation_context with all details
```

### Temporary Context

```elixir
# Execute with temporary context (restored after)
Foundation.ErrorContext.set_context(%{base: "context"})

Foundation.ErrorContext.with_temporary_context(%{temp: "data"}, fn ->
  # Temporary context active here
  Foundation.ErrorContext.get_context()
  # => %{temp: "data"}
end)

# Original context restored
Foundation.ErrorContext.get_context()
# => %{base: "context"}
```

### Error Enrichment

```elixir
# Automatically enrich errors with current context
Foundation.ErrorContext.set_context(%{request_id: "req-123"})

# Enrich an error
error = Foundation.Error.new(:validation_failed, "Invalid input")
enriched = Foundation.ErrorContext.enrich_error(error)
# => Error now includes request_id in context

# Works with error tuples too
{:error, enriched} = Foundation.ErrorContext.enrich_error({:error, :timeout})
# => {:error, %Foundation.Error{context: %{request_id: "req-123", ...}}}
```

### Context Inheritance for Spawned Processes

```elixir
# Parent process sets context
Foundation.ErrorContext.set_context(%{trace_id: "trace-123"})

# Spawn child with inherited context
pid = Foundation.ErrorContext.spawn_with_context(fn ->
  # Child has parent's context
  context = Foundation.ErrorContext.get_context()
  # => %{trace_id: "trace-123"}
  
  process_task()
end)

# Also works with linked processes
pid = Foundation.ErrorContext.spawn_link_with_context(fn ->
  # Linked process has context
  process_with_supervision()
end)
```

## Testing

When testing code that uses error context, the feature flag can be toggled:

```elixir
defmodule MyTest do
  use ExUnit.Case
  
  setup do
    # Save original flag state
    original = Foundation.FeatureFlags.enabled?(:use_logger_error_context)
    
    # Enable Logger metadata mode for tests
    Foundation.FeatureFlags.enable(:use_logger_error_context)
    
    on_exit(fn ->
      # Restore original state
      if original do
        Foundation.FeatureFlags.enable(:use_logger_error_context)
      else
        Foundation.FeatureFlags.disable(:use_logger_error_context)
      end
    end)
    
    :ok
  end
  
  test "error context is preserved" do
    Foundation.ErrorContext.set_context(%{test: true})
    assert Foundation.ErrorContext.get_context() == %{test: true}
  end
end
```

## Performance Considerations

Performance testing shows Logger metadata has comparable performance to Process dictionary:
- Logger metadata: ~1.16x slower than Process dictionary
- Absolute difference: ~1 microsecond per operation
- Acceptable trade-off for the benefits gained

## Migration Timeline

1. **Phase 1** (Current): Feature flag available, Process dictionary still default
2. **Phase 2**: Enable feature flag in staging/development environments
3. **Phase 3**: Enable in production with monitoring
4. **Phase 4**: Make Logger metadata the default
5. **Phase 5**: Remove Process dictionary code path

## Troubleshooting

### Context Not Appearing in Logs

Ensure your Logger backend is configured to include metadata:

```elixir
config :logger, :console,
  metadata: [:error_context, :request_id]
```

### Context Lost After Process Spawn

Use the provided spawn functions to inherit context:

```elixir
# Instead of
spawn(fn -> do_work() end)

# Use
Foundation.ErrorContext.spawn_with_context(fn -> do_work() end)
```

### Performance Concerns

If performance is critical:
1. Measure actual impact in your use case
2. Consider batching context updates
3. Use Process dictionary mode for hot paths (temporarily)

## Summary

The Logger metadata implementation provides a cleaner, more OTP-compliant way to manage error context while maintaining full backward compatibility. The migration can be done gradually using feature flags, with minimal code changes required.