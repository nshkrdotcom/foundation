# Foundation Technical Specifications

## Overview

This document provides detailed technical specifications for implementing the Foundation Layer prototype, defining exact interfaces, data structures, and behavioral contracts that must be implemented according to the unified vision documents.

## Core Type System

### 1. Foundation Agent Structure

Based on 011_FOUNDATION_LAYER_ARCHITECTURE.md and 012_FOUNDATION_AGENT_IMPLEMENTATION.md:

```elixir
defmodule ElixirML.Foundation.Types.Agent do
  @moduledoc """
  Core agent structure with all required fields for Foundation Layer.
  """
  
  @enforce_keys [:id, :name, :behavior]
  defstruct [
    # Core Identity
    :id,                    # UUID - unique agent identifier
    :name,                  # atom() - human-readable name
    :behavior,              # module() - agent behavior implementation
    
    # State Management
    state: %{},            # map() - agent's internal state
    variables: %{},        # %{atom() => Variable.t()} - optimization variables
    config: %{},           # map() - agent configuration
    
    # Capabilities and Actions
    actions: %{},          # %{atom() => Action.t()} - available actions
    capabilities: [],      # [atom()] - agent capabilities
    
    # Skills System (016)
    skills: %{},           # %{atom() => Skill.t()} - loaded skills
    skill_state: %{},      # %{atom() => term()} - skill-specific state
    skill_routes: %{},     # %{String.t() => {skill_id, handler}} - route table
    
    # Communication
    subscriptions: [],     # [String.t()] - event subscriptions
    message_queue: [],     # [Message.t()] - pending messages
    
    # Lifecycle
    status: :initializing, # :initializing | :running | :paused | :stopping | :stopped
    created_at: nil,       # DateTime.t()
    updated_at: nil,       # DateTime.t()
    
    # Metadata
    metadata: %{},         # map() - additional metadata
    version: "1.0.0"       # String.t() - agent version
  ]
  
  @type t :: %__MODULE__{
    id: String.t(),
    name: atom(),
    behavior: module(),
    state: map(),
    variables: %{atom() => ElixirML.Foundation.Types.Variable.t()},
    config: map(),
    actions: %{atom() => ElixirML.Foundation.Types.Action.t()},
    capabilities: [atom()],
    skills: %{atom() => ElixirML.Foundation.Types.Skill.t()},
    skill_state: %{atom() => term()},
    skill_routes: %{String.t() => {atom(), atom()}},
    subscriptions: [String.t()],
    message_queue: [ElixirML.Foundation.Types.Message.t()],
    status: agent_status(),
    created_at: DateTime.t() | nil,
    updated_at: DateTime.t() | nil,
    metadata: map(),
    version: String.t()
  }
  
  @type agent_status :: :initializing | :running | :paused | :stopping | :stopped
end
```

### 2. Variable System Types

Based on 011_FOUNDATION_LAYER_ARCHITECTURE.md:

```elixir
defmodule ElixirML.Foundation.Types.Variable do
  @moduledoc """
  Universal variable system for optimization and configuration.
  """
  
  @enforce_keys [:name, :type, :range]
  defstruct [
    :name,                 # atom() - variable identifier
    :type,                 # variable_type() - variable type
    :range,                # term() - type-specific range/constraints
    value: nil,            # term() - current value
    default: nil,          # term() - default value
    description: "",       # String.t() - human description
    metadata: %{},         # map() - additional metadata
    constraints: [],       # [constraint()] - validation constraints
    dependencies: []       # [atom()] - dependent variable names
  ]
  
  @type t :: %__MODULE__{
    name: atom(),
    type: variable_type(),
    range: term(),
    value: term(),
    default: term(),
    description: String.t(),
    metadata: map(),
    constraints: [constraint()],
    dependencies: [atom()]
  }
  
  @type variable_type :: 
    :float | :integer | :boolean | :string | :atom |
    :choice | :module | :composite | :embedding | :probability
    
  @type constraint :: 
    {:min, number()} | {:max, number()} | {:in, [term()]} |
    {:pattern, Regex.t()} | {:custom, function()}
end
```

### 3. Action System Types

Based on 011_FOUNDATION_LAYER_ARCHITECTURE.md and 019_FOUNDATION_ENHANCED_ACTION_FRAMEWORK.md:

