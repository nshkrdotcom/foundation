# Foundation Testing Strategy - GitHub Copilot Sonnet 4 Complement

**A comprehensive testing strategy to complement the existing TESTS.md, focusing on architectural validation, security testing, observability validation, and production-readiness verification.**

This document extends the Foundation library's testing coverage by addressing critical areas not fully covered in the base TESTS.md document. While the existing tests focus on contracts, stress testing, and benchmarks, this complement emphasizes **architectural integrity, security boundaries, observability depth, and production deployment scenarios**.

---

## 1. Architectural Validation Tests (`test/architecture/`)

**Gap Analysis:** The current test suite lacks validation of the layered architecture principles outlined in the README. Foundation follows a strict 4-layer architecture that needs enforcement to prevent architectural drift.

### File: `test/architecture/layer_dependency_validation_test.exs`

**Purpose:** Validate that the architectural boundaries defined in the README are enforced at compile-time and runtime, ensuring no layer violations occur.

```elixir
defmodule Foundation.Architecture.LayerDependencyValidationTest do
  use ExUnit.Case, async: false
  @moduletag :architecture

  @layers %{
    public_api: ~r/^Foundation\.(Config|Events|Telemetry|Utils|ServiceRegistry|ProcessRegistry|Infrastructure|ErrorContext)$/,
    business_logic: ~r/^Foundation\.Logic\./,
    service_layer: ~r/^Foundation\.Services\./,
    infrastructure: ~r/^Foundation\.(ProcessRegistry|ServiceRegistry|Infrastructure)\./
  }

  describe "Architecture Layer Dependencies" do
    test "public API layer only depends on business logic and service layers" do
      violations = validate_layer_dependencies(:public_api, [:business_logic, :service_layer])
      assert violations == [], "Public API layer violations: #{inspect(violations)}"
    end

    test "business logic layer only depends on service layer" do
      violations = validate_layer_dependencies(:business_logic, [:service_layer])
      assert violations == [], "Business logic layer violations: #{inspect(violations)}"
    end

    test "service layer only depends on infrastructure layer" do
      violations = validate_layer_dependencies(:service_layer, [:infrastructure])
      assert violations == [], "Service layer violations: #{inspect(violations)}"
    end

    test "infrastructure layer has no internal Foundation dependencies" do
      violations = validate_infrastructure_isolation()
      assert violations == [], "Infrastructure isolation violations: #{inspect(violations)}"
    end

    test "contract behaviors are properly implemented" do
      implementations = %{
        "Foundation.Contracts.Configurable" => ["Foundation.Services.ConfigServer"],
        "Foundation.Contracts.EventStore" => ["Foundation.Services.EventStore"],
        "Foundation.Contracts.Telemetry" => ["Foundation.Services.TelemetryService"]
      }

      violations = validate_behavior_implementations(implementations)
      assert violations == [], "Behavior implementation violations: #{inspect(violations)}"
    end
  end

  # Helper functions for static analysis would be implemented here
  defp validate_layer_dependencies(_layer, _allowed_deps), do: []
  defp validate_infrastructure_isolation(), do: []
  defp validate_behavior_implementations(_implementations), do: []
end
```

### File: `test/architecture/api_surface_stability_test.exs`

**Purpose:** Ensure the public API surface remains stable and backwards compatible, detecting breaking changes early.

```elixir
defmodule Foundation.Architecture.ApiSurfaceStabilityTest do
  use ExUnit.Case, async: true
  @moduletag :architecture

  @public_modules [
    Foundation,
    Foundation.Config,
    Foundation.Events,
    Foundation.Telemetry,
    Foundation.Utils,
    Foundation.ServiceRegistry,
    Foundation.ProcessRegistry,
    Foundation.Infrastructure,
    Foundation.ErrorContext
  ]

  describe "Public API Surface Stability" do
    test "all public modules export expected functions" do
      expected_exports = %{
        Foundation => [:initialize/0, :health/0, :available?/0],
        Foundation.Config => [:get/0, :get/1, :update/2, :subscribe/0, :updatable_paths/0, :reset/0, :available?/0],
        Foundation.Events => [:new_event/2, :new_event/3, :new_user_event/3, :new_system_event/2, :new_error_event/2, :store/1, :get/1, :query/1, :get_by_correlation/1],
        Foundation.Telemetry => [:emit_counter/2, :emit_gauge/3, :measure/3, :get_metrics/0]
      }

      Enum.each(expected_exports, fn {module, expected_functions} ->
        exported_functions = module.__info__(:functions)
        
        Enum.each(expected_functions, fn {function, arity} ->
          assert {function, arity} in exported_functions,
            "Expected #{module}.#{function}/#{arity} to be exported"
        end)
      end)
    end

    test "public modules have proper documentation" do
      Enum.each(@public_modules, fn module ->
        docs = Code.fetch_docs(module)
        assert docs != {:error, :module_not_found}, "Module #{module} should exist"
        
        case docs do
          {:docs_v1, _, _, _, module_doc, _, _} ->
            assert module_doc != :none, "Module #{module} should have documentation"
          _ ->
            flunk("Unexpected docs format for #{module}")
        end
      end)
    end

    test "all public functions have proper typespecs" do
      # Validate that critical public functions have typespecs
      modules_to_check = [Foundation.Config, Foundation.Events, Foundation.Telemetry]
      
      Enum.each(modules_to_check, fn module ->
        specs = Kernel.Typespec.fetch_specs(module)
        assert specs != :error, "Module #{module} should have typespecs"
      end)
    end
  end
end
```

