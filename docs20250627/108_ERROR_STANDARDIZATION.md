# Foundation OS Error Standardization
**Version 1.0 - Unified Error Handling Across All Components**  
**Date: June 27, 2025**

## Executive Summary

This document defines the comprehensive error standardization strategy for Foundation OS, establishing `Foundation.Types.Error` as the single canonical error structure across all system layers. The standardization eliminates error handling inconsistencies, improves debugging capabilities, and enables unified telemetry and monitoring.

**Current Problem**: Multiple error systems across Foundation, MABEAM, Jido libraries, and DSPEx  
**Target Solution**: Single, comprehensive error system with automatic conversion and telemetry  
**Migration Strategy**: Incremental conversion with backward compatibility during transition

## Current Error System Analysis

### Existing Error Systems

Based on historical docs analysis, we currently have multiple error handling approaches:

1. **Foundation.Types.Error**: Basic error structure 
2. **Foundation.Types.EnhancedError**: Extended error with chains and context (to be merged per doc 013)
3. **Jido Library Errors**: Various error formats in jido, jido_action, jido_signal
4. **DSPEx/ElixirML Errors**: ML-specific error handling
5. **Ad-hoc Error Handling**: Inconsistent patterns throughout codebase

### Problems with Current Approach

- **Inconsistent Error Formats**: Different layers use different error structures
- **Lost Context**: Error context and debugging information varies by layer
- **Difficult Telemetry**: Cannot aggregate errors across systems effectively
- **Poor Developer Experience**: Different error handling patterns in different areas
- **Limited Traceability**: Cannot trace errors across layer boundaries

---

## Canonical Error System Design

### Foundation.Types.Error (Enhanced)

Building on the API contract from doc 107, here's the complete canonical error system:

```elixir
defmodule Foundation.Types.Error do
  @moduledoc """
  Canonical error structure for the entire Foundation OS platform.
  Consolidates all error handling into a single, comprehensive system.
  """
  
  # Error categories (expanded from API contract)
  @type category :: 
    # Core system errors
    :validation | :authentication | :authorization | :network | 
    :timeout | :not_found | :conflict | :internal | :external |
    
    # Agent system errors  
    :agent_management | :agent_communication | :agent_lifecycle |
    
    # Coordination errors
    :coordination | :auction | :consensus | :negotiation | :market |
    
    # ML/DSPEx errors
    :ml_processing | :optimization | :variable_conflict | :model_error |
    
    # Infrastructure errors
    :circuit_breaker | :rate_limit | :resource_exhausted | :service_unavailable |
    
    # Signal/Communication errors
    :signal_dispatch | :message_routing | :serialization | :deserialization
  
  @type severity :: :debug | :info | :warning | :error | :critical
  
  @type error_code :: atom()
  
  @type context :: %{
    # Core debugging context
    module: module(),
    function: atom(),
    line: non_neg_integer(),
    
    # Request tracing
    request_id: String.t() | nil,
    trace_id: String.t() | nil,
    span_id: String.t() | nil,
    
    # User/session context
    user_id: String.t() | nil,
    session_id: String.t() | nil,
    
    # System context
    node: atom(),
    process_id: String.t(),
    
    # Custom context
    additional: map()
  }
  
  @type retry_info :: %{
    attempt: pos_integer(),
    max_attempts: pos_integer(),
    next_retry_at: DateTime.t() | nil,
    backoff_strategy: :linear | :exponential | :custom
  }
  
  @type t :: %__MODULE__{
    # Core error information
    category: category(),
    code: error_code(),
    message: String.t(),
    details: map(),
    severity: severity(),
    
    # Context and tracing
    context: context(),
    caused_by: t() | nil,
    error_chain: [t()],
    
    # Temporal information
    timestamp: DateTime.t(),
    
    # Retry and recovery
    retry_info: retry_info() | nil,
    recoverable: boolean(),
    
    # Telemetry and monitoring
    tags: [atom()],
    metrics: map()
  }
  
  defstruct [
    :category, :code, :message, :details, :severity,
    :context, :caused_by, :error_chain, :timestamp,
    :retry_info, :recoverable, :tags, :metrics
  ]
  
  # Construction functions
  def new(category, code, message, opts \\ [])
  def wrap(caused_by, category, code, message, opts \\ [])
  def chain(errors) when is_list(errors)
  
  # Context functions
  def with_context(error, context_updates)
  def capture_context(opts \\ [])
  def enrich_context(error, additional_context)
  
  # Retry functions
  def with_retry_info(error, retry_info)
  def should_retry?(error)
  def next_retry_delay(error)
  
  # Telemetry functions
  def add_tags(error, tags)
  def add_metrics(error, metrics)
  def telemetry_metadata(error)
  
  # Conversion functions
  def from_exception(exception, opts \\ [])
  def from_jido_error(jido_error, opts \\ [])
  def from_legacy_error(legacy_error, opts \\ [])
  
  # Serialization
  def to_map(error)
  def from_map(error_map)
  def to_json(error)
  def from_json(json_string)
  
  # Analysis functions
  def error_chain(error)
  def root_cause(error)
  def similar_errors(error, error_list)
  def aggregate_errors(errors)
end
```

