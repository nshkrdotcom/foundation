# Foundation/Jido System

A production-grade multi-agent platform for Elixir/BEAM that combines protocol-based infrastructure with autonomous agent orchestration capabilities.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Key Features](#key-features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Core Components](#core-components)
- [Usage Examples](#usage-examples)
- [Testing](#testing)
- [Development](#development)
- [Contributing](#contributing)
- [License](#license)

## Overview

The Foundation/Jido System is a comprehensive platform for building distributed, autonomous agent systems on the BEAM. It provides:

- **Protocol-based infrastructure** with swappable implementations
- **Multi-agent orchestration** with built-in coordination primitives
- **Production-grade services** including circuit breakers, rate limiting, and monitoring
- **Unified telemetry** and observability across all components
- **Fault-tolerant supervision** following OTP principles

## Architecture

The system is organized into five main layers:

### 1. Foundation Protocol Layer
Protocol-based abstractions for core infrastructure:
- `Foundation.Registry` - Service registration and discovery
- `Foundation.Coordination` - Distributed consensus and synchronization
- `Foundation.Infrastructure` - Circuit breakers, rate limiting, protected execution

### 2. MABEAM Implementation Layer
Multi-agent BEAM implementations of Foundation protocols:
- `MABEAM.AgentRegistry` - Agent-specific registration with capabilities
- `MABEAM.AgentCoordination` - Multi-agent consensus and barriers
- `MABEAM.AgentInfrastructure` - Agent-aware circuit breakers and rate limiting

### 3. Foundation Services Layer
Core infrastructure services:
- **RetryService** - Resilient retries with exponential backoff
- **ConnectionManager** - HTTP connection pooling
- **RateLimiter** - Token bucket rate limiting
- **SignalBus** - Event routing system
- **DependencyManager** - Service dependency tracking
- **HealthChecker** - Unified health monitoring

### 4. JidoSystem Agent Framework
Agent programming model and runtime:
- **Agents** - FoundationAgent, TaskAgent, MonitorAgent, CoordinatorAgent
- **Actions** - Reusable agent behaviors
- **Sensors** - Performance and system monitoring
- **Workflows** - Multi-agent task orchestration

### 5. JidoFoundation Bridge Layer
Integration between Jido agents and Foundation infrastructure:
- Automatic agent registration
- Telemetry forwarding
- Signal routing
- Protected execution

## Key Features

### Production-Ready Infrastructure
- **Supervision trees** - Every process properly supervised
- **Circuit breakers** - Protect against cascading failures
- **Rate limiting** - Prevent resource exhaustion
- **Connection pooling** - Efficient resource usage
- **Retry mechanisms** - Handle transient failures gracefully

### Multi-Agent Capabilities
- **Agent lifecycle management** - Create, monitor, and terminate agents
- **Coordination primitives** - Barriers, consensus, leader election
- **Message passing** - Type-safe inter-agent communication
- **Workflow orchestration** - Complex multi-agent task flows
- **Capability-based discovery** - Find agents by their abilities

### Observability & Monitoring
- **Structured telemetry** - Consistent event naming and metadata
- **Performance monitoring** - Track agent and system performance
- **Health checks** - Unified health status across all components
- **Error tracking** - Centralized error collection and analysis
- **Load testing** - Built-in performance testing framework

### Developer Experience
- **Protocol-based design** - Clean abstractions and interfaces
- **Comprehensive testing** - Unit, integration, and property-based tests
- **Mox-based mocking** - Test in isolation with mock implementations
- **Clear error messages** - Helpful debugging information
- **Extensive documentation** - Inline docs and examples

## Installation

Add `foundation` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:foundation, "~> 0.2.0"}
  ]
end
```

## Quick Start

### Basic Agent Example

```elixir
# Define an agent
defmodule MyAgent do
  use JidoSystem.Agents.FoundationAgent
  
  def handle_action(:greet, %{name: name}, state) do
    {:ok, "Hello, #{name}!", state}
  end
end

# Start the agent
{:ok, agent} = JidoSystem.start_agent(MyAgent, %{})

# Execute an action
{:ok, greeting} = JidoSystem.execute_action(agent, :greet, %{name: "Alice"})
# => "Hello, Alice!"
```

### Multi-Agent Workflow

```elixir
# Define a workflow
workflow = %JidoSystem.Workflows.Workflow{
  id: "data-processing",
  name: "Data Processing Pipeline",
  agents: [
    %{id: "fetcher", module: DataFetcher, config: %{}},
    %{id: "processor", module: DataProcessor, config: %{}},
    %{id: "validator", module: DataValidator, config: %{}}
  ],
  tasks: [
    %{id: "fetch", agent: "fetcher", action: :fetch_data},
    %{id: "process", agent: "processor", action: :process, depends_on: ["fetch"]},
    %{id: "validate", agent: "validator", action: :validate, depends_on: ["process"]}
  ]
}

# Execute the workflow
{:ok, results} = JidoSystem.Workflows.Engine.execute(workflow, %{source: "api"})
```

### Protected External Calls

```elixir
# Use circuit breakers for external calls
{:ok, result} = Foundation.Infrastructure.protected_call(
  :my_service,
  fn -> HTTPClient.get("https://api.example.com/data") end,
  circuit_breaker: true,
  retry: [max_attempts: 3, backoff: :exponential]
)
```

## Core Components

### Foundation Protocols

#### Registry Protocol
```elixir
# Register a service
Foundation.Registry.register(:my_service, self(), %{capabilities: [:compute, :store]})

# Discover services
{:ok, services} = Foundation.Registry.lookup_by_capability(:compute)
```

#### Coordination Protocol
```elixir
# Distributed consensus
{:ok, leader} = Foundation.Coordination.elect_leader(:my_cluster)

# Synchronization barrier
{:ok, _} = Foundation.Coordination.barrier(:checkpoint, 3)
```

#### Infrastructure Protocol
```elixir
# Rate limiting
{:ok, result} = Foundation.Infrastructure.rate_limited_call(
  :api_calls,
  fn -> perform_api_call() end,
  rate: 10,
  period: :second
)
```

### JidoSystem Agents

#### FoundationAgent
Base agent with automatic Foundation integration:
```elixir
defmodule MyWorker do
  use JidoSystem.Agents.FoundationAgent
  
  @impl true
  def init(config) do
    {:ok, %{tasks_processed: 0}}
  end
  
  @impl true
  def handle_action(:process_task, task, state) do
    # Process the task
    result = process(task)
    new_state = %{state | tasks_processed: state.tasks_processed + 1}
    {:ok, result, new_state}
  end
end
```

#### TaskAgent
High-performance task processing:
```elixir
{:ok, agent} = JidoSystem.start_agent(
  JidoSystem.Agents.TaskAgent,
  %{max_concurrent: 10, timeout: 5000}
)

# Queue tasks
JidoSystem.execute_action(agent, :queue_task, %{
  id: "task-1",
  payload: %{type: :compute, data: [1, 2, 3]}
})
```

#### MonitorAgent
System health monitoring:
```elixir
{:ok, monitor} = JidoSystem.start_agent(
  JidoSystem.Agents.MonitorAgent,
  %{check_interval: 5000}
)

# Get system health
{:ok, health} = JidoSystem.execute_action(monitor, :check_health, %{})
```

#### CoordinatorAgent
Multi-agent workflow orchestration:
```elixir
{:ok, coordinator} = JidoSystem.start_agent(
  JidoSystem.Agents.CoordinatorAgent,
  %{max_agents: 100}
)

# Coordinate a task across multiple agents
JidoSystem.execute_action(coordinator, :coordinate_task, %{
  task: %{type: :distributed_compute},
  agents: [agent1, agent2, agent3]
})
```

### Foundation Services

#### RetryService
```elixir
Foundation.Services.Retry.with_retry(
  fn -> unstable_operation() end,
  max_attempts: 5,
  backoff: {:exponential, 100}
)
```

#### RateLimiter
```elixir
# Configure rate limits
Foundation.Services.RateLimiter.configure(:api, rate: 100, period: :minute)

# Check and consume tokens
case Foundation.Services.RateLimiter.check_rate(:api) do
  :ok -> perform_operation()
  {:error, :rate_limited} -> {:error, "Too many requests"}
end
```

#### HealthChecker
```elixir
# Register health checks
Foundation.Services.HealthChecker.register_check(:database, fn ->
  case Database.ping() do
    :ok -> {:ok, %{status: :healthy}}
    _ -> {:error, %{status: :unhealthy}}
  end
end)

# Get overall health
{:ok, health} = Foundation.Services.HealthChecker.check_health()
```

## Usage Examples

### Building a Data Processing Pipeline

```elixir
defmodule DataPipeline do
  def process_data(source) do
    # Create specialized agents
    {:ok, fetcher} = JidoSystem.start_agent(DataFetchAgent, %{source: source})
    {:ok, transformer} = JidoSystem.start_agent(DataTransformAgent, %{})
    {:ok, validator} = JidoSystem.start_agent(DataValidateAgent, %{})
    
    # Create a coordinator
    {:ok, coordinator} = JidoSystem.start_agent(
      JidoSystem.Agents.CoordinatorAgent,
      %{}
    )
    
    # Define the workflow
    workflow = %{
      steps: [
        %{agent: fetcher, action: :fetch, id: "fetch"},
        %{agent: transformer, action: :transform, id: "transform", depends_on: ["fetch"]},
        %{agent: validator, action: :validate, id: "validate", depends_on: ["transform"]}
      ]
    }
    
    # Execute the pipeline
    JidoSystem.execute_action(coordinator, :execute_workflow, workflow)
  end
end
```

### Implementing a Distributed Task Queue

```elixir
defmodule DistributedQueue do
  def start_workers(count) do
    # Start multiple task agents
    workers = for i <- 1..count do
      {:ok, agent} = JidoSystem.start_agent(
        JidoSystem.Agents.TaskAgent,
        %{
          name: "worker-#{i}",
          max_concurrent: 5,
          timeout: 30_000
        }
      )
      agent
    end
    
    # Start a coordinator to distribute work
    {:ok, coordinator} = JidoSystem.start_agent(
      JidoSystem.Agents.CoordinatorAgent,
      %{
        workers: workers,
        strategy: :round_robin
      }
    )
    
    {:ok, coordinator}
  end
  
  def enqueue_task(coordinator, task) do
    JidoSystem.execute_action(coordinator, :distribute_task, task)
  end
end
```

### Monitoring System Health

```elixir
defmodule SystemMonitor do
  def start_monitoring do
    # Start the monitor agent
    {:ok, monitor} = JidoSystem.start_agent(
      JidoSystem.Agents.MonitorAgent,
      %{
        check_interval: 5_000,
        alerts_enabled: true
      }
    )
    
    # Register custom health checks
    Foundation.Services.HealthChecker.register_check(:api, &check_api_health/0)
    Foundation.Services.HealthChecker.register_check(:database, &check_db_health/0)
    Foundation.Services.HealthChecker.register_check(:cache, &check_cache_health/0)
    
    # Set up telemetry handlers
    :telemetry.attach(
      "system-monitor",
      [:foundation, :health, :check, :complete],
      &handle_health_event/4,
      nil
    )
    
    {:ok, monitor}
  end
  
  defp handle_health_event(_event_name, measurements, metadata, _config) do
    if metadata.status == :unhealthy do
      # Send alert
      Logger.error("Health check failed: #{inspect(metadata)}")
    end
  end
end
```

## Testing

The system includes comprehensive testing utilities:

### Unit Testing with Mox

```elixir
defmodule MyAgentTest do
  use ExUnit.Case
  import Mox
  
  setup :verify_on_exit!
  
  test "agent processes task successfully" do
    # Mock the infrastructure
    expect(Foundation.Infrastructure.Mock, :protected_call, fn _, fun, _ ->
      fun.()
    end)
    
    {:ok, agent} = JidoSystem.start_agent(MyAgent, %{})
    {:ok, result} = JidoSystem.execute_action(agent, :process, %{data: [1, 2, 3]})
    
    assert result == [2, 4, 6]
  end
end
```

### Integration Testing

```elixir
defmodule WorkflowIntegrationTest do
  use Foundation.IntegrationCase
  
  @tag :integration
  test "complete workflow executes successfully" do
    # Start all required services
    start_supervised!(Foundation.Services.Supervisor)
    start_supervised!(JidoSystem.Supervisor)
    
    # Run the workflow
    {:ok, results} = DataPipeline.process_data("test-source")
    
    assert results.fetch.status == :success
    assert results.transform.status == :success
    assert results.validate.status == :success
  end
end
```

### Property-Based Testing

```elixir
defmodule RateLimiterPropertyTest do
  use ExUnit.Case
  use ExUnitProperties
  
  property "rate limiter never exceeds configured rate" do
    check all rate <- integer(1..100),
              period <- member_of([:second, :minute]),
              requests <- integer(1..200) do
      
      Foundation.Services.RateLimiter.configure(:test, rate: rate, period: period)
      
      allowed = Enum.reduce(1..requests, 0, fn _, acc ->
        case Foundation.Services.RateLimiter.check_rate(:test) do
          :ok -> acc + 1
          {:error, :rate_limited} -> acc
        end
      end)
      
      assert allowed <= rate
    end
  end
end
```

### Load Testing

```elixir
# Run load tests
mix foundation.load_test --workers 100 --duration 60 --rate 1000
```

## Development

### Project Structure

```
foundation/
├── lib/
│   ├── foundation/          # Core Foundation protocols and services
│   ├── foundation_web/      # Web interface (if applicable)
│   ├── jido_system/         # Jido agent framework
│   ├── jido_foundation/     # Bridge layer
│   └── mabeam/              # Multi-agent BEAM implementations
├── test/
│   ├── foundation/          # Foundation tests
│   ├── jido_system/         # Jido tests
│   └── integration/         # Integration tests
├── config/                  # Configuration files
├── priv/                    # Private resources
└── mix.exs                  # Project configuration
```

### Running Tests

```bash
# Run all tests
mix test

# Run only unit tests
mix test --exclude integration

# Run with coverage
mix test --cover

# Run property-based tests
mix test --only property

# Run load tests
mix foundation.load_test
```

### Code Quality

```bash
# Run static analysis
mix credo

# Run type checking
mix dialyzer

# Format code
mix format

# Run all checks
mix check
```

### Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/your-org/foundation.git
   cd foundation
   ```

2. Install dependencies:
   ```bash
   mix deps.get
   ```

3. Set up the database (if applicable):
   ```bash
   mix ecto.setup
   ```

4. Run tests to verify setup:
   ```bash
   mix test
   ```

## Contributing

We welcome contributions! Please see our [Contributing Guide](CONTRIBUTING.md) for details on:

- Code of Conduct
- Development process
- Submitting pull requests
- Reporting issues

### Contribution Guidelines

1. **Fork the repository** and create your branch from `main`
2. **Write tests** for any new functionality
3. **Ensure all tests pass** and code is formatted
4. **Update documentation** as needed
5. **Submit a pull request** with a clear description

## License

This project is licensed under the Apache License 2.0 - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Built on the solid foundation of Elixir/OTP
- Inspired by actor model and multi-agent systems research
- Thanks to all contributors and the Elixir community

---

For more information, detailed API documentation, and advanced usage examples, please visit our [documentation site](https://foundation-docs.example.com).