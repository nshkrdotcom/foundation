# Foundation OS Testing Strategy
**Version 1.0 - Comprehensive Testing Approach for Multi-Layer Integration**  
**Date: June 27, 2025**

## Executive Summary

This document defines a comprehensive testing strategy for Foundation OS, covering unit testing, integration testing, end-to-end workflows, performance testing, and chaos engineering across all system layers. The strategy ensures reliability, maintainability, and confidence in the dependency-based multi-agent platform.

**Testing Philosophy**: Shift-left testing with comprehensive coverage at every layer  
**Integration Focus**: Extensive testing of boundaries between Foundation, FoundationJido, and DSPEx  
**Quality Gates**: Automated testing prevents regressions and ensures production readiness

## Testing Architecture Overview

### Testing Pyramid Structure

```
                    ┌─────────────────────┐
                    │   E2E Tests (5%)    │  ← Full workflow testing
                    │   Chaos/Load Tests  │
                    └─────────────────────┘
              ┌─────────────────────────────────┐
              │    Integration Tests (20%)      │  ← Layer boundary testing
              │    Contract Tests               │
              └─────────────────────────────────┘
        ┌─────────────────────────────────────────────┐
        │         Unit Tests (75%)                    │  ← Component isolation testing
        │         Property-based Tests                │
        └─────────────────────────────────────────────┘
```

### Test Categories by Layer

**Foundation Layer Testing**:
- Unit tests for ProcessRegistry, Infrastructure services
- Contract tests for Foundation.Types.Error  
- Performance tests for core primitives
- Integration tests with mocked external dependencies

**FoundationJido Integration Testing**:
- Unit tests for error conversion and bridge modules
- Integration tests with real Jido libraries
- Contract tests for agent registration and signal dispatch
- Multi-agent coordination scenario testing

**DSPEx Layer Testing**:
- Unit tests for ML schemas, variables, and programs
- Integration tests for program-agent conversion
- Performance tests for optimization algorithms
- End-to-end ML workflow testing

---

## Unit Testing Strategy

### Foundation Layer Unit Tests

```elixir
# test/foundation/process_registry_test.exs
defmodule Foundation.ProcessRegistryTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  
  alias Foundation.ProcessRegistry
  alias Foundation.Types.Error
  
  describe "register/3" do
    test "successfully registers process with valid metadata" do
      metadata = %{
        type: :agent,
        capabilities: [:ml_optimization],
        name: "test_agent",
        restart_policy: :permanent
      }
      
      {:ok, entry} = ProcessRegistry.register(self(), metadata)
      
      assert entry.pid == self()
      assert entry.metadata == metadata
      assert entry.namespace == :default
      assert %DateTime{} = entry.registered_at
    end
    
    test "returns error for invalid metadata" do
      invalid_metadata = %{type: :unknown_type}
      
      {:error, %Error{} = error} = ProcessRegistry.register(self(), invalid_metadata)
      
      assert error.category == :validation
      assert error.code == :invalid_metadata
    end
    
    property "handles concurrent registrations correctly" do
      check all pids <- list_of(constant(self()), min_length: 1, max_length: 10),
                names <- list_of(string(:alphanumeric), length: length(pids)) do
        
        tasks = Enum.zip(pids, names)
        |> Enum.map(fn {pid, name} ->
          Task.async(fn ->
            metadata = %{type: :agent, name: name, capabilities: []}
            ProcessRegistry.register(pid, metadata)
          end)
        end)
        
        results = Task.await_many(tasks, 5000)
        
        # All registrations should succeed
        assert Enum.all?(results, &match?({:ok, _}, &1))
        
        # All entries should be findable
        Enum.each(names, fn name ->
          assert {:ok, _entry} = ProcessRegistry.lookup(name)
        end)
      end
    end
  end
  
  describe "lookup/2" do
    setup do
      metadata = %{type: :agent, name: "lookup_test", capabilities: [:test]}
      {:ok, entry} = ProcessRegistry.register(self(), metadata)
      %{entry: entry}
    end
    
    test "finds process by name", %{entry: entry} do
      {:ok, found_entry} = ProcessRegistry.lookup("lookup_test")
      assert found_entry.pid == entry.pid
    end
    
    test "finds process by PID", %{entry: entry} do
      {:ok, found_entry} = ProcessRegistry.lookup(entry.pid)
      assert found_entry.metadata.name == "lookup_test"
    end
    
    test "returns not_found for non-existent process" do
      {:error, %Error{} = error} = ProcessRegistry.lookup("nonexistent")
      assert error.category == :not_found
      assert error.code == :process_not_found
    end
  end
end
```

### Error Standardization Unit Tests

