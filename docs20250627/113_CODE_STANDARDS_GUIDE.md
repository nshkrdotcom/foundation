# Foundation OS Code Standards Guide
**Version 1.0 - Comprehensive Standards for TDD Implementation**  
**Date: June 27, 2025**

## Executive Summary

This document establishes comprehensive code standards for implementing Foundation OS using Test-Driven Development (TDD), proper OTP design principles, and architectural best practices. These standards synthesize existing quality guidelines from CODE_QUALITY.md, supervision audits, concurrency patterns, and process hierarchy designs into a cohesive framework for reliable, maintainable code.

**Philosophy**: Production-grade code through TDD, OTP compliance, and architectural discipline  
**Approach**: Staged implementation with quality gates at every level  
**Enforcement**: Automated tooling with manual review checkpoints

## Core Design Principles

### 1. Test-Driven Development (TDD) Mandatory

**Red-Green-Refactor Cycle**:
```elixir
# 1. RED: Write failing test first
test "process registry registers agent with metadata" do
  metadata = %{type: :agent, capabilities: [:ml], name: "test_agent"}
  assert {:ok, entry} = Foundation.ProcessRegistry.register(self(), metadata)
  assert entry.metadata == metadata
end

# 2. GREEN: Minimal implementation to pass
def register(pid, metadata, namespace \\ :default) do
  # Minimal implementation
  {:ok, %{pid: pid, metadata: metadata, namespace: namespace}}
end

# 3. REFACTOR: Improve implementation while keeping tests green
def register(pid, metadata, namespace \\ :default) do
  with {:ok, validated_metadata} <- validate_metadata(metadata),
       {:ok, entry} <- do_register(pid, validated_metadata, namespace) do
    {:ok, entry}
  else
    {:error, reason} -> {:error, Error.new(:validation, :invalid_metadata, reason)}
  end
end
```

**TDD Quality Gates**:
- [ ] All code has tests written first
- [ ] Minimum 95% test coverage
- [ ] Property-based tests for complex logic
- [ ] Integration tests for system boundaries
- [ ] No production code without corresponding tests

### 2. OTP Design Patterns (Mandatory)

Based on OTP supervision audits and process hierarchy analysis:

#### **Supervision Tree Architecture**
```elixir
# CORRECT: Proper supervision hierarchy
Foundation.Application (Supervisor)
├── Foundation.ProcessRegistry (GenServer)
├── Foundation.ServiceRegistry (GenServer)  
├── Foundation.TaskSupervisor (DynamicSupervisor)
├── Foundation.HealthMonitor (GenServer)
└── Foundation.ServiceMonitor (GenServer)
```

#### **Forbidden Patterns**
```elixir
# ❌ FORBIDDEN: Unsupervised processes
spawn(fn -> long_running_task() end)
Task.start(fn -> background_work() end)
spawn_link(fn -> coordination_loop() end)

# ❌ FORBIDDEN: Mixed supervisor behaviors  
defmodule BadSupervisor do
  use DynamicSupervisor
  
  def handle_call(...), do: ... # Wrong: No GenServer callbacks in DynamicSupervisor
end

# ❌ FORBIDDEN: Process.sleep for coordination
def wait_for_process do
  Process.sleep(100)  # Wrong: Violates SLEEP.md principles
  check_status()
end
```

#### **Required Patterns**
```elixir
# ✅ REQUIRED: Supervised processes
Task.Supervisor.start_child(Foundation.TaskSupervisor, fn -> 
  background_work() 
end)

# ✅ REQUIRED: Proper GenServer structure
defmodule Foundation.ServiceMonitor do
  use GenServer
  
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end
  
  @impl true
  def init(opts), do: {:ok, initial_state(opts)}
end

# ✅ REQUIRED: Message-based coordination
def wait_for_ready(pid) do
  receive do
    {:ready, ^pid} -> :ok
  after
    5000 -> {:error, :timeout}
  end
end
```

### 3. Asynchronous Communication (Mandatory)

Following concurrency patterns guide:

