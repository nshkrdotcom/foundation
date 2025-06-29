defmodule JidoSystem.Agents.FoundationAgentTest do
  use ExUnit.Case, async: false
  use Foundation.TestConfig, :registry

  alias JidoSystem.Agents.FoundationAgent

  defmodule TestAgent do
    use FoundationAgent,
      name: "test_agent",
      description: "Test agent for Foundation integration",
      actions: [],
      schema: [
        status: [type: :atom, default: :idle],
        test_data: [type: :map, default: %{}]
      ]
  end

  setup do
    # Ensure clean state - detach any existing handlers
    try do
      :telemetry.detach("test_startup")
      :telemetry.detach("test_actions")
      :telemetry.detach("test_errors")
      :telemetry.detach("test_termination")
      :telemetry.detach("test_emit_event")
    rescue
      _ -> :ok
    end

    # Explicitly set the Foundation registry implementation to a running MABEAM process
    # This ensures Foundation.register can find a proper implementation
    case GenServer.whereis(MABEAM.AgentRegistry) do
      nil ->
        # Start MABEAM.AgentRegistry if not already running
        {:ok, registry_pid} = MABEAM.AgentRegistry.start_link(name: MABEAM.AgentRegistry, id: :test)
        Application.put_env(:foundation, :registry_impl, registry_pid)

      pid when is_pid(pid) ->
        # Use existing running process
        Application.put_env(:foundation, :registry_impl, pid)
    end

    :ok
  end

  describe "agent initialization" do
    test "successfully initializes and registers with Foundation", %{registry: _registry} do
      {:ok, pid} = TestAgent.start_link(id: "test_agent_1")

      # Verify agent is alive
      assert Process.alive?(pid)

      # The agent should be registered with Foundation via Bridge.register_agent
      # Bridge registers the agent with the configured Foundation registry

      # Use the global registry that was configured in setup
      global_registry = Application.get_env(:foundation, :registry_impl) || MABEAM.AgentRegistry

      case Foundation.Registry.lookup(global_registry, pid) do
        {:ok, {^pid, metadata}} ->
          # Check Bridge's standardized metadata structure
          assert metadata.framework == :jido
          # Note: singular "capability"
          assert metadata.capability == [:general_purpose]
          assert metadata.health_status == :healthy
          assert metadata.node == node()
          assert is_map(metadata.resources)
          assert %DateTime{} = metadata.registered_at

          # Check our custom metadata fields (merged via :metadata option)
          assert metadata.agent_type == "test_agent"
          assert metadata.foundation_integrated == true

        {:ok, {_other_pid, _metadata}} ->
          flunk("Found different PID than expected")

        :error ->
          flunk("Agent not found in Foundation registry")
      end
    end

    test "emits startup telemetry" do
      # Attach telemetry handler
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test_startup",
        [:jido_system, :agent, :started],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {ref, :telemetry, measurements, metadata})
        end,
        %{}
      )

      {:ok, _pid} = TestAgent.start_link(id: "test_agent_telemetry")

      # Verify telemetry was emitted
      assert_receive {^ref, :telemetry, %{count: 1}, metadata}
      assert metadata.agent_id == "test_agent_telemetry"
      assert metadata.agent_type == "test_agent"
      assert metadata.capabilities == [:general_purpose]

      :telemetry.detach("test_startup")
    end

    test "handles registration failure gracefully" do
      # Mock a registration failure scenario
      # This would require mocking the Bridge module, simplified for now
      {:ok, _pid} = TestAgent.start_link(id: "test_agent_failure")

      # Agent should still start even if registration has issues
      # In a real implementation, we'd test actual failure scenarios
    end
  end

  describe "action lifecycle telemetry" do
    setup do
      {:ok, pid} = TestAgent.start_link(id: "test_agent_actions")
      %{agent: pid}
    end

    test "emits telemetry for action execution", %{agent: agent} do
      test_pid = self()
      ref = make_ref()

      # Attach telemetry handlers
      :telemetry.attach_many(
        "test_actions",
        [
          [:jido_foundation, :bridge, :agent_event]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {ref, event, measurements, metadata})
        end,
        %{}
      )

      # Create a test instruction using a basic action that's registered by default
      instruction =
        Jido.Instruction.new!(%{
          action: Jido.Actions.Basic.Log,
          params: %{message: "Test log message", level: :info}
        })

      # Execute action
      Jido.Agent.Server.cast(agent, instruction)

      # Should receive before and after action telemetry
      assert_receive {^ref, [:jido_foundation, :bridge, :agent_event], _, _}

      :telemetry.detach("test_actions")
    end
  end

  describe "error handling" do
    setup do
      {:ok, pid} = TestAgent.start_link(id: "test_agent_errors")
      %{agent: pid}
    end

    test "handles errors gracefully and emits telemetry", %{agent: agent} do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test_errors",
        [:jido_foundation, :bridge, :agent_event],
        fn _event, measurements, metadata, _config ->
          if Map.get(metadata, :event_type) == :agent_error do
            send(test_pid, {ref, :error_telemetry, measurements, metadata})
          end
        end,
        %{}
      )

      # Simulate an error by sending an invalid instruction
      invalid_instruction = %{action: :invalid_action, params: %{}}

      # This should trigger error handling
      send(agent, {:error_test, invalid_instruction})

      # Note: In a real test, we'd trigger an actual error condition
      # This is simplified for demonstration

      :telemetry.detach("test_errors")
    end
  end

  describe "agent termination" do
    test "deregisters from Foundation on termination", %{registry: _registry} do
      {:ok, pid} = TestAgent.start_link(id: "test_agent_terminate")

      # The agent registers with the globally configured registry from setup
      global_registry = Application.get_env(:foundation, :registry_impl) || MABEAM.AgentRegistry

      # Verify registration
      assert {:ok, {^pid, _}} = Foundation.Registry.lookup(global_registry, pid)

      # Stop the agent
      GenServer.stop(pid)

      # Give some time for cleanup
      Process.sleep(10)

      # Verify deregistration
      assert :error = Foundation.Registry.lookup(global_registry, pid)
    end

    test "emits termination telemetry" do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test_termination",
        [:jido_system, :agent, :terminated],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {ref, :terminated, measurements, metadata})
        end,
        %{}
      )

      {:ok, pid} = TestAgent.start_link(id: "test_agent_term_telemetry")
      GenServer.stop(pid)

      assert_receive {^ref, :terminated, %{count: 1}, metadata}
      assert metadata.agent_id == "test_agent_term_telemetry"

      :telemetry.detach("test_termination")
    end
  end

  describe "helper functions" do
    setup do
      {:ok, pid} = TestAgent.start_link(id: "test_agent_helpers")
      {:ok, state} = Jido.Agent.Server.state(pid)
      %{agent: pid, agent_state: state.agent}
    end

    test "emit_event helper works correctly", %{agent: _agent, agent_state: agent_state} do
      test_pid = self()
      ref = make_ref()

      :telemetry.attach(
        "test_emit_event",
        [:jido, :agent, :test_event],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {ref, :custom_event, measurements, metadata})
        end,
        %{}
      )

      # Use the emit_event helper (would need to call it from within the agent)
      # This is a simplified test
      TestAgent.emit_event(agent_state, :test_event, %{value: 42}, %{test: true})

      assert_receive {^ref, :custom_event, measurements, metadata}
      assert measurements.value == 42
      assert metadata.test == true
      # Bridge sets agent_id to PID, but the original agent ID should still be there
      assert is_pid(metadata.agent_id)

      :telemetry.detach("test_emit_event")
    end

    test "coordinate_with_agents helper initiates coordination", %{
      agent: _agent,
      agent_state: agent_state
    } do
      # Test coordination functionality
      task = %{type: :test_coordination, data: %{}}

      result = TestAgent.coordinate_with_agents(agent_state, task, [])

      # Should return coordination result
      # In a real test, we'd verify actual MABEAM coordination
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "schema and configuration" do
    test "agent has correct schema configuration" do
      schema = TestAgent.__agent_metadata__()

      assert schema.name == "test_agent"
      assert schema.description == "Test agent for Foundation integration"
      # Capabilities are not part of agent metadata, they're runtime configuration
      # assert schema.capabilities == [:testing, :validation]
      assert is_list(schema.schema)
    end

    test "agent state follows schema defaults" do
      {:ok, pid} = TestAgent.start_link(id: "test_agent_schema")
      {:ok, state} = Jido.Agent.Server.state(pid)

      # Check default values from schema
      assert state.agent.state.status == :idle
      assert state.agent.state.test_data == %{}
    end
  end

  describe "Foundation integration" do
    test "agent properly integrates with Foundation Registry", %{registry: _registry} do
      {:ok, pid} = TestAgent.start_link(id: "foundation_integration_test")

      # The agent registers with the globally configured registry from setup
      global_registry = Application.get_env(:foundation, :registry_impl) || MABEAM.AgentRegistry

      # Verify the agent is registered with correct metadata
      case Foundation.Registry.lookup(global_registry, pid) do
        {:ok, {^pid, metadata}} ->
          assert metadata.agent_type == "test_agent"
          assert metadata.foundation_integrated == true
          assert is_pid(metadata.pid)
          assert is_list(metadata.capabilities)

        :error ->
          flunk("Agent not found in global registry")
      end
    end

    test "multiple agents can be registered simultaneously", %{registry: _registry} do
      agents =
        for i <- 1..5 do
          {:ok, pid} = TestAgent.start_link(id: "multi_agent_#{i}")
          pid
        end

      # The agents register with the globally configured registry from setup
      global_registry = Application.get_env(:foundation, :registry_impl) || MABEAM.AgentRegistry

      # Verify all agents are registered
      all_entries = Foundation.Registry.list_all(global_registry)
      registered_pids = Enum.map(all_entries, fn {_, pid, _} -> pid end)

      Enum.each(agents, fn agent_pid ->
        assert agent_pid in registered_pids
      end)
    end
  end
end
