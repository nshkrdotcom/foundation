# Foundation Implementation Bootstrap

## Overview

This document provides the immediate next steps to begin implementing the Foundation Layer prototype. It includes the exact commands, file templates, and initial code structure needed to start development according to the unified vision and technical specifications.

## Initial Setup

### 1. Project Structure Setup

Create the complete directory structure for the Foundation Layer:

```bash
# Core Foundation structure
mkdir -p lib/elixir_ml/foundation/{types,agents,skills,sensors,directives,actions,resources,signature}
mkdir -p lib/elixir_ml/foundation/types/{agent,variable,action,event,skill,sensor,directive}
mkdir -p lib/elixir_ml/foundation/{event_bus,registry,supervisor}
mkdir -p lib/elixir_ml/foundation/resources/{quota,rate_limiter,circuit_breaker,cost_tracker}
mkdir -p lib/elixir_ml/foundation/signature/{dsl,compiler,types,validators}

# Test structure
mkdir -p test/elixir_ml/foundation/{unit,integration,performance}
mkdir -p test/elixir_ml/foundation/unit/{types,agents,skills,sensors,directives,actions,resources,signature}

# Examples and documentation
mkdir -p examples/foundation/{basic,skills,workflows}
mkdir -p docs/foundation/{api,guides,tutorials}
```

### 2. Mix Dependencies

Add required dependencies to `mix.exs`:

```elixir
defp deps do
  [
    # Existing dependencies...
    
    # Foundation Layer dependencies
    {:uuid, "~> 1.1"},                    # UUID generation
    {:jason, "~> 1.4"},                   # JSON handling
    {:telemetry, "~> 1.2"},               # Observability
    {:telemetry_metrics, "~> 0.6"},       # Metrics collection
    {:cron, "~> 0.1"},                    # Cron expression parsing
    {:file_system, "~> 0.2"},             # File watching
    {:httpoison, "~> 2.0"},               # HTTP client
    {:plug, "~> 1.14"},                   # HTTP server utilities
    {:ecto, "~> 3.10"},                   # Database abstraction
    {:stream_data, "~> 0.6", only: :test} # Property-based testing
  ]
end
```

## Phase 1 Bootstrap: Core Types Implementation

### Step 1: Foundation Types Module

Create `lib/elixir_ml/foundation/types.ex`:

```elixir
defmodule ElixirML.Foundation.Types do
  @moduledoc """
  Core type definitions for the Foundation Layer.
  
  This module provides the fundamental data structures that all other
  Foundation components depend on. Types are designed for:
  
  - Performance: Compile-time optimization where possible
  - Safety: Strong typing with validation
  - Extensibility: Support for future enhancements
  - Interoperability: JSON serialization and CloudEvents compatibility
  """
  
  # Re-export all core types
  alias ElixirML.Foundation.Types.{
    Agent,
    Variable,
    Action,
    Event,
    Signal,
    Skill,
    Sensor,
    Directive,
    Resource
  }
  
  @type agent :: Agent.t()
  @type variable :: Variable.t()
  @type action :: Action.t()
  @type event :: Event.t()
  @type signal :: Signal.t()
  @type skill :: Skill.t()
  @type sensor :: Sensor.t()
  @type directive :: Directive.t()
  @type resource :: Resource.t()
  
  # Common validation patterns
  def validate_uuid(value) when is_binary(value) do
    case UUID.info(value) do
      {:ok, _} -> {:ok, value}
      {:error, _} -> {:error, :invalid_uuid}
    end
  end
  
  def validate_uuid(_), do: {:error, :invalid_uuid}
  
  def validate_timestamp(%DateTime{} = dt), do: {:ok, dt}
  def validate_timestamp(_), do: {:error, :invalid_timestamp}
  
  def validate_non_empty_string(value) when is_binary(value) and byte_size(value) > 0 do
    {:ok, value}
  end
  
  def validate_non_empty_string(_), do: {:error, :empty_string}
end
```

### Step 2: Agent Type Implementation

Create `lib/elixir_ml/foundation/types/agent.ex`:

```elixir
defmodule ElixirML.Foundation.Types.Agent do
  @moduledoc """
  Core agent structure with comprehensive field definitions.
  
  Based on unified vision documents 011-012, this structure provides
  the foundation for all agent implementations in the system.
  """
  
  alias ElixirML.Foundation.Types
  
  @enforce_keys [:id, :name, :behavior]
  defstruct [
    # Core Identity (required)
    :id,                    # String.t() - UUID
    :name,                  # atom() - human-readable name
    :behavior,              # module() - behavior implementation
    
    # State Management
    state: %{},            # map() - agent's internal state
    variables: %{},        # %{atom() => Variable.t()}
    config: %{},           # map() - configuration
    
    # Capabilities and Actions
    actions: %{},          # %{atom() => Action.t()}
    capabilities: [],      # [atom()] - granted capabilities
    
    # Skills System Integration
    skills: %{},           # %{atom() => Skill.t()}
    skill_state: %{},      # %{atom() => term()}
    skill_routes: %{},     # %{String.t() => {atom(), atom()}}
    
    # Communication
    subscriptions: [],     # [String.t()] - event subscriptions
    message_queue: [],     # [Message.t()] - pending messages
    
    # Lifecycle Management
    status: :initializing, # agent_status()
    created_at: nil,       # DateTime.t()
    updated_at: nil,       # DateTime.t()
    
    # Extensibility
    metadata: %{},         # map() - additional metadata
    version: "1.0.0"       # String.t() - agent version
  ]
  
  @type t :: %__MODULE__{
    id: String.t(),
    name: atom(),
    behavior: module(),
    state: map(),
    variables: %{atom() => Types.variable()},
    config: map(),
    actions: %{atom() => Types.action()},
    capabilities: [atom()],
    skills: %{atom() => Types.skill()},
    skill_state: %{atom() => term()},
    skill_routes: %{String.t() => {atom(), atom()}},
    subscriptions: [String.t()],
    message_queue: [Types.event()],
    status: agent_status(),
    created_at: DateTime.t() | nil,
    updated_at: DateTime.t() | nil,
    metadata: map(),
    version: String.t()
  }
  
  @type agent_status :: :initializing | :running | :paused | :stopping | :stopped | :error
  
  @doc """
  Creates a new agent with required fields and validation.
  """
  def new(name, behavior, opts \\ []) do
    id = Keyword.get(opts, :id, UUID.uuid4())
    now = DateTime.utc_now()
    
    %__MODULE__{
      id: id,
      name: name,
      behavior: behavior,
      config: Keyword.get(opts, :config, %{}),
      capabilities: Keyword.get(opts, :capabilities, []),
      created_at: now,
      updated_at: now,
      metadata: Keyword.get(opts, :metadata, %{})
    }
    |> validate()
  end
  
  @doc """
  Validates agent structure and constraints.
  """
  def validate(%__MODULE__{} = agent) do
    with {:ok, _} <- Types.validate_uuid(agent.id),
         {:ok, _} <- validate_name(agent.name),
         {:ok, _} <- validate_behavior(agent.behavior),
         {:ok, _} <- validate_status(agent.status) do
      {:ok, agent}
    else
      {:error, reason} -> {:error, {:validation_failed, reason}}
    end
  end
  
  def validate(_), do: {:error, :invalid_agent_struct}
  
  @doc """
  Updates agent status with timestamp.
  """
  def update_status(%__MODULE__{} = agent, new_status) do
    with {:ok, _} <- validate_status(new_status) do
      {:ok, %{agent | status: new_status, updated_at: DateTime.utc_now()}}
    end
  end
  
  @doc """
  Adds a capability to the agent.
  """
  def add_capability(%__MODULE__{} = agent, capability) when is_atom(capability) do
    if capability in agent.capabilities do
      {:ok, agent}
    else
      {:ok, %{agent | capabilities: [capability | agent.capabilities], updated_at: DateTime.utc_now()}}
    end
  end
  
  @doc """
  Removes a capability from the agent.
  """
  def remove_capability(%__MODULE__{} = agent, capability) do
    {:ok, %{agent | capabilities: List.delete(agent.capabilities, capability), updated_at: DateTime.utc_now()}}
  end
  
  @doc """
  Checks if agent has a specific capability.
  """
  def has_capability?(%__MODULE__{} = agent, capability) do
    capability in agent.capabilities
  end
  
  @doc """
  Adds an action to the agent.
  """
  def add_action(%__MODULE__{} = agent, action_name, action) when is_atom(action_name) do
    {:ok, %{agent | 
      actions: Map.put(agent.actions, action_name, action),
      updated_at: DateTime.utc_now()
    }}
  end
  
  @doc """
  Gets an action by name.
  """
  def get_action(%__MODULE__{} = agent, action_name) do
    case Map.get(agent.actions, action_name) do
      nil -> {:error, :action_not_found}
      action -> {:ok, action}
    end
  end
  
  # Private validation functions
  defp validate_name(name) when is_atom(name), do: {:ok, name}
  defp validate_name(_), do: {:error, :invalid_name}
  
  defp validate_behavior(behavior) when is_atom(behavior) do
    if Code.ensure_loaded?(behavior) do
      {:ok, behavior}
    else
      {:error, :behavior_not_found}
    end
  end
  
  defp validate_behavior(_), do: {:error, :invalid_behavior}
  
  defp validate_status(status) when status in [:initializing, :running, :paused, :stopping, :stopped, :error] do
    {:ok, status}
  end
  
  defp validate_status(_), do: {:error, :invalid_status}
end
```