---

## 2. Security & Boundary Tests (`test/security/`)

**Gap Analysis:** The current test suite doesn't validate security boundaries, input sanitization, or protection against common attack vectors.

### File: `test/security/input_validation_security_test.exs`

**Purpose:** Validate that all public APIs properly sanitize and validate inputs to prevent injection attacks and malformed data processing.

```elixir
defmodule Foundation.Security.InputValidationSecurityTest do
  use ExUnit.Case, async: false
  @moduletag :security

  describe "Configuration Security" do
    test "config paths reject malicious atom injection attempts" do
      malicious_inputs = [
        [:__struct__, Kernel],
        [:__info__, :functions],
        [:"Elixir.System", :cmd],
        # Test deeply nested malicious paths
        [:legitimate, :path, :"Elixir.File", :rm_rf],
        # Test binary injection
        ["binary_path", "with_string"]
      ]

      Enum.each(malicious_inputs, fn malicious_path ->
        result = Foundation.Config.get(malicious_path)
        # Should either reject with proper error or safely return not found
        assert match?({:error, _}, result), 
          "Malicious path #{inspect(malicious_path)} should be rejected"
      end)
    end

    test "config values reject dangerous data structures" do
      dangerous_values = [
        # Anonymous functions
        fn -> System.cmd("rm", ["-rf", "/"]) end,
        # References to sensitive modules
        %{__struct__: File, path: "/etc/passwd"},
        # Deeply nested complex structures that could cause DoS
        generate_deeply_nested_structure(1000)
      ]

      Enum.each(dangerous_values, fn dangerous_value ->
        result = Foundation.Config.update([:test, :dangerous], dangerous_value)
        # Should validate and reject dangerous structures
        assert match?({:error, _}, result),
          "Dangerous value #{inspect(dangerous_value, limit: 10)} should be rejected"
      end)
    end
  end

  describe "Event System Security" do
    test "event metadata rejects executable content" do
      malicious_metadata = %{
        command: "rm -rf /",
        script: "<script>alert('xss')</script>",
        code: "System.cmd('curl', ['http://malicious.com'])",
        # Test atom bombing attempt
        atoms: Enum.map(1..1000, &String.to_atom("malicious_atom_#{&1}"))
      }

      {:ok, event} = Foundation.Events.new_event(:test_event, malicious_metadata)
      {:ok, _event_id} = Foundation.Events.store(event)
      
      # Event should be stored but metadata should be sanitized
      {:ok, stored_event} = Foundation.Events.get(1)  # Assuming first event
      
      # Verify dangerous content is either rejected or properly escaped
      refute Map.has_key?(stored_event.metadata, :command)
      refute is_function(stored_event.metadata[:script] || false)
    end

    test "event correlation IDs prevent timing attacks" do
      # Generate multiple correlation IDs and verify they don't leak timing information
      correlation_ids = for _i <- 1..100, do: Foundation.Utils.generate_correlation_id()
      
      # Verify correlation IDs have sufficient entropy
      unique_ids = Enum.uniq(correlation_ids)
      assert length(unique_ids) == length(correlation_ids), 
        "Correlation IDs should be unique"
      
      # Verify they don't follow predictable patterns
      assert_unpredictable_sequence(correlation_ids)
    end
  end

  describe "Infrastructure Protection Security" do
    test "circuit breaker names resist injection attacks" do
      malicious_names = [
        :"Elixir.System.cmd",
        :"rm -rf /",
        String.to_atom("malicious_#{:os.getpid()}")
      ]

      Enum.each(malicious_names, fn malicious_name ->
        result = Foundation.Infrastructure.configure_protection(malicious_name, %{
          circuit_breaker: %{failure_threshold: 5, recovery_time: 30_000}
        })
        
        # Should either reject malicious names or safely isolate them
        case result do
          :ok -> verify_safe_isolation(malicious_name)
          {:error, _} -> :ok  # Expected rejection
        end
      end)
    end
  end

  # Helper functions
  defp generate_deeply_nested_structure(0), do: :leaf
  defp generate_deeply_nested_structure(n), do: %{nested: generate_deeply_nested_structure(n - 1)}
  
  defp assert_unpredictable_sequence(ids) do
    # Simple check for sequential patterns
    refute Enum.with_index(ids) |> Enum.all?(fn {id, index} -> 
      String.contains?(to_string(id), to_string(index))
    end), "Correlation IDs should not contain sequential patterns"
  end
  
  defp verify_safe_isolation(_name), do: :ok  # Implementation would verify isolation
end
```

### File: `test/security/privilege_escalation_test.exs`

**Purpose:** Ensure that the Foundation library doesn't inadvertently provide privilege escalation vectors through its APIs.

