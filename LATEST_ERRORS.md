[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
..[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] Registered Jido agent #PID<0.1813.0> with Foundation
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] Registered Jido agent #PID<0.1818.0> with Foundation
[info] Registered Jido agent #PID<0.1819.0> with Foundation
[info] Registered Jido agent #PID<0.1820.0> with Foundation
[info] Registered Jido agent #PID<0.1821.0> with Foundation
[info] Registered Jido agent #PID<0.1822.0> with Foundation
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] Registered Jido agent #PID<0.1826.0> with Foundation
[error] GenServer #PID<0.1826.0> terminating
** (RuntimeError) Simulated crash
    test/jido_foundation/bridge_test.exs:28: JidoFoundation.BridgeTest.MockJidoAgent.handle_call/3
    (stdlib 6.2.2) gen_server.erl:2381: :gen_server.try_handle_call/4
    (stdlib 6.2.2) gen_server.erl:2410: :gen_server.handle_msg/6
    (stdlib 6.2.2) proc_lib.erl:329: :proc_lib.init_p_do_apply/3
Last message (from #PID<0.1824.0>): {:execute, :crash}
[info] Agent #PID<0.1826.0> process died ({%RuntimeError{message: "Simulated crash"}, [{JidoFoundation.BridgeTest.MockJidoAgent, :handle_call, 3, [file: ~c"test/jido_foundation/bridge_test.exs", line: 28, error_info: %{module: Exception}]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2381]}, {:gen_server, :handle_msg, 6, [file: ~c"gen_server.erl", line: 2410]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 329]}]}), cleaning up
[warning] Jido action process exited: {{%RuntimeError{message: "Simulated crash"}, [{JidoFoundation.BridgeTest.MockJidoAgent, :handle_call, 3, [file: ~c"test/jido_foundation/bridge_test.exs", line: 28, error_info: %{module: Exception}]}, {:gen_server, :try_handle_call, 4, [file: ~c"gen_server.erl", line: 2381]}, {:gen_server, :handle_msg, 6, [file: ~c"gen_server.erl", line: 2410]}, {:proc_lib, :init_p_do_apply, 3, [file: ~c"proc_lib.erl", line: 329]}]}, {GenServer, :call, [#PID<0.1826.0>, {:execute, :crash}, 5000]}}
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[error] Failed to register Jido agent: %Foundation.ErrorHandler.Error{category: :system, reason: :process_not_alive, context: %{retry_count: 1}, stacktrace: nil, timestamp: ~U[2025-06-29 01:23:52.712046Z], retry_count: 0, recovery_strategy: nil}
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] Registered Jido agent #PID<0.1839.0> with Foundation
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] Registered Jido agent #PID<0.1844.0> with Foundation
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] The function passed as a handler with ID "test-jido-events" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] Registered Jido agent #PID<0.1857.0> with Foundation
[info] Registered Jido agent #PID<0.1858.0> with Foundation
[info] Registered Jido agent #PID<0.1859.0> with Foundation
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] Registered Jido agent #PID<0.1867.0> with Foundation
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
....[info] Registered Jido agent #PID<0.1880.0> with Foundation
.[info] Registered Jido agent #PID<0.1884.0> with Foundation
[info] Registered Jido agent #PID<0.1886.0> with Foundation
[info] Registered Jido agent #PID<0.1887.0> with Foundation
[info] Registered Jido agent #PID<0.1888.0> with Foundation
..[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[warning] Max retries exceeded for agent #PID<0.1174.0>, final result: {:error, "attempt_2_failed"}
[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] Registered Jido agent #PID<0.1908.0> with Foundation
    warning: this clause for start_link/0 cannot match because a previous clause at line 10 always matches
    │
 10 │   while maintaining state validation, error handling, and extensibility through lifecycle hooks.
    │   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    │
    └─ deps/jido/lib/jido/agent.ex:10

[info] Retrying Jido action for agent #PID<0.1908.0>, attempt 1/3, delay: 50ms


  1) test error handling for missing configuration raises helpful error when registry implementation not configured (FoundationTest)
     test/foundation_test.exs:305
     Expected truthy, got false
     code: assert is_exception(exception)
     stacktrace:
       test/foundation_test.exs:318: (test)

...................    warning: variable "registry" is unused (if the variable is not meant to be used, prefix it with an underscore)
    │
 49 │     test "successfully initializes and registers with Foundation", %{registry: registry} do
    │                                                                                ~~~~~~~~
    │
    └─ test/jido_system/agents/foundation_agent_test.exs:49:80: JidoSystem.Agents.FoundationAgentTest."test agent initialization successfully initializes and registers with Foundation"/1

    warning: variable "pid" is unused (if the variable is not meant to be used, prefix it with an underscore)
    │
 94 │       {:ok, pid} = TestAgent.start_link(id: "test_agent_telemetry")
    │             ~~~
    │
    └─ test/jido_system/agents/foundation_agent_test.exs:94:13: JidoSystem.Agents.FoundationAgentTest."test agent initialization emits startup telemetry"/1

     warning: variable "registry" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 188 │     test "deregisters from Foundation on termination", %{registry: registry} do
     │                                                                    ~~~~~~~~
     │
     └─ test/jido_system/agents/foundation_agent_test.exs:188:68: JidoSystem.Agents.FoundationAgentTest."test agent termination deregisters from Foundation on termination"/1

     warning: variable "agent" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 237 │     test "emit_event helper works correctly", %{agent: agent, agent_state: agent_state} do
     │                                                        ~~~~~
     │
     └─ test/jido_system/agents/foundation_agent_test.exs:237:56: JidoSystem.Agents.FoundationAgentTest."test helper functions emit_event helper works correctly"/1

     warning: variable "agent" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 263 │     test "coordinate_with_agents helper initiates coordination", %{agent: agent, agent_state: agent_state} do
     │                                                                           ~~~~~
     │
     └─ test/jido_system/agents/foundation_agent_test.exs:263:75: JidoSystem.Agents.FoundationAgentTest."test helper functions coordinate_with_agents helper initiates coordination"/1

     warning: variable "registry" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 297 │     test "agent properly integrates with Foundation Registry", %{registry: registry} do
     │                                                                            ~~~~~~~~
     │
     └─ test/jido_system/agents/foundation_agent_test.exs:297:76: JidoSystem.Agents.FoundationAgentTest."test Foundation integration agent properly integrates with Foundation Registry"/1

     warning: variable "registry" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 315 │     test "multiple agents can be registered simultaneously", %{registry: registry} do
     │                                                                          ~~~~~~~~
     │
     └─ test/jido_system/agents/foundation_agent_test.exs:315:74: JidoSystem.Agents.FoundationAgentTest."test Foundation integration multiple agents can be registered simultaneously"/1

..[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] Registered Jido agent #PID<0.1934.0> with Foundation
[info] Registered Jido agent #PID<0.1935.0> with Foundation
[info] Registered Jido agent #PID<0.1936.0> with Foundation
[info] Retrying Jido action for agent #PID<0.1908.0>, attempt 2/3, delay: 100ms
    warning: unused alias Bridge
    │
  7 │   alias JidoFoundation.Bridge
    │   ~
    │
    └─ test/jido_system/agents/foundation_agent_test.exs:7:3

    warning: unused alias Registry
    │
  6 │   alias Foundation.{Registry, Telemetry}
    │   ~
    │
    └─ test/jido_system/agents/foundation_agent_test.exs:6:3

    warning: unused alias Telemetry
    │
  6 │   alias Foundation.{Registry, Telemetry}
    │   ~
    │
    └─ test/jido_system/agents/foundation_agent_test.exs:6:3

    warning: function count/1 required by protocol Foundation.Registry is not implemented (in module Foundation.Registry.FoundationTest.MockRegistry)
    │
 19 │   defimpl Foundation.Registry, for: MockRegistry do
    │   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    │
    └─ test/foundation_test.exs:19: Foundation.Registry.FoundationTest.MockRegistry (module)

    warning: function keys/2 required by protocol Foundation.Registry is not implemented (in module Foundation.Registry.FoundationTest.MockRegistry)
    │
 19 │   defimpl Foundation.Registry, for: MockRegistry do
    │   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    │
    └─ test/foundation_test.exs:19: Foundation.Registry.FoundationTest.MockRegistry (module)

    warning: function select/2 required by protocol Foundation.Registry is not implemented (in module Foundation.Registry.FoundationTest.MockRegistry)
    │
 19 │   defimpl Foundation.Registry, for: MockRegistry do
    │   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    │
    └─ test/foundation_test.exs:19: Foundation.Registry.FoundationTest.MockRegistry (module)

