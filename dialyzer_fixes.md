# Dialyzer Structural Fixes

## 1. Fix Pattern Match in foundation_agent.ex

**Issue**: Lines 239-242 use `__MODULE__` which is always `JidoSystem.Agents.FoundationAgent` at compile time, making the pattern matches unreachable.

**Current Code**:
```elixir
module_name = __MODULE__ |> to_string() |> String.split(".") |> List.last()

case module_name do
  "TaskAgent" -> [:task_processing, :validation, :queue_management]
  "MonitorAgent" -> [:monitoring, :alerting, :health_analysis] 
  "CoordinatorAgent" -> [:coordination, :orchestration, :workflow_management]
  _ -> [:general_purpose]
end
```

**Fix**: Pass the actual module as a parameter or use runtime module detection:

```elixir
# Option 1: Pass module explicitly
defp get_default_capabilities(module) do
  module_name = module |> to_string() |> String.split(".") |> List.last()
  
  case module_name do
    "TaskAgent" -> [:task_processing, :validation, :queue_management]
    "MonitorAgent" -> [:monitoring, :alerting, :health_analysis]
    "CoordinatorAgent" -> [:coordination, :orchestration, :workflow_management]
    _ -> [:general_purpose]
  end
end

# Option 2: Use agent.module field
defp get_default_capabilities(agent) do
  module_name = agent.module |> to_string() |> String.split(".") |> List.last()
  # ... rest of the code
end
```

## 2. Fix Unreachable Pattern in jido_system.ex

**Issue**: Lines 195 and 316 have pattern matches that can never succeed.

**Line 195**:
```elixir
{:error, {:task_failed, _reason}} ->
  {:error, "Task processing failed"}
```

**Analysis**: Need to check what `process_task/3` actually returns.

**Line 316**:
```elixir
{:error, {:workflow_failed, _reason}} ->
  {:error, "Workflow execution failed"}
```

**Analysis**: Need to check what `execute_workflow/3` actually returns.

## 3. Remove Unused Function

**Issue**: `validate_scheduler_data/1` at line 583 in system_health_sensor.ex is never called.

**Fix**: Simply remove the function if it's truly unused, or add a call to it if it should be used.

## 4. Fix Circuit Breaker Type Mismatch

**Issue**: Circuit breaker expects specific config format but receives different types.

**Fix**: Add type conversion or accept both formats:

```elixir
defp build_circuit_config(config, default_config) when is_list(config) do
  config_map = Enum.into(config, %{})
  build_circuit_config(config_map, default_config)
end

defp build_circuit_config(config, default_config) when is_map(config) do
  %CircuitConfig{
    failure_threshold: Map.get(config, :failure_threshold, default_config.failure_threshold),
    # ... rest of fields
  }
end
```

## Recommended Dialyzer Ignore File

Create `.dialyzer.ignore.exs`:

```elixir
[
  # Jido.Agent callback mismatches - unfixable without changing Jido
  {":0:unknown_type Unknown type: Jido.Sensor.sensor_result/0."},
  {"lib/jido_system/agents/task_agent.ex:49:callback_spec_arg_type_mismatch"},
  {"lib/jido_system/agents/monitor_agent.ex:57:callback_spec_arg_type_mismatch"},
  {"lib/jido_system/agents/coordinator_agent.ex:63:callback_spec_arg_type_mismatch"},
  
  # Pattern coverage warnings for defensive programming
  {"pattern_match_cov The pattern variable _error"},
  
  # Jido internal issues
  {"deps/jido/lib/jido/agent.ex"},
  
  # Auto-generated specs from macros
  {"extra_range @spec for handle_signal has more types"},
  {"invalid_contract Invalid type specification for function do_validate"},
  {"invalid_contract Invalid type specification for function on_error"},
  {"invalid_contract Invalid type specification for function pending?"},
  {"invalid_contract Invalid type specification for function reset"}
]
```

This will suppress the unfixable warnings while keeping dialyzer useful for catching real issues.