```elixir
defmodule Foundation.Security.PrivilegeEscalationTest do
  use ExUnit.Case, async: false
  @moduletag :security

  describe "Service Registry Security" do
    test "service registration requires proper authorization" do
      # Attempt to register system-critical services
      critical_services = [:config_server, :event_store, :telemetry_service]
      
      Enum.each(critical_services, fn service ->
        result = Foundation.ServiceRegistry.register(:production, service, self())
        
        # Should reject duplicate registrations of critical services
        assert match?({:error, _}, result),
          "Should not allow re-registration of critical service #{service}"
      end)
    end

    test "service lookup prevents unauthorized access to internal services" do
      # Try to look up services that should be internal-only
      internal_services = [:supervisor, :application_controller, :global_name_server]
      
      Enum.each(internal_services, fn service ->
        result = Foundation.ServiceRegistry.lookup(:production, service)
        
        # Should either not find or properly restrict access
        case result do
          {:ok, _pid} -> verify_access_restricted(service)
          {:error, :not_found} -> :ok  # Expected for internal services
        end
      end)
    end
  end

  describe "Process Registry Security" do
    test "process registration validates ownership" do
      # Attempt to register processes we don't own
      other_pid = spawn(fn -> :timer.sleep(1000) end)
      
      result = Foundation.ProcessRegistry.register(:test_process, other_pid)
      
      # Should verify ownership before registration
      assert match?({:error, _}, result),
        "Should not allow registration of processes we don't own"
    end
  end

  defp verify_access_restricted(_service), do: :ok  # Would implement actual access checks
end
```

---

## 3. Observability & Monitoring Tests (`test/observability/`)

**Gap Analysis:** While telemetry is tested functionally, there's no validation of observability depth, metric correlation, or monitoring effectiveness.

### File: `test/observability/telemetry_correlation_test.exs`

**Purpose:** Validate that telemetry events can be properly correlated across service boundaries and provide meaningful operational insights.

```elixir
defmodule Foundation.Observability.TelemetryCorrelationTest do
  use ExUnit.Case, async: false
  @moduletag :observability

  describe "Cross-Service Correlation" do
    test "configuration changes generate correlated telemetry and events" do
      correlation_id = Foundation.Utils.generate_correlation_id()
      
      # Perform a configuration change
      :ok = Foundation.Config.update([:test, :correlation_test], true)
      
      # Wait for async telemetry processing
      :timer.sleep(100)
      
      # Verify telemetry was emitted
      {:ok, metrics} = Foundation.Telemetry.get_metrics()
      config_metrics = Map.get(metrics, [:foundation, :config, :updates], %{})
      assert config_metrics.count > 0, "Configuration update should emit telemetry"
      
      # Verify corresponding event was created
      {:ok, events} = Foundation.Events.query(%{event_type: :config_updated})
      assert length(events) > 0, "Configuration update should create audit event"
      
      # Verify correlation between telemetry and events
      recent_event = List.first(events)
      assert Map.has_key?(recent_event.metadata, :correlation_id),
        "Config event should include correlation ID"
    end

    test "infrastructure protection events correlate with telemetry metrics" do
      # Execute protected operation that should trigger circuit breaker
      results = for _i <- 1..10 do
        Foundation.Infrastructure.execute_protected(
          :test_service,
          [circuit_breaker: :test_breaker],
          fn -> 
            if :rand.uniform() < 0.8, do: {:error, :simulated_failure}, else: :ok
          end
        )
      end
      
      failures = Enum.count(results, &match?({:error, _}, &1))
      
      # Verify telemetry captured the failures
      {:ok, metrics} = Foundation.Telemetry.get_metrics()
      circuit_breaker_metrics = Map.get(metrics, [:foundation, :infrastructure, :circuit_breaker], %{})
      
      assert circuit_breaker_metrics.failures >= failures,
        "Circuit breaker telemetry should capture failures"
      
      # Verify events were generated for circuit breaker state changes
      {:ok, events} = Foundation.Events.query(%{event_type: :circuit_breaker_opened})
      if failures >= 5 do  # Assuming threshold is 5
        assert length(events) > 0, "Circuit breaker should generate events when opened"
      end
    end
  end

  describe "Metric Aggregation Accuracy" do
    test "counter aggregation maintains consistency under concurrent load" do
      # Generate concurrent counter increments
      tasks = for i <- 1..50 do
        Task.async(fn ->
          Foundation.Telemetry.emit_counter([:test, :concurrent_counter], %{worker: i})
        end)
      end
      
      Task.await_many(tasks, 5000)
      
      # Verify aggregation accuracy
      {:ok, metrics} = Foundation.Telemetry.get_metrics()
      counter_value = get_in(metrics, [[:test, :concurrent_counter], :count])
      
      assert counter_value == 50, 
        "Counter should accurately aggregate concurrent increments: expected 50, got #{counter_value}"
    end

    test "gauge values reflect actual system state" do
      # Emit gauge values
      memory_values = [1024, 2048, 4096, 2048, 1024]
      
      Enum.each(memory_values, fn value ->
        Foundation.Telemetry.emit_gauge([:system, :memory], value, %{unit: :mb})
        :timer.sleep(10)  # Small delay to ensure ordering
      end)
      
      {:ok, metrics} = Foundation.Telemetry.get_metrics()
      gauge_value = get_in(metrics, [[:system, :memory], :value])
      
      # Should reflect the last emitted value
      assert gauge_value == 1024, 
        "Gauge should reflect last emitted value: expected 1024, got #{gauge_value}"
    end
  end

  describe "Performance Impact Measurement" do
    test "telemetry overhead remains within acceptable bounds" do
      # Measure baseline performance
      baseline_time = measure_operation_time(fn ->
        for _i <- 1..1000, do: :ok
      end)
      
      # Measure performance with telemetry
      telemetry_time = measure_operation_time(fn ->
        for i <- 1..1000 do
          Foundation.Telemetry.emit_counter([:performance, :test], %{iteration: i})
        end
      end)
      
      # Telemetry overhead should be less than 50% of baseline
      overhead_ratio = telemetry_time / baseline_time
      assert overhead_ratio < 1.5, 
        "Telemetry overhead too high: #{overhead_ratio * 100}% of baseline"
    end
  end

  defp measure_operation_time(operation) do
    start_time = :os.timestamp()
    operation.()
    end_time = :os.timestamp()
    :timer.now_diff(end_time, start_time) / 1000  # Convert to milliseconds
  end
end
```