```elixir
# test/foundation/error_standardization_test.exs
defmodule Foundation.ErrorStandardizationTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  
  alias Foundation.Types.Error
  alias FoundationJido.ErrorBridge
  
  describe "Foundation.Types.Error" do
    test "creates error with automatic context capture" do
      error = Error.new(:validation, :test_error, "Test message")
      
      assert error.category == :validation
      assert error.code == :test_error
      assert error.message == "Test message"
      assert %DateTime{} = error.timestamp
      assert error.context.module == __MODULE__
      assert error.context.function == :test
    end
    
    test "chains errors correctly" do
      root_error = Error.new(:external, :api_error, "API failed")
      wrapped_error = Error.wrap(root_error, :internal, :processing_failed, "Processing failed")
      
      assert wrapped_error.caused_by == root_error
      assert length(wrapped_error.error_chain) == 2
      assert Error.root_cause(wrapped_error) == root_error
    end
    
    property "serialization round-trip preserves error data" do
      check all category <- member_of([:validation, :network, :timeout, :internal]),
                code <- atom(:alphanumeric),
                message <- string(:printable, min_length: 1, max_length: 100) do
        
        original_error = Error.new(category, code, message)
        
        # Test JSON serialization
        json_string = Error.to_json(original_error)
        {:ok, deserialized_error} = Error.from_json(json_string)
        
        assert deserialized_error.category == original_error.category
        assert deserialized_error.code == original_error.code
        assert deserialized_error.message == original_error.message
      end
    end
  end
  
  describe "Jido error conversion" do
    test "converts JidoAction errors with context preservation" do
      jido_error = %JidoAction.Error{
        type: :validation,
        code: :invalid_params,
        message: "Invalid parameters",
        details: %{field: :name, value: nil}
      }
      
      foundation_error = ErrorBridge.from_jido_action_error(jido_error)
      
      assert %Error{} = foundation_error
      assert foundation_error.category == :validation
      assert foundation_error.code == :invalid_params
      assert foundation_error.details == %{field: :name, value: nil}
      assert foundation_error.context.converted_from == :jido_action
    end
    
    test "handles unknown Jido error formats gracefully" do
      unknown_error = {:error, "Something went wrong"}
      
      foundation_error = ErrorBridge.from_jido_error(unknown_error)
      
      assert %Error{} = foundation_error
      assert foundation_error.category == :external
      assert foundation_error.code == :jido_error
    end
  end
end
```

### DSPEx Unit Tests with Property-Based Testing

```elixir
# test/dspex/variable_test.exs
defmodule DSPEx.VariableTest do
  use ExUnit.Case, async: true
  use ExUnitProperties
  
  alias DSPEx.Variable
  alias DSPEx.Variable.Space
  
  describe "Variable creation and validation" do
    property "float variables respect range constraints" do
      check all min_val <- float(min: -1000.0, max: 1000.0),
                max_val <- float(min: min_val, max: min_val + 1000.0),
                default_val <- float(min: min_val, max: max_val) do
        
        variable = Variable.float(:test_var, range: {min_val, max_val}, default: default_val)
        
        assert variable.type == :float
        assert variable.constraints.range == {min_val, max_val}
        assert variable.default == default_val
        
        # Test constraint validation
        assert Variable.validate_value(variable, default_val) == {:ok, default_val}
        assert Variable.validate_value(variable, min_val - 1) == {:error, :out_of_range}
        assert Variable.validate_value(variable, max_val + 1) == {:error, :out_of_range}
      end
    end
    
    property "choice variables only accept valid options" do
      check all options <- list_of(atom(:alphanumeric), min_length: 2, max_length: 10),
                default <- member_of(options) do
        
        variable = Variable.choice(:test_choice, options, default: default)
        
        assert variable.type == :choice
        assert variable.constraints.options == options
        assert variable.default == default
        
        # All options should be valid
        Enum.each(options, fn option ->
          assert Variable.validate_value(variable, option) == {:ok, option}
        end)
        
        # Non-options should be invalid
        invalid_option = :definitely_not_in_options
        refute invalid_option in options
        assert Variable.validate_value(variable, invalid_option) == {:error, :invalid_choice}
      end
    end
  end
  
  describe "Variable space management" do
    test "validates complete variable space configuration" do
      space = Space.new()
      |> Space.add_variable(Variable.float(:temperature, range: {0.0, 2.0}))
      |> Space.add_variable(Variable.choice(:provider, [:openai, :anthropic]))
      |> Space.add_variable(Variable.integer(:max_tokens, range: {1, 4000}))
      
      # Valid configuration
      valid_config = %{
        temperature: 0.7,
        provider: :openai,
        max_tokens: 1000
      }
      
      assert {:ok, validated_config} = Space.validate_configuration(space, valid_config)
      assert validated_config == valid_config
      
      # Invalid configuration
      invalid_config = %{
        temperature: 3.0,  # Out of range
        provider: :invalid,  # Invalid choice
        max_tokens: 5000  # Out of range
      }
      
      assert {:error, errors} = Space.validate_configuration(space, invalid_config)
      assert length(errors) == 3
    end
    
    property "random configuration generation produces valid configurations" do
      check all var_count <- integer(1..10) do
        # Create a variable space with random variables
        space = create_random_variable_space(var_count)
        
        # Generate random configuration
        {:ok, config} = Space.random_configuration(space)
        
        # Configuration should be valid
        assert {:ok, _} = Space.validate_configuration(space, config)
        
        # All required variables should be present
        required_vars = Space.get_required_variables(space)
        Enum.each(required_vars, fn var ->
          assert Map.has_key?(config, var.name)
        end)
      end
    end
  end
  
  # Helper function for property-based testing
  defp create_random_variable_space(var_count) do
    Enum.reduce(1..var_count, Space.new(), fn i, space ->
      var_name = String.to_atom("var_#{i}")
      variable = case rem(i, 3) do
        0 -> Variable.float(var_name, range: {0.0, 1.0})
        1 -> Variable.integer(var_name, range: {1, 100})
        2 -> Variable.choice(var_name, [:option_a, :option_b, :option_c])
      end
      Space.add_variable(space, variable)
    end)
  end
end
```

