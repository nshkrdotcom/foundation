defmodule Foundation.ServiceIntegration do
  @moduledoc """
  Main integration interface for Foundation Service Integration Architecture.
  
  This module rebuilds the lost Service Integration functionality that was
  accidentally deleted during the P23aTranscend.md issue resolution. It provides
  a unified interface for service dependency management, health checking,
  and contract validation.

  ## Key Components

  - `Foundation.ServiceIntegration.ContractValidator` - Service contract validation
  - `Foundation.ServiceIntegration.DependencyManager` - Service dependency management  
  - `Foundation.ServiceIntegration.HealthChecker` - Unified health checking
  - `Foundation.ServiceIntegration.ContractEvolution` - Contract evolution utilities

  ## Usage

      # Get overall integration status
      {:ok, status} = Foundation.ServiceIntegration.integration_status()

      # Validate all service contracts
      {:ok, result} = Foundation.ServiceIntegration.validate_service_integration()

      # Start services in dependency order
      :ok = Foundation.ServiceIntegration.start_services_in_order([:my_service])

      # Graceful shutdown
      :ok = Foundation.ServiceIntegration.shutdown_services_gracefully([:my_service])
  """

  require Logger

  # Use full module names to avoid compilation dependency issues

  @doc """
  Provides comprehensive service health and dependency status.

  Returns a complete overview of the Foundation Service Integration status
  including service health, contract validation, and dependency information.
  """
  @spec integration_status() :: {:ok, map()} | {:error, term()}
  def integration_status do
    start_time = System.monotonic_time()
    
    result = try do
      # Gather status from all components
      contract_status = get_contract_status()
      service_health = get_service_health()
      dependency_status = get_dependency_status()
      
      overall_status = %{
        timestamp: DateTime.utc_now(),
        contract_validation: contract_status,
        service_health: service_health,
        dependency_management: dependency_status,
        integration_components: %{
          contract_validator: process_status(Foundation.ServiceIntegration.ContractValidator),
          dependency_manager: process_status(Foundation.ServiceIntegration.DependencyManager),
          health_checker: process_status(Foundation.ServiceIntegration.HealthChecker)
        }
      }
      
      {:ok, overall_status}
    rescue
      exception ->
        Logger.error("Exception getting integration status", exception: inspect(exception))
        {:error, {:integration_status_exception, exception}}
    end
    
    # Emit telemetry
    duration = System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond)
    :telemetry.execute(
      [:foundation, :service_integration, :status_check],
      %{duration: duration},
      %{result: elem(result, 0)}
    )
    
    result
  end

  @doc """
  Validates all service integration components.

  Performs system-wide integration validation including contract compliance,
  service availability, and dependency resolution.
  """
  @spec validate_service_integration() :: {:ok, map()} | {:error, term()}
  def validate_service_integration do
    try do
      # Use the working ContractValidator
      contract_result = case Process.whereis(Foundation.ServiceIntegration.ContractValidator) do
        nil -> 
          Logger.warning("ContractValidator not running, starting temporarily")
          {:ok, _pid} = Foundation.ServiceIntegration.ContractValidator.start_link(name: :temp_validator)
          result = GenServer.call(:temp_validator, :validate_all_contracts)
          GenServer.stop(:temp_validator)
          result
        _pid -> 
          GenServer.call(Foundation.ServiceIntegration.ContractValidator, :validate_all_contracts)
      end
      
      case contract_result do
        {:ok, validation_result} ->
          integration_result = %{
            contract_validation: validation_result,
            validation_timestamp: DateTime.utc_now(),
            validation_summary: summarize_validation_result(validation_result)
          }
          
          {:ok, integration_result}
          
        {:error, reason} ->
          {:error, {:contract_validation_failed, reason}}
      end
    rescue
      exception ->
        Logger.error("Exception during service integration validation", exception: inspect(exception))
        {:error, {:validation_exception, exception}}
    end
  end

  @doc """
  Starts services in proper dependency order.

  Takes a list of service modules and starts them in an order that respects
  their dependencies. Currently a placeholder for future DependencyManager integration.
  """
  @spec start_services_in_order([module()]) :: :ok | {:error, term()}
  def start_services_in_order(services) when is_list(services) do
    Logger.info("Starting services in dependency order", services: services)
    
    # Use DependencyManager for proper ordering
    case ensure_dependency_manager_running() do
      {:ok, _pid} ->
        case Foundation.ServiceIntegration.DependencyManager.start_services_in_dependency_order(services) do
          :ok -> :ok
          {:error, reason} -> {:error, reason}
        end
      {:error, reason} ->
        Logger.warning("DependencyManager unavailable, starting in provided order", reason: reason)
        start_services_simple(services)
    end
  end
  
  defp start_services_simple(services) do
    results = Enum.map(services, fn service ->
      try do
        case service.start_link() do
          {:ok, _pid} -> {:ok, service}
          {:error, {:already_started, _pid}} -> {:ok, service}
          {:error, reason} -> {:error, {service, reason}}
        end
      rescue
        exception -> {:error, {service, {:start_exception, exception}}}
      end
    end)
    
    failed = Enum.filter(results, &match?({:error, _}, &1))
    
    case failed do
      [] -> 
        Logger.info("All services started successfully", services: services)
        :ok
      failures ->
        Logger.error("Some services failed to start", failures: failures)
        {:error, {:service_startup_failures, failures}}
    end
  end

  @doc """
  Shuts down services gracefully in reverse dependency order.

  Stops services in an order that respects their dependencies, shutting down
  dependents before their dependencies.
  """
  @spec shutdown_services_gracefully([module()]) :: :ok | {:error, term()}
  def shutdown_services_gracefully(services) when is_list(services) do
    Logger.info("Shutting down services gracefully", services: services)
    
    # For now, shut down services in reverse order
    # TODO: Integrate with DependencyManager when implemented
    reverse_services = Enum.reverse(services)
    
    results = Enum.map(reverse_services, fn service ->
      try do
        case Process.whereis(service) do
          nil -> {:ok, service}  # Already stopped
          pid ->
            GenServer.stop(pid, :normal, 5000)
            {:ok, service}
        end
      rescue
        exception -> {:error, {service, {:shutdown_exception, exception}}}
      end
    end)
    
    failed = Enum.filter(results, &match?({:error, _}, &1))
    
    case failed do
      [] -> 
        Logger.info("All services shut down successfully", services: reverse_services)
        :ok
      failures ->
        Logger.warning("Some services failed to shut down cleanly", failures: failures)
        {:error, {:service_shutdown_failures, failures}}
    end
  end

  ## Testing and Development Utilities

  @doc """
  Quick validation check for Discovery service contract evolution.
  
  This specifically addresses Category 3 contract violations by testing
  whether MABEAM.Discovery supports the evolved function signatures.
  """
  @spec validate_discovery_evolution() :: boolean()
  def validate_discovery_evolution do
    try do
      Foundation.ServiceIntegration.ContractEvolution.validate_discovery_functions(MABEAM.Discovery)
    rescue
      _exception -> 
        # If MABEAM.Discovery is not available, return false
        false
    end
  end

  @doc """
  Development utility to check service integration component status.
  """
  @spec component_status() :: map()
  def component_status do
    %{
      contract_validator: process_status(Foundation.ServiceIntegration.ContractValidator),
      contract_evolution: module_status(Foundation.ServiceIntegration.ContractEvolution),
      dependency_manager: process_status(Foundation.ServiceIntegration.DependencyManager),
      health_checker: process_status(Foundation.ServiceIntegration.HealthChecker),
      signal_coordinator: process_status(Foundation.ServiceIntegration.SignalCoordinator),
      timestamp: DateTime.utc_now()
    }
  end

  ## Private Functions

  defp get_contract_status do
    case Process.whereis(Foundation.ServiceIntegration.ContractValidator) do
      nil -> :validator_not_running
      _pid -> 
        case GenServer.call(Foundation.ServiceIntegration.ContractValidator, :get_validation_status) do
          {:ok, status} -> status
          {:error, :not_validated} -> :not_yet_validated
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp get_service_health do
    case Process.whereis(Foundation.ServiceIntegration.HealthChecker) do
      nil -> 
        # Fallback to simple process checking
        foundation_services = [
          Foundation.Services.RetryService,
          Foundation.Services.ConnectionManager,
          Foundation.Services.RateLimiter,
          Foundation.Services.SignalBus
        ]
        
        health_status = Enum.map(foundation_services, fn service ->
          case Process.whereis(service) do
            nil -> {service, :unavailable}
            _pid -> {service, :available}
          end
        end)
        
        %{foundation_services: health_status, health_checker: :not_running}
      _pid ->
        case GenServer.call(Foundation.ServiceIntegration.HealthChecker, :system_health_summary) do
          {:ok, summary} -> summary
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp get_dependency_status do
    case Process.whereis(Foundation.ServiceIntegration.DependencyManager) do
      nil -> :dependency_manager_not_running
      _pid ->
        case Foundation.ServiceIntegration.DependencyManager.get_all_dependencies() do
          dependencies when is_map(dependencies) ->
            %{
              registered_services: Map.keys(dependencies),
              dependency_count: map_size(dependencies),
              status: :operational
            }
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp process_status(module) do
    case Process.whereis(module) do
      nil -> :not_running
      pid -> %{pid: pid, status: :running}
    end
  end

  defp module_status(module) do
    case Code.ensure_compiled(module) do
      {:module, ^module} -> :available
      {:error, _reason} -> :not_available
    end
  end

  defp summarize_validation_result(validation_result) do
    case validation_result.status do
      :all_valid -> :all_contracts_valid
      :evolution_detected -> :contract_evolution_handled
      :some_violations -> :validation_issues_detected
      other -> other
    end
  end
  
  defp ensure_dependency_manager_running do
    case Process.whereis(Foundation.ServiceIntegration.DependencyManager) do
      nil ->
        Logger.info("Starting temporary DependencyManager for service ordering")
        Foundation.ServiceIntegration.DependencyManager.start_link(name: :temp_dependency_manager)
      pid ->
        {:ok, pid}
    end
  end
end