```elixir
defmodule ElixirML.Foundation.Types.Action do
  @moduledoc """
  Enhanced action system with validation, workflows, and tool integration.
  """
  
  @enforce_keys [:name, :handler]
  defstruct [
    :name,                 # atom() - action identifier
    :handler,              # function() - execution function
    
    # Validation and Schema
    schema: nil,           # map() | nil - parameter validation schema
    instructions: [],      # [instruction()] - workflow instructions
    
    # Execution Control
    timeout: 30_000,       # pos_integer() - timeout in milliseconds
    retry_policy: nil,     # retry_policy() | nil - retry configuration
    middleware: [],        # [module()] - middleware stack
    
    # Capabilities and Security
    capabilities: [],      # [atom()] - required capabilities
    permissions: [],       # [atom()] - required permissions
    
    # Tool Integration
    tool_spec: nil,        # map() | nil - LLM tool specification
    
    # Metadata
    description: "",       # String.t() - human description
    metadata: %{}          # map() - additional metadata
  ]
  
  @type t :: %__MODULE__{
    name: atom(),
    handler: function(),
    schema: map() | nil,
    instructions: [instruction()],
    timeout: pos_integer(),
    retry_policy: retry_policy() | nil,
    middleware: [module()],
    capabilities: [atom()],
    permissions: [atom()],
    tool_spec: map() | nil,
    description: String.t(),
    metadata: map()
  }
  
  @type instruction :: 
    {:call, module(), atom(), [term()]} |
    {:pipe, [instruction()]} |
    {:parallel, [instruction()]} |
    {:conditional, condition(), instruction(), instruction()} |
    {:retry, instruction(), keyword()} |
    {:timeout, instruction(), pos_integer()}
    
  @type condition :: {:param, atom()} | {:result, atom()} | {:custom, function()}
  
  @type retry_policy :: %{
    max_attempts: pos_integer(),
    backoff: :linear | :exponential | :custom,
    retry_on: [module()],
    base_delay: pos_integer()
  }
end
```

### 4. Event and Signal Types

Based on 013_FOUNDATION_COMMUNICATION_PATTERNS.md and 017_FOUNDATION_SENSORS_FRAMEWORK.md:

```elixir
defmodule ElixirML.Foundation.Types.Event do
  @moduledoc """
  CloudEvents v1.0.2 compatible event structure.
  """
  
  @enforce_keys [:id, :source, :type, :specversion]
  defstruct [
    # CloudEvents Required Fields
    :id,                   # String.t() - event identifier
    :source,              # String.t() - event source URI
    :type,                # String.t() - event type (reverse DNS)
    :specversion,         # String.t() - CloudEvents version
    
    # CloudEvents Optional Fields
    datacontenttype: "application/json", # String.t()
    dataschema: nil,      # String.t() | nil
    subject: nil,         # String.t() | nil
    time: nil,            # DateTime.t() | nil
    data: nil,            # term() - event payload
    
    # Extensions
    extensions: %{}       # map() - additional fields
  ]
  
  @type t :: %__MODULE__{
    id: String.t(),
    source: String.t(),
    type: String.t(),
    specversion: String.t(),
    datacontenttype: String.t(),
    dataschema: String.t() | nil,
    subject: String.t() | nil,
    time: DateTime.t() | nil,
    data: term(),
    extensions: map()
  }
end

defmodule ElixirML.Foundation.Types.Signal do
  @moduledoc """
  Sensor-generated signals (specialized events).
  """
  
  @enforce_keys [:id, :source, :type, :sensor_id]
  defstruct [
    # CloudEvents compatibility
    :id,                   # String.t()
    :source,              # String.t()
    :type,                # String.t()
    :specversion,         # String.t()
    time: nil,            # DateTime.t()
    data: nil,            # term()
    
    # Signal-specific fields
    :sensor_id,           # String.t() - originating sensor
    severity: :info,      # :debug | :info | :warning | :error | :critical
    confidence: 1.0,      # float() - signal confidence (0.0-1.0)
    
    # Metadata
    metadata: %{}         # map()
  ]
  
  @type t :: %__MODULE__{
    id: String.t(),
    source: String.t(),
    type: String.t(),
    specversion: String.t(),
    time: DateTime.t() | nil,
    data: term(),
    sensor_id: String.t(),
    severity: severity_level(),
    confidence: float(),
    metadata: map()
  }
  
  @type severity_level :: :debug | :info | :warning | :error | :critical
end
```

### 5. Skills System Types

Based on 016_FOUNDATION_JIDO_SKILLS_INTEGRATION.md:

