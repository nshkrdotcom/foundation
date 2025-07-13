# Lessons Learned 002: Implementation Patterns from Jido Analysis

## Executive Summary

This document provides concrete implementation patterns learned from deep analysis of the Jido codebase. These patterns represent production-ready approaches to building agent-based systems in Elixir and should guide Foundation's architectural evolution.

## Pattern 1: Agent Definition vs Runtime Separation

### The Jido Pattern
Jido cleanly separates agent **definition** (compile-time) from agent **execution** (runtime):

```elixir
# COMPILE-TIME: Agent Definition
defmodule MyAgent do
  use Jido.Agent,
    name: "my_agent",
    description: "Processes complex workflows",
    schema: [
      status: [type: :atom, values: [:pending, :running, :complete]],
      retries: [type: :integer, default: 3]
    ],
    actions: [ProcessAction, ValidateAction]
  
  # Optional lifecycle callbacks
  def on_before_run(agent) do
    if agent.state.status == :ready do
      {:ok, agent}
    else
      {:error, "Agent not ready"}
    end
  end
end

# RUNTIME: Agent Execution
{:ok, agent_pid} = MyAgent.start_link(id: "agent_001")
{:ok, result} = MyAgent.cmd(agent_pid, ProcessAction, %{data: "input"})
```

### Key Insights
1. **Compile-time validation** prevents runtime errors
2. **Schema-driven state management** ensures type safety
3. **Lifecycle callbacks** enable custom behavior
4. **Clean separation** allows testing at both levels

### Foundation Implementation Recommendation
```elixir
# Foundation should adopt this pattern
defmodule Foundation.Agent do
  defmacro __using__(opts) do
    quote do
      @behaviour Foundation.Agent
      # Generate struct with enforced schema
      # Validate actions at compile time
      # Create type-safe state management
    end
  end
end

defmodule Foundation.Agent.Server do
  use GenServer
  # Handle runtime execution
  # Manage agent lifecycle
  # Process signals and actions
end
```

## Pattern 2: CloudEvents-Compliant Signal Architecture

### The Jido Pattern
Jido implements **CloudEvents v1.0.2** specification with extensions:

```elixir
# Core Signal Structure
%Jido.Signal{
  # CloudEvents required fields
  specversion: "1.0.2",
  id: "uuid-here",
  source: "/service/component",
  type: "domain.entity.action",
  
  # CloudEvents optional fields  
  subject: "specific-resource",
  time: "2024-01-01T00:00:00Z",
  datacontenttype: "application/json",
  data: %{payload: "here"},
  
  # Jido extensions
  jido_dispatch: {:pubsub, topic: "events"}
}

# Custom Signal Types
defmodule UserCreatedSignal do
  use Jido.Signal,
    type: "user.created",
    default_source: "/auth/service",
    schema: [
      user_id: [type: :string, required: true],
      email: [type: :string, required: true]
    ]
end

# Usage
{:ok, signal} = UserCreatedSignal.new(%{
  user_id: "123",
  email: "user@example.com"
})
```

### Sophisticated Routing
```elixir
# Trie-based Router with Pattern Matching
{:ok, router} = Jido.Signal.Router.new([
  # Exact matches
  {"user.created", HandleUserCreated},
  
  # Single wildcards (matches one segment)
  {"user.*.updated", HandleUserUpdates},
  
  # Multi-level wildcards (matches zero or more)
  {"audit.**", AuditLogger, 100}, # High priority
  
  # Pattern matching functions
  {"payment.processed", 
    fn signal -> signal.data.amount > 1000 end,
    HandleLargePayment},
    
  # Multiple dispatch targets
  {"system.error", [
    {MetricsCollector, [type: :error]},
    {AlertManager, [severity: :high]},
    {LogService, [level: :error]}
  ]}
])

# Route signals
{:ok, handlers} = Router.route(router, signal)
```

### Foundation Implementation Recommendation
```elixir
# Replace Foundation's event system with CloudEvents
defmodule Foundation.Signal do
  use TypedStruct
  
  # Implement CloudEvents v1.0.2 compliance
  typedstruct do
    field(:specversion, String.t(), default: "1.0.2")
    field(:id, String.t(), enforce: true)
    field(:source, String.t(), enforce: true) 
    field(:type, String.t(), enforce: true)
    # ... other CloudEvents fields
  end
  
  # Add Foundation-specific extensions
  field(:foundation_metadata, map())
  field(:foundation_dispatch, term())
end

defmodule Foundation.Signal.Router do
  # Implement trie-based routing
  # Support wildcard patterns
  # Handle priority and pattern matching
end
```

## Pattern 3: Action System with Directives

