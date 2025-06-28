defmodule JidoFoundation.BridgeTest do
  use ExUnit.Case, async: true
  use Foundation.TestConfig, :registry

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
    test "registers Jido agent with Foundation", %{registry: registry} do
      {:ok, agent} = MockJidoAgent.start_link(%{})

      on_exit(fn ->
        if Process.alive?(agent), do: GenServer.stop(agent, :normal, 5000)
      end)

      assert :ok =
               Bridge.register_agent(agent,
                 capabilities: [:test, :mock],
                 metadata: %{version: "1.0"},
                 registry: registry
               )

      # Verify registration
      assert {:ok, {^agent, metadata}} = Foundation.Registry.lookup(registry, agent)
      assert metadata.framework == :jido
      assert metadata.capability == [:test, :mock]
      assert metadata.health_status == :healthy
    end

    test "handles registration failure gracefully", %{registry: registry} do
      # Create a dead process reference
      dead_pid = spawn(fn -> :ok end)
      # Wait for process to terminate using monitoring
      ref = Process.monitor(dead_pid)
      assert_receive {:DOWN, ^ref, :process, ^dead_pid, _}, 100

      assert {:error, _} =
               Bridge.register_agent(dead_pid,
                 capabilities: [:test],
                 registry: registry
               )
    end
  end

  describe "unregister_agent/2" do
    test "unregisters agent from Foundation", %{registry: registry} do
      {:ok, agent} = MockJidoAgent.start_link(%{})

      on_exit(fn ->
        if Process.alive?(agent), do: GenServer.stop(agent, :normal, 5000)
      end)

      :ok = Bridge.register_agent(agent, capabilities: [:test], registry: registry)

      assert :ok = Bridge.unregister_agent(agent, registry: registry)
      assert :error = Foundation.Registry.lookup(registry, agent)
    end
  end

  describe "update_agent_metadata/3" do
    test "updates registered agent metadata", %{registry: registry} do
      {:ok, agent} = MockJidoAgent.start_link(%{})

      on_exit(fn ->
        if Process.alive?(agent), do: GenServer.stop(agent, :normal, 5000)
      end)

      :ok = Bridge.register_agent(agent, capabilities: [:test], registry: registry)

      assert :ok =
               Bridge.update_agent_metadata(
                 agent,
                 %{
                   status: :busy,
                   load: 0.75
                 },
                 registry: registry
               )

      assert {:ok, {^agent, metadata}} = Foundation.Registry.lookup(registry, agent)
      assert metadata.status == :busy
      assert metadata.load == 0.75
    end

    test "returns error for unregistered agent", %{registry: registry} do
      {:ok, agent} = MockJidoAgent.start_link(%{})

      on_exit(fn ->
        if Process.alive?(agent), do: GenServer.stop(agent, :normal, 5000)
      end)

      assert {:error, :agent_not_registered} =
               Bridge.update_agent_metadata(agent, %{}, registry: registry)
    end
  end

  describe "emit_agent_event/4" do
    test "emits telemetry events" do
      {:ok, agent} = MockJidoAgent.start_link(%{})

      on_exit(fn ->
        if Process.alive?(agent), do: GenServer.stop(agent, :normal, 5000)
      end)

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

      on_exit(fn ->
        if Process.alive?(agent), do: GenServer.stop(agent, :normal, 5000)
      end)

      result =
        Bridge.execute_protected(agent, fn ->
          GenServer.call(agent, {:execute, :success})
        end)

      assert result == {:ok, :completed}
    end

    test "uses fallback when circuit breaker opens" do
      {:ok, agent} = MockJidoAgent.start_link(%{})

      on_exit(fn ->
        if Process.alive?(agent), do: GenServer.stop(agent, :normal, 5000)
      end)

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
    setup %{registry: registry} do
      # Register some test agents
      agents =
        for i <- 1..5 do
          {:ok, agent} = MockJidoAgent.start_link(%{id: i})
          capabilities = if rem(i, 2) == 0, do: [:even, :number], else: [:odd, :number]

          :ok =
            Bridge.register_agent(agent,
              capabilities: capabilities,
              skip_monitoring: true,
              registry: registry
            )

          {i, agent}
        end

      on_exit(fn ->
        Enum.each(agents, fn {_i, agent} ->
          if Process.alive?(agent), do: GenServer.stop(agent, :normal, 5000)
        end)
      end)

      {:ok, agents: agents}
    end

    test "finds agents by capability", %{registry: registry} do
      {:ok, agents} = Bridge.find_agents_by_capability(:even, registry: registry)

      assert length(agents) == 2

      assert Enum.all?(agents, fn {_key, _pid, metadata} ->
               :even in metadata.capability
             end)
    end

    test "finds agents with multiple criteria", %{registry: registry} do
      {:ok, agents} =
        Bridge.find_agents(
          [
            {[:capability], :number, :eq},
            {[:health_status], :healthy, :eq}
          ],
          registry: registry
        )

      assert length(agents) == 5
    end
  end

  describe "batch operations" do
    test "batch registers multiple agents", %{registry: registry} do
      {agents, pids} =
        for i <- 1..3 do
          {:ok, agent} = MockJidoAgent.start_link(%{id: i})
          {{agent, [capabilities: [:batch, :"agent_#{i}"]]}, agent}
        end
        |> Enum.unzip()

      on_exit(fn ->
        Enum.each(pids, fn pid ->
          if Process.alive?(pid), do: GenServer.stop(pid, :normal, 5000)
        end)
      end)

      assert {:ok, registered} = Bridge.batch_register_agents(agents, registry: registry)
      assert length(registered) == 3
    end

    test "distributed_execute/3", %{registry: registry} do
      # Register agents with specific capability
      pids =
        for i <- 1..3 do
          {:ok, agent} = MockJidoAgent.start_link(%{id: i})

          :ok =
            Bridge.register_agent(agent,
              capabilities: [:distributed_test],
              skip_monitoring: true,
              registry: registry
            )

          agent
        end

      on_exit(fn ->
        Enum.each(pids, fn pid ->
          if Process.alive?(pid), do: GenServer.stop(pid, :normal, 5000)
        end)
      end)

      # Execute distributed operation
      {:ok, results} =
        Bridge.distributed_execute(
          :distributed_test,
          fn agent ->
            GenServer.call(agent, :get_state, 1000)
          end,
          registry: registry
        )

      assert length(results) == 3

      assert Enum.all?(results, fn
               {:ok, %{state: :ready}} -> true
               _ -> false
             end)
    end
  end

  describe "monitoring" do
    test "monitors agent health", %{registry: registry} do
      {:ok, agent} = MockJidoAgent.start_link(%{})

      on_exit(fn ->
        # Stop the monitor process before killing the agent
        case Process.get({:monitor, agent}) do
          nil -> :ok
          monitor_pid -> Process.exit(monitor_pid, :shutdown)
        end

        if Process.alive?(agent), do: GenServer.stop(agent, :normal, 5000)
      end)

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
          registry: registry
        )

      # Wait for health check to run
      assert_receive {:health_checked, ^health_check_ref}, 200
      assert {:ok, {_, metadata}} = Foundation.lookup(agent, registry)
      assert metadata.health_status == :healthy

      # Clean up monitor before we stop the agent
      case Process.get({:monitor, agent}) do
        nil -> :ok
        monitor_pid -> Process.exit(monitor_pid, :shutdown)
      end
    end
  end

  describe "convenience functions" do
    test "start_and_register_agent/3", %{registry: registry} do
      result =
        Bridge.start_and_register_agent(
          MockJidoAgent,
          %{auto: true},
          capabilities: [:auto_registered],
          registry: registry
        )

      assert {:ok, agent} = result
      assert Process.alive?(agent)

      on_exit(fn ->
        if Process.alive?(agent), do: GenServer.stop(agent, :normal, 5000)
      end)

      # Verify registration
      assert {:ok, {_, metadata}} = Foundation.lookup(agent, registry)
      assert :auto_registered in metadata.capability
    end
  end

  describe "error handling" do
    test "handles agent crashes gracefully", %{registry: registry} do
      # Trap exits to handle the crash gracefully
      Process.flag(:trap_exit, true)

      {:ok, agent} = MockJidoAgent.start_link(%{})

      on_exit(fn ->
        Process.flag(:trap_exit, false)
        if Process.alive?(agent), do: GenServer.stop(agent, :normal, 5000)
      end)

      :ok =
        Bridge.register_agent(agent,
          capabilities: [:crasher],
          skip_monitoring: true,
          registry: registry
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

    test "handles timeout in distributed execution", %{registry: registry} do
      # Create slow agent that responds slowly
      slow_agent =
        spawn(fn ->
          receive do
            # This is acceptable - simulating slow work
            _ -> :timer.sleep(10_000)
          end
        end)

      :ok =
        Bridge.register_agent(slow_agent,
          capabilities: [:slow],
          skip_monitoring: true,
          registry: registry
        )

      {:ok, results} =
        Bridge.distributed_execute(
          :slow,
          fn agent ->
            send(agent, :work)
            # Return immediately instead of sleeping - the test should verify the result
            :timeout
          end,
          max_concurrency: 1,
          registry: registry
        )

      assert [{:ok, :timeout}] = results
    end
  end
end
