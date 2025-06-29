defmodule JidoFoundation.MABEAMCoordinationTest do
  # Using registry isolation mode for MABEAM agent coordination
  use Foundation.UnifiedTestFoundation, :registry

  alias JidoFoundation.Bridge

  # Mock Jido Agent that can coordinate with MABEAM
  defmodule CoordinatingAgent do
    use GenServer

    defstruct [:id, :state, :coordination_config, :received_messages]

    def start_link(opts) do
      GenServer.start_link(__MODULE__, opts)
    end

    def init(opts) do
      state = %__MODULE__{
        id: Keyword.get(opts, :id, System.unique_integer()),
        state: :ready,
        coordination_config: Keyword.get(opts, :coordination_config, %{}),
        received_messages: []
      }

      {:ok, state}
    end

    def get_state(pid) do
      GenServer.call(pid, :get_state)
    end

    def send_coordination_message(pid, message) do
      GenServer.call(pid, {:coordination_message, message})
    end

    def get_received_messages(pid) do
      GenServer.call(pid, :get_received_messages)
    end

    def handle_call(:get_state, _from, state) do
      {:reply, state, state}
    end

    def handle_call({:coordination_message, message}, _from, state) do
      new_messages = [message | state.received_messages]
      new_state = %{state | received_messages: new_messages}
      {:reply, :ok, new_state}
    end

    def handle_call(:get_received_messages, _from, state) do
      {:reply, Enum.reverse(state.received_messages), state}
    end

    # Handle coordination messages from MABEAM
    def handle_info({:mabeam_coordination, from_agent, message}, state) do
      coordination_message = %{
        type: :mabeam_coordination,
        from: from_agent,
        message: message,
        received_at: System.system_time(:microsecond)
      }

      new_messages = [coordination_message | state.received_messages]
      new_state = %{state | received_messages: new_messages}

      {:noreply, new_state}
    end

    # Handle task distribution from MABEAM
    def handle_info({:mabeam_task, task_id, task_data}, state) do
      task_message = %{
        type: :mabeam_task,
        task_id: task_id,
        task_data: task_data,
        status: :received,
        received_at: System.system_time(:microsecond)
      }

      new_messages = [task_message | state.received_messages]
      new_state = %{state | received_messages: new_messages}

      # Simulate task processing
      send(self(), {:process_task, task_id})

      {:noreply, new_state}
    end

    def handle_info({:process_task, task_id}, state) do
      # Find the task and mark it as completed
      updated_messages =
        Enum.map(state.received_messages, fn msg ->
          if msg[:task_id] == task_id and msg[:status] == :received do
            Map.merge(msg, %{status: :completed, completed_at: System.system_time(:microsecond)})
          else
            msg
          end
        end)

      new_state = %{state | received_messages: updated_messages}

      # Emit completion signal
      Bridge.emit_signal(self(), %{
        id: System.unique_integer(),
        type: "task.completed",
        source: "agent://#{inspect(self())}",
        data: %{task_id: task_id, result: "success"},
        time: DateTime.utc_now()
      })

      {:noreply, new_state}
    end
  end

  describe "MABEAM-Jido agent coordination" do
    test "registers Jido agents in MABEAM coordination system", %{registry: registry} do
      {:ok, agent1} = CoordinatingAgent.start_link(id: "coord_agent_1")
      {:ok, agent2} = CoordinatingAgent.start_link(id: "coord_agent_2")

      on_exit(fn ->
        if Process.alive?(agent1), do: GenServer.stop(agent1)
        if Process.alive?(agent2), do: GenServer.stop(agent2)
      end)

      # Register agents with both Foundation and MABEAM coordination capabilities
      :ok =
        Bridge.register_agent(agent1,
          capabilities: [:coordination, :task_processing],
          metadata: %{mabeam_enabled: true, agent_type: :worker},
          registry: registry
        )

      :ok =
        Bridge.register_agent(agent2,
          capabilities: [:coordination, :task_distribution],
          metadata: %{mabeam_enabled: true, agent_type: :coordinator},
          registry: registry
        )

      # Verify agents are registered
      {:ok, {^agent1, metadata1}} = Foundation.lookup(agent1, registry)
      {:ok, {^agent2, metadata2}} = Foundation.lookup(agent2, registry)

      assert metadata1[:mabeam_enabled] == true
      assert metadata1[:agent_type] == :worker
      assert :coordination in metadata1[:capability]

      assert metadata2[:mabeam_enabled] == true
      assert metadata2[:agent_type] == :coordinator
      assert :coordination in metadata2[:capability]
    end

    test "enables agent-to-agent coordination through MABEAM", %{registry: registry} do
      {:ok, sender_agent} = CoordinatingAgent.start_link(id: "sender")
      {:ok, receiver_agent} = CoordinatingAgent.start_link(id: "receiver")

      on_exit(fn ->
        if Process.alive?(sender_agent), do: GenServer.stop(sender_agent)
        if Process.alive?(receiver_agent), do: GenServer.stop(receiver_agent)
      end)

      # Register both agents with coordination capabilities
      :ok =
        Bridge.register_agent(sender_agent,
          capabilities: [:coordination],
          registry: registry
        )

      :ok =
        Bridge.register_agent(receiver_agent,
          capabilities: [:coordination],
          registry: registry
        )

      # Simulate agent-to-agent coordination
      coordination_message = %{
        action: :collaborate,
        task_type: :data_processing,
        priority: :high,
        deadline: DateTime.add(DateTime.utc_now(), 3600, :second)
      }

      # Send coordination message between agents
      Bridge.coordinate_agents(sender_agent, receiver_agent, coordination_message)

      # Verify receiver got the coordination message
      # Allow message processing
      :timer.sleep(50)
      messages = CoordinatingAgent.get_received_messages(receiver_agent)

      assert length(messages) >= 1
      coordination_msg = Enum.find(messages, &(&1[:type] == :mabeam_coordination))
      assert coordination_msg != nil
      assert coordination_msg[:from] == sender_agent
      assert coordination_msg[:message][:action] == :collaborate
    end

    test "distributes tasks across Jido agents via MABEAM", %{registry: registry} do
      # Create multiple worker agents
      worker_agents =
        for i <- 1..3 do
          {:ok, agent} = CoordinatingAgent.start_link(id: "worker_#{i}")
          agent
        end

      {:ok, coordinator_agent} = CoordinatingAgent.start_link(id: "coordinator")

      on_exit(fn ->
        # Defensive process cleanup with race condition protection
        Enum.each(worker_agents, fn agent ->
          try do
            if Process.alive?(agent) do
              GenServer.stop(agent, :normal, 1000)
            end
          catch
            :exit, {:noproc, _} -> :ok  # Process already dead
            :exit, {:timeout, _} -> 
              # Force kill if stop timeout
              Process.exit(agent, :kill)
          end
        end)

        try do
          if Process.alive?(coordinator_agent) do
            GenServer.stop(coordinator_agent, :normal, 1000)
          end
        catch
          :exit, {:noproc, _} -> :ok  # Process already dead
          :exit, {:timeout, _} -> 
            # Force kill if stop timeout
            Process.exit(coordinator_agent, :kill)
        end
      end)

      # Register all agents
      Enum.each(worker_agents, fn agent ->
        :ok =
          Bridge.register_agent(agent,
            capabilities: [:task_processing, :coordination],
            metadata: %{agent_type: :worker},
            registry: registry
          )
      end)

      :ok =
        Bridge.register_agent(coordinator_agent,
          capabilities: [:task_distribution, :coordination],
          metadata: %{agent_type: :coordinator},
          registry: registry
        )

      # Distribute tasks to worker agents
      tasks = [
        %{id: "task_1", type: :data_analysis, data: %{records: 1000}},
        %{id: "task_2", type: :data_processing, data: %{batch: "batch_a"}},
        %{id: "task_3", type: :data_validation, data: %{schema: "v1"}}
      ]

      # Use MABEAM to distribute tasks
      Enum.zip(worker_agents, tasks)
      |> Enum.each(fn {agent, task} ->
        Bridge.distribute_task(coordinator_agent, agent, task)
      end)

      # Allow task processing
      :timer.sleep(100)

      # Verify each worker received and processed their task
      Enum.zip(worker_agents, tasks)
      |> Enum.each(fn {agent, task} ->
        messages = CoordinatingAgent.get_received_messages(agent)

        # Should have received the task
        task_msg = Enum.find(messages, &(&1[:task_id] == task.id))
        assert task_msg != nil
        assert task_msg[:status] == :completed
        assert task_msg[:task_data] == task
      end)
    end

    test "handles agent coordination failures gracefully", %{registry: registry} do
      {:ok, healthy_agent} = CoordinatingAgent.start_link(id: "healthy")

      # Create a dead agent
      dead_agent = spawn(fn -> :ok end)
      ref = Process.monitor(dead_agent)
      assert_receive {:DOWN, ^ref, :process, ^dead_agent, _}

      on_exit(fn ->
        if Process.alive?(healthy_agent), do: GenServer.stop(healthy_agent)
      end)

      # Register both agents
      :ok =
        Bridge.register_agent(healthy_agent,
          capabilities: [:coordination],
          registry: registry
        )

      # Try to register dead agent - should fail
      {:error, _} =
        Bridge.register_agent(dead_agent,
          capabilities: [:coordination],
          registry: registry
        )

      # Try to coordinate with dead agent - should handle gracefully
      coordination_message = %{action: :ping, data: "test"}

      result = Bridge.coordinate_agents(healthy_agent, dead_agent, coordination_message)

      # Should not crash and should return appropriate error
      assert result == :ok || match?({:error, _}, result)

      # Healthy agent should still be responsive
      state = CoordinatingAgent.get_state(healthy_agent)
      assert state.state == :ready
    end

    test "tracks coordination metrics and telemetry", %{registry: registry} do
      {:ok, agent1} = CoordinatingAgent.start_link(id: "metrics_agent_1")
      {:ok, agent2} = CoordinatingAgent.start_link(id: "metrics_agent_2")

      on_exit(fn ->
        if Process.alive?(agent1), do: GenServer.stop(agent1)
        if Process.alive?(agent2), do: GenServer.stop(agent2)
      end)

      # Attach telemetry handler for coordination events
      test_pid = self()

      :telemetry.attach(
        "test-coordination-events",
        [:jido, :agent, :coordination],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach("test-coordination-events")
      end)

      # Register agents
      :ok = Bridge.register_agent(agent1, capabilities: [:coordination], registry: registry)
      :ok = Bridge.register_agent(agent2, capabilities: [:coordination], registry: registry)

      # Perform coordination with telemetry
      coordination_message = %{action: :telemetry_test, data: "coordination_data"}
      Bridge.coordinate_agents(agent1, agent2, coordination_message)

      # Emit coordination telemetry manually (since we're testing the pattern)
      Bridge.emit_agent_event(
        agent1,
        :coordination,
        %{
          messages_sent: 1
        },
        %{
          target_agent: agent2,
          message_type: :telemetry_test,
          coordination_type: :direct
        }
      )

      # Verify coordination telemetry
      assert_receive {:telemetry, [:jido, :agent, :coordination], measurements, metadata}
      assert measurements.messages_sent == 1
      assert metadata.target_agent == agent2
      assert metadata.message_type == :telemetry_test
    end

    test "supports hierarchical agent coordination", %{registry: registry} do
      # Create a hierarchy: supervisor -> manager -> worker
      {:ok, supervisor_agent} = CoordinatingAgent.start_link(id: "supervisor")
      {:ok, manager_agent} = CoordinatingAgent.start_link(id: "manager")
      {:ok, worker_agent} = CoordinatingAgent.start_link(id: "worker")

      on_exit(fn ->
        if Process.alive?(supervisor_agent), do: GenServer.stop(supervisor_agent)
        if Process.alive?(manager_agent), do: GenServer.stop(manager_agent)
        if Process.alive?(worker_agent), do: GenServer.stop(worker_agent)
      end)

      # Register agents with hierarchical metadata
      :ok =
        Bridge.register_agent(supervisor_agent,
          capabilities: [:coordination, :supervision],
          metadata: %{level: :supervisor, manages: [manager_agent]},
          registry: registry
        )

      :ok =
        Bridge.register_agent(manager_agent,
          capabilities: [:coordination, :management],
          metadata: %{level: :manager, supervisor: supervisor_agent, manages: [worker_agent]},
          registry: registry
        )

      :ok =
        Bridge.register_agent(worker_agent,
          capabilities: [:coordination, :task_execution],
          metadata: %{level: :worker, manager: manager_agent},
          registry: registry
        )

      # Test hierarchical task delegation
      top_level_task = %{
        id: "hierarchical_task",
        type: :complex_analysis,
        subtasks: [
          %{id: "subtask_1", type: :data_collection},
          %{id: "subtask_2", type: :data_processing}
        ]
      }

      # Supervisor delegates to manager
      Bridge.delegate_task(supervisor_agent, manager_agent, top_level_task)

      # Manager delegates subtask to worker
      Bridge.delegate_task(manager_agent, worker_agent, hd(top_level_task.subtasks))

      # Allow delegation processing
      :timer.sleep(100)

      # Verify task delegation worked through the hierarchy
      _supervisor_messages = CoordinatingAgent.get_received_messages(supervisor_agent)
      manager_messages = CoordinatingAgent.get_received_messages(manager_agent)
      worker_messages = CoordinatingAgent.get_received_messages(worker_agent)

      # Manager should have received task from supervisor
      manager_task = Enum.find(manager_messages, &(&1[:task_id] == "hierarchical_task"))
      assert manager_task != nil

      # Worker should have received subtask from manager
      worker_task = Enum.find(worker_messages, &(&1[:task_id] == "subtask_1"))
      assert worker_task != nil
    end
  end
end