```elixir
# ✅ PREFERRED: Asynchronous cast
GenServer.cast(worker_pid, {:process_data, data})

# ⚠️ AVOID: Synchronous call unless response needed
GenServer.call(worker_pid, {:process_data, data})  # Only if result required

# ✅ REQUIRED: Event-driven architecture
Foundation.Telemetry.execute([:foundation, :data, :processed], %{count: 1}, %{
  worker_id: worker_id,
  processing_time: duration
})

# ✅ REQUIRED: Proper timeout handling
GenServer.call(worker_pid, request, 5000)  # Always specify timeout
```

## Code Structure Standards

### 1. Module Organization

Based on CODE_QUALITY.md and architectural analysis:

```elixir
defmodule Foundation.ProcessRegistry do
  @moduledoc """
  Universal process registration and discovery service.
  
  Provides foundation for agent management without agent-specific logic.
  Follows backend abstraction pattern for pluggable storage.
  
  ## Examples
  
      iex> metadata = %{type: :agent, capabilities: [:ml]}
      iex> {:ok, entry} = Foundation.ProcessRegistry.register(self(), metadata)
      iex> {:ok, ^entry} = Foundation.ProcessRegistry.lookup(self())
  """
  
  # 1. Module attributes and types
  @enforce_keys [:pid, :metadata, :namespace, :registered_at]
  defstruct @enforce_keys
  
  @type t :: %__MODULE__{
    pid: pid(),
    metadata: metadata(),
    namespace: atom(),
    registered_at: DateTime.t()
  }
  
  @type metadata :: %{
    type: atom(),
    capabilities: [atom()],
    name: String.t() | atom(),
    restart_policy: :permanent | :temporary | :transient,
    custom_data: map()
  }
  
  # 2. Client API (public interface)
  @spec register(pid(), metadata(), atom()) :: 
    {:ok, t()} | {:error, Foundation.Types.Error.t()}
  def register(pid, metadata, namespace \\ :default)
  
  @spec lookup(pid() | atom(), atom()) ::
    {:ok, t()} | {:error, Foundation.Types.Error.t()}
  def lookup(identifier, namespace \\ :default)
  
  # 3. GenServer callbacks (if applicable)
  @impl true
  def init(opts), do: {:ok, initial_state(opts)}
  
  @impl true  
  def handle_call({:register, pid, metadata, namespace}, _from, state) do
    # Implementation
  end
  
  # 4. Private helper functions
  defp validate_metadata(metadata), do: ...
  defp build_registry_entry(pid, metadata, namespace), do: ...
end
```

### 2. Type Specifications (Mandatory)

```elixir
# ✅ REQUIRED: @type t for all structs
@type t :: %__MODULE__{
  field1: type1(),
  field2: type2()
}

# ✅ REQUIRED: @spec for all public functions
@spec function_name(arg1_type(), arg2_type()) :: return_type()

# ✅ REQUIRED: Custom types for domain concepts
@type agent_id :: String.t()
@type capability :: atom()
@type coordination_result :: %{
  success: boolean(),
  assignments: %{agent_id() => term()},
  metrics: map()
}

# ✅ REQUIRED: Union types for error handling
@type result(success_type) :: {:ok, success_type} | {:error, Foundation.Types.Error.t()}
```

### 3. Error Handling Standards

Based on error standardization requirements:

```elixir
# ✅ REQUIRED: Use Foundation.Types.Error everywhere
alias Foundation.Types.Error

def register_agent(config) do
  with {:ok, validated_config} <- validate_config(config),
       {:ok, pid} <- start_agent_process(validated_config),
       {:ok, entry} <- register_in_system(pid, validated_config) do
    {:ok, entry}
  else
    {:error, %Error{} = error} -> {:error, error}
    {:error, reason} -> {:error, Error.new(:agent_management, :registration_failed, 
                                          inspect(reason))}
  end
end

# ✅ REQUIRED: Proper error context
Error.new(:validation, :invalid_config, "Configuration validation failed", %{
  field: :capabilities,
  value: invalid_value,
  constraint: "must be list of atoms"
})

# ✅ REQUIRED: Error chaining for debugging
Error.wrap(original_error, :coordination, :auction_failed, 
          "Agent auction coordination failed")
```

### 4. Documentation Standards