```elixir
defmodule ElixirML.Foundation.Types.Skill do
  @moduledoc """
  Modular skill system for extending agent capabilities.
  """
  
  @enforce_keys [:id, :name, :version, :module]
  defstruct [
    :id,                   # String.t() - unique skill identifier
    :name,                # atom() - skill name
    :version,             # String.t() - semantic version
    :module,              # module() - skill implementation
    
    # Capability Definition
    description: "",       # String.t() - skill description
    routes: [],           # [{String.t(), atom()}] - URL patterns and handlers
    sensors: [],          # [Sensor.t()] - associated sensors
    actions: %{},         # %{atom() => Action.t()} - skill actions
    
    # Configuration and Dependencies
    config: %{},          # map() - skill configuration
    dependencies: [],     # [String.t()] - required skill IDs
    conflicts: [],        # [String.t()] - conflicting skill IDs
    
    # Lifecycle
    status: :unloaded,    # :unloaded | :loaded | :active | :error
    loaded_at: nil,       # DateTime.t() | nil
    
    # Metadata
    metadata: %{}         # map()
  ]
  
  @type t :: %__MODULE__{
    id: String.t(),
    name: atom(),
    version: String.t(),
    module: module(),
    description: String.t(),
    routes: [{String.t(), atom()}],
    sensors: [ElixirML.Foundation.Types.Sensor.t()],
    actions: %{atom() => ElixirML.Foundation.Types.Action.t()},
    config: map(),
    dependencies: [String.t()],
    conflicts: [String.t()],
    status: skill_status(),
    loaded_at: DateTime.t() | nil,
    metadata: map()
  }
  
  @type skill_status :: :unloaded | :loaded | :active | :error
end
```

### 6. Sensor Types

Based on 017_FOUNDATION_SENSORS_FRAMEWORK.md:

```elixir
defmodule ElixirML.Foundation.Types.Sensor do
  @moduledoc """
  Event detection and signal generation framework.
  """
  
  @enforce_keys [:id, :type, :handler]
  defstruct [
    :id,                   # String.t() - sensor identifier
    :type,                # sensor_type() - sensor type
    :handler,             # function() - detection handler
    
    # Configuration
    config: %{},          # map() - sensor configuration
    state: nil,           # term() - sensor state
    
    # Control
    enabled: true,        # boolean() - active/inactive
    interval: 1000,       # pos_integer() - detection interval (ms)
    
    # Signal Generation
    signal_config: %{},   # map() - signal generation configuration
    
    # Metadata
    metadata: %{}         # map()
  ]
  
  @type t :: %__MODULE__{
    id: String.t(),
    type: sensor_type(),
    handler: function(),
    config: map(),
    state: term(),
    enabled: boolean(),
    interval: pos_integer(),
    signal_config: map(),
    metadata: map()
  }
  
  @type sensor_type :: 
    :cron | :heartbeat | :file | :webhook | :http | :database | :custom
end
```

### 7. Directive Types

Based on 018_FOUNDATION_DIRECTIVES_SYSTEM.md:

```elixir
defmodule ElixirML.Foundation.Types.Directive do
  @moduledoc """
  Safe agent modification through validated directives.
  """
  
  @enforce_keys [:type, :action, :params]
  defstruct [
    id: nil,              # String.t() | nil - directive identifier
    :type,                # directive_type() - directive category
    :action,              # atom() - specific action
    :params,              # map() - action parameters
    
    # Validation
    validation: nil,      # map() | nil - validation rules
    
    # Execution Control
    timeout: 30_000,      # pos_integer() - execution timeout
    priority: :normal,    # priority_level() - execution priority
    
    # Audit Trail
    timestamp: nil,       # DateTime.t() | nil - creation time
    metadata: %{}         # map() - additional metadata
  ]
  
  @type t :: %__MODULE__{
    id: String.t() | nil,
    type: directive_type(),
    action: atom(),
    params: map(),
    validation: map() | nil,
    timeout: pos_integer(),
    priority: priority_level(),
    timestamp: DateTime.t() | nil,
    metadata: map()
  }
  
  @type directive_type :: :agent | :server | :system
  @type priority_level :: :low | :normal | :high | :critical
end
```

## Protocol Specifications

### 1. Agent Behavior Protocol

```elixir
defmodule ElixirML.Foundation.AgentBehaviour do
  @moduledoc """
  Core behavior that all Foundation agents must implement.
  """
  
  @callback init(config :: map()) :: 
    {:ok, state :: term()} | {:error, reason :: term()}
    
  @callback handle_action(action :: Action.t(), params :: map(), state :: term()) ::
    {:ok, result :: term(), new_state :: term()} |
    {:error, reason :: term(), state :: term()}
    
  @callback handle_signal(signal :: Signal.t(), state :: term()) ::
    {:noreply, new_state :: term()} |
    {:stop, reason :: term(), new_state :: term()}
    
  @callback handle_directive(directive :: Directive.t(), state :: term()) ::
    {:ok, new_state :: term()} |
    {:error, reason :: term(), state :: term()}
    
  @callback handle_message(message :: Message.t(), state :: term()) ::
    {:noreply, new_state :: term()} |
    {:reply, response :: term(), new_state :: term()} |
    {:stop, reason :: term(), new_state :: term()}
    
  @callback terminate(reason :: term(), state :: term()) :: term()
  
  @optional_callbacks [terminate: 2]
end
```