.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] Registered Jido agent #PID<0.1951.0> with Foundation
[error] Failed to register Jido agent: %Foundation.ErrorHandler.Error{category: :system, reason: :process_not_alive, context: %{retry_count: 1}, stacktrace: nil, timestamp: ~U[2025-06-29 01:23:52.851244Z], retry_count: 0, recovery_strategy: nil}
.    warning: module attribute @impl was not set for function start_link/1 callback (specified in Jido.Agent). This either means you forgot to add the "@impl true" annotation before the definition or that you are accidentally overriding this callback
    │
 10 │     use FoundationAgent,
    │     ~~~~~~~~~~~~~~~~~~~~
    │
    └─ test/jido_system/agents/foundation_agent_test.exs:10: JidoSystem.Agents.FoundationAgentTest.TestAgent (module)

.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] The function passed as a handler with ID "test-retry-events" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
[info] Registered Jido agent #PID<0.1959.0> with Foundation
[info] Retrying Jido action for agent #PID<0.1959.0>, attempt 1/2, delay: 100ms
...[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] Registered Jido agent #PID<0.1967.0> with Foundation
[info] Retrying Jido action for agent #PID<0.1967.0>, attempt 1/3, delay: 100ms
[info] Retrying Jido action for agent #PID<0.1967.0>, attempt 2/3, delay: 200ms
...[info] The function passed as a handler with ID "test-error" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
........[info] Running compensation logic for error: :needs_cleanup
...........

  2) test circuit breaker states closed -> open transition on failures (Foundation.Infrastructure.CircuitBreakerTest)
     test/foundation/infrastructure/circuit_breaker_test.exs:21
     Assertion with == failed
     code:  assert result == {:error, :circuit_open}
     left:  {:ok, {:ok, "should_not_execute"}}
     right: {:error, :circuit_open}
     stacktrace:
       test/foundation/infrastructure/circuit_breaker_test.exs:43: (test)

.

  3) test circuit breaker states open -> half_open -> closed recovery (Foundation.Infrastructure.CircuitBreakerTest)
     test/foundation/infrastructure/circuit_breaker_test.exs:46
     Assertion with == failed
     code:  assert status == :open
     left:  :closed
     right: :open
     stacktrace:
       test/foundation/infrastructure/circuit_breaker_test.exs:57: (test)



  4) test circuit breaker states circuit opens again on failure after reset (Foundation.Infrastructure.CircuitBreakerTest)
     test/foundation/infrastructure/circuit_breaker_test.exs:74
     Assertion with == failed
     code:  assert status == :open
     left:  :closed
     right: :open
     stacktrace:
       test/foundation/infrastructure/circuit_breaker_test.exs:93: (test)

[info] The function passed as a handler with ID "test_handler_#Reference<0.741964219.2526019598.3682>" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4


[info] The function passed as a handler with ID "test_handler_failure_#Reference<0.741964219.2526019598.3682>" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
  5) test fallback behavior returns error when circuit is open (Foundation.Infrastructure.CircuitBreakerTest)
     test/foundation/infrastructure/circuit_breaker_test.exs:173
     Assertion with == failed
     code:  assert result == {:error, :circuit_open}
     left:  {:ok, {:ok, :primary}}
     right: {:error, :circuit_open}
     stacktrace:
       test/foundation/infrastructure/circuit_breaker_test.exs:186: (test)

..[info] Foundation.ResourceManager started with limits: %{max_memory_mb: 2048, max_ets_entries: 10000, cleanup_interval: 100, alert_threshold: 0.8, max_registry_size: 1000}
.[info] Foundation.ResourceManager started with limits: %{max_memory_mb: 1024, max_ets_entries: 1000000, cleanup_interval: 60000, alert_threshold: 0.9, max_registry_size: 100000}
[info] Foundation.ResourceManager started with limits: %{max_memory_mb: 2048, max_ets_entries: 10000, cleanup_interval: 100, alert_threshold: 0.8, max_registry_size: 1000}
.[info] Foundation Protocol Platform stopping
[info] Foundation.ResourceManager started with limits: %{max_memory_mb: 2048, max_ets_entries: 10000, cleanup_interval: 100, alert_threshold: 0.8, max_registry_size: 1000}
[info] The function passed as a handler with ID "test-resource-events" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
[notice] Application foundation exited: shutdown
.[info] Foundation.ResourceManager started with limits: %{max_memory_mb: 2048, max_ets_entries: 10000, cleanup_interval: 100, alert_threshold: 0.8, max_registry_size: 1000}
.[info] Foundation.ResourceManager started with limits: %{max_memory_mb: 2048, max_ets_entries: 10000, cleanup_interval: 100, alert_threshold: 0.8, max_registry_size: 1000}
.[info] Foundation.ResourceManager started with limits: %{max_memory_mb: 2048, max_ets_entries: 10000, cleanup_interval: 100, alert_threshold: 0.8, max_registry_size: 1000}
.[info] Foundation.ResourceManager started with limits: %{max_memory_mb: 2048, max_ets_entries: 10000, cleanup_interval: 100, alert_threshold: 0.8, max_registry_size: 1000}
.[info] Foundation.ResourceManager started with limits: %{max_memory_mb: 2048, max_ets_entries: 10000, cleanup_interval: 100, alert_threshold: 0.8, max_registry_size: 1000}
.[info] Foundation.ResourceManager started with limits: %{max_memory_mb: 2048, max_ets_entries: 10000, cleanup_interval: 100, alert_threshold: 0.8, max_registry_size: 1000}
.[info] Foundation.ResourceManager started with limits: %{max_memory_mb: 2048, max_ets_entries: 10000, cleanup_interval: 100, alert_threshold: 0.8, max_registry_size: 1000}
.[info] Starting task processing
[info] Task completed successfully
.[info] Starting task processing
.[info] Task completed successfully
[info] The function passed as a handler with ID "test_task_telemetry" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
[info] Starting task processing
.[info] Task completed successfully
[info] The function passed as a handler with ID "test_failure_telemetry" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
[info] Starting task processing
[warning] Task attempt failed, retrying
[warning] Task attempt failed, retrying
.[error] Task failed after all retries
[error] Task processing failed
[info] Starting task processing
.[info] Sending notification
[info] Sending notification
[info] Task completed successfully
[info] Starting task processing
[info] Task completed successfully
.[info] Starting task processing
[info] Task completed successfully
.[info] Starting task processing
[info] Task completed successfully
.[info] Starting task processing
.[warning] Task validation failed
[info] Starting task processing
[warning] Task validation failed
.[info] Starting task processing
.[warning] Task validation failed
[info] Starting task processing
.[info] Task completed successfully
[info] Starting task processing
.[info] Task completed successfully
[info] Starting task processing
[info] Task completed successfully
.[info] Starting task processing
[info] Task completed successfully
.[info] Starting task processing
.[warning] Task validation failed
.[info] Starting task processing
[info] Task completed successfully
.[info] Starting task processing
[info] Task completed successfully
.[info] Starting task processing
[warning] Task validation failed
[info] Starting task processing
[warning] Task attempt failed, retrying
.[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
.[info] Starting task processing
[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] FoundationAgent mount called for agent task_agent_queue
[info] Attempting to register agent task_agent_queue with Bridge
[info] Registered Jido agent #PID<0.2265.0> with Foundation
[info] Agent task_agent_queue registered with Foundation
[info] TaskAgent task_agent_queue mounted with capabilities: [:task_processing, :validation, :queue_management]
[info] SIGNAL: jido.agent.event.started from agent:task_agent_queue with data=%{agent_id: "task_agent_queue"}
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] FoundationAgent mount called for agent task_agent_init
[info] Attempting to register agent task_agent_init with Bridge
[info] Registered Jido agent #PID<0.2276.0> with Foundation
[info] Agent task_agent_init registered with Foundation
[info] TaskAgent task_agent_init mounted with capabilities: [:task_processing, :validation, :queue_management]
[info] SIGNAL: jido.agent.event.started from agent:task_agent_init with data=%{agent_id: "task_agent_init"}
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] FoundationAgent mount called for agent task_agent_coordination
[info] Attempting to register agent task_agent_coordination with Bridge
[info] Registered Jido agent #PID<0.2281.0> with Foundation
[info] Agent task_agent_coordination registered with Foundation
[info] TaskAgent task_agent_coordination mounted with capabilities: [:task_processing, :validation, :queue_management]
[info] SIGNAL: jido.agent.event.started from agent:task_agent_coordination with data=%{agent_id: "task_agent_coordination"}
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] FoundationAgent mount called for agent task_agent_metrics
[info] Attempting to register agent task_agent_metrics with Bridge
[info] Registered Jido agent #PID<0.2286.0> with Foundation
[info] Agent task_agent_metrics registered with Foundation
[info] TaskAgent task_agent_metrics mounted with capabilities: [:task_processing, :validation, :queue_management]
[info] SIGNAL: jido.agent.event.started from agent:task_agent_metrics with data=%{agent_id: "task_agent_metrics"}
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] FoundationAgent mount called for agent task_agent_processing
[info] Attempting to register agent task_agent_processing with Bridge
[info] Registered Jido agent #PID<0.2293.0> with Foundation
[info] Agent task_agent_processing registered with Foundation
[info] TaskAgent task_agent_processing mounted with capabilities: [:task_processing, :validation, :queue_management]
[info] SIGNAL: jido.agent.event.started from agent:task_agent_processing with data=%{agent_id: "task_agent_processing"}
[warning] Agent task_agent_processing encountered error: #Jido.Error<
  type: :validation_error
  message: "Invalid parameters for Action (Elixir.JidoSystem.Actions.ProcessTask): required :task_id option not found, received options: [:input_data]"
  stacktrace:
    (jido 1.2.0) lib/jido/error.ex:139: Jido.Error.new/4
    (foundation 0.1.5) deps/jido/lib/jido/action.ex:374: JidoSystem.Actions.ProcessTask.do_validate_params/1
    (foundation 0.1.5) deps/jido/lib/jido/action.ex:319: JidoSystem.Actions.ProcessTask.validate_params/1
    (jido_action 1.0.0) lib/jido/exec.ex:407: Jido.Exec.validate_params/2
    (jido_action 1.0.0) lib/jido/exec.ex:133: Jido.Exec.run/4
