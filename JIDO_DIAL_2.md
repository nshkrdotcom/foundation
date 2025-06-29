home@Desktop:~/p/g/n/elixir_ml/foundation$ mix dialyzer
Compiling 3 files (.ex)
     warning: Logger.warn/1 is deprecated. Use Logger.warning/2 instead
     │
 173 │         Logger.warn("Agent #{agent.id} encountered error: #{inspect(error)}")
     │         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     │
     └─ lib/jido_system/agents/foundation_agent.ex:173: JidoSystem.Agents.TaskAgent.on_error/2

     warning: Logger.warn/1 is deprecated. Use Logger.warning/2 instead
     │
 199 │             Logger.warn("Failed to deregister agent #{agent.id}: #{inspect(reason)}")
     │             ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     │
     └─ lib/jido_system/agents/foundation_agent.ex:199: JidoSystem.Agents.TaskAgent.shutdown/2

     warning: Logger.warn/1 is deprecated. Use Logger.warning/2 instead
     │
 216 │           Logger.warn("TaskAgent #{agent.id} has too many errors, pausing")
     │                  ~
     │
     └─ lib/jido_system/agents/task_agent.ex:216:18: JidoSystem.Agents.TaskAgent.on_error/2

    warning: unused alias QueueTask
    │
 78 │   alias JidoSystem.Actions.{ProcessTask, ValidateTask, QueueTask}
    │   ~
    │
    └─ lib/jido_system/agents/task_agent.ex:78:3

     warning: module attribute @impl was not set for function handle_info/2 callback (specified in GenServer). This either means you forgot to add the "@impl true" annotation before the definition or that you are accidentally overriding this callback
     │
 367 │   def handle_info(:process_queue, state) do
     │   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     │
     └─ lib/jido_system/agents/task_agent.ex:367: JidoSystem.Agents.TaskAgent (module)

     warning: Foundation.Registry.select/2 is undefined or private
     │
 357 │       agent_entries = Registry.select(Foundation.Registry, [{{:_, :_, :_}, [], [:"$_"]}])
     │                                ~
     │
     └─ lib/jido_system.ex:357:32: JidoSystem.get_system_status/0
     └─ lib/jido_system.ex:710:30: JidoSystem.stop_all_agents/2

     warning: Foundation.start_link/0 is undefined or private
     │
 518 │         Foundation.start_link()
     │                    ~
     │
     └─ lib/jido_system.ex:518:20: JidoSystem.ensure_foundation_started/0

     warning: Foundation.Registry.select/2 is undefined or private
     │
 169 │       registry_entries = Registry.select(Foundation.Registry, [{{:_, :_, :_}, [], [:"$_"]}])
     │                                   ~
     │
     └─ lib/jido_system/sensors/agent_performance_sensor.ex:169:35: JidoSystem.Sensors.AgentPerformanceSensor.collect_agent_performance_data/0

     warning: Foundation.Registry.keys/2 is undefined or private
     │
 612 │     case Registry.keys(Foundation.Registry, pid) do
     │                   ~
     │
     └─ lib/jido_system.ex:612:19: JidoSystem.get_agent_id/1

     warning: the following clause will never match:

         {:error, reason}

     because it attempts to match on the result of:

         deliver_signal(state)

     which has type:

         dynamic({:ok, term(), term()})

     typing violation found at:
     │
 639 │       {:error, reason} ->
     │       ~~~~~~~~~~~~~~~~~~~
     │
     └─ lib/jido_system/sensors/agent_performance_sensor.ex:639: JidoSystem.Sensors.AgentPerformanceSensor.handle_info/2

     warning: :scheduler.utilization/1 is undefined (module :scheduler is not available or is yet to be defined)
     │
 364 │       scheduler_utilization: :scheduler.utilization(1),
     │                                         ~
     │
     └─ lib/jido_system/agents/monitor_agent.ex:364:41: JidoSystem.Agents.MonitorAgent.collect_system_metrics/0

     warning: module attribute @impl was not set for function handle_info/2 callback (specified in GenServer). This either means you forgot to add the "@impl true" annotation before the definition or that you are accidentally overriding this callback
     │
 589 │   def handle_info(:collect_metrics, state) do
     │   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     │
     └─ lib/jido_system/agents/monitor_agent.ex:589: JidoSystem.Agents.MonitorAgent (module)

     warning: using single-quoted strings to represent charlists is deprecated.
     Use ~c"" if you indeed want a charlist or use "" instead.
     You may run "mix format --migrate" to change all single-quoted
     strings to use the ~c sigil and fix this warning.
     │
 271 │       case :os.cmd('uptime') |> to_string() do
     │                    ~
     │
     └─ lib/jido_system/sensors/system_health_sensor.ex:271:20

     warning: variable "metrics" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 581 │   defp generate_recommendations(:warning, analysis, metrics) do
     │                                                     ~~~~~~~
     │
     └─ lib/jido_system/sensors/system_health_sensor.ex:581:53: JidoSystem.Sensors.SystemHealthSensor.generate_recommendations/3

     warning: variable "analysis" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 603 │   defp generate_recommendations(:critical, analysis, metrics) do
     │                                            ~~~~~~~~
     │
     └─ lib/jido_system/sensors/system_health_sensor.ex:603:44: JidoSystem.Sensors.SystemHealthSensor.generate_recommendations/3

     warning: variable "metrics" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 603 │   defp generate_recommendations(:critical, analysis, metrics) do
     │                                                      ~~~~~~~
     │
     └─ lib/jido_system/sensors/system_health_sensor.ex:603:54: JidoSystem.Sensors.SystemHealthSensor.generate_recommendations/3

     warning: variable "analysis" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 609 │   defp generate_recommendations(:emergency, analysis, metrics) do
     │                                             ~~~~~~~~
     │
     └─ lib/jido_system/sensors/system_health_sensor.ex:609:45: JidoSystem.Sensors.SystemHealthSensor.generate_recommendations/3

     warning: variable "metrics" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 609 │   defp generate_recommendations(:emergency, analysis, metrics) do
     │                                                       ~~~~~~~
     │
     └─ lib/jido_system/sensors/system_health_sensor.ex:609:55: JidoSystem.Sensors.SystemHealthSensor.generate_recommendations/3

    warning: unused alias Telemetry
    │
 72 │   alias Foundation.{Telemetry, Registry}
    │   ~
    │
    └─ lib/jido_system/sensors/system_health_sensor.ex:72:3

     warning: :scheduler.utilization/1 is undefined (module :scheduler is not available or is yet to be defined)
     │
 340 │       :scheduler.utilization(1)
     │                  ~
     │
     └─ lib/jido_system/sensors/system_health_sensor.ex:340:18: JidoSystem.Sensors.SystemHealthSensor.get_scheduler_utilization/0

     warning: the following clause will never match:

         {:error, reason}

     because it attempts to match on the result of:

         deliver_signal(state)

     which has type:

         dynamic({:ok, term(), term()})

     typing violation found at:
     │
 624 │       {:error, reason} ->
     │       ~~~~~~~~~~~~~~~~~~~
     │
     └─ lib/jido_system/sensors/system_health_sensor.ex:624: JidoSystem.Sensors.SystemHealthSensor.handle_info/2

     warning: using single-quoted strings to represent charlists is deprecated.
     Use ~c"" if you indeed want a charlist or use "" instead.
     You may run "mix format --migrate" to change all single-quoted
     strings to use the ~c sigil and fix this warning.
     │
 402 │     case :os.cmd('uptime') |> to_string() do
     │                  ~
     │
     └─ lib/jido_system/agents/monitor_agent.ex:402:18

     warning: Logger.warn/1 is deprecated. Use Logger.warning/2 instead
     │
 173 │         Logger.warn("Agent #{agent.id} encountered error: #{inspect(error)}")
     │         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     │
     └─ lib/jido_system/agents/foundation_agent.ex:173: JidoSystem.Agents.MonitorAgent.on_error/2

     warning: Logger.warn/1 is deprecated. Use Logger.warning/2 instead
     │
 199 │             Logger.warn("Failed to deregister agent #{agent.id}: #{inspect(reason)}")
     │             ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     │
     └─ lib/jido_system/agents/foundation_agent.ex:199: JidoSystem.Agents.MonitorAgent.shutdown/2

     warning: variable "measurements" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 617 │   def handle_info({:telemetry_event, event, measurements, metadata}, state) do
     │                                             ~~~~~~~~~~~~
     │
     └─ lib/jido_system/agents/monitor_agent.ex:617:45: JidoSystem.Agents.MonitorAgent.handle_info/2

    warning: unused alias CheckThresholds
    │
 96 │   alias JidoSystem.Actions.{CollectMetrics, AnalyzeHealth, CheckThresholds}
    │   ~
    │
    └─ lib/jido_system/agents/monitor_agent.ex:96:3

    warning: unused alias Registry
    │
 34 │   alias Foundation.Registry
    │   ~
    │
    └─ lib/jido_system/agents/foundation_agent.ex:34:3

     warning: got "@impl Foundation.Infrastructure" for function protocol_version/1 but this behaviour was not declared with @behaviour
     │
 294 │   def protocol_version(_impl), do: {:ok, "1.0"}
     │   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     │
     └─ lib/foundation/infrastructure/circuit_breaker.ex:294: Foundation.Infrastructure.CircuitBreaker (module)

     warning: got "@impl Foundation.Infrastructure" for function register_circuit_breaker/3 but this behaviour was not declared with @behaviour
     │
 297 │   def register_circuit_breaker(_impl, service_id, config) do
     │   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     │
     └─ lib/foundation/infrastructure/circuit_breaker.ex:297: Foundation.Infrastructure.CircuitBreaker (module)

     warning: got "@impl Foundation.Infrastructure" for function execute_protected/4 but this behaviour was not declared with @behaviour
     │
 302 │   def execute_protected(_impl, service_id, function, _context) do
     │   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     │
     └─ lib/foundation/infrastructure/circuit_breaker.ex:302: Foundation.Infrastructure.CircuitBreaker (module)

     warning: got "@impl Foundation.Infrastructure" for function get_circuit_status/2 but this behaviour was not declared with @behaviour
     │
 307 │   def get_circuit_status(_impl, service_id) do
     │   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     │
     └─ lib/foundation/infrastructure/circuit_breaker.ex:307: Foundation.Infrastructure.CircuitBreaker (module)

     warning: got "@impl Foundation.Infrastructure" for function setup_rate_limiter/3 but this behaviour was not declared with @behaviour
     │
 314 │   def setup_rate_limiter(_impl, _limiter_id, _config) do
     │   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     │
     └─ lib/foundation/infrastructure/circuit_breaker.ex:314: Foundation.Infrastructure.CircuitBreaker (module)

     warning: got "@impl Foundation.Infrastructure" for function check_rate_limit/3 but this behaviour was not declared with @behaviour
     │
 319 │   def check_rate_limit(_impl, _limiter_id, _identifier) do
     │   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     │
     └─ lib/foundation/infrastructure/circuit_breaker.ex:319: Foundation.Infrastructure.CircuitBreaker (module)

     warning: got "@impl Foundation.Infrastructure" for function get_rate_limit_status/3 but this behaviour was not declared with @behaviour
     │
 324 │   def get_rate_limit_status(_impl, _limiter_id, _identifier) do
     │   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     │
     └─ lib/foundation/infrastructure/circuit_breaker.ex:324: Foundation.Infrastructure.CircuitBreaker (module)

     warning: got "@impl Foundation.Infrastructure" for function monitor_resource/3 but this behaviour was not declared with @behaviour
     │
 329 │   def monitor_resource(_impl, _resource_id, _config) do
     │   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     │
     └─ lib/foundation/infrastructure/circuit_breaker.ex:329: Foundation.Infrastructure.CircuitBreaker (module)

     warning: got "@impl Foundation.Infrastructure" for function get_resource_usage/2 but this behaviour was not declared with @behaviour
     │
 334 │   def get_resource_usage(_impl, _resource_id) do
     │   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     │
     └─ lib/foundation/infrastructure/circuit_breaker.ex:334: Foundation.Infrastructure.CircuitBreaker (module)

     warning: variable "context" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 294 │   defp apply_validation_rule(:external, task, params, context) do
     │                                                       ~~~~~~~
     │
     └─ lib/jido_system/actions/validate_task.ex:294:55: JidoSystem.Actions.ValidateTask.apply_validation_rule/4

     warning: Logger.warn/2 is deprecated. Use Logger.warning/2 instead
     │
 317 │     Logger.warn("Unknown validation rule",
     │            ~
     │
     └─ lib/jido_system/actions/validate_task.ex:317:12: JidoSystem.Actions.ValidateTask.apply_validation_rule/4

     warning: variable "task" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 443 │   defp apply_business_rule(:rate_limit, config, task, context) do
     │                                                 ~~~~
     │
     └─ lib/jido_system/actions/validate_task.ex:443:49: JidoSystem.Actions.ValidateTask.apply_business_rule/4

     warning: Logger.warn/2 is deprecated. Use Logger.warning/2 instead
     │
 462 │     Logger.warn("Unknown business rule", rule: rule_name)
     │            ~
     │
     └─ lib/jido_system/actions/validate_task.ex:462:12: JidoSystem.Actions.ValidateTask.apply_business_rule/4

     warning: variable "timeout" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 500 │   defp validate_with_schema_service(task, endpoint, timeout) do
     │                                                     ~~~~~~~
     │
     └─ lib/jido_system/actions/validate_task.ex:500:53: JidoSystem.Actions.ValidateTask.validate_with_schema_service/3

     warning: variable "timeout" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 513 │   defp validate_with_data_quality_service(task, endpoint, timeout) do
     │                                                           ~~~~~~~
     │
     └─ lib/jido_system/actions/validate_task.ex:513:59: JidoSystem.Actions.ValidateTask.validate_with_data_quality_service/3

     warning: variable "timeout" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 528 │   defp validate_with_compliance_service(task, endpoint, timeout) do
     │                                                         ~~~~~~~
     │
     └─ lib/jido_system/actions/validate_task.ex:528:57: JidoSystem.Actions.ValidateTask.validate_with_compliance_service/3

     warning: variable "validated_task" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 590 │       {:ok, validated_task} ->
     │             ~
     │
     └─ lib/jido_system/actions/validate_task.ex:590:13: JidoSystem.Actions.ValidateTask.emit_validation_telemetry/5

    warning: unused alias Bridge
    │
 56 │   alias JidoFoundation.Bridge
    │   ~
    │
    └─ lib/jido_system/actions/validate_task.ex:56:3

    warning: unused alias Telemetry
    │
 55 │   alias Foundation.{Telemetry, CircuitBreaker, Cache}
    │   ~
    │
    └─ lib/jido_system/actions/validate_task.ex:55:3

     warning: Logger.warn/1 is deprecated. Use Logger.warning/2 instead
     │
 539 │           Logger.warn("Failed to auto-start monitoring: #{inspect(reason)}")
     │                  ~
     │
     └─ lib/jido_system.ex:539:18: JidoSystem.start_jido_system_components/1

     warning: variable "auto_start_sensors" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 528 │     auto_start_sensors = Keyword.get(opts, :auto_start_sensors, true)
     │     ~~~~~~~~~~~~~~~~~~
     │
     └─ lib/jido_system.ex:528:5: JidoSystem.start_jido_system_components/1

     warning: Logger.warn/1 is deprecated. Use Logger.warning/2 instead
     │
 554 │           Logger.warn("Unknown sensor type: #{sensor_type}")
     │                  ~
     │
     └─ lib/jido_system.ex:554:18: JidoSystem.start_sensors/3

     warning: variable "module" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 698 │   defp get_sensor_description(module) do
     │                               ~~~~~~
     │
     └─ lib/jido_system.ex:698:31: JidoSystem.get_sensor_description/1

     warning: variable "module" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 703 │   defp get_sensor_category(module) do
     │                            ~~~~~~
     │
     └─ lib/jido_system.ex:703:28: JidoSystem.get_sensor_category/1

    warning: unused alias ValidateTask
    │
 62 │   alias JidoSystem.Actions.{ProcessTask, ValidateTask}
    │   ~
    │
    └─ lib/jido_system.ex:62:3

     warning: Logger.warn/1 is deprecated. Use Logger.warning/2 instead
     │
 173 │         Logger.warn("Agent #{agent.id} encountered error: #{inspect(error)}")
     │         ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     │
     └─ lib/jido_system/agents/foundation_agent.ex:173: JidoSystem.Agents.CoordinatorAgent.on_error/2

     warning: Logger.warn/1 is deprecated. Use Logger.warning/2 instead
     │
 199 │             Logger.warn("Failed to deregister agent #{agent.id}: #{inspect(reason)}")
     │             ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     │
     └─ lib/jido_system/agents/foundation_agent.ex:199: JidoSystem.Agents.CoordinatorAgent.shutdown/2

     warning: variable "reason" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 496 │   defp update_failure_tracking(failure_recovery, agent_id, reason) do
     │                                                            ~~~~~~
     │
     └─ lib/jido_system/agents/coordinator_agent.ex:496:60: JidoSystem.Agents.CoordinatorAgent.update_failure_tracking/3

     warning: variable "workflow" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 552 │       %{status: :running, current_step: step, workflow: %{tasks: tasks}} = workflow
     │                                                                            ~
     │
     └─ lib/jido_system/agents/coordinator_agent.ex:552:76: JidoSystem.Agents.CoordinatorAgent.handle_info/2

     warning: unused alias ExecuteWorkflow
     │
 104 │   alias JidoSystem.Actions.{RegisterAgents, ExecuteWorkflow, DistributeTask}
     │   ~
     │
     └─ lib/jido_system/agents/coordinator_agent.ex:104:3

     warning: unused alias RegisterAgents
     │
 104 │   alias JidoSystem.Actions.{RegisterAgents, ExecuteWorkflow, DistributeTask}
     │   ~
     │
     └─ lib/jido_system/agents/coordinator_agent.ex:104:3

     warning: unused alias Registry
     │
 102 │   alias Foundation.{Registry, Telemetry}
     │   ~
     │
     └─ lib/jido_system/agents/coordinator_agent.ex:102:3

     warning: unused alias Telemetry
     │
 102 │   alias Foundation.{Registry, Telemetry}
     │   ~
     │
     └─ lib/jido_system/agents/coordinator_agent.ex:102:3

     warning: the following clause will never match:

         {:ok, task_result}

     because it attempts to match on the result of:

         JidoFoundation.Bridge.delegate_task(selected_agent.pid, task, timeout: agent.state.task_timeout)

     which has type:

         dynamic(:ok or {:error, :delegation_failed})

     typing violation found at:
     │
 258 │             {:ok, task_result} ->
     │             ~~~~~~~~~~~~~~~~~~~~~
     │
     └─ lib/jido_system/agents/coordinator_agent.ex:258: JidoSystem.Agents.CoordinatorAgent.handle_distribute_task/2

     warning: the following clause will never match:

         {:ok, result}

     because it attempts to match on the result of:

         JidoFoundation.Bridge.delegate_task(alternative_agent.pid, task, [])

     which has type:

         dynamic(:ok or {:error, :delegation_failed})

     typing violation found at:
     │
 481 │           {:ok, result} ->
     │           ~~~~~~~~~~~~~~~~
     │
     └─ lib/jido_system/agents/coordinator_agent.ex:481: JidoSystem.Agents.CoordinatorAgent.handle_task_failure/4

     warning: module attribute @impl was not set for function handle_info/2 callback (specified in GenServer). This either means you forgot to add the "@impl true" annotation before the definition or that you are accidentally overriding this callback
     │
 528 │   def handle_info({:start_workflow_execution, execution_id}, state) do
     │   ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
     │
     └─ lib/jido_system/agents/coordinator_agent.ex:528: JidoSystem.Agents.CoordinatorAgent (module)

     warning: Logger.warn/2 is deprecated. Use Logger.warning/2 instead
     │
 134 │           Logger.warn("Task validation failed",
     │                  ~
     │
     └─ lib/jido_system/actions/process_task.ex:134:18: JidoSystem.Actions.ProcessTask.run/2

     warning: Logger.warn/2 is deprecated. Use Logger.warning/2 instead
     │
 214 │         Logger.warn("Task attempt failed, retrying",
     │                ~
     │
     └─ lib/jido_system/actions/process_task.ex:214:16: JidoSystem.Actions.ProcessTask.process_with_retry/3

     warning: variable "context" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 397 │   defp process_notification_task(params, context) do
     │                                          ~~~~~~~
     │
     └─ lib/jido_system/actions/process_task.ex:397:42: JidoSystem.Actions.ProcessTask.process_notification_task/2

     warning: Logger.warn/2 is deprecated. Use Logger.warning/2 instead
     │
 433 │     Logger.warn("Unknown transformation", transform: transform)
     │            ~
     │
     └─ lib/jido_system/actions/process_task.ex:433:12: JidoSystem.Actions.ProcessTask.apply_transformation/2

     warning: function calculate_backoff/1 is unused
     │
 504 │   defp calculate_backoff(attempt) do
     │        ~
     │
     └─ lib/jido_system/actions/process_task.ex:504:8: JidoSystem.Actions.ProcessTask (module)

    warning: unused alias Bridge
    │
 48 │   alias JidoFoundation.Bridge
    │   ~
    │
    └─ lib/jido_system/actions/process_task.ex:48:3

     warning: Logger.warn/2 is deprecated. Use Logger.warning/2 instead
     │
 183 │         Logger.warn("Failed to collect agent performance data", error: inspect(e))
     │                ~
     │
     └─ lib/jido_system/sensors/agent_performance_sensor.ex:183:16: JidoSystem.Sensors.AgentPerformanceSensor.collect_agent_performance_data/0

     warning: variable "trends" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 431 │   defp classify_performance_level(issues, stats, trends) do
     │                                                  ~~~~~~
     │
     └─ lib/jido_system/sensors/agent_performance_sensor.ex:431:50: JidoSystem.Sensors.AgentPerformanceSensor.classify_performance_level/3

     warning: variable "stats" is unused (if the variable is not meant to be used, prefix it with an underscore)
     │
 447 │   defp generate_optimization_suggestions(issues, stats, trends) do
     │                                                  ~~~~~
     │
     └─ lib/jido_system/sensors/agent_performance_sensor.ex:447:50: JidoSystem.Sensors.AgentPerformanceSensor.generate_optimization_suggestions/3

     warning: clauses with the same name and arity (number of arguments) should be grouped together, "def handle_info/2" was previously defined (lib/jido_system/sensors/agent_performance_sensor.ex:633)
     │
 674 │   def handle_info(msg, state) do
     │       ~
     │
     └─ lib/jido_system/sensors/agent_performance_sensor.ex:674:7

Generated foundation app
Finding suitable PLTs
Checking PLT...
[:abacus, :asn1, :backoff, :certifi, :circular_buffer, :compiler, :cowboy, :cowboy_telemetry, :cowlib, :crontab, :crypto, :deep_merge, :eex, :elixir, :ex_check, :ex_dbug, :finch, :foundation, :fuse, :gemini_ex, :gen_stage, :git_cli, :git_ops, :hackney, :hammer, :hpax, :httpoison, :idna, :jason, :jido, :jido_action, :jido_signal, :joken, :jose, :kernel, :libgraph, :logger, :meck, :metrics, :mime, :mimerl, :mint, :mox, :msgpax, :nimble_options, :nimble_ownership, :nimble_parsec, :nimble_pool, :ok, :parse_trans, ...]
PLT is up to date!
:ignore_warnings opt specified in mix.exs: .dialyzer.ignore.exs, but file does not exist.

Starting Dialyzer
[
  check_plt: false,
  init_plt: ~c"/home/home/p/g/n/elixir_ml/foundation/priv/plts/dialyzer.plt",
  files: [~c"_build/dev/lib/foundation/ebin/Elixir.MLFoundation.AgentPatterns.WorkflowCoordinator.beam",
   ~c"_build/dev/lib/foundation/ebin/Elixir.MLFoundation.DistributedOptimization.SGDWorker.beam",
   ~c"_build/dev/lib/foundation/ebin/Elixir.MLFoundation.TeamOrchestration.ValidatorAgent.beam",
   ~c"_build/dev/lib/foundation/ebin/Elixir.MLFoundation.DistributedOptimization.beam",
   ~c"_build/dev/lib/foundation/ebin/Elixir.MABEAM.AgentCoordination.beam",
   ...],
  warnings: [:error_handling, :underspecs, :unknown]
]
Total errors: 112, Skipped: 0, Unnecessary Skips: 0
done in 0m4.09s
deps/jido/lib/jido/agent.ex:49:unused_fun
Function do_validate/3 will never be called.
________________________________________________________________________________
deps/jido/lib/jido/agent.ex:49:unused_fun
Function enqueue_instructions/2 will never be called.
________________________________________________________________________________
deps/jido/lib/jido/agent.ex:57:unused_fun
Function do_validate/3 will never be called.
________________________________________________________________________________
deps/jido/lib/jido/agent.ex:57:unused_fun
Function enqueue_instructions/2 will never be called.
________________________________________________________________________________
deps/jido/lib/jido/agent.ex:63:unused_fun
Function do_validate/3 will never be called.
________________________________________________________________________________
deps/jido/lib/jido/agent.ex:63:unused_fun
Function enqueue_instructions/2 will never be called.
________________________________________________________________________________
deps/jido/lib/jido/agent.ex:592:call
The function call will not succeed.

JidoSystem.Agents.CoordinatorAgent.set(_ :: %JidoSystem.Agents.CoordinatorAgent{}, _ :: map(), _ :: any())

breaks the contract
(t() | Jido.server(), :elixir.keyword() | map(), :elixir.keyword()) :: agent_result()

________________________________________________________________________________
deps/jido/lib/jido/agent.ex:592:call
The function call will not succeed.

JidoSystem.Agents.MonitorAgent.set(_ :: %JidoSystem.Agents.MonitorAgent{}, _ :: map(), _ :: any())

breaks the contract
(t() | Jido.server(), :elixir.keyword() | map(), :elixir.keyword()) :: agent_result()

________________________________________________________________________________
deps/jido/lib/jido/agent.ex:592:call
The function call will not succeed.

JidoSystem.Agents.TaskAgent.set(_ :: %JidoSystem.Agents.TaskAgent{}, _ :: map(), _ :: any())

breaks the contract
(t() | Jido.server(), :elixir.keyword() | map(), :elixir.keyword()) :: agent_result()

________________________________________________________________________________
deps/jido/lib/jido/agent.ex:604:call
The function call will not succeed.

JidoSystem.Agents.CoordinatorAgent.validate(_ :: %JidoSystem.Agents.CoordinatorAgent{:state => map(), _ => _}, [
  {:strict_validation, _},
  ...
])

breaks the contract
(t() | Jido.server(), :elixir.keyword()) :: agent_result()

________________________________________________________________________________
deps/jido/lib/jido/agent.ex:604:call
The function call will not succeed.

JidoSystem.Agents.MonitorAgent.validate(_ :: %JidoSystem.Agents.MonitorAgent{:state => map(), _ => _}, [
  {:strict_validation, _},
  ...
])

breaks the contract
(t() | Jido.server(), :elixir.keyword()) :: agent_result()

________________________________________________________________________________
deps/jido/lib/jido/agent.ex:604:call
The function call will not succeed.

JidoSystem.Agents.TaskAgent.validate(_ :: %JidoSystem.Agents.TaskAgent{:state => map(), _ => _}, [{:strict_validation, _}, ...]) ::
  :ok
def a() do
  :ok
end

breaks the contract
(t() | Jido.server(), :elixir.keyword()) :: agent_result()

________________________________________________________________________________
deps/jido/lib/jido/agent.ex:705:call
The function call will not succeed.

JidoSystem.Agents.CoordinatorAgent.on_before_validate_state(_ :: %JidoSystem.Agents.CoordinatorAgent{})

breaks the contract
(t()) :: agent_result()

________________________________________________________________________________
deps/jido/lib/jido/agent.ex:705:call
The function call will not succeed.

JidoSystem.Agents.MonitorAgent.on_before_validate_state(_ :: %JidoSystem.Agents.MonitorAgent{})

breaks the contract
(t()) :: agent_result()

________________________________________________________________________________
deps/jido/lib/jido/agent.ex:705:call
The function call will not succeed.

JidoSystem.Agents.TaskAgent.on_before_validate_state(_ :: %JidoSystem.Agents.TaskAgent{})

breaks the contract
(t()) :: agent_result()

________________________________________________________________________________
deps/jido/lib/jido/agent.ex:846:call
The function call will not succeed.

JidoSystem.Agents.CoordinatorAgent.on_before_plan(_ :: %JidoSystem.Agents.CoordinatorAgent{}, nil, %{})

breaks the contract
(t(), Jido.Instruction.instruction_list(), map()) :: agent_result()

________________________________________________________________________________
deps/jido/lib/jido/agent.ex:846:call
The function call will not succeed.

JidoSystem.Agents.MonitorAgent.on_before_plan(_ :: %JidoSystem.Agents.MonitorAgent{}, nil, %{})

breaks the contract
(t(), Jido.Instruction.instruction_list(), map()) :: agent_result()

________________________________________________________________________________
deps/jido/lib/jido/agent.ex:846:call
The function call will not succeed.

JidoSystem.Agents.TaskAgent.on_before_plan(_ :: %JidoSystem.Agents.TaskAgent{}, nil, %{})

breaks the contract
(t(), Jido.Instruction.instruction_list(), map()) :: agent_result()

________________________________________________________________________________
deps/jido/lib/jido/agent.ex:961:call
The function call will not succeed.

JidoSystem.Agents.CoordinatorAgent.on_before_run(_ :: %JidoSystem.Agents.CoordinatorAgent{})

breaks the contract
(t()) :: agent_result()

________________________________________________________________________________
deps/jido/lib/jido/agent.ex:961:call
The function call will not succeed.

JidoSystem.Agents.MonitorAgent.on_before_run(_ :: %JidoSystem.Agents.MonitorAgent{})

breaks the contract
(t()) :: agent_result()

________________________________________________________________________________
deps/jido/lib/jido/agent.ex:961:call
The function call will not succeed.

JidoSystem.Agents.TaskAgent.on_before_run(_ :: %JidoSystem.Agents.TaskAgent{})

breaks the contract
(t()) :: agent_result()

________________________________________________________________________________
deps/jido/lib/jido/agent.ex:1063:call
The function call will not succeed.

JidoSystem.Agents.CoordinatorAgent.set(_ :: %JidoSystem.Agents.CoordinatorAgent{}, _ :: any(), [{:strict_validation, _}, ...]) ::
  :ok
def a() do
  :ok
end

breaks the contract
(t() | Jido.server(), :elixir.keyword() | map(), :elixir.keyword()) :: agent_result()

________________________________________________________________________________
deps/jido/lib/jido/agent.ex:1063:call
The function call will not succeed.

JidoSystem.Agents.MonitorAgent.set(_ :: %JidoSystem.Agents.MonitorAgent{}, _ :: any(), [{:strict_validation, _}, ...])

breaks the contract
(t() | Jido.server(), :elixir.keyword() | map(), :elixir.keyword()) :: agent_result()

________________________________________________________________________________
deps/jido/lib/jido/agent.ex:1063:call
The function call will not succeed.

JidoSystem.Agents.TaskAgent.set(_ :: %JidoSystem.Agents.TaskAgent{}, _ :: any(), [{:strict_validation, _}, ...])

breaks the contract
(t() | Jido.server(), :elixir.keyword() | map(), :elixir.keyword()) :: agent_result()

________________________________________________________________________________
lib/jido_system.ex:96:extra_range
The type specification has too many types for the function.

Function:
JidoSystem.start/1

Extra type:
{:ok, pid()}

Success typing:
{:error, {:foundation_start_failed, _}} | {:ok, [{:monitoring, map()}]}

________________________________________________________________________________
lib/jido_system.ex:187:extra_range
The type specification has too many types for the function.

Function:
JidoSystem.process_task/3

Extra type:
{:ok, _}

Success typing:
{:error, :server_not_found}

________________________________________________________________________________
lib/jido_system.ex:235:contract_supertype
Type specification is a supertype of the success typing.

Function:
JidoSystem.start_monitoring/1

Type specification:
@spec start_monitoring(:elixir.keyword()) :: {:ok, map()} | {:error, term()}

Success typing:
@spec start_monitoring(Keyword.t()) ::
  {:error, _}
  | {:ok,
     %{
       :configuration => map(),
       :monitor_agent => pid(),
       :sensors => map(),
       :started_at => map()
     }}

________________________________________________________________________________
lib/jido_system.ex:308:extra_range
The type specification has too many types for the function.

Function:
JidoSystem.execute_workflow/3

Extra type:
{:ok, binary()}

Success typing:
{:error, :server_not_found}

________________________________________________________________________________
lib/jido_system.ex:353:contract_supertype
Type specification is a supertype of the success typing.

Function:
JidoSystem.get_system_status/0

Type specification:
@spec get_system_status() :: {:ok, map()} | {:error, term()}

Success typing:
@spec get_system_status() ::
  {:error, {:status_collection_failed, map()}}
  | {:ok,
     %{
       :agent_count => non_neg_integer(),
       :agents => map(),
       :health_score => number(),
       :performance_metrics => map(),
       :sensor_count => 0,
       :system_info => map(),
       :timestamp => map(),
       :uptime => non_neg_integer()
     }}

________________________________________________________________________________
lib/jido_system.ex:484:contract_supertype
Type specification is a supertype of the success typing.

Function:
JidoSystem.stop/1

Type specification:
@spec stop(:elixir.keyword()) :: :ok | {:error, term()}

Success typing:
@spec stop(Keyword.t()) ::
  :ok
  | {:error,
     {:shutdown_failed, %{:__exception__ => true, :__struct__ => atom(), atom() => _}}}

________________________________________________________________________________
lib/jido_system.ex:201:11:pattern_match
The pattern can never match the type.

Pattern:
:ok

Type:
{:error, :server_not_found} | {:ok, binary()}

________________________________________________________________________________
lib/jido_system.ex:322:11:pattern_match
The pattern can never match the type.

Pattern:
:ok

Type:
{:error, :server_not_found} | {:ok, binary()}

________________________________________________________________________________
lib/jido_system.ex:357:32:call_to_missing
Call to missing or private function Foundation.Registry.select/2.
________________________________________________________________________________
lib/jido_system.ex:518:20:call_to_missing
Call to missing or private function Foundation.start_link/0.
________________________________________________________________________________
lib/jido_system.ex:612:19:call_to_missing
Call to missing or private function Foundation.Registry.keys/2.
________________________________________________________________________________
lib/jido_system.ex:710:30:call_to_missing
Call to missing or private function Foundation.Registry.select/2.
________________________________________________________________________________
lib/jido_system/actions/get_performance_metrics.ex:6:extra_range
The type specification has too many types for the function.

Function:
JidoSystem.Actions.GetPerformanceMetrics.run/2

Extra type:
{:error, _}

Success typing:
{:ok, %{:queue_size => non_neg_integer(), :success_rate => float(), _ => _}}

________________________________________________________________________________
lib/jido_system/actions/get_task_status.ex:6:extra_range
The type specification has too many types for the function.

Function:
JidoSystem.Actions.GetTaskStatus.run/2

Extra type:
{:error, _}

Success typing:

  {:ok,
   %{
     :current_task => _,
     :error_count => _,
     :performance_metrics => _,
     :processed_count => _,
     :queue_size => non_neg_integer(),
     :status => _,
     :uptime => integer()
   }}


________________________________________________________________________________
lib/jido_system/actions/pause_processing.ex:6:extra_range
The type specification has too many types for the function.

Function:
JidoSystem.Actions.PauseProcessing.run/2

Extra type:
{:error, _}

Success typing:

  {:ok,
   %{
     :paused_at => %DateTime{
       :calendar => atom(),
       :day => pos_integer(),
       :hour => non_neg_integer(),
       :microsecond => {_, _},
       :minute => non_neg_integer(),
       :month => pos_integer(),
       :second => non_neg_integer(),
       :std_offset => integer(),
       :time_zone => binary(),
       :utc_offset => integer(),
       :year => integer(),
       :zone_abbr => binary()
     },
     :previous_status => _,
     :reason => _,
     :status => :paused
   }}


________________________________________________________________________________
lib/jido_system/actions/resume_processing.ex:6:extra_range
The type specification has too many types for the function.

Function:
JidoSystem.Actions.ResumeProcessing.run/2

Extra type:
{:error, _}

Success typing:

  {:ok,
   %{
     :previous_status => _,
     :resumed_at => %DateTime{
       :calendar => atom(),
       :day => pos_integer(),
       :hour => non_neg_integer(),
       :microsecond => {_, _},
       :minute => non_neg_integer(),
       :month => pos_integer(),
       :second => non_neg_integer(),
       :std_offset => integer(),
       :time_zone => binary(),
       :utc_offset => integer(),
       :year => integer(),
       :zone_abbr => binary()
     },
     :status => :idle
   }}


________________________________________________________________________________
lib/jido_system/agents/coordinator_agent.ex:63:callback_spec_arg_type_mismatch
The @spec type for the 1st argument is not a
supertype of the expected type for the mount/2 callback
in the Jido.Agent behaviour.

Success type:
%Jido.Agent.Server.State{
  :agent => %Jido.Agent{
    :actions => [atom()],
    :category => nil | binary(),
    :description => nil | binary(),
    :dirty_state? => boolean(),
    :id => nil | binary(),
    :name => nil | binary(),
    :pending_instructions => nil | :queue.queue(_),
    :result => _,
    :runner => atom(),
    :schema => nil | Keyword.t(),
    :state => map(),
    :tags => nil | [binary()],
    :vsn => nil | binary()
  },
  :child_supervisor => nil | pid(),
  :current_signal => %Jido.Signal{
    :data => _,
    :datacontenttype => nil | binary(),
    :dataschema => nil | binary(),
    :id => binary(),
    :jido_dispatch => nil | Keyword.t(Keyword.t()) | {atom(), Keyword.t()},
    :source => binary(),
    :specversion => binary(),
    :subject => nil | binary(),
    :time => nil | binary(),
    :type => binary()
  },
  :current_signal_type => atom(),
  :dispatch => [
    {:err, {atom(), Keyword.t()}}
    | {:log, {atom(), Keyword.t()}}
    | {:out, {atom(), Keyword.t()}}
  ],
  :journal => %Jido.Signal.Journal{:adapter => atom(), :adapter_pid => nil | pid()},
  :log_level =>
    :alert | :critical | :debug | :emergency | :error | :info | :notice | :warning,
  :max_queue_size => non_neg_integer(),
  :mode => :auto | :step,
  :opts => Keyword.t(),
  :orchestrator_pid => nil | pid(),
  :parent_pid => nil | pid(),
  :pending_signals => :queue.queue(_),
  :registry => atom(),
  :reply_refs => %{binary() => {pid(), _}},
  :router => %Jido.Signal.Router.Router{
    :route_count => non_neg_integer(),
    :trie => %Jido.Signal.Router.TrieNode{
      :handlers =>
        nil
        | %Jido.Signal.Router.NodeHandlers{
            :handlers => [
              %Jido.Signal.Router.HandlerInfo{
                :complexity => non_neg_integer(),
                :priority => non_neg_integer(),
                :target => _
              }
            ],
            :matchers => [
              %Jido.Signal.Router.PatternMatch{
                :complexity => non_neg_integer(),
                :match => (%Jido.Signal{
                             :data => _,
                             :datacontenttype => nil | binary(),
                             :dataschema => nil | binary(),
                             :id => binary(),
                             :jido_dispatch =>
                               nil | Keyword.t(Keyword.t()) | {atom(), Keyword.t()},
                             :source => binary(),
                             :specversion => binary(),
                             :subject => nil | binary(),
                             :time => nil | binary(),
                             :type => binary()
                           } ->
                             boolean()),
                :priority => non_neg_integer(),
                :target => _
              }
            ]
          },
      :segments => %{
        binary() => %Jido.Signal.Router.TrieNode{
          :handlers => nil | map(),
          :segments => map(),
          :wildcards => [any()],
          _ => _
        }
      },
      :wildcards => [
        %Jido.Signal.Router.WildcardHandlers{
          :handlers => %Jido.Signal.Router.NodeHandlers{
            :handlers => [
              %Jido.Signal.Router.HandlerInfo{
                :complexity => non_neg_integer(),
                :priority => non_neg_integer(),
                :target => _
              }
            ],
            :matchers => [
              %Jido.Signal.Router.PatternMatch{
                :complexity => non_neg_integer(),
                :match => (%Jido.Signal{
                             :data => _,
                             :datacontenttype => nil | binary(),
                             :dataschema => nil | binary(),
                             :id => binary(),
                             :jido_dispatch =>
                               nil | Keyword.t(Keyword.t()) | {atom(), Keyword.t()},
                             :source => binary(),
                             :specversion => binary(),
                             :subject => nil | binary(),
                             :time => nil | binary(),
                             :type => binary()
                           } ->
                             boolean()),
                :priority => non_neg_integer(),
                :target => _
              }
            ]
          },
          :type => :multi | :single
        }
      ]
    }
  },
  :skills => [
    %Jido.Skill{
      :category => nil | binary(),
      :description => nil | binary(),
      :name => binary(),
      :opts_key => atom(),
      :opts_schema => nil | map(),
      :signal_patterns => [binary()],
      :tags => [binary()],
      :vsn => nil | binary()
    }
  ],
  :status => :idle | :initializing | :paused | :planning | :running
}

Behaviour callback type:
%Jido.Agent{
  :actions => [atom()],
  :category => nil | binary(),
  :description => nil | binary(),
  :dirty_state? => boolean(),
  :id => nil | binary(),
  :name => nil | binary(),
  :pending_instructions => nil | :queue.queue(_),
  :result => _,
  :runner => atom(),
  :schema => nil | Keyword.t(),
  :state => map(),
  :tags => nil | [binary()],
  :vsn => nil | binary()
}

________________________________________________________________________________
lib/jido_system/agents/coordinator_agent.ex:63:callback_spec_arg_type_mismatch
The @spec type for the 1st argument is not a
supertype of the expected type for the shutdown/2 callback
in the Jido.Agent behaviour.

Success type:
%Jido.Agent.Server.State{
  :agent => %Jido.Agent{
    :actions => [atom()],
    :category => nil | binary(),
    :description => nil | binary(),
    :dirty_state? => boolean(),
    :id => nil | binary(),
    :name => nil | binary(),
    :pending_instructions => nil | :queue.queue(_),
    :result => _,
    :runner => atom(),
    :schema => nil | Keyword.t(),
    :state => map(),
    :tags => nil | [binary()],
    :vsn => nil | binary()
  },
  :child_supervisor => nil | pid(),
  :current_signal => %Jido.Signal{
    :data => _,
    :datacontenttype => nil | binary(),
    :dataschema => nil | binary(),
    :id => binary(),
    :jido_dispatch => nil | Keyword.t(Keyword.t()) | {atom(), Keyword.t()},
    :source => binary(),
    :specversion => binary(),
    :subject => nil | binary(),
    :time => nil | binary(),
    :type => binary()
  },
  :current_signal_type => atom(),
  :dispatch => [
    {:err, {atom(), Keyword.t()}}
    | {:log, {atom(), Keyword.t()}}
    | {:out, {atom(), Keyword.t()}}
  ],
  :journal => %Jido.Signal.Journal{:adapter => atom(), :adapter_pid => nil | pid()},
  :log_level =>
    :alert | :critical | :debug | :emergency | :error | :info | :notice | :warning,
  :max_queue_size => non_neg_integer(),
  :mode => :auto | :step,
  :opts => Keyword.t(),
  :orchestrator_pid => nil | pid(),
  :parent_pid => nil | pid(),
  :pending_signals => :queue.queue(_),
  :registry => atom(),
  :reply_refs => %{binary() => {pid(), _}},
  :router => %Jido.Signal.Router.Router{
    :route_count => non_neg_integer(),
    :trie => %Jido.Signal.Router.TrieNode{
      :handlers =>
        nil
        | %Jido.Signal.Router.NodeHandlers{
            :handlers => [
              %Jido.Signal.Router.HandlerInfo{
                :complexity => non_neg_integer(),
                :priority => non_neg_integer(),
                :target => _
              }
            ],
            :matchers => [
              %Jido.Signal.Router.PatternMatch{
                :complexity => non_neg_integer(),
                :match => (%Jido.Signal{
                             :data => _,
                             :datacontenttype => nil | binary(),
                             :dataschema => nil | binary(),
                             :id => binary(),
                             :jido_dispatch =>
                               nil | Keyword.t(Keyword.t()) | {atom(), Keyword.t()},
                             :source => binary(),
                             :specversion => binary(),
                             :subject => nil | binary(),
                             :time => nil | binary(),
                             :type => binary()
                           } ->
                             boolean()),
                :priority => non_neg_integer(),
                :target => _
              }
            ]
          },
      :segments => %{
        binary() => %Jido.Signal.Router.TrieNode{
          :handlers => nil | map(),
          :segments => map(),
          :wildcards => [any()],
          _ => _
        }
      },
      :wildcards => [
        %Jido.Signal.Router.WildcardHandlers{
          :handlers => %Jido.Signal.Router.NodeHandlers{
            :handlers => [
              %Jido.Signal.Router.HandlerInfo{
                :complexity => non_neg_integer(),
                :priority => non_neg_integer(),
                :target => _
              }
            ],
            :matchers => [
              %Jido.Signal.Router.PatternMatch{
                :complexity => non_neg_integer(),
                :match => (%Jido.Signal{
                             :data => _,
                             :datacontenttype => nil | binary(),
                             :dataschema => nil | binary(),
                             :id => binary(),
                             :jido_dispatch =>
                               nil | Keyword.t(Keyword.t()) | {atom(), Keyword.t()},
                             :source => binary(),
                             :specversion => binary(),
                             :subject => nil | binary(),
                             :time => nil | binary(),
                             :type => binary()
                           } ->
                             boolean()),
                :priority => non_neg_integer(),
                :target => _
              }
            ]
          },
          :type => :multi | :single
        }
      ]
    }
  },
  :skills => [
    %Jido.Skill{
      :category => nil | binary(),
      :description => nil | binary(),
      :name => binary(),
      :opts_key => atom(),
      :opts_schema => nil | map(),
      :signal_patterns => [binary()],
      :tags => [binary()],
      :vsn => nil | binary()
    }
  ],
  :status => :idle | :initializing | :paused | :planning | :running
}

Behaviour callback type:
%Jido.Agent{
  :actions => [atom()],
  :category => nil | binary(),
  :description => nil | binary(),
  :dirty_state? => boolean(),
  :id => nil | binary(),
  :name => nil | binary(),
  :pending_instructions => nil | :queue.queue(_),
  :result => _,
  :runner => atom(),
  :schema => nil | Keyword.t(),
  :state => map(),
  :tags => nil | [binary()],
  :vsn => nil | binary()
}

________________________________________________________________________________
lib/jido_system/agents/coordinator_agent.ex:63:invalid_contract
The @spec for the function does not match the success typing of the function.

Function:
JidoSystem.Agents.CoordinatorAgent.do_validate/3

Success typing:
@spec do_validate(t(), map(), :elixir.keyword()) :: map_result()

________________________________________________________________________________
lib/jido_system/agents/coordinator_agent.ex:63:extra_range
The type specification has too many types for the function.

Function:
JidoSystem.Agents.CoordinatorAgent.handle_signal/2

Extra type:
{:error, _}

Success typing:
{:ok, _}

________________________________________________________________________________
lib/jido_system/agents/coordinator_agent.ex:63:invalid_contract
The @spec for the function does not match the success typing of the function.

Function:
JidoSystem.Agents.CoordinatorAgent.on_error/2

Success typing:
@spec on_error(t(), any()) :: agent_result()

________________________________________________________________________________
lib/jido_system/agents/coordinator_agent.ex:63:invalid_contract
The @spec for the function does not match the success typing of the function.

Function:
JidoSystem.Agents.CoordinatorAgent.pending?/1

Success typing:
@spec pending?(t()) :: non_neg_integer()

________________________________________________________________________________
lib/jido_system/agents/coordinator_agent.ex:63:invalid_contract
The @spec for the function does not match the success typing of the function.

Function:
JidoSystem.Agents.CoordinatorAgent.reset/1

Success typing:
@spec reset(t()) :: agent_result()

________________________________________________________________________________
lib/jido_system/agents/coordinator_agent.ex:63:extra_range
The type specification has too many types for the function.

Function:
JidoSystem.Agents.CoordinatorAgent.transform_result/3

Extra type:
{:error, _}

Success typing:
{:ok, _}

________________________________________________________________________________
lib/jido_system/agents/coordinator_agent.ex:141:7:pattern_match_cov
The pattern
variable_error

can never match, because previous clauses completely cover the type
{:ok, _}.

________________________________________________________________________________
lib/jido_system/agents/coordinator_agent.ex:258:19:pattern_match
The pattern can never match the type.

Pattern:
{:ok, _task_result}

Type:
:ok | {:error, :delegation_failed}

________________________________________________________________________________
lib/jido_system/agents/coordinator_agent.ex:481:17:pattern_match
The pattern can never match the type.

Pattern:
{:ok, _result}

Type:
:ok | {:error, :delegation_failed}

________________________________________________________________________________
lib/jido_system/agents/coordinator_agent.ex:509:15:pattern_match
The pattern can never match the type.

Pattern:
:failed

Type:
:cancelled

________________________________________________________________________________
lib/jido_system/agents/coordinator_agent.ex:517:8:unused_fun
Function update_task_metrics/1 will never be called.
________________________________________________________________________________
lib/jido_system/agents/foundation_agent.ex:57:callback_type_mismatch
Type mismatch for @callback on_error/2 in Jido.Agent behaviour.

Expected type:

  {:error,
   %Jido.Agent{
     :actions => [atom()],
     :category => nil | binary(),
     :description => nil | binary(),
     :dirty_state? => boolean(),
     :id => nil | binary(),
     :name => nil | binary(),
     :pending_instructions => nil | :queue.queue(_),
     :result => _,
     :runner => atom(),
     :schema => nil | Keyword.t(),
     :state => map(),
     :tags => nil | [binary()],
     :vsn => nil | binary()
   }}
  | {:ok,
     %Jido.Agent{
       :actions => [atom()],
       :category => nil | binary(),
       :description => nil | binary(),
       :dirty_state? => boolean(),
       :id => nil | binary(),
       :name => nil | binary(),
       :pending_instructions => nil | :queue.queue(_),
       :result => _,
       :runner => atom(),
       :schema => nil | Keyword.t(),
       :state => map(),
       :tags => nil | [binary()],
       :vsn => nil | binary()
     }}


Actual type:
{:ok, %{:state => %{:status => :recovering, _ => _}, _ => _}, []}

________________________________________________________________________________
lib/jido_system/agents/foundation_agent.ex:63:callback_type_mismatch
Type mismatch for @callback on_error/2 in Jido.Agent behaviour.

Expected type:

  {:error,
   %Jido.Agent{
     :actions => [atom()],
     :category => nil | binary(),
     :description => nil | binary(),
     :dirty_state? => boolean(),
     :id => nil | binary(),
     :name => nil | binary(),
     :pending_instructions => nil | :queue.queue(_),
     :result => _,
     :runner => atom(),
     :schema => nil | Keyword.t(),
     :state => map(),
     :tags => nil | [binary()],
     :vsn => nil | binary()
   }}
  | {:ok,
     %Jido.Agent{
       :actions => [atom()],
       :category => nil | binary(),
       :description => nil | binary(),
       :dirty_state? => boolean(),
       :id => nil | binary(),
       :name => nil | binary(),
       :pending_instructions => nil | :queue.queue(_),
       :result => _,
       :runner => atom(),
       :schema => nil | Keyword.t(),
       :state => map(),
       :tags => nil | [binary()],
       :vsn => nil | binary()
     }}


Actual type:
{:ok, %{:state => %{:status => :recovering, _ => _}, _ => _}, []}

________________________________________________________________________________
lib/jido_system/agents/foundation_agent.ex:231:pattern_match
The pattern can never match the type.

Pattern:
JidoSystem.Agents.TaskAgent

Type:
JidoSystem.Agents.CoordinatorAgent

________________________________________________________________________________
lib/jido_system/agents/foundation_agent.ex:231:pattern_match
The pattern can never match the type.

Pattern:
JidoSystem.Agents.TaskAgent

Type:
JidoSystem.Agents.MonitorAgent

________________________________________________________________________________
lib/jido_system/agents/foundation_agent.ex:232:pattern_match
The pattern can never match the type.

Pattern:
JidoSystem.Agents.MonitorAgent

Type:
JidoSystem.Agents.CoordinatorAgent

________________________________________________________________________________
lib/jido_system/agents/foundation_agent.ex:232:pattern_match
The pattern can never match the type.

Pattern:
JidoSystem.Agents.MonitorAgent

Type:
JidoSystem.Agents.TaskAgent

________________________________________________________________________________
lib/jido_system/agents/foundation_agent.ex:233:pattern_match
The pattern can never match the type.

Pattern:
JidoSystem.Agents.CoordinatorAgent

Type:
JidoSystem.Agents.MonitorAgent

________________________________________________________________________________
lib/jido_system/agents/foundation_agent.ex:233:pattern_match
The pattern can never match the type.

Pattern:
JidoSystem.Agents.CoordinatorAgent

Type:
JidoSystem.Agents.TaskAgent

________________________________________________________________________________
lib/jido_system/agents/foundation_agent.ex:234:pattern_match_cov
The pattern
:variable_

can never match, because previous clauses completely cover the type
JidoSystem.Agents.CoordinatorAgent.

________________________________________________________________________________
lib/jido_system/agents/foundation_agent.ex:234:pattern_match_cov
The pattern
:variable_

can never match, because previous clauses completely cover the type
JidoSystem.Agents.MonitorAgent.

________________________________________________________________________________
lib/jido_system/agents/foundation_agent.ex:234:pattern_match_cov
The pattern
:variable_

can never match, because previous clauses completely cover the type
JidoSystem.Agents.TaskAgent.

________________________________________________________________________________
lib/jido_system/agents/monitor_agent.ex:57:callback_spec_arg_type_mismatch
The @spec type for the 1st argument is not a
supertype of the expected type for the mount/2 callback
in the Jido.Agent behaviour.

Success type:
%Jido.Agent.Server.State{
  :agent => %Jido.Agent{
    :actions => [atom()],
    :category => nil | binary(),
    :description => nil | binary(),
    :dirty_state? => boolean(),
    :id => nil | binary(),
    :name => nil | binary(),
    :pending_instructions => nil | :queue.queue(_),
    :result => _,
    :runner => atom(),
    :schema => nil | Keyword.t(),
    :state => map(),
    :tags => nil | [binary()],
    :vsn => nil | binary()
  },
  :child_supervisor => nil | pid(),
  :current_signal => %Jido.Signal{
    :data => _,
    :datacontenttype => nil | binary(),
    :dataschema => nil | binary(),
    :id => binary(),
    :jido_dispatch => nil | Keyword.t(Keyword.t()) | {atom(), Keyword.t()},
    :source => binary(),
    :specversion => binary(),
    :subject => nil | binary(),
    :time => nil | binary(),
    :type => binary()
  },
  :current_signal_type => atom(),
  :dispatch => [
    {:err, {atom(), Keyword.t()}}
    | {:log, {atom(), Keyword.t()}}
    | {:out, {atom(), Keyword.t()}}
  ],
  :journal => %Jido.Signal.Journal{:adapter => atom(), :adapter_pid => nil | pid()},
  :log_level =>
    :alert | :critical | :debug | :emergency | :error | :info | :notice | :warning,
  :max_queue_size => non_neg_integer(),
  :mode => :auto | :step,
  :opts => Keyword.t(),
  :orchestrator_pid => nil | pid(),
  :parent_pid => nil | pid(),
  :pending_signals => :queue.queue(_),
  :registry => atom(),
  :reply_refs => %{binary() => {pid(), _}},
  :router => %Jido.Signal.Router.Router{
    :route_count => non_neg_integer(),
    :trie => %Jido.Signal.Router.TrieNode{
      :handlers =>
        nil
        | %Jido.Signal.Router.NodeHandlers{
            :handlers => [
              %Jido.Signal.Router.HandlerInfo{
                :complexity => non_neg_integer(),
                :priority => non_neg_integer(),
                :target => _
              }
            ],
            :matchers => [
              %Jido.Signal.Router.PatternMatch{
                :complexity => non_neg_integer(),
                :match => (%Jido.Signal{
                             :data => _,
                             :datacontenttype => nil | binary(),
                             :dataschema => nil | binary(),
                             :id => binary(),
                             :jido_dispatch =>
                               nil | Keyword.t(Keyword.t()) | {atom(), Keyword.t()},
                             :source => binary(),
                             :specversion => binary(),
                             :subject => nil | binary(),
                             :time => nil | binary(),
                             :type => binary()
                           } ->
                             boolean()),
                :priority => non_neg_integer(),
                :target => _
              }
            ]
          },
      :segments => %{
        binary() => %Jido.Signal.Router.TrieNode{
          :handlers => nil | map(),
          :segments => map(),
          :wildcards => [any()],
          _ => _
        }
      },
      :wildcards => [
        %Jido.Signal.Router.WildcardHandlers{
          :handlers => %Jido.Signal.Router.NodeHandlers{
            :handlers => [
              %Jido.Signal.Router.HandlerInfo{
                :complexity => non_neg_integer(),
                :priority => non_neg_integer(),
                :target => _
              }
            ],
            :matchers => [
              %Jido.Signal.Router.PatternMatch{
                :complexity => non_neg_integer(),
                :match => (%Jido.Signal{
                             :data => _,
                             :datacontenttype => nil | binary(),
                             :dataschema => nil | binary(),
                             :id => binary(),
                             :jido_dispatch =>
                               nil | Keyword.t(Keyword.t()) | {atom(), Keyword.t()},
                             :source => binary(),
                             :specversion => binary(),
                             :subject => nil | binary(),
                             :time => nil | binary(),
                             :type => binary()
                           } ->
                             boolean()),
                :priority => non_neg_integer(),
                :target => _
              }
            ]
          },
          :type => :multi | :single
        }
      ]
    }
  },
  :skills => [
    %Jido.Skill{
      :category => nil | binary(),
      :description => nil | binary(),
      :name => binary(),
      :opts_key => atom(),
      :opts_schema => nil | map(),
      :signal_patterns => [binary()],
      :tags => [binary()],
      :vsn => nil | binary()
    }
  ],
  :status => :idle | :initializing | :paused | :planning | :running
}

Behaviour callback type:
%Jido.Agent{
  :actions => [atom()],
  :category => nil | binary(),
  :description => nil | binary(),
  :dirty_state? => boolean(),
  :id => nil | binary(),
  :name => nil | binary(),
  :pending_instructions => nil | :queue.queue(_),
  :result => _,
  :runner => atom(),
  :schema => nil | Keyword.t(),
  :state => map(),
  :tags => nil | [binary()],
  :vsn => nil | binary()
}

________________________________________________________________________________
lib/jido_system/agents/monitor_agent.ex:57:callback_spec_arg_type_mismatch
The @spec type for the 1st argument is not a
supertype of the expected type for the shutdown/2 callback
in the Jido.Agent behaviour.

Success type:
%Jido.Agent.Server.State{
  :agent => %Jido.Agent{
    :actions => [atom()],
    :category => nil | binary(),
    :description => nil | binary(),
    :dirty_state? => boolean(),
    :id => nil | binary(),
    :name => nil | binary(),
    :pending_instructions => nil | :queue.queue(_),
    :result => _,
    :runner => atom(),
    :schema => nil | Keyword.t(),
    :state => map(),
    :tags => nil | [binary()],
    :vsn => nil | binary()
  },
  :child_supervisor => nil | pid(),
  :current_signal => %Jido.Signal{
    :data => _,
    :datacontenttype => nil | binary(),
    :dataschema => nil | binary(),
    :id => binary(),
    :jido_dispatch => nil | Keyword.t(Keyword.t()) | {atom(), Keyword.t()},
    :source => binary(),
    :specversion => binary(),
    :subject => nil | binary(),
    :time => nil | binary(),
    :type => binary()
  },
  :current_signal_type => atom(),
  :dispatch => [
    {:err, {atom(), Keyword.t()}}
    | {:log, {atom(), Keyword.t()}}
    | {:out, {atom(), Keyword.t()}}
  ],
  :journal => %Jido.Signal.Journal{:adapter => atom(), :adapter_pid => nil | pid()},
  :log_level =>
    :alert | :critical | :debug | :emergency | :error | :info | :notice | :warning,
  :max_queue_size => non_neg_integer(),
  :mode => :auto | :step,
  :opts => Keyword.t(),
  :orchestrator_pid => nil | pid(),
  :parent_pid => nil | pid(),
  :pending_signals => :queue.queue(_),
  :registry => atom(),
  :reply_refs => %{binary() => {pid(), _}},
  :router => %Jido.Signal.Router.Router{
    :route_count => non_neg_integer(),
    :trie => %Jido.Signal.Router.TrieNode{
      :handlers =>
        nil
        | %Jido.Signal.Router.NodeHandlers{
            :handlers => [
              %Jido.Signal.Router.HandlerInfo{
                :complexity => non_neg_integer(),
                :priority => non_neg_integer(),
                :target => _
              }
            ],
            :matchers => [
              %Jido.Signal.Router.PatternMatch{
                :complexity => non_neg_integer(),
                :match => (%Jido.Signal{
                             :data => _,
                             :datacontenttype => nil | binary(),
                             :dataschema => nil | binary(),
                             :id => binary(),
                             :jido_dispatch =>
                               nil | Keyword.t(Keyword.t()) | {atom(), Keyword.t()},
                             :source => binary(),
                             :specversion => binary(),
                             :subject => nil | binary(),
                             :time => nil | binary(),
                             :type => binary()
                           } ->
                             boolean()),
                :priority => non_neg_integer(),
                :target => _
              }
            ]
          },
      :segments => %{
        binary() => %Jido.Signal.Router.TrieNode{
          :handlers => nil | map(),
          :segments => map(),
          :wildcards => [any()],
          _ => _
        }
      },
      :wildcards => [
        %Jido.Signal.Router.WildcardHandlers{
          :handlers => %Jido.Signal.Router.NodeHandlers{
            :handlers => [
              %Jido.Signal.Router.HandlerInfo{
                :complexity => non_neg_integer(),
                :priority => non_neg_integer(),
                :target => _
              }
            ],
            :matchers => [
              %Jido.Signal.Router.PatternMatch{
                :complexity => non_neg_integer(),
                :match => (%Jido.Signal{
                             :data => _,
                             :datacontenttype => nil | binary(),
                             :dataschema => nil | binary(),
                             :id => binary(),
                             :jido_dispatch =>
                               nil | Keyword.t(Keyword.t()) | {atom(), Keyword.t()},
                             :source => binary(),
                             :specversion => binary(),
                             :subject => nil | binary(),
                             :time => nil | binary(),
                             :type => binary()
                           } ->
                             boolean()),
                :priority => non_neg_integer(),
                :target => _
              }
            ]
          },
          :type => :multi | :single
        }
      ]
    }
  },
  :skills => [
    %Jido.Skill{
      :category => nil | binary(),
      :description => nil | binary(),
      :name => binary(),
      :opts_key => atom(),
      :opts_schema => nil | map(),
      :signal_patterns => [binary()],
      :tags => [binary()],
      :vsn => nil | binary()
    }
  ],
  :status => :idle | :initializing | :paused | :planning | :running
}

Behaviour callback type:
%Jido.Agent{
  :actions => [atom()],
  :category => nil | binary(),
  :description => nil | binary(),
  :dirty_state? => boolean(),
  :id => nil | binary(),
  :name => nil | binary(),
  :pending_instructions => nil | :queue.queue(_),
  :result => _,
  :runner => atom(),
  :schema => nil | Keyword.t(),
  :state => map(),
  :tags => nil | [binary()],
  :vsn => nil | binary()
}

________________________________________________________________________________
lib/jido_system/agents/monitor_agent.ex:57:invalid_contract
The @spec for the function does not match the success typing of the function.

Function:
JidoSystem.Agents.MonitorAgent.do_validate/3

Success typing:
@spec do_validate(t(), map(), :elixir.keyword()) :: map_result()

________________________________________________________________________________
lib/jido_system/agents/monitor_agent.ex:57:extra_range
The type specification has too many types for the function.

Function:
JidoSystem.Agents.MonitorAgent.handle_signal/2

Extra type:
{:error, _}

Success typing:
{:ok, _}

________________________________________________________________________________
lib/jido_system/agents/monitor_agent.ex:57:invalid_contract
The @spec for the function does not match the success typing of the function.

Function:
JidoSystem.Agents.MonitorAgent.on_error/2

Success typing:
@spec on_error(t(), any()) :: agent_result()

________________________________________________________________________________
lib/jido_system/agents/monitor_agent.ex:57:invalid_contract
The @spec for the function does not match the success typing of the function.

Function:
JidoSystem.Agents.MonitorAgent.pending?/1

Success typing:
@spec pending?(t()) :: non_neg_integer()

________________________________________________________________________________
lib/jido_system/agents/monitor_agent.ex:57:invalid_contract
The @spec for the function does not match the success typing of the function.

Function:
JidoSystem.Agents.MonitorAgent.reset/1

Success typing:
@spec reset(t()) :: agent_result()

________________________________________________________________________________
lib/jido_system/agents/monitor_agent.ex:57:extra_range
The type specification has too many types for the function.

Function:
JidoSystem.Agents.MonitorAgent.transform_result/3

Extra type:
{:error, _}

Success typing:
{:ok, _}

________________________________________________________________________________
lib/jido_system/agents/monitor_agent.ex:133:7:pattern_match_cov
The pattern
variable_error

can never match, because previous clauses completely cover the type
{:ok, _}.

________________________________________________________________________________
lib/jido_system/agents/monitor_agent.ex:364:41:unknown_function
Function :scheduler.utilization/1 does not exist.
________________________________________________________________________________
lib/jido_system/agents/monitor_agent.ex:370:46:no_return
The created anonymous function has no local return.
________________________________________________________________________________
lib/jido_system/agents/monitor_agent.ex:372:11:pattern_match
The pattern can never match the type.

Pattern:
[{_pid, _metadata}]

Type:
:error | {:ok, {pid(), map()}}

________________________________________________________________________________
lib/jido_system/agents/monitor_agent.ex:381:12:pattern_match
The pattern can never match the type.

Pattern:
[]

Type:
:error | {:ok, {pid(), map()}}

________________________________________________________________________________
lib/jido_system/agents/monitor_agent.ex:409:7:pattern_match_cov
The pattern
:variable_

can never match, because previous clauses completely cover the type
binary().

________________________________________________________________________________
lib/jido_system/agents/task_agent.ex:49:callback_spec_arg_type_mismatch
The @spec type for the 1st argument is not a
supertype of the expected type for the mount/2 callback
in the Jido.Agent behaviour.

Success type:
%Jido.Agent.Server.State{
  :agent => %Jido.Agent{
    :actions => [atom()],
    :category => nil | binary(),
    :description => nil | binary(),
    :dirty_state? => boolean(),
    :id => nil | binary(),
    :name => nil | binary(),
    :pending_instructions => nil | :queue.queue(_),
    :result => _,
    :runner => atom(),
    :schema => nil | Keyword.t(),
    :state => map(),
    :tags => nil | [binary()],
    :vsn => nil | binary()
  },
  :child_supervisor => nil | pid(),
  :current_signal => %Jido.Signal{
    :data => _,
    :datacontenttype => nil | binary(),
    :dataschema => nil | binary(),
    :id => binary(),
    :jido_dispatch => nil | Keyword.t(Keyword.t()) | {atom(), Keyword.t()},
    :source => binary(),
    :specversion => binary(),
    :subject => nil | binary(),
    :time => nil | binary(),
    :type => binary()
  },
  :current_signal_type => atom(),
  :dispatch => [
    {:err, {atom(), Keyword.t()}}
    | {:log, {atom(), Keyword.t()}}
    | {:out, {atom(), Keyword.t()}}
  ],
  :journal => %Jido.Signal.Journal{:adapter => atom(), :adapter_pid => nil | pid()},
  :log_level =>
    :alert | :critical | :debug | :emergency | :error | :info | :notice | :warning,
  :max_queue_size => non_neg_integer(),
  :mode => :auto | :step,
  :opts => Keyword.t(),
  :orchestrator_pid => nil | pid(),
  :parent_pid => nil | pid(),
  :pending_signals => :queue.queue(_),
  :registry => atom(),
  :reply_refs => %{binary() => {pid(), _}},
  :router => %Jido.Signal.Router.Router{
    :route_count => non_neg_integer(),
    :trie => %Jido.Signal.Router.TrieNode{
      :handlers =>
        nil
        | %Jido.Signal.Router.NodeHandlers{
            :handlers => [
              %Jido.Signal.Router.HandlerInfo{
                :complexity => non_neg_integer(),
                :priority => non_neg_integer(),
                :target => _
              }
            ],
            :matchers => [
              %Jido.Signal.Router.PatternMatch{
                :complexity => non_neg_integer(),
                :match => (%Jido.Signal{
                             :data => _,
                             :datacontenttype => nil | binary(),
                             :dataschema => nil | binary(),
                             :id => binary(),
                             :jido_dispatch =>
                               nil | Keyword.t(Keyword.t()) | {atom(), Keyword.t()},
                             :source => binary(),
                             :specversion => binary(),
                             :subject => nil | binary(),
                             :time => nil | binary(),
                             :type => binary()
                           } ->
                             boolean()),
                :priority => non_neg_integer(),
                :target => _
              }
            ]
          },
      :segments => %{
        binary() => %Jido.Signal.Router.TrieNode{
          :handlers => nil | map(),
          :segments => map(),
          :wildcards => [any()],
          _ => _
        }
      },
      :wildcards => [
        %Jido.Signal.Router.WildcardHandlers{
          :handlers => %Jido.Signal.Router.NodeHandlers{
            :handlers => [
              %Jido.Signal.Router.HandlerInfo{
                :complexity => non_neg_integer(),
                :priority => non_neg_integer(),
                :target => _
              }
            ],
            :matchers => [
              %Jido.Signal.Router.PatternMatch{
                :complexity => non_neg_integer(),
                :match => (%Jido.Signal{
                             :data => _,
                             :datacontenttype => nil | binary(),
                             :dataschema => nil | binary(),
                             :id => binary(),
                             :jido_dispatch =>
                               nil | Keyword.t(Keyword.t()) | {atom(), Keyword.t()},
                             :source => binary(),
                             :specversion => binary(),
                             :subject => nil | binary(),
                             :time => nil | binary(),
                             :type => binary()
                           } ->
                             boolean()),
                :priority => non_neg_integer(),
                :target => _
              }
            ]
          },
          :type => :multi | :single
        }
      ]
    }
  },
  :skills => [
    %Jido.Skill{
      :category => nil | binary(),
      :description => nil | binary(),
      :name => binary(),
      :opts_key => atom(),
      :opts_schema => nil | map(),
      :signal_patterns => [binary()],
      :tags => [binary()],
      :vsn => nil | binary()
    }
  ],
  :status => :idle | :initializing | :paused | :planning | :running
}

Behaviour callback type:
%Jido.Agent{
  :actions => [atom()],
  :category => nil | binary(),
  :description => nil | binary(),
  :dirty_state? => boolean(),
  :id => nil | binary(),
  :name => nil | binary(),
  :pending_instructions => nil | :queue.queue(_),
  :result => _,
  :runner => atom(),
  :schema => nil | Keyword.t(),
  :state => map(),
  :tags => nil | [binary()],
  :vsn => nil | binary()
}

________________________________________________________________________________
lib/jido_system/agents/task_agent.ex:49:callback_spec_arg_type_mismatch
The @spec type for the 1st argument is not a
supertype of the expected type for the shutdown/2 callback
in the Jido.Agent behaviour.

Success type:
%Jido.Agent.Server.State{
  :agent => %Jido.Agent{
    :actions => [atom()],
    :category => nil | binary(),
    :description => nil | binary(),
    :dirty_state? => boolean(),
    :id => nil | binary(),
    :name => nil | binary(),
    :pending_instructions => nil | :queue.queue(_),
    :result => _,
    :runner => atom(),
    :schema => nil | Keyword.t(),
    :state => map(),
    :tags => nil | [binary()],
    :vsn => nil | binary()
  },
  :child_supervisor => nil | pid(),
  :current_signal => %Jido.Signal{
    :data => _,
    :datacontenttype => nil | binary(),
    :dataschema => nil | binary(),
    :id => binary(),
    :jido_dispatch => nil | Keyword.t(Keyword.t()) | {atom(), Keyword.t()},
    :source => binary(),
    :specversion => binary(),
    :subject => nil | binary(),
    :time => nil | binary(),
    :type => binary()
  },
  :current_signal_type => atom(),
  :dispatch => [
    {:err, {atom(), Keyword.t()}}
    | {:log, {atom(), Keyword.t()}}
    | {:out, {atom(), Keyword.t()}}
  ],
  :journal => %Jido.Signal.Journal{:adapter => atom(), :adapter_pid => nil | pid()},
  :log_level =>
    :alert | :critical | :debug | :emergency | :error | :info | :notice | :warning,
  :max_queue_size => non_neg_integer(),
  :mode => :auto | :step,
  :opts => Keyword.t(),
  :orchestrator_pid => nil | pid(),
  :parent_pid => nil | pid(),
  :pending_signals => :queue.queue(_),
  :registry => atom(),
  :reply_refs => %{binary() => {pid(), _}},
  :router => %Jido.Signal.Router.Router{
    :route_count => non_neg_integer(),
    :trie => %Jido.Signal.Router.TrieNode{
      :handlers =>
        nil
        | %Jido.Signal.Router.NodeHandlers{
            :handlers => [
              %Jido.Signal.Router.HandlerInfo{
                :complexity => non_neg_integer(),
                :priority => non_neg_integer(),
                :target => _
              }
            ],
            :matchers => [
              %Jido.Signal.Router.PatternMatch{
                :complexity => non_neg_integer(),
                :match => (%Jido.Signal{
                             :data => _,
                             :datacontenttype => nil | binary(),
                             :dataschema => nil | binary(),
                             :id => binary(),
                             :jido_dispatch =>
                               nil | Keyword.t(Keyword.t()) | {atom(), Keyword.t()},
                             :source => binary(),
                             :specversion => binary(),
                             :subject => nil | binary(),
                             :time => nil | binary(),
                             :type => binary()
                           } ->
                             boolean()),
                :priority => non_neg_integer(),
                :target => _
              }
            ]
          },
      :segments => %{
        binary() => %Jido.Signal.Router.TrieNode{
          :handlers => nil | map(),
          :segments => map(),
          :wildcards => [any()],
          _ => _
        }
      },
      :wildcards => [
        %Jido.Signal.Router.WildcardHandlers{
          :handlers => %Jido.Signal.Router.NodeHandlers{
            :handlers => [
              %Jido.Signal.Router.HandlerInfo{
                :complexity => non_neg_integer(),
                :priority => non_neg_integer(),
                :target => _
              }
            ],
            :matchers => [
              %Jido.Signal.Router.PatternMatch{
                :complexity => non_neg_integer(),
                :match => (%Jido.Signal{
                             :data => _,
                             :datacontenttype => nil | binary(),
                             :dataschema => nil | binary(),
                             :id => binary(),
                             :jido_dispatch =>
                               nil | Keyword.t(Keyword.t()) | {atom(), Keyword.t()},
                             :source => binary(),
                             :specversion => binary(),
                             :subject => nil | binary(),
                             :time => nil | binary(),
                             :type => binary()
                           } ->
                             boolean()),
                :priority => non_neg_integer(),
                :target => _
              }
            ]
          },
          :type => :multi | :single
        }
      ]
    }
  },
  :skills => [
    %Jido.Skill{
      :category => nil | binary(),
      :description => nil | binary(),
      :name => binary(),
      :opts_key => atom(),
      :opts_schema => nil | map(),
      :signal_patterns => [binary()],
      :tags => [binary()],
      :vsn => nil | binary()
    }
  ],
  :status => :idle | :initializing | :paused | :planning | :running
}

Behaviour callback type:
%Jido.Agent{
  :actions => [atom()],
  :category => nil | binary(),
  :description => nil | binary(),
  :dirty_state? => boolean(),
  :id => nil | binary(),
  :name => nil | binary(),
  :pending_instructions => nil | :queue.queue(_),
  :result => _,
  :runner => atom(),
  :schema => nil | Keyword.t(),
  :state => map(),
  :tags => nil | [binary()],
  :vsn => nil | binary()
}

________________________________________________________________________________
lib/jido_system/agents/task_agent.ex:49:invalid_contract
The @spec for the function does not match the success typing of the function.

Function:
JidoSystem.Agents.TaskAgent.do_validate/3

Success typing:
@spec do_validate(t(), map(), :elixir.keyword()) :: map_result()

________________________________________________________________________________
lib/jido_system/agents/task_agent.ex:49:extra_range
The type specification has too many types for the function.

Function:
JidoSystem.Agents.TaskAgent.handle_signal/2

Extra type:
{:error, _}

Success typing:
{:ok, _}

________________________________________________________________________________
lib/jido_system/agents/task_agent.ex:49:invalid_contract
The @spec for the function does not match the success typing of the function.

Function:
JidoSystem.Agents.TaskAgent.on_error/2

Success typing:
@spec on_error(t(), any()) :: agent_result()

________________________________________________________________________________
lib/jido_system/agents/task_agent.ex:49:invalid_contract
The @spec for the function does not match the success typing of the function.

Function:
JidoSystem.Agents.TaskAgent.pending?/1

Success typing:
@spec pending?(t()) :: non_neg_integer()

________________________________________________________________________________
lib/jido_system/agents/task_agent.ex:49:invalid_contract
The @spec for the function does not match the success typing of the function.

Function:
JidoSystem.Agents.TaskAgent.reset/1

Success typing:
@spec reset(t()) :: agent_result()

________________________________________________________________________________
lib/jido_system/agents/task_agent.ex:49:extra_range
The type specification has too many types for the function.

Function:
JidoSystem.Agents.TaskAgent.transform_result/3

Extra type:
{:error, _}

Success typing:
{:ok, _}

________________________________________________________________________________
lib/jido_system/agents/task_agent.ex:113:7:pattern_match_cov
The pattern
variable_error

can never match, because previous clauses completely cover the type
{:ok, _}.

________________________________________________________________________________
lib/jido_system/agents/task_agent.ex:187:7:pattern_match_cov
The pattern
variable_error

can never match, because previous clauses completely cover the type
{:ok, _}.

________________________________________________________________________________
lib/jido_system/agents/task_agent.ex:193:7:callback_type_mismatch
Type mismatch for @callback on_error/2 in Jido.Agent behaviour.

Expected type:

  {:error,
   %Jido.Agent{
     :actions => [atom()],
     :category => nil | binary(),
     :description => nil | binary(),
     :dirty_state? => boolean(),
     :id => nil | binary(),
     :name => nil | binary(),
     :pending_instructions => nil | :queue.queue(_),
     :result => _,
     :runner => atom(),
     :schema => nil | Keyword.t(),
     :state => map(),
     :tags => nil | [binary()],
     :vsn => nil | binary()
   }}
  | {:ok,
     %Jido.Agent{
       :actions => [atom()],
       :category => nil | binary(),
       :description => nil | binary(),
       :dirty_state? => boolean(),
       :id => nil | binary(),
       :name => nil | binary(),
       :pending_instructions => nil | :queue.queue(_),
       :result => _,
       :runner => atom(),
       :schema => nil | Keyword.t(),
       :state => map(),
       :tags => nil | [binary()],
       :vsn => nil | binary()
     }}


Actual type:

  {:ok,
   %{
     :state => %{
       :current_task => nil,
       :error_count => _,
       :status => :idle | :paused | :recovering,
       _ => _
     },
     _ => _
   }, []}


________________________________________________________________________________
lib/jido_system/agents/task_agent.ex:229:7:pattern_match_cov
The pattern
variable_error

can never match, because previous clauses completely cover the type
{:ok, %{:state => %{:status => :recovering, _ => _}, _ => _}, []}.

________________________________________________________________________________
lib/jido_system/sensors/agent_performance_sensor.ex:32:contract_supertype
Type specification is a supertype of the success typing.

Function:
JidoSystem.Sensors.AgentPerformanceSensor.__sensor_metadata__/0

Type specification:
@spec __sensor_metadata__() :: map()

Success typing:
@spec __sensor_metadata__() :: %{:category => _, :description => _, :name => _, :schema => _, :tags => _, :vsn => _}

________________________________________________________________________________
lib/jido_system/sensors/agent_performance_sensor.ex:32:invalid_contract
The @spec for the function does not match the success typing of the function.

Function:
JidoSystem.Sensors.AgentPerformanceSensor.deliver_signal/1

Success typing:
@spec deliver_signal(map()) :: {:ok, Jido.Signal.t()} | {:error, any()}

________________________________________________________________________________
lib/jido_system/sensors/agent_performance_sensor.ex:32:extra_range
The type specification has too many types for the function.

Function:
JidoSystem.Sensors.AgentPerformanceSensor.mount/1

Extra type:
{:error, _}

Success typing:

  {:ok,
   %{
     :agent_metrics => %{},
     :last_analysis => %DateTime{
       :calendar => atom(),
       :day => pos_integer(),
       :hour => non_neg_integer(),
       :microsecond => {_, _},
       :minute => non_neg_integer(),
       :month => pos_integer(),
       :second => non_neg_integer(),
       :std_offset => integer(),
       :time_zone => binary(),
       :utc_offset => integer(),
       :year => integer(),
       :zone_abbr => binary()
     },
     :optimization_suggestions => %{},
     :performance_history => %{},
     :started_at => %DateTime{
       :calendar => atom(),
       :day => pos_integer(),
       :hour => non_neg_integer(),
       :microsecond => {_, _},
       :minute => non_neg_integer(),
       :month => pos_integer(),
       :second => non_neg_integer(),
       :std_offset => integer(),
       :time_zone => binary(),
       :utc_offset => integer(),
       :year => integer(),
       :zone_abbr => binary()
     },
     :monitoring_interval => non_neg_integer(),
     _ => _
   }}


________________________________________________________________________________
lib/jido_system/sensors/agent_performance_sensor.ex:32:extra_range
The type specification has too many types for the function.

Function:
JidoSystem.Sensors.AgentPerformanceSensor.on_before_deliver/2

Extra type:
{:error, _}

Success typing:
{:ok, _}

________________________________________________________________________________
lib/jido_system/sensors/agent_performance_sensor.ex:32:unknown_type
Unknown type: Jido.Sensor.sensor_result/0.
________________________________________________________________________________
lib/jido_system/sensors/agent_performance_sensor.ex:32:extra_range
The type specification has too many types for the function.

Function:
JidoSystem.Sensors.AgentPerformanceSensor.shutdown/1

Extra type:
{:error, _}

Success typing:
{:ok, _}

________________________________________________________________________________
lib/jido_system/sensors/agent_performance_sensor.ex:32:contract_supertype
Type specification is a supertype of the success typing.

Function:
JidoSystem.Sensors.AgentPerformanceSensor.to_json/0

Type specification:
@spec to_json() :: map()

Success typing:
@spec to_json() :: %{:category => _, :description => _, :name => _, :schema => _, :tags => _, :vsn => _}

________________________________________________________________________________
lib/jido_system/sensors/agent_performance_sensor.ex:81:7:callback_type_mismatch
Type mismatch for @callback deliver_signal/1 in Jido.Sensor behaviour.

Expected type:

  {:error, _}
  | {:ok,
     %Jido.Signal{
       :data => _,
       :datacontenttype => nil | binary(),
       :dataschema => nil | binary(),
       :id => binary(),
       :jido_dispatch => nil | Keyword.t(Keyword.t()) | {atom(), Keyword.t()},
       :source => binary(),
       :specversion => binary(),
       :subject => nil | binary(),
       :time => nil | binary(),
       :type => binary()
     }}


Actual type:

  {:ok,
   {:error, <<_::64, _::size(8)>>}
   | {:ok,
      %Jido.Signal{
        :data => _,
        :datacontenttype => nil | binary(),
        :dataschema => nil | binary(),
        :id => binary(),
        :jido_dispatch => nil | [any()] | {_, _},
        :source => binary(),
        :specversion => <<_::40>>,
        :subject => nil | binary(),
        :time => nil | binary(),
        :type => binary()
      }}, _}


________________________________________________________________________________
lib/jido_system/sensors/agent_performance_sensor.ex:169:35:call_to_missing
Call to missing or private function Foundation.Registry.select/2.
________________________________________________________________________________
lib/jido_system/sensors/agent_performance_sensor.ex:636:39:call
The function call will not succeed.

Jido.Signal.Dispatch.dispatch(
  _signal ::
    {:error, <<_::64, _::size(8)>>}
    | {:ok,
       %Jido.Signal{
         :data => _,
         :datacontenttype => nil | binary(),
         :dataschema => nil | binary(),
         :id => binary(),
         :jido_dispatch => nil | [any()] | {_, _},
         :source => binary(),
         :specversion => <<_::40>>,
         :subject => nil | binary(),
         :time => nil | binary(),
         :type => binary()
       }},
  any()
)

breaks the contract
(Jido.Signal.t(), dispatch_configs()) :: :ok | {:error, term()}

________________________________________________________________________________
lib/jido_system/sensors/agent_performance_sensor.ex:639:16:pattern_match
The pattern can never match the type.

Pattern:
{:error, _reason}

Type:

  {:ok,
   {:error, <<_::64, _::size(8)>>}
   | {:ok,
      %Jido.Signal{
        :data => _,
        :datacontenttype => nil | binary(),
        :dataschema => nil | binary(),
        :id => binary(),
        :jido_dispatch => nil | [any()] | {_, _},
        :source => binary(),
        :specversion => <<_::40>>,
        :subject => nil | binary(),
        :time => nil | binary(),
        :type => binary()
      }}, _}


________________________________________________________________________________
lib/jido_system/sensors/system_health_sensor.ex:49:contract_supertype
Type specification is a supertype of the success typing.

Function:
JidoSystem.Sensors.SystemHealthSensor.__sensor_metadata__/0

Type specification:
@spec __sensor_metadata__() :: map()

Success typing:
@spec __sensor_metadata__() :: %{:category => _, :description => _, :name => _, :schema => _, :tags => _, :vsn => _}

________________________________________________________________________________
lib/jido_system/sensors/system_health_sensor.ex:49:invalid_contract
The @spec for the function does not match the success typing of the function.

Function:
JidoSystem.Sensors.SystemHealthSensor.deliver_signal/1

Success typing:
@spec deliver_signal(map()) :: {:ok, Jido.Signal.t()} | {:error, any()}

________________________________________________________________________________
lib/jido_system/sensors/system_health_sensor.ex:49:extra_range
The type specification has too many types for the function.

Function:
JidoSystem.Sensors.SystemHealthSensor.mount/1

Extra type:
{:error, _}

Success typing:

  {:ok,
   %{
     :alert_cooldown => _,
     :baseline_metrics => %{},
     :collection_count => 0,
     :collection_interval => non_neg_integer(),
     :enable_anomaly_detection => _,
     :history_size => _,
     :last_alerts => %{},
     :last_metrics => %{},
     :metrics_history => [],
     :started_at => %DateTime{
       :calendar => atom(),
       :day => pos_integer(),
       :hour => non_neg_integer(),
       :microsecond => {_, _},
       :minute => non_neg_integer(),
       :month => pos_integer(),
       :second => non_neg_integer(),
       :std_offset => integer(),
       :time_zone => binary(),
       :utc_offset => integer(),
       :year => integer(),
       :zone_abbr => binary()
     },
     :thresholds => _,
     _ => _
   }}


________________________________________________________________________________
lib/jido_system/sensors/system_health_sensor.ex:49:extra_range
The type specification has too many types for the function.

Function:
JidoSystem.Sensors.SystemHealthSensor.on_before_deliver/2

Extra type:
{:error, _}

Success typing:

  {:ok,
   %{
     :data => %{
       :collection_count => _,
       :sensor_id => _,
       :sensor_uptime => integer(),
       _ => _
     },
     _ => _
   }}


________________________________________________________________________________
lib/jido_system/sensors/system_health_sensor.ex:49:unknown_type
Unknown type: Jido.Sensor.sensor_result/0.
________________________________________________________________________________
lib/jido_system/sensors/system_health_sensor.ex:49:extra_range
The type specification has too many types for the function.

Function:
JidoSystem.Sensors.SystemHealthSensor.shutdown/1

Extra type:
{:error, _}

Success typing:
{:ok, _}

________________________________________________________________________________
lib/jido_system/sensors/system_health_sensor.ex:49:contract_supertype
Type specification is a supertype of the success typing.

Function:
JidoSystem.Sensors.SystemHealthSensor.to_json/0

Type specification:
@spec to_json() :: map()

Success typing:
@spec to_json() :: %{:category => _, :description => _, :name => _, :schema => _, :tags => _, :vsn => _}

________________________________________________________________________________
lib/jido_system/sensors/system_health_sensor.ex:113:7:callback_type_mismatch
Type mismatch for @callback deliver_signal/1 in Jido.Sensor behaviour.

Expected type:

  {:error, _}
  | {:ok,
     %Jido.Signal{
       :data => _,
       :datacontenttype => nil | binary(),
       :dataschema => nil | binary(),
       :id => binary(),
       :jido_dispatch => nil | Keyword.t(Keyword.t()) | {atom(), Keyword.t()},
       :source => binary(),
       :specversion => binary(),
       :subject => nil | binary(),
       :time => nil | binary(),
       :type => binary()
     }}


Actual type:

  {:ok,
   {:error, <<_::64, _::size(8)>>}
   | {:ok,
      %Jido.Signal{
        :data => _,
        :datacontenttype => nil | binary(),
        :dataschema => nil | binary(),
        :id => binary(),
        :jido_dispatch => nil | [any()] | {_, _},
        :source => binary(),
        :specversion => <<_::40>>,
        :subject => nil | binary(),
        :time => nil | binary(),
        :type => binary()
      }}
   | %Jido.Signal{
       :data => _,
       :datacontenttype => nil | binary(),
       :dataschema => nil | binary(),
       :id => binary(),
       :jido_dispatch => nil | [{_, _}] | {atom(), [any()]},
       :source => binary(),
       :specversion => <<_::40>>,
       :subject => nil | binary(),
       :time => nil | binary(),
       :type => binary()
     }, _}


________________________________________________________________________________
lib/jido_system/sensors/system_health_sensor.ex:283:9:pattern_match_cov
The pattern
:variable_

can never match, because previous clauses completely cover the type
binary().

________________________________________________________________________________
lib/jido_system/sensors/system_health_sensor.ex:340:18:unknown_function
Function :scheduler.utilization/1 does not exist.
________________________________________________________________________________
lib/jido_system/sensors/system_health_sensor.ex:624:16:pattern_match
The pattern can never match the type.

Pattern:
{:error, _reason}

Type:

  {:ok,
   {:error, <<_::64, _::size(8)>>}
   | {:ok,
      %Jido.Signal{
        :data => _,
        :datacontenttype => nil | binary(),
        :dataschema => nil | binary(),
        :id => binary(),
        :jido_dispatch => nil | [any()] | {_, _},
        :source => binary(),
        :specversion => <<_::40>>,
        :subject => nil | binary(),
        :time => nil | binary(),
        :type => binary()
      }}
   | %Jido.Signal{
       :data => _,
       :datacontenttype => nil | binary(),
       :dataschema => nil | binary(),
       :id => binary(),
       :jido_dispatch => nil | [{_, _}] | {atom(), [any()]},
       :source => binary(),
       :specversion => <<_::40>>,
       :subject => nil | binary(),
       :time => nil | binary(),
       :type => binary()
     }, _}


________________________________________________________________________________
done (warnings were emitted)
Halting VM with exit status 2