### 2. Skill Behavior Protocol

```elixir
defmodule ElixirML.Foundation.SkillBehaviour do
  @moduledoc """
  Behavior for implementing modular agent skills.
  """
  
  @callback init(config :: map()) :: 
    {:ok, state :: map()} | {:error, term()}
    
  @callback routes() :: 
    [{path_pattern :: String.t(), handler :: atom()}]
    
  @callback sensors() :: 
    [Sensor.t()]
    
  @callback actions() :: 
    %{atom() => Action.t()}
    
  @callback handle_route(path :: String.t(), params :: map(), state :: map()) ::
    {:ok, response :: term(), new_state :: map()} |
    {:error, reason :: term(), state :: map()}
    
  @callback cleanup(state :: map()) :: :ok
  
  @optional_callbacks [cleanup: 1]
end
```

### 3. Sensor Behavior Protocol

```elixir
defmodule ElixirML.Foundation.SensorBehaviour do
  @moduledoc """
  Behavior for implementing event detection sensors.
  """
  
  @callback init(config :: map()) :: 
    {:ok, state :: term()} | {:error, term()}
    
  @callback detect(state :: term()) :: 
    {:signal, Signal.t(), new_state :: term()} |
    {:signals, [Signal.t()], new_state :: term()} |
    {:noop, state :: term()} |
    {:error, reason :: term(), state :: term()}
    
  @callback cleanup(state :: term()) :: :ok
  
  @optional_callbacks [cleanup: 1]
end
```

## Resource Management Specifications

### 1. Resource Types

Based on 014_FOUNDATION_RESOURCE_MANAGEMENT.md:

```elixir
defmodule ElixirML.Foundation.Resources.Types do
  @moduledoc """
  Standard resource type definitions.
  """
  
  # Token-based resources (LLM usage)
  def tokens(), do: %ResourceType{
    name: :tokens,
    unit: :count,
    renewable: true,
    cost_per_unit: 0.00001
  }
  
  # API call limits
  def api_calls(), do: %ResourceType{
    name: :api_calls,
    unit: :count,
    renewable: true,
    cost_per_unit: 0.001
  }
  
  # Memory allocation
  def memory(), do: %ResourceType{
    name: :memory,
    unit: :bytes,
    renewable: false
  }
  
  # Compute time
  def compute_time(), do: %ResourceType{
    name: :compute_time,
    unit: :milliseconds,
    renewable: true,
    cost_per_unit: 0.0001
  }
  
  # Concurrent request slots
  def concurrent_requests(), do: %ResourceType{
    name: :concurrent_requests,
    unit: :count,
    renewable: false
  }
end
```

### 2. Resource Allocation Interface

```elixir
defmodule ElixirML.Foundation.Resources.Allocator do
  @moduledoc """
  Resource allocation and management interface.
  """
  
  @callback allocate(resource :: atom(), amount :: number(), agent_id :: String.t()) ::
    {:ok, allocation_id :: String.t()} |
    {:error, :insufficient_resources | :quota_exceeded | term()}
    
  @callback deallocate(allocation_id :: String.t()) ::
    :ok | {:error, :not_found | term()}
    
  @callback check_quota(resource :: atom(), agent_id :: String.t()) ::
    {:ok, available :: number(), limit :: number()} |
    {:error, term()}
    
  @callback get_usage(agent_id :: String.t()) ::
    {:ok, usage :: map()} | {:error, term()}
end
```

## Native DSPy Signature Specifications

Based on 1100_native_signature_syntax_exploration.md:

### 1. Signature Macro System

```elixir
defmodule ElixirML.Foundation.Signature do
  @moduledoc """
  Native DSPy signature syntax with compile-time optimization.
  """
  
  defmacro __using__(_opts) do
    quote do
      import ElixirML.Foundation.Signature.DSL
      Module.register_attribute(__MODULE__, :signatures, accumulate: true)
      @before_compile ElixirML.Foundation.Signature.Compiler
    end
  end
  
  defmacro signature(name, do: block) do
    quote do
      @signatures {unquote(name), unquote(block)}
    end
  end
end
```

### 2. Type System for Signatures

