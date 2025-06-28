defmodule JidoFoundation.InfrastructureBridge do
  @moduledoc """
  Infrastructure protection bridge for Jido agents using Foundation services.
  
  This module enables Jido agents to seamlessly leverage Foundation's
  infrastructure protection services including circuit breakers, rate limiting,
  resource management, and fault tolerance patterns.
  
  Key capabilities:
  - Automatic protection for Jido agent operations
  - Agent-scoped infrastructure configuration
  - Protection policy inheritance and override
  - Performance monitoring and telemetry integration
  - Fault isolation and recovery coordination
  
  ## Usage Examples
  
      # Execute Jido action with Foundation protection
      {:ok, result} = InfrastructureBridge.execute_protected_action(
        MyApp.GenerateCodeAction,
        %{prompt: "Create a hello world function"},
        %{
          circuit_breaker: %{failure_threshold: 3},
          rate_limiter: %{requests_per_second: 5},
          timeout: 30_000
        }
      )
      
      # Configure agent-wide protection
      :ok = InfrastructureBridge.configure_agent_protection(
        :coder_agent,
        %{
          default_circuit_breaker: %{failure_threshold: 5, recovery_time: 30_000},
          default_rate_limiter: %{requests_per_second: 10, burst_size: 20},
          resource_limits: %{max_memory: 1024, max_cpu: 0.8}
        }
      )
  """

  alias Foundation.Infrastructure.AgentProtection
  alias Foundation.Infrastructure
  alias JidoFoundation.AgentBridge
  require Logger

  @type protection_spec :: %{
          circuit_breaker: map() | nil,
          rate_limiter: map() | nil,
          resource_limiter: map() | nil,
          timeout: pos_integer() | nil,
          retry: map() | nil
        }

  @type agent_protection_config :: %{
          agent_id: atom(),
          default_circuit_breaker: map(),
          default_rate_limiter: map(),
          default_resource_limits: map(),
          operation_overrides: %{atom() => protection_spec()},
          monitoring_enabled: boolean()
        }

  @type bridge_result :: {:ok, term()} | {:error, term()}

  @doc """
  Executes a Jido action with Foundation infrastructure protection.
  
  Wraps the execution of a Jido action with comprehensive Foundation
  protection including circuit breakers, rate limiting, and resource control.
  
  ## Parameters
  - `action_module`: The Jido action module to execute
  - `params`: Parameters for the action
  - `protection_spec`: Protection configuration
  - `opts`: Additional execution options
  
  ## Protection Options
  - `:circuit_breaker` - Circuit breaker configuration
  - `:rate_limiter` - Rate limiter configuration  
  - `:resource_limiter` - Resource limiting configuration
  - `:timeout` - Execution timeout in milliseconds
  - `:retry` - Retry configuration
  
  ## Returns
  - `{:ok, result}` if action succeeds
  - `{:error, reason}` if action fails or protection triggers
  """
  @spec execute_protected_action(module(), map(), protection_spec(), keyword()) :: bridge_result()
  def execute_protected_action(action_module, params, protection_spec, opts \\ []) do
    agent_id = Keyword.get(opts, :agent_id, :unknown)
    operation_type = Keyword.get(opts, :operation_type, action_module)
    correlation_id = Keyword.get(opts, :correlation_id, generate_correlation_id())

    # Build protection chain from spec
    with {:ok, protection_chain} <- build_protection_chain(protection_spec, agent_id, operation_type) do
      
      # Create protected operation
      protected_operation = fn ->
        execute_jido_action(action_module, params, opts)
      end
      
      # Execute with protection
      start_time = System.monotonic_time(:microsecond)
      
      result = execute_with_protection_chain(protected_operation, protection_chain, %{
        agent_id: agent_id,
        operation_type: operation_type,
        correlation_id: correlation_id
      })
      
      duration = System.monotonic_time(:microsecond) - start_time
      
      # Emit telemetry
      emit_protected_execution_telemetry(agent_id, operation_type, result, duration)
      
      result
    end
  end

  @doc """
  Configures protection policies for a specific Jido agent.
  
  Sets up default protection configurations that will be applied to all
  operations performed by the specified agent unless overridden.
  
  ## Parameters
  - `agent_id`: The agent identifier
  - `protection_config`: Agent protection configuration
  - `opts`: Configuration options
  
  ## Returns
  - `:ok` if configuration successful
  - `{:error, reason}` if configuration failed
  """
  @spec configure_agent_protection(atom(), agent_protection_config(), keyword()) :: bridge_result()
  def configure_agent_protection(agent_id, protection_config, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, :jido)
    
    with {:ok, validated_config} <- validate_protection_config(protection_config),
         :ok <- store_agent_protection_config(agent_id, validated_config),
         :ok <- update_agent_metadata_with_protection(namespace, agent_id, validated_config) do
      
      Logger.info("Agent protection configured", 
        agent_id: agent_id,
        circuit_breaker: Map.has_key?(validated_config, :default_circuit_breaker),
        rate_limiter: Map.has_key?(validated_config, :default_rate_limiter),
        resource_limits: Map.has_key?(validated_config, :default_resource_limits)
      )
      
      emit_protection_config_telemetry(agent_id, validated_config)
      :ok
    end
  end

  @doc """
  Gets current protection status for a Jido agent.
  
  ## Parameters
  - `agent_id`: The agent identifier
  - `opts`: Status query options
  
  ## Returns
  - `{:ok, status}` with protection status information
  - `{:error, reason}` if status query failed
  """
  @spec get_agent_protection_status(atom(), keyword()) :: bridge_result()
  def get_agent_protection_status(agent_id, opts \\ []) do
    namespace = Keyword.get(opts, :namespace, :jido)
    
    with {:ok, protection_config} <- get_agent_protection_config(agent_id),
         {:ok, runtime_status} <- get_protection_runtime_status(agent_id) do
      
      status = %{
        agent_id: agent_id,
        namespace: namespace,
        protection_config: protection_config,
        runtime_status: runtime_status,
        health: assess_protection_health(runtime_status),
        last_updated: DateTime.utc_now()
      }
      
      {:ok, status}
    end
  end

  @doc """
  Executes a Jido action with agent's default protection configuration.
  
  Uses the agent's configured default protection settings, with optional
  operation-specific overrides.
  
  ## Parameters
  - `agent_id`: The agent identifier
  - `action_module`: The Jido action module
  - `params`: Action parameters
  - `opts`: Execution options
  
  ## Returns
  - `{:ok, result}` if action succeeds
  - `{:error, reason}` if action fails or protection triggers
  """
  @spec execute_with_agent_protection(atom(), module(), map(), keyword()) :: bridge_result()
  def execute_with_agent_protection(agent_id, action_module, params, opts \\ []) do
    operation_override = Keyword.get(opts, :protection_override, %{})
    
    with {:ok, agent_protection} <- get_agent_protection_config(agent_id),
         {:ok, effective_protection} <- merge_protection_specs(agent_protection, operation_override, action_module) do
      
      execute_protected_action(
        action_module, 
        params, 
        effective_protection, 
        Keyword.put(opts, :agent_id, agent_id)
      )
    end
  end

  @doc """
  Manages agent resource allocation through Foundation infrastructure.
  
  ## Parameters
  - `agent_id`: The agent identifier
  - `resource_requests`: List of resource requests
  - `opts`: Resource management options
  
  ## Returns
  - `{:ok, allocations}` if resources allocated successfully
  - `{:error, reason}` if allocation failed
  """
  @spec manage_agent_resources(atom(), [map()], keyword()) :: bridge_result()
  def manage_agent_resources(agent_id, resource_requests, opts \\ []) do
    with {:ok, agent_info} <- get_agent_info(agent_id),
         {:ok, resource_requirements} <- extract_resource_requirements(agent_info),
         {:ok, allocations} <- allocate_resources_via_foundation(agent_id, resource_requests, resource_requirements) do
      
      Logger.debug("Resources allocated for agent", 
        agent_id: agent_id,
        allocations: length(allocations)
      )
      
      {:ok, allocations}
    end
  end

  @doc """
  Monitors agent operations and adjusts protection dynamically.
  
  ## Parameters
  - `agent_id`: The agent identifier
  - `monitoring_config`: Monitoring configuration
  
  ## Returns
  - `:ok` if monitoring started successfully
  - `{:error, reason}` if monitoring setup failed
  """
  @spec start_dynamic_protection_monitoring(atom(), map()) :: bridge_result()
  def start_dynamic_protection_monitoring(agent_id, monitoring_config \\ %{}) do
    with {:ok, monitor_pid} <- start_protection_monitor(agent_id, monitoring_config),
         :ok <- register_protection_monitor(agent_id, monitor_pid) do
      
      Logger.info("Dynamic protection monitoring started", 
        agent_id: agent_id,
        monitor_pid: monitor_pid
      )
      
      :ok
    end
  end

  @doc """
  Gets comprehensive protection metrics for an agent.
  
  ## Parameters
  - `agent_id`: The agent identifier
  - `time_window`: Time window for metrics in seconds
  
  ## Returns
  - `{:ok, metrics}` with protection metrics
  - `{:error, reason}` if metrics collection failed
  """
  @spec get_protection_metrics(atom(), pos_integer()) :: bridge_result()
  def get_protection_metrics(agent_id, time_window \\ 300) do
    with {:ok, foundation_metrics} <- AgentProtection.get_protection_metrics(agent_id, time_window),
         {:ok, bridge_metrics} <- get_bridge_specific_metrics(agent_id, time_window) do
      
      combined_metrics = Map.merge(foundation_metrics, %{
        bridge_metrics: bridge_metrics,
        integration_health: assess_integration_health(agent_id),
        recommendations: generate_protection_recommendations(foundation_metrics, bridge_metrics)
      })
      
      {:ok, combined_metrics}
    end
  end

  # Private implementation functions

  defp build_protection_chain(protection_spec, agent_id, operation_type) do
    protections = []
    
    # Add circuit breaker protection
    protections = if protection_spec.circuit_breaker do
      [build_circuit_breaker_protection(protection_spec.circuit_breaker, agent_id, operation_type) | protections]
    else
      protections
    end
    
    # Add rate limiter protection
    protections = if protection_spec.rate_limiter do
      [build_rate_limiter_protection(protection_spec.rate_limiter, agent_id, operation_type) | protections]
    else
      protections
    end
    
    # Add resource limiter protection
    protections = if protection_spec.resource_limiter do
      [build_resource_limiter_protection(protection_spec.resource_limiter, agent_id) | protections]
    else
      protections
    end
    
    # Add timeout protection
    protections = if protection_spec.timeout do
      [build_timeout_protection(protection_spec.timeout) | protections]
    else
      protections
    end
    
    # Add retry protection
    protections = if protection_spec.retry do
      [build_retry_protection(protection_spec.retry, agent_id, operation_type) | protections]
    else
      protections
    end
    
    {:ok, Enum.reverse(protections)}
  end

  defp build_circuit_breaker_protection(config, agent_id, operation_type) do
    fn operation ->
      AgentProtection.circuit_breaker_protect(agent_id, operation_type, operation, config)
    end
  end

  defp build_rate_limiter_protection(config, agent_id, operation_type) do
    fn operation ->
      AgentProtection.rate_limit_protect(agent_id, operation_type, operation, config)
    end
  end

  defp build_resource_limiter_protection(config, agent_id) do
    fn operation ->
      AgentProtection.resource_limit_protect(agent_id, operation, config)
    end
  end

  defp build_timeout_protection(timeout_ms) do
    fn operation ->
      try do
        Task.await(Task.async(operation), timeout_ms)
      catch
        :exit, {:timeout, _} -> {:error, :timeout}
      end
    end
  end

  defp build_retry_protection(config, agent_id, operation_type) do
    max_retries = Map.get(config, :max_retries, 3)
    delay = Map.get(config, :delay_ms, 1000)
    
    fn operation ->
      retry_with_backoff(operation, max_retries, delay, agent_id, operation_type)
    end
  end

  defp execute_with_protection_chain(operation, [], _context) do
    # No more protection layers, execute the operation
    operation.()
  end

  defp execute_with_protection_chain(operation, [protection | rest], context) do
    # Apply current protection layer and continue with remaining protections
    protected_operation = fn ->
      execute_with_protection_chain(operation, rest, context)
    end
    
    protection.(protected_operation)
  end

  defp execute_jido_action(action_module, params, opts) do
    # Execute the Jido action
    # This would integrate with Jido.Exec in a real implementation
    try do
      case apply(action_module, :run, [params, %{}]) do
        {:ok, result} -> {:ok, result}
        {:error, reason} -> {:error, reason}
        result -> {:ok, result}
      end
    rescue
      error ->
        Logger.error("Jido action execution failed with exception",
          action: action_module,
          error: inspect(error)
        )
        {:error, {:action_exception, error}}
    end
  end

  defp retry_with_backoff(operation, 0, _delay, agent_id, operation_type) do
    Logger.error("Operation failed after all retries",
      agent_id: agent_id,
      operation: operation_type
    )
    {:error, :max_retries_exceeded}
  end

  defp retry_with_backoff(operation, retries_left, delay, agent_id, operation_type) do
    case operation.() do
      {:ok, result} -> {:ok, result}
      {:error, reason} ->
        Logger.warning("Operation failed, retrying",
          agent_id: agent_id,
          operation: operation_type,
          retries_left: retries_left - 1,
          reason: reason
        )
        
        :timer.sleep(delay)
        retry_with_backoff(operation, retries_left - 1, delay * 2, agent_id, operation_type)
    end
  end

  defp validate_protection_config(config) do
    # Validate protection configuration structure
    required_fields = [:agent_id]
    
    case check_required_fields(config, required_fields) do
      :ok -> {:ok, config}
      error -> error
    end
  end

  defp check_required_fields(config, required_fields) do
    missing = Enum.reject(required_fields, &Map.has_key?(config, &1))
    
    case missing do
      [] -> :ok
      fields -> {:error, {:missing_required_fields, fields}}
    end
  end

  defp merge_protection_specs(agent_protection, operation_override, action_module) do
    # Get operation-specific overrides
    operation_overrides = Map.get(agent_protection, :operation_overrides, %{})
    specific_override = Map.get(operation_overrides, action_module, %{})
    
    # Merge configurations with priority: operation_override > specific_override > defaults
    merged_spec = %{}
    
    merged_spec = merge_circuit_breaker_config(merged_spec, agent_protection, specific_override, operation_override)
    merged_spec = merge_rate_limiter_config(merged_spec, agent_protection, specific_override, operation_override)
    merged_spec = merge_resource_limiter_config(merged_spec, agent_protection, specific_override, operation_override)
    merged_spec = merge_timeout_config(merged_spec, agent_protection, specific_override, operation_override)
    merged_spec = merge_retry_config(merged_spec, agent_protection, specific_override, operation_override)
    
    {:ok, merged_spec}
  end

  defp merge_circuit_breaker_config(spec, agent, specific, override) do
    cb_config = override[:circuit_breaker] || specific[:circuit_breaker] || agent[:default_circuit_breaker]
    if cb_config, do: Map.put(spec, :circuit_breaker, cb_config), else: spec
  end

  defp merge_rate_limiter_config(spec, agent, specific, override) do
    rl_config = override[:rate_limiter] || specific[:rate_limiter] || agent[:default_rate_limiter]
    if rl_config, do: Map.put(spec, :rate_limiter, rl_config), else: spec
  end

  defp merge_resource_limiter_config(spec, agent, specific, override) do
    resource_config = override[:resource_limiter] || specific[:resource_limiter] || agent[:default_resource_limits]
    if resource_config, do: Map.put(spec, :resource_limiter, resource_config), else: spec
  end

  defp merge_timeout_config(spec, agent, specific, override) do
    timeout = override[:timeout] || specific[:timeout] || agent[:default_timeout]
    if timeout, do: Map.put(spec, :timeout, timeout), else: spec
  end

  defp merge_retry_config(spec, agent, specific, override) do
    retry_config = override[:retry] || specific[:retry] || agent[:default_retry]
    if retry_config, do: Map.put(spec, :retry, retry_config), else: spec
  end

  defp emit_protected_execution_telemetry(agent_id, operation_type, result, duration) do
    status = case result do
      {:ok, _} -> :success
      {:error, _} -> :error
    end

    :telemetry.execute(
      [:jido_foundation, :infrastructure_bridge, :protected_execution],
      %{duration: duration},
      %{
        agent_id: agent_id,
        operation_type: operation_type,
        status: status
      }
    )
  end

  defp emit_protection_config_telemetry(agent_id, config) do
    :telemetry.execute(
      [:jido_foundation, :infrastructure_bridge, :protection_configured],
      %{count: 1},
      %{
        agent_id: agent_id,
        has_circuit_breaker: Map.has_key?(config, :default_circuit_breaker),
        has_rate_limiter: Map.has_key?(config, :default_rate_limiter),
        has_resource_limits: Map.has_key?(config, :default_resource_limits)
      }
    )
  end

  defp generate_correlation_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16()
  end

  # Placeholder implementations for complex functions

  defp store_agent_protection_config(_agent_id, _config), do: :ok
  defp update_agent_metadata_with_protection(_namespace, _agent_id, _config), do: :ok
  defp get_agent_protection_config(_agent_id), do: {:ok, %{}}
  defp get_protection_runtime_status(_agent_id), do: {:ok, %{}}
  defp assess_protection_health(_runtime_status), do: :healthy
  defp get_agent_info(_agent_id), do: {:ok, %{}}
  defp extract_resource_requirements(_agent_info), do: {:ok, %{}}
  defp allocate_resources_via_foundation(_agent_id, _requests, _requirements), do: {:ok, []}
  defp start_protection_monitor(_agent_id, _config), do: {:ok, spawn(fn -> :ok end)}
  defp register_protection_monitor(_agent_id, _pid), do: :ok
  defp get_bridge_specific_metrics(_agent_id, _time_window), do: {:ok, %{}}
  defp assess_integration_health(_agent_id), do: :healthy
  defp generate_protection_recommendations(_foundation_metrics, _bridge_metrics), do: []
end
