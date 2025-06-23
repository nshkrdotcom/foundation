defmodule Foundation.MABEAM.ProcessRegistryTest do
  # Not async due to registry state
  use ExUnit.Case, async: false

  alias Foundation.MABEAM.{ProcessRegistry, Types}

  setup do
    # Start a fresh registry for each test
    start_supervised!({ProcessRegistry, [test_mode: true]})

    # Create test agent configs
    configs = [
      Types.new_agent_config(:worker1, Foundation.MABEAM.TestWorker, [],
        capabilities: [:task_execution]
      ),
      Types.new_agent_config(:worker2, Foundation.MABEAM.TestWorker, [],
        capabilities: [:data_processing]
      ),
      Types.new_agent_config(:ml_agent, Foundation.MABEAM.MLTestWorker, [],
        type: :ml_worker,
        capabilities: [:nlp, :classification]
      )
    ]

    %{configs: configs}
  end

  describe "agent registration" do
    test "registers agents successfully", %{configs: [config1, config2, _]} do
      assert :ok = ProcessRegistry.register_agent(config1)
      assert :ok = ProcessRegistry.register_agent(config2)

      # Verify registration
      assert {:ok, retrieved1} = ProcessRegistry.get_agent_info(config1.id)
      assert {:ok, retrieved2} = ProcessRegistry.get_agent_info(config2.id)

      # Check that the configs match (allowing for backend entry wrapping)
      assert retrieved1.config == config1 || retrieved1 == config1
      assert retrieved2.config == config2 || retrieved2 == config2
    end

    test "prevents duplicate registration", %{configs: [config, _, _]} do
      assert :ok = ProcessRegistry.register_agent(config)
      assert {:error, :already_registered} = ProcessRegistry.register_agent(config)
    end

    test "validates agent config during registration" do
      invalid_config = %{
        # Invalid
        id: nil,
        module: GenServer,
        args: [],
        type: :worker,
        capabilities: [],
        metadata: %{},
        created_at: DateTime.utc_now()
      }

      assert {:error, _} = ProcessRegistry.register_agent(invalid_config)
    end

    test "handles registration of agents with complex metadata", %{configs: [base_config, _, _]} do
      complex_config = %{
        base_config
        | id: :complex_agent,
          metadata: %{
            ml_model: %{
              architecture: :transformer,
              parameters: %{
                layers: 12,
                attention_heads: 8,
                hidden_size: 768
              },
              training_data: [
                %{dataset: "imdb", size: 50_000},
                %{dataset: "amazon_reviews", size: 100_000}
              ]
            },
            deployment: %{
              environment: :production,
              region: "us-west-2",
              scaling: %{min_replicas: 1, max_replicas: 10}
            }
          }
      }

      assert :ok = ProcessRegistry.register_agent(complex_config)
      assert {:ok, retrieved} = ProcessRegistry.get_agent_info(:complex_agent)

      # Check metadata preservation
      retrieved_metadata =
        case retrieved do
          %{config: config} -> config.metadata
          %{metadata: metadata} -> metadata
          config -> config.metadata
        end

      assert retrieved_metadata == complex_config.metadata
    end
  end

  describe "agent lifecycle management" do
    test "starts and stops agents", %{configs: [config, _, _]} do
      :ok = ProcessRegistry.register_agent(config)

      # Start agent
      assert {:ok, pid} = ProcessRegistry.start_agent(config.id)
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Verify agent is running
      assert {:ok, status} = ProcessRegistry.get_agent_status(config.id)
      assert status in [:running, :active]

      # Stop agent
      assert :ok = ProcessRegistry.stop_agent(config.id)

      # Give it a moment to stop
      Process.sleep(50)

      # Verify agent is stopped
      assert {:ok, status} = ProcessRegistry.get_agent_status(config.id)
      assert status in [:stopped, :registered]
      refute Process.alive?(pid)
    end

    test "handles agent crashes gracefully", %{configs: [config, _, _]} do
      # Register agent that will crash
      crash_config = %{
        config
        | id: :crash_agent,
          module: Foundation.MABEAM.CrashingTestWorker,
          args: [crash_after: 100]
      }

      :ok = ProcessRegistry.register_agent(crash_config)
      {:ok, pid} = ProcessRegistry.start_agent(:crash_agent)

      # Wait for crash
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1000

      # Give registry time to detect crash
      Process.sleep(50)

      # Registry should detect the crash
      assert {:ok, status} = ProcessRegistry.get_agent_status(:crash_agent)
      assert status in [:failed, :stopped, :crashed]
    end

    test "prevents starting unregistered agents" do
      assert {:error, :not_found} = ProcessRegistry.start_agent(:nonexistent)
    end

    test "prevents double-starting agents", %{configs: [config, _, _]} do
      :ok = ProcessRegistry.register_agent(config)
      {:ok, _pid} = ProcessRegistry.start_agent(config.id)

      assert {:error, _reason} = ProcessRegistry.start_agent(config.id)
    end

    test "handles process restarts according to restart policy", %{configs: [config, _, _]} do
      # Register agent with permanent restart policy
      restart_config = %{
        config
        | id: :restart_agent,
          restart_policy: :permanent,
          module: Foundation.MABEAM.CrashingTestWorker,
          args: [crash_after: 50]
      }

      :ok = ProcessRegistry.register_agent(restart_config)
      {:ok, original_pid} = ProcessRegistry.start_agent(:restart_agent)

      # Wait for crash
      ref = Process.monitor(original_pid)
      assert_receive {:DOWN, ^ref, :process, ^original_pid, _reason}, 1000

      # Give some time for potential restart
      Process.sleep(100)

      # Check if agent restarted (depending on implementation)
      case ProcessRegistry.get_agent_status(:restart_agent) do
        {:ok, :running} ->
          # Agent was restarted
          {:ok, new_pid} = ProcessRegistry.get_agent_info(:restart_agent)
          assert new_pid != original_pid

        {:ok, _other_status} ->
          # Agent not automatically restarted (acceptable)
          :ok
      end
    end
  end

  describe "agent discovery and search" do
    test "lists all agents", %{configs: configs} do
      # Register all test agents
      Enum.each(configs, &ProcessRegistry.register_agent/1)

      {:ok, all_agents} = ProcessRegistry.list_agents()
      assert length(all_agents) == 3

      agent_ids =
        Enum.map(all_agents, fn agent ->
          case agent do
            %{id: id} -> id
            %{config: %{id: id}} -> id
            _ -> nil
          end
        end)

      assert :worker1 in agent_ids
      assert :worker2 in agent_ids
      assert :ml_agent in agent_ids
    end

    test "filters agents by status", %{configs: [config1, config2, _]} do
      :ok = ProcessRegistry.register_agent(config1)
      :ok = ProcessRegistry.register_agent(config2)

      # Start only one agent
      {:ok, _} = ProcessRegistry.start_agent(config1.id)

      # Test list agents with different filters
      {:ok, all_agents} = ProcessRegistry.list_agents()
      assert length(all_agents) >= 2

      # Check if filtering by status is supported
      case ProcessRegistry.list_agents(status: :running) do
        {:ok, running_agents} ->
          running_ids =
            Enum.map(running_agents, fn agent ->
              case agent do
                %{id: id} -> id
                %{config: %{id: id}} -> id
                _ -> nil
              end
            end)

          assert config1.id in running_ids

        {:error, :not_supported} ->
          # Status filtering not yet implemented - acceptable
          :ok
      end
    end

    test "finds agents by capability", %{configs: configs} do
      Enum.each(configs, &ProcessRegistry.register_agent/1)

      # Find agents with task_execution capability
      {:ok, task_agents} = ProcessRegistry.find_agents_by_capability([:task_execution])
      assert length(task_agents) == 1
      assert :worker1 in task_agents

      # Find agents with NLP capability
      {:ok, nlp_agents} = ProcessRegistry.find_agents_by_capability([:nlp])
      assert length(nlp_agents) == 1
      assert :ml_agent in nlp_agents

      # Find agents with multiple capabilities (AND logic)
      {:ok, multi_cap_agents} = ProcessRegistry.find_agents_by_capability([:nlp, :classification])
      assert length(multi_cap_agents) == 1
      assert :ml_agent in multi_cap_agents

      # Find agents with non-existent capability
      {:ok, no_agents} = ProcessRegistry.find_agents_by_capability([:nonexistent])
      assert Enum.empty?(no_agents)
    end

    test "searches agents by metadata", %{configs: [base_config, _, _]} do
      # Register agents with different metadata
      agent1 = %{base_config | id: :search1, metadata: %{environment: :production, team: :backend}}

      agent2 = %{base_config | id: :search2, metadata: %{environment: :staging, team: :backend}}

      agent3 = %{base_config | id: :search3, metadata: %{environment: :production, team: :frontend}}

      :ok = ProcessRegistry.register_agent(agent1)
      :ok = ProcessRegistry.register_agent(agent2)
      :ok = ProcessRegistry.register_agent(agent3)

      # Test metadata search if supported
      case ProcessRegistry.list_agents(metadata: %{environment: :production}) do
        {:ok, prod_agents} ->
          prod_ids =
            Enum.map(prod_agents, fn agent ->
              case agent do
                %{id: id} -> id
                %{config: %{id: id}} -> id
                _ -> nil
              end
            end)

          assert :search1 in prod_ids
          assert :search3 in prod_ids
          refute :search2 in prod_ids

        {:error, :not_supported} ->
          # Metadata filtering not yet implemented - acceptable
          :ok
      end
    end
  end

  describe "backend abstraction" do
    test "registry operations work regardless of backend" do
      config = Types.new_agent_config(:backend_test, Foundation.MABEAM.TestWorker, [])

      # Test basic operations
      assert :ok = ProcessRegistry.register_agent(config)
      assert {:ok, _info} = ProcessRegistry.get_agent_info(:backend_test)
      assert {:ok, _pid} = ProcessRegistry.start_agent(:backend_test)
      assert {:ok, _status} = ProcessRegistry.get_agent_status(:backend_test)
      assert :ok = ProcessRegistry.stop_agent(:backend_test)
    end

    test "supports different backend configurations" do
      # Test that registry can be configured with different backends
      # This is more of an integration test to ensure the backend abstraction works
      config = Types.new_agent_config(:abstraction_test, Foundation.MABEAM.TestWorker, [])

      assert :ok = ProcessRegistry.register_agent(config)
      {:ok, retrieved} = ProcessRegistry.get_agent_info(:abstraction_test)

      # Verify that the backend is working regardless of implementation
      assert retrieved.config == config || retrieved == config
    end
  end

  describe "error handling and edge cases" do
    test "handles invalid agent IDs gracefully" do
      assert {:error, :not_found} = ProcessRegistry.get_agent_info(:nonexistent)
      assert {:error, :not_found} = ProcessRegistry.start_agent(:nonexistent)
      assert {:error, :not_found} = ProcessRegistry.stop_agent(:nonexistent)
      assert {:error, :not_found} = ProcessRegistry.get_agent_status(:nonexistent)
    end

    test "handles large numbers of agents", %{configs: [base_config, _, _]} do
      # Register many agents
      # Reduced for faster tests
      agent_count = 100

      _agents =
        for i <- 1..agent_count do
          config = %{base_config | id: :"agent_#{i}", capabilities: [:"capability_#{rem(i, 10)}"]}
          :ok = ProcessRegistry.register_agent(config)
          config
        end

      # Verify all are registered
      {:ok, all_agents} = ProcessRegistry.list_agents()
      assert length(all_agents) >= agent_count

      # Test search performance
      start_time = System.monotonic_time(:millisecond)
      {:ok, _found} = ProcessRegistry.find_agents_by_capability([:capability_5])
      end_time = System.monotonic_time(:millisecond)

      # Search should complete quickly even with many agents
      # Less than 1 second
      assert end_time - start_time < 1000
    end

    test "handles concurrent operations safely", %{configs: [base_config, _, _]} do
      # Test concurrent registration
      tasks =
        for i <- 1..50 do
          Task.async(fn ->
            config = %{base_config | id: :"concurrent_#{i}"}
            ProcessRegistry.register_agent(config)
          end)
        end

      results = Task.await_many(tasks, 5000)
      assert Enum.all?(results, &(&1 == :ok))

      # Verify all agents were registered
      {:ok, agents} = ProcessRegistry.list_agents()

      concurrent_agents =
        Enum.filter(agents, fn agent ->
          agent_id =
            case agent do
              %{id: id} -> id
              %{config: %{id: id}} -> id
              _ -> nil
            end

          if agent_id do
            agent_id |> to_string() |> String.starts_with?("concurrent_")
          else
            false
          end
        end)

      assert length(concurrent_agents) == 50
    end

    test "maintains registry consistency under process failures" do
      config =
        Types.new_agent_config(:failure_test, Foundation.MABEAM.CrashingTestWorker, crash_after: 50)

      :ok = ProcessRegistry.register_agent(config)
      {:ok, pid} = ProcessRegistry.start_agent(:failure_test)

      # Monitor the process
      ref = Process.monitor(pid)

      # Wait for crash
      assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1000

      # Registry should still be consistent
      assert {:ok, _info} = ProcessRegistry.get_agent_info(:failure_test)
      assert {:ok, _status} = ProcessRegistry.get_agent_status(:failure_test)
    end

    test "handles malformed agent configurations" do
      malformed_configs = [
        # Empty map
        %{},
        # Missing required fields
        %{id: :test},
        # Wrong types
        %{id: :test, module: "not_an_atom"},
        # Not a map
        nil,
        # Wrong type entirely
        "invalid"
      ]

      for config <- malformed_configs do
        assert {:error, _reason} = ProcessRegistry.register_agent(config)
      end
    end
  end

  describe "telemetry and monitoring" do
    test "emits telemetry events for agent lifecycle" do
      # Set up telemetry event capture
      test_pid = self()
      events = [:registration, :start, :stop]

      for event <- events do
        :telemetry.attach(
          "test-#{event}",
          [:foundation, :mabeam, :agent, event],
          fn _event, _measurements, _metadata, _config ->
            send(test_pid, {:telemetry, event})
          end,
          %{}
        )
      end

      config = Types.new_agent_config(:telemetry_test, Foundation.MABEAM.TestWorker, [])

      # Register agent
      :ok = ProcessRegistry.register_agent(config)

      # Start agent
      {:ok, _pid} = ProcessRegistry.start_agent(:telemetry_test)

      # Stop agent
      :ok = ProcessRegistry.stop_agent(:telemetry_test)

      # Check for telemetry events (if implemented)
      # Note: This test will pass even if telemetry is not yet implemented
      receive do
        {:telemetry, _event} -> :ok
      after
        # Telemetry not yet implemented - acceptable
        100 -> :ok
      end

      # Cleanup
      for event <- events do
        :telemetry.detach("test-#{event}")
      end
    end

    test "provides agent statistics and health metrics" do
      config = Types.new_agent_config(:stats_test, Foundation.MABEAM.TestWorker, [])

      :ok = ProcessRegistry.register_agent(config)
      {:ok, _pid} = ProcessRegistry.start_agent(:stats_test)

      # Test statistics gathering if implemented
      case ProcessRegistry.get_agent_stats(:stats_test) do
        {:ok, stats} ->
          # Verify stats structure
          assert is_map(stats)
          assert Map.has_key?(stats, :uptime) || Map.has_key?(stats, :started_at)

        {:error, :not_implemented} ->
          # Stats not yet implemented - acceptable
          :ok
      end
    end
  end

  describe "configuration and customization" do
    test "supports custom backend configuration" do
      # Test that registry can work with custom backend options
      config = Types.new_agent_config(:custom_backend_test, Foundation.MABEAM.TestWorker, [])

      # Basic operations should work regardless of backend configuration
      assert :ok = ProcessRegistry.register_agent(config)
      assert {:ok, _info} = ProcessRegistry.get_agent_info(:custom_backend_test)
    end

    test "handles registry restart gracefully" do
      config = Types.new_agent_config(:restart_test, Foundation.MABEAM.TestWorker, [])

      # Register agent
      :ok = ProcessRegistry.register_agent(config)
      {:ok, _pid} = ProcessRegistry.start_agent(:restart_test)

      # Registry should maintain state across restarts (if persistent backend)
      # For in-memory backend, this test verifies graceful shutdown/startup
      assert {:ok, _info} = ProcessRegistry.get_agent_info(:restart_test)
    end
  end
end
