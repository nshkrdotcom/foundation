defmodule JidoFoundation.BridgeTest do
  # Using supervision testing mode for Bridge tests to support service dependencies
  use Foundation.UnifiedTestFoundation, :supervision_testing

  alias JidoFoundation.Bridge

  # Mock Jido agent for testing
  defmodule MockJidoAgent do
    use GenServer

    def start_link(config) do
      GenServer.start_link(__MODULE__, config)
    end

    def init(config) do
      {:ok, %{config: config, state: :ready}}
    end

    def handle_call(:get_state, _from, state) do
      {:reply, state, state}
    end

    def handle_call({:execute, action}, _from, state) do
      result =
        case action do
          :success -> {:ok, :completed}
          :failure -> {:error, :failed}
          :crash -> raise "Simulated crash"
        end

      {:reply, result, state}
    end
  end

  describe "register_agent/2" do
    test "registers Jido agent with Foundation", %{supervision_tree: sup_tree} do
      {:ok, agent} = MockJidoAgent.start_link(%{})

      # Foundation.UnifiedTestFoundation :supervision_testing mode handles all process cleanup automatically

      assert :ok =
               Bridge.register_agent(agent,
                 capabilities: [:test, :mock],
                 metadata: %{version: "1.0"},
                 supervision_tree: sup_tree
               )

      # Verify registration
      assert {:ok, {^agent, metadata}} = Foundation.Registry.lookup(sup_tree.registry, agent)
      assert metadata.framework == :jido
      assert metadata.capability == [:test, :mock]
      assert metadata.health_status == :healthy
    end

    test "handles registration failure gracefully", %{supervision_tree: sup_tree} do
      # Create a dead process reference
      dead_pid = spawn(fn -> :ok end)
      # Wait for process to terminate using monitoring
      ref = Process.monitor(dead_pid)
      assert_receive {:DOWN, ^ref, :process, ^dead_pid, _}, 100

      assert {:error, _} =
               Bridge.register_agent(dead_pid,
                 capabilities: [:test],
                 supervision_tree: sup_tree
               )
    end
  end

  describe "unregister_agent/2" do
    test "unregisters agent from Foundation", %{supervision_tree: sup_tree} do
      {:ok, agent} = MockJidoAgent.start_link(%{})

      # Foundation.UnifiedTestFoundation :supervision_testing mode handles all process cleanup automatically

      :ok = Bridge.register_agent(agent, capabilities: [:test], supervision_tree: sup_tree)

      assert :ok = Bridge.unregister_agent(agent, supervision_tree: sup_tree)
      assert :error = Foundation.Registry.lookup(sup_tree.registry, agent)
    end
  end

  describe "update_agent_metadata/3" do
    test "updates registered agent metadata", %{supervision_tree: sup_tree} do
      {:ok, agent} = MockJidoAgent.start_link(%{})

      # Foundation.UnifiedTestFoundation :supervision_testing mode handles all process cleanup automatically

      :ok = Bridge.register_agent(agent, capabilities: [:test], supervision_tree: sup_tree)

      assert :ok =
               Bridge.update_agent_metadata(
                 agent,
                 %{
                   status: :busy,
                   load: 0.75
                 },
                 supervision_tree: sup_tree
               )

      assert {:ok, {^agent, metadata}} = Foundation.Registry.lookup(sup_tree.registry, agent)
      assert metadata.status == :busy
      assert metadata.load == 0.75
    end

    test "returns error for unregistered agent", %{supervision_tree: sup_tree} do
      {:ok, agent} = MockJidoAgent.start_link(%{})

      # Foundation.UnifiedTestFoundation :supervision_testing mode handles all process cleanup automatically

      assert {:error, :agent_not_registered} =
               Bridge.update_agent_metadata(agent, %{}, supervision_tree: sup_tree)
    end
  end

  describe "emit_agent_event/4" do
    test "emits telemetry events" do
      {:ok, agent} = MockJidoAgent.start_link(%{})

      # Foundation.UnifiedTestFoundation :supervision_testing mode handles all process cleanup automatically

      :telemetry.attach(
        "test-jido-events",
        [:jido, :agent, :test_event],
        fn event, measurements, metadata, _config ->
          send(self(), {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      Bridge.emit_agent_event(agent, :test_event, %{value: 42}, %{extra: :data})

      assert_receive {:telemetry, [:jido, :agent, :test_event], measurements, metadata}
      assert measurements.value == 42
      assert metadata.agent_id == agent
      assert metadata.framework == :jido
      assert metadata.extra == :data

      :telemetry.detach("test-jido-events")
    end
  end

  describe "execute_protected/3" do
    test "executes action with circuit breaker protection" do
      {:ok, agent} = MockJidoAgent.start_link(%{})

      # Foundation.UnifiedTestFoundation :supervision_testing mode handles all process cleanup automatically

      result =
        Bridge.execute_protected(agent, fn ->
          GenServer.call(agent, {:execute, :success})
        end)

      assert result == {:ok, :completed}
    end

    test "uses fallback when circuit breaker opens" do
      {:ok, agent} = MockJidoAgent.start_link(%{})

      # Foundation.UnifiedTestFoundation :supervision_testing mode handles all process cleanup automatically

      service_id = {:test_service, System.unique_integer()}

      # Cause multiple failures to open circuit
      for _ <- 1..6 do
        Bridge.execute_protected(
          agent,
          fn ->
            {:error, :service_error}
          end,
          service_id: service_id
        )
      end

      # Circuit should be open, fallback should be used
      result =
        Bridge.execute_protected(
          agent,
          fn ->
            {:ok, :should_not_execute}
          end,
          service_id: service_id,
          fallback: {:ok, :fallback_used}
        )

      assert result == {:ok, :fallback_used}
    end
  end

  describe "resource management" do
    test "acquires and releases resources" do
      token = Bridge.acquire_resource(:test_resource, %{test: true})
      assert {:ok, _} = token

      assert :ok = Bridge.release_resource(elem(token, 1))
    end
  end

  describe "agent discovery" do
    setup %{supervision_tree: sup_tree} do
      # Register some test agents
      agents =
        for i <- 1..5 do
          {:ok, agent} = MockJidoAgent.start_link(%{id: i})
          capabilities = if rem(i, 2) == 0, do: [:even, :number], else: [:odd, :number]

          :ok =
            Bridge.register_agent(agent,
              capabilities: capabilities,
              skip_monitoring: true,
              supervision_tree: sup_tree
            )

          {i, agent}
        end

      # Foundation.UnifiedTestFoundation :supervision_testing mode handles all process cleanup automatically

      {:ok, agents: agents}
    end

    test "finds agents by capability", %{supervision_tree: sup_tree} do
      {:ok, agents} = Bridge.find_agents_by_capability(:even, supervision_tree: sup_tree)

      assert length(agents) == 2

      assert Enum.all?(agents, fn {_key, _pid, metadata} ->
               :even in metadata.capability
             end)
    end

    test "finds agents with multiple criteria", %{supervision_tree: sup_tree} do
      {:ok, agents} =
        Bridge.find_agents(
          [
            {[:capability], :number, :eq},
            {[:health_status], :healthy, :eq}
          ],
          supervision_tree: sup_tree
        )

      assert length(agents) == 5
    end
  end

  describe "batch operations" do
    test "batch registers multiple agents", %{supervision_tree: sup_tree} do
      {agents, _pids} =
        for i <- 1..3 do
          {:ok, agent} = MockJidoAgent.start_link(%{id: i})
          {{agent, [capabilities: [:batch, :"agent_#{i}"]]}, agent}
        end
        |> Enum.unzip()

      # Foundation.UnifiedTestFoundation :supervision_testing mode handles all process cleanup automatically

      assert {:ok, registered} = Bridge.batch_register_agents(agents, supervision_tree: sup_tree)
      assert length(registered) == 3
    end

    test "distributed_execute/3", %{supervision_tree: sup_tree} do
      # Register agents with specific capability
      # Foundation.UnifiedTestFoundation :supervision_testing mode handles all process cleanup automatically
      _pids =
        for i <- 1..3 do
          {:ok, agent} = MockJidoAgent.start_link(%{id: i})

          :ok =
            Bridge.register_agent(agent,
              capabilities: [:distributed_test],
              skip_monitoring: true,
              supervision_tree: sup_tree
            )

          agent
        end

      # Execute distributed operation using supervision_tree context for isolated services
      {:ok, results} =
        Bridge.distributed_execute(
          :distributed_test,
          fn agent ->
            GenServer.call(agent, :get_state, 1000)
          end,
          supervision_tree: sup_tree
        )

      assert length(results) == 3

      assert Enum.all?(results, fn
               {:ok, %{state: :ready}} -> true
               _ -> false
             end)
    end
  end

  describe "monitoring" do
    test "monitors agent health", %{supervision_tree: sup_tree} do
      {:ok, agent} = MockJidoAgent.start_link(%{})

      # Foundation.UnifiedTestFoundation :supervision_testing mode handles all process cleanup automatically

      # Track when health checks happen
      test_pid = self()
      health_check_ref = make_ref()

      health_check = fn pid ->
        send(test_pid, {:health_checked, health_check_ref})
        if Process.alive?(pid), do: :healthy, else: :unhealthy
      end

      :ok =
        Bridge.register_agent(agent,
          capabilities: [:monitored],
          health_check: health_check,
          health_check_interval: 100,
          supervision_tree: sup_tree
        )

      # Wait for health check to run
      assert_receive {:health_checked, ^health_check_ref}, 200
      assert {:ok, {_, metadata}} = Foundation.lookup(agent, sup_tree.registry)
      assert metadata.health_status == :healthy

      # Clean up monitor before we stop the agent
      case Process.get({:monitor, agent}) do
        nil -> :ok
        monitor_pid -> Process.exit(monitor_pid, :shutdown)
      end
    end
  end

  describe "convenience functions" do
    test "start_and_register_agent/3", %{supervision_tree: sup_tree} do
      result =
        Bridge.start_and_register_agent(
          MockJidoAgent,
          %{auto: true},
          capabilities: [:auto_registered],
          supervision_tree: sup_tree
        )

      assert {:ok, agent} = result
      assert Process.alive?(agent)

      # Foundation.UnifiedTestFoundation :supervision_testing mode handles all process cleanup automatically

      # Verify registration
      assert {:ok, {_, metadata}} = Foundation.lookup(agent, sup_tree.registry)
      assert :auto_registered in metadata.capability
    end
  end

  describe "error handling" do
    test "handles agent crashes gracefully", %{supervision_tree: sup_tree} do
      # Trap exits to handle the crash gracefully
      Process.flag(:trap_exit, true)

      {:ok, agent} = MockJidoAgent.start_link(%{})

      # Foundation.UnifiedTestFoundation :supervision_testing mode handles all process cleanup automatically

      :ok =
        Bridge.register_agent(agent,
          capabilities: [:crasher],
          skip_monitoring: true,
          supervision_tree: sup_tree
        )

      result =
        Bridge.execute_protected(
          agent,
          fn ->
            GenServer.call(agent, {:execute, :crash})
          end,
          fallback: {:ok, :recovered}
        )

      assert result == {:ok, :recovered}
    end

    test "handles unknown calls in distributed execution", %{supervision_tree: sup_tree} do
      # Create slow agent using Foundation.TestProcess for proper OTP compliance
      {:ok, slow_agent} = Foundation.TestProcess.start_link()

      :ok =
        Bridge.register_agent(slow_agent,
          capabilities: [:slow],
          skip_monitoring: true,
          supervision_tree: sup_tree
        )

      # Foundation.UnifiedTestFoundation :supervision_testing mode handles all process cleanup automatically

      {:ok, results} =
        Bridge.distributed_execute(
          :slow,
          fn agent ->
            # Test unknown call behavior with Foundation.TestProcess
            # Foundation.TestProcess responds to unknown calls with {:unknown_call, call}
            # instead of timing out (this is intentional for test stability)
            GenServer.call(agent, :nonexistent_call, 1000)
          end,
          max_concurrency: 1,
          supervision_tree: sup_tree
        )

      assert [{:ok, {:unknown_call, :nonexistent_call}}] = results
    end
  end
end