### Step 3: Agent Behavior Protocol

Create `lib/elixir_ml/foundation/agent_behaviour.ex`:

```elixir
defmodule ElixirML.Foundation.AgentBehaviour do
  @moduledoc """
  Behavior specification for Foundation agents.
  
  All Foundation agents must implement this behavior to ensure
  consistent interaction patterns and lifecycle management.
  
  Based on unified vision documents 011-012.
  """
  
  alias ElixirML.Foundation.Types.{Agent, Action, Signal, Directive, Event}
  
  @doc """
  Initialize the agent with configuration.
  
  Called when the agent is first started. Should return the initial
  state that will be managed by the agent process.
  
  ## Parameters
  - `config` - Agent configuration map
  
  ## Returns
  - `{:ok, state}` - Successful initialization
  - `{:error, reason}` - Initialization failed
  """
  @callback init(config :: map()) :: 
    {:ok, state :: term()} | {:error, reason :: term()}
  
  @doc """
  Handle action execution requests.
  
  Called when an action is requested to be executed by this agent.
  The action should be validated, executed, and the result returned.
  
  ## Parameters
  - `action` - The action to execute
  - `params` - Parameters for the action
  - `state` - Current agent state
  
  ## Returns
  - `{:ok, result, new_state}` - Action executed successfully
  - `{:error, reason, state}` - Action execution failed
  """
  @callback handle_action(action :: Action.t(), params :: map(), state :: term()) ::
    {:ok, result :: term(), new_state :: term()} |
    {:error, reason :: term(), state :: term()}
  
  @doc """
  Handle incoming signals from sensors.
  
  Called when a sensor generates a signal that this agent has
  subscribed to. Agents can react to signals by updating state
  or triggering actions.
  
  ## Parameters
  - `signal` - The signal to handle
  - `state` - Current agent state
  
  ## Returns
  - `{:noreply, new_state}` - Signal handled, continue
  - `{:stop, reason, new_state}` - Signal handling caused agent to stop
  """
  @callback handle_signal(signal :: Signal.t(), state :: term()) ::
    {:noreply, new_state :: term()} |
    {:stop, reason :: term(), new_state :: term()}
  
  @doc """
  Handle directive execution.
  
  Called when a directive is sent to modify agent behavior or state.
  Directives should be validated before execution.
  
  ## Parameters
  - `directive` - The directive to execute
  - `state` - Current agent state
  
  ## Returns
  - `{:ok, new_state}` - Directive executed successfully
  - `{:error, reason, state}` - Directive execution failed
  """
  @callback handle_directive(directive :: Directive.t(), state :: term()) ::
    {:ok, new_state :: term()} |
    {:error, reason :: term(), state :: term()}
  
  @doc """
  Handle general messages.
  
  Called for any other messages not covered by specific handlers.
  This is the catch-all for inter-agent communication.
  
  ## Parameters
  - `message` - The message to handle
  - `state` - Current agent state
  
  ## Returns
  - `{:noreply, new_state}` - Message handled, continue
  - `{:reply, response, new_state}` - Message handled, send response
  - `{:stop, reason, new_state}` - Message handling caused agent to stop
  """
  @callback handle_message(message :: Event.t(), state :: term()) ::
    {:noreply, new_state :: term()} |
    {:reply, response :: term(), new_state :: term()} |
    {:stop, reason :: term(), new_state :: term()}
  
  @doc """
  Handle agent termination.
  
  Called when the agent is shutting down. Should perform any
  necessary cleanup operations.
  
  ## Parameters
  - `reason` - Reason for termination
  - `state` - Final agent state
  
  ## Returns
  - Any term (ignored)
  """
  @callback terminate(reason :: term(), state :: term()) :: term()
  
  # Make terminate/2 optional
  @optional_callbacks [terminate: 2]
  
  @doc """
  Convenience macro for implementing agents.
  
  Provides default implementations for common patterns.
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour ElixirML.Foundation.AgentBehaviour
      
      # Default terminate implementation
      def terminate(_reason, _state), do: :ok
      
      # Default message handler
      def handle_message(_message, state), do: {:noreply, state}
      
      defoverridable [terminate: 2, handle_message: 2]
    end
  end
end
```

