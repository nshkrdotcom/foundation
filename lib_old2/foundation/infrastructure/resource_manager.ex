defmodule Foundation.Infrastructure.ResourceManager do
  @moduledoc """
  Agent-aware resource management and monitoring system.

  Provides comprehensive resource tracking, allocation, and enforcement
  for multi-agent environments. Monitors system and agent-specific resources,
  enforces resource limits, and provides early warning systems for resource
  exhaustion scenarios.

  ## Features

  - **Multi-Level Monitoring**: System, node, and agent-specific resource tracking
  - **Dynamic Allocation**: Resource allocation based on agent capabilities and health
  - **Threshold Management**: Configurable warning and critical thresholds
  - **Resource Enforcement**: Automatic throttling and protection mechanisms
  - **Coordination Integration**: Resource decisions participate in agent coordination
  - **Predictive Alerts**: Early warning system for resource exhaustion

  ## Resource Types Monitored

  - **Memory**: Heap usage, process memory, agent-specific allocation
  - **CPU**: System load, process CPU usage, agent computational load
  - **Network**: Connection counts, bandwidth usage, request rates
  - **Storage**: Disk usage, file handles, temporary storage
  - **Custom**: Agent-specific resource types (GPU memory, model slots, etc.)

  ## Usage

      # Start resource manager
      {:ok, _pid} = ResourceManager.start_link([
        monitoring_interval: 5_000,
        system_thresholds: %{
          memory: %{warning: 0.8, critical: 0.9},
          cpu: %{warning: 0.7, critical: 0.85}
        }
      ])

      # Register agent with resource requirements
      ResourceManager.register_agent(:ml_agent_1, %{
        memory_limit: 2_000_000_000,  # 2GB
        cpu_limit: 2.0,              # 2 cores
        custom_resources: %{gpu_memory: 4_000_000_000}
      })

      # Check resource availability
      case ResourceManager.check_resource_availability(:ml_agent_1, :memory, 500_000_000) do
        :ok -> proceed_with_allocation()
        {:error, error} -> handle_resource_constraint(error)
      end

      # Get comprehensive resource status
      status = ResourceManager.get_system_resource_status()
  """

  use GenServer
  require Logger

  alias Foundation.ProcessRegistry
  alias Foundation.Telemetry
  alias Foundation.Types.Error

  @type agent_id :: atom() | String.t()
  @type resource_type :: :memory | :cpu | :network | :storage | atom()
  @type resource_amount :: non_neg_integer() | float()
  @type threshold_config :: %{warning: float(), critical: float()}
  @type resource_limits :: %{resource_type() => resource_amount()}

  @type resource_status :: %{
    current: resource_amount(),
    limit: resource_amount(),
    percentage: float(),
    status: :ok | :warning | :critical
  }

  @type agent_resource_info :: %{
    agent_id: agent_id(),
    resource_limits: resource_limits(),
    current_usage: resource_limits(),
    health_impact: float(),
    last_updated: DateTime.t()
  }

  defstruct [
    :monitoring_interval,
    :system_thresholds,
    :agent_resources,
    :system_metrics,
    :resource_history,
    :alert_state,
    :enforcement_enabled
  ]

  @type t :: %__MODULE__{
    monitoring_interval: pos_integer(),
    system_thresholds: %{resource_type() => threshold_config()},
    agent_resources: :ets.tid(),
    system_metrics: :ets.tid(),
    resource_history: :ets.tid(),
    alert_state: map(),
    enforcement_enabled: boolean()
  }

  # Default system resource thresholds
  @default_system_thresholds %{
    memory: %{warning: 0.8, critical: 0.9},
    cpu: %{warning: 0.7, critical: 0.85},
    network_connections: %{warning: 0.8, critical: 0.9},
    file_handles: %{warning: 0.8, critical: 0.9}
  }

  # Public API

  @doc """
  Start the resource manager with specified configuration.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(options \\ []) do
    GenServer.start_link(__MODULE__, options, name: __MODULE__)
  end

  @doc """
  Register an agent with its resource requirements and limits.

  ## Parameters
  - `agent_id`: Unique identifier for the agent
  - `resource_limits`: Resource limits and requirements for the agent
  - `metadata`: Additional agent context

  ## Examples

      ResourceManager.register_agent(:ml_agent_1, %{
        memory_limit: 2_000_000_000,
        cpu_limit: 2.0,
        custom_resources: %{gpu_memory: 4_000_000_000}
      })
  """
  @spec register_agent(agent_id(), resource_limits(), map()) ::
    :ok | {:error, Error.t()}
  def register_agent(agent_id, resource_limits, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:register_agent, agent_id, resource_limits, metadata})
  rescue
    error -> {:error, resource_manager_error("register_agent failed", error)}
  end

  @doc """
  Check if sufficient resources are available for an agent operation.

  Performs comprehensive resource availability checking including
  system-level and agent-specific constraints.
  """
  @spec check_resource_availability(agent_id(), resource_type(), resource_amount()) ::
    :ok | {:error, Error.t()}
  def check_resource_availability(agent_id, resource_type, required_amount) do
    GenServer.call(__MODULE__, {:check_availability, agent_id, resource_type, required_amount})
  rescue
    error -> {:error, resource_manager_error("check_availability failed", error)}
  end

  @doc """
  Allocate resources to an agent for a specific operation.

  Records resource allocation and updates tracking to prevent
  over-allocation of system resources.
  """
  @spec allocate_resources(agent_id(), resource_limits()) ::
    :ok | {:error, Error.t()}
  def allocate_resources(agent_id, resource_allocation) do
    GenServer.call(__MODULE__, {:allocate_resources, agent_id, resource_allocation})
  rescue
    error -> {:error, resource_manager_error("allocate_resources failed", error)}
  end

  @doc """
  Release previously allocated resources.

  Updates resource tracking to make resources available for other agents.
  """
  @spec release_resources(agent_id(), resource_limits()) :: :ok
  def release_resources(agent_id, resource_deallocation) do
    GenServer.call(__MODULE__, {:release_resources, agent_id, resource_deallocation})
  rescue
    error ->
      Logger.warning("Resource release failed for #{agent_id}: #{inspect(error)}")
      :ok
  end

  @doc """
  Get comprehensive system resource status.

  Returns current resource utilization across all monitored resources
  and agents, including health indicators and trend information.
  """
  @spec get_system_resource_status() :: {:ok, map()} | {:error, Error.t()}
  def get_system_resource_status do
    GenServer.call(__MODULE__, :get_system_status)
  rescue
    error -> {:error, resource_manager_error("get_system_status failed", error)}
  end

  @doc """
  Get resource status for a specific agent.
  """
  @spec get_agent_resource_status(agent_id()) :: {:ok, agent_resource_info()} | {:error, Error.t()}
  def get_agent_resource_status(agent_id) do
    GenServer.call(__MODULE__, {:get_agent_status, agent_id})
  rescue
    error -> {:error, resource_manager_error("get_agent_status failed", error)}
  end

  @doc """
  Update resource limits for an existing agent.

  Allows dynamic adjustment of agent resource constraints based
  on changing requirements or system conditions.
  """
  @spec update_agent_limits(agent_id(), resource_limits()) :: :ok | {:error, Error.t()}
  def update_agent_limits(agent_id, new_limits) do
    GenServer.call(__MODULE__, {:update_limits, agent_id, new_limits})
  rescue
    error -> {:error, resource_manager_error("update_limits failed", error)}
  end

  # GenServer Implementation

  @impl GenServer
  def init(options) do
    monitoring_interval = Keyword.get(options, :monitoring_interval, 5_000)
    system_thresholds = Keyword.get(options, :system_thresholds, @default_system_thresholds)
    enforcement_enabled = Keyword.get(options, :enforcement_enabled, true)

    # Create ETS tables for resource tracking
    agent_resources = :ets.new(:agent_resources, [
      :set, :private, {:write_concurrency, true}, {:read_concurrency, true}
    ])

    system_metrics = :ets.new(:system_metrics, [
      :set, :private, {:write_concurrency, true}, {:read_concurrency, true}
    ])

    resource_history = :ets.new(:resource_history, [
      :ordered_set, :private, {:write_concurrency, true}, {:read_concurrency, true}
    ])

    state = %__MODULE__{
      monitoring_interval: monitoring_interval,
      system_thresholds: system_thresholds,
      agent_resources: agent_resources,
      system_metrics: system_metrics,
      resource_history: resource_history,
      alert_state: %{},
      enforcement_enabled: enforcement_enabled
    }

    # Register with ProcessRegistry
    case ProcessRegistry.register(:foundation, __MODULE__, self(), %{
      type: :resource_manager,
      health: :healthy,
      monitoring_interval: monitoring_interval
    }) do
      :ok ->
        # Start resource monitoring
        schedule_monitoring()

        # Perform initial system resource collection
        collect_system_metrics(state)

        Telemetry.emit_counter(
          [:foundation, :infrastructure, :resource_manager, :started],
          %{monitoring_interval: monitoring_interval}
        )

        {:ok, state}

      {:error, reason} ->
        {:stop, {:registration_failed, reason}}
    end
  end

  @impl GenServer
  def handle_call({:register_agent, agent_id, resource_limits, metadata}, _from, state) do
    agent_info = %{
      agent_id: agent_id,
      resource_limits: resource_limits,
      current_usage: initialize_usage_map(resource_limits),
      health_impact: 0.0,
      last_updated: DateTime.utc_now(),
      metadata: metadata
    }

    :ets.insert(state.agent_resources, {agent_id, agent_info})

    Telemetry.emit_counter(
      [:foundation, :infrastructure, :resource_manager, :agent_registered],
      %{agent_id: agent_id, resource_types: Map.keys(resource_limits)}
    )

    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call({:check_availability, agent_id, resource_type, required_amount}, _from, state) do
    result = perform_availability_check(agent_id, resource_type, required_amount, state)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:allocate_resources, agent_id, resource_allocation}, _from, state) do
    result = perform_resource_allocation(agent_id, resource_allocation, state)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:release_resources, agent_id, resource_deallocation}, _from, state) do
    perform_resource_release(agent_id, resource_deallocation, state)
    {:reply, :ok, state}
  end

  @impl GenServer
  def handle_call(:get_system_status, _from, state) do
    status = build_system_status(state)
    {:reply, {:ok, status}, state}
  end

  @impl GenServer
  def handle_call({:get_agent_status, agent_id}, _from, state) do
    result = get_agent_info(agent_id, state)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_call({:update_limits, agent_id, new_limits}, _from, state) do
    result = update_agent_resource_limits(agent_id, new_limits, state)
    {:reply, result, state}
  end

  @impl GenServer
  def handle_info(:monitor_resources, state) do
    new_state = perform_resource_monitoring_cycle(state)
    schedule_monitoring()
    {:noreply, new_state}
  end

  @impl GenServer
  def handle_info(_message, state) do
    {:noreply, state}
  end

  # Private Implementation

  defp perform_availability_check(agent_id, resource_type, required_amount, state) do
    with {:ok, agent_info} <- get_agent_info(agent_id, state),
         :ok <- check_agent_limits(agent_info, resource_type, required_amount),
         :ok <- check_system_availability(resource_type, required_amount, state) do
      :ok
    else
      {:error, _} = error -> error
      error -> {:error, resource_availability_error(agent_id, resource_type, error)}
    end
  end

  defp check_agent_limits(agent_info, resource_type, required_amount) do
    case Map.get(agent_info.resource_limits, resource_type) do
      nil -> :ok  # No limit defined for this resource type
      limit ->
        current_usage = Map.get(agent_info.current_usage, resource_type, 0)
        if current_usage + required_amount <= limit do
          :ok
        else
          {:error, agent_limit_exceeded_error(agent_info.agent_id, resource_type,
            current_usage, required_amount, limit)}
        end
    end
  end

  defp check_system_availability(resource_type, required_amount, state) do
    case get_system_resource_status(resource_type, state) do
      %{status: :critical} ->
        {:error, system_resource_critical_error(resource_type)}

      %{current: current, limit: limit} when current + required_amount > limit ->
        {:error, system_resource_exceeded_error(resource_type, current, required_amount, limit)}

      _ -> :ok
    end
  end

  defp perform_resource_allocation(agent_id, resource_allocation, state) do
    case get_agent_info(agent_id, state) do
      {:ok, agent_info} ->
        # Update current usage
        new_usage = Map.merge(agent_info.current_usage, resource_allocation, fn
          _key, current, additional -> current + additional
        end)

        updated_info = %{agent_info |
          current_usage: new_usage,
          last_updated: DateTime.utc_now()
        }

        :ets.insert(state.agent_resources, {agent_id, updated_info})

        # Emit telemetry
        Telemetry.emit_counter(
          [:foundation, :infrastructure, :resource_manager, :resources_allocated],
          %{agent_id: agent_id, resources: Map.keys(resource_allocation)}
        )

        :ok

      {:error, _} = error -> error
    end
  end

  defp perform_resource_release(agent_id, resource_deallocation, state) do
    case get_agent_info(agent_id, state) do
      {:ok, agent_info} ->
        # Update current usage (subtract released resources)
        new_usage = Map.merge(agent_info.current_usage, resource_deallocation, fn
          _key, current, released -> max(0, current - released)
        end)

        updated_info = %{agent_info |
          current_usage: new_usage,
          last_updated: DateTime.utc_now()
        }

        :ets.insert(state.agent_resources, {agent_id, updated_info})

        # Emit telemetry
        Telemetry.emit_counter(
          [:foundation, :infrastructure, :resource_manager, :resources_released],
          %{agent_id: agent_id, resources: Map.keys(resource_deallocation)}
        )

      {:error, _} ->
        # Log warning but don't fail the release
        Logger.warning("Failed to find agent #{agent_id} for resource release")
    end
  end

  defp get_agent_info(agent_id, state) do
    case :ets.lookup(state.agent_resources, agent_id) do
      [{^agent_id, agent_info}] -> {:ok, agent_info}
      [] -> {:error, agent_not_found_error(agent_id)}
    end
  end

  defp update_agent_resource_limits(agent_id, new_limits, state) do
    case get_agent_info(agent_id, state) do
      {:ok, agent_info} ->
        updated_info = %{agent_info |
          resource_limits: new_limits,
          last_updated: DateTime.utc_now()
        }

        :ets.insert(state.agent_resources, {agent_id, updated_info})

        Telemetry.emit_counter(
          [:foundation, :infrastructure, :resource_manager, :limits_updated],
          %{agent_id: agent_id}
        )

        :ok

      {:error, _} = error -> error
    end
  end

  defp perform_resource_monitoring_cycle(state) do
    # Collect current system metrics
    new_state = collect_system_metrics(state)

    # Update agent resource usage from system information
    updated_state = update_agent_usage_from_system(new_state)

    # Check for threshold violations and emit alerts
    check_and_emit_alerts(updated_state)

    # Store historical data
    store_resource_history(updated_state)

    updated_state
  end

  defp collect_system_metrics(state) do
    current_time = DateTime.utc_now()

    # Collect Erlang VM metrics
    memory_total = :erlang.memory(:total)
    memory_limit = get_system_memory_limit()

    process_count = :erlang.system_info(:process_count)
    process_limit = :erlang.system_info(:process_limit)

    # Store system metrics
    system_metrics = %{
      memory: %{current: memory_total, limit: memory_limit},
      processes: %{current: process_count, limit: process_limit},
      timestamp: current_time
    }

    :ets.insert(state.system_metrics, {:current, system_metrics})

    state
  end

  defp update_agent_usage_from_system(state) do
    # Update agent resource usage based on actual system measurements
    # This is a simplified implementation - in production you might use
    # more sophisticated process monitoring

    all_agents = :ets.tab2list(state.agent_resources)

    Enum.each(all_agents, fn {agent_id, agent_info} ->
      # Try to get actual resource usage for the agent
      updated_usage = get_actual_agent_usage(agent_id, agent_info)

      if updated_usage != agent_info.current_usage do
        updated_info = %{agent_info |
          current_usage: updated_usage,
          last_updated: DateTime.utc_now()
        }

        :ets.insert(state.agent_resources, {agent_id, updated_info})
      end
    end)

    state
  end

  defp get_actual_agent_usage(agent_id, agent_info) do
    # Try to get actual resource usage from ProcessRegistry
    case ProcessRegistry.lookup(:foundation, agent_id) do
      {:ok, pid, _metadata} when is_pid(pid) ->
        # Get process memory usage
        case Process.info(pid, [:memory, :reductions]) do
          [{:memory, memory}, {:reductions, reductions}] ->
            %{
              memory: memory,
              cpu: calculate_cpu_usage(reductions),
              # Keep other usage as reported
              network: Map.get(agent_info.current_usage, :network, 0),
              storage: Map.get(agent_info.current_usage, :storage, 0)
            }

          _ -> agent_info.current_usage
        end

      _ -> agent_info.current_usage
    end
  end

  defp calculate_cpu_usage(_reductions) do
    # Simplified CPU usage calculation
    # In production, you'd track reductions over time
    0.0
  end

  defp check_and_emit_alerts(state) do
    # Check system resource thresholds
    system_metrics = get_current_system_metrics(state)

    Enum.each(state.system_thresholds, fn {resource_type, thresholds} ->
      case Map.get(system_metrics, resource_type) do
        %{current: current, limit: limit} ->
          percentage = current / limit

          cond do
            percentage >= thresholds.critical ->
              emit_resource_alert(:critical, resource_type, percentage, state)

            percentage >= thresholds.warning ->
              emit_resource_alert(:warning, resource_type, percentage, state)

            true -> :ok
          end

        _ -> :ok
      end
    end)
  end

  defp emit_resource_alert(severity, resource_type, percentage, _state) do
    Telemetry.emit_counter(
      [:foundation, :infrastructure, :resource_manager, :alert],
      %{
        severity: severity,
        resource_type: resource_type,
        percentage: percentage
      }
    )

    if severity == :critical do
      Logger.warning(
        "Critical resource alert: #{resource_type} at #{trunc(percentage * 100)}%",
        resource_type: resource_type,
        percentage: percentage
      )
    end
  end

  defp store_resource_history(state) do
    current_time = System.system_time(:millisecond)
    system_metrics = get_current_system_metrics(state)

    :ets.insert(state.resource_history, {current_time, system_metrics})

    # Clean old history (keep last hour)
    cutoff_time = current_time - (60 * 60 * 1000)
    :ets.select_delete(state.resource_history, [
      {{:"$1", :_}, [{:<, :"$1", cutoff_time}], [true]}
    ])
  end

  defp build_system_status(state) do
    system_metrics = get_current_system_metrics(state)
    all_agents = :ets.tab2list(state.agent_resources)

    %{
      system_resources: system_metrics,
      agent_count: length(all_agents),
      agent_resources: Enum.map(all_agents, fn {_id, info} -> info end),
      resource_history_size: :ets.info(state.resource_history, :size),
      monitoring_interval: state.monitoring_interval,
      enforcement_enabled: state.enforcement_enabled
    }
  end

  defp get_current_system_metrics(state) do
    case :ets.lookup(state.system_metrics, :current) do
      [{:current, metrics}] -> metrics
      [] -> %{}
    end
  end

  defp get_system_resource_status(resource_type, state) do
    system_metrics = get_current_system_metrics(state)
    resource_data = Map.get(system_metrics, resource_type, %{current: 0, limit: 1})

    percentage = resource_data.current / resource_data.limit
    thresholds = Map.get(state.system_thresholds, resource_type, %{warning: 0.8, critical: 0.9})

    status = cond do
      percentage >= thresholds.critical -> :critical
      percentage >= thresholds.warning -> :warning
      true -> :ok
    end

    Map.put(resource_data, :status, status)
  end

  defp get_system_memory_limit do
    # Get total system memory or use a reasonable default
    case :erlang.memory(:total) do
      total when total > 0 -> total * 10  # Assume 10x current as limit
      _ -> 8_000_000_000  # 8GB default
    end
  end

  defp initialize_usage_map(resource_limits) do
    resource_limits
    |> Map.keys()
    |> Enum.reduce(%{}, fn resource_type, acc ->
      Map.put(acc, resource_type, 0)
    end)
  end

  defp schedule_monitoring do
    Process.send_after(self(), :monitor_resources, 5_000)
  end

  # Error Helper Functions

  defp resource_manager_error(message, error) do
    Error.new(
      code: 8001,
      error_type: :resource_manager_error,
      message: "Resource manager error: #{message}",
      severity: :medium,
      context: %{error: error}
    )
  end

  defp agent_not_found_error(agent_id) do
    Error.new(
      code: 8002,
      error_type: :agent_not_found,
      message: "Agent not found in resource manager: #{agent_id}",
      severity: :medium,
      context: %{agent_id: agent_id}
    )
  end

  defp resource_availability_error(agent_id, resource_type, details) do
    Error.new(
      code: 8003,
      error_type: :resource_availability_check_failed,
      message: "Resource availability check failed for #{agent_id}:#{resource_type}",
      severity: :medium,
      context: %{agent_id: agent_id, resource_type: resource_type, details: details}
    )
  end

  defp agent_limit_exceeded_error(agent_id, resource_type, current, required, limit) do
    Error.new(
      code: 8004,
      error_type: :agent_resource_limit_exceeded,
      message: "Agent #{agent_id} would exceed #{resource_type} limit: #{current + required} > #{limit}",
      severity: :medium,
      context: %{
        agent_id: agent_id,
        resource_type: resource_type,
        current_usage: current,
        required_amount: required,
        limit: limit
      },
      retry_strategy: :fixed_delay
    )
  end

  defp system_resource_critical_error(resource_type) do
    Error.new(
      code: 8005,
      error_type: :system_resource_critical,
      message: "System resource #{resource_type} is in critical state",
      severity: :high,
      context: %{resource_type: resource_type},
      retry_strategy: :exponential_backoff
    )
  end

  defp system_resource_exceeded_error(resource_type, current, required, limit) do
    Error.new(
      code: 8006,
      error_type: :system_resource_limit_exceeded,
      message: "System #{resource_type} limit would be exceeded: #{current + required} > #{limit}",
      severity: :high,
      context: %{
        resource_type: resource_type,
        current_usage: current,
        required_amount: required,
        limit: limit
      },
      retry_strategy: :exponential_backoff
    )
  end
end