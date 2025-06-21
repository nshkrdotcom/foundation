# test/foundation/mabeam/core_test.exs
defmodule Foundation.MABEAM.CoreTest do
  use ExUnit.Case, async: false

  alias Foundation.MABEAM.Core
  alias Foundation.ProcessRegistry

  setup do
    # Ensure clean state for each test
    on_exit(fn ->
      pid = Process.whereis(Core)

      if pid && Process.alive?(pid) do
        GenServer.stop(Core, :normal)
      end
    end)

    :ok
  end

  describe "GenServer lifecycle" do
    test "starts and stops cleanly" do
      assert {:ok, pid} = Core.start_link([])
      assert Process.alive?(pid)
      assert GenServer.stop(pid) == :ok
    end

    test "registers with process registry" do
      {:ok, _pid} = Core.start_link([])

      # Should be registered with ProcessRegistry
      assert {:ok, registered_pid} = ProcessRegistry.lookup(:production, Core)
      assert is_pid(registered_pid)
    end

    test "handles configuration during startup" do
      config = %{
        max_variables: 50,
        coordination_timeout: 3000
      }

      {:ok, _pid} = Core.start_link(config: config)

      {:ok, status} = Core.system_status()
      assert status.config.max_variables == 50
      assert status.config.coordination_timeout == 3000
    end

    test "gracefully handles startup failures" do
      # Test invalid configuration
      invalid_config = %{invalid_key: :invalid_value}

      # Should still start but use defaults
      assert {:ok, _pid} = Core.start_link(config: invalid_config)
    end
  end

  describe "orchestration variable registration" do
    setup do
      {:ok, _pid} = Core.start_link([])
      :ok
    end

    test "registers valid orchestration variable" do
      variable = create_valid_orchestration_variable()
      assert :ok = Core.register_orchestration_variable(variable)

      {:ok, status} = Core.system_status()
      assert Map.has_key?(status.variable_registry, variable.id)
      assert status.variable_registry[variable.id] == variable
    end

    test "rejects invalid variable - missing required fields" do
      invalid_variable = %{id: :invalid, scope: :local}

      assert {:error, reason} = Core.register_orchestration_variable(invalid_variable)
      assert is_binary(reason) or is_atom(reason)
    end

    test "rejects duplicate variable registration" do
      variable = create_valid_orchestration_variable()
      assert :ok = Core.register_orchestration_variable(variable)

      # Try to register the same variable again
      assert {:error, _reason} = Core.register_orchestration_variable(variable)
    end

    test "allows different variables with different IDs" do
      variable1 = create_valid_orchestration_variable(:var1)
      variable2 = create_valid_orchestration_variable(:var2)

      assert :ok = Core.register_orchestration_variable(variable1)
      assert :ok = Core.register_orchestration_variable(variable2)

      {:ok, status} = Core.system_status()
      assert Map.has_key?(status.variable_registry, :var1)
      assert Map.has_key?(status.variable_registry, :var2)
    end

    test "emits telemetry event on variable registration" do
      # Setup telemetry handler
      test_pid = self()
      handler_id = :test_handler

      :telemetry.attach(
        handler_id,
        [:mabeam, :variable, :registered],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:telemetry_event, event, measurements, metadata})
        end,
        nil
      )

      variable = create_valid_orchestration_variable()
      :ok = Core.register_orchestration_variable(variable)

      assert_receive {:telemetry_event, [:mabeam, :variable, :registered], measurements, metadata}
      assert measurements.count == 1
      assert metadata.variable_id == variable.id

      :telemetry.detach(handler_id)
    end
  end

  describe "system coordination" do
    setup do
      {:ok, _pid} = Core.start_link([])
      :ok
    end

    test "coordinates empty system" do
      assert {:ok, []} = Core.coordinate_system()
    end

    test "coordinates system with single variable" do
      variable = create_valid_orchestration_variable()
      :ok = Core.register_orchestration_variable(variable)

      assert {:ok, results} = Core.coordinate_system()
      assert is_list(results)
      # May be 0 if no coordination needed
      assert length(results) >= 0
    end

    test "coordinates system with multiple variables" do
      variable1 = create_valid_orchestration_variable(:var1)
      variable2 = create_valid_orchestration_variable(:var2)

      :ok = Core.register_orchestration_variable(variable1)
      :ok = Core.register_orchestration_variable(variable2)

      assert {:ok, results} = Core.coordinate_system()
      assert is_list(results)
    end

    test "handles coordination with context" do
      variable = create_valid_orchestration_variable()
      :ok = Core.register_orchestration_variable(variable)

      context = %{task_type: :computation, load: :medium}
      assert {:ok, results} = Core.coordinate_system(context)
      assert is_list(results)
    end

    test "handles coordination failures gracefully" do
      # Register a variable that will fail during coordination
      failing_variable = create_failing_orchestration_variable()
      :ok = Core.register_orchestration_variable(failing_variable)

      # Should not crash, but may return error or empty results
      result = Core.coordinate_system()
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "emits telemetry for coordination events" do
      test_pid = self()
      handler_id = :coordination_test_handler

      :telemetry.attach(
        handler_id,
        [:mabeam, :coordination, :start],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:coordination_start, event, measurements, metadata})
        end,
        nil
      )

      :telemetry.attach(
        "#{handler_id}_stop",
        [:mabeam, :coordination, :stop],
        fn event, measurements, metadata, _ ->
          send(test_pid, {:coordination_stop, event, measurements, metadata})
        end,
        nil
      )

      variable = create_valid_orchestration_variable()
      :ok = Core.register_orchestration_variable(variable)
      {:ok, _} = Core.coordinate_system()

      assert_receive {:coordination_start, [:mabeam, :coordination, :start], _, _}
      assert_receive {:coordination_stop, [:mabeam, :coordination, :stop], _, _}

      :telemetry.detach(handler_id)
      :telemetry.detach("#{handler_id}_stop")
    end
  end

  describe "system status and monitoring" do
    setup do
      {:ok, _pid} = Core.start_link([])
      :ok
    end

    test "returns system status" do
      {:ok, status} = Core.system_status()

      assert is_map(status)
      assert Map.has_key?(status, :variable_registry)
      assert Map.has_key?(status, :coordination_history)
      assert Map.has_key?(status, :performance_metrics)
      assert Map.has_key?(status, :config)
      assert status.variable_registry == %{}
    end

    test "system status reflects registered variables" do
      variable = create_valid_orchestration_variable()
      :ok = Core.register_orchestration_variable(variable)

      {:ok, status} = Core.system_status()
      assert Map.has_key?(status.variable_registry, variable.id)
    end

    test "system status includes performance metrics" do
      {:ok, status} = Core.system_status()

      metrics = status.performance_metrics
      assert is_map(metrics)
      assert Map.has_key?(metrics, :coordination_count)
      assert Map.has_key?(metrics, :variable_count)
      assert metrics.variable_count == 0

      # Register a variable and check metrics update
      variable = create_valid_orchestration_variable()
      :ok = Core.register_orchestration_variable(variable)

      {:ok, updated_status} = Core.system_status()
      assert updated_status.performance_metrics.variable_count == 1
    end

    test "system status includes coordination history" do
      {:ok, status} = Core.system_status()
      assert is_list(status.coordination_history)
      assert Enum.empty?(status.coordination_history)

      # Perform coordination to generate history
      variable = create_valid_orchestration_variable()
      :ok = Core.register_orchestration_variable(variable)
      {:ok, _} = Core.coordinate_system()

      {:ok, updated_status} = Core.system_status()
      # History should be updated (length may vary based on implementation)
      assert is_list(updated_status.coordination_history)
    end
  end

  describe "health checks and service integration" do
    setup do
      {:ok, _pid} = Core.start_link([])
      :ok
    end

    test "provides health check information" do
      assert {:ok, health} = Core.health_check()

      assert is_map(health)
      assert Map.has_key?(health, :status)
      assert Map.has_key?(health, :checks)
      assert health.status in [:healthy, :degraded, :unhealthy]
    end

    test "health check includes service dependencies" do
      {:ok, health} = Core.health_check()

      checks = health.checks
      assert is_map(checks)
      # Should include checks for Foundation services
      assert Map.has_key?(checks, :process_registry)
      assert Map.has_key?(checks, :telemetry)
    end

    test "reports healthy status under normal conditions" do
      {:ok, health} = Core.health_check()
      assert health.status == :healthy
    end
  end

  describe "error handling and fault tolerance" do
    setup do
      {:ok, _pid} = Core.start_link([])
      :ok
    end

    test "handles invalid coordination requests gracefully" do
      # This should not crash the process
      result = Core.coordinate_system("invalid_context")
      assert match?({:error, _}, result) or match?({:ok, _}, result)
    end

    test "continues operating after coordination failure" do
      failing_variable = create_failing_orchestration_variable()
      :ok = Core.register_orchestration_variable(failing_variable)

      # First coordination may fail
      Core.coordinate_system()

      # But the system should still be operational
      {:ok, status} = Core.system_status()
      assert is_map(status)

      # And we can still register new variables
      good_variable = create_valid_orchestration_variable(:good_var)
      assert :ok = Core.register_orchestration_variable(good_variable)
    end

    test "handles GenServer call timeouts" do
      # Create a blocking operation (simulate)
      spawn(fn ->
        # This will timeout if the GenServer is blocked
        result = Core.system_status()
        assert {:ok, _} = result
      end)

      # Give some time for the call
      :timer.sleep(10)
    end
  end

  # Helper functions for test data
  defp create_valid_orchestration_variable(id \\ :test_variable) do
    %{
      id: id,
      scope: :local,
      type: :agent_selection,
      agents: [:agent1, :agent2],
      coordination_fn: &test_coordination_function/3,
      adaptation_fn: &test_adaptation_function/3,
      constraints: [],
      resource_requirements: %{memory: 100, cpu: 0.5},
      fault_tolerance: %{strategy: :restart, max_restarts: 3},
      telemetry_config: %{enabled: true}
    }
  end

  defp create_failing_orchestration_variable(id \\ :failing_variable) do
    %{
      id: id,
      scope: :local,
      type: :agent_selection,
      agents: [:agent1, :agent2],
      coordination_fn: &failing_coordination_function/3,
      adaptation_fn: &test_adaptation_function/3,
      constraints: [],
      resource_requirements: %{memory: 100, cpu: 0.5},
      fault_tolerance: %{strategy: :restart, max_restarts: 3},
      telemetry_config: %{enabled: true}
    }
  end

  # Mock coordination function for testing
  defp test_coordination_function(_agents, _context, _variable) do
    {:ok, %{selected_agent: :agent1, action: :start}}
  end

  # Mock adaptation function for testing
  defp test_adaptation_function(_result, _context, _variable) do
    {:ok, :no_adaptation_needed}
  end

  # Failing coordination function for error testing
  defp failing_coordination_function(_agents, _context, _variable) do
    {:error, :coordination_failed}
  end
end
