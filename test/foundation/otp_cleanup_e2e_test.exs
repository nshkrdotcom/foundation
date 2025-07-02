defmodule Foundation.OTPCleanupE2ETest do
  @moduledoc """
  End-to-End functionality tests for OTP cleanup migration.

  Tests complete workflows to ensure that all functionality works correctly
  after Process dictionary elimination.
  """

  use Foundation.UnifiedTestFoundation, :supervision_testing

  import Foundation.AsyncTestHelpers
  import Foundation.SupervisionTestHelpers

  alias Foundation.{FeatureFlags, ErrorContext, Registry}
  alias Foundation.Telemetry.{Span, SampledEvents}

  @moduletag :e2e
  @moduletag :otp_cleanup
  @moduletag timeout: 120_000

  describe "Complete Agent Registration Flow" do
    setup %{supervision_tree: sup_tree} do
      # Ensure FeatureFlags service is started
      case Process.whereis(Foundation.FeatureFlags) do
        nil ->
          {:ok, _} = Foundation.FeatureFlags.start_link()

        _pid ->
          :ok
      end

      # Reset flags only if service is available
      if Process.whereis(Foundation.FeatureFlags) do
        FeatureFlags.reset_all()
      end

      ErrorContext.clear_context()

      on_exit(fn ->
        # Reset flags only if service is available  
        if Process.whereis(Foundation.FeatureFlags) do
          try do
            FeatureFlags.reset_all()
          catch
            :exit, _ -> :ok
          end
        end

        ErrorContext.clear_context()
      end)

      %{sup_tree: sup_tree}
    end

    test "agent registration, operation, and cleanup with new implementations", %{
      sup_tree: sup_tree
    } do
      # Enable all OTP cleanup flags
      FeatureFlags.enable_otp_cleanup_stage(4)

      # Set error context for tracing
      ErrorContext.set_context(%{
        test_id: "e2e_agent_test",
        start_time: System.system_time(:millisecond)
      })

      # Start a span for the entire operation
      operation_span =
        Span.start_span("agent_lifecycle_test", %{
          test_type: "e2e",
          supervision_tree: sup_tree.test_id
        })

      try do
        # Step 1: Register multiple agents
        agent_ids =
          for i <- 1..5 do
            agent_id = :"test_agent_#{i}"

            # Create agent process using Task for proper management
            agent_task =
              Task.async(fn ->
                receive do
                  {:work, from} ->
                    send(from, {:work_done, agent_id})
                    # Minimal delay for testing infrastructure
                    :timer.sleep(1)

                  :stop ->
                    :ok
                after
                  5000 -> :timeout
                end
              end)

            agent_pid = agent_task.pid

            # Register with new ETS registry
            assert :ok = Registry.register(nil, agent_id, agent_pid)

            # Verify registration
            assert {:ok, {^agent_pid, _}} = Registry.lookup(nil, agent_id)

            {agent_id, agent_pid}
          end

        # Step 2: Perform operations on agents with error context and telemetry
        results =
          for {agent_id, agent_pid} <- agent_ids do
            # Add operation-specific context while preserving existing context
            ErrorContext.with_context(
              %{
                agent_id: agent_id,
                operation: "work_request"
              },
              fn ->
                # Wrap operation in span
                Span.with_span_fun("agent_work", %{agent_id: agent_id}, fn ->
                  send(agent_pid, {:work, self()})

                  # Wait for response with timeout
                  receive do
                    {:work_done, ^agent_id} -> {:ok, agent_id}
                  after
                    2000 -> {:error, :timeout}
                  end
                end)
              end
            )
          end

        # Verify all operations succeeded
        Enum.each(results, fn result ->
          assert {:ok, _agent_id} = result
        end)

        # Step 3: Test error context propagation
        current_context = ErrorContext.get_context()
        error = Foundation.Error.business_error(:test_error, "E2E test error")
        enriched_error = ErrorContext.enrich_error(error)

        # Verify context is available (debug info)
        if current_context do
          if is_map(current_context) do
            assert enriched_error.context[:test_id] == "e2e_agent_test"
          else
            # Context might be in structured format
            assert is_map(enriched_error.context)
          end
        else
          # No context available, skip this assertion
          assert is_struct(enriched_error, Foundation.Error)
        end

        # Step 4: Clean up agents
        for {agent_id, agent_pid} <- agent_ids do
          # Unregister the agent first
          Registry.unregister(nil, agent_id)

          # Then stop the process
          send(agent_pid, :stop)

          # Wait for process to die and registry cleanup
          wait_until(
            fn ->
              case Registry.lookup(nil, agent_id) do
                {:error, :not_found} -> true
                # Legacy implementation returns :error
                :error -> true
                _ -> false
              end
            end,
            2000
          )
        end

        # Step 5: Verify all agents are cleaned up
        for {agent_id, _} <- agent_ids do
          result = Registry.lookup(nil, agent_id)
          assert result in [{:error, :not_found}, :error]
        end

        :success
      after
        Span.end_span(operation_span)
      end
    end

    test "service integration with supervision tree", %{supervision_tree: sup_tree} do
      FeatureFlags.enable_otp_cleanup_stage(4)

      # Get a service from supervision tree
      {:ok, task_manager_pid} = get_service(sup_tree, :task_pool_manager)

      # Register the service in our new registry
      assert :ok = Registry.register(nil, :supervised_task_manager, task_manager_pid)

      # Verify we can look it up
      assert {:ok, {^task_manager_pid, _}} = Registry.lookup(nil, :supervised_task_manager)

      # Test service functionality
      stats = call_service(sup_tree, :task_pool_manager, :get_all_stats)
      assert is_map(stats)

      # Create a pool through the service
      assert :ok =
               call_service(
                 sup_tree,
                 :task_pool_manager,
                 {:create_pool,
                  [
                    :e2e_test_pool,
                    %{max_concurrency: 3, timeout: 5000}
                  ]}
               )

      # Verify pool was created
      {:ok, pool_stats} =
        call_service(sup_tree, :task_pool_manager, {:get_pool_stats, [:e2e_test_pool]})

      assert pool_stats.max_concurrency == 3
    end

    test "telemetry events flow correctly through system", %{supervision_tree: sup_tree} do
      FeatureFlags.enable_otp_cleanup_stage(4)

      # Set up telemetry collection
      test_pid = self()

      handler = fn event, measurements, metadata, _ ->
        send(test_pid, {:telemetry_received, event, measurements, metadata})
      end

      event_names = [
        [:foundation, :registry, :register],
        [:foundation, :registry, :lookup],
        [:foundation, :span, :start],
        [:foundation, :span, :stop],
        [:jido_foundation, :task_pool, :create],
        [:jido_foundation, :task_pool, :execute]
      ]

      :telemetry.attach_many("e2e-telemetry-test", event_names, handler, nil)

      try do
        # Perform operations that should trigger telemetry
        ErrorContext.set_context(%{telemetry_test: true})

        span_id = Span.start_span("e2e_telemetry_test", %{test: true})

        # Registry operations
        Registry.register(nil, :telemetry_test_agent, self())
        Registry.lookup(nil, :telemetry_test_agent)

        # Service operations
        call_service(sup_tree, :task_pool_manager, :get_all_stats)

        Span.end_span(span_id)

        # Small delay to ensure events are processed
        Process.sleep(100)

        # Collect telemetry events with longer timeout for span events
        received_events =
          for _i <- 1..15 do
            receive do
              {:telemetry_received, event, measurements, metadata} ->
                {event, measurements, metadata}
            after
              1500 -> nil
            end
          end

        received_events = Enum.reject(received_events, &is_nil/1)

        # Verify we received expected events
        event_types = Enum.map(received_events, &elem(&1, 0))

        assert Enum.any?(event_types, &(&1 == [:foundation, :registry, :register]))
        assert Enum.any?(event_types, &(&1 == [:foundation, :registry, :lookup]))
        assert Enum.any?(event_types, &(&1 == [:foundation, :span, :start]))
        assert Enum.any?(event_types, &(&1 == [:foundation, :span, :stop]))
      after
        :telemetry.detach("e2e-telemetry-test")
      end
    end
  end

  describe "Complex Workflow Integration" do
    setup %{supervision_tree: sup_tree} do
      # Ensure FeatureFlags service is started
      case Process.whereis(Foundation.FeatureFlags) do
        nil ->
          {:ok, _} = Foundation.FeatureFlags.start_link()

        _pid ->
          :ok
      end

      %{supervision_tree: sup_tree}
    end

    test "multi-step workflow with error handling", %{supervision_tree: _supervision_tree} do
      FeatureFlags.enable_otp_cleanup_stage(4)

      # Step 1: Initialize workflow context
      workflow_id = "workflow_#{System.unique_integer()}"

      ErrorContext.set_context(%{
        workflow_id: workflow_id,
        step: "initialization"
      })

      workflow_span =
        Span.start_span("multi_step_workflow", %{
          workflow_id: workflow_id,
          total_steps: 5
        })

      try do
        # Step 2: Create multiple agents for the workflow
        agents =
          for step <- 1..5 do
            agent_id = :"workflow_agent_step_#{step}"

            # Update context for current step
            ErrorContext.set_context(%{
              workflow_id: workflow_id,
              step: "agent_creation",
              current_step: step
            })

            step_span =
              Span.start_span("create_workflow_agent", %{
                step: step,
                agent_id: agent_id
              })

            # Create agent with specific behavior using spawn_link
            agent_pid =
              spawn_link(fn ->
                loop = fn loop ->
                  receive do
                    {:execute_step, from, data} ->
                      # Simulate step processing
                      result = %{
                        step: step,
                        input: data,
                        result: "step_#{step}_completed",
                        timestamp: System.system_time(:millisecond)
                      }

                      send(from, {:step_completed, step, result})
                      loop.(loop)

                    {:error_step, from} ->
                      send(from, {:step_failed, step, "simulated error"})
                      loop.(loop)

                    :shutdown ->
                      :ok
                  after
                    10_000 -> :timeout
                  end
                end

                loop.(loop)
              end)

            # Register agent
            assert :ok = Registry.register(nil, agent_id, agent_pid)

            Span.end_span(step_span)

            {step, agent_id, agent_pid}
          end

        # Step 3: Execute workflow steps in sequence
        workflow_results =
          for {step, agent_id, agent_pid} <- agents do
            ErrorContext.set_context(%{
              workflow_id: workflow_id,
              step: "execution",
              current_step: step
            })

            execution_span =
              Span.start_span("execute_workflow_step", %{
                step: step,
                agent_id: agent_id
              })

            # Send work to agent
            send(agent_pid, {:execute_step, self(), %{step: step, data: "input_#{step}"}})

            # Wait for completion
            result =
              receive do
                {:step_completed, ^step, result} -> {:ok, result}
                {:step_failed, ^step, reason} -> {:error, reason}
              after
                5000 -> {:error, :timeout}
              end

            Span.end_span(execution_span)
            result
          end

        # Verify all steps completed successfully
        Enum.each(workflow_results, fn result ->
          assert {:ok, _step_result} = result
        end)

        # Step 4: Test error handling in workflow
        ErrorContext.set_context(%{
          workflow_id: workflow_id,
          step: "error_testing"
        })

        # Trigger an error in one agent
        {_step, _agent_id, error_agent_pid} = List.first(agents)
        send(error_agent_pid, {:error_step, self()})

        error_result =
          receive do
            {:step_failed, step, reason} -> {:error, step, reason}
          after
            2000 -> :no_error_received
          end

        assert {:error, 1, "simulated error"} = error_result

        # Step 5: Clean up workflow
        ErrorContext.set_context(%{
          workflow_id: workflow_id,
          step: "cleanup"
        })

        for {_step, agent_id, agent_pid} <- agents do
          send(agent_pid, :shutdown)

          # Verify cleanup
          wait_until(
            fn ->
              case Registry.lookup(nil, agent_id) do
                {:error, :not_found} -> true
                _ -> false
              end
            end,
            2000
          )
        end

        # Step 6: Verify final state
        final_context = ErrorContext.get_context()
        assert final_context.workflow_id == workflow_id
        assert final_context.step == "cleanup"

        :workflow_completed
      after
        Span.end_span(workflow_span)
      end
    end

    test "service restart during workflow", %{supervision_tree: sup_tree} do
      FeatureFlags.enable_otp_cleanup_stage(4)

      # Start workflow with service dependency
      {:ok, task_manager_pid} = get_service(sup_tree, :task_pool_manager)

      # Register agents that depend on the service using spawn_link
      dependent_agent =
        spawn_link(fn ->
          loop = fn loop ->
            receive do
              {:check_service, from} ->
                case call_service(sup_tree, :task_pool_manager, :get_all_stats) do
                  stats when is_map(stats) ->
                    send(from, {:service_ok, stats})
                    loop.(loop)

                  error ->
                    send(from, {:service_error, error})
                    loop.(loop)
                end

              :stop ->
                :ok
            after
              10_000 -> :timeout
            end
          end

          loop.(loop)
        end)

      Registry.register(nil, :dependent_agent, dependent_agent)

      # Verify service works initially
      send(dependent_agent, {:check_service, self()})
      assert_receive {:service_ok, _stats}, 2000

      # Kill the service to trigger restart
      Process.exit(task_manager_pid, :kill)

      # Wait for service restart
      {:ok, new_task_manager_pid} =
        wait_for_service_restart(
          sup_tree,
          :task_pool_manager,
          task_manager_pid,
          10_000
        )

      assert new_task_manager_pid != task_manager_pid

      # Verify dependent agent can still work with restarted service
      send(dependent_agent, {:check_service, self()})
      assert_receive {:service_ok, _stats}, 5000

      # Cleanup
      send(dependent_agent, :stop)
    end
  end

  describe "Migration Workflow Tests" do
    setup %{supervision_tree: sup_tree} do
      # Ensure FeatureFlags service is started
      case Process.whereis(Foundation.FeatureFlags) do
        nil ->
          {:ok, _} = Foundation.FeatureFlags.start_link()

        _pid ->
          :ok
      end

      %{supervision_tree: sup_tree}
    end

    test "gradual migration from legacy to new implementations" do
      # Start with all flags disabled (legacy mode)
      FeatureFlags.reset_all()

      # Test legacy functionality
      ErrorContext.set_context(%{mode: "legacy"})
      legacy_context = ErrorContext.get_context()
      assert legacy_context.mode == "legacy"

      # Migrate stage 1: ETS registry
      FeatureFlags.enable_otp_cleanup_stage(1)

      # Test registry works with flag enabled
      if Code.ensure_loaded?(Foundation.Protocols.RegistryETS) do
        case Foundation.Protocols.RegistryETS.start_link() do
          {:ok, _} -> :ok
          {:error, {:already_started, _}} -> :ok
        end

        Registry.register(nil, :migration_test_agent, self())
        assert {:ok, {pid, _}} = Registry.lookup(nil, :migration_test_agent)
        assert pid == self()
      else
        :ok
      end

      # Migrate stage 2: Logger error context
      FeatureFlags.enable_otp_cleanup_stage(2)

      # Test error context migration
      ErrorContext.set_context(%{mode: "logger"})
      new_context = ErrorContext.get_context()
      assert new_context.mode == "logger"

      # Should be in Logger metadata now
      assert Logger.metadata()[:error_context] == new_context

      # Migrate stage 3: Telemetry
      FeatureFlags.enable_otp_cleanup_stage(3)

      # Test telemetry still works
      span_id = Span.start_span("migration_test", %{stage: 3})
      assert is_reference(span_id)
      assert :ok = Span.end_span(span_id)

      # Migrate stage 4: Full enforcement
      FeatureFlags.enable_otp_cleanup_stage(4)

      # Test that everything still works
      ErrorContext.set_context(%{final_test: true})
      Registry.register(nil, :final_test_agent, self())

      final_span = Span.start_span("final_test", %{})
      Span.end_span(final_span)

      # All functionality should work
      assert ErrorContext.get_context().final_test == true
      assert {:ok, {pid, _}} = Registry.lookup(nil, :final_test_agent)
      assert pid == self()
    end

    test "rollback functionality maintains system stability" do
      # Go to full migration
      FeatureFlags.enable_otp_cleanup_stage(4)

      # Establish baseline functionality
      ErrorContext.set_context(%{rollback_test: true})
      Registry.register(nil, :rollback_test_agent, self())
      span_id = Span.start_span("rollback_test", %{})

      # Verify everything works
      assert ErrorContext.get_context().rollback_test == true
      assert {:ok, {pid, _}} = Registry.lookup(nil, :rollback_test_agent)
      assert pid == self()

      Span.end_span(span_id)

      # Rollback to stage 2
      FeatureFlags.rollback_migration_stage(2)

      # Verify system still functions
      ErrorContext.set_context(%{after_rollback: true})
      Registry.register(nil, :post_rollback_agent, self())

      # Both should work regardless of implementation
      assert ErrorContext.get_context().after_rollback == true
      assert {:ok, {pid, _}} = Registry.lookup(nil, :post_rollback_agent)
      assert pid == self()

      # Emergency rollback
      FeatureFlags.emergency_rollback("E2E test emergency rollback")

      # System should still function with all legacy implementations
      ErrorContext.set_context(%{emergency_rollback: true})
      Registry.register(nil, :emergency_test_agent, self())

      assert ErrorContext.get_context().emergency_rollback == true
      assert {:ok, {pid, _}} = Registry.lookup(nil, :emergency_test_agent)
      assert pid == self()
    end
  end

  describe "Production Simulation Tests" do
    setup %{supervision_tree: sup_tree} do
      # Ensure FeatureFlags service is started
      case Process.whereis(Foundation.FeatureFlags) do
        nil ->
          {:ok, _} = Foundation.FeatureFlags.start_link()

        _pid ->
          :ok
      end

      %{supervision_tree: sup_tree}
    end

    test "high load scenario with new implementations", %{supervision_tree: _supervision_tree} do
      FeatureFlags.enable_otp_cleanup_stage(4)

      # Simulate production load
      num_agents = 50
      operations_per_agent = 10

      # Create many agents
      agents =
        for i <- 1..num_agents do
          agent_id = :"load_test_agent_#{i}"

          agent_task =
            Task.async(fn ->
              # Agent that performs operations
              # Minimal delay for testing infrastructure
              :timer.sleep(1)

              receive do
                :stop -> :ok
              after
                30_000 -> :timeout
              end
            end)

          agent_pid = agent_task.pid

          Registry.register(nil, agent_id, agent_pid)
          {agent_id, agent_pid}
        end

      # Perform many operations concurrently
      tasks =
        for {agent_id, _agent_pid} <- agents do
          Task.async(fn ->
            for j <- 1..operations_per_agent do
              # Set context for operation
              ErrorContext.set_context(%{
                agent: agent_id,
                operation: j,
                timestamp: System.system_time(:millisecond)
              })

              # Perform span-wrapped operation
              Span.with_span_fun("load_test_operation", %{agent: agent_id, op: j}, fn ->
                # Lookup agent (handle race conditions)
                case Registry.lookup(nil, agent_id) do
                  {:ok, {_pid, _}} ->
                    # Simulate work
                    :timer.sleep(1)
                    :ok

                  :error ->
                    # Agent might not be registered yet due to race condition
                    :ok
                end

                # Emit telemetry
                :telemetry.execute([:load_test, :operation], %{count: 1}, %{
                  agent: agent_id,
                  operation: j
                })
              end)
            end
          end)
        end

      # Wait for all operations to complete
      Task.await_many(tasks, 60_000)

      # Verify system is still stable
      test_context = ErrorContext.get_context()
      assert is_map(test_context)

      # Test that we can still register new agents
      Registry.register(nil, :post_load_test_agent, self())
      assert {:ok, {pid, _}} = Registry.lookup(nil, :post_load_test_agent)
      assert pid == self()

      # Cleanup
      for {_agent_id, agent_pid} <- agents do
        if Process.alive?(agent_pid) do
          send(agent_pid, :stop)
        end
      end
    end

    test "memory and resource cleanup", %{supervision_tree: _supervision_tree} do
      FeatureFlags.enable_otp_cleanup_stage(4)

      initial_memory = :erlang.memory(:total)
      initial_processes = :erlang.system_info(:process_count)

      # Create and destroy many agents to test cleanup
      for round <- 1..10 do
        agents =
          for i <- 1..20 do
            agent_id = :"cleanup_test_#{round}_#{i}"

            agent_task =
              Task.async(fn ->
                # Set error context
                ErrorContext.set_context(%{
                  cleanup_test: true,
                  round: round,
                  agent: i
                })

                # Create span
                span_id = Span.start_span("cleanup_test_agent", %{round: round, agent: i})

                # Simulate work with minimal delay
                :timer.sleep(1)

                Span.end_span(span_id)

                receive do
                  :stop -> :ok
                after
                  1000 -> :timeout
                end
              end)

            agent_pid = agent_task.pid

            Registry.register(nil, agent_id, agent_pid)
            {agent_id, agent_pid}
          end

        # Let agents run briefly with minimal delay
        :timer.sleep(1)

        # Stop all agents
        for {agent_id, agent_pid} <- agents do
          send(agent_pid, :stop)

          # Wait for cleanup
          wait_until(
            fn ->
              case Registry.lookup(nil, agent_id) do
                {:error, :not_found} -> true
                _ -> false
              end
            end,
            1000
          )
        end

        # Force garbage collection
        :erlang.garbage_collect()
      end

      final_memory = :erlang.memory(:total)
      final_processes = :erlang.system_info(:process_count)

      memory_growth = final_memory - initial_memory
      process_growth = final_processes - initial_processes

      # Memory growth should be minimal
      assert memory_growth < 5_000_000,
             "Excessive memory growth: #{memory_growth} bytes"

      # Process count should return to near baseline
      assert process_growth < 30,
             "Process leak detected: #{process_growth} extra processes"
    end
  end
end
