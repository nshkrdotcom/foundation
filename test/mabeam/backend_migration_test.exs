defmodule MABEAM.BackendMigrationTest do
  @moduledoc """
  Tests for the migration from MABEAM-specific backends to Foundation unified backends.

  Validates that the MABEAM.Agent module provides equivalent functionality
  to the previous MABEAM.ProcessRegistry while using the unified Foundation infrastructure.
  """
  use ExUnit.Case, async: false

  alias MABEAM.Agent
  alias Foundation.ProcessRegistry

  setup do
    on_exit(fn ->
      # Clean up any test agents
      try do
        agents = Agent.list_agents()

        Enum.each(agents, fn agent ->
          case agent.id do
            id when is_atom(id) ->
              id_str = Atom.to_string(id)

              if String.starts_with?(id_str, "migration_test_") do
                Agent.unregister_agent(id)
              end

            _ ->
              :ok
          end
        end)
      rescue
        _ -> :ok
      end
    end)

    :ok
  end

  describe "functional equivalence with previous MABEAM ProcessRegistry" do
    test "agent registration functionality matches previous interface" do
      # Test the equivalent of old MABEAM ProcessRegistry.register_agent
      agent_config = %{
        id: :migration_test_worker,
        type: :worker,
        module: MABEAM.TestWorker,
        args: [test: true],
        capabilities: [:computation, :data_processing],
        restart_policy: :permanent
      }

      # Register agent using new Agent module
      assert :ok = Agent.register_agent(agent_config)

      # Verify it's registered in the unified registry
      assert {:ok, metadata} =
               ProcessRegistry.get_metadata(:production, {:agent, :migration_test_worker})

      assert metadata.type == :mabeam_agent
      assert metadata.agent_type == :worker
      assert metadata.capabilities == [:computation, :data_processing]
    end

    test "agent lifecycle management matches previous functionality" do
      # Register an agent
      agent_config = %{
        id: :migration_test_lifecycle,
        type: :lifecycle_worker,
        module: MABEAM.TestWorker,
        capabilities: [:lifecycle_test]
      }

      assert :ok = Agent.register_agent(agent_config)

      # Verify agent is registered and can be started
      assert {:ok, :registered} = Agent.get_agent_status(:migration_test_lifecycle)

      # Test that we can get agent info (equivalent to previous agent queries)
      assert {:ok, info} = Agent.get_agent_info(:migration_test_lifecycle)
      assert info.id == :migration_test_lifecycle
      assert info.type == :lifecycle_worker
      assert info.capabilities == [:lifecycle_test]
      assert info.status == :registered
      # Not started yet
      assert info.pid == nil
    end

    test "agent discovery functionality matches previous capability queries" do
      # Register multiple agents with different capabilities
      agents = [
        %{id: :migration_test_nlp, type: :nlp_worker, capabilities: [:nlp, :text_processing]},
        %{
          id: :migration_test_cv,
          type: :cv_worker,
          capabilities: [:computer_vision, :image_processing]
        },
        %{
          id: :migration_test_hybrid,
          type: :hybrid_worker,
          capabilities: [:nlp, :computer_vision, :multimodal]
        }
      ]

      Enum.each(agents, fn config ->
        full_config = Map.put(config, :module, MABEAM.TestWorker)
        assert :ok = Agent.register_agent(full_config)
      end)

      # Test capability-based discovery (equivalent to old find_agents_by_capability)
      nlp_agents = Agent.find_agents_by_capability([:nlp])
      nlp_agent_ids = Enum.map(nlp_agents, & &1.id)

      assert :migration_test_nlp in nlp_agent_ids
      assert :migration_test_hybrid in nlp_agent_ids
      refute :migration_test_cv in nlp_agent_ids

      # Test multimodal capability discovery
      multimodal_agents = Agent.find_agents_by_capability([:nlp, :computer_vision])
      multimodal_agent_ids = Enum.map(multimodal_agents, & &1.id)

      assert :migration_test_hybrid in multimodal_agent_ids
      refute :migration_test_nlp in multimodal_agent_ids
      refute :migration_test_cv in multimodal_agent_ids

      # Test type-based discovery
      nlp_workers = Agent.find_agents_by_type(:nlp_worker)
      assert length(nlp_workers) == 1
      assert hd(nlp_workers).id == :migration_test_nlp
    end

    test "uses Foundation ProcessRegistry as unified backend" do
      # Register an agent
      agent_config = %{
        id: :migration_test_backend,
        type: :backend_test,
        module: MABEAM.TestWorker,
        capabilities: [:backend_testing]
      }

      assert :ok = Agent.register_agent(agent_config)

      # Verify it's using the Foundation ProcessRegistry
      agent_key = {:agent, :migration_test_backend}

      # Should be findable through Foundation ProcessRegistry
      assert {:ok, metadata} = ProcessRegistry.get_metadata(:production, agent_key)
      assert metadata.type == :mabeam_agent

      # Should appear in Foundation ProcessRegistry service listings
      services = ProcessRegistry.list_services(:production)
      assert agent_key in services

      # Should be discoverable through Foundation ProcessRegistry metadata queries
      mabeam_services =
        ProcessRegistry.find_services_by_metadata(:production, fn metadata ->
          metadata[:type] == :mabeam_agent
        end)

      backend_test_services =
        Enum.filter(mabeam_services, fn {_key, _pid, metadata} ->
          metadata[:agent_type] == :backend_test
        end)

      assert length(backend_test_services) == 1
      {found_key, _pid, found_metadata} = hd(backend_test_services)
      assert found_key == agent_key
      assert found_metadata.capabilities == [:backend_testing]
    end
  end

  describe "performance characteristics equivalent to previous backend" do
    test "maintains fast registration and lookup times" do
      # Register multiple agents quickly
      agent_count = 20

      registration_times =
        Enum.map(1..agent_count, fn i ->
          agent_config = %{
            id: :"migration_test_perf_#{i}",
            type: :performance_test,
            module: MABEAM.TestWorker,
            capabilities: [:performance]
          }

          start_time = System.monotonic_time(:microsecond)
          :ok = Agent.register_agent(agent_config)
          end_time = System.monotonic_time(:microsecond)

          end_time - start_time
        end)

      # Test lookup performance
      lookup_times =
        Enum.map(1..agent_count, fn i ->
          agent_id = :"migration_test_perf_#{i}"

          start_time = System.monotonic_time(:microsecond)
          {:ok, _status} = Agent.get_agent_status(agent_id)
          end_time = System.monotonic_time(:microsecond)

          end_time - start_time
        end)

      # Performance requirements
      avg_registration_time = Enum.sum(registration_times) / length(registration_times)
      avg_lookup_time = Enum.sum(lookup_times) / length(lookup_times)

      # Should maintain sub-millisecond performance
      # < 1ms average
      assert avg_registration_time < 1000
      # < 0.5ms average
      assert avg_lookup_time < 500

      # Test discovery performance
      start_time = System.monotonic_time(:microsecond)
      performance_agents = Agent.find_agents_by_capability([:performance])
      end_time = System.monotonic_time(:microsecond)
      discovery_time = end_time - start_time

      assert length(performance_agents) == agent_count
      # Discovery should be < 5ms
      assert discovery_time < 5000
    end
  end

  describe "data compatibility and migration safety" do
    test "handles complex metadata structures correctly" do
      # Test with complex metadata similar to what MABEAM ProcessRegistry handled
      complex_config = %{
        id: :migration_test_complex,
        type: :complex_agent,
        module: MABEAM.MLTestWorker,
        args: [model_type: :transformer],
        capabilities: [:nlp, :text_generation, :reasoning],
        custom_metadata: %{
          model_parameters: %{
            hidden_size: 768,
            num_layers: 12,
            num_heads: 12,
            vocab_size: 50257
          },
          training_info: %{
            dataset: "custom_corpus",
            epochs: 10,
            learning_rate: 0.00002
          },
          performance_metrics: %{
            perplexity: 15.2,
            bleu_score: 0.85,
            inference_speed: "150ms/token"
          }
        }
      }

      assert :ok = Agent.register_agent(complex_config)

      # Verify complex metadata is preserved
      assert {:ok, info} = Agent.get_agent_info(:migration_test_complex)
      assert info.type == :complex_agent
      assert info.capabilities == [:nlp, :text_generation, :reasoning]

      # Check that custom metadata is stored in the config
      assert {:ok, metadata} =
               ProcessRegistry.get_metadata(:production, {:agent, :migration_test_complex})

      assert metadata.config.custom_metadata.model_parameters.hidden_size == 768
      assert metadata.config.custom_metadata.performance_metrics.bleu_score == 0.85
    end
  end
end