### File: `test/observability/health_monitoring_test.exs`

**Purpose:** Validate that the health monitoring system provides accurate and actionable health information.

```elixir
defmodule Foundation.Observability.HealthMonitoringTest do
  use ExUnit.Case, async: false
  @moduletag :observability

  describe "System Health Reporting" do
    test "health check detects service unavailability" do
      # Get baseline health
      {:ok, healthy_status} = Foundation.health()
      assert healthy_status.status == :healthy
      
      # Simulate service failure (in a controlled test environment)
      # This would require test-specific service management
      original_pid = Process.whereis(Foundation.Services.EventStore)
      if original_pid do
        GenServer.stop(original_pid)
        :timer.sleep(100)  # Allow time for failure detection
        
        {:ok, unhealthy_status} = Foundation.health()
        assert unhealthy_status.status in [:degraded, :unhealthy]
        assert Map.has_key?(unhealthy_status, :failed_services)
        assert :event_store in unhealthy_status.failed_services
        
        # Restart service and verify recovery
        Foundation.Application.start_event_store()
        :timer.sleep(200)  # Allow time for recovery detection
        
        {:ok, recovered_status} = Foundation.health()
        assert recovered_status.status == :healthy
      end
    end

    test "health check includes performance metrics" do
      {:ok, health} = Foundation.health()
      
      # Should include key performance indicators
      assert Map.has_key?(health, :performance)
      performance = health.performance
      
      expected_metrics = [:response_time_avg, :memory_usage, :process_count, :message_queue_lengths]
      Enum.each(expected_metrics, fn metric ->
        assert Map.has_key?(performance, metric),
          "Health check should include #{metric}"
      end)
      
      # Validate metric ranges
      assert performance.response_time_avg >= 0
      assert performance.memory_usage > 0
      assert performance.process_count > 0
    end

    test "health status transitions are properly logged" do
      # This test would require integration with actual logging system
      # For now, verify that status changes generate appropriate events
      
      # Trigger a status change scenario
      :ok = Foundation.Telemetry.emit_gauge([:system, :cpu_usage], 95.0, %{unit: :percent})
      
      # Verify health status reflects high resource usage
      {:ok, health} = Foundation.health()
      
      if health.status != :healthy do
        # Should generate health status change event
        {:ok, events} = Foundation.Events.query(%{event_type: :health_status_changed})
        recent_events = Enum.take(events, 5)  # Get recent events
        
        status_change_events = Enum.filter(recent_events, fn event ->
          Map.get(event.metadata, :new_status) != nil
        end)
        
        assert length(status_change_events) > 0,
          "Health status changes should generate audit events"
      end
    end
  end

  describe "Service Dependency Tracking" do
    test "health check identifies service dependency chains" do
      {:ok, health} = Foundation.health()
      
      # Should include service dependency information
      assert Map.has_key?(health, :dependencies)
      dependencies = health.dependencies
      
      # Core services should be tracked
      core_services = [:config_server, :event_store, :telemetry_service]
      Enum.each(core_services, fn service ->
        assert Map.has_key?(dependencies, service),
          "Should track dependency status for #{service}"
      end)
      
      # Each dependency should have status and response time
      Enum.each(dependencies, fn {service, info} ->
        assert Map.has_key?(info, :status), "#{service} should have status"
        assert Map.has_key?(info, :response_time), "#{service} should have response time"
        assert info.status in [:healthy, :degraded, :unhealthy]
        assert is_number(info.response_time) and info.response_time >= 0
      end)
    end
  end
end
```

---

## 4. Production Deployment Tests (`test/deployment/`)

**Gap Analysis:** The current tests don't validate production deployment scenarios, configuration management, or operational procedures.

### File: `test/deployment/configuration_migration_test.exs`

**Purpose:** Validate that configuration changes can be safely deployed and rolled back in production scenarios.