### The Jido Pattern
Actions can return **directives** that modify agent state:

```elixir
defmodule ProcessDataAction do
  use Jido.Action,
    name: "process_data",
    schema: [
      input: [type: :string, required: true],
      validate: [type: :boolean, default: true]
    ],
    output_schema: [
      result: [type: :string, required: true],
      status: [type: :atom, required: true]
    ]
  
  @impl true
  def run(params, context) do
    # Process the data
    result = String.upcase(params.input)
    
    # Return result with state modification directives
    {:ok, 
     %{result: result, status: :completed},
     [
       # Modify agent state
       %StateModification{
         op: :set, 
         path: [:last_processed], 
         value: DateTime.utc_now()
       },
       
       # Enqueue next action if validation needed
       if params.validate do
         %ActionEnqueue{
           action: ValidateResultAction,
           params: %{data: result}
         }
       end
     ] |> Enum.reject(&is_nil/1)}
  end
end
```

### Directive Types Available
```elixir
# State Modification Directives
%StateModification{op: :set, path: [:config, :mode], value: :active}
%StateModification{op: :update, path: [:counter], value: &(&1 + 1)}
%StateModification{op: :delete, path: [:temp_data]}
%StateModification{op: :reset, path: [:cache]}

# Action Management Directives  
%ActionEnqueue{action: NextAction, params: %{}, priority: :high}
%ActionRegister{action: DynamicAction}
%ActionDeregister{action: OldAction}

# Process Management Directives
%ProcessStart{spec: child_spec, id: :worker_pool}
%ProcessStop{id: :worker_pool, reason: :shutdown}
```

### Foundation Implementation Recommendation
```elixir
defmodule Foundation.Action do
  @type directive :: Foundation.Agent.Directive.t()
  @type action_result ::
    {:ok, map()} |
    {:ok, map(), directive() | [directive()]} |
    {:error, any()} |
    {:error, any(), directive() | [directive()]}
    
  @callback run(params :: map(), context :: map()) :: action_result()
end

defmodule Foundation.Agent.Directive do
  # Define directive types for Foundation
  # Handle state modifications
  # Manage action queues
  # Control child processes
end
```

## Pattern 4: GenServer-Based Agent Runtime

### The Jido Pattern
Agent.Server implements sophisticated GenServer patterns:

```elixir
defmodule Jido.Agent.Server do
  use GenServer
  
  # Proper initialization with validation
  def init(opts) do
    with {:ok, agent} <- build_agent(opts),
         {:ok, state} <- build_initial_state(opts),
         {:ok, state} <- register_actions(state),
         {:ok, state} <- setup_skills(state),
         {:ok, state} <- setup_routing(state) do
      {:ok, state}
    else
      {:error, reason} -> {:stop, reason}
    end
  end
  
  # Signal-based communication
  def handle_call({:signal, signal}, from, state) do
    # Store reply reference for async processing
    state = store_reply_ref(state, signal.id, from)
    
    # Enqueue signal for processing
    case enqueue_signal(state, signal) do
      {:ok, new_state} ->
        # Trigger async processing
        Process.send_after(self(), :process_queue, 0)
        {:noreply, new_state}
      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end
  
  # Async queue processing
  def handle_info(:process_queue, state) do
    case dequeue_and_process(state) do
      {:ok, new_state} -> {:noreply, new_state}
      {:error, reason} -> {:noreply, handle_error(state, reason)}
    end
  end
  
  # Proper shutdown handling
  def terminate(reason, state) do
    cleanup_resources(state)
    shutdown_child_processes(state)
    emit_shutdown_signal(state, reason)
    :ok
  end
end
```

### Key Patterns
1. **Validation in init/1** prevents invalid states
2. **Signal queuing** enables async processing  
3. **Reply reference storage** handles sync/async correctly
4. **Proper resource cleanup** in terminate/2
5. **Process monitoring** for child processes

### Foundation Implementation Recommendation
```elixir
defmodule Foundation.Agent.Server do
  use GenServer
  
  # Follow Jido's initialization pattern
  def init(opts) do
    with {:ok, validated_opts} <- validate_options(opts),
         {:ok, agent} <- create_agent(validated_opts),
         {:ok, state} <- initialize_state(agent, validated_opts),
         {:ok, state} <- setup_infrastructure(state) do
      {:ok, state}
    else
      {:error, reason} -> {:stop, reason}
    end
  end
  
  # Implement signal-based communication
  # Add proper queue management
  # Handle resource cleanup
end
```

## Pattern 5: Comprehensive Testing Strategies

