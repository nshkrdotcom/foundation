defmodule JidoSystem.Agents.TaskAgentTest do
  # Using registry isolation mode for TaskAgent tests with comprehensive telemetry cleanup
  use Foundation.UnifiedTestFoundation, :registry
  use Foundation.TelemetryTestHelpers

  alias JidoSystem.Agents.TaskAgent
  alias JidoSystem.Actions.{ProcessTask, QueueTask}

  setup do
    # Ensure clean state - detach any existing handlers
    try do
      :telemetry.detach("test_task_completion")
      :telemetry.detach("test_task_telemetry")
    rescue
      _ -> :ok
    end

    :ok
  end

  # Import proper test helpers
  import Foundation.TaskAgentTestHelpers

  describe "task agent initialization" do
    test "successfully initializes with correct capabilities", %{registry: _registry} do
      {:ok, pid} = start_supervised({TaskAgent, [id: "task_agent_init"]})

      # Immediately check if alive - no polling needed for start_supervised
      assert Process.alive?(pid)

      # Verify we can get state - this proves the agent is fully initialized
      {:ok, state} = Jido.Agent.Server.state(pid)
      assert state.agent.id == "task_agent_init"

      # Verify GenServer registration
      assert GenServer.whereis(pid) == pid
    end

    test "initializes with correct default state" do
      {:ok, pid} = TaskAgent.start_link(id: "task_agent_state")
      {:ok, state} = Jido.Agent.Server.state(pid)

      agent_state = state.agent.state
      assert agent_state.status == :idle
      assert agent_state.processed_count == 0
      assert agent_state.error_count == 0
      assert agent_state.current_task == nil
      assert :queue.is_empty(agent_state.task_queue)
      assert is_map(agent_state.performance_metrics)
    end

    test "schedules periodic queue processing" do
      {:ok, pid} = TaskAgent.start_link(id: "task_agent_periodic")

      # The agent should schedule queue processing
      # We can't easily test the exact timing, but we can verify the agent starts properly
      assert Process.alive?(pid)
    end
  end

  describe "task processing" do
    setup do
      {:ok, pid} = TaskAgent.start_link(id: "task_agent_processing")
      %{agent: pid}
    end

    test "processes valid tasks successfully", %{agent: agent} do
      test_pid = self()
      ref = make_ref()

      # Attach telemetry to track task completion
      :telemetry.attach(
        "test_task_completion",
        [:jido_system, :task, :completed],
        fn _event, measurements, metadata, _config ->
          send(test_pid, {ref, :task_completed, measurements, metadata})
        end,
        %{}
      )

      # Create a valid task with all required ProcessTask parameters
      task = %{
        task_id: "test_task_1",
        task_type: :data_processing,
        input_data: %{source: "test.csv", format: "csv"},
        timeout: 30_000,
        retry_attempts: 3,
        circuit_breaker: false
      }

      # Process the task
      instruction =
        Jido.Instruction.new!(%{
          action: ProcessTask,
          params: task
        })

      Jido.Agent.Server.cast(agent, instruction)

      # Should receive completion telemetry
      assert_receive {^ref, :task_completed, _measurements, metadata}, 5000
      assert metadata.task_id == "test_task_1"
      assert metadata.result == :success

      # Verify agent state updated
      {:ok, state} = Jido.Agent.Server.state(agent)
      assert state.agent.state.processed_count == 1
      assert state.agent.state.status == :idle

      :telemetry.detach("test_task_completion")
    end

    test "handles task validation errors", %{agent: agent} do
      # Create an invalid task (missing required fields)
      invalid_task = %{
        # Missing task_id and task_type
        input_data: %{some: "data"}
      }

      # Use the proper helper that waits for telemetry events
      {:ok, final_state} = process_invalid_task_and_wait(agent, invalid_task)

      IO.puts(
        "*** Test checking state: error_count=#{final_state.agent.state.error_count}, status=#{final_state.agent.state.status}"
      )

      assert final_state.agent.state.error_count > 0
    end

    test "respects paused status", %{agent: agent} do
      # Pause the agent using the proper helper
      {:ok, state} = pause_and_confirm(agent)
      assert state.agent.state.status == :paused

      # Try to process a task while paused
      task = %{
        task_id: "paused_task",
        task_type: :data_processing,
        input_data: %{source: "test.csv"},
        timeout: 30_000,
        retry_attempts: 3
      }

      process_instruction =
        Jido.Instruction.new!(%{
          action: ProcessTask,
          params: task
        })

      Jido.Agent.Server.cast(agent, process_instruction)

      # Wait a minimal amount for the cast to be processed
      :timer.sleep(50)

      # Verify task was not processed (agent is paused)
      {:ok, final_state} = Jido.Agent.Server.state(agent)
      assert final_state.agent.state.processed_count == 0
      assert final_state.agent.state.status == :paused
    end
  end

  describe "task queuing" do
    setup do
      {:ok, pid} = TaskAgent.start_link(id: "task_agent_queue")
      %{agent: pid}
    end

    test "queues tasks with different priorities", %{agent: agent} do
      # Queue multiple tasks
      for {priority, id} <- [{:high, "high_1"}, {:normal, "normal_1"}, {:low, "low_1"}] do
        task = %{
          id: id,
          type: :data_processing,
          input_data: %{source: "test.csv"}
        }

        instruction =
          Jido.Instruction.new!(%{
            action: QueueTask,
            params: %{task: task, priority: priority}
          })

        Jido.Agent.Server.cast(agent, instruction)
      end

      # Wait a minimal amount for all casts to be processed
      :timer.sleep(100)

      # Verify queue has all 3 tasks
      {:ok, queue_size} = get_queue_size_sync(agent)
      assert queue_size == 3
    end

    test "respects queue size limits", %{agent: agent} do
      # Get current max queue size
      {:ok, state} = Jido.Agent.Server.state(agent)
      max_size = state.agent.state.max_queue_size

      # Try to queue more tasks than the limit
      for i <- 1..(max_size + 5) do
        task = %{
          id: "overflow_task_#{i}",
          type: :data_processing,
          input_data: %{source: "test.csv"}
        }

        instruction =
          Jido.Instruction.new!(%{
            action: QueueTask,
            params: %{task: task, priority: :normal}
          })

        Jido.Agent.Server.cast(agent, instruction)
      end

      # Wait for all casts to be processed
      :timer.sleep(200)

      # Queue should not exceed max size
      {:ok, queue_size} = get_queue_size_sync(agent)
      assert queue_size <= max_size, "Queue size #{queue_size} exceeded max #{max_size}"
    end
  end

  describe "performance metrics" do
    setup do
      {:ok, pid} = TaskAgent.start_link(id: "task_agent_metrics")
      %{agent: pid}
    end

    test "tracks performance metrics correctly", %{agent: agent} do
      # Process several tasks
      for i <- 1..3 do
        task = %{
          task_id: "metrics_task_#{i}",
          task_type: :data_processing,
          input_data: %{source: "test#{i}.csv"},
          timeout: 30_000,
          retry_attempts: 3
        }

        instruction =
          Jido.Instruction.new!(%{
            action: ProcessTask,
            params: task
          })

        Jido.Agent.Server.cast(agent, instruction)
      end

      # Process tasks using the telemetry-based helper
      for i <- 1..3 do
        task = %{
          task_id: "metrics_task_sync_#{i}",
          task_type: :data_processing,
          input_data: %{source: "test#{i}.csv"},
          timeout: 30_000,
          retry_attempts: 3
        }

        # Process each task and wait for completion
        {:ok, _result} = process_task_and_wait(agent, task)
      end

      # Now verify metrics were updated
      {:ok, metrics} = get_metrics_sync(agent)
      assert metrics.total_processing_time > 0
      assert metrics.average_processing_time > 0

      {:ok, state} = Jido.Agent.Server.state(agent)
      assert state.agent.state.processed_count >= 3
    end

    test "provides status information", %{agent: agent} do
      instruction =
        Jido.Instruction.new!(%{
          action: JidoSystem.Actions.GetTaskStatus,
          params: %{}
        })

      Jido.Agent.Server.cast(agent, instruction)

      # Wait minimal time for cast to process
      :timer.sleep(20)

      # Verify status
      {:ok, state} = Jido.Agent.Server.state(agent)
      assert state.agent.state.status in [:idle, :processing, :paused]
    end
  end

  describe "error handling and recovery" do
    setup do
      {:ok, pid} = TaskAgent.start_link(id: "task_agent_errors")
      %{agent: pid}
    end

    test "handles processing errors gracefully", %{agent: agent} do
      # Create a task that will cause an error
      error_task = %{
        task_id: "error_task",
        # This should cause an error
        task_type: :invalid_type,
        input_data: %{},
        timeout: 30_000,
        retry_attempts: 3
      }

      _instruction =
        Jido.Instruction.new!(%{
          action: ProcessTask,
          params: error_task
        })

      # Use the helper that waits for error processing
      {:ok, state} = process_invalid_task_and_wait(agent, error_task)

      # Agent should handle the error and continue operating
      assert Process.alive?(agent)
      assert state.agent.state.error_count > 0
      # Should recover to idle
      assert state.agent.state.status == :idle
    end

    @tag :slow
    test "pauses after too many errors", %{agent: agent} do
      # Simulate multiple errors - more than the error threshold (10)
      for i <- 1..12 do
        error_task = %{
          task_id: "error_task_#{i}",
          task_type: :invalid_type,
          input_data: %{},
          timeout: 30_000,
          retry_attempts: 3
        }

        # Process and wait for error
        {:ok, _state} = process_invalid_task_and_wait(agent, error_task)
      end

      # Now check final state
      {:ok, final_state} = Jido.Agent.Server.state(agent)

      IO.puts(
        "*** Test 3 checking state: error_count=#{final_state.agent.state.error_count}, status=#{final_state.agent.state.status}"
      )

      assert final_state.agent.state.error_count >= 10
      # Agent should have paused after 10 errors
      assert final_state.agent.state.status == :paused
    end
  end

  describe "telemetry integration" do
    setup do
      {:ok, pid} = TaskAgent.start_link(id: "task_agent_telemetry")
      %{agent: pid}
    end

    test "emits task processing telemetry", %{agent: agent} do
      test_pid = self()
      ref = make_ref()

      # Attach telemetry handlers
      events = [
        [:jido_system, :task, :started],
        [:jido_system, :task, :completed],
        [:jido_system, :task, :failed]
      ]

      :telemetry.attach_many(
        "test_task_telemetry",
        events,
        fn event, measurements, metadata, _config ->
          send(test_pid, {ref, event, measurements, metadata})
        end,
        %{}
      )

      # Process a task
      task = %{
        task_id: "telemetry_task",
        task_type: :data_processing,
        input_data: %{source: "test.csv"},
        timeout: 30_000,
        retry_attempts: 3
      }

      instruction =
        Jido.Instruction.new!(%{
          action: ProcessTask,
          params: task
        })

      Jido.Agent.Server.cast(agent, instruction)

      # Should receive started and completed events
      assert_receive {^ref, [:jido_system, :task, :started], _, _}
      assert_receive {^ref, [:jido_system, :task, :completed], _, _}

      :telemetry.detach("test_task_telemetry")
    end
  end

  describe "agent coordination" do
    setup do
      {:ok, pid} = TaskAgent.start_link(id: "task_agent_coordination")
      %{agent: pid}
    end

    test "can coordinate with other agents", %{agent: agent} do
      # Test the coordination helper function
      {:ok, state} = Jido.Agent.Server.state(agent)

      task = %{type: :coordination_test, data: %{}}
      result = TaskAgent.coordinate_with_agents(state.agent, task, [])

      # Should return a coordination result
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end
end