---

## Integration Testing Strategy

### Foundation-Jido Integration Tests

```elixir
# test/foundation_jido/integration_test.exs
defmodule FoundationJido.IntegrationTest do
  use ExUnit.Case, async: false  # Not async due to process registry state
  
  alias Foundation.ProcessRegistry
  alias FoundationJido.Agent.RegistryAdapter
  alias FoundationJido.Signal.FoundationDispatch
  
  setup do
    # Start test registry namespace
    {:ok, _} = ProcessRegistry.start_namespace(:test)
    on_exit(fn -> ProcessRegistry.stop_namespace(:test) end)
    %{namespace: :test}
  end
  
  describe "agent registration integration" do
    test "Jido agent registers with Foundation registry", %{namespace: namespace} do
      agent_config = %{
        name: "test_jido_agent",
        module: TestJidoAgent,
        capabilities: [:test_capability],
        namespace: namespace
      }
      
      # Register agent through integration layer
      {:ok, result} = RegistryAdapter.register_agent(agent_config)
      
      assert %{pid: pid, agent_id: agent_id, registry_entry: entry} = result
      assert is_pid(pid)
      assert agent_id == "test_jido_agent"
      
      # Verify agent is in Foundation registry
      {:ok, found_entry} = ProcessRegistry.lookup(pid, namespace)
      assert found_entry == entry
      assert found_entry.metadata.type == :agent
      assert :test_capability in found_entry.metadata.capabilities
      
      # Verify agent is actually a running Jido agent
      assert Process.alive?(pid)
      assert {:ok, :pong} = GenServer.call(pid, :ping)
    end
    
    test "agent registration failure is properly handled", %{namespace: namespace} do
      invalid_config = %{
        name: nil,  # Invalid name
        module: NonExistentModule,
        namespace: namespace
      }
      
      {:error, %Foundation.Types.Error{} = error} = RegistryAdapter.register_agent(invalid_config)
      
      assert error.category == :agent_management
      assert error.code == :agent_registration_failed
    end
  end
  
  describe "signal dispatch integration" do
    test "signal dispatches through Foundation infrastructure" do
      # Setup test signal target
      {:ok, target_pid} = start_test_signal_target()
      
      signal = JidoSignal.Signal.new(%{
        type: "test.message",
        data: %{message: "Hello from integration test"},
        source: "test_sender"
      })
      
      dispatch_config = %{
        type: :pid,
        target: target_pid,
        circuit_breaker: :test_circuit
      }
      
      # Dispatch through Foundation integration
      {:ok, result} = FoundationDispatch.dispatch(signal, dispatch_config)
      
      assert result.success == true
      assert is_number(result.duration_ms)
      assert result.attempts == 1
      
      # Verify target received the signal
      assert_receive {:signal_received, received_signal}
      assert received_signal.data.message == "Hello from integration test"
    end
    
    test "circuit breaker integration works correctly" do
      # Setup failing target to trigger circuit breaker
      signal = JidoSignal.Signal.new(%{type: "test.fail"})
      dispatch_config = %{type: :http, target: "http://localhost:99999", circuit_breaker: :test_http}
      
      # Multiple failures should open circuit breaker
      failures = Enum.map(1..5, fn _ ->
        FoundationDispatch.dispatch(signal, dispatch_config)
      end)
      
      assert Enum.all?(failures, &match?({:error, _}, &1))
      
      # Circuit breaker should now be open
      assert Foundation.Infrastructure.CircuitBreaker.status(:test_http) == :open
    end
  end
  
  describe "error conversion integration" do
    test "Jido errors are automatically converted to Foundation errors" do
      # Create a Jido agent that will produce an error
      {:ok, agent_pid} = start_failing_jido_agent()
      
      # Call through integration layer
      result = RegistryAdapter.execute_agent_action(agent_pid, :failing_action, %{})
      
      # Should receive Foundation error, not Jido error
      assert {:error, %Foundation.Types.Error{} = error} = result
      assert error.category == :agent_management
      assert error.context.converted_from == :jido_action
    end
  end
  
  # Test helpers
  defp start_test_signal_target do
    Agent.start_link(fn -> [] end, name: :test_signal_target)
    Agent.update(:test_signal_target, fn _ ->
      Process.register(self(), :signal_target)
      []
    end)
    {:ok, Process.whereis(:signal_target)}
  end
  
  defp start_failing_jido_agent do
    # Implementation of test agent that produces predictable errors
    # ... agent implementation
  end
end
```

