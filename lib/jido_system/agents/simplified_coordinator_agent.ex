defmodule JidoSystem.Agents.SimplifiedCoordinatorAgent do
  @moduledoc """
  Simplified coordinator agent that delegates workflow management to dedicated processes.

  This agent now has a single responsibility: coordinating between clients and
  the workflow execution infrastructure. It no longer maintains workflow state
  internally, preventing data loss and enabling better scalability.

  ## Improvements over original CoordinatorAgent:
  - No volatile state storing active workflows
  - Delegates to WorkflowSupervisor for process management
  - Each workflow runs in its own supervised process
  - Crash of one workflow doesn't affect others
  - Horizontally scalable
  """

  use JidoSystem.Agents.FoundationAgent,
    name: "simplified_coordinator",
    description: "Lightweight coordinator that delegates to workflow processes",
    actions: [
      JidoSystem.Actions.StartWorkflow,
      JidoSystem.Actions.GetWorkflowStatus,
      JidoSystem.Actions.CancelWorkflow,
      JidoSystem.Actions.ListWorkflows
    ],
    schema: [
      status: [type: :atom, default: :ready],
      total_workflows_started: [type: :integer, default: 0]
    ]

  require Logger
  alias JidoSystem.Supervisors.WorkflowSupervisor
  alias JidoSystem.Processes.WorkflowProcess

  # Action implementations

  defmodule JidoSystem.Actions.StartWorkflow do
    use Jido.Action,
      name: "start_workflow",
      description: "Starts a new workflow process",
      schema: [
        workflow_spec: [type: :map, required: true]
      ]

    def run(context, params) do
      workflow_id = generate_workflow_id()
      workflow_spec = params.workflow_spec

      case WorkflowSupervisor.start_workflow(workflow_id, workflow_spec) do
        {:ok, pid} ->
          Logger.info("Started workflow #{workflow_id} with pid #{inspect(pid)}")

          # Update agent state
          new_agent = update_in(context.agent.state.total_workflows_started, &(&1 + 1))

          {:ok, %{workflow_id: workflow_id, pid: pid}, %{context | agent: new_agent}}

        {:error, reason} ->
          {:error, {:failed_to_start_workflow, reason}}
      end
    end

    defp generate_workflow_id do
      "workflow_#{System.unique_integer([:positive, :monotonic])}"
    end
  end

  defmodule JidoSystem.Actions.GetWorkflowStatus do
    use Jido.Action,
      name: "get_workflow_status",
      description: "Gets the status of a workflow",
      schema: [
        workflow_id: [type: :string, required: true]
      ]

    def run(_context, params) do
      case WorkflowProcess.get_status(params.workflow_id) do
        {:ok, status} -> {:ok, status}
        error -> {:error, error}
      end
    end
  end

  defmodule JidoSystem.Actions.CancelWorkflow do
    use Jido.Action,
      name: "cancel_workflow",
      description: "Cancels a running workflow",
      schema: [
        workflow_id: [type: :string, required: true]
      ]

    def run(_context, params) do
      case WorkflowProcess.cancel(params.workflow_id) do
        :ok -> {:ok, %{workflow_id: params.workflow_id, status: :cancelled}}
        error -> {:error, error}
      end
    end
  end

  defmodule JidoSystem.Actions.ListWorkflows do
    use Jido.Action,
      name: "list_workflows",
      description: "Lists all active workflows",
      schema: []

    def run(_context, _params) do
      workflows = WorkflowSupervisor.list_workflows()
      {:ok, %{workflows: workflows, count: length(workflows)}}
    end
  end
end
