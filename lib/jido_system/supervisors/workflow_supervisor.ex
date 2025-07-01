defmodule JidoSystem.Supervisors.WorkflowSupervisor do
  @moduledoc """
  DynamicSupervisor for managing individual workflow processes.
  
  Each workflow runs as its own isolated process, preventing cascading failures
  and enabling horizontal scaling. This follows OTP best practices by using
  a process-per-workflow pattern instead of storing all workflows in a single
  agent's state.
  """
  
  use DynamicSupervisor
  require Logger
  
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end
  
  @impl true
  def init(_opts) do
    Logger.info("Starting WorkflowSupervisor")
    
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 3,
      max_seconds: 5
    )
  end
  
  @doc """
  Starts a new workflow process under supervision.
  
  Returns {:ok, pid} or {:error, reason}.
  """
  def start_workflow(workflow_id, workflow_spec) do
    child_spec = %{
      id: {:workflow, workflow_id},
      start: {JidoSystem.Processes.WorkflowProcess, :start_link, [[
        id: workflow_id,
        spec: workflow_spec
      ]]},
      restart: :transient
    }
    
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end
  
  @doc """
  Stops a workflow process.
  """
  def stop_workflow(workflow_id) do
    case get_workflow_pid(workflow_id) do
      {:ok, pid} ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
      :error ->
        {:error, :not_found}
    end
  end
  
  @doc """
  Lists all active workflow processes.
  """
  def list_workflows do
    children = DynamicSupervisor.which_children(__MODULE__)
    
    Enum.map(children, fn {_, pid, _, _} ->
      case JidoSystem.Processes.WorkflowProcess.get_info(pid) do
        {:ok, info} -> info
        _ -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end
  
  @doc """
  Gets the pid for a specific workflow.
  """
  def get_workflow_pid(workflow_id) do
    children = DynamicSupervisor.which_children(__MODULE__)
    
    result = Enum.find(children, fn {_, pid, _, _} ->
      case JidoSystem.Processes.WorkflowProcess.get_id(pid) do
        {:ok, ^workflow_id} -> true
        _ -> false
      end
    end)
    
    case result do
      {_, pid, _, _} -> {:ok, pid}
      nil -> :error
    end
  end
end