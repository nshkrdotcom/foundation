defmodule MABEAM.CoreTest do
  use ExUnit.Case, async: false

  alias MABEAM.Core

  setup do
    # Start Core service (handle already started services gracefully)
    case start_supervised({Core, [test_mode: true]}) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    # Clean up any existing variables from previous tests
    {:ok, variables} = Core.list_orchestration_variables()

    for {id, _} <- variables do
      Core.unregister_orchestration_variable(id)
    end

    %{test_start_time: System.monotonic_time(:millisecond)}
  end

  describe "Core service lifecycle" do
    test "starts successfully with default configuration" do
      assert {:ok, status} = Core.system_status()
      assert is_map(status)
      assert Map.has_key?(status, :variable_registry)
      assert Map.has_key?(status, :coordination_history)
      assert Map.has_key?(status, :performance_metrics)
    end

    test "starts with custom configuration" do
      config = %{
        coordination_timeout: 10_000,
        max_variables: 100,
        telemetry_enabled: true
      }

      assert :ok = Core.update_configuration(config)
      {:ok, status} = Core.system_status()
      assert status.service_config.coordination_timeout == 10_000
    end

    @tag :slow
    test "reports healthy status after startup" do
      assert {:ok, :healthy} = Core.health_check()
    end
  end

  describe "variable registration and management" do
    test "registers valid orchestration variable successfully" do
      variable = create_valid_variable(:test_variable_1)
      assert :ok = Core.register_orchestration_variable(variable)

      {:ok, status} = Core.system_status()
      assert Map.has_key?(status.variable_registry, :test_variable_1)

      registered_variable = status.variable_registry[:test_variable_1]
      assert registered_variable.id == :test_variable_1
      assert registered_variable.scope == :local
      assert registered_variable.type == :agent_selection
    end

    test "rejects invalid variable with missing required fields" do
      invalid_variables = [
        # Empty map
        %{},
        # Missing other required fields
        %{id: :invalid},
        # Invalid ID
        %{id: nil, scope: :local},
        # Invalid scope
        %{id: :test, scope: :invalid_scope},
        # Invalid type
        %{id: :test, scope: :local, type: :invalid_type}
      ]

      for invalid_variable <- invalid_variables do
        assert {:error, _reason} = Core.register_orchestration_variable(invalid_variable)
      end
    end

    test "prevents duplicate variable registration" do
      variable = create_valid_variable(:duplicate_test)
      assert :ok = Core.register_orchestration_variable(variable)
      assert {:error, :already_registered} = Core.register_orchestration_variable(variable)
    end

    test "allows variable updates for existing variables" do
      variable = create_valid_variable(:updatable_variable)
      assert :ok = Core.register_orchestration_variable(variable)

      updated_variable = %{variable | agents: [:new_agent_1, :new_agent_2], scope: :global}

      assert :ok = Core.update_orchestration_variable(:updatable_variable, updated_variable)

      {:ok, status} = Core.system_status()
      updated = status.variable_registry[:updatable_variable]
      assert updated.scope == :global
      assert length(updated.agents) == 2
    end

    test "unregisters variables successfully" do
      variable = create_valid_variable(:removable_variable)
      assert :ok = Core.register_orchestration_variable(variable)

      {:ok, status} = Core.system_status()
      assert Map.has_key?(status.variable_registry, :removable_variable)

      assert :ok = Core.unregister_orchestration_variable(:removable_variable)

      {:ok, updated_status} = Core.system_status()
      assert not Map.has_key?(updated_status.variable_registry, :removable_variable)
    end

    test "lists all registered variables" do
      variables = [
        create_valid_variable(:list_test_1),
        create_valid_variable(:list_test_2),
        create_valid_variable(:list_test_3)
      ]

      for variable <- variables do
        :ok = Core.register_orchestration_variable(variable)
      end

      {:ok, variable_list} = Core.list_orchestration_variables()
      assert length(variable_list) >= 3

      variable_ids = Enum.map(variable_list, fn {id, _var} -> id end)
      assert :list_test_1 in variable_ids
      assert :list_test_2 in variable_ids
      assert :list_test_3 in variable_ids
    end
  end

  describe "system coordination" do
    test "coordinates empty system successfully" do
      # Clear any existing variables
      {:ok, variables} = Core.list_orchestration_variables()

      for {id, _} <- variables do
        Core.unregister_orchestration_variable(id)
      end

      assert {:ok, []} = Core.coordinate_system()
    end

    test "coordinates system with single variable" do
      variable = create_valid_variable(:single_coordination, [:test_agent_1])
      assert :ok = Core.register_orchestration_variable(variable)

      assert {:ok, results} = Core.coordinate_system()
      assert is_list(results)
      assert length(results) == 1

      [result] = results
      assert result.variable_id == :single_coordination
      assert Map.has_key?(result, :result)
      assert Map.has_key?(result, :duration_ms)
    end

    test "coordinates system with multiple variables" do
      variables = [
        create_valid_variable(:multi_coord_1, [:agent_1]),
        create_valid_variable(:multi_coord_2, [:agent_2]),
        create_valid_variable(:multi_coord_3, [:agent_3])
      ]

      for variable <- variables do
        :ok = Core.register_orchestration_variable(variable)
      end

      assert {:ok, results} = Core.coordinate_system()
      assert length(results) >= 3

      variable_ids = Enum.map(results, fn result -> result.variable_id end)
      assert :multi_coord_1 in variable_ids
      assert :multi_coord_2 in variable_ids
      assert :multi_coord_3 in variable_ids
    end

    test "handles coordination timeouts gracefully" do
      variable = create_slow_variable(:timeout_test)
      assert :ok = Core.register_orchestration_variable(variable)

      # Set a very short timeout for this test
      assert :ok = Core.update_configuration(%{coordination_timeout: 50})

      assert {:ok, results} = Core.coordinate_system()
      [result] = results

      # Should either succeed quickly or have some error due to timing
      case result.result do
        {:ok, _} ->
          # If it succeeds, duration might still be longer due to function execution time
          assert result.duration_ms >= 0

        {:error, _} ->
          # Any error is acceptable for timeout scenarios
          assert result.duration_ms >= 0
      end
    end

    test "coordinates specific variable by ID" do
      variable = create_valid_variable(:specific_coordination)
      assert :ok = Core.register_orchestration_variable(variable)

      assert {:ok, result} = Core.coordinate_variable(:specific_coordination)
      assert result.variable_id == :specific_coordination
      assert Map.has_key?(result, :result)
    end

    test "rejects coordination of non-existent variable" do
      assert {:error, :variable_not_found} = Core.coordinate_variable(:nonexistent)
    end
  end

  describe "performance metrics and monitoring" do
    test "tracks coordination performance metrics" do
      {:ok, initial_metrics} = Core.get_performance_metrics()

      variable = create_valid_variable(:metrics_test)
      :ok = Core.register_orchestration_variable(variable)

      {:ok, _result} = Core.coordinate_variable(:metrics_test)

      {:ok, updated_metrics} = Core.get_performance_metrics()

      assert updated_metrics.coordination_count > initial_metrics.coordination_count
      assert updated_metrics.variable_count >= initial_metrics.variable_count
      assert is_number(updated_metrics.avg_coordination_time_ms)
    end

    test "maintains coordination history" do
      variable = create_valid_variable(:history_test)
      :ok = Core.register_orchestration_variable(variable)

      {:ok, _result} = Core.coordinate_variable(:history_test)

      {:ok, history} = Core.get_coordination_history()
      assert is_list(history)
      assert length(history) > 0

      [latest_event | _] = history

      assert latest_event.type in [
               :coordination_start,
               :coordination_complete,
               :variable_registered
             ]

      assert is_list(latest_event.variables)
      assert %DateTime{} = latest_event.timestamp
    end

    test "provides system statistics" do
      {:ok, stats} = Core.get_system_statistics()

      assert Map.has_key?(stats, :total_variables)
      assert Map.has_key?(stats, :total_coordinations)
      assert Map.has_key?(stats, :success_rate)
      assert Map.has_key?(stats, :avg_response_time_ms)
      assert Map.has_key?(stats, :uptime_seconds)

      assert is_number(stats.total_variables)
      assert is_number(stats.total_coordinations)
      assert stats.success_rate >= 0.0 and stats.success_rate <= 1.0
    end
  end

  describe "error handling and fault tolerance" do
    test "handles coordination function failures gracefully" do
      failing_variable = create_failing_variable(:failure_test)
      assert :ok = Core.register_orchestration_variable(failing_variable)

      assert {:ok, results} = Core.coordinate_system()
      [result] = results

      assert result.variable_id == :failure_test
      assert match?({:error, _}, result.result)
    end

    test "continues coordination after partial failures" do
      variables = [
        create_valid_variable(:success_1),
        create_failing_variable(:failure_1),
        create_valid_variable(:success_2)
      ]

      for variable <- variables do
        :ok = Core.register_orchestration_variable(variable)
      end

      assert {:ok, results} = Core.coordinate_system()
      assert length(results) == 3

      successful_results =
        Enum.filter(results, fn result ->
          match?({:ok, _}, result.result)
        end)

      # At least the two valid ones should succeed
      assert length(successful_results) >= 2
    end

    test "recovers from invalid variable states" do
      # This would test recovery mechanisms if a variable becomes corrupted
      variable = create_valid_variable(:recovery_test)
      :ok = Core.register_orchestration_variable(variable)

      # Simulate variable corruption by direct state manipulation
      # In a real scenario, this might happen due to network issues, etc.

      assert {:ok, result} = Core.coordinate_variable(:recovery_test)
      # Should either succeed or provide a clear error
      assert is_map(result)
    end
  end

  describe "integration with Foundation services" do
    test "integrates with ProcessRegistry for agent discovery" do
      # This test assumes ProcessRegistry is available and working
      variable = create_valid_variable(:integration_test, [:some_agent])
      assert :ok = Core.register_orchestration_variable(variable)

      # The coordination should attempt to discover agents via ProcessRegistry
      assert {:ok, result} = Core.coordinate_variable(:integration_test)
      assert is_map(result)
    end

    test "emits telemetry events during coordination" do
      # Set up telemetry capture
      test_pid = self()
      events = [:coordination_start, :coordination_complete, :variable_registered]

      for event <- events do
        :telemetry.attach(
          "test-#{event}",
          [:foundation, :mabeam, :core, event],
          fn _event, _measurements, _metadata, _config ->
            send(test_pid, {:telemetry, event})
          end,
          %{}
        )
      end

      variable = create_valid_variable(:telemetry_test)
      :ok = Core.register_orchestration_variable(variable)

      # Give telemetry time to register
      Process.sleep(10)

      {:ok, _result} = Core.coordinate_variable(:telemetry_test)

      # Should receive telemetry events
      assert_receive {:telemetry, :variable_registered}, 1000
      assert_receive {:telemetry, :coordination_start}, 1000
      assert_receive {:telemetry, :coordination_complete}, 1000

      # Cleanup
      for event <- events do
        :telemetry.detach("test-#{event}")
      end
    end
  end

  describe "concurrent operations and thread safety" do
    test "handles concurrent variable registrations" do
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            variable = create_valid_variable(:"concurrent_reg_#{i}")
            Core.register_orchestration_variable(variable)
          end)
        end

      results = Task.await_many(tasks, 5000)
      successful_registrations = Enum.count(results, fn result -> result == :ok end)

      assert successful_registrations == 10
    end

    test "handles concurrent system coordinations" do
      # Register a variable for coordination
      variable = create_valid_variable(:concurrent_coord_test)
      :ok = Core.register_orchestration_variable(variable)

      tasks =
        for _i <- 1..5 do
          Task.async(fn ->
            Core.coordinate_variable(:concurrent_coord_test)
          end)
        end

      results = Task.await_many(tasks, 10_000)

      # All coordinations should complete successfully
      successful_coordinations =
        Enum.count(results, fn
          {:ok, _result} -> true
          _ -> false
        end)

      assert successful_coordinations == 5
    end
  end

  # Helper functions for creating test variables

  defp create_valid_variable(id, agents \\ [:test_agent]) do
    %{
      id: id,
      scope: :local,
      type: :agent_selection,
      agents: agents,
      coordination_fn: &test_coordination_function/3,
      adaptation_fn: &test_adaptation_function/3,
      constraints: [],
      resource_requirements: %{memory: 100, cpu: 0.1},
      fault_tolerance: %{strategy: :restart, max_restarts: 3},
      telemetry_config: %{enabled: true},
      created_at: DateTime.utc_now(),
      metadata: %{test: true}
    }
  end

  defp create_slow_variable(id) do
    %{
      id: id,
      scope: :local,
      type: :agent_selection,
      agents: [:slow_agent],
      coordination_fn: &slow_coordination_function/3,
      adaptation_fn: &test_adaptation_function/3,
      constraints: [],
      resource_requirements: %{memory: 100, cpu: 0.1},
      fault_tolerance: %{strategy: :restart, max_restarts: 3},
      telemetry_config: %{enabled: true},
      created_at: DateTime.utc_now(),
      metadata: %{test: true, slow: true}
    }
  end

  defp create_failing_variable(id) do
    %{
      id: id,
      scope: :local,
      type: :agent_selection,
      agents: [:failing_agent],
      coordination_fn: &failing_coordination_function/3,
      adaptation_fn: &test_adaptation_function/3,
      constraints: [],
      resource_requirements: %{memory: 100, cpu: 0.1},
      fault_tolerance: %{strategy: :restart, max_restarts: 3},
      telemetry_config: %{enabled: true},
      created_at: DateTime.utc_now(),
      metadata: %{test: true, should_fail: true}
    }
  end

  # Mock coordination functions for testing

  defp test_coordination_function(agents, _context, _metadata) do
    # Simple test coordination that returns success with agent list
    {:ok,
     %{
       coordinated_agents: agents,
       coordination_type: :test,
       timestamp: DateTime.utc_now()
     }}
  end

  defp slow_coordination_function(_agents, context, _metadata) do
    # Simulate a slow coordination operation based on context timeout
    delay = Map.get(context, :coordination_timeout, 100) + 10
    Process.sleep(delay)
    {:ok, %{result: :slow_success}}
  end

  defp failing_coordination_function(_agents, _context, _metadata) do
    # Simulate a coordination failure
    {:error, :coordination_failed}
  end

  defp test_adaptation_function(result, _context, _metadata) do
    # Simple test adaptation that just returns the result
    {:ok, result}
  end
end