>
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
.[info] FoundationAgent mount called for agent task_agent_state
.[info] Attempting to register agent task_agent_state with Bridge
[info] Registered Jido agent #PID<0.2298.0> with Foundation
[info] Agent task_agent_state registered with Foundation
[info] TaskAgent task_agent_state mounted with capabilities: [:task_processing, :validation, :queue_management]
[info] SIGNAL: jido.agent.event.started from agent:task_agent_state with data=%{agent_id: "task_agent_state"}
[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] FoundationAgent mount called for agent task_agent_periodic
[info] Attempting to register agent task_agent_periodic with Bridge
[info] Registered Jido agent #PID<0.2303.0> with Foundation
[info] Agent task_agent_periodic registered with Foundation
[info] TaskAgent task_agent_periodic mounted with capabilities: [:task_processing, :validation, :queue_management]
[info] SIGNAL: jido.agent.event.started from agent:task_agent_periodic with data=%{agent_id: "task_agent_periodic"}
[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] FoundationAgent mount called for agent task_agent_processing
[info] Attempting to register agent task_agent_processing with Bridge
[info] Registered Jido agent #PID<0.2308.0> with Foundation
[info] Agent task_agent_processing registered with Foundation
[info] TaskAgent task_agent_processing mounted with capabilities: [:task_processing, :validation, :queue_management]
[info] SIGNAL: jido.agent.event.started from agent:task_agent_processing with data=%{agent_id: "task_agent_processing"}
[warning] Agent task_agent_processing encountered error: {:agent_paused, "Task processing is currently paused"}
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] FoundationAgent mount called for agent task_agent_metrics
[info] Attempting to register agent task_agent_metrics with Bridge
[info] Registered Jido agent #PID<0.2315.0> with Foundation
[info] Agent task_agent_metrics registered with Foundation
[info] TaskAgent task_agent_metrics mounted with capabilities: [:task_processing, :validation, :queue_management]
[info] SIGNAL: jido.agent.event.started from agent:task_agent_metrics with data=%{agent_id: "task_agent_metrics"}
[info] Starting task processing
[info] Task completed successfully
[info] Starting task processing
[info] Task completed successfully
[info] Starting task processing
[info] Task completed successfully
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] FoundationAgent mount called for agent task_agent_telemetry
[info] Attempting to register agent task_agent_telemetry with Bridge
[info] Registered Jido agent #PID<0.2326.0> with Foundation
[info] Agent task_agent_telemetry registered with Foundation
[info] TaskAgent task_agent_telemetry mounted with capabilities: [:task_processing, :validation, :queue_management]
[info] SIGNAL: jido.agent.event.started from agent:task_agent_telemetry with data=%{agent_id: "task_agent_telemetry"}
[info] The function passed as a handler with ID "test_task_telemetry" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
[info] Starting task processing
[info] Task completed successfully
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] FoundationAgent mount called for agent task_agent_processing
[info] Attempting to register agent task_agent_processing with Bridge
[info] Registered Jido agent #PID<0.2333.0> with Foundation
[info] Agent task_agent_processing registered with Foundation
[info] TaskAgent task_agent_processing mounted with capabilities: [:task_processing, :validation, :queue_management]
[info] SIGNAL: jido.agent.event.started from agent:task_agent_processing with data=%{agent_id: "task_agent_processing"}
[info] The function passed as a handler with ID "test_task_completion" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
[info] Starting task processing
[info] Task completed successfully
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] FoundationAgent mount called for agent task_agent_queue
[info] Attempting to register agent task_agent_queue with Bridge
[info] Registered Jido agent #PID<0.2340.0> with Foundation
[info] Agent task_agent_queue registered with Foundation
[info] TaskAgent task_agent_queue mounted with capabilities: [:task_processing, :validation, :queue_management]
[info] SIGNAL: jido.agent.event.started from agent:task_agent_queue with data=%{agent_id: "task_agent_queue"}
[error] Action JidoSystem.Actions.QueueTask failed: %{error: :queue_full, max_size: 1000, current_size: 1000}
[error] Action JidoSystem.Actions.QueueTask failed: %{error: :queue_full, max_size: 1000, current_size: 1000}
[warning] Agent task_agent_queue encountered error: #Jido.Error<
  type: :execution_error
  message: %{error: :queue_full, max_size: 1000, current_size: 1000}
  stacktrace:
    (jido 1.2.0) lib/jido/error.ex:139: Jido.Error.new/4
    (jido_action 1.0.0) lib/jido/exec.ex:1005: Jido.Exec.execute_action/4
    (jido_action 1.0.0) lib/jido/exec.ex:843: anonymous fn/7 in Jido.Exec.execute_action_with_timeout/5
>
[error] Action JidoSystem.Actions.QueueTask failed: %{error: :queue_full, max_size: 1000, current_size: 1000}
[error] Action JidoSystem.Actions.QueueTask failed: %{error: :queue_full, max_size: 1000, current_size: 1000}
[warning] Agent task_agent_queue encountered error: #Jido.Error<
  type: :execution_error
  message: %{error: :queue_full, max_size: 1000, current_size: 1000}
  stacktrace:
    (jido 1.2.0) lib/jido/error.ex:139: Jido.Error.new/4
    (jido_action 1.0.0) lib/jido/exec.ex:1005: Jido.Exec.execute_action/4
    (jido_action 1.0.0) lib/jido/exec.ex:843: anonymous fn/7 in Jido.Exec.execute_action_with_timeout/5
>
[error] Action JidoSystem.Actions.QueueTask failed: %{error: :queue_full, max_size: 1000, current_size: 1000}
[error] Action JidoSystem.Actions.QueueTask failed: %{error: :queue_full, max_size: 1000, current_size: 1000}
[warning] Agent task_agent_queue encountered error: #Jido.Error<
  type: :execution_error
  message: %{error: :queue_full, max_size: 1000, current_size: 1000}
  stacktrace:
    (jido 1.2.0) lib/jido/error.ex:139: Jido.Error.new/4
    (jido_action 1.0.0) lib/jido/exec.ex:1005: Jido.Exec.execute_action/4
    (jido_action 1.0.0) lib/jido/exec.ex:843: anonymous fn/7 in Jido.Exec.execute_action_with_timeout/5
>
[error] Action JidoSystem.Actions.QueueTask failed: %{error: :queue_full, max_size: 1000, current_size: 1000}
[error] Action JidoSystem.Actions.QueueTask failed: %{error: :queue_full, max_size: 1000, current_size: 1000}
[warning] Agent task_agent_queue encountered error: #Jido.Error<
  type: :execution_error
  message: %{error: :queue_full, max_size: 1000, current_size: 1000}
  stacktrace:
    (jido 1.2.0) lib/jido/error.ex:139: Jido.Error.new/4
    (jido_action 1.0.0) lib/jido/exec.ex:1005: Jido.Exec.execute_action/4
    (jido_action 1.0.0) lib/jido/exec.ex:843: anonymous fn/7 in Jido.Exec.execute_action_with_timeout/5