```elixir
defmodule Foundation.Deployment.ConfigurationMigrationTest do
  use ExUnit.Case, async: false
  @moduletag :deployment

  describe "Configuration Migration Safety" do
    test "configuration updates preserve system stability" do
      # Take snapshot of current configuration
      {:ok, original_config} = Foundation.Config.get()
      
      # Apply configuration changes that might be done during deployment
      deployment_changes = [
        {[:logging, :level], :warn},          # Change log level
        {[:telemetry, :batch_size], 1000},    # Adjust telemetry batching
        {[:events, :retention_hours], 168}    # Change event retention
      ]
      
      # Apply changes sequentially and verify system remains stable
      Enum.each(deployment_changes, fn {path, value} ->
        :ok = Foundation.Config.update(path, value)
        
        # Verify system remains responsive after each change
        assert Foundation.available?(), "System should remain available after config update"
        
        # Verify core functionality still works
        {:ok, _event} = Foundation.Events.new_event(:deployment_test, %{config_path: path})
        :ok = Foundation.Telemetry.emit_counter([:deployment, :config_updates], %{})
      end)
      
      # Rollback changes and verify system returns to original state
      Foundation.Config.reset()
      :timer.sleep(100)  # Allow propagation
      
      {:ok, rolled_back_config} = Foundation.Config.get()
      assert config_equivalent?(original_config, rolled_back_config),
        "Configuration rollback should restore original state"
    end

    test "invalid configuration changes are safely rejected" do
      invalid_changes = [
        {[:nonexistent, :path], "value"},     # Invalid path
        {[:logging, :level], :invalid_level}, # Invalid value
        {[:telemetry, :batch_size], -1},      # Invalid negative value
        {[:events, :retention_hours], "not_a_number"}  # Wrong type
      ]
      
      Enum.each(invalid_changes, fn {path, value} ->
        result = Foundation.Config.update(path, value)
        assert match?({:error, _}, result),
          "Invalid config change #{inspect({path, value})} should be rejected"
        
        # System should remain stable after rejection
        assert Foundation.available?(),
          "System should remain available after rejecting invalid config"
      end)
    end
  end

  describe "Configuration Validation" do
    test "configuration schema validation prevents invalid deployments" do
      # Test various invalid configuration structures
      invalid_configs = [
        %{},  # Empty config
        %{logging: "not_a_map"},  # Wrong type for section
        %{ai: %{provider: %{invalid: :structure}}},  # Invalid nested structure
        %{telemetry: %{enabled: "not_boolean"}}  # Wrong type for boolean field
      ]
      
      Enum.each(invalid_configs, fn invalid_config ->
        # This assumes there's a way to validate configs before applying
        result = Foundation.Config.validate(invalid_config)
        assert match?({:error, _}, result),
          "Invalid config #{inspect(invalid_config, limit: 5)} should fail validation"
      end)
    end
  end

  defp config_equivalent?(config1, config2) do
    # Simple equality check - in practice might need more sophisticated comparison
    config1 == config2
  end
end
```

### File: `test/deployment/service_startup_test.exs`

**Purpose:** Validate that Foundation services start up correctly in various deployment scenarios and handle startup failures gracefully.

```elixir
defmodule Foundation.Deployment.ServiceStartupTest do
  use ExUnit.Case, async: false
  @moduletag :deployment

  describe "Cold Start Scenarios" do
    test "services start in correct dependency order" do
      # This test would require the ability to control service startup
      # Track service startup order
      startup_order = []
      
      # Monitor service startup events
      :ok = Foundation.Events.subscribe(:service_startup)
      
      # Simulate application restart
      Foundation.Application.restart_services()
      
      # Collect startup events for analysis
      startup_events = collect_startup_events(5000)  # 5 second timeout
      
      # Verify correct startup order: Infrastructure -> Services -> API
      expected_order = [
        :process_registry,
        :service_registry,
        :config_server,
        :event_store,
        :telemetry_service
      ]
      
      actual_order = extract_startup_order(startup_events)
      
      # Verify infrastructure services start first
      config_pos = Enum.find_index(actual_order, &(&1 == :config_server))
      registry_pos = Enum.find_index(actual_order, &(&1 == :process_registry))
      
      assert registry_pos < config_pos,
        "Process registry should start before config server"
    end

    test "startup continues despite non-critical service failures" do
      # Simulate scenario where a non-critical service fails to start
      # (This would require dependency injection or test-specific configuration)
      
      # Configure one service to fail startup
      Process.put(:simulate_telemetry_startup_failure, true)
      
      # Attempt application startup
      result = Foundation.Application.start_services()
      
      # Core services should still be available
      assert Foundation.Config.available?(),
        "Config service should be available despite telemetry failure"
      
      assert Foundation.Events.store(%Foundation.Types.Event{
        id: 1,
        event_type: :test,
        metadata: %{},
        timestamp: DateTime.utc_now(),
        correlation_id: "test"
      }) == {:ok, 1}, "Event storage should work despite telemetry failure"
    end
  end

  describe "Warm Start Scenarios" do
    test "services resume from previous state correctly" do
      # Create some state before restart
      :ok = Foundation.Config.update([:test, :deployment], "pre_restart_value")
      {:ok, event} = Foundation.Events.new_event(:pre_restart, %{test: true})
      {:ok, _} = Foundation.Events.store(event)
      
      # Simulate service restart (not full application restart)
      Foundation.Application.restart_services()
      
      # Verify state is preserved
      {:ok, preserved_config} = Foundation.Config.get([:test, :deployment])
      assert preserved_config == "pre_restart_value",
        "Configuration should be preserved across service restarts"
      
      {:ok, events} = Foundation.Events.query(%{event_type: :pre_restart})
      assert length(events) > 0,
        "Events should be preserved across service restarts"
    end
  end

  describe "Resource Constraint Scenarios" do
    test "services handle low memory conditions gracefully" do
      # Simulate low memory by creating memory pressure
      # (This is a simplified simulation)
      memory_hogs = for _i <- 1..10 do
        spawn(fn -> 
          # Create some memory pressure
          _large_list = for i <- 1..100_000, do: "memory_pressure_#{i}"
          :timer.sleep(5000)
        end)
      end
      
      # Verify services remain responsive under memory pressure
      assert Foundation.available?(),
        "Foundation should remain available under memory pressure"
      
      # Cleanup
      Enum.each(memory_hogs, &Process.exit(&1, :kill))
    end

    test "services handle high CPU load gracefully" do
      # Create CPU pressure
      cpu_load_tasks = for _i <- 1..System.schedulers_online() do
        Task.async(fn ->
          # CPU intensive work
          end_time = :os.timestamp() |> :timer.now_diff({0, 0, 0}) + 2_000_000  # 2 seconds
          cpu_intensive_loop(end_time)
        end)
      end
      
      # Verify services remain responsive under CPU load
      start_time = System.monotonic_time(:millisecond)
      assert Foundation.available?()
      response_time = System.monotonic_time(:millisecond) - start_time
      
      # Response time should be reasonable even under load
      assert response_time < 1000,
        "Foundation should respond within 1 second even under CPU load"
      
      # Cleanup
      Task.await_many(cpu_load_tasks, 3000)
    end
  end

  # Helper functions
  defp collect_startup_events(timeout) do
    receive do
      {:service_startup, event} -> [event | collect_startup_events(timeout)]
    after
      timeout -> []
    end
  end

  defp extract_startup_order(events) do
    events
    |> Enum.sort_by(&Map.get(&1.metadata, :startup_time, 0))
    |> Enum.map(&Map.get(&1.metadata, :service))
  end

  defp cpu_intensive_loop(end_time) do
    current_time = :os.timestamp() |> :timer.now_diff({0, 0, 0})
    if current_time < end_time do
      # Some CPU work
      :math.pow(2, 10)
      cpu_intensive_loop(end_time)
    end
  end
end
```

