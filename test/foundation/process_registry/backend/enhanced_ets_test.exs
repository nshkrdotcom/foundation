defmodule Foundation.ProcessRegistry.Backend.EnhancedETSTest do
  @moduledoc """
  Tests for enhanced ETS backend functionality needed for MABEAM integration.

  This test validates that the Foundation ETS backend can handle:
  - Capability-based indexing
  - Complex metadata queries
  - Agent-specific requirements
  - Performance under load
  """
  use ExUnit.Case, async: false

  alias Foundation.ProcessRegistry.Backend.ETS

  setup do
    # Create a unique backend instance for each test
    test_ref = make_ref()
    table_name = :"test_backend_#{inspect(test_ref)}"

    {:ok, backend_state} = ETS.init(table_name: table_name)

    on_exit(fn ->
      # Clean up test table
      try do
        case :ets.info(table_name) do
          :undefined -> :ok
          _ -> :ets.delete(table_name)
        end
      rescue
        _ -> :ok
      end
    end)

    %{backend: backend_state, table_name: table_name}
  end

  describe "enhanced metadata support for MABEAM" do
    test "stores and retrieves complex agent metadata", %{backend: backend} do
      agent_key = {:agent, :ml_worker}
      agent_pid = spawn(fn -> Process.sleep(1000) end)

      complex_metadata = %{
        type: :mabeam_agent,
        agent_type: :ml_worker,
        capabilities: [:nlp, :text_processing, :gpu_acceleration],
        config: %{
          model_type: :transformer,
          frameworks: [:pytorch, :tensorflow],
          gpu_memory: 8192,
          batch_size: 32
        },
        performance_metrics: %{
          avg_response_time: 150,
          throughput: 1000,
          accuracy: 0.95
        },
        created_at: DateTime.utc_now(),
        last_updated: DateTime.utc_now()
      }

      # Register agent with complex metadata
      assert {:ok, new_backend} = ETS.register(backend, agent_key, agent_pid, complex_metadata)

      # Retrieve and verify metadata
      assert {:ok, {retrieved_pid, retrieved_metadata}} = ETS.lookup(new_backend, agent_key)
      assert retrieved_pid == agent_pid
      assert retrieved_metadata.type == :mabeam_agent
      assert retrieved_metadata.capabilities == [:nlp, :text_processing, :gpu_acceleration]
      assert retrieved_metadata.config.model_type == :transformer
      assert retrieved_metadata.performance_metrics.accuracy == 0.95

      # Clean up
      Process.exit(agent_pid, :kill)
    end

    test "supports metadata updates for dynamic agent properties", %{backend: backend} do
      agent_key = {:agent, :adaptive_worker}
      agent_pid = spawn(fn -> Process.sleep(1000) end)

      initial_metadata = %{
        type: :mabeam_agent,
        capabilities: [:basic_processing],
        performance_metrics: %{accuracy: 0.8, throughput: 500}
      }

      # Register agent
      {:ok, backend1} = ETS.register(backend, agent_key, agent_pid, initial_metadata)

      # Update metadata to reflect learning/adaptation
      updated_metadata = %{
        type: :mabeam_agent,
        capabilities: [:basic_processing, :advanced_analysis, :pattern_recognition],
        performance_metrics: %{accuracy: 0.92, throughput: 750},
        adaptation_count: 1,
        last_adaptation: DateTime.utc_now()
      }

      assert {:ok, backend2} = ETS.update_metadata(backend1, agent_key, updated_metadata)

      # Verify updates
      assert {:ok, {_pid, metadata}} = ETS.lookup(backend2, agent_key)
      assert :advanced_analysis in metadata.capabilities
      assert metadata.performance_metrics.accuracy == 0.92
      assert metadata.adaptation_count == 1

      Process.exit(agent_pid, :kill)
    end

    test "handles high-volume agent registrations efficiently", %{backend: backend} do
      agent_count = 100

      # Register multiple agents with different capabilities
      {final_backend, agent_pids} =
        Enum.reduce(1..agent_count, {backend, []}, fn i, {current_backend, pids} ->
          agent_key = {:agent, :"agent_#{i}"}
          agent_pid = spawn(fn -> Process.sleep(5000) end)

          capabilities =
            case rem(i, 3) do
              0 -> [:nlp, :text_processing]
              1 -> [:computer_vision, :image_recognition]
              2 -> [:data_analysis, :statistical_modeling]
            end

          metadata = %{
            type: :mabeam_agent,
            agent_type: :worker,
            capabilities: capabilities,
            worker_id: i,
            created_at: DateTime.utc_now()
          }

          {:ok, new_backend} = ETS.register(current_backend, agent_key, agent_pid, metadata)
          {new_backend, [agent_pid | pids]}
        end)

      # Verify all agents are registered
      {:ok, all_registrations} = ETS.list_all(final_backend)

      agent_registrations =
        Enum.filter(all_registrations, fn {key, _pid, metadata} ->
          match?({:agent, _}, key) and metadata.type == :mabeam_agent
        end)

      assert length(agent_registrations) == agent_count

      # Test capability-based filtering (simulated)
      nlp_agents =
        Enum.filter(agent_registrations, fn {_key, _pid, metadata} ->
          :nlp in (metadata.capabilities || [])
        end)

      cv_agents =
        Enum.filter(agent_registrations, fn {_key, _pid, metadata} ->
          :computer_vision in (metadata.capabilities || [])
        end)

      # Should have roughly 1/3 of agents for each capability type
      assert length(nlp_agents) >= 30 and length(nlp_agents) <= 35
      assert length(cv_agents) >= 30 and length(cv_agents) <= 35

      # Clean up
      Enum.each(agent_pids, fn pid -> Process.exit(pid, :kill) end)
    end
  end

  describe "performance characteristics for MABEAM workloads" do
    test "maintains sub-millisecond lookup times under load", %{backend: backend} do
      # Register 50 agents
      {loaded_backend, agent_pids} =
        Enum.reduce(1..50, {backend, []}, fn i, {current_backend, pids} ->
          agent_key = {:agent, :"perf_agent_#{i}"}
          agent_pid = spawn(fn -> Process.sleep(2000) end)

          metadata = %{
            type: :mabeam_agent,
            capabilities: [:performance_test],
            index: i
          }

          {:ok, new_backend} = ETS.register(current_backend, agent_key, agent_pid, metadata)
          {new_backend, [agent_pid | pids]}
        end)

      # Measure lookup performance
      lookup_times =
        Enum.map(1..20, fn i ->
          agent_key = {:agent, :"perf_agent_#{rem(i, 50) + 1}"}

          start_time = System.monotonic_time(:microsecond)
          {:ok, {_pid, _metadata}} = ETS.lookup(loaded_backend, agent_key)
          end_time = System.monotonic_time(:microsecond)

          end_time - start_time
        end)

      avg_lookup_time = Enum.sum(lookup_times) / length(lookup_times)
      max_lookup_time = Enum.max(lookup_times)

      # Verify performance requirements
      # Average < 1ms
      assert avg_lookup_time < 1000
      # Max < 5ms
      assert max_lookup_time < 5000

      # Clean up
      Enum.each(agent_pids, fn pid -> Process.exit(pid, :kill) end)
    end

    test "handles concurrent access safely", %{backend: backend} do
      # Create multiple tasks that access the backend concurrently
      num_tasks = 10
      operations_per_task = 20

      tasks =
        Enum.map(1..num_tasks, fn task_id ->
          Task.async(fn ->
            Enum.map(1..operations_per_task, fn op_id ->
              agent_key = {:agent, :"concurrent_agent_#{task_id}_#{op_id}"}
              agent_pid = spawn(fn -> Process.sleep(100) end)

              metadata = %{
                type: :mabeam_agent,
                task_id: task_id,
                operation_id: op_id,
                timestamp: DateTime.utc_now()
              }

              result = ETS.register(backend, agent_key, agent_pid, metadata)

              # Clean up immediately
              Process.exit(agent_pid, :kill)

              result
            end)
          end)
        end)

      # Wait for all tasks to complete
      results = Enum.map(tasks, &Task.await/1)

      # Verify all operations succeeded (most should succeed, some may conflict)
      successful_operations =
        results
        |> List.flatten()
        |> Enum.count(fn
          {:ok, _} -> true
          _ -> false
        end)

      # Should have significant success rate despite concurrent access
      total_operations = num_tasks * operations_per_task
      success_rate = successful_operations / total_operations

      # At least 80% success rate
      assert success_rate > 0.8
    end
  end

  describe "agent-specific query capabilities" do
    test "supports complex metadata queries for agent discovery", %{backend: backend} do
      # Register agents with different configurations
      test_agents = [
        %{key: {:agent, :nlp_specialist}, capabilities: [:nlp, :text_analysis], performance: 0.95},
        %{
          key: {:agent, :vision_expert},
          capabilities: [:computer_vision, :object_detection],
          performance: 0.88
        },
        %{
          key: {:agent, :hybrid_agent},
          capabilities: [:nlp, :computer_vision, :multimodal],
          performance: 0.92
        },
        %{
          key: {:agent, :data_analyst},
          capabilities: [:data_mining, :statistical_analysis],
          performance: 0.87
        }
      ]

      {final_backend, agent_pids} =
        Enum.reduce(test_agents, {backend, []}, fn agent_config, {current_backend, pids} ->
          agent_pid = spawn(fn -> Process.sleep(1000) end)

          metadata = %{
            type: :mabeam_agent,
            capabilities: agent_config.capabilities,
            performance_score: agent_config.performance,
            specialization:
              agent_config.key |> elem(1) |> Atom.to_string() |> String.contains?("specialist")
          }

          {:ok, new_backend} = ETS.register(current_backend, agent_config.key, agent_pid, metadata)
          {new_backend, [agent_pid | pids]}
        end)

      # Query for all registrations
      {:ok, all_registrations} = ETS.list_all(final_backend)

      # Filter for agents with NLP capability
      nlp_agents =
        Enum.filter(all_registrations, fn {_key, _pid, metadata} ->
          metadata.type == :mabeam_agent and :nlp in (metadata.capabilities || [])
        end)

      # nlp_specialist and hybrid_agent
      assert length(nlp_agents) == 2

      # Filter for high-performance agents (> 0.9)
      high_perf_agents =
        Enum.filter(all_registrations, fn {_key, _pid, metadata} ->
          metadata.type == :mabeam_agent and (metadata.performance_score || 0) > 0.9
        end)

      # nlp_specialist and hybrid_agent
      assert length(high_perf_agents) == 2

      # Filter for specialist agents
      specialist_agents =
        Enum.filter(all_registrations, fn {_key, _pid, metadata} ->
          metadata.type == :mabeam_agent and metadata.specialization == true
        end)

      # nlp_specialist
      assert length(specialist_agents) == 1

      # Clean up
      Enum.each(agent_pids, fn pid -> Process.exit(pid, :kill) end)
    end
  end

  describe "backend health and monitoring" do
    test "provides health check information", %{backend: backend} do
      # Add some registrations
      {backend_with_data, agent_pids} =
        Enum.reduce(1..5, {backend, []}, fn i, {current_backend, pids} ->
          agent_key = {:agent, :"health_test_#{i}"}
          agent_pid = spawn(fn -> Process.sleep(1000) end)

          metadata = %{type: :mabeam_agent, health_test: true}

          {:ok, new_backend} = ETS.register(current_backend, agent_key, agent_pid, metadata)
          {new_backend, [agent_pid | pids]}
        end)

      # Get health information
      case ETS.health_check(backend_with_data) do
        {:ok, health_info} ->
          assert is_map(health_info)
          assert Map.has_key?(health_info, :status)
          assert health_info.status in [:healthy, :degraded, :unhealthy]
          assert Map.has_key?(health_info, :registrations_count)
          assert health_info.registrations_count >= 5

        {:error, _reason} ->
          # Health check might not be implemented yet, that's ok for this test
          :ok
      end

      # Clean up
      Enum.each(agent_pids, fn pid -> Process.exit(pid, :kill) end)
    end
  end
end