>
[error] Action JidoSystem.Actions.QueueTask failed: %{error: :queue_full, max_size: 1000, current_size: 1000}
[error] Action JidoSystem.Actions.QueueTask failed: %{error: :queue_full, max_size: 1000, current_size: 1000}
[warning] Agent task_agent_queue encountered error: #Jido.Error<
  type: :execution_error
  message: %{error: :queue_full, max_size: 1000, current_size: 1000}
  stacktrace:
    (jido 1.2.0) lib/jido/error.ex:139: Jido.Error.new/4
    (jido_action 1.0.0) lib/jido/exec.ex:1005: Jido.Exec.execute_action/4
    (jido_action 1.0.0) lib/jido/exec.ex:843: anonymous fn/7 in Jido.Exec.execute_action_with_timeout/5
>
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] FoundationAgent mount called for agent task_agent_errors
[info] Attempting to register agent task_agent_errors with Bridge
[info] Registered Jido agent #PID<0.4365.0> with Foundation
[info] Agent task_agent_errors registered with Foundation
[info] TaskAgent task_agent_errors mounted with capabilities: [:task_processing, :validation, :queue_management]
[info] SIGNAL: jido.agent.event.started from agent:task_agent_errors with data=%{agent_id: "task_agent_errors"}
[info] Starting task processing
[warning] Task attempt failed, retrying
[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
[error] Action JidoSystem.Actions.ProcessTask failed: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 72, task_id: "error_task", failed_at: ~U[2025-06-29 01:23:58.234086Z]}
[info] Starting task processing
[warning] Task attempt failed, retrying
[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
[error] Action JidoSystem.Actions.ProcessTask failed: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 138, task_id: "error_task", failed_at: ~U[2025-06-29 01:23:58.487027Z]}
[warning] Agent task_agent_errors encountered error: #Jido.Error<
  type: :execution_error
  message: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 138, task_id: "error_task", failed_at: ~U[2025-06-29 01:23:58.487027Z]}
  stacktrace:
    (jido 1.2.0) lib/jido/error.ex:139: Jido.Error.new/4
    (jido_action 1.0.0) lib/jido/exec.ex:1005: Jido.Exec.execute_action/4
    (jido_action 1.0.0) lib/jido/exec.ex:843: anonymous fn/7 in Jido.Exec.execute_action_with_timeout/5
>
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] FoundationAgent mount called for agent task_agent_errors
[info] Attempting to register agent task_agent_errors with Bridge
[info] Registered Jido agent #PID<0.4374.0> with Foundation
[info] Agent task_agent_errors registered with Foundation
[info] TaskAgent task_agent_errors mounted with capabilities: [:task_processing, :validation, :queue_management]
[info] SIGNAL: jido.agent.event.started from agent:task_agent_errors with data=%{agent_id: "task_agent_errors"}
[info] Starting task processing
[warning] Task attempt failed, retrying
[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
[error] Action JidoSystem.Actions.ProcessTask failed: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 100, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:23:58.490157Z]}
[info] Starting task processing
[warning] Task attempt failed, retrying
[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
[error] Action JidoSystem.Actions.ProcessTask failed: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 299, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:23:58.742469Z]}
[warning] Agent task_agent_errors encountered error: #Jido.Error<
  type: :execution_error
  message: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 299, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:23:58.742469Z]}
  stacktrace:
    (jido 1.2.0) lib/jido/error.ex:139: Jido.Error.new/4
    (jido_action 1.0.0) lib/jido/exec.ex:1005: Jido.Exec.execute_action/4
    (jido_action 1.0.0) lib/jido/exec.ex:843: anonymous fn/7 in Jido.Exec.execute_action_with_timeout/5
>
[info] Starting task processing
[warning] Task attempt failed, retrying
[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
[error] Action JidoSystem.Actions.ProcessTask failed: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 89, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:23:58.746413Z]}
[info] Starting task processing
[warning] Task attempt failed, retrying
[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
[error] Action JidoSystem.Actions.ProcessTask failed: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 516, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:23:58.999146Z]}
[warning] Agent task_agent_errors encountered error: #Jido.Error<
  type: :execution_error
  message: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 516, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:23:58.999146Z]}
  stacktrace:
    (jido 1.2.0) lib/jido/error.ex:139: Jido.Error.new/4
    (jido_action 1.0.0) lib/jido/exec.ex:1005: Jido.Exec.execute_action/4
    (jido_action 1.0.0) lib/jido/exec.ex:843: anonymous fn/7 in Jido.Exec.execute_action_with_timeout/5
>
[info] Starting task processing
[warning] Task attempt failed, retrying
[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
[error] Action JidoSystem.Actions.ProcessTask failed: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 69, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:23:59.006494Z]}
[info] Starting task processing
[warning] Task attempt failed, retrying
[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
[error] Action JidoSystem.Actions.ProcessTask failed: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 78, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:23:59.258017Z]}
[warning] Agent task_agent_errors encountered error: #Jido.Error<
  type: :execution_error
  message: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 78, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:23:59.258017Z]}
  stacktrace:
    (jido 1.2.0) lib/jido/error.ex:139: Jido.Error.new/4
    (jido_action 1.0.0) lib/jido/exec.ex:1005: Jido.Exec.execute_action/4
    (jido_action 1.0.0) lib/jido/exec.ex:843: anonymous fn/7 in Jido.Exec.execute_action_with_timeout/5
>
[info] Starting task processing
[warning] Task attempt failed, retrying
[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
[error] Action JidoSystem.Actions.ProcessTask failed: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 40, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:23:59.259432Z]}
[info] Starting task processing
[warning] Task attempt failed, retrying
[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
[error] Action JidoSystem.Actions.ProcessTask failed: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 347, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:23:59.511746Z]}
[warning] Agent task_agent_errors encountered error: #Jido.Error<
  type: :execution_error
  message: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 347, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:23:59.511746Z]}
  stacktrace:
    (jido 1.2.0) lib/jido/error.ex:139: Jido.Error.new/4
    (jido_action 1.0.0) lib/jido/exec.ex:1005: Jido.Exec.execute_action/4
    (jido_action 1.0.0) lib/jido/exec.ex:843: anonymous fn/7 in Jido.Exec.execute_action_with_timeout/5
>
[info] Starting task processing
[warning] Task attempt failed, retrying
[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
[error] Action JidoSystem.Actions.ProcessTask failed: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 46, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:23:59.517610Z]}
[info] Starting task processing
[warning] Task attempt failed, retrying
[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
[error] Action JidoSystem.Actions.ProcessTask failed: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 846, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:23:59.771333Z]}
[warning] Agent task_agent_errors encountered error: #Jido.Error<
  type: :execution_error
  message: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 846, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:23:59.771333Z]}
  stacktrace:
    (jido 1.2.0) lib/jido/error.ex:139: Jido.Error.new/4
    (jido_action 1.0.0) lib/jido/exec.ex:1005: Jido.Exec.execute_action/4
    (jido_action 1.0.0) lib/jido/exec.ex:843: anonymous fn/7 in Jido.Exec.execute_action_with_timeout/5
>
[info] Starting task processing
[warning] Task attempt failed, retrying
[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
[error] Action JidoSystem.Actions.ProcessTask failed: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 58, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:23:59.775653Z]}
[info] Starting task processing
[warning] Task attempt failed, retrying
[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
[error] Action JidoSystem.Actions.ProcessTask failed: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 389, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:24:00.030073Z]}
[warning] Agent task_agent_errors encountered error: #Jido.Error<
  type: :execution_error
  message: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 389, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:24:00.030073Z]}
  stacktrace:
    (jido 1.2.0) lib/jido/error.ex:139: Jido.Error.new/4
    (jido_action 1.0.0) lib/jido/exec.ex:1005: Jido.Exec.execute_action/4
    (jido_action 1.0.0) lib/jido/exec.ex:843: anonymous fn/7 in Jido.Exec.execute_action_with_timeout/5
