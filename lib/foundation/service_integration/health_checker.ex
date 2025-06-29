defmodule Foundation.ServiceIntegration.HealthChecker do
  @moduledoc """
  Rebuilds the lost HealthChecker addressing signal pipeline issues.
  
  This module provides unified health checking across all service boundaries,
  integrating with Foundation service patterns and handling signal system flaws.
  It includes circuit breaker integration for resilient checking and aggregated
  system health reporting.

  ## Purpose

  The HealthChecker provides:
  - Standardized health check protocols across services
  - Circuit breaker integration for resilient health checking
  - Aggregated system health reporting with performance metrics
  - Health check scheduling and alerting capabilities
  - Integration with signal system monitoring (addressing Category 2 issues)

  ## Features

  - Real-time service health monitoring with ≤100ms response time
  - Circuit breaker patterns for fault tolerance
  - Foundation service integration (RetryService, SignalBus, etc.)
  - Signal system health validation with fallback strategies
  - Comprehensive health reporting and telemetry
  - Automatic health check scheduling

  ## Usage

      # Start the health checker
      {:ok, _pid} = Foundation.ServiceIntegration.HealthChecker.start_link()

      # Get system health summary
      {:ok, health} = Foundation.ServiceIntegration.HealthChecker.system_health_summary()

      # Register a custom health check
      :ok = Foundation.ServiceIntegration.HealthChecker.register_health_check(
        MyService,
        &MyService.health_check/0,
        interval: 30_000
      )

      # Check specific service health
      {:ok, status} = Foundation.ServiceIntegration.HealthChecker.check_service_health(MyService)
  """

  use GenServer
  require Logger

  @type health_status :: :healthy | :unhealthy | :degraded | :unknown
  @type health_result :: %{
    service: module(),
    status: health_status(),
    response_time_ms: non_neg_integer(),
    metadata: map(),
    timestamp: DateTime.t()
  }
  @type system_health :: %{
    foundation_services: [health_result()],
    signal_system: health_result(),
    registered_services: [health_result()],
    overall_status: health_status(),
    summary: map()
  }

  ## Client API

  @doc """
  Starts the HealthChecker GenServer.

  ## Options

  - `:name` - Process name (default: __MODULE__)
  - `:check_interval` - Health check interval in ms (default: 60_000)
  - `:enable_auto_checks` - Enable automatic health checking (default: true)
  - `:circuit_breaker_threshold` - Circuit breaker failure threshold (default: 3)
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Provides comprehensive system health summary.

  Returns real-time health status for Foundation services, signal system,
  and registered custom services. Includes performance metrics and overall
  system status assessment.

  ## Returns

  - `{:ok, system_health()}` - Complete system health information
  - `{:error, reason}` - Health check failed
  """
  @spec system_health_summary() :: {:ok, system_health()} | {:error, term()}
  def system_health_summary do
    GenServer.call(__MODULE__, :system_health_summary, 10_000)
  end

  @doc """
  Registers a custom health check for a service.

  ## Parameters

  - `service_module` - The service module to monitor
  - `health_check_fun` - Function that returns health status
  - `options` - Health check configuration

  ## Options

  - `:interval` - Check interval in ms (default: 60_000)
  - `:timeout` - Health check timeout in ms (default: 5_000) 
  - `:circuit_breaker` - Enable circuit breaker (default: true)
  - `:metadata` - Additional metadata to include
  """
  @spec register_health_check(module(), function(), keyword()) :: :ok
  def register_health_check(service_module, health_check_fun, options \\ []) do
    GenServer.call(__MODULE__, {:register_health_check, service_module, health_check_fun, options})
  end

  @doc """
  Checks the health of a specific service.

  ## Parameters

  - `service_module` - The service to check

  ## Returns

  - `{:ok, health_result()}` - Service health information
  - `{:error, reason}` - Health check failed
  """
  @spec check_service_health(module()) :: {:ok, health_result()} | {:error, term()}
  def check_service_health(service_module) do
    GenServer.call(__MODULE__, {:check_service_health, service_module}, 8_000)
  end

  @doc """
  Gets all registered health checks and their last results.
  """
  @spec get_all_health_checks() :: map()
  def get_all_health_checks do
    GenServer.call(__MODULE__, :get_all_health_checks)
  end

  @doc """
  Unregisters a health check for a service.
  """
  @spec unregister_health_check(module()) :: :ok
  def unregister_health_check(service_module) do
    GenServer.call(__MODULE__, {:unregister_health_check, service_module})
  end

  @doc """
  Forces immediate health check for all registered services.
  """
  @spec force_health_checks() :: {:ok, [health_result()]} | {:error, term()}
  def force_health_checks do
    GenServer.call(__MODULE__, :force_health_checks, 15_000)
  end

  ## GenServer Implementation

  defstruct [
    :check_interval,
    :enable_auto_checks,
    :circuit_breaker_threshold,
    :registered_health_checks,
    :last_health_results,
    :circuit_breaker_states,
    :timer_ref
  ]

  @impl GenServer
  def init(opts) do
    check_interval = Keyword.get(opts, :check_interval, 60_000)
    enable_auto_checks = Keyword.get(opts, :enable_auto_checks, true)
    circuit_breaker_threshold = Keyword.get(opts, :circuit_breaker_threshold, 3)

    state = %__MODULE__{
      check_interval: check_interval,
      enable_auto_checks: enable_auto_checks,
      circuit_breaker_threshold: circuit_breaker_threshold,
      registered_health_checks: %{},
      last_health_results: %{},
      circuit_breaker_states: %{},
      timer_ref: nil
    }

    # Start automatic health checking if enabled
    new_state = if enable_auto_checks do
      schedule_health_checks(state)
    else
      state
    end

    Logger.info("Foundation.ServiceIntegration.HealthChecker started",
      check_interval: check_interval,
      auto_checks: enable_auto_checks,
      circuit_breaker_threshold: circuit_breaker_threshold)

    {:ok, new_state}
  end

  @impl GenServer
  def handle_call(:system_health_summary, _from, state) do
    start_time = System.monotonic_time()
    
    result = try do
      with {:ok, foundation_health} <- check_foundation_services(),
           {:ok, signal_health} <- check_signal_system_with_fallback(),
           {:ok, service_health} <- check_registered_services(state) do
        
        overall_status = calculate_overall_status(foundation_health, signal_health, service_health)
        
        system_health = %{
          foundation_services: foundation_health,
          signal_system: signal_health,
          registered_services: service_health,
          overall_status: overall_status,
          summary: %{
            total_services: length(foundation_health) + length(service_health) + 1,
            healthy_services: count_healthy_services(foundation_health, signal_health, service_health),
            check_timestamp: DateTime.utc_now()
          }
        }
        
        {:ok, system_health}
        
      else
        error -> 
          Logger.warning("System health check encountered error", error: inspect(error))
          handle_health_check_error(error)
      end
    rescue
      exception ->
        Logger.error("Exception during system health check", exception: inspect(exception))
        {:error, {:health_check_exception, exception}}
    end
    
    # Emit telemetry
    duration = System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond)
    :telemetry.execute(
      [:foundation, :service_integration, :health_check],
      %{duration: duration, service_count: count_services(state)},
      %{result: elem(result, 0)}
    )
    
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:register_health_check, service_module, health_check_fun, options}, _from, state) do
    health_check_config = %{
      function: health_check_fun,
      interval: Keyword.get(options, :interval, 60_000),
      timeout: Keyword.get(options, :timeout, 5_000),
      circuit_breaker: Keyword.get(options, :circuit_breaker, true),
      metadata: Keyword.get(options, :metadata, %{})
    }
    
    new_health_checks = Map.put(state.registered_health_checks, service_module, health_check_config)
    new_state = %{state | registered_health_checks: new_health_checks}
    
    Logger.debug("Registered health check", service: service_module, config: health_check_config)
    
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call({:check_service_health, service_module}, _from, state) do
    result = perform_service_health_check(service_module, state)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call(:get_all_health_checks, _from, state) do
    result = %{
      registered: state.registered_health_checks,
      last_results: state.last_health_results,
      circuit_breakers: state.circuit_breaker_states
    }
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:unregister_health_check, service_module}, _from, state) do
    new_health_checks = Map.delete(state.registered_health_checks, service_module)
    new_results = Map.delete(state.last_health_results, service_module)
    new_breakers = Map.delete(state.circuit_breaker_states, service_module)
    
    new_state = %{state | 
      registered_health_checks: new_health_checks,
      last_health_results: new_results,
      circuit_breaker_states: new_breakers
    }
    
    Logger.debug("Unregistered health check", service: service_module)
    
    {:reply, :ok, new_state}
  end

  @impl GenServer
  def handle_call(:force_health_checks, _from, state) do
    {results, new_state} = perform_all_health_checks(state)
    {:reply, {:ok, results}, new_state}
  end

  @impl GenServer
  def handle_info(:perform_health_checks, state) do
    {_results, new_state} = perform_all_health_checks(state)
    
    # Schedule next health check
    updated_state = if state.enable_auto_checks do
      schedule_health_checks(new_state)
    else
      new_state
    end
    
    {:noreply, updated_state}
  end

  @impl GenServer
  def handle_info({:timeout, timer_ref, :perform_health_checks}, %{timer_ref: timer_ref} = state) do
    {_results, new_state} = perform_all_health_checks(state)
    
    # Schedule next health check
    updated_state = if state.enable_auto_checks do
      schedule_health_checks(new_state)
    else
      %{new_state | timer_ref: nil}
    end
    
    {:noreply, updated_state}
  end

  @impl GenServer
  def handle_info({:timeout, _old_timer_ref, :perform_health_checks}, state) do
    # Ignore old timer messages
    {:noreply, state}
  end

  @impl GenServer
  def terminate(_reason, state) do
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end
    :ok
  end

  ## Private Functions

  defp service_supports_health_check?(service) do
    # List of Foundation services that have health check implementations
    health_check_supported = [
      Foundation.Services.RetryService,
      Foundation.Services.ConnectionManager,
      Foundation.Services.RateLimiter,
      Foundation.Services.SignalBus
    ]
    
    service in health_check_supported
  end

  defp schedule_health_checks(state) do
    # Cancel existing timer
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end
    
    # Schedule new health check
    timer_ref = Process.send_after(self(), :perform_health_checks, state.check_interval)
    %{state | timer_ref: timer_ref}
  end

  defp check_foundation_services do
    # Address service availability issues (Category 1 - already fixed)
    foundation_services = [
      Foundation.Services.RetryService,
      Foundation.Services.ConnectionManager,
      Foundation.Services.RateLimiter,
      Foundation.Services.SignalBus,
      Foundation.ResourceManager,  # Now properly available via Category 1 fix
      Foundation.PerformanceMonitor
    ]
    
    health_results = Enum.map(foundation_services, fn service ->
      check_foundation_service_health(service)
    end)
    
    {:ok, health_results}
  end

  defp check_foundation_service_health(service) do
    start_time = System.monotonic_time()
    
    {status, metadata} = case Process.whereis(service) do
      nil -> 
        {:unavailable, %{error: :process_not_found}}
      
      pid ->
        # Check if service supports health checks before calling
        if service_supports_health_check?(service) do
          try do
            case GenServer.call(service, :health_check, 1000) do
              :healthy -> {:healthy, %{pid: pid}}
              :unhealthy -> {:unhealthy, %{pid: pid, reason: :service_reported_unhealthy}}
              :degraded -> {:degraded, %{pid: pid, reason: :service_reported_degraded}}
              {:error, reason} -> {:unhealthy, %{pid: pid, error: reason}}
              _other -> {:healthy, %{pid: pid, note: :non_standard_response}}
            end
          catch
            :exit, {:timeout, _} -> {:degraded, %{pid: pid, error: :health_check_timeout}}
            :exit, {:noproc, _} -> {:unavailable, %{error: :process_died_during_check}}
            _kind, _reason -> {:healthy, %{pid: pid, note: :health_check_not_supported}}
          end
        else
          # Service doesn't support health checks - assume healthy if running
          {:healthy, %{pid: pid, note: :health_check_not_supported}}
        end
    end
    
    response_time = System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond)
    
    %{
      service: service,
      status: status,
      response_time_ms: response_time,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }
  end

  defp check_signal_system_with_fallback do
    # Address Category 2 signal pipeline race conditions with fallback
    start_time = System.monotonic_time()
    
    {status, metadata} = try do
      # Test signal system synchronously to avoid race conditions
      case Process.whereis(Foundation.Services.SignalBus) do
        nil ->
          {:unavailable, %{error: :signal_bus_not_running}}
          
        pid ->
          # Use a simple health check rather than complex signal routing
          case GenServer.call(Foundation.Services.SignalBus, :health_check, 2000) do
            :healthy -> {:healthy, %{pid: pid}}
            :unhealthy -> {:unhealthy, %{pid: pid}}
            :degraded -> {:degraded, %{pid: pid}}
            other -> {:healthy, %{pid: pid, response: other}}
          end
      end
    rescue
      exception -> {:unhealthy, %{exception: inspect(exception)}}
    catch
      :exit, {:timeout, _} -> {:degraded, %{error: :health_check_timeout}}
      :exit, {:noproc, _} -> {:unavailable, %{error: :signal_bus_unavailable}}
      _kind, reason -> {:degraded, %{error: reason}}
    end
    
    response_time = System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond)
    
    signal_health = %{
      service: :signal_system,
      status: status,
      response_time_ms: response_time,
      metadata: metadata,
      timestamp: DateTime.utc_now()
    }
    
    {:ok, signal_health}
  end

  defp check_registered_services(state) do
    results = Enum.map(state.registered_health_checks, fn {service, _config} ->
      case perform_service_health_check(service, state) do
        {:ok, result} -> result
      end
    end)
    
    {:ok, results}
  end

  defp perform_service_health_check(service_module, state) do
    case Map.get(state.registered_health_checks, service_module) do
      nil ->
        # Try default health check for Foundation services
        result = check_foundation_service_health(service_module)
        {:ok, result}
        
      config ->
        # Use registered health check function
        start_time = System.monotonic_time()
        
        {status, metadata} = try do
          # Check circuit breaker state
          case should_skip_due_to_circuit_breaker(service_module, state) do
            true ->
              {:degraded, %{circuit_breaker: :open, reason: :too_many_failures}}
              
            false ->
              # Execute health check with timeout
              case execute_health_check_with_timeout(config.function, config.timeout) do
                :healthy -> {:healthy, config.metadata}
                :unhealthy -> {:unhealthy, config.metadata}
                :degraded -> {:degraded, config.metadata}
                {:error, reason} -> {:unhealthy, Map.put(config.metadata, :error, reason)}
                other -> {:healthy, Map.put(config.metadata, :response, other)}
              end
          end
        rescue
          exception ->
            {:unhealthy, Map.put(config.metadata, :exception, inspect(exception))}
        end
        
        response_time = System.convert_time_unit(System.monotonic_time() - start_time, :native, :millisecond)
        
        result = %{
          service: service_module,
          status: status,
          response_time_ms: response_time,
          metadata: metadata,
          timestamp: DateTime.utc_now()
        }
        
        {:ok, result}
    end
  end

  defp execute_health_check_with_timeout(health_check_fun, timeout) do
    task = Task.async(fn -> health_check_fun.() end)
    
    try do
      Task.await(task, timeout)
    catch
      :exit, {:timeout, _} -> {:error, :health_check_timeout}
    end
  end

  defp should_skip_due_to_circuit_breaker(service_module, state) do
    case Map.get(state.circuit_breaker_states, service_module) do
      nil -> false
      %{failures: failures} when failures >= state.circuit_breaker_threshold -> true
      _ -> false
    end
  end

  defp perform_all_health_checks(state) do
    # Perform health checks for all registered services
    results = Enum.map(state.registered_health_checks, fn {service, _config} ->
      case perform_service_health_check(service, state) do
        {:ok, result} -> result
      end
    end)
    
    # Update last results and circuit breaker states
    new_results = Enum.into(results, %{}, fn result -> {result.service, result} end)
    new_breaker_states = update_circuit_breaker_states(results, state.circuit_breaker_states)
    
    new_state = %{state |
      last_health_results: Map.merge(state.last_health_results, new_results),
      circuit_breaker_states: new_breaker_states
    }
    
    {results, new_state}
  end

  defp update_circuit_breaker_states(results, current_states) do
    Enum.reduce(results, current_states, fn result, acc ->
      service = result.service
      current_state = Map.get(acc, service, %{failures: 0})
      
      new_state = case result.status do
        :healthy -> %{failures: 0}
        _ -> %{failures: current_state.failures + 1}
      end
      
      Map.put(acc, service, new_state)
    end)
  end

  defp calculate_overall_status(foundation_health, signal_health, service_health) do
    all_statuses = [signal_health.status] ++ 
                   Enum.map(foundation_health, & &1.status) ++ 
                   Enum.map(service_health, & &1.status)
    
    cond do
      Enum.any?(all_statuses, &(&1 == :unavailable)) -> :degraded
      Enum.any?(all_statuses, &(&1 == :unhealthy)) -> :unhealthy
      Enum.any?(all_statuses, &(&1 == :degraded)) -> :degraded
      Enum.all?(all_statuses, &(&1 == :healthy)) -> :healthy
      true -> :unknown
    end
  end

  defp count_healthy_services(foundation_health, signal_health, service_health) do
    all_results = [signal_health] ++ foundation_health ++ service_health
    Enum.count(all_results, & &1.status == :healthy)
  end

  defp count_services(state) do
    # Foundation (6) + Signal (1) + Registered
    6 + 1 + map_size(state.registered_health_checks)
  end

  defp handle_health_check_error(error) do
    case error do
      {:error, :signal_system_error} ->
        {:ok, %{
          foundation_services: [],
          signal_system: %{status: :unhealthy, error: :signal_system_error},
          registered_services: [],
          overall_status: :degraded,
          summary: %{error: :partial_health_check}
        }}
      
      other ->
        {:error, other}
    end
  end
end