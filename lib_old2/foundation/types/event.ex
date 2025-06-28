defmodule Foundation.Types.Event do
  @moduledoc """
  Comprehensive event type system for Foundation infrastructure.

  Provides structured event definitions for all Foundation components,
  with support for agent context, coordination events, and infrastructure
  monitoring. Designed to enable rich observability and event-driven
  architectures in multi-agent environments.

  ## Features

  - **Structured Event Types**: Predefined schemas for all Foundation events
  - **Agent Context Integration**: Events automatically enriched with agent information
  - **Validation**: Type checking and constraint validation for event data
  - **Serialization**: JSON-compatible event structures for persistence and transport
  - **Correlation**: Event correlation and tracing support
  - **Metadata**: Rich metadata support for debugging and analysis

  ## Event Categories

  - **System Events**: Application lifecycle, health, configuration changes
  - **Agent Events**: Agent lifecycle, health changes, capability updates
  - **Infrastructure Events**: Circuit breaker trips, rate limits, resource alerts
  - **Coordination Events**: Consensus, barriers, locks, leader election
  - **Performance Events**: Metrics, latency, throughput measurements

  ## Usage

      # Create a system event
      event = Event.new(:system_started, %{
        components: [:process_registry, :coordination, :telemetry],
        startup_duration: 1500
      })

      # Create an agent event with context
      event = Event.new(:agent_health_changed, %{
        agent_id: :ml_agent_1,
        old_health: :healthy,
        new_health: :degraded,
        reason: "memory threshold exceeded"
      })

      # Create a coordination event
      event = Event.new(:consensus_completed, %{
        coordination_id: :model_selection,
        participants: [:agent_1, :agent_2, :agent_3],
        result: :accepted,
        duration: 250
      })
  """

  @type event_id :: String.t()
  @type event_type :: atom()
  @type agent_id :: atom() | String.t()
  @type correlation_id :: String.t()
  @type event_data :: map()
  @type event_metadata :: map()

  defstruct [
    :id,
    :type,
    :data,
    :metadata,
    :timestamp,
    :correlation_id,
    :agent_context,
    :source_node,
    :severity
  ]

  @type t :: %__MODULE__{
    id: event_id(),
    type: event_type(),
    data: event_data(),
    metadata: event_metadata(),
    timestamp: DateTime.t(),
    correlation_id: correlation_id() | nil,
    agent_context: map() | nil,
    source_node: atom(),
    severity: :low | :medium | :high | :critical
  }

  # Event type definitions with validation schemas
  @event_schemas %{
    # System Events
    :system_started => %{
      required: [:components],
      optional: [:startup_duration, :configuration],
      severity: :medium
    },
    :system_stopping => %{
      required: [:reason],
      optional: [:shutdown_duration],
      severity: :medium
    },
    :system_health_check => %{
      required: [:status],
      optional: [:component_health, :metrics],
      severity: :low
    },

    # Agent Events
    :agent_started => %{
      required: [:agent_id],
      optional: [:capabilities, :initial_health, :configuration],
      severity: :medium
    },
    :agent_stopped => %{
      required: [:agent_id, :reason],
      optional: [:final_state, :cleanup_duration],
      severity: :medium
    },
    :agent_health_changed => %{
      required: [:agent_id, :old_health, :new_health],
      optional: [:reason, :metrics, :threshold_breached],
      severity: :high
    },
    :agent_capability_updated => %{
      required: [:agent_id, :capabilities],
      optional: [:added_capabilities, :removed_capabilities],
      severity: :low
    },
    :agent_resource_alert => %{
      required: [:agent_id, :resource_type, :current_usage, :threshold],
      optional: [:trend, :recommendation],
      severity: :high
    },

    # Infrastructure Events
    :circuit_breaker_opened => %{
      required: [:circuit_name, :failure_count],
      optional: [:agent_id, :last_error, :threshold],
      severity: :high
    },
    :circuit_breaker_closed => %{
      required: [:circuit_name],
      optional: [:agent_id, :recovery_duration],
      severity: :medium
    },
    :rate_limit_exceeded => %{
      required: [:entity_id, :operation_type, :current_rate, :limit],
      optional: [:agent_id, :window_ms],
      severity: :medium
    },
    :resource_threshold_exceeded => %{
      required: [:resource_type, :current_value, :threshold],
      optional: [:agent_id, :trend, :prediction],
      severity: :high
    },

    # Coordination Events
    :consensus_started => %{
      required: [:coordination_id, :participants, :proposal],
      optional: [:strategy, :timeout, :initiator],
      severity: :low
    },
    :consensus_completed => %{
      required: [:coordination_id, :participants, :result],
      optional: [:votes, :duration, :strategy],
      severity: :medium
    },
    :consensus_timeout => %{
      required: [:coordination_id, :participants],
      optional: [:partial_votes, :timeout_duration],
      severity: :high
    },
    :barrier_created => %{
      required: [:barrier_id, :participants],
      optional: [:timeout, :description],
      severity: :low
    },
    :barrier_satisfied => %{
      required: [:barrier_id, :participants],
      optional: [:wait_duration, :last_arrival],
      severity: :medium
    },
    :lock_acquired => %{
      required: [:resource_id, :holder_id],
      optional: [:wait_duration, :lock_type],
      severity: :low
    },
    :lock_released => %{
      required: [:resource_id, :holder_id],
      optional: [:hold_duration, :lock_type],
      severity: :low
    },
    :leader_elected => %{
      required: [:group_id, :leader_id, :candidates],
      optional: [:election_duration, :criteria],
      severity: :medium
    },

    # Configuration Events
    :config_changed => %{
      required: [:config_path, :old_value, :new_value],
      optional: [:agent_id, :scope, :change_reason],
      severity: :medium
    },
    :config_validation_failed => %{
      required: [:config_path, :value, :validation_error],
      optional: [:agent_id, :attempted_by],
      severity: :high
    },

    # Performance Events
    :performance_metric => %{
      required: [:metric_name, :value, :metric_type],
      optional: [:agent_id, :tags, :unit],
      severity: :low
    },
    :performance_alert => %{
      required: [:metric_name, :current_value, :threshold, :condition],
      optional: [:agent_id, :trend, :recommendation],
      severity: :high
    },

    # Error Events
    :error_occurred => %{
      required: [:error_type, :message],
      optional: [:agent_id, :context, :stack_trace, :recovery_action],
      severity: :high
    },
    :error_recovered => %{
      required: [:error_type, :recovery_method],
      optional: [:agent_id, :recovery_duration, :final_state],
      severity: :medium
    }
  }

  @doc """
  Create a new Foundation event with validation and enrichment.

  ## Parameters
  - `event_type`: The type of event (must be a known event type)
  - `event_data`: The event-specific data
  - `options`: Additional options for event creation

  ## Options
  - `:correlation_id` - Link this event to other related events
  - `:agent_id` - Associate event with a specific agent
  - `:metadata` - Additional metadata for the event
  - `:severity` - Override default severity level

  ## Examples

      # Basic system event
      event = Event.new(:system_started, %{
        components: [:process_registry, :telemetry]
      })

      # Agent event with correlation
      event = Event.new(:agent_health_changed, %{
        agent_id: :ml_agent_1,
        old_health: :healthy,
        new_health: :degraded
      }, correlation_id: "health-check-cycle-123")
  """
  @spec new(event_type(), event_data(), keyword()) :: {:ok, t()} | {:error, term()}
  def new(event_type, event_data, options \\ []) do
    case validate_event_data(event_type, event_data) do
      :ok ->
        event = %__MODULE__{
          id: generate_event_id(),
          type: event_type,
          data: event_data,
          metadata: Keyword.get(options, :metadata, %{}),
          timestamp: DateTime.utc_now(),
          correlation_id: Keyword.get(options, :correlation_id),
          agent_context: extract_agent_context(event_data, options),
          source_node: Node.self(),
          severity: determine_severity(event_type, options)
        }

        {:ok, enrich_event(event)}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Create a new event, raising an exception on validation failure.

  Same as `new/3` but raises an exception instead of returning an error tuple.
  """
  @spec new!(event_type(), event_data(), keyword()) :: t()
  def new!(event_type, event_data, options \\ []) do
    case new(event_type, event_data, options) do
      {:ok, event} -> event
      {:error, reason} -> raise ArgumentError, "Invalid event: #{inspect(reason)}"
    end
  end

  @doc """
  Validate event data against the event type schema.
  """
  @spec validate_event_data(event_type(), event_data()) :: :ok | {:error, term()}
  def validate_event_data(event_type, event_data) do
    case Map.get(@event_schemas, event_type) do
      nil ->
        {:error, {:unknown_event_type, event_type}}

      schema ->
        validate_against_schema(event_data, schema)
    end
  end

  @doc """
  Convert an event to a map suitable for JSON serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = event) do
    %{
      id: event.id,
      type: event.type,
      data: event.data,
      metadata: event.metadata,
      timestamp: DateTime.to_iso8601(event.timestamp),
      correlation_id: event.correlation_id,
      agent_context: event.agent_context,
      source_node: event.source_node,
      severity: event.severity
    }
  end

  @doc """
  Create an event from a serialized map.
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(event_map) do
    try do
      timestamp = case Map.get(event_map, "timestamp") do
        nil -> DateTime.utc_now()
        iso_string when is_binary(iso_string) ->
          case DateTime.from_iso8601(iso_string) do
            {:ok, dt, _} -> dt
            _ -> DateTime.utc_now()
          end
        %DateTime{} = dt -> dt
      end

      event = %__MODULE__{
        id: Map.get(event_map, "id"),
        type: atomize_key(Map.get(event_map, "type")),
        data: Map.get(event_map, "data", %{}),
        metadata: Map.get(event_map, "metadata", %{}),
        timestamp: timestamp,
        correlation_id: Map.get(event_map, "correlation_id"),
        agent_context: Map.get(event_map, "agent_context"),
        source_node: atomize_key(Map.get(event_map, "source_node")),
        severity: atomize_key(Map.get(event_map, "severity"))
      }

      {:ok, event}
    rescue
      error ->
        {:error, {:deserialization_failed, error}}
    end
  end

  @doc """
  Get all known event types with their schemas.
  """
  @spec get_event_schemas() :: map()
  def get_event_schemas, do: @event_schemas

  @doc """
  Check if an event type is known and valid.
  """
  @spec valid_event_type?(event_type()) :: boolean()
  def valid_event_type?(event_type) do
    Map.has_key?(@event_schemas, event_type)
  end

  @doc """
  Get the schema for a specific event type.
  """
  @spec get_event_schema(event_type()) :: {:ok, map()} | {:error, :unknown_event_type}
  def get_event_schema(event_type) do
    case Map.get(@event_schemas, event_type) do
      nil -> {:error, :unknown_event_type}
      schema -> {:ok, schema}
    end
  end

  @doc """
  Extract agent ID from event data or context.
  """
  @spec extract_agent_id(t()) :: agent_id() | nil
  def extract_agent_id(%__MODULE__{} = event) do
    case event.agent_context do
      %{agent_id: agent_id} -> agent_id
      _ -> Map.get(event.data, :agent_id)
    end
  end

  @doc """
  Check if an event is related to a specific agent.
  """
  @spec agent_related?(t(), agent_id()) :: boolean()
  def agent_related?(%__MODULE__{} = event, agent_id) do
    extract_agent_id(event) == agent_id
  end

  @doc """
  Check if an event should trigger an alert based on severity.
  """
  @spec alertable?(t()) :: boolean()
  def alertable?(%__MODULE__{severity: severity}) do
    severity in [:high, :critical]
  end

  # Private Implementation

  defp validate_against_schema(event_data, schema) do
    # Check required fields
    case check_required_fields(event_data, schema.required) do
      :ok ->
        # Check field types and constraints
        check_field_constraints(event_data, schema)

      {:error, _} = error ->
        error
    end
  end

  defp check_required_fields(event_data, required_fields) do
    missing_fields = Enum.filter(required_fields, fn field ->
      not Map.has_key?(event_data, field)
    end)

    if Enum.empty?(missing_fields) do
      :ok
    else
      {:error, {:missing_required_fields, missing_fields}}
    end
  end

  defp check_field_constraints(event_data, schema) do
    # Basic validation - in production you might use a more sophisticated schema library
    all_allowed_fields = schema.required ++ Map.get(schema, :optional, [])

    extra_fields = Map.keys(event_data) -- all_allowed_fields

    if Enum.empty?(extra_fields) do
      :ok
    else
      {:error, {:unexpected_fields, extra_fields}}
    end
  end

  defp extract_agent_context(event_data, options) do
    agent_id = Keyword.get(options, :agent_id) || Map.get(event_data, :agent_id)

    case agent_id do
      nil -> nil
      agent_id ->
        case get_agent_metadata(agent_id) do
          {:ok, metadata} -> Map.put(metadata, :agent_id, agent_id)
          :error -> %{agent_id: agent_id, status: :not_found}
        end
    end
  end

  defp get_agent_metadata(agent_id) do
    # Try to get agent metadata from ProcessRegistry
    try do
      case Foundation.ProcessRegistry.lookup(:foundation, agent_id) do
        {:ok, _pid, metadata} ->
          context = Map.take(metadata, [:capability, :health, :resources, :type])
          {:ok, context}

        :error ->
          :error
      end
    rescue
      _ -> :error
    end
  end

  defp determine_severity(event_type, options) do
    case Keyword.get(options, :severity) do
      nil ->
        schema = Map.get(@event_schemas, event_type, %{})
        Map.get(schema, :severity, :low)

      severity ->
        severity
    end
  end

  defp enrich_event(event) do
    # Add additional computed metadata
    enriched_metadata = Map.merge(event.metadata, %{
      event_category: categorize_event(event.type),
      processing_timestamp: DateTime.utc_now(),
      schema_version: "1.0"
    })

    %{event | metadata: enriched_metadata}
  end

  defp categorize_event(event_type) do
    cond do
      String.starts_with?(Atom.to_string(event_type), "system_") -> :system
      String.starts_with?(Atom.to_string(event_type), "agent_") -> :agent
      String.starts_with?(Atom.to_string(event_type), "circuit_") -> :infrastructure
      String.starts_with?(Atom.to_string(event_type), "rate_") -> :infrastructure
      String.starts_with?(Atom.to_string(event_type), "resource_") -> :infrastructure
      String.starts_with?(Atom.to_string(event_type), "consensus_") -> :coordination
      String.starts_with?(Atom.to_string(event_type), "barrier_") -> :coordination
      String.starts_with?(Atom.to_string(event_type), "lock_") -> :coordination
      String.starts_with?(Atom.to_string(event_type), "leader_") -> :coordination
      String.starts_with?(Atom.to_string(event_type), "config_") -> :configuration
      String.starts_with?(Atom.to_string(event_type), "performance_") -> :performance
      String.starts_with?(Atom.to_string(event_type), "error_") -> :error
      true -> :unknown
    end
  end

  defp generate_event_id do
    :crypto.strong_rand_bytes(12)
    |> Base.url_encode64(padding: false)
  end

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