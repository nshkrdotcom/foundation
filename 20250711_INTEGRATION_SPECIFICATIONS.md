# DSPEx Integration Specifications
**Date**: 2025-07-11  
**Status**: Integration Design  
**Scope**: Complete system integration architecture

## Executive Summary

This document specifies the precise integration architecture between DSPEx, ElixirML, Foundation, and Jido layers. By leveraging our simplified Foundation/Jido integration (1,720+ line reduction), we achieve clean separation of concerns while enabling seamless interoperability across all system components.

## System Architecture Overview

### Layer Separation and Responsibilities

```
┌─────────────────────────────────────────────────────────────┐
│                      DSPEx Layer                            │
│  User Interface - ML-Native Developer Experience            │
│  ────────────────────────────────────────────────────────  │
│  • DSPEx.Program - Intuitive program definition            │
│  • DSPEx.Optimizer - Universal optimization interface      │
│  • DSPEx.Skills - Composable functionality                 │
│  • DSPEx.MABEAM - Multi-agent conversion                   │
└─────────────────────────────────────────────────────────────┘
              ▼ Clean API Boundary ▼
┌─────────────────────────────────────────────────────────────┐
│                    ElixirML Layer                           │
│  ML Foundation - Schema, Variables, Agents                 │
│  ────────────────────────────────────────────────────────  │
│  • Schema Engine - ML-native types & validation            │
│  • Variable System - Universal parameter optimization      │
│  • MABEAM - Multi-agent coordination primitives            │
└─────────────────────────────────────────────────────────────┘
              ▼ Service Protocols ▼
┌─────────────────────────────────────────────────────────────┐
│                   Foundation Layer                          │
│  Infrastructure - Production-Grade Services                │
│  ────────────────────────────────────────────────────────  │
│  • Registry - Service discovery & agent lifecycle          │
│  • Telemetry - Observability & monitoring                  │
│  • Services - HTTP, Database, Circuit breakers             │
│  • Supervision - Fault tolerance & process management      │
└─────────────────────────────────────────────────────────────┘
              ▼ Agent Interface ▼
┌─────────────────────────────────────────────────────────────┐
│                     Jido Layer                              │
│  Agent Runtime - Simplified & Streamlined                  │
│  ────────────────────────────────────────────────────────  │
│  • Agent Lifecycle - Mount, shutdown, callbacks            │
│  • Skills System - Modular capabilities                    │
│  • Sensors - Event detection & response                    │
│  • Actions - Validated behavior execution                  │
└─────────────────────────────────────────────────────────────┘
```

## Integration Protocols

### Protocol 1: DSPEx ↔ ElixirML Integration

#### Schema Integration
```elixir
# DSPEx programs use ElixirML schemas transparently
defmodule MyProgram do
  use DSPEx.Program
  
  # This automatically integrates with ElixirML.Schema
  defschema InputSchema do
    field :text, :string, required: true
    field :temperature, :probability, default: 0.7, variable: true
    # ↑ Variable extraction handled by ElixirML.Variable.Space
  end
  
  def predict(input) do
    # Automatic validation via ElixirML.Schema
    # Variable extraction via ElixirML.Variable.MLTypes
  end
end

# Implementation bridge
defmodule DSPEx.Schema do
  defmacro defschema(name, do: block) do
    quote do
      # Store DSPEx metadata
      @dspex_schemas {unquote(name), unquote(block)}
      
      # Delegate to ElixirML for core functionality
      use ElixirML.Schema
      defschema unquote(name) do
        unquote(block)
      end
      
      # Extract variables for optimization
      @dspex_variables ElixirML.Variable.extract_from_schema(__MODULE__, unquote(name))
    end
  end
end
```

#### Variable System Integration
```elixir
# DSPEx optimization automatically uses ElixirML Variable System
defmodule DSPEx.Optimizer do
  def optimize(program_module, training_data, opts) do
    # Extract variables using ElixirML
    variable_space = ElixirML.Variable.Space.new()
                    |> extract_program_variables(program_module)
    
    # Use ElixirML optimizers
    case opts[:optimizer] do
      :simba -> 
        ElixirML.Teleprompter.SIMBA.optimize(variable_space, evaluation_fn, opts)
      :mipro -> 
        ElixirML.Teleprompter.MIPRO.optimize(variable_space, evaluation_fn, opts)
    end
  end
  
  defp extract_program_variables(space, program_module) do
    program_module.__dspex_variables__()
    |> Enum.reduce(space, fn variable_spec, acc ->
      variable = convert_to_elixir_ml_variable(variable_spec)
      ElixirML.Variable.Space.add_variable(acc, variable)
    end)
  end
end
```

