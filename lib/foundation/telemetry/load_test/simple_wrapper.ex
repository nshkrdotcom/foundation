defmodule Foundation.Telemetry.LoadTest.SimpleWrapper do
  @moduledoc false

  use Foundation.Telemetry.LoadTest

  @impl true
  def scenarios do
    # Get the ETS table name from the process that called run_simple
    case Process.get(:simple_scenario_table) do
      nil ->
        # Fallback for testing
        [
          %{
            name: :simple_scenario,
            weight: 100,
            run: fn _ctx -> {:ok, :no_op} end,
            setup: nil,
            teardown: nil
          }
        ]

      table_name ->
        # Read the scenario function from ETS
        case :ets.lookup(table_name, :scenario_fun) do
          [{:scenario_fun, fun}] ->
            [
              %{
                name: :simple_scenario,
                weight: 100,
                run: fun,
                setup: nil,
                teardown: nil
              }
            ]

          [] ->
            # Table exists but no function stored
            [
              %{
                name: :simple_scenario,
                weight: 100,
                run: fn _ctx -> {:ok, :no_op} end,
                setup: nil,
                teardown: nil
              }
            ]
        end
    end
  end
end