### Error Code Registry

**Systematic Error Code Organization**:

```elixir
defmodule Foundation.Types.ErrorCodes do
  @moduledoc """
  Comprehensive registry of all error codes used across Foundation OS.
  Organized by category for easy lookup and maintenance.
  """
  
  # Foundation Layer Error Codes
  @foundation_codes %{
    # Process Registry
    registry_not_found: %{
      category: :not_found,
      severity: :error,
      message: "Registry namespace not found",
      recoverable: false
    },
    process_not_found: %{
      category: :not_found, 
      severity: :warning,
      message: "Process not found in registry",
      recoverable: true
    },
    process_already_registered: %{
      category: :conflict,
      severity: :error, 
      message: "Process already registered",
      recoverable: false
    },
    
    # Infrastructure
    circuit_breaker_open: %{
      category: :circuit_breaker,
      severity: :warning,
      message: "Circuit breaker is open",
      recoverable: true
    },
    rate_limit_exceeded: %{
      category: :rate_limit,
      severity: :warning, 
      message: "Rate limit exceeded",
      recoverable: true
    },
    
    # Network and connectivity
    connection_timeout: %{
      category: :timeout,
      severity: :error,
      message: "Connection timed out",
      recoverable: true
    },
    service_unavailable: %{
      category: :service_unavailable,
      severity: :error,
      message: "Service temporarily unavailable", 
      recoverable: true
    }
  }
  
  # FoundationJido Layer Error Codes
  @foundation_jido_codes %{
    # Agent Management
    agent_start_failed: %{
      category: :agent_lifecycle,
      severity: :error,
      message: "Failed to start agent",
      recoverable: true
    },
    agent_registration_failed: %{
      category: :agent_management,
      severity: :error,
      message: "Agent registration failed",
      recoverable: true
    },
    capability_mismatch: %{
      category: :agent_management,
      severity: :warning,
      message: "Agent capabilities don't match requirements",
      recoverable: false
    },
    
    # Signal Processing
    signal_dispatch_failed: %{
      category: :signal_dispatch,
      severity: :error,
      message: "Signal dispatch failed",
      recoverable: true
    },
    adapter_unavailable: %{
      category: :signal_dispatch,
      severity: :error,
      message: "Signal dispatch adapter unavailable",
      recoverable: true
    },
    
    # Coordination
    coordination_timeout: %{
      category: :coordination,
      severity: :warning,
      message: "Coordination process timed out",
      recoverable: true
    },
    insufficient_agents: %{
      category: :coordination,
      severity: :error,
      message: "Insufficient agents for coordination",
      recoverable: false
    },
    auction_failed: %{
      category: :auction,
      severity: :error,
      message: "Auction process failed",
      recoverable: true
    }
  }
  
  # DSPEx Layer Error Codes
  @dspex_codes %{
    # Program Execution
    program_execution_failed: %{
      category: :ml_processing,
      severity: :error,
      message: "Program execution failed",
      recoverable: true
    },
    model_prediction_failed: %{
      category: :model_error,
      severity: :error,
      message: "Model prediction failed", 
      recoverable: true
    },
    
    # Optimization
    optimization_diverged: %{
      category: :optimization,
      severity: :warning,
      message: "Optimization algorithm diverged",
      recoverable: true
    },
    variable_space_invalid: %{
      category: :variable_conflict,
      severity: :error,
      message: "Variable space validation failed",
      recoverable: false
    },
    
    # Multi-agent ML
    coordination_convergence_failed: %{
      category: :coordination,
      severity: :warning,
      message: "Multi-agent optimization failed to converge",
      recoverable: true
    }
  }
  
  def all_codes do
    Map.merge(@foundation_codes, Map.merge(@foundation_jido_codes, @dspex_codes))
  end
  
  def get_code_info(code), do: Map.get(all_codes(), code)
  def category_codes(category), do: Enum.filter(all_codes(), fn {_, info} -> info.category == category end)
end
```

