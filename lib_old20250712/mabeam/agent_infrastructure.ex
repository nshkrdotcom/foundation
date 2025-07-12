defmodule MABEAM.AgentInfrastructure do
  @moduledoc """
  GenServer-based infrastructure backend for multi-agent systems.

  Implements the Foundation.Infrastructure protocol with agent-specific
  optimizations for circuit breakers, rate limiting, and resource monitoring.

  ## Features

  - **Circuit Breakers**: Protect against cascading failures
  - **Rate Limiting**: Token bucket and sliding window strategies
  - **Resource Monitoring**: Track and alert on resource usage
  - **Automatic Recovery**: Self-healing circuit breakers

  ## Implementation Details

  All infrastructure state is managed through ETS tables for performance,
  with the GenServer process handling state transitions and monitoring.
  """

  use GenServer
  require Logger

  defstruct circuit_table: nil,
            rate_limiter_table: nil,
            resource_table: nil,
            infrastructure_id: nil,
            monitors: %{},
            cleanup_interval: 60_000,
            cleanup_timer: nil

  # Default configurations
  @default_circuit_config %{
    failure_threshold: 5,
    timeout: 60_000,
    success_threshold: 3
  }

  # --- OTP Lifecycle ---

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  def init(opts) do
    # Generate unique infrastructure ID for table names
    infrastructure_id = Keyword.get(opts, :id, :default)
    cleanup_interval = Keyword.get(opts, :cleanup_interval, 60_000)

    # Create unique table names for this instance
    circuit_table_name = :"agent_circuit_#{infrastructure_id}"
    rate_limiter_table_name = :"agent_rate_limiter_#{infrastructure_id}"
    resource_table_name = :"agent_resource_#{infrastructure_id}"

    # Clean up any existing tables from previous runs
    [circuit_table_name, rate_limiter_table_name, resource_table_name]
    |> Enum.each(&safe_ets_delete/1)

    # Tables are private to this process
    table_opts = [:private, read_concurrency: true, write_concurrency: true]

    state = %__MODULE__{
      circuit_table: :ets.new(circuit_table_name, [:set | table_opts]),
      rate_limiter_table: :ets.new(rate_limiter_table_name, [:set | table_opts]),
      resource_table: :ets.new(resource_table_name, [:set | table_opts]),
      infrastructure_id: infrastructure_id,
      monitors: %{},
      cleanup_interval: cleanup_interval
    }

    # Schedule periodic cleanup
    cleanup_timer = Process.send_after(self(), :cleanup_expired, cleanup_interval)

    Logger.info("MABEAM.AgentInfrastructure (#{infrastructure_id}) started")

    {:ok, %{state | cleanup_timer: cleanup_timer}}
  end

  def terminate(_reason, state) do
    Logger.info("MABEAM.AgentInfrastructure (#{state.infrastructure_id}) terminating")

    # Cancel cleanup timer
    if state.cleanup_timer do
      Process.cancel_timer(state.cleanup_timer)
    end

    # Cancel all monitors
    Enum.each(state.monitors, fn {_ref, _resource_id} ->
      # Cleanup logic would go here
      :ok
    end)

    # Clean up ETS tables
    safe_ets_delete(state.circuit_table)
    safe_ets_delete(state.rate_limiter_table)
    safe_ets_delete(state.resource_table)
    :ok
  end

  defp safe_ets_delete(table) do
    :ets.delete(table)
  rescue
    ArgumentError -> :ok
  end

  # --- Circuit Breaker Implementation ---

  def handle_call({:register_circuit_breaker, service_id, config}, _from, state) do
    case :ets.lookup(state.circuit_table, service_id) do
      [] ->
        validated_config = Map.merge(@default_circuit_config, config)

        circuit_data = %{
          service_id: service_id,
          state: :closed,
          failure_count: 0,
          success_count: 0,
          last_failure_time: nil,
          config: validated_config
        }

        :ets.insert(state.circuit_table, {service_id, circuit_data})

        Logger.debug("Registered circuit breaker for service #{inspect(service_id)}")

        {:reply, :ok, state}

      _ ->
        {:reply, {:error, :already_exists}, state}
    end
  end

  def handle_call({:execute_protected, service_id, function, context}, _from, state) do
    case :ets.lookup(state.circuit_table, service_id) do
      [{^service_id, circuit_data}] ->
        case circuit_data.state do
          :open ->
            handle_open_circuit(service_id, function, context, circuit_data, state)

          :closed ->
            execute_and_track(service_id, function, context, circuit_data, state)

          :half_open ->
            execute_and_track(service_id, function, context, circuit_data, state)
        end

      [] ->
        {:reply, {:error, :service_not_found}, state}
    end
  end

  def handle_call({:get_circuit_status, service_id}, _from, state) do
    case :ets.lookup(state.circuit_table, service_id) do
      [{^service_id, circuit_data}] ->
        {:reply, {:ok, circuit_data.state}, state}

      [] ->
        {:reply, {:error, :service_not_found}, state}
    end
  end

  # --- Rate Limiting Implementation ---

  def handle_call({:setup_rate_limiter, limiter_id, config}, _from, state) do
    case :ets.lookup(state.rate_limiter_table, limiter_id) do
      [] ->
        case validate_rate_limiter_config(config) do
          {:ok, validated_config} ->
            limiter_data = initialize_rate_limiter(limiter_id, validated_config)
            :ets.insert(state.rate_limiter_table, {limiter_id, limiter_data})

            Logger.debug(
              "Setup rate limiter #{inspect(limiter_id)} with config #{inspect(validated_config)}"
            )

            {:reply, :ok, state}

          {:error, reason} ->
            {:reply, {:error, {:invalid_config, reason}}, state}
        end

      _ ->
        {:reply, {:error, :already_exists}, state}
    end
  end

  def handle_call({:check_rate_limit, limiter_id, identifier}, _from, state) do
    case :ets.lookup(state.rate_limiter_table, limiter_id) do
      [{^limiter_id, limiter_data}] ->
        {allowed, updated_limiter} = check_and_update_rate_limit(limiter_data, identifier)
        :ets.insert(state.rate_limiter_table, {limiter_id, updated_limiter})

        if allowed do
          {:reply, :ok, state}
        else
          {:reply, {:error, :rate_limited}, state}
        end

      [] ->
        {:reply, {:error, :limiter_not_found}, state}
    end
  end

  def handle_call({:get_rate_limit_status, limiter_id, identifier}, _from, state) do
    case :ets.lookup(state.rate_limiter_table, limiter_id) do
      [{^limiter_id, limiter_data}] ->
        status = get_identifier_status(limiter_data, identifier)
        {:reply, {:ok, status}, state}

      [] ->
        {:reply, {:error, :limiter_not_found}, state}
    end
  end

  # --- Resource Monitoring Implementation ---

  def handle_call({:monitor_resource, resource_id, config}, _from, state) do
    case validate_resource_config(config) do
      {:ok, validated_config} ->
        resource_data = %{
          resource_id: resource_id,
          config: validated_config,
          current_usage: %{},
          last_check: System.monotonic_time(:millisecond)
        }

        :ets.insert(state.resource_table, {resource_id, resource_data})

        # Schedule monitoring
        check_interval = Map.get(validated_config, :check_interval, 30_000)
        Process.send_after(self(), {:check_resource, resource_id}, check_interval)

        Logger.debug("Started monitoring resource #{inspect(resource_id)}")

        {:reply, :ok, state}

      {:error, reason} ->
        {:reply, {:error, {:invalid_config, reason}}, state}
    end
  end

  def handle_call({:get_resource_usage, resource_id}, _from, state) do
    case :ets.lookup(state.resource_table, resource_id) do
      [{^resource_id, resource_data}] ->
        # Update with current usage
        current_usage = measure_resource_usage(resource_id)
        updated_data = %{resource_data | current_usage: current_usage}
        :ets.insert(state.resource_table, {resource_id, updated_data})

        {:reply, {:ok, current_usage}, state}

      [] ->
        {:reply, {:error, :resource_not_found}, state}
    end
  end

  # --- Periodic Tasks ---

  def handle_info(:cleanup_expired, state) do
    # Clean up stale rate limiter entries
    cleanup_rate_limiters(state.rate_limiter_table)

    # Schedule next cleanup
    cleanup_timer = Process.send_after(self(), :cleanup_expired, state.cleanup_interval)

    {:noreply, %{state | cleanup_timer: cleanup_timer}}
  end

  def handle_info({:check_resource, resource_id}, state) do
    case :ets.lookup(state.resource_table, resource_id) do
      [{^resource_id, resource_data}] ->
        # Measure current usage
        current_usage = measure_resource_usage(resource_id)

        # Check thresholds
        check_resource_thresholds(resource_data, current_usage)

        # Update data
        updated_data = %{
          resource_data
          | current_usage: current_usage,
            last_check: System.monotonic_time(:millisecond)
        }

        :ets.insert(state.resource_table, {resource_id, updated_data})

        # Schedule next check
        check_interval = Map.get(resource_data.config, :check_interval, 30_000)
        Process.send_after(self(), {:check_resource, resource_id}, check_interval)

      [] ->
        # Resource no longer monitored
        :ok
    end

    {:noreply, state}
  end

  def handle_info({:reset_circuit_timeout, service_id}, state) do
    case :ets.lookup(state.circuit_table, service_id) do
      [{^service_id, circuit_data}] ->
        if circuit_data.state == :open do
          # Transition to half-open
          updated_data = %{circuit_data | state: :half_open, success_count: 0}
          :ets.insert(state.circuit_table, {service_id, updated_data})
          Logger.debug("Circuit breaker for #{inspect(service_id)} transitioned to half-open")
        end

      [] ->
        :ok
    end

    {:noreply, state}
  end

  # --- Private Circuit Breaker Helpers ---

  defp handle_open_circuit(service_id, function, context, circuit_data, state) do
    # Check if timeout has elapsed
    if should_attempt_reset?(circuit_data) do
      # Transition to half-open
      updated_data = %{circuit_data | state: :half_open, success_count: 0}
      :ets.insert(state.circuit_table, {service_id, updated_data})
      execute_and_track(service_id, function, context, updated_data, state)
    else
      {:reply, {:error, :circuit_open}, state}
    end
  end

  defp execute_and_track(service_id, function, _context, circuit_data, state) do
    result = function.()

    # Track success
    updated_data = handle_success(circuit_data)
    :ets.insert(state.circuit_table, {service_id, updated_data})

    {:reply, {:ok, result}, state}
  rescue
    exception ->
      # Track failure
      updated_data = handle_failure(circuit_data)
      :ets.insert(state.circuit_table, {service_id, updated_data})

      # Schedule reset timeout if circuit opened
      if updated_data.state == :open do
        Process.send_after(
          self(),
          {:reset_circuit_timeout, service_id},
          updated_data.config.timeout
        )
      end

      {:reply, {:error, Exception.message(exception)}, state}
  end

  defp handle_success(circuit_data) do
    case circuit_data.state do
      :half_open ->
        new_success_count = circuit_data.success_count + 1

        if new_success_count >= circuit_data.config.success_threshold do
          # Close the circuit
          %{circuit_data | state: :closed, failure_count: 0, success_count: 0}
        else
          %{circuit_data | success_count: new_success_count}
        end

      _ ->
        # Reset failure count on success
        %{circuit_data | failure_count: 0}
    end
  end

  defp handle_failure(circuit_data) do
    new_failure_count = circuit_data.failure_count + 1

    updated_data = %{
      circuit_data
      | failure_count: new_failure_count,
        last_failure_time: System.monotonic_time(:millisecond)
    }

    case circuit_data.state do
      :closed ->
        if new_failure_count >= circuit_data.config.failure_threshold do
          # Open the circuit
          %{updated_data | state: :open}
        else
          updated_data
        end

      :half_open ->
        # Failure in half-open immediately opens circuit
        %{updated_data | state: :open}

      :open ->
        updated_data
    end
  end

  defp should_attempt_reset?(circuit_data) do
    circuit_data.last_failure_time != nil and
      System.monotonic_time(:millisecond) - circuit_data.last_failure_time >=
        circuit_data.config.timeout
  end

  # --- Private Rate Limiter Helpers ---

  defp validate_rate_limiter_config(config) do
    with {:ok, rate} <- validate_required(config, :rate),
         {:ok, per} <- validate_required(config, :per),
         {:ok, strategy} <- validate_strategy(config) do
      burst = Map.get(config, :burst, rate)

      {:ok,
       %{
         rate: rate,
         per: per,
         burst: burst,
         strategy: strategy
       }}
    end
  end

  defp validate_required(config, key) do
    case Map.get(config, key) do
      nil -> {:error, "#{key} is required"}
      value -> {:ok, value}
    end
  end

  defp validate_strategy(config) do
    strategy = Map.get(config, :strategy, :token_bucket)

    if strategy in [:token_bucket, :sliding_window] do
      {:ok, strategy}
    else
      {:error, "invalid strategy: #{strategy}"}
    end
  end

  defp initialize_rate_limiter(_limiter_id, config) do
    %{
      config: config,
      # Per-identifier buckets
      buckets: %{},
      window_start: System.monotonic_time(:millisecond)
    }
  end

  defp check_and_update_rate_limit(limiter_data, identifier) do
    case limiter_data.config.strategy do
      :token_bucket ->
        check_token_bucket(limiter_data, identifier)

      :sliding_window ->
        check_sliding_window(limiter_data, identifier)
    end
  end

  defp check_token_bucket(limiter_data, identifier) do
    now = System.monotonic_time(:millisecond)

    bucket =
      Map.get(limiter_data.buckets, identifier, %{
        tokens: limiter_data.config.burst,
        last_refill: now
      })

    # Calculate tokens to add based on time elapsed
    time_elapsed = now - bucket.last_refill
    tokens_to_add = time_elapsed / limiter_data.config.per * limiter_data.config.rate
    new_tokens = min(bucket.tokens + tokens_to_add, limiter_data.config.burst)

    if new_tokens >= 1 do
      # Allow request and consume token
      updated_bucket = %{tokens: new_tokens - 1, last_refill: now}
      updated_buckets = Map.put(limiter_data.buckets, identifier, updated_bucket)
      {true, %{limiter_data | buckets: updated_buckets}}
    else
      # Deny request but update refill time
      updated_bucket = %{tokens: new_tokens, last_refill: now}
      updated_buckets = Map.put(limiter_data.buckets, identifier, updated_bucket)
      {false, %{limiter_data | buckets: updated_buckets}}
    end
  end

  defp check_sliding_window(limiter_data, identifier) do
    # Simplified sliding window implementation
    # In production, use a more sophisticated approach with time buckets
    now = System.monotonic_time(:millisecond)
    window = Map.get(limiter_data.buckets, identifier, %{requests: [], window_start: now})

    # Remove old requests outside the window
    cutoff = now - limiter_data.config.per
    active_requests = Enum.filter(window.requests, &(&1 > cutoff))

    if length(active_requests) < limiter_data.config.rate do
      # Allow request
      updated_window = %{requests: [now | active_requests], window_start: window.window_start}
      updated_buckets = Map.put(limiter_data.buckets, identifier, updated_window)
      {true, %{limiter_data | buckets: updated_buckets}}
    else
      # Deny request
      updated_window = %{requests: active_requests, window_start: window.window_start}
      updated_buckets = Map.put(limiter_data.buckets, identifier, updated_window)
      {false, %{limiter_data | buckets: updated_buckets}}
    end
  end

  defp get_identifier_status(limiter_data, identifier) do
    case limiter_data.config.strategy do
      :token_bucket ->
        bucket =
          Map.get(limiter_data.buckets, identifier, %{
            tokens: limiter_data.config.burst,
            last_refill: System.monotonic_time(:millisecond)
          })

        %{
          available_tokens: bucket.tokens,
          max_tokens: limiter_data.config.burst,
          refill_rate: limiter_data.config.rate / limiter_data.config.per
        }

      :sliding_window ->
        window = Map.get(limiter_data.buckets, identifier, %{requests: []})
        now = System.monotonic_time(:millisecond)
        cutoff = now - limiter_data.config.per
        active_requests = Enum.filter(window.requests, &(&1 > cutoff))

        %{
          current_requests: length(active_requests),
          max_requests: limiter_data.config.rate,
          window_ms: limiter_data.config.per
        }
    end
  end

  defp cleanup_rate_limiters(rate_limiter_table) do
    now = System.monotonic_time(:millisecond)
    # 1 hour
    cutoff = now - 3_600_000

    # Use ETS foldl to process entries without loading entire table
    :ets.foldl(
      fn {limiter_id, limiter_data}, acc ->
        # Remove old buckets
        active_buckets =
          limiter_data.buckets
          |> Enum.filter(fn {_identifier, bucket} ->
            last_activity = Map.get(bucket, :last_refill, Map.get(bucket, :window_start, 0))
            last_activity > cutoff
          end)
          |> Enum.into(%{})

        updated_data = %{limiter_data | buckets: active_buckets}
        :ets.insert(rate_limiter_table, {limiter_id, updated_data})
        acc
      end,
      :ok,
      rate_limiter_table
    )
  end

  # --- Private Resource Monitoring Helpers ---

  defp validate_resource_config(config) do
    # Basic validation
    if is_map(config) do
      {:ok, config}
    else
      {:error, :config_must_be_map}
    end
  end

  defp measure_resource_usage(_resource_id) do
    # Get system resource usage
    # This is a simplified version - in production, use proper monitoring
    %{
      memory_usage: :erlang.memory(:total) / :erlang.memory(:system),
      cpu_usage: :erlang.statistics(:scheduler_wall_time) |> calculate_cpu_usage(),
      process_count: :erlang.system_info(:process_count)
    }
  end

  defp calculate_cpu_usage(scheduler_stats) do
    # Simplified CPU calculation
    # In production, track deltas over time
    total_active =
      scheduler_stats
      |> Enum.map(fn {_id, active, total} -> active / total end)
      |> Enum.sum()

    total_active / length(scheduler_stats)
  end

  defp check_resource_thresholds(resource_data, current_usage) do
    thresholds = Map.get(resource_data.config, :thresholds, %{})

    Enum.each(thresholds, fn {resource, threshold} ->
      current_value = Map.get(current_usage, resource, 0)

      if current_value > threshold do
        Logger.warning("Resource #{resource} exceeded threshold: #{current_value} > #{threshold}")

        # Execute configured actions
        actions = Map.get(resource_data.config, :actions, [])
        execute_threshold_actions(resource_data.resource_id, resource, actions)
      end
    end)
  end

  defp execute_threshold_actions(resource_id, resource, actions) do
    Enum.each(actions, fn action ->
      case action do
        {:log, level} ->
          Logger.log(level, "Threshold breach for #{resource_id} on #{resource}")

        {:notify, recipient} ->
          # Send notification (implementation depends on system)
          send(recipient, {:resource_threshold_breach, resource_id, resource})

        _ ->
          Logger.debug("Unknown action: #{inspect(action)}")
      end
    end)
  end
end
