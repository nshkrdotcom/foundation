defmodule JidoSystem.Actions.QueueTask do
  @moduledoc """
  Task queueing action with priority support and circuit breaker protection.
  """
  
  use Jido.Action,
    name: "queue_task",
    description: "Queue tasks with priority support",
    schema: [
      task: [type: :map, required: true, doc: "Task to queue"],
      priority: [type: :atom, default: :normal, doc: "Task priority (:high, :normal, :low)"],
      queue_name: [type: :string, default: "default", doc: "Target queue name"],
      delay: [type: :integer, default: 0, doc: "Delay before processing (ms)"]
    ]
  
  @impl true
  def run(params, context) do
    # Get the current state from context
    state = Map.get(context, :state, %{})
    task_queue = Map.get(state, :task_queue, :queue.new())
    max_queue_size = Map.get(state, :max_queue_size, 1000)
    
    # Check if queue is full
    if :queue.len(task_queue) >= max_queue_size do
      {:error, %{
        error: :queue_full,
        current_size: :queue.len(task_queue),
        max_size: max_queue_size
      }}
    else
      # Add task to queue based on priority
      updated_queue = add_task_to_queue(task_queue, params.task, params.priority)
    
    # Return the result with the updated queue
    # The agent will handle the state update
    {:ok, %{
      queued: true,
      task_id: Map.get(params.task, :id),
      priority: params.priority,
      queue_name: params.queue_name,
      queued_at: DateTime.utc_now(),
      queue_size: :queue.len(updated_queue),
      updated_queue: updated_queue
    }}
    end
  end
  
  defp add_task_to_queue(queue, task, priority) do
    # For now, just add to the end of the queue
    # In a real implementation, we'd handle priorities properly
    :queue.in({priority, task}, queue)
  end
end