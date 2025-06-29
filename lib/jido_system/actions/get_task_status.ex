defmodule JidoSystem.Actions.GetTaskStatus do
  @moduledoc """
  Action to get the current task status from an agent.
  """

  use Jido.Action,
    name: "get_task_status",
    description: "Get current task processing status",
    schema: []

  @impl true
  def run(_params, context) do
    # Get state directly from context, as that's what's passed by the agent
    state = Map.get(context, :state, %{})

    {:ok,
     %{
       status: Map.get(state, :status, :unknown),
       current_task: Map.get(state, :current_task),
       processed_count: Map.get(state, :processed_count, 0),
       error_count: Map.get(state, :error_count, 0),
       queue_size: queue_size(state),
       uptime: calculate_uptime(state),
       performance_metrics: Map.get(state, :performance_metrics, %{})
     }}
  end

  defp queue_size(state) do
    case Map.get(state, :task_queue) do
      queue when queue != nil ->
        try do
          :queue.len(queue)
        rescue
          _ -> 0
        end

      _ ->
        0
    end
  end

  defp calculate_uptime(state) do
    case Map.get(state, :started_at) do
      %DateTime{} = started_at ->
        DateTime.diff(DateTime.utc_now(), started_at, :second)

      _ ->
        0
    end
  end
end
