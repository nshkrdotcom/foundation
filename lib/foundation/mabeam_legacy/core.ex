defmodule Foundation.MABEAM.Core do
  @moduledoc """
  Universal Variable Orchestrator for multi-agent coordination on the BEAM.

  Provides the core infrastructure for variables to coordinate agents across
  the entire BEAM cluster, managing agent lifecycle, resource allocation,
  and adaptive behavior based on collective performance.

  ## Features

  - Universal variable registration and management
  - Basic agent coordination protocols
  - Integration with Foundation services (ProcessRegistry, Events, Telemetry)
  - Performance monitoring and metrics collection
  - Fault tolerance and graceful error handling
  - Health checks and service monitoring

  ## Architecture

  The Core orchestrator maintains:
  - Variable registry for orchestration variables
  - Coordination history for audit and analysis
  - Performance metrics for optimization
  - Service configuration and state

  ## Usage

      # Start the Core orchestrator
      {:ok, pid} = Foundation.MABEAM.Core.start_link([])

      # Register an orchestration variable
      variable = create_orchestration_variable()
      :ok = Foundation.MABEAM.Core.register_orchestration_variable(variable)

      # Coordinate the system
      {:ok, results} = Foundation.MABEAM.Core.coordinate_system()

  """

  use Foundation.Services.ServiceBehaviour

  alias Foundation.{Events, ProcessRegistry, ServiceRegistry}
  # alias Foundation.MABEAM.Types  # Not used yet, will be needed for validation

  # ============================================================================
  # Type Definitions
  # ============================================================================

  @type orchestrator_state :: %{
          # Service state from ServiceBehaviour
          service_name: atom(),
          config: map(),
          health_status: :starting | :healthy | :degraded | :unhealthy | :stopping,
          last_health_check: DateTime.t() | nil,
          startup_time: DateTime.t(),
          dependencies: [atom()],
          dependency_status: %{atom() => boolean()},
          metrics: service_metrics(),
          namespace: ProcessRegistry.namespace(),
          # Core-specific state
          variable_registry: %{atom() => orchestration_variable()},
          coordination_history: [coordination_event()],
          performance_metrics: performance_metrics()
        }

  @type orchestration_variable :: %{
          id: atom(),
          scope: :local | :global | :cluster,
          type: :agent_selection | :resource_allocation | :communication_topology,
          agents: [pid() | atom()],
          coordination_fn: (list(), map(), map() -> {:ok, term()} | {:error, term()}),
          adaptation_fn: (term(), map(), map() -> {:ok, term()} | {:error, term()}),
          constraints: [term()],
          resource_requirements: %{memory: number(), cpu: number()},
          fault_tolerance: %{strategy: atom(), max_restarts: non_neg_integer()},
          telemetry_config: %{enabled: boolean()}
        }

  @type coordination_event :: %{
          id: String.t(),
          type: :coordination_start | :coordination_complete | :coordination_error,
          timestamp: DateTime.t(),
          variables: [atom()],
          result: term(),
          duration_ms: non_neg_integer() | nil,
          metadata: map()
        }

  @type coordination_result :: %{
          variable_id: atom(),
          result: {:ok, term()} | {:error, term()},
          duration_ms: non_neg_integer(),
          metadata: map()
        }

  @type performance_metrics :: %{
          coordination_count: non_neg_integer(),
          variable_count: non_neg_integer(),
          avg_coordination_time_ms: float(),
          success_rate: float(),
          error_count: non_neg_integer()
        }

  @type service_metrics :: %{
          health_checks: non_neg_integer(),
          health_check_failures: non_neg_integer(),
          uptime_ms: non_neg_integer(),
          memory_usage: non_neg_integer(),
          message_queue_length: non_neg_integer()
        }

  @type system_status :: %{
          variable_registry: %{atom() => orchestration_variable()},
          coordination_history: [coordination_event()],
          performance_metrics: performance_metrics(),
          config: map()
        }

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Start the MABEAM Core orchestrator.

  ## Parameters
  - `opts` - Keyword list of options including:
    - `:config` - Custom configuration map
    - `:namespace` - ProcessRegistry namespace (default: :production)

  ## Returns
  - `{:ok, pid}` - Successfully started
  - `{:error, reason}` - Startup failed

  ## Examples

      iex> {:ok, pid} = Foundation.MABEAM.Core.start_link([])
      iex> is_pid(pid)
      true

      iex> config = %{max_variables: 50}
      iex> {:ok, pid} = Foundation.MABEAM.Core.start_link(config: config)
      iex> is_pid(pid)
      true
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register an orchestration variable with the Core orchestrator.

  ## Parameters
  - `variable` - Orchestration variable map with required fields

  ## Returns
  - `:ok` - Successfully registered
  - `{:error, reason}` - Registration failed

  ## Examples

      iex> variable = create_test_variable()
      iex> Foundation.MABEAM.Core.register_orchestration_variable(variable)
      :ok
  """
  @spec register_orchestration_variable(orchestration_variable()) :: :ok | {:error, term()}
  def register_orchestration_variable(variable) do
    GenServer.call(__MODULE__, {:register_variable, variable})
  end

  @doc """
  Coordinate the system using all registered variables.

  ## Parameters
  - `context` - Optional coordination context (default: %{})

  ## Returns
  - `{:ok, [coordination_result()]}` - Coordination completed
  - `{:error, reason}` - Coordination failed

  ## Examples

      iex> Foundation.MABEAM.Core.coordinate_system()
      {:ok, []}

      iex> context = %{task_type: :computation, load: :medium}
      iex> Foundation.MABEAM.Core.coordinate_system(context)
      {:ok, [%{variable_id: :test_var, result: {:ok, :completed}}]}
  """
  @spec coordinate_system(map()) :: {:ok, [coordination_result()]} | {:error, term()}
  def coordinate_system(context \\ %{}) do
    GenServer.call(__MODULE__, {:coordinate_system, context})
  end

  @doc """
  Get the current system status including variables and metrics.

  ## Returns
  - `{:ok, system_status()}` - Current status
  - `{:error, reason}` - Status retrieval failed

  ## Examples

      iex> {:ok, status} = Foundation.MABEAM.Core.system_status()
      iex> is_map(status.variable_registry)
      true
  """
  @spec system_status() :: {:ok, system_status()} | {:error, term()}
  def system_status do
    GenServer.call(__MODULE__, :system_status)
  end

  @doc """
  Perform a health check on the Core orchestrator.

  ## Returns
  - `{:ok, health_info}` - Health check data
  - `{:error, reason}` - Health check failed

  ## Examples

      iex> {:ok, health} = Foundation.MABEAM.Core.health_check()
      iex> health.status in [:healthy, :degraded, :unhealthy]
      true
  """
  @spec health_check() :: {:ok, map()} | {:error, term()}
  def health_check do
    GenServer.call(__MODULE__, :health_check)
  end

  # ============================================================================
  # ServiceBehaviour Required Callbacks
  # ============================================================================

  @impl Foundation.Services.ServiceBehaviour
  def service_config do
    %{
      health_check_interval: 30_000,
      graceful_shutdown_timeout: 10_000,
      dependencies: [Foundation.ProcessRegistry, Foundation.ServiceRegistry, Foundation.Telemetry],
      telemetry_enabled: true,
      resource_monitoring: true
    }
  end

  @impl Foundation.Services.ServiceBehaviour
  def handle_health_check(state) do
    # Perform health checks
    checks = %{
      process_registry: check_process_registry(),
      service_registry: check_service_registry(),
      telemetry: check_telemetry_service(),
      variables: check_variable_registry(state),
      memory: check_memory_usage()
    }

    # Determine overall health status
    status = determine_health_status(checks)

    _health_info = %{
      status: status,
      checks: checks,
      timestamp: DateTime.utc_now(),
      uptime_ms: DateTime.diff(DateTime.utc_now(), state.startup_time, :millisecond)
    }

    {:ok, status, Map.put(state, :last_health_check, DateTime.utc_now())}
  end

  # ============================================================================
  # GenServer Implementation
  # ============================================================================

  @doc false
  def init_service(opts) do
    config = Keyword.get(opts, :config, %{})

    # Initialize Core-specific state
    core_state = %{
      variable_registry: %{},
      coordination_history: [],
      performance_metrics: %{
        coordination_count: 0,
        variable_count: 0,
        avg_coordination_time_ms: 0.0,
        success_rate: 1.0,
        error_count: 0
      }
    }

    # Merge with user config
    final_config = Map.merge(default_core_config(), config)

    # Note: ServiceBehaviour handles registration automatically
    setup_telemetry()
    {:ok, Map.put(core_state, :config, final_config)}
  end

  @impl GenServer
  def handle_call({:register_variable, variable}, _from, state) do
    case validate_orchestration_variable(variable) do
      {:ok, validated_variable} ->
        if Map.has_key?(state.variable_registry, variable.id) do
          {:reply, {:error, :variable_already_exists}, state}
        else
          new_registry = Map.put(state.variable_registry, variable.id, validated_variable)
          new_metrics = update_variable_metrics(state.performance_metrics, :add)

          new_state = %{state | variable_registry: new_registry, performance_metrics: new_metrics}

          # Emit telemetry event
          emit_variable_registered_event(validated_variable)

          # Emit Foundation event
          emit_foundation_event(:variable_registered, %{
            variable_id: variable.id,
            variable_type: variable.type,
            scope: variable.scope
          })

          {:reply, :ok, new_state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl GenServer
  def handle_call({:coordinate_system, context}, _from, state) do
    start_time = System.monotonic_time(:millisecond)

    # Emit coordination start telemetry
    :telemetry.execute([:mabeam, :coordination, :start], %{count: 1}, %{
      context: context,
      variable_count: map_size(state.variable_registry)
    })

    # Perform coordination
    results = coordinate_variables(state.variable_registry, context)

    # Calculate timing
    end_time = System.monotonic_time(:millisecond)
    duration_ms = end_time - start_time

    # Create coordination event
    event = %{
      id: generate_event_id(),
      type: :coordination_complete,
      timestamp: DateTime.utc_now(),
      variables: Map.keys(state.variable_registry),
      result: results,
      duration_ms: duration_ms,
      metadata: %{context: context}
    }

    # Update state
    # Keep last 100 events
    new_history = [event | Enum.take(state.coordination_history, 99)]
    new_metrics = update_coordination_metrics(state.performance_metrics, results, duration_ms)

    new_state = %{state | coordination_history: new_history, performance_metrics: new_metrics}

    # Emit coordination stop telemetry
    :telemetry.execute(
      [:mabeam, :coordination, :stop],
      %{
        duration: duration_ms,
        result_count: length(results)
      },
      %{success: true}
    )

    {:reply, {:ok, results}, new_state}
  end

  @impl GenServer
  def handle_call(:system_status, _from, state) do
    status = %{
      variable_registry: state.variable_registry,
      coordination_history: state.coordination_history,
      performance_metrics: state.performance_metrics,
      config: state.config
    }

    {:reply, {:ok, status}, state}
  end

  @impl GenServer
  def handle_call(:health_check, _from, state) do
    case handle_health_check(state) do
      {:ok, status, new_state} ->
        health_info = %{
          status: status,
          checks: %{
            process_registry: check_process_registry(),
            telemetry: check_telemetry_service(),
            variables: check_variable_registry(state)
          },
          metrics: state.performance_metrics,
          uptime_ms: DateTime.diff(DateTime.utc_now(), state.startup_time, :millisecond)
        }

        {:reply, {:ok, health_info}, new_state}
    end
  end

  @impl GenServer
  def handle_call(:ping, _from, state) do
    {:reply, :pong, state}
  end

  @impl GenServer
  def handle_call(:get_metrics, _from, state) do
    metrics = %{
      variable_count: map_size(state.variable_registry),
      coordination_count: state.performance_metrics.coordination_count,
      success_rate: state.performance_metrics.success_rate,
      avg_coordination_time_ms: state.performance_metrics.avg_coordination_time_ms,
      error_count: state.performance_metrics.error_count,
      uptime_ms: DateTime.diff(DateTime.utc_now(), state.startup_time, :millisecond),
      health_status: state.health_status,
      memory_usage: state.metrics.memory_usage
    }

    {:reply, {:ok, metrics}, state}
  end

  # ============================================================================
  # Private Implementation Functions
  # ============================================================================

  defp default_core_config do
    %{
      max_variables: 1000,
      coordination_timeout: 5000,
      history_retention: 100,
      telemetry_enabled: true
    }
  end

  defp validate_orchestration_variable(variable) do
    required_fields = [:id, :scope, :type, :agents, :coordination_fn, :adaptation_fn]

    missing_fields =
      Enum.filter(required_fields, fn field ->
        not Map.has_key?(variable, field)
      end)

    if Enum.empty?(missing_fields) do
      # Additional validation can be added here
      {:ok, variable}
    else
      {:error, "Missing required fields: #{inspect(missing_fields)}"}
    end
  end

  defp coordinate_variables(variables, context) do
    variables
    |> Enum.map(fn {id, variable} ->
      coordinate_single_variable(id, variable, context)
    end)
    |> Enum.filter(fn result -> result != nil end)
  end

  defp coordinate_single_variable(id, variable, context) do
    start_time = System.monotonic_time(:millisecond)

    try do
      case variable.coordination_fn.(variable.agents, context, variable) do
        {:ok, result} ->
          duration = System.monotonic_time(:millisecond) - start_time

          %{
            variable_id: id,
            result: {:ok, result},
            duration_ms: duration,
            metadata: %{success: true}
          }

        {:error, reason} ->
          duration = System.monotonic_time(:millisecond) - start_time

          %{
            variable_id: id,
            result: {:error, reason},
            duration_ms: duration,
            metadata: %{success: false, reason: reason}
          }
      end
    rescue
      error ->
        duration = System.monotonic_time(:millisecond) - start_time

        %{
          variable_id: id,
          result: {:error, :coordination_exception},
          duration_ms: duration,
          metadata: %{success: false, error: inspect(error)}
        }
    end
  end

  defp update_variable_metrics(metrics, :add) do
    %{metrics | variable_count: metrics.variable_count + 1}
  end

  defp update_coordination_metrics(metrics, results, duration_ms) do
    success_count =
      Enum.count(results, fn %{result: result} ->
        match?({:ok, _}, result)
      end)

    total_count = length(results)
    new_coordination_count = metrics.coordination_count + 1

    # Update average coordination time
    new_avg_time =
      if new_coordination_count == 1 do
        duration_ms * 1.0
      else
        (metrics.avg_coordination_time_ms * metrics.coordination_count + duration_ms) /
          new_coordination_count
      end

    # Update success rate
    new_success_rate =
      if total_count > 0 do
        success_count / total_count
      else
        metrics.success_rate
      end

    error_count = total_count - success_count

    %{
      metrics
      | coordination_count: new_coordination_count,
        avg_coordination_time_ms: new_avg_time,
        success_rate: new_success_rate,
        error_count: metrics.error_count + error_count
    }
  end

  defp setup_telemetry do
    # Register with ProcessRegistry for service discovery
    ProcessRegistry.register(:production, __MODULE__, self())

    :telemetry.execute([:mabeam, :core, :started], %{count: 1}, %{
      module: __MODULE__,
      timestamp: DateTime.utc_now()
    })
  end

  defp emit_variable_registered_event(variable) do
    :telemetry.execute([:mabeam, :variable, :registered], %{count: 1}, %{
      variable_id: variable.id,
      variable_type: variable.type,
      scope: variable.scope
    })
  end

  defp emit_foundation_event(type, metadata) do
    case Events.new_event(type, metadata, correlation_id: generate_event_id()) do
      {:ok, event} -> Events.store(event)
      # Log error in production
      {:error, _reason} -> :ok
    end
  end

  defp generate_event_id do
    "mabeam_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  # Health check helpers
  defp check_process_registry do
    case ProcessRegistry.lookup(:production, __MODULE__) do
      {:ok, _pid} -> :healthy
      :error -> :unhealthy
    end
  end

  defp check_service_registry do
    case ServiceRegistry.lookup(:production, __MODULE__) do
      {:ok, _info} -> :healthy
      # Not critical for basic operation
      {:error, _} -> :degraded
    end
  end

  defp check_telemetry_service do
    # Basic check - if telemetry is loaded and working
    :telemetry.execute([:mabeam, :health_check, :test], %{}, %{})
    :healthy
  rescue
    _ -> :degraded
  end

  defp check_variable_registry(state) do
    if is_map(state.variable_registry) do
      :healthy
    else
      :unhealthy
    end
  end

  defp check_memory_usage do
    {:memory, memory} = :erlang.process_info(self(), :memory)
    # 100MB threshold
    if memory < 100_000_000 do
      :healthy
    else
      :degraded
    end
  end

  defp determine_health_status(checks) do
    unhealthy_count = Enum.count(checks, fn {_key, status} -> status == :unhealthy end)
    degraded_count = Enum.count(checks, fn {_key, status} -> status == :degraded end)

    cond do
      unhealthy_count > 0 -> :unhealthy
      degraded_count > 2 -> :degraded
      true -> :healthy
    end
  end
end
