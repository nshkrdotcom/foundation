# DSPEx Technical Design Specification
**Date**: 2025-07-11  
**Status**: Technical Design  
**Scope**: Complete DSPEx interface architecture on simplified Foundation

## Executive Summary

This technical design specifies the complete DSPEx interface layer built on our simplified Foundation/Jido integration. By leveraging the 51% code reduction and clean infrastructure, we can create an intuitive ML interface that automatically provides multi-agent capabilities, universal optimization, and production-grade reliability.

## Architecture Overview

### System Architecture
```
┌─────────────────────────────────────────────────────────────┐
│                    DSPEx User Interface                     │
├─────────────────────────────────────────────────────────────┤
│  DSPEx.Program  │  DSPEx.Schema  │  DSPEx.Optimizer        │
│  - predict/1    │  - ML types    │  - optimize/3           │
│  - to_agents/1  │  - validation  │  - multi_agent_opt/3    │
│  - compose/2    │  - extraction  │  - variable_space/1     │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│                 ElixirML Foundation Layer                   │
├─────────────────────────────────────────────────────────────┤
│  Schema Engine  │  Variable Sys  │  MABEAM Multi-Agent     │
│  - ML types     │  - universal   │  - coordination         │
│  - compile-time │  - optimization│  - specialized agents   │
│  - validation   │  - extraction  │  - fault tolerance      │
└─────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────┐
│              Simplified Foundation/Jido Layer               │
├─────────────────────────────────────────────────────────────┤
│  Foundation     │  Jido (Clean)  │  Infrastructure         │
│  - supervision  │  - agents      │  - telemetry           │
│  - registry     │  - skills      │  - persistence         │
│  - services     │  - sensors     │  - communication       │
└─────────────────────────────────────────────────────────────┘
```

### Core Design Principles

1. **Intuitive by Default**: Minimal boilerplate, maximum functionality
2. **Production First**: Enterprise concerns handled automatically  
3. **Universal Optimization**: Any parameter can be optimized
4. **Multi-Agent Native**: Every program can become a distributed system
5. **Composable**: Skills and actions combine cleanly
6. **Type Safe**: ML-native types with compile-time validation

## DSPEx.Program Interface Design

### Basic Program Definition
```elixir
defmodule QABot do
  use DSPEx.Program,
    name: "question_answering_bot",
    description: "Answers questions based on context",
    version: "1.0.0"

  # Schema defines inputs, outputs, and optimizable parameters
  defschema InputSchema do
    field :question, :string, required: true, description: "User question"
    field :context, :string, required: false, description: "Background context"
    field :max_tokens, :integer, default: 1000, variable: true, range: {100, 4000}
    field :temperature, :probability, default: 0.7, variable: true
    field :model, :string, default: "gpt-4", variable: true, choices: ["gpt-4", "gpt-3.5-turbo", "claude-3"]
  end

  defschema OutputSchema do
    field :answer, :string, required: true
    field :confidence, :probability, required: true
    field :sources, {:list, :string}, default: []
    field :reasoning, :reasoning_chain, required: false
  end

  # Core prediction function
  def predict(input) do
    input
    |> validate_input()
    |> extract_context()
    |> generate_response()
    |> validate_output()
  end

  # Composable pipeline functions
  defp extract_context(%{context: nil, question: question}) do
    # Use web search skill to find context
    DSPEx.Skills.WebSearch.search(question, max_results: 5)
  end
  defp extract_context(input), do: input

  defp generate_response(input) do
    prompt = build_prompt(input)
    
    # Automatic provider selection based on variables
    response = DSPEx.LLM.complete(prompt, 
      model: input.model,
      temperature: input.temperature,
      max_tokens: input.max_tokens
    )
    
    %{answer: response.text, confidence: response.confidence}
  end
end
```