```elixir
defmodule Foundation.Coordination.Auction do
  @moduledoc """
  Economic auction protocols for multi-agent coordination.
  
  Implements various auction mechanisms including:
  - First-price sealed-bid auctions
  - Second-price sealed-bid auctions  
  - English (ascending) auctions
  - Dutch (descending) auctions
  
  ## Architecture
  
  The auction system follows the Actor model with:
  - Auctioneer: Manages auction lifecycle and rules
  - Bidders: Submit bids according to auction protocol
  - Observers: Monitor auction progress and outcomes
  
  ## Examples
  
      iex> auction_spec = %{type: :first_price, reserve_price: 100}
      iex> participants = [agent1, agent2, agent3]
      iex> {:ok, result} = Auction.run_auction(auction_spec, participants)
      iex> assert result.winner != nil
      iex> assert result.winning_bid >= 100
      
  ## Configuration
  
  Auctions can be configured with:
  - `:timeout` - Maximum auction duration (default: 30_000ms)
  - `:reserve_price` - Minimum acceptable bid (optional)
  - `:increment` - Minimum bid increment for English auctions
  """
  
  @type auction_spec :: %{
    type: :first_price | :second_price | :english | :dutch,
    reserve_price: non_neg_integer() | nil,
    timeout: pos_integer(),
    increment: pos_integer() | nil
  }
  
  @type participant :: %{
    agent_id: String.t(),
    capabilities: [atom()],
    resource_constraints: map()
  }
  
  @type auction_result :: %{
    success: boolean(),
    winner: participant() | nil,
    winning_bid: non_neg_integer() | nil,
    total_bids: non_neg_integer(),
    duration_ms: non_neg_integer()
  }
  
  @doc """
  Runs an auction with the specified parameters.
  
  ## Parameters
  
  - `auction_spec`: Configuration for the auction mechanism
  - `participants`: List of agents eligible to participate
  - `opts`: Additional options (see module documentation)
  
  ## Returns
  
  - `{:ok, auction_result()}` on successful auction completion
  - `{:error, Foundation.Types.Error.t()}` on auction failure
  
  ## Examples
  
      # Simple first-price auction
      auction_spec = %{type: :first_price, reserve_price: 50}
      participants = [%{agent_id: "agent1", capabilities: [:ml]}]
      {:ok, result} = Auction.run_auction(auction_spec, participants)
      
      # English auction with custom timeout
      auction_spec = %{type: :english, increment: 10}
      {:ok, result} = Auction.run_auction(auction_spec, participants, timeout: 60_000)
  """
  @spec run_auction(auction_spec(), [participant()], keyword()) :: 
    {:ok, auction_result()} | {:error, Foundation.Types.Error.t()}
  def run_auction(auction_spec, participants, opts \\ [])
end
```

## Testing Standards

### 1. Test Structure and Organization

```elixir
defmodule Foundation.ProcessRegistryTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  
  alias Foundation.ProcessRegistry
  alias Foundation.Types.Error
  
  # Test data setup
  setup do
    # Clean slate for each test
    ProcessRegistry.clear_namespace(:test)
    %{namespace: :test}
  end
  
  describe "register/3" do
    test "successfully registers process with valid metadata", %{namespace: namespace} do
      metadata = %{
        type: :agent,
        capabilities: [:ml_optimization],
        name: "test_agent"
      }
      
      assert {:ok, entry} = ProcessRegistry.register(self(), metadata, namespace)
      assert entry.pid == self()
      assert entry.metadata == metadata
      assert entry.namespace == namespace
      assert %DateTime{} = entry.registered_at
    end
    
    test "returns error for invalid metadata", %{namespace: namespace} do
      invalid_metadata = %{type: :unknown_type}
      
      assert {:error, %Error{} = error} = ProcessRegistry.register(self(), invalid_metadata, namespace)
      assert error.category == :validation
      assert error.code == :invalid_metadata
    end
    
    property "handles concurrent registrations correctly" do
      check all process_count <- integer(1..20),
                names <- list_of(string(:alphanumeric), length: process_count) do
        
        # Create test processes
        processes = Enum.map(1..process_count, fn _ ->
          spawn(fn -> Process.sleep(:infinity) end)
        end)
        
        # Register concurrently
        tasks = Enum.zip(processes, names)
        |> Enum.map(fn {pid, name} ->
          Task.async(fn ->
            metadata = %{type: :agent, name: name, capabilities: []}
            ProcessRegistry.register(pid, metadata, :test)
          end)
        end)
        
        results = Task.await_many(tasks, 5000)
        
        # All registrations should succeed
        assert Enum.all?(results, &match?({:ok, _}, &1))
        
        # Cleanup
        Enum.each(processes, &Process.exit(&1, :kill))
      end
    end
  end
  
  describe "lookup/2" do
    setup %{namespace: namespace} do
      metadata = %{type: :agent, name: "lookup_test", capabilities: [:test]}
      {:ok, entry} = ProcessRegistry.register(self(), metadata, namespace)
      %{entry: entry}
    end
    
    test "finds process by name", %{entry: entry, namespace: namespace} do
      assert {:ok, found_entry} = ProcessRegistry.lookup("lookup_test", namespace)
      assert found_entry.pid == entry.pid
    end
    
    test "returns not_found for non-existent process", %{namespace: namespace} do
      assert {:error, %Error{} = error} = ProcessRegistry.lookup("nonexistent", namespace)
      assert error.category == :not_found
      assert error.code == :process_not_found
    end
  end
end
```

