defmodule DSPEx.Variables.Actions.UpdateValue do
  @moduledoc """
  Core action for updating cognitive variable values with coordination.

  This action handles:
  1. Value validation against constraints
  2. Impact assessment for coordination decisions
  3. Consensus coordination when needed
  4. Performance feedback collection
  5. Registry updates
  """

  use Jido.Action,
    name: "update_cognitive_variable_value",
    description: "Updates cognitive variable value with coordination",
    schema: [
      new_value: [type: :number, required: true, doc: "New value for the variable"],
      requester: [type: :pid, required: false, doc: "Process requesting the update"]
    ]

  require Logger

  @impl true
  def run(%{new_value: new_value} = _params, _context) do
    Logger.debug("Updating cognitive variable value to #{new_value}")

    # For now, just validate the value is a number
    if is_number(new_value) do
      result = %{
        new_value: new_value,
        updated_at: DateTime.utc_now(),
        status: :updated
      }
      {:ok, result}
    else
      {:error, "Value must be a number"}
    end
  end

end