>
[info] Starting task processing
[warning] Task attempt failed, retrying
[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
[error] Action JidoSystem.Actions.ProcessTask failed: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 48, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:24:00.035730Z]}
[info] Starting task processing
[warning] Task attempt failed, retrying
[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
[error] Action JidoSystem.Actions.ProcessTask failed: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 490, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:24:00.288004Z]}
[warning] Agent task_agent_errors encountered error: #Jido.Error<
  type: :execution_error
  message: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 490, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:24:00.288004Z]}
  stacktrace:
    (jido 1.2.0) lib/jido/error.ex:139: Jido.Error.new/4
    (jido_action 1.0.0) lib/jido/exec.ex:1005: Jido.Exec.execute_action/4
    (jido_action 1.0.0) lib/jido/exec.ex:843: anonymous fn/7 in Jido.Exec.execute_action_with_timeout/5
>
[info] Starting task processing
[warning] Task attempt failed, retrying
[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
[error] Action JidoSystem.Actions.ProcessTask failed: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 64, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:24:00.294762Z]}
[info] Starting task processing
[warning] Task attempt failed, retrying
[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
[error] Action JidoSystem.Actions.ProcessTask failed: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 126, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:24:00.546101Z]}
[warning] Agent task_agent_errors encountered error: #Jido.Error<
  type: :execution_error
  message: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 126, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:24:00.546101Z]}
  stacktrace:
    (jido 1.2.0) lib/jido/error.ex:139: Jido.Error.new/4
    (jido_action 1.0.0) lib/jido/exec.ex:1005: Jido.Exec.execute_action/4
    (jido_action 1.0.0) lib/jido/exec.ex:843: anonymous fn/7 in Jido.Exec.execute_action_with_timeout/5
>
[info] Starting task processing
[warning] Task attempt failed, retrying
[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
[error] Action JidoSystem.Actions.ProcessTask failed: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 82, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:24:00.547783Z]}
[info] Starting task processing
[warning] Task attempt failed, retrying
[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
[error] Action JidoSystem.Actions.ProcessTask failed: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 299, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:24:00.800490Z]}
[warning] Agent task_agent_errors encountered error: #Jido.Error<
  type: :execution_error
  message: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 299, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:24:00.800490Z]}
  stacktrace:
    (jido 1.2.0) lib/jido/error.ex:139: Jido.Error.new/4
    (jido_action 1.0.0) lib/jido/exec.ex:1005: Jido.Exec.execute_action/4
    (jido_action 1.0.0) lib/jido/exec.ex:843: anonymous fn/7 in Jido.Exec.execute_action_with_timeout/5
>
[info] Starting task processing
[warning] Task attempt failed, retrying
[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
[error] Action JidoSystem.Actions.ProcessTask failed: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 78, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:24:00.805404Z]}
[info] Starting task processing
[warning] Task attempt failed, retrying
[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
[error] Action JidoSystem.Actions.ProcessTask failed: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 769, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:24:01.057533Z]}
[warning] Agent task_agent_errors encountered error: #Jido.Error<
  type: :execution_error
  message: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 769, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:24:01.057533Z]}
  stacktrace:
    (jido 1.2.0) lib/jido/error.ex:139: Jido.Error.new/4
    (jido_action 1.0.0) lib/jido/exec.ex:1005: Jido.Exec.execute_action/4
    (jido_action 1.0.0) lib/jido/exec.ex:843: anonymous fn/7 in Jido.Exec.execute_action_with_timeout/5
>
[warning] TaskAgent task_agent_errors has too many errors, pausing
[warning] Agent task_agent_errors encountered error: {:agent_paused, "Task processing is currently paused"}
[info] Starting task processing
[warning] Task attempt failed, retrying
[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
[error] Action JidoSystem.Actions.ProcessTask failed: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 61, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:24:01.062908Z]}
[info] Starting task processing
[warning] Task attempt failed, retrying
[warning] Task attempt failed, retrying
[error] Task failed after all retries
[error] Task processing failed
[error] Action JidoSystem.Actions.ProcessTask failed: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 98, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:24:01.314076Z]}
[warning] Agent task_agent_errors encountered error: #Jido.Error<
  type: :execution_error
  message: %{error: {:retries_exhausted, {:unsupported_task_type, :invalid_type}}, status: :failed, duration: 98, task_id: "error_task_1", failed_at: ~U[2025-06-29 01:24:01.314076Z]}
  stacktrace:
    (jido 1.2.0) lib/jido/error.ex:139: Jido.Error.new/4
    (jido_action 1.0.0) lib/jido/exec.ex:1005: Jido.Exec.execute_action/4
    (jido_action 1.0.0) lib/jido/exec.ex:843: anonymous fn/7 in Jido.Exec.execute_action_with_timeout/5
>
[warning] TaskAgent task_agent_errors has too many errors, pausing
.[info] Starting SystemHealthSensor
[error] Failed to collect system metrics
[info] Starting SystemHealthSensor
[info] Starting SystemHealthSensor


  6) test health analysis analyzes normal system health correctly (JidoSystem.Sensors.SystemHealthSensorTest)
     test/jido_system/sensors/system_health_sensor_test.exs:166
     match (match?) failed
     code:  assert match?({:ok, %Signal{}, _state}, result)
     left:  {:ok, %Jido.Signal{}, _state}
     right: {
              :ok,
              {:ok, %Jido.Signal{jido_dispatch: nil, data: %{error: "%FunctionClauseError{module: JidoSystem.Sensors.SystemHealthSensor, function: :\"-get_average_cpu_utilization/1-fun-0-\", arity: 1, kind: nil, args: nil, clauses: nil}", timestamp: ~U[2025-06-29 01:24:02.328765Z], sensor_id: "analysis_test_sensor"}, dataschema: nil, datacontenttype: "application/json", time: "2025-06-29T01:24:02.328813Z", subject: nil, type: "system.health.error", source: "/sensors/system_health", id: "0197b948-c098-71ae-8670-316e60675c86", specversion: "1.0.2"}},
              %{
                id: "analysis_test_sensor",
                started_at: ~U[2025-06-29 01:24:01.315493Z],
                target: {:pid, [target: #PID<0.4422.0>]},
                history_size: 20,
                collection_interval: 1000,
                thresholds: %{process_count: 10000, memory_usage: 85, cpu_usage: 80, message_queue_size: 1000},
                enable_anomaly_detection: true,
                collection_count: 0,
                metrics_history: [],
                last_metrics: %{},
                baseline_metrics: %{},
                last_alerts: %{},
                alert_cooldown: 300000
              }
            }
     stacktrace:
       test/jido_system/sensors/system_health_sensor_test.exs:168: (test)

.[error] Failed to collect system metrics


[info] Starting SystemHealthSensor
  7) test signal generation includes sensor metadata in signals (JidoSystem.Sensors.SystemHealthSensorTest)
     test/jido_system/sensors/system_health_sensor_test.exs:313
     ** (KeyError) key :data not found in: {:ok,
      %Jido.Signal{
        jido_dispatch: nil,
        data: %{
          error: "%FunctionClauseError{module: JidoSystem.Sensors.SystemHealthSensor, function: :\"-get_average_cpu_utilization/1-fun-0-\", arity: 1, kind: nil, args: nil, clauses: nil}",
          timestamp: ~U[2025-06-29 01:24:03.342769Z],
          sensor_id: "signal_test_sensor"
        },
        dataschema: nil,
        datacontenttype: "application/json",
        time: "2025-06-29T01:24:03.342818Z",
        subject: nil,
        type: "system.health.error",
        source: "/sensors/system_health",
        id: "0197b948-c48e-75a5-8c20-6490ee59857c",
        specversion: "1.0.2"
      }}

     If you are using the dot syntax, such as map.field, make sure the left-hand side of the dot is a map
     code: assert signal.data.sensor_id == state.id
     stacktrace:
       test/jido_system/sensors/system_health_sensor_test.exs:317: (test)

[error] Failed to collect system metrics
[info] Starting SystemHealthSensor


  8) test signal generation generates different signal types based on health status (JidoSystem.Sensors.SystemHealthSensorTest)
     test/jido_system/sensors/system_health_sensor_test.exs:322
     ** (KeyError) key :type not found in: {:ok,
      %Jido.Signal{
        jido_dispatch: nil,
        data: %{
          error: "%FunctionClauseError{module: JidoSystem.Sensors.SystemHealthSensor, function: :\"-get_average_cpu_utilization/1-fun-0-\", arity: 1, kind: nil, args: nil, clauses: nil}",
          timestamp: ~U[2025-06-29 01:24:04.362580Z],
          sensor_id: "signal_test_sensor"
        },
        dataschema: nil,
        datacontenttype: "application/json",
        time: "2025-06-29T01:24:04.362707Z",
        subject: nil,
        type: "system.health.error",
        source: "/sensors/system_health",
        id: "0197b948-c88a-7234-b0f9-ee36060abdea",
        specversion: "1.0.2"
      }}

     If you are using the dot syntax, such as map.field, make sure the left-hand side of the dot is a map
     code: assert signal.type in valid_types
     stacktrace:
       test/jido_system/sensors/system_health_sensor_test.exs:333: (test)