```elixir
defmodule ElixirML.Foundation.Signature.Types do
  @moduledoc """
  Type system for DSPy signatures with ML-specific types.
  """
  
  # Basic types
  @basic_types [:str, :int, :float, :bool]
  
  # ML-specific types
  @ml_types [:embedding, :token_list, :tensor, :probability, :confidence_score]
  
  # Container types
  @container_types [:list, :dict, :optional, :union]
  
  # Type validation and conversion
  def validate_type(value, type_spec) do
    # Implementation for type validation
  end
  
  def convert_type(value, from_type, to_type) do
    # Implementation for type conversion
  end
end
```

### 3. Compile-Time Optimization

```elixir
defmodule ElixirML.Foundation.Signature.Compiler do
  @moduledoc """
  Compile-time signature processing and optimization.
  """
  
  defmacro __before_compile__(env) do
    signatures = Module.get_attribute(env.module, :signatures)
    
    # Generate optimized validation functions
    validations = generate_validations(signatures)
    
    # Generate field accessors
    accessors = generate_accessors(signatures)
    
    # Generate schema metadata
    schema = generate_schema(signatures)
    
    quote do
      unquote_splicing(validations)
      unquote_splicing(accessors)
      unquote(schema)
    end
  end
  
  defp generate_validations(signatures) do
    # Implementation for generating validation functions
  end
  
  defp generate_accessors(signatures) do
    # Implementation for generating field accessors
  end
  
  defp generate_schema(signatures) do
    # Implementation for generating schema metadata
  end
end
```

## Testing Specifications

### 1. Test Categories

1. **Unit Tests** - Individual component testing
2. **Integration Tests** - Component interaction testing
3. **Property-Based Tests** - Behavioral guarantees
4. **Performance Tests** - Load and stress testing
5. **End-to-End Tests** - Complete workflow testing

### 2. Test Coverage Requirements

- **Minimum Coverage**: 95% line coverage
- **Critical Paths**: 100% coverage for error handling
- **Edge Cases**: Property-based testing for edge cases
- **Integration Points**: Comprehensive integration testing

### 3. Test Infrastructure

```elixir
defmodule ElixirML.Foundation.TestHelpers do
  @moduledoc """
  Common test utilities and helpers.
  """
  
  def setup_test_agent(config \\ %{}) do
    # Standard test agent setup
  end
  
  def mock_skill(name, behaviors \\ %{}) do
    # Skill mocking utilities
  end
  
  def assert_event_emitted(event_type, timeout \\ 1000) do
    # Event assertion helpers
  end
  
  def simulate_resource_pressure(resource, duration) do
    # Resource pressure simulation
  end
end
```

## Performance Requirements

### 1. Latency Requirements

- **Agent Message Handling**: <10ms average, <50ms p99
- **Event Propagation**: <5ms across event bus
- **Action Execution**: <100ms for simple actions
- **Resource Allocation**: <1ms for quota checks

### 2. Throughput Requirements

- **Event Processing**: 10,000+ events/second
- **Agent Coordination**: 1,000+ agents active simultaneously
- **Message Routing**: 50,000+ messages/second
- **State Persistence**: 1,000+ state updates/second

### 3. Resource Requirements

- **Memory per Agent**: <10MB baseline, <50MB with skills
- **CPU Usage**: <5% per agent under normal load
- **Network Bandwidth**: <1KB/second per agent baseline
- **Storage**: <1MB per agent for persistent state

## Security Specifications

### 1. Capability-Based Security

```elixir
defmodule ElixirML.Foundation.Security.Capabilities do
  @moduledoc """
  Capability-based security model for agents and actions.
  """
  
  @capabilities [
    :file_read, :file_write, :network_access, :database_access,
    :llm_access, :skill_management, :agent_control, :system_admin
  ]
  
  def check_capability(agent, capability) do
    # Implementation for capability checking
  end
  
  def grant_capability(agent_id, capability, grantor) do
    # Implementation for capability granting
  end
  
  def revoke_capability(agent_id, capability, revoker) do
    # Implementation for capability revocation
  end
end
```

### 2. Input Validation

- **Parameter Validation**: Schema-based validation for all inputs
- **Path Traversal Protection**: Sanitize all file paths
- **Injection Prevention**: Escape all dynamic queries
- **Rate Limiting**: Prevent abuse through rate limiting

### 3. Audit Trail

- **Action Logging**: Log all agent actions with timestamps
- **State Changes**: Track all state modifications
- **Access Control**: Log all capability checks and changes
- **Error Tracking**: Comprehensive error logging

This technical specification provides the detailed contracts and interfaces needed to implement the Foundation Layer prototype according to the unified vision.