### Contract Testing

```elixir
# test/contracts/api_contract_test.exs
defmodule APIContractTest do
  use ExUnit.Case
  
  alias Foundation.ProcessRegistry
  alias Foundation.Types.Error
  
  describe "Foundation.ProcessRegistry contract compliance" do
    test "register/3 returns contract-compliant response" do
      metadata = %{type: :agent, capabilities: [], name: "contract_test"}
      
      {:ok, entry} = ProcessRegistry.register(self(), metadata)
      
      # Verify response matches contract
      assert %{
        pid: pid,
        metadata: returned_metadata,
        registered_at: timestamp,
        namespace: namespace
      } = entry
      
      assert is_pid(pid)
      assert %DateTime{} = timestamp
      assert is_atom(namespace)
      assert returned_metadata == metadata
    end
    
    test "lookup/2 error response matches contract" do
      {:error, error} = ProcessRegistry.lookup("nonexistent")
      
      # Verify error structure matches contract
      assert %Error{
        category: :not_found,
        code: :process_not_found,
        message: message,
        timestamp: timestamp,
        context: context
      } = error
      
      assert is_binary(message)
      assert %DateTime{} = timestamp
      assert is_map(context)
    end
  end
  
  describe "FoundationJido.Agent contract compliance" do
    test "register_agent/1 returns contract-compliant response" do
      config = %{name: "contract_agent", capabilities: [:test]}
      
      {:ok, result} = FoundationJido.Agent.RegistryAdapter.register_agent(config)
      
      # Verify response matches contract
      assert %{
        pid: pid,
        agent_id: agent_id,
        registry_entry: entry
      } = result
      
      assert is_pid(pid)
      assert is_binary(agent_id) or is_atom(agent_id)
      assert %{pid: ^pid} = entry  # Registry entry should contain same PID
    end
  end
end
```

---

## End-to-End Testing Strategy

### Multi-Agent Workflow Tests