---

## Migration Strategy

### Phase 1: Foundation Error System Completion

**Complete Enhanced Error Merge**:

```bash
# Based on audit doc 013, complete the error consolidation
# that was partially implemented

# 1. Verify current state
find lib/foundation/types/ -name "*error*"

# 2. Complete the merge (if not already done)
mix foundation.complete_error_merge

# 3. Update all Foundation modules
find lib/foundation/ -name "*.ex" -exec grep -l "EnhancedError" {} \;
```

**Update Foundation Modules**:

```elixir
# Before: lib/foundation/process_registry/registry.ex
defmodule Foundation.ProcessRegistry.Registry do
  def register(pid, metadata, namespace) do
    case validate_metadata(metadata) do
      :ok -> do_register(pid, metadata, namespace)
      {:error, reason} -> {:error, reason}  # Old inconsistent format
    end
  end
end

# After: lib/foundation/process_registry/registry.ex
defmodule Foundation.ProcessRegistry.Registry do
  alias Foundation.Types.Error
  
  def register(pid, metadata, namespace) do
    case validate_metadata(metadata) do
      :ok -> do_register(pid, metadata, namespace)
      {:error, reason} -> 
        {:error, Error.new(:validation, :invalid_metadata, 
                          "Metadata validation failed", %{reason: reason})}
    end
  end
end
```

### Phase 2: Jido Library Error Standardization

**Create Jido Error Conversion Layer**:

```elixir
# lib/foundation_jido/error_bridge.ex
defmodule FoundationJido.ErrorBridge do
  @moduledoc """
  Converts Jido library errors to Foundation.Types.Error format.
  Provides transparent error conversion during integration.
  """
  
  alias Foundation.Types.Error
  
  @doc """
  Convert JidoAction error to Foundation error.
  """
  def from_jido_action_error(%JidoAction.Error{} = jido_error) do
    Error.new(
      map_jido_category(jido_error.type),
      map_jido_code(jido_error.code),
      jido_error.message,
      context: %{
        jido_type: jido_error.type,
        jido_details: jido_error.details,
        converted_from: :jido_action
      },
      details: jido_error.details || %{},
      severity: map_jido_severity(jido_error.severity)
    )
  end
  
  @doc """
  Convert JidoSignal error to Foundation error.
  """
  def from_jido_signal_error(%JidoSignal.Error{} = signal_error) do
    Error.new(
      :signal_dispatch,
      map_signal_code(signal_error.reason),
      signal_error.message || "Signal processing failed",
      context: %{
        signal_id: signal_error.signal_id,
        adapter: signal_error.adapter,
        converted_from: :jido_signal
      },
      details: signal_error.context || %{},
      severity: :error
    )
  end
  
  @doc """
  Convert generic Jido error to Foundation error.
  """
  def from_jido_error(error) when is_binary(error) do
    Error.new(:external, :jido_error, error,
      context: %{converted_from: :jido_string})
  end
  
  def from_jido_error({:error, reason}) do
    Error.new(:external, :jido_error, inspect(reason),
      context: %{converted_from: :jido_tuple, original: reason})
  end
  
  # Mapping functions
  defp map_jido_category(:validation), do: :validation
  defp map_jido_category(:execution), do: :internal
  defp map_jido_category(:timeout), do: :timeout
  defp map_jido_category(:network), do: :network
  defp map_jido_category(_), do: :external
  
  defp map_jido_code(:invalid_action), do: :invalid_action
  defp map_jido_code(:execution_failed), do: :execution_failed
  defp map_jido_code(:timeout), do: :action_timeout
  defp map_jido_code(code), do: code
  
  defp map_signal_code(:dispatch_failed), do: :signal_dispatch_failed
  defp map_signal_code(:target_unreachable), do: :target_unreachable
  defp map_signal_code(:serialization_failed), do: :serialization_failed
  defp map_signal_code(reason), do: reason
  
  defp map_jido_severity(:error), do: :error
  defp map_jido_severity(:warning), do: :warning
  defp map_jido_severity(:info), do: :info
  defp map_jido_severity(_), do: :error
end
```