### Advanced Program Features
```elixir
defmodule AdvancedQABot do
  use DSPEx.Program
  use DSPEx.Skills.WebSearch
  use DSPEx.Skills.VectorDatabase
  use DSPEx.Skills.Reasoning

  # Complex schema with ML-native types
  defschema InputSchema do
    field :question, :string, required: true
    field :query_embedding, :embedding, dimension: 1536
    field :search_strategy, :module, 
      default: DSPEx.Strategies.HybridSearch,
      variable: true,
      choices: [
        DSPEx.Strategies.HybridSearch,
        DSPEx.Strategies.SemanticSearch,
        DSPEx.Strategies.KeywordSearch
      ]
    field :reasoning_steps, :integer, default: 3, variable: true, range: {1, 10}
    field :confidence_threshold, :probability, default: 0.8, variable: true
  end

  # Multi-step reasoning pipeline
  def predict(input) do
    with {:ok, context} <- search_context(input),
         {:ok, reasoning} <- apply_reasoning(input, context),
         {:ok, response} <- generate_final_answer(input, reasoning) do
      {:ok, response}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  # Automatic agent conversion
  def to_agent_system(opts \\ []) do
    DSPEx.MABEAM.convert_program(__MODULE__, opts)
  end

  # Skill-based composition
  defp search_context(input) do
    # Use variable-selected strategy
    strategy = input.search_strategy
    strategy.search(input.question, embedding: input.query_embedding)
  end

  defp apply_reasoning(input, context) do
    # Chain-of-thought reasoning with variable steps
    DSPEx.Skills.Reasoning.chain_of_thought(
      input.question, 
      context, 
      steps: input.reasoning_steps
    )
  end
end
```

## DSPEx.Schema Integration

### ML-Native Type System
```elixir
defmodule DSPEx.Schema do
  @moduledoc """
  Extended ElixirML.Schema with DSPEx-specific conveniences
  """
  
  defmacro __using__(opts) do
    quote do
      use ElixirML.Schema, unquote(opts)
      import DSPEx.Schema.DSL
      import DSPEx.Schema.Variables
    end
  end
  
  # DSPEx-specific field types
  defmacro field(name, type, opts \\ []) do
    quote do
      # Extend ElixirML field with DSPEx features
      ElixirML.Schema.field(unquote(name), unquote(type), unquote(opts))
      
      # Automatic variable extraction for optimization
      if unquote(opts[:variable]) do
        @dspex_variables {unquote(name), unquote(type), unquote(opts)}
      end
    end
  end
end
```

### Enhanced Type Definitions
```elixir
defmodule DSPEx.Types do
  @moduledoc """
  DSPEx-specific types extending ElixirML.Types
  """
  
  # LLM-specific types
  def llm_provider do
    {:choice, ["openai", "anthropic", "google", "local"], 
     weights: %{
       "openai" => %{cost: 0.8, speed: 0.9, quality: 0.9},
       "anthropic" => %{cost: 0.7, speed: 0.8, quality: 0.95},
       "google" => %{cost: 0.9, speed: 0.95, quality: 0.85}
     }}
  end
  
  def model_selection(provider) do
    case provider do
      "openai" -> {:choice, ["gpt-4", "gpt-3.5-turbo", "gpt-4-turbo"]}
      "anthropic" -> {:choice, ["claude-3-opus", "claude-3-sonnet", "claude-3-haiku"]}
      "google" -> {:choice, ["gemini-pro", "gemini-ultra"]}
    end
  end
  
  # Search strategy types
  def search_strategy do
    {:module, [
      DSPEx.Strategies.HybridSearch,
      DSPEx.Strategies.SemanticSearch,
      DSPEx.Strategies.KeywordSearch,
      DSPEx.Strategies.GraphSearch
    ]}
  end
  
  # Reasoning strategy types
  def reasoning_strategy do
    {:module, [
      DSPEx.Reasoning.ChainOfThought,
      DSPEx.Reasoning.ReAct,
      DSPEx.Reasoning.ProgramOfThought,
      DSPEx.Reasoning.TreeOfThoughts
    ]}
  end
end
```

## DSPEx.Optimizer Integration