### The Jido Test Structure
```
test/
├── jido/
│   ├── agent/               # Agent behavior tests
│   │   ├── agent_cmd_test.exs
│   │   ├── agent_state_test.exs
│   │   └── server_test.exs
│   ├── actions/             # Action implementation tests
│   │   ├── basic_test.exs
│   │   └── workflow_test.exs
│   ├── signal/              # Signal routing tests
│   │   ├── router_test.exs
│   │   └── bus_test.exs
│   └── integration/         # End-to-end tests
├── support/                 # Test helpers
│   ├── test_agent.ex
│   ├── test_actions.ex
│   └── assertions.ex
└── test_helper.exs
```

### Testing Patterns
```elixir
# Agent Lifecycle Testing
defmodule AgentLifecycleTest do
  use ExUnit.Case
  
  test "agent initialization and state management" do
    {:ok, agent} = TestAgent.new(id: "test_001")
    assert agent.state.status == :pending
    
    {:ok, updated_agent} = TestAgent.set(agent, status: :running)
    assert updated_agent.state.status == :running
    assert updated_agent.dirty_state? == true
  end
  
  test "action execution with directives" do
    {:ok, agent} = TestAgent.new()
    {:ok, agent} = TestAgent.register_action(agent, TestAction)
    
    {:ok, agent, directives} = TestAgent.cmd(agent, TestAction, %{input: "test"})
    
    assert agent.result.output == "PROCESSED: test"
    assert length(directives) > 0
  end
end

# Signal Routing Testing  
defmodule SignalRoutingTest do
  use ExUnit.Case
  
  test "wildcard pattern matching" do
    {:ok, router} = Router.new([
      {"user.*", UserHandler},
      {"audit.**", AuditHandler}
    ])
    
    user_signal = %Signal{type: "user.created", ...}
    {:ok, [UserHandler]} = Router.route(router, user_signal)
    
    audit_signal = %Signal{type: "audit.user.login", ...}  
    {:ok, [AuditHandler]} = Router.route(router, audit_signal)
  end
end

# Integration Testing
defmodule IntegrationTest do
  use ExUnit.Case
  
  test "full agent workflow" do
    # Start agent
    {:ok, pid} = TestAgent.start_link(id: "integration_test")
    
    # Send signal
    {:ok, signal_id} = TestAgent.cast(pid, test_signal)
    
    # Verify processing
    :timer.sleep(100)
    {:ok, state} = TestAgent.state(pid)
    assert state.last_signal_id == signal_id
  end
end
```

### Foundation Testing Recommendations
1. **Adopt Jido's test structure** for consistency
2. **Test agent lifecycle comprehensively** (init, state changes, shutdown)
3. **Test signal routing patterns** (exact, wildcards, priorities)
4. **Add integration tests** for end-to-end workflows
5. **Use property-based testing** for edge cases

## Pattern 6: Configuration and Validation

### The Jido Pattern
Comprehensive validation at multiple levels:

```elixir
# Compile-time configuration validation
@agent_schema NimbleOptions.new!(
  name: [type: :string, required: true],
  actions: [type: {:list, :atom}, default: []],
  schema: [type: :keyword_list, default: []]
)

# Runtime parameter validation  
def validate_params(params) do
  with {:ok, params} <- on_before_validate_params(params),
       {:ok, validated} <- do_validate_params(params),
       {:ok, final} <- on_after_validate_params(validated) do
    {:ok, final}
  end
end

# State validation with callbacks
def validate_state(agent) do
  with {:ok, agent} <- on_before_validate_state(agent),
       {:ok, validated_state} <- validate_against_schema(agent.state),
       {:ok, agent} <- on_after_validate_state(agent) do
    {:ok, agent}
  end
end
```

### Foundation Implementation Recommendation
```elixir
defmodule Foundation.Validation do
  # Standardize validation patterns across Foundation
  # Use NimbleOptions for schema validation
  # Implement callback-based validation hooks
  # Provide clear error messages with context
end
```

## Conclusion

These implementation patterns represent proven approaches to building production-ready agent systems. Foundation should adopt these patterns systematically:

1. **Agent Definition/Runtime Separation** - Enables type safety and testing
2. **CloudEvents Signal Architecture** - Provides standards compliance and interoperability  
3. **Directive-Based Actions** - Enables sophisticated state management
4. **Proper GenServer Patterns** - Ensures reliability and fault tolerance
5. **Comprehensive Testing** - Validates behavior at all levels
6. **Multi-Level Validation** - Prevents errors at compile and runtime

The next document will provide specific integration strategies for migrating Foundation to these patterns.

---

**Status**: Implementation patterns analysis complete  
**Next**: Integration strategies document (_lessonsLearned_003)