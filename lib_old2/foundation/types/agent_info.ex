defmodule Foundation.Types.AgentInfo do
  @moduledoc """
  Comprehensive agent information and metadata type system.

  Provides structured types for representing agent state, capabilities,
  health, and metadata in Foundation's multi-agent environment. Designed
  to support rich agent coordination, monitoring, and management features.

  ## Features

  - **Agent Lifecycle**: Complete agent state tracking from registration to termination
  - **Capability Management**: Dynamic capability registration and discovery
  - **Health Monitoring**: Multi-dimensional health assessment and reporting
  - **Resource Tracking**: Agent resource usage and allocation monitoring
  - **Coordination Context**: Agent coordination state and participation tracking
  - **Performance Metrics**: Agent performance data and trend analysis

  ## Agent States

  - `:initializing` - Agent is starting up and configuring
  - `:ready` - Agent is ready to accept work
  - `:active` - Agent is actively processing tasks
  - `:idle` - Agent is running but not currently processing
  - `:degraded` - Agent is functioning but with reduced capacity
  - `:maintenance` - Agent is in maintenance mode
  - `:stopping` - Agent is shutting down gracefully
  - `:stopped` - Agent has stopped completely

  ## Usage

      # Create agent info
      agent_info = AgentInfo.new(%{
        agent_id: :ml_agent_1,
        capability: :inference,
        initial_state: :initializing
      })

      # Update agent state
      {:ok, updated_info} = AgentInfo.update_state(agent_info, :ready)

      # Add capabilities
      {:ok, updated_info} = AgentInfo.add_capability(updated_info, :training)

      # Update health metrics
      {:ok, updated_info} = AgentInfo.update_health(updated_info, :healthy, %{
        memory_usage: 0.7,
        cpu_usage: 0.4
      })
  """

  @type agent_id :: atom() | String.t()
  @type capability :: atom()
  @type agent_state :: :initializing | :ready | :active | :idle | :degraded | :maintenance | :stopping | :stopped
  @type health_status :: :healthy | :degraded | :unhealthy | :unknown
  @type resource_type :: :memory | :cpu | :network | :storage | :gpu | atom()

  @type resource_usage :: %{
    resource_type() => float() | non_neg_integer()
  }

  @type health_metrics :: %{
    overall_health: health_status(),
    resource_health: %{resource_type() => health_status()},
    performance_health: health_status(),
    coordination_health: health_status(),
    last_health_check: DateTime.t(),
    health_trend: :improving | :stable | :degrading,
    health_score: float()
  }

  @type performance_metrics :: %{
    tasks_completed: non_neg_integer(),
    tasks_failed: non_neg_integer(),
    average_task_duration: float(),
    throughput_per_second: float(),
    error_rate: float(),
    success_rate: float(),
    last_performance_update: DateTime.t()
  }

  @type coordination_state :: %{
    active_consensus: [atom()],
    active_barriers: [atom()],
    held_locks: [String.t()],
    leadership_roles: [atom()],
    coordination_score: float(),
    last_coordination_activity: DateTime.t() | nil
  }

  @type agent_configuration :: %{
    startup_parameters: map(),
    runtime_configuration: map(),
    capability_configuration: %{capability() => map()},
    resource_limits: resource_usage(),
    coordination_preferences: map()
  }

  defstruct [
    :agent_id,
    :state,
    :capabilities,
    :health_metrics,
    :resource_usage,
    :performance_metrics,
    :coordination_state,
    :configuration,
    :metadata,
    :created_at,
    :last_updated,
    :version
  ]

  @type t :: %__MODULE__{
    agent_id: agent_id(),
    state: agent_state(),
    capabilities: MapSet.t(capability()),
    health_metrics: health_metrics(),
    resource_usage: resource_usage(),
    performance_metrics: performance_metrics(),
    coordination_state: coordination_state(),
    configuration: agent_configuration(),
    metadata: map(),
    created_at: DateTime.t(),
    last_updated: DateTime.t(),
    version: non_neg_integer()
  }

  @doc """
  Create a new agent info structure with default values.

  ## Parameters
  - `params`: Map containing initial agent parameters

  ## Required Parameters
  - `:agent_id` - Unique identifier for the agent

  ## Optional Parameters
  - `:capability` or `:capabilities` - Initial agent capabilities
  - `:initial_state` - Starting state (defaults to :initializing)
  - `:configuration` - Initial configuration
  - `:metadata` - Additional metadata

  ## Examples

      # Basic agent
      agent_info = AgentInfo.new(%{agent_id: :simple_agent})

      # ML agent with capabilities
      agent_info = AgentInfo.new(%{
        agent_id: :ml_agent_1,
        capabilities: [:inference, :training],
        initial_state: :ready,
        metadata: %{model_type: "transformer"}
      })
  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(params) do
    case validate_required_params(params) do
      :ok ->
        agent_info = %__MODULE__{
          agent_id: params.agent_id,
          state: Map.get(params, :initial_state, :initializing),
          capabilities: extract_capabilities(params),
          health_metrics: initialize_health_metrics(),
          resource_usage: %{},
          performance_metrics: initialize_performance_metrics(),
          coordination_state: initialize_coordination_state(),
          configuration: Map.get(params, :configuration, %{}),
          metadata: Map.get(params, :metadata, %{}),
          created_at: DateTime.utc_now(),
          last_updated: DateTime.utc_now(),
          version: 1
        }

        {:ok, agent_info}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Create a new agent info structure, raising on error.
  """
  @spec new!(map()) :: t()
  def new!(params) do
    case new(params) do
      {:ok, agent_info} -> agent_info
      {:error, reason} -> raise ArgumentError, "Invalid agent info: #{inspect(reason)}"
    end
  end

  @doc """
  Update the agent's state.

  ## Examples

      {:ok, updated_info} = AgentInfo.update_state(agent_info, :active)
  """
  @spec update_state(t(), agent_state()) :: {:ok, t()} | {:error, term()}
  def update_state(%__MODULE__{} = agent_info, new_state) do
    case validate_state_transition(agent_info.state, new_state) do
      :ok ->
        updated_info = %{agent_info |
          state: new_state,
          last_updated: DateTime.utc_now(),
          version: agent_info.version + 1
        }

        {:ok, updated_info}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Add a capability to the agent.

  ## Examples

      {:ok, updated_info} = AgentInfo.add_capability(agent_info, :training)
  """
  @spec add_capability(t(), capability()) :: {:ok, t()}
  def add_capability(%__MODULE__{} = agent_info, capability) do
    updated_capabilities = MapSet.put(agent_info.capabilities, capability)

    updated_info = %{agent_info |
      capabilities: updated_capabilities,
      last_updated: DateTime.utc_now(),
      version: agent_info.version + 1
    }

    {:ok, updated_info}
  end

  @doc """
  Remove a capability from the agent.

  ## Examples

      {:ok, updated_info} = AgentInfo.remove_capability(agent_info, :training)
  """
  @spec remove_capability(t(), capability()) :: {:ok, t()}
  def remove_capability(%__MODULE__{} = agent_info, capability) do
    updated_capabilities = MapSet.delete(agent_info.capabilities, capability)

    updated_info = %{agent_info |
      capabilities: updated_capabilities,
      last_updated: DateTime.utc_now(),
      version: agent_info.version + 1
    }

    {:ok, updated_info}
  end

  @doc """
  Update the agent's health metrics.

  ## Examples

      {:ok, updated_info} = AgentInfo.update_health(agent_info, :healthy, %{
        memory_usage: 0.7,
        cpu_usage: 0.4
      })
  """
  @spec update_health(t(), health_status(), map()) :: {:ok, t()}
  def update_health(%__MODULE__{} = agent_info, overall_health, resource_metrics \\ %{}) do
    current_health = agent_info.health_metrics

    updated_health = %{current_health |
      overall_health: overall_health,
      resource_health: calculate_resource_health(resource_metrics),
      last_health_check: DateTime.utc_now(),
      health_trend: calculate_health_trend(current_health.overall_health, overall_health),
      health_score: calculate_health_score(overall_health, resource_metrics)
    }

    updated_info = %{agent_info |
      health_metrics: updated_health,
      resource_usage: Map.merge(agent_info.resource_usage, resource_metrics),
      last_updated: DateTime.utc_now(),
      version: agent_info.version + 1
    }

    {:ok, updated_info}
  end

  @doc """
  Update the agent's performance metrics.

  ## Examples

      {:ok, updated_info} = AgentInfo.update_performance(agent_info, %{
        tasks_completed: 150,
        average_task_duration: 250.5
      })
  """
  @spec update_performance(t(), map()) :: {:ok, t()}
  def update_performance(%__MODULE__{} = agent_info, performance_data) do
    current_performance = agent_info.performance_metrics

    updated_performance = Map.merge(current_performance, performance_data)
    |> Map.put(:last_performance_update, DateTime.utc_now())
    |> calculate_derived_performance_metrics()

    updated_info = %{agent_info |
      performance_metrics: updated_performance,
      last_updated: DateTime.utc_now(),
      version: agent_info.version + 1
    }

    {:ok, updated_info}
  end

  @doc """
  Update the agent's coordination state.

  ## Examples

      {:ok, updated_info} = AgentInfo.update_coordination(agent_info, %{
        active_consensus: [:model_selection],
        held_locks: ["resource_1", "resource_2"]
      })
  """
  @spec update_coordination(t(), map()) :: {:ok, t()}
  def update_coordination(%__MODULE__{} = agent_info, coordination_data) do
    current_coordination = agent_info.coordination_state

    updated_coordination = Map.merge(current_coordination, coordination_data)
    |> Map.put(:last_coordination_activity, DateTime.utc_now())
    |> calculate_coordination_score()

    updated_info = %{agent_info |
      coordination_state: updated_coordination,
      last_updated: DateTime.utc_now(),
      version: agent_info.version + 1
    }

    {:ok, updated_info}
  end

  @doc """
  Check if the agent has a specific capability.

  ## Examples

      AgentInfo.has_capability?(agent_info, :inference)
      #=> true
  """
  @spec has_capability?(t(), capability()) :: boolean()
  def has_capability?(%__MODULE__{} = agent_info, capability) do
    MapSet.member?(agent_info.capabilities, capability)
  end

  @doc """
  Check if the agent is in a healthy state.

  ## Examples

      AgentInfo.healthy?(agent_info)
      #=> true
  """
  @spec healthy?(t()) :: boolean()
  def healthy?(%__MODULE__{} = agent_info) do
    agent_info.health_metrics.overall_health == :healthy and
    agent_info.state in [:ready, :active, :idle]
  end

  @doc """
  Check if the agent is available for work.

  ## Examples

      AgentInfo.available?(agent_info)
      #=> true
  """
  @spec available?(t()) :: boolean()
  def available?(%__MODULE__{} = agent_info) do
    agent_info.state in [:ready, :idle] and
    agent_info.health_metrics.overall_health in [:healthy, :degraded]
  end

  @doc """
  Get a summary of the agent's current status.

  ## Examples

      AgentInfo.status_summary(agent_info)
      #=> %{state: :active, health: :healthy, capabilities: 3, load: :medium}
  """
  @spec status_summary(t()) :: map()
  def status_summary(%__MODULE__{} = agent_info) do
    %{
      agent_id: agent_info.agent_id,
      state: agent_info.state,
      health: agent_info.health_metrics.overall_health,
      capabilities: MapSet.size(agent_info.capabilities),
      capability_list: MapSet.to_list(agent_info.capabilities),
      load: determine_load_level(agent_info),
      coordination_active: coordination_active?(agent_info),
      last_updated: agent_info.last_updated,
      version: agent_info.version
    }
  end

  @doc """
  Convert agent info to a map suitable for JSON serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = agent_info) do
    %{
      agent_id: agent_info.agent_id,
      state: agent_info.state,
      capabilities: MapSet.to_list(agent_info.capabilities),
      health_metrics: serialize_health_metrics(agent_info.health_metrics),
      resource_usage: agent_info.resource_usage,
      performance_metrics: serialize_performance_metrics(agent_info.performance_metrics),
      coordination_state: serialize_coordination_state(agent_info.coordination_state),
      configuration: agent_info.configuration,
      metadata: agent_info.metadata,
      created_at: DateTime.to_iso8601(agent_info.created_at),
      last_updated: DateTime.to_iso8601(agent_info.last_updated),
      version: agent_info.version
    }
  end

  @doc """
  Create agent info from a serialized map.
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(agent_map) do
    try do
      agent_info = %__MODULE__{
        agent_id: atomize_key(Map.get(agent_map, "agent_id")),
        state: atomize_key(Map.get(agent_map, "state")),
        capabilities: MapSet.new(Map.get(agent_map, "capabilities", [])),
        health_metrics: deserialize_health_metrics(Map.get(agent_map, "health_metrics", %{})),
        resource_usage: Map.get(agent_map, "resource_usage", %{}),
        performance_metrics: deserialize_performance_metrics(Map.get(agent_map, "performance_metrics", %{})),
        coordination_state: deserialize_coordination_state(Map.get(agent_map, "coordination_state", %{})),
        configuration: Map.get(agent_map, "configuration", %{}),
        metadata: Map.get(agent_map, "metadata", %{}),
        created_at: parse_datetime(Map.get(agent_map, "created_at")),
        last_updated: parse_datetime(Map.get(agent_map, "last_updated")),
        version: Map.get(agent_map, "version", 1)
      }

      {:ok, agent_info}
    rescue
      error ->
        {:error, {:deserialization_failed, error}}
    end
  end

  # Private Implementation

  defp validate_required_params(params) do
    if Map.has_key?(params, :agent_id) do
      :ok
    else
      {:error, :missing_agent_id}
    end
  end

  defp extract_capabilities(params) do
    cond do
      Map.has_key?(params, :capabilities) ->
        MapSet.new(params.capabilities)

      Map.has_key?(params, :capability) ->
        MapSet.new([params.capability])

      true ->
        MapSet.new()
    end
  end

  defp initialize_health_metrics do
    %{
      overall_health: :unknown,
      resource_health: %{},
      performance_health: :unknown,
      coordination_health: :healthy,
      last_health_check: DateTime.utc_now(),
      health_trend: :stable,
      health_score: 0.0
    }
  end

  defp initialize_performance_metrics do
    %{
      tasks_completed: 0,
      tasks_failed: 0,
      average_task_duration: 0.0,
      throughput_per_second: 0.0,
      error_rate: 0.0,
      success_rate: 0.0,
      last_performance_update: DateTime.utc_now()
    }
  end

  defp initialize_coordination_state do
    %{
      active_consensus: [],
      active_barriers: [],
      held_locks: [],
      leadership_roles: [],
      coordination_score: 0.0,
      last_coordination_activity: nil
    }
  end

  defp validate_state_transition(current_state, new_state) do
    # Define valid state transitions
    valid_transitions = %{
      :initializing => [:ready, :stopped],
      :ready => [:active, :idle, :maintenance, :stopping],
      :active => [:idle, :degraded, :maintenance, :stopping],
      :idle => [:active, :ready, :maintenance, :stopping],
      :degraded => [:active, :idle, :maintenance, :stopping],
      :maintenance => [:ready, :stopping],
      :stopping => [:stopped],
      :stopped => []
    }

    case Map.get(valid_transitions, current_state, []) do
      allowed_states ->
        if new_state in allowed_states do
          :ok
        else
          {:error, {:invalid_state_transition, current_state, new_state}}
        end
    end
  end

  defp calculate_resource_health(resource_metrics) do
    Enum.reduce(resource_metrics, %{}, fn {resource_type, usage}, acc ->
      health = cond do
        usage > 0.9 -> :unhealthy
        usage > 0.8 -> :degraded
        true -> :healthy
      end

      Map.put(acc, resource_type, health)
    end)
  end

  defp calculate_health_trend(old_health, new_health) do
    health_scores = %{healthy: 3, degraded: 2, unhealthy: 1, unknown: 0}

    old_score = Map.get(health_scores, old_health, 0)
    new_score = Map.get(health_scores, new_health, 0)

    cond do
      new_score > old_score -> :improving
      new_score < old_score -> :degrading
      true -> :stable
    end
  end

  defp calculate_health_score(overall_health, resource_metrics) do
    base_score = case overall_health do
      :healthy -> 1.0
      :degraded -> 0.7
      :unhealthy -> 0.3
      :unknown -> 0.0
    end

    # Adjust based on resource usage
    resource_penalty = Enum.reduce(resource_metrics, 0.0, fn {_type, usage}, acc ->
      cond do
        usage > 0.9 -> acc + 0.3
        usage > 0.8 -> acc + 0.1
        true -> acc
      end
    end)

    max(0.0, base_score - resource_penalty)
  end

  defp calculate_derived_performance_metrics(performance) do
    total_tasks = performance.tasks_completed + performance.tasks_failed

    updated_performance = if total_tasks > 0 do
      success_rate = performance.tasks_completed / total_tasks
      error_rate = performance.tasks_failed / total_tasks

      performance
      |> Map.put(:success_rate, success_rate)
      |> Map.put(:error_rate, error_rate)
    else
      performance
    end

    updated_performance
  end

  defp calculate_coordination_score(coordination_state) do
    # Calculate coordination activity score
    active_count = length(coordination_state.active_consensus) +
                  length(coordination_state.active_barriers) +
                  length(coordination_state.held_locks) +
                  length(coordination_state.leadership_roles)

    score = min(1.0, active_count * 0.2)

    Map.put(coordination_state, :coordination_score, score)
  end

  defp determine_load_level(agent_info) do
    coordination_load = agent_info.coordination_state.coordination_score
    resource_load = calculate_average_resource_usage(agent_info.resource_usage)

    average_load = (coordination_load + resource_load) / 2

    cond do
      average_load > 0.8 -> :high
      average_load > 0.5 -> :medium
      average_load > 0.2 -> :low
      true -> :minimal
    end
  end

  defp calculate_average_resource_usage(resource_usage) do
    if map_size(resource_usage) == 0 do
      0.0
    else
      total_usage = Enum.reduce(resource_usage, 0.0, fn {_type, usage}, acc ->
        acc + usage
      end)

      total_usage / map_size(resource_usage)
    end
  end

  defp coordination_active?(agent_info) do
    coordination = agent_info.coordination_state

    length(coordination.active_consensus) > 0 or
    length(coordination.active_barriers) > 0 or
    length(coordination.held_locks) > 0 or
    length(coordination.leadership_roles) > 0
  end

  defp serialize_health_metrics(health_metrics) do
    health_metrics
    |> Map.put(:last_health_check, DateTime.to_iso8601(health_metrics.last_health_check))
  end

  defp serialize_performance_metrics(performance_metrics) do
    performance_metrics
    |> Map.put(:last_performance_update, DateTime.to_iso8601(performance_metrics.last_performance_update))
  end

  defp serialize_coordination_state(coordination_state) do
    last_activity = case coordination_state.last_coordination_activity do
      nil -> nil
      datetime -> DateTime.to_iso8601(datetime)
    end

    Map.put(coordination_state, :last_coordination_activity, last_activity)
  end

  defp deserialize_health_metrics(health_map) do
    health_map
    |> Map.put(:last_health_check, parse_datetime(Map.get(health_map, "last_health_check")))
    |> Map.put(:overall_health, atomize_key(Map.get(health_map, "overall_health", "unknown")))
    |> Map.put(:performance_health, atomize_key(Map.get(health_map, "performance_health", "unknown")))
    |> Map.put(:coordination_health, atomize_key(Map.get(health_map, "coordination_health", "healthy")))
    |> Map.put(:health_trend, atomize_key(Map.get(health_map, "health_trend", "stable")))
  end

  defp deserialize_performance_metrics(performance_map) do
    performance_map
    |> Map.put(:last_performance_update, parse_datetime(Map.get(performance_map, "last_performance_update")))
  end

  defp deserialize_coordination_state(coordination_map) do
    last_activity = case Map.get(coordination_map, "last_coordination_activity") do
      nil -> nil
      datetime_string -> parse_datetime(datetime_string)
    end

    coordination_map
    |> Map.put(:last_coordination_activity, last_activity)
  end

  defp parse_datetime(nil), do: DateTime.utc_now()
  defp parse_datetime(%DateTime{} = dt), do: dt
  defp parse_datetime(iso_string) when is_binary(iso_string) do
    case DateTime.from_iso8601(iso_string) do
      {:ok, dt, _} -> dt
      _ -> DateTime.utc_now()
    end
  end
  defp parse_datetime(_), do: DateTime.utc_now()

  defp atomize_key(nil), do: nil
  defp atomize_key(value) when is_atom(value), do: value
  defp atomize_key(value) when is_binary(value) do
    try do
      String.to_existing_atom(value)
    rescue
      ArgumentError -> String.to_atom(value)
    end
  end
  defp atomize_key(value), do: value
end