```elixir
# test/e2e/multi_agent_workflow_test.exs
defmodule E2E.MultiAgentWorkflowTest do
  use ExUnit.Case, async: false
  
  alias DSPEx.Program
  alias DSPEx.Jido.ProgramAgent
  alias FoundationJido.Coordination.Orchestrator
  
  @moduletag :e2e
  
  describe "complete multi-agent optimization workflow" do
    test "optimizes ML program using multi-agent coordination" do
      # Step 1: Create DSPEx program
      program = create_test_ml_program()
      training_data = generate_training_data()
      
      # Step 2: Convert program to agent
      {:ok, program_agent_pid} = ProgramAgent.start_program_agent(%{
        program: program,
        optimization_enabled: true,
        coordination_capabilities: [:optimization, :collaboration]
      })
      
      # Step 3: Start additional optimization agents
      {:ok, helper_agent1} = start_optimization_helper_agent(:simba_specialist)
      {:ok, helper_agent2} = start_optimization_helper_agent(:beacon_specialist)
      
      # Step 4: Setup coordination
      agent_specs = [
        %{agent_id: "program_agent", pid: program_agent_pid, capabilities: [:ml_execution, :optimization]},
        %{agent_id: "simba_agent", pid: helper_agent1, capabilities: [:simba_optimization]},
        %{agent_id: "beacon_agent", pid: helper_agent2, capabilities: [:beacon_optimization]}
      ]
      
      coordination_spec = %{
        coordination_type: :auction,
        objective: :maximize_performance,
        timeout: 30_000,
        convergence_threshold: 0.95
      }
      
      # Step 5: Execute multi-agent optimization
      {:ok, coordination_result} = Orchestrator.coordinate(agent_specs, coordination_spec)
      
      # Step 6: Verify results
      assert coordination_result.success == true
      assert coordination_result.assignments != %{}
      assert coordination_result.metrics.final_performance > 0.8
      assert coordination_result.duration_ms < 30_000
      
      # Step 7: Verify program was actually optimized
      {:ok, optimized_program} = ProgramAgent.get_current_program(program_agent_pid)
      
      # Test optimized program performance
      original_performance = test_program_performance(program, training_data)
      optimized_performance = test_program_performance(optimized_program, training_data)
      
      assert optimized_performance > original_performance
      
      # Step 8: Test optimized program execution
      test_input = %{text: "Test input for optimized program"}
      {:ok, result} = ProgramAgent.execute_program(program_agent_pid, %{inputs: test_input})
      
      assert result.outputs != %{}
      assert result.performance_metrics.execution_time < 5000  # Should be fast
      assert result.performance_metrics.confidence > 0.7
    end
    
    test "handles coordination failures gracefully" do
      # Test with insufficient agents
      agent_specs = [
        %{agent_id: "lonely_agent", pid: self(), capabilities: [:basic]}
      ]
      
      coordination_spec = %{
        coordination_type: :consensus,
        minimum_participants: 3,  # More than available
        timeout: 5000
      }
      
      {:error, error} = Orchestrator.coordinate(agent_specs, coordination_spec)
      
      assert error.category == :coordination
      assert error.code == :insufficient_agents
    end
    
    test "handles network partitions and recovery" do
      # Simulate network partition scenario
      # This would involve testing distributed coordination resilience
      # Implementation would depend on specific clustering setup
    end
  end
  
  describe "signal propagation across layers" do
    test "signals flow correctly from DSPEx through FoundationJido to Foundation" do
      # Setup signal tracing
      test_pid = self()
      :telemetry.attach("e2e-signal-trace", [:foundation, :signal, :dispatch], fn event, measurements, metadata, _ ->
        send(test_pid, {:telemetry, event, measurements, metadata})
      end, nil)
      
      # Start program agent that will emit signals
      {:ok, program_agent} = ProgramAgent.start_program_agent(%{
        program: create_signaling_program(),
        signal_enabled: true
      })
      
      # Execute program that triggers signal cascade
      {:ok, _result} = ProgramAgent.execute_program(program_agent, %{
        inputs: %{trigger_signals: true}
      })
      
      # Verify signal telemetry was emitted
      assert_receive {:telemetry, [:foundation, :signal, :dispatch], measurements, metadata}
      assert measurements.duration > 0
      assert metadata.layer == :dspex
      
      :telemetry.detach("e2e-signal-trace")
    end
  end
  
  # Test helper functions
  defp create_test_ml_program do
    # Create a simple ML program for testing
    DSPEx.Program.new(
      signature: "input_text -> output_text",
      predictor: TestPredictor,
      variable_space: create_test_variable_space()
    )
  end
  
  defp generate_training_data do
    # Generate synthetic training data
    Enum.map(1..10, fn i ->
      %{
        input: %{text: "Test input #{i}"},
        expected_output: %{text: "Expected output #{i}"}
      }
    end)
  end
  
  defp test_program_performance(program, training_data) do
    # Simple performance metric: accuracy on training data
    correct_predictions = Enum.count(training_data, fn example ->
      {:ok, prediction} = Program.predict(program, example.input)
      prediction.text == example.expected_output.text
    end)
    
    correct_predictions / length(training_data)
  end
  
  # ... additional helper functions
end
```

### Performance Integration Tests

