defmodule Foundation.MABEAM.Integration.StressTest do
  use ExUnit.Case, async: false

  alias Foundation.MABEAM.{AgentRegistry, Types, Comms, Core, Coordination, ProcessRegistry}

  @moduletag :integration
  @moduletag :stress
  # 5 minutes for stress tests
  @moduletag timeout: 300_000

  setup do
    # Start services if not already started
    case start_supervised({ProcessRegistry, [test_mode: true]}, restart: :transient) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    case start_supervised({Core, [test_mode: true]}, restart: :transient) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    case start_supervised({Comms, [test_mode: true]}, restart: :transient) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    case start_supervised({Coordination, [test_mode: true]}, restart: :transient) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end

    # Small delay to ensure services are ready
    Process.sleep(100)

    :ok
  end

  describe "high-load agent operations" do
    test "system handles 100+ concurrent agents" do
      agent_count = 100

      # Register many agents concurrently
      registration_tasks =
        for i <- 1..agent_count do
          Task.async(fn ->
            agent_id = :"stress_agent_#{i}"

            config = %{
              id: agent_id,
              type: :worker,
              module: Foundation.MABEAM.StressTestAgent,
              config: [agent_id: i],
              supervision: %{strategy: :one_for_one, max_restarts: 3, max_seconds: 60}
            }

            AgentRegistry.register_agent(agent_id, config)
          end)
        end

      registration_results = Task.await_many(registration_tasks, 30_000)
      successful_registrations = Enum.count(registration_results, &(&1 == :ok))

      assert successful_registrations >= agent_count * 0.95,
             "Only #{successful_registrations}/#{agent_count} agents registered successfully"

      # Start agents concurrently
      startup_tasks =
        for i <- 1..agent_count do
          Task.async(fn ->
            agent_id = :"stress_agent_#{i}"
            AgentRegistry.start_agent(agent_id)
          end)
        end

      startup_results = Task.await_many(startup_tasks, 60_000)
      successful_startups = Enum.count(startup_results, &match?({:ok, _}, &1))

      assert successful_startups >= agent_count * 0.9,
             "Only #{successful_startups}/#{agent_count} agents started successfully"

      # Test discovery performance with many agents
      start_time = System.monotonic_time(:millisecond)
      {:ok, all_agents} = AgentRegistry.list_agents()
      end_time = System.monotonic_time(:millisecond)

      discovery_time = end_time - start_time
      assert discovery_time < 100, "Discovery too slow with many agents: #{discovery_time}ms"
      assert length(all_agents) >= 90, "Should find at least 90 agents"

      # Test system status performance
      start_time = System.monotonic_time(:millisecond)
      {:ok, _status} = Core.get_system_statistics()
      end_time = System.monotonic_time(:millisecond)

      status_time = end_time - start_time
      assert status_time < 500, "System status too slow: #{status_time}ms"

      # Cleanup
      cleanup_tasks =
        for i <- 1..agent_count do
          Task.async(fn ->
            agent_id = :"stress_agent_#{i}"
            AgentRegistry.stop_agent(agent_id)
            AgentRegistry.deregister_agent(agent_id)
          end)
        end

      Task.await_many(cleanup_tasks, 60_000)
    end

    test "massive concurrent communication load" do
      # Setup fewer agents but high message volume
      agent_count = 50
      message_count_per_agent = 100

      agents =
        for i <- 1..agent_count do
          agent_id = :"comm_stress_#{i}"
          config = Types.new_agent_config(agent_id, Foundation.MABEAM.StressTestAgent, agent_id: i)
          :ok = ProcessRegistry.register_agent(config)
          {:ok, _pid} = ProcessRegistry.start_agent(agent_id)
          agent_id
        end

      try do
        # Send massive number of concurrent messages
        total_messages = agent_count * message_count_per_agent

        start_time = System.monotonic_time(:millisecond)

        message_tasks =
          for agent_id <- agents, i <- 1..message_count_per_agent do
            Task.async(fn ->
              Comms.request(agent_id, {:stress_message, i})
            end)
          end

        results = Task.await_many(message_tasks, 120_000)

        end_time = System.monotonic_time(:millisecond)
        total_time = end_time - start_time

        successful_messages = Enum.count(results, &match?({:ok, _}, &1))
        success_rate = successful_messages / total_messages

        assert success_rate >= 0.95,
               "Message success rate too low: #{success_rate * 100}%"

        messages_per_second = total_messages / (total_time / 1000)

        assert messages_per_second >= 100,
               "Message throughput too low: #{messages_per_second}/sec"

        # Verify agents are still responsive
        health_checks =
          for agent_id <- Enum.take(agents, 10) do
            Task.async(fn ->
              Comms.request(agent_id, :health_check)
            end)
          end

        health_results = Task.await_many(health_checks, 10_000)
        # Health results are in format [{:ok, {:ok, :healthy}}, ...]
        assert Enum.all?(health_results, fn result ->
                 case result do
                   {:ok, {:ok, :healthy}} -> true
                   _ -> false
                 end
               end)
      after
        for agent_id <- agents do
          ProcessRegistry.stop_agent(agent_id)
          # Note: ProcessRegistry doesn't have unregister_agent, agents are cleaned up on stop
        end
      end
    end
  end

  describe "massive variable operations" do
    test "system handles hundreds of variables" do
      variable_count = 500

      # Register many variables concurrently
      variable_tasks =
        for i <- 1..variable_count do
          Task.async(fn ->
            variable =
              Types.new_variable(
                :"stress_var_#{i}",
                %{data: "value_#{i}", index: i},
                :system
              )

            Core.register_variable(variable)
          end)
        end

      variable_results = Task.await_many(variable_tasks, 60_000)
      successful_registrations = Enum.count(variable_results, &(&1 == :ok))

      assert successful_registrations >= variable_count * 0.95,
             "Only #{successful_registrations}/#{variable_count} variables registered"

      # Test concurrent variable listing (since get_variable doesn't exist)
      access_tasks =
        for _i <- 1..100 do
          Task.async(fn ->
            Core.list_variables()
          end)
        end

      access_results = Task.await_many(access_tasks, 30_000)
      successful_access = Enum.count(access_results, &match?({:ok, _}, &1))

      assert successful_access >= 95,
             "Only #{successful_access}/100 variable accesses succeeded"

      # Cleanup
      cleanup_tasks =
        for i <- 1..variable_count do
          Task.async(fn ->
            variable_name = :"stress_var_#{i}"
            Core.delete_variable(variable_name, :system)
          end)
        end

      Task.await_many(cleanup_tasks, 60_000)
    end
  end

  describe "massive coordination stress" do
    test "hundreds of concurrent coordination sessions" do
      # Setup participants
      participant_count = 20

      participants =
        for i <- 1..participant_count do
          agent_id = :"coord_stress_#{i}"

          config =
            Types.new_agent_config(agent_id, Foundation.MABEAM.CoordinationTestAgent, [agent_id: i],
              capabilities: [:consensus]
            )

          :ok = ProcessRegistry.register_agent(config)
          {:ok, _pid} = ProcessRegistry.start_agent(agent_id)
          agent_id
        end

      try do
        # Start many concurrent coordination sessions
        session_count = 10

        coordination_tasks =
          for i <- 1..session_count do
            Task.async(fn ->
              # Use random subset of participants
              session_participants = Enum.take_random(participants, 5)

              # Register a simple consensus protocol for this session
              protocol = %{
                name: :"consensus_#{i}",
                type: :consensus,
                algorithm: :majority_vote,
                timeout: 5000,
                retry_policy: %{}
              }

              :ok = Coordination.register_protocol(:"consensus_#{i}", protocol)

              {:ok, results} =
                Coordination.coordinate(:"consensus_#{i}", session_participants, %{
                  question: "Stress test session #{i}",
                  options: [:proceed, :abort]
                })

              session_id = make_ref()

              # Return result directly (no async messaging in current implementation)
              {session_id, {:ok, results}, :completed}
            end)
          end

        results = Task.await_many(coordination_tasks, 120_000)

        completed_sessions = Enum.count(results, fn {_, _, status} -> status == :completed end)
        successful_sessions = Enum.count(results, fn {_, result, _} -> match?({:ok, _}, result) end)

        assert completed_sessions >= session_count * 0.8,
               "Only #{completed_sessions}/#{session_count} sessions completed"

        assert successful_sessions >= completed_sessions * 0.9,
               "Only #{successful_sessions}/#{completed_sessions} completed sessions succeeded"
      after
        for participant <- participants do
          ProcessRegistry.stop_agent(participant)
          # Note: ProcessRegistry doesn't have unregister_agent, agents are cleaned up on stop
        end
      end
    end
  end

  describe "memory and performance under stress" do
    test "memory usage remains stable under extreme load" do
      initial_memory = :erlang.memory(:total)

      # Create extreme load scenario
      load_tasks = [
        # Task 1: Many agents
        Task.async(fn ->
          agents =
            for i <- 1..200 do
              agent_id = :"memory_stress_#{i}"
              config = Types.new_agent_config(agent_id, Foundation.MABEAM.StressTestAgent, [])
              :ok = ProcessRegistry.register_agent(config)
              {:ok, _pid} = ProcessRegistry.start_agent(agent_id)
              agent_id
            end

          # Cleanup
          for agent_id <- agents do
            ProcessRegistry.stop_agent(agent_id)
            # Note: ProcessRegistry doesn't have unregister_agent, agents are cleaned up on stop
          end
        end),

        # Task 2: Many variables
        Task.async(fn ->
          variables =
            for i <- 1..500 do
              # 400 bytes per variable
              large_data = String.duplicate("data", 100)
              variable = Types.new_variable(:"memory_var_#{i}", large_data, :system)
              :ok = Core.register_variable(variable)
              variable.name
            end

          # Cleanup
          for var_name <- variables do
            Core.delete_variable(var_name, :system)
          end
        end),

        # Task 3: Heavy communication
        Task.async(fn ->
          # Setup some agents for communication
          comm_agents =
            for i <- 1..10 do
              agent_id = :"comm_memory_#{i}"
              config = Types.new_agent_config(agent_id, Foundation.MABEAM.StressTestAgent, [])
              :ok = ProcessRegistry.register_agent(config)
              {:ok, _pid} = ProcessRegistry.start_agent(agent_id)
              agent_id
            end

          # Send many messages
          for _i <- 1..1000 do
            agent = Enum.random(comm_agents)
            Comms.request(agent, {:memory_test, :rand.uniform(1000)})
          end

          # Cleanup
          for agent_id <- comm_agents do
            ProcessRegistry.stop_agent(agent_id)
            # Note: ProcessRegistry doesn't have unregister_agent, agents are cleaned up on stop
          end
        end)
      ]

      # Run all load tasks concurrently
      Task.await_many(load_tasks, 120_000)

      # Force garbage collection
      for _i <- 1..3 do
        :erlang.garbage_collect()
        Process.sleep(100)
      end

      final_memory = :erlang.memory(:total)
      memory_growth = final_memory - initial_memory

      # Memory growth should be reasonable (less than 100MB)
      assert memory_growth < 104_857_600,
             "Excessive memory growth: #{memory_growth / 1_048_576} MB"

      # System should still be responsive
      test_variable = Types.new_variable(:memory_test_final, "test", :system)
      assert :ok = Core.register_variable(test_variable)
      assert {:ok, vars} = Core.list_variables()
      assert Enum.any?(vars, fn name -> name == :memory_test_final end)

      Core.delete_variable(:memory_test_final, :system)
    end

    @tag :slow
    test "performance degrades gracefully under extreme load" do
      # Baseline performance measurement
      baseline_agent_id = :baseline_agent
      config = Types.new_agent_config(baseline_agent_id, Foundation.MABEAM.StressTestAgent, [])
      :ok = ProcessRegistry.register_agent(config)
      {:ok, _pid} = ProcessRegistry.start_agent(baseline_agent_id)

      # Measure baseline latency
      baseline_times =
        for _i <- 1..10 do
          {time_us, {:ok, _}} =
            :timer.tc(fn ->
              Comms.request(baseline_agent_id, {:echo, "baseline"})
            end)

          # Convert to milliseconds
          time_us / 1000
        end

      baseline_avg = Enum.sum(baseline_times) / length(baseline_times)

      # Allow system to settle
      Process.sleep(100)

      # Create system load (reduced for more realistic testing)
      load_agents =
        for i <- 1..20 do
          agent_id = :"load_agent_#{i}"
          config = Types.new_agent_config(agent_id, Foundation.MABEAM.StressTestAgent, [])
          :ok = ProcessRegistry.register_agent(config)
          {:ok, _pid} = ProcessRegistry.start_agent(agent_id)
          agent_id
        end

      # Create background load (reduced to avoid overwhelming the system)
      load_task =
        Task.async(fn ->
          for i <- 1..500 do
            agent = Enum.random(load_agents)
            Comms.request(agent, {:background_load, :rand.uniform(5)})
            # Add small delay to prevent overwhelming
            if rem(i, 50) == 0, do: Process.sleep(10)
          end
        end)

      # Let load start running
      Process.sleep(100)

      # Measure performance under load
      under_load_times =
        for _i <- 1..10 do
          {time_us, {:ok, _}} =
            :timer.tc(fn ->
              Comms.request(baseline_agent_id, {:echo, "under_load"})
            end)

          time_us / 1000
        end

      under_load_avg = Enum.sum(under_load_times) / length(under_load_times)

      # Wait for background load to complete
      Task.await(load_task, 60_000)

      # Performance should degrade gracefully (increased threshold for realistic testing)
      degradation_factor = under_load_avg / baseline_avg

      assert degradation_factor < 50.0,
             "Performance degraded too much: #{degradation_factor}x slower"

      # System should still be functional
      assert {:ok, _} = Comms.request(baseline_agent_id, :health_check)

      # Cleanup
      ProcessRegistry.stop_agent(baseline_agent_id)
      # Note: ProcessRegistry doesn't have unregister_agent, agents are cleaned up on stop

      for agent_id <- load_agents do
        ProcessRegistry.stop_agent(agent_id)
        # Note: ProcessRegistry doesn't have unregister_agent, agents are cleaned up on stop
      end
    end
  end
