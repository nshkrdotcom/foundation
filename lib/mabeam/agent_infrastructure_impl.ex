defimpl Foundation.Infrastructure, for: MABEAM.AgentInfrastructure do
  @moduledoc """
  Foundation.Infrastructure protocol implementation for MABEAM.AgentInfrastructure.

  All operations are delegated to the GenServer process to ensure
  consistency and proper state management.
  """

  # --- Circuit Breaker Operations ---

  def register_circuit_breaker(infrastructure_pid, service_id, config) do
    GenServer.call(infrastructure_pid, {:register_circuit_breaker, service_id, config})
  end

  def execute_protected(infrastructure_pid, service_id, function, context) do
    GenServer.call(infrastructure_pid, {:execute_protected, service_id, function, context})
  end

  def get_circuit_status(infrastructure_pid, service_id) do
    GenServer.call(infrastructure_pid, {:get_circuit_status, service_id})
  end

  # --- Rate Limiting Operations ---

  def setup_rate_limiter(infrastructure_pid, limiter_id, config) do
    GenServer.call(infrastructure_pid, {:setup_rate_limiter, limiter_id, config})
  end

  def check_rate_limit(infrastructure_pid, limiter_id, identifier) do
    GenServer.call(infrastructure_pid, {:check_rate_limit, limiter_id, identifier})
  end

  def get_rate_limit_status(infrastructure_pid, limiter_id, identifier) do
    GenServer.call(infrastructure_pid, {:get_rate_limit_status, limiter_id, identifier})
  end

  # --- Resource Monitoring Operations ---

  def monitor_resource(infrastructure_pid, resource_id, config) do
    GenServer.call(infrastructure_pid, {:monitor_resource, resource_id, config})
  end

  def get_resource_usage(infrastructure_pid, resource_id) do
    GenServer.call(infrastructure_pid, {:get_resource_usage, resource_id})
  end
end