### Step 4: Basic Agent Implementation

Create `lib/elixir_ml/foundation/agent.ex`:

```elixir
defmodule ElixirML.Foundation.Agent do
  @moduledoc """
  Core agent implementation using GenServer.
  
  Provides the runtime infrastructure for Foundation agents with:
  - Lifecycle management
  - Action execution
  - Signal handling
  - Directive processing
  - Resource management integration
  
  Based on unified vision documents 011-012.
  """
  
  use GenServer
  require Logger
  
  alias ElixirML.Foundation.Types.{Agent, Action, Signal, Directive, Event}
  alias ElixirML.Foundation.{Registry, EventBus, Resources}
  
  @doc """
  Starts an agent with the given configuration.
  """
  def start_link(agent_config) do
    {agent_name, config} = extract_agent_config(agent_config)
    GenServer.start_link(__MODULE__, config, name: {:via, Registry, {ElixirML.Foundation.Registry, agent_name}})
  end
  
  @doc """
  Executes an action on the specified agent.
  """
  def execute_action(agent_ref, action_name, params \\ %{}) do
    GenServer.call(agent_ref, {:execute_action, action_name, params})
  end
  
  @doc """
  Sends a signal to the agent.
  """
  def handle_signal(agent_ref, signal) do
    GenServer.cast(agent_ref, {:handle_signal, signal})
  end
  
  @doc """
  Applies a directive to the agent.
  """
  def apply_directive(agent_ref, directive) do
    GenServer.call(agent_ref, {:apply_directive, directive})
  end
  
  @doc """
  Gets the current agent state information.
  """
  def get_info(agent_ref) do
    GenServer.call(agent_ref, :get_info)
  end
  
  # GenServer callbacks
  
  def init(%{agent: agent, behavior: behavior} = config) do
    Logger.info("Starting agent #{agent.name} with behavior #{behavior}")
    
    # Initialize the behavior
    case behavior.init(config) do
      {:ok, behavior_state} ->
        state = %{
          agent: agent,
          behavior: behavior,
          behavior_state: behavior_state,
          last_activity: DateTime.utc_now()
        }
        
        # Subscribe to relevant events
        subscribe_to_events(agent.subscriptions)
        
        {:ok, state}
        
      {:error, reason} ->
        Logger.error("Failed to initialize agent #{agent.name}: #{inspect(reason)}")
        {:stop, {:init_failed, reason}}
    end
  end
  
  def handle_call({:execute_action, action_name, params}, _from, state) do
    %{agent: agent, behavior: behavior, behavior_state: behavior_state} = state
    
    with {:ok, action} <- Agent.get_action(agent, action_name),
         :ok <- check_capabilities(agent, action.capabilities),
         {:ok, validated_params} <- validate_action_params(action, params),
         {:ok, result, new_behavior_state} <- behavior.handle_action(action, validated_params, behavior_state) do
      
      new_state = %{state | 
        behavior_state: new_behavior_state,
        last_activity: DateTime.utc_now()
      }
      
      Logger.debug("Agent #{agent.name} executed action #{action_name}")
      {:reply, {:ok, result}, new_state}
    else
      {:error, reason} ->
        Logger.warning("Action execution failed for #{agent.name}.#{action_name}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call({:apply_directive, directive}, _from, state) do
    %{agent: agent, behavior: behavior, behavior_state: behavior_state} = state
    
    case behavior.handle_directive(directive, behavior_state) do
      {:ok, new_behavior_state} ->
        new_state = %{state | 
          behavior_state: new_behavior_state,
          last_activity: DateTime.utc_now()
        }
        Logger.debug("Agent #{agent.name} applied directive #{directive.action}")
        {:reply, :ok, new_state}
        
      {:error, reason, behavior_state} ->
        Logger.warning("Directive application failed for #{agent.name}: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end
  
  def handle_call(:get_info, _from, state) do
    info = %{
      agent: state.agent,
      status: :running,
      last_activity: state.last_activity,
      uptime: DateTime.diff(DateTime.utc_now(), state.agent.created_at, :millisecond)
    }
    {:reply, info, state}
  end
  
  def handle_cast({:handle_signal, signal}, state) do
    %{agent: agent, behavior: behavior, behavior_state: behavior_state} = state
    
    case behavior.handle_signal(signal, behavior_state) do
      {:noreply, new_behavior_state} ->
        new_state = %{state | 
          behavior_state: new_behavior_state,
          last_activity: DateTime.utc_now()
        }
        {:noreply, new_state}
        
      {:stop, reason, new_behavior_state} ->
        Logger.info("Agent #{agent.name} stopping due to signal: #{inspect(reason)}")
        new_state = %{state | behavior_state: new_behavior_state}
        {:stop, reason, new_state}
    end
  end
  
  def handle_info({:event, event}, state) do
    %{agent: agent, behavior: behavior, behavior_state: behavior_state} = state
    
    case behavior.handle_message(event, behavior_state) do
      {:noreply, new_behavior_state} ->
        new_state = %{state | 
          behavior_state: new_behavior_state,
          last_activity: DateTime.utc_now()
        }
        {:noreply, new_state}
        
      {:reply, response, new_behavior_state} ->
        # Send response back via event bus
        EventBus.publish(create_response_event(event, response, agent))
        new_state = %{state | behavior_state: new_behavior_state}
        {:noreply, new_state}
        
      {:stop, reason, new_behavior_state} ->
        Logger.info("Agent #{agent.name} stopping due to message: #{inspect(reason)}")
        new_state = %{state | behavior_state: new_behavior_state}
        {:stop, reason, new_state}
    end
  end
  
  def terminate(reason, state) do
    %{agent: agent, behavior: behavior, behavior_state: behavior_state} = state
    
    Logger.info("Agent #{agent.name} terminating: #{inspect(reason)}")
    
    # Call behavior terminate if implemented
    if function_exported?(behavior, :terminate, 2) do
      behavior.terminate(reason, behavior_state)
    end
    
    :ok
  end
  
  # Private helper functions
  
  defp extract_agent_config(%{agent: %Agent{} = agent, behavior: behavior} = config) do
    {agent.name, %{agent: agent, behavior: behavior}}
  end
  
  defp extract_agent_config(%{name: name} = config) do
    {name, config}
  end
  
  defp subscribe_to_events(subscriptions) do
    Enum.each(subscriptions, fn topic ->
      EventBus.subscribe(topic)
    end)
  end
  
  defp check_capabilities(agent, required_capabilities) do
    missing = required_capabilities -- agent.capabilities
    
    if Enum.empty?(missing) do
      :ok
    else
      {:error, {:missing_capabilities, missing}}
    end
  end
  
  defp validate_action_params(action, params) do
    # TODO: Implement schema validation when action framework is complete
    {:ok, params}
  end
  
  defp create_response_event(original_event, response, agent) do
    %Event{
      id: UUID.uuid4(),
      source: "agent://#{agent.id}",
      type: "io.elixirml.agent.response",
      specversion: "1.0",
      time: DateTime.utc_now(),
      data: %{
        response: response,
        in_response_to: original_event.id
      }
    }
  end
end
```

