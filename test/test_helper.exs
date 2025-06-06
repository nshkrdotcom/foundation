# Main test helper for Foundation enterprise test suite

ExUnit.start()

# The ProcessRegistry is already started by Foundation.Application
# Just ensure test mode is configured for proper service behavior

# Configure ExUnit
ExUnit.configure(
  exclude: [
    # Exclude slow tests by default
    :slow,
    # Exclude end-to-end tests in unit test runs
    :end_to_end,
    # Exclude distributed tests (require multiple nodes)
    :distributed,
    # Exclude benchmarks in regular test runs
    :benchmark,
    # Exclude stress tests
    :stress,
    # Exclude security tests (can be resource intensive)
    :security,
    # Exclude performance tests (can be slow)
    :performance,
    # Exclude architecture tests (can be slow)
    :architecture,
    # Exclude observability tests (can be complex)
    :observability,
    # Exclude edge case tests (can be unpredictable)
    :edge_cases,
    # Exclude deployment tests (environment specific)
    :deployment
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

Code.require_file("support/foundation_test_helper.exs", __DIR__)
Code.require_file("support/contract_test_helpers.exs", __DIR__)

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
    # Global test setup
    # TODO: Add any global setup needed

    on_exit(fn ->
      # Global test cleanup
      :ok
    end)

    :ok
  end
end

# Configure test environment
Application.put_env(:foundation, :test_mode, true)
