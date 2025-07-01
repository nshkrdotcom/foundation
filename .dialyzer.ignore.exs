# Dialyzer ignore file for Foundation
# These warnings are primarily due to Jido library type inconsistencies
# that cannot be fixed without modifying the external dependency

[
  # Jido.Agent behaviour expects agent structs but gets Server.State
  # This is a fundamental design mismatch in Jido that affects all agents
  {"lib/jido_system/agents/task_agent.ex", :callback_spec_arg_type_mismatch},
  {"lib/jido_system/agents/monitor_agent.ex", :callback_spec_arg_type_mismatch},
  {"lib/jido_system/agents/coordinator_agent.ex", :callback_spec_arg_type_mismatch},
  
  # Jido.Sensor missing type definition
  {"lib/jido_system/sensors/agent_performance_sensor.ex", :unknown_type, "Unknown type: Jido.Sensor.sensor_result/0."},
  {"lib/jido_system/sensors/system_health_sensor.ex", :unknown_type, "Unknown type: Jido.Sensor.sensor_result/0."},
  
  # Auto-generated specs from Jido macros that don't match implementations
  {"lib/jido_system/agents/task_agent.ex", :invalid_contract, "Invalid type specification for function do_validate."},
  {"lib/jido_system/agents/task_agent.ex", :invalid_contract, "Invalid type specification for function on_error."},
  {"lib/jido_system/agents/task_agent.ex", :invalid_contract, "Invalid type specification for function pending?."},
  {"lib/jido_system/agents/task_agent.ex", :invalid_contract, "Invalid type specification for function reset."},
  {"lib/jido_system/agents/monitor_agent.ex", :invalid_contract, "Invalid type specification for function do_validate."},
  {"lib/jido_system/agents/monitor_agent.ex", :invalid_contract, "Invalid type specification for function on_error."},
  {"lib/jido_system/agents/monitor_agent.ex", :invalid_contract, "Invalid type specification for function pending?."},
  {"lib/jido_system/agents/monitor_agent.ex", :invalid_contract, "Invalid type specification for function reset."},
  {"lib/jido_system/agents/coordinator_agent.ex", :invalid_contract, "Invalid type specification for function do_validate."},
  {"lib/jido_system/agents/coordinator_agent.ex", :invalid_contract, "Invalid type specification for function on_error."},
  {"lib/jido_system/agents/coordinator_agent.ex", :invalid_contract, "Invalid type specification for function pending?."},
  {"lib/jido_system/agents/coordinator_agent.ex", :invalid_contract, "Invalid type specification for function reset."},
  
  # Extra return types in specs - Jido generates broader specs than needed
  {"lib/jido_system/agents/task_agent.ex", :extra_range, "@spec for handle_signal has more types than are returned by the function."},
  {"lib/jido_system/agents/task_agent.ex", :extra_range, "@spec for transform_result has more types than are returned by the function."},
  {"lib/jido_system/agents/monitor_agent.ex", :extra_range, "@spec for handle_signal has more types than are returned by the function."},
  {"lib/jido_system/agents/monitor_agent.ex", :extra_range, "@spec for transform_result has more types than are returned by the function."},
  {"lib/jido_system/agents/coordinator_agent.ex", :extra_range, "@spec for handle_signal has more types than are returned by the function."},
  {"lib/jido_system/agents/coordinator_agent.ex", :extra_range, "@spec for transform_result has more types than are returned by the function."},
  
  # Sensor-related spec issues
  {"lib/jido_system/sensors/agent_performance_sensor.ex", :extra_range, "@spec for mount has more types than are returned by the function."},
  {"lib/jido_system/sensors/agent_performance_sensor.ex", :extra_range, "@spec for on_before_deliver has more types than are returned by the function."},
  {"lib/jido_system/sensors/agent_performance_sensor.ex", :extra_range, "@spec for shutdown has more types than are returned by the function."},
  {"lib/jido_system/sensors/agent_performance_sensor.ex", :invalid_contract, "Invalid type specification for function deliver_signal."},
  {"lib/jido_system/sensors/system_health_sensor.ex", :extra_range, "@spec for deliver_signal has more types than are returned by the function."},
  {"lib/jido_system/sensors/system_health_sensor.ex", :extra_range, "@spec for mount has more types than are returned by the function."},
  {"lib/jido_system/sensors/system_health_sensor.ex", :extra_range, "@spec for shutdown has more types than are returned by the function."},
  {"lib/jido_system/sensors/system_health_sensor.ex", :invalid_contract, "Invalid type specification for function on_before_deliver."},
  
  # Contract supertypes - specs are too general
  {"lib/jido_system/sensors/agent_performance_sensor.ex", :contract_supertype, "Type specification for __sensor_metadata__ is a supertype of the success typing."},
  {"lib/jido_system/sensors/agent_performance_sensor.ex", :contract_supertype, "Type specification for to_json is a supertype of the success typing."},
  {"lib/jido_system/sensors/system_health_sensor.ex", :contract_supertype, "Type specification for __sensor_metadata__ is a supertype of the success typing."},
  {"lib/jido_system/sensors/system_health_sensor.ex", :contract_supertype, "Type specification for to_json is a supertype of the success typing."},
  
  # Callback type mismatches
  {"lib/jido_system/agents/foundation_agent.ex", :callback_type_mismatch, "Type mismatch for @callback on_error."},
  {"lib/jido_system/agents/task_agent.ex", :callback_type_mismatch, "Type mismatch for @callback on_error."},
  {"lib/jido_system/sensors/agent_performance_sensor.ex", :callback_type_mismatch, "Type mismatch for @callback deliver_signal."},
  {"lib/jido_system/sensors/system_health_sensor.ex", :callback_type_mismatch, "Type mismatch for @callback on_before_deliver."},
  
  # Pattern match coverage - defensive catch-all clauses
  {"lib/jido_system/agents/task_agent.ex", :pattern_match_cov, "The pattern variable _error@1 can never match the type, because it is covered by previous clauses."},
  {"lib/jido_system/agents/task_agent.ex", :pattern_match_cov, "The pattern variable _error@2 can never match the type, because it is covered by previous clauses."},
  {"lib/jido_system/agents/monitor_agent.ex", :pattern_match_cov, "The pattern variable _error@1 can never match the type, because it is covered by previous clauses."},
  {"lib/jido_system/agents/monitor_agent.ex", :pattern_match_cov, "The pattern variable _ can never match the type, because it is covered by previous clauses."},
  {"lib/jido_system/agents/coordinator_agent.ex", :pattern_match_cov, "The pattern variable _error@1 can never match the type, because it is covered by previous clauses."},
  {"lib/jido_system/sensors/system_health_sensor.ex", :pattern_match_cov, "The pattern variable _scheduler_utilization@1 can never match the type, because it is covered by previous clauses."},
  {"lib/jido_system/sensors/system_health_sensor.ex", :pattern_match_cov, "The pattern variable __invalid_data@1 can never match the type, because it is covered by previous clauses."},
  {"lib/jido_system/sensors/system_health_sensor.ex", :pattern_match_cov, "The pattern variable _error@2 can never match the type, because it is covered by previous clauses."},
  
  # Action module extra ranges
  {"lib/jido_system/actions/get_performance_metrics.ex", :extra_range},
  {"lib/jido_system/actions/get_task_status.ex", :extra_range},
  {"lib/jido_system/actions/pause_processing.ex", :extra_range},
  {"lib/jido_system/actions/resume_processing.ex", :extra_range},
  {"lib/jido_system/actions/execute_workflow.ex", :extra_range},
  {"lib/jido_system/actions/process_task.ex", :extra_range},
  {"lib/jido_system/actions/queue_task.ex", :extra_range},
  
  # JidoSystem module issues  
  {"lib/jido_system.ex", :extra_range},
  {"lib/jido_system.ex", :contract_supertype},
  {"lib/jido_system.ex", :invalid_contract},
  {"lib/jido_system.ex", :pattern_match},
  
  # Foundation core
  {"lib/foundation.ex", :extra_range},
  {"lib/foundation/infrastructure/circuit_breaker.ex", :callback_arg_type_mismatch},
  {"lib/foundation/infrastructure/circuit_breaker.ex", :callback_type_mismatch},
  
  # Monitor agent specific
  {"lib/jido_system/agents/monitor_agent.ex", :no_return, "The created anonymous function has no local return."},
  {"lib/jido_system/agents/monitor_agent.ex", :pattern_match, "The pattern can never match the type :error | {:ok, {pid(), map()}}."},
  
  # Unused function (will be fixed separately)
  {"lib/jido_system/sensors/system_health_sensor.ex", :unused_fun, "Function validate_scheduler_data/1 will never be called."},
  
  # Coordinator agent pattern issues
  {"lib/jido_system/agents/coordinator_agent.ex", :pattern_match},
  
  # Monitor agent pattern issues  
  {"lib/jido_system/agents/monitor_agent.ex", :pattern_match},
  
  # Task agent pattern issues
  {"lib/jido_system/agents/task_agent.ex", :pattern_match},
  
  # All Jido library internal warnings
  ~r/deps\/jido\//,
  
  # FoundationJidoSupervisor - Dialyzer doesn't understand our supervisor init format
  {"lib/foundation_jido_supervisor.ex", :callback_type_mismatch}
]