### Step 5: Initial Test Setup

Create `test/elixir_ml/foundation/types/agent_test.exs`:

```elixir
defmodule ElixirML.Foundation.Types.AgentTest do
  use ExUnit.Case, async: true
  doctest ElixirML.Foundation.Types.Agent
  
  alias ElixirML.Foundation.Types.Agent
  
  describe "new/3" do
    test "creates agent with required fields" do
      assert {:ok, agent} = Agent.new(:test_agent, TestBehavior)
      
      assert agent.name == :test_agent
      assert agent.behavior == TestBehavior
      assert is_binary(agent.id)
      assert agent.status == :initializing
      assert %DateTime{} = agent.created_at
      assert %DateTime{} = agent.updated_at
    end
    
    test "accepts optional configuration" do
      config = %{timeout: 5000, memory_limit: "100MB"}
      capabilities = [:read_files, :network_access]
      
      assert {:ok, agent} = Agent.new(:test_agent, TestBehavior, 
        config: config, 
        capabilities: capabilities
      )
      
      assert agent.config == config
      assert agent.capabilities == capabilities
    end
    
    test "validates required fields" do
      assert {:error, _} = Agent.new(nil, TestBehavior)
      assert {:error, _} = Agent.new(:test, nil)
    end
  end
  
  describe "update_status/2" do
    test "updates status and timestamp" do
      {:ok, agent} = Agent.new(:test_agent, TestBehavior)
      original_time = agent.updated_at
      
      Process.sleep(1) # Ensure time difference
      
      assert {:ok, updated_agent} = Agent.update_status(agent, :running)
      assert updated_agent.status == :running
      assert DateTime.compare(updated_agent.updated_at, original_time) == :gt
    end
    
    test "validates status values" do
      {:ok, agent} = Agent.new(:test_agent, TestBehavior)
      
      assert {:ok, _} = Agent.update_status(agent, :running)
      assert {:ok, _} = Agent.update_status(agent, :paused)
      assert {:ok, _} = Agent.update_status(agent, :stopped)
      assert {:error, _} = Agent.update_status(agent, :invalid_status)
    end
  end
  
  describe "capability management" do
    test "adds capabilities" do
      {:ok, agent} = Agent.new(:test_agent, TestBehavior)
      
      assert {:ok, updated_agent} = Agent.add_capability(agent, :file_access)
      assert :file_access in updated_agent.capabilities
      assert Agent.has_capability?(updated_agent, :file_access)
    end
    
    test "removes capabilities" do
      {:ok, agent} = Agent.new(:test_agent, TestBehavior, capabilities: [:file_access, :network])
      
      assert {:ok, updated_agent} = Agent.remove_capability(agent, :file_access)
      refute :file_access in updated_agent.capabilities
      assert :network in updated_agent.capabilities
    end
    
    test "handles duplicate capability additions" do
      {:ok, agent} = Agent.new(:test_agent, TestBehavior, capabilities: [:file_access])
      
      assert {:ok, updated_agent} = Agent.add_capability(agent, :file_access)
      assert length(updated_agent.capabilities) == 1
    end
  end
  
  describe "action management" do
    test "adds and retrieves actions" do
      {:ok, agent} = Agent.new(:test_agent, TestBehavior)
      action = create_test_action()
      
      assert {:ok, updated_agent} = Agent.add_action(agent, :test_action, action)
      assert {:ok, retrieved_action} = Agent.get_action(updated_agent, :test_action)
      assert retrieved_action == action
    end
    
    test "handles missing actions" do
      {:ok, agent} = Agent.new(:test_agent, TestBehavior)
      
      assert {:error, :action_not_found} = Agent.get_action(agent, :missing_action)
    end
  end
  
  # Helper functions
  defp create_test_action do
    %ElixirML.Foundation.Types.Action{
      name: :test_action,
      handler: fn _, _ -> {:ok, "test result"} end,
      capabilities: [],
      timeout: 5000
    }
  end
end

# Mock behavior for testing
defmodule TestBehavior do
  @behaviour ElixirML.Foundation.AgentBehaviour
  
  def init(_config), do: {:ok, %{}}
  def handle_action(_action, _params, state), do: {:ok, :test_result, state}
  def handle_signal(_signal, state), do: {:noreply, state}
  def handle_directive(_directive, state), do: {:ok, state}
  def handle_message(_message, state), do: {:noreply, state}
end
```