**Wrap Jido Library Calls**:

```elixir
# lib/foundation_jido/signal/foundation_dispatch.ex
defmodule FoundationJido.Signal.FoundationDispatch do
  alias Foundation.Types.Error
  alias FoundationJido.ErrorBridge
  
  def dispatch(signal, config) do
    case JidoSignal.Dispatch.dispatch(signal, config) do
      {:ok, result} -> {:ok, result}
      {:error, jido_error} -> 
        foundation_error = ErrorBridge.from_jido_signal_error(jido_error)
        {:error, foundation_error}
    end
  rescue
    exception ->
      error = Error.from_exception(exception, 
        category: :signal_dispatch,
        code: :dispatch_exception,
        context: %{signal: signal, config: config}
      )
      {:error, error}
  end
end
```

### Phase 3: DSPEx Error Standardization

**DSPEx Error Conversion**:

```elixir
# lib/dspex/error_bridge.ex
defmodule DSPEx.ErrorBridge do
  @moduledoc """
  Converts DSPEx/ElixirML errors to Foundation format.
  """
  
  alias Foundation.Types.Error
  
  def from_ml_error(%ElixirML.Schema.ValidationError{} = validation_error) do
    Error.new(
      :validation,
      :schema_validation_failed,
      "ML schema validation failed",
      details: %{
        field: validation_error.field,
        value: validation_error.value,
        constraint: validation_error.constraint
      },
      context: %{
        schema: validation_error.schema,
        converted_from: :elixir_ml_validation
      },
      severity: :error
    )
  end
  
  def from_optimization_error(%DSPEx.Teleprompter.OptimizationError{} = opt_error) do
    Error.new(
      :optimization,
      :optimization_failed,
      opt_error.message,
      details: %{
        strategy: opt_error.strategy,
        iteration: opt_error.iteration,
        metrics: opt_error.metrics
      },
      context: %{
        program: opt_error.program_name,
        converted_from: :dspex_optimization
      },
      severity: determine_optimization_severity(opt_error),
      recoverable: opt_error.recoverable
    )
  end
  
  def from_program_error({:error, reason}) when is_atom(reason) do
    case reason do
      :program_not_found -> 
        Error.new(:not_found, :program_not_found, "DSPEx program not found")
      :invalid_signature ->
        Error.new(:validation, :invalid_signature, "Program signature validation failed")
      :execution_timeout ->
        Error.new(:timeout, :program_timeout, "Program execution timed out")
      _ ->
        Error.new(:ml_processing, :program_error, "Program execution failed", 
          details: %{reason: reason})
    end
  end
  
  defp determine_optimization_severity(%{convergence_score: score}) when score < 0.1, do: :critical
  defp determine_optimization_severity(%{convergence_score: score}) when score < 0.5, do: :error  
  defp determine_optimization_severity(_), do: :warning
end
```