---

## 5. Edge Case & Error Recovery Tests (`test/edge_cases/`)

**Gap Analysis:** While the current tests cover chaos engineering, they don't thoroughly test edge cases, boundary conditions, and error recovery scenarios.

### File: `test/edge_cases/boundary_condition_test.exs`

**Purpose:** Test system behavior at boundary conditions and edge cases that might not be covered in normal testing.

```elixir
defmodule Foundation.EdgeCases.BoundaryConditionTest do
  use ExUnit.Case, async: false
  @moduletag :edge_cases

  describe "Resource Limit Boundaries" do
    test "event storage handles maximum event size gracefully" do
      # Test with very large event metadata
      large_metadata = %{
        large_data: String.duplicate("x", 1_000_000),  # 1MB string
        nested_data: generate_deep_nested_map(100),
        array_data: Enum.to_list(1..10_000)
      }
      
      {:ok, large_event} = Foundation.Events.new_event(:large_event, large_metadata)
      
      result = Foundation.Events.store(large_event)
      
      case result do
        {:ok, _id} ->
          # If accepted, verify it can be retrieved
          {:ok, retrieved} = Foundation.Events.get(1)
          assert retrieved.metadata.large_data == large_metadata.large_data
          
        {:error, reason} ->
          # If rejected, ensure it's for the right reason
          assert reason.type in [:payload_too_large, :validation_error]
      end
    end

    test "configuration handles deeply nested path access" do
      # Test with very deep configuration paths
      deep_path = Enum.map(1..50, &:"level_#{&1}")
      
      result = Foundation.Config.get(deep_path)
      
      # Should handle gracefully - either find value or return not found
      assert match?({:ok, _} | {:error, %{type: :not_found}}, result)
      
      # System should remain responsive
      assert Foundation.available?()
    end

    test "telemetry handles metric name collisions and edge cases" do
      # Test with conflicting metric names
      conflicting_metrics = [
        [:app, :requests, :total],
        [:app, :requests, :total],  # Exact duplicate
        [:app, "requests", :total], # String vs atom
        [:"app.requests", :total]   # Dot notation
      ]
      
      Enum.each(conflicting_metrics, fn metric_name ->
        :ok = Foundation.Telemetry.emit_counter(metric_name, %{source: :test})
      end)
      
      {:ok, metrics} = Foundation.Telemetry.get_metrics()
      
      # Should handle naming conflicts gracefully
      assert is_map(metrics)
      
      # Verify system remains stable
      assert Foundation.available?()
    end
  end

  describe "Concurrent Access Edge Cases" do
    test "configuration updates under high concurrent read load" do
      # Start many concurrent readers
      reader_tasks = for i <- 1..100 do
        Task.async(fn ->
          for _j <- 1..50 do
            Foundation.Config.get([:test, :concurrent_access])
            :timer.sleep(:rand.uniform(10))  # Random small delay
          end
          i  # Return task identifier
        end)
      end
      
      # Perform updates while readers are active
      for value <- 1..10 do
        :ok = Foundation.Config.update([:test, :concurrent_access], value)
        :timer.sleep(50)  # Allow some time between updates
      end
      
      # Wait for readers to complete
      completed_tasks = Task.await_many(reader_tasks, 10_000)
      
      # All readers should complete successfully
      assert length(completed_tasks) == 100
      
      # Final configuration should be consistent
      {:ok, final_value} = Foundation.Config.get([:test, :concurrent_access])
      assert final_value == 10
    end

    test "event storage under rapid concurrent insertions" do
      # Generate many concurrent event insertions
      insertion_tasks = for i <- 1..200 do
        Task.async(fn ->
          {:ok, event} = Foundation.Events.new_event(:concurrent_test, %{task_id: i})
          Foundation.Events.store(event)
        end)
      end
      
      results = Task.await_many(insertion_tasks, 10_000)
      
      # All insertions should succeed
      successful_insertions = Enum.count(results, &match?({:ok, _}, &1))
      assert successful_insertions == 200, 
        "Expected 200 successful insertions, got #{successful_insertions}"
      
      # Verify all events can be retrieved
      {:ok, stored_events} = Foundation.Events.query(%{event_type: :concurrent_test})
      assert length(stored_events) == 200
    end
  end

  describe "Error Propagation Edge Cases" do
    test "nested service failures don't cause cascading system failure" do
      # Create a chain of dependent operations that might fail
      operations = [
        fn -> Foundation.Config.get([:nested, :operation, :1]) end,
        fn -> Foundation.Events.new_event(:nested_op, %{step: 2}) end,
        fn -> Foundation.Telemetry.emit_counter([:nested, :operation], %{step: 3}) end
      ]
      
      # Execute operations and handle potential failures
      results = Enum.map(operations, fn operation ->
        try do
          operation.()
        rescue
          error -> {:error, error}
        catch
          :exit, reason -> {:error, {:exit, reason}}
          :throw, value -> {:error, {:throw, value}}
        end
      end)
      
      # System should remain available regardless of individual failures
      assert Foundation.available?(),
        "System should remain available despite nested operation failures"
      
      # Health check should still work
      assert match?({:ok, _}, Foundation.health())
    end
  end

  # Helper function
  defp generate_deep_nested_map(0), do: %{leaf: :value}
  defp generate_deep_nested_map(depth) do
    %{"level_#{depth}" => generate_deep_nested_map(depth - 1)}
  end
end
```