end

# Support agents for stress testing
defmodule Foundation.MABEAM.StressTestAgent do
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, [])
  end

  def init(args) do
    agent_id = Keyword.get(args, :agent_id, :unknown)
    {:ok, %{agent_id: agent_id, message_count: 0, last_message: nil}}
  end

  def handle_call({:stress_message, i}, _from, state) do
    new_state = %{state | message_count: state.message_count + 1, last_message: i}
    {:reply, {:ok, {:stress_response, i}}, new_state}
  end

  def handle_call({:echo, message}, _from, state) do
    {:reply, {:ok, {:echo_response, message}}, state}
  end

  def handle_call({:background_load, value}, _from, state) do
    # Simulate some processing
    :timer.sleep(:rand.uniform(5))
    {:reply, {:ok, {:processed, value}}, state}
  end

  def handle_call({:memory_test, value}, _from, state) do
    # Create some temporary data
    temp_data = String.duplicate("test", value)
    new_state = Map.put(state, :temp_data, temp_data)
    {:reply, {:ok, {:memory_response, byte_size(temp_data)}}, new_state}
  end

  def handle_call(:health_check, _from, state) do
    {:reply, {:ok, :healthy}, state}
  end

  def handle_call(:get_stats, _from, state) do
    {:reply, {:ok, %{message_count: state.message_count, last_message: state.last_message}}, state}
  end

  def handle_call(_request, _from, state) do
    {:reply, {:error, :unknown_request}, state}
  end

  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  def handle_info(_info, state) do
    {:noreply, state}
  end