### 2. Integration Testing Standards

```elixir
defmodule Foundation.IntegrationTest do
  use ExUnit.Case, async: false  # Integration tests not async
  
  alias Foundation.ProcessRegistry
  alias Foundation.ServiceRegistry
  
  describe "service discovery integration" do
    test "service registry integrates with process registry" do
      # Start a mock service
      {:ok, service_pid} = MockService.start_link(name: :test_service)
      
      # Register service
      service_config = %{
        name: :test_service,
        type: :worker,
        capabilities: [:data_processing]
      }
      
      assert {:ok, _} = ServiceRegistry.register_service(service_pid, service_config)
      
      # Verify integration
      assert {:ok, found_pid} = ServiceRegistry.find_service(:test_service)
      assert found_pid == service_pid
      
      # Verify process registry integration
      assert {:ok, entry} = ProcessRegistry.lookup(service_pid)
      assert entry.metadata.type == :worker
      
      # Cleanup
      GenServer.stop(service_pid)
    end
  end
end
```

### 3. Performance Testing Standards

```elixir
defmodule Foundation.PerformanceTest do
  use ExUnit.Case, async: false
  
  @moduletag :performance
  @moduletag timeout: 300_000  # 5 minutes for performance tests
  
  describe "process registry performance" do
    test "handles high-volume concurrent registrations" do
      process_count = 1000
      namespace = :performance_test
      
      {time_microseconds, results} = :timer.tc(fn ->
        1..process_count
        |> Task.async_stream(fn i ->
          pid = spawn(fn -> Process.sleep(:infinity) end)
          metadata = %{
            type: :agent,
            name: "perf_agent_#{i}",
            capabilities: [:performance_test]
          }
          ProcessRegistry.register(pid, metadata, namespace)
        end, max_concurrency: 50, timeout: 30_000)
        |> Enum.to_list()
      end)
      
      # All registrations should succeed
      success_count = Enum.count(results, &match?({:ok, {:ok, _}}, &1))
      assert success_count == process_count
      
      # Performance assertion
      time_seconds = time_microseconds / 1_000_000
      registrations_per_second = process_count / time_seconds
      
      assert registrations_per_second > 100  # At least 100 registrations/sec
      
      IO.puts("Performance: #{registrations_per_second} registrations/second")
    end
  end
end
```

## Quality Assurance Automation

### 1. Pre-commit Hooks

```bash
#!/bin/sh
# .git/hooks/pre-commit

echo "Running Foundation OS quality checks..."

# 1. Format code
echo "Formatting code..."
mix format --check-formatted || {
  echo "Code formatting required. Run: mix format"
  exit 1
}

# 2. Run tests with coverage
echo "Running tests with coverage..."
mix test --cover || {
  echo "Tests failed"
  exit 1
}

# 3. Check test coverage threshold
echo "Checking test coverage..."
mix test.coverage --threshold 95 || {
  echo "Test coverage below 95%"
  exit 1
}

# 4. Run Credo for code quality
echo "Running Credo..."
mix credo --strict || {
  echo "Credo quality checks failed"
  exit 1
}

# 5. Run Dialyzer for type checking
echo "Running Dialyzer..."
mix dialyzer || {
  echo "Type checking failed"
  exit 1
}

# 6. Check for forbidden patterns
echo "Checking for anti-patterns..."
./scripts/check_antipatterns.sh || {
  echo "Anti-pattern violations found"
  exit 1
}

echo "All quality checks passed!"
```

