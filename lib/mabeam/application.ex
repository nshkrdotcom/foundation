defmodule MABEAM.Application do
  @moduledoc """
  MABEAM Application supervisor.

  Manages all MABEAM services and provides integration with Foundation infrastructure.
  """

  use Application

  @doc """
  Starts the MABEAM application with all required services.
  """
  def start(_type, _args) do
    children = [
      # Core MABEAM services
      {MABEAM.Core, name: :mabeam_core},
      {MABEAM.AgentRegistry, name: :mabeam_agent_registry},
      {MABEAM.Coordination, name: :mabeam_coordination},
      {MABEAM.Economics, name: :mabeam_economics},
      {MABEAM.Telemetry, name: :mabeam_telemetry},
      {MABEAM.AgentSupervisor, name: :mabeam_agent_supervisor},
      {MABEAM.LoadBalancer, name: :mabeam_load_balancer},
      {MABEAM.PerformanceMonitor, name: :mabeam_performance_monitor}
    ]

    opts = [strategy: :one_for_one, name: MABEAM.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @doc """
  Stops the MABEAM application gracefully.
  """
  def stop(_state) do
    :ok
  end
end