[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[info] Starting SystemHealthSensor


[info] Starting SystemHealthSensor
  9) test health analysis tracks trends with sufficient history (JidoSystem.Sensors.SystemHealthSensorTest)
     test/jido_system/sensors/system_health_sensor_test.exs:216
     ** (KeyError) key :data not found in: {:ok,
      %Jido.Signal{
        jido_dispatch: nil,
        data: %{
          error: "%FunctionClauseError{module: JidoSystem.Sensors.SystemHealthSensor, function: :\"-get_average_cpu_utilization/1-fun-0-\", arity: 1, kind: nil, args: nil, clauses: nil}",
          timestamp: ~U[2025-06-29 01:24:17.181184Z],
          sensor_id: "analysis_test_sensor"
        },
        dataschema: nil,
        datacontenttype: "application/json",
        time: "2025-06-29T01:24:17.181238Z",
        subject: nil,
        type: "system.health.error",
        source: "/sensors/system_health",
        id: "0197b948-f49d-7325-9456-9e71b042a167",
        specversion: "1.0.2"
      }}

     If you are using the dot syntax, such as map.field, make sure the left-hand side of the dot is a map
     code: if Map.has_key?(signal.data, :trends) do
     stacktrace:
       test/jido_system/sensors/system_health_sensor_test.exs:227: (test)

.[info] Starting SystemHealthSensor
.[info] Shutting down SystemHealthSensor


[info] Starting SystemHealthSensor
 10) test process integration sensor process handles periodic collection (JidoSystem.Sensors.SystemHealthSensorTest)
     test/jido_system/sensors/system_health_sensor_test.exs:338
     Assertion failed, no matching message after 1000ms
     The process mailbox is empty.
     code: assert_receive {:signal, %Jido.Signal{} = _signal}
     stacktrace:
       test/jido_system/sensors/system_health_sensor_test.exs:348: (test)

[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics


 11) test metrics collection maintains metrics history within limit (JidoSystem.Sensors.SystemHealthSensorTest)
     test/jido_system/sensors/system_health_sensor_test.exs:122
     Assertion with == failed
     code:  assert length(state.metrics_history) == state.history_size
     left:  0
     right: 10
     stacktrace:
       test/jido_system/sensors/system_health_sensor_test.exs:130: (test)

[info] Starting SystemHealthSensor
.[info] Starting SystemHealthSensor
.[info] Shutting down SystemHealthSensor
[info] Starting SystemHealthSensor
.[info] Shutting down SystemHealthSensor
[info] Starting SystemHealthSensor
[error] Failed to collect system metrics


[info] Starting SystemHealthSensor
 12) test metrics collection handles collection errors gracefully (JidoSystem.Sensors.SystemHealthSensorTest)
     test/jido_system/sensors/system_health_sensor_test.exs:134
     match (=) failed
     code:  assert %Signal{} = signal
     left:  %Jido.Signal{}
     right: {:ok, %Jido.Signal{jido_dispatch: nil, data: %{error: "%FunctionClauseError{module: JidoSystem.Sensors.SystemHealthSensor, function: :\"-get_average_cpu_utilization/1-fun-0-\", arity: 1, kind: nil, args: nil, clauses: nil}", timestamp: ~U[2025-06-29 01:24:34.399952Z], sensor_id: "metrics_test_sensor"}, dataschema: nil, datacontenttype: "application/json", time: "2025-06-29T01:24:34.399995Z", subject: nil, type: "system.health.error", source: "/sensors/system_health", id: "0197b949-37e0-74ad-9b1e-126bbb4f0dee", specversion: "1.0.2"}}
     stacktrace:
       test/jido_system/sensors/system_health_sensor_test.exs:142: (test)

[error] Failed to collect system metrics
[info] Starting SystemHealthSensor


 13) test health analysis generates appropriate recommendations (JidoSystem.Sensors.SystemHealthSensorTest)
     test/jido_system/sensors/system_health_sensor_test.exs:203
     ** (KeyError) key :data not found in: {:ok,
      %Jido.Signal{
        jido_dispatch: nil,
        data: %{
          error: "%FunctionClauseError{module: JidoSystem.Sensors.SystemHealthSensor, function: :\"-get_average_cpu_utilization/1-fun-0-\", arity: 1, kind: nil, args: nil, clauses: nil}",
          timestamp: ~U[2025-06-29 01:24:35.417504Z],
          sensor_id: "analysis_test_sensor"
        },
        dataschema: nil,
        datacontenttype: "application/json",
        time: "2025-06-29T01:24:35.417626Z",
        subject: nil,
        type: "system.health.error",
        source: "/sensors/system_health",
        id: "0197b949-3bda-777d-a17c-fd9f7fe8d750",
        specversion: "1.0.2"
      }}

     If you are using the dot syntax, such as map.field, make sure the left-hand side of the dot is a map
     code: assert is_list(signal.data.recommendations)
     stacktrace:
       test/jido_system/sensors/system_health_sensor_test.exs:206: (test)

[error] Failed to collect system metrics
[info] Starting SystemHealthSensor


 14) test signal generation generates signals with correct structure (JidoSystem.Sensors.SystemHealthSensorTest)
     test/jido_system/sensors/system_health_sensor_test.exs:294
     match (=) failed
     code:  assert %Signal{type: type, data: data} = signal
     left:  %Jido.Signal{type: type, data: data}
     right: {:ok, %Jido.Signal{jido_dispatch: nil, data: %{error: "%FunctionClauseError{module: JidoSystem.Sensors.SystemHealthSensor, function: :\"-get_average_cpu_utilization/1-fun-0-\", arity: 1, kind: nil, args: nil, clauses: nil}", timestamp: ~U[2025-06-29 01:24:36.437310Z], sensor_id: "signal_test_sensor"}, dataschema: nil, datacontenttype: "application/json", time: "2025-06-29T01:24:36.437431Z", subject: nil, type: "system.health.error", source: "/sensors/system_health", id: "0197b949-3fd5-75cb-bf89-4f72bae6b632", specversion: "1.0.2"}}
     stacktrace:
       test/jido_system/sensors/system_health_sensor_test.exs:298: (test)

[error] Failed to collect system metrics
[info] Starting SystemHealthSensor


 15) test metrics collection collects comprehensive system metrics (JidoSystem.Sensors.SystemHealthSensorTest)
     test/jido_system/sensors/system_health_sensor_test.exs:98
     match (=) failed
     code:  assert %Signal{} = signal
     left:  %Jido.Signal{}
     right: {:ok, %Jido.Signal{jido_dispatch: nil, data: %{error: "%FunctionClauseError{module: JidoSystem.Sensors.SystemHealthSensor, function: :\"-get_average_cpu_utilization/1-fun-0-\", arity: 1, kind: nil, args: nil, clauses: nil}", timestamp: ~U[2025-06-29 01:24:37.449781Z], sensor_id: "metrics_test_sensor"}, dataschema: nil, datacontenttype: "application/json", time: "2025-06-29T01:24:37.449859Z", subject: nil, type: "system.health.error", source: "/sensors/system_health", id: "0197b949-43ca-7764-a028-48a5339b1739", specversion: "1.0.2"}}
     stacktrace:
       test/jido_system/sensors/system_health_sensor_test.exs:101: (test)

[error] Failed to collect system metrics
[info] Starting SystemHealthSensor


 16) test health analysis detects threshold violations (JidoSystem.Sensors.SystemHealthSensorTest)
     test/jido_system/sensors/system_health_sensor_test.exs:184
     ** (KeyError) key :data not found in: {:ok,
      %Jido.Signal{
        jido_dispatch: nil,
        data: %{
          error: "%FunctionClauseError{module: JidoSystem.Sensors.SystemHealthSensor, function: :\"-get_average_cpu_utilization/1-fun-0-\", arity: 1, kind: nil, args: nil, clauses: nil}",
          timestamp: ~U[2025-06-29 01:24:38.460058Z],
          sensor_id: "analysis_test_sensor"
        },
        dataschema: nil,
        datacontenttype: "application/json",
        time: "2025-06-29T01:24:38.460118Z",
        subject: nil,
        type: "system.health.error",
        source: "/sensors/system_health",
        id: "0197b949-47bc-7016-819d-f53f685cb0bd",
        specversion: "1.0.2"
      }}

     If you are using the dot syntax, such as map.field, make sure the left-hand side of the dot is a map
     code: assert signal.data.status in [:warning, :critical, :emergency]
     stacktrace:
       test/jido_system/sensors/system_health_sensor_test.exs:198: (test)

