defmodule Foundation.TestSupervisor do
  @moduledoc """
  Special supervisor for tests that need more lenient restart policies.
  Only use when testing crash/restart behavior specifically.
  """
  use Supervisor

  def start_link(children) do
    # More lenient for specific test scenarios only
    Supervisor.start_link(__MODULE__, children, name: __MODULE__)
  end

  @impl true
  def init(children) do
    # Test-specific lenient strategy
    Supervisor.init(children, strategy: :one_for_one, max_restarts: 100, max_seconds: 10)
  end
end
