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
    # Exclude AI tests (may require API keys)
    :ai,
    # Exclude capture tests (may require instrumentation)
    :capture,
    # Exclude Phoenix tests (may require Phoenix setup)
    :phoenix,
    # Exclude distributed tests (require multiple nodes)
    :distributed,
    # Exclude real-world tests (require external projects)
    :real_world,
    # Exclude benchmarks in regular test runs
    :benchmark,
    # Exclude stress tests
    :stress,
    # Exclude memory tests
    :memory,
    # Exclude scalability tests
    :scalability,
    # Exclude regression tests
    :regression,
    # Exclude scenario tests
    :scenario,
    # Exclude external HTTP tests (use mock implementation)
    :external_http
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

# Global test setup
defmodule Foundation.TestCase do
  @moduledoc """
  Base test case with common setup for all Foundation tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Foundation.Test.Fixtures
      alias Foundation.Test.Mocks

      import Foundation.Test.Support.Assertions.CPGAssertions
      import Foundation.Test.Support.Assertions.GraphAssertions
      import Foundation.Test.Support.Assertions.PerformanceAssertions
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
Application.put_env(:foundation, :ai_providers, [:mock])
Application.put_env(:foundation, :capture_mode, :test)