## Immediate Next Steps

### 1. Run Initial Setup

```bash
# Install dependencies
mix deps.get

# Create the initial file structure
# (Run the mkdir commands from above)

# Create the initial files
# (Copy the code templates above)

# Run initial tests
mix test test/elixir_ml/foundation/types/agent_test.exs
```

### 2. Validate Bootstrap

Ensure the bootstrap is working correctly:

```bash
# Compile the project
mix compile

# Check for warnings or errors
mix compile --warnings-as-errors

# Run the test suite
mix test

# Check test coverage (if installed)
mix test --cover
```

### 3. Continue with Phase 1

Once the bootstrap is validated:

1. Implement remaining type definitions (Variable, Action, Event, etc.)
2. Create basic infrastructure (EventBus, Registry, Supervisor)
3. Build out the agent framework
4. Add comprehensive test coverage

### 4. Development Workflow

Establish the development workflow:

```bash
# Before each commit
mix format
mix compile --warnings-as-errors
mix test
mix credo --strict
mix dialyzer
```

## Success Criteria for Bootstrap

- [ ] Project compiles without warnings
- [ ] Basic Agent type implemented and tested
- [ ] AgentBehaviour protocol defined
- [ ] Core Agent GenServer implementation working
- [ ] Initial test suite passing
- [ ] Directory structure established
- [ ] Dependencies added and working

This bootstrap provides the immediate foundation to begin implementing the complete Foundation Layer according to the unified vision and technical specifications.