### Phase 4: Automatic Error Conversion

**Global Error Handling Middleware**:

```elixir
# lib/foundation/error_handler.ex
defmodule Foundation.ErrorHandler do
  @moduledoc """
  Global error handling and conversion system.
  Automatically converts errors to Foundation format.
  """
  
  alias Foundation.Types.Error
  alias FoundationJido.ErrorBridge
  alias DSPEx.ErrorBridge, as: DSPExErrorBridge
  
  @doc """
  Normalize any error to Foundation.Types.Error format.
  """
  def normalize_error(error) do
    case error do
      %Error{} = foundation_error -> 
        foundation_error
        
      %JidoAction.Error{} = jido_error ->
        ErrorBridge.from_jido_action_error(jido_error)
        
      %JidoSignal.Error{} = signal_error ->
        ErrorBridge.from_jido_signal_error(signal_error)
        
      %ElixirML.Schema.ValidationError{} = validation_error ->
        DSPExErrorBridge.from_ml_error(validation_error)
        
      %DSPEx.Teleprompter.OptimizationError{} = opt_error ->
        DSPExErrorBridge.from_optimization_error(opt_error)
        
      exception when is_exception(exception) ->
        Error.from_exception(exception)
        
      {:error, reason} ->
        Error.new(:external, :unknown_error, inspect(reason),
          details: %{original: reason})
        
      reason when is_binary(reason) ->
        Error.new(:external, :unknown_error, reason)
        
      reason ->
        Error.new(:external, :unknown_error, "Unknown error occurred",
          details: %{original: inspect(reason)})
    end
  end
  
  @doc """
  Wrap function calls with automatic error conversion.
  """
  defmacro with_error_conversion(do: block) do
    quote do
      try do
        case unquote(block) do
          {:ok, result} -> {:ok, result}
          {:error, error} -> {:error, Foundation.ErrorHandler.normalize_error(error)}
          result -> result
        end
      rescue
        exception -> {:error, Foundation.ErrorHandler.normalize_error(exception)}
      end
    end
  end
end
```

**Usage in Integration Layer**:

```elixir
# lib/foundation_jido/agent/registry_adapter.ex
defmodule FoundationJido.Agent.RegistryAdapter do
  import Foundation.ErrorHandler, only: [with_error_conversion: 1]
  
  def register_agent(config) do
    with_error_conversion do
      with {:ok, jido_agent} <- start_jido_agent(config),
           {:ok, metadata} <- build_metadata(config),
           {:ok, entry} <- Foundation.ProcessRegistry.register(jido_agent, metadata) do
        {:ok, %{pid: jido_agent, agent_id: config.name, registry_entry: entry}}
      end
    end
  end
end
```

---

## Error Telemetry Integration

### Automatic Error Metrics

```elixir
# lib/foundation/error_telemetry.ex
defmodule Foundation.ErrorTelemetry do
  @moduledoc """
  Automatic telemetry for all Foundation errors.
  Provides comprehensive error monitoring and alerting.
  """
  
  alias Foundation.Types.Error
  alias Foundation.Telemetry
  
  @doc """
  Emit telemetry for an error.
  """
  def emit_error_telemetry(%Error{} = error) do
    # Core error metrics
    Telemetry.execute([:foundation, :error, :occurred], %{count: 1}, %{
      category: error.category,
      code: error.code,
      severity: error.severity,
      recoverable: error.recoverable
    })
    
    # Context-specific metrics
    emit_context_metrics(error)
    
    # Error chain metrics
    emit_chain_metrics(error)
    
    # Performance impact metrics
    emit_performance_metrics(error)
  end
  
  defp emit_context_metrics(%Error{context: context} = error) do
    if context.module do
      Telemetry.execute([:foundation, :error, :by_module], %{count: 1}, %{
        module: context.module,
        function: context.function,
        category: error.category
      })
    end
    
    if context.request_id do
      Telemetry.execute([:foundation, :error, :by_request], %{count: 1}, %{
        request_id: context.request_id,
        category: error.category
      })
    end
  end
  
  defp emit_chain_metrics(%Error{error_chain: chain}) when length(chain) > 1 do
    Telemetry.execute([:foundation, :error, :chained], %{
      count: 1,
      chain_length: length(chain)
    }, %{
      root_category: List.last(chain).category,
      final_category: List.first(chain).category
    })
  end
  defp emit_chain_metrics(_), do: :ok
  
  defp emit_performance_metrics(%Error{} = error) do
    # Track errors that might indicate performance issues
    performance_categories = [:timeout, :circuit_breaker, :rate_limit, :resource_exhausted]
    
    if error.category in performance_categories do
      Telemetry.execute([:foundation, :performance, :error], %{count: 1}, %{
        category: error.category,
        severity: error.severity
      })
    end
  end
end
```