```elixir
# test/performance/system_performance_test.exs
defmodule Performance.SystemPerformanceTest do
  use ExUnit.Case, async: false
  
  @moduletag :performance
  @moduletag timeout: 300_000  # 5 minutes timeout for performance tests
  
  describe "system performance under load" do
    test "handles concurrent agent registrations" do
      # Test concurrent agent registration performance
      agent_count = 100
      
      {time_microseconds, results} = :timer.tc(fn ->
        1..agent_count
        |> Task.async_stream(fn i ->
          config = %{name: "perf_agent_#{i}", capabilities: [:performance_test]}
          FoundationJido.Agent.RegistryAdapter.register_agent(config)
        end, max_concurrency: 20, timeout: 30_000)
        |> Enum.to_list()
      end)
      
      # All registrations should succeed
      success_count = Enum.count(results, &match?({:ok, {:ok, _}}, &1))
      assert success_count == agent_count
      
      # Performance assertion: should complete within reasonable time
      time_seconds = time_microseconds / 1_000_000
      agents_per_second = agent_count / time_seconds
      
      assert agents_per_second > 10  # At least 10 registrations per second
      IO.puts("Registered #{agent_count} agents in #{time_seconds}s (#{agents_per_second} agents/sec)")
    end
    
    test "signal dispatch performance under load" do
      # Setup multiple signal targets
      target_count = 50
      targets = Enum.map(1..target_count, fn i ->
        {:ok, pid} = Agent.start_link(fn -> [] end)
        {i, pid}
      end)
      
      # Send signals to all targets concurrently
      signal_count = 200
      
      {time_microseconds, results} = :timer.tc(fn ->
        1..signal_count
        |> Task.async_stream(fn i ->
          target_index = rem(i, target_count) + 1
          {_, target_pid} = Enum.find(targets, fn {index, _} -> index == target_index end)
          
          signal = JidoSignal.Signal.new(%{
            type: "performance.test",
            data: %{message: "Signal #{i}"}
          })
          
          config = %{type: :pid, target: target_pid}
          FoundationJido.Signal.FoundationDispatch.dispatch(signal, config)
        end, max_concurrency: 50, timeout: 60_000)
        |> Enum.to_list()
      end)
      
      # All dispatches should succeed
      success_count = Enum.count(results, &match?({:ok, {:ok, _}}, &1))
      assert success_count == signal_count
      
      # Performance assertion
      time_seconds = time_microseconds / 1_000_000
      signals_per_second = signal_count / time_seconds
      
      assert signals_per_second > 50  # At least 50 signals per second
      IO.puts("Dispatched #{signal_count} signals in #{time_seconds}s (#{signals_per_second} signals/sec)")
    end
    
    test "multi-agent coordination scales with agent count" do
      # Test coordination performance with different agent counts
      agent_counts = [5, 10, 20, 50]
      
      performance_results = Enum.map(agent_counts, fn count ->
        agents = start_test_agents(count)
        
        coordination_spec = %{
          coordination_type: :auction,
          objective: :minimize_cost,
          timeout: 30_000
        }
        
        {time_microseconds, result} = :timer.tc(fn ->
          FoundationJido.Coordination.Orchestrator.coordinate(agents, coordination_spec)
        end)
        
        cleanup_test_agents(agents)
        
        time_seconds = time_microseconds / 1_000_000
        {count, time_seconds, elem(result, 0)}
      end)
      
      # All coordinations should succeed
      Enum.each(performance_results, fn {count, time, status} ->
        assert status == :ok
        IO.puts("Coordinated #{count} agents in #{time}s")
      end)
      
      # Performance should scale reasonably (sub-linear growth acceptable)
      max_time = performance_results |> Enum.map(fn {_, time, _} -> time end) |> Enum.max()
      assert max_time < 10.0  # Even largest coordination should complete in <10s
    end
  end
  
  describe "memory and resource utilization" do
    test "memory usage remains stable under load" do
      initial_memory = get_memory_usage()
      
      # Perform intensive operations
      Enum.each(1..100, fn i ->
        # Create and destroy agents
        {:ok, pid} = FoundationJido.Agent.RegistryAdapter.register_agent(%{
          name: "memory_test_#{i}",
          capabilities: [:memory_test]
        })
        
        # Send some signals
        signal = JidoSignal.Signal.new(%{type: "memory.test", data: %{iteration: i}})
        FoundationJido.Signal.FoundationDispatch.dispatch(signal, %{type: :pid, target: pid})
        
        # Cleanup
        GenServer.stop(pid.pid)
      end)
      
      # Force garbage collection
      :erlang.garbage_collect()
      Process.sleep(1000)
      
      final_memory = get_memory_usage()
      memory_growth = final_memory - initial_memory
      
      # Memory growth should be minimal (allowing for some variance)
      assert memory_growth < initial_memory * 0.1  # Less than 10% growth
      IO.puts("Memory usage: #{initial_memory} -> #{final_memory} (#{memory_growth} growth)")
    end
  end
  
  # Helper functions
  defp start_test_agents(count) do
    Enum.map(1..count, fn i ->
      {:ok, result} = FoundationJido.Agent.RegistryAdapter.register_agent(%{
        name: "perf_coord_agent_#{i}",
        capabilities: [:coordination_test, :auction_participant]
      })
      
      %{
        agent_id: "perf_coord_agent_#{i}",
        pid: result.pid,
        capabilities: [:coordination_test, :auction_participant]
      }
    end)
  end
  
  defp cleanup_test_agents(agents) do
    Enum.each(agents, fn agent ->
      if Process.alive?(agent.pid) do
        GenServer.stop(agent.pid)
      end
    end)
  end
  
  defp get_memory_usage do
    :erlang.memory(:total)
  end
end
```

---

## Chaos Engineering and Fault Tolerance Testing

### Chaos Testing Framework

