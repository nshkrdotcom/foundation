# lib/foundation/mabeam/types.ex
defmodule Foundation.MABEAM.Types do
  @moduledoc """
  Type definitions for the MABEAM (Multi-Agent BEAM) system.

  This module defines the core types used throughout the MABEAM system for
  multi-agent coordination, universal variable orchestration, and distributed
  state management.

  ## Design Philosophy

  These types are designed with a pragmatic single-node implementation in mind,
  but with APIs that support future distributed operation. The types provide:

  - Clear boundaries between local and distributed operations
  - Extensible structures for future distributed features
  - Strong typing for agent coordination protocols
  - Compatibility with Foundation's enhanced error system

  ## Agent Architecture

  MABEAM agents are autonomous entities that can:
  - Manage their own state and lifecycle
  - Participate in coordination protocols
  - Share and orchestrate universal variables
  - Communicate through structured message passing

  ## Universal Variables

  Universal variables are shared state entities that:
  - Can be accessed and modified by multiple agents
  - Have conflict resolution strategies
  - Support transactional updates
  - Maintain consistency across the system
  """

  alias Foundation.Types.Error

  # ============================================================================
  # Core Agent Types
  # ============================================================================

  @typedoc "Unique identifier for an agent"
  @type agent_id :: atom() | String.t()

  @typedoc "Agent state representation"
  @type agent_state :: %{
          id: agent_id(),
          type: agent_type(),
          status: agent_status(),
          capabilities: [agent_capability()],
          variables: %{variable_name() => variable_value()},
          coordination_state: coordination_state(),
          metadata: agent_metadata()
        }

  @typedoc "Type classification for agents"
  # Manages coordination protocols
  @type agent_type ::
          :coordinator
          # Executes tasks and operations
          | :worker
          # Observes and reports on system state
          | :monitor
          # Manages universal variables
          | :orchestrator
          # Combines multiple agent types
          | :hybrid

  @typedoc "Current operational status of an agent"
  # Agent is starting up
  @type agent_status ::
          :initializing
          # Agent is operational
          | :active
          # Agent is participating in coordination
          | :coordinating
          # Agent is waiting for coordination
          | :waiting
          # Agent is operational but with reduced capability
          | :degraded
          # Agent is shutting down
          | :stopping
          # Agent has stopped
          | :stopped

  @typedoc "Capabilities that an agent can provide"
  # Can participate in consensus protocols
  @type agent_capability ::
          :consensus
          # Can engage in negotiation
          | :negotiation
          # Can participate in auctions
          | :auction
          # Can engage in market mechanisms
          | :market
          # Can access universal variables
          | :variable_access
          # Can coordinate with other agents
          | :coordination
          # Can monitor system state
          | :monitoring
          # Can emit telemetry data
          | :telemetry

  @typedoc "Metadata associated with an agent"
  @type agent_metadata :: %{
          created_at: DateTime.t(),
          updated_at: DateTime.t(),
          version: String.t(),
          node: node(),
          namespace: atom(),
          tags: [String.t()],
          custom: map()
        }

  # ============================================================================
  # Universal Variable Types
  # ============================================================================

  @typedoc "Name identifier for a universal variable"
  @type variable_name :: atom() | String.t()

  @typedoc "Value stored in a universal variable"
  @type variable_value :: term()

  @typedoc "Universal variable with metadata and coordination info"
  @type universal_variable :: %{
          name: variable_name(),
          value: variable_value(),
          type: variable_type(),
          access_mode: access_mode(),
          conflict_resolution: conflict_resolution_strategy(),
          version: non_neg_integer(),
          last_modified: DateTime.t(),
          last_modifier: agent_id(),
          metadata: variable_metadata()
        }

  @typedoc "Type classification for universal variables"
  # Shared read/write access
  @type variable_type ::
          :shared
          # Write-once, read-many
          | :broadcast
          # Supports accumulation operations
          | :accumulator
          # Numeric counter with atomic operations
          | :counter
          # Boolean flag with atomic set/clear
          | :flag
          # FIFO queue operations
          | :queue
          # Set collection operations
          | :set
          # Custom type with user-defined operations
          | :custom

  @typedoc "Access control mode for variables"
  # Any agent can access
  @type access_mode ::
          :public
          # Only authorized agents can access
          | :restricted
          # Only the creating agent can access
          | :owner_only
          # Access requires coordination protocol
          | :coordinated

  @typedoc "Strategy for resolving conflicting variable updates"
  # Most recent update wins
  @type conflict_resolution_strategy ::
          :last_write_wins
          # First update wins, others rejected
          | :first_write_wins
          # Attempt to merge conflicting updates
          | :merge
          # Agents vote on the correct value
          | :vote
          # User-defined resolution function
          | :custom
          # Reject conflicting updates with error
          | :error

  @typedoc "Metadata for universal variables"
  @type variable_metadata :: %{
          created_at: DateTime.t(),
          created_by: agent_id(),
          access_count: non_neg_integer(),
          modification_count: non_neg_integer(),
          conflict_count: non_neg_integer(),
          tags: [String.t()],
          custom: map()
        }

  # ============================================================================
  # Coordination Types
  # ============================================================================

  @typedoc "Current coordination state of an agent"
  @type coordination_state :: %{
          active_protocols: [coordination_protocol()],
          pending_requests: [coordination_request()],
          coordination_history: [coordination_event()],
          leadership_status: leadership_status(),
          group_memberships: [group_id()]
        }

  @typedoc "Types of coordination protocols"
  # Reach agreement on a value
  @type coordination_protocol ::
          :consensus
          # Elect a leader among agents
          | :leader_election
          # Negotiate terms or values
          | :negotiation
          # Auction-based resource allocation
          | :auction
          # Market-based coordination
          | :market
          # Exclusive access to resources
          | :mutual_exclusion
          # Synchronization barrier
          | :barrier
          # User-defined coordination protocol
          | :custom

  @typedoc "Request for coordination between agents"
  @type coordination_request :: %{
          id: String.t(),
          protocol: coordination_protocol(),
          initiator: agent_id(),
          participants: [agent_id()],
          parameters: map(),
          timeout: pos_integer(),
          created_at: DateTime.t()
        }

  @typedoc "Event in coordination history"
  @type coordination_event :: %{
          id: String.t(),
          type: coordination_event_type(),
          protocol: coordination_protocol(),
          participants: [agent_id()],
          result: coordination_result(),
          timestamp: DateTime.t(),
          metadata: map()
        }

  @typedoc "Types of coordination events"
  @type coordination_event_type ::
          :protocol_started
          | :protocol_completed
          | :protocol_failed
          | :agent_joined
          | :agent_left
          | :consensus_reached
          | :leader_elected
          | :negotiation_completed
          | :auction_completed

  @typedoc "Result of a coordination protocol"
  @type coordination_result ::
          {:ok, term()}
          | {:error, Error.t()}
          | {:timeout, String.t()}

  @typedoc "Leadership status of an agent"
  # Agent is following a leader
  @type leadership_status ::
          :follower
          # Agent is candidating for leadership
          | :candidate
          # Agent is the elected leader
          | :leader
          # Agent is not participating in leadership
          | :none

  @typedoc "Identifier for coordination groups"
  @type group_id :: atom() | String.t()

  # ============================================================================
  # Message Passing Types
  # ============================================================================

  @typedoc "Message passed between agents"
  @type agent_message :: %{
          id: String.t(),
          from: agent_id(),
          to: agent_id() | [agent_id()],
          type: message_type(),
          payload: term(),
          priority: message_priority(),
          timestamp: DateTime.t(),
          reply_to: String.t() | nil,
          correlation_id: String.t() | nil
        }

  @typedoc "Types of messages between agents"
  # Request for action or information
  @type message_type ::
          :request
          # Response to a request
          | :response
          # One-way notification
          | :notification
          # Coordination protocol message
          | :coordination
          # Universal variable update
          | :variable_update
          # Liveness indication
          | :heartbeat
          # System-level message
          | :system

  @typedoc "Priority levels for message processing"
  # Process when convenient
  @type message_priority ::
          :low
          # Standard priority
          | :normal
          # Process promptly
          | :high
          # Process immediately
          | :urgent
          # System-critical message
          | :system

  # ============================================================================
  # Configuration Types
  # ============================================================================

  @typedoc "Configuration for the MABEAM system"
  @type mabeam_config :: %{
          mode: operation_mode(),
          coordination: coordination_config(),
          variables: variable_config(),
          messaging: messaging_config(),
          telemetry: telemetry_config(),
          timeouts: timeout_config()
        }

  @typedoc "Operation mode for MABEAM"
  # Single-node operation (pragmatic)
  @type operation_mode ::
          :single_node
          # Full distributed operation
          | :distributed
          # Mixed mode operation
          | :hybrid

  @typedoc "Configuration for coordination protocols"
  @type coordination_config :: %{
          default_timeout: pos_integer(),
          max_participants: pos_integer(),
          retry_attempts: non_neg_integer(),
          consensus_threshold: float(),
          leader_election_timeout: pos_integer(),
          heartbeat_interval: pos_integer()
        }

  @typedoc "Configuration for universal variables"
  @type variable_config :: %{
          default_access_mode: access_mode(),
          default_conflict_resolution: conflict_resolution_strategy(),
          max_variables: pos_integer(),
          persistence_enabled: boolean(),
          backup_interval: pos_integer(),
          cleanup_interval: pos_integer()
        }

  @typedoc "Configuration for message passing"
  @type messaging_config :: %{
          max_message_size: pos_integer(),
          message_queue_limit: pos_integer(),
          delivery_timeout: pos_integer(),
          retry_attempts: non_neg_integer(),
          compression_enabled: boolean(),
          encryption_enabled: boolean()
        }

  @typedoc "Configuration for telemetry"
  @type telemetry_config :: %{
          enabled: boolean(),
          metrics_interval: pos_integer(),
          event_buffer_size: pos_integer(),
          export_format: :prometheus | :statsd | :custom,
          custom_exporters: [module()]
        }

  @typedoc "Timeout configuration"
  @type timeout_config :: %{
          agent_startup: pos_integer(),
          agent_shutdown: pos_integer(),
          coordination_default: pos_integer(),
          variable_access: pos_integer(),
          message_delivery: pos_integer(),
          health_check: pos_integer()
        }

  # ============================================================================
  # Error Types
  # ============================================================================

  @typedoc "MABEAM-specific error types"
  @type mabeam_error ::
          :agent_not_found
          | :agent_already_exists
          | :invalid_agent_config
          | :coordination_failed
          | :consensus_timeout
          | :variable_not_found
          | :variable_conflict
          | :access_denied
          | :protocol_error
          | :message_delivery_failed
          | :system_overload

  # ============================================================================
  # Utility Functions
  # ============================================================================

  @doc """
  Create a new agent state with default values.

  ## Parameters
  - `id` - Unique identifier for the agent
  - `type` - Type classification for the agent
  - `opts` - Optional configuration

  ## Returns
  A new agent_state with sensible defaults.

  ## Examples

      iex> agent = Foundation.MABEAM.Types.new_agent(:worker_1, :worker)
      iex> agent.id
      :worker_1

      iex> agent = Foundation.MABEAM.Types.new_agent("coord_1", :coordinator,
      ...>   capabilities: [:consensus, :negotiation])
      iex> :consensus in agent.capabilities
      true
  """
  @spec new_agent(agent_id(), agent_type(), keyword()) :: agent_state()
  def new_agent(id, type, opts \\ []) do
    now = DateTime.utc_now()

    %{
      id: id,
      type: type,
      status: :initializing,
      capabilities: Keyword.get(opts, :capabilities, default_capabilities(type)),
      variables: %{},
      coordination_state: %{
        active_protocols: [],
        pending_requests: [],
        coordination_history: [],
        leadership_status: :none,
        group_memberships: []
      },
      metadata: %{
        created_at: now,
        updated_at: now,
        version: "1.0.0",
        node: Node.self(),
        namespace: Keyword.get(opts, :namespace, :default),
        tags: Keyword.get(opts, :tags, []),
        custom: Keyword.get(opts, :custom, %{})
      }
    }
  end

  @doc """
  Create a new universal variable with default configuration.

  ## Parameters
  - `name` - Name identifier for the variable
  - `value` - Initial value
  - `creator` - Agent that created the variable
  - `opts` - Optional configuration

  ## Returns
  A new universal_variable with sensible defaults.

  ## Examples

      iex> var = Foundation.MABEAM.Types.new_variable(:counter, 0, :agent_1)
      iex> var.name
      :counter

      iex> var = Foundation.MABEAM.Types.new_variable("shared_state", %{}, "coordinator",
      ...>   type: :shared, access_mode: :public)
      iex> var.access_mode
      :public
  """
  @spec new_variable(variable_name(), variable_value(), agent_id(), keyword()) ::
          universal_variable()
  def new_variable(name, value, creator, opts \\ []) do
    now = DateTime.utc_now()

    %{
      name: name,
      value: value,
      type: Keyword.get(opts, :type, :shared),
      access_mode: Keyword.get(opts, :access_mode, :public),
      conflict_resolution: Keyword.get(opts, :conflict_resolution, :last_write_wins),
      version: 1,
      last_modified: now,
      last_modifier: creator,
      metadata: %{
        created_at: now,
        created_by: creator,
        access_count: 0,
        modification_count: 1,
        conflict_count: 0,
        tags: Keyword.get(opts, :tags, []),
        custom: Keyword.get(opts, :custom, %{})
      }
    }
  end

  @doc """
  Create a new coordination request.

  ## Parameters
  - `protocol` - Type of coordination protocol
  - `initiator` - Agent initiating the coordination
  - `participants` - List of participating agents
  - `opts` - Optional parameters and configuration

  ## Returns
  A new coordination_request.
  """
  @spec new_coordination_request(coordination_protocol(), agent_id(), [agent_id()], keyword()) ::
          coordination_request()
  def new_coordination_request(protocol, initiator, participants, opts \\ []) do
    %{
      id: Keyword.get(opts, :id, generate_request_id()),
      protocol: protocol,
      initiator: initiator,
      participants: participants,
      parameters: Keyword.get(opts, :parameters, %{}),
      timeout: Keyword.get(opts, :timeout, 5000),
      created_at: DateTime.utc_now()
    }
  end

  @doc """
  Create a new agent message.

  ## Parameters
  - `from` - Sending agent
  - `to` - Receiving agent(s)
  - `type` - Message type
  - `payload` - Message content
  - `opts` - Optional message configuration

  ## Returns
  A new agent_message.
  """
  @spec new_message(agent_id(), agent_id() | [agent_id()], message_type(), term(), keyword()) ::
          agent_message()
  def new_message(from, to, type, payload, opts \\ []) do
    %{
      id: Keyword.get(opts, :id, generate_message_id()),
      from: from,
      to: to,
      type: type,
      payload: payload,
      priority: Keyword.get(opts, :priority, :normal),
      timestamp: DateTime.utc_now(),
      reply_to: Keyword.get(opts, :reply_to),
      correlation_id: Keyword.get(opts, :correlation_id)
    }
  end

  @doc """
  Get default configuration for MABEAM system.

  ## Returns
  A mabeam_config with pragmatic defaults for single-node operation.
  """
  def default_config do
    %{
      mode: :single_node,
      coordination: %{
        default_timeout: 5_000,
        max_participants: 100,
        retry_attempts: 3,
        consensus_threshold: 0.51,
        leader_election_timeout: 10_000,
        heartbeat_interval: 1_000
      },
      variables: %{
        default_access_mode: :public,
        default_conflict_resolution: :last_write_wins,
        max_variables: 10_000,
        persistence_enabled: false,
        backup_interval: 60_000,
        cleanup_interval: 300_000
      },
      messaging: %{
        # 1MB
        max_message_size: 1_048_576,
        message_queue_limit: 1_000,
        delivery_timeout: 5_000,
        retry_attempts: 3,
        compression_enabled: false,
        encryption_enabled: false
      },
      telemetry: %{
        enabled: true,
        metrics_interval: 10_000,
        event_buffer_size: 1_000,
        export_format: :prometheus,
        custom_exporters: []
      },
      timeouts: %{
        agent_startup: 10_000,
        agent_shutdown: 5_000,
        coordination_default: 5_000,
        variable_access: 1_000,
        message_delivery: 3_000,
        health_check: 2_000
      }
    }
  end

  # ============================================================================
  # Private Helper Functions
  # ============================================================================

  defp default_capabilities(:coordinator),
    do: [:consensus, :negotiation, :coordination, :monitoring]

  defp default_capabilities(:worker), do: [:variable_access, :coordination]
  defp default_capabilities(:monitor), do: [:monitoring, :telemetry]
  defp default_capabilities(:orchestrator), do: [:variable_access, :coordination, :consensus]

  defp default_capabilities(:hybrid),
    do: [:consensus, :negotiation, :variable_access, :coordination, :monitoring]

  defp default_capabilities(_), do: [:coordination]

  defp generate_request_id do
    "req_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end

  defp generate_message_id do
    "msg_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
