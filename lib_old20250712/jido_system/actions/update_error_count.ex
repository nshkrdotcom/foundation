defmodule JidoSystem.Actions.UpdateErrorCount do
  @moduledoc """
  Internal action to update the error count state in TaskAgent.

  This action is used internally by TaskAgent to persist error count
  changes that occur during error handling.
  """

  use Jido.Action,
    name: "update_error_count",
    description: "Update the agent's error count state through proper business logic flow",
    schema: [
      increment: [type: :integer, default: 1, doc: "Amount to increment error count by"]
    ]

  require Logger

  @impl true
  def run(params, _context) do
    increment = params.increment

    # Return increment instruction to be processed by TaskAgent.on_after_run
    # The actual error count calculation happens in the agent's business logic
    {:ok,
     %{
       error_count_increment: increment,
       status: :error_count_increment,
       updated_at: DateTime.utc_now()
     }}
  end
end
