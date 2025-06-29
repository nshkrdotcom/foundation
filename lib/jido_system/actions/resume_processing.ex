defmodule JidoSystem.Actions.ResumeProcessing do
  @moduledoc """
  Action to resume task processing in an agent.
  """

  use Jido.Action,
    name: "resume_processing",
    description: "Resume task processing in the agent",
    schema: []

  @impl true
  def run(_params, context) do
    # Get state directly from context
    state = Map.get(context, :state, %{})
    previous_status = Map.get(state, :status)

    # Return the result indicating resume was requested
    {:ok,
     %{
       status: :idle,
       previous_status: previous_status,
       resumed_at: DateTime.utc_now()
     }}
  end
end
