defmodule Foundation.Infrastructure.AgentRateLimiter do
  @moduledoc """
  Agent-aware rate limiting with capability and resource-based throttling.
  
  Extends traditional rate limiting to include agent context, allowing for
  sophisticated throttling based on agent health, capabilities, resource usage,
  and coordination state. Designed for multi-agent environments where different
  agents may have different rate limiting requirements.
  
  ## Agent Context Features
  
  - **Capability-Based Limits**: Different rate limits per agent capability
  - **Resource-Aware Throttling**: Rate limits adjust based on agent resource usage  
  - **Health-Based Adjustment**: Rate limits decrease for unhealthy agents
  - **Coordination Integration**: Rate limiting participates in agent coordination
  - **Dynamic Thresholds**: Rate limits adapt to current system load
  
  ## Usage
  
      # Start agent-aware rate limiter
      {:ok, _pid} = AgentRateLimiter.start_link([
        namespace: :production,
        default_limits: %{
          inference: {100, 60_000},  # 100 requests per minute
          training: {10, 60_000},    # 10 requests per minute
          coordination: {1000, 60_000} # 1000 coordination events per minute
        }
      ])
      
      # Check rate limit with agent context
      case AgentRateLimiter.check_rate_with_agent(
        :ml_agent_1,
        :inference,
        %{model: "gpt-4", complexity: :high}
      ) do
        :ok -> proceed_with_inference()
        {:error, error} -> handle_rate_limit(error)
      end
      
      # Execute operation with rate limiting
      result = AgentRateLimiter.execute_with_limit(
        :ml_agent_1,
        :inference,
        fn -> perform_ml_inference() end
      )
  """
  
  use GenServer
  require Logger
  
  alias Foundation.ProcessRegistry
  alias Foundation.Telemetry
  alias Foundation.Types.Error
  
  @type agent_id :: atom() | String.t()
  @type capability :: atom()
  @type operation_type :: atom()
  @type rate_limit :: {pos_integer(), pos_integer()}  # {count, window_ms}
  @type resource_usage :: %{
    memory: float(),
    cpu: float(),
    connections: non_neg_integer()
  }
  
  @type agent_context :: %{
    agent_id: agent_id(),
    capability: capability(),
    health: :healthy | :degraded | :unhealthy,
    resource_usage: resource_usage()
  }
  
  @type rate_limiter_options :: [
    namespace: atom(),
    default_limits: %{capability() => rate_limit()},
    adaptive_scaling: boolean(),
    health_adjustment_factor: float(),
    resource_threshold_scaling: boolean()
  ]
  
  defstruct [
    :namespace,
    :default_limits,
    :adaptive_scaling,
    :health_adjustment_factor,
    :resource_threshold_scaling,
    :rate_buckets,
    :agent_contexts,
    :last_cleanup
  ]
  
  @type t :: %__MODULE__{
    namespace: atom(),
    default_limits: map(),
    adaptive_scaling: boolean(),
    health_adjustment_factor: float(),
    resource_threshold_scaling: boolean(),
    rate_buckets: :ets.tid(),
    agent_contexts: :ets.tid(),
    last_cleanup: DateTime.t()
  }
  
  # Default rate limits per capability
  @default_capability_limits %{
    inference: {100, 60_000},      # 100 per minute
    training: {10, 60_000},        # 10 per minute  
    coordination: {1000, 60_000},  # 1000 per minute
    monitoring: {500, 60_000},     # 500 per minute
    general: {200, 60_000}         # 200 per minute
  }
  
  # Public API
  
  @doc """
  Start the agent-aware rate limiter.
  """
  @spec start_link(rate_limiter_options()) :: {:ok, pid()} | {:error, term()}
  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end
  
  @doc """
  Check if an agent can perform an operation based on rate limits.
  
  Takes into account the agent's current health, resource usage,
  and capability-specific rate limits.
  
  ## Parameters
  - `agent_id`: The agent requesting to perform the operation
  - `operation_type`: Type of operation (maps to capability)
  - `metadata`: Additional context for the operation
  
  ## Examples
  
      case AgentRateLimiter.check_rate_with_agent(:ml_agent_1, :inference, %{}) do
        :ok -> proceed()
        {:error, error} -> handle_limit(error)
      end
  """
  @spec check_rate_with_agent(agent_id(), operation_type(), map()) :: 
    :ok | {:error, Error.t()}
  def check_rate_with_agent(agent_id, operation_type, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:check_rate, agent_id, operation_type, metadata}, 5_000)
  rescue
    error -> {:error, rate_limiter_error("check_rate failed", error)}
  catch
    :exit, {:timeout, _} -> {:error, rate_limiter_timeout_error()}
    :exit, {:noproc, _} -> {:error, rate_limiter_not_running_error()}
  end
  
  @doc """
  Execute an operation with rate limiting protection.
  
  Combines rate limit checking with operation execution,
  providing automatic backpressure based on agent context.
  """
  @spec execute_with_limit(agent_id(), operation_type(), (-> any()), map()) :: 
    {:ok, any()} | {:error, Error.t()}
  def execute_with_limit(agent_id, operation_type, operation, metadata \\ %{}) 
      when is_function(operation, 0) do
    
    case check_rate_with_agent(agent_id, operation_type, metadata) do
      :ok ->
        try do
          result = operation.()
          
          # Emit success telemetry
          Telemetry.emit_counter(
            [:foundation, :infrastructure, :agent_rate_limiter, :operation_success],
            Map.merge(metadata, %{agent_id: agent_id, operation_type: operation_type})
          )
          
          {:ok, result}
        rescue
          error ->
            operation_error = Error.new(
              code: 6020,
              error_type: :rate_limited_operation_failed,
              message: "Rate limited operation failed: #{inspect(error)}",
              severity: :medium,
              context: %{
                agent_id: agent_id,
                operation_type: operation_type,
                error: error
              }
            )
            
            {:error, operation_error}
        end
      
      {:error, _} = error ->
        error
    end
  end
  
  @doc """
  Update the rate limits for a specific agent capability.
  
  Allows dynamic adjustment of rate limits based on system load,
  agent performance, or operational requirements.
  """
  @spec update_agent_limits(agent_id(), capability(), rate_limit()) :: :ok | {:error, term()}
  def update_agent_limits(agent_id, capability, {limit, window_ms}) do
    GenServer.call(__MODULE__, {:update_limits, agent_id, capability, limit, window_ms})
  rescue
    error -> {:error, rate_limiter_error("update_limits failed", error)}
  end
  
  @doc """
  Get current rate limiting status for an agent.
  
  Returns detailed information about current usage, limits,
  and agent-specific adjustments.
  """
  @spec get_agent_status(agent_id()) :: {:ok, map()} | {:error, Error.t()}
  def get_agent_status(agent_id) do
    GenServer.call(__MODULE__, {:get_status, agent_id})
  rescue
    error -> {:error, rate_limiter_error("get_status failed", error)}
  end
  
  @doc """
  Reset rate limiting buckets for an agent.
  
  Clears all current rate limiting state for the specified agent,
  useful for testing or manual intervention scenarios.
  """
  @spec reset_agent_buckets(agent_id()) :: :ok | {:error, term()}
  def reset_agent_buckets(agent_id) do
    GenServer.call(__MODULE__, {:reset_buckets, agent_id})
  rescue
    error -> {:error, rate_limiter_error("reset_buckets failed", error)}
  end
  
  # GenServer Implementation
  
  @impl GenServer
  def init(options) do
    namespace = Keyword.get(options, :namespace, :foundation)
    default_limits = Keyword.get(options, :default_limits, @default_capability_limits)
    adaptive_scaling = Keyword.get(options, :adaptive_scaling, true)
    health_adjustment_factor = Keyword.get(options, :health_adjustment_factor, 0.5)
    resource_threshold_scaling = Keyword.get(options, :resource_threshold_scaling, true)
    
    # Create ETS tables for rate buckets and agent contexts
    rate_buckets = :ets.new(:agent_rate_buckets, [
      :set, :private, {:write_concurrency, true}, {:read_concurrency, true}
    ])
    
    agent_contexts = :ets.new(:agent_contexts, [
      :set, :private, {:write_concurrency, true}, {:read_concurrency, true}
    ])
    
    state = %__MODULE__{
      namespace: namespace,
      default_limits: default_limits,
      adaptive_scaling: adaptive_scaling,
      health_adjustment_factor: health_adjustment_factor,
      resource_threshold_scaling: resource_threshold_scaling,
      rate_buckets: rate_buckets,
      agent_contexts: agent_contexts,
      last_cleanup: DateTime.utc_now()
    }
    
    # Register with ProcessRegistry
    case ProcessRegistry.register(namespace, __MODULE__, self(), %{
      type: :rate_limiter,
      capabilities: Map.keys(default_limits),
      health: :healthy
    }) do
      :ok ->
        # Schedule periodic cleanup
        schedule_cleanup()
        
        Telemetry.emit_counter(
          [:foundation, :infrastructure, :agent_rate_limiter, :started],
          %{namespace: namespace, capabilities: Map.keys(default_limits)}
        )
        
        {:ok, state}
      
      {:error, reason} ->
        {:stop, {:registration_failed, reason}}
    end
  end
  
  @impl GenServer
  def handle_call({:check_rate, agent_id, operation_type, metadata}, _from, state) do
    # Get or update agent context
    agent_context = get_or_update_agent_context(agent_id, state)
    
    # Determine effective rate limit for this agent/operation
    effective_limit = calculate_effective_limit(agent_context, operation_type, state)
    
    # Check current usage against limit
    result = check_rate_bucket(agent_id, operation_type, effective_limit, state)
    
    # Emit telemetry
    emit_rate_check_telemetry(result, agent_id, operation_type, metadata, agent_context)
    
    {:reply, result, state}
  end
  
  @impl GenServer
  def handle_call({:update_limits, agent_id, capability, limit, window_ms}, _from, state) do
    # Store agent-specific limit override
    :ets.insert(state.agent_contexts, {
      {agent_id, :limit_override, capability}, 
      {limit, window_ms}
    })
    
    Telemetry.emit_counter(
      [:foundation, :infrastructure, :agent_rate_limiter, :limits_updated],
      %{agent_id: agent_id, capability: capability, limit: limit}
    )
    
    {:reply, :ok, state}
  end
  
  @impl GenServer
  def handle_call({:get_status, agent_id}, _from, state) do
    status = build_agent_status(agent_id, state)
    {:reply, {:ok, status}, state}
  end
  
  @impl GenServer
  def handle_call({:reset_buckets, agent_id}, _from, state) do
    # Remove all buckets for this agent
    match_pattern = {{agent_id, :_, :_}, :_}
    :ets.match_delete(state.rate_buckets, match_pattern)
    
    Telemetry.emit_counter(
      [:foundation, :infrastructure, :agent_rate_limiter, :buckets_reset],
      %{agent_id: agent_id}
    )
    
    {:reply, :ok, state}
  end
  
  @impl GenServer
  def handle_info(:cleanup_buckets, state) do
    new_state = perform_bucket_cleanup(state)
    schedule_cleanup()
    {:noreply, new_state}
  end
  
  @impl GenServer
  def handle_info(_message, state) do
    {:noreply, state}
  end
  
  # Private Implementation
  
  defp get_or_update_agent_context(agent_id, state) do
    # Try to get current agent context from ProcessRegistry
    case ProcessRegistry.lookup(state.namespace, agent_id) do
      {:ok, _pid, metadata} ->
        agent_context = %{
          agent_id: agent_id,
          capability: Map.get(metadata, :capability, :general),
          health: Map.get(metadata, :health, :healthy),
          resource_usage: Map.get(metadata, :resources, %{})
        }
        
        # Cache the context
        :ets.insert(state.agent_contexts, {agent_id, agent_context})
        agent_context
      
      :error ->
        # Use cached context or defaults
        case :ets.lookup(state.agent_contexts, agent_id) do
          [{^agent_id, cached_context}] -> cached_context
          [] -> 
            default_context = %{
              agent_id: agent_id,
              capability: :general,
              health: :healthy,
              resource_usage: %{}
            }
            :ets.insert(state.agent_contexts, {agent_id, default_context})
            default_context
        end
    end
  end
  
  defp calculate_effective_limit(agent_context, operation_type, state) do
    # Start with base limit for the operation type
    base_limit = get_base_limit(agent_context.capability, operation_type, state)
    
    # Apply health-based adjustments
    health_adjusted = apply_health_adjustment(base_limit, agent_context.health, state)
    
    # Apply resource-based adjustments
    resource_adjusted = apply_resource_adjustment(health_adjusted, agent_context.resource_usage, state)
    
    resource_adjusted
  end
  
  defp get_base_limit(capability, operation_type, state) do
    # Check for agent-specific overrides first
    override_key = {capability, :limit_override, operation_type}
    
    case :ets.lookup(state.agent_contexts, override_key) do
      [{^override_key, limit}] -> limit
      [] ->
        # Use default limits
        Map.get(state.default_limits, operation_type, 
          Map.get(state.default_limits, capability, {100, 60_000}))
    end
  end
  
  defp apply_health_adjustment({limit, window}, :healthy, _state), do: {limit, window}
  defp apply_health_adjustment({limit, window}, :degraded, state) do
    if state.adaptive_scaling do
      adjusted_limit = trunc(limit * 0.7)  # 70% of normal limit
      {max(adjusted_limit, 1), window}
    else
      {limit, window}
    end
  end
  defp apply_health_adjustment({limit, window}, :unhealthy, state) do
    if state.adaptive_scaling do
      adjusted_limit = trunc(limit * state.health_adjustment_factor)
      {max(adjusted_limit, 1), window}
    else
      {limit, window}
    end
  end
  
  defp apply_resource_adjustment({limit, window}, resource_usage, state) do
    if state.resource_threshold_scaling and map_size(resource_usage) > 0 do
      # Calculate resource pressure (0.0 to 1.0)
      memory_pressure = Map.get(resource_usage, :memory, 0.0)
      cpu_pressure = Map.get(resource_usage, :cpu, 0.0)
      max_pressure = max(memory_pressure, cpu_pressure)
      
      if max_pressure > 0.8 do
        # Reduce limit when under resource pressure
        adjustment_factor = 1.0 - (max_pressure - 0.8) * 2  # Scale from 1.0 to 0.6
        adjusted_limit = trunc(limit * adjustment_factor)
        {max(adjusted_limit, 1), window}
      else
        {limit, window}
      end
    else
      {limit, window}
    end
  end
  
  defp check_rate_bucket(agent_id, operation_type, {limit, window_ms}, state) do
    current_time = System.system_time(:millisecond)
    window_start = div(current_time, window_ms) * window_ms
    bucket_key = {agent_id, operation_type, window_start}
    
    case :ets.lookup(state.rate_buckets, bucket_key) do
      [{^bucket_key, current_count}] ->
        if current_count >= limit do
          rate_limit_exceeded_error(agent_id, operation_type, current_count, limit)
        else
          # Increment counter
          :ets.update_counter(state.rate_buckets, bucket_key, {2, 1})
          :ok
        end
      
      [] ->
        # First request in this window
        :ets.insert(state.rate_buckets, {bucket_key, 1})
        :ok
    end
  end
  
  defp build_agent_status(agent_id, state) do
    # Get current buckets for this agent
    match_pattern = {{agent_id, :_, :_}, :_}
    buckets = :ets.match(state.rate_buckets, match_pattern)
    
    # Get agent context
    agent_context = case :ets.lookup(state.agent_contexts, agent_id) do
      [{^agent_id, context}] -> context
      [] -> %{agent_id: agent_id, status: :not_found}
    end
    
    %{
      agent_id: agent_id,
      agent_context: agent_context,
      active_buckets: length(buckets),
      current_usage: calculate_current_usage(buckets),
      effective_limits: get_all_effective_limits(agent_context, state)
    }
  end
  
  defp calculate_current_usage(buckets) do
    buckets
    |> Enum.map(fn [_key, count] -> count end)
    |> Enum.sum()
  end
  
  defp get_all_effective_limits(agent_context, state) do
    state.default_limits
    |> Enum.map(fn {operation_type, _base_limit} ->
      effective_limit = calculate_effective_limit(agent_context, operation_type, state)
      {operation_type, effective_limit}
    end)
    |> Enum.into(%{})
  end
  
  defp perform_bucket_cleanup(state) do
    current_time = System.system_time(:millisecond)
    cutoff_time = current_time - (2 * 60 * 60 * 1000)  # 2 hours ago
    
    # Delete old buckets
    match_spec = [
      {{{:_, :_, :"$1"}, :_}, [{:<, :"$1", cutoff_time}], [true]}
    ]
    deleted_count = :ets.select_delete(state.rate_buckets, match_spec)
    
    if deleted_count > 0 do
      Telemetry.emit_counter(
        [:foundation, :infrastructure, :agent_rate_limiter, :buckets_cleaned],
        %{deleted_count: deleted_count}
      )
    end
    
    %{state | last_cleanup: DateTime.utc_now()}
  end
  
  defp schedule_cleanup do
    # Clean up old buckets every 10 minutes
    Process.send_after(self(), :cleanup_buckets, 10 * 60 * 1000)
  end
  
  defp emit_rate_check_telemetry(result, agent_id, operation_type, metadata, agent_context) do
    telemetry_metadata = Map.merge(metadata, %{
      agent_id: agent_id,
      operation_type: operation_type,
      agent_health: agent_context.health,
      agent_capability: agent_context.capability
    })
    
    case result do
      :ok ->
        Telemetry.emit_counter(
          [:foundation, :infrastructure, :agent_rate_limiter, :request_allowed],
          telemetry_metadata
        )
      
      {:error, _} ->
        Telemetry.emit_counter(
          [:foundation, :infrastructure, :agent_rate_limiter, :request_denied],
          telemetry_metadata
        )
    end
  end
  
  # Error Helper Functions
  
  defp rate_limit_exceeded_error(agent_id, operation_type, current_count, limit) do
    {:error, Error.new(
      code: 6010,
      error_type: :agent_rate_limit_exceeded,
      message: "Rate limit exceeded for agent #{agent_id} operation #{operation_type}: #{current_count}/#{limit}",
      severity: :medium,
      context: %{
        agent_id: agent_id,
        operation_type: operation_type,
        current_count: current_count,
        limit: limit
      },
      retry_strategy: :fixed_delay
    )}
  end
  
  defp rate_limiter_error(message, error) do
    Error.new(
      code: 6011,
      error_type: :rate_limiter_error,
      message: "Rate limiter error: #{message}",
      severity: :medium,
      context: %{error: error}
    )
  end
  
  defp rate_limiter_timeout_error do
    Error.new(
      code: 6012,
      error_type: :rate_limiter_timeout,
      message: "Rate limiter operation timed out",
      severity: :medium,
      context: %{}
    )
  end
  
  defp rate_limiter_not_running_error do
    Error.new(
      code: 6013,
      error_type: :rate_limiter_not_running,
      message: "Rate limiter service is not running",
      severity: :high,
      context: %{}
    )
  end
end