```elixir
# test/chaos/chaos_test.exs
defmodule Chaos.ChaosTest do
  use ExUnit.Case, async: false
  
  @moduletag :chaos
  @moduletag timeout: 600_000  # 10 minutes for chaos tests
  
  describe "fault injection and recovery" do
    test "system recovers from random agent crashes" do
      # Start a coordinated system with multiple agents
      agent_count = 20
      agents = start_coordinated_agent_system(agent_count)
      
      # Begin continuous coordination workload
      workload_task = Task.async(fn ->
        run_continuous_coordination_workload(agents, duration: 60_000)  # 1 minute
      end)
      
      # Inject chaos: randomly crash agents
      chaos_task = Task.async(fn ->
        inject_random_agent_crashes(agents, crash_probability: 0.1, interval: 2000)
      end)
      
      # Wait for workload completion
      workload_result = Task.await(workload_task, 120_000)
      Task.shutdown(chaos_task, :brutal_kill)
      
      # Verify system maintained functionality despite crashes
      assert workload_result.successful_coordinations > 10
      assert workload_result.error_rate < 0.3  # Less than 30% errors acceptable with chaos
      
      # Verify system auto-recovery
      surviving_agents = count_surviving_agents(agents)
      assert surviving_agents > agent_count * 0.7  # At least 70% should survive/recover
    end
    
    test "system handles network partition scenarios" do
      # This test would require distributed setup
      # Simulate network partitions between agent groups
      
      # Setup distributed agents across multiple nodes
      nodes = setup_test_cluster(3)
      agents_per_node = 5
      
      all_agents = Enum.flat_map(nodes, fn node ->
        start_agents_on_node(node, agents_per_node)
      end)
      
      # Start coordination workload
      coordination_task = Task.async(fn ->
        run_distributed_coordination(all_agents, duration: 30_000)
      end)
      
      # Inject network partition
      partition_task = Task.async(fn ->
        Process.sleep(10_000)  # Let system stabilize first
        create_network_partition(nodes, duration: 15_000)
      end)
      
      coordination_result = Task.await(coordination_task, 60_000)
      Task.await(partition_task, 60_000)
      
      # System should handle partition gracefully
      assert coordination_result.partition_detected == true
      assert coordination_result.continued_operation == true
      assert coordination_result.recovery_time < 10_000  # Recover within 10s
    end
    
    test "circuit breakers protect system during cascading failures" do
      # Setup system with circuit breaker protection
      {:ok, _} = start_circuit_breaker_protected_system()
      
      # Inject cascading failure: overload external service
      external_service_pid = start_failing_external_service()
      
      # Generate load that would normally cause cascading failure
      load_results = Enum.map(1..100, fn i ->
        Task.async(fn ->
          # This should trigger circuit breaker protection
          FoundationJido.Signal.FoundationDispatch.dispatch(
            create_external_service_signal(i),
            %{type: :http, target: external_service_pid, circuit_breaker: :external_service}
          )
        end)
      end)
      |> Task.await_many(30_000)
      
      # Circuit breaker should have activated
      assert Foundation.Infrastructure.CircuitBreaker.status(:external_service) == :open
      
      # Most requests should fail fast (not timeout)
      fast_failures = Enum.count(load_results, fn result ->
        case result do
          {:error, error} -> error.code == :circuit_breaker_open
          _ -> false
        end
      end)
      
      assert fast_failures > 80  # Most should fail fast due to circuit breaker
      
      # System should remain responsive
      health_check_response_time = measure_health_check_time()
      assert health_check_response_time < 100  # Should respond quickly despite load
    end
  end
  
  describe "resource exhaustion scenarios" do
    test "system handles memory pressure gracefully" do
      # Apply memory pressure while maintaining operations
      initial_memory = :erlang.memory(:total)
      
      # Start memory-intensive workload
      memory_hog_task = Task.async(fn ->
        consume_memory_gradually(target_mb: 500, duration: 30_000)
      end)
      
      # Continue normal operations under memory pressure
      operation_task = Task.async(fn ->
        run_normal_operations_under_pressure(duration: 30_000)
      end)
      
      operation_result = Task.await(operation_task, 60_000)
      Task.shutdown(memory_hog_task, :brutal_kill)
      
      # System should continue functioning
      assert operation_result.operations_completed > 50
      assert operation_result.error_rate < 0.2
      
      # Memory should not grow excessively
      final_memory = :erlang.memory(:total)
      memory_growth_ratio = final_memory / initial_memory
      assert memory_growth_ratio < 3.0  # Less than 3x growth
    end
    
    test "system handles process exhaustion" do
      # Test behavior when approaching process limit
      initial_process_count = length(Process.list())
      max_safe_processes = 10_000  # Conservative limit
      
      # Spawn many processes (but not enough to crash system)
      process_count = max_safe_processes - initial_process_count - 1000  # Safety buffer
      
      spawned_pids = Enum.map(1..process_count, fn i ->
        spawn(fn ->
          Process.sleep(30_000)  # Keep alive for test duration
        end)
      end)
      
      # Try to perform normal operations with high process count
      {:ok, coordination_result} = FoundationJido.Coordination.Orchestrator.coordinate(
        create_minimal_agent_specs(),
        %{coordination_type: :consensus, timeout: 10_000}
      )
      
      # Should still work despite high process count
      assert coordination_result.success == true
      
      # Cleanup
      Enum.each(spawned_pids, &Process.exit(&1, :kill))
    end
  end
  
  # Chaos testing helper functions
  defp start_coordinated_agent_system(count) do
    Enum.map(1..count, fn i ->
      {:ok, result} = FoundationJido.Agent.RegistryAdapter.register_agent(%{
        name: "chaos_agent_#{i}",
        capabilities: [:chaos_resilient, :coordination]
      })
      
      Map.put(result, :agent_id, "chaos_agent_#{i}")
    end)
  end
  
  defp inject_random_agent_crashes(agents, opts) do
    crash_probability = Keyword.get(opts, :crash_probability, 0.1)
    interval = Keyword.get(opts, :interval, 1000)
    
    Stream.repeatedly(fn ->
      Process.sleep(interval)
      
      # Randomly select agents to crash
      agents_to_crash = Enum.filter(agents, fn _ ->
        :rand.uniform() < crash_probability
      end)
      
      Enum.each(agents_to_crash, fn agent ->
        if Process.alive?(agent.pid) do
          Process.exit(agent.pid, :chaos_kill)
        end
      end)
      
      length(agents_to_crash)
    end)
    |> Enum.take(30)  # Run for 30 intervals
  end
  
  # ... additional chaos testing helpers
end
```