---

## 6. Performance Regression Tests (`test/performance/`)

**Gap Analysis:** The current benchmark tests focus on individual operations but don't track performance regressions over time or test performance under realistic workloads.

### File: `test/performance/regression_tracking_test.exs`

**Purpose:** Track performance metrics over time to detect regressions early and ensure performance characteristics remain within acceptable bounds.

```elixir
defmodule Foundation.Performance.RegressionTrackingTest do
  use ExUnit.Case, async: false
  @moduletag :performance

  @performance_baselines %{
    config_get: %{max_time_ms: 1.0, p95_time_ms: 0.5},
    config_update: %{max_time_ms: 5.0, p95_time_ms: 2.0},
    event_store: %{max_time_ms: 2.0, p95_time_ms: 1.0},
    event_query: %{max_time_ms: 10.0, p95_time_ms: 5.0},
    telemetry_emit: %{max_time_ms: 0.5, p95_time_ms: 0.2}
  }

  describe "Performance Baseline Validation" do
    test "configuration operations meet performance baselines" do
      times = benchmark_operation(1000, fn ->
        Foundation.Config.get([:dev, :debug_mode])
      end)
      
      stats = calculate_stats(times)
      baseline = @performance_baselines.config_get
      
      assert stats.p95 <= baseline.p95_time_ms,
        "Config get P95 (#{stats.p95}ms) exceeds baseline (#{baseline.p95_time_ms}ms)"
      
      assert stats.max <= baseline.max_time_ms,
        "Config get max (#{stats.max}ms) exceeds baseline (#{baseline.max_time_ms}ms)"
    end

    test "event operations meet performance baselines" do
      # Test event storage performance
      store_times = benchmark_operation(1000, fn ->
        {:ok, event} = Foundation.Events.new_event(:perf_test, %{iteration: :rand.uniform(1000)})
        Foundation.Events.store(event)
      end)
      
      store_stats = calculate_stats(store_times)
      store_baseline = @performance_baselines.event_store
      
      assert store_stats.p95 <= store_baseline.p95_time_ms,
        "Event store P95 (#{store_stats.p95}ms) exceeds baseline (#{store_baseline.p95_time_ms}ms)"
      
      # Test event query performance
      query_times = benchmark_operation(100, fn ->
        Foundation.Events.query(%{event_type: :perf_test})
      end)
      
      query_stats = calculate_stats(query_times)
      query_baseline = @performance_baselines.event_query
      
      assert query_stats.p95 <= query_baseline.p95_time_ms,
        "Event query P95 (#{query_stats.p95}ms) exceeds baseline (#{query_baseline.p95_time_ms}ms)"
    end

    test "telemetry operations meet performance baselines" do
      times = benchmark_operation(10000, fn ->
        Foundation.Telemetry.emit_counter([:perf, :test], %{iteration: :rand.uniform(100)})
      end)
      
      stats = calculate_stats(times)
      baseline = @performance_baselines.telemetry_emit
      
      assert stats.p95 <= baseline.p95_time_ms,
        "Telemetry emit P95 (#{stats.p95}ms) exceeds baseline (#{baseline.p95_time_ms}ms)"
    end
  end

  describe "Realistic Workload Performance" do
    test "mixed workload performance remains stable" do
      # Simulate realistic application workload
      workload_duration = 30_000  # 30 seconds
      start_time = System.monotonic_time(:millisecond)
      
      operations_completed = run_mixed_workload(workload_duration)
      
      end_time = System.monotonic_time(:millisecond)
      actual_duration = end_time - start_time
      
      # Calculate throughput
      throughput = operations_completed / (actual_duration / 1000)  # ops/second
      
      # Should maintain reasonable throughput
      assert throughput >= 100,
        "Mixed workload throughput (#{throughput} ops/sec) below expected minimum"
      
      # System should remain responsive
      response_start = System.monotonic_time(:millisecond)
      assert Foundation.available?()
      response_time = System.monotonic_time(:millisecond) - response_start
      
      assert response_time < 100,
        "System response time (#{response_time}ms) too slow after sustained load"
    end
  end

  describe "Memory Usage Tracking" do
    test "memory usage remains stable under sustained operations" do
      initial_memory = get_process_memory(:config_server)
      
      # Perform sustained operations
      for _i <- 1..10_000 do
        Foundation.Config.get([:dev, :debug_mode])
        if rem(_i, 1000) == 0, do: :erlang.garbage_collect()
      end
      
      final_memory = get_process_memory(:config_server)
      memory_growth = final_memory - initial_memory
      
      # Memory growth should be minimal (less than 10MB)
      assert memory_growth < 10_000_000,
        "Excessive memory growth: #{memory_growth} bytes after 10k operations"
    end
  end

  # Helper functions
  defp benchmark_operation(iterations, operation) do
    for _i <- 1..iterations do
      start_time = System.monotonic_time(:microsecond)
      operation.()
      end_time = System.monotonic_time(:microsecond)
      (end_time - start_time) / 1000  # Convert to milliseconds
    end
  end

  defp calculate_stats(times) do
    sorted_times = Enum.sort(times)
    count = length(times)
    
    %{
      min: Enum.min(times),
      max: Enum.max(times),
      avg: Enum.sum(times) / count,
      p50: Enum.at(sorted_times, div(count, 2)),
      p95: Enum.at(sorted_times, div(count * 95, 100)),
      p99: Enum.at(sorted_times, div(count * 99, 100))
    }
  end

  defp run_mixed_workload(duration_ms) do
    start_time = System.monotonic_time(:millisecond)
    operation_count = :counters.new(1, [])
    
    # Start multiple worker processes
    workers = for _i <- 1..4 do
      spawn_link(fn -> 
        mixed_workload_worker(start_time, duration_ms, operation_count)
      end)
    end
    
    # Wait for duration
    :timer.sleep(duration_ms)
    
    # Stop workers
    Enum.each(workers, &Process.exit(&1, :normal))
    
    :counters.get(operation_count, 1)
  end

  defp mixed_workload_worker(start_time, duration_ms, counter) do
    if System.monotonic_time(:millisecond) - start_time < duration_ms do
      # Randomly choose an operation
      case :rand.uniform(4) do
        1 -> Foundation.Config.get([:dev, :debug_mode])
        2 -> 
          {:ok, event} = Foundation.Events.new_event(:workload, %{worker: self()})
          Foundation.Events.store(event)
        3 -> Foundation.Telemetry.emit_counter([:workload, :ops], %{worker: self()})
        4 -> Foundation.Events.query(%{limit: 10})
      end
      
      :counters.add(counter, 1, 1)
      mixed_workload_worker(start_time, duration_ms, counter)
    end
  end

  defp get_process_memory(service_name) do
    case Foundation.ServiceRegistry.lookup(:production, service_name) do
      {:ok, pid} ->
        case Process.info(pid, :memory) do
          {:memory, memory} -> memory
          nil -> 0
        end
      _ -> 0
    end
  end
end
```