### 2. Anti-Pattern Detection Script

```bash
#!/bin/bash
# scripts/check_antipatterns.sh

echo "Checking for forbidden patterns..."

# Check for unsupervised spawn calls
if grep -r "spawn(" lib/ --include="*.ex" | grep -v "# Approved:"; then
  echo "ERROR: Found unsupervised spawn() calls in lib/"
  echo "Use Task.Supervisor.start_child/2 instead"
  exit 1
fi

# Check for Process.sleep calls
if grep -r "Process.sleep" lib/ --include="*.ex"; then
  echo "ERROR: Found Process.sleep calls in lib/"
  echo "Use message-based coordination instead"
  exit 1
fi

# Check for mixed supervisor behaviors
if grep -A 10 "use DynamicSupervisor" lib/**/*.ex | grep "handle_call\|handle_cast\|handle_info"; then
  echo "ERROR: Found GenServer callbacks in DynamicSupervisor"
  echo "Separate DynamicSupervisor from GenServer concerns"
  exit 1
fi

# Check for missing type specs on public functions
python3 scripts/check_typespecs.py lib/ || exit 1

echo "Anti-pattern checks passed!"
```

### 3. CI/CD Pipeline Configuration

```yaml
# .github/workflows/quality.yml
name: Foundation OS Quality Pipeline

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        elixir: ['1.15', '1.16']
        otp: ['25', '26']
    
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: ${{ matrix.elixir }}
          otp-version: ${{ matrix.otp }}
      
      - name: Cache deps
        uses: actions/cache@v3
        with:
          path: deps
          key: deps-${{ runner.os }}-${{ matrix.otp }}-${{ matrix.elixir }}-${{ hashFiles('**/mix.lock') }}
      
      - name: Install dependencies
        run: mix deps.get
      
      - name: Check formatting
        run: mix format --check-formatted
      
      - name: Run tests with coverage
        run: mix test --cover
        env:
          MIX_ENV: test
      
      - name: Verify test coverage
        run: mix test.coverage --threshold 95
      
      - name: Run Credo
        run: mix credo --strict
      
      - name: Run Dialyzer
        run: mix dialyzer --halt-exit-status
      
      - name: Check anti-patterns
        run: ./scripts/check_antipatterns.sh
      
      - name: Run integration tests
        run: mix test --only integration
        if: matrix.elixir == '1.16' && matrix.otp == '26'
      
      - name: Upload coverage reports
        uses: codecov/codecov-action@v3
        with:
          file: ./cover/excoveralls.json
        if: matrix.elixir == '1.16' && matrix.otp == '26'
```

## Development Workflow

### 1. Feature Development Process

```bash
# 1. Start with failing test
git checkout -b feature/agent-coordination
echo "Write failing test first" > TODO.md

# 2. TDD cycle
mix test                    # Should fail
# Write minimal implementation
mix test                    # Should pass
# Refactor while keeping tests green
mix test                    # Should still pass

# 3. Quality checks
mix format
mix credo --strict
mix dialyzer
./scripts/check_antipatterns.sh

# 4. Integration verification
mix test --only integration

# 5. Performance verification (if applicable)
mix test --only performance
```

### 2. Code Review Checklist

**Architecture Review**:
- [ ] Follows OTP supervision patterns
- [ ] No unsupervised processes
- [ ] Proper separation of concerns
- [ ] Error handling uses Foundation.Types.Error
- [ ] No Process.sleep for coordination

**Code Quality Review**:
- [ ] All public functions have @spec
- [ ] All structs have @type t
- [ ] Comprehensive @moduledoc and @doc
- [ ] Follows naming conventions
- [ ] No code duplication

**Testing Review**:
- [ ] Tests written before implementation (TDD)
- [ ] Property-based tests for complex logic
- [ ] Integration tests for system boundaries
- [ ] Performance tests for critical paths
- [ ] Coverage >95% for new code

