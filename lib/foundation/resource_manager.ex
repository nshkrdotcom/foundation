defmodule Foundation.ResourceManager do
  @moduledoc """
  Manages resource safety for Foundation operations.

  This module provides:
  - Memory usage monitoring and limits
  - ETS table size management
  - Backpressure mechanisms
  - Resource cleanup verification
  - Performance metrics and alerts

  ## Configuration

  Configure resource limits in your application:

      config :foundation,
        resource_limits: %{
          max_memory_mb: 1024,           # Maximum memory usage in MB
          max_ets_entries: 1_000_000,    # Maximum entries per ETS table
          max_registry_size: 100_000,     # Maximum agents per registry
          cleanup_interval: 60_000,       # Cleanup interval in ms
          alert_threshold: 0.9           # Alert when 90% of limit reached
        }

  ## Usage

  The ResourceManager automatically monitors Foundation registries and
  enforces resource limits. It can also be used directly:

      # Check if operation is allowed
      {:ok, token} = Foundation.ResourceManager.acquire_resource(:register_agent, %{size: 1})

      # Perform operation...

      # Release resource
      Foundation.ResourceManager.release_resource(token)
  """

  use GenServer
  require Logger

  @default_limits %{
    max_memory_mb: 1024,
    max_ets_entries: 1_000_000,
    max_registry_size: 100_000,
    cleanup_interval: 60_000,
    alert_threshold: 0.9
  }

  defstruct [
    :limits,
    :current_usage,
    :monitored_tables,
    :cleanup_timer,
    :alert_callbacks,
    :backpressure_state
  ]

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Registers an ETS table for monitoring.
  """
  def monitor_table(table_name) do
    GenServer.call(__MODULE__, {:monitor_table, table_name})
  end

  @doc """
  Acquires a resource token if resources are available.

  Returns {:ok, token} if resources available, {:error, :resource_exhausted} otherwise.
  """
  def acquire_resource(resource_type, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:acquire_resource, resource_type, metadata})
  end

  @doc """
  Releases a previously acquired resource token.
  """
  def release_resource(token) do
    GenServer.cast(__MODULE__, {:release_resource, token})
  end

  @doc """
  Gets current resource usage statistics.
  """
  def get_usage_stats do
    GenServer.call(__MODULE__, :get_usage_stats)
  end

  @doc """
  Registers a callback for resource alerts.
  """
  def register_alert_callback(callback) when is_function(callback, 2) do
    GenServer.call(__MODULE__, {:register_alert_callback, callback})
  end

  @doc """
  Forces a resource cleanup cycle.
  """
  def force_cleanup do
    GenServer.call(__MODULE__, :force_cleanup)
  end

  # Server Implementation

  def init(_opts) do
    # Load configuration
    config_limits = Application.get_env(:foundation, :resource_limits, %{})
    limits = Map.merge(@default_limits, config_limits)

    state = %__MODULE__{
      limits: limits,
      current_usage: %{
        memory_mb: 0,
        ets_entries: %{},
        total_ets_entries: 0,
        registry_sizes: %{},
        active_tokens: %{}
      },
      monitored_tables: MapSet.new(),
      cleanup_timer: nil,
      alert_callbacks: [],
      backpressure_state: :normal
    }

    # Start cleanup timer
    timer = Process.send_after(self(), :cleanup, limits.cleanup_interval)

    # Initial measurement
    state = measure_current_usage(%{state | cleanup_timer: timer})

    Logger.info("Foundation.ResourceManager started with limits: #{inspect(limits)}")

    {:ok, state}
  end

  def handle_call({:monitor_table, table_name}, _from, state) do
    new_tables = MapSet.put(state.monitored_tables, table_name)
    new_state = %{state | monitored_tables: new_tables}

    # Immediately measure the new table
    updated_state = measure_table_usage(new_state, table_name)

    {:reply, :ok, updated_state}
  end

  def handle_call({:acquire_resource, resource_type, metadata}, _from, state) do
    case check_resource_availability(state, resource_type, metadata) do
      :ok ->
        token = generate_token(resource_type, metadata)
        new_usage = record_token(state.current_usage, token, metadata)
        new_state = %{state | current_usage: new_usage}

        # Check if we need to enter backpressure
        updated_state = update_backpressure_state(new_state)

        {:reply, {:ok, token}, updated_state}

      {:error, reason} = error ->
        trigger_alert(state, :resource_denied, %{
          resource_type: resource_type,
          reason: reason,
          current_usage: state.current_usage
        })

        {:reply, error, state}
    end
  end

  def handle_call(:get_usage_stats, _from, state) do
    stats = compile_usage_stats(state)
    {:reply, stats, state}
  end

  def handle_call({:register_alert_callback, callback}, _from, state) do
    new_callbacks = [callback | state.alert_callbacks]
    {:reply, :ok, %{state | alert_callbacks: new_callbacks}}
  end

  def handle_call(:force_cleanup, _from, state) do
    new_state = perform_cleanup(state)
    {:reply, :ok, new_state}
  end

  def handle_cast({:release_resource, token}, state) do
    new_usage = remove_token(state.current_usage, token)
    new_state = %{state | current_usage: new_usage}

    # Check if we can exit backpressure
    updated_state = update_backpressure_state(new_state)

    {:noreply, updated_state}
  end

  def handle_info(:cleanup, state) do
    # Perform cleanup
    new_state = perform_cleanup(state)

    # Schedule next cleanup
    timer = Process.send_after(self(), :cleanup, state.limits.cleanup_interval)

    {:noreply, %{new_state | cleanup_timer: timer}}
  end

  def handle_info({:telemetry_event, _event, _measurements, _metadata}, state) do
    # Ignore telemetry events sent to this process
    {:noreply, state}
  end

  def handle_info(_msg, state) do
    # Ignore unexpected messages
    {:noreply, state}
  end

  # Private Functions

  defp measure_current_usage(state) do
    # Measure memory
    memory_mb = :erlang.memory(:total) / 1_048_576

    # Measure ETS tables
    ets_entries =
      Enum.reduce(state.monitored_tables, %{}, fn table, acc ->
        size = safe_ets_info(table, :size)
        Map.put(acc, table, size)
      end)

    # Calculate total entries
    total_entries = Enum.sum(Map.values(ets_entries))

    new_usage = %{
      state.current_usage
      | memory_mb: memory_mb,
        ets_entries: ets_entries,
        total_ets_entries: total_entries
    }

    %{state | current_usage: new_usage}
  end

  defp measure_table_usage(state, table_name) do
    size = safe_ets_info(table_name, :size)

    new_entries = Map.put(state.current_usage.ets_entries, table_name, size)
    total = Enum.sum(Map.values(new_entries))

    new_usage = %{state.current_usage | ets_entries: new_entries, total_ets_entries: total}

    %{state | current_usage: new_usage}
  end

  defp safe_ets_info(table, key) do
    case :ets.info(table, key) do
      :undefined -> 0
      value -> value
    end
  rescue
    _ -> 0
  end

  defp check_resource_availability(state, :register_agent, _metadata) do
    %{limits: limits, current_usage: usage} = state

    cond do
      # Check memory limit
      usage.memory_mb > limits.max_memory_mb ->
        {:error, :memory_exhausted}

      # Check total ETS entries
      Map.get(usage, :total_ets_entries, 0) >= limits.max_ets_entries ->
        {:error, :ets_table_full}

      # Check if in severe backpressure
      state.backpressure_state == :severe ->
        {:error, :backpressure_active}

      true ->
        :ok
    end
  end

  defp check_resource_availability(_state, _type, _metadata) do
    # Default to allowing unknown resource types
    :ok
  end

  defp generate_token(resource_type, metadata) do
    %{
      id: System.unique_integer([:positive, :monotonic]),
      type: resource_type,
      metadata: metadata,
      acquired_at: System.monotonic_time(:millisecond)
    }
  end

  defp record_token(usage, token, _metadata) do
    tokens = Map.get(usage, :active_tokens, %{})
    new_tokens = Map.put(tokens, token.id, token)
    Map.put(usage, :active_tokens, new_tokens)
  end

  defp remove_token(usage, token) do
    tokens = Map.get(usage, :active_tokens, %{})
    new_tokens = Map.delete(tokens, token.id)
    Map.put(usage, :active_tokens, new_tokens)
  end

  defp update_backpressure_state(state) do
    %{limits: limits, current_usage: usage} = state

    memory_ratio = usage.memory_mb / limits.max_memory_mb
    ets_ratio = Map.get(usage, :total_ets_entries, 0) / limits.max_ets_entries

    new_backpressure =
      cond do
        memory_ratio > 0.95 or ets_ratio > 0.95 ->
          :severe

        memory_ratio > limits.alert_threshold or ets_ratio > limits.alert_threshold ->
          :moderate

        true ->
          :normal
      end

    if new_backpressure != state.backpressure_state do
      trigger_alert(state, :backpressure_changed, %{
        old_state: state.backpressure_state,
        new_state: new_backpressure,
        memory_ratio: memory_ratio,
        ets_ratio: ets_ratio
      })
    end

    %{state | backpressure_state: new_backpressure}
  end

  defp perform_cleanup(state) do
    Logger.debug("ResourceManager performing cleanup cycle")

    # Clean up expired tokens
    now = System.monotonic_time(:millisecond)
    tokens = Map.get(state.current_usage, :active_tokens, %{})

    # Remove tokens older than 5 minutes
    active_tokens =
      Enum.reduce(tokens, %{}, fn {id, token}, acc ->
        if now - token.acquired_at < 300_000 do
          Map.put(acc, id, token)
        else
          acc
        end
      end)

    # Re-measure usage
    measured_state = measure_current_usage(state)
    updated_usage = Map.put(measured_state.current_usage, :active_tokens, active_tokens)

    %{measured_state | current_usage: updated_usage}
    |> update_backpressure_state()
  end

  defp compile_usage_stats(state) do
    %{limits: limits, current_usage: usage} = state

    %{
      memory: %{
        current_mb: usage.memory_mb,
        limit_mb: limits.max_memory_mb,
        usage_percent: usage.memory_mb / limits.max_memory_mb * 100
      },
      ets_tables: %{
        total_entries: Map.get(usage, :total_ets_entries, 0),
        limit_entries: limits.max_ets_entries,
        usage_percent: Map.get(usage, :total_ets_entries, 0) / limits.max_ets_entries * 100,
        per_table: usage.ets_entries
      },
      active_tokens: map_size(Map.get(usage, :active_tokens, %{})),
      backpressure_state: state.backpressure_state
    }
  end

  defp trigger_alert(state, alert_type, data) do
    Enum.each(state.alert_callbacks, fn callback ->
      # Call in a spawned process to avoid blocking
      spawn(fn ->
        try do
          callback.(alert_type, data)
        rescue
          e ->
            Logger.error("Alert callback failed: #{Exception.message(e)}")
        end
      end)
    end)

    # Also emit telemetry
    :telemetry.execute(
      [:foundation, :resource_manager, alert_type],
      Map.take(data, [:memory_ratio, :ets_ratio]),
      Map.drop(data, [:memory_ratio, :ets_ratio])
    )
  end
end