#### MABEAM Integration
```elixir
# DSPEx multi-agent conversion uses ElixirML.MABEAM
defmodule DSPEx.MABEAM do
  def convert_program(program_module, opts) do
    # Create agent specifications for ElixirML.MABEAM
    agent_specs = [
      {:program_executor, DSPEx.Agents.ProgramAgent, %{
        program: program_module
      }},
      {:optimizer, ElixirML.MABEAM.Agents.OptimizerAgent, %{
        strategy: opts[:optimization_strategy]
      }}
    ]
    
    # Use ElixirML.MABEAM for coordination
    ElixirML.MABEAM.create_agent_system(agent_specs)
  end
end
```

### Protocol 2: ElixirML ↔ Foundation Integration

#### Service Discovery Integration
```elixir
# ElixirML agents register with Foundation.Registry
defmodule ElixirML.MABEAM.Core do
  def start_agent(agent_spec, opts) do
    case Jido.Agent.start_link(agent_spec, opts) do
      {:ok, pid} ->
        # Register with Foundation Registry
        metadata = %{
          framework: :elixir_ml,
          type: :mabeam_agent,
          capabilities: extract_capabilities(agent_spec),
          started_at: DateTime.utc_now()
        }
        
        Foundation.Registry.register(pid, pid, metadata)
        {:ok, pid}
        
      error ->
        error
    end
  end
end
```

#### Telemetry Integration
```elixir
# ElixirML emits events to Foundation.Telemetry
defmodule ElixirML.Variable.Space do
  def optimize(space, evaluation_fn, opts) do
    # Emit optimization start event
    Foundation.Telemetry.emit(
      [:elixir_ml, :optimization, :started],
      %{variable_count: count_variables(space)},
      %{optimizer: opts[:optimizer]}
    )
    
    result = run_optimization(space, evaluation_fn, opts)
    
    # Emit completion event
    Foundation.Telemetry.emit(
      [:elixir_ml, :optimization, :completed],
      %{duration: result.duration, score: result.score},
      %{optimizer: opts[:optimizer]}
    )
    
    result
  end
end
```

#### Resource Management Integration
```elixir
# ElixirML uses Foundation services for external calls
defmodule ElixirML.LLM.Provider do
  def complete(prompt, opts) do
    # Use Foundation's HTTP client with circuit breaker
    case Foundation.Services.HTTPClient.post(
      build_url(opts[:provider]),
      build_payload(prompt, opts),
      headers: build_headers(opts),
      timeout: opts[:timeout] || 30_000,
      retries: opts[:retries] || 3
    ) do
      {:ok, response} ->
        # Use Foundation cost tracking
        Foundation.Services.CostTracker.record_usage(
          opts[:provider],
          calculate_cost(response, opts)
        )
        
        parse_response(response, opts)
        
      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

### Protocol 3: Foundation ↔ Jido Integration (Simplified)

#### Agent Lifecycle Integration
```elixir
# Simplified Foundation agents use clean Jido interface
defmodule JidoSystem.Agents.FoundationAgent do
  defmacro __using__(opts) do
    quote do
      use Jido.Agent, unquote(opts)
      
      # Clean mount signature - no defensive programming
      def mount(agent, opts) do
        # Direct Foundation service registration
        metadata = build_metadata(__MODULE__, agent)
        Foundation.Registry.register(self(), metadata)
        
        # Simple telemetry
        Foundation.Telemetry.emit([:jido_system, :agent, :started], %{}, %{
          agent_id: agent.id,
          agent_type: __MODULE__
        })
        
        {:ok, agent}
      end
      
      # Clean shutdown signature
      def shutdown(agent, reason) do
        # Direct Foundation cleanup
        Foundation.Registry.unregister(self())
        
        Foundation.Telemetry.emit([:jido_system, :agent, :terminated], %{}, %{
          agent_id: agent.id,
          reason: reason
        })
        
        {:ok, agent}
      end
      
      defoverridable mount: 2, shutdown: 2
    end
  end
end
```

#### Skills Integration
```elixir
# Foundation services exposed as Jido skills
defmodule JidoFoundation.Skills.HTTPClient do
  use Jido.Skill
  
  def call(action, params, context) do
    case action do
      :get ->
        Foundation.Services.HTTPClient.get(
          params.url,
          params.headers || [],
          timeout: params.timeout || 10_000
        )
        
      :post ->
        Foundation.Services.HTTPClient.post(
          params.url,
          params.body,
          headers: params.headers || [],
          timeout: params.timeout || 10_000
        )
    end
  end