### Universal Optimization Interface
```elixir
defmodule DSPEx.Optimizer do
  @moduledoc """
  Universal optimization interface for DSPEx programs
  """
  
  @doc """
  Optimize any DSPEx program with any optimizer
  """
  def optimize(program_module, training_data, opts \\ []) do
    # Extract variable space from program
    variable_space = extract_variable_space(program_module)
    
    # Select optimizer
    optimizer = opts[:optimizer] || :simba
    
    # Run optimization
    case optimizer do
      :simba -> optimize_with_simba(program_module, variable_space, training_data, opts)
      :mipro -> optimize_with_mipro(program_module, variable_space, training_data, opts)
      :genetic -> optimize_with_genetic(program_module, variable_space, training_data, opts)
      :multi_agent -> optimize_with_multi_agent(program_module, variable_space, training_data, opts)
    end
  end
  
  @doc """
  Multi-agent optimization using MABEAM
  """
  def optimize_with_multi_agent(program_module, variable_space, training_data, opts) do
    # Convert program to agent system
    {:ok, agent_system} = DSPEx.MABEAM.convert_program(program_module)
    
    # Create optimization agents
    agent_specs = [
      {:optimizer, DSPEx.Agents.OptimizerAgent, %{strategy: :simba}},
      {:evaluator, DSPEx.Agents.EvaluatorAgent, %{metrics: [:accuracy, :cost]}},
      {:coordinator, DSPEx.Agents.CoordinatorAgent, %{}}
    ]
    
    # Run distributed optimization
    ElixirML.MABEAM.optimize_system(
      agent_system,
      training_data,
      agent_specs,
      opts
    )
  end
  
  defp extract_variable_space(program_module) do
    # Get variables from schema definitions
    schema_variables = program_module.__dspex_variables__()
    
    # Build ElixirML Variable.Space
    Enum.reduce(schema_variables, ElixirML.Variable.Space.new(), fn {name, type, opts}, space ->
      variable = build_variable(name, type, opts)
      ElixirML.Variable.Space.add_variable(space, variable)
    end)
  end
end
```

### Optimization Strategies
```elixir
defmodule DSPEx.Optimizers.SIMBA do
  @moduledoc """
  SIMBA optimization strategy for DSPEx programs
  """
  
  def optimize(program_module, variable_space, training_data, opts) do
    # Configure SIMBA with DSPEx-specific features
    config = %{
      population_size: opts[:population_size] || 50,
      generations: opts[:generations] || 100,
      mutation_rate: opts[:mutation_rate] || 0.1,
      crossover_rate: opts[:crossover_rate] || 0.8,
      
      # DSPEx-specific optimizations
      cost_awareness: opts[:cost_awareness] || true,
      multi_objective: opts[:multi_objective] || [:accuracy, :cost, :latency],
      variable_dependencies: extract_dependencies(variable_space)
    }
    
    # Run SIMBA optimization
    DSPEx.Teleprompter.SIMBA.optimize(
      program_module,
      training_data,
      variable_space,
      config
    )
  end
end
```

## DSPEx.MABEAM Multi-Agent Integration

### Automatic Agent Conversion
```elixir
defmodule DSPEx.MABEAM do
  @moduledoc """
  Convert DSPEx programs into multi-agent systems
  """
  
  def convert_program(program_module, opts \\ []) do
    # Analyze program structure
    program_analysis = analyze_program(program_module)
    
    # Create agent specifications
    agent_specs = create_agent_specs(program_analysis, opts)
    
    # Initialize MABEAM system
    ElixirML.MABEAM.create_agent_system(agent_specs)
  end
  
  defp analyze_program(program_module) do
    %{
      schema: program_module.__dspex_schema__(),
      variables: program_module.__dspex_variables__(),
      skills: program_module.__dspex_skills__(),
      complexity: estimate_complexity(program_module)
    }
  end
  
  defp create_agent_specs(analysis, opts) do
    base_specs = [
      {:main, DSPEx.Agents.ProgramAgent, %{
        program_module: analysis.program_module,
        schema: analysis.schema
      }}
    ]
    
    # Add specialized agents based on program features
    specs = add_optimization_agents(base_specs, analysis)
    specs = add_skill_agents(specs, analysis)
    specs = add_monitoring_agents(specs, analysis)
    
    if opts[:coordinator] != false do
      specs ++ [{:coordinator, DSPEx.Agents.CoordinatorAgent, %{}}]
    else
      specs
    end
  end
end
```