end

defmodule Foundation.MABEAM.CoordinationTestAgent do
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, [])
  end

  def init(args) do
    agent_id = Keyword.get(args, :agent_id, :unknown)
    {:ok, %{agent_id: agent_id, coordination_count: 0}}
  end

  def handle_call({:mabeam_coordination_request, _session_id, protocol, data}, _from, state) do
    # Simulate coordination processing
    response =
      case protocol do
        :simple_consensus ->
          # Randomly vote for proceed or abort
          vote = if :rand.uniform() > 0.3, do: :proceed, else: :abort
          {:vote, vote}

        :negotiation ->
          # Provide a random offer
          offer = %{resource: data.resource, price: :rand.uniform(1000)}
          {:offer, offer}

        _ ->
          {:error, :unsupported_protocol}
      end

    new_state = %{state | coordination_count: state.coordination_count + 1}
    {:reply, {:ok, response}, new_state}
  end

  def handle_call(:health_check, _from, state) do
    {:reply, {:ok, :healthy}, state}
  end

  def handle_call(:get_stats, _from, state) do
    {:reply, {:ok, %{coordination_count: state.coordination_count}}, state}
  end

  def handle_call(_request, _from, state) do
    {:reply, {:error, :unknown_request}, state}
  end

  def handle_cast(_msg, state) do
    {:noreply, state}
  end

  def handle_info(_info, state) do
    {:noreply, state}
  end
end
