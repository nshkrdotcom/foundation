defmodule JidoSystem.Agents.PersistentFoundationAgent do
  @moduledoc """
  Enhanced FoundationAgent with automatic state persistence to ETS.

  This agent extends FoundationAgent to provide automatic persistence of
  critical state fields to ETS tables that survive process crashes.

  ## Usage

      defmodule MyAgent do
        use JidoSystem.Agents.PersistentFoundationAgent,
          name: "my_agent",
          description: "Agent with persistent state",
          actions: [MyApp.Actions.ProcessData],
          persistent_fields: [:active_workflows, :task_queue],
          schema: [
            status: [type: :atom, default: :idle],
            active_workflows: [type: :map, default: %{}],
            task_queue: [type: :any, default: :queue.new()]
          ]
      end
  """

  defmacro __using__(opts) do
    # Extract persistent fields configuration and remove from opts
    persistent_fields = Keyword.get(opts, :persistent_fields, [])
    clean_opts = Keyword.delete(opts, :persistent_fields)

    quote location: :keep do
      use JidoSystem.Agents.FoundationAgent, unquote(clean_opts)

      alias JidoSystem.Agents.StatePersistence
      require Logger

      @persistent_fields unquote(persistent_fields)

      # Override mount to restore persisted state
      def mount(server_state, opts) do
        # Call parent mount first
        {:ok, server_state} = super(server_state, opts)

        # Restore persisted state if available
        agent_id = server_state.agent.id

        if @persistent_fields != [] do
          Logger.info("Restoring persistent state for agent #{agent_id}")

          # Load persisted state based on agent type
          persisted_state = load_persisted_state(agent_id)

          # Merge persisted state into agent state
          updated_agent =
            update_in(server_state.agent.state, fn current_state ->
              Enum.reduce(@persistent_fields, current_state, fn field, acc ->
                if Map.has_key?(persisted_state, field) do
                  Map.put(acc, field, persisted_state[field])
                else
                  acc
                end
              end)
            end)

          {:ok, %{server_state | agent: updated_agent}}
        else
          {:ok, server_state}
        end
      end

      # Override on_after_run to persist state after each action
      def on_after_run(agent) do
        result = super(agent)

        # Persist critical state fields after successful run
        if @persistent_fields != [] do
          persist_state(agent)
        end

        result
      end

      # Helper to determine which persistence method to use
      defp load_persisted_state(agent_id) do
        cond do
          __MODULE__ == JidoSystem.Agents.CoordinatorAgent ->
            StatePersistence.load_coordinator_state(agent_id)

          __MODULE__ == JidoSystem.Agents.TaskAgent ->
            StatePersistence.load_task_state(agent_id)

          true ->
            # Generic agent - use coordinator table as default
            StatePersistence.load_coordinator_state(agent_id)
        end
      end

      defp persist_state(agent) do
        state_to_persist = Map.take(agent.state, @persistent_fields)

        cond do
          __MODULE__ == JidoSystem.Agents.CoordinatorAgent ->
            StatePersistence.save_coordinator_state(agent.id, state_to_persist)

          __MODULE__ == JidoSystem.Agents.TaskAgent ->
            StatePersistence.save_task_state(agent.id, state_to_persist)

          true ->
            # Generic agent - use coordinator table as default
            StatePersistence.save_coordinator_state(agent.id, state_to_persist)
        end
      end

      # Allow agents to override these if needed
      defoverridable mount: 2, on_after_run: 1, load_persisted_state: 1, persist_state: 1
    end
  end
end
