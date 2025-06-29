defmodule JidoSystem.Agents.TaskAgent do
  @moduledoc """
  Specialized agent for task processing with Foundation infrastructure support.

  TaskAgent handles discrete units of work with built-in monitoring, error recovery,
  and integration with Foundation services. It's designed for high-throughput
  task processing scenarios.

  ## Features
  - Automatic task validation and preprocessing
  - Circuit breaker protection for external dependencies
  - Task queue management with priority support
  - Comprehensive telemetry and monitoring
  - Automatic retry with exponential backoff
  - Dead letter queue for failed tasks

  ## State Management
  The agent maintains:
  - `:status` - Current operational status (:idle, :processing, :paused, :error)
  - `:processed_count` - Total number of successfully processed tasks
  - `:error_count` - Total number of failed tasks
  - `:current_task` - Currently processing task (if any)
  - `:task_queue` - Priority queue of pending tasks
  - `:performance_metrics` - Processing time statistics

  ## Usage

      # Start the agent
      {:ok, pid} = JidoSystem.Agents.TaskAgent.start_link(id: "task_processor_1")

      # Process a task
      task = %{
        id: "task_123",
        type: :data_processing,
        payload: %{input: "data.csv", output: "processed.json"},
        priority: :high
      }

      JidoSystem.Agents.TaskAgent.cmd(pid, :process_task, task)

      # Get agent status
      {:ok, status} = JidoSystem.Agents.TaskAgent.cmd(pid, :get_status)

      # Pause/resume processing
      JidoSystem.Agents.TaskAgent.cmd(pid, :pause)
      JidoSystem.Agents.TaskAgent.cmd(pid, :resume)
  """

  use JidoSystem.Agents.FoundationAgent,
    name: "task_agent",
    description: "Processes tasks with Foundation infrastructure support",
    actions: [
      JidoSystem.Actions.ProcessTask,
      JidoSystem.Actions.ValidateTask,
      JidoSystem.Actions.QueueTask,
      JidoSystem.Actions.GetTaskStatus,
      JidoSystem.Actions.PauseProcessing,
      JidoSystem.Actions.ResumeProcessing,
      JidoSystem.Actions.GetPerformanceMetrics
    ],
    schema: [
      status: [type: :atom, default: :idle],
      processed_count: [type: :integer, default: 0],
      error_count: [type: :integer, default: 0],
      current_task: [type: :map, default: nil],
      task_queue: [type: :any, default: :queue.new()],
      performance_metrics: [
        type: :map,
        default: %{
          total_processing_time: 0,
          average_processing_time: 0,
          fastest_task: nil,
          slowest_task: nil
        }
      ],
      max_queue_size: [type: :integer, default: 1000],
      circuit_breaker_state: [type: :atom, default: :closed]
    ]

  require Logger
  alias JidoSystem.Actions.{ProcessTask, ValidateTask}

  @impl true
  def mount(server_state, opts) do
    case super(server_state, opts) do
      {:ok, initialized_server_state} ->
        agent = initialized_server_state.agent

        Logger.info(
          "TaskAgent #{agent.id} mounted with capabilities: #{inspect(get_default_capabilities())}"
        )

        # Schedule periodic queue processing
        schedule_queue_processing()

        {:ok, initialized_server_state}

      error ->
        error
    end
  end

  @impl true
  def on_before_run(agent) do
    case super(agent) do
      {:ok, updated_agent} ->
        # Check if agent is paused before running any task
        if agent.state.status == :paused do
          emit_event(agent, :task_processing_paused, %{}, %{
            reason: "Agent is paused"
          })

          {:error, {:agent_paused, "Task processing is currently paused"}}
        else
          # Update status to processing
          new_state = %{agent.state | status: :processing}
          {:ok, %{updated_agent | state: new_state}}
        end

      error ->
        error
    end
  end

  @impl true
  def on_after_run(agent, result, directives) do
    case super(agent, result, directives) do
      {:ok, updated_agent} ->
        # Update task-specific metrics based on result
        # Note: State modifications like queue updates and status changes are now handled by directives
        new_state =
          case result do
            %{status: :completed, duration: duration} = result_map ->
              # Handle ProcessTask successful result with metrics update
              new_metrics =
                update_performance_metrics(
                  updated_agent.state.performance_metrics,
                  duration,
                  result_map
                )

              %{
                updated_agent.state
                | status: :idle,
                  processed_count: updated_agent.state.processed_count + 1,
                  current_task: nil,
                  performance_metrics: new_metrics
              }

            %{status: :completed} ->
              # Handle ProcessTask without duration (fallback)
              %{
                updated_agent.state
                | status: :idle,
                  processed_count: updated_agent.state.processed_count + 1,
                  current_task: nil
              }

            %{queued: true} ->
              # Handle QueueTask result - directives handle queue update, just clear current_task
              %{updated_agent.state | current_task: nil}

            %{status: :paused} ->
              # Handle PauseProcessing result - directive handles status, just clear current_task
              %{updated_agent.state | current_task: nil}

            %{status: :idle} ->
              # Handle ResumeProcessing result - directive handles status, just clear current_task  
              %{updated_agent.state | current_task: nil}

            %{} ->
              # Generic success case
              %{
                updated_agent.state
                | status: :idle,
                  processed_count: updated_agent.state.processed_count + 1,
                  current_task: nil
              }

            error when is_atom(error) or is_tuple(error) or is_binary(error) ->
              %{
                agent.state
                | status: :idle,
                  error_count: agent.state.error_count + 1,
                  current_task: nil
              }

            _ ->
              # Catch-all for unexpected result formats
              Logger.debug(
                "TaskAgent received unexpected result format: #{inspect(result, limit: 50, printable_limit: 1000)}"
              )

              %{updated_agent.state | status: :idle, current_task: nil}
          end

        {:ok, %{updated_agent | state: new_state}}

      error ->
        error
    end
  end

  @impl true
  def on_error(agent, error) do
    case super(agent, error) do
      {:ok, updated_agent, directives} ->
        # Additional task-specific error handling
        # Don't increment error count for certain expected errors
        should_count_error =
          case error do
            {:agent_paused, _} -> false
            _ -> true
          end

        error_count =
          if should_count_error do
            updated_agent.state.error_count + 1
          else
            updated_agent.state.error_count
          end

        new_state = %{updated_agent.state | error_count: error_count, current_task: nil}

        # If we have too many errors, pause processing
        if new_state.error_count >= 10 and should_count_error do
          Logger.warning("TaskAgent #{agent.id} has too many errors, pausing")
          paused_state = %{new_state | status: :paused}
          {:ok, %{updated_agent | state: paused_state}, directives}
        else
          # Set status to idle after error handling
          final_state =
            if should_count_error do
              # Changed from :error to :idle
              %{new_state | status: :idle}
            else
              new_state
            end

          {:ok, %{updated_agent | state: final_state}, directives}
        end

      error ->
        error
    end
  end

  # Custom action implementations

  def handle_process_task(agent, task_params) do
    try do
      start_time = System.monotonic_time(:microsecond)

      # Create validate task instruction
      validate_instruction = Jido.Instruction.new!(%{
        action: ValidateTask,
        params: task_params
      })

      # Validate task using Jido.Exec for consistent execution
      case Jido.Exec.run(ValidateTask, task_params, %{}) do
        {:ok, validated_task} ->
          # Create process task instruction
          process_instruction = Jido.Instruction.new!(%{
            action: ProcessTask,
            params: validated_task
          })

          # Process the task using Jido.Exec for consistent execution
          result = case Jido.Exec.run(ProcessTask, validated_task, %{agent_id: agent.id}) do
            {:ok, task_result} -> task_result
            {:error, _} = error -> error
          end

          # Update performance metrics
          end_time = System.monotonic_time(:microsecond)
          processing_time = end_time - start_time

          new_metrics =
            update_performance_metrics(
              agent.state.performance_metrics,
              processing_time,
              validated_task
            )

          new_state = %{agent.state | performance_metrics: new_metrics}

          emit_event(
            agent,
            :task_completed,
            %{
              processing_time: processing_time,
              task_id: Map.get(validated_task, :id)
            },
            %{}
          )

          {:ok, result, %{agent | state: new_state}}

        {:error, reason} ->
          emit_event(agent, :task_validation_failed, %{}, %{reason: reason})
          {:error, {:validation_failed, reason}}
      end
    rescue
      e ->
        emit_event(agent, :task_processing_error, %{}, %{error: inspect(e)})
        {:error, {:processing_error, e}}
    end
  end

  def handle_queue_task(agent, task_params) do
    if :queue.len(agent.state.task_queue) >= agent.state.max_queue_size do
      emit_event(agent, :queue_full, %{queue_size: :queue.len(agent.state.task_queue)}, %{})
      {:error, :queue_full}
    else
      priority = Map.get(task_params, :priority, :normal)
      new_queue = enqueue_with_priority(agent.state.task_queue, task_params, priority)
      new_state = %{agent.state | task_queue: new_queue}

      emit_event(
        agent,
        :task_queued,
        %{
          queue_size: :queue.len(new_queue),
          priority: priority
        },
        %{task_id: Map.get(task_params, :id)}
      )

      {:ok, :queued, %{agent | state: new_state}}
    end
  end

  def handle_get_status(agent, _params) do
    status = %{
      status: agent.state.status,
      processed_count: agent.state.processed_count,
      error_count: agent.state.error_count,
      queue_size: :queue.len(agent.state.task_queue),
      current_task: agent.state.current_task,
      performance_metrics: agent.state.performance_metrics,
      circuit_breaker_state: agent.state.circuit_breaker_state,
      uptime: 0
    }

    {:ok, status, agent}
  end

  def handle_pause_processing(agent, params) do
    new_state = %{agent.state | status: :paused}
    emit_event(agent, :processing_paused, %{}, %{})

    {:ok,
     %{
       status: :paused,
       previous_status: agent.state.status,
       reason: Map.get(params, :reason, "Manual pause"),
       paused_at: DateTime.utc_now()
     }, %{agent | state: new_state}}
  end

  def handle_resume_processing(agent, _params) do
    new_state = %{agent.state | status: :idle}
    emit_event(agent, :processing_resumed, %{}, %{})

    # Process any queued tasks
    schedule_queue_processing()

    {:ok, :resumed, %{agent | state: new_state}}
  end

  # Private helper functions

  defp schedule_queue_processing() do
    Process.send_after(self(), :process_queue, 1000)
  end

  defp enqueue_with_priority(queue, task, :high) do
    # For simplicity, just add to front for high priority
    :queue.in_r(task, queue)
  end

  defp enqueue_with_priority(queue, task, _) do
    :queue.in(task, queue)
  end

  defp update_performance_metrics(metrics, processing_time, task) do
    new_total = metrics.total_processing_time + processing_time
    new_count = (metrics[:task_count] || 0) + 1
    new_average = div(new_total, new_count)

    fastest =
      case metrics.fastest_task do
        nil -> {processing_time, task}
        {time, _} when processing_time < time -> {processing_time, task}
        existing -> existing
      end

    slowest =
      case metrics.slowest_task do
        nil -> {processing_time, task}
        {time, _} when processing_time > time -> {processing_time, task}
        existing -> existing
      end

    %{
      total_processing_time: new_total,
      average_processing_time: new_average,
      task_count: new_count,
      fastest_task: fastest,
      slowest_task: slowest
    }
  end

  # Handle periodic queue processing
  @impl true
  def handle_info(:process_queue, state) do
    if state.agent.state.status == :idle and not :queue.is_empty(state.agent.state.task_queue) do
      case :queue.out(state.agent.state.task_queue) do
        {{:value, task}, new_queue} ->
          new_agent_state = %{state.agent.state | task_queue: new_queue}
          new_agent = %{state.agent | state: new_agent_state}

          # Process the task
          instruction =
            Jido.Instruction.new!(%{
              action: ProcessTask,
              params: task
            })

          # Let the agent process the instruction
          Jido.Agent.Server.cast(self(), instruction)

          {:noreply, %{state | agent: new_agent}}

        {:empty, _} ->
          {:noreply, state}
      end
    else
      # Re-schedule if still processing or paused
      if state.agent.state.status in [:processing, :paused] do
        schedule_queue_processing()
      end

      {:noreply, state}
    end
  end

  def handle_info(msg, state) do
    Logger.debug("TaskAgent received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end
end