### Error Aggregation and Analysis

```elixir
# lib/foundation/error_analyzer.ex
defmodule Foundation.ErrorAnalyzer do
  @moduledoc """
  Analyzes error patterns for system health monitoring.
  """
  
  alias Foundation.Types.Error
  
  def analyze_error_patterns(errors, time_window \\ :hour) do
    %{
      total_errors: length(errors),
      by_category: group_by_category(errors),
      by_severity: group_by_severity(errors),
      trending_errors: find_trending_errors(errors, time_window),
      error_rate: calculate_error_rate(errors, time_window),
      most_common: find_most_common_errors(errors),
      recovery_rate: calculate_recovery_rate(errors)
    }
  end
  
  def generate_alerts(analysis) do
    alerts = []
    
    # High error rate alert
    alerts = if analysis.error_rate > 0.05 do
      [%{type: :high_error_rate, severity: :warning, rate: analysis.error_rate} | alerts]
    else
      alerts
    end
    
    # Critical error alert
    alerts = if analysis.by_severity[:critical] > 0 do
      [%{type: :critical_errors, severity: :critical, count: analysis.by_severity[:critical]} | alerts]
    else
      alerts
    end
    
    # Trending error alert
    alerts = if length(analysis.trending_errors) > 0 do
      [%{type: :trending_errors, severity: :warning, errors: analysis.trending_errors} | alerts]
    else
      alerts
    end
    
    alerts
  end
  
  # Implementation functions...
  defp group_by_category(errors), do: Enum.group_by(errors, & &1.category)
  defp group_by_severity(errors), do: Enum.group_by(errors, & &1.severity)
  # ... rest of implementation
end
```

---

## Testing Strategy for Error Standardization

### Error Conversion Tests

```elixir
# test/foundation/error_standardization_test.exs
defmodule Foundation.ErrorStandardizationTest do
  use ExUnit.Case
  
  alias Foundation.Types.Error
  alias FoundationJido.ErrorBridge
  
  describe "Jido error conversion" do
    test "converts JidoAction errors correctly" do
      jido_error = %JidoAction.Error{
        type: :validation,
        code: :invalid_action,
        message: "Action validation failed",
        details: %{field: :name}
      }
      
      foundation_error = ErrorBridge.from_jido_action_error(jido_error)
      
      assert %Error{} = foundation_error
      assert foundation_error.category == :validation
      assert foundation_error.code == :invalid_action
      assert foundation_error.message == "Action validation failed"
      assert foundation_error.context.converted_from == :jido_action
    end
    
    test "preserves original error context" do
      jido_error = %JidoAction.Error{type: :execution, details: %{step: 3}}
      foundation_error = ErrorBridge.from_jido_action_error(jido_error)
      
      assert foundation_error.context.jido_details == %{step: 3}
      assert foundation_error.details == %{step: 3}
    end
  end
  
  describe "automatic error normalization" do
    test "normalizes various error types" do
      errors = [
        %Error{category: :validation, code: :test},
        %JidoAction.Error{type: :execution, code: :failed},
        {:error, :timeout},
        "String error",
        %RuntimeError{message: "Runtime error"}
      ]
      
      normalized = Enum.map(errors, &Foundation.ErrorHandler.normalize_error/1)
      
      assert Enum.all?(normalized, &match?(%Error{}, &1))
    end
  end
end
```