[error] Failed to collect system metrics
[info] Starting SystemHealthSensor


 17) test error handling produces error signals when collection fails (JidoSystem.Sensors.SystemHealthSensorTest)
     test/jido_system/sensors/system_health_sensor_test.exs:394
     match (=) failed
     code:  assert %Signal{} = signal
     left:  %Jido.Signal{}
     right: {:ok, %Jido.Signal{jido_dispatch: nil, data: %{error: "%FunctionClauseError{module: JidoSystem.Sensors.SystemHealthSensor, function: :\"-get_average_cpu_utilization/1-fun-0-\", arity: 1, kind: nil, args: nil, clauses: nil}", timestamp: ~U[2025-06-29 01:24:39.474397Z], sensor_id: "error_test_sensor"}, dataschema: nil, datacontenttype: "application/json", time: "2025-06-29T01:24:39.474444Z", subject: nil, type: "system.health.error", source: "/sensors/system_health", id: "0197b949-4bb2-76c1-bd9a-37397dad3256", specversion: "1.0.2"}}
     stacktrace:
       test/jido_system/sensors/system_health_sensor_test.exs:402: (test)

[error] Failed to collect system metrics


[info] Starting SystemHealthSensor
 18) test error handling handles metrics collection errors gracefully (JidoSystem.Sensors.SystemHealthSensorTest)
     test/jido_system/sensors/system_health_sensor_test.exs:384
     match (match?) failed
     code:  assert match?({:ok, %Signal{}, _state}, result)
     left:  {:ok, %Jido.Signal{}, _state}
     right: {
              :ok,
              {:ok, %Jido.Signal{jido_dispatch: nil, data: %{error: "%FunctionClauseError{module: JidoSystem.Sensors.SystemHealthSensor, function: :\"-get_average_cpu_utilization/1-fun-0-\", arity: 1, kind: nil, args: nil, clauses: nil}", timestamp: ~U[2025-06-29 01:24:40.489305Z], sensor_id: "error_test_sensor"}, dataschema: nil, datacontenttype: "application/json", time: "2025-06-29T01:24:40.489403Z", subject: nil, type: "system.health.error", source: "/sensors/system_health", id: "0197b949-4fa9-73eb-a26d-1ac68a3499db", specversion: "1.0.2"}},
              %{
                id: "error_test_sensor",
                started_at: ~U[2025-06-29 01:24:39.474580Z],
                target: {:pid, [target: #PID<0.4448.0>]},
                history_size: 100,
                collection_interval: 1000,
                thresholds: %{process_count: 10000, memory_usage: 85, cpu_usage: 80},
                enable_anomaly_detection: true,
                collection_count: 0,
                metrics_history: [],
                last_metrics: %{},
                baseline_metrics: %{},
                last_alerts: %{},
                alert_cooldown: 300000
              }
            }
     stacktrace:
       test/jido_system/sensors/system_health_sensor_test.exs:391: (test)

[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics
[error] Failed to collect system metrics


[info] Starting SystemHealthSensor
 19) test anomaly detection detects anomalies when enabled (JidoSystem.Sensors.SystemHealthSensorTest)
     test/jido_system/sensors/system_health_sensor_test.exs:254
     ** (KeyError) key :data not found in: {:ok,
      %Jido.Signal{
        jido_dispatch: nil,
        data: %{
          error: "%FunctionClauseError{module: JidoSystem.Sensors.SystemHealthSensor, function: :\"-get_average_cpu_utilization/1-fun-0-\", arity: 1, kind: nil, args: nil, clauses: nil}",
          timestamp: ~U[2025-06-29 01:24:58.217513Z],
          sensor_id: "anomaly_test_sensor"
        },
        dataschema: nil,
        datacontenttype: "application/json",
        time: "2025-06-29T01:24:58.217681Z",
        subject: nil,
        type: "system.health.error",
        source: "/sensors/system_health",
        id: "0197b949-9ae9-7edb-8dbd-0505999098fc",
        specversion: "1.0.2"
      }}

     If you are using the dot syntax, such as map.field, make sure the left-hand side of the dot is a map
     code: assert is_list(signal.data.anomalies)
     stacktrace:
       test/jido_system/sensors/system_health_sensor_test.exs:264: (test)

[error] Failed to collect system metrics


 20) test anomaly detection skips anomaly detection when disabled (JidoSystem.Sensors.SystemHealthSensorTest)
     test/jido_system/sensors/system_health_sensor_test.exs:268
     ** (KeyError) key :data not found in: {:ok,
      %Jido.Signal{
        jido_dispatch: nil,
        data: %{
          error: "%FunctionClauseError{module: JidoSystem.Sensors.SystemHealthSensor, function: :\"-get_average_cpu_utilization/1-fun-0-\", arity: 1, kind: nil, args: nil, clauses: nil}",
          timestamp: ~U[2025-06-29 01:24:59.238537Z],
          sensor_id: "anomaly_test_sensor"
        },
        dataschema: nil,
        datacontenttype: "application/json",
        time: "2025-06-29T01:24:59.238587Z",
        subject: nil,
        type: "system.health.error",
        source: "/sensors/system_health",
        id: "0197b949-9ee6-7f8d-b54c-5562318064ae",
        specversion: "1.0.2"
      }}

     If you are using the dot syntax, such as map.field, make sure the left-hand side of the dot is a map
     code: assert is_list(signal.data.anomalies)
     stacktrace:
       test/jido_system/sensors/system_health_sensor_test.exs:274: (test)

[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] The function passed as a handler with ID "jido-signal-router" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
[info] Registered Jido agent #PID<0.4460.0> with Foundation
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] The function passed as a handler with ID "jido-signal-router" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
[info] Registered Jido agent #PID<0.4468.0> with Foundation
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] The function passed as a handler with ID "jido-signal-router" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
[info] Registered Jido agent #PID<0.4475.0> with Foundation
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] The function passed as a handler with ID "jido-signal-router" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
[info] The function passed as a handler with ID "test-routing-events" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
[info] Registered Jido agent #PID<0.4482.0> with Foundation
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] The function passed as a handler with ID "jido-signal-router" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
[info] Registered Jido agent #PID<0.4489.0> with Foundation
.[info] Starting load balancing coordination for 2 inference agents
.[info] Starting consensus coordination with 3 inference agents
..[info] Starting resource allocation coordination with 2 agents using greedy strategy
.[info] Starting capability transition coordination: training -> inference for 1 agents
..[info] Starting consensus coordination with 3 inference agents
.[info] Starting resource allocation coordination with 3 agents using greedy strategy
.[info] Starting barrier coordination with 2 training agents
.[warning] No capable agents found for coordination: :non_existent
..[warning] No agents meet resource requirements: %{cpu: 2.0, memory: 2.0}
.[warning] Insufficient inference agents for load balancing
.[info] Created barrier :node1_sync for 1 inference agents
.[info] Starting unknown_type coordination with 3 inference agents
...[info] Starting consensus coordination with 1 inference agents
..[info] Created barrier :sync_checkpoint for 1 coordination agents
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] MABEAM.AgentRegistry (test) started with anonymous ETS tables (process-managed)
[info] The function passed as a handler with ID "test_termination" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
[info] FoundationAgent mount called for agent test_agent_term_telemetry
[info] Attempting to register agent test_agent_term_telemetry with Bridge
[info] Registered Jido agent #PID<0.4616.0> with Foundation
[info] Agent test_agent_term_telemetry registered with Foundation
[info] SIGNAL: jido.agent.event.started from agent:test_agent_term_telemetry with data=%{agent_id: "test_agent_term_telemetry"}
[error] Elixir.JidoSystem.Agents.FoundationAgentTest.TestAgent server terminating

Reason:
** (ErlangError) Erlang error: :normal

Stacktrace:
    (elixir 1.18.3) lib/process.ex:896: Process.info/2
    (jido 1.2.0) lib/jido/agent/server.ex:344: Jido.Agent.Server.terminate/2
    (stdlib 6.2.2) gen_server.erl:2393: :gen_server.try_terminate/3
    (stdlib 6.2.2) gen_server.erl:2594: :gen_server.terminate/10
    (stdlib 6.2.2) proc_lib.erl:329: :proc_lib.init_p_do_apply/3


