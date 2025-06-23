defmodule Foundation.MABEAM.Core do
  @moduledoc """
  Universal Variable Orchestrator for multi-agent coordination on the BEAM.
  
  Provides the core infrastructure for variables to coordinate agents across
  the entire BEAM cluster, managing agent lifecycle, resource allocation,
  and adaptive behavior based on collective performance.
  
  ## Features
  
  - Universal variable registration and management
  - System-wide coordination protocols  
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
  
  All data structures are 100% serializable for distribution readiness.
  """
  
  use GenServer
  
  # Note: Keeping aliases for future use in integration
  
  @type orchestrator_state :: %{
    variable_registry: %{atom() => orchestration_variable()},
    coordination_history: [coordination_event()],
    performance_metrics: performance_metrics(),
    service_config: map(),
    startup_time: DateTime.t()
  }
  
  @type orchestration_variable :: %{
    id: atom(),
    scope: :local | :global | :cluster,
    type: :agent_selection | :resource_allocation | :communication_topology,
    agents: [atom()],
    coordination_fn: function(),
    adaptation_fn: function(),
    constraints: [term()],
    resource_requirements: %{memory: number(), cpu: number()},
    fault_tolerance: %{strategy: atom(), max_restarts: non_neg_integer()},
    telemetry_config: %{enabled: boolean()},
    created_at: DateTime.t(),
    metadata: map()
  }
  
  @type coordination_event :: %{
    id: String.t(),
    type: :coordination_start | :coordination_complete | :coordination_error | :variable_registered,
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
    total_errors: non_neg_integer()
  }
  
  ## Public API
  
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @spec system_status() :: {:ok, map()}
  def system_status() do
    GenServer.call(__MODULE__, :system_status)
  end
  
  @spec health_check() :: {:ok, :healthy | :degraded | :unhealthy}
  def health_check() do
    GenServer.call(__MODULE__, :health_check)
  end
  
  @spec update_configuration(map()) :: :ok
  def update_configuration(config) do
    GenServer.call(__MODULE__, {:update_configuration, config})
  end
  
  @spec register_orchestration_variable(orchestration_variable()) :: :ok | {:error, term()}
  def register_orchestration_variable(variable) do
    GenServer.call(__MODULE__, {:register_variable, variable})
  end
  
  @spec update_orchestration_variable(atom(), orchestration_variable()) :: :ok | {:error, term()}
  def update_orchestration_variable(variable_id, variable) do
    GenServer.call(__MODULE__, {:update_variable, variable_id, variable})
  end
  
  @spec unregister_orchestration_variable(atom()) :: :ok | {:error, term()}
  def unregister_orchestration_variable(variable_id) do
    GenServer.call(__MODULE__, {:unregister_variable, variable_id})
  end
  
  @spec list_orchestration_variables() :: {:ok, [{atom(), orchestration_variable()}]}
  def list_orchestration_variables() do
    GenServer.call(__MODULE__, :list_variables)
  end
  
  @spec coordinate_system() :: {:ok, [coordination_result()]}
  def coordinate_system() do
    GenServer.call(__MODULE__, :coordinate_system, 30_000)
  end
  
  @spec coordinate_variable(atom()) :: {:ok, coordination_result()} | {:error, term()}
  def coordinate_variable(variable_id) do
    GenServer.call(__MODULE__, {:coordinate_variable, variable_id}, 30_000)
  end
  
  @spec get_performance_metrics() :: {:ok, performance_metrics()}
  def get_performance_metrics() do
    GenServer.call(__MODULE__, :get_performance_metrics)
  end
  
  @spec get_coordination_history() :: {:ok, [coordination_event()]}
  def get_coordination_history() do
    GenServer.call(__MODULE__, :get_coordination_history)
  end
  
  @spec get_system_statistics() :: {:ok, map()}
  def get_system_statistics() do
    GenServer.call(__MODULE__, :get_system_statistics)
  end
  
  ## GenServer Implementation
  
  @impl true
  def init(opts) do
    test_mode = Keyword.get(opts, :test_mode, false)
    
    state = %{
      variable_registry: %{},
      coordination_history: [],
      performance_metrics: %{
        coordination_count: 0,
        variable_count: 0,
        avg_coordination_time_ms: 0.0,
        success_rate: 1.0,
        total_errors: 0
      },
      service_config: %{
        coordination_timeout: 5000,
        max_variables: 1000,
        telemetry_enabled: true
      },
      startup_time: DateTime.utc_now(),
      test_mode: test_mode
    }
    
    emit_telemetry(:service_started, %{}, %{test_mode: test_mode})
    {:ok, state}
  end
  
  @impl true
  def handle_call(:system_status, _from, state) do
    status = %{
      variable_registry: state.variable_registry,
      coordination_history: Enum.take(state.coordination_history, 10),
      performance_metrics: state.performance_metrics,
      service_config: state.service_config,
      uptime_seconds: DateTime.diff(DateTime.utc_now(), state.startup_time, :second)
    }
    {:reply, {:ok, status}, state}
  end
  
  @impl true
  def handle_call(:health_check, _from, state) do
    # Simple health check - can be enhanced with dependency checks
    health_status = cond do
      map_size(state.variable_registry) > state.service_config.max_variables ->
        :degraded
      state.performance_metrics.success_rate < 0.8 ->
        :degraded
      true ->
        :healthy
    end
    
    {:reply, {:ok, health_status}, state}
  end
  
  @impl true
  def handle_call({:update_configuration, config}, _from, state) do
    new_config = Map.merge(state.service_config, config)
    new_state = %{state | service_config: new_config}
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call({:register_variable, variable}, _from, state) do
    case validate_variable(variable) do
      :ok ->
        if Map.has_key?(state.variable_registry, variable.id) do
          {:reply, {:error, :already_registered}, state}
        else
          new_registry = Map.put(state.variable_registry, variable.id, variable)
          new_metrics = %{state.performance_metrics | 
            variable_count: map_size(new_registry)
          }
          
          new_state = %{state | 
            variable_registry: new_registry,
            performance_metrics: new_metrics
          }
          
          emit_telemetry(:variable_registered, %{count: 1}, %{
            variable_id: variable.id,
            variable_type: variable.type,
            scope: variable.scope
          })
          
          new_state_with_event = add_coordination_event(new_state, :variable_registered, [variable.id], {:ok, :registered})
          
          {:reply, :ok, new_state_with_event}
        end
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:update_variable, variable_id, variable}, _from, state) do
    case validate_variable(variable) do
      :ok ->
        if Map.has_key?(state.variable_registry, variable_id) do
          new_registry = Map.put(state.variable_registry, variable_id, variable)
          new_state = %{state | variable_registry: new_registry}
          {:reply, :ok, new_state}
        else
          {:reply, {:error, :variable_not_found}, state}
        end
      
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  @impl true
  def handle_call({:unregister_variable, variable_id}, _from, state) do
    if Map.has_key?(state.variable_registry, variable_id) do
      new_registry = Map.delete(state.variable_registry, variable_id)
      new_metrics = %{state.performance_metrics | 
        variable_count: map_size(new_registry)
      }
      
      new_state = %{state | 
        variable_registry: new_registry,
        performance_metrics: new_metrics
      }
      
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :variable_not_found}, state}
    end
  end
  
  @impl true
  def handle_call(:list_variables, _from, state) do
    variable_list = Enum.map(state.variable_registry, fn {id, variable} -> {id, variable} end)
    {:reply, {:ok, variable_list}, state}
  end
  
  @impl true
  def handle_call(:coordinate_system, _from, state) do
    start_time = System.monotonic_time(:millisecond)
    
    emit_telemetry(:coordination_start, %{variable_count: map_size(state.variable_registry)}, %{
      type: :system_coordination
    })
    
    results = Enum.map(state.variable_registry, fn {variable_id, variable} ->
      coordinate_single_variable(variable_id, variable, state)
    end)
    
    end_time = System.monotonic_time(:millisecond)
    duration = end_time - start_time
    
    # Update performance metrics
    new_metrics = update_performance_metrics(state.performance_metrics, results, duration)
    
    # Add to coordination history
    new_state = add_coordination_event(
      %{state | performance_metrics: new_metrics},
      :coordination_complete,
      Map.keys(state.variable_registry),
      {:ok, results},
      duration
    )
    
    emit_telemetry(:coordination_complete, %{
      duration: duration,
      variable_count: length(results),
      success_count: Enum.count(results, fn result -> match?({:ok, _}, result.result) end)
    }, %{type: :system_coordination})
    
    {:reply, {:ok, results}, new_state}
  end
  
  @impl true
  def handle_call({:coordinate_variable, variable_id}, _from, state) do
    case Map.get(state.variable_registry, variable_id) do
      nil ->
        {:reply, {:error, :variable_not_found}, state}
      
      variable ->
        start_time = System.monotonic_time(:millisecond)
        
        emit_telemetry(:coordination_start, %{variable_count: 1}, %{
          type: :variable_coordination,
          variable_id: variable_id
        })
        
        result = coordinate_single_variable(variable_id, variable, state)
        
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time
        
        # Update performance metrics
        new_metrics = update_performance_metrics(state.performance_metrics, [result], duration)
        
        # Add to coordination history
        new_state = add_coordination_event(
          %{state | performance_metrics: new_metrics},
          :coordination_complete,
          [variable_id],
          result.result,
          duration
        )
        
        emit_telemetry(:coordination_complete, %{
          duration: duration,
          variable_count: 1,
          success_count: if(match?({:ok, _}, result.result), do: 1, else: 0)
        }, %{
          type: :variable_coordination,
          variable_id: variable_id
        })
        
        {:reply, {:ok, result}, new_state}
    end
  end
  
  @impl true
  def handle_call(:get_performance_metrics, _from, state) do
    {:reply, {:ok, state.performance_metrics}, state}
  end
  
  @impl true
  def handle_call(:get_coordination_history, _from, state) do
    # Return most recent events first
    history = Enum.reverse(state.coordination_history)
    {:reply, {:ok, history}, state}
  end
  
  @impl true
  def handle_call(:get_system_statistics, _from, state) do
    uptime_seconds = DateTime.diff(DateTime.utc_now(), state.startup_time, :second)
    
    stats = %{
      total_variables: state.performance_metrics.variable_count,
      total_coordinations: state.performance_metrics.coordination_count,
      success_rate: state.performance_metrics.success_rate,
      avg_response_time_ms: state.performance_metrics.avg_coordination_time_ms,
      uptime_seconds: uptime_seconds,
      total_errors: state.performance_metrics.total_errors
    }
    
    {:reply, {:ok, stats}, state}
  end
  
  ## Private Functions
  
  defp validate_variable(variable) do
    required_fields = [:id, :scope, :type, :agents, :coordination_fn, :adaptation_fn]
    
    cond do
      not is_map(variable) ->
        {:error, :invalid_variable_format}
      
      not Enum.all?(required_fields, &Map.has_key?(variable, &1)) ->
        {:error, :missing_required_fields}
      
      not is_atom(variable.id) or variable.id == nil ->
        {:error, :invalid_variable_id}
      
      variable.scope not in [:local, :global, :cluster] ->
        {:error, :invalid_scope}
      
      variable.type not in [:agent_selection, :resource_allocation, :communication_topology] ->
        {:error, :invalid_type}
      
      not is_list(variable.agents) ->
        {:error, :invalid_agents_list}
      
      not is_function(variable.coordination_fn, 3) ->
        {:error, :invalid_coordination_function}
      
      not is_function(variable.adaptation_fn, 3) ->
        {:error, :invalid_adaptation_function}
      
      true ->
        :ok
    end
  end
  
  defp coordinate_single_variable(variable_id, variable, state) do
    start_time = System.monotonic_time(:millisecond)
    
    try do
      # Call the variable's coordination function
      context = %{
        variable_id: variable_id,
        coordination_timeout: state.service_config.coordination_timeout,
        timestamp: DateTime.utc_now()
      }
      
      coordination_result = variable.coordination_fn.(variable.agents, context, variable.metadata)
      
      # Apply adaptation function if coordination succeeded
      final_result = case coordination_result do
        {:ok, coord_result} ->
          case variable.adaptation_fn.(coord_result, context, variable.metadata) do
            {:ok, adapted_result} -> {:ok, adapted_result}
            {:error, adapt_error} -> {:error, {:adaptation_failed, adapt_error}}
          end
        
        {:error, _} = error ->
          error
      end
      
      end_time = System.monotonic_time(:millisecond)
      duration = end_time - start_time
      
      %{
        variable_id: variable_id,
        result: final_result,
        duration_ms: duration,
        metadata: %{
          coordination_type: variable.type,
          agent_count: length(variable.agents),
          timestamp: DateTime.utc_now()
        }
      }
      
    rescue
      error ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time
        
        %{
          variable_id: variable_id,
          result: {:error, {:coordination_exception, Exception.message(error)}},
          duration_ms: duration,
          metadata: %{
            error: Exception.message(error),
            timestamp: DateTime.utc_now()
          }
        }
    end
  end
  
  defp update_performance_metrics(current_metrics, results, total_duration) do
    coordination_count = current_metrics.coordination_count + length(results)
    
    successful_results = Enum.count(results, fn result ->
      match?({:ok, _}, result.result)
    end)
    
    error_count = length(results) - successful_results
    total_errors = current_metrics.total_errors + error_count
    
    success_rate = if coordination_count > 0 do
      (coordination_count - total_errors) / coordination_count
    else
      1.0
    end
    
    # Calculate new average coordination time
    current_total_time = current_metrics.avg_coordination_time_ms * current_metrics.coordination_count
    new_total_time = current_total_time + total_duration
    avg_coordination_time_ms = if coordination_count > 0 do
      new_total_time / coordination_count
    else
      0.0
    end
    
    %{
      coordination_count: coordination_count,
      variable_count: current_metrics.variable_count,
      avg_coordination_time_ms: avg_coordination_time_ms,
      success_rate: success_rate,
      total_errors: total_errors
    }
  end
  
  defp add_coordination_event(state, event_type, variables, result, duration \\ nil) do
    event = %{
      id: generate_event_id(),
      type: event_type,
      timestamp: DateTime.utc_now(),
      variables: variables,
      result: result,
      duration_ms: duration,
      metadata: %{}
    }
    
    # Keep only the last 100 events to prevent memory growth
    new_history = [event | state.coordination_history] |> Enum.take(100)
    
    %{state | coordination_history: new_history}
  end
  
  defp generate_event_id() do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
  
  defp emit_telemetry(event, measurements, metadata) do
    :telemetry.execute(
      [:foundation, :mabeam, :core, event],
      measurements,
      metadata
    )
  end
end