**Security Review**:
- [ ] No hardcoded secrets or credentials
- [ ] Input validation for all external data
- [ ] Proper error message sanitization
- [ ] Resource limits and timeouts

### 3. Staged Implementation Approach

**Phase 1: Foundation Layer**
```bash
# Week 1: Core registry and error system
mix test test/foundation/process_registry_test.exs
mix test test/foundation/types/error_test.exs

# Week 2: Service coordination
mix test test/foundation/service_registry_test.exs
mix test test/foundation/coordination_test.exs

# Week 3: Infrastructure services
mix test test/foundation/infrastructure_test.exs
mix test test/foundation/telemetry_test.exs
```

**Phase 2: Integration Layer**
```bash
# Week 4-5: Jido integration
mix test test/foundation_jido/agent_test.exs
mix test test/foundation_jido/signal_test.exs

# Week 6: Error standardization
mix test test/foundation_jido/error_bridge_test.exs
```

**Phase 3: DSPEx Layer**
```bash
# Week 7-8: ML integration
mix test test/dspex/program_test.exs
mix test test/dspex/jido_integration_test.exs

# Week 9: Multi-agent coordination
mix test test/dspex/coordination_test.exs
```

## Performance and Scalability Standards

### 1. Performance Targets

**Foundation Layer**:
- Process registry: <1ms lookup latency
- Service discovery: <5ms resolution time
- Error creation: <0.1ms overhead
- Telemetry emission: <0.5ms overhead

**Integration Layer**:
- Agent registration: <10ms end-to-end
- Signal dispatch: <2ms local dispatch
- Error conversion: <0.2ms overhead
- Cross-layer calls: <5ms latency

**DSPEx Layer**:
- Program execution: <100ms for simple programs
- Variable validation: <1ms per variable
- Multi-agent coordination: <30s for team coordination
- Optimization iteration: <10s per iteration

### 2. Resource Limits

```elixir
# Process memory limits
{:ok, pid} = Agent.start_link(fn -> %{} end, [
  max_heap_size: %{
    size: 1_000_000,    # 1MB heap limit
    kill: true,         # Kill on exceed
    error_logger: true  # Log violations
  }
])

# Process message queue limits  
Process.flag(:message_queue_data, :off_heap)
Process.flag(:min_heap_size, 1000)

# System resource monitoring
if :erlang.memory(:total) > 1_000_000_000 do  # 1GB limit
  Logger.error("System memory usage exceeded limit")
  System.halt(1)
end
```

### 3. Scalability Patterns

```elixir
# Horizontal scaling pattern
def scale_agents(target_count) do
  current_count = MABEAM.AgentRegistry.count_active_agents()
  
  cond do
    current_count < target_count ->
      spawn_additional_agents(target_count - current_count)
    current_count > target_count ->
      terminate_excess_agents(current_count - target_count)
    true ->
      :no_scaling_needed
  end
end

# Load balancing pattern
def distribute_workload(tasks, agents) do
  agent_loads = Enum.map(agents, &get_agent_load/1)
  
  tasks
  |> Enum.zip(Stream.cycle(agents))
  |> Enum.each(fn {task, agent} ->
    if get_agent_load(agent) < max_load_threshold() do
      assign_task(agent, task)
    else
      queue_task(task)
    end
  end)
end
```

## Conclusion

This comprehensive code standards guide provides the foundation for implementing Foundation OS with:

1. **TDD Discipline**: All code developed test-first with comprehensive coverage
2. **OTP Compliance**: Proper supervision, process management, and fault tolerance
3. **Quality Automation**: Continuous validation of code quality and architectural patterns
4. **Performance Assurance**: Clear targets and monitoring for system performance
5. **Staged Implementation**: Incremental development with quality gates

**Key Success Factors**:
- Mandatory TDD with >95% coverage
- Zero tolerance for OTP anti-patterns
- Automated quality enforcement
- Clear performance targets
- Comprehensive documentation

Following these standards ensures Foundation OS will be production-ready, maintainable, and scalable from day one. The emphasis on quality automation and TDD provides confidence for the complex architectural transformation ahead.