Agent State:
- ID: test_agent_term_telemetry
- Status: idle
- Queue Size: 0
- Mode: auto

[info] Agent test_agent_term_telemetry shutting down: :normal
[info] SIGNAL: jido.agent.event.stopped from agent:test_agent_term_telemetry with data=%{reason: :normal}
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] MABEAM.AgentRegistry (test) started with anonymous ETS tables (process-managed)
[info] FoundationAgent mount called for agent test_agent_1
[info] Attempting to register agent test_agent_1 with Bridge
[info] Registered Jido agent #PID<0.4622.0> with Foundation
[info] Agent test_agent_1 registered with Foundation
[info] SIGNAL: jido.agent.event.started from agent:test_agent_1 with data=%{agent_id: "test_agent_1"}
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] MABEAM.AgentRegistry (test) started with anonymous ETS tables (process-managed)
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] MABEAM.AgentRegistry (test) started with anonymous ETS tables (process-managed)
[info] FoundationAgent mount called for agent test_agent_errors
[info] Attempting to register agent test_agent_errors with Bridge
[info] Registered Jido agent #PID<0.4632.0> with Foundation
[info] Agent test_agent_errors registered with Foundation
[info] SIGNAL: jido.agent.event.started from agent:test_agent_errors with data=%{agent_id: "test_agent_errors"}
[info] The function passed as a handler with ID "test_errors" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] MABEAM.AgentRegistry (test) started with anonymous ETS tables (process-managed)
[info] The function passed as a handler with ID "test_startup" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
[info] FoundationAgent mount called for agent test_agent_telemetry
[info] Attempting to register agent test_agent_telemetry with Bridge
[info] Registered Jido agent #PID<0.4638.0> with Foundation
[info] Agent test_agent_telemetry registered with Foundation
[info] SIGNAL: jido.agent.event.started from agent:test_agent_telemetry with data=%{agent_id: "test_agent_telemetry"}
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] MABEAM.AgentRegistry (test) started with anonymous ETS tables (process-managed)
[info] FoundationAgent mount called for agent test_agent_failure
[info] Attempting to register agent test_agent_failure with Bridge
[info] Registered Jido agent #PID<0.4644.0> with Foundation
[info] Agent test_agent_failure registered with Foundation
[info] SIGNAL: jido.agent.event.started from agent:test_agent_failure with data=%{agent_id: "test_agent_failure"}
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] MABEAM.AgentRegistry (test) started with anonymous ETS tables (process-managed)
[info] FoundationAgent mount called for agent test_agent_terminate
[info] Attempting to register agent test_agent_terminate with Bridge
[info] Registered Jido agent #PID<0.4650.0> with Foundation
[info] Agent test_agent_terminate registered with Foundation
[info] SIGNAL: jido.agent.event.started from agent:test_agent_terminate with data=%{agent_id: "test_agent_terminate"}
[error] Elixir.JidoSystem.Agents.FoundationAgentTest.TestAgent server terminating

Reason:
** (ErlangError) Erlang error: :normal

Stacktrace:
    (elixir 1.18.3) lib/process.ex:896: Process.info/2
    (jido 1.2.0) lib/jido/agent/server.ex:344: Jido.Agent.Server.terminate/2
    (stdlib 6.2.2) gen_server.erl:2393: :gen_server.try_terminate/3
    (stdlib 6.2.2) gen_server.erl:2594: :gen_server.terminate/10
    (stdlib 6.2.2) proc_lib.erl:329: :proc_lib.init_p_do_apply/3


Agent State:
- ID: test_agent_terminate
- Status: idle
- Queue Size: 0
- Mode: auto

[info] Agent test_agent_terminate shutting down: :normal
[info] SIGNAL: jido.agent.event.stopped from agent:test_agent_terminate with data=%{reason: :normal}
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] MABEAM.AgentRegistry (test) started with anonymous ETS tables (process-managed)
[info] FoundationAgent mount called for agent test_agent_helpers
[info] Attempting to register agent test_agent_helpers with Bridge
[info] Registered Jido agent #PID<0.4656.0> with Foundation
[info] Agent test_agent_helpers registered with Foundation
[info] SIGNAL: jido.agent.event.started from agent:test_agent_helpers with data=%{agent_id: "test_agent_helpers"}
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] MABEAM.AgentRegistry (test) started with anonymous ETS tables (process-managed)
[info] FoundationAgent mount called for agent multi_agent_1
[info] Attempting to register agent multi_agent_1 with Bridge
[info] Registered Jido agent #PID<0.4662.0> with Foundation
[info] Agent multi_agent_1 registered with Foundation
[info] SIGNAL: jido.agent.event.started from agent:multi_agent_1 with data=%{agent_id: "multi_agent_1"}
[info] FoundationAgent mount called for agent multi_agent_2
[info] Attempting to register agent multi_agent_2 with Bridge
[info] Registered Jido agent #PID<0.4664.0> with Foundation
[info] Agent multi_agent_2 registered with Foundation
[info] SIGNAL: jido.agent.event.started from agent:multi_agent_2 with data=%{agent_id: "multi_agent_2"}
[info] FoundationAgent mount called for agent multi_agent_3
[info] Attempting to register agent multi_agent_3 with Bridge
[info] Registered Jido agent #PID<0.4666.0> with Foundation
[info] Agent multi_agent_3 registered with Foundation
[info] SIGNAL: jido.agent.event.started from agent:multi_agent_3 with data=%{agent_id: "multi_agent_3"}
[info] FoundationAgent mount called for agent multi_agent_4
[info] Attempting to register agent multi_agent_4 with Bridge
[info] Registered Jido agent #PID<0.4668.0> with Foundation
[info] Agent multi_agent_4 registered with Foundation
[info] SIGNAL: jido.agent.event.started from agent:multi_agent_4 with data=%{agent_id: "multi_agent_4"}
[info] FoundationAgent mount called for agent multi_agent_5
[info] Attempting to register agent multi_agent_5 with Bridge
[info] Registered Jido agent #PID<0.4670.0> with Foundation
[info] Agent multi_agent_5 registered with Foundation
.[info] SIGNAL: jido.agent.event.started from agent:multi_agent_5 with data=%{agent_id: "multi_agent_5"}
[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] MABEAM.AgentRegistry (test) started with anonymous ETS tables (process-managed)
[info] FoundationAgent mount called for agent test_agent_actions
[info] Attempting to register agent test_agent_actions with Bridge
[info] Registered Jido agent #PID<0.4676.0> with Foundation
[info] Agent test_agent_actions registered with Foundation
[info] SIGNAL: jido.agent.event.started from agent:test_agent_actions with data=%{agent_id: "test_agent_actions"}
[info] The function passed as a handler with ID "test_actions" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] MABEAM.AgentRegistry (test) started with anonymous ETS tables (process-managed)
[info] FoundationAgent mount called for agent test_agent_helpers
[info] Attempting to register agent test_agent_helpers with Bridge
[info] Registered Jido agent #PID<0.4682.0> with Foundation
[info] Agent test_agent_helpers registered with Foundation
[info] SIGNAL: jido.agent.event.started from agent:test_agent_helpers with data=%{agent_id: "test_agent_helpers"}
[info] The function passed as a handler with ID "test_emit_event" is a local function.
This means that it is either an anonymous function or a capture of a function without a module specified. That may cause a performance penalty when calling that handler. For more details see the note in `telemetry:attach/4` documentation.

https://hexdocs.pm/telemetry/telemetry.html#attach/4
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] MABEAM.AgentRegistry (test) started with anonymous ETS tables (process-managed)
[info] FoundationAgent mount called for agent test_agent_schema
[info] Attempting to register agent test_agent_schema with Bridge
[info] Registered Jido agent #PID<0.4688.0> with Foundation
[info] Agent test_agent_schema registered with Foundation
[info] SIGNAL: jido.agent.event.started from agent:test_agent_schema with data=%{agent_id: "test_agent_schema"}
.[info] MABEAM.AgentRegistry (default) started with anonymous ETS tables (process-managed)
[info] MABEAM.AgentRegistry (test) started with anonymous ETS tables (process-managed)
[info] FoundationAgent mount called for agent foundation_integration_test
[info] Attempting to register agent foundation_integration_test with Bridge
[info] Registered Jido agent #PID<0.4694.0> with Foundation
[info] Agent foundation_integration_test registered with Foundation
[info] SIGNAL: jido.agent.event.started from agent:foundation_integration_test with data=%{agent_id: "foundation_integration_test"}
.
Finished in 65.3 seconds (1.4s async, 63.8s sync)
281 tests, 20 failures