---

## Continuous Integration Testing

### CI Pipeline Test Configuration

```yaml
# .github/workflows/test.yml
name: Foundation OS Test Suite

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main]

jobs:
  unit-tests:
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
          key: ${{ runner.os }}-deps-${{ hashFiles('**/mix.lock') }}
      
      - name: Install dependencies
        run: mix deps.get
      
      - name: Run unit tests
        run: |
          mix test --exclude integration --exclude e2e --exclude performance --exclude chaos
          mix test.coverage --threshold 90
  
  integration-tests:
    runs-on: ubuntu-latest
    needs: unit-tests
    
    services:
      postgres:
        image: postgres:13
        env:
          POSTGRES_PASSWORD: postgres
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5
    
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.16'
          otp-version: '26'
      
      - name: Install dependencies
        run: mix deps.get
      
      - name: Run integration tests
        run: mix test --only integration
        env:
          DATABASE_URL: postgres://postgres:postgres@localhost/foundation_test
  
  e2e-tests:
    runs-on: ubuntu-latest
    needs: integration-tests
    
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.16'
          otp-version: '26'
      
      - name: Install dependencies
        run: mix deps.get
      
      - name: Run end-to-end tests
        run: mix test --only e2e
        timeout-minutes: 10
  
  performance-tests:
    runs-on: ubuntu-latest
    needs: integration-tests
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.16'
          otp-version: '26'
      
      - name: Install dependencies
        run: mix deps.get
      
      - name: Run performance tests
        run: mix test --only performance
        timeout-minutes: 15
      
      - name: Upload performance results
        uses: actions/upload-artifact@v3
        with:
          name: performance-results
          path: test/results/performance/
  
  chaos-tests:
    runs-on: ubuntu-latest
    needs: e2e-tests
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    
    steps:
      - uses: actions/checkout@v3
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.16'
          otp-version: '26'
      
      - name: Install dependencies
        run: mix deps.get
      
      - name: Run chaos tests
        run: mix test --only chaos
        timeout-minutes: 20
```

### Test Quality Gates

```elixir
# mix.exs - Test configuration
defmodule FoundationOS.MixProject do
  use Mix.Project
  
  def project do
    [
      # ... other config
      test_coverage: [
        threshold: 90,
        ignore_modules: [
          ~r/\.Test$/,
          ~r/Test\./,
          FoundationOS.TestHelpers
        ]
      ],
      preferred_cli_env: [
        "test.watch": :test,
        "test.coverage": :test,
        "test.integration": :test,
        "test.e2e": :test,
        "test.performance": :test,
        "test.chaos": :test
      ],
      aliases: aliases()
    ]
  end
  
  defp aliases do
    [
      "test.all": ["test", "test.integration", "test.e2e"],
      "test.quick": ["test --exclude integration --exclude e2e --exclude performance --exclude chaos"],
      "test.integration": ["test --only integration"],
      "test.e2e": ["test --only e2e"],
      "test.performance": ["test --only performance"],
      "test.chaos": ["test --only chaos"],
      "test.coverage": ["coveralls.html --threshold 90"],
      "quality.check": ["test.all", "credo --strict", "dialyzer", "boundary.check"]
    ]
  end
end
```

## Conclusion

This comprehensive testing strategy ensures Foundation OS reliability through:

1. **Multi-Layer Coverage**: Unit, integration, E2E, performance, and chaos testing
2. **Contract Validation**: API contract compliance across all layers
3. **Property-Based Testing**: Automated edge case discovery for complex systems
4. **Performance Assurance**: Load testing and performance regression detection
5. **Fault Tolerance Validation**: Chaos engineering confirms system resilience
6. **Continuous Quality**: Automated CI/CD pipeline with quality gates

**Key Benefits**:
- **Confidence**: Comprehensive testing enables safe refactoring and feature development
- **Reliability**: Multi-layer testing catches issues before production
- **Performance**: Performance testing prevents degradation over time
- **Maintainability**: Well-tested code is easier to modify and extend
- **Production Readiness**: Chaos testing validates real-world fault tolerance

The testing strategy scales with the system complexity and provides the quality foundation needed for a production multi-agent platform.