### Specialized DSPEx Agents
```elixir
defmodule DSPEx.Agents.ProgramAgent do
  @moduledoc """
  Agent that executes DSPEx program logic
  """
  
  use JidoSystem.Agents.FoundationAgent,
    name: "dspex_program_agent",
    description: "Executes DSPEx program with automatic optimization",
    actions: [
      DSPEx.Actions.ExecuteProgram,
      DSPEx.Actions.OptimizeParameters,
      DSPEx.Actions.CacheResults,
      DSPEx.Actions.ValidateOutput
    ],
    schema: [
      program_module: [type: :atom, required: true],
      current_config: [type: :map, default: %{}],
      optimization_state: [type: :map, default: %{}],
      execution_cache: [type: :map, default: %{}],
      performance_metrics: [type: :map, default: %{}]
    ]
  
  def handle_execute_program(agent, %{input: input, config: config}) do
    try do
      # Use current optimized configuration
      execution_config = Map.merge(agent.state.current_config, config)
      
      # Execute program with configuration
      result = apply(agent.state.program_module, :predict, [
        Map.merge(input, execution_config)
      ])
      
      # Update performance metrics
      new_metrics = update_performance_metrics(
        agent.state.performance_metrics,
        result,
        execution_config
      )
      
      new_state = %{agent.state | performance_metrics: new_metrics}
      
      emit_event(agent, :program_executed, %{
        execution_time: result.execution_time,
        cost: result.cost,
        accuracy: result.accuracy
      }, %{})
      
      {:ok, result, %{agent | state: new_state}}
    rescue
      e ->
        emit_event(agent, :program_execution_error, %{}, %{error: inspect(e)})
        {:error, {:execution_error, e}}
    end
  end
end

defmodule DSPEx.Agents.OptimizerAgent do
  @moduledoc """
  Agent specialized in parameter optimization
  """
  
  use JidoSystem.Agents.FoundationAgent,
    name: "dspex_optimizer_agent",
    description: "Optimizes DSPEx program parameters using various strategies",
    actions: [
      DSPEx.Actions.RunOptimization,
      DSPEx.Actions.EvaluateConfiguration,
      DSPEx.Actions.UpdateBestParams,
      DSPEx.Actions.AnalyzePerformance
    ],
    schema: [
      optimization_strategy: [type: :atom, default: :simba],
      variable_space: [type: :any, required: true],
      best_configuration: [type: :map, default: %{}],
      optimization_history: [type: :list, default: []],
      convergence_criteria: [type: :map, default: %{
        max_generations: 100,
        min_improvement: 0.001,
        stagnation_threshold: 10
      }]
    ]
  
  def handle_run_optimization(agent, %{program_agent: program_pid, training_data: data}) do
    # Coordinate with program agent for optimization
    case run_optimization_cycle(agent, program_pid, data) do
      {:ok, optimized_config} ->
        new_state = %{agent.state | best_configuration: optimized_config}
        
        # Update program agent with new configuration
        Foundation.SupervisedSend.send_supervised(
          program_pid,
          {:update_config, optimized_config},
          timeout: 5000
        )
        
        {:ok, optimized_config, %{agent | state: new_state}}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

## Skills and Actions System

### DSPEx Skills Framework
```elixir
defmodule DSPEx.Skills do
  @moduledoc """
  Modular skills that enhance DSPEx programs
  """
  
  defmacro __using__(skill_module) do
    quote do
      @dspex_skills (Module.get_attribute(__MODULE__, :dspex_skills) || []) ++ [unquote(skill_module)]
      Module.put_attribute(__MODULE__, :dspex_skills, @dspex_skills)
      
      # Import skill functions
      import unquote(skill_module)
    end
  end
end

defmodule DSPEx.Skills.WebSearch do
  @moduledoc """
  Web search capabilities for DSPEx programs
  """
  
  def search(query, opts \\ []) do
    max_results = opts[:max_results] || 5
    search_engine = opts[:engine] || :google
    
    # Use Foundation's HTTP client with circuit breaker
    case Foundation.Services.HTTPClient.get(
      build_search_url(search_engine, query),
      headers: build_headers(search_engine),
      timeout: 10_000,
      retries: 3
    ) do
      {:ok, response} ->
        results = parse_search_results(response.body, search_engine)
        {:ok, Enum.take(results, max_results)}
        
      {:error, reason} ->
        {:error, {:search_failed, reason}}
    end
  end
  
  def search_with_embeddings(query, opts \\ []) do
    # Combine traditional search with semantic search
    with {:ok, traditional_results} <- search(query, opts),
         {:ok, embedding} <- DSPEx.Embeddings.embed(query),
         {:ok, semantic_results} <- DSPEx.VectorDB.search(embedding, opts) do
      
      # Merge and rank results
      merged_results = merge_search_results(traditional_results, semantic_results)
      {:ok, merged_results}
    end
  end
end

