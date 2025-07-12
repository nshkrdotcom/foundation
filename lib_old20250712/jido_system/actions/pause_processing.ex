defmodule JidoSystem.Actions.PauseProcessing do
  @moduledoc """
  Action to pause task processing in an agent.
  """

  use Jido.Action,
    name: "pause_processing",
    description: "Pause task processing in the agent",
    schema: [
      reason: [type: :string, default: "Manual pause", doc: "Reason for pausing"]
    ]

  @impl true
  def run(params, context) do
    # Get state directly from context
    state = Map.get(context, :state, %{})
    previous_status = Map.get(state, :status)

    # Return result with StateModification directive to pause the agent
    status_directive = %Jido.Agent.Directive.StateModification{
      op: :set,
      path: [:status],
      value: :paused
    }

    {:ok,
     %{
       status: :paused,
       previous_status: previous_status,
       reason: params.reason,
       paused_at: DateTime.utc_now()
     }, status_directive}
  end
end
