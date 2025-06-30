defmodule JidoSystem.Agents.CoordinatorAgent do
  @moduledoc """
  Multi-agent coordination and orchestration with MABEAM integration.

  CoordinatorAgent manages complex workflows involving multiple agents, handles
  task distribution, monitors agent performance, and ensures coordinated execution
  across the Foundation infrastructure.

  ## Features
  - Multi-agent workflow orchestration
  - Dynamic task distribution and load balancing
  - Agent capability matching and selection
  - Workflow state management and recovery
  - Performance optimization and resource allocation
  - MABEAM integration for distributed coordination
  - Fault tolerance and automatic recovery

  ## Coordination Capabilities
  - Task decomposition and distribution
  - Agent selection based on capabilities
  - Workflow execution monitoring
  - Result aggregation and processing
  - Failure detection and recovery
  - Load balancing across agents
  - Performance metrics and optimization

  ## State Management
  The agent maintains:
  - `:coordination_status` - Current coordination state (:idle, :coordinating, :paused)
  - `:active_workflows` - Currently executing workflows
  - `:agent_pool` - Available agents and their capabilities
  - `:task_queue` - Pending coordination tasks
  - `:execution_metrics` - Performance and timing metrics
  - `:failure_recovery` - Error tracking and recovery strategies

  ## Usage

      # Start the coordinator agent
      {:ok, pid} = JidoSystem.Agents.CoordinatorAgent.start_link(id: "workflow_coordinator")

      # Register agents for coordination
      agents = [
        %{pid: task_agent_pid, capabilities: [:task_processing]},
        %{pid: monitor_agent_pid, capabilities: [:monitoring]}
      ]
      JidoSystem.Agents.CoordinatorAgent.cmd(pid, :register_agents, %{agents: agents})

      # Execute a coordinated workflow
      workflow = %{
        id: "data_processing_pipeline",
        tasks: [
          %{action: :validate_data, agent_capabilities: [:validation]},
          %{action: :process_data, agent_capabilities: [:task_processing]},
          %{action: :monitor_progress, agent_capabilities: [:monitoring]}
        ]
      }
      {:ok, execution_id} = JidoSystem.Agents.CoordinatorAgent.cmd(pid, :execute_workflow, workflow)

      # Monitor workflow progress
      {:ok, status} = JidoSystem.Agents.CoordinatorAgent.cmd(pid, :get_workflow_status, %{execution_id: execution_id})
  """

  use JidoSystem.Agents.FoundationAgent,
    name: "coordinator_agent",
    description: "Multi-agent coordination and orchestration with MABEAM integration",
    actions: [
      JidoSystem.Actions.MonitorWorkflow,
      JidoSystem.Actions.DistributeTask,
      JidoSystem.Actions.AggregateResults,
      JidoSystem.Actions.GetWorkflowStatus,
      JidoSystem.Actions.PauseWorkflow,
      JidoSystem.Actions.ResumeWorkflow,
      JidoSystem.Actions.CancelWorkflow,
      JidoSystem.Actions.OptimizeAllocation,
      JidoSystem.Actions.GetCoordinationMetrics
    ],
    schema: [
      coordination_status: [type: :atom, default: :idle],
      active_workflows: [type: :map, default: %{}],
      agent_pool: [type: :map, default: %{}],
      task_queue: [type: :any, default: :queue.new()],
      execution_metrics: [
        type: :map,
        default: %{
          total_workflows: 0,
          successful_workflows: 0,
          failed_workflows: 0,
          average_execution_time: 0,
          total_tasks_distributed: 0
        }
      ],
      failure_recovery: [
        type: :map,
        default: %{
          retry_attempts: %{},
          failed_agents: %{},
          recovery_strategies: []
        }
      ],
      max_concurrent_workflows: [type: :integer, default: 10],
      # 30 seconds
      task_timeout: [type: :integer, default: 30_000],
      # 1 minute
      agent_health_check_interval: [type: :integer, default: 60_000]
    ]

  require Logger
  alias JidoFoundation.Bridge
  alias JidoSystem.Actions.DistributeTask

  @impl true
  def mount(server_state, opts) do
    case super(server_state, opts) do
      {:ok, initialized_server_state} ->
        agent = initialized_server_state.agent
        Logger.info("CoordinatorAgent #{agent.id} mounted for multi-agent coordination")

        # Start periodic health checks
        schedule_agent_health_checks()

        # Start workflow monitoring
        schedule_workflow_monitoring()

        {:ok, initialized_server_state}
    end
  end

  @impl true
  def on_before_run(agent) do
    case super(agent) do
      {:ok, updated_agent} ->
        # Check coordination limits
        if map_size(agent.state.active_workflows) >= agent.state.max_concurrent_workflows do
          emit_event(
            agent,
            :workflow_limit_exceeded,
            %{
              active_workflows: map_size(agent.state.active_workflows),
              limit: agent.state.max_concurrent_workflows
            },
            %{}
          )

          {:error, {:workflow_limit_exceeded, "Maximum concurrent workflows exceeded"}}
        else
          {:ok, updated_agent}
        end
    end
  end

  # Action Handlers

  @spec handle_register_agents(Jido.Agent.t(), map()) :: 
    {:ok, map(), Jido.Agent.t()} | {:error, term()}
  def handle_register_agents(agent, %{agents: agents}) when is_list(agents) do
    try do
      # Validate and register each agent
      {successful, failed} =
        Enum.reduce(agents, {[], []}, fn agent_spec, {success, failures} ->
          case validate_and_register_agent(agent_spec) do
            {:ok, registered_agent} ->
              {[registered_agent | success], failures}

            {:error, reason} ->
              {success, [{agent_spec, reason} | failures]}
          end
        end)

      # Update agent pool
      new_pool =
        Enum.reduce(successful, agent.state.agent_pool, fn registered_agent, pool ->
          Map.put(pool, registered_agent.id, registered_agent)
        end)

      new_state = %{agent.state | agent_pool: new_pool}

      emit_event(
        agent,
        :agents_registered,
        %{
          successful_count: length(successful),
          failed_count: length(failed),
          total_pool_size: map_size(new_pool)
        },
        %{}
      )

      result = %{
        successful: successful,
        failed: failed,
        total_registered: map_size(new_pool)
      }

      {:ok, result, %{agent | state: new_state}}
    rescue
      e ->
        emit_event(agent, :agent_registration_error, %{}, %{error: inspect(e)})
        {:error, {:registration_error, e}}
    end
  end

  def handle_execute_workflow(agent, workflow) do
    try do
      execution_id = generate_execution_id()
      start_time = System.monotonic_time(:microsecond)

      # Validate workflow structure
      case validate_workflow(workflow) do
        :ok ->
          # Initialize workflow execution
          workflow_execution = %{
            id: execution_id,
            workflow: workflow,
            status: :initializing,
            start_time: start_time,
            tasks: %{},
            results: %{},
            current_step: 0,
            total_steps: length(workflow.tasks || []),
            assigned_agents: %{},
            created_at: DateTime.utc_now()
          }

          # Add to active workflows
          new_workflows = Map.put(agent.state.active_workflows, execution_id, workflow_execution)

          new_state = %{
            agent.state
            | active_workflows: new_workflows,
              execution_metrics: update_workflow_metrics(agent.state.execution_metrics, :started)
          }

          # Start workflow execution asynchronously
          send(self(), {:start_workflow_execution, execution_id})

          emit_event(
            agent,
            :workflow_started,
            %{
              execution_id: execution_id,
              task_count: workflow_execution.total_steps
            },
            %{workflow_id: workflow.id}
          )

          {:ok, %{execution_id: execution_id, status: :initializing}, %{agent | state: new_state}}

        {:error, reason} ->
          emit_event(agent, :workflow_validation_failed, %{}, %{
            workflow_id: Map.get(workflow, :id),
            reason: reason
          })

          {:error, {:validation_failed, reason}}
      end
    rescue
      e ->
        emit_event(agent, :workflow_execution_error, %{}, %{error: inspect(e)})
        {:error, {:execution_error, e}}
    end
  end

  def handle_distribute_task(agent, %{task: task, target_capabilities: capabilities}) do
    try do
      # Find suitable agents
      suitable_agents = find_agents_by_capabilities(agent.state.agent_pool, capabilities)

      case suitable_agents do
        [] ->
          emit_event(agent, :no_suitable_agents, %{}, %{
            required_capabilities: capabilities
          })

          {:error, {:no_suitable_agents, capabilities}}

        agents ->
          # Select best agent based on current load
          selected_agent = select_optimal_agent(agents)

          # Delegate task via MABEAM
          case Bridge.delegate_task(self(), selected_agent.pid, task) do
            :ok ->
              emit_event(
                agent,
                :task_distributed,
                %{
                  agent_id: selected_agent.id,
                  task_id: Map.get(task, :id)
                },
                %{}
              )

              # Update metrics
              new_metrics = update_task_metrics(agent.state.execution_metrics)
              new_state = %{agent.state | execution_metrics: new_metrics}

              {:ok,
               %{
                 agent_id: selected_agent.id,
                 result: :delegated
               }, %{agent | state: new_state}}

            {:error, reason} ->
              emit_event(agent, :task_distribution_failed, %{}, %{
                agent_id: selected_agent.id,
                task_id: Map.get(task, :id),
                reason: reason
              })

              # Try with next available agent or mark as failed
              handle_task_failure(agent, task, selected_agent, reason)
          end
      end
    rescue
      e ->
        emit_event(agent, :task_distribution_error, %{}, %{error: inspect(e)})
        {:error, {:distribution_error, e}}
    end
  end

  def handle_get_workflow_status(agent, %{execution_id: execution_id}) do
    case Map.get(agent.state.active_workflows, execution_id) do
      nil ->
        {:error, :workflow_not_found}

      workflow ->
        status = %{
          id: workflow.id,
          status: workflow.status,
          progress: calculate_progress(workflow),
          current_step: workflow.current_step,
          total_steps: workflow.total_steps,
          start_time: workflow.start_time,
          duration: System.monotonic_time(:microsecond) - workflow.start_time,
          assigned_agents: Map.keys(workflow.assigned_agents),
          results_count: map_size(workflow.results)
        }

        {:ok, status, agent}
    end
  end

  def handle_pause_workflow(agent, %{execution_id: execution_id}) do
    case Map.get(agent.state.active_workflows, execution_id) do
      nil ->
        {:error, :workflow_not_found}

      workflow ->
        updated_workflow = %{workflow | status: :paused, paused_at: DateTime.utc_now()}
        new_workflows = Map.put(agent.state.active_workflows, execution_id, updated_workflow)
        new_state = %{agent.state | active_workflows: new_workflows}

        emit_event(agent, :workflow_paused, %{}, %{execution_id: execution_id})

        {:ok, :paused, %{agent | state: new_state}}
    end
  end

  def handle_resume_workflow(agent, %{execution_id: execution_id}) do
    case Map.get(agent.state.active_workflows, execution_id) do
      nil ->
        {:error, :workflow_not_found}

      %{status: :paused} = workflow ->
        updated_workflow = %{workflow | status: :running, resumed_at: DateTime.utc_now()}
        new_workflows = Map.put(agent.state.active_workflows, execution_id, updated_workflow)
        new_state = %{agent.state | active_workflows: new_workflows}

        # Continue workflow execution
        send(self(), {:continue_workflow_execution, execution_id})

        emit_event(agent, :workflow_resumed, %{}, %{execution_id: execution_id})

        {:ok, :resumed, %{agent | state: new_state}}

      _ ->
        {:error, :workflow_not_paused}
    end
  end

  def handle_cancel_workflow(agent, %{execution_id: execution_id}) do
    case Map.get(agent.state.active_workflows, execution_id) do
      nil ->
        {:error, :workflow_not_found}

      workflow ->
        # Cancel any running tasks
        Enum.each(workflow.assigned_agents, fn {agent_id, _} ->
          case Map.get(agent.state.agent_pool, agent_id) do
            %{pid: pid} -> send(pid, {:cancel_task, execution_id})
            _ -> :ok
          end
        end)

        # Remove from active workflows
        new_workflows = Map.delete(agent.state.active_workflows, execution_id)
        new_metrics = update_workflow_metrics(agent.state.execution_metrics, :cancelled)
        new_state = %{agent.state | active_workflows: new_workflows, execution_metrics: new_metrics}

        emit_event(agent, :workflow_cancelled, %{}, %{execution_id: execution_id})

        {:ok, :cancelled, %{agent | state: new_state}}
    end
  end

  def handle_get_coordination_metrics(agent, _params) do
    metrics =
      Map.merge(agent.state.execution_metrics, %{
        active_workflows: map_size(agent.state.active_workflows),
        agent_pool_size: map_size(agent.state.agent_pool),
        queue_size: :queue.len(agent.state.task_queue),
        coordination_status: agent.state.coordination_status
      })

    {:ok, metrics, agent}
  end

  # Private helper functions

  defp schedule_agent_health_checks() do
    # 1 minute
    Process.send_after(self(), :check_agent_health, 60_000)
  end

  defp schedule_workflow_monitoring() do
    # 30 seconds
    Process.send_after(self(), :monitor_workflows, 30_000)
  end

  defp validate_and_register_agent(%{pid: pid, capabilities: capabilities} = agent_spec)
       when is_pid(pid) and is_list(capabilities) do
    # Check if agent is alive
    if Process.alive?(pid) do
      agent_id = Map.get(agent_spec, :id, "agent_#{inspect(pid)}")

      registered_agent = %{
        id: agent_id,
        pid: pid,
        capabilities: capabilities,
        status: :available,
        load: 0,
        registered_at: DateTime.utc_now(),
        last_health_check: DateTime.utc_now()
      }

      {:ok, registered_agent}
    else
      {:error, :agent_not_alive}
    end
  end

  defp validate_and_register_agent(_), do: {:error, :invalid_agent_spec}

  defp validate_workflow(%{tasks: tasks}) when is_list(tasks) and length(tasks) > 0 do
    # Basic workflow validation
    case Enum.all?(tasks, &validate_task/1) do
      true -> :ok
      false -> {:error, :invalid_task_structure}
    end
  end

  defp validate_workflow(_), do: {:error, :invalid_workflow_structure}

  defp validate_task(%{action: action}) when is_atom(action), do: true
  defp validate_task(_), do: false

  defp generate_execution_id() do
    "exec_#{System.unique_integer()}_#{DateTime.utc_now() |> DateTime.to_unix()}"
  end

  defp find_agents_by_capabilities(agent_pool, required_capabilities) do
    agent_pool
    |> Enum.filter(fn {_id, agent} ->
      agent.status == :available and
        Enum.all?(required_capabilities, &(&1 in agent.capabilities))
    end)
    |> Enum.map(fn {_id, agent} -> agent end)
  end

  defp select_optimal_agent(agents) do
    # Select agent with lowest current load
    agents
    |> Enum.min_by(& &1.load, fn -> hd(agents) end)
  end

  defp handle_task_failure(agent, task, failed_agent, reason) do
    # Update failure recovery tracking
    new_failure_recovery =
      update_failure_tracking(
        agent.state.failure_recovery,
        failed_agent.id,
        reason
      )

    new_state = %{agent.state | failure_recovery: new_failure_recovery}

    # Try to find alternative agent
    remaining_agents =
      find_agents_by_capabilities(
        agent.state.agent_pool,
        Map.get(task, :required_capabilities, [])
      )
      |> Enum.reject(&(&1.id == failed_agent.id))

    case remaining_agents do
      [] ->
        {:error, {:no_alternative_agents, reason}}

      alternatives ->
        alternative_agent = select_optimal_agent(alternatives)

        case Bridge.delegate_task(self(), alternative_agent.pid, task) do
          :ok ->
            emit_event(agent, :task_recovered, %{}, %{
              failed_agent: failed_agent.id,
              alternative_agent: alternative_agent.id,
              task_id: Map.get(task, :id)
            })

            {:ok, %{agent_id: alternative_agent.id, result: :recovered},
             %{agent | state: new_state}}

          {:error, new_reason} ->
            {:error, {:recovery_failed, new_reason}}
        end
    end
  end

  defp update_failure_tracking(failure_recovery, agent_id, _reason) do
    failed_agents = Map.update(failure_recovery.failed_agents, agent_id, 1, &(&1 + 1))
    %{failure_recovery | failed_agents: failed_agents}
  end

  defp update_workflow_metrics(metrics, event) do
    case event do
      :started ->
        %{metrics | total_workflows: metrics.total_workflows + 1}

      :completed ->
        %{metrics | successful_workflows: metrics.successful_workflows + 1}

      :failed ->
        %{metrics | failed_workflows: metrics.failed_workflows + 1}

      :cancelled ->
        %{metrics | failed_workflows: metrics.failed_workflows + 1}
    end
  end

  defp update_task_metrics(metrics) do
    %{metrics | total_tasks_distributed: metrics.total_tasks_distributed + 1}
  end

  defp calculate_progress(%{current_step: current, total_steps: total}) when total > 0 do
    current / total * 100
  end

  defp calculate_progress(_), do: 0

  # Handle periodic and workflow messages

  @impl true
  def handle_info({:start_workflow_execution, execution_id}, state) do
    case Map.get(state.agent.state.active_workflows, execution_id) do
      nil ->
        {:noreply, state}

      workflow ->
        # Start executing the first task
        updated_workflow = %{workflow | status: :running}
        new_workflows = Map.put(state.agent.state.active_workflows, execution_id, updated_workflow)
        new_agent_state = %{state.agent.state | active_workflows: new_workflows}
        new_agent = %{state.agent | state: new_agent_state}

        # Execute next task
        send(self(), {:execute_next_task, execution_id})

        {:noreply, %{state | agent: new_agent}}
    end
  end

  def handle_info({:execute_next_task, execution_id}, state) do
    case Map.get(state.agent.state.active_workflows, execution_id) do
      nil ->
        {:noreply, state}

      %{status: :running, current_step: step, workflow: %{tasks: tasks}} = _workflow
      when step < length(tasks) ->
        task = Enum.at(tasks, step)

        # Execute the task
        instruction =
          Jido.Instruction.new!(%{
            action: DistributeTask,
            params: %{
              task: task,
              target_capabilities: Map.get(task, :agent_capabilities, [])
            },
            context: %{execution_id: execution_id, task_index: step}
          })

        Jido.Agent.Server.cast(self(), instruction)

        {:noreply, state}

      %{current_step: step, total_steps: total} = workflow when step >= total ->
        # Workflow completed
        completed_workflow = %{
          workflow
          | status: :completed,
            completed_at: DateTime.utc_now(),
            total_duration: System.monotonic_time(:microsecond) - workflow.start_time
        }

        new_workflows =
          Map.put(state.agent.state.active_workflows, execution_id, completed_workflow)

        new_metrics = update_workflow_metrics(state.agent.state.execution_metrics, :completed)

        new_agent_state = %{
          state.agent.state
          | active_workflows: new_workflows,
            execution_metrics: new_metrics
        }

        new_agent = %{state.agent | state: new_agent_state}

        emit_event(
          state.agent,
          :workflow_completed,
          %{
            execution_id: execution_id,
            duration: completed_workflow.total_duration
          },
          %{}
        )

        {:noreply, %{state | agent: new_agent}}

      _ ->
        {:noreply, state}
    end
  end

  def handle_info({:continue_workflow_execution, execution_id}, state) do
    send(self(), {:execute_next_task, execution_id})
    {:noreply, state}
  end

  def handle_info(:check_agent_health, state) do
    # Check health of all registered agents
    dead_agents =
      state.agent.state.agent_pool
      |> Enum.filter(fn {_id, agent} -> not Process.alive?(agent.pid) end)
      |> Enum.map(fn {id, _agent} -> id end)

    if not Enum.empty?(dead_agents) do
      new_pool =
        Enum.reduce(dead_agents, state.agent.state.agent_pool, fn id, pool ->
          Map.delete(pool, id)
        end)

      new_agent_state = %{state.agent.state | agent_pool: new_pool}
      new_agent = %{state.agent | state: new_agent_state}

      emit_event(
        state.agent,
        :dead_agents_removed,
        %{
          removed_count: length(dead_agents),
          remaining_count: map_size(new_pool)
        },
        %{dead_agents: dead_agents}
      )

      schedule_agent_health_checks()
      {:noreply, %{state | agent: new_agent}}
    else
      schedule_agent_health_checks()
      {:noreply, state}
    end
  end

  def handle_info(:monitor_workflows, state) do
    # Check for stalled or timeout workflows
    current_time = System.monotonic_time(:microsecond)
    # 5 minutes in microseconds
    timeout_threshold = 300_000_000

    stalled_workflows =
      state.agent.state.active_workflows
      |> Enum.filter(fn {_id, workflow} ->
        workflow.status == :running and
          current_time - workflow.start_time > timeout_threshold
      end)

    if not Enum.empty?(stalled_workflows) do
      emit_event(
        state.agent,
        :stalled_workflows_detected,
        %{
          stalled_count: length(stalled_workflows)
        },
        %{}
      )
    end

    schedule_workflow_monitoring()
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.debug("CoordinatorAgent received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end
end
