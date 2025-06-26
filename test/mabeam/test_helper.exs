# MABEAM Test Helper
# Sets up test environment for MABEAM modules

# Start Foundation services that MABEAM depends on
Application.ensure_all_started(:foundation)

# Start MABEAM services for testing
case MABEAM.Application.start(:normal, []) do
  {:ok, _pid} -> 
    # MABEAM services started successfully
    :ok
  {:error, {:already_started, _pid}} ->
    # Already started, that's fine
    :ok
  {:error, reason} ->
    IO.puts("Warning: Failed to start MABEAM services for testing: #{inspect(reason)}")
    # Continue anyway - some tests might still work
    :ok
end

# Configure test environment
ExUnit.start()