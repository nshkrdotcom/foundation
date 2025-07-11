# Main test helper for Foundation enterprise test suite

ExUnit.start()

# Start the Foundation application explicitly for tests
# This ensures all components including ProcessRegistry are available
{:ok, _} = Application.ensure_all_started(:foundation)

# Wait for ProcessRegistry specifically to be available
retries = 20

wait_for_registry = fn
  _wait_fn, 0 ->
    raise "ProcessRegistry not available after maximum retries"

  wait_fn, retries_left ->
    try do
      Foundation.ProcessRegistry.stats()
      :ok
    rescue
      ArgumentError ->
        Process.sleep(100)
        wait_fn.(wait_fn, retries_left - 1)
    end
end

wait_for_registry.(wait_for_registry, retries)

# Configure ExUnit with callback to ensure Foundation is available before each test
ExUnit.configure(
  exclude: [
    # Only exclude slow tests by default
    :slow
  ],
  # 30 seconds timeout
  timeout: 30_000,
  # Stop after 10 failures
  max_failures: 10,
  # Set to true for detailed output
  trace: false,
  # Capture log output during tests
  capture_log: true
)

# Add a callback to ensure Foundation is running before each test
ExUnit.after_suite(fn _results ->
  try do
    Application.stop(:foundation)
  rescue
    _ -> :ok
  end
end)

# Hook to ensure Foundation is available before each test
defmodule FoundationTestSetup do
  use ExUnit.CaseTemplate

  setup do
    # Ensure Foundation is running before each test
    Foundation.TestHelpers.ensure_foundation_running()
    :ok
  end
end

Code.require_file("support/foundation_test_helper.exs", __DIR__)
Code.require_file("support/contract_test_helpers.exs", __DIR__)
Code.require_file("support/test_workers.exs", __DIR__)

Code.require_file("support/coordination_helpers.exs", __DIR__)
Code.require_file("support/telemetry_helpers.exs", __DIR__)

# Global test setup
defmodule Foundation.TestCase do
  @moduledoc """
  Base test case with common setup for all Foundation tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # Add any common aliases or imports here when needed
    end
  end

  setup do
    # Ensure Foundation app is running before each test
    case Foundation.available?() do
      true ->
        :ok

      false ->
        # Application is not available, restart it
        Application.stop(:foundation)
        {:ok, _} = Application.ensure_all_started(:foundation)

        # Wait for ProcessRegistry to be available
        retries = 10
        wait_for_registry(retries)
    end

    on_exit(fn ->
      # Ensure services are cleaned up but app stays running
      try do
        if Foundation.available?() do
          # Clean up any test-specific state
          :ok
        else
          # If Foundation is not available, restart it for the next test
          Application.stop(:foundation)
          {:ok, _} = Application.ensure_all_started(:foundation)
          wait_for_registry(5)
        end
      rescue
        _ -> :ok
      end
    end)

    :ok
  end

  defp wait_for_registry(0), do: :ok

  defp wait_for_registry(retries) do
    try do
      Foundation.ProcessRegistry.stats()
      :ok
    rescue
      _ ->
        Process.sleep(50)
        wait_for_registry(retries - 1)
    end
  end
end

# Configure test environment
Application.put_env(:foundation, :test_mode, true)

# Start MABEAM services if running MABEAM tests or all tests
# This allows MABEAM tests to work despite services being moved out of Foundation.Application
should_start_mabeam =
  case System.argv() do
    args when is_list(args) ->
      # Start MABEAM if:
      # 1. Explicitly running test/mabeam tests
      # 2. Running mix test without arguments (all tests)
      # 3. No test path specified (default runs all)
      Enum.any?(args, &String.contains?(&1, "test/mabeam")) or
        Enum.empty?(Enum.filter(args, &String.starts_with?(&1, "test/"))) or
        args == []

    _ ->
      true
  end

if should_start_mabeam do
  IO.puts("Starting MABEAM services for tests...")

  case MABEAM.Application.start(:normal, []) do
    {:ok, _pid} ->
      IO.puts("MABEAM services started successfully for testing")

    {:error, {:already_started, _pid}} ->
      IO.puts("MABEAM services already started")

    {:error, reason} ->
      IO.puts("Warning: Failed to start MABEAM services: #{inspect(reason)}")
  end
end
