defmodule JidoSystem.Actions.GetPerformanceMetrics do
  @moduledoc """
  Action to get performance metrics from an agent.
  """
  
  use Jido.Action,
    name: "get_performance_metrics",
    description: "Get agent performance metrics",
    schema: [
      metric_type: [type: :atom, default: :all, doc: "Type of metrics to retrieve (:all, :summary, :detailed)"]
    ]
  
  @impl true
  def run(params, context) do
    # Get state directly from context, as that's what's passed by the agent
    state = Map.get(context, :state, %{})
    metrics = Map.get(state, :performance_metrics, %{})
    
    result = case params.metric_type do
      :summary ->
        %{
          total_processed: Map.get(state, :processed_count, 0),
          total_errors: Map.get(state, :error_count, 0),
          average_processing_time: Map.get(metrics, :average_processing_time, 0),
          success_rate: calculate_success_rate(state)
        }
        
      :detailed ->
        Map.merge(metrics, %{
          processed_count: Map.get(state, :processed_count, 0),
          error_count: Map.get(state, :error_count, 0),
          success_rate: calculate_success_rate(state),
          queue_size: queue_size(state),
          status: Map.get(state, :status, :unknown)
        })
        
      _ ->
        # :all - return everything
        %{
          summary: %{
            total_processed: Map.get(state, :processed_count, 0),
            total_errors: Map.get(state, :error_count, 0),
            average_processing_time: Map.get(metrics, :average_processing_time, 0),
            success_rate: calculate_success_rate(state)
          },
          detailed: metrics,
          current_state: %{
            status: Map.get(state, :status, :unknown),
            queue_size: queue_size(state),
            current_task: Map.get(state, :current_task)
          }
        }
    end
    
    {:ok, result}
  end
  
  defp calculate_success_rate(state) do
    processed = Map.get(state, :processed_count, 0)
    errors = Map.get(state, :error_count, 0)
    total = processed + errors
    
    if total > 0 do
      Float.round(processed / total * 100, 2)
    else
      100.0
    end
  end
  
  defp queue_size(state) do
    case Map.get(state, :task_queue) do
      queue when queue != nil -> 
        try do
          :queue.len(queue)
        rescue
          _ -> 0
        end
      _ -> 0
    end
  end
end