defmodule DSPEx.Skills.Reasoning do
  @moduledoc """
  Reasoning capabilities for DSPEx programs
  """
  
  def chain_of_thought(question, context, opts \\ []) do
    steps = opts[:steps] || 3
    
    # Build reasoning chain
    reasoning_chain = 
      1..steps
      |> Enum.reduce([], fn step, chain ->
        prompt = build_reasoning_prompt(question, context, chain, step)
        
        case DSPEx.LLM.complete(prompt, temperature: 0.3) do
          {:ok, response} ->
            reasoning_step = %{
              step: step,
              thought: response.text,
              confidence: response.confidence
            }
            [reasoning_step | chain]
            
          {:error, _} ->
            chain
        end
      end)
      |> Enum.reverse()
    
    # Generate final answer based on reasoning chain
    final_prompt = build_final_answer_prompt(question, context, reasoning_chain)
    
    case DSPEx.LLM.complete(final_prompt) do
      {:ok, response} ->
        {:ok, %{
          answer: response.text,
          reasoning_chain: reasoning_chain,
          confidence: calculate_chain_confidence(reasoning_chain)
        }}
        
      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

## Production Features

### Monitoring and Observability
```elixir
defmodule DSPEx.Telemetry do
  @moduledoc """
  Production telemetry for DSPEx programs
  """
  
  def setup_telemetry do
    events = [
      [:dspex, :program, :executed],
      [:dspex, :optimization, :completed],
      [:dspex, :agent, :created],
      [:dspex, :error, :occurred]
    ]
    
    Enum.each(events, fn event ->
      :telemetry.attach(
        "dspex-#{Enum.join(event, "-")}",
        event,
        &handle_telemetry_event/4,
        %{}
      )
    end)
  end
  
  defp handle_telemetry_event([:dspex, :program, :executed], measurements, metadata, _config) do
    # Track execution metrics
    :telemetry.execute([:foundation, :metrics], %{
      execution_time: measurements.duration,
      cost: measurements.cost,
      tokens_used: measurements.tokens
    }, metadata)
    
    # Update program-specific dashboards
    Phoenix.PubSub.broadcast(
      Foundation.PubSub,
      "dspex:programs:#{metadata.program_id}",
      {:execution_completed, measurements}
    )
  end
end
```

### Cost Tracking and Optimization
```elixir
defmodule DSPEx.CostTracker do
  @moduledoc """
  Track and optimize costs across DSPEx programs
  """
  
  def track_execution_cost(program_id, config, result) do
    cost_data = %{
      program_id: program_id,
      configuration: config,
      tokens_used: result.tokens_used,
      model_cost: calculate_model_cost(config.model, result.tokens_used),
      execution_time: result.execution_time,
      timestamp: DateTime.utc_now()
    }
    
    # Store cost data
    Foundation.Services.Database.insert("program_costs", cost_data)
    
    # Check cost thresholds
    check_cost_thresholds(program_id, cost_data)
    
    cost_data
  end
  
  def optimize_for_cost(program_module, target_cost_reduction) do
    # Analyze cost patterns
    cost_analysis = analyze_program_costs(program_module)
    
    # Suggest optimizations
    optimizations = [
      suggest_model_alternatives(cost_analysis),
      suggest_prompt_optimizations(cost_analysis),
      suggest_caching_strategies(cost_analysis)
    ]
    
    # Apply optimizations that meet target reduction
    apply_cost_optimizations(program_module, optimizations, target_cost_reduction)
  end
end
```

## API Documentation

### Core DSPEx API
```elixir
# Program Definition
defmodule MyProgram do
  use DSPEx.Program
  # ... schema and predict/1 function
end

# Basic usage
result = MyProgram.predict(%{question: "What is AI?"})

# Optimization
optimized = DSPEx.optimize(MyProgram, training_data)

# Multi-agent conversion
{:ok, agents} = MyProgram.to_agent_system()

# Composition
composed = DSPEx.compose(ProgramA, ProgramB, strategy: :pipeline)

# Production deployment
{:ok, deployment} = DSPEx.deploy(MyProgram, 
  environment: :production,
  scaling: :auto,
  monitoring: :enabled
)
```

### Integration API
```elixir
# ElixirML integration
variable_space = DSPEx.extract_variables(MyProgram)
optimized_space = ElixirML.Variable.Space.optimize(variable_space, data)

# Foundation integration
{:ok, _pid} = DSPEx.start_supervised(MyProgram, name: :my_program)
result = DSPEx.call(:my_program, :predict, [input])

# MABEAM integration
{:ok, system} = DSPEx.MABEAM.create_system([MyProgram, OtherProgram])
{:ok, result} = DSPEx.MABEAM.coordinate(system, task)
```

This technical design provides a complete specification for building the DSPEx interface on our simplified Foundation/Jido integration. The design leverages all the infrastructure work while providing an intuitive, powerful interface that automatically handles production concerns, optimization, and multi-agent coordination.