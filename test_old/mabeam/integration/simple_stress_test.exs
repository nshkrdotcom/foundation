defmodule MABEAM.Integration.SimpleStressTest do
  use ExUnit.Case, async: false

  alias MABEAM.{AgentRegistry, Core}

  @moduletag :integration
  @moduletag :stress
  # 1 minute for simple stress tests
  @moduletag timeout: 60_000

  setup do
    # Services are already started by the application
    # Small delay to ensure services are ready
    Process.sleep(100)
    :ok
  end

  describe "basic stress testing" do
    test "system handles multiple concurrent agents" do
      agent_count = 10

      # Register agents concurrently
      registration_tasks =
        for i <- 1..agent_count do
          Task.async(fn ->
            agent_id = :"simple_stress_agent_#{i}"

            config = %{
              id: agent_id,
              type: :worker,
              module: MABEAM.SimpleStressAgent,
              config: %{agent_id: i},
              supervision: %{strategy: :one_for_one, max_restarts: 3, max_seconds: 60}
            }

            AgentRegistry.register_agent(agent_id, config)
          end)
        end

      registration_results = Task.await_many(registration_tasks, 10_000)
      successful_registrations = Enum.count(registration_results, &(&1 == :ok))

      assert successful_registrations >= agent_count * 0.9,
             "Only #{successful_registrations}/#{agent_count} agents registered successfully"

      # Start agents concurrently
      startup_tasks =
        for i <- 1..agent_count do
          Task.async(fn ->
            agent_id = :"simple_stress_agent_#{i}"
            AgentRegistry.start_agent(agent_id)
          end)
        end

      startup_results = Task.await_many(startup_tasks, 10_000)
      successful_startups = Enum.count(startup_results, &match?({:ok, _}, &1))

      assert successful_startups >= agent_count * 0.8,
             "Only #{successful_startups}/#{agent_count} agents started successfully"

      # Test agent listing performance
      start_time = System.monotonic_time(:millisecond)
      {:ok, all_agents} = AgentRegistry.list_agents()
      end_time = System.monotonic_time(:millisecond)

      discovery_time = end_time - start_time
      assert discovery_time < 100, "Discovery too slow: #{discovery_time}ms"
      assert length(all_agents) >= agent_count * 0.8, "Should find most agents"

      # Cleanup
      cleanup_tasks =
        for i <- 1..agent_count do
          Task.async(fn ->
            agent_id = :"simple_stress_agent_#{i}"
            AgentRegistry.stop_agent(agent_id)
            AgentRegistry.deregister_agent(agent_id)
          end)
        end

      Task.await_many(cleanup_tasks, 10_000)
    end

    test "system handles core operations under load" do
      # Test multiple concurrent core operations
      operation_count = 20

      operation_tasks =
        for i <- 1..operation_count do
          Task.async(fn ->
            # Test different core operations concurrently
            case rem(i, 3) do
              0 -> Core.get_system_statistics()
              1 -> Core.get_performance_metrics()
              2 -> Core.list_orchestration_variables()
            end
          end)
        end

      operation_results = Task.await_many(operation_tasks, 10_000)
      successful_operations = Enum.count(operation_results, &match?({:ok, _}, &1))

      assert successful_operations >= operation_count * 0.9,
             "Only #{successful_operations}/#{operation_count} core operations succeeded"
    end

    test "system status remains responsive" do
      # Test system statistics performance
      start_time = System.monotonic_time(:millisecond)
      {:ok, _status} = Core.get_system_statistics()
      end_time = System.monotonic_time(:millisecond)

      status_time = end_time - start_time
      assert status_time < 500, "System status too slow: #{status_time}ms"

      # Test agent registry health
      {:ok, health} = AgentRegistry.system_health()
      assert is_map(health)
      assert Map.has_key?(health, :total_agents)
    end
  end
end

# Simple support agent for stress testing
defmodule MABEAM.SimpleStressAgent do
  use GenServer

  def start_link(args) do
    GenServer.start_link(__MODULE__, args, [])
  end

  def init(args) do
    agent_id = Map.get(args, :agent_id, :unknown)
    {:ok, %{agent_id: agent_id, message_count: 0}}
  end

  def handle_call(:health_check, _from, state) do
    {:reply, {:ok, :healthy}, state}
  end

  def handle_call({:echo, message}, _from, state) do
    {:reply, {:ok, {:echo_response, message}}, state}
  end

  def handle_call(:get_stats, _from, state) do
    {:reply, {:ok, %{message_count: state.message_count}}, state}
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