end
```

## Data Flow Specifications

### Request Flow: DSPEx → ElixirML → Foundation → Jido

#### 1. DSPEx Program Execution
```elixir
# User calls DSPEx program
MyProgram.predict(%{question: "What is AI?"})

# DSPEx layer
DSPEx.Program.execute(MyProgram, input) do
  # Validate input using ElixirML.Schema
  {:ok, validated} = MyProgram.InputSchema.validate(input)
  
  # Execute predict function
  MyProgram.predict(validated)
end

# ElixirML layer (if multi-agent)
ElixirML.MABEAM.coordinate_execution(agent_system, input) do
  # Distribute to appropriate agents
  # Use Foundation.Registry for agent discovery
  # Use Foundation.Services for external calls
end

# Foundation layer
Foundation.Services.HTTPClient.post(llm_endpoint, payload) do
  # Circuit breaker protection
  # Cost tracking
  # Telemetry emission
end

# Jido layer
Jido.Agent.run(agent, action, params) do
  # Execute action with validation
  # Handle errors gracefully
  # Emit lifecycle events
end
```

#### 2. Optimization Flow
```elixir
# User optimizes program
DSPEx.optimize(MyProgram, training_data)

# DSPEx extracts variables
variable_space = extract_variables(MyProgram)

# ElixirML runs optimization
ElixirML.Teleprompter.SIMBA.optimize(variable_space, eval_fn) do
  # Use Foundation.Registry to find available agents
  # Use Foundation.Telemetry for progress tracking
  # Use Foundation.Services for parallel evaluation
end

# Foundation coordinates resources
Foundation.Services.ProcessManager.spawn_workers(evaluation_tasks) do
  # Proper supervision
  # Resource limits
  # Error isolation
end

# Jido executes evaluation tasks
Jido.Agent.run(evaluation_agent, :evaluate, config) do
  # Run program with configuration
  # Return evaluation score
end
```

### Event Flow: Telemetry and Monitoring

#### 1. Event Emission Chain
```elixir
# DSPEx events
:telemetry.execute([:dspex, :program, :executed], measurements, metadata)
  ↓
# ElixirML events  
:telemetry.execute([:elixir_ml, :optimization, :step], measurements, metadata)
  ↓
# Foundation events
:telemetry.execute([:foundation, :service, :call], measurements, metadata)
  ↓
# Jido events
:telemetry.execute([:jido, :agent, :action], measurements, metadata)
```

#### 2. Monitoring Integration
```elixir
# Foundation.Telemetry aggregates all events
defmodule Foundation.Telemetry.Aggregator do
  def handle_event([:dspex | _], measurements, metadata, _config) do
    # DSPEx-specific aggregation
    update_dspex_metrics(measurements, metadata)
  end
  
  def handle_event([:elixir_ml | _], measurements, metadata, _config) do
    # ElixirML-specific aggregation
    update_ml_metrics(measurements, metadata)
  end
  
  def handle_event([:jido | _], measurements, metadata, _config) do
    # Jido-specific aggregation
    update_agent_metrics(measurements, metadata)
  end
end
```

## Error Handling Specifications

### Error Propagation Strategy

#### 1. Layer-Specific Error Handling
```elixir
# DSPEx Layer - User-friendly errors
defmodule DSPEx.Error do
  defstruct [:type, :message, :details, :suggestions]
  
  def from_elixir_ml_error(%ElixirML.Error{} = error) do
    %__MODULE__{
      type: :optimization_error,
      message: "Optimization failed: #{error.message}",
      details: error.details,
      suggestions: generate_suggestions(error)
    }
  end
end

# ElixirML Layer - Technical errors
defmodule ElixirML.Error do
  defstruct [:type, :message, :details, :context]
  
  def from_foundation_error(%Foundation.Error{} = error) do
    %__MODULE__{
      type: map_foundation_error_type(error.type),
      message: error.message,
      details: error.details,
      context: %{layer: :foundation}
    }
  end
end

# Foundation Layer - Infrastructure errors
defmodule Foundation.Error do
  defstruct [:type, :message, :details, :service]
  
  def from_jido_error(%Jido.Error{} = error) do
    %__MODULE__{
      type: :agent_error,
      message: "Agent operation failed: #{error.message}",
      details: error.details,
      service: :jido_system
    }
  end
end
```

#### 2. Error Recovery Mechanisms
```elixir
# Automatic error recovery with circuit breaker
defmodule DSPEx.ErrorRecovery do
  def execute_with_recovery(operation, opts \\ []) do
    case operation.() do
      {:ok, result} ->
        {:ok, result}
        
      {:error, %DSPEx.Error{type: :optimization_error}} ->
        # Retry with simpler optimization
        retry_with_fallback(operation, :simple_optimization)
        
      {:error, %DSPEx.Error{type: :agent_error}} ->
        # Fallback to direct execution
        retry_with_fallback(operation, :direct_execution)
        
      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

