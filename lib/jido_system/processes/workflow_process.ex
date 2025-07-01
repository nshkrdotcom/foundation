defmodule JidoSystem.Processes.WorkflowProcess do
  @moduledoc """
  GenServer process for managing a single workflow execution.
  
  This extracts workflow management from the monolithic CoordinatorAgent,
  following the OTP principle of one process per concurrent activity.
  Each workflow is isolated with its own state and lifecycle.
  """
  
  use GenServer
  require Logger
  
  defstruct [
    :id,
    :spec,
    :status,
    :current_task_index,
    :task_results,
    :assigned_agents,
    :started_at,
    :completed_at,
    :error
  ]
  
  # Client API
  
  def start_link(opts) do
    workflow_id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(workflow_id))
  end
  
  def execute_next_task(workflow_id) do
    GenServer.call(via_tuple(workflow_id), :execute_next_task)
  end
  
  def get_status(workflow_id) do
    GenServer.call(via_tuple(workflow_id), :get_status)
  end
  
  def get_info(pid) when is_pid(pid) do
    GenServer.call(pid, :get_info)
  end
  
  def get_id(pid) when is_pid(pid) do
    GenServer.call(pid, :get_id)
  end
  
  def cancel(workflow_id) do
    GenServer.call(via_tuple(workflow_id), :cancel)
  end
  
  # Server Implementation
  
  @impl true
  def init(opts) do
    workflow_id = Keyword.fetch!(opts, :id)
    workflow_spec = Keyword.fetch!(opts, :spec)
    
    state = %__MODULE__{
      id: workflow_id,
      spec: workflow_spec,
      status: :initialized,
      current_task_index: 0,
      task_results: [],
      assigned_agents: %{},
      started_at: System.system_time(:second),
      completed_at: nil,
      error: nil
    }
    
    Logger.info("WorkflowProcess #{workflow_id} initialized")
    
    # Start execution
    send(self(), :start_execution)
    
    {:ok, state}
  end
  
  @impl true
  def handle_call(:get_status, _from, state) do
    status = %{
      id: state.id,
      status: state.status,
      progress: calculate_progress(state),
      current_task: get_current_task(state),
      results: state.task_results,
      error: state.error
    }
    
    {:reply, {:ok, status}, state}
  end
  
  @impl true
  def handle_call(:get_info, _from, state) do
    info = Map.take(state, [:id, :status, :started_at])
    {:reply, {:ok, info}, state}
  end
  
  @impl true
  def handle_call(:get_id, _from, state) do
    {:reply, {:ok, state.id}, state}
  end
  
  @impl true
  def handle_call(:cancel, _from, state) do
    Logger.info("Cancelling workflow #{state.id}")
    
    new_state = %{state | 
      status: :cancelled,
      completed_at: System.system_time(:second)
    }
    
    # Could add cleanup logic here
    
    {:reply, :ok, new_state}
  end
  
  @impl true
  def handle_call(:execute_next_task, _from, state) do
    case execute_current_task(state) do
      {:ok, result, new_state} ->
        {:reply, {:ok, result}, new_state}
      {:error, reason, new_state} ->
        {:reply, {:error, reason}, new_state}
    end
  end
  
  @impl true
  def handle_info(:start_execution, state) do
    Logger.info("Starting execution of workflow #{state.id}")
    
    new_state = %{state | status: :running}
    
    # Schedule first task
    send(self(), :execute_task)
    
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(:execute_task, state) do
    case execute_current_task(state) do
      {:ok, _result, new_state} ->
        if workflow_complete?(new_state) do
          complete_state = %{new_state | 
            status: :completed,
            completed_at: System.system_time(:second)
          }
          
          Logger.info("Workflow #{state.id} completed successfully")
          {:noreply, complete_state}
        else
          # Schedule next task
          send(self(), :execute_task)
          {:noreply, new_state}
        end
        
      {:error, reason, new_state} ->
        error_state = %{new_state |
          status: :failed,
          error: reason,
          completed_at: System.system_time(:second)
        }
        
        Logger.error("Workflow #{state.id} failed: #{inspect(reason)}")
        {:noreply, error_state}
    end
  end
  
  # Private functions
  
  defp via_tuple(workflow_id) do
    {:via, Registry, {JidoSystem.WorkflowRegistry, workflow_id}}
  end
  
  defp execute_current_task(state) do
    current_task = get_current_task(state)
    
    if current_task do
      # In a real implementation, this would delegate to TaskDistributor
      # For now, simulate task execution
      Logger.info("Executing task #{current_task.action} for workflow #{state.id}")
      
      # Simulate task completion
      result = %{
        task: current_task,
        output: "simulated_result",
        executed_at: System.system_time(:second)
      }
      
      new_state = %{state |
        current_task_index: state.current_task_index + 1,
        task_results: state.task_results ++ [result]
      }
      
      {:ok, result, new_state}
    else
      {:error, :no_more_tasks, state}
    end
  end
  
  defp get_current_task(state) do
    Enum.at(state.spec.tasks, state.current_task_index)
  end
  
  defp workflow_complete?(state) do
    state.current_task_index >= length(state.spec.tasks)
  end
  
  defp calculate_progress(state) do
    total_tasks = length(state.spec.tasks)
    if total_tasks > 0 do
      (state.current_task_index / total_tasks) * 100
    else
      0
    end
  end
end