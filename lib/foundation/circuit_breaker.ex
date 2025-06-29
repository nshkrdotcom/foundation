defmodule Foundation.CircuitBreaker do
  @moduledoc """
  Convenience module for circuit breaker functionality.
  
  Delegates to Foundation.Infrastructure.CircuitBreaker.
  """
  
  defdelegate configure(service_id, config \\ []), to: Foundation.Infrastructure.CircuitBreaker
  defdelegate call(service_id, function, opts \\ []), to: Foundation.Infrastructure.CircuitBreaker
  defdelegate get_status(service_id), to: Foundation.Infrastructure.CircuitBreaker
  defdelegate reset(service_id), to: Foundation.Infrastructure.CircuitBreaker
  defdelegate start_link(opts \\ []), to: Foundation.Infrastructure.CircuitBreaker
end