## Performance Specifications

### Latency Requirements

| Operation | Target Latency | Timeout |
|-----------|---------------|---------|
| Simple DSPEx prediction | <100ms | 5s |
| Complex multi-agent workflow | <1s | 30s |
| Variable extraction | <10ms | 1s |
| Agent system creation | <500ms | 10s |
| Optimization step | <2s | 60s |

### Throughput Requirements

| Metric | Target | Measurement |
|--------|--------|-------------|
| Concurrent DSPEx programs | 1,000+ | Per node |
| Agent operations per second | 10,000+ | System-wide |
| Optimization evaluations | 100+ | Per second |
| Foundation service calls | 50,000+ | Per second |

### Resource Utilization

| Resource | Target Utilization | Alert Threshold |
|----------|-------------------|-----------------|
| CPU | <70% | 80% |
| Memory | <80% | 90% |
| Agent processes | <10,000 | 15,000 |
| ETS tables | <100 | 150 |

## Security Specifications

### Authentication and Authorization

#### 1. Inter-Layer Security
```elixir
# Foundation provides authentication for all layers
defmodule Foundation.Auth do
  def authenticate_request(token, scope) do
    case validate_token(token) do
      {:ok, user} ->
        if authorized?(user, scope) do
          {:ok, user}
        else
          {:error, :unauthorized}
        end
        
      {:error, reason} ->
        {:error, reason}
    end
  end
end

# DSPEx enforces authorization
defmodule DSPEx.Program do
  def predict(input, opts \\ []) do
    case Foundation.Auth.authenticate_request(opts[:token], :program_execution) do
      {:ok, _user} ->
        execute_prediction(input, opts)
        
      {:error, reason} ->
        {:error, {:authentication_failed, reason}}
    end
  end
end
```

#### 2. Skill Security
```elixir
# Skills require explicit permission grants
defmodule DSPEx.Skills.WebSearch do
  def search(query, opts) do
    case Foundation.Auth.check_permission(opts[:user], :web_search) do
      :ok ->
        perform_search(query, opts)
        
      {:error, reason} ->
        {:error, {:permission_denied, reason}}
    end
  end
end
```

### Data Protection

#### 1. Sensitive Data Handling
```elixir
# Automatic PII detection and protection
defmodule DSPEx.Privacy do
  def sanitize_input(input) do
    input
    |> detect_pii()
    |> mask_sensitive_data()
    |> audit_log()
  end
  
  defp detect_pii(input) do
    # Use Foundation.Services.PIIDetector
    Foundation.Services.PIIDetector.scan(input)
  end
end
```

## Testing Integration Specifications

### Cross-Layer Testing Strategy

#### 1. Integration Test Framework
```elixir
defmodule DSPEx.IntegrationTest do
  use ExUnit.Case
  
  setup do
    # Start all layers in test mode
    {:ok, _} = Foundation.Application.start_test_mode()
    {:ok, _} = ElixirML.Application.start_test_mode()
    {:ok, _} = DSPEx.Application.start_test_mode()
    
    :ok
  end
  
  test "end-to-end DSPEx program execution" do
    # Test complete flow from DSPEx → ElixirML → Foundation → Jido
    defmodule TestProgram do
      use DSPEx.Program
      
      defschema InputSchema do
        field :text, :string, required: true
      end
      
      def predict(input) do
        {:ok, %{result: "processed: #{input.text}"}}
      end
    end
    
    # Execute and verify all layers work together
    assert {:ok, result} = TestProgram.predict(%{text: "test"})
    assert result.result == "processed: test"
  end
end
```

#### 2. Mock Integration
```elixir
# Foundation provides test doubles for all services
defmodule Foundation.Test.Mocks do
  def setup_mocks do
    # Mock HTTP client
    Mox.defmock(Foundation.Services.HTTPClient.Mock, for: Foundation.Services.HTTPClient)
    
    # Mock telemetry
    Mox.defmock(Foundation.Telemetry.Mock, for: Foundation.Telemetry)
    
    # Mock registry
    Mox.defmock(Foundation.Registry.Mock, for: Foundation.Registry)
  end
end
```

This integration specification ensures clean separation of concerns while enabling seamless interoperability across all system layers. The simplified Foundation/Jido integration removes complexity barriers and allows each layer to focus on its core responsibilities while leveraging the full power of the integrated system.