---

## 7. Test Execution Strategy

### Running Complementary Tests

```bash
# Run all architectural tests
mix test --only architecture

# Run security-focused tests
mix test --only security

# Run observability tests
mix test --only observability

# Run deployment scenario tests
mix test --only deployment

# Run edge case tests
mix test --only edge_cases

# Run performance regression tests
mix test --only performance

# Run the complete complementary test suite
mix test test/architecture test/security test/observability test/deployment test/edge_cases test/performance
```

### Integration with Existing Test Suite

This complementary test suite is designed to work alongside the existing TESTS.md proposals:

1. **Contract Tests**: Extend architectural validation
2. **Stress Tests**: Complement with deployment and edge case scenarios  
3. **Benchmarks**: Enhanced with regression tracking
4. **Smoke Tests**: Integrated with observability validation

### Continuous Integration Integration

```yaml
# Add to .github/workflows/elixir.yml
- name: Run Architectural Tests
  run: mix test --only architecture

- name: Run Security Tests  
  run: mix test --only security

- name: Run Performance Regression Tests
  run: mix test --only performance --max-failures 1
```

---

## Summary

This complementary testing strategy addresses critical gaps in Foundation's testing coverage by focusing on:

1. **Architectural Integrity**: Ensuring the layered architecture is maintained
2. **Security Boundaries**: Validating input sanitization and privilege isolation  
3. **Observability Depth**: Testing telemetry correlation and health monitoring
4. **Production Readiness**: Validating deployment scenarios and startup procedures
5. **Edge Case Resilience**: Testing boundary conditions and error recovery
6. **Performance Tracking**: Monitoring for regressions and maintaining baselines

Together with the existing TESTS.md proposals, this creates a comprehensive testing strategy that ensures Foundation remains robust, secure, and performant in production environments.