### Error Telemetry Tests

```elixir
# test/foundation/error_telemetry_test.exs
defmodule Foundation.ErrorTelemetryTest do
  use ExUnit.Case
  
  alias Foundation.Types.Error
  alias Foundation.ErrorTelemetry
  
  setup do
    # Attach test telemetry handler
    :telemetry.attach_many(
      "test-error-handler",
      [
        [:foundation, :error, :occurred],
        [:foundation, :error, :by_module],
        [:foundation, :performance, :error]
      ],
      fn event, measurements, metadata, _config ->
        send(self(), {:telemetry, event, measurements, metadata})
      end,
      nil
    )
    
    on_exit(fn -> :telemetry.detach("test-error-handler") end)
  end
  
  test "emits telemetry for errors" do
    error = Error.new(:validation, :test_error, "Test error")
    ErrorTelemetry.emit_error_telemetry(error)
    
    assert_receive {:telemetry, [:foundation, :error, :occurred], 
                   %{count: 1}, 
                   %{category: :validation, code: :test_error}}
  end
  
  test "emits context-specific telemetry" do
    error = Error.new(:internal, :test_error, "Test", 
      context: %{module: TestModule, function: :test_function})
    
    ErrorTelemetry.emit_error_telemetry(error)
    
    assert_receive {:telemetry, [:foundation, :error, :by_module],
                   %{count: 1},
                   %{module: TestModule, function: :test_function}}
  end
end
```

---

## Migration Verification

### Verification Checklist

```bash
# 1. No legacy error structures in use
find lib/ -name "*.ex" -exec grep -l "EnhancedError" {} \;
# Should return empty

# 2. All Jido errors converted
grep -r "JidoAction.Error\|JidoSignal.Error" lib/ --include="*.ex"
# Should only appear in conversion functions

# 3. Consistent error handling
mix foundation.audit_error_handling

# 4. Telemetry integration working
mix foundation.test_error_telemetry

# 5. Performance impact acceptable
mix foundation.benchmark_error_conversion
```

### Automated Migration Verification

```elixir
# lib/foundation/migration_verifier.ex
defmodule Foundation.MigrationVerifier do
  @moduledoc """
  Verifies error standardization migration is complete.
  """
  
  def verify_error_standardization do
    results = %{
      legacy_errors: check_legacy_errors(),
      jido_conversion: check_jido_conversion(),
      telemetry_integration: check_telemetry_integration(),
      performance_impact: check_performance_impact()
    }
    
    overall_status = if Enum.all?(Map.values(results), & &1.status == :ok) do
      :complete
    else
      :incomplete
    end
    
    %{status: overall_status, details: results}
  end
  
  defp check_legacy_errors do
    # Check for EnhancedError usage
    case System.cmd("grep", ["-r", "EnhancedError", "lib/", "--include=*.ex"]) do
      {output, 0} when output != "" -> 
        %{status: :error, message: "Legacy EnhancedError found", details: output}
      _ -> 
        %{status: :ok, message: "No legacy errors found"}
    end
  end
  
  # ... rest of verification functions
end
```

## Conclusion

This error standardization strategy provides:

1. **Unified Error System**: Single canonical error structure across all layers
2. **Automatic Conversion**: Transparent conversion from legacy and Jido errors
3. **Enhanced Debugging**: Rich context and error chaining for better troubleshooting
4. **Comprehensive Telemetry**: Automatic error monitoring and analysis
5. **Migration Safety**: Incremental migration with verification checkpoints

The result is a robust, maintainable error handling system that improves debugging capabilities, enables better monitoring, and provides a consistent developer experience across the entire Foundation OS platform.

**Key Benefits**:
- Reduced debugging time through consistent error formats
- Better system monitoring through unified telemetry
- Improved error recovery through structured retry information
- Enhanced developer experience through predictable error handling
- Future-proof error system that can evolve with the platform